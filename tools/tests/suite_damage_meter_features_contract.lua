local root = assert(arg[1], "repository root required")
MSUF_DM_FEATURE_TESTS = true
dofile(root .. "/tools/tests/suite_damage_meter_contract.lua")
local f = assert(MSUF_DM_FIXTURE)
local D, S, M, api = f.D, f.S, f.M, f.api
local roster = {
    { name = "Tank-Realm", class = "WARRIOR", spec = 132355, guid = "Player-Tank", total = 1500000, pps = 15000 },
    { name = "Me", class = "MAGE", spec = 135932, guid = "Player-1", total = 900000, pps = 9000, isLocal = true },
    { name = "Healer-Realm", class = "PRIEST", spec = 135940, guid = "Player-Heal", total = 300000, pps = 3000 },
}
local function Settings(values) assert(S.SetMany("damageMeter", values)) end
f.SetCombat(false)
f.SetZone("none")
f.SetGroup(false)
f.SetRoster(roster)
api.secret, api.targetMode, api.empty = false, true, false
Settings({ enabled = true, windowCount = 2, visibility = 1, w1Type = 1, w2Type = 1,
    w1Session = 1, w2Session = 1, showPlayer = false, headerHeight = 22,
    headerSelectors = true, hoverTooltip = true, tooltipRows = 3, inlineRecap = false })
local win, other = D.windows[1], D.windows[2]
local boss = { name = "Boss", guid = "Creature-0-99", creature = 99 }
local add = { name = "Add", guid = "Creature-0-100", creature = 100 }

-- Actual header action -> native choice -> ranked target-only rows.
assert(win.buttons.target.shown, "Damage Done lacks its direct target selector")
D.HeaderButtonClick(win.buttons.target)
f.Pick(f.GetMenu(), "Boss")
assert(win.damageTarget and win.damageTarget.creature == 99, "target menu did not select the enemy")
assert(win.session.totalAmount == 2300 and win.session.combatSources[1].totalAmount == 1600
    and win.session.combatSources[2].totalAmount == 700, "target ranking shows overall or incomplete amounts")
assert(win.title.text == "Damage Done: Boss", "selected target is absent from the title")
D.OpenBreakdown(win, 1)
assert(#win.bd.source.combatSpells == 2 and win.bd.source.totalAmount == 1600,
    "target click opened all-target spells")
D.CloseBreakdown(win, true)
local sourceCalls = api.source
local targets, count, sum = D.TargetGroups(win, win.session.combatSources[1])
assert(count == 1 and sum == 1600 and targets[1].name == "Boss" and api.source == sourceCalls,
    "target hover fetched or displayed other targets")

-- Window snapshot deduplication may never mix two filters or filtered/unfiltered views.
D.MarkAll()
D.PaintDirty()
assert(win.session.totalAmount == 2300 and other.session.totalAmount == 2700000,
    "filtered session leaked into another window")
assert(D.SelectTarget(other, add))
D.MarkAll()
D.PaintDirty()
assert(win.session.totalAmount == 2300 and other.session.totalAmount == 700,
    "different selected targets shared one cached session")
local old = win.filteredCache
assert(M.watchTypes[D.TYPE.EnemyDamageTaken][0], "selected target does not hear inverse updates")
f.Event("DAMAGE_METER_COMBAT_SESSION_UPDATED", D.TYPE.EnemyDamageTaken, 0)
f.RunPaint()
assert(win.filteredCache ~= old and other.filteredCache ~= old, "inverse update kept the target cache")

-- Missing optional session duration must not erase the native target DPS.
do
    local get = C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(kind, meter)
        local session = get(kind, meter)
        session.durationSeconds = nil
        return session
    end
    D.InvalidateTargets()
    D.Paint(win)
    assert(win.session.combatSources[1].amountPerSecond == 16, "nil duration invented zero target DPS")
    C_DamageMeter.GetCombatSessionFromType = get
end

-- An attacker row that fits no player (a pet, guardian, totem or NPC) is left out of the ranking, never
-- credited to a player: the first boss ability (Tank, 1000) is the unknown attacker's, so Tank keeps 600 of 1600.
-- The audit contract covers names that fit several players and protected names.
for _, attacker in ipairs({ "UnknownPet", "Tank-OtherRealm" }) do
    local original = C_DamageMeter.GetCombatSessionSourceFromType
    C_DamageMeter.GetCombatSessionSourceFromType = function(kind, meter, guid, creature)
        local detail = original(kind, meter, guid, creature)
        if meter == D.TYPE.EnemyDamageTaken then detail.combatSpells[1].combatSpellDetails.unitName = attacker end
        return detail
    end
    D.InvalidateTargets()
    D.Paint(win)
    local list = assert(win.session, "an attacker that is no player erased the ranking: " .. attacker).combatSources
    assert(#list == 2 and list[1].name == "Me" and list[1].totalAmount == 700
        and list[2].name == "Tank-Realm" and list[2].totalAmount == 600, attacker .. " was credited to a player")
    C_DamageMeter.GetCombatSessionSourceFromType = original
    D.InvalidateTargets()
    D.Paint(win)
end

-- Hidden windows hear no data events; the reveal must discard cached target totals.
do
    local original = C_DamageMeter.GetCombatSessionSourceFromType
    S.ToggleDamageMeterViews()
    assert(not win.shown and not f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"))
    C_DamageMeter.GetCombatSessionSourceFromType = function(kind, meter, guid, creature)
        local detail = original(kind, meter, guid, creature)
        if meter == D.TYPE.EnemyDamageTaken then detail.combatSpells[1].totalAmount = 2000 end
        return detail
    end
    S.ToggleDamageMeterViews()
    f.RunPaint()
    assert(win.session.combatSources[1].totalAmount == 2600, "reveal retained stale target totals")
    C_DamageMeter.GetCombatSessionSourceFromType = original
end
f.Event("DAMAGE_METER_RESET")
assert(not win.damageTarget and win.title.text == "Damage Done", "reset left the selected target title")
assert(D.SelectTarget(win, boss))
f.Event("DAMAGE_METER_CURRENT_SESSION_UPDATED")
f.RunPaint()
assert(not win.damageTarget and win.title.text == "Damage Done", "new current fight retained a previous target selection")

-- Opt-in sync includes only opted-in windows; historic IDs remain runtime-only.
Settings({ windowCount = 3, w3Type = 3, w1SyncSession = true, w2SyncSession = true, w3SyncSession = false })
local third = D.windows[3]
D.SetWindowSession(win, D.SESSION.CURRENT, 7, 75)
assert(win.sessionID == 7 and other.sessionID == 7 and third.sessionID == nil, "fight sync ignored membership")
Settings({ autoCurrent = false, w1AutoCurrent = 2, w2AutoCurrent = 3 })
D.ClearPins()
assert(win.sessionID == nil and other.sessionID == 7, "per-window auto-current override ignored shared/off choice")
Settings({ w1MythicSwap = true, w2MythicSwap = false, w1MythicType = 4 })
D.MythicStart()
assert(win.meterType == D.TYPE.HealingDone and not win.sessionID and not win.overall,
    "M+ start did not apply selected type/current")
D.MythicEnd()
assert(win.overall and other.sessionID == 7, "M+ completion changed a window without opt-in")
D.SetWindowSession(win, D.SESSION.CURRENT, 7, 75)
D.MythicEnd()
assert(win.sessionID == 7, "M+ completion replaced a manually pinned historical fight")
do
    local threat, session = D.THREAT, other.sessionID
    D.THREAT = #f.NS.DamageMeterTypeLabels
    D.SelectSession({ index = 1, meterType = D.THREAT }, D.SESSION.OVERALL, nil, nil)
    assert(other.sessionID == session, "threat window originated fight synchronization")
    D.THREAT = threat
end
D.SetWindowSession(win, D.SESSION.CURRENT, nil, nil)

-- Safe class resolution requires a current unique class AND a unique native source.
do
    local oldGUID, oldClass = UnitGUID, UnitClassBase
    local units = { player = roster[2], party1 = roster[1], party2 = roster[3] }
    UnitGUID = function(unit) return units[unit] and units[unit].guid end
    UnitClassBase = function(unit) return units[unit] and units[unit].class end
    f.SetZone("party")
    f.SetGroup(true)
    Settings({ w1Type = 1, w1MythicSwap = false, w1MythicType = 1 })
    D.SnapshotIdentities()
    local secretRow = { sourceGUID = f.Secret("guid"), sourceCreatureID = nil,
        classFilename = "WARRIOR", specIconID = 132355, isLocalPlayer = false }
    assert(D.Identity(secretRow, win) == "Player-Tank", "unique verified party identity did not resolve")
    assert(D.Identity(secretRow, { meterType = D.TYPE.HealingDone }) == nil,
        "damage identity snapshot resolved an untracked healing source")
    assert(D.Identity(secretRow, { meterType = D.TYPE.DamageDone, sessionID = 7 }) == nil,
        "live identity snapshot resolved a historical source")
    f.SetCombat(true)
    api.secret = true
    f.Event("PLAYER_REGEN_DISABLED")
    D.OpenBreakdown(win, 1)
    assert(not win.bd.blocked and win.bd.guid == "Player-Tank", "actual combat click did not use plain party identity")
    f.Event("GROUP_ROSTER_UPDATE")
    assert(D.Identity(secretRow, win) == nil, "combat roster change retained a stale identity")
    f.SetCombat(false)
    api.secret = false
    f.Event("PLAYER_REGEN_ENABLED")
    D.CloseBreakdown(win, true)
    units.party3 = { guid = "Player-New", class = "WARRIOR" }
    D.SnapshotIdentities()
    assert(D.Identity(secretRow, win) == nil, "duplicate current class guessed a player")
    units.party3 = nil
    roster[4] = { name = "OldTank", class = "WARRIOR", spec = 132355,
        guid = "Player-Old", total = 500, pps = 5 }
    D.SnapshotIdentities()
    assert(D.Identity(secretRow, win) == nil, "departed source row resolved to a replacement player")
    roster[4] = nil
    f.SetZone("raid")
    D.SnapshotIdentities()
    assert(D.Identity(secretRow, win) == nil, "party identity inference escaped into raids")
    f.SetZone("none")
    f.SetGroup(false)
    UnitGUID, UnitClassBase = oldGUID, oldClass
end

-- Recap API returns newest first: retain killing blow when limiting rows.
do
    local events = {}
    for i = 1, 10 do
        events[i] = { event = "SPELL_DAMAGE", spellId = 133, spellName = "Hit" .. i,
            amount = 200, currentHP = (i - 1) * 100, timestamp = 101 - i }
    end
    events[1].overkill = 50
    C_DeathRecap = { HasRecapEvents = function(id) return id == 77 end,
        GetRecapEvents = function() return events end, GetRecapMaxHealth = function() return 1000 end }
    roster[1].recap = 77
    Settings({ w1Type = 10, w1Session = 1, inlineRecap = true, tooltipRows = 3 })
    D.OpenBreakdown(win, 1)
    assert(win.bd.recap and win.bdRows[1].nameText.text == "-0.0s Hit1", "inline recap omitted the killing event")
    assert(win.bdRows[1].valueText.text == "200 (50 overkill)", "inline recap lost overkill")
    D.CloseBreakdown(win, true)
    D.ShowTip(win, win.rows[1])
    assert(M.tip.rows[1].nameText.text == "-0.0s Hit1" and M.tip.rows[3].nameText.text == "-2.0s Hit3",
        "recap tooltip retained the oldest rather than newest N events")
    events[1].timestamp = f.Secret("death time")
    D.ShowTip(win, win.rows[1])
    assert(M.tip.rows[2].nameText.text == "Hit2", "secret killing timestamp invented an older death moment")
    events[1].amount, events[1].currentHP, events[1].spellName, events[1].spellId =
        f.Secret("amount"), f.Secret("health"), f.Secret("spell name"), f.Secret("spell id")
    D.ShowTip(win, win.rows[1])
    assert(M.tip.rows[1].nameText.text == events[1].spellName, "secret recap name was discarded")
    assert(not M.tip.rows[1].icon:IsShown(), "secret recap ID was sent to texture lookup")
    D.HideTip()
    f.SetCombat(true)
    api.secret = true
    f.Event("PLAYER_REGEN_DISABLED")
    D.OpenBreakdown(win, 1)
    assert(win.bd.recap and win.bd.recap.restricted, "combat recap did not retain its restriction state")
    events[1].timestamp, events[1].amount, events[1].currentHP, events[1].spellName, events[1].spellId =
        100, 200, 0, "Hit1", 133
    f.SetCombat(false)
    api.secret = false
    f.Event("PLAYER_REGEN_ENABLED")
    assert(win.bd.recap and not win.bd.recap.restricted and win.bdRows[1].nameText.text == "-0.0s Hit1",
        "open recap kept the secret snapshot after combat")
    D.CloseBreakdown(win, true)
end

-- Hover positioning, independent texture, favorites and display gates share real UI routes.
Settings({ w1Type = 1, inlineRecap = false, breakdownOwnTexture = true, breakdownTexture = "Blizzard" })
local textureResolver = S.ResolveTexture
S.ResolveTexture = function(value, fallback)
    if value == "FeatureBreakdown" then return "test-breakdown" end
    return textureResolver(value, fallback)
end
S.Set("damageMeter", "breakdownTexture", "FeatureBreakdown")
for choice, point in ipairs({ "BOTTOMLEFT", "CENTER", "TOPRIGHT", "TOPLEFT" }) do
    S.Set("damageMeter", "tooltipAnchor", choice)
    D.ShowTip(win, win.rows[1])
    assert(M.tip.points[1][1] == point, "hover anchor choice was ignored")
    assert(M.tip.rows[1].bar:GetStatusBarTexture().texture == "test-breakdown"
        and M.style.texture ~= "test-breakdown", "breakdown ignored its own texture")
end
S.ResolveTexture = textureResolver
D.HideTypeMenu()
D.OpenTypeMenu(win, win.buttons.type)
assert(D.typePanel.favoriteButtons[0].shown and D.typePanel.favoriteButtons[2].shown,
    "default favorite meters were not shown")
local favorite = D.typePanel.favoriteButtons[0]
favorite.scripts.OnClick(favorite, "RightButton")
assert(not D.typePanel.favoriteButtons[0].shown and D.typePanel.buttons[0].shown,
    "removing a favorite removed the actual meter choice")
D.HideTypeMenu()
-- Preview layers may hide a configured button, but cannot resurrect one disabled by runtime settings.
do
    local options = { S = S, Tr = function(value) return value end, T = {} }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/DamageMeterPreviewLayers.lua"))("Options", options)
    local targets = { buttons = {}, rows = {} }
    for key in pairs(win.buttons) do targets.buttons[key] = CreateFrame("Frame") end
    for i in ipairs(win.rows) do targets.rows[i] = {} end
    local preview = { layers = { window = true, header = true, title = true, timer = true,
        buttons = true, bars = true, name = true, value = true, icon = true }, targets = targets, layerButtons = {} }
    S.Set("damageMeter", "targetSelector", false)
    options.MeterPreviewLayers.Paint(preview, win)
    assert(not win.buttons.target.shown and not targets.buttons.target.shown, "preview resurrected a disabled target selector")
    Settings({ targetSelector = true, w1Type = 3 })
    options.MeterPreviewLayers.Paint(preview, win)
    assert(not win.buttons.target.shown, "healing preview showed the damage target selector")
    Settings({ w1Type = 1, headerSelectors = false })
    options.MeterPreviewLayers.Paint(preview, win)
    assert(not win.buttons.target.shown and not win.buttons.type.shown and not win.buttons.session.shown,
        "preview resurrected compact-header selectors")
end
Settings({ enabled = false })
assert(not f.Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "disabled feature retained native data events")
print("Damage meter features: target ranking/spells, isolation, cache edges, combat identity, recap, sync, M+ and hover/favorites passed")
