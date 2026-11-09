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

local function ReceiveLoot(value)
    local kind, _, link = GetCursorInfo()
    if not S.Public(kind) or kind ~= "item" then return end
    local entry = Plan.Loot.New(link)
    if entry then return entry.link .. (value:match("[\r\n].*$") or "") end
end

local function AddLoot()
    W.Edit("Add item", "Drop an item here or paste its link. Enter an optional source on the next line.", "", 1152, function(value)
        local link, source = value:match("^([^\r\n]*)[\r\n]*(.*)$")
        source = source:gsub("[\r\n]+", " ")
        if #source > 80 then return false, S.Text("The text is too long.") end
        local entry = Plan.Loot.New(link, source)
        if not entry then return false, S.Text("Enter a valid item link.") end
        if Plan.Loot.Save(entry) then return true end
        return false, S.Text("The loot list is full.")
    end, nil, true, ReceiveLoot)
end

local function BrowseLoot(_, _, window)
    local rows = Plan.Loot.JournalRows()
    if not rows then
        window:SetStatus(S.Text("Open an instance's Loot tab in the Adventure Guide first."))
        return
    end
    if #rows == 0 then
        window:SetStatus(S.Text("No loot is available from the current Adventure Guide page."))
        return
    end
    S.ToolListWindow.Open(Plan.owner, { title = "Adventure Guide", help = "Select an item to save as a loot goal.",
        rows = function() return rows end, valid = Plan.CanEdit,
        actions = { W.Action("Save", function(_, row, picker)
            if Plan.Loot.Save(row.loot) then
                S.ToolListWindow.Close(Plan.owner)
            else
                picker:SetStatus(S.Text("The loot list is full."))
            end
        end, true, "primary") } })
end

local function LootActions()
    local actions = { W.Action("Add item", AddLoot, false, "primary"),
        W.Action("Remove", function(_, row) W.Remove("loot", row) end, true, "danger"),
        W.Action("Toggle equipped items", function()
            W.hideEquipped = not W.hideEquipped
            W.Refresh()
        end) }
    if not NS.Client.isForever then actions[#actions + 1] = W.Action("Import guide loot", BrowseLoot) end
    return actions
end

local function CorrectionAction(field, label, guidance)
    local action = W.Action(label, function(_, _, window)
        if Plan.Loadouts.Open(field) then
            if guidance then S.Print(S.Text(guidance)) end
            Plan.Board.Dismiss(Plan.owner)
        else
            window:SetStatus(S.Text("Unavailable on this client or in combat."))
        end
    end, true)
    action.enabled = function(_, row)
        return row ~= nil and row.differences ~= nil and row.differences[field] == true and Plan.Loadouts.CanOpen(field) == true
    end
    return action
end

function W.Actions(tab)
    if tab == "loot" then return LootActions() end
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
            W.Action("Loadout settings", function() S.Open("loadoutReminder") end),
            CorrectionAction("talents", "Talents"),
            CorrectionAction("loot", "Loot specialization", "Choose Loot Specialization in the player menu."),
            CorrectionAction("gear", "Equipment sets") }
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
