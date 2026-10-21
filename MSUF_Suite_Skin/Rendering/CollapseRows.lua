local _, NS = ...

-- Native tree nodes keep their identity while toggling. The linear
-- lists below rebuild their providers and expose stable category identities.
local Rows = {}
NS.CollapseRows = Rows
local Safety = NS.Safety
local kinds = { ReputationFrame = "reputation", SkillsFrame = "skills", TokenFrame = "currency",
    AchievementFrameCategories = "achievement", LFDQueueFrame = "dungeon", RaidFinderQueueFrame = "dungeon",
    ScenarioQueueFrame = "dungeon" }
local ids = { reputation = "factionID", skills = "skillID", currency = "currencyID" }
local arrows = { "CollapseExpand", "CollapseIcon", "ToggleCollapseButton", "CollapseButton", "StateIcon", "Toggle",
    "expandOrCollapseButton", "Collapsed" }

function Rows.Model(target, provider)
    if Safety.HasMethod(provider, "GetRootNode") then return "tree" end
    for _ = 1, 5 do
        if not target then return end
        if Safety.HasMethod(target, "CreateCategories") and Safety.HasMethod(target, "GetCategorySet") then
            return "settings", target
        end
        local name = Safety.Read(target, "GetName")
        if type(name) == "string" and kinds[name] then return kinds[name], target end
        target = Safety.Read(target, "GetParent")
    end
end

local function Tree(node)
    if not Safety.HasMethod(node, "GetData") or not Safety.HasMethod(node, "IsCollapsed") then return end
    local size = Safety.Read(node, "GetSize")
    local collapsed
    if type(size) == "number" and size > 0 then
        local value = Safety.Call(node, "IsCollapsed")
        if Safety.Public(value) then collapsed = value == true end
    end
    return node, collapsed, Safety.Read(node, "GetParent")
end

local function Settings(node)
    local data = Safety.Field(node, "data")
    local category = Safety.Field(data, "category")
    if not Safety.HasMethod(category, "IsExpanded") then return end
    local expanded = Safety.Read(category, "IsExpanded")
    local children = Safety.Read(category, "GetSubcategories")
    local collapsed
    if type(expanded) == "boolean" and type(children) == "table" and #children > 0 then collapsed = not expanded end
    return category, collapsed, Safety.Read(category, "GetParentCategory")
end

local function Linear(state, node)
    local header = Safety.Field(node, "isHeader") == true
    local key = Safety.Field(node, ids[state.model])
    if type(key) ~= "number" or key <= 0 then key = Safety.Field(node, "name") end
    if type(key) ~= "number" and type(key) ~= "string" then return end
    local depth = Safety.Field(node, "currencyListDepth")
    if type(depth) ~= "number" then depth = Safety.Field(node, "isChild") == true and 1 or 0 end
    local parentDepth = depth
    if state.model ~= "currency" and not header then parentDepth = depth + 1 end
    local parent = state.headerStack[parentDepth] or not header and state.headerStack[1] or nil
    if type(key) == "string" then key = (header and "header:" or "entry:") .. (parent or "") .. "/" .. key end
    local collapsed
    if header then
        if state.model == "currency" then
            local expanded = Safety.Field(node, "isHeaderExpanded")
            if type(expanded) == "boolean" then collapsed = not expanded end
        else
            local value = Safety.Field(node, "isCollapsed")
            if type(value) == "boolean" then collapsed = value end
        end
        state.headerStack[depth + 1] = key
        for index = depth + 2, 8 do state.headerStack[index] = nil end
    end
    return key, collapsed, parent
end

local function Achievement(node)
    local key = Safety.Field(node, "id")
    if type(key) ~= "number" and type(key) ~= "string" then return end
    local parent, collapsed = Safety.Field(node, "parent"), nil
    if parent == true then
        local value = Safety.Field(node, "collapsed")
        if type(value) == "boolean" then collapsed = value end
        parent = nil
    elseif type(parent) ~= "number" then parent = nil end
    return key, collapsed, parent
end

local function Dungeon(state, node, row)
    local key = Safety.Field(node, "dungeonID")
    if type(key) ~= "number" then return end
    if Safety.Read(Safety.Field(row, "expandOrCollapseButton"), "IsShown") == true then
        state.headerStack[1] = key
        local value = Safety.Field(row, "isCollapsed")
        if type(value) == "boolean" then return key, value end
    end
    return key, nil, state.headerStack[1]
end

function Rows.Ancestors(state, parent)
    for _ = 1, 16 do
        if not parent or state.currentCollapsed[parent] ~= nil then return end
        local node, collapsed, ancestor = Tree(parent)
        if not node then return end
        state.currentCollapsed[node], state.newParents[node] = collapsed, ancestor
        parent = ancestor
    end
end

function Rows.Context(state)
    if state.model == "settings" then return Safety.Read(state.contextRoot, "GetCategorySet") end
end

function Rows.Resolve(state, node, row)
    if state.model == "tree" then return Tree(node) end
    if state.model == "settings" then return Settings(node) end
    if state.model == "achievement" then return Achievement(node) end
    if state.model == "dungeon" then return Dungeon(state, node, row) end
    return Linear(state, node)
end

function Rows.Arrow(row)
    for index = 1, #arrows do
        local arrow = Safety.Field(row, arrows[index])
        if Safety.CanCreateRegions(arrow) and Safety.HasMethod(arrow, "CreateAnimationGroup") then return arrow end
    end
    return Safety.Read(row, "GetCollapseButton")
end
