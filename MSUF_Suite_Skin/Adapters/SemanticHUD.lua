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
    hookCount = 0,
    waitingForCooldownViewer = false,
    surfaceRecords = setmetatable({}, { __mode = "k" }),
}
NS.SemanticHUD = SemanticHUD

local DEFAULT_OWNER = "blizzardWindows"
local COOLDOWN_ADDON = "Blizzard_CooldownViewer"
local ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local MAX_ACTIVE_ITEMS = 64

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
    {
        name = "BuffBarCooldownViewer",
        mixin = "BuffBarCooldownViewerMixin",
        kind = "bar",
    },
    {
        name = "BuffIconCooldownViewer",
        mixin = "BuffIconCooldownViewerMixin",
        kind = "icon",
    },
    {
        name = "EssentialCooldownViewer",
        mixin = "EssentialCooldownViewerMixin",
        kind = "icon",
    },
    {
        name = "UtilityCooldownViewer",
        mixin = "UtilityCooldownViewerMixin",
        kind = "icon",
    },
}

local lifecycleMethods = {
    "OnAcquireItemFrame",
    "RefreshLayout",
    "OnShow",
}

local function WeakMap()
    return setmetatable({}, { __mode = "k" })
end

-- Pass the operands through pcall; do not allocate a capturing closure per read.
local function IndexMember(object, key)
    return object[key]
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(IndexMember, object, key)
    return ok and value or nil
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("semantic HUD " .. tostring(label), message)
    end
end

local function IsCombatLocked()
    return type(NS.IsCombatLocked) == "function" and NS.IsCombatLocked() == true
end

local function CategoryEnabled()
    local generic = NS.GenericWindows
    if generic and type(generic.IsCategoryEnabled) == "function" then
        local ok, enabled = pcall(generic.IsCategoryEnabled, "hud")
        return ok and enabled ~= false
    end
    return true
end

local function IsLoaded(addon)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
        return ok and (loaded == true or (loaded == nil and loadedOrLoading == true))
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, addon)
        return ok and loaded == true
    end
    return false
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
            surfaces = WeakMap(),
        }
        SemanticHUD.owners[parentOwner] = state
    end
    return state, parentOwner
end

local function CanCreateRegions(target)
    return target and NS.Safety
        and type(NS.Safety.CanCreateRegions) == "function"
        and NS.Safety.CanCreateRegions(target, true)
end

local function CanDecorate(target)
    return target and NS.Safety
        and type(NS.Safety.CanDecorate) == "function"
        and NS.Safety.CanDecorate(target, true)
end

local function CosmeticOwnerAvailable(region, owner)
    if not CanDecorate(region) or not NS.Cosmetics then return false end
    local getter = SafeField(NS.Cosmetics, "GetOwner")
    if type(getter) ~= "function" then return false end
    local ok, current = pcall(getter, region)
    return ok and (current == nil or current == owner)
end

local function FadeExact(region, owner)
    if not CosmeticOwnerAvailable(region, owner)
        or type(SafeField(NS.Cosmetics, "Fade")) ~= "function" then
        return false, "already owned"
    end
    local ok, applied = pcall(NS.Cosmetics.Fade, region, owner)
    if not ok then
        Report("fade", applied)
        return false, "failed"
    end
    return applied == true, applied and "applied" or "native"
end

local function SurfaceOwnerAvailable(target, owner, spec)
    if not CanCreateRegions(target) or not NS.Registry
        or type(SafeField(NS.Registry, "GetSurface")) ~= "function" then
        return false
    end
    local ok, existing = pcall(NS.Registry.GetSurface, target)
    if not ok then return false end
    if not existing then return true end
    local record = SemanticHUD.surfaceRecords[target]
    return record ~= nil
        and record.surface == existing
        and record.spec == spec
        and (record.owner == nil or record.owner == owner)
        and SafeField(existing, "spec") == spec
end

local function AttachOwnedSurface(state, target, spec)
    if not state or not state.active or IsCombatLocked()
        or not SurfaceOwnerAvailable(target, state.skinOwner, spec)
        or not NS.Surface or type(SafeField(NS.Surface, "Attach")) ~= "function" then
        return false, "already owned"
    end

    local existing = NS.Registry.GetSurface(target)
    local record = SemanticHUD.surfaceRecords[target]
    if existing then
        if not record or record.surface ~= existing or record.spec ~= spec
            or (record.owner and record.owner ~= state.skinOwner) then
            return false, "already owned"
        end
        if type(SafeField(NS.Surface, "SetVisible")) ~= "function" then
            return false, "unavailable"
        end
        local ok, visible = pcall(NS.Surface.SetVisible, target, true)
        if not ok or visible ~= true then
            if not ok then Report("surface restore", visible) end
            return false, "protected"
        end
        record.owner = state.skinOwner
        state.surfaces[target] = existing
        return true, "restored"
    end

    local ok, surface, reason = pcall(NS.Surface.Attach, target, spec)
    if not ok then
        Report("surface", surface)
        return false, "failed"
    end
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
    if not region then return false end
    local getObjectType = SafeField(region, "GetObjectType")
    local getName = SafeField(region, "GetName")
    local getAtlas = SafeField(region, "GetAtlas")
    if type(getObjectType) ~= "function" or type(getName) ~= "function"
        or type(getAtlas) ~= "function" then
        return false
    end

    local typeOK, objectType = pcall(getObjectType, region)
    local nameOK, name = pcall(getName, region)
    local atlasOK, atlas = pcall(getAtlas, region)
    return typeOK and objectType == "Texture"
        and nameOK and name == nil
        and atlasOK and atlas == ICON_OVERLAY_ATLAS
end

local function FindIconOverlay(frame)
    local getRegions = SafeField(frame, "GetRegions")
    if type(getRegions) ~= "function" then return nil end
    local ok, regions = pcall(function() return { getRegions(frame) } end)
    if not ok then return nil end

    -- The exact Retail templates have only a handful of regions. Keep even
    -- this local exact search bounded so a foreign replacement cannot turn it
    -- into an unbounded traversal.
    local count = math.min(#regions, 16)
    for index = 1, count do
        if IsAnonymousOverlay(regions[index]) then return regions[index] end
    end
    return nil
end

local function ViewerDefinition(viewer)
    for index = 1, #viewerDefinitions do
        local definition = viewerDefinitions[index]
        if _G[definition.name] == viewer then return definition end
    end
    return nil
end

local function IconOwnerAvailable(button, owner, overlay)
    if not CanCreateRegions(button) or not CosmeticOwnerAvailable(overlay, owner)
        or not NS.IconSkin then
        return false
    end
    local getter = SafeField(NS.IconSkin, "GetOwner")
    if type(getter) ~= "function" then return false end
    local ok, current = pcall(getter, button)
    return ok and (current == nil or current == owner)
end

local function SkinExactIcon(state, button, icon, overlay)
    if not state or not state.active or IsCombatLocked()
        or not button or not icon or not overlay
        or not IconOwnerAvailable(button, state.skinOwner, overlay)
        or type(SafeField(NS.IconSkin, "Apply")) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.IconSkin.Apply, button, state.skinOwner, {
        icon = icon,
        nativeBorder = overlay,
        allowImplicitProtected = true,
    })
    if not ok then Report("icon", applied) end
    return ok and applied ~= nil
end

local function SkinIconItem(state, item)
    local icon = SafeField(item, "Icon")
    local overlay = FindIconOverlay(item)
    return SkinExactIcon(state, item, icon, overlay)
end

local function SkinBarItem(state, item)
    local iconFrame = SafeField(item, "Icon")
    local icon = SafeField(iconFrame, "Icon")
    local overlay = FindIconOverlay(iconFrame)
    local bar = SafeField(item, "Bar")
    local barBackground = SafeField(bar, "BarBG")
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

local function EnumerateActiveItems(viewer, callback)
    local pool = SafeField(viewer, "itemFramePool")
    local enumerate = SafeField(pool, "EnumerateActive")
    if type(enumerate) ~= "function" or type(callback) ~= "function" then
        return false, 0
    end

    local ok, iterator, invariant, control = pcall(enumerate, pool)
    if not ok or type(iterator) ~= "function" then return false, 0 end
    local count = 0
    for _ = 1, MAX_ACTIVE_ITEMS do
        local iterOK, item = pcall(iterator, invariant, control)
        if not iterOK or item == nil then break end
        control = item
        count = count + 1
        callback(item)
    end
    return true, count
end

local function ApplyViewer(state, viewer)
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled() then return true, "disabled" end

    local definition = ViewerDefinition(viewer)
    if not definition then return false, "foreign viewer" end
    local styled = 0
    local enumerated, count = EnumerateActiveItems(viewer, function(item)
        local applied
        if definition.kind == "bar" then
            applied = SkinBarItem(state, item)
        else
            applied = SkinIconItem(state, item)
        end
        if applied then styled = styled + 1 end
    end)
    if not enumerated then return false, "missing pool" end
    if count > 0 and styled == 0 then return false, "unsupported" end
    return true, styled > 0 and "applied" or "empty"
end

local function SkinLossOfControl(state)
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled() then return true, "disabled" end

    local root = _G.LossOfControlFrame
    local background = SafeField(root, "blackBg")
    if not root or not background then return false, "missing" end

    -- Icon, Cooldown, RedLineTop, RedLineBottom, AbilityName, TimeLeft and Anim
    -- are intentionally never read by the styling path.
    if not SurfaceOwnerAvailable(root, state.skinOwner, LOC_SURFACE_SPEC)
        or not CosmeticOwnerAvailable(background, state.skinOwner) then
        return false, "already owned"
    end
    local attached = AttachOwnedSurface(state, root, LOC_SURFACE_SPEC)
    local faded = FadeExact(background, state.skinOwner)
    return attached == true and faded == true,
        attached == true and faded == true and "applied" or "failed"
end

local function RestoreVisuals(state)
    if not state or IsCombatLocked() then return false, "combat" end

    local restored = true

    if NS.IconSkin and type(SafeField(NS.IconSkin, "DisableOwner")) == "function" then
        pcall(NS.IconSkin.DisableOwner, state.skinOwner)
    end
    if NS.Surface and type(SafeField(NS.Surface, "SetVisible")) == "function"
        and NS.Registry and type(SafeField(NS.Registry, "GetSurface")) == "function" then
        local remaining = WeakMap()
        for target, surface in pairs(state.surfaces) do
            local record = SemanticHUD.surfaceRecords[target]
            local ok, current = pcall(NS.Registry.GetSurface, target)
            if ok and current == surface and record and record.surface == surface
                and record.owner == state.skinOwner then
                local hiddenOK, hidden = pcall(NS.Surface.SetVisible, target, false)
                if hiddenOK and hidden == true then
                    record.owner = nil
                else
                    remaining[target] = surface
                    restored = false
                    if not hiddenOK then Report("surface restore", hidden) end
                end
            end
        end
        state.surfaces = remaining
    end
    if NS.Cosmetics and type(SafeField(NS.Cosmetics, "RestoreOwner")) == "function" then
        pcall(NS.Cosmetics.RestoreOwner, state.skinOwner)
    end
    if restored then state.surfaces = WeakMap() end
    return restored, restored and "restored" or "protected"
end

local function DeferredKey(state, suffix)
    return "semantic-hud:" .. tostring(state.parentOwner) .. ":" .. tostring(suffix)
end

local function CancelDeferred(state)
    if not state then return end
    for key in pairs(state.deferred) do
        if NS.CombatGate and type(SafeField(NS.CombatGate, "Cancel")) == "function" then
            pcall(NS.CombatGate.Cancel, key)
        end
        state.deferred[key] = nil
    end
end

local function RunOrDefer(state, suffix, callback)
    if not state or not state.active or not NS.CombatGate
        or type(SafeField(NS.CombatGate, "RunOrDefer")) ~= "function" then
        return false, "combat gate unavailable"
    end
    local key = DeferredKey(state, suffix)
    state.deferred[key] = true
    local ok, ran, reason = pcall(NS.CombatGate.RunOrDefer, key, function()
        local current = SemanticHUD.owners[state.parentOwner]
        if current then current.deferred[key] = nil end
        if current and current.active then callback(current) end
    end)
    if not ok then
        state.deferred[key] = nil
        Report("defer " .. tostring(suffix), ran)
        return false, "failed"
    end
    if ran then state.deferred[key] = nil end
    return ran == true, reason
end

local function RequestViewerForOwners(viewer)
    local definition = ViewerDefinition(viewer)
    if not definition then return end
    for _, state in pairs(SemanticHUD.owners) do
        if state.active then
            -- CombatGate coalesces repeated OnAcquire/RefreshLayout/OnShow
            -- signals per logical owner and exact viewer. The callback is the
            -- only place that may inspect the pool or mutate UI.
            RunOrDefer(state, "cooldown-" .. definition.name, function(current)
                ApplyViewer(current, viewer)
            end)
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
    if SemanticHUD.hooks[key] then return true end

    local viewer = _G[definition.name]
    local concreteMixin = _G[definition.mixin]
    -- CreateFromMixins copies methods at every layer, and XML applies the
    -- finished concrete mixin to the already-created global frame. Hook the
    -- exact frame method that self:Method() resolves at runtime, while also
    -- requiring that the matching concrete Retail mixin exposes the contract.
    -- This avoids relying on later changes to CooldownViewerMixin propagating
    -- through either copy boundary.
    local viewerMethod = SafeField(viewer, method)
    local concreteMethod = SafeField(concreteMixin, method)
    if type(hooksecurefunc) ~= "function"
        or type(viewerMethod) ~= "function"
        or type(concreteMethod) ~= "function"
        or viewerMethod ~= concreteMethod then
        return false
    end

    local ok, message = pcall(hooksecurefunc, viewer, method, function(self)
        if self == viewer then RequestViewerForOwners(viewer) end
    end)
    if not ok then
        Report("hook " .. key, message)
        return false
    end
    SemanticHUD.hooks[key] = true
    SemanticHUD.hookCount = SemanticHUD.hookCount + 1
    return true
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
            if type(SafeField(viewer, method)) ~= "function"
                or type(SafeField(concreteMixin, method)) ~= "function" then
                return false
            end
        end
    end
    return true
end

local function OnCooldownViewerLoaded()
    SemanticHUD.waitingForCooldownViewer = false
    InstallCooldownHooks()
    RequestAllViewersForOwners()
end

local function ScheduleCooldownViewer()
    if CooldownViewerReady() or IsLoaded(COOLDOWN_ADDON) then
        OnCooldownViewerLoaded()
        return true
    end
    if SemanticHUD.waitingForCooldownViewer or not EventUtil
        or type(SafeField(EventUtil, "ContinueOnAddOnLoaded")) ~= "function" then
        return false
    end
    SemanticHUD.waitingForCooldownViewer = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded,
        COOLDOWN_ADDON, OnCooldownViewerLoaded)
    if not ok then
        SemanticHUD.waitingForCooldownViewer = false
        Report("load " .. COOLDOWN_ADDON, message)
        return false
    end
    return true
end

local function ApplyState(state)
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then
        return RunOrDefer(state, "apply", ApplyState)
    end
    if not CategoryEnabled() then
        RestoreVisuals(state)
        return true, "disabled"
    end

    local applied = SkinLossOfControl(state) == true and 1 or 0
    local waiting = false
    if CooldownViewerReady() or IsLoaded(COOLDOWN_ADDON) then
        InstallCooldownHooks()
        for index = 1, #viewerDefinitions do
            local viewer = _G[viewerDefinitions[index].name]
            if viewer then
                local ok = ApplyViewer(state, viewer)
                if ok then applied = applied + 1 end
            end
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
    local state
    state, parentOwner = OwnerState(parentOwner)
    CancelDeferred(state)
    state.active = true
    if IsCombatLocked() then return RunOrDefer(state, "apply", ApplyState) end
    return ApplyState(state)
end

function SemanticHUD.Refresh(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = SemanticHUD.owners[parentOwner]
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then return RunOrDefer(state, "apply", ApplyState) end
    return ApplyState(state)
end

local function DisableNow(state)
    if not state then return true end
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
    if IsCombatLocked() then
        if not NS.CombatGate
            or type(SafeField(NS.CombatGate, "RunOrDefer")) ~= "function" then
            return false, "combat gate unavailable"
        end
        local key = DeferredKey(state, "disable")
        state.deferred[key] = true
        local ok, ran, reason = pcall(NS.CombatGate.RunOrDefer, key, function()
            local current = SemanticHUD.owners[parentOwner]
            if current then current.deferred[key] = nil end
            if current and not current.active then DisableNow(current) end
        end)
        if not ok then
            state.deferred[key] = nil
            Report("defer disable", ran)
            return false, "failed"
        end
        return ran == true, reason
    end
    return DisableNow(state)
end

function SemanticHUD.GetState(parentOwner)
    return SemanticHUD.owners[parentOwner or DEFAULT_OWNER]
end

return SemanticHUD
