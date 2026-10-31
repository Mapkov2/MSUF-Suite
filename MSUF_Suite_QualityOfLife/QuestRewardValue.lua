local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local M = { markers = {}, pending = {}, requested = {} }
local IN_COMBAT = { inCombat = true }
local function Clear()
    for _, marker in pairs(M.markers) do marker:Hide() end
    for id in pairs(M.pending) do M.pending[id] = nil end
    M.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
end
local function Item(button, log)
    local index = button:GetID()
    if not S.Finite(index) or index < 1 then return end
    local count, id, link
    if log then
        local _, _, quantity, _, _, item = GetQuestLogChoiceInfo(index)
        count, id, link = quantity, item, GetQuestLogItemLink("choice", index)
    else
        local _, _, quantity, _, _, item = GetQuestItemInfo("choice", index)
        count, id, link = quantity, item, GetQuestItemLink("choice", index)
    end
    if S.Finite(id) and id > 0 and S.Finite(count) and count > 0 and S.PublicText(link) then return id, count, link end
end
local Draw
local function Loaded(_, _, id, success)
    if not S.Finite(id) or not M.pending[id] then return end
    M.pending[id], M.requested[id] = nil, "finished"
    if S.Public(success) and success == true then M.job:Request() end
    if not next(M.pending) then M.context:RemoveEvent("GET_ITEM_INFO_RECEIVED") end
end
Draw = function()
    if not M.active then return end
    Clear()
    local frame = QuestInfoFrame
    local log = frame.questLog
    if not S.Public(log) then return end
    local quest = log and C_QuestLog.GetSelectedQuest() or GetQuestID()
    if not S.Finite(quest) then return end
    if M.quest ~= quest or M.log ~= log then
        M.quest, M.log = quest, log
        for id in pairs(M.requested) do M.requested[id] = nil end
    end
    local rewards = frame.rewardsFrame
    if not rewards or not rewards:IsVisible() then return end
    local buttons = rewards.RewardButtons
    if type(buttons) ~= "table" then return end
    local best, maximum, missing = nil, 0, false
    for i = 1, math.min(#buttons, 100) do
        local button = buttons[i]
        if button:IsShown() and button.type == "choice" and button.objectType == "item" then
            local id, count, link = Item(button, log)
            if id then
                local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(link)
                if S.Finite(price) and price >= 0 then
                    if price * count > maximum then best, maximum = button, price * count end
                else
                    missing = true
                    if not M.requested[id] then
                        M.requested[id], M.pending[id] = true, true
                        M.context:Event("GET_ITEM_INFO_RECEIVED", Loaded, IN_COMBAT)
                        C_Item.RequestLoadItemDataByID(id)
                    elseif M.requested[id] == true then
                        M.pending[id] = true
                    end
                end
            else
                missing = true end
        end
    end
    if next(M.pending) then M.context:Event("GET_ITEM_INFO_RECEIVED", Loaded, IN_COMBAT) end
    if missing or not best then return end
    local marker = M.markers[best]
    if not marker then
        marker = S.CreateFrame("Frame", nil, best)
        marker:SetSize(16, 16)
        marker:SetPoint("TOPRIGHT", best, "TOPRIGHT", -2, -2)
        local icon = S.CreateTexture(marker, nil, "OVERLAY")
        icon:SetAllPoints(marker)
        icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        M.markers[best] = marker
    end
    marker:Show()
end
local function Changed()
    if M.active then M.job:Request() end
end
function M:Enable()
    self.job = self.context:Coalesce(0, Draw)
    if not self.hooked then
        hooksecurefunc("QuestInfo_Display", Changed)
        hooksecurefunc("QuestInfo_ShowRewards", Changed)
        self.hooked = true
    end
    self:Refresh()
end
function M:Refresh() self.job:Request() end
function M:Disable()
    Clear()
    self.quest = nil
end
S.Install("questRewardValue", M)
