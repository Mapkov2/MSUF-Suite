"""Reject preview regressions without modifying the working checkout."""
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
lua = os.environ.get('MSUF_LUA51', r'C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe')
test = root / 'tools/tests/suite_buff_reminders_preview_contract.lua'
for case, expected in {
    'buffer': 'preview ignored its isolated entry buffer',
    'effects': 'preview ignored runtime category border effects',
    'count': 'preview ignored runtime count typography',
    'geometry': 'preview ignored configured icon size',
    'cached': 'appearance refresh rebuilt the bag selection',
}.items():
    result = subprocess.run([lua, str(test), str(root), case], cwd=root,
                            capture_output=True, text=True, errors='replace')
    assert result.returncode != 0 and expected in result.stderr, f'{case}: unexpected result\n{result.stderr}'
print('Buff reminder preview: 5 runtime mutations rejected')
