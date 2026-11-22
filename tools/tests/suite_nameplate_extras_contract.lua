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
    function f:SetPoint(...) self.point = { ... }; geometry = geometry + 1 end
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:ClearAllPoints() geometry = geometry + 1 end
    function f:SetAllPoints(p) self.anchor = p end
    function f:SetMinMaxValues(a,b) self.min, self.max = a,b end
    function f:SetValue(v) self.value = v end -- native sink, including opaque power
    function f:SetStatusBarTexture(p) self.texture = p end
    function f:SetStatusBarColor(...) self.color = {...} end
    function f:GetStatusBarTexture() return self.fill end
    function f:SetTexture(p) self.texture = p end
    function f:GetTexture() return self.texture end
    function f:SetBlendMode(mode) self.blendMode = mode end
    function f:SetGradient(...) self.gradient = { ... } end
    function f:AddMaskTexture(mask)
        assert(not combat and not self.mask, "duplicate mask or mask added in combat")
        self.mask = mask
    end
    function f:RemoveMaskTexture(mask)
        assert(not combat and self.mask == mask, "wrong mask or mask removed in combat")
        self.mask = nil
    end
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
ns.IsSecret = issecretvalue
ns.AnchorPoints, ns.AnchorLabels = { "CENTER" }, { "Center" }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Suite", ns)
ns.NameplateStyle = { HighlightOrder = function() return { "target", "focus", "mouseover" } end,
    CreateBorder = function() return {} end, PaintBorder = function(b,_,size,hex) b.size,b.hex = size,hex end }
local reaction, fighting, player = 4, false, false
function UnitIsPlayer() return player end
function UnitReaction() return reaction end
function UnitAffectingCombat() return fighting end
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
uf.isFriend, uf.isPlayer = false, false
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
config.enemyTargetPatternTexture, config.enemyTargetPatternAlpha = "enemy", 60
config.neutralTargetPatternTexture, config.neutralTargetPatternAlpha = "neutral", 0
config.friendlyTargetPatternTexture = ""
config.friendlyNpcTargetPatternTexture, config.friendlyNpcTargetPatternAlpha = "npc", 80
p.EasyFeatures.Configure(owner)
p.EasyFeatures.Paint(uf, health, cast, "enemy", "nameplate1", true)
assert(pattern.shown and pattern.texture == "neutral" and pattern.alpha == 0, "neutral scoped pattern or zero opacity lost")
p.EasyFeatures.SetOpacity(uf, 1)
fighting = true
p.EasyFeatures.UpdatePatternScope(uf, "nameplate1")
assert(pattern.shown and pattern.texture == "enemy" and pattern.alpha == .6, "engaged neutral did not use the enemy pattern")
uf.isFriend, uf.isPlayer, player = true, true, true
p.EasyFeatures.Paint(uf, health, cast, "friendly", "nameplate1", true)
assert(not pattern.shown, "an explicit empty player pattern inherited an old texture")
uf.isPlayer, player, reaction = false, false, 5
p.EasyFeatures.Paint(uf, health, cast, "friendly", "nameplate1", true)
assert(pattern.shown and pattern.texture == "npc" and pattern.alpha == .8, "friendly NPC inherited the player pattern")
config.friendlyNpcTargetPatternTexture, config.friendlyNpcHoverPatternTexture = "", "npc-hover"
config.friendlyNpcHoverPatternAlpha = 25
p.EasyFeatures.Configure(owner)
p.EasyFeatures.Paint(uf, health, cast, "friendly", "nameplate1", true)
assert(p.EasyFeatures.hoverPatterns and not pattern.shown, "hover-only pattern should register before the unit is hovered")
hover = uf
p.EasyFeatures.Hover(uf)
assert(pattern.shown and pattern.texture == "npc-hover" and pattern.alpha == .25)
hover = nil
p.EasyFeatures.Hover(uf)
assert(not pattern.shown, "leaving a hovered nameplate kept its pattern")
owner.active = false
p.EasyFeatures.Configure(owner)
assert(not next(watcher.events), "disabled resources retained event subscriptions")
active = true
cast:HandleCastStart()
assert(not tint.shown, "disabled cast hook painted a stale frame")
assert(not owner.extras and not p.EasyFeatures.enabled, "disabled feature gates disagree")
local violations = stop()
assert(#violations == 0, table.concat(violations,"\n"))
do
    local targetFrame = Frame()
    ns.HostBridge.TargetResourceFrame = function() return targetFrame end
    owner.active = true
    config.look, config.targetUnitFrameResource = 2, true
    config.targetUnitFrameResourceWidth, config.targetUnitFrameResourceHeight, config.targetUnitFrameResourceY = 114, 5, -8
    p.TargetResource.Configure(owner)
    local unitFrameRow
    for _, frame in ipairs(frames) do if frame.parent == targetFrame and frame.unitFrame then unitFrameRow = frame end end
    assert(unitFrameRow and unitFrameRow.point[1] == "TOPLEFT" and unitFrameRow.point[2] == targetFrame)
    assert(unitFrameRow.point[5] == -8 and unitFrameRow.width == 114)
    local called = reads
    value = secret
    watcher.scripts.OnEvent(watcher, "UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    assert(rawequal(unitFrameRow.bars[1].value, secret) and reads == called + 1)
    combat = true
    maximum = 6
    watcher.scripts.OnEvent(watcher, "UNIT_MAXPOWER", "player")
    assert(unitFrameRow.alpha == 0 and #unitFrameRow.bars == 5, "resource row resized during combat")
    combat = false
    watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_ENABLED")
    assert(unitFrameRow.alpha == 1 and #unitFrameRow.bars == 6, "resource row did not resume after combat")
    owner.active = false
    p.TargetResource.Configure(owner)
    assert(unitFrameRow.alpha == 0 and not next(watcher.events))
end

do
    local prefix = "enemy"
    Load("Modes")
    p.PlatePrefix = function() return prefix end
    ns.IsCombatLocked = ns.InCombat
    ns.HostBridge.GlossTexture = function() return not ns.Client.isForever and "gloss" or nil end
    assert(loadfile(root .. "/MSUF_Suite/Core/GlossMaterial.lua"))("MSUF_Suite", ns)
    assert(loadfile(root .. "/MSUF_Suite/Core/NameplateGradient.lua"))("MSUF_Suite", ns)
    Load("SlantedHealth")
    local shape, gradient = p.SlantedHealth, ns.NameplateStyle.Gradient
    local frame, hp = Frame(), Frame()
    local firstFill, secondFill, back = Frame(hp), Frame(hp), Frame(hp)
    hp.fill, hp.bgTexture = firstFill, back
    hp.CreateMaskTexture = function(self) return Frame(self) end
    local visual = { fill = Frame(hp), back = Frame(hp) }
    local function Writable(region) return not region.forbidden end
    shape.Configure({ look = 3, enemySlantedHealth = true })
    combat, frame.protected = true, true
    assert(not shape.Apply(frame, hp, true, Writable) and not firstFill.mask, "protected plate was clipped in combat")
    combat = false
    assert(shape.Apply(frame, hp, true, Writable) and firstFill.mask and firstFill.mask == back.mask)
    shape.Visual(hp, visual)
    assert(visual.slanted and visual.fill.mask == firstFill.mask and visual.slantRim)

    local finish = { healthGradientEnabled = true }
    local plan, pending = gradient.Plan(finish, "health"), {}
    combat = true
    gradient.PaintHealth(hp, visual, plan, frame, pending)
    assert(pending[frame] and not visual.gradient, "protected plate allocated a gradient in combat")
    combat = false
    gradient.PaintHealth(hp, visual, plan, frame, pending)
    assert(visual.gradient[2].mask == firstFill.mask, "health gradient covers the slanted edge")

    finish.healthGradientDirLeft, finish.healthGradientDirUp, finish.healthGradientDirDown = true, true, true
    finish.healthGlossEnabled = true
    plan = gradient.Plan(finish, "health", plan)
    gradient.PaintHealth(hp, visual, plan, frame, pending)
    local layers = { unpack(visual.gradient, 1, 4) }
    local glossCount = 0
    for _, texture in ipairs(hp.textures) do
        if texture.blendMode == "ADD" then
            layers[#layers + 1] = texture
            glossCount = glossCount + 1
        end
    end
    assert(glossCount == (ns.Client.isForever and 1 or 2), "test did not create the expected gloss textures")
    for _, texture in ipairs(layers) do
        assert(texture.shown and texture.mask == firstFill.mask and texture.anchor == firstFill)
    end

    hp.fill = secondFill
    assert(shape.Apply(frame, hp, true, Writable) and not firstFill.mask and secondFill.mask == back.mask)
    gradient.PaintHealth(hp, visual, plan, frame, pending)
    for _, texture in ipairs(layers) do
        assert(texture.mask == secondFill.mask and texture.anchor == secondFill)
    end

    gradient.PaintHealth(hp, visual, nil, frame, pending)
    prefix = "friendly"
    assert(shape.Apply(frame, hp, true, Writable) and not back.mask and not secondFill.mask
        and not visual.slanted and not visual.fill.mask and not visual.slantRim.shown)
    for _, texture in ipairs(layers) do assert(not texture.shown and not texture.mask) end
    gradient.PaintHealth(hp, visual, plan, frame, pending)
    for _, texture in ipairs(layers) do assert(texture.shown and not texture.mask) end
    prefix = "enemy"
    assert(shape.Apply(frame, hp, true, Writable) and secondFill.mask)
    for _, texture in ipairs(layers) do assert(texture.shown and texture.mask == secondFill.mask) end
end
print("Nameplate extras, clipped native health, and target UnitFrame resources passed")
