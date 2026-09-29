"""The Suite's in-game notes are generated from its own release history."""

import subprocess
import sys
from pathlib import Path


root = Path(sys.argv[1])
tool = root / "tools" / "update_suite_changelog.py"
subprocess.run([sys.executable, str(tool), "--check"], cwd=root, check=True)
toc = (root / "MSUF_Suite" / "MSUF_Suite_Mainline.toc").read_text(encoding="utf-8")
assert "Core\\Changelog.lua" in toc, "Suite core does not load its release history"
print("suite_changelog_contract: ok")
