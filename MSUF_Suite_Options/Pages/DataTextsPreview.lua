local _, P = ...
local Suite, S, M, T, Tr = P.Suite, P.S, P.M, P.T, P.Tr
local Data = P.DataTextsPreviewData
local Preview = {}
P.DataTextsPreview = Preview
local ID, PAGE = "dataTexts", "suite_dataTexts"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local EMPTY_CONFIG = {}
local BADGE = "Interface\\AddOns\\MSUF_Suite_DataTexts\\Media\\BagMedallion.tga"
local OUTLINES, ALIGN = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }, { "LEFT", "CENTER", "RIGHT" }
local DOCK = Suite.DataTextDock
local DOCK_POINTS = { [DOCK.TOP] = "TOP", [DOCK.BOTTOM] = "BOTTOM", [DOCK.LEFT] = "LEFT", [DOCK.RIGHT] = "RIGHT" }
local EDGE_POINTS = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }

local function Edges(parent, layer)
    local edges = {}
    for i, points in ipairs(EDGE_POINTS) do
        local edge = parent:CreateTexture(nil, layer or "OVERLAY")
        edge:SetPoint(points[1], parent, points[1])
        edge:SetPoint(points[2], parent, points[2])
        edges[i] = edge
    end
    return edges
end

local function Border(edges, color, size, shown, alpha)
    local r, g, b = P.RGB(color)
    for i, edge in ipairs(edges) do
        edge:SetColorTexture(r, g, b, alpha or 1)
        if i <= 2 then edge:SetHeight(size) else edge:SetWidth(size) end
        edge:SetShown(shown)
    end
end

local function Metadata(ui, button, key, label)
    if ui.options.interactive == false or not M.RegisterControlMetadata then return end
    local identity = "bar" .. ui.bar .. key
    if button.previewMetadataKey == identity then return end
    button.previewMetadataKey = identity
    M.RegisterControlMetadata(button, P.Meta(PAGE, ID, identity, "ephemeral", PAGE .. "_bar" .. ui.bar),
        label, "button")
end

local function Selection(ui)
    local selected = ui.options.selectedSlot
    if type(selected) == "function" then return selected() end
    return ui.selectedSlot or selected
end

local function Highlight(ui, button)
    local selected = ui.options.interactive ~= false and Selection(ui) == button.slot
    local thickness = 2 * ui.pixel / math.max(.01, (ui.fit or 1) * (button.slotScale or 1))
    Border(button.edges, "57c7df", thickness, selected)
    button.hover:SetShown(button.hovered and not selected)
end

local function NewSlot(ui, index)
    local button = CreateFrame("Button", nil, ui.sample)
    button.slot = index
    button.fill = button:CreateTexture(nil, "BACKGROUND")
    button.fill:SetAllPoints(button)
    button.hover = button:CreateTexture(nil, "HIGHLIGHT")
    button.hover:SetAllPoints(button)
    button.hover:SetColorTexture(.34, .78, .87, .12)
    button.edges = Edges(button)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetWordWrap(false)
    button.label:SetTextColor(1, 1, 1)
    button.divider = ui.sample:CreateTexture(nil, "ARTWORK")
    button._msuf2SkipHistoryCheckpoint = true
    button._msuf2AllowCombatClick = true
    button:EnableMouse(ui.options.interactive ~= false)
    if ui.options.interactive == false then return button end
    button:SetScript("OnEnter", function()
        button.hovered = true
        Highlight(ui, button)
    end)
    button:SetScript("OnLeave", function()
        button.hovered = nil
        Highlight(ui, button)
    end)
    button:SetScript("OnClick", function()
        if ui.disposed then return end
        ui.selectedSlot = index
        if ui.options.onSelect then ui.options.onSelect(index) end
        ui:Refresh()
    end)
    return button
end

local function PaintBackdrop(ui, style, inset)
    local fade = style.backgroundEnabled and style.backgroundGradient
    ui.fill:SetTexture(Suite.ResolveTexture(style.backgroundTexture) or WHITE)
    local r, g, b = P.RGB(style.backgroundColor)
    ui.fill:SetVertexColor(r, g, b, style.backgroundOpacity / 100)
    ui.fill:SetShown(style.backgroundEnabled and not fade)
    ui.gradient:SetShown(fade == true)
    if fade then
        local fr, fg, fb = P.RGB(style.backgroundFadeColor)
        local opacity = style.backgroundOpacity / 100
        ui.gradient:SetGradient("VERTICAL", CreateColor(fr, fg, fb, opacity), CreateColor(r, g, b, opacity))
    end
    Border(ui.edges, style.borderColor, style.borderSize * ui.pixel, style.borderEnabled, .85)
    ui.accent:SetShown(style.accentEnabled)
    ui.accent:ClearAllPoints()
    local top = style.accentPosition == Suite.DataTextAccentPosition.TOP
    local point = top and "TOP" or "BOTTOM"
    ui.accent:SetPoint(point .. "LEFT", ui.sample, point .. "LEFT", top and inset or 0, 0)
    ui.accent:SetPoint(point .. "RIGHT", ui.sample, point .. "RIGHT")
    ui.accent:SetHeight(ui.pixel)
    local ar, ag, ab = P.RGB(style.accentColor)
    ui.accent:SetColorTexture(ar, ag, ab, .9)
    ui.badge:SetShown(style.bagBadge)
    ui.badge:SetSize(style.bagBadgeSize, style.bagBadgeSize)
    ui.badge:ClearAllPoints()
    ui.badge:SetPoint("LEFT", ui.sample, "LEFT", Data.Snap(4, ui.pixel), 0)
end

local function Entries(ui, config, style)
    local entries, prefix = {}, "bar" .. ui.bar .. "Slot"
    local font = Suite.ResolveFont(style.font) or Suite.GlobalFontPath()
    for slot = 1, ui.maxSlots do
        local button, block = ui.slots[slot], prefix .. slot
        local choice = config[block]
        local source = choice and Suite.DataTextSourceKeys[choice]
        button:SetShown(source ~= nil and source ~= false)
        button.divider:Hide()
        if source then
            P.StylePreviewFont(button.label, font, style.fontSize, OUTLINES[style.textOutline] or "OUTLINE",
                style.fontRendering, style.fontShadow, style.fontShadowOpacity, style.fontShadowDistance)
            button.label:SetJustifyH(ALIGN[style.textAlign] or "CENTER")
            button.label:SetText(Data.Text(source, style, config, block))
            entries[#entries + 1] = { button = button, block = block, textWidth = button.label:GetUnboundedStringWidth(),
                placement = config[block .. "Placement"], limit = source == "broker" and config[block .. "MaxWidth"] or nil }
            Metadata(ui, button, "Slot" .. slot .. ".preview", Tr("Choose data for place %d"):format(slot))
        end
    end
    return entries
end

local function PaintSlot(ui, entry, config, style, ordinal, count, vertical, width, height)
    local button, block, pixel = entry.button, entry.block, ui.pixel
    local scale = (config[block .. "Scale"] or 100) / 100
    local left = Data.Snap(entry.offset, pixel)
    local right = Data.Snap(entry.offset + entry.length, pixel)
    button.slotScale = scale
    button:SetScale(scale)
    button:ClearAllPoints()
    if vertical then
        button:SetPoint("TOP", ui.sample, "TOP", 0, -left / scale)
        button:SetSize(width / scale, math.max(1, right - left) / scale)
    else
        button:SetPoint("LEFT", ui.sample, "LEFT", left / scale, 0)
        button:SetSize(math.max(1, right - left) / scale, height / scale)
    end
    local available = vertical and width / scale or (right - left) / scale
    local padding = math.max(0, math.min(config[block .. "Padding"] or style.padding, (available - 4) / 2))
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", padding, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -padding, 0)
    local r, g, b = P.RGB(config[block .. "Background"] or "101010")
    button.fill:SetColorTexture(r, g, b, (config[block .. "Alpha"] or 0) / 100)
    Highlight(ui, button)
    local divider = button.divider
    divider:SetShown(style.separatorEnabled and ordinal < count)
    divider:ClearAllPoints()
    local offset = Data.Snap(right + style.gap / 2, pixel)
    local length = math.max(6, (vertical and width or height) - 2 * style.padding)
    if vertical then
        divider:SetPoint("CENTER", ui.sample, "TOP", 0, -offset)
        divider:SetSize(length, style.separatorSize * pixel)
    else
        divider:SetPoint("CENTER", ui.sample, "LEFT", offset, 0)
        divider:SetSize(style.separatorSize * pixel, length)
    end
    local sr, sg, sb = P.RGB(style.separatorColor)
    divider:SetColorTexture(sr, sg, sb, .8)
end

local function ValueColor(style)
    if not style.valueClassColor then return end
    local _, class = UnitClass("player")
    if Suite.IsSecret(class) or not class then return end
    if S.ClassHex then
        style.valueColor = S.ClassHex(class) or style.valueColor
    else
        local color = C_ClassColor.GetClassColor(class)
        if color then style.valueColor = color:GenerateHexColor():sub(3) end
    end
end

local function ReadConfig(ui)
    local config = ui.options.config
    if config == nil then return S.Config(ID) end
    if type(config) == "function" then config = config() end
    return type(config) == "table" and config or EMPTY_CONFIG
end

local function PlaceSample(ui, config, prefix)
    local point, x, y = "CENTER", 0, 8
    if ui.options.compact then
        point = DOCK_POINTS[config[prefix .. "Dock"]] or Suite.DataTextPoints[config[prefix .. "Point"]] or point
        x = point:find("LEFT", 1, true) and 12 or point:find("RIGHT", 1, true) and -12 or 0
        y = point:find("TOP", 1, true) and -8 or point:find("BOTTOM", 1, true) and 8 or 0
        x, y = x / ui.fit, y / ui.fit
    end
    ui.sample:ClearAllPoints()
    ui.sample:SetPoint(point, ui.host, point, x, y)
end

local function Paint(ui)
    if ui.disposed or not ui.host:IsVisible() then return end
    local bar = ui.barId
    if type(bar) == "function" then bar = bar() end
    if not bar then
        ui.sample:Hide()
        ui.add:Hide()
        return
    end
    ui.bar = bar
    ui.rawConfig = ReadConfig(ui)
    local config, prefix = ui.config, "bar" .. bar
    local style = Suite.DataTextEffectiveStyle(config, bar)
    local vertical = config[prefix .. "Vertical"] == true
    if vertical then style.bagBadge = false end
    ValueColor(style)
    ui.pixel = S.PixelUnit and S.PixelUnit() or 1
    local entries = Entries(ui, config, style)
    local span = vertical and UIParent:GetHeight() or UIParent:GetWidth()
    local width, height, inset = Data.Layout(entries, config, bar, style, ui.pixel, span)
    local badge = style.bagBadge and style.bagBadgeSize or 0
    local availableHeight = ui.height - (ui.options.compact and 16 or 86)
    local fit = math.min(1, (ui.width - 24) / math.max(1, width), availableHeight / math.max(1, height, badge))
    ui.fit = math.max(.01, fit)
    ui.sample:SetSize(width, height)
    ui.sample:SetScale(ui.fit)
    PlaceSample(ui, config, prefix)
    ui.sample:Show()
    PaintBackdrop(ui, style, inset)
    for i, entry in ipairs(entries) do PaintSlot(ui, entry, config, style, i, #entries, vertical, width, height) end
    local status = config[prefix .. "Name"] or Tr("Bar %d"):format(bar)
    if config[prefix .. "FullScreen"] then status = Tr("%s - Full screen"):format(status) end
    if not config[prefix .. "Enabled"] then status = Tr("%s - Hidden"):format(status) end
    P.SetTranslatedText(ui.status, status)
    ui.empty:SetShown(#entries == 0)
    ui.add:SetShown(not ui.options.compact and ui.options.interactive ~= false and ui.options.onAdd ~= nil)
    ui.add:SetEnabled(#entries < ui.maxSlots and not P.Combat())
    Metadata(ui, ui.add, ".preview.add", Tr("Add data"))
    ui.entries = entries
end

local function MakeCanvas(ui)
    local sample = CreateFrame("Frame", nil, ui.host)
    sample:SetPoint("CENTER", ui.host, "CENTER", 0, ui.options.compact and 0 or 8)
    ui.sample = sample
    ui.fill = sample:CreateTexture(nil, "BACKGROUND")
    ui.fill:SetAllPoints(sample)
    ui.gradient = sample:CreateTexture(nil, "BACKGROUND")
    ui.gradient:SetTexture(WHITE)
    ui.gradient:SetAllPoints(sample)
    ui.edges = Edges(sample, "BORDER")
    ui.accent = sample:CreateTexture(nil, "ARTWORK")
    ui.badge = sample:CreateTexture(nil, "OVERLAY")
    ui.badge:SetTexture(BADGE)
    for slot = 1, ui.maxSlots do ui.slots[slot] = NewSlot(ui, slot) end
end

local function Lifecycle(ui)
    function ui:Refresh() Paint(self) end
    function ui:SetBar(bar)
        self.barId = bar
        self:Refresh()
    end
    function ui:SetSelectedSlot(slot)
        self.selectedSlot = slot
        self:Refresh()
    end
    function ui:Dispose()
        self.disposed = true
        self.host:Hide()
    end
    ui.host:SetScript("OnShow", function() ui:Refresh() end)
    ui.host:SetScript("OnSizeChanged", function(_, width, height)
        ui.width, ui.height = width, height
        ui:Refresh()
    end)
    ui.host:SetScript("OnHide", function()
        for _, button in ipairs(ui.slots) do button.hovered = nil end
    end)
    M.TrackRefresh(ui.ctx, function() ui:Refresh() end)
end

local function ConfigView(ui)
    return setmetatable({}, { __index = function(_, key)
        local value = ui.rawConfig and ui.rawConfig[key]
        if value ~= nil then return value end
        local rule = P.catalog[ID].rules[key]
        return rule and rule.default
    end })
end

function Preview.Build(ctx, parent, barId, options)
    options = options or {}
    local width, height = options.width or 640, options.height or 180
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", options.x or 16, options.y or -16)
    host:SetSize(width, height)
    host:SetClipsChildren(true)
    local ui = { host = host, frame = host, barId = barId, options = options, ctx = ctx, slots = {}, pixel = 1,
        width = width, height = height, bottomY = (options.y or -16) - height,
        maxSlots = options.maxSlots or Suite.DataTextSlotLimit }
    ui.config = ConfigView(ui)
    local chrome = M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(host, "canvas", T) end
    ui.status = P.Text(host, "", 12, -10, width - 24, T.colors.text)
    local emptyText = options.compact and "Empty bar" or "Add your first data source to this bar."
    ui.empty = P.Text(host, emptyText, 12, -math.floor(height / 2), width - 24)
    ui.empty:SetJustifyH("CENTER")
    ui.hint = P.Text(host, "Sample values. Click a data text to edit it.", 12, -(height - 22), width - 174)
    ui.add = T.Button(host, "Add data", 136, 26)
    ui.add:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -10, 8)
    ui.add._msuf2SkipHistoryCheckpoint = true
    ui.add:SetScript("OnClick", function()
        if not ui.disposed and ui.options.interactive ~= false and not P.Combat() and ui.options.onAdd then
            ui.options.onAdd(ui.add)
        end
    end)
    ui.status:SetShown(not options.compact)
    ui.hint:SetShown(not options.compact)
    MakeCanvas(ui)
    Lifecycle(ui)
    ui:Refresh()
    return ui
end
