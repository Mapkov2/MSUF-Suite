"""Guard changes must be rejected by the behavioral nameplate contract."""
from pathlib import Path
import os, subprocess, sys, tempfile
root = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]).resolve()
runtime = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
contract = root / "tools/tests/suite_nameplate_name_format_contract.lua"
files = {"runtime": root / "MSUF_Suite_Nameplates/NameText.lua", "helper": root / "MSUF_Suite/Core/NameplateText.lua"}
cases = [
    ("secret restore", "runtime", "    if not S.Public(current) then\n        ForgetPlain(state)\n        return\n    end", ""),
    ("pooled identity", "runtime", "    Clear(state)\nend\n", "end\n"),
    ("deferred replay", "runtime", "M.pendingPlates[uf], state.look, state.tintRevision = true, nil, nil", "M.pendingPlates[uf], state.tintRevision = true, nil"),
    ("mapped owner", "runtime", "    if M.activeUnits[unit] ~= uf then return end", "    if not unit then return end"),
    ("side switch", "runtime", "if not look or not M.config[look.visualSide] then return end", "if not look then return end"),
    ("neutral scope", "runtime", 'if kind == "neutralNpc" then scope =', 'if kind == "enemyNpc" then scope ='),
    ("restricted color", "runtime", "(look.customColor or look.shared) and state.r", "(look.customColor or look.shared)"),
    ("shared opacity", "helper", "look.shared and look.shared.textColor.a or 1", "1"),
    ("warm work", "runtime", "    if enabled and state and state.unit == unit and state.look == look then return end", ""),
]
baseline = subprocess.run([runtime,str(contract),str(root)],cwd=root,capture_output=True,text=True)
assert baseline.returncode == 0, baseline.stderr
with tempfile.TemporaryDirectory(prefix="suite-name-format-mutations-") as temp:
    for number,(label,kind,before,after) in enumerate(cases):
        source = files[kind].read_bytes().decode("utf-8-sig").replace("\r\n", "\n")
        assert source.count(before) == 1, (label,source.count(before))
        candidate = Path(temp) / (str(number)+".lua")
        candidate.write_bytes(source.replace(before,after).encode())
        env = dict(os.environ)
        env["SUITE_NAME_FORMAT_OVERRIDE" if kind == "runtime" else "SUITE_NAME_TEXT_HELPER_OVERRIDE"] = str(candidate)
        result = subprocess.run([runtime,str(contract),str(root)],cwd=root,env=env,capture_output=True,text=True)
        assert result.returncode != 0, label+" mutation survived"
        assert "cannot open" not in result.stderr and "syntax error" not in result.stderr, label+" failed to parse"
        print("rejected "+label)
print(f"PASS {len(cases)} nameplate behavior/secret/performance mutations rejected")
