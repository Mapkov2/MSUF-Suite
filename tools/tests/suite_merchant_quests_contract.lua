local root = assert(arg[1], "repository root required")
-- Merchant helpers (repair, junk selling) and quest automation: which visits
-- spend money, what stays manual, and which events stay registered.
local secret = {}
issecretvalue = function(value) return value == secret end
local combat, shift = false, false
local repairs, messages = {}, {}
local money, repairCost, canRepair, merchantRepairs = 500000, 30000, true, true
local guildAllowed, guildAllowance, guildFunds = false, 0, 0
local nativeJunk, nativeEnabled, nativeRequests = 3, true, 0

InCombatLockdown = function() return combat end
IsShiftKeyDown = function() return shift end
CanMerchantRepair = function() return merchantRepairs end
GetRepairAllCost = function() return repairCost, canRepair end
GetMoney = function() return money end
RepairAllItems = function(guild) repairs[#repairs + 1] = guild == true and "guild" or "own" end
CanGuildBankRepair = function() return guildAllowed end
GetGuildBankWithdrawMoney = function() return guildAllowance end
GetGuildBankMoney = function() return guildFunds end
C_MerchantFrame = {
    IsSellAllJunkEnabled = function() return nativeEnabled end,
    GetNumJunkItems = function() return nativeJunk end,
    SellAllJunkItems = function() nativeRequests = nativeRequests + 1 end,
}

local suite = { instances = {} }
suite.Public = function(value) return not issecretvalue(value) end
suite.Number = function(value) return suite.Public(value) and type(value) == "number" and value == value end
suite.Finite = function(value) return suite.Number(value) and value > -math.huge and value < math.huge end
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
------------------------------------------------------------------ merchant
local merchant = assert(suite.instances.qol)
merchant.active = true
merchant.context = Context()
merchant.config = { repair = true, repairLimit = 50, guildRepair = false, repairFallback = true,
    autoJunk = true, junkReport = true }
merchant:Enable()
assert(merchant.context.events.MERCHANT_SHOW and merchant.context.events.MERCHANT_CLOSED
    and not merchant.context.events.BAG_UPDATE_DELAYED, "merchant events were not registered on demand")

-- A visit repairs within the limit and delegates the eligible junk list to
-- Blizzard's native action (which applies backpack and bag exclusions).
Fire(merchant, "MERCHANT_SHOW")
assert(#repairs == 1 and repairs[1] == "own", "a repair within the limit did not use the player's money")
assert(nativeRequests == 1 and merchant.saleRequested,
    "junk was not delegated to Blizzard's native merchant API")
Fire(merchant, "MERCHANT_SHOW")
assert(nativeRequests == 1, "duplicate merchant event repeated the sale")
Fire(merchant, "MERCHANT_CLOSED")
assert(messages[1] == "Junk sale requested." and not merchant.saleRequested
    and not merchant.context.events.BAG_UPDATE_DELAYED, "closing the merchant misreported the request")
nativeJunk = 0

-- Costs above the limit or above the player's money are never paid.
repairs = {}
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
merchantRepairs = secret
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
merchantRepairs = true
assert(#repairs == 0, "an unreadable merchant repair capability authorized spending")

-- Native availability, unreadable counts, Shift and combat all fail closed.
repairs, messages = {}, {}
merchant.config.repair = false
nativeJunk = 14
nativeEnabled = false
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
nativeEnabled = secret
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
nativeEnabled, nativeJunk = true, secret
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
nativeJunk = math.huge
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
nativeJunk = 0
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
nativeJunk = 14
shift = secret
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
shift = true
Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
shift, combat = false, true
Fire(merchant, "MERCHANT_SHOW")
combat = false
Fire(merchant, "MERCHANT_CLOSED")
assert(nativeRequests == 1 and #messages == 0,
    "native gating, unreadable count, Shift or combat did not pause junk selling")

Fire(merchant, "MERCHANT_SHOW")
Fire(merchant, "MERCHANT_CLOSED")
assert(nativeRequests == 2 and messages[1] == "Junk sale requested.",
    "normal merchant visit did not resume native junk selling")

-- Turning both helpers off releases the merchant events.
merchant.config.repair, merchant.config.autoJunk = false, false
merchant:Refresh()
assert(not next(merchant.context.events), "disabled merchant helpers kept their events")
merchant:Disable()
print("Suite merchant: repair limits, guild order, native junk, pauses and events passed")

------------------------------------------------------------------ quests
local accepted, completed, rewards, selected = 0, 0, {}, {}
local questID, questCost, questChoices, completable = 101, 0, 1, true
local accountDone, trivial, logIndex, questInfo = {}, {}, {}, {}
local active, available = {}, {}
GetQuestMoneyToGet = function() return questCost end
GetQuestID = function() return questID end
AcceptQuest = function() accepted = accepted + 1 end
IsQuestCompletable = function() return completable end
CompleteQuest = function() completed = completed + 1 end
GetNumQuestChoices = function() return questChoices end
GetQuestReward = function(choice) rewards[#rewards + 1] = choice end
C_QuestLog = {
    IsQuestFlaggedCompletedOnAccount = function(id) return accountDone[id] == true end,
    IsQuestTrivial = function(id) return trivial[id] == true end,
    GetLogIndexForQuestID = function(id) return logIndex[id] end,
    GetInfo = function(index) return questInfo[index] end,
}
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
    skipTrivial = false, skipDaily = false, skipWeekly = false,
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

-- The new exclusions preserve old profiles until selected. Unknown quest
-- frequency stays manual when either repeatable-quest exclusion is enabled.
quests.config.skipTrivial = true
trivial[501] = true
questID = 501
Fire(quests, "QUEST_FINISHED")
Fire(quests, "QUEST_DETAIL")
assert(accepted == 3, "trivial quest was accepted")
quests.config.skipTrivial, quests.config.skipDaily = false, true
questID = 502
Fire(quests, "QUEST_DETAIL")
assert(accepted == 3, "unknown quest frequency was accepted")
logIndex[502], questInfo[1] = 1, { frequency = 1 }
Fire(quests, "QUEST_DETAIL")
assert(accepted == 3, "daily quest was accepted")
questInfo[1] = { frequency = 0 }
Fire(quests, "QUEST_DETAIL")
assert(accepted == 4, "ordinary quest with known frequency was not accepted")
quests.config.skipDaily, quests.config.skipWeekly = false, true
questID, logIndex[503], questInfo[2] = 503, 2, { frequency = 2 }
Fire(quests, "QUEST_FINISHED")
Fire(quests, "QUEST_DETAIL")
assert(accepted == 4, "weekly quest was accepted")

-- Gossip metadata is retained for the subsequent quest dialog, even after
-- Blizzard closes the gossip window during selection.
quests.config.skipDaily, quests.config.skipWeekly = true, true
active = {}
available = { { questID = 601, frequency = 1 }, { questID = 602, frequency = 2 },
    { questID = 603, frequency = 0 } }
Fire(quests, "GOSSIP_SHOW")
assert(selected[1] == "accept:603", "gossip did not skip daily and weekly offers")
Fire(quests, "GOSSIP_CLOSED")
questID = 603
Fire(quests, "QUEST_DETAIL")
assert(accepted == 5, "selected ordinary gossip quest lost its frequency metadata")
Fire(quests, "QUEST_FINISHED")
quests.config.skipTrivial = true
available = { { questID = 604, frequency = 0, isTrivial = secret },
    { questID = 605, frequency = 0, isTrivial = false } }
Fire(quests, "GOSSIP_SHOW")
assert(selected[2] == "accept:605", "unreadable triviality was not left manual")
Fire(quests, "GOSSIP_CLOSED")
Fire(quests, "QUEST_FINISHED")
questID = secret
Fire(quests, "QUEST_DETAIL")
assert(accepted == 5, "secret quest ID reached an automation decision")
quests.config.skipTrivial, quests.config.skipDaily, quests.config.skipWeekly = false, false, false
selected = {}

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
