local _, P = ...
local NS, S = P.NS, P.Suite
-- Damage meter runtime. The DamageMeter/*.lua files share the private table
-- below. Loading them touches nothing in the client: frames, events and timers
-- exist only while the module is active and has something to show.
local D = { windows = {}, MAX = 5, KEYS = {}, OVERALL = 0, CURRENT = 1 }
P.DamageMeter = D
-- damageMeterEnabled is declared on the catalog entry (restored on disable).
local M = { styleGen = 0, events = {} }
D.M = M
local Public, Finite = S.Public, S.Finite
-- The client's secret test (Platform.lua) for the per-row readers.
local IsSecret = NS.IsSecret
local floor, format = math.floor, string.format

-- Enum.DamageMeterType values are identical on every client (catalog choice
-- index = value + 1). Dps/Hps lead with the rate, like Blizzard's meter;
-- interrupts and dispels are plain counts. Damage and healing break down
-- into targets as well as spells.
local TYPE = Enum.DamageMeterType
D.TYPE = TYPE
D.perSecond = { [TYPE.Dps] = true, [TYPE.Hps] = true }
D.countOnly = { [TYPE.Interrupts] = true, [TYPE.Dispels] = true }
D.damageTypes = { [TYPE.DamageDone] = true, [TYPE.Dps] = true }
D.healingTypes = { [TYPE.HealingDone] = true, [TYPE.Hps] = true }
D.targetTypes = { [TYPE.DamageDone] = true, [TYPE.Dps] = true, [TYPE.HealingDone] = true, [TYPE.Hps] = true }
-- Catalog choice values (MSUF_Suite/Core/Catalog/DamageMeter.lua).
D.VISIBILITY, D.SESSION, D.ICON = NS.DamageMeterVisibility, NS.DamageMeterSession, NS.DamageMeterIconStyle
D.ROW_BORDER, D.TEXT_STYLE, D.VALUE_FORMAT = NS.DamageMeterRowBorder, NS.DamageMeterTextStyle, NS.DamageMeterValueFormat

-- Per-window setting names, built once so paint and visibility paths never
-- concatenate keys.
local suffixes = { "Type", "Session", "Width", "Height", "X", "Y", "Locked", "HideDungeon", "HideRaid", "HidePvP",
    "HideWorld" }
for i = 1, D.MAX do
    local keys = {}
    for _, suffix in ipairs(suffixes) do keys[suffix] = "w" .. i .. suffix end
    D.KEYS[i] = keys
end

-- Plain junk (nil, NaN, infinity) becomes 0; secret values pass through for
-- C sinks. Runs for every value of every painted row: one secret test, no
-- Lua reader call.
local HUGE = math.huge
function D.Num(value)
    if IsSecret(value) then return value end
    if type(value) == "number" and value == value and value > -HUGE and value < HUGE then return value end
    return 0
end

function D.Count(list)
    if type(list) ~= "table" then return 0 end
    local count = #list
    return not IsSecret(count) and count or 0
end

-- Ambiguate accepts secret names; its result goes directly to text sinks.
-- Character-count shortening remains limited to public strings.
function D.Short(name)
    if not IsSecret(name) and type(name) ~= "string" then return "" end
    local config = M.config
    if not (config and config.showRealm) then name = Ambiguate(name, "short") end
    if IsSecret(name) then return name end
    local maxChars = config and config.nameMaxChars or 0
    if maxChars <= 0 then return name end
    local index, chars = 1, 0
    while index <= #name and chars < maxChars do
        local first = name:byte(index)
        local bytes = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
        index = index + bytes
        chars = chars + 1
    end
    if index > #name then return name end
    return name:sub(1, index - 1) .. (config.nameEllipsis and "..." or "")
end

-- Plain amounts: three significant digits with K/M/B units. Called only when
-- a row's plain value changed.
function D.Compact(value)
    local sign = ""
    if value < 0 then sign, value = "-", -value end
    if value < 999.5 then return sign .. floor(value + .5) end
    local unit, divisor = "K", 1e3
    if value >= 999.5e6 then unit, divisor = "B", 1e9 elseif value >= 999.5e3 then unit, divisor = "M", 1e6 end
    value = value / divisor
    return format(value < 9.995 and "%s%.2f%s" or value < 99.95 and "%s%.1f%s" or "%s%.0f%s", sign, value, unit)
end

-- Native formatting accepts secret values. Constant raw suffixes avoid
-- client-localized global strings; the config is created once on opt-in.
local englishAbbreviation
function D.ConfigureAbbreviation()
    if not M.config.englishNumbers or englishAbbreviation then return end
    local points = {}
    for _, unit in ipairs({ { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        points[#points + 1] = { breakpoint = unit[1] * 10, abbreviation = unit[2],
            significandDivisor = unit[1], fractionDivisor = 1, abbreviationIsGlobal = false }
        points[#points + 1] = { breakpoint = unit[1], abbreviation = unit[2],
            significandDivisor = unit[1] / 10, fractionDivisor = 10, abbreviationIsGlobal = false }
    end
    englishAbbreviation = { locale = "enUS", config = CreateAbbreviateConfig(points) }
end
function D.Abbreviate(value)
    return AbbreviateNumbers(value, M.config.englishNumbers and englishAbbreviation or nil)
end

function D.Clock(seconds)
    seconds = floor(seconds)
    if seconds >= 3600 then return format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60) end
    return format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- Blizzard ships localized meter strings with Blizzard_DamageMeter on every
-- client; S.BlizzardText falls back to the suite locale.

local typeGlobals = { "DAMAGE_METER_TYPE_DAMAGE_DONE", "DAMAGE_METER_TYPE_DPS", "DAMAGE_METER_TYPE_HEALING_DONE",
    "DAMAGE_METER_TYPE_HPS", "DAMAGE_METER_TYPE_ABSORBS", "DAMAGE_METER_TYPE_INTERRUPTS", "DAMAGE_METER_TYPE_DISPELS",
    "DAMAGE_METER_TYPE_DAMAGE_TAKEN", "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN", "DAMAGE_METER_TYPE_DEATHS",
    "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN" }
function D.TypeName(meterType)
    local labels = NS.DamageMeterTypeLabels
    return S.BlizzardText(typeGlobals[meterType + 1], labels and labels[meterType + 1] or "")
end

function D.Blocked() return S.Text("Details are available after combat.") end

function D.SessionTypes()
    local sessionTypes = Enum.DamageMeterSessionType
    D.OVERALL, D.CURRENT = sessionTypes.Overall, sessionTypes.Current
end

-- GetSessionDurationSeconds is not SecretWhenInCombat; the value is still checked.
function D.Duration(sessionType)
    local value = C_DamageMeter.GetSessionDurationSeconds(sessionType)
    if Finite(value) and value >= 0 then return value end
end

-- A new Current session can lag the combat edge by a moment; the local
-- combat clock caps a stale reading from the previous fight.
function D.LiveDuration()
    local value = D.Duration(D.CURRENT)
    if not M.inCombat or not M.combatStart then return value end
    local elapsed = GetTime() - M.combatStart
    if not value or value > elapsed + 2 then return elapsed end
    return value
end

function S.DamageMeterAvailability()
    local ok, reason = C_DamageMeter.IsDamageMeterAvailable()
    if Public(ok) and ok == false then
        if Public(reason) and type(reason) == "string" and reason ~= "" then return false, reason end
        return false, S.Text("Combat meter data is unavailable")
    end
    return true
end

-- One C API call per paint. Edit Mode shows sample rows while there is no
-- data; the options preview always shows them.
function D.FetchSession(win)
    if M.preview then return D.Sample(win.meterType) end
    if not M.available then return nil end
    local session
    if win.sessionID then
        session = C_DamageMeter.GetCombatSessionFromID(win.sessionID, win.meterType)
    else
        session = C_DamageMeter.GetCombatSessionFromType(win.sessionType, win.meterType)
    end
    if type(session) ~= "table" then session = nil end
    if M.forced and D.Count(session and session.combatSources) == 0 then return D.Sample(win.meterType) end
    return session
end

function D.FetchSource(win, guid, creature)
    if not (guid or creature) then return nil end
    local source
    if win.sessionID then
        source = C_DamageMeter.GetCombatSessionSourceFromID(win.sessionID, win.meterType, guid, creature)
    else
        source = C_DamageMeter.GetCombatSessionSourceFromType(win.sessionType, win.meterType, guid, creature)
    end
    return type(source) == "table" and source or nil
end

-- The source getters refuse secret arguments from addon code. Only plain
-- identities go back into the API; in combat that leaves the local player's
-- own row, mapped to UnitGUID("player"). nil,nil means "blocked".
function D.Identity(source)
    local guid, creature = source.sourceGUID, source.sourceCreatureID
    if not Public(guid) or type(guid) ~= "string" or guid == "" then guid = nil end
    if not Finite(creature) or creature <= 0 then creature = nil end
    if not guid and not creature then
        local isLocal = source.isLocalPlayer
        if Public(isLocal) and isLocal == true then
            local own = UnitGUID("player")
            if Public(own) and type(own) == "string" and own ~= "" then guid = own end
        end
    end
    return guid, creature
end

local samples = {}
local sampleClasses = { "WARRIOR", "MAGE", "PRIEST", "HUNTER", "ROGUE", "DRUID", "PALADIN" }
-- Static sample sessions for Edit Mode and the options preview (built once).
function D.Sample(meterType)
    local kind = D.countOnly[meterType] and "count" or "amount"
    local sample = samples[kind]
    if sample then return sample end
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    local list, total = {}, 0
    for i, class in ipairs(sampleClasses) do
        local amount = kind == "count" and 15 - 2 * i or floor(52e6 / (i + .35))
        local name = names[class] or class
        list[i] = {
            name = name,
            classFilename = class,
            specIconID = 0,
            totalAmount = amount,
            amountPerSecond = amount / 95,
            isLocalPlayer = i == 3,
            deathRecapID = 0,
            deathTimeSeconds = 17 * i
        }
        total = total + amount
    end
    sample = { combatSources = list, maxAmount = list[1].totalAmount, totalAmount = total, durationSeconds = 95, isSample = true }
    samples[kind] = sample
    return sample
end

-- Identity test: never probe fields that C-returned sessions do not define.
function D.IsSample(session)
    return session ~= nil and (session == samples.count or session == samples.amount)
end

local groupIndex, groups = {}, {}
local function ByAmount(a, b) return a.amount > b.amount end
-- EnemyDamageTaken: one enemy's spells regrouped by the attacking unit. Plain
-- data only (scratch tables are reused); any secret field returns nil and the
-- caller falls back to the spell list rendered through sinks.
function D.GroupSpells(source)
    local spells = source and source.combatSpells
    local count = D.Count(spells)
    if count == 0 then return nil end
    for key in pairs(groupIndex) do groupIndex[key] = nil end
    local n, sum = 0, 0
    for i = 1, count do
        local spell = spells[i]
        local details = spell.combatSpellDetails
        local name, amount = details and details.unitName, spell.totalAmount
        if not Public(name) or type(name) ~= "string" or name == "" or not Finite(amount) then return nil end
        local entry = groupIndex[name]
        if not entry then
            n = n + 1
            entry = groups[n] or {}
            groups[n], groupIndex[name] = entry, entry
            local class, spec = details.unitClassFilename, details.specIconID
            entry.name, entry.amount = name, 0
            entry.class = Public(class) and type(class) == "string" and class or ""
            entry.spec = Finite(spec) and spec or 0
        end
        entry.amount = entry.amount + amount
        sum = sum + amount
    end
    for i = #groups, n + 1, -1 do groups[i] = nil end
    table.sort(groups, ByAmount)
    return groups, n, sum
end

-- The DamageDone source exposes spells, not a per-target total. The inverse
-- EnemyDamageTaken session exposes each enemy's attackers. Build the target
-- totals once, on the first out-of-combat hover, and reuse them until the
-- meter reports new data. Secret or ambiguous identities fail closed.
local function TargetIndex(session)
    if not Public(session) then return nil end
    local sources = session and session.combatSources
    if type(sources) ~= "table" or not Public(sources) then return nil end
    local count = #sources
    if not Public(count) then return nil end
    local full, short = {}, {}
    for index = 1, count do
        local source = sources[index]
        if type(source) ~= "table" or not Public(source) then return nil end
        local name, class = source.name, source.classFilename
        if not Public(name) or type(name) ~= "string" or not Public(class) or type(class) ~= "string" then
            return nil
        end
        local player = { name = name, class = class }
        if full[name] ~= nil then full[name] = false else full[name] = player end
        local abbreviated = Ambiguate(name, "short")
        if not Public(abbreviated) or type(abbreviated) ~= "string" then return nil end
        if short[abbreviated] ~= nil then short[abbreviated] = false else short[abbreviated] = player end
    end
    return full, short
end

local function TargetPlayer(full, short, name, class)
    local player = full[name]
    -- A complete realm-qualified name remains usable when its short form is
    -- ambiguous; only short-name lookups must fail closed in that case.
    if not player then player = short[name] end
    if not player then
        local abbreviated = Ambiguate(name, "short")
        if not Public(abbreviated) or type(abbreviated) ~= "string" then return nil end
        player = short[abbreviated]
    end
    if not player or player == false or (class ~= "" and player.class ~= "" and player.class ~= class) then return nil end
    return player.name
end

local function EnemySession(win)
    local session
    if win.sessionID then
        session = C_DamageMeter.GetCombatSessionFromID(win.sessionID, TYPE.EnemyDamageTaken)
    else
        session = C_DamageMeter.GetCombatSessionFromType(win.sessionType, TYPE.EnemyDamageTaken)
    end
    return type(session) == "table" and Public(session) and session or nil
end

local function EnemySource(win, guid, creature)
    local function Fetch(sourceGUID, sourceCreatureID)
        if win.sessionID then
            return C_DamageMeter.GetCombatSessionSourceFromID(win.sessionID, TYPE.EnemyDamageTaken, sourceGUID,
                sourceCreatureID)
        end
        return C_DamageMeter.GetCombatSessionSourceFromType(win.sessionType, TYPE.EnemyDamageTaken, sourceGUID,
            sourceCreatureID)
    end
    -- The enemy view is keyed by creature ID on some clients. Prefer that
    -- lookup, then fall back to the exact identity used by Blizzard's UI.
    if creature then
        local detail = Fetch(nil, creature)
        if type(detail) == "table" and D.Count(detail.combatSpells) > 0 then return detail end
    end
    local detail = Fetch(guid, creature)
    if type(detail) == "table" and D.Count(detail.combatSpells) > 0 then return detail end
    if guid and creature then return Fetch(guid, nil) end
    return detail
end

local function BuildTargets(win)
    local full, short = TargetIndex(win.session)
    if not full then return nil end
    local enemies = EnemySession(win)
    local sources = enemies and enemies.combatSources
    if type(sources) ~= "table" or not Public(sources) then return nil end
    local count = #sources
    if not Public(count) then return nil end
    local players = {}
    for index = 1, count do
        local enemy = sources[index]
        if type(enemy) ~= "table" or not Public(enemy) then return nil end
        local target = enemy.name
        if not Public(target) or type(target) ~= "string" or target == "" then return nil end
        local guid, creature = D.Identity(enemy)
        if not guid and not creature then return nil end
        local detail = EnemySource(win, guid, creature)
        if type(detail) ~= "table" or not Public(detail) then return nil end
        local spells = detail.combatSpells
        if type(spells) ~= "table" or not Public(spells) then return nil end
        local spellCount = #spells
        if not Public(spellCount) then return nil end
        for spellIndex = 1, spellCount do
            local spell = spells[spellIndex]
            if type(spell) ~= "table" or not Public(spell) then return nil end
            local data = spell.combatSpellDetails
            if type(data) ~= "table" or not Public(data) then return nil end
            local attacker, class = data.unitName, data.unitClassFilename
            if not Public(attacker) or type(attacker) ~= "string"
                or not Public(class) or type(class) ~= "string" then return nil end
            if attacker ~= "" then
                local playerName = TargetPlayer(full, short, attacker, class)
                if playerName then
                    -- The enemy entry's spell total is the amount represented
                    -- by this attacker row in the native meter.
                    local amount = spell.totalAmount
                    if not Public(amount) or not Finite(amount) then return nil end
                    if amount > 0 then
                        local player = players[playerName]
                        if not player then
                            player = { list = {}, index = {}, sum = 0 }
                            players[playerName] = player
                        end
                        local entry = player.index[target]
                        if not entry then
                            entry = { name = target, amount = 0, class = "", spec = 0 }
                            player.index[target] = entry
                            player.list[#player.list + 1] = entry
                        end
                        entry.amount = entry.amount + amount
                        player.sum = player.sum + amount
                    end
                end
            end
        end
    end
    for _, player in pairs(players) do
        table.sort(player.list, ByAmount)
        player.index = nil
    end
    return players
end

-- HealingDone/Hps source spells can contain one recipient in their unit
-- details. Aggregate those public values only when the tooltip is opened.
-- A secret field cannot be used as a table key or summed by addon Lua.
local function HealingTargets(detail)
    local spells = detail and detail.combatSpells
    if type(spells) ~= "table" or not Public(spells) then return nil end
    local count = #spells
    if not Public(count) then return nil end
    local index, list, sum = {}, {}, 0
    for i = 1, count do
        local spell = spells[i]
        if type(spell) ~= "table" or not Public(spell) then return nil end
        local data = spell.combatSpellDetails
        if not Public(data) then return nil end
        if type(data) == "table" then
            local name, amount = data.unitName, data.amount
            if not Public(name) or not Public(amount) then return nil end
            if type(name) == "string" and name ~= "" and Finite(amount) and amount > 0 then
                local entry = index[name]
                if not entry then
                    local class, spec = data.unitClassFilename, data.specIconID
                    entry = { name = name, amount = 0,
                        class = Public(class) and type(class) == "string" and class or "",
                        spec = Finite(spec) and spec or 0 }
                    index[name] = entry
                    list[#list + 1] = entry
                end
                entry.amount = entry.amount + amount
                sum = sum + amount
            end
        end
    end
    if #list == 0 then return nil end
    table.sort(list, ByAmount)
    return list, #list, sum
end

function D.InvalidateTargets()
    M.targetRevision = (M.targetRevision or 0) + 1
end

function D.TargetGroups(win, source, detail)
    if M.inCombat or NS.IsCombatLocked() or M.preview then return nil end
    if D.healingTypes[win.meterType] then return HealingTargets(detail) end
    if not D.damageTypes[win.meterType] then return nil end
    if not source then return nil end
    local name = source.name
    if not Public(name) or type(name) ~= "string" then return nil end
    local cache = win.targetCache
    if not cache or cache.revision ~= M.targetRevision or cache.sessionID ~= win.sessionID
        or cache.sessionType ~= win.sessionType then
        cache = { revision = M.targetRevision, sessionID = win.sessionID, sessionType = win.sessionType }
        win.targetCache = cache
    end
    -- The inverse view can arrive shortly after the damage view at a combat
    -- edge. A failed read gets a short cooldown instead of being cached for
    -- the rest of the fight/session.
    local now = GetTime()
    if not cache.players and (not cache.retryAt or now >= cache.retryAt) then
        local players = BuildTargets(win)
        if players and next(players) then
            cache.players, cache.retryAt = players, nil
        else
            cache.retryAt = now + 1
        end
    end
    local player = cache.players and cache.players[name]
    if not player then return nil end
    return player.list, #player.list, player.sum
end

-- Public snapshot for challenge lifecycle consumers. This never resets or
-- relabels a native session. The consumer owns start/end boundaries and must
-- invalidate a baseline on DAMAGE_METER_RESET.
local SNAPSHOT_TYPES = { damage = TYPE.DamageDone, damageTaken = TYPE.DamageTaken,
    interrupts = TYPE.Interrupts, deaths = TYPE.Deaths }
function S.ReadDamageMeterTotals()
    if NS.IsCombatLocked() then return nil end
    local available = C_DamageMeter.IsDamageMeterAvailable()
    if not Public(available) or not available then return nil end
    local result = {}
    for key, meterType in pairs(SNAPSHOT_TYPES) do
        local session = C_DamageMeter.GetCombatSessionFromType(D.OVERALL, meterType)
        if not Public(session) or type(session) ~= "table" then return nil end
        local sources = session.combatSources
        if not Public(sources) or type(sources) ~= "table" then return nil end
        local count = #sources
        if not Public(count) then return nil end
        local values = {}
        for i = 1, count do
            local source = sources[i]
            if not Public(source) or type(source) ~= "table" then return nil end
            local guid, amount = source.sourceGUID, source.totalAmount
            if not Public(guid) or not Finite(amount) or amount < 0 then return nil end
            if type(guid) == "string" and guid ~= "" then values[guid] = (values[guid] or 0) + amount end
        end
        result[key] = values
    end
    return result
end
