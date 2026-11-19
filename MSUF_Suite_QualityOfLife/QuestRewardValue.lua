local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local M = { markers = {}, values = {}, pending = {} }
local ITEM_LOADED = "ITEM_DATA_LOAD_RESULT"
local IN_COMBAT = { inCombat = true }
local function Clear()
    for _, marker in pairs(M.markers) do marker:Hide() end
    for _, label in pairs(M.values) do label:Hide() end
    for id in pairs(M.pending) do M.pending[id] = nil end
    M.context:RemoveEvent(ITEM_LOADED)
end
local function ChoiceValue(button, log)
    local index = button:GetID()
    if not S.Finite(index) or index < 1 then return end
    local count, id
    if log then
        local _, _, quantity, _, _, item = GetQuestLogChoiceInfo(index)
        count, id = quantity, item
    else
        local _, _, quantity, _, _, item = GetQuestItemInfo("choice", index)
        count, id = quantity, item
    end
    if not S.Finite(id) or id <= 0 then return end

    -- Forever QuestInfo_ShowRewardAsItemCommon already loads the item through
    -- ItemEventListener in both views. Read the contextual price only from cache.
    if S.Finite(count) and count > 0 then
        local getLink = log and GetQuestLogItemLink or GetQuestItemLink
        local link = getLink("choice", index)
        local cached = S.PublicText(link) and C_Item.IsItemDataCachedByID(link)
        if S.Public(cached) and cached == true then
            local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(link)
            if S.Finite(price) and price >= 0 then return price * count end
        end
    end
    M.pending[id] = true
end
local function ShowValue(button, amount)
    if amount <= 0 then return end
    local label = M.values[button]
    if not label then
        label = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        M.values[button] = label
    end
    label:SetText(S.MoneyText(amount))
    label:Show()
end
local Draw
local function Loaded(_, _, id, success)
    if not S.Finite(id) or not M.pending[id] then return end
    M.pending[id] = nil
    if S.Public(success) and success == true then M.job:Request() end
    if not next(M.pending) then M.context:RemoveEvent(ITEM_LOADED) end
end
Draw = function()
    if not M.active or NS.InCombat() then return end
    local frame = QuestInfoFrame
    Clear()
    if not frame then return end
    local log = frame.questLog
    if not S.Public(log) then return end
    local quest = log and C_QuestLog.GetSelectedQuest() or GetQuestID()
    if not S.Finite(quest) then return end
    local rewards = frame.rewardsFrame
    if not rewards or not rewards:IsVisible() then return end
    local buttons = rewards.RewardButtons
    if type(buttons) ~= "table" then return end
    local best, maximum, missing = nil, 0, false
    for i = 1, math.min(#buttons, 100) do
        local button = buttons[i]
        if button:IsShown() and button.type == "choice" and button.objectType == "item" then
            local amount = ChoiceValue(button, log)
            if amount then
                ShowValue(button, amount)
                if amount > maximum then best, maximum = button, amount end
            else
                missing = true
            end
        end
    end
    if next(M.pending) then M.context:Event(ITEM_LOADED, Loaded, IN_COMBAT) end
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
    if M.active and not NS.InCombat() then M.job:Request() end
end
function M:Enable()
    self.job = self.context:Coalesce(0, Draw)
    self.context:Event("QUEST_FINISHED", Changed)
    self.context:Event("PLAYER_REGEN_DISABLED", function()
        M.job:Cancel()
        Clear()
    end, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", function()
        local rewards = QuestInfoFrame and QuestInfoFrame.rewardsFrame
        if rewards and rewards:IsVisible() then Changed() end
    end, IN_COMBAT)
    if not self.hooked then
        hooksecurefunc("QuestInfo_Display", Changed)
        hooksecurefunc("QuestInfo_ShowRewards", Changed)
        self.hooked = true
    end
    self:Refresh()
end
function M:Refresh() Changed() end
function M:Disable()
    Clear()
end
S.Install("questRewardValue", M)
