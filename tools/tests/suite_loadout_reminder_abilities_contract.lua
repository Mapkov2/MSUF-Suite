local root = assert(arg[1])
local fixture = dofile(root .. "/tools/tests/comfort_fixture.lua").New(root, false)
local S = fixture.S
local zone, guid, reads, learned = 101, "Player-1-0001", 0, false
GetInstanceInfo = function() return "Dungeon", "party", 1, "", 5, false, false, zone end
UnitGUID = function() return guid end
C_Spell = { GetSpellName = function(id) return id == 1000 and "Utility" or nil end,
    GetSpellIDForSpellIdentifier = function(name) return name == "Utility" and 1000 or nil end }
C_SpellBook = { IsSpellKnown = function(id) assert(id == 1000); reads = reads + 1; return learned end }
S.LoadoutSnapshot = function() return 12, "Build", 1, "Loot" end
S.PlaceHost, S.QoLWarningSound = function() end, function() end
S.PaintQoLCard = function() return {} end
S.QoLCard = function()
    local host, background, border = fixture.Frame(), fixture.Frame(), fixture.Frame()
    border.SetColorTexture = function() end
    return host, background, border
end
S.CreateFontString = function()
    local label = fixture.Frame()
    label.SetJustifyH, label.SetWordWrap, label.SetMaxLines = function() end, function() end, function() end
    return label
end
function S.SetMany(id, values)
    for key, value in pairs(values) do fixture.modules[id].config[key] = value end
    return true
end
fixture:Load("MSUF_Suite_QualityOfLife/LoadoutReminder.lua")
local m = fixture:Start("loadoutReminder", { duration = 8 })
m.context.After, m.context.Cancel = function() end, function() end
assert(m:SetDungeonAbilities("Utility, 1000"))
assert(m.detail.text == "Missing abilities: Utility" and reads == 1, "the reminder must report the missing ability only once")
learned = true
m:Test()
assert(m.detail.text == "Build  |  Loot: Loot", "a learned ability must clear the warning")
learned = false
local openedZone, openedGuid, openedConfig = m:DungeonAbilityContext()
zone = 102
assert(not m:SetDungeonAbilities("Utility", openedZone, openedGuid, openedConfig), "an old prompt must not change a different dungeon")
local before = reads
m:Test()
assert(reads == before and not m.detail.text:find("Missing", 1, true), "another dungeon must not inherit the rule")
zone, guid = 101, "Player-1-0002"
m:Test()
assert(reads == before, "another character must not inherit the rule")
guid = "Player-1-0001"
fixture:Combat(true)
assert(not m:SetDungeonAbilities("0"))
m:Test()
assert(reads == before, "the ability check must stay out of combat")
fixture:Combat(false)
assert(m:SetDungeonAbilities("0") and m.config.dungeonAbilities == "")
print("suite_loadout_reminder_abilities_contract: ok")
