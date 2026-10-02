local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Optional message tools: clickable URLs, class-colored group names, short
-- channel prefixes, a timestamp on every line, saved history and the idle
-- fade's wake-up. A secure post-hook on a window's AddMessage sees each
-- line; a line that changes is rewritten in place through the window's own
-- TransformMessages, so Blizzard's elevation barrier keeps every access ID,
-- event argument and censorship formatter and nothing is delivered again.
-- The combat log (ChatFrame2, Blizzard_CombatLog's COMBATLOG) prints far
-- more lines than anyone reads: its lines only wake the idle fade. Its text
-- tools would rewrite the whole window per line, and Blizzard_CombatLog
-- rebuilds the window from the client's own entries; Blizzard's combat log
-- has its own Timestamp setting. Everything a line needs is compiled when
-- the settings change.
local M = C.M
local PublicText = S.PublicText
local HistoryRing, HistoryStore, HistoryReplay = C.HistoryRing, C.HistoryStore, C.HistoryReplay
local ChatActivity = C.ChatActivity
local Dispatch = S.Dispatch
local URL = "https?://[^%s|<>]+"
local NAME = "[%a\128-\255][%w\128-\255]*"
local DATE_SPEC = "%%[aAbBcdHIjmMpSUwWxXyYzZ%%]"
local DEFAULT_STAMP = "[%H:%M]"
-- Group chat prefixes, shortened in this order.
local CHANNELS = {
    "GUILD", "G", "PARTY", "P", "RAID", "R", "RAID_WARNING", "RW", "INSTANCE_CHAT", "I", "OFFICER", "O",
}
-- frame -> { live, ring, key, replayed, source, rendered, matches, transform }
local hooks = setmetatable({}, { __mode = "k" })
local members, shortcuts, channelRules = {}, {}, {}
-- Reused buffers of the formatting passes (the outer one splits around
-- native links, the inner one around URLs).
local runs, pieces = {}, {}
local tools = {}
local stampFormat, stampSecond, stampText = DEFAULT_STAMP, nil, ""
local nativeSetting, nativeFormat, nativePrefix

------------------------------------------------------------------ formatting
local function ColorName(name)
    local hex = members[name]
    if hex then return "|cff" .. hex .. name .. "|r" end
end

local function ColorNames(run)
    if not tools.names then return run end
    return (run:gsub(NAME, ColorName))
end

local function LinkURL(url)
    local body, tail = url:match("^(.-)([.,!;:)]*)$")
    return "|Hmsufurl:" .. body .. "|h[" .. body .. "]|h" .. tail
end

-- Plain text between native links: URLs become links, names get colored
-- outside the new links.
local function FormatRun(run)
    if run == "" or not tools.links then return ColorNames(run) end
    local start, finish = run:find(URL)
    if not start then return ColorNames(run) end
    local count, index = 0, 1
    while start do
        pieces[count + 1] = ColorNames(run:sub(index, start - 1))
        pieces[count + 2] = LinkURL(run:sub(start, finish))
        count, index = count + 2, finish + 1
        start, finish = run:find(URL, index)
    end
    pieces[count + 1] = ColorNames(run:sub(index))
    return table.concat(pieces, "", 1, count + 1)
end

-- Never alters the payload of a native hyperlink, texture or atlas escape.
local function FormatPlainRuns(text)
    local count, index, length = 0, 1, #text
    while index <= length do
        local start, finish = text:find("|H.-|h.-|h", index)
        local escape, escapeEnd = text:find("|[TA].-|[ta]", index)
        if escape and (not start or escape < start) then start, finish = escape, escapeEnd end
        if not start then
            count = count + 1
            runs[count] = FormatRun(text:sub(index))
            break
        end
        runs[count + 1] = FormatRun(text:sub(index, start - 1))
        runs[count + 2] = text:sub(start, finish)
        count, index = count + 2, finish + 1
    end
    return table.concat(runs, "", 1, count)
end

local function WorldChannel(number, name)
    return "[" .. (shortcuts[name] or number) .. "]"
end

-- Prefix labels differ by client language; only the bracketed label of the
-- public prefix changes, the native sender link stays untouched.
local function ShortChannels(text)
    for i = 1, #channelRules, 2 do
        local start, finish = text:find(channelRules[i], 1, true)
        if start then text = text:sub(1, start - 1) .. channelRules[i + 1] .. text:sub(finish + 1) end
    end
    return (text:gsub("%[(%d+)%. ([^%]]+)%]", WorldChannel))
end

-- A user format must never interrupt Blizzard's message delivery.
local function ValidFormat(format)
    return type(format) == "string" and #format <= 64 and not format:gsub(DATE_SPEC, ""):find("%", 1, true)
end

-- Once per second at most: the Suite stamp and the prefix Blizzard writes
-- itself (ChatFrameUtil.GetTimestampFormat, TimeUtil.BetterDate) while its
-- showTimestamps setting is on. Its own stamp is replaced, not repeated.
local function RefreshStamps(now)
    stampSecond = now
    stampText = date(stampFormat, now) .. " "
    local setting = C_CVar.GetCVar("showTimestamps")
    if setting ~= nativeSetting then
        nativeSetting = setting
        nativeFormat = PublicText(setting) and setting ~= "none" and ValidFormat(setting) and setting or nil
    end
    nativePrefix = nativeFormat and TimeUtil.BetterDate(nativeFormat, now) or nil
end

local function Stamp(text)
    local now = time()
    if now ~= stampSecond then RefreshStamps(now) end
    if nativePrefix and text:find(nativePrefix, 1, true) == 1 then text = text:sub(#nativePrefix + 1) end
    return stampText .. text
end

local function Format(text)
    if tools.plain then text = FormatPlainRuns(text) end
    if tools.channels then text = ShortChannels(text) end
    if tools.stamps then text = Stamp(text) end
    return text
end

-- The rendered public line, nil for a restricted or empty one.
function C.FormatMessage(text)
    text = PublicText(text)
    if not text or not tools.format then return text end
    return Format(text)
end

local function CompileChannels(config)
    for i = #channelRules, 1, -1 do channelRules[i] = nil end
    for name in pairs(shortcuts) do shortcuts[name] = nil end
    if not config.shortenChannels then return end
    for i = 1, #CHANNELS, 2 do
        local bracket = _G["CHAT_" .. CHANNELS[i] .. "_GET"]:match("(%[.-%])")
        if bracket then
            channelRules[#channelRules + 1] = bracket
            channelRules[#channelRules + 1] = "[" .. CHANNELS[i + 1] .. "]"
        end
    end
    for pair in config.channelShortcuts:gmatch("[^;]+") do
        local name, short = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if name and short and #name > 0 and #short > 0 and #short <= 12 then shortcuts[name] = short end
    end
end

-- Cold path: what every line needs, from the current settings.
function C.CompileMessages(config)
    tools.links, tools.names = config.linkURLs, config.colorMentionNames
    tools.channels, tools.stamps = config.shortenChannels, config.allTimestamps
    tools.plain = tools.links or tools.names
    tools.format = tools.plain or tools.channels or tools.stamps
    tools.history = config.saveHistory
    tools.fade = config.idleSeconds > 0
    tools.any = tools.format or tools.history or tools.fade
    CompileChannels(config)
    stampFormat = ValidFormat(config.timestampFormat) and config.timestampFormat or DEFAULT_STAMP
    stampSecond = nil
end

------------------------------------------------------------------ message hook
-- TransformMessages is the only writer that keeps a window's buffer secure:
-- ScrollingMessageFrameSecureMixin runs it as an elevation barrier
-- (ScrollingMessageFrame.lua:795-824); an entry written from addon code
-- would taint every refresh that reads it. Its loop visits each stored
-- entry in storage order (CircularBuffer:TransformIf), and AddMessage pushes
-- the new line to the front, storage slot CalculateElementIndex(1). The
-- predicate counts the visits and accepts only that slot, while it still
-- holds the raw line: only the newest entry is rewritten, and every other
-- visit costs one comparison. Should another hook's line have taken the
-- slot, one more pass rewrites the entries that hold the raw text.
local function Transform(frame, record)
    record.done = false
    record.aim(frame.historyBuffer:CalculateElementIndex(1))
    frame:TransformMessages(record.newest, record.transform)
    if not record.done then frame:TransformMessages(record.matches, record.transform) end
    return true
end

local function MessageAdded(frame, text, r, g, b)
    local record = hooks[frame]
    if not record.live or record.source then return end
    if record.wakeOnly then
        ChatActivity(frame)
        return
    end
    local public = PublicText(text)
    if not public then return end
    local rendered = public
    if tools.format then
        rendered = Format(public)
        if rendered ~= public then
            record.source, record.rendered = public, rendered
            if Dispatch(Transform, frame, record) ~= true then rendered = public end
            record.source, record.rendered = nil, nil
        end
    end
    if record.ring then HistoryStore(record.ring, rendered, r, g, b) end
    if tools.fade then ChatActivity(frame) end
end

local function NewRecord()
    local record = {}
    -- The visit count and the newest slot are upvalues: the predicate runs
    -- once per stored line.
    local visit, slot = 0, 0
    record.aim = function(newest)
        visit, slot = 0, newest
    end
    record.newest = function(text)
        visit = visit + 1
        if visit ~= slot then return false end
        return PublicText(text) == record.source
    end
    record.matches = function(text)
        return PublicText(text) == record.source
    end
    record.transform = function(_, r, g, b, ...)
        record.done = true
        return record.rendered, r, g, b, ...
    end
    return record
end

-- Permanent tabs (not Blizzard's temporary whisper windows) save history.
local function HistoryKey(frame)
    local id = frame:GetID()
    if frame.isTemporary or not S.Finite(id) or id < 1 or id > Constants.ChatFrameConstants.MaxChatWindows then
        return
    end
    local name, title = PublicText(frame:GetName()), PublicText((GetChatWindowInfo(id)))
    return name and title and name .. ":" .. title or nil
end

-- Cold path, per styled window (Window.lua). The combat log (ChatFrame2,
-- Blizzard_CombatLog's COMBATLOG) takes the hook only for the idle fade.
function C.ApplyMessages(_, frame)
    local record = hooks[frame]
    local combatLog = frame == ChatFrame2
    if not (combatLog and tools.fade or not combatLog and tools.any) then
        if record then record.live, record.ring = nil, nil end
        return
    end
    if not record then
        record = NewRecord()
        hooks[frame] = record
        -- Never replace the native AddMessage: post-hook its elevation barrier.
        hooksecurefunc(frame, "AddMessage", MessageAdded)
    end
    record.live, record.ring, record.wakeOnly = true, nil, combatLog
    if combatLog then return end
    local key = tools.history and HistoryKey(frame)
    if not key then return end
    record.ring = HistoryRing(key)
    if record.replayed ~= key then
        record.replayed = key
        Dispatch(HistoryReplay, frame, record.ring)
    end
end

function C.MessagesDisable()
    for _, record in pairs(hooks) do record.live, record.ring = nil, nil end
    for name in pairs(members) do members[name] = nil end
end

------------------------------------------------------------------ links and events
-- Clicked "msufurl" links come straight here: SetItemRef asks LinkUtil
-- first and stops once a handler answered, so neither the item tooltip nor
-- a shift-click insertion ever sees them. The handler cannot be removed;
-- links already in a window keep opening the copy box after Disable.
local function OpenURL(_, _, linkData)
    local url = PublicText(linkData.options)
    if url then C.ShowURL(url) end
end
LinkUtil.RegisterLinkHandler("msufurl", OpenURL)

function C.MessageRoster()
    for name in pairs(members) do members[name] = nil end
    if not tools.names then return end
    local raid = IsInRaid()
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 0, count do
        local unit = i == 0 and "player" or (raid and "raid" or "party") .. i
        local name = PublicText(UnitName(unit))
        local _, class = UnitClass(unit)
        local hex = name and C.ClassHex(class)
        if hex then members[name] = hex end
    end
end

local function WhisperSound()
    local c = M.config
    if c.whisperSound ~= "" then
        PlaySoundFile(c.whisperSound, "Master")
    elseif c.whisperSoundKit > 0 then
        PlaySound(c.whisperSoundKit, "Master")
    end
end

function C.MessagesRefresh(self)
    local c, context = self.config, self.context
    C.CompileMessages(c)
    if tools.names then
        C.ListenInCombat(context, "GROUP_ROSTER_UPDATE", C.MessageRoster)
    else
        context:RemoveEvent("GROUP_ROSTER_UPDATE")
    end
    C.MessageRoster()
    if c.whisperSound ~= "" or c.whisperSoundKit > 0 then
        C.ListenInCombat(context, "CHAT_MSG_WHISPER", WhisperSound)
    else
        context:RemoveEvent("CHAT_MSG_WHISPER")
    end
end
