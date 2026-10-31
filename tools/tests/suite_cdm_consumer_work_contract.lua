local root = assert(arg[1], "repository root required")
local measureOnly = arg[2] == "measure"
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local noop = function() end
local function wipe(t) for k in pairs(t) do t[k] = nil end end
local secrets = setmetatable({}, { __mode = "k" })
local secret = {}
secrets[secret] = true
local calls = { spell = 0, item = 0, secret = 0, overlay = 0, writes = 0, timers = 0 }
issecretvalue = function(value)
    calls.secret = calls.secret + 1
    return secrets[value] == true
end
local function Public(value) return not issecretvalue(value) end
local answer, power, itemAnswer, itemPower = true, false, false, true
C_Spell = { IsSpellUsable = function() calls.spell = calls.spell + 1; return answer, power end,
    IsSpellInRange = function() error("unexpected range query") end }
C_Item = { IsUsableItem = function() calls.item = calls.item + 1; return itemAnswer, itemPower end }
C_SpellActivationOverlay = { IsSpellOverlayed = function() calls.overlay = calls.overlay + 1; return false end }
local queued
C_Timer = { After = function(delay, callback)
    Check(delay == 0 and queued == nil, "new timer or uncoalesced scheduling")
    calls.timers = calls.timers + 1
    queued = callback
end }
local function Run()
    local fn = queued
    queued = nil
    if fn then fn() end
end
local S = { Public = Public, USABLE = { USABLE = 1, OUT_OF_RANGE = 2, UNUSABLE = 3, NO_POWER = 4 },
    USABLE_TINT = { [1] = { 1, 1, 1 }, [3] = { .4, .4, .4 }, [4] = { .4, .4, 1 } },
    NewUnitRunner = function()
        -- Error/retry behavior is exercised by the full boot contract with
        -- the real module Runtime; the budget counts Effects/Flush/Const.
        return function(_, _, _, fn, a, b) fn(a, b) end, function() return false end, noop
    end }
local C = { M = { active = true }, EMPTY = {}, wipe = wipe, plans = {}, views = {}, bars = {}, state = {},
    Const = { KIND = { COOLDOWN = 1 }, FAMILY = { AURA = 2 }, GLOW = {} },
    Index = { bags = {}, usable = {} }, Layout = { dirty = {}, Request = noop },
    Time = { Refresh = function() return false end }, Icons = { Texture = noop },
    Preview = { Glows = noop }, Diagnostics = {} }
-- Execute the production choice provider, including strict true semantics.
local source = assert(io.open(root .. "/MSUF_Suite_CooldownManager/Const.lua", "rb"))
local constText = source:read("*a"):gsub("\r\n", "\n"); source:close()
local pick = assert(constText:match("function K%.Pick%(ov, view, field%).-\nend"))
assert(loadstring("local K = ...\n" .. pick, "@" .. root .. "/MSUF_Suite_CooldownManager/Const.lua"))(C.Const)
local P = { NS = { CDM = { SLOTS = {} } }, Suite = S, CDM = C }
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Effects.lua"))("contract", P)
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Flush.lua"))("contract", P)
local view = { usable = true, behaviorGen = 1 }
C.views.a, C.views.b = view, view
C.bars.a, C.bars.b = { hidden = false }, { hidden = false }
local function Texture()
    return { SetVertexColor = function(_, r, g, b)
        Check(Public(r) and Public(g) and Public(b), "secret reached color")
        calls.writes = calls.writes + 1
    end }
end
local function Entry(id, slot, src)
    local entry = { key = tostring(id) .. slot .. (src or "s"), spell = id, base = id, id = id,
        src = src or "s", slot = slot, ov = {}, family = 1, cooling = false }
    entry.icon = { tex = Texture(), entry = entry }
    return entry
end
local entries = {}
for i = 1, 6 do
    entries[#entries + 1] = Entry(i, "a")
    entries[#entries + 1] = Entry(i, "b")
end
C.Index.usable = entries

local fx = C.Effects
if not measureOnly then
    local pick, visits = C.Const.Pick, 0
    C.Const.Pick = function(ov, bar, key) visits = visits + 1; return pick(ov, bar, key) end
    Check(not fx.ReadyRule({}, { readyGlow = true, fullChargeGlow = true }, true, false),
        "cooling incomplete spell became ready")
    Check(visits == 0, "impossible ready state still resolved settings")
    C.Const.Pick = pick
    local values = { false, true, "inherit" }
    for _, a in ipairs(values) do
        for _, f in ipairs(values) do
            for _, cooling in ipairs({ false, true }) do
                for _, full in ipairs({ false, true }) do
                    local ov = {}
                    if a ~= "inherit" then ov.readyGlow = a end
                    if f ~= "inherit" then ov.fullChargeGlow = f end
                    for _, fallback in ipairs({ false, true }) do
                        local bar = { readyGlow = fallback, fullChargeGlow = fallback }
                        local ready = a == "inherit" and fallback or a == true
                        local charge = f == "inherit" and fallback or f == true
                        local expected = (ready and not cooling) or (charge and full)
                        Check((fx.ReadyRule(ov, bar, cooling, full) and true or false) == expected,
                            "ready/charge override matrix changed")
                    end
                end
            end
        end
    end
end
local readyCalls, glowWrites = 0, 0
local refreshReady = fx.RefreshReady
fx.RefreshReady = function(entry)
    readyCalls = readyCalls + 1
    return refreshReady(entry)
end
-- Preserve the real ReadyWanted evaluator; this fake widget sink records
-- transitions without including the animation creation cost in warm work.
fx.SetGlow = function(icon, reason, on)
    if reason ~= "ready" then return end
    on = on and true or false
    if icon.readyOn ~= on then glowWrites = glowWrites + 1; icon.readyOn = on end
end
local function Pass()
    C.Flush.dirty.usable = true
    C.Schedule()
    Run()
end
local function BindAll()
    for i = 1, #entries do C.Flush.Mark(entries[i], "full") end
    Run()
end
local function ClearHidden()
    for i = 1, #entries do entries[i].hidden = false end
end
view.readyResources, view.readyGlow = true, true
BindAll()
if not measureOnly then
local initial = readyCalls
for _ = 1, 20 do Pass() end
if not measureOnly then
    Check(readyCalls == initial, "unchanged resource state repeated ReadyWanted work")
end
Check(entries[1].icon.readyOn == true, "warm ready state lost")
power, answer = true, false
Pass()
Check(not entries[1].icon.readyOn and entries[1].usableCode == 4, "resource loss did not clear ready glow/tint")
power, answer = false, true
Pass()
Check(entries[1].icon.readyOn and entries[1].usableCode == 1, "resource gain did not restore ready glow/tint")
-- Non-resource changes still have their own owner, even if the answer holds.
local entry = entries[1]
entry.cooling = true; fx.Update(entry)
Check(not entry.icon.readyOn, "cooldown start lost its ready edge")
entry.cooling = false; fx.Update(entry)
Check(entry.icon.readyOn, "cooldown end lost its ready edge")
entry.ov.fullChargeGlow, entry.ov.readyGlow = true, false
entry.fullyCharged = false; fx.RefreshReady(entry)
Check(not entry.icon.readyOn, "partial charges retained full-charge glow")
entry.fullyCharged = true; fx.RefreshReady(entry)
Check(entry.icon.readyOn, "full charges lost glow with unchanged resource answer")
entry.ov = {}; C.state.readyGlowCombat = true
C.state.inCombat = false; fx.CombatChanged(true)
C.Index.ready = { entry }; fx.CombatChanged(true)
Check(not entry.icon.readyOn, "combat gate did not hide ready glow")
C.state.inCombat = true; fx.CombatChanged(true)
Check(entry.icon.readyOn, "combat start did not restore ready glow")
C.state.readyGlowCombat = nil
-- Direct callers retain their refresh behavior; no implicit long-lived cache.
entry.cooling = true
local direct = readyCalls
fx.Usable(entry)
Check(readyCalls == direct + 1 and not entry.icon.readyOn, "direct caller lost fresh ready evaluation")
entry.cooling = false; fx.Usable(entry)
Check(entry.icon.readyOn, "direct ready catch-up lost")
-- Secret values are normalized, never compared or retained as readiness.
power, answer = secret, secret; Pass()
Check(entry.resourcesAvailable == nil and not entry.icon.readyOn and entry.usableCode == 1,
    "secret result changed readiness or tint semantics")
power, answer = false, true; Pass()
-- Explicit false beats the bar default; an absent override inherits it.
for _, inherited in ipairs({ false, true, 0, "yes" }) do
    view.readyResources = inherited
    for _, override in ipairs({ false, true, "inherit", 0, "yes" }) do
        entry.ov = {}
        if override ~= "inherit" then entry.ov.readyResources = override end
        local wanted = override == "inherit" and inherited == true or override == true
        local before = readyCalls
        fx.Usable(entry)
        Check(readyCalls == before + (wanted and 1 or 0), "resource override/inheritance changed")
    end
end
entry.ov = {}; view.readyResources = true
-- Individual hidden entries leave the ordinary sweep even with a visible bar.
for i = 1, #entries do entries[i].hidden = true; fx.Update(entries[i]) end
local reads = calls.spell
Pass()
if not measureOnly then Check(calls.spell == reads, "hidden individual icons still queried usability") end
-- A warm icon reappears with a new answer before any later usable broadcast.
power, answer = true, false
local showWrites = glowWrites
entry.hidden = false; fx.Update(entry)
Check(glowWrites == showWrites, "show briefly painted a stale ready glow")
Check(entry.usableCode == 4 and not entry.icon.readyOn, "warm show reused stale usability")
power, answer = false, true
entry.hidden = true; fx.Update(entry); Pass()
entry.hidden = false; fx.Update(entry)
Check(entry.usableCode == 1 and entry.icon.readyOn, "second warm show did not refresh")
-- Pool/rebind: old hidden marker cannot cause a second read on a new binding.
entry.hidden = true; fx.Update(entry); Pass()
entry.hidden = false; entry.ov = {}
reads = calls.spell
fx.Update(entry)
Check(calls.spell == reads + 1, "rebind plus show duplicated a native read")
-- Show and broadcast share the existing synchronous query maps.
entry.hidden = true; fx.Update(entry); Pass()
entry.hidden = false
reads = calls.spell
C.Flush.Mark(entry, "full"); C.Flush.dirty.usable = true; Run()
Check(calls.spell == reads + (measureOnly and 6 or 1), "show/broadcast failed to share the query scope")
ClearHidden(); BindAll()
-- Selection remains per domain and current exact ID on a show edge.
local item = Entry(1, "a", "i")
item.hidden = true; fx.Update(item)
entries[#entries + 1] = item; Pass(); entries[#entries] = nil
item.hidden = false; itemAnswer, itemPower = false, true
local items = calls.item
fx.Update(item)
Check(calls.item == items + 1 and item.usableCode == 4, "item show did not read current item answer")
-- Event eligibility retains the old cadence even when every icon is hidden.
entry.hidden = true
Check(fx.UsableShown(entry), "individual hidden icon changed event eligibility")
Pass(); Check(entry.usablePending == true, "broadcast did not defer hidden icon")
-- Preview displays simulated hidden entries; seed before painting, without
-- waiting for a later broadcast or changing the per-entry hide preference.
C.state.preview = true; entry.icon.simFx = true
answer, power = false, true
local previewReads = calls.spell
fx.Update(entry)
Check(calls.spell == previewReads + 1 and entry.usableCode == 4,
    "preview show retained stale hidden state")
previewReads = calls.spell; Pass()
Check(calls.spell > previewReads and not entry.usablePending, "preview icon was gated by old hidden state")
C.state.preview = nil; entry.icon.simFx = nil
Pass(); Check(entry.usablePending == true, "preview exit left hidden broadcast active")
-- Direct range/bar catch-up consumes the pending state; show must not read twice.
fx.Usable(entry)
entry.hidden = false
local directReads = calls.spell
fx.Update(entry)
Check(calls.spell == directReads, "show repeated a completed direct catch-up")
-- A new output decision must also be retried after a failed show read.
entry.hidden = true; fx.Update(entry); Pass()
entry.hidden = false
local usable = fx.Usable
fx.Usable = function() error("injected show read failure") end
local ok = pcall(fx.Update, entry)
fx.Usable = usable
if not measureOnly then Check(not ok, "show path skipped required refresh") end
answer, power = true, false
local retryReads = calls.spell
fx.Update(entry)
Check(calls.spell == retryReads + 1 and entry.usableCode == 1,
    "failed show read was marked complete before retry")
answer, power = true, false
ClearHidden(); BindAll()

end

local function Measure(label, hiddenCount, resources)
    view.readyResources, view.readyGlow = resources, resources
    for i = 1, #entries do entries[i].hidden = i <= hiddenCount; fx.Update(entries[i]) end
    local function Batch() for _ = 1, 200 do Pass() end end
    Batch()
    local vm = 0
    local function Tick()
        local info = debug.getinfo(2, "S")
        if info and info.source:find("/MSUF_Suite_CooldownManager/", 1, true) then vm = vm + 1 end
    end
    local beforeSpell, beforeItem, beforeSecret = calls.spell, calls.item, calls.secret
    local beforeReady, beforePaint, beforeGlow = readyCalls, calls.writes, glowWrites
    debug.sethook(Tick, "", 1); Batch(); debug.sethook()
    local native, nativeItem, secretCount = calls.spell-beforeSpell, calls.item-beforeItem, calls.secret-beforeSecret
    local ready, paints, glows = readyCalls-beforeReady, calls.writes-beforePaint, glowWrites-beforeGlow
    local function Allocation()
        collectgarbage("collect"); collectgarbage("stop"); Batch()
        local start = collectgarbage("count"); Batch()
        local used = collectgarbage("count")-start; collectgarbage("restart"); return used
    end
    local allocation = math.min(Allocation(), Allocation())
    print(string.format("consumer %s: vm=%d spell=%d item=%d secret=%d ready=%d paints=%d glows=%d allocationKiB=%.6f",
        label,vm,native,nativeItem,secretCount,ready,paints,glows,allocation))
    Check(nativeItem == 0 and paints == 0 and glows == 0 and allocation <= .01, "new native writes/domain/allocation")
    if not measureOnly then
        Check(native == (hiddenCount == 12 and 0 or hiddenCount == 6 and 600 or 1200), "hidden query budget")
        Check(ready == 0, "unchanged ready work budget")
        local budgets = { ["visible-plain"] = 320000, ["visible-resources"] = 327200,
            ["half-hidden"] = 198200, ["all-hidden"] = 69200 }
        Check(vm <= budgets[label], "consumer VM work budget")
        Check(secretCount == (hiddenCount == 12 and 0 or hiddenCount == 6 and 3600 or 7200),
            "consumer secret/native budget")
    end
end
Measure("visible-plain",0,false)
Measure("visible-resources",0,true)
Measure("half-hidden",6,true)
Measure("all-hidden",12,true)
print("CDM consumer work: " .. checks .. " checks passed")
