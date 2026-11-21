local _, NS = ...
local Safety = NS.Safety
local Selection = {}
NS.QuestRewardSelection = Selection

local MAX_CHOICES = 40
local COMBAT_KEY = "quest-text:reward-selection"
local active, hooked, queued, rebuilding = false, false, false, false
local open, pageID, attemptedCount, pickedKind, pickedID, pickedAmount

local function Field(object, key)
    if not Safety.Public(object) or type(object) ~= "table" or Safety.IsForbidden(object) then return end
    local value = object[key]
    if Safety.Public(value) then return value end
end

local function Number(value)
    if Safety.Public(value) and type(value) == "number" and value >= 0 then return value end
end

local function Positive(value)
    value = Number(value)
    if value and value > 0 then return value end
end

local function CurrentPage()
    if not active or not open then return false end
    if Safety.Read(QuestFrameRewardPanel, "IsVisible") ~= true then return false end
    if Safety.Read(WorldMapFrame, "IsVisible") == true or Safety.Read(QuestLogPopupDetailFrame, "IsVisible") == true then return false end
    local log, map = QuestInfoFrame.questLog, QuestInfoFrame.mapView
    local owned = Safety.Public(log) and not log and Safety.Public(map) and not map
        and Field(QuestInfoFrame, "rewardsFrame") == QuestInfoRewardsFrame
        and Field(QuestInfoFrame, "acceptButton") == QuestFrameCompleteQuestButton
        and Safety.Read(QuestInfoTitleHeader, "GetParent") == QuestRewardScrollChildFrame
    if not owned then return false end
    local currentID = Positive(GetQuestID())
    if not currentID then return false end
    if not pageID then pageID = currentID end
    return currentID == pageID
end

local function Anchor(region)
    local _, target = Safety.Call(region, "GetPoint", 1)
    if Safety.Public(target) then return target end
end

local function LaidOut()
    if Safety.Read(QuestInfoRewardsFrame, "IsShown") ~= true
        or Safety.Read(QuestInfoRewardsFrame, "GetParent") ~= QuestRewardScrollChildFrame then return false end
    local last = Anchor(QuestInfoSpacerFrame)
    if not last or Safety.Read(QuestInfoSpacerFrame, "GetParent") ~= QuestRewardScrollChildFrame then return false end
    return last == QuestInfoRewardsFrame or Safety.Read(last, "GetParent") == QuestInfoRewardsFrame
        or (Safety.Read(last, "GetParent") == QuestRewardScrollChildFrame and Anchor(QuestInfoRewardsFrame) == last)
end

local function ChoiceIndex(row, count)
    if Field(row, "type") ~= "choice" or Field(row, "questID") ~= pageID
        or Safety.Read(row, "GetParent") ~= QuestInfoRewardsFrame or Safety.Read(row, "IsShown") ~= true then return end
    local index = Positive(Safety.Read(row, "GetID"))
    if index and index <= count then return index end
end

local function ItemIdentity(row, index)
    local kind = Field(row, "objectType")
    local lootType = GetQuestItemInfoLootType("choice", index)
    if not Safety.Public(lootType) then return end
    if kind == "item" and lootType == 0 then
        local name, _, amount, _, _, id = GetQuestItemInfo("choice", index)
        if Safety.Public(name) and type(name) == "string" and name ~= "" and name == Safety.Read(Field(row, "Name"), "GetText") then
            if Safety.Public(amount) then return kind, Positive(id), Number(amount) end
        end
    elseif kind == "currency" and lootType == 1 then
        local offered = C_QuestOffer.GetQuestRewardCurrencyInfo("choice", index)
        local id = Positive(Field(offered, "currencyID"))
        if id and id == Field(Field(row, "currencyInfo"), "currencyID") then
            local amount = offered.totalRewardAmount
            if Safety.Public(amount) and amount == nil then amount = offered.baseRewardAmount end
            if Safety.Public(amount) then return kind, id, Number(amount) end
        end
    end
end

-- The first native buttons are the choice slots. Blizzard appends fixed items
-- and currencies afterwards. Never transfer a selection across unknown rows.
local function MatchingChoice(kind, id, amount, count)
    local buttons = Field(QuestInfoRewardsFrame, "RewardButtons")
    if not buttons or count < 2 or count > MAX_CHOICES then return end
    local match
    for index = 1, count do
        local row = Field(buttons, index)
        if ChoiceIndex(row, count) ~= index then return end
        local rowKind, rowID, rowAmount = ItemIdentity(row, index)
        if not rowID or not rowAmount then return end
        if rowKind == kind and rowID == id then
            if match or rowAmount ~= amount then return end
            match = row
        end
    end
    return match
end

local function Remember(row)
    if rebuilding or not CurrentPage() or Field(row, "type") ~= "choice" then return end
    pickedKind, pickedID, pickedAmount = nil, nil, nil
    local count = Number(GetNumQuestChoices())
    if not count or count < 2 or count > MAX_CHOICES then return end
    local index = ChoiceIndex(row, count)
    if not index or index ~= Field(QuestInfoFrame, "itemChoice") or Field(QuestInfoFrame, "chooseItems") ~= true then return end
    local kind, id, amount = ItemIdentity(row, index)
    if id and amount and MatchingChoice(kind, id, amount, count) == row then pickedKind, pickedID, pickedAmount = kind, id, amount end
end

local function ChoiceModeDisabled(value)
    return Safety.Public(value) and not value
end

local function NeedsDisplay(count)
    if not LaidOut() then return true end
    if count > 1 and ChoiceModeDisabled(QuestInfoFrame.chooseItems) then return true end
    local buttons = Field(QuestInfoRewardsFrame, "RewardButtons")
    for index = 1, count do
        if ChoiceIndex(Field(buttons, index), count) ~= index then return true end
    end
    return false
end

local function Repair()
    if not CurrentPage() or NS.IsCombatLocked() then return end
    local count = Number(GetNumQuestChoices())
    if not count or count > MAX_CHOICES then return end
    if count < 2 then pickedKind, pickedID, pickedAmount = nil, nil, nil end
    if count == 0 and not Positive(GetNumQuestRewards()) and not Positive(GetRewardXP()) and not Positive(GetRewardMoney()) then return end
    if NeedsDisplay(count) then
        if attemptedCount == count then return end
        attemptedCount = count
        -- RewardPanel_OnShow uses this same native builder. It repairs both
        -- template selection mode and the shared block's layout. It does not
        -- submit a reward, run a button OnClick, or restart the reading fade.
        local material = QuestFrame_GetMaterial()
        Safety.Dispatch(QuestInfo_Display, QUEST_TEMPLATE_REWARD, QuestRewardScrollChildFrame,
            QuestFrameCompleteQuestButton, material)
    else
        attemptedCount = nil
    end
    if not pickedID or not CurrentPage() or Field(QuestInfoFrame, "chooseItems") ~= true
        or Field(QuestInfoFrame, "itemChoice") ~= 0 then return end
    local match = MatchingChoice(pickedKind, pickedID, pickedAmount, count)
    if not match then
        pickedKind, pickedID, pickedAmount = nil, nil, nil
        return
    end
    -- Restore only the exact reward picked by the player on this page.
    -- Blizzard's selection-only helper moves its highlight and records the
    -- row index. The native Complete button still owns the hand-in.
    Safety.Dispatch(QuestInfoItem_OnClick, match)
end

local function Settle()
    if rebuilding then return end
    rebuilding = true
    Safety.Dispatch(Repair)
    rebuilding = false
end

local function AfterNative()
    queued = false
    if active and open then NS.CombatGate.RunOrDefer(COMBAT_KEY, Settle) end
end

local function Queue()
    if active and open and not queued and not rebuilding then
        queued = true
        C_Timer.After(0, AfterNative)
    end
end

local function Hidden()
    open, pageID, attemptedCount = false, nil, nil
    pickedKind, pickedID, pickedAmount = nil, nil, nil
end

local function Shown()
    Hidden()
    if active then
        open, pageID = true, Positive(GetQuestID())
        Queue()
    end
end

function Selection.Enable()
    if active then return end
    if not hooked then
        hooksecurefunc("QuestInfoItem_OnClick", Safety.Isolated(Remember))
        QuestFrameRewardPanel:HookScript("OnShow", Safety.Isolated(Shown))
        QuestFrameRewardPanel:HookScript("OnHide", Hidden)
        -- Item updates and learned-spell updates both rebuild this block outside Display.
        hooksecurefunc("QuestInfo_ShowRewards", Queue)
        hooked = true
    end
    active = true
    if Safety.Read(QuestFrameRewardPanel, "IsVisible") == true then Shown() end
end

function Selection.Disable()
    active = false
    Hidden()
end
