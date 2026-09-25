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

local Safety = NS.Safety

local listenerOwner = {}
local listenerRegistered = false

-- Tinted colors are compared with what the client reports back.
local COLOR_EPSILON = 0.0001

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

local Field = Safety.Field

local function IsTintable(region)
    return type(Field(region, "SetVertexColor")) == "function"
        and Safety.ReadColor(region, "GetVertexColor") ~= nil
end

local function IsFadeable(region)
    return type(Field(region, "GetAlpha")) == "function"
        and type(Field(region, "SetAlpha")) == "function"
end

local function FieldsEqual(object, expected)
    for key, value in pairs(expected) do
        if Field(object, key) ~= value then return false end
    end
    return true
end

local function GetterReturns(target, methodName, expected)
    return type(Field(target, methodName)) == "function"
        and Safety.Read(target, methodName) == expected
end

local function OverlayMatches(region, expectedAtlas)
    return IsTintable(region) and Safety.Read(region, "GetAtlas") == expectedAtlas
end

local function SetRegions(list, first, second, third)
    list[1], list[2], list[3] = first, second, third
end

local function ClearRegions(list)
    list[1], list[2], list[3] = nil, nil, nil
end

-- A contract names the verified Blizzard regions of one scroll bar. Its
-- region lists are always present, empty when a template has none.
local function NewContract()
    return { trackRegions = {}, thumbRegions = {}, backgroundRegions = {} }
end

-- Refreshes compare the live bar against the stored contract through this
-- reused scratch contract instead of a new one.
local scratchContract = NewContract()

local function CommonContract(target, contract)
    -- The supported Retail templates are EventFrames. Reject Slider objects
    -- before looking at fields so an ordinary horizontal value slider can
    -- never opt in merely because an addon gave it similarly named children.
    local objectType = Safety.Read(target, "GetObjectType")
    if type(objectType) ~= "string" or objectType == "Slider" then return nil end
    if type(Field(target, "SetScrollPercentage")) ~= "function"
        or type(Field(target, "GetScrollPercentage")) ~= "function" then
        return nil
    end

    local track = Field(target, "Track")
    local thumb = Field(track, "Thumb")
    local back = Field(target, "Back")
    local forward = Field(target, "Forward")
    if not track or not thumb or not back or not forward
        or not GetterReturns(target, "GetTrack", track)
        or not GetterReturns(target, "GetThumb", thumb)
        or not GetterReturns(target, "GetBackStepper", back)
        or not GetterReturns(target, "GetForwardStepper", forward)
        or type(Field(track, "CreateTexture")) ~= "function" then
        return nil
    end

    local trackBegin = Field(track, "Begin")
    local trackMiddle = Field(track, "Middle")
    local trackEnd = Field(track, "End")
    if trackBegin or trackMiddle or trackEnd then
        if not IsFadeable(trackBegin) or not IsFadeable(trackMiddle)
            or not IsFadeable(trackEnd) then
            return nil
        end
        SetRegions(contract.trackRegions, trackBegin, trackMiddle, trackEnd)
    else
        ClearRegions(contract.trackRegions)
    end
    local thumbRegions = contract.thumbRegions
    SetRegions(thumbRegions, Field(thumb, "Begin"), Field(thumb, "Middle"), Field(thumb, "End"))
    local backTexture = Field(back, "Texture")
    local forwardTexture = Field(forward, "Texture")
    for index = 1, 3 do
        if not IsTintable(thumbRegions[index]) then return nil end
    end
    if not IsTintable(backTexture) or not IsTintable(forwardTexture) then return nil end

    contract.target = target
    contract.track = track
    contract.thumb = thumb
    contract.back = back
    contract.forward = forward
    contract.backTexture = backTexture
    contract.forwardTexture = forwardTexture
    contract.kind = nil
    contract.background = nil
    contract.backOverlay = nil
    contract.forwardOverlay = nil
    ClearRegions(contract.backgroundRegions)
    return contract
end

local function IsMinimalContract(target, contract, horizontal)
    return not horizontal and #contract.trackRegions == 3
        and Field(target, "Background") == nil
        and FieldsEqual(contract.thumb, minimalThumbFields)
        and FieldsEqual(contract.back, minimalBackFields)
        and FieldsEqual(contract.forward, minimalForwardFields)
        and Field(contract.back, "Overlay") == nil
        and Field(contract.forward, "Overlay") == nil
end

-- Fills contract (a new one when omitted) from the live scroll bar.
local function DetectContract(target, contract)
    contract = CommonContract(target, contract or NewContract())
    if not contract then return nil, "unsupported" end

    local targetHorizontal = Field(target, "isHorizontal") == true
    local thumbHorizontal = Field(contract.thumb, "isHorizontal") == true
    local horizontal = targetHorizontal or thumbHorizontal
    if IsMinimalContract(target, contract, horizontal) then
        contract.kind = "minimal"
        return contract
    end

    local background = Field(target, "Background")
    if not background or #contract.trackRegions ~= 0 then return nil, "unsupported" end
    local definition = horizontal and trimContracts.horizontal or trimContracts.vertical
    if targetHorizontal ~= definition.horizontal
        or thumbHorizontal ~= definition.horizontal
        or not FieldsEqual(contract.thumb, definition.thumb)
        or not FieldsEqual(contract.back, definition.back)
        or not FieldsEqual(contract.forward, definition.forward) then
        return nil, "unsupported"
    end

    local backgroundRegions = contract.backgroundRegions
    SetRegions(backgroundRegions, Field(background, "Begin"), Field(background, "Middle"),
        Field(background, "End"))
    for index = 1, 3 do
        if not IsTintable(backgroundRegions[index]) then return nil, "unsupported" end
    end

    contract.kind = definition.horizontal and "trim-horizontal" or "trim-vertical"
    contract.background = background
    local backOverlay = Field(contract.back, "Overlay")
    local forwardOverlay = Field(contract.forward, "Overlay")
    if OverlayMatches(backOverlay, definition.backOverlay)
        and OverlayMatches(forwardOverlay, definition.forwardOverlay) then
        contract.backOverlay = backOverlay
        contract.forwardOverlay = forwardOverlay
    end
    return contract
end

local function SameRegions(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function SameContract(left, right)
    return left ~= nil and right ~= nil and left.kind == right.kind
        and left.track == right.track and left.thumb == right.thumb
        and left.back == right.back and left.forward == right.forward
        and left.background == right.background
        and SameRegions(left.trackRegions, right.trackRegions)
        and SameRegions(left.thumbRegions, right.thumbRegions)
        and SameRegions(left.backgroundRegions, right.backgroundRegions)
        and left.backTexture == right.backTexture
        and left.forwardTexture == right.forwardTexture
        and left.backOverlay == right.backOverlay
        and left.forwardOverlay == right.forwardOverlay
end

local function CanDecorate(contract)
    return Safety.CanCreateRegions(contract.track, false)
        and Safety.CanDecorate(contract.target, false)
        and Safety.CanDecorate(contract.thumb, false)
        and Safety.CanDecorate(contract.back, false)
        and Safety.CanDecorate(contract.forward, false)
        and (not contract.background or Safety.CanDecorate(contract.background, false))
end

local function SameColor(color, r, g, b, a)
    return math.abs(color[1] - r) <= COLOR_EPSILON
        and math.abs(color[2] - g) <= COLOR_EPSILON
        and math.abs(color[3] - b) <= COLOR_EPSILON
        and math.abs(color[4] - a) <= COLOR_EPSILON
end

local function TintRegion(state, region, role, alphaScale)
    local held = ScrollBarSkin.regionOwners[region]
    if held and held ~= state then return false end
    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    if not r then return false end

    local tint = state.tints[region]
    if not tint then
        tint = { original = { r, g, b, a }, applied = {} }
        state.tints[region] = tint
    elseif tint.applied[1] and not SameColor(tint.applied, r, g, b, a)
        and not SameColor(tint.original, r, g, b, a) then
        return false
    end

    local tokenR, tokenG, tokenB, tokenA = NS.Theme.GetColor(role)
    local applied = tint.applied
    applied[1], applied[2], applied[3] = tokenR, tokenG, tokenB
    applied[4] = tint.original[4] * (tonumber(tokenA) or 1) * (alphaScale or 1)
    region:SetVertexColor(applied[1], applied[2], applied[3], applied[4])
    tint.role = role
    tint.alphaScale = alphaScale or 1
    ScrollBarSkin.regionOwners[region] = state
    return true
end

local function TintRegions(state, regions, role, alphaScale)
    for index = 1, #regions do
        if not TintRegion(state, regions[index], role, alphaScale) then return false end
    end
    return true
end

-- Tints stop at the first region another owner or Blizzard has changed.
local function ApplyTints(state)
    local contract = state.contract
    if not TintRegions(state, contract.thumbRegions, "accentBright", 1)
        or not TintRegion(state, contract.backTexture, "blizzardArrow", 1)
        or not TintRegion(state, contract.forwardTexture, "blizzardArrow", 1)
        or not TintRegions(state, contract.backgroundRegions, "borderSoft", 0.72) then
        return false
    end
    if contract.backOverlay then
        return TintRegion(state, contract.backOverlay, "hover", 1)
            and TintRegion(state, contract.forwardOverlay, "hover", 1)
    end
    return true
end

local function RestoreTints(state)
    for region, tint in pairs(state.tints) do
        local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
        if r and tint.applied[1] and SameColor(tint.applied, r, g, b, a) then
            local original = tint.original
            region:SetVertexColor(original[1], original[2], original[3], original[4])
        end
        if ScrollBarSkin.regionOwners[region] == state then
            ScrollBarSkin.regionOwners[region] = nil
        end
        state.tints[region] = nil
    end
end

local function FadeTrack(state)
    local regions = state.contract.trackRegions
    for index = 1, #regions do
        if not NS.Cosmetics.Fade(regions[index], state.cosmeticOwner) then
            return false
        end
    end
    return true
end

local function BindOwner(target, state, owner)
    if state.owner and state.owner ~= owner then
        local oldSet = ScrollBarSkin.owners[state.owner]
        if oldSet then oldSet[target] = nil end
    end
    state.owner = owner
    local set = ScrollBarSkin.owners[owner]
    if not set then
        set = WeakSet()
        ScrollBarSkin.owners[owner] = set
    end
    set[target] = true
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

local function RestoreNative(state)
    NS.Cosmetics.RestoreOwner(state.cosmeticOwner)
    RestoreTints(state)
end

local function RestoreState(target, state)
    if not state then return end
    RestoreNative(state)
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
    local detected, reason = DetectContract(target, scratchContract)
    if not detected or not SameContract(state.contract, detected) then
        RestoreState(target, state)
        ScrollBarSkin.states[target] = nil
        return false, reason or "contract changed"
    end
    local contract = state.contract
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
    local detected, reason = DetectContract(target, scratchContract)
    if not detected then return nil, reason end
    if not CanDecorate(detected) then return nil, "protected" end

    local state = ScrollBarSkin.states[target]
    if state and state.enabled ~= false and state.owner ~= owner then
        return nil, "already owned"
    end
    if state and not SameContract(state.contract, detected) then
        RestoreState(target, state)
        ScrollBarSkin.states[target] = nil
        state = nil
    end

    if not state then
        if NS.Registry.GetSurface(detected.track) then return nil, "surface already owned" end
        state = {
            target = target,
            contract = DetectContract(target),
            cosmeticOwner = {},
            tints = setmetatable({}, { __mode = "k" }),
            enabled = false,
        }
    elseif NS.Registry.GetSurface(detected.track) ~= state.surface then
        return nil, "surface ownership"
    end

    local contract = state.contract
    local wasEnabled = state.enabled ~= false
    if not FadeTrack(state) or not ApplyTints(state) then
        if not wasEnabled then RestoreNative(state) end
        return nil, "native ownership"
    end

    local surface, surfaceReason = NS.Surface.Attach(contract.track, TRACK_SURFACE_SPEC)
    if not surface then
        if not wasEnabled then RestoreNative(state) end
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

local function ApplyAndListen(target, owner)
    local state, reason = ApplyNow(target, owner)
    if state then EnsureListener() end
    return state, reason
end

function ScrollBarSkin.Apply(target, owner)
    if not target then return nil, "invalid target" end
    if owner == nil then return nil, "invalid owner" end
    local contract, reason = DetectContract(target, scratchContract)
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
            ApplyAndListen(target, owner)
        end)
        return nil, "combat"
    end

    ClearPendingTarget(target, true)
    return ApplyAndListen(target, owner)
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
    local contract = DetectContract(target, scratchContract)
    return contract and contract.kind or nil
end

return ScrollBarSkin
