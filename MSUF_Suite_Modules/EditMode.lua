local _, P = ...
local NS, S = P.NS, P.Suite
-- Suite frames join MSUF Edit Mode through its public API (identical in the
-- Main and Classic MSUF builds). Each element moves a frame the suite owns;
-- positions are ordinary module settings, so undo, discard and profiles work
-- through the normal Set/SetMany path.
local owners, sessionAPI = {}, nil
local profile, epoch = nil, 0
local EMPTY = {}

-- Captured states belong to one profile. A profile switch invalidates them.
local function Epoch()
    if profile ~= NS.DB then
        profile = NS.DB
        epoch = epoch + 1
    end
    return epoch
end

local function Finite(value)
    return S.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function API()
    local api = _G.MSUF_EditModeAPI
    if type(api) == "table" and type(api.RegisterElement) == "function" then return api end
end

local function OwnerName(id)
    return "MSUFSuite." .. id
end

-- MSUF's own Blizzard adapter can register the same Blizzard surface a suite
-- module now owns (Minimap, Blizzard's damage meter). While a suite owner
-- claims its key, that record reports disabled. Records are looked up at call
-- time by MSUF, so wrapping isEnabled needs no MSUF change; re-created records
-- are wrapped again at the next session start.
local suppressed, wrapped = {}, setmetatable({}, { __mode = "k" })
local function WrapSuppressed()
    local em = _G.MSUF_EM2
    local external = em and em.ExternalElements
    if type(external) ~= "table" or type(external.GetRecord) ~= "function" then return end
    for key in pairs(suppressed) do
        local record = external.GetRecord(key)
        if type(record) == "table" and not wrapped[record] then
            local original = record.isEnabled
            wrapped[record] = true
            record.isEnabled = function(...)
                if next(suppressed[key] or EMPTY) then return false end
                if type(original) == "function" then return original(...) end
                return true
            end
        end
    end
end

function S.SuppressHostElement(owner, key, claim)
    suppressed[key] = suppressed[key] or {}
    suppressed[key][owner] = claim and true or nil
    if claim then WrapSuppressed() end
end

local function SessionChanged(active)
    if active then WrapSuppressed() end
    S.SetEditMode(active)
end

-- The any-edit-mode listener covers MSUF's own preview, including suspension
-- by another edit mode. It has no removal API; the closure is inert once no
-- suite module is active.
local anyListener = false
local function EnsureSession(api)
    if not anyListener and type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
        anyListener = true
        _G.MSUF_RegisterAnyEditModeListener(function(active) SessionChanged(active == true) end)
    elseif not anyListener and sessionAPI ~= api and type(api.RegisterSessionListener) == "function" then
        api.RegisterSessionListener("MSUFSuite", SessionChanged)
        sessionAPI = api
    end
    if api.IsActive and api.IsActive() then SessionChanged(true) end
end

-- Positions are offsets of spec.point against the same point of UIParent, in
-- the frame's own scale. Preview drags move the frame; commits write settings.
local function Place(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
end

local function ValidState(state)
    return type(state) == "table" and state.epoch == Epoch() and not NS.IsCombatLocked()
        and type(state.values) == "table"
end

local function Element(id, elementID, spec)
    local function Frame()
        local frame = spec.getFrame()
        if frame and not NS.Safety.IsForbidden(frame) then return frame end
    end
    local function Scale()
        local frame = Frame()
        local scale = frame and frame:GetScale()
        return Finite(scale) and scale > 0 and scale or 1
    end
    local function Point()
        return type(spec.point) == "function" and spec.point() or spec.point or "CENTER"
    end
    return {
        id = elementID,
        label = S.Text(spec.label),
        group = "MSUF Suite",
        order = spec.order or 1000,
        getFrame = Frame,
        isEnabled = function()
            return S.states[id].active and (not spec.isEnabled or spec.isEnabled()) and Frame() ~= nil
        end,
        captureState = function()
            local config = S.Config(id)
            local values = { [spec.xKey] = config[spec.xKey], [spec.yKey] = config[spec.yKey] }
            if spec.pointKey then values[spec.pointKey] = config[spec.pointKey] end
            for _, key in ipairs(spec.historyKeys or EMPTY) do values[key] = config[key] end
            return { epoch = Epoch(), values = values }
        end,
        restoreState = function(state)
            if not ValidState(state) then return false end
            return S.SetMany(id, state.values)
        end,
        movePosition = function(request)
            local state = request and request.state
            if not ValidState(state) then return false end
            local scale = Scale()
            local x = state.values[spec.xKey] + (request.deltaX or 0) / scale
            local y = state.values[spec.yKey] + (request.deltaY or 0) / scale
            if not Finite(x) or not Finite(y) then return false end
            if request.phase ~= "commit" then
                -- Elements whose x/y are not UIParent offsets place themselves.
                if spec.place then return spec.place(x, y) == true end
                local frame = Frame()
                if not frame then return false end
                Place(frame, Point(), x, y)
                return true
            end
            local values = {
                [spec.xKey] = math.floor(x * 10 + 0.5) / 10,
                [spec.yKey] = math.floor(y * 10 + 0.5) / 10,
            }
            for key, value in pairs(spec.moveValues or EMPTY) do values[key] = value end
            return S.SetMany(id, values)
        end,
        resetPosition = function()
            local rules = S.catalog[id].rules
            local values = { [spec.xKey] = rules[spec.xKey].default, [spec.yKey] = rules[spec.yKey].default }
            if spec.pointKey then values[spec.pointKey] = rules[spec.pointKey].default end
            for _, key in ipairs(spec.resetKeys or EMPTY) do values[key] = rules[key].default end
            return S.SetMany(id, values)
        end,
        extraControls = spec.extraControls,
        openSettings = function()
            S.Open(id)
            return true
        end,
    }
end

-- spec: label, getFrame(), xKey, yKey, point (string or function), pointKey,
-- isEnabled(), order, extraControls, historyKeys, moveValues, resetKeys,
-- place(x, y) (drag preview for x/y that are not UIParent offsets).
-- Returns true when MSUF Edit Mode accepted the element.
function S.RegisterOwnedMover(id, elementID, spec)
    local api = API()
    if not api or not S.catalog[id] then return false end
    owners[id] = owners[id] or {}
    if owners[id][elementID] then return true end
    local ok = api.RegisterElement(OwnerName(id), Element(id, elementID, spec)) == true
    if ok then
        owners[id][elementID] = true
        EnsureSession(api)
    end
    return ok
end

function S.RefreshOwnedMovers(id)
    local api = API()
    if api and owners[id] and api.RefreshOwner then api.RefreshOwner(OwnerName(id)) end
end

function S.UnregisterEditElements(id)
    local api = API()
    if owners[id] and api and api.UnregisterOwner then api.UnregisterOwner(OwnerName(id)) end
    owners[id] = nil
    if not next(owners) and sessionAPI then
        if sessionAPI.UnregisterSessionListener then sessionAPI.UnregisterSessionListener("MSUFSuite") end
        sessionAPI = nil
    end
end

-- Opens MSUF Edit Mode, preferably with the given element selected.
function S.OpenEditMode(id, elementID)
    if NS.IsCombatLocked() then return false end
    local api = API()
    if api and id and owners[id] and api.EnterEditMode then
        if elementID and owners[id][elementID] and api.EnterEditMode(OwnerName(id), elementID) then return true end
        for owned in pairs(owners[id]) do
            if api.EnterEditMode(OwnerName(id), owned) then return true end
        end
    end
    local em = _G.MSUF_EM2
    if em and em.State and type(em.State.Enter) == "function" then
        em.State.Enter("player")
        return true
    end
    return false
end

-- Edit Mode previews are cold transitions: modules re-apply so hidden or
-- faded surfaces become visible for placement outside combat.
function S.SetEditMode(active)
    active = active == true
    if S.editMode == active then return end
    S.editMode = active
    for id in pairs(owners) do
        if S.states[id].active then S.Apply(id) end
    end
end

function S.RefreshEditMover(id)
    local instance = S.instances[id]
    if S.states[id] and S.states[id].active and instance and instance.RegisterMovers then
        instance:RegisterMovers()
    end
end
