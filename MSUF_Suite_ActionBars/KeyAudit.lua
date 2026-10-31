local _, P = ...
local NS, S, AB = P.NS, P.Suite, P.ActionBars
-- A button the player cannot see needs no key: its bar is switched off
-- (Never) or it lies beyond the bar's button count.
local function Drawn(rec)
    local bar = rec.bar
    return rec.index <= (bar.count or AB.BUTTONS) and AB.M.config[bar.key.Visibility] ~= AB.ENUM.VISIBILITY.NEVER
end
function S.ActionKeyAuditRows(onlyIssues)
    local rows = {}
    if not AB.M.active or NS.InCombat() then return rows end
    for _, rec in ipairs(AB.owned) do
        local slot = rec.button:GetAttribute("action")
        if Drawn(rec) and S.Finite(slot) and S.PublicText(rec.command) then
            local kind, id = GetActionInfo(slot)
            if S.PublicText(kind) and S.Finite(id) then
                local key = GetBindingKey(rec.command)
                local bound = S.PublicText(key) and key ~= ""
                if not onlyIssues or not bound then
                    local name
                    if kind == "spell" then
                        local info = C_Spell.GetSpellInfo(id)
                        name = S.Public(info) and type(info) == "table" and S.PublicText(info.name)
                    elseif kind == "item" then
                        name = S.PublicText(C_Item.GetItemNameByID(id))
                    elseif kind == "macro" then
                        name = S.PublicText(GetMacroInfo(id))
                    end
                    name = name or S.Text("Action %d"):format(slot)
                    rows[#rows + 1] = { key = "slot:" .. rec.command,
                        label = S.Text("%s · %s · Button %d"):format(name, S.Text(NS.ActionBarTitles[rec.bar.index]), rec.index),
                        detail = bound and S.Text("Bound to %s"):format(key) or S.Text("No key assigned. This action can still be clicked.") }
                end
            end
        end
    end
    return rows
end
