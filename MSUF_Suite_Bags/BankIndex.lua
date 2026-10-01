local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Index, Slots = P.InventoryIndex, P.SlotCache
local BANK_VIEW = NS.BagsBankView
local Bank = {}
P.BankInventoryIndex = Bank

function Bank.New()
    local index = Index.New()
    index.containers, index.tabs = {}, {}
    return index
end

-- Slots come from the shared cache: only tabs with a BAG_UPDATE or a slot
-- with an ITEM_LOCK_CHANGED since the last pass are read from the client.
local function ReadTab(index, tab, bankType)
    local id = tab.ID
    if not S.Finite(id) then return end
    Slots.bankTabs[id] = true
    local size = Slots.Sync(id)
    local container = index.containers[id]
    if not container then
        container = { slots = {} }
        index.containers[id] = container
    end
    container.id, container.bankType = id, bankType
    container.name = S.Public(tab.name) and tab.name or S.Text("Bank")
    index.tabs[#index.tabs + 1] = container
    for slot = 1, size do
        local key = container.slots[slot]
        if not key then key = {}; container.slots[slot] = key end
        local info, quest, version = Slots.Get(id, slot)
        local item = Index.ReadButton(index, key, info, quest, version, id, slot, bankType)
        item.bagName = container.name
    end
    for slot = #container.slots, size + 1, -1 do container.slots[slot] = nil end
    container.size = size
end

local function ReadType(index, bankType)
    if not C_Bank.CanViewBank(bankType) then return end
    local tabs = C_Bank.FetchPurchasedBankTabData(bankType)
    if type(tabs) ~= "table" then return end
    for i = 1, #tabs do ReadTab(index, tabs[i], bankType) end
end

function Bank.Read(index, mode)
    for i = #index.items, 1, -1 do index.items[i] = nil end
    for i = #index.tabs, 1, -1 do index.tabs[i] = nil end
    index.filtered = 0
    local both = mode == BANK_VIEW.CATEGORIES
    if both or mode == BANK_VIEW.CHARACTER then ReadType(index, Enum.BankType.Character) end
    if both or mode == BANK_VIEW.WARBANK then ReadType(index, Enum.BankType.Account) end
    index.revision = index.revision + 1
    return index.items
end
