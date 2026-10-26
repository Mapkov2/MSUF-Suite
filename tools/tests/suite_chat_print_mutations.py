"""Reject chat print regressions in memory, without changing the checkout."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve().as_posix()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
target = "MSUF_Suite_Chat/Messages.lua"
cases = [
    ("function P.NS.PrintChatMessage(frame, text)", "function S.PrintChatMessage(frame, text)",
     "Suite print traversed the full history"),
    ("local rendered = Format(public)", "local rendered = public",
     "stored line"),
    ("if stale or tools.format and public ~= record.prepared\n        and (public ~= record.unchanged or record.unchangedGeneration ~= formatGeneration) then", "if tools.format then",
     "nested print or echo repeated formatting"),
    ("local previous, generation, source = record.prepared, record.preparedGeneration, record.preparedSource",
     "local previous, generation, source",
     "nested print or echo repeated formatting"),
    ("record.prepared, record.preparedGeneration, record.preparedSource = previous, generation, source",
     "record.prepared, record.preparedGeneration, record.preparedSource = rendered, generation, source",
     "nested print or echo repeated formatting"),
    ("if record.ring then HistoryStore", "if record.ring and public ~= record.prepared then HistoryStore",
     "history count"),
    ("and not record.source and tools.prepare", "and tools.prepare",
     "stored line"),
    ("record and record.live and not record.wakeOnly", "record and not record.wakeOnly",
     "disabled formatter still ran"),
    ("and not record.wakeOnly and not record.source", "and not record.source",
     "combat log formatted"),
    ("if Format(rendered) ~= rendered then", 'if Format(rendered) == "" then',
     "stored line"),
    ("record.unchanged, record.unchangedGeneration = public, formatGeneration",
     "record.unchanged, record.unchangedGeneration = nil, formatGeneration",
     "unchanged print formatted twice"),
    ("or record.unchangedGeneration ~= formatGeneration", "",
     "stale identity memo survived refresh"),
    ("record.preparedGeneration ~= formatGeneration", "false",
     "stale prepared memo survived settings refresh"),
    ("record.prepared, record.preparedGeneration, record.preparedSource = rendered, formatGeneration, public",
     "record.prepared, record.preparedGeneration, record.preparedSource = rendered, nil, public",
     "nested print or echo repeated formatting"),
    ("function C.MessageRoster()\n    formatGeneration = formatGeneration + 1", "function C.MessageRoster()",
     "stale prepared memo survived roster refresh"),
    ("Format(stale and record.preparedSource or public)", "Format(public)",
     "stale prepared memo survived disabled refresh"),
    ("if stale or tools.format and public ~= record.prepared", "if tools.format and (stale or public ~= record.prepared)",
     "stale prepared memo survived disabled refresh"),
]
for before, after, expected in cases:
    script = f'''
arg = {{ {json.dumps(root)} }}
local original = loadfile
loadfile = function(path)
    if path:sub(-{len(target)}) == {json.dumps(target)} then
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        local a, z = assert(source:find({json.dumps(before)}, 1, true))
        return assert(loadstring(source:sub(1, a - 1) .. {json.dumps(after)} .. source:sub(z + 1), "@" .. path))
    end
    return original(path)
end
assert(original(arg[1] .. "/tools/tests/suite_chat_print_contract.lua"))()
'''
    run = subprocess.run([lua, "-"], input=script, cwd=root, capture_output=True, text=True, errors="replace")
    detail = (run.stderr or run.stdout).splitlines()
    assert run.returncode and expected in run.stderr, f"{before}: unexpected mutation result {run.returncode}: {detail[:1]}"
print(f"Chat prints: {len(cases)} regressions rejected without modifying source")
