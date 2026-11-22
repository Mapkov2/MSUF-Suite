"""Release channels, host dependencies, payload safety and load references."""

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("suite_release", root / "tools/build_suite_release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def rejects(function, message):
    try:
        function()
    except ValueError:
        return
    raise AssertionError(message)


for name in ("MSUF_Suite/AGENTS.md", "MSUF_Suite/.env", "MSUF_Suite/.agents/private.toml",
             "MSUF_Suite/tests/private.lua", "MSUF_Suite/!!!Perfy.lua", "MSUF_Suite/SavedVariables/profile.lua"):
    rejects(lambda: builder.validate_payload({name: b"private"}), "Shipped local artifact: " + name)
rejects(lambda: builder.validate_payload({"MSUF_Suite/Core/Load.toc": b"Core/Missing.lua\n"}),
        "Missing TOC load reference was packaged")
rejects(lambda: builder.validate_payload({"MSUF_Suite/Core/Load.xml": b'<Ui><Script file="Missing.lua"/></Ui>'}),
        "Missing XML load reference was packaged")
builder.validate_payload({"MSUF_Suite/Core/Load.toc": b"Child.xml\n",
                          "MSUF_Suite/Core/Child.xml": b'<Ui><Script file="Child.lua"/></Ui>',
                          "MSUF_Suite/Core/Child.lua": b"return true"})

# Validate the real working source, including new modules installed from the
# checkout. The publication builder still limits its input to Git-listed files.
worktree_files = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root,
).decode("utf-8").split("\0")
worktree_files = sorted({file for file in worktree_files if file and (root / file).is_file()})
version = builder.field((root / "MSUF_Suite/MSUF_Suite_Mainline.toc").read_text(encoding="utf-8-sig"), "Version")
addons = builder.validate_addons(root, worktree_files, version)
builder.validate_payload({file: (root / file).read_bytes() for file in worktree_files if file.split("/")[0] in addons})

with tempfile.TemporaryDirectory(prefix="suite-release-contract-") as temporary:
    scratch = Path(temporary) / "source"
    core = scratch / "MSUF_Suite/MSUF_Suite_Mainline.toc"
    options = scratch / "MSUF_Suite_Options/MSUF_Suite_Options_Mainline.toc"
    for path in (core, options):
        path.parent.mkdir(parents=True)
    header = "## Version: 0.1-alpha\n## Interface: 120105,120107,16001\n"
    core.write_text(header + "## Dependencies: MidnightSimpleUnitFrames\n"
                    "## X-Curse-Project-ID: 1743628\n## X-Wago-ID: YK9xrV6L\n", encoding="utf-8")
    options.write_text(header + "## Dependencies: MSUF_Suite, MidnightSimpleUnitFrames_Options\n", encoding="utf-8")
    files = [path.relative_to(scratch).as_posix() for path in (core, options)]
    # A complete minimal package has one optional addon with all canonical catalogs.
    addon = "MSUF_Suite_Locales"
    locale_manifest = scratch / addon / (addon + "_Mainline.toc")
    locale_manifest.parent.mkdir(parents=True)
    locale_entries = []
    for locale in ("deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"):
        locale_entries.append("..\\MSUF_Suite\\Locales\\" + locale + ".lua\n")
        catalog = scratch / "MSUF_Suite/Locales" / (locale + ".lua")
        catalog.parent.mkdir(exist_ok=True)
        catalog.write_text("return\n", encoding="utf-8")
        files.append(catalog.relative_to(scratch).as_posix())
    locale_manifest.write_text(header + "## Dependencies: MidnightSimpleUnitFrames\n## LoadOnDemand: 1\n"
                               + "".join(locale_entries), encoding="utf-8")
    files.append(locale_manifest.relative_to(scratch).as_posix())
    builder.validate_addons(scratch, files, "0.1-alpha")
    original = core.read_bytes()
    for old, new in ((b"MidnightSimpleUnitFrames", b"OptionalHost"), (b"120105,120107,16001", b"120105,16001"),
                     (b"120105,120107,16001", b"120105,120107"),
                     (b"0.1-alpha", b"0.1")):
        core.write_bytes(original.replace(old, new))
        rejects(lambda: builder.validate_addons(scratch, files, "0.1-alpha"), "Unsafe TOC passed: " + str(new))
    core.write_bytes(original)
    cycle = scratch / "MSUF_Suite_Cycle/MSUF_Suite_Cycle_Mainline.toc"
    cycle.parent.mkdir()
    cycle.write_text(header + "## Dependencies: MSUF_Suite, MSUF_Suite_Cycle\n", encoding="utf-8")
    rejects(lambda: builder.validate_addons(scratch, files + [cycle.relative_to(scratch).as_posix()], "0.1-alpha"),
            "An addon may reach MSUF and still fail to load because of a required dependency cycle")
    options.write_text(header + "## Dependencies: MSUF_Suite\n", encoding="utf-8")
    rejects(lambda: builder.validate_addons(scratch, files, "0.1-alpha"), "MSUF Options became optional")

    # Metadata and deterministic archive checks need a release entry; use an
    # isolated Git fixture so an Unreleased working changelog is also testable.
    options.write_text(header + "## Dependencies: MSUF_Suite, MidnightSimpleUnitFrames_Options\n", encoding="utf-8")
    for path, content in (("CHANGELOG.md", "# Suite changelog\n\n## Unreleased\n\n- Pending.\n"),
                          ("LICENSE.txt", "Test license\n"), ("README.md", "# Suite fixture\n")):
        (scratch / path).write_text(content, encoding="utf-8")
    subprocess.run(["git", "init", "--quiet"], cwd=scratch, check=True)
    subprocess.run(["git", "-c", "core.autocrlf=false", "add", "--", *files, "CHANGELOG.md", "LICENSE.txt", "README.md"],
                   cwd=scratch, check=True)
    root = scratch
    scratch = Path(temporary) / "output"
    rejects(lambda: builder.build(root, scratch / "unreleased"), "Unreleased changelog became publishable")
    (root / "CHANGELOG.md").write_text("# Suite changelog\n\n## 0.1 Alpha - 2026-01-01\n\n- Fixture release.\n",
                                       encoding="utf-8")

    first = builder.build(root, scratch / "first")
    second = builder.build(root, scratch / "second")
    assert first.read_bytes() == second.read_bytes(), "Package is not deterministic"
    manifest = json.loads((first.parent / "RELEASE_MANIFEST.json").read_text(encoding="utf-8"))
    assert manifest["sha256"] == hashlib.sha256(first.read_bytes()).hexdigest()
    assert manifest["githubPrerelease"] is False
    assert manifest["projects"] == {"curseforge": "1743628", "wago": "YK9xrV6L"}
    assert manifest["curseforgeReleaseType"] == manifest["wagoStability"] == "alpha"
    with zipfile.ZipFile(first) as package:
        assert set(package.namelist()) == set(manifest["files"])
        assert all(name.split("/")[0] in manifest["addons"] for name in package.namelist())
        for name, digest in manifest["files"].items():
            assert hashlib.sha256(package.read(name)).hexdigest() == digest, name
    curseforge = json.loads((first.parent / "CURSEFORGE_METADATA.json").read_text(encoding="utf-8"))
    assert curseforge["gameVersionNames"] == ["12.1.5", "12.1.7", "1.60.1"]
    assert curseforge["relations"]["projects"] == [{"slug": "midnightsimpleunitframes", "projectID": 1384660,
                                                  "type": "requiredDependency"}]
    wago = json.loads((first.parent / "WAGO_METADATA.json").read_text(encoding="utf-8"))
    assert wago["stability"] == "alpha"
    assert wago["supported_retail_patches"] == ["12.1.5", "12.1.7"]
    assert wago["supported_forever_patches"] == ["1.60.1"]
    client = builder.build(root, scratch / "client-beta", curseforge_client_beta=True)
    client_manifest = json.loads((client.parent / "RELEASE_MANIFEST.json").read_text(encoding="utf-8"))
    assert client_manifest["version"] == manifest["version"]
    assert client_manifest["curseforgeReleaseType"] == "beta"
    assert client_manifest["publishTargets"] == ["curseforge"]
    assert not (client.parent / "WAGO_METADATA.json").exists()
    assert set(client_manifest["files"]) == set(manifest["files"]) | {"MSUF_Suite/README.md"}
    assert all(client_manifest["files"][name] == digest for name, digest in manifest["files"].items())
    with zipfile.ZipFile(client) as package:
        assert package.read("MSUF_Suite/README.md") == (root / "README.md").read_bytes()
        assert all(hashlib.sha256(package.read(name)).hexdigest() == digest
                   for name, digest in client_manifest["files"].items())
    client_metadata = json.loads((client.parent / "CURSEFORGE_METADATA.json").read_text(encoding="utf-8"))
    assert client_metadata["releaseType"] == "beta"
    assert client_metadata["relations"] == curseforge["relations"]
    beta = builder.build(root, scratch / "beta", release_channel="beta")
    beta_manifest = json.loads((beta.parent / "RELEASE_MANIFEST.json").read_text(encoding="utf-8"))
    assert beta_manifest["version"] == manifest["version"]
    assert beta_manifest["title"] == manifest["title"] and beta_manifest["githubPrerelease"] is False
    assert beta_manifest["publishTargets"] == ["github", "curseforge", "wago"]
    assert beta_manifest["curseforgeReleaseType"] == beta_manifest["wagoStability"] == "beta"
    assert beta_manifest["files"] == client_manifest["files"]
    for name, field in (("CURSEFORGE_METADATA.json", "releaseType"), ("WAGO_METADATA.json", "stability")):
        assert json.loads((beta.parent / name).read_text(encoding="utf-8"))[field] == "beta"
    assert builder.build(root, scratch / "beta-second", release_channel="beta").read_bytes() == beta.read_bytes()
    rejects(lambda: builder.build(root, beta.parent), "Beta output was overwritten by Alpha metadata")
    rejects(lambda: builder.build(root, client.parent, release_channel="beta"), "Client-only output accepted Wago metadata")
    rejects(lambda: builder.build(root, scratch / "invalid", release_channel="release"), "Unknown channel accepted")
    for output, beta in ((first.parent, True), (client.parent, False)):
        before = {path.name: path.read_bytes() for path in output.iterdir() if path.is_file()}
        rejects(lambda: builder.build(root, output, curseforge_client_beta=beta), "Mixed output variants were accepted")
        after = {path.name: path.read_bytes() for path in output.iterdir() if path.is_file()}
        assert before == after, "Rejected variant switch overwrote a published artifact or metadata"
print("suite_release_package_contract: ok")
