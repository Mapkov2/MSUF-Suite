local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Tools = S.ToolListWindow
local Palette = { entries = {}, rows = {}, seen = {}, tab = "all", item = { key = "itemSearch" } }
local RECENT_LIMIT = 8
S.QuickActions = Palette

-- Only action IDs from this table are saved. Labels are localized at open time.
-- This list points to owned windows. It does not expose arbitrary commands or item use.
local ACTIONS = {
    { key = "weekly", title = "Weekly overview", search = "adventure planner vault reset", planner = "characters" },
    { key = "preparation", title = "Preparation", search = "adventure planner", planner = "preparation" },
    { key = "lootGoals", title = "Loot goals", search = "adventure planner", planner = "loot" },
    { key = "inventoryArchive", title = "Inventory archive", search = "bags bank items alt", module = "inventoryArchive" },
    { key = "character", title = "Character", search = "character panel paper doll", panel = "character" },
    { key = "gear", title = "Equipment", search = "character panel gear durability", character = "gear" },
    { key = "reputation", title = "Reputation", search = "character panel faction", character = "reputation" },
    { key = "currency", title = "Currency", search = "character panel tokens", character = "currency" },
    { key = "worldMap", title = "World map", search = "map", panel = "worldMap" },
    { key = "currencyGoals", title = "Currency goals", module = "currencyGoals" },
    { key = "craftShopping", title = "Crafting shopping list", module = "craftShopping" },
    { key = "restockPlanner", title = "Stock targets", module = "restockPlanner" },
    { key = "waypointLists", title = "Saved waypoint lists", module = "waypointLists" },
    { key = "notificationHistory", title = "Suite notice history", module = "notificationHistory" },
    { key = "keyAudit", title = "Action and key review", module = "keyAudit" },
}
local byKey = {}
for i = 1, #ACTIONS do
    local action = ACTIONS[i]
    byKey[action.key] = action
end

local function ActiveModule(id)
    local module = S.instances[id]
    if module and module.active == true then return module end
end

local function Available(action)
    if action.module then return ActiveModule(action.module) ~= nil end
    if action.planner then return S.PlanningTools and S.PlanningTools.CanEdit() end
    if action.panel then return S.CanOpenNativeWindow() end
    local character = ActiveModule("characterPanel")
    return character and character.running and S.OpenCharacterPanelTab and S.CanOpenNativeWindow()
end

local function Trim(query)
    return query:match("^%s*(.-)%s*$")
end

local function Match(row, query)
    for term in query:gmatch("%S+") do
        if not row.search:find(term, 1, true) then return false end
    end
    return true
end

local function ReadState()
    local state = S.CharacterData("quickActions") or {}
    local favorites, cleanFavorites = state.favorites, {}
    if type(favorites) == "table" then
        for i = 1, #ACTIONS do
            local key = ACTIONS[i].key
            local value = favorites[key]
            if S.Public(value) and value == true then cleanFavorites[key] = true end
        end
    end
    state.favorites = cleanFavorites
    local recent, clean, seen = state.recent, {}, {}
    if type(recent) == "table" then
        for i = 1, RECENT_LIMIT do
            local key = S.PublicText(recent[i])
            if key and byKey[key] and not seen[key] then
                seen[key] = true
                clean[#clean + 1] = key
            end
        end
    end
    state.recent = clean
    return state
end

local function Remember(state, key)
    local recent = state.recent
    for i = #recent, 1, -1 do
        if recent[i] == key then table.remove(recent, i) end
    end
    table.insert(recent, 1, key)
    if #recent > RECENT_LIMIT then recent[RECENT_LIMIT + 1] = nil end
end

local function InitEntries(owner)
    for i = 1, #ACTIONS do
        local action = ACTIONS[i]
        local row = owner.entries[action.key] or { key = action.key, action = action }
        local title = S.Text(action.title)
        row.title = title
        row.search = (title .. " " .. action.title .. " " .. (action.search or "")):lower()
        owner.entries[action.key] = row
    end
end

local function AddRow(owner, key, query)
    if owner.seen[key] then return end
    local row = owner.entries[key]
    if not row or not Available(row.action) or not Match(row, query) then return end
    owner.seen[key] = true
    local favorite = owner.state.favorites[key] == true
    row.checked = favorite and true or nil
    row.label = row.title
    row.detail = S.Text(favorite and "Favorites" or "Quick actions")
    owner.rows[#owner.rows + 1] = row
end

local function Rows(owner, query, input)
    wipe(owner.rows)
    wipe(owner.seen)
    query = Trim(query)
    if owner.tab == "all" or owner.tab == "favorites" then
        for i = 1, #ACTIONS do
            local key = ACTIONS[i].key
            if owner.state.favorites[key] == true then AddRow(owner, key, query) end
        end
    end
    if owner.tab == "all" or owner.tab == "recent" then
        for _, key in ipairs(owner.state.recent) do AddRow(owner, key, query) end
    end
    if owner.tab == "all" then
        for i = 1, #ACTIONS do AddRow(owner, ACTIONS[i].key, query) end
        if #query >= 2 and ActiveModule("inventoryArchive") then
            local item = owner.item
            item.query = Trim(input)
            item.label = S.Text("Search inventory archive for %s"):format((item.query:gsub("|", "||")))
            item.detail = S.Text("Inventory archive")
            owner.rows[#owner.rows + 1] = item
        end
    end
    return owner.rows
end

local function OpenAction(action)
    if action.planner then return S.PlanningTools.Window.Open(action.planner) end
    if action.panel then return S.ShowPanel(action.panel) end
    if action.character then return S.OpenCharacterPanelTab(action.character) end
    local module = ActiveModule(action.module)
    module:Open()
    return Tools.IsOpen(module)
end

local function Run(owner, row)
    if not row or NS.InCombat() then return end
    local action, state = row.action, owner.state
    if action and not Available(action) then return end
    local archive, query
    if row == owner.item then
        archive, query = ActiveModule("inventoryArchive"), row.query
        if not archive or not query then return end
    elseif not action then
        return
    end
    Tools.Close(owner)
    if archive then
        if archive:Browse("all", query) then Remember(state, "inventoryArchive") end
    elseif OpenAction(action) then
        Remember(state, action.key)
    else
        NS.Print(S.Text("Unavailable on this client or in combat."))
    end
end

local function CanFavorite(_, row) return row ~= nil and row.action ~= nil end
local function ToggleFavorite(owner, row)
    if not CanFavorite(owner, row) then return end
    local favorites = owner.state.favorites
    favorites[row.key] = not favorites[row.key] or nil
    Tools.Refresh(owner)
end

local SPEC = {
    title = "Quick actions",
    searchHint = "Search actions and items",
    help = "Use the arrow keys to select an action, then press Enter.",
    gamepad = true,
    empty = "No matching actions.",
    tabs = {
        { key = "all", label = "All" },
        { key = "favorites", label = "Favorites" },
        { key = "recent", label = "Recent actions" },
    },
    currentTab = function(owner) return owner.tab end,
    selectTab = function(owner, key) owner.tab = key end,
    rows = Rows,
    filter = function() return true end,
    activate = Run,
    menu = ToggleFavorite,
    actions = {
        { label = "Open", run = Run, enabled = function(_, row) return row ~= nil end },
        { label = "Toggle favorite", run = ToggleFavorite, enabled = CanFavorite },
    },
    onHide = function(owner)
        owner.item.query, owner.item.label, owner.state = nil, nil, nil
        wipe(owner.rows)
        wipe(owner.seen)
    end,
}

function Palette.Toggle(query)
    if NS.InCombat() then return false end
    if Tools.IsOpen(Palette) then
        Tools.Close(Palette)
        if not query then return true end
    end
    Palette.tab, Palette.state = "all", ReadState()
    InitEntries(Palette)
    return Tools.Open(Palette, SPEC, query) ~= nil
end
