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

local function IsProtected(target, allowImplicitProtected)
    return not NS.Safety or not NS.Safety.CanCreateRegions(target, allowImplicitProtected)
end

local function AccessibleNumber(region, method)
    if not region or type(region[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(region[method], region)
    if not ok then
        return nil
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return tonumber(value)
end

local function CopySpec(spec)
    local copy = {}
    for key, value in pairs(spec or {}) do
        if key ~= "active" and key ~= "regions" and key ~= "nineSlices" then
            copy[key] = value
        end
    end
    return copy
end

local function CopyCosmeticSpec(spec)
    local copy = {}
    for _, key in ipairs({ "regions", "nineSlices" }) do
        local source = spec and spec[key]
        if type(source) == "table" then
            local list = {}
            for index = 1, #source do
                list[index] = source[index]
            end
            copy[key] = list
        end
    end
    return copy
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

local function NewState(target, kind, owner)
    local state = {
        kind = kind,
        enabled = false,
        faded = setmetatable({}, { __mode = "k" }),
        native = {},
    }
    ControlSkin.states[target] = state
    BindOwner(target, state, owner)
    return state
end

local function GetState(target, kind, owner)
    local state = ControlSkin.states[target]
    if not state then
        return NewState(target, kind, owner)
    end
    if state.kind ~= kind then
        return nil, "control already uses a different skin kind"
    end
    BindOwner(target, state, owner)
    return state
end

local function FadeRegion(state, region)
    if not region or type(region.SetAlpha) ~= "function" then
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
    for index = 1, #(names or {}) do
        local name = names[index]
        if type(name) == "string" then
            FadeRegion(state, target[name])
        end
    end
end

local function FadeNineSlice(state, nineSlice)
    if not nineSlice then
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
    for index = 1, #((spec and spec.nineSlices) or {}) do
        local field = spec.nineSlices[index]
        if type(field) == "string" then
            FadeNineSlice(state, target[field])
        end
    end
end

local function RestoreCosmetics(state)
    for region, alpha in pairs(state.faded) do
        -- Leave a cosmetic value installed after ours alone. Zero is the
        -- exact alpha this module owns and is therefore safe to restore.
        if AccessibleNumber(region, "GetAlpha") == 0 and type(region.SetAlpha) == "function" then
            region:SetAlpha(alpha)
        end
    end
    state.faded = setmetatable({}, { __mode = "k" })
end

local function ReadSpecialTexture(button, getter)
    if type(button[getter]) ~= "function" then
        return nil
    end
    local ok, texture = pcall(button[getter], button)
    return ok and texture or nil
end

local function SnapshotButtonState(button, state)
    if state.nativeCaptured then
        return
    end
    state.nativeCaptured = true
    state.native.highlight = ReadSpecialTexture(button, "GetHighlightTexture")
    state.native.pushed = ReadSpecialTexture(button, "GetPushedTexture")
    state.native.disabled = ReadSpecialTexture(button, "GetDisabledTexture")
    if state.native.highlight and type(state.native.highlight.GetBlendMode) == "function" then
        local ok, blendMode = pcall(state.native.highlight.GetBlendMode, state.native.highlight)
        if ok then
            state.native.highlightBlendMode = blendMode
        end
    end
end

local function SetSpecialTexture(button, setter, texture, blendMode)
    if type(button[setter]) ~= "function" then
        return false
    end
    local ok
    if blendMode then
        ok = pcall(button[setter], button, texture, blendMode)
    else
        ok = pcall(button[setter], button, texture)
    end
    return ok == true
end

local function SetOwnedStateAlpha(surface, alpha)
    if not surface then
        return
    end
    for _, key in ipairs({ "highlight", "pushed", "disabled" }) do
        local texture = surface[key]
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

local function RestoreButtonStates(button, state)
    if not state.nativeCaptured then
        return
    end
    local surface = NS.Registry.GetSurface(button)
    if surface then
        if ReadSpecialTexture(button, "GetHighlightTexture") == surface.highlight then
            SetSpecialTexture(button, "SetHighlightTexture", state.native.highlight, state.native.highlightBlendMode)
        end
        if ReadSpecialTexture(button, "GetPushedTexture") == surface.pushed then
            SetSpecialTexture(button, "SetPushedTexture", state.native.pushed)
        end
        if ReadSpecialTexture(button, "GetDisabledTexture") == surface.disabled then
            SetSpecialTexture(button, "SetDisabledTexture", state.native.disabled)
        end
    end
    SetOwnedStateAlpha(surface, 0)
    state.native = {}
    state.nativeCaptured = false
end

local function DetectSelected(tab)
    if type(tab.IsSelected) == "function" then
        local ok, selected = pcall(tab.IsSelected, tab)
        if ok then
            return selected == true
        end
    end
    local active = tab.MiddleActive or tab.LeftActive or tab.RightActive
    if active and type(active.IsShown) == "function" then
        local ok, shown = pcall(active.IsShown, active)
        if ok then
            return shown == true
        end
    end
    return false
end

local function DefaultButtonSpec(kind, spec)
    local copy = CopySpec(spec)
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

local function DefaultSearchSpec(spec)
    local copy = CopySpec(spec)
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

local function ApplyButtonNow(button, owner, kind, spec)
    local actionKind = NS.Checkmarks and NS.Checkmarks.GetWindowAction(button) or nil
    if NS.Checkmarks then
        NS.Checkmarks.TrackButton(button, owner)
        NS.Checkmarks.TrackDropdown(button, owner)
    end
    local state, reason = GetState(button, kind, owner)
    if not state then
        return nil, reason
    end

    state.spec = DefaultButtonSpec(kind, spec)
    state.cosmeticSpec = CopyCosmeticSpec(spec)
    state.requestedActive = spec and spec.active
    if actionKind and NS.WindowActionSkin then
        local action, actionReason = NS.WindowActionSkin.Apply(button, owner, actionKind)
        if not action then return nil, actionReason or "window action unavailable" end
        state.windowAction = true
        state.actionKind = actionKind
        state.enabled = true
        return state
    end

    state.windowAction = false
    state.actionKind = nil
    state.preserveNativeStates = false
    SnapshotButtonState(button, state)
    local surface, surfaceReason
    surface, surfaceReason = SkinButtonSurface(button, state)
    if not surface or not AssignOwnedButtonStates(button) then
        state.native = {}
        state.nativeCaptured = false
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
    state.spec = DefaultSearchSpec(spec)
    state.cosmeticSpec = CopyCosmeticSpec(spec)
    local surface, surfaceReason = NS.Surface.Attach(searchBox, state.spec)
    if not surface then
        return nil, surfaceReason or "surface unavailable"
    end
    ApplyCosmetics(searchBox, state, "searchBox", spec)
    state.enabled = true
    return state
end

local function ApplyDeferred(target, operation, callback, allowImplicitProtected)
    if not target then return nil, "invalid control" end
    if IsProtected(target, allowImplicitProtected) then
        return nil, "protected control"
    end
    if type(target.CreateTexture) ~= "function" then return nil, "invalid control" end

    -- Ordinary OOC applications do not need a deferred job key, wrapper or
    -- captured result slots. Keep the keyed combat path exactly as before.
    if not NS.IsCombatLocked() then
        local result, reason = callback()
        return result, reason
    end

    local result, callbackReason
    local ran, reason = NS.CombatGate.RunOrDefer("controlskin:" .. tostring(target), function()
        result, callbackReason = callback()
    end)
    if ran then
        return result, callbackReason
    end
    return nil, reason or operation
end

function ControlSkin.ApplyThreeSliceButton(button, owner, spec)
    spec = spec or {}
    return ApplyDeferred(button, "apply", function()
        return ApplyButtonNow(button, owner, "threeSlice", spec)
    end, spec.allowImplicitProtected)
end

function ControlSkin.ApplyButton(button, owner, spec)
    spec = spec or {}
    return ApplyDeferred(button, "apply", function()
        return ApplyButtonNow(button, owner, "button", spec)
    end, spec.allowImplicitProtected)
end

ControlSkin.ApplyUIPanelButton = ControlSkin.ApplyButton

function ControlSkin.ApplyMinimalTab(tab, owner, spec)
    spec = spec or {}
    return ApplyDeferred(tab, "apply", function()
        return ApplyButtonNow(tab, owner, "minimalTab", spec)
    end, spec.allowImplicitProtected)
end

function ControlSkin.ApplyPanelTab(tab, owner, spec)
    spec = spec or {}
    return ApplyDeferred(tab, "apply", function()
        return ApplyButtonNow(tab, owner, "panelTab", spec)
    end, spec.allowImplicitProtected)
end

function ControlSkin.ApplyTab(tab, owner, spec)
    if tab and (tab.LeftActive or tab.MiddleActive or tab.RightActive) then
        return ControlSkin.ApplyPanelTab(tab, owner, spec)
    end
    return ControlSkin.ApplyMinimalTab(tab, owner, spec)
end

function ControlSkin.ApplySearchBox(searchBox, owner, spec)
    spec = spec or {}
    return ApplyDeferred(searchBox, "apply", function()
        return ApplySearchNow(searchBox, owner, spec)
    end, spec.allowImplicitProtected)
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
        ApplyCosmetics(target, state, state.kind, state.cosmeticSpec)
    else
        local actionKind = NS.Checkmarks and NS.Checkmarks.GetWindowAction(target) or nil
        if NS.Checkmarks then
            NS.Checkmarks.TrackButton(target, state.owner)
            NS.Checkmarks.TrackDropdown(target, state.owner)
        end
        if actionKind and NS.WindowActionSkin then
            if state.nativeCaptured then RestoreButtonStates(target, state) end
            local action, reason = NS.WindowActionSkin.Apply(target, state.owner, actionKind)
            if not action then return false, reason or "window action unavailable" end
            state.windowAction = true
            state.actionKind = actionKind
            state.preserveNativeStates = false
            state.enabled = true
            return true
        elseif state.windowAction and NS.WindowActionSkin then
            NS.WindowActionSkin.Disable(target, state.owner)
            state.windowAction = false
            state.actionKind = nil
        end
        SnapshotButtonState(target, state)
        local surface, reason = SkinButtonSurface(target, state, active)
        if not surface or not AssignOwnedButtonStates(target) then
            return false, reason or "surface unavailable"
        end
        ApplyCosmetics(target, state, state.kind, state.cosmeticSpec)
    end
    return true
end

function ControlSkin.Refresh(target, active)
    local state = ControlSkin.states[target]
    if not state then
        return false, "unknown control"
    end
    local result, callbackReason
    local refreshed, reason = ApplyDeferred(target, "refresh", function()
        result, callbackReason = RefreshNow(target, state, active)
        return result, callbackReason
    end, state.spec and state.spec.allowImplicitProtected)
    if refreshed == nil then
        return false, reason
    end
    return refreshed, callbackReason
end

local function EnableNow(target, state, active)
    if state.kind == "searchBox" then
        local surface, reason = NS.Surface.Attach(target, state.spec)
        if not surface then
            return nil, reason or "surface unavailable"
        end
    else
        local actionKind = NS.Checkmarks and NS.Checkmarks.GetWindowAction(target) or nil
        if NS.Checkmarks then
            NS.Checkmarks.TrackButton(target, state.owner)
            NS.Checkmarks.TrackDropdown(target, state.owner)
        end
        if actionKind and NS.WindowActionSkin then
            local action, reason = NS.WindowActionSkin.Apply(target, state.owner, actionKind)
            if not action then return nil, reason or "window action unavailable" end
            state.windowAction = true
            state.actionKind = actionKind
            state.enabled = true
            return true
        end
        state.windowAction = false
        state.actionKind = nil
        -- A disabled control may have been restyled by Blizzard or another addon.
        -- Capture that current cooperative state before our textures are assigned
        -- again so the next Disable restores the latest owner, not our old skin.
        SnapshotButtonState(target, state)
        local surface, reason = SkinButtonSurface(target, state, active)
        if not surface or not AssignOwnedButtonStates(target) then
            state.native = {}
            state.nativeCaptured = false
            return nil, reason or "surface unavailable"
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
    local enabled, reason = ApplyDeferred(target, "enable", function()
        return EnableNow(target, state, active)
    end, state.spec and state.spec.allowImplicitProtected)
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
    local result, callbackReason
    local disabled, reason = ApplyDeferred(target, "disable", function()
        result, callbackReason = DisableNow(target, state)
        return result, callbackReason
    end, state.spec and state.spec.allowImplicitProtected)
    if disabled == nil then
        return false, reason
    end
    return disabled, callbackReason
end

function ControlSkin.RefreshOwner(owner)
    local set = ControlSkin.owners[owner]
    if not set then
        return true
    end
    local ran, reason = NS.CombatGate.RunOrDefer("controlskin-owner:" .. tostring(owner), function()
        for target in pairs(set) do
            local state = ControlSkin.states[target]
            if state and state.enabled and not IsProtected(target, state.spec and state.spec.allowImplicitProtected) then
                RefreshNow(target, state)
            end
        end
    end)
    return ran == true, reason
end

function ControlSkin.DisableOwner(owner)
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(owner) end
    local set = ControlSkin.owners[owner]
    if not set then
        return true
    end
    local ran, reason = NS.CombatGate.RunOrDefer("controlskin-owner:" .. tostring(owner), function()
        for target in pairs(set) do
            local state = ControlSkin.states[target]
            if state and not IsProtected(target, state.spec and state.spec.allowImplicitProtected) then
                DisableNow(target, state)
            end
        end
        ControlSkin.owners[owner] = nil
    end)
    return ran == true, reason
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
