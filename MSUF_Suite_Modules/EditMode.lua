local _, P = ...
local NS, S = P.NS, P.Suite
-- Suite frames join MSUF Edit Mode through its public API (identical in the
-- Main and Classic MSUF builds). Each element moves a frame the suite owns;
-- positions are ordinary module settings, so undo, discard and profiles work
-- through the normal Set/SetMany path.
local owners, sessionAPI = {}, nil
local profile, epoch = nil, 0
local EMPTY = {}
local SIZE_LABELS = { width = "Width", height = "Height", scale = "Scale %" }

-- Captured states belong to one profile. A profile switch invalidates them.
local function Epoch()
    if profile ~= NS.DB then
        profile = NS.DB
        epoch = epoch + 1
    end
    return epoch
end

local Finite = S.Finite

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

-- MSUF's external popup shows X/Y in its summary; owner controls make them
-- editable. Every Suite mover with numeric profile coordinates gets fields. A
-- native bag window starts at Blizzard's live position until first moved.
local function PositionValues(id, spec)
    local config = S.Config(id)
    local values = { [spec.xKey] = config[spec.xKey], [spec.yKey] = config[spec.yKey] }
    if spec.capture then spec.capture(values) end
    return values
end

local function SetPositionValue(id, spec, key, value)
    if not spec.moveValues then return S.Set(id, key, value) end
    local values = PositionValues(id, spec)
    values[key] = value
    for flag, enabled in pairs(spec.moveValues) do values[flag] = enabled end
    return S.SetMany(id, values)
end

local function PopupControls(id, spec)
    if spec.quickPosition == false then return spec.extraControls end
    local controls, rules = {}, S.catalog[id].rules
    for _, axis in ipairs({ { spec.xKey, "X" }, { spec.yKey, "Y" } }) do
        local key, label = axis[1], axis[2]
        local rule = rules[key]
        if rule and rule.min and rule.max then
            controls[#controls + 1] = {
                id = key, label = label, kind = "number", min = rule.min, max = rule.max, step = 1,
                get = function() return PositionValues(id, spec)[key] end,
                set = function(value) return SetPositionValue(id, spec, key, value) end,
            }
        end
    end
    for _, control in ipairs(spec.extraControls or EMPTY) do controls[#controls + 1] = control end
    -- Numeric sizing uses the existing external popup API; that API has no drag-resize contract.
    for _, key in ipairs(spec.sizeKeys or EMPTY) do
        local label = SIZE_LABELS[key]
        local rule, exists = rules[key], false
        for _, control in ipairs(controls) do
            if control.id == key then
                exists = true
                break
            end
        end
        if not exists and rule and rule.min and rule.max then
            controls[#controls + 1] = { id = key, label = S.Text(label or rule.label or key), kind = "number",
                min = rule.min, max = rule.max, step = rule.step or 1,
                get = function() return S.Config(id)[key] end,
                set = function(value) return S.Set(id, key, value) end }
        end
    end
    return controls
end

local function CaptureKeys(spec)
    local keys, seen = {}, {}
    for _, list in ipairs({spec.historyKeys or EMPTY, spec.sizeKeys or EMPTY}) do
        for _, key in ipairs(list) do
            if not seen[key] then
                keys[#keys+1]=key
                seen[key]=true
            end
        end
    end
    return keys
end

local function ResetPosition(id, spec)
    local rules = S.catalog[id].rules
    local values = { [spec.xKey] = rules[spec.xKey].default, [spec.yKey] = rules[spec.yKey].default }
    if spec.pointKey then values[spec.pointKey] = rules[spec.pointKey].default end
    for _, key in ipairs(spec.resetKeys or EMPTY) do values[key] = rules[key].default end
    return S.SetMany(id, values)
end

-- The element's frame (spec.getFrame) while it is accessible, its scale
-- and the anchor point its x/y offsets use.
local function SpecFrame(spec)
    local frame = spec.getFrame()
    if frame and not NS.Safety.IsForbidden(frame) then return frame end
end

local function SpecScale(spec)
    local frame = SpecFrame(spec)
    local scale = frame and frame:GetScale()
    return Finite(scale) and scale > 0 and scale or 1
end

local function SpecPoint(spec)
    return type(spec.point) == "function" and spec.point() or spec.point or "CENTER"
end

-- The saved values an undo restores (position and captureKeys).
local function CaptureState(id, spec, captureKeys)
    local config = S.Config(id)
    local values = { [spec.xKey] = config[spec.xKey], [spec.yKey] = config[spec.yKey] }
    if spec.pointKey then values[spec.pointKey] = config[spec.pointKey] end
    for _, key in ipairs(captureKeys) do values[key] = config[key] end
    local state = { epoch = Epoch(), values = values }
    -- A module may start a drag from its live position (Bags: Blizzard's
    -- anchor while the bag never moved). Undo still restores the saved
    -- values, so a native anchor never reaches the profile.
    if spec.capture then
        local origin = { [spec.xKey] = values[spec.xKey], [spec.yKey] = values[spec.yKey] }
        spec.capture(origin)
        state.origin = origin
    end
    return state
end

-- A drag preview moves the frame; the commit writes the settings.
local function MovePosition(id, spec, request)
    local state = request and request.state
    if not ValidState(state) then return false end
    local scale = SpecScale(spec)
    local origin = state.origin or state.values
    local x = origin[spec.xKey] + (request.deltaX or 0) / scale
    local y = origin[spec.yKey] + (request.deltaY or 0) / scale
    if not Finite(x) or not Finite(y) then return false end
    if request.phase ~= "commit" then
        -- Elements whose x/y are not UIParent offsets place themselves.
        if spec.place then return spec.place(x, y) == true end
        local frame = SpecFrame(spec)
        if not frame then return false end
        Place(frame, SpecPoint(spec), x, y)
        return true
    end
    local values = {
        [spec.xKey] = math.floor(x * 10 + 0.5) / 10,
        [spec.yKey] = math.floor(y * 10 + 0.5) / 10,
    }
    for key, value in pairs(spec.moveValues or EMPTY) do values[key] = value end
    -- MSUF Edit Mode also commits a drag still held when combat starts.
    return S.CommitEditPosition(id, values)
end

local function Element(id, elementID, spec)
    local captureKeys = CaptureKeys(spec)
    local function Frame() return SpecFrame(spec) end
    return {
        id = elementID,
        label = S.Text(spec.label),
        group = "MSUF Suite",
        centerPopup = spec.centerPopup == true,
        order = spec.order or 1000,
        getFrame = Frame,
        isEnabled = function()
            return S.states[id].active and (not spec.isEnabled or spec.isEnabled())
                and (not spec.visible or spec.visible()) and Frame() ~= nil
        end,
        captureState = function() return CaptureState(id, spec, captureKeys) end,
        restoreState = function(state)
            if not ValidState(state) then return false end
            return S.CommitEditPosition(id, state.values)
        end,
        movePosition = function(request) return MovePosition(id, spec, request) end,
        resetPosition = function() return ResetPosition(id, spec) end,
        extraControls = PopupControls(id, spec),
        openSettings = function()
            return S.Open(id)
        end,
    }
end

-- spec: label, getFrame(), xKey, yKey, point (string or function), pointKey,
-- isEnabled(), visible(), order, quickPosition=false opt-out, extraControls, historyKeys,
-- sizeKeys (explicit catalog dimensions for this element), moveValues, resetKeys,
-- place(x, y) (drag preview for x/y that are not UIParent offsets),
-- capture(origin) (live drag start x/y; undo keeps the saved values).
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
        if S.states[id].active then
            local instance=S.instances and S.instances[id]
            -- Own sample frames can hide immediately even when Apply must wait for combat.
            if not active and instance and instance.HideEditPreview then S.Dispatch(instance.HideEditPreview,instance) end
            S.Apply(id)
        end
    end
end

-- The controller calls this right after the module started or refreshed.
function S.RefreshEditMover(id)
    local instance = S.instances[id]
    if instance.RegisterMovers then instance:RegisterMovers() end
end
