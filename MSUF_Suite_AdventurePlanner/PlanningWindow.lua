local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local Window = { tab = "characters", sort = "date", minimum = 0, today = false, contextOnly = false }
Plan.Window = Window
-- Navigation order; group names the rail title (Board.NAV_GROUPS) and nav a
-- shorter rail label where the page title is long.
-- Mythic+ goals stay built and saved but out of the navigation for now
-- (owner decision 2026-10-29).
local TABS = { { key = "characters", label = "Weekly overview", group = "week" },
    { key = "preparation", label = "Preparation", group = "week" },
    { key = "goals", label = "Mythic+ goals", group = "history", hidden = true },
    { key = "runs", label = "Mythic+ archive", group = "history" },
    { key = "raid", label = "Raid archive", group = "history" }, { key = "loadouts", label = "Instance loadouts", group = "tools" },
    { key = "lfg", label = "Group finder workspaces", nav = "Group finder", group = "tools" },
    { key = "notes", label = "Instance notes and checklists", nav = "Notes", group = "tools" } }

function Window.Refresh()
    if Plan.owner and Plan.CanEdit() then Plan.Board.Refresh(Plan.owner) end
end

function Window.Edit(title, label, text, limit, save, valid, multiline)
    if not Plan.CanEdit() then return end
    S.ToolListWindow.Edit(Plan.owner, { title = title, label = label, text = text or "", maxBytes = limit,
        multiline = multiline, valid = valid, onSave = function(_, value)
            if not Plan.CanEdit() then return false end
            return save(value)
        end })
end

-- role: "primary" for the page's main action, "danger" for removals.
function Window.Action(label, run, selected, role)
    return { label = label, run = run, role = role,
        enabled = function(_, row) return Plan.CanEdit() and (not selected or row ~= nil) end }
end

function Window.Remove(bucket, row)
    if not row then return end
    local key = row.key
    local function Current()
        local account = Plan.Account()
        local entries
        if bucket == "characters" or bucket == "workspaces" then
            entries = account and account[bucket]
        else
            entries = Plan.Bucket(bucket)
        end
        return entries and entries[key]
    end
    local baseline = Current()
    local text = type(baseline) == "table" and baseline.text
    Window.Edit("Delete saved entry", "Type DELETE to remove this entry.", "", 6, function(text)
        if text ~= "DELETE" then return false, S.Text("Type DELETE to confirm.") end
        if bucket == "workspaces" then return Plan.LFG.Delete(key) end
        if bucket == "characters" then
            local account = Plan.Account()
            if account and account.characters then
                account.characters[key] = nil
                Plan.Changed()
                return true
            end
            return false
        end
        return Plan.Delete(bucket, key)
    end, function()
        local current = Current()
        return current == baseline and (type(current) ~= "table" or current.text == text)
    end)
end

local function Preparation()
    local rows = {}
    for index, row in ipairs(S.PlanningReadiness()) do
        rows[#rows + 1] = { key = tostring(index), label = row.label,
            detail = row.detail or row.status, module = row.module, search = row.label }
    end
    local durability = S.ReadInfoSource("durability")
    rows[#rows + 1] = { key = "durability", label = S.Text("Durability"), module = "durabilityAlert",
        detail = S.Finite(durability) and S.Text("Durability: %d%%"):format(math.floor(durability * 100 + .5)) or S.Text("Unknown") }
    local current = Plan.Loadouts.Current()
    rows[#rows + 1] = { key = "loadout", label = S.Text("Current loadout"), module = "loadoutReminder",
        detail = current and S.Text("Talents: %s\nLoot: %s\nEquipment: %s"):format(current.build, current.lootName,
            current.equipmentName or S.Text("Any equipment")) or S.Text("Unavailable on this client or in combat.") }
    rows[#rows + 1] = { key = "gear", label = S.Text("Gear details"),
        detail = S.Text("Gear enhancements are not evaluated here. Review your equipment in the character panel.") }
    return rows
end

function Window.Rows()
    local tab = Window.tab
    if tab == "characters" then return Plan.Weekly.Rows(false) end
    if tab == "preparation" then return Preparation() end
    if tab == "loadouts" then return Plan.Loadouts.Rows() end
    if tab == "runs" then
        local rows = Plan.History.Runs("", Window.minimum, Window.sort)
        for _, row in ipairs(rows) do
            row.label = S.Text("%s — %s"):format(row.label, Plan.Date(row.run.recordedAt))
            row.detail = row.detail .. "\n" .. row.note
            if Window.comparison and Window.comparison.key == row.key then row.detail = Window.comparison.text end
            row.search = row.label .. " " .. row.note
            row.checked = Window.first == row.key
        end
        return rows
    end
    if tab == "raid" then
        if not Plan.owner.config.raidHistory then return {} end
        local rows = Plan.History.Attempts("", Window.today)
        for _, row in ipairs(rows) do
            row.label = S.Text("%s — %s"):format(row.label, row.detail)
            local hp = row.attempt.remaining
            row.detail = row.detail .. "\n" .. (S.Finite(hp) and S.Text("Remaining health: %.1f%%"):format(hp)
                or S.Text("Remaining health unavailable."))
        end
        return rows
    end
    if tab == "goals" then return Plan.History.Goals("") end
    if tab == "lfg" then return Plan.LFG.Rows() end
    if tab == "notes" then return Plan.Notes.Rows(Window.contextOnly) end
    return {}
end

local function Status()
    if Window.tab == "runs" then
        return S.Text("Minimum +%d | Sort: %s | Compare: select a first run, then another run.")
            :format(Window.minimum, S.Text(Window.sort == "level" and "Level" or Window.sort == "time" and "Time" or "Date"))
    end
    if Window.tab == "raid" then return S.Text("Saved attempts remain available. Combat recording is disabled.") end
    if Window.tab == "notes" then return S.Text("Use [ ] at the start of a line for a checklist. Right-click to tick items.") end
    if NS.Client.isForever and (Window.tab == "lfg" or Window.tab == "goals" or Window.tab == "loadouts") then
        return S.Text("Available only in Retail")
    end
    return S.Text("Saved locally. Only visited characters and recorded activities are shown.")
end

local function SupportedTabs()
    local tabs, forever = {}, NS.Client.isForever
    for _, tab in ipairs(TABS) do
        if not tab.hidden and not (forever and (tab.key == "lfg" or tab.key == "loadouts" or tab.key == "runs")) then
            tabs[#tabs + 1] = tab
        end
    end
    return tabs
end
function Window.Open(tab)
    if not Plan.CanEdit() then return false end
    local tabs, requested = SupportedTabs(), tab or Window.tab
    local supported = false
    for _, entry in ipairs(tabs) do if entry.key == requested then supported = true break end end
    if not supported then requested = "characters" end
    tab = requested
    Window.tab = tab or Window.tab
    -- A comparison answers one visit: a new window, tab or selection starts without it.
    Window.comparison = nil
    local spec = { title = "Adventure planner", help = "Choose a tab, search and select an entry for details.",
        empty = "Select an entry to see its details.", tabs = tabs, rows = Window.Rows, status = Status,
        currentTab = function() return Window.tab end, valid = Plan.CanEdit, menu = Window.Menu,
        onSelect = function() Window.comparison = nil end }
    spec.selectTab = function(_, key)
        Window.tab, Window.comparison = key, nil
        spec.actions = Window.Actions(key)
    end
    spec.actions = Window.Actions(Window.tab)
    Window.host = Plan.Board.Open(Plan.owner, spec)
    return Window.host ~= nil
end
