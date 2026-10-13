"""Real skin loaders: independent long-term lifecycle and ownership regressions."""
import os
from pathlib import Path
import subprocess
import sys


def main():
    root = Path(sys.argv[1]).resolve()
    helper = Path(__file__).with_name("longterm_skin_cases.lua")
    lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
    reference = root.parent / "MapkoSkin"
    legacy = root.parent / "_repo_backups" / "6.22"
    # Same standalone/host arguments as the existing absorption runner.
    assert (reference / "tests/MapkoSkin/run.lua").is_file(), "MapkoSkin test reference missing"
    assert legacy.is_dir(), "legacy host missing"
    cases = [("public-fault", None), ("archive", None), ("level-help", None)]
    cases += [(case, host) for case in ("public-partial", "micro-preview", "checkmarks")
              for host in (legacy, "Forever")]
    cases += [("stats", legacy), ("model", "Forever")]
    cases += [("builder-" + case, None) for case in (
        "normal-embedded", "normal-window", "recovery-newpage", "context",
        "retry-embedded", "retry-window", "retry-direct-mode", "nested-context")]
    wanted = sys.argv[2] if len(sys.argv) > 2 else ""
    failures = []
    selected = [(case, host) for case, host in cases if wanted in case]
    assert selected, "unknown case filter"
    for case, host in selected:
        script = helper.with_name("longterm_level_help.lua") if case == "level-help" else helper
        if case.startswith("builder-"):
            script = helper.with_name("longterm_skin_builder.lua")
        command = [lua, str(script), str(root), case.removeprefix("builder-")]
        if host is not None:
            command += [str(reference), str(host)]
        run = subprocess.run(command, cwd=root, capture_output=True, text=True, errors="replace")
        label = case + ("/Forever" if host == "Forever" else "/Mainline" if host is not None else "")
        if run.returncode:
            failures.append(label)
            print("FAIL " + label)
            print("\n".join((run.stdout + run.stderr).strip().splitlines()[-8:]))
        else:
            print("ok   " + label)
    print(f"Long-term skin: {len(selected) - len(failures)} passed, {len(failures)} failed")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
