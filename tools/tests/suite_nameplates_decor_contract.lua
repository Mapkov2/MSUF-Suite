local root = assert(arg[1])
local secret, combat, target, focus = {}, false, "nameplate1", "nameplate1"
local created, calls = {}, 0
local function Public(v) return not rawequal(v, secret) end
local function NoValues() error("decoration queried gameplay values or restricted geometry") end
UnitHealth, UnitHealthMax, UnitPower = NoValues, NoValues, NoValues
local nativeStyle = "0"
NamePlateSetupOptions = { useClassicHealthBar = false }
C_CVar = { GetCVar = function(key)
    if key == "nameplateStyle" then return nativeStyle end
    if key == "nameplateSelectedScale" then return "1.1" end
end }
UnitIsUnit = function(unit, other)
    local value = other == "target" and target or focus
    if rawequal(value, secret) then return secret end
    return unit == value
end
local Frame
Frame = function(kind, parent)
    local f = { kind = kind, parent = parent, shown = true, points = {}, hooks = {}, width = 100, height = 20 }
    created[#created + 1] = f
    function f:IsForbidden() return self.forbidden or self.parent and self.parent:IsForbidden() or false end
    function f:IsProtected() return self.protected or self.parent and self.parent:IsProtected() or false end
    local function Write(self)
        assert(not self:IsForbidden(), "forbidden region written")
        assert(not (combat and self:IsProtected()), "protected write in combat")
        calls = calls + 1
    end
    function f:SetShown(v) Write(self); self.shown = v end
    function f:Show() self:SetShown(true) end
    function f:Hide() self:SetShown(false) end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:SetPoint(...) Write(self); self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() Write(self); self.points = {} end
    function f:SetAllPoints(owner) Write(self); self.allPoints = owner end
    function f:SetWidth(value) Write(self); self.width = value end
    function f:SetHeight(value) Write(self); self.height = value end
    function f:SetSize(w, h) Write(self); self.width, self.height = w, h end
    function f:SetAlpha(v) Write(self); self.alpha = v end
    function f:SetColorTexture(...) Write(self); self.color = { ... } end
    function f:SetVertexColor(...) Write(self); self.vertex = { ... } end
    function f:SetTexture(v) Write(self); self.texture = v end
    function f:SetBlendMode(v) Write(self); self.blend = v end
    function f:HookScript(key, fn) self.hooks[key] = fn end
    function f:CreateTexture() return Frame("Texture", self) end
    f.GetWidth, f.GetHeight, f.GetPoint, f.GetRect = NoValues, NoValues, NoValues, NoValues
    if kind == "StatusBar" then
        f.fill = Frame("Texture", f)
        function f:GetStatusBarTexture() return self.fill end
        function f:SetStatusBarTexture(v) Write(self); self.fill.texture = v end
        function f:SetMinMaxValues(lo, hi) Write(self); self.min, self.max = lo, hi end
        function f:SetValue(v) Write(self); self.value = v end
    end
    return f
end
CreateFrame = function(kind, _, parent) return Frame(kind, parent) end
local NS = { Client = { isForever = false, isMainline = true }, Text = function(v) return v end,
    Public = Public, IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function(f) return f and f:IsForbidden() end },
    RGB = function(hex) return tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255, tonumber(hex:sub(5,6),16)/255 end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("Core", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("Core", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Nameplates.lua"))("Core", NS)
local config = {}
for key, rule in pairs(NS.SuiteCatalog.nameplates.rules) do config[key] = rule.default end
config.nativeStyle, config.barGeometry = 2, 2
assert(NS.SuiteCatalog.nameplates.cvars.nameplateSelectedScale)
local Draw = assert(NS.NameplateStyle.Decor)
assert(not Draw.Plan(config, "enemy").active and not Draw.Plan(config, "friendly").active)
assert(Draw.TargetScale(config, 1.1) == 1.1)
config.targetScaleEnabled, config.targetScalePercent = true, 130
assert(Draw.TargetScale(config, 1.1) == 1.3)
local function Plate(kind)
    local uf = Frame("Button")
    local health, cast = Frame(kind or "StatusBar", uf), Frame("StatusBar", uf)
    uf.HealthBarsContainer = { healthBar = health }
    return uf, health, cast
end
config.enemyOuterFrame, config.enemyShadowEnabled = true, true
config.enemyGlowEnabled, config.enemyGlowMode = true, 2
config.enemyThresholdEnabled, config.enemyFocusMarker = true, true
config.enemyTextureEnabled, config.enemyFillTexture = true, 2
config.enemyBorderStyle = 2
local p = Draw.Plan(config, "enemy")
local uf, health, cast = Plate()
local s = { parent = uf, health = health, cast = cast }
Draw.Paint(s, p, true, true, true)
assert(s.combined.outer.host:IsVisible() and not s.single.outer.host:IsVisible())
assert(s.thresholdBar.value == .2 and s.threshold.points[1][3] == "TOPRIGHT")
assert(s.focusMarker.points[1][3] == "LEFT" and s.focusMarker.points[1][4] == -56)
assert(s.finish.allPoints == health.fill and s.finish.blend == "MOD" and s.finish.texture:find("Stripes",1,true))
local count, before = #created, calls
for _ = 1, 100 do Draw.Paint(s, p, true, true, true) end
assert(#created == count and calls == before, "warm paint created objects or rewrote unchanged native properties")
Draw.Paint(s, p, false, false, false)
assert(s.single.outer.host:IsVisible() and not s.combined.outer.host:IsVisible())
assert(not s.focusMarker:IsShown() and not s.single.glow.host:IsShown())
Draw.Paint(s, p, true, true, true)
assert(s.combined.shadow.host:IsShown())
config.enemyOuterFrame = false
p = Draw.Plan(config, "enemy")
Draw.Paint(s, p, true, true, true)
assert(not s.combined.shadow.host:IsShown(), "disabled joined frame retained stale decoration")
for _, key in ipairs({ "HealthWidthDelta", "HealthOffsetX", "HealthOffsetY", "CastOffsetX", "CastOffsetY",
    "CastIconOffsetX", "CastIconOffsetY" }) do
    for _, value in ipairs({ -20, 20 }) do
        config["enemy" .. key], config.enemyOuterFrame = value, true
        p = Draw.Plan(config, "enemy")
        assert(not p.joined, "offset bars must use separate enclosing frames")
        Draw.Paint(s, p, true, true, true)
        assert(s.single.outer.host:IsVisible() and s.castOnly.outer.host:IsVisible())
        assert(s.castOnly.outer.first == cast and s.castOnly.outer.last == cast)
        config["enemy" .. key] = 0
    end
end
p = Draw.Plan(config, "enemy")
assert(p.joined, "style lifecycle control must start with join-eligible geometry")
Draw.Paint(s, p, true, true, true)
assert(s.combined.outer.host:IsVisible(), "style lifecycle control did not start joined")
NamePlateSetupOptions.useClassicHealthBar = true
nativeStyle, config.nativeStyle = "6", 8
Draw.Paint(s, p, true, true, true)
assert(s.castOnly.outer.host:IsVisible() and s.single.outer.host:IsVisible(),
    "native style change reused stale joined geometry")
NamePlateSetupOptions.useClassicHealthBar = false
nativeStyle, config.nativeStyle = "0", 2
NS.Client.isForever, config.barGeometry = true, 1
assert(not Draw.Plan(config,"enemy").joined, "native Forever badge reservation needs separate frames")
NS.Client.isForever, config.barGeometry = false, 2
health.shown = false
for _, region in ipairs({ s.single.outer.host, s.castOnly.outer.host, s.threshold, s.focusMarker, s.finish }) do
    assert(not region:IsVisible() or region == s.castOnly.outer.host, "names-only health retained ghost decoration")
end
health.shown, cast.shown = true, false
-- Preview bars are Buttons, not StatusBars; only the explicit sample fill exists.
local pu, pb, pc = Plate("Button")
local ps = { parent = pu, health = pb, cast = pc, fillSource = pb:CreateTexture() }
Draw.Paint(ps, Draw.Plan(config,"enemy"), true, true, false)
assert(ps.finish.allPoints == ps.fillSource, "preview queried StatusBar-only API on Button")
local private = { NS = NS }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Decor.lua"))("Nameplates", private)
local owner = { config = config, active = true, pendingPlates = {} }
local Runtime = private.Decor
Runtime.Configure(owner)
combat = true
local cu, ch, cc = Plate()
local oldCount = #created
Runtime.Paint(cu, ch, cc, "enemy", "nameplate1")
assert(#created > oldCount and not owner.pendingPlates[cu], "new unprotected combat plate did not receive decoration")
local function GlowCount(bar)
    local count = 0
    for _, region in ipairs(created) do
        if region.kind == "Frame" and region.parent == bar and region.alpha == .25 and region:IsVisible() then
            count = count + 1
        end
    end
    return count
end
assert(GlowCount(ch) > 0)
target = "nameplate2"
Runtime.TargetChanged(nil)
assert(GlowCount(ch) == 0, "target change without target arrows retained the previous glow")
target, focus = secret, secret
Runtime.Paint(cu, ch, cc, "enemy", "nameplate1")
cc.shown = secret
cc.hooks.OnHide(cc)
target, focus, cc.shown = "nameplate1", "nameplate1", true
local protected, ph, pc = Plate()
protected.protected = true
oldCount = #created
Runtime.Paint(protected, ph, pc, "enemy", "nameplate2")
assert(owner.pendingPlates[protected] and #created == oldCount, "protected combat plate was mutated")
cu.forbidden = true
Runtime.Paint(cu, ch, cc, "enemy", "nameplate1")
Runtime.Restore(ch)
cu.forbidden, combat = false, false
Runtime.Disable()
assert(not Runtime.inUse)
print("Nameplate decoration: native/preview painters, lifecycle, guarded combat and zero-write warm paint passed")
