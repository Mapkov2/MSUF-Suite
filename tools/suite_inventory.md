# Suite feature inventory

Run `python tools/suite_inventory_diff.py` to compare the working tree with the
tracked pre-program snapshot from `29ca197`. The normal check needs Python 3.12
and Lua 5.1 (`MSUF_LUA51` overrides the default path), but no git history or sibling
checkout. `--diff` lists all removals and additions. Every unapproved removal,
invalid allowlist entry, stale exception, or extraction error fails the check.
`python tools/run_suite_tests.py` runs the gate after the contracts and includes
its result in the final pass/fail total, with one inventory summary line. The
`inventory` name filter selects both the tool contracts and the real gate.

`--freeze REV` rebuilds the snapshot using the current extractor against that
commit's addon sources. It does not change or prune exceptions. Review a baseline
change explicitly: advancing it can hide a loss. `--verify-baseline` re-extracts
the recorded commit and requires exact equality. If the commit is unavailable,
verification reports SKIP; the normal inventory gate still runs from JSON.

The older `BEFORE_ROOT [AFTER_ROOT] --client retail|forever|both` mode remains a
strict comparison of two supplied trees. It has no historical exceptions; use
the default frozen check for the audited pre-program comparison.

## Surface and boundaries

- The Lua helper loads the catalog's TOC segment, finalizes it and records both
  clients separately: module IDs, page/addon routes, every rule key, typed default,
  indexed choice, label, section ID/title, kind, visibility, limits and step.
  Indexed choices detect reorderings as well as deletions. Generated rules and
  bindings are evaluated, including hidden settings. Labels remain tied to their
  owner so identical text elsewhere cannot hide a loss.
- English keys use the same `Extractor` and `skin_strings` pass as
  `suite_locale_tool.py extract`; translation coverage is irrelevant here and no
  host locale files are read. This includes the skin's enUS source table.
- Source declarations cover slash aliases, XML bindings, public `S.*` assignments
  and function definitions, saved-variable TOC roots and their named top-level
  fields, including direct aliases, literal constructors and root-key constants.
  Catalog defaults cover the Suite profile's setting leaves. Arbitrary runtime
  data keys (GUIDs, character names, chat tabs) are not fixed field names.
- Mover registrations include the skin's direct registration and expand known
  dynamic families: action bars, damage windows, CDM slots, DataTexts bars and
  threat windows. Bounds come from source/catalog values. An unknown mover or
  slash registration expression aborts extraction instead of silently omitting
  it. When introducing a different registration idiom, extend the extractor and
  its synthetic tests in the same change.
- This is a static interface-loss gate, not a proof that a setting still has a
  working implementation. Unchanged declarations cannot establish live visuals,
  taint safety, runtime paths or third-party use of an exported function.

## Exceptions and evidence at the package base

Each `removed` entry requires `category`, `item`, `basis`, `evidence`, `reason`,
and an ISO date. Only `*` is a wildcard; other characters are literal. Basis is
`migration`, `owner`, `dead`, or `moved`. Exceptions are category-specific and each
entry must cover at least one actual removal. Evidence is reviewed text, retained
in shallow checkouts; the normal gate does not treat it as executable code or
fetch external sources.

All 14 removals between `29ca197` and `a7aee25` have exact exceptions:

| Category / old item | Replacement or proof | Commit |
| --- | --- | --- |
| Labels: retail and forever `minimap.infoClockDate`, Show date (day-month-year) | Same setting, Show date; localized short date | `91e00e5` |
| Locale: Show date (day-month-year) | Show date | `91e00e5` |
| Locale: Current spec: (trailing space) | Current spec: %s | `91e00e5` |
| Locale: Loot: (trailing space) | Loot: %s | `91e00e5` |
| Locale: Extended | %s (Extended) | `91e00e5` |
| Locale: World boss | %s (World boss) | `91e00e5` |
| Locale: Tier | Tier %d | `91e00e5` |
| Locale: Keystone level | Keystone level %d | `91e00e5` |
| Locale: Equipment slot | Equipment slot %d | `652cc70` |
| Locale: enabled | %d / %d enabled | `7f9330b` |
| Locale: restores | Off - restores %s | `f34d0d4` |
| Export: S.ActionBarPreviewInfo | Only definition in parent product tree; active preview uses P.ActionBarGrid | `d432072` |
| Export: S.AddSpellFromCursor | Only definition in parent product tree | `996ebf4` |

The history search used `git log -S` with each quoted old Lua literal or export
name, followed by the removing patch. `git grep` at each export removal's parent
found only its definition in product sources. Both removal commits also record
their cross-addon/string-dispatch audits; those historical audits do not prove
that unknown third-party addons never used the exports. The full hashes and
source paths are in the allowlist. No setting key or stored data was renamed by
these exceptions, so none needs a saved-data migration.

## Tool verification

`python tools/tests/suite_inventory_tool_contract.py` uses synthetic sources and
snapshots, including removal failure, allowed removal, addition, stale and invalid
exceptions, literal wildcard handling, alias extraction, bounds, catalog errors,
history-free operation and baseline tampering. Add `--mutations` to run intentional
guard/extraction failures in a disposable temporary copy. Product files are never
mutated by these tests.
