-- Suite delivery uses the native AddMessage entry point and its post-hooks.
-- Compare it with the original print path against a wrapped, full buffer.
local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local secret = {}
local reported, dispatched = 0, 0
local nativeCalls = 0
local S = {
    IsSecret = function(value) return rawequal(value, secret) end,
    Finite = function(value) return type(value) == "number" end,
    Text = function(value) return value end,
    ClassRGB = function() return 1, .5, 0 end,
}
S.Public = function(value) return not S.IsSecret(value) end
S.PublicText = function(value)
    return not S.IsSecret(value) and type(value) == "string" and value ~= "" and value or nil
end
S.Dispatch = function(callback, ...)
    nativeCalls = nativeCalls + 1
    dispatched = dispatched + 1
    local thread = coroutine.create(callback)
    local hook, mask, count = debug.gethook()
    if hook then debug.sethook(thread, hook, mask, count) end
    local ok, result = coroutine.resume(thread, ...)
    if not ok then reported = reported + 1; return end
    return result
end
local NS = { Suite = S }
local private = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Chat/Shared.lua"))("MSUF_Suite_Chat", private)
local C, M = private.Chat, private.Chat.M
local config = Support.CatalogDefaults(root, "chat")
config.saveHistory, config.historyLines, config.idleSeconds, config.coloredUnreadTabs = true, 20, 5, true
config.linkURLs, config.colorMentionNames, config.shortenChannels, config.allTimestamps = true, true, true, true
config.timestampFormat = "[%H:%M]"
M.config = config
C.CompileUnread = function() end
C.MessageUnread = function(frame, kind)
    frame.unread = frame.unread + 1
    frame.lastType = kind
    if frame.onUnread then frame.onUnread() end
end
C.ChatActivity = function(frame) frame.wakes, frame.alpha = frame.wakes + 1, 1 end
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
GetChatWindowInfo = function() return "Print" end
LinkUtil = { RegisterLinkHandler = function() end }
CHAT_GUILD_GET, CHAT_PARTY_GET = "|Hchannel:GUILD|h[Guild]|h %s: ", "[Party] %s: "
CHAT_RAID_GET, CHAT_RAID_WARNING_GET = "[Raid] %s: ", "[Raid Warning] %s: "
CHAT_INSTANCE_CHAT_GET, CHAT_OFFICER_GET = "[Instance] %s: ", "[Officer] %s: "
C_CVar = { GetCVar = function() nativeCalls = nativeCalls + 1; return "12:34 " end }
time = function() nativeCalls = nativeCalls + 1; return 1000 end
date = function(format)
    if format == "<%p>" then return "<a.m.>" end
    return format == "12:34 " and "12:34 " or "[12:34]"
end
TimeUtil = { BetterDate = function(format) return date(format) end }
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end
local memberName = "Mapko"
UnitName = function() return memberName end
UnitClass = function() return "Mage", "MAGE" end
hooksecurefunc = function(frame, method, callback)
    eq(method, "AddMessage", "native hook")
    frame.hooks[#frame.hooks + 1] = callback
end
assert(loadfile(root .. "/MSUF_Suite_Chat/History.lua"))("MSUF_Suite_Chat", private)
-- Load the shipped public entry point without booting unrelated platform APIs.
local file = assert(io.open(root .. "/MSUF_Suite/Core/Platform.lua", "rb"))
local platform = file:read("*a"); file:close()
local printSource = assert(platform:match("function Suite%.Print%(message%).-\nend"))
local defaultPrint = platform:match("function Suite%.PrintChatMessage%(frame, text%).-\nend") or ""
assert(loadstring("local Suite = ...\n" .. defaultPrint .. "\n" .. printSource))(NS)
S.Print = NS.Print
local fallback
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) fallback = text end }
S.Print(42)
eq(fallback, "MSUF Suite: 42", "chat addon absent")
assert(loadfile(root .. "/MSUF_Suite_Chat/Messages.lua"))("MSUF_Suite_Chat", private)

local function Window(id)
    local entries, head = {}, 0
    local window = { id = id, hooks = {}, transforms = 0, unread = 0, wakes = 0, alpha = .2 }
    local function Package(text, r, g, b, ...)
        nativeCalls = nativeCalls + 1 -- PackageEntry's GetTime.
        return { text = text, r = r, g = g, b = b, n = select("#", ...), timestamp = 1000, ... }
    end
    function window:GetID() return self.id end
    function window:GetName() return "ChatFrame" .. self.id end
    function window:GetMaxLines() return 128 end
    function window:GetNumMessages() return #entries end
    function window:BackFillMessage() error("unexpected history replay") end
    window.historyBuffer = { CalculateElementIndex = function(_, index)
        nativeCalls = nativeCalls + 1
        return (head - index) % 128 + 1
    end }
    function window:AddMessage(text, r, g, b, ...)
        nativeCalls = nativeCalls + 1
        if self.failNext then self.failNext = nil; error("delivery failed") end
        head = head % 128 + 1
        entries[head] = Package(text, r, g, b, ...)
        for _, hook in ipairs(self.hooks) do hook(self, text, r, g, b, ...) end
    end
    function window:TransformMessages(predicate, transform)
        nativeCalls = nativeCalls + 1
        self.transforms = self.transforms + 1
        if self.onTransform then self.onTransform() end
        -- Native TransformMessages makes two closures and repackages changed
        -- entries, including a fresh native timestamp (ScrollingMessageFrame).
        local function Unpackage(entry) return entry.text, entry.r, entry.g, entry.b, unpack(entry, 1, entry.n) end
        local function TransformEntry(...) return Package(transform(...)) end
        for index, entry in ipairs(entries) do
            if predicate(Unpackage(entry)) then
                entries[index] = TransformEntry(Unpackage(entry))
            end
        end
    end
    function window:Line(index) return entries[(head - index) % 128 + 1] end
    for index = 1, 140 do window:AddMessage("old " .. index, .1, .2, .3, 9, "access", "line") end
    return window
end
local function Compile()
    C.CompileMessages(config)
    C.MessageRoster()
end
local function Print(window, legacy, message)
    DEFAULT_CHAT_FRAME = window
    if legacy then window:AddMessage("MSUF Suite: " .. tostring(message)) else S.Print(message) end
end
local function Formats(callback)
    local calls = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "nS")
        if info.name == "Format" and info.source:find("Messages.lua", 1, true) then calls = calls + 1 end
    end, "c")
    callback()
    debug.sethook()
    return calls
end
local function Pair()
    MSUFSuiteChatHistory = nil
    local old, new = Window(1), Window(3)
    C.ApplyMessages(M, old)
    C.ApplyMessages(M, new)
    return old, new
end
local function Same(old, new)
    for index = 1, 128 do
        local a, b = old:Line(index), new:Line(index)
        eq(b.text, a.text, "stored line " .. index)
        eq(b.r, a.r, "stored red")
        eq(b.g, a.g, "stored green")
        eq(b.b, a.b, "stored blue")
        eq(b.n, a.n, "payload length " .. index)
        for field = 1, a.n do eq(b[field], a[field], "native payload " .. field) end
    end
    eq(new.unread, old.unread, "unread count")
    eq(new.wakes, old.wakes, "activity count")
    eq(new.alpha, old.alpha, "fade wake")
    eq(new.lastType, old.lastType, "delivery type")
    local a, b = C.HistoryRing("ChatFrame1:Print"), C.HistoryRing("ChatFrame3:Print")
    eq(b.count, a.count, "history count")
    eq(b.next, a.next, "history cursor")
    for index = 1, a.count do
        for _, key in ipairs({ "text", "r", "g", "b" }) do
            eq(b.lines[index][key], a.lines[index][key], "saved " .. key)
        end
    end
end

Compile()
do
    local old, new = Pair()
    local text = "12:34 |Hchannel:GUILD|h[Guild]|h Mapko https://example.org/Mapko. |Hspell:123|h[Mapko]|h |cff00ff00green|r"
    for index = 1, 45 do
        Print(old, true, text .. " " .. index)
        Print(new, false, text .. " " .. index)
    end
    Same(old, new)
    eq(old.transforms, 45, "legacy full-history passes")
    eq(new.transforms, 0, "Suite print traversed the full history")
    assert(new:Line(1).text:find("|cffff8000Mapko|r", 1, true), "class color missing")
    assert(new:Line(1).text:find("|Hmsufurl:https://example.org/Mapko|h", 1, true), "URL missing")
end

-- Warm, identical inputs isolate recurring work from first-use string/ring
-- creation. The fixture includes native entry storage and dispatch overhead.
do
    C.ClearHistory()
    local old, new = Pair()
    local text = "budget Mapko https://example.org/budget |Hspell:123|h[Mapko]|h"
    for _ = 1, 25 do Print(old, true, text); Print(new, false, text) end
    local function Measure(window, legacy, texts)
        local instructions = 0
        local function Count() instructions = instructions + 1 end
        collectgarbage("collect")
        collectgarbage("stop")
        local heap = collectgarbage("count")
        local native = nativeCalls
        debug.sethook(Count, "", 1)
        for index = 1, 100 do Print(window, legacy, texts and texts[index] or text) end
        debug.sethook()
        local grown = collectgarbage("count") - heap
        collectgarbage("restart")
        return instructions, grown, nativeCalls - native
    end
    local oldVM, oldHeap, oldNative = Measure(old, true)
    local newVM, newHeap, newNative = Measure(new, false)
    assert(newVM < oldVM, "prepared prints increased VM work: " .. newVM .. " >= " .. oldVM)
    assert(newHeap <= oldHeap, "prepared prints increased warm allocation: " .. newHeap .. " > " .. oldHeap)
    assert(newNative < oldNative, "prepared prints increased native work: " .. newNative .. " >= " .. oldNative)
    -- Different, equally sized inputs prevent string interning across the
    -- two deliveries from hiding per-message formatting allocations.
    local oldTexts, newTexts = {}, {}
    for index = 1, 100 do
        local body = " Mapko https://example.org/" .. index .. " |Hspell:123|h[Mapko]|h " .. index
        oldTexts[index], newTexts[index] = "old" .. body, "new" .. body
    end
    oldVM, oldHeap, oldNative = Measure(old, true, oldTexts)
    newVM, newHeap, newNative = Measure(new, false, newTexts)
    assert(newVM < oldVM, "distinct prepared prints increased VM work")
    assert(newHeap <= oldHeap, "distinct prepared prints increased allocation: " .. newHeap .. " > " .. oldHeap)
    assert(newNative < oldNative, "distinct prepared prints increased native work")
end

-- Hooks both before and after our hook can print, echo the prepared line,
-- and add unrelated messages. Only those unrelated messages need transforms.
for _, before in ipairs({ true, false }) do
    C.ClearHistory()
    local old, new = Pair()
    local function Install(window, legacy)
        local nested = false
        local hook = function(frame, text)
            if nested or not text:find("OUTER", 1, true) then return end
            nested = true
            Print(frame, legacy, "NESTED Mapko https://example.org/nested")
            frame:AddMessage(text)
            frame:AddMessage("external Mapko", .2, .3, .4, 7, "access", "line")
            nested = false
        end
        table.insert(window.hooks, before and 1 or #window.hooks + 1, hook)
    end
    Install(old, true)
    Install(new, false)
    Print(old, true, "OUTER Mapko https://example.org/outer")
    local calls = Formats(function() Print(new, false, "OUTER Mapko https://example.org/outer") end)
    Same(old, new)
    eq(new.transforms, 1, "nested Suite prints or hook echo traversed history")
    eq(calls, 5, "nested print or echo repeated formatting")
end
config.timestampFormat = "[%H:%M]"
Compile()

-- A nested print from the unread observer also restores the outer marker.
do
    C.ClearHistory()
    local old, new = Pair()
    local function Install(window, legacy)
        window.onUnread = function()
            window.onUnread = nil
            Print(window, legacy, "observer Mapko")
        end
    end
    Install(old, true)
    Install(new, false)
    Print(old, true, "outer observer Mapko")
    Print(new, false, "outer observer Mapko")
    Same(old, new)
    eq(new.transforms, 0, "unread reentry lost the enclosing prepared line")
end

config.linkURLs, config.colorMentionNames, config.shortenChannels, config.allTimestamps = false, false, false, false
Compile()
do
    C.ClearHistory()
    local old, new = Pair()
    Print(old, true, "Mapko https://example.org/plain")
    local calls = dispatched
    Print(new, false, "Mapko https://example.org/plain")
    eq(dispatched, calls, "formatting off added a secure boundary")
    Same(old, new)
    eq(new:Line(1).text, "MSUF Suite: Mapko https://example.org/plain", "formatting off")
    eq(new.transforms, 0, "formatting off transformed history")
    eq(new.wakes, 1, "formatting off lost activity")
end

-- Enabled tools can leave a line unchanged. It still formats only once,
-- without paying a new secure boundary, including nested unchanged prints.
config.linkURLs = true
Compile()
do
    C.ClearHistory()
    local old, new = Pair()
    local calls = dispatched
    eq(Formats(function() Print(new, false, "plain text") end), 1, "unchanged print formatted twice")
    eq(dispatched, calls, "unchanged print added a secure boundary")
    local nested = false
    table.insert(new.hooks, 1, function(frame)
        if nested then return end
        nested = true
        Print(frame, false, "nested plain text")
        nested = false
    end)
    eq(Formats(function() Print(new, false, "outer plain text") end), 2, "unchanged reentry formatted twice")
    new.hooks[1] = function()
        config.allTimestamps = true
        Compile()
    end
    Print(new, false, "settings changed in hook")
    eq(new:Line(1).text, "[12:34] MSUF Suite: settings changed in hook", "stale identity memo survived refresh")
end

-- An earlier hook can change the formatter after preparation. Only results
-- from the current generation may bypass the secure transform path.
for _, refresh in ipairs({ "settings", "roster", "disabled", "timestamp", "roster removal" }) do
    C.ClearHistory()
    local old, new = Pair()
    local function Reset()
        config.allTimestamps, config.colorMentionNames = refresh == "timestamp", refresh ~= "disabled"
        config.linkURLs = true
        memberName = refresh == "roster removal" and "Other" or "Mapko"
        Compile()
    end
    for _, window in ipairs({ old, new }) do
        table.insert(window.hooks, 1, function()
            if refresh == "settings" then
                config.allTimestamps = true
                Compile()
            elseif refresh == "disabled" then
                config.linkURLs = false
                Compile()
            elseif refresh == "timestamp" then
                config.allTimestamps = false
                Compile()
            else
                memberName = refresh == "roster" and "Other" or "Mapko"
                C.MessageRoster()
            end
        end)
        Reset()
        Print(window, window == old, "refresh Other https://example.org/refresh")
    end
    eq(new:Line(1).text, old:Line(1).text, "stale prepared memo survived " .. refresh .. " refresh")
    eq(new.transforms, 1, "formatter refresh skipped its transform")
    Same(old, new)
end
memberName = "Mapko"
config.allTimestamps, config.colorMentionNames = true, true
Compile()
do
    C.ClearHistory()
    local old, new = Pair()
    -- The old hook suppresses a print raised while Transform owns its record.
    for _, window in ipairs({ old, new }) do
        window.onTransform = function()
            window.onTransform = nil
            Print(window, window == old, "inside transform Mapko")
        end
        window:AddMessage("external Mapko")
    end
    Same(old, new)
    eq(new:Line(1).text, "MSUF Suite: inside transform Mapko", "transform reentry changed")
    eq(new.wakes, 1, "transform reentry escaped suppression")
    local historyCount = C.HistoryRing("ChatFrame3:Print").count
    NS.PrintChatMessage(new, secret)
    eq(new:Line(1).text, secret, "unreadable line did not reach its native sink")
    eq(C.HistoryRing("ChatFrame3:Print").count, historyCount, "unreadable line was saved")
    new.failNext = true
    Print(new, false, "failed Mapko")
    eq(reported, 1, "delivery failure not reported")
    local passes = new.transforms
    local calls = Formats(function() new:AddMessage("[12:34] MSUF Suite: failed |cffff8000Mapko|r") end)
    eq(calls, 1, "failed print suppressed a subsequent external message")
    new:AddMessage("MSUF Suite: failed Mapko")
    eq(new.transforms, passes + 1, "failed print suppressed a subsequent external message")
    C.MessagesDisable()
    Print(new, false, "disabled Mapko")
    eq(new:Line(1).text, "MSUF Suite: disabled Mapko", "disabled formatter still ran")
    local untouched = Window(5)
    Print(untouched, false, "unstyled Mapko")
    eq(untouched:Line(1).text, "MSUF Suite: unstyled Mapko", "unstyled destination formatted")
    ChatFrame2 = Window(2)
    C.ApplyMessages(M, ChatFrame2)
    Print(ChatFrame2, false, "combat log Mapko")
    eq(ChatFrame2:Line(1).text, "MSUF Suite: combat log Mapko", "combat log formatted")
    eq(ChatFrame2.wakes, 1, "combat log lost activity")
    eq(ChatFrame2.unread, 0, "combat log gained unread work")
end

-- Some accepted custom formats are not idempotent. In that case an
-- independent identical hook line cannot safely share a prepared result.
config.timestampFormat = "<%p>"
Compile()
do
    C.ClearHistory()
    local old, new = Pair()
    for _, window in ipairs({ old, new }) do
        local emitted = false
        table.insert(window.hooks, 1, function(frame)
            if emitted then return end
            emitted = true
            frame:AddMessage("<a.m.> MSUF Suite: localized |cffff8000Mapko|r")
        end)
    end
    Print(old, true, "localized Mapko")
    Print(new, false, "localized Mapko")
    Same(old, new)
    eq(new.transforms, old.transforms, "unstable format did not keep the old path")
    local calls = Formats(function() Print(new, false, "second localized Mapko") end)
    eq(calls, 1, "unstable format was reprobed before refresh")
end
print("chat Suite prints: full history, nested hooks, echoes, history, activity and formatting off PASS")
