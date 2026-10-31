local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local W = Plan.Window

local function EditNote(key, label, instanceID, encounterID)
    local entries = Plan.Bucket("notes")
    local old = entries and entries[key]
    local baseline = old and old.text
    W.Edit("Personal instance notes", "Notes and checklist ([ ] marks a task)", old and old.text or "", 4000,
        function(text) return Plan.Notes.Save(key, label, text, instanceID, encounterID) end,
        function()
            local current = (Plan.Bucket("notes") or {})[key]
            return current == old and (not current or current.text == baseline)
        end, true)
end

local function NewNote(boss)
    local instance = Plan.Instance()
    if not instance then return end
    if not boss then
        EditNote(instance.key, instance.name, instance.id)
        return
    end
    W.Edit("Boss notes", "Boss or encounter name", "", 80, function(value)
        local name = Plan.Name(value)
        if not name then return false end
        EditNote(instance.key .. ":" .. name:lower(), name, instance.id)
        return true
    end)
end

local function Checked(key, baseline, number)
    if not Plan.CanEdit() or (Plan.Bucket("notes") or {})[key] ~= baseline then return false end
    local index = 0
    for line in (baseline.text .. "\n"):gmatch("(.-)\n") do
        index = index + 1
        if index == number then return line:match("^%[[xX]%]") ~= nil end
    end
    return false
end

function W.Menu(_, row, button)
    if W.tab ~= "notes" or not row.note then return end
    local baseline = row.note
    S.ContextMenu(button, function(_, root)
        root:CreateTitle(row.label)
        local index = 0
        for line in (baseline.text .. "\n"):gmatch("(.-)\n") do
            index = index + 1
            local number = index
            if line:match("^%[[ xX]%]") then
                local text = line:sub(4)
                root:CreateCheckbox(text, function()
                    return Checked(row.key, baseline, number)
                end, function()
                    if Plan.CanEdit() and (Plan.Bucket("notes") or {})[row.key] == baseline then
                        Plan.Notes.Toggle(row.key, number)
                    end
                end)
            end
        end
    end)
end

local function NoteActions()
    local actions = { W.Action("Instance note", function() NewNote(false) end, false, "primary"),
        W.Action("Boss note", function() NewNote(true) end), W.Action("Edit note", function(_, row)
            EditNote(row.key, row.label, row.note.instanceID, row.note.encounterID)
        end, true), W.Action("Delete note", function(_, row) W.Remove("notes", row) end, true, "danger"),
        W.Action("Current / all", function() W.contextOnly = not W.contextOnly W.Refresh() end) }
    actions[1].enabled = function() return Plan.CanEdit() and Plan.Instance() ~= nil end
    actions[2].enabled = actions[1].enabled
    return actions
end

local function WorkspaceActions()
    return { W.Action("Save workspace", function()
        W.Edit("Save LFG workspace", "Name for current filters, roles and note", "", 80, function(text)
            if Plan.LFG.Save(text) then return true end
            return false, S.Text("Use a unique name; up to 20 workspaces can be saved.")
        end)
    end, false, "primary"), W.Action("Apply workspace", function(_, row, window)
        local ok, reason = Plan.LFG.Apply(row.key)
        window:SetStatus(ok and S.Text("Workspace applied. Applications remain manual.") or reason or S.Text("Workspace could not be applied."))
    end, true), W.Action("Delete workspace", function(_, row) W.Remove("workspaces", row) end, true, "danger"),
        W.Action("Filter settings", function() S.Open("groupFinderTools") end),
        W.Action("Note settings", function() S.Open("groupFinderDoubleClick") end) }
end

function W.Actions(tab)
    if tab == "characters" then
        return { W.Action("Refresh current character", function() Plan.Weekly.Request() Plan.Weekly.Capture() end, false, "primary"),
            W.Action("Forget character", function(_, row) W.Remove("characters", row) end, true, "danger") }
    end
    if tab == "preparation" then
        local settings = W.Action("Open settings", function(_, row) S.Open(row.module) end, true)
        settings.enabled = function(_, row) return Plan.CanEdit() and row ~= nil and row.module ~= nil end
        return { settings, W.Action("Refresh", W.Refresh) }
    end
    if tab == "loadouts" then
        local actions = { W.Action("Save current", function(_, _, window)
            window:SetStatus(Plan.Loadouts.Save() and S.Text("Current loadout saved for this instance.")
                or S.Text("Enter a dungeon or raid and select a talent loadout first."))
        end, false, "primary"), W.Action("Delete loadout", function(_, row) W.Remove("loadouts", row) end, true, "danger"),
            W.Action("Loadout settings", function() S.Open("loadoutReminder") end) }
        actions[1].enabled = function() return Plan.CanEdit() and not NS.Client.isForever and Plan.Instance() ~= nil end
        return actions
    end
    if tab == "runs" then return W.RunActions() end
    if tab == "raid" then return { W.Action("Today / all", function() W.today = not W.today W.Refresh() end) } end
    if tab == "goals" then return W.GoalActions() end
    if tab == "lfg" then return WorkspaceActions() end
    if tab == "notes" then return NoteActions() end
    return {}
end
