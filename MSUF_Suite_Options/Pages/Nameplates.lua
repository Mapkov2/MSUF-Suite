local _, P = ...
local Tr = P.Tr
local PAGE, ID = "suite_nameplates", "nameplates"

local HELP = {
    general = "Mapko uses Modern plates, Medium size and the same bar dimensions on Retail and Forever. Guild names and titles also affect names in the world. Bind Toggle friendly NPC nameplates under MSUF Suite in Blizzard Key Bindings. Import protection keeps your current nameplates when importing a full Suite profile; explicit nameplate imports still replace them.",
    enemy = P.Help("Set enemy nameplate size, text and appearance.", "Blizzard supplies the name and health values. Mapko requests full enemy plates and both health values so normal enemies show text too. Width and height change only the enemy health bar in pixels; 0 keeps the selected bar dimensions. Backdrop, border and role fill are separate live skin layers in the preview; right-click a layer for its setting. Role colors use the saved palette; mana is only a caster hint. Open the three-dot menu here or Nameplates in MSUF Colors to change the palette."),
    friendly = "Friendly player display chooses Blizzard's setting, names for all friendly players, names for party / raid only, or health bars. Names only hides Blizzard bars, casts and auras for friendly players; it does not change NPC or enemy plates. Group / outsider in the preview only changes the sample. Blizzard can forbid changes to friendly plates in instances; those frames stay under Blizzard's control.",
    castbar = "Blizzard supplies the castbar texture, colors, progress and interrupts. Customize its text and details here. Select and move each cast element in the preview; positions apply outside combat.",
    roleColors = "Priority: focus, safe tank aggro, threat, tapped, quest, neutral, then NPC type. Turning focus off allows the next rule. Disabled threat overrides preserve Blizzard's active threat color. Tank mode uses your effective role; warnings also work for damage/healers. Secret values stay with Blizzard.",
    elements = "Blizzard owns these elements. The rarity icon setting applies to all nameplates; raid target icons are hidden only on enemy plates. Castbar details control Blizzard's own castbar. The preview and live plates use the same switches.",
    auras = "Blizzard owns the aura icons and updates. Choose Keep Blizzard setting or Customize for each unit type. Buffs, debuffs and control effects can be selected and dragged separately in the preview. Aura size uses Blizzard's own setting.",
    signals = "Blizzard owns aggro flashes, progressive highlights and soft target icons. Optional colors tint Blizzard's existing threat textures; its health bar threat color stays under the role-color overlay. Soft target icons also need the nameplate icon switch enabled and a matching soft target in game.",
    personal = "Skin only Blizzard's own personal mana and alternate-power status bars. Blizzard still owns their values, fill and visibility. Class-specific resource points retain Blizzard's layout. Select and drag the power bar in the personal preview.",
}

local ELEMENT_KEYS = { enemyTextMode = true, enemyRarityIcon = true, enemyRaidIcon = true }
local CAST_ELEMENT_KEYS = { enemyCastEnabled = true, enemyCastDisplay = true,
    enemyCastSpellName = true, enemyCastSpellIcon = true, enemyCastSpellTarget = true,
    enemyCastImportant = true, enemyCastTargetHighlight = true }
local enemyTab = "appearance"

local function IsPositionRule(rule)
    return rule.key:match("Offset[XY]$") ~= nil
end

-- Search follows the same placement rules as the page and preview.
function P.NameplateSearchTarget(rule)
    if IsPositionRule(rule) then return PAGE .. "_preview", nil, false end
    if ELEMENT_KEYS[rule.key] or CAST_ELEMENT_KEYS[rule.key] then return PAGE .. "_enemy" end
    if rule.section == "enemyColors" then
        return PAGE .. (rule.key == "enemyTargetColor" and "_enemy" or "_roleColors")
    end
end

local function VisibleRules(rules)
    local visible = {}
    for _, rule in ipairs(rules) do
        if not IsPositionRule(rule) then visible[#visible + 1] = rule end
    end
    return visible
end

local function PositionKeys(rules)
    local keys = {}
    for _, rule in ipairs(rules) do
        if IsPositionRule(rule) then keys[#keys + 1] = rule.key end
    end
    return keys
end

-- One panel per enemy tab (Design, Blizzard elements) with its rules; a
-- search hit on a rule selects the rule's tab first.
local function EnemyPanels(ctx, body, width, sectionId, appearance, elements)
    local panels, heights = {}, {}
    for _, spec in ipairs({ { "appearance", appearance, HELP.enemy }, { "elements", elements, HELP.elements } }) do
        local panel = CreateFrame("Frame", nil, body)
        panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -59)
        panel:SetSize(width + 32, 100)
        local help = P.Description(panel, spec[3], 16, -18, width, "Enemy appearance")
        local y = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
        local entries
        y, entries = P.RuleGrid(ctx, panel, PAGE, ID, spec[2], y, width, nil, sectionId)
        local tab = spec[1]
        for _, entry in ipairs(entries or {}) do
            if entry.widget then
                entry.widget._msuf2PrepareExactSearchTarget = function()
                    P.SelectNameplatesEnemyTab(tab)
                end
            end
        end
        heights[spec[1]] = -y + 14
        panel:SetHeight(heights[spec[1]])
        panels[spec[1]] = panel
    end
    return panels, heights
end

-- The section reset covers the enemy rules and the cast bar elements shown here.
local function EnemyResetRules(rules, elements)
    local resetRules = {}
    for _, rule in ipairs(rules) do resetRules[#resetRules + 1] = rule end
    for _, rule in ipairs(elements) do
        if CAST_ELEMENT_KEYS[rule.key] then resetRules[#resetRules + 1] = rule end
    end
    return resetRules
end

local function EnemySection(ctx, builder, rules)
    local appearance, elements = {}, {}
    for _, rule in ipairs(rules) do
        if not IsPositionRule(rule) then
            local target = ELEMENT_KEYS[rule.key] and elements or appearance
            target[#target + 1] = rule
        end
    end
    for _, rule in ipairs(P.SectionRules(ID, "castbar")) do
        if CAST_ELEMENT_KEYS[rule.key] then elements[#elements + 1] = rule end
    end
    local sectionId = PAGE .. "_enemy"
    if type(P.W.SegmentTabs) ~= "function" then
        local body = P.RuleSection(ctx, builder, PAGE, ID, sectionId, Tr("Enemy appearance"), appearance,
            { help = HELP.enemy, open = true, resetKeys = PositionKeys(rules) })
        local elementsBody = P.RuleSection(ctx, builder, PAGE, ID, PAGE .. "_enemyElements", Tr("Blizzard elements"), elements,
            { help = HELP.elements })
        P.SelectNameplatesEnemyTab = function(tab) return tab == "elements" and elementsBody or body end
        return body
    end

    local body = builder:CollapsibleSection(sectionId, Tr("Enemy appearance"), 120, true)
    local width = math.max(240, (body._msuf2Width or builder.width or 720) - 32)
    local panels, heights = EnemyPanels(ctx, body, width, sectionId, appearance, elements)
    local function RefreshHeight(tab)
        P.FinishBody(builder, body, -59 - heights[tab])
    end
    local tabs, refresh, _, selectTab = P.W.SegmentTabs(ctx, body, {
        label = "", values = { { value = "appearance", text = Tr("Design") },
            { value = "elements", text = Tr("Blizzard elements") } },
        width = math.min(360, width), frames = panels, defaultTab = "appearance",
        get = function() return enemyTab end,
        set = function(tab)
            enemyTab = tab
            if tab == "elements" and P.ShowNameplatesElementsSample then P.ShowNameplatesElementsSample() end
        end,
        afterRefresh = RefreshHeight, x = 16, y = -12,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    P.SelectNameplatesEnemyTab = function(tab)
        if selectTab then selectTab(tab) end
        return body
    end
    if P.M.RegisterControlMetadata then
        P.M.RegisterControlMetadata(tabs, P.Meta(PAGE, ID, "enemy.tabs", "action", sectionId),
            "Enemy nameplate tabs", "segment")
    end
    P.AttachRuleColors(body, Tr("Enemy appearance"), ID, rules)
    local resetRules = EnemyResetRules(rules, elements)
    P.AttachSectionReset(ctx, body, Tr("Enemy appearance"), function() return P.ResetRules(ID, resetRules) end)
    refresh()
    return body
end

local function Build(ctx)
    local builder = P.W.PageBuilder(ctx)
    local sections = {}
    P.BuildNameplatesPreview(ctx, builder, sections)
    P.ModuleCard(ctx, builder, PAGE, ID, nil, { rules = P.SectionRules(ID, "general"), help = HELP.general })
    for _, section in ipairs({ "enemy", "roleColors", "castbar", "auras", "signals", "friendly", "personal" }) do
        local allRules = P.SectionRules(ID, section)
        local rules = VisibleRules(allRules)
        if section == "castbar" then
            local styled = {}
            for _, rule in ipairs(rules) do
                if not CAST_ELEMENT_KEYS[rule.key] then styled[#styled + 1] = rule end
            end
            rules = styled
        end
        if section ~= "friendly" then
            for _, rule in ipairs(P.SectionRules(ID, "enemyColors")) do
                local owner = rule.key == "enemyTargetColor" and "enemy" or "roleColors"
                if owner == section then
                    rules[#rules + 1] = rule
                    allRules[#allRules + 1] = rule
                end
            end
        end
        if section == "enemy" then
            sections.enemy = EnemySection(ctx, builder, allRules)
        else
            sections[section] = P.RuleSection(ctx, builder, PAGE, ID, PAGE .. "_" .. section, Tr(rules[1].sectionTitle), rules,
                { help = HELP[section], resetKeys = PositionKeys(allRules) })
        end
    end
end

P.RegisterPage({ key = PAGE, label = "Nameplates", title = "Nameplates", build = Build, icon = { 7, 0 },
    nav = "combat", navOrder = 1,
    aliases = { "nameplate", "plates", "enemynameplates", "friendlynameplates" } })
