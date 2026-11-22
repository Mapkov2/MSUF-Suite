local _, NS = ...
local Cards = {}
NS.QuestRewardCards = Cards

local Safety, Kit = NS.Safety, NS.AdapterKit
local cards = Kit.WeakSet()
local enabled, hooked, generation = false, false, 0

-- The large native item template puts both the icon and its parchment name
-- plate on BACKGROUND. Our fill sits behind the icon. No frame covers the
-- button, so native hover, modified clicks and reward selection stay intact.
local function NewCard(row)
    local fill = row:CreateTexture(nil, "BACKGROUND", nil, -4)
    fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 1)
    local line = row:CreateTexture(nil, "ARTWORK", nil, 3)
    line:SetPoint("BOTTOMLEFT", fill)
    line:SetPoint("BOTTOMRIGHT", fill)
    line:SetHeight(2)
    line:Hide()
    local card = { fill = fill, line = line }
    cards[row] = card
    return card
end

local function Release(card)
    if not card.active then return end
    card.active = false
    card.fill:Hide()
    card.line:Hide()
    NS.IconSkin.DisableOwner(card)
    NS.Cosmetics.RestoreOwner(card)
end

local function NativePage()
    if not enabled or Safety.Read(QuestFrame, "IsVisible") ~= true then return end
    local rewards = QuestInfoRewardsFrame
    if Safety.Read(rewards, "IsVisible") ~= true then return end
    local parent = Safety.Read(rewards, "GetParent")
    if parent == QuestDetailScrollChildFrame and Safety.Read(QuestFrameDetailPanel, "IsVisible") == true then
        return rewards, false
    end
    if parent == QuestRewardScrollChildFrame and Safety.Read(QuestFrameRewardPanel, "IsVisible") == true then
        return rewards, true
    end
end

local function MarkSelection(row, card, turnIn)
    local kind, choice = row.type, Safety.Field(QuestInfoFrame, "itemChoice")
    local selected = turnIn and Safety.Public(kind) and kind == "choice"
        and Safety.Public(choice) and type(choice) == "number" and choice > 0 and choice == Safety.Read(row, "GetID")
    card.line:SetShown(selected == true)
end

local function PaintRow(row, turnIn)
    local namePlate, icon, border = row.NameFrame, row.Icon, row.IconBorder
    if not Kit.ParentIs(namePlate, row) or not Kit.ParentIs(icon, row) then return end
    local card = cards[row] or NewCard(row)
    card.active, card.generation = true, generation
    NS.Cosmetics.FadeDecoration(namePlate, card)
    if Kit.ParentIs(border, row) then Kit.SkinItemIcon(row, card, icon, border, true, true) end
    card.fill:SetColorTexture(NS.Theme.GetColor("card"))
    card.line:SetColorTexture(NS.Theme.GetColor("accent"))
    card.fill:Show()
    MarkSelection(row, card, turnIn)
end

local rowParts = { "NameFrame", "Icon", "IconBorder" }
local function CanPaintRow(row, locked)
    if not Safety.CanCreateRegions(row, not locked) then return false end
    if not locked then return true end
    for _, key in ipairs(rowParts) do
        local part = Safety.Field(row, key)
        if not Safety.Public(part) or part and (not Kit.ParentIs(part, row) or not Safety.CanDecorate(part)) then return false end
    end
    local parent = Safety.Read(row, "GetParent")
    for _ = 1, 12 do
        if parent == UIParent then return true end
        if not Safety.CanDecorate(parent) then return false end
        if parent == QuestFrame then return true end
        parent = Safety.Read(parent, "GetParent")
    end
    return false
end

function Cards.Paint()
    local locked = NS.IsCombatLocked()
    if locked then NS.CombatGate.RunOrDefer("quest-reward-cards", Cards.Paint) end
    generation = generation + 1
    local rewards, turnIn = NativePage()
    local rows = Safety.Field(rewards, "RewardButtons")
    if Safety.Public(rows) and type(rows) == "table" then
        for index = 1, math.min(#rows, 80) do
            local row = rows[index]
            if Safety.Public(row) and Kit.ParentIs(row, rewards) and Safety.Read(row, "IsShown") == true
                and CanPaintRow(row, locked) then PaintRow(row, turnIn) end
        end
    end
    for row, card in pairs(cards) do
        if card.active and card.generation ~= generation and (not locked or CanPaintRow(row, true)) then Release(card) end
    end
end

local queued = false
local function PaintAfterNative()
    queued = false
    Safety.Dispatch(Cards.Paint)
end

local function AfterNative()
    if not queued and enabled and Safety.Read(QuestFrame, "IsVisible") == true then
        queued = true
        C_Timer.After(0, PaintAfterNative)
    end
end

local function OnHide()
    if enabled then NS.Registry.QueueJob(Cards.Paint) end
end

function Cards.Enable()
    if not hooked then
        hooksecurefunc("QuestInfoItem_OnClick", AfterNative)
        hooksecurefunc("QuestInfo_ShowRewards", AfterNative)
        QuestFrame:HookScript("OnHide", OnHide)
        hooked = true
    end
    enabled = true
end

function Cards.Disable()
    enabled = false
    Cards.Paint()
end
