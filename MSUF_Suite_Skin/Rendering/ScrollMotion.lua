local _, NS = ...

-- Configure Blizzard's finite scroll interpolator through its public methods.
-- No wheel handler, scroll method, native field or update script is replaced.
local ScrollMotion = { states = setmetatable({}, { __mode = "k" }),
    targets = setmetatable({}, { __mode = "k" }), owners = {} }
NS.ScrollMotion = ScrollMotion
local Safety = NS.Safety
local Partner

local function Safe(target)
    return Safety.Public(target) and not Safety.IsForbidden(target) and not Safety.GetProtection(target)
        and not Safety.IsCompositorManaged(target)
end

local function Supported(target)
    return Safe(target) and Safety.HasMethod(target, "SetInterpolateScroll")
        and Safety.HasMethod(target, "CanInterpolateScroll") and Safety.HasMethod(target, "HookScript")
        and Safety.HasMethod(target, "SetScrollPercentage") and Safety.HasMethod(target, "GetScrollInterpolator")
        and Safety.HasMethod(target, "Interpolate")
end

local function Flag(target)
    local value = Safety.Call(target, "CanInterpolateScroll")
    if not Safety.Public(value) then return false end
    return value == nil or type(value) == "boolean", value
end

local function Enabled()
    local db = NS.DB
    return db and db.enabled and db.theme.smoothScrolling ~= false and db.theme.reduceMotion ~= true
        and not NS.Motion.combat and not NS.IsCombatLocked()
end

local function Cancel(target, snap)
    if Safety.IsForbidden(target) then return end
    -- GetScrollInterpolator creates one when absent. Read the verified native
    -- storage slot instead so an idle/unused controller allocates nothing.
    local interpolator = Safety.Field(target, "interpolator")
    if not Safety.Public(interpolator) or type(interpolator) ~= "table" then return end
    local destination = Safety.Read(interpolator, "GetInterpolateTo")
    Safety.Invoke(interpolator, "Cancel")
    if snap and type(destination) == "number" and Safe(target) and not NS.Motion.combat
        and not NS.IsCombatLocked() then
        target:SetScrollPercentage(math.max(0, math.min(1, destination)), true)
    end
end

local function Write(state, value)
    state.writing = true
    Safety.Dispatch(state.target.SetInterpolateScroll, state.target, value)
    state.writing = false
    state.written = value
end

local function CancelPartner(target)
    local partner = Partner(target)
    local state = partner and ScrollMotion.states[partner]
    if state and state.captured then Cancel(partner, false) end
end

local function Interpolating(target)
    local state = ScrollMotion.states[target]
    if state and state.captured and next(state.leases) then CancelPartner(target) end
end

local function LayoutChanged(state)
    if state.captured then
        Cancel(state.target, false)
        CancelPartner(state.target)
    end
end

local function ScrollToOffset(target, _, immediate)
    if Safety.Public(immediate) and immediate then
        local state = ScrollMotion.states[target]
        if state then LayoutChanged(state) end
    end
end

local function ScrollToBoundary(target, immediate)
    ScrollToOffset(target, nil, immediate)
end

local function FlagChanged(target)
    local state = ScrollMotion.states[target]
    if state and not state.writing then
        state.captured, state.pending = false, false
        local partner = Partner(target)
        local paired = partner and ScrollMotion.states[partner]
        if paired then paired.captured, paired.pending = false, false end
    end
end

local function Capture(state)
    local valid, original = Flag(state.target)
    if valid then state.original, state.captured, state.pending = original, true, false end
    return valid
end

local function Update(state)
    local target = state.target
    if not state.captured or not next(state.leases) or not Safe(target) then return end
    local valid, current = Flag(target)
    if not valid then return end
    local desired = Enabled() == true and not state.dragging
    if not desired then Cancel(target, true) end
    if current ~= desired then Write(state, desired) end
    state.written = desired
end

local function Restore(state)
    if not state.captured then state.pending = false return end
    local target = state.target
    if not Safe(target) then
        Cancel(target, false)
        state.pending = true
        return
    end
    Cancel(target, true)
    local valid, current = Flag(target)
    if valid and current == state.written then Write(state, state.original) end
    state.pending, state.captured = false, false
end

local function Hidden(target)
    local state = ScrollMotion.states[target]
    if state and state.captured and next(state.leases) then
        Cancel(target, false)
        state.dragging = false
        local partner = Partner(target)
        local paired = partner and ScrollMotion.states[partner]
        if paired and paired.captured then
            Cancel(partner, false)
            paired.dragging = false
        end
    end
end

local function ThumbDown(state, button)
    if not Safety.Public(button) or button ~= "LeftButton" or not state.captured then return end
    state.dragging = true
    Cancel(state.target, false)
    Update(state)
    local partner = Partner(state.target)
    local paired = partner and ScrollMotion.states[partner]
    if paired and paired.captured then
        paired.dragging = true
        Cancel(paired.target, false)
        Update(paired)
    end
end

local function ThumbUp(state, button)
    if not Safety.Public(button) or button ~= "LeftButton" then return end
    state.dragging = false
    Update(state)
    local partner = Partner(state.target)
    local paired = partner and ScrollMotion.states[partner]
    if paired then paired.dragging = false Update(paired) end
end

local function BindThumb(state)
    if state.thumb then return end
    local thumb = Safety.Read(state.target, "GetThumb")
    if not Safe(thumb) or not Safety.HasMethod(thumb, "RegisterCallback") then return end
    state.thumb = thumb
    state.dragging = Safety.Read(state.target, "IsThumbMouseDown") == true
    thumb:RegisterCallback("OnMouseDown", ThumbDown, state)
    thumb:RegisterCallback("OnMouseUp", ThumbUp, state)
end

local function BindLayout(state)
    local target = state.target
    if not state.layout and Safety.HasMethod(target, "GetView")
        and Safety.HasMethod(target, "RegisterCallback") and Safety.HasMethod(target, "UnregisterCallback") then
        target:RegisterCallback(ScrollBoxListMixin.Event.OnLayout, LayoutChanged, state)
        state.layout = true
    end
end

local function Shown(target)
    local state = ScrollMotion.states[target]
    if state then
        if state.pending and not next(state.leases) then Restore(state)
        else Update(state) end
        local partner = Partner(target)
        local paired = partner and ScrollMotion.states[partner]
        if paired then Update(paired) end
    end
end

local function AddController(lease, target)
    if not Supported(target) then return false end
    local valid = Flag(target)
    if not valid then return false end
    local state = ScrollMotion.states[target]
    if not state then
        state = { target = target, leases = {} }
        ScrollMotion.states[target] = state
        target:HookScript("OnHide", Safety.Isolated(Hidden))
        target:HookScript("OnShow", Safety.Isolated(Shown))
        hooksecurefunc(target, "SetInterpolateScroll", Safety.Isolated(FlagChanged))
        hooksecurefunc(target, "Interpolate", Safety.Isolated(Interpolating))
        if Safety.HasMethod(target, "ScrollToOffset") then
            hooksecurefunc(target, "ScrollToOffset", Safety.Isolated(ScrollToOffset))
        end
        if Safety.HasMethod(target, "ScrollToBegin") then
            hooksecurefunc(target, "ScrollToBegin", Safety.Isolated(ScrollToBoundary))
        end
        if Safety.HasMethod(target, "ScrollToEnd") then
            hooksecurefunc(target, "ScrollToEnd", Safety.Isolated(ScrollToBoundary))
        end
    end
    if not next(state.leases) and not state.captured then Capture(state) end
    if not state.leases[lease] then
        state.leases[lease] = true
        lease.controllers[#lease.controllers + 1] = state
    end
    BindThumb(state)
    BindLayout(state)
    Update(state)
    return true
end

Partner = function(target)
    local partner = Safety.Field(target, "registeredScrollBar")
    if not Safety.Public(partner) then return nil end
    if partner == nil then partner = Safety.Field(target, "registeredScrollBox") end
    if Safety.Public(partner) and type(partner) == "table" and partner ~= target then return partner end
    return nil
end

function ScrollMotion.Track(target, owner)
    if owner == nil or not Supported(target) or NS.Motion.combat or NS.IsCombatLocked() then return false end
    local partner = Partner(target)
    if not Flag(target) or partner and (not Supported(partner) or not Flag(partner)) then return false end
    local targets = ScrollMotion.targets[target]
    if not targets then targets = {} ScrollMotion.targets[target] = targets end
    local lease = targets[owner]
    if not lease then
        lease = { target = target, owner = owner, controllers = {} }
        targets[owner] = lease
    end
    local owned = ScrollMotion.owners[owner]
    if not owned then owned = {} ScrollMotion.owners[owner] = owned end
    owned[lease] = true
    local applied = AddController(lease, target)
    if partner then AddController(lease, partner) end
    return applied
end

function ScrollMotion.Release(target, owner)
    local targets = ScrollMotion.targets[target]
    local lease = targets and targets[owner]
    if not lease then return end
    for index = #lease.controllers, 1, -1 do
        local state = lease.controllers[index]
        state.leases[lease], lease.controllers[index] = nil, nil
        if not next(state.leases) then
            if state.layout then
                state.target:UnregisterCallback(ScrollBoxListMixin.Event.OnLayout, state)
                state.layout = false
            end
            if state.thumb then
                state.thumb:UnregisterCallback("OnMouseDown", state)
                state.thumb:UnregisterCallback("OnMouseUp", state)
                state.thumb, state.dragging = nil, false
            end
            Restore(state)
        end
    end
    local owned = ScrollMotion.owners[owner]
    if owned then
        owned[lease] = nil
        if not next(owned) then ScrollMotion.owners[owner] = nil end
    end
end

function ScrollMotion.ReleaseOwner(owner)
    local owned = ScrollMotion.owners[owner]
    if not owned then return end
    for lease in pairs(owned) do ScrollMotion.Release(lease.target, owner) end
end

local function Refresh(_, domain, key)
    local acquire = domain == "profile" or domain == "motion"
        and (key == "smoothScrolling" or key == "reduceMotion")
    for _, state in pairs(ScrollMotion.states) do
        if acquire and not state.captured and next(state.leases) and Safe(state.target) then Capture(state) end
        if domain == "PLAYER_REGEN_DISABLED" and state.captured then Cancel(state.target, false) end
        if state.pending and not next(state.leases) then Restore(state)
        else Update(state) end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", Refresh)
NS.Registry.AddListener(ScrollMotion, Refresh)
NS.GenericWindows.SetScrollMotionProvider(ScrollMotion.Track, ScrollMotion.ReleaseOwner)
NS.ScrollBarSkin.SetScrollMotionProvider(ScrollMotion.Track, ScrollMotion.Release)
