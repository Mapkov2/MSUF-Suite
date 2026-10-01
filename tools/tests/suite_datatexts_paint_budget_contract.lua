-- DataTexts paint cost budget, against the client model of
-- suite_minimap_harness.lua with the real Suite core and the FULL DataTexts
-- TOC loaded. One repaint per event (gold, bag space, durability) and per
-- sampled tick (FPS) is pinned with two deterministic measures, never
-- wall-clock time:
--   * Lua VM instructions per repaint (count hook on every instruction);
--   * kilobytes allocated per repaint, with the collector stopped.
-- Two bars: six equal places, and an auto-sized ("Fit text") bar whose
-- changed values relayout it.
--
-- Budgets are the measured baseline (2026-10-01, before the A-S3 DataTexts
-- restructuring) plus 2%; kilobytes get another 0.05 KB of rounding slack.
-- A change may only lower a number. Lower a budget after an optimization;
-- raise one only with a dated reason, never to hide a regression. A harness
-- change that moves the counts needs a new baseline.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1"

local BUDGETS = {
    { name = "gold", instructions = 3025, kilobytes = 2.68 },
    { name = "bag space", instructions = 1410, kilobytes = 0.91 },
    { name = "durability", instructions = 4856, kilobytes = 2.71 },
    { name = "sampled FPS tick", instructions = 3531, kilobytes = 2.90 },
    -- The account total (trackAltGold) also records this character's gold.
    { name = "gold with account total", instructions = 3168, kilobytes = 2.75, altGold = true },
    -- A bar shown only below full health follows every player health event
    -- (steady: the player stays injured).
    { name = "injured-only health", instructions = 385, kilobytes = 0.15, injured = true },
}

local state = { money = 1234567, free = 8, durability = 80, fps = 80, health = 1 }
local W = H.New(root, "Mainline", { beforeModules = function(world)
    local G = world.G
    G.GetFramerate = function() return state.fps end
    G.GetMoney = function() return state.money end
    G.GetInventoryItemDurability = function() return state.durability, 100 end
    G.GetGameTime = function() return 14, 3 end
    G.GetServerTime = function() return 1700000000 + world.now end
    G.GetNetStats = function() return 0, 0, 30, 50 end
    G.GetPhysicalScreenSize = function() return 1024, 768 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return state.free, 0 end,
    }
    G.UnitLevel = function() return 20 end
    G.UnitXP = function() return 200 end
    G.UnitXPMax = function() return 1000 end
    G.UnitGUID = function() return "Player-1" end
    G.UnitName = function() return "Alice" end
    G.GetRealmName = function() return "Realm" end
    G.Enum = { LuaCurveType = { Step = 1 } }
    G.C_CurveUtil = { CreateCurve = function()
        return { SetType = function() end, AddPoint = function() end }
    end }
    -- The test returns the curve's result: 1 below full health, else 0.
    G.UnitHealthPercent = function() return state.health end
end })
local S = W.S
W.LoadAddon("MSUF_Suite_DataTexts")
local M = assert(S.instances.dataTexts)
H.Enable(W, { infoFPS = false, infoClock = false, infoLocation = false })
assert(S.SetMany("dataTexts", {
    enabled = true, hideBlizzardBagBar = false,
    bar1Slot1 = 2, bar1Slot2 = 11, bar1Slot3 = 3, bar1Slot4 = 4, bar1Slot5 = 6, bar1Slot6 = 13,
    bar2Enabled = true, bar2Layout = 2, bar2Slot1 = 5, bar2Slot2 = 6, bar2Slot3 = 2, bar2Slot4 = 4,
}))
assert(M.active and M.bars[1].frame:IsShown() and M.bars[2].frame:IsShown(), "both DataTexts bars must show")

local function Measure(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    fn()
    debug.sethook()
    local kilobytes = collectgarbage("count") - before
    collectgarbage("restart")
    return ticks, kilobytes
end

-- Each repaint changes its value, so the paint path runs every time.
local REPAINTS = {
    ["gold"] = function(step)
        state.money = state.money + (step % 2 == 0 and 10000 or -10000)
        W.Event("PLAYER_MONEY")
    end,
    ["bag space"] = function(step)
        state.free = step % 2 == 0 and 7 or 8
        W.Event("BAG_UPDATE_DELAYED")
    end,
    ["durability"] = function(step)
        state.durability = step % 2 == 0 and 70 or 80
        W.Event("UPDATE_INVENTORY_DURABILITY")
    end,
    ["sampled FPS tick"] = function(step)
        state.fps = step % 2 == 0 and 41 or 59
        W.Advance(2)
    end,
}
REPAINTS["gold with account total"] = REPAINTS.gold
-- Below full health: each health event repaints the shown bar.
REPAINTS["injured-only health"] = function()
    state.health = 1
    W.Event("UNIT_HEALTH", "player")
end

local summary, failures = {}, {}
for _, case in ipairs(BUDGETS) do
    local repaint = REPAINTS[case.name]
    if case.altGold then assert(S.Set("dataTexts", "trackAltGold", true)) end
    if case.injured then assert(S.Set("dataTexts", "bar1LoadCondShowWhenInjured", true)) end
    repaint(1)
    repaint(2)
    local ticks, kilobytes = 0, 0
    local passes = 4
    for step = 1, passes do
        local t, k = Measure(function() repaint(step) end)
        ticks, kilobytes = ticks + t, kilobytes + k
    end
    ticks, kilobytes = ticks / passes, kilobytes / passes
    summary[#summary + 1] = string.format("%s %d instr/%.2f KB", case.name, ticks, kilobytes)
    if not MEASURE_ONLY then
        if ticks > case.instructions then
            failures[#failures + 1] = string.format("%s: %d instructions per repaint, budget %d",
                case.name, ticks, case.instructions)
        end
        if kilobytes > case.kilobytes then
            failures[#failures + 1] = string.format("%s: %.2f KB per repaint, budget %.2f",
                case.name, kilobytes, case.kilobytes)
        end
    end
end
assert(#failures == 0, table.concat(failures, "\n") .. "\nmeasured: " .. table.concat(summary, "; "))
print("DataTexts paint budget passed (" .. table.concat(summary, "; ") .. ")")
