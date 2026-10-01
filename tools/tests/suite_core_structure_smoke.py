"""Structure contract of MSUF_Suite, MSUF_Suite_Modules and MSUF_Suite_Options.

Every Lua file stays below 900 lines, 150 main-chunk locals and 80 lines per
function (luac listing), uses no pcall/xpcall/loadstring and no existence
guard for an API that Retail and Forever both have. Split files load in
dependency order, and the shared helpers exist once.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
LUAC = str(Path(LUA).with_name("luac.exe"))
ADDONS = ("MSUF_Suite", "MSUF_Suite_Modules", "MSUF_Suite_Options")
# Files outside this contract, with the reason.
EXEMPT = {}
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def lua_files():
    for addon in ADDONS:
        for path in sorted((ROOT / addon).rglob("*.lua")):
            rel = path.relative_to(ROOT).as_posix()
            if rel not in EXEMPT:
                yield rel, path


# Sizes: lines, main-chunk locals and function length. Language packs are
# data (one line per string; tools/suite_locale_tool.py checks them).
FUNCTION = re.compile(r"^(main|function) <.*:(\d+),(\d+)> ")
LANGUAGE_PACK = re.compile(r"^MSUF_Suite/Locales/[a-z]{2}[A-Z]{2}\.lua$")
for rel, path in lua_files():
    text = path.read_text(encoding="utf-8")
    check(text.count("\n") <= 900 or LANGUAGE_PACK.match(rel), rel + " is above 900 lines")
    check(not re.search(r"\b(pcall|xpcall|loadstring)\b", text), rel + " uses pcall, xpcall or loadstring")
    run = subprocess.run([LUAC, "-l", "-p", str(path)], capture_output=True, text=True)
    check(run.returncode == 0, rel + " does not compile: " + run.stderr.strip())
    listing = run.stdout.splitlines()
    for i, line in enumerate(listing):
        match = FUNCTION.match(line)
        if not match:
            continue
        if match.group(1) == "main":
            locals_ = int(re.search(r"(\d+) locals?", listing[i + 1]).group(1))
            check(locals_ <= 150, "%s declares %d main-chunk locals" % (rel, locals_))
        else:
            length = int(match.group(3)) - int(match.group(2)) + 1
            check(length <= 80, "%s:%s has a %d-line function" % (rel, match.group(2), length))

# No existence guard for an API both clients have (verified against the live
# and forever UI source); the tests stub these APIs instead.
GUARDS = re.compile(
    r"\b(C_\w+) and \1\.|\bEnum and Enum\.|securecallfunction or|\bif C_Timer\b|\bnot C_Timer\b"
    r"|\bnot (?:C_AddOns|EventRegistry)\b|\b(?:C_AddOns|EventRegistry) and\b|TODO\(test stubs\)"
    r"|type\((?:_G\.)?(hooksecurefunc|InCombatLockdown|UnitClass|UnitName|UnitLevel|UnitXP|UnitGUID|GetRealmName|GetMoney"
    r"|GetLocale|IsLoggedIn|ReloadUI|GetCursorPosition|GetZoneText|GetGameTime|GetCVarBool|GetTime|C_Timer"
    r"|OpenAllBags|IsInInstance|GetTaskInfo|GetQuestObjectiveInfo|GetAchievementInfo|GetAchievementCriteriaInfo"
    r"|GetQuestLogSpecialItemInfo|UseQuestLogSpecialItem|OpenQuestLog|GetInventoryItemTexture|GetInventoryItemID"
    r"|GetWorldElapsedTime|GetWorldElapsedTimers|LoggingCombat|GetInstanceInfo|GetBindingText"
    r"|GetPhysicalScreenSize|C_Map|C_Container|C_Item|C_Spell|C_Texture|C_ChallengeMode|C_Scenario)\) *[~=]=")
for rel, path in lua_files():
    found = len(GUARDS.findall(path.read_text(encoding="utf-8")))
    check(found == 0, "%s guards %d APIs both clients have" % (rel, found))

# No probe for a module of the same addon or of MSUF_Suite: every file of an
# addon has loaded before its functions run, and MSUF_Suite before the load-
# on-demand addons. S.* exports of a load-on-demand addon, the database before
# it is initialised and other addons' exports stay checked where they are used.
OWN = r"(?:Suite|NS|P|P\.Suite|P\.S|Page|CDM)"
MODULE_PROBES = re.compile(
    r"\b(" + OWN + r")\.((?!DB\b|RootDB\b)[A-Z]\w*) and \1\.\2\b"
    r"|\bif (?:not )?" + OWN + r"\.(?!DB\b|RootDB\b)[A-Z]\w* then\b"
    r"|type\(" + OWN + r"\.[A-Z]\w*\) [~=]= \"function\""
    r"|\b" + OWN + r"\.[A-Z]\w* or (?:\{\}|\d)")
for rel, path in lua_files():
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if not line.strip().startswith("--")]
    found = sum(1 for line in lines if MODULE_PROBES.search(line))
    check(found == 0, "%s probes %d modules that are always loaded" % (rel, found))

# Split files load after the files they build on.
def toc(addon):
    lines = (ROOT / addon / (addon + "_Mainline.toc")).read_text(encoding="utf-8").splitlines()
    return [line.strip().replace("\\", "/") for line in lines if line.strip() and not line.startswith("#")]


def ordered(addon, files):
    order = toc(addon)
    at = [order.index(name) if name in order else -1 for name in files]
    check(-1 not in at and at == sorted(at), "%s TOC must list %s in this order" % (addon, ", ".join(files)))


ordered("MSUF_Suite", ["Core/Platform.lua", "Core/Database.lua", "Core/SessionGold.lua", "Core/SuiteCatalog.lua",
                       "Core/Catalog/ActionBars.lua", "Core/MinimapStyle.lua", "Core/Suite.lua", "Core/Startup.lua"])
ordered("MSUF_Suite_Options", ["Pages/MinimapPreviewArt.lua", "Pages/MinimapPreviewPaint.lua",
                               "Pages/MinimapPreview.lua", "Pages/Minimap.lua"])
ordered("MSUF_Suite_Options", ["Pages/CooldownManagerData.lua", "Pages/CooldownManagerBars.lua",
                               "Pages/CooldownManagerWidgets.lua", "Pages/CooldownManagerPicker.lua",
                               "Pages/CooldownManagerPopover.lua", "Pages/CooldownManagerPreviewIcons.lua",
                               "Pages/CooldownManagerPreview.lua", "Pages/CooldownManager.lua"])

# Shared helpers exist once across the Suite addons (the skin is separate).
suite_sources = {}
for folder in sorted(ROOT.glob("MSUF_Suite*")):
    if folder.is_dir() and not folder.name.startswith("MSUF_Suite_Skin"):
        for path in folder.rglob("*.lua"):
            suite_sources[path.relative_to(ROOT).as_posix()] = path.read_text(encoding="utf-8")


def only_in(pattern, owners, what, addons=None):
    found = sorted(rel for rel, text in suite_sources.items()
                   if re.search(pattern, text) and (addons is None or rel.split("/")[0] in addons))
    check(found == sorted(owners), "%s must live only in %s, found in %s" % (what, ", ".join(owners), ", ".join(found)))


only_in(r'"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER"', ["MSUF_Suite/Core/SuiteCatalog.lua"], "the anchor list")
only_in(r'"Top left", "Top", "Top right"', ["MSUF_Suite/Core/SuiteCatalog.lua"], "the anchor labels")
only_in(r"hex:sub\(1, 2\), 16", ["MSUF_Suite/Core/Platform.lua"], "the color reader")
only_in(r"GetLibrary\(\"LibSharedMedia-3\.0\"", ["MSUF_Suite/Core/Platform.lua"], "the SharedMedia lookup",
        ADDONS + ("MSUF_Suite_CooldownManager", "MSUF_Suite_ActionBars"))
only_in(r"\.suiteGold\b", ["MSUF_Suite/Core/SessionGold.lua"], "the session gold store")
only_in(r"function S\.BlizzardText", ["MSUF_Suite_Modules/Surfaces.lua"], "S.BlizzardText")
only_in(r"function \w+\.Text\(global|function MM\.Label\(", [], "a Blizzard-text helper copy")
# Every text section links its shadow settings through Build.LinkFontShadow.
only_in(r'key = "fontRendering", values', ["MSUF_Suite/Core/SuiteCatalog.lua"], "the text shadow wiring")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Suite core, modules and options structure: sizes, guards, load order and shared helpers passed")
