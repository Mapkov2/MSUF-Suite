local _, NS = ...

-- Cold, bounded walks start only at explicitly adopted menu roots. Existing
-- row callbacks register deeper lists without scanning UIParent or globals.
local Menus = { states = setmetatable({}, { __mode = "k" }) }
NS.MenuMotion = Menus
local Safety, Content = NS.Safety, NS.ContentMotion
local bodyKeys = { "Content", "content", "ContentFrame", "PanelContainer" }
local walk, children

local function Safe(frame)
    return Safety.CanCreateRegions(frame) and Safety.HasMethod(frame, "HookScript")
        and Safety.HasMethod(frame, "GetObjectType") and not Safety.GetProtection(frame)
        and Safety.Read(frame, "GetObjectType") ~= "GameTooltip"
end

function Menus.TrackTarget(frame, owner)
    if not Safe(frame) then return end
    NS.CollapseCollections.Track(frame, owner)
    if Safety.HasMethod(frame, "GetDataProvider") and Safety.HasMethod(frame, "RegisterCallback") then
        NS.ResultMotion.Track(frame, owner)
        NS.ScrollMotion.Track(frame, owner)
        return true
    elseif Safety.Read(frame, "GetObjectType") == "ScrollFrame" then
        NS.LegacyScrollMotion.Track(frame, owner)
    end
end

local function Scan(state)
    state.queued = false
    if not next(state.owners) or not Safe(state.root) or Safety.Read(state.root, "IsVisible") ~= true then return end
    state.budget, state.content = 480, nil
    walk(state, state.root, 0)
end

local function Schedule(state)
    if state.queued or not next(state.owners) then return end
    state.queued = true
    NS.Registry.QueueJob(state.scan)
end

local function Changed(frame)
    local states = Menus.observers[frame]
    for state in pairs(states) do Schedule(state) end
end
Menus.observers = setmetatable({}, { __mode = "k" })

local function Observe(state, frame)
    local states = Menus.observers[frame]
    if not states then
        states = {}
        Menus.observers[frame] = states
        frame:HookScript("OnShow", Changed)
        if Safety.Read(frame, "HasScript", "OnSizeChanged") then frame:HookScript("OnSizeChanged", Changed) end
    end
    states[state] = true
    state.observed[frame] = true
end

children = function(state, depth, ...)
    for index = 1, select("#", ...) do
        if state.budget <= 0 then return end
        local child = select(index, ...)
        if Safety.Public(child) and type(child) == "table" and Safe(child) then walk(state, child, depth) end
    end
end

walk = function(state, frame, depth)
    if state.budget <= 0 or depth > 8 or not Safe(frame) then return end
    state.budget = state.budget - 1
    if depth == 0 then Observe(state, frame) end
    if Menus.TrackTarget(frame, state) then return end
    for index = 1, #bodyKeys do
        local body = Safety.Field(frame, bodyKeys[index])
        if Safety.Public(body) and type(body) == "table" and body ~= frame then
            if not state.content then state.content = body end
            if Safe(body) then Observe(state, body) end
            Content.Watch(body, state.owner)
        end
    end
    children(state, depth + 1, Safety.Call(frame, "GetChildren"))
end

function Menus.Track(root, owner, contentOnly)
    if owner == nil or not Safe(root) or NS.Motion.combat or NS.IsCombatLocked() then return false end
    -- Authored tab bodies already identify the exact content container.
    -- Watch it once; its descendants need neither discovery nor registration.
    if contentOnly then return Content.Watch(root, owner) end
    local state = Menus.states[root]
    if not state then
        state = { root = root, owners = {}, observed = {} }
        state.scan = function() Scan(state) end
        Menus.states[root] = state
    end
    state.owners[owner], state.owner = true, owner
    Content.Watch(root, owner)
    Observe(state, root)
    Scan(state)
    return true
end

local function StateFor(frame)
    for _ = 1, 16 do
        local states = Menus.observers[frame]
        if states then
            for state in pairs(states) do
                if next(state.owners) then return state end
            end
        end
        frame = Safety.Read(frame, "GetParent")
        if not frame then return end
    end
end

function Menus.OwnerFor(frame)
    local state = StateFor(frame)
    return state and state.owner
end

function Menus.SelectionChanged(tab)
    local state = StateFor(tab)
    if state and state.content then Content.Play(state.content, state.owner, tab) end
end

function Menus.Release(owner, root)
    for target, state in pairs(Menus.states) do
        if root == nil or root == target then
            state.owners[owner] = nil
            state.owner = next(state.owners)
            if not next(state.owners) then
                NS.ResultMotion.ReleaseOwner(state)
                NS.ScrollMotion.ReleaseOwner(state)
                NS.LegacyScrollMotion.ReleaseOwner(state)
                NS.AddonListMotion.DisableOwner(state)
                for frame in pairs(state.observed) do Menus.observers[frame][state] = nil end
                wipe(state.observed)
            else Schedule(state) end
        end
    end
    Content.UnwatchOwner(owner)
end

local function SettingsChanged(state, category)
    local panel = state.settingsPanel
    local list = Safety.Read(panel, "GetSettingsList") or Safety.Field(Safety.Field(panel, "Container"), "SettingsList")
    local canvas = Safety.Read(panel, "GetSettingsCanvas") or Safety.Field(Safety.Field(panel, "Container"), "SettingsCanvas")
    local target = Safety.Read(canvas, "IsShown") == true and canvas or list
    if target and state.motionCategory ~= category then
        state.motionCategory = category
        Menus.Track(target, state)
        Content.Play(target, state, category)
    end
end

local function Refresh(_, domain)
    if domain ~= "profile" and domain ~= "adapter" then return end
    for _, state in pairs(Menus.states) do Schedule(state) end
end
NS.Registry.AddListener(Menus, Refresh)
NS.GenericWindows.SetMenuMotionProvider(Menus.Track, Menus.Release)
NS.Adapters.SetMenuMotionProvider(Menus.Track, Menus.Release)
NS.AdapterKit.SetMotionProvider(Menus.TrackTarget, Content.Watch)
NS.Checkmarks.SetSettingsMotionProvider(SettingsChanged, Menus.Release)
NS.PublicAPI.TrackMenu, NS.PublicAPI.ReleaseMenu = Menus.Track, Menus.Release

local function ReleaseMotionTarget(owner)
    NS.ResultMotion.ReleaseOwner(owner)
    NS.ScrollMotion.ReleaseOwner(owner)
    NS.LegacyScrollMotion.ReleaseOwner(owner)
    NS.AddonListMotion.DisableOwner(owner)
end
NS.SocialUISkin.SetMotionProvider(Menus.TrackTarget, ReleaseMotionTarget)
