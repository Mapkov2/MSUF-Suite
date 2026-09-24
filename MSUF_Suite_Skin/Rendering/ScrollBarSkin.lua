local _, NS = ...

-- Reversible cosmetics for the current Retail MinimalScrollBar and
-- WowTrimScrollBar contracts. Blizzard keeps absolute ownership of scrolling,
-- state atlases, geometry and visibility; this module only adds a track
-- surface, suppresses the verified native track art, and tints verified
-- thumb/stepper regions outside combat.
local ScrollBarSkin = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
    pendingTargets = setmetatable({}, { __mode = "k" }),
    pendingOwners = {},
    regionOwners = setmetatable({}, { __mode = "k" }),
}
NS.ScrollBarSkin = ScrollBarSkin

local listenerOwner = {}
local listenerRegistered = false

local TRACK_SURFACE_SPEC = {
    role = "input",
    shape = "continuous",
    radius = 4,
    border = 0,
    inset = 0,
}

local minimalThumbFields = {
    upBeginTexture = "minimal-scrollbar-small-thumb-top",
    upMiddleTexture = "minimal-scrollbar-small-thumb-middle",
    upEndTexture = "minimal-scrollbar-small-thumb-bottom",
    overBeginTexture = "minimal-scrollbar-small-thumb-top-over",
    overMiddleTexture = "minimal-scrollbar-small-thumb-middle-over",
    overEndTexture = "minimal-scrollbar-small-thumb-bottom-over",
    downBeginTexture = "minimal-scrollbar-small-thumb-top-down",
    downMiddleTexture = "minimal-scrollbar-small-thumb-middle-down",
    downEndTexture = "minimal-scrollbar-small-thumb-bottom-down",
}

local minimalBackFields = {
    normalTexture = "minimal-scrollbar-arrow-top",
    overTexture = "minimal-scrollbar-arrow-top-over",
    downTexture = "minimal-scrollbar-arrow-top-down",
    disabledTexture = "minimal-scrollbar-arrow-top",
}

local minimalForwardFields = {
    normalTexture = "minimal-scrollbar-arrow-bottom",
    overTexture = "minimal-scrollbar-arrow-bottom-over",
    downTexture = "minimal-scrollbar-arrow-bottom-down",
    disabledTexture = "minimal-scrollbar-bottom-top",
}

local trimContracts = {
    vertical = {
        horizontal = false,
        thumb = {
            upBeginTexture = "UI-ScrollBar-Knob-EndCap-Top",
            upMiddleTexture = "UI-ScrollBar-Knob-Center",
            upEndTexture = "UI-ScrollBar-Knob-EndCap-Bottom",
            overBeginTexture = "UI-ScrollBar-Knob-MouseOver-EndCap-Top",
            overMiddleTexture = "UI-ScrollBar-Knob-MouseOver-Center",
            overEndTexture = "UI-ScrollBar-Knob-MouseOver-EndCap-Bottom",
            disabledBeginTexture = "UI-ScrollBar-Knob-EndCap-Top-Disabled",
            disabledMiddleTexture = "UI-ScrollBar-Knob-Center-Disabled",
            disabledEndTexture = "UI-ScrollBar-Knob-EndCap-Bottom-Disabled",
        },
        back = {
            upTexture = "UI-ScrollBar-ScrollUpButton-Up",
            downTexture = "UI-ScrollBar-ScrollUpButton-Down",
            disabledTexture = "UI-ScrollBar-ScrollUpButton-Disabled",
        },
        forward = {
            upTexture = "UI-ScrollBar-ScrollDownButton-Up",
            downTexture = "UI-ScrollBar-ScrollDownButton-Down",
            disabledTexture = "UI-ScrollBar-ScrollDownButton-Disabled",
        },
        backOverlay = "UI-ScrollBar-ScrollUpButton-Highlight",
        forwardOverlay = "UI-ScrollBar-ScrollDownButton-Highlight",
    },
    horizontal = {
        horizontal = true,
        thumb = {
            upBeginTexture = "UI-ScrollBar-Knob-EndCap-Left",
            upMiddleTexture = "UI-ScrollBar-Knob-Center-Horizontal",
            upEndTexture = "UI-ScrollBar-Knob-EndCap-Right",
            overBeginTexture = "UI-ScrollBar-Knob-MouseOver-EndCap-Left",
            overMiddleTexture = "UI-ScrollBar-Knob-MouseOver-Center-Horizontal",
            overEndTexture = "UI-ScrollBar-Knob-MouseOver-EndCap-Right",
            disabledBeginTexture = "UI-ScrollBar-Knob-EndCap-Left-Disabled",
            disabledMiddleTexture = "UI-ScrollBar-Knob-Center-Disabled-Horizontal",
            disabledEndTexture = "UI-ScrollBar-Knob-EndCap-Right-Disabled",
        },
        back = {
            upTexture = "UI-ScrollBar-ScrollLeftButton-Up",
            downTexture = "UI-ScrollBar-ScrollLeftButton-Down",
            disabledTexture = "UI-ScrollBar-ScrollLeftButton-Disabled",
        },
        forward = {
            upTexture = "UI-ScrollBar-ScrollRightButton-Up",
            downTexture = "UI-ScrollBar-ScrollRightButton-Down",
            disabledTexture = "UI-ScrollBar-ScrollRightButton-Disabled",
        },
        backOverlay = "UI-ScrollBar-ScrollLeftButton-Highlight",
        forwardOverlay = "UI-ScrollBar-ScrollRightButton-Highlight",
    },
}

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Accessible(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value
end

local function ReadObjectType(object)
    local getter = SafeField(object, "GetObjectType")
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object)
    value = ok and Accessible(value) or nil
    return type(value) == "string" and value or nil
end

local function ReadVertexColor(region)
    local getter = SafeField(region, "GetVertexColor")
    if type(getter) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(getter, region)
    if not ok then return nil end
    r, g, b, a = Accessible(r), Accessible(g), Accessible(b), Accessible(a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return { r, g, b, type(a) == "number" and a or 1 }
end

local function IsTintable(region)
    return ReadVertexColor(region) ~= nil
        and type(SafeField(region, "SetVertexColor")) == "function"
end

local function IsFadeable(region)
    return type(SafeField(region, "GetAlpha")) == "function"
        and type(SafeField(region, "SetAlpha")) == "function"
end

local function FieldsEqual(object, expected)
    for key, value in pairs(expected) do
        if SafeField(object, key) ~= value then return false end
    end
    return true
end

local function GetterReturns(target, methodName, expected)
    local method = SafeField(target, methodName)
    if type(method) ~= "function" then return false end
    local ok, value = pcall(method, target)
    return ok and value == expected
end

local function OverlayMatches(region, expectedAtlas)
    if not IsTintable(region) then return false end
    local getter = SafeField(region, "GetAtlas")
    if type(getter) ~= "function" then return false end
    local ok, atlas = pcall(getter, region)
    atlas = ok and Accessible(atlas) or nil
    return atlas == expectedAtlas
end

local function CommonContract(target)
    -- The supported Retail templates are EventFrames. Reject Slider objects
    -- before looking at fields so an ordinary horizontal value slider can
    -- never opt in merely because an addon gave it similarly named children.
    local objectType = ReadObjectType(target)
    if not objectType or objectType == "Slider" then return nil end
    if type(SafeField(target, "SetScrollPercentage")) ~= "function"
        or type(SafeField(target, "GetScrollPercentage")) ~= "function" then
        return nil
    end

    local track = SafeField(target, "Track")
    local thumb = SafeField(track, "Thumb")
    local back = SafeField(target, "Back")
    local forward = SafeField(target, "Forward")
    if not track or not thumb or not back or not forward
        or not GetterReturns(target, "GetTrack", track)
        or not GetterReturns(target, "GetThumb", thumb)
        or not GetterReturns(target, "GetBackStepper", back)
        or not GetterReturns(target, "GetForwardStepper", forward)
        or type(SafeField(track, "CreateTexture")) ~= "function" then
        return nil
    end

    local trackRegions = {}
    local trackBegin = SafeField(track, "Begin")
    local trackMiddle = SafeField(track, "Middle")
    local trackEnd = SafeField(track, "End")
    if trackBegin or trackMiddle or trackEnd then
        if not IsFadeable(trackBegin) or not IsFadeable(trackMiddle)
            or not IsFadeable(trackEnd) then
            return nil
        end
        trackRegions = { trackBegin, trackMiddle, trackEnd }
    end
    local thumbRegions = {
        SafeField(thumb, "Begin"),
        SafeField(thumb, "Middle"),
        SafeField(thumb, "End"),
    }
    local backTexture = SafeField(back, "Texture")
    local forwardTexture = SafeField(forward, "Texture")
    for index = 1, 3 do
        if not IsTintable(thumbRegions[index]) then return nil end
    end
    if not IsTintable(backTexture) or not IsTintable(forwardTexture) then return nil end

    return {
        target = target,
        track = track,
        thumb = thumb,
        back = back,
        forward = forward,
        trackRegions = trackRegions,
        thumbRegions = thumbRegions,
        backTexture = backTexture,
        forwardTexture = forwardTexture,
    }
end

local function DetectContract(target)
    local contract = CommonContract(target)
    if not contract then return nil, "unsupported" end

    local horizontal = SafeField(target, "isHorizontal") == true
        or SafeField(contract.thumb, "isHorizontal") == true
    local background = SafeField(target, "Background")
    if not background and not horizontal and #contract.trackRegions == 3
        and FieldsEqual(contract.thumb, minimalThumbFields)
        and FieldsEqual(contract.back, minimalBackFields)
        and FieldsEqual(contract.forward, minimalForwardFields)
        and SafeField(contract.back, "Overlay") == nil
        and SafeField(contract.forward, "Overlay") == nil then
        contract.kind = "minimal"
        contract.tintSpecs = {
            { regions = contract.thumbRegions, role = "accentBright", alpha = 1 },
            { regions = { contract.backTexture, contract.forwardTexture }, role = "blizzardArrow", alpha = 1 },
        }
        return contract
    end

    if not background or #contract.trackRegions ~= 0 then return nil, "unsupported" end
    local definition = horizontal and trimContracts.horizontal or trimContracts.vertical
    local targetHorizontal = SafeField(target, "isHorizontal") == true
    local thumbHorizontal = SafeField(contract.thumb, "isHorizontal") == true
    if targetHorizontal ~= definition.horizontal
        or thumbHorizontal ~= definition.horizontal
        or not FieldsEqual(contract.thumb, definition.thumb)
        or not FieldsEqual(contract.back, definition.back)
        or not FieldsEqual(contract.forward, definition.forward) then
        return nil, "unsupported"
    end

    local backgroundRegions = {
        SafeField(background, "Begin"),
        SafeField(background, "Middle"),
        SafeField(background, "End"),
    }
    for index = 1, 3 do
        if not IsTintable(backgroundRegions[index]) then return nil, "unsupported" end
    end

    contract.kind = definition.horizontal and "trim-horizontal" or "trim-vertical"
    contract.background = background
    contract.backgroundRegions = backgroundRegions
    contract.tintSpecs = {
        { regions = contract.thumbRegions, role = "accentBright", alpha = 1 },
        { regions = { contract.backTexture, contract.forwardTexture }, role = "blizzardArrow", alpha = 1 },
        { regions = backgroundRegions, role = "borderSoft", alpha = 0.72 },
    }

    local backOverlay = SafeField(contract.back, "Overlay")
    local forwardOverlay = SafeField(contract.forward, "Overlay")
    if OverlayMatches(backOverlay, definition.backOverlay)
        and OverlayMatches(forwardOverlay, definition.forwardOverlay) then
        contract.backOverlay = backOverlay
        contract.forwardOverlay = forwardOverlay
        contract.tintSpecs[#contract.tintSpecs + 1] = {
            regions = { backOverlay, forwardOverlay }, role = "hover", alpha = 1,
        }
    end
    return contract
end

local function SameContract(left, right)
    if not left or not right or left.kind ~= right.kind
        or left.track ~= right.track or left.thumb ~= right.thumb
        or left.back ~= right.back or left.forward ~= right.forward
        or left.background ~= right.background then
        return false
    end
    for _, key in ipairs({ "trackRegions", "thumbRegions", "backgroundRegions" }) do
        local a, b = left[key] or {}, right[key] or {}
        if #a ~= #b then return false end
        for index = 1, #a do
            if a[index] ~= b[index] then return false end
        end
    end
    return left.backTexture == right.backTexture
        and left.forwardTexture == right.forwardTexture
        and left.backOverlay == right.backOverlay
        and left.forwardOverlay == right.forwardOverlay
end

local function CanDecorate(contract)
    if not NS.Safety or not NS.Safety.CanCreateRegions(contract.track, false) then
        return false
    end
    for _, target in ipairs({
        contract.target, contract.thumb, contract.back, contract.forward,
        contract.background,
    }) do
        if target and not NS.Safety.CanDecorate(target, false) then return false end
    end
    return true
end

local function SameColor(left, right)
    if not left or not right then return false end
    local epsilon = 0.0001
    for index = 1, 4 do
        if math.abs(left[index] - right[index]) > epsilon then return false end
    end
    return true
end

local function TintRegion(state, region, role, alphaScale)
    local held = ScrollBarSkin.regionOwners[region]
    if held and held ~= state then return false end
    local current = ReadVertexColor(region)
    if not current then return false end

    local tint = state.tints[region]
    if not tint then
        tint = { original = current }
        state.tints[region] = tint
    elseif tint.applied and not SameColor(current, tint.applied)
        and not SameColor(current, tint.original) then
        return false
    end

    local r, g, b, a = NS.Theme.GetColor(role)
    local desired = { r, g, b, tint.original[4] * (tonumber(a) or 1) * (alphaScale or 1) }
    local setter = SafeField(region, "SetVertexColor")
    local ok = type(setter) == "function"
        and pcall(setter, region, desired[1], desired[2], desired[3], desired[4])
    if not ok then return false end
    tint.applied = desired
    tint.role = role
    tint.alphaScale = alphaScale or 1
    ScrollBarSkin.regionOwners[region] = state
    return true
end

local function ApplyTints(state)
    for index = 1, #state.contract.tintSpecs do
        local spec = state.contract.tintSpecs[index]
        for regionIndex = 1, #spec.regions do
            if not TintRegion(state, spec.regions[regionIndex], spec.role, spec.alpha) then
                return false
            end
        end
    end
    return true
end

local function RestoreTints(state)
    for region, tint in pairs(state.tints) do
        local current = ReadVertexColor(region)
        local setter = SafeField(region, "SetVertexColor")
        if tint.applied and SameColor(current, tint.applied) and type(setter) == "function" then
            pcall(setter, region, unpack(tint.original))
        end
        if ScrollBarSkin.regionOwners[region] == state then
            ScrollBarSkin.regionOwners[region] = nil
        end
    end
    state.tints = setmetatable({}, { __mode = "k" })
end

local function FadeTrack(state)
    for index = 1, #state.contract.trackRegions do
        if not NS.Cosmetics.Fade(state.contract.trackRegions[index], state.cosmeticOwner) then
            return false
        end
    end
    return true
end

local function OwnerSet(owner)
    local set = ScrollBarSkin.owners[owner]
    if not set then
        set = WeakSet()
        ScrollBarSkin.owners[owner] = set
    end
    return set
end

local function BindOwner(target, state, owner)
    if state.owner and state.owner ~= owner then
        local oldSet = ScrollBarSkin.owners[state.owner]
        if oldSet then oldSet[target] = nil end
    end
    state.owner = owner
    OwnerSet(owner)[target] = true
end

local function TargetKey(target)
    return "scrollbarskin:" .. tostring(target)
end

local function RefreshKey(target)
    return "scrollbarskin-refresh:" .. tostring(target)
end

local function OwnerKey(owner)
    return "scrollbarskin-owner:" .. tostring(owner)
end

local function ClearPendingTarget(target, cancel)
    local owner = ScrollBarSkin.pendingTargets[target]
    if owner ~= nil then
        local set = ScrollBarSkin.pendingOwners[owner]
        if set then
            set[target] = nil
            if next(set) == nil then ScrollBarSkin.pendingOwners[owner] = nil end
        end
        ScrollBarSkin.pendingTargets[target] = nil
    end
    if cancel and NS.CombatGate then NS.CombatGate.Cancel(TargetKey(target)) end
end

local function RestoreState(target, state)
    if not state then return end
    NS.Cosmetics.RestoreOwner(state.cosmeticOwner)
    RestoreTints(state)
    if state.contract and NS.Registry.GetSurface(state.contract.track) == state.surface then
        NS.Surface.SetVisible(state.contract.track, false)
    end
    local owner = state.owner
    local owned = owner and ScrollBarSkin.owners[owner]
    if owned then
        owned[target] = nil
        if next(owned) == nil then ScrollBarSkin.owners[owner] = nil end
    end
    state.enabled = false
    state.owner = nil
end

local function RefreshNow(target, state)
    if not state or state.enabled == false then return false, "disabled" end
    local contract, reason = DetectContract(target)
    if not contract or not SameContract(state.contract, contract) then
        RestoreState(target, state)
        ScrollBarSkin.states[target] = nil
        return false, reason or "contract changed"
    end
    if not CanDecorate(contract) then return false, "protected" end
    if not FadeTrack(state) or not ApplyTints(state) then return false, "native ownership" end
    if NS.Registry.GetSurface(contract.track) ~= state.surface then
        return false, "surface ownership"
    end
    NS.Surface.SetVisible(contract.track, true)
    NS.Surface.Refresh(contract.track)
    return true
end

local function ApplyNow(target, owner)
    local contract, reason = DetectContract(target)
    if not contract then return nil, reason end
    if not CanDecorate(contract) then return nil, "protected" end

    local state = ScrollBarSkin.states[target]
    if state and state.enabled ~= false and state.owner ~= owner then
        return nil, "already owned"
    end
    if state and not SameContract(state.contract, contract) then
        RestoreState(target, state)
        ScrollBarSkin.states[target] = nil
        state = nil
    end

    if not state then
        if NS.Registry.GetSurface(contract.track) then return nil, "surface already owned" end
        state = {
            target = target,
            contract = contract,
            cosmeticOwner = {},
            tints = setmetatable({}, { __mode = "k" }),
            enabled = false,
        }
    elseif NS.Registry.GetSurface(contract.track) ~= state.surface then
        return nil, "surface ownership"
    end

    local wasEnabled = state.enabled ~= false
    state.contract = contract
    if not FadeTrack(state) or not ApplyTints(state) then
        if not wasEnabled then
            NS.Cosmetics.RestoreOwner(state.cosmeticOwner)
            RestoreTints(state)
        end
        return nil, "native ownership"
    end

    local surface, surfaceReason = NS.Surface.Attach(contract.track, TRACK_SURFACE_SPEC)
    if not surface then
        if not wasEnabled then
            NS.Cosmetics.RestoreOwner(state.cosmeticOwner)
            RestoreTints(state)
        end
        return nil, surfaceReason or "surface unavailable"
    end

    state.surface = surface
    state.enabled = true
    ScrollBarSkin.states[target] = state
    BindOwner(target, state, owner)
    NS.Surface.SetVisible(contract.track, true)
    return state
end

local function RefreshAll()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("scrollbarskin-refresh-all", RefreshAll)
        return false, "combat"
    end
    for target, state in pairs(ScrollBarSkin.states) do
        if state.enabled ~= false then RefreshNow(target, state) end
    end
    return true
end

local function EnsureListener()
    if listenerRegistered then return end
    NS.Registry.AddListener(listenerOwner, RefreshAll)
    listenerRegistered = true
end

function ScrollBarSkin.Apply(target, owner)
    if not target then return nil, "invalid target" end
    if owner == nil then return nil, "invalid owner" end
    local contract, reason = DetectContract(target)
    if not contract then return nil, reason end
    if not CanDecorate(contract) then return nil, "protected" end

    NS.CombatGate.Cancel(OwnerKey(owner))
    if NS.IsCombatLocked() then
        ClearPendingTarget(target, true)
        ScrollBarSkin.pendingTargets[target] = owner
        local pending = ScrollBarSkin.pendingOwners[owner]
        if not pending then
            pending = WeakSet()
            ScrollBarSkin.pendingOwners[owner] = pending
        end
        pending[target] = true
        NS.CombatGate.RunOrDefer(TargetKey(target), function()
            if ScrollBarSkin.pendingTargets[target] ~= owner then return end
            ClearPendingTarget(target, false)
            local state = ApplyNow(target, owner)
            if state then EnsureListener() end
        end)
        return nil, "combat"
    end

    ClearPendingTarget(target, true)
    local state, applyReason = ApplyNow(target, owner)
    if state then EnsureListener() end
    return state, applyReason
end

function ScrollBarSkin.Refresh(target)
    local state = target and ScrollBarSkin.states[target]
    if not state or state.enabled == false then return false, "disabled" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(RefreshKey(target), function()
            local current = ScrollBarSkin.states[target]
            if current and current.enabled ~= false then RefreshNow(target, current) end
        end)
        return false, "combat"
    end
    NS.CombatGate.Cancel(RefreshKey(target))
    return RefreshNow(target, state)
end

local function DisableNow(owner)
    local owned = ScrollBarSkin.owners[owner]
    if not owned then return false end
    for target in pairs(owned) do
        local state = ScrollBarSkin.states[target]
        if state and state.owner == owner then
            NS.CombatGate.Cancel(RefreshKey(target))
            RestoreState(target, state)
        end
    end
    ScrollBarSkin.owners[owner] = nil
    return true
end

function ScrollBarSkin.DisableOwner(owner)
    if owner == nil then return false, "invalid owner" end
    local pending = ScrollBarSkin.pendingOwners[owner]
    if pending then
        for target in pairs(pending) do
            ScrollBarSkin.pendingTargets[target] = nil
            NS.CombatGate.Cancel(TargetKey(target))
        end
        ScrollBarSkin.pendingOwners[owner] = nil
    end

    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(OwnerKey(owner), function() DisableNow(owner) end)
        return false, "combat"
    end
    NS.CombatGate.Cancel(OwnerKey(owner))
    return DisableNow(owner)
end

function ScrollBarSkin.GetState(target)
    return ScrollBarSkin.states[target]
end

function ScrollBarSkin.GetContract(target)
    local contract = DetectContract(target)
    return contract and contract.kind or nil
end

return ScrollBarSkin
