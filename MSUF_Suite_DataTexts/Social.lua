local _, P = ...
local NS, S = P.NS, P.Suite
local Sources, NO_VALUE = P.DataTextSources, P.NO_VALUE
local Finite, Public, PublicText = S.Finite, S.Public, S.PublicText

-- The Friends and Guild places. Their value is a count of who is online, read
-- from the count APIs, so an event costs a few numbers; bursts of events (a
-- login brings one per friend) fold into one refresh (provider.delay, see
-- Sources.lua). The member list of the tooltip is built when the pointer rests
-- on the place, out of combat, and never beyond ROWS rows. A click opens
-- Blizzard's window through the secure overlay (Actions.lua, S.PanelButton).
local ROWS = 20
local DELAY = .2
-- Guild roster requests are throttled; the roster arrives as GUILD_ROSTER_UPDATE.
local ROSTER_INTERVAL = 15
local TEXT = {
    friends = S.Text("Friends"),
    guild = S.Text("Guild"),
    wowFriends = S.Text("WoW friends online"),
    bnetFriends = S.Text("Battle.net friends online"),
    members = S.Text("Members online"),
    level = S.Text("Level %d"),
    more = S.Text("Open the window to see everyone."),
}
local GRAY = .7

local function Table(value)
    return Public(value) and type(value) == "table"
end

local function True(value)
    return Public(value) and value == true
end

local function Colored(name, classFile)
    local hex = PublicText(classFile) and S.ClassHex(classFile)
    return hex and "|cff" .. hex .. name .. "|r" or name
end

-- Level and zone, the right side of a row.
local function Detail(level, area)
    local text = Finite(level) and TEXT.level:format(level) or ""
    local zone = PublicText(area)
    if zone and zone ~= "" then text = text ~= "" and text .. ", " .. zone or zone end
    return text
end

local function AddRow(tooltip, name, detail)
    tooltip:AddDoubleLine(name, detail, 1, 1, 1, GRAY, GRAY, GRAY)
end

------------------------------------------------------------------ friends
local Friends = { delay = DELAY }

-- Online character friends and online Battle.net friends, the two numbers
-- Blizzard's own friends button adds up (QuickJoinToastMixin:
-- UpdateDisplayedFriendCount); the character list only exists with the
-- legacy friend system. nil while either is withheld.
local function OnlineFriends()
    local _, bnet = BNGetNumFriends()
    local wow = C_FriendList.IsLegacyFriendSystemEnabled() and C_FriendList.GetNumOnlineFriends() or 0
    if Finite(bnet) and Finite(wow) then return wow, bnet end
end

function Friends.Format()
    local wow, bnet = OnlineFriends()
    return TEXT.friends, wow and tostring(wow + bnet) or NO_VALUE
end

-- Returns the rows left after the character friends.
local function WowFriendRows(tooltip, rows)
    for index = 1, C_FriendList.GetNumFriends() do
        if rows <= 0 then break end
        local info = C_FriendList.GetFriendInfoByIndex(index)
        local name = Table(info) and True(info.connected) and PublicText(info.name)
        if name then
            AddRow(tooltip, name, Detail(info.level, info.area))
            rows = rows - 1
        end
    end
    return rows
end

-- A Battle.net friend playing WoW right now: name (account name) and place.
local function BnetFriendRow(tooltip, info)
    local game = Table(info) and info.gameAccountInfo
    if not (Table(game) and True(game.isOnline) and PublicText(game.clientProgram) == BNET_CLIENT_WOW) then return false end
    local character = PublicText(game.characterName)
    if not character then return false end
    local account = PublicText(info.accountName) or PublicText(info.battleTag)
    local name = Colored(character, game.classFilename)
    AddRow(tooltip, account and name .. " (" .. account .. ")" or name, Detail(game.characterLevel, game.areaName))
    return true
end

function Friends.Lines(tooltip)
    if NS.InCombat() then return end
    local wow, bnet = OnlineFriends()
    if not wow then return end
    tooltip:AddDoubleLine(TEXT.wowFriends, tostring(wow), 1, 1, 1, 1, 1, 1)
    tooltip:AddDoubleLine(TEXT.bnetFriends, tostring(bnet), 1, 1, 1, 1, 1, 1)
    local rows = WowFriendRows(tooltip, ROWS)
    for index = 1, BNGetNumFriends() do
        if rows <= 0 then break end
        if BnetFriendRow(tooltip, C_BattleNet.GetFriendAccountInfo(index)) then rows = rows - 1 end
    end
    if rows <= 0 and wow + bnet > ROWS then tooltip:AddLine(TEXT.more, GRAY, GRAY, GRAY) end
end

Sources.Register("friends", Friends, { "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED" })

------------------------------------------------------------------ guild
local Guild = { delay = DELAY }
local lastRequest

-- The roster is requested at most every ROSTER_INTERVAL seconds, when the
-- pointer rests on a Guild place and when no roster has arrived yet.
local function RequestRoster()
    local now = GetTime()
    if lastRequest and now - lastRequest < ROSTER_INTERVAL then return end
    lastRequest = now
    C_GuildInfo.GuildRoster()
end

-- Members and members online; nil outside a guild or before the roster.
local function OnlineMembers()
    if not IsInGuild() then return end
    local total, online = GetNumGuildMembers()
    if Finite(total) and Finite(online) and total > 0 then return total, online end
end

function Guild.Rebind(_, wanted)
    if wanted and IsInGuild() and not OnlineMembers() then RequestRoster() end
end

function Guild.Format()
    local _, online = OnlineMembers()
    return TEXT.guild, online and tostring(online) or NO_VALUE
end

-- The online members, stopping once all of them are listed or ROWS are.
local function MemberRows(tooltip, total, online)
    local rows = math.min(ROWS, online)
    for index = 1, total do
        if rows <= 0 then break end
        local name, _, _, level, _, zone, _, _, isOnline, _, classFile = GetGuildRosterInfo(index)
        local shown = True(isOnline) and PublicText(name)
        if shown then
            AddRow(tooltip, Colored(shown, classFile), Detail(level, zone))
            rows = rows - 1
        end
    end
    return online > ROWS
end

function Guild.Lines(tooltip)
    if NS.InCombat() or not IsInGuild() then return end
    RequestRoster()
    local total, online = OnlineMembers()
    if not total then return end
    tooltip:AddDoubleLine(TEXT.members, tostring(online), 1, 1, 1, 1, 1, 1)
    if MemberRows(tooltip, total, online) then tooltip:AddLine(TEXT.more, GRAY, GRAY, GRAY) end
end

Sources.Register("guild", Guild, { "GUILD_ROSTER_UPDATE" })
