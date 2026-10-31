local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local W = Plan.Window

local function Compare(_, row)
    if not row then return end
    if not W.first then
        W.first = row.key
        W.Refresh()
        return
    end
    local first
    for _, candidate in ipairs(Plan.History.Runs("")) do if candidate.key == W.first then first = candidate.run break end end
    local detail = Plan.History.Compare(first, row.run)
    W.first = nil
    -- A read-only result stays in the selected details pane until the next selection.
    W.comparison = { key = row.key, text = detail }
    W.Refresh()
end

local function Note(_, row)
    local baseline = row.note
    W.Edit("Run note", "Personal note", baseline, 2000, function(text) return Plan.History.SaveRunNote(row.key, text) end,
        function()
            for _, current in ipairs(Plan.History.Runs("")) do
                if current.key == row.key then return current.note == baseline end
            end
            return false
        end, true)
end

local function Filter()
    W.Edit("Filter runs", "Minimum keystone level (0 shows all)", tostring(W.minimum), 2, function(text)
        local value = tonumber(text)
        if not S.Finite(value) or value < 0 or value > 99 or value % 1 ~= 0 then return false end
        W.minimum = value
        W.Refresh()
        return true
    end)
end

function W.RunActions()
    return { W.Action("Compare runs", Compare, true), W.Action("Edit note", Note, true), W.Action("Minimum level", Filter),
        W.Action("Change sort", function()
            W.sort = W.sort == "date" and "level" or W.sort == "level" and "time" or "date"
            W.Refresh()
        end), W.Action("Recording settings", function() S.Open("runSummary") end) }
end

local function GoalLevel(id, name, existing)
    local entries = Plan.Bucket("goals")
    local baseline = entries and entries[tostring(id)]
    local level = baseline and baseline.level
    W.Edit("Dungeon target", "Target keystone level (2–99)", existing and tostring(existing) or "10", 2, function(text)
        return Plan.History.SaveGoal(id, name, tonumber(text))
    end, function()
        local current = (Plan.Bucket("goals") or {})[tostring(id)]
        return current == baseline and (not current or current.level == level)
    end)
end

function W.AddGoal(_, _, window)
    if NS.Client.isForever then return end
    local maps = C_ChallengeMode.GetMapTable()
    if not S.Public(maps) or type(maps) ~= "table" then return end
    local profile = NS.DB
    S.ContextMenu(window.actions[1], function(_, root)
        root:CreateTitle(S.Text("Choose dungeon"))
        for i = 1, math.min(#maps, 64) do
            local id = maps[i]
            if S.Finite(id) then
                local name = S.PublicText(C_ChallengeMode.GetMapUIInfo(id))
                if name then root:CreateButton(name, function()
                    if Plan.CanEdit() and NS.DB == profile then GoalLevel(id, name) end
                end) end
            end
        end
    end)
end

function W.GoalActions()
    return { W.Action("Add dungeon", W.AddGoal, false, "primary"), W.Action("Edit target", function(_, row)
        GoalLevel(tonumber(row.key), row.label, row.goal.level)
    end, true), W.Action("Delete target", function(_, row) W.Remove("goals", row) end, true, "danger") }
end
