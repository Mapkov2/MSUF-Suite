local root = assert(arg[1])
local selected = arg[2] or "session"
MSUF_DM_FEATURE_TESTS = true
dofile(root .. "/tools/tests/suite_damage_meter_contract.lua")
local f = assert(MSUF_DM_FIXTURE)
local D, S, M, api = f.D, f.S, f.M, f.api
f.SetCombat(false)
f.SetZone("none")
f.Event("PLAYER_REGEN_ENABLED")
api.secret, api.empty = false, false
local function Settings(values) assert(S.SetMany("damageMeter", values)) end
local function Fetches() return api.fetch + api.fetchID end

if selected == "session" then
    Settings({ enabled = true, windowCount = 3, visibility = 1, w1Type = 1, w2Type = 3, w3Type = 8,
        w1Session = 1, w2Session = 1, w3Session = 1, autoCurrent = false,
        w1AutoCurrent = 1, w2AutoCurrent = 1, w3AutoCurrent = 1,
        w1SyncSession = true, w2SyncSession = true, w3SyncSession = true })
    local win = D.windows[1]
    local function Select(value, id)
        local gen, fetch = M.styleGen, Fetches()
        D.SelectSession(win, value, id, id and 65)
        return M.styleGen - gen, Fetches() - fetch
    end
    assert(not M.pendingWrites)
    M.inCombat = true
    assert(not D.PersistMany({}) and not M.pendingWrites, "empty selection created combat persistence work")
    M.inCombat = false
    local gen, fetch = Select(D.SESSION.OVERALL)
    assert(gen == 1 and fetch == 3, "synced fight selection rebuilt styles/fetched once per window: " .. gen .. "/" .. fetch)
    gen, fetch = Select(D.SESSION.CURRENT)
    assert(gen == 1 and fetch == 3, "return to Current repeated the settings refresh")
    gen, fetch = Select(D.SESSION.CURRENT, 7)
    assert(gen == 0 and fetch == 3, "runtime-only pin caused a full settings refresh")
    for i = 1, 3 do
        assert(D.windows[i].sessionID == 7 and M.config[D.KEYS[i].Session] == 1, "batch saved or lost a historical ID")
    end
    f.SetCombat(true)
    f.Event("PLAYER_REGEN_DISABLED")
    gen, fetch = Select(D.SESSION.OVERALL)
    assert(gen == 0 and fetch == 3 and M.config.w1Session == 1, "combat selection wrote saved settings")
    for i = 1, 3 do assert(M.pendingWrites[D.KEYS[i].Session] == 2 and D.windows[i].overall) end
    -- Choosing the original saved value must overwrite an older queued pick.
    Select(D.SESSION.CURRENT)
    for i = 1, 3 do assert(M.pendingWrites[D.KEYS[i].Session] == 1) end
    Select(D.SESSION.OVERALL)
    gen = M.styleGen
    f.SetCombat(false)
    f.Event("PLAYER_REGEN_ENABLED")
    assert(M.styleGen == gen + 1 and not M.pendingWrites and M.config.w3Session == 2, "combat batch did not flush once")
    Settings({ w1MythicSwap = true, w2MythicSwap = true, w3MythicSwap = true,
        w1MythicType = 4, w2MythicType = 2, w3MythicType = 8 })
    gen, fetch = M.styleGen, Fetches()
    D.MythicStart()
    assert(M.styleGen == gen + 1 and Fetches() == fetch + 3, "M+ type/current transition was not one batch")
    assert(M.config.w1Type == 3 and M.config.w2Type == 1 and M.config.w3Type == 7, "M+ batch lost chosen meter types")
    for i = 1, 3 do assert(not D.windows[i].overall and M.config[D.KEYS[i].Session] == 1) end
    gen, fetch = M.styleGen, Fetches()
    D.MythicEnd()
    assert(M.styleGen == gen + 1 and Fetches() == fetch + 3, "M+ Overall transition refreshed once per window")
    -- Repeated completion has no setting writes but still paints current data.
    gen = M.styleGen
    D.MythicEnd()
    assert(M.styleGen == gen, "unchanged M+ selection rebuilt style")
    print("Meter selection budget: 3 synced windows, 1 style generation/3 snapshots; pins/combat keep styles; M+ is one batch")
elseif selected == "picker" or selected == "title" then
    Settings({ enabled = true, windowCount = 1, visibility = 1, w1Type = 1, w1Session = 1, combatTime = false })
    local win = D.windows[1]
    if selected == "picker" then
        local before, gen = Fetches(), M.styleGen
        D.SetWindowType(win, D.TYPE.HealingDone)
        assert(Fetches() == before + 1 and M.styleGen == gen + 1, "one type click fetched twice")
        f.SetCombat(true)
        f.Event("PLAYER_REGEN_DISABLED")
        before, gen = Fetches(), M.styleGen
        D.SetWindowType(win, D.TYPE.DamageTaken)
        assert(Fetches() == before + 1 and M.styleGen == gen and M.pendingWrites.w1Type == 8,
            "combat type click did not paint once and queue persistence")
    else
        D.OpenBreakdown(win, 1)
        local title, color = win.panel.title.SetText, win.panel.targetsTab.text.SetTextColor
        local calls = 0
        win.panel.title.SetText = function(...) calls = calls + 1; return title(...) end
        win.panel.targetsTab.text.SetTextColor = function(...) calls = calls + 1; return color(...) end
        win.panel.spellsTab.text.SetTextColor = win.panel.targetsTab.text.SetTextColor
        for _ = 1, 20 do D.RefreshBreakdown(win) end
        assert(calls == 0, "unchanged breakdown heading rewrote native text/colors: " .. calls)
        win.bd.name = "Changed-Realm"
        D.RefreshBreakdown(win)
        assert(calls == 1 and win.panel.title.text == "Changed", "changed readable heading did not repaint once")
        win.bd.name = f.Secret("heading")
        D.RefreshBreakdown(win)
        D.RefreshBreakdown(win)
        assert(calls == 3, "secret heading was compared or cached")
        win.bd.name = nil
        D.RefreshBreakdown(win)
        assert(calls == 4 and win.panel.title.text == "", "secret heading did not clear to an absent name")
        win.bd.name = "Changed-Realm"
        win.bd.view = "targets"
        D.RenderBreakdown(win)
        assert(calls == 7, "view change did not recolor tabs and restore plain heading")
    end
    print("Meter native-write budget: " .. selected .. " changes paint once; unchanged public chrome stays quiet")
elseif selected == "recap" then
    local events = {}
    for i = 1, 12 do
        events[i] = { event = "SPELL_DAMAGE", spellId = 133, spellName = "Hit" .. i,
            amount = 200, currentHP = (i - 1) * 50, timestamp = 101 - i }
    end
    C_DeathRecap = { HasRecapEvents = function() return true end,
        GetRecapEvents = function() return events end, GetRecapMaxHealth = function() return 1000 end }
    api.roster[1].recap = 77
    Settings({ enabled = true, windowCount = 1, w1Type = 10, w1Session = 1, inlineRecap = true,
        visibility = 1, w1Height = 105, combatTime = false })
    local win = D.windows[1]
    D.OpenBreakdown(win, 1)
    assert(win.bd.recap and not win.bd.recap.restricted)
    local calls, saved = 0, {}
    for _, key in ipairs({ "SetTexture", "SetTexCoord", "SetMinMaxValues", "SetValue", "SetText",
        "SetFormattedText", "SetStatusBarColor", "SetTextColor" }) do
        local native = f.Region[key]
        saved[key] = native
        f.Region[key] = function(...) calls = calls + 1; return native(...) end
    end
    local getTexture = C_Spell.GetSpellTexture
    C_Spell.GetSpellTexture = function(...) calls = calls + 1; return getTexture(...) end
    for _ = 1, 20 do D.RefreshBreakdown(win) end
    assert(calls == 0, "unchanged readable recap repainted native sinks: " .. calls)
    D.ScrollBreakdown(win, -1)
    assert(calls > 0 and win.bdRows[1].nameText.text ~= "-0.0s Hit1", "scroll reused the wrong recap rows")
    calls = 0
    D.RefreshBreakdown(win)
    assert(calls == 0, "scrolled recap did not settle")
    M.styleGen = M.styleGen + 1
    D.RefreshBreakdown(win)
    assert(calls > 0 and win.panel.styleGen == M.styleGen, "style generation did not repaint the recap")
    calls = 0
    win.capacity = win.capacity - 1
    D.RenderRecap(win)
    assert(calls > 0, "capacity change reused stale recap layout")
    local previous = win.bd.recap
    win.bd.recap = D.ReadRecap(previous.id)
    calls = 0
    D.RefreshBreakdown(win)
    assert(calls > 0, "new recap snapshot did not repaint")
    -- Restricted snapshots must keep reaching C sinks and declassify later.
    events[1].amount = f.Secret("recap amount")
    win.bd.offset, win.bd.recap = 0, D.ReadRecap(77)
    assert(win.bd.recap.restricted)
    calls = 0
    D.RefreshBreakdown(win)
    local first = calls
    D.RefreshBreakdown(win)
    assert(calls > first and first > 0, "secret recap used a readable-snapshot cache")
    events[1].amount = 200
    calls = 0
    D.RefreshBreakdown(win)
    assert(calls > 0 and not win.bd.recap.restricted, "recap declassification did not repaint")
    calls = 0
    D.RefreshBreakdown(win)
    assert(calls == 0, "declassified recap did not settle")
    D.CloseBreakdown(win, true)
    assert(not win.bd.paintedRecap, "closed recap retained its native snapshot")
    for key, native in pairs(saved) do f.Region[key] = native end
    C_Spell.GetSpellTexture = getTexture
    print("Meter recap budget: 20 unchanged readable refreshes, zero texture/font/bar writes; scroll/style/size/secrets repaint")
elseif selected == "hidden" or selected == "faded" then
    Settings({ enabled = true, windowCount = 2, w1Type = 1, w2Type = 3, w1Session = 1, w2Session = 1,
        visibility = selected == "faded" and 4 or 1, combatTime = true, headerTimer = true,
        timer = true, timerAnchor = 1, timerDecimals = true, timerKeep = true })
    local win = D.windows[1]
    if selected == "faded" then
        assert(win.faded and not D.HasDirtyVisible())
        assert(not f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "fully faded meter retained the session-event stream")
        assert(f.Registered("DAMAGE_METER_RESET") and f.Registered("DAMAGE_METER_CURRENT_SESSION_UPDATED"),
            "faded viewer lost sparse fight invalidation events")
        D.SelectSession(win, D.SESSION.CURRENT, 7, 65)
        f.Event("DAMAGE_METER_RESET")
        assert(not win.sessionID, "reset while faded retained an expired pin")
        local delivered, fetch = 0, Fetches()
        for _ = 1, 1000 do
            if f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED") then
                delivered = delivered + 1
                f.Event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0)
            end
        end
        assert(delivered == 0 and Fetches() == fetch, "fully faded meter still handled a data storm")
        win.hover = true
        D.ApplyHover(win)
        assert(Fetches() == fetch + 1 and f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "hover reveal did not catch up/reconnect once")
        assert(not next(M.watchTypes[2]), "faded healing window still watched its data")
        win.hover = false
        D.ApplyHover(win)
        assert(not f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "fading the last viewer kept data events")
        local party = {
            player = { name = "Me", class = "MAGE", guid = "Player-1", spec = 135932, total = 500, pps = 5 },
            party1 = { name = "Tank-Realm", class = "WARRIOR", guid = "Player-Tank", spec = 132355, total = 1000, pps = 10 },
        }
        UnitGUID = function(unit) return party[unit] and party[unit].guid end
        UnitClassBase = function(unit) return party[unit] and party[unit].class end
        f.SetRoster({ party.party1, party.player })
        f.SetZone("party")
        Settings({ enabled = false })
        Settings({ enabled = true, combatDetails = true })
        win.hover = true
        D.ApplyHover(win)
        local secretRow = { sourceGUID = f.Secret("guid"), classFilename = "WARRIOR", specIconID = 132355 }
        assert(D.Identity(secretRow, win) == "Player-Tank", "first party hover reveal did not seed readable identities")
        f.SetCombat(true)
        f.Event("PLAYER_REGEN_DISABLED")
        win.hover = false
        D.ApplyHover(win)
        party.party2 = { guid = "Player-New", class = "WARRIOR" }
        assert(f.Registered("GROUP_ROSTER_UPDATE"), "faded party lost identity invalidation")
        f.Event("GROUP_ROSTER_UPDATE")
        win.hover = true
        D.ApplyHover(win)
        assert(D.Identity(secretRow, win) == nil, "faded roster churn retained a stale class identity")
    else
        -- Native OnHide/OnShow propagates to descendants when UIParent hides.
        -- The generic fixture's Show/Hide only changes its own shown flag.
        local function ParentVisible(visible)
            if visible then UIParent:Show() else UIParent:Hide() end
            local probe = M.visibilityProbe
            local handler = probe and probe:GetScript(visible and "OnShow" or "OnHide")
            if handler then handler(probe) end
        end
        f.SetCombat(true)
        f.Event("PLAYER_REGEN_DISABLED")
        ParentVisible(false)
        assert(not D.HasDirtyVisible() and not D.NeedClock(), "ancestor-hidden meter kept paint/clock work")
        assert(not f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED") and not D.timerJob.pending,
            "ancestor-hidden meter kept data events/tenths")
        assert(f.Registered("PLAYER_REGEN_ENABLED"), "hidden UI lost the combat-end lifecycle")
        local fetch = Fetches()
        for _ = 1, 20 do D.PaintDirty() end
        assert(Fetches() == fetch, "ancestor-hidden meter fetched sessions")
        ParentVisible(true)
        assert(Fetches() == fetch + 2 and D.NeedClock() and not win.dirty, "ancestor reveal did not catch up once")
        assert(f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "ancestor reveal did not reconnect the stream")
        local reads, visible = 0, f.Region.IsVisible
        f.Region.IsVisible = function(self) reads = reads + 1; return visible(self) end
        D.MarkAll()
        D.PaintDirty()
        assert(reads == 0, "warm paints probe native visibility")
        f.Region.IsVisible = visible
        D.OpenBreakdown(win, 1)
        assert(win.bd.open)
        ParentVisible(false)
        assert(win.bd.open, "hiding the parent discarded the selected detail panel")
        ParentVisible(true)
        f.SetCombat(false)
        f.Event("PLAYER_REGEN_ENABLED")
        Settings({ enabled = false })
        assert(not M.visibilityProbe:GetScript("OnShow") and not M.visibilityProbe:GetScript("OnHide"), "disabled meter retained visibility callbacks")
    end
    print("Meter visibility budget: " .. selected .. " viewers suspend data work; reveal catches up without native paint-time visibility probes")
else error("unknown case: " .. selected) end
