local root = assert(arg[1], "repository root required")
local secretMT = { __index = function() error("secret indexed") end,
    __tostring = function() error("secret stringified") end }
local function Secret() return setmetatable({}, secretMT) end
local function Public(value) return getmetatable(value) ~= secretMT end
local function Wipe(t) for key in pairs(t) do t[key] = nil end end
local function Run(flavor)
    local locked, timers, created, queries, writes, marks, prepared = false, {}, 0, 0, 0, 0, 0
    local actions = { [5] = 123, [6] = 123 }
    local usable = { [5] = true, [6] = true }
    C_Timer = { After = function(delay, fn)
        assert(delay == 0, "usability fallback must only coalesce the current event burst")
        timers[#timers + 1] = fn
    end }
    C_ActionBar = { IsUsableAction = function(slot)
        assert(Public(slot), "secret slot queried")
        queries = queries + 1
        return usable[slot]
    end }
    local function Timers()
        local pending = timers
        timers = {}
        for i = 1, #pending do pending[i]() end
    end
    local function Button(slot)
        return { slot = slot, GetSize = function() return 36, 36 end,
            GetFrameLevel = function() return 2 end }
    end
    local first, second = Button(5), Button(6)
    local function Frame(_, _, parent)
        assert(not locked, "glow frame created in combat")
        created = created + 1
        local frame = { parent = parent }
        function frame:SetAllPoints() end
        function frame:SetFrameLevel() end
        function frame:SetScript(event, callback) self[event] = callback end
        return frame
    end
    local S = { Public = Public, CreateFrame = Frame, states = { actionbars = { active = true } } }
    local C = { M = { active = true }, state = {}, entries = {}, views = { ess = { on = true } }, wipe = Wipe,
        Const = { FAMILY = { COOLDOWN = 1 } },
        Flush = { dirty = {}, Mark = function() marks = marks + 1 end }, Schedule = function() end }
    C.Effects = { SetGlow = function(host, reason, on)
        assert(reason == "ready" and type(on) == "boolean", "only a public display state reaches the painter")
        host.on = on
        writes = writes + 1
    end, Refit = function() end, PrepareGlow = function() prepared = prepared + 1 end }
    local visits = 0
    C.ActionGlows = { ButtonSlot = function(button) return button.slot end,
        SlotSpell = function(slot) return actions[slot] end,
        Visitor = function()
            if not S.states.actionbars.active then return end
            return function(spell, callback)
                assert(not locked and spell == 123, "only the configured spell visits buttons outside combat")
                visits = visits + 1
                callback(first)
                callback(second)
            end
        end }
    local P = { Suite = S, NS = { Client = { isForever = flavor == "Forever" },
        IsCombatLocked = function() return locked end }, CDM = C }
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/ActionUsableGlows.lua"))("contract", P)
    local U = C.ActionUsableGlows
    U.Refresh()
    assert(not U.wanted and created == 0 and queries == 0 and #timers == 0, "disabled feature did work")
    local entry = { key = "s123", src = "s", base = 123, spell = 222, override = 222, family = 1, slot = "ess", ov = {} }
    C.entries.s123 = entry
    U.Refresh()
    assert(created == 0 and queries == 0, "unset option built feedback")
    entry.ov.actionUsableGlow = true
    U.Refresh()
    assert(U.wanted and C.Flush.dirty.events and visits == 1 and created == 2 and queries == 2,
        "configured base-action slots were not bound once for the overridden spell")
    assert(marks == 1, "first activation must request fresh shared timing")
    assert(prepared == 2, "glow art must be prepared before usability/cooldown events")
    local seen = {}
    C.Effects.SetGlow = function(host, _, on)
        seen[host.parent] = host
        host.on = on
        writes = writes + 1
    end
    U.Timing(entry, {}, false, false)
    assert(seen[first].on and seen[second].on, "ready usable actions did not glow")
    seen[first].OnSizeChanged(seen[first],48,48)
    assert(seen[first].w==48 and seen[first].h==48,"action-button resize left stale glow dimensions")
    seen[first].OnSizeChanged(seen[first],Secret(),Secret())
    assert(seen[first].w==48,"unreadable geometry entered the glow cache")
    U.Changed(nil, nil, { { slot = 5, usable = false } })
    assert(not seen[first].on and seen[second].on, "slot payload touched the wrong action")
    local q, w = queries, writes
    U.Changed(nil, nil, { { slot = 77, usable = true } })
    U.Changed(nil, nil, { { slot = 5, usable = false } })
    assert(queries == q and writes == w, "unrelated/unchanged payload performed work")
    U.Changed(nil, nil, { { slot = 6, usable = Secret() }, { slot = Secret(), usable = true }, Secret() })
    assert(not seen[second].on, "secret usability was treated as usable")
    for i = 1, 100 do U.Queue() end
    assert(#timers == 1 and queries == q, "fallback storm did not coalesce")
    Timers()
    assert(queries == q + 2 and seen[first].on and seen[second].on, "fallback did not query selected slots only")
    U.Timing(entry, nil, nil, false)
    assert(not seen[first].on and not seen[second].on, "unknown cooldown enabled a glow")
    U.Timing(entry, {}, Secret(), false)
    assert(not seen[first].on, "secret cooldown enabled a glow")
    U.Timing(entry, {}, true, false, false)
    assert(not seen[first].on and not seen[second].on,"approximate previous readiness enabled a glow")
    U.Timing(entry, {}, true, true, true)
    assert(not seen[first].on, "active real cooldown enabled a glow")
    U.Cooldown(entry, false)
    assert(seen[first].on and seen[second].on, "cooldown completion did not resume feedback")
    C.state.readyGlowCombat=true
    U.Repaint()
    assert(not seen[first].on and not seen[second].on,"combat-only ready policy ignored outside combat")
    C.state.inCombat=true
    U.Repaint()
    assert(seen[first].on and seen[second].on,"combat-only policy did not resume on combat edge")
    C.state.readyGlowCombat,C.state.inCombat=false,false
    -- Another enabled entry keeps the owner running across an individual
    -- combat opt-out. Reenable must still discard stale ready timing.
    C.entries.other={key="s456",src="s",spell=456,family=1,slot="ess",ov={actionUsableGlow=true}}
    local oldVisitor=C.ActionGlows.Visitor
    C.ActionGlows.Visitor=function()
        local visit=oldVisitor()
        return function(spell,callback) if spell==123 then visit(spell,callback) end end
    end
    locked=true
    entry.ov.actionUsableGlow=nil
    U.Refresh()
    assert(U.wanted and entry.actionGlowCooling==nil,"individual combat opt-out kept old timing")
    entry.ov.actionUsableGlow=true
    local marked=marks
    U.Refresh()
    Timers()
    assert(not seen[first].on and marks>marked,"individual combat reenable reused stale readiness")
    U.Cooldown(entry,false)
    C.entries.other=nil
    C.ActionGlows.Visitor=oldVisitor
    locked=false
    -- Both page changes and macro remaps can change an action in combat.
    locked = true
    first.slot = 77
    actions[77] = 999
    q, w = queries, visits
    U.Follow()
    Timers()
    assert(not seen[first].on and seen[second].on and visits == w, "paged action inherited another spell's glow")
    actions[6] = 999
    U.Cooldown(entry, false)
    assert(not seen[second].on, "macro remap kept stale feedback")
    actions[6] = Secret()
    U.Cooldown(entry, false)
    assert(not seen[second].on, "unreadable macro route enabled feedback")
    U.Refresh()
    assert(U.pending and created == 2, "combat refresh built new frames")
    entry.ov.actionUsableGlow = nil
    U.Refresh()
    assert(not U.wanted and not seen[first].on and not seen[second].on, "combat opt-out left feedback")
    U.Queue()
    assert(#timers == 1, "disabled feature queued new work") -- previous combat follow is still pending
    Timers()
    locked = false
    first.slot, actions[6] = 5, 123
    entry.ov.actionUsableGlow = true
    U.Refresh()
    assert(not seen[first].on and not seen[second].on, "reenable trusted an old cooldown answer")
    U.Cooldown(entry, false)
    assert(created == 2 and seen[first].on and seen[second].on, "reenable did not reuse the owned hosts")
    C.views.ess.on=false
    U.Refresh()
    assert(not U.wanted and not seen[first].on,"disabled CDM group retained action feedback")
    C.views.ess.on=true
    U.Refresh()
    U.Cooldown(entry,false)
    S.states.actionbars.active = false
    U.Refresh()
    assert(not U.wanted and not seen[first].on and not seen[second].on, "action bars off retained feedback")
    S.states.actionbars.active = true
    U.Refresh()
    U.Cooldown(entry, false)
    C.entries.s123 = nil
    U.Refresh()
    assert(not U.wanted and not seen[first].on, "removed entry retained feedback")
    U.Release()
    print(flavor .. ": optional action usability routing, secrets, combat and reuse pass")
end
Run("Mainline")
Run("Forever")
