local _, NS = ...

-- Reversible skins for foreign Blizzard controls. Adapters choose a named
-- template API (ThreeSlice, UIPanel button, tab, or search box), may group
-- controls by owner, and can Refresh, Enable, Disable, or disable that owner.
-- All ownership is external; this module never adds fields or scripts to the
-- foreign frame.
local ControlSkin = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
}
NS.ControlSkin = ControlSkin

local Safety = NS.Safety

local nineSlicePieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local regionSets = {
    threeSlice = { "Left", "Center", "Right" },
    button = { "Left", "Middle", "Right", "Center" },
    minimalTab = { "Left", "Middle", "Right" },
    panelTab = {
        "Left", "Middle", "Right",
        "LeftActive", "MiddleActive", "RightActive",
        "LeftHighlight", "MiddleHighlight", "RightHighlight",
    },
    searchBox = {
        "Left", "Middle", "Right", "Background",
        "LeftTex", "MiddleTex", "RightTex",
    },
}

-- Spec keys that describe cosmetics or one-shot state, not the surface.
local nonSurfaceSpecKeys = { active = true, regions = true, nineSlices = true }
local cosmeticListKeys = { "regions", "nineSlices" }
local ownedStateKeys = { "highlight", "pushed", "disabled" }

local function IsProtected(target, allowImplicitProtected)
    return not Safety.CanCreateRegions(target, allowImplicitProtected)
end

local function AccessibleNumber(region, method)
    return tonumber(Safety.Read(region, method))
end

local function Wipe(target)
    for key in pairs(target) do target[key] = nil end
    return target
end

-- The surface part of a caller spec, copied into the control's own table.
local function CopySpec(spec, target)
    if spec == target then return target end
    target = Wipe(target or {})
    for key, value in pairs(spec) do
        if not nonSurfaceSpecKeys[key] then
            target[key] = value
        end
    end
    return target
end

-- Snapshot of the caller's extra region lists, reusing the previous lists.
local function CopyCosmeticSpec(spec, target)
    target = target or {}
    for index = 1, #cosmeticListKeys do
        local key = cosmeticListKeys[index]
        local source = spec and spec[key]
        if type(source) == "table" then
            local list = Wipe(target[key] or {})
            for position = 1, #source do
                list[position] = source[position]
            end
            target[key] = list
        else
            target[key] = nil
        end
    end
    return target
end

local function OwnerSet(owner)
    if owner == nil then
        return nil
    end
    local set = ControlSkin.owners[owner]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        ControlSkin.owners[owner] = set
    end
    return set
end

local function BindOwner(target, state, owner)
    if state.owner ~= nil and state.owner ~= owner then
        local oldSet = ControlSkin.owners[state.owner]
        if oldSet then
            oldSet[target] = nil
        end
    end
    state.owner = owner
    local set = OwnerSet(owner)
    if set then
        set[target] = true
    end
end

local function GetState(target, kind, owner)
    local state = ControlSkin.states[target]
    if not state then
        state = {
            kind = kind,
            enabled = false,
            faded = setmetatable({}, { __mode = "k" }),
            native = {},
        }
        ControlSkin.states[target] = state
    elseif state.kind ~= kind then
        return nil, "control already uses a different skin kind"
    end
    BindOwner(target, state, owner)
    return state
end

local function FadeRegion(state, region)
    if type(region) ~= "table" or type(region.SetAlpha) ~= "function" then
        return false
    end
    if state.faded[region] == nil then
        local alpha = AccessibleNumber(region, "GetAlpha")
        if alpha == nil then
            return false
        end
        state.faded[region] = alpha
    end
    region:SetAlpha(0)
    return true
end

local function FadeNamedRegions(target, state, names)
    if not names then return end
    for index = 1, #names do
        local name = names[index]
        if type(name) == "string" then
            FadeRegion(state, target[name])
        end
    end
end

local function FadeNineSlice(state, nineSlice)
    if type(nineSlice) ~= "table" then
        return
    end
    for index = 1, #nineSlicePieces do
        FadeRegion(state, nineSlice[nineSlicePieces[index]])
    end
end

local function ApplyCosmetics(target, state, kind, spec)
    FadeNamedRegions(target, state, regionSets[kind])
    FadeNamedRegions(target, state, spec and spec.regions)

    if kind == "searchBox" then
        FadeNineSlice(state, target.NineSlice)
    end
    local nineSlices = spec and spec.nineSlices
    if nineSlices then
        for index = 1, #nineSlices do
            local field = nineSlices[index]
            if type(field) == "string" then
                FadeNineSlice(state, target[field])
            end
        end
    end
end

local function RestoreCosmetics(state)
    for region, alpha in pairs(state.faded) do
        -- Leave a cosmetic value installed after ours alone. Zero is the
        -- exact alpha this module owns and is therefore safe to restore.
        if AccessibleNumber(region, "GetAlpha") == 0 then
            region:SetAlpha(alpha)
        end
        state.faded[region] = nil
    end
end

local function ReadSpecialTexture(button, getter)
    return (Safety.Call(button, getter))
end

local function SnapshotButtonState(button, state)
    if state.nativeCaptured then
        return
    end
    state.nativeCaptured = true
    local native = state.native
    native.highlight = ReadSpecialTexture(button, "GetHighlightTexture")
    native.pushed = ReadSpecialTexture(button, "GetPushedTexture")
    native.disabled = ReadSpecialTexture(button, "GetDisabledTexture")
    native.highlightBlendMode = Safety.Read(native.highlight, "GetBlendMode")
end

-- The state-texture setters reject nil. A slot that had no native texture
-- keeps our owned texture, which the caller hides.
local function SetSpecialTexture(button, setter, texture, blendMode)
    if texture == nil then
        return false
    end
    if blendMode then
        return Safety.Invoke(button, setter, texture, blendMode)
    end
    return Safety.Invoke(button, setter, texture)
end

local function SetOwnedStateAlpha(surface, alpha)
    if not surface then
        return
    end
    for index = 1, #ownedStateKeys do
        local texture = surface[ownedStateKeys[index]]
        if texture and type(texture.SetAlpha) == "function" then
            texture:SetAlpha(alpha)
        end
    end
end

local function AssignOwnedButtonStates(button)
    local surface = NS.Registry.GetSurface(button)
    if not surface or surface.kind ~= "button" then
        return false
    end
    -- SkinOwnedButton has already painted the final opacity for all states.
    -- SetAlpha(1) here also replaces SetVertexColor's alpha in the client,
    -- turning even softFill/off highlights and disabled fills fully opaque.
    -- Re-enabling is handled by that paint; binding must preserve its result.
    SetSpecialTexture(button, "SetHighlightTexture", surface.highlight, "BLEND")
    NS.Surface.EnsureOwnedButtonHighlightLayer(button)
    SetSpecialTexture(button, "SetPushedTexture", surface.pushed)
    SetSpecialTexture(button, "SetDisabledTexture", surface.disabled)
    return true
end

local function ForgetNativeStates(state)
    Wipe(state.native)
    state.nativeCaptured = false
end

local function RestoreButtonStates(button, state)
    if not state.nativeCaptured then
        return
    end
    local surface = NS.Registry.GetSurface(button)
    local native = state.native
    if surface then
        if ReadSpecialTexture(button, "GetHighlightTexture") == surface.highlight then
            SetSpecialTexture(button, "SetHighlightTexture", native.highlight, native.highlightBlendMode)
        end
        if ReadSpecialTexture(button, "GetPushedTexture") == surface.pushed then
            SetSpecialTexture(button, "SetPushedTexture", native.pushed)
        end
        if ReadSpecialTexture(button, "GetDisabledTexture") == surface.disabled then
            SetSpecialTexture(button, "SetDisabledTexture", native.disabled)
        end
    end
    SetOwnedStateAlpha(surface, 0)
    ForgetNativeStates(state)
end

local function DetectSelected(tab)
    if type(tab.IsSelected) == "function" then
        return Safety.Read(tab, "IsSelected") == true
    end
    local active = tab.MiddleActive or tab.LeftActive or tab.RightActive
    return Safety.Read(active, "IsShown") == true
end

local function DefaultButtonSpec(kind, spec, target)
    local copy = CopySpec(spec, target)
    local isTab = kind == "minimalTab" or kind == "panelTab"
    copy.role = copy.role or (isTab and "navigation" or "button")
    copy.activeRole = copy.activeRole or (isTab and "navigationActive" or "buttonPrimary")
    if copy.useControlShape == nil then
        copy.useControlShape = true
    end
    if copy.pillHeight == nil then
        copy.pillHeight = kind == "threeSlice" and 32 or 24
    end
    return copy
end

local function DefaultSearchSpec(spec, target)
    local copy = CopySpec(spec, target)
    copy.role = copy.role or "input"
    if copy.useControlShape == nil then
        copy.useControlShape = true
    end
    copy.pillHeight = copy.pillHeight or 20
    return copy
end

local function SkinButtonSurface(button, state, active)
    local isTab = state.kind == "minimalTab" or state.kind == "panelTab"
    if active == nil then active = state.requestedActive end
    if active == nil and isTab then active = DetectSelected(button) end
    return NS.Surface.SkinOwnedButton(button, state.spec, active == true,
        isTab and state.requestedActive == nil)
end

local function TrackNativeAssets(button, owner)
    local actionKind = NS.Checkmarks and NS.Checkmarks.GetWindowAction(button) or nil
    if NS.Checkmarks then
        NS.Checkmarks.TrackButton(button, owner)
        NS.Checkmarks.TrackDropdown(button, owner)
    end
    return actionKind
end

local function MarkWindowAction(state, actionKind)
    state.windowAction = true
    state.actionKind = actionKind
    state.enabled = true
end

local function ApplyButtonNow(button, owner, kind, spec)
    local actionKind = TrackNativeAssets(button, owner)
    local state, reason = GetState(button, kind, owner)
    if not state then
        return nil, reason
    end

    state.spec = DefaultButtonSpec(kind, spec, state.spec)
    state.cosmeticSpec = CopyCosmeticSpec(spec, state.cosmeticSpec)
    state.requestedActive = spec.active
    if actionKind and NS.WindowActionSkin then
        local action, actionReason = NS.WindowActionSkin.Apply(button, owner, actionKind)
        if not action then return nil, actionReason or "window action unavailable" end
        MarkWindowAction(state, actionKind)
        return state
    end

    state.windowAction = false
    state.actionKind = nil
    SnapshotButtonState(button, state)
    local surface, surfaceReason = SkinButtonSurface(button, state)
    if not surface or not AssignOwnedButtonStates(button) then
        ForgetNativeStates(state)
        return nil, surfaceReason or "surface unavailable"
    end
    ApplyCosmetics(button, state, kind, spec)

    state.enabled = true
    return state
end

local function ApplySearchNow(searchBox, owner, spec)
    local state, reason = GetState(searchBox, "searchBox", owner)
    if not state then
        return nil, reason
    end
    state.spec = DefaultSearchSpec(spec, state.spec)
    state.cosmeticSpec = CopyCosmeticSpec(spec, state.cosmeticSpec)
    local surface, surfaceReason = NS.Surface.Attach(searchBox, state.spec)
    if not surface then
        return nil, surfaceReason or "surface unavailable"
    end
    ApplyCosmetics(searchBox, state, "searchBox", spec)
    state.enabled = true
    return state
end

-- Runs apply(target, a, b, c) now, or once after combat under a per-control
-- key. Only the combat path allocates.
local function RunOrDefer(target, allowImplicitProtected, operation, apply, a, b, c)
    if not target then return nil, "invalid control" end
    if IsProtected(target, allowImplicitProtected) then
        return nil, "protected control"
    end
    if type(target.CreateTexture) ~= "function" then return nil, "invalid control" end
    if not NS.IsCombatLocked() then
        return apply(target, a, b, c)
    end
    local _, reason = NS.CombatGate.RunOrDefer("controlskin:" .. tostring(target), function()
        apply(target, a, b, c)
    end)
    return nil, reason or operation
end

local emptySpec = {}

local function ApplyButtonKind(button, owner, spec, kind)
    spec = spec or emptySpec
    return RunOrDefer(button, spec.allowImplicitProtected, "apply", ApplyButtonNow, owner, kind, spec)
end

function ControlSkin.ApplyThreeSliceButton(button, owner, spec)
    return ApplyButtonKind(button, owner, spec, "threeSlice")
end

function ControlSkin.ApplyButton(button, owner, spec)
    return ApplyButtonKind(button, owner, spec, "button")
end

ControlSkin.ApplyUIPanelButton = ControlSkin.ApplyButton

function ControlSkin.ApplyMinimalTab(tab, owner, spec)
    return ApplyButtonKind(tab, owner, spec, "minimalTab")
end

function ControlSkin.ApplyPanelTab(tab, owner, spec)
    return ApplyButtonKind(tab, owner, spec, "panelTab")
end

function ControlSkin.ApplyTab(tab, owner, spec)
    if type(tab) == "table" and (tab.LeftActive or tab.MiddleActive or tab.RightActive) then
        return ControlSkin.ApplyPanelTab(tab, owner, spec)
    end
    return ControlSkin.ApplyMinimalTab(tab, owner, spec)
end

function ControlSkin.ApplySearchBox(searchBox, owner, spec)
    spec = spec or emptySpec
    return RunOrDefer(searchBox, spec.allowImplicitProtected, "apply", ApplySearchNow, owner, spec)
end

-- Button skins follow a native window action (returns nil and its kind) or
-- (re)assign the owned state textures. A refresh also drops an action layer
-- whose native art kit has changed to a non-action family.
local function RepaintButton(target, state, active, dropStaleAction)
    local actionKind = TrackNativeAssets(target, state.owner)
    if actionKind and NS.WindowActionSkin then
        return nil, actionKind
    end
    if dropStaleAction and state.windowAction and NS.WindowActionSkin then
        NS.WindowActionSkin.Disable(target, state.owner)
    end
    state.windowAction = false
    state.actionKind = nil
    -- A disabled control may have been restyled by Blizzard or another addon.
    -- Capture that current cooperative state before our textures are assigned
    -- again so the next Disable restores the latest owner, not our old skin.
    SnapshotButtonState(target, state)
    local surface, reason = SkinButtonSurface(target, state, active)
    if not surface or not AssignOwnedButtonStates(target) then
        return false, reason or "surface unavailable"
    end
    return true
end

local function RefreshNow(target, state, active)
    if not state.enabled then
        return false, "disabled"
    end
    if state.kind == "searchBox" then
        local surface, reason = NS.Surface.Attach(target, state.spec)
        if not surface then
            return false, reason or "surface unavailable"
        end
    else
        local painted, detail = RepaintButton(target, state, active, true)
        if painted == nil then
            if state.nativeCaptured then RestoreButtonStates(target, state) end
            local action, reason = NS.WindowActionSkin.Apply(target, state.owner, detail)
            if not action then return false, reason or "window action unavailable" end
            MarkWindowAction(state, detail)
            return true
        elseif not painted then
            return false, detail
        end
    end
    ApplyCosmetics(target, state, state.kind, state.cosmeticSpec)
    return true
end

local function AllowsImplicit(state)
    return state.spec and state.spec.allowImplicitProtected
end

function ControlSkin.Refresh(target, active)
    local state = ControlSkin.states[target]
    if not state then
        return false, "unknown control"
    end
    local refreshed, reason = RunOrDefer(target, AllowsImplicit(state), "refresh", RefreshNow, state, active)
    if refreshed == nil then
        return false, reason
    end
    return refreshed, reason
end

local function EnableNow(target, state, active)
    if state.kind == "searchBox" then
        local surface, reason = NS.Surface.Attach(target, state.spec)
        if not surface then
            return nil, reason or "surface unavailable"
        end
    else
        local painted, detail = RepaintButton(target, state, active, false)
        if painted == nil then
            local action, reason = NS.WindowActionSkin.Apply(target, state.owner, detail)
            if not action then return nil, reason or "window action unavailable" end
            MarkWindowAction(state, detail)
            return true
        elseif not painted then
            ForgetNativeStates(state)
            return nil, detail
        end
    end
    ApplyCosmetics(target, state, state.kind, state.cosmeticSpec)
    state.enabled = true
    return true
end

function ControlSkin.Enable(target, active)
    local state = ControlSkin.states[target]
    if not state then
        return false, "unknown control"
    end
    local enabled, reason = RunOrDefer(target, AllowsImplicit(state), "enable", EnableNow, state, active)
    if enabled == nil then
        return false, reason
    end
    return enabled, reason
end

local function DisableNow(target, state)
    if NS.Checkmarks then NS.Checkmarks.UntrackDropdown(target) end
    if state.windowAction then
        if NS.Checkmarks and type(NS.Checkmarks.UntrackButton) == "function" then
            NS.Checkmarks.UntrackButton(target, state.owner)
        elseif NS.WindowActionSkin then
            NS.WindowActionSkin.Disable(target, state.owner)
        end
        state.windowAction = false
        state.actionKind = nil
    elseif state.kind ~= "searchBox" then
        RestoreButtonStates(target, state)
    end
    RestoreCosmetics(state)
    NS.Surface.SetNativeStateSync(target, false)
    NS.Surface.SetVisible(target, false)
    state.enabled = false
    return true
end

function ControlSkin.Disable(target)
    local state = ControlSkin.states[target]
    if not state then
        return false, "unknown control"
    end
    local disabled, reason = RunOrDefer(target, AllowsImplicit(state), "disable", DisableNow, state)
    if disabled == nil then
        return false, reason
    end
    return disabled, reason
end

local function RefreshOwnerNow(owner)
    local set = ControlSkin.owners[owner]
    if not set then return end
    for target in pairs(set) do
        local state = ControlSkin.states[target]
        if state and state.enabled and not IsProtected(target, AllowsImplicit(state)) then
            RefreshNow(target, state)
        end
    end
end

local function DisableOwnerNow(owner)
    local set = ControlSkin.owners[owner]
    if not set then return end
    for target in pairs(set) do
        local state = ControlSkin.states[target]
        if state and not IsProtected(target, AllowsImplicit(state)) then
            DisableNow(target, state)
        end
    end
    ControlSkin.owners[owner] = nil
end

-- Owner-wide work shares one key per owner, so a later request replaces a
-- pending one.
local function RunOwnerOperation(owner, operation)
    if not NS.IsCombatLocked() then
        operation(owner)
        return true
    end
    local ran, reason = NS.CombatGate.RunOrDefer("controlskin-owner:" .. tostring(owner), function()
        operation(owner)
    end)
    return ran == true, reason
end

function ControlSkin.RefreshOwner(owner)
    if not ControlSkin.owners[owner] then
        return true
    end
    return RunOwnerOperation(owner, RefreshOwnerNow)
end

function ControlSkin.DisableOwner(owner)
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(owner) end
    if not ControlSkin.owners[owner] then
        return true
    end
    return RunOwnerOperation(owner, DisableOwnerNow)
end

function ControlSkin.IsApplied(target)
    local state = ControlSkin.states[target]
    return state ~= nil and state.enabled == true
end

function ControlSkin.GetKind(target)
    local state = ControlSkin.states[target]
    return state and state.kind or nil
end

function ControlSkin.GetOwner(target)
    local state = ControlSkin.states[target]
    return state and state.enabled and state.owner or nil
end
