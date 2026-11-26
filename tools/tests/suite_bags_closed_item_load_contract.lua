local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

-- The harness dispatches scripts for a widget's own Show/Hide. Supply the
-- descendant transitions WoW dispatches when its parent changes visibility.
local function ParentVisibility(W, shown, ...)
    local frames = { ... }
    W.Native(function()
        W.UIParent:SetShown(shown)
        for _, frame in ipairs(frames) do
            local script = frame:GetScript(shown and "OnShow" or "OnHide")
            if script then script(frame) end
        end
    end)
end

local function NativeLevels(client)
    local W = H.New(root, { client = client,
        config = { inventoryView = 4, bankView = 1, showItemLevel = true, showBindBadge = false, showBankItemLevel = true } })
    W.sizes[0], W.sizes[6] = 1, 1
    W.Define(41, { name = "Bag helm", class = 4, equipLoc = "INVTYPE_HEAD", level = 0 })
    W.Define(42, { name = "Bank helm", class = 4, equipLoc = "INVTYPE_HEAD", level = 0 })
    W.Put(0, 1, 41)
    W.Put(6, 1, 42)
    local panel = W.BankFrame.BankPanel
    local button = W.NewWidget("Button", nil, panel, true)
    function button:GetBankTabID() return 6 end
    function button:GetContainerSlotID() return 1 end
    function button:Refresh() self.itemInfo = C_Container.GetContainerItemInfo(6, 1) end
    function panel:EnumerateValidItems()
        local sent = false
        return function()
            if not sent then sent = true return button end
        end
    end
    button:Refresh()
    W.Apply()
    W.OpenBags()
    W.OpenBank()
    W.Settle()
    local function Listening() return W.M.context.callbacks.GET_ITEM_INFO_RECEIVED ~= nil end
    assert(W.requested[41] == 1 and W.requested[42] == 1 and Listening(), "missing cold badge loads")
    ParentVisibility(W, false, W.CF, W.BankFrame, panel)
    assert(W.CF:IsShown() and not W.CF:IsVisible() and panel:IsShown() and not panel:IsVisible())
    assert(not Listening(), "ancestor-hidden windows retained the badge listener")
    W.M:UpdateVisible()
    W.M:UpdateBank()
    W.Fire("GET_ITEM_INFO_RECEIVED", 41, false)
    W.Fire("GET_ITEM_INFO_RECEIVED", 42, false)
    assert(not Listening() and W.requested[41] == 1 and W.requested[42] == 1, "ancestor-hidden labels requested data")
    ParentVisibility(W, true, W.CF, W.BankFrame, panel)
    W.Settle()
    assert(Listening() and W.requested[41] == 2 and W.requested[42] == 2, "ancestor reveal lost outstanding badge work")
    W.CloseBags()
    assert(Listening(), "closing the backpack silenced a native bank label")
    W.CloseBank()
    assert(not Listening(), "closed windows retained the badge item-data listener")
    W.Fire("GET_ITEM_INFO_RECEIVED", 41, false)
    W.Fire("GET_ITEM_INFO_RECEIVED", 42, false)
    W.OpenBags()
    W.Settle()
    assert(W.requested[41] == 3 and Listening(), "unheard backpack failure was never retried")
    W.OpenBank()
    W.Settle()
    assert(W.requested[42] == 3, "unheard bank failure was never retried")
    W.CloseBank()
    assert(Listening(), "closing the bank silenced a backpack label")
    W.items[6][1] = nil
    button:Refresh()
    W.OpenBank()
    W.Settle()
    assert(W.M.bankPending[42] == nil, "the bank still waited for an item removed while hidden")
    W.data[41].level = 391
    W.Fire("GET_ITEM_INFO_RECEIVED", 41, true)
    W.Settle()
    assert(W.M.overlays[W.CF.Items[1]].label:GetText() == "391", "recovered bag level missing")
    assert(not Listening(), "invisible bank retained stale pending work")
    W.config.enabled = false
    W.Apply()
    assert(not Listening(), "disabled bags retained a load listener")
end

local function IndexLoads(client)
    local W = H.New(root, { client = client, config = { inventoryView = 1, showItemLevel = false,
        showBindBadge = false, showRecent = false } })
    W.sizes[0] = 20
    W.Define(51, { name = "Late ore", cached = false })
    W.Put(0, 1, 51)
    W.Apply()
    W.OpenBags()
    W.Settle()
    assert(W.requested[51] == 1, "metadata cold request")
    W.CloseBags()
    W.EnterCombat()
    W.Fire("GET_ITEM_INFO_RECEIVED", 51, false)
    W.LeaveCombat()
    W.OpenBags()
    W.Settle()
    assert(W.requested[51] == 2, "an unheard metadata failure blocked a later attempt")
    W.Fire("GET_ITEM_INFO_RECEIVED", 51, false)
    W.P.InventoryView.Request()
    W.Settle()
    assert(W.requested[51] == 2, "unavailable metadata retried without opening")
    W.data[51].cached = true
    W.CloseBags()
    W.OpenBags()
    W.Settle()
    assert(W.P.InventoryView.index.items[1].name == "Late ore", "available metadata did not recover")

    local function WarmCost(count)
        local index = W.P.InventoryIndex.New()
        index.records = {}
        for i = 1, count do index.records[i] = { loaded = true } end
        local ticks = 0
        debug.sethook(function() ticks = ticks + 1 end, "", 1)
        W.P.InventoryIndex.Retry(index)
        debug.sethook()
        return ticks
    end
    assert(WarmCost(148) <= WarmCost(1) + 5, "reopening walks every resolved record")
end

local function BankSets(client)
    local W = H.New(root, { client = client, config = { bankView = 2, showEquipmentSetNames = true } })
    W.Apply()
    W.OpenBank()
    W.Settle()
    local bank = W.P.BankInventory
    assert(bank.active, "organized bank unavailable")
    W.P.InventoryView.Pause()
    local reads, get = 0, C_EquipmentSet.GetEquipmentSetIDs
    C_EquipmentSet.GetEquipmentSetIDs = function(...)
        reads = reads + 1
        return get(...)
    end
    for _, event in ipairs({ "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
        assert(bank.events:IsEventRegistered(event), "organized bank does not watch " .. event)
        local before = reads
        W.Fire(event, 1, true)
        W.Settle()
        assert(reads == before + 1, "organized bank did not refresh changed set locations")
    end
    local revision, setReads = bank.index.revision, reads
    bank.Request()
    ParentVisibility(W, false, W.BankFrame, W.BankFrame.BankPanel)
    W.Settle()
    bank.Request()
    W.Settle()
    assert(not bank.events:IsEventRegistered("BAG_UPDATE") and bank.index.revision == revision,
        "a queued bank flush revived the hidden bank's index or listeners")
    W.Fire("EQUIPMENT_SETS_CHANGED")
    ParentVisibility(W, true, W.BankFrame, W.BankFrame.BankPanel)
    W.Settle()
    assert(bank.index.revision == revision + 1 and reads == setReads + 1 and bank.events:IsEventRegistered("BAG_UPDATE"),
        "ancestor reveal did not restore organized bank freshness and listeners")
    W.CloseBank()
    assert(not bank.events:IsEventRegistered("EQUIPMENT_SETS_CHANGED") and not bank.events:IsEventRegistered("PLAYER_EQUIPMENT_CHANGED"),
        "closed bank still listens for equipment-set layout")
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    if not arg[2] or arg[2] == "native" then NativeLevels(client) end
    if not arg[2] or arg[2] == "index" then IndexLoads(client) end
    if not arg[2] or arg[2] == "bank" then BankSets(client) end
end
print("Bag and bank load lifecycle, warm index and independent bank set updates passed")
