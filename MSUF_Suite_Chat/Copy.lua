local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Opt-in copy chooser: a Copy button on each chat window opens one shared
-- dialog listing the window's recent public lines. Choosing a line puts its
-- plain text into an edit box, ready for Ctrl+C. Nothing reads the chat
-- until the button is clicked.
local M = C.M
local ROWS = 10
local TEXT = {
    copy = S.Text("Copy"),
    copyTooltip = S.Text("Copy a recent chat message"),
    copyTitle = S.Text("Copy chat message (drag to move)"),
    copyHint = S.Text("Choose a line, then press Ctrl+C"),
    copyEmpty = S.Text("No recent messages to copy"),
}
local Fill, Tint, ShowTooltip, HideTooltip = C.Fill, C.Tint, C.ShowTooltip, C.HideTooltip

local function PlainMessage(text)
    -- GetMessageInfo returns Blizzard's rendered line, including a timestamp
    -- if its native setting is enabled. Present readable text in the copy box.
    local plain = text:gsub("|H.-|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return plain
end

-- Also clears the chosen text, so a closed dialog keeps no chat content.
local function HideCopyDialog(panel)
    if not panel then return end
    panel:Hide()
    panel.edit:ClearFocus()
    panel.edit:SetText("")
    for _, row in ipairs(panel.rows) do
        row.message = nil
        row.label:SetText("")
        row:Hide()
    end
end
C.HideCopyDialog = HideCopyDialog

-- A dedicated title drag area leaves message rows and the copy edit box
-- free for clicks, selection and Ctrl+C.
local function CreateCopyHeader(panel)
    local dragHandle = S.CreateFrame("Button", nil, panel)
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, 0)
    dragHandle:SetHeight(56)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() panel:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    panel.dragHandle = dragHandle
    local title = S.CreateFontString(dragHandle, nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", dragHandle, "TOPLEFT", 15, -13)
    title:SetText(TEXT.copyTitle)
    local hint = S.CreateFontString(dragHandle, nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", dragHandle, "TOPLEFT", 15, -36)
    hint:SetText(TEXT.copyHint)
    panel.hint = hint
    local close = S.CreateFrame("Button", nil, panel)
    close:SetSize(24, 22)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    local closeLabel = S.CreateFontString(close, nil, "ARTWORK", "GameFontNormal")
    closeLabel:SetPoint("CENTER", close, "CENTER")
    closeLabel:SetText("X")
    close:SetScript("OnClick", function() HideCopyDialog(panel) end)
end

local function CopyRowClick(row)
    if not row.message then return end
    local edit = row.panel.edit
    edit:SetText(row.message)
    edit:SetFocus()
    edit:HighlightText()
end

local function CreateCopyRows(panel)
    panel.rows = {}
    for i = 1, ROWS do
        local row = S.CreateFrame("Button", nil, panel)
        row.panel = panel
        row:SetSize(410, 23)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, -61 - (i - 1) * 25)
        local shade = Fill(row, "BACKGROUND")
        shade:SetAllPoints(row)
        Tint(shade, i % 2 == 0 and "252a2d" or "1d2225", 100)
        local label = S.CreateFontString(row, nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 7, 0)
        label:SetWidth(394)
        label:SetJustifyH("LEFT")
        label:SetMaxLines(1)
        row.label = label
        row:SetScript("OnClick", CopyRowClick)
        panel.rows[i] = row
    end
end

local function CreateCopyDialog()
    local panel = S.CreateFrame("Frame", nil, UIParent)
    panel:SetSize(440, 345)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    local background = Fill(panel, "BACKGROUND")
    background:SetAllPoints(panel)
    Tint(background, "151719", 97)
    CreateCopyHeader(panel)
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(400, 25)
    edit:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() HideCopyDialog(panel) end)
    panel.edit = edit
    CreateCopyRows(panel)
    panel:Hide()
    return panel
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
