"""The Forever factory install keeps the frame positions the factory was made with.

The bundled Forever frame profile (ForeverFrames.lua) is decoded as the client
decodes it (base64, raw deflate, CBOR). Every positioned frame in it carries
MSUF's own screen reference (screenPositionMode "relativeHeight" and the
UIParent height it was saved at). The real installer (Open, Continue, Install
with its defaults on WoW Forever) runs on that data through the real Suite core.
MSUF is modelled as both hosts behave (MSUF_UF_Config.lua AdaptScreenPosition
and MSUF_SetCurrentProfileScreenReferenceHeight): a frame whose reference
differs from the current UIParent height is scaled by current / reference and
restamped, at the import's runtime apply and again when a reference is set.
Each frame must end at its saved offset scaled by UIParent height / its own
reference, at 1440, 1080 and 768 UI units.
Usage: python suite_forever_factory_reference_smoke.py <suite root>
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
# The frames MSUF itself adapts to the screen: group anchors on UIParent and
# unit frames without a unit-frame anchor.
ADAPTED = ("gf_party", "gf_raid", "gf_mythicraid", "arena")

HARNESS = r"""
local root = arg[1]
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local FRAMES = FRAMES_LITERAL
local ADAPTED = { "gf_party", "gf_raid", "gf_mythicraid", "arena" }
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
-- MSUF's AdaptScreenPosition: only frames that carry the relative mode move.
local function Adapt(conf)
    if type(conf) ~= "table" or conf.screenPositionMode ~= "relativeHeight" then return end
    local height = UIParent:GetHeight()
    local previous = tonumber(conf.screenPositionHeight)
    if previous and previous >= 400 and previous <= 10000 and math.abs(previous - height) > 0.01 then
        local factor = height / previous
        for _, field in ipairs({ "offsetX", "offsetY", "x", "y" }) do
            if type(conf[field]) == "number" then conf[field] = conf[field] * factor end
        end
    end
    conf.screenPositionHeight = height
end
local function Layout(db)
    for _, key in ipairs(ADAPTED) do Adapt(db[key]) end
end
for _, height in ipairs({ 1440, 1080, 768 }) do
    local Suite = H.Setup({ root = root, forever = true, uiHeight = height,
        frameFactory = function() return Copy(FRAMES) end,
        afterImport = function(_, profile) Layout(profile) end })
    -- MSUF_SetCurrentProfileScreenReferenceHeight: stamps every positioned
    -- frame with the given reference, then refreshes the layout.
    MSUF_SetCurrentProfileScreenReferenceHeight = function(reference)
        for _, conf in pairs(MSUF_DB) do
            if type(conf) == "table" and (conf.offsetX ~= nil or conf.offsetY ~= nil) then
                conf.screenPositionHeight, conf.screenPositionMode = reference, "relativeHeight"
            end
        end
        Layout(MSUF_DB)
        return true
    end
    local frame = H.Install(Suite)
    assert(MSUF_ActiveProfile:find("^MSUF Suite Forever"), "the Forever profile was not installed: "
        .. tostring(frame.status.text))
    assert(#H.reported == 0, "a call raised: " .. tostring(H.reported[1]))
    for _, key in ipairs(ADAPTED) do
        local authored, conf = FRAMES[key], MSUF_DB[key]
        local factor = height / authored.screenPositionHeight
        for _, field in ipairs({ "offsetX", "offsetY" }) do
            local want = authored[field] * factor
            assert(math.abs(conf[field] - want) < 0.01, ("%s.%s at UIParent height %d is %.1f, the factory's "
                .. "position there is %.1f"):format(key, field, height, conf[field], want))
        end
    end
    print(("UIParent height %d: gf_party %.1f, %.1f"):format(height, MSUF_DB.gf_party.offsetX, MSUF_DB.gf_party.offsetY))
end
"""


def text(value):
    return value.decode("utf-8") if isinstance(value, bytes) else value


def lua_literal(value):
    if isinstance(value, (bytes, str)):
        return '"' + "".join("\\%d" % b for b in text(value).encode("utf-8")) + '"'
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua_literal(k) + "]=" + lua_literal(v) for k, v in value.items()) + "}"
    raise TypeError(type(value))


def main():
    root = Path(sys.argv[1])
    source = (root / "MSUF_Suite" / "Core" / "ForeverFrames.lua").read_text(encoding="utf-8")
    compact = re.search(r"Suite\.ForeverFactoryFramesCompact = \[\[(.*?)\]\]", source, re.S).group(1)
    assert compact.startswith("MSUF3:")
    envelope = cbor2.loads(zlib.decompress(base64.b64decode(compact[6:]), -15))
    profile = envelope[b"payload"]
    frames = {}
    for key in ADAPTED:
        conf = {text(k): v for k, v in profile[key.encode()].items()}
        assert conf.get("screenPositionMode") in (b"relativeHeight", "relativeHeight"), key + " has no screen reference"
        frames[key] = {field: conf[field] for field in ("offsetX", "offsetY", "screenPositionHeight")}
        frames[key]["screenPositionMode"] = "relativeHeight"
    script = HARNESS.replace("FRAMES_LITERAL", lua_literal(frames), 1)
    run = subprocess.run([LUA, "-", str(root)], input=script, capture_output=True, text=True, errors="replace",
                         cwd=root)
    output = (run.stdout + run.stderr).strip()
    if run.returncode:
        raise SystemExit(output)
    print(output)


if __name__ == "__main__":
    main()
