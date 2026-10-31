local _, P = ...
local NS, S = P.NS, P.Suite
local Data = {}
S.InventoryData = Data
local names = {}
local nameCount = 0
local EVENT = "GET_ITEM_INFO_RECEIVED"
-- An item the client has not cached is asked for once; the item list that
-- shows its numbered placeholder repaints when the data arrives. The event is
-- listened to only while an answer is outstanding.
local requests, pending, listener, repaint = S.QoLItemRequests(), {}

local function Repaint()
    for _, instance in pairs(S.instances) do S.ToolListWindow.Refresh(instance) end
end

local function Arrived(_, _, itemID, success)
    if not requests:Arrived(itemID) then return end
    pending[itemID] = nil
    if not next(pending) then listener:UnregisterEvent(EVENT) end
    if success then repaint:Request() end
end

local function Ask(id)
    if pending[id] or not requests:Request(id) then return end
    pending[id] = true
    if not listener then
        listener = S.CreateFrame("Frame")
        listener:SetScript("OnEvent", Arrived)
        repaint = S.Debounce(0, Repaint)
    end
    listener:RegisterEvent(EVENT)
end

function Data.Name(id)
    local value = names[id]
    if value then return value end
    local raw = C_Item.GetItemNameByID(id)
    local name = S.PublicText(raw)
    if name then
        nameCount = nameCount + 1
        if nameCount > 2048 then names, nameCount = {}, 1 end
        names[id] = name
        return name
    end
    if S.Public(raw) and raw == nil then Ask(id) end
    return S.Text("Item %d"):format(id)
end

function Data.Item(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not S.Public(info) then return nil, false end
    if info == nil then return nil, true end
    if type(info) ~= "table" or not S.Finite(info.itemID) or info.itemID < 1
        or not S.Finite(info.stackCount) or info.stackCount < 1 then return nil, false end
    local id, link = info.itemID, S.PublicText(info.hyperlink)
    local item = { bag = bag, slot = slot, itemID = id, count = info.stackCount, name = Data.Name(id), link = link }
    item.search = item.name:lower() .. " " .. id
    item.quality = S.Finite(info.quality) and info.quality or nil
    item.locked = not S.Public(info.isLocked) or info.isLocked ~= false
    item.bound = not S.Public(info.isBound) or info.isBound ~= false
    item.hasNoValue = not S.Public(info.hasNoValue) or info.hasNoValue ~= false
    item.hasLoot = not S.Public(info.hasLoot) or info.hasLoot ~= false
    item.icon = S.Finite(info.iconFileID) and info.iconFileID or nil
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    item.quest = not S.Public(quest) or type(quest) ~= "table"
    if not item.quest then
        item.quest = not S.Public(quest.isQuestItem) or quest.isQuestItem ~= false
            or not S.Public(quest.questID) or quest.questID ~= nil
    end
    return item, true
end

function Data.Scan(bags)
    local items, counts, complete = {}, {}, true
    for i = 1, math.min(#bags, 20) do
        local bag, slots = bags[i], C_Container.GetContainerNumSlots(bags[i])
        if not S.Finite(slots) or slots < 0 or slots > 200 or slots % 1 ~= 0 then complete = false
        else
            for slot = 1, slots do
                local item, known = Data.Item(bag, slot)
                if not known then complete = false end
                if item then
                    items[#items + 1] = item
                    counts[item.itemID] = (counts[item.itemID] or 0) + item.count
                end
            end
        end
    end
    return items, counts, complete
end

local BAGS = { 0, 1, 2, 3, 4, 5 }
function Data.Bags() return Data.Scan(BAGS) end

function Data.BankBags(bankType)
    local can = C_Bank.CanUseBank(bankType)
    if not S.Public(can) or can ~= true then return nil end
    local tabs = C_Bank.FetchPurchasedBankTabData(bankType)
    if not S.Public(tabs) or type(tabs) ~= "table" then return nil end
    local result = {}
    for i = 1, math.min(#tabs, 20) do
        local tab = tabs[i]
        if not S.Public(tab) or type(tab) ~= "table" or not S.Finite(tab.ID) then return nil end
        result[#result + 1] = tab.ID
    end
    return result
end

function Data.CurrentCharacter()
    local guid = S.PublicText(UnitGUID("player"))
    local name, realm = UnitFullName("player")
    name, realm = S.PublicText(name), S.PublicText(realm) or S.PublicText(GetNormalizedRealmName())
    local region = S.PublicText(GetCurrentRegionName())
    if not guid or not name or not realm or not region then return end
    return guid, name .. "-" .. realm, region
end

function Data.EmptyCursor()
    local cursor = GetCursorInfo()
    return S.Public(cursor) and cursor == nil
end

function Data.QuantityRows(values, counts)
    local rows = {}
    for id, quantity in pairs(values) do
        rows[#rows + 1] = { key = id, itemID = id, quantity = quantity,
            label = S.Text("%s — target %d, in bags %d"):format(Data.Name(id), quantity, counts and counts[id] or 0),
            detail = S.Text("Select an item to change its quantity or remove it."), search = Data.Name(id) .. " " .. id }
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end
