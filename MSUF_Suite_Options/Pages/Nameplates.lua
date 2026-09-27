local _, P = ...
local Tr = P.Tr
local PAGE, ID = "suite_nameplates", "nameplates"

local HELP = {
    general = "Jundies uses Modern plates and Medium size. Guild names and titles also affect names in the world. Bind Toggle friendly NPC nameplates under MSUF Suite in Blizzard Key Bindings. Import protection keeps your current nameplates when importing a full Suite profile; explicit nameplate imports still replace them.",
    enemy = "Blizzard supplies the name and health values. Jundies requests full enemy plates and both health values so normal enemies show text too. Role colors use the saved Platynator DEFAULT palette; mana is only a caster hint. Open the three-dot menu here or Nameplates in MSUF Colors to change the palette.",
    friendly = "Party / raid members shows friendly player names without bars and hides names of other friendly players. The Group / outsider preview button tests the filter. Blizzard can forbid changes to friendly plates in instances; those frames stay under Blizzard's control.",
    castbar = "Blizzard supplies the castbar texture, colors, progress and interrupts. Customize its text and details here. Drag elements or use X/Y; positions apply outside combat.",
    roleColors = "Priority: focus, safe tank aggro, threat, tapped, quest, neutral, then NPC type. Turning focus off allows the next rule. Disabled threat overrides preserve Blizzard's active threat color. Tank mode uses your effective role; warnings also work for damage/healers. Secret values stay with Blizzard.",
}

local function Build(ctx)
    local builder = P.W.PageBuilder(ctx)
    local sections = {}
    P.BuildNameplatesPreview(ctx, builder, sections)
    P.ModuleCard(ctx, builder, PAGE, ID, nil, { rules = P.SectionRules(ID, "general"), help = HELP.general })
    for _, section in ipairs({ "enemy", "roleColors", "castbar", "friendly" }) do
        local rules = P.SectionRules(ID, section)
        if section ~= "friendly" then
            for _, rule in ipairs(P.SectionRules(ID, "enemyColors")) do
                local owner = rule.key == "enemyTargetColor" and "enemy" or "roleColors"
                if owner == section then rules[#rules + 1] = rule end
            end
        end
        sections[section] = P.RuleSection(ctx, builder, PAGE, ID, PAGE .. "_" .. section, Tr(rules[1].sectionTitle), rules,
            { help = HELP[section], open = section == "enemy" })
    end
end

P.RegisterPage({ key = PAGE, label = "Nameplates", title = "Nameplates", build = Build, icon = { 7, 0 },
    aliases = { "nameplate", "plates", "enemynameplates", "friendlynameplates" } })
