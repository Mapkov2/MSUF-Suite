local _, Private = ...
local NS, O = Private.NS, Private.Options

-- Shared widget parts: buttons, row layout, the history and refresh glue,
-- the popup combat watcher and the value rows without a popup (toggle,
-- cycle, segmented). Dropdowns (WidgetsDropdown.lua), slider and text rows
-- (WidgetsInput.lua) and color rows (WidgetsColor.lua) load after this file
-- and take its private helpers from Private.Widgets.

local DISABLED_ALPHA = 0.52

local function PlayClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Settings never change in combat. Every widget change and every setting
-- button asks here first.
local function CanChange()
    return not NS.IsCombatLocked()
end

-- The last color painted on one widget part: `last` is that part's own table
-- (made once); true when r, g, b, a differ and were stored.
local function ColorChanged(last, r, g, b, a)
    if last[1] == r and last[2] == g and last[3] == b and last[4] == a then return false end
    last[1], last[2], last[3], last[4] = r, g, b, a
    return true
end

------------------------------------------------------------------ buttons
-- One shared click handler; each button carries its own callback. A setting
-- button (O.CreateSettingButton) does nothing in combat but tell its page.
local function ButtonClick(self, mouseButton)
    if self.disabledByOptions then return end
    if self.changesSettings and not CanChange() then
        local refused = self.optionsRefused
        if refused then refused(self, "combat") end
        return
    end
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

-- A button whose callback changes settings (reset, profiles, undo, and the
-- value buttons of cycles, segmented rows and dropdowns). In combat a click
-- is refused before the click sound plays; refused(button, reason),
-- optional, reports it.
function O.CreateSettingButton(parent, text, width, height, callback, role, refused)
    local button = O.CreateButton(parent, text, width, height, callback, role)
    button.changesSettings = true
    button.optionsRefused = refused
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

-- A label shows "disabled" while its button is disabled, else its active
-- state (title or muted) once one was set, else the normal text color. The
-- active and the enabled state are set independently and in any order.
local function PaintButtonLabel(button, state)
    if not state or not state.label then return end
    local colorKey = "text"
    if button.disabledByOptions then
        colorKey = "disabled"
    elseif state.active ~= nil then
        colorKey = state.active and "title" or "muted"
    end
    O.SetTextColor(state.label, colorKey)
end

function O.SetButtonActive(button, active)
    NS.Surface.SetActive(button, active)
    local state = O.widgetStates[button]
    if state then state.active = active == true end
    PaintButtonLabel(button, state)
end

function O.SetButtonEnabled(button, enabled)
    enabled = enabled == true
    button.disabledByOptions = not enabled
    button:EnableMouse(enabled)
    PaintButtonLabel(button, O.widgetStates[button])
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

-- The scrolling left column of a page with a preview on the right: below
-- the page title, down to the bottom. Returns the scroll frame and its
-- content (see O.CreateScrollContainer).
function O.CreateLeftColumn(page, hostWidth, contentHeight, contentWidth)
    local host = CreateFrame("Frame", nil, page)
    host:SetPoint("TOPLEFT", 4, -70)
    host:SetPoint("BOTTOMLEFT", 4, 4)
    host:SetWidth(hostWidth)
    return O.CreateScrollContainer(host, contentHeight, contentWidth)
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

-- A thin accent thumb on an ink track, shared by the dropdown and the page
-- scroll containers.
function O.CreateScrollThumb(slider, thumbHeight)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(NS.Theme.GetColor("ink"))
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, thumbHeight)
    thumb:SetTexture(NS.path .. "Media\\Shapes\\pill_h24_fill.png")
    thumb:SetTextureSliceMargins(12, 0, 12, 0)
    thumb:SetVertexColor(NS.Theme.GetColor("accent"))
    slider:SetThumbTexture(thumb)
    return track, thumb
end

-- The text field of the dropdown search, text rows and color rows.
local function CreateInputBox(parent, insets)
    local input = CreateFrame("EditBox", nil, parent)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetTextInsets(insets, insets, 0, 0)
    NS.Surface.Attach(input, { role = "input", shape = "continuous", radius = 4, border = 1 })
    return input
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

------------------------------------------------------------------ history and refresh glue
-- nil refuses the change (combat); false starts it without a history entry.
local function BeginWidgetChange(labelText, options)
    if not CanChange() then return nil end
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

-- Tracks a refresher (see O.TrackRefresh) and paints with it once now.
function O.TrackAndRefresh(refresh)
    O.TrackRefresh(refresh)
    refresh()
end

------------------------------------------------------------------ combat
-- Popups that capture the mouse (the dropdown blocker covers the screen) or
-- edit a color close when combat starts. PLAYER_REGEN_DISABLED fires before
-- the lockdown begins, so a cancelled color is still restored. The event is
-- registered only while such a popup is open.
-- dropdown: the dropdown is open; pickerCancel: the cancel of our open
-- color picker. Each popup's file adds the function that closes it
-- (CloseOnCombat), in TOC order.
local popups = { dropdown = false }
local combatClosers = {}
local combatWatcher = CreateFrame("Frame")

local function WatchCombat()
    if popups.dropdown or popups.pickerCancel then
        combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    else
        combatWatcher:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
end

local function CloseOnCombat(close)
    combatClosers[#combatClosers + 1] = close
end

combatWatcher:SetScript("OnEvent", function()
    for index = 1, #combatClosers do
        combatClosers[index]()
    end
    WatchCombat()
end)

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

    local painted
    local function Refresh()
        local enabled = getter() == true
        if enabled == painted then return end
        painted = enabled
        NS.Surface.SetActive(track, enabled)
        knob:ClearAllPoints()
        if enabled then
            knob:SetPoint("RIGHT", track, "RIGHT", -4, 0)
        else
            knob:SetPoint("LEFT", track, "LEFT", 4, 0)
        end
        O.SetTextColor(label, enabled and "text" or "muted")
    end
    O.TrackAndRefresh(Refresh)

    button:SetScript("OnClick", function()
        local began = BeginWidgetChange(labelText, options)
        if began == nil then return end
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

-- options: history = false; refused(button, reason) reports a click refused
-- in combat.
function O.CreateCycle(parent, labelText, values, getter, setter, width, formatter, options)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(width or 520, 42)
    local label = O.CreateText(row, labelText, 12, "text")
    label:SetPoint("LEFT", 12, 0)

    local valueButton = O.CreateSettingButton(row, "", 180, 28, function()
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
        if began == nil then return end
        setter(nextValue)
        CommitWidgetChange(labelText, options, began)
    end, nil, options and options.refused)
    valueButton:SetPoint("RIGHT", -8, 0)
    local valueLabel = O.widgetStates[valueButton].label

    local painted, hasPainted = nil, false
    O.TrackAndRefresh(function()
        local value = getter()
        if hasPainted and value == painted then return end
        painted, hasPainted = value, true
        valueLabel:SetText(formatter and formatter(value) or tostring(value))
    end)
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
        local button = O.CreateSettingButton(row, formatter and formatter(value) or tostring(value),
            buttonWidth, 28, function()
                if getter() == value then return end
                local began = BeginWidgetChange(labelText, options)
                if began == nil then return end
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

    local painted, hasPainted = nil, false
    O.TrackAndRefresh(function()
        local selected = getter()
        if hasPainted and selected == painted then return end
        painted, hasPainted = selected, true
        for index = 1, #available do
            O.SetButtonActive(buttons[index], available[index] == selected)
        end
    end)
    row.segmentButtons = buttons
    return row
end

-- Private to the widget files that load next (TOC order).
Private.Widgets = {
    CanChange = CanChange,
    ColorChanged = ColorChanged,
    BeginWidgetChange = BeginWidgetChange,
    CommitWidgetChange = CommitWidgetChange,
    CreateInputBox = CreateInputBox,
    popups = popups,
    WatchCombat = WatchCombat,
    CloseOnCombat = CloseOnCombat,
}
