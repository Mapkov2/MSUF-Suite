"""Run UI regressions with in-memory source mutations; the checkout stays intact."""
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
lua = os.environ.get('MSUF_LUA51', r'C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe')
test = root / 'tools/tests/suite_menu_ux_contract.lua'
mutations = {
    'exactTab': 'search left the target in a hidden tab',
    'narrowTabs': 'narrow host must use a dropdown',
    'duplicate': 'leading zero bypassed duplicate validation',
    'combat': 'composer wrote settings in combat',
    'inheritance': 'global inheritance changed another reminder type',
    'inlineQoL': 'QoL details stayed below the whole feature list',
    'lazyQoL': "attempt to index local 'record'",
    'itemSearch': 'item search left the consumable input hidden',
    'filteredSearch': 'search could not reveal a filtered feature without details',
    'filterTitle': 'QoL filter overlaps the section title',
    'copyWrap': 'wrapped summary overlaps the footer',
    'meterDefault': 'damage meter hid general settings on first open',
    'reminderRelease': 'hidden reminder preview did not release its renderer',
    'reminderScale': 'reminder preview shrank the native icons to a fixed height',
    'reminderIdle': 'hidden reminder preview kept native listeners',
}
for mutation, expected in mutations.items():
    run = subprocess.run([lua, str(test), str(root), 'Mainline', mutation], cwd=root,
                         capture_output=True, text=True, errors='replace')
    assert run.returncode != 0, f'{mutation}: the behavior test accepted the regression'
    assert expected in run.stderr, f'{mutation}: failed for an unexpected reason:\n{run.stderr}'
print(f'Suite menu UX: {len(mutations)} source mutations rejected without editing product files')
