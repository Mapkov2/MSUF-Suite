local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE = "suite_qualityOfLife"

local HELP = {
    self_combat_text = "Shows incoming damage and healing for you or your vehicle. Blizzard's own combat text is hidden while enabled and restored when disabled. Move the display in MSUF Edit Mode. During heavy bursts the oldest of the visible messages is replaced. The game may keep amounts private, so messages are never combined or filtered by their value.",
    character_extras = "A small summary sits beside the Character tab of your character sheet and leaves with it. It lists your gear with gem sockets and how many are filled, open ones in amber (click a line to open socketing), the total durability of your gear and, if you like, your PvP item level. Its buttons open the Great Vault and the current expansion page. It updates while the sheet is open, at most once per frame.",
    character_model = "Shows the total durability of your gear on the character model, moved by the two offsets, and crops the edges of the gear slot icons on your character sheet and in the Inspect window.",
    character_flyouts = "Equipment choices (the list that opens from a gear slot) show the item level on each item, so you can compare without hovering. The arrows beside the gear slots can be hidden; hold Alt over a slot to open its choices.",
    popup_attention = "The Suite look gives Blizzard's dialogs a dark panel, and the Suite font sets their text font and size; each works alone, and without them dialogs keep Blizzard's look and fonts. A minimum height makes short dialogs taller once Blizzard has sized them; 0 keeps Blizzard's height. A custom position moves the first dialog and the ones Blizzard stacks below it; place it and set the height in MSUF Edit Mode.",
    popup_revive = "When someone offers you a resurrection, its dialog gets a green frame, optionally with Blizzard's ready check sound, and its accept button can get a green frame of its own. Accepting stays your click.",
    popup_toasts = "Loot toasts write the item quality as a word in its color, such as Epic or Rare, next to Blizzard's colored item name; currency toasts stay as they are. Money toasts can get a thin gold frame.",
    tooltip_details = "Adds guild rank, the hovered unit's target, item levels, the unit's current mount and item or spell details to Blizzard's main tooltip, and can show player names without titles. Your own item level and the one of the unit open in the Inspect window need no request. Item levels of other hovered players are a separate choice that sends inspect requests: at most one per hover, never while the Inspect window or another inspect is busy. Mounts are read once when a unit tooltip opens, out of combat; a change appears on the next hover. Place the fixed corner in MSUF Edit Mode; the cursor offsets apply to the cursor anchor.",
    dungeon_casts = "Lists the casts of attackable enemy nameplates while you are in a five-player dungeon, oldest first; the game runs each bar and timer. The game keeps spell, target, marker and interrupt details hidden from addons, so casts are never sorted or filtered by them: fading or hiding uses the game's important-spell flag (a hidden cast keeps its place in the list), raid markers sit on the spell icon, and the ready mark, an edge stripe or the whole bar, shows on interruptible casts while your interrupt is off cooldown. Dimming checks four times a second whether your interrupt reaches each listed enemy; a cast it cannot check stays bright. The interrupt is found from your talents and pet unless you enter a spell ID. MSUF Edit Mode shows sample casts for placing the list.",
    target_distance = "Shows an approximate range to your current target from the game's range checks of spells you know; values include the target's hitbox, and dashes mean that no known spell can tell. Write the text with {range} and {unit}. The estimate can sit below the target frame, following it when the frame moves, or anywhere on screen; MSUF Edit Mode moves both placements.",
    action_tracker_visibility = "Choose where recent actions appear. Delves have their own switch; battlegrounds and arenas share one, and other scenarios follow Outside instances. Where the tracker is switched off, it does not listen to your casts.",
    cursor_gcd = "The global cooldown can leave the ring for a fixed circle of its own size and opacity, shown next to casts. Place it in MSUF Edit Mode; its button there works while this choice is on.",
    stats_numbers = "Numbers can be percentages, combat rating or both on two lines, and stat names short or full. Leech, avoidance and speed each have their own value color; the other stats follow the strip's style.",
    stats_fps = "A frame-rate readout can sit below the strip or on its own, placed in MSUF Edit Mode. The MSUF Suite FPS key binding shows or hides it for this session, in combat too; a new choice here replaces that session switch.",
    mythic_reset = "The keystone notice remains local. The optional group announcement forwards only Blizzard's confirmed reset message immediately after your own reset request, while you are group leader. Failed attempts and resets by other players are not announced.",
    dungeon_portals = "Learned dungeon portals use secure buttons. Group suggestions require a verified dungeon map or an exact destination match. Unknown destinations show no suggestion; buttons hide in combat.",
    action_tracker = "Shows your most recent successful spells. Standard rows have an icon, name and marker; Icons only is a compact vertical icon column. Display width applies to standard rows; icon width follows row height in the icon preset. Position and anchor are set in MSUF Edit Mode, which shows sample actions. The list stops listening while disabled. Spells whose details the client keeps private cannot appear.",
    action_tracker_colors = "Choose a style above or change these colors to make a Custom look. Rows update immediately.",
    repair = "Repairs only when the cost is within your limit. Guild funds are used first when allowed.",
    junk = "Uses Blizzard's Sell All Junk action when a merchant opens, including its per-bag exclusions. Hold Shift while opening the merchant to skip selling. The optional chat line confirms the request, not completed sales.",
    automation = "Hold Shift to pause. Quests with a money cost and quests with a reward choice always stay manual.",
    filters = "An empty allow-list includes every quest. Separate quest IDs with spaces or commas. Daily and weekly exclusions leave a quest manual if its frequency cannot be read. Existing profiles keep their previous behavior until you enable an exclusion.",
    merchant_level = "Shows item levels on merchant equipment when Blizzard has loaded its item data. Buyback items and items without an item level stay unchanged.",
    merchant_list = "Replaces the merchant's pages with one list; scroll it with the mouse wheel or the bar. Right-click buys, left-click picks an item up and Shift-click asks for a quantity; linking and previewing work as usual. Purchases paid with currencies or items, or costing at least 150 gold, ask for confirmation first. The buyback tab keeps Blizzard's layout. Drop or click an item from your bags onto the list to sell it; one you can still refund asks whether to refund it.",
    vault_spec = "Shows the current loot specialization when you open the Great Vault. Updates if you change loot specialization while the window is open.",
    tooltip_ids = "Hold Alt to see the ID of an item, spell, creature, quest, currency or temporary weapon enchant on its tooltip, or press Alt while the tooltip is open; the IDs stay until the tooltip is built again. Spell icon IDs and Blizzard's account character currency data are optional, and that data joins an open tooltip when it arrives. No ID or quantity appears when the client keeps it private.",
    tooltip_visibility = "Hide Blizzard's main tooltip in combat, in instances, or for selected item, spell and unit tooltips. MSUF unit and group frame tooltips keep their own visibility settings; aura tooltips keep their Show Tooltip switches. Each choice works independently. A hidden tooltip turns fully transparent, so Blizzard keeps handling it as usual.",
    item_counts = "Shows the number you own, including your bank and Warband bank, when the item tooltip has a public item ID. Optionally separate storage locations. Empty counts are omitted.",
    socket_gems = "Lists carried gem types beside Blizzard's socket window. Inspect each gem with its normal bag tooltip and confirm compatibility in the native socket window before applying it.",
    copy_spell_id = "Hover a spell and type /msufcopyspell to select its public ID in a small edit box. Press Ctrl+C to copy it. You can also pass an ID to the command. No clipboard action runs automatically.",
    mplus_score = "Adds the current-season Mythic+ score to the main tooltip of another player when Blizzard provides a public score. Unknown or restricted scores stay hidden.",
    class_colors = "Colors player names on the main tooltip with Blizzard's class palette. Other unit names keep their normal colors.",
    macro_builder = "Type /msufmacro to preview a mouseover ally, mouseover enemy or focus enemy macro. Enter a spell name or ID, then explicitly create a character macro outside combat. Drag it from /macro to your action bar.",
    profile_links = "Native character context menus offer Raider.IO and Warcraft Logs links. Select one to open a copyable URL; press Ctrl+C in its edit box. No chat message text is read, and no browser opens automatically.",
    waypoint_command = "Type /way x y for the current map or /way mapID x y. /msufway always works. The short /way alias is used only when no other addon owns it.",
    daily_comfort = "Cinematic confirmation can be skipped after you choose to exit. Automatic skipping is a separate option and also skips movies. Both stay inactive during combat, and a vehicle sequence always keeps its exit confirmation. Hide tutorials while this helper is enabled, prefill the DELETE word while keeping the final confirmation manual, hide only the successful screenshot notice, or open your character window at merchants on the tab you used last. At the auction house, Blizzard's filter button is marked while Current Expansion Only is off; tick it there once and Blizzard keeps it for this character.",
    daily_cvars = "Optional Blizzard settings for chat, map, sound and low-health or alternate screen flashes. MSUF restores the previous value when you turn a choice or this helper off. Changes you make yourself in Blizzard settings while this helper runs are respected.",
    collection_markers = "Clear only new mount, pet and toy fanfares acquired while this helper is active. Your collection entries remain available. Each collection type can be switched off independently.",
    guild_privacy = "Type /msufguildprivacy or use the small ON/OFF button above the main chat window. Any chat window containing Guild or Officer is covered in full, including other channels in a mixed window. Click a cover to reveal the windows again. Messages keep arriving underneath.",
    ui_error_filter = "Hide only the selected error types. Blizzard keeps handling all other messages and their sounds. Each choice remembers and restores its previous display state when you turn it off.",
    cursor_effects = "A ring around the mouse pointer that makes it easy to find. Pick its shape, size, color, an optional short trail and a centre dot; No ring keeps only the dot or the progress fill. The camera mode shows ring, dot and trail only while you hold a mouse button down on the game world to turn the camera. The highlight follows the pointer only while something is shown, and it moves nothing while the pointer rests.",
    cursor_progress = "Blizzard's own cooldown swipe fills the ring: the global cooldown after each ability, and casts or channels while they run. A cast takes the place of the global cooldown until it ends; the bright edge marks how far the cast has come.",
    cursor_when = "Limit the whole highlight to combat, to instances or to the open world, then give the pointer ring, the global cooldown and the cast fill their own combat rule. Nothing follows the pointer while it is hidden.",
    expansion_shortcuts = "An adjacent button opens a small menu for expansion, Great Vault, Adventure Guide and world map pages. Blizzard's landing button keeps its own click behavior. Menu actions are disabled in combat.",
    secondary_stats = "Critical strike, haste, mastery and versatility as your character sheet shows them; leech, avoidance and speed can each join the strip (speed is the stat, not your running speed). Show only in combat hides the strip outside fights. Values the game hides show a dash, and the strip updates from your stat events. MSUF Edit Mode moves the strip.",
    pet_status = "Warn when your pet is missing or dead. By default, the missing warning applies to Hunters and Warlocks; the dead warning applies to any class with a pet. MSUF Edit Mode moves the alert.",
    movement_cue = "Enter up to eight spell IDs for movement abilities. When movement begins, the first known, ready and usable spell appears briefly; a shared 20-second cooldown limits notices. Empty IDs do no work. MSUF Edit Mode moves the cue.",
    burning_rush_cue = "For Warlocks: show Burning Rush only while its aura is active in combat. Blizzard's native aura container follows the aura; Suite does not scan auras. MSUF Edit Mode shows a sample and moves the cue.",
    group_death_alert = "Reports the first observed death of each group member during combat. Local chat, a screen notice and a sound can be selected separately. Simultaneous deaths share one sound. Optionally include your own death. The listener is active only while you are grouped and in combat.",
    release_protection = "Hold the selected key while clicking Release Spirit. The release button stays hidden until you hold it; resurrection and death recap remain available. Choose where to use the protection. Blizzard's automatic release timer is unchanged.",
    bloodlust_lockout = "Shows your own Bloodlust exhaustion while in a group, or a ready state if you prefer. Relevant player aura changes update it; MSUF Edit Mode moves it and previews the locked state.",
    group_finder_double_click = "Double-click a search result to open Blizzard's application dialog. With submit on double-click, the second click also signs up with the roles already chosen in that dialog; hold Shift to review it instead. A saved note can appear beside the dialog for copying; it is stored when you finish editing.",
    group_finder_applicant_sort = "Sort applicants for your own Mythic+ listing by their average member score, highest first. Ties keep Blizzard's order. If any score is missing or restricted, the native order remains. The closed list is untouched.",
    group_finder_exit = "When the native group listing panel closes with applications still active, show their count in your own chat. Your applications remain active and no group chat is sent.",
    trusted_invites = "Accept only ordinary party invitations from the relationship types you select. Invites remain manual in combat, while grouped, during queue-loss or quest-session confirmations, or when Blizzard asks you to choose a role. The native popup handles the final action.",
    raid_shortcuts = "Type /msufraid to expand Blizzard's Raid Manager, /msufpull [1-60] for its native countdown, or /msufmark tank or /msufmark healer to mark one unambiguous party member. Optional automatic markers work only for one clear tank or healer in a five-player party, as leader or assistant. Existing and occupied markers are respected. Countdowns, markers and ready checks wait while Blizzard restricts them during combat, encounters and keystones; automatic markers try again afterwards.",
    keystone_command = "Type /keys or /msufkeys to see your own current keystone. Add party, raid or instance to share it in that channel. /keys group requests keys from group members running this Suite helper. The /keys alias is used only when another addon has not claimed it. Inside dungeons and raids Blizzard locks chat for addons; your key is then shown only to you.",
    delve_sole_power = "Only in an active Delve and outside combat: if the player choice has exactly one enabled spell option, one button and no confirmation, MSUF selects it once. Other choices remain manual.",
    loadout_reminder = "Shows your current talent build and loot specialization on ready checks, when a dungeon queue pops, or when you enter an instance. It never changes your talents or loot spec.",
    loadout_expectation = "Save your current build and loot specialization for this character in the active profile. A different selection highlights the reminder. Clear the saved selection to show current information without a comparison.",
    quiet_popups = "Choose each Blizzard popup separately. The feature hides its window when it appears and leaves the underlying game events intact. Combat lockdown can prevent hiding a protected window.",
    collection = "Adds automatic collection on top of Blizzard's own Auto Loot setting, which stays unchanged. Locked slots and confirmations stay manual.",
    history = "Hides or briefly shows the loot history window. Need, Greed and Pass popups stay available.",
    open_containers = "Only containers newly acquired after enabling this helper are opened. It waits for combat to end, opens one at a time, and leaves them to you while you hold Shift or a loot window or a window that gives item use another meaning is open: merchant, bank, guild bank, mail, trade, auction house, scrapper, socket, upgrade and similar. Warbound containers stay unopened unless you allow them; profiles that used this helper before keep opening them. Midnight Artisan payouts can wait while your Shard of Dundun is capped.",
    marked_sales = "Enter up to 200 item IDs. A button appears only at a merchant and previews eligible stacks; clicking it opens a confirmation. The helper checks item identity, quality, value, quest status and bag position again before requesting sales. Equippable items require a separate opt-in.",
    filtered_loot = "Shows up to three extra compact notices for Blizzard personal item-loot toasts. Filter by minimum quality, mount or pet items, and optionally up to 100 item IDs. Native Blizzard notices remain visible; ordinary bag additions without a toast are not included.",
    trainer_all = "At a trainer, review the count and combined gold cost before buying. The button learns only abilities already available at confirmation, checks each step again, and stops when the trainer closes, combat starts or the list changes. Profession choices and rank steps stay manual.",
    upgrade_equipment = "Opens your character window, on the tab you used last, when an item upgrade merchant opens. It closes only a window this helper opened and waits for the end of combat to open or close it.",
    profession_outfits = "Selected profession outfits and cosmetic auras are removed outside combat. Fishing is excluded. Noggenfogger skeleton removal also removes its underwater-breathing effect. Client refusal stops this helper until settings change.",
    log_dungeons = "Choose the dungeon difficulties where MSUF starts the combat log. Mythic+ begins when the keystone starts.",
    log_raids = "Choose the raid difficulties where MSUF starts the combat log.",
    log_other = "Battlegrounds, arenas, scenarios and delves are independent choices.",
    log_exit = "MSUF stops only a log it started. A log that was already on stays on. Re-entering selected content cancels a pending stop. WoW writes the log in its Logs folder.",
    xp_bar = "Choose Clean Modern, Midnight Blue, neutral Midnight Dark glass or MSUF Forever's dark gold frame. All use MSUF's bar texture and font. Turn the 20 XP divisions on or off. The lower line can show session gain, XP per hour and time to level. Move or resize the bar in MSUF Edit Mode; its popup edits X, Y, width, height and scale. Hover for exact values. A session survives /reload and starts fresh on the next login.",
    innervate_cue = "Retail Druids only. Every incoming whisper in combat is a possible Innervate cue; message text cannot be inspected reliably during chat lockdown. The alert waits for a publicly known Innervate cooldown, or shows a generic cue when readiness is unavailable. A preferred target can be outlined on an MSUF group frame resolved outside combat. MSUF Edit Mode previews the alert and edits its position and size.",
    durability_warning = "Shows the lowest equipped durability below your chosen threshold, outside combat. MSUF Edit Mode shows a sample even when your gear is repaired. Its popup edits X, Y, width, height and scale.",
    battle_res = "Shows Blizzard's shared battle resurrection charges in an active Mythic+ run or raid encounter. The icon counts down to the next charge using Blizzard's cooldown display. Hidden when the shared pool is unavailable. MSUF Edit Mode previews the display and edits X, Y, width, height and scale.",
    flight_hud = "Retail only. Shows while Skyriding is available, or only in flight if selected. Choose bars or Blizzard Vigor gems; gem scale and a refill sound are optional. Separate bar heights, Surge icon size and speed-value offsets are under Text and bars. MSUF Edit Mode previews the HUD. Unknown charge values display as dashes.",
    threat_meter = "WoW Forever only. Lists your group's threat on the watched enemy from Blizzard's threat data, highest first; for a friendly target, its enemy is used. Values the game keeps hidden are left out. Turn the mouse wheel over the window when more members are listed than rows fit. The red mark shows where you would take aggro, which is not the point where you match the tank. The meter repaints at most five times a second and reads no combat log.",
    flight_route = "Forever only. Route times are learned from completed flight-master journeys and kept in this profile. A first journey has no invented estimate. Early landing does not overwrite a full-route time. Intermediate stops come from the native taxi map; its tooltip can preview the route. Land at next stop requests the next available landing point.",
    flight_typography = "Choose an MSUF or SharedMedia font and bar texture. Font size, outline, shadow, Smooth/Sharp/Slug rendering, bar height and spacing update the HUD immediately. Slug has no shadow.",
    flight_colors = "Pick a preset above or use the three color dots in this header for your own colors. Changing a color marks the look as Custom. Panel opacity and empty bar opacity are separate.",
}

local GROUPS = {
    { id = "selfCombatText", title = "Own combat text", switch = "enabled", sections = { "self_combat_text" },
        keywords = { "SCT", "FCT", "floating combat text", "Kampftext", "Schadenszahlen", "Heilungszahlen" } },
    -- Keep the visible feature names alphabetic; section IDs stay stable for search and history.
    { id = "actionTracker", title = "Action tracker", switch = "enabled",
        sections = { "action_tracker", "action_tracker_visibility", "action_tracker_colors" } },
    { id = "dungeonPortals", title = "Dungeon portals (Retail)", switch = "enabled", sections = { "dungeon_portals" } },
    { id = "enemyCastStack", title = "Dungeon cast stack (Retail)", switch = "enabled",
        sections = { "dungeon_casts" } },
    { id = "groupFinderExitReminder", title = "Active application reminder (Retail)", switch = "enabled",
        sections = { "group_finder_exit" } },
    { id = "trustedPartyInvites", title = "Trusted party invites (Retail)", switch = "enabled",
        sections = { "trusted_invites" } },
    { id = "battleRes", title = "Battle resurrection (Retail)", switch = "enabled",
        sections = { "battle_res" } },
    { id = "groupBloodlust", title = "Bloodlust lockout (Retail)", switch = "enabled", sections = { "bloodlust_lockout" } },
    { id = "loot", title = "Collecting loot", switch = "quickLoot", other = "manageHistory", sections = { "collection" } },
    { id = "collectionNewMarkers", title = "Collection new markers (Retail)", switch = "enabled", sections = { "collection_markers" } },
    { id = "combatLog", title = "Combat logging", switch = "enabled",
        sections = { "log_dungeons", "log_raids", "log_other", "log_exit" } },
    { id = "cursorEffects", title = "Cursor highlight (Retail)", switch = "enabled",
        sections = { "cursor_effects", "cursor_progress", "cursor_gcd", "cursor_when" } },
    { id = "dailyComfort", title = "Daily UI comforts", switch = "enabled", sections = { "daily_comfort", "daily_cvars" } },
    { id = "delveSolePower", title = "Delve single power (Retail)", switch = "enabled",
        sections = { "delve_sole_power" } },
    { id = "xpBar", title = "Experience bar", switch = "enabled", sections = { "xp_bar" } },
    { id = "mapLandingShortcuts", title = "Expansion shortcuts (Retail)", switch = "enabled",
        sections = { "expansion_shortcuts" } },
    { id = "vaultSpec", title = "Great Vault loot spec (Retail)", switch = "enabled", sections = { "vault_spec" } },
    { id = "groupDeathAlert", title = "Group death alert", switch = "enabled", sections = { "group_death_alert" } },
    { id = "releaseProtection", title = "Release spirit protection", switch = "enabled", sections = { "release_protection" },
        keywords = { "freilassen", "releasen", "geist freilassen", "release schutz", "release-schutz", "anti release" } },
    { id = "groupFinderDoubleClick", title = "Group finder double-click (Retail)", switch = "enabled",
        sections = { "group_finder_double_click" } },
    { id = "groupFinderApplicantSort", title = "Mythic+ applicant score sorting (Retail)", switch = "enabled",
        sections = { "group_finder_applicant_sort" } },
    { id = "guildChatPrivacy", title = "Guild chat privacy cover (Retail)", switch = "enabled",
        sections = { "guild_privacy" } },
    { id = "innervateCue", title = "Innervate whisper cue (Retail Druid)", switch = "enabled", sections = { "innervate_cue" } },
    { id = "itemCounts", title = "Item counts in tooltips (Retail)", switch = "enabled", sections = { "item_counts" } },
    { id = "socketGemSuggestions", title = "Gems in bags (Retail)", switch = "enabled", sections = { "socket_gems" } },
    { id = "tooltipSpellCopy", title = "Copy spell ID (Retail)", switch = "enabled", sections = { "copy_spell_id" } },
    { id = "tooltipMPlusScore", title = "Mythic+ score in tooltips (Retail)", switch = "enabled", sections = { "mplus_score" } },
    { id = "tooltipClassColors", title = "Class-colored player names (Retail)", switch = "enabled",
        sections = { "class_colors" } },
    { id = "macroBuilder", title = "Macro builder (Retail)", switch = "enabled", sections = { "macro_builder" } },
    { id = "chatProfileLinks", title = "Character profile links (Retail)", switch = "enabled", sections = { "profile_links" } },
    { id = "mythicKeyShare", title = "Keystone command (Retail)", switch = "enabled",
        sections = { "keystone_command" } },
    { id = "trainerLearnAll", title = "Learn all at trainer (Retail)", switch = "enabled",
        sections = { "trainer_all" } },
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
    { id = "targetDistance", title = "Target spell-range estimate (Retail)", switch = "enabled", sections = { "target_distance" } },
    { id = "qol", title = "Sell junk", switch = "autoJunk", other = "repair", sections = { "junk" } },
    { id = "lootVendorRules", title = "Sell marked items (Retail)", switch = "enabled", sections = { "marked_sales" } },
    { id = "lootToastFilter", title = "Filtered loot notice (Retail)", switch = "enabled",
        sections = { "filtered_loot" } },
    { id = "skyriding", title = "Skyriding HUD (Retail)", switch = "enabled",
        sections = { "flight_hud", "flight_typography", "flight_colors" } },
    { id = "threatMeter", title = "Threat meter (Forever)", switch = "enabled", sections = { "threat_meter" } },
    { id = "flightTimer", title = "Flight route timer (Forever)", switch = "enabled", sections = { "flight_route" } },
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
table.sort(GROUPS, function(a, b) return Tr(a.title) < Tr(b.title) end)

-- One visible home per feature. The module/settings identities above remain
-- unchanged, including the two switches owned by each of `loot` and `qol`.
local CATEGORIES = {
    { id = "everydayAutomation", title = "Everyday & Automation", keys = {
        "collectionNewMarkers.enabled", "dailyComfort.enabled", "delveSolePower.enabled",
        "trainerLearnAll.enabled", "quests.enabled",
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
            "chatProfileLinks.enabled", "xpBar.enabled", "loadoutReminder.enabled", "combatStatsHUD.enabled",
            "targetDistance.enabled", "characterExtras.enabled",
        } },
        { id = "gear", title = "Gear", keys = {
            "characterUpgradeWindow.enabled", "socketGemSuggestions.enabled", "durabilityAlert.enabled",
            "professionAppearance.enabled",
        } },
    } },
    { id = "groupRaid", title = "Group & Raid", keys = {
        "battleRes.enabled", "groupBloodlust.enabled", "groupDeathAlert.enabled", "innervateCue.enabled",
        "groupRaidShortcuts.enabled", "trustedPartyInvites.enabled", "releaseProtection.enabled",
    } },
    { id = "groupFinderMythic", title = "Group Finder & Mythic+", tabs = {
        { id = "groupFinder", title = "Group Finder", keys = {
            "groupFinderExitReminder.enabled", "groupFinderDoubleClick.enabled",
        } },
        { id = "mythic", title = "Mythic+", keys = {
            "mythicKeyShare.enabled", "groupFinderApplicantSort.enabled", "mythicResetReminder.enabled",
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

local byKey, assigned = {}, {}
for _, group in ipairs(GROUPS) do byKey[group.id .. "." .. group.switch] = group end
local function LocalizedTitleLess(a, b)
    local left, right = Tr(a.title), Tr(b.title)
    return left == right and a.title < b.title or left < right
end
local function ResolveFeatures(keys, category, tab)
    local features = {}
    for _, key in ipairs(keys) do
        local group = assert(byKey[key], "Unknown Quality of Life feature: " .. key)
        assert(not assigned[group], "Duplicate Quality of Life feature: " .. key)
        assigned[group] = true
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
    assert(assigned[group], "Uncategorized Quality of Life feature: " .. group.title)
end
local function SortCategories()
    for _, category in ipairs(CATEGORIES) do
        table.sort(category.features, LocalizedTitleLess)
        if category.tabs then
            for _, tab in ipairs(category.tabs) do table.sort(tab.features, LocalizedTitleLess) end
            table.sort(category.tabs, LocalizedTitleLess)
        end
    end
    table.sort(CATEGORIES, LocalizedTitleLess)
end
SortCategories()
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
    local group = byKey[id .. ".enabled"]
    -- Multi-feature modules such as loot/merchant helpers open the overview.
    if not group then return true end
    local entry = P.M.cache and P.M.cache[PAGE]
    local resolve = entry and entry._msuf2ResolveMissingSection
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

local function FeatureKeywords(group)
    local words = { group.title, Tr(group.title), group.categoryTitle, Tr(group.categoryTitle) }
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
    local info = CreateFrame("Frame", nil, details)
    info:SetPoint("TOPRIGHT", details, "TOPRIGHT", -54, -10)
    info:SetSize(20, 20)
    info:EnableMouse(true)
    local glyph = P.T.Font(info, "GameFontHighlightSmall", "?", P.T.colors.muted, "caption")
    glyph:SetAllPoints(info)
    glyph:SetJustifyH("CENTER")
    glyph:SetJustifyV("MIDDLE")
    local helpText = {}
    for _, section in ipairs(sections) do helpText[#helpText + 1] = Tr(HELP[section.key]) end
    P.M.AddTooltip(info, Tr(group.title), table.concat(helpText, "\n\n"), { hook = true })
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
            entry.widget._msuf2PrepareExactSearchTarget = function() group.reveal(true) end
        end
    end
end

local function BuildFeatureDetails(ctx, panel, group, sectionId, width, sections, allRules, keywords)
    if #allRules == 0 and not EDIT_ELEMENTS[group.id]
        and group.id ~= "xpBar" and group.id ~= "innervateCue" and group.id ~= "loadoutReminder" then
        return nil, 0
    end
    local details = P.T.Panel(panel, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    P.T.ApplySurface(details, "card")
    details:SetSize(width, 100)
    details._msuf2Width, details._msuf2ContextColorHost = width, true
    local heading = P.Text(details, group.title, 16, -14, width - 104, P.T.colors.text)
    heading:SetWordWrap(false)
    details.title = heading
    AddFeatureHelp(details, group, sections)
    local y = -42
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
            Tr(group.title) .. " " .. Tr("Colors"), "button")
    end
    if #allRules > 0 then
        details._msufSuiteSectionReset = function()
            return P.ResetRules(group.id, allRules, nil, { group.switch })
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
        shade:SetColorTexture(0.10, 0.15, 0.22, 0.55)
    else
        shade:SetColorTexture(0.07, 0.10, 0.15, row._msufSuiteEven and 0.34 or 0.22)
    end
    stripe:SetShown(selected == true)
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
    local meta = P.Meta(PAGE, group.id, group.switch, "setting", sectionId)
    meta.label, meta.keywords = Tr(group.title), FeatureKeywords(group)
    P.M.BindBoolWidget(ctx, toggle,
        function() return GroupEnabled(group) end,
        function(value) SetGroupEnabled(group, value == true) end, meta)
    local searchMeta = P.Meta(PAGE, group.id, group.switch, "setting", sectionId)
    searchMeta.pageKey, searchMeta.kind = PAGE, "toggle"
    searchMeta.label, searchMeta.keywords = Tr(group.title), meta.keywords
    P.M.RegisterSearchWidget(toggle, searchMeta)
    toggle._msuf2PrepareExactSearchTarget = function() group.reveal(true) end
    local help = Tr(HELP[group.sections[1]])
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
    return row, toggle, settings, meta.keywords
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
        local detailHeight = selected and records[selected] and records[selected].detailHeight or 0
        for group, record in pairs(records) do
            if record.details then record.details:SetShown(group == selected) end
            if record.settings then record.settings:SetActive(group == selected) end
            local active = group == selected
            if record.row._msufSuiteSelected ~= active then
                record.row._msufSuiteSelected = active
                PaintFeatureRow(record.row)
            end
        end
        local height = 8 + #features * ROW_HEIGHT + (detailHeight > 0 and detailHeight + 12 or 0)
        panel:SetHeight(height)
        if not category.tabs or state.activeTab == tabId then
            P.FinishBody(builder, body, panelTop - height)
        end
    end
    state.updateHeight[tabId] = Layout
    local function Select(group, force)
        local record = records[group]
        if record and record.hasDetails and not record.details then
            local details, height, colors = BuildFeatureDetails(ctx, panel, group,
                record.sectionId, width, record.sections, record.allRules, record.keywords)
            record.details, record.detailHeight, record.colorShortcut = details, height, colors
            details:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -8 - #features * ROW_HEIGHT)
            details._msuf2CollapsibleEntry = entry
            P.Refresh()
        end
        selected = (not force and selected == group) and nil or group
        Layout()
    end
    for index, group in ipairs(features) do
        local oldSectionId = FeatureSectionId(group)
        local sections, allRules = FeatureRules(group)
        local hasDetails = #allRules > 0 or EDIT_ELEMENTS[group.id] ~= nil
            or group.id == "xpBar" or group.id == "innervateCue" or group.id == "loadoutReminder"
        local row, toggle, settings, keywords = BuildFeatureRow(ctx, panel, group, category,
            oldSectionId, width, index, hasDetails, Select)
        row._msuf2CollapsibleEntry = entry
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
            if hasDetails then Select(group, force ~= false) end
            return record.details or row
        end
        record.reveal = group.reveal
    end
    Layout()
end

-- A lazy host builds a category's feature rows when it first opens
-- (P.LazySection). Its header keeps the enabled count, and the page resolver
-- finds the category of each feature route (owners) to build it first.
local function CategoryShell(ctx, body, category, featureOrder, owners)
    for _, tab in ipairs(category.tabs or { category }) do
        for _, group in ipairs(tab.features) do
            local id = FeatureSectionId(group)
            owners[id], featureOrder[#featureOrder + 1] = body, id
        end
    end
    local entry = body._msuf2CollapsibleEntry
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
    local entry = body._msuf2CollapsibleEntry
    local width = math.max(240, (body._msuf2Width or builder.width or 720) - 32)
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
        if tabs._msuf2Title then tabs._msuf2Title:Hide() end
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
    SortCategories()
    local builder = P.W.PageBuilder(ctx)
    local rows, order, owners = {}, {}, {}
    ctx.qualityOfLifeFeatureRows, ctx.qualityOfLifeFeatureOrder = rows, order
    if ctx.entry then
        ctx.entry.qualityOfLifeFeatureRows = rows
        ctx.entry.qualityOfLifeFeatureOrder = order
        ctx.entry.sections = ctx.entry.sections or {}
        ctx.entry._msuf2ResolveMissingSection = function(sectionId)
            -- A lazy category builds its rows first (never in combat).
            if not rows[sectionId] then P.EnsureSectionContent(owners[sectionId]) end
            local record = rows[sectionId]
            return record and record.reveal(true) or nil
        end
    end
    for _, category in ipairs(CATEGORIES) do
        BuildCategory(ctx, builder, category, rows, order, owners)
    end
end

P.RegisterPage({ key = PAGE, label = "Quality of Life", title = "Quality of Life", build = Build, icon = { 7, 1 },
    nav = "general", navOrder = 1,
    aliases = { "qol", "qualityoflife", "quality_of_life", "actiontracker", "actions", "casts", "merchant",
        "itemlevel", "vault", "lootspec", "tooltipids", "loot", "quests", "combatlog", "logging", "comfort",
        "experience", "xpbar", "xp", "innervate", "whisper", "durability", "repairwarning", "battleres", "brez",
        "combatres", "skyriding", "vigor", "secondwind", "groupfinder", "keys", "keystone", "bloodlust" } })
