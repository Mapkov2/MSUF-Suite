-- The reminder list R.BuildEntries makes, field by field, for configurations
-- that reach every kind of entry: class and group buffs, other classes'
-- notices, configured spells, items and weapon enchants, the automatic
-- consumables with and without stock, food notices, Rogue poison slots, the
-- map potion, Forever's ranked buff and campfire, and the twelve-entry cap.
-- GOLDEN was printed by the module before its entry constructors were
-- named (arg 2 "print" prints the current list).
local root = assert(arg[1], "repository root required")
local printOnly = arg[2] == "print"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

local known, inventory, bags, itemSpells, spellNames = {}, {}, {}, {}, {}
local roster, class, specID, currentMap = {}, "MAGE", 259, 300
Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 }, PowerType = { Mana = 0 },
    ItemClass = { Consumable = 0 }, ItemConsumableSubclass = { Fooddrink = 5 },
}
Constants = { InventoryConstants = { NumBagSlots = 4 } }
DifficultyUtil = { ID = { DungeonTimewalker = 24, RaidTimewalker = 33 } }
C_SpellBook = {
    IsSpellKnown = function(id) return known[id] == true end,
    IsSpellInSpellBook = function() return false end,
}
C_Spell = {
    GetSpellName = function(id) return spellNames[id] end,
    GetSpellTexture = function(id) return id end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and 16 or 0 end,
    GetContainerItemID = function(bag, slot) return bags[bag] and bags[bag][slot] end,
}
C_Item = {
    GetItemCount = function(id) return inventory[id] or 0 end,
    GetItemIconByID = function(id) return id end,
    -- Food is a Food & Drink consumable; 900003 is a shield, every other
    -- item a one-handed sword.
    GetItemInfoInstant = function(id)
        if itemSpells[id] then return id, "Consumable", "Food & Drink", "", 0, 0, 5 end
        if id == 900003 then return id, "Armor", "Shield", "INVTYPE_SHIELD", 0, 4, 0 end
        return id, "Weapon", "Sword", "INVTYPE_WEAPON", 0, 2, 0
    end,
    GetItemSpell = function(id) if itemSpells[id] then return "Use", itemSpells[id] end end,
    RequestLoadItemDataByID = function() end,
}
C_Map = { GetBestMapForUnit = function() return currentMap end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return specID end,
}
local weapons = { [16] = 900001 }
GetInventoryItemID = function(_, slot) return weapons[slot] end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return #roster end
UnitIsUnit = function(unit, other) return unit == other end
UnitClass = function(unit)
    if unit == "player" then return class, class end
    local token = roster[tonumber(unit:match("%d+") or 0)]
    return token, token
end

local S = {
    Public = function(value) return not (type(value) == "table" and value.secret) end,
    Install = function() end, Text = function(value) return value end,
}
local NS = { IsCombatLocked = function() return false end,
    Client = { isForever = false, modernEquipment = true, SupportsEvent = function() return true end } }
local private = { NS = NS, Suite = S }
Support.Load(root, "MSUF_Suite_BuffReminders", private, nil, { ["Bootstrap.lua"] = true })
local R = private.BuffReminders

local BASE = { classBuff = false, groupBuff = false, otherClassBuffs = false, spellIDs = "", items = "",
    mainHandItem = "", offHandItem = "", autoFlask = false, autoFood = false, autoRune = false,
    autoWeapon = false, autoRoguePoisons = false, restockNotice = false, campfireBuff = false,
    mapPotion = false, mapPotionMaps = "", mapPotionItem = "", flaskChoice = "", runeChoice = "",
    oilChoice = "", foodChoice = "" }
local function Owner(overrides)
    local config = {}
    for key, value in pairs(BASE) do config[key] = value end
    for key, value in pairs(overrides) do config[key] = value end
    return { config = config }
end

local function List(list)
    if not list then return "-" end
    local parts = {}
    for i = 1, #list do parts[i] = tostring(list[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local FIELDS = { "kind", "id", "aura", "slot", "poison", "poisonRank", "restock", "category",
    "group", "notice", "ranked", "spellName", "bit", "present", "actionID", "count" }
local function Describe(entries)
    local rows = {}
    for index, entry in ipairs(entries) do
        local parts = {}
        for i, field in ipairs(FIELDS) do parts[i] = field .. "=" .. tostring(entry[field]) end
        parts[#parts + 1] = "aliases=" .. List(entry.aliases)
        parts[#parts + 1] = "candidates=" .. List(entry.candidates)
        rows[index] = table.concat(parts, " ")
    end
    return table.concat(rows, "\n")
end

local scenarios = {}
local function Scenario(name, setup, overrides)
    scenarios[#scenarios + 1] = { name = name, setup = setup, overrides = overrides }
end
Scenario("mage buffs and configured entries", function()
    class, roster = "MAGE", { "PRIEST", "WARRIOR" }
    known = { [1459] = true }
    weapons = { [16] = 900001, [17] = 900002 }
end, { classBuff = true, groupBuff = true, otherClassBuffs = true, spellIDs = "777, 778,777",
    items = "123:888,124:889,bad", mainHandItem = "456", offHandItem = "457" })
Scenario("automatic consumables in stock", function()
    class, roster, known = "WARRIOR", {}, {}
    weapons = { [16] = 900001, [17] = 900002 }
    inventory = { [241324] = 2, [241325] = 1, [259085] = 3, [243733] = 1, [250010] = 1 }
    itemSpells = { [250010] = 1233738 }
    bags = { [0] = { [1] = 250010 } }
end, { autoFlask = true, autoFood = true, autoRune = true, autoWeapon = true, flaskChoice = "241325" })
Scenario("automatic consumables restocked", function()
    inventory, bags, itemSpells = {}, {}, {}
end, { autoFlask = true, autoFood = true, autoRune = true, autoWeapon = true, restockNotice = true,
    foodChoice = "250001" })
Scenario("food notice without restock", function() end, { autoFood = true })
Scenario("paladin imbue and shield", function()
    class, known = "PALADIN", { [433583] = true }
    weapons = { [16] = 900001, [17] = 900003 }
    inventory = { [243733] = 1 }
end, { autoWeapon = true })
Scenario("rogue assassination poisons", function()
    class, specID = "ROGUE", 259
    known = { [2823] = true, [315584] = true, [381664] = true, [381801] = true,
        [381637] = true, [5761] = true, [3408] = true }
    weapons = { [16] = 900001 }
end, { autoRoguePoisons = true, spellIDs = "2823" })
Scenario("rogue outlaw poisons", function()
    specID = 260
    known = { [2823] = true, [315584] = true, [8679] = true, [381637] = true }
end, { autoRoguePoisons = true })
Scenario("map potion out of stock", function()
    class, known, inventory, currentMap = "MAGE", {}, {}, 300
    itemSpells = { [124640] = 185394 }
end, { mapPotion = true, mapPotionMaps = "200, 300", mapPotionItem = "124640", restockNotice = true })
Scenario("forever ranked buff and campfire", function()
    NS.Client.isForever, NS.Client.modernEquipment = true, false
    class, roster, known, itemSpells = "PRIEST", { "MAGE" }, { [1243] = true }, {}
    spellNames = { [1243] = "Power Word: Fortitude", [R.CAMP_BENEFITS] = "Camp Benefits" }
end, { classBuff = true, groupBuff = true, otherClassBuffs = true, campfireBuff = true })
Scenario("twelve-entry cap", function()
    NS.Client.isForever, NS.Client.modernEquipment = false, true
    class, roster, known, spellNames = "MAGE", {}, { [1459] = true }, {}
end, { classBuff = true, spellIDs = "1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012",
    items = "123:888", mainHandItem = "456" })

local GOLDEN = {
    [1] = [[
kind=spell id=1459 aura=1459 slot=nil poison=nil poisonRank=nil restock=false category=class group=true notice=nil ranked=false spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1459,432778} candidates=-
kind=spell id=21562 aura=21562 slot=nil poison=nil poisonRank=nil restock=false category=class group=nil notice=true ranked=false spellName=nil bit=nil present=nil actionID=nil count=nil aliases={21562} candidates=-
kind=spell id=6673 aura=6673 slot=nil poison=nil poisonRank=nil restock=false category=class group=nil notice=true ranked=false spellName=nil bit=nil present=nil actionID=nil count=nil aliases={6673} candidates=-
kind=spell id=777 aura=777 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=778 aura=778 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=item id=123 aura=888 slot=nil poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=item id=124 aura=889 slot=nil poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=weapon id=456 aura=nil slot=16 poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=weapon id=457 aura=nil slot=17 poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
    [2] = [[
kind=item id=241325 aura=1235057 slot=nil poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1235057,1235108,1235110,1235111} candidates=-
kind=food id=250010 aura=nil slot=nil poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=item id=259085 aura=1264426 slot=nil poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1264426,1242347,1234969,453250,393438,347901} candidates=-
kind=weapon id=243733 aura=nil slot=16 poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=weapon id=243733 aura=nil slot=17 poison=nil poisonRank=nil restock=false category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
    [3] = [[
kind=item id=245933 aura=1235057 slot=nil poison=nil poisonRank=nil restock=true category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1235057,1235108,1235110,1235111} candidates=-
kind=food id=250001 aura=nil slot=nil poison=nil poisonRank=nil restock=true category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=item id=259085 aura=1264426 slot=nil poison=nil poisonRank=nil restock=true category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1264426,1242347,1234969,453250,393438,347901} candidates=-
kind=weapon id=243738 aura=nil slot=16 poison=nil poisonRank=nil restock=true category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=weapon id=243738 aura=nil slot=17 poison=nil poisonRank=nil restock=true category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
    [4] = [[
kind=food id=104280 aura=nil slot=nil poison=nil poisonRank=nil restock=false category=consumable group=nil notice=food ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
    [5] = [[
]],
    [6] = [[
kind=spell id=2823 aura=2823 slot=nil poison=lethal poisonRank=1 restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={2823,315584,381664,8679} candidates={2823,381664,315584}
kind=spell id=381664 aura=381664 slot=nil poison=lethal poisonRank=2 restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={2823,315584,381664,8679} candidates={2823,381664,315584}
kind=spell id=381637 aura=381637 slot=nil poison=nonlethal poisonRank=1 restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={381637,5761,3408} candidates={381637,5761,3408}
kind=spell id=5761 aura=5761 slot=nil poison=nonlethal poisonRank=2 restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={381637,5761,3408} candidates={381637,5761,3408}]],
    [7] = [[
kind=spell id=315584 aura=315584 slot=nil poison=lethal poisonRank=1 restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={2823,315584,381664,8679} candidates={315584,8679,2823}
kind=spell id=381637 aura=381637 slot=nil poison=nonlethal poisonRank=1 restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases={381637,5761,3408} candidates={381637}]],
    [8] = [[
kind=item id=124640 aura=185394 slot=nil poison=nil poisonRank=nil restock=true category=consumable group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
    [9] = [[
kind=spell id=1243 aura=1243 slot=nil poison=nil poisonRank=nil restock=false category=class group=true notice=nil ranked=true spellName=Power Word: Fortitude bit=nil present=nil actionID=nil count=nil aliases={1243,21562} candidates=-
kind=spell id=1459 aura=1459 slot=nil poison=nil poisonRank=nil restock=false category=class group=nil notice=true ranked=true spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1459,23028} candidates=-
kind=spell id=1229741 aura=1229741 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=camp ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
    [10] = [[
kind=spell id=1459 aura=1459 slot=nil poison=nil poisonRank=nil restock=false category=class group=false notice=nil ranked=false spellName=nil bit=nil present=nil actionID=nil count=nil aliases={1459,432778} candidates=-
kind=spell id=1001 aura=1001 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1002 aura=1002 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1003 aura=1003 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1004 aura=1004 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1005 aura=1005 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1006 aura=1006 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1007 aura=1007 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1008 aura=1008 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1009 aura=1009 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1010 aura=1010 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-
kind=spell id=1011 aura=1011 slot=nil poison=nil poisonRank=nil restock=false category=personal group=nil notice=nil ranked=nil spellName=nil bit=nil present=nil actionID=nil count=nil aliases=- candidates=-]],
}

local output = {}
for index, scenario in ipairs(scenarios) do
    scenario.setup()
    local owner = Owner(scenario.overrides)
    -- The second compile builds into the other buffer: both must agree.
    local first = Describe(R.BuildEntries(owner))
    owner.entries = R.BuildEntries(owner)
    local second = Describe(owner.entries)
    assert(first == second, scenario.name .. ": the two entry buffers disagree")
    if printOnly then
        output[#output + 1] = ("    [%d] = [[\n%s]],"):format(index, first)
    else
        assert(GOLDEN[index], scenario.name .. ": no golden list")
        assert(first == GOLDEN[index], scenario.name .. ": the reminder list changed\n" .. first
            .. "\nexpected\n" .. GOLDEN[index])
    end
end
if printOnly then
    print(table.concat(output, "\n"))
else
    print("Suite buff reminders entries: " .. #scenarios .. " reminder lists match field by field")
end
