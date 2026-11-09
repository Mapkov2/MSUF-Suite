local _, NS = ...

-- Provider replacement followed by OnLayout is a completed native result set.
-- Start before that layout is drawn. A delayed fade would blank results that
-- were already visible; rapid provider changes retarget the current opacity.
local Results = { states = setmetatable({}, { __mode = "k" }) }
NS.ResultMotion = Results
local Safety, Content, Motion = NS.Safety, NS.ContentMotion, NS.Motion
local visible = {}

local function ClearOpening(state)
    local pending = state.opening
    if not pending then return end
    pending[state.target] = nil
    state.opening = nil
end

local function Cancel(state)
    ClearOpening(state)
    Content.StopOwner(state, state.target)
end

local function OpeningFinished(target, covered)
    local state = Results.states[target]
    state.opening = nil
    if not covered then Content.Play(target, state, state.provider) end
end

local function Provider(target)
    -- ScrollBoxListMixin:GetDataProvider dereferences GetView unconditionally.
    -- Catalog/shop frames can be adopted before their native SetView ran.
    if Safety.HasMethod(target, "GetView") and Safety.Read(target, "GetView") == nil then return nil end
    return Safety.Read(target, "GetDataProvider")
end

local function Layout(state)
    local provider = Provider(state.target)
    if provider ~= state.provider then NS.AddonListMotion.Track(state.target, state, provider) end
    local collapsed = NS.AddonListMotion.LayoutFor(state.target)
    if collapsed then Cancel(state) end
    if provider == state.provider then return end
    local previous = state.provider
    state.provider = provider
    if not collapsed and previous ~= nil and provider ~= nil and Motion.Enabled()
        and Safety.Read(state.target, "IsVisible") == true then
        ClearOpening(state)
        state.opening = Content.DeferToOpening(state.target, OpeningFinished)
        if not state.opening then Content.Play(state.target, state, provider) end
    else Cancel(state) end
end

local function Hidden(target)
    visible[target] = nil
    local state = Results.states[target]
    if state then Cancel(state) end
end

local function Shown(target)
    local state = Results.states[target]
    if state and state.registered then visible[target] = state end
end

function Results.Track(target, owner)
    if not Safety.CanCreateRegions(target) or Safety.GetProtection(target)
        or not Safety.HasMethod(target, "RegisterCallback") or not Safety.HasMethod(target, "GetDataProvider")
        or not Safety.HasMethod(target, "CreateAnimationGroup") then return end
    local state = Results.states[target]
    if not state then
        state = { target = target, owners = {} }
        Results.states[target] = state
        target:HookScript("OnHide", Hidden)
        target:HookScript("OnShow", Shown)
    end
    state.owners[owner] = true
    if not state.registered then
        state.provider = Provider(target)
        NS.AddonListMotion.Track(target, state, state.provider)
        target:RegisterCallback(ScrollBoxListMixin.Event.OnLayout, Layout, state)
        state.registered = true
    end
    local shown = Safety.Read(target, "IsVisible")
    if Safety.Public(shown) and shown == true then Shown(target) end
end

function Results.ReleaseOwner(owner)
    for _, state in pairs(Results.states) do
        state.owners[owner] = nil
        if not next(state.owners) then
            visible[state.target] = nil
            Cancel(state)
            NS.AddonListMotion.DisableOwner(state)
            if state.registered then
                state.target:UnregisterCallback(ScrollBoxListMixin.Event.OnLayout, state)
                state.registered = false
            end
        end
    end
end

local function StopAll(_, event)
    for _, state in pairs(visible) do
        if event ~= "PLAYER_REGEN_DISABLED" or not Safety.CanCreateRegions(state.target) then Cancel(state) end
    end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", StopAll)
NS.Registry.AddListener(Results, StopAll)
NS.GenericWindows.SetContentMotionProvider(Results.Track, Results.ReleaseOwner)
