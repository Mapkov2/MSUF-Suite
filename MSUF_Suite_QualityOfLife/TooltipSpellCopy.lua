local _, P = ...
local S = P.Suite

-- C_OS.CopyToClipboard is restricted. Keep the last public spell tooltip ID
-- for a user-invoked, selected edit box instead.
local M = {}
local COMMAND = "MSUFSUITECOPYSPELL"

local function ShowCopy(message)
    if not M.active then return end
    local id = M.lastID
    local typed = S.PublicText(message)
    if typed and typed:match("^%s*%d+%s*$") then
        local parsed = tonumber(typed)
        if S.Finite(parsed) and parsed > 0 then id = parsed end
    end
    if not S.Finite(id) or id < 1 then
        S.Print(S.Text("Hover a spell first, then use /msufcopyspell"))
        return
    end
    M.dialog = M.dialog or S.QoLCopyDialog("Copy spell ID", "Press Ctrl+C to copy", 270)
    S.QoLShowCopy(M.dialog, tostring(math.floor(id)))
end

local function Spell(_, data)
    local id = data.id
    if S.Finite(id) and id > 0 then M.lastID = math.floor(id) end
end

function M:Enable()
    S.RegisterSlash(COMMAND, ShowCopy, "/msufcopyspell")
    S.TooltipLines.Add(self, "Spell", Spell)
end

function M:Refresh() end

function M:Disable()
    S.UnregisterSlash(COMMAND, ShowCopy)
    self.lastID = nil
    if self.dialog then S.QoLClearCopy(self.dialog) end
end

S.Install("tooltipSpellCopy", M)
