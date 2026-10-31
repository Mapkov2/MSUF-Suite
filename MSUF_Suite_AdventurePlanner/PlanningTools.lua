local _, P = ...
local NS, S = P.NS, P.Suite
local Plan = { id = "planningTools", views = {} }
S.PlanningTools = Plan
P.PlanningTools = Plan
Plan.LIMIT = { characters = 200, attempts = 200, notes = 80, loadouts = 80, goals = 64, workspaces = 20 }

function Plan.Active()
    local owner = Plan.owner
    return owner ~= nil and owner.active == true
end

function Plan.CanEdit()
    return Plan.Active() and not Plan.owner.suspended and not Plan.owner.leaving and not NS.InCombat()
end

function Plan.Now()
    local value = GetServerTime()
    return S.Finite(value) and value >= 0 and value or nil
end

function Plan.Text(value, limit)
    if not S.Public(value) or type(value) ~= "string" then return nil end
    local text = value
    text = text:gsub("[%z\1-\8\11\12\14-\31]", "")
    if #text > (limit or 120) then return nil end
    return text
end

function Plan.Name(value)
    local name = Plan.Text(value, 80)
    if not name then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name
end

function Plan.Table(parent, key)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    return parent[key]
end

function Plan.Character()
    return S.CharacterData("planning")
end

function Plan.Account()
    if type(NS.RootDB) ~= "table" then return nil end
    return Plan.Table(NS.RootDB, "suitePlanning")
end

function Plan.Count(entries)
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

function Plan.Bucket(key)
    local data = Plan.Character()
    return data and Plan.Table(data, key)
end

function Plan.Changed()
    Plan.generation = (Plan.generation or 0) + 1
    if Plan.Window then Plan.Window.Refresh() end
end

function Plan.Notify(key, title, detail)
    if not Plan.Active() then return end
    S.Print(S.Text("%s — %s"):format(title, detail))
    S.Notifications.Push("planning." .. key, title, detail, Plan.id)
end

function Plan.Instance()
    local name, kind, difficulty, _, _, _, _, id = GetInstanceInfo()
    name, kind = S.PublicText(name), S.PublicText(kind)
    if not name or not kind or not S.Finite(id) or id <= 0 or not S.Finite(difficulty) then return nil end
    if kind ~= "party" and kind ~= "raid" and kind ~= "scenario" then return nil end
    return { id = id, name = name, kind = kind, difficulty = difficulty, key = tostring(id) }
end

function Plan.Date(value)
    if not S.Finite(value) or value <= 0 then return S.Text("Unknown") end
    return date("%Y-%m-%d %H:%M", value)
end

function Plan.Match(query, ...)
    if type(query) ~= "string" or query == "" then return true end
    query = query:lower()
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and value:lower():find(query, 1, true) then return true end
    end
    return false
end

function Plan.SortNames(a, b)
    return a.label:lower() == b.label:lower() and tostring(a.key) < tostring(b.key)
        or a.label:lower() < b.label:lower()
end

function Plan.Delete(bucket, key)
    if not Plan.CanEdit() then return false end
    local data = Plan.Bucket(bucket)
    if not data or data[key] == nil then return false end
    data[key] = nil
    Plan.Changed()
    return true
end
