local _, NS = ...

-- Versioned public integration API.  External addons explicitly submit only
-- their own visual targets; MapkoSkin never executes their callbacks,
-- traverses their frame trees, or exposes internal owner/state tables.
-- This file checks their input and reconciles each claimed target;
-- PublicAPIMethods.lua adds the facades they call.
local PublicAPI = {
    major = NS.publicAPIMajor,
    minor = NS.publicAPIMinor,
    databaseReady = false,
    playerReady = false,
}
NS.PublicAPI = PublicAPI
-- The optional rendering half binds these after the facades load.
PublicAPI.PlayContent = function() return false end
PublicAPI.StopContent = function() return false end
PublicAPI.TrackMenu = function() return false end
PublicAPI.ReleaseMenu = function() end
PublicAPI.OnRegistrationChanged = function() end

-- The rendering modules load before this file (TOC order).
local ControlSkin = NS.ControlSkin
local WindowActionSkin = NS.WindowActionSkin
local IconSkin = NS.IconSkin
local Cosmetics = NS.Cosmetics
local Registry = NS.Registry

local API = {
    major = PublicAPI.major,
    minor = PublicAPI.minor,
    version = PublicAPI.major,
}
PublicAPI.API = API

local clients = {}
local clientRecords = setmetatable({}, { __mode = "k" })
local scopeRecords = setmetatable({}, { __mode = "k" })
local claims = setmetatable({}, { __mode = "k" })
local registeredWindows = setmetatable({}, { __mode = "k" })
local showHooks = setmetatable({}, { __mode = "k" })
local QueueEntry, ReconcileEntry, ReleaseEntry

local materialRoles = {
    shell = true, panel = true, card = true, popup = true, input = true,
    button = true, buttonPrimary = true, navigation = true,
    buttonDanger = true, buttonSuccess = true,
    navigationActive = true, status = true,
}

local shapes = {
    pill = true, round = true, continuous = true, squircle = true,
}

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

-- A number between minimum and maximum; nil for anything else.
local function ClampOption(value, minimum, maximum)
    value = tonumber(value)
    if not value then return nil end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

-- Read declarative options without invoking caller metatables.
local Public = NS.Safety.Public
local function OptionValue(options, key)
    local value = rawget(options, key)
    if type(value) ~= "nil" and Public(value) then return value end
end

local function ReadOption(options, key)
    if type(options) == "table" and Public(options) then return OptionValue(options, key) end
end

-- ownedArt: the caller built this control itself, with no native state
-- textures, Icon or Checked fields, dropdown mixin or Blizzard-gold text,
-- and never adds them. The skin then skips its native-asset and gold-text
-- tracking for it; a false claim only costs the caller that adoption.
local specFlags = { "active", "forceEdge", "listItem", "slice", "useControlShape", "ownedArt", "paletteMotion", "selectionEdge" }

-- Whitelist only declarative rendering values.  Public callers cannot pass
-- region arrays, callbacks, functions, internal owner tokens, or the reviewed
-- allowImplicitProtected exception used by a few built-in Blizzard adapters.
local function SanitizeSpec(source)
    local spec = { allowImplicitProtected = false }
    if type(source) ~= "table" or not Public(source) then return spec end
    local role = OptionValue(source, "role")
    local activeRole = OptionValue(source, "activeRole")
    local shape = OptionValue(source, "shape")
    if materialRoles[role] then spec.role = role end
    if materialRoles[activeRole] then spec.activeRole = activeRole end
    if shapes[shape] then spec.shape = shape end
    spec.inset = ClampOption(OptionValue(source, "inset"), -16, 32)
    spec.radius = ClampOption(OptionValue(source, "radius"), 4, 12)
    spec.border = ClampOption(OptionValue(source, "border"), 0, 2)
    spec.pillHeight = ClampOption(OptionValue(source, "pillHeight"), 20, 32)
    for index = 1, #specFlags do
        local key = specFlags[index]
        local value = OptionValue(source, key)
        if type(value) == "boolean" then spec[key] = value end
    end
    local keepGlassFill = rawget(source, "keepGlassFill")
    if type(keepGlassFill) == "boolean" and Public(keepGlassFill) then spec.keepGlassFill = keepGlassFill end
    local motion = OptionValue(source, "motion")
    if type(motion) == "boolean" then spec.motion = motion end
    local group = OptionValue(source, "motionGroup")
    if type(group) == "string" and #group <= 80 then spec.motionGroup = group end
    return spec
end

local function ScopeAllowed(scope)
    if not scope or scope.client.internal then return true end
    local settings = NS.DB and NS.DB.addonSkins
    return not settings or settings.registered ~= false
end

local function RuntimeEnabled(scope)
    return PublicAPI.playerReady == true and NS.DB and NS.DB.enabled == true and ScopeAllowed(scope)
end

-- Counts settings notifications (theme, colours, geometry, profile, adapters,
-- master switch). A fully applied entry records the count it was applied
-- under; see SelectEntry.
local settingsGeneration = 0

local function NextSettingsGeneration()
    settingsGeneration = settingsGeneration + 1
end

-- Public input is untrusted: forbidden, protected (explicitly or through a
-- secure descendant) and compositor-managed targets are refused.
local function SafeTarget(target, needsRegions)
    if not NS.Safety.Public(target) then return false, "secret-target" end
    if target == nil then return false, "invalid-target" end
    local Safety = NS.Safety
    -- GetProtection checks forbidden status before reading any other method.
    -- Keep the answers local to this check: parenting/protection can change.
    local protected, explicit = Safety.GetProtection(target)
    if protected or explicit then return false, "protected-target" end
    if needsRegions and (type(target) ~= "table" or Safety.IsCompositorManaged(target)) then
        return false, "protected-target"
    end
    return true
end

local function ReadMember(target, key)
    return NS.Safety.Field(target, key) or nil
end

-- A secret parent (12.1 Hierarchy aspect) reads as nil and is never compared.
local function IsDescendant(target, region)
    local current = region
    for _ = 1, 8 do
        local parent = NS.Safety.Read(current, "GetParent")
        if not parent then return false end
        if parent == target then return true end
        current = parent
    end
    return false
end

local function ResolveIconSpec(button, options)
    options = type(options) == "table" and options or {}
    local icon = ReadOption(options, "icon")
        or ReadMember(button, "Icon") or ReadMember(button, "icon")
        or ReadMember(button, "IconTexture")
    local nativeBorder = ReadOption(options, "nativeBorder")
        or ReadMember(button, "IconBorder") or ReadMember(button, "iconBorder")
    local safeIcon = SafeTarget(icon, false)
    local safeBorder = SafeTarget(nativeBorder, false)
    if not safeIcon or not safeBorder then return nil, "protected-target" end
    if not IsDescendant(button, icon) or not IsDescendant(button, nativeBorder) then
        return nil, "foreign-region"
    end
    return {
        allowImplicitProtected = false,
        icon = icon,
        nativeBorder = nativeBorder,
    }
end

local function ExistingOwner(target)
    local bar = NS.ScrollBarSkin.GetState(target)
    return (bar and bar.enabled ~= false and bar.owner) or ControlSkin.GetOwner(target) or WindowActionSkin.GetOwner(target)
        or IconSkin.GetOwner(target) or Cosmetics.GetOwner(target)
end

local function TargetEntry(scope, target, needsRegions)
    local safe, reason = SafeTarget(target, needsRegions)
    if not safe then return nil, reason end
    local claimed = claims[target]
    local entry = scope.targets[target]
    if entry then
        if claimed and claimed ~= entry then return nil, "already-owned" end
        return entry
    end
    if claimed then return nil, "already-owned" end
    if ExistingOwner(target) then return nil, "already-owned" end
    local surface = Registry.GetSurface(target)
    if surface and surface.visible ~= false then return nil, "already-owned" end
    entry = {
        owner = {},
        scope = scope, target = target,
        pendingKey = "public-target:" .. scope.key .. ":" .. tostring(target),
        dependencies = WeakSet(),
    }
    scope.targets[target] = entry
    if scope.outcomes then scope.outcomes[target] = nil end
    claims[target] = entry
    return entry
end

local function ClaimDependency(entry, target)
    local safe, reason = SafeTarget(target, false)
    if not safe then return false, reason end
    local claimed = claims[target]
    if claimed and claimed ~= entry then return false, "already-owned" end
    local owner = ExistingOwner(target)
    if owner and owner ~= entry.owner then return false, "already-owned" end
    claims[target] = entry
    entry.dependencies[target] = true
    return true
end

-- Check every named child before assigning any part of a composite widget.
local function ClaimParts(entry, parts)
    local previous = entry.parts
    local bar = entry.widget and entry.widget.plan.nativeBar and NS.ScrollBarSkin.GetState(entry.target)
    for part in pairs(parts) do
        if claims[part] and claims[part] ~= entry then return false, "already-owned" end
        local owner = ExistingOwner(part)
        if owner and owner ~= entry.owner and not (bar and bar.owner == entry.owner and owner == bar.cosmeticOwner) then
            return false, "already-owned"
        end
        local surface = Registry.GetSurface(part)
        if surface and surface.visible ~= false and not (previous and previous[part]) then return false, "already-owned" end
    end
    if previous then
        for part in pairs(previous) do
            if not parts[part] and claims[part] == entry and not entry.dependencies[part] then claims[part] = nil end
        end
    end
    for part in pairs(parts) do claims[part] = entry end
    entry.parts = parts
    return true
end

local function EntryNeedsRegions(entry)
    return entry.surface ~= nil or entry.control ~= nil or entry.icon ~= nil or entry.menu ~= nil or entry.window ~= nil
end

local function ValidateEntry(entry)
    local safe, reason = SafeTarget(entry.target, EntryNeedsRegions(entry))
    if not safe then return false, reason end
    if entry.label and not NS.LabelStyle.CanStyle(entry.target) then return false, "protected-target" end
    if entry.icon then
        safe, reason = SafeTarget(entry.icon.icon, false)
        if not safe then return false, reason end
        safe, reason = SafeTarget(entry.icon.nativeBorder, false)
        if not safe then return false, reason end
        if not IsDescendant(entry.target, entry.icon.icon)
            or not IsDescendant(entry.target, entry.icon.nativeBorder) then
            return false, "foreign-region"
        end
        if claims[entry.icon.nativeBorder] ~= entry then
            return false, "already-owned"
        end
        local owner = ExistingOwner(entry.icon.nativeBorder)
        if owner and owner ~= entry.owner then return false, "already-owned" end
    end
    return true
end

-- Entry failures are reported while other targets keep their work. The
-- completion flag distinguishes an error from a callback's normal refusal.
local function FinishCall(callback, ...)
    return true, callback(...)
end

local function GuardedCall(callback, ...)
    local finished, ok, reason = NS.Safety.Dispatch(FinishCall, callback, ...)
    if not finished then return false, "error" end
    return ok, reason
end

local function ReleaseClose(entry)
    local close = entry.ownedClose
    if not close then return true end
    if close.sponsor == entry then
        local ok, reason = ReleaseEntry(entry.scope, close.target, close)
        if not ok then return false, reason end
    elseif close.captionHost == entry then
        close.captionHost = nil
        local scope = entry.scope
        if scope.targets[close.target] == close and not scope.suspended and not scope.client.unregisterPending and RuntimeEnabled(scope) then
            local ok, reason = ReconcileEntry(scope, close.target, close)
            if not ok then return false, reason end
        end
    end
    entry.ownedClose = nil
    return true
end

local function CleanupNow(entry)
    local safe, reason = ValidateEntry(entry)
    if not safe then return false, reason end
    if entry.ownedClose then
        local ok, why = ReleaseClose(entry)
        if not ok then return false, why end
    end
    if entry.addonWindow then
        local ok, why = NS.AddonWindowControls.Release(entry)
        if not ok then return false, why end
    end
    if entry.caption then NS.PublicCaption.Release(entry) end
    if entry.widget then NS.PublicWidgets.Release(entry) end
    PublicAPI.ReleaseMenu(entry.owner, entry.target)
    PublicAPI.StopContent(entry.owner, entry.target)
    if entry.label then NS.LabelStyle.Release(entry.target, entry.owner) end
    ControlSkin.DisableOwner(entry.owner)
    WindowActionSkin.DisableOwner(entry.owner)
    IconSkin.DisableOwner(entry.owner)
    Cosmetics.RestoreOwner(entry.owner)
    if Registry.GetSurface(entry.target) then
        NS.Surface.SetNativeStateSync(entry.target, false)
        NS.Surface.SetVisible(entry.target, false)
    end
    entry.pendingVisible = nil
    entry.applied = false
    return true
end

local function CleanupEntry(entry)
    return GuardedCall(CleanupNow, entry)
end

local function DropEntry(scope, target, entry)
    NS.CombatGate.Cancel(entry.pendingKey)
    if claims[target] == entry then claims[target] = nil end
    for dependency in pairs(entry.dependencies or {}) do
        if claims[dependency] == entry then claims[dependency] = nil end
    end
    if entry.parts then
        for part in pairs(entry.parts) do if claims[part] == entry then claims[part] = nil end end
    end
    local parent = entry.sponsor or entry.captionHost
    if parent then parent.ownedClose = nil end
    registeredWindows[entry] = nil
    scope.targets[target] = nil
    scope.outcomes = scope.outcomes or WeakSet()
    scope.outcomes[target] = true
end

ReleaseEntry = function(scope, target, entry)
    local cleaned, reason = CleanupEntry(entry)
    if not cleaned then
        if entry.applied ~= true then
            DropEntry(scope, target, entry)
            return true, "released"
        end
        return false, reason
    end
    DropEntry(scope, target, entry)
    return true, "released"
end

local function ApplyControl(target, entry)
    local control = entry.control
    if not control then return true end
    local method
    if control.widget then
        local plan, reason = NS.PublicWidgets.Describe(target, control.kind, control.spec)
        if not plan then return false, reason end
        local claimed
        claimed, reason = ClaimParts(entry, plan.parts)
        if not claimed then return false, reason end
        return NS.PublicWidgets.Apply(entry, plan)
    elseif control.kind == "windowAction" then
        if control.caption or entry.captionHost then
            entry.nativeAction = nil
            if WindowActionSkin.GetOwner(target) == entry.owner then WindowActionSkin.Disable(target, entry.owner) end
            local parts = NS.PublicCaption.Parts(target)
            if not parts then return false, "invalid-caption-art" end
            local claimed, reason = ClaimParts(entry, parts)
            if not claimed then return false, reason end
            return NS.PublicCaption.Apply(entry, parts)
        end
        if entry.caption then NS.PublicCaption.Release(entry) ClaimParts(entry, {}) end
        local state, reason = WindowActionSkin.ApplyExplicit(target, entry.owner, control.action, control.motion ~= false, control.options)
        entry.nativeAction = state and state.style == "native"
        return state ~= nil, reason
    elseif control.kind == "button" then
        method = ControlSkin.ApplyButton
    elseif control.kind == "threeSlice" then
        method = ControlSkin.ApplyThreeSliceButton
    elseif control.kind == "tab" then
        method = ControlSkin.ApplyTab
    elseif control.kind == "searchBox" then
        method = ControlSkin.ApplySearchBox
    end
    if not method then return false, "unsupported-control" end
    local state, reason = method(target, entry.owner, control.spec)
    if not state then return false, reason or "unsupported-control" end
    return true
end

local function ApplyCosmetic(target, entry)
    if not entry.cosmetic then return true end
    local applied
    if entry.cosmetic == "alpha" then
        applied = Cosmetics.Fade(target, entry.owner)
    elseif entry.cosmetic == "vertex" then
        applied = Cosmetics.SuppressVertexAlpha(target, entry.owner)
    end
    if not applied then return false, "unsupported-region" end
    return true
end

local function FailEntry(scope, target, entry, reason)
    local cleaned = CleanupEntry(entry)
    if cleaned or entry.applied ~= true then
        DropEntry(scope, target, entry)
        scope.outcomes[target] = reason or "error"
    end
    return false, reason
end

local function Shown(target)
    local entry = claims[target]
    if entry and entry.pendingVisible then QueueEntry(entry.scope, target, entry) end
end

-- Build the requested art only when this frame can display it. Repeated
-- setters/refreshes while hidden update the same entry, then paint once.
-- Menu-only watches remain cheap and must precede their first OnShow.
local function DeferHidden(scope, target, entry)
    if entry.applied or entry.release or not (entry.surface or entry.control or entry.icon)
        or scope.client.name ~= "MidnightSimpleUnitFrames"
        or not NS.Safety.HasMethod(target, "HookScript")
        or NS.Safety.Read(target, "IsVisible") ~= false then return false end
    if not NS.SuiteOwnership.IsOptionsSurface(target) then return false end
    if not showHooks[target] then
        target:HookScript("OnShow", Shown)
        showHooks[target] = true
    end
    entry.scope, entry.pendingVisible = scope, true
    return true
end

local function ApplyWindow(scope, entry)
    local options = entry.window
    local valid, why = NS.AddonWindowControls.Validate(entry.target, options)
    if not valid then return false, why end
    local close = NS.AddonWindowControls.Enabled() and options.closeButton
    if entry.ownedClose and entry.ownedClose.target ~= close then
        local ok, reason = ReleaseClose(entry)
        if not ok then return false, reason end
    end
    if close and not entry.skipClose then
        local child, reason = TargetEntry(scope, close, true)
        if not child then return false, reason end
        if not child.control then
            if child.surface then return false, "kind-conflict" end
            child.control = { kind = "windowAction", action = "close", caption = true }
            child.sponsor, entry.ownedClose = entry, child
            local ok
            ok, reason = ReconcileEntry(scope, close, child)
            if not ok then return false, reason end
        elseif child.control.kind ~= "windowAction" or child.control.action ~= "close" then
            return false, "kind-conflict"
        elseif not child.control.caption and not child.captionHost then
            child.captionHost, entry.ownedClose = entry, child
            local ok, why = ReconcileEntry(scope, close, child)
            if not ok then return false, why end
        end
    end
    return NS.AddonWindowControls.Apply(entry, options, scope.client.name)
end

local function ReconcileNow(scope, target, entry)
    if scope.released or scope.client.released or scope.client.unregisterPending
        or entry.release then
        return ReleaseEntry(scope, target, entry)
    end
    -- A hidden host surface already has its OnShow hook. Later setters only
    -- change the requested state. Recheck all parts when painting is possible.
    if entry.pendingVisible and not scope.suspended and RuntimeEnabled(scope)
        and NS.Safety.ReadUnprotected(target, "IsVisible") == false then return true, "applied" end
    local safe, reason = ValidateEntry(entry)
    if not safe then return FailEntry(scope, target, entry, reason) end
    if scope.suspended or not RuntimeEnabled(scope) then
        local cleaned, cleanReason = CleanupEntry(entry)
        return cleaned, cleaned and "suspended" or cleanReason
    end

    -- The host suppresses its fallback only for an accepted "applied" result.
    -- This entry owns that presentation now; its one paint waits for visibility.
    if DeferHidden(scope, target, entry) then return true, "applied" end
    if entry.pendingVisible and entry.active ~= nil and entry.control and entry.control.kind == "button" then
        entry.control.spec.active = entry.active
    end
    entry.pendingVisible = nil

    -- Attach/control painters can change native state before they finish.
    -- Retain this owner after a partial failure until cleanup really succeeds.
    entry.applied = true
    if entry.surface then
        local surface
        surface, reason = NS.Surface.Attach(target, entry.surface)
        if not surface then return FailEntry(scope, target, entry, reason or "unsupported-frame") end
    end
    local applied
    applied, reason = ApplyControl(target, entry)
    if not applied then return FailEntry(scope, target, entry, reason) end
    if entry.icon then
        local state
        state, reason = IconSkin.Apply(target, entry.owner, entry.icon)
        if not state then return FailEntry(scope, target, entry, reason or "unsupported-icon") end
    end
    applied, reason = ApplyCosmetic(target, entry)
    if not applied then return FailEntry(scope, target, entry, reason) end
    if entry.active ~= nil then
        applied, reason = NS.Surface.SetActive(target, entry.active)
        if not applied then return FailEntry(scope, target, entry, reason or "unsupported-state") end
    end
    if entry.visible ~= nil then
        applied, reason = NS.Surface.SetVisible(target, entry.visible)
        if not applied then return FailEntry(scope, target, entry, reason or "unsupported-state") end
    end
    if entry.window then
        applied, reason = ApplyWindow(scope, entry)
        if not applied then return FailEntry(scope, target, entry, reason or "unsupported-window") end
        if reason == "suspended" and not (entry.surface or entry.control or entry.icon or entry.label or entry.menu or entry.cosmetic) then
            entry.applied = false
            return true, reason
        end
    end
    entry.applied = true
    if entry.menu then PublicAPI.TrackMenu(target, entry.owner, entry.menu == "content") end
    if entry.label then NS.LabelStyle.Apply(target, entry.owner) end
    entry.appliedControl, entry.appliedFor = entry.control, settingsGeneration
    return true, "applied"
end

ReconcileEntry = function(scope, target, entry)
    local previous = entry.status
    local ok, reason = GuardedCall(ReconcileNow, scope, target, entry)
    entry.status = ok and (entry.pendingVisible and "pending-visible" or reason == "applied" and entry.nativeAction and "native" or reason) or "failed"
    entry.failure = not ok and reason or nil
    if scope.notifyTargets and (previous == "queued" or previous == "pending" or previous == "deferred" or previous == "pending-visible")
        and entry.status ~= "pending-visible" then NS.Registry.QueueJob(scope.signalJob) end
    return ok, reason
end

-- Suite's authored Character Panel tabs only paint addon artwork. Their
-- navigation must work on the first opening in combat as well as on retargets.
local function OwnedCharacterNavigation(scope, entry)
    local spec = entry.surface
    return spec and spec.ownedArt and spec.motion == true and spec.role == "navigation"
        and scope.client.name == "MSUF_Suite_characterPanel"
        and not (entry.control or entry.icon or entry.cosmetic or entry.menu or entry.release)
        and entry.visible == nil and not scope.suspended and scope.pendingOperation ~= "release" and RuntimeEnabled(scope)
end

QueueEntry = function(scope, target, entry)
    if not PublicAPI.playerReady then entry.status = "pending" return true, "pending" end
    if NS.IsCombatLocked() and not (OwnedCharacterNavigation(scope, entry) and ValidateEntry(entry)) then
        entry.status = "deferred"
        if not entry.afterCombat then
            entry.afterCombat = function()
                if scope.targets[target] == entry then ReconcileEntry(scope, target, entry) end
            end
        end
        NS.CombatGate.RunOrDefer(entry.pendingKey, entry.afterCombat)
        return true, "deferred"
    end
    local applied, reason = ReconcileEntry(scope, target, entry)
    return applied == true, reason
end

-- An owned button skin over a shown button surface: what ApplyButtonNow
-- leaves behind for owner.
local function PaintedButton(target, owner)
    local state = ControlSkin.states[target]
    if not state or state.kind ~= "button" or state.enabled ~= true
        or state.windowAction or state.owner ~= owner then
        return false
    end
    local surface = Registry.GetSurface(target)
    return surface ~= nil and surface.kind == "button" and surface.visible ~= false
        and not surface.syncNativeSelected
end

-- A selection change on a button that its last full reconcile applied with
-- this control spec, under the same settings: that reconcile ended in one
-- paint for the selection, and everything before it would repeat what the
-- button already shows. So only that paint runs. Any other change (a new spec
-- or role, a settings notification, suspend, release, another owner, an
-- icon, cosmetic or visibility aspect) takes the full reconcile.
local function SelectEntry(scope, target, entry)
    if OwnedCharacterNavigation(scope, entry) and claims[target] == entry
        and entry.applied and entry.appliedFor == settingsGeneration then
        local surface = Registry.GetSurface(target)
        if surface and surface.spec == entry.surface and surface.visible ~= false and not surface.syncNativeSelected
            and ValidateEntry(entry) and NS.Surface.SetActive(target, entry.active) then
            return true, "applied"
        end
    end
    local control = entry.control
    if control and control.kind == "button" and entry.appliedControl == control
        and entry.applied == true and entry.appliedFor == settingsGeneration
        and not (entry.surface or entry.icon or entry.cosmetic) and entry.visible == nil
        and PublicAPI.playerReady and not NS.IsCombatLocked()
        and not scope.suspended and RuntimeEnabled(scope)
        and PaintedButton(target, entry.owner) and ValidateEntry(entry)
        and NS.Surface.SetActive(target, entry.active, true) then
        return true, "applied"
    end
    return QueueEntry(scope, target, entry)
end

-- Private to PublicAPIMethods.lua, which loads next (TOC order) and takes it
-- off NS again.
NS.PublicAPIShared = {
    clients = clients,
    ScopeAllowed = ScopeAllowed,
    registeredWindows = registeredWindows,
    GuardedCall = GuardedCall,
    clientRecords = clientRecords,
    scopeRecords = scopeRecords,
    WeakSet = WeakSet,
    ReadOption = ReadOption,
    SanitizeSpec = SanitizeSpec,
    RuntimeEnabled = RuntimeEnabled,
    SafeTarget = SafeTarget,
    ResolveIconSpec = ResolveIconSpec,
    TargetEntry = TargetEntry,
    ClaimDependency = ClaimDependency,
    CleanupEntry = CleanupEntry,
    DropEntry = DropEntry,
    ReconcileEntry = ReconcileEntry,
    QueueEntry = QueueEntry,
    SelectEntry = SelectEntry,
    NextSettingsGeneration = NextSettingsGeneration,
}
