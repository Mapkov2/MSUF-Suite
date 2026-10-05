local _, P = ...
local NS, S = P.NS, P.Suite
-- Threat mode (WoW Forever): a meter window lists the group's threat on the
-- enemy you watch, like Omen did: highest first, each member's share of the
-- tank's threat, and a red "Pull aggro" row where you would take aggro. The
-- rows, styles, scrolling and own-row pin are the meter's own: the snapshot
-- below has the shape of a C_DamageMeter session (combatSources, maxAmount).
--
-- Data: UnitDetailedThreatSituation(unit, enemy), Blizzard's own source on
-- every client (its target frame shows rawPercentage, the share of the tank).
-- WoW Forever makes a boss's values secret (SecretWhenUnitThreatValuesRestricted):
-- they are never compared or sorted. A restricted enemy lists the group in
-- roster order, bars on the share of the tank, numbers through C formatters.
--
-- Cost: the events are registered only while a shown window shows threat
-- (Controller.lua UpdateEvents); UNIT_THREAT_LIST_UPDATE is filtered to the
-- target in C. Events only mark threat windows dirty, and one coalesced paint
-- runs at most every UPDATE_DELAY. The snapshot, its entries and the roster
-- are reused: a paint allocates nothing.
local D = P.DamageMeter
if not D.THREAT then return end
local M = D.M
local Public, Finite = S.Public, S.Finite
local IsSecret = NS.IsSecret
local Abbreviate = D.Abbreviate
local VALUE_FORMAT = D.VALUE_FORMAT
local floor, format, sort, min = math.floor, string.format, table.sort, math.min
local UPDATE_DELAY = .2
-- Omen's red pull bar; its text a lighter red that reads on any bar color.
local PULL_R, PULL_G, PULL_B = .86, .16, .12
local PULL_TEXT_R, PULL_TEXT_G, PULL_TEXT_B = 1, .45, .4
-- A secret share of the tank's threat, as text: through the secret-safe C
-- formatters (they take secret numbers from addon code). Chosen once here:
-- picking per value with and/or would truth-test the secret result.
local StringUtil = C_StringUtil or {}
local TruncateWhenZero, WrapString = StringUtil.TruncateWhenZero, StringUtil.WrapString
local SecretShare = Abbreviate
if TruncateWhenZero and WrapString then
    SecretShare = function(value) return WrapString(TruncateWhenZero(value), nil, "%") end
end
-- The value formats that show a second value: there it is the threat points.
local SECOND_VALUE = { [VALUE_FORMAT.PARENTHESES] = "%s (%s)", [VALUE_FORMAT.BAR] = "%s | %s",
    [VALUE_FORMAT.CUSTOM] = "%s (%s)" }

local RAID, PARTY, PARTY_PET = {}, {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
for i = 1, 4 do PARTY[i], PARTY_PET[i] = "party" .. i, "partypet" .. i end

-- The roster (tokens with their name, class and own-player flag; group and
-- pet changes mark it stale and the next paint rebuilds it, so a burst of
-- changes costs one rebuild), the watched enemy, and the reused snapshot.
local T = { units = {}, names = {}, classes = {}, own = {}, count = 0, entries = {}, stale = false, raid = false }
local list = {}
local session = { combatSources = list, maxAmount = 1 }
-- The pull row's class token has no class color and no class icon.
local pull = { name = S.Text("Pull aggro"), classFilename = "PULL", specIconID = 0, isLocalPlayer = false, order = 0, pull = true }

local function AddUnit(unit)
    local exists = UnitExists(unit)
    if not Public(exists) or not exists then return end
    local n = T.count + 1
    T.count = n
    T.units[n] = unit
    T.names[n] = GetUnitName(unit, true)
    local _, class = UnitClass(unit)
    T.classes[n] = Public(class) and type(class) == "string" and class or ""
    local own = UnitIsUnit(unit, "player")
    T.own[n] = Public(own) and own == true
end

-- Group members, and pets outside raids: a raid's pets rarely hold threat and
-- would double the reads of every paint.
function D.ThreatRoster()
    T.count, T.stale = 0, false
    local raid, members = IsInRaid(), GetNumGroupMembers()
    T.raid = Public(raid) and raid == true
    if T.raid and Finite(members) then
        for i = 1, min(40, members) do AddUnit(RAID[i]) end
    else
        AddUnit("player")
        AddUnit("pet")
        for i = 1, 4 do
            AddUnit(PARTY[i])
            AddUnit(PARTY_PET[i])
        end
    end
    for i = T.count + 1, #T.units do T.units[i], T.names[i], T.classes[i], T.own[i] = nil, nil, nil, nil end
end

local function Is(unit, test)
    local exists = UnitExists(unit)
    if not Public(exists) or not exists then return false end
    local result = test("player", unit)
    return Public(result) and result == true
end
-- Omen's choice: a hostile target, else the enemy a friendly target fights.
local function Enemy()
    if Is("target", UnitCanAttack) then return "target" end
    if Is("target", UnitCanAssist) and Is("targettarget", UnitCanAttack) then return "targettarget" end
end

-- Re-reads the watched enemy. True when the threat list filter must change:
-- a friendly target's enemy has no unit events of its own.
function D.ThreatTarget()
    local enemy = Enemy()
    local name = enemy and UnitName(enemy)
    T.enemyName = Public(name) and type(name) == "string" and name ~= "" and name or nil
    local refilter = (enemy == "targettarget") ~= (T.enemy == "targettarget")
    T.enemy = enemy
    return refilter
end
function D.ThreatListUnit() return T.enemy ~= "targettarget" and "target" or nil end
function D.ThreatEnemyName() return T.enemyName end

-- Threat window titles name the watched enemy.
local function UpdateTitles()
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.meterType == D.THREAT then D.UpdateTitle(win) end
    end
end

function D.ThreatStart()
    D.ThreatRoster()
    D.ThreatTarget()
    UpdateTitles()
end

function D.ThreatShown()
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown and win.meterType == D.THREAT then return true end
    end
    return false
end

local function Entry(n, i)
    local entry = T.entries[n]
    if not entry then
        entry = { specIconID = 0 }
        T.entries[n] = entry
    end
    entry.name, entry.classFilename, entry.isLocalPlayer, entry.order = T.names[i], T.classes[i], T.own[i], i
    list[n] = entry
    return entry
end

local function ByThreat(a, b)
    if a.totalAmount ~= b.totalAmount then return a.totalAmount > b.totalAmount end
    return a.order < b.order
end

-- The snapshot of the watched enemy's threat list. Plain values sort highest
-- first, number the members and add the pull row. A player who is not tanking
-- holds scaledPercentage of the pull threshold and rawPercentage of the tank's
-- threat, so the threshold and its share of the tank follow from the player's
-- own numbers, whether or not the tank is in the group.
function D.ThreatSession()
    if T.stale then D.ThreatRoster() end
    local n, top, threshold, pullShare, restricted = 0, 0, nil, nil, false
    local enemy = T.enemy
    for i = 1, enemy and T.count or 0 do
        local tanking, _, scaled, raw, threat = UnitDetailedThreatSituation(T.units[i], enemy)
        local secret = IsSecret(threat) or IsSecret(raw)
        if secret or (Finite(threat) and Finite(raw)) then
            n = n + 1
            local entry = Entry(n, i)
            entry.totalAmount, entry.points, entry.percent, entry.rank = threat, threat, raw, nil
            if secret then
                restricted = true
            else
                if threat > top then top = threat end
                if T.own[i] and not (Public(tanking) and tanking == true) and Finite(scaled) and scaled > 0 then
                    threshold, pullShare = threat * 100 / scaled, raw * 100 / scaled
                end
            end
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    if restricted then
        -- Unsorted, so unnumbered: every bar takes its member's share of the tank as it is.
        for i = 1, n do list[i].totalAmount = list[i].percent end
        session.maxAmount = 100
        return session
    end
    if threshold then
        n = n + 1
        pull.totalAmount, pull.points, pull.percent = threshold, threshold, pullShare
        list[n] = pull
        if threshold > top then top = threshold end
    end
    sort(list, ByThreat)
    local rank = 0
    for i = 1, n do
        local entry = list[i]
        if not entry.pull then
            rank = rank + 1
            entry.rank = rank
        end
    end
    session.maxAmount = top > 0 and top or 1
    return session
end

-- A threat row: its member number (none on the pull row or an unsorted list)
-- and its value, the share of the tank's threat (Omen's number) with the
-- threat points where the value format shows a second value. Rank and value
-- memoize under keys of their own (rank -n or 0, format -fmt), so a row that
-- showed a meter (Rows.lua, positive keys) never skips its first threat text.
function D.PaintThreatValue(row, source, maxAmount)
    D.SetBar(row, maxAmount, source.totalAmount)
    if source.pull then
        row.bar:SetStatusBarColor(PULL_R, PULL_G, PULL_B, M.style.barAlpha)
        row.nameText:SetTextColor(PULL_TEXT_R, PULL_TEXT_G, PULL_TEXT_B)
    end
    local rank = source.rank
    if M.style.rank and (rank and -rank or 0) ~= row.rank then
        row.rank = rank and -rank or 0
        row.rankText:SetText(rank and D.ranks[rank] or "")
    end
    local fmt = M.style.numberFormat
    local second, percent, points = SECOND_VALUE[fmt], source.percent, source.points
    if IsSecret(percent) or IsSecret(points) then
        row.mA, row.mP, row.mF = nil, nil, nil
        local share = SecretShare(percent)
        if second then row.valueText:SetFormattedText(second, share, Abbreviate(points)) else row.valueText:SetText(share) end
        return
    end
    local share = floor(percent + .5)
    if share == row.mP and points == row.mA and -fmt == row.mF then return end
    row.mP, row.mA, row.mF = share, points, -fmt
    local text = format("%d%%", share)
    if second then text = format(second, text, Abbreviate(points)) end
    row.valueText:SetText(text)
end

-- One paint per UPDATE_DELAY for every threat event since the last one; all
-- threat windows share the one snapshot it reads.
function D.ThreatTick()
    local session
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown and win.dirty and not win.faded and win.meterType == D.THREAT then
            if session then D.Paint(win, session, true) else D.Paint(win) end
            session = win.session
        end
    end
end
function D.ThreatEnable(context) D.threatJob = context:Coalesce(UPDATE_DELAY, D.ThreatTick) end

local function Changed()
    local dirty = false
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown and win.meterType == D.THREAT then win.dirty, dirty = true, true end
    end
    local job = D.threatJob
    if dirty and not job.pending then job:Request() end
end

-- UNIT_THREAT_LIST_UPDATE: filtered to the target in C, unfiltered only while
-- a friendly target's enemy is watched. That enemy has no token of its own:
-- its list repaints through another token (a nameplate, boss or focus) or on
-- target, roster and combat changes.
function D.ThreatListUpdated(_, _, unit)
    if T.enemy == "targettarget" then
        if not Public(unit) then return end
        local same = UnitIsUnit(unit, "targettarget")
        if not (Public(same) and same) then return end
    end
    Changed()
end

-- PLAYER_TARGET_CHANGED.
function D.ThreatTargetChanged()
    if D.ThreatTarget() then D.UpdateEvents() end
    UpdateTitles()
    Changed()
end
-- The target's UNIT_TARGET (filtered in C): it matters only while the target
-- is not the watched enemy itself, as a hostile target's own target never does.
function D.ThreatTargetsTarget()
    if T.enemy == "target" then return end
    D.ThreatTargetChanged()
end

-- GROUP_ROSTER_UPDATE through the controller's roster handler: the next
-- paint rebuilds the roster.
function D.ThreatRosterChanged()
    T.stale = true
    Changed()
end
-- UNIT_PET: a raid lists no pets.
function D.ThreatPetChanged()
    if T.raid then return end
    D.ThreatRosterChanged()
end

-- Edit Mode and the options preview: a tank, four members and the pull row
-- (built once).
local SAMPLE = { { "WARRIOR", 100, 52e3 }, { "MAGE", 96, 49.9e3 }, { "ROGUE", 88, 45.8e3 }, { "PRIEST", 63, 32.8e3, true },
    { "HUNTER", 41, 21.3e3 } }
function D.ThreatSample()
    local sample = D.threatSample
    if sample then return sample end
    local names, sources = LOCALIZED_CLASS_NAMES_MALE or {}, {}
    sources[1] = { name = pull.name, classFilename = "PULL", specIconID = 0, isLocalPlayer = false,
        order = 0, pull = true, totalAmount = 57.2e3, points = 57.2e3, percent = 110 }
    for i, data in ipairs(SAMPLE) do
        sources[i + 1] = { name = names[data[1]] or data[1], classFilename = data[1], specIconID = 0, rank = i,
            isLocalPlayer = data[4] == true, order = i, totalAmount = data[3], points = data[3], percent = data[2] }
    end
    sample = { combatSources = sources, maxAmount = 57.2e3 }
    D.threatSample = sample
    return sample
end
