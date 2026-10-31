local _, P = ...
local NS, S = P.NS, P.Suite
local M = { phrases = {}, nextNotice = {} }
-- An instance group (random dungeon, raid finder, battleground) chats on its own events: it counts as
-- raid chat while that group is a raid and as party chat otherwise.
local INSTANCE = "instance"
local EVENTS = { CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party", CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid", CHAT_MSG_GUILD = "guild",
    CHAT_MSG_SAY = "say", CHAT_MSG_CHANNEL = "channels",
    CHAT_MSG_INSTANCE_CHAT = INSTANCE, CHAT_MSG_INSTANCE_CHAT_LEADER = INSTANCE }
-- The setting that decides whether a message of this event is watched.
local function Scope(event)
    local scope = EVENTS[event]
    if scope == INSTANCE then return IsInRaid(LE_PARTY_CATEGORY_INSTANCE) and "raid" or "party" end
    return scope
end
-- Whether the scope is watched at all; the instance chat needs party or raid chat.
local function Watches(config, scope)
    if scope == INSTANCE then return config.party or config.raid end
    return config[scope]
end
local function Characters(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end
local function Compile()
    wipe(M.phrases)
    wipe(M.nextNotice)
    local seen = {}
    for text in M.config.words:gmatch("[^\r\n]+") do
        text = text:match("^%s*(.-)%s*$")
        local key = text:lower()
        if #text > 0 and Characters(text) <= 80 and not seen[key] and #M.phrases < 20 then
            seen[key] = true
            M.phrases[#M.phrases + 1] = { key = key, label = text }
        end
    end
end
local function Message(_, event, text, author)
    if not S.PublicText(text) or not S.PublicText(author) or #text > 2048 or #author > 160 then return end
    local now = GetTime()
    if not S.Finite(now) then return end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):lower()
    for i = 1, #M.phrases do
        local phrase = M.phrases[i]
        if now >= (M.nextNotice[phrase.key] or 0) and plain:find(phrase.key, 1, true) then
            if not M.config[Scope(event)] then return end
            M.nextNotice[phrase.key] = now + M.config.cooldown
            local title = S.Text("Keyword: %s"):format(phrase.label)
            local detail = S.Text("%s: %s"):format(author, text)
            S.Print(S.Text("%s — %s"):format(title, detail))
            S.Notifications.Push("keyword:" .. phrase.key, title, detail, "keywordAlerts")
            if M.config.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
            return
        end
    end
end
function M:Open()
    local config, initial = self.config, self.config.words
    return S.ToolListWindow.Edit(self, { title = "Keyword notifications", label = "One phrase per line, up to 20 phrases.",
        text = self.config.words, maxBytes = 6500, multiline = true, onSave = function(_, text)
            if self.config ~= config or self.config.words ~= initial then
                return false, S.Text("Settings changed. Review again before applying.")
            end
            local count = 0
            for line in text:gmatch("[^\r\n]+") do
                if Characters(line) > 80 then return false, "Each phrase may contain up to 80 characters." end
                count = count + 1
            end
            if count > 20 then return false, "Keep at most 20 phrases." end
            return S.Set("keywordAlerts", "words", text)
        end })
end
function M:Refresh()
    Compile()
    for event, scope in pairs(EVENTS) do
        if Watches(self.config, scope) and #self.phrases > 0 then self.context:Event(event, Message, { inCombat = true })
        else
            self.context:RemoveEvent(event)
        end
    end
end
function M:Enable() self:Refresh() end
function M:Disable() wipe(self.nextNotice) S.ToolListWindow.Close(self) end
S.Install("keywordAlerts", M)
