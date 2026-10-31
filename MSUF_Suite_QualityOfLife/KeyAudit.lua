local _, P = ...
local NS, S = P.NS, P.Suite
local M = { rows = {} }
local function BindingName(command)
    return S.PublicText(_G["BINDING_NAME_" .. command]) or command
end
local function Bindings(rows)
    local count = GetNumBindings()
    if not S.Finite(count) then return end
    for i = 1, math.min(count, 3000) do
        local command, _, first, second = GetBinding(i)
        if S.PublicText(command) and (S.PublicText(first) or S.PublicText(second)) then
            local keys, overridden = {}, false
            for index = 1, 2 do
                local key = index == 1 and first or second
                if S.PublicText(key) then
                    local effective = GetBindingAction(key, true)
                    local changed = S.PublicText(effective) and effective ~= "" and effective ~= command
                    overridden = overridden or changed
                    keys[#keys + 1] = changed and S.Text("%s → %s"):format(key, BindingName(effective)) or key
                end
            end
            if not M.config.onlyIssues or overridden then
                rows[#rows + 1] = { key = "binding:" .. command, label = BindingName(command),
                    detail = table.concat(keys, "\n") .. "\n" .. S.Text(overridden
                        and "Another route currently overrides this binding. Suite paging can do this intentionally."
                        or "This binding currently follows its saved command.") }
            end
        end
    end
end
local function Scan()
    if NS.InCombat() then return end
    local rows = S.ActionKeyAuditRows and S.ActionKeyAuditRows(M.config.onlyIssues) or {}
    Bindings(rows)
    M.rows = rows
    S.ToolListWindow.Refresh(M)
end
function M:Open()
    Scan()
    return S.ToolListWindow.Open(self, { title = "Action and key review", rows = function() return self.rows end,
        help = "A snapshot of current keys and loaded Suite action bars. Refresh after changing actions, forms or bindings.",
        empty = "No matching entries. Enable Suite action bars to include action slots.",
        actions = { { label = "Refresh review", run = Scan },
            { label = "Action bar settings", run = function() S.Open("actionbars") end } } })
end
function M:Enable() end
function M:Refresh() if #self.rows > 0 then Scan() end end
function M:Disable() wipe(self.rows) S.ToolListWindow.Close(self) end
S.Install("keyAudit", M)
