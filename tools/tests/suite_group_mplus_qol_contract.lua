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
local support = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))()
-- The shipped combat and restriction rules; they follow whatever lockdown
-- and client tables this test installs.
local ns
ns = support.Platform(root, setmetatable({ InCombatLockdown = function() return ns.IsCombatLocked() end },
    { __index = _G }))
ns.AnchorPoints, ns.IsCombatLocked = { "CENTER" }, function() return false end
-- Platform.lua's IsSecret is the client's issecretvalue.
ns.IsSecret = function(value) return value == "secret" end
ns.Dispatch = function(callback, ...) return callback(...) end
support.QoLStyleFixture(root, suite)
local function context()
    return { events = {},
        Event = function(self, event, callback) self.events[event] = callback end,
        RemoveEvent = function(self, event) self.events[event] = nil end,
    }
end

-- Window controls used by the explicit keystone overview.
local function keyWidget()
    local w = { shown = false }
    return setmetatable(w, { __index = function(_, method)
        if method == "Show" then return function(self) self.shown = true end end
        if method == "Hide" then return function(self) self.shown = false end end
        if method == "SetText" then return function(self, value) self.text = value end end
        if method == "SetScript" then return function(self, event, callback) self[event] = callback end end
        return function() end
    end })
end
suite.CreateFrame, suite.CreateTexture, suite.CreateFontString = keyWidget, keyWidget, keyWidget
suite.SetStyledFont, suite.GlobalFontPath = function() end, function() return "font" end
IsShiftKeyDown = function() return false end
IsInGuild = function() return true end
-- The second click opens Blizzard's confirmation dialog, never submits it.
-- Blizzard_GroupFinder loads with the Retail UI before any Suite module.
local hooked, opens, now = nil, 0, 10
local dialogBroken = false
local dialogHooks = {}
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
LFGListSearchEntry_OnClick = function() end
LFGListApplicationDialog = { shown = false, resultID = 11,
    IsShown = function(self) return self.shown end,
    HookScript = function(_, script, callback) dialogHooks[script] = callback end,
    SignUpButton = { IsEnabled = function() return true end } }
LFGListSearchPanel_SignUp = function(panel)
    assert(panel == LFGListFrame.SearchPanel)
    if dialogBroken then error("Blizzard dialog failed") end
    opens = opens + 1
end
ns.Finish = function(callback, ...) return true, callback(...) end
-- securecallfunction: an error is reported and the call returns nothing.
suite.Dispatch = function(fn, ...)
    local results = { pcall(fn, ...) }
    if results[1] then return unpack(results, 2) end
end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupFinderDoubleClick.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local finder = assert(installed.groupFinderDoubleClick)
finder.context, finder.active, finder.config = context(), true, { note = "" }
finder:Enable()
assert(hooked and dialogHooks.OnShow and not finder.context.events.ADDON_LOADED,
    "double-click waited for an addon that loads with the UI")
hooked({ resultID = 11 }, "LeftButton")
now = 10.2
hooked({ resultID = 11 }, "LeftButton")
assert(opens == 1, "double-click did not open one native dialog")
dialogBroken = true
local noticesBeforeDialog = #notices
now = 10.5
hooked({ resultID = 11 }, "LeftButton")
now = 10.6
hooked({ resultID = 11 }, "LeftButton")
assert(#notices == noticesBeforeDialog + 1 and opens == 1,
    "a failing Blizzard dialog raised an error or gave no notice")
dialogBroken = false
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
local submits, shiftHeld = 0, false
finder.config = { quickApply = true, note = "" }
IsShiftKeyDown = function() return shiftHeld end
local originalOpen = LFGListSearchPanel_SignUp
LFGListSearchPanel_SignUp = function(p) originalOpen(p); LFGListApplicationDialog.shown = true end
LFGListApplicationDialogSignUpButton_OnClick = function() submits = submits + 1; LFGListApplicationDialog.shown = false end
now = 11; hooked({ resultID = 11 }, "LeftButton"); now = 11.1; hooked({ resultID = 11 }, "LeftButton")
assert(submits == 1, "opt-in second click did not submit the valid native dialog")
shiftHeld = true
now = 12; hooked({ resultID = 11 }, "LeftButton"); now = 12.1; hooked({ resultID = 11 }, "LeftButton")
assert(submits == 1 and LFGListApplicationDialog.shown, "Shift failed to retain application dialog")
shiftHeld = false
-- The saved note: a byte limit matching the setting, one save when editing
-- ends, and a change made in combat saved after combat.
local noteWrites, combatNow = {}, false
ns.IsCombatLocked = function() return combatNow end
suite.Set = function(id, key, value)
    assert(id == "groupFinderDoubleClick" and key == "note")
    noteWrites[#noteWrites + 1] = value
    finder.config.note = value
    return true
end
local edit
suite.CreateFrame = function(kind)
    local w = keyWidget()
    if kind == "EditBox" then
        edit = w
        w.SetMaxBytes = function(self, value) self.maxBytes = value end
        w.SetMaxLetters = function() error("letter limits let multi-byte notes exceed the setting") end
        w.GetText = function(self) return self.text end
        w.ClearFocus = function(self) if self.OnEditFocusLost then self.OnEditFocusLost(self) end end
    end
    return w
end
finder.config.showNote = true
dialogHooks.OnShow()
assert(edit and edit.maxBytes == 64 and finder.notePanel.shown, "note panel missing or not byte-limited")
edit.text = "Übung"
assert(#noteWrites == 0, "the note was saved per keystroke")
edit.OnEditFocusLost(edit)
assert(#noteWrites == 1 and noteWrites[1] == "Übung", "finished note edit was not saved once")
combatNow = true
edit.text = "Kampfnotiz"
edit.OnEditFocusLost(edit)
assert(#noteWrites == 1 and finder.context.events.PLAYER_REGEN_ENABLED, "combat note edit was lost or written in combat")
combatNow = false
finder.context.events.PLAYER_REGEN_ENABLED(finder, "PLAYER_REGEN_ENABLED")
assert(#noteWrites == 2 and noteWrites[2] == "Kampfnotiz" and not finder.context.events.PLAYER_REGEN_ENABLED,
    "combat note edit was not saved after combat")
ns.IsCombatLocked = function() return false end
suite.CreateFrame = keyWidget
local opensBeforeDisable = opens
finder:Disable()
finder.active = false
buttonEnabled = true
hooked({ resultID = 11 }, "LeftButton")
assert(opens == opensBeforeDisable, "disabled module still opened the dialog")

-- The command shares only the player's readable keystone, on explicit channel.
local slash = support.SlashRegistry()
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
local chatLocked, addonResult = false, 0
Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 } }
UISpecialFrames = {}
C_ChatInfo = {
    -- A SendChatMessage call during chat lockdown is blocked and cannot be caught.
    SendChatMessage = function(message, channel)
        assert(not chatLocked, "SendChatMessage called during chat messaging lockdown")
        chat[#chat + 1] = { message, channel }
    end,
    InChatMessagingLockdown = function() return chatLocked end,
    RegisterAddonMessagePrefix = function(prefix)
        assert(prefix == "MSUFKEY1")
        return true
    end,
    SendAddonMessage = function(prefix, payload, channel)
        if addonResult ~= 0 then return addonResult end
        addonMessages[#addonMessages + 1] = { prefix, payload, channel }
        return 0
    end,
}
LE_PARTY_CATEGORY_INSTANCE = 2
IsInGroup = function(category) return category == nil end
IsInRaid = function() return false end
UnitFullName = function() return "Player", "Realm" end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SlashCommands.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MPlusKeystoneShare.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local keys = assert(installed.mythicKeyShare)
keys.active, keys.context = true, context()
keys:Enable()
assert(SLASH_MSUFSUITEKEYS1 == "/msufkeys" and SLASH_MSUFSUITEKEYS2 == "/keys")
assert(slash.Type("/keys"), "the typed /keys alias did not run")
assert(notices[#notices] == "Keystone: The Dawn +12" and #chat == 0)
SlashCmdList.MSUFSUITEKEYS("party")
assert(#chat == 1 and chat[1][2] == "PARTY" and chat[1][1] == "Keystone: The Dawn +12")
-- Inside a dungeon chat is locked down even before the key starts.
chatLocked = true
SlashCmdList.MSUFSUITEKEYS("party")
assert(#chat == 1 and notices[#notices] == "Chat messages are blocked here right now; only you see your keystone."
    and notices[#notices - 1] == "Keystone: The Dawn +12", "a locked-down key share was sent or not shown locally")
chatLocked = false
assert(UISpecialFrames[1] == "MSUFSuiteKeystones", "Escape does not close the keystone window")
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
mapID, now = 101, 28
addonResult = Enum.SendAddonMessageResult.AddOnMessageLockdown
SlashCmdList.MSUFSUITEKEYS("group")
assert(notices[#notices] == "Keystone requests cannot be sent right now; the window lists only your own key."
    and not keys.requestExpiresAt, "a refused key request gave no feedback or kept waiting for answers")
addonResult = 0
now = 30
SlashCmdList.MSUFSUITEKEYS("guild")
assert(addonMessages[#addonMessages][3] == "GUILD" and keys.host.shown)
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "K:101:12", "GUILD", "Guildmate-Realm")
assert(keys.rows["Guildmate-Realm"] == "The Dawn +12")
keys.context.events.CHAT_MSG_ADDON(keys, "CHAT_MSG_ADDON", "MSUFKEY1", "K:101:12", "PARTY", "WrongChannel-Realm")
assert(not keys.rows["WrongChannel-Realm"], "reply from previous request channel entered guild table")
local inserted, picked, cursorID = 0, 0, nil
keys.config = { insertKey = true }
ChallengesKeystoneFrame = { HookScript = function(self, _, fn) self.show = fn end }
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemInfo = function() return { hyperlink = "|Hkeystone:180653:101:12|h[Keystone]|h", isLocked = false, itemID = 180653 } end,
    PickupContainerItem = function() picked = picked + 1; cursorID = 180653 end }
CursorHasItem = function() return cursorID ~= nil end
GetCursorInfo = function() if cursorID then return "item", cursorID end end
ClearCursor = function() cursorID = nil end
C_ChallengeMode.HasSlottedKeystone = function() return false end
C_ChallengeMode.SlotKeystone = function() inserted = inserted + 1; cursorID = nil end
-- S.QoLRestrictedCall (Bootstrap.lua) reports an ADDON_ACTION_BLOCKED refusal.
local refuseKey = false
suite.QoLRestrictedCall = function(action, ...)
    if refuseKey then refuseKey = false; return false end
    action(...)
    return true
end
keys.context.events.ADDON_LOADED(keys, "ADDON_LOADED", "Blizzard_ChallengesUI")
ChallengesKeystoneFrame.show()
assert(picked == 1 and inserted == 1 and cursorID == nil)
cursorID = 99; ChallengesKeystoneFrame.show()
assert(picked == 1 and cursorID == 99, "key insertion replaced a foreign cursor")
cursorID = nil
-- A refused insertion is reported and the picked-up key goes back.
refuseKey = true
ChallengesKeystoneFrame.show()
assert(picked == 2 and inserted == 1 and cursorID == nil
    and notices[#notices] == "Keystone insertion was blocked by the client.", "a refused key insertion gave no feedback")
keys:Disable()
assert(not SlashCmdList.MSUFSUITEKEYS and not SLASH_MSUFSUITEKEYS1
    and not keys.context.events.CHAT_MSG_ADDON)

-- Player aura deltas stay dormant outside a group and skip unrelated spells.
local grouped, auraReads, auraRestricted = false, 0, false
local auras = {}
local auraTimers = {}
C_Timer = { After = function(delay, callback)
    assert(delay == .1, "lockout refresh changed its bounded delay")
    auraTimers[#auraTimers + 1] = callback
end }
local function DrainAuras()
    while #auraTimers > 0 do table.remove(auraTimers, 1)() end
end
-- The client under combat, encounter or keystone restrictions: the lockout
-- auras are secret and GetPlayerAuraBySpellID returns nothing for them
-- (RequiresNonSecretAura); it never raises.
C_Secrets = { ShouldSpellAuraBeSecret = function() return auraRestricted end }
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
    auraReads = auraReads + 1
    if auraRestricted then return nil end
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
-- RestrictedActionsConstantsDocumentation.lua: Inactive 0, Activating 1, Active 2.
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupBloodlust.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local lust = assert(installed.groupBloodlust)
lust.host, lust.cooldown, lust.title, lust.status = widget(), widget(), widget(), widget()
lust.background, lust.edges = widget(), { widget(), widget(), widget(), widget() }
lust.active, lust.context = true, support.ModuleTimers(root, suite, ns)("groupBloodlust", lust, context())
lust.config = { point = 1, width = 172, height = 42, scale = 100, x = 0, y = 0,
    onlyWhenLocked = false }
local moverRegistrations, register = 0, suite.RegisterOwnedMover
suite.RegisterOwnedMover = function(...) moverRegistrations = moverRegistrations + 1; return register(...) end
lust:Enable()
-- The controller registers the movers after Enable (S.RefreshEditMover).
assert(moverRegistrations == 0, "Enable registered the Edit Mode mover itself")
suite.RegisterOwnedMover = register
assert(not lust.context.events.UNIT_AURA and auraReads == 0 and not lust.host.shown)
grouped = true
lust.context.events.GROUP_ROSTER_UPDATE(lust)
assert(lust.context.events.UNIT_AURA and lust.status.text == "Ready" and lust.host.shown)
local before = auraReads
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    addedAuras = { { spellId = 123 } } })
assert(auraReads == before, "unrelated aura delta queried lockout auras")
do
    local delta={isFullUpdate=false}
    local callback=lust.context.events.UNIT_AURA
    collectgarbage("collect");collectgarbage("stop")
    local memory=collectgarbage("count")
    for _=1,500 do callback(lust,"UNIT_AURA","player",delta) end
    local allocated=collectgarbage("count")-memory
    collectgarbage("restart")
    assert(allocated<1 and auraReads==before,
        "irrelevant empty aura deltas allocated scratch tables or read lockouts")
end
auras[57724] = { auraInstanceID = 9, duration = 600, expirationTime = 800 }
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    addedAuras = { { spellId = 57724 } } })
assert(#auraTimers == 1 and auraReads == before,
    "a lockout delta fetched data before its shared callback")
DrainAuras()
assert(lust.status.text == "Locked" and lust.cooldown.start == 200
    and lust.cooldown.duration == 600)
do
    auras[57724].auraInstanceID="secret"
    local callback=lust.context.events.UNIT_AURA
    callback(lust,"UNIT_AURA","player",{isFullUpdate=true})
    DrainAuras()
    assert(lust.unknownInstanceID,"restricted lockout ID was not classified")
    local reads=auraReads
    callback(lust,"UNIT_AURA","player",{isFullUpdate=false,addedAuras={{spellId=123}}})
    callback(lust,"UNIT_AURA","player",{isFullUpdate=false})
    assert(auraReads==reads,"added-only unrelated deltas re-fetched an unknown lockout")
    local delta={isFullUpdate=false,updatedAuraInstanceIDs={99}}
    callback(lust,"UNIT_AURA","player",delta)
    collectgarbage("collect");collectgarbage("stop")
    local memory=collectgarbage("count")
    for _=1,1000 do callback(lust,"UNIT_AURA","player",delta) end
    local allocated=collectgarbage("count")-memory
    collectgarbage("restart")
    assert(allocated<1 and auraReads==reads and #auraTimers==1,
        "an unknown-instance aura storm repeated reads, timers or allocations")
    DrainAuras()
    assert(auraReads>reads,"an unknown lockout update was skipped")
    reads=auraReads
    -- UNIT_AURA listens only while C_Secrets keeps the lockout spells
    -- readable, so an added aura with a secret spell ID is another buff
    -- (raid combat sends many); restriction edges read again instead.
    callback(lust,"UNIT_AURA","player",{isFullUpdate=false,addedAuras={{spellId="secret"}}})
    DrainAuras()
    assert(auraReads==reads and #auraTimers==0,"a secret added spell re-read the readable lockouts")
    assert(lust.context.events.ADDON_RESTRICTION_STATE_CHANGED,
        "restriction edges are not heard while the lockouts are readable")
    lust.context.events.ADDON_RESTRICTION_STATE_CHANGED(lust,"ADDON_RESTRICTION_STATE_CHANGED",1,1)
    assert(auraReads==reads and #auraTimers==1,"an activating restriction read before its dispatch ended")
    DrainAuras()
    assert(auraReads>reads,"an activating restriction did not read the lockouts again")
end
auras[57724] = nil
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    removedAuraInstanceIDs = { 9 } })
DrainAuras()
assert(lust.status.text == "Ready" and lust.cooldown.start == nil)
-- Fury of the Aspects leaves its own Exhaustion (390435).
auras[390435] = { auraInstanceID = 10, duration = 600, expirationTime = 900 }
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = false,
    addedAuras = { { spellId = 390435 } } })
DrainAuras()
assert(lust.status.text == "Locked" and lust.cooldown.start == 300,
    "the Evoker's Exhaustion did not count as a Bloodlust lockout")
-- Restricted: the known lockout keeps counting; no aura is read or claimed.
now = 400
auraRestricted = true
ns.IsCombatLocked = function() return auraRestricted end
local readsAtRestriction = auraReads
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = true })
DrainAuras()
assert(lust.status.text == "Locked" and lust.host.shown and auraReads == readsAtRestriction
    and not lust.context.events.UNIT_AURA and lust.context.events.ADDON_RESTRICTION_STATE_CHANGED,
    "a restricted aura lookup replaced the known lockout or kept listening to auras")
now = 950
lust.context.events.GROUP_ROSTER_UPDATE(lust)
assert(auraReads == readsAtRestriction and lust.host.shown and lust.status.text == "Unknown",
    "an unreadable lockout state was shown as Ready or read again")
lust.config.onlyWhenLocked = true
lust.context.events.GROUP_ROSTER_UPDATE(lust)
assert(not lust.host.shown, "only-while-exhausted showed an unknown state")
lust.config.onlyWhenLocked = false
auraRestricted = false
auras[390435] = nil
lust.context.events.ADDON_RESTRICTION_STATE_CHANGED(lust, "ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
assert(lust.context.events.UNIT_AURA and lust.context.events.ADDON_RESTRICTION_STATE_CHANGED
    and lust.host.shown and lust.status.text == "Ready", "lockout did not resume when the restriction ended")
auraRestricted = true
lust.context.events.UNIT_AURA(lust, "UNIT_AURA", "player", { isFullUpdate = true })
DrainAuras()
assert(lust.status.text == "Unknown", "a fresh restriction claimed a lockout state")
auraRestricted = false
lust.context.events.PLAYER_REGEN_ENABLED(lust, "PLAYER_REGEN_ENABLED")
assert(lust.context.events.UNIT_AURA and lust.status.text == "Ready", "lockout did not resume after combat")
lust.context.events.UNIT_AURA(lust,"UNIT_AURA","player",{isFullUpdate=true})
lust.context.events.GROUP_ROSTER_UPDATE(lust)
local readsAfterRefresh=auraReads
DrainAuras()
assert(auraReads==readsAfterRefresh,"a roster/settings paint did not consume pending aura work")
lust.context.events.UNIT_AURA(lust,"UNIT_AURA","player",{isFullUpdate=true})
-- As the controller stops a module: inactive, Disable, then Release.
lust.active = false
lust:Disable()
lust.context:CancelTimers()
DrainAuras()
assert(auraReads==readsAfterRefresh,"a stale lockout callback queried after disable")
assert(not lust.context.events.UNIT_AURA and not lust.context.events.GROUP_ROSTER_UPDATE
    and not lust.context.events.PLAYER_ENTERING_WORLD and not lust.context.events.ADDON_RESTRICTION_STATE_CHANGED
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
-- The server refuses a response for a changed choice; the API never raises.
local refused = 0
C_PlayerChoice.SendPlayerChoiceResponse = function() refused = refused + 1 end
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
delve.context.events.PLAYER_CHOICE_UPDATE(delve)
assert(#chosen == 1 and refused == 1 and delve.lastChoiceID == 8,
    "a refused Delve response was sent more than once")
delve:Disable()
assert(not delve.context.events.PLAYER_CHOICE_UPDATE and not delve.context.events.PLAYER_CHOICE_CLOSE)

-- A reset produces a local notice and never sends automated group chat.
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MPlusResetReminder.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
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
-- Screen/chat/sound are independent, and simultaneous deaths produce one sound.
local screenNotices, sounds = {}, 0
RaidWarningFrame, ChatTypeInfo, SOUNDKIT = {}, { RAID_WARNING = { r = 1, g = .28, b = 0 } }, { RAID_WARNING = 8959 }
PlaySound = function() sounds = sounds + 1 end
RaidWarningUtil = { AddMessage = function() error("death messages mutated the shared Blizzard warning pool") end }
RaidNotice_AddMessage = function() error("death messages used the shared Blizzard warning frame") end
suite.CreateFrame = function(kind)
    assert(kind == "MessageFrame", "screen death alerts require an owned native message frame")
    local frame = keyWidget()
    function frame:AddMessage(message, r, g, b)
        assert(r == 1 and g == .28 and b == 0, "death warning color changed")
        screenNotices[#screenNotices + 1] = message
    end
    return frame
end
death.config.chat, death.config.screen, death.config.sound = false, true, true
unitDead = {}; death:Refresh()
deathNotices = #notices
unitDead.player, unitDead.party1 = true, true
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "player")
death.context.events.UNIT_HEALTH(death, "UNIT_HEALTH", "party1")
assert(#notices == deathNotices and #screenNotices == 2 and sounds == 1,
    "screen/sound choices ignored or simultaneous sounds overlapped")
-- A player who died keeps watching the wipe (suite_group_death_alert_contract).
unitDead.player, inCombat = nil, false
death.context.events.PLAYER_REGEN_ENABLED(death, "PLAYER_REGEN_ENABLED")
assert(not death.dead and not death.context.events.UNIT_HEALTH and not death.context.events.UNIT_FLAGS,
    "death alert kept watching health outside combat")
death:Disable()
print("Suite group finder, keystone, bloodlust, Delve, reset and death lifecycle passed")
