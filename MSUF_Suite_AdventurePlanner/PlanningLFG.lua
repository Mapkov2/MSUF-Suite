local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local LFG = {}
Plan.LFG = LFG
local KEYS = { "difficulty", "minimumRating", "activities", "needsRole", "hasTank", "hasHealer" }

local function Entries()
    local account = Plan.Account()
    return account and Plan.Table(account, "workspaces")
end

function LFG.Save(name)
    if not Plan.CanEdit() or NS.Client.isForever then return false end
    name = Plan.Name(name)
    local entries = Entries()
    if not name or not entries or entries[name] or Plan.Count(entries) >= Plan.LIMIT.workspaces then return false end
    local _, tank, healer, damage = GetLFGRoles()
    if not S.Public(tank) or not S.Public(healer) or not S.Public(damage) then return false end
    local filters, values = S.Config("groupFinderTools"), {}
    for _, key in ipairs(KEYS) do values[key] = filters[key] end
    entries[name] = { filters = values, tank = tank == true, healer = healer == true, damage = damage == true,
        note = S.Config("groupFinderDoubleClick").note or "" }
    Plan.Changed()
    return true
end

function LFG.Apply(name)
    if not Plan.CanEdit() or NS.Client.isForever then return false, S.Text("Available only in Retail") end
    local entries, m = Entries(), S.instances.groupFinderTools
    local entry = entries and entries[name]
    if not entry or not m or not m.active or not m.config.filters
        or not m.CanApplyFilters() then return false, S.Text("Enable saved filters and open a dungeon search first.") end
    local tank, healer, damage = UnitGetAvailableRoles("player")
    if not S.Public(tank) or not S.Public(healer) or not S.Public(damage) then return false end
    local useTank, useHealer, useDamage = entry.tank and tank == true, entry.healer and healer == true, entry.damage and damage == true
    if not useTank and not useHealer and not useDamage then return false, S.Text("This character cannot use the saved roles.") end
    if not S.SetMany("groupFinderTools", entry.filters) then return false end
    if not S.SetMany("groupFinderDoubleClick", { note = entry.note }) then return false end
    local leader = GetLFGRoles()
    if not S.Public(leader) then return false end
    SetLFGRoles(leader == true, useTank, useHealer, useDamage)
    return m.ApplyFilters()
end

function LFG.Delete(name)
    if not Plan.CanEdit() then return false end
    local entries = Entries()
    if not entries or not entries[name] then return false end
    entries[name] = nil
    Plan.Changed()
    return true
end

function LFG.Rows()
    local rows = {}
    for name, entry in pairs(Entries() or {}) do
        if Plan.Name(name) and type(entry) == "table" and type(entry.filters) == "table" then
            local roles = {}
            if entry.tank then roles[#roles + 1] = S.Text("Tank") end
            if entry.healer then roles[#roles + 1] = S.Text("Healer") end
            if entry.damage then roles[#roles + 1] = S.Text("Damage") end
            rows[#rows + 1] = { key = name, label = name, workspace = entry,
                detail = S.Text("Roles: %s\nMinimum rating: %d\nApplication note: %s\nApplying only changes filters, roles and the saved note.")
                    :format(table.concat(roles, ", "), entry.filters.minimumRating or 0, entry.note or "") }
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end
