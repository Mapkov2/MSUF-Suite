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

-- A movable Suite-owned window with a title, a drag strip (panel.dragHandle)
-- and a close button (panel.close).
function S.QoLWindow(width, height, title, titleSize)
    local panel = S.CreateFrame("Frame", nil, UIParent)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    local background = S.CreateTexture(panel, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.065, .075, .085, .97)
    local accent = S.CreateTexture(panel, nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(.8, .68, .42, 1)
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
