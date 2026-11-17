local _, P = ...
local M, W, SB = P.M, P.W, P.M.PreviewSelectionBar
local Layout = {}
P.NameplatesPreviewLayout = Layout

local TOOL_HEIGHT, TOOL_GAP = 20, 6
local LABEL_INSET = 8

function Layout.StyleButton(button)
    local label = P.HM.GetControlLabel(button)
    if not label then return end
    label:ClearAllPoints()
    label:SetPoint("LEFT", button, "LEFT", LABEL_INSET, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -LABEL_INSET, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
end

local function TextWidth(label)
    local measure = label and (label.GetUnboundedStringWidth or label.GetStringWidth)
    return measure and math.ceil(measure(label)) or 0
end

function Layout.FitButton(button, available, minimum)
    local width = math.min(available, math.max(minimum, TextWidth(P.HM.GetControlLabel(button)) + 2 * LABEL_INSET + 4))
    button:SetWidth(width)
    return width
end

local function PlaceTool(control, tools, point, x, y)
    control:ClearAllPoints()
    control:SetPoint(point, tools, point, x, y)
end

function Layout.Tools(ui)
    local tools, width = ui.tools, ui.body:GetWidth()
    if not width or width < 1 then return end
    local x, y = 0, 0
    local step = TOOL_HEIGHT + TOOL_GAP
    for _, entry in ipairs(ui.zoomControls) do
        local control, minimum = entry[1], entry[2]
        local size
        if control == ui.zoomLabel then
            size = math.min(width, math.max(minimum, TextWidth(control) + 4))
            control:SetWidth(size)
        else
            size = Layout.FitButton(control, width, minimum)
        end
        if x + size > width then x, y = 0, y - step end
        PlaceTool(control, tools, "TOPLEFT", x, control == ui.zoomLabel and y - 4 or y)
        x = x + size + TOOL_GAP
    end
    local pickerSize = Layout.FitButton(ui.elementPicker, width, 96)
    local pickerWrapped = x + pickerSize > width
    if pickerWrapped then y = y - step end
    PlaceTool(ui.elementPicker, tools, "TOPRIGHT", 0, y)

    local targetSize = Layout.FitButton(ui.targetStateButton, width, 126)
    local focusSize = Layout.FitButton(ui.focusStateButton, width, 96)
    if targetSize + TOOL_GAP + focusSize <= width then
        y = y - step
        PlaceTool(ui.targetStateButton, tools, "TOPRIGHT", -focusSize - TOOL_GAP, y)
    elseif pickerWrapped and targetSize + TOOL_GAP + pickerSize <= width then
        PlaceTool(ui.targetStateButton, tools, "TOPRIGHT", -pickerSize - TOOL_GAP, y)
        y = y - step
    else
        PlaceTool(ui.targetStateButton, tools, "TOPRIGHT", 0, y - step)
        y = y - 2 * step
    end
    PlaceTool(ui.focusStateButton, tools, "TOPRIGHT", 0, y)
    tools:SetHeight(TOOL_HEIGHT - y)
end

function Layout.Samples(ui)
    Layout.Tools(ui)
    local width, height = ui.canvas:GetWidth(), ui.canvas:GetHeight()
    if not width or width <= 24 or not height or height <= 0 then return end
    local firstRow = width - (ui.backgroundButton and ui.backgroundButton:GetWidth() + 22 or 16)
    local x, y, available = 0, 0, firstRow
    for _, button in ipairs(ui.sampleButtons) do
        if button:IsShown() then
            local size = Layout.FitButton(button, width - 16, 20)
            if x + size > available then
                x, y, available = 0, y - 24, width - 16
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", ui.samples, "TOPLEFT", x, y)
            x = x + size + 5
        end
    end
    ui.samples:SetSize(width - 16, 20 - y)
    local raidTop = math.min(42 - y, math.max(8, height - ui.raidPalette:GetHeight() - 4))
    ui.raidPalette:ClearAllPoints()
    ui.raidPalette:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -8, -raidTop)
end

function Layout.Apply(self)
    local body, canvas, tools, rail = self.body, self.canvas, self.tools, self.layerRail
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    local editing = not self.compact and not self.groupPreviewEnabled
    tools:SetShown(editing)
    if SB then SB.SetShown(body, editing) end
    rail:SetShown(editing)
    self.samples:SetShown(editing)
    self.raidPalette:SetShown(editing)
    self.hint:SetShown(editing)
    if not editing then
        canvas:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
        return
    end
    self:LayoutLayerRail()
    -- Anchor each row above the actual wrapped rail, leaving all remaining
    -- height to the canvas. Width changes therefore need no guessed row count.
    local anchor = rail
    if self.selection then
        self.selection:ClearAllPoints()
        self.selection:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 0, 6)
        self.selection:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 6)
        anchor = self.selection
    end
    tools:ClearAllPoints()
    tools:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 5)
    tools:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 5)
    canvas:SetPoint("BOTTOMRIGHT", tools, "TOPRIGHT", 0, 4)
    Layout.Samples(self)
end

function Layout.Attach(ui, section, toolbar, record)
    local body, ctx = ui.body, ui.ctx
    local function Refresh()
        ui:Layout()
        ui:Paint()
    end
    body.Refresh = Refresh
    function body:ApplyCompactPreviewPresentation(compact)
        compact = compact == true
        -- Settings links and header resizing reapply the current presentation.
        -- Keep the selected element and its X/Y input during a reflow.
        if ui.compact ~= compact then
            ui:CancelDrag()
            ui:Select(nil)
            ui.compact = compact
        end
        Refresh()
    end
    -- Use the same page ownership lifecycle as UF/GF. The fixed section owns
    -- the header anchor; scrolling only moves the settings wrapper below it.
    if W.AttachPinnedPreview then
        W.AttachPinnedPreview(section, body, { stateKey = "nameplatePreview",
            pageKey = ctx.key, wrapper = ctx.wrapper })
    end
    local expander
    if W.AttachFixedPreviewExpander then
        expander = W.AttachFixedPreviewExpander(section, toolbar, body, {
            pageKey = ctx.key, wrapper = ctx.wrapper,
            compactHeight = 116, compactTop = -38,
            expandedHeight = 480, expandedTop = -38, expandedSectionHeight = 526,
            refreshPreview = Refresh,
        })
    end
    ui.expander = expander
    if expander and expander.button then
        ui.hint:ClearAllPoints()
        ui.hint:SetPoint("LEFT", section.title or toolbar, section.title and "RIGHT" or "LEFT", section.title and 12 or 160, 0)
        ui.hint:SetPoint("RIGHT", expander.button, "LEFT", -124, 0)
    end
    -- FixedPreviewSection reserves the compact height on construction. The
    -- expander registers controls but does not initialize their presentation.
    -- Initialize before activation even if another page selected Compact.
    if ui.groupPreviewButton then
        ui.groupPreviewButton:ClearAllPoints()
        ui.groupPreviewButton:SetPoint("RIGHT", expander and expander.button or toolbar, expander and "LEFT" or "RIGHT", -8, 0)
    end
    body:ApplyCompactPreviewPresentation(expander ~= nil)
    body:SetScript("OnSizeChanged", Refresh)
    body:SetScript("OnShow", Refresh)
    if record then
        record.onActivate = function()
            -- Ownership settling can hide the body before the wrapper shows.
            -- Compact activation must wake it just as the expander does.
            body:SetFrameLevel(section:GetFrameLevel() + 2)
            body:Show()
            if expander and expander.expanded then expander:Relayout("NAMEPLATES_PREVIEW") end
            Refresh()
        end
    end
end
