local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_quest_text_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/QuestText.lua"))', 1, true))
local body = [======[
QuestFrame = quest
QuestInfo_ShowRewards = function() end
QuestFrameProgressItems_Update = function() end
local checks = 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function ForbiddenWrite() error("skin changed native quest interaction or visibility") end
local pages = { "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }
for _, name in ipairs(pages) do
    local panel = Frame(quest)
    panel.scriptHooks = {}
    function panel:HookScript(event, callback) self.scriptHooks[event] = callback end
    panel.Show, panel.Hide, panel.SetAlpha, panel.SetParent = ForbiddenWrite, ForbiddenWrite, ForbiddenWrite, ForbiddenWrite
    _G[name] = panel
end
local progress = Frame(QuestFrameProgressPanel)
QuestProgressText = Text(progress, 0.1, 0.1, 0.1, 0.8)
QuestProgressTitleText = Text(progress, 0.2, 0.1, 0.0)
QuestProgressRequiredItemsText = Text(progress, 0.2, 0.1, 0.0)
QuestProgressRequiredMoneyText = Text(progress, 0.0, 0.0, 0.0)
GreetingText, CurrentQuestsText, AvailableQuestsText = Text(quest, 0.1, 0.1, 0.1), Text(quest, 0.2, 0.1, 0), Text(quest, 0.2, 0.1, 0)
local rewardParent = Frame(QuestFrameRewardPanel)
QuestInfoRewardText.parent = rewardParent
local heading = Text(rewardParent, 0.1, 0.1, 0.1)
QuestInfoRewardsFrame.ItemChooseText = Text(rewardParent, 0.1, 0.1, 0.1)
QuestInfoRewardsFrame.spellHeaderPool = { EnumerateActive = function()
    local values = { [heading] = true }
    return next, values
end }
local choice, completed, continued = 0, 0, 0
local choose = function(id) choice = id end
local continue = function() continued = continued + 1 end
local complete = function() if choice > 0 then completed = completed + 1 end end
local buttons = { { script = continue }, { script = complete }, { script = choose } }
for _, button in ipairs(buttons) do
    button.Enable, button.Disable, button.SetScript, button.Click = ForbiddenWrite, ForbiddenWrite, ForbiddenWrite, ForbiddenWrite
end
QuestFrameCompleteButton, QuestFrameCompleteQuestButton = buttons[1], buttons[2]
QuestInfoRewardsFrame.RewardButtons = { buttons[3] }
local override = os.getenv("SUITE_QUEST_TEXT_OVERRIDE")
assert(loadfile(override or root .. "/MSUF_Suite_Skin/Adapters/QuestText.lua"))("MSUF_Suite_Skin", NS)
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client = { isForever = flavor == "Forever" }
    Check(NS.QuestText.Activate(quest, "quest"), "quest root not activated")
    Check(QuestProgressText.color[1] == theme.text[1] and QuestProgressRequiredMoneyText.color[1] == theme.text[1],
        "skin enabled during a progress page left its instructions unreadable")
    Check(QuestProgressText.color[4] == 0.8, "paint changed native quest text alpha")
    Check(CurrentQuestsText.color[1] == theme.title[1] and GreetingText.color[1] == theme.text[1],
        "re-enable left an already populated greeting dark")
    Check(heading.color[1] == theme.text[1], "pooled spell-reward instructions stayed parchment-dark")
    for _, name in ipairs(pages) do
        local shown = _G[name].scriptHooks.OnShow
        Check(shown ~= nil, "native XML-bound page OnShow is not observed: " .. name)
        -- XML holds the original function. Its native layout and reparenting
        -- finish before HookScript; the skin sees the final content owner.
        QuestInfoRewardText:SetTextColor(0.1, 0.1, 0.1)
        shown(_G[name])
        Check(QuestInfoRewardText.color[1] == theme.text[1], "page transition left reward text dark")
    end
    Check(callbacks.QuestInfo_ShowRewards and callbacks.QuestFrameProgressItems_Update,
        "late native quest updates bypass the text skin")
    heading:SetTextColor(0.12, 0.1, 0.08)
    callbacks.QuestInfo_ShowRewards()
    Check(heading.color[1] == theme.text[1], "late QUEST_ITEM_UPDATE left a recycled reward heading dark")
    QuestProgressRequiredMoneyText:SetTextColor(0, 0, 0)
    callbacks.QuestFrameProgressItems_Update()
    Check(QuestProgressRequiredMoneyText.color[1] == theme.text[1], "native progress update darkened the money requirement")
    Check(choice == 0 and completed == 0 and continued == 0, "skin performed a quest action")
    buttons[1].script()
    buttons[3].script(2)
    buttons[2].script()
    Check(continued == 1 and choice == 2 and completed == 1, "native continue, selection or completion callback changed")
    choice, completed, continued = 0, 0, 0
    NS.QuestText.Deactivate(quest, "quest")
    Check(heading.color[1] == 0.12 and QuestProgressRequiredMoneyText.color[1] == 0,
        "disable did not restore the latest native colors")
    callbacks.QuestInfo_ShowRewards()
    Check(heading.color[1] == 0.12, "inactive quest hook still repainted content")
end
Check(#reported == 0, "quest skin emitted an error")
print("suite quest lifecycle contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_quest_lifecycle_contract"))()
