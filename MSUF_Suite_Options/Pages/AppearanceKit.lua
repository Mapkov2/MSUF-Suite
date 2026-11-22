local _, P = ...
local Suite, M, W, Tr, HM = P.Suite, P.M, P.W, P.Tr, P.HM
local PAGE = "suite_skin"
local SearchRow, Button = P.SkinSearchRow, P.SkinSearchButton

-- The toolkit Appearance.lua builds the Skinning page with: the on-demand
-- engine, history-wrapped skin writes, row metadata and dropdown values, the
-- section accordion and its reset to the factory profile.
local Kit = {}
P.SkinPageKit = Kit

local coldSections
function Kit.ColdSections()
    coldSections = coldSections or {
        { "basic", "Choose a look" }, { "material", "Glass and surfaces" }, { "shape", "Corners and hover" }, { "fonts", "Fonts" },
        { "icons", "Window buttons and icon borders" }, { "window_controls", "Window position, size and minimize" },
        { "windows", "Blizzard windows" }, { "coverage", "Window categories" },
    }
    return coldSections
end

function Kit.RefreshButton(ctx, header, skin)
    local button = Button(ctx, header, "Refresh Blizzard skins", 20, 0, 226, function()
        skin.Adapters.ApplyAll()
        skin.Typography.ApplyConfigured()
        skin.Registry.RefreshAll()
        if ctx.skinPreview then ctx.skinPreview.Paint() end
    end, function() return not P.Combat() end, P.Meta(PAGE, "skin", "maintenance.refresh", "action"), { height = 21 })
    if button then
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", header, "TOPRIGHT", -16, -5)
    end
end

-- The skin engine loads on demand (never in combat) the first time this page
-- is built.
local function LoadedEngine()
    local skin = _G.MapkoSkin
    if skin and skin.addonName == "MSUF_Suite_Skin" and skin.DB and skin.Theme then return skin end
end

local function Engine()
    local skin = LoadedEngine()
    if not skin and not P.Combat() then
        Suite.Skin.EnsureEngine()
        return LoadedEngine()
    end
    return skin
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

local tooltipSections = { tooltips = true, tooltip_builder = true, tooltip_layout = true, unit_tooltips = true }
local function PageForSection(section)
    return tooltipSections[section] and "suite_tooltips" or PAGE
end

local function Meta(key, section)
    local page = PageForSection(section)
    local meta = P.Meta(page, "skin", key, "setting", "suite_skin_" .. section)
    meta.pageKey = page
    return meta
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
    continuous = "Continuous", line = "Line",
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

-- The Skinning values a collapsed section shows, most important first.
P.RegisterSummary("skin", "theme.look theme.gradient geometry.family geometry.controlShape"
    .. " icons.windowActions.style theme.iconBorderStyle font.enabled font.face icons.microMenu.preset"
    .. " icons.microMenu.scale")

local function Row(kind, label, key, section, get, set, values, min, max, step)
    local row = Meta(key, section)
    row.summary = P.SummaryPriority("skin", key)
    row.searchLabel = label
    row.id, row.kind, row.label, row.get, row.set = key, kind, Tr(label), get, set
    if kind == "dropdown" then
        row.values = values
    elseif kind == "slider" then
        row.min, row.max, row.step = min, max, P.SliderStep(min, max, nil, step)
        row.roundStep = row.step >= 1
    end
    return row
end

function Kit.AddWindowAnimationRow(shape, skin)
    local label, key = "Window animations", "theme.windowAnimations"
    local row = Row("dropdown", label, key, "shape", skin.Theme.GetWindowAnimationMode,
        function(value) Change(skin, label, key,
            function() return skin.Theme.SetAppearance("windowAnimations", value) end) end,
        Values(skin.WindowAnimationModes, { subtle = "Subtle", extended = "Extended" }))
    row.tooltip = Tr("Subtle fades supported windows in. Extended uses a longer fade.")
    row.unavailable = function()
        if skin.DB.theme.reduceMotion == true then return Tr("Disabled while Reduced motion is on.") end
    end
    shape[#shape + 1] = row
end

function Kit.AddScrollRows(shape, skin)
    local modes = {
        { value = "native", text = Tr("Default") },
        { value = "smooth", text = Tr("Smooth scrolling") },
        { value = "adaptive", text = Tr("Adaptive") },
    }
    shape[#shape + 1] = Row("dropdown", "Scroll behavior", "theme.smoothScrolling", "shape",
        skin.Theme.GetScrollBehavior,
        function(value) Change(skin, "Scroll behavior", "theme.smoothScrolling",
            function() return skin.Theme.SetScrollBehavior(value) end) end, modes)
    shape[#shape + 1] = Row("toggle", "Bounce at list edges", "theme.scrollEdgeBounce", "shape",
        function() return skin.DB.theme.scrollEdgeBounce ~= false end,
        function(value) Change(skin, "Bounce at list edges", "theme.scrollEdgeBounce",
            function() return skin.Theme.SetAppearance("scrollEdgeBounce", value) end) end)
    shape[#shape].unavailable = function()
        if skin.Theme.GetScrollBehavior() ~= "adaptive" then return Tr("Requires adaptive scrolling.") end
    end
end

local function SkinDefault(defaults, id)
    if id == "theme.menuAnimations" or id == "theme.dropdownDimming"
        or id == "theme.windowFocusDimming" or id == "theme.smoothScrolling" or id == "theme.scrollEdgeBounce" then return true end
    if id == "theme.reduceMotion" then return false end
    if id == "suiteEnabled" then return true end
    if id == "enabled.windows" then return defaults.blizzardWindowsEnabled ~= false end
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
                if value ~= nil or row.id == "theme.windowAnimations" then
                    changes[#changes + 1] = { row = row, value = value }
                end
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
        elseif id == "fonts" then
            -- The font choice also lives in followMSUF and the Shared Media
            -- pick, which no row writes: the font owner sets the factory choice.
            if not skin.Typography.SetSelection(skin.Typography.SelectionOf(defaults.typography)) then
                return false
            end
        end
        for _, item in ipairs(changes) do
            local path = item.row.id
            if path == "suiteEnabled" then
                Suite.Skin.SetEnabled(item.value == true)
            elseif path == "enabled.windows" then
                skin.Adapters.SetBlizzardWindowsEnabled(item.value)
            else
                if path == "theme.smoothScrolling" then skin.DB.theme.adaptiveScrolling = nil end
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
        if id == "addon_skins" then
            skin.DB.addonSkins.discovered, skin.DB.addonSkins.looks = {}, {}
        end
        if id == "material" or id == "shape" or id == "icons" then
            skin.DB.theme.look = "custom"
        end
        skin.Typography.ApplyConfigured()
        skin.Adapters.ApplyAll()
        skin.Registry.RefreshAll()
        skin.Registry.NotifyListeners(id == "addon_skins" and "addonSkins" or "theme", "section-reset")
        return true
    end)
end

-- A row with `unavailable() -> reason | nil` stays visible but inert while it
-- answers a reason, and says that reason on hover.
local function GateRows(ctx, grid, rows)
    for _, row in ipairs(rows) do
        local widget, unavailable = row.unavailable and grid.controls[row.id], row.unavailable
        if widget then
            if W.SetControlDisabledReason then
                W.SetControlDisabledReason(widget, function()
                    local reason = unavailable()
                    return reason and Tr(reason)
                end)
            end
            M.TrackRefresh(ctx, function() W.SetControlEnabled(widget, unavailable() == nil) end)
        end
    end
end

function Kit.SettingsGrid(ctx, body, visibleRows, y, width)
    local grid = W.SettingsRows(ctx, body, {
        x = 16, y = y, width = width, columns = width >= 520 and 2 or 1, rows = visibleRows,
    })
    GateRows(ctx, grid, visibleRows)
    local entries = {}
    for _, row in ipairs(visibleRows) do
        local widget = grid.controls[row.id]
        if widget and row.outlineOverview then
            Suite.HostBridge.AttachOutlineOverview(M, widget, function() return row.outlineOverview end)
        end
        if widget and row.tooltip and M.AddTooltip then
            M.AddTooltip(widget, row.label, row.tooltip, { hook = true,
                enabled = function() return not row.unavailable or row.unavailable() == nil end })
        end
        entries[#entries + 1] = { widget = widget, meta = row,
            rule = { key = row.id, label = row.searchLabel }, label = row.label }
    end
    return grid.bottomY, entries
end

-- One accordion: help, a settings grid of the non-color rows, an optional
-- `extra(body, y, width) -> y` builder, and the color shortcut. A lazy host
-- builds them when the accordion first opens (P.LazySection); its summary
-- and "..." are in the header at once.
local function Section(ctx, b, id, title, help, rows, open, extra, contextRows, route, reset)
    local sectionId = route and route.section or "suite_skin_" .. id
    if ctx.searchRows then
        local page = route and route.page or PageForSection(id)
        SearchRow(ctx, { kind = "section", label = Tr(title), searchLabel = title, pageKey = page }, sectionId, Tr(title), Tr(help))
        for _, row in ipairs(rows) do SearchRow(ctx, row, sectionId, Tr(title), Tr(help)) end
        for _, row in ipairs(contextRows or {}) do SearchRow(ctx, row, sectionId, Tr(title), Tr(help)) end
        if extra then extra(nil, 0, 720) end
        return
    end
    local visibleRows = {}
    for _, row in ipairs(rows) do
        if row.kind ~= "color" then visibleRows[#visibleRows + 1] = row end
    end
    local function Content(body)
        if route then Engine() end
        local width = math.max(240, (HM.GetSectionWidth(body) or b.width or 720) - 32)
        local y = -18
        if help then
            local hint = P.Description(body, help, 16, y, width, title)
            y = y - math.max(14, math.ceil(hint:GetStringHeight() or 14)) - 12
        end
        if #visibleRows > 0 then
            local entries
            y, entries = Kit.SettingsGrid(ctx, body, visibleRows, y, width)
            if route then P.HUDMenu.Prepare(body, entries)
            else P.MenuWorkspace.Prepare(body, entries) end
        end
        if extra then y = extra(body, y, width) or y end
        P.AttachRowsSummary(ctx, body, visibleRows)
        local getEngine = tooltipSections[id] and Suite.TooltipAppearance.Engine or nil
        P.AttachSkinColors(body, title, contextRows or rows, getEngine)
        return y
    end
    return P.LazySection(b, sectionId, Tr(title), open, {
        content = Content,
        shell = id ~= "advanced" and function(body)
            P.AttachSectionReset(ctx, body, title, function()
                if reset then return reset() end
                return ResetSkinSection(Engine(), id, rows, contextRows)
            end)
        end or nil,
        summary = function(body) P.AttachRowsSummary(ctx, body, visibleRows) end,
        finish = function(body, y) P.FinishBody(b, body, y) end,
    })
end

local function SkinColorRow(skin, key, label)
    local row = Meta("color." .. key, "basic")
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

Kit.Engine, Kit.Change, Kit.Meta, Kit.Values = Engine, Change, Meta, Values
Kit.Row, Kit.Section, Kit.ResetSkinSection = Row, Section, ResetSkinSection
Kit.SkinColorRow, Kit.ConfigRow = SkinColorRow, ConfigRow

local CHARACTER_TOGGLES = {
    { "Character details", "characterDetails", "enabled", "CharacterDetails" },
    { "Expanded details", "characterDetails", "expanded", "CharacterDetails" },
    { "Character quality of life style", "characterDetails", "styleEQoL", "CharacterDetails" },
    { "Inline gear", "characterDetails", "inlineGear", "CharacterDetails" },
    { "Wide layout", "characterDetails", "wideLayout", "CharacterDetails" },
    { "Character stats", "characterStats", "enabled", "CharacterStats" },
    { "Diminishing returns", "characterStats", "diminishingReturns", "CharacterStats" },
}

local CHARACTER_HELP = "Choose the detailed character view and its extra information. Changing the view reloads the UI."
local function RetailCharacterOption()
    return "This feature is available only in Retail"
end

function Kit.BuildCharacter(ctx, b)
    if not Suite.Client.AddOnEnabled("MSUF_Suite_Skin") then return end
    local route = { page = "suite_hud", section = "suite_hud_characterPanel_equipment" }
    local character = {
        Row("dropdown", "Character view", "character.view", "character",
            function()
                local engine = LoadedEngine()
                return engine and engine.DB.characterDetails.view or "modern"
            end,
            function(value)
                local skin = Engine()
                Change(skin, "Character view", "character.view", function() return skin.CharacterDetails.SetView(value) end)
            end,
            Values({ "modern", "list", "classic" })),
    }
    local retail = Suite.Client.modernEquipment == true
    local function Available()
        if not retail and not Suite.Client.isForever then return RetailCharacterOption() end
        if not LoadedEngine() then return "The Suite skin engine is unavailable." end
    end
    local help = Suite.Client.isForever
        and "Choose the Suite Character Panel layout. Extra details apply to Blizzard's character and inspect windows."
        or CHARACTER_HELP
    character[1].unavailable = Available
    for _, spec in ipairs(CHARACTER_TOGGLES) do
        local label, group, key, api = spec[1], spec[2], spec[3], spec[4]
        local row = Row("toggle", label, group .. "." .. key, "character",
            function()
                local engine = LoadedEngine()
                return engine and engine.DB[group][key]
            end,
            function(value)
                local skin = Engine()
                Change(skin, label, group .. "." .. key, function() return skin[api].SetOption(key, value) end)
            end)
        row.unavailable = not retail and (key == "wideLayout" or api == "CharacterStats") and RetailCharacterOption or Available
        character[#character + 1] = row
    end
    for _, row in ipairs(character) do
        local identity = P.Meta(route.page, "skin", row.id, "setting", route.section)
        for key, value in pairs(identity) do row[key] = value end
        row.pageKey = route.page
    end
    Section(ctx, b, "character", "Character and equipment", help, character, false, nil, nil, route)
end

function Kit.ResetCharacter()
    local skin = LoadedEngine()
    if not skin then return end
    local defaults = skin.Database.CreateFactoryProfile()
    skin.DB.characterDetails, skin.DB.characterStats = defaults.characterDetails, defaults.characterStats
    skin.Adapters.ApplyAll()
    skin.Registry.NotifyListeners("characterDetails", "reset")
end
