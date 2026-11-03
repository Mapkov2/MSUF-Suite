-- Real Bags TOC and native lifecycle on both clients: a failed item lookup
-- can recover on reopening, and uncached worn equipment is never empty gear.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local selected = arg[2]

local function Item(W, id)
    for _, item in ipairs(W.P.InventoryView.index.items) do
        if item.itemID == id then return item end
    end
    error("item missing: " .. id)
end

local function Arrow(W, id)
    local marker = W.P.InventoryDetails.markers[Item(W, id).button]
    return marker ~= nil and marker.shown == true
end

local function Repaint(W)
    W.Native(function() W.CF:UpdateItems() end)
    W.Settle()
end

local function Metadata(client)
    local W = H.New(root, { client = client, config = { inventoryView = 3, mergeStacks = false,
        showItemLevel = false, showBindBadge = false, showRecent = false, hideEmptyCategories = true,
        groupEquipmentSlots = false } })
    W.sizes[0] = 2
    W.Define(20, { name = "Recovered Helm", class = 4, subclass = 1, equipLoc = "INVTYPE_HEAD", cached = false })
    W.Define(10, { name = "Bread", class = 0 })
    W.Put(0, 1, 20)
    W.Put(0, 2, 10)
    W.Apply()
    W.OpenBags()
    W.Settle()
    local warm = Item(W, 10)
    local version = warm.version
    assert(W.requested[20] == 1 and not Item(W, 20).loaded, client .. ": cold lookup not requested once")
    W.Fire("GET_ITEM_INFO_RECEIVED", 20, false)
    W.Settle()
    Repaint(W)
    assert(W.requested[20] == 1, client .. ": failed metadata retried on a normal repaint")
    W.CloseBags()
    W.OpenBags()
    W.Settle()
    assert(W.requested[20] == 2, client .. ": unchanged native bag reopening did not retry failed metadata")
    assert(Item(W, 10) == warm and warm.version == version and warm.name == "Bread",
        client .. ": retry invalidated an already loaded record")
    Repaint(W)
    W.Fire("GET_ITEM_INFO_RECEIVED", 20, false)
    W.Settle()
    Repaint(W)
    assert(W.requested[20] == 2, client .. ": repeated failure started an item request loop")
    W.CloseBags()
    W.OpenBags()
    W.Settle()
    assert(W.requested[20] == 3, client .. ": second explicit reopening did not retry")
    W.data[20].cached = true
    W.Fire("GET_ITEM_INFO_RECEIVED", 20, true)
    W.Settle()
    assert(Item(W, 20).loaded and Item(W, 20).name == "Recovered Helm"
        and W.P.InventoryView.model.groupsByKey.equipment, client .. ": retry did not recover metadata/category")
    W.CloseBags()
    W.OpenBags()
    W.Settle()
    assert(W.requested[20] == 3, client .. ": loaded metadata requested again on reopening")
    W.config.enabled = false
    W.Apply()
    assert(next(W.P.InventoryView.index.pending) == nil, client .. ": disabling retained pending metadata")
end

local function Bank(client)
    local W = H.New(root, { client = client, config = { bankView = 1, showBankItemLevel = true } })
    W.sizes[6] = 1
    W.Define(40, { name = "Bank Helm", equipLoc = "INVTYPE_HEAD", class = 4, subclass = 1, level = 0 })
    W.Put(6, 1, 40)
    local panel = W.BankFrame.BankPanel
    local button = W.NewWidget("Button", nil, panel, true)
    function button:GetBankTabID() return 6 end
    function button:GetContainerSlotID() return 1 end
    function button:Refresh() self.itemInfo = C_Container.GetContainerItemInfo(6, 1) end
    function panel:EnumerateValidItems()
        local emitted = false
        return function()
            if emitted then return nil end
            emitted = true
            return button
        end
    end
    button:Refresh()
    W.Apply()
    W.OpenBank()
    W.Settle()
    assert(W.requested[40] == 1, client .. ": native bank did not request the missing level once")
    W.Fire("GET_ITEM_INFO_RECEIVED", 40, false)
    W.Settle()
    W.Native(function() panel:GenerateItemSlotsForSelectedTab(); button:Refresh() end)
    assert(W.requested[40] == 1, client .. ": bank tab/button repaint retried a failed load")
    W.CloseBank()
    W.OpenBank()
    W.Settle()
    assert(W.requested[40] == 2, client .. ": native bank close/reopen did not retry the failed level")
    W.Fire("GET_ITEM_INFO_RECEIVED", 40, false)
    W.Native(function() panel:GenerateItemSlotsForSelectedTab(); button:Refresh() end)
    W.Settle()
    assert(W.requested[40] == 2, client .. ": second native bank failure started a retry loop")
    W.CloseBank()
    W.OpenBank()
    W.Settle()
    assert(W.requested[40] == 3, client .. ": next native bank opening did not retry once")
    W.data[40].level = 500
    W.Fire("GET_ITEM_INFO_RECEIVED", 40, true)
    W.Settle()
    local label = W.M.bankOverlays[button].label
    assert(label.shown and label.text == "500", client .. ": successful bank retry did not restore its label")
    W.CloseBank()
    W.OpenBank()
    W.Settle()
    assert(W.requested[40] == 3, client .. ": resolved bank item requested again")
    W.config.enabled = false
    W.Apply()
    W.CloseBank()
    W.OpenBank()
    W.Fire("GET_ITEM_INFO_RECEIVED", 40, true)
    W.Settle()
    assert(not label.shown and W.requested[40] == 3 and next(W.M.bankPending) == nil,
        client .. ": disabled native bank levels retained work or a label")
end


local function Equipment(client)
    local secret = {}
    local W = H.New(root, { client = client, isSecret = function(value) return value == secret end,
        config = { inventoryView = 1, mergeStacks = false, showUpgradeMarker = true } })
    W.sizes[0] = 3
    local kinds = { [20] = "INVTYPE_HEAD", [21] = "INVTYPE_FINGER", [22] = "INVTYPE_WEAPON",
        [25] = "INVTYPE_HEAD", [26] = "INVTYPE_FINGER", [27] = "INVTYPE_FINGER",
        [28] = "INVTYPE_WEAPON", [29] = "INVTYPE_WEAPON" }
    for id, equipLoc in pairs(kinds) do
        W.Define(id, { name = "Gear " .. id, class = 4, subclass = equipLoc == "INVTYPE_HEAD" and 1 or 0,
            equipLoc = equipLoc, quality = 4, level = id < 25 and 300 or 450 })
    end
    for slot = 1, 3 do W.Put(0, slot, 19 + slot) end
    W.worn[1], W.worn[11], W.worn[12], W.worn[16], W.worn[17] = "item:25", "item:26", "item:27", "item:28", "item:29"
    local unknown, hidden = { [25] = true, [27] = true, [29] = true }, { [12] = true, [17] = true }
    local readLink, readID, readLevel = GetInventoryItemLink, GetInventoryItemID, C_Item.GetDetailedItemLevelInfo
    local links, ids, levels = 0, 0, 0
    GetInventoryItemLink = function(unit, slot)
        links = links + 1
        if hidden[slot] then return nil end
        return readLink(unit, slot)
    end
    GetInventoryItemID = function(unit, slot)
        ids = ids + 1
        if W.worn[slot] == secret then return secret end
        return readID(unit, slot)
    end
    C_Item.GetDetailedItemLevelInfo = function(link)
        levels = levels + 1
        if unknown[tonumber(link:match("item:(%d+)"))] then return nil end
        return readLevel(link)
    end
    W.Apply()
    W.OpenBags()
    W.Settle()
    assert(not Arrow(W, 20) and not Arrow(W, 21) and not Arrow(W, 22),
        client .. ": unknown equipped metadata was treated as an empty slot")
    assert(W.requested[25] == 1 and W.requested[27] == 1 and W.requested[29] == 1,
        client .. ": unresolved equipped items were not requested once each")
    -- Cold trade: 16 links, with one ID read only for each unavailable level
    -- (14 here: 11 empty slots plus three occupied, unresolved slots).
    assert(links == 16 and ids == 14, client .. ": unbounded cold equipment discovery")
    local beforeLinks, beforeIDs, beforeLevels = links, ids, levels
    for _ = 1, 3 do Repaint(W) end
    W.Fire("GET_ITEM_INFO_RECEIVED", 9999, true)
    W.Fire("ITEM_DATA_LOAD_RESULT", 9999, true)
    W.Fire("GET_ITEM_INFO_RECEIVED", secret, true)
    W.Fire("ITEM_DATA_LOAD_RESULT", 25, secret)
    W.Fire("GET_ITEM_INFO_RECEIVED", 25, false)
    W.Fire("ITEM_DATA_LOAD_RESULT", 25, false)
    W.Settle()
    assert(links == beforeLinks and ids == beforeIDs and levels == beforeLevels and W.requested[25] == 1,
        client .. ": repaint, unrelated/secret item event or failure invalidated the equipment cache")
    -- An early successful notification may precede the detailed level. Keep
    -- waiting for the second native event, without requesting in a loop.
    W.Fire("GET_ITEM_INFO_RECEIVED", 25, true)
    W.Settle()
    assert(not Arrow(W, 20) and W.requested[25] == 1, client .. ": early success restarted the item request")
    unknown[25] = nil
    W.Fire("ITEM_DATA_LOAD_RESULT", 25, true)
    W.Settle()
    assert(not Arrow(W, 20), client .. ": higher worn level acquired a false upgrade arrow")
    beforeLinks = links
    W.Fire("GET_ITEM_INFO_RECEIVED", 25, true)
    W.Settle()
    assert(links == beforeLinks, client .. ": duplicate resolved-item event invalidated worn equipment")
    unknown[27], unknown[29], hidden[12], hidden[17] = nil, nil, nil, nil
    W.Fire("ITEM_DATA_LOAD_RESULT", 27, true)
    W.Fire("GET_ITEM_INFO_RECEIVED", 29, true)
    W.Settle()
    assert(links == beforeLinks + 16 and not Arrow(W, 21) and not Arrow(W, 22),
        client .. ": completed equipment loads did not coalesce into one rebuild")
    local events = W.P.UpgradeMarker.events
    assert(not events:IsEventRegistered("GET_ITEM_INFO_RECEIVED") and not events:IsEventRegistered("ITEM_DATA_LOAD_RESULT"),
        client .. ": resolved equipment retained item event listeners")
    unknown[25], W.data[25].level = true, 200
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
    W.Settle()
    assert(not Arrow(W, 20) and W.requested[25] == 2, client .. ": equipment change did not retry unknown level once")
    unknown[25] = nil
    W.Fire("GET_ITEM_INFO_RECEIVED", 25, true)
    W.Settle()
    assert(Arrow(W, 20), client .. ": loaded lower worn level did not produce its upgrade arrow")
    W.worn[12], W.worn[17] = nil, nil
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 12, false)
    W.Settle()
    assert(Arrow(W, 21) and not Arrow(W, 22), client .. ": empty ring/weapon semantics changed")
    W.worn[1] = secret
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
    W.Settle()
    assert(not Arrow(W, 20), client .. ": secret equipped identity became an empty slot")
    W.worn[1], unknown[25] = "item:25", true
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
    W.Settle()
    W.config.showUpgradeMarker = false
    W.Apply()
    W.Settle()
    assert(not Arrow(W, 20) and not events:IsEventRegistered("GET_ITEM_INFO_RECEIVED")
        and not events:IsEventRegistered("ITEM_DATA_LOAD_RESULT") and next(W.P.UpgradeMarker.pending) == nil,
        client .. ": disabling retained marker or equipped-data listeners")
    beforeLinks, beforeIDs, beforeLevels = links, ids, levels
    W.Fire("GET_ITEM_INFO_RECEIVED", 25, true)
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
    W.Settle()
    assert(links == beforeLinks and ids == beforeIDs and levels == beforeLevels, client .. ": disabled marker did work")
    local requests = W.requested[25]
    W.config.showUpgradeMarker = true
    W.Apply()
    W.Settle()
    assert(W.requested[25] == requests + 1 and not Arrow(W, 20), client .. ": re-enable did not retry unresolved equipment")
    unknown[25] = nil
    W.Fire("ITEM_DATA_LOAD_RESULT", 25, true)
    W.Settle()
    assert(Arrow(W, 20), client .. ": re-enabled marker did not recover from item completion")
    W.config.enabled = false
    W.Apply()
    assert(next(W.P.UpgradeMarker.pending) == nil and next(W.P.UpgradeMarker.requested) == nil
        and not events:IsEventRegistered("PLAYER_EQUIPMENT_CHANGED"), client .. ": disable retained equipped state")
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    if not arg[3] or client == arg[3] then
    if not selected or selected == "bank" then Bank(client) end
    if not selected or selected == "metadata" then Metadata(client) end
    if not selected or selected == "equipment" then Equipment(client) end
    end
end
print("bags item recovery: native reopening, equipped unknown/empty, bounded loads, cached repaint and teardown passed")
