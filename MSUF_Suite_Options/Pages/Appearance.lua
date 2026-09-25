local _, P = ...
local Suite, M, W, T, Tr = P.Suite, P.M, P.W, P.T, P.Tr
local PAGE = "suite_skin"
local format = string.format

-- The skin engine loads on demand (never in combat) the first time this page
-- is built.
local function Engine()
    local skin = _G.MapkoSkin
    if not (skin and skin.addonName == "MSUF_Suite_Skin") and Suite.Skin and Suite.Skin.EnsureEngine
        and not P.Combat() then
        Suite.Skin.EnsureEngine()
        skin = _G.MapkoSkin
    end
    if skin and skin.addonName == "MSUF_Suite_Skin" and skin.DB and skin.Theme then return skin end
end

-- Every skin write is one MSUF history entry; the page repaints afterwards.
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
local MICRO_PRESET_LABELS = {
    forever = "MSUF Forever", modern = "Midnight Blue", midnightDark = "Midnight Dark",
    blizzard = "Blizzard original",
}
local BAR_MATERIAL_LABELS = {
    modern = "Midnight Blue", midnightDark = "Midnight Dark",
    forever = "MSUF Forever", theme = "Follow skin look",
}

-- Dropdown values; unknown camelCase values read as words ("outOfCombat" ->
-- "Out Of Combat").
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
    if kind == "dropdown" then
        row.values = values
    elseif kind == "slider" then
        row.min, row.max, row.step = min, max, P.SliderStep(min, max, nil, step)
        row.roundStep = row.step >= 1
    end
    return row
end

-- The section's three-dot menu edits its color rows (all skin colors for the
-- palette section).
local function AttachColors(body, title, rows)
    local colorRows = {}
    for _, row in ipairs(rows) do
        if row.kind == "color" then colorRows[#colorRows + 1] = row end
    end
    if #colorRows == 0 or not W.AttachContextColorShortcut then return end
    local shortcut = W.AttachContextColorShortcut(body, {
        title = Tr(title),
        maxTargets = #colorRows,
        getTargets = function()
            local targets = {}
            for _, row in ipairs(colorRows) do
                targets[#targets + 1] = {
                    label = row.label,
                    get = row.get,
                    set = row.set,
                    settingKey = row.settingKey,
                    hasOpacity = true,
                    getOpacity = function() return select(4, row.get()) end,
                }
            end
            return targets
        end,
    })
    if shortcut then shortcut._msuf2BoundColorShortcut = nil end
end

local function SkinDefault(defaults, id)
    if id == "suiteEnabled" then return true end
    if id == "enabled.windows" then return defaults.enabled end
    if id == "font.face" then return defaults.typography.face end
    if id:sub(1, 5) == "font." then id = "typography." .. id:sub(6) end
    if id:sub(1, 10) == "character." then id = "characterDetails." .. id:sub(11) end
    if id:sub(1, 6) == "color." then id = "theme.colors." .. id:sub(7) end
    if id:sub(1, 9) == "coverage." then id = "skinCategories." .. id:sub(10) end
    local value = defaults
    for part in id:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function ResetSkinSection(skin, id, rows, contextRows)
    if P.Combat() or not skin then return false end
    local defaults = skin.Database.CreateFactoryProfile()
    if type(defaults) ~= "table" then return false end
    local seen, changes = {}, {}
    for _, list in ipairs({ rows or {}, contextRows or {} }) do
        for _, row in ipairs(list) do
            if not seen[row.id] then
                seen[row.id] = true
                local value = SkinDefault(defaults, row.id)
                if value ~= nil then changes[#changes + 1] = { row = row, value = value } end
            end
        end
    end
    if id == "fonts" then
        changes[#changes + 1] = { row = { id = "typography.customPath" }, value = defaults.typography.customPath }
    end
    if #changes == 0 then return false end
    return Change(skin, "Reset section", "section." .. id, function()
        if id == "basic" then
            if not skin.Theme.ApplyLook(defaults.theme.look) then return false end
        elseif id == "micro" then
            if not skin.MicroMenuSkin.ApplyPreset(defaults.icons.microMenu.preset) then return false end
        end
        for _, item in ipairs(changes) do
            local path = item.row.id
            if path == "suiteEnabled" then
                if Suite.Skin then Suite.Skin.SetEnabled(item.value == true) end
            else
                if path == "enabled.windows" then path = "enabled" end
                if path:sub(1, 5) == "font." then path = "typography." .. path:sub(6) end
                if path:sub(1, 10) == "character." then path = "characterDetails." .. path:sub(11) end
                if path:sub(1, 6) == "color." then path = "theme.colors." .. path:sub(7) end
                if path:sub(1, 9) == "coverage." then path = "skinCategories." .. path:sub(10) end
                local parent, last = skin.DB, nil
                for part in path:gmatch("[^.]+") do
                    if last then parent = parent[last] end
                    last = part
                end
                if type(parent) == "table" and last then parent[last] = Suite.CopyValue(item.value) end
            end
        end
        if id == "material" or id == "shape" or id == "colors" or id == "icons" then
            skin.DB.theme.look = "custom"
        end
        skin.Typography.ApplyConfigured()
        skin.Adapters.ApplyAll()
        skin.Registry.RefreshAll()
        skin.Registry.NotifyListeners("theme", "section-reset")
        return true
    end)
end

-- One accordion: help, a settings grid of the non-color rows, an optional
-- `extra(body, y, width) -> y` builder, and the color shortcut.
local function Section(ctx, b, id, title, help, rows, open, extra, contextRows)
    local body = b:CollapsibleSection("suite_skin_" .. id, Tr(title), 120, open)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = -18
    if help then
        local hint = P.Text(body, help, 16, y, width)
        y = y - math.max(14, math.ceil(hint:GetStringHeight() or 14)) - 12
    end
    local visibleRows = {}
    for _, row in ipairs(rows) do
        if row.kind ~= "color" then visibleRows[#visibleRows + 1] = row end
    end
    if #visibleRows > 0 then
        local grid = W.SettingsRows(ctx, body, {
            x = 16, y = y, width = width, columns = width >= 520 and 2 or 1, rows = visibleRows,
        })
        y = grid.bottomY
    end
    if extra then y = extra(body, y, width) or y end
    AttachColors(body, title, contextRows or rows)
    if id ~= "advanced" then
        P.AttachSectionReset(ctx, body, title, function()
            return ResetSkinSection(Engine(), id, rows, contextRows)
        end)
    end
    P.FinishBody(b, body, y)
    return body
end

local function SkinColorRow(skin, key, label)
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
    return row
end

-- A row bound to skin.DB[path][key], written through `setter(key, value)`.
local function ConfigRow(skin, rows, section, label, path, key, kind, values, min, max, step, setter)
    local id = path .. "." .. key
    rows[#rows + 1] = Row(kind, label, id, section,
        function() return skin.DB[path][key] end,
        function(value) Change(skin, label, id, function() return setter(key, value) end) end,
        kind == "dropdown" and Values(values) or nil, min, max, step)
end

local function SkinBox(skin, parent, x, y, width, height, role)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    if skin.Surface and skin.Surface.Attach then skin.Surface.Attach(frame, { role = role }) end
    return frame
end

-- The docked sample renders with the skin engine's own surfaces.
local function Preview(ctx, b, skin)
    local section, toolbar = W.FixedPreviewSection(ctx, b, { title = Tr("Skin preview"), height = 176 })
    if not section then return end
    local hint = T.Font(toolbar, "GameFontDisableSmall", Tr("Choose a look below; this sample follows your changes."),
        T.colors.muted)
    hint:SetPoint("LEFT", toolbar, "LEFT", 125, 0)
    hint:SetPoint("RIGHT", toolbar, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    local canvas = CreateFrame("Frame", nil, section)
    canvas:SetPoint("TOPLEFT", 14, -42)
    canvas:SetPoint("BOTTOMRIGHT", -14, 9)
    local shell = SkinBox(skin, canvas, 10, -7, 292, 116, "shell")
    local title = T.Font(shell, "GameFontNormal", Tr("Window shell"), T.colors.text)
    title:SetPoint("TOPLEFT", 14, -12)
    local panel = SkinBox(skin, shell, 13, -37, 266, 66, "panel")
    local card = SkinBox(skin, panel, 10, -10, 246, 22, "card")
    local cardLabel = T.Font(card, "GameFontHighlightSmall", Tr("Panel and card layer"), T.colors.text)
    cardLabel:SetPoint("LEFT", 8, 0)
    local button = SkinBox(skin, panel, 10, -40, 76, 19, "buttonPrimary")
    local buttonLabel = T.Font(button, "GameFontHighlightSmall", Tr("Primary"), T.colors.text)
    buttonLabel:SetPoint("CENTER")
    local note = P.Text(canvas, "", 326, -18, 300)
    -- Labels take the token's RGB only; the preview keeps them opaque.
    local function PaintLabel(label, token)
        local r, g, blue = skin.Theme.GetColor(token)
        label:SetTextColor(r, g, blue)
    end
    M.TrackRefresh(ctx, function()
        PaintLabel(title, "title")
        PaintLabel(cardLabel, "text")
        PaintLabel(buttonLabel, "accent")
        local look = skin.LookPresets[skin.DB.theme.look]
        note:SetText(Tr(look and look.label or "Custom") .. "\n"
            .. Tr(look and look.description or "Your own colors, materials and shape."))
    end)
end

------------------------------------------------------------------ Micro Bar
local MICRO_PRESETS = { "modern", "midnightDark", "forever", "blizzard" }

local function MicroOption(skin, label, key)
    return function(value)
        Change(skin, label, "micro." .. key, function() return skin.MicroMenuSkin.SetOption(key, value) end)
    end
end

local function MicroRows(skin)
    local settings = function() return skin.DB.icons.microMenu end
    return {
        Row("toggle", "Style the Micro Bar", "skins.microMenu", "micro",
            function() return skin.DB.skins.microMenu end,
            function(value)
                Change(skin, "Micro Bar", "skins.microMenu",
                    function() return skin.Adapters.SetEnabled("microMenu", value) end)
            end),
        Row("dropdown", "Show Micro Bar", "icons.microMenu.visibility", "micro",
            function() return settings().visibility end,
            MicroOption(skin, "Micro Bar visibility", "visibility"), Values(skin.MicroMenuVisibilityModes)),
        Row("dropdown", "Bar direction", "icons.microMenu.orientation", "micro",
            function() return settings().orientation end,
            MicroOption(skin, "Micro Bar direction", "orientation"), Values(skin.MicroMenuOrientations)),
        Row("slider", "Buttons per line", "icons.microMenu.buttonsPerLine", "micro",
            function() return settings().buttonsPerLine end,
            MicroOption(skin, "Micro Bar buttons", "buttonsPerLine"),
            nil, 1, skin.Client and skin.Client.isForever and 14 or 13, 1),
        Row("slider", "Scale", "icons.microMenu.scale", "micro",
            function() return settings().scale end,
            MicroOption(skin, "Micro Bar scale", "scale"), nil, 0.5, 1.5, 0.05),
    }
end

local function MicroLoadRows(skin)
    local rows = {}
    for _, condition in ipairs(skin.MicroMenuLoadConditions) do
        local key, label = condition[1], condition[2]
        rows[#rows + 1] = Row("toggle", label, "icons.microMenu." .. key, "micro_load_conditions",
            function() return skin.DB.icons.microMenu[key] end,
            MicroOption(skin, "Micro Bar " .. label, key))
    end
    return rows
end

local function MicroHint(preset)
    local label = MICRO_PRESET_LABELS[preset] or preset == "custom" and "Custom" or "Other style"
    local detail = preset == "blizzard"
        and "Blizzard's original Micro Bar and buttons. Use Blizzard Edit Mode to move it."
        or "MSUF looks use Suite glyphs and a player portrait. Blizzard keeps every button action and tooltip."
    return format(Tr("Selected: %s. %s"), Tr(label), Tr(detail))
end

-- Makes sure the Suite owns a styled bar before MSUF Edit Mode opens it.
local function MoveMicroBar(skin)
    if not skin.DB.skins.microMenu then
        Change(skin, "Style Micro Bar", "skins.microMenu",
            function() return skin.Adapters.SetEnabled("microMenu", true) end)
    end
    if skin.DB.icons.microMenu.layoutMode ~= "owned" then
        Change(skin, "Move Micro Bar", "micro.layoutMode",
            function() return skin.MicroMenuSkin.SetOption("layoutMode", "owned") end)
    end
    if skin.OwnedMicroBar then skin.OwnedMicroBar.OpenEditMode() end
end

-- Preset buttons, the selected preset's note and the Edit Mode shortcut.
local function MicroPresetExtra(ctx, skin)
    return function(body, y, width)
        local half = math.floor((width - 12) / 2)
        for index, style in ipairs(MICRO_PRESETS) do
            P.Button(ctx, body, MICRO_PRESET_LABELS[style],
                16 + ((index - 1) % 2) * (half + 12), y - math.floor((index - 1) / 2) * 38, half, function()
                    Change(skin, "Micro Bar " .. style, "micro.preset",
                        function() return skin.MicroMenuSkin.ApplyPreset(style) end)
                end, nil, P.Meta(PAGE, "skin", "micro.preset." .. style, "action", "suite_skin_micro"))
        end
        local description = P.Text(body, "", 16, y - 72, width)
        local function RefreshMicroHint()
            description:SetText(MicroHint(skin.DB.icons.microMenu.preset))
        end
        RefreshMicroHint()
        M.TrackRefresh(ctx, RefreshMicroHint)
        local descHeight = math.max(22, math.ceil(description:GetStringHeight() or 22))
        P.Button(ctx, body, "Move in MSUF Edit Mode", 16, y - 82 - descHeight, width,
            function() MoveMicroBar(skin) end, nil, P.Meta(PAGE, "skin", "micro.move", "action", "suite_skin_micro"))
        return y - 120 - descHeight
    end
end

-- { label, key, kind, values, min, max, step } of the detail rows.
local function MicroDetailSpecs(skin)
    return {
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
    }
end

-- A glyph needs 4 px of room inside its button; bigger glyphs grow the button.
local function SetMicroDetail(skin, key, value)
    if key == "iconSize" and value > (skin.DB.icons.microMenu.buttonSize or 28) - 4 then
        local required = math.min(32, math.floor(value + 4.5))
        if skin.MicroMenuSkin.SetOption("buttonSize", required) == false then return false end
    end
    return skin.MicroMenuSkin.SetOption(key, value)
end

local function MicroDetailRows(skin)
    local styles = Values(skin.MicroMenuPresets, MICRO_PRESET_LABELS)
    styles[#styles + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    local details = {
        Row("dropdown", "Style", "icons.microMenu.preset", "micro_details",
            function() return skin.DB.icons.microMenu.preset end,
            function(value)
                Change(skin, "Micro Bar style", "micro.preset", function() return skin.MicroMenuSkin.ApplyPreset(value) end)
            end, styles),
    }
    for _, spec in ipairs(MicroDetailSpecs(skin)) do
        local label, key, kind = spec[1], spec[2], spec[3]
        local values = kind == "dropdown"
            and Values(spec[4], key == "barMaterial" and BAR_MATERIAL_LABELS or nil) or nil
        details[#details + 1] = Row(kind, label, "icons.microMenu." .. key, "micro_details",
            function() return skin.DB.icons.microMenu[key] end,
            function(value)
                Change(skin, label, "micro." .. key, function() return SetMicroDetail(skin, key, value) end)
            end, values, spec[5], spec[6], spec[7])
    end
    return details
end

local function BuildMicroBar(ctx, b, skin)
    Section(ctx, b, "micro", "Micro Bar",
        "Choose a look and when the Suite bar appears. Visibility rules use the Suite layout; Blizzard layout keeps Blizzard's visibility. MSUF Edit Mode reveals the bar for moving.",
        MicroRows(skin), true, MicroPresetExtra(ctx, skin))
    Section(ctx, b, "micro_load_conditions", "Micro Bar Load Conditions",
        "Hide the Suite Micro Bar when any selected condition is true. The health condition uses your character's health; at full health the transparent bar can still receive clicks. MSUF Edit Mode shows the bar for placement. Blizzard layout keeps Blizzard's visibility.",
        MicroLoadRows(skin), false)
    Section(ctx, b, "micro_details", "Micro Bar details",
        "Optional artwork and spacing controls. Use MSUF Edit Mode for position, nudging, reset, undo and redo.",
        MicroDetailRows(skin), false, function(body, y, width)
            P.Button(ctx, body, "Reset Micro Bar to client default", 16, y, width, function()
                Change(skin, "Reset Micro Bar", "micro.reset", skin.MicroMenuSkin.ResetRecommended)
            end, nil, P.Meta(PAGE, "skin", "micro.reset", "action", "suite_skin_micro_details"))
            return y - 40
        end)
end

------------------------------------------------------------------ sections
local function BuildFrameBasics(ctx, b, skin)
    local basics = Section(ctx, b, "frame_basic", "Frame Basics",
        "Switch the whole Skinning module here, or adjust Blizzard and Suite windows separately below.", {
            Row("toggle", "Skin Blizzard windows", "enabled.windows", "frame_basic",
                function() return skin.DB.enabled end,
                function(value)
                    Change(skin, "Skin Blizzard windows", "enabled.windows",
                        function() return skin.Adapters.SetMasterEnabled(value) end)
                end),
            Row("toggle", "Skin Suite windows and buttons", "suiteEnabled", "frame_basic",
                function() return Suite.Skin and Suite.Skin.enabled end,
                function(value)
                    Change(skin, "Skin Suite windows", "suiteEnabled", function() return Suite.Skin.SetEnabled(value) end)
                end),
        }, true)
    local enable = W.SectionSwitch(basics, Tr("Enable Skinning"), Tr("Enable"))
    M.BindBoolWidget(ctx, enable,
        function() return skin.DB.enabled == true or Suite.Skin and Suite.Skin.enabled == true end,
        function(value)
            Change(skin, "Skinning", "enabled", function()
                local windows = skin.Adapters.SetMasterEnabled(value)
                if not windows then return false end
                return Suite.Skin.SetEnabled(value)
            end)
        end,
        Meta("enabled", "frame_basic"))
    M.TrackRefresh(ctx, function() W.SetControlEnabled(enable, not P.Combat()) end)
end

local function BuildLook(ctx, b, skin)
    local looks = {}
    for _, key in ipairs(skin.LookOrder) do
        looks[#looks + 1] = { value = key, text = Tr(skin.LookPresets[key].label) }
    end
    looks[#looks + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    local defaultLook = skin.Defaults.theme.look
    local defaultLabel = Tr(skin.LookPresets[defaultLook].label)
    Section(ctx, b, "basic", "Choose a look",
        format(Tr("Choosing a look updates Skinning and every enabled Suite module. Modules enabled later inherit it. New skin profiles start with %s."), defaultLabel), {
            Row("dropdown", "Style preset", "theme.look", "basic",
                function() return skin.DB.theme.look end,
                function(value)
                    Change(skin, "Skin look", "look", function() return skin.Theme.ApplyLook(value) end)
                end, looks),
        }, true, function(body, y, width)
            local half = math.floor((width - 12) / 2)
            local restore = format(Tr("Restore %s"), defaultLabel)
            P.Button(ctx, body, restore, 16, y, half, function()
                Change(skin, restore, "look.default", function() return skin.Theme.ApplyLook(defaultLook) end)
            end, nil, P.Meta(PAGE, "skin", "look.default", "action", "suite_skin_basic"))
            P.Button(ctx, body, "All skin colors", 28 + half, y, half, function()
                if M.SelectPage then M.SelectPage("opt_colors") end
            end, nil, P.Meta(PAGE, "skin", "colors", "navigation", "suite_skin_basic"))
            return y - 40
        end)
end

local HUD_TOGGLES = {
    { "Damage meter windows", "damageMeterWindows" },
    { "Damage meter rows", "damageMeterRows" },
    { "Damage meter details", "damageMeterDetails" },
}

local function BuildHUD(ctx, b, skin)
    local hud = {
        Row("toggle", "Style Blizzard damage meter", "skins.damageMeter", "hud",
            function() return skin.DB.skins.damageMeter end,
            function(value)
                Change(skin, "Blizzard damage meter", "skins.damageMeter",
                    function() return skin.Adapters.SetEnabled("damageMeter", value) end)
            end),
    }
    for _, spec in ipairs(HUD_TOGGLES) do
        local label, key = spec[1], spec[2]
        hud[#hud + 1] = Row("toggle", label, "hud." .. key, "hud",
            function() return skin.DB.hud[key] end,
            function(value)
                Change(skin, label, "hud." .. key, function()
                    skin.DB.hud[key] = value == true
                    skin.Adapters.Refresh("damageMeter")
                    skin.Registry.NotifyListeners("hud", key)
                    return true
                end)
            end)
    end
    Section(ctx, b, "hud", "Blizzard HUD",
        "Style the Blizzard damage meter. Configure the Suite Objective Tracker and announcements on the HUD page.",
        hud, false)
end

local MATERIAL_SPECS = {
    { "Shaded surfaces", "gradient", "toggle" },
    { "Light direction", "gradientDirection", "dropdown", { "VERTICAL", "HORIZONTAL" } },
    { "Shading strength", "gradientStrength", "slider", nil, 0, 1, 0.05 },
    { "Surface depth", "materialDepth", "slider", nil, 0, 1, 0.05 },
    { "Window opacity", "shellOpacity", "slider", nil, 0.35, 1, 0.05 },
    { "Content opacity", "panelOpacity", "slider", nil, 0.35, 1, 0.05 },
    { "Controls opacity", "controlOpacity", "slider", nil, 0.35, 1, 0.05 },
    { "Outline opacity", "borderOpacity", "slider", nil, 0, 1, 0.05 },
}

local function BuildMaterial(ctx, b, skin)
    local material = {}
    for _, spec in ipairs(MATERIAL_SPECS) do
        ConfigRow(skin, material, "material", spec[1], "theme", spec[2], spec[3], spec[4], spec[5], spec[6], spec[7],
            skin.Theme.SetAppearance)
    end
    Section(ctx, b, "material", "Glass and surfaces",
        "Adjust the glass effect while keeping your colors and window coverage.", material, true)
end

local function BuildShape(ctx, b, skin)
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
end

local MAIN_COLORS = {
    { "Window background", "background" }, { "Panel", "surface" }, { "Button", "buttonFill" },
    { "Accent", "accent" }, { "Text", "text" }, { "Border", "border" },
}

local function BuildColors(ctx, b, skin)
    local paletteValues = Values(skin.PaletteOrder, skin.PaletteLabels)
    paletteValues[#paletteValues + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    local colors = {
        Row("dropdown", "Color palette", "theme.preset", "colors",
            function() return skin.DB.theme.preset end,
            function(value)
                Change(skin, "Skin color palette", "palette", function() return skin.Theme.ApplyPreset(value) end)
            end, paletteValues),
    }
    for _, spec in ipairs(MAIN_COLORS) do
        colors[#colors + 1] = SkinColorRow(skin, spec[2], spec[1])
    end
    local paletteRows = {}
    for _, entry in ipairs(skin.ColorOrder or {}) do
        paletteRows[#paletteRows + 1] = SkinColorRow(skin, entry[1], (skin.L and skin.L[entry[2]]) or entry[1])
    end
    local defaultLabel = Tr(skin.LookPresets[skin.Defaults.theme.look].label)
    Section(ctx, b, "colors", "Main colors",
        "Use the color dots for the full skin palette. The same colors are under Appearance > Colors > Suite skin.",
        colors, false, function(body, y, width)
            P.Button(ctx, body, format(Tr("Reset skin colors to %s"), defaultLabel), 16, y, width, function()
                Change(skin, "Reset skin colors", "colors.reset", skin.Theme.ResetColors)
            end, nil, P.Meta(PAGE, "skin", "colors.reset", "action", "suite_skin_colors"))
            return y - 40
        end, paletteRows)
end

local FONT_TOGGLES = {
    { "Chat and Communities", "applyChat", "SetApplyChat" },
    { "Quest, mail and combat text", "includeSpecial", "SetIncludeSpecial" },
}

local function BuildFonts(ctx, b, skin)
    local fonts = {
        Row("toggle", "Override Blizzard fonts", "font.enabled", "fonts",
            function() return skin.DB.typography.enabled end,
            function(value)
                Change(skin, "Blizzard fonts", "font.enabled", function() return skin.Typography.SetEnabled(value) end)
            end),
    }
    local function FontValues()
        local values = {}
        for _, key in ipairs(skin.Typography.GetSelectionValues()) do
            values[#values + 1] = { value = key, text = skin.Typography.GetSelectionLabel(key) }
        end
        return values
    end
    fonts[#fonts + 1] = Row("dropdown", "Font", "font.face", "fonts", skin.Typography.GetSelection,
        function(value)
            Change(skin, "Blizzard font", "font.face", function() return skin.Typography.SetSelection(value) end)
        end, FontValues)
    for _, spec in ipairs(FONT_TOGGLES) do
        local label, key, setter = spec[1], spec[2], spec[3]
        fonts[#fonts + 1] = Row("toggle", label, "font." .. key, "fonts",
            function() return skin.DB.typography[key] end,
            function(value)
                Change(skin, label, "font." .. key, function() return skin.Typography[setter](value) end)
            end)
    end
    Section(ctx, b, "fonts", "Fonts", "Blizzard keeps its text sizes and outlines.", fonts, false,
        function(body, y, width)
            M.BindTextInputAt(ctx, body, Tr("Custom font path"), 16, y, width,
                function() return skin.DB.typography.customPath or "" end,
                function(value)
                    Change(skin, "Custom font path", "font.path",
                        function() return skin.Typography.SetCustomPath(value or "") end)
                end,
                true, Meta("font.path", "fonts"))
            return y - 60
        end)
end

local function BuildIcons(ctx, b, skin)
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
            function(value)
                Change(skin, label, "icons.windowActions." .. key,
                    function() return skin.WindowActionSkin.SetOption(key, value) end)
            end,
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
end

local function BuildWindowControls(ctx, b, skin)
    Section(ctx, b, "window_controls", "Window position, size and minimize",
        "Drag a window by its top edge; drag the bottom-right corner to scale it. The top-right minus button collapses compatible windows to a restore tab. Bags and protected windows keep their native behavior.", {
            Row("toggle", "Move, resize and minimize Blizzard windows", "windowControls.enabled", "icons",
                function() return skin.DB.windowControls.enabled end,
                function(value)
                    Change(skin, "Blizzard window controls", "windowControls.enabled",
                        function() return skin.WindowControls.SetEnabled(value) end)
                end),
        }, false, function(body, y, width)
            P.Button(ctx, body, "Reset Blizzard window positions and sizes", 16, y, width, function()
                Change(skin, "Reset Blizzard window layout", "windowControls.layout", skin.WindowControls.ResetLayout)
            end, nil, P.Meta(PAGE, "skin", "windowControls.layout", "action", "suite_skin_icons"))
            return y - 40
        end)
end

-- Micro Bar and damage meter adapters have their own sections above.
local function BuildWindows(ctx, b, skin)
    local windows = {}
    local order, definitions = skin.Adapters.GetDefinitions()
    for _, id in ipairs(order) do
        if id ~= "microMenu" and id ~= "damageMeter" then
            local definition = definitions[id]
            local label = definition and definition.labelKey and skin.L[definition.labelKey] or id
            windows[#windows + 1] = Row("toggle", label, "skins." .. id, "windows",
                function() return skin.DB.skins[id] end,
                function(value)
                    Change(skin, label, "skins." .. id, function() return skin.Adapters.SetEnabled(id, value) end)
                end)
        end
    end
    Section(ctx, b, "windows", "Blizzard windows",
        "Choose which Blizzard interfaces receive the skin. Blizzard keeps their interactions.", windows, false)
end

local function BuildCoverage(ctx, b, skin)
    local categories = {}
    for _, item in ipairs(skin.GenericWindows.GetCategories()) do
        local id = item.id
        categories[#categories + 1] = Row("toggle", CATEGORY_LABELS[id] or id,
            "coverage." .. id, "coverage", function() return skin.DB.skinCategories[id] end,
            function(value)
                Change(skin, "Skin " .. id, "coverage." .. id,
                    function() return skin.GenericWindows.SetCategoryEnabled(id, value) end)
            end)
    end
    Section(ctx, b, "coverage", "Window categories",
        "Narrow general Blizzard window coverage by category.", categories, false)
end

local CHARACTER_TOGGLES = {
    { "Character details", "characterDetails", "enabled", "CharacterDetails" },
    { "Expanded details", "characterDetails", "expanded", "CharacterDetails" },
    { "Character quality of life style", "characterDetails", "styleEQoL", "CharacterDetails" },
    { "Inline gear", "characterDetails", "inlineGear", "CharacterDetails" },
    { "Wide layout", "characterDetails", "wideLayout", "CharacterDetails" },
    { "Character stats", "characterStats", "enabled", "CharacterStats" },
    { "Diminishing returns", "characterStats", "diminishingReturns", "CharacterStats" },
}

local function BuildCharacter(ctx, b, skin)
    local character = {
        Row("dropdown", "Character view", "character.view", "character",
            function() return skin.DB.characterDetails.view end,
            function(value)
                Change(skin, "Character view", "character.view", function() return skin.CharacterDetails.SetView(value) end)
            end,
            Values({ "modern", "list", "classic" })),
    }
    for _, spec in ipairs(CHARACTER_TOGGLES) do
        local label, group, key, api = spec[1], spec[2], spec[3], spec[4]
        character[#character + 1] = Row("toggle", label, group .. "." .. key, "character",
            function() return skin.DB[group][key] end,
            function(value)
                Change(skin, label, group .. "." .. key, function() return skin[api].SetOption(key, value) end)
            end)
    end
    Section(ctx, b, "character", "Character panel and stats",
        "Choose the detailed character view and its extra information. Changing the view reloads the UI.",
        character, false)
end

local function ResetSkinProfile(skin)
    skin.Database.ResetAll()
    skin.Typography.ApplyConfigured()
    skin.Adapters.ApplyAll()
    skin.Registry.RefreshAll()
    skin.Registry.NotifyListeners("theme", "reset")
    return true
end
P.ResetSkinPage = function()
    local skin = Engine()
    if not skin or P.Combat() then return false end
    if not ResetSkinProfile(skin) then return false end
    if Suite.Skin then return Suite.Skin.SetEnabled(true) end
    return true
end

local function BuildMaintenance(ctx, b, skin)
    Section(ctx, b, "advanced", "Maintenance",
        "Refresh newly opened Blizzard windows. Use Reset page in the menu toolbar to restore this skin profile.",
        {}, false, function(body, y, width)
            P.Button(ctx, body, "Refresh Blizzard skins", 16, y, width, function()
                if skin.Adapters.ApplyAll then skin.Adapters.ApplyAll() end
            end, nil, P.Meta(PAGE, "skin", "maintenance.refresh", "action", "suite_skin_advanced"))
            return y - 40
        end)
end

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    local skin = Engine()
    if not skin then
        Section(ctx, b, "frame_basic", "Frame Basics",
            P.Combat() and "Open Skinning outside combat to load its settings." or "The Suite skin engine is unavailable.",
            {}, true)
        return
    end
    -- FixedPreviewSection must own the first builder slot so its reserved
    -- header space contains the preview instead of leaving a blank gap.
    Preview(ctx, b, skin)
    BuildFrameBasics(ctx, b, skin)
    BuildLook(ctx, b, skin)
    BuildMicroBar(ctx, b, skin)
    BuildHUD(ctx, b, skin)
    BuildMaterial(ctx, b, skin)
    BuildShape(ctx, b, skin)
    BuildColors(ctx, b, skin)
    BuildFonts(ctx, b, skin)
    BuildIcons(ctx, b, skin)
    BuildWindowControls(ctx, b, skin)
    BuildWindows(ctx, b, skin)
    BuildCoverage(ctx, b, skin)
    BuildCharacter(ctx, b, skin)
    BuildMaintenance(ctx, b, skin)
end

P.RegisterPage({ key = PAGE, label = "Skinning", title = "Skinning", build = Build, icon = { 4, 1 },
    aliases = { "suite_skin", "mapkoskin", "skinning" } })
