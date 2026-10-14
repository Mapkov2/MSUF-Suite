local _, P = ...
local Tr, HM = P.Tr, P.HM
local PAGE, ID = "suite_nameplates", "nameplates"

local HELP = {
    general = P.Help("Pick a look: Mapko (recommended), Jundies, Blizzard (no skin) or Custom. Quick Setup applies Mapko.",
        "Mapko uses Modern plates, Medium size and the same bar dimensions on Retail and Forever. Guild names and titles also affect names in the world. Bind Toggle friendly NPC nameplates under MSUF Suite in Blizzard Key Bindings. Import protection keeps your current nameplates when importing a full Suite profile; explicit nameplate imports still replace them."),
    enemy = P.Help("Set enemy nameplate size, text and appearance.", "Blizzard supplies the name and health values. Mapko requests full enemy plates and both health values so normal enemies show text too. Width and height change only the enemy health bar in pixels; 0 keeps the selected bar dimensions. Backdrop, border and role fill are separate live skin layers in the preview; right-click a layer for its setting. Role colors use the saved palette; mana is only a caster hint. Open the three-dot menu here or Nameplates in MSUF Colors to change the palette."),
    friendly = P.Help("Names, health bars and text on friendly plates.",
        "Friendly player display chooses Blizzard's setting, names for all friendly players, names for party / raid only, or health bars. Names only hides Blizzard bars, casts and auras for friendly players; it does not change NPC or enemy plates. Group / outsider in the preview only changes the sample. Blizzard can forbid changes to friendly plates in instances; those frames stay under Blizzard's control."),
    castbar = P.Help("Text on Blizzard's enemy castbars.",
        "Blizzard supplies the castbar texture, colors, progress and interrupts. Customize its text and details here. Select and move each cast element in the preview; positions apply outside combat."),
    roleColors = P.Help("Color enemy health by type, threat and focus.",
        "Priority: focus, safe tank aggro, threat, tapped, quest, neutral, then NPC type. Turning focus off allows the next rule. Disabled threat overrides preserve Blizzard's active threat color. Tank mode uses your effective role; warnings also work for damage/healers. Secret values stay with Blizzard."),
    elements = P.Help("Blizzard's own icons and castbar details.",
        "Blizzard owns these elements. The rarity icon setting applies to all nameplates; raid target icons are hidden only on enemy plates. Castbar details control Blizzard's own castbar. The preview and live plates use the same switches."),
    auras = P.Help("Which Blizzard auras each kind of plate shows.",
        "Blizzard owns the aura icons and updates. Choose Keep Blizzard setting or Customize for each unit type. Buffs, debuffs and control effects can be selected and dragged separately in the preview. Aura size uses Blizzard's own setting."),
    signals = P.Help("Blizzard's aggro, target, focus and soft target signals.",
        "Blizzard owns aggro flashes, progressive highlights and soft target icons. Optional colors tint Blizzard's existing threat textures; its health bar threat color stays under the role-color overlay. Soft target icons also need the nameplate icon switch enabled and a matching soft target in game."),
    decor = P.Help("Frame styling and clear target highlights.",
        "Frames join aligned bars; detached bars keep separate frames. Effects are static. Threshold marks a fixed percentage. Preview switches apply live."),
    personal = P.Help("Border of Blizzard's personal power bar.",
        "Skin only Blizzard's own personal mana and alternate-power status bars. Blizzard still owns their values, fill and visibility. Class-specific resource points retain Blizzard's layout. Select and drag the power bar in the personal preview."),
    native = P.Help("Blizzard's own plate style and size, and player names in the world."),
    visibility = P.Help("Which units get nameplates and how plates share space.",
        "Blizzard's own nameplate options. Keep Blizzard setting changes nothing; other choices go back to Blizzard's value when the skin turns off."),
}

local CAST_ELEMENT_KEYS = { enemyCastEnabled = true, enemyCastDisplay = true,
    enemyCastSpellName = true, enemyCastSpellIcon = true, enemyCastSpellTarget = true,
    enemyCastImportant = true, enemyCastTargetHighlight = true }

-- Where every nameplate setting shows, in page order: one accordion per
-- entry and, in a tabbed one, one tab (Portrait and Class Resources style).
-- Keys missing on this client are skipped. Colors open from the section's
-- ::: menu; positions stay with the preview and reset with the section whose
-- catalog section `positions` names. A setting placed nowhere still shows,
-- under More settings.
local ROLE_SWITCHES, ROLE_COLORS = {}, {}
for _, role in ipairs(P.Suite.NameplateStyle.Roles) do
    if role.key ~= "TankMode" then ROLE_SWITCHES[#ROLE_SWITCHES + 1] = "enemy" .. role.key .. "Enabled" end
    ROLE_COLORS[#ROLE_COLORS + 1] = "enemy" .. role.key .. "Color"
end
local MODULE_KEYS = { "look", "enemy", "friendly", "protectImport" }
local SECTIONS = {
    { key = "native", area = "general", title = "Blizzard plates",
      keys = { "nativeStyle", "nativeSize", "targetScaleEnabled", "targetScalePercent", "barGeometry", "levelAppearance",
            "classColors", "playerGuildNames", "playerTitles" } },
    { key = "visibility", area = "general", catalog = "visibility" },
    { key = "personal", area = "general", catalog = "personal", positions = "personal" },
    { key = "enemy", area = "enemies", title = "Enemy appearance", open = true, positions = "enemy",
      colors = { "enemyBorderColor", "enemyBackdropColor", "enemyOuterFrameColor", "enemyGlowColor", "enemyTargetColor",
            "enemyFocusMarkerColor", "enemyThresholdColor" }, tabs = {
        { id = "bar", label = "Bar", help = "enemy", keys = { "enemyHealthWidthDelta", "enemyHealthHeightDelta",
            "enemyBackdropEnabled", "enemyBackdropAlpha", "enemyBorderEnabled", "enemyBorderSize", "enemyBorderStyle",
            "enemyTextureEnabled", "enemyFillTexture" } },
        { id = "frame", label = "Frame and highlights", help = "decor", keys = {
            "enemyOuterFrame", "enemyOuterFrameSize", "enemyShadowEnabled", "enemyGlowEnabled", "enemyGlowMode", "enemyEffectSize" } },
        { id = "text", label = "Text", keys = { "enemyTextMode", "enemyMirrorHeader", "enemyTextEnabled", "enemyCustomFont", "enemyNameFont",
            "enemyNameSize", "enemyHealthTextSize", "enemyTextOutline", "enemyTextShadow", "enemyLevelEnabled", "enemyLevelSize" } },
        { id = "markers", label = "Markers", help = "elements", keys = { "enemyEliteMarker", "enemyEliteMarkerAnchor",
            "enemyEliteMarkerSize", "enemyQuestMarker", "enemyQuestMarkerAnchor", "enemyQuestMarkerSize",
            "enemyRarityIcon", "enemyRaidIcon", "enemyFocusMarker", "enemyFocusMarkerSize", "enemyFocusMarkerX", "enemyFocusMarkerY",
            "enemyThresholdEnabled", "enemyThresholdPercent" } },
        { id = "target", label = "Target arrows", keys = { "enemyTargetMarker", "enemyTargetStyle", "enemyTargetLayout",
            "enemyTargetAnchor", "enemyTargetDirection", "enemyTargetMarkerSize", "enemyTargetHideFriendly" } },
    } },
    { key = "castbar", area = "enemies", catalog = "castbar", positions = "castbar" },
    { key = "roleColors", area = "colors", title = "Enemy color rules", open = true, colors = ROLE_COLORS, tabs = {
        { id = "rules", label = "Rules", help = "roleColors", keys = { "enemyRoleColors", "enemyColorsInDungeons",
            "enemyColorsOutside", "enemyQuestColors", "enemyTankMode", "enemyPreviewRole" } },
        { id = "types", label = "Types", keys = ROLE_SWITCHES },
    } },
    { key = "signals", area = "colors", title = "Blizzard indicators",
      colors = { "threatFlashColor", "threatHighlightColor", "selectionTargetColor", "selectionFocusColor" }, tabs = {
        { id = "aggro", label = "Aggro", help = "signals", keys = { "threatSignalMode", "threatFlash", "threatHighlight",
            "threatFlashColorEnabled", "threatHighlightColorEnabled" } },
        { id = "selection", label = "Target and focus", keys = { "selectionBorder", "selectionDim", "selectionDimPercent" } },
        { id = "soft", label = "Soft target", keys = { "softTargetEnemy", "softTargetFriend", "softTargetInteract",
            "softTargetIconGate" } },
    } },
    { key = "auraColors", area = "colors" },
    { key = "friendly", area = "friendly", title = "Friendly appearance", open = true, positions = "friendly",
      colors = { "friendlyBorderColor", "friendlyBackdropColor", "friendlyOuterFrameColor", "friendlyGlowColor" }, tabs = {
        { id = "display", label = "Display", help = "friendly", keys = { "friendlyNamesOnly", "friendlyNameClassColor",
            "friendlyRealm", "friendlyNPCs" } },
        { id = "bar", label = "Bar", keys = { "friendlyHealthWidthDelta", "friendlyHealthHeightDelta",
            "friendlyBackdropEnabled", "friendlyBackdropAlpha", "friendlyBorderEnabled", "friendlyBorderSize",
            "friendlyBorderStyle", "friendlyTextureEnabled", "friendlyFillTexture" } },
        { id = "frame", label = "Frame and highlights", help = "decor", keys = {
            "friendlyOuterFrame", "friendlyOuterFrameSize", "friendlyShadowEnabled", "friendlyGlowEnabled", "friendlyGlowMode", "friendlyEffectSize" } },
        { id = "text", label = "Text", keys = { "friendlyTextEnabled", "friendlyCustomFont", "friendlyNameFont",
            "friendlyNameSize", "friendlyTextOutline", "friendlyTextShadow", "friendlyLevelEnabled", "friendlyLevelSize" } },
        { id = "markers", label = "Markers", keys = { "friendlyEliteMarker", "friendlyEliteMarkerAnchor",
            "friendlyEliteMarkerSize", "friendlyQuestMarker", "friendlyQuestMarkerAnchor", "friendlyQuestMarkerSize" } },
        { id = "castbar", label = "Castbar", keys = { "friendlyCastTextEnabled", "friendlyCastTimeEnabled",
            "friendlyCastCustomFont", "friendlyCastFont", "friendlyCastSize", "friendlyCastOutline", "friendlyCastTextShadow" } },
    } },
    { key = "auras", area = "auras", title = "Blizzard auras", open = true, positions = "auras", tabs = {
        { id = "enemyNpc", label = "Enemy NPC", help = "auras", keys = { "enemyNpcAuraMode", "enemyNpcBuffs",
            "enemyNpcDebuffs", "enemyNpcControl" } },
        { id = "enemyPlayer", label = "Enemy player", keys = { "enemyPlayerAuraMode", "enemyPlayerBuffs",
            "enemyPlayerDebuffs", "enemyPlayerControl" } },
        { id = "friendlyPlayer", label = "Friendly player", keys = { "friendlyPlayerAuraMode", "friendlyPlayerBuffs",
            "friendlyPlayerDebuffs", "friendlyPlayerControl" } },
        { id = "general", label = "General", keys = { "friendlyNpcDebuffs", "auraScaleMode", "auraScalePercent",
            "personalAuras", "auraClickthrough" } },
    } },
}
P.NameplateSections = SECTIONS
local ENEMY
for _, spec in ipairs(SECTIONS) do
    if spec.key == "enemy" then ENEMY = spec end
end

local function IsPositionRule(rule)
    return rule.key:match("Offset[XY]$") ~= nil
end

-- The catalog rules of a key list that exist on this client.
local function Rules(keys)
    local rules, catalog = {}, P.catalog[ID].rules
    for _, key in ipairs(keys or {}) do
        if catalog[key] then rules[#rules + 1] = catalog[key] end
    end
    return rules
end

local function VisibleRules(rules)
    local visible = {}
    for _, rule in ipairs(rules) do
        if not IsPositionRule(rule) then visible[#visible + 1] = rule end
    end
    return visible
end

local function PositionKeys(section)
    local keys = {}
    for _, rule in ipairs(section and P.SectionRules(ID, section) or {}) do
        if IsPositionRule(rule) then keys[#keys + 1] = rule.key end
    end
    return keys
end

-- Section id of every placed key; More settings holds the rest.
local placed = {}
for _, key in ipairs(MODULE_KEYS) do placed[key] = PAGE .. "_" .. ID .. "_module" end
for _, spec in ipairs(SECTIONS) do
    local function Place(keys)
        for _, key in ipairs(keys or {}) do placed[key] = PAGE .. "_" .. spec.key end
    end
    Place(spec.keys)
    Place(spec.colors)
    for _, tab in ipairs(spec.tabs or {}) do Place(tab.keys) end
    if spec.catalog then
        for _, rule in ipairs(P.SectionRules(ID, spec.catalog)) do placed[rule.key] = placed[rule.key] or PAGE .. "_" .. spec.key end
    end
end

-- Visible settings the placement does not name (a newer catalog rule).
local function Unplaced()
    local rules = {}
    for _, rule in ipairs(P.catalog[ID].controls or {}) do
        if not placed[rule.key] and rule.key ~= "enabled" and not rule.hidden and not rule.previewOnly
            and not IsPositionRule(rule) and rule.section ~= "auraColors" then rules[#rules + 1] = rule end
    end
    return rules
end

-- Search follows the same placement as the page and preview.
function P.NameplateSearchTarget(rule)
    if IsPositionRule(rule) then return PAGE .. "_preview", nil, false end
    if placed[rule.key] then return placed[rule.key] end
    if rule.section ~= "auraColors" and rule.key ~= "enabled" then return PAGE .. "_more" end
end

-- One panel per tab with its rules; a search hit on a rule selects the
-- rule's tab first (the preview's exact setting jump uses the same hook).
local function Panels(ctx, body, width, spec, sectionId)
    local panels, heights = {}, {}
    for _, tab in ipairs(spec.tabs) do
        local panel = CreateFrame("Frame", nil, body)
        panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -59)
        panel:SetSize(width + 32, 100)
        local y = -18
        if tab.help then
            local help = P.Description(panel, HELP[tab.help], 16, y, width, Tr(spec.title))
            y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
        end
        local entries
        y, entries = P.RuleGrid(ctx, panel, PAGE, ID, tab.rules, y, width, nil, sectionId)
        for _, entry in ipairs(entries or {}) do
            if entry.widget then
                HM.SetSearchTargetPrepare(entry.widget, function() spec.select(tab.id) end)
            end
        end
        heights[tab.id] = -y + 14
        panel:SetHeight(heights[tab.id])
        panels[tab.id] = panel
    end
    return panels, heights
end

local selectedTabs = {}

local function Tabs(ctx, builder, body, spec, sectionId)
    local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local panels, heights = Panels(ctx, body, width, spec, sectionId)
    local values = {}
    for _, tab in ipairs(spec.tabs) do values[#values + 1] = { value = tab.id, text = Tr(tab.label) } end
    local tabs, refresh, _, selectTab = P.W.SegmentTabs(ctx, body, {
        label = "", values = values, width = math.min(width, math.max(360, 120 * #values)), frames = panels,
        defaultTab = spec.tabs[1].id,
        get = function() return selectedTabs[spec.key] or spec.tabs[1].id end,
        set = function(tab)
            selectedTabs[spec.key] = tab
            if spec.onTab then spec.onTab(tab) end
        end,
        afterRefresh = function(tab) P.FinishBody(builder, body, -59 - heights[tab]) end, x = 16, y = -12,
    })
    P.HideControlTitle(tabs)
    if P.M.RegisterControlMetadata then
        P.M.RegisterControlMetadata(tabs, P.Meta(PAGE, ID, spec.key .. ".tabs", "action", sectionId), spec.title, "segment")
    end
    return refresh, selectTab
end

-- A tabbed accordion. A lazy host builds the tabs on first open; selecting a
-- tab from outside (search, preview) builds the section first.
local function TabbedSection(ctx, builder, spec)
    local sectionId, all = PAGE .. "_" .. spec.key, Rules(spec.colors)
    for _, tab in ipairs(spec.tabs) do
        tab.rules = Rules(tab.keys)
        for _, rule in ipairs(tab.rules) do all[#all + 1] = rule end
    end
    if type(P.W.SegmentTabs) ~= "function" then
        local body = P.RuleSection(ctx, builder, PAGE, ID, sectionId, Tr(spec.title), all,
            { help = HELP[spec.tabs[1].help], open = spec.open, resetKeys = PositionKeys(spec.positions) })
        spec.select = function() return body end
        return body
    end
    local refresh, selectTab
    return P.LazySection(builder, sectionId, Tr(spec.title), spec.open, {
        content = function(body)
            refresh, selectTab = Tabs(ctx, builder, body, spec, sectionId)
            P.AttachRuleColors(body, Tr(spec.title), ID, all)
        end,
        shell = function(body)
            spec.select = function(tab)
                if not selectTab then P.EnsureSectionContent(body) end
                if selectTab and tab then selectTab(tab) end
                return body
            end
            P.AttachSectionReset(ctx, body, Tr(spec.title), function()
                return P.ResetRules(ID, all, nil, PositionKeys(spec.positions))
            end)
        end,
        finish = function() refresh() end,
    })
end

-- MSUF owns the interrupt-ready indicator on these castbars: its switch and
-- its look are MSUF's (Castbars > Interrupt Ready Indicator), drawn here by
-- MSUF_Suite_Nameplates/KickReady.lua. Shown where the host has the engine.
-- Every host with the engine has Menu2's exact setting jump.
local KICK_SWITCH, KICK_SWITCH_LABEL = "general.kickReadyShowNameplates", "Show on enemy nameplates (MSUF Suite)"
local KICK_HELP =
    "Interrupt readiness on these castbars looks exactly like on MSUF's castbars. Turn it on and style it in MSUF: Castbars > Interrupt Ready Indicator."
local function KickReadyLink(ctx)
    return function(body, y, width)
        if not P.Suite.HostBridge.KickReady() then return y end
        local text = P.Description(body, KICK_HELP, 16, y, width, Tr("Enemy castbar"))
        y = y - math.max(14, math.ceil(text:GetStringHeight() or 14)) - 8
        P.Button(ctx, body, "Open interrupt settings", 16, y, 220, function()
            P.M.OpenExactSettingControl(KICK_SWITCH, KICK_SWITCH_LABEL, "opt_castbar")
        end, nil, P.Meta(PAGE, ID, "action.kickReady", "action", PAGE .. "_castbar"))
        return y - 40
    end
end

-- An accordion of one key list or one catalog section.
local function PlainSection(ctx, builder, spec, rules)
    rules = rules or (spec.catalog and VisibleRules(P.SectionRules(ID, spec.catalog)) or Rules(spec.keys))
    for _, rule in ipairs(Rules(spec.colors)) do rules[#rules + 1] = rule end
    if #rules == 0 then return nil end
    return P.RuleSection(ctx, builder, PAGE, ID, PAGE .. "_" .. spec.key, Tr(spec.title or rules[1].sectionTitle), rules,
        { help = HELP[spec.key], open = spec.open, resetKeys = PositionKeys(spec.positions),
          extra = spec.key == "castbar" and KickReadyLink(ctx) or nil })
end

-- Preview handles and the lazy-section contract still name the old enemy
-- tabs: Design opens the bar tab, Blizzard elements the markers tab.
local LEGACY_ENEMY_TABS = { appearance = "bar", elements = "markers" }
ENEMY.onTab = function(tab)
    if (tab == "text" or tab == "markers") and P.ShowNameplatesElementsSample then P.ShowNameplatesElementsSample() end
end
function P.SelectNameplatesEnemyTab(tab)
    local select = ENEMY.select
    return select and select(LEGACY_ENEMY_TABS[tab] or tab)
end

local function Build(ctx)
    local builder = P.W.PageBuilder(ctx)
    local sections = {}
    local Workspace = P.NameplatesWorkspace
    local ui = Workspace.Header(ctx, builder)
    P.BuildNameplatesPreview(ctx, builder, sections)
    Workspace.Track(ui, P.ModuleCard(ctx, builder, PAGE, ID, nil, { rules = Rules(MODULE_KEYS), help = HELP.general }), "general")
    for _, spec in ipairs(SECTIONS) do
        if spec.key == "auraColors" then
            P.BuildNameplatesAuraColors(ctx, builder, sections)
        elseif spec.tabs then
            sections[spec.key] = TabbedSection(ctx, builder, spec)
        else
            sections[spec.key] = PlainSection(ctx, builder, spec)
        end
        Workspace.Track(ui, sections[spec.key], spec.area)
    end
    local more = PlainSection(ctx, builder, { key = "more", title = "More settings" }, Unplaced())
    if more then Workspace.Track(ui, more, "general") end
    Workspace.Finish(ui)
end

P.RegisterPage({ key = PAGE, label = "Nameplates", title = "Nameplates", build = Build, icon = { 7, 0 },
    nav = "combat", navOrder = 1,
    aliases = { "nameplate", "plates", "enemynameplates", "friendlynameplates" } })
