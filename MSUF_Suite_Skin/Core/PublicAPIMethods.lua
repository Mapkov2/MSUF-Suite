local _, NS = ...

-- The public API's facades (see PublicAPI.lua): the scope and client
-- methods callers use, the versioned API table, and the lifecycle hooks
-- that sync registered clients with the skin's state.
local PublicAPI = NS.PublicAPI
local API = PublicAPI.API
-- PublicAPI.lua's private state and helpers: taken off NS again, so no
-- other addon can reach the client registry or the entry functions through
-- _G.MapkoSkin.
local Shared = NS.PublicAPIShared
NS.PublicAPIShared = nil
local clients = Shared.clients
local clientRecords = Shared.clientRecords
local scopeRecords = Shared.scopeRecords
local WeakSet = Shared.WeakSet
local ReadOption = Shared.ReadOption
local SanitizeSpec = Shared.SanitizeSpec
local RuntimeEnabled = Shared.RuntimeEnabled
local SafeTarget = Shared.SafeTarget
local ResolveIconSpec = Shared.ResolveIconSpec
local TargetEntry = Shared.TargetEntry
local ClaimDependency = Shared.ClaimDependency
local CleanupEntry = Shared.CleanupEntry
local DropEntry = Shared.DropEntry
local ReconcileEntry = Shared.ReconcileEntry
local QueueEntry = Shared.QueueEntry
local SelectEntry = Shared.SelectEntry
local NextSettingsGeneration = Shared.NextSettingsGeneration
local HasMethod = NS.Safety.HasMethod

local listenerOwner = {}
local listenerActive = false

local ScopeMethods = {}
local ClientMethods = {}

local nineSlicePieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
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

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local windowActionSetters = {
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture",
}

local function ValidIdentifier(value)
    if type(value) ~= "string" or #value < 1 or #value > 64 then return false end
    if value:match("^%s") or value:match("%s$") then return false end
    return value:match("^[^:%c]+$") ~= nil
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
    return SelectEntry(scope, target, entry)
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
    return NS.Typography.GetSelectionPath(NS.Typography.GetSelection())
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
        integrationVersion = math.floor(NS.Clamp(
            ReadOption(options, "integrationVersion"), 1, 2147483647)),
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

-- Settings notifications arrive once per slider tick or colour-picker move,
-- and consumers repaint whole menus and modules on the signal: it goes out
-- once per frame for each distinct domain and key, after that frame's
-- writes, each signal its own error boundary.
local queuedSignals, queuedSignalKeys = {}, {}

local function EmitAppearanceSignals()
    local signals = queuedSignals
    queuedSignals, queuedSignalKeys = {}, {}
    for index = 1, #signals do
        local signal = signals[index]
        NS.Safety.Dispatch(API.OnAppearanceChanged, API, signal[1], signal[2])
    end
end

local function QueueAppearanceSignal(domain, key)
    local id = tostring(domain) .. "\31" .. tostring(key)
    if queuedSignalKeys[id] then return end
    queuedSignalKeys[id] = true
    queuedSignals[#queuedSignals + 1] = { domain, key }
    NS.Registry.QueueJob(EmitAppearanceSignals)
end

local function OnRegistryChanged(_, domain, key)
    -- First, so the client syncs below record the new settings.
    NextSettingsGeneration()
    if domain == "profile" or (domain == "adapter" and key == "master") then
        for _, record in pairs(clients) do QueueClientSync(record) end
    end
    QueueAppearanceSignal(domain, key)
end

function PublicAPI.Activate()
    if listenerActive then return end
    listenerActive = true
    NS.Registry.AddListener(listenerOwner, OnRegistryChanged)
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

return PublicAPI
