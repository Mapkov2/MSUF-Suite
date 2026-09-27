local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local Public = S.Public
local MAX_GOSSIP_QUESTS = 100

local function Allowed(self, id)
    if not Public(id) or type(id) ~= "number" or id <= 0 or self.skip[id] then return false end
    if self.hasOnly and not self.only[id] then return false end
    if self.config.firstTime then
        local done = C_QuestLog.IsQuestFlaggedCompletedOnAccount(id)
        if not Public(done) or done then return false end
    end
    return true
end

-- First allowed quest of a gossip list; completable ones only when required.
local function FirstQuest(self, quests, needComplete)
    if not Public(quests) or type(quests) ~= "table" then return nil end
    for i = 1, math.min(#quests, MAX_GOSSIP_QUESTS) do
        local quest = quests[i]
        if Public(quest) and type(quest) == "table"
            and (not needComplete or (Public(quest.isComplete) and quest.isComplete))
            and Allowed(self, quest.questID) then
            return quest.questID
        end
    end
    return nil
end

local function Gossip(self, event)
    if event == "GOSSIP_CLOSED" then
        self.gossipChosen = nil
        return
    end
    if NS.IsCombatLocked() or IsShiftKeyDown() or self.gossipChosen then return end
    if self.config.complete then
        local questID = FirstQuest(self, C_GossipInfo.GetActiveQuests(), true)
        if questID then
            self.gossipChosen = true
            C_GossipInfo.SelectActiveQuest(questID)
            return
        end
    end
    if self.config.accept then
        local questID = FirstQuest(self, C_GossipInfo.GetAvailableQuests(), false)
        if questID then
            self.gossipChosen = true
            C_GossipInfo.SelectAvailableQuest(questID)
        end
    end
end

local function Quest(self, event)
    if event == "QUEST_FINISHED" then
        for key in pairs(self.handled) do self.handled[key] = nil end
        return
    end
    if NS.IsCombatLocked() or IsShiftKeyDown() then return end
    local cost = GetQuestMoneyToGet()
    -- An unreadable cost cannot authorize spending on a quest turn-in.
    if event ~= "QUEST_DETAIL" and (not Public(cost) or type(cost) ~= "number" or cost > 0) then return end
    local questID = GetQuestID()
    if not Allowed(self, questID) or self.handled[event] == questID then return end
    self.handled[event] = questID
    local c = self.config
    if event == "QUEST_DETAIL" and c.accept then
        AcceptQuest()
    elseif event == "QUEST_PROGRESS" and c.complete then
        local ready = IsQuestCompletable()
        if Public(ready) and ready then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" and c.reward then
        local choices = GetNumQuestChoices()
        if Public(choices) and type(choices) == "number" and choices >= 0 and choices <= 1 then
            GetQuestReward(choices)
        end
    end
end

local function WantEvent(context, event, wanted, handler)
    if wanted then
        context:Event(event, handler)
    else
        context:RemoveEvent(event)
    end
end

function M:Refresh()
    local context, c = self.context, self.config
    self.only, self.skip = {}, {}
    for id in c.onlyIDs:gmatch("%d+") do self.only[tonumber(id)] = true end
    for id in c.skipIDs:gmatch("%d+") do self.skip[tonumber(id)] = true end
    self.hasOnly = next(self.only) ~= nil
    local gossip = c.gossip and (c.accept or c.complete)
    WantEvent(context, "GOSSIP_SHOW", gossip, Gossip)
    WantEvent(context, "GOSSIP_CLOSED", gossip, Gossip)
    if not gossip then self.gossipChosen = nil end
    WantEvent(context, "QUEST_DETAIL", c.accept, Quest)
    WantEvent(context, "QUEST_PROGRESS", c.complete, Quest)
    WantEvent(context, "QUEST_COMPLETE", c.reward, Quest)
    WantEvent(context, "QUEST_FINISHED", c.accept or c.complete or c.reward, Quest)
end

function M:Enable()
    self.handled = {}
    self:Refresh()
end

function M:Disable()
    self.handled = {}
    self.gossipChosen = nil
end

S.Install("quests", M)
