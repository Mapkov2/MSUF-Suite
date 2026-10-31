-- DataTexts: the per-bar reset, the settings of the built-in places, the
-- Friends, Guild, Secondary stat and Mythic+ rating places, and the
-- reputation progress they and the experience bar share.
-- The experience bar's Track choice: suite_dt_progress_xpbar_contract.lua.
local root = assert(arg[1], "repository root required")
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
-- What a DataText shows without a value: U+2014 EM DASH as UTF-8 bytes.
local DASH = "\226\128\148"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

------------------------------------------------------------------ the catalog
local defaults, NS = Support.CatalogDefaults(root, "dataTexts")
local spec = NS.SuiteCatalog.dataTexts
local function Config(overrides)
    local config = {}
    for key, value in pairs(defaults) do config[key] = value end
    for key, value in pairs(overrides or {}) do config[key] = value end
    return config
end
-- Competing information bars disable the module the way other modules' conflicts do.
local conflicts = {}
for _, name in ipairs(spec.conflicts) do conflicts[name] = true end
assert(conflicts.Titan and conflicts.ChocolateBar and conflicts.Bazooka, "the information bar addons are no conflict")
-- Defaults keep what the places always showed.
eq(defaults.clockSource, NS.DataTextClockSource.REALM, "default clock")
eq(defaults.clock24Hour, true, "24-hour default")
eq(defaults.clockSeconds, false, "seconds default")
eq(defaults.durabilityWarning, 20, "durability limit")
eq(defaults.fpsWarning, 30, "FPS limit")
eq(defaults.latencyWarning, 200, "latency limit")
eq(defaults.coordinateDecimals, 1, "coordinate decimals")
-- New sources are appended: saved places keep their numbers.
eq(NS.DataTextSourceIndex.vault, 28, "an existing source moved")
eq(NS.DataTextSourceIndex.supplies, 29, "an existing source moved")
local appended = { friends = 1, guild = 2, secondaryStat = 3, mythicRating = 4 }
for key, offset in pairs(appended) do
    appended[key] = NS.DataTextSourceIndex.supplies + offset
    eq(NS.DataTextSourceIndex[key], appended[key], key .. " position")
end
NS.Client.isForever = false
assert(NS.DataTextSourceAvailable("mythicRating"), "Mythic+ rating is Retail's")
NS.Client.isForever = true
assert(not NS.DataTextSourceAvailable("mythicRating"), "Forever has no Mythic+ rating")
assert(NS.DataTextSourceAvailable("friends") and NS.DataTextSourceAvailable("guild"), "social places are on both clients")
NS.Client.isForever = false
-- The stat choice belongs to every place, also the extra ones, and applies to the Secondary stat only.
for _, key in ipairs({ "bar1Slot1Stat", "bar1Slot6Stat", "bar12Slot12Stat" }) do
    local rule = assert(spec.rules[key], key .. " is no setting")
    eq(rule.default, NS.DataTextStat.CRIT, key .. " default")
    eq(rule.requiresChoice.key, key:gsub("Stat$", ""), key .. " depends on its place")
    assert(rule.requiresChoice.values[appended.secondaryStat], key .. " is not for the Secondary stat")
end

------------------------------------------------------------------ the per-bar reset
-- A bar's reset writes the bar's defaults but leaves Show bar alone: the
-- default of Show bar is off for every bar but the first, so resetting bar 2
-- used to hide it.
do
    local written
    local P = { Suite = NS, S = { Config = function() return Config({ bar2Enabled = true, bar2Width = 600 }) end },
        Tr = function(text) return text end, Help = function() end, M = {}, W = {}, HM = {}, DataTextPage = {},
        ResetRules = function(id, rules, keyFn)
            assert(id == "dataTexts")
            written = {}
            for _, rule in ipairs(rules) do
                local key = keyFn and keyFn(rule.key) or not keyFn and rule.key
                if key then written[key] = rule.default end
            end
            return true
        end }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/DataTextsEditor.lua"))("MSUF_Suite_Options", P)
    assert(P.DataTextEditor.ResetBar(2))
    eq(written.bar2Enabled, nil, "a bar reset must keep Show bar")
    eq(written.bar2Width, 390, "the bar's other settings reset")
    eq(written.bar2Slot1Stat, 1, "the place settings reset")
    eq(written.bar3Width, nil, "another bar was reset")
    -- The old route reset Show bar to its default, which hides every bar but the first.
    eq(spec.rules.bar2Enabled.default, false, "bar 2 default")
end

------------------------------------------------------------------ built-in places
local settings = Config()
local readings = {}
local localTime = { H = 9, M = 5, S = 7 }
TIME_TWELVEHOURAM, TIME_TWELVEHOURPM = "%d:%02d AM", "%d:%02d PM"
date = function(format) return string.format("%02d", localTime[format:sub(2)]) end
local S = { Text = function(v) return v end, Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v end, MoneyText = tostring,
    PublicText = function(v) return type(v) == "string" and v ~= "secret" and v or nil end,
    ClassHex = function(class) return class == "MAGE" and "3fc7eb" or nil end, RGB = function() return 1, 1, 1 end,
    Config = function() return settings end, GamepadUI = function() return false end,
    ReadInfoSource = function(key) return unpack(readings[key] or {}) end }
NS.Suite = S
NS.IsCombatLocked = function() return false end
local inCombat = false
NS.InCombat = function() return inCombat end
NS.Finish = function(callback, ...) return true, callback(...) end
S.Dispatch = function(callback, ...) return callback(...) end
local function Load(file, package)
    MSUFSuite = NS
    assert(loadfile(root .. "/MSUF_Suite_DataTexts/" .. file .. ".lua"))("MSUF_Suite_DataTexts", package)
end
assert(loadfile(root .. "/MSUF_Suite_Modules/PlayerReaders.lua"))("MSUF_Suite_Modules", { Suite = S })
local P = {}
Load("Bootstrap", P)
Load("Standard", P)
local Standard = P.DataTextStandard
local function Show(key, overrides)
    settings = Config(overrides)
    Standard.Configure(settings)
    local _, value, severity = Standard.Format(key)
    return value, severity
end
readings.clockTime, readings.clockStamp = { 14, 3 }, { 1700000017 }
readings.fps, readings.latency, readings.durability = { 29.6 }, { 30, 200 }, { .2, 20, 100 }
readings.coordinates = { .482, .617 }
-- The defaults are today's output.
eq(Show("clock"), "14:03", "default clock")
local value, severity = Show("fps")
eq(value .. "/" .. tostring(severity), "30/bad", "FPS below 30 warns")
readings.fps = { 30 }
eq(select(2, Show("fps")), nil, "30 FPS does not warn")
value, severity = Show("latency")
eq(value .. "/" .. tostring(severity), "200 ms/bad", "200 ms warns")
readings.latency = { 30, 199 }
eq(select(2, Show("latency")), nil, "199 ms does not warn")
value, severity = Show("durability")
eq(value .. "/" .. tostring(severity), "20%/bad", "20 percent durability warns")
readings.durability = { .21, 20, 100 }
eq(select(2, Show("durability")), nil, "21 percent durability does not warn")
eq(Show("coordinates"), "48.2, 61.7", "default coordinates")
readings.fps, readings.latency = { 29 }, { 30, 100 }
eq(select(2, Show("fpsLatency")), "bad", "FPS / latency warns on the FPS")
readings.fps, readings.latency = { 60 }, { 30, 200 }
eq(select(2, Show("fpsLatency")), "bad", "FPS / latency warns on the latency")
readings.latency = { 30, 199 }
eq(select(2, Show("fpsLatency")), nil, "FPS / latency in range")
-- The settings change them.
readings.fps, readings.latency, readings.durability = { 45 }, { 30, 100 }, { .5, 20, 100 }
eq(select(2, Show("fps", { fpsWarning = 60 })), "bad", "FPS limit")
eq(select(2, Show("latency", { latencyWarning = 100 })), "bad", "latency limit")
eq(select(2, Show("durability", { durabilityWarning = 50 })), "bad", "durability limit")
eq(select(2, Show("durability", { durabilityWarning = 49 })), nil, "durability limit, just above")
eq(Show("coordinates", { coordinateDecimals = 0 }), "48, 62", "coordinates without decimals")
eq(Show("coordinates", { coordinateDecimals = 3 }), "48.200, 61.700", "coordinates with three decimals")
local LOCAL, REALM = NS.DataTextClockSource.LOCAL, NS.DataTextClockSource.REALM
eq(Show("clock", { clockSource = LOCAL }), "09:05", "the computer's clock")
eq(Show("clock", { clockSource = LOCAL, clockSeconds = true }), "09:05:07", "the computer's clock with seconds")
eq(Show("clock", { clockSeconds = true }), "14:03:37", "the realm clock with seconds")
eq(Show("clock", { clock24Hour = false }), "2:03 PM", "the realm clock in 12 hours")
eq(Show("clock", { clock24Hour = false, clockSeconds = true }), "2:03:37 PM", "12 hours with seconds")
eq(Show("clock", { clockSource = LOCAL, clock24Hour = false }), "9:05 AM", "the computer's clock in 12 hours")
localTime.H = 0
eq(Show("clock", { clockSource = LOCAL, clock24Hour = false }), "12:05 AM", "midnight in 12 hours")
readings.clockTime = { "secret", 3 }
eq(Show("clock", { clockSource = REALM }), DASH, "a withheld game time shows the placeholder")
readings.clockTime = { 14, 3 }

------------------------------------------------------------------ the reputation resolver
MAX_REPUTATION_REACTION = 8
local standings = { FACTION_STANDING_LABEL4 = "Friendly", FACTION_STANDING_LABEL8 = "Exalted" }
GetText = function(token) return standings[token] end
UnitSex = function() return 2 end
RENOWN_LEVEL_LABEL, HONOR_LEVEL_LABEL = "Renown %d", "Honor Level %d"
local watched, paragon, major, friendship, renown, maxRenown
C_Reputation = {
    GetWatchedFactionData = function() return watched end,
    IsFactionParagonForCurrentPlayer = function() return paragon ~= nil end,
    GetFactionParagonInfo = function() if paragon then return paragon.value, paragon.threshold, 0, paragon.pending end end,
    IsMajorFaction = function() return major == true end,
}
C_MajorFactions = {
    GetMajorFactionData = function() return renown end,
    HasMaximumRenown = function() return maxRenown == true end,
}
C_GossipInfo = { GetFriendshipReputation = function() return friendship or { friendshipFactionID = 0 } end }
local function Reset(data)
    watched = data
    paragon, major, friendship, renown, maxRenown = nil, nil, nil, nil, nil
end
local function Progress()
    local info = S.ReputationProgress()
    if not info then return "none" end
    return string.format("%s|%s|%s|%s|%s|%s", info.name, info.label, info.current, info.maximum, info.kind,
        tostring(info.capped))
end
Reset(nil)
eq(Progress(), "none", "no watched faction")
Reset({ factionID = 0, name = "" })
eq(Progress(), "none", "the empty watched faction")
Reset({ factionID = 7, name = "Faction", reaction = 4, currentStanding = 50, currentReactionThreshold = 0,
    nextReactionThreshold = 200 })
eq(Progress(), "Faction|Friendly|50|200|standing|false", "a plain standing")
watched.currentStanding, watched.currentReactionThreshold, watched.nextReactionThreshold = 3150, 3000, 6000
eq(Progress(), "Faction|Friendly|150|3000|standing|false", "a standing inside its step")
watched.reaction, watched.currentStanding, watched.currentReactionThreshold, watched.nextReactionThreshold = 8, 42000, 42000, 42000
eq(Progress(), "Faction|Exalted|1|1|standing|true", "maximum standing is capped, with a name")
paragon = { value = 12500, threshold = 10000, pending = false }
eq(Progress(), "Faction|Paragon|2500|10000|paragon|false", "paragon progress inside its cycle")
paragon.pending = true
eq(Progress(), "Faction|Paragon|10000|10000|paragon|false", "a waiting paragon reward fills the bar, never beyond it")
paragon = nil
major, renown = true, { renownLevel = 12, renownReputationEarned = 1200, renownLevelThreshold = 2500 }
eq(Progress(), "Faction|Renown 12|1200|2500|renown|false", "renown inside its level")
maxRenown = true
eq(Progress(), "Faction|Renown 12|1|1|renown|true", "maximum renown is capped")
major, maxRenown = nil, nil
friendship = { friendshipFactionID = 55, reaction = "Good Friend", standing = 8500, reactionThreshold = 8400,
    nextThreshold = 16800 }
eq(Progress(), "Faction|Good Friend|100|8400|friendship|false", "friendship inside its rank")
friendship.nextThreshold = nil
eq(Progress(), "Faction|Good Friend|1|1|friendship|true", "the best friendship rank is capped")
watched.name = "secret"
eq(Progress(), "none", "a withheld faction name shows nothing")

------------------------------------------------------------------ the sources
local lib = {}
LibStub = nil
C_CVar = { GetCVar = function() return "1" end }
GetMaxPlayerLevel = function() return 80 end
local level = 80
UnitLevel = function() return level end
UnitXP = function() return 50 end
UnitXPMax = function() return 100 end
local calls = setmetatable({}, { __index = function() return 0 end })
local function Counted(name, fn) return function(...) calls[name] = calls[name] + 1; return fn(...) end end
-- Friends: 3 character friends and 4 Battle.net friends online.
local friendRows, bnetRows = {}, {}
for i = 1, 30 do
    friendRows[i] = { connected = i <= 25, name = "Friend" .. i, level = 70, area = "Zone", guid = "G" .. i }
    bnetRows[i] = { accountName = "Account" .. i, battleTag = "Tag" .. i, gameAccountInfo = { isOnline = i <= 25,
        clientProgram = i % 2 == 0 and "WoW" or "App", characterName = "Char" .. i, classFilename = "MAGE",
        characterLevel = 80, areaName = "Place" } }
end
BNET_CLIENT_WOW = "WoW"
local onlineWow, onlineBnet = 3, 4
BNGetNumFriends = Counted("bnCount", function() return 30, onlineBnet end)
C_FriendList = {
    IsLegacyFriendSystemEnabled = function() return true end,
    GetNumOnlineFriends = function() return onlineWow end,
    GetNumFriends = Counted("friendTotal", function() return 30 end),
    GetFriendInfoByIndex = Counted("friendRow", function(index) return friendRows[index] end),
}
C_BattleNet = { GetFriendAccountInfo = Counted("bnetRow", function(index) return bnetRows[index] end) }
-- Guild.
local inGuild, roster = true, { total = 0, online = 0 }
local guildMembers = {}
for i = 1, 60 do
    guildMembers[i] = { "Member" .. i, "Rank", 1, 80, "Mage", "Zone", "", "", i <= 40, 0, "MAGE" }
end
IsInGuild = function() return inGuild end
GetNumGuildMembers = function() return roster.total, roster.online, roster.online end
GetGuildRosterInfo = Counted("guildRow", function(index) return unpack(guildMembers[index]) end)
local now = 1000
GetTime = function() return now end
C_GuildInfo = { GuildRoster = Counted("rosterRequest", function() end) }
-- Secondary stats and Mythic+.
GetCritChance, GetRangedCritChance, GetSpellCritChance = function() return 10 end, function() return 9 end,
    function() return 11 end
GetHaste, GetMasteryEffect, GetLifesteal = function() return 21.34 end, function() return 34.2 end,
    function() return "secret" end
CR_VERSATILITY_DAMAGE_DONE = 29
GetCombatRatingBonus, GetVersatilityBonus = function() return 5 end, function() return 1.5 end
local score = 2851.4
C_ChallengeMode = { GetOverallDungeonScore = function() return score end,
    GetMapUIInfo = function(id) return "Dungeon" .. id end }
C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = Counted("ratingSummary", function()
    return { currentSeasonScore = score, runs = { { challengeModeID = 1, mapScore = 300.2, bestRunLevel = 12 },
        { challengeModeID = 2, mapScore = 0, bestRunLevel = 0 } } }
end) }

local panelClicks = {}
S.PanelButton = function() return nil end
S.TogglePanel = function(panel) panelClicks[#panelClicks + 1] = panel end
local config = Config({ bar1Slot3Stat = 3, bar1Slot5Stat = 5, bar1Slot6Stat = 99 })
settings = config
S.Config = function() return config end
local registered, jobs = {}, {}
local M = { active = true, activeSources = {}, config = config, updates = {}, values = {}, due = {}, bars = {} }
function M:UpdateSource(key) self.updates[#self.updates + 1] = key end
M.context = {
    Event = function(_, event) registered[event] = true end,
    RemoveEvent = function(_, event) registered[event] = nil end,
    -- A job of the context: Request() runs the function on the next Run().
    Coalesce = function(_, delay, fn)
        local job = jobs[fn]
        if not job then
            job = { delay = delay, fn = fn }
            function job:Request() self.requested = (self.requested or 0) + 1 end
            jobs[fn] = job
        end
        return job
    end,
}
local function Run()
    for _, job in pairs(jobs) do
        if job.requested then job.requested = nil; job.fn(M) end
    end
end
Load("Sources", P)
Load("Social", P)
Load("Stats", P)
Load("Actions", P)
local X, A = P.DataTextSources, P.DataTextActions
local function Button()
    return { written = {}, SetAttribute = function() end }
end
local function Bind(kind, bar, slot)
    local button = Button()
    local key = X.Bind(button, config, bar, slot, kind)
    M.activeSources[key] = true
    return key, button
end
X.Rebind(M)
local friends, friendsButton = Bind("friends", 1, 1)
local guild, guildButton = Bind("guild", 1, 2)
local stat1, stat1Button = Bind("secondaryStat", 1, 3)
local rating, ratingButton = Bind("mythicRating", 1, 4)
for _, kind in ipairs({ "friends", "guild", "secondaryStat", "mythicRating" }) do
    assert(X.kinds[kind], kind .. " is no source kind")
end
local function Value(key) local _, value = X.Format(key); return value end

-- Friends: counts of who is online; nothing is listed until the pointer rests on the place.
eq(Value(friends), "7", "online character and Battle.net friends")
onlineWow = 0
eq(Value(friends), "4", "only Battle.net friends")
C_FriendList.IsLegacyFriendSystemEnabled = function() return false end
onlineWow = 5
eq(Value(friends), "4", "without the legacy friend system only Battle.net friends count")
C_FriendList.IsLegacyFriendSystemEnabled = function() return true end
onlineWow = 3
eq(calls.friendRow + calls.bnetRow + calls.friendTotal, 0, "the count read friend rows")
local wanted = {}
X.WantedEvents(M.activeSources, wanted)
assert(wanted.FRIENDLIST_UPDATE and wanted.BN_FRIEND_INFO_CHANGED, "friends need their two events")
assert(wanted.GUILD_ROSTER_UPDATE and wanted.COMBAT_RATING_UPDATE and wanted.MASTERY_UPDATE and wanted.UNIT_STATS,
    "guild and stat events")
assert(wanted.CHALLENGE_MODE_COMPLETED, "the rating event")
assert(wanted.PLAYER_REGEN_DISABLED, "social places release their secure overlay in combat")
-- A burst of events refreshes the place once, after the context's wait.
M.updates = {}
for _ = 1, 40 do X.Changed(M, "BN_FRIEND_INFO_CHANGED") end
eq(#M.updates, 0, "an event refreshed at once")
Run()
eq(#M.updates, 1, "a burst of events folds into one refresh")
eq(M.updates[1], friends, "the burst refreshed another place")
local function Tooltip(button, title)
    GameTooltip.lines = {}
    A.Tooltip(button, title)
    return GameTooltip.lines
end
GameTooltip = { lines = {} }
function GameTooltip:SetOwner() end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
function GameTooltip:Show() end
-- Out of combat: both counts, then the capped list (character friends first, then Battle.net friends in WoW).
inCombat = true
local lines = Tooltip(friendsButton, "Friends online")
eq(#lines, 2, "the title and the place's value only in combat")
eq(calls.friendRow + calls.bnetRow + calls.friendTotal, 0, "combat built the friend list")
inCombat = false
friendsButton.text = "Friends: 29"
onlineWow = 25
lines = Tooltip(friendsButton, "Friends online")
eq(lines[3], "WoW friends online | 25", "character friend count")
eq(lines[4], "Battle.net friends online | 4", "Battle.net friend count")
eq(#lines, 4 + 20 + 1, "the list is capped at twenty rows and says so")
assert(lines[5]:find("Friend1 |", 1, true) and lines[24]:find("Friend20 |", 1, true), "character friends come first")
eq(lines[#lines], "Open the window to see everyone.", "a capped list says so")
eq(calls.bnetRow, 0, "character friends fill the list before Battle.net friends are read")
-- Battle.net friends in WoW list their character, class colored, with the account.
onlineWow = 1
for i = 1, 25 do friendRows[i].connected = false end
friendRows[1].connected = true
lines = Tooltip(friendsButton, "Friends online")
assert(lines[5] == "Friend1 | Level 70, Zone", "one character friend row: " .. tostring(lines[5]))
assert(lines[6]:find("|cff3fc7ebChar2|r (Account2) | Level 80, Place", 1, true), "Battle.net row: " .. tostring(lines[6]))
-- A click opens the Friends panel through the secure panel button, or Blizzard's panel manager.
friendsButton.source = friends
NS.IsCombatLocked = function() return true end
A.Click(friendsButton, "LeftButton")
eq(#panelClicks, 0, "a click in combat opened a window")
NS.IsCombatLocked = function() return false end
A.Click(friendsButton, "LeftButton")
eq(panelClicks[#panelClicks], "friends", "the friends place opens the friends panel")
A.Click(guildButton, "LeftButton")
eq(panelClicks[#panelClicks], "guild", "the guild place opens the guild panel")
assert(X.secureKinds.friends and X.secureKinds.guild, "the social places borrow the secure overlay")

-- Guild: online members; the roster is requested on hover only, throttled.
eq(Value(guild), DASH, "no roster yet")
eq(calls.rosterRequest, 0, "nothing requested before the place is bound")
X.Rebind(M)
eq(calls.rosterRequest, 1, "an empty roster is requested once the place shows")
X.Rebind(M)
eq(calls.rosterRequest, 1, "the request is throttled")
roster.total, roster.online = 60, 40
eq(Value(guild), "40", "online guild members")
inGuild = false
eq(Value(guild), DASH, "outside a guild")
inGuild = true
inCombat = true
Tooltip(guildButton, "Guild online")
eq(calls.rosterRequest + calls.guildRow, 1, "combat requested the roster or built the list")
inCombat = false
now = now + 5
lines = Tooltip(guildButton, "Guild online")
eq(calls.rosterRequest, 1, "a hover within the interval requested again")
eq(lines[3], "Members online | 40", "guild header")
eq(#lines - 3, 21, "twenty members and the capped-list note")
assert(lines[4]:find("|cff3fc7ebMember1|r | Level 80, Zone", 1, true), "guild row: " .. tostring(lines[4]))
now = now + 20
Tooltip(guildButton, "Guild online")
eq(calls.rosterRequest, 2, "a later hover requests the roster again")

-- Secondary stat: one place, one stat.
eq(select(2, X.Format(stat1)), "34.2%", "mastery place")
local label = X.Format(stat1)
eq(label, "Mastery", "stat name")
local leech = Bind("secondaryStat", 1, 5)
eq(select(2, X.Format(leech)), DASH, "a withheld stat shows the placeholder")
local versatility = Bind("secondaryStat", 1, 6)
config.bar1Slot6Stat = 4
X.Bind(Button(), config, 1, 6, "secondaryStat")
eq(select(2, X.Format(versatility)), "6.5%", "versatility adds rating and effects")
config.bar1Slot3Stat = 1
X.Bind(Button(), config, 1, 3, "secondaryStat")
eq(select(2, X.Format(stat1)), "11.0%", "crit takes the highest of melee, ranged and the lowest spell school")
config.bar1Slot3Stat = 2
X.Bind(Button(), config, 1, 3, "secondaryStat")
eq(select(2, X.Format(stat1)), "21.3%", "haste")
inCombat = true
local statCalls = calls.ratingSummary
lines = Tooltip(stat1Button, "Secondary stat")
eq(#lines, 2, "combat listed the stats")
inCombat = false
stat1Button.text = "Haste: 21.3%"
lines = Tooltip(stat1Button, "Secondary stat")
eq(lines[3], "Critical strike | 11.0%", "stat tooltip lists every stat")
eq(#lines, 7, "five stats")

-- Mythic+ rating: Retail's current season score.
eq(Value(rating), "2851", "the season score")
lines = Tooltip(ratingButton, "Mythic+ rating")
eq(lines[3], "+12 Dungeon1 | 300", "a dungeon with its best key")
eq(lines[4], "Dungeon2 | 0", "a dungeon never run")
inCombat = true
Tooltip(ratingButton, "Mythic+ rating")
eq(calls.ratingSummary, 1, "combat read the rating summary")
inCombat = false
score = "secret"
eq(Value(rating), DASH, "a withheld score shows the placeholder")

-- Forever has no Mythic+: the place shows the placeholder and subscribes to nothing.
do
    NS.Client.isForever = true
    local forever = {}
    Load("Bootstrap", forever)
    Load("Sources", forever)
    Load("Social", forever)
    Load("Stats", forever)
    local Y = forever.DataTextSources
    local key = Y.Bind(Button(), config, 2, 1, "mythicRating")
    Y.Rebind({ active = true, activeSources = { [key] = true }, config = config, context = M.context })
    score = 2851
    eq(select(2, Y.Format(key)), DASH, "Forever shows no Mythic+ rating")
    local events = {}
    Y.WantedEvents({ [key] = true }, events)
    eq(events.CHALLENGE_MODE_COMPLETED, nil, "Forever subscribed to a Mythic+ event")
    NS.Client.isForever = false
end

------------------------------------------------------------------ reputation in the XP / reputation place
local progress = X.Bind(Button(), config, 3, 1, "progress")
M.activeSources[progress] = true
watched = { factionID = 7, name = "Faction", reaction = 4, currentStanding = 50, currentReactionThreshold = 0,
    nextReactionThreshold = 200 }
paragon, major, friendship = nil, nil, nil
local function Text(key) local name, shown = X.Format(key); return name .. "|" .. shown end
eq(Text(progress), "Faction|25%", "a plain standing shows its percentage, as it always did")
watched.reaction, watched.currentStanding, watched.currentReactionThreshold, watched.nextReactionThreshold = 8, 42000, 42000, 42000
eq(Text(progress), "Faction|Exalted", "maximum standing shows its name and standing")
paragon = { value = 12500, threshold = 10000, pending = false }
eq(Text(progress), "Faction|Paragon · 25%", "paragon progress")
paragon.pending = true
eq(Text(progress), "Faction|Paragon · 100%", "a waiting paragon reward reads as a full bar, not 125%")
paragon = nil
major, renown = true, { renownLevel = 12, renownReputationEarned = 1250, renownLevelThreshold = 2500 }
eq(Text(progress), "Faction|Renown 12 · 50%", "renown progress")
maxRenown = true
eq(Text(progress), "Faction|Renown 12", "maximum renown")
major, maxRenown = nil, nil
friendship = { friendshipFactionID = 55, reaction = "Good Friend", standing = 8500, reactionThreshold = 8400,
    nextThreshold = 16800 }
eq(Text(progress), "Faction|Good Friend · 1%", "friendship progress")
friendship = nil
watched = nil
eq(Text(progress), "Reputation|" .. DASH, "no watched faction")
level = 20
eq(Text(progress), "XP|50%", "leveling shows experience")
local progressWanted = {}
X.WantedEvents({ [progress] = true }, progressWanted)
assert(progressWanted.MAJOR_FACTION_RENOWN_LEVEL_CHANGED and progressWanted.UPDATE_FACTION,
    "renown changes refresh the XP / reputation place")

print("datatexts progress PASS")
