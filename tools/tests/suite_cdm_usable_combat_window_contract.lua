local root = assert(arg[1], "repository root required")
-- The Cooldown Manager's usability sweep window in combat (Events.lua
-- UsableWindow). Owner decision 2026-11-11, an accepted trade: in combat the
-- ordinary tint sweep opens a 0.5 s window instead of 0.2 s. 2026-11-11 raid
-- trace (300 s): 7,817 SPELL_UPDATE_USABLE (26/s), 1,442 sweeps at 4.8/s,
-- 19,604 usable reads (13.6 per sweep), 273 ms inclusive. At that event rate
-- a whole fight in combat sweeps about 2/s: about 600 sweeps and 8,200 reads,
-- about 11,400 reads (~114 ms native, ~160 ms inclusive) fewer. The worst-case
-- tint latency inside a storm goes from 0.2 s to 0.5 s in combat.
-- Held here, on the main contract's harness up to its cooldown events:
--   * the leading edge sweeps at once in and out of combat;
--   * out of combat a 6 s storm at 26 events/s sweeps on the 0.2 s window;
--   * in combat (C.state.inCombat from PLAYER_REGEN_DISABLED, while
--     InCombatLockdown is still false) the same storm sweeps on the 0.5 s
--     window and ends with one trailing sweep that paints the final state;
--   * leaving combat inside a 0.5 s window: the open window runs out, then
--     0.2 s windows again;
--   * "show only when usable" gates keep 0.2 s and resource-ready glows keep
--     their 0.1 s window in combat.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
    local RATE, SECONDS = 26, 6
    -- The harness fires a wake at the next event step, so a window lasts
    -- whole steps: 0.2 s -> 6 steps (26 sweeps in 6 s), 0.5 s -> 13 steps (12).
    local function Expected(window) return SECONDS / (math.ceil(window * RATE - 1e-6) / RATE) end
    local function Reads() return usable.calls[201] or 0 end
    -- Events at RATE per second for SECONDS; the last one sets the final state.
    local function Storm(final)
        local before, step, last = Reads(), 1 / RATE, nil
        for i = 1, RATE * SECONDS do
            if i == RATE * SECONDS then usable[201] = final end
            Fire("SPELL_UPDATE_USABLE")
            if i == RATE * SECONDS then last = Reads() end
            Run(step)
        end
        return Reads() - before, last
    end
    local function Edge(label)
        Run(2)
        local before = Reads()
        assert(Fire("SPELL_UPDATE_USABLE"), "SPELL_UPDATE_USABLE is not registered")
        Run()
        assert(Reads() == before + 1, label .. ": the first event after a quiet window did not sweep at once")
    end
    assert(C.Index.usableInterval == .2 and not C.state.inCombat, "the fixture is not ordinary usability out of combat")

    -- Out of combat: unchanged 0.2 s windows.
    Edge("out of combat")
    local idle = Storm(nil)
    Run(1)
    assert(math.abs(idle - Expected(.2)) <= 1,
        "out of combat a " .. SECONDS .. " s storm swept " .. idle .. " times, not every 0.2 s")

    -- In combat: 0.5 s windows, read from the module's own combat state.
    Fire("PLAYER_REGEN_DISABLED")
    assert(C.state.inCombat and not InCombatLockdown(), "PLAYER_REGEN_DISABLED did not mark combat before lockdown")
    Edge("in combat")
    local fought, last = Storm(false)
    assert(math.abs(fought - Expected(.5)) <= 1,
        "in combat a " .. SECONDS .. " s storm swept " .. fought .. " times, not every 0.5 s")
    Run(.5)
    assert(Reads() == last + 1, "the storm did not end with exactly one sweep after its last event")
    assert(e21.icon.tex.vc[1] == .4, "the trailing sweep did not paint the final unusable tint")
    Run(2)
    assert(Reads() == last + 1, "the window kept sweeping without events")

    -- Leaving combat inside a 0.5 s window: that window runs out first.
    usable[201] = nil
    Edge("combat leading edge")
    local opened = Reads()
    Fire("PLAYER_REGEN_ENABLED")
    assert(not C.state.inCombat, "PLAYER_REGEN_ENABLED did not end combat")
    Run(.25)
    Fire("SPELL_UPDATE_USABLE")
    Run(.2)
    assert(Reads() == opened, "an event inside the combat window swept before the window ran out")
    Run(.06)
    assert(Reads() == opened + 1 and e21.icon.tex.vc[1] == 1, "the open combat window did not end with its sweep")
    -- That sweep opened the first 0.2 s window (to +0.71 s).
    Run(.1)
    Fire("SPELL_UPDATE_USABLE")
    Run(.05)
    assert(Reads() == opened + 1, "the first out-of-combat window swept early")
    Run(.06)
    assert(Reads() == opened + 2, "out of combat the next window was not 0.2 s")

    -- "Show only when usable" gates show and hide icons by this sweep: while
    -- any gate exists the window stays 0.2 s in combat (the gate list alone
    -- decides, read when the window opens).
    Fire("PLAYER_REGEN_DISABLED")
    C.Index.gated[1] = e21
    Edge("gated in combat")
    local gated = Reads()
    Fire("SPELL_UPDATE_USABLE")
    Run(.15)
    assert(Reads() == gated, "a gated sweep ran before its deadline")
    Run(.06)
    assert(Reads() == gated + 1, "\"show only when usable\" gates lost their 0.2 s window in combat")
    C.Index.gated[1] = nil
    Fire("PLAYER_REGEN_ENABLED")
    -- Resource-ready glows keep 0.1 s in combat.
    local old = e21.ov
    local override = {}
    for key, value in pairs(old or {}) do override[key] = value end
    override.readyResources = true
    e21.ov = override
    C.Index.Rebuild()
    Fire("PLAYER_REGEN_DISABLED")
    Edge("resource glow in combat")
    local glow = Reads()
    Fire("SPELL_UPDATE_USABLE")
    Run(.05)
    assert(Reads() == glow, "resource usability swept before its deadline")
    Run(.051)
    assert(Reads() == glow + 1, "resource-ready glows lost their 0.1 s window in combat")
    e21.ov = old
    C.Index.Rebuild()
    Fire("PLAYER_REGEN_ENABLED")
    Run(1)
    print(("CDM usable combat window: 6 s storm at 26/s swept %d times out of combat, %d in combat (+1 trailing)"):format(
        idle, fought))
end)() end
]=], "------------------------------------------------------------------ cooldown events")
