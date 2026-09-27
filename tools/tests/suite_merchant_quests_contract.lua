local root = assert(arg[1], "repository root required")
-- Merchant helpers (repair, junk selling) and quest automation: which visits
-- spend money, what stays manual, and which events stay registered.
local secret = {}
issecretvalue = function(value) return value == secret end
local combat, shift = false, false
local repairs, used, messages = {}, {}, {}
local money, repairCost, canRepair, merchantRepairs = 500000, 30000, true, true
local guildAllowed, guildAllowance, guildFunds = false, 0, 0
local bags = {}

InCombatLockdown = function() return combat end
IsShiftKeyDown = function() return shift end
NUM_BAG_SLOTS = 4
Enum = { ItemQuality = { Poor = 0 } }
CanMerchantRepair = function() return merchantRepairs end
GetRepairAllCost = function() return repairCost, canRepair end
GetMoney = function() return money end
RepairAllItems = function(guild) repairs[#repairs + 1] = guild == true and "guild" or "own" end
CanGuildBankRepair = function() return guildAllowed end
GetGuildBankWithdrawMoney = function() return guildAllowance end
GetGuildBankMoney = function() return guildFunds end
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].size or 0 end,
    GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] or nil end,
    UseContainerItem = function(bag, slot)
        used[#used + 1] = bag * 1000 + slot
        bags[bag][slot] = nil
    end,
}

local suite = { instances = {} }
suite.Public = function(value) return not issecretvalue(value) end
suite.Number = function(value) return suite.Public(value) and type(value) == "number" and value == value end
suite.Text = function(value) return value end
function suite.Install(id, module)
    assert((id == "qol" or id == "quests") and not suite.instances[id])
    suite.instances[id] = module
end
local owner = {
    IsCombatLocked = function() return combat end,
    Print = function(message) messages[#messages + 1] = message end,
}
for _, file in ipairs({ "Merchant", "QuestHelpers" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))(
        "MSUF_Suite_QualityOfLife", { NS = owner, Suite = suite })
end

local function Context()
    local context = { events = {} }
    function context:Event(name, callback) self.events[name] = callback end
    function context:RemoveEvent(name) self.events[name] = nil end
    return context
end
local function Fire(module, name, ...)
    local callback = assert(module.context.events[name], "missing event " .. name)
    callback(module, name, ...)
end
local function Junk(itemID, count, flags)
    local item = { quality = 0, itemID = itemID, stackCount = count }
    for key, value in pairs(flags or {}) do item[key] = value end
    return item
end

------------------------------------------------------------------ merchant
local merchant = assert(suite.instances.qol)
merchant.active = true
merchant.context = Context()
merchant.config = { repair = true, repairLimit = 50, guildRepair = false, repairFallback = true,
    autoJunk = true, junkReport = true }
merchant:Enable()
assert(merchant.context.events.MERCHANT_SHOW and merchant.context.events.MERCHANT_CLOSED
    and not merchant.context.events.BAG_UPDATE_DELAYED, "merchant events were not registered on demand")

-- A visit repairs within the limit and sells readable, unlocked poor items.
bags[0] = { size = 4, Junk(1, 3), { quality = 2, itemID = 2 }, Junk(3, 1, { isLocked = true }),
    Junk(4, 1, { hasNoValue = true }) }
Fire(merchant, "MERCHANT_SHOW")
assert(#repairs == 1 and repairs[1] == "own", "a repair within the limit did not use the player's money")
assert(#used == 1 and used[1] == 1, "junk selling touched a non-junk, locked or valueless item")
Fire(merchant, "MERCHANT_CLOSED")
assert(messages[1] == "Sold 3 junk items." and merchant.soldCount == 0
    and not merchant.context.events.BAG_UPDATE_DELAYED, "closing the merchant did not report the sold count")

-- Costs above the limit or above the player's money are never paid.
repairs, used = {}, {}
repairCost = 600000
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
repairCost, money = 30000, 1000
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
money = 500000
assert(#repairs == 0, "a repair above the limit or the player's money was paid")

-- Guild repair first; without guild money the fallback decides.
merchant.config.guildRepair = true
guildAllowed, guildAllowance, guildFunds = true, -1, 100000
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
guildFunds = 0
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
merchant.config.repairFallback = false
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
assert(#repairs == 2 and repairs[1] == "guild" and repairs[2] == "own",
    "guild repair did not come first or the fallback setting was ignored")
merchant.config.guildRepair, merchant.config.repairFallback = false, true

-- A secret cost never authorizes a repair.
repairs = {}
repairCost = secret
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
repairCost = 30000
assert(#repairs == 0, "a secret repair cost was paid")

-- More junk than one batch continues on the next bag update, which clears
-- the requests of the previous batch in place.
repairs, used, messages = {}, {}, {}
merchant.config.repair = false
bags[0] = { size = 14 }
for slot = 1, 14 do bags[0][slot] = Junk(100 + slot, 1) end
Fire(merchant, "MERCHANT_SHOW")
local requested = merchant.requested
assert(#used == 12 and merchant.context.events.BAG_UPDATE_DELAYED and #repairs == 0,
    "a large junk pass was not split into bounded batches")
Fire(merchant, "BAG_UPDATE_DELAYED")
assert(#used == 14 and not merchant.context.events.BAG_UPDATE_DELAYED and merchant.requested == requested,
    "the second junk batch did not finish or replaced the request table")
Fire(merchant, "MERCHANT_CLOSED")
assert(messages[1] == "Sold 14 junk items.", "junk count across batches")
Fire(merchant, "MERCHANT_SHOW")
assert(merchant.requested == requested and not next(requested),
    "a new merchant visit allocated or kept the previous request table")
Fire(merchant, "MERCHANT_CLOSED")

-- Shift pauses selling; combat blocks the whole visit.
bags[0] = { size = 1, Junk(200, 1) }
used = {}
shift = true
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
shift, combat = false, true
Fire(merchant, "MERCHANT_SHOW")
combat = false
Fire(merchant, "MERCHANT_CLOSED")
assert(#used == 0, "Shift or combat did not pause junk selling")

-- Turning both helpers off releases the merchant events.
merchant.config.repair, merchant.config.autoJunk = false, false
merchant:Refresh()
assert(not next(merchant.context.events), "disabled merchant helpers kept their events")
merchant:Disable()
print("Suite merchant: repair limits, guild order, junk batches, pauses and events passed")

------------------------------------------------------------------ quests
local accepted, completed, rewards, selected = 0, 0, {}, {}
local questID, questCost, questChoices, completable = 101, 0, 1, true
local accountDone = {}
local active, available = {}, {}
GetQuestMoneyToGet = function() return questCost end
GetQuestID = function() return questID end
AcceptQuest = function() accepted = accepted + 1 end
IsQuestCompletable = function() return completable end
CompleteQuest = function() completed = completed + 1 end
GetNumQuestChoices = function() return questChoices end
GetQuestReward = function(choice) rewards[#rewards + 1] = choice end
C_QuestLog = { IsQuestFlaggedCompletedOnAccount = function(id) return accountDone[id] == true end }
C_GossipInfo = {
    GetActiveQuests = function() return active end,
    GetAvailableQuests = function() return available end,
    SelectActiveQuest = function(id) selected[#selected + 1] = "turnin:" .. id end,
    SelectAvailableQuest = function(id) selected[#selected + 1] = "accept:" .. id end,
}

local quests = assert(suite.instances.quests)
quests.active = true
quests.context = Context()
quests.config = { accept = true, complete = true, reward = true, gossip = true, firstTime = false,
    onlyIDs = "", skipIDs = "" }
quests:Enable()
local registered = quests.context.events
assert(registered.QUEST_DETAIL and registered.QUEST_PROGRESS and registered.QUEST_COMPLETE
    and registered.QUEST_FINISHED and registered.GOSSIP_SHOW and registered.GOSSIP_CLOSED,
    "quest automation events were not registered")

-- Offered quests are accepted, ready ones completed, single rewards taken;
-- each dialog step acts once per quest.
Fire(quests, "QUEST_DETAIL")
Fire(quests, "QUEST_DETAIL")
Fire(quests, "QUEST_PROGRESS")
Fire(quests, "QUEST_COMPLETE")
assert(accepted == 1 and completed == 1 and #rewards == 1 and rewards[1] == 1,
    "quest dialogs were not handled exactly once")
local handled = quests.handled
Fire(quests, "QUEST_FINISHED")
assert(quests.handled == handled and not next(handled), "closing a quest dialog allocated a new record")
Fire(quests, "QUEST_DETAIL")
assert(accepted == 2, "a finished dialog did not allow the next quest")

-- Reward choices and quests that cost money stay manual; so does Shift.
questChoices = 2
Fire(quests, "QUEST_FINISHED")
Fire(quests, "QUEST_COMPLETE")
questChoices, questCost = 1, 5000
Fire(quests, "QUEST_FINISHED")
Fire(quests, "QUEST_COMPLETE")
questCost = secret
Fire(quests, "QUEST_FINISHED")
Fire(quests, "QUEST_COMPLETE")
questCost, shift = 0, true
Fire(quests, "QUEST_FINISHED")
Fire(quests, "QUEST_COMPLETE")
shift = false
assert(#rewards == 1, "a reward choice, a money cost, a secret cost or Shift was automated")

-- Filters: skipped IDs, an only-list, and account-completed quests.
Fire(quests, "QUEST_FINISHED")
quests.config.skipIDs = "101"
quests:Refresh()
Fire(quests, "QUEST_DETAIL")
quests.config.skipIDs, quests.config.onlyIDs = "", "202, 303"
quests:Refresh()
Fire(quests, "QUEST_DETAIL")
assert(accepted == 2, "a skipped or unlisted quest was accepted")
questID = 202
Fire(quests, "QUEST_DETAIL")
quests.config.onlyIDs, quests.config.firstTime = "", true
quests:Refresh()
questID, accountDone[303] = 303, true
Fire(quests, "QUEST_DETAIL")
assert(accepted == 3, "the only-list or the first-time filter was ignored")
quests.config.firstTime = false
quests:Refresh()

-- Gossip: completed quests are turned in before new ones are picked, once
-- per dialog; the choice resets when the dialog closes.
active = { { questID = 404, isComplete = false }, { questID = 405, isComplete = true } }
available = { { questID = 406 } }
Fire(quests, "GOSSIP_SHOW")
Fire(quests, "GOSSIP_SHOW")
assert(#selected == 1 and selected[1] == "turnin:405", "gossip did not turn in the completed quest once")
Fire(quests, "GOSSIP_CLOSED")
active = {}
Fire(quests, "GOSSIP_SHOW")
assert(#selected == 2 and selected[2] == "accept:406", "gossip did not pick the offered quest")
Fire(quests, "GOSSIP_CLOSED")

-- Turning the actions off releases their events.
quests.config.accept, quests.config.complete, quests.config.reward = false, false, false
quests:Refresh()
assert(not next(quests.context.events), "disabled quest actions kept their events")
quests:Disable()
print("Suite quest helpers: accept, complete, single rewards, manual costs, filters, gossip and events passed")
