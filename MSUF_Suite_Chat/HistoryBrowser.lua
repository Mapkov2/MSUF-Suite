local _, P = ...
local S = P.Suite
local C = P.Chat
local owner = { active = true }
local copy
local TABS = { { key = "messages", label = "Saved chat" }, { key = "whispers", label = "Conversations" } }

local function ResetRows()
    owner.rows, owner.contacts, owner.contact, owner.contactRows = nil, nil, nil, nil
end

local function ContactRows()
    if owner.contacts then return owner.contacts end
    local rows = {}
    local title = S.Text("Conversation with %s")
    for i, contact in ipairs(C.WhisperSnapshot()) do
        local name = title:format(contact.peer)
        rows[i] = { key = contact.peer, label = contact.peer, detail = name .. "\n" .. contact.lines[1],
            contact = contact }
    end
    owner.contacts = rows
    return rows
end

local function ConversationRows()
    if owner.contactRows then return owner.contactRows end
    local rows = {}
    local name = S.Text("Conversation with %s"):format(owner.contact.peer)
    for i, text in ipairs(owner.contact.lines) do
        rows[i] = { key = i, label = text, text = text, detail = name .. "\n" .. text }
    end
    owner.contactRows = rows
    return rows
end

-- The requested snapshots live only while the browser is open.
local function Rows()
    if owner.tab == "whispers" then return owner.contact and ConversationRows() or ContactRows() end
    if not owner.rows then owner.rows = C.HistorySnapshot() end
    return owner.rows
end

local function Matches(_, row, query)
    if not row.searchLower then row.searchLower = (row.search or row.label):lower() end
    return row.searchLower:find(query, 1, true) ~= nil
end

local function Refresh(_, _, window)
    ResetRows()
    window.offset, window.selected = 0, nil
    S.ToolListWindow.Refresh(owner)
end

local function Copy(_, row)
    if not copy then copy = S.QoLCopyDialog("Copy saved message", "Press Ctrl+C to copy the selected message.", 620) end
    S.QoLShowCopy(copy, row.text)
end

local function SetContact(contact, window)
    owner.contact, owner.contactRows = contact, nil
    window.offset, window.selected = 0, nil
    window.search:SetText("")
    window:Refresh()
end

local function CanCopyMessage(_, row) return row ~= nil and row.text ~= nil end
local function CanOpenContact(_, row) return row ~= nil and row.contact ~= nil end

local function CopyConversation()
    local chronological, lines = {}, owner.contact.lines
    for i = #lines, 1, -1 do chronological[#chronological + 1] = lines[i] end
    C.ShowChatTranscript(table.concat(chronological, "\n"))
end

local function SelectTab(_, key)
    owner.tab, owner.contact, owner.contactRows = key, nil, nil
end

local function Status()
    if owner.contact then return S.Text("Conversation with %s"):format(owner.contact.peer) end
    local config = C.M.config
    if owner.tab == "whispers"
        and (not config or not (config.saveHistory and config.historyWhispers ~= false and config.historyConversations)) then
        return S.Text("Enable whisper conversations to archive future messages from characters.")
    end
end

function C.HistoryDisable()
    S.ToolListWindow.Close(owner)
end

function C.HistoryCleared()
    ResetRows()
    S.ToolListWindow.Refresh(owner)
    if copy then S.QoLClearCopy(copy) end
    C.HideCopyDialog(C.M.copyDialog)
end

local function Closed()
    ResetRows()
    if copy then S.QoLClearCopy(copy) end
end

function C.M:OpenHistory(whispers)
    owner.tab = whispers and "whispers" or "messages"
    return S.ToolListWindow.Open(owner, { title = "Search saved chat", rows = Rows, filter = Matches,
        tabs = TABS, currentTab = function() return owner.tab end, selectTab = SelectTab, status = Status,
        help = "Search saved text and chat tab names. Enable Save chat history to keep future messages.",
        empty = "No saved messages match this search.",
        onHide = Closed,
        actions = {
            { label = "Copy selected message", enabled = CanCopyMessage, run = Copy },
            { label = "Open conversation", enabled = CanOpenContact,
                run = function(_, row, window) SetContact(row.contact, window) end },
            { label = "Copy conversation", enabled = function() return owner.contact ~= nil end, run = CopyConversation },
            { label = "Back to conversations", enabled = function() return owner.contact ~= nil end,
                run = function(_, _, window) SetContact(nil, window) end },
            { label = "Refresh saved messages", run = Refresh },
        } })
end
