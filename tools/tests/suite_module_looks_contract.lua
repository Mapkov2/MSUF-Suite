-- A module's appearance and the Suite's global look (MSUF_Suite/Core/
-- Suite.lua, SuiteCatalog.lua): the global look is only a default for a
-- module without explicit appearance data. Each module's record
-- (db.moduleLooks) names the look its appearance last answered; enabling a
-- module adopts the global look only while that record differs. So a look
-- the player chose survives turning the module off and on, a preset or a
-- profile reload; a first enable, or one after the global look changed while
-- the module was off, adopts the global look; a page reset adopts it again.
-- Profiles saved before the record get it from their settings, and nothing is
-- restyled by that migration. Real core, real catalog.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite = {}
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
UnitGUID = function() return "Player-Test" end
UnitClass = function() return "Mage", "MAGE" end
C_ClassColor = { GetClassColor = function() return { r = .25, g = .78, b = .92 } end }
Minimap = { SetMaskTexture = function() end }
-- Bags read Blizzard's combined bag setting; the cooldown manager needs
-- MSUF's codec (no profile string is decoded here).
C_CVar = { GetCVar = function(name) return name == "combinedBags" and "1" or nil end }
MSUF_EncodeCompactTable = function() return "MSUF3:" end
MSUF_TryDecodeCompactString = function() return nil end
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end
local loaded = {}
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    DoesAddOnExist = function() return true end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function(name)
        loaded[name] = true
        local controller = Suite.Suite
        if name == "MSUF_Suite_Modules" then
            controller.NewContext = function()
                return { Release = function() end, RefreshOwnedSkins = function() end }
            end
            controller.RefreshEditMover = function() end
            controller.UnregisterEditElements = function() end
            return
        end
        for _, id in ipairs(Suite.SuiteOrder) do
            if Suite.SuiteCatalog[id].addon == name then
                controller.instances[id] = { Enable = function() end, Refresh = function() end, Disable = function() end }
            end
        end
    end,
}
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileIO.lua")
Suite.Suite.RGB = Suite.RGB
_G.MSUFSuite = Suite
assert(Suite.Database.Initialize(nil))
local S, Looks = Suite.Suite, Suite.SuiteLooks
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- The modules the review named, with one setting the active global look
-- writes: a colour of its look where it has one, else its look choice.
local MODULES = { "minimap", "chat", "damageMeter", "bags", "actionbars", "dataTexts", "cooldownManager",
    "buffReminders" }
local function StyledKey(id)
    local written = Suite.CopyValue(Suite.Defaults.suite.modules[id])
    Looks.ApplyToConfig(id, written, Suite.DB.suite.globalLook)
    local rules, choice = S.catalog[id].rules, nil
    for key, value in pairs(written) do
        if rules[key].color and key ~= "enabled" then return key, "123456" end
        if S.catalog[id].look.key == key then choice = key end
    end
    assert(choice, id .. " has no setting the global look writes")
    local values = rules[choice].choices
    for index = 1, #values do
        if index ~= written[choice] then return choice, index end
    end
end

for _, id in ipairs(Suite.SuiteOrder) do S.Config(id).enabled = false end
S.Start()
Check(Suite.DB.suite.globalLook == "cleanModern", "a new profile does not start with Clean Modern")
for _, id in ipairs(MODULES) do
    Check(S.Availability(id) == true, id .. " is not available in this harness")
    local key, value = StyledKey(id)
    Check(S.Set(id, "enabled", true) and S.states[id].active, id .. " did not start")
    Check(S.Set(id, key, value) and S.Config(id)[key] == value, id .. " refused its own look")
    Check(S.Set(id, "enabled", false) and S.Set(id, "enabled", true), id .. " did not turn off and on")
    Check(S.Config(id)[key] == value,
        id .. ": turning the module off and on replaced the player's " .. key .. " with the global look")
    -- The same through a batch (an import, the menu's preset choice).
    Check(S.SetMany(id, { enabled = false }) and S.SetMany(id, { enabled = true }) and S.Config(id)[key] == value,
        id .. ": a batch enable replaced the player's look")
end
-- "Core modules on" keeps the look of a running core module.
local presetKey, presetValue = StyledKey("bags")
Check(S.Config("bags")[presetKey] == presetValue and S.Preset("core"), "the core preset refused")
Check(S.Config("bags")[presetKey] == presetValue, "the core preset replaced a running module's look")
-- A profile reload keeps it too.
S.Normalize(Suite.DB)
Check(S.Config("chat")[StyledKey("chat")] == select(2, StyledKey("chat")), "a normalization replaced a look")

-- A module enabled for the first time adopts the global look.
local db = Suite.DB.suite
local fresh = "xpBar"
Check(db.moduleLooks[fresh] == "cleanModern", "the factory styling did not record its look")
db.moduleLooks[fresh] = nil
S.Config(fresh).look = 1
Check(S.Set(fresh, "enabled", false) and S.Set(fresh, "enabled", true) and S.Config(fresh).look == 5
    and db.moduleLooks[fresh] == "cleanModern", "a first enable did not adopt the global look")
-- The global look changes while a module is off: it adopts the new look
-- when it is enabled again, and keeps it through the next off/on.
Check(S.Set("chat", "enabled", false), "chat did not turn off")
Check(S.ApplyGlobalLook("midnightDark") and db.moduleLooks.chat ~= "midnightDark",
    "the global look restyled a module that is off")
Check(S.Set("chat", "enabled", true) and S.Config("chat").look == 2 and db.moduleLooks.chat == "midnightDark",
    "a module that was off when the global look changed did not adopt it")
-- The suite-wide gesture itself restyles every running module, a styled one too.
Check(S.Config("minimap").stylePreset == 9 and db.moduleLooks.minimap == "midnightDark",
    "the global look did not restyle a running module")
-- A page reset gives the module the global look again (the catalog's own
-- look is Midnight Dark).
Check(S.ApplyGlobalLook("foreverGlass") and S.Set("bags", "look", 1) and S.Reset("bags")
    and S.Config("bags").look == 3, "a page reset did not adopt the global look")

-- The record travels with copies and exports, known modules and looks only.
db.moduleLooks.unknownModule, db.moduleLooks.chat = "midnight", "midnightDark"
local copy = assert(Suite.ProfileIO.PrepareTable(Suite.DB, true))
Check(copy.suite.moduleLooks.chat == "midnightDark" and copy.suite.moduleLooks.unknownModule == nil,
    "a copy lost the module looks or kept an unknown module")
db.moduleLooks.chat = "noSuchLook"
S.Normalize(Suite.DB)
Check(db.moduleLooks.chat == nil and db.moduleLooks.unknownModule == nil, "normalization kept an invalid record")
Check(table.concat(Suite.Database.PROFILE_SETTINGS, ","):find("moduleLooks", 1, true),
    "undo history does not restore the module looks")

-- A profile saved before the record (its revision ends before the step).
local step = Support.MigrationStep(root, "Steps.RecordModuleLooks")
local function Saved(modules)
    return { suite = { schema = 1, revision = step - 1, globalLook = "cleanModern", modules = modules } }
end
local custom = { enabled = false, stylePreset = 1, borderColor = "ff0000", shadowSize = 12 }
local cleanBags = Suite.CopyValue(Suite.Defaults.suite.modules.bags)
Looks.ApplyToConfig("bags", cleanBags, "cleanModern")
local darkBags = Suite.CopyValue(Suite.Defaults.suite.modules.bags)
Looks.ApplyToConfig("bags", darkBags, "midnightDark")
darkBags.enabled = false
-- Running in Midnight Blue: adopted then, or chosen by the player since.
local running = Suite.CopyValue(Suite.Defaults.suite.modules.chat)
Looks.ApplyToConfig("chat", running, "midnight")
running.enabled = true
local old = Saved({ minimap = Suite.CopyValue(custom), bags = darkBags, chat = running,
    damageMeter = { enabled = false } })
local before = Suite.CopyValue(old.suite.modules)
S.Normalize(old)
local records = old.suite.moduleLooks
Check(old.suite.revision == S.MigrationRevision, "the record step did not run")
Check(records.minimap == "cleanModern" and records.chat == "cleanModern",
    "a styled or running module of an older profile would adopt the global look")
Check(records.bags == "midnightDark", "a module that was off in another look lost its later adoption")
-- (Its catalog appearance is a look of its own, or none.)
Check(records.damageMeter ~= "cleanModern", "a module never styled would not adopt the global look")
for id, config in pairs(before) do
    for key, value in pairs(config) do
        Check(old.suite.modules[id][key] == value, "the record step restyled " .. id .. "." .. key)
    end
end
Suite.DB = old
Suite.Registry.NotifyListeners("profile", "old")
Check(S.Set("minimap", "enabled", true) and S.Config("minimap").borderColor == "ff0000"
    and S.Config("minimap").stylePreset == 1, "an older profile's styled module was restyled when enabled")
Check(S.Set("bags", "enabled", true) and S.Config("bags").look == cleanBags.look,
    "an older profile's module in another look did not adopt the global look")
Check(S.Set("chat", "enabled", false) and S.Set("chat", "enabled", true) and S.Config("chat").look == 1,
    "an older profile's running module was restyled after off and on")
Check(S.Set("damageMeter", "enabled", true) and S.Config("damageMeter").look == 5,
    "an older profile's unstyled module did not adopt the global look")
Check(#reported == 0, "a call raised: " .. tostring(reported[1]))
print("Suite module looks: " .. checks .. " checks passed")
