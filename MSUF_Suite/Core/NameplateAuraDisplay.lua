local _, NS = ...
-- Settings shared by the options, preview and the tracked aura containers.
-- The built-in nameplate rows are used unless a tracked row requests exclusions.
local Display = { LIMIT = 16, MAX_ICONS = 40, LIST_BYTES = 2048 }
NS.NameplateAuraDisplay = Display
local Public, floor, min, max = NS.Public, math.floor, math.min, math.max

-- Spell lists are client data: Retail and WoW Forever have different auras.
-- Every list is stored once per client under its own key, so a profile
-- imported on the other client keeps the list it arrived with, shows its own
-- list there and returns unchanged.
Display.Clients = {
    { id = "Retail", client = "retail", label = "Retail" },
    { id = "Forever", client = "forever", label = "WoW Forever" },
}
Display.Client = NS.Client.isForever and "Forever" or "Retail"

Display.Scopes = {
    { key = "enemy", id = "Enemy", label = "Enemy", helpful = false },
    { key = "friendly", id = "Friendly", label = "Friendly", helpful = true },
}
Display.NativeRows = {
    { key = "buff", id = "Buff", label = "Buffs", kind = "native", element = "Buffs", native = "Buffs",
        frame = "BuffListFrame" },
    { key = "debuff", id = "Debuff", label = "Debuffs", kind = "native", element = "Auras", native = "Debuffs",
        frame = "DebuffListFrame" },
    { key = "control", id = "Control", label = "Control effects", kind = "native", element = "ControlAura", native = "Control",
        frame = "CrowdControlListFrame", playerFrame = "LossOfControlFrame" },
}
Display.Containers = {
    { key = "custom1", id = "Custom1", label = "Custom 1", kind = "custom", list = "Spells", y = 74, element = "CustomOne" },
    { key = "custom2", id = "Custom2", label = "Custom 2", kind = "custom", list = "Spells", y = 102, element = "CustomTwo" },
    { key = "custom3", id = "Custom3", label = "Custom 3", kind = "custom", list = "Spells", y = 130, element = "CustomThree" },
    { key = "dots", id = "Dots", label = "Dots on target", kind = "dots", list = "IDs", y = 46, element = "Tracked" },
}
Display.NativeGroups = { enemy = { "enemyNpc", "enemyPlayer" }, friendly = { "friendlyPlayer" } }
Display.NativeShared = { "auraScaleMode", "auraScalePercent", "auraDebuffPadding", "personalAuras", "auraClickthrough" }

function Display.NativeSetting(group, kind)
    if group == "friendlyNpc" then return kind == "Debuffs" and "friendlyNpcDebuffs" or nil end
    return group and group .. kind
end

function Display.NativeShown(config, group, kind)
    local style = NS.NameplateStyle
    local key = Display.NativeSetting(group, kind)
    if not key then return false end
    local original = config.look == 2
    if group == "friendlyNpc" then
        local mode = config[key]
        if not original and (mode == 2 or mode == 3) then return mode == 2 end
        return style.NativeToggle("nameplateShowDebuffsOnFriendly", false)
    end
    if not original and config[group .. "AuraMode"] == 2 then return config[key] == true end
    return style.NativeBit(style.AuraCVar[group], style.AuraBits[kind], true)
end

function Display.Active(config)
    return config.auraDisplayEnabled == true
end

function Display.PersonalAuras()
    return NS.NameplateStyle.NativeToggle("nameplateShowAllPersonalAuras", false)
end

Display.Tools = {
    native = { "layout", "style" },
    custom = { "setup", "layout", "ordering", "filters", "whitelist", "style" },
}
Display.Tools.dots = Display.Tools.custom
Display.NativeFields = { layout = { "Scale", "Layer" }, style = { "Alpha" } }
Display.ToolLabels = { setup = "Setup", layout = "Layout", ordering = "Ordering", filters = "Filters",
    whitelist = "Whitelist", style = "Style" }
-- The settings of each tool, in control order. A container lacks the fields
-- its kind does not have (Name on Dots, Source on Custom, Filter off a lane).
Display.ToolFields = {
    setup = { "Visible", "Name", "Type", "Display", "Source", "HideDuplicates", "Missing", "MissingAlpha" },
    layout = { "Anchor", "Growth", "Max", "Size", "HeightPercent", "PerRow", "Gap", "Layer" },
    ordering = { "Sort", "Order" },
    filters = { "OnlyMine", "HidePermanent", "MaxDuration" },
    whitelist = {},
    style = { "IconSkin", "Pandemic", "Zoom", "Alpha", "Tooltip", "Padding", "Dispel", "StackText", "StackPoint", "StackSize", "StackX", "StackY",
        "TimeText", "TimePoint", "TimeSize", "TimeX", "TimeY", "TimeDecimals", "Swipe", "SwipeDirection",
        "DurationBar", "DurationBarDisplay", "DurationBarHeight", "DurationBarPosition", "DurationBarDirection", "DurationBarColor" },
}
Display.Types = { "Buffs", "Debuffs" }
Display.Displays = { "Fixed slots", "Only active auras" }
Display.Sources = { "DoTs selected for health colors", "Custom aura IDs" }
Display.Sorts = { "Blizzard priority", "Expiration time", "Name", "Application order", "Important first" }
Display.Orders = { "Normal", "Reversed" }
Display.Growth = { "Right then up", "Left then up", "Right then down", "Left then down" }
-- The common appearance of the tracked containers.
Display.AppearanceKeys = { "auraFont", "auraTextOutline", "auraTimeText", "auraTimeSize", "auraTimePoint", "auraTimeX",
    "auraTimeY", "auraStackText", "auraStackSize", "auraStackPoint", "auraStackX", "auraStackY", "auraSwipe",
    "auraSwipeAlpha", "auraDispelHighlight", "auraEnrageHighlight", "auraPandemicHighlight", "auraHighlightSize" }
Display.ColorKeys = { "auraTimeColor", "auraStackColor", "auraPandemicColor" }
Display.SharedKeys = { "auraDisplayEnabled", "auraSunder", "auraClickthrough", "auraColorsData", "look", "enemy", "friendly",
    "personalAuras", "auraScaleMode", "auraScalePercent", "nativeSize", "auraEnemyBuffScale", "auraEnemyDebuffScale",
    "auraFriendlyBuffScale", "auraFriendlyDebuffScale", "auraEnemyBuffLayer", "auraEnemyDebuffLayer", "auraFriendlyBuffLayer",
    "auraFriendlyDebuffLayer", "auraEnemyBuffAlpha", "auraEnemyDebuffAlpha", "auraFriendlyBuffAlpha", "auraFriendlyDebuffAlpha" }
for _, list in ipairs({ Display.AppearanceKeys, Display.ColorKeys }) do
    for _, key in ipairs(list) do Display.SharedKeys[#Display.SharedKeys + 1] = key end
end

-- Blizzard's maxDuration candidate filter also rejects duration 0, so an
-- unreachable finite ceiling hides permanent auras and keeps every timed one.
local MAX_FINITE_DURATION = 2147483647
local SUNDER = { 7386, 7405, 8380, 11596, 11597, 25225, 47467 }
-- The container point that sits on each health bar anchor (outside the
-- bar) and the direction a lane keeps its distance in.
local ATTACH = { TOPLEFT = { "BOTTOMLEFT", 0, 1 }, TOP = { "BOTTOM", 0, 1 }, TOPRIGHT = { "BOTTOMRIGHT", 0, 1 },
    LEFT = { "RIGHT", -1, 0 }, CENTER = { "CENTER", 0, 0 }, RIGHT = { "LEFT", 1, 0 },
    BOTTOMLEFT = { "TOPLEFT", 0, -1 }, BOTTOM = { "TOP", 0, -1 }, BOTTOMRIGHT = { "TOPRIGHT", 0, -1 } }

function Display.Prefix(scope, container)
    return "aura" .. scope.id .. container.id
end

-- The key of a container's spell list on one client (default: this client).
function Display.ListKey(scope, container, clientId)
    return Display.Prefix(scope, container) .. container.list .. (clientId or Display.Client)
end

function Display.Scope(key)
    for _, scope in ipairs(Display.Scopes) do
        if scope.key == key then return scope end
    end
end

function Display.Container(key)
    for _, row in ipairs(Display.NativeRows) do
        if row.key == key then return row end
    end
    for _, container in ipairs(Display.Containers) do
        if container.key == key then return container end
    end
end

-- The scope and container of a preview handle id ("enemy.Tracked").
function Display.Element(id)
    local side, element = tostring(id):match("^(%a+)%.(%a+)$")
    local scope = side and Display.Scope(side)
    if not scope then return end
    for _, container in ipairs(Display.Containers) do
        if container.element == element then return scope, container end
    end
end

function Display.NativeElement(element)
    for _, row in ipairs(Display.NativeRows) do
        if row.element == element then return row end
    end
end

function Display.VisibilityKeys(scope, lane)
    local switches = {}
    for _, group in ipairs(Display.NativeGroups[scope.key]) do
        switches[#switches + 1] = Display.NativeSetting(group, lane.native)
    end
    return switches
end

-- The catalog keys one tool edits, in control order. own: only the
-- container's own controls, without visibility and shared appearance.
function Display.ToolKeys(scope, container, tool, own)
    local keys, rules = {}, NS.SuiteCatalog.nameplates.rules
    local prefix = Display.Prefix(scope, container)
    local function Add(list)
        for _, key in ipairs(list) do
            if rules[key] then keys[#keys + 1] = key end
        end
    end
    local fields = container.kind == "native" and Display.NativeFields or Display.ToolFields
    for _, field in ipairs(fields[tool] or {}) do Add({ prefix .. field }) end
    if own then return keys end
    if container.kind == "native" and tool == "layout" then
        Add(Display.VisibilityKeys(scope, container))
        if scope.key == "friendly" and container.key == "debuff" then Add({ "friendlyNpcDebuffs" }) end
    elseif tool == "whitelist" and container.kind == "dots" and scope.key == "enemy" then
        Add({ prefix .. "Source", "auraSunder" })
    end
    return keys
end

local function ID(value)
    if not Public(value) or type(value) ~= "number" or value < 1 or value >= 2147483648
        or value ~= floor(value) then return end
    return value
end

function Display.IDs(text, limit)
    local list, set = {}, {}
    if not Public(text) or type(text) ~= "string" then return list, set end
    for token in text:sub(1, Display.LIST_BYTES):gmatch("[^,%s;]+") do
        local id = ID(tonumber(token))
        if id and not set[id] then
            list[#list + 1], set[id] = id, true
            if #list == (limit or Display.MAX_ICONS) then break end
        end
    end
    return list, set
end

local function Read(config, key)
    local rule = NS.SuiteCatalog.nameplates.rules[key]
    local value = config[key]
    if not rule then return value end
    if not Public(value) or type(value) ~= type(rule.default) then return rule.default end
    if type(value) == "number" then
        if value ~= value then return rule.default end
        value = max(rule.min, min(rule.max, value))
        return floor(value / (rule.step or 1) + .5) * (rule.step or 1)
    end
    if rule.color and not value:match("^%x%x%x%x%x%x$") then return rule.default end
    if rule.maxLength and #value > rule.maxLength then return value:sub(1, rule.maxLength) end
    return value
end

local function AddRow(rows, used, id, ids, any)
    local set = {}
    for _, spell in ipairs(ids) do
        spell = ID(spell)
        if spell and not used[spell] then set[spell], used[spell] = true, true end
    end
    if next(set) then rows[#rows + 1] = { id = id, ids = set, any = any or nil } end
end

local function AddTrackedRow(rows, used, id, ids)
    if used[id] then return end
    local aliases = NS.Client.isForever and NS.HostBridge.ForeverAuraAliases(id)
    if not aliases then return AddRow(rows, used, id, ids) end
    local merged = { id }
    for _, spell in ipairs(ids) do merged[#merged + 1] = spell end
    for _, spell in ipairs(aliases) do merged[#merged + 1] = spell end
    AddRow(rows, used, id, merged)
end

-- The DoTs the health colors use for this specialization. A preview shows a
-- saved specialization without reading the live one.
local function ColorRows(values, preview)
    local colors = NS.NameplateAuraColors
    local stored = colors.Decode(values.auraColorsData)
    if not preview then
        local spec = colors.Spec()
        return spec and colors.Selected(stored[spec]) or {}
    end
    local spec = preview.specID
    if not spec then
        for id in pairs(stored) do if not spec or id < spec then spec = id end end
    end
    local selected = {}
    for _, row in ipairs(stored[spec] or {}) do
        if row.enabled ~= false then selected[#selected + 1] = row end
    end
    return selected
end

-- The auras a Suite-only container tracks, in slot order. any: an aura from
-- every player (Sunder Armor), whatever Only mine says.
function Display.Rows(values, scope, container, preview)
    local rows, used = {}, {}
    local prefix = Display.Prefix(scope, container)
    if container.kind == "dots" and scope.key == "enemy" and values[prefix .. "Source"] == 1 then
        for _, row in ipairs(ColorRows(values, preview)) do AddTrackedRow(rows, used, row.id, row.ids) end
    else
        for _, id in ipairs(Display.IDs(values[Display.ListKey(scope, container)])) do
            AddTrackedRow(rows, used, id, { id })
        end
    end
    if container.kind == "dots" and scope.key == "enemy" and values.auraSunder and NS.Client.isForever then
        AddRow(rows, used, SUNDER[1], SUNDER, true)
    end
    return rows
end

local function Geometry(c)
    local left, down = c.growth == 2 or c.growth == 4, c.growth >= 3
    local columns = max(1, min(c.count, c.perRow))
    local lines = max(1, math.ceil(c.count / c.perRow))
    c.flowPoint = (down and "TOP" or "BOTTOM") .. (left and "RIGHT" or "LEFT")
    c.horizontal, c.vertical = left and "Left" or "Right", down and "Down" or "Up"
    c.dx, c.dy = left and -1 or 1, down and -1 or 1
    local padding = 2 * c.padding
    c.lineSize = c.perRow * (c.width + c.gap) - c.gap
    c.gridWidth = columns * (c.width + c.gap) - c.gap + padding
    c.gridHeight = lines * (c.height + c.gap) - c.gap + padding
end

-- Where icon `index` of a fixed grid sits, from the container's flow corner.
function Display.SlotOffset(c, index)
    local column, line = (index - 1) % c.perRow, floor((index - 1) / c.perRow)
    return (c.padding + column * (c.width + c.gap)) * c.dx, (c.padding + line * (c.height + c.gap)) * c.dy
end

local function Candidate(ids, limit)
    local candidate = { includeSpellIDs = ids }
    if limit then candidate.maxDuration = limit end
    return candidate
end

-- Size and anchor of a container text: its own, or the shared appearance.
function Display.Text(values, prefix, field)
    local point, size = values[prefix .. field .. "Point"], values[prefix .. field .. "Size"]
    local text = { x = 0, y = 0 }
    if point == 1 then
        text.point, text.x, text.y = NS.AnchorPoints[values["aura" .. field .. "Point"]],
            values["aura" .. field .. "X"], values["aura" .. field .. "Y"]
    else
        text.point = NS.AnchorPoints[point - 1]
    end
    text.x = text.x + (values[prefix .. field .. "X"] or 0)
    text.y = text.y + (values[prefix .. field .. "Y"] or 0)
    text.size = size == 0 and values["aura" .. field .. "Size"] or size
    return text
end

local function DurationLimit(values, prefix)
    local duration = values[prefix .. "MaxDuration"]
    return duration > 0 and duration or values[prefix .. "HidePermanent"] and MAX_FINITE_DURATION or nil
end

-- Fixed slots keep one place per aura; Only active auras packs them. A row
-- from every player needs its own filter: its own slot, or the second group.
local function Tracking(c, values, prefix, rows)
    local base = (values[prefix .. "Type"] == 1 and "HELPFUL" or "HARMFUL")
    local mine, limit = values[prefix .. "OnlyMine"], DurationLimit(values, prefix)
    c.anyFilter = base .. "|INCLUDE_NAME_PLATE_ONLY"
    c.filter = mine and base .. "|PLAYER|INCLUDE_NAME_PLATE_ONLY" or c.anyFilter
    c.fixed = values[prefix .. "Display"] == 1
    c.helpful = base == "HELPFUL"
    c.rows, c.count, c.groupCount, c.anyCount = {}, 0, 0, 0
    if c.fixed then
        for index = 1, min(#rows, c.max, Display.LIMIT) do
            local row = rows[index]
            c.rows[index] = { id = row.id, any = row.any, filter = row.any and c.anyFilter or c.filter,
                candidate = Candidate(row.ids, limit) }
        end
        c.count = #c.rows
        return
    end
    local include, any = {}, {}
    for _, row in ipairs(rows) do
        local target = row.any and mine and any or include
        for id in pairs(row.ids) do target[id] = true end
        c.rows[#c.rows + 1] = row
    end
    c.groupCount = next(include) and c.max or 0
    c.anyCount = next(any) and 1 or 0
    c.count = max(c.groupCount, c.anyCount)
    c.candidate, c.anyCandidate = Candidate(include, limit), Candidate(any, limit)
end

local function Compile(config, values, scope, container, preview)
    local prefix, parts = Display.Prefix(scope, container), {}
    local function V(field)
        local key = prefix .. field
        if values[key] == nil then values[key] = Read(config, key) end
        parts[#parts + 1] = tostring(values[key])
        return values[key]
    end
    for _, fields in pairs(Display.ToolFields) do
        for _, field in ipairs(fields) do V(field) end
    end
    local listKey = Display.ListKey(scope, container)
    values[listKey] = Read(config, listKey)
    parts[#parts + 1] = tostring(values[listKey])
    local c = { key = container.key, kind = container.kind, prefix = prefix, scope = scope.key, label = container.label,
        element = container.element }
    local size = V("Size")
    c.width, c.height = size, max(1, floor(size * V("HeightPercent") / 100 + .5))
    c.gap, c.perRow, c.growth, c.max, c.layer = V("Gap"), V("PerRow"), V("Growth"), V("Max"), V("Layer")
    local rows = Display.Rows(values, scope, container, preview)
    for _, row in ipairs(rows) do
        local ids = {}
        for id in pairs(row.ids) do ids[#ids + 1] = id end
        table.sort(ids)
        parts[#parts + 1] = table.concat(ids, ",") .. (row.any and "*" or "")
    end
    Tracking(c, values, prefix, rows)
    c.enabled = values.auraDisplayEnabled == true and V("Visible") and #rows > 0
    c.hideDuplicates = V("HideDuplicates")
    parts[#parts + 1] = tostring(c.enabled)
    c.iconSkin, c.padding = V("IconSkin") == true, V("Padding")
    Geometry(c)
    local anchor = NS.AnchorPoints[V("Anchor")]
    c.point, c.relative, c.x, c.y = ATTACH[anchor][1], anchor, V("OffsetX"), V("OffsetY")
    c.sort, c.reverse = V("Sort"), V("Order") == 2
    c.missing, c.missingAlpha = c.fixed and V("Missing"), V("MissingAlpha")
    c.crop = .07 + (1 - 100 / V("Zoom")) * .43
    c.alpha, c.tooltip, c.dispel, c.pandemic, c.swipe = V("Alpha") / 100, V("Tooltip"), V("Dispel"), V("Pandemic"), V("Swipe")
    c.swipeReverse = V("SwipeDirection") ~= 2
    c.durationBar = V("DurationBar")
    c.barOnly = c.durationBar and V("DurationBarDisplay") == 2
    c.durationBarHeight = min(c.height, V("DurationBarHeight"))
    c.durationBarTop = V("DurationBarPosition") == 2
    c.durationBarElapsed = V("DurationBarDirection") == 2
    c.durationBarColor = V("DurationBarColor")
    c.timeText, c.stackText, c.timeDecimals = V("TimeText"), V("StackText"), V("TimeDecimals")
    c.text = { Time = Display.Text(values, prefix, "Time"), Stack = Display.Text(values, prefix, "Stack") }
    c.sig = table.concat(parts, "|")
    return c
end

-- A checked row claims its configured spell IDs. Fixed rows only claim IDs
-- from the slots within their visible limit.
local function AddExclusions(ids, source)
    local function Add(candidate)
        for id in pairs(candidate.includeSpellIDs) do ids[id] = true end
    end
    if source.fixed then
        for _, row in ipairs(source.rows) do Add(row.candidate) end
    else
        Add(source.candidate)
        Add(source.anyCandidate)
    end
end

local function AddLaneExclusions(list, destination, helpful)
    local ids = {}
    local row = list[destination]
    for index, source in ipairs(list) do
        local preferred = not row or index ~= destination and row.kind ~= "dots"
            and (index < destination or source.kind == "dots" or not row.hideDuplicates)
        -- A target-only row is not an exclusion source for ordinary tracked
        -- rows: they also run on plates where that DoT row is absent.
        if preferred and (not row or source.kind ~= "dots")
            and source.enabled and source.hideDuplicates and source.helpful == helpful then
            AddExclusions(ids, source)
        end
    end
    return next(ids) and ids or nil
end

local function HasExclusions(list)
    for _, row in ipairs(list) do
        if row.enabled and row.hideDuplicates then return true end
    end
    return false
end

function Display.Exclusions(list)
    local rows = {
        debuff = AddLaneExclusions(list, 0, false),
        buff = AddLaneExclusions(list, 0, true),
    }
    for index, row in ipairs(list) do
        if row.enabled then rows[row.key] = AddLaneExclusions(list, index, row.helpful) end
    end
    return rows
end

function Display.Excluding(candidate, ids)
    if not ids then return candidate end
    return { includeSpellIDs = candidate.includeSpellIDs, maxDuration = candidate.maxDuration, excludeSpellIDs = ids }
end

-- The immutable plan of every container. signature: any change; style: the
-- settings every container shares; a container's sig: its own settings, so
-- the runtime touches only the containers an edit changed. used: the side
-- has an enabled tracked container.
function Display.Plan(config, preview)
    local values, shared, signature = {}, {}, {}
    for _, key in ipairs(Display.SharedKeys) do
        values[key] = Read(config, key)
        shared[#shared + 1] = tostring(values[key])
    end
    local plan = { values = values, scopes = {}, used = {}, targetOnly = {}, always = {}, exclusions = {}, style = table.concat(shared, "|") }
    signature[1] = plan.style
    plan.iconSkin = false
    for _, scope in ipairs(Display.Scopes) do
        local list = {}
        for _, container in ipairs(Display.Containers) do
            local c = Compile(config, values, scope, container, preview)
            list[#list + 1], signature[#signature + 1] = c, c.sig
            if c.enabled then
                plan.used[scope.key] = true
                if c.kind == "dots" then
                    plan.targetOnly[scope.key] = true
                else
                    plan.always[scope.key] = true
                end
                if c.iconSkin then plan.iconSkin = true end
            end
        end
        plan.scopes[scope.key] = list
        if HasExclusions(list) then
            local exclusions = Display.Exclusions(list)
            plan.exclusions[scope.key] = exclusions
        end
    end
    plan.signature = table.concat(signature, "#")
    return plan
end
