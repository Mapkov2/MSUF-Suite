local _, NS = ...
local Build = NS.CatalogBuild.ForAddon("MSUF_Suite_CharacterPanel")
local CustomTabs = NS.CharacterTabs

local ID = "characterPanel"
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
    { id = "overview", label = NS.Text("Overview") },
    { id = "gear", label = NS.Text("Equipment") },
    { id = "reputation", label = NS.Text("Reputation") },
    { id = "skills", label = NS.Text("Skills") },
    { id = "pvp", label = NS.Text("PvP") },
    { id = "currency", label = NS.Text("Currency") },
    { id = "statistics", label = NS.Text("Statistics") },
}
Header.InspectTabs = { Header.Tabs[1], Header.Tabs[2], { id = "compare", label = NS.Text("Compare") } }

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

function Header.Order(config, kind)
    local spec = orders[kind]
    local value = config[spec.key] or ""
    local custom = kind == "tab" and CustomTabs.Get(config) or nil
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
        if not seen[item.id] then ordered[#ordered + 1] = item end
    end
    for i = 1, #customItems do
        local item = customItems[i]
        if not seen[item.id] then ordered[#ordered + 1] = item end
    end
    spec.ordered = ordered
    return ordered
end

function Header.Move(config, kind, id, destinationId)
    if id == destinationId then return end
    local ordered = Header.Order(config, kind)
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

Build.Module(ID, {
    title = "Character Panel",
    description = "Choose the Suite character and inspect windows or the Blizzard windows with the Basic skin.",
    core = true,
    page = "suite_hud",
    summary = "mode",
    prepareConfig = CustomTabs.Normalize,
})

local tabOrder = Build.String("tabOrder", "Tab order", "", 256)
local customTabs = Build.String("customTabs", "Custom tabs", "", CustomTabs.MaxBytes)
customTabs.hidden = true
local inspectTabOrder = Build.String("inspectTabOrder", "Tab order", "", 128)
local headerOrder = Build.String("headerOrder", "Header field order", "", 128)
tabOrder.hidden, inspectTabOrder.hidden, headerOrder.hidden = true, true, true
Build.Section(ID, "appearance", "Appearance", {
    Build.Choice("mode", "Panel style", MODE.SUITE, { "Basic", "Suite" }),
    Build.Bool("showFullStats", "Show all stats in Overview", true),
    tabOrder, inspectTabOrder, headerOrder, customTabs,
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
