-- The native page and click sequence follows Blizzard_UIPanels_Game/Mainline/
-- QuestFrame.lua and QuestInfo.lua on Forever 3d8abb1d and Retail ab5cb850.
local root = assert(arg[1], "Suite root required")
local checks, queued, granted, errors, displays = 0, {}, {}, 0, 0
local activeQuest, choiceIDs, locked = 301, {}, false
local clickToComplete, itemAmount = false, 1
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Frame(parent)
    local widget = { parent = parent, shown = true, hooks = {} }
    function widget:GetParent() return self.parent end
    function widget:GetID() return self.id end
    function widget:IsShown() return self.shown end
    function widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function widget:GetAlpha() return 1 end
    function widget:GetEffectiveAlpha() return 1 end
    function widget:GetPoint() return "TOPLEFT", self.anchor, "BOTTOMLEFT", 0, -10 end
    function widget:SetPoint(_, anchor) self.anchor = anchor end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:IsEnabled() return self.enabled == true end
    function widget:HookScript(event, callback) self.hooks[event] = callback end
    function widget:Fire(event, ...)
        if self.hooks[event] then self.hooks[event](self, ...) end
    end
    return widget
end
function hooksecurefunc(name, post)
    local original = assert(_G[name], name)
    _G[name] = function(...)
        local result = original(...)
        post(...)
        return result
    end
end
C_Timer = { After = function(delay, cb) assert(delay == 0) queued[#queued + 1] = cb end }
local function Settle()
    for step = 1, 4 do
        local current = queued
        queued = {}
        for _, callback in ipairs(current) do callback() end
        if #queued == 0 then return end
    end
    error("unbounded quest selection refresh")
end
function InCombatLockdown() return locked end
function securecallfunction(callback, ...) return callback(...) end
function GetQuestID() return activeQuest end
function GetNumQuestChoices() return #choiceIDs end
function GetNumQuestRewards() return 0 end
function GetRewardXP() return 0 end
function GetRewardMoney() return 0 end
function GetQuestItemInfo(kind, index)
    local item = choiceIDs[index]
    if kind == "choice" and item and item > 0 then return "Reward " .. item, 1, itemAmount, 2, true, item end
end
local unknownCurrency, currencyAmount = false, 4
function GetQuestItemInfoLootType(kind, index)
    assert(kind == "choice")
    return choiceIDs[index] and choiceIDs[index] < 0 and 1 or 0
end
C_QuestOffer = { GetQuestRewardCurrencyInfo = function(kind, index)
    assert(GetQuestItemInfoLootType(kind, index) == 1, "read currency fields for a non-currency")
    if not unknownCurrency then return { currencyID = -choiceIDs[index], totalRewardAmount = currencyAmount } end
end }
-- With default contrast Blizzard can return a second value indicating how
-- to render parchment. It must never reach QuestInfo_Display's mapView slot.
function QuestFrame_GetMaterial() return "Parchment", true end
function IsModifiedClick() return false end
QuestFrame = Frame()
QuestFrameRewardPanel = Frame(QuestFrame)
QuestRewardScrollChildFrame = Frame(QuestFrameRewardPanel)
QuestFrameCompleteQuestButton = Frame(QuestFrameRewardPanel)
QuestInfoTitleHeader = Frame(QuestRewardScrollChildFrame)
QuestInfoSpacerFrame = Frame(QuestRewardScrollChildFrame)
QuestInfoRewardsFrame = Frame(QuestRewardScrollChildFrame)
QuestInfoRewardsFrame.Header = Frame(QuestInfoRewardsFrame)
QuestInfoRewardsFrame.ItemChooseText = Frame(QuestInfoRewardsFrame)
QuestInfoRewardsFrame.RewardButtons = {}
QuestInfoItemHighlight = Frame(QuestInfoRewardsFrame)
QuestInfoRewardsFrame.ItemHighlight = QuestInfoItemHighlight
QuestInfoFrame = { rewardsFrame = QuestInfoRewardsFrame, itemChoice = 0 }
WorldMapFrame, QuestLogPopupDetailFrame = Frame(), Frame()
WorldMapFrame:Hide()
QuestLogPopupDetailFrame:Hide()
QUEST_TEMPLATE_REWARD = { chooseItems = true }
function QuestInfoItem_OnClick(row)
    if row.type == "choice" then
        QuestInfoItemHighlight:SetPoint("TOPLEFT", row)
        QuestInfoItemHighlight:Show()
        QuestInfoFrame.itemChoice = row:GetID()
    end
end
-- ShowRewards renders new data under the existing owner and resets selection.
-- Only Display runs the subsequent shared-element parenting and anchoring loop.
local function NativeRewards()
    local block = QuestInfoRewardsFrame
    block.activeRewardElements = {}
    block.shown = #choiceIDs > 0
    if #choiceIDs == 0 then return end
    if #choiceIDs == 1 then QuestInfoFrame.chooseItems = nil end
    for i = 1, math.max(#choiceIDs, #block.RewardButtons) do
        local row = block.RewardButtons[i] or Frame(block)
        block.RewardButtons[i] = row
        row.id, row.questID, row.type, row.objectType = i, activeQuest, "choice", "item"
        if choiceIDs[i] and choiceIDs[i] < 0 then
            row.objectType, row.currencyInfo = "currency", { currencyID = -choiceIDs[i] }
        else
            row.currencyInfo = nil
        end
        row.Name = row.Name or Frame(row)
        row.Name.text = choiceIDs[i] and ("Reward " .. choiceIDs[i])
        function row.Name:GetText() return self.text end
        row.shown = choiceIDs[i] ~= nil
        if row.shown then block.activeRewardElements[#block.activeRewardElements + 1] = row end
    end
    QuestInfoFrame.itemChoice = 0
    QuestInfoItemHighlight:Hide()
    return block, block.activeRewardElements[#choiceIDs]
end
QuestInfo_ShowRewards = NativeRewards
function QuestInfo_Display(template, parent, button, material, mapView)
    assert(template == QUEST_TEMPLATE_REWARD and parent == QuestRewardScrollChildFrame)
    assert(button == QuestFrameCompleteQuestButton and material == "Parchment" and mapView == nil)
    displays = displays + 1
    QuestInfoFrame.chooseItems, QuestInfoFrame.acceptButton = template.chooseItems, button
    QuestInfoFrame.questLog, QuestInfoFrame.mapView, QuestInfoFrame.rewardsFrame = nil, nil, QuestInfoRewardsFrame
    QuestInfoTitleHeader.parent, QuestInfoSpacerFrame.parent = parent, parent
    local block, last = NativeRewards()
    if block then block.parent = parent end
    QuestInfoSpacerFrame.anchor = last or QuestInfoTitleHeader
end
local function NativeOpen(questID, choices)
    QuestFrameRewardPanel:Hide()
    QuestFrameRewardPanel:Fire("OnHide")
    activeQuest, choiceIDs = questID, choices
    QuestFrameCompleteQuestButton.enabled = true
    QuestFrameRewardPanel:Show()
    local material = QuestFrame_GetMaterial()
    QuestInfo_Display(QUEST_TEMPLATE_REWARD, QuestRewardScrollChildFrame, QuestFrameCompleteQuestButton, material)
    QuestFrameRewardPanel:Fire("OnShow")
    QuestFrame:Fire("OnEvent", "QUEST_COMPLETE")
    Settle()
end
local function ItemUpdate(choices, beforeSettle)
    choiceIDs = choices
    QuestInfo_ShowRewards()
    QuestFrame:Fire("OnEvent", "QUEST_ITEM_UPDATE")
    if beforeSettle then beforeSettle() end
    Settle()
end
local function ClickChoice(index)
    local row = QuestInfoRewardsFrame.RewardButtons[index]
    Check(row and row:IsVisible(), "native choice row is unavailable")
    if QuestInfoFrame.chooseItems then QuestInfoItem_OnClick(row) end
end
function GetQuestReward(index)
    assert(clickToComplete, "skin claimed the quest without the user's click")
    granted[#granted + 1] = index
end
local function ClickComplete()
    Check(QuestFrameCompleteQuestButton:IsEnabled(), "native Complete was disabled")
    clickToComplete = true
    if #choiceIDs == 1 then QuestInfoFrame.itemChoice = 1 end
    if #choiceIDs > 0 and QuestInfoFrame.itemChoice == 0 then
        errors = errors + 1
    else
        GetQuestReward(QuestInfoFrame.itemChoice)
    end
    clickToComplete = false
end
local deferred
local NS = { Client = {}, IsCombatLocked = InCombatLockdown, CombatGate = { RunOrDefer = function(_, cb)
    if locked then deferred = cb else cb() end
end } }
NS.Safety = assert(loadfile(root .. "/MSUF_Suite/Appearance/Safety.lua"))("Skin", NS)
if arg[2] ~= "baseline" then
    local path = os.getenv("SUITE_QUEST_SELECTION_OVERRIDE") or root .. "/MSUF_Suite_Skin/Adapters/QuestRewardSelection.lua"
    assert(loadfile(path))("Skin", NS)
end
for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    if NS.QuestRewardSelection then NS.QuestRewardSelection.Enable() end
    local grants, priorErrors = #granted, errors
    NativeOpen(301, { 101 })
    ItemUpdate({ 101, 102, 103 })
    Check(QuestInfoFrame.chooseItems and QuestInfoFrame.itemChoice == 0 and #granted == grants,
        "native 1-to-3 update left reward choices disabled or chose a reward automatically")
    ClickChoice(2)
    Check(QuestInfoFrame.itemChoice == 2 and QuestInfoItemHighlight:IsShown(), "real second choice was ignored")
    ItemUpdate({ 101, 102, 103 })
    Check(QuestInfoFrame.itemChoice == 2 and QuestInfoItemHighlight.anchor == QuestInfoRewardsFrame.RewardButtons[2]
        and QuestInfoItemHighlight:IsShown() and #granted == grants, "reward refresh lost the explicitly chosen item")
    QuestInfo_ShowRewards() -- also called outside QUEST_ITEM_UPDATE, including spell learning
    Settle()
    Check(QuestInfoFrame.itemChoice == 2 and QuestInfoItemHighlight:IsShown() and #granted == grants,
        "standalone native reward refresh erased an existing selection")
    ClickComplete()
    Check(#granted == grants + 1 and granted[#granted] == 2 and errors == priorErrors, "native Complete did not grant the selected second reward")
    NativeOpen(302, { 101, 102 })
    ItemUpdate({ 101, 102 })
    Check(QuestInfoFrame.itemChoice == 0 and #granted == grants + 1, "choice from an earlier quest was restored")
    ClickChoice(2)
    ItemUpdate({ 101, 204 })
    Check(QuestInfoFrame.itemChoice == 0, "a recycled slot selected a different item")
    ClickChoice(2)
    ItemUpdate({ 101, 204, 205 }, function() ClickChoice(3) end)
    Check(QuestInfoFrame.itemChoice == 3, "queued repair overwrote a newer user choice")
    NativeOpen(302, { 101, 204, 205 })
    ItemUpdate({ 101, 204, 205 })
    Check(QuestInfoFrame.itemChoice == 0, "prior opening of the same quest restored its old selection")
    QuestInfoFrame.itemChoice = 1
    ItemUpdate({ 101, 204 })
    Check(QuestInfoFrame.itemChoice == 0, "a choice without a witnessed click was restored")
    NativeOpen(303, { 101, 102 })
    ClickChoice(2)
    ItemUpdate({ 102, 101 })
    Check(QuestInfoFrame.itemChoice == 1, "reordered reward lost its stable item identity")
    ItemUpdate({ 102, 102 })
    Check(QuestInfoFrame.itemChoice == 0, "two identical items resulted in an arbitrary selection")
    NativeOpen(304, { 101, -101 })
    ClickChoice(2)
    ItemUpdate({ -101, 101 })
    Check(QuestInfoFrame.itemChoice == 1, "currency restore confused identical item and currency IDs")
    ItemUpdate({ 101, 202 })
    Check(QuestInfoFrame.itemChoice == 0, "a missing currency was replaced by an item")
    NativeOpen(304, { -101, -102 })
    unknownCurrency = true
    ClickChoice(2)
    unknownCurrency = nil
    ItemUpdate({ -101, -102 })
    Check(QuestInfoFrame.itemChoice == 0, "an unidentified currency was preselected")
    currencyAmount = nil
    NativeOpen(304, { -101, -102 })
    ClickChoice(2)
    ItemUpdate({ -101, -102 })
    Check(QuestInfoFrame.itemChoice == 0, "unknown currency amounts were treated as matching")
    currencyAmount = 4
    NativeOpen(0, { 101 })
    activeQuest = 307
    ItemUpdate({ 101, 102 })
    Check(QuestInfoFrame.chooseItems and QuestInfoFrame.itemChoice == 0, "delayed native quest ID kept multiple choices disabled")
    ClickChoice(2)
    itemAmount = 4
    ItemUpdate({ 101, 102 })
    Check(QuestInfoFrame.itemChoice == 0, "the same item with a different quantity was reselected")
    itemAmount = 1
    NativeOpen(305, { 101, 102 })
    local foreign = Frame()
    foreign:Hide()
    QuestInfoRewardsFrame.parent = foreign
    ItemUpdate({ 101, 102 })
    Check(QuestInfoRewardsFrame.parent == QuestRewardScrollChildFrame and QuestInfoRewardsFrame:IsVisible()
        and QuestInfoFrame.itemChoice == 0, "late native rows remained under a hidden former owner")
    NativeOpen(306, { 101 })
    local renders = displays
    locked = true
    ItemUpdate({ 101, 102 })
    Check(displays == renders and not QuestInfoFrame.chooseItems, "rebuilt the native reward dialog in combat")
    locked = false
    assert(deferred)()
    deferred = nil
    Check(QuestInfoFrame.chooseItems and QuestInfoFrame.itemChoice == 0, "current reward page failed to settle after combat")
    NativeOpen(303, { 101 })
    WorldMapFrame:Show()
    local before = displays
    ItemUpdate({ 101, 102 })
    Check(displays == before, "repair rewrote shared UI during map ownership")
    WorldMapFrame:Hide()
    if NS.QuestRewardSelection then NS.QuestRewardSelection.Disable() end
end
print("suite quest reward selection contract: " .. checks .. " checks passed")
