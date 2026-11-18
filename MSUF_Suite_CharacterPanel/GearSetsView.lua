local _, NS = ...
local Actions, Layout = NS.GearActions, NS.GroupLayout
local SetView = {}
NS.GearSetsView = SetView

local INSET, GAP, BUTTON, START = 8, 5, 27, 64
local ICON_TILE, ICON_GAP = 28, 5
local ROW, STEP, ICON = 33, 36, 24
local UNKNOWN_ICON = 134400
local MISSING = { .92, .44, .40 }

local function Enabled(button, enabled)
    if button.setEnabled == enabled then return end
    button.setEnabled = enabled
    button:SetEnabled(enabled)
    button:SetAlpha(enabled and 1 or .55)
end

local function PaintControls(pane)
    local list = pane.list
    local selected = list.session.selected
    list.style.Visible(pane.selectedActions, selected ~= nil)
    Enabled(pane.equip, selected ~= nil and selected.equipped == false)
end

local PaintRows
local function ClickRow(button, mouse)
    local list = button.list
    if not list.session or not button.set then return end
    Actions.Select(list.session, button.set)
    PaintControls(list.pane)
    PaintRows(list, list.rowOffset)
    if mouse == "RightButton" then Actions.Manage(button, list.session, button.set) end
end

local function EquipRow(button, mouse)
    local session = button.list.session
    if mouse == "LeftButton" and session and button.set then Actions.Equip(session, button.set) end
end

local function PickupRow(button)
    local session = button.list.session
    if session and button.set then Actions.Pickup(session, button.set) end
end

local function RowTooltip(row)
    if not row.list.session or not row.set then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetEquipmentSet(row.set.id)
end

local function ReleaseTooltip(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function NewRow(list)
    local view, style = list.view, list.style
    local row = style.Row(view, list.canvas)
    row.list = list
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnClick", ClickRow)
    row:SetScript("OnDoubleClick", EquipRow)
    row:SetScript("OnDragStart", PickupRow)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", ReleaseTooltip)
    row:SetScript("OnHide", ReleaseTooltip)
    row.selection = style.Fill(view, row, "ARTWORK", style.selected, 1)
    row.icon = style.Texture(row, nil, "OVERLAY")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 4, 0)
    row.label = style.Font(view, row, 12, style.text)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -22, 0)
    row.check = style.Texture(row, nil, "OVERLAY")
    row.check:SetTexture("Interface\Buttons\UI-CheckBox-Check")
    row.check:SetSize(17, 17)
    row.check:SetPoint("RIGHT", -3, 0)
    return row
end

function PaintRows(list, offset)
    local session, style, pool = list.session, list.style, list.buttons
    if not session then return end
    list.rowOffset = offset
    local first = math.floor(offset / STEP) + 1
    local last = math.min(#session.rows, math.ceil((offset + list.height) / STEP))
    for i = first, last do
        local index = i - first + 1
        local row, data = pool[index], session.rows[i]
        if not row then
            row = NewRow(list)
            pool[index] = row
        end
        if row.setID ~= nil and row.setID ~= data.id then ReleaseTooltip(row) end
        row.set, row.setID = data, data.id
        local file = data.icon or UNKNOWN_ICON
        if row.file ~= file then
            row.file = file
            row.icon:SetTexture(file)
        end
        local color = data.missing and data.missing > 0 and MISSING or style.text
        if row.color ~= color then
            row.color = color
            style.Tint(list.view, row.label, color, true)
        end
        style.Text(row.label, data.name)
        style.Place(row, 0, (i - 1) * STEP, list.width, ROW)
        style.Visible(row.selection, session.selectedID == data.id)
        style.Visible(row.check, data.equipped)
        style.Visible(row, true)
    end
    for i = last - first + 2, #pool do
        pool[i].set = nil
        style.Visible(pool[i], false)
    end
end

local function Button(view, parent, style, text, action)
    local button, label = style.Button(view, parent, text, action)
    Layout.Wrap(label)
    label:SetMaxLines(2)
    return button, label
end

local function SelectedButton(pane, text, action)
    local list = pane.list
    return Button(list.view, pane.selectedActions, list.style, text, function(button)
        local session = list.session
        if session and session.selected then action(button, session, session.selected) end
    end)
end

local function CloseEditor(editor)
    if not editor.entry then return end
    Actions.ReleaseEditor(editor.entry)
    editor.entry = nil
    editor.input:ClearFocus()
    editor.style.Visible(editor, false)
    editor.style.Visible(editor.pane.main, true)
end

local function NameChanged(editor)
    local valid = Actions.EditorName(editor.input:GetText()) ~= nil
    Enabled(editor.accept, valid)
    editor.style.Text(editor.error, "")
end

local function AcceptEditor(editor)
    if not editor.entry then return end
    local saved, reason = Actions.SubmitEditor(editor.entry, editor.input:GetText(), editor.icon)
    if saved then CloseEditor(editor)
    elseif reason then editor.style.Text(editor.error, reason) end
end

local function PickIcon(button)
    local editor = button.editor
    editor.icon = button.fileID
    for _, tile in ipairs(editor.icons) do
        editor.style.Visible(tile.mark, tile.fileID == editor.icon)
    end
end

local function AddIcon(editor, file, index)
    local view, style = editor.pane.list.view, editor.style
    local tile = editor.icons[index]
    if not tile then
        tile = style.Row(view, editor)
        tile.editor = editor
        tile:SetScript("OnClick", PickIcon)
        tile.image = style.Texture(tile, nil, "ARTWORK")
        tile.image:SetPoint("TOPLEFT", 2, -2)
        tile.image:SetPoint("BOTTOMRIGHT", -2, 2)
        tile.mark = style.Fill(view, tile, "BACKGROUND", style.accent, 1)
        editor.icons[index] = tile
    end
    tile.fileID = file
    tile.image:SetTexture(file)
    local step = ICON_TILE + ICON_GAP
    local columns = math.floor((style.width - 2 * INSET + ICON_GAP) / step)
    local row, column = math.floor((index - 1) / columns), (index - 1) % columns
    style.Place(tile, INSET + column * step, 115 + row * step, ICON_TILE, ICON_TILE)
    style.Visible(tile, true)
    style.Visible(tile.mark, editor.icon == file)
end

local function PaintIcons(editor, entry)
    editor.icon = entry.icon or UNKNOWN_ICON
    AddIcon(editor, editor.icon, 1)
    local count = 1
    if editor.icon ~= UNKNOWN_ICON then
        count = 2
        AddIcon(editor, UNKNOWN_ICON, count)
    end
    for _, icon in ipairs(entry.icons) do
        if icon.id ~= editor.icon and icon.id ~= UNKNOWN_ICON then
            count = count + 1
            AddIcon(editor, icon.id, count)
        end
    end
    for i = count + 1, #editor.icons do editor.style.Visible(editor.icons[i], false) end
end

local function EditorLabel(view, editor, text, y, color)
    local style = editor.style
    local label = style.Font(view, editor, 12, color)
    label:SetPoint("TOPLEFT", INSET, -y)
    label:SetPoint("RIGHT", -INSET, 0)
    Layout.Wrap(label)
    label:SetMaxLines(2)
    style.Text(label, text)
    return label
end

local function EditorInput(view, editor, available)
    local style = editor.style
    local input = style.Input(view, editor)
    input:SetFontObject("ChatFontNormal")
    NS.Suite.SetFont(input, view.fontPath, 13, "")
    view.fonts[input] = 13
    style.Tint(view, input, style.text, true)
    input:SetAutoFocus(false)
    input:SetMaxLetters(16)
    input:SetTextInsets(7, 7, 0, 0)
    input:SetScript("OnTextChanged", function() NameChanged(editor) end)
    input:SetScript("OnEnterPressed", function() AcceptEditor(editor) end)
    input:SetScript("OnEscapePressed", function() CloseEditor(editor) end)
    style.Place(input, INSET, 67, available, BUTTON)
    return input
end

local function NewEditor(pane)
    local view, style = pane.list.view, pane.list.style
    local editor = NS.Window.CreateChild(view, "Frame", pane)
    editor:SetAllPoints()
    editor:SetScript("OnHide", CloseEditor)
    editor.pane, editor.style, editor.icons = pane, style, {}
    local available = style.width - 2 * INSET
    local half = (available - GAP) / 2
    editor.title = EditorLabel(view, editor, "", 30, style.title)
    EditorLabel(view, editor, NS.Text("Equipment set name"), 50, style.text)
    EditorLabel(view, editor, NS.Text("Set icon"), 98, style.text)
    editor.input = EditorInput(view, editor, available)
    editor.error = EditorLabel(view, editor, "", style.height - 68, MISSING)
    editor.slots = Button(view, editor, style, NS.Text("Ignored equipment slots"), function(button)
        if editor.entry then Actions.NewSlots(button, editor.entry) end
    end)
    style.Place(editor.slots, INSET, style.height - 104, available, BUTTON)
    editor.accept = Button(view, editor, style, NS.String(SAVE) or NS.Text("Save current equipment"), function()
        AcceptEditor(editor)
    end)
    local cancel = Button(view, editor, style, NS.Text("Cancel"), function() CloseEditor(editor) end)
    style.Place(editor.accept, INSET, style.height - INSET - BUTTON, half, BUTTON)
    style.Place(cancel, INSET + half + GAP, style.height - INSET - BUTTON, half, BUTTON)
    return editor
end

local function OpenEditor(pane, row)
    local list = pane.list
    if not list.session then return end
    local entry = Actions.BeginEditor(list.session, row)
    if not entry then return end
    local style = list.style
    local editor = pane.editor or NewEditor(pane)
    pane.editor = editor
    editor.entry = entry
    local title = row and (NS.String(EQUIPMENT_SET_EDIT) or NS.Text("Edit"))
        or NS.String(PAPERDOLL_NEWEQUIPMENTSET) or NS.Text("New equipment set")
    style.Text(editor.title, title)
    style.Visible(editor.slots, row == nil)
    PaintIcons(editor, entry)
    editor.input:SetText(entry.name or "")
    NameChanged(editor)
    style.Visible(pane.main, false)
    style.Visible(editor, true)
    editor.input:SetFocus()
    if entry.name then editor.input:HighlightText() end
end

local function SetButtons(pane, available)
    local list = pane.list
    local style = list.style
    local actions = NS.Window.CreateChild(list.view, "Frame", pane.main)
    actions:SetAllPoints()
    pane.selectedActions = actions
    local half = (available - GAP) / 2
    pane.equip = SelectedButton(pane, NS.String(EQUIPSET_EQUIP) or "Equip", function(_, session, row) Actions.Equip(session, row) end)
    pane.save = SelectedButton(pane, NS.String(SAVE) or NS.Text("Save current equipment"), function(_, session, row) Actions.Save(session, row) end)
    pane.slots = SelectedButton(pane, NS.Text("Ignored equipment slots"), Actions.EditSlots)
    pane.manage = SelectedButton(pane, NS.Text("Manage equipment sets"), Actions.Manage)
    local edit = SelectedButton(pane, NS.String(EQUIPMENT_SET_EDIT) or NS.Text("Edit"), function(_, _, row) OpenEditor(pane, row) end)
    pane.edit = edit
    style.Place(pane.equip, INSET, 29, half, BUTTON)
    style.Place(pane.save, INSET + half + GAP, 29, half, BUTTON)
    local last = style.height - INSET - BUTTON
    style.Place(pane.slots, INSET, last - BUTTON - GAP, available, BUTTON)
    local editWidth = 70
    style.Place(edit, INSET, last, editWidth, BUTTON)
    style.Place(pane.manage, INSET + editWidth + GAP, last, available - editWidth - GAP, BUTTON)
end

local function NewPane(view, parent, style)
    local pane = style.Panel(view, parent)
    pane:SetPoint("TOPRIGHT")
    pane:SetSize(style.width, style.height)
    pane.parent = parent

    local title = style.Font(view, pane, 13, style.text)
    title:SetPoint("TOPLEFT", INSET, -INSET)
    title:SetPoint("RIGHT", -INSET, 0)
    style.Text(title, NS.Text("Equipment sets"))

    local main = NS.Window.CreateChild(view, "Frame", pane)
    main:SetAllPoints()
    pane.main = main
    style.Visible(main, true)
    local available = style.width - 2 * INSET
    local height = style.height - START - 3 * BUTTON - 3 * GAP - INSET
    local list = Layout.NewList(view, main, available, height, 1, PaintRows)
    pane.list, list.pane, list.style, list.buttons = list, pane, style, {}
    list.scroll:SetPoint("TOPLEFT", INSET, -START)
    if list.thumb then style.Tint(view, list.thumb, style.accent) end
    local blank = style.Font(view, main, 11, style.muted)
    blank:SetPoint("TOPLEFT", INSET, -29)
    blank:SetPoint("RIGHT", -INSET, 0)
    Layout.Wrap(blank)
    blank:SetMaxLines(2)
    style.Text(blank, NS.Text("No saved equipment sets"))
    pane.blank = blank
    local new, label = Button(view, main, style, NS.String(PAPERDOLL_NEWEQUIPMENTSET) or NS.Text("New equipment set"), function()
        OpenEditor(pane)
    end)
    pane.new = new
    style.Visible(new, true)
    style.Tint(view, label, style.title, true)
    SetButtons(pane, available)
    return pane
end

local function PaintPane(pane, session, style)
    local list = pane.list
    local reset = list.session ~= session
    if not reset and pane.revision == session.revision then return end
    if reset and pane.editor then CloseEditor(pane.editor) end
    list.session, pane.revision = session, session.revision
    local count = #session.rows
    local content = math.max(1, count * STEP - GAP)
    PaintRows(list, Layout.UpdateScroll(list, content, reset))
    style.Visible(pane.blank, count == 0)
    local y = count == 0 and 56 or START + math.min(content, list.height) + GAP
    style.Place(pane.new, INSET, y, style.width - 2 * INSET, BUTTON)
    Enabled(pane.new, session.canCreate)
    PaintControls(pane)
end

local function HidePane(view, style)
    local pane = view.setPane
    if not pane then return end
    if pane.editor then CloseEditor(pane.editor) end
    style.Visible(pane, false)
    pane.list.session = nil
end

function SetView.ShowList(list, fixed, groups, reset, combat, style)
    local view, show = list.view, style.Visible
    local rail, session = list == view.rail, not combat and list.view.setManager
    if rail and view.detailSlot then session = nil end
    local split = view.setReport
    if rail or not session then
        if split then show(split.scroll, false) end
    end
    if not session then
        HidePane(view, style)
        return Layout.ShowList(list, fixed, groups, reset, combat, show)
    end
    show(list.scroll, false)
    if fixed then show(fixed.canvas, false) end

    local pane = view.setPane or NewPane(view, list.parent, style)
    view.setPane = pane
    if pane.parent ~= list.parent then
        pane.parent = list.parent
        pane:SetParent(list.parent)
        pane:ClearAllPoints()
        pane:SetPoint("TOPRIGHT")
    end
    if not rail then
        if not split then
            split = Layout.NewList(view, list.parent, view.bodyWidth - style.width - style.gap, list.height, list.columns, list.paint)
            view.setReport = split
            if split.thumb then style.Tint(view, split.thumb, style.accent) end
        end
        Layout.ShowList(split, nil, groups, reset or not split.scroll.panelShown, false, show)
    end
    PaintPane(pane, session, style)
    show(pane, true)
    return fixed
end
