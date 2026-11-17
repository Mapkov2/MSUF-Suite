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
local offerXP, rewardXP, rewardMoney = nil, 0, 0
function QuestDetailScrollChildFrame:CreateFontString()
    local region = NativeFrame(self)
    function region:SetPoint(_, owner) self.anchor = owner end
    function region:SetWidth() end
    function region:SetJustifyH() end
    function region:SetText(text) self.text = text end
    function region:SetTextColor() end
    offerXP = region
    return region
end
function GetRewardXP() return rewardXP end
function GetRewardMoney() return rewardMoney end
function GetMoneyString(value) return tostring(value) .. " coins" end
function BreakUpLargeNumbers(value) return tostring(value) end
EXPERIENCE_COLON = "Experience:"
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
        callbacks.QuestInfo_ShowRewards()
        NextFrame()
        Check(offerXP and offerXP:IsVisible() and offerXP.anchor == QuestInfoSpacerFrame
            and offerXP.text == "Experience: 3950", "XP-only offer did not show the reward returned by the client")
        rewards.shown = true
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
        Check(offerXP:IsShown() and offerXP.text == "1250 coins", "offer without XP lost its money reward")
        rewardMoney = 0
    end
    QuestFrameProgressPanel:Show()
    -- The fallback line hides with its parent page at once and is settled after the build.
    if nativeFades then Check(not offerXP:IsVisible(), "offer summary stayed visible on progress") end
    NextFrame()
    if nativeFades then Check(not offerXP:IsShown(), "offer summary survived the move to progress") end
    Check(rewards.alpha == 1, "fixture lost native detail OnHide restoration")
    QuestFrameCompleteButton.click()
    NextFrame()
    Recovered("ordinary progress to reward")
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
    for _, method in ipairs({ "Show", "Hide", "SetText", "SetTextColor" }) do Counted(offerXP, method) end
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
Check(#reported == 0, "isolated quest error during the hand-in")
print("suite quest reward transition contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_quest_reward_transition_contract"))()
