local _, P = ...
local S, Tr, HM = P.S, P.Tr, P.HM
local PAGE = "suite_qualityOfLife"
-- Aliases name feature switches; keywords also describe their detail controls.
local GROUPS = {
    { id = "selfCombatText", title = "Own combat text", switch = "enabled", sections = { "self_combat_text" },
        keywords = { "SCT", "FCT", "floating combat text", "Kampftext", "Schadenszahlen", "Heilungszahlen" } },
    -- Keep the visible feature names alphabetic; section IDs stay stable for search and history.
    { id = "actionTracker", title = "Action tracker", switch = "enabled",
        sections = { "action_tracker", "action_tracker_visibility", "action_tracker_colors" },
        aliases = { "cast history", "spell history", "last casts", "zauberverlauf" } },
    { id = "dungeonPortals", title = "Dungeon portals (Retail)", switch = "enabled", sections = { "dungeon_portals" } },
    { id = "enemyCastStack", title = "Dungeon cast stack (Retail)", switch = "enabled",
        sections = { "dungeon_casts" }, aliases = { "enemy casts", "cast list" } },
    { id = "groupFinderExitReminder", title = "Active application reminder (Retail)", switch = "enabled",
        sections = { "group_finder_exit" } },
    { id = "trustedPartyInvites", title = "Trusted party invites (Retail)", switch = "enabled",
        sections = { "trusted_invites" } },
    { id = "battleRes", title = "Battle resurrection (Retail)", switch = "enabled",
        sections = { "battle_res" }, aliases = { "combat resurrection", "brez", "kampfwiederbelebung" } },
    { id = "groupBloodlust", title = "Bloodlust lockout (Retail)", switch = "enabled", sections = { "bloodlust_lockout" },
        aliases = { "bloodlust timer", "heroism timer", "exhaustion timer", "kampfrausch timer" } },
    { id = "loot", title = "Collecting loot", switch = "quickLoot", other = "manageHistory", sections = { "collection" } },
    { id = "collectionNewMarkers", title = "Collection new markers (Retail)", switch = "enabled", sections = { "collection_markers" } },
    { id = "combatLog", title = "Combat logging", switch = "enabled",
        sections = { "log_dungeons", "log_raids", "log_other", "log_exit" } },
    { id = "cursorEffects", title = "Cursor highlight (Retail)", switch = "enabled",
        sections = { "cursor_effects", "cursor_progress", "cursor_gcd", "cursor_when" },
        aliases = { "cursor ring", "gcd ring" } },
    { id = "dailyComfort", title = "Daily UI comforts", switch = "enabled", sections = { "daily_comfort", "daily_cvars" } },
    { id = "delveSolePower", title = "Delve single power (Retail)", switch = "enabled",
        sections = { "delve_sole_power" } },
    { id = "playerAuras", title = "Player aura layout", switch = "enabled", sections = { "player_auras" },
        aliases = { "player buffs", "minimap auras" } },
    { id = "playerAuraSkins", title = "Player aura skins", switch = "enabled", sections = { "player_aura_skins" }, aliases = { "buff skins" } },
    { id = "xpBar", title = "Experience bar", switch = "enabled", sections = { "xp_bar" },
        aliases = { "exp bar", "erfahrungsleiste" } },
    { id = "mapLandingShortcuts", title = "Expansion shortcuts (Retail)", switch = "enabled",
        sections = { "expansion_shortcuts" } },
    { id = "vaultSpec", title = "Great Vault loot spec (Retail)", switch = "enabled", sections = { "vault_spec" } },
    { id = "groupDeathAlert", title = "Group death alert", switch = "enabled", sections = { "group_death_alert" },
        aliases = { "death announcer", "death announce", "death announcements", "death alert",
            "Todesmelder", "Todesansage", "Todesmeldungen" } },
    { id = "releaseProtection", title = "Release spirit protection", switch = "enabled", sections = { "release_protection" },
        keywords = { "freilassen", "releasen", "geist freilassen", "release schutz", "release-schutz", "anti release" } },
    { id = "groupFinderDoubleClick", title = "Group finder double-click (Retail)", switch = "enabled",
        sections = { "group_finder_double_click" } },
    { id = "groupFinderApplicantSort", title = "Mythic+ applicant score sorting (Retail)", switch = "enabled",
        sections = { "group_finder_applicant_sort" } },
    { id = "mythicAutoQueue", title = "Mythic+ Auto Queue (Retail)", switch = "enabled", sections = { "mythic_auto_queue" },
        aliases = { "auto queue", "auto que", "auto accept", "auto invite", "auto role check", "rollenabfrage", "automatisch annehmen" } },
    { id = "guildChatPrivacy", title = "Guild chat privacy cover (Retail)", switch = "enabled",
        sections = { "guild_privacy" } },
    { id = "innervateCue", title = "Innervate whisper cue (Retail Druid)", switch = "enabled", sections = { "innervate_cue" } },
    { id = "itemCounts", title = "Item counts in tooltips (Retail)", switch = "enabled", sections = { "item_counts" } },
    { id = "socketGemSuggestions", title = "Gems in bags (Retail)", switch = "enabled", sections = { "socket_gems" } },
    { id = "tooltipSpellCopy", title = "Copy spell ID (Retail)", switch = "enabled", sections = { "copy_spell_id" } },
    { id = "tooltipMPlusScore", title = "Mythic+ score in tooltips (Retail)", switch = "enabled", sections = { "mplus_score" } },
    { id = "tooltipClassColors", title = "Class-colored player names (Retail)", switch = "enabled", sections = { "class_colors" } },
    { id = "macroBuilder", title = "Macro builder", switch = "enabled", sections = { "macro_builder" } },
    { id = "chatProfileLinks", title = "Character profile links (Retail)", switch = "enabled", sections = { "profile_links" },
        aliases = { "raider io", "raiderio", "warcraft logs", "warcraftlogs", "wcl", "applicant profiles",
            "group finder profile links", "lfg profile links", "right click profiles", "bewerber profile",
            "bewerber rechtsklick", "gruppensuche profile", "rechtsklick links", "raid progress", "raidprogress",
            "raid fortschritt", "raidfortschritt", "progressstand", "bewerber fortschritt" } },
    { id = "mythicKeyShare", title = "Keystone command (Retail)", switch = "enabled", sections = { "keystone_command" } },
    { id = "autoUprank", title = "Auto-uprank (Forever)", switch = "enabled", sections = { "auto_uprank" } },
    { id = "trainerLearnAll", title = "Learn all at trainer (Retail)", switch = "enabled", sections = { "trainer_all" } },
    { id = "characterUpgradeWindow", title = "Equipment window at upgrades (Retail)", switch = "enabled",
        sections = { "upgrade_equipment" } },
    { id = "mythicResetReminder", title = "Mythic+ reset reminder (Retail)", switch = "enabled",
        sections = { "mythic_reset" } },
    { id = "loadoutReminder", title = "Loadout reminder (Retail)", switch = "enabled",
        sections = { "loadout_reminder", "loadout_expectation" } },
    { id = "loot", title = "Loot history", switch = "manageHistory", other = "quickLoot", sections = { "history" } },
    { id = "durabilityAlert", title = "Low durability warning", switch = "enabled",
        sections = { "durability_warning" } },
    { id = "merchantLevel", title = "Merchant item levels (Retail)", switch = "enabled", sections = { "merchant_level" } },
    { id = "lootContainers", title = "Open new containers (Retail)", switch = "enabled",
        sections = { "open_containers" } },
    { id = "quests", title = "Quest helpers", switch = "enabled", sections = { "automation", "filters" } },
    { id = "quietPopups", title = "Quiet Blizzard popups", switch = "enabled", sections = { "quiet_popups" } },
    { id = "uiErrorFilter", title = "Quiet repeated errors", switch = "enabled", sections = { "ui_error_filter" } },
    { id = "groupRaidShortcuts", title = "Raid shortcuts (Retail)", switch = "enabled",
        sections = { "raid_shortcuts" } },
    { id = "combatPetStatus", title = "Pet status warning", switch = "enabled", sections = { "pet_status" } },
    { id = "professionAppearance", title = "Profession appearance remover (Retail)", switch = "enabled",
        sections = { "profession_outfits" } },
    { id = "combatMovementCue", title = "Movement ability cue (Retail)", switch = "enabled",
        sections = { "movement_cue" } },
    { id = "burningRushCue", title = "Burning Rush cue (Retail Warlock)", switch = "enabled",
        sections = { "burning_rush_cue" } },
    { id = "qol", title = "Repair", switch = "repair", other = "autoJunk", sections = { "repair" } },
    { id = "combatStatsHUD", title = "Secondary stats (Retail)", switch = "enabled",
        sections = { "secondary_stats", "stats_numbers", "stats_fps" } },
    { id = "targetDistance", title = "Target spell-range estimate (Retail)", switch = "enabled", sections = { "target_distance" },
        aliases = { "range finder", "zielreichweite" } },
    { id = "qol", title = "Sell junk", switch = "autoJunk", other = "repair", sections = { "junk" } },
    { id = "lootVendorRules", title = "Sell marked items (Retail)", switch = "enabled", sections = { "marked_sales" } },
    { id = "lootToastFilter", title = "Filtered loot notice (Retail)", switch = "enabled",
        sections = { "filtered_loot" } },
    { id = "skyriding", title = "Skyriding HUD (Retail)", switch = "enabled",
        sections = { "flight_hud", "flight_typography", "flight_colors" } },
    { id = "threatMeter", title = "Threat meter (Forever)", switch = "enabled", sections = { "threat_meter" },
        aliases = { "aggro meter", "threat list", "bedrohungsliste" } },
    { id = "flightTimer", title = "Flight route timer (Forever)", switch = "enabled", sections = { "flight_route" },
        aliases = { "taxi timer", "flight path timer" } },
    { id = "characterExtras", title = "Character sheet additions (Retail)", switch = "enabled",
        sections = { "character_extras", "character_model", "character_flyouts" },
        keywords = { "charakterfenster", "character window" } },
    { id = "merchantList", title = "Scrollable merchant offers (Retail)", switch = "enabled", sections = { "merchant_list" } },
    { id = "tooltipDetails", title = "Tooltip details and anchor (Retail)", switch = "enabled", sections = { "tooltip_details" } },
    { id = "popupAttention", title = "Dialogs and loot toasts (Retail)", switch = "enabled",
        sections = { "popup_attention", "popup_revive", "popup_toasts" } },
    { id = "tooltipIDs", title = "Tooltip IDs (Retail)", switch = "enabled", sections = { "tooltip_ids" } },
    { id = "tooltipVisibility", title = "Tooltip visibility", switch = "enabled", sections = { "tooltip_visibility" } },
    { id = "waypoints", title = "Waypoint command", switch = "enabled", sections = { "waypoint_command" } },
}
-- One visible home per feature. The module/settings identities above remain
-- unchanged, including the two switches owned by each of `loot` and `qol`.
local CATEGORIES = {
    { id = "everydayAutomation", title = "Everyday & Automation", keys = {
        "collectionNewMarkers.enabled", "dailyComfort.enabled", "delveSolePower.enabled",
        "trainerLearnAll.enabled", "autoUprank.enabled", "quests.enabled", "questRewardValue.enabled",
        "mailRecipients.enabled", "fishingComfort.enabled",
    } },
    { id = "lootMerchants", title = "Loot & Merchants", tabs = {
        { id = "loot", title = "Loot", keys = {
            "loot.quickLoot", "lootToastFilter.enabled", "vaultSpec.enabled", "loot.manageHistory",
            "lootContainers.enabled",
        } },
        { id = "merchants", title = "Merchants", keys = {
            "merchantLevel.enabled", "qol.repair", "qol.autoJunk", "lootVendorRules.enabled", "merchantList.enabled",
        } },
    } },
    { id = "characterGear", title = "Character & Gear", tabs = {
        { id = "character", title = "Character", keys = {
            "chatProfileLinks.enabled", "xpBar.enabled", "playerAuras.enabled", "playerAuraSkins.enabled", "loadoutReminder.enabled", "combatStatsHUD.enabled",
            "targetDistance.enabled", "characterExtras.enabled",
        } },
        { id = "gear", title = "Gear", keys = {
            "characterUpgradeWindow.enabled", "socketGemSuggestions.enabled", "durabilityAlert.enabled",
            "professionAppearance.enabled",
        } },
    } },
    { id = "groupRaid", title = "Group & Raid", keys = {
        "battleRes.enabled", "groupBloodlust.enabled", "groupDeathAlert.enabled", "innervateCue.enabled",
        "groupRaidShortcuts.enabled", "trustedPartyInvites.enabled", "autoResponses.enabled", "releaseProtection.enabled",
    } },
    { id = "groupFinderMythic", title = "Group Finder & Mythic+", tabs = {
        { id = "groupFinder", title = "Group Finder", keys = {
            "groupFinderExitReminder.enabled", "groupFinderDoubleClick.enabled", "groupFinderTools.enabled",
        } },
        { id = "mythic", title = "Mythic+", keys = {
            "mythicKeyShare.enabled", "mythicAutoQueue.enabled", "groupFinderApplicantSort.enabled", "mythicResetReminder.enabled",
            "tooltipMPlusScore.enabled", "enemyCastStack.enabled", "dungeonPortals.enabled",
        } },
    } },
    { id = "combatAlerts", title = "Combat & Alerts", keys = {
        "actionTracker.enabled", "burningRushCue.enabled", "combatLog.enabled", "macroBuilder.enabled",
        "combatMovementCue.enabled", "combatPetStatus.enabled",
        "threatMeter.enabled", "selfCombatText.enabled",
    } },
    { id = "mapTravel", title = "Map & Travel", keys = {
        "mapLandingShortcuts.enabled", "skyriding.enabled", "waypoints.enabled",
        "flightTimer.enabled",
    } },
    { id = "interfaceChat", title = "Interface & Chat", keys = {
        "cursorEffects.enabled", "guildChatPrivacy.enabled", "quietPopups.enabled", "uiErrorFilter.enabled", "popupAttention.enabled",
    } },
    { id = "tooltips", title = "Tooltips", keys = {
        "tooltipClassColors.enabled", "tooltipSpellCopy.enabled", "itemCounts.enabled", "tooltipIDs.enabled",
        "tooltipVisibility.enabled", "tooltipDetails.enabled",
    } },
}

P.PlayerAurasPage.FilterQualityOfLife(GROUPS, CATEGORIES)
P.ExtendQoLTools(GROUPS, CATEGORIES)
local byKey = {}
for _, group in ipairs(GROUPS) do byKey[group.id .. "." .. group.switch] = group end
local function ResolveFeatures(keys, category, tab)
    local features = {}
    for _, key in ipairs(keys) do
        local group = assert(byKey[key], "Unknown Quality of Life feature: " .. key)
        assert(not group.category, "Duplicate Quality of Life feature: " .. key)
        group.category, group.categoryTitle = category.id, category.title
        group.tab, group.tabTitle = tab and tab.id or nil, tab and tab.title or nil
        features[#features + 1] = group
    end
    return features
end
for _, category in ipairs(CATEGORIES) do
    category.features = {}
    if category.tabs then
        for _, tab in ipairs(category.tabs) do
            tab.features = ResolveFeatures(tab.keys, category, tab)
            for _, group in ipairs(tab.features) do category.features[#category.features + 1] = group end
            tab.keys = nil
        end
    else
        category.features = ResolveFeatures(category.keys, category)
    end
    category.keys = nil
end
for _, group in ipairs(GROUPS) do
    assert(group.category, "Uncategorized Quality of Life feature: " .. group.title)
end
function P.SortQualityOfLifeCategories()
    table.sort(GROUPS, P.QoLTitleLess)
    for _, category in ipairs(CATEGORIES) do
        table.sort(category.features, P.QoLTitleLess)
        if category.tabs then
            for _, tab in ipairs(category.tabs) do table.sort(tab.features, P.QoLTitleLess) end
            table.sort(category.tabs, P.QoLTitleLess)
        end
    end
    table.sort(CATEGORIES, P.QoLTitleLess)
    P.qualityOfLifeSorted = true
end
P.QualityOfLifeCategories = CATEGORIES
P.QualityOfLifeSearchFeatures = GROUPS
local function GroupEnabled(group)
    return P.Get(group.id, "enabled") == true and P.Get(group.id, group.switch) == true
end
local function SetGroupEnabled(group, value)
    if group.switch == "enabled" then return P.Set(group.id, "enabled", value) end
    local otherActive = P.Get(group.id, "enabled") == true and P.Get(group.id, group.other) == true
    return P.SetMany(group.id, { [group.switch] = value, enabled = value or otherActive })
end

local function GroupRules(group, source)
    local rules = {}
    for _, rule in ipairs(source) do
        if rule.key ~= group.switch and not rule.hidden then rules[#rules + 1] = rule end
    end
    return rules
end

local function SelectInnervateTarget()
    local name, realm = UnitFullName("target")
    if not P.Suite.PublicText(name) or not P.Suite.Public(realm) then return end
    P.Set("innervateCue", "targetName", realm and realm ~= "" and (name .. "-" .. realm) or name)
end

local function HasPlayerTarget()
    local player = UnitIsPlayer("target")
    return P.Suite.Public(player) and player == true
end

local function AddLoadoutAction(ctx, body, id, sectionId, y, width)
    P.Button(ctx, body, "Show the reminder now", 16, y, width,
        function() if S.LoadoutReminder then S.LoadoutReminder:Test() end end,
        function() return S.Status(id) == "Active" and not P.Combat() end,
        P.Meta(PAGE, id, "action.test", "action", sectionId))
    y = y - 38
    P.Button(ctx, body, "Save current build and loot spec", 16, y, width,
        function() if S.LoadoutReminder then S.LoadoutReminder:SaveCurrent() end end,
        function() return S.Status(id) == "Active" and not P.Combat() end,
        P.Meta(PAGE, id, "action.saveCurrent", "action", sectionId))
    y = y - 38
    P.Button(ctx, body, "Clear saved selection", 16, y, width,
        function() if S.LoadoutReminder then S.LoadoutReminder:ClearSaved() end end,
        function() return S.Status(id) == "Active" and not P.Combat() end,
        P.Meta(PAGE, id, "action.clearSaved", "action", sectionId))
    return y - 38
end


-- The Edit Mode element of each module that has one (spec.editElement).
local EDIT_ELEMENTS = {}
for id, spec in pairs(P.catalog) do
    if spec.editElement then EDIT_ELEMENTS[id] = spec.editElement end
end
-- Edit Mode elements that exist only in one setup: the cursor's global
-- cooldown circle is placed only while it stands on its own.
local EDIT_READY = { cursorEffects = function() return P.Get("cursorEffects", "gcdDetached") == true end }
-- Search offers the same Move / resize buttons (Menu/SearchActions.lua).
P.QualityOfLifeEditElements = EDIT_ELEMENTS


local function AddEditModeAction(ctx, body, id, sectionId, y, width, element)
    P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
        function() P.OpenEditMode(id, element) end,
        function()
            return P.EditModeReady() and S.Status(id) == "Active" and (not EDIT_READY[id] or EDIT_READY[id]())
        end,
        P.Meta(PAGE, id, "action.edit", "action", sectionId))
    return y - ((id == "xpBar" or id == "innervateCue") and 34 or 38)
end

local ROW_HEIGHT = 44

local function FeatureSectionId(group)
    return PAGE .. "_" .. group.id .. "_" .. group.sections[1]
end

-- Edit Mode uses the same exact feature route as search. Resolve it after the
-- page opens so lazy details and the selected subtab are ready before focus.
function P.Suite.Menu.FocusQualityOfLifeModule(id)
    if P.PlayerAurasPage.Open(id) then return true end
    local group = byKey[id .. ".enabled"]
    -- Multi-feature modules such as loot/merchant helpers open the overview.
    if not group then return true end
    local entry = P.M.cache and P.M.cache[PAGE]
    local resolve = entry and HM.GetMissingSectionResolver(entry)
    local section = resolve and resolve(FeatureSectionId(group))
    if not section then return false end
    -- Anchor the existing menu navigation to the detail panel itself. Focusing
    -- its collapsible entry would scroll to the category above the feature list.
    local called, opened, focused = P.M.SearchBridge.OpenSearchTarget(PAGE, "", nil, section, {},
        { pageKey = PAGE, sectionId = FeatureSectionId(group) })
    return called == true and opened == true and focused == true
end

local function FeatureRules(group)
    local sections, all = {}, {}
    for _, key in ipairs(group.sections) do
        local source = P.SectionRules(group.id, key)
        local rules = GroupRules(group, source)
        sections[#sections + 1] = { key = key, source = source, rules = rules }
        for _, rule in ipairs(rules) do all[#all + 1] = rule end
    end
    return sections, all
end

local function FeatureKeywords(group, includeAliases)
    local words = { group.title, Tr(group.title), group.categoryTitle, Tr(group.categoryTitle) }
    if includeAliases then
        for _, word in ipairs(group.aliases or {}) do words[#words + 1] = word end
    end
    for _, word in ipairs(group.keywords or {}) do words[#words + 1] = word end
    if group.tabTitle then
        words[#words + 1], words[#words + 2] = group.tabTitle, Tr(group.tabTitle)
    end
    for _, section in ipairs(group.sections) do
        for _, rule in ipairs(P.SectionRules(group.id, section)) do
            if not rule.hidden then
                words[#words + 1], words[#words + 2] = rule.label, Tr(rule.label)
            end
        end
    end
    return words
end

local function AddFeatureHelp(details, group, sections)
    local helpText = {}
    for _, section in ipairs(sections) do helpText[#helpText + 1] = P.QoLHelpText(section.key) end
    local title, text = Tr(group.title), table.concat(helpText, "\n\n")
    local info
    if P.W.HelpButton then
        info = P.W.HelpButton(details, title, text)
    else
        info = CreateFrame("Button", nil, details)
        info:SetSize(24, 24)
        P.T.ApplySurface(info, "card")
        local glyph = P.T.Font(info, "GameFontHighlight", "?", P.T.colors.text, "body")
        glyph:SetAllPoints(info)
        glyph:SetJustifyH("CENTER")
        glyph:SetJustifyV("MIDDLE")
        P.M.AddTooltip(info, title, text, { hook = true })
        info:SetScript("OnClick", function(self) self:GetScript("OnEnter")(self) end)
    end
    info:SetPoint("TOPRIGHT", details, "TOPRIGHT", -54, -10)
end

local function RuleSearchKind(rule)
    if rule.font or rule.texture or rule.choices then return "dropdown" end
    if type(rule.default) == "boolean" then return "toggle" end
    if type(rule.default) == "number" then return "slider" end
    return "textinput"
end

local function RegisterFeatureRuleSearch(group, sectionId, entries, keywords)
    for _, entry in ipairs(entries or {}) do
        if entry.widget then
            local rule = entry.rule
            local meta = P.Meta(PAGE, group.id, rule.key, "setting", sectionId)
            meta.pageKey, meta.kind = PAGE, RuleSearchKind(rule)
            meta.label, meta.keywords = Tr(rule.label), keywords
            P.M.RegisterSearchWidget(entry.widget, meta)
            HM.SetSearchTargetPrepare(entry.widget, function() return group.reveal(true) ~= nil end)
        end
    end
end

local function BuildFeatureDetails(ctx, panel, group, sectionId, width, sections, allRules, keywords)
    if #allRules == 0 and group.id ~= "mailTemplates" and not EDIT_ELEMENTS[group.id]
        and group.id ~= "xpBar" and group.id ~= "innervateCue" and group.id ~= "loadoutReminder"
        and group.id ~= "macroBuilder" then
        return nil, 0
    end
    local details = P.T.Panel(panel, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    P.T.ApplySurface(details, "card")
    details:SetSize(width, 100)
    HM.SetSectionWidth(details, width)
    HM.MarkContextColorHost(details)
    local heading = P.Text(details, group.title, 16, -14, width - 104, P.T.colors.text)
    heading:SetWordWrap(false)
    details.title = heading
    AddFeatureHelp(details, group, sections)
    local y = P.BuildQoLIndicatorPreview(ctx, details, group.id, width, -42)
    y = P.BuildNewToolActions(ctx, details, group.id, sectionId, y, width - 32)
    for _, section in ipairs(sections) do
        if #sections > 1 and section.source[1] then
            local subtitle = P.Text(details, section.source[1].sectionTitle, 16, y, width - 32, P.T.colors.text)
            y = y - math.max(14, math.ceil(subtitle:GetStringHeight() or 14)) - 6
        end
        if #section.rules > 0 then
            local _, entries
            y, entries = P.RuleGrid(ctx, details, PAGE, group.id, section.rules, y,
                width - 32, nil, sectionId)
            RegisterFeatureRuleSearch(group, sectionId, entries, keywords)
        end
        y = y - 12
    end
    local element = EDIT_ELEMENTS[group.id]
    if element then y = AddEditModeAction(ctx, details, group.id, sectionId, y, width - 32, element) end
    if group.id == "xpBar" then
        P.Button(ctx, details, "Reset session", 16, y, width - 32,
            function() if S.ResetXPSession then S.ResetXPSession() end end,
            function() return S.Status(group.id) == "Active" end,
            P.Meta(PAGE, group.id, "action.resetSession", "action", sectionId))
        y = y - 38
    elseif group.id == "innervateCue" then
        P.Button(ctx, details, "Use current player target", 16, y, width - 32,
            SelectInnervateTarget, HasPlayerTarget,
            P.Meta(PAGE, group.id, "action.target", "action", sectionId))
        y = y - 38
    elseif group.id == "loadoutReminder" then
        y = AddLoadoutAction(ctx, details, group.id, sectionId, y, width - 32)
    end
    local colorShortcut = P.AttachRuleColors(details, group.title, group.id, allRules)
    -- The host's color shortcut adjusts card titles; keep room for both it and help.
    heading:SetWidth(width - 104)
    if colorShortcut then
        P.M.RegisterControlMetadata(colorShortcut,
            P.Meta(PAGE, group.id, "action.colors." .. group.switch, "action", sectionId),
            Tr("%s Colors"):format(Tr(group.title)), "button")
    end
    if #allRules > 0 then
        -- A section reset restores the section's settings; whether the feature
        -- runs (allRules leaves its switch out) stays the player's choice.
        details._msufSuiteSectionReset = function()
            return P.ResetRules(group.id, allRules)
        end
        P.Button(ctx, details, "Reset section", 16, y, math.min(180, width - 32),
            details._msufSuiteSectionReset, function() return not P.Combat() end,
            P.Meta(PAGE, group.id, "action.reset." .. group.switch, "action", sectionId))
        y = y - 38
    end
    local height = math.max(72, -y + 12)
    details:SetHeight(height)
    details:Hide()
    return details, height, colorShortcut
end

local FALLBACK_ROW_ACCENT = { 0.23, 0.51, 0.96 }
local function PaintFeatureRow(row)
    local selected, hovered = row._msufSuiteSelected, row._msufSuiteHovered
    local shade, stripe = row._msufSuiteShade, row._msufSuiteStripe
    if selected then
        local accent = P.T.colors.coreGlow or P.T.colors.accent or FALLBACK_ROW_ACCENT
        shade:SetColorTexture(accent[1], accent[2], accent[3], hovered and 0.46 or 0.36)
        stripe:SetColorTexture(accent[1], accent[2], accent[3], 0.95)
    elseif hovered then
        local color = P.T.colors.pillHover or P.T.colors.panel2 or P.T.colors.panel
        shade:SetColorTexture(color[1], color[2], color[3], 0.55)
    else
        local color = P.T.colors.panel2 or P.T.colors.pillBase or P.T.colors.panel
        shade:SetColorTexture(color[1], color[2], color[3], row._msufSuiteEven and 0.34 or 0.22)
    end
    stripe:SetShown(selected == true)
end

local function FeatureSwitchMeta(group, sectionId)
    if group.id == "macroBuilder" then
        return P.Meta("suite_macros", group.id, group.switch, "setting")
    end
    return P.Meta(PAGE, group.id, group.switch, "setting", sectionId)
end

local function PrepareFeatureSwitch(toggle, group)
    HM.SetSearchTargetPrepare(toggle, function()
        if group.id == "macroBuilder" then
            P.MacroPage.PrepareSearch("consumable")
            return P.Suite.Menu.Open("suite_macros")
        end
        return group.reveal(true) ~= nil
    end)
end

local function BuildFeatureRow(ctx, panel, group, category, sectionId, width, index, hasDetails, onSettings)
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4 - (index - 1) * ROW_HEIGHT)
    row:SetSize(width, ROW_HEIGHT - 4)
    row:EnableMouse(true)
    local shade = row:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(row)
    local stripe = row:CreateTexture(nil, "BORDER")
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    stripe:SetWidth(3)
    row._msufSuiteShade, row._msufSuiteStripe = shade, stripe
    row._msufSuiteEven = index % 2 == 0
    PaintFeatureRow(row)
    row:SetScript("OnEnter", function(self)
        self._msufSuiteHovered = true
        PaintFeatureRow(self)
    end)
    row:SetScript("OnLeave", function(self)
        self._msufSuiteHovered = false
        PaintFeatureRow(self)
    end)
    local textWidth = width - (hasDetails and 164 or 78)
    local label = P.T.Font(row, "GameFontHighlightSmall", group.title, P.T.colors.text, "control")
    label:SetPoint("LEFT", row, "LEFT", 12, 0)
    label:SetWidth(textWidth)
    label:SetHeight(36)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(true)
    label:SetMaxLines(2)
    local toggle = P.W.SwitchAt(row, "", width - 52, -10, 0, "HIDDEN")
    local meta = FeatureSwitchMeta(group, sectionId)
    meta.label, meta.keywords = Tr(group.title), FeatureKeywords(group, true)
    P.M.BindBoolWidget(ctx, toggle,
        function() return GroupEnabled(group) end,
        function(value) SetGroupEnabled(group, value == true) end, meta)
    local searchMeta = FeatureSwitchMeta(group, sectionId)
    searchMeta.pageKey, searchMeta.kind = group.id == "macroBuilder" and "suite_macros" or PAGE, "toggle"
    searchMeta.label, searchMeta.keywords = Tr(group.title), meta.keywords
    P.M.RegisterSearchWidget(toggle, searchMeta)
    PrepareFeatureSwitch(toggle, group)
    local help = P.QoLHelpText(group.sections[1])
    P.M.AddTooltip(toggle, Tr(group.title), help, { hook = true })
    local settings
    if hasDetails then
        settings = P.T.Button(row, "Settings", 88, 25)
        settings:SetPoint("RIGHT", toggle, "LEFT", -10, 0)
        settings:SetScript("OnClick", function() onSettings(group, false) end)
        P.M.AddTooltip(settings, Tr(group.title), help, { hook = true })
        P.M.RegisterControlMetadata(settings,
            P.Meta(PAGE, group.id, "action.settings." .. group.switch, "action", sectionId),
            Tr(group.title) .. " " .. Tr("Settings"), "button")
        row:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then onSettings(group, false) end
        end)
    end
    P.M.AddTooltip(row, Tr(group.title), help, { hook = true })
    P.M.TrackRefresh(ctx, function()
        local available, reason = S.Availability(group.id)
        P.W.SetControlEnabled(toggle, not P.Combat())
        local suffix = available and "" or (reason and (" - " .. P.Suite.StatusText(reason, Tr)) or Tr(" - Unavailable"))
        P.SetTranslatedText(label, Tr(group.title) .. suffix)
        PaintFeatureRow(row)
    end)
    return row, toggle, settings, group.aliases and FeatureKeywords(group) or meta.keywords
end

local function LayoutFeatureRows(panel, features, records, selected, activeOnly)
    local offset = 4
    for _, group in ipairs(features) do
        local record = records[group]
        local shown = not activeOnly or GroupEnabled(group) or group == selected
        if record.shown ~= shown then
            record.row:SetShown(shown)
            record.shown = shown
        end
        if record.rowY ~= offset then
            record.row:ClearAllPoints()
            record.row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -offset)
            record.rowY = offset
        end
        if shown then offset = offset + ROW_HEIGHT end
        if record.details and group == selected then
            if record.detailsY ~= offset then
                record.details:ClearAllPoints()
                record.details:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -offset - 4)
                record.detailsY = offset
            end
            offset = offset + record.detailHeight + 12
        end
        local isSelected = group == selected
        if record.details and record.detailsShown ~= isSelected then
            record.details:SetShown(isSelected)
            record.detailsShown = isSelected
        end
        if record.row._msufSuiteSelected ~= isSelected then
            record.row._msufSuiteSelected = isSelected
            if record.settings then record.settings:SetActive(isSelected) end
            PaintFeatureRow(record.row)
        end
    end
    local height = offset + 4
    if panel.suiteQoLHeight ~= height then
        panel:SetHeight(height)
        panel.suiteQoLHeight = height
    end
    return height
end

local function BuildCategoryPanel(ctx, builder, body, entry, category, tab, width, panelTop,
        state, featureRows)
    local features, tabId = tab and tab.features or category.features, tab and tab.id or "main"
    local panel = CreateFrame("Frame", nil, body)
    panel:SetPoint("TOPLEFT", body, "TOPLEFT", 16, panelTop)
    panel:SetSize(width, 100)
    state.panels[tabId] = panel
    local records, selected = {}, nil
    local function Layout()
        local height = LayoutFeatureRows(panel, features, records, selected, ctx.suiteQoLActiveOnly)
        if (not category.tabs or state.activeTab == tabId) and (state.height ~= height or state.heightTab ~= tabId) then
            P.FinishBody(builder, body, panelTop - height)
            state.height, state.heightTab = height, tabId
        end
    end
    state.updateHeight[tabId] = Layout
    local function Select(group, force)
        local record = records[group]
        if record and record.hasDetails and not record.details then
            local details, height, colors = BuildFeatureDetails(ctx, panel, group,
                record.sectionId, width, record.sections, record.allRules, record.keywords)
            record.details, record.detailHeight, record.colorShortcut = details, height, colors
            HM.SetSectionEntry(details, entry)
            P.Refresh()
        end
        selected = (not force and selected == group) and nil or group
        Layout()
    end
    for index, group in ipairs(features) do
        local oldSectionId = FeatureSectionId(group)
        local sections, allRules = FeatureRules(group)
        local hasDetails = #allRules > 0 or group.id == "mailTemplates" or group.id == "macroBuilder"
            or EDIT_ELEMENTS[group.id] ~= nil
            or group.id == "xpBar" or group.id == "innervateCue" or group.id == "loadoutReminder"
        local row, toggle, settings, keywords = BuildFeatureRow(ctx, panel, group, category,
            oldSectionId, width, index, hasDetails, Select)
        HM.SetSectionEntry(row, entry)
        local record = {
            row = row, toggle = toggle, settings = settings, hasDetails = hasDetails,
            sectionId = oldSectionId, sections = sections, allRules = allRules,
            category = category.id, tab = tabId, title = group.title, keywords = keywords,
        }
        records[group] = record
        featureRows[oldSectionId] = record
        -- Legacy section IDs are virtual routes for search and menu links.
        group.reveal = function(force)
            if state.selectTab and category.tabs then state.selectTab(tabId) end
            if hasDetails or ctx.suiteQoLActiveOnly then Select(group, force ~= false) end
            return record.details or row
        end
        record.reveal = group.reveal
    end
    Layout()
    P.M.TrackRefresh(ctx, Layout)
end

-- Lazy category headers count enabled features; routes build their owner first.
local function CategoryShell(ctx, body, category, featureOrder, owners)
    for _, tab in ipairs(category.tabs or { category }) do
        for _, group in ipairs(tab.features) do
            local id = FeatureSectionId(group)
            owners[id], featureOrder[#featureOrder + 1] = body, id
        end
    end
    local entry = HM.GetSectionEntry(body)
    P.M.TrackRefresh(ctx, function()
        local enabled = 0
        for _, group in ipairs(category.features) do
            if GroupEnabled(group) then enabled = enabled + 1 end
        end
        P.SetTranslatedText(entry.label, Tr(category.title) .. "  "
            .. Tr("%d/%d enabled"):format(enabled, #category.features))
    end)
end

local function CategoryContent(ctx, builder, body, category, featureRows)
    local entry = HM.GetSectionEntry(body)
    local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local panelTop = category.tabs and -62 or -12
    local state = { panels = {}, updateHeight = {}, activeTab = category.tabs and category.tabs[1].id }
    if category.tabs then
        for _, tab in ipairs(category.tabs) do
            BuildCategoryPanel(ctx, builder, body, entry, category, tab, width, panelTop,
                state, featureRows)
        end
        local values = {}
        for _, tab in ipairs(category.tabs) do
            values[#values + 1] = { value = tab.id, text = Tr(tab.title) }
        end
        local tabs, refresh, _, choose = P.W.SegmentTabs(ctx, body, {
            label = "", values = values, width = math.min(400, width - 32),
            frames = state.panels, defaultTab = state.activeTab,
            get = function() return state.activeTab end,
            set = function(tab) state.activeTab = tab end,
            afterRefresh = function(tab) state.updateHeight[tab]() end,
            x = 16, y = -12,
        })
        P.HideControlTitle(tabs)
        state.selectTab = choose
        refresh()
    else
        BuildCategoryPanel(ctx, builder, body, entry, category, nil, width, panelTop,
            state, featureRows)
    end
end

local function BuildCategory(ctx, builder, category, featureRows, featureOrder, owners)
    P.LazySection(builder, PAGE .. "_category_" .. category.id, Tr(category.title), false, {
        content = function(body) CategoryContent(ctx, builder, body, category, featureRows) end,
        shell = function(body) CategoryShell(ctx, body, category, featureOrder, owners) end,
    })
end

local function Build(ctx)
    P.SortQualityOfLifeCategories()
    local builder = P.W.PageBuilder(ctx)
    if builder.Section then
        local header = builder:Section(Tr("Quality of Life"), 72)
        if header.title then header.title:Hide() end
        P.M.BindDropdownAt(ctx, header, Tr("Show"), 16, -8, {
            { value = false, text = Tr("All") }, { value = true, text = Tr("Enabled only") },
        }, math.max(240, (builder.width or 720) - 32), function() return ctx.suiteQoLActiveOnly == true end,
            function(value) ctx.suiteQoLActiveOnly = value == true
                P.Refresh() end,
            P.Meta(PAGE, "qol", "view.enabled", "ephemeral"))
    end
    local rows, order, owners = {}, {}, {}
    ctx.qualityOfLifeFeatureRows, ctx.qualityOfLifeFeatureOrder = rows, order
    if ctx.entry then
        ctx.entry.qualityOfLifeFeatureRows = rows
        ctx.entry.qualityOfLifeFeatureOrder = order
        ctx.entry.sections = ctx.entry.sections or {}
        HM.SetMissingSectionResolver(ctx.entry, function(sectionId)
            -- A lazy category builds its rows first (never in combat).
            if not rows[sectionId] then P.EnsureSectionContent(owners[sectionId]) end
            local record = rows[sectionId]
            return record and record.reveal(true) or nil
        end)
    end
    for _, category in ipairs(CATEGORIES) do
        BuildCategory(ctx, builder, category, rows, order, owners)
    end
    P.BuildGraphicsPerformance(ctx, builder)
end

P.RegisterPage({ key = PAGE, label = "Quality of Life", title = "Quality of Life", build = Build, notice = P.BuildGraphicsNotice, icon = { 7, 1 },
    nav = "general", navOrder = 1,
    aliases = { "qol", "qualityoflife", "quality_of_life", "actiontracker", "actions", "casts", "merchant",
        "itemlevel", "vault", "lootspec", "tooltipids", "loot", "quests", "combatlog", "logging", "comfort",
        "experience", "xpbar", "xp", "innervate", "whisper", "durability", "repairwarning", "battleres", "brez",
        "combatres", "skyriding", "vigor", "secondwind", "groupfinder", "keys", "keystone", "bloodlust" } })
