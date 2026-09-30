local root = assert(arg[1], "repository root required")
local S = {}
MSUFSuite = { Suite = S }
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
MSUF_SetFontChecked = nil

print("Suite text effects: Smooth, Sharp, Slug, shadows and reset passed")
