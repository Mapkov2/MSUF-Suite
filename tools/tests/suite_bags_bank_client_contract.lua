-- The Suite bank view with the FULL Bags TOC loaded (client model of
-- suite_bags_harness.lua): the mode switch leaves Blizzard's bank controls
-- free, item actions never drive BankFrame, refunds are confirmed, arriving
-- item data reads no tab again and renamed tabs show their new names.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Overlaps(W, a, b)
    local al, ab, aw, ah = W.Rect(a)
    local bl, bb, bw, bh = W.Rect(b)
    return al < bl + bw and bl < al + aw and ab < bb + bh and bb < ab + ah
end

local function Bank(options)
    local W = H.New(root, options)
    W.sizes[0], W.sizes[6], W.sizes[12] = 4, 6, 6
    W.bankTabs[Enum.BankType.Character] = { { ID = 6, name = "Bank tab" } }
    W.bankTabs[Enum.BankType.Account] = { { ID = 12, name = "Warband tab" } }
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(40, { name = "Vendor trinket", class = 15 })
    W.Put(6, 1, 10, 4)
    W.Put(12, 1, 10, 6)
    W.Put(0, 1, 40, 1, { refundable = true })
    W.Apply()
    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    return W
end

local function Button(W, bag, slot)
    for _, button in ipairs(W.P.BankInventory.buttons) do
        local record = button.record
        if button.shown and record and record.bag == bag and record.slot == slot then return button end
    end
end

local function Click(W, button, mouseButton) W.Insecure(button.scripts.OnClick, button, mouseButton or "LeftButton") end

---------------------------------------------------------------- the mode switch
do
    local W = Bank({ config = { bankView = 1 } })
    local B = W.P.BankInventory
    assert(B.modeButton and B.modeButton.shown, "the bank view switch is missing in Blizzard's own bank view")
    assert(not Overlaps(W, B.modeButton, BankFrame.BankItemSearchBox)
        and not Overlaps(W, B.modeButton, BankFrame.BankPanel.AutoSortButton),
        "the bank view switch covers Blizzard's bank search box or Clean Up button")
end

---------------------------------------------------------------- item actions
do
    local W = Bank({ config = { bankView = 4 } })
    local B = W.P.BankInventory
    assert(B.active and B.frame.shown, "the Suite bank view did not open")
    local warband = Button(W, 12, 1)
    Click(W, warband)
    assert(not W.cursor and W.errors[#W.errors]:find("Warband Bank", 1, true),
        "a warband item must not move while Blizzard's Bank tab is selected")
    -- Hovering it out of combat lays one secure overlay over it that clicks
    -- Blizzard's Warband Bank tab from secure code, then picks the item up.
    W.RunScript(warband, "OnEnter")
    local tab = assert(W.P.BankActions.tabOverlay, "hovering a warband item attached no secure tab overlay")
    assert(tab.protected and tab.parent == W.UIParent and tab.shown and tab.points[1][2] == warband
        and tab:GetAttribute("type1") == "click" and tab:GetAttribute("useOnKeyDown") == false
        and tab:GetAttribute("clickbutton1") == W.BankFrame:GetTabButton(W.BankFrame.accountBankTabID),
        "the tab overlay is not a secure Warband Bank tab click over the hovered item")
    assert(tab.stateDrivers and tab.stateDrivers.visibility == "[combat] hide", "the tab overlay shows in combat")
    -- Moving onto the overlay keeps the item's tooltip.
    W.RunScript(tab, "OnEnter")
    assert(W.GameTooltip.owner == warband, "the tab overlay hid the warband item's tooltip")
    W.SecureClick(tab)
    assert(W.BankFrame:GetActiveBankType() == Enum.BankType.Account and W.cursor and W.cursor.id == 10,
        "clicking a warband item did not switch to the Warband Bank tab and pick it up")
    assert(not tab.shown and #tab.points == 0 and W.calls.setTab == 1 and #W.taint == 0,
        "the tab switch ran from Suite code or the overlay stayed on the item: " .. table.concat(W.taint, ", "))
    -- With the Warband Bank tab selected no overlay is needed.
    W.RunScript(warband, "OnEnter")
    assert(not tab.shown, "the tab overlay attached while the Warband Bank tab was selected")
    Click(W, warband)
    assert(not W.cursor and W.Item(12, 1).id == 10, "the item goes back on a second click")
    -- A refundable item entering the warband bank asks first.
    W.cursor = { id = 40, link = "item:40", count = 1, refundable = true, location = { bag = 0, slot = 1 } }
    local empty = Button(W, 12, 2)
    local pickups = #W.calls.pickups
    Click(W, empty)
    assert(#W.calls.pickups == pickups and W.cursor, "a refundable item entered the warband bank unasked")
    local confirm
    for _, frame in ipairs(W.frames) do
        if frame.text == END_REFUND then confirm = frame.parent end
    end
    assert(confirm and confirm.shown, "the refund question did not show Blizzard's END_REFUND text")
    local okay
    for _, child in ipairs(confirm.children) do if child.text == OKAY then okay = child end end
    W.Insecure(okay.scripts.OnClick, okay, "LeftButton")
    assert(#W.calls.pickups == pickups + 1 and W.Item(12, 2) and W.Item(12, 2).id == 40,
        "accepting the refund question must deposit the item")
    Click(W, Button(W, 6, 1), "RightButton")
    assert(W.calls.uses[#W.calls.uses][1] == 6, "a right click must withdraw the item")
    -- Splitting uses the Suite panel; Blizzard's split window stays closed.
    W.modified = "SPLITSTACK"
    Click(W, Button(W, 6, 1))
    W.modified = nil
    assert(W.P.StackSplitter.frame.shown and not StackSplitFrame:IsShown(),
        "a Suite bank stack must split in the Suite panel")
    -- Standing alone the panel takes any amount, like Blizzard's split
    -- window: arrows step it and a typed number sets it, within the stack.
    local panel = W.P.StackSplitter
    local function Child(text)
        for _, child in ipairs(panel.frame.children) do if child.text == text then return child end end
        error("no split panel control " .. text)
    end
    assert(panel.box.shown and panel.frame.height == 97 and panel.amount == 1 and panel.box.text == "1",
        "the Suite bank split panel offers no free amount")
    W.Insecure(Child(">").scripts.OnClick, Child(">"), "LeftButton")
    assert(panel.amount == 2 and panel.box.text == "2" and panel.take.text == "Pick up 2", "the up arrow did not step")
    panel.box.text = "3"
    W.Insecure(panel.box.scripts.OnTextChanged, panel.box, true)
    assert(panel.amount == 3 and panel.box.text == "3" and panel.take.text == "Pick up 3", "a typed amount was ignored")
    panel.box.text = "9"
    W.Insecure(panel.box.scripts.OnTextChanged, panel.box, true)
    assert(panel.amount == 4 and panel.box.text == "4", "a typed amount above the stack was not clamped")
    W.Insecure(Child("<").scripts.OnClick, Child("<"), "LeftButton")
    assert(panel.amount == 3, "the down arrow did not step")
    W.Insecure(panel.take.scripts.OnClick, panel.take, "LeftButton")
    assert(W.cursor and W.cursor.count == 3 and not panel.frame.shown, "the chosen amount was not picked up")
    W.cursor = nil
    assert(W.calls.setTab == 1 and #W.taint == 0,
        "Suite bank actions drove BankFrame or Blizzard's split window: " .. table.concat(W.taint, ", "))
    -- PLAYER_REGEN_DISABLED comes before the lockdown: the overlay lets go.
    W.BankFrame.BankPanel.bankType = Enum.BankType.Character
    local tab = W.P.BankActions.tabOverlay
    W.RunScript(Button(W, 12, 1), "OnEnter")
    assert(tab.shown, "the tab overlay did not attach again")
    W.Fire("PLAYER_REGEN_DISABLED")
    assert(not tab.shown and #tab.points == 0, "the combat start left the tab overlay on the bank view")
    W.combat = true
    W.RunScript(Button(W, 12, 1), "OnEnter")
    assert(not tab.shown, "a hover in combat attached the tab overlay")
    W.combat = false
    -- Closing the bank releases it too.
    W.RunScript(Button(W, 12, 1), "OnEnter")
    W.Native(function() W.BankFrame:Hide() end)
    assert(not tab.shown and #tab.points == 0, "a closed bank kept the tab overlay")
end

---------------------------------------------------------------- incremental bank reads
do
    local W = Bank({ config = { bankView = 4 } })
    W.Define(50, { name = "Late item", class = 15, cached = false })
    W.Put(12, 3, 50, 1)
    W.Fire("BAG_UPDATE", 12)
    W.Settle()
    local B = W.P.BankInventory
    local late = Button(W, 12, 3)
    assert(late and late.record.name == "50", "an uncached bank item shows its ID until its data arrives")
    W.data[50].cached = true
    local reads = W.calls.info
    W.Fire("GET_ITEM_INFO_RECEIVED", 50, true)
    W.Settle()
    assert(Button(W, 12, 3).record.name == "Late item" and W.calls.info == reads,
        "arriving item data must update the bank view without reading its tabs again")
    W.bankTabs[Enum.BankType.Account][1].name = "Renamed"
    W.Fire("BANK_TAB_SETTINGS_UPDATED", Enum.BankType.Account)
    W.Settle()
    local named = false
    for _, button in ipairs(B.categories) do
        if button.shown and button.text == "Renamed" then named = true end
    end
    assert(named, "a renamed bank tab kept its old name in the sidebar")
end

print("bank view client model: mode switch, item actions, refunds, splits, incremental reads and tab names passed")
