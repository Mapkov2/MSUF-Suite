local _, NS = ...

-- Exact shared chrome adapters, verified clean-room against
-- Gethe/wow-ui-source upstream/live at
-- 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4:
--
--   Blizzard_FrameXML/TalkingHeadUI.xml
--   Blizzard_SocialToast/SocialToast.xml
--   Blizzard_BNet/BNet.xml
--   Blizzard_Minimap/Mainline/AddonCompartment.xml
--   Blizzard_QuickKeybind/QuickKeybind.xml
--   Blizzard_RaidFrame/Mainline/RaidFrame.xml
--   Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.lua/.xml
--   Blizzard_PlayerChoice/Blizzard_PlayerChoice.lua/.xml
--   Blizzard_CustomizationUI/Blizzard_CustomizationUI.lua/.xml
--   Blizzard_CharacterCustomize/Blizzard_CharacterCustomize.lua/.xml
--   Blizzard_CombatLog/Mainline/Blizzard_CombatLog.lua/.xml
--
-- The adapter follows Blizzard's own addon, callback and post-pool lifecycle
-- points. It never replaces a Blizzard method or script, and deliberately
-- leaves models, text, fonts, semantic icons, animations and geometry native.
local SharedChrome = {
    owners = {},
    activeOwnerCount = 0,
    callbackState = {},
    hooks = {},
    waitingAddons = {},
}
NS.SharedChrome = SharedChrome

local DEFAULT_OWNER = "blizzardWindows"

local QUEUE_UPDATED_CALLBACK = "QueueStatusUpdate.QueuesUpdated"
local CUSTOMIZATION_SET_CALLBACK = "Customization.OnSetCustomizations"
local CUSTOMIZATION_CATEGORY_CALLBACK = "Customization.OnCategorySelected"
local CHAR_CUSTOMIZE_SHOW_CALLBACK = "CharCustomize.OnShow"

local addonKinds = {
    Blizzard_FrameXML = { "talking-head" },
    Blizzard_BNet = { "social-toasts" },
    Blizzard_Minimap = { "addon-compartment" },
    Blizzard_QuickKeybind = { "quick-keybind" },
    Blizzard_RaidFrame = { "raid" },
    Blizzard_QueueStatusFrame = { "queue-status" },
    Blizzard_PlayerChoice = { "player-choice" },
    Blizzard_CharacterCustomize = { "character-customize" },
    Blizzard_CombatLog = { "combat-log" },
}

local allKinds = {
    "talking-head",
    "social-toasts",
    "addon-compartment",
    "quick-keybind",
    "raid",
    "queue-status",
    "player-choice",
    "character-customize",
    "combat-log",
}

local QUEUE_MODE = {
    role = "popup",
    maxDepth = 8,
    maxNodes = 400,
    allowImplicitProtected = false,
}

local QUEUE_ENTRY_MODE = {
    role = "card",
    radius = 5,
    maxDepth = 4,
    maxNodes = 120,
    allowImplicitProtected = false,
}

local PLAYER_CHOICE_MODE = {
    role = "shell",
    maxDepth = 10,
    maxNodes = 1000,
    allowImplicitProtected = true,
}

local CHARACTER_CUSTOMIZE_MODE = {
    -- CharCustomizeFrame is a UIParent-sized interaction layer. Traversing it
    -- reaches the option/category pools, but it must never receive a root fill.
    rootSurface = false,
    preserveRootArt = true,
    maxDepth = 10,
    maxNodes = 1000,
    allowImplicitProtected = false,
}

local RAID_MODE = {
    role = "shell",
    maxDepth = 8,
    maxNodes = 800,
    -- Blizzard_RaidFrame adds explicitly secure unit buttons below this root.
    -- GenericWindows skips those buttons; this flag only permits the now
    -- implicitly protected, non-secure surrounding chrome outside combat.
    allowImplicitProtected = true,
}

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("shared chrome " .. label, message)
    end
end

local function IsCombatLocked()
    return type(NS.IsCombatLocked) == "function" and NS.IsCombatLocked() == true
end

local function CategoryEnabled(category)
    local generic = NS.GenericWindows
    if generic and type(generic.IsCategoryEnabled) == "function" then
        local ok, enabled = pcall(generic.IsCategoryEnabled, category)
        return ok and enabled ~= false
    end
    return true
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = SharedChrome.owners[owner]
    if not state then
        state = {
            active = false,
            deferred = {},
            surfaces = setmetatable({}, { __mode = "k" }),
        }
        SharedChrome.owners[owner] = state
    end
    return state, owner
end

local function TrackSurface(owner, target)
    local state = SharedChrome.owners[owner]
    if state and target then state.surfaces[target] = true end
end

local function Attach(target, owner, spec)
    if not target or not NS.Surface or type(NS.Surface.Attach) ~= "function"
        or not NS.Safety or not NS.Safety.CanDecorate(target, true) then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local ok, surface = pcall(NS.Surface.Attach, target, spec)
    if not ok then
        Report("surface", surface)
        return false
    end
    if not surface then return false end
    TrackSurface(owner, target)
    return true
end

local function Fade(region, owner)
    if not region or not NS.Cosmetics or type(NS.Cosmetics.Fade) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.Cosmetics.Fade, region, owner)
    if not ok then Report("fade", applied) end
    return ok and applied == true
end

local function SuppressVertexAlpha(region, owner)
    if not region or not NS.Cosmetics
        or type(NS.Cosmetics.SuppressVertexAlpha) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.Cosmetics.SuppressVertexAlpha, region, owner)
    if not ok then Report("vertex alpha", applied) end
    return ok and applied == true
end

local function FadeNineSlice(frame, owner)
    if not frame or not NS.Cosmetics or type(NS.Cosmetics.FadeNineSlice) ~= "function" then
        return
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, frame, owner)
    if not ok then Report("nine slice", message) end
end

local function FadeDialogHeader(header, owner)
    if not header or not NS.Cosmetics or type(NS.Cosmetics.FadeDialogHeader) ~= "function" then
        return
    end
    local ok, message = pcall(NS.Cosmetics.FadeDialogHeader, header, owner)
    if not ok then Report("dialog header", message) end
end

local function SkinButton(button, owner, spec)
    if not button or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function"
        or not NS.Safety or not NS.Safety.CanControl(button, true) then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local ok, state = pcall(NS.ControlSkin.ApplyButton, button, owner, spec)
    if not ok then
        Report("button", state)
        return false
    end
    if not state then return false end
    TrackSurface(owner, button)
    return true
end

local function ApplyGeneric(frame, owner, mode, label)
    if not frame or not NS.GenericWindows or type(NS.GenericWindows.ApplyFrame) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.GenericWindows.ApplyFrame, frame, owner, mode)
    if not ok then
        Report(label or "generic", applied)
        return false
    end
    return applied == true
end

local function SkinTalkingHead(owner)
    if not CategoryEnabled("hud") then return false end
    local root = _G.TalkingHeadFrame
    if not root then return false end

    -- Alpha animations keep running natively. Vertex-alpha suppression removes
    -- only the ornamental texture layer without fighting those animations;
    -- portrait art, the PlayerModel, text and geometry remain native.
    local background = SafeField(root, "BackgroundFrame")
    local applied = Attach(background, owner, {
        role = "popup", radius = 8, inset = 0,
    })

    local main = SafeField(root, "MainFrame")
    SuppressVertexAlpha(SafeField(background, "TextBackground"), owner)
    SuppressVertexAlpha(SafeField(main, "Sheen"), owner)
    SuppressVertexAlpha(SafeField(main, "TextSheen"), owner)
    local overlay = SafeField(main, "Overlay")
    SuppressVertexAlpha(SafeField(overlay, "Glow_TopBar"), owner)
    SuppressVertexAlpha(SafeField(overlay, "Glow_LeftBar"), owner)
    SuppressVertexAlpha(SafeField(overlay, "Glow_RightBar"), owner)
    local closeButton = SafeField(main, "CloseButton")
    applied = SkinButton(closeButton, owner, {
        role = "button", useControlShape = true,
        pillHeight = 18, radius = 4, inset = 1,
    }) or applied
    return applied
end

local function SkinSocialToast(frame, owner)
    if not frame then return false end
    local applied = Attach(frame, owner, {
        role = "popup", radius = 6, inset = 0,
    })
    -- BackdropTemplate exposes its neutral nine-slice pieces directly. Hide
    -- only those reversible pieces; the separate glow animation remains
    -- native. The close-button detector preserves its native icon textures.
    FadeNineSlice(frame, owner)
    applied = SkinButton(SafeField(frame, "CloseButton"), owner, {
        role = "button", useControlShape = true,
        pillHeight = 18, radius = 4, inset = 1,
    }) or applied
    return applied
end

local function SkinSocialToasts(owner)
    if not CategoryEnabled("social") then return false end
    local applied = SkinSocialToast(_G.BNToastFrame, owner)
    applied = SkinSocialToast(_G.TimeAlertFrame, owner) or applied
    return applied
end

local function SkinAddonCompartment(owner)
    if not CategoryEnabled("hud") then return false end
    local button = _G.AddonCompartmentFrame
    if not button then return false end

    -- A plain surface keeps the minimap atlas, addon count and DropdownButton
    -- semantics native; ControlSkin would replace interactive state textures.
    return Attach(button, owner, {
        role = "button", useControlShape = true,
        pillHeight = 16, radius = 4, inset = 0, forceEdge = true,
    })
end

local function SkinQuickKeybind(owner)
    if not CategoryEnabled("utility") then return false end
    local root = _G.QuickKeybindFrame
    if not root then return false end

    -- QuickKeybindFrame is explicitly protected in XML. Never pass the root
    -- itself to Surface, ControlSkin, Cosmetics or GenericWindows. Its named
    -- children are only handled when Safety identifies them as permissible
    -- implicit descendants outside combat.
    local applied = false
    local background = SafeField(root, "BG")
    if background and NS.Safety and NS.Safety.CanDecorate(background, true) then
        applied = Attach(background, owner, {
            role = "popup", radius = 8, inset = 0,
        }) or applied
        Fade(SafeField(background, "Bg"), owner)
        FadeNineSlice(background, owner)
    end

    local header = SafeField(root, "Header")
    if header and NS.Safety and NS.Safety.CanDecorate(header, true) then
        applied = Attach(header, owner, {
            role = "navigation", radius = 6, inset = 0,
        }) or applied
        FadeDialogHeader(header, owner)
    end

    for _, field in ipairs({ "DefaultsButton", "CancelButton", "OkayButton" }) do
        applied = SkinButton(SafeField(root, field), owner, {
            role = "button", activeRole = "buttonPrimary",
            useControlShape = true, pillHeight = 22,
            radius = 5, inset = 1,
        }) or applied
    end
    -- UseCharacterBindingsButton is a semantic checkbox and remains native.
    return applied
end

local function SkinRaid(owner)
    if not CategoryEnabled("group") then return false end
    return ApplyGeneric(_G.RaidParentFrame, owner, RAID_MODE, "raid")
end

local function ForEachActivePoolFrame(pool, callback, limit)
    local enumerate = SafeField(pool, "EnumerateActive")
    if type(enumerate) ~= "function" then return false end
    local visited, count = false, 0
    limit = math.max(1, math.min(128, tonumber(limit) or 64))
    local ok, message = pcall(function()
        for frame in enumerate(pool) do
            if count >= limit then break end
            count = count + 1
            visited = true
            callback(frame)
        end
    end)
    if not ok then Report("pool", message) end
    return ok and visited
end

local function SkinQueueStatus(owner)
    if not CategoryEnabled("hud") then return false end
    local root = _G.QueueStatusFrame
    if not root then return false end
    local applied = ApplyGeneric(root, owner, QUEUE_MODE, "queue status")
    ForEachActivePoolFrame(SafeField(root, "statusEntriesPool"), function(entry)
        applied = ApplyGeneric(entry, owner, QUEUE_ENTRY_MODE, "queue entry") or applied
    end)
    return applied
end

local function SkinPlayerChoice(owner)
    if not CategoryEnabled("quest") then return false end
    return ApplyGeneric(_G.PlayerChoiceFrame, owner, PLAYER_CHOICE_MODE, "player choice")
end

local function SkinCharacterCustomize(owner)
    if not CategoryEnabled("character") then return false end
    return ApplyGeneric(_G.CharCustomizeFrame, owner, CHARACTER_CUSTOMIZE_MODE,
        "character customize")
end

local function SkinCombatLog(owner)
    if not CategoryEnabled("utility") then return false end
    local root = _G.CombatLogQuickButtonFrame_Custom
    if not root then return false end

    local applied = Attach(root, owner, {
        role = "navigation", radius = 4, inset = 0, forceEdge = true,
    })
    Fade(_G.CombatLogQuickButtonFrame_CustomTexture, owner)
    applied = SkinButton(_G.CombatLogQuickButtonFrame_CustomAdditionalFilterButton, owner, {
        role = "navigation", activeRole = "navigationActive",
        useControlShape = true, pillHeight = 24,
        radius = 4, inset = 1,
        -- The normal texture is the semantic filter glyph and is not listed.
        regions = {},
    }) or applied
    -- ProgressBar, quick-button labels, fonts and anchors are intentionally
    -- absent from this adapter.
    return applied
end

local kindSkinners = {
    ["talking-head"] = SkinTalkingHead,
    ["social-toasts"] = SkinSocialToasts,
    ["addon-compartment"] = SkinAddonCompartment,
    ["quick-keybind"] = SkinQuickKeybind,
    raid = SkinRaid,
    ["queue-status"] = SkinQueueStatus,
    ["player-choice"] = SkinPlayerChoice,
    ["character-customize"] = SkinCharacterCustomize,
    ["combat-log"] = SkinCombatLog,
}

local function ApplyKind(owner, kind)
    local state = SharedChrome.owners[owner]
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then return false, "combat" end
    local skinner = kindSkinners[kind]
    if type(skinner) ~= "function" then return false, "invalid" end
    local ok, applied = pcall(skinner, owner)
    if not ok then
        Report(kind, applied)
        return false, "failed"
    end
    return applied == true, applied and "applied" or "missing"
end

local function DeferredKey(owner, suffix)
    return "shared-chrome:" .. tostring(owner) .. ":" .. tostring(suffix)
end

local function RunOrDefer(owner, suffix, callback)
    local state = SharedChrome.owners[owner]
    if not state or not state.active then return false, "disabled" end
    if not NS.CombatGate or type(NS.CombatGate.RunOrDefer) ~= "function" then
        return false, "combat gate unavailable"
    end

    local key = DeferredKey(owner, suffix)
    state.deferred[key] = true
    local ok, ran, reason = pcall(NS.CombatGate.RunOrDefer, key, function()
        local current = SharedChrome.owners[owner]
        if current then current.deferred[key] = nil end
        if current and current.active then callback(current) end
    end)
    if not ok then
        state.deferred[key] = nil
        Report("defer " .. tostring(suffix), ran)
        return false, "failed"
    end
    return ran == true, reason
end

local function RequestKindForOwners(kind)
    for owner, state in pairs(SharedChrome.owners) do
        if state.active then
            RunOrDefer(owner, kind, function()
                ApplyKind(owner, kind)
            end)
        end
    end
end

local function ApplyAllNow(owner)
    local applied = 0
    for index = 1, #allKinds do
        local success = ApplyKind(owner, allKinds[index])
        if success then applied = applied + 1 end
    end
    return applied
end

local function HookMixinMethod(key, mixin, method, callback)
    if SharedChrome.hooks[key] then return true end
    if type(hooksecurefunc) ~= "function" or type(SafeField(mixin, method)) ~= "function" then
        return false
    end
    local ok, message = pcall(hooksecurefunc, mixin, method, callback)
    if not ok then
        Report("hook " .. key, message)
        return false
    end
    SharedChrome.hooks[key] = true
    return true
end

local function OnPlayerChoicePoolReady(frame)
    if frame == _G.PlayerChoiceFrame then
        RequestKindForOwners("player-choice")
    end
end

local function InstallHooks()
    local mixin = _G.PlayerChoiceFrameMixin
    HookMixinMethod("player-choice-options", mixin, "SetupOptions", OnPlayerChoicePoolReady)
    -- Grid pages can repopulate nested reward/button pools without rebuilding
    -- the outer option pool.
    HookMixinMethod("player-choice-page", mixin, "OnPageChanged", OnPlayerChoicePoolReady)
end

local function IsHiddenEmptyQueue(root)
    -- upstream/live QueueStatusFrameMixin:Update releases/rebuilds the pool,
    -- then fires QueuesUpdated even with no queues and the tooltip hidden.
    -- Any unavailable/secret/throwing method falls back to the full skin pass.
    if root:IsShown() ~= false then return false end
    if root.statusEntriesPool:GetNumActive() == 0 then return true end
    return false
end

function SharedChrome:OnQueueStatusUpdated()
    -- This callback fires after QueueStatusFrameMixin:Update has released,
    -- acquired, sorted and anchored every statusEntriesPool entry.
    local root = _G.QueueStatusFrame
    if root then
        local ok, idle = pcall(IsHiddenEmptyQueue, root)
        if ok and idle then return end
    end
    RequestKindForOwners("queue-status")
end

function SharedChrome:OnCustomizationSet()
    RequestKindForOwners("character-customize")
end

function SharedChrome:OnCustomizationCategory(frame)
    if frame == _G.CharCustomizeFrame then
        RequestKindForOwners("character-customize")
    end
end

function SharedChrome:OnCharacterCustomizeShown(frame)
    if frame == _G.CharCustomizeFrame then
        RequestKindForOwners("character-customize")
    end
end

local function RegisterCallback(event, method, key)
    if SharedChrome.callbackState[key] then return true end
    local registry = EventRegistry
    if not registry or type(SafeField(registry, "RegisterCallback")) ~= "function" then
        return false
    end
    local ok, message = pcall(registry.RegisterCallback, registry, event, method, SharedChrome)
    if not ok then
        Report("register " .. event, message)
        return false
    end
    SharedChrome.callbackState[key] = true
    return true
end

local function RegisterCallbacks()
    RegisterCallback(QUEUE_UPDATED_CALLBACK, SharedChrome.OnQueueStatusUpdated, "queue")
    RegisterCallback(CUSTOMIZATION_SET_CALLBACK, SharedChrome.OnCustomizationSet, "customization-set")
    RegisterCallback(CUSTOMIZATION_CATEGORY_CALLBACK,
        SharedChrome.OnCustomizationCategory, "customization-category")
    RegisterCallback(CHAR_CUSTOMIZE_SHOW_CALLBACK,
        SharedChrome.OnCharacterCustomizeShown, "character-show")
end

local function UnregisterCallback(event, key)
    if not SharedChrome.callbackState[key] then return end
    local registry = EventRegistry
    if registry and type(SafeField(registry, "UnregisterCallback")) == "function" then
        pcall(registry.UnregisterCallback, registry, event, SharedChrome)
    end
    SharedChrome.callbackState[key] = nil
end

local function UnregisterCallbacks()
    UnregisterCallback(QUEUE_UPDATED_CALLBACK, "queue")
    UnregisterCallback(CUSTOMIZATION_SET_CALLBACK, "customization-set")
    UnregisterCallback(CUSTOMIZATION_CATEGORY_CALLBACK, "customization-category")
    UnregisterCallback(CHAR_CUSTOMIZE_SHOW_CALLBACK, "character-show")
end

local function IsAddonLoaded(addon)
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

local function ScheduleAddonLoads()
    if not EventUtil or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then return end
    for addon, kinds in pairs(addonKinds) do
        if not IsAddonLoaded(addon) and not SharedChrome.waitingAddons[addon] then
            SharedChrome.waitingAddons[addon] = true
            local pendingAddon, pendingKinds = addon, kinds
            local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, pendingAddon, function()
                SharedChrome.waitingAddons[pendingAddon] = nil
                if SharedChrome.activeOwnerCount == 0 then return end
                InstallHooks()
                RegisterCallbacks()
                for index = 1, #pendingKinds do
                    RequestKindForOwners(pendingKinds[index])
                end
            end)
            if not ok then
                SharedChrome.waitingAddons[pendingAddon] = nil
                Report("addon load " .. pendingAddon, message)
            end
        end
    end
end

function SharedChrome.Apply(owner)
    local state
    state, owner = OwnerState(owner)
    if not state.active then
        state.active = true
        SharedChrome.activeOwnerCount = SharedChrome.activeOwnerCount + 1
    end

    ScheduleAddonLoads()
    RegisterCallbacks()
    InstallHooks()

    local applied = 0
    local ran, reason = RunOrDefer(owner, "apply", function()
        applied = ApplyAllNow(owner)
    end)
    if not ran then return false, reason or "combat" end
    return true, applied > 0 and "applied" or "waiting"
end

function SharedChrome.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = SharedChrome.owners[owner]
    if not state then return true end
    if IsCombatLocked() then return false, "combat" end

    state.active = false
    if NS.CombatGate and type(NS.CombatGate.Cancel) == "function" then
        for key in pairs(state.deferred) do NS.CombatGate.Cancel(key) end
    end
    state.deferred = {}
    if NS.Surface and type(NS.Surface.SetVisible) == "function" then
        for target in pairs(state.surfaces) do
            pcall(NS.Surface.SetVisible, target, false)
        end
    end

    SharedChrome.owners[owner] = nil
    SharedChrome.activeOwnerCount = math.max(0, SharedChrome.activeOwnerCount - 1)
    if SharedChrome.activeOwnerCount == 0 then
        UnregisterCallbacks()
    end

    -- The parent blizzardWindows adapter owns the shared ControlSkin,
    -- Cosmetics and GenericWindows restoration and performs it once after all
    -- sibling adapters have disabled.
    return true
end

return SharedChrome
