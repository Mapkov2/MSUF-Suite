local root = assert(arg[1])
local callbacks, combat, cursor, mutations = {}, false, nil, 0
local slots = { [1] = { link = "item:1", count = 10 }, [3] = { link = "item:2", count = 5 } }
local frame = { SetScript = function(self, _, callback) self.callback = callback end,
    RegisterEvent = function() end, UnregisterAllEvents = function() end }
local P = { NS = { Client = { SupportsEvent = function() return true end }, IsCombatLocked = function() return combat end },
    Suite = { Public = function(value) return value ~= "secret" end,
        Finite = function(value) return type(value) == "number" end, CreateFrame = function() return frame end },
    BagsModule = { active = true } }
C_Timer = {
    After = function(_, callback) callbacks[#callbacks + 1] = callback end,
    NewTimer = function(_, callback) return { Cancel = function() end, callback = callback } end,
}
hooksecurefunc = function() end
GetCursorInfo = function() if cursor then return "item", 1, cursor.link end end
C_Container = {
    GetContainerItemInfo = function(_, slot)
        local item = slots[slot]
        if item then return { hyperlink = item.link, stackCount = item.count, isLocked = item.locked } end
    end,
    GetContainerNumFreeSlots = function() return 5, 0 end,
    GetContainerNumSlots = function() return 6 end,
    SplitContainerItem = function(_, slot, count)
        mutations = mutations + 1
        assert(not combat and cursor == nil)
        local item = assert(slots[slot])
        item.count = item.count - count
        cursor = { link = item.link, count = count }
        frame.callback(nil, "CURSOR_CHANGED")
    end,
    PickupContainerItem = function(_, slot)
        mutations = mutations + 1
        assert(not slots[slot], "auto split must never touch an occupied destination")
        slots[slot], cursor = cursor, nil
        frame.callback(nil, "CURSOR_CHANGED")
    end,
}
-- No test item is a crafting reagent (GetItemInfo's 17th result).
C_Item = { GetItemFamily = function() return 0 end, GetItemInfo = function() return "Item" end }
Enum = { BagIndex = { ReagentBag = 5 } }
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 0
bit = { band = function() return 0 end }
assert(loadfile(root .. "/MSUF_Suite_Bags/SplitInventory.lua"))("Bags", P)
assert(loadfile(root .. "/MSUF_Suite_Bags/AutoSplit.lua"))("Bags", P)
local A = P.AutoSplit
local owner = { GetBagID = function() return 0 end, GetID = function() return 1 end }
local function Drain()
    local limit = 0
    while #callbacks > 0 do
        limit = limit + 1; assert(limit < 100, "auto split must settle without polling")
        table.remove(callbacks, 1)()
    end
end
assert(A.Start(owner, 3)); Drain()
assert(not A.job and not cursor and slots[1].count == 1 and slots[2].count == 3 and slots[4].count == 3 and slots[5].count == 3)
assert(slots[3].link == "item:2" and slots[3].count == 5, "unrelated stack unchanged")
slots = { [1] = { link = "item:1", count = 10 } }
assert(A.Start(owner, 2))
combat = true
local before = mutations
frame.callback(nil, "PLAYER_REGEN_DISABLED"); Drain()
assert(not A.job and mutations == before and cursor, "combat abort leaves cursor with player; never silently places/clears it")
combat, cursor = false, nil
slots = { [1] = { link = "item:1", count = 10 } }
assert(A.Start(owner, 2))
cursor.link = "item:99"
Drain()
assert(not A.job and cursor.link == "item:99" and not slots[2], "foreign cursor item is never moved")
cursor = nil
slots = { [1] = { link = "item:1", count = 10 } }
assert(A.Start(owner, 2))
slots[2] = { link = "item:3", count = 1 }
Drain()
assert(not A.job and slots[2].link == "item:3" and cursor, "destination changed after planning aborts without swapping")
cursor = nil
slots = { [1] = { link = "item:1", count = 10, locked = true } }
assert(not A.Start(owner, 2), "locked source cannot begin")
slots[1].locked, slots[1].link = false, "secret"
assert(not A.Start(owner, 2), "restricted source cannot begin")
slots[1].link = "item:1"
for i = 2, 6 do slots[i] = { link = "item:2", count = 1 } end
assert(not A.Start(owner, 2), "full bags do not begin")
local I = P.SplitInventory
GuildBankFrame = { IsShown = function() return true end }
GetCurrentGuildBankTab = function() return 2 end
local guildOwner = { GetID = function() return 4 end, GetParent = function() return GuildBankFrame end }
local guild = I.Source(guildOwner)
assert(guild.kind == "guild" and guild.bag == 2 and guild.slot == 4 and I.Available(guild))
GetGuildBankItemLink = function() return nil end
GetGuildBankItemInfo = function() return nil, nil, false end
local link, count, locked = I.Read(guild)
assert(link == nil and count == 0 and not locked and #I.Destinations(guild, "item:1") == 98,
    "native empty guild slots accept nil counts without treating a real item as empty")
GetGuildBankItemInfo = function() return 123, nil, false end
link, count, locked = I.Read(guild)
assert(locked and count == nil, "partially loaded guild items are never empty destinations")
GetGuildBankItemInfo = function() return nil, 0, "secret" end
assert(#I.Destinations(guild, "item:1") == 0, "restricted guild locks remain unavailable")
GetCurrentGuildBankTab = function() return 3 end
assert(not I.Available(guild), "changing guild bank tabs invalidates the split scope")
local bankOwner = { bankTabID = 12, containerSlotID = 3, bankType = 2 }
local bank = I.Source(bankOwner)
assert(bank.kind == "bank" and bank.bag == 12 and bank.slot == 3 and bank.bankType == 2)
print("auto split lifecycle, native inventory adapters, cursor ownership and cancellation passed")
