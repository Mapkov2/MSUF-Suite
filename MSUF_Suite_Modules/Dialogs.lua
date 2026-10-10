local _, Private = ...
local S = Private.Suite

-- Suite-owned windows and the one copy dialog, shared by the Quality of Life
-- and Chat addons (both load after this runtime). C_OS.CopyToClipboard is
-- restricted, so a copy dialog only selects its text for Ctrl+C.

-- Text in a Suite-owned window; text is English source text.
function S.QoLLabel(parent, text, size)
    local label = S.CreateFontString(parent, nil, "ARTWORK")
    S.SetFont(label, nil, size or 12, "")
    label:SetText(S.Text(text))
    return label
end

-- A Suite-owned panel in UIParent with the windows' background and accent
-- line, clamped to the screen and taking the mouse.
local function SuitePanel(strata, name)
    local panel = S.CreateFrame("Frame", name, UIParent)
    panel:SetFrameStrata(strata)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    local background = S.CreateTexture(panel, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.065, .075, .085, .97)
    local accent = S.CreateTexture(panel, nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(.8, .68, .42, 1)
    return panel
end

-- A movable Suite-owned window with a title, a drag strip (panel.dragHandle)
-- and a close button (panel.close).
function S.QoLWindow(width, height, title, titleSize)
    local panel = SuitePanel("DIALOG")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetMovable(true)
    local drag = S.CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -32, 0)
    drag:SetHeight(38)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    local close = S.CreateFrame("Button", nil, panel)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -7, -7)
    S.QoLLabel(close, "X", 13):SetPoint("CENTER")
    close:SetScript("OnClick", function() panel:Hide() end)
    S.QoLLabel(panel, title, titleSize or 14):SetPoint("TOPLEFT", 14, -12)
    panel.dragHandle, panel.close = drag, close
    return panel
end

------------------------------------------------------------------ copy dialog
function S.QoLShowCopy(panel, text)
    panel.edit:SetText(text)
    panel:Show()
    panel.edit:SetFocus()
    panel.edit:HighlightText()
end

-- Also forgets the text and the chooser lines, so a closed dialog keeps
-- nothing it showed.
function S.QoLClearCopy(panel)
    panel:Hide()
    panel.edit:ClearFocus()
    panel.edit:SetText("")
    for _, row in ipairs(panel.rows) do
        row.message = nil
        row.label:SetText("")
        row:Hide()
    end
end

-- A chosen line goes into the edit box, selected for Ctrl+C.
local function ChooseRow(row)
    if not row.message then return end
    local edit = row.panel.edit
    edit:SetText(row.message)
    edit:SetFocus()
    edit:HighlightText()
end

-- Chooser lines under the hint: row i shows row.message (set by the caller).
local CHOOSER_TOP, ROW_HEIGHT, ROW_STEP, ROW_INSET = -61, 23, 25, 15
local ROW_SHADES = { "252a2d", "1d2225" }

local function AddRows(panel, width, count)
    for i = 1, count do
        local row = S.CreateFrame("Button", nil, panel)
        row.panel = panel
        row:SetSize(width - 2 * ROW_INSET, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", ROW_INSET, CHOOSER_TOP - (i - 1) * ROW_STEP)
        local shade = S.CreateTexture(row, nil, "BACKGROUND")
        shade:SetAllPoints(row)
        shade:SetColorTexture(S.RGB(ROW_SHADES[i % 2 + 1]))
        local label = S.CreateFontString(row, nil, "ARTWORK")
        S.SetFont(label, nil, 11, "")
        label:SetPoint("LEFT", row, "LEFT", 7, 0)
        label:SetWidth(width - 2 * ROW_INSET - 16)
        label:SetJustifyH("LEFT")
        label:SetMaxLines(1)
        row.label = label
        row:SetScript("OnClick", ChooseRow)
        row:Hide()
        panel.rows[i] = row
    end
end

-- A movable window with one edit box for text the player copies with Ctrl+C
-- (title and hint are English source text; panel.hint can be retitled).
-- options.rows adds that many chooser lines under the hint, a dialog of
-- options.height; the edit box then sits at the bottom. Closing or Escape
-- clears the dialog (S.QoLClearCopy).
function S.QoLCopyDialog(title, hint, width, options)
    local rows = options and options.rows or 0
    local panel = S.QoLWindow(width, options and options.height or 104, title)
    panel.rows = {}
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    panel.edit = edit
    local function Clear() S.QoLClearCopy(panel) end
    edit:SetScript("OnEscapePressed", Clear)
    panel.close:SetScript("OnClick", Clear)
    local hintLabel = S.QoLLabel(panel, hint, 11)
    panel.hint = hintLabel
    if rows > 0 then
        hintLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", ROW_INSET, -36)
        edit:SetSize(width - 40, 25)
        edit:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)
        AddRows(panel, width, rows)
    else
        hintLabel:SetPoint("BOTTOM", 0, 9)
        edit:SetSize(width - 54, 25)
        edit:SetPoint("TOP", panel, "TOP", 0, -45)
    end
    panel:Hide()
    return panel
end

------------------------------------------------------------------ Gamepad UI
-- WoW Forever's Gamepad UI. InputUtil.IsGamepadUIEnabled exists only there
-- (upstream/forever Blizzard_SharedXML/Mainline/InputUtil.lua; Retail 12.1.0
-- and 12.1.5 define none), so Retail never takes a Gamepad UI path. Under it
-- Blizzard's frame controls manager (Blizzard_GamepadSharedUtility/
-- FrameControlsManager.lua) follows every Blizzard panel, context menu and
-- static popup inside the call that opens it: ShowUIPanel's
-- BroadcastShowUIPanelEvent (UIParentPanelManager.lua), MenuProxy.OnShow
-- (Blizzard_Menu/Menu.lua) and the popup handler's PopupOpened callback
-- (Blizzard_StaticPopup/StaticPopupGamepad.lua, which also writes the
-- dialog's StaticPopupDialogs entry). Opened from addon code, it writes its
-- focus and binding state tainted; the binding change then calls the
-- protected SetPreferredGamepadInteractTarget (MainActionBarFrame.lua) and
-- the gamepad's spellbook casts stay blocked until a reload. Under the
-- Gamepad UI the Suite therefore opens Blizzard windows only through secure
-- clicks on Blizzard's own buttons (S.PanelButton, MicroMenu.lua) and shows
-- its menus and questions in its own list below.
function S.GamepadUI()
    local input = InputUtil
    return type(input) == "table" and input.IsGamepadUIEnabled ~= nil and input.IsGamepadUIEnabled() == true
end

------------------------------------------------------------------ pad list
-- The Suite's context menus and questions under the Gamepad UI (S.ContextMenu,
-- S.Confirm, S.AskText): the same entries, labels and callbacks in a
-- Suite-owned list, which the pad reaches through Classic MSUF's navigation
-- like every Suite window there (NS.Client.AttachControllerWindow; A picks,
-- B closes and declines a question), the cursor or the mouse. A host without
-- that navigation (Classic MSUF before it, Platform.lua) keeps Blizzard's
-- dialogs and menus, as before the list existed. A menu takes
-- the description calls the Suite's generators make (CreateTitle,
-- CreateButton with submenus, CreateCheckbox, CreateRadio, CreateDivider,
-- SetEnabled with a boolean, SetResponse); other description calls change
-- nothing. As in
-- Blizzard_Menu (Menu.lua Pick, MenuTemplates.lua), a pick closes the menu
-- unless its response is Refresh (a checkbox's default) or Open, which
-- rebuild it.
local PAD_WIDTH, PAD_ROW, PAD_INSET, PAD_INDENT = 260, 22, 8, 12
-- The list keeps this much of the screen free above and below itself.
local PAD_SCREEN_MARGIN = 40
local PICK_INPUT = { buttonName = "LeftButton" }
-- Dispatch(Finish, fn, ...) tells a raised callback (nothing) from its result.
local function Finish(callback, ...) return true, callback(...) end
local Element = {}
local function Ignore() end
local ElementMeta = { __index = function(_, key)
    return Element[key] or (type(key) == "string" and key:match("^%u") and Ignore or nil)
end }

local function AddElement(parent, kind, text, first, second, data)
    local element = setmetatable({ kind = kind, text = text, children = {} }, ElementMeta)
    if kind == "button" then
        element.callback, element.data = first, second
    elseif kind == "checkbox" or kind == "radio" then
        element.isSelected, element.callback, element.data = first, second, data
    end
    -- MenuTemplates.CreateCheckbox: SetResponse(MenuResponse.Refresh).
    if kind == "checkbox" then element.response = MenuResponse.Refresh end
    parent.children[#parent.children + 1] = element
    return element
end
function Element:CreateTitle(text) return AddElement(self, "title", text) end
function Element:CreateButton(text, callback, data) return AddElement(self, "button", text, callback, data) end
function Element:CreateCheckbox(text, isSelected, setSelected, data)
    return AddElement(self, "checkbox", text, isSelected, setSelected, data)
end
function Element:CreateRadio(text, isSelected, setSelected, data)
    return AddElement(self, "radio", text, isSelected, setSelected, data)
end
function Element:CreateDivider() return AddElement(self, "divider") end
function Element:CreateSpacer() return AddElement(self, "divider") end
function Element:SetEnabled(enabled) self.enabled = enabled end
function Element:SetResponse(response) self.response = response end

local function ElementEnabled(element)
    return element.enabled ~= false
end

-- MenuResponse (Blizzard_Menu/MenuConstants.lua, loaded at startup on every
-- client): Open and Refresh keep the menu.
local function KeepsMenu(response)
    return response ~= nil and (response == MenuResponse.Refresh or response == MenuResponse.Open)
end

local function Flatten(list, element, depth)
    for _, child in ipairs(element.children) do
        list[#list + 1] = { element = child, depth = depth }
        if #child.children > 0 then Flatten(list, child, depth + 1) end
    end
end

local function EntryLabel(element)
    local text = element.text or ""
    if element.kind == "checkbox" or element.kind == "radio" then
        local selected = element.isSelected and element.isSelected(element.data)
        local mark = element.kind == "checkbox" and (selected and "[x] " or "[  ] ") or (selected and "(o) " or "(  ) ")
        return mark .. text
    end
    return text
end

local function ScrollPad(scroll, delta)
    local range = math.max(0, scroll:GetVerticalScrollRange())
    scroll:SetVerticalScroll(math.max(0, math.min(range, scroll:GetVerticalScroll() - delta * PAD_ROW * 3)))
end

-- The rows sit in a scroll frame's child, the shape Classic MSUF's pad
-- navigation scrolls: it brings the selected row into view through the
-- row's parent ScrollFrame (ScrollIntoView, PadNavigation.lua) and scrolls
-- it with the right stick. The mouse wheel scrolls it too.
local function PadPanel(name)
    local panel = SuitePanel("FULLSCREEN_DIALOG", name)
    panel:SetWidth(PAD_WIDTH)
    local text = S.CreateFontString(panel, nil, "ARTWORK")
    S.SetFont(text, nil, 12, "")
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_INSET, -PAD_INSET - 2)
    text:SetWidth(PAD_WIDTH - 2 * PAD_INSET)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    local scroll = S.CreateFrame("ScrollFrame", nil, panel)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollPad)
    local child = S.CreateFrame("Frame", nil, scroll)
    child:SetWidth(PAD_WIDTH - 2 * PAD_INSET)
    scroll:SetScrollChild(child)
    panel.text, panel.rows, panel.entries, panel.scroll, panel.child = text, {}, {}, scroll, child
    panel:Hide()
    return panel
end

local PickPadRow
local function PadRow(panel, index)
    local row = panel.rows[index]
    if row then return row end
    row = S.CreateFrame("Button", nil, panel.child)
    row:SetHeight(PAD_ROW)
    row:RegisterForClicks("LeftButtonUp")
    local highlight = S.CreateTexture(row, nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetColorTexture(1, 1, 1, .12)
    local line = S.CreateTexture(row, nil, "ARTWORK")
    line:SetPoint("LEFT", row, "LEFT", 4, 0)
    line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, .18)
    local label = S.CreateFontString(row, nil, "OVERLAY")
    S.SetFont(label, nil, 12, "")
    label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.line, row.label, row.panel = line, label, panel
    row:SetScript("OnClick", function(self) PickPadRow(self) end)
    panel.rows[index] = row
    return row
end

-- entries[i] = { element, depth } for menus, { action, label } for questions.
-- The list below top shows as many rows as fit on the screen and scrolls
-- the rest; a rebuilt list keeps its scroll where it can.
local function FillPad(panel, entries, top)
    panel.entries = entries
    local scroll, child = panel.scroll, panel.child
    for index, entry in ipairs(entries) do
        local row, element = PadRow(panel, index), entry.element
        local kind = element and element.kind
        local clickable = entry.action ~= nil
            or (kind == "button" or kind == "checkbox" or kind == "radio") and element.callback ~= nil
            and ElementEnabled(element)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * PAD_ROW)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(index - 1) * PAD_ROW)
        row.line:SetShown(kind == "divider")
        row.label:SetShown(kind ~= "divider")
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 6 + (entry.depth or 0) * PAD_INDENT, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.label:SetText(element and EntryLabel(element) or entry.label)
        -- A submenu's own row heads its entries below it.
        local shade = (clickable or element and #element.children > 0) and 1 or .5
        if kind == "title" then row.label:SetTextColor(1, .82, 0) else row.label:SetTextColor(shade, shade, shade) end
        row:SetEnabled(clickable)
        row:Show()
    end
    for index = #entries + 1, #panel.rows do panel.rows[index]:Hide() end
    local fit = math.floor((UIParent:GetHeight() - 2 * PAD_SCREEN_MARGIN + top - PAD_INSET) / PAD_ROW)
    local shown = math.max(1, math.min(#entries, fit))
    child:SetHeight(math.max(1, #entries) * PAD_ROW)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_INSET, top)
    scroll:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_INSET, top)
    scroll:SetHeight(shown * PAD_ROW)
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), (#entries - shown) * PAD_ROW))
    panel:SetHeight(-top + shown * PAD_ROW + PAD_INSET)
end

-- The pad reaches the list through Classic MSUF's navigation (Platform.lua).
-- Runtime.lua sets Private.NS.
local function PadList()
    return S.GamepadUI() and Private.NS.Client.HasControllerNavigation()
end

local function TakePad(panel)
    local client = Private.NS.Client
    if not panel.padAttached then
        client.AttachControllerWindow(panel)
        panel.padAttached = true
    end
    client.ResumeControllerWindow(panel)
end

------------------------------------------------------------------ pad menus
local menuPanel

local function BuildPadMenu(panel)
    local root = setmetatable({ children = {} }, ElementMeta)
    local args = panel.args
    S.Dispatch(panel.generator, panel.owner, root, unpack(args, 1, args.n))
    local entries = {}
    Flatten(entries, root, 0)
    panel.text:SetText("")
    panel.text:Hide()
    FillPad(panel, entries, -PAD_INSET)
    return #entries
end

local function MenuClickAway(panel)
    local over = panel:IsMouseOver()
    if S.Public(over) and over == true then return end
    panel:Hide()
end

local function MenuPanel()
    if menuPanel then return menuPanel end
    menuPanel = PadPanel()
    menuPanel:SetScript("OnEvent", MenuClickAway)
    menuPanel:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self.generator, self.owner, self.args = nil, nil, nil
    end)
    return menuPanel
end

-- A Blizzard context menu (MenuUtil.CreateContextMenu, the generator gets
-- owner, the root description and the extra arguments), or the Suite's list
-- under the Gamepad UI, opened below owner. A menu that names no frame of its
-- own (nil or UIParent, whose bottom left is the screen's corner) opens in
-- the screen's centre, where the pad's list is found without a cursor.
function S.ContextMenu(owner, generator, ...)
    if not PadList() then return MenuUtil.CreateContextMenu(owner, generator, ...) end
    local panel = MenuPanel()
    if panel:IsShown() then panel:Hide() end
    panel.scroll:SetVerticalScroll(0)
    panel.owner, panel.generator, panel.args = owner, generator, { n = select("#", ...), ... }
    if BuildPadMenu(panel) == 0 then
        panel.generator, panel.owner, panel.args = nil, nil, nil
        return
    end
    panel:ClearAllPoints()
    if owner and owner ~= UIParent then
        panel:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    panel:Show()
    panel:RegisterEvent("GLOBAL_MOUSE_DOWN")
    TakePad(panel)
    return panel
end

-- As MenuElementDescriptionProxyMixin:Pick, a disabled entry never runs.
local function PickMenuRow(panel, element)
    if not element.callback or not ElementEnabled(element) then return end
    local response = element.response
    local ok, answer = S.Dispatch(Finish, element.callback, element.data, PICK_INPUT, nil)
    if ok and answer ~= nil then response = answer end
    if panel ~= menuPanel or not panel:IsShown() then return end
    if KeepsMenu(response) and panel.generator then
        BuildPadMenu(panel)
    else
        panel:Hide()
    end
end

------------------------------------------------------------------ pad questions
-- One question at a time. The labels and the answers follow Blizzard's
-- generic confirmation and input box (GameDialogDefs.lua): YES/NO and
-- DONE/CANCEL by default, the input box answers only with text, the callback
-- gets it. Blizzard's generic dialogs show several questions at once; here a
-- new question declines the shown one (its cancelCallback runs), so no
-- caller waits for an answer that never comes. Escape declines as on
-- Blizzard's dialogs (hideOnEscape, StaticPopup_EscapePressed runs OnCancel):
-- the panel is in UISpecialFrames, which Blizzard's CloseSpecialWindows walks
-- through securecall (UIParentPanelManager.lua), also while the edit box has
-- no focus and the pad's navigation does not hold the list (combat, or a
-- Blizzard panel holding SmartNavigation). S.HideQuestion closes the question
-- unanswered, as StaticPopup_Hide does.
local QUESTION_NAME = "MSUFSuitePadQuestion"
local questionPanel

-- Ends the question on panel: hides it, runs the caller's onHide and clears
-- the box; declined runs its cancelCallback. Everything runs here, not in
-- OnHide, which a Hide while the UI is hidden (Alt+Z) does not fire.
local function EndQuestion(panel, declined)
    local data, onHide = panel.question, panel.onHide
    if not data then return end
    panel.question, panel.input, panel.onHide = nil, nil, nil
    panel:Hide()
    panel.edit:ClearFocus()
    if onHide then S.Dispatch(onHide, panel) end
    panel.edit:SetText("")
    if declined and data.cancelCallback then S.Dispatch(data.cancelCallback) end
end

local function QuestionPanel()
    if questionPanel then return questionPanel end
    local panel = PadPanel(QUESTION_NAME)
    UISpecialFrames[#UISpecialFrames + 1] = QUESTION_NAME
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetSize(PAD_WIDTH - 2 * PAD_INSET - 10, 24)
    edit:SetScript("OnEnterPressed", function() panel:Answer(true) end)
    edit:SetScript("OnEscapePressed", function() panel:Answer(false) end)
    edit:Hide()
    panel.edit = edit
    -- The caller presets and restores the box as on Blizzard's dialog frame.
    function panel:GetEditBox() return self.edit end
    -- B in Classic MSUF's navigation runs a window's own Close (declines).
    function panel:Close() self:Answer(false) end
    function panel:Answer(accepted)
        local data, input = self.question, self.input
        if not data then return end
        local text = input and self.edit:GetText() or nil
        if accepted and input and (type(text) ~= "string" or text == "") then return end
        EndQuestion(self, not accepted)
        if accepted then S.Dispatch(data.callback, text) end
    end
    -- Hidden by someone else while unanswered (Escape through
    -- UISpecialFrames): declined. A hidden UI (Alt+Z) keeps the question, as
    -- Blizzard's dialog does.
    panel:SetScript("OnHide", function(self)
        if not self:IsShown() then EndQuestion(self, true) end
    end)
    questionPanel = panel
    return panel
end

local function PadAnswer(row) row.panel:Answer(row.entry.action == "accept") end

local function OpenPadQuestion(data, input, onHide)
    local panel = QuestionPanel()
    EndQuestion(panel, true)
    panel.question, panel.input, panel.onHide = data, input, onHide
    panel.text:Show()
    panel.text:SetFormattedText(data.text or "", data.text_arg1, data.text_arg2)
    local height = panel.text:GetStringHeight()
    local top = -PAD_INSET - 6 - (type(height) == "number" and height or PAD_ROW)
    local edit = panel.edit
    edit:SetShown(input == true)
    if input then
        edit:SetMaxLetters(data.maxLetters or 24)
        edit:SetText("")
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_INSET + 6, top - 2)
        top = top - 30
    end
    FillPad(panel, {
        { action = "accept", label = data.acceptText or input and DONE or YES },
        { action = "cancel", label = data.cancelText or input and CANCEL or NO },
    }, top)
    panel:ClearAllPoints()
    panel:SetPoint("TOP", UIParent, "TOP", 0, -135)
    panel:Show()
    TakePad(panel)
    return panel
end

local function HidePadQuestion(data)
    if questionPanel and questionPanel.question == data then EndQuestion(questionPanel, false) end
end

function PickPadRow(row)
    local entry = row.entry
    if not entry then return end
    if entry.action then
        PadAnswer(row)
    elseif entry.element then
        PickMenuRow(row.panel, entry.element)
    end
end

------------------------------------------------------------------ Blizzard dialogs
-- A question in one of Blizzard's dialog frames. StaticPopupDialogs is
-- Blizzard's table, read by its own dialog code, so the Suite adds no entry
-- to it: Blizzard's generic confirmation and input box take the text, the
-- button labels and the callbacks as data (Blizzard_StaticPopup/
-- StaticPopup.lua StaticPopup_ShowCustomGenericConfirmation and
-- StaticPopup_ShowCustomGenericInputBox, Blizzard_StaticPopup_Game/
-- GameDialogDefs.lua; the same on upstream/live and upstream/forever).
--   data.text           a format string for data.text_arg1 and text_arg2
--   data.acceptText     the accept label; data.cancelText the cancel label
--   data.callback       runs on accept (the input box passes its text)
--   data.cancelCallback runs on cancel
--   data.showAlert      the confirmation's alert icon
--   data.maxLetters     the input box's limit (Blizzard's default is 24)
-- Both generic dialogs allow several at a time; a question replaces the
-- earlier one under the same key, as one dialog of its own did. They also
-- show while the player is dead; the Suite asks only from merchant and
-- trainer windows, which close then. Under the Gamepad UI (on a host with
-- the pad's navigation) the question is the Suite's own (pad questions
-- above): Blizzard's popup handler would
-- write the shared GENERIC_CONFIRMATION and GENERIC_INPUT_BOX entries and
-- the frame controls manager in the Suite's call.
local GENERIC_CONFIRMATION, GENERIC_INPUT_BOX, PAD = "GENERIC_CONFIRMATION", "GENERIC_INPUT_BOX", "pad"
local askedWhich, askedData = {}, {}

-- Closes the question under key, if it is still shown; nothing else.
function S.HideQuestion(key)
    local data = askedData[key]
    if not data then return end
    if askedWhich[key] == PAD then HidePadQuestion(data) else StaticPopup_Hide(askedWhich[key], data) end
    askedWhich[key], askedData[key] = nil, nil
end

function S.Confirm(key, data)
    S.HideQuestion(key)
    if PadList() then
        OpenPadQuestion(data, false)
        askedWhich[key], askedData[key] = PAD, data
        return
    end
    StaticPopup_ShowCustomGenericConfirmation(data)
    askedWhich[key], askedData[key] = GENERIC_CONFIRMATION, data
end

-- StaticPopup_ShowCustomGenericInputBox(data) is StaticPopup_Show for the
-- generic input box; called directly, StaticPopup_Show also returns the
-- dialog, so the caller can preset its edit box, and runs onHide(dialog)
-- (its customOnHideScript) however the dialog closes, to undo such presets
-- on the shared dialog frame.
function S.AskText(key, data, onHide)
    S.HideQuestion(key)
    if PadList() then
        askedWhich[key], askedData[key] = PAD, data
        return OpenPadQuestion(data, true, onHide)
    end
    local dialog = StaticPopup_Show(GENERIC_INPUT_BOX, nil, nil, data, nil, onHide)
    if dialog then askedWhich[key], askedData[key] = GENERIC_INPUT_BOX, data end
    return dialog
end
