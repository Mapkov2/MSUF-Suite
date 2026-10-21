# Suite startup loading

The core loads Platform first. Platform asks the native addon loader for exactly one
`MSUF_Suite_Locale_<locale>` companion, selected from MSUF's finalized `LOCALE`.
English and unknown locale values load none. The ten unchanged canonical catalogs
remain in `MSUF_Suite/Locales`; each companion TOC references just its own catalog.

Companions require MidnightSimpleUnitFrames, rather than the Suite core which is
still loading. This avoids a dependency cycle. The catalog finishes before the
Suite captures translations for bindings, catalog rows or runtime labels. The
selection does not use the WoW client locale. On an older host without
`RegisterLocale`, catalogs continue to fill `MSUF.L`. Existing host translations
win; a nil or English identity entry may be filled, exactly as before.

Load completion follows `Suite.Client.IsAddOnLoaded`, including its authoritative
second return value on Forever. An absent, disabled or outdated companion is
reported through the existing translated load-error format. It never changes the
host locale, marks `startupError`, suppresses setup or prevents module startup.
All ten companion TOCs and catalogs are mandatory in package validation.

The ten companion folders add ten installed-addon metadata slots. Existing memory
readers therefore perform ten additional native memory reads per sample/tooltip;
the shared sample keeps its 30-second cache. Unloaded companions contribute zero
and no tooltip rows; the selected loaded pack has its own honest memory row. The
memory providers themselves and their update cadence are unchanged. This bounded
runtime cost is separate from the startup compilation savings.

The profile database still copies every stored profile before validation publishes
the new root. `CopyValue` preserves cycles, shared references, table keys, optional
`seen`, primitive/function identity and the previous no-metatable-copy behavior.
Only tables recurse; primitive members no longer call another Lua function. A
table root has one extra helper call, accepted only with the measured aggregate
profile-copy budget; primitive roots retain their direct return.

Regression checks are auto-discovered by `tools/run_suite_tests.py`:

- `suite_copy_startup_budget_contract.lua`: full graph semantics; frozen original
  algorithm versus current provider, at least 5% fewer VM instructions, unchanged
  native type/pairs counts and at most the existing 2% allocation tolerance.
- `suite_locale_loader_contract.lua`: all 12 language choices on both client
  models and old/new hosts; custom client/menu language combinations, preloaded
  catalogs, nested load notification, combat/manual loading and diagnosed errors;
  complete raw-value parity and actual Core/profile/installer boots.
- `suite_locale_loading_manifest_contract.py`: all ten catalogs and companions,
  dependency/load-order safety, version/reference integrity and missing-file
  rejection, plus reduced selected-catalog compilation input.
- `suite_locale_memory_footprint_contract.lua`: unchanged memory totals/rows and
  30-second caching for ten unloaded packs; the selected pack remains reported.
- Existing locale coverage, UI/search, profile/variant/import, startup/skin,
  packaging and the complete Suite gate remain required.

Native VM, calls, compiler CPU and allocation measurements are offline evidence.
They do not establish WoW login seconds, native frame cost, combat/taint or visual
behavior. No deferred startup work, polling or new timer is introduced.
