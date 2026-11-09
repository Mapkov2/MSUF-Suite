-- Per-category tab capture and a distinct opt-in whisper archive.
local repo = arg[1] or "."
local root = repo .. "/MSUF_Suite_Chat/"
local Secrets = dofile(repo .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
local IsSecret = Secrets.IsSecret
local secret = Secrets.New("number")
local stop = Secrets.Watch({ root .. "History.lua", root .. "Copy.lua" }, { strict = true })
local function Finite(value)
    return not IsSecret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function PublicText(value)
    return not IsSecret(value) and type(value) == "string" and value ~= "" and value or nil
end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
ChatTypeInfo = {
    SYSTEM = { id = 1 }, PARTY = { id = 2 }, GUILD = { id = 3 }, CHANNEL4 = { id = 4 },
    WHISPER = { id = 5 }, WHISPER_INFORM = { id = 6 }, BN_WHISPER = { id = 7 }, DND = { id = 8 },
}
local config = { saveHistory = true, historyLines = 20, historyConversations = true }
local suite = { Text = function(s) return s end, IsSecret = IsSecret, Finite = Finite, PublicText = PublicText }
local module = { config = config }
local C = { M = module }
local P = { Chat = C, Suite = suite, NS = {} }
for _, name in ipairs({ "Copy.lua", "History.lua", "HistoryBrowser.lua" }) do
    assert(loadfile(root .. name))("MSUF_Suite_Chat", P)
end

MSUFSuiteChatHistory = {
    tabs = { ["ChatFrame1:General"] = { lines = { { text = "legacy row" } }, count = 1, next = 2, limit = 20 } },
    clock = 1,
}
C.CompileHistory(config)
local ring = C.HistoryRing("ChatFrame1:General")
assert(ring.count == 1 and ring.lines[1].text == "legacy row", "legacy tab history was lost")
C.HistoryStore(ring, "readable whisper", .5, .6, .7, 5)
assert(ring.count == 2, "the default excluded an existing kind of tab message")

config.historyWhispers, config.historyPublic = false, false
C.CompileHistory(config)
C.HistoryStore(ring, "uncategorized secret", 1, 1, 1, secret)
assert(ring.count == 2, "a restricted type fell through into the allowed system category")
config.historySystem = false
C.CompileHistory(config)
for _, id in ipairs({ 1, 4, 5, 6, 7, 8, secret }) do C.HistoryStore(ring, "excluded", 1, 1, 1, id) end
C.HistoryStore(ring, "untyped system message", 1, 1, 1)
C.HistoryWhisper("|Hplayer:Ally:9:WHISPER:Ally|h[Ally]|h: blocked", 5)
assert(ring.count == 2 and #C.WhisperSnapshot() == 0, "history filtering did not protect an opted-out category")
C.HistoryStore(ring, "party line", 1, 1, 1, 2)
C.HistoryStore(ring, "guild line", 1, 1, 1, 3)
assert(ring.count == 4 and ring.lines[3].text == "party line" and ring.lines[4].text == "guild line",
    "selected history categories were not saved")

config.historyWhispers = true
C.CompileHistory(config)
local incoming = "|Hplayer:Ally Surname-Realm:10:WHISPER:Ally Surname-Realm|h[Ally Surname]|h: Hello"
local outgoing = "To |Hplayer:Ally Surname-Realm:11:WHISPER:Ally Surname-Realm|h[Ally Surname]|h: Hi"
C.HistoryWhisper(incoming, 5)
C.HistoryWhisper(incoming, 5) -- Native delivery in another window.
C.HistoryWhisper(outgoing, 6)
C.HistoryWhisper(incoming, secret)
C.HistoryWhisper(incoming:gsub(":10:", ":0:"), 5)
C.HistoryWhisper("|HBNplayer:|K2|k:12|h[|K2|k]|h: Hidden sender", 7)
local contacts = C.WhisperSnapshot()
assert(#contacts == 1 and contacts[1].peer == "Ally Surname-Realm" and #contacts[1].lines == 2,
    "incoming and outgoing whispers did not group once under the full character name")
assert(contacts[1].lines[1] == "To [Ally Surname]: Hi" and contacts[1].lines[2] == "[Ally Surname]: Hello",
    "archive display lost the visible message or chronological direction")
assert(ring.count == 4, "temporary conversations entered the native replay ring")

local opened, reopened
suite.ToolListWindow = {
    Open = function(owner, spec) opened = { owner = owner, spec = spec } return opened end,
    Refresh = function() reopened = true end,
    Close = function() end,
}
C.HideCopyDialog = function() end
local transcript
C.ShowChatTranscript = function(text) transcript = text end
module:OpenHistory(true)
local spec, owner = opened.spec, opened.owner
assert(spec.currentTab() == "whispers", "the archive shortcut did not open the conversation tab")
local peers = spec.rows()
assert(spec.filter(owner, peers[1], "surname"), "conversation search ignored its character name")
local window = { search = { SetText = function() end }, Refresh = function() end }
spec.actions[2].run(owner, peers[1], window)
assert(#spec.rows() == 2, "selecting a conversation did not show both messages")
spec.actions[3].run(owner)
assert(transcript == "[Ally Surname]: Hello\nTo [Ally Surname]: Hi",
    "copying a conversation did not give the complete transcript oldest first")
module:ClearHistory()
C.HistoryWhisper(incoming, 5)
assert(reopened and ring.count == 0 and #C.WhisperSnapshot() == 0,
    "clearing the archive kept visible history or repopulated an already-cleared message")

config.historyConversations = false
C.CompileHistory(config)
C.HistoryWhisper(incoming:gsub(":10:", ":13:"), 5)
assert(#C.WhisperSnapshot() == 0, "disabled conversation storage kept capturing")
C.ShowChatLine(Secrets.New("string"))
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("PASS chat history categories, whisper archive, and strict secret guards")
