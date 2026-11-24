-- Exercise a single pooled Blizzard FontString with independent text, vertex and region alpha.
local root = assert(arg[1])
local secret = {}
local function Public(value) return not rawequal(value, secret) end
local function Finite(value) return Public(value) and type(value) == "number" end
local friendlyR, friendlyG, friendlyB = .1, .65, .9
local NS = {
    AnchorPoints = {}, AnchorLabels = {}, Client = { isForever = true },
    Public = Public, Finite = Finite, IsSecret = function(v) return not Public(v) end,
    InCombat = function() return false end, IsCombatLocked = function() return false end,
    Safety = { IsForbidden = function(r) return r.forbidden == true end },
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16)/255, tonumber(hex:sub(3, 4), 16)/255, tonumber(hex:sub(5, 6), 16)/255
    end,
    HostBridge = { NPCNameColor = function() return friendlyR, friendlyG, friendlyB end },
}
local P = { NS = NS, Suite = NS }
local globalHooks = {}
function hooksecurefunc(object, method, hook)
    if type(object) == "string" then globalHooks[object] = method return end
    local previous = assert(object[method], method)
    object[method] = function(...) previous(...); hook(...) end
end
function CreateFrame() error("coloring allocated an overlay") end
local R = {}
R.__index = R
local function Region()
    return setmetatable({ alpha = 1, shown = true, alphaWrites = 0, colorWrites = 0, textWrites = 0,
        visibilityWrites = 0, r = .7, g = .6, b = .5, a = .85, vr = .9, vg = .8, vb = .7, va = .75 }, R)
end
function R:IsProtected() return false end
function R:CanBeAccessedInContext() return not self.blocked end
function R:IsForbidden() return false end
function R:GetAlpha() return self.alpha end
function R:SetAlpha(value) self.alpha, self.alphaWrites = value, self.alphaWrites + 1 end
function R:GetText() return self.text end
function R:SetText(value) self.text, self.textWrites = value, self.textWrites + 1 end
function R:IsShown() return self.shown end
function R:SetShown(value) self.shown, self.visibilityWrites = value, self.visibilityWrites + 1 end
function R:Hide() self:SetShown(false) end
function R:Show() self:SetShown(true) end
function R:GetTextColor() return self.r, self.g, self.b, self.a end
function R:GetVertexColor() return self.vr, self.vg, self.vb, self.va end
function R:SetTextColor(...)
    local r, g, b, a = ...
    self.r, self.g, self.b, self.textArgs = r, g, b, select("#", ...)
    if self.textArgs >= 4 then self.a = a or 1 end
    self.colorWrites = self.colorWrites + 1
end
function R:SetVertexColor(...)
    local r, g, b, a = ...
    self.vr, self.vg, self.vb, self.va, self.vertexArgs = r, g, b, a or 1, select("#", ...)
    self.colorWrites = self.colorWrites + 1
end
function R:SetFontObject(font) self.r, self.g, self.b, self.a = unpack(font) end
function R:GetFont() return "Fonts/FRIZQT__.TTF", 14, "OUTLINE" end
function R:CreateFontString() error("coloring allocated a second FontString") end
function R:SetIsTarget(value) self.isTarget = value end

assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Suite", NS)
local dir = root .. "/MSUF_Suite_Nameplates/"
assert(loadfile(dir .. "Modes.lua"))("Plates", P)
assert(loadfile(dir .. "FriendlyNames.lua"))("Plates", P)
local N = P.FriendlyNames
local config = { friendly = true, enemy = true, enabled = true, look = 3, friendlyNPCs = 5,
    friendlyNpcPlateNameTypeColor = true, neutralPlateNameOnly = true, neutralPlateNameTypeColor = true,
    enemyNeutralColor = "e5db00", friendlyNamesOnly = P.Mode.ALL_NAMES_ONLY }
local owner = { active = true, friendlyNames = {}, activeUnits = {}, pendingPlates = {}, config = config }
N.Bind(owner)
N.ConfigureNameOnly()
local uf = Region()
uf.unit, uf.isFriend, uf.isPlayer = "nameplate7", true, false
uf.name, uf.HealthBarsContainer = Region(), Region()
local name, bar = uf.name, Region()
uf.HealthBarsContainer.healthBar = bar
local function Apply(kind)
    P.UnitKinds[uf] = kind
    owner.activeUnits[uf.unit] = uf
    local active, player = N.ApplyNameOnly(uf, uf.unit, nil, nil, kind)
    if player then N.PaintNameOnly(uf) end
    return active
end
local function CheckRGB(r, g, b)
    assert(name.r == r and name.g == g and name.b == b, "wrong native glyph tint")
    -- Blizzard colors names through the vertex: the NPC color is carried there as well.
    assert(name.vr == r and name.vg == g and name.vb == b, "the NPC color missed the native vertex channel")
end

name.text, name.alpha = "Mature Paletusk", .64
assert(Apply("neutralNpc") and uf.HealthBarsContainer.alpha == 0)
CheckRGB(229/255,219/255,0)
-- Both setters reach a FontString's alpha: the vertex is written like Blizzard writes it, RGB only.
assert(name.alpha == .64 and name.a == .85 and name.vertexArgs == 3, "name-only tint changed native opacity")
assert(name.alphaWrites == 0 and name.visibilityWrites == 0 and name.textWrites == 0 and uf.name == name,
    "coloring took over native text, region or visibility")
-- Blizzard's separate color channels can be reset while selecting and deselecting.
name:SetTextColor(.3, .4, .5, .56)
name:SetVertexColor(.95, .2, .1, .42)
bar:SetIsTarget(true)
CheckRGB(229/255,219/255,0)
assert(name.a == .56 and name.vertexArgs == 3, "selection changed native opacity")
config.enemyNeutralColor = "782fd4"
N.ConfigureNameOnly()
assert(Apply("neutralNpc"))
bar:SetIsTarget(false)
CheckRGB(120/255,47/255,212/255)
name:SetAlpha(0)
name:Hide()
N.PaintNameOnly(uf)
assert(not name:IsShown() and name.alpha == 0, "coloring overrode a native hide")
name:SetAlpha(.78)
name:Show()
name:SetText(secret)
N.PaintNameOnly(uf)
assert(rawequal(name.text, secret) and name.alpha == .78, "coloring rewrote native text or opacity")
local beforeWrites = name.colorWrites
for _ = 1, 1000 do N.PaintNameOnly(uf) end
assert(name.colorWrites == beforeWrites and name.alphaWrites == 2 and name.textWrites == 1 and name.visibilityWrites == 2,
    "stable name paints rewrote native presentation")
N.RestoreNameOnly(uf)
assert(name.r == .3 and name.g == .4 and name.b == .5 and name.a == .56, "pool release lost native font color")
assert(name.vr == .95 and name.vg == .2 and name.vb == .1 and name.vertexArgs == 3, "pool release lost native vertex color")
assert(name.alpha == .78 and name.alphaWrites == 2 and uf.HealthBarsContainer.alpha == 1, "pooled health bar inherited hidden text")

-- Same frame, new friendly NPC, then back to ordinary native bars.
uf.unit = "nameplate11"
name:SetText("Wheatley")
name:SetTextColor(.8, .7, .4, .92)
name:SetVertexColor(1, 1, 1, .9)
assert(Apply("friendlyNpc"))
CheckRGB(friendlyR,friendlyG,friendlyB)
name:SetFontObject({1,1,1,.6})
CheckRGB(friendlyR,friendlyG,friendlyB)
friendlyR, friendlyG, friendlyB = .7, .4, .9
N.RefreshFriendlyPalette(true)
CheckRGB(friendlyR,friendlyG,friendlyB)
config.friendlyNPCs = P.Mode.SHOW
N.ConfigureNameOnly()
assert(not Apply("friendlyNpc") and uf.HealthBarsContainer.alpha == 1 and name.shown and name.text == "Wheatley")
name:SetTextColor(.2, .7, .4, .9)
name:SetVertexColor(.4, .5, .6, .7)
bar:SetIsTarget(true)
assert(name.r == .2 and name.vr == .4 and name.a == .9 and name.va == .7 and name.alpha == .78,
    "inactive name-only hooks altered the health-bar name")

local available, updates = nil, 0
function UnitName() return available end
function UnitIsUnit(a,b) return a == b end
function securecallfunction(fn, ...) return fn(...) end
function CompactUnitFrame_UpdateName(frame)
    updates = updates + 1
    if frame:ShouldShowName() then frame.name:SetText(available); frame.name:Show() else frame.name:Hide() end
    globalHooks.CompactUnitFrame_UpdateName(frame)
end
function uf:ShouldShowName() return not self.widgetsOnlyMode and (not self.isSimplified or self.isTarget) end
uf.optionTable = {}
config.friendlyNPCs = 5
N.ConfigureNameOnly()
name:SetText(nil)
assert(Apply("friendlyNpc"))
N.RepairMissing(uf, uf.unit)
available = "Flight Master"
N.RepairMissing(uf, uf.unit)
assert(name.shown and name.text == available and name.alpha == .78)
CheckRGB(friendlyR,friendlyG,friendlyB)
local completed = updates
N.RepairMissing(uf, uf.unit)
assert(updates == completed, "native updater repainted an already populated name")
N.RestoreNameOnly(uf)
uf.isPlayer, uf.isSimplified, uf.isTarget = true, true, false
P.UnitKinds[uf] = "friendlyPlayer"
name:Hide()
available = "Friendly Player"
function bar:SetIsTarget(target) uf.isTarget = target end
N.RepairMissing(uf, uf.unit)
bar:SetIsTarget(true)
assert(name.shown and name.text == available and name.alpha == .78, "pooled simplified player stayed hidden on selection")
bar:SetIsTarget(false)
assert(not name.shown, "explicit simplification no longer hides a deselected player")
uf.widgetsOnlyMode, uf.isTarget = true, true
N.RepairMissing(uf, uf.unit)
assert(not name.shown)
uf.widgetsOnlyMode, uf.isSimplified = false, false
local publicCalls = updates
available = secret
function uf:ShouldShowName() error("restricted identity branches must stay native") end
name:SetText(nil)
name:Show()
N.RepairMissing(uf, uf.unit)
assert(rawequal(name.text, secret) and updates == publicCalls, "opaque pending name lost at the native text sink")
name:Hide()
N.RepairMissing(uf, uf.unit)
assert(not name.shown and updates == publicCalls, "a hidden restricted name was forced visible")
owner.activeUnits[uf.unit] = nil
bar:SetIsTarget(true)
assert(updates == publicCalls, "repainted a released nameplate")
print("native name-only lifecycle: palette, dual tint, opacity, selection, reuse, late names and warm writes passed")
