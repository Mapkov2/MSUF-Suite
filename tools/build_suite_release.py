"""Build the tracked Suite addons and Alpha upload metadata without publishing."""

import argparse
import hashlib
import json
import posixpath
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def tracked_files(root):
    result = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True)
    return sorted(path.decode("utf-8") for path in result.stdout.split(b"\0") if path)


def field(content, name):
    values = re.findall(r"^## " + re.escape(name) + r":\s*([^\r\n]+)", content, re.MULTILINE)
    if len(values) != 1:
        raise ValueError(f"Expected one TOC {name} field")
    return values[0].strip()


def validate_addons(root, files, version):
    addons = sorted({path.split("/")[0] for path in files if path.startswith("MSUF_Suite/")
                     or path.startswith("MSUF_Suite_")})
    dependencies = {}
    for addon in addons:
        tocs = [path for path in files if path.startswith(addon + "/") and path.endswith(".toc")]
        if tocs != [f"{addon}/{addon}_Mainline.toc"]:
            raise ValueError(f"Unexpected client manifests for {addon}: {tocs}")
        content = (root / tocs[0]).read_text(encoding="utf-8-sig")
        if field(content, "Version") != version:
            raise ValueError(f"Mixed release version in {tocs[0]}")
        dependencies[addon] = [value.strip() for value in field(content, "Dependencies").split(",")]
        interfaces = {value.strip() for value in field(content, "Interface").split(",")}
        if not {"120105", "16001"}.issubset(interfaces):
            raise ValueError(f"Retail 12.1.5 or Forever interface is missing in {tocs[0]}")
    if dependencies.get("MSUF_Suite") != ["MidnightSimpleUnitFrames"]:
        raise ValueError("MSUF must be the Suite core's required dependency")
    if "MidnightSimpleUnitFrames_Options" not in dependencies.get("MSUF_Suite_Options", []):
        raise ValueError("Suite Options must require MSUF Options")
    for addon in addons:
        pending, seen = [addon], set()
        while pending:
            name = pending.pop()
            if name not in seen:
                seen.add(name)
                pending.extend(dependencies.get(name, []))
        if "MidnightSimpleUnitFrames" not in seen:
            raise ValueError(f"{addon} can load without the required MSUF host")
        unknown = seen.difference(addons, {"MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options"})
        if unknown:
            raise ValueError(f"Missing required addon dependencies: {sorted(unknown)}")
    return addons


def validate_payload(payload):
    extensions = {".lua", ".xml", ".toc", ".tga", ".blp", ".png", ".jpg", ".jpeg", ".ttf", ".otf", ".ogg", ".wav", ".mp3"}
    notices = {"LICENSE.txt", "THIRD_PARTY_NOTICES.txt"}
    for path in payload:
        parts = Path(path).parts
        if any(part.startswith(".") or part.lower() in {"tests", "tools", "savedvariables", "perfy", "dist"} for part in parts):
            raise ValueError(f"Local or private artifact in addon payload: {path}")
        if Path(path).suffix.lower() not in extensions and Path(path).name not in notices and path != "MSUF_Suite/README.md":
            raise ValueError(f"Unreviewed release payload type: {path}")
        if Path(path).name.lower() in {"perfy.lua", "!!!perfy.lua"}:
            raise ValueError(f"Local diagnostic artifact in addon payload: {path}")
    for path, content in payload.items():
        if path.endswith(".toc"):
            references = [line.strip() for line in content.decode("utf-8-sig").splitlines()
                          if line.strip() and not line.lstrip().startswith("#")]
        elif path.endswith(".xml"):
            document = ET.fromstring(content)
            references = [node.attrib["file"] for node in document.iter()
                          if node.tag.rsplit("}", 1)[-1] in {"Script", "Include"} and "file" in node.attrib]
        else:
            continue
        for reference in references:
            target = posixpath.normpath(posixpath.join(posixpath.dirname(path), reference.replace("\\", "/")))
            if target not in payload:
                raise ValueError(f"Missing packaged load reference: {path} -> {reference}")


def build(root, output, curseforge_client_beta=False, release_channel="alpha"):
    if release_channel not in ("alpha", "beta"):
        raise ValueError("Unsupported release channel")
    if curseforge_client_beta and release_channel != "alpha":
        raise ValueError("Use the normal Beta package for publishing to all platforms")
    release_type = "beta" if curseforge_client_beta else release_channel
    targets = ["curseforge"] if curseforge_client_beta else ["github", "curseforge", "wago"]
    existing_manifest = output / "RELEASE_MANIFEST.json"
    if existing_manifest.exists():
        previous = json.loads(existing_manifest.read_text(encoding="utf-8"))
        if previous["curseforgeReleaseType"] != release_type or previous["publishTargets"] != targets:
            raise ValueError("Use separate output directories for the Alpha and CurseForge client Beta packages")
    if curseforge_client_beta and (output / "WAGO_METADATA.json").exists():
        raise ValueError("Refusing a client Beta output directory containing Wago upload metadata")
    files = tracked_files(root)
    core_toc = (root / "MSUF_Suite/MSUF_Suite_Mainline.toc").read_text(encoding="utf-8-sig")
    version = field(core_toc, "Version")
    match = re.fullmatch(r"(\d+(?:\.\d+)+)-alpha(?:([1-9]\d*))?", version)
    if not match:
        raise ValueError("This publisher accepts Alpha versions only")
    release_name = f"{match[1]} Alpha" + (f" {match[2]}" if match[2] else "")
    title = "MSUF Suite " + release_name
    addons = validate_addons(root, files, version)
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    entry = changelog.split("\n## ", 1)[1].split("\n## ", 1)[0].strip()
    heading = entry.split(" - ", 1)[0]
    if heading != release_name:
        raise ValueError("Latest changelog does not match the release version")
    requirements = ("**Alpha build. Requires Midnight Simple Unit Frames (MSUF); compatible with MSUF 6.5 "
                    "(release 6.50). CurseForge installs MSUF as a required dependency.**\n\n"
                    "Supported clients: WoW Retail 12.1.5 and WoW Forever 1.60.1.\n")
    notes = "# " + title + "\n\n" + requirements + "\n## " + entry + "\n"
    output.mkdir(parents=True, exist_ok=True)
    payload = {path: (root / path).read_bytes() for path in files if path.split("/")[0] in addons}
    payload["MSUF_Suite/LICENSE.txt"] = (root / "LICENSE.txt").read_bytes()
    if curseforge_client_beta or release_channel == "beta":
        payload["MSUF_Suite/README.md"] = (root / "README.md").read_bytes()
    validate_payload(payload)
    suffix = "-curseforge-client" if curseforge_client_beta else ""
    archive = output / f"MSUF-Suite-{version}{suffix}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        for path, content in sorted(payload.items()):
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            package.writestr(info, content)
    metadata = {
        "CURSEFORGE_METADATA.json": {
            "displayName": title + (" (CurseForge Client)" if curseforge_client_beta else ""),
            "releaseType": release_type, "changelogType": "markdown", "changelog": notes,
            "gameVersionNames": ["12.1.5", "1.60.1"],
            "relations": {"projects": [{"slug": "midnightsimpleunitframes", "projectID": "1384660",
                                         "type": "requiredDependency"}]},
        },
        "WAGO_METADATA.json": {
            "label": title, "stability": release_channel, "changelog": notes,
            "supported_retail_patches": ["12.1.5"], "supported_forever_patches": ["1.60.1"],
        },
        "RELEASE_MANIFEST.json": {
            "version": version, "tag": "v" + version, "title": title, "githubPrerelease": False,
            "curseforgeReleaseType": release_type,
            "publishTargets": targets,
            "wagoStability": release_channel, "requiredHost": "MSUF 6.5 (6.50)",
            "addons": addons, "archive": archive.name, "bytes": archive.stat().st_size,
            "projects": {"curseforge": field(core_toc, "X-Curse-Project-ID"), "wago": field(core_toc, "X-Wago-ID")},
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "files": {path: hashlib.sha256(content).hexdigest() for path, content in sorted(payload.items())},
        },
    }
    if curseforge_client_beta:
        del metadata["WAGO_METADATA.json"]
    for name, value in metadata.items():
        (output / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    (output / "RELEASE_NOTES.md").write_text(notes, encoding="utf-8", newline="\n")
    (output / "PROJECT_DESCRIPTION.md").write_bytes((root / "README.md").read_bytes())
    channel = "CurseForge client Beta" if curseforge_client_beta else "CurseForge/Wago " + release_channel.title()
    print(f"Built {archive.name}: {len(addons)} addons, {len(payload)} files; {channel}, MSUF required")
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--curseforge-client-beta", action="store_true",
                        help="Additional CurseForge Beta file for initial client listing; Suite version remains Alpha")
    parser.add_argument("--release-channel", choices=("alpha", "beta"), default="alpha",
                        help="Distribution channel; the Suite Alpha version name is retained")
    args = parser.parse_args()
    output = args.output or ROOT / "dist" / ("curseforge-client" if args.curseforge_client_beta else args.release_channel)
    build(ROOT, output, args.curseforge_client_beta, args.release_channel)


if __name__ == "__main__":
    main()
