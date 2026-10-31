local _, NS = ...

-- Cold, bounded walks start only at explicitly adopted menu roots. Existing
-- row callbacks register deeper lists without scanning UIParent or globals.
local Menus = { states = setmetatable({}, { __mode = "k" }) }
NS.MenuMotion = Menus
local Safety, Content = NS.Safety, NS.ContentMotion
local bodyKeys = { "Content", "content", "ContentFrame", "PanelContainer" }
-- Frame identity, not child count, decides whether discovery is reusable.
-- These are the optional capabilities consulted by the motion providers.
local shapeKeys = { "GetDataProvider", "RegisterCallback", "CreateAnimationGroup", "GetScrollChild",
    "headerFramePool", "titleFramePool", "headerButtonPool", "communityChannelButtonPool" }
local walk, children, Schedule

local function Safe(frame)
    if not Safety.CanCreateRegions(frame) then return end
    local kind = Safety.Read(frame, "GetObjectType")
    if kind and kind ~= "GameTooltip" and Safety.HasMethod(frame, "HookScript") then return kind end
end

local function TrackChecked(frame, owner, kind)
    local collection = NS.CollapseCollections.Track(frame, owner)
    if Safety.HasMethod(frame, "GetDataProvider") and Safety.HasMethod(frame, "RegisterCallback") then
        NS.ResultMotion.Track(frame, owner)
        NS.ScrollMotion.Track(frame, owner)
        return true, true
    elseif kind == "ScrollFrame" then
        NS.LegacyScrollMotion.Track(frame, owner)
        return false, true
    end
    return false, collection == true
end

function Menus.TrackTarget(frame, owner)
    local kind = Safe(frame)
    if kind and TrackChecked(frame, owner, kind) then return true end
end

-- Only discovery retains these public identities. Protection and visibility
-- are read again on every pass; no native/secret result is cached for painting.
local function Fields(record, keys, values, remember)
    for index = 1, #keys do
        local value = Safety.Field(record.frame, keys[index])
        if not Safety.Public(value) then return false end
        if remember then values[index] = value elseif values[index] ~= value then return false end
    end
    return true
end

local function Bodies(record, remember, owner)
    if not Fields(record, bodyKeys, record.bodies, remember) then return false end
    for index = 1, #bodyKeys do
        local body = record.bodies[index]
        local kind = body ~= nil and body ~= record.frame and Safe(body) or nil
        if remember then record.bodyKinds[index] = kind elseif record.bodyKinds[index] ~= kind then return false end
        if kind then
            local method = Safety.Field(body, "CreateAnimationGroup")
            if not Safety.Public(method) then return false end
            if remember then record.bodyMethods[index] = method elseif record.bodyMethods[index] ~= method then return false end
        elseif remember then record.bodyMethods[index] = nil end
        if not remember and record.watched[index] then
            local watch = Content.watchers[body]
            if not watch or not watch.owners[owner] then return false end
        end
    end
    return true
end

local function SameChildren(record, ...)
    if record.count ~= select("#", ...) then return false end
    for index = 1, record.count do
        local child = select(index, ...)
        if not Safety.Public(child) or record.children[index] ~= child then return false end
    end
    return true
end

local function Current(state)
    if not state.reusable or state.cacheOwner ~= state.owner then return false end
    for index = 1, state.length do
        local record = state.records[index]
        local kind = Safe(record.frame)
        if record.kind ~= kind then return false end
        if kind then
            if not Fields(record, shapeKeys, record.shape, false) then return false end
            if not record.leaf and (not Bodies(record, false, state.owner)
                or not record.terminal and not SameChildren(record, Safety.Call(record.frame, "GetChildren"))) then return false end
        end
    end
    return true
end

local function RefreshTargets(state)
    -- Existing lists may replace a provider/scroll partner without changing
    -- their frame tree. Their native binding owners still reconcile each edge.
    for index = 1, state.length do
        if not next(state.owners) then return end
        local record = state.records[index]
        if record.target then Menus.TrackTarget(record.frame, state) end
    end
end

local function ReleaseMotionTarget(owner)
    NS.ResultMotion.ReleaseOwner(owner)
    NS.ScrollMotion.ReleaseOwner(owner)
    NS.LegacyScrollMotion.ReleaseOwner(owner)
    NS.AddonListMotion.DisableOwner(owner)
end

local function ScanNow(state)
    if not next(state.owners) or not Safe(state.root) or Safety.Read(state.root, "IsVisible") ~= true then
        state.completed = true
        return
    end
    if not state.discover and Current(state) then RefreshTargets(state) state.completed = true return end
    state.discover, state.reusable, state.buildValid, state.length = false, false, true, 0
    state.budget, state.edges, state.content = 480, 0, nil
    for frame in pairs(state.observed) do state.observed[frame] = false end
    state.observed[state.root] = true
    walk(state, state.root, 0)
    for index = #state.records, state.length + 1, -1 do state.records[index] = nil end
    state.cacheOwner = state.owner
    state.reusable = state.buildValid
    if state.reusable then
        for frame, kept in pairs(state.observed) do
            if not kept then
                Menus.observers[frame][state] = nil
                state.observed[frame] = nil
            end
        end
    else
        wipe(state.records)
        state.length = 0
    end
    state.completed = true
end

local function Scan(state)
    if state.scanning then
        state.discover = true
        if not state.reentryQueued then state.reentryQueued = true Schedule(state, true) end
        return
    end
    state.queued, state.scanning, state.completed = false, true, false
    -- A native provider can reenter Track/Release or fail. Its boundary also
    -- guarantees that the guard is released and partial snapshots stay cold.
    Safety.Dispatch(ScanNow, state)
    state.scanning = false
    if not state.completed then state.reusable = false end
    if state.dropRecords or not next(state.owners) then
        local dropped = state.dropRecords
        wipe(state.records)
        state.length, state.reusable, state.dropRecords = 0, false, nil
        if dropped and not next(state.owners) then ReleaseMotionTarget(state) end
    end
end

Schedule = function(state, discover)
    if not state.scanning then state.reentryQueued = false end
    if discover then state.discover = true end
    if state.queued or not next(state.owners) then return end
    state.queued = true
    NS.Registry.QueueJob(state.scan)
end

local function Resized(frame)
    local states = Menus.observers[frame]
    for state in pairs(states) do Schedule(state) end
end

local function Shown(frame)
    local states = Menus.observers[frame]
    for state in pairs(states) do Schedule(state, true) end
end
Menus.observers = setmetatable({}, { __mode = "k" })

local function Observe(state, frame)
    local states = Menus.observers[frame]
    if not states then
        states = {}
        Menus.observers[frame] = states
        frame:HookScript("OnShow", Shown)
        if Safety.Read(frame, "HasScript", "OnSizeChanged") then frame:HookScript("OnSizeChanged", Resized) end
    end
    states[state] = true
    state.observed[frame] = true
end

children = function(state, record, depth, ...)
    local count = select("#", ...)
    if record then
        local first = ...
        if count ~= 1 or not Safety.Public(first) or first ~= nil then state.edges = state.edges + count end
        if state.edges > 480 then state.buildValid = false record = nil end
    end
    if record then
        for index = #record.children, count + 1, -1 do record.children[index] = nil end
        record.count = count
    end
    for index = 1, select("#", ...) do
        if state.budget <= 0 or not next(state.owners) then state.buildValid = false return end
        local child = select(index, ...)
        if Safety.Public(child) then
            if record and state.buildValid then record.children[index] = child end
            if type(child) == "table" then walk(state, child, depth) end
        else
            state.buildValid = false
        end
    end
end

local function Record(state, frame, kind)
    if not state.buildValid then return end
    if state.length >= 480 then state.buildValid = false return end
    local index = state.length + 1
    local record = state.records[index]
    if not record then
        record = { shape = {}, bodies = {}, bodyKinds = {}, bodyMethods = {}, watched = {}, children = {} }
        state.records[index] = record
    end
    if record.frame ~= frame or not kind then
        wipe(record.shape)
        wipe(record.bodies)
        wipe(record.bodyKinds)
        wipe(record.bodyMethods)
        wipe(record.watched)
        wipe(record.children)
    end
    record.frame, record.kind, record.leaf, record.target = frame, kind, false, false
    state.length = index
    return record
end

walk = function(state, frame, depth)
    if state.budget <= 0 or not next(state.owners) then state.buildValid = false return end
    if depth > 8 then return end
    local kind = Safe(frame)
    local record = Record(state, frame, kind)
    if record then record.terminal = depth == 8 end
    if not kind then return end
    state.budget = state.budget - 1
    -- Observe/Track can call native hooks. Keep the provider's own guards and
    -- read permissions fresh after those calls, rather than caching a lease.
    local leaf, target = TrackChecked(frame, state, kind)
    if record then record.leaf, record.target = leaf, target end
    if not next(state.owners) then state.buildValid = false return end
    if Safety.IsForbidden(frame) then state.buildValid = false return end
    if record and not Fields(record, shapeKeys, record.shape, true) then state.buildValid = false end
    if leaf then
        if record then
            wipe(record.children) wipe(record.bodies) wipe(record.bodyKinds) wipe(record.bodyMethods) wipe(record.watched)
            record.count = 0
        end
        return
    end
    for index = 1, #bodyKeys do
        local body = Safety.Field(frame, bodyKeys[index])
        if record then record.watched[index] = false end
        if Safety.Public(body) and type(body) == "table" and body ~= frame then
            if not state.content then state.content = body end
            if Safe(body) then Observe(state, body)
            elseif state.observed[body] ~= nil then state.observed[body] = true end
            local watched = Content.Watch(body, state.owner)
            if record then record.watched[index] = watched == true end
        end
    end
    if Safety.IsForbidden(frame) then state.buildValid = false return end
    if record and not Bodies(record, true) then state.buildValid = false end
    if depth < 8 then
        children(state, record, depth + 1, Safety.Call(frame, "GetChildren"))
    elseif record then
        wipe(record.children)
        record.count = 0
    end
end

function Menus.Track(root, owner, contentOnly)
    if owner == nil or not Safe(root) or NS.Motion.combat or NS.IsCombatLocked() then return false end
    -- Authored tab bodies already identify the exact content container.
    -- Watch it once; its descendants need neither discovery nor registration.
    if contentOnly then return Content.Watch(root, owner) end
    local state = Menus.states[root]
    if not state then
        state = { root = root, owners = {}, observed = {}, records = {} }
        state.scan = function() Scan(state) end
        Menus.states[root] = state
    end
    state.owners[owner], state.owner = true, owner
    Content.Watch(root, owner)
    Observe(state, root)
    state.discover = true
    if not state.scanning then state.reentryQueued = false end
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
            state.owner, state.cacheOwner = next(state.owners), nil
            if not next(state.owners) then
                ReleaseMotionTarget(state)
                for frame in pairs(state.observed) do Menus.observers[frame][state] = nil end
                wipe(state.observed)
                if state.scanning then state.dropRecords = true else wipe(state.records) state.length = 0 end
                state.buildValid = false
                state.reusable = false
            else Schedule(state, true) end
        end
    end
    Content.UnwatchOwner(owner)
    -- UnwatchOwner spans every root. Other menus held by this same owner
    -- must restore their bodies even when their frame identities stayed put.
    for _, state in pairs(Menus.states) do
        if state.owners[owner] then
            Content.Watch(state.root, owner)
            Schedule(state, true)
        end
    end
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
    for _, state in pairs(Menus.states) do Schedule(state, true) end
end
NS.Registry.AddListener(Menus, Refresh)
NS.GenericWindows.SetMenuMotionProvider(Menus.Track, Menus.Release)
NS.Adapters.SetMenuMotionProvider(Menus.Track, Menus.Release)
NS.AdapterKit.SetMotionProvider(Menus.TrackTarget, Content.Watch)
NS.Checkmarks.SetSettingsMotionProvider(SettingsChanged, Menus.Release)
NS.PublicAPI.TrackMenu, NS.PublicAPI.ReleaseMenu = Menus.Track, Menus.Release

NS.SocialUISkin.SetMotionProvider(Menus.TrackTarget, ReleaseMotionTarget)
