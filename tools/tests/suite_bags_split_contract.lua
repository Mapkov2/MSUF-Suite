-- Stack splitting with the FULL Bags TOC loaded (client model of
-- suite_bags_harness.lua): the Suite panel never writes, calls or hides
-- Blizzard's StackSplitFrame; Stop always closes an orphaned panel.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Bags(options)
    local W = H.New(root, options)
    W.sizes[0], W.sizes[1] = 8, 4
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Put(0, 1, 10, 10)
    W.Apply()
    W.OpenBags()
    W.Settle()
    return W
end

local function ButtonFor(W, bag, slot)
    for _, button in W.CF:EnumerateValidItems() do
        if button:GetBagID() == bag and button:GetID() == slot then return button end
    end
end

local function Panel(W) return W.P.StackSplitter end

local function Click(W, button) W.Insecure(button.scripts.OnClick, button, "LeftButton") end

local function Preset(W, text)
    for _, child in ipairs(Panel(W).frame.children) do
        if child.text == text then return child end
    end
    error("no split preset " .. text)
end

---------------------------------------------------------------- pick up
do
    local W = Bags()
    local owner = ButtonFor(W, 0, 1)
    W.ShiftClick(owner)
    local panel = Panel(W)
    assert(panel.frame and panel.frame.shown and panel.attached, "the Suite panel did not join Blizzard's split window")
    -- Beside Blizzard's window its own arrows and typing set the amount.
    assert(not panel.box.shown and panel.frame.height == 69, "the attached panel repeats Blizzard's amount controls")
    Click(W, Preset(W, "5"))
    assert(panel.take.text == "Pick up 5" and panel.auto.text == "Auto split by 5", "presets must set the Suite amount")
    W.SplitType(3)
    assert(panel.amount == 3, "typing in Blizzard's window must set the Suite amount as well")
    Click(W, Preset(W, "Half"))
    assert(panel.amount == 5, "Half takes half of the stack")
    Click(W, panel.take)
    local split = W.calls.splits[#W.calls.splits]
    assert(split and split[1] == 0 and split[2] == 1 and split[3] == 5 and W.cursor and W.cursor.count == 5,
        "Pick up must split the chosen amount onto the cursor")
    assert(#W.taint == 0, "the Suite wrote to or called Blizzard's split window: " .. table.concat(W.taint, ", "))
    -- The player places the stack: Blizzard's own click closes its window.
    W.Native(function() ButtonFor(W, 1, 1).scripts.OnClick(ButtonFor(W, 1, 1), "LeftButton") end)
    assert(not StackSplitFrame:IsShown() and not panel.frame.shown and W.Item(1, 1).count == 5,
        "placing the stack must close Blizzard's window and the panel")
    assert(#W.taint == 0, "closing the split tainted it: " .. table.concat(W.taint, ", "))
end

---------------------------------------------------------------- auto split while a key is held
do
    local W = Bags()
    W.ShiftClick(ButtonFor(W, 0, 1))
    -- The player holds W: StackSplitFrame captured the key (OnKeyDown) and
    -- its OnHide releases it with RunBinding(..., "up").
    W.SplitHoldKey("W")
    local panel = Panel(W)
    Click(W, Preset(W, "5"))
    Click(W, panel.auto)
    W.Settle(40)
    assert(not W.P.AutoSplit.job and W.Item(0, 1).count == 5 and W.Item(0, 2) and W.Item(0, 2).count == 5,
        "auto split did not split the stack into the chosen amount")
    assert(#W.taint == 0, "auto split released a held key or hid Blizzard's window from Suite code: "
        .. table.concat(W.taint, ", "))
    W.SplitCancel()
    assert(not panel.frame.shown and #W.taint == 0, "Blizzard's cancel closes the panel too")
end

---------------------------------------------------------------- Stop
do
    local W = Bags()
    W.ShiftClick(ButtonFor(W, 0, 1))
    local panel = Panel(W)
    Click(W, Preset(W, "1"))
    Click(W, panel.auto)
    assert(W.P.AutoSplit.job, "auto split did not start")
    W.SplitCancel()
    assert(panel.frame.shown, "the panel must stay while a split runs, so Stop stays reachable")
    local stop
    for _, child in ipairs(panel.frame.children) do if child.text == "Stop" then stop = child end end
    Click(W, stop)
    assert(not W.P.AutoSplit.job and not panel.frame.shown, "Stop must end the split and close the orphaned panel")
end

---------------------------------------------------------------- reagent bag
do
    -- Bags 0-1 full, only the reagent bag (reporting family 0) has room.
    local W = H.New(root)
    W.sizes[0], W.sizes[1], W.sizes[5] = 2, 0, 4
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(30, { name = "Ore", class = 7, maxStack = 200, reagent = true })
    W.Put(0, 1, 10, 10)
    W.Put(0, 2, 30, 50)
    W.Apply()
    local Split = W.P.SplitInventory
    local potion = Split.Destinations({ kind = "bag", bag = 0, slot = 1 }, "item:10")
    assert(#potion == 0, "a non-reagent must never be planned into the reagent bag")
    local ore = Split.Destinations({ kind = "bag", bag = 0, slot = 2 }, "item:30")
    assert(#ore == 4 and ore[1].bag == 5, "crafting reagents may use the reagent bag")
    local started, reason = W.P.AutoSplit.Start({ GetBagID = function() return 0 end,
        GetID = function() return 1 end }, 2)
    assert(not started and reason == "full", "auto split must report no room instead of trying the reagent bag")
end

print("stack split: Suite-owned amounts, pick up, auto split with held keys, Stop and the reagent bag passed")
