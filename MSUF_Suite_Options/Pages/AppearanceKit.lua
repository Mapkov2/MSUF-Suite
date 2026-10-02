local _, P = ...
local Suite, W, Tr = P.Suite, P.W, P.Tr
local PAGE = "suite_skin"
local SearchRow = P.SkinSearchRow

-- The toolkit Appearance.lua builds the Skinning page with: the on-demand
-- engine, history-wrapped skin writes, row metadata and dropdown values, the
-- section accordion and its reset to the factory profile.
local Kit = {}
P.SkinPageKit = Kit

-- The skin engine loads on demand (never in combat) the first time this page
-- is built.
local function Engine()
    local skin = _G.MapkoSkin
    if not (skin and skin.addonName == "MSUF_Suite_Skin") and not P.Combat() then
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
P.RegisterSummary("skin", "theme.look theme.shellOpacity theme.panelOpacity geometry.family geometry.controlShape"
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
                Suite.Skin.SetEnabled(item.value == true)
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
        if id == "material" or id == "shape" or id == "icons" then
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
    if ctx.searchRows then
        local sectionId = "suite_skin_" .. id
        SearchRow(ctx, { kind = "section", label = Tr(title), searchLabel = title }, sectionId, Tr(title), Tr(help))
        for _, row in ipairs(rows) do SearchRow(ctx, row, sectionId, Tr(title), Tr(help)) end
        for _, row in ipairs(contextRows or {}) do SearchRow(ctx, row, sectionId, Tr(title), Tr(help)) end
        if extra then extra(nil, 0, 720) end
        return
    end
    local body = b:CollapsibleSection("suite_skin_" .. id, Tr(title), 120, open)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = -18
    if help then
        local hint = P.Description(body, help, 16, y, width, title)
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
    P.AttachRowsSummary(ctx, body, visibleRows)
    P.AttachSkinColors(body, title, contextRows or rows)
    if id ~= "advanced" then
        P.AttachSectionReset(ctx, body, title, function()
            return ResetSkinSection(Engine(), id, rows, contextRows)
        end)
    end
    P.FinishBody(b, body, y)
    return body
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
