local _, P = ...
local UI = {}
P.NameplatesAdvancedAuras = UI
local Model, Style, DotColors = P.Suite.NameplateAuraDisplay, P.Suite.NameplateStyle, P.NameplatesAuraUI
local Tr = P.Tr
local PAGE, ID = "suite_nameplates", "nameplates"
local SECTION = PAGE .. "_auraWorkspace"
local DOT_COLOR_KEYS = { "auraColorsEnabled", "auraColorsNoneEnabled", "auraColorsIndividual", "auraColorsAll", "auraColorsNone" }
local previews = setmetatable({}, { __mode = "k" })
local EMPTY = {}
local OUTLINE = { "", "OUTLINE", "THICKOUTLINE" }
local LIST_LABELS = {
    custom = { add = "Add allowed aura", remove = "Remove allowed aura",
        empty = "No spells tracked. Add up to 40 exact SpellIDs." },
    dots = { add = "Add custom tracked aura", remove = "Remove custom tracked aura",
        empty = "No DoT selected. Choose one above or add a custom Spell ID." },
}
local view = { scope = "enemy", plate = "enemy", container = "buff", tools = {} }
local function Container() return Model.Container(view.container) end
local function Tool(container) return view.tools[container.key] or Model.Tools[container.kind][1] end

local function Containers()
    local list = {}
    for _, row in ipairs(Model.NativeRows) do list[#list + 1] = row end
    for _, row in ipairs(Model.Containers) do list[#list + 1] = row end
    return list
end

local selectView, revealWorkspace

function UI.SelectSide(side, plate)
    plate = plate or side
    if plate == view.plate or not Model.Scope(side) then return end
    view.scope, view.plate = side, plate
    if side ~= "enemy" then view.dotColors = false end
    if selectView then selectView() end
end

local function WorkspaceKeys()
    local keys, seen = { "auraDisplayEnabled" }, { auraDisplayEnabled = true }
    for _, list in ipairs({ Model.NativeShared, Model.AppearanceKeys, DOT_COLOR_KEYS }) do
        for _, key in ipairs(list) do keys[#keys + 1], seen[key] = key, true end
    end
    for _, scope in ipairs(Model.Scopes) do
        for _, container in ipairs(Containers()) do
            for _, tool in ipairs(Model.Tools[container.kind]) do
                for _, key in ipairs(Model.ToolKeys(scope, container, tool)) do
                    if not seen[key] then keys[#keys + 1], seen[key] = key, true end
                end
            end
        end
    end
    return keys
end

-- Every aura setting is reached from this one workspace.
function UI.Append(sections)
    sections[#sections + 1] = { key = "auraWorkspace", area = "auras", title = "Auras", keys = WorkspaceKeys(),
        colors = Model.ColorKeys, build = UI.Build, prepare = UI.PrepareSearch }
end

function UI.Lookup(query)
    if type(query) ~= "string" or query == "" or #query > 128 then return end
    local id = tonumber(query) or C_Spell.GetSpellIDForSpellIdentifier(query)
    if not P.Suite.Public(id) or type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= math.floor(id) then return end
    local name, icon = C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
    if not P.Suite.Public(name) or type(name) ~= "string" then return end
    return { value = id, text = string.format(Tr("%s (Aura %d)"), name, id), icon = P.Suite.Public(icon) and icon or 134400 }
end

local function SpellValues(ids)
    local values = {}
    for _, id in ipairs(ids) do
        values[#values + 1] = UI.Lookup(tostring(id)) or {
            value = id, text = string.format(Tr("Check the ID for unknown aura %d"), id), icon = 134400 }
    end
    return values
end

local function Suggestions(lookup)
    local values, seen = {}, {}
    if lookup and lookup.value then values[1], seen[lookup.value] = lookup, true end
    -- The same curated/native DoT suggestions as the aura-color picker.
    for _, row in ipairs(P.Suite.NameplateAuraColors.Suggestions()) do
        if not seen[row.id] then
            local value = UI.Lookup(tostring(row.id))
            if value then values[#values + 1], seen[row.id] = value, true end
        end
    end
    return values
end

-- A list edit writes this client's list only (Model.ListKey). Adding a custom
-- DoT also selects the custom list as the container's source.
local function CanEditList(scope)
    if P.Combat() or not P.Get(ID, "enabled") then return false end
    return P.Get(ID, "look") ~= 2 and P.Get(ID, scope.key)
end

local function ChangeList(scope, container, id, action)
    if not CanEditList(scope) then return end
    local key = Model.ListKey(scope, container)
    local ids, set = Model.IDs(P.Get(ID, key))
    if action == "add" then
        if set[id] or #ids >= Model.MAX_ICONS then return end
        ids[#ids + 1] = id
    else
        for index, spell in ipairs(ids) do
            if spell == id then
                if action == "remove" then
                    table.remove(ids, index)
                else
                    local dest = index + (action == "up" and -1 or 1)
                    if not ids[dest] then return end
                    ids[index], ids[dest] = ids[dest], ids[index]
                end
                break
            end
        end
    end
    local value = table.concat(ids, ",")
    local source = Model.Prefix(scope, container) .. "Source"
    if action == "add" and P.catalog[ID].rules[source] then return P.SetMany(ID, { [key] = value, [source] = 2 }) end
    return P.Set(ID, key, value)
end

local function ListRow(scope, container, label, action, lookup)
    local key = Model.ListKey(scope, container)
    local row = P.Meta(PAGE, ID, "action." .. key .. action, "action", SECTION)
    row.id, row.label, row.kind = key .. action, Tr(label), "dropdown"
    row.get = function() return nil end
    row.values = function()
        if action ~= "add" then return SpellValues(Model.IDs(P.Get(ID, key))) end
        return Suggestions(lookup.match)
    end
    row.set = function(id)
        if P.Suite.Public(id) and type(id) == "number" and #Model.IDs(tostring(id), 1) == 1 then
            ChangeList(scope, container, id, action)
        end
    end
    return row
end

local function ListSummary(scope, container)
    local ids = Model.IDs(P.Get(ID, Model.ListKey(scope, container)))
    if #ids == 0 then return Tr(LIST_LABELS[container.kind].empty) end
    local names = {}
    for index, value in ipairs(SpellValues(ids)) do names[index] = value.text end
    return table.concat(names, ", ")
end

-- The aura list of one container on this client: find by name or ID, add and
-- remove through the host's dropdown rows, and the list in stored order.
local function SpellList(ctx, panel, y, width, scope, container)
    local key, labels, lookup, query = Model.ListKey(scope, container), LIST_LABELS[container.kind], {}, ""
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y - 60)
    icon:SetTexture(134400)
    local found = P.Text(panel, "", 42, y - 63, width - 28)
    local function Lookup(value)
        query = value or ""
        lookup.match = UI.Lookup(query)
        icon:SetTexture(lookup.match and lookup.match.icon or 134400)
        P.SetTranslatedText(found, lookup.match and lookup.match.text or Tr("Enter a spell name or valid aura ID."))
        P.Refresh()
    end
    local input = P.M.BindTextInputAt(ctx, panel, Tr("Find aura by name or ID"), 16, y, width,
        function() return query end, Lookup, false, P.Meta(PAGE, ID, "action." .. key .. "Lookup", "action", SECTION))
    input:SetOnValueCommitted(function(value)
        Lookup(value)
        if lookup.match then ChangeList(scope, container, lookup.match.value, "add") end
    end)
    input:SetMaxLetters(128)
    P.SetTranslatedText(found, Tr("Enter a spell name or valid aura ID."))
    local rows = {
        ListRow(scope, container, labels.add, "add", lookup), ListRow(scope, container, labels.remove, "remove", lookup),
        ListRow(scope, container, "Move aura up", "up", lookup), ListRow(scope, container, "Move aura down", "down", lookup),
    }
    local grid = P.W.SettingsRows(ctx, panel, { x = 16, y = y - 92, width = width, columns = 2, rows = rows })
    local summary = P.Text(panel, "", 16, grid.bottomY - 8, width)
    local shown
    P.M.TrackRefresh(ctx, function()
        local enabled = CanEditList(scope)
        for _, row in ipairs(rows) do grid.controls[row.id]:SetEnabled(enabled) end
        local stored = P.Get(ID, key)
        if stored ~= shown then
            shown = stored
            P.SetTranslatedText(summary, ListSummary(scope, container))
        end
    end)
    return grid.bottomY - 64
end

local function Short(rule)
    if not rule.short then return rule end
    return setmetatable({ label = rule.short }, { __index = rule })
end

local function Grid(ctx, panel, keys, y, width, columns)
    local rules, catalog = {}, P.catalog[ID].rules
    for _, key in ipairs(keys) do
        local rule = catalog[key]
        if rule and not key:match("[XY]$") and P.catalog[ID].controlAvailable(rule) then
            rules[#rules + 1] = Short(rule)
        end
    end
    if #rules == 0 then return y end
    return (P.RuleGrid(ctx, panel, PAGE, ID, rules, y, width, nil, SECTION, columns))
end

local function Heading(panel, text, y, width)
    local heading = P.Text(panel, text, 16, y, width, nil, "section")
    heading:SetJustifyH("CENTER")
    return y - 28
end

local function Card(parent)
    local theme = P.T
    return theme.Panel(parent, nil, theme.colors.panel2, theme.colors.borderSoft)
end

local STYLE_PARTS = {
    { title = "Basics", keys = { "Zoom", "Tooltip", "Clickthrough", "Alpha", "Padding", "Dispel", "IconSkin" } },
    { title = "Stack Count", keys = { "StackText", "StackSize", "StackPoint" } },
    { title = "Cooldown Text", keys = { "TimeText", "Swipe", "TimeSize", "TimePoint", "TimeDecimals", "SwipeDirection" } },
    { title = "Duration bar", keys = { "DurationBar", "DurationBarHeight", "DurationBarDisplay", "DurationBarPosition",
        "DurationBarDirection", "DurationBarColor" } },
    { title = "Pandemic", keys = { "Pandemic" } },
}

local function AddStyle(parts, prefix)
    for _, section in ipairs(STYLE_PARTS) do
        local keys = {}
        for _, field in ipairs(section.keys) do keys[#keys + 1] = prefix .. field end
        parts[#parts + 1] = { key = prefix .. section.title, build = function(ctx, panel, width)
            local y = Grid(ctx, panel, keys, Heading(panel, section.title, -12, width), width, 2)
            if section.title == "Duration bar" then
                local rule = P.catalog[ID].rules[prefix .. "DurationBarColor"]
                P.AttachRuleColors(panel, section.title, ID, { rule })
            end
            return y
        end }
    end
end

local function BuildTool(ctx, panel, width, scope, container, tool)
    local title = Tr(container.label) .. " · " .. Tr(Model.ToolLabels[tool])
    local keys, y = Model.ToolKeys(scope, container, tool, true), Heading(panel, title, -12, width)
    local prefix = Model.Prefix(scope, container)
    if tool == "layout" then
        local numbers = {}
        for i = 3, #keys do numbers[#numbers + 1] = keys[i] end
        y = Grid(ctx, panel, { prefix .. "Anchor", prefix .. "Growth" }, y, width, 2)
        return Grid(ctx, panel, numbers, y, width, width >= 620 and 4 or 2)
    elseif tool == "setup" and container.kind == "dots" then
        local setup = {}
        for _, key in ipairs(keys) do if key ~= prefix .. "Source" then setup[#setup + 1] = key end end
        return Grid(ctx, panel, setup, y, width)
    elseif tool == "whitelist" then
        if container.kind == "dots" and scope.key == "enemy" then
            y = Grid(ctx, panel, { prefix .. "Source", "auraSunder" }, y, width, 2)
        end
        return SpellList(ctx, panel, y - 6, width, scope, container)
    end
    return Grid(ctx, panel, keys, y, width)
end

local function Unsupported(container)
    return view.plate == "friendlyNpc" and container.kind == "native" and container.key ~= "debuff"
end

local function VisibilityKeys(scope, container)
    if view.plate == "friendlyNpc" then return { "friendlyNpcDebuffs" } end
    if view.plate == "neutral" then return { "enemyNpc" .. container.native } end
    return Model.VisibilityKeys(scope, container)
end

local function NativeSwitch(key, column)
    return { key = "visible:" .. key, column = column, build = function(ctx, panel, width)
        local rule = P.catalog[ID].rules[key]
        local row = P.RuleRow(PAGE, ID, rule, nil, SECTION)
        local button = P.M.BindSwitchAt(ctx, panel, row.label, 16, 0, width / 2, row.get, row.set, row)
        P.GateControls(ctx, ID, { { widget = button, rule = rule, checked = row.get } })
        P.HM.SetSearchTargetPrepare(button, function() UI.PrepareSearch(key) end)
        return -28
    end }
end

local function NativePart(scope, container, tool)
    return function(ctx, panel, width)
        local title = Tr(container.label) .. " · " .. Tr(Model.ToolLabels[tool])
        local y = Heading(panel, title, -12, width)
        if tool == "layout" then
            y = y - (width >= 560 and 32 or 60)
            local keys = Model.ToolKeys(scope, container, tool, true)
            y = Grid(ctx, panel, keys, y, width, width >= 620 and 4 or 2)
            local note = P.Text(panel, "The game keeps the anchor, growth, spacing and icon limit for this row.", 16, y - 4, width)
            return y - 14 - math.ceil(note:GetStringHeight() or 14)
        end
        y = Grid(ctx, panel, Model.ToolKeys(scope, container, tool, true), y, width, 2)
        local message = container.key == "control"
        local note = P.Text(panel, message and "The game selects, filters and orders the auras in this row."
            or "A visible tracked slot can hide its matching icon here. Restricted auras stay visible.", 16, y - 4, width)
        return y - 14 - math.ceil(note:GetStringHeight() or 14)
    end
end

local function Parts(scope, container, tool)
    if Unsupported(container) then
        return { { key = "unsupported:" .. container.key, build = function(_, panel, width)
            local note = P.Description(panel, "This aura row is unavailable for friendly NPCs.", 16, -8, width, Tr(container.label))
            return -24 - math.max(14, math.ceil(note:GetStringHeight() or 14))
        end } }
    end
    local parts, prefix = {}, Model.Prefix(scope, container)
    if container.kind == "native" then
        parts[#parts + 1] = { key = prefix .. tool, build = NativePart(scope, container, tool) }
        if tool == "layout" then
            for column, key in ipairs(VisibilityKeys(scope, container)) do parts[#parts + 1] = NativeSwitch(key, column) end
        end
    elseif tool == "style" then
        AddStyle(parts, prefix)
    else
        if tool == "setup" then
            parts[1] = { key = "tracked:enabled", build = function(ctx, panel, width)
                return Grid(ctx, panel, { "auraDisplayEnabled" }, -6, width, 2)
            end }
        end
        parts[#parts + 1] = { key = prefix .. tool, build = function(ctx, panel, width)
            return BuildTool(ctx, panel, width, scope, container, tool)
        end }
    end
    return parts
end

local function Values(list, key, label)
    local values = {}
    for _, item in ipairs(list) do values[#values + 1] = { value = key and item[key] or item, text = label and label(item) or item.label } end
    return values
end

local function Kind()
    return Model.Container(view.container).kind
end

local function ToolValues(kind)
    return Values(Model.Tools[kind], nil, function(tool) return Model.ToolLabels[tool] end)
end

local function SetBarShown(bar, shown)
    bar:SetShown(shown)
    bar.label:SetShown(shown)
    for _, button in ipairs(bar.buttons) do button:SetShown(shown) end
end

-- MSUF's Container and Edit bars (7.0 hosts). select: shows the view.
local function Bars(ctx, body, width, select)
    local W, top = P.W, -28
    local function Bar(label, values, centerY, get, set)
        local bar = W.ScopeOverrideBar(ctx, body, { values = values, width = width + 32, startX = 88, maxRight = width + 12,
            label = label, labelWidth = 72,
            centerY = centerY, getValue = get, setValue = function(value)
                set(value)
                select()
            end })
        local metrics = bar:GetLayoutMetrics()
        return bar, metrics and metrics.bottomY or centerY - 14
    end
    local _, bottom = Bar("Container:", Values(Containers(), "key"), top, function() return view.container end,
        function(value) view.container, view.appearance, view.dotColors = value, false, false end)
    top = math.min(top - 34, bottom - 22)
    local tools, lowest = {}, top
    for _, kind in ipairs({ "native", "custom" }) do
        tools[kind], bottom = Bar("Edit:", ToolValues(kind), top, function() return Tool(Container()) end,
            function(value) view.tools[view.container], view.appearance, view.dotColors = value, false, false end)
        lowest = math.min(lowest, bottom)
    end
    return lowest - 2, function()
        for kind, bar in pairs(tools) do SetBarShown(bar, (kind == "native") == (Kind() == "native") and not Unsupported(Container())) end
    end
end

-- Hosts without that bar get the same three choices as dropdown rows.
local function Dropdowns(ctx, body, width, select)
    local function Row(key, label, values, get, set)
        local row = P.Meta(PAGE, ID, "action.auraWorkspace." .. key, "action", SECTION)
        row.id, row.label, row.kind, row.values, row.get = "auraWorkspace" .. key, Tr(label), "dropdown", values, get
        row.set = function(value)
            set(value)
            select()
        end
        return row
    end
    local rows = {
        Row("Container", "Container", function() return Values(Containers(), "key") end,
            function() return view.container end, function(value) view.container, view.appearance, view.dotColors = value, false, false end),
        Row("Tool", "Edit", function() return ToolValues(Kind()) end, function() return Tool(Container()) end,
            function(value) view.tools[view.container], view.appearance, view.dotColors = value, false, false end),
    }
    local grid = P.W.SettingsRows(ctx, body, { x = 16, y = -18, width = width, columns = width >= 560 and 3 or 1, rows = rows })
    return grid.bottomY, function() end
end

local function Footer(ctx, body, width, y, select)
    P.Button(ctx, body, "Global Aura Appearance", 16, y - 4, 170, function()
        view.appearance, view.dotColors = not view.appearance, false
        select()
    end, nil, P.Meta(PAGE, ID, "action.auraWorkspace.appearance", "action", SECTION))
    if not DotColors then return y - 36 end
    local nextRow = width < 370
    P.Button(ctx, body, "DoT health colors", nextRow and 16 or 194, y - 4 - (nextRow and 36 or 0), 168, function()
        view.dotColors, view.appearance = not view.dotColors, false
        select()
    end, function() return view.scope == "enemy" end, P.Meta(PAGE, ID, "action.auraWorkspace.dotColors", "action", SECTION))
    return y - (nextRow and 72 or 36)
end

local function Appearance(ctx, panel, width)
    local y = Heading(panel, "Shared aura appearance", -12, width)
    y = Grid(ctx, panel, Model.NativeShared, y, width, 2)
    y = Heading(panel, "Tracked auras", y - 8, width)
    return Grid(ctx, panel, Model.AppearanceKeys, y, width, 2)
end

local function ContainerOf()
    return Model.Scope(view.scope), Model.Container(view.container)
end

local function ColorShortcut(body)
    local colors, catalog = {}, P.catalog[ID].rules
    for _, key in ipairs(Model.ColorKeys) do colors[#colors + 1] = catalog[key] end
    P.AttachRuleColors(body, Tr("Auras"), ID, colors, nil, nil, DotColors and function()
        return view.scope == "enemy" and DotColors.ColorTargets() or {}
    end, DotColors and P.Suite.NameplateAuraColors.LIMIT + 2)
end

local function Content(ctx, builder, body)
    local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local built = {}
    local header = Card(body)
    header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    header:SetWidth(width + 32)
    local top, showTools
    local select
    local function Part(part)
        if not built[part.key] and not P.Combat() then
            local frame = part.column and CreateFrame("Frame", nil, body) or Card(body)
            frame:SetSize(part.column and width / 2 or width + 32, 100)
            local height = -part.build(ctx, frame, width, function(bottom)
                frame:SetHeight(-bottom)
                local entry = built[part.key]
                if entry then
                    entry.height = -bottom
                    if view.dotColors then select() end
                end
            end)
            frame:SetHeight(height)
            built[part.key] = { frame = frame, height = height }
        end
        return built[part.key]
    end
    select = function(first)
        local scope, container = ContainerOf()
        local y, shown, cardY = top, {}, top
        local parts = view.dotColors and DotColors and { { key = "dotColors", build = DotColors.Build } }
            or view.appearance and { { key = "appearance", build = Appearance } }
            or Parts(scope, container, Tool(container))
        for _, part in ipairs(parts) do
            local entry = Part(part)
            if entry then
                entry.frame:ClearAllPoints()
                if part.column then
                    local index = part.column - 1
                    local columnX = width >= 560 and index * (width / 2) or 0
                    local rowY = width >= 560 and 0 or index * entry.height
                    entry.frame:SetFrameLevel(header:GetFrameLevel() + 2)
                    entry.frame:SetPoint("TOPLEFT", body, "TOPLEFT", columnX, cardY - 37 - rowY)
                else
                    entry.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
                    cardY, y = y, y - entry.height - 8
                end
                shown[entry] = true
            end
        end
        for _, entry in pairs(built) do entry.frame:SetShown(shown[entry] == true) end
        showTools()
        if not first then
            P.FinishBody(builder, body, y - 14)
            P.Refresh()
        end
        return y - 14
    end
    selectView = function() select() end
    if P.W.ScopeOverrideBar then
        top, showTools = Bars(ctx, header, width, selectView)
    else
        top, showTools = Dropdowns(ctx, header, width, selectView)
    end
    top = Footer(ctx, header, width, top - 8, selectView)
    header:SetHeight(-top + 4)
    top = top - 12
    ColorShortcut(body)
    return select(true)
end

-- Restore the original layout and the dragged position. The display
-- switches remain independent of a layout reset.
local function ResetView()
    if view.dotColors and DotColors then
        DotColors.ResetColors()
        return true
    end
    local scope, container = ContainerOf()
    local prefix = Model.Prefix(scope, container)
    local rules = P.SectionRules(ID, prefix)
    if view.appearance then
        local keys = {}
        for _, list in ipairs({ Model.NativeShared, Model.AppearanceKeys, Model.ColorKeys }) do
            for _, key in ipairs(list) do keys[#keys + 1] = key end
        end
        return P.ResetRules(ID, {}, nil, keys)
    end
    local offsets = container.kind == "native" and P.NameplateAuraPositionKeys(scope.key, { container.element })
    return P.ResetRules(ID, rules, nil, offsets or nil)
end

-- A search hit or a preview click on an aura setting opens its view.
local index
function UI.PrepareSearch(key)
    if not index then
        index = { friendlyNpcDebuffs = { "friendly", "debuff", "layout", "friendlyNpc" },
            auraDisplayEnabled = { "enemy", "custom1", "setup" } }
        for _, name in ipairs(DOT_COLOR_KEYS) do index[name] = { "enemy", "dots", "setup", nil, false, true } end
        for _, list in ipairs({ Model.NativeShared, Model.AppearanceKeys, Model.ColorKeys }) do
            for _, name in ipairs(list) do index[name] = { "enemy", "buff", "layout", nil, true } end
        end
        for _, scope in ipairs(Model.Scopes) do
            for _, container in ipairs(Containers()) do
                for _, tool in ipairs(Model.Tools[container.kind]) do
                    for _, name in ipairs(Model.ToolKeys(scope, container, tool)) do
                        index[name] = index[name] or { scope.key, container.key, tool }
                    end
                end
                if container.kind == "dots" and scope.key == "enemy" then
                    index[Model.Prefix(scope, container) .. "Source"] = { scope.key, container.key, "whitelist" }
                    index.auraSunder = { scope.key, container.key, "whitelist" }
                end
            end
        end
    end
    local target = index[key]
    if not target then return end
    local workspace = P.NameplatesWorkspace
    local scope, plate = target[1], target[4]
    if not plate and workspace and workspace.Side() == scope then
        plate = workspace.Kind()
        if plate == "neutral" and key:match("^enemyPlayer") then plate = "enemy" end
        if plate == "friendlyNpc" and (key:match("^friendlyPlayer") or target[2] ~= "debuff") then plate = "friendly" end
    end
    plate = plate or scope
    view.scope, view.plate, view.container = scope, plate, target[2]
    view.tools[view.container], view.appearance, view.dotColors = target[3], target[5] == true, target[6] == true
    if workspace and workspace.Kind() ~= plate then workspace.Open(plate) end
    if P.ShowNameplatesAuraSample and (key:match("^enemyNpc") or key:match("^enemyPlayer")) then P.ShowNameplatesAuraSample(key) end
    if revealWorkspace then revealWorkspace() end
end

function UI.Summary()
    local scope = Model.Scope(view.scope)
    if not P.Get(ID, "enabled") then return nil end
    local config = P.S.Config(ID)
    local group = view.plate == "friendlyNpc" and "friendlyNpc" or scope.key == "enemy" and "enemyNpc" or "friendlyPlayer"
    local buffs = Model.NativeShown(config, group, "Buffs")
    local debuffs = Model.NativeShown(config, group, "Debuffs")
    if view.plate == "enemy" then
        buffs = buffs or Model.NativeShown(config, "enemyPlayer", "Buffs")
        debuffs = debuffs or Model.NativeShown(config, "enemyPlayer", "Debuffs")
    end
    if buffs and debuffs then return Tr("Buffs and debuffs") end
    if buffs then return Tr("Buffs") end
    if debuffs then return Tr("Debuffs") end
    if Model.NativeShown(config, group, "Control") or view.plate == "enemy" and Model.NativeShown(config, "enemyPlayer", "Control") then
        return Tr("Control effects")
    end
end

function UI.Build(ctx, builder, spec)
    local pageEntry = P.M.cache and P.M.cache[PAGE]
    selectView, revealWorkspace = nil, nil
    return P.LazySection(builder, SECTION, Tr(spec.title), spec.open == true, {
        head = P.NameplatesSectionsLayout.Header(ctx, spec, SECTION),
        content = function(body) return Content(ctx, builder, body) end,
        shell = function(body)
            revealWorkspace = function()
                if P.M.cache and P.M.cache[PAGE] ~= pageEntry or P.Combat() then return end
                local entry = P.HM.GetSectionEntry(body)
                local reveal = entry and P.HM.GetSectionEnsureVisible(entry)
                if reveal then reveal() end
                if not selectView then P.EnsureSectionContent(body) end
                if selectView then selectView() end
            end
            P.AttachSectionReset(ctx, body, Tr(spec.title), ResetView)
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end

local function SampleIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    local swipe = frame:CreateTexture(nil, "OVERLAY")
    swipe:SetColorTexture(0, 0, 0, .4)
    swipe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    swipe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    local textHost = CreateFrame("Frame", nil, frame)
    textHost:SetAllPoints(frame)
    textHost:SetFrameLevel(frame:GetFrameLevel() + 1)
    return { frame = frame, icon = icon, swipe = swipe, border = Style.CreateBorder(frame),
        Time = textHost:CreateFontString(nil, "OVERLAY"), Stack = textHost:CreateFontString(nil, "OVERLAY") }
end

local function SampleText(part, plan, c, field, sample)
    local values, label, text = plan.values, part[field], c.text[field]
    P.StylePreviewFont(label, plan.font, text.size, OUTLINE[values.auraTextOutline])
    label:ClearAllPoints()
    label:SetPoint(text.point, part.frame, text.point, text.x, text.y)
    label:SetTextColor(P.RGB(values["aura" .. field .. "Color"]))
    label:SetText(sample)
    label:SetShown(values["aura" .. field .. "Text"] and c[field == "Time" and "timeText" or "stackText"])
end

local function PaintIcon(part, plan, c, index, row, missing)
    local values = plan.values
    part.frame:SetSize(c.width, c.height)
    local icon = C_Spell.GetSpellTexture(row.id)
    part.icon:SetTexture(P.Suite.Public(icon) and icon or 134400)
    part.icon:SetTexCoord(c.crop, 1 - c.crop, c.crop, 1 - c.crop)
    local look = c.iconSkin and plan.iconLook
    if look or part.skinned then
        part.skinned = P.Suite.HostBridge.PaintIconSkin(part.frame, look or nil, c.width, c.height, part.icon, true)
    end
    part.icon:SetDesaturated(missing)
    part.icon:SetAlpha(c.barOnly and not missing and 0 or 1)
    part.frame:SetAlpha(missing and c.missingAlpha / 100 or c.alpha)
    part.swipe:SetHeight(c.height * .35)
    part.swipe:SetAlpha(values.auraSwipeAlpha / 100)
    part.swipe:SetShown(not c.barOnly and values.auraSwipe and c.swipe and not missing)
    SampleText(part, plan, c, "Time", index == 1 and (c.timeDecimals > 2 and "2.4" or "7") or "12")
    SampleText(part, plan, c, "Stack", index == 1 and "3" or "2")
    if missing then
        part.Time:Hide()
        part.Stack:Hide()
    end
    local bar = part.durationBar
    if c.durationBar and not missing then
        bar = bar or part.frame:CreateTexture(nil, "OVERLAY")
        part.durationBar = bar
        local edge, y = c.durationBarTop and "TOPLEFT" or "BOTTOMLEFT", c.durationBarTop and -1 or 1
        bar:ClearAllPoints()
        bar:SetPoint(edge, part.frame, edge, 1, y)
        bar:SetSize((c.width - 2) * (c.durationBarElapsed and .35 or .65), c.durationBarHeight)
        bar:SetColorTexture(P.RGB(c.durationBarColor))
        bar:Show()
    elseif bar then
        bar:Hide()
    end
    local color
    if index == 1 and values.auraPandemicHighlight and c.pandemic then color = values.auraPandemicColor
    elseif index == 2 and values.auraDispelHighlight and c.dispel then color = "66aaff" end
    Style.PaintBorder(part.border, part.frame, color and not missing and values.auraHighlightSize or 0, color)
    part.frame:Show()
end

local function PaintIcons(record, parent, plan, c, exclusions, visible)
    local limit = c.fixed and c.count or math.min(c.max, 3)
    local count = 0
    for index, row in ipairs(c.rows) do
        local missing = c.fixed and index == limit and limit > 1
        if (not missing or c.missing) and not (exclusions and exclusions[row.id]) then
            count = count + 1
            local part = record.icons[count] or SampleIcon(parent)
            record.icons[count] = part
            PaintIcon(part, plan, c, count, row, missing)
            local x, y = Model.SlotOffset(c, c.fixed and index or count)
            part.frame:ClearAllPoints()
            part.frame:SetPoint(c.flowPoint, parent, c.flowPoint, x, y)
            if visible and not missing then visible[row.id] = true end
        end
        if count == limit then break end
    end
    for index = count + 1, #record.icons do record.icons[index].frame:Hide() end
end

local function PaintTextHandle(record, sample, plan, c, facts, previewText)
    local part = record.icons[1]
    if not part or not part.frame:IsShown() then return end
    local prefix = facts.sharedText and "aura" or c.prefix
    local text = c.text[previewText]
    if facts.sharedText then
        local key = prefix .. previewText
        text.point = P.Suite.AnchorPoints[plan.values[key .. "Point"]]
        text.x, text.y = plan.values[key .. "X"], plan.values[key .. "Y"]
    end
    SampleText(part, plan, c, previewText, previewText == "Time" and "7" or "3")
    local label = part[previewText]
    label:Show()
    local handles = record.textHandles or {}
    record.textHandles = handles
    local handle = handles[previewText]
    local key = prefix .. previewText
    if not handle then
        handle = CreateFrame("Button", nil, record.frame)
        handle:SetFrameLevel(part.frame:GetFrameLevel() + 3)
        handles[previewText] = handle
        local id = sample.prefix .. "." .. c.element .. previewText
        facts.editor:Bind(handle, id, Tr(previewText == "Time" and "Cooldown Text" or "Stack Count"), key .. "X", key .. "Y", c.prefix)
    else
        handle.keyX, handle.keyY = key .. "X", key .. "Y"
    end
    handle._npSettingKey = key .. "Size"
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", label, "CENTER", 0, 0)
    handle:SetSize(math.max(16, label:GetStringWidth()), math.max(16, text.size))
    handle:Show()
end

local function PaintContainer(record, sample, plan, c, facts, visible)
    local previewText = facts.element == c.element .. "Time" and "Time"
        or facts.element == c.element .. "Stack" and "Stack"
    local selected = previewText or facts.element == c.element
    local shown = (c.enabled or selected) and facts.show ~= false and (c.kind ~= "dots" or facts.target == true or selected)
    record.frame:SetShown(shown)
    for _, handle in pairs(record.textHandles or EMPTY) do handle:Hide() end
    if not shown then return end
    record.frame:ClearAllPoints()
    record.frame:SetPoint(c.point, sample.bar, c.relative, c.x, c.y)
    record.frame:SetSize(c.gridWidth, c.gridHeight)
    local exclusions = plan.exclusions[sample.prefix]
    local lane = not selected and visible and c.hideDuplicates and (c.helpful and visible.buff or visible.debuff)
    if selected and #c.rows == 0 then c.rows[1], c.count = { id = 172 }, 1 end
    PaintIcons(record, record.frame, plan, c, not selected and exclusions and exclusions[c.key], lane)
    if previewText and facts.editor then PaintTextHandle(record, sample, plan, c, facts, previewText) end
end

local function HidePreview(state)
    for _, record in pairs(state.containers) do record.frame:Hide() end
end

function UI.Preview(sample, config, facts)
    local state = previews[sample]
    local editing = facts and facts.element and not Model.NativeElement(facts.element)
    local on = (Model.Active(config) or editing) and config.look ~= 2 and config[sample.prefix]
    if not on and not state then return end
    facts = facts or {}
    local plan = Model.Plan(on and config or {}, facts)
    if plan.iconSkin then plan.iconLook = P.Suite.HostBridge.IconSkinLook(nil, "RECTANGLE", nil, true) end
    plan.font = P.Suite.ResolveFont(plan.values.auraFont) or P.Suite.GlobalFontPath()
    if not state then
        state = { containers = {} }
        previews[sample] = state
    end
    local visible = on and plan.exclusions[sample.prefix] and { buff = {}, debuff = {} }
    state.exclusions = visible or nil
    if on then
        for _, c in ipairs(plan.scopes[sample.prefix]) do
            local record = state.containers[c.key]
            if not record then
                record = { frame = CreateFrame(sample.static and "Frame" or "Button", nil, sample.cell), icons = {} }
                state.containers[c.key] = record
            end
            PaintContainer(record, sample, plan, c, facts, visible)
        end
    end
    if not on then HidePreview(state) end
    return on and state or nil
end

function UI.Render(editor, sample, metrics)
    local facts = sample.auraPreviewFacts or {}
    sample.auraPreviewFacts = facts
    facts.target = sample.state and sample.state.target
    facts.show = not (metrics.namesOnly or metrics.skinDisabled) and editor:LayerOn("auras")
    facts.element = not sample.static and sample.prefix == editor.sampleKind and editor.auraSample or nil
    facts.editor, facts.sharedText = not sample.static and editor or nil, editor.sharedAuraText
    local state = UI.Preview(sample, P.S.Config(ID), facts)
    sample.auraPreviewState = state
    if not state or state.bound or sample.static then return end
    local scope = Model.Scope(sample.prefix)
    for _, container in ipairs(Model.Containers) do
        local record = state.containers[container.key]
        if record then
            local prefix = Model.Prefix(scope, container)
            editor:Bind(record.frame, sample.prefix .. "." .. container.element,
                Tr("%s: %s"):format(Tr(scope.label), Tr(container.label)), prefix .. "OffsetX", prefix .. "OffsetY", prefix)
        end
    end
    state.bound = true
end
