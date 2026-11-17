local root = assert(arg[1])
local Secrets = assert(loadfile(root .. "/../MidnightSimpleUnitFrames-7.0/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
local secret = Secrets.New("number")
local locked = Secrets.New("boolean")
local combat, value, maximum, target, active, trade, power = false, secret, 5, "nameplate1", true, false, 4
local reads, geometry, created, frames, castReads = 0, 0, 0, {}, 0
local function Public(v) return not issecretvalue(v) end
local function RGB(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end
local function Frame(parent)
    created = created + 1
    local f = { parent = parent, alpha = 1, shown = true, textures = {}, scripts = {}, events = {}, height = 8 }
    function f:CanBeAccessedInContext() return not self.sealed end
    function f:IsProtected() return self.protected == true end
    function f:GetParent() return self.parent end
    function f:SetAlpha(a) self.alpha = a end
    function f:GetAlpha() return self.alpha end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(v) self.shown = v end
    function f:SetSize(w,h) geometry = geometry + 1 self.width, self.height = w,h end
    function f:SetWidth(w) geometry = geometry + 1 self.width = w end
    function f:GetHeight() return self.height end
    function f:SetHeight(h) self.height = h end
    function f:SetPoint(...) geometry = geometry + 1 end
    function f:ClearAllPoints() geometry = geometry + 1 end
    function f:SetAllPoints(p) self.anchor = p end
    function f:SetMinMaxValues(a,b) self.min, self.max = a,b end
    function f:SetValue(v) self.value = v end -- native sink, including opaque power
    function f:SetStatusBarTexture(p) self.texture = p end
    function f:SetStatusBarColor(...) self.color = {...} end
    function f:GetStatusBarTexture() return self.fill end
    function f:SetTexture(p) self.texture = p end
    function f:GetTexture() return self.texture end
    function f:SetColorTexture(...) self.color = {...} end
    function f:SetVertexColor(...) self.color = {...} end
    function f:SetVertexColorFromBoolean(v,yes,no) self.boolean, self.yes, self.no = v,yes,no end
    function f:SetTextColor(...) self.color = {...} end
    function f:GetTextColor() return unpack(self.color or {1,1,1,1}) end
    function f:SetTexCoord(...) self.coords = {...} end
    function f:EnableMouse() end
    function f:CreateTexture() local t = Frame(self) self.textures[#self.textures+1] = t return t end
    function f:SetScript(s,fn) assert(s ~= "OnUpdate", "extras added polling") self.scripts[s] = fn end
    function f:HookScript(s,fn) assert(s ~= "OnUpdate", "extras added polling") self.scripts[s] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e,u) assert(u == "player") self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    return f
end
function CreateFrame(_, _, parent) local f = Frame(parent) frames[#frames+1] = f return f end
function CreateColor(...) return {...} end
function hooksecurefunc(o,k,fn) local old = assert(o[k]); o[k] = function(self,...) old(self,...) fn(self,...) end end
function UnitIsUnit(unit,other) return unit == target and other == "target" end
function UnitCastingInfo() castReads=castReads+1 if active then return "Spell", "Spell", 123, 0, 1, trade, 1, locked end end
function UnitChannelInfo() end
NamePlateSetupOptions = { castBarToHealthBarSpacing = 2 }
PowerBarColor = { COMBO_POINTS = {r=1,g=.8,b=0}, RUNES = {r=.5,g=.5,b=.5} }
local plates, hover = {}, nil
C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit == "target" and target or unit] end }
local ns = { Public = Public, Finite = function(v) return Public(v) and type(v) == "number" end,
    InCombat = function() return combat end, Safety = { IsForbidden = function(f) return f.forbidden end },
    Client = { isForever = arg[2] == "Forever" }, RGB = RGB,
    ResolveTexture = function(p) if p and p ~= "" then return p end end }
local config = { look = 1, targetPatternTexture = "pattern", targetPatternAlpha = 35,
    castHealthColors = true, threatNameColor = true, threatFrameColor = true, enemyThreatLostColor = "ff0000",
    targetClassResource = true, targetClassResourceWidth = 100, targetClassResourceHeight = 5, targetClassResourceY = -6,
    castIconCombinedHeight = true, castSeamLine = true }
ns.NameplateStyle = { HighlightOrder = function() return { "target", "focus", "mouseover" } end,
    CreateBorder = function() return {} end, PaintBorder = function(b,_,size,hex) b.size,b.hex = size,hex end }
ns.HostBridge = { NameplateResource = function()
    return power, function() reads = reads + 1 return value end, function() return maximum end, "COMBO_POINTS"
end }
local p = { NS = ns, Mouseover = { IsHovered = function(f) return hover == f end },
    SkinAllowed = function() return true end, RoleKey = { ThreatLost = { color = "enemyThreatLostColor", enabled = "enemyThreatLostEnabled" } } }
local owner = { active = true, config = config, barSettings = {}, pendingPlates = {} }
local function Load(name) assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. name .. ".lua"))("Nameplates",p) end
Load("TargetResource")
Load("EasyFeatures")
local stop = Secrets.Watch(root .. "/MSUF_Suite_Nameplates/EasyFeatures.lua", {strict=true})
local uf, health, cast = Frame(), Frame(), Frame()
uf.name = Frame()
health.fill = Frame(health)
uf.HealthBarsContainer = { healthBar = health }
uf.CastBarsContainer = { castBar = cast }
cast.Icon, cast.unit = Frame(cast), "nameplate1"
cast.Icon.texture = 123
for _,name in ipairs({"HandleCastStart","UpdateInterruptibleState","PlayInterruptAnims","PlayFinishAnim","UpdateIconShown"}) do cast[name] = function() end end
plates.nameplate1 = { UnitFrame = uf }
p.EasyFeatures.Configure(owner)
p.EasyFeatures.Paint(uf,health,cast,"enemy","nameplate1",true,"ThreatLost")
assert(uf.name.color[1] == 1 and uf.name.color[2] == 0)
local tint, pattern
for _,t in ipairs(health.textures) do if t.texture == "pattern" then pattern=t elseif rawequal(t.boolean,locked) then tint=t end end
assert(tint and pattern and pattern.shown, "opaque cast lock or target pattern missing")
assert(rawequal(tint.boolean,locked), "cast lock was transformed in Lua")
assert(cast.Icon.alpha == 0, "combined icon did not replace the native icon visually")
p.EasyFeatures.SetOpacity(uf,.5)
assert(pattern.alpha == .175 and tint.alpha == .5, "layer fade discarded the configured pattern opacity")
cast:UpdateInterruptibleState(locked)
assert(tint.alpha == .5, "interruptibility change reset the health layer fade")
local castBefore = castReads
cast:UpdateIconShown()
cast:HandleCastStart()
assert(castReads == castBefore + 1, "one cast start performed duplicate spell queries")
local watcher = assert(frames[1])
local row = assert(frames[2])
assert(row.bars and #row.bars == 5 and rawequal(row.bars[1].value,secret))
local before, geom = reads, geometry
for _=1,100 do watcher.scripts.OnEvent(watcher,"UNIT_POWER_UPDATE","player","ENERGY") end
assert(reads == before and geometry == geom, "unrelated power rebuilt resources")
watcher.scripts.OnEvent(watcher,"UNIT_POWER_UPDATE","player","COMBO_POINTS")
assert(reads == before + 1 and geometry == geom, "matching power did more than one read or rebuilt geometry")
value = 0
watcher.scripts.OnEvent(watcher,"UNIT_POWER_UPDATE","player","COMBO_POINTS")
assert(row.alpha == 1 and row.bars[1].value == 0, "zero resource was treated as a missing resource")
active = false
cast:PlayFinishAnim()
assert(not tint.shown)
p.EasyFeatures.Paint(uf,health,cast,"enemy","nameplate1",true,"ThreatLost")
assert(not tint.shown, "native post-cast hold reactivated the cast health tint")
uf.name:SetTextColor(.2,.3,.4,1)
p.EasyFeatures.NativeName(uf)
assert(uf.name.color[2] == 0, "native name refresh erased threat tint")
p.EasyFeatures.Role(uf,nil)
assert(uf.name.color[1] == .2 and uf.name.color[2] == .3, "threat release restored an obsolete name color")
target = nil
p.EasyFeatures.Selection("target")
assert(not pattern.shown and row.alpha == 0)
target = "nameplate1"
p.EasyFeatures.Added()
assert(pattern.shown, "target plate reappearance missed its pattern")
combat, uf.protected = true,true
p.EasyFeatures.Restore(uf,true)
assert(row.alpha == 0, "protected owner orphaned visible resource pips")
combat, uf.protected = false,false
p.EasyFeatures.Restore(uf,true)
assert(not pattern.shown and cast.Icon.alpha == 1)
p.EasyFeatures.Paint(uf,health,cast,"enemy","nameplate2",true,nil)
assert(not pattern.shown, "pooled frame inherited the previous target")
owner.active = false
p.EasyFeatures.Configure(owner)
assert(not next(watcher.events), "disabled resources retained event subscriptions")
active = true
cast:HandleCastStart()
assert(not tint.shown, "disabled cast hook painted a stale frame")
assert(not owner.extras and not p.EasyFeatures.enabled, "disabled feature gates disagree")
local violations = stop()
assert(#violations == 0, table.concat(violations,"\n"))
print("Nameplate extras: opaque sinks, cast finish, native name refresh, target pooling, protected release and event budgets passed")
