-- DataTexts on the live module (the shared harness): the clock settings take
-- effect at once, and the Friends and Secondary stat places update from their
-- events, one refresh per burst, and only while a place shows them.
-- The sources and settings themselves: suite_dt_progress_contract.lua.
local root = assert(arg[1], "repository root required")
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")

local state = { onlineWow = 2, onlineBnet = 3, haste = 20 }
local reads = { friends = 0, haste = 0 }
local W = H.New(root, "Mainline", { beforeModules = function(world)
    local G = world.G
    G.GetFramerate = function() return 60 end
    G.GetMoney = function() return 100000 end
    G.GetInventoryItemDurability = function() return 80, 100 end
    G.GetGameTime = function() return 14, 3 end
    G.GetServerTime = function() return 1700000000 + math.floor(world.now) end
    G.GetNetStats = function() return 0, 0, 30, 50 end
    G.GetPhysicalScreenSize = function() return 1024, 768 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end,
    }
    G.UnitLevel = function() return 20 end
    G.UnitXP = function() return 200 end
    G.UnitXPMax = function() return 1000 end
    G.UnitGUID = function() return "Player-1" end
    G.UnitName = function() return "Alice" end
    G.GetRealmName = function() return "Realm" end
    G.Enum = { LuaCurveType = { Step = 1 } }
    G.C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
    G.UnitHealthPercent = function() return 1 end
    G.TIME_TWELVEHOURAM, G.TIME_TWELVEHOURPM = "%d:%02d AM", "%d:%02d PM"
    G.BNGetNumFriends = function() reads.friends = reads.friends + 1; return 10, state.onlineBnet end
    G.C_FriendList = {
        IsLegacyFriendSystemEnabled = function() return true end,
        GetNumOnlineFriends = function() return state.onlineWow end,
    }
    G.GetHaste = function() reads.haste = reads.haste + 1; return state.haste end
    G.C_EventUtils = { IsEventValid = function() return true end }
end })
local S = W.S
W.LoadAddon("MSUF_Suite_DataTexts")
local M = assert(S.instances.dataTexts)
H.Enable(W, { infoFPS = false, infoClock = false, infoLocation = false })
local Suite = W.Suite
local INDEX = Suite.DataTextSourceIndex
assert(S.SetMany("dataTexts", {
    enabled = true, hideBlizzardBagBar = false,
    bar1Slot1 = INDEX.clock, bar1Slot2 = INDEX.friends, bar1Slot3 = INDEX.secondaryStat, bar1Slot4 = INDEX.none,
    bar1Slot5 = INDEX.none, bar1Slot6 = INDEX.none, bar1Slot3Stat = Suite.DataTextStat.HASTE,
}))
assert(M.active and M.bars[1].frame:IsShown(), "the DataTexts bar must show")
local slots = M.bars[1].slots
local function Listening(event)
    for _, frame in ipairs(W.frames) do
        if frame.events[event] then return true end
    end
    return false
end
-- The realm time is 14:03 and the realm second is 20 plus the seconds the harness has run.
eq(slots[1].text, "Time: 14:03", "the clock keeps its look")

-- Settings apply at once. The clock was due at the next minute (40 seconds
-- away): showing seconds samples it again right away, and a clock without
-- seconds does not tick every second.
W.Advance(10)
eq(slots[1].text, "Time: 14:03", "a clock without seconds is not sampled every second")
assert(S.Set("dataTexts", "clock24Hour", false))
eq(slots[1].text, "Time: 2:03 PM", "the 12-hour clock")
assert(S.Set("dataTexts", "clockSeconds", true))
W.Advance(.1)
eq(slots[1].text, "Time: 2:03:30 PM", "seconds show at once")
W.Advance(1)
eq(slots[1].text, "Time: 2:03:31 PM", "seconds tick every second")
W.Advance(2)
eq(slots[1].text, "Time: 2:03:33 PM", "seconds keep up")
assert(S.Set("dataTexts", "clockSeconds", false))
W.Advance(.1)
eq(slots[1].text, "Time: 2:03 PM", "seconds hide again")
W.Advance(5)
eq(slots[1].text, "Time: 2:03 PM", "and the clock waits for the minute")
assert(S.Set("dataTexts", "clock24Hour", true))
eq(slots[1].text, "Time: 14:03", "back to 24 hours")

-- Friends: the place shows the count, refreshes once per burst of events.
eq(slots[2].text, "Friends: 5", "online friends")
assert(Listening("FRIENDLIST_UPDATE") and Listening("BN_FRIEND_INFO_CHANGED"), "friends need their events")
state.onlineBnet = 7
local before = reads.friends
for _ = 1, 30 do W.Event("BN_FRIEND_INFO_CHANGED", 1) end
eq(slots[2].text, "Friends: 5", "an event repainted before the wait")
W.Advance(.5)
eq(slots[2].text, "Friends: 9", "the burst refreshed the place")
eq(reads.friends - before, 1, "a burst of 30 events read the friend count more than once")
state.onlineWow = 4
W.Event("FRIENDLIST_UPDATE")
W.Advance(.5)
eq(slots[2].text, "Friends: 11", "the character friends event")
-- Secondary stat: its unit events are the player's only.
eq(slots[3].text, "Haste: 20.0%", "the chosen stat")
assert(Listening("COMBAT_RATING_UPDATE") and Listening("MASTERY_UPDATE") and Listening("UNIT_STATS"), "stat events")
state.haste = 25
W.Event("COMBAT_RATING_UPDATE")
W.Advance(.2)
eq(slots[3].text, "Haste: 25.0%", "a rating change repaints the stat")
-- Without a social or stat place the events are released.
assert(S.SetMany("dataTexts", { bar1Slot2 = INDEX.none, bar1Slot3 = INDEX.none }))
assert(not Listening("FRIENDLIST_UPDATE") and not Listening("BN_FRIEND_INFO_CHANGED"),
    "friend events stayed registered without a Friends place")
assert(not Listening("COMBAT_RATING_UPDATE") and not Listening("UNIT_STATS"),
    "stat events stayed registered without a Secondary stat place")

print("datatexts places PASS")
