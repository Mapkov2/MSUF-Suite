local root = assert(arg[1], "repository root required")
MSUF_DM_FEATURE_TESTS = true
-- The runtime's private namespace, for the preview file at the end.
local originalLoad, private = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
dofile(root .. "/tools/tests/suite_damage_meter_contract.lua")
loadfile = originalLoad
local f = assert(MSUF_DM_FIXTURE)
local D, S, NS, M, api, Region = f.D, f.S, f.NS, f.M, f.api, f.Region
-- Damage meter chat report and window comfort: report lines, channels,
-- refusals and staggering; click-through at the combat edges; window scale;
-- smooth fill; Hide in Delves; meter per role next to Mythic+.
local TYPE = D.TYPE
local function Settings(values) assert(S.SetMany("damageMeter", values)) end
local function Find(node, text)
    for _, item in ipairs(node.items) do
        if item.text == text then return item end
        if item.items then
            local found = Find(item, text)
            if found then return found end
        end
    end
end

------------------------------------------------------------------ client stubs
local sent, printed, locked = {}, {}, false
C_ChatInfo = { InChatMessagingLockdown = function() return locked end,
    SendChatMessage = function(text, chat, language, target)
        sent[#sent + 1] = { text = text, chat = chat, language = language, target = target }
    end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) printed[#printed + 1] = text end }
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
local group, target = { home = false, instance = false, raid = false, guild = false, officer = false }, nil
IsInGroup = function(category)
    if category == LE_PARTY_CATEGORY_HOME then return group.home end
    if category == LE_PARTY_CATEGORY_INSTANCE then return group.instance end
    return group.home or group.instance
end
IsInRaid = function(category) return group.raid and (category == nil or category == LE_PARTY_CATEGORY_HOME) end
IsInGuild = function() return group.guild end
C_GuildInfo = { IsGuildOfficer = function() return group.officer end }
UnitIsPlayer = function(unit) return unit == "target" and target ~= nil and target.player == true end
UnitIsUnit = function(first, second) return first == "target" and second == "player" and target ~= nil and target.self == true end
UnitIsConnected = function() return true end
GetUnitName = function(unit) return unit == "target" and target and target.name or nil end
-- C_Timer.After calls are kept so a test can fire the report's tick itself.
local queued, after = {}, C_Timer.After
C_Timer.After = function(delay, callback)
    queued[#queued + 1] = { delay = delay, callback = callback }
    return after(delay, callback)
end
-- Fires the pending report tick once its wait is over; false when none waits.
local function Tick()
    local handle = M.context.timers[D.ReportTick]
    if not (handle and handle.due) then return false end
    f.SetTime(handle.due + .001)
    for i = #queued, 1, -1 do
        if queued[i].callback == handle.tick then
            table.remove(queued, i)
            handle.tick()
            return true
        end
    end
    return false
end
-- The fixture's status bar records one value; these keep the interpolation
-- argument and every value written.
function Region:SetValue(value, ...)
    self.value, self.valueWrites = value, (self.valueWrites or 0) + 1
    self.valueArgs, self.valueFill = select("#", ...), (...)
    self.valueLog = self.valueLog or {}
    self.valueLog[#self.valueLog + 1] = { value = value, fill = (...) }
end
function Region:SetMinMaxValues(low, high, ...)
    self.min, self.max, self.rangeWrites = low, high, (self.rangeWrites or 0) + 1
    self.rangeArgs, self.rangeFill = select("#", ...), (...)
end
local function Reset() sent, printed = {}, {} end
local function Names()
    local list = {}
    for _, channel in ipairs(D.ReportChannels()) do list[#list + 1] = channel.chat end
    return table.concat(list, ",")
end
local function Last() return printed[#printed] or "" end

local roster = {
    { name = "Tank-Realm", class = "WARRIOR", guid = "Player-Tank", total = 1500000, pps = 15000, death = 17 },
    { name = "Me", class = "MAGE", guid = "Player-1", total = 900000, pps = 9000, death = 34, isLocal = true, spec = 135932 },
    { name = "Healer-Realm", class = "PRIEST", guid = "Player-Heal", total = 300000, pps = 3000, death = 51 },
}
f.SetCombat(false)
f.SetZone("none")
f.SetRoster(roster)
api.secret, api.empty, api.targetMode = false, false, false
Settings({ enabled = true, windowCount = 2, visibility = 1, w1Type = 1, w2Type = 3, w1Session = 1, w2Session = 1,
    showPlayer = false, numberFormat = 3, percent = false, reportLines = 2, w1Locked = false })
local win, other = D.windows[1], D.windows[2]
local c = M.config

------------------------------------------------------------------ keys and defaults
do
    local rules = S.catalog.damageMeter.rules
    assert(c.reportLines == 2 and c.smoothFill == 1, "report lines default 5, smooth fill default Off")
    assert(NS.DamageMeterReportLines[c.reportLines] == 5 and rules.reportLines.choices[3] == "10 lines")
    for i = 1, D.MAX do
        local keys = D.KEYS[i]
        assert(c["w" .. i .. "ClickThrough"] == 1 and c["w" .. i .. "Scale"] == 100 and c["w" .. i .. "HideDelve"] == false
            and c["w" .. i .. "RoleTank"] == 1 and c["w" .. i .. "RoleHealer"] == 1 and c["w" .. i .. "RoleDamager"] == 1,
            "new window settings must default to today's behaviour")
        for _, suffix in ipairs({ "Scale", "ClickThrough", "HideDelve", "RoleTank", "RoleHealer", "RoleDamager" }) do
            assert(keys[suffix] == "w" .. i .. suffix and rules[keys[suffix]].window == i, "per-window key lost its window: " .. suffix)
        end
    end
    local suffixes = {}
    for _, suffix in ipairs(D.WindowSuffixes()) do suffixes[suffix] = true end
    for _, suffix in ipairs({ "Scale", "ClickThrough", "HideDelve", "RoleTank", "RoleHealer", "RoleDamager" }) do
        assert(suffixes[suffix], "closing a window would not move " .. suffix)
    end
    -- Closing window 2 moves the later windows' new settings down and frees the last slot.
    Settings({ windowCount = 3, w3Scale = 130, w3ClickThrough = 3, w3HideDelve = true, w3RoleTank = 5 })
    assert(D.CloseWindow(D.windows[2]))
    assert(c.w2Scale == 130 and c.w2ClickThrough == 3 and c.w2HideDelve == true and c.w2RoleTank == 5
        and c.w3Scale == 100 and c.w3ClickThrough == 1 and c.w3HideDelve == false and c.w3RoleTank == 1,
        "closing a window did not shift the new per-window settings")
    Settings({ windowCount = 2, w2Scale = 100, w2ClickThrough = 1, w2HideDelve = false, w2RoleTank = 1, w2Type = 3 })
    other = D.windows[2]
end

------------------------------------------------------------------ report: channels and menu
assert(Names() == "SAY", "only Say is usable outside every group, guild and target")
group.home = true
assert(Names() == "SAY,PARTY")
group.raid = true
assert(Names() == "SAY,PARTY,RAID")
group.instance = true
assert(Names() == "SAY,PARTY,RAID,INSTANCE_CHAT")
group.guild = true
assert(Names() == "SAY,PARTY,RAID,INSTANCE_CHAT,GUILD")
group.officer = true
assert(Names() == "SAY,PARTY,RAID,INSTANCE_CHAT,GUILD,OFFICER")
target = { name = "Target-Realm", player = true, self = true }
assert(Names() == "SAY,PARTY,RAID,INSTANCE_CHAT,GUILD,OFFICER", "your own target is not a whisper target")
target.self = false
assert(Names() == "SAY,PARTY,RAID,INSTANCE_CHAT,GUILD,OFFICER,WHISPER")
group.raid, group.instance, group.officer, group.guild, target = false, false, false, false, nil
assert(Names() == "SAY,PARTY")

D.HeaderButtonClick(win.buttons.settings)
local report = assert(Find(f.GetMenu(), "Report"), "window menu has no Report entry")
assert(#report.items == 2 and report.items[1].text == "Say" and report.items[2].text == "Party",
    "the Report menu must list the usable channels only")

------------------------------------------------------------------ report: lines and format
Reset()
f.SetZone("party")
assert(D.SendReport(win, "PARTY"))
assert(#sent == 1 and sent[1].text == "Damage Done [1:40]" and sent[1].chat == "PARTY", "the header goes out at once")
assert(D.ReportTick and M.report and M.context.timers[D.ReportTick].due, "the other lines wait for the context timer")
assert(Tick() and #sent == 2 and sent[2].text == "1. Tank 1.5M (15K) 56%", "ranked line 1: " .. tostring(sent[2] and sent[2].text))
assert(Tick() and #sent == 3 and sent[3].text == "2. Me 900K (9K) 33%")
assert(Tick() and #sent == 4 and sent[4].text == "3. Healer 300K (3K) 11%")
assert(not M.report and not Tick(), "the last line ends the report")
assert(sent[4].target == nil and sent[4].language == nil)

-- A report starts outside combat, but its staggered tail can become due
-- after combat begins. Test both the event edge before lockdown and the
-- lockdown guard before the event; neither may send a remaining row.
for _, edge in ipairs({ "event", "lockdown" }) do
    Reset()
    f.SetCombat(false)
    assert(D.SendReport(win, "PARTY") and #sent == 1, edge .. ": report header did not start")
    if edge == "event" then f.Event("PLAYER_REGEN_DISABLED") else f.SetCombat(true) end
    assert(Tick() and #sent == 1 and not M.report and not Tick(),
        edge .. ": a queued report sent rows in combat or kept its tail")
    f.SetCombat(false)
    f.Event("PLAYER_REGEN_ENABLED")
end

-- The lines follow the window's own number format, fight and meter.
Reset()
Settings({ numberFormat = 1 })
assert(D.SendReport(win, "PARTY") and Tick() and sent[2].text == "1. Tank 15K 56%", "per-second format")
while Tick() do end
Reset()
Settings({ numberFormat = 5, valueOrder = 3, valueSeparator = 4 })
assert(D.SendReport(win, "PARTY") and Tick() and sent[2].text == "1. Tank 15K || 1.5M || 56%", "custom layout: chat takes a bar doubled")
while Tick() do end
Reset()
Settings({ numberFormat = 3, w1Session = 2 })
assert(D.SendReport(win, "PARTY") and sent[1].text == "Damage Done (Overall) [1:40]", "overall header")
while Tick() do end
Reset()
D.SetWindowSession(win, D.SESSION.CURRENT, 7, 65)
assert(D.SendReport(win, "PARTY") and sent[1].text == "Damage Done - Fight 7 [1:40]", "pinned fight header")
while Tick() do end
D.SetWindowSession(win, D.SESSION.CURRENT, nil, nil)
Settings({ w1Session = 1, w1Type = TYPE.Deaths + 1 })
Reset()
assert(D.SendReport(win, "PARTY") and Tick() and sent[2].text == "1. Tank 0:17", "deaths report the time of death")
while Tick() do end
Settings({ w1Type = TYPE.DamageDone + 1 })

-- 3 / 5 / 10 lines of a long ranking.
do
    local many = {}
    for i = 1, 12 do many[i] = { name = "P" .. i, class = "MAGE", guid = "Player-" .. i, total = 1000 * (13 - i), pps = 10, death = i } end
    f.SetRoster(many)
    D.MarkAll()
    D.PaintDirty()
    for choice, lines in ipairs({ 3, 5, 10 }) do
        Settings({ reportLines = choice })
        Reset()
        assert(D.SendReport(win, "PARTY"))
        while Tick() do end
        assert(#sent == lines + 1, "reportLines " .. choice .. " sent " .. #sent .. " messages")
    end
    f.SetRoster(roster)
    Settings({ reportLines = 2 })
    D.MarkAll()
    D.PaintDirty()
end

------------------------------------------------------------------ report: refusals
Reset()
f.SetCombat(true)
f.Event("PLAYER_REGEN_DISABLED")
assert(not D.SendReport(win, "PARTY") and #sent == 0 and Last():find("Available after combat", 1, true),
    "a report in combat must say Available after combat and send nothing")
D.HeaderButtonClick(win.buttons.settings)
assert(Find(f.GetMenu(), "Report"), "the Report entry stays in combat so that it can explain")
f.SetCombat(false)
f.Event("PLAYER_REGEN_ENABLED")
printed = {}
-- Out of combat but still protected (declassification lags the combat edge).
api.secret = true
assert(not D.SendReport(win, "PARTY") and #sent == 0 and Last():find("Available after combat", 1, true),
    "protected values must never be sent")
api.secret = false
-- A protected total alone (the percent's denominator) is enough to refuse.
do
    local get = C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(kind, meter)
        local session = get(kind, meter)
        session.totalAmount = f.Secret("total")
        return session
    end
    printed = {}
    assert(not D.SendReport(win, "PARTY") and #sent == 0 and Last():find("Available after combat", 1, true),
        "a protected session total was sent")
    C_DamageMeter.GetCombatSessionFromType = get
end
-- Chat lock, a channel that went away since the menu opened, and no data.
printed, locked = {}, true
assert(not D.SendReport(win, "PARTY") and #sent == 0 and Last():find("blocked", 1, true), "chat messaging lockdown")
locked = false
group.home = false
printed = {}
assert(not D.SendReport(win, "PARTY") and #sent == 0 and Last():find("not available", 1, true), "a channel that is gone")
group.home = true
api.empty = true
printed = {}
assert(not D.SendReport(win, "PARTY") and #sent == 0 and Last():find("nothing to report", 1, true), "an empty ranking")
api.empty = false
-- Threat (WoW Forever) has no ranking to report.
do
    local threat = D.THREAT
    D.THREAT = #NS.DamageMeterTypeLabels
    win.meterType = D.THREAT
    D.HeaderButtonClick(win.buttons.settings)
    assert(Find(f.GetMenu(), "Report").enabled == false, "a threat window cannot report")
    win.meterType, D.THREAT = TYPE.DamageDone, threat
end

------------------------------------------------------------------ report: channels, whisper, say, staggering
Reset()
target = { name = "Target-Realm", player = true }
D.HeaderButtonClick(win.buttons.settings)
f.Pick(f.GetMenu(), "Whisper target")
assert(sent[1].chat == "WHISPER" and sent[1].target == "Target-Realm", "whisper goes to the target's name")
while Tick() do end
target = nil
-- Say outside an instance needs the click's hardware event: no waiting.
Reset()
f.SetZone("none")
assert(D.SendReport(win, "SAY") and #sent == 4 and not M.report and not Tick(), "say outside instances sends every line at once")
Reset()
f.SetZone("party")
assert(D.SendReport(win, "SAY") and #sent == 1 and Tick() and #sent == 2, "say inside an instance is staggered like the rest")
while Tick() do end
-- A second report waits for the first.
Reset()
assert(D.SendReport(win, "PARTY") and not D.SendReport(win, "PARTY") and #sent == 1, "two reports must not interleave")
while Tick() do end
-- Chat locking mid-report stops it; disabling the module stops its timer.
Reset()
assert(D.SendReport(win, "PARTY"))
locked = true
printed = {}
assert(Tick() and #sent == 1 and not M.report and Last():find("blocked", 1, true), "a lock mid-report ends it")
locked = false
Reset()
assert(D.SendReport(win, "PARTY"))
local handle = M.context.timers[D.ReportTick]
local tick = handle.tick
Settings({ enabled = false })
tick()
assert(#sent == 1 and not M.report, "a disabled module sent a late line")
Settings({ enabled = true })
win, other = D.windows[1], D.windows[2]
f.SetZone("none")

------------------------------------------------------------------ click-through at the regen edges
do
    function Region:EnableMouse(enabled) self.mouse = enabled end
    local function All(w, expected)
        local frames = { w.frame, w.header, w.body, w.grip }
        for _, button in pairs(w.buttons) do frames[#frames + 1] = button end
        for _, row in pairs(w.rows) do frames[#frames + 1] = row end
        if w.panel then
            frames[#frames + 1] = w.panel
            frames[#frames + 1] = w.panel.targetsTab
            frames[#frames + 1] = w.panel.spellsTab
            for _, row in pairs(w.bdRows) do frames[#frames + 1] = row end
        end
        for _, frame in ipairs(frames) do
            if (frame.mouse ~= false) ~= expected then return false end
        end
        return true
    end
    Settings({ windowCount = 3, w1ClickThrough = 2, w2ClickThrough = 1, w3ClickThrough = 2, w3Type = 1 })
    local third = D.windows[3]
    assert(All(win, true) and All(other, true) and All(third, true), "click-through In combat must leave windows usable outside combat")
    assert(#third.rows == 3, "window 3 should have drawn three rows before the combat")
    D.OpenBreakdown(win, 1)
    assert(win.panel and win.bd.open)
    f.SetCombat(true)
    f.Event("PLAYER_REGEN_DISABLED")
    assert(All(win, false) and All(other, true) and All(third, false), "the combat start did not make the windows click-through")
    -- Rows made during the combat are click-through too.
    D.CloseBreakdown(win, true)
    local many = {}
    for i = 1, 6 do many[i] = { name = "P" .. i, class = "MAGE", guid = "Player-" .. i, total = 1000 * (7 - i), pps = 10, death = i } end
    f.SetRoster(many)
    D.MarkAll()
    D.PaintDirty()
    assert(#third.rows == 6 and All(third, false) and All(win, false), "a row created in combat took the mouse")
    f.SetCombat(false)
    f.Event("PLAYER_REGEN_ENABLED")
    assert(All(win, true) and All(third, true), "the combat end did not give the mouse back")
    f.SetRoster(roster)
    -- Always: click-through now, except while Edit Mode or the preview places windows, or for Mouseover windows.
    Settings({ w1ClickThrough = 3 })
    assert(All(win, false) and All(other, true), "Always must not wait for combat")
    assert(S.DamageMeterPreview(true) and All(win, true), "the preview needs the mouse to place windows")
    assert(S.DamageMeterPreview(false) and All(win, false))
    Settings({ visibility = 4 })
    assert(All(win, true), "a Mouseover window needs the mouse to appear")
    Settings({ visibility = 1 })
    assert(All(win, false))
    Settings({ w1ClickThrough = 1, windowCount = 2 })
    assert(All(win, true), "Never gives the mouse back")
end

------------------------------------------------------------------ window scale keeps the saved position
do
    function Region:SetScale(scale) self.scale = scale end
    function Region:GetScale() return self.scale or 1 end
    function Region:GetEffectiveScale() return self.scale or 1 end
    local frame = win.frame
    Settings({ w1Scale = 100, w1X = -100, w1Y = 50 })
    Settings({ w1Scale = 150 })
    assert(frame.scale == 1.5, "the window frame did not take its scale")
    assert(c.w1X == -67 and c.w1Y == 33, "a new scale must keep the corner in place: " .. c.w1X .. "," .. c.w1Y)
    local point = frame.points[1]
    assert(point[1] == "BOTTOMRIGHT" and point[4] == -67 and point[5] == 33, "the window was not re-anchored")
    assert(math.abs(point[4] * 1.5 + 100) <= 1 and math.abs(point[5] * 1.5 - 50) <= 1, "the window moved on screen")
    Settings({ w1Scale = 100 })
    assert(frame.scale == 1 and c.w1X == -100 and c.w1Y == 50, "scale back to 100% must restore the position")
    -- A change that brings its own offsets (profile, reset, import) keeps them.
    Settings({ w1Scale = 150, w1X = -300 })
    assert(c.w1X == -300 and c.w1Y == 50, "an explicit position was rescaled")
    win.placedConfig = {}
    Settings({ w1Scale = 100 })
    assert(c.w1X == -300, "another profile's offsets were rescaled")
    -- Rescaled offsets stay inside their setting.
    Settings({ w1Scale = 100, w1X = -4000 })
    Settings({ w1Scale = 50 })
    assert(c.w1X == -4000, "a rescaled offset left its range")
    -- Saving a drag: the frame's edges are in its own scale.
    Settings({ w1Scale = 150, w1X = -67, w1Y = 33 })
    frame.right, frame.bottom = 1920 / 1.5 - 200, 40
    D.SaveGeometry(win, false)
    assert(c.w1X == -200 and c.w1Y == 40, "a dragged scaled window saved " .. c.w1X .. "," .. c.w1Y)
    Settings({ w1Scale = 100, w1X = -20, w1Y = 20 })
    frame.right, frame.bottom = 1920 - 30, 25
    D.SaveGeometry(win, false)
    assert(c.w1X == -30 and c.w1Y == 25, "an unscaled window saved a different position than before")
end

------------------------------------------------------------------ smooth fill
do
    local function Paint()
        D.MarkAll()
        D.PaintDirty()
        return f.Row(win, 1).bar
    end
    -- The fixture's Enum lacks it; every declared client has it (client_api_snapshot.json).
    Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
    Settings({ smoothFill = 1 })
    local bar = Paint()
    assert(bar.valueArgs == 0 and bar.rangeArgs == 0, "Off must keep the plain bar writes")
    Settings({ smoothFill = 2 })
    bar = Paint()
    assert(bar.valueArgs == 1 and bar.valueFill == 1 and bar.rangeArgs == 1 and bar.rangeFill == 1,
        "On must ease the bar's range and value")
    -- Protected values go to the same C writes.
    api.secret = true
    local writes = bar.valueWrites
    bar = Paint()
    assert(bar.valueWrites > writes and bar.valueFill == 1, "protected values must reach the smooth write")
    api.secret = false
    Settings({ smoothFill = 1 })
    bar = Paint()
    assert(bar.valueArgs == 0 and bar.rangeArgs == 0, "turning smooth fill off restores the plain writes")
end

------------------------------------------------------------------ Hide in Delves
do
    -- A Delve: scenarios report their own instance type, the client's Delve
    -- test tells them apart (the audit contract covers the other scenarios).
    C_DelvesUI = { HasActiveDelve = function() return true end }
    f.SetZone("scenario")
    Settings({ windowCount = 2, w1HideDungeon = true, w1HideDelve = false, w2HideDungeon = false, w2HideDelve = true })
    D.EvaluateVisibility()
    assert(win.shown and not other.shown, "Hide in Delves must hide only the window that has it")
    f.SetZone("party")
    D.EvaluateVisibility()
    assert(not win.shown and other.shown, "Hide in dungeons no longer owns scenarios, and still owns dungeons")
    f.SetZone("none")
    Settings({ w1HideDungeon = false, w2HideDelve = false })
    D.EvaluateVisibility()
    D.HeaderButtonClick(win.buttons.settings)
    local item = assert(Find(f.GetMenu(), "Hide in Delves"), "the window menu lacks Hide in Delves")
    item.callback(item.data)
    assert(c.w1HideDelve == true, "the menu entry did not set Hide in Delves")
    Settings({ w1HideDelve = false })
    -- Profiles from before the option keep their behaviour: derived once.
    local stored = { suite = { schema = 1, modules = { damageMeter = {
        w1HideDungeon = true, w2HideDungeon = false, w3HideDungeon = true, w3HideDelve = false } } } }
    S.Normalize(stored)
    local saved = stored.suite.modules.damageMeter
    assert(saved.w1HideDelve == true, "a profile that hid in dungeons must keep hiding in Delves")
    assert(saved.w2HideDelve == false, "a profile that showed in dungeons must keep showing in Delves")
    assert(saved.w3HideDelve == false, "a stored choice must not be derived again")
    saved.w1HideDungeon, saved.w1HideDelve = true, false
    S.Normalize(stored)
    assert(saved.w1HideDelve == false, "unticking Hide in Delves must stick")
    local fresh = { suite = { schema = 1, modules = {} } }
    S.Normalize(fresh)
    assert(fresh.suite.modules.damageMeter.w1HideDelve == false and fresh.suite.modules.damageMeter.w1HideDungeon == false)
end

------------------------------------------------------------------ meter per role next to Mythic+
do
    local role, specIndex, keyActive = "TANK", 1, false
    C_SpecializationInfo = { GetSpecialization = function() return specIndex end,
        GetSpecializationInfo = function(index) return 250 + index, "Spec", "", 0, role end }
    C_ChallengeMode = { IsChallengeModeActive = function() return keyActive end }
    local function Spec(newRole)
        role = newRole
        f.Event("PLAYER_SPECIALIZATION_CHANGED", "player")
    end
    local DAMAGE_TAKEN, HEALING, DPS = TYPE.DamageTaken + 2, TYPE.HealingDone + 2, TYPE.Dps + 2
    Settings({ windowCount = 2, w1Type = 1, w2Type = 3, w1RoleTank = 1, w1RoleHealer = 1, w1RoleDamager = 1,
        w2RoleTank = 1, w2RoleHealer = 1, w2RoleDamager = 1, w1MythicType = 1, w2MythicType = 1 })
    assert(not f.Registered("PLAYER_SPECIALIZATION_CHANGED"), "role events must stay off while every role keeps its meter")
    Settings({ w1RoleTank = DAMAGE_TAKEN, w1RoleHealer = HEALING, w2RoleHealer = DPS })
    assert(f.Registered("PLAYER_SPECIALIZATION_CHANGED"), "role events are needed once a role has a meter")
    Spec("TANK")
    assert(win.meterType == TYPE.DamageTaken and c.w1Type == TYPE.DamageTaken + 1 and other.meterType == TYPE.HealingDone,
        "tank did not get its meter")
    Spec("HEALER")
    assert(win.meterType == TYPE.HealingDone and other.meterType == TYPE.Dps, "healer did not switch both windows")
    Spec("DAMAGER")
    assert(win.meterType == TYPE.HealingDone and other.meterType == TYPE.Dps, "Keep must leave the meters alone")
    -- Another specialization of the same role keeps a meter the player picked.
    Spec("HEALER")
    D.SetWindowType(win, TYPE.Absorbs)
    Spec("HEALER")
    assert(win.meterType == TYPE.Absorbs, "a change inside one role overrode a manual pick")
    -- Login re-applies; later world entries do not.
    f.Event("PLAYER_ENTERING_WORLD", false, false)
    assert(win.meterType == TYPE.Absorbs, "a zone change overrode a manual pick")
    f.Event("PLAYER_ENTERING_WORLD", true, false)
    assert(win.meterType == TYPE.HealingDone, "the first world entry did not apply the role meter")

    -- Mythic+: a window with a Mythic+ meter belongs to it while a key runs.
    Settings({ w1MythicType = TYPE.Interrupts + 2, w1RoleTank = DAMAGE_TAKEN, w1RoleHealer = HEALING,
        w2RoleTank = TYPE.Absorbs + 2 })
    Spec("TANK")
    assert(win.meterType == TYPE.DamageTaken and other.meterType == TYPE.Absorbs, "outside a key the role meter applies")
    keyActive = true
    f.Event("CHALLENGE_MODE_START")
    assert(win.meterType == TYPE.Interrupts and other.meterType == TYPE.Absorbs, "the key's start must win over the role meter")
    Spec("HEALER")
    assert(win.meterType == TYPE.Interrupts, "a role meter overrode the Mythic+ meter during the key")
    assert(other.meterType == TYPE.Dps, "a window without a Mythic+ meter still follows its role")
    f.Event("PLAYER_ENTERING_WORLD", true, false)
    assert(win.meterType == TYPE.Interrupts, "a login in the key overrode the Mythic+ meter")
    keyActive = false
    Spec("TANK")
    assert(win.meterType == TYPE.DamageTaken and other.meterType == TYPE.Absorbs, "after the key the role meter applies again")
    -- A Mythic+ choice of Keep leaves the window to its role, key or not.
    Settings({ w1MythicType = 1 })
    keyActive = true
    Spec("HEALER")
    assert(win.meterType == TYPE.HealingDone, "Keep at Mythic+ start must not block the role meter")
    keyActive = false
    Settings({ w1RoleTank = 1, w1RoleHealer = 1, w2RoleTank = 1, w2RoleHealer = 1 })
    assert(not f.Registered("PLAYER_SPECIALIZATION_CHANGED"), "role events stay registered after the last role meter is gone")
end

------------------------------------------------------------------ preview (last: it switches the module off)
do
    assert(originalLoad(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
    M:Disable()
    M.active = false
    local config = S.Config("damageMeter")
    config.w1Width, config.w1Height, config.w1Type, config.w1Session = 300, 170, 1, 1
    config.w1Scale, config.smoothFill = 150, 1
    local stage = CreateFrame("Frame", nil, UIParent)
    local preview = assert(S.DamageMeterDrawMenuPreview(stage, 1))
    assert(preview.previewZoom == 1.5, "the preview did not hand the page the window's scale")
    local bar = preview.rows[1].bar
    assert(bar.valueArgs == 0, "Off: the preview bars write plainly")
    config.smoothFill = 2
    S.DamageMeterDrawMenuPreview(stage, 1)
    local log = bar.valueLog
    assert(#log >= 2 and log[#log].value == 125000 and log[#log].fill == 1 and log[#log - 1].value == 0
        and log[#log - 1].fill == nil, "turning smooth fill on must show the bars easing in from empty")
    config.w1Scale = 100
    assert(S.DamageMeterDrawMenuPreview(stage, 1).previewZoom == 1)
    local writes = #log
    config.w1Width = 310
    S.DamageMeterDrawMenuPreview(stage, 1)
    for i = writes + 1, #log do assert(log[i].value ~= 0, "a later redraw emptied the bars again") end
end

print("Damage meter report: lines and format, channels, refusals, staggering, click-through, scale, smooth fill, Delves and role meters passed")
