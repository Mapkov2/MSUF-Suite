local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_quest_text_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/QuestText.lua"))', 1, true))
-- Stand-ins let an unsafe comparison or formatting produce observable output.
issecretvalue = function(value) return value == 0.375 or value == 7 or value == "Restricted Quest Item" end
local body = [======[
local checks = 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local now, timers = 0, {}
local after = C_Timer.After
function C_Timer.After(delay, callback)
    if delay == 0 then return after(delay, callback) end
    assert(delay > 0, "invalid timer delay")
    timers[#timers + 1] = { due = now + delay, run = callback }
end
function C_Timer.NewTimer(delay, callback)
    local timer = { due = now + delay, run = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
local function ActiveTimers()
    local count = 0
    for _, timer in ipairs(timers) do if not timer.cancelled then count = count + 1 end end
    return count
end
local function Advance(seconds)
    now = now + seconds
    local scheduled = timers
    timers = {}
    for _, timer in ipairs(scheduled) do
        if not timer.cancelled then
            if timer.due <= now then timer.run(timer) else timers[#timers + 1] = timer end
        end
    end
end
local function NativeFrame(parent)
    local frame = { parent = parent, shown = true, alpha = 1, hooks = {} }
    function frame:GetParent() return self.parent end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:GetEffectiveAlpha() return self.alpha * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
    function frame:HookScript(event, callback)
        local prior = self.hooks[event]
        self.hooks[event] = prior and function(...) prior(...); callback(...) end or callback
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.onHide then self.onHide(self) end
        if self.hooks.OnHide then self.hooks.OnHide(self) end
    end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self.onShow then self.onShow(self) end
        if self.hooks.OnShow then self.hooks.OnShow(self) end
    end
    return frame
end
local function WithOpacity(text, parent)
    text.parent, text.alpha, text.shown = parent, 1, true
    text.GetAlpha = function(self) return self.alpha end
    text.SetAlpha = function(self, alpha) self.alpha = alpha end
    text.IsShown = function(self) return self.shown end
    text.IsVisible = function(self) return self.shown and self.parent:IsVisible() end
    return text
end
quest = NativeFrame()
QuestFrame = quest
QuestFrameDetailPanel = NativeFrame(quest)
QuestFrameProgressPanel = NativeFrame(quest)
QuestFrameRewardPanel = NativeFrame(quest)
QuestDetailScrollChildFrame = NativeFrame(QuestFrameDetailPanel)
QuestRewardScrollChildFrame = NativeFrame(QuestFrameRewardPanel)
QuestInfoSpacerFrame = NativeFrame(QuestDetailScrollChildFrame)
QuestInfoObjectivesText = WithOpacity(Text(QuestDetailScrollChildFrame, 0.2, 0.1, 0.1), QuestDetailScrollChildFrame)
QuestInfoObjectivesHeader = WithOpacity(Text(QuestDetailScrollChildFrame, 0.3, 0.2, 0.1), QuestDetailScrollChildFrame)
local objectiveText = ""
function GetObjectiveText() return objectiveText end
function QuestInfoObjectivesText:GetText() return self.value end
function QuestInfoSpacerFrame:GetPoint(index)
    assert(index == 1)
    return "TOPLEFT", self.anchor, "BOTTOMLEFT", 0, -20
end
local offerXP, rewardXP, rewardMoney = nil, 0, 0
local offerItems = { choice = {}, reward = {} }
local questID, logData, loadCallbacks, preloads = 2846, { [2846] = {} }, {}, {}
local itemData, itemCallbacks = {}, {}
C_Item = {
    GetItemNameByID = function(id) return itemData[id] end,
    IsItemDataCachedByID = function(id) return itemData[id] ~= nil end,
}
ItemEventListener = { AddCallback = function(_, id, callback) itemCallbacks[id] = callback end }
function GetQuestID() return questID end
local function NotFading() return false end
UIFrameIsFading = NotFading
local atMaxLevel = false
GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return atMaxLevel end }
function GetQuestItemInfoLootType() return 0 end
function HaveQuestRewardData(id) return logData[id] ~= nil end
QuestEventListener = { AddCallback = function(_, id, callback) loadCallbacks[id] = callback end }
C_TaskQuest = { RequestPreloadRewardData = function(id) preloads[id] = (preloads[id] or 0) + 1 end }
local function LogData(id)
    assert(type(id) == "number", "queried rewards for the selected quest")
    return logData[id] or {}
end
function GetNumQuestLogChoices(id) return #(LogData(id).choice or {}) end
function GetNumQuestLogRewards(id) return #(LogData(id).reward or {}) end
function GetQuestLogRewardXP(id) return LogData(id).xp or 0 end
function GetQuestLogRewardMoney(id) return LogData(id).money or 0 end
local function LogItem(kind, index, id)
    local item = (LogData(id)[kind] or {})[index]
    if item then return item.name, 1, item.count or 1, 2, true, item.itemID end
end
function GetQuestLogChoiceInfo(index, id) return LogItem("choice", index, id) end
function GetQuestLogRewardInfo(index, id) return LogItem("reward", index, id) end
function QuestDetailScrollChildFrame:CreateFontString()
    local region = NativeFrame(self)
    function region:SetPoint(_, owner) self.anchor = owner end
    function region:ClearAllPoints() self.anchor = nil end
    function region:SetWidth() end
    function region:SetJustifyH() end
    function region:SetText(text) self.text = text end
    function region:SetTextColor() end
    offerXP = region
    return region
end
local eventFrames = {}
local function DeliverQuestEvent(event)
    local deliveries = 0
    if QuestFrame.hooks.OnEvent then
        deliveries = deliveries + 1
        QuestFrame.hooks.OnEvent(QuestFrame, event)
    end
    for _, frame in ipairs(eventFrames) do
        if frame.events[event] then
            deliveries = deliveries + 1
            frame.onEvent(frame, event)
        end
    end
    return deliveries
end
function CreateFrame(kind, parent)
    assert(kind == "Frame" and parent == nil)
    local frame = NativeFrame()
    function frame:SetScript(script, callback)
        assert(script == "OnEvent")
        self.onEvent = callback
        self.events = {}
        eventFrames[#eventFrames + 1] = self
    end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetParent(owner) self.parent = owner end
    function frame:SetPoint(_, owner) self.anchor = owner end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:CreateFontString(...)
        local label = QuestDetailScrollChildFrame.CreateFontString(self, ...)
        function label:SetText(text) self.text, frame.text = text, text end
        function label:GetStringHeight()
            local _, newlines = self.text:gsub("\n", "")
            return (newlines + 1) * 12
        end
        frame.label, offerXP = label, frame
        return label
    end
    return frame
end
function GetRewardXP() return rewardXP end
function GetRewardMoney() return rewardMoney end
function GetMoneyString(value) return tostring(value) .. " coins" end
function BreakUpLargeNumbers(value) return tostring(value) end
EXPERIENCE_COLON = "Experience:"
QUEST_REWARDS = "Rewards"
REWARD_CHOICES = "You may choose one of these rewards:"
REWARD_ITEMS = "You will also receive:"
REWARD_ITEMS_ONLY = "You will receive:"
function GetNumQuestChoices() return #offerItems.choice end
function GetNumQuestRewards() return #offerItems.reward end
function GetQuestItemInfo(kind, index)
    local item = offerItems[kind][index]
    if item then return item.name, 1, item.count or 1, 2, true, item.itemID end
end
local function HasOfferText(text)
    return offerXP and offerXP:IsVisible() and type(offerXP.text) == "string" and offerXP.text:find(text, 1, true)
end
-- A native Button fires OnEnable when Enable() changes its state. The skin
-- observes that script; it must not replace the button's Enable member.
local nativeEnable
QuestFrameAcceptButton = { enabled = true, scriptHooks = {},
    IsEnabled = function(self) return self.enabled end,
    Enable = function(self)
        local changed = not self.enabled
        self.enabled = true
        if changed and self.scriptHooks.OnEnable then self.scriptHooks.OnEnable(self) end
    end,
    HookScript = function(self, event, callback) self.scriptHooks[event] = callback end,
}
nativeEnable = QuestFrameAcceptButton.Enable
WithOpacity(QuestInfoRewardText, QuestDetailScrollChildFrame)
WithOpacity(QuestInfoTitleHeader, QuestDetailScrollChildFrame)
local rewards = NativeFrame(QuestDetailScrollChildFrame)
function rewards:GetPoint(index)
    assert(index == 1)
    return "TOPLEFT", self.anchor, "BOTTOMLEFT", 0, -15
end
rewards.XPFrame, rewards.MoneyFrame = NativeFrame(rewards), NativeFrame(rewards)
rewards.Header = WithOpacity(Text(rewards, 0.2, 0.1, 0.1), rewards)
rewards.ItemChooseText = Text(rewards, 0.1, 0.1, 0.1)
QuestInfoRewardsFrame = rewards
QuestInfoFrame = { itemChoice = 0 }
local completed, continued = 0, 0
local nativeFades = false
local choices = {}
for index = 1, 2 do
    local button = NativeFrame(rewards)
    button.click = function() QuestInfoFrame.itemChoice = index end
    choices[index] = button
end
-- QuestInfo_Display anchors the spacer to the last native element. A standalone
-- QuestInfo_ShowRewards refresh changes rows, but does not rebuild that anchor.
local function PopulateNative(choicesShown, fixedShown, xpShown, moneyShown, layOut)
    rewards.activeRewardElements, rewards.RewardButtons = {}, {}
    local function AddItem(kind, index)
        local item = offerItems[kind][index]
        local row = NativeFrame(rewards)
        row.type, row.objectType, row.questID = kind, "item", questID
        function row:GetID() return index end
        row.Name = NativeFrame(row)
        function row.Name:GetText() return item.name end
        rewards.RewardButtons[#rewards.RewardButtons + 1] = row
        rewards.activeRewardElements[#rewards.activeRewardElements + 1] = row
    end
    for i = 1, choicesShown do AddItem("choice", i) end
    for i = 1, fixedShown do AddItem("reward", i) end
    rewards.XPFrame.shown, rewards.MoneyFrame.shown = xpShown, moneyShown
    if xpShown then table.insert(rewards.activeRewardElements, rewards.XPFrame) end
    if layOut then
        if rewards.shown then rewards.anchor = QuestInfoObjectivesText end
        QuestInfoSpacerFrame.anchor = rewards.shown and
            (rewards.activeRewardElements[#rewards.activeRewardElements] or rewards.Header) or QuestInfoObjectivesText
    end
end
rewards.activeRewardElements, rewards.RewardButtons = {}, {}
local firstClick, secondClick = choices[1].click, choices[2].click
local function Complete()
    if QuestInfoFrame.itemChoice > 0 then completed = completed + 1 end
end
QuestFrameCompleteQuestButton = { click = Complete }

-- Lifecycle model from Blizzard_UIPanels_Game/Mainline/{QuestFrame,QuestInfo}.lua:
-- shared elements are reparented by Display; Forever Detail hides them AFTER
-- Display and its OnHide restores them. Current Retail has no reading fade.
-- Reward hides Progress and reuses the same elements on both clients.
-- The normal sequence is deliberately tested separately from stale-state recovery.
local function NativeDisplay(parent)
    QuestInfoTitleHeader.parent, QuestInfoRewardText.parent, rewards.parent = parent, parent, parent
    QuestInfoRewardText.shown, rewards.shown = true, true
    QuestInfoSpacerFrame.parent, QuestInfoSpacerFrame.anchor = parent, rewards.Header
    if callbacks.QuestInfo_Display then callbacks.QuestInfo_Display() end
end
local mayShow, fullOffer, nativeOffers = false, true, 0
C_QuestLog = { ShouldShowQuestRewards = function(id) return id == questID and mayShow end }
QUEST_TEMPLATE_DETAIL = {}
WorldMapFrame, QuestLogPopupDetailFrame = NativeFrame(), NativeFrame()
WorldMapFrame:Hide()
QuestLogPopupDetailFrame:Hide()
function QuestFrame_GetMaterial() return "Parchment", true end
function QuestInfo_Display(template, parent, button, material, ...)
    Check(select("#", ...) == 0, "material contrast flag became mapView on the NPC offer")
    assert(template == QUEST_TEMPLATE_DETAIL and parent == QuestDetailScrollChildFrame
        and button == QuestFrameAcceptButton and material == "Parchment", "rebuilt a foreign quest template")
    nativeOffers = nativeOffers + 1
    if fullOffer then
        QuestInfoObjectivesText.value = GetObjectiveText()
        rewards.shown, rewards.parent = true, parent
        PopulateNative(#offerItems.choice, #offerItems.reward, rewardXP > 0, rewardMoney > 0, true)
    end
    if callbacks.QuestInfo_Display then callbacks.QuestInfo_Display() end
end
QuestInfo_ShowRewards = function() rewards.shown = true end
QuestFrameDetailPanel.onShow = function(self)
    QuestFrameRewardPanel:Hide()
    QuestFrameProgressPanel:Hide()
    NativeDisplay(QuestDetailScrollChildFrame)
    if nativeFades then
        self.fading = 1
        QuestFrameAcceptButton.enabled = false
        QuestInfoRewardText:SetAlpha(0)
        rewards:SetAlpha(0)
    end
end
QuestFrameDetailPanel.onHide = function()
    if nativeFades then
        QuestInfoRewardText:SetAlpha(1)
        rewards:SetAlpha(1)
    end
end
QuestFrameProgressPanel.onShow = function()
    QuestFrameDetailPanel:Hide()
    QuestFrameRewardPanel:Hide()
end
QuestFrameRewardPanel.onShow = function()
    QuestFrameDetailPanel:Hide()
    QuestFrameProgressPanel:Hide()
    NativeDisplay(QuestRewardScrollChildFrame)
    -- The outer native page fade is separate from the shared objects.
    if nativeFades then QuestRewardScrollChildFrame:SetAlpha(0.25) end
end
local function Continue()
    continued = continued + 1
    QuestFrameRewardPanel:Hide()
    QuestFrameRewardPanel:Show()
end
QuestFrameCompleteButton = { click = Continue }
local function Stale()
    QuestInfoRewardText:SetAlpha(0)
    QuestInfoRewardText.color[4] = 0
    rewards:SetAlpha(0)
end
local function Recovered(label)
    Check(QuestInfoRewardText.alpha == 1 and QuestInfoRewardText.color[4] == 1, label .. ": text opacity")
    Check(rewards.alpha == 1 and choices[1]:IsVisible() and choices[2]:IsVisible(), label .. ": reward choices")
    Check(QuestRewardScrollChildFrame.alpha == (nativeFades and 0.25 or 1), label .. ": outer native fade changed")
end
local override = os.getenv("SUITE_QUEST_TEXT_OVERRIDE")
assert(loadfile(override or root .. "/MSUF_Suite_Skin/Adapters/QuestText.lua"))("MSUF_Suite_Skin", NS)
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client = { isForever = flavor == "Forever" }
    nativeFades = NS.Client.isForever
    QuestFrameDetailPanel:Hide()
    QuestFrameProgressPanel:Hide()
    QuestFrameRewardPanel:Hide()
    NS.QuestText.Activate(quest, "quest")
    local closedDeliveries = 0
    for _ = 1, 300 do closedDeliveries = closedDeliveries + DeliverQuestEvent("QUEST_LOG_UPDATE") end
    Check(closedDeliveries == 0, "skin received quest log events without a visible quest offer")
    QuestFrameDetailPanel:Show()
    NextFrame()
    local expected = nativeFades and 0 or 1
    Check(QuestInfoRewardText.alpha == expected and rewards.alpha == expected, "native detail opacity overridden")
    Check(callbacks[QuestFrameAcceptButton] == nil and QuestFrameAcceptButton.Enable == nativeEnable,
        "a member of the native Accept button was hooked")
    if nativeFades then
        QuestFrameDetailPanel.fading = nil
        QuestFrameAcceptButton:Enable()
        NextFrame()
        Check(rewards.alpha == 1 and QuestInfoRewardText.alpha == 1, "offer rewards stayed transparent after reading")
        rewardXP, rewards.shown = 3950, false
        PopulateNative(0, 0, false, false, true)
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(offerXP and offerXP:IsVisible() and offerXP.anchor == QuestInfoObjectivesText
            and offerXP.text == "Rewards\n" .. REWARD_ITEMS_ONLY .. "\nExperience: 3950",
            "XP-only fallback did not follow the offer objectives")
        rewards.shown = true
        PopulateNative(0, 0, true, false, true)
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not offerXP:IsShown(), "fallback duplicated Blizzard's reward")
        rewards.shown, rewardXP = false, 0.375
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not offerXP:IsShown(), "secret XP was formatted")
        rewardXP, rewardMoney = 0, 1250
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("1250 coins") and not HasOfferText(EXPERIENCE_COLON), "offer without XP lost its money reward")

        offerItems.choice = { { name = "Gemshale Pauldrons", count = 1 }, { name = "Dank Shoulderpads", count = 1 } }
        offerItems.reward = { { name = "Spellshifter Rod", count = 1 } }
        rewardXP = 3950
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText(REWARD_CHOICES) and HasOfferText("Gemshale Pauldrons") and HasOfferText("Dank Shoulderpads"),
            "Forever offer without a native reward block lost its item choices")
        Check(HasOfferText(REWARD_ITEMS) and HasOfferText("Spellshifter Rod"),
            "Forever offer without a native reward block lost its guaranteed item")
        Check(HasOfferText("Experience: 3950") and HasOfferText("1250 coins"),
            "item preview hid the XP or money from the same offer")

        rewards.shown = true
        PopulateNative(2, 1, true, true, true)
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not offerXP:IsShown(), "item preview duplicated Blizzard's reward block")

        -- A native item refresh can show the reused frame without relocating it.
        rewards.parent = QuestRewardScrollChildFrame
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("Gemshale Pauldrons") and HasOfferText("Dank Shoulderpads"),
            "off-page native rewards suppressed the current offer preview")
        rewards.parent = QuestDetailScrollChildFrame
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not offerXP:IsShown(), "item preview survived the native reward block's return")

        rewards.shown, rewardXP, rewardMoney = false, 0, 0
        offerItems.choice, offerItems.reward = {}, { { count = 1 } }
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(not offerXP:IsShown(), "new offer with cold item data displayed stale rewards")
        offerItems.reward[1].name = "Spellshifter Rod"
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("Spellshifter Rod") and HasOfferText(REWARD_ITEMS_ONLY),
            "late reward data did not populate the guaranteed-item preview")
        Check(not HasOfferText("Gemshale Pauldrons") and not HasOfferText("Dank Shoulderpads"),
            "current offer preview retained the earlier choice items")
        offerItems.choice = { { name = "Restricted Quest Item", count = 1 } }
        offerItems.reward[1].count = 7
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not HasOfferText("Restricted Quest Item") and not HasOfferText("7"),
            "preview formatted a restricted item name or quantity")

        offerItems.choice, offerItems.reward[1].count = {}, 1
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("Spellshifter Rod"), "readable offer did not recover after restricted data")
    end
    do
        -- Saving Sharpbeak: native ShowRewards may leave a correctly parented
        -- shell with some displayed rows while the offer knows more rewards.
        questID = 2994
        logData[questID] = {}
        offerItems.choice = { { name = "Gryphon Rider's Stormhammer" }, { name = "Gryphon Rider's Leggings" },
            { name = "Gryphon Rider's Grip" } }
        offerItems.reward, rewardXP, rewardMoney = {}, 7350, 22500
        rewards.shown = true
        PopulateNative(0, 0, false, false, true)
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(HasOfferText("Stormhammer") and HasOfferText("Leggings") and HasOfferText("Grip") and HasOfferText("7350")
            and HasOfferText("22500"), "empty attached native shell suppressed Saving Sharpbeak rewards")
        PopulateNative(1, 0, true, false, true)
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("Leggings") and HasOfferText("22500"), "partial native render omitted the remaining rewards")
        Check(not HasOfferText("Stormhammer") and not HasOfferText("7350"), "partial native render duplicated visible rewards")
        rewards.shown = false
        rewards.anchor = QuestInfoRewardText -- prior page's preceding paragraph
        PopulateNative(0, 0, false, false, true)
        rewards.shown = true
        PopulateNative(3, 0, true, true, false)
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("Stormhammer") and HasOfferText("Leggings"), "standalone refresh only populated the old layout")
        PopulateNative(3, 0, true, true, true)
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(not offerXP:IsShown(), "a complete new native layout retained duplicate preview rows")
        if nativeFades then
            rewards.alpha = 0
            local fading = true
            UIFrameIsFading = function(region) return fading and region == rewards end
            callbacks.QuestInfo_ShowRewards()
            NextFrame()
            Check(rewards.alpha == 0, "offer recovery interrupted the native fade")
            fading = false
            Advance(0.71)
            NextFrame()
            Check(rewards.alpha == 1, "shown choice rows stayed transparent after the native offer fade")
            UIFrameIsFading = NotFading
        end

        -- A cold offer can have zero active-offer values before acceptance.
        -- The quest-scoped result arrives before the loot cache in this sequence.
        questID, offerItems.choice, rewardXP, rewardMoney = 2995, {}, 0, 0
        logData[questID], loadCallbacks[questID], preloads[questID] = nil, nil, nil
        rewards.shown = false
        PopulateNative(0, 0, false, false, true)
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(not offerXP:IsShown() and preloads[questID] == 1, "cold offer inherited choices or did not preload reward data")
        local loaded = assert(loadCallbacks[questID], "cold offer did not request its quest data")
        for i = 1, 20 do
            Check(DeliverQuestEvent("QUEST_LOG_UPDATE") == 1, "open cold offer missed or duplicated a quest log event")
        end
        Check(DeliverQuestEvent("QUEST_FINISHED") == 0, "open cold offer received unrelated native events")
        Check(#queuedJobs == 0, "unrelated log updates repeatedly repainted an offer with unavailable reward data")
        loaded()
        NextFrame()
        Check(preloads[questID] == 1, "an early quest data result repeatedly requested its reward payload")
        logData[questID] = { choice = { { name = "Cached Choice" } }, reward = { { name = "Cached Item" } },
            money = 1234, xp = 888 }
        DeliverQuestEvent("QUEST_LOG_UPDATE")
        NextFrame()
        Check(HasOfferText("Cached Choice") and HasOfferText("Cached Item") and HasOfferText("888")
            and HasOfferText("1234"), "explicit quest reward data did not hydrate a still-open cold offer")
        offerItems.choice, questID = { { itemID = 9534 } }, 2996
        itemData[9534], itemCallbacks[9534] = nil, nil
        callbacks.QuestInfo_Display()
        NextFrame()
        loaded()
        NextFrame()
        Check(not HasOfferText("Cached Choice") and not HasOfferText("Cached Item"), "an earlier offer leaked into the next one")
        itemData[9534] = "Newly Loaded Axe"
        local loadedItem = assert(itemCallbacks[9534], "missing callback for a cold item's name")
        loadedItem()
        NextFrame()
        Check(HasOfferText("Newly Loaded Axe"), "item cache resolved without painting the current offer")
        questID, offerItems.choice = 2846, {}
        callbacks.QuestInfo_Display()
        NextFrame()
        loadedItem()
        NextFrame()
        Check(not HasOfferText("Newly Loaded Axe"), "retired item callback leaked into another quest")
        -- A count may arrive before its active-offer names and IDs. Only
        -- supplement a slot when the quest-scoped payload can identify it.
        questID, offerItems.choice = 2997, { {} }
        logData[questID] = { choice = { { name = "Warm Quest-Scoped Blade", itemID = 6842 } } }
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(HasOfferText("Warm Quest-Scoped Blade"), "active count with empty slot suppressed matching cached choice")
        offerItems.choice[1].itemID = 0
        logData[questID].xp, atMaxLevel = 888, true
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(HasOfferText("Warm Quest-Scoped Blade") and not HasOfferText("888"),
            "zero item ID lost the available choice or max-level offer displayed unavailable XP")
        Check(offerXP.parent == QuestDetailScrollChildFrame and offerXP.height >= offerXP.label:GetStringHeight(),
            "scroll content did not include the height of the entire offer preview")
        atMaxLevel = false
        offerItems.choice[1].itemID = 9864
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not HasOfferText("Warm Quest-Scoped Blade"), "explicit quest row replaced a different active item ID")
        offerItems.choice[1].itemID = nil
        logData[questID].choice[2] = { name = "Unmatched Choice" }
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(not HasOfferText("Warm Quest-Scoped Blade") and not HasOfferText("Unmatched Choice"),
            "ambiguous cached choices replaced an unidentifiable active slot")
        -- In a real NPC detail context Blizzard can now lay out its own rows.
        questID, mayShow, fullOffer = 3007, true, true
        logData[questID] = {}
        itemData[9841], itemData[9842] = "Native Hammer", "Native Boots"
        offerItems.choice = { { name = itemData[9841], itemID = 9841 }, { name = itemData[9842], itemID = 9842 } }
        QuestInfoFrame.acceptButton, QuestInfoFrame.rewardsFrame = QuestFrameAcceptButton, rewards
        QuestInfoFrame.questLog, QuestInfoFrame.mapView = nil, nil
        rewards.shown = false
        PopulateNative(0, 0, false, false, true)
        local before = nativeOffers
        if nativeFades then
            QuestFrameDetailPanel.fading = 1
            callbacks.QuestInfo_Display()
            NextFrame()
            Check(nativeOffers == before, "offer visualization restarted the NPC reading fade")
            QuestFrameDetailPanel.fading = nil
        end
        WorldMapFrame:Show()
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(nativeOffers == before, "offer visualization rewrote the map's shared widgets")
        WorldMapFrame:Hide()
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 1 and rewards:IsVisible() and #rewards.RewardButtons == 2,
            "warm active offer did not recover the native reward item buttons")
        local second = rewards.RewardButtons[2]
        Check(second:GetParent() == rewards and second.questID == questID and second.type == "choice"
            and second:GetID() == 2 and second.Name:GetText() == "Native Boots" and second:IsVisible(),
            "native item tooltip lost its live offer kind, index or current row")
        Check(not HasOfferText("Native Hammer") and not HasOfferText("Native Boots")
            and QuestInfoFrame.itemChoice == 0, "native offer buttons duplicated text or selected an item")
        for i = 1, 8 do callbacks.QuestInfo_ShowRewards() end
        NextFrame()
        Check(nativeOffers == before + 1, "healthy native item rows kept rebuilding the offer")
        questID, fullOffer = 3008, false
        logData[questID] = {}
        rewards.shown = false
        PopulateNative(0, 0, false, false, true)
        callbacks.QuestInfo_Display()
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 2 and HasOfferText("Native Boots"), "unsuccessful native layout removed fallback rewards")
        for i = 1, 8 do callbacks.QuestInfo_ShowRewards(); NextFrame() end
        Check(nativeOffers == before + 2, "unfinished native layout retried indefinitely")
        questID, offerItems.choice = 3009, {}
        logData[questID] = { choice = { { name = "Log-only Reward", itemID = 9843 } } }
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(nativeOffers == before + 2 and HasOfferText("Log-only Reward"),
            "quest-log-only item caused a native offer rebuild")
        questID, rewardXP, rewardMoney = 3010, 1494, 0
        logData[questID], fullOffer, mayShow = {}, true, true
        offerItems.choice, offerItems.reward = {}, {}
        objectiveText, QuestInfoObjectivesText.value = "Search near the stables for the missing horses.", ""
        rewards.shown = false
        PopulateNative(0, 0, false, false, true)
        before = nativeOffers
        callbacks.QuestInfo_Display()
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 1 and QuestInfoObjectivesText.value == objectiveText and rewards:IsVisible()
            and rewards.XPFrame:IsShown() and not rewards.MoneyFrame:IsShown() and not offerXP:IsShown(),
            "first Foal Play offer did not recover the native objectives and XP-only reward")
        questID, rewardXP, rewardMoney, mayShow = 3011, 0, 0, false
        logData[questID] = { xp = 2936, money = 2000 }
        objectiveText = "Kill 8 Mudfin Oracles and 8 Mudfin Murlocs."
        QuestInfoObjectivesText.value, rewards.shown = objectiveText, false
        PopulateNative(0, 0, false, false, true)
        QuestInfoSpacerFrame.anchor = rewards.Header
        callbacks.QuestInfo_Display()
        NextFrame()
        Check(offerXP.anchor == QuestInfoObjectivesText and HasOfferText("2000 coins\nExperience: 2936")
            and not HasOfferText("1494"), "second offer's cold rewards were misplaced or carried over")
        rewardXP, rewardMoney, mayShow = 2936, 2000, true
        DeliverQuestEvent("QUEST_LOG_UPDATE")
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 2 and rewards:IsVisible() and rewards.anchor == QuestInfoObjectivesText
            and rewards.XPFrame:IsShown() and rewards.MoneyFrame:IsShown() and not offerXP:IsShown(),
            "late active Freshwater Fiends amounts did not replace the fallback under the objectives")
        if nativeFades then
            QuestInfoObjectivesHeader:SetAlpha(0)
            QuestInfoObjectivesText:SetAlpha(0)
            QuestInfoObjectivesHeader.color[4], QuestInfoObjectivesText.color[4] = 0, 0
            Advance(0.71)
            NextFrame()
            Check(QuestInfoObjectivesHeader.alpha == 1 and QuestInfoObjectivesText.alpha == 1
                and QuestInfoObjectivesHeader.color[4] == 1 and QuestInfoObjectivesText.color[4] == 1,
                "native reading cleanup left an invisible gap before the XP and silver")
        end
        for i = 1, 8 do
            Check(DeliverQuestEvent("QUEST_LOG_UPDATE") == 0, "complete visible offer still receives quest log events")
        end
        Check(nativeOffers == before + 2 and #queuedJobs == 0, "healthy XP and silver page kept painting")
        -- XP may be ready in the native UI while both the objective and the
        -- active money value are still missing from an already cached quest.
        questID, logData[3012], rewardMoney, objectiveText = 3012, {}, 0, ""
        QuestInfoObjectivesText.value = ""
        PopulateNative(0, 0, true, false, true)
        callbacks.QuestInfo_Display()
        NextFrame()
        objectiveText = "Kill the remaining murlocs."
        DeliverQuestEvent("QUEST_LOG_UPDATE")
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 3 and QuestInfoObjectivesText.value == objectiveText
            and not rewards.MoneyFrame:IsShown(), "late objective text alone did not restore the native paragraph")
        rewardMoney = 2000
        DeliverQuestEvent("QUEST_LOG_UPDATE")
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 4 and QuestInfoObjectivesText.value == objectiveText
            and rewards.MoneyFrame:IsVisible() and not offerXP:IsShown(),
            "a previously healthy XP row suppressed the late objective or silver")
        rewards.anchor, QuestInfoSpacerFrame.anchor = QuestInfoRewardText, rewards.Header
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 5 and rewards.anchor == QuestInfoObjectivesText and not offerXP:IsShown(),
            "a spacer pointing into a misplaced rewards frame concealed its stale anchor")
        questID, logData[3013], offerItems.reward = 3013, {}, { { itemID = 9900 } }
        QuestInfoObjectivesText.value, rewards.shown = "", false
        PopulateNative(0, 0, false, false, true)
        callbacks.QuestInfo_Display()
        NextFrame()
        NextFrame()
        Check(nativeOffers == before + 6 and rewards.XPFrame:IsVisible() and rewards.MoneyFrame:IsVisible()
            and QuestInfoObjectivesText.value == objectiveText, "an uncached item held back active objectives and amounts")
        offerItems.reward = {}
        if nativeFades then
            questID, mayShow, rewards.shown = 3014, false, false
            logData[questID] = { xp = 2936 }
            PopulateNative(0, 0, false, false, true)
            UIFrameIsFading = function(region) return region == QuestInfoObjectivesText end
            callbacks.QuestInfo_Display()
            NextFrame()
            Check(not offerXP:IsShown(), "full-opacity fallback jumped ahead of its fading native anchor")
            UIFrameIsFading = NotFading
            Advance(0.71)
            NextFrame()
            Check(offerXP:IsVisible() and offerXP.anchor == QuestInfoObjectivesText,
                "fallback did not appear under the objectives once their native fade finished")
        end
        objectiveText, rewardXP, rewardMoney = "", 0, 0
        questID, offerItems.choice, mayShow = 2846, {}, false
    end
    QuestFrameProgressPanel:Show()
    Check(DeliverQuestEvent("QUEST_LOG_UPDATE") == 0, "hidden offer still receives quest log events")
    Check(DeliverQuestEvent("QUEST_FINISHED") == 0, "inactive skin still receives native quest events")
    -- The fallback line hides with its parent page at once and is settled after the build.
    if nativeFades then Check(not offerXP:IsVisible(), "offer summary stayed visible on progress") end
    NextFrame()
    if nativeFades then Check(not offerXP:IsShown(), "offer summary survived the move to progress") end
    Check(rewards.alpha == 1, "fixture lost native detail OnHide restoration")
    QuestFrameCompleteButton.click()
    NextFrame()
    Recovered("ordinary progress to reward")
    if nativeFades then
        Check(not offerXP:IsVisible() and not offerXP:IsShown(), "offer preview carried into the choice page")
        offerItems.reward = {}
    end
    -- Recovery inputs represent the reported blank shared content. They do not
    -- claim the ordinary native sequence above creates this stale state itself.
    Stale()
    callbacks.QuestInfo_Display()
    NextFrame()
    Recovered("already-stale shared widgets")
    for _ = 1, 12 do callbacks.QuestInfo_Display() end
    Check(#queuedJobs == 1, "page burst queued multiple settlements")
    Stale()
    NextFrame()
    Recovered("write after synchronous page hook")
    Check(#queuedJobs == 0, "settlement became a polling loop")
    Stale()
    callbacks.QuestInfo_ShowRewards()
    NextFrame()
    Recovered("late reward item data")
    Check(QuestInfoFrame.itemChoice == 0 and completed == 0, "skin chose or completed a reward")
    Check(choices[1].click == firstClick and choices[2].click == secondClick
        and QuestFrameCompleteQuestButton.click == Complete, "native click scripts changed")
    choices[2].click()
    QuestFrameCompleteQuestButton.click()
    Check(QuestInfoFrame.itemChoice == 2 and completed == 1, "native reward selection/completion failed")
    QuestInfoFrame.itemChoice, completed = 0, 0

    callbacks.QuestInfo_Display()
    QuestFrameRewardPanel:Hide()
    Stale()
    NextFrame()
    Check(rewards.alpha == 0 and QuestInfoRewardText.color[4] == 0, "closed page repaired by delayed job")
    QuestFrameRewardPanel:Show()
    callbacks.QuestInfo_Display()
    rewards.parent, QuestInfoRewardText.parent = other, other
    Stale()
    NextFrame()
    Check(rewards.alpha == 0 and QuestInfoRewardText.alpha == 0, "reparented map/popup content revealed")
    NativeDisplay(QuestRewardScrollChildFrame)
    callbacks.QuestInfo_Display()
    NS.QuestText.Deactivate(quest, "quest")
    Stale()
    NextFrame()
    Check(rewards.alpha == 0 and QuestInfoRewardText.color[4] == 0, "disabled skin repaired queued content")
    NS.QuestText.Activate(quest, "quest")
    Recovered("enable on already-open reward page")
    NextFrame()

    -- Recovery respects native hidden state even inside a shown reward page.
    rewards.shown, QuestInfoRewardText.shown = false, false
    Stale()
    callbacks.QuestInfo_Display()
    NextFrame()
    Check(not rewards.shown and rewards.alpha == 0 and QuestInfoRewardText.alpha == 0,
        "skin showed content Blizzard explicitly hid")
    rewards.shown, QuestInfoRewardText.shown = true, true
    rewards.IsProtected = function() return true, false end
    QuestInfoRewardText.IsProtected = rewards.IsProtected
    locked = true
    callbacks.QuestInfo_Display()
    NextFrame()
    Check(rewards.alpha == 0 and QuestInfoRewardText.alpha == 0, "protected recovery ran in combat")
    Check(deferred["quest-text:repaint"] ~= nil, "protected reward recovery was not deferred")
    locked = false
    deferred["quest-text:repaint"]()
    Recovered("complete settlement after combat")
    rewards.IsProtected, QuestInfoRewardText.IsProtected = nil, nil
    NextFrame()
    NS.QuestText.Deactivate(quest, "quest")
end
-- Unreadable native state must not be interpreted as permission to reveal.
NS.QuestText.Activate(quest, "quest")
Stale()
local alphaGetter = rewards.GetAlpha
rewards.GetAlpha = function() return 0.375 end
callbacks.QuestInfo_Display()
NextFrame()
Check(rewards.alpha == 0, "secret opacity was compared or replaced")
rewards.GetAlpha = alphaGetter
local visibleGetter = QuestFrameRewardPanel.IsVisible
QuestFrameRewardPanel.IsVisible = function() return 0.375 end
Stale()
callbacks.QuestInfo_Display()
NextFrame()
Check(rewards.alpha == 0 and QuestInfoRewardText.alpha == 0, "secret page visibility authorized recovery")
QuestFrameRewardPanel.IsVisible = visibleGetter
rewards.IsForbidden = function() return true end
rewards.GetParent = function() error("forbidden reward frame was inspected") end
callbacks.QuestInfo_Display()
NextFrame()
Check(rewards.alpha == 0, "forbidden reward frame changed")
rewards.IsForbidden = nil
rewards.GetParent = function(self) return self.parent end
NS.QuestText.Deactivate(quest, "quest")
-- Opacity alone is not a new native RGB color. Releasing after a fade must
-- restore native RGB with the CURRENT alpha, not either saved transient alpha.
QuestFrameRewardPanel:Hide()
QuestInfoRewardText.parent = quest
QuestInfoRewardText:SetTextColor(0.18, 0.17, 0.16, 0.7)
NS.QuestText.Activate(quest, "quest")
QuestInfoRewardText.color[4] = 0
callbacks.QuestInfo_Display()
QuestInfoRewardText.color[4] = 0.4
NS.QuestText.Deactivate(quest, "quest")
NextFrame()
Check(QuestInfoRewardText.color[1] == 0.18 and QuestInfoRewardText.color[3] == 0.16,
    "alpha-only native update replaced original RGB with Suite RGB")
Check(QuestInfoRewardText.color[4] == 0.4, "disable restored stale alpha")
Check(continued == 2 and #reported == 0, "unexpected action or isolated quest error")

-- The reported hand-in, in Blizzard's order (Mainline/QuestFrame.lua,
-- upstream/forever bebcb6bf and upstream/live 297d7aaa): QUEST_PROGRESS shows
-- the progress page, whose OnShow sets its text colors through the global
-- setters; Continue raises QUEST_COMPLETE, and QuestFrameRewardPanel_OnShow
-- runs QuestInfo_Display and only then scrolls, sets the portrait and starts
-- the fade. No skin write may land inside either build; one settlement on the
-- next frame paints the regions where Blizzard left them.
local writes, skinWrites, building = 0, 0, false
local function Counted(region, method)
    local native = region[method]
    region[method] = function(self, ...)
        writes = writes + 1
        return native(self, ...)
    end
end
local function Guard(callback)
    if not callback then return nil end
    return function(...)
        local before = writes
        callback(...)
        if building then skinWrites = skinWrites + writes - before end
    end
end
QuestProgressTitleText = Text(QuestFrameProgressPanel, 0.20, 0.12, 0.05)
QuestProgressText = Text(QuestFrameProgressPanel, 0.18, 0.12, 0.06)
local painted = { QuestInfoRewardText, QuestInfoTitleHeader, rewards.ItemChooseText, QuestProgressTitleText, QuestProgressText }
for _, region in ipairs(painted) do
    Counted(region, "SetTextColor")
    Counted(region, "SetFixedColor")
end
for _, region in ipairs({ QuestInfoRewardText, QuestInfoTitleHeader, rewards }) do Counted(region, "SetAlpha") end
if offerXP then
    for _, method in ipairs({ "Show", "Hide" }) do Counted(offerXP, method) end
    for _, method in ipairs({ "SetText", "SetTextColor" }) do Counted(offerXP.label or offerXP, method) end
end
for name, callback in pairs(callbacks) do
    if type(name) == "string" then callbacks[name] = Guard(callback) end
end
for _, panel in ipairs({ QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }) do
    for event, callback in pairs(panel.hooks) do panel.hooks[event] = Guard(callback) end
end
QuestFrameAcceptButton.scriptHooks.OnEnable = Guard(QuestFrameAcceptButton.scriptHooks.OnEnable)
local progressShow, rewardShow, tails = QuestFrameProgressPanel.onShow, QuestFrameRewardPanel.onShow, 0
QuestFrameProgressPanel.onShow = function(self)
    progressShow(self)
    QuestProgressTitleText.color = { 0.20, 0.12, 0.05, 1 }
    callbacks.QuestFrame_SetTitleTextColor(QuestProgressTitleText)
    QuestProgressText.color = { 0.18, 0.12, 0.06, 1 }
    callbacks.QuestFrame_SetTextColor(QuestProgressText)
end
QuestFrameRewardPanel.onShow = function(self)
    -- QuestInfo_Display's material colors precede its element pass.
    local color = QuestInfoRewardText.color
    color[1], color[2], color[3] = 0.24, 0.22, 0.16
    rewardShow(self)
    tails = tails + 1
end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client = { isForever = flavor == "Forever" }
    nativeFades = NS.Client.isForever
    QuestFrameDetailPanel:Hide()
    QuestFrameProgressPanel:Hide()
    QuestFrameRewardPanel:Hide()
    QuestRewardScrollChildFrame.alpha = 1
    Check(NS.QuestText.Activate(quest, "quest"), flavor .. ": quest root not activated")
    NextFrame()
    skinWrites, building = 0, true
    QuestFrameProgressPanel:Show()
    building = false
    Check(skinWrites == 0, flavor .. ": skin wrote inside the native progress page build")
    Check(#queuedJobs == 1, flavor .. ": progress build did not request exactly one settlement")
    NextFrame()
    Check(QuestProgressTitleText.color[1] == theme.title[1] and QuestProgressText.color[1] == theme.text[1],
        flavor .. ": progress text stayed parchment-dark after the build")
    Stale()
    local tailsBefore = tails
    skinWrites, building = 0, true
    QuestFrameCompleteButton.click()
    building = false
    Check(tails == tailsBefore + 1, flavor .. ": fixture did not finish the native reward page")
    Check(skinWrites == 0, flavor .. ": skin wrote inside QuestFrameRewardPanel_OnShow")
    Check(#queuedJobs == 1, flavor .. ": reward build did not request exactly one settlement")
    NextFrame()
    Recovered(flavor .. ": settled reward page")
    Check(QuestInfoRewardText.color[1] == theme.text[1] and QuestInfoRewardText.parent == QuestRewardScrollChildFrame,
        flavor .. ": settled reward text was not painted on its current page")
    Check(QuestInfoFrame.itemChoice == 0 and completed == 0, flavor .. ": skin chose or completed a reward")
    choices[2].click()
    QuestFrameCompleteQuestButton.click()
    Check(QuestInfoFrame.itemChoice == 2 and completed == 1, flavor .. ": native reward selection/completion failed")
    QuestInfoFrame.itemChoice, completed = 0, 0
    NS.QuestText.Deactivate(quest, "quest")
    NextFrame()
    Check(QuestProgressText.color[1] == 0.18 and QuestInfoRewardText.color[1] == 0.24,
        flavor .. ": disable did not restore the native colors")
end
-- The Forever 70959 capture for Report to Doren (331) already had text,
-- two choices and 2,936 XP on the right parents. Model the observed opacity
-- samples without assuming which script reduced it again after frame one.
Advance(2)
GetQuestID = function() return 331 end
GetRewardText = function() return "Completion narrative" end
GetCVar = function(name) if name == "instantQuestText" then return "0" end end
InCombatLockdown = function() return locked end
QuestInfoRewardText.GetText = GetRewardText
offerItems.choice = { { name = "Junglewalker Sandals" }, { name = "Frost Metal Pauldrons" } }
offerItems.reward, rewardXP, rewardMoney = {}, 2936, 0
QuestInfoFrame.rewardsFrame, QuestInfoFrame.chooseItems, QuestInfoFrame.questLog = rewards, true, false
local function OpenReward(forever)
    NS.Client = { isForever = forever }
    nativeFades = forever
    QuestFrameRewardPanel:Hide()
    NS.QuestText.Activate(quest, "quest")
    NextFrame()
    QuestFrameRewardPanel:Show()
    QuestRewardScrollChildFrame:SetAlpha(0)
    Stale()
    Advance(0.013)
    QuestRewardScrollChildFrame:SetAlpha(0.10)
    NextFrame()
    Check(QuestInfoRewardText.alpha == 1 and QuestInfoRewardText.color[4] == 1
        and rewards:GetEffectiveAlpha() == 0.10, "first-frame sample differs from the captured hand-in")
end
local function FinishNativeFade()
    Advance(0.50)
    QuestRewardScrollChildFrame:SetAlpha(1)
end
local function NoReveal(message)
    Check(QuestInfoRewardText.alpha == 0 and QuestInfoRewardText.color[4] == 0 and rewards.alpha == 0, message)
end
OpenReward(true)
choices[2].click()
Stale()
FinishNativeFade()
local repairWrites = writes
Advance(0.138) -- 651 ms: the native scroll child has finished its fade.
Advance(0.256) -- 907 ms: the user manually captured the still-open page.
Check(QuestInfoRewardText.alpha == 1 and QuestInfoRewardText.color[4] == 1 and rewards:GetEffectiveAlpha() == 1,
    "Doren's populated text and two choices stayed transparent after the native fade")
Check(writes - repairWrites == 3, "repair repainted more than the three invisible properties")
Check(choices[2]:IsVisible() and QuestInfoFrame.itemChoice == 2 and QuestInfoFrame.chooseItems and completed == 0,
    "late opacity repair changed the selected reward or submitted the quest")
QuestFrameCompleteQuestButton.click()
Check(completed == 1, "native Complete lost the player's selected item")
QuestInfoFrame.itemChoice, completed = 0, 0

OpenReward(true)
for _ = 1, 12 do callbacks.QuestInfo_ShowRewards() end
NextFrame()
Check(ActiveTimers() == 1, "reward updates multiplied the post-fade timer")
FinishNativeFade()
local before = writes
Advance(0.39)
Check(writes == before and ActiveTimers() == 0 and #queuedJobs == 0,
    "healthy post-fade check repainted content or continued polling")

local function FirstRepair()
    OpenReward(true)
    Stale()
    FinishNativeFade()
    Advance(0.188) -- first check at 0.70 s, after native 0.50 s fade
    Check(QuestInfoRewardText.alpha == 1 and QuestInfoRewardText.color[4] == 1 and rewards.alpha == 1,
        "first post-fade repair did not restore the three stale properties")
end
FirstRepair()
Advance(0.19)
Stale() -- possible second write before the manual sample at 907 ms
local secondRepairWrites = writes
Advance(0.016)
NoReveal("a second writer set the content to zero before the manual sample")
Advance(0.51) -- one confirmation near 1.40 s for a page that needed repair
Check(QuestInfoRewardText.alpha == 1 and QuestInfoRewardText.color[4] == 1 and rewards.alpha == 1,
    "a second zero write before 907 ms left text and choices invisible")
Check(writes - secondRepairWrites == 3 and ActiveTimers() == 0 and #queuedJobs == 0,
    "second repair repainted unrelated regions or scheduled a third check")
local finalRepairWrites = writes
Advance(3)
Check(writes == finalRepairWrites and ActiveTimers() == 0, "repaired page kept checking or writing")

for _, close in ipairs({ function() QuestFrameRewardPanel:Hide() end, function() NS.QuestText.Deactivate(quest, "quest") end }) do
    FirstRepair()
    Check(ActiveTimers() == 1, "first repair did not schedule exactly one confirmation")
    close()
    NextFrame()
    Check(ActiveTimers() == 0, "closing the reward panel or removing the skin kept the confirmation timer")
    Stale()
    Advance(0.8)
    NoReveal("cancelled confirmation changed hidden or unskinned content")
end

OpenReward(true)
local skinRGB = QuestInfoRewardText.color[1]
QuestInfoRewardText.alpha, QuestInfoRewardText.color[4], rewards.alpha = 0.5, 0.6, 0.7
FinishNativeFade()
Advance(0.39)
Check(QuestInfoRewardText.alpha == 0.5 and QuestInfoRewardText.color[4] == 0.6 and rewards.alpha == 0.7
    and QuestInfoRewardText.color[1] == skinRGB, "post-fade repair replaced partial native opacity or the skin color")

local function Excluded(change, restore, message)
    OpenReward(true)
    FinishNativeFade()
    change()
    NextFrame()
    Stale()
    Advance(0.39)
    NoReveal(message)
    restore()
end
local function Nothing() end
Excluded(function() QuestFrameRewardPanel:Hide() end, Nothing, "post-fade timer revealed a closed reward page")
Excluded(function() QuestFrameDetailPanel:Show() end, function() QuestFrameDetailPanel:Hide() end,
    "post-fade timer revealed detail-page reading text")
Excluded(function() QuestInfoRewardText.parent, rewards.parent = other, other end, Nothing,
    "post-fade timer revealed shared regions under a map/popup owner")
Excluded(function() NS.QuestText.Deactivate(quest, "quest") end, Nothing, "disabled skin repaired text after the fade")
Excluded(function() QuestInfoRewardText.shown, rewards.shown = false, false end,
    function() QuestInfoRewardText.shown, rewards.shown = true, true end, "post-fade timer revealed hidden regions")
local publicVisibility = QuestFrameRewardPanel.IsVisible
Excluded(function() QuestFrameRewardPanel.IsVisible = function() return 0.375 end end,
    function() QuestFrameRewardPanel.IsVisible = publicVisibility end, "restricted visibility authorized post-fade paint")
OpenReward(true)
FinishNativeFade()
local ownAlpha, fontColor = rewards.GetAlpha, QuestInfoRewardText.GetTextColor
rewards.GetAlpha = function() return 0.375 end
QuestInfoRewardText.GetTextColor = function() return 1, 1, 1, 0.375 end
rewards.alpha, QuestInfoRewardText.color[4] = 0, 0
Advance(0.39)
Check(rewards.alpha == 0 and QuestInfoRewardText.color[4] == 0, "post-fade repair inferred restricted opacity")
rewards.GetAlpha, QuestInfoRewardText.GetTextColor = ownAlpha, fontColor
local function Protected(explicit)
    rewards.IsProtected = function() return true, explicit end
    QuestInfoRewardText.IsProtected = rewards.IsProtected
end
local function Unprotect()
    rewards.IsProtected, QuestInfoRewardText.IsProtected = nil, nil
end
Excluded(function() Protected(true) end, Unprotect, "post-fade timer painted explicitly protected regions out of combat")
local function DeferTurnIn()
    OpenReward(true)
    FinishNativeFade()
    deferred = {}
    Stale()
    Protected(false)
    locked = true
    Advance(0.39)
    NoReveal("post-fade timer wrote to protected regions during combat")
    local key, job = next(deferred)
    Check(type(job) == "function" and next(deferred, key) == nil, "combat did not queue one post-fade check")
    return job
end
local function ResumeTurnIn(job)
    locked = false
    job()
    Unprotect()
end
local afterCombat = DeferTurnIn()
ResumeTurnIn(afterCombat)
Check(QuestInfoRewardText.alpha == 1 and QuestInfoRewardText.color[4] == 1 and rewards.alpha == 1,
    "combat exit did not repair the still-current hand-in")
afterCombat = DeferTurnIn()
QuestFrameRewardPanel:Hide()
ResumeTurnIn(afterCombat)
NoReveal("deferred combat job revealed a closed page")
afterCombat = DeferTurnIn()
QuestFrameRewardPanel:Hide()
QuestFrameRewardPanel:Show()
Stale()
ResumeTurnIn(afterCombat)
NoReveal("deferred combat job crossed a close and reopen of the same quest")
afterCombat = DeferTurnIn()
QuestInfoTitleHeader.parent = other
ResumeTurnIn(afterCombat)
NoReveal("deferred combat job painted a superseded reward template")

OpenReward(true)
FinishNativeFade()
OpenReward(true) -- same ID again, but a different opening of the reward page
Stale()
Advance(0.25) -- the first opening's timer would now be due
NoReveal("a previous opening's timer wrote to the new reward page")
Advance(0.25)
QuestRewardScrollChildFrame:SetAlpha(1)
Advance(0.25)
Check(QuestInfoRewardText.alpha == 1 and rewards.alpha == 1, "new opening lost its own post-fade settlement")
OpenReward(false)
Stale()
FinishNativeFade()
Advance(1)
NoReveal("Forever's post-fade repair ran on Retail")
Check(ActiveTimers() == 0 and #queuedJobs == 0, "idle quest dialog kept scheduling work")
Check(#reported == 0, "isolated quest error during the hand-in: " .. tostring(reported[1]))
print("suite quest reward transition contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_quest_reward_transition_contract"))()
