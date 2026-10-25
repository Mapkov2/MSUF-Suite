# MSUF Suite Changelog

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
