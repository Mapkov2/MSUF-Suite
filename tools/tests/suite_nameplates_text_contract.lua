local root = assert(arg[1])
local secret = {}
local private = { NS = { NameplateStyle = {}, Safety = { IsForbidden = function() return false end } }, Suite = {
    Public = function(value) return not rawequal(value, secret) end,
    Finite = function(value) return type(value) == "number" end,
    SetFont = function(region, ...) region:SetFont(...) end,
} }
assert(loadfile(os.getenv("SUITE_NAMEPLATES_TEXT_OVERRIDE") or root .. "/MSUF_Suite_Nameplates/Text.lua"))("nameplates", private)
local Text = private.Text
local region = { path = "native", size = 10, flags = "", shadow = { 0, 0, 0, .6 }, offset = { 1, -1 }, reads = 0, writes = 0 }
function region:GetFont() self.reads = self.reads + 1; return self.path, self.size, self.flags end
function region:SetFont(path, size, flags)
    self.writes = self.writes + 1
    if self.reject then return false end
    self.path, self.size, self.flags = path, size, flags or ""
end
function region:GetShadowColor() return unpack(self.shadow) end
function region:GetShadowOffset() return unpack(self.offset) end
function region:SetShadowColor(...) self.shadow = { ... } end
function region:SetShadowOffset(...) self.offset = { ... } end
local style = { enabled = true, flags = "", shadow = false }
local function Apply(size, reads, writes)
    region.reads, region.writes = 0, 0
    Text.Apply(region, style, size or 0)
    assert(region.reads == reads and region.writes == writes,
        "font apply: GetFont=" .. region.reads .. ", SetFont=" .. region.writes .. "; expected " .. reads .. ", " .. writes)
end
Apply(0, 1, 0)
Apply(0, 1, 0)
Apply(12, 2, 1)
Apply(12, 1, 0)
-- Blizzard resets a pooled region: capture its latest font and shadow.
region.path, region.size, region.flags, region.shadow = "locale", 11, "SLUG", { .1, .2, .3, .8 }
Apply(12, 2, 1)
assert(Text.originals[region][1] == "locale" and Text.originals[region][2] == 11 and Text.originals[region][3] == "SLUG")
Apply(12, 1, 0)
Text.Restore(region)
assert(region.path == "locale" and region.size == 11 and region.flags == "SLUG" and region.shadow[4] == .8,
    "restore lost Blizzard's recaptured font/shadow")
region.path, region.size, region.flags = "pooled", 9, ""
Apply(0, 1, 0)
assert(Text.originals[region][1] == "pooled" and not Text.originals[region].restored, "pool reuse skipped recapture")
style.shadow = true
Apply(0, 1, 0)
assert(region.shadow[4] == 1, "shadow-only change was skipped")
region.shadow[4] = .5
Text.Invalidate(region)
Apply(0, 1, 0)
assert(region.shadow[4] == 1, "Blizzard shadow invalidation was skipped")
region.reject = true
Apply(15, 2, 1)
assert(Text.originals[region].appliedSize == 9, "failed SetFont cached the requested size")
region.reject = false
Apply(15, 2, 1)
style.enabled = false
Apply(0, 0, 1)
assert(region.size == 9, "disabled style did not restore the native font")
style.enabled, region.path = true, secret
Apply(0, 1, 0)
assert(rawequal(region.path, secret), "restricted font was written")
print("Suite nameplate text: one no-write GetFont; native resets, pool reuse, failed writes, shadows and restoration passed")
