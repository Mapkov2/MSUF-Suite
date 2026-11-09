local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Opt-in copy chooser: a Copy button on each chat window opens one shared
-- dialog over the window's readable lines. A snapshot lives only while the
-- dialog is open, so typing a search never walks the native message buffer.
-- Copy all takes the latest complete snapshot when clicked.
local M = C.M
local ROWS, WIDTH, INSET = 10, 500, 16
local ALL_BUTTON_WIDTH, ACTION_HEIGHT = 130, 27
local CHOOSER = { rows = ROWS, height = 457 }
local SEARCH_ROW_TOP, ROW_STEP = -112, 26
-- InputScrollFrameTemplate keeps native scrolling and selection. Only the
-- inherited background pieces are replaced, on our own scroll frame.
local INPUT_ART = {
    "TopLeftTex", "TopTex", "TopRightTex", "LeftTex", "MiddleTex", "RightTex",
    "BottomLeftTex", "BottomTex", "BottomRightTex",
}
local TEXT = {
    copy = S.Text("Copy"),
    copyTooltip = S.Text("Copy a recent chat message"),
    copyHint = S.Text("Choose a line, then press Ctrl+C"),
    copyEmpty = S.Text("No recent messages to copy"),
    copyAll = S.Text("Copy all"),
    copyAllHint = S.Text("Every line is selected, press Ctrl+C"),
    copyURL = S.Text("Copy this URL with Ctrl+C"),
    search = S.Text("Search this chat tab"),
    noMatches = S.Text("No chat messages match this search."),
    range = S.Text("%d–%d of %d"),
    back = S.Text("Back to messages"),
}
local Fill, Tint, ShowTooltip, HideTooltip = C.Fill, C.Tint, C.ShowTooltip, C.HideTooltip

function C.PlainChatMessage(text)
    -- GetMessageInfo returns Blizzard's rendered line, including a timestamp
    -- if its native setting is enabled. Present readable text in the copy box.
    local plain = text:gsub("|H.-|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return plain
end

-- Also clears the chosen text, so a closed dialog keeps no chat content.
local function HideCopyDialog(panel)
    if panel then S.QoLClearCopy(panel) end
end
C.HideCopyDialog = HideCopyDialog

local function ReadMessages(frame, first, last, step)
    local lines, kept = {}, 0
    for index = first, last, step do
        local message = S.PublicText(frame:GetMessageInfo(index))
        if message and message ~= "" then
            kept = kept + 1
            lines[kept] = C.PlainChatMessage(message)
        end
    end
    return lines
end

-- Blizzard's multi-line input with its scroll bar (InputScrollFrameTemplate
-- sizes its box from the frame's width when it loads, before this size).
local function CreateAllView(panel)
    local view = S.CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate,BackdropTemplate")
    view:SetPoint("TOPLEFT", panel.rows[1], "TOPLEFT")
    view:SetPoint("BOTTOMRIGHT", panel.edit, "BOTTOMRIGHT")
    for _, key in ipairs(INPUT_ART) do view[key]:Hide() end
    view.CharCount:Hide()
    S.QoLCopySurface(view, "card")
    view.EditBox:SetWidth(WIDTH - 2 * INSET - 18)
    view.EditBox:SetTextInsets(10, 6, 6, 6)
    S.SetFont(view.EditBox, nil, 12, "")
    view.EditBox:SetTextColor(.92, .95, 1)
    view.EditBox:SetScript("OnEscapePressed", function() HideCopyDialog(panel) end)
    view:Hide()
    panel.allView = view
    return view
end

-- Back to the chooser: the Copy all box gives up its text.
local function CloseAllView(panel)
    local view = panel.allView
    if not view then return end
    view.EditBox:ClearFocus()
    view.EditBox:SetText("")
    view:Hide()
    panel.edit:Show()
end

local function ShowRows(panel)
    local matches, offset = panel.matches, panel.offset
    for i, row in ipairs(panel.rows) do
        row.message = matches[offset + i]
        row.label:SetText(row.message or "")
        row:SetShown(row.message ~= nil)
    end
    local count = #matches
    local empty = panel.search:GetText() == "" and TEXT.copyEmpty or TEXT.noMatches
    panel.hint:SetText(count > 0 and TEXT.copyHint or empty)
    panel.counter:SetText(TEXT.range:format(count > 0 and offset + 1 or 0, math.min(count, offset + ROWS), count))
    panel.previous:SetEnabled(offset > 0)
    panel.next:SetEnabled(offset + ROWS < count)
end

local function SetActionText(button, text)
    if button.copyLabel then button.copyLabel:SetText(text) else button:SetText(text) end
end

local function ShowNavigation(panel, shown)
    panel.search:SetShown(shown)
    panel.previous:SetShown(shown)
    panel.next:SetShown(shown)
    panel.counter:SetShown(shown)
end

local function SearchChanged(search)
    local panel = search:GetParent()
    if not panel.lines then return end
    local query, matches = search:GetText():lower(), panel.matches
    local count = 0
    if query ~= "" and not panel.searchLines then
        panel.searchLines = {}
        for i, line in ipairs(panel.lines) do panel.searchLines[i] = line:lower() end
    end
    for i, line in ipairs(panel.lines) do
        if query == "" or panel.searchLines[i]:find(query, 1, true) then
            count = count + 1
            matches[count] = line
        end
    end
    for i = #matches, count + 1, -1 do matches[i] = nil end
    panel.offset = 0
    panel.edit:SetText("")
    ShowRows(panel)
end

local function ShowAllText(panel, text)
    for _, row in ipairs(panel.rows) do row:Hide() end
    local view = panel.allView or CreateAllView(panel)
    panel.edit:Hide()
    view:Show()
    view.EditBox:SetText(text)
    panel.hint:SetText(TEXT.copyAllHint)
    view.EditBox:SetFocus()
    view.EditBox:HighlightText()
end

local function CopyAll(panel)
    if panel.allOpen then
        panel.allOpen = nil
        CloseAllView(panel)
        SetActionText(panel.copyAll, TEXT.copyAll)
        ShowNavigation(panel, true)
        ShowRows(panel)
        return
    end
    local frame = panel.chatFrame
    if not frame or NS.Safety.IsForbidden(frame) then return end
    local count = frame:GetNumMessages()
    if not S.Number(count) then return end
    local text = table.concat(ReadMessages(frame, 1, count, 1), "\n")
    if text == "" then
        panel.hint:SetText(TEXT.copyEmpty)
        return
    end
    panel.allOpen = true
    panel.search:ClearFocus()
    ShowNavigation(panel, false)
    SetActionText(panel.copyAll, TEXT.back)
    ShowAllText(panel, text)
end

local function CreateActionButton(panel, text, width, action)
    local bridge = NS.HostBridge
    local button = bridge and bridge.MenuButton(panel, width, ACTION_HEIGHT)
    if not button then
        button = S.CreateFrame("Button", nil, panel, "BackdropTemplate")
        button:SetSize(width, ACTION_HEIGHT)
        S.QoLCopySurface(button, "card")
        local hover = S.CreateTexture(button, nil, "HIGHLIGHT")
        hover:SetAllPoints(button)
        hover:SetColorTexture(.30, .58, .82, .25)
        local label = S.CreateFontString(button, nil, "ARTWORK")
        S.SetFont(label, nil, 12, "")
        label:SetPoint("CENTER")
        button.copyLabel = label
    end
    SetActionText(button, text)
    button:SetScript("OnClick", action)
    return button
end

local function AddSearch(panel)
    local search = S.CreateFrame("EditBox", nil, panel, "InputBoxInstructionsTemplate")
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET + 4, -76)
    search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -INSET - 4, -76)
    search:SetHeight(27)
    search:SetAutoFocus(false)
    search:SetMaxBytes(512)
    search.Instructions:SetText(TEXT.search)
    search:SetScript("OnTextChanged", SearchChanged)
    search:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    if NS.HostBridge then NS.HostBridge.MenuEditBox(search) end
    panel.search = search
    for i, row in ipairs(panel.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, SEARCH_ROW_TOP - (i - 1) * ROW_STEP)
    end
end

local function AddNavigation(panel)
    panel.previous = CreateActionButton(panel, S.Text("Previous"), 96, function()
        panel.offset = math.max(0, panel.offset - ROWS)
        ShowRows(panel)
    end)
    panel.previous:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", INSET, 49)
    panel.next = CreateActionButton(panel, S.Text("Next"), 96, function()
        panel.offset = panel.offset + ROWS
        ShowRows(panel)
    end)
    panel.next:SetPoint("LEFT", panel.previous, "RIGHT", 8, 0)
    panel.counter = S.QoLLabel(panel, "", 11)
    panel.counter:SetPoint("LEFT", panel.next, "RIGHT", 12, 0)
end

local function ResetCopyDialog(panel)
    panel.chatFrame, panel.lines, panel.matches, panel.searchLines, panel.allOpen = nil, nil, nil, nil, nil
    panel.search:ClearFocus()
    panel.search:SetText("")
    panel.edit:ClearFocus()
    panel.edit:SetText("")
    CloseAllView(panel)
    for _, row in ipairs(panel.rows) do
        row.message = nil
        row.label:SetText("")
        row:Hide()
    end
end

local function CreateCopyDialog()
    local panel = S.QoLCopyDialog("Copy chat message (drag to move)", "Choose a line, then press Ctrl+C", WIDTH, CHOOSER)
    panel.copyAll = CreateActionButton(panel, TEXT.copyAll, ALL_BUTTON_WIDTH, function() CopyAll(panel) end)
    panel.copyAll:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -INSET, -43)
    panel.hint:SetPoint("TOPRIGHT", panel.copyAll, "TOPLEFT", -12, 0)
    AddSearch(panel)
    AddNavigation(panel)
    panel:SetScript("OnHide", ResetCopyDialog)
    return panel
end

local function ShowCopyDialog(self, frame)
    if not (self.config.copyMessages or self.config.headerToolbar) or not frame or NS.Safety.IsForbidden(frame) then return end
    local count = frame:GetNumMessages()
    if not S.Number(count) then return end
    local panel = self.copyDialog or CreateCopyDialog()
    self.copyDialog = panel
    ResetCopyDialog(panel)
    panel.chatFrame, panel.lines, panel.matches = frame, ReadMessages(frame, count, 1, -1), {}
    SetActionText(panel.copyAll, TEXT.copyAll)
    panel.copyAll:Show()
    ShowNavigation(panel, true)
    SearchChanged(panel.search)
    panel:Show()
end

C.OpenCopyDialog = ShowCopyDialog

local function CopyButtonClick(button) ShowCopyDialog(M, button.chatFrame) end

local function PrepareSingle()
    local panel = M.copyDialog or CreateCopyDialog()
    M.copyDialog = panel
    ResetCopyDialog(panel)
    ShowNavigation(panel, false)
    panel.copyAll:Hide()
    return panel
end

-- Links already present in chat may outlive the enabled message options.
function C.ShowURL(url)
    local panel = PrepareSingle()
    panel.hint:SetText(TEXT.copyURL)
    S.QoLShowCopy(panel, url)
end

function C.ShowChatLine(text)
    local line = S.PublicText(text)
    if not line or line == "" then return end
    local panel = PrepareSingle()
    panel.hint:SetText(TEXT.copyHint)
    S.QoLShowCopy(panel, C.PlainChatMessage(line))
end

function C.ShowChatTranscript(text)
    local panel = PrepareSingle()
    panel:Show()
    ShowAllText(panel, text)
end

local function CopyButtonEnter(button) ShowTooltip(button, TEXT.copyTooltip) end

local function CreateCopyButton(frame)
    local button = S.CreateFrame("Button", nil, frame)
    button.chatFrame = frame
    button:SetSize(46, 19)
    button:SetFrameStrata("MEDIUM")
    local fill = Fill(button, "BACKGROUND")
    fill:SetAllPoints(button)
    button.fill = fill
    local label = S.CreateFontString(button, nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER")
    label:SetText(TEXT.copy)
    button:SetScript("OnClick", CopyButtonClick)
    button:SetScript("OnEnter", CopyButtonEnter)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

function C.ApplyCopyButton(self, visual, frame, top)
    if not self.config.copyMessages or self.config.headerToolbar and frame.isDocked then
        if visual.copyButton then visual.copyButton:Hide() end
        HideCopyDialog(self.copyDialog)
        return
    end
    local button = visual.copyButton or CreateCopyButton(frame)
    visual.copyButton = button
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4 + (self.config.copyButtonX or 0),
        math.max(21, top) - 3 + (self.config.copyButtonY or 0))
    button:SetFrameLevel(frame:GetFrameLevel() + 4)
    Tint(button.fill, self.config.panelColor, 95)
    button:Show()
end
