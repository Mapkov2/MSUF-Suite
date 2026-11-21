local _, P = ...

local Kit, M, T, HM, Tr = P.SkinPageKit, P.M, P.T, P.HM, P.Tr
local Interaction = P.PreviewInteraction
local STYLE, BUILDER = "suite_skin_tooltips", "suite_skin_tooltip_builder"
local LAYOUT = "theme.tooltipLayout."
local SAMPLE_CHROME = { role = "popup", radius = 0, opaqueFill = true }
local AXES = { 4, 22, -5, 5 }
local SAMPLES = {
    { id = "item", label = "Items", name = function() return Tr("Trailblazer's cloak") end,
        icon = 133754, kind = function() return Tr("Back") end, level = 60, color = 3,
        rows = { { "Armor", "38" }, { "Intellect", "+12" }, { "Stamina", "+9" } } },
    { id = "spell", label = "Spells", name = function() return Tr("Frostbolt") end,
        icon = 135846, kind = function() return Tr("Spell") end,
        rows = { { "Cast time", "2.0 s" }, { "Range", function() return Tr("40 yd") end },
            { "School", function() return Tr("Frost") end } } },
    { id = "unit", label = "Units", name = function() return Tr("Player Name") end,
        color = { r = .25, g = .78, b = .92 },
        rows = { { "Level 80 Human Paladin", "" }, { "Alliance", "" }, { "Health", "100%" } } },
    { id = "loot", label = "Loot", name = function() return Tr("Trailblazer's cloak") end,
        icon = 133754, kind = function() return Tr("Back") end, level = 60, color = 3 },
}
local LAYERS = {
    { "header", "Header", "headerColor" }, { "title", "Title", "tint", true },
    { "icon", "Icon", "iconSize", true }, { "data", "Details", "level" },
    { "rule", "Accent line", "rule" }, { "border", "Tooltip frame", "borderMode" },
}

local function IsDetailed(preview, sample)
    return preview.card.TypeStyle(sample.id) == "custom"
end

local function Open(preview, spec)
    local field = spec and spec[3]
    local sample = SAMPLES[preview.selected]
    if sample.id == "loot" and (not field or field == "iconSize" or not IsDetailed(preview, sample)) then
        return preview.ui:Focus(STYLE)
            and P.Suite.HostBridge.OpenExactMenuSetting(M, "suite_skin", STYLE, "msufsuite.skin." .. LAYOUT .. "lootStyle")
    end
    local section = field and BUILDER or STYLE
    if not preview.ui:Focus(section) then return false end
    if not field or field == "headerColor" then return true end
    return P.Suite.HostBridge.OpenExactMenuSetting(M, "suite_skin", section, "msufsuite.skin." .. LAYOUT .. field)
end

local function Put(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
end

local function Sample(preview)
    local frame = CreateFrame("Frame", nil, preview.stage)
    frame:SetPoint("CENTER")
    preview.skin.Surface.Attach(frame, SAMPLE_CHROME)
    preview.frame = frame
    local card = preview.card.Create(frame)
    card.frame:SetPoint("TOPLEFT")
    card.frame:SetPoint("TOPRIGHT")
    preview.header = card
    preview.outline = preview.card.CreateOutline(frame)
    preview.outline.frame:SetFrameLevel(frame:GetFrameLevel() + 8)
    local compact = frame:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    compact:SetPoint("TOPLEFT", 14, -11)
    compact:SetPoint("TOPRIGHT", -12, -11)
    compact:SetJustifyH("LEFT")
    compact:SetWordWrap(false)
    preview.compact = compact
    local lootFill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    lootFill:SetAllPoints()
    lootFill:SetAtlas("looting_itemcard_bg")
    local lootEdge = frame:CreateTexture(nil, "BORDER")
    lootEdge:SetAllPoints()
    lootEdge:SetAtlas("looting_itemcard_stroke_normal")
    local lootIcon = frame:CreateTexture(nil, "ARTWORK")
    lootIcon:SetPoint("LEFT", 6, 0)
    lootIcon:SetSize(36, 36)
    lootIcon:SetTexCoord(.07, .93, .07, .93)
    preview.lootFill, preview.lootEdge, preview.lootIcon = lootFill, lootEdge, lootIcon
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 14, -57)
    body:SetPoint("BOTTOMRIGHT", -14, 9)
    preview.body = body
    local rows = {}
    for index = 1, 3 do
        local y = -(index - 1) * 19
        local label = body:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        local value = body:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        label:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        label:SetPoint("TOPRIGHT", body, "TOPRIGHT", -58, y)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        value:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
        value:SetTextColor(.62, .83, 1)
        rows[index] = { label, value }
    end
    preview.rows = rows
end

local function LayerTargets(preview)
    local header = preview.header
    return { header = header.frame, title = header.title, icon = header.icon, data = preview.body,
        rule = header.rule, border = preview.outline.edges[1] }
end

local function PlaceHit(handle, region)
    handle:ClearAllPoints()
    handle:SetAllPoints(region)
end

local Layout
local function Movable(preview, handle)
    return handle and handle.spec[4] and handle:IsVisible() and preview.header.frame:IsShown()
        and (handle.spec[1] ~= "icon" or SAMPLES[preview.selected].id ~= "loot")
end

local function Highlight(preview, handle)
    local selection = preview.selection
    if selection then
        local show = Movable(preview, handle) == true
        if selection:IsShown() ~= show then
            selection:SetShown(show)
            preview.bar:SetShown(not show)
            Layout(preview)
        end
        if show then M.PreviewSelectionBar.Refresh(preview.stage) end
    end
    local open
    if handle then open = handle.open end
    Interaction.Select(preview.bar, handle, handle and handle.spec[2], open)
end

local function ReadOffsets(preview)
    return preview.card.Setting("x"), preview.card.Setting("y")
end

local function WriteOffsets(preview, x, y)
    if P.Combat() or not preview.root:IsVisible() then return false end
    return Kit.Change(preview.skin, "Tooltip builder", LAYOUT .. "position", function()
        return preview.card.SetOffsets(x, y)
    end)
end

local function BuildHandles(preview)
    local stage, card = preview.stage, preview.card
    preview.kit = Interaction.Handles(preview.host, {
        owner = stage, manualDrag = true, escape = function() preview.kit:Release() end,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        click = function(handle, _, moved)
            if not moved then handle.open() end
        end,
        select = function(handle) Highlight(preview, handle) end,
        drag = function(_, phase)
            if phase == "press" then preview.dragProfile, preview.dragDatabase = P.ProfileGuard(), preview.skin.DB end
            if phase == "done" or phase == "cancel" then preview.dragProfile, preview.dragDatabase = nil, nil end
        end,
    })
    local targets = LayerTargets(preview)
    local function Read() return ReadOffsets(preview) end
    local function Write(x, y, dragged)
        if dragged and not (preview.dragProfile and preview.dragProfile() and preview.dragDatabase == preview.skin.DB) then return false end
        return WriteOffsets(preview, x, y)
    end
    local function Follow(_, dx, dy)
        local x, y = Read()
        card.PlaceContent(preview.header, math.max(AXES[1], math.min(AXES[2], x + dx)),
            math.max(AXES[3], math.min(AXES[4], y + dy)))
    end
    for index, spec in ipairs(LAYERS) do
        local key = spec[1]
        local handle = CreateFrame("Button", nil, stage)
        handle:SetFrameLevel(stage:GetFrameLevel() + 14 + index)
        handle.spec, handle.open = spec, function() return Open(preview, spec) end
        PlaceHit(handle, targets[key])
        preview.handles[key] = handle
        preview.kit:Add(key, handle, spec[4] and Read or nil, spec[4] and Write or nil,
            spec[4] and { follow = Follow, can = function() return Movable(preview, handle) end } or nil)
        HM.SkipHistoryCheckpoint(handle)
    end
end

local function TrackInput(preview, input)
    if not input then return end
    input:HookScript("OnEditFocusGained", function()
        preview.axisProfile, preview.axisDatabase = P.ProfileGuard(), preview.skin.DB
    end)
    input:HookScript("OnHide", function() preview.axisProfile, preview.axisDatabase = nil, nil end)
end

local function BuildSelection(preview)
    if not M.PreviewSelectionBar then return end
    local selection = M.PreviewSelectionBar.Create(preview.stage, {
        Tr = Tr, Theme = function() return T end,
        HandleList = function() return preview.kit.list end,
        HandleLabel = function(handle) return handle.spec[2] end,
        IsPlaced = function(handle) return Movable(preview, handle) == true end,
        ReadOffsets = function() return ReadOffsets(preview) end,
        WriteOffsets = function(_, handle, x, y, reason)
            if reason == "PREVIEW_EXACT_OFFSET" and not (preview.axisProfile and preview.axisProfile()
                and preview.axisDatabase == preview.skin.DB) then return false end
            if Movable(preview, handle) then return WriteOffsets(preview, x, y) end
        end,
        NudgeDelta = function(_, dx, dy) return preview.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, handle)
            if Movable(preview, handle) then return WriteOffsets(preview, 10, 0) end
        end,
        OpenSettings = function(_, handle) return handle.open() end,
        SelectHandle = function(_, handle) preview.kit:Select(handle) return true end,
    })
    preview.selection = selection
    selection:Hide()
    TrackInput(preview, selection.axisX.edit)
    TrackInput(preview, selection.axisY.edit)
end

local function PaintSample(preview, sample, rich)
    local card, loot = preview.card, sample.id == "loot"
    local header, layers = preview.header, preview.layers
    local hasHeader = layers.header and rich
    local name = sample.name()
    header.frame:SetPoint("TOPLEFT", preview.frame, "TOPLEFT", loot and 44 or 0, loot and -2 or 0)
    header.frame:SetPoint("TOPRIGHT", preview.frame, "TOPRIGHT", loot and -1 or 0, loot and -2 or 0)
    if rich then
        local icon = not loot and sample.icon or nil
        card.Draw(header, name, icon, sample.kind and sample.kind(),
            sample.level and Tr("Item level %d"):format(sample.level), sample.color, loot and 42 or nil)
    end
    header.frame:SetShown(hasHeader)
    header.icon:SetShown(not loot and hasHeader and layers.icon and sample.icon ~= nil and card.Setting("icon"))
    header.title:SetShown(hasHeader and layers.title)
    header.meta:SetShown(hasHeader and layers.data)
    header.rule:SetShown(hasHeader and layers.rule and card.Setting("rule"))
    preview.compact:SetPoint("TOPLEFT", loot and 50 or 14, loot and -14 or -11)
    preview.compact:SetText(name)
    preview.compact:SetShown(not rich and layers.header and layers.title)
    preview.skin.Surface.SetVisible(preview.frame, not loot)
    preview.lootFill:SetShown(loot)
    preview.lootEdge:SetShown(loot and layers.border and (not rich or card.Setting("borderMode") == "native"))
    preview.lootIcon:SetShown(loot and layers.icon)
    if loot then preview.lootIcon:SetTexture(sample.icon) end
    local height = rich and card.HeaderHeight() or 24
    preview.body:SetPoint("TOPLEFT", 14, -height - 10)
    preview.body:SetShown(not loot and layers.data)
    preview.frame:SetHeight(loot and 46 or height + 80)
    if not loot then
        for index, row in ipairs(preview.rows) do
            local data = sample.rows[index]
            row[1]:SetText(Tr(data[1]))
            local value = data[2]
            row[2]:SetText(type(value) == "function" and value() or value)
        end
    end
end

local function Paint(preview)
    if not preview.root:IsVisible() then return end
    local sample, card, header, layers = SAMPLES[preview.selected], preview.card, preview.header, preview.layers
    local loot, rich = sample.id == "loot", IsDetailed(preview, sample)
    PaintSample(preview, sample, rich)
    local handles = preview.handles
    PlaceHit(handles.title, rich and header.title or preview.compact)
    PlaceHit(handles.header, rich and header.frame or preview.compact)
    handles.header:SetShown(layers.header and rich)
    handles.title:SetShown(layers.header and layers.title)
    PlaceHit(handles.icon, loot and preview.lootIcon or header.icon)
    PlaceHit(handles.data, loot and header.meta or preview.body)
    handles.icon:SetShown(loot and preview.lootIcon:IsShown() or header.icon:IsShown())
    handles.rule:SetShown(header.rule:IsShown())
    handles.data:SetShown(layers.data and (not loot or rich and layers.header))
    local outline = preview.outline
    if rich and layers.border then card.PaintOutline(outline, preview.frame, preview.frame, header.r, header.g, header.b)
    else outline.frame:Hide() end
    if loot and preview.lootEdge:IsShown() then
        handles.border:ClearAllPoints()
        handles.border:SetPoint("TOPLEFT", preview.lootEdge)
        handles.border:SetPoint("TOPRIGHT", preview.lootEdge)
        handles.border:SetHeight(3)
    else PlaceHit(handles.border, outline.edges[1]) end
    handles.border:SetShown(outline.frame:IsShown() or loot and preview.lootEdge:IsShown())
    Interaction.Refresh(preview.bar)
    if preview.selection and preview.selection:IsShown() then M.PreviewSelectionBar.Refresh(preview.stage) end
    Interaction.RefreshLayerRail(preview)
end

Layout = function(preview)
    if not preview.root:IsShown() then return end
    local ui = preview.ui
    local full = ui.header:GetWidth()
    local width = math.max(204, (full and full > 100 and full or ui.width) - 32)
    local sidebar = width >= 630
    local rail = sidebar and math.floor(width * .36) or width
    local stage = sidebar and width - rail - 12 or width
    local y = -103
    Put(preview.stage, preview.root, 16, y, stage, 152)
    preview.frame:SetWidth(math.min(310, stage - 32))
    local railX, railY = sidebar and 28 + stage or 16, sidebar and y or y - 160
    preview.chips:ClearAllPoints()
    preview.chips:SetPoint("TOPLEFT", preview.root, "TOPLEFT", railX, railY)
    Interaction.LayoutLayerRail(preview, rail)
    local bottom = math.max(-y + 152, -railY + preview.chips:GetHeight())
    Interaction.SizeBar(preview.bar, width)
    Interaction.LayoutSelectionBar(preview.selection, width)
    local bar = preview.selection and preview.selection:IsShown() and preview.selection or preview.bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 16, -bottom - 7)
    P.MenuWorkspace.FitHeader(ui, bottom + bar:GetHeight() + 14)
    local cell = (width - (#SAMPLES - 1) * 6) / #SAMPLES
    for index, button in ipairs(preview.tabs) do Put(button, preview.root, 16 + (index - 1) * (cell + 6), -68, cell, 28) end
end

local function Build(ui, skin)
    local root = CreateFrame("Frame", nil, ui.header)
    root:SetAllPoints(ui.header)
    local stage = CreateFrame("Frame", nil, root)
    skin.Surface.Attach(stage, { role = "panel", radius = 7 })
    local preview = { ui = ui, skin = skin, card = skin.ItemTooltipCard, root = root, stage = stage,
        selected = 1, tabs = {}, layers = {}, handles = {} }
    preview.host = P.Suite.PreviewKit.NewHost(nil, { frame = stage, paint = function() Paint(preview) end })
    Sample(preview)
    preview.bar = Interaction.Bar(ui.ctx, root, ui.width - 32)
    BuildHandles(preview)
    BuildSelection(preview)
    for index, sample in ipairs(SAMPLES) do
        local button = T.Button(root, sample.label, 120, 28)
        HM.MarkSegmentChoice(button)
        HM.SkipHistoryCheckpoint(button)
        preview.tabs[index] = button
        button:SetScript("OnClick", function()
            preview.kit:Release()
            preview.selected = index
            for i, tab in ipairs(preview.tabs) do tab:SetActive(i == index) end
            Paint(preview)
        end)
    end
    preview.tabs[1]:SetActive(true)
    Interaction.BuildLayerRail(preview, root, LAYERS, function(key, visible)
        preview.layers[key] = visible
        Paint(preview)
        return true
    end, function(spec) return Open(preview, spec) end, function(key)
        if key ~= "icon" and key ~= "rule" and key ~= "border" then return end
        local sample = SAMPLES[preview.selected]
        if sample.id == "loot" and (key == "icon" or key == "border") then return end
        if not IsDetailed(preview, sample) then return STYLE end
        if key == "icon" and (not sample.icon or not preview.card.Setting("icon")) then return BUILDER end
        if key == "rule" and not preview.card.Setting("rule") then return BUILDER end
        if key == "border" and preview.card.Setting("borderMode") == "native" then return BUILDER end
    end)
    for _, spec in ipairs(LAYERS) do preview.layers[spec[1]] = true end
    root:HookScript("OnShow", function()
        root:RegisterEvent("PLAYER_REGEN_DISABLED")
        preview.host:Activate()
    end)
    root:HookScript("OnHide", function()
        root:UnregisterEvent("PLAYER_REGEN_DISABLED")
        preview.host:Deactivate()
    end)
    root:SetScript("OnEvent", function() preview.kit:Release() end)
    M.TrackRefresh(ui.ctx, function() if root:IsVisible() then Paint(preview) end end)
    ui.header:HookScript("OnSizeChanged", function(_, width)
        if preview.width == width then return end
        preview.width = width
        Layout(preview)
    end)
    return preview
end

function P.ShowSkinTooltipPreview(ui, skin, shown)
    local preview = ui.tooltipPreview
    if shown and not preview then
        preview = Build(ui, skin)
        ui.tooltipPreview = preview
    end
    if not preview then return end
    preview.root:SetShown(shown)
    if not shown then return end
    if not preview.host.active then
        preview.root:RegisterEvent("PLAYER_REGEN_DISABLED")
        preview.host:Activate()
    end
    Layout(preview)
    Paint(preview)
end
