local _, P = ...
local S = P.Suite
local C = P.Chat
local owner = { active = true }
local copy
-- The snapshot (up to 16 tabs of 1000 lines) lives only while the window is open.
local function Rows()
    if not owner.rows then owner.rows = C.HistorySnapshot() end
    return owner.rows
end
local function Refresh()
    owner.rows = nil
    S.ToolListWindow.Refresh(owner)
end
local function Copy(_, row)
    if not copy then copy = S.QoLCopyDialog("Copy saved message", "Press Ctrl+C to copy the selected message.", 620) end
    S.QoLShowCopy(copy, row.text)
end
function C.HistoryDisable()
    S.ToolListWindow.Close(owner)
end
function C.M:OpenHistory()
    return S.ToolListWindow.Open(owner, { title = "Search saved chat", rows = Rows,
        help = "Search saved text and chat tab names. Enable Save chat history to keep future messages.",
        empty = "No saved messages match this search.",
        onHide = function()
            owner.rows = nil
            if copy then S.QoLClearCopy(copy) end
        end,
        actions = { { label = "Copy selected message", enabled = function(_, row) return row ~= nil end, run = Copy },
            { label = "Refresh saved messages", run = Refresh } } })
end
