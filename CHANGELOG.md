# MSUF Suite Changelog

### Unreleased

#### Highlights

- Chat has a new settings workspace, an optional header toolbar, and Edit Mode support for detached chat windows.
- DataTexts gains a Modern data bar, a standalone game-menu button, progress indicators, and a more interactive bar editor.
- The XP bar now has a drag-and-drop text editor, independent textures, and per-label formatting.
- WoW Forever gains opt-in world map information and gathering skill tooltips. Skinning also offers a compact quest list layout.
- An opt-in Quality of Life tool keeps supported Blizzard windows open together. The merchant Buyback tab now has item search.

#### Chat

- Organize settings into Basics, Appearance, Input Line, Messages, and Extras. Topic buttons wrap as the settings window narrows and share a persistent preview.
- Add an optional header toolbar with New Tab, Chat Input, Copy Chat, a move and resize lock, and Chat Settings. The toolbar reserves space in the tab strip and remains accessible while hovered in minimal mode.
- Add optional input-line animation with adjustable duration and width. A width of zero follows the chat window.
- Add the Compact chat look with the toolbar, smaller tabs, an animated input line, and the sidebar collapsed.
- Add individual Edit Mode movers for detached chat windows. The preview lists the detached windows and links to their movers. Position edits preserve native saved placement and support undo.
- Use screen-position fields on compatible MSUF hosts, with offset controls on older hosts. Preserve fractional offsets and the untouched axis when moving or nudging the docked chat window.
- Add a multi-select picker for deleting chat tabs, with confirmation and safeguards for primary or changed tabs.
- Let preview layers reflect the live chat layout and provide direct links from selectable preview elements to their settings. Improve hover, text fading, copy, clock, sidebar, and tab overflow behavior.
- Move mouse-wheel scrolling, class-colored names, whisper window behavior, and message fading into Chat Behavior under Messages. Existing profiles and legacy Daily UI Comforts imports carry their saved chat choices forward.

#### DataTexts

- Add the Modern data bar preset with a centered clock and slots for the game menu, progress, durability, professions, gold, FPS, latency, and location.
- Add the standalone Micro Menu Button preset and a customizable caption for any slot using that source.
- Add a Progress Bar source that displays XP with rested progress while leveling, then tracked reputation or renown, and honor when available. The tooltip identifies the progress being shown.
- Let the preview select slots and expose their settings, simulate progress, and reflect centered and docked layouts. Use the same progress fill and rested segments in the preview and live bars.
- Add bar selection, an All Bars view for shared settings, and confirmed multi-bar deletion. Refresh the editor and source picker as bars and sources change.
- Align the bar selector with Add Bar and Delete Bars in wide layouts. Keep the actions on a separate row in narrow layouts.
- Refresh active sources when their bindings change, keep their event subscriptions in sync, and update the Hearthstone menu as available hearth items change. Improve native bag-bar visibility, dock geometry, and weekly rewards integration.

#### Experience Bar and HUD

- Add independent foreground and background textures for the XP bar.
- Configure Level, Current XP, Percentage, Session XP, XP per Hour, and Time to Level independently. Each text element has font, size, outline, anchor, offsets, and applicable visibility and display formats.
- Choose current, current/maximum, or remaining XP, percentage precision, short or full numbers, and labeled or value-only readouts where supported.
- Select, drag, and nudge text directly in the XP preview. Edit offsets and jump to the selected text's settings from the preview.
- Start a fresh XP session on a new login and preserve it across a UI reload, including when the optional XP module is enabled after login. Keep preview samples separate from live session statistics.
- Add Classic Lines, Twin Arrows, Gilded Edges, and Soft Glow artwork for announcement banners. The HUD preview can switch artwork, hide it, and replay the banner with the same artwork as the live HUD.

#### WoW Forever world map and gathering

- Add an opt-in World Map Information module with zone level ranges, flight points, boats, zeppelins, skycutters, dungeon entrances and approaches, and roads to neighboring zones.
- Configure each map overlay separately, filter travel markers by faction, and adjust marker size. Click a marker to place a map pin.
- Add opt-in gathering skill information for known herbs and ore deposits. World-object and minimap-node tooltips can be enabled independently and can color the requirement by your skill margin.
- Add an optional Glimmer highlight for skinnable corpses. Refresh the highlight after looting as the interaction changes.

#### Skinning and Blizzard windows

- Add a Blizzard or Compact quest list selector under Skinning. Compact shows level, title, and objective progress while retaining quest search, tracking, selection, and native tooltips.
- Style the world map's quest search, count area, and row hover without replacing Blizzard's map highlight or tooltip behavior.
- Add an opt-in Keep Blizzard Windows Open setting for supported panels such as the auction house, bags, quest details, professions, and the world map. Set an optional window limit and use Escape to close the most recently opened supported window. Preserve the compact map position across maximize and restore.
- Add a fit-to-screen caption control for supported skinned windows, with restoration of the previous position and scale. Refine minimize and close button placement, title clearance, and combat deferral.
- Skin Blizzard's Chat Settings, including its categories, tabs, checkboxes, and channel and filter lists.
- Smooth AddOn List row and group transitions when filtering or rapidly toggling sections. Refine shared control glyphs and menu transitions.

#### Nameplates

- Use MSUF's existing Fonts > Nameplates scope when the host provides it. Nameplate settings and search link to the corresponding formatting and color sections.
- On older compatible hosts, support full, clipped, abbreviated, and abbreviated-and-clipped names, with a configurable character limit, clip direction, and ellipsis. Friendly and enemy name colors can be customized independently.
- Apply shared text formatting and typography consistently between live nameplates and the preview, including supported character-name display options.
- Add castbar width adjustments and keep the native castbar border, height, and spell icon aligned. Add separate friendly and enemy Blizzard health bar border toggles on Forever.
- Improve level-number and badge behavior on name-only plates and refresh name styling as Blizzard reuses plates. Update preview castbar sizing, target decoration, and text positioning.

#### Bags, Macros, and other tools

- Search the merchant Buyback tab by item name. Non-matching entries dim so their original positions and native buyback actions remain available.
- Create a spell macro from the spellbook picker and optionally publish it straight to Blizzard's macro list. Use the spell's icon automatically.
- Drop spellbook spells onto supported macro rule and sequence fields. Improve spell and pet-spell discovery, preserve ranked spell names on Forever, and add paging to the picker.
- After leaving Quick Keybind Mode opened from Suite Action Bars, close the Blizzard Settings panel the client reopens automatically. Preserve existing Blizzard keybind sessions and defer the close when combat locks the UI.
- Choose Original, Match Meter Look, or a separate theme for Damage Meter menus. The setting applies to meter, fight, target, and window menus, and the fight menu can be tried from the preview.
- Improve Minimap preview parity for the addon drawer, native zoom controls, player marker, and individual layers. Refresh the visible preview as the underlying minimap changes.
- Start the flight countdown reliably when taxi state updates arrive during or after takeoff. Reuse the running countdown until its timing changes.
- Smooth rapid open and close interactions in Adventure Planner groups and improve the size of its navigation rows. Refine Cooldown Manager preview chips and compact Action Bars navigation.

#### Setup, profiles, and settings

- Resume Suite startup and installer checks when combat ends, including logins where the player's combat flag settles after the combat-end event.
- Improve settings search and preview links so they open the relevant topic, expand the matching section, and focus the setting on supported hosts. Keep old Chat Behavior search targets usable after the move.
- Add per-feature reset actions in Quality of Life and improve help affordances for truncated descriptions.
- Update localized labels and descriptions for the new settings and add automated coverage for the new runtime, profile, and preview behavior.

#### Alpha issues carried forward

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
