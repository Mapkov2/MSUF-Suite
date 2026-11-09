local root = assert(arg[1], "repository root required")
local source = root .. "/MSUF_Suite_Chat/SpamFilter.lua"

local strict = arg[2] and assert(loadfile(arg[2]))()
if strict then strict.Install() end
local secret = strict and strict.New("string") or newproxy(true)
local secretID = strict and strict.New("number") or secret
if not strict then
    local meta = getmetatable(secret)
    local function Raise() error("secret value used", 2) end
    for _, method in ipairs({ "__index", "__concat", "__len", "__lt", "__le", "__tostring" }) do
        meta[method] = Raise
    end
end

local function IsSecret(value)
    if strict then return strict.IsSecret(value) end
    return rawequal(value, secret)
end
local suite = {
    PublicText = function(value)
        return not IsSecret(value) and type(value) == "string" and value ~= "" and value or nil
    end,
    Finite = function(value)
        return not IsSecret(value) and type(value) == "number" and value == value
    end,
}

local now, timeReads, guidReads = 10, 0, 0
GetTime = function() timeReads = timeReads + 1; return now end
UnitGUID = function(unit)
    assert(unit == "player")
    guidReads = guidReads + 1
    return "Player-self"
end
wipe = function(t) for k in pairs(t) do t[k] = nil end end

local filter, adds, removes = nil, 0, 0
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        assert(event == "CHAT_MSG_CHANNEL" and not filter, "unexpected duplicate or broad registration")
        filter, adds = callback, adds + 1
    end,
    RemoveMessageEventFilter = function(event, callback)
        assert(event == "CHAT_MSG_CHANNEL" and callback == filter, "wrong native filter removed")
        filter, removes = nil, removes + 1
    end,
}

local chat, self = {}, { config = {} }
assert(loadfile(source))("MSUF_Suite_Chat", { Suite = suite, Chat = chat })
local frameA, frameB = {}, {}
local function Deliver(frame, text, lineID, sender, channel, baseName, guid)
    return filter(frame, "CHAT_MSG_CHANNEL", text, sender or "Speaker-Realm", "", channel or "2. Trade", "", "",
        0, 2, baseName or "Trade", 0, lineID, guid or "Player-speaker")
end
local function Configure(enabled, phrases, repeatSeconds, channels)
    self.config.spamFilter = enabled
    self.config.spamPhrases = phrases
    self.config.spamRepeatSeconds = repeatSeconds
    self.config.spamChannels = channels
    chat.SpamFilterRefresh(self)
end

Configure(false, "boost", 20, "")
Configure(true, " ;\n ", 0, "")
Configure(true, "boost", 20, " ;, ")
assert(not filter and adds == 0 and guidReads == 0, "inactive rules did native work")

Configure(true, " BOOST ; 50% [off]\nFree carry", 20, " Trade, LookingForGroup ")
assert(filter and adds == 1 and guidReads == 1, "active rules failed to register exactly once")
assert(Deliver(frameA, "cheap bOoSt!", 100) and Deliver(frameB, "cheap bOoSt!", 100), "case-folded block differed by tab")
assert(Deliver(frameB, "deal: 50% [OFF] now", 101), "literal punctuation changed into a pattern")
assert(not Deliver(frameB, "deal: 50x off now", 102), "pattern punctuation blocked an unrelated line")
assert(Deliver(frameA, "take the Free Carry now", 103, nil, "4. LookingForGroup", "LookingForGroup"), "newline phrase")
assert(not Deliver(frameA, "boost", 104, nil, "1. General - Stormwind", "General"), "non-selected channel was filtered")
assert(not Deliver(frameA, "boost", 105, nil, nil, nil, "Player-self"), "own outgoing line was hidden")

-- Native filters run on several frames. A distinct ID counts as a repeat
-- once, even if another line is delivered between the two frame callbacks.
local before = timeReads
assert(not Deliver(frameA, "sale", 201))
assert(not Deliver(frameB, "other line", 202))
assert(not Deliver(frameB, "sale", 201))
assert(Deliver(frameB, "sale", 203))
assert(Deliver(frameA, "sale", 203))
assert(timeReads - before == 3, "fan-out re-read the clock or repeated a decision")
if not strict then
    local function WarmFanout()
        for _ = 1, 1000 do
            assert(not Deliver(frameA, "sale", 201) and Deliver(frameB, "sale", 203))
        end
    end
    local steps = 0
    debug.sethook(function() steps = steps + 1 end, "", 1)
    WarmFanout()
    debug.sethook()
    assert(steps <= 247000, ("cached keep + discard: %d instructions across 1000 callback pairs"):format(steps))

    local minimum
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local memory = collectgarbage("count")
        WarmFanout()
        local delta = collectgarbage("count") - memory
        collectgarbage("restart")
        minimum = math.min(minimum or delta, delta)
    end
    assert(minimum < 1, "cached deliveries allocated at least 1 KiB across 1000 callback pairs")
    print(("Cached keep + discard: %.1f instructions/pair, %.3f KiB/1000 pairs"):format(steps / 1000, minimum))
end

now = 20
assert(not Deliver(frameA, "sale", 204, nil, nil, nil, "Player-another"), "another sender was suppressed")
assert(not Deliver(frameA, "sale", 205, nil, "2. Trade - Another Zone"), "another channel was suppressed")
assert(Deliver(frameA, "sale", 206), "repeat inside interval was visible")
Configure(true, " BOOST ; 50% [off]\nFree carry", 20, " Trade, LookingForGroup ")
assert(adds == 1 and guidReads == 1 and Deliver(frameA, "sale", 207), "unchanged refresh reset repeat state")
now = 30
assert(not Deliver(frameA, "sale", 208), "suppressed repeats incorrectly extended the time window")

-- Even a previously cached discard must let an unreadable payload pass.
local watch = strict and strict.Watch(source, { strict = true })
before = timeReads
assert(not Deliver(frameA, secret, 100), "restricted message was discarded")
assert(not Deliver(frameA, "boost", 100, secret), "restricted sender was discarded")
assert(not Deliver(frameA, "boost", 100, nil, secret), "restricted channel was discarded")
assert(not Deliver(frameA, "boost", 100, nil, nil, secret), "restricted channel base name was discarded")
assert(not Deliver(frameA, "boost", 100, nil, nil, nil, secret), "restricted GUID was discarded")
assert(not Deliver(frameA, "boost", secretID), "restricted delivery ID did not fail open")
assert(timeReads == before, "restricted values triggered repeat work")
if watch then
    local violations = watch()
    assert(#violations == 0, table.concat(violations, "\n"))
end

assert(Deliver(frameA, "boost", 0), "public phrase must still work without a repeat ID")
assert(not Deliver(frameA, "sale", 0) and not Deliver(frameB, "sale", 0), "missing delivery ID counted as a repeat")
assert(timeReads == before, "unidentifiable delivery read the clock")

-- Fixed rings may evict old traffic, but must not mix identities or aliases.
Configure(true, "", 600, "")
assert(not Deliver(frameA, "ring sentinel", 300))
for i = 1, 530 do assert(not Deliver(frameA, "line " .. i, 300 + i)) end
assert(not Deliver(frameA, "ring sentinel", 900), "repeat buffer did not evict its oldest entry")
assert(Deliver(frameB, "ring sentinel", 901), "eviction damaged new repeat detection")
for i = 1, 530 do
    assert(not Deliver(frameA, "shared text", 1000 + i, nil, nil, nil, "Player-" .. i))
end
assert(not Deliver(frameA, "shared text", 2000, nil, nil, nil, "Player-1"), "evicted text collision was retained")
assert(Deliver(frameB, "shared text", 2001, nil, nil, nil, "Player-530"), "text index broke during ring reuse")

local stale = filter
Configure(false, "", 600, "")
assert(not filter and removes == 1, "disable left the native filter registered")
assert(not stale(frameA, "CHAT_MSG_CHANNEL", "boost", "Speaker-Realm"), "stale callback filtered while disabled")
Configure(true, "carry", 0, "")
assert(adds == 2 and not Deliver(frameA, "ring sentinel", 901), "disable retained decision or repeat state")
assert(Deliver(frameA, "carry", 901 + 1), "phrase-only configuration failed")
chat.SpamFilterDisable()
chat.SpamFilterDisable()
assert(not filter and removes == 2, "module disable was not idempotent")

print("Suite native chat spam filtering contract passed")
