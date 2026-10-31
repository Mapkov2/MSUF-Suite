# Suite startup loading

The core loads Platform first. For a translated MSUF menu language, Platform
asks the native addon loader for the single optional `MSUF_Suite_Locales` addon.
English and unknown locale values load none. Its TOC references all ten unchanged
canonical catalogs in `MSUF_Suite/Locales`; each returns before registration or
table population unless its locale matches MSUF's finalized `LOCALE`.

Locales requires MidnightSimpleUnitFrames, rather than the Suite core which is
still loading. This avoids a dependency cycle. The selected catalog finishes
before Suite captures translations for bindings, catalog rows or runtime labels.
Selection follows MSUF's menu language, independently of the WoW client locale.
Older hosts without `RegisterLocale` continue to fill `MSUF.L`. Existing host
translations win; a nil or English identity entry may be filled, as before.

Load completion follows `Suite.Client.IsAddOnLoaded`, including its authoritative
second return on Forever. Disabled Locales is an intentional English fallback
and produces no warning. Missing or outdated Locales retains the existing load
diagnostic and also falls back to English. The host locale and translation table
are preserved; Suite text, bindings and skin use the English fallback without
preventing module startup. Shared MSUF menu chrome follows the host language.
After updating, remove the old `MSUF_Suite_Locale_<locale>` addon folders.

This layout has one installed-addon metadata slot instead of ten, so existing
memory readers make nine fewer native reads per sample or tooltip. The loaded
Locales addon owns its native memory row; the 30-second memory cache is unchanged.
Disabled Locales and English skip all Suite catalogs. When Locales loads, all ten
files are compiled; only the selected catalog populates translations. The bundle
does not claim a compiler or login-time improvement over individual language addons.
Package validation requires the combined TOC and all ten canonical catalogs.

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
- `suite_locale_loading_manifest_contract.py`: the combined addon and all ten catalogs,
  dependency/load-order safety, version/reference integrity and missing-file
  rejection and inactive-locale guards.
- `suite_locale_memory_footprint_contract.lua`: unchanged memory totals/rows and
  30-second caching for one unloaded addon; the loaded addon remains reported.
- Existing locale coverage, UI/search, profile/variant/import, startup/skin,
  packaging and the complete Suite gate remain required.

Native VM, calls, compiler CPU and allocation measurements are offline evidence.
They do not establish WoW login seconds, native frame cost, combat/taint or visual
behavior. No deferred startup work, polling or new timer is introduced.
