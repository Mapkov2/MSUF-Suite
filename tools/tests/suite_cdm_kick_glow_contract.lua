-- Six native glow styles on independently gated per-interrupt layers.
-- Optional argument 2 selects the MSUF 7.0 host; the standard sibling is the default.
local root = assert(arg[1], "repository root required")
-- Argument 3 selects the routine regression case; environment switches remain
-- available to earlier focused mutation/fixture invocations.
local mode = arg[3] or "normal"
assert(mode == "normal" or mode == "cold" or mode == "stale" or mode == "effects" or mode == "provider",
    "unknown CDM kick glow mode: " .. tostring(mode))
local file = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_contract.lua", "rb"))
local code = file:read("*a"):gsub("\r", "")
file:close()
code = code:sub(1, assert(code:find("------------------------------------------------------------------ enable: capture", 1, true)) - 1)
-- Upgrade only this fixture's sentinel implementation before addon load.
-- The mature runtime/client fixture and its assertions remain unchanged.
local start = assert(code:find("local SecretMT={}", 1, true))
local finish = assert(code:find("local SECRET_NUM,SECRET_BOOL,SECRET_TEXT=", start, true))
code = code:sub(1, start - 1) .. [=[
local hostRoot = (arg[2] or (root .. "/../MidnightSimpleUnitFrames-7.0")):gsub("\\", "/")
local Strict = dofile(hostRoot .. "/tools/tests/classpower_secrets.lua")
Strict.Install()
Strict.GUARD_NAMES.falsy.Public = true
local IsSecret = Strict.IsSecret
local Secret = Strict.New
]=] .. code:sub(finish)
local checks = [==[
do (function()
local NS = private.NS
Setter("SetClipsChildren", nil, true)
Setter("SetBlendMode", nil, true)
Setter("SetOffset", nil, true)
assert(C.KickMark, "the CDM has no per-interrupt glow consumer")
local revealed = setmetatable({}, { __mode = "k" })
local function Restricted(kind, value)
    local box = Secret(kind)
    revealed[box] = value
    return box
end
local function Reveal(value)
    if IsSecret(value) then return revealed[value] end
    return value
end
CreateColor = function(red, green, blue, alpha)
    return { GetRGBA = function() return red, green, blue, alpha end }
end
local raw, casting, channeling, restrictedDuration = false, false, false, false
UnitCastingDuration = function()
    if not casting then return nil end
    if restrictedDuration then return Restricted("table", true) end
    return {}
end
UnitChannelDuration = function() return channeling and {} or nil end
UnitCastingInfo = function() return nil, nil, nil, nil, nil, nil, nil, raw end
UnitChannelInfo = function() return nil, nil, nil, nil, nil, nil, raw end
local ready = { false, true }
local owner, callback, staleCallback, independent, active, registered, nativeSelections
local ids = { 96231, 31935 }
local resolvedSlots = (kickMode == "stale" or os.getenv("CDM_STALE_SLOTS")) and 0 or #ids
local api = { version = 2 }
function api.SlotCount() return resolvedSlots end
function api.Spell(index) return ids[index] end
function api.Register(key, fn, optIn)
    assert(not registered and optIn == true, "CDM must explicitly opt into its own engine lifecycle")
    owner, callback, staleCallback, independent, registered = key, fn, fn, optIn, true
    resolvedSlots = #ids
    return true
end
function api.Unregister(key)
    assert(key == owner)
    callback, registered, independent = nil, false, false
end
function api.SetActive(key, on) assert(key == owner); active = on end
-- Real v2 selector, with the native curve modeled only at its C boundary.
local adapter = {}
local adapterHost = { Require = function() return { Castbars = { KickReady = adapter } } end }
assert(loadfile(hostRoot .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady_Consumers.lua"))("MSUF", adapterHost)
local function NativeSelect(value, yes, no)
    nativeSelections = (nativeSelections or 0) + 1
    local selected = Reveal(value) and yes or no
    if IsSecret(value) then
        local _, _, _, alpha = selected:GetRGBA()
        return CreateColor(SECRET_NUM, SECRET_NUM, SECRET_NUM, Restricted("number", Reveal(alpha)))
    end
    return selected
end
local selectors = adapter.CreateConsumerAPI({
    SlotReady = function(index) return ready[index] end, IsSecret = IsSecret, SelectNative = NativeSelect,
    SlotCount = api.SlotCount, Slots = { { spellID = ids[1] }, { spellID = ids[2] } },
})
api.SelectSlotColor, api.Spell = selectors.SelectSlotColor, selectors.Spell
function api.SelectColor() error("aggregate readiness cannot select one interrupt") end
NS.HostBridge.KickReady = function() return api end
names[96231], names[31935] = "Rebuke", "Avenger's Shield"
known[96231], known[31935] = true, true
infos[11].spellID, infos[11].charges, infos[11].linkedSpellIDs = 96231, false, {}
infos[12].spellID, infos[12].hasAura = 31935, false
local config = S.Config(ID)
config.captured, config.defaultsVersion = true, Suite.CDM.DEFAULTS_VERSION
config.ess_procGlow, overlayed[96231] = true, true
module.config, module.context, module.active = config, S.NewContext(ID), true
if kickMode == "cold" or os.getenv("CDM_COLD_ON") then
    config.ess_kickMark, config.ess_procGlow, config.ess_readyGlow = true, false, false
    config.ess_fullChargeGlow, config.ess_assist, overlayed[96231] = false, false, false
    casting, ready[1], ready[2] = true, true, false
    module:Enable(); Run()
    local entry
    for _, candidate in ipairs(C.plans.ess.entries) do if candidate.spell == 96231 then entry = candidate end end
    local layer = assert(entry and entry.icon and entry.icon.kickGlow,
        "cold saved-on interrupt acquired no glow layer after icon sync")
    assert(not entry.icon.glow and not entry.icon.ants, "cold fixture had another base glow")
    assert(layer.cast:IsShown() and layer.proxy.glow:IsShown() and Reveal(layer.proxy.alpha) == 1,
        "cold saved-on interrupt did not immediately paint the existing target cast")
    module.active = false
    module:Disable()
    assert(not registered and not active and layer.proxy.alpha == 0 and layer.cast.alpha == 0,
        "cold saved-on disable retained readiness ownership")
    print("PASS cold saved-on kick: first icon sync, existing target cast, no base glow, immediate seed, safe release")
    return
end
module:Enable(); Run()
assert(not registered, "an off bar registered a provider consumer")
local primary, secondary
for _, entry in ipairs(C.plans.ess.entries) do
    if entry.spell == 96231 then primary = entry end
    if entry.spell == 31935 then secondary = entry end
end
assert(primary and primary.icon and secondary and secondary.icon, "real interrupt entries did not resolve")
assert(not primary.icon.kickGlow and not secondary.icon.kickGlow, "off created a glow layer")
local count, before = #all, nativeSelections or 0
for index = 1, 10 do C.KickMark.Rebuild() end
assert(#all == count and (nativeSelections or 0) == before and not registered, "off did native work or allocated frames")
-- An old provider remains usable by old consumers; this feature fails closed.
api.version = 1
config.ess_kickMark = true
module:Refresh(); Run()
assert(not registered and not primary.icon.kickGlow, "v1 aggregate host enabled a per-interrupt glow")
api.version = 2
module:Refresh(); Run()
assert(registered and independent, "matching enabled bar did not register")
local first, second = assert(primary.icon.kickGlow), assert(secondary.icon.kickGlow)
local parent = primary.icon:GetParent()
local pooledProxy, pooledGlow, pooledGate = first.proxy, first.proxy.glow, first.proxy.effectGate
assert(first.proxy.glow ~= primary.icon.glow, "kick glow shared the existing reason-union layer")
local listener
for _, frame in ipairs(all) do
    if frame.events.UNIT_SPELLCAST_INTERRUPTIBLE then listener = frame end
end
assert(listener and listener.events.PLAYER_TARGET_CHANGED, "target cast events missing")
local function Event(event) listener.scripts.OnEvent(listener, event, "target") end
local function Visible(layer)
    return layer.cast:IsShown() and layer.proxy.glow:IsShown()
        and Reveal(layer.cast.alpha) * Reveal(layer.proxy.alpha) > 0
end
local watch = (kickMode == "effects" and "Effects.lua") or (kickMode == "provider" and "provider")
    or os.getenv("CDM_KICK_WATCH") or "KickMark.lua"
local watchPath = root .. "/MSUF_Suite_CooldownManager/" .. watch
if watch == "provider" then watchPath = hostRoot .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady_Consumers.lua" end
local stopKick = Strict.Watch(watchPath, { strict = true })
casting = true
Event("UNIT_SPELLCAST_START")
assert(not Visible(first) and Visible(second), "secondary readiness incorrectly lit the recovering primary")
for style = 1, 6 do
    config.ess_glowStyle = style
    overlayed[96231] = true
    module:Refresh(); Run()
    assert(first.proxy.gStyle == style and second.proxy.gStyle == style, "selected glow style did not reach the isolated layer")
    assert(primary.icon:GetParent() == parent and first.cast:GetParent() == primary.icon,
        "kick glow reparented the original icon")
    assert(primary.icon.gProc and primary.icon.glow:IsShown(), "kick glow suppressed the existing proc glow")
    if style >= 5 then assert(first.proxy.glow.linesOn, "line style was replaced with a fixed border") end
end
ready[1], ready[2] = Restricted("boolean", false), Restricted("boolean", true)
raw, restrictedDuration = Restricted("boolean", false), true
Event("UNIT_SPELLCAST_START")
ready[1], ready[2] = Restricted("boolean", true), Restricted("boolean", false)
callback("projection")
assert(Visible(first) and not Visible(second), "projection notification retained aggregate/secondary readiness")
count, before = #all, writes
local selectedBefore = nativeSelections
callback("readiness")
assert(#all == count and writes - before == 4 and nativeSelections - selectedBefore == 4,
    "warm two-slot secret repaint exceeded its frozen four alpha writes/four curve selections: frames=" .. tostring(#all-count)
        .. " writes=" .. tostring(writes-before) .. " selects=" .. tostring(nativeSelections-selectedBefore))
raw = Restricted("boolean", true)
Event("UNIT_SPELLCAST_START")
assert(not Visible(first) and not Visible(second), "restricted uninterruptible cast showed a glow")
raw = Restricted("boolean", false)
Event("UNIT_SPELLCAST_START")
assert(Visible(first) and not Visible(second), "restricted interruptible edge did not recover")
casting, channeling = false, true
Event("UNIT_SPELLCAST_CHANNEL_START")
assert(Visible(first), "channel cast did not retain the readiness gate")
channeling = false
Event("UNIT_SPELLCAST_CHANNEL_STOP")
assert(not Visible(first) and not active, "cast stop retained readiness or a glow")
casting = true
Event("UNIT_SPELLCAST_START")
C.Effects.ResetIcon(primary.icon)
assert(not Visible(first) and first.proxy.alpha == 0 and first.cast.alpha == 0,
    "recycling retained a restricted alpha mask")
C.KickMark.Rebuild()
assert(Visible(first), "recycled layer did not rebind")
casting = false
Event("UNIT_SPELLCAST_STOP")
config.ess_kickMark = false
module:Refresh(); Run()
assert(not registered and not independent and not active and not Visible(first), "off retained provider/visual ownership")
assert(first.proxy.alpha == 0 and first.cast.alpha == 0, "off retained stale restricted masks")
assert(next(listener.events) == nil, "off retained target events")
local gateWrites = pooledGate.calls.SetShown or 0
local allGlows, inCombat = C.state.allGlowsCombat, C.state.inCombat
C.state.allGlowsCombat, C.state.inCombat = true, false
C.Effects.CombatChanged(false)
C.state.inCombat = true
C.Effects.CombatChanged(true)
assert((pooledGate.calls.SetShown or 0) == gateWrites,
    "disabled kick proxy remained in the shared combat gate walk")
C.state.allGlowsCombat, C.state.inCombat = allGlows, inCombat
C.Effects.CombatChanged(false)
count, before = #all, writes
staleCallback("readiness")
Event("UNIT_SPELLCAST_START")
assert(#all == count and writes == before, "a stale callback repainted a deactivated layer")
local violations = stopKick()
assert(#violations == 0, "secret read in kick consumer: " .. table.concat(violations, "\n"))
count = #all
casting, config.ess_kickMark = true, true
module:Refresh(); Run()
assert(registered and Visible(first), "re-enable did not restore the pooled layer")
assert(first.proxy == pooledProxy and first.proxy.glow == pooledGlow and first.proxy.effectGate == pooledGate and #all == count,
    "park/re-enable replaced pooled glow widgets")
module.active = false
module:Disable()
assert(not registered and not active and not Visible(first) and next(listener.events) == nil,
    "module disable retained provider, events or glow")
print("PASS CDM kick glow: six styles, isolated proc, per-slot projection, strict masks, channel, recycle, old host, off, release")
end)() end
]==]
local prefix = "local kickMode = " .. string.format("%q", mode) .. "\n"
assert(loadstring(prefix .. code .. "\n" .. checks, "@" .. root .. "/tools/tests/suite_cdm_kick_glow_fixture.lua"))()
