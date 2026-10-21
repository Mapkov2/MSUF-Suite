local _, NS = ...

-- Observe the native tree after layout. Only finite render transforms move;
-- Blizzard keeps the provider, row anchors, scrolling and activation logic.
local AddonListMotion = { states = {}, scrollStates = {}, records = setmetatable({}, { __mode = "k" }) }
NS.AddonListMotion = AddonListMotion
local Safety, Motion, Rows = NS.Safety, NS.Motion, NS.CollapseRows
local abs = math.abs
local Noop = function() end
local Ghost = { Capture = Noop, Released = Noop, Layout = Noop, Stop = Noop, Release = Noop, AfterLayout = Noop, Hidden = Noop, Initialized = Noop }
function AddonListMotion.SetGhostProvider(provider) Ghost = provider end

local function Stop(record)
    if record.group then record.group:Stop() end
    if record.arrowGroup then record.arrowGroup:Stop() end
end

local function StopState(state)
    Ghost.Stop(state)
    state.ghostGeneration = (state.ghostGeneration or 0) + 1
    for _, record in pairs(state.records) do Stop(record) end
    wipe(state.previous)
    wipe(state.collapsed)
    wipe(state.parents)
    state.provider, state.hadSnapshot = nil, false
end

local function RowHidden(row)
    local record = AddonListMotion.records[row]
    if record then Ghost.Hidden(record) Stop(record) end
end

local OnLayout

local function RootHidden(root)
    local state = AddonListMotion.states[root] or AddonListMotion.scrollStates[root]
    if state then StopState(state) end
end

local function RootShown(root)
    local state = AddonListMotion.states[root] or AddonListMotion.scrollStates[root]
    if state and state.active then OnLayout(state) end
end

local function CollectionScrolled(root)
    local state = AddonListMotion.scrollStates[root]
    if state and state.active then StopState(state) OnLayout(state) end
end

local function SafeRow(row)
    return Safety.CanCreateRegions(row) and not Safety.GetProtection(row)
        and Safety.HasMethod(row, "CreateAnimationGroup")
end

local function CreateGroup(record)
    if record.group then return end
    local group = record.row:CreateAnimationGroup()
    local translation = group:CreateAnimation("Translation")
    translation:SetDuration(0.16)
    translation:SetSmoothing("IN_OUT")
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetDuration(0.16)
    alpha:SetSmoothing("IN_OUT")
    record.group, record.translation, record.alpha = group, translation, alpha
end

local function Animate(record, offset, reveal)
    if not SafeRow(record.row) then Stop(record) return end
    local alpha = Safety.Read(record.row, "GetAlpha")
    if type(alpha) ~= "number" then Stop(record) return end
    CreateGroup(record)
    local carry = 0
    if Safety.Read(record.group, "IsPlaying") then
        local progress = Safety.Read(record.translation, "GetSmoothProgress")
        if type(progress) == "number" then carry = (record.offset or 0) * progress end
    end
    record.group:Stop()
    record.offset = offset + carry
    record.translation:SetOffset(0, record.offset)
    record.alphaFrom, record.alphaTo = alpha, reveal and 0 or alpha
    record.alpha:SetFromAlpha(alpha)
    record.alpha:SetToAlpha(reveal and 0 or alpha)
    -- Reverse playback starts at the old render position and settles at the
    -- native layout, with no SetPoint/SetAlpha or final-alpha ownership.
    record.group:Play(true)
end

local function AnimateArrow(record, collapsed)
    local arrow = Rows.Arrow(record.row)
    if not arrow or not SafeRow(arrow) then return end
    if not record.arrowGroup then
        record.arrowGroup = arrow:CreateAnimationGroup()
        record.rotation = record.arrowGroup:CreateAnimation("Rotation")
        record.rotation:SetDuration(0.16)
        record.rotation:SetSmoothing("IN_OUT")
    end
    local degrees = collapsed and -90 or 90
    if Safety.Read(record.arrowGroup, "IsPlaying") then
        local progress = Safety.Read(record.rotation, "GetSmoothProgress")
        if type(progress) == "number" then degrees = degrees + (record.degrees or 0) * progress end
    end
    record.arrowGroup:Stop()
    record.degrees = degrees
    record.rotation:SetDegrees(degrees)
    record.arrowGroup:Play(true)
end

local walking
local function Collect(row)
    local state = walking
    local record = state.records[row]
    if state.count >= 128 or not SafeRow(row) then
        if record then Stop(record) end
        return
    end
    local node = Safety.Read(row, "GetElementData")
    local top = Safety.Read(row, "GetTop")
    if not state.collection and type(node) ~= "table" or type(top) ~= "number" then
        if record then Stop(record) end
        return
    end
    if not record then
        record = { row = row, state = state }
        state.records[row], AddonListMotion.records[row] = record, record
        if Safety.HasMethod(row, "HookScript") then row:HookScript("OnHide", RowHidden) end
    end
    local collapsed, parent
    if state.collection then node, collapsed, parent = state.resolve(state, row)
    elseif state.generic then node, collapsed, parent = Rows.Resolve(state, node, row) end
    if node == nil then Stop(record) return end
    if record.node ~= node then Stop(record) end
    record.node, record.top, record.parent = node, top, parent
    if state.seenKeys[node] then state.ambiguous = true end
    state.seenKeys[node], state.newParents[node], state.currentTops[node] = true, parent, top
    if state.generic then state.currentCollapsed[node] = collapsed end
    if state.model == "tree" then Rows.Ancestors(state, parent) end
    if state.generic then record.collapsed = collapsed else
    local data = Safety.Read(node, "GetData")
    local category = Safety.Field(data, "category")
    record.collapsed = nil
    if Safety.Public(category) and category ~= nil then
        local collapsed = Safety.Call(node, "IsCollapsed")
        if Safety.Public(collapsed) then record.collapsed = collapsed == true end
    end
    end
    state.count = state.count + 1
    state.rows[state.count] = record
    Ghost.Capture(state, record)
end

local function Snapshot(state)
    wipe(state.previous)
    wipe(state.collapsed)
    wipe(state.parents)
    for node, parent in pairs(state.newParents) do state.parents[node] = parent end
    for node, collapsed in pairs(state.currentCollapsed) do state.collapsed[node] = collapsed end
    for index = 1, state.count do
        local record = state.rows[index]
        state.previous[record.node] = record.top
        state.collapsed[record.node] = record.collapsed
        state.parents[record.node] = record.parent
    end
end

local function Changes(state, eligible)
    if not eligible or state.ambiguous then return end
    local changed, top
    for index = 1, state.count do
        local record = state.rows[index]
        local old = state.collapsed[record.node]
        if old ~= nil and record.collapsed ~= nil and old ~= record.collapsed then
            changed, top = true, record.top
            state.changes[record.node] = record.collapsed
            AnimateArrow(record, record.collapsed)
        end
    end
    if state.model == "tree" then
        for node, old in pairs(state.collapsed) do
            local collapsed = state.currentCollapsed[node]
            if collapsed == nil then
                local value = Safety.Call(node, "IsCollapsed")
                if Safety.Public(value) then collapsed = value == true end
            end
            if collapsed ~= nil and old ~= collapsed then
                state.changes[node], changed = collapsed, true
                top = top or Safety.Read(state.scrollBox, "GetTop")
            end
        end
    end
    return changed, top
end

local function RevealTop(state, record, fallback)
    local parent = record.parent
    for _ = 1, 16 do
        if not parent then break end
        if state.changes[parent] == false then return state.currentTops[parent] or fallback end
        parent = state.newParents[parent]
    end
    return fallback
end

local function AnimateRow(state, record, changed, headerTop, stable)
    local parent = state.model == "encounter" and state.records[Safety.Read(record.row, "GetParent")]
    if parent and parent.group and Safety.Read(parent.group, "IsPlaying") then Stop(record) return end
    local oldTop = state.previous[record.node]
    if changed then
        local delta = oldTop and oldTop - record.top or RevealTop(state, record, headerTop) - record.top
        if abs(delta) > 0.25 then Animate(record, delta, oldTop == nil) end
    elseif not stable then Stop(record) end
end

OnLayout = function(state)
    if not state.active or not Motion.Enabled() or Safety.Read(state.root, "IsVisible") ~= true then
        StopState(state)
        return
    end
    local scrollBox = state.scrollBox
    if not state.collection and Safety.HasMethod(scrollBox, "GetView") and Safety.Read(scrollBox, "GetView") == nil then
        StopState(state)
        return
    end
    local provider = state.collection and state or Safety.Read(scrollBox, "GetDataProvider")
    local offset = Safety.Read(scrollBox, "GetDerivedScrollOffset")
    if state.collection then offset = Safety.Read(scrollBox, "GetVerticalScroll") or 0 end
    local width, height = Safety.Read(scrollBox, "GetWidth"), Safety.Read(scrollBox, "GetHeight")
    local scale = Safety.Read(scrollBox, "GetEffectiveScale")
    local stable = provider ~= nil and provider == state.provider and offset == state.offset
        and width == state.width and height == state.height and scale == state.scale
        and type(offset) == "number" and type(width) == "number" and type(height) == "number"
        and type(scale) == "number"
    stable = Ghost.Layout(state, provider, offset, width, height, scale) or stable
    state.provider, state.offset = provider, offset
    state.width, state.height, state.scale, state.count = width, height, scale, 0
    wipe(state.headerStack)
    wipe(state.changes)
    wipe(state.currentCollapsed)
    wipe(state.newParents)
    wipe(state.currentTops)
    wipe(state.seenKeys)
    state.ambiguous = false
    local previousWalk = walking
    walking = state
    if state.collection then Safety.Dispatch(state.enumerate, state, Collect)
    else Safety.Dispatch(scrollBox.ForEachFrame, scrollBox, Collect) end
    walking = previousWalk
    local context = state.contextReader and state.contextReader(state) or Rows.Context(state)
    local sameContext = state.context == context
    local sameGeometry = width == state.lastWidth and height == state.lastHeight and scale == state.lastScale
        and type(width) == "number" and type(height) == "number" and type(scale) == "number" and type(offset) == "number"
    local eligible = sameContext and (stable or state.generic and state.model ~= "tree" and sameGeometry and state.hadSnapshot)
    local changed, headerTop = Changes(state, eligible)
    state.context = context
    if changed and type(headerTop) ~= "number" then changed = nil wipe(state.changes) end
    Ghost.AfterLayout(state, changed)
    for index = 1, state.count do AnimateRow(state, state.rows[index], changed, headerTop, stable) end
    Snapshot(state)
    state.lastWidth, state.lastHeight, state.lastScale, state.hadSnapshot = width, height, scale, true
    return changed == true
end

local function Released(state, row, node)
    local record = state.records[row]
    if record then
        Ghost.Released(state, record, node)
        Stop(record)
        record.node = nil
    end
end

local function Register(state)
    if state.registered then return end
    local scrollBox = state.scrollBox
    if not state.collection then
        if not state.driven then scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnLayout, OnLayout, state) end
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnReleasedFrame, Released, state)
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, Ghost.Initialized, state)
    end
    state.registered = true
end

local function CreateState(root, scrollBox)
    local state = { root = root, scrollBox = scrollBox, records = {}, rows = {}, previous = {}, collapsed = {},
        count = 0, owners = {}, parents = {}, headerStack = {}, changes = {}, currentCollapsed = {}, newParents = {},
        currentTops = {}, seenKeys = {} }
    AddonListMotion.states[root], AddonListMotion.scrollStates[scrollBox] = state, state
    root:HookScript("OnHide", RootHidden)
    root:HookScript("OnShow", RootShown)
    return state
end

function AddonListMotion.Attach(root, owner)
    local scrollBox = Safety.Field(root, "ScrollBox")
    if not Safety.CanDecorate(root) or not Safety.HasMethod(scrollBox, "RegisterCallback")
        or not Safety.HasMethod(scrollBox, "ForEachFrame") then return false end
    local state = AddonListMotion.scrollStates[scrollBox] or CreateState(root, scrollBox)
    if state.driven then
        state.driven, state.generic = false, false
        if state.registered then scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnLayout, OnLayout, state) end
    end
    state.owners[owner], state.active = true, true
    Register(state)
    OnLayout(state)
    return true
end

function AddonListMotion.Track(scrollBox, owner, provider)
    if Safety.HasMethod(scrollBox, "GetView") and Safety.Read(scrollBox, "GetView") == nil then return false end
    local state = AddonListMotion.scrollStates[scrollBox]
    if not state then
        local model, contextRoot = Rows.Model(scrollBox, provider)
        if not model or not Safety.CanCreateRegions(scrollBox) or Safety.GetProtection(scrollBox)
            or not Safety.HasMethod(scrollBox, "ForEachFrame") then return false end
        state = CreateState(scrollBox, scrollBox)
        state.model, state.contextRoot, state.generic, state.driven = model, contextRoot, true, true
        state.owners[owner], state.active = true, true
        Register(state)
        OnLayout(state)
    end
    state.owners[owner], state.active = true, true
    Register(state)
    if not state.hadSnapshot then OnLayout(state) end
    return true
end

-- One dispatcher evaluates collapse before deciding whether results may fade.
function AddonListMotion.LayoutFor(scrollBox)
    local state = AddonListMotion.scrollStates[scrollBox]
    if state and state.driven then return OnLayout(state) end
    return false
end

function AddonListMotion.TrackCollection(root, owner, model, enumerate, resolve, contextReader, scope, contextRoot)
    if not Safety.CanCreateRegions(root) or Safety.GetProtection(root) then return false end
    local state = AddonListMotion.scrollStates[root] or CreateState(root, root)
    state.collection, state.generic, state.model = true, true, model
    state.enumerate, state.resolve, state.contextReader, state.scope = enumerate, resolve, contextReader, scope
    state.contextRoot = contextRoot
    if not state.scrollHooked and Safety.Read(root, "HasScript", "OnVerticalScroll") == true then
        root:HookScript("OnVerticalScroll", CollectionScrolled)
        state.scrollHooked = true
    end
    state.owners[owner], state.active = true, true
    Register(state)
    if not state.hadSnapshot then OnLayout(state) end
    return true
end

function AddonListMotion.RebuildCollection(root)
    local state = AddonListMotion.scrollStates[root]
    if not state or not state.active then return end
    state.ghostGeneration = (state.ghostGeneration or 0) + 1
    for index = 1, state.count do
        local record = state.rows[index]
        Ghost.Released(state, record, record.node)
    end
    return OnLayout(state)
end

function AddonListMotion.DisableOwner(owner)
    for _, state in pairs(AddonListMotion.states) do
        state.owners[owner] = nil
        if not next(state.owners) then
            state.active = false
            StopState(state)
            Ghost.Release(state)
            if state.registered then
                if not state.collection then
                    if not state.driven then state.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnLayout, state) end
                    state.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnReleasedFrame, state)
                    state.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, state)
                end
                state.registered = false
            end
        end
    end
end

local function StopAll()
    for _, state in pairs(AddonListMotion.states) do StopState(state) end
end
local function SettingsChanged()
    StopAll()
    for _, state in pairs(AddonListMotion.states) do
        if state.active then OnLayout(state) end
    end
end
local function CombatChanged(_, event)
    if event == "PLAYER_REGEN_DISABLED" then StopAll()
    else SettingsChanged() end
end
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", CombatChanged)
NS.Registry.AddListener(AddonListMotion, SettingsChanged)
