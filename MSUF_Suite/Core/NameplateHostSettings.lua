local _, Suite = ...
local Settings = {}
Suite.NameplateHostSettings = Settings
local IsSecret = Suite.IsSecret

-- Portable settings are restricted to the two owners that draw nameplate text
-- and interrupt readiness. A missing section leaves that owner unchanged.
local SCHEMA = {
    general = {
        kickReadyShowNameplates = { "boolean" },
        kickReadyStyle = { "enum", { border = true, box = true, fill = true } },
        kickReadyAutoSize = { "boolean" },
        kickReadySize = { "number", 8, 80 },
        kickReadyAnchor = { "enum", { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true,
            TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true, CENTER = true } },
        kickReadyOffsetX = { "number", -2000, 2000 },
        kickReadyOffsetY = { "number", -2000, 2000 },
        kickReadyTimeMarker = { "boolean" },
        kickReadyTimeSegment = { "boolean" },
        kickReadyColor = { "color" },
        kickNotReadyColor = { "color" },
        castbarOutlineThickness = { "number", 0, 12 },
        castbarTexture = { "string", 256 },
        castbarInterruptibleColor = { "string", 128 },
        castbarNonInterruptibleColor = { "string", 128 },
        castbarInterruptUnavailableColor = { "string", 128 },
        castbarInterruptibleR = { "number", 0, 1 },
        castbarInterruptibleG = { "number", 0, 1 },
        castbarInterruptibleB = { "number", 0, 1 },
        castbarNonInterruptibleR = { "number", 0, 1 },
        castbarNonInterruptibleG = { "number", 0, 1 },
        castbarNonInterruptibleB = { "number", 0, 1 },
        castbarInterruptUnavailableR = { "number", 0, 1 },
        castbarInterruptUnavailableG = { "number", 0, 1 },
        castbarInterruptUnavailableB = { "number", 0, 1 },
    },
    nameplates = {
        fontOverride = { "boolean" },
        fontKey = { "string", 256 },
        fontSize = { "number", 1, 200 },
        nameFontSize = { "number", 1, 200 },
        noOutline = { "boolean" },
        boldText = { "boolean" },
        fontMonochrome = { "boolean" },
        fontSlug = { "boolean" },
        textBackdrop = { "boolean" },
        fontShadowOpacity = { "number", 0.2, 1 },
        fontShadowDistance = { "number", 1, 2 },
        fontShadowStrength = { "enum", { SOFT = true, NORMAL = true, DEEP = true } },
        fontTextAlpha = { "number", 0.7, 1 },
        fontBaselineOffset = { "number", -4, 4 },
        nameFormat = { "enum", { FULL = true, CUT = true, ABBREV = true, ABBREV_CUT = true } },
        shortenNames = { "boolean" },
        shortenNameClipSide = { "enum", { LEFT = true, RIGHT = true } },
        shortenNameMaxChars = { "number", 4, 40 },
        shortenNameShowDots = { "boolean" },
        nameColorMode = { "enum", { DEFAULT = true, CLASS = true, CUSTOM = true } },
        nameClassColor = { "boolean" },
        npcNameRed = { "boolean" },
        nameNpcClassColor = { "boolean" },
        nameColorR = { "number", 0, 1 },
        nameColorG = { "number", 0, 1 },
        nameColorB = { "number", 0, 1 },
        fontColorR = { "number", 0, 1 },
        fontColorG = { "number", 0, 1 },
        fontColorB = { "number", 0, 1 },
    },
}

local COLOR_KEYS = { [1] = true, [2] = true, [3] = true, [4] = true,
    ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, r = true, g = true, b = true, a = true }
local COLOR_CHANNELS = { "r", "g", "b", "a" }

local function PlainTable(value)
    return not IsSecret(value) and type(value) == "table" and getmetatable(value) == nil
end

local function NumberInRange(value, minimum, maximum)
    return not IsSecret(value) and type(value) == "number" and value >= minimum and value <= maximum
end

local function NormalizeColor(value)
    if not PlainTable(value) then return nil end
    for key in pairs(value) do
        if IsSecret(key) or not COLOR_KEYS[key] then return nil end
    end
    local out = {}
    for index = 1, 4 do
        local channel = value[index]
        if IsSecret(channel) then return nil end
        if channel == nil then channel = value[tostring(index)] end
        if IsSecret(channel) then return nil end
        if channel == nil then channel = value[COLOR_CHANNELS[index]] end
        if IsSecret(channel) then return nil end
        if channel == nil and index == 4 then channel = 1 end
        if not NumberInRange(channel, 0, 1) then return nil end
        out[index] = channel
    end
    return out
end

local function NormalizeField(value, spec)
    if IsSecret(value) then return nil end
    local kind = spec[1]
    if kind == "boolean" then
        if type(value) == "boolean" then return value end
    elseif kind == "number" then
        if NumberInRange(value, spec[2], spec[3]) then return value end
    elseif kind == "string" then
        if type(value) == "string" and #value > 0 and #value <= spec[2] and not value:find("%c") then return value end
    elseif kind == "enum" then
        if type(value) == "string" and spec[2][value] then return value end
    elseif kind == "color" then
        return NormalizeColor(value)
    end
end

local function NormalizeSection(section, schema)
    if not PlainTable(section) then return nil end
    local out = {}
    for key, value in pairs(section) do
        if IsSecret(key) or type(key) ~= "string" or not schema[key] then return nil end
        local normalized = NormalizeField(value, schema[key])
        if normalized == nil then return nil end
        out[key] = normalized
    end
    return out
end

local function NormalizeClear(clear, out)
    if not PlainTable(clear) then return nil end
    local result, seen, count = {}, {}, 0
    for index, path in pairs(clear) do
        if not NumberInRange(index, 1, 80) or index % 1 ~= 0 then return nil end
        if IsSecret(path) or type(path) ~= "string" then return nil end
        local section, key = path:match("^(%a+)%.(%w+)$")
        if not section or not SCHEMA[section] or not SCHEMA[section][key] or seen[path] then return nil end
        if out[section] and out[section][key] ~= nil then return nil end
        seen[path], count = true, count + 1
        result[index] = path
    end
    if count ~= #result then return nil end
    table.sort(result)
    return result
end

function Settings.Normalize(payload)
    if IsSecret(payload) then return nil, "invalid" end
    if payload == nil then return nil end
    if not PlainTable(payload) then return nil, "invalid" end
    local version = payload.version
    if IsSecret(version) or version ~= nil and version ~= 1 then return nil, "invalid" end
    local out = { version = 1 }
    for key, value in pairs(payload) do
        if IsSecret(key) or type(key) ~= "string" then return nil, "invalid" end
        if SCHEMA[key] then
            out[key] = NormalizeSection(value, SCHEMA[key])
            if not out[key] then return nil, "invalid" end
        elseif key ~= "version" and key ~= "clear" then
            return nil, "invalid"
        end
    end
    local clear = payload.clear
    if IsSecret(clear) then return nil, "invalid" end
    if clear ~= nil then
        out.clear = NormalizeClear(clear, out)
        if not out.clear then return nil, "invalid" end
    end
    return out
end

-- Captures can come from a newer host or pre-validation saved data. Filter
-- each field independently; pasted imports continue through strict Normalize.
function Settings.Capture(payload)
    if not PlainTable(payload) then return nil end
    local out = { version = 1 }
    for section, schema in pairs(SCHEMA) do
        if PlainTable(payload[section]) then
            local values = {}
            for key, rule in pairs(schema) do
                local value = NormalizeField(payload[section][key], rule)
                if value ~= nil then values[key] = value end
            end
            out[section] = values
        end
    end
    if PlainTable(payload.clear) then
        local clear, seen = {}, {}
        for _, path in pairs(payload.clear) do
            if not IsSecret(path) and type(path) == "string" then
                local section, key = path:match("^(%a+)%.(%w+)$")
                if section and SCHEMA[section] and SCHEMA[section][key] and not seen[path]
                    and not (out[section] and out[section][key] ~= nil) then
                    seen[path], clear[#clear + 1] = true, path
                end
            end
        end
        table.sort(clear)
        out.clear = clear
    end
    return out
end

local HostBridge = Suite.HostBridge

-- The settings provider is optional on older hosts and may be published late.
local function NameplateSettingsProvider()
    local get = HostBridge.NameplateSettingsGetter()
    if type(get) ~= "function" then return nil end
    local provider = get()
    return type(provider) == "table" and provider.version == 1 and provider or nil
end

function HostBridge.HasNameplateSettings()
    return NameplateSettingsProvider() ~= nil
end

function HostBridge.HasNameplateFontSettings()
    local provider = NameplateSettingsProvider()
    return provider ~= nil and type(provider.HasFontScope) == "function" and provider.HasFontScope() == true
end

function HostBridge.CaptureNameplateSettings(profileName)
    local provider = NameplateSettingsProvider()
    if not provider then return nil, "unavailable" end
    local payload, reason, snapshot = provider.Capture(profileName)
    return Settings.Capture(payload), reason, Settings.Capture(snapshot)
end

function HostBridge.ResolveNameplateTypography(overrides, profileName)
    local provider = NameplateSettingsProvider()
    if not provider or type(provider.ResolveTypography) ~= "function" then return nil end
    local resolved, reason = provider.ResolveTypography(overrides, profileName)
    local captured = Settings.Capture({ nameplates = resolved })
    return captured and captured.nameplates, reason
end

function HostBridge.NormalizeNameplateSettings(payload)
    return Suite.NameplateHostSettings.Normalize(payload)
end

function HostBridge.ApplyNameplateSettings(payload, transition)
    local normalized, reason = HostBridge.NormalizeNameplateSettings(payload)
    if reason then return false, reason end
    if normalized == nil then return true end
    if Suite.InCombat(transition) or Suite.IsCombatLocked() then return false, "combat" end
    local provider = NameplateSettingsProvider()
    if not provider then return false, "unavailable" end
    local fonts = HostBridge.HasNameplateFontSettings()
    local fallback = not fonts and normalized.nameplates ~= nil
    if not fonts then
        normalized.nameplates = nil
        local clear = {}
        for _, path in ipairs(normalized.clear or {}) do
            if path:sub(1, 11) == "nameplates." then fallback = true else clear[#clear + 1] = path end
        end
        normalized.clear = #clear > 0 and clear or nil
    end
    local ok, result = provider.Apply(normalized)
    if not ok then return false, result end
    local report = type(result) == "table" and result or {}
    report.fontFallback = fallback
    return true, report
end

-- Cold editors enumerate this schema instead of maintaining another field list.
function Settings.Keys(section)
    local keys = {}
    if IsSecret(section) or type(section) ~= "string" then return keys end
    for key in pairs(SCHEMA[section] or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local NPC_KINDS = { friendly = true, neutral = true, enemy = true, dead = true }

function HostBridge.NPCNameColor(unitOrKind)
    if not Suite.Public(unitOrKind) or type(unitOrKind) ~= "string" then return end
    local colors = HostBridge.NPCColors()
    if not colors or type(colors.GetNPCColor) ~= "function" then return end
    local kind = NPC_KINDS[unitOrKind] and unitOrKind
    if not kind then
        -- UnitDocumentation, live and forever: public unit tokens, nullable reaction.
        local dead = UnitIsDeadOrGhost(unitOrKind)
        if not Suite.Public(dead) then return end
        if dead then
            kind = "dead"
        else
            local reaction = UnitReaction(unitOrKind, "player")
            if not Suite.Finite(reaction) then return end
            kind = reaction >= 5 and "friendly" or reaction == 4 and "neutral" or "enemy"
        end
    end
    return colors.GetNPCColor(kind)
end

function HostBridge.HasNameplateFontsMenu(M)
    local formatter = HostBridge.NameFormatter()
    local bridge = M.SearchBridge
    return formatter and formatter.Nameplates and M.pages and M.pages.opt_fonts
        and bridge and bridge.OpenSearchTarget
end

-- Menu2 applies the scope as view state and resolves the real section on both
-- cold and cached pages. The Suite never writes the host profile.
function HostBridge.NameplateFontsTarget(section)
    return "opt_fonts", { sectionId = section }, { general = { _fontScopeKey = "nameplates" } }
end

function HostBridge.OpenNameplateFonts(M, section)
    local page, target, route = HostBridge.NameplateFontsTarget(section)
    local called, opened = M.SearchBridge.OpenSearchTarget(page, nil, nil, nil, route, target)
    return called and opened
end

