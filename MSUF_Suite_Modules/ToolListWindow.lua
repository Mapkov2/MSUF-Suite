local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Tools = {}
S.ToolListWindow = Tools
local PAGE_ROWS, ROW_HEIGHT = 12, 27
local current, editor
local EDITOR_FONTS = { title = 14, hint = 12, input = 12, error = 11 }

local function Label(parent, text, size)
    local label = S.QoLLabel(parent, text or "", size or 12)
    label:SetJustifyH("LEFT")
    return label
end

local function Button(parent, text, width, action)
    local button = S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(S.Text(text))
    button:SetScript("OnClick", action)
    return button
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
        local button, row = window.buttons[i], window.filtered[window.offset + i]
        if row then
            local marker = row.checked == true and "[x] " or row.checked == false and "[ ] " or ""
            button.text:SetText(marker .. (row.label or ""))
            button.icon:SetTexture(row.icon)
            button.icon:SetShown(row.icon ~= nil)
            button.text:SetPoint("LEFT", row.icon and 32 or 7, 0)
            button.text:SetTextColor(row.disabled and .55 or .92, row.disabled and .55 or .94, row.disabled and .55 or .97)
            button.fill:SetColorTexture(.2, .36, .46, row.key == window.selected and .85 or .18)
            button:Show()
        else
            button:Hide()
        end
    end
    window.details:SetText(selected and selected.detail or S.Text(window.spec.empty or "Select an entry to see its details."))
    window.details:SetHeight(math.max(67, window.details:GetStringHeight() + 6))
    window.detailsChild:SetHeight(window.details:GetHeight())
    window.counter:SetText(S.Text("%d–%d of %d"):format(#window.filtered == 0 and 0 or window.offset + 1,
        math.min(#window.filtered, window.offset + PAGE_ROWS), #window.filtered))
    window.previous:SetEnabled(window.offset > 0)
    window.next:SetEnabled(window.offset + PAGE_ROWS < #window.filtered)
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
    local query = window.search:GetText():lower()
    window.items = window.spec.rows(window.owner, query) or {}
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
    window.offset = math.min(window.offset, math.max(0, math.floor((count - 1) / PAGE_ROWS) * PAGE_ROWS))
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
    window.owner, window.spec, window.profile, window.selected = nil, nil, nil, nil
    window.items, window.filtered = {}, {}
    window.details:SetText("")
    window.status:SetText("")
    window.search:ClearFocus()
    if spec and spec.onHide then spec.onHide(owner) end
end

local function CreateRows(window)
    window.buttons = {}
    for i = 1, PAGE_ROWS do
        local row = S.CreateFrame("Button", nil, window)
        row:SetSize(720, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 18, -153 - (i - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.index = i
        row.fill = S.CreateTexture(row, nil, "BACKGROUND")
        row.fill:SetAllPoints()
        row.text = Label(row, "", 12)
        row.text:SetPoint("LEFT", 7, 0)
        row.text:SetPoint("RIGHT", -7, 0)
        row.text:SetWordWrap(false)
        row.icon = S.CreateTexture(row, nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 6, 0)
        row:SetScript("OnClick", RowClicked)
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
        window.offset = math.max(0, window.offset - PAGE_ROWS)
        window:Refresh()
    end)
    window.previous:SetPoint("TOPLEFT", 18, -484)
    window.next = Button(window, "Next", 86, function()
        window.offset = window.offset + PAGE_ROWS
        window:Refresh()
    end)
    window.next:SetPoint("LEFT", window.previous, "RIGHT", 6, 0)
    window.counter = Label(window, "", 11)
    window.counter:SetPoint("LEFT", window.next, "RIGHT", 12, 0)
end

local function Create()
    local window = S.QoLWindow(756, 650, "")
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
    window.search:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    window.search:SetScript("OnTextChanged", function() window.offset = 0 window:Refresh() end)
    local detailScroll = S.CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
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
    window.status = Label(window, "", 11)
    window.status:SetPoint("BOTTOMLEFT", 18, 48)
    window.status:SetSize(720, 25)
    window.status:SetWordWrap(true)
    window.items, window.filtered, window.offset = {}, {}, 0
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

function Tools.Open(owner, spec)
    if NS.InCombat() or owner.active == false then return end
    if not current then current = Create() end
    if current:IsShown() then current:Hide() end
    current.owner, current.spec, current.profile = owner, spec, NS.DB
    current.selected, current.offset = nil, 0
    current.title:SetText(S.Text(spec.title))
    current.help:SetText(S.Text(spec.help or ""))
    current.search:SetText("")
    current:Show()
    current:Refresh()
    return current
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
    S.SetFont(editor.save:GetFontString(), nil, 12, "")
    S.SetFont(editor.cancel:GetFontString(), nil, 12, "")
    S.SetFont(editor.close.caption, nil, 13, "")
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
    local panel = S.QoLWindow(560, 330, "")
    -- A prompt stays above the DIALOG tool windows that open it, however deep their content nests.
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel.title = Label(panel, "", 14)
    panel.title:SetPoint("TOPLEFT", 16, -12)
    panel.hint = Label(panel, "", 12)
    panel.hint:SetPoint("TOPLEFT", 16, -48)
    panel.hint:SetSize(520, 42)
    panel.hint:SetWordWrap(true)
    local scroll = S.CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -98)
    scroll:SetSize(490, 148)
    panel.input = S.CreateFrame("EditBox", nil, scroll)
    panel.input:SetWidth(480)
    panel.input:SetHeight(148)
    panel.input:SetAutoFocus(false)
    S.SetFont(panel.input, nil, 12, "")
    scroll:SetScrollChild(panel.input)
    panel.input:SetScript("OnEscapePressed", function() panel:Hide() end)
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
    editor.input:SetFocus()
    editor.input:HighlightText()
end
