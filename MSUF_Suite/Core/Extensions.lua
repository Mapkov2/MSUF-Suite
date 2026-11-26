local _, Suite = ...
-- Registered addons share Suite's presentation and profile entry points.
-- Each owns one ID and can withdraw the callbacks and data it published.
local API = { version = 1 }
local Extensions = {}
Suite.API.Extensions, Suite.Extensions = API, Extensions
local entries, order = {}, {}
local painting, hasTooltip = false, false
local MAX_ADDONS, MAX_SETTINGS = 32, 32
local BROKER_PREFIX = "MSUF."
local STATE_KEY = "extensions"

local function Key(value)
    return Suite.PublicText(value) and #value <= 48 and value:match("^[A-Za-z][A-Za-z0-9_%-]*$")
end

local function Text(value, limit)
    value = Suite.PublicText(value)
    if value and #value <= limit then return value end
end

local function RecountTooltipProviders()
    hasTooltip = false
    for _, entry in ipairs(order) do
        if entry.tooltip then hasTooltip = true return end
    end
end

local function ProfileSettings(id, create)
    local profile = Suite.DB
    if not profile or type(profile.suite) ~= "table" then return end
    local data = profile.suite
    local state = data.moduleState
    if type(state) ~= "table" then
        if not create then return end
        state = {}
        data.moduleState = state
    end
    local all = state[STATE_KEY]
    if type(all) ~= "table" then
        if not create then return end
        all = {}
        state[STATE_KEY] = all
    end
    local settings = all[id]
    if type(settings) ~= "table" and create then
        settings = {}
        all[id] = settings
    end
    if type(settings) == "table" then return settings end
end

local function Scalar(value)
    if not Suite.Public(value) then return false end
    local kind = type(value)
    return value == nil or kind == "boolean" or Suite.Finite(value) or Text(value, 240) ~= nil
end

local function SetSetting(entry, key, value)
    if painting or Suite.InCombat() or entries[entry.id] ~= entry or not Key(key) or not Scalar(value) then return false end
    local settings = ProfileSettings(entry.id, value ~= nil)
    if not settings then return value == nil end
    if value ~= nil and settings[key] == nil then
        local count = 0
        for _ in pairs(settings) do
            count = count + 1
            if count >= MAX_SETTINGS then return false end
        end
    end
    settings[key] = value
    return true
end

local function NotifyBroker(entry)
    local data = Suite.Suite.DataTextExtraSources
    if data and data.ExtensionChanged then data.ExtensionChanged(BROKER_PREFIX .. entry.id) end
end

local function Publish(entry, label, value, icon)
    if painting or entries[entry.id] ~= entry then return false end
    label, value = Text(label, 100), Text(value, 240)
    if not label or not value then return false end
    local texture = Text(icon, 240)
    if not texture and Suite.Finite(icon) and icon > 0 then texture = icon end
    local data = entry.dataText
    if data and data.label == label and data.text == value and data.icon == texture then return true end
    if not data then data = {} entry.dataText = data end
    data.label, data.text, data.icon = label, value, texture
    NotifyBroker(entry)
    return true
end

local function Unregister(entry)
    if painting or entries[entry.id] ~= entry then return false end
    entries[entry.id] = nil
    for index = 1, #order do
        if order[index] == entry then table.remove(order, index) break end
    end
    RecountTooltipProviders()
    if entry.dataText then NotifyBroker(entry) end
    return true
end

-- Use the addon's TOC directory as its ID. Pass a tooltip callback only when
-- it can return one public label/value pair for the supplied unit or ID.
function API.Register(id, tooltip)
    if painting or not Key(id) or entries[id] or #order >= MAX_ADDONS then return nil end
    if not Suite.Public(tooltip) or (tooltip ~= nil and type(tooltip) ~= "function") then return nil end
    local entry = { id = id, tooltip = tooltip }
    entries[id], order[#order + 1] = entry, entry
    if tooltip then hasTooltip = true end
    return {
        GetSetting = function(key)
            if entries[id] ~= entry or not Key(key) then return end
            local settings = ProfileSettings(id)
            local value = settings and settings[key]
            if Scalar(value) then return value end
        end,
        SetSetting = function(key, value) return SetSetting(entry, key, value) end,
        PublishDataText = function(label, value, icon) return Publish(entry, label, value, icon) end,
        RegisterProfile = function(label, revision, text)
            if painting or entries[id] ~= entry or not Text(label, 80) or label == "" then return false end
            if not Suite.Finite(revision) or revision < 1 or revision > 100000 or revision % 1 ~= 0 then return false end
            if entry.pack and entry.pack.revision >= revision then return false end
            if not Text(text, Suite.SuiteProfiles.maxBytes) or not text:match("^MSUFS[123]:") then return false end
            entry.pack = { id = id, label = label, revision = revision, text = text }
            return true
        end,
        Unregister = function() return Unregister(entry) end,
    }
end

function Extensions.TooltipLines(kind, identity, tooltip, add)
    if not hasTooltip or painting or Suite.InCombat() then return end
    if kind == "Unit" then
        if not Suite.PublicText(identity) then return end
    elseif not Suite.Finite(identity) then return end
    painting = true
    for _, entry in ipairs(order) do
        if entry.tooltip then
            local ok, label, value = Suite.Dispatch(Suite.Finish, entry.tooltip, kind, identity)
            if not ok then
                entry.tooltip = nil
                RecountTooltipProviders()
            elseif Text(label, 100) and label ~= "" and Text(value, 240) then
                Suite.Dispatch(add, tooltip, label, value, .85, .85, .85)
            end
        end
    end
    painting = false
end

function Extensions.Broker(name)
    if not Suite.PublicText(name) then return nil, false end
    local id = name:match("^MSUF%.(.+)$")
    local entry = id and entries[id]
    return entry and entry.dataText or nil, entry ~= nil
end

function Extensions.AddBrokers(names)
    local seen = {}
    for _, name in ipairs(names) do seen[name] = true end
    for _, entry in ipairs(order) do
        local name = BROKER_PREFIX .. entry.id
        if #names >= 256 then break end
        if entry.dataText and not seen[name] then names[#names + 1] = name end
    end
end

function Extensions.ProfilePacks()
    local packs = {}
    for _, entry in ipairs(order) do
        local pack = entry.pack
        if pack then packs[#packs + 1] = { id = pack.id, label = pack.label, revision = pack.revision } end
    end
    table.sort(packs, function(a, b)
        if a.label == b.label then return a.id < b.id end
        return a.label < b.label
    end)
    return packs
end

function Extensions.ImportProfile(id, revision, name)
    if Suite.InCombat() or not Key(id) then return false end
    local entry = entries[id]
    local pack = entry and entry.pack
    if not pack or pack.revision ~= revision then return false, "The registered profile changed. Reopen this page." end
    return Suite.SuiteProfiles.Import(name, pack.text)
end
