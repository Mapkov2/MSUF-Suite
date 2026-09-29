local root = assert(arg[1], "repository root required")
local module, calls, notices = nil, {}, {}
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
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }

local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge end,
    Text = function(value) return value end,
    Install = function(id, instance) assert(id == "lootContainers"); module = instance end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Print = function(value) notices[#notices + 1] = value end,
}
local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end

slots[0][1] = { guid = "old", info = { itemID = 10, hasLoot = true, isLocked = false } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootContainers.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
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

MerchantFrame = { IsShown = function() return true end }
slots[2][1] = { guid = "merchant", info = { itemID = 15, hasLoot = true, isLocked = false } }
Settle(2)
assert(#calls == 2 and #module.pending == 0,
    "merchant access used an item as a sale instead of leaving it manual")
MerchantFrame = nil

slots[3][1] = { guid = "locked", info = { itemID = 16, hasLoot = true, isLocked = true } }
slots[3][2] = { guid = "ordinary", info = { itemID = 17, hasLoot = false, isLocked = false } }
Settle(3)
assert(#calls == 2, "locked or non-container item was used")

slots[4][1] = { guid = "batch-one", info = { itemID = 18, hasLoot = true, isLocked = false } }
slots[4][2] = { guid = "batch-two", info = { itemID = 19, hasLoot = true, isLocked = false } }
Settle(4)
assert(#calls == 3 and #module.pending == 1 and context.events.LOOT_CLOSED,
    "a batch used multiple containers before the first loot window closed")
LootFrame = { IsShown = function() return true end }
context.events.LOOT_CLOSED(module, "LOOT_CLOSED")
assert(#calls == 3 and #deferred == 1, "loot close did not defer to native frame cleanup")
LootFrame = nil
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
C_Container.UseContainerItem = function() error("client refused item use") end
slots[1][2] = { guid = "refused", info = { itemID = 21, hasLoot = true, isLocked = false } }
Settle(1)
assert(module.blocked and #notices == 1
    and notices[1] == "Automatic container opening was blocked by the client."
    and not context.events.BAG_UPDATE and not context.events.BAG_UPDATE_DELAYED
    and not context.events.LOOT_CLOSED,
    "restricted container use did not stop automation once")
print("Suite loot containers: new public GUID, combat, Shift, UI safety and disable passed")
