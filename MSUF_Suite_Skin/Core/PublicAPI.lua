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

-- Raw option read: caller metatables never run. False reads as unset.
local function ReadOption(options, key)
    if type(options) ~= "table" then return nil end
    return rawget(options, key) or nil
end

-- ownedArt: the caller built this control itself, with no native state
-- textures, Icon or Checked fields, dropdown mixin or Blizzard-gold text,
-- and never adds them. The skin then skips its native-asset and gold-text
-- tracking for it; a false claim only costs the caller that adoption.
local specFlags = { "active", "forceEdge", "listItem", "slice", "useControlShape", "ownedArt" }

-- Whitelist only declarative rendering values.  Public callers cannot pass
-- region arrays, callbacks, functions, internal owner tokens, or the reviewed
-- allowImplicitProtected exception used by a few built-in Blizzard adapters.
local function SanitizeSpec(source)
    source = type(source) == "table" and source or {}
    local spec = { allowImplicitProtected = false }
    local role = ReadOption(source, "role")
    local activeRole = ReadOption(source, "activeRole")
    local shape = ReadOption(source, "shape")
    if materialRoles[role] then spec.role = role end
    if materialRoles[activeRole] then spec.activeRole = activeRole end
    if shapes[shape] then spec.shape = shape end
    spec.inset = ClampOption(ReadOption(source, "inset"), -16, 32)
    spec.radius = ClampOption(ReadOption(source, "radius"), 4, 12)
    spec.border = ClampOption(ReadOption(source, "border"), 0, 2)
    spec.pillHeight = ClampOption(ReadOption(source, "pillHeight"), 20, 32)
    for index = 1, #specFlags do
        local key = specFlags[index]
        local value = ReadOption(source, key)
        if type(value) == "boolean" then spec[key] = value end
    end
    return spec
end

local function RuntimeEnabled()
    return PublicAPI.playerReady == true and NS.DB and NS.DB.enabled == true
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
    if target == nil then return false, "invalid-target" end
    local Safety = NS.Safety
    if Safety.IsForbidden(target) then return false, "protected-target" end
    local protected, explicit = Safety.GetProtection(target)
    if protected or explicit then return false, "protected-target" end
    if needsRegions and not Safety.CanCreateRegions(target, false) then
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
    return ControlSkin.GetOwner(target) or WindowActionSkin.GetOwner(target)
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
        target = target,
        pendingKey = "public-target:" .. scope.key .. ":" .. tostring(target),
        dependencies = WeakSet(),
    }
    scope.targets[target] = entry
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

local function EntryNeedsRegions(entry)
    return entry.surface ~= nil or entry.control ~= nil or entry.icon ~= nil
end

local function ValidateEntry(entry)
    local safe, reason = SafeTarget(entry.target, EntryNeedsRegions(entry))
    if not safe then return false, reason end
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

local function CleanupEntry(entry)
    local safe, reason = ValidateEntry(entry)
    if not safe then return false, reason end
    ControlSkin.DisableOwner(entry.owner)
    WindowActionSkin.DisableOwner(entry.owner)
    IconSkin.DisableOwner(entry.owner)
    Cosmetics.RestoreOwner(entry.owner)
    if Registry.GetSurface(entry.target) then
        NS.Surface.SetNativeStateSync(entry.target, false)
        NS.Surface.SetVisible(entry.target, false)
    end
    entry.applied = false
    return true
end

local function DropEntry(scope, target, entry)
    NS.CombatGate.Cancel(entry.pendingKey)
    if claims[target] == entry then claims[target] = nil end
    for dependency in pairs(entry.dependencies or {}) do
        if claims[dependency] == entry then claims[dependency] = nil end
    end
    scope.targets[target] = nil
end

local function ReleaseEntry(scope, target, entry)
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
    if control.kind == "windowAction" then
        local state, reason = WindowActionSkin.Apply(target, entry.owner, control.action)
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
    if cleaned or entry.applied ~= true then DropEntry(scope, target, entry) end
    return false, reason
end

local function ReconcileEntry(scope, target, entry)
    if scope.released or scope.client.released or scope.client.unregisterPending
        or entry.release then
        return ReleaseEntry(scope, target, entry)
    end
    local safe, reason = ValidateEntry(entry)
    if not safe then return FailEntry(scope, target, entry, reason) end
    if scope.suspended or not RuntimeEnabled() then
        local cleaned, cleanReason = CleanupEntry(entry)
        return cleaned, cleaned and "suspended" or cleanReason
    end

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
    entry.applied = true
    entry.appliedControl, entry.appliedFor = entry.control, settingsGeneration
    return true, "applied"
end

local function QueueEntry(scope, target, entry)
    if not PublicAPI.playerReady then return true, "pending" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(entry.pendingKey, function()
            ReconcileEntry(scope, target, entry)
        end)
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
    local control = entry.control
    if control and control.kind == "button" and entry.appliedControl == control
        and entry.applied == true and entry.appliedFor == settingsGeneration
        and not (entry.surface or entry.icon or entry.cosmetic) and entry.visible == nil
        and PublicAPI.playerReady and not NS.IsCombatLocked()
        and not scope.suspended and RuntimeEnabled()
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
