local _, Private = ...
local NS, O = Private.NS, Private.Options

local BORDER_VALUES = { 0, 1, 2 }
local MICRO_STYLE_VALUES = { "modern", "midnightDark", "forever", "custom" }
local POSITION_VALUES = {
    "bottomLeft", "bottomRight", "bottomCenter", "topRight", "topCenter", "custom",
}

local function MicroMenuSettings()
    return NS.DB.icons.microMenu
end

local function WindowActionSettings()
    return NS.DB.icons.windowActions
end

local function Percent(value)
    return tostring(math.floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end

local function Pixel(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    return value == 1 and "1 px" or tostring(value) .. " px"
end

local function PresetLabel(value)
    local labels = {
        forever = "MSUF Forever",
        modern = "Midnight Blue",
        midnightDark = "Midnight Dark",
        custom = "Custom",
    }
    return labels[value] or tostring(value)
end

local function WindowActionStyleLabel(value)
    local labels = {
        bare = "Bare",
        soft = "Soft",
        outline = "Outline",
        native = "Native",
    }
    return labels[value] or tostring(value)
end

local function WindowActionGlyphLabel(value)
    local labels = {
        plusMinus = "+ / -",
        chevrons = "Chevrons",
    }
    return labels[value] or tostring(value)
end

local function WindowActionWeightLabel(value)
    local labels = { fine = "Fine", bold = "Bold" }
    return labels[value] or tostring(value)
end

local function IconStyleLabel(value)
    local labels = {
        line = "Line glyphs",
        bold = "Bold glyphs",
        blizzardIcons = "Blizzard icons",
        blizzard = "Full Blizzard",
    }
    return labels[value] or tostring(value)
end

local function HoverStyleLabel(value)
    local labels = {
        outline = "Outline",
        softFill = "Soft",
        solidFill = "Solid",
        iconOnly = "Icon",
        off = "Off",
    }
    return labels[value] or tostring(value)
end

local function TintLabel(value)
    local labels = {
        native = "Native",
        theme = "Theme",
        class = "Class",
        monochrome = "Mono",
    }
    return labels[value] or tostring(value)
end

local function ShapeLabel(value)
    local labels = {
        global = "Global",
        round = "Round",
        continuous = "Smooth",
        squircle = "Squircle",
    }
    return labels[value] or tostring(value)
end

local function LayoutModeLabel(value)
    local labels = {
        owned = "MSKIN Bar",
        blizzard = "Blizzard",
    }
    return labels[value] or tostring(value)
end

local function VisibilityLabel(value)
    local labels = {
        always = "Always", combat = "In combat", outOfCombat = "Out of combat",
        mouseover = "On mouseover", never = "Never",
    }
    return labels[value] or tostring(value)
end

local function OrientationLabel(value)
    local labels = {
        horizontal = "Horizontal",
        vertical = "Vertical",
    }
    return labels[value] or tostring(value)
end

local function GrowthLabel(value)
    local labels = {
        RIGHT_DOWN = "Right / down",
        LEFT_DOWN = "Left / down",
        RIGHT_UP = "Right / up",
        LEFT_UP = "Left / up",
    }
    return labels[value] or tostring(value)
end

local function PositionPresetLabel(value)
    local labels = {
        bottomLeft = "Bottom left",
        bottomRight = "Bottom right",
        bottomCenter = "Bottom center",
        topRight = "Top right",
        topCenter = "Top center",
        custom = "Custom",
    }
    return labels[value] or tostring(value)
end

local function ButtonCount(value)
    value = math.floor((tonumber(value) or 1) + 0.5)
    return value == 1 and "1 button" or tostring(value) .. " buttons"
end

local function BorderLabel(value)
    value = tonumber(value) or 0
    return value <= 0 and "Off" or Pixel(value)
end

local function IconBorderLabel(value)
    local labels = {
        quality = "Quality",
        theme = "Theme",
        off = "Off",
    }
    return labels[value] or tostring(value)
end

local function SetMicroOption(key, value)
    return NS.MicroMenuSkin.SetOption(key, value)
end

local function SetWindowActionOption(key, value)
    return NS.WindowActionSkin.SetOption(key, value)
end

local function CreateSubheading(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(484, 26)
    local label = O.CreateText(row, text, 10, "accent")
    label:SetPoint("BOTTOMLEFT", 4, 3)
    return row
end

local function SeedWindowActionButton(button, kind)
    local family = {
        close = "RedButton-Exit",
        maximize = "RedButton-Expand",
        minimize = "RedButton-Condense",
    }
    local atlas = family[kind]
    if not atlas then return end
    local normal = button:CreateTexture(nil, "ARTWORK")
    local pushed = button:CreateTexture(nil, "ARTWORK")
    local disabled = button:CreateTexture(nil, "ARTWORK")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    normal:SetAtlas(atlas)
    pushed:SetAtlas(atlas .. "-Pressed")
    disabled:SetAtlas(atlas .. "-Disabled")
    highlight:SetAtlas("RedButton-Highlight")
    button:SetNormalTexture(normal)
    button:SetPushedTexture(pushed)
    button:SetDisabledTexture(disabled)
    button:SetHighlightTexture(highlight, "ADD")
end

local function CreateWindowActionPreview(parent)
    local row = O.CreatePanel(parent, "card")
    row:SetSize(484, 82)
    local label = O.CreateText(row, "Live window-action preview", 12, "text")
    label:SetPoint("TOPLEFT", 12, -10)
    local note = O.CreateText(row, "Native hit targets, independent artwork", 9, "dim")
    note:SetPoint("BOTTOMLEFT", 12, 12)

    local reset = O.CreateButton(row, "Reset actions", 104, 24, function()
        O.BeginUserChange("Reset Window Actions")
        local ok = NS.WindowActionSkin.ResetRecommended()
        if ok == false then
            O.CancelUserChange()
            return
        end
        O.CommitUserChange("Reset Window Actions")
    end)
    reset:SetPoint("BOTTOMRIGHT", -10, 8)

    local buttons = {}
    for index, kind in ipairs({ "maximize", "minimize", "close" }) do
        local button = CreateFrame("Button", nil, row)
        button:SetSize(28, 28)
        button:SetPoint("RIGHT", -124 - (3 - index) * 34, 4)
        SeedWindowActionButton(button, kind)
        buttons[index] = button
    end

    local function Refresh()
        for index, kind in ipairs({ "maximize", "minimize", "close" }) do
            local button = buttons[index]
            if NS.Checkmarks then NS.Checkmarks.TrackButton(button, "options-window-actions") end
            NS.WindowActionSkin.Apply(button, "options-window-actions", kind)
        end
    end
    O.TrackRefresh(Refresh)
    Refresh()
    return row
end

local function ResolvePreviewGeometry(settings)
    if settings.shape == "global" then
        return NS.DB.geometry.controlShape, NS.DB.geometry.radius
    end
    return settings.shape, settings.radius
end

local function CreateItemBorderPreview(parent)
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
        local thickness = math.max(1, math.min(3,
            math.floor((tonumber(theme.iconBorderThickness) or 1) + 0.5)))
        local padding = math.max(0, math.min(3,
            math.floor((tonumber(theme.iconBorderPadding) or 0) + 0.5)))
        local extent = padding + thickness
        local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
        for index = 1, 4 do lines[index]:ClearAllPoints() end

        top:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", -extent, padding)
        top:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", extent, padding)
        top:SetHeight(thickness)
        bottom:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -extent, -padding)
        bottom:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", extent, -padding)
        bottom:SetHeight(thickness)
        left:SetPoint("TOPRIGHT", icon, "TOPLEFT", -padding, extent)
        left:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -padding, -extent)
        left:SetWidth(thickness)
        right:SetPoint("TOPLEFT", icon, "TOPRIGHT", padding, extent)
        right:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", padding, -extent)
        right:SetWidth(thickness)

        local style = theme.iconBorderStyle
        local r, g, b, a
        if style == "quality" then
            r, g, b, a = 0.639, 0.208, 0.933, 1
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

O.RegisterPage("icons", NS.L.ICONS or "Icons", function(page)
    O.CreateSectionTitle(page, "Window actions, Micro Bar and icons",
        "Choose clean window controls and a complete Micro Bar style, then tune individual artwork only when needed.")

    local controlsHost = CreateFrame("Frame", nil, page)
    controlsHost:SetPoint("TOPLEFT", 4, -70)
    controlsHost:SetPoint("BOTTOMLEFT", 4, 4)
    controlsHost:SetWidth(510)
    local controlsScroll, controlsList = O.CreateScrollContainer(controlsHost, 2500, 484)
    page._mskinIconsScroll = controlsScroll
    page._mskinIconsContent = controlsList

    local actionHeading = CreateSubheading(controlsList, "WINDOW ACTIONS")
    local actionStyle = O.CreateSegmented(controlsList, "Button style",
        NS.WindowActionStyles, function()
            return WindowActionSettings().style
        end, function(value)
            SetWindowActionOption("style", value)
        end, 484, WindowActionStyleLabel)
    local actionGlyph = O.CreateSegmented(controlsList, "Maximize / minimize symbols",
        NS.WindowActionGlyphModes, function()
            return WindowActionSettings().glyphMode
        end, function(value)
            SetWindowActionOption("glyphMode", value)
        end, 484, WindowActionGlyphLabel)
    local actionWeight = O.CreateSegmented(controlsList, "Line weight",
        NS.WindowActionWeights, function()
            return WindowActionSettings().weight
        end, function(value)
            SetWindowActionOption("weight", value)
        end, 484, WindowActionWeightLabel)
    local actionSize = O.CreateSlider(controlsList, "Maximize / minimize size", 8, 18, 1, function()
        return WindowActionSettings().glyphSize
    end, function(value)
        SetWindowActionOption("glyphSize", value)
    end, 484, Pixel)
    local closeSize = O.CreateSlider(controlsList, "Close X size", 6, 18, 1, function()
        return WindowActionSettings().closeGlyphSize
    end, function(value)
        SetWindowActionOption("closeGlyphSize", value)
    end, 484, Pixel)
    local actionShape = O.CreateSegmented(controlsList, "Button shape",
        NS.WindowActionShapes, function()
            return WindowActionSettings().surfaceShape
        end, function(value)
            SetWindowActionOption("surfaceShape", value)
        end, 484, ShapeLabel)
    local actionRadius = O.CreateSegmented(controlsList, "Button corner radius",
        NS.GeometryRadii, function()
            return WindowActionSettings().surfaceRadius
        end, function(value)
            SetWindowActionOption("surfaceRadius", value)
        end, 484, Pixel)
    local actionInset = O.CreateSlider(controlsList,
        "Visual inset (larger makes the button smaller)", 0, 6, 1, function()
            return WindowActionSettings().surfaceInset
        end, function(value)
            SetWindowActionOption("surfaceInset", value)
        end, 484, Pixel)
    local actionOffsetX = O.CreateSlider(controlsList, "Glyph horizontal offset", -4, 4, 1, function()
        return WindowActionSettings().glyphOffsetX
    end, function(value)
        SetWindowActionOption("glyphOffsetX", value)
    end, 484, Pixel)
    local actionOffsetY = O.CreateSlider(controlsList, "Glyph vertical offset", -4, 4, 1, function()
        return WindowActionSettings().glyphOffsetY
    end, function(value)
        SetWindowActionOption("glyphOffsetY", value)
    end, 484, Pixel)
    local actionOpacity = O.CreateSlider(controlsList, "Idle glyph opacity", 0.35, 1, 0.05, function()
        return WindowActionSettings().opacity
    end, function(value)
        SetWindowActionOption("opacity", value)
    end, 484, Percent)
    local actionPreview = CreateWindowActionPreview(controlsList)

    local microHeading = CreateSubheading(controlsList, "MICRO BAR")
    local enabled = O.CreateToggle(controlsList, "Skin the Blizzard Micro Bar", function()
        return NS.DB.skins.microMenu
    end, function(value)
        NS.Adapters.SetEnabled("microMenu", value)
    end, 484)

    local layoutHeading = CreateSubheading(controlsList, "MSKIN-OWNED MICRO BAR")
    local layoutMode = O.CreateSegmented(controlsList, "Layout engine", NS.MicroMenuLayoutModes, function()
        return MicroMenuSettings().layoutMode
    end, function(value)
        SetMicroOption("layoutMode", value)
    end, 484, LayoutModeLabel)
    local visibility, visibilityButton = O.CreateDropdown(controlsList, "Show Micro Bar",
        NS.MicroMenuVisibilityModes, function()
            return MicroMenuSettings().visibility
        end, function(value)
            SetMicroOption("visibility", value)
        end, 484, VisibilityLabel)
    local positionPreset = O.CreateSegmented(controlsList, "Screen position",
        POSITION_VALUES, function()
        return MicroMenuSettings().positionPreset
    end, function(value)
        if value ~= "custom" then NS.MicroMenuSkin.SetPositionPreset(value) end
    end, 484, PositionPresetLabel)
    local orientation = O.CreateSegmented(controlsList, "Bar direction", NS.MicroMenuOrientations, function()
        return MicroMenuSettings().orientation
    end, function(value)
        SetMicroOption("orientation", value)
    end, 484, OrientationLabel)
    local locked = O.CreateToggle(controlsList, "Lock bar position (unlock to drag)", function()
        return MicroMenuSettings().locked
    end, function(value)
        SetMicroOption("locked", value)
    end, 484)
    local scale = O.CreateSlider(controlsList, "Bar scale", 0.5, 1.5, 0.05, function()
        return MicroMenuSettings().scale
    end, function(value)
        SetMicroOption("scale", value)
    end, 484, Percent)

    local advancedLayoutHeading = CreateSubheading(controlsList, "ADVANCED BAR LAYOUT")
    local growth = O.CreateSegmented(controlsList, "Growth direction", NS.MicroMenuGrowthModes, function()
        return MicroMenuSettings().growth
    end, function(value)
        SetMicroOption("growth", value)
    end, 484, GrowthLabel)
    local buttonsPerLine = O.CreateSlider(controlsList, "Buttons per line", 1,
        NS.Client and NS.Client.isForever and 14 or 13, 1, function()
        return MicroMenuSettings().buttonsPerLine
    end, function(value)
        SetMicroOption("buttonsPerLine", value)
    end, 484, ButtonCount)
    local spacing = O.CreateSlider(controlsList, "Button spacing", -8, 16, 1, function()
        return MicroMenuSettings().spacing
    end, function(value)
        SetMicroOption("spacing", value)
    end, 484, Pixel)
    local padding = O.CreateSlider(controlsList, "Bar padding", 0, 16, 1, function()
        return MicroMenuSettings().padding
    end, function(value)
        SetMicroOption("padding", value)
    end, 484, Pixel)
    local layoutX = O.CreateSlider(controlsList, "Horizontal offset", -4096, 4096, 1, function()
        return MicroMenuSettings().layoutX
    end, function(value)
        SetMicroOption("layoutX", value)
    end, 484, Pixel)
    local layoutY = O.CreateSlider(controlsList, "Vertical offset", -4096, 4096, 1, function()
        return MicroMenuSettings().layoutY
    end, function(value)
        SetMicroOption("layoutY", value)
    end, 484, Pixel)

    local preset = O.CreateSegmented(controlsList, "Micro Bar style", MICRO_STYLE_VALUES, function()
        return MicroMenuSettings().preset
    end, function(value)
        if value ~= "custom" then NS.MicroMenuSkin.ApplyPreset(value) end
    end, 484, PresetLabel)

    local iconStyle = O.CreateSegmented(controlsList, "Icon artwork",
        NS.MicroMenuIconStyles, function()
            return MicroMenuSettings().iconStyle
        end, function(value)
            SetMicroOption("iconStyle", value)
        end, 484, IconStyleLabel)

    local tint = O.CreateSegmented(controlsList, "Icon colors", NS.MicroMenuTintModes, function()
        return MicroMenuSettings().tint
    end, function(value)
        SetMicroOption("tint", value)
    end, 484, TintLabel)

    local buttonSize = O.CreateSlider(controlsList, "Visual button size", 20, 32, 1, function()
        return MicroMenuSettings().buttonSize
    end, function(value)
        SetMicroOption("buttonSize", value)
    end, 484, Pixel)
    local iconSize = O.CreateSlider(controlsList, "Glyph size", 10, 28, 1, function()
        return MicroMenuSettings().iconSize
    end, function(value)
        local requiredButtonSize = math.min(32, math.floor(value + 4.5))
        if value > (MicroMenuSettings().buttonSize or 28) - 4 then
            SetMicroOption("buttonSize", requiredButtonSize)
        end
        SetMicroOption("iconSize", value)
    end, 484, Pixel)
    local hoverStyle = O.CreateSegmented(controlsList, "Mouse-over effect",
        NS.MicroMenuHoverStyles, function()
            return MicroMenuSettings().hoverStyle
        end, function(value)
            SetMicroOption("hoverStyle", value)
        end, 484, HoverStyleLabel)

    local itemStyle = O.CreateSegmented(controlsList, "Verified item icon borders", NS.IconBorderStyles, function()
        return NS.DB.theme.iconBorderStyle
    end, function(value)
        NS.Theme.SetAppearance("iconBorderStyle", value)
    end, 484, IconBorderLabel)

    local materialHeading = CreateSubheading(controlsList, "MICRO BAR MATERIALS")
    local barBackground = O.CreateToggle(controlsList, "Bar background", function()
        return MicroMenuSettings().barBackground
    end, function(value)
        SetMicroOption("barBackground", value)
    end, 484)
    local barBorder = O.CreateSegmented(controlsList, "Bar border", BORDER_VALUES, function()
        return MicroMenuSettings().barBorder
    end, function(value)
        SetMicroOption("barBorder", value)
    end, 484, BorderLabel)
    local barMaterial = O.CreateSegmented(controlsList, "Bar material",
        NS.MicroMenuBarMaterials, function()
            return MicroMenuSettings().barMaterial
        end, function(value)
            SetMicroOption("barMaterial", value)
        end, 484, PresetLabel)
    local buttonBackground = O.CreateToggle(controlsList, "Individual button backgrounds", function()
        return MicroMenuSettings().buttonBackground
    end, function(value)
        SetMicroOption("buttonBackground", value)
    end, 484)
    local buttonBorder = O.CreateSegmented(controlsList, "Individual button borders", BORDER_VALUES, function()
        return MicroMenuSettings().buttonBorder
    end, function(value)
        SetMicroOption("buttonBorder", value)
    end, 484, BorderLabel)
    local shape = O.CreateSegmented(controlsList, "Bar and button shape", NS.MicroMenuShapes, function()
        return MicroMenuSettings().shape
    end, function(value)
        SetMicroOption("shape", value)
    end, 484, ShapeLabel)
    local radius = O.CreateSegmented(controlsList, "Corner radius", NS.GeometryRadii, function()
        return MicroMenuSettings().radius
    end, function(value)
        SetMicroOption("radius", value)
    end, 484, Pixel)

    local stateHeading = CreateSubheading(controlsList, "MICRO ICON STATES")
    local normalOpacity = O.CreateSlider(controlsList, "Normal icon opacity", 0, 1, 0.05, function()
        return MicroMenuSettings().normalOpacity
    end, function(value)
        SetMicroOption("normalOpacity", value)
    end, 484, Percent)
    local hoverOpacity = O.CreateSlider(controlsList, "Mouse-over icon opacity", 0, 1, 0.05, function()
        return MicroMenuSettings().hoverOpacity
    end, function(value)
        SetMicroOption("hoverOpacity", value)
    end, 484, Percent)
    local pressedOpacity = O.CreateSlider(controlsList, "Pressed icon opacity", 0, 1, 0.05, function()
        return MicroMenuSettings().pressedOpacity
    end, function(value)
        SetMicroOption("pressedOpacity", value)
    end, 484, Percent)
    local disabledOpacity = O.CreateSlider(controlsList, "Disabled icon opacity", 0, 1, 0.05, function()
        return MicroMenuSettings().disabledOpacity
    end, function(value)
        SetMicroOption("disabledOpacity", value)
    end, 484, Percent)

    local itemHeading = CreateSubheading(controlsList, "GLOBAL ITEM ICON BORDERS")
    local itemThickness = O.CreateSlider(controlsList, "Border thickness", 1, 3, 1, function()
        return NS.DB.theme.iconBorderThickness
    end, function(value)
        NS.Theme.SetAppearance("iconBorderThickness", value)
    end, 484, Pixel)
    local itemPadding = O.CreateSlider(controlsList, "Distance from icon", 0, 3, 1, function()
        return NS.DB.theme.iconBorderPadding
    end, function(value)
        NS.Theme.SetAppearance("iconBorderPadding", value)
    end, 484, Pixel)
    local itemOpacity = O.CreateSlider(controlsList, "Border opacity", 0, 1, 0.05, function()
        return NS.DB.theme.iconBorderOpacity
    end, function(value)
        NS.Theme.SetAppearance("iconBorderOpacity", value)
    end, 484, Percent)

    local rows = {
        { actionHeading, true }, { actionStyle, true }, { actionGlyph, true },
        { actionWeight, false }, { actionSize, false }, { closeSize, true },
        { actionShape, false }, { actionRadius, false }, { actionInset, false },
        { actionOffsetX, false }, { actionOffsetY, false }, { actionOpacity, false },
        { actionPreview, true }, { microHeading, true },
        { enabled, true },
        { layoutHeading, true }, { layoutMode, true }, { positionPreset, true },
        { orientation, true }, { locked, true }, { scale, true },
        { advancedLayoutHeading, false }, { growth, false }, { buttonsPerLine, false },
        { spacing, false }, { padding, false }, { layoutX, false }, { layoutY, false },
        { preset, true }, { iconStyle, true }, { tint, true },
        { buttonSize, true }, { iconSize, true }, { hoverStyle, true },
        { itemStyle, true },
        { materialHeading, false }, { barBackground, false }, { barBorder, false },
        { barMaterial, false },
        { buttonBackground, false }, { buttonBorder, false }, { shape, false }, { radius, false },
        { stateHeading, false }, { normalOpacity, false }, { hoverOpacity, false },
        { pressedOpacity, false }, { disabledOpacity, false },
        { itemHeading, false }, { itemThickness, false }, { itemPadding, false }, { itemOpacity, false },
    }

    local function RefreshMode()
        local guided = O.GetMode() == "guided"
        local previous
        local contentHeight = 4
        for index = 1, #rows do
            local row, essential = rows[index][1], rows[index][2]
            local show = not guided or essential
            row:ClearAllPoints()
            row:SetShown(show)
            if show then
                if previous then
                    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
                else
                    row:SetPoint("TOPLEFT", 0, -2)
                end
                contentHeight = contentHeight + row:GetHeight() + (previous and 8 or 0)
                previous = row
            end
        end
        controlsList:SetHeight(math.max(1, contentHeight + 4))
    end
    O.TrackMode(RefreshMode)
    RefreshMode()

    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", 534, -70)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)

    local previewHeading = O.CreateText(preview, "LIVE ICON PREVIEW", 11, "muted")
    previewHeading:SetPoint("TOPLEFT", 16, -16)

    local microPreview = O.CreatePanel(preview, "panel")
    microPreview:SetPoint("TOPLEFT", 16, -44)
    microPreview:SetPoint("TOPRIGHT", -16, -44)
    microPreview:SetHeight(174)
    local microTitle = O.CreateText(microPreview, "Blizzard Micro Bar", 12, "title")
    microTitle:SetPoint("TOPLEFT", 12, -12)

    local barPreview = CreateFrame("Frame", nil, microPreview)
    barPreview:SetPoint("TOPLEFT", 12, -38)
    barPreview:SetPoint("TOPRIGHT", -12, -38)
    barPreview:SetHeight(70)
    local barSpec = { role = "microBar", shape = "continuous", radius = 6, border = 1 }
    NS.Surface.Attach(barPreview, barSpec)

    local previewStates = {
        { key = "normal", label = "Normal", suffix = "Up", button = "ProfessionMicroButton" },
        { key = "hover", label = "Hover", suffix = "Mouseover", button = "PlayerSpellsMicroButton" },
        { key = "pressed", label = "Pressed", suffix = "Down", button = "QuestLogMicroButton" },
        { key = "disabled", label = "Disabled", suffix = "Disabled", button = "GuildMicroButton" },
    }
    local previewButtons = {}
    for index = 1, #previewStates do
        local stateInfo = previewStates[index]
        local button = CreateFrame("Frame", nil, barPreview)
        button:SetSize(42, 50)
        if index == 1 then
            button:SetPoint("LEFT", 8, 0)
        else
            button:SetPoint("LEFT", previewButtons[index - 1].frame, "RIGHT", 8, 0)
        end
        local buttonSpec = { role = "microButton", shape = "continuous", radius = 6, border = 1 }
        NS.Surface.Attach(button, buttonSpec)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", 0, 1)
        NS.MicroMenuVisual.ApplyIcon(icon, stateInfo.button,
            MicroMenuSettings().iconStyle)
        icon:SetSize(18, 18)
        previewButtons[index] = { frame = button, spec = buttonSpec, icon = icon, state = stateInfo.key }
    end

    for index = 1, #previewStates do
        local label = O.CreateText(microPreview, previewStates[index].label, 9, "dim", "CENTER")
        label:SetPoint("TOP", previewButtons[index].frame, "BOTTOM", 0, -5)
        label:SetWidth(48)
    end

    local previewStatus = O.CreateText(microPreview, "", 10, "muted")
    previewStatus:SetPoint("BOTTOMLEFT", 12, 10)
    previewStatus:SetPoint("RIGHT", -12, 0)

    local itemPreview = O.CreatePanel(preview, "card")
    itemPreview:SetPoint("TOPLEFT", microPreview, "BOTTOMLEFT", 0, -12)
    itemPreview:SetPoint("TOPRIGHT", microPreview, "BOTTOMRIGHT", 0, -12)
    itemPreview:SetHeight(94)
    local itemTitle = O.CreateText(itemPreview, "Global item borders", 12, "title")
    itemTitle:SetPoint("TOPLEFT", 12, -12)
    local itemIcon = CreateItemBorderPreview(itemPreview)
    itemIcon:SetPoint("BOTTOMLEFT", 12, 8)
    local itemText = O.CreateText(itemPreview,
        "Quality follows Blizzard's native item color. Theme uses your Icon Border color.", 10, "muted")
    itemText:SetPoint("TOPLEFT", 72, -40)
    itemText:SetPoint("RIGHT", -10, 0)
    itemText:SetJustifyV("TOP")

    local safety = O.CreatePanel(preview, "status")
    safety:SetPoint("TOPLEFT", itemPreview, "BOTTOMLEFT", 0, -12)
    safety:SetPoint("TOPRIGHT", itemPreview, "BOTTOMRIGHT", 0, -12)
    safety:SetHeight(116)
    local safetyTitle = O.CreateText(safety, "NATIVE BEHAVIOR, INDEPENDENT ART", 10, "success")
    safetyTitle:SetPoint("TOPLEFT", 12, -12)
    local safetyText = O.CreateText(safety,
        "Blizzard keeps the button artwork, clicks, tooltips, enabled states and notifications. Optional glyph artwork is available in the detail controls. Visual changes apply outside combat only.",
        10, "text")
    safetyText:SetPoint("TOPLEFT", safetyTitle, "BOTTOMLEFT", 0, -8)
    safetyText:SetPoint("RIGHT", -12, 0)
    safetyText:SetJustifyV("TOP")

    local colors = O.CreateButton(preview, "Open Colors", 104, 28, function()
        O.ShowPage("colors", "Micro Bar colors")
    end)
    colors:SetPoint("BOTTOMLEFT", 16, 14)
    local reset = O.CreateButton(preview, "Reset recommended", 126, 28, function()
        local began = O.BeginUserChange("Reset Micro Bar")
        local ok = NS.MicroMenuSkin.ResetRecommended()
        if ok == false then
            O.CancelUserChange()
            return
        end
        O.CommitUserChange("Reset Micro Bar")
    end)
    reset:SetPoint("LEFT", colors, "RIGHT", 8, 0)

    local function RefreshPreview()
        local settings = MicroMenuSettings()
        local enabledNow = NS.DB.skins.microMenu == true
        local ownsLayout = enabledNow and settings.layoutMode == "owned"
        O.SetWidgetEnabled(layoutMode, enabledNow)
        O.SetWidgetEnabled(visibilityButton, ownsLayout)
        visibility:SetAlpha(ownsLayout and 1 or 0.52)
        for _, widget in ipairs({
            positionPreset, orientation, locked, scale, growth, buttonsPerLine,
            spacing, padding, layoutX, layoutY,
        }) do
            O.SetWidgetEnabled(widget, ownsLayout)
        end
        for _, widget in ipairs({
            preset, iconStyle, tint, buttonSize, iconSize, hoverStyle,
            barBackground, barBorder, barMaterial, buttonBackground, buttonBorder, shape,
            radius, normalOpacity, hoverOpacity, pressedOpacity, disabledOpacity,
        }) do
            O.SetWidgetEnabled(widget, enabledNow)
        end
        local shapeValue, radiusValue = ResolvePreviewGeometry(settings)
        barSpec.shape = shapeValue
        barSpec.role = settings.barMaterial == "forever" and "microBarForever"
            or settings.barMaterial == "modern" and "microBarModern"
            or settings.barMaterial == "midnightDark" and "microBarDark"
            or "microBar"
        barSpec.radius = radiusValue
        barSpec.border = settings.barBorder
        barSpec.fillVisible = settings.barBackground == true
        NS.Surface.Attach(barPreview, barSpec)

        for index = 1, #previewButtons do
            local item = previewButtons[index]
            item.frame:SetSize(settings.buttonSize, settings.buttonSize)
            item.spec.shape = shapeValue
            item.spec.radius = radiusValue
            item.spec.border = settings.buttonBorder
            item.spec.fillVisible = settings.buttonBackground == true
            NS.Surface.Attach(item.frame, item.spec)
            local stateInfo = previewStates[index]
            if settings.iconStyle == "blizzard" and item.icon.SetAtlas then
                item.icon:SetAtlas("UI-HUD-MicroMenu-Questlog-" .. stateInfo.suffix, true)
                item.icon:SetSize(32, 40)
            else
                NS.MicroMenuVisual.ApplyIcon(item.icon, stateInfo.button,
                    settings.iconStyle)
                item.icon:SetSize(settings.iconStyle == "blizzardIcons"
                    and settings.iconSize * 0.8 or settings.iconSize, settings.iconSize)
            end
            local r, g, b, a = NS.MicroMenuSkin.GetIconColor(item.state)
            item.icon:SetVertexColor(tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1)
            item.icon:SetDesaturated(settings.iconStyle == "blizzard"
                and settings.tint == "monochrome")
        end

        barPreview:SetAlpha(enabledNow and 1 or 0.42)
        local nativeArt = settings.iconStyle == "blizzard"
        local nativeIcons = settings.iconStyle == "blizzardIcons"
        if enabledNow and settings.layoutMode == "owned" then
            previewStatus:SetText(nativeIcons and "Enabled - Blizzard icons in the Suite bar"
                or nativeArt and "Enabled - Blizzard artwork in the Suite bar"
                or "Enabled - optional glyphs on native click targets")
            safetyText:SetText(nativeIcons
                and "Blizzard supplies the icons. The Suite keeps its own button plates, bar frame and spacing. Native clicks, tooltips and notifications stay intact."
                or nativeArt
                and "The Suite frames Blizzard's original Micro Buttons. Their artwork, clicks, tooltips, enabled states and notifications stay native. Queue and FPS indicators stay at Blizzard's Edit Mode position. No recurring MSKIN update runs."
                or "The optional glyph layer changes appearance while Blizzard keeps clicks, tooltips, enabled states and notifications. Queue and FPS indicators stay at Blizzard's Edit Mode position. No recurring MSKIN update runs.")
        elseif enabledNow then
            previewStatus:SetText(nativeIcons and "Enabled - Blizzard icons at Blizzard's position"
                or nativeArt and "Enabled - Blizzard position and artwork"
                or "Enabled - Blizzard position with optional glyphs")
            safetyText:SetText(nativeIcons
                and "Blizzard Edit Mode owns position. The Suite keeps its button plates and Blizzard supplies only the icons."
                or nativeArt
                and "Blizzard Edit Mode owns position and layout. The original button artwork, clicks and notifications stay intact."
                or "Blizzard Edit Mode owns position and layout. The optional glyph layer changes appearance while native clicks and notifications stay intact.")
        else
            previewStatus:SetText("Preview only - Micro Bar skinning is off")
        end
        O.SetTextColor(previewStatus, enabledNow and "success" or "disabled")
    end
    O.TrackRefresh(RefreshPreview)
    RefreshPreview()
end)
