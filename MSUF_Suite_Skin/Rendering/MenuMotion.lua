local _, NS = ...

-- Cold, bounded walks start only at explicitly adopted menu roots. Existing
-- row callbacks register deeper lists without scanning UIParent or globals.
local Menus = { states = setmetatable({}, { __mode = "k" }) }
NS.MenuMotion = Menus
local Safety, Content = NS.Safety, NS.ContentMotion
local HasSecret = hasanysecretvalues
local bodyKeys = { "Content", "content", "ContentFrame", "PanelContainer" }
local emptyChildren = {}
local walk, children, Schedule, Observe

local function Safe(frame)
    if not Safety.CanCreateRegions(frame) then return end
    local kind = Safety.Read(frame, "GetObjectType")
    if kind and kind ~= "GameTooltip" and Safety.HasMethod(frame, "HookScript") then return kind end
end

-- Every modern list, quest collection and channel collection has one of
-- these three public fields. Ordinary widgets cannot bind a motion provider.
local function NoMotionBinding(frame)
    local provider, quest, channel = frame.GetDataProvider, frame.headerFramePool, frame.headerButtonPool
    if HasSecret then
        if HasSecret(provider, quest, channel) then return false end
    elseif not (Safety.Public(provider) and Safety.Public(quest) and Safety.Public(channel)) then return false end
    return provider == nil and quest == nil and channel == nil
end

local function TrackChecked(frame, owner, kind)
    if kind ~= "ScrollFrame" and NoMotionBinding(frame) then return false, false end
    local groupFinder = NS.ForeverGroupFinder
    if groupFinder and groupFinder.IsActivityList and groupFinder.IsActivityList(frame) then return false, false end
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
-- Read the optional motion capabilities once per pass. No identity is used
-- until the entire tuple is public, including the optional collection pools.
local function ShapeFields(record, remember)
    local frame, values = record.frame, record
    local provider, callback = frame.GetDataProvider, frame.RegisterCallback
    local animation, scroll = frame.CreateAnimationGroup, frame.GetScrollChild
    local headers, titles = frame.headerFramePool, frame.titleFramePool
    local buttons, channels = frame.headerButtonPool, frame.communityChannelButtonPool
    if not remember and HasSecret and not record.bodies and not record.leaf then
        local content, lower, panel, container = frame.Content, frame.content, frame.ContentFrame, frame.PanelContainer
        if HasSecret(provider, callback, animation, scroll, headers, titles, buttons, channels, content, lower, panel, container) then return false end
        if content ~= nil or lower ~= nil or panel ~= nil or container ~= nil then return false end
    elseif HasSecret then
        if HasSecret(provider, callback, animation, scroll, headers, titles, buttons, channels) then return false end
    elseif not (Safety.Public(provider) and Safety.Public(callback) and Safety.Public(animation) and Safety.Public(scroll)
        and Safety.Public(headers) and Safety.Public(titles) and Safety.Public(buttons) and Safety.Public(channels)) then return false end
    if remember then
        values[1], values[2], values[3], values[4] = provider, callback, animation, scroll
        values[5], values[6], values[7], values[8] = headers, titles, buttons, channels
        return true
    end
    return provider == values[1] and callback == values[2] and animation == values[3] and scroll == values[4]
        and headers == values[5] and titles == values[6] and buttons == values[7] and channels == values[8]
end

local function NoBodies(frame)
    local content, lower, panel, container = frame.Content, frame.content, frame.ContentFrame, frame.PanelContainer
    if HasSecret then
        if HasSecret(content, lower, panel, container) then return end
    elseif not (Safety.Public(content) and Safety.Public(lower) and Safety.Public(panel) and Safety.Public(container)) then return false end
    return content == nil and lower == nil and panel == nil and container == nil
end

local function Bodies(record, remember, owner)
    local frame, values = record.frame, record.bodies
    local content, lower, panel, container = frame.Content, frame.content, frame.ContentFrame, frame.PanelContainer
    if HasSecret then
        if HasSecret(content, lower, panel, container) then return false end
    elseif not (Safety.Public(content) and Safety.Public(lower) and Safety.Public(panel) and Safety.Public(container)) then return false end
    if not values then return content == nil and lower == nil and panel == nil and container == nil end
    if remember then
        values[1], values[2], values[3], values[4] = content, lower, panel, container
        record.hasBodies = false
    elseif not record.hasBodies then
        return content == nil and lower == nil and panel == nil and container == nil
    elseif content ~= values[1] or lower ~= values[2] or panel ~= values[3] or container ~= values[4] then return false end
    for index = 1, #bodyKeys do
        local body = record.bodies[index]
        if remember and body ~= nil then record.hasBodies = true end
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
    local count = select("#", ...)
    -- The discovery walk uses Safety.Call, which represents no returns as
    -- one nil. The warm path can recognize an empty native tuple directly.
    if count == 0 then return record.count == 1 and record.children == emptyChildren end
    if record.count ~= count then return false end
    if record.count == 1 then
        local child = ...
        return Safety.Public(child) and record.children[1] == child
    end
    if HasSecret then
        if HasSecret(...) then return false end
        for index = 1, record.count do
            if record.children[index] ~= select(index, ...) then return false end
        end
        return true
    end
    for index = 1, record.count do
        local child = select(index, ...)
        if not Safety.Public(child) or record.children[index] ~= child then return false end
    end
    return true
end

local function CurrentChildren(record)
    local frame = record.frame
    if not Safety.IsForbidden(frame) then
        local getter = Safety.ReadableMethod(frame, "GetChildren")
        if getter then return SameChildren(record, getter(frame)) end
    end
    return SameChildren(record)
end

-- A named pane can be replaced without changing the native child count.
-- Keep only public, current identities of the authored direct children.
local function SyncDeferredPanes(state)
    local adapter = NS.CommunitiesSkin
    local active = adapter and adapter.activeState
    if not active or not active.active or active.frame ~= state.root or state.root ~= CommunitiesFrame or not NS.Client.isForever then
        if state.panes then state.panes, state.paneKeys, state.discover = nil, nil, true end
        return
    end
    local keys = adapter.deferredMotionPanes
    local previous = state.paneKeys or {}
    state.paneKeys = previous
    for index = 1, #keys do
        local pane = Safety.Field(state.root, keys[index])
        if not Safety.Public(pane) or type(pane) ~= "table"
            or not adapter.CanDeferMotionPane(active, keys[index], pane) then pane = nil end
        if previous[index] ~= pane then
            previous[index], state.discover = pane, true
            state.panes = nil
        end
    end
    if not state.panes then
        state.panes = {}
        for index = 1, #keys do
            local pane = previous[index]
            if pane then state.panes[pane] = true end
        end
    elseif not state.discover then
        for pane, status in pairs(state.panes) do
            if status == "hidden" and Safety.Read(pane, "IsShown") ~= false then
                state.discover = true
                return
            end
        end
    end
end

local function Current(state)
    if not state.reusable or state.cacheOwner ~= state.owner then return false end
    for index = 1, state.length do
        local record = state.records[index]
        local kind = Safe(record.frame)
        if record.kind ~= kind then return false end
        if kind then
            if not ShapeFields(record, false) then return false end
            if not record.leaf then
                if (record.bodies or not HasSecret) and not Bodies(record, false, state.owner) then return false end
                if not record.terminal and not CurrentChildren(record) then return false end
            end
        end
    end
    return true
end

local function RefreshTargets(state)
    -- Existing lists may replace a provider/scroll partner without changing
    -- their frame tree. Their native binding owners still reconcile each edge.
    local targets = state.targets
    if not targets then return end
    for index = 1, #targets do
        if not next(state.owners) then return end
        Menus.TrackTarget(targets[index], state)
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
    -- Catalog preparation may precede the first OnShow observer.
    state.rootHidden = nil
    SyncDeferredPanes(state)
    if not state.discover and Current(state) then RefreshTargets(state) state.completed = true return end
    state.discover, state.reusable, state.buildValid, state.length = false, false, true, 0
    state.budget, state.edges, state.content = 480, 0, nil
    if state.panes then
        -- This is already a cold rebuild. Spend its finite budget on the
        -- currently visible panes; their persistent OnShow hooks cover reuse.
        for pane in pairs(state.panes) do state.panes[pane] = true end
    end
    if state.targets then wipe(state.targets) end
    for frame in pairs(state.observed) do state.observed[frame] = false end
    Observe(state, state.root)
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
        state.targets = nil
        state.length = 0
    end
    state.completed = true
end

-- The root already counted each unopened direct pane once. Extend its
-- existing snapshot with just that subtree and charge against its remaining
-- budget. A later native root/size notification can verify the same records.
local function AppendPane(state, pane)
    if not state.panes or state.panes[pane] ~= "hidden" then return end
    if not state.reusable or state.cacheOwner ~= state.owner then Schedule(state, true) return end
    if not Safe(state.root) or Safety.Read(pane, "GetParent") ~= state.root
        or Safety.Read(pane, "IsVisible") ~= true then return end
    state.reusable = false
    local remaining = state.budget
    state.budget = remaining + 1
    walk(state, pane, 1)
    state.budget = math.min(remaining, state.budget)
    state.reusable = state.buildValid == true
end

local function Scan(state, pane)
    if state.scanning then
        if pane then
            state.pendingPanes = state.pendingPanes or {}
            state.pendingPanes[pane] = true
            return
        end
        state.discover = true
        if not state.reentryQueued then state.reentryQueued = true Schedule(state, true) end
        return
    end
    state.scanning, state.completed = true, false
    -- A native provider can reenter Track/Release or fail. Its boundary also
    -- guarantees that the guard is released and partial snapshots stay cold.
    if pane then
        Safety.Dispatch(AppendPane, state, pane)
        state.completed = true
    else Safety.Dispatch(ScanNow, state) end
    if state.pendingPanes then
        -- Even a reentrant foreign provider cannot exceed the number of
        -- authored direct children. Reconcile any remaining signals together.
        for _ = 1, #NS.CommunitiesSkin.deferredMotionPanes do
            local pending = next(state.pendingPanes)
            if not pending or not next(state.owners) then break end
            state.pendingPanes[pending] = nil
            Safety.Dispatch(AppendPane, state, pending)
            if not state.pendingPanes then break end
        end
        if state.pendingPanes and next(state.pendingPanes) then
            wipe(state.pendingPanes)
            Schedule(state, true)
        end
    end
    state.scanning = false
    if not state.completed then state.reusable = false end
    if state.dropRecords or not next(state.owners) then
        local dropped = state.dropRecords
        wipe(state.records)
        state.targets = nil
        state.length, state.reusable, state.dropRecords = 0, false, nil
        if dropped and not next(state.owners) then ReleaseMotionTarget(state) end
    end
end

Schedule = function(state, discover)
    if not state.scanning then state.reentryQueued = false end
    if discover then state.discover = true end
    if state.queued or state.rootHidden or not next(state.owners) then return end
    state.queued = true
    NS.Registry.QueueJob(state.scan)
end

local function NotifyObservers(frame)
    local visible
    for state, relation in pairs(Menus.observers[frame]) do
        if not state.rootHidden and not state.queued then
            if not visible then
                visible = Safety.Read(frame, "IsVisible") == true
                if not visible then return end
            end
            if relation ~= "descendant" or NS.AdapterKit.IsDescendantOf(frame, state.root) then Schedule(state) end
        end
    end
end

local function Shown(frame)
    local root = Menus.states[frame]
    if root then root.rootHidden = nil end
    -- A reopened panel can reuse discovery if its live children, bodies and
    -- capabilities still match. The content watcher owns the opening fade.
    NotifyObservers(frame)
end

local function CancelScan(state)
    if state.queued then
        NS.Registry.CancelJob(state.scan)
        state.queued = false
    end
end

local function Hidden(root)
    local state = Menus.states[root]
    state.rootHidden = true
    CancelScan(state)
end
Menus.observers = setmetatable({}, { __mode = "k" })

Observe = function(state, frame)
    local states = Menus.observers[frame]
    if not states then
        states = {}
        Menus.observers[frame] = states
        frame:HookScript("OnShow", Shown)
        if Safety.Read(frame, "HasScript", "OnSizeChanged") then frame:HookScript("OnSizeChanged", NotifyObservers) end
    end
    if not states[state] then
        -- Authored bodies may intentionally live outside the tree. Only require
        -- ancestry on signals from bodies first adopted inside this root.
        states[state] = frame ~= state.root and NS.AdapterKit.IsDescendantOf(frame, state.root) and "descendant" or true
    end
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
        if count == 0 or count == 1 and Safety.Public(...) and (...) == nil then
            record.children = emptyChildren
        elseif record.children == emptyChildren then
            record.children = {}
        else
            for index = record.count, count + 1, -1 do record.children[index] = nil end
        end
        record.count = count
    end
    for index = 1, select("#", ...) do
        if state.budget <= 0 or not next(state.owners) then state.buildValid = false return end
        local child = select(index, ...)
        if Safety.Public(child) then
            if record and state.buildValid and record.children ~= emptyChildren then record.children[index] = child end
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
        record = { children = emptyChildren }
        state.records[index] = record
    elseif record.frame ~= frame or not kind then
        wipe(record)
        record.children = emptyChildren
    end
    record.frame, record.kind, record.leaf = frame, kind, false
    state.length = index
    return record
end

local paneHooks = setmetatable({}, { __mode = "k" })
local function PaneShown(pane)
    local state = paneHooks[pane]
    if not state or not state.panes then return end
    local status = state.panes[pane]
    if status == "hidden" then
        -- A child's OnShow can precede the parent's hook. AppendPane uses
        -- actual visibility; no root scan or unrelated sibling is required.
        Scan(state, pane)
    elseif status == "active" and not state.rootHidden and Safety.Read(pane, "GetParent") == state.root then
        Schedule(state)
    end
end

local function HiddenPane(state, frame)
    if state.panes[frame] == "active" or Safety.Read(frame, "HasScript", "OnShow") ~= true then return end
    local hidden = Safety.Read(frame, "IsShown") == false
    state.panes[frame] = hidden and "hidden" or "active"
    if not paneHooks[frame] then frame:HookScript("OnShow", PaneShown) end
    paneHooks[frame] = state
    return hidden
end

walk = function(state, frame, depth)
    if state.budget <= 0 or not next(state.owners) then state.buildValid = false return end
    if depth > 8 then return end
    local kind = Safe(frame)
    if kind then
        state.budget = state.budget - 1
        if depth == 1 and state.panes and state.panes[frame] and HiddenPane(state, frame) then return end
    end
    local record = Record(state, frame, kind)
    if record then record.terminal = depth == 8 end
    if not kind then return end
    -- Observe/Track can call native hooks. Keep the provider's own guards and
    -- read permissions fresh after those calls, rather than caching a lease.
    local leaf, target = TrackChecked(frame, state, kind)
    if record then
        record.leaf = leaf
        if target then
            state.targets = state.targets or {}
            state.targets[#state.targets + 1] = frame
        end
    end
    if not next(state.owners) then state.buildValid = false return end
    if Safety.IsForbidden(frame) then state.buildValid = false return end
    if record and not ShapeFields(record, true) then state.buildValid = false end
    if leaf then
        if record then
            record.children, record.count = emptyChildren, 0
            record.bodies, record.bodyKinds, record.bodyMethods, record.watched = nil, nil, nil, nil
        end
        return
    end
    -- Most frames have none of the named body keys. They need neither a
    -- second read nor four empty tables; Current still detects a late body.
    if NoBodies(frame) then
        if record then record.bodies, record.bodyKinds, record.bodyMethods, record.watched = nil, nil, nil, nil end
    else
        if record and not record.bodies then
            record.bodies, record.bodyKinds, record.bodyMethods, record.watched = {}, {}, {}, {}
        end
        for index = 1, #bodyKeys do
            local body = Safety.Field(frame, bodyKeys[index])
            if record then record.watched[index] = false end
            if Safety.Public(body) and type(body) == "table" and body ~= frame then
                if not state.content then state.content = body end
                if Safe(body) then Observe(state, body)
                elseif state.observed[body] ~= nil then state.observed[body] = true end
                local watched = Content.Watch(body, state.owner, nil, state.root)
                if record then record.watched[index] = watched == true end
            end
        end
        if Safety.IsForbidden(frame) then state.buildValid = false return end
        if record and not Bodies(record, true) then state.buildValid = false end
    end
    if Safety.IsForbidden(frame) then state.buildValid = false return end
    if depth < 8 then
        children(state, record, depth + 1, Safety.Call(frame, "GetChildren"))
    elseif record then
        record.children, record.count = emptyChildren, 0
    end
end

local function RegisterRoot(root, owner, window)
    local state = Menus.states[root]
    if not state then
        state = { root = root, owners = {}, observed = {}, records = {} }
        state.scan = function()
            state.queued = false
            Scan(state)
        end
        Menus.states[root] = state
        state.rootHidden = Safety.Read(root, "IsVisible") ~= true
        root:HookScript("OnHide", Hidden)
    end
    state.owners[owner] = window and "window" or state.owners[owner] or true
    state.owner = owner
    Content.Watch(root, owner, state.owners[owner] == "window")
    if window then NS.WindowMotion.Watch(root, owner) end
    return state
end

function Menus.Track(root, owner, contentOnly, window)
    if owner == nil or not Safe(root) then return false end
    -- Authored tab bodies already identify the exact content container.
    -- Watch it once; its descendants need neither discovery nor registration.
    if contentOnly then return Content.Watch(root, owner) end
    local state = RegisterRoot(root, owner, window)
    Observe(state, root)
    if not state.scanning then
        state.reentryQueued = false
        CancelScan(state)
    end
    Scan(state)
    return true
end

local function StateFor(frame)
    for _ = 1, 16 do
        local states = Menus.observers[frame]
        if states then
            for state, relation in pairs(states) do
                if next(state.owners) and (relation ~= "descendant" or NS.AdapterKit.IsDescendantOf(frame, state.root)) then return state end
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
            if state.owners[owner] == "window" then NS.WindowMotion.Unwatch(target, owner) end
            state.owners[owner] = nil
            state.owner, state.cacheOwner = next(state.owners), nil
            if not next(state.owners) then
                ReleaseMotionTarget(state)
                for frame in pairs(state.observed) do Menus.observers[frame][state] = nil end
                wipe(state.observed)
                CancelScan(state)
                if state.scanning then state.dropRecords = true
                else
                    wipe(state.records)
                    state.targets, state.length = nil, 0
                end
                state.paneKeys, state.panes, state.pendingPanes = nil, nil, nil
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
            Content.Watch(state.root, owner, state.owners[owner] == "window")
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

local function TrackAdapterRoot(root, owner, contentOnly, candidate)
    local window = candidate and NS.WindowControlPolicy.IsAnimationWindow(root)
    return Menus.Track(root, owner, contentOnly, window)
end

local function PrepareAdapterWindow(root, owner)
    if owner == nil or not Safe(root) or not NS.WindowControlPolicy.IsAnimationWindow(root) then return end
    -- The catalog paints on first show. Observe the root early so the first
    -- opening uses the selected fade without traversing a closed window.
    RegisterRoot(root, owner, true)
end

NS.Registry.AddListener(Menus, Refresh)
NS.GenericWindows.SetMenuMotionProvider(TrackAdapterRoot, Menus.Release, PrepareAdapterWindow)
NS.Adapters.SetMenuMotionProvider(TrackAdapterRoot, Menus.Release)
NS.AdapterKit.SetMotionProvider(Menus.TrackTarget, Content.Watch)
NS.Checkmarks.SetSettingsMotionProvider(SettingsChanged, Menus.Release)
NS.PublicAPI.TrackMenu, NS.PublicAPI.ReleaseMenu = Menus.Track, Menus.Release

NS.SocialUISkin.SetMotionProvider(Menus.TrackTarget, ReleaseMotionTarget)
