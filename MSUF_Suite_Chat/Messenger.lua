local _, P = ...
local NS, S = P.NS, P.Suite
local D = P.Messenger
local W = D.Window
-- The whisper messenger (module chatMessenger, opt-in): whispers of
-- characters and Battle.net friends in a Suite window, one tab per
-- conversation, with a reply line.
-- Blizzard's chat stays the delivery: nothing here filters, hides or
-- reroutes a native whisper, hooks a chat frame or writes ChatTypeInfo or a
-- chat edit box. The messenger only listens to the whisper events, after
-- every argument passed the secret checks; a whisper with a restricted body,
-- sender, line ID or account ID, or a censored line, stays Blizzard's alone
-- and is only counted. Replies go out through C_ChatInfo.SendChatMessage
-- (as the damage meter report) or C_BattleNet.SendWhisper, refused while Blizzard's
-- chat messaging lockdown applies; the event Blizzard sends for the reply
-- adds it to the tab, so a reply never shows twice.
local M = {}
local IN_COMBAT = { inCombat = true }
local PublicText, Finite, Public = S.PublicText, S.Finite, S.Public
local MAX_BYTES = 255
local NAME_KEY, CLOSE_KEY = "chat-messenger-new", "chat-messenger-close-all"
-- event -> whether it reports the player's own whisper
local CHARACTER_EVENTS = { CHAT_MSG_WHISPER = false, CHAT_MSG_WHISPER_INFORM = true }
local BNET_EVENTS = { CHAT_MSG_BN_WHISPER = false, CHAT_MSG_BN_WHISPER_INFORM = true }

-- A line the messenger may show: a readable native line ID whose line the
-- client does not hide behind its profanity filter.
local function Readable(lineID)
    if not Finite(lineID) or lineID <= 0 or lineID % 1 ~= 0 then return false end
    local censored = C_ChatInfo.IsChatLineCensored(lineID)
    return Public(censored) and censored == false
end

-- A restricted incoming whisper is counted only; Blizzard's chat shows it.
local function NativeOnly(outgoing)
    if outgoing then return end
    D.nativeOnly = D.nativeOnly + 1
    W.Refresh()
end

-- A new incoming whisper may open the window; in combat (when the window
-- hides then) it opens once combat ends.
local function Arrived(self, tab)
    if not self.config.openOnWhisper or W.IsShown() then return end
    if self.config.hideInCombat and NS.InCombat() then
        W.OpenAfterCombat()
        return
    end
    D.Select(tab)
    W.Show()
end

local function Delivered(self, tab, body, outgoing, lineID)
    if not tab then return end
    D.Seed(tab)
    local seen = W.IsShown() and D.selected == tab
    if D.Receive(tab, body, outgoing, lineID, seen) and not outgoing then Arrived(self, tab) end
    W.Refresh()
end

-- CHAT_MSG_WHISPER(_INFORM): text, the other character, ..., the line ID
-- (11th) and the sender's GUID (12th; read for incoming whispers only).
local function CharacterWhisper(self, event, text, sender, _, _, _, _, _, _, _, _, lineID, guid)
    local outgoing = CHARACTER_EVENTS[event]
    local body, name = PublicText(text), D.CharacterName(sender)
    if not (body and name and Readable(lineID)) then return NativeOnly(outgoing) end
    Delivered(self, D.CharacterTab(name, not outgoing and guid or nil, not outgoing), body, outgoing, lineID)
end

-- CHAT_MSG_BN_WHISPER(_INFORM): text, the friend's protected name, ..., the
-- line ID (11th) and the friend's session account ID (13th).
local function BattleNetWhisper(self, event, text, sender, _, _, _, _, _, _, _, _, lineID, _, accountID)
    local outgoing = BNET_EVENTS[event]
    local body = PublicText(text)
    if not (body and Finite(accountID) and Readable(lineID)) then return NativeOnly(outgoing) end
    Delivered(self, D.BattleNetTab(accountID, sender), body, outgoing, lineID)
end

------------------------------------------------------------------ replies
local function Outgoing(text)
    local body = PublicText(text)
    body = body and body:match("^%s*(.-)%s*$")
    if not body or body == "" or #body > MAX_BYTES then return nil end
    return body
end

-- Sends a reply to the selected conversation. Returns true once it went
-- out; the reply line keeps refused text.
function M:Send(text)
    local tab, body = D.selected, Outgoing(text)
    if not (self.active and tab and body) then return false end
    if NS.ChatLocked() then
        S.Print(S.Text("Chat messages are blocked here right now; your reply was not sent."))
        return false
    end
    if tab.kind == "bnet" then
        local sent = C_BattleNet.SendWhisper(tab.accountID, body)
        return S.Public(sent) and sent == true
    else
        C_ChatInfo.SendChatMessage(body, "WHISPER", nil, tab.name)
    end
    return true
end

------------------------------------------------------------------ actions
local function SelectTab(tab)
    D.Select(tab)
    D.Seed(tab)
    D.MarkRead(tab)
    W.Refresh()
    W.FocusInput()
end

local function CloseTab(tab)
    D.Close(tab)
    D.Seed(D.selected)
    D.MarkRead(D.selected)
    W.Refresh()
end

local function StartConversation(self, typed)
    if not self.active then return end
    local name = D.CharacterName(PublicText(typed) and typed:match("^%s*(.-)%s*$"))
    if not name then
        S.Print(S.Text("Enter a character name, optionally with its realm (Name-Realm)."))
        return
    end
    local tab = D.CharacterTab(name)
    if not tab then return end
    D.Select(tab)
    W.Show()
    W.FocusInput()
end

local function AskName(self)
    if not self.active then return end
    S.AskText(NAME_KEY, {
        text = S.Text("Whisper which character? Name or Name-Realm"), maxLetters = 64,
        callback = function(typed) StartConversation(self, typed) end,
    })
end

local function CloseAll(self)
    if not self.active or #D.tabs == 0 then return end
    S.Confirm(CLOSE_KEY, {
        text = S.Text("Close every conversation? Blizzard chat keeps all whispers."),
        callback = function()
            if not self.active then return end
            D.CloseAll()
            W.Refresh()
        end,
    })
end

------------------------------------------------------------------ combat
local function CombatStarted(self, event)
    if NS.InCombat(event) then W.CombatStarted(self.config.hideInCombat) end
end

local function CombatEnded(_, event)
    if not NS.InCombat(event) then W.CombatEnded() end
end

------------------------------------------------------------------ lifecycle
local function Listen(self, events, enabled, callback)
    for event in pairs(events) do
        if enabled then
            self.context:Event(event, callback, IN_COMBAT)
        else
            self.context:RemoveEvent(event)
        end
    end
end

function M:Enable()
    W.SetHandlers({
        select = SelectTab, close = CloseTab,
        send = function(text) return M:Send(text) end,
        ask = function() AskName(M) end,
        closeAll = function() CloseAll(M) end,
    })
    self.context:Event("PLAYER_REGEN_DISABLED", CombatStarted, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", CombatEnded, IN_COMBAT)
    self:Refresh()
end

function M:Refresh()
    D.Configure(self.config)
    Listen(self, CHARACTER_EVENTS, self.config.character, CharacterWhisper)
    Listen(self, BNET_EVENTS, self.config.battleNet, BattleNetWhisper)
    W.Apply(self.config)
end

-- Off keeps nothing: the window, its questions and every conversation go.
function M:Disable()
    S.HideQuestion(NAME_KEY)
    S.HideQuestion(CLOSE_KEY)
    W.Release()
    D.Reset()
end

-- The options page's "Open whisper messenger" button.
function M:Toggle()
    if self.active then W.Toggle() end
end

S.Install("chatMessenger", M)
