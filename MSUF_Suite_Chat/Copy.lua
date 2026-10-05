local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Opt-in copy chooser: a Copy button on each chat window opens one shared
-- dialog listing the window's recent public lines. Choosing a line puts its
-- plain text into an edit box, ready for Ctrl+C. Nothing reads the chat
-- until the button is clicked.
local M = C.M
local ROWS = 10
-- The shared copy dialog (MSUF_Suite_Modules/Dialogs.lua) with a chooser.
local CHOOSER = { rows = ROWS, height = 345 }
local TEXT = {
    copy = S.Text("Copy"),
    copyTooltip = S.Text("Copy a recent chat message"),
    copyHint = S.Text("Choose a line, then press Ctrl+C"),
    copyEmpty = S.Text("No recent messages to copy"),
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

-- The drag strip of the title leaves the message rows and the copy edit box
-- free for clicks, selection and Ctrl+C.
local function CreateCopyDialog()
    return S.QoLCopyDialog("Copy chat message (drag to move)", "Choose a line, then press Ctrl+C", 440, CHOOSER)
end

-- Newest first: the last ROWS public lines among the window's newest 100.
local function ShowCopyDialog(self, frame)
    if not self.config.copyMessages or not frame or NS.Safety.IsForbidden(frame) then return end
    local count = frame:GetNumMessages()
    if not S.Number(count) then return end
    local panel = self.copyDialog or CreateCopyDialog()
    self.copyDialog = panel
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
