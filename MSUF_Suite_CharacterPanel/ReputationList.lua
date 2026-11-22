local _, NS = ...
local List = {}
NS.ReputationList = List
local Num, Public, String = NS.Number, NS.Public, NS.String
local Factions = C_Reputation
local collected, scanning

local function Data(value)
    if Public(value) and type(value) == "table" and canaccesstable(value) then return value end
end

local function Yes(value)
    return Public(value) and value == true
end

-- Sort indices describe the visible tree. Opening one header only shifts
-- later indices, so closing in reverse restores even nested hidden headers.
local function Walk(tx, rows, warID)
    local all = Enum.ReputationSortType.None
    if tx.sort and tx.sort ~= all then Factions.SetReputationSortType(all) end
    if tx.legacyHidden then Factions.SetLegacyReputationsShown(true) end
    local index, count = 1, Num(Factions.GetNumFactions()) or 0
    while index <= count do
        local info = Data(Factions.GetFactionDataByIndex(index))
        if info then
            if Yes(info.isHeader) and Yes(info.isCollapsed) then
                tx[#tx + 1] = index
                Factions.ExpandFactionHeader(index)
                count = Num(Factions.GetNumFactions()) or count
            end
            if rows then rows[#rows + 1] = info end
            if warID and Num(info.factionID) == warID then
                if Yes(info.canToggleAtWar) and Public(info.atWarWith) and type(info.atWarWith) == "boolean" then
                    Factions.ToggleFactionAtWar(index)
                end
                break
            end
        end
        index = index + 1
    end
end

local function Enumerate(rows, warID)
    local tx = { sort = Num(Factions.GetReputationSortType()), selected = Num(Factions.GetSelectedFaction()) }
    if not NS.Host.Client.isForever then
        local legacy = Factions.AreLegacyReputationsShown()
        tx.legacyHidden = Public(legacy) and legacy == false
    end
    local dispatch = NS.Suite.Dispatch
    scanning = true
    local ok = dispatch(NS.Suite.Finish, Walk, tx, rows, warID)
    for n = #tx, 1, -1 do dispatch(Factions.CollapseFactionHeader, tx[n]) end
    if tx.legacyHidden then dispatch(Factions.SetLegacyReputationsShown, false) end
    local sorted = tx.sort and tx.sort ~= Enum.ReputationSortType.None
    if sorted then dispatch(Factions.SetReputationSortType, tx.sort) end
    local changed = #tx > 0 or tx.legacyHidden or sorted
    if changed and tx.selected and tx.selected >= 0 then
        local current = Num(dispatch(Factions.GetSelectedFaction))
        if current and current ~= tx.selected then dispatch(Factions.SetSelectedFaction, tx.selected) end
    end
    scanning = nil
    return ok, changed
end

function List.ToggleHiddenWar(id)
    if not scanning and not NS.Host.InCombat() and collected and collected.ids[id] then
        local _, changed = Enumerate(nil, id)
        if changed then collected.wroteAt, collected.awaitingEcho = GetTime(), true end
    end
end

-- Header and filter changes can themselves deliver UPDATE_FACTION. Refresh
-- the known standings by ID on the echo without mutating the native list.
local function VisibleStructure()
    local keys = {}
    for i = 1, Num(Factions.GetNumFactions()) or 0 do
        local info = Data(Factions.GetFactionDataByIndex(i))
        if info then
            keys[#keys + 1] = (Num(info.factionID) or 0) .. ":" .. (String(info.name) or "")
                .. (Yes(info.isCollapsed) and "-" or "+")
        end
    end
    return table.concat(keys, "\031")
end

function List.Update(state, event, id)
    if scanning then return false end
    local standaloneUpdate = false
    if event == "UPDATE_FACTION" then
        state.receivedUpdate = true
        standaloneUpdate = not state.awaitingEcho and (not state.wroteAt or GetTime() - state.wroteAt > 1)
    end
    if standaloneUpdate or event == "MAJOR_FACTION_UNLOCKED"
        or event == "FACTION_STANDING_CHANGED" and not (state.ids and state.ids[Num(id)]) then
        state.forceScan = true
    end
    state.updateOnly = not state.forceScan
    return true
end

function List.Rows(state)
    local rows = state.rows
    if state.receivedUpdate then state.awaitingEcho, state.receivedUpdate = nil, nil end
    if state.updateOnly and rows and state.visible == VisibleStructure() then
        for i, info in ipairs(rows) do
            local id = Num(info.factionID)
            if id and id > 0 and (not Yes(info.isHeader) or Yes(info.isHeaderWithRep)) then
                local current = Data(Factions.GetFactionDataByID(id))
                state.progress[i] = current
            end
        end
    else
        local candidate = {}
        local ok, changed = Enumerate(candidate)
        state.wroteAt, state.awaitingEcho = changed and GetTime() or nil, changed
        if ok then
            rows = candidate
            state.rows, state.ids, state.progress = rows, {}, {}
            for _, info in ipairs(rows) do
                local id = Num(info.factionID)
                if id and id > 0 then state.ids[id] = true end
            end
            state.visible, collected = VisibleStructure(), state
        end
    end
    state.updateOnly, state.forceScan = nil, nil
    return rows or {}
end

function List.Paint(module, combat)
    local state = module.reputations
    if not state then
        state = { groups = {}, closed = {} }
        module.reputations = state
    end
    if not combat then
        NS.Pages.Read("reputation", state.groups, module.config, state)
    elseif #state.groups == 0 then
        state.groups[1] = { title = NS.Text("Available after combat"), rows = {} }
    end
    module.view:ShowGroups(state.groups, combat, not combat and state or nil)
end

function List.Toggle(module, key)
    local state = module.reputations
    if not state or type(key) ~= "string" or NS.Host.InCombat() then return end
    state.closed[key] = not state.closed[key] or nil
    module.view:ShowGroups(state.groups, false, state)
end

local function Lower(text)
    return (strlower or string.lower)(text)
end

function List.Query(text)
    text = String(text)
    return text and Lower(text:match("^%s*(.-)%s*$")) or ""
end

local function Match(entry, text, query)
    if text ~= entry.searchName then
        entry.searchName, entry.searchLower = text, Lower(text)
    end
    return entry.searchLower:find(query, 1, true) ~= nil
end

function List.Project(state, groups)
    local filtered, closed = {}, state.closed or {}
    local query = state.query or ""
    local matches, total = 0, 0
    local parent, parentClosed, parentMatches, parentGroup, parentListed
    for _, group in ipairs(groups) do
        local child = group.depth == 1
        local key = child and (parent or "") .. "\031" .. group.title or group.title
        if not child then
            parent, parentClosed = group.title, closed[key]
            parentMatches = query ~= "" and Match(group, group.title, query)
            parentGroup, parentListed = group, false
        end
        local collapsed = closed[key] and query == ""
        local all = query == "" or parentMatches or Match(group, group.title, query)
        local rows = {}
        total = total + #group.rows
        if not collapsed and (not child or not parentClosed or query ~= "") then
            for _, row in ipairs(group.rows) do
                if all or Match(row, row.factionName or row.label, query) then rows[#rows + 1] = row end
            end
        end
        if (query == "" and (not child or not parentClosed)) or #rows > 0 then
            matches = matches + #rows
            if child and parentGroup and not parentListed then
                filtered[#filtered + 1] = { title = parentGroup.title, rows = {} }
                parentListed = true
            end
            filtered[#filtered + 1] = { title = group.title, depth = group.depth, rows = rows,
                collapsed = collapsed, action = query == "" and group.action and key or nil }
            if not child then parentListed = true end
        end
    end
    if #filtered == 0 then filtered[1] = { title = NS.Text("No results"), rows = {} } end
    return filtered, matches, total
end
