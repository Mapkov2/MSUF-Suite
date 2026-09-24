local _, P = ...
local Suite, M, W, T, Tr = P.Suite, P.M, P.W, P.T, P.Tr
local PAGE = "suite_skin"

local function Engine()
    local skin = _G.MapkoSkin
    if not (skin and skin.addonName == "MSUF_Suite_Skin") and Suite.Skin and Suite.Skin.EnsureEngine
        and not P.Combat() then
        Suite.Skin.EnsureEngine()
        skin = _G.MapkoSkin
    end
    if skin and skin.addonName == "MSUF_Suite_Skin" and skin.DB and skin.Theme then return skin end
end

local function Change(skin, label, key, fn)
    if P.Combat() or not skin then return false end
    local reason
    local result = P.WithHistory(label, "suite:skin." .. key, function()
        local ok, message = fn()
        reason = message
        return ok
    end)
    P.Refresh()
    return result, reason
end

local function Meta(key, section)
    return P.Meta(PAGE, "skin", key, "setting", "suite_skin_" .. section)
end

local CHOICE_LABELS = {
    VERTICAL = "Vertical", HORIZONTAL = "Horizontal",
    RIGHT_DOWN = "Right, then down", LEFT_DOWN = "Left, then down",
    RIGHT_UP = "Right, then up", LEFT_UP = "Left, then up",
    plusMinus = "+ / -", softFill = "Soft fill", solidFill = "Solid fill",
    iconOnly = "Icon only", off = "Off", bare = "Bare", native = "Blizzard",
    blizzardIcons = "Blizzard icons", blizzard = "Full Blizzard",
    global = "Use global shape", owned = "Suite bar",
    quality = "Item quality", theme = "Skin color", monochrome = "Monochrome",
    friz = "Friz Quadrata", horizontal = "Horizontal", vertical = "Vertical",
    modern = "Modern", forever = "MSUF Forever", list = "List", classic = "Classic",
    always = "Always", combat = "In combat", outOfCombat = "Out of combat",
    mouseover = "On mouseover", never = "Never",
}
local CATEGORY_LABELS = {
    character = "Character and equipment", inventory = "Bags and bank",
    npc = "Merchants and NPCs", quest = "Quests and gossip",
    social = "Social, mail and guild", group = "Group Finder and PvE",
    profession = "Professions and crafting", economy = "Auction and economy",
    journal = "Collections and journals", map = "Map interfaces",
    calendar = "Calendar", utility = "Utility windows and dialogs",
    ["item-service"] = "Item services and upgrades", expansion = "Expansion interfaces",
    housing = "Housing interfaces", hud = "Blizzard HUD and alerts",
    tutorial = "Tutorials and help overlays",
}
local function Values(list, labels)
    local result = {}
    for _, value in ipairs(list or {}) do
        local text = labels and labels[value] or CHOICE_LABELS[value] or tostring(value)
        if type(value) == "string" and text == value then
            text = text:gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
        end
        result[#result + 1] = { value = value, text = Tr(text) }
    end
    return result
end

local function Row(kind, label, key, section, get, set, values, min, max, step)
    local row = Meta(key, section)
    row.id, row.kind, row.label, row.get, row.set = key, kind, Tr(label), get, set
    if kind == "dropdown" then row.values = values
    elseif kind == "slider" then
        row.min, row.max, row.step, row.roundStep = min, max, step, step >= 1
    end
    return row
end

local function Section(ctx, b, id, title, help, rows, open, extra)
    local body = b:CollapsibleSection("suite_skin_" .. id, Tr(title), 120, open)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = -18
    if help then
        local hint = P.Text(body, help, 16, y, width)
        y = y - math.max(14, math.ceil(hint:GetStringHeight() or 14)) - 12
    end
    if #rows > 0 then
        local grid = W.SettingsRows(ctx, body, {
            x = 16, y = y, width = width, columns = width >= 520 and 2 or 1, rows = rows,
        })
        y = grid.bottomY
    end
    if extra then y = extra(body, y, width) or y end
    P.FinishBody(b, body, y)
    return body
end

local function ConfigRow(skin, rows, section, label, path, key, kind, values, min, max, step, setter)
    local id = path .. "." .. key
    rows[#rows + 1] = Row(kind, label, id, section,
        function() return skin.DB[path][key] end,
        function(value) Change(skin, label, id, function() return setter(key, value) end) end,
        kind == "dropdown" and Values(values) or nil, min, max, step)
end

local function Preview(ctx, b, skin)
    local section, toolbar = W.FixedPreviewSection(ctx, b, { title = Tr("Skin preview"), height = 176 })
    if not section then return end
    local hint = T.Font(toolbar, "GameFontDisableSmall", Tr("Choose a look below; this sample follows your changes."), T.colors.muted)
    hint:SetPoint("LEFT", toolbar, "LEFT", 125, 0)
    hint:SetPoint("RIGHT", toolbar, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    local canvas = CreateFrame("Frame", nil, section)
    canvas:SetPoint("TOPLEFT", 14, -42)
    canvas:SetPoint("BOTTOMRIGHT", -14, 9)
    local function Box(parent, x, y, width, height, role)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetPoint("TOPLEFT", x, y)
        frame:SetSize(width, height)
        if skin.Surface and skin.Surface.Attach then skin.Surface.Attach(frame, { role = role }) end
        return frame
    end
    local shell = Box(canvas, 10, -7, 292, 116, "shell")
    local title = T.Font(shell, "GameFontNormal", Tr("Window shell"), T.colors.text)
    title:SetPoint("TOPLEFT", 14, -12)
    local panel = Box(shell, 13, -37, 266, 66, "panel")
    local card = Box(panel, 10, -10, 246, 22, "card")
    local cardLabel = T.Font(card, "GameFontHighlightSmall", Tr("Panel and card layer"), T.colors.text)
    cardLabel:SetPoint("LEFT", 8, 0)
    local button = Box(panel, 10, -40, 76, 19, "buttonPrimary")
    local buttonLabel = T.Font(button, "GameFontHighlightSmall", Tr("Primary"), T.colors.text)
    buttonLabel:SetPoint("CENTER")
    local note = P.Text(canvas, "", 326, -18, 300)
    M.TrackRefresh(ctx, function()
        local r, g, blue = skin.Theme.GetColor("title")
        title:SetTextColor(r, g, blue)
        r, g, blue = skin.Theme.GetColor("text")
        cardLabel:SetTextColor(r, g, blue)
        r, g, blue = skin.Theme.GetColor("accent")
        buttonLabel:SetTextColor(r, g, blue)
        local look = skin.LookPresets[skin.DB.theme.look]
        note:SetText((look and look.label or Tr("Custom")) .. "\n" ..
            (look and look.description or Tr("Your own colors, materials and shape.")))
    end)
end

local function BuildMicroBar(ctx, b, skin)
    local micro = {
        Row("toggle", "Style the Micro Bar", "skins.microMenu", "micro",
            function() return skin.DB.skins.microMenu end,
            function(value) Change(skin, "Micro Bar", "skins.microMenu",
                function() return skin.Adapters.SetEnabled("microMenu", value) end) end),
        Row("dropdown", "Show Micro Bar", "icons.microMenu.visibility", "micro",
            function() return skin.DB.icons.microMenu.visibility end,
            function(value) Change(skin, "Micro Bar visibility", "micro.visibility",
                function() return skin.MicroMenuSkin.SetOption("visibility", value) end) end,
            Values(skin.MicroMenuVisibilityModes)),
        Row("dropdown", "Bar direction", "icons.microMenu.orientation", "micro",
            function() return skin.DB.icons.microMenu.orientation end,
            function(value) Change(skin, "Micro Bar direction", "micro.orientation",
                function() return skin.MicroMenuSkin.SetOption("orientation", value) end) end,
            Values(skin.MicroMenuOrientations)),
        Row("slider", "Buttons per line", "icons.microMenu.buttonsPerLine", "micro",
            function() return skin.DB.icons.microMenu.buttonsPerLine end,
            function(value) Change(skin, "Micro Bar buttons", "micro.buttonsPerLine",
                function() return skin.MicroMenuSkin.SetOption("buttonsPerLine", value) end) end,
            nil, 1, skin.Client and skin.Client.isForever and 14 or 13, 1),
        Row("slider", "Scale", "icons.microMenu.scale", "micro",
            function() return skin.DB.icons.microMenu.scale end,
            function(value) Change(skin, "Micro Bar scale", "micro.scale",
                function() return skin.MicroMenuSkin.SetOption("scale", value) end) end,
            nil, 0.5, 1.5, 0.05),
    }
    Section(ctx, b, "micro", "Micro Bar",
        "Choose a look and when the Suite bar appears. Visibility rules use the Suite layout; Blizzard layout keeps Blizzard's visibility. MSUF Edit Mode reveals the bar for moving.",
        micro, true, function(body, y, width)
            local half = math.floor((width - 12) / 2)
            for index, entry in ipairs({
                { "modern", "Midnight Blue" },
                { "midnightDark", "Midnight Dark" },
                { "forever", "MSUF Forever" },
            }) do
                local style = entry[1]
                P.Button(ctx, body, entry[2],
                    index == 3 and 16 or 16 + (index - 1) * (half + 12),
                    index == 3 and y - 38 or y, index == 3 and width or half, function()
                        Change(skin, "Micro Bar " .. style, "micro.preset",
                            function() return skin.MicroMenuSkin.ApplyPreset(style) end)
                    end, nil, P.Meta(PAGE, "skin", "micro.preset." .. style,
                        "action", "suite_skin_micro"))
            end
            local description = P.Text(body, "", 16, y - 72, width)
            local function RefreshMicroHint()
                local selected = skin.DB.icons.microMenu.preset
                local label = selected == "forever" and "MSUF Forever"
                    or selected == "modern" and "Midnight Blue"
                    or selected == "midnightDark" and "Midnight Dark"
                    or selected == "custom" and "Custom" or "Other style"
                description:SetText("Selected: " .. label .. ". All three looks use MSUF glyphs and a player portrait. The selected look changes the bar, buttons and hover colors. Blizzard keeps every button action and tooltip.")
            end
            RefreshMicroHint()
            M.TrackRefresh(ctx, RefreshMicroHint)
            local descHeight = math.max(22, math.ceil(description:GetStringHeight() or 22))
            P.Button(ctx, body, "Move in MSUF Edit Mode", 16, y - 82 - descHeight, width,
                function()
                    if not skin.DB.skins.microMenu then
                        Change(skin, "Style Micro Bar", "skins.microMenu",
                            function() return skin.Adapters.SetEnabled("microMenu", true) end)
                    end
                    if skin.DB.icons.microMenu.layoutMode ~= "owned" then
                        Change(skin, "Move Micro Bar", "micro.layoutMode",
                            function() return skin.MicroMenuSkin.SetOption("layoutMode", "owned") end)
                    end
                    if skin.OwnedMicroBar then skin.OwnedMicroBar.OpenEditMode() end
                end, nil, P.Meta(PAGE, "skin", "micro.move", "action", "suite_skin_micro"))
            return y - 120 - descHeight
        end)

    local details = {}
    local styles = Values(skin.MicroMenuPresets, {
        forever = "MSUF Forever", modern = "Midnight Blue", midnightDark = "Midnight Dark",
    })
    styles[#styles + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    details[#details + 1] = Row("dropdown", "Style", "icons.microMenu.preset", "micro_details",
        function() return skin.DB.icons.microMenu.preset end,
        function(value) Change(skin, "Micro Bar style", "micro.preset",
            function() return skin.MicroMenuSkin.ApplyPreset(value) end) end, styles)
    for _, spec in ipairs({
        { "Layout engine", "layoutMode", "dropdown", skin.MicroMenuLayoutModes },
        { "Growth direction", "growth", "dropdown", skin.MicroMenuGrowthModes },
        { "Button spacing", "spacing", "slider", nil, -8, 16, 1 },
        { "Bar padding", "padding", "slider", nil, 0, 16, 1 },
        { "Bar material", "barMaterial", "dropdown", skin.MicroMenuBarMaterials },
        { "Icon artwork", "iconStyle", "dropdown", skin.MicroMenuIconStyles },
        { "Icon colors", "tint", "dropdown", skin.MicroMenuTintModes },
        { "Button size", "buttonSize", "slider", nil, 20, 32, 1 },
        { "Glyph size", "iconSize", "slider", nil, 10, 28, 1 },
        { "Mouseover effect", "hoverStyle", "dropdown", skin.MicroMenuHoverStyles },
        { "Bar background", "barBackground", "toggle" },
        { "Bar border", "barBorder", "dropdown", { 0, 1, 2 } },
        { "Button backgrounds", "buttonBackground", "toggle" },
        { "Button borders", "buttonBorder", "dropdown", { 0, 1, 2 } },
        { "Bar and button shape", "shape", "dropdown", skin.MicroMenuShapes },
        { "Corner radius", "radius", "dropdown", skin.GeometryRadii },
        { "Normal icon opacity", "normalOpacity", "slider", nil, 0, 1, 0.05 },
        { "Mouseover icon opacity", "hoverOpacity", "slider", nil, 0, 1, 0.05 },
        { "Pressed icon opacity", "pressedOpacity", "slider", nil, 0, 1, 0.05 },
        { "Disabled icon opacity", "disabledOpacity", "slider", nil, 0, 1, 0.05 },
    }) do
        local label, key, kind = spec[1], spec[2], spec[3]
        details[#details + 1] = Row(kind, label, "icons.microMenu." .. key, "micro_details",
            function() return skin.DB.icons.microMenu[key] end,
            function(value) Change(skin, label, "micro." .. key, function()
                if key == "iconSize" and value > (skin.DB.icons.microMenu.buttonSize or 28) - 4 then
                    local required = math.min(32, math.floor(value + 4.5))
                    if skin.MicroMenuSkin.SetOption("buttonSize", required) == false then return false end
                end
                return skin.MicroMenuSkin.SetOption(key, value)
            end) end,
            kind == "dropdown" and Values(spec[4], key == "barMaterial" and {
                modern = "Midnight Blue", midnightDark = "Midnight Dark",
                forever = "MSUF Forever", theme = "Follow skin look",
            } or nil) or nil, spec[5], spec[6], spec[7])
    end
    Section(ctx, b, "micro_details", "Micro Bar details",
        "Optional artwork and spacing controls. Use MSUF Edit Mode for position, nudging, reset, undo and redo.",
        details, false, function(body, y, width)
            P.Button(ctx, body, "Reset Micro Bar to client default", 16, y, width, function()
                Change(skin, "Reset Micro Bar", "micro.reset", skin.MicroMenuSkin.ResetRecommended)
            end, nil, P.Meta(PAGE, "skin", "micro.reset", "action", "suite_skin_micro_details"))
            return y - 40
        end)
end

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    local skin = Engine()
    if not skin then
        Section(ctx, b, "frame_basic", "Frame Basics",
            P.Combat() and "Open Skinning outside combat to load its settings." or "The Suite skin engine is unavailable.", {}, true)
        return
    end
    -- FixedPreviewSection must own the first builder slot so its reserved
    -- header space contains the preview instead of leaving a blank gap.
    Preview(ctx, b, skin)
    local basics = Section(ctx, b, "frame_basic", "Frame Basics",
        "Switch the whole Skinning module here, or adjust Blizzard and Suite windows separately below.", {
            Row("toggle", "Skin Blizzard windows", "enabled.windows", "frame_basic",
                function() return skin.DB.enabled end,
                function(value) Change(skin, "Skin Blizzard windows", "enabled.windows",
                    function() return skin.Adapters.SetMasterEnabled(value) end) end),
            Row("toggle", "Skin Suite windows and buttons", "suiteEnabled", "frame_basic",
                function() return Suite.Skin and Suite.Skin.enabled end,
                function(value) Change(skin, "Skin Suite windows", "suiteEnabled",
                    function() return Suite.Skin.SetEnabled(value) end) end),
        }, true)
    local enable = W.SectionSwitch(basics, Tr("Enable Skinning"), Tr("Enable"))
    M.BindBoolWidget(ctx, enable, function()
        return skin.DB.enabled == true or Suite.Skin and Suite.Skin.enabled == true
    end,
        function(value) Change(skin, "Skinning", "enabled", function()
            local windows = skin.Adapters.SetMasterEnabled(value)
            if not windows then return false end
            return Suite.Skin.SetEnabled(value)
        end) end,
        Meta("enabled", "frame_basic"))
    M.TrackRefresh(ctx, function() W.SetControlEnabled(enable, not P.Combat()) end)

    local looks = {}
    for _, key in ipairs(skin.LookOrder) do
        looks[#looks + 1] = { value = key, text = Tr(skin.LookPresets[key].label) }
    end
    looks[#looks + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    local defaultLook = skin.Defaults.theme.look
    local defaultLabel = skin.LookPresets[defaultLook].label
    Section(ctx, b, "basic", "Choose a look",
        "Choosing a look updates Skinning and every enabled Suite module. Modules enabled later inherit it. New skin profiles start with " .. defaultLabel .. ".", {
        Row("dropdown", "Style preset", "theme.look", "basic",
            function() return skin.DB.theme.look end,
            function(value) Change(skin, "Skin look", "look", function() return skin.Theme.ApplyLook(value) end) end, looks),
    }, true, function(body, y, width)
        local half = math.floor((width - 12) / 2)
        P.Button(ctx, body, "Restore " .. defaultLabel, 16, y, half, function()
            Change(skin, "Restore " .. defaultLabel, "look.default",
                function() return skin.Theme.ApplyLook(defaultLook) end)
        end, nil, P.Meta(PAGE, "skin", "look.default", "action", "suite_skin_basic"))
        P.Button(ctx, body, "All skin colors", 28 + half, y, half, function()
            if M.SelectPage then M.SelectPage("opt_colors") end
        end, nil, P.Meta(PAGE, "skin", "colors", "navigation", "suite_skin_basic"))
        return y - 40
    end)

    BuildMicroBar(ctx, b, skin)

    local hud = {
        Row("toggle", "Style objective tracker", "skins.objectiveTracker", "hud",
            function() return skin.DB.skins.objectiveTracker end,
            function(value) Change(skin, "Objective tracker", "skins.objectiveTracker",
                function() return skin.Adapters.SetEnabled("objectiveTracker", value) end) end),
        Row("dropdown", "Tracker style", "hud.objectiveTrackerStyle", "hud",
            function() return skin.DB.hud.objectiveTrackerStyle end,
            function(value) Change(skin, "Tracker style", "hud.objectiveTrackerStyle", function()
                if value ~= "forever" and value ~= "modern" then return false end
                skin.DB.hud.objectiveTrackerStyle = value
                skin.Adapters.Refresh("objectiveTracker")
                skin.Registry.NotifyListeners("hud", "objectiveTrackerStyle")
                return true
            end) end,
            Values({ "forever", "modern" })),
        Row("toggle", "MSUF colors on objectives", "skins.objectiveTrackerAccents", "hud",
            function() return skin.DB.skins.objectiveTrackerAccents end,
            function(value) Change(skin, "Objective colors", "skins.objectiveTrackerAccents",
                function() return skin.Adapters.SetEnabled("objectiveTrackerAccents", value) end) end),
        Row("toggle", "Style Blizzard damage meter", "skins.damageMeter", "hud",
            function() return skin.DB.skins.damageMeter end,
            function(value) Change(skin, "Blizzard damage meter", "skins.damageMeter",
                function() return skin.Adapters.SetEnabled("damageMeter", value) end) end),
    }
    for _, spec in ipairs({ { "Tracker title background", "objectiveTrackerBackground", "objectiveTracker" },
        { "Section headers", "objectiveTrackerHeaders", "objectiveTracker" },
        { "Objective progress bars", "objectiveTrackerBars", "objectiveTracker" },
        { "Damage meter windows", "damageMeterWindows", "damageMeter" },
        { "Damage meter rows", "damageMeterRows", "damageMeter" },
        { "Damage meter details", "damageMeterDetails", "damageMeter" } }) do
        local label, key, adapter = spec[1], spec[2], spec[3]
        hud[#hud + 1] = Row("toggle", label, "hud." .. key, "hud",
            function() return skin.DB.hud[key] end,
            function(value) Change(skin, label, "hud." .. key, function()
                skin.DB.hud[key] = value == true
                skin.Adapters.Refresh(adapter)
                skin.Registry.NotifyListeners("hud", key)
                return true
            end) end)
    end
    Section(ctx, b, "hud", "Blizzard HUD",
        "Objective headers use the selected look. Move the tracker in Blizzard Edit Mode; Blizzard keeps its position, tracking and actions.", hud, false)

    local material = {}
    for _, spec in ipairs({
        { "Shaded surfaces", "gradient", "toggle" },
        { "Light direction", "gradientDirection", "dropdown", { "VERTICAL", "HORIZONTAL" } },
        { "Shading strength", "gradientStrength", "slider", nil, 0, 1, 0.05 },
        { "Surface depth", "materialDepth", "slider", nil, 0, 1, 0.05 },
        { "Window opacity", "shellOpacity", "slider", nil, 0.35, 1, 0.05 },
        { "Content opacity", "panelOpacity", "slider", nil, 0.35, 1, 0.05 },
        { "Controls opacity", "controlOpacity", "slider", nil, 0.35, 1, 0.05 },
        { "Outline opacity", "borderOpacity", "slider", nil, 0, 1, 0.05 },
    }) do
        ConfigRow(skin, material, "material", spec[1], "theme", spec[2], spec[3], spec[4], spec[5], spec[6], spec[7],
            skin.Theme.SetAppearance)
    end
    Section(ctx, b, "material", "Glass and surfaces",
        "Adjust the glass effect while keeping your colors and window coverage.", material, true)

    local shape = {}
    for _, spec in ipairs({
        { "Window corners", "family", skin.GeometryFamilies },
        { "Button corners", "controlShape", skin.ControlShapes },
        { "Corner radius", "radius", skin.GeometryRadii },
        { "Outline thickness", "border", skin.GeometryBorders },
    }) do
        ConfigRow(skin, shape, "shape", spec[1], "geometry", spec[2], "dropdown", spec[3], nil, nil, nil,
            skin.Theme.SetGeometry)
    end
    ConfigRow(skin, shape, "shape", "Hover highlight", "theme", "hoverStyle", "dropdown", skin.HoverStyles,
        nil, nil, nil, skin.Theme.SetAppearance)
    ConfigRow(skin, shape, "shape", "Hover strength", "theme", "hoverIntensity", "slider", nil,
        0, 1, 0.05, skin.Theme.SetAppearance)
    Section(ctx, b, "shape", "Corners and hover", "Window shape, button shape, outlines and mouseover feedback.", shape, false)

    local paletteValues = Values(skin.PaletteOrder, skin.PaletteLabels)
    paletteValues[#paletteValues + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    local colors = {
        Row("dropdown", "Color palette", "theme.preset", "colors",
            function() return skin.DB.theme.preset end,
            function(value) Change(skin, "Skin color palette", "palette",
                function() return skin.Theme.ApplyPreset(value) end) end, paletteValues),
    }
    for _, spec in ipairs({ { "Window background", "background" }, { "Panel", "surface" },
        { "Button", "buttonFill" }, { "Accent", "accent" }, { "Text", "text" }, { "Border", "border" } }) do
        local label, key = spec[1], spec[2]
        local row = Meta("color." .. key, "colors")
        row.id, row.kind, row.label = key, "color", Tr(label)
        row.get = function()
            local color = skin.Theme.GetColorTable(key)
            return color[1], color[2], color[3], color[4]
        end
        row.set = function(r, g, blue, alpha)
            Change(skin, label, "color." .. key,
                function() return skin.Theme.SetColor(key, r, g, blue, alpha) end)
        end
        colors[#colors + 1] = row
    end
    Section(ctx, b, "colors", "Main colors",
        "Use the MSUF color picker here. The full palette is under Appearance > Colors > Suite skin.", colors, false,
        function(body, y, width)
            P.Button(ctx, body, "Reset skin colors to " .. skin.LookPresets[skin.Defaults.theme.look].label,
                16, y, width, function()
                Change(skin, "Reset skin colors", "colors.reset", skin.Theme.ResetColors)
            end, nil, P.Meta(PAGE, "skin", "colors.reset", "action", "suite_skin_colors"))
            return y - 40
        end)

    local fonts = {}
    fonts[#fonts + 1] = Row("toggle", "Override Blizzard fonts", "font.enabled", "fonts",
        function() return skin.DB.typography.enabled end,
        function(value) Change(skin, "Blizzard fonts", "font.enabled",
            function() return skin.Typography.SetEnabled(value) end) end)
    local function FontValues()
        local values = {}
        for _, key in ipairs(skin.Typography.GetSelectionValues()) do
            values[#values + 1] = { value = key, text = skin.Typography.GetSelectionLabel(key) }
        end
        return values
    end
    fonts[#fonts + 1] = Row("dropdown", "Font", "font.face", "fonts", skin.Typography.GetSelection,
        function(value) Change(skin, "Blizzard font", "font.face",
            function() return skin.Typography.SetSelection(value) end) end, FontValues)
    for _, spec in ipairs({ { "Chat and Communities", "applyChat", "SetApplyChat" },
        { "Quest, mail and combat text", "includeSpecial", "SetIncludeSpecial" } }) do
        local label, key, setter = spec[1], spec[2], spec[3]
        fonts[#fonts + 1] = Row("toggle", label, "font." .. key, "fonts",
            function() return skin.DB.typography[key] end,
            function(value) Change(skin, label, "font." .. key,
                function() return skin.Typography[setter](value) end) end)
    end
    Section(ctx, b, "fonts", "Fonts", "Blizzard keeps its text sizes and outlines.", fonts, false,
        function(body, y, width)
            M.BindTextInputAt(ctx, body, Tr("Custom font path"), 16, y, width,
                function() return skin.DB.typography.customPath or "" end,
                function(value) Change(skin, "Custom font path", "font.path",
                    function() return skin.Typography.SetCustomPath(value or "") end) end,
                true, Meta("font.path", "fonts"))
            return y - 60
        end)

    local icons = {}
    for _, spec in ipairs({
        { "Window action style", "style", "dropdown", skin.WindowActionStyles },
        { "Maximize/minimize symbols", "glyphMode", "dropdown", skin.WindowActionGlyphModes },
        { "Line weight", "weight", "dropdown", skin.WindowActionWeights },
        { "Maximize/minimize size", "glyphSize", "slider", nil, 8, 18, 1 },
        { "Close X size", "closeGlyphSize", "slider", nil, 6, 18, 1 },
        { "Action button shape", "surfaceShape", "dropdown", skin.WindowActionShapes },
        { "Action corner radius", "surfaceRadius", "dropdown", skin.GeometryRadii },
        { "Visual inset", "surfaceInset", "slider", nil, 0, 6, 1 },
        { "Glyph horizontal offset", "glyphOffsetX", "slider", nil, -4, 4, 1 },
        { "Glyph vertical offset", "glyphOffsetY", "slider", nil, -4, 4, 1 },
        { "Idle glyph opacity", "opacity", "slider", nil, 0.35, 1, 0.05 },
    }) do
        local label, key, kind = spec[1], spec[2], spec[3]
        icons[#icons + 1] = Row(kind, label, "icons.windowActions." .. key, "icons",
            function() return skin.DB.icons.windowActions[key] end,
            function(value) Change(skin, label, "icons.windowActions." .. key,
                function() return skin.WindowActionSkin.SetOption(key, value) end) end,
            kind == "dropdown" and Values(spec[4]) or nil, spec[5], spec[6], spec[7])
    end
    for _, spec in ipairs({
        { "Item icon border", "iconBorderStyle", "dropdown", skin.IconBorderStyles },
        { "Item border thickness", "iconBorderThickness", "slider", nil, 1, 3, 1 },
        { "Item border padding", "iconBorderPadding", "slider", nil, 0, 3, 1 },
        { "Item border opacity", "iconBorderOpacity", "slider", nil, 0, 1, 0.05 },
    }) do
        ConfigRow(skin, icons, "icons", spec[1], "theme", spec[2], spec[3], spec[4], spec[5], spec[6], spec[7],
            skin.Theme.SetAppearance)
    end
    Section(ctx, b, "icons", "Window buttons and icon borders",
        "Close, expand and minimize symbols plus item borders.", icons, false,
        function(body, y, width)
            P.Button(ctx, body, "Reset window buttons", 16, y, width, function()
                Change(skin, "Reset window buttons", "icons.windowActions.reset",
                    skin.WindowActionSkin.ResetRecommended)
            end, nil, P.Meta(PAGE, "skin", "icons.windowActions.reset", "action", "suite_skin_icons"))
            return y - 40
        end)

    local windowControls = {
        Row("toggle", "Move, resize and minimize Blizzard windows", "windowControls.enabled", "icons",
            function() return skin.DB.windowControls.enabled end,
            function(value) Change(skin, "Blizzard window controls", "windowControls.enabled",
                function() return skin.WindowControls.SetEnabled(value) end) end),
    }
    Section(ctx, b, "window_controls", "Window position, size and minimize",
        "Drag a window by its top edge; drag the bottom-right corner to scale it. The top-right minus button collapses compatible windows to a restore tab. Bags and protected windows keep their native behavior.",
        windowControls, false, function(body, y, width)
            P.Button(ctx, body, "Reset Blizzard window positions and sizes", 16, y, width, function()
                Change(skin, "Reset Blizzard window layout", "windowControls.layout",
                    skin.WindowControls.ResetLayout)
            end, nil, P.Meta(PAGE, "skin", "windowControls.layout", "action", "suite_skin_icons"))
            return y - 40
        end)

    local windows = {}
    local order, definitions = skin.Adapters.GetDefinitions()
    for _, id in ipairs(order) do
        if id ~= "microMenu" and id ~= "objectiveTracker"
            and id ~= "objectiveTrackerAccents" and id ~= "damageMeter" then
            local definition = definitions[id]
            local label = definition and definition.labelKey and skin.L[definition.labelKey] or id
            windows[#windows + 1] = Row("toggle", label, "skins." .. id, "windows",
                function() return skin.DB.skins[id] end,
                function(value) Change(skin, label, "skins." .. id,
                    function() return skin.Adapters.SetEnabled(id, value) end) end)
        end
    end
    Section(ctx, b, "windows", "Blizzard windows",
        "Choose which Blizzard interfaces receive the skin. Blizzard keeps their interactions.", windows, false)

    local categories = {}
    for _, item in ipairs(skin.GenericWindows.GetCategories()) do
        local id = item.id
        categories[#categories + 1] = Row("toggle", CATEGORY_LABELS[id] or id,
            "coverage." .. id, "coverage", function() return skin.DB.skinCategories[id] end,
            function(value) Change(skin, "Skin " .. id, "coverage." .. id,
                function() return skin.GenericWindows.SetCategoryEnabled(id, value) end) end)
    end
    Section(ctx, b, "coverage", "Window categories",
        "Narrow general Blizzard window coverage by category.", categories, false)

    local character = {
        Row("dropdown", "Character view", "character.view", "character",
            function() return skin.DB.characterDetails.view end,
            function(value) Change(skin, "Character view", "character.view",
                function() return skin.CharacterDetails.SetView(value) end) end,
            Values({ "modern", "list", "classic" })),
    }
    for _, spec in ipairs({ { "Character details", "characterDetails", "enabled", "CharacterDetails" },
        { "Expanded details", "characterDetails", "expanded", "CharacterDetails" },
        { "Character quality of life style", "characterDetails", "styleEQoL", "CharacterDetails" },
        { "Inline gear", "characterDetails", "inlineGear", "CharacterDetails" },
        { "Wide layout", "characterDetails", "wideLayout", "CharacterDetails" },
        { "Character stats", "characterStats", "enabled", "CharacterStats" },
        { "Diminishing returns", "characterStats", "diminishingReturns", "CharacterStats" } }) do
        local label, group, key, api = spec[1], spec[2], spec[3], spec[4]
        character[#character + 1] = Row("toggle", label, group .. "." .. key, "character",
            function() return skin.DB[group][key] end,
            function(value) Change(skin, label, group .. "." .. key,
                function() return skin[api].SetOption(key, value) end) end)
    end
    Section(ctx, b, "character", "Character panel and stats",
        "Choose the detailed character view and its extra information. Changing the view reloads the UI.", character, false)

    Section(ctx, b, "advanced", "Maintenance",
        "Refresh newly opened Blizzard windows or restore the active skin profile to the client default.",
        {}, false, function(body, y, width)
            local half = math.floor((width - 12) / 2)
            P.Button(ctx, body, "Refresh Blizzard skins", 16, y, half, function()
                if skin.Adapters.ApplyAll then skin.Adapters.ApplyAll() end
            end, nil, P.Meta(PAGE, "skin", "maintenance.refresh", "action", "suite_skin_advanced"))
            local armed = false
            local reset
            reset = P.Button(ctx, body, "Reset active skin profile", 28 + half, y, half, function()
                if not armed then
                    armed = true
                    reset:SetText(Tr("Confirm skin reset"))
                    if reset._msuf2Label then reset._msuf2Label:SetText(Tr("Confirm skin reset")) end
                    return
                end
                armed = false
                Change(skin, "Reset active skin profile", "maintenance.reset", function()
                    skin.Database.ResetAll()
                    skin.Typography.ApplyConfigured()
                    skin.Adapters.ApplyAll()
                    skin.Registry.RefreshAll()
                    skin.Registry.NotifyListeners("theme", "reset")
                    return true
                end)
                reset:SetText(Tr("Reset active skin profile"))
                if reset._msuf2Label then reset._msuf2Label:SetText(Tr("Reset active skin profile")) end
            end, nil, P.Meta(PAGE, "skin", "maintenance.reset", "action", "suite_skin_advanced"))
            return y - 40
        end)
end

P.RegisterPage({ key = PAGE, label = "Skinning", title = "Skinning", build = Build, icon = { 4, 1 },
    aliases = { "suite_skin", "mapkoskin", "skinning" } })
