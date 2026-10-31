local _, P = ...
local NS, S = P.NS, P.Suite
-- Report to chat: the ranking of a window (its meter type and fight) as chat
-- lines, from the window's Settings menu. The client protects meter values in
-- combat and a protected value cannot be put into text, so a report waits for
-- the end of combat and sends nothing built from a protected value. The lines
-- go out one per tick of a context timer, so chat's flood control never drops
-- the tail and a disabled module stops at once.
local D = P.DamageMeter
local M = D.M
local Public, Finite = S.Public, S.Finite
local min, format = math.min, string.format
local REPORT_GAP = .3
local EMPTY = {}

local function Yes(value) return Public(value) and value == true end

------------------------------------------------------------------ channels
-- A player in a whisper-able target: the name chat addresses, else nil.
local function WhisperTarget()
    if not Yes(UnitIsPlayer("target")) or Yes(UnitIsUnit("target", "player")) or not Yes(UnitIsConnected("target")) then
        return nil
    end
    return S.PublicText((GetUnitName("target", true)))
end

-- Blizzard's own chat rules (ChatFrameEditBox.lua): a channel is usable while
-- its group or guild exists. usable() answers for right now.
local CHANNELS = {
    { chat = "SAY", global = "SAY_MESSAGE", english = "Say", usable = function() return true end },
    { chat = "PARTY", global = "PARTY_MESSAGE", english = "Party",
        usable = function() return Yes(IsInGroup(LE_PARTY_CATEGORY_HOME)) end },
    { chat = "RAID", global = "RAID_MESSAGE", english = "Raid",
        usable = function() return Yes(IsInRaid(LE_PARTY_CATEGORY_HOME)) end },
    { chat = "INSTANCE_CHAT", global = "INSTANCE_CHAT_MESSAGE", english = "Instance",
        usable = function() return Yes(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) end },
    { chat = "GUILD", global = "GUILD_MESSAGE", english = "Guild", usable = function() return Yes(IsInGuild()) end },
    { chat = "OFFICER", global = "OFFICER_MESSAGE", english = "Officer",
        usable = function() return Yes(IsInGuild()) and Yes(C_GuildInfo.IsGuildOfficer()) end },
    -- Its answer is the target's name.
    { chat = "WHISPER", english = "Whisper target", usable = WhisperTarget },
}

function D.ReportChannels()
    local list = {}
    for _, channel in ipairs(CHANNELS) do
        if channel.usable() then list[#list + 1] = channel end
    end
    return list
end

function D.ReportChannelName(channel)
    return S.BlizzardText(channel.global, channel.english)
end

-- What a channel answers for right now (nil: unusable, or no such channel).
local function ChannelAnswer(chat)
    for _, channel in ipairs(CHANNELS) do
        if channel.chat == chat then return channel.usable() end
    end
end

------------------------------------------------------------------ lines
-- The window's own number formatter writes into a row's value text. A bare
-- sink collects the text, so a report reads like the window and follows its
-- value format; the percent always shows, as in the breakdown.
local sink = { valueText = {} }
function sink.valueText:SetText(text) self.text = text end

local function ValueText(win, session, source)
    if win.meterType == D.TYPE.Deaths then
        local seconds = source.deathTimeSeconds
        return Finite(seconds) and seconds >= 0 and not win.overall and D.Clock(seconds) or ""
    end
    D.ClearMemo(sink)
    D.SetValueText(sink, win.meterType, source.totalAmount, source.amountPerSecond, session.totalAmount, true)
    return sink.valueText.text
end

-- The window's title, its pinned fight and the fight's length.
local function Header(win, session)
    local text = win.titleText or D.TypeName(win.meterType)
    if win.sessionID then
        text = format("%s - %s", text, format(S.BlizzardText("DAMAGE_METER_COMBAT_NUMBER", "Fight %d"), win.sessionID))
    end
    local duration = session.durationSeconds
    if Finite(duration) and duration > 0 then text = format("%s [%s]", text, D.Clock(duration)) end
    return text
end

-- A source the report can print: a readable name and readable amounts.
local function Readable(source)
    return type(source) == "table" and Public(source) and type(source.name) == "string" and Public(source.name)
        and Public(source.totalAmount) and Public(source.amountPerSecond) and Public(source.deathTimeSeconds)
end

-- The header and up to count ranked lines of the window's meter and fight,
-- fetched now: an empty list when there is nothing to say, nil when a value
-- is protected.
local function BuildLines(win, count)
    local session = D.FetchSession(win)
    if session == nil then return EMPTY end
    if not Public(session) or type(session) ~= "table" then return nil end
    local sources = session.combatSources
    if not Public(sources) or not Public(session.totalAmount) or not Public(session.durationSeconds) then return nil end
    local total = D.Count(sources)
    if total == 0 then return EMPTY end
    local lines = { Header(win, session) }
    for rank = 1, min(count, total) do
        local source = sources[rank]
        if not Readable(source) then return nil end
        local value = ValueText(win, session, source)
        local name = D.Short(source.name)
        lines[#lines + 1] = value ~= "" and format("%d. %s %s", rank, name, value) or format("%d. %s", rank, name)
    end
    return lines
end

------------------------------------------------------------------ sending
local function InInstance()
    local inside = IsInInstance()
    return Yes(inside)
end

-- Chat reads "|" as the start of an escape code and refuses a lone one (a Bar
-- value format or a "|" separator prints it): a literal bar goes out doubled.
local function Escaped(line) return (line:gsub("|", "||")) end

-- Sends the next line of the report in flight; true while lines remain. The
-- report leaves M.report before its line goes out and returns only when more
-- lines wait, so a send that raises cannot keep the next report from starting.
local function SendNext()
    local report = M.report
    M.report = nil
    if M.inCombat or NS.InCombat() then return false end
    if NS.ChatLocked() then
        S.Print(S.Text("Chat messages are blocked here right now; the report was not completed."))
        return false
    end
    report.sent = report.sent + 1
    C_ChatInfo.SendChatMessage(Escaped(report.lines[report.sent]), report.chat, nil, report.target)
    if report.sent >= #report.lines then return false end
    M.report = report
    return true
end

-- The context timer: one line per tick.
function D.ReportTick()
    if M.report and SendNext() then M.context:After(REPORT_GAP, D.ReportTick) end
end

function D.CancelReport()
    M.report = nil
    if M.context then M.context:Cancel(D.ReportTick) end
end

-- Reports win's ranking to a channel of D.ReportChannels(). Returns true when
-- it started sending. Refuses (with a note in the chat frame) in combat, while
-- a value is protected, for a channel that is gone and while chat is locked.
function D.SendReport(win, chat)
    if M.report then return false end
    if M.inCombat or NS.InCombat() then
        S.Print(S.Text("Available after combat"))
        return false
    end
    local answer = ChannelAnswer(chat)
    if not answer then
        S.Print(S.Text("That chat channel is not available right now."))
        return false
    end
    if NS.ChatLocked() then
        S.Print(S.Text("Chat messages are blocked here right now; the report was not sent."))
        return false
    end
    local lines = BuildLines(win, NS.DamageMeterReportLines[M.config.reportLines])
    if not lines then
        S.Print(S.Text("Available after combat"))
        return false
    end
    if #lines == 0 then
        S.Print(S.Text("There is nothing to report yet."))
        return false
    end
    M.report = { lines = lines, chat = chat, target = chat == "WHISPER" and answer or nil, sent = 0 }
    -- Say outside instances is limited to a hardware event, which only the
    -- click that chose it still holds: all of its lines go out now.
    if chat == "SAY" and not InInstance() then
        while SendNext() do end
    else
        D.ReportTick()
    end
    return true
end

------------------------------------------------------------------ menu
local function ReportChosen(data) D.SendReport(data.win, data.chat) end

-- The Report entry of a window's Settings menu: one choice per usable channel.
-- A threat window has no ranking to report.
function D.ReportMenu(root, win)
    local menu = root:CreateButton(S.Text("Report"))
    if win.meterType == D.THREAT then
        menu:SetEnabled(false)
        return
    end
    for _, channel in ipairs(D.ReportChannels()) do
        menu:CreateButton(D.ReportChannelName(channel), ReportChosen, { win = win, chat = channel.chat })
    end
end
