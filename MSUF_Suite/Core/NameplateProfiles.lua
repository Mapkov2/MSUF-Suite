local _, NS = ...
local Profiles = {}
NS.NameplateProfiles = Profiles
local ID = "nameplates"

Profiles.Groups = {
    { key = "layout", label = "Layout and visibility" },
    { key = "auras", label = "Auras and aura positions" },
    { key = "text", label = "Names and typography" },
    { key = "casts", label = "Castbars and interrupt readiness" },
    { key = "colors", label = "Colors and highlights" },
    { key = "blizzard", label = "General Blizzard nameplate settings" },
}

function Profiles.Selection(options)
    local source = options and options.nameplateSections
    if type(source) ~= "table" then return nil end
    local selected = {}
    for _, group in ipairs(Profiles.Groups) do
        if source[group.key] == true then selected[group.key] = true end
    end
    return selected
end

function Profiles.SettingGroup(key, rule)
    local section = rule.section or ""
    if section == "auraColors" then return "colors" end
    if section:lower():find("aura", 1, true) or key:find("Auras", 1, true)
        or key:find("Buffs", 1, true) or key:find("ControlAura", 1, true) then return "auras" end
    if key:find("Cast", 1, true) or section:lower():find("cast", 1, true) == 1 then return "casts" end
    if key:match("Offset[XY]$") then return "layout" end
    if section == "nameText" or section:match("^extraText%d$") or key:find("Font", 1, true)
        or key:find("Name", 1, true) or key:find("Text", 1, true) and not key:find("Texture", 1, true) then return "text" end
    if rule.color or section == "roleColors" or section == "signals" then return "colors" end
    return "layout"
end

function Profiles.FilterSettings(settings, selected)
    local result, rules = {}, NS.SuiteCatalog[ID].rules
    for key, value in pairs(settings) do
        local rule = rules[key]
        if rule and key ~= "protectImport" and key ~= "nativeProfileMode"
            and (not selected or selected[Profiles.SettingGroup(key, rule)]) then result[key] = value end
    end
    return result
end

function Profiles.FilterShared(shared, selected)
    if not shared or not selected then return shared end
    local result = { version = shared.version }
    if selected.text then result.nameplates = shared.nameplates end
    if selected.casts then result.general = shared.general end
    for _, path in ipairs(shared.clear or {}) do
        local section = path:match("^(%a+)%.")
        if section == "nameplates" and selected.text or section == "general" and selected.casts then
            result.clear = result.clear or {}
            result.clear[#result.clear + 1] = path
        end
    end
    if not result.nameplates and not result.general and not result.clear then return nil end
    return result
end

local BUILTINS = {
    { key = "compact", label = "Compact", settings = { enemyHealthWidthDelta = 120, enemyHealthHeightDelta = 12,
        enemyCastHeight = 10, targetScaleEnabled = true, targetScalePercent = 115 } },
    { key = "tank", label = "Tank", settings = { enemyTankMode = true, enemyFocusMarker = true,
        enemyThreatTransitionEnabled = true, focusReminderEnabled = true, enemyNameDuringCast = 2,
        interruptFeedbackEnabled = true, extraText1Source = 6, extraText1Side = 2,
        enemyHealthWidthDelta = 150, enemyHealthHeightDelta = 16, targetScaleEnabled = true, targetScalePercent = 120 } },
    { key = "dots", label = "DoT", settings = { enemyHealthWidthDelta = 150, enemyHealthHeightDelta = 14,
        auraDisplayEnabled = true, auraScaleMode = 2, auraScalePercent = 120, executePulseEnabled = true,
        enemyNameDuringCast = 2, interruptFeedbackEnabled = true, extraText1Source = 10, extraText1Side = 2 } },
    { key = "pvp", label = "PvP", settings = { enemyFocusMarker = true, focusScaleEnabled = true, focusScalePercent = 115,
        interruptFeedbackEnabled = true, extraText1Source = 2, extraText1Side = 2, enemyHealthWidthDelta = 155,
        enemyHealthHeightDelta = 16, targetScaleEnabled = true, targetScalePercent = 125 } },
}

local function Store()
    local root = NS.RootDB
    if not root then return nil end
    if type(root.nameplateTemplates) ~= "table" then root.nameplateTemplates = {} end
    return root.nameplateTemplates
end

function Profiles.List()
    local result = {}
    for _, entry in ipairs(BUILTINS) do result[#result + 1] = { key = entry.key, label = entry.label, builtin = true } end
    local saved = {}
    for name, text in pairs(Store() or {}) do
        if NS.Database.IsProfileName(name) and type(text) == "string" then saved[#saved + 1] = name end
    end
    table.sort(saved)
    for _, name in ipairs(saved) do result[#result + 1] = { key = "saved:" .. name, label = name } end
    return result
end

local function DefaultTypography()
    return { fontOverride = true, fontKey = "EXPRESSWAY", fontSize = 12, nameFontSize = 12,
        noOutline = false, boldText = false, fontMonochrome = false, fontSlug = false, textBackdrop = true,
        fontShadowOpacity = 1, fontShadowDistance = 1, fontTextAlpha = 1, fontBaselineOffset = 0,
        nameFormat = "FULL", shortenNames = false, shortenNameClipSide = "LEFT", shortenNameMaxChars = 12,
        shortenNameShowDots = true, nameColorMode = "DEFAULT", nameClassColor = false, npcNameRed = false,
        nameNpcClassColor = false, nameColorR = 1, nameColorG = 1, nameColorB = 1,
        fontColorR = 1, fontColorG = 1, fontColorB = 1 }
end

-- A template turns interrupt readiness on for nameplates; its look stays the
-- one MSUF's castbar menu sets for every castbar.
local function DefaultInterrupts()
    return { kickReadyShowNameplates = true }
end

local function Builtin(entry)
    local catalog = NS.SuiteCatalog[ID]
    local settings = NS.CopyValue(NS.Defaults.suite.modules[ID])
    for key, value in pairs(catalog.look.presets[4]) do settings[key] = value end
    settings.enabled, settings.enemy, settings.friendly, settings.look = true, true, true, 3
    settings.auraScaleMode, settings.auraScalePercent = 2, 100
    settings.personalAuras, settings.friendlyNpcDebuffs = 2, 2
    for _, group in ipairs(NS.NameplateStyle.AuraGroups) do
        settings[group.key .. "AuraMode"] = 2
        settings[group.key .. "Buffs"], settings[group.key .. "Debuffs"], settings[group.key .. "Control"] = true, true, true
    end
    for key, value in pairs(entry.settings) do
        if catalog.rules[key] then settings[key] = value end
    end
    return NS.ProfileIO.EncodeNameplateProfile(settings, NS.ProfileIO.DefaultNameplateCVars(),
        { version = 1, nameplates = DefaultTypography(), general = DefaultInterrupts() })
end

function Profiles.Read(key)
    for _, entry in ipairs(BUILTINS) do if entry.key == key then return Builtin(entry) end end
    local name = type(key) == "string" and key:match("^saved:(.+)$")
    local saved = Store()
    if name and saved and type(saved[name]) == "string" then return saved[name] end
    return nil, "Choose a nameplate template"
end

function Profiles.Save(name, text, overwrite)
    if NS.InCombat() then return false, "Finish combat before editing the suite" end
    name = type(name) == "string" and name:match("^%s*(.-)%s*$")
    if not NS.Database.IsProfileName(name) then return false, "Enter a new profile name" end
    local saved = Store()
    if not saved then return false, "Missing suite profile" end
    if saved[name] and overwrite ~= true then return false, "Profile name already exists" end
    local reason
    if not text then text, reason = NS.ProfileIO.ExportModule(ID) end
    if not text then return false, reason end
    local id = NS.ProfileIO.PrepareModuleProfile(text)
    if id ~= ID then return false, "Invalid nameplate template" end
    saved[name] = text
    return true, "saved:" .. name
end

function Profiles.Delete(key)
    if NS.InCombat() then return false, "Finish combat before editing the suite" end
    local name = type(key) == "string" and key:match("^saved:(.+)$")
    local saved = Store()
    if not name or not saved or not saved[name] then return false, "Choose a saved nameplate template" end
    saved[name] = nil
    return true
end

local function Equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not Equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function Changes(values, current)
    local changes = {}
    for key, value in pairs(values or {}) do
        if not Equal(current[key], value) then changes[#changes + 1] = { key = key, value = value, before = current[key] } end
    end
    table.sort(changes, function(a, b) return a.key < b.key end)
    return changes
end

local function SharedValues(shared)
    local values = {}
    if not shared then return values end
    for _, section in ipairs({ "general", "nameplates" }) do
        for key, value in pairs(shared[section] or {}) do values[section .. "." .. key] = value end
    end
    for _, key in ipairs(shared.clear or {}) do values[key] = "Inherited" end
    return values
end

function Profiles.Inspect(text, options)
    local id, settings, reason, _, native, shared, included = NS.ProfileIO.PrepareModuleProfile(text, true)
    if id ~= ID then return nil, reason or "Invalid nameplate template" end
    local selected = Profiles.Selection(options)
    if included then
        if not selected then selected = included
        else for key in pairs(selected) do if not included[key] then selected[key] = nil end end end
    end
    options = selected and { nameplateSections = selected } or options
    settings, shared = Profiles.FilterSettings(settings, selected), Profiles.FilterShared(shared, selected)
    if selected and not selected.blizzard then native = nil end
    local changes = Changes(settings, NS.Suite.Config(ID))
    local nativeChanges = Changes(native, NS.ProfileIO.CaptureNameplateCVars() or {})
    local sharedChanges = Changes(SharedValues(shared), SharedValues(NS.ProfileIO.CaptureNameplateShared()))
    local encoded, why = NS.ProfileIO.EncodeNameplateProfile(settings, native, shared, options)
    if not encoded then return nil, why end
    return { text = encoded, changes = changes, native = native, shared = shared, legacy = not native,
        nativeChanges = nativeChanges, sharedChanges = sharedChanges }
end

local previous
local function CaptureSetup()
    local db = NS.DB
    return { profile = NS.Database.GetActiveProfileName(), owner = db, settings = NS.CopyValue(NS.Suite.Config(ID)),
        native = NS.ProfileIO.NameplateSnapshot(db.nameplateCVars), shared = NS.ProfileIO.CaptureNameplateUndo(),
        storedNative = NS.CopyValue(db.nameplateCVars), storedShared = NS.CopyValue(db.nameplateShared),
        pending = NS.CopyValue(db.nameplateSharedPending), look = db.suite.moduleLooks and db.suite.moduleLooks[ID] }
end

function Profiles.CanRestore()
    return previous ~= nil and previous.owner == NS.DB and previous.profile == NS.Database.GetActiveProfileName()
end

function Profiles.Apply(text, options)
    local prepared, reason = Profiles.Inspect(text, options)
    if not prepared then return false, reason end
    local before = CaptureSetup()
    local ok, failure = NS.SuiteProfiles.ImportModule(prepared.text)
    if ok then previous = before end
    return ok, failure, NS.ProfileIO.lastNameplateReport
end

function Profiles.RestorePrevious()
    if not Profiles.CanRestore() then return false, "No previous nameplate setup is available" end
    local before = CaptureSetup()
    local ok, reason = NS.SuiteProfiles.RestoreNameplateSetup(previous)
    if ok then previous = before end
    return ok, reason, NS.ProfileIO.lastNameplateReport
end
