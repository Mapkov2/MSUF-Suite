"""Reject duplicate header declarations in the Suite's native key bindings."""

from pathlib import Path
import sys
from xml.etree import ElementTree


bindings_path = Path(sys.argv[1]) / "MSUF_Suite" / "Bindings.xml"
seen = set()
visible = hidden = 0
for binding in ElementTree.parse(bindings_path).getroot().findall("Binding"):
    header = binding.get("header")
    if header is not None:
        assert header not in seen, f"Duplicate binding header {header}: {binding.get('name')}"
        seen.add(header)
    name = binding.get("name")
    if name.startswith("MSUFSUITE_CHARACTER_FROM_"):
        hidden += 1
        assert binding.get("hidden") == "true" and f'OpenBoundCharacterTab("{name}")' in binding.text
    elif name.startswith("MSUFSUITE_CHARACTER_"):
        visible += 1
        assert binding.get("category") == "BINDING_HEADER_MSUFSUITE_CHARACTER"
        assert f'OpenBoundCharacterTab("{name}")' in binding.text
assert (visible, hidden) == (16, 3)
