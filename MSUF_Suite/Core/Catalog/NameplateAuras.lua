local _, NS = ...
local B, Model = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates"), NS.NameplateAuraDisplay
local id, spec = "nameplates", NS.SuiteCatalog.nameplates
local POSITION_LIMIT = 2048
local rules = {
    B.Tooltip(B.Bool("auraDisplayEnabled", "Enable MSUF nameplate auras", false),
        "MSUF draws the Buffs and Debuffs made Visible here, Custom 1-3 and Dots on target. Off: only Blizzard's own nameplate auras."),
    B.Font("auraFont", "Aura font"),
    B.Choice("auraTextOutline", "Aura text outline", 2, { "None", "Outline", "Thick outline" }),
    B.Bool("auraTimeText", "Show aura countdown", true),
    B.Number("auraTimeSize", "Aura countdown size", 11, 6, 36),
    B.Color("auraTimeColor", "Aura countdown color", "ffffff"),
    B.Choice("auraTimePoint", "Aura countdown position", 5, NS.AnchorLabels),
    B.Number("auraTimeX", "Aura countdown X", 0, -50, 50),
    B.Number("auraTimeY", "Aura countdown Y", 0, -50, 50),
    B.Bool("auraStackText", "Show aura stacks", true),
    B.Number("auraStackSize", "Aura stack size", 11, 6, 36),
    B.Color("auraStackColor", "Aura stack color", "ffffff"),
    B.Choice("auraStackPoint", "Aura stack position", 9, NS.AnchorLabels),
    B.Number("auraStackX", "Aura stack X", -1, -50, 50),
    B.Number("auraStackY", "Aura stack Y", 1, -50, 50),
    B.Bool("auraSwipe", "Show aura cooldown swipe", true),
    B.Number("auraSwipeAlpha", "Aura cooldown swipe opacity (%)", 100, 0, 100, 5),
    B.Bool("auraDispelHighlight", "Highlight aura dispel types", true),
    B.Bool("auraEnrageHighlight", "Highlight enrage auras", true),
    B.Bool("auraPandemicHighlight", "Highlight aura pandemic window", false),
    B.Color("auraPandemicColor", "Aura pandemic color", "ff7026"),
    B.Number("auraHighlightSize", "Aura highlight thickness", 2, 1, 5),
}
B.Section(id, "auraDisplay", "Native aura appearance", rules)

-- A rule of one container. short: the label inside the container's own
-- workspace, where the Container bar already names it; the full label names
-- the container for search and resets.
local function Rule(rule, short, fields)
    rule.short = short
    for field, value in pairs(fields or {}) do rule[field] = value end
    return rule
end

local function PointLabels()
    local labels = { "Global setting" }
    for _, label in ipairs(NS.AnchorLabels) do labels[#labels + 1] = label end
    return labels
end

local function SetupRules(scope, container, prefix, L)
    if container.kind == "lane" then
        return { Rule(B.Tooltip(B.Bool(prefix .. "Visible", L("%s visible"), false),
            "On: MSUF draws these auras with the settings here and hides Blizzard's own list. Off: Blizzard keeps drawing them."),
            "Visible") }
    end
    local dots = container.kind == "dots"
    local fixed = { key = prefix .. "Display", values = { [1] = true } }
    local setup = { Rule(B.Bool(prefix .. "Visible", L("%s enabled"), false), "Enabled") }
    if not dots then setup[#setup + 1] = Rule(B.String(prefix .. "Name", L("%s container name"), "", 24), "Container name") end
    setup[#setup + 1] = Rule(B.Choice(prefix .. "Type", L("%s aura type"), scope.helpful and 1 or 2, Model.Types), "Aura type")
    setup[#setup + 1] = Rule(B.Tooltip(B.Choice(prefix .. "Display", L("%s display"), dots and 1 or 2, Model.Displays),
        "Fixed slots keep one place per tracked aura, in list order. Flow shows only active auras and packs them."), "Display")
    if dots and scope.key == "enemy" then
        setup[#setup + 1] = Rule(B.Choice(prefix .. "Source", L("%s tracked DoT selection"), 1, Model.Sources), "Tracked DoT selection")
    end
    setup[#setup + 1] = Rule(B.Bool(prefix .. "Missing", L("%s missing auras faded"), dots), "Show missing auras faded",
        { requiresChoice = fixed })
    setup[#setup + 1] = Rule(B.Number(prefix .. "MissingAlpha", L("%s placeholder opacity (percent)"), 25, 5, 80, 5),
        "Placeholder opacity", { enableKey = prefix .. "Missing", requiresChoice = fixed })
    return setup
end

local function LayoutRules(container, prefix, L)
    local layout = {
        Rule(B.Choice(prefix .. "Anchor", L("%s anchor"), container.anchor or 2, NS.AnchorLabels), "Anchor"),
        Rule(B.Choice(prefix .. "Growth", L("%s growth direction"), container.growth or 1, Model.Growth), "Growth"),
        Rule(B.Number(prefix .. "Max", L("%s maximum icons"), 8, 1, Model.MAX_ICONS), "Max"),
        Rule(B.Number(prefix .. "Size", L("%s icon size"), 24, 10, 80), "Size"),
        Rule(B.Number(prefix .. "HeightPercent", L("%s icon height (percent)"), 100, 25, 200, 5), "Icon height (percent)"),
        Rule(B.Number(prefix .. "PerRow", L("%s icons per row"), 8, 1, 40), "Per row"),
        Rule(B.Number(prefix .. "Gap", L("%s icon spacing"), 2, 0, 20), "Gap"),
        Rule(B.Number(prefix .. "Layer", L("%s layer"), 5, 0, 30), "Layer (0-30)"),
    }
    -- A lane keeps the offsets of Blizzard's list (the same preview handle).
    if container.y then
        layout[#layout + 1] = B.Number(prefix .. "OffsetX", L("%s X"), 0, -POSITION_LIMIT, POSITION_LIMIT)
        layout[#layout + 1] = B.Number(prefix .. "OffsetY", L("%s Y"), container.y, -POSITION_LIMIT, POSITION_LIMIT)
    end
    return layout
end

local function BehaviorRules(scope, container, prefix, L)
    -- Fixed slots keep the list order; a lane always packs its auras.
    local lane = container.kind == "lane"
    local flow = not lane and { requiresChoice = { key = prefix .. "Display", values = { [2] = true } } } or nil
    local mine = container.kind == "dots" or lane and scope.key == "enemy" and container.key == "debuff"
    local behavior = {}
    if lane then behavior[1] = Rule(B.Choice(prefix .. "Filter", L("%s filter"), 1, Model.Filters), "Show") end
    for _, rule in ipairs({
        Rule(B.Choice(prefix .. "Sort", L("%s sorting"), 1, Model.Sorts), "Sort By", flow),
        Rule(B.Choice(prefix .. "Order", L("%s sort order"), 1, Model.Orders), "Order", flow),
        Rule(B.Bool(prefix .. "OnlyMine", L("%s only my auras"), mine), "Only mine"),
        Rule(B.Bool(prefix .. "HidePermanent", L("%s hide permanent auras"), false), "Hide permanent"),
        Rule(B.Tooltip(B.Number(prefix .. "MaxDuration", L("%s maximum duration (seconds)"), 0, 0, 180, 5),
            "Hides auras that last longer. 0 shows every duration."), "Maximum duration"),
    }) do behavior[#behavior + 1] = rule end
    return behavior
end

local function StyleRules(prefix, L)
    local points = PointLabels()
    return {
        Rule(B.Bool(prefix .. "Pandemic", L("%s pandemic state"), true), "Show Pandemic State"),
        Rule(B.Number(prefix .. "Zoom", L("%s icon zoom (percent)"), 100, 100, 200, 5), "Icon Zoom (%)"),
        Rule(B.Number(prefix .. "Alpha", L("%s opacity (percent)"), 100, 10, 100, 5), "Opacity"),
        Rule(B.Bool(prefix .. "Tooltip", L("%s tooltip"), true), "Tooltip"),
        Rule(B.Bool(prefix .. "Dispel", L("%s dispel-type border"), true), "Dispel-type Border"),
        Rule(B.Bool(prefix .. "StackText", L("%s stack count"), true), "Stack count"),
        Rule(B.Choice(prefix .. "StackPoint", L("%s stack anchor"), 1, points), "Stack anchor", { enableKey = prefix .. "StackText" }),
        Rule(B.Tooltip(B.Number(prefix .. "StackSize", L("%s stack size"), 0, 0, 36), "0 uses the global aura stack size."),
            "Stack size", { enableKey = prefix .. "StackText" }),
        Rule(B.Bool(prefix .. "TimeText", L("%s cooldown text"), true), "Cooldown text"),
        Rule(B.Choice(prefix .. "TimePoint", L("%s cooldown anchor"), 1, points), "Cooldown anchor", { enableKey = prefix .. "TimeText" }),
        Rule(B.Tooltip(B.Number(prefix .. "TimeSize", L("%s cooldown text size"), 0, 0, 36), "0 uses the global aura countdown size."),
            "Cooldown text size", { enableKey = prefix .. "TimeText" }),
        Rule(B.Bool(prefix .. "Swipe", L("%s cooldown swipe"), true), "Cooldown swipe"),
    }
end

-- One list per client (NameplateAuraDisplay.lua): only this client's list
-- has a control, both travel with the profile.
local function ListRules(scope, container, name)
    local lists = {}
    for _, client in ipairs(Model.Clients) do
        local label = NS.Text("%s aura IDs (%s)"):format(name, NS.Text(client.label))
        lists[#lists + 1] = Rule(B.String(Model.ListKey(scope, container, client.id), label, "", Model.LIST_BYTES), nil,
            { hidden = true, ids = true, client = client.client })
    end
    return lists
end

local sections = { auraDisplay = true }
for _, scope in ipairs(Model.Scopes) do
    for _, container in ipairs(Model.Containers) do
        local prefix = Model.Prefix(scope, container)
        local name = NS.Text("%s: %s"):format(NS.Text(scope.label), NS.Text(container.label))
        local function L(format) return NS.Text(format):format(name) end
        sections[prefix] = true
        for _, list in ipairs({ SetupRules(scope, container, prefix, L), LayoutRules(container, prefix, L),
            BehaviorRules(scope, container, prefix, L), StyleRules(prefix, L), ListRules(scope, container, name) }) do
            B.Section(id, prefix, name, list)
        end
    end
end
B.Add(id, B.Tooltip(B.Bool("auraSunder", "Show Sunder Armor stacks on WoW Forever", false),
    "Adds a fixed Sunder Armor slot for auras from any player on WoW Forever. Blizzard supplies its stack count and duration."),
    "auraEnemyDots", NS.Text("%s: %s"):format(NS.Text("Enemy"), NS.Text("Dots on target")))

-- The shared appearance belongs to the look; a container's content and
-- placement are the player's own and survive a look change.
for _, rule in ipairs(spec.controls) do
    if sections[rule.section] then
        if rule.key ~= "auraDisplayEnabled" and not rule.enableKey then rule.enableKey = "auraDisplayEnabled" end
        if rule.section == "auraDisplay" then
            spec.look.visualKeys[rule.key] = true
            for _, preset in pairs(spec.look.presets) do preset[rule.key] = rule.default end
        end
    end
end
spec.rules.auraPandemicColor.enableKey = "auraPandemicHighlight"
spec.rules.auraSwipeAlpha.enableKey = "auraSwipe"
spec.rules.auraSunder.client = "forever"
