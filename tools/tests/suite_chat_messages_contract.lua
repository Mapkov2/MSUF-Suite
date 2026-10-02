-- Chat message tools: formatting through the native transform, saved
-- history per character, the combat log left alone, the msufurl link
-- handler and the idle fade in combat. The client model follows Blizzard's
-- source on Retail and Forever: ChatFrame2 is the combat log (COMBATLOG),
-- the voice transcription window has its own event handler, chat frames
-- hold 128 lines and BackFillMessage adds behind the oldest one.
local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local combat = false
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    RootDB = {} }
local S = {
    Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end,
    Text = function(v) return v end,
    ClassRGB = function() return 1, .5, 0 end,
    Dispatch = function(callback, ...) return callback(...) end,
}
S.PublicText = function(v) return v ~= "secret" and type(v) == "string" and v ~= "" and v or nil end
S.Queue = function() error("chat message tools queued the module for combat end") end
local config = Support.CatalogDefaults(root, "chat")
config.saveHistory, config.historyLines, config.linkURLs, config.colorMentionNames = true, 20, true, true
local events = {}
local context = { removed = {}, combat = {} }
function context:Event(event, callback, allowCombat) events[event], self.combat[event] = callback, allowCombat end
function context:RemoveEvent(event) events[event], self.combat[event] = nil, nil end
local copied
local C
local function LoadChat(saved)
    MSUFSuiteChatHistory = saved
    local handlers = {}
    LinkUtil = { RegisterLinkHandler = function(kind, handler)
        assert(not handlers[kind], "a link handler was registered twice in one session")
        handlers[kind] = handler
    end }
    local private = { NS = NS, Suite = S }
    local toc = Support.TocFiles(root, "MSUF_Suite_Chat")
    local position = {}
    for i, file in ipairs(toc) do position[file] = i end
    local files = { "Shared.lua", "History.lua", "Fade.lua", "Messages.lua" }
    for i = 2, #files do
        assert(position[files[i - 1]] < position[files[i]], files[i] .. " loads before " .. files[i - 1])
    end
    for _, file in ipairs(files) do assert(loadfile(root .. "/MSUF_Suite_Chat/" .. file))("MSUF_Suite_Chat", private) end
    local chat = private.Chat
    chat.ShowURL = function(url) copied = url end
    local module = chat.M
    module.config, module.active, module.context = config, true, context
    return chat, module, handlers
end
-- Blizzard's global strings and the chat constants are read once per compile.
local strings = { CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: ", CHAT_PARTY_GET = "|Hchannel:PARTY|h[Party]|h %s: ",
    CHAT_RAID_GET = "[Raid] %s: ", CHAT_RAID_WARNING_GET = "[Raid Warning] %s: ",
    CHAT_INSTANCE_CHAT_GET = "[Instance] %s: ", CHAT_OFFICER_GET = "[Officer] %s: " }
local stringReads = 0
setmetatable(_G, { __index = function(_, key)
    if strings[key] then
        stringReads = stringReads + 1
        return strings[key]
    end
end })
UnitName = function(unit) return unit == "party1" and "Mapko" or "Other" end
UnitClass = function() return "Mage", "MAGE" end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 1 end
GetChatWindowInfo = function(id) return id == 1 and "General" or "Other" end
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
CHAT_FRAME_FADE_OUT_TIME = 2.0
local nativeStamp, cvarReads = "none", 0
C_CVar = { GetCVar = function(key)
    assert(key == "showTimestamps")
    cvarReads = cvarReads + 1
    return nativeStamp
end }
local clock = 1000
time = function() return clock end
date = function(format)
    if format:find("%Q", 1, true) or format:sub(-1) == "%" then error("invalid date format") end
    return format == "%H:%M " and "12:34 " or "[12:34]"
end
TimeUtil = { BetterDate = function(format) return date(format) end }
local now = 0
GetTime = function() return now end
local timers = {}
C_Timer = { NewTimer = function(delay, callback)
    local timer = { callback = callback, delay = delay, due = now + delay }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local function RunTimers(untilTime)
    now = untilTime
    local ran = true
    while ran do
        ran = false
        for i, timer in ipairs(timers) do
            if not timer.cancelled and timer.due <= now then
                table.remove(timers, i)
                timer.callback()
                ran = true
                break
            end
        end
    end
end
local securePostHooks, fcfHooks = {}, {}
hooksecurefunc = function(frame, method, callback)
    if type(frame) == "string" then
        assert(frame == "FCF_FadeInChatFrame" or frame == "FCF_FadeOutChatFrame", "unexpected global hook " .. frame)
        fcfHooks[frame] = method
        return
    end
    eq(method, "AddMessage", "only the native message post-hook")
    frame.securePostHooks = frame.securePostHooks or {}
    frame.securePostHooks[#frame.securePostHooks + 1] = callback
    securePostHooks[frame] = true
end

local function Frame(id, name)
    local frame = { lines = {}, payloads = {}, scripts = {}, alpha = 1, id = id, name = name or ("ChatFrame" .. id) }
    function frame:GetName() return self.name end
    function frame:GetID() return self.id end
    function frame:GetMaxLines() return 128 end
    function frame:GetNumMessages() return #self.lines end
    function frame:AddMessage(text, ...)
        self.lines[#self.lines + 1] = text
        self.payloads[#self.lines] = { n = select("#", ...), ... }
        for _, callback in ipairs(self.securePostHooks or {}) do callback(self, text, ...) end
    end
    -- Blizzard's BackFillMessage pushes behind the oldest line, never past MaxLines.
    function frame:BackFillMessage(text, ...)
        if #self.lines >= 128 then return end
        table.insert(self.lines, 1, text)
        table.insert(self.payloads, 1, { n = select("#", ...), ... })
        self.backfilled = (self.backfilled or 0) + 1
    end
    function frame:TransformMessages(predicate, transform)
        self.transforms = (self.transforms or 0) + 1
        for index, text in ipairs(self.lines) do
            local payload = self.payloads[index]
            if predicate(text, unpack(payload, 1, payload.n)) then
                local values = { transform(text, unpack(payload, 1, payload.n)) }
                self.lines[index] = values[1]
                for i = 1, payload.n do payload[i] = values[i + 1] end
            end
        end
    end
    -- These windows never wrap their 128 lines, so storage order is the
    -- display order and the newest line (index 1, the front) is stored last.
    frame.historyBuffer = { CalculateElementIndex = function(_, index) return #frame.lines - index + 1 end }
    function frame:HookScript(script) error("chat message tools hooked the " .. script .. " script") end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    return frame
end
ChatFrame2 = Frame(2)

local saved
local M, handlers
C, M, handlers = LoadChat(nil)
assert(handlers.msufurl, "URL clicks did not register Blizzard's link handler")
C.MessagesRefresh(M)
assert(events.GROUP_ROSTER_UPDATE and not events.CHAT_MSG_WHISPER,
    "message events did not follow the enabled tools")
-- Chat is a geometry module: these text and sound listeners must also run
-- in combat (the context's allowCombat).
assert(context.combat.GROUP_ROSTER_UPDATE == true, "the group name colors wait for the end of combat")
do
    local kit = config.whisperSoundKit
    config.whisperSoundKit = 12867
    C.MessagesRefresh(M)
    assert(events.CHAT_MSG_WHISPER and context.combat.CHAT_MSG_WHISPER == true,
        "the whisper sound waits for the end of combat")
    config.whisperSoundKit = kit
    C.MessagesRefresh(M)
end
C.MessageRoster()
-- The rendered line of one message: a window's message hook rewrites what it
-- is handed through the window's own TransformMessages, so the window's
-- newest stored line is the result (a temporary window keeps no history).
local formatWindow
local function Rendered(text)
    if not formatWindow then
        formatWindow = Frame(9)
        formatWindow.isTemporary = true
        C.ApplyMessages(M, formatWindow)
    end
    formatWindow:AddMessage(text)
    return formatWindow.lines[#formatWindow.lines]
end
local formatted = Rendered("Mapko https://example.org/Mapko. |Hspell:123|h[Mapko]|h")
assert(formatted:find("|cffff8000Mapko|r", 1, true), "public mention colored")
assert(formatted:find("|Hmsufurl:https://example.org/Mapko|h", 1, true), "URL preserved as copy link")
assert(formatted:find("|Hspell:123|h[Mapko]|h", 1, true), "native hyperlink not changed")
eq(Rendered("secret"), "secret", "a restricted message was rewritten")
-- SetItemRef asks LinkUtil first and stops when the handler answers.
eq(handlers.msufurl("msufurl:https://example.org/x", "[x]", { type = "msufurl", options = "https://example.org/x" }), nil,
    "the URL handler must answer as handled")
eq(copied, "https://example.org/x", "clicking a URL did not open its copy box")
config.allTimestamps, config.timestampFormat = true, "%Q"
C.CompileMessages(config)
assert(Rendered("hello"):find("[12:34]", 1, true), "invalid timestamp falls back")
config.timestampFormat = "%"
C.CompileMessages(config)
assert(Rendered("hello"):find("[12:34]", 1, true))
-- Blizzard's own stamp (showTimestamps) is replaced, not repeated.
config.timestampFormat = "[%H:%M]"
nativeStamp = "%H:%M "
C.CompileMessages(config)
eq(Rendered("12:34 hello"), "[12:34] hello", "Blizzard's own timestamp was kept next to the Suite stamp")
-- Per line, settings were compiled: no global string, and the native
-- setting at most once per second.
config.shortenChannels, config.channelShortcuts = true, "General=Gen"
C.CompileMessages(config)
stringReads, cvarReads = 0, 0
for _ = 1, 20 do Rendered("|Hchannel:GUILD|h[Guild]|h Mapko: hi [2. General] and [Guild]") end
eq(stringReads, 0, "a line read Blizzard's channel labels")
assert(cvarReads <= 1, "a line read the native timestamp setting")
local shortened = Rendered("|Hchannel:GUILD|h[Guild]|h Mapko: hi [2. General]")
assert(shortened:find("|Hchannel:GUILD|h[G]|h", 1, true) and shortened:find("[Gen]", 1, true),
    "channel prefixes or shortcuts were not shortened")
config.allTimestamps, config.shortenChannels, nativeStamp = false, false, "none"
C.MessagesRefresh(M)

local a, b = Frame(1), Frame(3)
local nativeAdd = a.AddMessage
C.ApplyMessages(M, a)
C.ApplyMessages(M, b)
saved = assert(MSUFSuiteChatHistory, "the per-character history table was not created")
eq(a.AddMessage, nativeAdd, "native method retained")
for i = 1, 25 do a:AddMessage("line " .. i, 1, 1, 1) end
b:AddMessage("other tab")
eq(#a.lines, 25, "delivery intact")
C.ApplyMessages(M, a)
eq(#a.lines, 25, "empty-at-login history not replayed after later capture")
local history = saved.tabs["ChatFrame1:General"]
eq(history.count, 20, "bounded ring")
eq(saved.tabs["ChatFrame3:Other"].count, 1, "separate permanent tab")
-- The combat log takes no text tools and keeps no history; the voice
-- transcription window (its own event handler) gets every tool.
local combatLog = ChatFrame2
C.ApplyMessages(M, combatLog)
assert(not securePostHooks[combatLog], "the combat log got the message hook without the idle fade")
combatLog:AddMessage("Mapko hits https://example.org for 5")
eq(combatLog.transforms, nil, "a combat log line was transformed")
local voice = Frame(4)
voice.customEventHandler = function() return false end
C.ApplyMessages(M, voice)
voice:AddMessage("Mapko: see https://example.org/voice")
assert(voice.lines[1]:find("|Hmsufurl:https://example.org/voice|h", 1, true),
    "the voice transcription window lost its message tools")
assert(saved.tabs["ChatFrame4:Other"] and saved.tabs["ChatFrame4:Other"].count == 1,
    "the voice transcription window kept no history")
for key in pairs(saved.tabs) do
    assert(not key:find("ChatFrame2", 1, true), "history was kept for the combat log")
end
C.MessagesDisable()

-- A new session of the same character: lines replay behind the session's.
local restored = Frame(1)
C, M, handlers = LoadChat(saved)
C.MessagesRefresh(M)
restored:AddMessage("session start")
C.ApplyMessages(M, restored)
eq(#restored.lines, 21, "restored bounded history")
eq(restored.lines[1], "line 6", "oldest kept restored first")
eq(restored.lines[20], "line 25", "latest restored last")
eq(restored.lines[21], "session start", "saved lines must sit behind the session's own lines")
eq(history.count, 20, "replay does not save duplicates")
C.ApplyMessages(M, restored)
eq(#restored.lines, 21, "repeat refresh does not replay")
eq(#restored.securePostHooks, 1, "refresh installed a second post-hook")
-- Native transforms keep censorship/event metadata and access IDs intact.
local opaque = setmetatable({}, { __index = function() error("native private event arguments inspected") end })
local formatter = function() end
restored:AddMessage("Mapko https://example.org/test", .2, .3, .4, 7, 53, 54, "CHAT_MSG_WHISPER", opaque, formatter)
local latest = #restored.lines
assert(restored.lines[latest]:find("|Hmsufurl:https://example.org/test|h", 1, true), "native formatting lost URL")
local payload = restored.payloads[latest]
eq(payload[1], .2, "red"); eq(payload[2], .3, "green"); eq(payload[3], .4, "blue")
eq(payload[4], 7, "type ID"); eq(payload[5], 53, "access ID"); eq(payload[6], 54, "line ID")
eq(payload[7], "CHAT_MSG_WHISPER", "native event"); eq(payload[8], opaque, "private argument identity")
eq(payload[9], formatter, "censorship formatter identity")
local beforeResize = #restored.lines
config.historyLines = 40
C.ApplyMessages(M, restored)
eq(history.count, 20, "grow retains saved lines"); eq(history.limit, 40, "grown capacity")
restored:AddMessage("after grow")
eq(history.count, 21, "grown ring accepts new line")
config.historyLines = 20
C.ApplyMessages(M, restored)
eq(history.count, 20, "shrink retains newest lines"); eq(history.limit, 20, "shrunk capacity")
eq(#restored.lines, beforeResize + 1, "capacity change does not replay current-session lines")
-- Battle.net names only resolve in the session that received them.
restored:AddMessage("|HBNplayer:|Kq12|k:5:9:BN_WHISPER:|Kq12|k|h[|Kq12|k]|h: hi, |Kq13|k")
local kept = history.lines[(history.next - 2) % history.limit + 1].text
eq(kept, "[Battle.net friend]: hi, Battle.net friend", "a saved line kept a session-bound Battle.net name or link")
-- Restricted chat text is neither parsed nor saved; a history-only line
-- reads no unit or tab information and never transforms the buffer.
GetChatWindowInfo = function() error("per-message native tab read") end
local count = history.count
restored:AddMessage("secret")
eq(history.count, count, "restricted payload not saved")
config.linkURLs, config.colorMentionNames = false, false
C.CompileMessages(config)
local transforms = restored.transforms
restored:AddMessage("history only")
eq(restored.transforms, transforms, "history-only capture does not scan or transform the native buffer")
local temporary = Frame(5)
temporary.isTemporary = true
C.ApplyMessages(M, temporary)
temporary:AddMessage("temporary whisper")
eq(saved.tabs["ChatFrame5:Other"], nil, "temporary conversations excluded")
GetChatWindowInfo = function(id) return id == 1 and "General" or "Other" end
C.MessagesDisable()
local beforeDisabled = history.next
restored:AddMessage("disabled delivery")
eq(history.next, beforeDisabled, "disabled module does not record")
C.MessagesRefresh(M)
C.ApplyMessages(M, restored)
eq(#restored.securePostHooks, 1, "re-enable duplicated post-hook")
local afterEnable = #restored.lines
C.ApplyMessages(M, restored)
eq(#restored.lines, afterEnable, "re-enable replayed existing live history")

-- Idle fade: one timer per idle period, direct alpha that also works in
-- combat, wake on new lines and on Blizzard's mouse-over fade-in.
config.idleSeconds, config.idleAlpha = 5, 20
C.MessagesRefresh(M)
C.ApplyMessages(M, restored)
local tab = Frame(0, "ChatFrame1Tab")
tab.alpha = 0.8
_G.ChatFrame1Tab = tab
restored.editBox = Frame(0, "ChatFrame1EditBox")
restored.editBox.alpha = 0.35
local visual = { frame = restored }
M.visuals[restored] = visual
for i = #timers, 1, -1 do timers[i] = nil end
C.ApplyInactivity(M, visual)
assert(fcfHooks.FCF_FadeInChatFrame and fcfHooks.FCF_FadeOutChatFrame, "pointer activity is not followed")
eq(#timers, 1, "arming the fade did not start one countdown")
for i = 1, 30 do now = i * 0.1; restored:AddMessage("busy " .. i) end
eq(#timers, 1, "every line started its own timer")
RunTimers(now + 5)
eq(restored.alpha, .2, "idle fade")
eq(tab.alpha, .2, "the tab did not fade with its window")
eq(restored.editBox.alpha, .2, "the input line did not fade with its window")
combat = true
restored:AddMessage("party message in combat")
eq(restored.alpha, 1, "a line in combat did not wake the faded window")
eq(tab.alpha, 0.8, "waking did not give the tab its alpha back")
eq(restored.editBox.alpha, 0.35, "waking did not give the input line its alpha back")
RunTimers(now + 5)
eq(restored.alpha, .2, "the fade did not run in combat")
-- Blizzard's fade-in on mouse-over wakes the window and holds the fade.
fcfHooks.FCF_FadeInChatFrame(restored)
eq(restored.alpha, 1, "mouse-over did not wake the window")
eq(tab.alpha, .2, "waking on mouse-over fought Blizzard's own tab fade-in")
tab.alpha = 1 -- Blizzard's fade-in animation reached mouseOverAlpha
RunTimers(now + 30)
eq(restored.alpha, 1, "the window faded under the pointer")
tab.alpha = 0.8 -- Blizzard's fade-out animation reached noMouseAlpha
fcfHooks.FCF_FadeOutChatFrame(restored)
RunTimers(now + 5)
eq(restored.alpha, .2, "the countdown did not start again after the pointer left")
-- Blizzard changed the input line meanwhile (chat opened): its value stays.
restored.editBox.alpha = 1
restored:AddMessage("wake")
eq(restored.editBox.alpha, 1, "waking overwrote Blizzard's own input alpha")
combat = false
RunTimers(now + 5)
config.idleSeconds = 0
C.ApplyInactivity(M, visual)
eq(restored.alpha, 1, "off restores after timer already finished")
eq(tab.alpha, 0.8, "off did not restore the tab")

-- The combat log's lines wake its idle fade, and do nothing else.
do
    config.idleSeconds = 5
    C.MessagesRefresh(M)
    local logVisual = { frame = combatLog }
    M.visuals[combatLog] = logVisual
    _G.ChatFrame2Tab = Frame(0, "ChatFrame2Tab")
    C.ApplyMessages(M, combatLog)
    C.ApplyInactivity(M, logVisual)
    assert(securePostHooks[combatLog], "the combat log's lines do not wake its idle fade")
    RunTimers(now + 5)
    eq(combatLog.alpha, .2, "the combat log did not fade")
    local count = #combatLog.lines
    combatLog:AddMessage("Mapko hits https://example.org for 5")
    eq(combatLog.alpha, 1, "a combat log line did not wake the faded combat log")
    eq(combatLog.transforms, nil, "a combat log line was transformed for the fade")
    eq(#combatLog.lines, count + 1, "a combat log line was not delivered")
    for key in pairs(saved.tabs) do
        assert(not key:find("ChatFrame2", 1, true), "the fade made the combat log keep history")
    end
    config.idleSeconds = 0
    C.ApplyInactivity(M, logVisual)
    M.visuals[combatLog] = nil
end

-- History-only and fade hot path: no allocation once the ring is full.
config.idleSeconds = 5
C.MessagesRefresh(M)
C.ApplyMessages(M, restored)
C.ApplyInactivity(M, visual)
local texts = {}
for i = 1, 200 do texts[i] = "steady " .. i end
for i = 1, 40 do restored:AddMessage(texts[i]) end
restored.lines, restored.payloads = {}, {}
local function Quiet(frame, text) frame.securePostHooks[1](frame, text, 1, 1, 1) end
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for i = 41, 200 do Quiet(restored, texts[i]) end
local grown = collectgarbage("count") - before
collectgarbage("restart")
assert(grown < 1, "the history and fade path allocated per line (" .. grown .. " KB)")

-- A full window wraps: Blizzard's CircularBuffer (CircularBuffer.lua)
-- behind ScrollingMessageFrame's AddMessage and TransformMessages
-- (ScrollingMessageFrame.lua). AddMessage pushes to the front, TransformIf
-- visits every stored entry in storage order. Only the newest entry may be
-- rewritten, and a formatted line costs the hook a fixed budget.
do
    local EMPTY = {}
    local function NativeWindow(id, maxLines)
        local buffer = { elements = {}, head = 0, max = maxLines }
        function buffer:CalculateElementIndex(index)
            local globalIndex = self.head - index + 1
            if globalIndex == 0 then return self.max end
            return (globalIndex - 1) % self.max + 1
        end
        local window = { id = id, historyBuffer = buffer, transforms = 0 }
        function window:GetName() return "ChatFrame" .. self.id end
        function window:GetID() return self.id end
        function window:GetMaxLines() return buffer.max end
        function window:GetNumMessages() return #buffer.elements end
        function window:BackFillMessage() error("an empty saved ring replayed lines") end
        function window:AddMessage(text, r, g, b, ...)
            buffer.head = buffer.head + 1
            local insert = buffer.head
            local count = select("#", ...)
            buffer.elements[insert] = { message = text, r = r, g = g, b = b,
                extraData = count > 0 and { n = count, ... } or nil }
            buffer.head = insert % buffer.max
            for _, callback in ipairs(self.securePostHooks or EMPTY) do callback(self, text, r, g, b, ...) end
        end
        function window:TransformMessages(predicate, transform)
            self.transforms = self.transforms + 1
            for i, entry in ipairs(buffer.elements) do
                local extra = entry.extraData or EMPTY
                if predicate(entry.message, entry.r, entry.g, entry.b, unpack(extra, 1, extra.n or 0)) then
                    local values = { transform(entry.message, entry.r, entry.g, entry.b, unpack(extra, 1, extra.n or 0)) }
                    buffer.elements[i] = { message = values[1], r = values[2], g = values[3], b = values[4] }
                end
            end
        end
        -- Display order: 1 is the newest line.
        function window:Line(index) return buffer.elements[buffer:CalculateElementIndex(index)].message end
        return window
    end
    config.allTimestamps, config.saveHistory, config.idleSeconds = true, false, 0
    C.MessagesRefresh(M)
    local window = NativeWindow(6, 128)
    window:AddMessage("hello", 1, 1, 1)
    C.ApplyMessages(M, window)
    for i = 1, 126 do window:AddMessage("line " .. i, 1, 1, 1) end
    window:AddMessage("hello", 1, 1, 1)
    eq(window:Line(1), "[12:34] hello", "the newest line was not stamped")
    eq(window:Line(128), "hello", "an older line with the same text was rewritten")
    eq(window:Line(2), "[12:34] line 126", "the line before the newest lost its stamp")
    for i = 127, 140 do window:AddMessage("line " .. i, 1, 1, 1) end
    eq(window:Line(1), "[12:34] line 140", "the newest line of a wrapped window was not stamped")
    for index = 1, 128 do
        assert(window:Line(index):find("[12:34] ", 1, true) == 1, "a line of the wrapped window was not stamped once")
    end
    -- Another hook that adds its own line first: the raw line is found anyway.
    local echoing = false
    table.insert(window.securePostHooks, 1, function(frame, text)
        if echoing or text ~= "ping" then return end
        echoing = true
        frame:AddMessage("pong", 1, 1, 1)
        echoing = false
    end)
    window:AddMessage("ping", 1, 1, 1)
    eq(window:Line(1), "[12:34] pong", "the other hook's line was not stamped")
    eq(window:Line(2), "[12:34] ping", "a line pushed past the front by another hook was not stamped")
    table.remove(window.securePostHooks, 1)
    -- Budget: Lua VM instructions of one stamped line in a full window,
    -- this window model included (GC and hooks aside, deterministic on Lua
    -- 5.1). 2026-10-01: 4534 when every visit read the raw text, 3548 with
    -- the newest-slot predicate; +2 % headroom.
    local CHAT_LINE_BUDGET = 3620
    local count = 0
    local function Instructions(fn)
        count = 0
        debug.sethook(function() count = count + 1 end, "", 1)
        fn()
        debug.sethook()
        return count
    end
    local used = Instructions(function() window:AddMessage("budget line", 1, 1, 1) end)
    eq(window:Line(1), "[12:34] budget line", "the budget line was not stamped")
    print("chat stamped line in a full 128-line window: " .. used .. " instructions")
    assert(used <= CHAT_LINE_BUDGET, "a stamped line cost " .. used .. " instructions (budget " .. CHAT_LINE_BUDGET .. ")")
    config.allTimestamps, config.saveHistory, config.idleSeconds = false, true, 5
    C.MessagesRefresh(M)
end

C.ClearHistory()
eq(history.count, 0, "clear saved content")
restored:AddMessage("after clear")
eq(saved.tabs["ChatFrame1:General"].count, 1, "clear did not detach old ring")
-- Another character has its own saved variables: nothing replays and the
-- first character's table stays untouched.
local otherSaved
local otherChat, other = LoadChat(otherSaved)
otherChat.MessagesRefresh(other)
local otherFrame = Frame(1)
otherChat.ApplyMessages(other, otherFrame)
eq(#otherFrame.lines, 0, "another character replayed the previous character history")
otherFrame:AddMessage("character B")
eq(MSUFSuiteChatHistory.tabs["ChatFrame1:General"].count, 1, "another character saved under wrong identity")
eq(saved.tabs["ChatFrame1:General"].count, 1, "another character altered previous history")
-- History is per character: the Chat TOC declares the table, and the
-- account-wide Suite database never holds chat lines.
local tocFile = assert(io.open(root .. "/MSUF_Suite_Chat/MSUF_Suite_Chat_Mainline.toc", "rb"))
local tocText = tocFile:read("*a")
tocFile:close()
assert(tocText:gsub("\r", ""):find("\n## SavedVariablesPerCharacter: MSUFSuiteChatHistory\n", 1, true),
    "the Chat TOC does not keep history per character")
eq(next(NS.RootDB), nil, "chat lines reached the account-wide Suite database")
print("chat messages PASS")
