local _, NS = ...

-- Exact semantic HUD adapters, verified clean-room against
-- Gethe/wow-ui-source upstream/live at
-- 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4:
--
--   Blizzard_FrameXML/LossOfControlFrame.xml
--   Blizzard_CooldownViewer/CooldownViewer.lua
--   Blizzard_CooldownViewer/CooldownViewer.xml
--
-- Blizzard keeps ownership of layout, text, timers, cooldowns, status-bar
-- fills, pips, application counts, alert effects, animations and actions.
-- This adapter only replaces exact decorative backgrounds and the exact
-- anonymous Cooldown Manager icon-overlay atlas with reversible primitives.
local SemanticHUD = {
    owners = {},
    hooks = {},
    waitingForCooldownViewer = false,
    surfaceRecords = setmetatable({}, { __mode = "k" }),
}
NS.SemanticHUD = SemanticHUD

local Field = NS.Safety.Field
local Call = NS.Safety.Call

-- Exactly one boolean, also for a missing target (Field returns no value then).
local function HasMethod(target, name)
    return type(target) == "table" and type(target[name]) == "function"
end

local DEFAULT_OWNER = "blizzardWindows"
local COOLDOWN_ADDON = "Blizzard_CooldownViewer"
local ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local MAX_ACTIVE_ITEMS = 64
local MAX_OVERLAY_REGIONS = 16

local LOC_SURFACE_SPEC = {
    role = "popup",
    radius = 6,
    inset = 0,
    allowImplicitProtected = true,
}

local BAR_SURFACE_SPEC = {
    role = "status",
    shape = "continuous",
    radius = 3,
    inset = 0,
    allowImplicitProtected = true,
}

local viewerDefinitions = {
    { name = "BuffBarCooldownViewer", mixin = "BuffBarCooldownViewerMixin", kind = "bar" },
    { name = "BuffIconCooldownViewer", mixin = "BuffIconCooldownViewerMixin", kind = "icon" },
    { name = "EssentialCooldownViewer", mixin = "EssentialCooldownViewerMixin", kind = "icon" },
    { name = "UtilityCooldownViewer", mixin = "UtilityCooldownViewerMixin", kind = "icon" },
}

local lifecycleMethods = {
    "OnAcquireItemFrame",
    "RefreshLayout",
    "OnShow",
}

local function WeakMap()
    return setmetatable({}, { __mode = "k" })
end

local function CategoryEnabled()
    return NS.GenericWindows.IsCategoryEnabled("hud") ~= false
end

-- The Suite cooldown manager turns Blizzard's viewers off or runs them
-- invisibly; while it runs the viewers stay unstyled (Core/SuiteOwnership.lua).
-- Apply asks the Suite; the viewer hooks reuse that answer.
local function CooldownsOwned(ask)
    local ownership = NS.SuiteOwnership
    if not ownership then return false end
    if ask then return ownership.Owns("cooldownViewers") end
    return ownership.Owned("cooldownViewers")
end

local function OwnerState(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = SemanticHUD.owners[parentOwner]
    if not state then
        state = {
            parentOwner = parentOwner,
            skinOwner = tostring(parentOwner) .. ":semantic-hud",
            active = false,
            deferred = {},
            jobs = {},
            surfaces = WeakMap(),
        }
        SemanticHUD.owners[parentOwner] = state
    end
    return state, parentOwner
end

local function CosmeticOwnerAvailable(region, owner)
    if not NS.Safety.CanDecorate(region, true) then return false end
    local current = NS.Cosmetics.GetOwner(region)
    return current == nil or current == owner
end

local function FadeExact(region, owner)
    if not CosmeticOwnerAvailable(region, owner) then
        return false, "already owned"
    end
    local applied = NS.Cosmetics.Fade(region, owner)
    return applied == true, applied and "applied" or "native"
end

local function SurfaceOwnerAvailable(target, owner, spec)
    if not NS.Safety.CanCreateRegions(target, true) then
        return false
    end
    local existing = NS.Registry.GetSurface(target)
    if not existing then return true end
    local record = SemanticHUD.surfaceRecords[target]
    return record ~= nil
        and record.surface == existing
        and record.spec == spec
        and (record.owner == nil or record.owner == owner)
        and existing.spec == spec
end

local function AttachOwnedSurface(state, target, spec)
    if not state.active or NS.IsCombatLocked()
        or not SurfaceOwnerAvailable(target, state.skinOwner, spec) then
        return false, "already owned"
    end

    local existing = NS.Registry.GetSurface(target)
    if existing then
        -- SurfaceOwnerAvailable verified this is our released record.
        if NS.Surface.SetVisible(target, true) ~= true then
            return false, "protected"
        end
        SemanticHUD.surfaceRecords[target].owner = state.skinOwner
        state.surfaces[target] = existing
        return true, "restored"
    end

    local surface, reason = NS.Surface.Attach(target, spec)
    if not surface then return false, reason or "unsupported" end
    SemanticHUD.surfaceRecords[target] = {
        surface = surface,
        spec = spec,
        owner = state.skinOwner,
    }
    state.surfaces[target] = surface
    return true, "applied"
end

local function IsAnonymousOverlay(region)
    return Call(region, "GetObjectType") == "Texture"
        and Call(region, "GetName") == nil
        and Call(region, "GetAtlas") == ICON_OVERLAY_ATLAS
end

local function FirstOverlay(...)
    -- The exact Retail templates have only a handful of regions. Keep even
    -- this local exact search bounded so a foreign replacement cannot turn it
    -- into an unbounded traversal.
    for index = 1, math.min(select("#", ...), MAX_OVERLAY_REGIONS) do
        local region = select(index, ...)
        if IsAnonymousOverlay(region) then return region end
    end
    return nil
end

-- The overlay is a fixed template region of each pooled item frame.
local overlays = WeakMap()

local function FindIconOverlay(frame)
    if not frame then return nil end
    local overlay = overlays[frame]
    if not overlay then
        overlay = FirstOverlay(Call(frame, "GetRegions"))
        overlays[frame] = overlay
    end
    return overlay
end

local function ViewerDefinition(viewer)
    for index = 1, #viewerDefinitions do
        local definition = viewerDefinitions[index]
        if _G[definition.name] == viewer then return definition end
    end
    return nil
end

local function IconOwnerAvailable(button, owner, overlay)
    if not NS.Safety.CanCreateRegions(button, true) or not CosmeticOwnerAvailable(overlay, owner) then
        return false
    end
    local current = NS.IconSkin.GetOwner(button)
    return current == nil or current == owner
end

local function SkinExactIcon(state, button, icon, overlay)
    if not state.active or NS.IsCombatLocked()
        or not button or not icon or not overlay
        or not IconOwnerAvailable(button, state.skinOwner, overlay) then
        return false
    end
    return NS.IconSkin.Apply(button, state.skinOwner, {
        icon = icon,
        nativeBorder = overlay,
        allowImplicitProtected = true,
    }) ~= nil
end

local function SkinIconItem(state, item)
    return SkinExactIcon(state, item, Field(item, "Icon"), FindIconOverlay(item))
end

local function SkinBarItem(state, item)
    local iconFrame = Field(item, "Icon")
    local icon = Field(iconFrame, "Icon")
    local overlay = FindIconOverlay(iconFrame)
    local bar = Field(item, "Bar")
    local barBackground = Field(bar, "BarBG")
    if not iconFrame or not icon or not overlay or not bar or not barBackground then
        return false
    end

    -- Preflight all three ownership domains before mutating any of them.
    if not IconOwnerAvailable(iconFrame, state.skinOwner, overlay)
        or not SurfaceOwnerAvailable(bar, state.skinOwner, BAR_SURFACE_SPEC)
        or not CosmeticOwnerAvailable(barBackground, state.skinOwner) then
        return false
    end

    local iconApplied = SkinExactIcon(state, iconFrame, icon, overlay)
    local surfaceApplied = AttachOwnedSurface(state, bar, BAR_SURFACE_SPEC)
    local backgroundFaded = FadeExact(barBackground, state.skinOwner)
    return iconApplied or surfaceApplied == true or backgroundFaded == true
end

local function ApplyViewer(state, viewer)
    if not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled() then return true, "disabled" end

    local definition = ViewerDefinition(viewer)
    if not definition then return false, "foreign viewer" end
    local pool = Field(viewer, "itemFramePool")
    if not HasMethod(pool, "EnumerateActive") then return false, "missing pool" end

    local skinItem = definition.kind == "bar" and SkinBarItem or SkinIconItem
    local count, styled = 0, 0
    -- ObjectPoolMixin:EnumerateActive() returns object -> true. Only the
    -- object key is touched; the bound keeps a foreign pool walk finite.
    local iterator, invariant, control = pool:EnumerateActive()
    for _ = 1, MAX_ACTIVE_ITEMS do
        local item = iterator(invariant, control)
        if item == nil then break end
        control = item
        count = count + 1
        if skinItem(state, item) then styled = styled + 1 end
    end
    if count > 0 and styled == 0 then return false, "unsupported" end
    return true, styled > 0 and "applied" or "empty"
end

local function SkinLossOfControl(state)
    if not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled() then return true, "disabled" end

    local root = _G.LossOfControlFrame
    local background = Field(root, "blackBg")
    if not root or not background then return false, "missing" end

    -- Icon, Cooldown, RedLineTop, RedLineBottom, AbilityName, TimeLeft and Anim
    -- are intentionally never read by the styling path.
    if not SurfaceOwnerAvailable(root, state.skinOwner, LOC_SURFACE_SPEC)
        or not CosmeticOwnerAvailable(background, state.skinOwner) then
        return false, "already owned"
    end
    local attached = AttachOwnedSurface(state, root, LOC_SURFACE_SPEC)
    local faded = FadeExact(background, state.skinOwner)
    if attached == true and faded == true then
        return true, "applied"
    end
    return false, "failed"
end

local function RestoreVisuals(state)
    if NS.IsCombatLocked() then return false, "combat" end

    NS.IconSkin.DisableOwner(state.skinOwner)
    local remaining = WeakMap()
    local restored = true
    for target, surface in pairs(state.surfaces) do
        local record = SemanticHUD.surfaceRecords[target]
        if NS.Registry.GetSurface(target) == surface and record and record.surface == surface
            and record.owner == state.skinOwner then
            if NS.Surface.SetVisible(target, false) == true then
                record.owner = nil
            else
                remaining[target] = surface
                restored = false
            end
        end
    end
    state.surfaces = remaining
    NS.Cosmetics.RestoreOwner(state.skinOwner)
    return restored, restored and "restored" or "protected"
end

local function CancelDeferred(state)
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
end

-- Runs callback(state, argument) now, or once after combat. Each suffix maps
-- to one callback, so its combat job and key are built once per owner.
local function RunOrDefer(state, suffix, callback, argument)
    if not state.active then return false, "disabled" end
    if not NS.IsCombatLocked() then
        callback(state, argument)
        return true
    end
    local job = state.jobs[suffix]
    if not job then
        local key = "semantic-hud:" .. tostring(state.parentOwner) .. ":" .. tostring(suffix)
        job = { key = key }
        job.run = function()
            local current = SemanticHUD.owners[state.parentOwner]
            if current then current.deferred[key] = nil end
            if current and current.active then callback(current, argument) end
        end
        state.jobs[suffix] = job
    end
    state.deferred[job.key] = true
    return NS.CombatGate.RunOrDefer(job.key, job.run)
end

local function RequestViewerForOwners(viewer)
    if CooldownsOwned(false) then return end
    local definition = ViewerDefinition(viewer)
    if not definition then return end
    for _, state in pairs(SemanticHUD.owners) do
        if state.active then
            -- CombatGate coalesces repeated OnAcquire/RefreshLayout/OnShow
            -- signals per logical owner and exact viewer. ApplyViewer is the
            -- only place that may inspect the pool or mutate UI.
            RunOrDefer(state, definition.name, ApplyViewer, viewer)
        end
    end
end

local function RequestAllViewersForOwners()
    for index = 1, #viewerDefinitions do
        local viewer = _G[viewerDefinitions[index].name]
        if viewer then RequestViewerForOwners(viewer) end
    end
end

local function HookViewerMethod(definition, method)
    local key = definition.name .. ":" .. method
    if SemanticHUD.hooks[key] then return end

    local viewer = _G[definition.name]
    -- CreateFromMixins copies methods at every layer, and XML applies the
    -- finished concrete mixin to the already-created global frame. Hook the
    -- exact frame method that self:Method() resolves at runtime, while also
    -- requiring that the matching concrete Retail mixin exposes the contract.
    -- This avoids relying on later changes to CooldownViewerMixin propagating
    -- through either copy boundary.
    local viewerMethod = Field(viewer, method)
    if type(viewerMethod) ~= "function"
        or viewerMethod ~= Field(_G[definition.mixin], method) then
        return
    end
    hooksecurefunc(viewer, method, function(self)
        if self == viewer then RequestViewerForOwners(viewer) end
    end)
    SemanticHUD.hooks[key] = true
end

local function InstallCooldownHooks()
    -- Four exact viewers times three exact lifecycle methods: never more than
    -- twelve permanent, inert-when-disabled posthooks. In particular, the
    -- BuffBar OnAcquire hook targets its concrete override and therefore runs
    -- only after SetBarContent and SetBarWidth have completed.
    for definitionIndex = 1, #viewerDefinitions do
        local definition = viewerDefinitions[definitionIndex]
        for methodIndex = 1, #lifecycleMethods do
            HookViewerMethod(definition, lifecycleMethods[methodIndex])
        end
    end
end

local function CooldownViewerReady()
    for index = 1, #viewerDefinitions do
        local definition = viewerDefinitions[index]
        local viewer = _G[definition.name]
        local concreteMixin = _G[definition.mixin]
        if type(concreteMixin) ~= "table" then return false end
        for methodIndex = 1, #lifecycleMethods do
            local method = lifecycleMethods[methodIndex]
            if not HasMethod(viewer, method)
                or type(concreteMixin[method]) ~= "function" then
                return false
            end
        end
    end
    return true
end

local function CooldownViewerLoaded()
    return CooldownViewerReady() or NS.Client.IsAddOnLoaded(COOLDOWN_ADDON)
end

local function OnCooldownViewerLoaded()
    SemanticHUD.waitingForCooldownViewer = false
    InstallCooldownHooks()
    RequestAllViewersForOwners()
end

local function ScheduleCooldownViewer()
    if CooldownViewerLoaded() then
        OnCooldownViewerLoaded()
        return true
    end
    if SemanticHUD.waitingForCooldownViewer or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    SemanticHUD.waitingForCooldownViewer = true
    EventUtil.ContinueOnAddOnLoaded(COOLDOWN_ADDON, OnCooldownViewerLoaded)
    return true
end

local function ApplyState(state)
    if not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then
        return RunOrDefer(state, "apply", ApplyState)
    end
    if not CategoryEnabled() then
        RestoreVisuals(state)
        return true, "disabled"
    end

    local applied = SkinLossOfControl(state) == true and 1 or 0
    local waiting = false
    if CooldownsOwned(true) then
        applied = applied + 1 -- nothing to style: the Suite owns the viewers
    elseif CooldownViewerLoaded() then
        InstallCooldownHooks()
        for index = 1, #viewerDefinitions do
            local viewer = _G[viewerDefinitions[index].name]
            if viewer and ApplyViewer(state, viewer) then applied = applied + 1 end
        end
    else
        waiting = ScheduleCooldownViewer()
    end

    if applied > 0 and waiting then return true, "partial" end
    if applied > 0 then return true, "applied" end
    if waiting then return true, "waiting" end
    return false, "missing"
end

function SemanticHUD.Apply(parentOwner)
    local state = OwnerState(parentOwner)
    CancelDeferred(state)
    state.active = true
    return ApplyState(state)
end

function SemanticHUD.Refresh(parentOwner)
    local state = SemanticHUD.owners[parentOwner or DEFAULT_OWNER]
    if not state or not state.active then return false, "disabled" end
    return ApplyState(state)
end

local function DisableNow(state)
    state.active = false
    CancelDeferred(state)
    local restored, reason = RestoreVisuals(state)
    if not restored then return false, reason end
    if SemanticHUD.owners[state.parentOwner] == state then
        SemanticHUD.owners[state.parentOwner] = nil
    end
    return true
end

function SemanticHUD.Disable(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = SemanticHUD.owners[parentOwner]
    if not state then return true end

    CancelDeferred(state)
    state.active = false
    if not NS.IsCombatLocked() then
        return DisableNow(state)
    end
    local key = "semantic-hud:" .. parentOwner .. ":disable"
    state.deferred[key] = true
    return NS.CombatGate.RunOrDefer(key, function()
        local current = SemanticHUD.owners[parentOwner]
        if current then current.deferred[key] = nil end
        if current and not current.active then DisableNow(current) end
    end)
end

return SemanticHUD
