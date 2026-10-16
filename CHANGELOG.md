# MSUF Suite Changelog

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
