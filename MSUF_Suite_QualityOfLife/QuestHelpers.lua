local _,P=...
local NS,S=P.NS,P.Suite
local M={}
local function Allowed(self,id)
    if not S.Public(id) or type(id)~="number" or id<=0 or self.skip[id] then return false end
    if self.hasOnly and not self.only[id] then return false end
    if self.config.firstTime then
        if not C_QuestLog or type(C_QuestLog.IsQuestFlaggedCompletedOnAccount)~="function" then return false end
        local done=C_QuestLog.IsQuestFlaggedCompletedOnAccount(id)
        if not S.Public(done) or done then return false end
    end
    return true
end
local function Gossip(self,event)
    if event=="GOSSIP_CLOSED" then self.gossipChosen=nil;return end
    if NS.IsCombatLocked() or (type(IsShiftKeyDown)=="function" and IsShiftKeyDown()) or not C_GossipInfo or self.gossipChosen then return end
    local selected,selector
    if self.config.complete and type(C_GossipInfo.GetActiveQuests)=="function" then
        local quests=C_GossipInfo.GetActiveQuests()
        if S.Public(quests) and type(quests)=="table" then
            for i=1,math.min(#quests,100) do
                local q=quests[i]
                if S.Public(q) and type(q)=="table" and S.Public(q.isComplete) and q.isComplete and Allowed(self,q.questID) then selected=q.questID;selector=C_GossipInfo.SelectActiveQuest;break end
            end
        end
    end
    if not selected and self.config.accept and type(C_GossipInfo.GetAvailableQuests)=="function" then
        local quests=C_GossipInfo.GetAvailableQuests()
        if S.Public(quests) and type(quests)=="table" then
            for i=1,math.min(#quests,100) do
                local q=quests[i]
                if S.Public(q) and type(q)=="table" and Allowed(self,q.questID) then selected=q.questID;selector=C_GossipInfo.SelectAvailableQuest;break end
            end
        end
    end
    if selected and type(selector)=="function" then self.gossipChosen=true;selector(selected) end
end
local function Quest(self,event)
    if event=="QUEST_FINISHED" then self.handled={}; return end
    if NS.IsCombatLocked() or (type(IsShiftKeyDown)=="function" and IsShiftKeyDown()) then return end
    local cost=type(GetQuestMoneyToGet)=="function" and GetQuestMoneyToGet() or nil
    -- A missing cost contract cannot authorize spending on a quest turn-in.
    if event~="QUEST_DETAIL" and (not S.Public(cost) or type(cost)~="number" or cost>0) then return end
    local questID=type(GetQuestID)=="function" and GetQuestID()
    if not Allowed(self,questID) then return end
    if self.handled[event]==questID then return end
    self.handled[event]=questID
    if event=="QUEST_DETAIL" and self.config.accept and type(AcceptQuest)=="function" then
        AcceptQuest()
    elseif event=="QUEST_PROGRESS" and self.config.complete and type(IsQuestCompletable)=="function" and type(CompleteQuest)=="function" then
        local ready=IsQuestCompletable()
        if S.Public(ready) and ready then CompleteQuest() end
    elseif event=="QUEST_COMPLETE" and self.config.reward and type(GetNumQuestChoices)=="function" and type(GetQuestReward)=="function" then
        local choices=GetNumQuestChoices()
        if S.Public(choices) and type(choices)=="number" and choices>=0 and choices<=1 then GetQuestReward(choices) end
    end
end
function M:Refresh()
    local ctx,c=self.context,self.config
    self.only,self.skip={},{}
    for id in c.onlyIDs:gmatch("%d+") do self.only[tonumber(id)]=true end
    for id in c.skipIDs:gmatch("%d+") do self.skip[tonumber(id)]=true end
    self.hasOnly=next(self.only)~=nil
    if c.gossip and (c.accept or c.complete) then ctx:Event("GOSSIP_SHOW",Gossip);ctx:Event("GOSSIP_CLOSED",Gossip)
    else ctx:RemoveEvent("GOSSIP_SHOW");ctx:RemoveEvent("GOSSIP_CLOSED");self.gossipChosen=nil end
    if c.accept then ctx:Event("QUEST_DETAIL",Quest) else ctx:RemoveEvent("QUEST_DETAIL") end
    if c.complete then ctx:Event("QUEST_PROGRESS",Quest) else ctx:RemoveEvent("QUEST_PROGRESS") end
    if c.reward then ctx:Event("QUEST_COMPLETE",Quest) else ctx:RemoveEvent("QUEST_COMPLETE") end
    if c.accept or c.complete or c.reward then ctx:Event("QUEST_FINISHED",Quest)
    else ctx:RemoveEvent("QUEST_FINISHED") end
end
function M:Enable() self.handled={}; self:Refresh() end
function M:Disable() self.handled={};self.gossipChosen=nil end
S.Install("quests",M)
