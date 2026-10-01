local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
UnitGUID = function() return "Player-Test" end
Minimap = { SetMaskTexture = function() end }
C_AddOns = { IsAddOnLoaded = function() return false end,
    DoesAddOnExist = function() return false end, GetAddOnEnableState = function() return 2 end }
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end,
        UnregisterEvent = function() end, UnregisterAllEvents = function() end }
end
securecallfunction = function(callback, ...) return callback(...) end
local colors = { MAGE = { r = .25, g = .78, b = .92 }, PRIEST = { r = 1, g = 1, b = 1 },
    DRUID = { r = 1, g = .49, b = .04 } }
local classCalls, colorCalls = 0, 0
local function Session(class, profile, forever)
    MSUF_NS.Client = forever and { Flavor = "Mainline", IsForever = true } or nil
    UnitClass = function(unit)
        assert(unit == "player", "Class Style read another unit")
        classCalls = classCalls + 1
        return class, class
    end
    C_ClassColor = { GetClassColor = function(token)
        colorCalls = colorCalls + 1
        return colors[token]
    end }
    local ns = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
    assert(loadfile(root .. "/MSUF_Suite/Core/ProfileIO.lua"))("MSUF_Suite", ns)
    ns.DB = profile or { suite = { schema = 1, revision = ns.Suite.MigrationRevision, modules = {} } }
    -- Keep runtime frames outside this catalog/controller contract.
    ns.Suite.Apply = function() end
    ns.Suite.Start()
    return ns
end

local mage = Session("MAGE")
assert(classCalls == 1 and colorCalls == 1, "class resolver did not cache the character")
local expected = { actionbars = 6, bags = 6, chat = 6, damageMeter = 6, dataTexts = 6,
    xpBar = 6, skyriding = 6, minimap = 12, cursorEffects = 6, actionTracker = 7, combatStatsHUD = 6 }
local legacy = {
    standard = { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern" },
    minimap = { "Custom", "Clean", "Arcane", "Ember", "Astral", "Steel", "MSUF Forever",
        "Midnight Blue", "Midnight Dark", "Antique Map", "Clean Modern" },
    actionTracker = { "Classic UI", "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern" },
    cursorEffects = { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Clean Modern", "Custom" },
    qol = { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Clean Modern" },
}
legacy.combatStatsHUD = legacy.cursorEffects
for _, id in ipairs(mage.SuiteOrder) do
    local spec = mage.SuiteCatalog[id]
    local look = spec.look
    if look and look.global then
        local names = legacy[id] or (look.global == true and legacy.standard or legacy.qol)
        for index, name in ipairs(names) do
            assert(spec.rules[look.key].choices[index] == name, id .. " changed an existing style index/name")
        end
        local choice = look.global == true and 6 or look.global[6]
        assert(choice and spec.rules[look.key].choices[choice] == "Class Style", id .. " missed the added choice")
        assert(mage.DB.suite.modules[id][look.key] ~= choice, id .. " silently migrated to Class Style")
    end
end
assert(mage.Suite.ApplyGlobalLook("classColor"), "global style gesture rejected Class Style")
assert(mage.Suite.StyleProfile(mage.DB, "classColor"))
local m = mage.DB.suite.modules
for id, choice in pairs(expected) do
    local look = mage.SuiteCatalog[id].look
    assert(m[id][look.key] == choice, id .. " has the wrong appended Class Style index")
    assert(mage.SuiteCatalog[id].rules[look.key].choices[choice] == "Class Style", id .. " has no Class Style label")
end
assert(mage.SuiteCatalog.cursorEffects.look.presets[5] == nil, "cursor Custom was replaced by a preset")
assert(mage.SuiteCatalog.combatStatsHUD.look.presets[5] == nil, "stats Custom was replaced by a preset")
assert(mage.QoLVisualStyles[5].accent == "40c7eb")
assert(m.chat.accentColor == "40c7eb" and m.bags.accentColor == "40c7eb")
assert(m.cursorEffects.color == "40c7eb" and m.combatStatsHUD.accentColor == "40c7eb")
assert(m.cooldownManager.classStyle and m.buffReminders.classStyle)
assert(m.buffReminders.borderColor == mage.DataTextLooks[6].border)
assert(m.nameplates.look == mage.Defaults.suite.modules.nameplates.look, "global style changed nameplate architecture")
local staticAccent = mage.ChatLookPresets[5].accentColor
for _ = 1, 100 do
    mage.Suite.Normalize(mage.DB)
    mage.SuiteLooks.ApplyToConfig("bags", m.bags, "classColor")
    assert(mage.QoLVisualStyles[5].accent == mage.DataTextLooks[6].accent)
end
assert(classCalls == 1 and colorCalls == 1, "settings refresh queried the class again")
assert(mage.ChatLookPresets[5].accentColor == staticAccent, "dynamic preset mutated Clean Modern")

-- Deliberate module customizations survive class changes, including modules
-- without a visible preset selector and per-bar DataText overrides.
assert(mage.Suite.SetMany("chat", { look = 4, accentColor = "123456" }))
assert(mage.Suite.Set("buffReminders", "borderColor", "112233"))
assert(m.buffReminders.classStyle == false)
m.dataTexts.customColors = true
m.dataTexts.bar1StyleOverride, m.dataTexts.bar1CustomColors = true, true
m.dataTexts.bar1Look, m.dataTexts.bar1AccentColor = 4, "654321"
local shared = assert(mage.ProfileIO.PrepareTable(mage.DB, false))
local priest = Session("PRIEST", shared, true)
local p = priest.DB.suite.modules
assert(classCalls == 2 and colorCalls == 2)
assert(p.bags.accentColor == "ffffff" and p.actionbars.interactionColor == "ffffff",
    "new character retained exported class colors")
assert(p.chat.look == 4 and p.chat.accentColor == "123456", "Custom chat was recolored")
assert(p.buffReminders.borderColor == "112233" and not p.buffReminders.classStyle,
    "custom reminder border was recolored")
assert(p.cooldownManager.classStyle and priest.DataTextLooks[6].border == "808080")
for _, slot in ipairs(priest.CDM.SLOTS) do
    local key = priest.CDM.KEYS[slot.key].borderColor
    if key then assert(p.cooldownManager[key] == "808080", "CDM retained another character's border") end
end
assert(p.bags.backgroundColor == "101010" and priest.DataTextLooks[6].background == "101010"
    and priest.QoLVisualStyles[5].background == "101010", "white Priest class brightened the surfaces")
assert(p.dataTexts.customColors and p.dataTexts.bar1CustomColors and p.dataTexts.bar1AccentColor == "654321",
    "class refresh reset deliberate DataText overrides")
assert(priest.DataTextLooks[6].warning == priest.DataTextLooks[5].warning,
    "class palette changed semantic warnings")

-- A profile switch/import replaces stored RGB with the receiving player's
-- class, while a later-enabled module adopts the active global choice.
priest.DB = priest.CopyValue(mage.DB)
priest.Registry.NotifyListeners("profile", "imported")
p = priest.DB.suite.modules
assert(p.bags.accentColor == "ffffff", "profile activation kept foreign class colors")
p.bags.enabled, p.bags.look, p.bags.accentColor = false, 2, "b9ab86"
assert(priest.Suite.Set("bags", "enabled", true))
assert(p.bags.look == 6 and p.bags.accentColor == "ffffff", "later enabled module missed Class Style")
assert(priest.Suite.ApplyGlobalLook("cleanModern"))
assert(p.bags.look == 5 and p.bags.accentColor == "e6ecf2" and p.chat.accentColor == "e6ecf2")
assert(not p.cooldownManager.classStyle and not p.buffReminders.classStyle)
priest.Suite.Normalize(priest.DB)
assert(p.bags.accentColor == "e6ecf2", "class refresh overwrote a restored static look")
assert(classCalls == 2 and colorCalls == 2)

-- Early load retry is bounded by cold settings
-- paths; they add no polling, event listener or rendering callback.
local retry = Session(nil)
UnitClass = function() classCalls = classCalls + 1; return "Druid", "DRUID" end
C_ClassColor.GetClassColor = function(token) return colors[token] end
retry.Suite.Normalize(retry.DB)
assert(retry.DataTextLooks[6].accent == "ff7d0a", "early class identity was not retried")
local calls = classCalls
retry.Suite.Normalize(retry.DB)
assert(classCalls == calls, "late class identity was not cached")
print("Suite Class Style: character/login/import, static restore, Custom preservation and cached palettes verified")
