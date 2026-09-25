local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local WIDTH = 484
local Pixel, Percent = O.Pixel, O.Percent

------------------------------------------------------------------ value labels
local PresetLabel = O.Labeler({
    forever = L["MSUF Forever"],
    modern = L["Midnight Blue"],
    midnightDark = L["Midnight Dark"],
    custom = L["Custom"],
})
local WindowActionStyleLabel = O.Labeler({
    bare = L["Bare"],
    soft = L["Soft"],
    outline = L["Outline"],
    native = L["Native"],
})
local WindowActionGlyphLabel = O.Labeler({ plusMinus = "+ / -", chevrons = L["Chevrons"] })
local WindowActionWeightLabel = O.Labeler({ fine = L["Fine"], bold = L["Bold"] })
local IconStyleLabel = O.Labeler({
    line = L["Line glyphs"],
    bold = L["Bold glyphs"],
    blizzardIcons = L["Blizzard icons"],
    blizzard = L["Full Blizzard"],
})
local HoverStyleLabel = O.Labeler({
    outline = L["Outline"],
    softFill = L["Soft"],
    solidFill = L["Solid"],
    iconOnly = L["Icon"],
    off = L["Off"],
})
local TintLabel = O.Labeler({
    native = L["Native"],
    theme = L["Theme"],
    class = L["Class"],
    monochrome = L["Mono"],
})
local ShapeLabel = O.Labeler({
    global = L["Global"],
    round = L["Round"],
    continuous = L["Smooth"],
    squircle = L["Squircle"],
})
local LayoutModeLabel = O.Labeler({ owned = L["MSKIN Bar"], blizzard = L["Blizzard"] })
local OrientationLabel = O.Labeler({ horizontal = L["Horizontal"], vertical = L["Vertical"] })
local GrowthLabel = O.Labeler({
    RIGHT_DOWN = L["Right / down"],
    LEFT_DOWN = L["Left / down"],
    RIGHT_UP = L["Right / up"],
    LEFT_UP = L["Left / up"],
})
local PositionPresetLabel = O.Labeler({
    bottomLeft = L["Bottom left"],
    bottomRight = L["Bottom right"],
    bottomCenter = L["Bottom center"],
    topRight = L["Top right"],
    topCenter = L["Top center"],
    custom = L["Custom"],
})
local IconBorderLabel = O.Labeler({ quality = L["Quality"], theme = L["Theme"], off = L["Off"] })

local function ButtonCount(value)
    value = math.floor((tonumber(value) or 1) + 0.5)
    return value == 1 and L["1 button"] or L["%d buttons"]:format(value)
end

local function BorderLabel(value)
    value = tonumber(value) or 0
    return value <= 0 and L["Off"] or Pixel(value)
end

------------------------------------------------------------------ settings rows
-- Rows in page order. kind: heading, preview, toggle, segmented or slider.
-- source picks the setting table and its setter (micro, action, theme);
-- set/get override them. essential rows stay in Guided mode. gate: "layout"
-- rows need the Suite-owned bar, "micro" rows need Micro Bar skinning.
local ROWS = {
    { kind = "heading", label = L["WINDOW ACTIONS"], essential = true },
    { kind = "segmented", label = L["Button style"], source = "action", key = "style",
        values = NS.WindowActionStyles, format = WindowActionStyleLabel, essential = true },
    { kind = "segmented", label = L["Maximize / minimize symbols"], source = "action", key = "glyphMode",
        values = NS.WindowActionGlyphModes, format = WindowActionGlyphLabel, essential = true },
    { kind = "segmented", label = L["Line weight"], source = "action", key = "weight",
        values = NS.WindowActionWeights, format = WindowActionWeightLabel },
    { kind = "slider", label = L["Maximize / minimize size"], source = "action", key = "glyphSize",
        min = 8, max = 18, format = Pixel },
    { kind = "slider", label = L["Close X size"], source = "action", key = "closeGlyphSize",
        min = 6, max = 18, format = Pixel, essential = true },
    { kind = "segmented", label = L["Button shape"], source = "action", key = "surfaceShape",
        values = NS.WindowActionShapes, format = ShapeLabel },
    { kind = "segmented", label = L["Button corner radius"], source = "action", key = "surfaceRadius",
        values = NS.GeometryRadii, format = Pixel },
    { kind = "slider", label = L["Visual inset (larger makes the button smaller)"], source = "action",
        key = "surfaceInset", min = 0, max = 6, format = Pixel },
    { kind = "slider", label = L["Glyph horizontal offset"], source = "action", key = "glyphOffsetX",
        min = -4, max = 4, format = Pixel },
    { kind = "slider", label = L["Glyph vertical offset"], source = "action", key = "glyphOffsetY",
        min = -4, max = 4, format = Pixel },
    { kind = "slider", label = L["Idle glyph opacity"], source = "action", key = "opacity",
        min = 0.35, max = 1, step = 0.05, format = Percent },
    { kind = "preview", essential = true },

    { kind = "heading", label = L["MICRO BAR"], essential = true },
    { kind = "toggle", label = L["Skin the Blizzard Micro Bar"], essential = true,
        get = function() return NS.DB.skins.microMenu end,
        set = function(value) NS.Adapters.SetEnabled("microMenu", value) end },

    { kind = "heading", label = L["MSKIN-OWNED MICRO BAR"], essential = true },
    { kind = "segmented", label = L["Layout engine"], source = "micro", key = "layoutMode",
        values = NS.MicroMenuLayoutModes, format = LayoutModeLabel, essential = true, gate = "micro" },
    { kind = "segmented", label = L["Screen position"], source = "micro", key = "positionPreset",
        values = { "bottomLeft", "bottomRight", "bottomCenter", "topRight", "topCenter", "custom" },
        format = PositionPresetLabel, essential = true, gate = "layout",
        set = function(value)
            if value ~= "custom" then NS.MicroMenuSkin.SetPositionPreset(value) end
        end },
    { kind = "segmented", label = L["Bar direction"], source = "micro", key = "orientation",
        values = NS.MicroMenuOrientations, format = OrientationLabel, essential = true, gate = "layout" },
    { kind = "toggle", label = L["Lock bar position (unlock to drag)"], source = "micro", key = "locked",
        essential = true, gate = "layout" },
    { kind = "slider", label = L["Bar scale"], source = "micro", key = "scale",
        min = 0.5, max = 1.5, step = 0.05, format = Percent, essential = true, gate = "layout" },

    { kind = "heading", label = L["ADVANCED BAR LAYOUT"] },
    { kind = "segmented", label = L["Growth direction"], source = "micro", key = "growth",
        values = NS.MicroMenuGrowthModes, format = GrowthLabel, gate = "layout" },
    { kind = "slider", label = L["Buttons per line"], source = "micro", key = "buttonsPerLine",
        min = 1, max = NS.Client and NS.Client.isForever and 14 or 13, format = ButtonCount, gate = "layout" },
    { kind = "slider", label = L["Button spacing"], source = "micro", key = "spacing",
        min = -8, max = 16, format = Pixel, gate = "layout" },
    { kind = "slider", label = L["Bar padding"], source = "micro", key = "padding",
        min = 0, max = 16, format = Pixel, gate = "layout" },
    { kind = "slider", label = L["Horizontal offset"], source = "micro", key = "layoutX",
        min = -4096, max = 4096, format = Pixel, gate = "layout" },
    { kind = "slider", label = L["Vertical offset"], source = "micro", key = "layoutY",
        min = -4096, max = 4096, format = Pixel, gate = "layout" },

    { kind = "segmented", label = L["Micro Bar style"], source = "micro", key = "preset",
        values = { "modern", "midnightDark", "forever", "custom" }, format = PresetLabel,
        essential = true, gate = "micro",
        set = function(value)
            if value ~= "custom" then NS.MicroMenuSkin.ApplyPreset(value) end
        end },
    { kind = "segmented", label = L["Icon artwork"], source = "micro", key = "iconStyle",
        values = NS.MicroMenuIconStyles, format = IconStyleLabel, essential = true, gate = "micro" },
    { kind = "segmented", label = L["Icon colors"], source = "micro", key = "tint",
        values = NS.MicroMenuTintModes, format = TintLabel, essential = true, gate = "micro" },
    { kind = "slider", label = L["Visual button size"], source = "micro", key = "buttonSize",
        min = 20, max = 32, format = Pixel, essential = true, gate = "micro" },
    -- A glyph needs 4 px of room inside its button; bigger glyphs grow the button.
    { kind = "slider", label = L["Glyph size"], source = "micro", key = "iconSize",
        min = 10, max = 28, format = Pixel, essential = true, gate = "micro",
        set = function(value)
            if value > (NS.DB.icons.microMenu.buttonSize or 28) - 4 then
                NS.MicroMenuSkin.SetOption("buttonSize", math.min(32, math.floor(value + 4.5)))
            end
            NS.MicroMenuSkin.SetOption("iconSize", value)
        end },
    { kind = "segmented", label = L["Mouse-over effect"], source = "micro", key = "hoverStyle",
        values = NS.MicroMenuHoverStyles, format = HoverStyleLabel, essential = true, gate = "micro" },
    { kind = "segmented", label = L["Verified item icon borders"], source = "theme", key = "iconBorderStyle",
        values = NS.IconBorderStyles, format = IconBorderLabel, essential = true },

    { kind = "heading", label = L["MICRO BAR MATERIALS"] },
    { kind = "toggle", label = L["Bar background"], source = "micro", key = "barBackground", gate = "micro" },
    { kind = "segmented", label = L["Bar border"], source = "micro", key = "barBorder",
        values = { 0, 1, 2 }, format = BorderLabel, gate = "micro" },
    { kind = "segmented", label = L["Bar material"], source = "micro", key = "barMaterial",
        values = NS.MicroMenuBarMaterials, format = PresetLabel, gate = "micro" },
    { kind = "toggle", label = L["Individual button backgrounds"], source = "micro", key = "buttonBackground",
        gate = "micro" },
    { kind = "segmented", label = L["Individual button borders"], source = "micro", key = "buttonBorder",
        values = { 0, 1, 2 }, format = BorderLabel, gate = "micro" },
    { kind = "segmented", label = L["Bar and button shape"], source = "micro", key = "shape",
        values = NS.MicroMenuShapes, format = ShapeLabel, gate = "micro" },
    { kind = "segmented", label = L["Corner radius"], source = "micro", key = "radius",
        values = NS.GeometryRadii, format = Pixel, gate = "micro" },

    { kind = "heading", label = L["MICRO ICON STATES"] },
    { kind = "slider", label = L["Normal icon opacity"], source = "micro", key = "normalOpacity",
        min = 0, max = 1, step = 0.05, format = Percent, gate = "micro" },
    { kind = "slider", label = L["Mouse-over icon opacity"], source = "micro", key = "hoverOpacity",
        min = 0, max = 1, step = 0.05, format = Percent, gate = "micro" },
    { kind = "slider", label = L["Pressed icon opacity"], source = "micro", key = "pressedOpacity",
        min = 0, max = 1, step = 0.05, format = Percent, gate = "micro" },
    { kind = "slider", label = L["Disabled icon opacity"], source = "micro", key = "disabledOpacity",
        min = 0, max = 1, step = 0.05, format = Percent, gate = "micro" },

    { kind = "heading", label = L["GLOBAL ITEM ICON BORDERS"] },
    { kind = "slider", label = L["Border thickness"], source = "theme", key = "iconBorderThickness",
        min = 1, max = 3, format = Pixel },
    { kind = "slider", label = L["Distance from icon"], source = "theme", key = "iconBorderPadding",
        min = 0, max = 3, format = Pixel },
    { kind = "slider", label = L["Border opacity"], source = "theme", key = "iconBorderOpacity",
        min = 0, max = 1, step = 0.05, format = Percent },
}

local function SettingsTable(source)
    if source == "micro" then return NS.DB.icons.microMenu end
    if source == "action" then return NS.DB.icons.windowActions end
    return NS.DB.theme
end

local SETTERS = {
    micro = function(key, value) return NS.MicroMenuSkin.SetOption(key, value) end,
    action = function(key, value) return NS.WindowActionSkin.SetOption(key, value) end,
    theme = function(key, value) return NS.Theme.SetAppearance(key, value) end,
}

local function RowGetter(spec)
    if spec.get then return spec.get end
    local source, key = spec.source, spec.key
    return function() return SettingsTable(source)[key] end
end

local function RowSetter(spec)
    if spec.set then return spec.set end
    local setter, key = SETTERS[spec.source], spec.key
    return function(value) setter(key, value) end
end

local function ResetWithHistory(label, reset)
    O.BeginUserChange(label)
    if reset() == false then
        O.CancelUserChange()
        return
    end
    O.CommitUserChange(label)
end

------------------------------------------------------------------ window action preview
local WINDOW_ACTION_KINDS = { "maximize", "minimize", "close" }

local function CreateWindowActionPreview(parent)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(WIDTH, 82)
    local label = O.CreateText(row, L["Live window-action preview"], 12, "text")
    label:SetPoint("TOPLEFT", 12, -10)
    local note = O.CreateText(row, L["Native hit targets, independent artwork"], 9, "dim")
    note:SetPoint("BOTTOMLEFT", 12, 12)

    local reset = O.CreateButton(row, L["Reset actions"], 104, 24, function()
        ResetWithHistory(L["Reset Window Actions"], NS.WindowActionSkin.ResetRecommended)
    end)
    reset:SetPoint("BOTTOMRIGHT", -10, 8)

    local buttons = {}
    for index, kind in ipairs(WINDOW_ACTION_KINDS) do
        local button = CreateFrame("Button", nil, row)
        button:SetSize(28, 28)
        button:SetPoint("RIGHT", -124 - (#WINDOW_ACTION_KINDS - index) * 34, 4)
        O.SeedWindowActionTextures(button, kind)
        buttons[index] = button
    end

    local function Refresh()
        for index, kind in ipairs(WINDOW_ACTION_KINDS) do
            local button = buttons[index]
            if NS.Checkmarks then NS.Checkmarks.TrackButton(button, "options-window-actions") end
            NS.WindowActionSkin.Apply(button, "options-window-actions", kind)
        end
    end
    O.TrackRefresh(Refresh)
    Refresh()
    return row
end

local function CreateRow(list, spec)
    local kind = spec.kind
    if kind == "heading" then return O.CreateSubheading(list, spec.label, WIDTH) end
    if kind == "preview" then return CreateWindowActionPreview(list) end
    local get, set = RowGetter(spec), RowSetter(spec)
    if kind == "toggle" then
        return O.CreateToggle(list, spec.label, get, set, WIDTH)
    elseif kind == "segmented" then
        return O.CreateSegmented(list, spec.label, spec.values, get, set, WIDTH, spec.format)
    end
    return O.CreateSlider(list, spec.label, spec.min, spec.max, spec.step or 1, get, set, WIDTH, spec.format)
end

-- The left column. Returns the widgets each gate enables.
local function BuildControls(page)
    local controlsHost = CreateFrame("Frame", nil, page)
    controlsHost:SetPoint("TOPLEFT", 4, -70)
    controlsHost:SetPoint("BOTTOMLEFT", 4, 4)
    controlsHost:SetWidth(510)
    local controlsScroll, list = O.CreateScrollContainer(controlsHost, 2500, WIDTH)
    page._mskinIconsScroll = controlsScroll
    page._mskinIconsContent = list

    local rows, gates = {}, { layout = {}, micro = {} }
    for index = 1, #ROWS do
        local spec = ROWS[index]
        local widget = CreateRow(list, spec)
        rows[index] = { widget, spec.essential == true }
        if spec.gate then
            local gated = gates[spec.gate]
            gated[#gated + 1] = widget
        end
    end
    local RefreshMode = O.StackRows(list, rows)
    O.TrackMode(RefreshMode)
    RefreshMode()
    return gates
end

------------------------------------------------------------------ live preview
local PREVIEW_STATES = {
    { key = "normal", label = L["Normal"], suffix = "Up", button = "ProfessionMicroButton" },
    { key = "hover", label = L["Hover"], suffix = "Mouseover", button = "PlayerSpellsMicroButton" },
    { key = "pressed", label = L["Pressed"], suffix = "Down", button = "QuestLogMicroButton" },
    { key = "disabled", label = L["Disabled"], suffix = "Disabled", button = "GuildMicroButton" },
}
local BAR_ROLES = {
    forever = "microBarForever",
    modern = "microBarModern",
    midnightDark = "microBarDark",
}
local ITEM_QUALITY_SAMPLE = { 0.639, 0.208, 0.933, 1 }

local function BuildMicroPreview(preview, view)
    local microPreview = O.CreatePanel(preview, "panel")
    microPreview:SetPoint("TOPLEFT", 16, -44)
    microPreview:SetPoint("TOPRIGHT", -16, -44)
    microPreview:SetHeight(174)
    local microTitle = O.CreateText(microPreview, L["Blizzard Micro Bar"], 12, "title")
    microTitle:SetPoint("TOPLEFT", 12, -12)

    local bar = CreateFrame("Frame", nil, microPreview)
    bar:SetPoint("TOPLEFT", 12, -38)
    bar:SetPoint("TOPRIGHT", -12, -38)
    bar:SetHeight(70)
    view.bar = bar
    view.barSpec = { role = "microBar", shape = "continuous", radius = 6, border = 1 }
    NS.Surface.Attach(bar, view.barSpec)

    view.buttons = {}
    local iconStyle = NS.DB.icons.microMenu.iconStyle
    for index, stateInfo in ipairs(PREVIEW_STATES) do
        local button = CreateFrame("Frame", nil, bar)
        button:SetSize(42, 50)
        if index == 1 then
            button:SetPoint("LEFT", 8, 0)
        else
            button:SetPoint("LEFT", view.buttons[index - 1].frame, "RIGHT", 8, 0)
        end
        local spec = { role = "microButton", shape = "continuous", radius = 6, border = 1 }
        NS.Surface.Attach(button, spec)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", 0, 1)
        NS.MicroMenuVisual.ApplyIcon(icon, stateInfo.button, iconStyle)
        icon:SetSize(18, 18)
        view.buttons[index] = { frame = button, spec = spec, icon = icon, info = stateInfo }

        local label = O.CreateText(microPreview, stateInfo.label, 9, "dim", "CENTER")
        label:SetPoint("TOP", button, "BOTTOM", 0, -5)
        label:SetWidth(48)
    end

    view.status = O.CreateText(microPreview, "", 10, "muted")
    view.status:SetPoint("BOTTOMLEFT", 12, 10)
    view.status:SetPoint("RIGHT", -12, 0)
    return microPreview
end

local function CreateItemBorderSample(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(48, 48)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(38, 38)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    local lines = {}
    for index = 1, 4 do
        lines[index] = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    end

    local function Refresh()
        local theme = NS.DB.theme
        -- The same border geometry and clamping as real item buttons.
        NS.IconSkin.AnchorLines(lines, icon, theme.iconBorderThickness, theme.iconBorderPadding)
        local style = theme.iconBorderStyle
        local r, g, b, a
        if style == "quality" then
            r, g, b, a = ITEM_QUALITY_SAMPLE[1], ITEM_QUALITY_SAMPLE[2], ITEM_QUALITY_SAMPLE[3], ITEM_QUALITY_SAMPLE[4]
        else
            r, g, b, a = NS.Theme.GetColor("iconBorder")
        end
        a = (tonumber(a) or 1) * (tonumber(theme.iconBorderOpacity) or 1)
        for index = 1, 4 do
            lines[index]:SetColorTexture(r, g, b, a)
            lines[index]:SetShown(style ~= "off")
        end
    end
    O.TrackRefresh(Refresh)
    Refresh()
    return holder
end

local function BuildItemPreview(preview, microPreview)
    local itemPreview = O.CreatePanel(preview, "card")
    itemPreview:SetPoint("TOPLEFT", microPreview, "BOTTOMLEFT", 0, -12)
    itemPreview:SetPoint("TOPRIGHT", microPreview, "BOTTOMRIGHT", 0, -12)
    itemPreview:SetHeight(94)
    local itemTitle = O.CreateText(itemPreview, L["Global item borders"], 12, "title")
    itemTitle:SetPoint("TOPLEFT", 12, -12)
    local sample = CreateItemBorderSample(itemPreview)
    sample:SetPoint("BOTTOMLEFT", 12, 8)
    local itemText = O.CreateText(itemPreview,
        L["Quality follows Blizzard's native item color. Theme uses your Icon Border color."], 10, "muted")
    itemText:SetPoint("TOPLEFT", 72, -40)
    itemText:SetPoint("RIGHT", -10, 0)
    itemText:SetJustifyV("TOP")
    return itemPreview
end

local function BuildSafetyNote(preview, itemPreview, view)
    local safety = O.CreatePanel(preview, "status")
    safety:SetPoint("TOPLEFT", itemPreview, "BOTTOMLEFT", 0, -12)
    safety:SetPoint("TOPRIGHT", itemPreview, "BOTTOMRIGHT", 0, -12)
    safety:SetHeight(116)
    local safetyTitle = O.CreateText(safety, L["NATIVE BEHAVIOR, INDEPENDENT ART"], 10, "success")
    safetyTitle:SetPoint("TOPLEFT", 12, -12)
    view.safetyText = O.CreateText(safety,
        L["Blizzard keeps the button artwork, clicks, tooltips, enabled states and notifications. Optional glyph artwork is available in the detail controls. Visual changes apply outside combat only."],
        10, "text")
    view.safetyText:SetPoint("TOPLEFT", safetyTitle, "BOTTOMLEFT", 0, -8)
    view.safetyText:SetPoint("RIGHT", -12, 0)
    view.safetyText:SetJustifyV("TOP")
end

local function BuildPreviewActions(preview)
    local colors = O.CreateButton(preview, L["Open Colors"], 104, 28, function()
        O.ShowPage("colors", L["Micro Bar colors"])
    end)
    colors:SetPoint("BOTTOMLEFT", 16, 14)
    local reset = O.CreateButton(preview, L["Reset recommended"], 126, 28, function()
        ResetWithHistory(L["Reset Micro Bar"], NS.MicroMenuSkin.ResetRecommended)
    end)
    reset:SetPoint("LEFT", colors, "RIGHT", 8, 0)
end

-- Status line and safety note per layout owner and icon artwork.
local STATUS_TEXT = {
    owned = {
        icons = L["Enabled - Blizzard icons in the Suite bar"],
        art = L["Enabled - Blizzard artwork in the Suite bar"],
        glyphs = L["Enabled - optional glyphs on native click targets"],
    },
    blizzard = {
        icons = L["Enabled - Blizzard icons at Blizzard's position"],
        art = L["Enabled - Blizzard position and artwork"],
        glyphs = L["Enabled - Blizzard position with optional glyphs"],
    },
}
local SAFETY_TEXT = {
    owned = {
        icons = L["Blizzard supplies the icons. The Suite keeps its own button plates, bar frame and spacing. Native clicks, tooltips and notifications stay intact."],
        art = L["The Suite frames Blizzard's original Micro Buttons. Their artwork, clicks, tooltips, enabled states and notifications stay native. Queue and FPS indicators stay at Blizzard's Edit Mode position. No recurring MSKIN update runs."],
        glyphs = L["The optional glyph layer changes appearance while Blizzard keeps clicks, tooltips, enabled states and notifications. Queue and FPS indicators stay at Blizzard's Edit Mode position. No recurring MSKIN update runs."],
    },
    blizzard = {
        icons = L["Blizzard Edit Mode owns position. The Suite keeps its button plates and Blizzard supplies only the icons."],
        art = L["Blizzard Edit Mode owns position and layout. The original button artwork, clicks and notifications stay intact."],
        glyphs = L["Blizzard Edit Mode owns position and layout. The optional glyph layer changes appearance while native clicks and notifications stay intact."],
    },
}

local function ResolvePreviewGeometry(settings)
    if settings.shape == "global" then
        return NS.DB.geometry.controlShape, NS.DB.geometry.radius
    end
    return settings.shape, settings.radius
end

local function PaintGates(gates, enabled, ownsLayout)
    for index = 1, #gates.layout do O.SetWidgetEnabled(gates.layout[index], ownsLayout) end
    for index = 1, #gates.micro do O.SetWidgetEnabled(gates.micro[index], enabled) end
end

local function PaintBar(view, settings, shape, radius)
    local spec = view.barSpec
    spec.shape = shape
    spec.role = BAR_ROLES[settings.barMaterial] or "microBar"
    spec.radius = radius
    spec.border = settings.barBorder
    spec.fillVisible = settings.barBackground == true
    NS.Surface.Attach(view.bar, spec)
end

local function PaintButton(item, settings, shape, radius)
    item.frame:SetSize(settings.buttonSize, settings.buttonSize)
    item.spec.shape = shape
    item.spec.radius = radius
    item.spec.border = settings.buttonBorder
    item.spec.fillVisible = settings.buttonBackground == true
    NS.Surface.Attach(item.frame, item.spec)
    local icon = item.icon
    if settings.iconStyle == "blizzard" and icon.SetAtlas then
        icon:SetAtlas("UI-HUD-MicroMenu-Questlog-" .. item.info.suffix, true)
        icon:SetSize(32, 40)
    else
        NS.MicroMenuVisual.ApplyIcon(icon, item.info.button, settings.iconStyle)
        local width = settings.iconStyle == "blizzardIcons" and settings.iconSize * 0.8 or settings.iconSize
        icon:SetSize(width, settings.iconSize)
    end
    local r, g, b, a = NS.MicroMenuSkin.GetIconColor(item.info.key)
    icon:SetVertexColor(tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1)
    icon:SetDesaturated(settings.iconStyle == "blizzard" and settings.tint == "monochrome")
end

local function PaintStatus(view, settings, enabled)
    if enabled then
        local owner = settings.layoutMode == "owned" and "owned" or "blizzard"
        local art = settings.iconStyle == "blizzardIcons" and "icons"
            or settings.iconStyle == "blizzard" and "art" or "glyphs"
        view.status:SetText(STATUS_TEXT[owner][art])
        view.safetyText:SetText(SAFETY_TEXT[owner][art])
    else
        view.status:SetText(L["Preview only - Micro Bar skinning is off"])
    end
    O.SetTextColor(view.status, enabled and "success" or "disabled")
end

local function PaintPreview(view, gates)
    local settings = NS.DB.icons.microMenu
    local enabled = NS.DB.skins.microMenu == true
    PaintGates(gates, enabled, enabled and settings.layoutMode == "owned")
    local shape, radius = ResolvePreviewGeometry(settings)
    PaintBar(view, settings, shape, radius)
    for index = 1, #view.buttons do
        PaintButton(view.buttons[index], settings, shape, radius)
    end
    view.bar:SetAlpha(enabled and 1 or 0.42)
    PaintStatus(view, settings, enabled)
end

local function BuildPreview(page, gates)
    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", 534, -70)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)
    local heading = O.CreateText(preview, L["LIVE ICON PREVIEW"], 11, "muted")
    heading:SetPoint("TOPLEFT", 16, -16)

    local view = {}
    local microPreview = BuildMicroPreview(preview, view)
    BuildSafetyNote(preview, BuildItemPreview(preview, microPreview), view)
    BuildPreviewActions(preview)

    local function Refresh() PaintPreview(view, gates) end
    O.TrackRefresh(Refresh)
    Refresh()
end

O.RegisterPage("icons", NS.L.ICONS, function(page)
    O.CreateSectionTitle(page, L["Window actions, Micro Bar and icons"],
        L["Choose clean window controls and a complete Micro Bar style, then tune individual artwork only when needed."])
    BuildPreview(page, BuildControls(page))
end)
