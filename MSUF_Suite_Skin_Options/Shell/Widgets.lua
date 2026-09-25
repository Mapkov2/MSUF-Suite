local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local DISABLED_ALPHA = 0.52

local function PlayClick()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

------------------------------------------------------------------ buttons
-- One shared click handler; each button carries its own callback.
local function ButtonClick(self, mouseButton)
    if self.disabledByOptions then return end
    PlayClick()
    local callback = self.optionsCallback
    if callback then callback(self, mouseButton) end
end

function O.CreateButton(parent, text, width, height, callback, role)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 120, height or 28)
    local state = NS.Surface.SkinOwnedButton(button, {
        role = role or "button",
        activeRole = role == "navigation" and "navigationActive" or nil,
        useControlShape = true,
        pillHeight = height or 28,
    })
    local label = O.CreateText(button, text or "", 12, "text", "CENTER")
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -10, 0)
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button.optionsCallback = callback
    button:SetScript("OnClick", ButtonClick)
    O.widgetStates[button] = { label = label, surface = state, role = role or "button" }
    return button
end

-- Left-aligned single-line caption for list rows (navigation, search results,
-- dropdown entries).
function O.AlignButtonLabel(button)
    local state = O.widgetStates[button]
    local label = state and state.label
    if not label then return nil end
    label:SetJustifyH("LEFT")
    return label
end

local WINDOW_ACTION_ATLAS = {
    close = "RedButton-Exit",
    maximize = "RedButton-Expand",
    minimize = "RedButton-Condense",
}

-- Blizzard's red window-action art as the native state textures, so the
-- window action skin draws over the same regions Blizzard buttons have.
function O.SeedWindowActionTextures(button, kind)
    local atlas = WINDOW_ACTION_ATLAS[kind]
    if not atlas then return false end
    local normal = button:CreateTexture(nil, "ARTWORK")
    local pushed = button:CreateTexture(nil, "ARTWORK")
    local disabled = button:CreateTexture(nil, "ARTWORK")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    normal:SetAtlas(atlas)
    pushed:SetAtlas(atlas .. "-Pressed")
    disabled:SetAtlas(atlas .. "-Disabled")
    highlight:SetAtlas("RedButton-Highlight")
    button:SetNormalTexture(normal)
    button:SetPushedTexture(pushed)
    button:SetDisabledTexture(disabled)
    button:SetHighlightTexture(highlight, "ADD")
    return true
end

function O.CreateWindowActionButton(parent, kind, width, height, callback)
    local button = O.CreateButton(parent, "", width or 28, height or 28, callback)
    O.SeedWindowActionTextures(button, WINDOW_ACTION_ATLAS[kind] and kind or "minimize")
    NS.Checkmarks.TrackButton(button, "options-window-actions")
    NS.WindowActionSkin.Apply(button, "options-window-actions", kind)
    return button
end

function O.SetButtonActive(button, active)
    NS.Surface.SetActive(button, active)
    local state = O.widgetStates[button]
    if state and state.label then
        O.SetTextColor(state.label, active and "title" or "muted")
    end
end

function O.SetButtonEnabled(button, enabled)
    local state = O.widgetStates[button]
    enabled = enabled == true
    button.disabledByOptions = not enabled
    button:EnableMouse(enabled)
    if state and state.label then
        O.SetTextColor(state.label, enabled and "text" or "disabled")
    end
end

function O.SetWidgetEnabled(widget, enabled)
    if not widget then return end
    enabled = enabled == true
    if widget.segmentButtons then
        for index = 1, #widget.segmentButtons do
            O.SetButtonEnabled(widget.segmentButtons[index], enabled)
        end
    elseif widget._mskinControl then
        widget._mskinControl:EnableMouse(enabled)
    elseif O.widgetStates[widget] then
        O.SetButtonEnabled(widget, enabled)
    end
    widget:SetAlpha(enabled and 1 or DISABLED_ALPHA)
end

------------------------------------------------------------------ layout helpers
-- Small accent heading between groups of rows.
function O.CreateSubheading(parent, text, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or 484, 26)
    local label = O.CreateText(row, text, 10, "accent")
    label:SetPoint("BOTTOMLEFT", 4, 3)
    return row
end

-- Stacks { widget, essential } rows top to bottom; Guided mode keeps only the
-- essential ones. Returns a mode listener that also resizes the list.
function O.StackRows(list, rows)
    return function()
        local guided = O.GetMode() == "guided"
        local previous
        local contentHeight = 4
        for index = 1, #rows do
            local row, essential = rows[index][1], rows[index][2]
            local show = not guided or essential
            row:ClearAllPoints()
            row:SetShown(show)
            if show then
                if previous then
                    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
                else
                    row:SetPoint("TOPLEFT", 0, -2)
                end
                contentHeight = contentHeight + row:GetHeight() + (previous and 8 or 0)
                previous = row
            end
        end
        list:SetHeight(math.max(1, contentHeight + 4))
    end
end

------------------------------------------------------------------ history glue
local function BeginWidgetChange(labelText, options)
    if options and options.history == false then return false end
    return O.BeginUserChange(labelText)
end

-- CommitUserChange repaints the options itself; without an active change
-- the widget asks for the repaint.
local function CommitWidgetChange(labelText, options, began)
    if options and options.history == false then return end
    if began or O.IsUserChangeActive() then
        O.CommitUserChange(labelText)
    else
        O.RefreshAll()
    end
end

------------------------------------------------------------------ toggle, cycle, segmented
function O.CreateToggle(parent, labelText, getter, setter, width, options)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 430, 38)
    NS.Surface.SkinOwnedButton(button, { role = "card", useControlShape = false })

    local label = O.CreateText(button, labelText, 12, "text")
    label:SetPoint("LEFT", 12, 0)

    local track = CreateFrame("Frame", nil, button)
    track:SetSize(42, 20)
    track:SetPoint("RIGHT", -9, 0)
    NS.Surface.Attach(track, {
        role = "navigation",
        activeRole = "navigationActive",
        shape = "pill",
        pillHeight = 20,
    })

    local knob = CreateFrame("Frame", nil, track)
    knob:SetSize(14, 14)
    NS.Surface.Attach(knob, { role = "popup", shape = "round", radius = 8, border = 1, slice = false })

    local function Refresh()
        local enabled = getter() == true
        NS.Surface.SetActive(track, enabled)
        knob:ClearAllPoints()
        if enabled then
            knob:SetPoint("RIGHT", track, "RIGHT", -4, 0)
        else
            knob:SetPoint("LEFT", track, "LEFT", 4, 0)
        end
        O.SetTextColor(label, enabled and "text" or "muted")
    end
    O.TrackRefresh(Refresh)
    Refresh()

    button:SetScript("OnClick", function()
        if NS.IsCombatLocked() then return end
        local began = BeginWidgetChange(labelText, options)
        setter(not getter())
        PlayClick()
        Refresh()
        CommitWidgetChange(labelText, options, began)
    end)
    return button
end

local function Choices(values)
    local available = type(values) == "function" and values() or values
    return type(available) == "table" and available or {}
end

function O.CreateCycle(parent, labelText, values, getter, setter, width, formatter, options)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 520, 42)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("LEFT", 12, 0)

    local valueButton = O.CreateButton(row, "", 180, 28, function()
        local available = Choices(values)
        if #available == 0 then return end
        local current = getter()
        local nextValue = available[1]
        for index = 1, #available do
            if available[index] == current then
                nextValue = available[(index % #available) + 1]
                break
            end
        end
        local began = BeginWidgetChange(labelText, options)
        setter(nextValue)
        CommitWidgetChange(labelText, options, began)
    end)
    valueButton:SetPoint("RIGHT", -8, 0)
    local valueLabel = O.widgetStates[valueButton].label

    local function Refresh()
        local value = getter()
        valueLabel:SetText(formatter and formatter(value) or tostring(value))
    end
    O.TrackRefresh(Refresh)
    Refresh()
    return row
end

-- One-click alternative to a cycle for small, mutually exclusive sets. This
-- keeps the complete choice set visible in Guided mode while reusing the same
-- history, sound, active-state and refresh contracts as the other widgets.
function O.CreateSegmented(parent, labelText, values, getter, setter, width, formatter, options)
    local available = Choices(values)
    local rowWidth = width or 520
    local row = O.CreatePanel(parent, "card")
    row:SetSize(rowWidth, 72)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -9)

    local gap = 6
    local innerWidth = rowWidth - 24
    local buttonWidth = innerWidth
    if #available > 0 then
        buttonWidth = math.floor((innerWidth - math.max(0, #available - 1) * gap) / #available)
    end
    local buttons = {}
    for index = 1, #available do
        local value = available[index]
        local button = O.CreateButton(row, formatter and formatter(value) or tostring(value),
            buttonWidth, 28, function()
                if getter() == value then return end
                local began = BeginWidgetChange(labelText, options)
                setter(value)
                if options and options.history == false then
                    O.RefreshAll()
                else
                    CommitWidgetChange(labelText, options, began)
                end
            end, "navigation")
        if index == 1 then
            button:SetPoint("BOTTOMLEFT", 12, 8)
        else
            button:SetPoint("LEFT", buttons[index - 1], "RIGHT", gap, 0)
        end
        buttons[index] = button
    end

    local function Refresh()
        local selected = getter()
        for index = 1, #available do
            O.SetButtonActive(buttons[index], available[index] == selected)
        end
    end
    O.TrackRefresh(Refresh)
    Refresh()
    row.segmentButtons = buttons
    return row
end

------------------------------------------------------------------ dropdown
-- One reusable, searchable popup for large option sets. Values are resolved
-- only when opened, so fonts registered later by any loaded SharedMedia addon
-- appear without a reload or a permanent media callback.
local dropdown = {
    rows = {},
    values = {},
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
end
O.CloseDropdown = CloseDropdown

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
    for index = #dropdown.filtered, 1, -1 do dropdown.filtered[index] = nil end
    for index = 1, #dropdown.values do
        local value = dropdown.values[index]
        if query == "" or DropdownLabel(value):lower():find(query, 1, true) then
            dropdown.filtered[#dropdown.filtered + 1] = value
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

-- A thin accent thumb on an ink track, shared by the dropdown and the page
-- scroll containers.
function O.CreateScrollThumb(slider, thumbHeight)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(NS.Theme.GetColor("ink"))
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, thumbHeight)
    thumb:SetTexture(NS.path .. "Media\\Shapes\\pill_h24_fill.png")
    if thumb.SetTextureSliceMargins then thumb:SetTextureSliceMargins(12, 0, 12, 0) end
    thumb:SetVertexColor(NS.Theme.GetColor("accent"))
    slider:SetThumbTexture(thumb)
    return track, thumb
end

local function CreateDropdownSearch(frame)
    local search = CreateFrame("EditBox", nil, frame)
    search:SetPoint("TOPLEFT", 12, -12)
    search:SetPoint("TOPRIGHT", -38, -12)
    search:SetHeight(28)
    search:SetAutoFocus(false)
    search:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    if search.SetTextInsets then search:SetTextInsets(9, 9, 0, 0) end
    NS.Surface.Attach(search, { role = "input", shape = "continuous", radius = 4, border = 1 })
    search:SetScript("OnTextChanged", FilterDropdown)
    search:SetScript("OnEscapePressed", CloseDropdown)
    return search
end

local function CreateDropdownRows(frame)
    for index = 1, dropdown.visibleRows do
        local row = O.CreateButton(frame, "", 390, 26, PickDropdownRow, "navigation")
        row:SetPoint("TOPLEFT", 12, -46 - (index - 1) * 27)
        local label = O.AlignButtonLabel(row)
        if label.SetWordWrap then label:SetWordWrap(false) end
        if label.SetMaxLines then label:SetMaxLines(1) end
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
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
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
    EnsureDropdown()
    dropdown.owner = owner
    dropdown.getter = getter
    dropdown.setter = setter
    dropdown.formatter = formatter
    dropdown.previewer = previewer
    dropdown.countLabel = options and options.countLabel or L["choices"]
    dropdown.countSingular = options and options.countSingular or L["choice"]
    dropdown.values = type(provider) == "function" and (provider() or {}) or (provider or {})
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
        setter(value)
        CommitWidgetChange(labelText, options, began)
    end
    local valueButton = O.CreateButton(row, "", math.min(350, (width or 620) * 0.52), 28, function(button)
        OpenDropdown(button, values, getter, Pick, formatter, previewer, options)
    end)
    valueButton:SetPoint("RIGHT", -8, 0)
    local caption = O.AlignButtonLabel(valueButton)
    valueButton.defaultFont = caption:GetFont()
    if caption.SetWordWrap then caption:SetWordWrap(false) end
    if caption.SetMaxLines then caption:SetMaxLines(1) end

    local function Refresh()
        local value = getter()
        caption:SetText((formatter and formatter(value) or tostring(value)) .. "  v")
        local path = previewer and previewer(value)
        local _, height, flags = caption:GetFont()
        caption:SetFont(path or valueButton.defaultFont, height or 12, flags or "")
    end
    O.TrackRefresh(Refresh)
    Refresh()
    return row, valueButton
end

------------------------------------------------------------------ slider, input, search
function O.CreateSlider(parent, labelText, minimum, maximum, step, getter, setter, width, formatter, options)
    -- One whole unit for integral ranges, one percent point for fractional
    -- ranges such as opacity and scale. Modifier keys use the same 5x/10x
    -- increments as the Suite controls in the MSUF menu.
    step = step < 1 and 0.01 or 1
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 520, 58)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -9)
    local valueText = O.CreateText(row, "", 11, "accent", "RIGHT")
    valueText:SetPoint("TOPRIGHT", -12, -9)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("BOTTOMLEFT", 14, 10)
    slider:SetPoint("BOTTOMRIGHT", -14, 10)
    slider:SetHeight(14)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(3)
    track:SetColorTexture(NS.Theme.GetColor("borderSoft"))

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(16, 16)
    thumb:SetTexture(NS.path .. "Media\\Shapes\\continuous_r8_fill.png")
    thumb:SetVertexColor(NS.Theme.GetColor("accent"))
    slider:SetThumbTexture(thumb)

    local internalChange = false
    local dragging = false
    slider:SetScript("OnMouseDown", function()
        if NS.IsCombatLocked() then return end
        dragging = BeginWidgetChange(labelText, options)
    end)
    slider:SetScript("OnMouseUp", function()
        if dragging then CommitWidgetChange(labelText, options, true) end
        dragging = false
    end)
    slider:SetScript("OnValueChanged", function(_, value)
        if internalChange or NS.IsCombatLocked() then return end
        local multiplier = IsControlKeyDown and IsControlKeyDown() and 10
            or IsShiftKeyDown and IsShiftKeyDown() and 5 or 1
        local increment = step * multiplier
        value = minimum + math.floor((value - minimum) / increment + 0.5) * increment
        value = math.max(minimum, math.min(maximum, value))
        if value ~= slider:GetValue() then
            internalChange = true
            slider:SetValue(value)
            internalChange = false
        end
        local current = tonumber(getter())
        if current and math.abs(current - value) < 0.000001 then return end
        local began = not dragging and BeginWidgetChange(labelText, options)
        setter(value)
        if began then CommitWidgetChange(labelText, options, true) end
    end)

    local function Refresh()
        local value = getter()
        internalChange = true
        slider:SetValue(value)
        internalChange = false
        valueText:SetText(formatter and formatter(value) or tostring(value))
        track:SetColorTexture(NS.Theme.GetColor("borderSoft"))
        thumb:SetVertexColor(NS.Theme.GetColor("accent"))
    end
    O.TrackRefresh(Refresh)
    Refresh()
    row._mskinControl = slider
    return row
end

local function CreateInputBox(parent, insets)
    local input = CreateFrame("EditBox", nil, parent)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    if input.SetTextInsets then input:SetTextInsets(insets, insets, 0, 0) end
    NS.Surface.Attach(input, { role = "input", shape = "continuous", radius = 4, border = 1 })
    return input
end

function O.CreateInput(parent, labelText, getter, setter, width, options)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 520, 58)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -9)

    local input = CreateInputBox(row, 8)
    input:SetPoint("BOTTOMLEFT", 12, 8)
    input:SetPoint("BOTTOMRIGHT", -12, 8)
    input:SetHeight(24)

    local function Current()
        return tostring(getter() or "")
    end
    local function Commit()
        if NS.IsCombatLocked() then return end
        local value = input:GetText() or ""
        if value ~= Current() then
            local began = BeginWidgetChange(labelText, options)
            setter(value)
            CommitWidgetChange(labelText, options, began)
        end
    end
    input:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText(Current())
        self:ClearFocus()
    end)
    input:SetScript("OnEditFocusLost", Commit)

    O.TrackRefresh(function()
        if not input:HasFocus() then input:SetText(Current()) end
    end)
    input:SetText(Current())
    return row, input
end

function O.CreateSearchBox(parent, placeholderText, callback, width)
    local input = CreateInputBox(parent, 10)
    input:SetSize(width or 300, 28)

    local placeholder = O.CreateText(input, placeholderText or L["Search..."], 11, "dim")
    placeholder:SetPoint("LEFT", 10, 0)
    placeholder:SetPoint("RIGHT", -10, 0)

    local function RefreshSearch()
        local text = input:GetText() or ""
        placeholder:SetShown(text == "")
        if callback then callback(text, input) end
    end
    input:SetScript("OnTextChanged", RefreshSearch)
    input:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
        RefreshSearch()
    end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input.RefreshSearch = RefreshSearch
    return input
end

------------------------------------------------------------------ colors
local function IsEmbeddedCard(card)
    local host = O.embeddedHost
    for _ = 1, 16 do
        if not card then break end
        if card == host then return true end
        card = card.GetParent and card:GetParent()
    end
    return false
end

local function ColorHistoryLabel(colorKey)
    return L["Color: %s"]:format(tostring(colorKey))
end

-- One MSUF context-color target bound to a skin color token.
local function ColorTarget(colorKey, label)
    return {
        label = label,
        hasOpacity = true,
        getRGB = function()
            local color = NS.Theme.GetColorTable(colorKey)
            return color[1], color[2], color[3]
        end,
        getOpacity = function() return NS.Theme.GetColorTable(colorKey)[4] end,
        setRGB = function(r, g, b, a)
            NS.Theme.SetColor(colorKey, r, g, b, a)
            O.RefreshAll()
        end,
    }
end

local function MenuWidgets()
    local menu = _G.MSUF2
    return menu and menu.Widgets
end

local function OpenBlizzardColorPicker(colorKey)
    if NS.IsCombatLocked() or not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        return
    end
    local current = NS.Theme.GetColorTable(colorKey)
    local original = { current[1], current[2], current[3], current[4] }
    local originalPreset = NS.DB.theme.preset
    local originalLook = NS.DB.theme.look
    local historyLabel = ColorHistoryLabel(colorKey)
    local historyCaptured = false

    local function ApplySelection()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = ColorPickerFrame:GetColorAlpha()
        local began = not historyCaptured and O.BeginUserChange(historyLabel)
        NS.Theme.SetColor(colorKey, r, g, b, a)
        if began then
            O.CommitUserChange(historyLabel)
            historyCaptured = true
        end
    end

    ColorPickerFrame:SetupColorPickerAndShow({
        r = current[1],
        g = current[2],
        b = current[3],
        opacity = current[4],
        hasOpacity = true,
        swatchFunc = ApplySelection,
        opacityFunc = ApplySelection,
        cancelFunc = function()
            NS.Theme.SetColor(colorKey, original[1], original[2], original[3], original[4])
            NS.DB.theme.preset = originalPreset
            NS.DB.theme.look = originalLook
            if historyCaptured then O.DiscardLastChange(historyLabel) end
            O.RefreshAll()
        end,
    })
end

-- Embedded in MSUF, colors open MSUF's own picker so the change joins its
-- history; the standalone window uses Blizzard's color picker.
local function OpenColorPicker(colorKey, card)
    local widgets = MenuWidgets()
    if IsEmbeddedCard(card) and O.embeddedHost:IsShown()
        and widgets and type(widgets.OpenContextColors) == "function" then
        local opened = widgets.OpenContextColors(card, {
            title = tostring(colorKey),
            targets = { ColorTarget(colorKey, tostring(colorKey)) },
            historyLabel = ColorHistoryLabel(colorKey),
            historySource = "suite:skin-color",
        })
        if opened then return end
    end
    OpenBlizzardColorPicker(colorKey)
end

local function FormatHex(color)
    return ("#%02X%02X%02X%02X"):format(
        math.floor((color[1] or 0) * 255 + 0.5),
        math.floor((color[2] or 0) * 255 + 0.5),
        math.floor((color[3] or 0) * 255 + 0.5),
        math.floor((color[4] or 1) * 255 + 0.5))
end

local function ParseHex(value, fallbackAlpha)
    value = tostring(value or ""):gsub("%s+", ""):gsub("^#", "")
    if #value ~= 6 and #value ~= 8 then return nil end
    local r = tonumber(value:sub(1, 2), 16)
    local g = tonumber(value:sub(3, 4), 16)
    local b = tonumber(value:sub(5, 6), 16)
    local a = #value == 8 and tonumber(value:sub(7, 8), 16) or math.floor((fallbackAlpha or 1) * 255 + 0.5)
    if not r or not g or not b or not a then return nil end
    return r / 255, g / 255, b / 255, a / 255
end

local function CreateSwatch(row, colorKey)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(52, 24)
    swatch:SetPoint("RIGHT", -10, 0)
    NS.Surface.SkinOwnedButton(swatch, {
        role = "input",
        shape = "continuous",
        radius = 4,
        border = 1,
        useControlShape = false,
    })
    local color = swatch:CreateTexture(nil, "BACKGROUND", nil, -6)
    color:SetPoint("TOPLEFT", 4, -4)
    color:SetPoint("BOTTOMRIGHT", -4, 4)
    swatch:SetScript("OnClick", function() OpenColorPicker(colorKey, row) end)
    return color
end

function O.CreateColorRow(parent, colorKey, labelText, width, description)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 600, 50)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("TOPLEFT", 12, -8)

    local help = O.CreateText(row, description or colorKey, 9, "dim")
    help:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    help:SetPoint("RIGHT", -250, 0)

    local input = CreateInputBox(row, 7)
    input:SetSize(126, 24)
    input:SetPoint("RIGHT", -72, 0)

    local color = CreateSwatch(row, colorKey)
    local widgets = MenuWidgets()
    if IsEmbeddedCard(row) and widgets and type(widgets.AttachContextColorShortcut) == "function" then
        widgets.AttachContextColorShortcut(row, {
            title = tostring(labelText),
            offsetX = -207,
            targets = { ColorTarget(colorKey, tostring(labelText)) },
            historyLabel = ColorHistoryLabel(colorKey),
            historySource = "suite:skin-color",
        })
    end

    local function CommitHex()
        local current = NS.Theme.GetColorTable(colorKey)
        local r, g, b, a = ParseHex(input:GetText(), current[4])
        if not r then
            input:SetText(FormatHex(current))
            return
        end
        local began = O.BeginUserChange(labelText)
        NS.Theme.SetColor(colorKey, r, g, b, a)
        if began then O.CommitUserChange(labelText) end
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", CommitHex)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatHex(NS.Theme.GetColorTable(colorKey)))
        self:ClearFocus()
    end)
    input:SetScript("OnEditFocusLost", CommitHex)

    local function Refresh()
        local tableColor = NS.Theme.GetColorTable(colorKey)
        color:SetColorTexture(tableColor[1], tableColor[2], tableColor[3], tableColor[4])
        if not input:HasFocus() then input:SetText(FormatHex(tableColor)) end
    end
    O.TrackRefresh(Refresh)
    Refresh()
    return row
end

function O.CreateSectionTitle(parent, titleText, description)
    local title = O.CreateText(parent, titleText, 20, "title")
    title:SetPoint("TOPLEFT", 4, -2)
    if description then
        local subtitle = O.CreateText(parent, description, 12, "muted")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
        subtitle:SetPoint("RIGHT", -8, 0)
        subtitle:SetJustifyV("TOP")
        return title, subtitle
    end
    return title
end
