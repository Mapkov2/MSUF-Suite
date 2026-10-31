local root = assert(arg[1], "repository root required")
local forever = arg[2] == "Forever"
-- Damage meter audit fixes: Hide in Delves matches Delves only; the Mythic+
-- reset is hidden where there are no keystones (WoW Forever); the header timer
-- size and offsets grey with its switch; a threat window offers no fights (its
-- header has no Session button, its Fight and Sync settings are greyed); the
-- page answers to the names players know from other meters; a chat report
-- escapes "|" and a failed send cannot wedge the next report.
-- Retail runs the base meter fixture, WoW Forever (argument "Forever") the
-- threat fixture, which loads the meter with the Forever client model.
MSUF_DM_FEATURE_TESTS = true
local originalLoad, private = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
dofile(root .. "/tools/tests/" .. (forever and "suite_damage_meter_threat_contract.lua"
    or "suite_damage_meter_contract.lua"))
loadfile = originalLoad
local D, S, M, NS = private.DamageMeter, private.Suite, private.DamageMeter.M, MSUFSuite
local rules = S.catalog.damageMeter.rules
local ID = "damageMeter"
local function Settings(values) assert(S.SetMany(ID, values)) end

------------------------------------------------------------------ the options page, loaded without Menu2
-- A stand-in for everything the page asks of the options host: any name is a
-- function that returns itself, so Build runs through and registers its gate.
local Any
Any = setmetatable({}, { __index = function() return Any end, __call = function() return Any end })
local registered
-- The settings the gate reads: the page's own copy, so the runtime stays as it is.
local values = { windowCount = 2, w1Type = 1, w2Type = 3 }
local P = setmetatable({
    Suite = NS, catalog = S.catalog, SearchPreparers = {}, Gates = {},
    Get = function(_, key) return values[key] end,
    RegisterPage = function(page) registered = page end,
}, { __index = function() return Any end })
assert(originalLoad(root .. "/MSUF_Suite_Options/Pages/DamageMeter.lua"))("MSUF_Suite_Options", P)
assert(registered and registered.key == "suite_damageMeter", "the page did not register")
registered.build(Any)
local gate = assert(P.Gates[ID], "the page registered no gate")

------------------------------------------------------------------ search aliases
do
    local aliases = {}
    for _, alias in ipairs(registered.aliases) do aliases[alias] = true end
    for _, word in ipairs({ "meter", "dps", "details", "skada", "recount" }) do
        assert(aliases[word], "the page lacks the search alias '" .. word .. "'")
    end
end

------------------------------------------------------------------ header timer greying
do
    for _, key in ipairs({ "headerTimerSize", "headerTimerOffsetX", "headerTimerOffsetY" }) do
        assert(rules[key].enableKey == "headerTimer" and not rules[key].hidden,
            key .. " must grey with the header timer switch")
    end
    assert(rules.headerTimer.enableKey == "combatTime", "the header timer switch lost its parent switch")
end

------------------------------------------------------------------ the Mythic+ reset
do
    assert(rules.mythicReset.hidden == (forever or nil), "the Mythic+ reset must be hidden on Forever only")
    for i = 1, NS.DamageMeterMaxWindows do
        assert(rules["w" .. i .. "MythicSwap"].hidden == (forever or nil)
            and rules["w" .. i .. "MythicType"].hidden == (forever or nil), "the window Mythic+ choices follow the client")
    end
    if forever then
        assert(S.Config(ID).mythicReset == true and not D.WantsMythicEvents(),
            "Forever listens for keystones, so the reset would have an effect")
    end
end

------------------------------------------------------------------ window fight settings
do
    for _, key in ipairs({ "w1Session", "w1SyncSession", "w2Session", "w2SyncSession", "w1Width" }) do
        assert(gate({ key = key }, key) == true, key .. " must stay editable on a meter window")
    end
    local ok, reason = gate({ key = "w3Session" }, "w3Session")
    assert(ok == false and reason == nil, "a window above the count keeps its plain disabled state")
    if forever then
        values.w2Type = D.THREAT + 1
        for _, key in ipairs({ "w2Session", "w2SyncSession" }) do
            ok, reason = gate({ key = key }, key)
            assert(ok == false and reason == "Threat windows do not use fights.", key .. " must grey on a threat window")
        end
        for _, key in ipairs({ "w2Width", "w2Height", "w2X", "w1Session", "w1SyncSession" }) do
            assert(gate({ key = key }, key) == true, key .. " greyed without a threat window reason")
        end
        values.w2Type = 3
    else
        assert(NS.DamageMeterThreatType == nil, "Retail has no threat meter")
    end
end

------------------------------------------------------------------ Hide in Delves (Retail fixture)
if not forever then
    local f = assert(MSUF_DM_FIXTURE)
    local delve, reads = false, 0
    C_DelvesUI = { HasActiveDelve = function() reads = reads + 1; return delve end }
    f.SetCombat(false)
    f.SetZone("none")
    f.SetRoster({ { name = "Tank-Realm", class = "WARRIOR", guid = "Player-Tank", total = 1500000, pps = 15000, death = 17 } })
    f.api.secret, f.api.empty, f.api.targetMode = false, false, false
    -- Window 1 hides in dungeons only, window 2 in Delves only.
    Settings({ enabled = true, windowCount = 2, visibility = 1, w1Type = 1, w2Type = 3,
        w1HideDungeon = true, w1HideDelve = false, w2HideDungeon = false, w2HideDelve = true })
    local first, second = D.windows[1], D.windows[2]
    local function Zone(kind, active)
        f.SetZone(kind)
        delve = active
        D.EvaluateVisibility()
    end
    Zone("none", false)
    assert(first.shown and second.shown and reads == 0, "outside instances nothing hides, and no Delve is asked for")
    Zone("party", false)
    assert(not first.shown and second.shown and reads == 0, "a dungeon is not a scenario: no Delve lookup")
    Zone("scenario", true)
    assert(first.shown and not second.shown, "a Delve must hide with Hide in Delves only")
    assert(reads == 1, "one Delve lookup per visibility pass")
    Zone("scenario", false)
    assert(not first.shown and second.shown, "another scenario must keep following Hide in dungeons")
    -- A protected answer is no Delve and must not be compared.
    Zone("scenario", f.Secret("delve"))
    assert(not first.shown and second.shown, "a protected Delve answer must read as no Delve")
    Settings({ w1HideDungeon = false, w2HideDelve = false })
    Zone("none", false)
end

------------------------------------------------------------------ chat report (Retail fixture)
-- Chat refuses a lone "|": a Bar value format or a "|" separator prints one.
-- A send that raises must not leave the report in flight.
if not forever then
    local f = assert(MSUF_DM_FIXTURE)
    local sent, failing = {}, false
    C_ChatInfo = { InChatMessagingLockdown = function() return false end,
        SendChatMessage = function(text)
            if failing then error("chat rejected the line") end
            sent[#sent + 1] = text
        end }
    DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    f.SetCombat(false)
    f.SetZone("none")
    f.SetRoster({
        { name = "Tank-Realm", class = "WARRIOR", guid = "Player-Tank", total = 1500000, pps = 15000, death = 17 },
        { name = "Me", class = "MAGE", guid = "Player-1", total = 900000, pps = 9000, death = 34, isLocal = true },
        { name = "Healer-Realm", class = "PRIEST", guid = "Player-Heal", total = 300000, pps = 3000, death = 51 },
    })
    Settings({ w1Type = 1, w1Session = 1, reportLines = 2, numberFormat = 5, valueOrder = 3, valueSeparator = 4 })
    D.MarkAll()
    D.PaintDirty()
    local win = D.windows[1]

    -- Say outside an instance sends every line at once.
    assert(D.SendReport(win, "SAY") and #sent == 4, "the report did not go out")
    local bars
    for _, text in ipairs(sent) do
        local rest = text:gsub("||", "")
        assert(not rest:find("|", 1, true), "chat would refuse the line '" .. text .. "'")
        bars = bars or text:find("||", 1, true)
    end
    assert(bars, "the custom layout prints bars: they must go out doubled")
    assert(not M.report, "the report stayed in flight")

    -- The first line raises.
    sent, failing = {}, true
    assert(not pcall(D.SendReport, win, "SAY"), "the stand-in send did not raise")
    assert(M.report == nil, "a raising send left the report in flight")
    failing, sent = false, {}
    assert(D.SendReport(win, "SAY") and #sent == 4, "the next report could not start")

    -- A later line raises, one line per tick in a group.
    f.SetGroup(true)
    sent = {}
    assert(D.SendReport(win, "PARTY") and #sent == 1 and M.report, "a group report sends line by line")
    failing = true
    assert(not pcall(D.ReportTick), "the stand-in send did not raise")
    assert(M.report == nil, "a raising later line left the report in flight")
    failing, sent = false, {}
    assert(D.SendReport(win, "PARTY") and #sent == 1, "the next group report could not start")
    D.CancelReport()
    f.SetGroup(false)
end

------------------------------------------------------------------ target filter (Retail fixture)
-- An attacker row that is no player (pet, guardian, totem, NPC) is left out;
-- a name that fits several players, or a protected name, fails the filter.
if not forever then
    local f = assert(MSUF_DM_FIXTURE)
    local win = D.windows[1]
    local attacker
    local source = C_DamageMeter.GetCombatSessionSourceFromType
    C_DamageMeter.GetCombatSessionSourceFromType = function(kind, meter, guid, creature)
        local detail = source(kind, meter, guid, creature)
        if meter == D.TYPE.EnemyDamageTaken and attacker ~= nil then
            detail.combatSpells[1].combatSpellDetails.unitName = attacker
        end
        return detail
    end
    local roster = {
        { name = "Tank-Realm", class = "WARRIOR", guid = "Player-Tank", total = 1500000, pps = 15000, death = 17 },
        { name = "Me", class = "MAGE", guid = "Player-1", total = 900000, pps = 9000, death = 34, isLocal = true },
    }
    f.SetRoster(roster)
    f.api.secret, f.api.empty, f.api.targetMode = false, false, true
    Settings({ w1Type = 1, w1Session = 1 })
    assert(D.SelectTarget(win, { name = "Boss", guid = "Creature-0-99", creature = 99 }))
    -- What the filtered window ranks after the first boss ability (Tank, 1000) came from `name`.
    local function Ranking(name)
        attacker = name
        D.InvalidateTargets()
        D.Paint(win)
        return win.session
    end
    local function Names(session)
        local list = {}
        for _, row in ipairs(session.combatSources) do list[#list + 1] = row.name .. "=" .. row.totalAmount end
        return table.concat(list, ",")
    end
    assert(Names(Ranking(nil)) == "Tank-Realm=1600,Me=700", "the unchanged boss ranking")
    for _, pet in ipairs({ "Imp", "Tank-OtherRealm", "" }) do
        local session = assert(Ranking(pet), "the attacker '" .. pet .. "' failed the whole target filter")
        assert(Names(session) == "Me=700,Tank-Realm=600", "the attacker '" .. pet .. "' was credited to a player")
    end
    -- Two sources share the short name "Tank", which the boss's other abilities use: it cannot pick one.
    f.SetRoster({
        { name = "Tank-RealmA", class = "WARRIOR", guid = "Player-A", total = 1500000, pps = 15000, death = 17 },
        { name = "Tank-RealmB", class = "WARRIOR", guid = "Player-B", total = 900000, pps = 9000, death = 34 },
    })
    assert(Ranking("Tank") == nil and win.status.text == "Target data unavailable",
        "an ambiguous attacker must fail the filter, not be guessed")
    -- A protected attacker name is never compared.
    f.SetRoster(roster)
    assert(Ranking(f.Secret("attacker")) == nil and win.status.text == "Target data unavailable",
        "a protected attacker name must fail the filter")
    C_DamageMeter.GetCombatSessionSourceFromType = source
    attacker, f.api.targetMode = nil, false
    D.ClearTarget(win)
    D.InvalidateTargets()
    D.Paint(win)
end

------------------------------------------------------------------ a threat window has no Session button (Forever fixture)
if forever then
    local win = assert(D.windows[1], "the threat fixture left no window")
    local c = S.Config(ID)
    c.headerVisible, c.headerSelectors, c.targetSelector = true, true, true
    local step = math.min(c.headerIconSize, c.headerHeight) + 2
    local function X(button) return button.points[#button.points][4] end
    local function Slot(index) return -3 - (index - 1) * step end
    D.SetWindowType(win, 0)
    D.StyleHeader(win)
    local buttons = win.buttons
    assert(buttons.session.shown and buttons.type.shown and buttons.target.shown, "a damage window shows all five buttons")
    assert(X(buttons.settings) == Slot(1) and X(buttons.reset) == Slot(2) and X(buttons.session) == Slot(3)
        and X(buttons.type) == Slot(4) and X(buttons.target) == Slot(5), "the damage window's button slots changed")
    local timerAt = X(win.timer)
    D.SetWindowType(win, D.THREAT)
    assert(win.meterType == D.THREAT and win.styleGen == M.styleGen, "the window did not switch to threat in place")
    assert(not buttons.session.shown and not buttons.session.configuredShown, "a threat window must not offer fights")
    assert(buttons.settings.shown and buttons.reset.shown and buttons.type.shown and not buttons.target.shown,
        "a threat window keeps settings, reset and the meter picker")
    assert(X(buttons.settings) == Slot(1) and X(buttons.reset) == Slot(2) and X(buttons.type) == Slot(3),
        "the meter picker must close the Session button's slot")
    assert(X(win.timer) == -3 - 3 * step - 2 and X(win.timer) > timerAt, "the header timer must follow the shorter button row")
    -- Without header selectors the row is settings and reset in both cases.
    c.headerSelectors = false
    D.StyleHeader(win)
    assert(buttons.settings.shown and buttons.reset.shown and not buttons.session.shown and not buttons.type.shown,
        "turning the selectors off leaves settings and reset")
    c.headerSelectors = true
    D.SetWindowType(win, 0)
    assert(buttons.session.shown and X(buttons.session) == Slot(3) and X(buttons.type) == Slot(4),
        "leaving threat must bring the Session button back")
end

print("Damage meter audit: Delves, report pipes and failed sends, Mythic+ reset, header timer greying, threat fights and search aliases passed")
