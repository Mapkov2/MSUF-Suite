-- Bag refresh cost budget, against the client model of suite_bags_harness.lua
-- with the FULL Bags TOC loaded. A native bag refresh (Blizzard's
-- UpdateItems, the Suite post-hooks and the inventory view's next-frame
-- flush) is pinned with two deterministic measures, never wall-clock time:
--   * Lua VM instructions per refresh (count hook on every instruction);
--   * kilobytes allocated per refresh, with the collector stopped.
-- Inventory: a max-level character (backpack 20, four 36-slot bags).
--
-- Budgets are the measured baseline (2026-10-01, before the A-S3 Bags
-- restructuring) plus 2%; kilobytes get another 0.05 KB of rounding slack.
-- A change may only lower a number. Lower a budget after an optimization;
-- raise one only with a dated reason, never to hide a regression. A harness
-- change that moves the counts needs a new baseline.
-- Lowered 2026-10-01 (A-S3 S3.10): the bag font and the new-item flags
-- are read once per render.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local BUDGETS = {
    -- view = inventoryView: 1 All items, 3 Categories, 4 Blizzard grid.
    { name = "all items, unchanged", view = 1, instructions = 110655, kilobytes = 0.76 },
    { name = "all items, one bag changed", view = 1, change = true, instructions = 115385, kilobytes = 2.19 },
    { name = "categories, unchanged", view = 3, instructions = 128756, kilobytes = 1.73 },
    { name = "categories, one bag changed", view = 3, change = true, instructions = 133708, kilobytes = 3.18 },
    { name = "Blizzard grid, unchanged", view = 4, instructions = 44769, kilobytes = 0.24 },
    { name = "Blizzard grid, one bag changed", view = 4, change = true, instructions = 47773, kilobytes = 1.56 },
}
local MEASURE_ONLY = os.getenv("MSUF_BUDGET_MEASURE") == "1"

local function Inventory(view)
    local W = H.New(root, { config = { inventoryView = view, showBindBadge = true, desaturateJunk = true } })
    -- Blizzard's own UpdateItems, before the Suite hooks it.
    W.nativeUpdateItems = W.CF.UpdateItems
    W.sizes[0] = 20
    for bag = 1, 4 do W.sizes[bag] = 36 end
    for i = 1, 30 do W.Define(100 + i, { name = "Armor " .. i, equipLoc = "INVTYPE_CHEST", level = 600 + i, quality = 3 }) end
    for i = 1, 20 do W.Define(200 + i, { name = "Potion " .. i, class = 0, maxStack = 20 }) end
    for i = 1, 20 do W.Define(300 + i, { name = "Cloth " .. i, class = 7, maxStack = 200 }) end
    for i = 1, 10 do W.Define(400 + i, { name = "Junk " .. i, quality = 0 }) end
    W.Define(500, { name = "Warbound cloak", equipLoc = "INVTYPE_CLOAK", level = 610, quality = 4, bind = 8 })
    local slot = 0
    local function Next()
        slot = slot + 1
        local bag = slot <= 20 and 0 or 1 + math.floor((slot - 21) / 36)
        return bag, slot <= 20 and slot or (slot - 21) % 36 + 1
    end
    for i = 1, 30 do local bag, s = Next(); W.Put(bag, s, 100 + i, 1) end
    for i = 1, 20 do local bag, s = Next(); W.Put(bag, s, 200 + i, 5) end
    for i = 1, 20 do local bag, s = Next(); W.Put(bag, s, 300 + i, 40) end
    for i = 1, 10 do local bag, s = Next(); W.Put(bag, s, 400 + i, 1) end
    local bag, s = Next()
    W.Put(bag, s, 500, 1)
    -- 81 items, 83 empty slots.
    W.Apply()
    W.OpenBags()
    W.Settle()
    return W
end

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

local summary, failures = {}, {}
for _, case in ipairs(BUDGETS) do
    local W = Inventory(case.view)
    assert(W.M.active, case.name .. ": Bags did not start")
    local count = 3
    local function Refresh()
        if case.change then
            count = count == 3 and 4 or 3
            W.Put(3, 5, 201, count)
            W.BagChanged(3)
        else
            W.Native(function() W.CF:UpdateItems() end)
        end
        W.Settle()
    end
    -- Warm like an open bag: item data cached, labels created, model pooled.
    Refresh()
    Refresh()
    local function Native()
        W.Native(W.nativeUpdateItems, W.CF)
    end
    local ticks, kilobytes = 0, 0
    local passes = 4
    for _ = 1, passes do
        local t, k = Measure(Refresh)
        local nt, nk = Measure(Native)
        ticks, kilobytes = ticks + t - nt, kilobytes + k - nk
    end
    ticks, kilobytes = ticks / passes, kilobytes / passes
    summary[#summary + 1] = string.format("%s %d instr/%.2f KB", case.name, ticks, kilobytes)
    if not MEASURE_ONLY then
        if ticks > case.instructions then
            failures[#failures + 1] = string.format("%s: %d instructions per refresh, budget %d",
                case.name, ticks, case.instructions)
        end
        if kilobytes > case.kilobytes then
            failures[#failures + 1] = string.format("%s: %.2f KB per refresh, budget %.2f",
                case.name, kilobytes, case.kilobytes)
        end
    end
end
assert(#failures == 0, table.concat(failures, "\n") .. "\nmeasured: " .. table.concat(summary, "; "))
print("bag refresh budget passed (" .. table.concat(summary, "; ") .. ")")
