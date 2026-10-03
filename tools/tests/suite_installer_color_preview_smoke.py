"""Installer swatches match the real factories and palette styles on both clients.

Only the bundled profile copies and owned preview frames may change. This uses
actual decoded Modern/Forever profiles, normalized by ProfileIO, and compares
both cards and all six color buttons with the actual staged install colors.
"""
import re
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import HARNESS as SETUP, LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode


CHECK = r"""
local profiles = {}
MSUF_TryDecodeCompactString = function(text)
    decodes = decodes + 1
    return Copy(text == Suite.RetailProfileModuleCompact:sub(8) and MODERN or FOREVER)
end
profiles.classic = assert(Suite.ProfileIO.PrepareProfile(Suite.RetailProfileModuleCompact, false))
profiles.forever = assert(Suite.ProfileIO.PrepareProfile(Suite.ForeverFactoryModuleCompact, false))
local originals = Copy(profiles)
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Frame(parent)
    local frame = { parent = parent, shown = true, scripts = {} }
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetAllPoints(owner) self.allPoints = owner end
    function frame:SetTexture(value) self.texture = value end
    function frame:SetVertexColor(...) self.color = { ... } end
    function frame:SetTextColor(...) self.textColor = { ... } end
    function frame:SetText(value) self.text = value end
    function frame:SetFontObject(value) self.font = value end
    function frame:SetJustifyH(value) self.justify = value end
    function frame:SetScript(key, callback) self.scripts[key] = callback end
    function frame:SetShown(value) self.shown = value end
    function frame:IsVisible() return self.shown and (not parent or parent:IsVisible()) end
    function frame:CreateTexture() return Frame(self) end
    function frame:CreateFontString() return Frame(self) end
    return frame
end
CreateFrame = function(_, _, parent) return Frame(parent) end
local window, reads, choices = Frame(), 0, {}
window:SetSize(580, 470)
local function Label(parent) return Frame(parent) end
local function Card(parent, x, y, callback)
    local frame = Frame(parent)
    frame:SetSize(508, 64)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    frame.title, frame.detail, frame.mark = Frame(frame), Frame(frame), Frame(frame)
    frame:SetScript("OnClick", callback)
    return frame
end
local function Button(parent, x, y, width, text, callback)
    local frame = Frame(parent)
    frame:SetSize(width, 30)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    frame.caption = Frame(frame)
    frame.caption:SetText(text)
    frame:SetScript("OnClick", callback)
    return frame
end
local function Style(frame, selected) frame.selected = selected end
local function Preview(layout) reads = reads + 1; return profiles[layout] end
assert(loadfile(root .. "/MSUF_Suite/Core/InstallerProfiles.lua"))("MSUF_Suite", Suite)
Suite.InstallerProfiles.Build(window, Label, Card, Button, Style,
    function(layout) choices.layout = layout end, function(look) choices.look = look end, Preview)
local function Expected(layout, look)
    local copy = Copy(profiles[layout])
    if look ~= "authored" then assert(Suite.Suite.StyleProfile(copy, look)) end
    return copy.suite.modules.damageMeter
end
local function Color(actual, hex, alpha, message)
    local r, g, b = Suite.RGB(hex)
    assert(actual and math.abs(actual[1] - r) < 0.000001 and math.abs(actual[2] - g) < 0.000001
        and math.abs(actual[3] - b) < 0.000001, message .. ": incorrect RGB")
    if alpha then assert(actual[4] == alpha, message .. ": incorrect opacity") end
end
local function CheckCard(layout, look)
    local frame, expected = window[layout].preview, Expected(layout, look)
    assert(frame:IsVisible(), layout .. ": preview hidden")
    Color(frame.edge.color, expected.borderColor, 1, layout .. " border")
    Color(frame.background.color, expected.bgColor, expected.bgAlpha / 100, layout .. " background")
    Color(frame.fill.color, expected.barColor, 1, layout .. " accent")
    Color(frame.caption.textColor, expected.leftColor, nil, layout .. " text")
    assert(frame.parent == window[layout] and frame.point[4] >= 388
        and frame.point[4] + frame.width <= 508 and -frame.point[5] + frame.height <= 64,
        layout .. ": preview overlaps the detail or leaves its card")
end
local looks = { "authored", "midnight", "midnightDark", "foreverGlass", "cleanModern", "classColor" }
local slots = { "bgColor", "borderColor", "barColor", "leftColor" }
local paints = 0
for _, layout in ipairs({ "classic", "forever" }) do
    for _, look in ipairs(looks) do
        Suite.InstallerProfiles.Show(window, true, layout, look)
        CheckCard("classic", look)
        CheckCard("forever", look)
        assert(window[layout].selected, "layout highlight lost")
        for index, control in ipairs(window.colors) do
            local expected = Expected(layout, looks[index])
            assert(control.selected == (looks[index] == look), "palette highlight lost")
            assert(control.height == 38 and control.width == 80, "swatches did not get space")
            for slot, swatch in ipairs(control.swatches) do
                assert(swatch:IsVisible(), "palette swatch hidden")
                Color(swatch.color, expected[slots[slot]], 1, looks[index] .. " swatch " .. slot)
                assert(swatch.point[4] + swatch.width <= control.width
                    and swatch.point[5] + swatch.height <= control.height, "swatch leaves button")
            end
            control.scripts.OnClick()
            assert(choices.look == (looks[index] ~= "authored" and looks[index] or nil),
                "preview button selects a different palette")
        end
        paints = paints + 1
        Suite.InstallerProfiles.Show(window, false, layout, look)
        assert(not window.classic.preview:IsVisible() and not window.forever.preview:IsVisible(),
            "preview visible outside the profile page")
    end
end
assert(reads == paints * 2, "hidden pages or palettes request extra factory profiles")
assert(decodes == 2, "painting redecoded full profiles")
assert(Equal(originals, profiles), "preview modified the authored profiles")
assert(Suite.DB == nil and MSUF_DB == nil and MSUFSuiteDB == nil, "preview initialized saved settings")
assert(#reported == 0, tostring(reported[1]))
assert(Expected("forever", "authored").bgColor ~= Expected("forever", "cleanModern").bgColor,
    "fixture must distinguish authored Profile colors from Clean Modern")
local class = Expected("classic", "classColor").barColor
assert(class ~= "e6ecf2", "Class Style is not a character color")
print("Installer preview on " .. client .. ": " .. paints .. " layout/palette states, class " .. class
    .. ", two card colors, six swatch strips; no authored or saved-setting writes")
"""


def main():
    root = Path(sys.argv[1])
    core = root / "MSUF_Suite/Core"
    modern_source = (core / "RetailProfile.lua").read_text(encoding="utf-8")
    modern_compact = "".join(re.findall(r"\[\[(.*?)\]\]",
        modern_source.split("Suite.RetailProfileSkinCompact =")[0], re.S))
    forever_source = (core / "ForeverFactory.lua").read_text(encoding="utf-8")
    forever_compact = re.search(r"Suite.ForeverFactoryModuleCompact = \[\[(.*?)\]\]",
        forever_source, re.S).group(1)
    modern, forever = [decode(text, "MSUFM1:MSUF3:") for text in (modern_compact, forever_compact)]
    setup = SETUP.split("local S, defaults")[0].replace("ENVELOPE", lua_literal(modern), 1)
    for client in ("retail", "forever"):
        for character in ("WARLOCK", "PALADIN"):
            color = "r = 0.58, g = 0.51, b = 0.79" if character == "WARLOCK" else "r = 0.96, g = 0.55, b = 0.73"
            fixture = 'UnitClass = function() return "Test", "' + character + '" end\n'
            fixture += "C_ClassColor = { GetClassColor = function() return { "
            fixture += color + " } end }\n"
            script = fixture + setup + CHECK.replace("MODERN", lua_literal(modern), 1)
            script = script.replace("FOREVER", lua_literal(forever), 1)
            run = subprocess.run([LUA, "-", str(root), client, "RetailProfile.lua"], input=script,
                text=True, capture_output=True, errors="replace", cwd=root)
            if run.returncode:
                raise SystemExit(run.stdout + run.stderr)
            print(run.stdout.strip())


if __name__ == "__main__":
    main()
