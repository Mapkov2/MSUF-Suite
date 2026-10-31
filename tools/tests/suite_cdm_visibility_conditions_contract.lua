local root = assert(arg[1], "repository root required")
-- Bar visibility conditions of the cooldown manager: the hide conditions on
-- the shared state drivers (resting, not in a group, flying, dead) and the
-- instance rule beside them, opacity while hidden, the mouseover probe and
-- the fades (MSUF_Suite_CooldownManager/Visibility.lua), their setting work
-- (Settings.lua), the inspection's reasons (MSUF_Suite/Core/CDMInspection.lua)
-- and the page's section and dependent controls. Defaults keep the driver
-- strings of the first release and cost nothing: no new event, no new frame,
-- no garbage, no widget call.
--   lua suite_cdm_visibility_conditions_contract.lua <suiteRoot>
local checks = 0
local function Check(value, message)
    checks = checks + 1
    if not value then error(message, 2) end
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

------------------------------------------------------------------ secrets
local SecretMT = {}
local function Raise(what) return function() error("secret value used: " .. what, 2) end end
for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__lt", "__le", "__eq",
    "__call", "__len" }) do
    SecretMT[key] = Raise(key)
end
SecretMT.__index = Raise("index"); SecretMT.__newindex = Raise("assignment")
local function Secret() return setmetatable({}, SecretMT) end
issecretvalue = function(value) return getmetatable(value) == SecretMT end

------------------------------------------------------------------ frames and animations
local frames, groups, calls = {}, {}, {}
local function Count(name) calls[name] = (calls[name] or 0) + 1 end
local function Writes() local n = 0; for _ in pairs(calls) do n = n + 1 end; return n end
local function ResetCalls() for key in pairs(calls) do calls[key] = nil end end
local Frame = {}
Frame.__index = Frame
function CreateFrame(kind, _, parent)
    Count("CreateFrame")
    local frame = setmetatable({ kind = kind, parent = parent, scripts = {}, attrs = {}, events = {}, alpha = 1,
        shown = true, visible = true, level = parent and parent.level + 1 or 1, mouse = true }, Frame)
    frames[#frames + 1] = frame
    return frame
end
function Frame:SetScript(key, fn) self.scripts[key] = fn end
function Frame:Show() Count("Show"); self.shown = true end
function Frame:Hide() Count("Hide"); self.shown = false end
function Frame:IsVisible() return self.shown and self.visible end
function Frame:SetAlpha(alpha) Count("SetAlpha"); self.alpha = alpha end
function Frame:GetAlpha() return self.alpha end
function Frame:SetAllPoints(target) Count("SetAllPoints"); self.allPoints = target end
function Frame:SetIgnoreParentAlpha(value) Count("SetIgnoreParentAlpha"); self.ignoreParentAlpha = value end
function Frame:EnableMouse(value) Count("EnableMouse"); self.mouse = value end
function Frame:EnableMouseMotion(value) Count("EnableMouseMotion"); self.motion = value end
function Frame:SetFrameLevel(level) Count("SetFrameLevel"); self.level = level end
function Frame:GetFrameLevel() return self.level end
function Frame:SetFrameStrata(strata) Count("SetFrameStrata"); self.strata = strata end
function Frame:RegisterEvent(event) Count("RegisterEvent"); self.events[event] = true end
function Frame:RegisterUnitEvent(event, unit) Count("RegisterUnitEvent"); self.events[event] = unit end
function Frame:UnregisterEvent(event) Count("UnregisterEvent"); self.events[event] = nil end
function Frame:SetAttribute(key, value)
    self.attrs[key] = value
    local handler = self.scripts.OnAttributeChanged
    if handler then handler(self, key, value) end
end
function Frame:GetAttribute(key) return self.attrs[key] end
local Group, Anim = {}, {}
Group.__index, Anim.__index = Group, Anim
function Frame:CreateAnimationGroup()
    Count("CreateAnimationGroup")
    local group = setmetatable({ owner = self, scripts = {}, progress = 0 }, Group)
    groups[#groups + 1] = group
    return group
end
function Group:SetToFinalAlpha(value) self.final = value end
function Group:CreateAnimation(kind) local anim = setmetatable({ kind = kind }, Anim); self.alphaAnim = anim; return anim end
function Group:SetScript(key, fn) self.scripts[key] = fn end
function Group:Play() Count("Play"); self.playing, self.progress = true, 0 end
function Group:Stop()
    Count("Stop")
    if not self.playing then return end
    self.playing = false
    if self.scripts.OnStop then self.scripts.OnStop(self) end
end
function Group:GetProgress() return self.progress end
function Anim:SetFromAlpha(value) self.from = value end
function Anim:SetToAlpha(value) self.to = value end
function Anim:SetDuration(value) self.duration = value end
-- The client ends a fade: the final alpha stays (SetToFinalAlpha), then OnFinished.
local function Finish(group)
    group.playing = false
    if group.final then group.owner.alpha = group.alphaAnim.to end
    if group.scripts.OnFinished then group.scripts.OnFinished(group) end
end
local function Enter(frame) frame.scripts.OnEnter(frame) end
local function Leave(frame) frame.scripts.OnLeave(frame) end

------------------------------------------------------------------ client state
local combat = false
InCombatLockdown = function() return combat end
local inPetBattle, vehicleUI, overrideBar = false, false, false
C_PetBattles = { IsInBattle = function() return inPetBattle end }
UnitHasVehicleUI = function() return vehicleUI end
C_ActionBar = { HasOverrideActionBar = function() return overrideBar end }
local instanceType, instanceReads = "none", 0
IsInInstance = function() instanceReads = instanceReads + 1; return instanceType ~= "none", instanceType end
-- The state driver manager: macro conditions resolve at registration and on
-- Tick(); "dead" asks the conditional's unit (@player here, else the target).
local cond = { combat = false, target = false, mounted = false, vehicleui = false, overridebar = false, petbattle = false,
    resting = false, group = false, flying = false, playerDead = false, targetDead = false }
local KNOWN = { combat = true, mounted = true, vehicleui = true, overridebar = true, petbattle = true, resting = true,
    flying = true }
local function Holds(group)
    local unit, ok = "target", true
    for token in group:gmatch("[^,]+") do
        if token:sub(1, 1) == "@" then
            unit = token:sub(2)
        elseif token == "exists" then
            ok = ok and unit == "target" and cond.target
        elseif token == "dead" then
            ok = ok and (unit == "player" and cond.playerDead or unit == "target" and cond.targetDead)
        elseif token == "nogroup" then
            ok = ok and not cond.group
        else
            assert(KNOWN[token], "unknown macro conditional " .. token)
            ok = ok and cond[token] == true
        end
    end
    return ok
end
local function Evaluate(expression)
    for clause in (expression .. ";"):gmatch("%s*([^;]-)%s*;") do
        local head, action = clause:match("^(.*%])%s*(%S+)$")
        if not head then return clause end
        for group in head:gmatch("%[(.-)%]") do
            if Holds(group) then return action end
        end
    end
end
local drivers, registered = {}, 0
RegisterAttributeDriver = function(frame, attr, values)
    assert(not combat, "a driver registered in combat")
    registered = registered + 1
    drivers[frame] = values
    local value = Evaluate(values)
    if frame:GetAttribute(attr) ~= value then frame:SetAttribute(attr, value) end
end
UnregisterAttributeDriver = function(frame)
    assert(not combat, "a driver unregistered in combat")
    drivers[frame] = nil
end
local function Tick()
    for frame, values in pairs(drivers) do
        local value = Evaluate(values)
        if frame:GetAttribute("msufvis") ~= value then frame:SetAttribute("msufvis", value) end
    end
end
-- The inspection asks the same conditionals.
local parsed = 0
SecureCmdOptionParse = function(expression) parsed = parsed + 1; return Evaluate(expression) end

------------------------------------------------------------------ suite core and catalog
MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsRetail = true, SupportsEvent = function() return true end } }
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
MSUF_EncodeCompactTable = function() return "" end
MSUF_TryDecodeCompactString = function() return nil end
UIParent = CreateFrame("Frame")
local NS = {}
for _, file in ipairs({ "Core/Platform.lua", "Core/Database.lua", "Core/SuiteCatalog.lua", "Core/HostBridge.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite/" .. file))("MSUF_Suite", NS)
end
local B = NS.CatalogBuild
local original = B.Module
B.Module = function(id, spec)
    if id ~= "cooldownManager" then return original(id, spec) end
    spec.id, spec.addon, spec.controls, spec.rules, spec.conflicts = id, "MSUF_Suite_CooldownManager", {}, {}, spec.conflicts or {}
    NS.SuiteCatalog[id] = spec
    NS.SuiteOrder[#NS.SuiteOrder + 1] = id
    B.Add(id, B.Bool("enabled", "Enable module", false))
    return spec
end
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManagerData.lua"))("MSUF_Suite", NS)
local CDM = NS.CDM
local rules = NS.SuiteCatalog.cooldownManager.rules
local VIS = CDM.VIS

------------------------------------------------------------------ catalog: one rule per bar, off by default
local NEW = {
    { "hideResting", "Hide while resting", false }, { "hideSolo", "Hide when not in a group", false },
    { "hideWorld", "Hide outside instances", false }, { "hideFlying", "Hide while flying", false },
    { "hideDead", "Hide while dead", false }, { "hiddenAlpha", "Opacity while hidden (percent)", 0 },
    { "hoverShow", "Show on mouseover", false }, { "fadeTime", "Fade time (seconds)", 0 },
}
for _, slot in ipairs(CDM.SLOTS) do
    local keys = CDM.KEYS[slot.key]
    for _, new in ipairs(NEW) do
        local rule = rules[keys[new[1]]]
        Check(rule and rule.label == new[2] and rule.default == new[3] and not rule.hidden,
            slot.key .. ": rule " .. new[1] .. " missing, renamed or not off by default")
    end
end
Check(rules.ess_hiddenAlpha.min == 0 and rules.ess_hiddenAlpha.max == 100 and rules.ess_hiddenAlpha.step == 5,
    "opacity while hidden is a percent in steps of 5")
Check(rules.ess_fadeTime.min == 0 and rules.ess_fadeTime.max == 2 and rules.ess_fadeTime.step == 0.1,
    "fade time runs from 0 to 2 seconds in tenths")
-- The menu order of the generated rules: the new ones follow "Hide in vehicles".
do
    local order = {}
    for i, rule in ipairs(NS.SuiteCatalog.cooldownManager.controls) do order[rule.key] = i end
    local at = order.c1_hideVehicle
    for i, new in ipairs(NEW) do
        Check(at and order["c1_" .. new[1]] == at + i, "custom bar 1: " .. new[1] .. " is not in place after Hide in vehicles")
    end
end

------------------------------------------------------------------ runtime
local mouseLog, usableRefresh = {}, 0
local M = { active = true }
local C = { M = M, state = { inCombat = false, preview = false }, views = {}, bars = {}, Diagnostics = {},
    Const = { VIS = VIS }, Index = { usable = {} }, Effects = { Usable = function() usableRefresh = usableRefresh + 1 end },
    Icons = { SetBarMouse = function(slot, on) mouseLog[#mouseLog + 1] = slot .. (on and "+" or "-") end },
    Auras = { SetBarMouse = function() end }, Layout = { Strata = function() end } }
local S = { Public = function(value) return not issecretvalue(value) end, CreateFrame = function(...) return CreateFrame(...) end }
local framesBeforeLoad = #frames
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Visibility.lua"))("MSUF_Suite_CooldownManager",
    { NS = NS, Suite = S, CDM = C })
local V = C.Visibility
Check(#frames == framesBeforeLoad, "loading the visibility plane created frames")
local function View(slot)
    local view = { key = slot }
    for suffix, key in pairs(CDM.KEYS[slot]) do view[suffix] = rules[key].default end
    return view
end
local ON = { "ess", "uti", "def", "ext", "buf", "bar" }
for _, slot in ipairs(CDM.SLOTS) do C.views[slot.key] = View(slot.key) end
for _, slot in ipairs(ON) do
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.level = 10
    C.bars[slot] = { key = slot, frame = frame }
end
local ess = C.views.ess
local essBar, utiBar = C.bars.ess, C.bars.uti
local function Listener()
    for _, frame in ipairs(frames) do if frame.scripts.OnEvent then return frame end end
end
local function Fire(event, ...) local frame = Listener(); frame.scripts.OnEvent(frame, event, ...) end

------------------------------------------------------------------ defaults: the first release's strings, no new cost
-- The driver strings of the first release, built the way it built them.
local OLD_BODY = { [1] = "show", [2] = "[combat] show; hide", [3] = "[combat][@target,exists] show; hide" }
local function OldExpression(vis, mounted, vehicle)
    if vis ~= 2 and vis ~= 3 and vis ~= 4 then vis = 1 end
    if vis == 4 then return "hide" end
    return "[petbattle] hide; " .. (vehicle and "[vehicleui][overridebar] hide; " or "") .. (mounted and "[mounted] hide; " or "")
        .. OLD_BODY[vis]
end
for _, vis in ipairs({ 1, 2, 3, 4, 9 }) do
    for _, mounted in ipairs({ false, true }) do
        for _, vehicle in ipairs({ false, true }) do
            local view = View("ess")
            view.vis, view.hideMounted, view.hideVehicle = vis, mounted, vehicle
            Check(V.Expression(view) == OldExpression(vis, mounted, vehicle),
                "default driver string changed: " .. V.Expression(view))
        end
    end
end
Check(V.Expression({ vis = 2, hideMounted = true, hideVehicle = true })
    == "[petbattle] hide; [vehicleui][overridebar] hide; [mounted] hide; [combat] show; hide", "first release string")
Check(V.Binding(View("ess")) == V.EVENTS, "an all-defaults bar needs no driver")
-- The default setup: one plain event frame for pet battles and vehicles,
-- nothing else; steady passes write nothing and allocate nothing.
V.ApplyAll()
local listener = Listener()
Check(#frames == framesBeforeLoad + #ON + 1 and listener, "all-defaults bars created a frame beyond the event frame")
local events = {}
for event in pairs(listener.events) do events[#events + 1] = event end
table.sort(events)
Check(table.concat(events, ",") == "PET_BATTLE_CLOSE,PET_BATTLE_OPENING_START,UNIT_ENTERED_VEHICLE,UNIT_EXITED_VEHICLE,"
    .. "UPDATE_OVERRIDE_ACTIONBAR,UPDATE_VEHICLE_ACTIONBAR", "all-defaults bars registered a new event: " .. table.concat(events, ","))
Check(next(V.fx) == nil and next(V.world) == nil and registered == 0 and instanceReads == 0,
    "all-defaults bars took an effect, a driver or an instance read")
for _, slot in ipairs(ON) do
    local bar = C.bars[slot]
    Check(bar.probe == nil and bar.fader == nil and bar.hidden == false and bar.frame.alpha == 1, "all-defaults bar " .. slot)
end
ResetCalls()
collectgarbage("collect"); collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 200 do
    V.ApplyAll(); V.CombatChanged(); Fire("PET_BATTLE_CLOSE"); Fire("UPDATE_OVERRIDE_ACTIONBAR")
end
local grown = collectgarbage("count") - before
collectgarbage("restart")
Check(grown < 1, "steady default visibility allocated " .. grown .. " KB")
Check(Writes() == 0, "steady default visibility made widget calls")

------------------------------------------------------------------ hide conditions on the drivers
local ALWAYS_VEHICLE = "[petbattle] hide; [vehicleui][overridebar] hide; "
local SINGLE = {
    { "hideResting", "[resting] hide; ", function(on) cond.resting = on end },
    { "hideSolo", "[nogroup] hide; ", function(on) cond.group = not on end },
    { "hideFlying", "[flying] hide; ", function(on) cond.flying = on end },
    { "hideDead", "[@player,dead] hide; ", function(on) cond.playerDead = on end },
}
cond.group = true
for _, case in ipairs(SINGLE) do
    local suffix, clause, Set = case[1], case[2], case[3]
    ess[suffix] = true
    Check(V.Binding(ess) == ALWAYS_VEHICLE .. clause .. "show", suffix .. ": driver string " .. tostring(V.Binding(ess)))
    V.Apply("ess")
    Check(V.expr.ess == ALWAYS_VEHICLE .. clause .. "show" and C.Diagnostics.DriverCount() == 1, suffix .. " needs its own driver")
    Check(essBar.hidden == false and essBar.frame.alpha == 1, suffix .. ": shown while it does not hold")
    Set(true); Tick()
    Check(essBar.hidden == true and essBar.frame.alpha == 0, suffix .. ": the condition does not hide the bar")
    Check(utiBar.hidden == false, suffix .. ": another bar hid with it")
    Set(false); Tick()
    Check(essBar.hidden == false and essBar.frame.alpha == 1, suffix .. ": the bar did not come back")
    ess[suffix] = false
    V.Apply("ess")
    Check(V.expr.ess == V.EVENTS and C.Diagnostics.DriverCount() == 0, suffix .. ": off, the bar went back to events")
end
-- A dead target is not the player.
ess.hideDead = true; V.Apply("ess")
cond.targetDead = true; Tick()
Check(essBar.hidden == false, "hide while dead reads the target")
cond.targetDead = false; ess.hideDead = false; V.Apply("ess")
-- Every condition with every rule, in driver order behind the first release's ones.
ess.vis, ess.hideMounted, ess.hideResting, ess.hideSolo, ess.hideFlying, ess.hideDead = VIS.COMBAT, true, true, true, true, true
Check(V.Expression(ess) == "[petbattle] hide; [vehicleui][overridebar] hide; [mounted] hide; [resting] hide; [nogroup] hide; "
    .. "[flying] hide; [@player,dead] hide; [combat] show; hide", "combined driver string " .. V.Expression(ess))
ess.vis = VIS.COMBAT_OR_TARGET
Check(V.Expression(ess) == "[petbattle] hide; [vehicleui][overridebar] hide; [mounted] hide; [resting] hide; [nogroup] hide; "
    .. "[flying] hide; [@player,dead] hide; [combat][@target,exists] show; hide", "combined target string")
ess.vis = VIS.HIDDEN
Check(V.Binding(ess) == V.HIDDEN and V.Expression(ess) == "hide", "Hidden stays static")
ess.vis = VIS.ALWAYS
V.Expression(ess)
collectgarbage("collect"); collectgarbage("stop")
before = collectgarbage("count")
for _ = 1, 200 do V.Expression(ess); V.Binding(ess) end
grown = collectgarbage("count") - before
collectgarbage("restart")
Check(grown < 1, "driver strings are built again on every call: " .. grown .. " KB")
ess.hideMounted, ess.hideResting, ess.hideSolo, ess.hideFlying, ess.hideDead = false, false, false, false, false
-- Combat parks the registration of a new condition, as for the first release's ones.
combat = true
ess.hideResting = true; V.Apply("ess")
Check(V.pending.ess and V.expr.ess == V.EVENTS, "combat registered a driver")
combat = false
V.FlushPending()
Check(not V.pending.ess and V.expr.ess == ALWAYS_VEHICLE .. "[resting] hide; show", "combat end applied the parked condition")
ess.hideResting = false; V.Apply("ess")

------------------------------------------------------------------ outside instances: a flag beside the driver
ess.hideWorld = true
V.Apply("ess")
Check(V.expr.ess == V.EVENTS and C.Diagnostics.DriverCount() == 0, "the instance rule needs no driver")
Check(listener.events.ZONE_CHANGED_NEW_AREA and instanceReads == 1, "the instance rule listens to zone changes and reads the instance")
Check(essBar.hidden == true and essBar.frame.alpha == 0, "outside an instance the bar hides")
for _, kind in ipairs({ "party", "raid", "scenario", "pvp", "arena" }) do
    instanceType = kind
    Fire("ZONE_CHANGED_NEW_AREA")
    Check(essBar.hidden == false and essBar.frame.alpha == 1, "inside a " .. kind .. " instance the bar shows")
    instanceType = "none"
    Fire("ZONE_CHANGED_NEW_AREA")
    Check(essBar.hidden == true, "leaving a " .. kind .. " instance hides the bar")
end
-- A loading screen applies every bar again and reads the instance.
instanceType = "party"
V.ApplyAll()
Check(essBar.hidden == false, "a loading screen did not read the instance")
-- Unknown kinds (housing and the like) and secret answers are outside.
instanceType = "neighborhood"; Fire("ZONE_CHANGED_NEW_AREA")
Check(essBar.hidden == true, "an unknown instance type counts as inside")
local realInstance = IsInInstance
IsInInstance = function() return Secret(), Secret() end
instanceType = "party"; V.ApplyAll()
Check(essBar.hidden == true, "a secret instance type counts as inside")
IsInInstance = realInstance
V.ApplyAll()
Check(essBar.hidden == false and utiBar.hidden == false, "the instance rule hid another bar")
-- It joins the driver: a combat bar inside an instance still waits for combat.
ess.vis = VIS.COMBAT; V.Apply("ess")
Check(essBar.hidden == true, "inside an instance the combat rule still hides")
cond.combat = true; C.state.inCombat = true; Tick()
Check(essBar.hidden == false, "combat in an instance shows the bar")
instanceType = "none"; Fire("ZONE_CHANGED_NEW_AREA")
Check(essBar.hidden == true, "outside an instance combat does not show the bar")
cond.combat = false; C.state.inCombat = false; Tick()
ess.vis, ess.hideWorld = VIS.ALWAYS, false
V.Apply("ess")
Check(not listener.events.ZONE_CHANGED_NEW_AREA and V.world.ess == nil and V.fx.ess == nil and essBar.hidden == false,
    "off, the instance rule left its event behind")
instanceType = "none"

------------------------------------------------------------------ opacity: hidden, faded, pointed at
-- One bar on a combat driver; the driver's answer and the combat state are set
-- directly, the composition is what this checks.
local function Paint(fields, inCombat, hidden)
    for key, value in pairs(fields) do ess[key] = value end
    V.Apply("ess")
    C.state.inCombat = inCombat
    V.state.ess = hidden and "hide" or "show"
    V.Paint("ess")
    return essBar.frame.alpha
end
local BASE = { vis = VIS.ALWAYS, alpha = 100, oocAlpha = 100, hiddenAlpha = 0, hoverShow = false, fadeTime = 0 }
local function Case(fields)
    local out = {}
    for key, value in pairs(BASE) do out[key] = value end
    for key, value in pairs(fields) do out[key] = value end
    return out
end
local ROWS = {
    -- fields, in combat, hidden by its rule, alpha, bar.hidden, label
    { {}, false, true, 0, true, "a plain hidden bar hides" },
    { { hiddenAlpha = 30 }, false, true, .3, false, "hidden: opacity while hidden" },
    { { hiddenAlpha = 30, oocAlpha = 20 }, false, true, .2, false, "hidden never brighter than the out-of-combat opacity" },
    { { hiddenAlpha = 30, alpha = 20 }, true, true, .2, false, "hidden never brighter than the opacity" },
    { { hiddenAlpha = 30, alpha = 80 }, true, false, .8, false, "shown in combat: the opacity" },
    { { hiddenAlpha = 30, oocAlpha = 50 }, false, false, .5, false, "shown out of combat: the out-of-combat opacity" },
    { { hoverShow = true }, false, true, 0, true, "mouseover alone still hides" },
    { { fadeTime = 0.5 }, false, true, 0, true, "a fade time alone still hides" },
}
for _, row in ipairs(ROWS) do
    Check(row[1].fadeTime or essBar.fader == nil, "a fade was made before the first fade time")
    local alpha = Paint(Case(row[1]), row[2], row[3])
    Check(Near(alpha, row[4]) and essBar.hidden == row[5], row[6] .. ": alpha " .. tostring(alpha))
end
Check(V.fx.ess, "an effect paints through the composed path")
-- The plain path keeps the first release's paint for the same settings.
Paint(Case({}), false, true)
Check(V.fx.ess == nil and essBar.hidden == true and essBar.frame.alpha == 0, "back on the plain paint")

------------------------------------------------------------------ mouseover: a motion-only probe
Paint(Case({ hoverShow = true, alpha = 80 }), false, true)
local probe = essBar.probe
Check(probe and probe.parent == essBar.frame and probe.allPoints == essBar.frame, "the probe covers the bar")
Check(probe.mouse == false and probe.motion == true and probe.ignoreParentAlpha == true,
    "the probe takes motion only and ignores the bar's alpha")
Check(probe.level == essBar.frame.level + 20, "the probe lies above the bar's icons and aura containers")
Check(essBar.hidden == true and essBar.frame.alpha == 0, "hidden until pointed at")
Enter(probe)
Check(Near(essBar.frame.alpha, .8) and essBar.hidden == false, "pointing shows the bar at its opacity")
Leave(probe)
Check(essBar.frame.alpha == 0 and essBar.hidden == true, "leaving hides it again")
-- Faded out of combat, pointed at: full opacity; in combat at full: no probe.
Paint(Case({ hoverShow = true, alpha = 90, oocAlpha = 40 }), false, false)
Check(Near(essBar.frame.alpha, .4) and probe.motion == true, "faded out of combat: the probe listens")
Enter(probe)
Check(Near(essBar.frame.alpha, .9), "pointing at a faded bar shows its opacity")
C.state.inCombat = true; V.CombatChanged()
Check(Near(essBar.frame.alpha, .9) and probe.motion == false and essBar.hover == nil,
    "at full opacity the probe stops listening and forgets the hover")
C.state.inCombat = false; V.CombatChanged()
Check(Near(essBar.frame.alpha, .4) and probe.motion == true, "faded again: the probe listens again")
-- Opacity while hidden and mouseover together: faded, then full.
Paint(Case({ hoverShow = true, hiddenAlpha = 25 }), false, true)
Check(Near(essBar.frame.alpha, .25) and essBar.hidden == false, "hidden and faded")
Enter(probe)
Check(essBar.frame.alpha == 1, "pointing at a faded hidden bar shows it")
Leave(probe)
-- The preview suspends the mouseover.
C.state.preview = true; V.Paint("ess")
Check(essBar.frame.alpha == 1 and probe.motion == false, "the preview shows the bar without the probe")
C.state.preview = false; V.Paint("ess")
Check(Near(essBar.frame.alpha, .25) and probe.motion == true, "leaving the preview")
-- Off: the probe stays pooled, silent.
local created = #frames
Paint(Case({}), false, true)
Check(probe.motion == false and V.fx.ess == nil and essBar.probe == probe, "mouseover off left the probe listening")
Paint(Case({ hoverShow = true }), false, true)
Check(#frames == created and probe.motion == true, "the probe is made once and kept")
Paint(Case({}), false, true)

------------------------------------------------------------------ fades: an Alpha animation, never a per-frame script
Paint(Case({}), false, false)
mouseLog = {}
ResetCalls()
Paint(Case({ fadeTime = 0.5 }), false, false)
Check(calls.Play == nil and calls.SetAlpha == nil, "an unchanged alpha fades or writes")
local fader
Paint(Case({ fadeTime = 0.5 }), false, true)
fader = essBar.fader
Check(fader and fader.owner == essBar.frame and fader.final == true and fader.playing, "a hide edge fades")
Check(fader.alphaAnim.kind == "Alpha" and fader.alphaAnim.from == 1 and fader.alphaAnim.to == 0
    and Near(fader.alphaAnim.duration, .5), "a full fade-out takes the fade time")
Check(essBar.hidden == false and #mouseLog == 0, "a fading bar keeps its mouse and containers until it is gone")
Finish(fader)
Check(essBar.hidden == true and essBar.frame.alpha == 0 and mouseLog[#mouseLog] == "ess-", "the end of a fade-out hides the bar")
-- A fade-in shows the bar at its start; a new target mid-fade goes on from there.
V.state.ess = "show"; V.Paint("ess")
Check(fader.playing and fader.alphaAnim.from == 0 and fader.alphaAnim.to == 1 and essBar.hidden == false
    and mouseLog[#mouseLog] == "ess+", "a fade-in shows the bar at its start")
fader.progress = .25
V.state.ess = "hide"; V.Paint("ess")
Check(fader.playing and Near(fader.alphaAnim.from, .25) and fader.alphaAnim.to == 0 and Near(fader.alphaAnim.duration, .125),
    "a new target mid-fade continues from the alpha on screen, for its share of the fade time")
Finish(fader)
-- Partial changes take their share of the time.
ess.oocAlpha = 60; V.state.ess = "show"; V.Paint("ess")
Check(Near(fader.alphaAnim.duration, .3) and Near(fader.alphaAnim.to, .6), "a partial fade takes its share")
Finish(fader)
Check(Near(essBar.frame.alpha, .6), "the fade ends at its target")
-- Instant: the preview, an invisible bar, and switching the fade off mid-fade.
C.state.preview = true; V.Paint("ess")
Check(not fader.playing and essBar.frame.alpha == 1, "the preview switches at once")
C.state.preview = false; V.Paint("ess")
Finish(fader)
essBar.frame.visible = false
V.state.ess = "hide"; V.Paint("ess")
Check(not fader.playing and essBar.frame.alpha == 0 and essBar.hidden == true, "an invisible bar switches at once")
essBar.frame.visible = true
V.state.ess = "show"; V.Paint("ess")
Check(fader.playing, "fading in")
fader.progress = .5
Paint(Case({ oocAlpha = 60 }), false, false)
Check(not fader.playing and Near(essBar.frame.alpha, .6) and essBar.hidden == false and V.fx.ess == nil,
    "switching the fade off ends a running fade at its target")
-- An outside stop (the client stopping the group) settles the bar too.
Paint(Case({ fadeTime = 1, oocAlpha = 60 }), false, true)
fader.playing = false; fader.scripts.OnStop(fader)
Check(essBar.frame.alpha == 0 and essBar.hidden == true, "an outside stop settles the bar at its target")
Paint(Case({}), false, false)
for _, frame in ipairs(frames) do Check(frame.scripts.OnUpdate == nil, "a frame runs a per-frame script") end
for _, group in ipairs(groups) do Check(group.scripts.OnUpdate == nil, "a fade runs a per-frame script") end

------------------------------------------------------------------ release
ess.hoverShow, ess.hideWorld = true, true
V.Apply("ess"); V.state.ess = "hide"; V.Paint("ess")
Check(probe.motion == true and listener.events.ZONE_CHANGED_NEW_AREA, "effects on before the release")
M.active = false
V.ReleaseAll()
Check(probe.motion == false and next(V.fx) == nil and next(V.world) == nil and not listener.events.ZONE_CHANGED_NEW_AREA,
    "the release left a probe, an effect or the zone event")
M.active = true
ess.hoverShow, ess.hideWorld = false, false
V.ApplyAll()

------------------------------------------------------------------ settings: each new setting repaints only
do
    local flush = { dirty = {}, sync = {}, style = {}, behavior = {}, visible = {} }
    local RC = { M = {}, Flush = flush, Diagnostics = {}, wipe = function(t) for k in pairs(t) do t[k] = nil end end,
        Const = { KIND = CDM.KIND, AURA_KINDS = {} } }
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Settings.lua"))("MSUF_Suite_CooldownManager",
        { NS = NS, Suite = S, CDM = RC })
    local work = RC.Diagnostics.SettingWork
    for _, new in ipairs(NEW) do
        local flags = {}
        for flag in pairs(work[new[1]] or {}) do flags[#flags + 1] = flag end
        Check(table.concat(flags, ",") == "visible", new[1] .. " must repaint visibility only, got " .. table.concat(flags, ","))
    end
end

------------------------------------------------------------------ inspection: which condition hides the bar
do
    local config = { enabled = true }
    for key, rule in pairs(rules) do config[key] = rule.default end
    config.enabled = true
    NS.Suite = { Config = function() return config end, Availability = function() return true end,
        states = { cooldownManager = {} } }
    NS.Text = function(text) return text end
    assert(loadfile(root .. "/MSUF_Suite/Core/CDMInspection.lua"))("MSUF_Suite", NS)
    local function Reason() return NS.Suite.CDMInspectionRow("ess").reason end
    parsed, instanceReads = 0, 0
    Check(not Reason():find("resting", 1, true) and parsed == 0 and instanceReads == 0,
        "defaults: no new reason and no live read")
    local LINES = {
        { "hideResting", "Hidden while resting.", "Hidden while resting. You are resting now.", function(on) cond.resting = on end },
        { "hideSolo", "Hidden when not in a group.", "Hidden when not in a group. You are not in a group now.",
            function(on) cond.group = not on end },
        { "hideWorld", "Hidden outside instances.", "Hidden outside instances. You are outside an instance now.",
            function(on) instanceType = on and "none" or "raid" end },
        { "hideFlying", "Hidden while flying.", "Hidden while flying. You are flying now.", function(on) cond.flying = on end },
        { "hideDead", "Hidden while dead.", "Hidden while dead. You are dead now.", function(on) cond.playerDead = on end },
    }
    for _, line in ipairs(LINES) do
        config["ess_" .. line[1]] = true
        line[4](false)
        local text = Reason()
        Check(text:find(line[2], 1, true) and not text:find(line[3], 1, true), line[1] .. ": the rule is not explained")
        line[4](true)
        Check(Reason():find(line[3], 1, true), line[1] .. ": the inspection does not say it hides the bar now")
        line[4](false)
        config["ess_" .. line[1]] = false
    end
    config.ess_hiddenAlpha, config.ess_hoverShow = 30, true
    local text = Reason()
    Check(text:find("Hidden, this bar fades to 30% opacity instead of disappearing.", 1, true)
        and text:find("Pointing at this bar shows it while it is hidden or faded.", 1, true), "fade and mouseover reasons")
    -- A secret instance type counts as outside, as at runtime.
    config.ess_hideWorld = true
    IsInInstance = function() return Secret(), Secret() end
    Check(Reason():find("You are outside an instance now.", 1, true), "a secret instance type broke the inspection")
    IsInInstance = realInstance
end

------------------------------------------------------------------ page: the visibility section and dependent controls
do
    local file = assert(io.open(root .. "/MSUF_Suite_Options/Pages/CooldownManager.lua", "rb"))
    local text = file:read("*a"):gsub("\r", ""); file:close()
    local list = text:match('{ id = "visibility", title = "Visibility", suffixes = (%b{}) }')
    local order = {}
    for suffix in (list or ""):gmatch('"(%w+)"') do order[#order + 1] = suffix end
    Check(table.concat(order, ",") == "vis,oocAlpha,hideMounted,hideVehicle,hideResting,hideSolo,hideWorld,hideFlying,"
        .. "hideDead,hiddenAlpha,hoverShow,fadeTime,tooltips", "visibility section order: " .. table.concat(order, ","))
    file = assert(io.open(root .. "/MSUF_Suite_Options/Pages/CooldownManagerInspection.lua", "rb"))
    text = file:read("*a"):gsub("\r", ""); file:close()
    local fields = text:match("local FIELDS = (%b{})") or ""
    for _, new in ipairs(NEW) do
        if new[1] ~= "fadeTime" then Check(fields:find('"' .. new[1] .. '"', 1, true), "the inspection note ignores " .. new[1]) end
    end
    -- The gate: opacity while hidden needs a hide rule, mouseover and fade
    -- time a hide rule or a fade out of combat.
    local config = {}
    for key, rule in pairs(rules) do config[key] = rule.default end
    local P = { Suite = { CDM = CDM, Public = S.Public }, S = {}, T = {}, Tr = function(t) return t end,
        catalog = { cooldownManager = { rules = rules } }, Gates = {}, SearchPreparers = {},
        Get = function(_, key) return config[key] end }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/CooldownManagerData.lua"))("MSUF_Suite_Options", P)
    local Page, Gate = P.CDMPage, P.Gates.cooldownManager
    Page.selected = "ess"
    local function Allowed(suffix) return Gate({ key = CDM.KEYS.c1[suffix], suffix = suffix }) end
    Check(Allowed("hiddenAlpha") and Allowed("hoverShow") and Allowed("fadeTime"), "defaults hide in vehicles: all usable")
    config.ess_hideVehicle = false
    local ok, why = Allowed("hiddenAlpha")
    Check(ok == false and why == "Nothing hides or fades this bar." and not Allowed("hoverShow") and not Allowed("fadeTime"),
        "nothing hides: the dependent controls grey out with a reason")
    config.ess_oocAlpha = 50
    Check(not Allowed("hiddenAlpha") and Allowed("hoverShow") and Allowed("fadeTime"), "a fade out of combat enables mouseover and fades")
    config.ess_oocAlpha = 100
    for _, suffix in ipairs({ "hideMounted", "hideResting", "hideSolo", "hideWorld", "hideFlying", "hideDead" }) do
        config["ess_" .. suffix] = true
        Check(Allowed("hiddenAlpha") and Allowed("hoverShow"), suffix .. " does not count as a hide rule")
        config["ess_" .. suffix] = false
    end
    config.ess_vis = VIS.COMBAT
    Check(Allowed("hiddenAlpha"), "a Show rule counts as a hide rule")
    Check(Allowed("hideResting") ~= false, "the hide conditions themselves are never greyed")
end

print(("suite_cdm_visibility_conditions_contract: ok (%d checks)"):format(checks))
