local _, P = ...
local T, M, Tr = P.T, P.M, P.Tr
local Samples = {}
P.MenuSamples = Samples

local function Text(parent, value, x, y, width)
    return P.Text(parent, value, x, y, width, T.colors.text)
end

local function Target(parent, x, y, width, height, open)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetSize(width, height)
    button:SetScript("OnClick", open)
    P.HM.SkipHistoryCheckpoint(button)
    return button
end

local function Fill(texture, hex, alpha)
    local r, g, b = P.RGB(hex)
    texture:SetColorTexture(r, g, b, alpha or 1)
end

local function Plate(parent)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(parent)
    return texture
end

local function Watch(ui, paint, footer, top)
    local function Refresh()
        paint()
        P.MenuWorkspace.FitHeader(ui, top + math.ceil(footer:GetStringHeight() or 14) + 16)
    end
    ui.refreshPreview = Refresh
    M.TrackRefresh(ui.ctx, function() if ui.header:IsVisible() then Refresh() end end)
    Refresh()
end

function Samples.Bags(ui)
    if not ui then return end
    local parent, width = ui.header, ui.width - 32
    local window = Target(parent, 16, -52, width, 124, function() ui:Focus("suite_bags_appearance") end)
    local background = Plate(window)
    local title = Text(window, "Bags", 12, -8, width - 24)
    local sidebar = Target(window, 8, -32, math.min(112, width * .3), 80,
        function() ui:Focus("suite_bags_organisation") end)
    Text(sidebar, "Categories", 4, -6, sidebar:GetWidth() - 8)
    local slots = {}
    for i = 1, 8 do
        local slot = Target(window, 130 + (i - 1) * 34, -40, 30, 30,
            function() ui:Focus("suite_bags_itemLevels") end)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints(slot)
        slot.icon:SetTexture(134400)
        slot.level = Text(slot, "450", 0, -2, 30)
        slots[i] = slot
    end
    local footer = Text(parent, "Sample values. Click an element to open its settings.", 16, -184, width)
    Watch(ui, function()
        local c = P.S.Config("bags")
        Fill(background, c.backgroundColor, (c.backgroundOpacity or 80) / 100)
        local bank = ui.selected == "bank"
        P.SetTranslatedText(title, bank and Tr("Bank organisation") or Tr("Bags"))
        sidebar:SetShown(c.inventoryView == 3)
        local start = c.inventoryView == 3 and math.min(128, width * .32) or 12
        local count = math.max(1, math.min(8, math.floor((width - start - 12) / 34)))
        for i, slot in ipairs(slots) do
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", window, "TOPLEFT", start + (i - 1) * 34, -40)
            slot:SetShown(i <= count)
            slot.level:SetShown(bank and c.showBankItemLevel or not bank and c.showItemLevel)
            P.StylePreviewFont(slot.level, c.itemLevelFont, c.itemLevelSize or 12, "OUTLINE", c.fontRendering)
        end
    end, footer, 184)
end

local function MeterText(label, c, size)
    local outlines = { "", "OUTLINE", "THICKOUTLINE", "", "OUTLINE", "THICKOUTLINE" }
    local shadow = c.outline == 1 or c.outline == 5 or c.outline == 6
    P.StylePreviewFont(label, c.font, size, outlines[c.outline] or "", c.rendering,
        shadow, c.shadowOpacity, c.shadowDistance)
end

local METER_CLASSES = { "c79c6e", "69ccf0", "f58cba" }
local function PaintMeterRow(row, c, index, width, top)
    local height, spacing = c.barHeight or 18, c.barSpacing or 2
    row:SetShown(index <= math.max(1, math.floor((122 - top) / (height + spacing))))
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 6, -top - (index - 1) * (height + spacing))
    Fill(row.track, c.trackColor, (c.trackAlpha or 40) / 100)
    row.fill:SetTexture(P.Suite.ResolveTexture(c.barTexture, "Interface\\Buttons\\WHITE8X8"))
    local r, g, b = P.RGB(c.classColors and METER_CLASSES[index] or c.barColor)
    row.fill:SetVertexColor(r, g, b, (c.barAlpha or 100) / 100)
    row.fill:SetSize((width - 12) * (1 - (index - 1) * .22), height)
    MeterText(row.left, c, c.leftSize or 11)
    MeterText(row.right, c, c.rightSize or 11)
    r, g, b = P.RGB(c.leftClassColor and METER_CLASSES[index] or c.leftColor)
    row.left:SetTextColor(r, g, b, (c.textOpacity or 100) / 100)
    r, g, b = P.RGB(c.rightClassColor and METER_CLASSES[index] or c.rightColor)
    row.right:SetTextColor(r, g, b, (c.textOpacity or 100) / 100)
end

function Samples.Meter(ui, selected, setSelected)
    if not ui then return end
    local width = ui.width - 32
    local choices = {}
    for i = 1, P.Suite.DamageMeterMaxWindows do choices[i] = { value = i, text = Tr("Window %d"):format(i) } end
    local picker = M.BindDropdownAt(ui.ctx, ui.header, Tr("Window"), 16, -42, choices, width,
        selected, setSelected, P.Meta("suite_damageMeter", "damageMeter", "window.selected", "ephemeral", "suite_damageMeter_windows"))
    ui.ctx.meterWindowPicker = picker
    P.HM.SetSearchTargetPrepare(picker, function() ui.select("window")
        return true end)
    local window = Target(ui.header, 16, -94, width, 122, function() ui:Focus("suite_damageMeter_windows") end)
    local background = Plate(window)
    local header = Target(window, 0, 0, width, 22, function() ui:Focus("suite_damageMeter_window") end)
    local head = Plate(header)
    local title = Text(header, "Damage meter", 8, -4, width - 16)
    local rows = {}
    for i = 1, 3 do
        local row = Target(window, 6, -26 - (i - 1) * 25, width - 12, 20,
            function() ui:Focus("suite_damageMeter_bars") end)
        row.track, row.fill = Plate(row), row:CreateTexture(nil, "ARTWORK")
        row.fill:SetPoint("TOPLEFT")
        row.left = Text(row, Tr("Player %d"):format(i), 4, -2, (width - 24) / 2)
        row.right = Text(row, "125.0K", (width - 24) / 2, -2, (width - 24) / 2)
        row.right:SetJustifyH("RIGHT")
        rows[i] = row
    end
    local scope = Text(ui.header, "", 16, -224, width)
    Watch(ui, function()
        local c, index = P.S.Config("damageMeter"), selected()
        Fill(background, c.bgColor, (c.bgAlpha or 80) / 100)
        Fill(head, c.headerColor, (c.headerAlpha or 90) / 100)
        local meter = P.Suite.DamageMeterTypeLabels[c["w" .. index .. "Type"] or 1]
        P.SetTranslatedText(title, Tr("Window %d"):format(index) .. " · " .. Tr(meter))
        header:SetHeight(c.headerHeight or 22)
        MeterText(title, c, c.headerFontSize or 11)
        local r, g, b = P.RGB(c.titleColor)
        title:SetTextColor(r, g, b, (c.textOpacity or 100) / 100)
        for i, row in ipairs(rows) do
            PaintMeterRow(row, c, i, width, (c.headerHeight or 22) + 4)
        end
        local description = ui.selected == "window" and Tr("Only the selected window") or Tr("Applies to all windows")
        P.SetTranslatedText(scope, description .. "\n" .. Tr("Sample values. Click an element to open its settings."))
    end, scope, 224)
end
