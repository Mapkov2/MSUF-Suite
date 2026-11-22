local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates")
local id = "nameplates"
local spec = NS.SuiteCatalog[id]
local rules = {
    B.Bool("questReactionColors", "Separate neutral and hostile quest colors", false),
    B.Color("questNeutralColor", "Neutral quest enemy", "ffa633"),
    B.Color("questHostileColor", "Hostile quest enemy", "ff4da6"),
    B.Bool("targetClassResource", "Show your class resource on the target nameplate", false),
    B.Number("targetClassResourceWidth", "Class resource width (px)", 100, 30, 300),
    B.Number("targetClassResourceHeight", "Class resource height (px)", 5, 2, 30),
    B.Number("targetClassResourceY", "Class resource vertical offset", -6, -200, 200),
    B.Bool("castHealthColors", "Color enemy health while casting", false),
    B.Color("castHealthInterruptible", "Interruptible caster health", "4fb3ff"),
    B.Color("castHealthLocked", "Uninterruptible caster health", "f39200"),
    B.Bool("threatNameColor", "Use threat colors on the enemy name", false),
    B.Bool("threatFrameColor", "Use threat colors on the health frame outline", false),
    B.Bool("castIconCombinedHeight", "Spell icon spans health and cast bars", false),
    B.Bool("castSeamLine", "Show a line between health and cast bars", false),
    B.Bool("targetUnitFrameResource", "Show your class resource on the MSUF target frame", false),
    B.Number("targetUnitFrameResourceWidth", "Target frame resource width", 114, 30, 300),
    B.Number("targetUnitFrameResourceHeight", "Target frame resource height", 5, 2, 30),
    B.Number("targetUnitFrameResourceY", "Target frame resource vertical offset", -8, -200, 200),
    B.Bool("enemySlantedHealth", "Slanted enemy health bars", false),
}
rules[1].enableKey = "enemyQuestColors"
for _, index in ipairs({ 2, 3 }) do rules[index].enableKey = "questReactionColors" end
for _, index in ipairs({ 5, 6, 7 }) do rules[index].enableKey = "targetClassResource" end
for _, index in ipairs({ 9, 10 }) do rules[index].enableKey = "castHealthColors" end
for _, index in ipairs({ 11, 12 }) do rules[index].enableKey = "enemyRoleColors" end
for _, index in ipairs({ 16, 17, 18 }) do rules[index].enableKey = "targetUnitFrameResource" end
local scopes = { enemy = "Enemy", neutral = "Neutral", friendly = "Friendly", friendlyNpc = "Friendly NPC" }
for _, scope in ipairs(NS.NameplateExtensions.OpacityScopes) do
    local label = NS.Text("%s: automatic class range spell"):format(NS.Text(scopes[scope]))
    local auto = B.Bool(scope .. "RangeAuto", label, false)
    auto.enableKey = scope .. "RangeEnabled"
    rules[#rules + 1] = auto
    spec.rules[scope .. "RangeSpell"].disabledBy = scope .. "RangeAuto"
end
B.Section(id, "plateExtras", "Extra nameplate features", rules)
local function AddToLooks(rule)
    spec.look.visualKeys[rule.key] = true
    for _, preset in pairs(spec.look.presets) do preset[rule.key] = rule.default end
end
for _, rule in ipairs(rules) do AddToLooks(rule) end

-- The old keys remain readable while importing pre-category profiles.
local function PatternRules(prefix, label)
    return {
        B.Texture(prefix .. "Texture", NS.Text("%s pattern texture"):format(label)),
        B.Number(prefix .. "Alpha", NS.Text("%s pattern opacity (%%)"):format(label), 35, 0, 100, 5),
    }
end
for _, pattern in ipairs(NS.NameplateExtensions.Patterns) do
    local label = NS.Text(pattern.label)
    B.Section(id, "plateExtras", "Extra nameplate features", PatternRules(pattern.kind .. "Pattern", label), { hidden = true })
    for _, scope in ipairs(NS.NameplateExtensions.OpacityScopes) do
        local scoped = PatternRules(scope .. pattern.field, label)
        B.Section(id, "plateHighlightPatterns", "Frame and highlights", scoped)
        for _, rule in ipairs(scoped) do AddToLooks(rule) end
    end
end
