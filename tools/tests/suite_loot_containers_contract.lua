local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, calls, notices, reported = nil, {}, {}, {}
local frames = Support.EventFrames()
local combat, shift, cursor = false, false, false
local slots = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
local deferred = {}
GetTime = function() return 0 end
local CompleteUse

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
        if CompleteUse and #module.pending == 0 then CompleteUse() end
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
-- Positive cancellation deadlines are exercised by the asynchronous contract.
C_Timer = { After = function(delay, callback)
    if delay == 0 then deferred[#deferred + 1] = callback end
end }

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

-- Normal successful native cycles in this legacy fixture complete explicitly.
-- The async contract separately holds those events back to test pending use.
CompleteUse = function()
    local opened, closed = context.events.LOOT_OPENED, context.events.LOOT_CLOSED
    if opened then opened(module, "LOOT_OPENED", true) end
    if closed then closed(module, "LOOT_CLOSED") end
end
local function Settle(bag)
    if not lootShown and context.events.LOOT_OPENED then CompleteUse() end
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
slots[1][3], slots[0][4] = slots[0][4], nil
Settle(0); Settle(1)
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(#calls == 2 and calls[2].bag == 1 and calls[2].slot == 3, "deferred container did not open after combat")

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
slots[3][1] = nil
Settle(3) -- a disappeared locked candidate cannot block later batches

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
C_Container.UseContainerItem = function() opened = opened + 1; CompleteUse() end
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


-- Native unlocks complete discovery without another BAG_UPDATE. Existing,
-- unreadable and deliberately cancelled containers must remain manual.
do
    local uses = {}
    local function FlushJobs()
        local queued = deferred
        deferred = {}
        for _, callback in ipairs(queued) do callback() end
    end
    local function Reset()
        module.active = false
        module:Disable()
        context:CancelTimers()
        deferred, uses = {}, {}
        combat, shift, cursor, lootShown = false, false, false, false
        MerchantFrame = nil
        for bag = 0, 5 do slots[bag] = {} end
        module.config, module.active = { skipWarbound = false }, true
        C_Container.UseContainerItem = function(bag, slot)
            uses[#uses + 1] = { bag = bag, slot = slot }
            lootShown = true
        end
    end
    local function Item(guid, locked)
        return { guid = guid, info = { itemID = 500, hasLoot = true, isLocked = locked } }
    end
    local function Unlock(bag, slot)
        slots[bag][slot].info.isLocked = false
        local handler = context.events.ITEM_LOCK_CHANGED
        if handler then handler(module, "ITEM_LOCK_CHANGED", bag, slot) end
        FlushJobs()
    end
    Reset()
    slots[0][1], slots[0][2] = Item("old-locked", true), { guid = "old-secret", info = "secret" }
    module:Enable()
    slots[0][3] = Item("new-locked", true)
    Settle(0)
    assert(#uses == 0, "new locked container was used early")
    Unlock(0, 3)
    assert(#uses == 1 and uses[1].slot == 3, "native unlock did not resume a new locked container")
    assert(not context.events.ITEM_LOCK_CHANGED, "completed queue retained its lock listener")
    lootShown = false
    slots[0][1].info.isLocked = false
    slots[0][2].info = Item("unused", false).info
    Settle(0)
    assert(#uses == 1, "baseline or resolved secret container became eligible")
    Settle(0)
    assert(#uses == 1, "opened unlocked GUID retried")

    -- Unrelated native/equipment locks read no slots and allocate no deferred work.
    Reset(); module:Enable()
    slots[1][2] = Item("moving-lock", true); Settle(1)
    local nativeRead, reads = C_Container.GetContainerItemInfo, 0
    C_Container.GetContainerItemInfo = function(...) reads = reads + 1; return nativeRead(...) end
    local onLock = assert(context.events.ITEM_LOCK_CHANGED)
    onLock(module, "ITEM_LOCK_CHANGED", 1, nil)
    onLock(module, "ITEM_LOCK_CHANGED", "secret", 2)
    onLock(module, "ITEM_LOCK_CHANGED", 1, "secret")
    onLock(module, "ITEM_LOCK_CHANGED", 1, 3)
    assert(reads == 0 and #deferred == 0, "unrelated locks did work")
    local minimumKB = math.huge
    for pass = 1, 2 do
        collectgarbage("collect"); collectgarbage("stop")
        local beforeKB = collectgarbage("count")
        for i = 1, 1000 do onLock(module, "ITEM_LOCK_CHANGED", 1, 3) end
        minimumKB = math.min(minimumKB, collectgarbage("count") - beforeKB)
        collectgarbage("restart")
    end
    assert(minimumKB == 0 and reads == 0 and #deferred == 0, "unrelated lock events allocated or queried the client")
    for i = 1, 10 do onLock(module, "ITEM_LOCK_CHANGED", 1, 2) end
    assert(#deferred == 1 and reads == 0, "matching lock burst did not coalesce")
    FlushJobs()
    assert(#uses == 0 and reads == 1, "still-locked retry did not stay bounded")
    C_Container.GetContainerItemInfo = nativeRead
    slots[2][4], slots[1][2] = slots[1][2], nil
    context.events.BAG_UPDATE(module, "BAG_UPDATE", 1)
    Settle(2)
    Unlock(2, 4)
    assert(#uses == 1 and uses[1].bag == 2 and uses[1].slot == 4, "moved locked GUID lost its location")
    lootShown = false
    Settle(2)
    assert(#uses == 1, "moved opened GUID was used twice")

    -- A locked candidate does not starve a later ready item or bypass loot pacing.
    Reset(); module:Enable()
    slots[0][1], slots[0][2] = Item("ready", false), Item("waiting", true)
    Settle(0)
    assert(#uses == 1 and uses[1].slot == 1, "locked queue member blocked a ready container")
    Unlock(0, 2)
    assert(#uses == 1, "unlock opened a second container while native loot was visible")
    lootShown = false
    context.events.LOOT_CLOSED(module, "LOOT_CLOSED")
    FlushJobs()
    assert(#uses == 2 and not context.events.ITEM_LOCK_CHANGED, "loot close did not drain the unlocked item")

    -- Deliberate suppression is terminal even if the item is still locked then.
    for _, reason in ipairs({ "shift", "merchant", "cursor" }) do
        Reset(); module:Enable()
        slots[0][1] = Item("cancel-" .. reason, true); Settle(0)
        if reason == "shift" then shift = true
        elseif reason == "merchant" then MerchantFrame = Window(true)
        else cursor = true end
        context.events.ITEM_LOCK_CHANGED(module, "ITEM_LOCK_CHANGED", 0, 1)
        FlushJobs()
        assert(#module.pending == 0 and not context.events.ITEM_LOCK_CHANGED, "locked cancellation kept eligibility")
        shift, cursor, MerchantFrame = false, false, nil
        Unlock(0, 1); Settle(0)
        assert(#uses == 0, "unlock bypassed deliberate " .. reason .. " cancellation")
    end

    Reset(); module:Enable()
    slots[0][1] = Item("combat-lock", true); Settle(0)
    combat = true; Unlock(0, 1)
    assert(#uses == 0 and context.events.PLAYER_REGEN_ENABLED, "unlock bypassed combat")
    combat = false
    context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
    assert(#uses == 1, "unlocked combat candidate was not resumed")

    Reset(); module:Enable()
    slots[0][1] = Item("gone", true); Settle(0)
    slots[0][1] = nil; Settle(0)
    assert(#module.pending == 0 and not context.events.ITEM_LOCK_CHANGED and #uses == 0, "gone locked GUID remained pending")
    slots[0][1] = Item("secret-later", true); Settle(0)
    slots[0][1].info = "secret"
    context.events.ITEM_LOCK_CHANGED(module, "ITEM_LOCK_CHANGED", 0, 1); FlushJobs()
    slots[0][1].info = Item("unused", false).info
    Settle(0)
    assert(#uses == 0 and not context.events.ITEM_LOCK_CHANGED, "unreadable waiting item became eligible later")

    -- Unlock retains the configured binding and currency-cap decisions.
    Reset(); module.config.skipWarbound = true; module:Enable()
    accountBound = true
    slots[0][1] = Item("warbound-lock", true); Settle(0)
    Unlock(0, 1)
    assert(#uses == 0 and #module.pending == 0 and not context.events.ITEM_LOCK_CHANGED, "unlock bypassed warbound exclusion")
    accountBound = false
    Settle(0)
    assert(#uses == 0, "excluded unlocked GUID retried")

    Reset(); module.config.holdDundun = true; module:Enable()
    currency.quantity, currency.useTotalEarnedForMaxQty, currency.quantityEarnedThisWeek = 8, false, 0
    slots[0][1] = Item("currency-lock", true)
    slots[0][1].info.itemID = 246585
    Settle(0); Unlock(0, 1)
    assert(#uses == 0 and module.held["currency-lock"] and not module.attempted["currency-lock"], "unlock bypassed currency cap")
    assert(not context.events.ITEM_LOCK_CHANGED and context.events.CURRENCY_DISPLAY_UPDATE, "held currency retained lock work")
    currency.quantity = 7
    CurrencyEvent()
    assert(#uses == 1 and not next(module.held), "unlocked payout did not resume after spending")

    -- A payout held before the lock must retain its eligible identity too.
    for _, condition in ipairs({ "released", "still-capped", "shift", "gone" }) do
        Reset(); module.config.holdDundun = true; module:Enable()
        currency.quantity = 8
        slots[0][1] = Item("held-lock-" .. condition, false)
        slots[0][1].info.itemID = 246585
        Settle(0)
        assert(next(module.held), "currency hold setup failed")
        slots[0][1].info.isLocked = true
        if condition ~= "still-capped" then currency.quantity = 7 end
        if condition == "shift" then shift = true end
        if condition == "gone" then slots[0][1] = nil end
        CurrencyEvent()
        if condition == "released" or condition == "still-capped" then
            assert(#uses == 0 and #module.pending == 1 and context.events.ITEM_LOCK_CHANGED,
                "currency-held payout lost eligibility while locked")
            Unlock(0, 1)
            if condition == "still-capped" then
                assert(#uses == 0 and next(module.held), "unlock bypassed the still-full currency cap")
                currency.quantity = 7; CurrencyEvent()
            end
            assert(#uses == 1 and not next(module.held) and #module.pending == 0, "held lock did not resume exactly once")
        else
            assert(#uses == 0 and not next(module.held) and #module.pending == 0,
                "currency resume ignored cancellation or missing GUID")
            shift = false
            if condition ~= "gone" then Unlock(0, 1); Settle(0) end
            assert(#uses == 0, "cancelled held lock was reopened")
        end
    end

    Reset(); module:Enable()
    slots[0][1] = Item("refused-lock", true); Settle(0)
    C_Container.UseContainerItem = function()
        frames.Fire("ADDON_ACTION_BLOCKED", "MSUF_Suite_QualityOfLife", "UseContainerItem()")
    end
    Unlock(0, 1)
    assert(module.blocked and module.attempted["refused-lock"] and not context.events.ITEM_LOCK_CHANGED,
        "refused unlocked item retained a retry route")

    Reset(); module:Enable()
    slots[0][1] = Item("cap-pending", true); Settle(0)
    module.seenCount = 1024
    slots[0][2] = Item("cap-hit", true); Settle(0)
    assert(module.seenSaturated and #module.pending == 0 and not context.events.ITEM_LOCK_CHANGED, "history cap left unlock work")
    Unlock(0, 1); Settle(0)
    assert(#uses == 0, "unlock bypassed history saturation")

    Reset(); module:Enable()
    slots[0][1] = Item("disabled-lock", true); Settle(0)
    context.events.ITEM_LOCK_CHANGED(module, "ITEM_LOCK_CHANGED", 0, 1)
    module.active = false; module:Disable(); context:CancelTimers()
    slots[0][1].info.isLocked = false; FlushJobs()
    assert(#uses == 0 and not context.events.ITEM_LOCK_CHANGED and #module.pending == 0, "disable retained an unlock callback")
    print("Suite loot containers: native unlock, bounded events, movement, cancellations and teardown passed")
end
