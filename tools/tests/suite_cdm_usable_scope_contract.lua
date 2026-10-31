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
local capturedSpell, capturedItem
local originalUsable = C.Effects.Usable
C.Effects.Usable = function(entry, cache)
    if cache then
        if entry.src == "i" then capturedItem = cache else capturedSpell = cache end
    end
    return originalUsable(entry, cache)
end
local function Empty(cache)
    return cache and next(cache.seen) == nil and next(cache.usable) == nil and next(cache.noPower) == nil
end
local function Pass(rebind, broadcast)
    if rebind then
        for i = 1, #entries do
            local entry = entries[i]
            entry.icon.fxEntry = nil
            C.Flush.Mark(entry, "full")
        end
    end
    if broadcast then C.Flush.dirty.usable = true; C.Schedule() end
    Run()
end
Pass(true, true)
if not measureOnly then Check(calls.spell == 6, "rebind/broadcast must read once per exact spell") end
Check(Empty(capturedSpell), "answers retained after pass")
answer, power = false, true
local before = calls.spell
Pass(false, true)
Check(calls.spell == before + 6 and entries[1].usableCode == 4
    and entries[1].resourcesAvailable == nil, "new pass did not read current state")
-- Same numeric ID in the item domain cannot reuse a spell answer.
local item = Entry(1, "a", "i")
entries[#entries + 1] = item
answer, power, itemAnswer, itemPower = true, false, false, true
local itemBefore = calls.item
Pass(true, false) -- no later broadcast may hide a cross-domain bind error
Check(entries[1].usableCode == 1 and item.usableCode == 4, "spell/item answers collided")
if not measureOnly then Check(calls.item == itemBefore + 1, "item rebind repeated its own query") end
Check(Empty(capturedItem), "item answers retained after pass")
entries[#entries] = nil
-- Secret results remain uninterpreted and are discarded before returning.
answer, power = secret, secret
Pass(true, true)
Check(entries[1].usableCode == 1 and entries[1].resourcesAvailable == nil
    and Empty(capturedSpell), "secret result was interpreted or retained")
-- No broadcast: full rebinds still share, then discard their answers.
answer, power = false, false
before = calls.spell
Pass(true, false)
if not measureOnly then Check(calls.spell == before + 6, "rebind-only scope did not share") end
Check(Empty(capturedSpell), "rebind-only scope retained answers")
-- Direct callers, including show/target/range catch-up, never inherit it.
answer = true
before = calls.spell
originalUsable(entries[1]); originalUsable(entries[1])
Check(calls.spell == before + 2 and entries[1].usableCode == 1, "direct reader inherited batch state")
-- Native queries distinguish the actual selected spell, not base/override.
entries[2].spell = 77
before = calls.spell
Pass(true, true)
if not measureOnly then Check(calls.spell == before + 7, "override was merged with base") end
entries[2].spell = 1
entries[2].spellCategory, entries[2].catSpell = 4, 88
before = calls.spell
Pass(true, true)
if not measureOnly then Check(calls.spell == before + 7, "category used the wrong query key") end
entries[2].spellCategory, entries[2].catSpell = nil, nil
-- Secret identities never become table keys in the reusable query maps.
local secretEntry = Entry(100, "a")
secretEntry.spell = secret
local cache = { seen = {}, usable = {}, noPower = {} }
before = calls.spell
originalUsable(secretEntry, cache); originalUsable(secretEntry, cache)
Check(calls.spell == before + 2 and Empty(cache), "secret identity was cached")
-- Preserve tint and resource semantics for all combinations of answers.
local values = { true, false, secret }
local e = entries[1]
for _, tint in ipairs({ false, true }) do
    for _, resources in ipairs({ false, true }) do
        for _, usable in ipairs(values) do
            for _, noPower in ipairs(values) do
                view.usable, view.readyResources = tint, resources
                answer, power = usable, noPower
                local code = 1
                if (tint or resources) and tint and usable == false then
                    code = noPower ~= secret and noPower and 4 or 3
                end
                local available = (tint or resources) and noPower == false or nil
                Pass(true, true)
                Check(e.usableCode == code and e.resourcesAvailable == available,
                    "tint/resource matrix changed")
                Check(Empty(capturedSpell), "matrix retained answers")
            end
        end
    end
end
view.usable, view.readyResources = true, false
answer, power = true, false
e.outOfRange = true
before = calls.spell
originalUsable(e)
Check(calls.spell == before, "out-of-range consumer queried usability")
view.readyResources = true
originalUsable(e)
Check(calls.spell == before + 1 and e.resourcesAvailable == true, "range suppressed resource consumer")
e.outOfRange, view.readyResources = nil, false

-- The shared object contains raw native answers, never one bar's derived
-- tint or resource policy. Ordered broadcast visits both possible readers.
do
    local all, first, second = entries, entries[1], entries[2]
    local other = { usable = false, readyResources = true, behaviorGen = 7 }
    C.views.b = other
    for _, reversed in ipairs({ false, true }) do
        entries = reversed and { second, first } or { first, second }
        C.Index.usable = entries
        answer, power = false, true
        local reads = calls.spell
        Pass(true, true)
        Check(first.usableCode == 4 and second.usableCode == 1
            and second.resourcesAvailable == nil, "shared query merged different bar policies")
        if not measureOnly then Check(calls.spell == reads + 1, "mixed bars repeated a query") end
        answer, power = true, false
        reads = calls.spell
        Pass(false, true)
        Check(calls.spell == reads + 1 and second.resourcesAvailable == true,
            "resource consumer did not interpret shared answer independently")
        first.outOfRange = true
        reads = calls.spell
        Pass(false, true)
        Check(calls.spell == reads + 1 and second.resourcesAvailable == true,
            "range-hidden first reader suppressed the next bar's query")
        first.outOfRange = nil
    end
    entries, C.Index.usable, C.views.b = all, all, view
end

-- Product-only VM count; stubs have their native calls counted separately.
-- 200 passes, 12 icons of six exact spells in two bars. Cold rebind/broadcast,
-- ordinary broadcast and warm full refresh are budgeted separately.
local function Measure(label, rebind, broadcast, invalidate)
    local function Batch()
        for _ = 1, 200 do
            if rebind and not invalidate then
                local reason = label == "non-full" and "charges" or "full"
                for i = 1, #entries do C.Flush.Mark(entries[i], reason) end
                if broadcast then C.Flush.dirty.usable = true end
                Run()
            else Pass(rebind, broadcast) end
        end
    end
    Batch()
    local vm = 0
    local function Tick()
        local info = debug.getinfo(2, "S")
        if info and info.source:find("/MSUF_Suite_CooldownManager/", 1, true) then vm = vm + 1 end
    end
    local spells, items, timers = calls.spell, calls.item, calls.timers
    local secretsBefore, overlays, writes = calls.secret, calls.overlay, calls.writes
    debug.sethook(Tick, "", 1)
    Batch()
    debug.sethook()
    local reads, itemReads, timerCalls = calls.spell - spells, calls.item - items, calls.timers - timers
    local secretCalls, overlayCalls, paintCalls = calls.secret - secretsBefore, calls.overlay - overlays, calls.writes - writes
    local function Allocation()
        collectgarbage("collect"); collectgarbage("stop")
        -- Lua 5.1 can shrink its call stack during a full collection. Rewarm
        -- that stack before measuring repeated work, with GC still stopped.
        Batch()
        local start = collectgarbage("count")
        Batch()
        local used = collectgarbage("count") - start
        collectgarbage("restart")
        return used
    end
    local allocation = math.min(Allocation(), Allocation())
    print(string.format("usable scope %s: vm=%d spell=%d item=%d timers=%d secret=%d overlay=%d paints=%d allocationKiB=%.6f",
        label, vm, reads, itemReads, timerCalls, secretCalls, overlayCalls, paintCalls, allocation))
    Check(itemReads == 0 and timerCalls == 200, "new native query domain or timer")
    Check(allocation <= .01, "batch allocated after warm-up")
    if not measureOnly then
        Check(reads == (broadcast and 1200 or 0), "native query budget exceeded")
        -- Rebind+broadcast retains 18 -> 6 native spell reads/pass.
        -- Both sides now execute/count production Const.Pick, including
        -- strict true and inheritance. Current-source rebind 1122400 ->
        -- 1096000; broadcast 327200 -> 320000; warm-full 504000 -> 489600.
        -- Non-full 120000 -> 122400 (+2%): one context argument per entry
        -- avoids duplicate native reads when show and broadcast coincide.
        local budget = label == "rebind+broadcast" and 1096000
            or label == "broadcast" and 320000
            or label == "non-full" and 122400 or 489600
        Check(vm <= budget, "VM work budget exceeded")
        -- Exact query identities need one extra secret guard per rebind.
        -- This replaces 2400 expensive usability queries with 2400 secret
        -- checks in the cold batch; total native count alone is insufficient.
        Check(secretCalls == (label == "rebind+broadcast" and 16800 or label == "broadcast" and 7200 or 0),
            "secret-check budget changed")
        Check(overlayCalls == (invalidate and 2400 or 0) and paintCalls == 0,
            "extra native overlay queries or widget writes")
    end
end
Measure("rebind+broadcast", true, true, true)
Measure("broadcast", false, true)
Measure("warm-full", true, false, false)
Measure("non-full", true, false, false)
print("CDM usable scope: " .. checks .. " checks passed")
