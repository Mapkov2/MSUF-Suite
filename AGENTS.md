# MSUF Suite Workflow

- This directory, `C:\MSUF Beta Branch\MSUF-Suite`, is the sole active Suite source and publication checkout on this host.
- Confirm `git rev-parse --show-toplevel` resolves here and `origin` is `https://github.com/Mapkov2/MSUF-Suite.git` before making Suite changes or publishing.
- Work in this checkout directly. Do not create a second `MSUF-Suite-Private` copy or sync between Suite source and publication folders.
- Preserve unrelated local changes and SavedVariables. Run `python tools/run_suite_tests.py` for Suite source changes; offline contracts do not prove live WoW behavior.
- Commit, push, release, or build a new Perfy artifact only when the user explicitly requests that action.
- Quality, cleanup and bug-fix work follows the local plan `../AGENTS_QUALITY.md` (next to this checkout, not part of the repo): rules, bug list, phases, exit criteria and status tracker.

## Durable rules (quality program, 2026-10-03)

Each rule exists because breaking it caused a real defect.

- **Clients:** Retail (12.1+) and WoW Forever only. Never use the combat log (`COMBAT_LOG_EVENT_UNFILTERED`) on these clients.
- **Error handling:** no `pcall`/`xpcall`. Boundaries go through `Safety.Dispatch`, which uses `securecallfunction`.
  - `securecallfunction` takes a function, never a callable table. Pass `job:EventFunction()`, not the job.
  - `Context:Event` accepts a job and converts it.
- **Secrets:** use `Suite.IsSecret` / `NS.IsSecret` first, before any compare, arithmetic, table-key lookup or truth test. Secrets only flow into C sinks.
- **Combat edge:** at `PLAYER_REGEN_DISABLED`, `InCombatLockdown()` is still false. Refusals use `NS.InCombat`; protected-write guards keep their own owners.
- **Blizzard frames and tables:** never write to them; `HookScript` is fine. Never write `StaticPopupDialogs`. Confirmations and text prompts use Blizzard's generic dialogs through `S.Confirm` / `P.Confirm` / `P.AskText` (keyed: one open question per key).
- **Host coupling:** the Suite talks to MSUF only through `MSUF_Suite/Core/HostBridge.lua`.
  - It uses host API v1 (`MSUF_HostAPI`, Menu2 page-reset providers) when the host has it, and the unchanged legacy path otherwise.
  - On v1 the Suite never writes `MSUF_DB` itself.
  - The contract is in `../HOST_API_SPEC.md`.
  - Compatibility must hold in all four old/new host × old/new Suite combinations.
- **Chat colours:** the ledger is a per-category state machine, documented in the header of `MSUF_Suite/Integrations/MapkoSkin.lua`.
  - Ownership is never inferred from colour equality.
  - An edit that ends where it started (for example a colour picker Cancel) is no change.
  - Recovery is the explicit "Restore chat colors" action.
  - `suite_skin_chat_color_exploration_contract.lua` checks the invariants over thousands of event sequences; keep it green.
- **Movers:** register only through the controller hook, enforced by `suite_mover_registration_contract.py`.
- **Performance:** change only what a Perfy trace measured. Budgets count VM instructions and native calls, because native cost is invisible to instruction counts. Record accepted trades in the commit and the test.
- **Gates in `run_suite_tests.py`:**
  - the structure gate (810-line files, 72-line functions);
  - `tools/quality_ratchet.py`: size metrics may grow up to their limit; defect metrics fail on +1; run `--update` after merges;
  - the frozen feature inventory `tools/suite_inventory_diff.py`: every removal needs an allowlist entry with evidence; never delete a feature to pass it;
  - `tools/suite_locale_tool.py verify`.
- **Locales:**
  - Translated text is a whole-sentence format key.
  - Edit locale files with Python, never PowerShell.
  - `MSUF_Suite/Locales/*.lua` merge with `merge=union`. After a merge, run `suite_locale_tool.py verify`: a union can re-add strings another branch removed.
- **Cross-review:** every change set gets an independent review with red-without-fix tests before it is merged. Fixes go back to the author of the change.
