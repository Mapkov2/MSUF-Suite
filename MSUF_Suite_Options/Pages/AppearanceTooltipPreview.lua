local _, P = ...

local Kit, M, T, HM, Tr = P.SkinPageKit, P.M, P.T, P.HM, P.Tr
local Interaction = P.PreviewInteraction
local PAGE, BUILDER = "suite_tooltips", "suite_skin_tooltip_builder"
local LAYOUT = "theme.tooltipLayout."
local ITEM, SPELL, UNIT, QUEST, LOOT, ENEMY, STACK, MOUNT, RIDER = 1, 2, 3, 4, 5, 6, 7, 8, 9
local PLAYER_ROWS = { { "Level 80 Human Paladin", "" }, { "Alliance", "" }, { "", "" } }
local function SampleSpec(palette, border)
    return { role = "popup", radius = 0, border = border, motion = false, depth = false, media = "background",
        resolveFill = palette.Fill, appearanceToken = "tooltipPalette" }
end
local SAMPLES = {
    [ITEM] = { id = "item", label = "Items", name = function() return Tr("Trailblazer's cloak") end,
        icon = 133754, kind = function() return Tr("Back") end, level = 60, color = 3,
        rows = { { "Armor", "38" }, { "Intellect", "+12" }, { "Stamina", "+9" } } },
    [SPELL] = { id = "spell", label = "Spells", name = function() return Tr("Frostbolt") end,
        icon = 135846, kind = function() return Tr("Spell") end,
        rows = { { "Cast time", "2.0 s" }, { "Range", function() return Tr("40 yd") end },
            { "School", function() return Tr("Frost") end } } },
    [UNIT] = { id = "unit", label = "Units", name = function() return Tr("Player Name") end,
        color = { r = .25, g = .78, b = .92 }, rows = PLAYER_ROWS },
    [QUEST] = { id = "quest", label = "Quests", name = function() return Tr("Quest objective progress") end,
        color = { r = 1, g = .82, b = .2 },
        rows = { { "Quests", "" }, { "Progress", "3/4" }, { "", "" } } },
    [LOOT] = { id = "loot", label = "Loot", name = function() return Tr("Trailblazer's cloak") end,
        icon = 133754, kind = function() return Tr("Back") end, level = 60, color = 3 },
    [ENEMY] = { id = "unit", enemy = true, keystone = true, label = "Enemy unit", name = function() return Tr("Enemy unit") end,
        color = { r = .95, g = .28, b = .22 }, rows = { { "Level", "56" }, { "", "" }, { "", "" } } },
    [STACK] = { id = "item", stack = "3", label = "Consumables", name = function() return Tr("Healthstone") end,
        icon = 538745, rows = { { "Consumables", "" }, { "", "" }, { "", "" } } },
    [MOUNT] = { id = "spell", mount = true, label = "Mount", name = function() return Tr("Mount") end,
        icon = 132261, rows = { { "Mount", "" }, { "", "" }, { "", "" } } },
    [RIDER] = { id = "unit", mounted = true, label = "Mounted", name = function() return Tr("Player Name") end,
        color = { r = .25, g = .78, b = .92 }, rows = PLAYER_ROWS },
}
local DETAIL_SAMPLES = {
    titles = UNIT, itemLevel = UNIT, inspectHovered = UNIT, spec = UNIT, guildRank = UNIT,
    target = UNIT, unitCombatStatus = UNIT, unitIdentityIcons = UNIT, unitFaction = UNIT, unitLocation = UNIT,
    unitTargeters = UNIT, hideHealth = UNIT, hideFaction = UNIT, hidePvP = UNIT, hideRealm = UNIT, hideGuild = UNIT,
    selfTarget = ENEMY, unitClassification = ENEMY, unitThreatStatus = ENEMY, unitThreatPercent = ENEMY, mythicForces = ENEMY,
    ownedMount = MOUNT, unitMount = RIDER, unitMountOwned = RIDER, maxStack = STACK, iconID = ITEM,
}
local NEEDS_NORMAL = {
    titles = true, inspectHovered = true, ownedMount = true, unitMount = true, unitMountOwned = true, unitTargeters = true,
    maxStack = true, iconID = true, hideFaction = true, hidePvP = true, hideRealm = true, hideGuild = true,
}
local LAYERS = {
    { "header", "Header", "headerTexture", "height" }, { "title", "Title", "tint", "offset" },
    { "icon", "Icon", "icon", "iconSize" }, { "data", "Details", "level" },
    { "rule", "Accent line", "rule" }, { "border", "Tooltip frame", "borderMode" },
    { "background", "Background", "backgroundTexture" },
}

local VITAL_LAYERS = {
    { "health", "Health bar", "unitHealth", "unitHealth" },
    { "healthText", "Health text", "unitHealthTextFormat", "unitHealthText" },
    { "power", "Resource Bar", "unitPower", "unitPower" },
}

local function IsDetailed(preview, sample)
    return preview.forceCard or preview.card.TypeStyle(sample.id) == "custom"
end

local Layout, Paint, SelectTitle
local UNIT_SECTION = "suite_skin_unit_tooltips"
local function SelectSample(preview, index, nativeUnit)
    preview.kit:Release()
    preview.selected, preview.forceCard, preview.nativeUnit = index, nil, nativeUnit or index == RIDER
    preview.sampleSelector:SetValue(index)
    Paint(preview)
end

local function SetScenario(preview, value)
    preview.kit:Release()
    preview.scenario, preview.restricted = value, value == "restricted"
    Paint(preview)
end

local function RevealDetail(ui, key)
    local preview = ui.tooltipPreview
    if ui.selected ~= "details" or not preview or not preview.root:IsVisible() then return end
    local index, current = DETAIL_SAMPLES[key], preview.selected
    local sample = SAMPLES[current]
    if key == "iconID" and (current == SPELL or current == STACK)
        or (key == "target" or key == "unitCombatStatus" or key == "unitTargeters" or key == "hideHealth") and sample.id == "unit" then
        index = current
    end
    local nativeUnit = SAMPLES[index].id == "unit"
    if NEEDS_NORMAL[key] and preview.restricted then
        preview.scenario, preview.restricted = "normal", false
        preview.stateSelector:SetValue("normal")
    end
    SelectSample(preview, index, nativeUnit)
end

function P.BindTooltipDetailPreview(ui, rows)
    for _, row in ipairs(rows) do
        if DETAIL_SAMPLES[row.id] then
            local key, read, write = row.id, row.get, row.set
            row.set = function(value)
                local previous = read()
                write(value)
                if read() ~= previous then RevealDetail(ui, key) end
            end
        end
    end
end

local function Open(preview, spec, blockedSection)
    local sample = SAMPLES[preview.selected]
    if sample.id == "loot" and (spec[1] == "icon" or spec[1] == "rule") then
        blockedSection = P.TooltipTypesSection
    end
    return P.TooltipPositionPreview.Open(preview, spec, sample.id, blockedSection)
end

local function Put(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
end

local function Sample(preview)
    local frame = CreateFrame("Frame", nil, preview.stage)
    frame:SetPoint("CENTER")
    preview.skin.Surface.Attach(frame, preview.paintChrome)
    preview.frame, preview.surfaceSpec = frame, preview.paintChrome
    if preview.skin.TooltipVitals then preview.vitals = preview.skin.TooltipVitals.CreatePreview(frame) end
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
    for index = 1, 15 do
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
    local targets = { header = header.frame, title = header.title, icon = header.icon, data = preview.body,
        rule = header.rule, border = preview.outline.edges[1], background = preview.frame }
    if preview.vitals then
        targets.health, targets.power, targets.healthText = preview.vitals.health, preview.vitals.power, preview.vitals.healthText
    end
    return targets
end

local function PlaceHit(handle, region)
    handle:ClearAllPoints()
    handle:SetAllPoints(region)
end

local ANCHOR_ID = "tooltipDetails"
local Position = P.TooltipPositionPreview
local ReadAnchor, WriteAnchor = Position.Read, Position.Write
local PlaceAnchor, DragAnchor, Clamp = Position.Place, Position.Drag, Position.Clamp

local function Movable(preview, handle)
    if not handle or not handle:IsVisible() then return false end
    if Position.IsAnchor(preview, handle) then return Position.CanMove(preview) end
    if handle == preview.scaleButton then return not preview.usesPanel and P.Get("tooltipVisibility", "enabled") == true end
    local key = handle.spec[1]
    if key == "health" then return preview.card.Setting("unitHealth") == "show" end
    if key == "power" then return preview.card.Setting("unitPower") == true end
    if key == "healthText" then return true end
    return handle.spec[4] ~= nil and SAMPLES[preview.selected].id ~= "loot" and preview.header.frame:IsShown()
end

local function BarPrefix(handle)
    local field = handle and handle.spec[4]
    if field == "unitHealth" or field == "unitPower" or field == "unitHealthText" then return field end
end

local function SizeField(handle)
    local field = handle and handle.spec[4]
    if field == "iconSize" or field == "height" then return field end
end

local function Highlight(preview, handle)
    local selection = preview.selection
    if selection then
        local show = Movable(preview, handle)
        if selection:IsShown() ~= show then
            selection:SetShown(show)
            preview.bar:SetShown(not show)
            Layout(preview)
        end
        if show then
            local single = SizeField(handle) or handle == preview.scaleButton
            local resize = handle.resize
            local scalar = single == "height" and "H" or single == "iconSize" and "S" or "%"
            selection.axisX.title:SetText(resize and "W" or single and scalar or "X")
            selection.axisY.title:SetText(resize and "H" or "Y")
            selection.axisY:SetShown(not single)
            M.PreviewSelectionBar.Refresh(preview.stage)
        end
    end
    local open
    if handle then open = handle.open end
    Interaction.Select(preview.bar, handle, handle and handle.spec[2], open)
end

local function ReadOffsets(preview, handle)
    if Position.IsAnchor(preview, handle) then return ReadAnchor(preview) end
    if handle and handle == preview.scaleButton then return Position.Scale(preview, true), 0 end
    local prefix = BarPrefix(handle)
    if prefix and handle.resize then return preview.card.Setting(prefix .. "Width"), preview.card.Setting(prefix .. "Height") end
    if prefix then return preview.card.Setting(prefix .. "X"), preview.card.Setting(prefix .. "Y") end
    local size = SizeField(handle)
    if size then return preview.card.Setting(size), 0 end
    return preview.card.Setting("x"), preview.card.Setting("y")
end

local function WriteOffsets(preview, x, y, handle)
    if Position.IsAnchor(preview, handle) then return WriteAnchor(preview, x, y) end
    if P.Combat() or not preview.root:IsVisible() then return false end
    if handle and handle == preview.scaleButton then return Position.WriteScale(preview, x) end
    local prefix = BarPrefix(handle)
    if prefix then
        if handle.resize then
            return Kit.Change(preview.skin, handle.spec[2], LAYOUT .. prefix .. "Size", function()
                return preview.card.SetUnitBarSize(prefix, x, y)
            end)
        end
        return Kit.Change(preview.skin, handle.spec[2], LAYOUT .. prefix .. "Position", function()
            return preview.card.SetUnitBarOffsets(prefix, x, y)
        end)
    end
    local kind = SAMPLES[preview.selected].id
    local size = SizeField(handle)
    if size then
        local min, max = preview.card.Range(size)
        return Kit.Change(preview.skin, handle.spec[2], LAYOUT .. size, function()
            return preview.card.Set(size, Clamp(x, min, max), kind)
        end)
    end
    return Kit.Change(preview.skin, "Tooltip builder", LAYOUT .. "position", function()
        return preview.card.SetOffsets(x, y, kind)
    end)
end

local function BindAnchorHandle(preview, key, button)
    button.spec = { "anchor", "Tooltip anchor" }
    button.open = function() return Open(preview, button.spec) end
    button:Hide()
    preview.kit:Add(key, button, function() return ReadAnchor(preview) end, function(x, y, dragged)
        if dragged then
            if not (preview.dragProfile and preview.dragProfile() and preview.dragMode == Position.Mode(preview)) then
                return false
            end
            local startX, startY = ReadAnchor(preview)
            x, y = DragAnchor(preview, x - startX, y - startY)
        end
        return WriteAnchor(preview, x, y)
    end, {
        can = function() return Movable(preview, button) end,
        scale = function() return preview.stage:GetEffectiveScale() end,
        follow = function(_, dx, dy)
            if preview.anchorMode and preview.anchorMode == Position.Mode(preview) then
                PlaceAnchor(preview, DragAnchor(preview, dx, dy))
            end
        end,
    })
    HM.SkipHistoryCheckpoint(button)
end

local function BuildAnchorHandle(preview)
    local button = T.Button(preview.root, "Tooltip anchor", 140, 25)
    local surface = CreateFrame("Button", nil, preview.frame)
    surface:SetAllPoints(preview.frame)
    surface:SetFrameLevel(preview.stage:GetFrameLevel() + 14)
    preview.anchorButton, preview.anchorSurface = button, surface
    BindAnchorHandle(preview, "anchor", button)
    BindAnchorHandle(preview, "anchorSurface", surface)
end

local function BuildScaleHandle(preview)
    local button = T.Button(preview.root, "Scale", 84, 25)
    button.spec = { "scale", "Main tooltip scale (percent)" }
    button.open = function() return Open(preview, button.spec) end
    preview.scaleButton = button
    button:Hide()
    preview.kit:Add("scale", button, function() return Position.Scale(preview, true), 0 end,
        function(x, _, dragged)
            if dragged and not (preview.dragProfile and preview.dragProfile()) then return false end
            return Position.WriteScale(preview, x)
        end, { can = function() return Movable(preview, button) end,
            follow = function(_, dx)
                preview.scaleDraft = Position.ClampScale(Position.Scale(preview, true) + dx)
                Paint(preview)
            end })
    HM.SkipHistoryCheckpoint(button)
end

local function BindDrag(preview, handle)
    local field = handle.spec[4]
    local card = preview.card
    local offset = field == "offset"
    local vertical = field == "height"
    local function Read()
        if offset then return ReadOffsets(preview) end
        local value = card.Setting(field)
        return value, 0
    end
    local function Clamp(value)
        local min, max = card.Range(field)
        return math.max(min, math.min(max, math.floor(value + .5)))
    end
    local function Write(x, y, dragged)
        if dragged and not (preview.dragProfile and preview.dragProfile() and preview.dragDatabase == preview.skin.DB) then
            return false
        end
        if vertical then x = dragged and card.Setting(field) - y or x + y end
        return WriteOffsets(preview, x, y, handle)
    end
    local function Follow(_, dx, dy)
        local x, y = Read()
        if offset then
            local minX, maxX = card.Range("x")
            local minY, maxY = card.Range("y")
            card.PlaceContent(preview.header, math.max(minX, math.min(maxX, x + dx)),
                math.max(minY, math.min(maxY, y + dy)))
        else
            preview.dragSize = preview.dragSize or {}
            preview.dragSize[field] = Clamp(vertical and x - dy or x + dx)
            Paint(preview)
        end
    end
    return Read, Write, Follow
end

local function BindBarDrag(preview, handle, resize)
    local card, prefix = preview.card, BarPrefix(handle)
    local keyA, keyB = prefix .. (resize and "Width" or "X"), prefix .. (resize and "Height" or "Y")
    local ax, bx = card.Range(keyA)
    local ay, by = card.Range(keyB)
    local function WidthUnit() return math.max(1, preview.frame:GetWidth() - 4) / 200 end
    local function Read() return card.Setting(keyA), card.Setting(keyB) end
    local function Convert(a, b, dragged)
        if resize and dragged then
            local width, height = Read()
            a, b = width + (a - width) / (preview.dragWidthUnit or WidthUnit()), height - (b - height)
        end
        return Clamp(a, ax, bx), Clamp(b, ay, by)
    end
    local function Write(x, y, dragged)
        if dragged and not (preview.dragProfile and preview.dragProfile() and preview.dragDatabase == preview.skin.DB) then
            return false
        end
        if not Movable(preview, handle) then return false end
        local a, b = Convert(x, y, dragged)
        return WriteOffsets(preview, a, b, handle)
    end
    local function Follow(_, dx, dy)
        local x, y = Read()
        local a, b = Convert(x + dx, y + dy, true)
        preview.dragSize = preview.dragSize or {}
        local draft = preview.dragSize[prefix] or {}
        preview.dragSize[prefix] = draft
        if resize then draft.width, draft.height = a, b
        else draft.x, draft.y = a, b end
        Paint(preview)
    end
    return Read, Write, Follow
end

local function BuildResizeHandle(preview, handle, bar)
    local key = handle.spec[1]
    local grip = CreateFrame("Button", nil, preview.frame)
    grip:SetSize(17, 17)
    grip:SetPoint("LEFT", bar, "RIGHT", 1, 0)
    grip:SetFrameLevel(handle:GetFrameLevel() + 2)
    grip.spec, grip.resize = { key, handle.spec[2], BarPrefix(handle) .. "Width", handle.spec[4] }, true
    grip.open = function() return Open(preview, grip.spec) end
    local icon = grip:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:Hide()
    local read, write, follow = BindBarDrag(preview, grip, true)
    preview.kit:Add(key .. "Size", grip, read, write, { follow = follow,
        can = function() return Movable(preview, handle) end })
    preview.handles[key .. "Size"] = grip
    HM.SkipHistoryCheckpoint(grip)
end

local function BuildHandles(preview)
    local stage = preview.stage
    preview.kit = Interaction.Handles(preview.host, {
        owner = stage, manualDrag = true, escape = function() preview.kit:Release() end,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        selecting = function(handle)
            if handle and handle == preview.handles.title and not P.Combat() and not preview.header.frame:IsShown()
                and SAMPLES[preview.selected].id ~= "loot" then
                preview.forceCard = true
                Paint(preview)
            end
        end,
        click = function(handle, button, moved)
            if not moved and not P.Combat() and (button == "RightButton" or not Movable(preview, handle)) then return handle.open() end
        end,
        select = function(handle) Highlight(preview, handle) end,
        tip = function(handle, entered)
            if preview.kit:Selected() ~= handle then Interaction.Outline(handle, entered, 1) end
        end,
        drag = function(handle, phase)
            if phase == "press" then
                preview.dragProfile, preview.dragDatabase = P.ProfileGuard(), preview.skin.DB
                preview.dragMode = preview.anchorMode
                if BarPrefix(handle) then preview.dragWidthUnit = math.max(1, preview.frame:GetWidth() - 4) / 200 end
            end
            if phase == "done" or phase == "cancel" then
                preview.dragProfile, preview.dragDatabase, preview.dragMode, preview.dragWidthUnit = nil, nil, nil, nil
                if preview.dragSize or preview.scaleDraft then
                    preview.dragSize, preview.scaleDraft = nil, nil
                    Paint(preview)
                end
            end
        end,
    })
    local targets = LayerTargets(preview)
    for index, spec in ipairs(preview.layerSpecs) do
        local key = spec[1]
        local handle = CreateFrame("Button", nil, preview.frame)
        handle:SetFrameLevel(stage:GetFrameLevel() + (key == "background" and 13 or 14 + index))
        handle.spec, handle.open = spec, function() return Open(preview, spec) end
        if SizeField(handle) then handle.openSize = function() return Open(preview, { key, spec[2], spec[4] }) end end
        PlaceHit(handle, targets[key])
        preview.handles[key] = handle
        local read, write, follow
        if BarPrefix(handle) then read, write, follow = BindBarDrag(preview, handle, false)
        elseif spec[4] then read, write, follow = BindDrag(preview, handle) end
        local controls = follow and { follow = follow, can = function() return Movable(preview, handle) end }
        if key == "healthText" then controls.clicks = { "LeftButtonUp", "RightButtonUp" } end
        preview.kit:Add(key, handle, read, write, controls)
        if key == "health" or key == "power" then BuildResizeHandle(preview, handle, targets[key]) end
        HM.SkipHistoryCheckpoint(handle)
    end
end

local function RefreshAnchorMode(preview)
    local mode, source
    local layout = preview.ui.selected == "layout"
    if layout then mode, source = Position.Mode(preview) end
    if layout == preview.anchorEditor and mode == preview.anchorMode and source == preview.anchorSource
        and preview.lastSource == preview.positionSource then return end
    preview.anchorMode, preview.anchorSource, preview.lastSource, preview.anchorEditor = mode, source, preview.positionSource, layout
    preview.anchorButton:SetShown(layout and P.Available(ANCHOR_ID) == true)
    preview.anchorSurface:SetShown(Position.CanMove(preview))
    preview.scaleButton:SetShown(layout and P.Available("tooltipVisibility") == true)
    if Position.IsAnchor(preview, preview.kit:Selected()) then preview.kit:Release() end
    Layout(preview)
end

local function FitHealthTextHandle(preview)
    local text, handle = preview.vitals.healthText, preview.handles.healthText
    local shown = preview.vitals.health:IsShown() and text:IsShown()
    handle:SetShown(shown)
    if not shown then return end
    local align = text:GetJustifyH()
    if align ~= "CENTER" and align ~= "RIGHT" then align = "LEFT" end
    handle:ClearAllPoints()
    handle:SetPoint(align, text, align)
    handle:SetSize(math.max(14, math.min(text:GetStringWidth(), text:GetWidth()) + 3), math.max(10, text:GetStringHeight()))
end

local function PaintVitals(preview, sample)
    if not preview.vitals then return end
    local unit = sample.id == "unit"
    local panel = preview.usesPanel
    local legacyHidden = P.TooltipDetailsEnabled() and P.Get("tooltipDetails", "hideHealth")
    local layers = preview.layers
    local height = preview.skin.TooltipVitals.PaintPreview(preview.vitals, unit, panel, legacyHidden,
        layers.health, layers.power, preview.dragSize, preview.restricted)
    if not layers.healthText then preview.vitals.healthText:Hide() end
    FitHealthTextHandle(preview)
    preview.handles.health:SetShown(preview.vitals.health:IsShown())
    preview.handles.power:SetShown(preview.vitals.power:IsShown())
    preview.handles.healthSize:SetShown(Movable(preview, preview.handles.health) == true)
    preview.handles.powerSize:SetShown(Movable(preview, preview.handles.power) == true)
    if preview.unitLayers ~= unit then
        preview.unitLayers = unit
        for _, button in ipairs(preview.layerButtons) do
            if button.key == "health" or button.key == "healthText" or button.key == "power" then button:SetShown(unit) end
        end
        preview.footerHeight = height
        Layout(preview)
    elseif preview.footerHeight ~= height then
        preview.footerHeight = height
        Layout(preview)
    end
end

Paint = function(preview)
    if not preview.root:IsVisible() then return end
    RefreshAnchorMode(preview)
    local sample, card, header, layers = SAMPLES[preview.selected], preview.card, preview.header, preview.layers
    preview.usesPanel = sample.id == "unit" and P.TooltipPreviewUsesPanel(preview)
    local loot, rich = sample.id == "loot", IsDetailed(preview, sample)
    local matching = loot and card.MatchesLootSurface()
    local extra = P.PaintTooltipPreviewSample(preview, sample, rich, matching)
    if preview.bodyExtra ~= extra then
        preview.bodyExtra = extra
        Layout(preview)
    end
    PaintVitals(preview, sample)
    local scale = preview.usesPanel and 1 or Position.Scale(preview) / 100
    if preview.displayScale ~= scale then
        preview.displayScale = scale
        preview.frame:SetScale(scale)
        Layout(preview)
    end
    PlaceAnchor(preview)
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
    if (rich or matching or not loot and preview.palette.IsActive()) and layers.border then
        local r, g, b
        if rich then r, g, b = header.r, header.g, header.b
        else r, g, b = preview.compact:GetTextColor() end
        card.PaintOutline(outline, preview.frame, preview.frame, r, g, b)
    else outline.frame:Hide() end
    if loot and preview.lootEdge:IsShown() then
        handles.border:ClearAllPoints()
        handles.border:SetPoint("TOPLEFT", preview.lootEdge)
        handles.border:SetPoint("TOPRIGHT", preview.lootEdge)
        handles.border:SetHeight(3)
    else PlaceHit(handles.border, outline.edges[1]) end
    handles.border:SetShown(outline.frame:IsShown() or loot and preview.lootEdge:IsShown())
    handles.background:SetShown(layers.background)
    Interaction.Refresh(preview.bar)
    if preview.selection and preview.selection:IsShown() then M.PreviewSelectionBar.Refresh(preview.stage) end
    Interaction.RefreshLayerRail(preview)
end

local function LayoutTools(preview, width, y)
    local choiceWidth = math.min(142, math.floor((width - 8) / 2))
    local stateWidth = math.min(174, width - choiceWidth - 8)
    local caption = preview.caption
    caption:ClearAllPoints()
    caption:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 16, y - 4)
    if width < choiceWidth + stateWidth + math.ceil(caption:GetStringWidth()) + 24 then
        y = y - math.max(26, math.ceil(caption:GetStringHeight()) + 10)
    end
    Put(preview.sampleSelector, preview.root, 16 + width - choiceWidth - stateWidth - 8, y, choiceWidth, 24)
    Put(preview.stateSelector, preview.root, 16 + width - stateWidth, y, stateWidth, 24)
    local layout = preview.ui.selected == "layout"
    preview.sourceSelector:SetShown(layout)
    local direction = layout and preview.anchorSource and preview.anchorMode == 3
    local side = layout and preview.anchorMode == 4
    preview.directionSelector:SetShown(direction == true)
    preview.sideSelector:SetShown(side)
    if layout then
        y = y - 28
        local sourceWidth = math.min(math.max(choiceWidth, preview.sourcePreferredWidth or 0), width - stateWidth - 8)
        Put(preview.sourceSelector, preview.root, 16 + width - sourceWidth - stateWidth - 8, y, sourceWidth, 24)
        if direction or side then
            Put(side and preview.sideSelector or preview.directionSelector, preview.root, 16 + width - stateWidth, y, stateWidth, 24)
        end
    end
    if preview.anchorButton:IsShown() or preview.scaleButton:IsShown() then
        y = y - 28
        Put(preview.anchorButton, preview.root, 16 + width - choiceWidth - stateWidth - 8, y, choiceWidth, 24)
        Put(preview.scaleButton, preview.root, 16 + width - stateWidth, y, stateWidth, 24)
    end
    return y - 32
end

Layout = function(preview)
    if not preview.root:IsShown() then return end
    local ui = preview.ui
    local full = ui.header:GetWidth()
    local width = math.max(204, (full and full > 100 and full or ui.width) - 32)
    local top = ui.tabs and ui.tabs:GetHeight() + 24 or 0
    local y = LayoutTools(preview, width, -10 - top)
    local scale = preview.displayScale or 1
    local baseHeight = (preview.anchorMode and 205 or 152) + (preview.footerHeight or 0) + (preview.bodyExtra or 0)
    local stageHeight = math.max(baseHeight, (preview.frame:GetHeight() + (preview.footerHeight or 0)) * scale + 32)
    Put(preview.stage, preview.root, 16, y, width, stageHeight)
    preview.frame:SetWidth(math.min(310, (width - (preview.anchorMode and 76 or 32)) / scale))
    PlaceAnchor(preview)
    Interaction.SizeBar(preview.bar, width)
    Interaction.LayoutSelectionBar(preview.selection, width)
    local bar = preview.selection and preview.selection:IsShown() and preview.selection or preview.bar
    y = y - stageHeight - 5
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 16, y)
    y = y - bar:GetHeight() - 7
    preview.chips:ClearAllPoints()
    preview.chips:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 16, y)
    Interaction.LayoutLayerRail(preview, width, true)
    P.MenuWorkspace.FitHeader(ui, -y + preview.chips:GetHeight() + 10)
end

SelectTitle = function(preview)
    if P.Combat() or not preview.root:IsVisible() then return false end
    if not preview.frame:IsShown() then
        SetScenario(preview, "normal")
        preview.stateSelector:SetValue("normal")
    end
    preview.kit:Release()
    preview.layers.header, preview.layers.title = true, true
    preview.forceCard = true
    Paint(preview)
    preview.kit:Select(preview.handles.title)
    return true
end

function Position.SelectSource(preview, source)
    preview.kit:Release()
    preview.positionSource = source
    preview.sourceSelector:SetValue(source)
    Paint(preview)
    local handle = preview.anchorSurface:IsVisible() and preview.anchorSurface or preview.anchorButton
    if handle:IsVisible() and not P.Combat() then preview.kit:Select(handle) end
end

local function BuildPositionControls(preview, Dropdown)
    local sources = { { value = "default", text = Tr("Default position") } }
    for _, source in ipairs(P.Suite.TooltipPositions.sources) do
        sources[#sources + 1] = { value = source.id, text = Tr(source.label) }
    end
    if T.MeasureTabWidth then
        local preferred = 0
        for _, source in ipairs(sources) do
            preferred = math.max(preferred, T.MeasureTabWidth(source.text) + 24)
        end
        preview.sourcePreferredWidth = preferred
    end
    preview.sourceSelector = Dropdown(Tr("Position preview source"), sources,
        function() return preview.positionSource end, function(value) Position.SelectSource(preview, value) end, "source")
    for _, field in ipairs({ "direction", "side" }) do
        local rule = P.catalog[ANCHOR_ID].rules[P.Suite.TooltipPositions.sources[1][field]]
        local values = {}
        for index, label in ipairs(rule.choices) do values[index] = { value = index, text = Tr(label) } end
        preview[field .. "Selector"] = Dropdown(rule.label, values, function()
            return preview.anchorSource and P.Get(ANCHOR_ID, preview.anchorSource[field]) or 1
        end, function(value)
            if preview.anchorSource then P.Set(ANCHOR_ID, preview.anchorSource[field], value) end
        end, field)
    end
end

local function BuildPreviewControls(preview)
    local root = preview.root
    preview.caption = T.Font(root, "GameFontHighlight", "Preview", T.colors.text, "card")
    local function Dropdown(label, values, read, set, key)
        local widget = M.BindDropdownAt(preview.ui.ctx, root, label, 0, 0, values, 136, read, set,
            P.Meta(PAGE, "skin", "view." .. key, "ephemeral"))
        P.HideControlTitle(widget)
        HM.SkipHistoryCheckpoint(widget)
        return widget
    end
    local samples = {}
    for index, sample in ipairs(SAMPLES) do
        if P.Suite.Client.modernEquipment or index < STACK then samples[#samples + 1] = { text = Tr(sample.label), value = index } end
    end
    preview.sampleSelector = Dropdown("Tooltips", samples,
        function() return preview.selected end, function(index) SelectSample(preview, index) end, "sample")
    preview.stateSelector = Dropdown("Preview", Kit.Values({ "normal", "restricted" },
        { normal = "Normal", restricted = "Combat restrictions" }),
        function() return preview.scenario end, function(value) SetScenario(preview, value) end, "scenario")
    BuildPositionControls(preview, Dropdown)
end

local function LayerSetting(preview, key)
    local sample = SAMPLES[preview.selected]
    if key == "health" or key == "power" or key == "healthText" then
        if not preview.frame:IsShown() or key == "healthText" and not preview.layers.health then return end
        if preview.restricted and key ~= "health" and not preview.usesPanel then return end
        local target = preview.vitals[key]
        if preview.layers[key] and not target:IsShown() then return UNIT_SECTION end
    end
    if key ~= "icon" and key ~= "rule" and key ~= "border" then return end
    if sample.id == "loot" and (key == "icon" or key == "border") then return end
    if not IsDetailed(preview, sample) then return P.TooltipTypesSection end
    if key == "icon" and (not sample.icon or not preview.card.Setting("icon")) then return BUILDER end
    if key == "rule" and not preview.card.Setting("rule") then return BUILDER end
    if key == "border" and preview.card.Setting("borderMode") == "native" then return BUILDER end
end

local function Build(ui, skin)
    local root = CreateFrame("Frame", nil, ui.header)
    root:SetAllPoints(ui.header)
    local stage = CreateFrame("Frame", nil, root)
    local canvas = stage:CreateTexture(nil, "BACKGROUND")
    canvas:SetAllPoints()
    canvas:SetColorTexture(.071, .086, .108, 1)
    local preview = { ui = ui, skin = skin, card = skin.ItemTooltipCard, root = root, stage = stage,
        selected = ITEM, scenario = "normal", positionSource = "default", layers = {}, handles = {}, rowSettings = {}, palette = skin.TooltipPalette }
    preview.positionReference = stage:CreateTexture(nil, "ARTWORK")
    preview.positionReference:SetSize(24, 16)
    preview.positionReference:SetColorTexture(.31, .47, .59, 1)
    preview.positionReference:Hide()
    preview.paintChrome, preview.paintFill = SampleSpec(preview.palette), SampleSpec(preview.palette, 0)
    preview.host = P.Suite.PreviewKit.NewHost(nil, { frame = stage, paint = function() Paint(preview) end })
    Sample(preview)
    preview.layerSpecs = LAYERS
    if preview.vitals then
        preview.layerSpecs = { unpack(LAYERS) }
        for _, spec in ipairs(VITAL_LAYERS) do preview.layerSpecs[#preview.layerSpecs + 1] = spec end
    end
    preview.bar = Interaction.Bar(ui.ctx, root, ui.width - 32, nil, true)
    BuildHandles(preview)
    BuildAnchorHandle(preview)
    BuildScaleHandle(preview)
    Position.BuildDetailHandles(preview, Open)
    Position.BuildSelection(preview, Movable, ReadOffsets, WriteOffsets, BarPrefix, SizeField)
    BuildPreviewControls(preview)
    P.BindTooltipPositionSearch(preview, SelectTitle, Paint)
    Interaction.BuildLayerRail(preview, root, preview.layerSpecs, function(key, visible)
        preview.layers[key] = visible
        Paint(preview)
        return true
    end, function(spec, section) return Open(preview, spec, section) end, function(key) return LayerSetting(preview, key) end)
    for _, spec in ipairs(preview.layerSpecs) do preview.layers[spec[1]] = true end
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
    skin.Registry.AddListener(preview, function(_, domain)
        if domain == "tooltipMedia" then Paint(preview) end
    end)
    if ui.tabs then ui.tabs:HookScript("OnSizeChanged", function() Layout(preview) end) end
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
    if preview.view ~= ui.selected then
        preview.view, preview.forceCard = ui.selected, nil
        preview.kit:Release()
    end
    preview.root:SetShown(shown)
    if not shown then return end
    if not preview.host.active then
        preview.root:RegisterEvent("PLAYER_REGEN_DISABLED")
        preview.host:Activate()
    end
    Layout(preview)
    Paint(preview)
end
