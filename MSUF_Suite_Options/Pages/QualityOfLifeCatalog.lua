local _, P = ...
-- Aliases name feature switches; keywords also describe their detail controls.
local GROUPS = {
    { id = "foreverWorldMap", title = "World map information (Forever)", switch = "enabled",
        sections = { "forever_world_map" }, aliases = { "zone levels", "travel markers", "world map" } },
    { id = "gatheringTooltips", title = "Gathering tooltips (Forever)", switch = "enabled",
        sections = { "gathering_tooltips" }, aliases = { "herbalism", "mining", "gathering skill" } },
    { id = "gatheringRoutes", title = "Resource routes", switch = "enabled",
        sections = { "gathering_routes" },
        aliases = { "gathering guide", "gathering radar", "farmhud", "farming route", "sammelroute", "sammelpfeil" } },
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
    { id = "glimmer", title = "Glimmer (Forever)", switch = "enabled",
        sections = { "glimmer_objects", "glimmer_appearance" },
        aliases = { "glimmer", "glimmern", "questhelp", "quest help", "questhelper", "quest helper", "questhilfe",
            "quest hilfe", "questobjekte", "questgegenstände", "questgegenstaende", "sammelobjekte", "funkeln",
            "quest sparkle", "quest sparkles", "loot sparkle", "loot sparkles", "quest glow", "gathering",
            "erz", "erze", "kräuter", "kraeuter", "ore", "herbs" } },
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
-- Keep registration cheap: only identities are collected while Options loads.
-- Feature widgets and translated sorting belong to the selected page.
P.PlayerAurasPage.FilterQualityOfLife(GROUPS, {})
P.ExtendQoLTools(GROUPS, {})
local V = {}
P.QoLView = V
local CATEGORIES = {
    { id = "character", title = "Character" },
    { id = "lootMerchants", title = "Loot & Merchants" },
    { id = "questsProfessions", title = "Quests & Professions" },
    { id = "groups", title = "Groups" },
    { id = "travel", title = "Travel" },
    { id = "interface", title = "Interface" },
}
V.GameplayCategory = { id = "gameplay", title = "Gameplay" }
local initialized = false
local function Subgroup(id, title, keys)
    return { id = id, title = title, keys = keys, features = {} }
end
local function Definitions()
return {
    { id = "character", title = "Character", subgroups = {
        Subgroup("character", "Character",
            "chatProfileLinks xpBar loadoutReminder characterExtras collectionNewMarkers autoUprank playerAuras playerAuraSkins"),
        Subgroup("gear", "Gear", "characterUpgradeWindow socketGemSuggestions durabilityAlert"),
    } },
    { id = "lootMerchants", title = "Loot & Merchants", subgroups = {
        Subgroup("loot", "Loot", "loot.quickLoot lootToastFilter vaultSpec loot.manageHistory lootContainers"),
        Subgroup("merchants", "Merchants", "merchantLevel qol.repair qol.autoJunk lootVendorRules merchantList inventoryProtection"),
    } },
    { id = "questsProfessions", title = "Quests & Professions", subgroups = {
        Subgroup("quests", "Quests", "quests questRewardValue"),
        Subgroup("professions", "Professions", "trainerLearnAll fishingComfort professionAppearance gatheringTooltips gatheringRoutes"),
    } },
    { id = "groups", title = "Groups", subgroups = {
        Subgroup("groupRaid", "Group & Raid", "groupRaidShortcuts trustedPartyInvites autoResponses releaseProtection"),
        Subgroup("groupFinder", "Group Finder", "groupFinderExitReminder groupFinderDoubleClick groupFinderTools groupFinderApplicantSort"),
        Subgroup("mythic", "Dungeons & Raids", "mythicKeyShare mythicAutoQueue mythicResetReminder combatLog delveSolePower"),
    } },
    { id = "travel", title = "Travel", subgroups = {
        Subgroup("travel", "Map & Travel", "mapLandingShortcuts skyriding waypoints flightTimer glimmer waypointLists dungeonPortals foreverWorldMap"),
    } },
    { id = "interface", title = "Interface", subgroups = {
        Subgroup("interface", "Interface", "dailyComfort soundProfiles"),
        Subgroup("chat", "Chat & Mail", "mailRecipients mailTemplates guildChatPrivacy"),
        Subgroup("notifications", "Notifications", "quietPopups uiErrorFilter popupAttention notificationHistory"),
        Subgroup("tooltips", "Tooltips", "tooltipClassColors tooltipSpellCopy itemCounts tooltipIDs tooltipVisibility tooltipDetails tooltipMPlusScore"),
    } },
}
end
local function GameplayGroups()
return {
    Subgroup("combatInformation", "Combat information", "actionTracker selfCombatText combatStatsHUD targetDistance threatMeter"),
    Subgroup("combatCues", "Combat cues", "burningRushCue combatMovementCue combatPetStatus cursorEffects"),
    Subgroup("groupCombat", "Group combat", "battleRes groupBloodlust groupDeathAlert innervateCue enemyCastStack"),
}
end
V.LegacyCategories = {
    characterGear = "character", everydayAutomation = "questsProfessions", groupRaid = "groups",
    groupFinderMythic = "groups", combatAlerts = "gameplay", mapTravel = "travel",
    interfaceChat = "interface", tooltips = "interface",
}

local function Resolve(category, byKey)
    category.features = {}
    for _, subgroup in ipairs(category.subgroups) do
        for key in subgroup.keys:gmatch("%S+") do
            local group = byKey[key]
            -- Embedded host pages remove the identities they now own.
            if group then
                assert(not group.category, "Duplicate Quality of Life feature: " .. key)
                group.category, group.categoryTitle = category.id, category.title
                group.tab, group.tabTitle = subgroup.id, subgroup.title
                subgroup.features[#subgroup.features + 1] = group
                category.features[#category.features + 1] = group
            else
                assert(P.PlayerAurasPage.Relocated(key),
                    "Unknown Quality of Life feature: " .. key)
            end
        end
        subgroup.keys = nil
    end
end
local function Initialize()
    if initialized then return end
    local byKey = {}
    for _, group in ipairs(GROUPS) do
        local key = group.switch == "enabled" and group.id or group.id .. "." .. group.switch
        byKey[key] = group
    end
    for index, definition in ipairs(Definitions()) do
        CATEGORIES[index].subgroups = definition.subgroups
        Resolve(CATEGORIES[index], byKey)
    end
    V.GameplayCategory.subgroups = GameplayGroups()
    Resolve(V.GameplayCategory, byKey)
    local macro = byKey.macroBuilder
    macro.category, macro.categoryTitle, macro.pageKey = "macros", "Macros", "suite_macros"
    for _, group in ipairs(GROUPS) do assert(group.category, "Uncategorized Quality of Life feature: " .. group.title) end
    initialized = true
end

function V.FindFeature(id, switch)
    Initialize()
    for _, group in ipairs(GROUPS) do
        if group.id == id and group.switch == (switch or "enabled") then return group end
    end
end

function V.GetFeaturePage(group)
    if group.id == "macroBuilder" then return "suite_macros" end
    if P.GameplayPage.Relocated(group.id) then return "gameplay" end
    return P.QoLOwners.PageFor(group.id) or "suite_qualityOfLife"
end

function V.GetCategories()
    Initialize()
    local result = {}
    for _, category in ipairs(CATEGORIES) do
        local view = { id = category.id, title = category.title, features = {}, subgroups = {} }
        for _, subgroup in ipairs(category.subgroups) do
            local group = { id = subgroup.id, title = subgroup.title, features = {} }
            for _, feature in ipairs(subgroup.features) do
                if V.GetFeaturePage(feature) == "suite_qualityOfLife" then
                    group.features[#group.features + 1] = feature
                    view.features[#view.features + 1] = feature
                end
            end
            if #group.features > 0 then view.subgroups[#view.subgroups + 1] = group end
        end
        table.sort(view.features, P.QoLTitleLess)
        if #view.features > 0 then result[#result + 1] = view end
    end
    if not P.GameplayPage.registered then result[#result + 1] = V.GameplayCategory end
    return result
end

local function SortCategory(category)
    table.sort(category.features, P.QoLTitleLess)
    for _, subgroup in ipairs(category.subgroups) do table.sort(subgroup.features, P.QoLTitleLess) end
end

function P.SortQualityOfLifeCategories()
    Initialize()
    table.sort(GROUPS, P.QoLTitleLess)
    for _, category in ipairs(CATEGORIES) do SortCategory(category) end
    SortCategory(V.GameplayCategory)
    for _, group in ipairs(GROUPS) do group.pageKey = V.GetFeaturePage(group) end
    P.qualityOfLifeSorted = true
end
P.QualityOfLifeCategories = CATEGORIES
P.QualityOfLifeSearchFeatures = GROUPS
