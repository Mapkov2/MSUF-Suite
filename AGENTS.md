# MSUF Suite Workflow

- This directory, `C:\MSUF Beta Branch\MSUF-Suite`, is the sole active Suite source and publication checkout on this host.
- Confirm `git rev-parse --show-toplevel` resolves here and `origin` is `https://github.com/Mapkov2/MSUF-Suite.git` before making Suite changes or publishing.
- Work in this checkout directly. Do not create a second `MSUF-Suite-Private` copy or sync between Suite source and publication folders.
- Preserve unrelated local changes and SavedVariables. Run `python tools/run_suite_tests.py` for Suite source changes; offline contracts do not prove live WoW behavior.
- Commit, push, release, or build a new Perfy artifact only when the user explicitly requests that action.
- Quality, cleanup and bug-fix work follows the local plan `../AGENTS_QUALITY.md` (next to this checkout, not part of the repo): rules, bug list, phases, exit criteria and status tracker.
