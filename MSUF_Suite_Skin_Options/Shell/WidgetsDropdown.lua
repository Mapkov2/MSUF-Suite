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
            text:SetText(DropdownLabel(value))
            local path = dropdown.previewer and dropdown.previewer(value)
            local _, height, flags = text:GetFont()
            text:SetFont(path or row.defaultFont, height or 12, flags or "")
            O.SetButtonActive(row, value == selected)
            row:Show()
        else
            row.value = nil
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
    frame:SetSize(430, 350)
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
    dropdown.frame:ClearAllPoints()
    dropdown.frame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    dropdown.blocker:Show()
    dropdown.search:SetFocus()
    FilterDropdown()
end

-- options: history = false, countLabel / countSingular (translated plurals).
function O.CreateDropdown(parent, labelText, values, getter, setter, width, formatter, previewer, options)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 620, 42)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("LEFT", 12, 0)

    local function Pick(value)
        local began = BeginWidgetChange(labelText, options)
        if began == nil then return end
        setter(value)
        CommitWidgetChange(labelText, options, began)
    end
    local valueButton = O.CreateSettingButton(row, "", math.min(350, (width or 620) * 0.52), 28,
        function(button)
            OpenDropdown(button, values, getter, Pick, formatter, previewer, options)
        end)
    valueButton:SetPoint("RIGHT", -8, 0)
    local caption = O.AlignButtonLabel(valueButton)
    valueButton.defaultFont = caption:GetFont()
    SingleLine(caption)

    local painted, paintedPath, hasPainted = nil, nil, false
    O.TrackAndRefresh(function()
        local value = getter()
        local path = previewer and previewer(value)
        if hasPainted and value == painted and path == paintedPath then return end
        painted, paintedPath, hasPainted = value, path, true
        caption:SetText((formatter and formatter(value) or tostring(value)) .. "  v")
        local _, height, flags = caption:GetFont()
        caption:SetFont(path or valueButton.defaultFont, height or 12, flags or "")
    end)
    return row, valueButton
end
