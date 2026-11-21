local _, NS = ...

-- Blizzard_UIPanels_Game/Mainline/QuestInfo.lua (upstream/forever bebcb6bf)
-- sets parchment-dark text in QuestInfo_Display. Our quest and map adapters
-- fade that parchment, so recolor only text currently parented to a skinned
-- quest window. The Blizzard display function remains responsible for content.
-- Blizzard_UIPanels_Game is not load-on-demand (12.1.0, 12.1.5, Forever), so
-- the quest, QuestInfo and gossip frames exist before this skin loads.
local QuestText = {
    roots = setmetatable({}, { __mode = "k" }),
    colors = setmetatable({}, { __mode = "k" }),
    hooks = {},
}
NS.QuestText = QuestText

local Safety = NS.Safety

local MAX_PARENT_DEPTH = 20
local MAX_OBJECTIVES = 40
local MAX_OFFER_ITEMS = 40
local REPAINT_KEY = "quest-text:repaint"
-- Forever fades the reward scroll child over 0.5 s. On quest 331 the shared
-- contents were opaque on the next frame and transparent again at 0.651 s.
local TURN_IN_CHECK_DELAY = 0.70
local TURN_IN_CHECK_KEY = "quest-text:turn-in-opacity"

-- Text colours are paint: Blizzard displays quest text in combat too (the
-- world map, the quest popup), so the paint runs in combat as well. Only a
-- region of a protected frame waits for one repaint after combat.
local PaintCurrent, RequestPaint

local function CanPaint(region)
    if not NS.IsCombatLocked() or Safety.CanDecorate(region, false) then return true end
    NS.CombatGate.RunOrDefer(REPAINT_KEY, PaintCurrent)
    return false
end

local function IsDetailReady()
    if not QuestText.roots[QuestFrame] then return false end
    if Safety.Read(QuestFrameDetailPanel, "IsVisible") ~= true then return false end
    if not NS.Client.isForever then return true end
    local fading = Safety.Field(QuestFrameDetailPanel, "fading")
    return Safety.Public(fading) and not fading
end

-- The offer owns the reading fade until Accept is enabled. Completion waits
-- for native reparenting. In either case only repair a shown, attached region.
local function IsCurrentReward(region)
    if not QuestText.roots[QuestFrame] or Safety.Read(region, "IsShown") ~= true then return false end
    local parent = Safety.Read(region, "GetParent")
    if parent and parent == QuestRewardScrollChildFrame then
        return Safety.Read(QuestFrameRewardPanel, "IsVisible") == true
    end
    if parent and parent == QuestDetailScrollChildFrame and NS.Client.isForever and IsDetailReady() then
        return UIFrameIsFading(region) == false
    end
    return false
end

local offerReward, offerLabel, offerAnchor, offerID, waitingForRewards, requestedQuest, fadeCheck, checkedOffer
local requestedItems = {}
local offerDisplays, offerReadiness

local function Positive(value)
    return Safety.Public(value) and type(value) == "number" and value > 0 and value
end

local function ClearOffer()
    offerID, waitingForRewards, requestedQuest = nil, nil, nil
    offerDisplays, checkedOffer, offerReadiness = nil, nil, nil
    for id in pairs(requestedItems) do requestedItems[id] = nil end
    if fadeCheck then
        fadeCheck:Cancel()
        fadeCheck = nil
    end
end

local function WatchOffer(id)
    if offerID ~= id then
        ClearOffer()
        offerID = id
    end
    local cached = id and HaveQuestRewardData(id)
    waitingForRewards = id ~= nil and Safety.Public(cached) and not cached
    if waitingForRewards and not requestedQuest then
        requestedQuest = true
        QuestEventListener:AddCallback(id, RequestPaint)
        C_TaskQuest.RequestPreloadRewardData(id)
    end
end

local function OfferAmount(active, byID)
    local value = active()
    if not Safety.Public(value) then return end
    if Positive(value) then return value end
    if active == GetRewardXP and GameRulesUtil.IsPlayerAtEffectiveMaxLevel() then return end
    if offerID then return Positive(byID(offerID)) end
end

local function AnchorTarget(region)
    local _, target = Safety.Call(region, "GetPoint", 1)
    if Safety.Public(target) then return target end
end

-- A standalone QUEST_ITEM_UPDATE rebuilds rows but does not run Display's
-- layout loop. A recycled frame can still be parented to the NPC scroll child.
local function LaidOutRewards(spacer)
    local rewards = QuestInfoRewardsFrame
    if Safety.Read(rewards, "IsShown") ~= true or Safety.Read(rewards, "GetParent") ~= QuestDetailScrollChildFrame then return end
    if Safety.Read(rewards, "GetEffectiveAlpha") == 0 and not UIFrameIsFading(rewards) then return end
    local prior = AnchorTarget(rewards)
    if not prior or Safety.Read(prior, "GetParent") ~= QuestDetailScrollChildFrame then return end
    if prior ~= QuestInfoObjectivesText and prior ~= QuestInfoSpecialObjectivesFrame and prior ~= QuestInfoGroupSize then return end
    local last = AnchorTarget(spacer)
    if last and (last == rewards or Safety.Read(last, "GetParent") == rewards) then return rewards end
    -- A late frame anchored to the same preceding paragraph is also in place.
    if prior == last then return rewards end
end

local function NativeItemNames(rewards)
    local rows = rewards and rewards.RewardButtons
    if not Safety.Public(rows) or type(rows) ~= "table" then return end
    local names = { choice = {}, reward = {} }
    for i = 1, math.min(#rows, MAX_OFFER_ITEMS * 2) do
        local row = rows[i]
        if Safety.Read(row, "IsShown") == true then
            local rowKind, objectType, id = row.type, row.objectType, row.questID
            if Safety.Public(id) and id == offerID and Safety.Public(rowKind) and names[rowKind]
                and Safety.Public(objectType) and objectType == "item" then
                local index = Safety.Read(row, "GetID")
                if Positive(index) then names[rowKind][index] = Safety.Read(row.Name, "GetText") end
            end
        end
    end
    return names
end

local function ReadOfferItem(kind, index, fromLog, count, logCount)
    local readLog = kind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
    if fromLog then return readLog(index, offerID) end
    local name, texture, quantity, quality, usable, itemID = GetQuestItemInfo(kind, index)
    if offerID and Safety.Public(name) and (name == nil or name == "") and Safety.Public(itemID) then
        local lootType = 0
        if kind == "choice" then lootType = GetQuestItemInfoLootType(kind, index) end
        local available = Positive(logCount(offerID))
        if available and index <= available and Safety.Public(lootType) and lootType == 0 then
            local logName, _, logQty, _, _, logID = readLog(index, offerID)
            if Safety.Public(logID) and Positive(logID) and (itemID == logID
                or (itemID == nil or itemID == 0) and available == count) then
                name, itemID = logName, logID
                if Safety.Public(quantity) and quantity == nil then quantity = logQty end
            end
        end
    end
    return name, texture, quantity, quality, usable, itemID
end

local function AppendOfferItems(lines, nativeNames, kind, activeCount, logCount)
    local count = activeCount()
    if not Safety.Public(count) then return end
    local fromLog = not Positive(count) and offerID ~= nil
    if fromLog then count = logCount(offerID) end
    if not Positive(count) then return end
    local heading = kind == "choice" and count > 1 and REWARD_CHOICES or (#lines > 0 and REWARD_ITEMS or REWARD_ITEMS_ONLY)
    local needsHeading = true
    for index = 1, math.min(count, MAX_OFFER_ITEMS) do
        local name, _, quantity, _, _, itemID = ReadOfferItem(kind, index, fromLog, count, logCount)
        if Safety.Public(name) and (name == nil or name == "") and Positive(itemID) then
            name = C_Item.GetItemNameByID(itemID)
        end
        local readable = Safety.Public(name) and type(name) == "string" and name ~= ""
        if readable and not (nativeNames and nativeNames[kind][index] == name) then
            if needsHeading then
                lines[#lines + 1] = heading
                needsHeading = false
            end
            if Safety.Public(quantity) and type(quantity) == "number" and quantity > 1 then
                name = ("%d x %s"):format(quantity, name)
            end
            lines[#lines + 1] = name
        end
        local cached = Positive(itemID) and C_Item.IsItemDataCachedByID(itemID)
        if Safety.Public(cached) and cached == false and Positive(itemID) and not requestedItems[itemID] then
            requestedItems[itemID] = true
            ItemEventListener:AddCallback(itemID, RequestPaint)
        end
    end
end

-- Only active NPC item data can populate Blizzard's hoverable reward buttons.
-- Explicit quest-log lookups are still useful for the text preview below.
local function ActiveItemGap(names, kind, count)
    local missing = false
    for index = 1, count do
        local lootType = 0
        if kind == "choice" then lootType = GetQuestItemInfoLootType(kind, index) end
        if not Safety.Public(lootType) then return end
        if lootType == 0 then
            local name, icon, amount, quality, usable, id, context = GetQuestItemInfo(kind, index)
            if not Safety.Public(name) or not Safety.Public(icon) or not Safety.Public(amount)
                or not Safety.Public(quality) or not Safety.Public(usable) or not Safety.Public(id)
                or not Safety.Public(context) then return end
            if id ~= nil and not Positive(id) then return end
            -- Blizzard waits on an uncached item by ID, or skips an empty
            -- slot. Its other rows and the objectives can already be laid out.
            if id and type(name) == "string" and name ~= "" and (not names or names[kind][index] ~= name) then
                missing = true
            end
        end
    end
    return missing
end

local function MayCoverOffer(frame)
    return frame ~= nil and Safety.Read(frame, "IsVisible") ~= false
end

local function IsNpcOffer(info)
    local accept, rewards = info.acceptButton, info.rewardsFrame
    local log, map = info.questLog, info.mapView
    return Safety.Public(accept) and accept == QuestFrameAcceptButton
        and Safety.Public(rewards) and rewards == QuestInfoRewardsFrame
        and Safety.Public(log) and not log and Safety.Public(map) and not map
end

-- Active objectives, money and experience can arrive separately, even if
-- quest-scoped data is already cached. Only a readiness change needs paint.
local function OfferReadiness()
    local objective = GetObjectiveText()
    local ready = Safety.Public(objective) and type(objective) == "string" and objective ~= "" and 4 or 0
    local allowed = C_QuestLog.ShouldShowQuestRewards(offerID)
    if not Safety.Public(allowed) or allowed ~= true then return ready end
    return ready + (Positive(GetRewardXP()) and 1 or 0) + (Positive(GetRewardMoney()) and 2 or 0)
end

local function CheckOfferAfterFade()
    fadeCheck, checkedOffer = nil, true
    RequestPaint()
end

local function RestoreOfferLayout(names, checkItems, xpMissing, moneyMissing, settled)
    if not offerID or Positive(GetQuestID()) ~= offerID then return end
    if Safety.Read(QuestInfoTitleHeader, "GetParent") ~= QuestDetailScrollChildFrame then return end
    if MayCoverOffer(WorldMapFrame) or MayCoverOffer(QuestLogPopupDetailFrame) then return end
    if not IsNpcOffer(QuestInfoFrame) then return end
    local choices, fixed = GetNumQuestChoices(), GetNumQuestRewards()
    if not Safety.Public(choices) or type(choices) ~= "number" or choices < 0 or choices > MAX_OFFER_ITEMS
        or not Safety.Public(fixed) or type(fixed) ~= "number" or fixed < 0 or fixed > MAX_OFFER_ITEMS then return end
    if NS.Client.isForever and (UIFrameIsFading(QuestInfoRewardsFrame) or UIFrameIsFading(QuestInfoObjectivesText)) then return end
    local show = C_QuestLog.ShouldShowQuestRewards(offerID)
    if not Safety.Public(show) then return end
    local showRewards = show == true
    local gaps = 0
    if showRewards and xpMissing and Positive(GetRewardXP()) then gaps = gaps + 1 end
    if showRewards and moneyMissing and Positive(GetRewardMoney()) then gaps = gaps + 2 end
    local objective = GetObjectiveText()
    if Safety.Public(objective) and type(objective) == "string" and objective ~= ""
        and (Safety.Read(QuestInfoObjectivesText, "GetParent") ~= QuestDetailScrollChildFrame
            or Safety.Read(QuestInfoObjectivesText, "GetText") ~= objective) then gaps = gaps + 4 end
    if showRewards and (checkItems or gaps > 0) then
        local missingChoice = ActiveItemGap(names, "choice", choices)
        local missingFixed = ActiveItemGap(names, "reward", fixed)
        if missingChoice == nil or missingFixed == nil then return end
        if missingChoice or missingFixed then gaps = gaps + 8 end
    end
    if gaps == 0 then
        if settled and showRewards then offerDisplays = nil end
        return
    end
    local signature = (choices * (MAX_OFFER_ITEMS + 1) + fixed) * 16 + gaps
    if offerDisplays and offerDisplays[signature] then return end
    if not settled then RequestPaint() return end
    if not offerDisplays then offerDisplays = {} end
    offerDisplays[signature] = true
    -- DetailPanel_OnShow uses this exact builder. It lays out real item buttons
    -- without accepting the quest or restarting the panel's reading animation.
    local material = QuestFrame_GetMaterial()
    Safety.Dispatch(QuestInfo_Display, QUEST_TEMPLATE_DETAIL, QuestDetailScrollChildFrame,
        QuestFrameAcceptButton, material)
    return true
end

-- The spacer may still point below an invisible reward block. Use the last
-- visible native paragraph as the anchor for any data only the quest log has.
local function VisibleOfferPart(region)
    if region and Safety.Read(region, "GetParent") == QuestDetailScrollChildFrame
        and Safety.Read(region, "IsVisible") == true then return region end
end

local function OfferRewardText(settled)
    local spacer = QuestInfoSpacerFrame
    if not IsDetailReady() then return end
    if Safety.Read(QuestInfoRewardsFrame, "IsShown") == nil then return end
    WatchOffer(Positive(GetQuestID()) or nil)
    local ownSpacer = Safety.Read(spacer, "GetParent") == QuestDetailScrollChildFrame
    if not ownSpacer and Safety.Read(QuestInfoTitleHeader, "GetParent") ~= QuestDetailScrollChildFrame then return end
    local rewards = ownSpacer and LaidOutRewards(spacer)
    if NS.Client.isForever and not checkedOffer and not fadeCheck then
        fadeCheck = C_Timer.NewTimer(TURN_IN_CHECK_DELAY, CheckOfferAfterFade)
    end
    local xp = not (rewards and Safety.Read(rewards.XPFrame, "IsShown") == true) and OfferAmount(GetRewardXP, GetQuestLogRewardXP)
    local money = not (rewards and Safety.Read(rewards.MoneyFrame, "IsShown") == true) and OfferAmount(GetRewardMoney, GetQuestLogRewardMoney)
    local experience = xp and (EXPERIENCE_COLON .. " " .. BreakUpLargeNumbers(xp))
    local coins = money and GetMoneyString(money, false, false)
    local lines = {}
    local nativeNames = NativeItemNames(rewards)
    AppendOfferItems(lines, nativeNames, "choice", GetNumQuestChoices, GetNumQuestLogChoices)
    AppendOfferItems(lines, nativeNames, "reward", GetNumQuestRewards, GetNumQuestLogRewards)
    offerReadiness = offerID and OfferReadiness() or nil
    if RestoreOfferLayout(nativeNames, #lines > 0, xp, money, settled) then return OfferRewardText(false) end
    if #lines == 0 and not rewards and (coins or experience) then lines[1] = REWARD_ITEMS_ONLY end
    if coins then lines[#lines + 1] = coins end
    if experience then lines[#lines + 1] = experience end
    if #lines == 0 then return end
    if rewards then return table.concat(lines, "\n"), rewards end
    local anchor = VisibleOfferPart(QuestInfoGroupSize) or VisibleOfferPart(QuestInfoSpecialObjectivesFrame)
        or VisibleOfferPart(QuestInfoObjectivesText) or VisibleOfferPart(QuestInfoDescriptionText)
    if anchor then
        table.insert(lines, 1, QUEST_REWARDS)
        return table.concat(lines, "\n"), anchor
    end
end

local function CanPaintOfferReward()
    return Safety.CanCreateRegions(QuestDetailScrollChildFrame, not NS.IsCombatLocked())
end

local function PaintOfferReward(settled)
    if NS.IsCombatLocked() then
        if offerReward and CanPaintOfferReward() then offerReward:Hide() end
        if offerReward or IsDetailReady() then NS.CombatGate.RunOrDefer(REPAINT_KEY, PaintCurrent) end
        return
    end
    local text, anchor = OfferRewardText(settled)
    if not text or NS.Client.isForever and UIFrameIsFading(anchor) then
        if offerReward and CanPaintOfferReward() then offerReward:Hide() end
        return
    end
    if not CanPaintOfferReward() then return end
    -- Supplement missing entries underneath the current native offer content.
    -- Give the wrapped text its own sized scroll child element, as Blizzard
    -- does for its native reward block. It never handles clicks.
    if not offerReward then
        offerReward = Safety.CreateChildFrame("Frame", QuestDetailScrollChildFrame)
        offerReward:SetWidth(275)
        offerLabel = offerReward:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        offerLabel:SetPoint("TOPLEFT")
        offerLabel:SetWidth(275)
        offerLabel:SetJustifyH("LEFT")
    end
    if offerAnchor ~= anchor then
        offerReward:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == QuestInfoRewardsFrame and -4 or -15)
        offerAnchor = anchor
    end
    offerLabel:SetText(text)
    offerLabel:SetTextColor(NS.Theme.GetColor("text"))
    offerReward:SetHeight(math.max(1, offerLabel:GetStringHeight()) + 5)
    offerReward:Show()
end

local function RevealReward(region)
    if not IsCurrentReward(region) or not CanPaint(region) then return end
    local alpha = Safety.Read(region, "GetAlpha")
    if type(alpha) == "number" and alpha < 1 then Safety.Invoke(region, "SetAlpha", 1) end
end

local function RestoreTurnInOpacity(region)
    if Safety.Read(region, "IsShown") ~= true or Safety.Read(region, "GetParent") ~= QuestRewardScrollChildFrame then return end
    if not Safety.CanDecorate(region, true) then return end
    local changed = false
    if Safety.Read(region, "GetAlpha") == 0 then changed = Safety.Invoke(region, "SetAlpha", 1) end
    if region == QuestInfoRewardText then
        local r, g, b, alpha = Safety.ReadColor(region, "GetTextColor")
        if alpha == 0 then return Safety.Invoke(region, "SetTextColor", r, g, b, 1) or changed end
    end
    return changed
end

local turnInTimer, turnInDue, verifyRepair
local AfterTurnInFade

local function CheckTurnInOpacity()
    if not turnInDue then return end
    turnInDue = false
    if not QuestText.roots[QuestFrame] or Safety.Read(QuestFrameRewardPanel, "IsVisible") ~= true then return end
    if Safety.Read(QuestInfoTitleHeader, "GetParent") ~= QuestRewardScrollChildFrame then return end
    local storyChanged = RestoreTurnInOpacity(QuestInfoRewardText)
    local rewardsChanged = RestoreTurnInOpacity(QuestInfoRewardsFrame)
    -- A late write hid this page once. Verify the repair once more in case
    -- the same transition writes again. Healthy pages finish on the first check.
    if not verifyRepair and (storyChanged or rewardsChanged) then
        verifyRepair = true
        turnInTimer = C_Timer.NewTimer(TURN_IN_CHECK_DELAY, AfterTurnInFade)
    end
end

AfterTurnInFade = function()
    turnInTimer, turnInDue = nil, true
    NS.CombatGate.RunOrDefer(TURN_IN_CHECK_KEY, CheckTurnInOpacity)
end

local function QueueTurnInCheck()
    if turnInTimer or turnInDue or not QuestText.roots[QuestFrame] then return end
    if Safety.Read(QuestFrameRewardPanel, "IsVisible") ~= true then return end
    verifyRepair = false
    turnInTimer = C_Timer.NewTimer(TURN_IN_CHECK_DELAY, AfterTurnInFade)
end

local function CancelTurnInCheck()
    if turnInTimer then
        turnInTimer:Cancel()
        turnInTimer = nil
    end
    turnInDue = false
end

local fields = {
    QuestInfoTitleHeader = "title",
    QuestInfoDescriptionHeader = "title",
    QuestInfoObjectivesHeader = "title",
    QuestInfoDescriptionText = "text",
    QuestInfoObjectivesText = "text",
    QuestInfoQuestType = "text",
    QuestInfoRewardText = "text",
    QuestInfoGroupSize = "text",
    QuestInfoTimerText = "text",
    QuestInfoSpellObjectiveLearnLabel = "text",
    QuestInfoRequiredMoneyText = "text",
    QuestProgressTitleText = "title",
    QuestProgressText = "text",
    QuestProgressRequiredItemsText = "title",
    QuestProgressRequiredMoneyText = "text",
    GreetingText = "text",
    CurrentQuestsText = "title",
    AvailableQuestsText = "title",
}

local rewardFields = {
    Header = "title",
    ItemChooseText = "text",
    ItemReceiveText = "text",
    PlayerTitleText = "text",
    QuestSessionBonusReward = "text",
}

-- The skinned root this region currently sits under, if any.
local function ActiveRoot(region)
    local current = region
    for _ = 1, MAX_PARENT_DEPTH do
        if not current then return nil end
        if QuestText.roots[current] then return current end
        current = Safety.Read(current, "GetParent")
    end
    return nil
end

-- Puts Blizzard's color back while ours is still showing, then forgets it.
local function Release(region, record)
    if not CanPaint(region) then return end
    local r, g, b, a = Safety.ReadColor(region, "GetTextColor")
    local owned = Safety.ColorMatches(record.applied, r, g, b, 1, Safety.COLOR_OWN)
    if record.fixed then
        -- Blizzard uses a fixed font color only with light quest text.
        local native = QuestTextContrast.UseLightText() == true
        Safety.Invoke(region, "SetFixedColor", native)
    end
    if owned then
        local original = record.original
        Safety.Invoke(region, "SetTextColor", original[1], original[2], original[3], a)
    end
    QuestText.colors[region] = nil
end

local function Paint(region, role, fixed)
    if type(region) ~= "table" or type(region.SetTextColor) ~= "function" then return end
    if not ActiveRoot(region) then
        -- QuestInfo FontStrings are shared between the map, NPC dialog and
        -- popup. Blizzard can move one without repainting when its material
        -- cache still matches, so restore our color on an unskinned parent.
        local record = QuestText.colors[region]
        if record then Release(region, record) end
        return
    end
    if not CanPaint(region) then return end
    local currentR, currentG, currentB, currentA = Safety.ReadColor(region, "GetTextColor")
    if not currentR then return end
    local record = QuestText.colors[region]
    if not record then
        record = { original = { currentR, currentG, currentB }, applied = {} }
        QuestText.colors[region] = record
    elseif not Safety.ColorMatches(record.applied, currentR, currentG, currentB, 1, Safety.COLOR_OWN) then
        -- A material change replaces RGB; a reading fade only changes opacity
        -- and must never replace the saved native RGB with our theme color.
        local original = record.original
        original[1], original[2], original[3] = currentR, currentG, currentB
    end
    local r, g, b = NS.Theme.GetColor(role)
    -- Blizzard applies the fixed-color mode before setting the text color.
    -- Keep that order for quest buttons and registered gossip FontStrings.
    if fixed and Safety.Invoke(region, "SetFixedColor", true) then record.fixed = true end
    if (region == QuestInfoRewardText or (region == QuestInfoObjectivesHeader or region == QuestInfoObjectivesText)
        and IsDetailReady() and NS.Client.isForever)
        and IsCurrentReward(region) then currentA = 1 end
    if Safety.Invoke(region, "SetTextColor", r, g, b, currentA) then
        local applied = record.applied
        applied[1], applied[2], applied[3], applied[4] = r, g, b, 1
    end
end

local function PaintRewards(rewards)
    for key, role in pairs(rewardFields) do Paint(rewards[key], role) end
    Paint(rewards.XPFrame.ReceiveText, "text")
    -- ShowRewards also runs independently for late item data; its font-string
    -- pool reapplies the parchment color whenever a spell heading is acquired.
    local pool = Safety.Field(rewards, "spellHeaderPool")
    if Safety.HasMethod(pool, "EnumerateActive") then
        local count = 0
        for heading in pool:EnumerateActive() do
            Paint(heading, "text")
            count = count + 1
            if count >= MAX_OBJECTIVES then break end
        end
    end
end

local function PaintGreetingButtons(pool)
    for button in pool:EnumerateActive() do
        Paint(Safety.Call(button, "GetFontString"), "text", true)
    end
end

-- GossipFrame owns ScrollBox FontStrings rather than the shared QuestInfo
-- globals. Blizzard registers each row and repaints all registered text in
-- UpdateTheme, including after a questTextContrast change.
local function PaintGossip()
    if not QuestText.roots[GossipFrame] then return end
    for region in pairs(GossipFrame.fontStrings) do Paint(region, "text", true) end
end

local function OnGossipFontString(region)
    Paint(region, "text", true)
end

-- Every hook runs inside Blizzard's own call (QuestInfo_Display, the NPC
-- greeting setup, GossipFrame's row setup), so each hook body is its own
-- error boundary and Blizzard's display goes on. The quest page hooks only
-- request a later paint (RequestPaint); GossipFrame's row hooks still paint.
local Isolated = Safety.Isolated

local function EnsureGossipHooks(root)
    if root ~= GossipFrame or QuestText.hooks[root] then return end
    if type(root.RegisterFontString) ~= "function" or type(root.UpdateTheme) ~= "function" then return end
    hooksecurefunc(root, "RegisterFontString", function(_, region)
        Safety.Dispatch(OnGossipFontString, region)
    end)
    hooksecurefunc(root, "UpdateTheme", Isolated(PaintGossip))
    QuestText.hooks[root] = true
end

PaintCurrent = function(settled)
    if not next(QuestText.roots) and not next(QuestText.colors) then return end
    Paint(Safety.Field(Safety.Field(QuestFrame, "TitleContainer"), "TitleText"), "title")
    for name, role in pairs(fields) do Paint(_G[name], role) end
    PaintRewards(QuestInfoRewardsFrame)
    local list = QuestInfoObjectivesFrame.Objectives
    for index = 1, math.min(#list, MAX_OBJECTIVES) do Paint(list[index], "text") end
    Paint(QuestInfoSealFrame.Text, "text")
    PaintGreetingButtons(QuestFrameGreetingPanel.titleButtonPool)
    PaintGossip()
    RevealReward(QuestInfoRewardText)
    RevealReward(QuestInfoRewardsFrame)
    if IsDetailReady() and NS.Client.isForever then
        RevealReward(QuestInfoObjectivesHeader)
        RevealReward(QuestInfoObjectivesText)
    end
    PaintOfferReward(settled == true)
end

-- Every native hook below fires partway through a page build: QuestInfo_Display
-- returns into QuestFrameRewardPanel_OnShow before its scroll reset, portrait
-- and fade (Mainline/QuestFrame.lua, upstream/forever bebcb6bf and upstream/live
-- 297d7aaa), and the panel OnShow, the setters and Forever's detail OnHide all
-- run inside QuestFrame_OnEvent before ShowUIPanel. The hooks only remember
-- the request; one paint follows on the next frame, after the whole build,
-- against the regions' current (possibly reparented) owners. Registry.QueueJob
-- waits for the end of combat, and quest text is shown and painted in combat.
local pendingRegions = setmetatable({}, { __mode = "k" })
local settleQueued = false

-- Each paint is its own error boundary (Safety.Dispatch).
local function Settle()
    settleQueued = false
    Safety.Dispatch(PaintCurrent, true)
    for region, role in pairs(pendingRegions) do
        pendingRegions[region] = nil
        Safety.Dispatch(Paint, region, role)
    end
end

RequestPaint = function()
    if settleQueued or not next(QuestText.roots) and not next(QuestText.colors) then return end
    settleQueued = true
    C_Timer.After(0, Settle)
end

local function PaintPage()
    PaintCurrent()
    -- Shared widgets can be reparented/repainted again later in the native
    -- page callback. Recheck their current owner once after that callback.
    if next(QuestText.roots) then RequestPaint() end
end

local function RestoreRoot(root)
    -- Clearing entries during pairs() is allowed; nothing is added meanwhile.
    for region, record in pairs(QuestText.colors) do
        if ActiveRoot(region) == root then Release(region, record) end
    end
end

-- NPC greeting and progress text use these native setters outside
-- QuestInfo_Display, inside the panel's OnShow.
local function RequestRegion(region, role)
    if not Safety.Public(region) or type(region) ~= "table" then return end
    if not next(QuestText.roots) and not next(QuestText.colors) then return end
    pendingRegions[region] = role
    RequestPaint()
end

local function OnGreetingText(region)
    RequestRegion(region, "text")
end

local function OnGreetingTitle(region)
    RequestRegion(region, "title")
end

-- These Blizzard functions are called through their globals. QUEST_LOG_UPDATE
-- also refreshes the greeting list through QuestFrameGreetingPanel_OnShow.
local PaintCurrentHook = Isolated(RequestPaint)
local function RewardPageShown()
    RequestPaint()
    if NS.Client.isForever then QueueTurnInCheck() end
end
local RewardPageShownHook = Isolated(RewardPageShown)
local globalHooks = {
    { "QuestInfo_Display", PaintCurrentHook },
    { "QuestInfo_ShowRewards", PaintCurrentHook },
    { "QuestFrameProgressItems_Update", PaintCurrentHook },
    { "QuestFrame_SetTextColor", Isolated(OnGreetingText) },
    { "QuestFrame_SetTitleTextColor", Isolated(OnGreetingTitle) },
    { "QuestFrameGreetingPanel_OnShow", PaintCurrentHook },
}

-- QuestFrame.xml binds the panel's OnShow as function="...", so the script
-- holds the function value from load time and never reaches the global
-- hook above. Opening the greeting is observed on the panel itself.
local questPanels = {
    "QuestFrameGreetingPanel", "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel",
}
local offerHooks = false
local function OfferHidden()
    ClearOffer()
    RequestPaint()
end

local function OfferEvent(_, event)
    if event ~= "QUEST_LOG_UPDATE" or not offerID then return end
    if waitingForRewards then
        local cached = HaveQuestRewardData(offerID)
        if Safety.Public(cached) and cached == true then RequestPaint() end
    end
    if offerReadiness and offerReadiness < 7 and IsDetailReady() and Positive(GetQuestID()) == offerID
        and OfferReadiness() ~= offerReadiness then RequestPaint() end
end

local function EnsurePanelShowHooks()
    for index = 1, #questPanels do
        local panel = Safety.Field(_G, questPanels[index])
        if Safety.HasMethod(panel, "HookScript") and not QuestText.hooks[panel] then
            if panel == QuestFrameRewardPanel then
                panel:HookScript("OnShow", RewardPageShownHook)
            else
                panel:HookScript("OnShow", PaintCurrentHook)
            end
            QuestText.hooks[panel] = true
        end
    end
    if not offerHooks and Safety.HasMethod(QuestFrameDetailPanel, "HookScript") then
        if Safety.HasMethod(QuestFrame, "HookScript") then QuestFrame:HookScript("OnEvent", OfferEvent) end
        if Safety.HasMethod(QuestFrameRewardPanel, "HookScript") then
            QuestFrameRewardPanel:HookScript("OnHide", Isolated(CancelTurnInCheck))
        end
        -- Enable() follows the last reading-fade update, after the Disable()
        -- in QuestFrameDetailPanel_OnShow, so the button's OnEnable fires.
        -- Observed as a script hook: no member of the native button changes.
        -- The native update continues to own the description fade and
        -- Accept's enabled state.
        if Safety.HasMethod(QuestFrameAcceptButton, "HookScript") then
            QuestFrameAcceptButton:HookScript("OnEnable", PaintCurrentHook)
        end
        -- The detail page hides inside the next page's OnShow; the fallback
        -- line goes with its hidden parent and is settled after that build.
        if Safety.HasMethod(QuestFrameDetailPanel, "HookScript") then
            QuestFrameDetailPanel:HookScript("OnHide", Isolated(OfferHidden))
        end
        offerHooks = true
    end
end

local function EnsureHooks()
    for index = 1, #globalHooks do
        local name, callback = globalHooks[index][1], globalHooks[index][2]
        if not QuestText.hooks[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, callback)
            QuestText.hooks[name] = true
        end
    end
    EnsurePanelShowHooks()
end

function QuestText.Activate(root, owner)
    if not root or NS.IsCombatLocked() then return false end
    local owners = QuestText.roots[root]
    if not owners then
        owners = {}
        QuestText.roots[root] = owners
        if root == QuestFrame then
            NS.QuestRewardSelection.Enable()
            if NS.Client.isForever then QueueTurnInCheck() end
        end
    end
    owners[owner] = true
    if root == QuestFrame then NS.QuestWindow.Activate(root, owner) end
    EnsureHooks()
    EnsureGossipHooks(root)
    PaintPage()
    return true
end

function QuestText.Deactivate(root, owner)
    local owners = root and QuestText.roots[root]
    if not owners then return end
    owners[owner] = nil
    if root == QuestFrame then NS.QuestWindow.Deactivate(root, owner) end
    if next(owners) then return end
    if root == QuestFrame then
        NS.QuestRewardSelection.Disable()
        CancelTurnInCheck()
        ClearOffer()
    end
    -- Restore while the root is still recognized for parent-chain matching.
    RestoreRoot(root)
    QuestText.roots[root] = nil
    if root == QuestFrame and offerReward then PaintOfferReward() end
end

function QuestText.Refresh()
    PaintCurrent()
end

NS.Registry.AddListener(QuestText, function(_, domain)
    if (domain == "color" or domain == "theme") and (next(QuestText.roots) or next(QuestText.colors)) then
        NS.Registry.QueueJob(PaintCurrent)
    end
end)

return QuestText
