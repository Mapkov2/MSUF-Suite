# MSUF Suite

**MSUF Suite Alpha** brings modular interface tools to World of Warcraft Retail and WoW Forever. Open `/msuf` to configure the Suite and choose the modules for your layout.

**Midnight Simple Unit Frames (MSUF) is required. This Suite alpha is compatible with MSUF 6.5 (release 6.50).** MSUF is configured as a Required Dependency on CurseForge and is installed automatically with the Suite. When using Wago, install MSUF through the Wago client as well.

## Modules

- **Action Bars** - Layout and appearance settings for your action bars.
- **Cooldown Manager** - Cooldown, buff, and buff bar displays.
- **Buff Reminders** - Reminders for missing buffs and consumables.
- **Bags & Bank** - Inventory and bank views.
- **Chat** - Chat styling, history, fading, and unread tab indicators.
- **Minimap** - Minimap layouts, appearance, and shortcuts.
- **DataTexts** - Configurable information bars.
- **Damage Meter** - Damage Meter windows, display options, and previews.
- **Nameplates** - Styling for Blizzard's native nameplates.
- **Adventure Planner** - A separate load-on-demand addon for character progress, lockouts, keystones, preparation and personal notes. Open `/plan`; runtime loads only when enabled.
- **Quality of Life** - Group and dungeon tools, encounter information, death alerts, incoming combat text, and reminders.
- **Skinning** - Interface window appearance and controls, with short hover, click, selection, focus, opening and disclosure animations on Suite-owned artwork. Blizzard AddOn-list groups animate their arrows and visible row transitions, with brief clipped visual copies for collapsing children. Menu page changes and completed search/filter results fade in, and palette changes blend owned backgrounds and borders. Modern and legacy dropdowns can dim their skinned window beneath the popup. Blizzard Settings pages, native tabs, Suite dialogs and AceGUI/AceConfig menus share these transitions. Supported native ScrollBoxes and modern scrollbars use optional smooth scrolling with immediate thumb dragging; older ScrollFrames use a short visual easing of their native offset. The Suite menu-animation, smooth-scrolling and reduced-motion switches also govern the connected MSUF 7.0 menu. Custom addons can adopt the same behavior through the scoped RegisterMenu/AnimateContent API. Configure Menu animations, Smooth scrolling, Reduced motion and Dim background for dropdowns under Corners and hover.

Modules can be enabled individually. The Suite includes shared profiles, setup presets, and previews in the MSUF options menu.

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
