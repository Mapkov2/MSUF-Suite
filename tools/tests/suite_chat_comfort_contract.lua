-- Chat comfort: Copy all, the scrollback limit, the typed lines kept between
-- sessions, channel sounds and the in-line keyword highlight (Chat's Copy,
-- History, Messages and Window files, with the catalog that declares them).
-- Chat text can be a restricted value on 12.1: SECRET stands for one and
-- raises on any string operation, so a gate that comes late fails here.
local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

------------------------------------------------------------------ client model
-- A frame as the dialogs and the chat code use it: the calls that matter keep
-- their state, every other call does nothing.
local NO_OPS = { "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameStrata", "SetFrameLevel",
    "EnableMouse", "SetClampedToScreen", "SetMovable", "StartMoving", "StopMovingOrSizing", "RegisterForDrag",
    "SetColorTexture", "SetHeight", "SetWidth", "SetFont", "SetTextColor", "SetJustifyH", "SetWordWrap",
    "SetMaxLines", "SetAutoFocus", "SetVertexColor", "SetTexture", "SetAlpha", "SetMultiLine" }
local function Widget(parent)
    local widget = { parent = parent, shown = true, scripts = {}, text = "" }
    for _, name in ipairs(NO_OPS) do widget[name] = function() end end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:Show() self.shown = true end
    function widget:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function widget:IsShown() return self.shown end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:SetFocus() self.focused = true end
    function widget:ClearFocus() self.focused = false end
    function widget:HighlightText() self.highlighted = true end
    function widget:CreateTexture() return Widget(self) end
    function widget:CreateFontString() return Widget(self) end
    return widget
end
UIParent = Widget()
local function CreateFrame(_, _, parent, template)
    local frame = Widget(parent)
    -- Blizzard's InputScrollFrameTemplate (InputBoxTemplates.xml).
    if template == "InputScrollFrameTemplate" then frame.CharCount, frame.EditBox = Widget(frame), Widget(frame) end
    return frame
end

local hooked = {}
-- A post-hook on a method of one object. AddMessage keeps the chat frame's own
-- list; any other method is wrapped. Only objects are hooked, never a global.
hooksecurefunc = function(target, method, callback)
    assert(type(target) == "table" and type(method) == "string", "hooked " .. tostring(target) .. ", not one object")
    hooked[target] = (hooked[target] or 0) + 1
    if method == "AddMessage" then
        target.securePostHooks[#target.securePostHooks + 1] = callback
        return
    end
    local native = target[method]
    assert(type(native) == "function", method .. " is not a method of the hooked object")
    target[method] = function(self, ...)
        native(self, ...)
        callback(self, ...)
    end
end

local function EditBox()
    local box = { history = {} }
    function box:AddHistoryLine(text) self.history[#self.history + 1] = text end
    return box
end

-- A chat window: lines[1] is the oldest (ScrollingMessageFrame:GetMessageInfo)
-- and SetMaxLines keeps the newest lines it already holds
-- (CircularBufferMixin:SetMaxNumElements). BackFillMessage adds behind the
-- oldest line while there is room.
local function ChatFrame(id, maxLines)
    local frame = { id = id, lines = {}, payloads = {}, max = maxLines or 128, infoCalls = 0,
        securePostHooks = {}, editBox = EditBox() }
    function frame:GetName() return "ChatFrame" .. self.id end
    function frame:GetID() return self.id end
    function frame:GetFrameLevel() return 1 end
    function frame:GetMaxLines() return self.max end
    function frame:SetMaxLines(limit)
        self.limitCalls = (self.limitCalls or 0) + 1
        while #self.lines > limit do
            table.remove(self.lines, 1)
            table.remove(self.payloads, 1)
        end
        self.max = limit
    end
    function frame:GetNumMessages() return #self.lines end
    function frame:GetMessageInfo(index)
        self.infoCalls = self.infoCalls + 1
        return self.lines[index]
    end
    function frame:AddMessage(text, ...)
        if #self.lines >= self.max then
            table.remove(self.lines, 1)
            table.remove(self.payloads, 1)
        end
        self.lines[#self.lines + 1] = text
        self.payloads[#self.lines] = { n = select("#", ...), ... }
        for i = 1, #self.securePostHooks do self.securePostHooks[i](self, text, ...) end
    end
    function frame:BackFillMessage(text, ...)
        if #self.lines >= self.max then return end
        table.insert(self.lines, 1, text)
        table.insert(self.payloads, 1, { n = select("#", ...), ... })
    end
    function frame:TransformMessages(predicate, transform)
        self.transforms = (self.transforms or 0) + 1
        for index, text in ipairs(self.lines) do
            local payload = self.payloads[index]
            if predicate(text, unpack(payload, 1, payload.n)) then
                local values = { transform(text, unpack(payload, 1, payload.n)) }
                self.lines[index] = values[1]
            end
        end
    end
    frame.historyBuffer = { CalculateElementIndex = function(_, index) return #frame.lines - index + 1 end }
    return frame
end
ChatFrame2 = ChatFrame(2)

local plays, now = {}, 100
PlaySound = function(kit, channel) plays[#plays + 1] = { kit = kit, channel = channel } end
PlaySoundFile = function(path, channel) plays[#plays + 1] = { file = path, channel = channel } end
GetTime = function() return now end
UnitName = function(unit) return unit == "player" and "Mapko" or "Other" end
local guidReads = 0
UnitGUID = function()
    guidReads = guidReads + 1
    return "Player-1-OWN"
end
UnitClass = function() return "Mage", "MAGE" end
GetChatWindowInfo = function(id) return id == 1 and "General" or "Other" end
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end

------------------------------------------------------------------ addon model
local config, catalogNS = Support.CatalogDefaults(root, "chat")
local Suite = {
    Public = function(value) return value ~= SECRET end,
    Number = function(value) return type(value) == "number" and value == value end,
    Text = function(text) return text end,
    RGB = function() return 1, 1, 1 end,
    SetFont = function() end,
    Dispatch = function(callback, ...) return callback(...) end,
    CreateFrame = CreateFrame,
    CreateTexture = function(parent) return parent:CreateTexture() end,
    CreateFontString = function(parent) return parent:CreateFontString() end,
}
Suite.Finite = function(value) return Suite.Number(value) and value > -math.huge and value < math.huge end
Suite.PublicText = function(value)
    if value ~= SECRET and type(value) == "string" and value ~= "" then return value end
end
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return false end,
    ChatSoundChannels = catalogNS.ChatSoundChannels, ChatLineLimits = catalogNS.ChatLineLimits }
assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("MSUF_Suite_Modules", { Suite = Suite })

local events, combatEvents, owned = {}, {}, {}
-- The context calls the chat code uses: events (also in combat) and owned
-- properties that go back when the setting returns to Blizzard's.
local context = {}
function context:Event(event, callback, options)
    events[event], combatEvents[event] = callback, Support.InCombatOption(options) or nil
end
function context:RemoveEvent(event) events[event], combatEvents[event] = nil, nil end
function context:Property(frame, getter, setter, value)
    local record = owned[frame] or {}
    owned[frame] = record
    record[setter] = record[setter] or { before = frame[getter](frame), getter = getter }
    if frame[getter](frame) ~= value then frame[setter](frame, value) end
    record[setter].applied = value
end
function context:RestoreProperty(frame, setter)
    local record = owned[frame] and owned[frame][setter]
    if not record then return end
    if frame[record.getter](frame) == record.applied then frame[setter](frame, record.before) end
    owned[frame][setter] = nil
end

local FILES = { "Shared.lua", "Unread.lua", "Copy.lua", "History.lua", "Messages.lua" }
-- A new session of the character: the files load again over the saved variable.
local function LoadChat(saved)
    MSUFSuiteChatHistory = saved
    LinkUtil = { RegisterLinkHandler = function() end }
    local private = { NS = NS, Suite = Suite }
    for _, file in ipairs(FILES) do assert(loadfile(root .. "/MSUF_Suite_Chat/" .. file))("MSUF_Suite_Chat", private) end
    local module = private.Chat.M
    module.config, module.context, module.active = config, context, true
    for event in pairs(events) do events[event], combatEvents[event] = nil, nil end
    return private.Chat, module
end
local C, M = LoadChat(nil)

local function Keys(set)
    local keys = {}
    for key in pairs(set) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

------------------------------------------------------------------ catalog
do
    local rules = catalogNS.SuiteCatalog.chat.rules
    eq(config.maxLines, 1, "the scrollback defaults to Blizzard's")
    eq(#rules.maxLines.choices, #catalogNS.ChatLineLimits + 1, "one limit per later choice")
    for _, key in ipairs({ "saveInputHistory", "highlightKeywords", "highlightOwnName" }) do
        eq(config[key], false, key .. " must default off")
    end
    eq(config.highlightWords, "", "the chat-owned keyword list starts empty")
    eq(rules.highlightWords.section, "highlight", "the keyword list belongs to the chat module")
    eq(catalogNS.ChatSoundChannels[1].kit, "whisperSoundKit", "the whisper sound kept its setting")
    eq(catalogNS.ChatSoundChannels[1].file, "whisperSound", "the whisper file kept its setting")
    local expected = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT" }
    for index, channel in ipairs(catalogNS.ChatSoundChannels) do
        eq(channel.events[1], expected[index], "channel " .. index)
        eq(config[channel.kit], 0, channel.kit .. " must default to silence")
        eq(config[channel.file], "", channel.file .. " must default to silence")
        assert(rules[channel.kit] and rules[channel.file], channel.label .. " has no settings")
    end
    eq(#catalogNS.ChatSoundChannels, #expected, "the channel list")
end

------------------------------------------------------------------ copy all
do
    config.copyMessages = true
    local frame = ChatFrame(1)
    for _, line in ipairs({ "|cffff0000Alice|r: hello |Hplayer:Bob|h[Bob]|h", SECRET, 7, "", "second public",
        "|cffffffffBob|r: last", SECRET }) do
        frame.lines[#frame.lines + 1] = line
    end
    local visual = {}
    C.ApplyCopyButton(M, visual, frame, 24)
    C.ApplyCopyButton(M, visual, frame, 24)
    eq(frame.infoCalls, 0, "the copy button read the buffer before any click")
    visual.copyButton.scripts.OnClick(visual.copyButton)
    local panel = M.copyDialog
    local chooserReads = frame.infoCalls
    assert(chooserReads <= 100, "the chooser reads at most the newest 100 lines")
    assert(panel.copyAll and panel.copyAll:IsShown(), "the dialog has no Copy all action")
    assert(not panel.allView, "the Copy all view exists before it is asked for")
    panel.copyAll.scripts.OnClick(panel.copyAll)
    eq(frame.infoCalls, chooserReads + #frame.lines, "Copy all reads the buffer once, on the click")
    local view = panel.allView
    eq(view.EditBox.text, "Alice: hello [Bob]\nsecond public\nBob: last",
        "Copy all keeps the public lines, oldest first, as plain text")
    assert(view:IsShown() and view.EditBox.focused and view.EditBox.highlighted, "the text is not selected for Ctrl+C")
    assert(not panel.edit:IsShown(), "the one-line box stays over the Copy all view")
    for _, row in ipairs(panel.rows) do assert(not row:IsShown(), "a chooser row stays over the Copy all view") end
    eq(panel.hint.text, "Every line is selected, press Ctrl+C", "hint")
    -- Closing, however it happens, forgets the text and brings the chooser back.
    panel.close.scripts.OnClick(panel.close)
    eq(view.EditBox.text, "", "a closed dialog kept the chat text")
    assert(not view:IsShown() and panel.edit:IsShown(), "closing left the Copy all view open")
    visual.copyButton.scripts.OnClick(visual.copyButton)
    assert(panel.rows[3]:IsShown() and not panel.rows[4]:IsShown(), "reopening did not list the three public lines")
    panel.copyAll.scripts.OnClick(panel.copyAll)
    view.EditBox.scripts.OnEscapePressed(view.EditBox)
    eq(view.EditBox.text, "", "Escape in the Copy all box kept the chat text")
    assert(not panel:IsShown(), "Escape in the Copy all box left the dialog open")
    -- A URL replaces the Copy all view and offers no Copy all.
    visual.copyButton.scripts.OnClick(visual.copyButton)
    panel.copyAll.scripts.OnClick(panel.copyAll)
    C.ShowURL("https://example.org/x")
    assert(not view:IsShown() and panel.edit:IsShown() and not panel.copyAll:IsShown(), "the URL dialog kept Copy all")
    eq(panel.edit.text, "https://example.org/x", "URL")
    -- Only restricted lines: nothing to copy, nothing shown.
    local hidden = ChatFrame(3)
    hidden.lines = { SECRET, SECRET }
    visual.copyButton.chatFrame = hidden
    visual.copyButton.scripts.OnClick(visual.copyButton)
    panel.copyAll.scripts.OnClick(panel.copyAll)
    assert(not view:IsShown(), "Copy all opened for a window without a public line")
    eq(panel.hint.text, "No recent messages to copy", "empty hint")
end

------------------------------------------------------------------ scrollback limit
do
    local window = ChatFrame(1)
    config.maxLines = 1
    C.ApplyLineLimit(M, window)
    eq(window.limitCalls, nil, "Keep Blizzard's setting touched the window")
    local choice = 3
    config.maxLines = choice
    C.ApplyLineLimit(M, window)
    eq(window.max, catalogNS.ChatLineLimits[choice - 1], "the chosen limit")
    C.ApplyLineLimit(M, ChatFrame2)
    eq(ChatFrame2.limitCalls, nil, "the combat log keeps Blizzard_CombatLog's limit")
    config.maxLines = 1
    C.ApplyLineLimit(M, window)
    eq(window.max, 128, "choosing Blizzard's setting again hands its limit back")

    -- A new session over a full saved ring: the limit comes first, so the
    -- replay fills the larger room and the session's own lines stay in front.
    config.saveHistory, config.historyLines = true, 200
    local saved = { tabs = {}, clock = 0 }
    C, M = LoadChat(saved)
    C.MessagesRefresh(M)
    local first = ChatFrame(1)
    C.ApplyMessages(M, first)
    for i = 1, 200 do first:AddMessage("old " .. i) end
    local function NewSession(limit)
        config.maxLines = limit
        C, M = LoadChat(saved)
        C.MessagesRefresh(M)
        local window = ChatFrame(1)
        for i = 1, 5 do window:AddMessage("new " .. i) end
        C.ApplyLineLimit(M, window)
        C.ApplyMessages(M, window)
        return window
    end
    local plain = NewSession(1)
    eq(#plain.lines, 128, "without a limit Blizzard's 128 lines hold only part of the ring")
    local roomy = NewSession(2)
    eq(#roomy.lines, 205, "the larger limit lost saved history")
    eq(roomy.lines[1], "old 1", "oldest saved line")
    eq(roomy.lines[200], "old 200", "newest saved line")
    eq(roomy.lines[201], "new 1", "the session's own lines sit in front of the saved ones")
    eq(roomy.lines[205], "new 5", "newest line")
    -- Raising the limit on a window that already shows lines drops none.
    config.maxLines = 4
    C.ApplyLineLimit(M, roomy)
    eq(#roomy.lines, 205, "a raised limit dropped lines")
    -- The limit is set before the ring replays (Window.lua is not loaded here).
    local handle = assert(io.open(root .. "/MSUF_Suite_Chat/Window.lua", "rb"))
    local window = handle:read("*a")
    handle:close()
    local limit, messages = window:find("C.ApplyLineLimit(self, frame)", 1, true), window:find("C.ApplyMessages(self, frame)", 1, true)
    assert(limit and messages and limit < messages, "ApplyWindow must set the limit before it applies the messages")
    config.saveHistory, config.maxLines = false, 1
end

------------------------------------------------------------------ typed lines
do
    config.saveInputHistory = true
    local saved = { tabs = {}, clock = 0, input = { "hello", 7, "/w Bob hi", "" } }
    C, M = LoadChat(saved)
    local first = ChatFrame(1)
    C.ApplyInputHistory(M, first)
    eq(table.concat(first.editBox.history, "|"), "hello|/w Bob hi", "the saved lines come back, oldest first")
    eq(#saved.input, 4, "feeding the lines back recorded them again")
    eq(hooked[first.editBox], 1, "the input box hook")
    C.ApplyInputHistory(M, first)
    eq(hooked[first.editBox], 1, "a second pass hooked the box again")
    eq(#first.editBox.history, 2, "a second pass fed the lines again")
    saved.input = { "hello", "/w Bob hi" }

    for _, line in ipairs({ "typed once", "typed once", "/script print(1)", "/RUN x()", "/dump y", "  /Script z",
        "/scripts" }) do
        first.editBox:AddHistoryLine(line)
    end
    eq(table.concat(saved.input, "|"), "hello|/w Bob hi|typed once|/scripts",
        "typed lines: code and dump commands stay out, a repeat is one line")
    first.editBox:AddHistoryLine(SECRET)
    first.editBox:AddHistoryLine(string.rep("x", 1281))
    eq(#saved.input, 4, "a restricted or oversized line was kept")
    for i = 1, 60 do first.editBox:AddHistoryLine("line " .. i) end
    eq(#saved.input, 50, "at most 50 lines are kept")
    eq(saved.input[1], "line 11", "the oldest lines go first")
    eq(saved.input[50], "line 60", "the newest line is last")

    -- Each box has its own hook and gets every saved line.
    local second = ChatFrame(3)
    C.ApplyInputHistory(M, second)
    eq(#second.editBox.history, 50, "another window's box")
    eq(hooked[second.editBox], 1, "another window's hook")
    eq(second.editBox.history[50], "line 60", "newest last in the box")
    eq(#saved.input, 50, "feeding a second box recorded lines")

    -- The hook stays after it is switched off, and records nothing then.
    config.saveInputHistory = false
    first.editBox:AddHistoryLine("while off")
    M.active = false
    config.saveInputHistory = true
    first.editBox:AddHistoryLine("while disabled")
    M.active = true
    eq(saved.input[50], "line 60", "a line was recorded while the module or the setting was off")
    first.editBox:AddHistoryLine("while on")
    eq(saved.input[50], "while on", "recording resumed")

    -- The next session, over the same saved variable.
    C, M = LoadChat(saved)
    local reloaded = ChatFrame(1)
    C.ApplyInputHistory(M, reloaded)
    eq(reloaded.editBox.history[50], "while on", "the lines of the last session were not kept")
    -- Off by default: no hook, nothing fed back.
    config.saveInputHistory = false
    C, M = LoadChat(saved)
    local plain = ChatFrame(1)
    C.ApplyInputHistory(M, plain)
    eq(hooked[plain.editBox], nil, "the default hooked the input box")
    eq(#plain.editBox.history, 0, "the default fed lines back")
    config.saveInputHistory = true
    C.ClearHistory()
    eq(saved.input, nil, "Clear saved chat history keeps the typed lines")
    config.saveInputHistory = false
end

------------------------------------------------------------------ channel sounds
do
    C, M = LoadChat(nil)
    C.MessagesRefresh(M)
    eq(#Keys(events), 0, "the default registered a chat event")
    local function Say(event, guid)
        events[event](M, event, "hello", "Bob", "", "", "", "", 0, 0, "", 0, 7, guid)
    end
    config.guildSoundKit, config.partySoundKit, config.raidSound = 3081, 3082, "Interface\\AddOns\\x\\raid.ogg"
    C.MessagesRefresh(M)
    eq(table.concat(Keys(events), " "), "CHAT_MSG_GUILD CHAT_MSG_PARTY CHAT_MSG_RAID", "only the chosen channels listen")
    for _, event in ipairs(Keys(events)) do assert(combatEvents[event] == true, event .. " must also arrive in combat") end
    -- A burst plays once; the next sound waits for the gap to pass.
    for _ = 1, 10 do Say("CHAT_MSG_GUILD", "Player-1-BOB") end
    eq(#plays, 1, "a burst of guild lines played more than once")
    eq(plays[1].kit, 3081, "guild kit")
    eq(plays[1].channel, "Master", "sound channel")
    now = now + 0.5
    Say("CHAT_MSG_GUILD", "Player-1-BOB")
    eq(#plays, 1, "the throttle let a second sound through")
    now = now + 0.5
    Say("CHAT_MSG_GUILD", "Player-1-BOB")
    eq(#plays, 2, "the throttle never ends")
    -- Each channel has its own throttle, and a custom file wins over the kit.
    Say("CHAT_MSG_PARTY", "Player-1-BOB")
    eq(plays[3].kit, 3082, "party kit")
    config.raidSoundKit = 99
    C.MessagesRefresh(M)
    Say("CHAT_MSG_RAID", "Player-1-BOB")
    eq(plays[4].file, "Interface\\AddOns\\x\\raid.ogg", "the file wins over the kit")
    -- The player's own line and a restricted guid.
    now = now + 5
    Say("CHAT_MSG_GUILD", "Player-1-OWN")
    eq(#plays, 4, "the player's own line played a sound")
    Say("CHAT_MSG_GUILD", "Player-1-BOB")
    eq(#plays, 5, "an own line used up the throttle")
    now = now + 5
    local reads = guidReads
    Say("CHAT_MSG_GUILD", SECRET)
    eq(#plays, 6, "a restricted guid silenced the channel")
    eq(guidReads, reads, "a restricted guid was compared")
    -- Whisper keeps its settings; a channel turned off stops listening.
    config.whisperSoundKit, config.bnWhisperSoundKit = 12867, 12868
    config.guildSoundKit = 0
    C.MessagesRefresh(M)
    assert(events.CHAT_MSG_WHISPER and events.CHAT_MSG_BN_WHISPER, "whisper channels did not listen")
    assert(not events.CHAT_MSG_GUILD and not events.CHAT_MSG_OFFICER and not events.CHAT_MSG_PARTY_LEADER,
        "a channel without a sound listened")
    Say("CHAT_MSG_WHISPER", "Player-1-BOB")
    eq(plays[#plays].kit, 12867, "whisper kit")
    for key in pairs(config) do
        if key:find("Sound", 1, true) then config[key] = type(config[key]) == "number" and 0 or "" end
    end
    C.MessagesRefresh(M)
    eq(#Keys(events), 0, "silencing every channel left an event registered")
end

------------------------------------------------------------------ keyword highlight
do
    local COLOR = "|cffffd100"
    C, M = LoadChat(nil)
    config.highlightKeywords, config.highlightWords = false, "LFM, wts ; tank"
    C.MessagesRefresh(M)
    local window = ChatFrame(9, 5000)
    window.isTemporary = true
    local function Reconfigure()
        C.MessagesRefresh(M)
        C.ApplyMessages(M, window)
    end
    local function Rendered(text)
        window:AddMessage(text)
        return window.lines[#window.lines]
    end
    Reconfigure()
    eq(Rendered("LFM heroic tank"), "LFM heroic tank", "the default highlighted a word")

    config.highlightKeywords = true
    Reconfigure()
    eq(Rendered("LFM heroic tank"), COLOR .. "LFM|r heroic " .. COLOR .. "tank|r", "hit")
    eq(Rendered("WTS lfm"), COLOR .. "WTS|r " .. COLOR .. "lfm|r", "capital letters do not matter, the text keeps its own")
    eq(Rendered("lfm lfm"), COLOR .. "lfm|r " .. COLOR .. "lfm|r", "two hits of one word")
    eq(Rendered("(tank), lfm."), "(" .. COLOR .. "tank|r), " .. COLOR .. "lfm|r.", "punctuation is a boundary")
    eq(Rendered("tanking xlfm lfmx 1lfm"), "tanking xlfm lfmx 1lfm", "only whole words are marked")
    eq(Rendered("nothing to see here"), "nothing to see here", "miss")
    eq(Rendered("LFM:\227\130\185LFM"), COLOR .. "LFM|r:\227\130\185" .. COLOR .. "LFM|r", "other scripts are boundaries")
    -- Escapes, links and URLs are never cut.
    config.highlightWords = "r, cff, ff0000, red, rtext, wts"
    Reconfigure()
    eq(Rendered("|cffff0000red|r text"), "|cffff0000red|r text", "a color escape was cut")
    eq(Rendered("|rtext and |n wts"), "|rtext and |n " .. COLOR .. "wts|r", "an escape's letter was marked")
    eq(Rendered("a final r"), "a final " .. COLOR .. "r|r", "a lone letter that is a word")
    config.highlightWords = "LFM, a.b, 1+1"
    config.linkURLs = true
    Reconfigure()
    eq(Rendered("|Hitem:19019|h[LFM Sword]|h LFM"), "|Hitem:19019|h[LFM Sword]|h " .. COLOR .. "LFM|r", "link payload")
    local linked = Rendered("see https://lfm.example/a.b LFM")
    eq(linked, "see |Hmsufurl:https://lfm.example/a.b|h[https://lfm.example/a.b]|h " .. COLOR .. "LFM|r",
        "a URL was marked inside")
    eq(Rendered("a.b axb 1+1 1x1"), COLOR .. "a.b|r axb " .. COLOR .. "1+1|r 1x1", "pattern characters are literal")
    config.linkURLs = false
    -- The formatter must be stable: a second pass leaves the line as it is.
    config.highlightWords = "LFM, tank"
    Reconfigure()
    local once = Rendered("LFM tank")
    eq(Rendered(once), once, "marking an already marked line changed it")
    local transforms = window.transforms
    NS.PrintChatMessage(window, "LFM now")
    eq(window.lines[#window.lines], COLOR .. "LFM|r now", "the prepared print")
    eq(window.transforms, transforms, "the highlight made the formatter unstable, so a print rewrote the buffer")
    -- A restricted line passes untouched, without a string operation.
    window:AddMessage(SECRET)
    eq(window.lines[#window.lines], SECRET, "a restricted line was rewritten")
    eq(window.transforms, transforms, "a restricted line was transformed")
    -- The player's own name, once, even when the list holds it too.
    config.highlightWords, config.highlightOwnName = "", true
    Reconfigure()
    eq(Rendered("hi mapko, Mapko!"), "hi " .. COLOR .. "mapko|r, " .. COLOR .. "Mapko|r!", "own name")
    config.highlightWords = "MAPKO"
    Reconfigure()
    eq(Rendered("Mapko"), COLOR .. "Mapko|r", "the name and the list marked one word twice")
    config.highlightOwnName, config.highlightColor = false, "12ab34"
    Reconfigure()
    eq(Rendered("mapko"), "|cff12ab34mapko|r", "color")
    config.highlightColor = "bad"
    Reconfigure()
    eq(Rendered("mapko"), COLOR .. "mapko|r", "an invalid color must fall back to the default")
    config.highlightColor = "ffd100"
    -- At most 20 words.
    local words = {}
    for i = 1, 25 do words[i] = "k" .. i end
    config.highlightWords = table.concat(words, ",")
    Reconfigure()
    eq(Rendered("k20 k21"), COLOR .. "k20|r k21", "the word list is not capped at 20")

    -- A line without a hit allocates nothing, with or without capitals.
    config.highlightWords = "LFM, wts, tank, boost"
    Reconfigure()
    local probe = ChatFrame(8)
    probe.isTemporary = true
    probe.AddMessage = function(self, text, ...)
        self.last = text
        for i = 1, #self.securePostHooks do self.securePostHooks[i](self, text, ...) end
    end
    C.ApplyMessages(M, probe)
    local misses = { "Hello World this is a Normal Line", "Mapko: Ready when you are, Everyone", "still no keyword here" }
    -- Memory taken while the collector is stopped, after a warm-up.
    local function Allocated(run)
        run()
        collectgarbage()
        collectgarbage("stop")
        local before = collectgarbage("count")
        run()
        local after = collectgarbage("count")
        collectgarbage("restart")
        return after - before
    end
    local function Miss()
        for i = 1, 2000 do probe:AddMessage(misses[i % #misses + 1]) end
    end
    local function Strings()
        for i = 1, 200 do local _ = tostring(i) .. "x" end
    end
    assert(Allocated(Strings) > 0, "the allocation probe measures nothing")
    eq(Allocated(Miss), 0, "a line without a keyword allocated")
end

print("Chat comfort: Copy all, scrollback limit, typed lines, channel sounds and keyword highlight passed")
