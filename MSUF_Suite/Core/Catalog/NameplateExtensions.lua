local _, NS = ...
local B, X = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates"), NS.NameplateExtensions
local id = "nameplates"

local function Enabled(rule, key)
    rule.enableKey = key
    return rule
end

local function AddBarFinishRules(key, enabled, strength, color, gloss, glossStrength)
    local rules = {
        enabled, strength, color,
        B.Bool(key .. "DirLeft", "Gradient left", false),
        B.Bool(key .. "DirRight", "Gradient right", true),
        B.Bool(key .. "DirUp", "Gradient up", false),
        B.Bool(key .. "DirDown", "Gradient down", false),
    }
    for i = 2, #rules do rules[i].enableKey = rules[1].key end
    rules[#rules + 1] = gloss
    rules[#rules + 1] = Enabled(glossStrength, gloss.key)
    for _, rule in ipairs(rules) do
        rule.requiresChoice = { key = "look", values = { [1] = true, [3] = true, [4] = true } }
    end
    B.Section(id, "barGradients", "Bar gradient", rules)
end
AddBarFinishRules("healthGradient", B.Bool("healthGradientEnabled", "Health gradient", false),
    B.Number("healthGradientStrength", "Health strength", 45, 0, 100, 5),
    B.Color("healthGradientColor", "Health gradient color", "000000"),
    B.Bool("healthGlossEnabled", "Health gloss", false),
    B.Number("healthGlossStrength", "Health gloss strength", 50, 0, 100, 5))
AddBarFinishRules("powerGradient", B.Bool("powerGradientEnabled", "Power gradient", false),
    B.Number("powerGradientStrength", "Power strength", 45, 0, 100, 5),
    B.Color("powerGradientColor", "Power gradient color", "000000"),
    B.Bool("powerGlossEnabled", "Power gloss", false),
    B.Number("powerGlossStrength", "Power gloss strength", 50, 0, 100, 5))

B.Section(id, "barGradients", "Textures & Gradient", {
    B.Bool("barsOverride", "Use custom settings for this scope", false),
    B.Bool("barsOverrideSaved", "Custom", false),
    B.Texture("powerFillTexture", "Power bar texture"),
    B.Texture("powerBackgroundTexture", "Power background texture"),
})
NS.SuiteCatalog[id].rules.barsOverrideSaved.hidden = true

local casting = {
    B.Bool("interruptFeedbackEnabled", "Customize interrupted-cast feedback", false),
    Enabled(B.Bool("interruptFeedbackShared", "Use shared interrupt color and duration", true), "interruptFeedbackEnabled"),
    Enabled(B.Number("interruptFeedbackDuration", "Interrupted feedback duration (seconds)", 1.2, .1, 5, .1), "interruptFeedbackEnabled"),
    Enabled(B.Color("interruptFeedbackColor", "Interrupted feedback color", "ff5050"), "interruptFeedbackEnabled"),
    Enabled(B.Bool("interruptFeedbackFlash", "Flash interrupted-cast feedback", false), "interruptFeedbackEnabled"),
    Enabled(B.Bool("interruptFeedbackWho", "Show who interrupted the cast", true), "interruptFeedbackEnabled"),
}
casting[3].disabledBy, casting[4].disabledBy = "interruptFeedbackShared", "interruptFeedbackShared"
for _, prefix in ipairs({ "enemy", "friendly" }) do
    casting[#casting + 1] = B.Choice(prefix .. "NameDuringCast", prefix == "enemy" and "Enemy name while casting" or "Friendly name while casting",
        1, { "Keep name visible", "Dim name", "Hide name" })
    casting[#casting + 1] = B.Number(prefix .. "NameCastAlpha",
        prefix == "enemy" and "Enemy casting-name opacity (%)" or "Friendly casting-name opacity (%)", 35, 0, 100, 5)
    casting[#casting + 1] = B.Bool(prefix .. "CastForeground",
        prefix == "enemy" and "Draw enemy castbar in foreground" or "Draw friendly castbar in foreground", false)
    casting[#casting + 1] = B.Choice(prefix .. "CastIconRelativeAnchor",
        prefix == "enemy" and "Enemy spell-icon anchor" or "Friendly spell-icon anchor", 1, X.CastIconAnchors)
    casting[#casting + 1] = B.Choice(prefix .. "RaidRelativeAnchor",
        prefix == "enemy" and "Enemy raid-marker anchor" or "Friendly raid-marker anchor", 1, X.RaidAnchors)
    casting[#casting].enableKey = prefix .. "RaidIcon"
end
B.Section(id, "castExtensions", "Cast feedback and relative anchors", casting)

local identity = {}
for _, prefix in ipairs({ "enemy", "friendly" }) do
    identity[#identity + 1] = B.Choice(prefix .. "IdentityIcons",
        prefix == "enemy" and "Enemy player icons" or "Friendly player icons", 1, X.IdentityIcons)
    identity[#identity + 1] = B.Number(prefix .. "IdentityIconSize",
        prefix == "enemy" and "Enemy player icon size" or "Friendly player icon size", 14, 8, 40)
    identity[#identity + 1] = B.Number(prefix .. "IdentityIconX",
        prefix == "enemy" and "Enemy player icon X" or "Friendly player icon X", -3, -2048, 2048)
    identity[#identity + 1] = B.Number(prefix .. "IdentityIconY",
        prefix == "enemy" and "Enemy player icon Y" or "Friendly player icon Y", 0, -2048, 2048)
end
B.Section(id, "plateIdentity", "Player identity icons", identity)

B.Section(id, "combatExtensions", "Combat emphasis", {
    B.Bool("focusScaleEnabled", "Scale the focused nameplate", false),
    Enabled(B.Number("focusScalePercent", "Focus nameplate scale (%)", 110, 50, 200, 5), "focusScaleEnabled"),
    B.Bool("castingScaleEnabled", "Scale casting nameplates", false),
    Enabled(B.Number("castingScalePercent", "Casting nameplate scale (%)", 110, 50, 200, 5), "castingScaleEnabled"),
    B.Bool("focusReminderEnabled", "Remind me to focus casters and lieutenants", false),
    Enabled(B.Color("focusReminderColor", "Focus reminder color", "ffb833"), "focusReminderEnabled"),
    B.Bool("executePulseEnabled", "Pulse enemies below execute health", false),
    Enabled(B.Number("executePulsePercent", "Execute health threshold (%)", 20, 1, 99), "executePulseEnabled"),
    Enabled(B.Number("executePulseAlpha", "Execute pulse opacity (%)", 60, 0, 100, 5), "executePulseEnabled"),
    Enabled(B.Color("executePulseColor", "Execute pulse color", "ff3030"), "executePulseEnabled"),
})

local scopeLabels = { enemy = "Enemy", neutral = "Neutral", friendly = "Friendly", friendlyNpc = "Friendly NPC" }
for _, scope in ipairs(X.OpacityScopes) do
    local click, range = scope .. "ClickboxEnabled", scope .. "RangeEnabled"
    local rules = {
        B.Bool(click, "Customize the nameplate click area", false),
        Enabled(B.Number(scope .. "ClickboxWidth", "Click area width (px)", 140, 20, 500), click),
        Enabled(B.Number(scope .. "ClickboxHeight", "Click area height (px)", 40, 5, 200), click),
        B.Bool(range, "Fade nameplates by spell range", false),
        Enabled(B.Number(scope .. "RangeSpell", "Range-check spell ID", 0, 0, 10000000), range),
        Enabled(B.Number(scope .. "RangeAlpha", "Out-of-range opacity (%)", 40, 0, 100, 5), range),
        Enabled(B.Number(scope .. "RangeUnknownAlpha", "Unknown-range opacity (%)", 100, 0, 100, 5), range),
        Enabled(B.Bool(scope .. "RangeText", "Show in-range, out-of-range or unknown text", false), range),
    }
    if scope == "friendly" or scope == "friendlyNpc" then
        rules[#rules + 1] = B.Bool(scope .. "PlateClickThrough", "Click through friendly nameplates", false)
    end
    B.Section(id, "plateInteraction", NS.Text("%s: %s"):format(NS.Text(scopeLabels[scope]), NS.Text("Click area and spell range")), rules)
end

B.Section(id, "threatDetail", "Threat warning detail", {
    Enabled(B.Bool("enemyThreatTransitionEnabled", "Separate orange threat warnings", false), "enemyRoleColors"),
    Enabled(B.Color("enemyThreatTransitionColor", "Orange threat warning", "ff9900"), "enemyThreatTransitionEnabled"),
})

local legacyContext = B.Bool("plateContextEnabled", "Customize nameplates by unit type and location", false)
local legacyNeutral = B.Bool("neutralNpcContextOverride", "Customize neutral visibility and opacity", false)
legacyContext.hidden, legacyNeutral.hidden = true, true
local context = { legacyContext, legacyNeutral, B.Bool("neutralNpcVisible", "Show neutral nameplates", true) }
for _, scope in ipairs(X.OpacityScopes) do
    context[#context + 1] = B.Bool(X.ContextKeys[scope], legacyContext.label, false)
end
local dimensions = {}
for _, kind in ipairs({ "neutralNpc", "friendlyNpc" }) do
    local toggle = kind .. "SizeOverride"
    dimensions[#dimensions + 1] = B.Bool(toggle, "Use separate health bar dimensions", false)
    dimensions[#dimensions + 1] = Enabled(B.Number(kind .. "HealthWidthDelta", "Health bar width adjustment (px)", 0, -30, 160), toggle)
    dimensions[#dimensions + 1] = Enabled(B.Number(kind .. "HealthHeightDelta", "Health bar height adjustment (px)", 0, -4, 24), toggle)
end
B.Section(id, "plateDimensions", "Health bar dimensions", dimensions)
local nameOnly = { Enabled(B.Bool("enemyPlateNameClassColor", "Class color for player names", false), "enemyPlateNameOnly") }
for _, scope in ipairs({ "enemy", "neutral", "friendlyNpc" }) do
    local toggle = scope .. "PlateNameOnly"
    local color = B.Bool(scope .. "PlateNameTypeColor", "Color name by NPC type", false)
    if scope == "friendlyNpc" then
        color.requiresChoice = { key = "friendlyNPCs", values = { [X.NPC_PLATE_NAME_ONLY] = true } }
    else
        local choices = { "Health bars", "Name only" }
        if scope == "neutral" then
            choices[3], choices[4] = "Health bars for attackable units", "Name only for attackable units"
        end
        nameOnly[#nameOnly + 1] = B.Choice(toggle, "Display", false, choices)
        color.enableKey = toggle
    end
    nameOnly[#nameOnly + 1] = color
end
local neutralMode = B.Choice("neutralNameOnlyMode", "Display", 1,
    { "Name only", "Health bars for attackable units", "Name only for attackable units" })
neutralMode.hidden = true
nameOnly[#nameOnly + 1] = neutralMode
for _, scope in ipairs(X.OpacityScopes) do
    nameOnly[#nameOnly + 1] = B.Tooltip(B.Bool(scope .. "CenterName", "Auto center above unit", false),
        "Center the name above the nameplate in Name only mode.")
end
B.Section(id, "plateNameOnly", "Name only", nameOnly)
for _, kind in ipairs(X.Kinds) do
    local key, label = kind.key, NS.Text(kind.label)
    local enabled = X.ContextKeys[X.OpacityScope(key)]
    context[#context + 1] = Enabled(B.Number(key .. "Opacity", NS.Text("%s opacity (%%)"):format(label), 100, 0, 100, 5), enabled)
    context[#context + 1] = Enabled(B.Number(key .. "Scale", NS.Text("%s scale (%%)"):format(label), 100, 50, 200, 5), enabled)
    context[#context + 1] = Enabled(B.Choice(key .. "CastVisibility", NS.Text("%s casting visibility"):format(label), 1,
        { "Always visible", "Visible while casting", "Visible while not casting" }), enabled)
    for _, location in ipairs(X.Contexts) do
        context[#context + 1] = Enabled(B.Bool(key .. location.key .. "Visible",
            NS.Text("Show %s in %s"):format(label, NS.Text(location.label)), true), enabled)
    end
end
B.Section(id, "plateContext", "Unit types and locations", context)

local enemyVisibility = {}
for _, condition in ipairs(X.EnemyConditions) do
    local rule = B.Bool(condition.key, condition.label, false)
    rule.client = condition.client
    if condition.replacedByHealth then
        rule.disabledBy = "enemyShowWhenInjured"
    end
    enemyVisibility[#enemyVisibility + 1] = rule
end
B.Section(id, "enemyLoadConditions", "Visibility", enemyVisibility)

for _, scope in ipairs(X.OpacityScopes) do
    local key = scope .. "Fade"
    local rules = {
        B.Number(key .. "Health", "Health foreground opacity (%)", 100, 0, 100, 5),
        B.Number(key .. "HealthBackground", "Health background opacity (%)", 100, 0, 100, 5),
        B.Bool(key .. "KeepText", "Keep text visible", false),
        B.Bool(key .. "KeepPrediction", "Keep absorbs and prediction visible", false),
        B.Bool(key .. "OutOfCombat", "Fade nameplates out of combat", false),
        Enabled(B.Number(key .. "OutOfCombatAlpha", "Out of Combat Opacity", 50, 0, 100, 5), key .. "OutOfCombat"),
    }
    if scope == "enemy" or scope == "neutral" then
        rules[#rules + 1] = Enabled(B.Number(key .. "Power", "Resource foreground opacity (%)", 100, 0, 100, 5), "enemyPowerEnabled")
        rules[#rules + 1] = Enabled(B.Number(key .. "PowerBackground", "Resource background opacity (%)", 100, 0, 100, 5), "enemyPowerEnabled")
    end
    B.Section(id, "plateOpacity", "Opacity", rules)
end

for _, scope in ipairs(X.OpacityScopes) do
    local sectionTitle = NS.Text("%s: %s"):format(NS.Text(scopeLabels[scope]), NS.Text("Status icons"))
    for source = X.FirstTextSource, X.LastTextSource do
        local key = X.TextKey(scope, source)
        local item = X.TextIndicators[source]
        local label = NS.Text(item.label)
        local rules = {
            B.Bool(key, NS.Text("Show %s"):format(label), false),
            B.Choice(key .. "Anchor", NS.Text("%s anchor"):format(label), item.anchor, X.TextAnchors),
            B.Number(key .. "X", NS.Text("%s X"):format(label), 0, -2048, 2048),
            B.Number(key .. "Y", NS.Text("%s Y"):format(label), item.y, -2048, 2048),
            B.Number(key .. "Size", NS.Text("%s size"):format(label), 10, 6, 48),
            B.Color(key .. "Color", NS.Text("%s color"):format(label), "ffffff"),
            B.Bool(key .. "Unknown", "Show a question mark when data is unavailable", false),
        }
        if item.layer then rules[#rules + 1] = B.Number(key .. "Layer", NS.Text("%s layer"):format(label), item.layer, 0, 30) end
        B.Section(id, "plateExtraText", sectionTitle, rules)
    end
end

-- Added after the legacy looks were captured. Every look must include the
-- neutral defaults so switching back to a preset also clears extensions.
local spec = NS.SuiteCatalog[id]
local prepare = spec.prepareConfig
spec.prepareConfig = function(config)
    if prepare then prepare(config) end
    X.SeparateContexts(config)
end
local look = spec.look
for _, rule in ipairs(spec.controls) do
    if rule.section == "barGradients" then
        local key, value = rule.key, rule.default
        local override = key == "barsOverride" or key == "barsOverrideSaved"
        if override then value = true else look.visualKeys[key] = true end
        look.presets[1][key], look.presets[4][key] = value, value
    elseif rule.section == "castExtensions" or rule.section == "combatExtensions" or rule.section == "plateInteraction"
        or rule.section == "plateContext" or rule.section == "plateDimensions" or rule.section == "threatDetail" or rule.section == "plateIdentity"
        or rule.section == "plateExtraText" then
        look.visualKeys[rule.key] = true
        for _, preset in pairs(look.presets) do preset[rule.key] = rule.default end
    end
end
