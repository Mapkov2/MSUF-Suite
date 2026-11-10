local root = assert(arg[1], "repository root required")
local path = arg[2] or root .. "/MSUF_Suite_QualityOfLife/LootRollData.lua"
local Secrets = dofile(arg[3] or root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
for _, name in ipairs({ "Public", "Finite", "Key", "Positive", "PublicTable", "True" }) do
    Secrets.GUARD_NAMES.falsy[name] = true
end
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

Enum = { EncounterLootDropRollState = {
    NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5,
} }
RAID_CLASS_COLORS = { MAGE = { colorStr = "ff40c7eb" } }
local S = { Public = function(value) return not issecretvalue(value) end }
function S.Finite(value)
    return S.Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
function S.PublicText(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
local private = { Suite = S }
assert(loadfile(path))("MSUF_Suite_QualityOfLife", private)
local D = assert(private.LootRollData)
local secretNumber, secretString, secretTable = Secrets.New("number"), Secrets.New("string"), Secrets.New("table")
local rolls, times, drops, infos, getterCalls = {}, {}, {}, {}, 0
local itemName, itemQuality, itemLevel, itemIcon, detailed = "Cached item", 4, 110, 9876, 123
GetLootRollItemInfo = function(id)
    getterCalls = getterCalls + 1
    return unpack(rolls[id] or {}, 1, 13)
end
GetLootRollItemLink = function(id) return rolls[id] and "item:loot:" .. id or nil end
GetLootRollTimeLeft = function(id) return times[id] end
C_Item = {
    GetItemInfo = function(link)
        assert(not issecretvalue(link), "secret item link reached Lua lookup")
        return itemName, link, itemQuality, itemLevel, nil, nil, nil, nil, nil, itemIcon
    end,
    GetDetailedItemLevelInfo = function(link)
        assert(not issecretvalue(link), "secret item link reached detailed-level lookup")
        return detailed
    end,
}
local keyLists = {}
C_LootHistory = {
    GetSortedInfoForDrop = function(encounter, key)
        assert(not issecretvalue(encounter) and not issecretvalue(key), "secret history key reached lookup")
        return drops[encounter] and drops[encounter][key]
    end,
    GetSortedDropsForEncounter = function(encounter) return keyLists[encounter] end,
    GetAllEncounterInfos = function() return infos end,
}

local stopWatch = Secrets.Watch(path, { strict = true })
rolls[7] = { 1234, "Live item", 2, 3, true, true, false, true, nil, nil, nil, nil, true }
times[7] = 45000
local entry = D.ReadRoll(7, 90000, 100)
Check(entry and entry.endsAt == 145, "remaining milliseconds must become seconds and override full duration")
Check(entry.duration == 90, "full duration supplies a stable seconds-scale timer maximum")
Check(entry.name == "Live item" and entry.icon == 1234 and entry.quality == 3 and entry.count == 2,
    "live item identity and quality must not be overwritten by cached base metadata")
Check(entry.itemLevel == 123 and entry.bindOnPickUp and entry.canNeed and not entry.canGreed
    and entry.canDisenchant and entry.canTransmog, "live flags and detailed item level")
Check(entry.counts[0] == 0 and entry.counts[4] == 0 and not entry.finished, "initial decision state")
times[7] = nil
Check(D.ReadRoll(7, 90000, 100).endsAt == 190, "missing remaining time uses supplied duration")
Check(D.ReadRoll(7, nil, 100) == nil, "unknown deadline must not fabricate a live roll")
times[7] = 0
Check(D.ReadRoll(7, 90000, 100) == nil, "zero time left is expired even when a full duration is supplied")
times[7] = -1
Check(D.ReadRoll(7, 90000, 100) == nil, "negative time left is expired rather than restarted")
times[7] = secretNumber
Check(D.ReadRoll(7, 30000, 100).endsAt == 130, "secret remaining time is not used in arithmetic")
local before = getterCalls
Check(D.ReadRoll(secretNumber, 30000, 100) == nil and getterCalls == before, "secret roll ID rejected before getter")
Check(D.ReadRoll(7, 30000, secretNumber) == nil, "secret clock rejected")
times[7] = 10000
rolls[7][2] = secretString
Check(D.ReadRoll(7, 30000, 100) == nil, "secret live name is not displayed")
rolls[7][2], rolls[7][1], rolls[7][4], rolls[7][6] = "Live item", secretNumber, secretNumber, secretTable
detailed, itemLevel, itemQuality, itemIcon = secretNumber, secretNumber, secretNumber, secretNumber
entry = D.ReadRoll(7, nil, 100)
Check(entry and not entry.canNeed and entry.quality == nil and entry.itemLevel == nil and entry.icon == nil,
    "secret metadata and eligibility fail closed without leaking into the view")
itemName, itemQuality, itemLevel, itemIcon, detailed = "Cached item", 4, 110, 9876, nil
Check(D.ReadRoll(7, nil, 100).itemLevel == 110, "base item level remains an optional cache fallback")
Check(D.ReadRoll(7, nil, 100).duration == 10, "remaining duration supplies the maximum when full duration is unknown")

for _, field in ipairs({ "lootListID", "lootListKey" }) do
    local info = { itemHyperlink = "item:history", rollInfos = {
        { playerName = "Main", playerClass = "MAGE", state = 0 },
        { playerName = "Off", state = 1, isSelf = true },
        { playerName = "Mog", state = 2 },
        { playerName = "Greed", state = 3 },
        { playerName = "Undecided", state = 4 },
        { playerName = "Pass", state = 5 },
    }, currentLeader = { playerName = "Main", playerClass = "MAGE", state = 0, roll = 88 },
        startTime = 90, duration = 120 }
    info[field] = 11
    drops[1], keyLists[1] = { [11] = info }, { info }
    entry = D.ReadDrop(1, 11)
    Check(entry.counts[1] == 2 and entry.counts[2] == 1 and entry.counts[4] == 1 and entry.counts[0] == 1,
        field .. ": map main/off need, greed, transmog and pass to action keys")
    Check(entry.counts[3] == 0 and not entry.rollNames[0]:find("Undecided", 1, true),
        field .. ": pending choice is not a pass and history cannot invent disenchant")
    Check(entry.selfChoice == 1 and entry.status == "leader" and not entry.finished and entry.statusRoll == 88,
        field .. ": self choice and pending leader stay separate from completed winner")
    Check(entry.statusName == "|cff40c7ebMain|r" and entry.rollNames[1]:find("|cff40c7ebMain|r", 1, true),
        field .. ": class-color names in status and participant tooltip")
    info.isTied = true
    entry = D.ReadDrop(1, 11)
    Check(entry.status == "waiting" and entry.statusName == nil, field .. ": ties do not invent a unique leader")
    info.isTied = secretTable
    entry = D.ReadDrop(1, 11)
    Check(entry.status == "waiting" and entry.statusName == nil, field .. ": unreadable tie state withholds the leader")
    info.isTied = nil
    info.winner = { playerName = "Winner", state = 3, roll = 99 }
    entry = D.ReadDrop(1, 11)
    Check(entry.finished and entry.status == "winner" and entry.statusName == "Winner" and entry.statusChoice == 2,
        field .. ": final winner wins over provisional leader")
    info.winner, info.currentLeader, info.allPassed = nil, nil, true
    entry = D.ReadDrop(1, 11)
    Check(entry.finished and entry.status == "allPassed", field .. ": all-pass is a completed outcome")
    local out = { 900, 901, 902 }
    Check(D.EncounterKeys(1, out) == out and #out == 1 and out[1] == 11,
        field .. ": refill supplied key buffer without stale tail")
    info.itemHyperlink = secretString
    Check(D.ReadDrop(1, 11) == nil, field .. ": secret history hyperlink rejected")
    info.itemHyperlink, info.rollInfos, info.allPassed = "item:history", secretTable, secretTable
    info.winner, info.currentLeader = secretTable, secretTable
    entry = D.ReadDrop(1, 11)
    Check(entry and not entry.finished and entry.status == "waiting" and entry.counts[1] == 0,
        field .. ": secret nested result and roll tables stay unknown")
    info.rollInfos = { { playerName = secretString, state = secretNumber, isSelf = secretTable },
        { playerName = secretString, playerClass = secretString, state = 3, isSelf = true } }
    entry = D.ReadDrop(1, 11)
    Check(entry.counts[2] == 1 and entry.selfChoice == 2 and entry.rollNames[2] == "",
        field .. ": known decision can be counted without revealing a secret name")
    keyLists[1] = secretTable
    Check(#D.EncounterKeys(1, out) == 0, field .. ": unreadable key list clears old values")
end

Check(D.ReadDrop(secretNumber, 1) == nil and D.ReadDrop(1, secretNumber) == nil, "secret history identity rejected")
drops[1][12] = secretTable
Check(D.ReadDrop(1, 12) == nil, "secret history object rejected before indexing")
local longRolls = {}
for i = 1, 80 do longRolls[i] = { playerName = "Player" .. i, state = 3 } end
drops[1][12] = { itemHyperlink = "item:many", rollInfos = longRolls }
entry = D.ReadDrop(1, 12)
local _, lineCount = entry.rollNames[2]:gsub("\n", "\n")
Check(lineCount < 40 and not entry.rollNames[2]:find("Player41", 1, true), "participant tooltips are bounded")
itemName = nil
entry = D.ReadDrop(1, 12)
Check(entry.name == entry.link, "uncached history preserves a readable hyperlink in the name slot")
itemName = "Cached item"
keyLists[1] = {}
for i = 1, 300 do keyLists[1][i] = { lootListKey = i } end
Check(#D.EncounterKeys(1, {}) == 128, "initial history-key expansion is bounded")
infos = {}
for i = 1, 12 do infos[i] = { encounterID = i, startTime = (13 - i) * 100 } end
infos[13], infos[14] = secretTable, { encounterID = secretNumber, startTime = 9999 }
local out = { 900, 901 }
Check(D.EncounterIDs(out) == out and #out == 8 and out[1] == 1 and out[8] == 8,
    "newest eight encounters fill the caller buffer, ignoring secret records")
infos = secretTable
Check(#D.EncounterIDs(out) == 0, "unreadable encounter list clears old values")
local violations = stopWatch()
Check(#violations == 0, table.concat(violations, "\n"))
print("PASS loot-roll data: " .. checks .. " checks including strict secrets and both history keys")
