local _, P = ...
local S = P.Suite
local C = P.Chat

local EVENT = "CHAT_MSG_CHANNEL"
local RECENT_LIMIT, DELIVERY_LIMIT = 512, 64
local PHRASE_LIMIT, MESSAGE_LIMIT = 32, 2048
local PublicText, Finite = S.PublicText, S.Finite
local rules, playerGUID

-- The filter runs once per native frame, including frames that later decide
-- they do not display this channel. Keep the decision keyed by Blizzard's
-- delivery ID so only a distinct delivery can count as a repeat.
local decisions, deliveryIDs, deliveryCursor = {}, {}, 0

-- Keep original strings and reuse the rows. The text index avoids constructing
-- a composite string for each delivery, and the ring bounds memory on busy realms.
local recentByText, recentRows, recentCursor = {}, {}, 0

local function RememberDecision(lineID, discard)
    deliveryCursor = deliveryCursor % DELIVERY_LIMIT + 1
    local oldID = deliveryIDs[deliveryCursor]
    if oldID then decisions[oldID] = nil end
    deliveryIDs[deliveryCursor], decisions[lineID] = lineID, discard
    return discard
end

local function RecordText(text, sender, channel, now)
    recentCursor = recentCursor % RECENT_LIMIT + 1
    local row = recentRows[recentCursor]
    if row.text then
        local previous, nextRow = row.previous, row.nextRow
        if previous then previous.nextRow = nextRow else recentByText[row.text] = nextRow end
        if nextRow then nextRow.previous = previous end
    end
    local first = recentByText[text]
    row.text, row.sender, row.channel, row.time = text, sender, channel, now
    row.previous, row.nextRow = nil, first
    if first then first.previous = row end
    recentByText[text] = row
end

local function IsRepeat(text, sender, channel)
    local now = GetTime()
    local row = recentByText[text]
    while row and now - row.time < rules.seconds do
        if row.sender == sender and row.channel == channel then return true end
        row = row.nextRow
    end
    RecordText(text, sender, channel, now)
    return false
end

-- Both clients call this before the chat frame formats the event. The registry
-- skips inaccessible text, and the fields used here are checked independently.
local function Filter(_, _, text, sender, _, channel, _, _, _, _, baseName, _, lineID, guid)
    if not rules or not Finite(lineID) then return false end
    local hasID = lineID > 0
    local cached
    if hasID then cached = decisions[lineID] end
    -- A cached keep never needs the payload. A cached discard still checks
    -- that this frame received public arguments.
    if cached == false then return false end
    if rules.scoped then
        if not PublicText(baseName) then return false end
        if cached == nil and not rules.channels[baseName:lower()] then
            return hasID and RememberDecision(lineID, false) or false
        end
    end
    if not PublicText(text) or #text > MESSAGE_LIMIT or not PublicText(sender)
        or not PublicText(guid) or not PublicText(channel) then
        return false
    end
    if not playerGUID then playerGUID = PublicText(UnitGUID("player")) end
    if not playerGUID or guid == playerGUID then return false end
    if cached then return true end
    for i = 1, #rules.phrases do
        if text:find(rules.phrases[i]) then
            return not hasID or RememberDecision(lineID, true)
        end
    end
    -- A delivery without a usable ID can still match a phrase. It cannot be
    -- compared for repeats because native windows would count as new messages.
    if hasID then
        return RememberDecision(lineID, rules.seconds > 0 and IsRepeat(text, guid, channel))
    end
    return false
end

local function FoldLetter(letter)
    return "[" .. letter:lower() .. letter:upper() .. "]"
end

local function CompilePhrases(source)
    local phrases, seen = {}, {}
    for entry in source:gmatch("[^;\r\n]+") do
        local phrase = entry:match("^%s*(.-)%s*$")
        local key = phrase:lower()
        if phrase ~= "" and #phrase <= MESSAGE_LIMIT and not seen[key] then
            -- Escape pattern punctuation first and fold only ASCII letters.
            -- The incoming text stays untouched, including multibyte letters.
            local pattern = phrase:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("[A-Za-z]", FoldLetter)
            phrases[#phrases + 1] = pattern
            seen[key] = true
            if #phrases == PHRASE_LIMIT then break end
        end
    end
    return phrases
end

local function CompileChannels(source)
    local channels = {}
    for entry in source:gmatch("[^,;\r\n]+") do
        local name = entry:match("^%s*(.-)%s*$")
        if name ~= "" then channels[name:lower()] = true end
    end
    return channels
end

local function ClearMemory()
    wipe(decisions)
    wipe(deliveryIDs)
    wipe(recentByText)
    for i = 1, #recentRows do wipe(recentRows[i]) end
    deliveryCursor, recentCursor = 0, 0
end

function C.SpamFilterDisable()
    if not rules then return end
    rules, playerGUID = nil, nil
    ChatFrameUtil.RemoveMessageEventFilter(EVENT, Filter)
    wipe(recentRows)
    ClearMemory()
end

function C.SpamFilterRefresh(self)
    local config = self.config
    if not config.spamFilter then
        C.SpamFilterDisable()
        return
    end

    local phraseText, channelText = config.spamPhrases or "", config.spamChannels or ""
    local seconds = config.spamRepeatSeconds or 0
    if rules and rules.phraseText == phraseText and rules.channelText == channelText
        and rules.seconds == seconds then
        return
    end
    local phrases, channels = CompilePhrases(phraseText), CompileChannels(channelText)
    local scoped = channelText:find("%S") ~= nil
    if (#phrases == 0 and seconds <= 0) or (scoped and not next(channels)) then
        C.SpamFilterDisable()
        return
    end
    local registered = rules ~= nil
    if seconds <= 0 then wipe(recentRows) end
    ClearMemory()
    if seconds > 0 and #recentRows == 0 then
        for i = 1, RECENT_LIMIT do recentRows[i] = {} end
    end
    rules = { phrases = phrases, phraseText = phraseText, seconds = seconds,
        channels = channels, channelText = channelText, scoped = scoped }
    playerGUID = PublicText(UnitGUID("player"))
    if not registered then ChatFrameUtil.AddMessageEventFilter(EVENT, Filter) end
end
