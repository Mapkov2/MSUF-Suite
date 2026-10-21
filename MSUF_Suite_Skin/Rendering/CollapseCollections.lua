local _, NS = ...

-- These native menus rebuild frame pools instead of using a ScrollBox.
-- Observe the completed native layout; cached copies own their exit motion.
local Collections = { roots = setmetatable({}, { __mode = "k" }), hooks = {} }
NS.CollapseCollections = Collections
local Safety, Engine, Rows = NS.Safety, NS.AddonListMotion, NS.CollapseCollectionRows
local questPools = { "headerFramePool", "campaignHeaderFramePool", "campaignHeaderMinimalFramePool",
    "covenantCallingsHeaderFramePool", "titleFramePool", "objectiveFramePool" }

local function QuestRows(state, visit)
    for index = 1, #questPools do
        local pool = Safety.Field(state.root, questPools[index])
        if Safety.HasMethod(pool, "EnumerateActive") then
            for row in pool:EnumerateActive() do
                if state.count >= 128 then return end
                if Safety.Read(row, "IsVisible") == true then visit(row) end
            end
        end
    end
end

local function ChannelRows(state, visit)
    local buttons = Safety.Field(state.root, "buttons")
    if type(buttons) ~= "table" then return end
    for index = 1, math.min(#buttons, 128) do visit(buttons[index]) end
end

local function EncounterRows(state, visit)
    local headers = Safety.Field(state.scope, "usedHeaders")
    if type(headers) ~= "table" then return end
    for index = 1, math.min(#headers, 64) do
        local header = headers[index]
        if Safety.Read(header, "IsVisible") == true then
            visit(header)
            local description = Safety.Field(header, "description")
            if Safety.Read(description, "IsVisible") == true then visit(description) end
        end
    end
end

local function Context(state)
    if state.model == "quest" then return Safety.Read(Safety.Field(state.root, "SearchBox"), "GetText") end
    if state.model == "encounter" then return Safety.Field(state.contextRoot, "encounterID") end
end

local function Updated(root) Engine.RebuildCollection(root) end
local function QuestUpdated()
    for root, model in pairs(Collections.roots) do if model == "quest" then Updated(root) end end
end
local function EncounterLayoutFinished()
    for root, model in pairs(Collections.roots) do if model == "encounter" then Updated(root) end end
end

local function EncounterUpdated(_, doNotShift)
    if Safety.Public(doNotShift) and doNotShift ~= true then EncounterLayoutFinished() end
end

local function HookGlobal(name, callback)
    if Collections.hooks[name] or type(Safety.Field(_G, name)) ~= "function" then return end
    hooksecurefunc(name, Safety.Isolated(callback))
    Collections.hooks[name] = true
end

function Collections.Track(root, owner)
    if not Safety.CanCreateRegions(root) or Safety.GetProtection(root) then return end
    if Safety.Field(root, "headerFramePool") and Safety.Field(root, "titleFramePool") then
        Engine.TrackCollection(root, owner, "quest", QuestRows, Rows.Quest, Context)
        Collections.roots[root] = "quest"
        HookGlobal("QuestLogQuests_Update", QuestUpdated)
        return true
    end
    if Safety.Field(root, "headerButtonPool") and Safety.Field(root, "communityChannelButtonPool") then
        Engine.TrackCollection(root, owner, "channel", ChannelRows, Rows.Channel, Context)
        if not Collections.roots[root] and Safety.HasMethod(root, "Update") then
            hooksecurefunc(root, "Update", Safety.Isolated(Updated))
        end
        Collections.roots[root] = "channel"
        return true
    end
end

function Collections.TrackRoot(frame, owner)
    Collections.Track(frame, owner)
    local quests = Safety.Field(frame, "QuestsFrame")
    Collections.Track(Safety.Field(quests, "ScrollFrame"), owner)
    Collections.Track(Safety.Field(frame, "ChannelList"), owner)
    local encounter = Safety.Field(frame, "encounter")
    local scroll = NS.AdapterKit.Path(encounter, "info", "detailsScroll")
    if scroll and Safety.Field(encounter, "usedHeaders") then
        Engine.TrackCollection(scroll, owner, "encounter", EncounterRows, Rows.Encounter, Context, encounter, frame)
        Collections.roots[scroll] = "encounter"
        HookGlobal("EncounterJournal_ToggleHeaders", EncounterUpdated)
        HookGlobal("EncounterJournal_DisplayEncounter", EncounterLayoutFinished)
    end
end

NS.GenericWindows.SetCollapseMotionProvider(Collections.TrackRoot, Engine.DisableOwner)
