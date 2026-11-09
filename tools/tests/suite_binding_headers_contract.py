"""Reject duplicate header declarations in the Suite's native key bindings."""

from pathlib import Path
import sys
from xml.etree import ElementTree


bindings_path = Path(sys.argv[1]) / "MSUF_Suite" / "Bindings.xml"
seen = set()
for binding in ElementTree.parse(bindings_path).getroot().findall("Binding"):
    header = binding.get("header")
    if header is not None:
        assert header not in seen, f"Duplicate binding header {header}: {binding.get('name')}"
        seen.add(header)
