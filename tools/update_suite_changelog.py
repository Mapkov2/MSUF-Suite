"""Build the Suite-owned in-game release history from CHANGELOG.md.

Run without arguments after editing the changelog, or use --check in gates.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "CHANGELOG.md"
OUTPUT = ROOT / "MSUF_Suite" / "Core" / "Changelog.lua"
TOC = ROOT / "MSUF_Suite" / "MSUF_Suite_Mainline.toc"
LINK_FIELDS = ("pageKey", "sectionId", "controlId", "settingKey", "prepareKind", "prepareValue", "label",
               "client", "fallbackSectionId")


def lua_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def parse_link(line):
    marker = re.fullmatch(r"<!-- msuf-menu-link: (.+) -->", line)
    if not marker:
        raise ValueError(f"Invalid Suite menu link: {line}")
    link = json.loads(marker.group(1))
    if not isinstance(link, dict) or any(
        field not in LINK_FIELDS or not isinstance(value, str) or not value.strip()
        for field, value in link.items()
    ) or not {"pageKey", "sectionId", "label"} <= link.keys():
        raise ValueError(f"Invalid Suite menu link fields: {line}")
    if ("client" in link or "fallbackSectionId" in link) and (
        link.get("client") not in ("forever", "retail") or "fallbackSectionId" not in link
    ):
        raise ValueError(f"A client-specific Suite link needs a fallback section: {line}")
    return link


def parse(source):
    entries = []
    previous_bullet = None
    for line in source.splitlines():
        marker = line.lstrip()
        if marker.startswith("<!-- msuf-menu-link"):
            if previous_bullet is None:
                raise ValueError("A Suite menu link must immediately follow its bullet")
            previous_bullet["link"] = parse_link(marker)
            previous_bullet = None
            continue
        previous_bullet = None
        release = re.fullmatch(r"##\s+(.+?)\s+-\s+(\d{4}-\d{2}-\d{2})\s*", line)
        if release:
            entries.append({"version": release.group(1), "date": release.group(2), "sections": []})
            continue
        if line.startswith("## "):
            raise ValueError(f"Invalid release heading: {line}")
        if not entries:
            continue
        section = re.fullmatch(r"###\s+(.+?)\s*", line)
        if section:
            entries[-1]["sections"].append({"title": section.group(1), "bullets": []})
            continue
        if line.startswith("- "):
            sections = entries[-1]["sections"]
            if not sections:
                sections.append({"title": "Changes", "bullets": []})
            previous_bullet = {"text": line[2:].strip()}
            sections[-1]["bullets"].append(previous_bullet)
    if not entries or any(not section["bullets"] for entry in entries for section in entry["sections"]):
        raise ValueError("Suite changelog needs releases with nonempty sections")
    if any(not entry["sections"] for entry in entries):
        raise ValueError("Every Suite release needs at least one bullet")
    versions = [entry["version"] for entry in entries]
    if len(versions) != len(set(versions)):
        raise ValueError("Duplicate Suite release version")
    if "Unreleased" in versions and versions[0] != "Unreleased":
        raise ValueError("Place the Unreleased Suite entry first")
    if versions[0] == "Unreleased" and any(
        "link" not in bullet for section in entries[0]["sections"] for bullet in section["bullets"]
    ):
        raise ValueError("Every Unreleased Suite changelog bullet needs a menu link")
    return entries


def render_bullet(bullet):
    text = lua_string(bullet["text"])
    link = bullet.get("link")
    if not link:
        return f"                    {text},"
    target = {key: value for key, value in link.items() if key not in ("client", "fallbackSectionId")}
    if "controlId" not in target or "client" in link:
        # The MSUF changelog requires a control ID. Suite Options resolves this
        # ID to a setting or section through the host's existing search API.
        target["controlId"] = "|".join(("msufsuite.changelog", link.get("client", ""),
                                       link.get("fallbackSectionId", ""), link.get("controlId", "")))
    fields = [f"{field} = {lua_string(target[field])}" for field in LINK_FIELDS if field in target]
    return f'                    {{ text = {text}, link = {{ {", ".join(fields)} }} }},'


def version_matches(toc_version, entries):
    def normalize(version):
        return re.sub(r"[^a-z0-9]", "", version.lower())

    candidates = entries[1:] if entries[0]["version"] == "Unreleased" else entries[:1]
    return any(normalize(toc_version) == normalize(entry["version"]) for entry in candidates)


def render(source):
    entries = parse(source)
    toc = TOC.read_text(encoding="utf-8-sig")
    version = re.search(r"^## Version:\s*(\S+)\s*$", toc, re.MULTILINE)
    if not version or not version_matches(version.group(1), entries):
        raise ValueError("The Suite changelog must include the core TOC version")
    digest = hashlib.sha256(source.encode("utf-8")).hexdigest().upper()
    lines = [
        "-- Generated by tools/update_suite_changelog.py from CHANGELOG.md. Do not edit directly.",
        "local _, Suite = ...",
        "Suite.Changelog = {",
        f"    sourceSha256 = {lua_string(digest)},",
        f"    currentVersion = {lua_string(entries[0]['version'])},",
        "    entries = {",
    ]
    for entry in entries:
        lines.extend([
            "        {",
            f"            version = {lua_string(entry['version'])},",
            f"            date = {lua_string(entry['date'])},",
            "            sections = {",
        ])
        for section in entry["sections"]:
            lines.append(f"                {{ title = {lua_string(section['title'])}, bullets = {{")
            lines.extend(render_bullet(bullet) for bullet in section["bullets"])
            lines.append("                } },")
        lines.extend(["            },", "        },"])
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail when the bundled Lua is stale")
    args = parser.parse_args()
    source = SOURCE.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    expected = render(source)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8").replace("\r\n", "\n") != expected:
            parser.error("MSUF_Suite/Core/Changelog.lua is stale; run tools/update_suite_changelog.py")
        print("Suite changelog is current")
    else:
        OUTPUT.write_text(expected, encoding="utf-8", newline="\n")
        print(f"Updated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
