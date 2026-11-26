local _, P = ...
local D = { present = {}, sample = "all" }
P.NameplatesAuraDraft = D
local NS, S, A = P.Suite, P.S, P.Suite.NameplateAuraColors
local KEYS = { "auraColorsEnabled", "auraColorsAll", "auraColorsNoneEnabled", "auraColorsNone",
    "auraColorsIndividual", "auraColorsData" }
local draft, watcher, cachedText, cachedData
local colorEpoch = 0

local function Current()
    return NS.DB, S.Config("nameplates")
end

local function Owns()
    if not draft then return false end
    local profile, config = Current()
    if profile ~= draft.profile or config ~= draft.config then return false end
    for _, key in ipairs(KEYS) do if config[key] ~= draft.base[key] then return false end end
    return true
end

function D.Get(key)
    if draft and not Owns() then draft = nil end
    if draft and draft.values[key] ~= nil then return draft.values[key] end
    return P.Get("nameplates", key)
end

function D.Pending() return draft ~= nil and Owns() end

function D.Discard()
    draft = nil
    if watcher then watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    P.Refresh()
end

local function Flush()
    if P.Combat() then return end
    local pending = draft
    local valid = Owns()
    draft = nil
    if pending and valid then P.SetMany("nameplates", pending.values) end
    if watcher then watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    P.Refresh()
end

function D.Set(key, value)
    if not P.Combat() then return P.Set("nameplates", key, value) end
    if not Owns() then
        local profile, config = Current()
        draft = { profile = profile, config = config, base = {}, values = {} }
        for _, field in ipairs(KEYS) do draft.base[field] = config[field] end
    end
    draft.values[key] = value
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", Flush)
    end
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    P.Refresh()
    return true
end

function D.Spec()
    local current = A.Spec()
    if D.current ~= current then D.selected, D.current = current, current end
    if not D.selected then D.selected = current end
    return D.selected
end

function D.Rows()
    local text = D.Get("auraColorsData")
    if cachedText ~= text then cachedText, cachedData = text, A.Decode(text) end
    return cachedData[D.Spec()] or {}
end

local function EditFor(spec, callback)
    if not spec then return false end
    local data = A.Decode(D.Get("auraColorsData"))
    data[spec] = data[spec] or {}
    if callback(data[spec]) == false then return false end
    return D.Set("auraColorsData", A.Encode(data))
end

function D.Edit(callback) return EditFor(D.Spec(), callback) end

-- A color popup can outlive a reorder or a spec selector change. Bind it
-- to an aura identity and profile epoch, never to a changing list index.
function D.BindColor(key, entry)
    local profile, config = Current()
    local epoch, selected, id = colorEpoch, D.Spec(), entry and entry.id
    local last = entry and entry.color or D.Get(key)
    local function Owned()
        local active, current = Current()
        return active == profile and current == config and epoch == colorEpoch
    end
    local function Find(rows)
        for _, row in ipairs(rows) do if row.id == id then return row end end
    end
    local function Get()
        if not Owned() then return last end
        if not id then return D.Get(key) end
        local row = Find(A.Decode(D.Get("auraColorsData"))[selected] or {})
        return row and row.color or last
    end
    local function Set(hex)
        if not Owned() or Get() ~= last then return false end
        if not id then
            last = hex
            return D.Set(key, hex)
        end
        return EditFor(selected, function(rows)
            local row = Find(rows)
            if not row then return false end
            row.color, last = hex, hex
        end)
    end
    return Get, Set
end

function D.Add(row)
    return D.Edit(function(rows)
        for _, entry in ipairs(rows) do if entry.id == row.id then return end end
        if #rows < A.LIMIT then
            row.enabled = true
            rows[#rows + 1] = row
        end
    end)
end

function D.ShowsFlameShockSetup()
    if not P.Suite.Client.isForever then return false end
    local _, class = UnitClass("player")
    return NS.Public(class) and class == "SHAMAN"
end

local FLAME_SHOCK = 8050
function D.CanTrackFlameShock()
    if P.Combat() or D.Pending() or P.Get("nameplates", "look") == 2 or not D.ShowsFlameShockSetup() then return false end
    local spec = D.Spec()
    if not spec or spec ~= A.Spec() then return false end
    local rows = D.Rows()
    if #rows < A.LIMIT then return true end
    for _, row in ipairs(rows) do if row.id == FLAME_SHOCK then return true end end
    return false
end

local function AddFlameRanks(row)
    local present = {}
    for _, id in ipairs(row.ids) do present[id] = true end
    for _, id in ipairs(NS.HostBridge.ForeverAuraAliases(FLAME_SHOCK) or {}) do
        if not present[id] then
            row.ids[#row.ids + 1] = id
            present[id] = true
        end
    end
end

function D.TrackFlameShock()
    if not D.CanTrackFlameShock() then return false end
    local spec = D.Spec()
    local data = A.Decode(D.Get("auraColorsData"))
    local rows = data[spec] or {}
    local flame, others
    for _, row in ipairs(rows) do
        if row.id == FLAME_SHOCK then
            flame = row
        elseif row.enabled ~= false then
            others = true
        end
    end
    local new = not flame
    if new then
        flame = { id = FLAME_SHOCK, ids = { FLAME_SHOCK }, color = A.DEFAULT_COLOR }
        rows[#rows + 1] = flame
    end
    AddFlameRanks(flame)
    flame.enabled = true
    data[spec] = rows
    local values = { auraColorsEnabled = true, auraColorsData = A.Encode(data) }
    if new and not others then values.auraColorsNoneEnabled = true end
    return P.SetMany("nameplates", values)
end

function D.Config()
    local out = {}
    for _, key in ipairs(KEYS) do out[key] = D.Get(key) end
    return out
end

function D.Color()
    if not D.Get("auraColorsEnabled") then return nil end
    local rows = D.Rows()
    if D.Spec() == A.Spec() then rows = A.Selected(rows)
    else
        local enabled = {}
        for _, row in ipairs(rows) do if row.enabled ~= false then enabled[#enabled + 1] = row end end
        rows = enabled
    end
    local present = {}
    for i, row in ipairs(rows) do
        present[row.id] = D.sample == "all" or D.sample == "partial" and i == 1
            or D.sample == "custom" and D.present[row.id] == true
    end
    return A.Preview(rows, present, D.Config())
end

function D.ResetColors()
    local data = A.Decode(D.Get("auraColorsData"))
    for _, row in ipairs(data[D.Spec()] or {}) do row.color = A.DEFAULT_COLOR end
    local values = { auraColorsAll = "48af97", auraColorsNone = "d9ab4b", auraColorsData = A.Encode(data) }
    if not P.Combat() then return P.SetMany("nameplates", values) end
    for key, value in pairs(values) do D.Set(key, value) end
end

NS.Registry.AddListener(D, function(_, domain)
    if domain ~= "profile" then return end
    draft, D.selected = nil, nil
    colorEpoch = colorEpoch + 1
    if watcher then watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end)
