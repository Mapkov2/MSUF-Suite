local _, NS = ...

-- Versioned public integration API.  External addons explicitly submit only
-- their own visual targets; MapkoSkin never executes their callbacks,
-- traverses their frame trees, or exposes internal owner/state tables.
local PublicAPI = {
    major = NS.publicAPIMajor or 2,
    minor = NS.publicAPIMinor or 0,
    databaseReady = false,
    playerReady = false,
}
NS.PublicAPI = PublicAPI

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
local listenerOwner = {}
local listenerActive = false

local ScopeMethods = {}
local ClientMethods = {}

local nineSlicePieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local materialRoles = {
    shell = true, panel = true, card = true, popup = true, input = true,
    button = true, buttonPrimary = true, navigation = true,
    buttonDanger = true, buttonSuccess = true,
    navigationActive = true, status = true,
}

local shapes = {
    pill = true, round = true, continuous = true, squircle = true,
}

local capabilities = {
    windowActions = true,
    appearanceSignal = true,
    combatCoalescing = true,
    cosmetics = true,
    defensiveThemeReads = true,
    icons = true,
    reversibleControls = true,
    surfaces = true,
}

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function Clamp(value, minimum, maximum)
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

local specFlags = { "active", "forceEdge", "listItem", "slice", "useControlShape" }
local windowActionSetters = {
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture",
}

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
    spec.inset = Clamp(ReadOption(source, "inset"), -16, 32)
    spec.radius = Clamp(ReadOption(source, "radius"), 4, 12)
    spec.border = Clamp(ReadOption(source, "border"), 0, 2)
    spec.pillHeight = Clamp(ReadOption(source, "pillHeight"), 20, 32)
    for index = 1, #specFlags do
        local key = specFlags[index]
        local value = ReadOption(source, key)
        if type(value) == "boolean" then spec[key] = value end
    end
    return spec
end

local function ValidIdentifier(value)
    if type(value) ~= "string" or #value < 1 or #value > 64 then return false end
    if value:match("^%s") or value:match("%s$") then return false end
    return value:match("^[^:%c]+$") ~= nil
end

local function RuntimeEnabled()
    return PublicAPI.playerReady == true and NS.DB and NS.DB.enabled == true
end

local function GetScope(facade)
    local scope = scopeRecords[facade]
    if not scope or scope.released or scope.client.released
        or scope.client.unregisterPending then
        return nil, "released"
    end
    return scope
end

local function GetClient(facade)
    local record = clientRecords[facade]
    if not record or record.released or record.unregisterPending then
        return nil, "released"
    end
    return record
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

local function HasMethod(target, key)
    return type(ReadMember(target, key)) == "function"
end

local function IsDescendant(target, region)
    local current = region
    for _ = 1, 8 do
        local parent = NS.Safety.Call(current, "GetParent")
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
    local owner = NS.ControlSkin and NS.ControlSkin.GetOwner
        and NS.ControlSkin.GetOwner(target)
    if owner then return owner end
    owner = NS.WindowActionSkin and NS.WindowActionSkin.GetOwner and NS.WindowActionSkin.GetOwner(target)
    if owner then return owner end
    owner = NS.IconSkin and NS.IconSkin.GetOwner and NS.IconSkin.GetOwner(target)
    if owner then return owner end
    return NS.Cosmetics and NS.Cosmetics.GetOwner and NS.Cosmetics.GetOwner(target)
end

local function NewScope(client, key)
    local facade = setmetatable({}, { __index = ScopeMethods })
    local scope = {
        client = client,
        facade = facade,
        key = key,
        targets = WeakSet(),
        pendingKey = "public-scope:" .. key,
        releaseEpoch = 0,
        suspended = false,
        released = false,
    }
    scopeRecords[facade] = scope
    return scope
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
    local surface = NS.Registry and NS.Registry.GetSurface(target)
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
    if NS.ControlSkin then NS.ControlSkin.DisableOwner(entry.owner) end
    if NS.WindowActionSkin then NS.WindowActionSkin.DisableOwner(entry.owner) end
    if NS.IconSkin then NS.IconSkin.DisableOwner(entry.owner) end
    if NS.Cosmetics then NS.Cosmetics.RestoreOwner(entry.owner) end
    if NS.Registry and NS.Registry.GetSurface(entry.target) then
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
        local state, reason = NS.WindowActionSkin.Apply(target, entry.owner, control.action)
        return state ~= nil, reason
    elseif control.kind == "button" then
        method = NS.ControlSkin and NS.ControlSkin.ApplyButton
    elseif control.kind == "threeSlice" then
        method = NS.ControlSkin and NS.ControlSkin.ApplyThreeSliceButton
    elseif control.kind == "tab" then
        method = NS.ControlSkin and NS.ControlSkin.ApplyTab
    elseif control.kind == "searchBox" then
        method = NS.ControlSkin and NS.ControlSkin.ApplySearchBox
    end
    if type(method) ~= "function" then return false, "unsupported-control" end
    local state, reason = method(target, entry.owner, control.spec)
    if not state then return false, reason or "unsupported-control" end
    return true
end

local function ApplyCosmetic(target, entry)
    if not entry.cosmetic then return true end
    local applied
    if entry.cosmetic == "alpha" then
        applied = NS.Cosmetics and NS.Cosmetics.Fade(target, entry.owner)
    elseif entry.cosmetic == "vertex" then
        applied = NS.Cosmetics and NS.Cosmetics.SuppressVertexAlpha(target, entry.owner)
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
        state, reason = NS.IconSkin.Apply(target, entry.owner, entry.icon)
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

local function RequestVisual(facade, target, aspect, value, needsRegions)
    local scope, reason = GetScope(facade)
    if not scope then return false, reason end
    local entry
    entry, reason = TargetEntry(scope, target, needsRegions)
    if not entry then return false, reason end
    if aspect == "surface" and entry.control then return false, "kind-conflict" end
    if aspect == "control" and entry.surface then return false, "kind-conflict" end
    if aspect == "control" and entry.control and entry.control.kind ~= value.kind
        and (entry.control.kind == "windowAction" or value.kind == "windowAction") then
        return false, "kind-conflict"
    end
    entry.release = nil
    entry.keepEpoch = scope.releaseEpoch
    entry[aspect] = value
    return QueueEntry(scope, target, entry)
end

function ScopeMethods:SkinFrame(frame, options)
    local safe, reason = SafeTarget(frame, true)
    if not safe then return false, reason end
    if not HasMethod(frame, "CreateTexture") then return false, "unsupported-frame" end
    return RequestVisual(self, frame, "surface", SanitizeSpec(options), true)
end

function ScopeMethods:SkinButton(button, options)
    local safe, reason = SafeTarget(button, true)
    if not safe then return false, reason end
    if not HasMethod(button, "SetHighlightTexture")
        or not HasMethod(button, "SetPushedTexture") then
        return false, "unsupported-control"
    end
    local spec = SanitizeSpec(options)
    local scope = GetScope(self)
    -- MSUF's sidebar uses the ordinary dark menu selection. Normalize older
    -- MSUF callers too, so a separately installed frame addon cannot bring
    -- back the bright blue navigation material.
    if scope and scope.client.name == "MidnightSimpleUnitFrames"
        and spec.role == "navigation" and spec.listItem == true then
        spec.activeRole = "button"
    end
    return RequestVisual(self, button, "control", {
        kind = "button", spec = spec,
    }, true)
end

-- Explicit role for authored addon buttons; never guess from names or scripts.
function ScopeMethods:SkinWindowAction(button, kind)
    local safe, reason = SafeTarget(button, true)
    if not safe then return false, reason end
    if kind ~= "close" and kind ~= "minimize" and kind ~= "maximize"
        and kind ~= "expand" and kind ~= "collapse" then return false, "invalid-action" end
    for index = 1, #windowActionSetters do
        if not HasMethod(button, windowActionSetters[index]) then return false, "unsupported-control" end
    end
    return RequestVisual(self, button, "control", { kind = "windowAction", action = kind }, true)
end

function ScopeMethods:SkinThreeSliceButton(button, options)
    local safe, reason = SafeTarget(button, true)
    if not safe then return false, reason end
    if not HasMethod(button, "SetHighlightTexture")
        or not HasMethod(button, "SetPushedTexture") then
        return false, "unsupported-control"
    end
    return RequestVisual(self, button, "control", {
        kind = "threeSlice", spec = SanitizeSpec(options),
    }, true)
end

function ScopeMethods:SkinTab(tab, options)
    local safe, reason = SafeTarget(tab, true)
    if not safe then return false, reason end
    if not HasMethod(tab, "SetHighlightTexture")
        or not HasMethod(tab, "SetPushedTexture") then
        return false, "unsupported-control"
    end
    return RequestVisual(self, tab, "control", {
        kind = "tab", spec = SanitizeSpec(options),
    }, true)
end

function ScopeMethods:SkinSearchBox(searchBox, options)
    local safe, reason = SafeTarget(searchBox, true)
    if not safe then return false, reason end
    if not HasMethod(searchBox, "CreateTexture") then return false, "unsupported-control" end
    return RequestVisual(self, searchBox, "control", {
        kind = "searchBox", spec = SanitizeSpec(options),
    }, true)
end

function ScopeMethods:SkinIcon(button, options)
    local safe, reason = SafeTarget(button, true)
    if not safe then return false, reason end
    if not HasMethod(button, "CreateTexture") then return false, "unsupported-icon" end
    local spec
    spec, reason = ResolveIconSpec(button, options)
    if not spec then return false, reason end
    local scope
    scope, reason = GetScope(self)
    if not scope then return false, reason end
    local existing = scope.targets[button]
    local entry
    entry, reason = TargetEntry(scope, button, true)
    if not entry then return false, reason end
    local claimed
    claimed, reason = ClaimDependency(entry, spec.nativeBorder)
    if not claimed then
        if not existing then DropEntry(scope, button, entry) end
        return false, reason
    end
    entry.release = nil
    entry.keepEpoch = scope.releaseEpoch
    entry.icon = spec
    return QueueEntry(scope, button, entry)
end

function ScopeMethods:Fade(region)
    local safe, reason = SafeTarget(region, false)
    if not safe then return false, reason end
    if not HasMethod(region, "SetAlpha") or not HasMethod(region, "GetAlpha") then
        return false, "unsupported-region"
    end
    return RequestVisual(self, region, "cosmetic", "alpha", false)
end

function ScopeMethods:SuppressVertexAlpha(region)
    local safe, reason = SafeTarget(region, false)
    if not safe then return false, reason end
    if not HasMethod(region, "SetVertexColor") or not HasMethod(region, "GetVertexColor") then
        return false, "unsupported-region"
    end
    return RequestVisual(self, region, "cosmetic", "vertex", false)
end

function ScopeMethods:FadeNineSlice(nineSlice)
    if type(nineSlice) ~= "table" then return false, "invalid-target" end
    local result, reason = true, "applied"
    for index = 1, #nineSlicePieces do
        local region = ReadOption(nineSlice, nineSlicePieces[index])
        if region then
            local applied, detail = self:Fade(region)
            if not applied then result, reason = false, detail end
        end
    end
    return result, reason
end

function ScopeMethods:SetActive(target, active)
    local scope, reason = GetScope(self)
    if not scope then return false, reason end
    local entry = scope.targets[target]
    if not entry or (not entry.surface and not entry.control) then
        return false, "unknown-target"
    end
    entry.release = nil
    entry.keepEpoch = scope.releaseEpoch
    entry.active = active == true
    return QueueEntry(scope, target, entry)
end

function ScopeMethods:SetVisible(target, visible)
    local scope, reason = GetScope(self)
    if not scope then return false, reason end
    local entry = scope.targets[target]
    if not entry or (not entry.surface and not entry.control) then
        return false, "unknown-target"
    end
    entry.release = nil
    entry.keepEpoch = scope.releaseEpoch
    entry.visible = visible == true
    return QueueEntry(scope, target, entry)
end

function ScopeMethods:Refresh(target)
    local scope, reason = GetScope(self)
    if not scope then return false, reason end
    local entry = scope.targets[target]
    if not entry then return false, "unknown-target" end
    entry.release = nil
    entry.keepEpoch = scope.releaseEpoch
    return QueueEntry(scope, target, entry)
end

function ScopeMethods:Release(target)
    local scope, reason = GetScope(self)
    if not scope then return false, reason end
    local entry = scope.targets[target]
    if not entry then return false, "unknown-target" end
    entry.release = true
    entry.keepEpoch = nil
    return QueueEntry(scope, target, entry)
end

local function RunScopeOperation(scope)
    local operation = scope.pendingOperation
    local epoch = scope.pendingEpoch
    scope.pendingOperation = nil
    scope.pendingEpoch = nil
    local targets = {}
    for target in pairs(scope.targets) do targets[#targets + 1] = target end
    local success, reason = true, operation == "release" and "released" or "applied"
    for index = 1, #targets do
        local target = targets[index]
        local entry = scope.targets[target]
        if entry then
            if operation == "release" and entry.keepEpoch ~= epoch then entry.release = true end
            local applied, detail = ReconcileEntry(scope, target, entry)
            if not applied then success, reason = false, detail end
        end
    end
    return success, reason
end

local function QueueScopeOperation(scope, operation)
    if operation == "release" then
        scope.releaseEpoch = scope.releaseEpoch + 1
        scope.pendingEpoch = scope.releaseEpoch
    end
    scope.pendingOperation = operation
    if not PublicAPI.playerReady then return true, "pending" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(scope.pendingKey, function()
            RunScopeOperation(scope)
        end)
        return true, "deferred"
    end
    local applied, reason = RunScopeOperation(scope)
    return applied == true, reason
end

function ScopeMethods:RefreshAll()
    local scope, reason = GetScope(self)
    if not scope then return false, reason end
    return QueueScopeOperation(scope, "refresh")
end

function ScopeMethods:ReleaseAll()
    local scope, reason = GetScope(self)
    if not scope then return false, reason end
    return QueueScopeOperation(scope, "release")
end

function ScopeMethods:GetColor(token)
    return NS.Theme.GetColor(token)
end

function ScopeMethods:GetFont()
    if not NS.Typography then return nil end
    local selection = NS.Typography.GetSelection and NS.Typography.GetSelection()
    return NS.Typography.GetSelectionPath and NS.Typography.GetSelectionPath(selection) or nil
end

function ScopeMethods:GetLook()
    return NS.DB and NS.DB.theme and NS.DB.theme.look or "midnight"
end

function ScopeMethods:GetAppearance(key)
    local value = NS.DB and NS.DB.theme and NS.DB.theme[key]
    return type(value) ~= "table" and value or nil
end

function ScopeMethods:IsEnabled()
    return RuntimeEnabled()
end

function ScopeMethods:IsReady()
    return PublicAPI.playerReady == true
end

local function SuspendScopeNow(scope)
    scope.suspended = true
    for _, entry in pairs(scope.targets) do CleanupEntry(entry) end
end

local function ResumeScopeNow(scope)
    scope.suspended = false
    local targets = {}
    for target in pairs(scope.targets) do targets[#targets + 1] = target end
    for index = 1, #targets do
        local target = targets[index]
        local entry = scope.targets[target]
        if entry then ReconcileEntry(scope, target, entry) end
    end
end

local function UnregisterClientNow(record)
    record.mainScope.suspended = false
    record.mainScope.pendingOperation = "release"
    local released, reason = RunScopeOperation(record.mainScope)
    if not released then
        -- Keep the client reachable when a target became unsafe after it was
        -- accepted.  Dropping the owner here would strand native state that
        -- could not be restored fail-closed; the caller can retry once safe.
        record.unregisterPending = false
        return false, reason
    end
    record.mainScope.released = true
    record.released = true
    record.unregisterPending = false
    clients[record.name] = nil
    NS.CombatGate.Cancel(record.mainScope.pendingKey)
    return true, "unregistered"
end

function ClientMethods:GetName()
    local record = clientRecords[self]
    return record and record.name or nil
end

function ClientMethods:Unregister()
    local record, reason = GetClient(self)
    if not record then return false, reason end
    record.unregisterPending = true
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("public-client:" .. record.name, function()
            UnregisterClientNow(record)
        end)
        return true, "deferred"
    end
    local unregistered, detail = UnregisterClientNow(record)
    return unregistered == true, detail
end

for name, method in pairs(ScopeMethods) do ClientMethods[name] = method end

local function NewClient(name, options)
    local facade = setmetatable({}, { __index = ClientMethods })
    local record = {
        facade = facade,
        integrationVersion = math.floor(Clamp(
            ReadOption(options, "integrationVersion"), 1, 2147483647) or 1),
        name = name,
    }
    record.mainScope = NewScope(record, name .. ":main")
    clientRecords[facade] = record
    scopeRecords[facade] = record.mainScope
    clients[name] = record
    return record
end

function API:RegisterAddon(name, options)
    if self ~= API then options, name = name, self end
    if not ValidIdentifier(name) then return nil, "invalid-addon" end
    if options ~= nil and type(options) ~= "table" then return nil, "invalid-options" end
    if clients[name] and not clients[name].released then return nil, "already-registered" end
    local record = NewClient(name, options)
    return record.facade, PublicAPI.playerReady and "registered" or "pending"
end

function API:GetRegisteredAddons()
    local result = {}
    for name, record in pairs(clients) do
        if not record.released then
            result[#result + 1] = {
                name = name,
                integrationVersion = record.integrationVersion,
            }
        end
    end
    table.sort(result, function(left, right) return left.name < right.name end)
    return result
end

function API:GetCapabilities()
    return CopyTable(capabilities)
end

function API:HasCapability(name)
    return capabilities[name] == true
end

function API:GetVersion()
    return NS.version, PublicAPI.major, PublicAPI.minor
end

function API:IsReady()
    return PublicAPI.playerReady == true
end

function API:IsEnabled()
    return RuntimeEnabled()
end

function API:GetColor(token)
    return NS.Theme.GetColor(token)
end

function API:GetFont()
    return ScopeMethods.GetFont(API)
end

function API:GetLook()
    return NS.DB and NS.DB.theme and NS.DB.theme.look or "midnight"
end

function API:GetAppearance(key)
    local value = NS.DB and NS.DB.theme and NS.DB.theme[key]
    return type(value) ~= "table" and value or nil
end

function API:GetAppearanceSnapshot()
    local theme = NS.DB and NS.DB.theme or {}
    local geometry = NS.DB and NS.DB.geometry or {}
    return {
        gradient = theme.gradient,
        gradientDirection = theme.gradientDirection,
        gradientStrength = theme.gradientStrength,
        shellOpacity = theme.shellOpacity,
        panelOpacity = theme.panelOpacity,
        controlOpacity = theme.controlOpacity,
        borderOpacity = theme.borderOpacity,
        materialDepth = theme.materialDepth,
        hoverStyle = theme.hoverStyle,
        hoverIntensity = theme.hoverIntensity,
        iconBorderStyle = theme.iconBorderStyle,
        windowActionStyle = (NS.DB and NS.DB.icons and NS.DB.icons.windowActions or NS.Defaults.icons.windowActions).style,
        geometry = {
            family = geometry.family,
            radius = geometry.radius,
            border = geometry.border,
            controlShape = geometry.controlShape,
        },
    }
end

-- Read-only lifecycle signal for cooperative renderers. No caller callback is
-- accepted or retained. Consumers may secure-post-hook this method; they must
-- not replace it. Signals run after reconciliation and never from a hot path.
function API:OnAppearanceChanged() end

local function SyncClientNow(record)
    if record.released or record.unregisterPending then return end
    if record.mainScope.pendingOperation then
        RunScopeOperation(record.mainScope)
    elseif RuntimeEnabled() then
        ResumeScopeNow(record.mainScope)
    else
        SuspendScopeNow(record.mainScope)
    end
end

local function QueueClientSync(record)
    if not NS.IsCombatLocked() then
        SyncClientNow(record)
        return true
    end
    return NS.CombatGate.RunOrDefer("public-client-sync:" .. record.name, function()
        SyncClientNow(record)
    end)
end

local function OnRegistryChanged(_, domain, key)
    if domain == "profile" or (domain == "adapter" and key == "master") then
        for _, record in pairs(clients) do QueueClientSync(record) end
    end
    API:OnAppearanceChanged(domain, key)
end

function PublicAPI.Activate()
    if listenerActive then return end
    listenerActive = true
    NS.Registry.AddListener(listenerOwner, OnRegistryChanged)
    if NS.DB then PublicAPI.OnDatabaseReady() end
end

function PublicAPI.OnDatabaseReady()
    PublicAPI.databaseReady = true
end

function PublicAPI.OnPlayerLogin()
    PublicAPI.databaseReady = true
    PublicAPI.playerReady = true
    for _, record in pairs(clients) do QueueClientSync(record) end
    API:OnAppearanceChanged("ready")
end

local function RefreshAllNow()
    for _, record in pairs(clients) do
        record.mainScope.suspended = not RuntimeEnabled()
        QueueScopeOperation(record.mainScope, "refresh")
    end
end

function PublicAPI.RefreshAll()
    if not PublicAPI.playerReady then return false, "pending" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("public:refresh-all", RefreshAllNow)
        return true, "deferred"
    end
    RefreshAllNow()
    return true, "applied"
end

function PublicAPI.GetCount()
    local count = 0
    for _, record in pairs(clients) do
        if not record.released then count = count + 1 end
    end
    return count
end

return PublicAPI
