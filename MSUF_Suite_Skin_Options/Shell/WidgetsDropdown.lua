local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

-- The dropdown row and its one shared, searchable popup (see Widgets.lua).
local Widgets = Private.Widgets
local CanChange = Widgets.CanChange
local BeginWidgetChange = Widgets.BeginWidgetChange
local CommitWidgetChange = Widgets.CommitWidgetChange
local CreateInputBox = Widgets.CreateInputBox
local popups = Widgets.popups
local WatchCombat = Widgets.WatchCombat

-- One reusable, searchable popup for large option sets. Values are resolved
-- only when opened, so fonts registered later by any loaded SharedMedia addon
-- appear without a reload or a permanent media callback.
local dropdown = {
    rows = {},
    values = {},
    -- Lowered labels of `values`, built once per open for the search filter.
    lowerLabels = {},
    filtered = {},
    offset = 1,
    visibleRows = 10,
}
O.dropdownState = dropdown

local POPUP_WIDTH, POPUP_HEIGHT, POPUP_GAP = 430, 350, 4
-- The collapsed value control: 2 units taller than the 28 of the other
-- value buttons, still inside the unchanged 42-unit row.
local VALUE_HEIGHT = 30

local function CloseDropdown()
    if dropdown.blocker then dropdown.blocker:Hide() end
    dropdown.owner = nil
    dropdown.setter = nil
    dropdown.getter = nil
    dropdown.formatter = nil
    dropdown.previewer = nil
    if popups.dropdown then
        popups.dropdown = false
        WatchCombat()
    end
end
O.CloseDropdown = CloseDropdown
Widgets.CloseOnCombat(CloseDropdown)

local function DropdownLabel(value)
    return dropdown.formatter and dropdown.formatter(value) or tostring(value)
end

-- The checkbox label style (O.CreateToggle: CreateText size 14, "text"),
-- captured once from a real label so value and list text match it exactly.
local labelStyle
local function LabelStyle(reference)
    if not labelStyle and reference then
        local path, height, flags = reference:GetFont()
        if path then labelStyle = { path = path, height = height or 13, flags = flags or "" } end
    end
    return labelStyle
end

-- Checkbox-label font (or a font preview at the same size) and color.
local function PaintLabelText(text, previewPath, fallbackPath)
    local style = labelStyle
    local _, height, flags = text:GetFont()
    text:SetFont(previewPath or (style and style.path) or fallbackPath,
        (style and style.height) or height or 13, (style and style.flags) or flags or "")
end

local function RefreshDropdownRows()
    if not dropdown.frame then return end
    local maximum = math.max(1, #dropdown.filtered - dropdown.visibleRows + 1)
    dropdown.offset = math.max(1, math.min(maximum, dropdown.offset or 1))
    dropdown.refreshing = true
    dropdown.slider:SetMinMaxValues(1, maximum)
    dropdown.slider:SetValue(dropdown.offset)
    dropdown.slider:SetShown(maximum > 1)
    dropdown.refreshing = false

    local selected = dropdown.getter and dropdown.getter()
    for index = 1, dropdown.visibleRows do
        local row = dropdown.rows[index]
        local value = dropdown.filtered[dropdown.offset + index - 1]
        if value ~= nil then
            row.value = value
            local text = row.caption
            local caption = DropdownLabel(value)
            text:SetText(caption)
            row.fullLabel = caption
            local path = dropdown.previewer and dropdown.previewer(value)
            PaintLabelText(text, path, row.defaultFont)
            O.SetButtonActive(row, value == selected)
            -- The checkbox label color; the selected row keeps its active surface.
            O.SetTextColor(text, "text")
            row:Show()
        else
            row.value = nil
            row.fullLabel = nil
            row:Hide()
        end
    end
    local count = #dropdown.filtered
    local label = count == 1 and dropdown.countSingular or dropdown.countLabel
    dropdown.count:SetText(("%d %s"):format(count, label))
end

local function FilterDropdown()
    local query = dropdown.search and (dropdown.search:GetText() or ""):lower() or ""
    local values, lowerLabels, filtered = dropdown.values, dropdown.lowerLabels, dropdown.filtered
    for index = #filtered, 1, -1 do filtered[index] = nil end
    for index = 1, #values do
        if query == "" or lowerLabels[index]:find(query, 1, true) then
            filtered[#filtered + 1] = values[index]
        end
    end
    dropdown.offset = 1
    RefreshDropdownRows()
end

local function PickDropdownRow(button)
    local value = button.value
    if value ~= nil and dropdown.setter then dropdown.setter(value) end
    CloseDropdown()
end

-- One line per value: a long label ends at the row edge.
local function SingleLine(label)
    label:SetWordWrap(false)
    label:SetMaxLines(1)
end

-- Full label on hover, only when the single line was cut, through the
-- client's shared tooltip; nothing in combat (the blocker closes anyway).
local function TruncatedText(label)
    if label and label.IsTruncated and label:IsTruncated() then return label:GetText() end
end

local function ShowFullLabel(button)
    local tooltip = _G.GameTooltip
    if not tooltip or (NS.IsCombatLocked and NS.IsCombatLocked()) then return end
    local title = TruncatedText(button.fieldLabel)
    local value = TruncatedText(button.caption)
    if not (title or value) then return end
    if value then value = button.fullLabel or value end
    tooltip:SetOwner(button, "ANCHOR_RIGHT")
    tooltip:SetText(title or value, 1, 1, 1, 1, true)
    if title and value then tooltip:AddLine(value, 1, 1, 1, true) end
    tooltip:Show()
end

local function HideFullLabel(button)
    local tooltip = _G.GameTooltip
    if tooltip and tooltip.GetOwner and tooltip:GetOwner() == button then tooltip:Hide() end
end

local function AttachFullLabel(button)
    if button.HookScript then
        button:HookScript("OnEnter", ShowFullLabel)
        button:HookScript("OnLeave", HideFullLabel)
        button:HookScript("OnHide", HideFullLabel)
    end
end

local function CreateDropdownSearch(frame)
    local search = CreateInputBox(frame, 9)
    search:SetPoint("TOPLEFT", 12, -12)
    search:SetPoint("TOPRIGHT", -38, -12)
    search:SetHeight(28)
    search:SetScript("OnTextChanged", FilterDropdown)
    search:SetScript("OnEscapePressed", CloseDropdown)
    return search
end

local function CreateDropdownRows(frame)
    for index = 1, dropdown.visibleRows do
        local row = O.CreateButton(frame, "", 390, 26, PickDropdownRow, "navigation")
        row:SetPoint("TOPLEFT", 12, -46 - (index - 1) * 27)
        local label = O.AlignButtonLabel(row)
        SingleLine(label)
        row.caption = label
        row.defaultFont = label:GetFont()
        AttachFullLabel(row)
        dropdown.rows[index] = row
    end
end

local function CreateDropdownSlider(frame)
    local slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPRIGHT", -9, -48)
    slider:SetPoint("BOTTOMRIGHT", -9, 28)
    slider:SetWidth(8)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    O.CreateScrollThumb(slider, 42)
    slider:SetScript("OnValueChanged", function(_, value)
        if dropdown.refreshing then return end
        dropdown.offset = math.floor((tonumber(value) or 1) + 0.5)
        RefreshDropdownRows()
    end)
    return slider
end

local function EnsureDropdown()
    if dropdown.frame then return end
    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:SetFrameLevel(500)
    blocker:EnableMouse(true)
    blocker:SetScript("OnClick", CloseDropdown)
    blocker:Hide()
    dropdown.blocker = blocker

    local frame = O.CreatePanel(blocker, "popup")
    frame:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    -- Last guard after PlacePopup: never drawn past the viewport.
    frame:SetClampedToScreen(true)
    frame:SetFrameLevel(501)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        dropdown.offset = (dropdown.offset or 1) - (delta or 0) * 3
        RefreshDropdownRows()
    end)
    dropdown.frame = frame

    dropdown.search = CreateDropdownSearch(frame)
    local close = O.CreateWindowActionButton(frame, "close", 28, 28, CloseDropdown)
    close:SetPoint("TOPRIGHT", -8, -12)
    CreateDropdownRows(frame)
    dropdown.slider = CreateDropdownSlider(frame)
    local count = O.CreateText(frame, "", 10, "dim")
    count:SetPoint("BOTTOMLEFT", 14, 10)
    dropdown.count = count
end

-- Natural anchor: below the control, right edges aligned. Flipped above when
-- the space below is short, and to left-aligned when the control sits too
-- close to the left edge (a bottom-right control opens up and leftwards).
-- Measured in UIParent units, the popup's own space.
local function PlacePopup(frame, owner)
    local vertical, ownerVertical, offsetY = "TOP", "BOTTOM", -POPUP_GAP
    local horizontal = "RIGHT"
    local root = UIParent
    local ownerScale = owner.GetEffectiveScale and owner:GetEffectiveScale()
    local rootScale = root and root.GetEffectiveScale and root:GetEffectiveScale()
    local bottom, top = owner.GetBottom and owner:GetBottom(), owner.GetTop and owner:GetTop()
    -- A right-aligned popup reaches POPUP_WIDTH left of the control's right edge.
    local right = owner.GetRight and owner:GetRight()
    local rootHeight = root and root.GetHeight and root:GetHeight()
    if type(ownerScale) == "number" and type(rootScale) == "number" and rootScale > 0 then
        local ratio = ownerScale / rootScale
        if type(bottom) == "number" and type(top) == "number" and type(rootHeight) == "number" then
            local below = bottom * ratio
            local above = rootHeight - top * ratio
            if below < POPUP_HEIGHT + POPUP_GAP and above > below then
                vertical, ownerVertical, offsetY = "BOTTOM", "TOP", POPUP_GAP
            end
        end
        if type(right) == "number" and right * ratio < POPUP_WIDTH then horizontal = "LEFT" end
    end
    frame:ClearAllPoints()
    frame:SetPoint(vertical .. horizontal, owner, ownerVertical .. horizontal, 0, offsetY)
end

local function OpenDropdown(owner, provider, getter, setter, formatter, previewer, options)
    if not CanChange() then return end
    EnsureDropdown()
    dropdown.owner = owner
    dropdown.getter = getter
    dropdown.setter = setter
    dropdown.formatter = formatter
    dropdown.previewer = previewer
    dropdown.countLabel = options and options.countLabel or L["choices"]
    dropdown.countSingular = options and options.countSingular or L["choice"]
    local values = type(provider) == "function" and (provider() or {}) or (provider or {})
    dropdown.values = values
    local lowerLabels = dropdown.lowerLabels
    for index = 1, #values do lowerLabels[index] = DropdownLabel(values[index]):lower() end
    for index = #lowerLabels, #values + 1, -1 do lowerLabels[index] = nil end
    popups.dropdown = true
    WatchCombat()
    dropdown.search:SetText("")
    dropdown.offset = 1
    PlacePopup(dropdown.frame, owner)
    dropdown.blocker:Show()
    dropdown.search:SetFocus()
    FilterDropdown()
end

-- options: history = false, countLabel / countSingular (translated plurals).
function O.CreateDropdown(parent, labelText, values, getter, setter, width, formatter, previewer, options)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 620, 42)
    -- Same call as the checkbox label; it is also the style reference.
    local label = O.CreateText(row, labelText, 14, "text")
    label:SetPoint("LEFT", 12, 0)
    SingleLine(label)
    LabelStyle(label)

    local function Pick(value)
        local began = BeginWidgetChange(labelText, options)
        if began == nil then return end
        setter(value)
        CommitWidgetChange(labelText, options, began)
    end
    local valueWidth = math.min(350, (width or 620) * 0.52)
    local valueButton = O.CreateSettingButton(row, "", valueWidth, VALUE_HEIGHT,
        function(button)
            OpenDropdown(button, values, getter, Pick, formatter, previewer, options)
        end)
    valueButton:SetPoint("RIGHT", -8, 0)
    local caption = O.AlignButtonLabel(valueButton)
    valueButton.defaultFont = caption:GetFont()
    valueButton.caption = caption
    valueButton.fieldLabel = label
    SingleLine(caption)
    local arrow = valueButton:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_dropdown_chevron_down.tga")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -10, 0)
    caption:ClearAllPoints()
    caption:SetPoint("LEFT", 10, 0)
    caption:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
    AttachFullLabel(valueButton)

    local painted, paintedPath, hasPainted = nil, nil, false
    O.TrackAndRefresh(function()
        local value = getter()
        local path = previewer and previewer(value)
        if hasPainted and value == painted and path == paintedPath then return end
        painted, paintedPath, hasPainted = value, path, true
        local text = formatter and formatter(value) or tostring(value)
        valueButton.fullLabel = text
        caption:SetText(text)
        PaintLabelText(caption, path, valueButton.defaultFont)
    end)
    local gear = O.AttachOutlineControl
        and O.AttachOutlineControl(row, labelText, options and options.outlineSetting, -16 - valueWidth)
    label:SetPoint("RIGHT", gear or valueButton, "LEFT", -8, 0)
    return row, valueButton
end
