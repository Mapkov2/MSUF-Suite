local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Tools = {}
S.ToolListWindow = Tools
local PAGE_ROWS, ROW_HEIGHT = 12, 27
local current, editor
local EDITOR_FONTS = { title = 14, hint = 12, input = 12, error = 11 }
local fonts = {}
local Restyle

local function Theme()
    return NS.HostBridge
end

local function Label(parent, text, size)
    local label = S.QoLLabel(parent, text or "", size or 12)
    label:SetJustifyH("LEFT")
    fonts[label] = size or 12
    return label
end

local function Button(parent, text, width, action)
    local bridge = Theme()
    local button = bridge and bridge.MenuButton(parent, width, 28)
        or S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 28)
    button:SetText(S.Text(text))
    button:SetScript("OnClick", action)
    return button
end

local function ButtonFont(button)
    local bridge = Theme()
    return bridge and bridge.MenuButtonLabel(button) or button:GetFontString()
end

local function Window(width, height)
    local bridge = Theme()
    if not bridge or not bridge.EnsureMenuTheme() then return S.QoLWindow(width, height, "") end
    local panel = S.CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel.toolModern = true
    panel:SetSize(width, height)
    panel:SetPoint("CENTER", UIParent, "CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    local drag = S.CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -40, 0)
    drag:SetHeight(36)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    panel.dragHandle = drag
    panel.close = bridge.MenuCloseButton(panel) or Button(panel, "X", 24)
    panel.close:SetPoint("TOPRIGHT", -10, -8)
    panel.close:SetScript("OnClick", function() panel:Hide() end)
    panel.close.caption = bridge.MenuButtonLabel(panel.close)
    bridge.MenuMaterial(panel, "shell")
    bridge.MenuAtmosphere(panel)
    return panel
end

local function PaintRow(button, row, selected)
    if button.toolModern then
        button:SetActive(selected)
        button:SetEnabled(not row.disabled)
    else
        button.text:SetTextColor(row.disabled and .55 or .92, row.disabled and .55 or .94, row.disabled and .55 or .97)
        button.fill:SetColorTexture(.2, .36, .46, selected and .85 or .18)
    end
end

local function Valid(window)
    return window.owner and window.profile == NS.DB and not NS.InCombat()
        and window.owner.active ~= false and (not window.spec.valid or window.spec.valid(window.owner))
end

-- Only a row the search leaves in the list counts: details and actions never act on a hidden one.
local function Selected(window)
    if not Valid(window) then return nil end
    for i = 1, #window.filtered do
        local row = window.filtered[i]
        if row.key == window.selected then return row end
    end
end

local function RunAction(button)
    local window = current
    if not window or not Valid(window) then return end
    window:Refresh()
    if not Valid(window) then return end
    local action, row = window.spec.actions and window.spec.actions[button.index], window:Selected()
    if action and (not action.enabled or action.enabled(window.owner, row)) then action.run(window.owner, row, window) end
end

local function RowClicked(button, mouse)
    local window = current
    if not window or not Valid(window) then return end
    local row = window.filtered[window.offset + button.index]
    if not row or row.disabled then return end
    window.selected = row.key
    if mouse == "RightButton" and window.spec.menu then
        window.spec.menu(window.owner, row, button)
    elseif window.spec.onSelect then
        window.spec.onSelect(window.owner, row)
    end
    window:Refresh()
end

local function DrawRows(window)
    local selected = window:Selected()
    for i = 1, PAGE_ROWS do
        local button = window.buttons[i]
        local row = i <= window.pageRows and window.filtered[window.offset + i]
        if row then
            local marker = row.checked == true and "[x] " or row.checked == false and "[ ] " or ""
            button.text:SetText(marker .. (row.label or ""))
            button.icon:SetTexture(row.icon)
            button.icon:SetShown(row.icon ~= nil)
            button.text:SetPoint("LEFT", row.icon and 32 or 7, 0)
            PaintRow(button, row, row.key == window.selected)
            button:Show()
        else
            button:Hide()
        end
    end
    window.details:SetText(selected and selected.detail or S.Text(window.spec.empty or "Select an entry to see its details."))
    window.details:SetHeight(math.max(67, window.details:GetStringHeight() + 6))
    window.detailsChild:SetHeight(window.details:GetHeight())
    window.counter:SetText(S.Text("%d–%d of %d"):format(#window.filtered == 0 and 0 or window.offset + 1,
        math.min(#window.filtered, window.offset + window.pageRows), #window.filtered))
    window.previous:SetEnabled(window.offset > 0)
    window.next:SetEnabled(window.offset + window.pageRows < #window.filtered)
    for i = 1, #window.actions do
        local action = window.spec.actions and window.spec.actions[i]
        local button = window.actions[i]
        button:SetShown(action ~= nil)
        if action then
            button:SetText(S.Text(action.label))
            button:SetEnabled(not action.enabled or action.enabled(window.owner, selected))
        end
    end
end

local function Refresh(window)
    if not window:IsShown() then return end
    if not Valid(window) then
        window:Hide()
        return
    end
    local input = S.PublicText(window.search:GetText()) or ""
    local query = input:lower()
    window.items = window.spec.rows(window.owner, query, input) or {}
    local filtered, count = window.filtered, 0
    for i = 1, math.min(#window.items, 20000) do
        local row = window.items[i]
        local match = query == ""
        if not match then
            if window.spec.filter then match = window.spec.filter(window.owner, row, query)
            else
                match = (row.search or row.label or ""):lower():find(query, 1, true) ~= nil
            end
        end
        if match then count = count + 1 filtered[count] = row end
    end
    for i = #filtered, count + 1, -1 do filtered[i] = nil end
    local pageRows = window.pageRows
    window.offset = math.min(window.offset, math.max(0, math.floor((count - 1) / pageRows) * pageRows))
    if window.spec.activate and not window:Selected() then
        local row = filtered[window.offset + 1]
        window.selected = row and row.key
    end
    if window.spec.status then window.status:SetText(window.spec.status(window.owner) or "") end
    local selectedTab = window.spec.currentTab and window.spec.currentTab(window.owner)
    for i = 1, #window.tabs do
        local tab, entry = window.tabs[i], window.spec.tabs and window.spec.tabs[i]
        tab:SetShown(entry ~= nil)
        if entry then tab:SetText(S.Text(entry.label)) tab:SetEnabled(entry.key ~= selectedTab) end
    end
    DrawRows(window)
end

local function Closed(window)
    local owner, spec = window.owner, window.spec
    if spec and spec.gamepad then
        window:EnableGamePadButton(false)
        window:SetScript("OnGamePadButtonDown", nil)
    end
    window.owner, window.spec, window.profile, window.selected = nil, nil, nil, nil
    window.items, window.filtered = {}, {}
    window.details:SetText("")
    window.status:SetText("")
    window.search:ClearFocus()
    if spec and spec.onHide then spec.onHide(owner) end
end

local function Activate(window)
    local row = window:Selected()
    if row and not row.disabled and window.spec.activate then window.spec.activate(window.owner, row, window) end
end

local function MoveSelection(window, key)
    if not Valid(window) or not window.spec.activate or (key ~= "UP" and key ~= "DOWN") then return end
    local index = window.offset + 1
    for i = 1, #window.filtered do
        if window.filtered[i].key == window.selected then index = i break end
    end
    local step = key == "UP" and -1 or 1
    local row = window.filtered[index + step]
    if not row then return end
    window.selected = row.key
    window.offset = math.floor((index + step - 1) / window.pageRows) * window.pageRows
    DrawRows(window)
end

local function PadButton(window, key)
    if not S.Public(key) then return end
    if key == "PADDUP" then
        MoveSelection(window, "UP")
    elseif key == "PADDDOWN" then
        MoveSelection(window, "DOWN")
    elseif key == "PAD1" then
        Activate(window)
    elseif key == "PAD2" then
        window:Hide()
    end
end

local function CreateRows(window)
    window.buttons = {}
    for i = 1, PAGE_ROWS do
        local bridge = Theme()
        local row = bridge and bridge.MenuNavButton(window, 720, ROW_HEIGHT - 2)
        local modern = row ~= nil
        row = row or S.CreateFrame("Button", nil, window)
        row.toolModern = modern
        row:SetSize(720, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 18, -153 - (i - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.index = i
        if not modern then
            row.fill = S.CreateTexture(row, nil, "BACKGROUND")
            row.fill:SetAllPoints()
        end
        row.text = modern and bridge.MenuButtonLabel(row) or Label(row, "", 12)
        if modern then row.text:ClearAllPoints() end
        row.text:SetPoint("LEFT", 7, 0)
        row.text:SetPoint("RIGHT", -7, 0)
        row.text:SetWordWrap(false)
        row.icon = S.CreateTexture(row, nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 6, 0)
        row:SetScript("OnClick", RowClicked)
        row:SetScript("OnDoubleClick", function(button, mouse)
            if mouse ~= "LeftButton" or not Valid(window) or not window.spec.activate then return end
            local selected = window.filtered[window.offset + button.index]
            if selected then window.selected = selected.key end
            Activate(window)
        end)
        window.buttons[i] = row
    end
end

local function CreateNavigation(window)
    window.actions, window.tabs = {}, {}
    for i = 1, 6 do
        local button = Button(window, "", 114, RunAction)
        button.index = i
        button:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 121, 17)
        window.actions[i] = button
    end
    for i = 1, 8 do
        local tab = Button(window, "", 86, function(button)
            if not Valid(window) then return end
            local entry = window.spec.tabs and window.spec.tabs[button.index]
            if entry and window.spec.selectTab then
                window.offset, window.selected = 0, nil
                window.spec.selectTab(window.owner, entry.key)
                window:Refresh()
            end
        end)
        tab.index = i
        tab:SetPoint("TOPLEFT", 18 + (i - 1) * 91, -82)
        window.tabs[i] = tab
    end
    window.previous = Button(window, "Previous", 86, function()
        window.offset = math.max(0, window.offset - window.pageRows)
        if window.spec and window.spec.activate then window.selected = nil end
        window:Refresh()
    end)
    window.previous:SetPoint("TOPLEFT", 18, -484)
    window.next = Button(window, "Next", 86, function()
        window.offset = window.offset + window.pageRows
        if window.spec and window.spec.activate then window.selected = nil end
        window:Refresh()
    end)
    window.next:SetPoint("LEFT", window.previous, "RIGHT", 6, 0)
    window.counter = Label(window, "", 11)
    window.counter:SetPoint("LEFT", window.next, "RIGHT", 12, 0)
end

local function Create()
    local window = Window(756, 650)
    window.title = Label(window, "", 15)
    window.title:SetPoint("TOPLEFT", 18, -12)
    window.title:SetWidth(680)
    window.help = Label(window, "", 11)
    window.help:SetPoint("TOPLEFT", 18, -42)
    window.help:SetSize(720, 34)
    window.help:SetWordWrap(true)
    window.search = S.CreateFrame("EditBox", nil, window, "InputBoxInstructionsTemplate")
    window.search:SetPoint("TOPLEFT", 24, -116)
    window.search:SetSize(705, 25)
    window.search:SetAutoFocus(false)
    window.search:SetMaxBytes(513)
    window.search.Instructions:SetText(S.Text("Search this list"))
    window.search:SetScript("OnEscapePressed", function(edit)
        if window.spec and window.spec.activate then window:Hide() else edit:ClearFocus() end
    end)
    window.search:SetScript("OnEnterPressed", function() Activate(window) end)
    window.search:SetScript("OnArrowPressed", function(_, key) MoveSelection(window, key) end)
    window.search:SetScript("OnTextChanged", function()
        window.offset = 0
        if window.spec and window.spec.activate then window.selected = nil end
        window:Refresh()
    end)
    local detailScroll = S.CreateFrame("ScrollFrame", nil, window, "ScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 18, -519)
    detailScroll:SetSize(692, 67)
    window.detailsChild = S.CreateFrame("Frame", nil, detailScroll)
    window.detailsChild:SetSize(686, 67)
    window.details = Label(window.detailsChild, "", 12)
    window.details:SetPoint("TOPLEFT")
    window.details:SetWidth(686)
    window.details:SetHeight(67)
    window.details:SetWordWrap(true)
    detailScroll:SetScrollChild(window.detailsChild)
    window.detailScroll = detailScroll
    if Theme() then Theme().MenuEditBox(window.search) end
    window.status = Label(window, "", 11)
    window.status:SetPoint("BOTTOMLEFT", 18, 48)
    window.status:SetSize(720, 25)
    window.status:SetWordWrap(true)
    window.items, window.filtered, window.offset = {}, {}, 0
    window.pageRows = PAGE_ROWS
    window.Refresh, window.Selected = Refresh, Selected
    window.SetStatus = function(self, text) self.status:SetText(text or "") end
    CreateRows(window)
    CreateNavigation(window)
    window:SetScript("OnHide", Closed)
    window:SetScript("OnEvent", function() window:Hide() end)
    window:RegisterEvent("PLAYER_REGEN_DISABLED")
    window:Hide()
    return window
end

-- The compact tool uses the same widgets and skin as the full tool window.
local function SetCompact(window, compact)
    if window.compact == compact then return end
    window.compact = compact
    window.pageRows = compact and 8 or PAGE_ROWS
    window:SetSize(compact and 620 or 756, compact and 500 or 650)
    window.title:SetWidth(compact and 544 or 680)
    window.help:SetWidth(compact and 584 or 720)
    window.search:SetWidth(compact and 569 or 705)
    window.search:SetPoint("TOPLEFT", 24, compact and -102 or -116)
    for i = 1, #window.buttons do
        local row = window.buttons[i]
        row:SetWidth(compact and 584 or 720)
        row:SetPoint("TOPLEFT", 18, -(compact and 139 or 153) - (i - 1) * ROW_HEIGHT)
    end
    for i = 1, #window.tabs do
        window.tabs[i]:SetPoint("TOPLEFT", 18 + (i - 1) * 91, compact and -68 or -82)
    end
    window.previous:SetPoint("TOPLEFT", 18, compact and -360 or -484)
    window.detailScroll:SetPoint("TOPLEFT", 18, compact and -396 or -519)
    window.detailScroll:SetSize(compact and 556 or 692, compact and 51 or 67)
    window.detailsChild:SetWidth(compact and 550 or 686)
    window.details:SetWidth(compact and 550 or 686)
    window.status:SetWidth(compact and 584 or 720)
end

function Tools.Open(owner, spec, query)
    if NS.InCombat() or owner.active == false then return end
    if not current then current = Create() end
    if current:IsShown() then current:Hide() end
    current.owner, current.spec, current.profile = owner, spec, NS.DB
    current.selected, current.offset = nil, 0
    SetCompact(current, spec.activate ~= nil)
    current.title:SetText(S.Text(spec.title))
    current.help:SetText(S.Text(spec.help or ""))
    current.search.Instructions:SetText(S.Text(spec.searchHint or "Search this list"))
    current.search:SetText(S.PublicText(query) or "")
    current:Show()
    current:Refresh()
    if spec.gamepad then
        current:SetScript("OnGamePadButtonDown", PadButton)
        current:EnableGamePadButton(true)
    end
    if spec.activate then current.search:SetFocus() end
    if Theme() then Theme().WatchMenuAppearance(Tools, Restyle) end
    Restyle()
    return current
end

function Tools.IsOpen(owner)
    return current and current.owner == owner and current:IsShown()
end

function Tools.Refresh(owner)
    if current and current.owner == owner then current:Refresh() end
end

function Tools.Close(owner)
    if current and current.owner == owner then current:Hide() end
    if editor and editor.owner == owner then editor:Hide() end
end

function Tools.IsEditing(owner)
    return editor ~= nil and editor.owner == owner and editor:IsShown()
end

function Tools.RefreshFonts(owner)
    if not editor or editor.owner ~= owner or not editor:IsShown() or NS.InCombat() then return end
    for key, size in pairs(EDITOR_FONTS) do S.SetFont(editor[key], nil, size, "") end
    S.SetFont(ButtonFont(editor.save), nil, 12, "")
    S.SetFont(ButtonFont(editor.cancel), nil, 12, "")
    if editor.close.caption then S.SetFont(editor.close.caption, nil, 13, "") end
end

local function SaveEdit()
    local owner, spec = editor.owner, editor.spec
    if not owner or NS.InCombat() or editor.profile ~= NS.DB or owner.active == false
        or spec.valid and not spec.valid(owner) then
            editor:Hide()
            return
        end
    local text = editor.input:GetText()
    if #text > (spec.maxBytes or 2048) then
        editor.error:SetText(S.Text("The text is too long."))
        return
    end
    local ok, why = spec.onSave(owner, text)
    if ok == false then
        editor.error:SetText(S.Text(why or "Check your input."))
        return
    end
    if editor.spec == spec then editor:Hide() end
    Tools.Refresh(owner)
end

local function CreateEditor()
    local panel = Window(560, 330)
    -- A prompt stays above the DIALOG tool windows that open it, however deep their content nests.
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel.title = Label(panel, "", 14)
    panel.title:SetPoint("TOPLEFT", 16, -12)
    panel.hint = Label(panel, "", 12)
    panel.hint:SetPoint("TOPLEFT", 16, -48)
    panel.hint:SetSize(520, 42)
    panel.hint:SetWordWrap(true)
    local scroll = S.CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -98)
    scroll:SetSize(490, 148)
    panel.input = S.CreateFrame("EditBox", nil, scroll)
    panel.input:SetWidth(480)
    panel.input:SetHeight(148)
    panel.input:SetAutoFocus(false)
    S.SetFont(panel.input, nil, 12, "")
    scroll:SetScrollChild(panel.input)
    panel.inputScroll = scroll
    panel.input:SetScript("OnEscapePressed", function() panel:Hide() end)
    panel.input:SetScript("OnReceiveDrag", function(input)
        local owner, spec = panel.owner, panel.spec
        if not owner or not spec.receive or NS.InCombat() or panel.profile ~= NS.DB or owner.active == false
            or spec.valid and not spec.valid(owner) then return end
        local replacement = spec.receive(input:GetText())
        if replacement then input:SetText(replacement) end
    end)
    panel.error = Label(panel, "", 11)
    panel.error:SetPoint("BOTTOMLEFT", 16, 45)
    panel.error:SetWidth(520)
    panel.error:SetTextColor(1, .6, .3)
    panel.save = Button(panel, "Save", 110, SaveEdit)
    panel.save:SetPoint("BOTTOMRIGHT", -138, 12)
    panel.cancel = Button(panel, "Cancel", 110, function() panel:Hide() end)
    panel.cancel:SetPoint("BOTTOMRIGHT", -16, 12)
    panel:SetScript("OnHide", function()
        panel.owner, panel.spec, panel.profile = nil, nil, nil
        panel.input:ClearFocus()
        panel.input:SetText("")
    end)
    panel:SetScript("OnEvent", function() panel:Hide() end)
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    return panel
end

Restyle = function()
    if NS.InCombat() or not (current and current:IsShown() or editor and editor:IsShown()) then return end
    local bridge = Theme()
    if not bridge then return end
    for label, size in pairs(fonts) do
        S.SetFont(label, nil, size, "")
        bridge.MenuFont(label, nil, size >= 14 and "title" or "body")
    end
    if current and current:IsShown() then
        if current.toolModern then bridge.MenuMaterial(current, "shell") end
        bridge.MenuEditBox(current.search)
    end
    if editor and editor:IsShown() then
        if editor.toolModern then bridge.MenuMaterial(editor, "shell") end
        bridge.MenuMaterial(editor.inputScroll, "card")
        bridge.MenuFont(editor.input, nil, "body")
        local color = bridge.MenuColor("danger", "text")
        if color then editor.error:SetTextColor(unpack(color)) end
    end
end

function Tools.Edit(owner, spec)
    if NS.InCombat() or owner.active == false then return end
    if not editor then editor = CreateEditor() end
    editor.owner, editor.spec, editor.profile = owner, spec, NS.DB
    editor.title:SetText(S.Text(spec.title))
    editor.hint:SetText(S.Text(spec.label or ""))
    editor.input:SetMultiLine(spec.multiline == true)
    editor.input:SetMaxBytes((spec.maxBytes or 2048) + 1)
    editor.input:SetText(spec.text or "")
    editor.error:SetText("")
    editor:Show()
    Tools.RefreshFonts(owner)
    if Theme() then Theme().WatchMenuAppearance(Tools, Restyle) end
    Restyle()
    editor.input:SetFocus()
    editor.input:HighlightText()
end
