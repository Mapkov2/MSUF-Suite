local _, P = ...
local S, Plan = P.Suite, P.PlanningTools
local Overview = {}
Plan.Overview = Overview

local function Progress(entry, kind)
    if type(entry.vault) ~= "table" then return S.Text("Unknown") end
    local nextRow, final
    for _, row in ipairs(entry.vault) do
        if type(row) == "table" and row.kind == kind and S.Finite(row.progress) and S.Finite(row.threshold) then
            if not final or row.threshold > final.threshold then final = row end
            if row.progress < row.threshold and (not nextRow or row.threshold < nextRow.threshold) then nextRow = row end
        end
    end
    local row = nextRow or final
    if not row then return S.Text("Unknown") end
    return S.Text("%d / %d"):format(math.min(row.progress, row.threshold), row.threshold)
end

function Overview.Cells(row)
    local entry = row.snapshot
    if not entry then return nil end
    local known = row.checked == true
    if P.NS.Client.isForever then return { "—", "—", "—", "—" } end
    local kinds = Enum.WeeklyRewardChestThresholdType
    local cells = { known and Progress(entry, kinds.Activities) or S.Text("Unknown"),
        known and Progress(entry, kinds.Raid) or S.Text("Unknown"),
        known and Progress(entry, kinds.World) or S.Text("Unknown"),
        known and entry.key and S.Text("+%d"):format(entry.key.level) or "—" }
    return cells
end

function Overview.Name(row)
    return row.snapshot and row.snapshot.character or row.label:match("^(.-) %- ") or row.label
end

function Overview.Subtitle(row, now)
    local entry, count = row.snapshot, 0
    if not entry then return "" end
    if entry.lockouts == nil then return S.Text("Unknown") end
    for _, lockout in ipairs(entry.lockouts or {}) do
        if S.Finite(lockout.expires) and lockout.expires > now then count = count + 1 end
    end
    return S.Text("%s • %d lockouts"):format(entry.realm or Plan.Date(entry.at), count)
end

function Overview.Hint(tab)
    if tab == "characters" then
        return S.Text("Log in to each character once. Weekly progress and lockouts are saved across your characters.")
    end
    if tab == "preparation" then
        return S.Text("Check durability, talents, loot and equipment before your group starts.")
    end
    if tab == "goals" then return S.Text("Set a target keystone level for each dungeon you want to push.") end
    if tab == "lfg" then return S.Text("Save Group Finder filters, roles and your note as reusable workspaces.") end
    if tab == "loadouts" then return S.Text("Enter a dungeon or raid and select a talent loadout first.") end
    if tab == "raid" then return S.Text("Saved attempts remain available. Combat recording is disabled.") end
    if tab == "runs" then return S.Text("Saved locally. Only visited characters and recorded activities are shown.") end
    if tab == "notes" then return S.Text("Use [ ] at the start of a line for a checklist. Right-click to tick items.") end
    return S.Text("Choose a tab, search and select an entry for details.")
end

function Overview.Detail(row, now)
    if not row or not row.snapshot then return row and row.detail end
    local entry = row.snapshot
    local lines = { Plan.Weekly.Detail(entry, row.checked) }
    if entry.lockoutsPending then lines[#lines + 1] = S.Text("Lockout data is waiting for the server.") end
    local active = 0
    for _, lockout in ipairs(entry.lockouts or {}) do
        if S.Finite(lockout.expires) and lockout.expires > now then active = active + 1 end
    end
    if entry.lockouts ~= nil then lines[#lines + 1] = S.Text("Active instance lockouts: %d"):format(active) end
    return table.concat(lines, "\n\n")
end

-- true when a vault reward waits. A snapshot from exactly the previous reset
-- counts its unlocked slots: the character was offline since and has not
-- claimed them. Older or unknown snapshots answer nil.
function Overview.RewardReady(entry, week, lastWeek)
    if week == "fresh" then
        if entry.reward == nil then return nil end
        return entry.reward == true
    end
    if week ~= "past" or not lastWeek or type(entry.vault) ~= "table" then return nil end
    for _, row in ipairs(entry.vault) do
        if S.Finite(row.progress) and S.Finite(row.threshold) and row.threshold > 0 and row.progress >= row.threshold then
            return true
        end
    end
    return false
end

-- Characters, those seen this reset, waiting vault rewards and total gold.
function Overview.Stats(rows)
    local rewards, fresh, gold, reset = 0, 0, 0, Plan.Weekly.Reset()
    for _, row in ipairs(rows) do
        local entry = row.snapshot
        if row.checked then fresh = fresh + 1 end
        if entry then
            local week, lastWeek = Plan.Weekly.Freshness(entry, reset)
            if row.checked then week = "fresh" end
            if Overview.RewardReady(entry, week, lastWeek) then rewards = rewards + 1 end
            if S.Finite(entry.money) then gold = gold + entry.money end
        end
    end
    return #rows, fresh, rewards, gold
end
