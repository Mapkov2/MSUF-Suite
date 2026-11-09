local _, P = ...
local S = P.Suite
local MODULE = "keywordAlerts"
local MAX_RULES, MAX_PHRASE, MAX_HITS = 20, 80, 100
local MAX_CHANNEL, MAX_MEDIA_NAME, MAX_SCOPES = 128, 116, 8
local CHANNEL_SEPARATOR = "\31"
local CHANNEL_PATTERN = "[^" .. CHANNEL_SEPARATOR .. "]+"
local EVENT_OPTIONS = { inCombat = true }
local DEFAULT, NAMED, MEDIA = "", "channel:", "lsm:"
local INSTANCE = "instance"
local EVENTS = { CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party", CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid", CHAT_MSG_GUILD = "guild",
    CHAT_MSG_SAY = "say", CHAT_MSG_CHANNEL = "channels",
    CHAT_MSG_INSTANCE_CHAT = INSTANCE, CHAT_MSG_INSTANCE_CHAT_LEADER = INSTANCE }
local CHANNELS = {
    { key = DEFAULT, label = "Use default channels" }, { key = "party", label = "Party" },
    { key = "raid", label = "Raid" }, { key = "guild", label = "Guild" },
    { key = "say", label = "Nearby speech" }, { key = "channels", label = "All public channels" },
}
local SOUNDS = {
    { key = DEFAULT, label = "Use default sound" }, { key = "none", label = "None" },
    { key = "raid", label = "Raid warning", kit = "RAID_WARNING" },
    { key = "ready", label = "Ready check", kit = "READY_CHECK" },
}
local function ByKey(entries)
    local result = {}
    for _, entry in ipairs(entries) do result[entry.key] = entry end
    return result
end
local channelByKey, soundByKey = ByKey(CHANNELS), ByKey(SOUNDS)
local M = { phrases = {}, routes = {}, publicNames = {}, hits = {}, hitCount = 0, hitNext = 1, hitSerial = 0 }

local function Trim(text) return text:match("^%s*(.-)%s*$") end
local function Characters(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end
local function ValidField(text, maxBytes)
    return text ~= "" and #text <= maxBytes and not text:find("[%c|]")
end
local function NamedChannel(key)
    local name = key:match("^" .. NAMED .. "(.+)$")
    return name and ValidField(name, MAX_CHANNEL) and name or nil
end
local function MediaName(key)
    local name = key:match("^" .. MEDIA .. "(.+)$")
    return name and ValidField(name, MAX_MEDIA_NAME) and name or nil
end

local function EncodedKey(key)
    return (key:gsub("[\t%%]", function(char) return char == "\t" and "%09" or "%25" end))
end

local function ParseChoices(encoded)
    local choices = {}
    for line in (encoded or ""):gmatch("[^\r\n]+") do
        local key, channels, sound = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)$")
        if key and not choices[key] then
            choices[key] = { channels = channels, sound = (soundByKey[sound] or MediaName(sound)) and sound or DEFAULT }
        end
    end
    return choices
end

local function ParsePhrases(words)
    local phrases, seen = {}, {}
    for text in words:gmatch("[^\r\n]+") do
        text = Trim(text)
        local key = text:lower()
        if #text > 0 and Characters(text) <= MAX_PHRASE and not seen[key] then
            seen[key] = true
            phrases[#phrases + 1] = { key = key, label = text }
            if #phrases == MAX_RULES then break end
        end
    end
    return phrases
end

local function SoundValue(key, defaultSound, shared)
    local entry = soundByKey[key]
    local name = MediaName(key)
    if entry and entry.kit then return SOUNDKIT[entry.kit] end
    if key == DEFAULT and defaultSound then return SOUNDKIT.RAID_WARNING end
    if name and shared then return nil, S.PublicText(shared:Fetch("sound", name, true)) end
end
local function Play(kit, path)
    if kit then
        PlaySound(kit, "Master")
    elseif path then
        PlaySoundFile(path, "Master")
    end
end

local function Route(phrase, scope)
    local rules = M.routes[scope]
    if not rules then
        rules = {}
        M.routes[scope] = rules
    end
    rules[#rules + 1] = phrase
    if scope == "party" or scope == "raid" then phrase[scope] = true end
end
local function ConfigureChannels(phrase, encoded, config)
    local selected, keys = {}, {}
    for key in encoded:gmatch(CHANNEL_PATTERN) do
        if not selected[key] and (channelByKey[key] or NamedChannel(key)) then
            selected[key] = true
            keys[#keys + 1] = key
            if #keys == MAX_SCOPES then break end
        end
    end
    phrase.channels = table.concat(keys, CHANNEL_SEPARATOR)
    phrase.defaultChannels = #keys == 0
    if phrase.defaultChannels then
        for i = 2, #CHANNELS do
            local scope = CHANNELS[i].key
            if config[scope] then Route(phrase, scope) end
        end
        phrase.allPublic = config.channels
    else
        for i = 1, #keys do
            local key = keys[i]
            local name = NamedChannel(key)
            if name then
                local lower = name:lower()
                if not phrase.publicNames then phrase.publicNames = {} end
                phrase.publicNames[lower] = true
                M.publicNames[lower] = true
                M.hasNamedPublic = true
            elseif key ~= "channels" then
                Route(phrase, key)
            end
        end
        phrase.allPublic = selected.channels
        if phrase.allPublic or phrase.publicNames then Route(phrase, "channels") end
    end
    M.anyPublic = M.anyPublic or phrase.allPublic
end

local function Compile()
    local config = M.config
    local choices = ParseChoices(config.phraseOptions)
    M.phrases = ParsePhrases(config.words)
    wipe(M.routes)
    wipe(M.publicNames)
    M.anyPublic, M.hasNamedPublic = false, false
    local shared
    for _, phrase in ipairs(M.phrases) do
        local choice = choices[EncodedKey(phrase.key)]
        phrase.sound = choice and choice.sound or DEFAULT
        ConfigureChannels(phrase, choice and choice.channels or DEFAULT, config)
        if phrase.party or phrase.raid then Route(phrase, INSTANCE) end
        if MediaName(phrase.sound) and shared == nil then shared = S.SharedMedia() or false end
        phrase.kit, phrase.path = SoundValue(phrase.sound, config.sound, shared)
        phrase.title = S.Text("Keyword: %s"):format(phrase.label)
        phrase.noticeKey = "keyword:" .. phrase.key
        phrase.nextAt = 0
    end
end

local function ClearHits()
    for _, entry in ipairs(M.hits) do wipe(entry) end
    M.hitNext, M.hitCount = 1, 0
end
local function AddHit(phrase, author, text, channel, scope)
    local entry = M.hits[M.hitNext]
    M.hitSerial = M.hitSerial + 1
    entry.id, entry.phrase = M.hitSerial, phrase.label
    entry.author, entry.text, entry.channel, entry.scope = author, text, channel, scope
    local stamp = GetServerTime()
    if not S.Finite(stamp) then stamp = nil end
    entry.stamp = stamp
    M.hitNext = M.hitNext % MAX_HITS + 1
    M.hitCount = math.min(M.hitCount + 1, MAX_HITS)
end

local function Notice(phrase, now, text, author, channel, scope)
    phrase.nextAt = now + M.config.cooldown
    local detail = S.Text("%s: %s"):format(author, text)
    AddHit(phrase, author, text, channel, scope)
    S.Print(S.Text("%s — %s"):format(phrase.title, detail))
    S.Notifications.Push(phrase.noticeKey, phrase.title, detail, MODULE)
    Play(phrase.kit, phrase.path)
end

local function PlainText(text)
    if not text:find("|", 1, true) then return text end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
end

local function Message(_, event, text, author, _, _, _, _, _, _, channelName)
    local scope = EVENTS[event]
    local phrases = M.routes[scope]
    if not phrases or not S.PublicText(text) or not S.PublicText(author) or #text > 2048 or #author > 160 then return end
    local channel, key
    if scope == "channels" then
        channel = S.PublicText(channelName)
        if channel and #channel > MAX_CHANNEL then channel = nil end
        if channel and M.hasNamedPublic then key = channel:lower() end
        if not M.anyPublic and not (key and M.publicNames[key]) then return end
    end
    local now = GetTime()
    if not S.Finite(now) then return end
    local plain, instanceScope
    for i = 1, #phrases do
        local phrase = phrases[i]
        local inChannel = scope ~= "channels" or phrase.allPublic or key and phrase.publicNames[key]
        if now >= phrase.nextAt and inChannel then
            if not plain then plain = PlainText(text):lower() end
            if plain:find(phrase.key, 1, true) then
                -- One native group query only when an instance message matches a phrase.
                if scope == INSTANCE and not instanceScope then
                    instanceScope = IsInRaid(LE_PARTY_CATEGORY_INSTANCE) and "raid" or "party"
                end
                local selected = phrase.defaultChannels and M.config or (instanceScope and phrase)
                local actualScope = instanceScope or scope
                if not selected or selected[actualScope] then
                    Notice(phrase, now, text, author, channel, actualScope)
                    return
                end
            end
        end
    end
end

-- The visible phrases stay in the original setting. The optional channel and
-- sound choices travel with the profile and are keyed by case-folded phrase.
local function SavePhrases(phrases)
    local words, encoded = {}, {}
    for _, phrase in ipairs(phrases) do
        words[#words + 1] = phrase.label
        if phrase.channels ~= DEFAULT or phrase.sound ~= DEFAULT then
            encoded[#encoded + 1] = table.concat({ EncodedKey(phrase.key), phrase.channels, phrase.sound }, "\t")
        end
    end
    return S.SetMany(MODULE, { words = table.concat(words, "\n"), phraseOptions = table.concat(encoded, "\n") })
end

local function Current()
    local config, words, options = M.config, M.config.words, M.config.phraseOptions
    return function()
        return M.config == config and config.words == words and config.phraseOptions == options
    end
end
local function CopyRules()
    local rules = {}
    for i, phrase in ipairs(M.phrases) do
        rules[i] = { key = phrase.key, label = phrase.label, channels = phrase.channels, sound = phrase.sound }
    end
    return rules
end
local function EditPhrase(_, row)
    local index = row and row.index
    local current = Current()
    local rules = CopyRules()
    S.ToolListWindow.Edit(M, { title = index and "Edit phrase" or "Add phrase",
        label = "Enter a word or phrase to watch for.", text = index and rules[index].label or "", maxBytes = MAX_PHRASE * 4,
        onSave = function(_, text)
            if not current() then return false, "Settings changed. Review again before applying." end
            text = Trim(text)
            if not ValidField(text, MAX_PHRASE * 4) or Characters(text) > MAX_PHRASE then
                return false, "Enter a phrase of 1 to 80 characters without formatting codes."
            end
            local key = text:lower()
            for i, phrase in ipairs(rules) do
                if i ~= index and phrase.key == key then return false, "That phrase is already watched." end
            end
            local phrase = index and rules[index] or { channels = DEFAULT, sound = DEFAULT }
            phrase.key, phrase.label = key, text
            rules[index or #rules + 1] = phrase
            return SavePhrases(rules)
        end })
end

local function RemovePhrase(_, row)
    local current, rules = Current(), CopyRules()
    S.Confirm("keywordRemovePhrase", { text = S.Text("Stop watching %s?"):format(row.label), callback = function()
        if not current() then return end
        table.remove(rules, row.index)
        SavePhrases(rules)
        S.ToolListWindow.Refresh(M)
    end })
end

function M:EditPhrases()
    local stillCurrent = Current()
    return S.ToolListWindow.Edit(self, { title = "Keyword notifications", label = "One phrase per line, up to 20 phrases.",
        text = self.config.words, maxBytes = 6500, multiline = true, onSave = function(_, text)
            if not stillCurrent() then
                return false, "Settings changed. Review again before applying."
            end
            local count = 0
            for line in text:gmatch("[^\r\n]+") do
                if Characters(line) > MAX_PHRASE then return false, "Each phrase may contain up to 80 characters." end
                count = count + 1
            end
            if count > MAX_RULES then return false, "Keep at most 20 phrases." end
            -- Existing bulk editing keeps its line semantics. Choices for
            -- removed phrases are dropped so re-adding one starts fresh.
            local options = self.config.phraseOptions
            if not options or options == "" then return S.Set(MODULE, "words", text) end
            local choices, encoded = ParseChoices(options), {}
            for _, phrase in ipairs(ParsePhrases(text)) do
                local key = EncodedKey(phrase.key)
                local choice = choices[key]
                if choice then encoded[#encoded + 1] = table.concat({ key, choice.channels, choice.sound }, "\t") end
            end
            return S.SetMany(MODULE, { words = text, phraseOptions = table.concat(encoded, "\n") })
        end })
end

local function ChannelLabel(key)
    local entry = channelByKey[key]
    return entry and S.Text(entry.label) or NamedChannel(key) or key
end
local function SoundLabel(key)
    local entry = soundByKey[key]
    return entry and S.Text(entry.label) or MediaName(key) or key
end
local function Choices(entries, current)
    local rows = {}
    for _, entry in ipairs(entries) do
        rows[#rows + 1] = { key = entry.key, label = S.Text(entry.label), checked = current == entry.key }
    end
    return rows
end
local function AddChoice(rows, seen, key, label, selected)
    if not seen[key] then
        seen[key] = true
        rows[#rows + 1] = { key = key, label = label, checked = selected == key }
    end
end
local function AddJoinedChannels(rows, seen, ...)
    for i = 2, select("#", ...), 3 do
        local name = S.PublicText((select(i, ...)))
        if name and ValidField(name, MAX_CHANNEL) then AddChoice(rows, seen, NAMED .. name, name) end
    end
end
local function ChannelChoices(encoded)
    local rows, seen, selected = Choices(CHANNELS, DEFAULT), {}, {}
    AddJoinedChannels(rows, seen, GetChannelList())
    for key in encoded:gmatch(CHANNEL_PATTERN) do
        selected[key] = true
        local name = NamedChannel(key)
        if name then AddChoice(rows, seen, key, name) end
    end
    for i = 2, #rows do rows[i].checked = selected[rows[i].key] == true end
    rows[1].checked = encoded == DEFAULT
    return rows, seen
end
local function SoundChoices(selected)
    local rows, seen = Choices(SOUNDS, selected), {}
    local shared = S.SharedMedia()
    local names = shared and shared:List("sound")
    if names then
        for _, value in ipairs(names) do
            local name = S.PublicText(value)
            if name and ValidField(name, MAX_MEDIA_NAME) then AddChoice(rows, seen, MEDIA .. name, name, selected) end
        end
    end
    local name = MediaName(selected)
    if name then AddChoice(rows, seen, selected, name, selected) end
    return rows
end
local function Selected(_, row) return row ~= nil end
local function Back() M:Open() end
local function ApplyChoice(rules, index, key, value, window)
    rules[index][key] = value
    local ok, why = SavePhrases(rules)
    if ok then
        Back()
    else
        window:SetStatus(S.Text(why))
    end
end

local function SelectedChannels(rows)
    local selected = {}
    for i = 2, #rows do
        if rows[i].checked then selected[#selected + 1] = rows[i].key end
    end
    return selected
end
local function ToggleChannel(rows, item)
    if item.key == DEFAULT then
        for i = 2, #rows do rows[i].checked = false end
        rows[1].checked = true
        return
    end
    local count = #SelectedChannels(rows)
    if item.checked then
        item.checked = false
        rows[1].checked = count == 1
    elseif count < MAX_SCOPES then
        item.checked = true
        rows[1].checked = false
    end
end
local function CustomChannel(rows, seen, current)
    S.ToolListWindow.Edit(M, { title = "Other channel", label = "Enter a public channel name without its number.",
        maxBytes = MAX_CHANNEL, valid = current, onSave = function(_, text)
            local name = Trim(text)
            if not ValidField(name, MAX_CHANNEL) then return false, "Enter a valid channel name." end
            local key = NAMED .. name
            for i = 2, #rows do
                if rows[i].key == key and rows[i].checked then return true end
            end
            if #SelectedChannels(rows) >= MAX_SCOPES then return false, "Choose up to 8 channels." end
            if not seen[key] then AddChoice(rows, seen, key, name) end
            for i = 2, #rows do
                if rows[i].key == key then ToggleChannel(rows, rows[i]) break end
            end
            return true
        end })
end
local function ChooseChannel(_, row)
    local current, rules = Current(), CopyRules()
    local rows, seen = ChannelChoices(row.channels)
    S.ToolListWindow.Open(M, { title = "Choose channels", rows = function() return rows end, valid = current,
        help = "Choose up to 8 channels. Use default channels to follow the settings in Chat Extras.",
        onSelect = function(_, item) ToggleChannel(rows, item) end,
        actions = {
            { label = "Apply", run = function(_, _, window)
                ApplyChoice(rules, row.index, "channels", table.concat(SelectedChannels(rows), CHANNEL_SEPARATOR), window)
            end },
            { label = "Other channel", run = function() CustomChannel(rows, seen, current) end },
            { label = "Back", run = Back },
        } })
end
local function ChooseSound(_, row)
    local current, rules, rows = Current(), CopyRules(), SoundChoices(row.sound)
    S.ToolListWindow.Open(M, { title = "Choose a sound", rows = function() return rows end, valid = current,
        actions = {
            { label = "Select", enabled = Selected, run = function(_, item, window)
                ApplyChoice(rules, row.index, "sound", item.key, window)
            end },
            { label = "Play", enabled = Selected, run = function(_, item)
                local kit, path = SoundValue(item.key, M.config.sound, S.SharedMedia())
                Play(kit, path)
            end },
            { label = "Back", run = Back },
        } })
end

local function RuleRows()
    local rows = {}
    for i, phrase in ipairs(M.phrases) do
        local labels = {}
        for key in phrase.channels:gmatch(CHANNEL_PATTERN) do labels[#labels + 1] = ChannelLabel(key) end
        local channels = #labels > 0 and table.concat(labels, ", ") or ChannelLabel(DEFAULT)
        local sound = SoundLabel(phrase.sound)
        rows[i] = { key = phrase.key, label = phrase.label, index = i, channels = phrase.channels, sound = phrase.sound,
            detail = S.Text("Channels: %s\nSound: %s"):format(channels, sound),
            search = phrase.label .. " " .. channels .. " " .. sound }
    end
    return rows
end

local function HitRows()
    local rows = {}
    for i = 1, M.hitCount do
        local hit = M.hits[(M.hitNext - i - 1) % MAX_HITS + 1]
        local channel = hit.channel or ChannelLabel(hit.scope)
        local time = S.Finite(hit.stamp) and date("%H:%M:%S", hit.stamp) or ""
        local text = S.Text("%s: %s"):format(hit.author, PlainText(hit.text))
        rows[i] = { key = hit.id, label = text, text = text,
            detail = S.Text("%s · %s · %s\n%s"):format(time, channel, hit.phrase, text),
            search = channel .. " " .. hit.phrase .. " " .. text }
    end
    return rows
end

local copy
local function CopyHit(_, row)
    if not copy then copy = S.QoLCopyDialog("Copy message", "Press Ctrl+C to copy the selected message.", 620) end
    S.QoLShowCopy(copy, row.text)
end

local function ShowMatches()
    local rows = HitRows()
    local function Refresh()
        rows = HitRows()
        S.ToolListWindow.Refresh(M)
    end
    S.ToolListWindow.Open(M, { title = "Keyword matches", rows = function() return rows end,
        help = "Review the latest 100 keyword matches from this session. Refresh to see new matches.",
        empty = "No keyword matches to show.",
        onHide = function() if copy then S.QoLClearCopy(copy) end end,
        actions = { { label = "Back", run = Back }, { label = "Refresh", run = Refresh },
            { label = "Copy message", enabled = Selected, run = CopyHit },
            { label = "Clear", run = function() ClearHits() Refresh() end } } })
end

function M:Open()
    return S.ToolListWindow.Open(self, { title = "Manage keyword alerts", rows = RuleRows,
        help = "Select a phrase to set its channel and sound. Rules using defaults follow the settings in Chat Extras.",
        empty = "Add a word or phrase to start watching chat.",
        tabs = { { key = "rules", label = "Rules" }, { key = "matches", label = "Matches" } },
        currentTab = function() return "rules" end,
        selectTab = function(_, key) if key == "matches" then ShowMatches() end end,
        actions = { { label = "Add phrase", enabled = function() return #M.phrases < MAX_RULES end,
                run = function() EditPhrase() end },
            { label = "Edit phrase", enabled = Selected, run = EditPhrase },
            { label = "Remove phrase", enabled = Selected, run = RemovePhrase },
            { label = "Channel", enabled = Selected, run = ChooseChannel },
            { label = "Sound", enabled = Selected, run = ChooseSound },
            { label = "Edit watched phrases", run = self.EditPhrases } } })
end

function M:Refresh()
    if self.profile and self.profile ~= self.config then
        ClearHits()
        S.ToolListWindow.Close(self)
    end
    self.profile = self.config
    Compile()
    if next(self.routes) and not self.hits[1] then
        for i = 1, MAX_HITS do self.hits[i] = {} end
    end
    for event, scope in pairs(EVENTS) do
        if self.routes[scope] then
            self.context:Event(event, Message, EVENT_OPTIONS)
        else
            self.context:RemoveEvent(event)
        end
    end
end
function M:Enable() self:Refresh() end
function M:Disable()
    ClearHits()
    wipe(self.hits)
    self.profile = nil
    S.ToolListWindow.Close(self)
end
S.Install(MODULE, M)
