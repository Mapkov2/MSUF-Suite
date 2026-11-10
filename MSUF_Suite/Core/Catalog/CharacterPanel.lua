local _, NS = ...
local Build = NS.CatalogBuild.ForAddon("MSUF_Suite_CharacterPanel")
local CustomTabs, Bindings = NS.CharacterTabs, NS.CharacterBindings

local ID = "characterPanel"
local PLAYER, INSPECT, FIELD = "tab", "inspectTab", "field"
local OVERVIEW, ATTRIBUTES = "overview", "attributes"
local HIDDEN_LIMIT = 128
local MODE = { BASIC = 1, SUITE = 2 }
NS.CharacterPanelMode = MODE
local Header = { Height = 62, Width = 940, CaptionWidth = 140 }
Header.PreviewWidth = Header.Width - Header.CaptionWidth - 2
NS.CharacterHeader = Header

Header.Fields = {
    { id = "portrait", prefix = "headerPortrait", label = "Portrait", size = 42, max = 52, visible = true, portrait = true },
    { id = "name", prefix = "headerName", label = "Name", size = 23, max = 30, visible = true, tone = "text" },
    { id = "level", prefix = "headerLevel", label = "Level", size = 12, max = 19, visible = true, lane = "meta" },
    { id = "class", prefix = "headerClass", label = "Class", size = 12, max = 19, visible = true, lane = "meta" },
    { id = "specialization", prefix = "headerSpecialization", label = "Specialization",
        size = 12, max = 19, visible = true, lane = "meta" },
    { id = "guild", prefix = "headerGuild", label = "Guild", size = 12, max = 19, lane = "meta" },
    { id = "zone", prefix = "headerZone", label = "Current zone", size = 12, max = 19, lane = "meta" },
    { id = "itemLevel", prefix = "headerItemLevel", label = "Item Level", size = 22, max = 30, visible = true, tone = "accentBright" },
}

Header.Tabs = {
    { id = OVERVIEW, label = NS.Text("Overview") },
    { id = "gear", label = NS.Text("Equipment") },
    { id = "reputation", label = NS.Text("Reputation") },
    { id = "skills", label = NS.Text("Skills") },
    { id = "pvp", label = NS.Text("PvP") },
    { id = "currency", label = NS.Text("Currency") },
    { id = "statistics", label = NS.Text("Statistics") },
}
Header.InspectTabs = { Header.Tabs[1], Header.Tabs[2], { id = "compare", label = NS.Text("Compare") } }
local attributesTab = { id = ATTRIBUTES, label = NS.Text("Attributes") }
local tabsWithAttributes = { unpack(Header.Tabs) }
table.insert(tabsWithAttributes, 4, attributesTab)

local function OrderSpec(items, key)
    local index = {}
    for i = 1, #items do index[items[i].id] = items[i] end
    return { items = items, key = key, index = index, value = "", ordered = items }
end
local orders = {
    tab = OrderSpec(Header.Tabs, "tabOrder"),
    inspectTab = OrderSpec(Header.InspectTabs, "inspectTabOrder"),
    field = OrderSpec(Header.Fields, "headerOrder"),
}

local attributesOrder = OrderSpec(tabsWithAttributes, "tabOrder")

local function ReadOrder(config, kind, spec)
    local value = config[spec.key]
    if type(value) ~= "string" then value = "" end
    local custom = kind == PLAYER and CustomTabs.Get(config) or nil
    if value == spec.value and custom == spec.custom then return spec.ordered end
    spec.value, spec.custom = value, custom
    if value == "" and (not custom or #custom == 0) then
        spec.ordered = spec.items
        return spec.ordered
    end

    local customIndex, customItems, ordered, seen = {}, {}, {}, {}
    if custom then
        for i = 1, #custom do
            local tab = custom[i]
            local x, y = CustomTabs.Position(tab)
            local item = { id = tab.id, label = tab.name, custom = true, x = x, y = y }
            customItems[i], customIndex[tab.id] = item, item
        end
    end
    for id in value:gmatch("[^,]+") do
        id = id:match("^%s*(.-)%s*$")
        local item = spec.index[id] or customIndex[id]
        if item and not seen[id] then
            ordered[#ordered + 1], seen[id] = item, true
        end
    end
    for i = 1, #spec.items do
        local item = spec.items[i]
        if not seen[item.id] and item ~= attributesTab then ordered[#ordered + 1] = item end
    end
    if spec == attributesOrder and not seen.attributes then
        for i = 1, #ordered do
            if ordered[i].id == "reputation" then
                table.insert(ordered, i + 1, attributesTab)
                break
            end
        end
    end
    for i = 1, #customItems do
        local item = customItems[i]
        if not seen[item.id] then ordered[#ordered + 1] = item end
    end
    spec.ordered = ordered
    return ordered
end

local visibilitySpecs = {
    [PLAYER] = { key = "hiddenTabs", stock = attributesOrder },
    [INSPECT] = { key = "hiddenInspectTabs", stock = orders.inspectTab },
}
local fallbackTabs = { Header.Tabs[1] }

local function RawOrder(config, kind, includeHiddenAttributes)
    local spec = kind == PLAYER and (config.showAttributesTab == true or includeHiddenAttributes)
        and attributesOrder or orders[kind]
    return ReadOrder(config, kind, spec)
end

local function SavedOrder(config, kind)
    -- Keep the position of Attributes when it was previously reordered.
    local value = config.tabOrder
    local savedAttributes = kind == PLAYER and type(value) == "string" and ("," .. value .. ","):find(",%s*attributes%s*,")
    return RawOrder(config, kind, savedAttributes)
end

local function ReadVisibility(config, kind)
    local spec = visibilitySpecs[kind]
    local ordered = RawOrder(config, kind)
    local hidden = config[spec.key]
    if type(hidden) ~= "string" or #hidden > HIDDEN_LIMIT then hidden = "" end
    local state = spec.state
    if state and state.ordered == ordered and state.value == hidden then return state end

    local visible = ordered
    if hidden ~= "" then
        local omitted = {}
        for id in hidden:gmatch("[^,]+") do
            id = id:match("^%s*(.-)%s*$")
            if id ~= ATTRIBUTES and spec.stock.index[id] then omitted[id] = true end
        end
        visible = {}
        for i = 1, #ordered do
            local tab = ordered[i]
            if not omitted[tab.id] then visible[#visible + 1] = tab end
        end
        -- An imported profile can hide all built-in tabs and have no custom tabs.
        if #visible == 0 then visible = fallbackTabs end
    end
    local ids, available = {}, {}
    for i = 1, #visible do ids[visible[i].id] = true end
    local stock = spec.stock.items
    for i = 1, #stock do
        local tab = stock[i]
        if not ids[tab.id] then available[#available + 1] = tab end
    end
    state = { ordered = ordered, value = hidden, visible = visible, ids = ids, available = available }
    spec.state = state
    return state
end

function Header.Order(config, kind)
    if kind == FIELD then return RawOrder(config, kind) end
    return ReadVisibility(config, kind).visible
end

function Header.TabVisible(config, kind, id)
    return ReadVisibility(config, kind).ids[id] == true
end

function Header.HiddenTabs(config, kind)
    return ReadVisibility(config, kind).available
end

local function ChooseHome(state, wanted, omitted)
    if wanted ~= omitted and state.ids[wanted] then return wanted end
    if omitted ~= OVERVIEW and state.ids[OVERVIEW] then return OVERVIEW end
    for i = 1, #state.visible do
        local id = state.visible[i].id
        if id ~= omitted then return id end
    end
end

function Header.HomeTab(config, kind)
    kind = kind or PLAYER
    return ChooseHome(ReadVisibility(config, kind), kind == PLAYER and config.homeTab or OVERVIEW)
end

local function HiddenSetting(spec, state, changed, visible)
    local hidden, stock = {}, spec.stock.items
    for i = 1, #stock do
        local id = stock[i].id
        if id ~= ATTRIBUTES then
            local shown = state.ids[id]
            if id == changed then shown = visible end
            if not shown then hidden[#hidden + 1] = id end
        end
    end
    return table.concat(hidden, ",")
end

function Header.SetTabVisible(config, kind, id, visible)
    visible = visible == true
    local spec = visibilitySpecs[kind]
    if not spec.stock.index[id] then return end
    local state = ReadVisibility(config, kind)
    if (state.ids[id] == true) == visible or (not visible and #state.visible == 1) then return end
    local patch = {}
    if id == ATTRIBUTES then patch.showAttributesTab = visible
    else patch[spec.key] = HiddenSetting(spec, state, id, visible) end
    if kind == PLAYER and not visible and ChooseHome(state, config.homeTab) == id then
        patch.homeTab = ChooseHome(state, config.homeTab, id)
    end
    return patch
end

function Header.SetHomeTab(config, id)
    if config.homeTab ~= id and Header.TabVisible(config, PLAYER, id) then return { homeTab = id } end
end

function Header.WithoutCustomTab(config, id, encoded)
    local state = ReadVisibility(config, PLAYER)
    if not CustomTabs.Find(config, id) or #state.visible == 1 or type(encoded) ~= "string" or encoded == config.customTabs then
        return
    end
    local ids, ordered = {}, SavedOrder(config, PLAYER)
    for i = 1, #ordered do
        local key = ordered[i].id
        if key ~= id then ids[#ids + 1] = key end
    end
    local patch = { customTabs = encoded, tabOrder = table.concat(ids, ","), homeTab = ChooseHome(state, config.homeTab, id) }
    Bindings.ClearTab(config, id, patch)
    return patch
end

function Header.Move(config, kind, id, destinationId)
    if id == destinationId then return end
    if kind ~= FIELD then
        local visible = ReadVisibility(config, kind).ids
        if not visible[id] or not visible[destinationId] then return end
    end
    local ordered = SavedOrder(config, kind)
    local ids, source, destination = {}
    for i = 1, #ordered do
        local key = ordered[i].id
        ids[i] = key
        if key == id then source = i end
        if key == destinationId then destination = i end
    end
    if not source or not destination then return end
    table.remove(ids, source)
    table.insert(ids, destination, id)
    return table.concat(ids, ",")
end

local function PrepareConfig(config)
    CustomTabs.Normalize(config)
    Bindings.Normalize(config)
    for kind, spec in pairs(visibilitySpecs) do
        if config[spec.key] ~= nil then
            config[spec.key] = HiddenSetting(spec, ReadVisibility(config, kind))
        end
    end
    if config.homeTab ~= nil or config.hiddenTabs ~= nil then config.homeTab = Header.HomeTab(config, PLAYER) end
end

Build.Module(ID, {
    title = "Character Panel",
    description = "Choose the Suite character and inspect windows or the Blizzard windows with the Basic skin.",
    core = true,
    page = "suite_hud",
    summary = "mode",
    prepareConfig = PrepareConfig,
})

local tabOrder = Build.String("tabOrder", "Tab order", "", 256)
local customTabs = Build.String("customTabs", "Custom tabs", "", CustomTabs.MaxBytes)
customTabs.hidden = true
local inspectTabOrder = Build.String("inspectTabOrder", "Tab order", "", 128)
local headerOrder = Build.String("headerOrder", "Header field order", "", 128)
local hiddenTabs = Build.String("hiddenTabs", "Hidden tabs", "", HIDDEN_LIMIT)
local hiddenInspectTabs = Build.String("hiddenInspectTabs", "Hidden tabs", "", HIDDEN_LIMIT)
local homeTab = Build.String("homeTab", "Main tab", OVERVIEW, 16)
tabOrder.hidden, inspectTabOrder.hidden, headerOrder.hidden = true, true, true
hiddenTabs.hidden, hiddenInspectTabs.hidden, homeTab.hidden = true, true, true
Build.Section(ID, "appearance", "Appearance", {
    Build.Choice("mode", "Panel style", MODE.SUITE, { "Basic", "Suite" }),
    Build.Bool("showFullStats", "Show all stats in Overview", true),
    Build.Bool("showAttributesTab", "Show Attributes tab", false),
    tabOrder, inspectTabOrder, headerOrder, customTabs, hiddenTabs, hiddenInspectTabs, homeTab,
})

Bindings.RegisterSettings(Build, ID)

local reputationColor = Build.Color("reputationBarColor", "Bar color", "")
reputationColor.inheritColor = "accentBright"
Build.Section(ID, "reputation", "Reputation", {
    Build.Bool("showReputationBars", "Show reputation bars", false),
    Build.Choice("reputationValue", "Reputation display", 1, {
        "Current standing", "Progress", "Remaining to goal", "Percentage",
    }),
    -- Goal indices 2 through 8 match the native standard standing IDs.
    Build.Choice("reputationGoal", "Reputation goal", 1, {
        "Next rank", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted",
    }),
    Build.Number("reputationBarHeight", "Bar height", 3, 2, 8),
    reputationColor,
})

for i = 1, #Header.Fields do
    local field = Header.Fields[i]
    local rules = {
        Build.Bool(field.prefix .. "Visible", "Show", field.visible),
        Build.Number(field.prefix .. "Size", "Size", field.size, field.portrait and 20 or 8, field.max),
        Build.Number(field.prefix .. "X", "Horizontal position", 0, -Header.PreviewWidth, Header.PreviewWidth),
        Build.Number(field.prefix .. "Y", "Vertical position", 0, -Header.Height, Header.Height),
    }
    if not field.portrait then
        local color = Build.Color(field.prefix .. "Color", "Text color", "")
        color.inheritColor = field.tone or "muted"
        rules[#rules + 1] = Build.Font(field.prefix .. "Font", "Font")
        rules[#rules + 1] = color
    end
    Build.Section(ID, field.id, field.label, rules)
end

-- Profiles created before the standalone panel keep their existing skin.
function NS.MigrateCharacterPanelMode(modules)
    local settings = NS.SuiteMigrationSteps.EnsureModule(modules, ID)
    if settings.mode == nil then settings.mode = MODE.BASIC end
end
