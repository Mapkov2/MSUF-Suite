-- Whisper messenger: tabs and routing for characters and Battle.net
-- friends, direct replies, restricted and censored whispers left to
-- Blizzard's chat, bounded tabs and lines, the existing whisper archive as
-- the only history (deduplicated by native line ID), combat hide/restore
-- with unread, and the repository rules for the new files.
local root = arg and arg[1] or "."
local chatRoot = root .. "/MSUF_Suite_Chat/"
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

------------------------------------------------------------------ secrets
-- A stand-in for the client's secret values: any comparison, arithmetic,
-- concatenation, length, call or index raises.
local secrets = setmetatable({}, { __mode = "k" })
local function Refuse() error("secret value was inspected", 2) end
local SECRET_META = { __index = Refuse, __newindex = Refuse, __concat = Refuse, __len = Refuse, __call = Refuse,
    __lt = Refuse, __le = Refuse, __add = Refuse, __sub = Refuse, __mod = Refuse, __unm = Refuse,
    __tostring = function() return "<secret>" end }
local function Secret()
    local value = setmetatable({}, SECRET_META)
    secrets[value] = true
    return value
end
local function IsSecret(value) return type(value) == "table" and secrets[value] == true end
local function Finite(value)
    return not IsSecret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function PublicText(value)
    return not IsSecret(value) and type(value) == "string" and value ~= "" and value or nil
end

------------------------------------------------------------------ client
date = os.date
GetNormalizedRealmName = function() return "Home" end
GetPlayerInfoByGUID = function(guid) return nil, guid == "Player-1-AB" and "MAGE" or nil end
ChatTypeInfo = { WHISPER = { id = 5 }, WHISPER_INFORM = { id = 6 }, BN_WHISPER = { id = 7 } }
local censored, sent, bnetSent, printed = {}, {}, {}, {}
C_ChatInfo = {
    IsChatLineCensored = function(id) return censored[id] == true end,
    SendChatMessage = function(text, kind, language, target) sent[#sent + 1] = { text, kind, language, target } end,
}
C_BattleNet = { SendWhisper = function(id, text)
    bnetSent[#bnetSent + 1] = { id, text }
    return true
end }

local combat, locked = false, false
local NS = {
    InCombat = function(event)
        if event == "PLAYER_REGEN_DISABLED" then return true end
        if event == "PLAYER_REGEN_ENABLED" then return false end
        return combat
    end,
    ChatLocked = function() return locked end,
}
local installed, asked, confirmed, hidden = nil, nil, nil, {}
local suite = {
    Text = function(text) return text end, IsSecret = IsSecret, Public = function(v) return not IsSecret(v) end,
    Finite = Finite, PublicText = PublicText,
    Print = function(text) printed[#printed + 1] = text end,
    AskText = function(key, data) asked = { key = key, data = data } end,
    Confirm = function(key, data) confirmed = { key = key, data = data } end,
    HideQuestion = function(key) hidden[#hidden + 1] = key end,
    Install = function(id, module) eq(id, "chatMessenger", "installed module id") installed = module end,
}
local historyConfig = { saveHistory = true, historyLines = 40, historyConversations = true }
local C = { M = { config = historyConfig } }
C.ClassHex = function(class) return class == "MAGE" and "3fc7eb" or nil end
local P = { Chat = C, Suite = suite, NS = NS }
for _, name in ipairs({ "Copy.lua", "History.lua", "MessengerData.lua" }) do
    assert(loadfile(chatRoot .. name))("MSUF_Suite_Chat", P)
end
local D = assert(P.Messenger, "MessengerData.lua did not publish the messenger state")

-- The window is a Suite frame tree; its contract here is visibility.
local shown, calls = false, { show = 0, afterCombat = 0, combatHide = 0, restore = 0 }
local W = {
    SetHandlers = function(handlers) calls.handlers = handlers end,
    Apply = function() end, Refresh = function() end, Release = function() shown = false end,
    IsShown = function() return shown end, FocusInput = function() end, UpdateLauncher = function() end,
    Show = function()
        shown, calls.show = true, calls.show + 1
        D.Seed(D.selected)
        D.MarkRead(D.selected)
    end,
    OpenAfterCombat = function() calls.afterCombat = calls.afterCombat + 1 end,
    CombatStarted = function(hide)
        if hide and shown then shown, calls.combatHide = false, calls.combatHide + 1 end
    end,
    CombatEnded = function() calls.restore = calls.restore + 1 end,
}
D.Window = W
D.Changed = W.Refresh
assert(loadfile(chatRoot .. "Messenger.lua"))("MSUF_Suite_Chat", P)
local M = assert(installed, "Messenger.lua did not install chatMessenger")

local events = {}
M.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
M.config = { character = true, battleNet = true, openOnWhisper = false, hideInCombat = true, launcher = true,
    showArchive = true, maxTabs = 3, maxLines = 20, fontSize = 12, width = 480, height = 360 }
M.active = true
M:Enable()

local function Fire(event, text, sender, lineID, guid, accountID)
    local callback = events[event]
    if not callback then return false end
    callback(M, event, text, sender, "", "", "", "", 0, 0, "", 0, lineID, guid, accountID)
    return true
end

------------------------------------------------------------------ routing
assert(Fire("CHAT_MSG_WHISPER", "hello there", "Ally-Home", 100, "Player-1-AB"), "no character whisper listener")
eq(#D.tabs, 1, "incoming whisper tab")
local ally = D.tabs[1]
eq(ally.key, "c:ally-home", "character tab key")
eq(ally.label, "Ally", "own-realm label")
eq(ally.unread, 1, "unread while hidden")
assert(ally.lines[1].text:find("hello there", 1, true) and ally.lines[1].text:find("3fc7eb", 1, true),
    "line lost its body or class color")
Fire("CHAT_MSG_WHISPER", "hello there", "Ally-Home", 100, "Player-1-AB")
eq(#ally.lines, 1, "the same native line was added twice")
Fire("CHAT_MSG_WHISPER_INFORM", "hi", "ally-home", 101, "Player-OWN")
eq(#D.tabs, 1, "outgoing whisper opened a second tab for the same character")
eq(ally.unread, 0, "replying did not mark the conversation read")
assert(ally.lines[2].text:find("You", 1, true), "own line is not marked")
Fire("CHAT_MSG_WHISPER", "from afar", "Visitor-Other", 102)
eq(D.byKey["c:visitor-other"].label, "Visitor-Other", "foreign realm stays in the label")

-- Restricted and censored whispers stay native and are only counted.
local before = #D.tabs
Fire("CHAT_MSG_WHISPER", Secret(), "Ally-Home", 103)
Fire("CHAT_MSG_WHISPER", "text", Secret(), 104)
Fire("CHAT_MSG_WHISPER", "text", "Ally-Home", Secret())
censored[105] = true
Fire("CHAT_MSG_WHISPER", "bad word", "Ally-Home", 105)
Fire("CHAT_MSG_WHISPER_INFORM", Secret(), "Ally-Home", 106)
eq(#D.tabs, before, "a restricted whisper opened a tab")
eq(#ally.lines, 2, "a restricted or censored whisper reached the messenger")
eq(D.nativeOnly, 4, "restricted incoming whispers were not counted (own lines are not)")

-- Battle.net: keyed by this session's account ID; the protected name is only drawn.
assert(Fire("CHAT_MSG_BN_WHISPER", "bnet hi", "|Kq7|k", 200, nil, 42), "no Battle.net listener")
local friend = D.byKey["b:42"]
assert(friend and friend.kind == "bnet" and friend.label == "|Kq7|k", "Battle.net tab")
Fire("CHAT_MSG_BN_WHISPER", "lost", "|Kq7|k", 201, nil, Secret())
Fire("CHAT_MSG_BN_WHISPER", "lost", Secret(), 202, nil, 42)
eq(#friend.lines, 2, "a readable Battle.net body with a protected name label was dropped")
eq(friend.label, "|Kq7|k", "a restricted name replaced the label")

------------------------------------------------------------------ limits
eq(#D.tabs, 3, "tab count before the limit")
D.MarkRead(D.byKey["c:visitor-other"])
D.Select(ally)
D.Select(friend)
Fire("CHAT_MSG_WHISPER", "fourth", "Newcomer-Home", 300)
eq(#D.tabs, 3, "tab limit not enforced")
assert(not D.byKey["c:visitor-other"], "the least recent read conversation was not the one closed")
assert(D.byKey["c:newcomer-home"] and D.byKey["b:42"], "the new or the selected tab was closed")
for index = 1, 25 do Fire("CHAT_MSG_WHISPER", "line " .. index, "Newcomer-Home", 400 + index) end
local newcomer = D.byKey["c:newcomer-home"]
eq(#newcomer.lines, 20, "line limit not enforced")
local ids = 0
for _ in pairs(newcomer.ids) do ids = ids + 1 end
eq(ids, 20, "trimmed lines kept their dedupe IDs")

------------------------------------------------------------------ replies
D.Select(ally)
assert(M:Send("  reply text  "), "character reply refused")
eq(sent[1][1], "reply text", "reply body")
eq(sent[1][2], "WHISPER", "reply chat type")
eq(sent[1][4], "Ally-Home", "reply target")
eq(#ally.lines, 2, "a reply was shown before Blizzard confirmed it")
locked = true
assert(not M:Send("blocked"), "reply sent during chat lockdown")
eq(#sent, 1, "lockdown reply reached the client")
locked = false
assert(not M:Send(Secret()) and not M:Send("   ") and not M:Send(("x"):rep(256)), "invalid reply accepted")
D.Select(friend)
assert(M:Send("bnet reply"), "Battle.net reply refused")
eq(bnetSent[1][1], 42, "Battle.net reply target")
eq(bnetSent[1][2], "bnet reply", "Battle.net reply body")
local bnetSend = C_BattleNet.SendWhisper
C_BattleNet.SendWhisper = function() return false end
assert(not M:Send("refused"), "Battle.net reply was cleared when the client refused it")
C_BattleNet.SendWhisper = bnetSend

-- New conversation through the shared input question.
calls.handlers.ask()
eq(asked.key, "chat-messenger-new", "new whisper question")
asked.data.callback("has space")
assert(not D.byKey["c:has space-home"], "an invalid name opened a tab")
asked.data.callback(" Typed ")
assert(D.byKey["c:typed-home"] and D.selected == D.byKey["c:typed-home"], "typed name did not open and select")
calls.handlers.closeAll()
eq(confirmed.key, "chat-messenger-close-all", "close all asks first")
assert(#D.tabs > 0, "close all ran before confirmation")
confirmed.data.callback()
eq(#D.tabs, 0, "confirmed close all kept tabs")

------------------------------------------------------------------ combat
M.config.openOnWhisper = true
shown = true
events.PLAYER_REGEN_DISABLED(M, "PLAYER_REGEN_DISABLED")
eq(calls.combatHide, 1, "combat start did not hide the window")
combat = true
Fire("CHAT_MSG_WHISPER", "in combat", "Fighter-Home", 500)
eq(calls.afterCombat, 1, "a combat whisper did not wait for combat to end")
eq(D.byKey["c:fighter-home"].unread, 1, "a combat whisper was not counted unread")
eq(calls.show, 1, "the window opened in combat")
combat = false
events.PLAYER_REGEN_ENABLED(M, "PLAYER_REGEN_ENABLED")
eq(calls.restore, 1, "combat end did not restore")
shown = false
Fire("CHAT_MSG_WHISPER", "after combat", "Fighter-Home", 501)
eq(calls.show, 2, "open on whisper did not open the window")
eq(D.byKey["c:fighter-home"].unread, 0, "the opened conversation stayed unread")

------------------------------------------------------------------ archive
-- The existing whisper archive is the only history; the live line with the
-- same native line ID replaces the archived one.
D.Reset()
shown = false
M.config.openOnWhisper = false
C.CompileHistory(historyConfig)
C.HistoryWhisper("|Hplayer:Old-Home:900:WHISPER:Old-Home|h[Old]|h: earlier", 5)
C.HistoryWhisper("|Hplayer:Old-Home:901:WHISPER:Old-Home|h[Old]|h: current", 5)
C.HistoryWhisper("|Hplayer:Other-Home:902:WHISPER:Other-Home|h[Other]|h: elsewhere", 5)
Fire("CHAT_MSG_WHISPER", "current", "Old-Home", 901)
local old = D.byKey["c:old-home"]
eq(#old.lines, 2, "archive and live line were not merged by line ID")
assert(old.lines[1].archived and old.lines[1].text:find("earlier", 1, true), "older archived line missing or not first")
assert(not old.lines[2].archived and old.lines[2].text:find("current", 1, true), "live line did not replace the archived one")
eq(old.unread, 1, "the first live delivery of an archived line was not counted")
D.ArchiveCleared()
eq(#old.lines, 1, "clearing the archive kept archived lines in the messenger")
D.Reset()
D.RestoreRecent(4)
eq(#D.tabs, 2, "recent archived conversations were not restored")
M.config.showArchive = false
M:Refresh()
D.Reset()
D.RestoreRecent(4)
eq(#D.tabs, 0, "archive restore ignored the setting")
local saved = _G.MSUFSuiteChatHistory
for key in pairs(saved) do
    assert(key == "tabs" or key == "clock" or key == "whispers", "the messenger added saved data: " .. tostring(key))
end

------------------------------------------------------------------ lifecycle
M.config.battleNet = false
M:Refresh()
eq(events.CHAT_MSG_BN_WHISPER, nil, "Battle.net listener kept after switching it off")
Fire("CHAT_MSG_WHISPER", "keep", "Ally-Home", 600)
M:Disable()
eq(#D.tabs, 0, "disable kept conversations")
eq(#hidden, 2, "disable left a question open")

------------------------------------------------------------------ repository rules
do
    D.Configure({ maxTabs = 3, showArchive = false })
    local first = D.CharacterTab("Pinned-Home")
    local selected = D.CharacterTab("Selected-Home")
    D.CharacterTab("Older-Home")
    D.Select(selected)
    D.TogglePin(first)
    assert(D.tabs[1] == first and first.pinned, "a pinned tab did not move to the front")
    D.CharacterTab("New-Home")
    assert(D.byKey[first.key] == first and not D.byKey["c:older-home"], "eviction closed the pinned tab")
    D.TogglePin(first)
    assert(not first.pinned, "unpinning did not clear the tab state")
    D.TogglePin(first)
    D.TogglePin(D.byKey["c:new-home"])
    local new = D.CharacterTab("Next-Home")
    assert(new and D.selected and D.byKey[first.key] == first and D.byKey["c:new-home"]
        and not D.byKey[selected.key], "pinned tabs prevented a new conversation")
    D.Reset()
end

local FORBIDDEN = { "ChatTypeInfo", "StaticPopupDialogs", "hooksecurefunc", "HookScript", "pcall", "OnUpdate",
    "COMBAT_LOG_EVENT", "CombatLogGetCurrentEventInfo", "SetAttribute", "ChatEdit_", "ChatFrameUtil",
    "EditBox:SetText", "FCF_", "SlashCmdList", "UISpecialFrames", "AddMessageEventFilter" }
for _, name in ipairs({ "MessengerData.lua", "MessengerWindow.lua", "Messenger.lua" }) do
    local file = assert(io.open(chatRoot .. name, "rb"))
    local source = file:read("*a")
    file:close()
    local code = source:gsub("%-%-[^\n]*", "")
    for _, word in ipairs(FORBIDDEN) do
        assert(not code:find(word, 1, true), name .. " uses " .. word)
    end
    local lines, start, startName = 0, nil, nil
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        lines = lines + 1
        assert(#line <= 120 or line:find("^%s*%-%-"), name .. ":" .. lines .. " is longer than 120 characters")
        if line:find("^local function ") or line:find("^function ") then start, startName = lines, line end
        if start and line:find("^end") then
            assert(lines - start + 1 <= 72, name .. ": " .. startName .. " is longer than 72 lines")
            start = nil
        end
    end
    assert(lines <= 810, name .. " is longer than 810 lines")
end
local toc = assert(io.open(chatRoot .. "MSUF_Suite_Chat_Mainline.toc", "rb"))
local tocText = toc:read("*a"):gsub("\r", "")
toc:close()
local data = assert(tocText:find("\nMessengerData.lua\n", 1, true), "MessengerData.lua is not in the TOC")
local window = assert(tocText:find("\nMessengerWindow.lua\n", 1, true), "MessengerWindow.lua is not in the TOC")
local module = assert(tocText:find("\nMessenger.lua\n", 1, true), "Messenger.lua is not in the TOC")
local history = assert(tocText:find("\nHistory.lua\n", 1, true), "History.lua left the TOC")
assert(history < data and data < window and window < module, "messenger files load out of order")
local catalog = assert(io.open(root .. "/MSUF_Suite/Core/Catalog/Chat.lua", "rb"))
local catalogText = catalog:read("*a")
catalog:close()
assert(catalogText:find('B.Module("chatMessenger"', 1, true) and catalogText:find("optIn = true, defaultEnabled = false", 1, true),
    "the messenger is not an opt-in catalog module")
print("PASS chat messenger routing, replies, restricted whispers, limits, archive dedupe, combat and rules")
