local _, NS = ...
-- Cold configuration of the nameplate aura containers, shared by the
-- runtime, the options and the preview. Every plate side (enemy, friendly)
-- has Buffs and Debuffs, Custom 1-3 and Dots on target, laid out like MSUF's
-- unit frame Auras. Buffs and Debuffs stay Blizzard's own lists until they
-- are made Visible here; then the Suite draws them and Blizzard's list of
-- that kind is hidden. No live aura data enters this model: Blizzard's aura
-- containers evaluate every predicate.
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
-- element: the container's handle in the nameplate preview editor (letters
-- only). A lane (Buffs, Debuffs) shares the handle, the offsets and the
-- plate-kind switches of Blizzard's list: native names its switch, fields
-- and elements what its tab shows and resets, frame Blizzard's list frame.
-- title: the name in a tool title ("Buff Layout"). y: default distance of a
-- Suite-only container above the health bar.
Display.Containers = {
    { key = "buff", id = "Buff", label = "Buffs", title = "Buff", kind = "lane", list = "Block", element = "Buffs",
        helpful = true, native = "Buffs", fields = { "Buffs" }, elements = { "Buffs" }, frame = "BuffListFrame",
        anchor = 4, growth = 2 },
    { key = "debuff", id = "Debuff", label = "Debuffs", title = "Debuff", kind = "lane", list = "Block", element = "Auras",
        helpful = false, native = "Debuffs", fields = { "Debuffs", "Control" }, elements = { "Auras", "ControlAura" },
        frame = "DebuffListFrame", anchor = 1, growth = 1 },
    { key = "custom1", id = "Custom1", label = "Custom 1", kind = "custom", list = "Spells", y = 74, element = "CustomOne" },
    { key = "custom2", id = "Custom2", label = "Custom 2", kind = "custom", list = "Spells", y = 102, element = "CustomTwo" },
    { key = "custom3", id = "Custom3", label = "Custom 3", kind = "custom", list = "Spells", y = 130, element = "CustomThree" },
    { key = "dots", id = "Dots", label = "Dots on target", kind = "dots", list = "IDs", y = 46, element = "Tracked" },
}
Display.NativeGroups = { enemy = { "enemyNpc", "enemyPlayer" }, friendly = { "friendlyPlayer" } }
Display.NativeShared = { "auraScaleMode", "auraScalePercent", "personalAuras", "auraClickthrough" }
Display.Tools = {
    lane = { "layout", "ordering", "filters", "blacklist", "style" },
    custom = { "setup", "layout", "ordering", "filters", "whitelist", "style" },
    dots = { "setup", "layout", "ordering", "filters", "dots", "style" },
}
Display.ToolLabels = { setup = "Setup", layout = "Layout", ordering = "Ordering", filters = "Filters",
    blacklist = "Blacklist", whitelist = "Whitelist", dots = "Dots", style = "Style" }
-- The settings of each tool, in control order. A container lacks the fields
-- its kind does not have (Name on Dots, Source on Custom, Filter off a lane).
Display.ToolFields = {
    setup = { "Visible", "Name", "Type", "Display", "Source", "Missing", "MissingAlpha" },
    layout = { "Anchor", "Growth", "Max", "Size", "HeightPercent", "PerRow", "Gap", "Layer" },
    ordering = { "Sort", "Order" },
    filters = { "Filter", "OnlyMine", "HidePermanent", "MaxDuration" },
    blacklist = {},
    whitelist = {},
    dots = {},
    style = { "Pandemic", "Zoom", "Alpha", "Tooltip", "Dispel", "StackText", "StackPoint", "StackSize",
        "TimeText", "TimePoint", "TimeSize", "Swipe" },
}
Display.Types = { "Buffs", "Debuffs" }
Display.Displays = { "Fixed slots", "Only active auras" }
Display.Sources = { "DoTs selected for health colors", "Custom aura IDs" }
Display.Filters = { "All auras", "Priority auras", "Important auras", "Stealable auras", "Dispellable auras" }
Display.Sorts = { "Blizzard priority", "Expiration time", "Name", "Application order", "Important first" }
Display.Orders = { "Normal", "Reversed" }
Display.Growth = { "Right then up", "Left then up", "Right then down", "Left then down" }
-- The look every container shares; the Style tool shows it below its own.
Display.AppearanceKeys = { "auraFont", "auraTextOutline", "auraTimeText", "auraTimeSize", "auraTimePoint", "auraTimeX",
    "auraTimeY", "auraStackText", "auraStackSize", "auraStackPoint", "auraStackX", "auraStackY", "auraSwipe",
    "auraSwipeAlpha", "auraDispelHighlight", "auraEnrageHighlight", "auraPandemicHighlight", "auraHighlightSize" }
Display.ColorKeys = { "auraTimeColor", "auraStackColor", "auraPandemicColor" }
Display.SharedKeys = { "auraDisplayEnabled", "auraSunder", "auraClickthrough", "auraColorsData", "look", "enemy", "friendly" }
for _, list in ipairs({ Display.AppearanceKeys, Display.ColorKeys }) do
    for _, key in ipairs(list) do Display.SharedKeys[#Display.SharedKeys + 1] = key end
end

-- Blizzard's maxDuration candidate filter also rejects duration 0, so an
-- unreachable finite ceiling hides permanent auras and keeps every timed one.
local MAX_FINITE_DURATION = 2147483647
local SUNDER = { 7386, 7405, 8380, 11596, 11597, 25225, 47467 }
local LANE_PAD = 6
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

-- Blizzard's settings a lane's Layout shows below its own, each in one
-- place only: the mode of each plate kind (shared by both lanes of the
-- plates), the lane's own switches, and what every Blizzard aura shares.
function Display.NativeKeys(scope, lane)
    local modes, switches = {}, {}
    for _, group in ipairs(Display.NativeGroups[scope.key]) do
        modes[#modes + 1] = group .. "AuraMode"
        for _, field in ipairs(lane.fields) do switches[#switches + 1] = group .. field end
    end
    if scope.key == "friendly" and lane.key == "debuff" then switches[#switches + 1] = "friendlyNpcDebuffs" end
    return modes, switches, Display.NativeShared
end

-- The catalog keys one tool edits, in control order. own: only the
-- container's own settings, without the ones its tool shares with others
-- (Blizzard's settings under a lane's Layout, the shared look under Style).
function Display.ToolKeys(scope, container, tool, own)
    local keys, rules = {}, NS.SuiteCatalog.nameplates.rules
    local prefix = Display.Prefix(scope, container)
    local function Add(list)
        for _, key in ipairs(list) do
            if rules[key] then keys[#keys + 1] = key end
        end
    end
    if container.kind == "lane" and tool == "layout" then Add({ prefix .. "Visible" }) end
    for _, field in ipairs(Display.ToolFields[tool] or {}) do Add({ prefix .. field }) end
    if tool == "dots" and scope.key == "enemy" then Add({ "auraSunder" }) end
    if own then return keys end
    if container.kind == "lane" and tool == "layout" then
        for _, list in ipairs({ Display.NativeKeys(scope, container) }) do Add(list) end
    elseif tool == "style" then
        Add(Display.AppearanceKeys)
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
        for _, row in ipairs(ColorRows(values, preview)) do AddRow(rows, used, row.id, row.ids) end
    else
        for _, id in ipairs(Display.IDs(values[Display.ListKey(scope, container)])) do AddRow(rows, used, id, { id }) end
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
    c.lineSize = c.perRow * (c.width + c.gap) - c.gap
    c.gridWidth = columns * (c.width + c.gap) - c.gap
    c.gridHeight = lines * (c.height + c.gap) - c.gap
end

-- Where icon `index` of a fixed grid sits, from the container's flow corner.
function Display.SlotOffset(c, index)
    local column, line = (index - 1) % c.perRow, floor((index - 1) / c.perRow)
    return column * (c.width + c.gap) * c.dx, line * (c.height + c.gap) * c.dy
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
    end
    c.groupCount = next(include) and c.max or 0
    c.anyCount = next(any) and 1 or 0
    c.count = max(c.groupCount, c.anyCount)
    c.candidate, c.anyCandidate = Candidate(include, limit), Candidate(any, limit)
end

-- A lane shows every aura of its kind Blizzard's filter accepts, minus the
-- blacklist. Crowd control stays with Blizzard's own list.
local function LaneTracking(c, values, prefix, lane, scope)
    local filter = lane.helpful and "HELPFUL|INCLUDE_NAME_PLATE_ONLY" or "HARMFUL|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL"
    local kind, candidate = values[prefix .. "Filter"], {}
    if values[prefix .. "OnlyMine"] then filter = filter .. "|PLAYER" end
    if kind == 2 then candidate.isPriorityAura = true
    elseif kind == 3 then filter = filter .. "|IMPORTANT"
    elseif kind == 4 then candidate.isStealable = true
    elseif kind == 5 then filter = filter .. "|DISPELLABLE" end
    local _, blocked = Display.IDs(values[Display.ListKey(scope, lane)])
    if next(blocked) then candidate.excludeSpellIDs = blocked end
    candidate.maxDuration = DurationLimit(values, prefix)
    c.filter, c.candidate, c.fixed, c.rows = filter, candidate, false, {}
    c.groupCount, c.anyCount, c.count = c.max, 0, c.max
end

-- The plate kinds a lane shows on: Blizzard's own switches, customized in
-- the Suite or left with Blizzard's setting. A preview reads no CVar.
local function LaneKinds(config, scope, lane, preview, parts)
    local kinds, style = {}, NS.NameplateStyle
    for _, group in ipairs(Display.NativeGroups[scope.key]) do
        if config[group .. "AuraMode"] == 2 then
            kinds[group] = config[group .. lane.native] == true
        else
            kinds[group] = preview ~= nil or style.NativeBit(style.AuraCVar[group], style.AuraBits[lane.native], true) == true
        end
        parts[#parts + 1] = tostring(kinds[group])
    end
    if scope.key == "friendly" and lane.key == "debuff" then
        local mode = config.friendlyNpcDebuffs
        kinds.friendlyNpc = mode == 2
            or mode == 1 and (preview ~= nil or style.NativeToggle("nameplateShowDebuffsOnFriendly", false) == true)
        parts[#parts + 1] = tostring(kinds.friendlyNpc)
    end
    return kinds
end

-- A lane sits where Blizzard's list sits (the same preview handle), a
-- Suite-only container at its own offsets.
local function Position(c, config, values, scope, container, V)
    local anchor = NS.AnchorPoints[V("Anchor")]
    local attach = ATTACH[anchor]
    c.point, c.relative = attach[1], anchor
    if container.kind ~= "lane" then
        c.x, c.y = V("OffsetX"), V("OffsetY")
        return
    end
    local key = scope.key .. container.element .. "Offset"
    values[key .. "X"], values[key .. "Y"] = Read(config, key .. "X") or 0, Read(config, key .. "Y") or 0
    c.x, c.y = values[key .. "X"] + attach[2] * LANE_PAD, values[key .. "Y"] + attach[3] * LANE_PAD
    c.offsets = values[key .. "X"] .. "," .. values[key .. "Y"]
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
    local listKey, lane = Display.ListKey(scope, container), container.kind == "lane"
    values[listKey] = Read(config, listKey)
    parts[#parts + 1] = tostring(values[listKey])
    local c = { key = container.key, kind = container.kind, prefix = prefix, scope = scope.key, label = container.label,
        frame = container.frame, element = container.element }
    local size = V("Size")
    c.width, c.height = size, max(1, floor(size * V("HeightPercent") / 100 + .5))
    c.gap, c.perRow, c.growth, c.max, c.layer = V("Gap"), V("PerRow"), V("Growth"), V("Max"), V("Layer")
    local rows = lane and {} or Display.Rows(values, scope, container, preview)
    for _, row in ipairs(rows) do
        local ids = {}
        for id in pairs(row.ids) do ids[#ids + 1] = id end
        table.sort(ids)
        parts[#parts + 1] = table.concat(ids, ",") .. (row.any and "*" or "")
    end
    if lane then
        LaneTracking(c, values, prefix, container, scope)
        c.kinds = LaneKinds(config, scope, container, preview, parts)
    else
        Tracking(c, values, prefix, rows)
    end
    c.enabled = V("Visible") and (lane or #rows > 0)
    Geometry(c)
    Position(c, config, values, scope, container, V)
    parts[#parts + 1] = c.offsets or ""
    c.sort, c.reverse = V("Sort"), V("Order") == 2
    c.missing, c.missingAlpha = c.fixed and V("Missing"), V("MissingAlpha")
    c.crop = .07 + (1 - 100 / V("Zoom")) * .43
    c.alpha, c.tooltip, c.dispel, c.pandemic, c.swipe = V("Alpha") / 100, V("Tooltip"), V("Dispel"), V("Pandemic"), V("Swipe")
    c.timeText, c.stackText = V("TimeText"), V("StackText")
    c.text = { Time = Display.Text(values, prefix, "Time"), Stack = Display.Text(values, prefix, "Stack") }
    c.sig = table.concat(parts, "|")
    return c
end

-- The immutable plan of every container. signature: any change; style: the
-- settings every container shares; a container's sig: its own settings, so
-- the runtime touches only the containers an edit changed. used: the side
-- has an enabled container; lanes: one of them replaces a Blizzard list.
function Display.Plan(config, preview)
    local values, shared, signature = {}, {}, {}
    for _, key in ipairs(Display.SharedKeys) do
        values[key] = Read(config, key)
        shared[#shared + 1] = tostring(values[key])
    end
    local plan = { values = values, scopes = {}, used = {}, lanes = {}, style = table.concat(shared, "|") }
    signature[1] = plan.style
    for _, scope in ipairs(Display.Scopes) do
        local list = {}
        for _, container in ipairs(Display.Containers) do
            local c = Compile(config, values, scope, container, preview)
            list[#list + 1], signature[#signature + 1] = c, c.sig
            if c.enabled then
                plan.used[scope.key] = true
                if c.kinds then plan.lanes[scope.key] = true end
            end
        end
        plan.scopes[scope.key] = list
    end
    plan.signature = table.concat(signature, "#")
    return plan
end
