"""Reject coverage regressions without editing the working checkout."""
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
lua = os.environ.get('MSUF_LUA51', r'C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe')
test = root / 'tools/tests/suite_buff_reminders_raid_contract.lua'
for case, expected in {
    'selection': 'overview took personal slots or wrong client buffs',
    'delta': 'one changed buff should read one member once',
    'hidden': 'hidden first-show state applied a delta or read native auras',
    'combat': 'last provider leaving in combat stayed in the overview',
    'reshow': 'returning provider icon stayed hidden',
    'preview': 'solo preview did not show supported sample buffs without aura reads',
}.items():
    result = subprocess.run([lua, str(test), str(root), case], cwd=root,
                            capture_output=True, text=True, errors='replace')
    assert result.returncode != 0 and expected in result.stderr, f'{case}: unexpected result\n{result.stderr}'
print('Raid coverage: six runtime mutations rejected')
