local _, NS = ...
local B, Model = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates"), NS.NameplateAuraDisplay
local id, spec = "nameplates", NS.SuiteCatalog.nameplates
local POSITION_LIMIT = 2048
local rules = {
    B.Tooltip(B.Bool("auraDisplayEnabled", "Enable custom aura rows", false),
        "Shows the enabled Custom 1–3 and Dots on target rows."),
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
B.Section(id, "auraDisplay", "Shared aura appearance", rules)
local emphasisLabels = { "Enlarge these spells", "Glow for these spells", "Pandemic glow for these spells" }
local emphasis = {}
local emphasisHelp = "Enter spell IDs separated by commas. Applies to spells in your tracked aura rows."
for index, entry in ipairs(NS.NameplateAuraEmphasis.flags) do
    for _, client in ipairs(Model.Clients) do
        local rule = B.Tooltip(B.String(entry.key .. client.id, emphasisLabels[index], "", Model.LIST_BYTES), emphasisHelp)
        rule.hidden = client.id ~= Model.Client
        emphasis[#emphasis + 1] = rule
    end
end
B.Section(id, "auraSpellEmphasis", "Tracked spell emphasis", emphasis)

-- A rule of one container. short: the label inside the container's own
-- workspace, where the Container bar already names it; the full label names
-- the container for search and resets.
local function Rule(rule, short, fields)
    rule.short = short
    for field, value in pairs(fields or {}) do rule[field] = value end
    return rule
end

local function ClickthroughRule(prefix, name)
    local label = "Let clicks pass through nameplate auras"
    return Rule(B.Choice(prefix .. "Clickthrough", NS.Text("%s: %s"):format(name, NS.Text(label)), 1,
        Model.ClickthroughChoices), label)
end

local function PointLabels()
    local labels = { "Global setting" }
    for _, label in ipairs(NS.AnchorLabels) do labels[#labels + 1] = label end
    return labels
end

local function SetupRules(scope, container, prefix, L)
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
    setup[#setup + 1] = Rule(B.Tooltip(B.Bool(prefix .. "HideDuplicates", L("%s hide duplicate auras"), false),
        "Hides verified duplicates. Both icons can remain visible when aura data is protected."),
        "Hide duplicate auras", { enableKey = prefix .. "Visible" })
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
    layout[#layout + 1] = B.Number(prefix .. "OffsetX", L("%s X"), 0, -POSITION_LIMIT, POSITION_LIMIT)
    layout[#layout + 1] = B.Number(prefix .. "OffsetY", L("%s Y"), container.y, -POSITION_LIMIT, POSITION_LIMIT)
    return layout
end

local function BehaviorRules(container, prefix, L)
    local flow = { requiresChoice = { key = prefix .. "Display", values = { [2] = true } } }
    return {
        Rule(B.Choice(prefix .. "Sort", L("%s sorting"), 1, Model.Sorts), "Sort By", flow),
        Rule(B.Choice(prefix .. "Order", L("%s sort order"), 1, Model.Orders), "Order", flow),
        Rule(B.Bool(prefix .. "OnlyMine", L("%s only my auras"), container.kind == "dots"), "Only mine"),
        Rule(B.Bool(prefix .. "HidePermanent", L("%s hide permanent auras"), false), "Hide permanent"),
        Rule(B.Tooltip(B.Number(prefix .. "MaxDuration", L("%s maximum duration (seconds)"), 0, 0, 180, 5),
            "Hides auras that last longer. 0 shows every duration."), "Maximum duration"),
    }
end

local function StyleRules(prefix, L, name)
    local points = PointLabels()
    return {
        Rule(B.Tooltip(B.Bool(prefix .. "IconSkin", L("%s use MSUF icon skin"), false),
            "Uses the default rectangular Icon Skin from MSUF when available."), "Use MSUF icon skin"),
        Rule(B.Bool(prefix .. "Pandemic", L("%s pandemic state"), true), "Show Pandemic State"),
        Rule(B.Number(prefix .. "Zoom", L("%s icon zoom (percent)"), 100, 100, 200, 5), "Icon Zoom (%)"),
        Rule(B.Number(prefix .. "Alpha", L("%s opacity (percent)"), 100, 10, 100, 5), "Opacity"),
        Rule(B.Bool(prefix .. "Tooltip", L("%s tooltip"), true), "Tooltip"),
        ClickthroughRule(prefix, name),
        Rule(B.Number(prefix .. "Padding", L("%s lane padding"), 0, 0, 16), "Lane Padding"),
        Rule(B.Bool(prefix .. "Dispel", L("%s dispel-type border"), true), "Dispel-type Border"),
        Rule(B.Bool(prefix .. "StackText", L("%s stack count"), true), "Stack count"),
        Rule(B.Choice(prefix .. "StackPoint", L("%s stack anchor"), 1, points), "Stack anchor", { enableKey = prefix .. "StackText" }),
        Rule(B.Tooltip(B.Number(prefix .. "StackSize", L("%s stack size"), 0, 0, 36), "0 uses the global aura stack size."),
            "Stack size", { enableKey = prefix .. "StackText" }),
        Rule(B.Bool(prefix .. "TimeText", L("%s cooldown text"), true), "Cooldown text"),
        Rule(B.Tooltip(B.Number(prefix .. "TimeDecimals", L("%s cooldown decimals below seconds"), 0, 0, 30),
            "Show one decimal place below this many seconds. Set 0 for the standard countdown."),
            "Decimals below sec", { enableKey = prefix .. "TimeText" }),
        Rule(B.Choice(prefix .. "TimePoint", L("%s cooldown anchor"), 1, points), "Cooldown anchor", { enableKey = prefix .. "TimeText" }),
        Rule(B.Tooltip(B.Number(prefix .. "TimeSize", L("%s cooldown text size"), 0, 0, 36), "0 uses the global aura countdown size."),
            "Cooldown text size", { enableKey = prefix .. "TimeText" }),
        Rule(B.Number(prefix .. "StackX", L("%s stack text X"), 0, -50, 50), "Stack X", { enableKey = prefix .. "StackText" }),
        Rule(B.Number(prefix .. "StackY", L("%s stack text Y"), 0, -50, 50), "Stack Y", { enableKey = prefix .. "StackText" }),
        Rule(B.Number(prefix .. "TimeX", L("%s cooldown text X"), 0, -50, 50), "Cooldown X", { enableKey = prefix .. "TimeText" }),
        Rule(B.Number(prefix .. "TimeY", L("%s cooldown text Y"), 0, -50, 50), "Cooldown Y", { enableKey = prefix .. "TimeText" }),
        Rule(B.Bool(prefix .. "Swipe", L("%s cooldown swipe"), true), "Cooldown swipe"),
        Rule(B.Choice(prefix .. "SwipeDirection", L("%s swipe direction"), 1, { "Reversed", "Normal" }), "Swipe direction",
            { enableKey = prefix .. "Swipe" }),
        Rule(B.Bool(prefix .. "DurationBar", L("%s duration bar"), false), "Duration bar"),
        Rule(B.Choice(prefix .. "DurationBarDisplay", L("%s duration bar display"), 1, { "Icon + Bar", "Bar Only" }),
            "Bar display", { enableKey = prefix .. "DurationBar" }),
        Rule(B.Number(prefix .. "DurationBarHeight", L("%s duration bar height"), 2, 1, 16), "Height",
            { enableKey = prefix .. "DurationBar" }),
        Rule(B.Choice(prefix .. "DurationBarPosition", L("%s duration bar position"), 1, { "Bottom", "Top" }), "Position",
            { enableKey = prefix .. "DurationBar" }),
        Rule(B.Choice(prefix .. "DurationBarDirection", L("%s duration bar direction"), 1, { "Remaining time", "Elapsed time" }),
            "Direction", { enableKey = prefix .. "DurationBar" }),
        Rule(B.Color(prefix .. "DurationBarColor", L("%s duration bar color"), "b180e0"), "Duration bar color",
            { enableKey = prefix .. "DurationBar" }),
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
    for _, row in ipairs(Model.NativeRows) do
        local prefix = Model.Prefix(scope, row)
        local name = NS.Text("%s: %s"):format(NS.Text(scope.label), NS.Text(row.label))
        local clickthrough = ClickthroughRule(prefix, name)
        B.Section(id, prefix, name, {
            Rule(B.Number(prefix .. "Scale", NS.Text("%s icon size (percent)"):format(name), 100, 50, 200, 5), "Icon size (%)"),
            Rule(B.Number(prefix .. "Layer", NS.Text("%s layer"):format(name), 0, 0, 30), "Layer (0-30)"),
            Rule(B.Number(prefix .. "Alpha", NS.Text("%s opacity (percent)"):format(name), 100, 10, 100, 5), "Opacity"),
            clickthrough,
        })
        spec.look.visualKeys[clickthrough.key] = true
        for _, preset in pairs(spec.look.presets) do preset[clickthrough.key] = clickthrough.default end
    end
    for _, container in ipairs(Model.Containers) do
        local prefix = Model.Prefix(scope, container)
        local name = NS.Text("%s: %s"):format(NS.Text(scope.label), NS.Text(container.label))
        local function L(format) return NS.Text(format):format(name) end
        sections[prefix] = true
        for _, list in ipairs({ SetupRules(scope, container, prefix, L), LayoutRules(container, prefix, L),
            BehaviorRules(container, prefix, L), StyleRules(prefix, L, name), ListRules(scope, container, name) }) do
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
        if rule.section ~= "auraDisplay" and not rule.enableKey then rule.enableKey = "auraDisplayEnabled" end
        if rule.section == "auraDisplay" then
            spec.look.visualKeys[rule.key] = true
            for _, preset in pairs(spec.look.presets) do preset[rule.key] = rule.default end
        end
    end
end
spec.rules.auraPandemicColor.enableKey = "auraPandemicHighlight"
spec.rules.auraSwipeAlpha.enableKey = "auraSwipe"
spec.rules.auraSunder.client = "forever"
