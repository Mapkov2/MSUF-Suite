# MSUF Suite Changelog

## 0.1.33 Alpha - 2026-11-22

Tooltip update for WoW Retail and WoW Forever. Requires Midnight Simple Unit Frames.

### Tooltip cards

- Custom item, spell and unit tooltip cards retain their design when combat restricts title or item data. The native title still appears in the custom header. The card skips details it cannot read.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_tooltips_preview","label":"Tooltip preview"} -->

### Enemy health bars

- When Blizzard exposes a health bar for a restricted enemy, the custom bar keeps its selected SharedMedia fill, background, size and position. Unavailable health text and power are omitted.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_skin_unit_tooltips","label":"Unitframe tooltips"} -->
- Visible tooltip rebuilds reuse the health bar, avoiding repeated fade, visibility and health-range updates without adding polling.

### Tooltip positioning

- On WoW Forever, world and MSUF unit-frame tooltips share the same position when the Suite anchor is enabled. This also applies in Blizzard tooltip mode.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_qualityOfLife_tooltipDetails_tooltip_details","label":"General tooltip anchor","settingKey":"msufsuite.tooltipDetails.anchor"} -->

### Where to find settings

These menu changes were introduced in 0.1.32.

- Open **Style → Tooltips** for presets, per-type styles, visibility, the shared anchor and the Unitframe tooltips section. Existing search shortcuts lead to the new page.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_skin_tooltips","label":"Tooltip styles"} -->
- Select elements in **Preview Layers** to position the title or anchor and to move or resize health and power bars. Combat examples show how the preview handles restricted data.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_tooltips_preview","label":"Tooltip preview"} -->
- Open **Interface → HUD → Adventure planner**. The previous standalone menu and its search results now lead there.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_planningTools_module","label":"Adventure planner"} -->
- Find Battle.net toast settings under **Style → Skinning → Blizzard windows → Notifications**. On WoW Forever, open **General → Macros → Auto Rank Up** to keep linked macros on the highest learned spell rank.

## 0.1.32 Alpha - 2026-11-22

### Menu and preview changes

- Moved tooltip settings out of Skinning and Miscellaneous into **Style → Tooltips**. Presets, the custom builder, visibility and Unitframe tooltips are grouped together. Existing search shortcuts follow the new page.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_skin_tooltips","label":"Tooltip styles"} -->
- Edit the title and anchor positions from Preview Layers. Move and resize health and power bars there and adjust the health text. Test quest, unit and restricted combat cases in the preview.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_tooltips_preview","label":"Tooltip preview"} -->
- Tooltips and loot rows can share a background and border or use separate styles.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_skin_tooltip_builder","label":"Tooltip builder"} -->
- Moved the Adventure planner from its standalone page to **Interface → HUD → Adventure planner** and redirected earlier search links.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_planningTools_module","label":"Adventure planner"} -->
- The Character Panel's Reputation tab is searchable. Custom tabs can show a Search box when their contents support it.
- **General → Macros** adds **Auto Rank Up** on WoW Forever. The builder can update a linked macro in place and asks before replacing a macro that was edited elsewhere.

### Tooltips

- Choose the Default, Detailed, Minimal or Dense preset or build a Custom layout for items, spells and units. Configure the health and power bars, including SharedMedia textures, and choose the health text format, font and position.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_skin_unit_tooltips","label":"Unitframe tooltips"} -->
- Suite styling also follows comparison tooltips and eligible quest or object tooltips. World and MSUF unit-frame tooltips share the selected style where the client allows it.
  <!-- msuf-menu-link: {"pageKey":"suite_tooltips","sectionId":"suite_skin_tooltips","label":"Tooltip styles"} -->

### HUD and gameplay

- The Flight Timer collects completed route timings and refreshes them through flight events.
- Reduced repeated work for floating combat text and adjusted gain displays on WoW Forever.

### Skinning

- Prepared quest rewards earlier in the native dialogue and refined gossip, quest, commerce and mail window styling.
- Updated window surfaces and caption controls shared by the available presets.

## 0.1.31 Alpha - 2026-11-21

### Retail and WoW Forever

- Use Space or a custom key to advance NPC dialogue. Number keys select dialogue options and quest rewards.
- Buy the missing quantity from your restock list with a confirmation that shows the amount and price.
- Bind a key to cast the next missing self-buff. Each press casts one buff outside combat.
- Look up recently sent mail for the current character, including recipients, attached items and gold.

### Retail

- See which players are missing raid buffs during a ready check.
- See an item's maximum upgrade level in the bag details.
- Optionally require Shift-click to roll or pass on a bonus roll outside combat.

### WoW Forever

- Mark food in your bags that your hunter pet can eat.
- Show when the Fishing key can reel in your bobber.

## 0.1.30 Alpha - 2026-11-21

Distributed through the Beta channel for WoW Retail and WoW Forever.

### Tooltips

- Added separate styles for item, spell, unit and loot tooltips, with an interactive preview and a shared layout builder.
- The spell style now covers buffs, debuffs, spellbook entries and action bar tooltips. The unit style also covers the MSUF unit-frame information panel.
- The shared tooltip anchor now covers items, spells, auras and MSUF unit frames.
- Fixed header and backdrop flicker during item tooltip updates. Loot rows can use the item card style while retaining native loot clicks, stack counts and quest markers.

### Quest and loot windows

- Improved the native quest offer and reward layout, including late quest data and the Forever reading fade.
- Preserved native loot row behavior when applying the Suite skin to the loot window.

## 0.1.29 Alpha - 2026-11-20

Distributed through the Beta channel for Retail and WoW Forever.

### Skinning

- Added Off, Subtle, and Extended window animations under Style → Skinning, with a live preview inside Suite settings. Reduced motion takes precedence.
- Registered supported Blizzard windows before their first opening, including the native macro window. The Blizzard shop uses a separate animated outline driven by Blizzard’s visibility event.
- Updated quest text styling and third-party addon skin integration.

### Bags and Cooldown Manager

- Refined Bags and Bank list views, category editing, and inventory layout and sizing.
- Added optional totem coverage indicators to supported Cooldown Manager entries.

### Navigation and other updates

- Added optional HandyNotes and Questie integration for Navigation HUD markers on supported clients.
- Updated the whisper messenger, quest tracking, buff reminders, loot roll layout, and merchant and auction display behavior.

## 0.1.28 Alpha - 2026-11-20

Distributed through the Beta channel for Retail and WoW Forever.

### Wayfarer and HUD

- Added the Wayfarer preset for WoW Forever, with a matching minimap frame, compass and HUD layout.
- Refined the optional map overlay and compass so heading and waypoint updates stay in sync as you move.
- Player aura layout now retains its position and skin when a visible icon's geometry temporarily becomes unreadable. Disabling the layout restores Blizzard's anchors and icon dimensions.

### WoW Forever windows and quests

- Revised item-data refresh for the quest reward value display to leave Blizzard's selection in control.
- The Spells to Learn panel can filter by learning source and omits talent spells.

### Suite settings and previews

- The Suite changelog is available from Suite settings, with shortcuts into supported settings.
- Updated editor previews, search and third-party addon skin integration.

### Highlights

- Added a Whisper Messenger with separate conversations for character and Battle.net whispers, an optional launcher, and access to saved character whispers.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Whisper messenger","sectionId":"suite_chat_chatMessenger_module","settingKey":"msufsuite.chatMessenger.enabled"} -->
- Bags and Bank have optional sortable item lists, a visual search builder, and read-only views of recorded inventories.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Show bag items as a sortable list","sectionId":"suite_bags_listView","settingKey":"msufsuite.bags.listView"} -->
- Action bars can combine combat, mount, target and mouseover conditions. Bars with native pages also accept custom macro paging rules.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Show this bar","sectionId":"suite_actionbars_bar_visibility","settingKey":"msufsuite.actionbars.bar1Visibility"} -->
- Manage Blizzard equipment sets from the Character Panel, show the active set in Overview, add sets to Custom Panels and place them on independent Action Bar 10.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Show equipment sets in Overview","sectionId":"suite_hud_characterPanel_appearance","settingKey":"msufsuite.characterPanel.showEquipmentSetsInOverview"} -->
- WoW Forever gains configurable floating damage text over enemies, with Suite font support and an option to hide Blizzard's damage numbers.
  <!-- msuf-menu-link: {"pageKey":"gameplay","label":"Floating combat text","sectionId":"suite_qualityOfLife_floatingCombatText_floating_combat_text","settingKey":"msufsuite.floatingCombatText.enabled","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_gameplay"} -->
- The bank follows Suite presets on both clients. WoW Forever also gains a Spells to Learn panel and refinements to the Glass look and window controls.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Blizzard windows"} -->

### Action Bars

- Combine visibility conditions with Any or All and use mouseover to reveal the bar.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Show this bar","sectionId":"suite_actionbars_bar_visibility","settingKey":"msufsuite.actionbars.bar1Visibility"} -->
- Bars 1 through 9 support validated macro paging where a native page is available. Vehicle, override and form paging retain priority. Reserved or invalid pages are rejected.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Custom paging (macro conditions)","sectionId":"suite_actionbars_bar_paging","settingKey":"msufsuite.actionbars.bar1Paging"} -->
- Optional Masque groups skin the buttons created by Suite, including bars 9 and 10 and Suite-created Bar 1 buttons.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Skin Suite-made buttons with Masque","sectionId":"suite_actionbars_appearance","settingKey":"msufsuite.actionbars.masque"} -->
- Refined visibility, paging, key handling and button refreshes during action changes and transitions.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","sectionId":"suite_actionbars_behavior","label":"Action bar behavior"} -->
- Independent Bar 10 accepts equipment-set actions picked up from the Character Panel.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Action bar 10","sectionId":"suite_actionbars_actionbars_module","controlId":"menu2.suite.actionbars.suite.actionbars.quick.bar10"} -->

### Bags and Bank

- Set Bags and Bank to list view independently. Sort by column, reorder columns and choose which item details to show.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Show bag items as a sortable list","sectionId":"suite_bags_listView","settingKey":"msufsuite.bags.listView"} -->
- Build searches with grouped conditions, apply them to the current inventory and save them for reuse. Open the builder from the inventory search controls.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","sectionId":"suite_bags_listView","label":"Bag list and inventory search"} -->
- Browse recorded bags and banks from the inventory window, including recorded Warband Bank contents on Retail. Recorded views show their snapshot date.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Inventory archive","sectionId":"suite_bags_inventoryArchive_module","settingKey":"msufsuite.inventoryArchive.enabled","controlId":"menu2.suite.bags.suite.inventory.archive.enabled"} -->
- Updated Bank window appearance in Suite Bags. On WoW Forever, the Glass look also extends through the Backpack sidebar and title and footer areas.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Bank background","sectionId":"suite_bags_bankWindow","settingKey":"msufsuite.bags.bankBackground"} -->
- The native Bank now uses the active Suite preset for item slots and money. Forever also styles the bag slots, side tabs and divider.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Blizzard windows"} -->
- Forever Bank minimize restores the original layout, the native close button stays clickable, and maximize includes space for the side tabs.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window position, size and minimize"} -->

### Character Panel

- Name, save, update, equip and delete Blizzard equipment sets. Set their icon, ignored slots and specialization in the set manager.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Show equipment sets in Overview","sectionId":"suite_hud_characterPanel_appearance","settingKey":"msufsuite.characterPanel.showEquipmentSetsInOverview"} -->
- Toggle the active equipment set in Overview or add Equipment Sets as a card or row in a Custom Panel.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->
- The Forever Modern Character Panel uses one translucent shell with matching close-button styling. Custom translucent looks keep the model and equipment interactions available.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->
- Fixed the Forever Attributes and report scroll direction, and moved their scrolling to Suite-owned controls.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->

### Chat

- Enable character whispers, Battle.net whispers or both. Configure the launcher, whether new whispers open the window, the number of tabs and the combat behavior.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Whisper messenger","sectionId":"suite_chat_chatMessenger_module","settingKey":"msufsuite.chatMessenger.enabled"} -->
- Open archived character whispers from the Messenger. Battle.net conversations are kept for the current session.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Show saved character whispers","sectionId":"suite_chat_chatMessenger_module","settingKey":"msufsuite.chatMessenger.showArchive"} -->
- Refined compact chat chrome, the toolbar, input transitions and message fading.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Minimal chat style","sectionId":"suite_chat_window","settingKey":"msufsuite.chat.minimalChrome"} -->
- Updated the Chat settings and preview layout, with shortcuts to the relevant controls from Preview Layers.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","sectionId":"suite_chat_window","label":"Chat window"} -->
- Retail guild chat privacy can cover the Guild & Communities chat and reveal it on demand.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Guild chat privacy cover (Retail)","sectionId":"suite_qualityOfLife_guildChatPrivacy_guild_privacy","settingKey":"msufsuite.guildChatPrivacy.enabled","client":"retail","fallbackSectionId":"suite_chat_chat_module"} -->

### Minimap

- Reorganized settings into Basics, Appearance, Layout, Buttons and Information displays.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","sectionId":"suite_minimap_minimap_module","label":"Minimap settings"} -->
- Updated the preset chooser and the way the preview displays map decorations and button placement.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","sectionId":"suite_minimap_style_presets","label":"Choose a look"} -->
- Show the tracking button only while the minimap is hovered. Tracking retains its native click behavior.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","label":"Show the tracking button only on mouseover","sectionId":"suite_minimap_elements","settingKey":"msufsuite.minimap.trackingMouseover","controlId":"menu2.suite.minimap.suite.minimap.tracking.mouseover"} -->

### Nameplates and Cast Bars

- Native nameplate style, native size and personal aura behavior are configurable alongside the per-unit-type pages.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Nameplate style","sectionId":"suite_nameplates_enemyStyle","settingKey":"msufsuite.nameplates.nativeStyle"} -->
- Choose the nameplate health fill and background under Bars, with a separate fill for your focus.
  <!-- msuf-menu-link: {"pageKey":"opt_bars","label":"Nameplate health fill texture","sectionId":"suite_nameplate_health_textures","settingKey":"msufsuite.nameplates.nativeHealthFillTexture","controlId":"menu2.opt.bars.suite.nameplates.native.health.fill.texture"} -->
- Choose the nameplate cast fill and background under Cast Bars. Cast colors have independent overrides for normal and uninterruptible casts.
  <!-- msuf-menu-link: {"pageKey":"opt_castbar","label":"Nameplate castbar background texture","sectionId":"suite_nameplate_cast_textures","settingKey":"msufsuite.nameplates.nativeCastBackgroundTexture","controlId":"menu2.opt.castbar.suite.nameplates.native.cast.background.texture"} -->
- Refined castbar textures, border and spark placement through layout changes, channels, empowers and the interrupt hold. Recycled plates refresh their castbar artwork.
  <!-- msuf-menu-link: {"pageKey":"opt_castbar","label":"Nameplate castbar fill texture","sectionId":"suite_nameplate_cast_textures","settingKey":"msufsuite.nameplates.nativeCastFillTexture","controlId":"menu2.opt.castbar.suite.nameplates.native.cast.fill.texture"} -->
- Choose how to highlight a cast targeting you. The Outline style draws a border, with the native highlight state supplying the trigger.
  <!-- msuf-menu-link: {"pageKey":"opt_bars","label":"Cast target highlight style","sectionId":"suite_nameplate_highlights","settingKey":"msufsuite.nameplates.castTargetHighlightStyle"} -->
- Choose Blizzard, Shared or Off separately for absorbs and heal absorbs.
  <!-- msuf-menu-link: {"pageKey":"opt_bars","label":"Absorb (positive)","sectionId":"suite_nameplate_absorbs","settingKey":"msufsuite.nameplates.nameplateAbsorbMode"} -->
- Per-type cast text settings control spell text, time, fonts and text outline. Castbar icon, width and height have their own controls.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Customize cast text","sectionId":"suite_nameplates_castbar","settingKey":"msufsuite.nameplates.enemyCastTextEnabled"} -->
- Enemy resource bars respect availability and refresh their geometry as plates change.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Show enemy power bar","sectionId":"suite_nameplates_enemyPower","settingKey":"msufsuite.nameplates.enemyPowerEnabled"} -->
- Separate native aura rows from optional custom rows. Updated filtering and duplicate handling, with native row sizing through Blizzard's controls.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Enable custom aura rows","sectionId":"suite_nameplates_auraWorkspace","settingKey":"msufsuite.nameplates.auraDisplayEnabled"} -->
- Preview controls stay on one line and wrap to a new row on narrow layouts. Updated layer selection and removed stray boxes from the element picker.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","sectionId":"suite_nameplates_enemyStyle","label":"Enemy nameplate style"} -->
- Reduced repeated styling on pooled nameplates. Text, layout and pending aura builds update from relevant events, with deferred work when native frames are still settling.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Enable","sectionId":"suite_nameplates_enemyBasics","settingKey":"msufsuite.nameplates.enemySkinEnabled"} -->

### Damage Meter and DataTexts

- Anchor a damage meter window above, below or beside another meter.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Anchor to","sectionId":"suite_damageMeter_windows","settingKey":"msufsuite.damageMeter.w1AnchorWindow"} -->
- Show totals, rates and percentages in separate meter columns or choose a more compact value format.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Value format","sectionId":"suite_damageMeter_text","settingKey":"msufsuite.damageMeter.numberFormat"} -->
- Group specialization lookup is opt-in. Enabling it sends inspect requests to fill missing specialization information.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Update group specializations (sends inspect requests)","sectionId":"suite_damageMeter_bars","settingKey":"msufsuite.damageMeter.inspectRemoteSpecs"} -->
- Refined meter windows, rows, breakdown and the preview settings.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Enable module","sectionId":"suite_damageMeter_damageMeter_module","settingKey":"msufsuite.damageMeter.enabled"} -->
- Use Add data on a DataText bar to add equipment sets, mail and time played, plus talent loadouts and keystones where supported. Equipment and talent sources can open their available choices.
  <!-- msuf-menu-link: {"pageKey":"suite_dataTexts","sectionId":"suite_dataTexts_presets","label":"DataTexts bar editor"} -->

### Gameplay, HUD and Quality of Life

- Forever floating damage text can show estimated personal hits or all hits on enemies. Set the font, critical-hit size, duration and vertical offset.
  <!-- msuf-menu-link: {"pageKey":"gameplay","label":"Font","sectionId":"suite_qualityOfLife_floatingCombatText_floating_combat_text","settingKey":"msufsuite.floatingCombatText.font","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_gameplay"} -->
- Compatible VoiceOver installations can add play, stop and replay controls to quests in the Suite Objective Tracker.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Objective Tracker","sectionId":"suite_hud_objectives_module","settingKey":"msufsuite.objectives.enabled"} -->
- Add a price comparison to item tooltips while browsing available results in the Forever Auction House.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","label":"Auction house price comparison","sectionId":"suite_qualityOfLife_auctionPriceTooltip_auction_price_tooltip","settingKey":"msufsuite.auctionPriceTooltip.enabled","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_lootMerchants"} -->
- Filtered loot notices can use personal loot messages on Forever and combine repeated pickups into one stack notice on both clients.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Filtered loot notice","sectionId":"suite_qualityOfLife_lootToastFilter_filtered_loot","settingKey":"msufsuite.lootToastFilter.enabled"} -->
- Navigation keeps manually selected destinations active and clears expired guide waypoints. RestedXP destinations refresh after a guide step changes.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","label":"Navigation & waypoints","sectionId":"suite_qualityOfLife_navigation_navigation_basics","settingKey":"msufsuite.navigation.enabled"} -->
- Reduced repeated XP estimate updates when the visible text and progress are unchanged.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Experience bar","sectionId":"suite_qualityOfLife_xpBar_xp_bar","settingKey":"msufsuite.xpBar.enabled"} -->
- Refined Blizzard player aura styling and preview interactions when changing layouts.
  <!-- msuf-menu-link: {"pageKey":"auras3_styling","label":"Show aura duration","sectionId":"auras3_styling_playerAuras_module","settingKey":"msufsuite.playerAuras.showDuration","controlId":"menu2.auras3.styling.suite.player.auras.show.duration"} -->
- Forever's parallel-window handling lets Blizzard manage spellbook and gamepad character-window dismissal.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","label":"Keep Blizzard windows open","sectionId":"suite_qualityOfLife_dailyComfort_daily_comfort","settingKey":"msufsuite.parallelWindows.enabled","controlId":"menu2.suite.quality.of.life.suite.parallel.windows.enabled"} -->

### Skinning and settings

- Forever's Spells to Learn panel lists unlearned spells and ranks by required level and shows the learning source where available.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Spells to Learn","settingKey":"msufsuite.skin.foreverSpellLearning","client":"forever","fallbackSectionId":"suite_skin_windows"} -->
- The Forever Professions overview can minimize and restore, its cards follow the Glass surface, and the crafting scale grip sits on the lower edge.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window position, size and minimize"} -->
- Forever World Map captions update after Blizzard's layout settles.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window position, size and minimize"} -->
- Forever's Compact quest log preserves Blizzard's objective preference and defers reflow during protected transitions.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_quests","label":"Quest list layout","settingKey":"msufsuite.skin.questLog.layout"} -->
- Deferred Forever mailbox skin and layout updates until the opening transition settles.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Blizzard windows"} -->
- Refined shared tooltip chrome, native menu rows, labels, caption titles and tutorial pointers.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_fonts","label":"Skinning fonts"} -->
- The interactive skin preview shows the chosen surface and window controls.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_material","label":"Glass and surfaces"} -->
- In Suite editors such as Minimap, Chat, Damage Meter, Character Panel, Loot Rolls, Skinning and Nameplates, clicking a disabled preview layer opens its settings and keeps the element disabled.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","sectionId":"suite_minimap_layout","label":"Size and position"} -->

## 0.1.27 Alpha - 2026-11-19

Distributed through the Beta channel for Retail and WoW Forever.

### Map overlay and equipment sets

- Enable Map overlay & compass under Quality of Life to open a click-through map with Shift+M or your own key binding. Adjust map zoom and opacity, show your active waypoint and move the optional compass independently.
- Add the compass to a DataTexts slot. Wide slots show a heading strip and narrow slots show your heading in degrees.
- The Character Panel Equipment tab opens the gear-set list directly. Equip or save a set from the list, and create a set with a name, an icon and its own ignored slots.

### Windows and DataTexts

- Improved minimize and restore for supported Blizzard windows, including the spellbook, bags and WoW Forever's Legacy window.
- Added the optional Show minimized windows taskbar under DataTexts to collect restore buttons in one place.
- Keep Blizzard windows open now recognizes more native panels and closes the oldest eligible panel when the configured limit is reached.

### Chat and Quests

- Fixed a Lua error when switching whisper tabs with the chat toolbar arrows.
- Fixed Spoken buttons and quest markers overlapping the quest log when their quest row is hidden.
- Quest details leave Blizzard's scroll reset in control while retaining visual scroll smoothing.

## 0.1.26 Alpha - 2026-11-18

Distributed through the Beta channel for Retail and WoW Forever.

### Fixes

- Fixed a Lua error when switching to a profile that turns off the Auction House price tooltip on WoW Forever.

## 0.1.25 Alpha - 2026-11-18

Distributed through the Beta channel for Retail and WoW Forever.

### World Map and Objective Tracker

- On Retail, enable World quests to browse quests in the current map area, see their rewards and time remaining, and filter by gold, reputation, currency or gear.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","sectionId":"suite_qualityOfLife_worldQuestTab_world_quest_tab","label":"World quests","client":"retail","fallbackSectionId":"suite_qualityOfLife_category_lootMerchants"} -->
- The Objective Tracker can hide completed objective lines and apply the focus color to the focused quest title.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_objectives_content","label":"Objective Tracker content"} -->
- Compact quest lists and folded groups now defer protected map updates until combat ends. The map restores the native objective display when the skin gives up control.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_quests","label":"Quest list layout","settingKey":"msufsuite.skin.questLog.layout"} -->

### Character Panel, Bags and HUD

- Select a faction in the Character Panel to show a movable Reputation Bar. It can sit beside or below the XP bar and follows the Character Panel's configurable standing colors.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->
- Retail Bags can show transmog collection status in item tooltips, with optional badges on item slots.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","sectionId":"suite_bags_transmog","label":"Transmog collection status","settingKey":"msufsuite.bags.showTransmogStatus","client":"retail","fallbackSectionId":"suite_bags_listView"} -->
- The level-up banner has a compact layout and separate switches for health, power, talent points and attributes.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_announcements_levelUp","label":"Level-up banner"} -->
- Chat can stay faded when loot, money, XP, reputation or skill messages arrive. The messages still appear in chat and history.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","sectionId":"suite_chat_window","label":"Chat window","settingKey":"msufsuite.chat.idleIgnoreProgress"} -->

### WoW Forever

- Spells to Learn distinguishes class quests, talents, items, portal trainers and spells learned automatically. It accounts for race-specific quests and rank prerequisites and shows trainer prices where available.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Spells to Learn","settingKey":"msufsuite.skin.foreverSpellLearning","client":"forever","fallbackSectionId":"suite_skin_windows"} -->
- Floating damage text uses separate lanes above each enemy nameplate to keep simultaneous hits readable.
  <!-- msuf-menu-link: {"pageKey":"gameplay","sectionId":"suite_qualityOfLife_floatingCombatText_floating_combat_text","label":"Floating combat text","settingKey":"msufsuite.floatingCombatText.enabled","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_gameplay"} -->
- The XP Optimizer can remind you when the Cozy Sleeping Bag bonus is active and still below three stacks.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_qualityOfLife_xpBar_xp_bar","label":"Experience bar"} -->

### Skinning and Quality of Life

- Choose a separate style and glyph size for the close button. Updated window controls and scrollbars keep their skin through window transitions.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window controls"} -->
- Added an optional skin for Numy's Addon Profiler and expanded the skinning API for participating addons to style their own captions, widgets and window controls.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_addon_skins","label":"Addon skins"} -->
- The UI error filter can hide action throttling and facing or position errors. WoW Forever also has a switch for spell and ability cooldown errors.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","sectionId":"suite_qualityOfLife_uiErrorFilter_ui_error_filter","label":"UI error messages"} -->

## 0.1.24 Alpha - 2026-11-17

Includes the accumulated Suite fixes and changes since 0.1.23 Alpha. Distributed through the Beta channel for Retail and WoW Forever.

### Changes

- Added optional skins for supported third-party addon windows, including Spoken, RestedXP, Enhance QoL and AceGUI/AceConfig. The feature starts disabled; each integration has its own switch. Improved addon menus, spellbook and spell-learning panels, mail scrolling, window controls and native button styling.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_addon_skins","label":"Addon skins"} -->
- Expanded Action Bars with special buttons, automatic class range text, additional border media and improvements to visibility rules, paging and key handling.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","sectionId":"suite_actionbars_behavior","label":"Action bar behavior"} -->
- Added Buff Reminder anchoring options and refined reminder layout, cursor placement, coverage and visual updates.
  <!-- msuf-menu-link: {"pageKey":"suite_buffReminders","sectionId":"suite_buffReminders_position","label":"Buff reminders"} -->
- Improved reagent inventory merging, item slot borders, bag and bank previews, inventory refreshes and physical sorting.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","sectionId":"suite_bags_listView","label":"Bags and inventory"} -->
- Improved chat position recovery, toolbar geometry, preview snapshots, chat bubbles and shared chat state.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","sectionId":"suite_chat_window","label":"Chat window"} -->
- Expanded trinket and action overlay support in the Cooldown Manager, with updated row settings, editor controls and preview behavior.
  <!-- msuf-menu-link: {"pageKey":"suite_cooldownManager","sectionId":"suite_cooldownManager_cooldownManager_module","label":"Cooldown Manager"} -->
- Expanded native nameplate options and health appearance, target resource display, cast settings and media controls. Refined friendly visibility, aura handling, cast outlines, mouseover behavior, roles, power bars and pooled plate updates.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","sectionId":"suite_nameplates_enemyStyle","label":"Enemy nameplate style"} -->
- Updated world map and quest controls, player aura handling and floating combat text behavior. Refined Forever spell-rank updates, merchant availability checks and related gameplay settings.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Window skins"} -->
- Updated profile import and variants, host integration, appearance controls, settings navigation and translations across all Suite language packs.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Suite appearance"} -->

## 0.1.23 Alpha - 2026-11-17

Changes since November 16, 2026 at around 12:00 CET.

### Highlights

- Added a Whisper Messenger with separate conversations for character and Battle.net whispers, an optional launcher, and access to saved character whispers.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Whisper messenger","sectionId":"suite_chat_chatMessenger_module","settingKey":"msufsuite.chatMessenger.enabled"} -->
- Bags and Bank have optional sortable item lists, a visual search builder, and read-only views of recorded inventories.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Show bag items as a sortable list","sectionId":"suite_bags_listView","settingKey":"msufsuite.bags.listView"} -->
- Action bars can combine combat, mount, target and mouseover conditions. Bars with native pages also accept custom macro paging rules.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Show this bar","sectionId":"suite_actionbars_bar_visibility","settingKey":"msufsuite.actionbars.bar1Visibility"} -->
- Manage Blizzard equipment sets from the Character Panel, show the active set in Overview, add sets to Custom Panels and place them on independent Action Bar 10.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Show equipment sets in Overview","sectionId":"suite_hud_characterPanel_appearance","settingKey":"msufsuite.characterPanel.showEquipmentSetsInOverview"} -->
- WoW Forever gains configurable floating damage text over enemies, with Suite font support and an option to hide Blizzard's damage numbers.
  <!-- msuf-menu-link: {"pageKey":"gameplay","label":"Floating combat text","sectionId":"suite_qualityOfLife_floatingCombatText_floating_combat_text","settingKey":"msufsuite.floatingCombatText.enabled","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_gameplay"} -->
- The bank follows Suite presets on both clients. WoW Forever also gains a Spells to Learn panel and refinements to the Glass look and window controls.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Blizzard windows"} -->

### Action Bars

- Combine visibility conditions with Any or All and use mouseover to reveal the bar.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Show this bar","sectionId":"suite_actionbars_bar_visibility","settingKey":"msufsuite.actionbars.bar1Visibility"} -->
- Bars 1 through 9 support validated macro paging where a native page is available. Vehicle, override and form paging retain priority. Reserved or invalid pages are rejected.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Custom paging (macro conditions)","sectionId":"suite_actionbars_bar_paging","settingKey":"msufsuite.actionbars.bar1Paging"} -->
- Optional Masque groups skin the buttons created by Suite, including bars 9 and 10 and Suite-created Bar 1 buttons.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Skin Suite-made buttons with Masque","sectionId":"suite_actionbars_appearance","settingKey":"msufsuite.actionbars.masque"} -->
- Refined visibility, paging, key handling and button refreshes during action changes and transitions.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","sectionId":"suite_actionbars_behavior","label":"Action bar behavior"} -->
- Independent Bar 10 accepts equipment-set actions picked up from the Character Panel.
  <!-- msuf-menu-link: {"pageKey":"suite_actionbars","label":"Action bar 10","sectionId":"suite_actionbars_actionbars_module","controlId":"menu2.suite.actionbars.suite.actionbars.quick.bar10"} -->

### Bags and Bank

- Set Bags and Bank to list view independently. Sort by column, reorder columns and choose which item details to show.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Show bag items as a sortable list","sectionId":"suite_bags_listView","settingKey":"msufsuite.bags.listView"} -->
- Build searches with grouped conditions, apply them to the current inventory and save them for reuse. Open the builder from the inventory search controls.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","sectionId":"suite_bags_listView","label":"Bag list and inventory search"} -->
- Browse recorded bags and banks from the inventory window, including recorded Warband Bank contents on Retail. Recorded views show their snapshot date.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Inventory archive","sectionId":"suite_bags_inventoryArchive_module","settingKey":"msufsuite.inventoryArchive.enabled","controlId":"menu2.suite.bags.suite.inventory.archive.enabled"} -->
- Updated Bank window appearance in Suite Bags. On WoW Forever, the Glass look also extends through the Backpack sidebar and title and footer areas.
  <!-- msuf-menu-link: {"pageKey":"suite_bags","label":"Bank background","sectionId":"suite_bags_bankWindow","settingKey":"msufsuite.bags.bankBackground"} -->
- The native Bank now uses the active Suite preset for item slots and money. Forever also styles the bag slots, side tabs and divider.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Blizzard windows"} -->
- Forever Bank minimize restores the original layout, the native close button stays clickable, and maximize includes space for the side tabs.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window position, size and minimize"} -->

### Character Panel

- Name, save, update, equip and delete Blizzard equipment sets. Set their icon, ignored slots and specialization in the set manager.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Show equipment sets in Overview","sectionId":"suite_hud_characterPanel_appearance","settingKey":"msufsuite.characterPanel.showEquipmentSetsInOverview"} -->
- Toggle the active equipment set in Overview or add Equipment Sets as a card or row in a Custom Panel.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->
- The Forever Modern Character Panel uses one translucent shell with matching close-button styling. Custom translucent looks keep the model and equipment interactions available.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->
- Fixed the Forever Attributes and report scroll direction, and moved their scrolling to Suite-owned controls.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","sectionId":"suite_hud_characterPanel_appearance","label":"Character Panel appearance"} -->

### Chat

- Enable character whispers, Battle.net whispers or both. Configure the launcher, whether new whispers open the window, the number of tabs and the combat behavior.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Whisper messenger","sectionId":"suite_chat_chatMessenger_module","settingKey":"msufsuite.chatMessenger.enabled"} -->
- Open archived character whispers from the Messenger. Battle.net conversations are kept for the current session.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Show saved character whispers","sectionId":"suite_chat_chatMessenger_module","settingKey":"msufsuite.chatMessenger.showArchive"} -->
- Refined compact chat chrome, the toolbar, input transitions and message fading.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Minimal chat style","sectionId":"suite_chat_window","settingKey":"msufsuite.chat.minimalChrome"} -->
- Updated the Chat settings and preview layout, with shortcuts to the relevant controls from Preview Layers.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","sectionId":"suite_chat_window","label":"Chat window"} -->
- Retail guild chat privacy can cover the Guild & Communities chat and reveal it on demand.
  <!-- msuf-menu-link: {"pageKey":"suite_chat","label":"Guild chat privacy cover (Retail)","sectionId":"suite_qualityOfLife_guildChatPrivacy_guild_privacy","settingKey":"msufsuite.guildChatPrivacy.enabled","client":"retail","fallbackSectionId":"suite_chat_chat_module"} -->

### Minimap

- Reorganized settings into Basics, Appearance, Layout, Buttons and Information displays.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","sectionId":"suite_minimap_minimap_module","label":"Minimap settings"} -->
- Updated the preset chooser and the way the preview displays map decorations and button placement.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","sectionId":"suite_minimap_style_presets","label":"Choose a look"} -->
- Show the tracking button only while the minimap is hovered. Tracking retains its native click behavior.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","label":"Show the tracking button only on mouseover","sectionId":"suite_minimap_elements","settingKey":"msufsuite.minimap.trackingMouseover","controlId":"menu2.suite.minimap.suite.minimap.tracking.mouseover"} -->

### Nameplates and Cast Bars

- Native nameplate style, native size and personal aura behavior are configurable alongside the per-unit-type pages.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Nameplate style","sectionId":"suite_nameplates_enemyStyle","settingKey":"msufsuite.nameplates.nativeStyle"} -->
- Choose the nameplate health fill and background under Bars, with a separate fill for your focus.
  <!-- msuf-menu-link: {"pageKey":"opt_bars","label":"Nameplate health fill texture","sectionId":"suite_nameplate_health_textures","settingKey":"msufsuite.nameplates.nativeHealthFillTexture","controlId":"menu2.opt.bars.suite.nameplates.native.health.fill.texture"} -->
- Choose the nameplate cast fill and background under Cast Bars. Cast colors have independent overrides for normal and uninterruptible casts.
  <!-- msuf-menu-link: {"pageKey":"opt_castbar","label":"Nameplate castbar background texture","sectionId":"suite_nameplate_cast_textures","settingKey":"msufsuite.nameplates.nativeCastBackgroundTexture","controlId":"menu2.opt.castbar.suite.nameplates.native.cast.background.texture"} -->
- Refined castbar textures, border and spark placement through layout changes, channels, empowers and the interrupt hold. Recycled plates refresh their castbar artwork.
  <!-- msuf-menu-link: {"pageKey":"opt_castbar","label":"Nameplate castbar fill texture","sectionId":"suite_nameplate_cast_textures","settingKey":"msufsuite.nameplates.nativeCastFillTexture","controlId":"menu2.opt.castbar.suite.nameplates.native.cast.fill.texture"} -->
- Choose how to highlight a cast targeting you. The Outline style draws a border, with the native highlight state supplying the trigger.
  <!-- msuf-menu-link: {"pageKey":"opt_bars","label":"Cast target highlight style","sectionId":"suite_nameplate_highlights","settingKey":"msufsuite.nameplates.castTargetHighlightStyle"} -->
- Choose Blizzard, Shared or Off separately for absorbs and heal absorbs.
  <!-- msuf-menu-link: {"pageKey":"opt_bars","label":"Absorb (positive)","sectionId":"suite_nameplate_absorbs","settingKey":"msufsuite.nameplates.nameplateAbsorbMode"} -->
- Per-type cast text settings control spell text, time, fonts and text outline. Castbar icon, width and height have their own controls.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Customize cast text","sectionId":"suite_nameplates_castbar","settingKey":"msufsuite.nameplates.enemyCastTextEnabled"} -->
- Enemy resource bars respect availability and refresh their geometry as plates change.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Show enemy power bar","sectionId":"suite_nameplates_enemyPower","settingKey":"msufsuite.nameplates.enemyPowerEnabled"} -->
- Separate native aura rows from optional custom rows. Updated filtering and duplicate handling, with native row sizing through Blizzard's controls.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Enable custom aura rows","sectionId":"suite_nameplates_auraWorkspace","settingKey":"msufsuite.nameplates.auraDisplayEnabled"} -->
- Preview controls stay on one line and wrap to a new row on narrow layouts. Updated layer selection and removed stray boxes from the element picker.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","sectionId":"suite_nameplates_enemyStyle","label":"Enemy nameplate style"} -->
- Reduced repeated styling on pooled nameplates. Text, layout and pending aura builds update from relevant events, with deferred work when native frames are still settling.
  <!-- msuf-menu-link: {"pageKey":"suite_nameplates","label":"Enable","sectionId":"suite_nameplates_enemyBasics","settingKey":"msufsuite.nameplates.enemySkinEnabled"} -->

### Damage Meter and DataTexts

- Anchor a damage meter window above, below or beside another meter.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Anchor to","sectionId":"suite_damageMeter_windows","settingKey":"msufsuite.damageMeter.w1AnchorWindow"} -->
- Show totals, rates and percentages in separate meter columns or choose a more compact value format.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Value format","sectionId":"suite_damageMeter_text","settingKey":"msufsuite.damageMeter.numberFormat"} -->
- Group specialization lookup is opt-in. Enabling it sends inspect requests to fill missing specialization information.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Update group specializations (sends inspect requests)","sectionId":"suite_damageMeter_bars","settingKey":"msufsuite.damageMeter.inspectRemoteSpecs"} -->
- Refined meter windows, rows, breakdown and the preview settings.
  <!-- msuf-menu-link: {"pageKey":"suite_damageMeter","label":"Enable module","sectionId":"suite_damageMeter_damageMeter_module","settingKey":"msufsuite.damageMeter.enabled"} -->
- Use Add data on a DataText bar to add equipment sets, mail and time played, plus talent loadouts and keystones where supported. Equipment and talent sources can open their available choices.
  <!-- msuf-menu-link: {"pageKey":"suite_dataTexts","sectionId":"suite_dataTexts_presets","label":"DataTexts bar editor"} -->

### Gameplay, HUD and Quality of Life

- Forever floating damage text can show estimated personal hits or all hits on enemies. Set the font, critical-hit size, duration and vertical offset.
  <!-- msuf-menu-link: {"pageKey":"gameplay","label":"Font","sectionId":"suite_qualityOfLife_floatingCombatText_floating_combat_text","settingKey":"msufsuite.floatingCombatText.font","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_gameplay"} -->
- Compatible VoiceOver installations can add play, stop and replay controls to quests in the Suite Objective Tracker.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Objective Tracker","sectionId":"suite_hud_objectives_module","settingKey":"msufsuite.objectives.enabled"} -->
- Add a price comparison to item tooltips while browsing available results in the Forever Auction House.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","label":"Auction house price comparison","sectionId":"suite_qualityOfLife_auctionPriceTooltip_auction_price_tooltip","settingKey":"msufsuite.auctionPriceTooltip.enabled","client":"forever","fallbackSectionId":"suite_qualityOfLife_category_lootMerchants"} -->
- Filtered loot notices can use personal loot messages on Forever and combine repeated pickups into one stack notice on both clients.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Filtered loot notice","sectionId":"suite_qualityOfLife_lootToastFilter_filtered_loot","settingKey":"msufsuite.lootToastFilter.enabled"} -->
- Navigation keeps manually selected destinations active and clears expired guide waypoints. RestedXP destinations refresh after a guide step changes.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","label":"Navigation & waypoints","sectionId":"suite_qualityOfLife_navigation_navigation_basics","settingKey":"msufsuite.navigation.enabled"} -->
- Reduced repeated XP estimate updates when the visible text and progress are unchanged.
  <!-- msuf-menu-link: {"pageKey":"suite_hud","label":"Experience bar","sectionId":"suite_qualityOfLife_xpBar_xp_bar","settingKey":"msufsuite.xpBar.enabled"} -->
- Refined Blizzard player aura styling and preview interactions when changing layouts.
  <!-- msuf-menu-link: {"pageKey":"auras3_styling","label":"Show aura duration","sectionId":"auras3_styling_playerAuras_module","settingKey":"msufsuite.playerAuras.showDuration","controlId":"menu2.auras3.styling.suite.player.auras.show.duration"} -->
- Forever's parallel-window handling lets Blizzard manage spellbook and gamepad character-window dismissal.
  <!-- msuf-menu-link: {"pageKey":"suite_qualityOfLife","label":"Keep Blizzard windows open","sectionId":"suite_qualityOfLife_dailyComfort_daily_comfort","settingKey":"msufsuite.parallelWindows.enabled","controlId":"menu2.suite.quality.of.life.suite.parallel.windows.enabled"} -->

### Skinning and settings

- Forever's Spells to Learn panel lists unlearned spells and ranks by required level and shows the learning source where available.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Spells to Learn","settingKey":"msufsuite.skin.foreverSpellLearning","client":"forever","fallbackSectionId":"suite_skin_windows"} -->
- The Forever Professions overview can minimize and restore, its cards follow the Glass surface, and the crafting scale grip sits on the lower edge.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window position, size and minimize"} -->
- Forever World Map captions update after Blizzard's layout settles.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_window_controls","label":"Window position, size and minimize"} -->
- Forever's Compact quest log preserves Blizzard's objective preference and defers reflow during protected transitions.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_quests","label":"Quest list layout","settingKey":"msufsuite.skin.questLog.layout"} -->
- Deferred Forever mailbox skin and layout updates until the opening transition settles.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_windows","label":"Blizzard windows"} -->
- Refined shared tooltip chrome, native menu rows, labels, caption titles and tutorial pointers.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_fonts","label":"Skinning fonts"} -->
- The interactive skin preview shows the chosen surface and window controls.
  <!-- msuf-menu-link: {"pageKey":"suite_skin","sectionId":"suite_skin_material","label":"Glass and surfaces"} -->
- In Suite editors such as Minimap, Chat, Damage Meter, Character Panel, Loot Rolls, Skinning and Nameplates, clicking a disabled preview layer opens its settings and keeps the element disabled.
  <!-- msuf-menu-link: {"pageKey":"suite_minimap","sectionId":"suite_minimap_layout","label":"Size and position"} -->

## 0.1.22 Alpha - 2026-11-15

### Nameplates

- Refined the Jundies and Mapko presets, health textures and Frame Outline controls. Choosing Off now also hides native target and focus outlines on skinned plates.
- Improved preview layers, selection, markers and settings shortcuts. The preview toolbar and layer list adapt to the available width.
- Castbar fills and backgrounds use their selected textures through casts, channels and interrupts. **Nameplate castbar colors are work in progress.** Inheriting Unit Frame colors and setting per-state overrides are still being tested, especially on WoW Forever.
- Reduced repeated work for name updates and preserved the handling of restricted names and aura data.

### WoW Forever skinning and windows

- Expanded the interactive Style preview with live scroll, dropdown, focus and action samples. Title buttons stay flat and honor the selected glyph style. Character Panel appearance settings are under HUD.
- The Character Panel offers List, Classic and Modern views. The spellbook toggles all spell ranks in one click and keeps the native book controls.
- Moved map filters beside the window controls and corrected their click area. Updated Guild & Communities styling and the developer panel's reload and diagnostics controls.
- Improved chat item links, quest offer reward display, and the Group Finder's category artwork and activity list controls. Adjusted protected window and mailbox interactions.

### Bags, action bars and Edit Mode

- Forever One Bag shows regular slots in physical bag order. Cleanup packs and sorts eligible slots across regular bags while respecting exclusions and keeping reagent, specialty and keyring slots separate.
- Reduced redundant Action Bar updates, repeated Data Text layout and unnecessary tooltip event work during normal play.
- Suite movers show screen coordinates at the edges with the updated MSUF Edit Mode, including Action Bars and the Minimap. Player debuffs retain their offset from the buff row.

### Other updates

- Refined character stats, navigation and the options previews. Navigation refreshes quest destinations across subzones and adjusts its update rate while walking.

## 0.1.21 Alpha - 2026-11-14

### Nameplates

- Rebuilt the menu with separate Enemy, Neutral, Friendly and Friendly NPC tabs and Unitframes-style accordions. Presets are in Basics, colors in their section menus, shared typography under Fonts, and spell range in its own section. Basics now owns each type's Enable switch.
- One preview handles all placement. Select or drag an element to adjust X/Y and available size. The element menu can show disabled elements for editing. The Castbar, Text, Resource Bar, Aura and Status Icons accordions leave position editing to the preview.
- Aggro, Target, Focus and Mouseover borders have their own preview layers. Right-click to go to Bars. Aggro inherits the host's Shared setting where supported, with an optional Nameplate override.
- Health and castbar foreground and background textures live under Bars and Cast Bars. Health has a separate focus texture and a choice of native or custom outline.
- Buffs, Debuffs and Control Effects have separate controls for their native rows. Three Custom rows and Dots on Target have their own lists, layout, ordering and style. Duplicate filtering keeps protected auras visible when the client restricts access to them.
- Text now has separate Name, HP Text and Power Text controls. Resource Bar supports mana and other available resources, size, fill, border and detached placement. Castbar options include separate icon, spell, time, target and interrupt settings.
- Status Icons use one indicator selector for supported markers and named text sources, including raid markers, level, quest progress and resource text. Preview current and Show all use the main preview.
- Added per-type visibility and opacity controls, out-of-combat opacity, click-area settings, and range spell selection by spellbook or spell ID.
- Fixed stale Enable and Show switches when reopening or switching tabs. Improved native aura filtering, resource rendering, bar textures, and preview positioning and navigation.

### Bags, character and chat

- On Forever, the backpack key also opens the reagent window in the Suite bag views when a reagent bag is equipped. Reagent and specialty slots stay out of the regular free-slot count, and detached bag positions clamp to the screen.
- Upgrade markers account for dual wield eligibility. Character and Inspect item levels use two decimals with the localized separator.
- Chat keeps messages and controls available while typing. Refined fading, compact chrome, the toolbar and spam filtering.

### Action bars, macros and cooldowns

- Forever action bar transfers use the full character name, including surnames.
- Macro Library entries can manage keyboard and supported mouse bindings, with conflict checks and cleanup when deleting a macro. Consumable macros respect the preferred item order and availability.
- Cooldowns refresh after loadout and spell override changes. Recharge overlays and countdowns keep their own style, layer and timer when the main cooldown ends.
- Updated augment rune detection for buff reminders.

### Combat, quests and interface

- Live damage meter rows can update party specialization icons. Threat displays handle tank changes before the reported percentages catch up.
- Mythic+ split records wait for confirmed completion times. Updated gathering names and tooltips, and refined the interact glow.
- Loot rolls reconcile pending choices with Blizzard and show the choice after submission. Quest helpers handle the native quest greeting flow.
- Blizzard player aura skins and layout recover more reliably after protected changes. Adjusted secure window controls and deferred World Map quest row updates during map opening.
- Added an optional developer diagnostics page and updated locale strings for the revised menus.

## 0.1.20 Alpha - 2026-11-12

[Compare with 0.1.19](https://github.com/Mapkov2/MSUF-Suite/compare/v0.1.19-alpha...v0.1.20-alpha) · [CurseForge](https://www.curseforge.com/wow/addons/msuf-suite) · [Wago](https://addons.wago.io/addons/msuf-suite)

### Bags

- New **Delete cheapest item** (Quality of Life): a button on the open bag deletes the stack a vendor pays least for, to make room when your bags are full. Point at it to see the stack marked in the bag; right-click to pick one of the ten cheapest or to never offer an item again. Only Poor items by default, at most Uncommon. Quest items, refundable items, equipment set items and Never sell items are never offered, and anything above Poor always asks first.
- Bag windows get the Windows caption of the skinned Blizzard windows: minimize, maximize and close. Minimize leaves a restore tab, and maximize toggles the side panel's full screen height.
- In combat with every bag window closed, the Bags run no code at all and catch up when a window opens or the fight ends.
- On WoW Forever, the keyring keeps its keys and tooltips visible in combat but takes no clicks or drags there, so Blizzard no longer blocks the action. New-item highlights clear when the bag closes.

### Window skin

- Skinned Blizzard windows get a Windows-style caption with minimize, maximize and close, with a choice of glyph styles. Fixed-size windows such as Trade show only close and minimize, and only windows you opened yourself leave a restore tab.
- Minimize and the restore tab click Blizzard's own buttons through secure code. This fixes the blocked action on WoW Forever when the world map opened after a window was minimized or restored.
- Turn off the Micro Bar frame to hide the whole frame around the micro menu.
- On WoW Forever, the spellbook brings back Show All Spell Ranks and gets a portrait ring that matches the skin.

### Cooldown manager

- On WoW Forever, entries follow the highest rank you have learned and keep their settings when you learn a new rank. Spell ranks, Defensives defaults, spell groups, racials, potions and bandages come from Enhance QoL's Forever data. Many thanks to R41z0r for building it and allowing the Suite to use it.
- Add totem slots: one entry for every slot or one per slot, each showing whatever totem, statue or summon is in it. Shamans see the slots named by element.
- The picker lists equipment slots with a use effect and stays open for several picks.

### Announcements

- The banner frame has its own section: turn it on or off and choose its shape (full box, top and bottom lines, corner brackets), thickness, opacity and color. Artwork opacity is adjustable too.
- Move the headline and subtitle by dragging them in the preview, or click one and use the arrow keys.

### Quality of life

- New **Battle.net toast** module: move Blizzard's Battle.net toast in MSUF Edit Mode and give it a Suite style, font, scale and layer. Its settings are on the Skinning page.
- The loot roll preview is now an element editor: click any part of a sample row to open its setting, show or hide parts in Preview Layers, and set each element's offset and size.
- **Player aura layout:** move Blizzard's own buff and debuff icons in MSUF Edit Mode. Each row has its own mover (Player buffs, Player debuffs) with icon size, zoom, icons per row and spacing in its popup. A drag stops at the screen edge, so the icons stay where you drop them.
- New **Icon zoom** setting for Blizzard's buff and debuff icons. The debuff row also gets a horizontal offset and can sit above the buffs.

### Reminders

- On WoW Forever, paladins get an aura reminder that casts the highest known rank of the aura used last.
- On WoW Forever, the Lightning Shield and weapon imbue reminders know every rank, and Earth Shield counts as a shield.

### Profiles and action bars

- Profile exports and imports can carry your action bar key bindings (bars 1 to 10) while the Suite action bars are on. Turn this off under Action bars > Behavior. Restore previous setup under Account transfer undoes an import's keys.
- An Account transfer import now replaces the target's action bar keys instead of skipping conflicting ones.

## 0.1.19 Alpha - 2026-11-12

[Compare with 0.1.18](https://github.com/Mapkov2/MSUF-Suite/compare/v0.1.18-alpha...v0.1.19-alpha) · [CurseForge](https://www.curseforge.com/wow/addons/msuf-suite) · [Wago](https://addons.wago.io/addons/msuf-suite)

### Navigation

- Show the followed map pin and your focused quest on the flight map, beneath the flight points so they stay clickable. Turn this off under Destinations & maps.
- The direction arrow keeps its place more steadily and follows UI scale and window size changes.
- Choose how an off-screen destination is shown: arrow and symbol, arrow only, or symbol only. The light beam's animation can be turned off.
- Inside dungeons, raids and other instances, navigation pauses during combat and resumes afterwards.

### Action bars, reminders and objectives

- Keep bar 1 on its page in Moonkin Form while cat and bear forms still change pages.
- On WoW Forever, druids get a Thorns reminder that casts the highest known rank on yourself outside combat.
- Tracked achievements in the Objective Tracker show their progress the way Blizzard's tracker words it, and stay listed when only another character has earned them.

### Cooldowns and nameplates

- On WoW Forever, Healthstone and health potion entries follow the strongest rank in your bags, count every rank, and use that item's icon and tooltip.
- Nameplate auras create their buttons gradually and use a single dispel ring, which reduces stutter when many plates appear in combat.
- Cooldown tints, empty Healthstone entries and nameplates with hidden names do less work in combat.

### Skins

- On WoW Forever, the Group Finder, Professions and talent windows get fitted side tabs, flat role icons, skinned profession rank bars and portrait rings that match the skin.

### Fixes

- A reload during combat now starts the Suite before combat lockdown on Retail as well as WoW Forever.
- Clicking a quest or the header in the Objective Tracker opens the quest log through Blizzard's own button, avoiding blocked quest-pin updates in combat.
- Whisper tab overflow arrows and the header toolbar keep their space when the chat window is resized.
- Action bars skip unchanged slot and drag updates, reducing idle work from macros.
- Cooldown stack counts keep their font on newly created icons.
- The raid pull timer and the flight timer's elapsed time no longer need a script running every second.
- The equipment comparison no longer shows a box instead of its arrow.

## 0.1.18 Alpha - 2026-11-10

[Compare with 0.1.17](https://github.com/Mapkov2/MSUF-Suite/compare/v0.1.17-alpha...v0.1.18-alpha) · [CurseForge](https://www.curseforge.com/wow/addons/msuf-suite) · [Wago](https://addons.wago.io/addons/msuf-suite)

### Nameplates

- The native Blizzard nameplate skin gains separate friendly and enemy aura layouts. Configure Buffs, Debuffs, three custom spell containers, and a dedicated Dots on Target display. Choose which spells to show and set each container's icon size, placement, spacing and growth direction. [Aura settings](https://github.com/Mapkov2/MSUF-Suite/blob/v0.1.18-alpha/MSUF_Suite_Options/Pages/NameplatesAdvancedAuras.lua)
- Set nameplate size, opacity and visibility by unit type and location. Add player identity icons, extra text, and separate raid-marker and cast-icon anchors. Preview multiple units while editing.
- Customize interrupted-cast feedback, casting-name visibility, focus and casting scale, execute pulses and threat warnings. Set a spell range check, click area and friendly click-through, or anchor Blizzard class resources to the target plate. [Nameplate controls](https://github.com/Mapkov2/MSUF-Suite/blob/v0.1.18-alpha/MSUF_Suite/Core/Catalog/NameplateExtensions.lua)
- Save and share nameplate profiles. Compatible MSUF hosts can also carry supported nameplate settings across imports and restore points.

### Navigation and quality of life

- The Navigation workspace brings together destinations, waypoints, saved routes, map markers and optional guide sources. Improve waypoint selection, Group Finder locations and travel guidance.
- On WoW Forever, start **Turn-in route** from the XP Optimizer. It guides you to quests ready to hand in, starting with the nearest available destination, and advances after each turn-in. Stop the route at any time. [Quest routing](https://github.com/Mapkov2/MSUF-Suite/blob/v0.1.18-alpha/MSUF_Suite_QualityOfLife/NavigationRoutes.lua)
- Add loot roll tools, a group buff overview and Mythic Keystone preparation checks.

### Character panel, bags and profiles

- Expand character statistics, reputation views, configurable tabs and keyboard bindings. Improve native character pages and combat behavior.
- Improve organized bags, item feedback, inventory views and keyring handling.
- Improve profile import and preservation, DataText appearance and settings previews.

### Fixes and interface

- Improve cooldown previews, action bar behavior, objective tracking, skins, localization and settings navigation.

## 0.1.17 Alpha - 2026-11-09

### Action Bars

- Add Account transfer for spell assignments and keyboard bindings. Capture setups manually or automatically, export them, and review an import before assigning it to another character or loadout. Apply spells and keys separately, see skipped changes, and restore the previous setup.
- Give Bar 10 its own assignments per character and specialization. Blizzard's page 10 remains available for forms. Enabled fixed bars reserve their native pages so the main bar avoids duplicate actions.

### Damage Meter

- Add Compare pulls to the Damage Meter fight menu. Compare DPS or HPS for two completed fights, then select a player to see per-spell rates and differences.

### Bags, bank and inventory tools

- Add Sort bag slots to physically rearrange items, with per-slot exclusions. Right-click the Bags title to open Blizzard's bag options.
- Add optional dimming for inactive quest items. Suppress the empty 0/0 item upgrade rank.
- Show Forever's native Keyring in organized bags. Add organized bank views and search to Forever's keyboard interface, with the native bank available in Gamepad UI.
- Deposit or withdraw matching stacks from the Filters menu. Review the batch for the current category or search and selected bank before moving items.
- Record dated mail attachments, active auctions, and accessible guild bank tabs in Inventory Archive. Browse records by character and location, and see where Crafting Shopping List materials were last recorded.

### Chat

- Search inside Copy Chat, move between matches, and copy the full tab. Click an MSUF timestamp to copy its message. Optionally show item icons beside links and class icons for known players.
- Choose which chat categories keep saved history. Optionally archive whispers per character, search past conversations, and copy a conversation.
- Add opt-in public chat filters for matching phrases, repeat messages, and selected channels.
- Add whisper-tab overflow arrows and separate message spacing controls.
- Give keyword alerts per-phrase channel filters, sound selection and previews, and a session history of the latest 100 matches.

### Adventure Planner

- Add Loot Goals to Adventure Planner. Drag an item or paste its link, track equipped status, and import visible Adventure Guide loot on Retail with lockout details where available.
- Compare saved and current talents, loot specialization, and equipment in Retail Instance Loadouts. Open the relevant Blizzard panels to make corrections.

### Quality of life

- Add the Quick Actions palette via /msufactions or a keybind. Open Suite tools and inventory search from the keyboard or gamepad, with favorites and recent actions per character.
- Add optional ready-check reminders for missing preparation, low durability, and loadout mismatches. Ally buff reminders can be limited to group members in range.
- Animate expansion and collapse in the Objective Tracker, with an option to turn the motion off and support for reduced-motion settings.
- Add an optional XP Optimizer to the XP bar with a turn-in XP strip, AFK-adjusted XP per hour, bonus cooldowns, and reminders for missing or expiring XP buffs.
- Add Trainer Budget to show the combined cost of available training and the gold still needed. Training uses Blizzard's purchase button.
- Add first-trip estimates for known flight paths and improve how the flight timer detects takeoff and restores an active flight after reload.
- Limit minimap information hit areas to visible text, the information box, and the invite icon so the rest of the minimap stays clickable.

### Character Panel and Inspect

- Follow native character tabs for reputation, currency, and Forever's skills, PvP, or stats views. Improve Overview and Equipment navigation and restore model control click targets. Keep readable vitals visible and show when full stats are available after combat.

### DataTexts

- Add a live DataTexts preset gallery for creating and styling bars. Back restores the prior bar and scroll position. Hover a row in the delete picker to highlight the matching on-screen bar.

### Nameplates

- Carry supported Blizzard nameplate settings through module profile exports, imports, and Workbench restore points.

### Skinning and Blizzard windows

- Add dedicated skins for the native Legacy talent tree, reward track, and challenge page while preserving their native artwork and state.
- Add an optional Readable values and status symbols setting for Bags, Character Panel, and Cooldown Manager, including larger cooldown and stack text.
- Improve mailbox readability with opaque message panes, theme-aware compose and invoice text, and a hint for messages with no body text.
- Prepare enabled Player Spells and Professions skins before combat, preserve Blizzard's spellbook rows and Group Finder scrolling, and respect reduced motion in profession panel transitions.

## 0.1.16 Alpha - 2026-11-09

### Character Panel and Inspect

- Keep the Suite Character Panel interactive during combat, including its tabs and gear details.
- Preserve the window layout when entering or leaving combat. Equipment changes continue to respect Blizzard's combat restrictions.

## 0.1.15 Alpha - 2026-11-09

### Character Panel and Inspect

- Add an optional Suite Character and Inspect interface for Retail and WoW Forever under Interface > HUD > Character Panel. Choose the Basic Blizzard skin or the Suite interface. Upgraded profiles keep the Basic view by default.
- Add Overview, Equipment, Reputation, Skills or Professions, PvP, Currency, and Statistics pages where the client provides the data. Inspect includes Overview, Equipment, and Compare with per-slot item-level differences.
- Show item tooltips, equipment set actions, gear audit details, and character information in the Suite window. Add model controls and show mounted movement speed when available.
- Add persistent window placement, scaling, docking, minimize and maximize controls, and overflow for the tab strip. Route character and inspect shortcuts to Blizzard when a native combat or gamepad path is needed.
- Customize the Character and Inspect headers independently. Toggle and style portrait, name, level, class and specialization, guild, zone, and item level. Reposition elements in the live preview with drag, arrow keys, or numeric offsets.
- Build custom Character tabs from presets or a blank layout. Search client-specific sources, add cards and rows, rename, duplicate or remove tabs, reorder them, and move the contents in the preview.
- Improve the Basic character and inspect skins with shared headers, tabs and action buttons. Keep Blizzard's stats lists under native control and improve Equipment Manager, item-level badges, and gear details, including Forever's ranged slot.
- Fix Forever character tab selection and spacing when toggling the side panel, and preserve native detail and inspection fallbacks when data is unavailable.

### Gathering and Quality of Life

- Add Resource Routes for known herbs, ore, fishing pools, skinning spots, and Retail timber. Open the route panel with `/msufgather` or from Quality of Life.
- Guide to the nearest known location with a direction arrow and distance in meters, then select another spot on arrival. Switch targets manually, place a Blizzard map waypoint, or stop guidance. The open-world arrow continues in combat and pauses in instances.
- Add an optional gathering radar with a configurable 50-300 meter range, profession filters and tracking status. Use `/msufgather hud` to toggle the radar and `/msufgather stop` to stop guidance.
- Use available GatherMate2 locations, save spots from the current position or map, and remove custom locations. Optionally remember successful herb and ore harvests.
- Add optional Current Zone and Other Zones groups for watched quests, including parent-zone matching for submaps. Keep focused quests separate and preserve ordinary grouping for quests with unreadable locations.
- Reduce repeated quest completion and log reads and reuse Objective Tracker rows. Quest reward actions still check the current quest state when clicked.
- Save up to six required spells per dungeon and character in Loadout Reminder. Enter names or spell IDs, see which abilities are missing, and clear the current dungeon's saved rules.
- Add an optional single-key fishing and bobber interaction on Forever. The Fishing key uses Blizzard's Interact Key during a fishing channel and returns to its normal binding when the cast ends or combat starts.
- Reuse the same mount lookup for character surfaces and unit tooltips, including checks for restricted aura data.

### WoW Forever world map

- Add an optional Observed Layer ID based on nearby NPCs. Show an unknown state when a usable observation is unavailable and reset it on a shard transfer. This is a local estimate that can differ between players on the same layer.
- Keep the map-side quest list on its native wheel and scrollbar offsets. Limit quest-row styling to the visible map and avoid redundant updates to hover artwork.
- Release compact quest titles at combat entry and repaint the list when combat ends. Preserve quest rows during collapse fades and Blizzard's row recycling.

### Nameplates, Action Bars, and Cooldown Manager

- Add an optional enemy power bar to supported Blizzard nameplate skins. Set its width, height, position, smoothing, resource colors, fallback color, and background opacity. Select, drag and resize it in the preview.
- Read power only for visible eligible enemy units, clear reused bars when plates change, and leave restricted values with Blizzard's supported display path.
- Add a Group Only visibility option to each action bar. It combines with existing per-bar visibility and gamepad rules.
- Fix pressed and checked artwork for styled action buttons and restore the correct appearance when switching button styles. Keep auto-repeat actions highlighted when the client exposes their state.
- Add defensive auras cast by you to the Cooldown Manager aura picker on supported clients, including Ignore Pain on Retail. Add Time Dilation to the group-buff choices.
- Track your supported external defensives on their readable recipients and show the recipient name on aura bars. Clear stale names on target, focus or roster changes and omit unverified recipient data.
- Improve resource and usability refreshes on visible cooldown entries. Skip hidden bars and redundant checks while keeping range tint and ready-glow behavior.

### DataTexts and Chat

- Keep the DataTexts game menu button available in combat through a preconfigured secure popup. Restricted actions stay disabled during combat and the popup closes after an action or when dismissed.
- Apply the active skin to the game menu, including fonts, hover state, border and opacity. Use the full bar width when the game menu is its only horizontal slot, and keep the popup within the screen.
- Center new freely positioned DataText bars and reset their position when changing from a dock to free placement. Open the selected bar's positioning popup directly from Move on Screen.
- Improve Copy Chat with a larger, scrollable text area, native selection and a visible Copy All action. Match the copy window, line picker, text input, and buttons to the active UI styling.

### Settings, previews, and skinning

- Move HUD into Interface and add the Character Panel to its preview. Let the feature selector wrap in narrow layouts and keep color shortcuts linked to the selected feature.
- Open the relevant preview handle and X/Y field from minimap position search results. Route other minimap results to their exact controls.
- Preserve inherited header colors in the color picker and keep the Nameplates setting index lazy until the page or search needs it.
- Keep Blizzard Settings and Keybindings scrolling native while easing the rendered content. Keep adaptive wheel acceleration on the AddOn List.
- Improve AddOn List collapse and expand animations with clipped copies of departing rows. Distinguish a real collapse from row recycling and preserve rows that remain visible.
- Avoid overlapping fades on nested menus and search results. Reuse menu discovery when reopening a skinned window and preserve scroll state through content updates.
- Refresh bundled Retail and Forever factory profiles, including Character Panel defaults. Update translations and extend regression coverage for the new modules, previews, secure menus, quest refreshes, and skin transitions.


## 0.1.14 Alpha - 2026-11-08

### Highlights

- Bags and Bank gain more appearance controls, a matching item preview, and gold totals for this login or the current day.
- The XP bar and tooltip can show time played at the current level. The editor previews the new label alongside the existing time-to-level estimate.
- Improved WoW Forever startup during a UI reload in combat, including HUD modules and the skinning work that resumes when combat ends.

### Bags, Bank, and DataTexts

- Refine reagent slots, bag and bank tab placement, item borders, and the placement and size of bag buttons. Keep native bag-slot input and the related bag and bank windows clear while another inventory window is open.
- Add gold history and per-character balances to the shared ledger. The Bags summary and the Today Gold DataText use the same daily total.
- Improve the native bag-bar takeover and the first layout of DataText bars after a reload or UI scale change.

### Chat, Nameplates, and Cooldown Manager

- Improve chat tab renaming, toolbar and detached-window previews, and the handling of saved screen positions on supported hosts.
- Refine nameplate level and name text, size controls, and the preview layout. The preview keeps the selected layout while switching settings tabs.
- Improve Cooldown Manager bar previews, layout controls, and host integration for saved profiles and native cooldown viewers.

### WoW Forever map and skinning

- Keep map information markers in the Suite's own layer and refresh them alongside Blizzard map updates. Improve quest search and compact quest-list controls.
- Improve world map positioning with Parallel Windows, including native panel transitions and combat deferral.
- Refine skins for Group Finder, professions, the spellbook, and talents. Improve native scroll motion, caption buttons, and the repaint of settings as windows reopen.

### Quality of Life and settings

- Group related settings into clearer sections and refine item selection and settings previews.
- Choose Shift, Ctrl, or Alt to pause quest automation. On Retail, Tooltip IDs can use a selected modifier or stay visible.
- Add an option to filter resource errors such as low energy or rage.
- On the MSUF 7.0 host, show the round variant of compatible minimap Icon Skins and preserve the crop when restoring player aura icons.
- Refresh the bundled Retail and Forever factory profiles and update translations for the new controls.

## 0.1.13 Alpha - 2026-11-07

### Highlights

- Chat has a new settings workspace, an optional header toolbar, and Edit Mode support for detached chat windows.
- DataTexts gains a Modern data bar, a standalone game-menu button, progress indicators, and a more interactive bar editor.
- The XP bar now has a drag-and-drop text editor, independent textures, and per-label formatting.
- WoW Forever gains opt-in world map information and gathering skill tooltips. Skinning also offers a compact quest list layout.
- An opt-in Quality of Life tool keeps supported Blizzard windows open together. The merchant Buyback tab now has item search.

### Chat

- Organize settings into Basics, Appearance, Input Line, Messages, and Extras. Topic buttons wrap as the settings window narrows and share a persistent preview.
- Add an optional header toolbar with New Tab, Chat Input, Copy Chat, a move and resize lock, and Chat Settings. The toolbar reserves space in the tab strip and remains accessible while hovered in minimal mode.
- Add optional input-line animation with adjustable duration and width. A width of zero follows the chat window.
- Add the Compact chat look with the toolbar, smaller tabs, an animated input line, and the sidebar collapsed.
- Add individual Edit Mode movers for detached chat windows. The preview lists the detached windows and links to their movers. Position edits preserve native saved placement and support undo.
- Use screen-position fields on compatible MSUF hosts, with offset controls on older hosts. Preserve fractional offsets and the untouched axis when moving or nudging the docked chat window.
- Add a multi-select picker for deleting chat tabs, with confirmation and safeguards for primary or changed tabs.
- Let preview layers reflect the live chat layout and provide direct links from selectable preview elements to their settings. Improve hover, text fading, copy, clock, sidebar, and tab overflow behavior.
- Move mouse-wheel scrolling, class-colored names, whisper window behavior, and message fading into Chat Behavior under Messages. Existing profiles and legacy Daily UI Comforts imports carry their saved chat choices forward.

### DataTexts

- Add the Modern data bar preset with a centered clock and slots for the game menu, progress, durability, professions, gold, FPS, latency, and location.
- Add the standalone Micro Menu Button preset and a customizable caption for any slot using that source.
- Add a Progress Bar source that displays XP with rested progress while leveling, then tracked reputation or renown, and honor when available. The tooltip identifies the progress being shown.
- Let the preview select slots and expose their settings, simulate progress, and reflect centered and docked layouts. Use the same progress fill and rested segments in the preview and live bars.
- Add bar selection, an All Bars view for shared settings, and confirmed multi-bar deletion. Refresh the editor and source picker as bars and sources change.
- Align the bar selector with Add Bar and Delete Bars in wide layouts. Keep the actions on a separate row in narrow layouts.
- Refresh active sources when their bindings change, keep their event subscriptions in sync, and update the Hearthstone menu as available hearth items change. Improve native bag-bar visibility, dock geometry, and weekly rewards integration.

### Experience Bar and HUD

- Add independent foreground and background textures for the XP bar.
- Configure Level, Current XP, Percentage, Session XP, XP per Hour, and Time to Level independently. Each text element has font, size, outline, anchor, offsets, and applicable visibility and display formats.
- Choose current, current/maximum, or remaining XP, percentage precision, short or full numbers, and labeled or value-only readouts where supported.
- Select, drag, and nudge text directly in the XP preview. Edit offsets and jump to the selected text's settings from the preview.
- Start a fresh XP session on a new login and preserve it across a UI reload, including when the optional XP module is enabled after login. Keep preview samples separate from live session statistics.
- Add Classic Lines, Twin Arrows, Gilded Edges, and Soft Glow artwork for announcement banners. The HUD preview can switch artwork, hide it, and replay the banner with the same artwork as the live HUD.
- Give announcement artwork its own frame and keep the banner background opacity independent. Edits preserve a live banner's display time and bring the static sample back after preview playback.

### WoW Forever world map and gathering

- Add an opt-in World Map Information module with zone level ranges, flight points, boats, zeppelins, skycutters, dungeon entrances and approaches, and roads to neighboring zones.
- Configure each map overlay separately, filter travel markers by faction, and adjust marker size. Click a marker to place a map pin.
- Add opt-in gathering skill information for known herbs and ore deposits. World-object and minimap-node tooltips can be enabled independently and can color the requirement by your skill margin.
- Add an optional Glimmer highlight for skinnable corpses. Refresh the highlight after looting as the interaction changes.

### Skinning and Blizzard windows

- Add a Blizzard or Compact quest list selector under Skinning. Compact shows level, title, and objective progress while retaining quest search, tracking, selection, and native tooltips.
- Style the world map's quest search, count area, and row hover without replacing Blizzard's map highlight or tooltip behavior.
- Add an opt-in Keep Blizzard Windows Open setting for supported panels such as the auction house, bags, quest details, professions, and the world map. Set an optional window limit and use Escape to close the most recently opened supported window. Preserve the compact map position across maximize and restore.
- Add a fit-to-screen caption control for supported skinned windows, with restoration of the previous position and scale. Refine minimize and close button placement, title clearance, and combat deferral.
- Skin Blizzard's Chat Settings, including its categories, tabs, checkboxes, and channel and filter lists.
- Smooth AddOn List row and group transitions when filtering or rapidly toggling sections. Refine shared control glyphs and menu transitions.

### Nameplates

- Use MSUF's existing Fonts > Nameplates scope when the host provides it. Nameplate settings and search link to the corresponding formatting and color sections.
- On older compatible hosts, support full, clipped, abbreviated, and abbreviated-and-clipped names, with a configurable character limit, clip direction, and ellipsis. Friendly and enemy name colors can be customized independently.
- Apply shared text formatting and typography consistently between live nameplates and the preview, including supported character-name display options.
- Add castbar width adjustments and keep the native castbar border, height, and spell icon aligned. Add separate friendly and enemy Blizzard health bar border toggles on Forever.
- Add Hide Health Bar Borders for Blizzard and styled nameplates, including health, target, and selection borders. Find it from search and see the result in the preview.
- Position the primary and right target arrows independently with draggable preview handles or numeric offsets. Existing pair spacing carries forward.
- Make the personal resource display toggle available with the Blizzard look and improve border and offset handling for its power and alternate power bars.
- Improve level-number and badge behavior on name-only plates and refresh name styling as Blizzard reuses plates. Update preview castbar sizing, target decoration, and text positioning.

### Bags, Macros, and other tools

- Search the merchant Buyback tab by item name. Non-matching entries dim so their original positions and native buyback actions remain available.
- Create a spell macro from the spellbook picker and optionally publish it straight to Blizzard's macro list. Use the spell's icon automatically.
- Drop spellbook spells onto supported macro rule and sequence fields. Improve spell and pet-spell discovery, preserve ranked spell names on Forever, and add paging to the picker.
- After leaving Quick Keybind Mode opened from Suite Action Bars, close the Blizzard Settings panel the client reopens automatically. Preserve existing Blizzard keybind sessions and defer the close when combat locks the UI.
- Choose Original, Match Meter Look, or a separate theme for Damage Meter menus. The setting applies to meter, fight, target, and window menus, and the fight menu can be tried from the preview.
- Improve Minimap preview parity for the addon drawer, native zoom controls, player marker, and individual layers. Refresh the visible preview as the underlying minimap changes.
- Start the flight countdown reliably when taxi state updates arrive during or after takeoff. Reuse the running countdown until its timing changes.
- Smooth rapid open and close interactions in Adventure Planner groups and improve the size of its navigation rows. Refine Cooldown Manager preview chips and compact Action Bars navigation.

### Setup, profiles, and settings

- Resume Suite startup and installer checks when combat ends, including logins where the player's combat flag settles after the combat-end event.
- Improve settings search and preview links so they open the relevant topic, expand the matching section, and focus the setting on supported hosts. Keep old Chat Behavior search targets usable after the move.
- Add per-feature reset actions in Quality of Life and improve help affordances for truncated descriptions.
- Update localized labels and descriptions for the new settings and add automated coverage for the new runtime, profile, and preview behavior.

### Alpha issues carried forward

- Automatic profile selection and installer appearance on alternate characters still need live verification.
- Quest reward selection after handing in items remains an open issue. The quest list changes cover the world map layout and its controls.

## 0.1.12 Alpha - 2026-11-06

### Bags, bank and inventory tools

- Add compact-window and side-panel layouts, adjustable window sizing, equipped-bag controls and optional bag animations.
- Add a category for equipment usable by your character and improve search, filters, category controls and bank presentation.
- Improve bag previews, native cleanup access, window resizing and native bag-bar ownership.

### Cooldown Manager

- Add group-buff tracking options and improve aura handling when targeting yourself or changing targets.
- Improve cooldown entry layout and configuration previews.

### Chat

- Start chat dragging from the visible window position and preserve the other coordinate when editing an axis.
- Improve chat mover controls and preview positioning.

### Quality of life

- Keep disabled action bars hidden when dragging actions and improve action-bar visibility controls.
- Add WoW Forever reminders for Mage armor and Priest Inner Fire, including known spell ranks.
- Keep the native XP bar hidden when Force Hide is enabled, including after late interface updates.
- Improve flight-route tracking, damage-meter initialization and native name-only display for friendly NPCs.

### Setup

- Add character-specific setup status and an option to select an existing profile during setup.
- Improve startup sequencing and profile synchronization with the skin module.
- Known Alpha issue: automatic profile selection and installer appearance on alternate characters remain under investigation.

### Skinning

- Preserve native world-map canvas motion on WoW Forever to prevent missing map tiles.
- Keep configured dropdown text colors through hover and menu state changes.
- Improve window motion, merchant focus and quest reward-page refresh handling.
- Known Alpha issue: quest reward selection can still fail after handing in quest items; this is not claimed as fully resolved.

## 0.1.11 Alpha - 2026-11-05

### Chat

- Keep the anchored chat window at its saved Suite position after native layout updates.
- Prevent chat from snapping back while dragging in Edit Mode; avoid competing Blizzard and Suite movers and preserve undo and native-position restoration.

### Bags and native windows

- Avoid stale item-binding queries when an item has just been sold or its bag slot has become empty.
- Correct quest progress, turn-in and reward text refreshes while keeping native page resets immediate.
- Preserve merchant-window focus during updates and avoid restricted gamepad-button inspection.
- Defer hidden social-window styling and preserve native scrolling controls.

### Menus and previews

- Organize Quality of Life into directly selectable, wrapping groups with expandable feature settings.
- Keep Suite gameplay helpers on the host Gameplay page and improve settings navigation and search.
- Prevent the Buff Reminders preview from overlapping its settings.
- Hand castbar artwork settings to compatible MSUF hosts while preserving existing saved choices. Native artwork requires MSUF 6.508 or a 7.0 build with artwork support; older hosts retain saved choices until upgraded.
- Refine the MSUF Blizzard setup preset and its bundled artwork.

### Glimmer

- Preserve native quest sparkles and improve highlight recovery, animation behavior and settings previews on WoW Forever.
- Improve Glimmer and Questhelp search discovery and retain deliberate opt-outs across setup presets.

## 0.1.10 Alpha - 2026-11-05

### Setup

- Fixed automatic Suite setup on first login and when an unfinished setup resumes: an unopened MSUF welcome screen no longer prevents the installer from appearing.
- Preserve priority for visible MSUF onboarding, combat deferral and completed or skipped installations.

## 0.1.9 Alpha - 2026-11-04

### Previews, loading and compatibility

- Keep the Bags, Damage Meter, Buff Reminders and Skinning areas directly selectable as tabs when the settings window is narrow or resized.
- Corrected DataTexts header sizing so bar choices and the add-bar button stay within the menu.
- Updated Mail templates and shared inventory-tool windows to the current MSUF menu style, including search fields, buttons, lists and scrollbars.
- Reorganized Quality of Life into searchable categories with enabled and disabled filters and inline feature settings.
- On compatible hosts, show Suite combat helpers on Gameplay and castbar artwork under Cast Bars while preserving saved settings, search links and favorites.

### Windows and skinning

- Keep the Character and Item Upgrade windows undimmed when used together.
- Corrected quest-panel background bounds to prevent the dimmed surface from extending beyond the native panel.
- Matched Adventure Guide ability descriptions, role sections, headers and help tips to the dark menu style while preserving readable text and native ability links.

### Cooldown Manager

- Corrected Warlock interrupt readiness and preset selection for Spell Lock granted by Grimoire of Sacrifice.
- Refined the MSUF Blizzard preset's focus position and boss and arena aura placement.

## 0.1.8 Alpha - 2026-11-03

### Setup presets and appearance

- Added the optional Dark Raid setup preset and refined the MSUF Blizzard preset, including frame artwork, castbars, party and raid settings, chat and damage meters.
- Improved installer previews, reference images, minimap elements and native queue-button placement.

### Windows and skinning

- Improved native window focus highlights, popup layering and movable window controls.
- Corrected combat-time skin updates and character equipment details, including delayed item information and native control handling.

### Cooldown Manager and bags

- Corrected Healthstone and Demonic Healthstone charges and cooldown refreshes during combat.
- Improved shared cooldown ownership and editor identity when changing specialization or profile.
- Corrected delayed bag and bank item information, inventory indexing and stale upgrade markers.

### Quality of life

- Fixed battle-resurrection text initialization, merchant protection checks and asynchronous loot-container handling.
- Improved Adventure Planner combat readiness, keystone sharing and player-aura geometry.

### Chat, data texts and damage meters

- Added the chat header clock and updated data-text icons and source selection.
- Corrected gamepad currency selection, damage-meter row identity and preview behavior.

## 0.1.7 Alpha - 2026-11-01

### Appearance

- Added the optional MSUF Blizzard installer preset with gold portraits, centered cooldowns, party frames and gryphon endcaps.
- Added two switchable, enlargable reference screenshots while keeping the interactive layout and module preview available.

### Chat

- Matched preview tabs, fonts, sidebar icons, message clipping and positioning more closely to the live chat window.

### Cooldown Manager

- Added replacement-buff tracking by spell name or ID while retaining the original spell cooldown.
- Refresh native spell and item catalogs after equipment, talent, specialization and Blizzard cooldown-data changes.

### Bags, bank and inventory tools

- Corrected BoE, Warbound and Warbound-until-equipped badges and search filters using each item's current binding state.

### Action Bars, Buff Reminders and HUD

- Added rank-aware Shaman shield and weapon-imbue reminders on WoW Forever.
- Added Blizzard gryphons as an action-bar endcap choice, with matching runtime and options previews.

### Quality of Life

- Added default-on Glimmer highlights for herbs, ore and quest objects selected by WoW Forever's native interact target.
- Glimmer includes category, effect, range and color controls plus a settings preview, and pauses during combat.

### Damage Meter

- Added melee and environmental damage names and icons to death recaps and improved the related preview controls.

### Skinning

- Keep Group Finder scroll state native while easing its visuals, and improve skinning of the game menu opened during combat.
- Improved native control detection, protected-frame guards and deferred skin updates.

### Previews, loading and compatibility

- Build native Nameplate options tabs on demand and prepare their controls before opening a search result.
- Improved settings search, preview navigation and client-specific regression coverage for Retail and WoW Forever.

## 0.1.6 Alpha - 2026-10-31

### Skinning

- Fixed passive tooltips becoming mouse targets when skin animations were attached, which could cause tooltip flicker and interfere with interactions beneath them. Opening animations remain available without adding mouse handlers to passive frames.
- Reload the interface after updating so previously installed mouse handlers are cleared.

### Chat

- Added an interactive Chat preview: select and drag the window, message text, tabs, input bar, copy button and sidebar icons, or adjust their coordinates precisely.
- Preview selections open the corresponding settings. Position edits support arrow nudges, undo/redo and resets, with guards against stale drags and edits after profile changes or during combat.
- Shared the sidebar artwork and window painters with the live Chat display, including native icon availability, unlocked window dimensions, inherited fonts, input geometry and complete-message clipping.
- Added saved offsets for message text, tabs and the input bar while preserving Blizzard's native chat interactions.

## 0.1.5 Alpha - 2026-10-31

### New Macro workshop

- Added a dedicated Macro menu with Builder, Consumables, My macros and Code tabs, plus search links that open the matching editor.
- Build macros from ordered actions, alternative rules and conditions, including target selection, modifier keys and negated conditions. Reorder actions and edit the generated result before creating a WoW macro.
- Added templates for focus interrupts, heal-or-attack choices, mouseover healing and attacks, cursor casts, self casts, pet commands, weapon switching and spell or item sequences.
- Added spell, item, pet-spell and icon pickers, target and world marker choices, action-bar page commands, sequence reset settings and optional tooltip generation.
- Added consumable builders for health supplies, food and drink, buff food, flasks and bandages. Configure Healthstone, healing potion and healing spell priorities, preferred items and flask stats.
- Consumable macros can choose available bag items, prefer conjured food, include a combat mana potion and refresh outside combat when automatic updates are enabled.
- Save drafts separately from WoW macros, search saved drafts and existing macros, import an existing macro into the editor, and choose character or account scope.
- Preview the generated code and character count, create or update a linked WoW macro, then pick it up or drag it to an action bar. Replacing a linked macro and discarding unsaved edits require confirmation.

### Adventure Planner

- Rebuilt the Adventure Planner as a separate window with grouped, collapsible navigation, a weekly overview, preparation checks, archives and instance tools.
- Added character snapshots with weekly Great Vault progress, keystones and recorded lockouts. Information shows the characters you have visited and the time of the saved snapshot.
- Added a personal preparation overview and ready-check preparation prompts.
- Added instance loadout snapshots and reminders on Retail.
- Added Mythic+ and raid archives, including saved run summaries, raid attempts and recorded encounter results.
- Added saved Group Finder workspaces and instance notes and checklists, with reminders when entering the matching instance.
- Added planner search routes, settings shortcuts, window motion and history integration. Available tabs follow the current client.

### Bags, bank and inventory tools

- Reorganized bag settings into Bags, Inventory organisation and Bank organisation workspaces.
- Expanded bag sorting with name, quality, item level, type, expansion, stack count and vendor-price choices; added saved searches and structured search filters.
- Added free-slot counts, optional upgrade markers and additional categories for profession gear, collectibles and containers.
- Added a separately configurable bank window with its own scale, position and background.
- Added an inventory archive to search recorded bags and banks across your characters, with snapshot dates and recorded item-owner counts in tooltips.
- Added stock targets with missing quantities and recorded bank supplies, plus a Retail crafting shopping list that combines tracked recipes and lets you choose material alternatives.
- Added never-sell lists and conservative equipment-set protection for Suite sale actions.
- Added Retail bank-transfer previews, moving one selected stack per click, and mail templates for recorded characters with saved subjects and item quantities. Sending mail stays manual.

### Everyday helpers

- Added Action and key review to inspect action slots, missing bindings and overridden keys without changing them.
- Added currency goals with goal-reached and near-cap notices.
- Added watched chat words and phrases with channel filters, repeat limits and optional sounds.
- Added named waypoint lists and a button to activate the next saved stop.
- Added context sound profiles for open-world, dungeon, raid and PvP play, with separate music, ambience and effects levels and a list of sound file IDs to mute.
- Added a bounded Suite notice history that combines repeated notices and opens the related settings.
- Added mail-recipient lists for recorded characters, with name, level and recent-visit sorting, minimum levels and hidden-recipient controls.
- Added quest-reward vendor-value markers, accounting for stack size; choosing a reward remains manual.
- Added fishing bindings with optional rod and lure choices and a temporary fishing sound profile.
- Added separate automatic-response choices for summons, resurrections, duels, pet duels and party invitations from strangers, with optional chat feedback and combat restrictions.

### Mythic+, groups and progression

- Added saved native Group Finder filters for dungeon difficulty, leader rating, activities, role availability, tanks and healers, plus Mythic+ application statistics for the session, character or account.
- Expanded applicant information with locally available Raider.IO raid progress and searchable profile links.
- Expanded keystone sharing and dungeon portals with optional other-addon key sources, current-season or custom portal sets and improved portal selection.
- Mythic+ role checks retain their automatic confirmation option. Invitations now show a reminder and remain manual in Blizzard's dialog instead of attempting blocked acceptance.
- Improved run summaries, party details, raid records, preparation data and loadout reminders.

### Cooldown Manager

- Reorganized bar configuration and spell selection, with clearer bar sections, scrolling, inspection tools and potion selection.
- Added more visibility conditions: resting, solo, outside instances, flying and dead, plus hidden opacity, mouseover reveal and fade duration.
- Added named-frame attachment, expanded bar sizing and alignment controls, and improved per-specialization layout handling.
- Added optional interrupt-ready glows and screen-center ready pulses, with additional glow styles and controls for line count, thickness and speed.
- Expanded icon swipe colors, class-colored swipes, active-buff swipes, sparks and optional Masque integration.
- Corrected preview text initialization and icon selection, aura highlights, spell overrides and cleanup when switching bars, profiles or preview contexts.

### Damage Meter

- Added target filtering, favorite meter choices and configurable chat reports with three, five or ten lines.
- Added identifiable party spell details during combat where the native data allows them, plus optional death details inside the meter.
- Expanded per-window behavior with scale, click-through modes, synchronized fight selection, role-based meter choices, return-to-current rules and Mythic+ start/end behavior.
- Added header visibility and button positioning, breakdown placement, optional smooth bar fill and more visibility conditions, including Delves.
- Expanded window, row and icon borders with independent styles, opacity, spacing and side controls, plus separators and separate background and breakdown textures.
- Added separate font and text-rendering choices for names, values, headers, details and the floating timer; the timer can dock to a chosen meter window.
- Reworked the menu preview and its layer editor, corrected hidden-preview cleanup and reduced work in hidden or faded windows.

### Action Bars, Buff Reminders and HUD

- Added Action Bar colors for usable spells, insufficient resources and unusable actions, plus fade duration, flyout direction and per-bar tooltip visibility.
- Added class and specialization reminders for supported buffs and stances, including Shadowform, Paladin auras and rites, Warrior stances, Shaman imbues and shields, Evoker ally buffs, Symbiotic Relationship and Arcane Familiar.
- Added reminder sounds, text-size controls and hide-while-resting behavior, with updated reminder and ready-check previews.
- Expanded the objective tracker with tracked collectibles, zone events, Traveler's Log activities, housing endeavors and tracked recipes where supported, plus optional raid encounters and Mythic+ overtime colors.
- Expanded the experience display to track experience, reputation, honor or an automatic choice; improved HUD, AFK and module preview handling.

### Chat, tooltips and DataTexts

- Added saved typed-chat history, main-chat anchoring, configurable line limits, movable sidebar icons, channel-specific sound kits or files and keyword or own-name highlighting.
- Expanded tooltip controls with specialization details, Mythic+ enemy forces where available, item-quality or class/reaction borders, and choices to hide faction, PvP, realm or guild lines.
- Added a modifier-key option to reveal hidden tooltips and improved tooltip scaling and visibility handling.
- Expanded DataTexts with Great Vault, supplies, secondary-stat and Mythic+ rating sources, plus improved source selection and previews.
- Added realm or local clock time, 12/24-hour and seconds choices, configurable durability/FPS/latency warning thresholds, coordinate precision and remembered or custom supplies.

### Minimap and native Nameplates

- Expanded Minimap difficulty-label colors and backgrounds, with sizing that follows the displayed text, and improved button selection and drawer handling.
- Fixed clock refresh after the AFK screen fades away and improved Minimap preview and visibility updates.
- Expanded Blizzard Nameplate controls for enemy and friendly units, minions, maximum distance, occluded opacity, distance fading and shrinking, stacking overlap and motion, screen margins and target clamping, where supported.
- Added mouseover highlighting, level difficulty colors, health-threshold line width and additional friendly castbar height, icon-size and timer-format controls. Nameplates continue to use Blizzard's native frames.

### Skinning, menus, profiles and loading

- Expanded Encounter Journal colors for cards, loot, filters, text, navigation and side tabs, with selected-tab updates.
- Reorganized Suite pages and shared previews, improved section and search routing, and integrated Blizzard player-aura layout and skin controls into the host's player-aura page on supported hosts.
- Integrated Suite settings with the MSUF 7.0 profile workbench, restore points and shared undo/redo, with improved profile switching and variant handling.
- Consolidated translated catalogs into one optional MSUF_Suite_Locales addon. Update all bundled Suite folders together and remove obsolete MSUF_Suite_Locale_* folders from older installs.
- Reduced repeated combat updates, hidden-window work and skin refreshes, and updated translations and compatibility handling for Retail, WoW Forever and supported MSUF hosts.
- Distributed through the Beta channel on CurseForge. The Suite version remains Alpha and requires Midnight Simple Unit Frames; newer host tools require MSUF 7.0. Client-specific features appear only where supported.

## 0.1.4 Alpha - 2026-10-25

### Appearance

- Added optional gloss to Suite bars and icons in the Damage Meter, Buff Reminders, Action Tracker, Battle Res, Enemy Cast Stack and Skyriding, with an adjustable strength.
- Added MSUF icon skins for the Minimap, Buff Reminders and Damage Meter icons.

### Quality of Life

- Added Mythic+ Auto Queue (Retail, off by default): confirms Mythic+ role checks with your saved roles and accepts invites for your active Mythic+ applications. Each part has its own switch.

### Minimap

- Grouped the Minimap settings into sections; search results open the matching section.

### Performance

- The connected MSUF menu opens pages, skins hidden menu parts and enters Edit Mode with much less work.
- Action bar cooldown feedback and the group Bloodlust tracker do less work per update.

## 0.1.3 Alpha - 2026-10-21

### Cooldown Manager

- Automatically save and restore bar layouts for each specialization, including positions, attachments, growth, rows, spacing and sizes. Specializations without a saved layout start from the current layout; shared layouts remain available.
- Preserve profile variant overrides while switching specialization layouts, editing bars, resetting settings and importing profiles.
- Added configurable pandemic-window highlights to buff icons, buff bars and cooldown icons displaying an aura, with glow style, color, border thickness and per-spell overrides.
- Improved native aura-container rendering, inactive placeholders, glow attachment and cleanup, including spell overrides and combat updates.
- Added MSUF icon skins and icon shapes to Cooldown Manager bars, with host-compatible fallbacks.

### Action Bars and player auras

- Added MSUF icon-skin selection and Rounded, Diamond, Hexagon and Blizzard portrait button shapes alongside Square and Circle on supported hosts.
- Added optional MSUF icon skins for Blizzard's player buffs and debuffs while retaining Blizzard's native size and layout.
- Improved player-aura skin refreshes so only artwork reset by Blizzard is repainted.
- Updated factory profiles and appearance setup to preserve the selected icon styles.

### Skinning and menu motion

- Added short hover, click, focus, selection, tab, disclosure and content transitions to Suite-owned interface artwork, plus blended palette changes.
- Added animated AddOn-list groups and search/filter result transitions, with cleanup for hidden or reused rows.
- Added optional smooth scrolling for supported native ScrollBoxes, modern scrollbars and legacy ScrollFrames; scrollbar dragging remains immediate.
- Added dropdown background dimming and shared transition support for Blizzard Settings, native tabs, Suite dialogs and supported AceGUI/AceConfig menus.
- Added Menu animations, Smooth scrolling, Reduced motion and Dim background for dropdowns controls, shared with the connected MSUF 7.0 menu where supported.

### Previews, loading and compatibility

- Unified interactive previews for Action Bars, Cooldown Manager, Nameplates, Minimap, Damage Meter, HUD and setup, including drag-hook ordering and corrected nameplate drag thresholds.
- Load only the language pack selected in MSUF instead of compiling every translation catalog at startup. Keep all bundled addon folders together when updating.
- Improved stored-profile copying and use native timed signal maps on supported clients, retaining the existing timer fallback and next-frame behavior.
- Updated translated controls, search labels, profile migrations, packaging validation and regression coverage for Retail, WoW Forever and supported MSUF hosts.
- Distributed through the Beta channel on CurseForge and Wago. The Suite remains in Alpha and requires Midnight Simple Unit Frames. New host icon skins and shapes require MSUF 7.0; older hosts retain compatible rendering.

## 0.1.2 Alpha - 2026-10-16

- Updated WoW Forever minimap integration for build 1.60.1.70425, including native button textures and removed widgets.
- Integrated Blizzard's conditional external-event button into the minimap row while preserving its native visibility and click behavior.
- Fixed the day/night ring to keep a constant visible size and restore Blizzard's current scale and position when the module is disabled.
- Matched minimap previews to native textures, hover layers and circular event masking, including compact preview sizes.
- Updated translations and regression coverage for Retail, WoW Forever, module cleanup and combat deferral.
- Distributed through the Beta channel on CurseForge and Wago. The Suite remains in Alpha and requires Midnight Simple Unit Frames.

## 0.1.1 Alpha - 2026-10-14

- Fixed Envenom buff tracking and the same cast-target versus buff-target mismatch across native Retail Cooldown Manager entries.
- Fixed aura identities, sounds and timer subscriptions after spell overrides, including changes during combat.
- Added action-bar glows for usable spells and configurable aura glow sources, with matching previews.
- Expanded native nameplate styling with target scaling, borders, static shadow/glow, focus markers, texture finishes and a health threshold indicator.
- Added an optional WoW Forever helper that updates action-bar spells to their highest learned rank, with a separate option for deliberately lower ranks.
- Fixed native Delve header sizing and widget stacking in the objective tracker.
- Updated translations, option previews and regression coverage.
- Distributed through the Beta channel on CurseForge and Wago. The Suite remains in Alpha and requires Midnight Simple Unit Frames.

## 0.1 Alpha - 2026-10-13

- Requires Midnight Simple Unit Frames (MSUF), installed separately. Compatible with MSUF 6.5 (release 6.50) on Retail 12.1.5 and WoW Forever 1.60.1. The Suite remains in Alpha.
- Expanded action bar, Cooldown Manager, buff reminder, bag and bank, chat, minimap, DataTexts, Damage Meter, native nameplate styling, and Skinning options.
- Added setup presets, shared profile integration, grouped option pages, searchable controls, and interactive previews.
- Expanded group and dungeon utilities, encounter information, incoming combat text, death alerts, and reminders.
- Improved profile switching, migrations, native frame ownership, module cleanup, event handling, and recovery from failed option builds.
- Includes the current localized menus and regression coverage for Retail, WoW Forever, and the MSUF host. Offline checks do not replace in-game testing.

## 1.0 Alpha 1 - 2026-09-25

- First public alpha package of the Suite core, optional modules, and Suite-owned Skinning module.
- Retail Modern's factory Micro Bar uses the compact two-column layout beside the Damage Meter. WoW Forever keeps its own factory design.
- Includes Suite pages inside MSUF Options, profile integration, and client-specific addon manifests.
- Requires Midnight Simple Unit Frames. Retail and WoW Forever have offline contract coverage; live gameplay and visual testing are still needed.
- Bags: profiles from before the Suite inventory views keep Blizzard's own item grid (new view choice Blizzard grid). The Suite views list slots in bag order, show every slot in combat and keep their tooltip lines.
