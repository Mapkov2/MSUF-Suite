local root = assert(arg[1], "repository root required")
local S = {}
MSUFSuite = { Suite = S }
-- The font file check (Suite.FontFileApplied) lives in the always loaded core.
MSUF_NS = {}
assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", MSUFSuite)
-- The "Font rendering" values (NS.FontRendering) come from the core catalog.
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", MSUFSuite)
GameFontHighlightSmall = { GetFont = function() return "Native.ttf", 12, "" end }
local scaleFlags
MSUF_ApplyFontScaleAnimationMode = function(_, flags) scaleFlags = flags end
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})

local font = { calls = {} }
function font:SetFont(path, size, flags)
    self.calls[#self.calls + 1] = { path, size, flags }
    self.path, self.size, self.flags = path, size, flags
    return true
end
function font:SetShadowColor(r, g, b, a) self.shadow = { r, g, b, a } end
function font:SetShadowOffset(x, y) self.offset = { x, y } end

S.SetStyledFont(font, "Chosen.ttf", 14, "THICKOUTLINE", 2, true, 60, 2)
assert(font.flags == "THICKOUTLINE,MONOCHROME" and font.shadow[4] == 0.6
    and font.offset[1] == 2 and font.offset[2] == -2 and scaleFlags == font.flags,
    "Sharp rendering or custom shadow was not applied")
S.SetStyledFont(font, "Chosen.ttf", 14, "THICKOUTLINE", 3, true, 60, 2)
assert(font.flags == "OUTLINE,SLUG" and font.shadow[4] == 0
    and font.offset[1] == 0 and scaleFlags == font.flags,
    "Slug did not suppress thick outline and shadow")
S.SetStyledFont(font, "Chosen.ttf", 14, "", 3, false, 100, 1)
assert(font.flags == "SLUG", "Slug without outline has unexpected flags")
S.SetStyledFont(font, "Chosen.ttf", 14, "OUTLINE", 1, false, 100, 1)
assert(font.flags == "OUTLINE" and font.shadow[4] == 0 and font.offset[1] == 0,
    "Default rendering did not restore shadow-free text")
-- The current host owns cold-font recovery; keep its requested face and flags.
local cold = { calls = 0 }
function cold:SetFont(path, size, flags)
    self.path, self.size, self.flags, self.calls = path, size, flags, self.calls + 1
    return false
end
MSUF_SetFontChecked = function(fs, path, size, flags) fs:SetFont(path, size, flags); return true end
assert(S.SetFont(cold, "Selected.ttf", 14, "OUTLINE") == "OUTLINE")
assert(cold.path == "Selected.ttf" and cold.calls == 1, "cold font application silently changed the user's face")

-- A client font string: SetFont returns false for a file the client cannot
-- load and keeps the font it had; GetFont names the file in use, nil before
-- any font; SetText raises without a font (SimpleFontStringAPIDocumentation
-- on live, ptr2 and forever).
local INSTALLED = { ["Native.ttf"] = true, ["Interface\\AddOns\\Media\\Selected.ttf"] = true }
local function ClientFontString(refusedFlags)
    local fs = { calls = {} }
    function fs:SetFont(path, size, flags)
        self.calls[#self.calls + 1] = { path, size, flags }
        if not INSTALLED[path] or refusedFlags and flags == refusedFlags then return false end
        self.font = { path, size, flags }
        return true
    end
    function fs:GetFont() if self.font then return unpack(self.font) end end
    function fs:SetText(text)
        if not self.font then error("FontString:SetText(): Font not set") end
        self.text = text
    end
    return fs
end
-- The host setters of every Classic host on the Mainline family
-- (MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua): the client's own answer.
MSUF_SetFontChecked = function(fs, path, size, flags) return fs:SetFont(path, size, flags or "") ~= false end
local gone = ClientFontString()
assert(S.SetFont(gone, "Interface\\AddOns\\SharedMedia_Removed\\gone.ttf", 13, "OUTLINE") == "OUTLINE")
assert(gone.font and gone.font[1] == "Native.ttf" and gone.font[2] == 13 and gone.font[3] == "OUTLINE",
    "a font the host reported as refused left the string without the native fallback")
gone:SetText("visible")
local plain = ClientFontString("OUTLINE,SLUG")
assert(S.SetFont(plain, "Missing.ttf", 12, "OUTLINE,SLUG") == "" and plain.font[1] == "Native.ttf"
    and plain.font[3] == "", "a refused font and refused flags did not end on the plain native font")
-- false while the string shows the requested file anyway keeps that face.
local applied = ClientFontString()
applied.font = { "interface/addons/media/selected.ttf", 14, "OUTLINE" }
MSUF_SetFontChecked = function() return false end
assert(S.SetFont(applied, "Interface\\AddOns\\Media\\Selected.ttf", 14, "OUTLINE") == "OUTLINE"
    and #applied.calls == 0 and applied.font[1] == "interface/addons/media/selected.ttf",
    "a face that applied despite a false answer was replaced by the fallback")
MSUF_SetFontChecked = nil
-- Older hosts without the setter keep the native fallback.
local native = ClientFontString()
assert(S.SetFont(native, "Missing.ttf", 11, "") == "" and native.font[1] == "Native.ttf",
    "a refused font without the host setter kept no font")

print("Suite text effects: Smooth, Sharp, Slug, shadows and reset passed")
