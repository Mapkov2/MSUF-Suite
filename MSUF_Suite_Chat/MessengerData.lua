local _, P = ...
local S = P.Suite
local C = P.Chat
-- Whisper messenger conversations (module chatMessenger). This file only
-- holds the session's readable whispers: one tab per character or
-- Battle.net friend, each a bounded list of rendered lines. Nothing here is
-- saved. Character conversations of earlier sessions come from Chat's
-- existing whisper archive (History.lua, "Archive whispers by character
-- name"), read when a tab opens; the native line ID removes a line the
-- archive and this session both hold. A Battle.net account ID is only valid
-- for the session that delivered it, so Battle.net tabs never outlive it and
-- never become an archive or table key beyond it.
-- Restricted (secret) payloads are never read here: Messenger.lua filters
-- every event argument before a tab or line is made, and such a whisper
-- stays in Blizzard's own chat.
local D = { tabs = {}, byKey = {}, selected = nil, nativeOnly = 0 }
P.Messenger = D
local PublicText, Finite = S.PublicText, S.Finite
local TABS_MIN, TABS_MAX, LINES_MIN, LINES_MAX = 2, 12, 20, 200
local maxTabs, maxLines = 8, 100
local clock = 0
local OWN_COLOR, STAMP_COLOR, ARCHIVE_COLOR = "|cff9fc3e8", "|cff7d8590", "|cff8c8c8c"
local MAX_NAME_BYTES = 96

D.TABS_MAX = TABS_MAX

local function Clamp(value, low, high, fallback)
    if not Finite(value) then return fallback end
    return math.max(low, math.min(high, math.floor(value)))
end

local function Tick()
    clock = clock + 1
    return clock
end

------------------------------------------------------------------ names
-- A character's full name ("Name-Realm"). Whisper events and the native
-- player link carry the realm; a typed name without one is on the player's
-- realm. Names never hold spaces, bars or control characters.
function D.CharacterName(name)
    name = PublicText(name)
    if not name or #name > MAX_NAME_BYTES or name:find("[%s|%c]") then return nil end
    name = name:gsub("^%-+", ""):gsub("%-+$", "")
    if name == "" then return nil end
    if not name:find("-", 1, true) then
        local realmName = GetNormalizedRealmName
        local realm = realmName and PublicText(realmName())
        if realm then name = name .. "-" .. realm end
    end
    return name
end

local function CharacterKey(name)
    return "c:" .. name:lower()
end

-- The name a tab shows: the character without the player's own realm.
local function ShortName(name)
    local base, realm = name:match("^([^-]+)%-(.+)$")
    if not base then return name end
    local realmName = GetNormalizedRealmName
    local own = realmName and PublicText(realmName())
    return realm == own and base or name
end

------------------------------------------------------------------ tabs
local function Older(a, b)
    if (a.unread > 0) ~= (b.unread > 0) then return a.unread == 0 end
    return a.used < b.used
end

local function RemoveAt(index)
    local tab = table.remove(D.tabs, index)
    if not tab then return end
    D.byKey[tab.key] = nil
    tab.draft = nil
    if D.selected == tab then D.selected = D.tabs[math.min(index, #D.tabs)] end
end

-- Over the limit, the least recent read conversation closes first; one
-- with unread lines only when every other one has some as well. Its lines
-- remain in Blizzard's chat. Keep the selection when another tab can close.
local function Evict(keep)
    while #D.tabs > maxTabs do
        local index
        for i, tab in ipairs(D.tabs) do
            if not tab.pinned and tab ~= D.selected and tab ~= keep and (not index or Older(tab, D.tabs[index])) then
                index = i
            end
        end
        if not index then
            for i, tab in ipairs(D.tabs) do
                if not tab.pinned and tab ~= keep then index = i break end
            end
        end
        if not index then break end
        RemoveAt(index)
    end
end

local function NewTab(key, kind)
    local tab = { key = key, kind = kind, lines = {}, ids = {}, unread = 0, used = Tick() }
    D.tabs[#D.tabs + 1] = tab
    D.byKey[key] = tab
    if not D.selected then D.selected = tab end
    Evict(tab)
    return D.byKey[key]
end

-- The conversation with a character, opened when missing. An incoming
-- whisper (canonical) carries the server's spelling of the name, which a
-- typed name or the player's own line never replaces; its guid colors the
-- name by class once.
function D.CharacterTab(name, guid, canonical)
    local key = CharacterKey(name)
    local tab = D.byKey[key] or NewTab(key, "character")
    if not tab then return nil end
    if canonical or not tab.name then tab.name, tab.label = name, ShortName(name) end
    if not tab.classHex and PublicText(guid) and guid:sub(1, 7) == "Player-" then
        local _, class = GetPlayerInfoByGUID(guid)
        tab.classHex = C.ClassHex(class)
    end
    return tab
end

-- A Battle.net conversation, keyed by this session's account ID. label is
-- the client's protected name escape: it is only ever drawn, never compared.
function D.BattleNetTab(accountID, label)
    if not Finite(accountID) or accountID <= 0 or accountID % 1 ~= 0 then return nil end
    local key = "b:" .. string.format("%d", accountID)
    local tab = D.byKey[key] or NewTab(key, "bnet")
    if not tab then return nil end
    tab.accountID = accountID
    tab.label = PublicText(label) or tab.label or S.Text("Battle.net friend")
    return tab
end

function D.Close(tab)
    for index, open in ipairs(D.tabs) do
        if open == tab then return RemoveAt(index) end
    end
end

function D.CanPin(tab)
    if not tab or D.byKey[tab.key] ~= tab then return false end
    if tab.pinned then return true end
    local count = 0
    for _, open in ipairs(D.tabs) do
        if open.pinned then count = count + 1 end
    end
    return count < maxTabs - 1
end

function D.TogglePin(tab)
    if not D.CanPin(tab) then return end
    local index = 1
    for i, open in ipairs(D.tabs) do
        if open == tab then
            table.remove(D.tabs, i)
            break
        end
    end
    tab.pinned = not tab.pinned or nil
    if not tab.pinned then
        while D.tabs[index] and D.tabs[index].pinned do index = index + 1 end
    end
    table.insert(D.tabs, index, tab)
    D.Changed()
end

function D.CloseAll()
    for index = #D.tabs, 1, -1 do RemoveAt(index) end
    D.selected = nil
end

function D.Select(tab)
    if not tab or D.byKey[tab.key] ~= tab then return end
    D.selected = tab
    tab.used = Tick()
end

function D.MarkRead(tab)
    if tab then tab.unread = 0 end
end

function D.TotalUnread()
    local total = 0
    for _, tab in ipairs(D.tabs) do total = total + tab.unread end
    return total
end

------------------------------------------------------------------ lines
local function Trim(tab)
    local lines = tab.lines
    while #lines > maxLines do
        local old = table.remove(lines, 1)
        if old.id and tab.ids[old.id] == old then tab.ids[old.id] = nil end
    end
end

local function Speaker(tab, outgoing)
    if outgoing then return OWN_COLOR .. S.Text("You") .. "|r" end
    local label = tab.label or ""
    if tab.classHex then return "|cff" .. tab.classHex .. label .. "|r" end
    return label
end

-- A readable body as the line the window shows.
function D.Render(tab, body, outgoing)
    return STAMP_COLOR .. date("%H:%M") .. "|r " .. Speaker(tab, outgoing) .. ": " .. body
end

-- Adds one delivered whisper. lineID is the native line ID (a readable
-- number). The same ID again is no new line; one the archive showed first
-- (Chat may archive it before this event reaches the messenger) becomes the
-- live line in place. Returns true for a newly delivered line. Lines the
-- player cannot see raise unread.
function D.Receive(tab, body, outgoing, lineID, seen)
    local id = string.format("%d", lineID)
    local text = D.Render(tab, body, outgoing)
    local existing = tab.ids[id]
    if existing then
        if not existing.archived then return false end
        existing.text, existing.archived = text, nil
    else
        local entry = { id = id, text = text }
        tab.lines[#tab.lines + 1] = entry
        tab.ids[id] = entry
        Trim(tab)
    end
    tab.used = Tick()
    if not outgoing and not seen then tab.unread = tab.unread + 1 end
    if outgoing then tab.unread = 0 end
    return true
end

------------------------------------------------------------------ archive
-- Chat's whisper archive matches a tab by full character name.
local function Matcher(tab)
    local key = tab.key
    return function(peer)
        local name = D.CharacterName(peer)
        return name ~= nil and CharacterKey(name) == key
    end
end

-- Once per session and tab: the archived lines of the conversation go in
-- front of the live ones, oldest first, without the lines this session
-- already holds. Cold path: a tab opening or the window showing it.
function D.Seed(tab)
    if not tab or tab.seeded or tab.kind ~= "character" or not D.showArchive then return end
    tab.seeded = true
    local rows = C.WhisperLines(Matcher(tab), maxLines)
    if #rows == 0 then return end
    local merged = {}
    for _, row in ipairs(rows) do
        local id = PublicText(row.id)
        if not (id and tab.ids[id]) then
            local entry = { id = id, text = ARCHIVE_COLOR .. row.text .. "|r", archived = true }
            merged[#merged + 1] = entry
            if id then tab.ids[id] = entry end
        end
    end
    for _, entry in ipairs(tab.lines) do merged[#merged + 1] = entry end
    tab.lines = merged
    Trim(tab)
end

-- The most recent archived conversations as tabs, when none is open yet.
function D.RestoreRecent(count)
    if #D.tabs > 0 or not D.showArchive then return end
    for _, contact in ipairs(C.WhisperSnapshot()) do
        if #D.tabs >= math.min(count, maxTabs) then break end
        local name = D.CharacterName(contact.peer)
        if name then D.Seed(D.CharacterTab(name)) end
    end
end

-- Chat's "Clear saved chat history" also clears what the messenger showed
-- from it.
function D.ArchiveCleared()
    for _, tab in ipairs(D.tabs) do
        local kept = {}
        for _, entry in ipairs(tab.lines) do
            if entry.archived then
                if entry.id then tab.ids[entry.id] = nil end
            else
                kept[#kept + 1] = entry
            end
        end
        tab.lines = kept
        tab.seeded = nil
    end
    D.Changed()
end
C.WhisperArchiveCleared = D.ArchiveCleared

------------------------------------------------------------------ lifecycle
function D.Configure(config)
    maxTabs = Clamp(config.maxTabs, TABS_MIN, TABS_MAX, 8)
    maxLines = Clamp(config.maxLines, LINES_MIN, LINES_MAX, 100)
    D.showArchive = config.showArchive ~= false
    if not D.showArchive then D.ArchiveCleared() end
    for index, tab in ipairs(D.tabs) do
        if index >= maxTabs then tab.pinned = nil end
        Trim(tab)
    end
    Evict()
end

-- A switched-off messenger keeps no conversation.
function D.Reset()
    D.CloseAll()
    D.nativeOnly = 0
end

function D.Limits()
    return maxTabs, maxLines
end
