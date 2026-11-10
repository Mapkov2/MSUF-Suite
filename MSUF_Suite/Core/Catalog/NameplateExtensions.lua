local _, NS = ...
local B, X = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates"), NS.NameplateExtensions
local id = "nameplates"

local function Enabled(rule, key)
    rule.enableKey = key
    return rule
end

local casting = {
    B.Bool("interruptFeedbackEnabled", "Customize interrupted-cast feedback", false),
    Enabled(B.Number("interruptFeedbackDuration", "Interrupted feedback duration (seconds)", 1.2, .1, 5, .1), "interruptFeedbackEnabled"),
    Enabled(B.Color("interruptFeedbackColor", "Interrupted feedback color", "ff5050"), "interruptFeedbackEnabled"),
    Enabled(B.Bool("interruptFeedbackFlash", "Flash interrupted-cast feedback", false), "interruptFeedbackEnabled"),
    Enabled(B.Bool("interruptFeedbackWho", "Show who interrupted the cast", true), "interruptFeedbackEnabled"),
}
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
    B.Bool("targetClassResources", "Anchor Blizzard class resources to the target nameplate", false),
})

B.Section(id, "plateInteraction", "Click area and spell range", {
    B.Bool("plateClickboxEnabled", "Customize the nameplate click area", false),
    Enabled(B.Number("plateClickboxWidth", "Click area width (px)", 140, 20, 500), "plateClickboxEnabled"),
    Enabled(B.Number("plateClickboxHeight", "Click area height (px)", 40, 5, 200), "plateClickboxEnabled"),
    B.Bool("friendlyPlateClickThrough", "Click through friendly nameplates", false),
    B.Bool("plateRangeEnabled", "Fade nameplates by spell range", false),
    Enabled(B.Number("plateRangeSpell", "Range-check spell ID", 0, 0, 10000000), "plateRangeEnabled"),
    Enabled(B.Number("plateRangeAlpha", "Out-of-range opacity (%)", 40, 0, 100, 5), "plateRangeEnabled"),
    Enabled(B.Number("plateRangeUnknownAlpha", "Unknown-range opacity (%)", 100, 0, 100, 5), "plateRangeEnabled"),
    Enabled(B.Bool("plateRangeText", "Show in-range, out-of-range or unknown text", false), "plateRangeEnabled"),
})

B.Section(id, "threatDetail", "Threat warning detail", {
    Enabled(B.Bool("enemyThreatTransitionEnabled", "Separate orange threat warnings", false), "enemyRoleColors"),
    Enabled(B.Color("enemyThreatTransitionColor", "Orange threat warning", "ff9900"), "enemyThreatTransitionEnabled"),
})

local context = { B.Bool("plateContextEnabled", "Customize nameplates by unit type and location", false) }
for _, kind in ipairs(X.Kinds) do
    local key, label = kind.key, NS.Text(kind.label)
    context[#context + 1] = Enabled(B.Number(key .. "Opacity", NS.Text("%s opacity (%%)"):format(label), 100, 0, 100, 5), "plateContextEnabled")
    context[#context + 1] = Enabled(B.Number(key .. "Scale", NS.Text("%s scale (%%)"):format(label), 100, 50, 200, 5), "plateContextEnabled")
    context[#context + 1] = Enabled(B.Choice(key .. "CastVisibility", NS.Text("%s casting visibility"):format(label), 1,
        { "Always visible", "Visible while casting", "Visible while not casting" }), "plateContextEnabled")
    for _, location in ipairs(X.Contexts) do
        context[#context + 1] = Enabled(B.Bool(key .. location.key .. "Visible",
            NS.Text("Show %s in %s"):format(label, NS.Text(location.label)), true), "plateContextEnabled")
    end
end
B.Section(id, "plateContext", "Unit types and locations", context)

for i = 1, 4 do
    local key = "extraText" .. i
    B.Section(id, key, NS.Text("Extra text %d"):format(i), {
        B.Choice(key .. "Source", "Text source", 1, X.TextSources),
        B.Choice(key .. "Side", "Show text on", 1, { "Enemy and friendly nameplates", "Enemy nameplates", "Friendly nameplates" }),
        B.Choice(key .. "Anchor", "Text anchor", i == 1 and 1 or 2, X.TextAnchors),
        B.Number(key .. "X", "Text X", 0, -2048, 2048),
        B.Number(key .. "Y", "Text Y", (i - 1) * -12, -2048, 2048),
        B.Number(key .. "Size", "Text size", 10, 6, 32),
        B.Color(key .. "Color", "Text color", "ffffff"),
        B.Bool(key .. "Unknown", "Show a question mark when data is unavailable", false),
    })
end

-- Added after the legacy looks were captured. Every look must include the
-- neutral defaults so switching back to a preset also clears extensions.
local spec = NS.SuiteCatalog[id]
for _, rule in ipairs(spec.controls) do
    if rule.section == "castExtensions" or rule.section == "combatExtensions" or rule.section == "plateInteraction"
        or rule.section == "plateContext" or rule.section == "threatDetail" or rule.section == "plateIdentity"
        or rule.section and rule.section:match("^extraText%d$") then
        spec.look.visualKeys[rule.key] = true
        for _, preset in pairs(spec.look.presets) do preset[rule.key] = rule.default end
    end
end
