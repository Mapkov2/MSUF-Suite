local _, NS = ...

-- Use the public menu proxies. Blizzard calls the response callback after
-- rebuilding rows, and may replace the description during that response.
local Rows = {}
NS.NativeMenuRows = Rows
local Safety = NS.Safety
local descriptions = setmetatable({}, { __mode = "k" })
local sessions = setmetatable({}, { __mode = "k" })
local active = {}
local MAX_NODES = 144

local function PaintRegions(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Safety.Public(region) and Safety.Read(region, "GetObjectType") == "FontString" then
            NS.LabelStyle.Apply(region, state, true, state.font)
            state.labels[region] = true
        end
    end
end

local function PaintNodes(state, depth, ...)
    for index = 1, select("#", ...) do
        if state.budget == 0 then return end
        state.budget = state.budget - 1
        local node = select(index, ...)
        if Safety.Public(node) and Safety.CanDecorate(node) and Safety.Read(node, "IsShown") ~= false then
            if depth == 1 then
                NS.BlizzardYellow.TrackMenuSelection(node)
                NS.Checkmarks.TrackFrame(node, state.owner)
            end
            PaintRegions(state, Safety.Call(node, "GetRegions"))
            if depth > 0 then PaintNodes(state, depth - 1, Safety.Call(node, "GetChildren")) end
        end
    end
end

local function MenuRow(wrapper, element)
    if Safety.Public(element) and type(element) == "table" then return element end
    return wrapper
end

local function OnInitialized(state, wrapper, element)
    if NS.IsCombatLocked() or active[state.menu] ~= state then return end
    local row = MenuRow(wrapper, element)
    if not Safety.Public(row) or type(row) ~= "table" then return end
    state.rows[row] = true
    NS.Registry.QueueJob(state.flush)
end

local function TrackScroll(state, scroll)
    if state.scroll or not Safety.Public(scroll) or not Safety.HasMethod(scroll, "RegisterCallback")
        or not Safety.HasMethod(scroll, "UnregisterCallback") then return end
    local event = ScrollBoxListMixin.Event.OnInitializedFrame
    state.scroll, state.event = scroll, event
    scroll:RegisterCallback(event, OnInitialized, state)
end

local function Paint(state)
    if active[state.menu] ~= state or not NS.DB or not NS.DB.enabled or NS.IsCombatLocked()
        or not Safety.CanDecorate(state.menu) or Safety.Read(state.menu, "IsShown") ~= true then return end
    local session, menu = state.session, state.menu
    local dropdown = session.dropdown
    if session.root == menu and dropdown then
        local description = Safety.Read(dropdown, "GetMenuDescription")
        if description and descriptions[description] ~= session
            and Rows.Track(dropdown, menu, state.owner) then return end
    end
    state.budget = MAX_NODES
    state.font = NS.LabelStyle.GetConfiguredPath() or false
    if state.full then
        state.full = false
        PaintNodes(state, 1, Safety.Call(menu, "GetChildren"))
        local scroll = Safety.Field(menu, "ScrollBox")
        if Safety.Public(scroll) and Safety.HasMethod(scroll, "ForEachFrame") then
            TrackScroll(state, scroll)
            scroll:ForEachFrame(state.paintRow)
        end
        for row in pairs(state.rows) do state.rows[row] = nil end
    else
        for row in pairs(state.rows) do
            state.rows[row] = nil
            PaintNodes(state, 1, row)
        end
    end
end

local function Release(state, restore)
    active[state.menu] = nil
    state.session.menus[state.menu] = nil
    state.restore = restore
    NS.Registry.QueueJob(state.cleanup)
end

local function Cleanup(state)
    if state.scroll then Safety.Invoke(state.scroll, "UnregisterCallback", state.event, state) end
    local restore = state.restore and not active[state.menu] and Safety.Read(state.menu, "IsShown") == true
    for label in pairs(state.labels) do NS.LabelStyle.Release(label, state, not restore) end
end

local function Acquire(session, menu)
    if not session.enabled or not Safety.Public(menu) or type(menu) ~= "table" then return end
    local old = active[menu]
    if old and old.session == session then return end
    if old then Release(old) end
    local state = {
        session = session, owner = session.owner, menu = menu, full = true,
        labels = setmetatable({}, { __mode = "k" }), rows = setmetatable({}, { __mode = "k" }),
    }
    state.flush = function() Paint(state) end
    state.cleanup = function() Cleanup(state) end
    state.paintRow = function(wrapper, element) PaintNodes(state, 1, MenuRow(wrapper, element)) end
    active[menu], session.menus[menu] = state, state
    NS.Registry.QueueJob(state.flush)
end

local function CloseSession(session, restore)
    if not session then return end
    session.enabled, session.root, session.dropdown = false, nil, nil
    for _, state in pairs(session.menus) do Release(state, restore) end
end

local function Bind(description, owner)
    local session = { owner = owner, menus = {} }
    descriptions[description] = session
    description:AddMenuResponseCallback(function()
        if not session.enabled then return end
        for _, state in pairs(session.menus) do
            state.full = true
            NS.Registry.QueueJob(state.flush)
        end
    end)
    if Safety.HasMethod(description, "AddMenuAcquiredCallback")
        and Safety.HasMethod(description, "AddMenuReleasedCallback") then
        description:AddMenuAcquiredCallback(function(proxy) Acquire(session, proxy) end)
        description:AddMenuReleasedCallback(function(proxy)
            if not Safety.Public(proxy) then return end
            local state = session.menus[proxy]
            if state then Release(state) end
        end)
    end
    return session
end

function Rows.Track(dropdown, menu, owner)
    local description = Safety.Read(dropdown, "GetMenuDescription")
    if not Safety.HasMethod(description, "AddMenuResponseCallback") then return false end
    local session = descriptions[description] or Bind(description, owner)
    local previous = sessions[dropdown]
    if previous and previous ~= session then CloseSession(previous) end
    sessions[dropdown], session.enabled, session.root, session.dropdown = session, true, menu, dropdown
    Acquire(session, menu)
    return true
end

function Rows.Close(dropdown, restore)
    CloseSession(sessions[dropdown], restore)
    sessions[dropdown] = nil
end

NS.Registry.AddListener(Rows, function(_, domain)
    if domain ~= "theme" and domain ~= "typography" and domain ~= "profile" then return end
    for _, state in pairs(active) do
        state.full = true
        NS.Registry.QueueJob(state.flush)
    end
end)
