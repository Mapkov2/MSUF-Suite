# MSUF Suite

**MSUF Suite Alpha** brings modular interface tools to World of Warcraft Retail and WoW Forever. Open `/msuf` to configure the Suite and choose the modules for your layout.

**Midnight Simple Unit Frames (MSUF) is required. This Suite alpha is compatible with MSUF 6.5 (release 6.50).** MSUF is configured as a Required Dependency on CurseForge and is installed automatically with the Suite. When using Wago, install MSUF through the Wago client as well.

## Modules

- **Action Bars** - Layout and appearance settings for your action bars.
- **Cooldown Manager** - Cooldown, buff, and buff bar displays. A cooldown can track a replacement buff selected by name or spell ID; its original cooldown remains unchanged.
- **Buff Reminders** - Reminders for missing buffs and consumables, including rank-aware Shaman shields and weapon imbues on Forever.
- **Bags & Bank** - Inventory and bank views.
- **Chat** - Chat styling, history, fading, and unread tab indicators. An interactive preview lets you select, move and position the window, text, tabs, input bar, copy button and sidebar icons, with matching settings, undo/redo and resets.
- **Minimap** - Minimap layouts, appearance, and shortcuts.
- **DataTexts** - Configurable information bars.
- **Damage Meter** - Damage Meter windows, display options, and previews.
- **Nameplates** - Styling for Blizzard's native nameplates.
- **Adventure Planner** - A separate load-on-demand addon for character progress, lockouts, keystones, preparation and personal notes. Open `/plan`; runtime loads only when enabled.
- **Quality of Life** - Group and dungeon tools, encounter information, death alerts, incoming combat text, and reminders.
- **Skinning** - Interface window appearance and controls, with short hover, click, selection, focus, opening and disclosure animations on Suite-owned artwork. Blizzard AddOn-list groups animate their arrows and visible row transitions, with brief clipped visual copies for collapsing children. Menu page changes and completed search/filter results fade in, and palette changes blend owned backgrounds and borders. Modern and legacy dropdowns can dim their skinned window beneath the popup. Blizzard Settings pages, native tabs, Suite dialogs and AceGUI/AceConfig menus share these transitions. Supported native ScrollBoxes and modern scrollbars use optional smooth scrolling with immediate thumb dragging; older ScrollFrames use a short visual easing of their native offset. The Suite menu-animation, smooth-scrolling and reduced-motion switches also govern the connected MSUF 7.0 menu. Custom addons can adopt the same behavior through the scoped RegisterMenu/AnimateContent API. Configure Menu animations, Smooth scrolling, Reduced motion and Dim background for dropdowns under Corners and hover.

On Forever, **Quality of Life > Map & Travel > Glimmer** is enabled by default and highlights the native interact target for herbs, ore and quest objects. Its mini preview shows the selected effect directly above the controls, even while the module is disabled. Choose its categories, range, color and effect; it pauses in combat and restores the interaction settings it owns when disabled.

Modules can be enabled individually. The Suite includes shared profiles, setup presets, and previews in the MSUF options menu.

The optional **MSUF Blizzard** setup preset adds compact gold portraits, smooth shaded health fills, rounded inset borders and dark name strips with shadowed white text. Blizzard's native buff and debuff rows sit beside the minimap; target aura rows clear the name and portrait. Party and raid cards use Blizzard's native raid health texture, separate name headers and native role icons. Player buffs and HoTs sit inside the upper part of each card; debuffs and external defensive buffs occupy separate lower corners. Raid layouts use columns of five, with room for 40 players or 20 in Mythic raids. Boss frames have a red name and level header, health and blue power bars, an overlapping gold portrait and a wider castbar underneath. Compact castbars use a yellow patterned fill and a full-width dark spell-name panel below them; uninterruptible casts are grey.

The layout includes centered cooldowns, native styled nameplates, a round minimap with Blizzard's compass frame, a bottom action bar with gryphons, chat on the left and smoothly shaded overall damage meters on the right. Chat uses heavier Expressway text and a clock in the header, with Blizzard's message timestamps and unused side buttons hidden while the preset is active. The native queue-status eye sits on the minimap's upper-left edge at a compact size. Its bottom information bar separates Home and World latency with icons, followed by FPS, location and durability. It keeps Blizzard's original quest tracker and uses its authored gold colors. Global color palettes are available on the other setup presets. When the Skinning addon is enabled in the AddOn list, setup loads it and activates modern dark window skins with warm gold accents. Its two example screenshots are marked as layout references; switch to Layout to preview your selected settings. Rerunning setup creates a separate profile and preserves your previous profiles.

## Install

Supported clients: **WoW Retail 12.1.5** and **WoW Forever 1.60.1**.

1. Install **MSUF Suite** through the **CurseForge client** or **Wago client**. Choose **Beta** in CurseForge and Wago for this release. The Suite itself remains in Alpha.
2. CurseForge installs **MSUF** automatically as a required dependency. In Wago, install **MSUF 6.5 (6.50)** as well.
3. Enable the desired modules and open `/msuf` in the game.

## Alpha feedback

The Suite is in its **Alpha phase**. Features and layouts may change, and bugs are possible. Please report the client and build, MSUF and Suite versions, steps to reproduce, and any Lua errors in the [Suite issue tracker](https://github.com/Mapkov2/MSUF-Suite/issues). Screenshots help with visual issues.

## Copyright

Copyright (c) 2026 Mapko. All rights reserved. See [LICENSE.txt](https://github.com/Mapkov2/MSUF-Suite/blob/main/LICENSE.txt). Bundled third-party components retain their own terms; see [third-party notices](https://github.com/Mapkov2/MSUF-Suite/blob/main/MSUF_Suite_Skin/THIRD_PARTY_NOTICES.txt).

Keep all bundled addon folders together when installing or updating. **MSUF Suite - Locales** contains all translations and follows the menu language selected in MSUF. Disable this optional addon for English Suite text, then reload the interface. When updating from individual language addons, remove the old `MSUF_Suite_Locale_<locale>` folders.

## Development

See [architecture and validation](docs/ARCHITECTURE.md) for source ownership,
required host fixtures and the boundary between offline checks and live testing.
The addon version is declared in `MSUF_Suite/MSUF_Suite_Mainline.toc`.

Dark Raid recreates Kuro's reference layout with compact dark unit frames, class-colored names, a vertical four-member party list, five-across raid grids, square center cooldowns, two-row action bars, native nameplate styling and side-by-side damage/healing meters. Player health includes one percentage decimal; combat and healing potions, Healthstone and the learned racial sit below the frame as real cooldowns with inventory counts. A separate Darkness/Blur cooldown row with charge counts anchors above its right edge when those spells are known. The combat timer uses two-digit minutes and retains its last duration on compatible MSUF hosts. Boss buffs and debuffs sit outside their frames, with compact castbars below. Health fills are translucent while text stays bright. Missing health is neutral gray; the full-height flat blue area is the absorb shield, including at full health. Target auras sit above the frame; its thin castbar sits directly below health. The reference pull and encounter timers above the target belong to the boss mod. Havoc has eight essential cooldowns and five raid utilities, following learned spells and their replacements. The bundled host profile variant uses seven utilities in dungeons. Six selected player auras share a centered lower row; Thrill of the Fight and the target Reaver's Mark occupy the upper row. With only one unit represented, that mixed row retains its native half-row anchor. A separate native Rending Strike container covers the Mark cell while that player buff is active, matching the observed glaive sequence. A lone upper icon still retains its half-row position. Full priority behavior outside the observed sequence, custom aura artwork and exact video colors remain unverified. A compact shared battle-resurrection count and recharge timer sit inside the player frame; the 24px player castbar sits between the lower aura row and the resource bar, with elapsed / total time and a separate lavender fill. The small left-side focus frame shows only its name, with a top-right raid marker and its own castbar directly below. The separate central duplicate enemy-cast display in the reference is not included. Interruptible casts are blue and uninterruptible casts red, including the native nameplate fill. Meters show totals and per-second rates with compact K/M numbers, integer values below 1000, and controls only on hover. The bundled host profile variant changes the second meter from current healing to Overall Damage Done in dungeons, and restores it on leaving. The native bag bar stays hidden without adding DataText strips; standard bag key bindings remain available. Choose Dark Raid in the Suite setup; the installer includes a reference screenshot and preserves existing profiles.
