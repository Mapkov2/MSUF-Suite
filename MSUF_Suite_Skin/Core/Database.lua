local _, NS = ...

local Database = { rootSchema = 1 }
NS.Database = Database

local function Clamp(value, minimum, maximum)
    value = tonumber(value)
    if not value then return minimum end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function IsListed(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

local function NormalizeColor(color, fallback)
    if type(color) ~= "table" then return NS.CopyValue(fallback) end
    for index = 1, 4 do color[index] = Clamp(color[index], 0, 1) end
    return color
end

-- Revision 38 briefly used the blue W2UI palette. Match its factory values
-- when returning to the Forever look from the user's backup.
local retiredForeverColors = {
    background = "09141F", ink = "0B1722", surface = "10202C", raised = "192B37",
    card = "12232E", popup = "0A1620", input = "0B1823",
    buttonFill = "192B37", buttonFillAlt = "10202C",
    rim = "806845", border = "A18456", borderSoft = "3C4A4C",
    buttonBorder = "806845", iconBorder = "A18456",
    blue = "1A303B", active = "213846", hover = "29434C", pressed = "18313B",
    accent = "D5AD71", accentBright = "F2D9A9", accentAlt = "BA9867",
    text = "EDE9E0", title = "F3E5CA", muted = "BDB8AD",
    dim = "969C9D", disabled = "747D80",
    blizzardYellow = "D5AD71", blizzardArrow = "D5AD71",
    blizzardExpand = "D5AD71", blizzardExpandPressed = "F2D9A9",
    blizzardExpandHover = "F2D9A9", checkmark = "D5AD71",
    blizzardClose = "F3E5CA", blizzardClosePressed = "D5AD71",
    blizzardCloseHover = "F2D9A9", blizzardCloseDisabled = "747D80",
}
local retiredForeverAlpha = {
    background = 0.98, ink = 0.97, surface = 0.96, raised = 0.96,
    card = 0.95, popup = 0.99, input = 0.98,
    buttonFill = 0.94, buttonFillAlt = 0.93,
    rim = 0.82, border = 0.86, borderSoft = 0.55,
    buttonBorder = 0.72, iconBorder = 0.86,
}
local retiredMicroSources = {
    microBarFill = "background", microBarFillAlt = "ink", microBarBorder = "border",
    microButtonFill = "buttonFill", microButtonFillAlt = "buttonFillAlt",
    microButtonBorder = "buttonBorder", microIcon = "text",
    microIconHover = "accentBright", microIconPressed = "accent",
    microIconDisabled = "disabled",
}
local function RestoreForeverColor(current, hex, desired, retiredAlpha)
    if not current or not hex or not desired then return end
    for index = 1, 3 do
        local old = tonumber(hex:sub(index * 2 - 1, index * 2), 16) / 255
        if math.abs(current[index] - old) > 0.000001 then return end
    end
    current[1], current[2], current[3] = desired[1], desired[2], desired[3]
    if retiredAlpha and math.abs(current[4] - retiredAlpha) < 0.000001 then
        current[4] = desired[4]
    end
end

function Database.Normalize(db)
    if type(db) ~= "table" then return nil end
    local previousRevision = tonumber(db.revision) or 0
    local oldDetails = db.characterDetails
    local classicOptOut = type(oldDetails)=="table" and oldDetails.view==nil
        and (oldDetails.enabled==false or oldDetails.inlineGear==false or oldDetails.wideLayout==false)
    local futureSuite = type(db.suite)=="table" and type(db.suite.schema)=="number"
        and db.suite.schema>1 and db.suite or nil
    if futureSuite then db.suite=nil end
    MergeDefaults(db, NS.Defaults)
    if futureSuite then db.suite=futureSuite end
    db.revision = NS.Defaults.revision
    db.enabled = db.enabled ~= false
    db.characterDetails.enabled = db.characterDetails.enabled ~= false
    db.characterDetails.expanded = db.characterDetails.expanded ~= false
    db.characterDetails.styleEQoL = db.characterDetails.styleEQoL ~= false
    db.characterDetails.inlineGear = db.characterDetails.inlineGear ~= false
    db.characterDetails.wideLayout = db.characterDetails.wideLayout ~= false
    if classicOptOut then db.characterDetails.view="classic" end
    local view=db.characterDetails.view
    if view~="modern" and view~="list" and view~="classic" then db.characterDetails.view="modern" end
    db.characterStats.enabled = db.characterStats.enabled ~= false
    db.characterStats.diminishingReturns = db.characterStats.diminishingReturns ~= false
    db.theme.gradient = db.theme.gradient ~= false
    db.theme.gradientStrength = Clamp(db.theme.gradientStrength, 0, 1)
    db.theme.materialDepth = Clamp(db.theme.materialDepth, 0, 1)
    db.theme.shellOpacity = Clamp(db.theme.shellOpacity, 0.35, 1)
    db.theme.panelOpacity = Clamp(db.theme.panelOpacity, 0.35, 1)
    db.theme.controlOpacity = Clamp(db.theme.controlOpacity, 0.35, 1)
    db.theme.borderOpacity = Clamp(db.theme.borderOpacity, 0, 1)
    db.theme.hoverIntensity = Clamp(db.theme.hoverIntensity, 0, 1)
    db.theme.iconBorderThickness = math.floor(Clamp(db.theme.iconBorderThickness, 1, 3) + 0.5)
    db.theme.iconBorderPadding = math.floor(Clamp(db.theme.iconBorderPadding, 0, 3) + 0.5)
    db.theme.iconBorderOpacity = Clamp(db.theme.iconBorderOpacity, 0, 1)
    if not IsListed(NS.GradientDirections, db.theme.gradientDirection) then
        db.theme.gradientDirection = NS.Defaults.theme.gradientDirection
    end
    if not IsListed(NS.HoverStyles, db.theme.hoverStyle) then
        db.theme.hoverStyle = NS.Defaults.theme.hoverStyle
    end
    if not IsListed(NS.IconBorderStyles, db.theme.iconBorderStyle) then
        db.theme.iconBorderStyle = NS.Defaults.theme.iconBorderStyle
    end
    if type(db.theme.look) ~= "string" or not NS.LookPresets[db.theme.look] then
        db.theme.look = "custom"
    end
    if previousRevision > 0 and previousRevision < 4 then db.theme.look = "custom" end
    if previousRevision > 0 and previousRevision < 39 and NS.Client.isForever
        and db.theme.look == "foreverGlass" then
        local retiredAppearance = {
            gradientStrength = 0.16, materialDepth = 0.06,
            shellOpacity = 0.99, panelOpacity = 0.97,
            controlOpacity = 1, borderOpacity = 0.92,
            hoverStyle = "outline", hoverIntensity = 0.72,
            iconBorderOpacity = 0.82,
        }
        local original = NS.LookPresets.foreverGlass.appearance
        for key, retired in pairs(retiredAppearance) do
            if db.theme[key] == retired then db.theme[key] = original[key] end
        end
        if db.geometry.family == "continuous" and db.geometry.radius == 4
            and db.geometry.border == 1 and db.geometry.controlShape == "continuous" then
            db.geometry.radius = NS.LookPresets.foreverGlass.geometry.radius
        end
        local palette = NS.PresetOverrides.foreverGlass
        for key, hex in pairs(retiredForeverColors) do
            RestoreForeverColor(db.theme.colors[key], hex, palette[key], retiredForeverAlpha[key])
        end
        for target, source in pairs(retiredMicroSources) do
            RestoreForeverColor(db.theme.colors[target], retiredForeverColors[source],
                palette[source], retiredForeverAlpha[source])
        end
        if previousRevision == 38 and db.typography.face == "friz" then
            db.typography.face = NS.Defaults.typography.face
        end
    end
    for key, fallback in pairs(NS.Defaults.theme.colors) do
        db.theme.colors[key] = NormalizeColor(db.theme.colors[key], fallback)
    end
    if previousRevision > 0 and previousRevision < 48
        and db.theme.look == "midnightDark"
        and db.theme.hoverStyle == "softFill"
        and math.abs(db.theme.hoverIntensity - 0.68) < 0.000001 then
        local hover = db.theme.colors.hover
        if math.abs(hover[1] - 66 / 255) < 0.000001
            and math.abs(hover[2] - 71 / 255) < 0.000001
            and math.abs(hover[3] - 67 / 255) < 0.000001 then
            local refreshed = NS.PresetOverrides.midnightDark.hover
            hover[1], hover[2], hover[3] = refreshed[1], refreshed[2], refreshed[3]
            db.theme.hoverStyle = "outline"
            db.theme.hoverIntensity = 1
        end
    end
    if previousRevision < 23 then
        -- Micro Bar tokens did not exist before revision 23. Seed them from
        -- the profile's established palette so existing custom looks upgrade
        -- coherently instead of receiving unrelated factory colors.
        local sources = {
            microBarFill = "background", microBarFillAlt = "ink", microBarBorder = "border",
            microButtonFill = "buttonFill", microButtonFillAlt = "buttonFillAlt",
            microButtonBorder = "buttonBorder", microIcon = "text",
            microIconHover = "accentBright", microIconPressed = "accent",
            microIconDisabled = "disabled",
        }
        for target, source in pairs(sources) do
            db.theme.colors[target] = NS.CopyValue(db.theme.colors[source])
        end
    end
    if previousRevision > 0 and previousRevision < 41 and NS.Client.isForever
        and db.theme.look == "foreverGlass" then
        -- Version 40 still inherited these micro colors from generic Glass.
        -- Replace only untouched factory RGB and keep custom alpha intact.
        local oldCard = { 32 / 255, 39 / 255, 42 / 255 }
        local microSources = {
            microBarFill = "background", microBarFillAlt = "ink", microBarBorder = "border",
            microButtonFill = "buttonFill", microButtonFillAlt = "buttonFillAlt",
            microButtonBorder = "buttonBorder", microIcon = "text",
            microIconHover = "accentBright", microIconPressed = "accent",
            microIconDisabled = "disabled",
        }
        local roles = { "card", "microBarFill", "microBarFillAlt", "microBarBorder",
            "microButtonFill", "microButtonFillAlt", "microButtonBorder",
            "microIcon", "microIconHover", "microIconPressed", "microIconDisabled" }
        for _, key in ipairs(roles) do
            local current = db.theme.colors[key]
            local old = key == "card" and oldCard
                or NS.PresetOverrides.foreverGlass[microSources[key]]
            local desired = NS.PresetOverrides.foreverGlass[key]
            if current and old and desired
                and math.abs(current[1] - old[1]) < 0.000001
                and math.abs(current[2] - old[2]) < 0.000001
                and math.abs(current[3] - old[3]) < 0.000001 then
                current[1], current[2], current[3] = desired[1], desired[2], desired[3]
            end
        end
    end

    if not IsListed(NS.GeometryFamilies, db.geometry.family) then
        db.geometry.family = NS.Defaults.geometry.family
    end
    if not IsListed(NS.GeometryRadii, tonumber(db.geometry.radius)) then
        db.geometry.radius = NS.Defaults.geometry.radius
    else db.geometry.radius = tonumber(db.geometry.radius) end
    if not IsListed(NS.GeometryBorders, tonumber(db.geometry.border)) then
        db.geometry.border = NS.Defaults.geometry.border
    else db.geometry.border = tonumber(db.geometry.border) end
    if not IsListed(NS.ControlShapes, db.geometry.controlShape) then
        db.geometry.controlShape = NS.Defaults.geometry.controlShape
    end

    db.typography.enabled = db.typography.enabled == true
    if not IsListed(NS.FontFaces, db.typography.face) then
        db.typography.face = NS.Defaults.typography.face
    end
    db.typography.sharedMediaFont = type(db.typography.sharedMediaFont) == "string"
        and db.typography.sharedMediaFont or NS.Defaults.typography.sharedMediaFont
    local legacyMediaPrefix = "Midnight Skin - "
    if db.typography.sharedMediaFont:sub(1, #legacyMediaPrefix) == legacyMediaPrefix then
        db.typography.sharedMediaFont = "MapkoSkin - "
            .. db.typography.sharedMediaFont:sub(#legacyMediaPrefix + 1)
    end
    db.typography.customPath = type(db.typography.customPath) == "string" and db.typography.customPath or ""
    db.typography.applyChat = db.typography.applyChat ~= false
    db.typography.includeSpecial = db.typography.includeSpecial ~= false

    for key in pairs(NS.Defaults.skins) do db.skins[key] = db.skins[key] ~= false end
    for key in pairs(NS.Defaults.skinCategories) do
        db.skinCategories[key] = db.skinCategories[key] ~= false
    end
    for key in pairs(NS.Defaults.hud) do
        if key ~= "objectiveTrackerStyle" then db.hud[key] = db.hud[key] ~= false end
    end
    if previousRevision < 31 then
        local look = NS.LookPresets[db.theme.look]
        if look and look.objectiveTrackerStyle then
            db.hud.objectiveTrackerStyle = look.objectiveTrackerStyle
        end
    end
    if db.hud.objectiveTrackerStyle ~= "forever"
        and db.hud.objectiveTrackerStyle ~= "modern" then
        db.hud.objectiveTrackerStyle = NS.Defaults.hud.objectiveTrackerStyle
    end
    local windowActions = db.icons.windowActions
    local actionDefaults = NS.Defaults.icons.windowActions
    if not IsListed(NS.WindowActionStyles, windowActions.style) then
        windowActions.style = actionDefaults.style
    end
    if not IsListed(NS.WindowActionGlyphModes, windowActions.glyphMode) then
        windowActions.glyphMode = actionDefaults.glyphMode
    end
    if not IsListed(NS.WindowActionWeights, windowActions.weight) then
        windowActions.weight = actionDefaults.weight
    end
    windowActions.glyphSize = math.floor(Clamp(windowActions.glyphSize, 8, 18) + 0.5)
    if previousRevision < 36 and windowActions.closeGlyphSize == 10 then
        windowActions.closeGlyphSize = 16
    end
    windowActions.closeGlyphSize = math.floor(Clamp(windowActions.closeGlyphSize, 6, 18) + 0.5)
    db.windowControls.enabled = db.windowControls.enabled ~= false
    if type(db.windowControls.scales) ~= "table" then db.windowControls.scales = {} end
    local keptScales = 0
    for name, scale in pairs(db.windowControls.scales) do
        if type(name) ~= "string" or #name > 80 or not name:match("^[%w_]+$")
            or type(scale) ~= "number" or scale ~= scale
            or scale < 0.70 or scale > 1.50 or keptScales >= 128 then
            db.windowControls.scales[name] = nil
        else
            keptScales = keptScales + 1
        end
    end
    if type(db.windowControls.positions) ~= "table" then db.windowControls.positions = {} end
    local keptPositions = 0
    for name, point in pairs(db.windowControls.positions) do
        if type(name) ~= "string" or #name > 80 or not name:match("^[%w_]+$")
            or type(point) ~= "table" or type(point.x) ~= "number"
            or type(point.y) ~= "number" or point.x ~= point.x or point.y ~= point.y
            or math.abs(point.x) > 8192 or math.abs(point.y) > 8192
            or keptPositions >= 128 then
            db.windowControls.positions[name] = nil
        else
            keptPositions = keptPositions + 1
        end
    end
    windowActions.glyphOffsetX = math.floor(Clamp(windowActions.glyphOffsetX, -4, 4) + 0.5)
    windowActions.glyphOffsetY = math.floor(Clamp(windowActions.glyphOffsetY, -4, 4) + 0.5)
    windowActions.surfaceInset = math.floor(Clamp(windowActions.surfaceInset, 0, 6) + 0.5)
    if not IsListed(NS.WindowActionShapes, windowActions.surfaceShape) then
        windowActions.surfaceShape = actionDefaults.surfaceShape
    end
    if not IsListed(NS.GeometryRadii, tonumber(windowActions.surfaceRadius)) then
        windowActions.surfaceRadius = actionDefaults.surfaceRadius
    else
        windowActions.surfaceRadius = tonumber(windowActions.surfaceRadius)
    end
    windowActions.opacity = Clamp(windowActions.opacity, 0.35, 1)
    local microMenu = db.icons.microMenu
    local defaults = NS.Defaults.icons.microMenu
    if previousRevision == 38 and NS.Client.isForever
        and db.theme.look == "foreverGlass" then
        local wasMoved = microMenu.positionPreset == "bottomLeft"
            and microMenu.layoutPoint == "BOTTOMLEFT"
            and microMenu.layoutRelativePoint == "BOTTOMLEFT"
            and microMenu.layoutX == 18 and microMenu.layoutY == 18
        if wasMoved then
            local position = NS.MicroMenuPositionPresets.bottomRight
            microMenu.layoutPoint, microMenu.layoutRelativePoint = position.point, position.relativePoint
            microMenu.layoutX, microMenu.layoutY = position.x, position.y
            microMenu.positionPreset = "bottomRight"
        end
        if microMenu.preset == "forever" then
            if microMenu.barBorder == 1 then microMenu.barBorder = 2 end
            if microMenu.padding == 5 then microMenu.padding = 3 end
        end
    end
    if previousRevision >= 38 and previousRevision < 40 and NS.Client.isForever
        and microMenu.preset == "forever" and microMenu.barMaterial == "forever"
        and microMenu.iconStyle == "blizzard" and microMenu.tint == "native"
        and microMenu.buttonSize == 32 and microMenu.iconSize == 24 then
        local preset = NS.MicroMenuPresetValues.forever
        for _, key in ipairs(NS.MicroMenuLookKeys) do microMenu[key] = preset[key] end
    end
    if previousRevision > 0 and previousRevision < 42 and NS.Client.isForever
        and db.theme.look == "foreverGlass" and microMenu.preset == "forever" then
        -- Update the old boxed factory strip once. Keep hand-tuned visual
        -- choices and all custom positions intact.
        if microMenu.barMaterial == "forever" and microMenu.iconStyle == "line"
            and microMenu.tint == "theme" and microMenu.buttonBackground == true
            and microMenu.buttonBorder == 1 and microMenu.buttonSize == 30
            and microMenu.iconSize == 20 and microMenu.spacing == 3 then
            local preset = NS.MicroMenuPresetValues.forever
            for _, key in ipairs(NS.MicroMenuLookKeys) do
                microMenu[key] = preset[key]
            end
        end
        if microMenu.positionPreset == "bottomRight"
            and microMenu.layoutPoint == "BOTTOMRIGHT"
            and microMenu.layoutRelativePoint == "BOTTOMRIGHT"
            and microMenu.layoutX == -24 and microMenu.layoutY == 24 then
            local position = NS.MicroMenuPositionPresets.bottomCenter
            microMenu.layoutPoint, microMenu.layoutRelativePoint = position.point, position.relativePoint
            microMenu.layoutX, microMenu.layoutY = position.x, position.y
            microMenu.positionPreset = "bottomCenter"
        end
        local oldMicroColors = {
            microBarFill = "14181B", microBarFillAlt = "111517", microIcon = "F4F3EB",
        }
        for key, hex in pairs(oldMicroColors) do
            RestoreForeverColor(db.theme.colors[key], hex,
                NS.PresetOverrides.foreverGlass[key])
        end
    end
    if previousRevision > 0 and previousRevision < 43 and NS.Client.isForever
        and microMenu.positionPreset == "bottomCenter"
        and microMenu.layoutPoint == "BOTTOM"
        and microMenu.layoutRelativePoint == "BOTTOM"
        and microMenu.layoutX == 0 and microMenu.layoutY == 18 then
        -- Keep the factory strip clear of the default action bars.
        microMenu.layoutY = NS.MicroMenuPositionPresets.bottomCenter.y
    end
    if previousRevision > 0 and previousRevision < 45
        and microMenu.preset == "modern" and microMenu.barMaterial == "modern"
        and microMenu.iconStyle == "blizzard" and microMenu.tint == "native"
        and microMenu.buttonSize == 32 and microMenu.iconSize == 24
        and microMenu.spacing == 6 and microMenu.padding == 10
        and microMenu.buttonBackground == false and microMenu.buttonBorder == 0 then
        -- Upgrade only the untouched named Retail factory style. User-tuned
        -- bars keep their saved artwork, geometry and position.
        local preset = NS.MicroMenuPresetValues.modern
        for _, key in ipairs(NS.MicroMenuLookKeys) do microMenu[key] = preset[key] end
    end
    if previousRevision > 0 and previousRevision < 44 and NS.Client.isForever
        and db.theme.look == "foreverGlass" and microMenu.preset == "forever"
        and microMenu.barMaterial == "forever" and microMenu.iconStyle == "line"
        and microMenu.buttonSize == 30 and microMenu.iconSize == 22
        and microMenu.buttonBackground == false then
        -- Move only the named factory look to the fuller gold icon artwork.
        microMenu.iconStyle = NS.MicroMenuPresetValues.forever.iconStyle
    end
    if previousRevision > 0 and previousRevision < 47
        and db.theme.look == "midnightDark" and microMenu.preset == "modern" then
        local old = NS.MicroMenuPresetValues.modern
        local untouched = true
        for _, key in ipairs(NS.MicroMenuLookKeys) do
            if microMenu[key] ~= old[key] then untouched = false; break end
        end
        if untouched then
            local dark = NS.MicroMenuPresetValues.midnightDark
            for _, key in ipairs(NS.MicroMenuLookKeys) do microMenu[key] = dark[key] end
            microMenu.preset = "midnightDark"
        end
    end
    if previousRevision > 0 and previousRevision < 46 and NS.Client.isForever
        and microMenu.preset == "forever" and microMenu.barMaterial == "forever"
        and microMenu.iconStyle == "bold" and microMenu.buttonSize == 30
        and microMenu.iconSize == 22 and microMenu.buttonBackground == false
        and microMenu.buttonBorder == 0 then
        -- Tighten only the untouched Forever strip and allow all fourteen
        -- Camelot buttons on one line. Preserve hand-tuned spacing and rows.
        if microMenu.spacing == 0 then microMenu.spacing = -3 end
        if microMenu.buttonsPerLine == 13 then microMenu.buttonsPerLine = 14 end
    end
    if previousRevision < 33 then
        -- The four old styles differed only slightly. Move named styles to
        -- the two authored looks while leaving user-edited bars alone.
        local legacy = {
            framed = "forever", midnight = "modern",
            class = "modern", minimal = "modern",
        }
        microMenu.preset = legacy[microMenu.preset] or microMenu.preset
        local preset = NS.MicroMenuPresetValues[microMenu.preset]
        if preset then
            for _, key in ipairs(NS.MicroMenuLookKeys) do
                microMenu[key] = preset[key]
            end
        elseif microMenu.preset == "custom" then
            microMenu.barMaterial = "theme"
        end
    end
    if not IsListed(NS.MicroMenuPresets, microMenu.preset) and microMenu.preset ~= "custom" then
        microMenu.preset = defaults.preset
    end
    if not IsListed(NS.MicroMenuShapes, microMenu.shape) then
        microMenu.shape = defaults.shape
    end
    if not IsListed(NS.MicroMenuBarMaterials, microMenu.barMaterial) then
        microMenu.barMaterial = defaults.barMaterial
    end
    if not IsListed(NS.MicroMenuTintModes, microMenu.tint) then
        microMenu.tint = defaults.tint
    end
    if microMenu.iconStyle == "glyph" then microMenu.iconStyle = "line" end
    if not IsListed(NS.MicroMenuIconStyles, microMenu.iconStyle) then
        microMenu.iconStyle = defaults.iconStyle
    end
    if not IsListed(NS.MicroMenuHoverStyles, microMenu.hoverStyle) then
        microMenu.hoverStyle = defaults.hoverStyle
    end
    if not IsListed(NS.MicroMenuLayoutModes, microMenu.layoutMode) then
        microMenu.layoutMode = defaults.layoutMode
    end
    if not IsListed(NS.MicroMenuVisibilityModes, microMenu.visibility) then
        microMenu.visibility = defaults.visibility
    end
    if not IsListed(NS.MicroMenuOrientations, microMenu.orientation) then
        microMenu.orientation = defaults.orientation
    end
    if not IsListed(NS.MicroMenuGrowthModes, microMenu.growth) then
        microMenu.growth = defaults.growth
    end
    if not IsListed(NS.MicroMenuPoints, microMenu.layoutPoint) then
        microMenu.layoutPoint = defaults.layoutPoint
    end
    if not IsListed(NS.MicroMenuPoints, microMenu.layoutRelativePoint) then
        microMenu.layoutRelativePoint = defaults.layoutRelativePoint
    end
    if microMenu.positionPreset ~= "custom"
        and not NS.MicroMenuPositionPresets[microMenu.positionPreset] then
        microMenu.positionPreset = defaults.positionPreset
    end
    microMenu.locked = microMenu.locked ~= false
    microMenu.buttonsPerLine =
        math.floor(Clamp(microMenu.buttonsPerLine, 1,
            NS.Client and NS.Client.isForever and 14 or 13) + 0.5)
    microMenu.spacing = math.floor(Clamp(microMenu.spacing, -8, 16) + 0.5)
    microMenu.scale = Clamp(microMenu.scale, 0.5, 1.5)
    microMenu.padding = math.floor(Clamp(microMenu.padding, 0, 16) + 0.5)
    microMenu.layoutX = math.floor(Clamp(microMenu.layoutX, -4096, 4096) + 0.5)
    microMenu.layoutY = math.floor(Clamp(microMenu.layoutY, -4096, 4096) + 0.5)
    if type(microMenu.barBackground) ~= "boolean" then
        microMenu.barBackground = defaults.barBackground
    end
    if type(microMenu.buttonBackground) ~= "boolean" then
        microMenu.buttonBackground = defaults.buttonBackground
    end
    microMenu.barBorder = math.floor(Clamp(microMenu.barBorder, 0, 2) + 0.5)
    microMenu.buttonBorder = math.floor(Clamp(microMenu.buttonBorder, 0, 2) + 0.5)
    microMenu.buttonSize = math.floor(Clamp(microMenu.buttonSize, 20, 32) + 0.5)
    microMenu.iconSize = math.floor(Clamp(microMenu.iconSize, 10,
        math.min(28, microMenu.buttonSize - 4)) + 0.5)
    if not IsListed(NS.GeometryRadii, tonumber(microMenu.radius)) then
        microMenu.radius = defaults.radius
    else
        microMenu.radius = tonumber(microMenu.radius)
    end
    microMenu.normalOpacity = Clamp(microMenu.normalOpacity, 0, 1)
    microMenu.hoverOpacity = Clamp(microMenu.hoverOpacity, 0, 1)
    microMenu.pressedOpacity = Clamp(microMenu.pressedOpacity, 0, 1)
    microMenu.disabledOpacity = Clamp(microMenu.disabledOpacity, 0, 1)
    if type(db.theme.preset) ~= "string" or not NS.PresetOverrides[db.theme.preset] then
        db.theme.preset = NS.Defaults.theme.preset
    end
    if NS.Suite then NS.Suite.Normalize(db) end
    return db
end

local function SanitizeValue(value, fallback)
    if type(fallback) == "table" then
        local source = type(value) == "table" and value or {}
        local result = {}
        for key, childDefault in pairs(fallback) do
            result[key] = SanitizeValue(source[key], childDefault)
        end
        return result
    end
    if type(value) ~= type(fallback) then return fallback end
    return value
end

function Database.SanitizeProfile(profile)
    if type(profile) ~= "table" then return nil end
    local safe = SanitizeValue(profile, NS.Defaults)
    local source = type(profile.windowControls) == "table"
        and profile.windowControls.scales or nil
    if type(source) == "table" then
        local copied = 0
        for name, scale in pairs(source) do
            if type(name) == "string" and #name <= 80 and name:match("^[%w_]+$")
                and type(scale) == "number" and scale == scale
                and scale >= 0.70 and scale <= 1.50 and copied < 128 then
                safe.windowControls.scales[name] = scale
                copied = copied + 1
            end
        end
    end
    local positions = type(profile.windowControls) == "table"
        and profile.windowControls.positions or nil
    if type(positions) == "table" then
        local copied = 0
        for name, point in pairs(positions) do
            if type(name) == "string" and #name <= 80 and name:match("^[%w_]+$")
                and type(point) == "table" and type(point.x) == "number"
                and type(point.y) == "number" and point.x == point.x and point.y == point.y
                and math.abs(point.x) <= 8192 and math.abs(point.y) <= 8192
                and copied < 128 then
                safe.windowControls.positions[name] = { x = point.x, y = point.y }
                copied = copied + 1
            end
        end
    end
    return Database.Normalize(safe)
end

function Database.NormalizeProfileName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[%z\1-\31]", ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

local function CreateFactoryProfile()
    local suite = _G.MSUFSuite
    local encoded = suite and suite.ForeverFactorySkinCompact
    local decode = _G.MSUF_TryDecodeCompactString
    if NS.Client and NS.Client.isForever and type(encoded) == "string"
        and type(decode) == "function" then
        local ok, envelope = pcall(decode, "MSUF3:" .. encoded:sub(8))
        if ok and type(envelope) == "table"
            and (envelope.addon == "MapkoSkin" or envelope.addon == "MidnightSkin")
            and envelope.format == 1 and envelope.kind == "profile" then
            local profile = Database.SanitizeProfile(envelope.payload)
            if profile then return profile end
        end
    end
    return Database.Normalize(NS.CopyValue(NS.Defaults))
end
Database.CreateFactoryProfile = CreateFactoryProfile

local function NewRoot(profile)
    return {
        schema = Database.rootSchema,
        activeProfile = "Default",
        profiles = { Default = Database.Normalize(profile or CreateFactoryProfile()) },
    }
end

local function NormalizeRoot(root)
    root.schema = Database.rootSchema
    if type(root.profiles) ~= "table" then root.profiles = {} end
    local normalized = {}
    for rawName, profile in pairs(root.profiles) do
        local name = Database.NormalizeProfileName(rawName)
        if name and type(profile) == "table" then
            normalized[name] = Database.Normalize(profile)
        end
    end
    if not next(normalized) then normalized.Default = CreateFactoryProfile() end
    root.profiles = normalized
    local active = Database.NormalizeProfileName(root.activeProfile)
    if not active or not normalized[active] then
        active = normalized.Default and "Default" or next(normalized)
    end
    root.activeProfile = active
    return root
end

function Database.Initialize()
    local stored = _G.MSUFSuiteSkinDB
    if type(stored) ~= "table" then stored = _G.MapkoSkinDB end
    if type(stored) ~= "table" then stored = _G.MidnightSkinDB end
    local root
    if type(stored) == "table" and type(stored.profiles) == "table" then
        root = NormalizeRoot(stored)
    elseif type(stored) == "table" then
        -- One-time migration from the 0.7 flat SavedVariables layout. Keep the
        -- entire normalized profile; no setting is dropped.
        root = NewRoot(stored)
    else
        root = NewRoot()
    end
    _G.MSUFSuiteSkinDB = root
    _G.MidnightSkinDB = nil
    NS.RootDB = root
    NS.DB = root.profiles[root.activeProfile]
    return NS.DB
end

function Database.GetRoot() return NS.RootDB end
function Database.GetActiveProfileName()
    return NS.RootDB and NS.RootDB.activeProfile or "Default"
end
function Database.GetProfile(name)
    return NS.RootDB and NS.RootDB.profiles and NS.RootDB.profiles[name]
end
function Database.GetProfileNames()
    local names = {}
    for name in pairs(NS.RootDB and NS.RootDB.profiles or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function ApplyActiveSettings(reason)
    if NS.Theme and NS.Theme.RefreshDynamicLook then NS.Theme.RefreshDynamicLook() end
    if NS.Typography then NS.Typography.ApplyConfigured() end
    if NS.Adapters then NS.Adapters.ApplyAll() end
    if NS.Registry then
        NS.Registry.RefreshAll()
        NS.Registry.NotifyListeners("profile", reason or "changed")
    end
end

function Database.SetProfile(name, profile)
    name = Database.NormalizeProfileName(name)
    profile = Database.SanitizeProfile(profile)
    if not name or not profile or not NS.RootDB then return false, "invalid-profile" end
    NS.RootDB.profiles[name] = profile
    if NS.RootDB.activeProfile == name then NS.DB = profile end
    return true, name
end

function Database.CreateProfile(name, copyCurrent)
    name = Database.NormalizeProfileName(name)
    if not name then return false, "invalid-name" end
    if not NS.RootDB then return false, "database-not-ready" end
    if NS.RootDB.profiles[name] then return false, "profile-exists" end
    NS.RootDB.profiles[name] = copyCurrent and Database.SanitizeProfile(NS.DB)
        or CreateFactoryProfile()
    return true, name
end

function Database.SetActiveProfile(name)
    name = Database.NormalizeProfileName(name)
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.RootDB then return false, "database-not-ready" end
    if not name or not NS.RootDB.profiles[name] then return false, "missing-profile" end
    if NS.Typography then NS.Typography.Restore() end
    NS.RootDB.activeProfile = name
    NS.DB = NS.RootDB.profiles[name]
    ApplyActiveSettings("activate")
    return true, name
end

function Database.DeleteProfile(name)
    name = Database.NormalizeProfileName(name)
    if not NS.RootDB then return false, "database-not-ready" end
    if not name or not NS.RootDB.profiles[name] then return false, "missing-profile" end
    local count = 0
    for _ in pairs(NS.RootDB.profiles) do count = count + 1 end
    if count <= 1 then return false, "last-profile" end
    local wasActive = name == NS.RootDB.activeProfile
    NS.RootDB.profiles[name] = nil
    if wasActive then
        local replacement = NS.RootDB.profiles.Default and "Default" or next(NS.RootDB.profiles)
        NS.RootDB.activeProfile = replacement
        NS.DB = NS.RootDB.profiles[replacement]
        ApplyActiveSettings("delete")
    end
    return true, wasActive and NS.RootDB.activeProfile or name
end

function Database.ReplaceProfiles(profiles, activeName)
    if NS.IsCombatLocked() or type(profiles) ~= "table" then return false, "invalid-profiles" end
    local clean = {}
    local count = 0
    for rawName, profile in pairs(profiles) do
        count = count + 1
        if count > 64 then return false, "too-many-profiles" end
        local name = Database.NormalizeProfileName(rawName)
        if name and type(profile) == "table" then clean[name] = Database.SanitizeProfile(profile) end
    end
    if not next(clean) then return false, "empty-profiles" end
    activeName = Database.NormalizeProfileName(activeName)
    if not activeName or not clean[activeName] then activeName = clean.Default and "Default" or next(clean) end
    if NS.Typography then NS.Typography.Restore() end
    NS.RootDB.profiles = clean
    NS.RootDB.activeProfile = activeName
    NS.DB = clean[activeName]
    ApplyActiveSettings("import-all")
    return true, activeName
end

function Database.ResetColors()
    NS.DB.theme.colors = NS.CopyValue(NS.Defaults.theme.colors)
    NS.DB.theme.preset = NS.Defaults.theme.preset
end

function Database.ResetAll()
    local profile = CreateFactoryProfile()
    local name = Database.GetActiveProfileName()
    if not NS.RootDB then NS.RootDB = NewRoot(profile) end
    NS.RootDB.profiles[name] = profile
    NS.DB = profile
    _G.MSUFSuiteSkinDB = NS.RootDB
    return profile
end

return Database
