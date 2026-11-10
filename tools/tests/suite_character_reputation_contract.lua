local root = assert(arg[1], "Suite checkout required")
local addon = root .. "/MSUF_Suite_CharacterPanel/"
local Strict = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
local secret = Strict.New("number")
local function Public(value) return not Strict.IsSecret(value) end
local function Finite(value) return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge end
local function Number(value) if Finite(value) then return value end end
local function Text(value) if Public(value) and type(value) == "string" then return value end end
local S = { Text = function(value) return value end, Public = Public, PublicText = Text, Finite = Finite }
local NS = { Host = { Client = { isForever = false } }, Suite = S, Number = Number, String = Text, Public = Public, Text = S.Text }
NS.Host.Text = S.Text
assert(loadfile(root .. "/MSUF_Suite/Core/CharacterTabs.lua"))("MSUF_Suite", NS.Host)

MAX_REPUTATION_REACTION = 8
RENOWN_LEVEL_LABEL = "Renown %d"
REPUTATION_PROGRESS_FORMAT = "%s / %s"
BreakUpLargeNumbers = tostring
local ranks = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local sexReads, countReads, factionReads, paragonReads, rankReads = 0, 0, 0, 0, 0
UnitSex = function() sexReads = sexReads + 1; return 2 end
GetText = function(key, sex)
    assert(sex == 2)
    rankReads = rankReads + 1
    return ranks[tonumber(key:sub(-1))]
end

local function Faction(name, id, rank, low, high, standing)
    return {
        name = name, factionID = id, reaction = rank,
        currentReactionThreshold = low, nextReactionThreshold = high, currentStanding = standing,
    }
end
local guild = Faction("Guild", 12, 5, 3000, 9000, 4500)
guild.isHeader, guild.isHeaderWithRep, guild.isCollapsed = true, true, true
local factions = {
    { name = "Alliance", isHeader = true },
    Faction("Stormwind", 1, 4, 0, 3000, 640),
    Faction("Odd thresholds", 2, 4, 10, 510, 310),
    Faction("Unknown", 3, 4, 0, 3000, secret),
    Faction("Complete", 4, 8, 42000, 43000, 42000),
    Faction("Major", 5, 4, 0, 3000, 0),
    Faction("Friendship", 6, 4, 0, 3000, 0),
    Faction("Paragon", 7, 8, 42000, 43000, 42500),
    Faction("Hostile", 8, 2, -6000, -3000, -5000),
    { name = secret },
    guild,
}
local watched, tooLowLevel
C_Reputation = {
    GetNumFactions = function() countReads = countReads + 1; return #factions end,
    GetFactionDataByIndex = function(i) factionReads = factionReads + 1; return factions[i] end,
    GetWatchedFactionData = function() return watched end,
    IsFactionParagonForCurrentPlayer = function(id) paragonReads = paragonReads + 1; return id == 7 end,
    GetFactionParagonInfo = function(id) assert(id == 7); return 11300, 10000, 20, true, tooLowLevel end,
    IsMajorFaction = function(id) return id == 5 end,
}
local maxRenown = false
C_MajorFactions = {
    GetMajorFactionData = function() return { renownLevel = 5, renownReputationEarned = 1500, renownLevelThreshold = 2500 } end,
    HasMaximumRenown = function() return maxRenown end,
}
local nextFriendship = 1200
C_GossipInfo = { GetFriendshipReputation = function(id)
    if id ~= 6 then return { friendshipFactionID = 0 } end
    return { friendshipFactionID = id, reaction = "Friend", standing = 850, reactionThreshold = 600,
        nextThreshold = nextFriendship }
end }

assert(loadfile(root .. "/MSUF_Suite_Modules/PlayerReaders.lua"))("MSUF_Suite_Modules", { Suite = S })
assert(loadfile(addon .. "Reputation.lua"))("MSUF_Suite_CharacterPanel", NS)
assert(loadfile(addon .. "Pages.lua"))("MSUF_Suite_CharacterPanel", NS)
local stopSecretWatch = Strict.Watch(addon .. "Pages.lua", { strict = true })
local groups = {}
local function Read(config) return NS.Pages.Read("reputation", groups, config) end

Read()
assert(countReads == 1 and factionReads == #factions and sexReads == 1 and paragonReads == 0)
local alliance, guildGroup = groups[1], groups[2]
assert(alliance.title == "Alliance" and alliance.action == 1 and #alliance.rows == 8)
assert(guildGroup.title == "Guild" and guildGroup.action == #factions and guildGroup.collapsed)
assert(guildGroup.rows[1].label == "Reputation" and guildGroup.rows[1].value == "Friendly")
local city, unusual, unknown, complete, major, friend, paragon, hostile = unpack(alliance.rows)
assert(city.value == "Neutral" and major.value == "Renown 5" and friend.value == "Friend" and paragon.value == "Exalted")
assert(city.reputationFill == nil and city.tooltip == nil)

local config = { showReputationBars = true, reputationValue = 3, reputationGoal = 8 }
Read(config)
assert(countReads == 2 and factionReads == 2 * #factions and sexReads == 2, "a render scanned factions twice")
assert(groups[1] == alliance and groups[1].rows[1] == city, "refresh recreated the pooled row")
assert(city.value == "41360 until Exalted" and city.reputationFill == 42640 / 84000 and city.reputationReaction == 4)
assert(unusual.value == "200 until Friendly" and unusual.reputationFill == .6, "guessed a distant custom threshold")
assert(unknown.value == "Neutral" and unknown.reputationFill == nil and unknown.tooltip == nil, "secret rep became full")
assert(complete.value == "0 until Exalted" and complete.reputationFill == 1)
assert(major.value == "1000 until Renown 6" and major.reputationFill == .6 and major.reputationReaction == nil)
assert(friend.value == "350 until Next rank" and friend.reputationFill == 250 / 600)
assert(paragon.value == "Reward available" and paragon.reputationFill == 1)
assert(hostile.value == "47000 until Exalted" and hostile.reputationFill == 37000 / 84000)

local tip = { lines = {} }
function tip:AddLine(line) self.lines[#self.lines + 1] = line end
function tip:AddDoubleLine(left, right) self:AddLine(left .. " " .. right) end
city.tooltip(tip, city.tooltipArgument)
assert(tip.lines[1] == "Reputation Neutral" and tip.lines[2] == "Progress 42640 / 84000"
    and tip.lines[3] == "41360 until Exalted" and tip.lines[4] == "2360 until Friendly")
factions[9].currentStanding = -4500
local details = city.tooltipArgument
local previousRankReads = rankReads
Read(config)
assert(city.tooltipArgument == details and rankReads == previousRankReads, "unchanged repaint recreated detail data or labels")
assert(hostile.value == "46500 until Exalted" and hostile.reputationFill == 37500 / 84000)
    local crossing = factions[9]
    crossing.reaction, crossing.currentReactionThreshold, crossing.nextReactionThreshold = 3, -3000, 0
    crossing.currentStanding = -2900
    tooLowLevel = true
    Read(config)
    assert(hostile.value == "44900 until Exalted" and hostile.reputationFill == 39100 / 84000,
        "crossing a negative rank regressed fixed-goal progress")
    assert(paragon.value ~= "Reward available", "a level-ineligible reward was marked claimable")

config.reputationValue, config.reputationGoal = 2, 1
Read(config)
assert(city.value == "640 / 3000" and city.reputationFill == 640 / 3000)
assert(complete.value == "Exalted" and complete.reputationFill == 1)
config.reputationValue = 4
maxRenown, nextFriendship = true, nil
Read(config)
assert(city.value == "21%" and major.value == "100%" and friend.value == "100%")
nextFriendship = secret
Read(config)
assert(friend.value == "Friend" and friend.reputationFill == nil, "unknown friendship limit looked capped")

Read()
assert(city.value == "Neutral" and city.reputationFill == nil and city.reputationReaction == nil and city.tooltip == nil)
assert(paragon.value == "Exalted" and paragon.reputationFill == nil, "plain display retained a detailed pooled row")
assert(NS.Reputation.OptionsKey(nil) == NS.Reputation.OptionsKey({}))
assert(NS.Reputation.OptionsKey(config) ~= NS.Reputation.OptionsKey({ reputationValue = 4 }))
local sample = { label = "Progress" }
NS.Reputation.Sample(sample, config)
assert(sample.value == "21%" and sample.reputationFill == 640 / 3000)
NS.Reputation.Sample(sample, nil)
assert(sample.value == "640 / 3000" and sample.reputationFill == nil)

watched = factions[4]
assert(S.ReputationProgress() == nil, "watched readers received a missing denominator")
watched = factions[8]
assert(S.ReputationProgress().kind == "paragon" and S.ReputationProgress().current == 10000)
do
    local directReads, currencyReads = 0, 0
    C_Reputation.GetFactionDataByID = function(id)
        directReads = directReads + 1
        if id == 99 then return secret end
        for _, faction in ipairs(factions) do if faction.factionID == id then return faction end end
    end
    C_CurrencyInfo = { GetCurrencyInfo = function(id)
        currencyReads = currencyReads + 1
        return id == 14 and { name = "Test currency", quantity = 120 } or { name = secret, quantity = secret }
    end }
    local pages, output = NS.Pages, {}
    local definition = { cards = { { title = "My character", rows = {
        { source = "faction:1", label = "", x = 4, y = 2 },
        { source = "faction:1", label = "My faction" },
        { source = "currency:14", label = "" },
        { source = "watchedReputation", label = "" },
        { source = "faction:99", label = "" },
        { source = "reputationReport", label = "", x = 7, y = -3 },
        { source = "reputationReport", label = "" },
    } } } }
    local options = { showReputationBars = true, reputationValue = 3, reputationGoal = 8 }
    local state = { config = options }
    local plan = pages.CustomPlan(definition)
    assert(plan.reputation and plan.hasReports and #plan.readers == 0)
    local subscribed, removed = {}, {}
    for _, event in ipairs(pages.CustomEvents(plan, pages.ReputationKey("custom1", options, plan))) do
        subscribed[event] = true
    end
    assert(subscribed.UPDATE_FACTION and subscribed.QUEST_TURNED_IN and subscribed.CURRENCY_DISPLAY_UPDATE)
    local previousCount = countReads
    pages.Custom(output, plan, state, false)
    local rows = output[1].rows
    assert(rows[1].label == "Stormwind" and rows[1].value == "41360 until Exalted" and rows[1].reputationFill)
    assert(rows[2].label == "My faction" and rows[2].value == rows[1].value)
    assert(rows[3].label == "Test currency" and rows[3].value == 120 and rows[3].reputationFill == nil)
    assert(rows[4].label == "Paragon" and rows[5].label == "Faction reputation (99)" and rows[5].value == "—")
    assert(rows[7].layout == rows[6].layout and rows[8].layout == rows[6].layout)
    assert(directReads == 2 and currencyReads == 1 and countReads == previousCount + 1,
        "custom faction duplicates or whole reports repeated their native read")
    assert(rows[#rows].value == "—", "duplicate whole report expanded twice")
    local pooled = rows[1]
    pages.Custom(output, plan, state, false)
    assert(rows[1] == pooled and directReads == 2 and currencyReads == 1 and countReads == previousCount + 1)
    pages.InvalidateCustom(plan, "CURRENCY_DISPLAY_UPDATE")
    pages.Custom(output, plan, state, false)
    assert(directReads == 2 and currencyReads == 2 and countReads == previousCount + 1,
        "a currency change rescanned reputation")
    pages.InvalidateCustom(plan, "UPDATE_FACTION")
    pages.Custom(output, plan, state, false)
    assert(directReads == 4 and currencyReads == 2 and countReads == previousCount + 2)
    watched = nil
    pages.InvalidateCustom(plan, "UPDATE_FACTION")
    pages.Custom(output, plan, state, true)
    assert(rows[4].label == "Watched reputation" and rows[4].value == "—"
        and not rows[4].tooltip and rows[4].reputationFill == nil, "watched replacement kept stale progress")
    local before = directReads
    pages.Custom(output, plan, nil, nil, options)
    assert(#rows == #definition.cards[1].rows and rows[6].value == "Report",
        "preview expansion broke the one-handle-per-authored-row contract")
    pages.Custom(output, plan, state, true)
    assert(directReads == before + 2, "preview mutated or invalidated the runtime snapshot")
    options.reputationValue, options.reputationGoal, options.showReputationBars = 1, 1, false
    pages.CustomPlan(definition, true)
    pages.Custom(output, plan, state, false)
    assert(rows[1].value == "Neutral" and rows[1].reputationFill == nil and rows[1].tooltip == nil)
    assert(pages.ReputationKey("custom1", options, plan) == NS.Reputation.OptionsKey())
    local events = pages.CustomEvents(plan, pages.ReputationKey("custom1", options, plan))
    for _, event in ipairs(events) do assert(event ~= "QUEST_TURNED_IN") end

    local attributes = pages.CustomPlan({ cards = { { title = "Stats", rows = {
        { source = "attributesReport", label = "" },
    } } } })
    pages.CustomEvents(attributes)
    local transitions = 0
    pages.SyncCustomEvents(attributes, true, function(events, enabled, isPage)
        transitions = transitions + 1
        assert(not enabled and isPage)
        for _, event in ipairs(events) do removed[event] = true end
    end)
    assert(removed.SPEED_UPDATE and removed.SPELL_POWER_CHANGED)
    pages.SyncCustomEvents(attributes, true, function() error("unchanged combat reconfigured events") end)
    pages.SyncCustomEvents(attributes, false, function(_, enabled) assert(enabled) transitions = transitions + 1 end)
    assert(transitions == 2)
end
stopSecretWatch()
print("Suite character reputation contract passed")
