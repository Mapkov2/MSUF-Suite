local root = assert(arg[1], "repository root required")
local installed = {}
local notices, chat = {}, {}
local function public(value) return value ~= "secret" end
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = public,
    PublicText = function(value)
        return public(value) and type(value) == "string" and value ~= "" and value or nil
    end,
    Finite = function(value)
        return public(value) and type(value) == "number" and value == value
    end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
    RegisterOwnedMover = function() end,
}
local ns = { AnchorPoints = { "CENTER" }, IsCombatLocked = function() return false end }
local function context()
    return { events = {},
        Event = function(self, event, callback) self.events[event] = callback end,
        RemoveEvent = function(self, event) self.events[event] = nil end,
    }
end

-- The second click opens Blizzard's confirmation dialog, never submits it.
local hooked, opens, now = nil, 0, 10
local dialogBlocked = false
hooksecurefunc = function(name, callback)
    assert(name == "LFGListSearchEntry_OnClick")
    hooked = callback
end
GetTime = function() return now end
local buttonEnabled = true
local panelShown = true
LFGListFrame = { SearchPanel = {
    selectedResult = 11,
    SignUpButton = { IsEnabled = function() return buttonEnabled end },
    IsShown = function() return panelShown end,
} }
LFGListSearchPanel_SignUp = function(panel)
    assert(panel == LFGListFrame.SearchPanel)
    if dialogBlocked then error("restricted dialog") end
    opens = opens + 1
end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupFinderDoubleClick.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local finder = assert(installed.groupFinderDoubleClick)
finder.context, finder.active = context(), true
finder:Enable()
assert(finder.context.events.ADDON_LOADED and not hooked)
LFGListSearchEntry_OnClick = function() end
finder.context.events.ADDON_LOADED(finder, "ADDON_LOADED", "Blizzard_GroupFinder")
assert(hooked and not finder.context.events.ADDON_LOADED)
hooked({ resultID = 11 }, "LeftButton")
now = 10.2
hooked({ resultID = 11 }, "LeftButton")
assert(opens == 1, "double-click did not open one native dialog")
dialogBlocked = true
local noticesBeforeDialog = #notices
now = 10.5
hooked({ resultID = 11 }, "LeftButton")
now = 10.6
hooked({ resultID = 11 }, "LeftButton")
assert(#notices == noticesBeforeDialog + 1 and opens == 1,
    "restricted group finder dialog raised an error")
dialogBlocked = false
buttonEnabled = false
hooked({ resultID = 11 }, "LeftButton")
now = 10.3
hooked({ resultID = 11 }, "LeftButton")
assert(opens == 1, "disabled sign-up was bypassed")
buttonEnabled = "secret"
hooked({ resultID = 11 }, "LeftButton")
now = 10.35
hooked({ resultID = 11 }, "LeftButton")
assert(opens == 1, "secret enabled state was used as a condition")
buttonEnabled = true
panelShown = "secret"
hooked({ resultID = 11 }, "LeftButton")
now = 10.4
hooked({ resultID = 11 }, "LeftButton")
assert(opens == 1, "secret panel state was used as a condition")
panelShown = true
finder:Disable()
finder.active = false
buttonEnabled = true
hooked({ resultID = 11 }, "LeftButton")
assert(opens == 1, "disabled module still opened the dialog")

-- The command shares only the player's readable keystone, on explicit channel.
SlashCmdList = {}
local mapID, level = 101, 12
local addonMessages = {}
C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return mapID end,
    GetOwnedKeystoneLevel = function() return level end,
}
C_ChallengeMode = { GetMapUIInfo = function(id)
    assert(id == 101)
    return "The Dawn"
end }
C_ChatInfo = {
    SendChatMessage = function(message, channel) chat[#chat + 1] = { message, channel } end,
    RegisterAddonMessagePrefix = function(prefix)
        assert(prefix == "MSUFKEY1")
        return true
    end,
    SendAddonMessage = function(prefix, payload, channel)
        addonMessages[#addonMessages + 1] = { prefix, payload, channel }
    end,
}
LE_PARTY_CATEGORY_INSTANCE = 2
IsInGroup = function(category) return category == nil end
IsInRaid = function() return false end
UnitFullName = function() return "Player", "Realm" end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MPlusKeystoneShare.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local keys = assert(installed.mythicKeyShare)
keys.active, keys.context = true, context()
keys:Enable()
assert(SLASH_MSUFSUITEKEYS1 == "/msufkeys" and SLASH_MSUFSUITEKEYS2 == "/keys")
SlashCmdList.MSUFSUITEKEYS("")
assert(notices[#notices] == "Keystone: The Dawn +12" and #chat == 0)
SlashCmdList.MSUFSUITEKEYS("party")
assert(#chat == 1 and chat[1][2] == "PARTY" and chat[1][1] == "Keystone: The Dawn +12")
now = 20
SlashCmdList.MSUFSUITEKEYS("group")
assert(addonMessages[1][1] == "MSUFKEY1" and addonMessages[1][2] == "Q"
    and addonMessages[1][3] == "PARTY")
local beforeNotice = #notices
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "K:101:12", "PARTY", "Alice-Realm")
assert(#notices == beforeNotice + 1 and notices[#notices] == "Alice-Realm: The Dawn +12")
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "secret", "PARTY", "Mallory-Realm")
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "K:999999:12", "PARTY", "Mallory-Realm")
assert(#notices == beforeNotice + 1, "secret or invalid peer payload was printed")
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "K:101:12", "PARTY", "Alice-Realm")
assert(#notices == beforeNotice + 1, "duplicate peer key printed twice")
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "Q", "PARTY", "Player-Realm")
assert(#addonMessages == 1, "responded to own request")
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "Q", "PARTY", "Bob-Realm")
assert(#addonMessages == 2 and addonMessages[2][2] == "K:101:12")
now = 26
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "K:101:12", "PARTY", "Carol-Realm")
assert(#notices == beforeNotice + 1, "unsolicited key was printed")
mapID = "secret"
SlashCmdList.MSUFSUITEKEYS("party")
assert(#chat == 1 and notices[#notices] == "No owned keystone found")
keys:Disable()
assert(not SlashCmdList.MSUFSUITEKEYS and not SLASH_MSUFSUITEKEYS1
    and not keys.context.events.CHAT_MSG_ADDON)

-- Player aura deltas stay dormant outside a group and skip unrelated spells.
local grouped, auraReads, auraRestricted = false, 0, false
local auras = {}
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
    auraReads = auraReads + 1
    if auraRestricted then error("unit auras restricted") end
    return auras[id]
end }
local function widget()
    return setmetatable({ shown = false }, { __index = {
        SetSize = function() end, SetScale = function() end, ClearAllPoints = function() end,
        SetPoint = function() end, SetText = function(self, value) self.text = value end,
        SetTextColor = function() end, SetColorTexture = function() end,
        SetCooldown = function(self, start, duration)
            self.start, self.duration = start, duration
        end,
        Clear = function(self) self.start, self.duration = nil, nil end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    } })
end
UIParent = {}
IsInGroup = function() return grouped end
assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, suite)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupBloodlust.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local lust = assert(installed.groupBloodlust)
lust.host, lust.cooldown, lust.title, lust.status = widget(), widget(), widget(), widget()
lust.background, lust.edges = widget(), { widget(), widget(), widget(), widget() }
lust.active, lust.context = true, context()
lust.config = { point = 1, width = 172, height = 42, scale = 100, x = 0, y = 0,
    onlyWhenLocked = false }
lust:Enable()
assert(not lust.context.events.UNIT_AURA and auraReads == 0 and not lust.host.shown)
grouped = true
lust.context.events.GROUP_ROSTER_UPDATE(lust)
assert(lust.context.events.UNIT_AURA and lust.status.text == "Ready" and lust.host.shown)
local before = auraReads
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    addedAuras = { { spellId = 123 } } })
assert(auraReads == before, "unrelated aura delta queried lockout auras")
auras[57724] = { auraInstanceID = 9, duration = 600, expirationTime = 800 }
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    addedAuras = { { spellId = 57724 } } })
assert(lust.status.text == "Locked" and lust.cooldown.start == 200
    and lust.cooldown.duration == 600)
auras[57724] = nil
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    removedAuraInstanceIDs = { 9 } })
assert(lust.status.text == "Ready" and lust.cooldown.start == nil)
auraRestricted = true
ns.IsCombatLocked = function() return auraRestricted end
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = true })
local readsAtRestriction = auraReads
assert(lust.auraBlocked and not lust.context.events.UNIT_AURA and not lust.host.shown,
    "restricted aura lookup did not stop until combat ends")
lust.context.events.GROUP_ROSTER_UPDATE(lust)
assert(auraReads == readsAtRestriction,
    "restricted aura lookup repeated on a roster update")
auraRestricted = false
lust.context.events.PLAYER_REGEN_ENABLED(lust)
assert(lust.context.events.UNIT_AURA and lust.host.shown
    and lust.status.text == "Ready", "lockout did not resume after combat")
lust:Disable()
assert(not lust.context.events.UNIT_AURA and not lust.context.events.GROUP_ROSTER_UPDATE
    and not lust.context.events.PLAYER_ENTERING_WORLD
    and not lust.context.events.PLAYER_REGEN_ENABLED and not lust.host.shown)

-- A Delve power is selected only when Blizzard exposes one safe response.
local chosen = {}
local inCombat, activeDelve = false, true
ns.IsCombatLocked = function() return inCombat end
local choice = { choiceID = 7, options = { {
    spellID = 2345, disabledOption = false,
    buttons = { { id = 99, disabled = false } },
} } }
C_DelvesUI = { HasActiveDelve = function() return activeDelve end }
C_PlayerChoice = {
    GetCurrentPlayerChoiceInfo = function() return choice end,
    SendPlayerChoiceResponse = function(id) chosen[#chosen + 1] = id end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupDelvePower.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local delve = assert(installed.delveSolePower)
delve.active, delve.context = true, context()
delve:Enable()
assert(#chosen == 1 and chosen[1] == 99)
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
assert(#chosen == 1, "one choice was selected more than once")
delve.context.events.PLAYER_CHOICE_CLOSE(delve)
choice.options[1].buttons[1].confirmation = "Confirm"
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
assert(#chosen == 1, "confirmation was bypassed")
choice.options[1].buttons[1].confirmation = nil
inCombat = true
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
assert(#chosen == 1, "choice was selected in combat")
inCombat = false
activeDelve = false
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
assert(#chosen == 1, "choice was selected outside a Delve")
activeDelve, choice.choiceID = true, 8
C_PlayerChoice.SendPlayerChoiceResponse = function() error("choice changed") end
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
assert(#chosen == 1 and delve.lastChoiceID == 8,
    "a rejected Delve response retried or raised a Lua error")
delve:Disable()
assert(not delve.context.events.PLAYER_CHOICE_UPDATE and not delve.context.events.PLAYER_CHOICE_CLOSE)

-- A reset produces a local notice and never sends automated group chat.
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MPlusResetReminder.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local reset = assert(installed.mythicResetReminder)
reset.active, reset.context = true, context()
reset:Enable()
local beforeChat, beforeNotices = #chat, #notices
reset.context.events.CHALLENGE_MODE_RESET(reset)
assert(#chat == beforeChat and #notices == beforeNotices + 1
    and notices[#notices] == "Keystone was reset")
reset:Disable()
assert(not reset.context.events.CHALLENGE_MODE_RESET)

-- Raid tokens contain the player, unlike party tokens. Keep one canonical
-- player token so the own-death toggle also works in raids without duplicates.
local raid, selfToken = true, "raid1"
local unitDead, restricted = {}, {}
inCombat = true
IsInGroup = function() return true end
IsInRaid = function() return raid end
local function canonical(unit) return unit == selfToken and "player" or unit end
UnitExists = function(unit)
    return unit == "player" or unit == selfToken or unit == "raid2" or unit == "party1"
end
UnitIsUnit = function(unit, other)
    if restricted[unit] then return "secret" end
    return canonical(unit) == canonical(other)
end
UnitIsDeadOrGhost = function(unit) return unitDead[canonical(unit)] == true end
UnitName = function(unit) return canonical(unit) == "player" and "Self" or "Teammate" end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupDeathAlert.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local death = assert(installed.groupDeathAlert)
death.active, death.context, death.config = true, context(), { includePlayer = false }
death:Enable()
local deathNotices = #notices
unitDead.player = true
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", selfToken)
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "player")
assert(#notices == deathNotices, "own raid death ignored includePlayer=false")
unitDead.raid2 = true
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "raid2")
assert(#notices == deathNotices + 1 and notices[#notices] == "Teammate died")

unitDead = {}
death.config.includePlayer = true
death:Refresh()
deathNotices = #notices
unitDead.player = true
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", selfToken)
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "player")
death.context.events.UNIT_FLAGS(death, "UNIT_FLAGS", "player")
assert(#notices == deathNotices + 1 and notices[#notices] == "Self died",
    "own raid death was omitted or reported through both aliases")

-- Roster changes replace the old alias; unreadable identity never enters
-- the baseline. Party behavior still includes the player exactly once.
unitDead, selfToken = {}, "raid3"
restricted.raid2 = true
death.context.events.GROUP_ROSTER_UPDATE(death, "GROUP_ROSTER_UPDATE")
assert(death.dead[selfToken] == nil and death.dead.raid2 == nil and death.dead.player == false,
    "roster rebuild kept a player alias or used restricted identity")
raid, restricted = false, {}
death:Refresh()
deathNotices = #notices
unitDead.player, unitDead.party1 = true, true
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "player")
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "party1")
assert(#notices == deathNotices + 2, "party death behavior changed")
inCombat = false
death.context.events.PLAYER_REGEN_ENABLED(death, "PLAYER_REGEN_ENABLED")
assert(not death.dead and not death.context.events.UNIT_HEALTH and not death.context.events.UNIT_FLAGS,
    "death alert kept watching health outside combat")
death:Disable()
print("Suite group finder, keystone, bloodlust, Delve, reset and death lifecycle passed")
