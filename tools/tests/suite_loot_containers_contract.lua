local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, calls, notices, reported = nil, {}, {}, {}
local frames = Support.EventFrames()
local combat, shift, cursor = false, false, false
local slots = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
local deferred = {}

Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 } }
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
C_Container = {
    GetContainerNumSlots = function(bag) return 5 end,
    GetContainerItemInfo = function(bag, slot)
        local item = slots[bag][slot]
        return item and item.info or nil
    end,
    UseContainerItem = function(bag, slot)
        calls[#calls + 1] = { bag = bag, slot = slot }
    end,
}
C_Item = { GetItemGUID = function(location)
    local item = slots[location.bag][location.slot]
    return item and item.guid or nil
end }
IsShiftKeyDown = function() return shift end
CursorHasItem = function() return cursor end
-- Blizzard_UIPanels_Game creates the loot window before any addon loads.
local lootShown = false
LootFrame = { IsShown = function() return lootShown end }
local function Window(shown) return { shown = shown, IsShown = function(self) return self.shown end } end
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }

local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge end,
    Text = function(value) return value end,
    Install = function(id, instance) assert(id == "lootContainers"); module = instance end,
    CreateFrame = frames.Create,
    Dispatch = Support.Dispatcher(reported),
}
Support.QoLStyleFixture(root, S)
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Print = function(value) notices[#notices + 1] = value end,
    Dispatch = S.Dispatch,
}
local context = Support.ModuleTimers(root, S, NS)("lootContainers", nil, { events = {} })
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end

slots[0][1] = { guid = "old", info = { itemID = 10, hasLoot = true, isLocked = false } }
-- SharedItems.lua loads first in the TOC: the shared ID list, bag-item
-- GUID and item-data helpers.
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SharedItems.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootContainers.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
S.instances.lootContainers = module
module:Enable()
assert(#calls == 0 and context.events.BAG_UPDATE and context.events.BAG_UPDATE_DELAYED,
    "the baseline opened an existing container or failed to register bag events")

local function Settle(bag)
    context.events.BAG_UPDATE(module, "BAG_UPDATE", bag)
    context.events.BAG_UPDATE_DELAYED(module, "BAG_UPDATE_DELAYED")
end
slots[0][2] = { guid = "new", info = { itemID = 11, hasLoot = true, isLocked = false } }
Settle(0)
assert(#calls == 1 and calls[1].bag == 0 and calls[1].slot == 2,
    "new public container did not open once")
Settle(0)
assert(#calls == 1, "unchanged container retried")
slots[0][2], slots[1][1] = nil, slots[0][2]
Settle(0)
Settle(1)
assert(#calls == 1, "moving an already-seen container looked like new loot")

-- A secret/unreadable baseline slot is never treated as newly acquired when
-- its data becomes public later.
slots[0][3] = { guid = "unknown", info = "secret" }
Settle(0)
slots[0][3].info = { itemID = 12, hasLoot = true, isLocked = false }
Settle(0)
assert(#calls == 1, "resolved secret item was auto-opened")

combat = true
slots[0][4] = { guid = "combat-new", info = { itemID = 13, hasLoot = true, isLocked = false } }
Settle(0)
assert(#calls == 1 and context.events.PLAYER_REGEN_ENABLED,
    "combat item opened early or was not deferred")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(#calls == 2 and calls[2].slot == 4, "deferred container did not open after combat")

shift = true
slots[0][5] = { guid = "paused", info = { itemID = 14, hasLoot = true, isLocked = false } }
Settle(0)
shift = false
assert(#calls == 2 and #module.pending == 0, "Shift did not leave the container manual")

MerchantFrame = Window(true)
slots[2][1] = { guid = "merchant", info = { itemID = 15, hasLoot = true, isLocked = false } }
Settle(2)
assert(#calls == 2 and #module.pending == 0,
    "merchant access used an item as a sale instead of leaving it manual")
MerchantFrame = nil
-- A container withdrawn from the guild bank would go straight back into it.
GuildBankFrame = Window(true)
slots[2][2] = { guid = "guildbank", info = { itemID = 22, hasLoot = true, isLocked = false } }
Settle(2)
assert(#calls == 2 and #module.pending == 0, "an open guild bank received a new container")
GuildBankFrame = nil
ScrappingMachineFrame = Window(true)
slots[2][3] = { guid = "scrapper", info = { itemID = 23, hasLoot = true, isLocked = false } }
Settle(2)
assert(#calls == 2 and #module.pending == 0, "an open scrapper received a new container")
ScrappingMachineFrame = nil

slots[3][1] = { guid = "locked", info = { itemID = 16, hasLoot = true, isLocked = true } }
slots[3][2] = { guid = "ordinary", info = { itemID = 17, hasLoot = false, isLocked = false } }
Settle(3)
assert(#calls == 2, "locked or non-container item was used")

slots[4][1] = { guid = "batch-one", info = { itemID = 18, hasLoot = true, isLocked = false } }
slots[4][2] = { guid = "batch-two", info = { itemID = 19, hasLoot = true, isLocked = false } }
Settle(4)
assert(#calls == 3 and #module.pending == 1 and context.events.LOOT_CLOSED,
    "a batch used multiple containers before the first loot window closed")
lootShown = true
context.events.LOOT_CLOSED(module, "LOOT_CLOSED")
assert(#calls == 3 and #deferred == 1, "loot close did not defer to native frame cleanup")
lootShown = false
deferred[1]()
assert(#calls == 4 and #module.pending == 0,
    "second container did not open after native loot window closed")

module.seenCount = 1024
slots[5][1] = { guid = "after-cap", info = { itemID = 20, hasLoot = true, isLocked = false } }
Settle(5)
assert(module.seenSaturated and #calls == 4,
    "bounded GUID history did not fail closed after its cap")

module.active = false
module:Disable()
assert(not context.events.BAG_UPDATE and not context.events.BAG_UPDATE_DELAYED
    and not context.events.PLAYER_REGEN_ENABLED and not context.events.LOOT_CLOSED
    and not next(module.pending), "disable left handlers or pending item actions")
module.active = true
module:Enable()
-- The client refuses a restricted item use with ADDON_ACTION_BLOCKED, not
-- with a Lua error.
C_Container.UseContainerItem = function()
    frames.Fire("ADDON_ACTION_BLOCKED", "MSUF_Suite_QualityOfLife", "UseContainerItem()")
end
slots[1][2] = { guid = "refused", info = { itemID = 21, hasLoot = true, isLocked = false } }
Settle(1)
assert(module.blocked and #notices == 1
    and notices[1] == "Automatic container opening was blocked by the client."
    and not context.events.BAG_UPDATE and not context.events.BAG_UPDATE_DELAYED
    and not context.events.LOOT_CLOSED and #reported == 0,
    "blocked container use did not stop automation once")
print("Suite loot containers: new public GUID, combat, Shift, UI safety and disable passed")

-- Account-bound and unreadable binding data stay manual.
module:Disable(); module.config = { skipWarbound = true }; module.active = true
C_Container.GetContainerItemID = function(bag, slot) return slots[bag][slot].info.itemID end
local accountBound = true
C_Item.IsItemBindToAccount = function() return accountBound end
C_Item.IsBoundToAccountUntilEquip = function() return false end
local opened = 0
C_Container.UseContainerItem = function() opened = opened + 1 end
module:Enable()
slots[5][2] = { guid = "warbound", info = { itemID = 31, hasLoot = true, isLocked = false } }
Settle(5)
assert(opened == 0)
accountBound = "secret"
slots[5][3] = { guid = "unknownbinding", info = { itemID = 32, hasLoot = true, isLocked = false } }
Settle(5)
assert(opened == 0)
accountBound = false
slots[5][4] = { guid = "ordinarybinding", info = { itemID = 33, hasLoot = true, isLocked = false } }
Settle(5)
assert(opened == 1)

-- Only Midnight's confirmed payout identity is subject to the optional cap.
module.config.holdDundun = true
local currency = { quantity = 8, maxQuantity = 8, useTotalEarnedForMaxQty = false,
    canEarnPerWeek = true, quantityEarnedThisWeek = 2, maxWeeklyQuantity = 8, totalEarned = 8 }
local currencyReads = 0
C_CurrencyInfo = { GetCurrencyInfo = function(id) assert(id == 3376); currencyReads = currencyReads + 1; return currency end }
local function CurrencyEvent()
    context.events.CURRENCY_DISPLAY_UPDATE(module, "CURRENCY_DISPLAY_UPDATE", 3376)
    local callback = table.remove(deferred)
    assert(callback); callback()
end
slots[0][2] = { guid = "payout-cap", info = { itemID = 246585, hasLoot = true, isLocked = false } }
Settle(0)
assert(opened == 1 and module.held["payout-cap"] and not module.attempted["payout-cap"])
assert(context.events.CURRENCY_DISPLAY_UPDATE and not context.events.LOOT_CLOSED)
slots[1][5], slots[0][2] = slots[0][2], nil
Settle(0); Settle(1)
assert(module.held["payout-cap"].bag == 1 and module.held["payout-cap"].slot == 5)
local beforeReads = currencyReads
context.events.CURRENCY_DISPLAY_UPDATE(module, "CURRENCY_DISPLAY_UPDATE", 999)
assert(currencyReads == beforeReads, "unrelated currency changes must not query or retry")
currency.quantity, currency.quantityEarnedThisWeek = 7, 8
CurrencyEvent()
assert(opened == 1 and module.held["payout-cap"], "spending does not bypass an exhausted weekly earning cap")
currency.quantityEarnedThisWeek = 0
CurrencyEvent()
assert(opened == 2 and not next(module.held) and not context.events.CURRENCY_DISPLAY_UPDATE)
currency.quantity = "secret"
slots[0][2] = { guid = "payout-unknown", info = { itemID = 246585, hasLoot = true, isLocked = false } }
Settle(0)
assert(opened == 2 and module.held["payout-unknown"], "unknown public cap data must retain the payout")
slots[2][2] = { guid = "payout-other", info = { itemID = 227713, hasLoot = true, isLocked = false } }
Settle(2)
assert(opened == 3, "the similarly named older payout must not inherit the Midnight mapping")
module.config.holdDundun = false; module:Refresh()
assert(opened == 4 and not next(module.held), "turning the cap option off releases only held candidates")
module.config.holdDundun = true
currency.quantity, currency.useTotalEarnedForMaxQty = 0, true
slots[2][3] = { guid = "payout-total", info = { itemID = 246585, hasLoot = true, isLocked = false } }
Settle(2)
assert(opened == 4 and module.held["payout-total"], "total-earned currency caps must use their declared semantics")
currency.totalEarned = 7
CurrencyEvent()
assert(opened == 5 and not context.events.CURRENCY_DISPLAY_UPDATE)
currency.totalEarned = 8
slots[2][4] = { guid = "payout-coalesce", info = { itemID = 246585, hasLoot = true, isLocked = false } }
Settle(2)
local queuedBefore = #deferred
context.events.CURRENCY_DISPLAY_UPDATE(module, "CURRENCY_DISPLAY_UPDATE", 3376)
context.events.CURRENCY_DISPLAY_UPDATE(module, "CURRENCY_DISPLAY_UPDATE", 3376)
assert(#deferred == queuedBefore + 1, "synchronous currency event bursts must coalesce")
currency.totalEarned = 7
-- As the controller stops a module: inactive, Disable, then Release.
module.active = false
module:Disable()
context:CancelTimers()
local staleCallback = table.remove(deferred); staleCallback()
assert(not next(module.held) and not context.events.CURRENCY_DISPLAY_UPDATE)
assert(opened == 5, "disable must cancel a pending currency resume")
