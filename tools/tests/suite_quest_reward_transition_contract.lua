local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_quest_text_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/QuestText.lua"))', 1, true))
-- Numeric stand-in lets an unsafe comparison produce an observable write.
issecretvalue = function(value) return value == 0.375 end
local body = [======[
local checks = 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function NativeFrame(parent)
    local frame = { parent = parent, shown = true, alpha = 1, hooks = {} }
    function frame:GetParent() return self.parent end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:HookScript(event, callback) self.hooks[event] = callback end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.onHide then self.onHide(self) end
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
    return text
end
quest = NativeFrame()
QuestFrame = quest
QuestFrameDetailPanel = NativeFrame(quest)
QuestFrameProgressPanel = NativeFrame(quest)
QuestFrameRewardPanel = NativeFrame(quest)
QuestDetailScrollChildFrame = NativeFrame(QuestFrameDetailPanel)
QuestRewardScrollChildFrame = NativeFrame(QuestFrameRewardPanel)
WithOpacity(QuestInfoRewardText, QuestDetailScrollChildFrame)
WithOpacity(QuestInfoTitleHeader, QuestDetailScrollChildFrame)
local rewards = NativeFrame(QuestDetailScrollChildFrame)
rewards.XPFrame = {}
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
    if callbacks.QuestInfo_Display then callbacks.QuestInfo_Display() end
end
QuestInfo_Display = NativeDisplay
QuestInfo_ShowRewards = function() rewards.shown = true end
QuestFrameDetailPanel.onShow = function()
    QuestFrameRewardPanel:Hide()
    QuestFrameProgressPanel:Hide()
    NativeDisplay(QuestDetailScrollChildFrame)
    if nativeFades then
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
    QuestFrameDetailPanel:Show()
    NextFrame()
    local expected = nativeFades and 0 or 1
    Check(QuestInfoRewardText.alpha == expected and rewards.alpha == expected, "native detail opacity overridden")
    QuestFrameProgressPanel:Show()
    Check(rewards.alpha == 1, "fixture lost native detail OnHide restoration")
    QuestFrameCompleteButton.click()
    NextFrame()
    Recovered("ordinary progress to reward")
    -- Recovery inputs represent the reported blank shared content. They do not
    -- claim the ordinary native sequence above creates this stale state itself.
    Stale()
    callbacks.QuestInfo_Display()
    Recovered("already-stale shared widgets")
    for _ = 1, 12 do callbacks.QuestInfo_Display() end
    Check(#queuedJobs == 1, "page burst queued multiple settlements")
    Stale()
    NextFrame()
    Recovered("write after synchronous page hook")
    Check(#queuedJobs == 0, "settlement became a polling loop")
    Stale()
    callbacks.QuestInfo_ShowRewards()
    Recovered("late reward item data")
    NextFrame()
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
print("suite quest reward transition contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_quest_reward_transition_contract"))()
