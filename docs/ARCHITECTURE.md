# Architecture and validation

The Suite loads after Midnight Simple Unit Frames. `MSUF_Suite` owns shared
configuration and the module catalog; feature addons and the skin engine load
their runtime through their own manifests. `MSUF_Suite_Options` also depends on
the host's load-on-demand Options addon. English text is the fallback, and a
selected locale is supplied by one locale companion addon.

## Ownership

- `Core/Platform.lua` owns public-value readers and the shared safety primitives.
  Restricted values must reach supported native setters without Lua comparisons.
- `Core/Suite.lua` owns module configuration and lifecycle. Catalog files define
  defaults, validation rules and menu metadata; feature runtimes consume those
  definitions instead of maintaining a second settings schema.
- `Core/Profiles.lua`, `ProfileIO.lua` and `ProfileVariants.lua` own profile
  mutation, transfer and overlays. A rejected mutation must preserve the active
  effective configuration, and history restore must update the runtime as well
  as the saved profile.
- `Core/HostBridge.lua` and `HostBridgeMenu.lua` provide the shared boundary for
  host settings and Menu2 services, including late Options loading. New callers
  belong here. Existing compatibility reads in platform, font and nameplate
  helpers still need case-by-case migration; moving them must preserve their
  optional-provider behavior and fallback.
- `MSUF_Suite_Options/Menu` owns shared navigation, metadata and controls;
  `Pages` owns feature-specific layout. Search and resets use the same settings
  definitions and keep saved source and choice identities stable.

## Adventure Planner

`MSUF_Suite_AdventurePlanner` is an independent load-on-demand feature addon.
Core owns its `planningTools` catalog and saved module settings; the addon
requires only Core and the shared Modules runtime. It retains the existing
`RootDB.suitePlanning`, `CharacterData("planning")` and run-summary storage.
Moving code never introduces another SavedVariables owner or resets records.
Shared loadout reading lives in `Modules/LoadoutSnapshot.lua`; optional group
finder operations are accessed through the active tool instance.

World lifecycle listeners remain armed during combat but perform no native
state reads there. Leaving the world cancels pending captures and updates only
last-seen time; gold and equipped item level come from live updates. This
avoids persisting temporary teardown zeroes while retaining a real zero balance.
Window and accordion animation groups stop on hide; resizing uses a transient
mouse-held driver. Reduced motion bypasses transitions.

## Embedded skin

`MSUF_Suite_Skin/Core` owns the database, theme, safety, registry and public API.
`Rendering` owns reusable surfaces, geometry, controls and motion. `Adapters`
connect those operations to individual Blizzard surfaces. The TOC specifies
their dependency order; an adapter must not introduce another owner for a shared
window, font, history transaction or animation.

Native hooks persist after module disable. Their callbacks must respect current
ownership and enabled state; finite continuations and animations must release or
cancel their pending work. Protected geometry and deferred work follow the
combat gate. Event-derived combat state covers the transition before native
lockdown becomes true. A hidden or inactive surface should not repeatedly scan,
create controls, or retain a refresh driver without a pending obligation.

The embedded engine retains its legacy public API for integrations. Host access
still goes through the Suite bridge. A compatibility adapter must preserve old
host behavior while keeping the normal current-host route explicit.

## Offline validation

Run `python tools/run_suite_tests.py` with Python 3.12+ and Lua 5.1. Set
`MSUF_LUA51` to the Lua executable when using another machine. A filter is an
optional positional argument; an empty selection is a failure. Filters execute
only their selected contracts, so a filtered success is not a full Suite pass.

The integration contracts currently require these sibling source fixtures:

| Fixture | Purpose |
| --- | --- |
| `MidnightSimpleUnitFrames` | Supported production host |
| `MidnightSimpleUnitFrames-7.0` | Development host and real renderer integration |
| `_repo_backups/6.22` | Frozen legacy host compatibility |
| `MapkoSkin` | Legacy skin migration and compatibility |

Record exact host revisions and any working-tree differences with a result.
Those fixtures are test dependencies and are not included in a Suite release.
The current runner depends on this local layout; the repository does not yet
provide a self-contained CI job for the complete host matrix.

The full runner includes contract tests, the quality ratchet and feature
inventory. Preserve frozen performance limits and compare native calls as well
as Lua instructions and allocation. A behavior correction needs a failing
original case and a successful corrected case. The package builder separately
checks selected addon dependencies, manifests and load references.

## Live acceptance

Offline tests model client behavior. Before release, exercise the changed areas
in Retail and Forever, including combat entry/exit, reload, profile changes,
protected UI actions, visibility and ownership release. Inspect Lua errors and
taint logs. Compare representative runtime CPU and allocation measurements on
the exact same build and scenario before asserting a performance improvement.
An installed or compiled package alone does not establish those results.
