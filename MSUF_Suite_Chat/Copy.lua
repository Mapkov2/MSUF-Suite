local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Opt-in copy chooser: a Copy button on each chat window opens one shared
-- dialog listing the window's recent public lines. Choosing a line puts its
-- plain text into an edit box, ready for Ctrl+C; Copy all puts every public
-- line of the window there. Nothing reads the chat until a button is clicked.
local M = C.M
local ROWS, WIDTH, INSET = 10, 440, 15
-- Copy all shows the lines in a scrolling multi-line box over the chooser
-- rows, which end 309 pixels below the top; the dialog's own edit box is
-- one line and cannot hold line breaks.
local ALL_TOP, ALL_HEIGHT, ALL_BUTTON_WIDTH = -61, 248, 84
-- The shared copy dialog (MSUF_Suite_Modules/Dialogs.lua) with a chooser.
local CHOOSER = { rows = ROWS, height = 345 }
local TEXT = {
    copy = S.Text("Copy"),
    copyTooltip = S.Text("Copy a recent chat message"),
    copyHint = S.Text("Choose a line, then press Ctrl+C"),
    copyEmpty = S.Text("No recent messages to copy"),
    copyAll = S.Text("Copy all"),
    copyAllHint = S.Text("Every line is selected, press Ctrl+C"),
    copyURL = S.Text("Copy this URL with Ctrl+C"),
}
local Fill, Tint, ShowTooltip, HideTooltip = C.Fill, C.Tint, C.ShowTooltip, C.HideTooltip

local function PlainMessage(text)
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

-- Every public line of the window, oldest first, one per line.
local function AllMessages(frame)
    local count = frame:GetNumMessages()
    if not S.Number(count) then return "" end
    local lines, kept = {}, 0
    for index = 1, count do
        local message = frame:GetMessageInfo(index)
        if S.Public(message) and type(message) == "string" and message ~= "" then
            kept = kept + 1
            lines[kept] = PlainMessage(message)
        end
    end
    return table.concat(lines, "\n", 1, kept)
end

-- Blizzard's multi-line input with its scroll bar (InputScrollFrameTemplate
-- sizes its box from the frame's width when it loads, before this size).
local function CreateAllView(panel)
    local view = S.CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
    view:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, ALL_TOP)
    view:SetSize(WIDTH - 2 * INSET, ALL_HEIGHT)
    view.CharCount:Hide()
    view.EditBox:SetWidth(WIDTH - 2 * INSET - 18)
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

local function CopyAll(panel)
    local frame = panel.chatFrame
    if not frame or NS.Safety.IsForbidden(frame) then return end
    local text = AllMessages(frame)
    if text == "" then
        panel.hint:SetText(TEXT.copyEmpty)
        return
    end
    for _, row in ipairs(panel.rows) do
        row.message = nil
        row:Hide()
    end
    local view = panel.allView or CreateAllView(panel)
    panel.edit:Hide()
    view:Show()
    view.EditBox:SetText(text)
    panel.hint:SetText(TEXT.copyAllHint)
    view.EditBox:SetFocus()
    view.EditBox:HighlightText()
end

local function CreateCopyAllButton(panel)
    local button = S.CreateFrame("Button", nil, panel)
    button:SetSize(ALL_BUTTON_WIDTH, 19)
    button:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -INSET, -33)
    local fill = Fill(button, "BACKGROUND")
    fill:SetAllPoints(button)
    Tint(fill, "252a2d", 100)
    local label = S.CreateFontString(button, nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER")
    label:SetText(TEXT.copyAll)
    button:SetScript("OnClick", function() CopyAll(panel) end)
    return button
end

-- The drag strip of the title leaves the message rows and the copy edit box
-- free for clicks, selection and Ctrl+C. Closing the dialog, however it
-- happens, ends the Copy all view.
local function CreateCopyDialog()
    local panel = S.QoLCopyDialog("Copy chat message (drag to move)", "Choose a line, then press Ctrl+C", WIDTH, CHOOSER)
    panel.copyAll = CreateCopyAllButton(panel)
    panel:SetScript("OnHide", CloseAllView)
    return panel
end

-- Newest first: the last ROWS public lines among the window's newest 100.
local function ShowCopyDialog(self, frame)
    if not self.config.copyMessages or not frame or NS.Safety.IsForbidden(frame) then return end
    local count = frame:GetNumMessages()
    if not S.Number(count) then return end
    local panel = self.copyDialog or CreateCopyDialog()
    self.copyDialog = panel
    CloseAllView(panel)
    panel.chatFrame = frame
    panel.copyAll:Show()
    local shown = 0
    for index = count, math.max(1, count - 99), -1 do
        if shown == ROWS then break end
        local message = frame:GetMessageInfo(index)
        if S.Public(message) and type(message) == "string" and message ~= "" then
            shown = shown + 1
            local row = panel.rows[shown]
            row.message = PlainMessage(message)
            row.label:SetText(row.message)
            row:Show()
        end
    end
    for i = shown + 1, ROWS do
        panel.rows[i].message = nil
        panel.rows[i]:Hide()
    end
    panel.hint:SetText(shown > 0 and TEXT.copyHint or TEXT.copyEmpty)
    panel.edit:SetText("")
    panel:Show()
end

local function CopyButtonClick(button) ShowCopyDialog(M, button.chatFrame) end

-- A clicked chat URL (Messages.lua links them) opens the dialog with only
-- that address, selected for Ctrl+C.
function C.ShowURL(url)
    local panel = M.copyDialog or CreateCopyDialog()
    M.copyDialog = panel
    CloseAllView(panel)
    panel.copyAll:Hide()
    for _, row in ipairs(panel.rows) do
        row.message = nil
        row:Hide()
    end
    panel.hint:SetText(TEXT.copyURL)
    S.QoLShowCopy(panel, url)
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
    if not self.config.copyMessages then
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
