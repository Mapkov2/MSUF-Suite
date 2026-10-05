local _, P = ...
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local Preview = P.ActionBarPreview
local ID, PAGE = "actionbars", "suite_actionbars"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\Halo"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "" }
local function Edges(parent)
    local edges = {}
    for i = 1, 4 do edges[i] = parent:CreateTexture(nil, "OVERLAY") end
    return edges
end
local function Border(edges, target, size, color, shown)
    local r, g, b = P.RGB(color)
    for i, edge in ipairs(edges) do
        edge:SetShown(shown and size > 0)
        edge:SetColorTexture(r, g, b, 1)
        edge:ClearAllPoints()
        if i <= 2 then
            local point = i == 1 and "TOP" or "BOTTOM"
            edge:SetPoint(point .. "LEFT", target, point .. "LEFT")
            edge:SetPoint(point .. "RIGHT", target, point .. "RIGHT")
            edge:SetHeight(size)
        else
            local point = i == 3 and "LEFT" or "RIGHT"
            edge:SetPoint("TOP" .. point, target, "TOP" .. point)
            edge:SetPoint("BOTTOM" .. point, target, "BOTTOM" .. point)
            edge:SetWidth(size)
        end
    end
end

local function Focus(ui, suffix)
    local workspace = ui.ctx._msufSuiteActionBarWorkspace
    if not workspace then return end
    for _, body in ipairs(workspace.sections) do
        if body._msufSuiteActionBarSectionId == "suite_actionbars_" .. suffix then
            body._msufSuiteActionBarReveal()
            if W.FocusCollapsibleSection then W.FocusCollapsibleSection(body, { persist = true, flash = true }) end
            return
        end
    end
end
local function Target(ui, button, key, section)
    button:SetScript("OnClick", function() Focus(ui, section) end)
    button._msuf2SkipHistoryCheckpoint = true
    button._msuf2AllowCombatClick = true
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "preview." .. key, "ephemeral", "suite_actionbars_" .. section),
            "Preview", "button")
    end
end
local function NewCooldown(tile)
    local cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
    cooldown:SetAllPoints(tile.icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:EnableMouse(false)
    return cooldown
end
local function NewTile(ui, ordinal)
    local tile = CreateFrame("Button", nil, ui.canvas)
    tile.fill = tile:CreateTexture(nil, "BACKGROUND")
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.mask = tile:CreateMaskTexture()
    tile.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tile.mask:SetAllPoints(tile.icon)
    tile.edges = Edges(tile)
    tile.art = tile:CreateTexture(nil, "OVERLAY")
    tile.cooldown, tile.chargeCooldown = NewCooldown(tile), NewCooldown(tile)
    tile.chargeCooldown:SetDrawSwipe(false)
    tile.text = CreateFrame("Button", nil, tile)
    tile.text:SetAllPoints(tile)
    tile.text:SetFrameLevel(tile.cooldown:GetFrameLevel() + 1)
    tile.text:EnableMouse(false)
    tile.key = T.Font(tile.text, "GameFontHighlightSmall", "", T.colors.text)
    tile.count = T.Font(tile.text, "GameFontHighlightSmall", "", T.colors.text)
    tile.name = T.Font(tile.text, "GameFontHighlightSmall", "", T.colors.text)
    tile.textHit = CreateFrame("Button", nil, tile.text)
    tile.textHit:SetPoint("TOPLEFT")
    tile.textHit:SetPoint("TOPRIGHT")
    tile.textHit:SetHeight(14)
    Target(ui, tile.textHit, "key" .. ordinal, "bar_text")
    Target(ui, tile, "button" .. ordinal, "appearance")
    return tile
end

local function Font(label, config, prefix, group, default, x, y, size, color, shown, owner)
    P.StylePreviewFont(label, Suite.ResolveFont(config.font), math.max(6, size), OUTLINES[config.fontOutline] or "",
        config.fontRendering, config.fontShadow, config.fontShadowOpacity, config.fontShadowDistance)
    local point = Suite.AnchorPoints[(config[prefix .. group .. "Point"] or 1) - 1]
    if point then x, y = 0, 0 else point = default end
    label:ClearAllPoints()
    label:SetPoint(point, owner, point, x + config[prefix .. group .. "X"], y + config[prefix .. group .. "Y"])
    label:SetTextColor(P.RGB(color))
    label:SetWordWrap(false)
    label:SetShown(shown)
end
local function StyleText(tile, c, p, bar, size)
    local nativeFont = bar >= 11 and 2 or 0
    local border = c.borderSize
    Font(tile.key, c, p, "Keybind", "TOPRIGHT", -1 - border, -2 - border,
        c[p .. "KeybindSize"] - nativeFont, c.keybindColor, c[p .. "Keybind"], tile)
    Font(tile.count, c, p, "Count", "BOTTOMRIGHT", -1 - border, 2 + border,
        c[p .. "CountSize"], c.countColor, true, tile)
    Font(tile.name, c, p, "Macro", "BOTTOM", 0, 2 + border,
        c[p .. "MacroSize"], c.macroColor, bar <= 10 and c[p .. "Macro"], tile)
    tile.key:SetWidth(math.max(1, size - 2))
    tile.name:SetWidth(math.max(1, size - 2))
    tile.textHit:SetHeight(math.min(size / 2, c[p .. "KeybindSize"] + 5))
    for _, cooldown in ipairs({ tile.cooldown, tile.chargeCooldown }) do
        local text = cooldown:GetCountdownFontString()
        if text then
            local fontSize = math.max(6, c[p .. "CooldownSize"] - nativeFont)
            if c[p .. "CooldownAutoSize"] then fontSize = math.min(fontSize, math.max(6, math.floor(size * .42))) end
            Font(text, c, p, "Cooldown", "CENTER", 0, 0, fontSize, c.cooldownColor, c.cooldownNumbers, tile)
        end
    end
    tile.cooldown:SetHideCountdownNumbers(not c.cooldownNumbers)
    tile.chargeCooldown:SetHideCountdownNumbers(not (c.cooldownNumbers and c.rechargeNumbers))
    local r, g, b = P.RGB(c.swipeColor)
    tile.cooldown:SetSwipeColor(r, g, b, c.swipeAlpha / 100)
end
local function BorderColor(c)
    if c.borderClassColor then
        local _, class = UnitClass("player")
        if not Suite.IsSecret(class) and class and RAID_CLASS_COLORS[class] then
            local color = RAID_CLASS_COLORS[class]
            return string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        end
    end
    return c.borderColor
end
local function StyleTile(tile, c, p, bar, size, color)
    local border, zoom = c.borderSize, c.iconZoom / 100
    tile:SetSize(size, size)
    tile.icon:ClearAllPoints()
    tile.icon:SetPoint("TOPLEFT", border, -border)
    tile.icon:SetPoint("BOTTOMRIGHT", -border, border)
    tile.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    tile.fill:SetAllPoints(tile.icon)
    local r, g, b = P.RGB(c.slotColor)
    tile.fill:SetColorTexture(r, g, b, c.slotAlpha / 100)
    local circle = c.buttonShape == Suite.ActionBarEnum.BUTTON_SHAPE.CIRCLE
    if circle ~= tile.masked then
        local method = circle and "AddMaskTexture" or "RemoveMaskTexture"
        tile.icon[method](tile.icon, tile.mask)
        tile.fill[method](tile.fill, tile.mask)
        tile.masked = circle
    end
    tile.cooldown:SetSwipeTexture(circle and CIRCLE or WHITE)
    tile.chargeCooldown:SetSwipeTexture(circle and CIRCLE or WHITE)
    local fancy = circle or c.borderArt == Suite.ActionBarEnum.BORDER_ART.BLIZZARD
    Border(tile.edges, tile, border, color, not fancy)
    tile.art:SetShown(fancy and border > 0)
    if fancy then
        if circle then tile.art:SetTexture(RING) else tile.art:SetAtlas("UI-HUD-ActionBar-IconFrame") end
        tile.art:SetVertexColor(P.RGB(color))
        tile.art:ClearAllPoints()
        tile.art:SetPoint("CENTER")
        local extent = (size + c.borderExpansion * 2) * c.borderScale / 100
        tile.art:SetSize(extent, extent)
    end
    StyleText(tile, c, p, bar, size)
end

local function Endcap(ui, c, p, side, color)
    local style = c[p .. side .. "Endcap"]
    local cap = ui.caps[side]
    cap:SetShown(style ~= Suite.ActionBarEnum.ENDCAP.NONE)
    local size, direction = c[p .. side .. "EndcapSize"], side == "Left" and -1 or 1
    cap:SetSize(size, size)
    cap:ClearAllPoints()
    cap:SetPoint("CENTER", ui.canvas, side == "Left" and "LEFT" or "RIGHT",
        direction * size * .6 + c[p .. side .. "EndcapX"], c[p .. side .. "EndcapY"])
    local diamond = style == Suite.ActionBarEnum.ENDCAP.DIAMOND
    for i, piece in ipairs(cap.pieces) do
        piece:SetShown(i <= (diamond and 2 or 4))
        piece:ClearAllPoints()
        piece:SetColorTexture(P.RGB(color))
        if diamond then
            piece:SetSize(size * .55, i == 1 and size * .55 or size * .3)
            piece:SetPoint("CENTER")
            piece:SetRotation(math.pi / 4)
            if i == 2 then piece:SetColorTexture(.08, .08, .08, 1) end
        else
            piece:SetSize(size * .55, math.max(1, size / 10))
            piece:SetPoint("CENTER", direction * math.floor((i - 1) / 2) * size * .28,
                i % 2 == 0 and -size * .16 or size * .16)
            piece:SetRotation(direction * (i % 2 == 0 and math.pi / 4 or -math.pi / 4))
        end
    end
end
local function Background(ui, c, p, width, height, color)
    local pad = c[p .. "BackgroundPadding"]
    local px, py = c[p .. "BackgroundPaddingX"], c[p .. "BackgroundPaddingY"]
    px, py = px < 0 and pad or px, py < 0 and pad or py
    local back = ui.background
    back:SetShown(c[p .. "Background"])
    back:ClearAllPoints()
    back:SetPoint("CENTER", ui.canvas, "CENTER", c[p .. "BackgroundX"], c[p .. "BackgroundY"])
    back:SetSize(width + px * 2, height + py * 2)
    local r, g, b = P.RGB(c[p .. "BackgroundColor"])
    back.fill:SetColorTexture(r, g, b, c[p .. "BackgroundAlpha"] / 100)
    Border(back.edges, back, c[p .. "BackgroundBorder"], color, true)
end

-- Fit the whole decorated bar, including asymmetric offsets, inside the
-- canvas. Large padding or endcaps must not overlap the header controls.
local function Bounds(c, p, width, height, size)
    local edge = math.max(0, ((size + c.borderExpansion * 2) * c.borderScale / 100 - size) / 2)
    local padX, padY = edge, edge
    for _, group in ipairs({ "Keybind", "Count", "Macro", "Cooldown" }) do
        local shown = group == "Count" or group == "Cooldown" and c.cooldownNumbers
            or (group == "Keybind" or group == "Macro") and c[p .. group]
        if shown then
            local overhang = math.max(0, c[p .. group .. "Size"] - size)
            padX = math.max(padX, math.abs(c[p .. group .. "X"]) + overhang)
            padY = math.max(padY, math.abs(c[p .. group .. "Y"]) + overhang)
        end
    end
    local left, right, bottom, top = -width / 2 - padX, width / 2 + padX, -height / 2 - padY, height / 2 + padY
    if c[p .. "Background"] then
        local pad, px, py = c[p .. "BackgroundPadding"], c[p .. "BackgroundPaddingX"], c[p .. "BackgroundPaddingY"]
        px, py = px < 0 and pad or px, py < 0 and pad or py
        local x, y = c[p .. "BackgroundX"], c[p .. "BackgroundY"]
        left, right = math.min(left, x - width / 2 - px), math.max(right, x + width / 2 + px)
        bottom, top = math.min(bottom, y - height / 2 - py), math.max(top, y + height / 2 + py)
    end
    for _, side in ipairs({ "Left", "Right" }) do
        if c[p .. side .. "Endcap"] ~= 1 then
            local cap = c[p .. side .. "EndcapSize"]
            local direction = side == "Left" and -1 or 1
            local x = direction * (width / 2 + cap * .6) + c[p .. side .. "EndcapX"]
            local y = c[p .. side .. "EndcapY"]
            left, right = math.min(left, x - cap / 2), math.max(right, x + cap / 2)
            bottom, top = math.min(bottom, y - cap / 2), math.max(top, y + cap / 2)
        end
    end
    return left - 4, right + 4, bottom - 4, top + 4
end

function Preview.RefreshScope(ui)
    local bar, c = ui.selected(), S.Config(ID)
    local p = "bar" .. bar
    if P.ActionBarMenu.IsShared(ui.ctx) then
        P.SetTranslatedText(ui.status, Tr("Shared settings affect every action bar."))
        return
    end
    local label = Tr(Suite.ActionBarTitles[bar])
    if c[p .. "Visibility"] == 6 then label = Tr("%s (hidden)"):format(label) end
    if S.ActionBarAvailable and not S.ActionBarAvailable(bar) then
        label = Tr("%s (not available on this client)"):format(label)
    end
    P.SetTranslatedText(ui.status, string.format(Tr("Editing: %s"), label))
end

local function Paint(ui)
    Preview.RefreshScope(ui)
    local bar, c = ui.selected(), S.Config(ID)
    local p = "bar" .. bar
    local count, size, gap = c[p .. "Buttons"], c[p .. "Size"], c[p .. "Spacing"]
    local columns, rows, r = Suite.ActionBarGrid(count, c[p .. "Rows"], c[p .. "Vertical"])
    local width, height = columns * size + (columns - 1) * gap, rows * size + (rows - 1) * gap
    local left, right, bottom, top = Bounds(c, p, width, height, size)
    local fit = math.min(1, ui.width / (right - left), (ui.height - 44) / (top - bottom))
    ui.canvas:SetSize(width, height)
    ui.canvas:SetScale(fit)
    ui.canvas:ClearAllPoints()
    -- Native anchors scale these local offsets together with the canvas.
    ui.canvas:SetPoint("CENTER", ui.host, "CENTER", -(left + right) / 2, 2 / fit - (top + bottom) / 2)
    ui.canvas:SetAlpha(math.max(.1, c[p .. "Alpha"] / 100))
    local color = BorderColor(c)
    Background(ui, c, p, width, height, color)
    for i, tile in ipairs(ui.tiles) do
        local shown = i <= count
        if shown then
            Preview.Read(tile, bar, i, c)
            StyleTile(tile, c, p, bar, size, color)
            local col, row = Suite.ActionBarCell(i - 1, columns, rows, r, c[p .. "Vertical"], c[p .. "Start"])
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", ui.canvas, "TOPLEFT", col * (size + gap), -row * (size + gap))
            shown = tile.filled or c[p .. "ShowEmpty"]
        end
        tile:SetShown(shown)
    end
    Endcap(ui, c, p, "Left", color)
    Endcap(ui, c, p, "Right", color)
end

function Preview.Build(ctx, parent, y, width, height, selected)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", 16, y)
    host:SetSize(width, height)
    host:SetClipsChildren(true)
    local ui = { ctx = ctx, host = host, width = width, height = height, selected = selected, tiles = {}, caps = {} }
    ctx._msufSuiteActionBarPreview = ui
    ui.status = P.Text(host, "", 0, 0, width, T.colors.muted)
    ui.canvas = CreateFrame("Frame", nil, host)
    ui.canvas:SetPoint("CENTER", host, "CENTER", 0, 2)
    ui.background = CreateFrame("Button", nil, ui.canvas)
    ui.background.fill = ui.background:CreateTexture(nil, "BACKGROUND")
    ui.background.fill:SetAllPoints()
    ui.background.edges = Edges(ui.background)
    Target(ui, ui.background, "background", "bar_background")
    for i = 1, 12 do ui.tiles[i] = NewTile(ui, i) end
    for _, side in ipairs({ "Left", "Right" }) do
        local cap = CreateFrame("Button", nil, ui.canvas)
        cap.pieces = {}
        for i = 1, 4 do cap.pieces[i] = cap:CreateTexture(nil, "ARTWORK") end
        ui.caps[side] = cap
        Target(ui, cap, side .. "Endcap", "bar_ornaments")
    end
    local hint = P.Text(host, "Click the preview to open the matching settings.", 0, -(height - 16), width)
    ui.hint = hint
    ui.Paint = function() Paint(ui) end
    M.TrackRefresh(ctx, function() if ui.active or host:IsVisible() then ui.Paint() end end)
    Preview.Watch(ui)
    ui.Paint()
    return height
end
