"""New profiles from the bundled factories start at the current migration revision.

Each factory string (RetailFactory.lua, ForeverFactory.lua) is decoded as the
client decodes it (base64, raw deflate, CBOR) and handed to the real Suite
core through MSUF's codec entry point; the profile comes from the real
Database.CreateFactoryProfile (first install, new profile, reset) and from
ProfileIO.PrepareProfile (the installer's factory). The data carries the
current suite.revision, so no migration step for older profiles runs on it:
the values those steps supplied are part of the data, Bags start with the
catalog's view (not Blizzard's grid) and the Damage Meter with the catalog's
refresh rate (1.5 seconds, the owner's 2026-10-03 decision).
Usage: python suite_factory_profile_smoke.py <suite root>
"""

import base64
import os
import re
import subprocess
import sys
import zlib
from pathlib import Path

import cbor2

LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
PREFIX = "MSUFM1:MSUF3:"

HARNESS = r"""
local root, client, factory = arg[1], arg[2], arg[3]
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, reported = {}, {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
if client == "forever" then GameEvent = { RegisterCamelotEvents = function() end } end
SlashCmdList = {}
InCombatLockdown = function() return false end
UnitGUID = function() return "Player-Test" end
Minimap = { SetMaskTexture = function() end }
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end, UnregisterEvent = function() end,
        UnregisterAllEvents = function() end }
end
C_AddOns = { IsAddOnLoaded = function() return false end, DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 0 end }
local envelope = ENVELOPE
local decodes = 0
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
-- MSUF's codec: the decoded factory, a fresh copy per call like the client's.
MSUF_EncodeCompactTable = function() return "MSUF3:" end
MSUF_TryDecodeCompactString = function(text)
    assert(text:sub(1, 6) == "MSUF3:", "the factory is not an MSUF3 string")
    decodes = decodes + 1
    return Copy(envelope)
end
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileIO.lua")
Suite.Suite.RGB = Suite.RGB
_G.MSUFSuite = Suite
assert(Suite.Client.isForever == (client == "forever"), "the client flavor is wrong")
local S, defaults = Suite.Suite, Suite.Defaults.suite.modules
local data = envelope.profile.suite
assert(data.revision == S.MigrationRevision, factory .. " is stamped with revision " .. tostring(data.revision)
    .. ", the current one is " .. S.MigrationRevision)
for key in pairs(data) do
    assert(not tostring(key):find("Revision$"), factory .. " still carries the legacy migration flag " .. tostring(key))
end
local function Check(profile, how)
    local m = profile.suite.modules
    assert(profile.suite.revision == S.MigrationRevision, how .. ": the profile revision is not current")
    assert(m.bags.inventoryView == defaults.bags.inventoryView, how .. ": Bags start with view "
        .. tostring(m.bags.inventoryView) .. ", the catalog's is " .. tostring(defaults.bags.inventoryView))
    assert(m.damageMeter.refreshRate == 1.5 and defaults.damageMeter.refreshRate == 1.5,
        how .. ": the Damage Meter refreshes every " .. tostring(m.damageMeter.refreshRate) .. " s")
    -- What the steps for older profiles supplied is part of the data.
    local o = m.objectives
    assert(o.titleSize == 18 and o.sectionSize == 14 and o.entrySize == 15 and o.objectiveSize == 13,
        how .. ": the tracker text sizes changed")
    assert(m.xpBar.point == 2 and m.xpBar.x == 0 and m.xpBar.y == -24, how .. ": the XP bar moved")
    assert(m.announcements.subtitleSize == 16, how .. ": the announcement subtitle size changed")
    assert(m.dataTexts.bar1Point == (factory == "ForeverFactory.lua" and 3 or 8), how .. ": the first DataText bar moved")
    assert(m.lootContainers.skipWarbound == true, how .. ": Warbound containers are opened")
    assert(m.nameplates.friendlyGroupOnly == nil, how .. ": the retired friendly plate switch came back")
end
assert(Suite.Database.Initialize(nil), "no database")
local created = Suite.Database.CreateFactoryProfile()
Check(created, "CreateFactoryProfile")
assert(created.suite.globalLook == "cleanModern" and created.suite.modules.chat.look == 5,
    "the factory profile was not styled Clean Modern")
Check(Suite.DB, "the first profile")
local compact = factory == "ForeverFactory.lua" and Suite.ForeverFactoryModuleCompact or Suite.RetailFactoryModuleCompact
Check(assert(Suite.ProfileIO.PrepareProfile(compact, false)), "the installer's factory")
assert(decodes >= 3, "the factory string was not decoded")
assert(#reported == 0, "a call raised: " .. tostring(reported[1]))
print(factory .. " on " .. client .. ": revision " .. data.revision .. ", Bags view "
    .. tostring(created.suite.modules.bags.inventoryView) .. ", Damage Meter "
    .. created.suite.modules.damageMeter.refreshRate .. " s")
"""


def lua_literal(value):
    if isinstance(value, bytes):
        return '"' + "".join("\\%d" % b for b in value) + '"'
    if isinstance(value, str):
        return lua_literal(value.encode("utf-8"))
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return "{" + ",".join(lua_literal(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua_literal(k) + "]=" + lua_literal(v) for k, v in value.items()) + "}"
    raise TypeError(type(value))


def envelope(path, name):
    source = path.read_text(encoding="utf-8")
    match = re.search(name + r" = \[\[(.*?)\]\]", source, re.S)
    assert match and match.group(1).startswith(PREFIX), name + " missing"
    return cbor2.loads(zlib.decompress(base64.b64decode(match.group(1)[len(PREFIX):]), -15))


def main():
    root = Path(sys.argv[1])
    core = root / "MSUF_Suite" / "Core"
    # The Forever factory also installs on Retail (the installer's Forever choice).
    for file, name, client in (("RetailFactory.lua", "RetailFactoryModuleCompact", "retail"),
                               ("ForeverFactory.lua", "ForeverFactoryModuleCompact", "forever"),
                               ("ForeverFactory.lua", "ForeverFactoryModuleCompact", "retail")):
        script = HARNESS.replace("ENVELOPE", lua_literal(envelope(core / file, name)), 1)
        run = subprocess.run([LUA, "-", str(root), client, file], input=script, capture_output=True,
                             text=True, errors="replace", cwd=root)
        output = (run.stdout + run.stderr).strip()
        if run.returncode:
            raise SystemExit(output)
        print(output)


if __name__ == "__main__":
    main()
