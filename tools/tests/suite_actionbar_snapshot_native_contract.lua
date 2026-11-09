local root = arg[1] or "."
local actions, keys, learned, independent = {}, {}, {}, {}
local cursor, combat, gamepad, accountScope, selected, starter, specGroup
local saves, pickups, placements, bindingWrites = 0, 0, 0, 0
local wrongRank, enterCombat, failPlace, slotRace, failKey, nativeEditor
local secrets = arg[2] and assert(loadfile(arg[2]))()
local SECRET = secrets and secrets.New("string") or {}
local stopWatching
if secrets then
    secrets.Install()
    secrets.GUARD_NAMES.falsy.Public = true
    secrets.GUARD_NAMES.falsy.Finite = true
    secrets.GUARD_NAMES.falsy.PositiveInteger = true
    stopWatching = secrets.Watch(root .. "/" .. (arg[3] or "MSUF_Suite_ActionBars/SnapshotNative.lua"), { strict = true })
end

local function Public(value)
    if secrets then return not secrets.IsSecret(value) end
    return value ~= SECRET
end
local S = {
    Public = Public,
    PublicText = function(value)
        if Public(value) and type(value) == "string" and value ~= "" then return value end
    end,
    Finite = function(value) return Public(value) and type(value) == "number" and math.abs(value) < math.huge end,
    Dispatch = function(call, ...) return call(...) end,
    Text = function(value) return value end,
}
local NS = { Client = { isForever = true }, InCombat = function() return combat == true end }
local AB = {
    BUTTONS = 12,
    Frame = function(name)
        if nativeEditor == name then return { IsShown = function() return true end } end
    end,
    ENUM = { BAR = { MAIN = 1, FIRST_NATIVE = 2, LAST_NATIVE = 8, LAST_ACTION = 10 } },
    FIRST_SLOT = { 1, 61, 49, 25, 37, 145, 157, 169, 13 },
    COMMANDS = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
        "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON",
        "MSUFSUITE_BAR9_BUTTON", "MSUFSUITE_BAR10_BUTTON" },
}

local function SnapshotSpell(index)
    local action = independent[index]
    if action == nil then return false end
    if type(action) == "number" then return action end
end
AB.Virtual = {
    SnapshotSpell = SnapshotSpell,
    SetSnapshotSpell = function(index, before, after)
        assert(not combat and cursor == nil)
        if SnapshotSpell(index) ~= before then return false end
        independent[index] = after or nil
        return true
    end,
}

Enum = { BindingSet = { Account = 1, Character = 2 }, SpellBookSpellBank = { Player = 0 },
    SpellBookItemType = { Spell = 1 } }
function UnitGUID() return "Player-1-Example" end
function UnitName() return "Example" end
function GetRealmName() return "Test Realm" end
function UnitClass() return "Mage", "MAGE" end
DUAL_SPEC_PRIMARY, DUAL_SPEC_SECONDARY = "Primary Talents", "Secondary Talents"
C_SpecializationInfo = {
    GetActiveSpecGroup = function() return specGroup end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function(index) assert(index == 1) return 62, "Arcane" end,
}
C_ClassTalents = {
    GetStarterBuildActive = function() return starter end,
    GetLastSelectedSavedConfigID = function(spec) assert(spec == 62) return selected end,
    GetActiveConfigID = function() return 55 end,
}
C_Traits = { GetConfigInfo = function(id) return { name = id == 55 and "Base" or "Named build" } end }
function GetLootSpecialization() return 0 end
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
C_ActionBar = {
    HasAction = function(slot)
        if actions[slot] == SECRET then return SECRET end
        return actions[slot] ~= nil
    end,
}
function GetActionInfo(slot)
    local action = actions[slot]
    if action == "macro" then return "macro", 4 end
    if action == "assisted" then return "spell", 101, "assistedcombat" end
    if action == SECRET then error("secret slot reached action read") end
    if action then return "spell", action end
end
C_SpellBook = {
    FindSpellBookSlotForSpell = function(id, hidden, flyouts)
        assert(hidden and flyouts == false)
        if learned[id] then return id, Enum.SpellBookSpellBank.Player end
    end,
    GetSpellBookItemType = function(index)
        return Enum.SpellBookItemType.Spell, index, index
    end,
}
function GetCursorInfo()
    if cursor == "item" then return "item", 81 end
    if cursor == SECRET then return SECRET end
    if cursor then return "spell", 1, "spell", cursor end
end
function ClearCursor() cursor = nil end
C_Spell = { PickupSpell = function(id)
    assert(not combat and not cursor)
    pickups = pickups + 1
    cursor = wrongRank or id
end }
function PlaceAction(slot)
    assert(not combat and cursor)
    placements = placements + 1
    if failPlace then return end
    actions[slot], cursor = cursor, actions[slot]
    if slotRace then actions[slot] = slotRace end
    if enterCombat then combat = true end
end
function PickupAction(slot)
    assert(not combat and not cursor)
    pickups = pickups + 1
    cursor, actions[slot] = actions[slot], nil
end
function GetCurrentBindingSet() return accountScope and Enum.BindingSet.Account or Enum.BindingSet.Character end
C_KeyBindings = { GetBindingContextForAction = function(command)
    assert(type(command) == "string")
    return 7
end }
function GetBindingAction(key, includeOverrides, context)
    assert(includeOverrides == false and context == 7)
    return keys[key] or ""
end
function GetBindingKey(command, includeOverrides, context)
    assert(includeOverrides == nil and context == 7)
    local bound = {}
    for key, mapped in pairs(keys) do
        if mapped == command then bound[#bound + 1] = key end
    end
    return unpack(bound)
end
function SetBinding(key, command, context)
    assert(not combat and context == 7)
    bindingWrites = bindingWrites + 1
    if failKey then return false end
    keys[key] = command
    return true
end
function SaveBindings(set)
    assert(not combat and set == GetCurrentBindingSet())
    saves = saves + 1
end

local P = { Suite = S, NS = NS, ActionBars = AB }
assert(loadfile(root .. "/MSUF_Suite_Modules/LoadoutSnapshot.lua"))("MSUF_Suite_Modules", P)
assert(loadfile(root .. "/MSUF_Suite_ActionBars/SnapshotNative.lua"))("MSUF_Suite_ActionBars", P)
local N = assert(AB.SnapshotNative)

local function Reset()
    actions, keys, learned, independent = {}, {}, { [101] = true, [102] = true, [103] = true }, {}
    cursor, combat, gamepad, accountScope, selected, starter, specGroup = nil, false, false, true, 71, false, 1
    saves, pickups, placements, bindingWrites = 0, 0, 0, 0
    wrongRank, enterCombat, failPlace, slotRace, failKey, nativeEditor = nil, nil, nil, nil, nil, nil
end

Reset()
NS.Client.isForever = false
local identity = N.Identity()
assert(identity.setup == "62:71" and identity.spec == 62 and identity.loadout == "Named build")
local id, name, loot = S.LoadoutSnapshot()
assert(id == 71 and name == "Named build" and loot == 62)
starter = true
assert(N.Identity().setup == "62:starter" and N.Identity().loadout == nil)
starter, selected = false, nil
assert(N.Identity().setup == "62:default" and N.Identity().loadout == nil and S.LoadoutSnapshot() == 55)
selected = SECRET
assert(N.Identity() == nil, "an unreadable native selection cannot match the default setup")
selected, starter = nil, SECRET
assert(N.Identity() == nil, "an unreadable starter-build flag cannot match the default setup")
local activeSpec = C_SpecializationInfo.GetSpecialization
C_SpecializationInfo.GetSpecialization = function() return nil end
assert(N.Identity().setup == "0:default" and N.Identity().setupLabel == "Mage")
C_SpecializationInfo.GetSpecialization = activeSpec
NS.Client.isForever = true
starter = false
assert(N.Identity().setup == "group:1" and N.Identity().group == 1 and N.Identity().setupLabel == DUAL_SPEC_PRIMARY)
specGroup = 2
assert(N.Identity().setup == "group:2" and N.Identity().group == 2 and N.Identity().setupLabel == DUAL_SPEC_SECONDARY)
specGroup = SECRET
assert(N.Identity() == nil, "unreadable Forever group was accepted as a snapshot setup")
specGroup = 3
assert(N.Identity() == nil, "unknown Forever group was accepted as a snapshot setup")

Reset()
actions = { [1] = 101, [73] = 102, [109] = 103, [121] = 101, [145] = 102, [180] = 103,
    [2] = "macro", [3] = SECRET, [4] = 104, [5] = "assisted" }
keys = { ["1"] = "ACTIONBUTTON1", ["ALT-1"] = "ACTIONBUTTON1", ["CTRL-1"] = "ACTIONBUTTON1",
    ["PAD1"] = "ACTIONBUTTON1", ["SHIFT-pad2"] = "ACTIONBUTTON1", ["Z"] = "JUMP",
    ["X"] = "CLICK MSUFSuiteButton:LeftButton", ["Y"] = "MSUFSUITE_BAR9_BUTTON1" }
local captured = assert(N.Capture())
assert(captured.scope == "account" and captured.slots[1] == 101 and captured.slots[73] == 102 and captured.slots[109] == 103)
assert(captured.slots[145] == 102 and captured.slots[180] == 103 and captured.slots[121] == nil)
assert(captured.unsupportedSlots == 4 and captured.slots[2] == nil and captured.slots[3] == nil
    and captured.slots[4] == nil and captured.slots[5] == nil)
assert(captured.keys["1"] == "ACTIONBUTTON1" and captured.keys["ALT-1"] == "ACTIONBUTTON1"
    and captured.keys["CTRL-1"] == "ACTIONBUTTON1" and captured.keys.Y == "MSUFSUITE_BAR9_BUTTON1")
assert(captured.keys.PAD1 == nil and captured.keys["SHIFT-pad2"] == nil and captured.keys.Z == nil and captured.keys.X == nil)
assert(not N.AllowedSlot(132) and not N.AllowedSlot(144) and not N.AllowedSlot(181))
assert(not N.AllowedCommand("BONUSACTIONBUTTON1") and not N.ValidKey("SPACE BAR"))
assert(saves == 0 and pickups == 0 and placements == 0 and bindingWrites == 0)

Reset()
actions = { [1] = 102, [3] = "macro", [4] = 104 }
keys = { Q = "JUMP", X = "ACTIONBUTTON1", V = SECRET }
local record = { scope = "account", slots = { [1] = 101, [2] = 102, [3] = 103, [4] = 103, [5] = 104 },
    keys = { E = "ACTIONBUTTON1", R = "ACTIONBUTTON2", Q = "ACTIONBUTTON1", X = "ACTIONBUTTON1",
        V = "ACTIONBUTTON1" } }
local plan = assert(N.Plan(record, true, true))
assert(plan.skippedSlots == 3 and plan.skippedKeys == 2 and plan.backup.slots[2].before == false)
assert(plan.backup.keys.E.before == false and plan.backup.keys.X == nil)
assert(saves == 0 and pickups == 0 and placements == 0 and bindingWrites == 0)
local report = assert(N.Apply(plan))
assert(report.slots == 2 and report.keys == 2 and report.skippedSlots == 3 and report.skippedKeys == 2)
assert(actions[1] == 101 and actions[2] == 102 and actions[3] == "macro" and keys.Q == "JUMP" and not cursor)
assert(keys.E == "ACTIONBUTTON1" and keys.R == "ACTIONBUTTON2" and saves == 1)
assert(report.backup.slots[1].before == 102 and report.backup.slots[2].before == false)
local restored = assert(N.Restore(report.backup))
assert(restored.slots == 2 and restored.keys == 2 and restored.backup == nil)
assert(actions[1] == 102 and actions[2] == nil and keys.E == nil and keys.R == nil and saves == 2 and not cursor)

Reset()
local simple = { scope = "account", slots = { [1] = 101 }, keys = { E = "ACTIONBUTTON1" } }
plan = assert(N.Plan(simple, true, true))
specGroup = 2
local result, why = N.Apply(plan)
assert(result == nil and why == "stale" and placements == 0 and bindingWrites == 0)
specGroup = 1
combat = true
result, why = N.Apply(plan)
assert(result == nil and why == "combat" and placements == 0 and bindingWrites == 0)
combat, cursor = false, "item"
result, why = N.Capture()
assert(result == nil and why == "cursor" and cursor == "item")
cursor, gamepad = nil, true
result, why = N.Plan(simple, true, true)
assert(result == nil and why == "gamepad")
gamepad = false

actions[1], keys.E = 102, "JUMP"
report = assert(N.Apply(plan))
assert(report.slots == 0 and report.keys == 0 and report.skippedSlots == 1 and report.skippedKeys == 1)
assert(actions[1] == 102 and keys.E == "JUMP" and report.backup == nil)
actions[1], keys.E = nil, nil

wrongRank = 102
report = assert(N.Apply(plan))
assert(report.slots == 0 and report.keys == 1 and report.skippedSlots == 1 and not actions[1] and not cursor)
wrongRank, keys.E = nil, nil
failPlace, failKey = true, true
report = assert(N.Apply(plan))
assert(report.slots == 0 and report.keys == 0 and not actions[1] and not keys.E and not cursor)
failPlace, failKey = nil, nil

report = assert(N.Apply(plan))
actions[1], keys.E = 103, "JUMP"
restored = assert(N.Restore(report.backup))
assert(restored.slots == 0 and restored.keys == 0 and restored.skippedSlots == 1 and restored.skippedKeys == 1)
assert(actions[1] == 103 and keys.E == "JUMP" and not restored.backup)

Reset()
nativeEditor = "QuickKeybindFrame"
assert(N.BindingScope() == nil and N.Plan(simple, false, true).skippedKeys == 1)
nativeEditor = "SettingsPanel"
assert(N.BindingScope() == nil and N.Plan(simple, false, true).skippedKeys == 1)
nativeEditor = nil
report = assert(N.Apply(assert(N.Plan(simple, true, true))))
accountScope = false
restored = assert(N.Restore(report.backup))
assert(restored.slots == 1 and restored.keys == 0 and restored.backup.keys.E and not restored.backup.slots[1])
assert(keys.E == "ACTIONBUTTON1" and saves == 1)
accountScope = true
assert(N.Restore(restored.backup).keys == 1 and keys.E == nil and saves == 2)

Reset()
enterCombat = true
report = assert(N.Apply(assert(N.Plan(simple, true, true))))
assert(report.slots == 1 and report.keys == 0 and report.reason == "combat" and report.backup.slots[1])
assert(actions[1] == 101 and keys.E == nil and saves == 0)
Reset()
actions[109] = 102
independent = { [1] = 103, [3] = "macro", [4] = 104, [5] = 104, [12] = 101 }
captured = assert(N.Capture())
assert(captured.slots[109] == 102 and captured.independentSlots[1] == 103 and captured.independentSlots[12] == 101,
    "capture conflated the native form page and independent bar")
assert(captured.unsupportedSlots == 3 and not captured.independentSlots[3] and not captured.independentSlots[4],
    "capture accepted unknown or unsupported independent actions")
record = { scope = "account", slots = { [109] = 101 }, keys = {},
    independentSlots = { [1] = 102, [2] = 101, [3] = 103, [4] = 104, [5] = 103, [13] = 101 } }
plan = assert(N.Plan(record, true, false))
assert(plan.skippedSlots == 4 and plan.backup.independentSlots[1].before == 103
    and plan.backup.independentSlots[2].before == false, "independent preflight lost eligibility or undo")
report = assert(N.Apply(plan))
assert(report.slots == 3 and report.skippedSlots == 4 and actions[109] == 101
    and independent[1] == 102 and independent[2] == 101 and independent[3] == "macro")
assert(pickups == 1 and placements == 1, "independent changes touched the native cursor or action slots")
restored = assert(N.Restore(report.backup))
assert(restored.slots == 3 and not restored.backup and actions[109] == 102
    and independent[1] == 103 and independent[2] == nil, "undo did not restore the two storage owners")

local legacy = { scope = "account", slots = { [109] = 101 }, keys = {} }
report = assert(N.Apply(assert(N.Plan(legacy, true, false))))
assert(report.slots == 1 and actions[109] == 101 and independent[1] == 103,
    "old packets must only apply their native form page")
assert(N.Restore({ scope = "account", slots = { [109] = { before = 102, after = 101 } }, keys = {} }).slots == 1)

local independentOnly = { scope = "account", slots = {}, keys = {}, independentSlots = { [1] = 101, [2] = 102 } }
plan = assert(N.Plan(independentOnly, true, false))
independent[1] = 102
report = assert(N.Apply(plan))
assert(report.slots == 1 and report.skippedSlots == 1 and independent[1] == 102
    and not report.backup.independentSlots[1] and report.backup.independentSlots[2],
    "independent import overwrote an intervening edit")
independent[2] = 103
restored = assert(N.Restore(report.backup))
assert(restored.slots == 0 and restored.skippedSlots == 1 and independent[2] == 103,
    "independent undo overwrote an intervening edit")
assert(N.Apply(assert(N.Plan(independentOnly, false, true))).slots == 0 and independent[1] == 102,
    "keys-only import changed independent actions")

Reset()
actions[109], independent[1] = 102, 103
record = { scope = "account", slots = { [109] = 101 }, keys = {}, independentSlots = { [1] = 102 } }
report = assert(N.Apply(assert(N.Plan(record, true, false))))
enterCombat = true
restored = assert(N.Restore(report.backup))
assert(restored.slots == 1 and restored.reason == "combat" and actions[109] == 102 and independent[1] == 102
    and restored.backup.independentSlots[1], "combat interruption lost the independent undo")
cursor, combat, enterCombat = nil, false, nil
assert(N.Restore(restored.backup).slots == 1 and independent[1] == 103, "independent undo did not resume")

if stopWatching then
    local violations = stopWatching()
    assert(#violations == 0, table.concat(violations, "\n"))
end
print("Suite action-bar snapshot native contract passed")
