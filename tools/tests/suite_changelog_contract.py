"""The Suite's in-game notes are generated from its own release history."""

import subprocess
import sys
from pathlib import Path


root = Path(sys.argv[1])
tool = root / "tools" / "update_suite_changelog.py"
subprocess.run([sys.executable, str(tool), "--check"], cwd=root, check=True)
toc = (root / "MSUF_Suite" / "MSUF_Suite_Mainline.toc").read_text(encoding="utf-8")
options = (root / "MSUF_Suite_Options" / "MSUF_Suite_Options_Mainline.toc").read_text(encoding="utf-8")
# The release history is menu data: it loads with the options addon, not at login.
assert "Changelog.lua" not in toc, "Suite core loads its release history at login"
assert "Menu\\ChangelogData.lua" in options, "Suite options do not load the release history"
print("suite_changelog_contract: ok")
