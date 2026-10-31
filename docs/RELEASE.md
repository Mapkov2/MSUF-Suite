# Suite Alpha publication

The Suite is a separate addon package for Retail and WoW Forever. It requires
Midnight Simple Unit Frames. MSUF 6.5 (release 6.50) is the compatible host.
Classic Era, TBC and Mists are not Suite upload targets.

Run the full local gate, then build the tracked addon files:

```text
python tools/run_suite_tests.py
python tools/build_suite_release.py
python tools/build_suite_release.py --curseforge-client-beta --output dist/curseforge-client
```

`dist/alpha` contains the ZIP, public project description, release notes,
CurseForge and Wago upload metadata, and the package file/hash manifest.
Local instructions, private planning, tests, profiling files, SavedVariables
and the MSUF host are excluded from the ZIP.

| Platform | Version / channel | Required MSUF dependency |
| --- | --- | --- |
| GitHub | Regular release, tag and title from `RELEASE_MANIFEST.json` | State that MSUF 6.5 (6.50) must be installed separately |
| CurseForge | Alpha plus an additional Beta file for initial app listing | `midnightsimpleunitframes`, project `1384660`, **Required Dependency**, installed automatically by the client |
| Wago | Alpha | Required by the addon TOC; public info links the MSUF project `XKq9aoKy` |

Use `PROJECT_DESCRIPTION.md` as the normal project info text and
`RELEASE_NOTES.md` for this version. The Alpha designation remains visible in
the title, tag, addon version and description even though GitHub uses a regular
release. Do not mark a CurseForge file as Release or the Wago version as Stable.

The owner also authorized a CurseForge client Beta file: new Alpha-only projects
do not initially appear in the CurseForge app. Its addon runtime is byte-identical
to the Alpha ZIP; only the public module/install README is added inside the core
folder. This variant is for CurseForge only. It uses the Beta distribution channel
while the addon version and product description remain **Alpha**, using the version declared in the core TOC. Wago remains
Alpha. A new project and its files still require CurseForge moderation.

The Suite upload destinations are CurseForge project **1743628**
([project](https://www.curseforge.com/wow/addons/msuf-suite)) and Wago project
**YK9xrV6L** ([project](https://addons.wago.io/addons/msuf-suite)).
Never use the MSUF host project ID as the Suite upload destination.
Tokens belong in GitHub secrets or the local environment, never in source or
release assets. API automation needs platform tokens; browser uploads use the
existing developer sign-in. Both project IDs are declared in the core TOC.

Upload the original Alpha ZIP to all three platforms, and the additional client
Beta ZIP to CurseForge only. Users install through the CurseForge client (Beta)
or Wago client (Alpha). CurseForge installs MSUF automatically; Wago users also
install MSUF in their client. CurseForge accepts the generated
`CURSEFORGE_METADATA.json` as the `metadata` multipart field and the ZIP as
`file`; authenticate using `X-Api-Token` at
`https://wow.curseforge.com/api/projects/1743628/upload-file`.
Wago accepts `WAGO_METADATA.json` and the ZIP at its Suite project version URL,
`https://addons.wago.io/api/projects/YK9xrV6L/version`, with Bearer authentication.
Wago's documented version upload metadata does not
include a dependency field, and the current project/version forms offer none.
The addon TOC enforces the required host; the public info states it explicitly.

After upload, verify the public version, Alpha channel, required dependency,
client targeting and ZIP hash. An accepted upload awaiting moderation is not
yet a visible download.

API references: [CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api),
[Wago Addons API](https://docs.wago.io/), [Wago game versions](https://addons.wago.io/api/data/game).

The builder also supports a normal Beta package for both platforms:

```text
python tools/build_suite_release.py --release-channel beta --output dist/beta
```

Use the channel and destinations in that package's generated metadata consistently.
Do not combine its files with `dist/alpha` or the CurseForge-only client variant.
A successful package build performs no upload. Publication requires a separate
release instruction.
