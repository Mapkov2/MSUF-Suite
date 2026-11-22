local _, P = ...

local Kit, M, T, HM, Tr = P.SkinPageKit, P.M, P.T, P.HM, P.Tr
local Interaction = P.PreviewInteraction
local PAGE, STYLE, BUILDER = "suite_tooltips", "suite_skin_tooltips", "suite_skin_tooltip_builder"
local LAYOUT = "theme.tooltipLayout."
local function SampleSpec(palette, border)
    return { role = "popup", radius = 0, border = border, motion = false, depth = false,
        resolveFill = palette.Fill, appearanceToken = "tooltipPalette" }
end
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
        rows = { { "Level 80 Human Paladin", "" }, { "Alliance", "" }, { "", "" } } },
    { id = "quest", label = "Quests", name = function() return Tr("Quest objective progress") end,
        color = { r = 1, g = .82, b = .2 },
        rows = { { "Quests", "" }, { "Progress", "3/4" }, { "", "" } } },
    { id = "loot", label = "Loot", name = function() return Tr("Trailblazer's cloak") end,
        icon = 133754, kind = function() return Tr("Back") end, level = 60, color = 3 },
}
local LAYERS = {
    { "header", "Header", "headerColor" }, { "title", "Title", "tint", "offset" },
    { "icon", "Icon", "iconSize", "iconSize" }, { "data", "Details", "level" },
    { "rule", "Accent line", "height", "height" }, { "border", "Tooltip frame", "borderMode" },
    { "background", "Background", "fillColor" },
}

local VITAL_LAYERS = {
    { "health", "Health bar", "unitHealth", "unitHealth" },
    { "healthText", "Health text", "unitHealthTextFormat", "unitHealthText" },
    { "power", "Resource Bar", "unitPower", "unitPower" },
}

local function IsDetailed(preview, sample)
    return (preview.forceCard or preview.card.TypeStyle(sample.id) == "custom")
        and (not preview.restricted or sample.id == "loot")
end

local function Open(preview, spec)
    local field = spec and spec[3]
    local sample = SAMPLES[preview.selected]
    if field == "unitHealthTextFormat" then return P.OpenTooltipHealthTextMenu(preview) end
    if field == "unitHealth" or field == "unitPower" then
        local section = "suite_skin_unit_tooltips"
        if preview.selected ~= 3 then preview.tabs[3]:GetScript("OnClick")() end
        return preview.ui:Focus(section)
            and P.Suite.HostBridge.OpenExactMenuSetting(M, PAGE, section, "msufsuite.skin." .. LAYOUT .. field)
    end
    if field == "fillColor" and P.W.OpenContextColors and not P.Combat() then
        P.W.OpenContextColors(preview.handles.background, { title = Tr("Tooltips"), getTargets = function()
            local targets = {}
            for _, row in ipairs(P.TooltipPaletteRows(preview.skin)) do
                targets[#targets + 1] = P.SkinColorTarget(preview.skin, row)
            end
            return targets
        end })
        return true
    end
    if sample.id == "loot" and field ~= "fillColor" and (not field or field == "iconSize" or not IsDetailed(preview, sample)) then
        return preview.ui:Focus(STYLE)
            and P.Suite.HostBridge.OpenExactMenuSetting(M, PAGE, STYLE, "msufsuite.skin." .. LAYOUT .. "lootStyle")
    end
    local section = field and BUILDER or STYLE
    if not preview.ui:Focus(section) then return false end
    if not field or field == "headerColor" then return true end
    return P.Suite.HostBridge.OpenExactMenuSetting(M, PAGE, section, "msufsuite.skin." .. LAYOUT .. field)
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
    for index = 1, 7 do
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

local Layout, Paint
local ANCHOR_ID = "tooltipDetails"
local anchorPrefixes = { [2] = "cursor", [3] = "fixed" }
local corners = {
    { "BOTTOMRIGHT", -1, 1 }, { "BOTTOMLEFT", 1, 1 },
    { "TOPRIGHT", -1, -1 }, { "TOPLEFT", 1, -1 },
}

local function AnchorKeys(preview)
    local prefix = anchorPrefixes[preview.anchorMode]
    if prefix then return prefix .. "X", prefix .. "Y" end
end

local function ReadAnchor(preview)
    local x, y = AnchorKeys(preview)
    if x then return P.Get(ANCHOR_ID, x), P.Get(ANCHOR_ID, y) end
    return 0, 0
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(value + .5)))
end

local function WriteAnchor(preview, x, y)
    if P.Combat() or not preview.root:IsVisible() or preview.anchorMode ~= P.TooltipAnchorMode()
        or not (P.Suite.Finite(x) and P.Suite.Finite(y)) then return false end
    local xKey, yKey = AnchorKeys(preview)
    if not xKey then return false end
    local rules = P.catalog[ANCHOR_ID].rules
    return P.SetMany(ANCHOR_ID, { [xKey] = Clamp(x, rules[xKey].min, rules[xKey].max),
        [yKey] = Clamp(y, rules[yKey].min, rules[yKey].max) })
end

local function AnchorProjection(preview)
    local x, y = AnchorKeys(preview)
    local rules = P.catalog[ANCHOR_ID].rules
    local corner = preview.anchorMode == 3 and (corners[P.Get(ANCHOR_ID, "growth")] or corners[1])
    local roomX = math.max(1, preview.stage:GetWidth() - preview.frame:GetWidth() - 24)
    local roomY = math.max(1, preview.stage:GetHeight() - preview.frame:GetHeight() - (preview.footerHeight or 0) - 24)
    local divisor = corner and 1 or 2
    return roomX / (rules[x].max * divisor), roomY / (rules[y].max * divisor), corner
end

local function PlaceAnchor(preview, x, y)
    local frame = preview.frame
    frame:ClearAllPoints()
    local footer = preview.footerHeight or 0
    if not preview.anchorMode then
        frame:SetPoint("CENTER", preview.stage, "CENTER", 0, footer / 2)
        return
    end
    local sx, sy, corner = AnchorProjection(preview)
    if x == nil then x, y = ReadAnchor(preview) end
    if corner then
        frame:SetPoint(corner[1], preview.stage, corner[1], corner[2] * (12 + math.abs(x) * sx),
            corner[3] * (12 + math.abs(y) * sy) + (corner[3] == 1 and footer or 0))
    else
        frame:SetPoint("CENTER", preview.stage, "CENTER", x * sx, y * sy + footer / 2)
    end
end

local function DragAnchor(preview, dx, dy)
    local x, y = ReadAnchor(preview)
    local sx, sy, corner = AnchorProjection(preview)
    local xKey, yKey = AnchorKeys(preview)
    local rules = P.catalog[ANCHOR_ID].rules
    if corner then
        local signX, signY = x == 0 and corner[2] or (x < 0 and -1 or 1), y == 0 and corner[3] or (y < 0 and -1 or 1)
        x = signX * Clamp(math.abs(x) + dx * corner[2] / sx, 0, rules[xKey].max)
        y = signY * Clamp(math.abs(y) + dy * corner[3] / sy, 0, rules[yKey].max)
    else
        x = Clamp(x + dx / sx, rules[xKey].min, rules[xKey].max)
        y = Clamp(y + dy / sy, rules[yKey].min, rules[yKey].max)
    end
    return x, y
end

local function Movable(preview, handle)
    if handle and handle == preview.anchorButton then return preview.anchorMode ~= nil and handle:IsVisible() end
    if handle and handle.spec[1] == "healthText" then return handle:IsVisible() end
    if handle and handle.spec[1] == "health" then
        return handle:IsVisible() and not preview.restricted and preview.card.Setting("unitHealth") == "show"
    end
    if handle and handle.spec[1] == "power" then return handle:IsVisible() and preview.card.Setting("unitPower") end
    return handle and handle.spec[4] and handle:IsVisible() and preview.header.frame:IsShown()
        and (handle.spec[1] ~= "icon" or SAMPLES[preview.selected].id ~= "loot")
end

local function BarPrefix(handle)
    local field = handle and handle.spec[4]
    if field == "unitHealth" or field == "unitPower" or field == "unitHealthText" then return field end
end

local function HasAxes(preview, handle)
    return handle and Movable(preview, handle) == true and
        (handle == preview.anchorButton or handle.spec[4] == "offset" or BarPrefix(handle) ~= nil)
end

local function Highlight(preview, handle)
    local selection = preview.selection
    if selection then
        local show = HasAxes(preview, handle) == true
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

local function ReadOffsets(preview, handle)
    if handle and handle == preview.anchorButton then return ReadAnchor(preview) end
    local prefix = BarPrefix(handle)
    if prefix then return preview.card.Setting(prefix .. "X"), preview.card.Setting(prefix .. "Y") end
    return preview.card.Setting("x"), preview.card.Setting("y")
end

local function WriteOffsets(preview, x, y, handle)
    if handle and handle == preview.anchorButton then return WriteAnchor(preview, x, y) end
    if P.Combat() or not preview.root:IsVisible() then return false end
    local prefix = BarPrefix(handle)
    if prefix then
        return Kit.Change(preview.skin, handle.spec[2], LAYOUT .. prefix .. "Position", function()
            return preview.card.SetUnitBarOffsets(prefix, x, y)
        end)
    end
    return Kit.Change(preview.skin, "Tooltip builder", LAYOUT .. "position", function()
        return preview.card.SetOffsets(x, y)
    end)
end

local function BuildAnchorHandle(preview)
    local button = T.Button(preview.root, "Tooltip anchor", 140, 25)
    button.spec = { "anchor", "Tooltip anchor" }
    button.open = function()
        local feature = P.QoLView.FindFeature(ANCHOR_ID)
        return P.Suite.HostBridge.OpenExactMenuSetting(M, PAGE, P.QoLView.FeatureSectionId(feature),
            "msufsuite.tooltipDetails.anchor")
    end
    preview.anchorButton = button
    button:Hide()
    preview.kit:Add("anchor", button, function() return ReadAnchor(preview) end, function(x, y, dragged)
        if dragged then
            if not (preview.dragProfile and preview.dragProfile() and preview.dragMode == P.TooltipAnchorMode()) then
                return false
            end
            local startX, startY = ReadAnchor(preview)
            x, y = DragAnchor(preview, x - startX, y - startY)
        end
        return WriteAnchor(preview, x, y)
    end, {
        can = function() return Movable(preview, button) end,
        follow = function(_, dx, dy)
            if preview.anchorMode and preview.anchorMode == P.TooltipAnchorMode() then
                PlaceAnchor(preview, DragAnchor(preview, dx, dy))
            end
        end,
    })
    HM.SkipHistoryCheckpoint(button)
end

local function BindDrag(preview, field)
    local card = preview.card
    local offset = field == "offset"
    local vertical = field == "height"
    local function Read()
        if offset then return ReadOffsets(preview) end
        local value = card.Setting(field)
        if vertical then return 0, -value end
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
        if offset then return WriteOffsets(preview, x, y) end
        return Kit.Change(preview.skin, "Tooltip builder", LAYOUT .. field, function()
            return card.Set(field, Clamp(vertical and -y or x))
        end)
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
            preview.dragSize[field] = Clamp(vertical and -(y + dy) or x + dx)
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
    local function Read()
        local a, b = card.Setting(keyA), card.Setting(keyB)
        if resize then return (preview.dragWidthUnit or WidthUnit()) * a, -b end
        return a, b
    end
    local function Convert(a, b)
        if resize then a, b = a / (preview.dragWidthUnit or WidthUnit()), -b end
        return Clamp(a, ax, bx), Clamp(b, ay, by)
    end
    local function Write(x, y, dragged)
        if dragged and not (preview.dragProfile and preview.dragProfile() and preview.dragDatabase == preview.skin.DB) then
            return false
        end
        if not Movable(preview, handle) then return false end
        local a, b = Convert(x, y)
        if not resize then return WriteOffsets(preview, a, b, handle) end
        return Kit.Change(preview.skin, handle.spec[2], LAYOUT .. prefix .. "Size", function()
            return card.SetUnitBarSize(prefix, a, b)
        end)
    end
    local function Follow(_, dx, dy)
        local x, y = Read()
        local a, b = Convert(x + dx, y + dy)
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
    local grip = CreateFrame("Button", nil, preview.stage)
    grip:SetSize(17, 17)
    grip:SetPoint("LEFT", bar, "RIGHT", 1, 0)
    grip:SetFrameLevel(handle:GetFrameLevel() + 2)
    grip.spec, grip.open = handle.spec, handle.open
    local icon = grip:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:Hide()
    local read, write, follow = BindBarDrag(preview, handle, true)
    preview.kit:Add(key .. "Size", grip, read, write, { follow = follow, select = false,
        can = function() return Movable(preview, handle) end })
    preview.handles[key .. "Size"] = grip
    HM.SkipHistoryCheckpoint(grip)
end

local function BuildHandles(preview)
    local stage = preview.stage
    preview.kit = Interaction.Handles(preview.host, {
        owner = stage, manualDrag = true, escape = function() preview.kit:Release() end,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        click = function(handle, button, moved)
            if not moved and (button == "RightButton" or not HasAxes(preview, handle)) then handle.open() end
        end,
        select = function(handle) Highlight(preview, handle) end,
        drag = function(handle, phase)
            if phase == "press" then
                preview.dragProfile, preview.dragDatabase = P.ProfileGuard(), preview.skin.DB
                preview.dragMode = preview.anchorMode
                if BarPrefix(handle) then preview.dragWidthUnit = math.max(1, preview.frame:GetWidth() - 4) / 200 end
            end
            if phase == "done" or phase == "cancel" then
                preview.dragProfile, preview.dragDatabase, preview.dragMode, preview.dragWidthUnit = nil, nil, nil, nil
                if preview.dragSize then
                    preview.dragSize = nil
                    Paint(preview)
                end
            end
        end,
    })
    local targets = LayerTargets(preview)
    for index, spec in ipairs(preview.layerSpecs) do
        local key = spec[1]
        local handle = CreateFrame("Button", nil, stage)
        handle:SetFrameLevel(stage:GetFrameLevel() + (key == "background" and 13 or 14 + index))
        handle.spec, handle.open = spec, function() return Open(preview, spec) end
        PlaceHit(handle, targets[key])
        preview.handles[key] = handle
        local read, write, follow
        if BarPrefix(handle) then read, write, follow = BindBarDrag(preview, handle, false)
        elseif spec[4] then read, write, follow = BindDrag(preview, spec[4]) end
        local controls = follow and { follow = follow, can = function() return Movable(preview, handle) end }
        if key == "healthText" then controls.clicks = { "LeftButtonUp", "RightButtonUp" } end
        preview.kit:Add(key, handle, read, write, controls)
        if key == "health" or key == "power" then BuildResizeHandle(preview, handle, targets[key]) end
        HM.SkipHistoryCheckpoint(handle)
    end
end

local function TrackInput(preview, input)
    if not input then return end
    input:HookScript("OnEditFocusGained", function()
        preview.axisProfile, preview.axisDatabase = P.ProfileGuard(), preview.skin.DB
        preview.axisMode = preview.anchorMode
    end)
    input:HookScript("OnHide", function() preview.axisProfile, preview.axisDatabase, preview.axisMode = nil, nil, nil end)
end

local function BuildSelection(preview)
    if not M.PreviewSelectionBar then return end
    local selection = M.PreviewSelectionBar.Create(preview.stage, {
        Tr = Tr, Theme = function() return T end,
        HandleList = function() return preview.kit.list end,
        HandleLabel = function(handle) return handle.spec[2] end,
        IsPlaced = function(handle) return HasAxes(preview, handle) == true end,
        ReadOffsets = function(_, handle) return ReadOffsets(preview, handle) end,
        WriteOffsets = function(_, handle, x, y, reason)
            if reason == "PREVIEW_EXACT_OFFSET" and not (preview.axisProfile and preview.axisProfile()
                and preview.axisDatabase == preview.skin.DB
                and (handle ~= preview.anchorButton or preview.axisMode == P.TooltipAnchorMode())) then return false end
            if HasAxes(preview, handle) then return WriteOffsets(preview, x, y, handle) end
        end,
        NudgeDelta = function(_, dx, dy) return preview.kit:Nudge(dx, dy) end,
        ResetOffsets = function(_, handle)
            if not HasAxes(preview, handle) then return false end
            if handle == preview.anchorButton then
                local x, y = AnchorKeys(preview)
                local rules = P.catalog[ANCHOR_ID].rules
                return WriteAnchor(preview, rules[x].default, rules[y].default)
            end
            if BarPrefix(handle) then return WriteOffsets(preview, 0, 0, handle) end
            return WriteOffsets(preview, 10, 0)
        end,
        OpenSettings = function(_, handle) return handle.open() end,
        SelectHandle = function(_, handle) preview.kit:Select(handle) return true end,
    })
    preview.selection = selection
    selection:Hide()
    TrackInput(preview, selection.axisX.edit)
    TrackInput(preview, selection.axisY.edit)
end

local function PaintSample(preview, sample, rich, matching)
    local card, loot = preview.card, sample.id == "loot"
    local header, layers = preview.header, preview.layers
    local hasHeader = layers.header and rich
    local name = sample.name()
    header.frame:SetPoint("TOPLEFT", preview.frame, "TOPLEFT", loot and 44 or 0, loot and -2 or 0)
    header.frame:SetPoint("TOPRIGHT", preview.frame, "TOPRIGHT", loot and -1 or 0, loot and -2 or 0)
    if rich then
        card.SetUnifiedHeader(header, matching or not loot and card.Setting("cardSurface") == "unified")
        local icon = not loot and sample.icon or nil
        card.Draw(header, name, icon, sample.kind and sample.kind(),
            sample.level and Tr("Item level %d"):format(sample.level), sample.color, loot and 42 or nil, preview.dragSize)
    end
    header.frame:SetShown(hasHeader)
    header.icon:SetShown(not loot and hasHeader and layers.icon and sample.icon ~= nil and card.Setting("icon"))
    header.title:SetShown(hasHeader and layers.title)
    header.meta:SetShown(hasHeader and layers.data)
    header.rule:SetShown(hasHeader and layers.rule and card.Setting("rule"))
    preview.compact:SetPoint("TOPLEFT", loot and 50 or 14, loot and -14 or -11)
    preview.compact:SetText(name)
    preview.compact:SetTextColor(preview.palette.Title())
    preview.compact:SetShown(not rich and layers.header and layers.title)
    local customOutline = (rich or matching or not loot and preview.palette.IsActive()) and card.Setting("borderMode") ~= "native"
    local spec = (loot or customOutline or not layers.border) and preview.paintFill or preview.paintChrome
    if preview.surfaceSpec ~= spec then
        preview.skin.Surface.Attach(preview.frame, spec)
        preview.surfaceSpec = spec
    end
    preview.skin.Surface.SetVisible(preview.frame, layers.background and (not loot or matching))
    preview.lootFill:SetShown(layers.background and loot and not matching)
    preview.lootEdge:SetShown(loot and layers.border and (not rich and not matching or card.Setting("borderMode") == "native"))
    preview.lootIcon:SetShown(loot and layers.icon)
    if loot then preview.lootIcon:SetTexture(sample.icon) end
    local height = rich and (preview.dragSize and preview.dragSize.height or card.HeaderHeight()) or 24
    preview.body:SetPoint("TOPLEFT", 14, -height - 10)
    preview.body:SetShown(not loot and layers.data)
    local extra = P.PaintTooltipPreviewBody(preview, sample)
    preview.frame:SetHeight(loot and 46 or height + 80 + extra)
    if preview.bodyExtra ~= extra then
        preview.bodyExtra = extra
        Layout(preview)
    end
end

local function RefreshAnchorMode(preview)
    local mode = P.TooltipAnchorMode()
    if mode == preview.anchorMode then return end
    preview.anchorMode = mode
    preview.anchorButton:SetShown(mode ~= nil)
    if preview.kit:Selected() == preview.anchorButton then preview.kit:Release() end
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
    local panel = P.TooltipPreviewUsesPanel()
    local legacyHidden = P.TooltipDetailsEnabled() and P.Get("tooltipDetails", "hideHealth")
    local height = preview.skin.TooltipVitals.PaintPreview(preview.vitals, unit, panel, legacyHidden,
        true, true, preview.dragSize, preview.restricted)
    preview.layers.health = preview.vitals.health:IsShown()
    preview.layers.power = preview.vitals.power:IsShown()
    FitHealthTextHandle(preview)
    preview.layers.healthText = preview.handles.healthText:IsShown()
    if preview.footerHeight ~= height then
        preview.footerHeight = height
        Layout(preview)
    end
    preview.handles.health:SetShown(preview.vitals.health:IsShown())
    preview.handles.power:SetShown(preview.vitals.power:IsShown())
    preview.handles.healthSize:SetShown(Movable(preview, preview.handles.health) == true)
    preview.handles.powerSize:SetShown(Movable(preview, preview.handles.power) == true)
    for _, button in ipairs(preview.layerButtons or {}) do
        if button.key == "health" or button.key == "healthText" or button.key == "power" then button:SetShown(unit) end
    end
end

Paint = function(preview)
    if not preview.root:IsVisible() then return end
    RefreshAnchorMode(preview)
    local sample, card, header, layers = SAMPLES[preview.selected], preview.card, preview.header, preview.layers
    local loot, rich = sample.id == "loot", IsDetailed(preview, sample)
    local matching = loot and card.MatchesLootSurface()
    PaintSample(preview, sample, rich, matching)
    PaintVitals(preview, sample)
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

Layout = function(preview)
    if not preview.root:IsShown() then return end
    local ui = preview.ui
    local full = ui.header:GetWidth()
    local width = math.max(204, (full and full > 100 and full or ui.width) - 32)
    local sidebar = width >= 630
    local rail = sidebar and math.floor(width * .36) or width
    local stage = sidebar and width - rail - 12 or width
    local y = -78
    local stageHeight = (preview.anchorMode and 205 or 152) + (preview.footerHeight or 0) + (preview.bodyExtra or 0)
    Put(preview.stage, preview.root, 16, y, stage, stageHeight)
    preview.frame:SetWidth(math.min(310, stage - (preview.anchorMode and 76 or 32)))
    PlaceAnchor(preview)
    local railX, railY = sidebar and 28 + stage or 16, sidebar and y or y - stageHeight - 8
    preview.chips:ClearAllPoints()
    preview.chips:SetPoint("TOPLEFT", preview.root, "TOPLEFT", railX, railY)
    Interaction.LayoutLayerRail(preview, rail)
    local bottom = math.max(-y + stageHeight, -railY + preview.chips:GetHeight())
    Interaction.SizeBar(preview.bar, width)
    Interaction.LayoutSelectionBar(preview.selection, width)
    local bar = preview.selection and preview.selection:IsShown() and preview.selection or preview.bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 16, -bottom - 7)
    P.MenuWorkspace.FitHeader(ui, bottom + bar:GetHeight() + 14)
    local cell = (width - (#SAMPLES - 1) * 6) / #SAMPLES
    for index, button in ipairs(preview.tabs) do Put(button, preview.root, 16 + (index - 1) * (cell + 6), -12, cell, 28) end
    local buttonCount = preview.anchorMode and 4 or 3
    local buttonWidth = math.min(150, (width - (buttonCount - 1) * 6) / buttonCount)
    for i, button in ipairs({ preview.combatButton, preview.restrictionsButton, preview.titleButton, preview.anchorButton }) do
        Put(button, preview.root, 16 + (i - 1) * (buttonWidth + 6), -45, buttonWidth, 25)
    end
end

local function SelectTitle(preview)
    if P.Combat() or preview.restricted or not preview.root:IsVisible() then return false end
    preview.kit:Release()
    preview.layers.header, preview.layers.title = true, true
    preview.forceCard = true
    Paint(preview)
    preview.kit:Select(preview.handles.title)
    return true
end

local function BuildPreviewButtons(preview)
    local root = preview.root
    for index, sample in ipairs(SAMPLES) do
        local button = T.Button(root, sample.label, 120, 28)
        HM.MarkSegmentChoice(button)
        HM.SkipHistoryCheckpoint(button)
        preview.tabs[index] = button
        button:SetScript("OnClick", function()
            preview.kit:Release()
            preview.selected, preview.forceCard = index, nil
            for i, tab in ipairs(preview.tabs) do tab:SetActive(i == index) end
            Paint(preview)
        end)
    end
    preview.tabs[1]:SetActive(true)
    preview.combatButton = T.Button(root, "In combat", 120, 25)
    HM.SkipHistoryCheckpoint(preview.combatButton)
    preview.combatButton:SetScript("OnClick", function(button)
        preview.kit:Release()
        preview.combat = not preview.combat
        if not preview.combat then preview.restricted = false end
        button:SetActive(preview.combat)
        preview.restrictionsButton:SetEnabled(preview.combat)
        preview.restrictionsButton:SetActive(preview.restricted == true)
        preview.titleButton:SetEnabled(not preview.restricted)
        Paint(preview)
    end)
    local restrictions = T.Button(root, "Combat restrictions", 150, 25)
    preview.restrictionsButton = restrictions
    HM.SkipHistoryCheckpoint(restrictions)
    restrictions:SetEnabled(false)
    restrictions:SetScript("OnClick", function(button)
        if not preview.combat then return end
        preview.kit:Release()
        preview.restricted = not preview.restricted
        button:SetActive(preview.restricted)
        preview.titleButton:SetEnabled(not preview.restricted)
        Paint(preview)
    end)
    preview.titleButton = T.Button(root, "Title", 140, 25)
    HM.SkipHistoryCheckpoint(preview.titleButton)
    preview.titleButton:SetScript("OnClick", function() return SelectTitle(preview) end)
end

local function Build(ui, skin)
    local root = CreateFrame("Frame", nil, ui.header)
    root:SetAllPoints(ui.header)
    local stage = CreateFrame("Frame", nil, root)
    skin.Surface.Attach(stage, { role = "panel", radius = 7 })
    local preview = { ui = ui, skin = skin, card = skin.ItemTooltipCard, root = root, stage = stage,
        selected = 1, tabs = {}, layers = {}, handles = {}, palette = skin.TooltipPalette }
    preview.paintChrome, preview.paintFill = SampleSpec(preview.palette), SampleSpec(preview.palette, 0)
    preview.host = P.Suite.PreviewKit.NewHost(nil, { frame = stage, paint = function() Paint(preview) end })
    Sample(preview)
    preview.layerSpecs = LAYERS
    if preview.vitals then
        preview.layerSpecs = { unpack(LAYERS) }
        for _, spec in ipairs(VITAL_LAYERS) do preview.layerSpecs[#preview.layerSpecs + 1] = spec end
    end
    preview.bar = Interaction.Bar(ui.ctx, root, ui.width - 32)
    BuildHandles(preview)
    BuildAnchorHandle(preview)
    BuildSelection(preview)
    BuildPreviewButtons(preview)
    P.BindTooltipPositionSearch(preview, SelectTitle, Paint)
    Interaction.BuildLayerRail(preview, root, preview.layerSpecs, function(key, visible)
        if key == "health" or key == "power" then
            local field = key == "health" and "unitHealth" or "unitPower"
            local value = visible
            if key == "health" then value = visible and "show" or "hide" end
            local label = key == "health" and "Health bar" or "Resource Bar"
            return Kit.Change(skin, label, LAYOUT .. field, function() return preview.card.Set(field, value) end)
        end
        if key == "healthText" then return Open(preview, VITAL_LAYERS[2]) end
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
    if preview.vitals then
        skin.Registry.AddListener(preview, function(_, domain)
            if domain == "tooltipMedia" then Paint(preview) end
        end)
    end
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
