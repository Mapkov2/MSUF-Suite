local _, P = ...
local NS, S = P.NS, P.Suite
local Standard = P.DataTextStandard
local Actions = P.DataTextActions
-- The DataTexts bar frames and the pointer on them: a bar is a plain frame
-- with a visual layer, a bag medallion and SLOT_COUNT places. Places are
-- ordinary buttons; Actions.lua lends them its secure overlay and popups.
-- DataTexts.lua styles, places and fills the bars.
local Bars = {}
P.DataTextBars = Bars
local M = P.DataTexts
local SLOT_COUNT = P.SLOT_COUNT
local BADGE = "Interface\\AddOns\\MSUF_Suite_DataTexts\\Media\\BagMedallion.tga"
local VISIBILITY = NS.DataTextVisibility
-- Per-bar setting names, built once so event paths never concatenate keys.
local BAR_KEYS = {}
local function BarKeys(i)
    if BAR_KEYS[i] then return BAR_KEYS[i] end
    local prefix = "bar" .. i
    BAR_KEYS[i] = {
        prefix = prefix, enabled = prefix .. "Enabled", visibility = prefix .. "Visibility",
        injured = prefix .. "LoadCondShowWhenInjured", instance = prefix .. "LoadCondHideInInstance",
        housing = prefix .. "LoadCondHideInHousing",
    }
    return BAR_KEYS[i]
end
P.DataTextBarKeys = BarKeys

-- A refresh builds the names again (bar IDs come and go).
function Bars.ResetKeys()
    for key in pairs(BAR_KEYS) do BAR_KEYS[key] = nil end
end

local function Tooltip(button)
    if not M.active or not button.source then return end
    local title = S.Text(NS.DataTextSources[button.sourceIndex] or "")
    if button.extra then
        Actions.Tooltip(button, title)
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, 1, .82, .36)
    if Standard.TooltipLines(GameTooltip, button, M.config) then Actions.GoldTooltip(GameTooltip) end
    GameTooltip:Show()
end

local function HideTooltip(button)
    Actions.Leave(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end
Bars.HideTooltip = HideTooltip

-- Built-in places open Blizzard windows out of combat; Actions.lua decides
-- for the additional sources.
local function Click(button, mouse)
    if not button.source then return end
    if button.extra then
        Actions.Click(button, mouse or "LeftButton")
    elseif not NS.IsCombatLocked() then
        Standard.Click(button)
    end
end

-- Mouseover bars: only a real hover change rebinds the sampled sources.
local function SetHover(bar, hovered)
    if M.config[bar.visibilityKey] ~= VISIBILITY.MOUSEOVER or bar.hover == hovered then return end
    bar.hover = hovered
    bar.frame:SetAlpha(hovered and 1 or 0)
    M:Rebind()
end

local function SlotEnter(button)
    SetHover(button.bar, true)
    Actions.hovered = button
    Actions.Attach(button)
    Tooltip(button)
end

local function SlotLeave(button)
    -- The secure overlay over this place took the pointer: still hovered.
    if Actions.Covers(button) then return end
    if Actions.hovered == button then Actions.hovered = nil end
    HideTooltip(button)
    if not button.bar.frame:IsMouseOver() then SetHover(button.bar, false) end
end
Actions.enter, Actions.leave = SlotEnter, SlotLeave

local function BarEnter(frame) SetHover(frame.bar, true) end

local function BarLeave(frame)
    if not frame:IsMouseOver() then SetHover(frame.bar, false) end
end

-- A bar that hides takes the secure overlay and popup of its places along.
local function BarShownChanged(frame)
    if not frame:IsVisible() then
        local owner = Actions.Owner()
        if owner and owner.bar.frame == frame then Actions.Detach() end
        local popup = Actions.popup
        if popup and popup.owner and popup.owner.bar.frame == frame then Actions.ClosePopup() end
    end
    if not M.styling then M:Rebind() end
end

local function CreateEdge(frame, layer, from, to)
    local texture = S.CreateTexture(frame, nil, layer)
    texture:SetPoint(from)
    texture:SetPoint(to)
    return texture
end

-- Places are ordinary buttons (no secure template), so a bar may move,
-- resize, show and hide in combat. Actions.lua runs protected clicks.
local function CreateSlot(bar, slot)
    local button = S.CreateFrame("Button", nil, bar.visual)
    button.bar, button.slot = bar, slot
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", Click)
    button:SetScript("OnEnter", SlotEnter)
    button:SetScript("OnLeave", SlotLeave)
    -- Only volume places take the wheel; the others leave it to the camera.
    button:SetScript("OnMouseWheel", Actions.Wheel)
    button:EnableMouseWheel(false)
    if bar.mouseEnabled == false then button:EnableMouse(false) end
    local text = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", button, "LEFT", 5, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    button.label = text
    return button
end

-- Legacy bars keep their six reusable places. Extra places allocate only
-- when configured, and are kept for later edits or recycling of this bar.
function Bars.EnsureSlots(bar, config)
    local count = 6
    for slot = 7, SLOT_COUNT do
        local source = config[bar.prefix .. "Slot" .. slot]
        if source and source ~= 1 then count = slot end
    end
    for slot = #bar.slots + 1, count do bar.slots[slot] = CreateSlot(bar, slot) end
end

local function AssignBarKeys(bar, index)
    local keys = BarKeys(index)
    local prefix = keys.prefix
    bar.index, bar.prefix = index, prefix
    bar.enabledKey, bar.visibilityKey = keys.enabled, keys.visibility
    bar.layoutKey, bar.widthKey, bar.heightKey = prefix .. "Layout", prefix .. "Width", prefix .. "Height"
    bar.injuredKey, bar.instanceKey, bar.housingKey = keys.injured, keys.instance, keys.housing
end

local function CreateBadge(bar)
    local badge = S.CreateFrame("Button", nil, bar.visual)
    badge.bar, badge.source, badge.sourceIndex, badge.text = bar, "bags", 3, Standard.LABELS.bags
    badge:RegisterForClicks("LeftButtonUp")
    badge:SetScript("OnClick", Click)
    badge:SetScript("OnEnter", SlotEnter)
    badge:SetScript("OnLeave", SlotLeave)
    local badgeArt = S.CreateTexture(badge, nil, "OVERLAY")
    badgeArt:SetAllPoints(badge)
    badgeArt:SetTexture(BADGE)
    bar.badge = badge
end

function Bars.Create(index)
    if M.bars[index] then return M.bars[index] end
    local recycled = table.remove(M.pool)
    if recycled then
        AssignBarKeys(recycled, index)
        recycled.hover = false
        M.bars[index] = recycled
        return recycled
    end
    local frame = S.CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    local visual = S.CreateFrame("Frame", nil, frame)
    visual:SetAllPoints(frame)
    local background = S.CreateTexture(visual, nil, "BACKGROUND")
    background:SetAllPoints(visual)
    local gradient = S.CreateTexture(visual, nil, "BACKGROUND")
    gradient:SetAllPoints(visual)
    gradient:SetTexture("Interface\\Buttons\\WHITE8X8")
    local top = CreateEdge(visual, "BORDER", "TOPLEFT", "TOPRIGHT")
    top:SetHeight(1)
    local bottom = CreateEdge(visual, "BORDER", "BOTTOMLEFT", "BOTTOMRIGHT")
    bottom:SetHeight(1)
    local left = CreateEdge(visual, "BORDER", "TOPLEFT", "BOTTOMLEFT")
    left:SetWidth(1)
    local right = CreateEdge(visual, "BORDER", "TOPRIGHT", "BOTTOMRIGHT")
    right:SetWidth(1)
    local accent = CreateEdge(visual, "ARTWORK", "BOTTOMLEFT", "BOTTOMRIGHT")
    accent:SetHeight(1)
    local bar = {
        frame = frame, visual = visual, background = background, gradient = gradient,
        border = { top, bottom, left, right },
        accent = accent, dividers = {}, slots = {},
    }
    AssignBarKeys(bar, index)
    frame.bar = bar
    M.bars[index] = bar
    CreateBadge(bar)
    Bars.EnsureSlots(bar, M.config)
    frame:SetScript("OnEnter", BarEnter)
    frame:SetScript("OnLeave", BarLeave)
    frame:SetScript("OnShow", BarShownChanged)
    frame:SetScript("OnHide", BarShownChanged)
    return bar
end
