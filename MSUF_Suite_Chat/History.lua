local _, P = ...
local S = P.Suite
local C = P.Chat
-- Saved chat history (saveHistory), kept per character in the
-- SavedVariablesPerCharacter table MSUFSuiteChatHistory: one ring of the
-- newest lines for each permanent chat tab, keyed by window and tab title.
-- At most MAX_TABS rings stay; once more tabs need one, the ring used least
-- recently (a renamed or deleted tab) is dropped. A ring replays once per
-- session through BackFillMessage, so saved lines sit behind every line
-- this session added. Battle.net names (|K escapes) only resolve in the
-- session that received them: a saved line keeps such a link's text without
-- the link and shows a placeholder for the name.
local M = C.M
local MAX_TABS = 16
local MAX_TEXT = 8192
local PublicText, Finite = S.PublicText, S.Finite
-- gsub replacement text: a translated "%" must stay a percent sign.
local BATTLE_NET = S.Text("Battle.net friend"):gsub("%%", "%%%%")
local store

-- Saved variables arrive after the addon's files ran, so the table is opened
-- on first use (the module enables after its addon finished loading).
local function Store()
    if store then return store end
    local saved = _G.MSUFSuiteChatHistory
    if type(saved) ~= "table" or type(saved.tabs) ~= "table" or not Finite(saved.clock) then
        saved = { tabs = {}, clock = 0 }
        _G.MSUFSuiteChatHistory = saved
    end
    store = saved
    return saved
end

local function LineLimit()
    local value = M.config.historyLines
    return Finite(value) and math.max(20, math.min(1000, math.floor(value))) or 200
end

-- Keeps the newest lines when the configured size changed or the saved ring
-- does not hold together (the file belongs to the player).
local function Fit(ring, limit)
    local lines, count, nextIndex, size = ring.lines, ring.count, ring.next, ring.limit
    if size == limit and type(lines) == "table" and Finite(count) and count >= 0 and count <= limit
        and count % 1 == 0 and Finite(nextIndex) and nextIndex >= 1 and nextIndex <= limit
        and nextIndex % 1 == 0 then
        return
    end
    local rows, kept = {}, 0
    if Finite(size) and size >= 1 and size <= 1000 and size % 1 == 0 and type(lines) == "table"
        and Finite(count) and Finite(nextIndex) and nextIndex % 1 == 0 then
        for offset = math.min(limit, size, math.max(0, math.floor(count))), 1, -1 do
            local row = lines[(nextIndex - offset - 1) % size + 1]
            if type(row) == "table" and PublicText(row.text) then
                kept = kept + 1
                rows[kept] = row
            end
        end
    end
    ring.lines, ring.count, ring.limit, ring.next = rows, kept, limit, kept % limit + 1
end

local function DropLeastRecent(tabs)
    while true do
        local count, oldestKey, oldest = 0, nil, nil
        for key, ring in pairs(tabs) do
            count = count + 1
            local used = type(ring) == "table" and Finite(ring.used) and ring.used or 0
            if not oldest or used < oldest then oldestKey, oldest = key, used end
        end
        if count <= MAX_TABS then return end
        tabs[oldestKey] = nil
    end
end

-- The ring of one tab, sized to the current setting. Cold path: Window.lua
-- resolves it when a window is styled; the message hook only writes to it.
function C.HistoryRing(key)
    local saved = Store()
    local ring = saved.tabs[key]
    local created = type(ring) ~= "table"
    if created then
        ring = { lines = {}, count = 0, next = 1, limit = LineLimit() }
        saved.tabs[key] = ring
    end
    saved.clock = saved.clock + 1
    ring.used = saved.clock
    if created then DropLeastRecent(saved.tabs) end
    Fit(ring, LineLimit())
    return ring
end

-- A link whose target holds a |K escape gives up the link, keeping its text.
local function Unlink(target, label)
    if target:find("|K", 1, true) then return label end
end

local function Keepable(text)
    if not text:find("|K", 1, true) then return text end
    text = text:gsub("|H(.-)|h(.-)|h", Unlink)
    return (text:gsub("|K.-|k", BATTLE_NET))
end

-- Per added line: one row write. Rows are reused once the ring is full.
function C.HistoryStore(ring, text, r, g, b)
    if #text > MAX_TEXT then return end
    local index, lines = ring.next, ring.lines
    local row = lines[index]
    if type(row) ~= "table" then
        row = {}
        lines[index] = row
    end
    row.text = Keepable(text)
    row.r, row.g, row.b = Finite(r) and r or 1, Finite(g) and g or 1, Finite(b) and b or 1
    ring.next = index % ring.limit + 1
    if ring.count < ring.limit then ring.count = ring.count + 1 end
end

-- Newest first, each saved line goes behind the lines already shown, as far
-- as the window has room (a full window takes no back-filled line).
function C.HistoryReplay(frame, ring)
    local room = frame:GetMaxLines() - frame:GetNumMessages()
    local lines, size, newest = ring.lines, ring.limit, ring.next - 1
    for offset = 1, math.min(ring.count, room) do
        local row = lines[(newest - offset) % size + 1]
        if type(row) == "table" and PublicText(row.text) and #row.text <= MAX_TEXT then
            frame:BackFillMessage(row.text, Finite(row.r) and row.r or 1,
                Finite(row.g) and row.g or 1, Finite(row.b) and row.b or 1)
        end
    end
end

-- Empties this character's rings in place, so styled windows keep writing
-- to the rings they already hold.
function C.ClearHistory()
    local tabs = Store().tabs
    for key, ring in pairs(tabs) do
        if type(ring) == "table" then
            ring.lines, ring.count, ring.next = {}, 0, 1
        else
            tabs[key] = nil
        end
    end
end

-- The options page's "Clear saved chat history" button.
function M:ClearHistory()
    C.ClearHistory()
end
