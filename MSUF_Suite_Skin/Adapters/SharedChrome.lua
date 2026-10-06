local _, NS = ...

local Safety = NS.Safety
local Field = Safety.Field
local Kit = NS.AdapterKit

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
    activeOwnerCount = 0,
    callbackState = {},
    hooks = {},
    waitingAddons = {},
}
NS.SharedChrome = SharedChrome

local DEFAULT_OWNER = "blizzardWindows"
local QUEUE_ENTRY_LIMIT = 64

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

local POPUP_SPEC = { role = "popup", radius = 8, inset = 0 }
local TOAST_SPEC = { role = "popup", radius = 6, inset = 0 }
local HEADER_SPEC = { role = "navigation", radius = 6, inset = 0 }
local SMALL_CLOSE_SPEC = {
    role = "button", useControlShape = true,
    pillHeight = 18, radius = 4, inset = 1,
}
local COMPARTMENT_SPEC = {
    role = "button", useControlShape = true,
    pillHeight = 16, radius = 4, inset = 0, forceEdge = true,
}
local KEYBIND_BUTTON_SPEC = {
    role = "button", activeRole = "buttonPrimary",
    useControlShape = true, pillHeight = 22,
    radius = 5, inset = 1,
}
local COMBAT_LOG_BAR_SPEC = { role = "navigation", radius = 4, inset = 0, forceEdge = true }
local COMBAT_LOG_FILTER_SPEC = {
    role = "navigation", activeRole = "navigationActive",
    useControlShape = true, pillHeight = 24,
    radius = 4, inset = 1,
    -- The normal texture is the semantic filter glyph and is not listed.
    regions = {},
}

local DIALOG_HEADER_FIELDS = { "LeftBG", "CenterBG", "RightBG" }
local TALKING_HEAD_OVERLAY_FIELDS = { "Glow_TopBar", "Glow_LeftBar", "Glow_RightBar" }
local QUICK_KEYBIND_BUTTONS = { "DefaultsButton", "CancelButton", "OkayButton" }

-- Deferral keys are shared-chrome:<owner>:<suffix>.
local Owners = Kit.NewOwners({
    prefix = "shared-chrome",
    default = DEFAULT_OWNER,
    surfaces = true,
    init = function(state)
        -- pooled queue entry -> skin generation of its pass
        state.queueEntries = Kit.WeakSet()
    end,
})
SharedChrome.owners = Owners.owners

local function ApplyGeneric(frame, owner, mode)
    return frame ~= nil and NS.GenericWindows.ApplyFrame(frame, owner, mode) == true
end

local function SkinTalkingHead(state)
    if not NS.GenericWindows.IsCategoryEnabled("hud") then return false end
    local root = _G.TalkingHeadFrame
    if not root then return false end

    -- Alpha animations keep running natively. Vertex-alpha suppression removes
    -- only the ornamental texture layer without fighting those animations;
    -- portrait art, the PlayerModel, text and geometry remain native.
    local background = Field(root, "BackgroundFrame")
    local applied = Kit.Attach(state, background, POPUP_SPEC)

    local main = Field(root, "MainFrame")
    Kit.SuppressVertexAlpha(state, Field(background, "TextBackground"))
    Kit.SuppressVertexAlpha(state, Field(main, "Sheen"))
    Kit.SuppressVertexAlpha(state, Field(main, "TextSheen"))
    local overlay = Field(main, "Overlay")
    for index = 1, #TALKING_HEAD_OVERLAY_FIELDS do
        Kit.SuppressVertexAlpha(state, Field(overlay, TALKING_HEAD_OVERLAY_FIELDS[index]))
    end
    applied = Kit.SkinControl(state, Field(main, "CloseButton"), SMALL_CLOSE_SPEC) or applied
    return applied
end

local function SkinSocialToast(state, frame)
    if not frame then return false end
    local applied = Kit.Attach(state, frame, TOAST_SPEC)
    -- BackdropTemplate exposes its neutral nine-slice pieces directly. Hide
    -- only those reversible pieces; the separate glow animation remains
    -- native. The close-button detector preserves its native icon textures.
    Kit.FadeNineSlice(state, frame)
    applied = Kit.SkinControl(state, Field(frame, "CloseButton"), SMALL_CLOSE_SPEC) or applied
    return applied
end

local function SkinSocialToasts(state)
    if not NS.GenericWindows.IsCategoryEnabled("social") then return false end
    local applied = SkinSocialToast(state, _G.BNToastFrame)
    applied = SkinSocialToast(state, _G.TimeAlertFrame) or applied
    return applied
end

local function SkinAddonCompartment(state)
    if not NS.GenericWindows.IsCategoryEnabled("hud") then return false end
    local button = AddonCompartmentFrame

    -- A plain surface keeps the minimap atlas, addon count and DropdownButton
    -- semantics native; ControlSkin would replace interactive state textures.
    return Kit.Attach(state, button, COMPARTMENT_SPEC)
end

local function SkinQuickKeybind(state)
    if not NS.GenericWindows.IsCategoryEnabled("utility") then return false end
    local root = _G.QuickKeybindFrame
    if not root then return false end

    -- QuickKeybindFrame is explicitly protected in XML. Never pass the root
    -- itself to Surface, ControlSkin, Cosmetics or GenericWindows. Its named
    -- children are only handled when Safety identifies them as permissible
    -- implicit descendants outside combat.
    local applied = false
    local background = Field(root, "BG")
    if background and Safety.CanDecorate(background, true) then
        applied = Kit.Attach(state, background, POPUP_SPEC) or applied
        Kit.Fade(state, Field(background, "Bg"))
        Kit.FadeNineSlice(state, background)
    end

    local header = Field(root, "Header")
    if header and Safety.CanDecorate(header, true) then
        applied = Kit.Attach(state, header, HEADER_SPEC) or applied
        Kit.FadeFields(state, header, DIALOG_HEADER_FIELDS)
    end

    for index = 1, #QUICK_KEYBIND_BUTTONS do
        applied = Kit.SkinControl(state, Field(root, QUICK_KEYBIND_BUTTONS[index]),
            KEYBIND_BUTTON_SPEC) or applied
    end
    -- UseCharacterBindingsButton is a semantic checkbox and remains native.
    return applied
end

local function SkinRaid(state)
    if not NS.GenericWindows.IsCategoryEnabled("group") then return false end
    return ApplyGeneric(_G.RaidParentFrame, state.owner, RAID_MODE)
end

-- QueueStatusFrameMixin:Update rebuilds the entry pool on every queue event.
-- The root and each pooled entry take one skin pass per look generation;
-- later updates only reach entries the pool created since.
local function SkinQueueStatus(state)
    if not NS.GenericWindows.IsCategoryEnabled("hud") then return false end
    local root = _G.QueueStatusFrame
    if not root then return false end
    local generation = Kit.SkinGeneration()
    local applied = state.queueRootGeneration == generation
    if not applied and ApplyGeneric(root, state.owner, QUEUE_MODE) then
        state.queueRootGeneration = generation
        applied = true
    end
    local pool = Field(root, "statusEntriesPool")
    if type((Field(pool, "EnumerateActive"))) == "function" then
        local entries = state.queueEntries
        local count = 0
        for entry in pool:EnumerateActive() do
            if count >= QUEUE_ENTRY_LIMIT then break end
            count = count + 1
            if entries[entry] == generation then
                applied = true
            elseif ApplyGeneric(entry, state.owner, QUEUE_ENTRY_MODE) then
                entries[entry] = generation
                applied = true
            end
        end
    end
    return applied
end

local function SkinPlayerChoice(state)
    if not NS.GenericWindows.IsCategoryEnabled("quest") then return false end
    return ApplyGeneric(_G.PlayerChoiceFrame, state.owner, PLAYER_CHOICE_MODE)
end

local function SkinCharacterCustomize(state)
    if not NS.GenericWindows.IsCategoryEnabled("character") then return false end
    return ApplyGeneric(_G.CharCustomizeFrame, state.owner, CHARACTER_CUSTOMIZE_MODE)
end

local function SkinCombatLog(state)
    if not NS.GenericWindows.IsCategoryEnabled("utility") then return false end
    local root = _G.CombatLogQuickButtonFrame_Custom
    if not root then return false end

    local applied = Kit.Attach(state, root, COMBAT_LOG_BAR_SPEC)
    Kit.Fade(state, _G.CombatLogQuickButtonFrame_CustomTexture)
    applied = Kit.SkinControl(state, _G.CombatLogQuickButtonFrame_CustomAdditionalFilterButton,
        COMBAT_LOG_FILTER_SPEC) or applied
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

-- Each kind is its own error boundary, so one failing kind leaves the others.
local function ApplyKind(state, kind)
    if not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    local finished, applied = Kit.Isolate(kindSkinners[kind], state)
    if not finished then return false, "error" end
    applied = applied == true
    return applied, applied and "applied" or "missing"
end

-- ApplyKind(state, kind) now, or once per owner and kind after combat.
local function RequestKindForOwners(kind)
    for _, state in pairs(SharedChrome.owners) do
        if state.active then
            Owners.RunOrDefer(state, kind, ApplyKind, kind)
        end
    end
end

local function ApplyAllNow(state)
    local applied = 0
    for index = 1, #allKinds do
        if ApplyKind(state, allKinds[index]) then applied = applied + 1 end
    end
    return applied
end

local function OnPlayerChoicePoolReady(frame)
    if frame == _G.PlayerChoiceFrame then
        RequestKindForOwners("player-choice")
    end
end

-- Mixin() copied PlayerChoiceFrameMixin onto PlayerChoiceFrame when
-- Blizzard_PlayerChoice created it, and self:SetupOptions() resolves on the
-- frame, so the frame instance is hooked (once) rather than the mixin.
local function InstallHooks()
    local frame = _G.PlayerChoiceFrame
    if not frame or SharedChrome.hooks[frame] then return end
    local installed = Kit.HookFunction(frame, "SetupOptions", OnPlayerChoicePoolReady)
    -- Grid pages can repopulate nested reward/button pools without rebuilding
    -- the outer option pool.
    installed = Kit.HookFunction(frame, "OnPageChanged", OnPlayerChoicePoolReady) or installed
    SharedChrome.hooks[frame] = installed
end

-- QueueStatusFrameMixin:Update releases/rebuilds the pool and then fires
-- QueuesUpdated even with no queues and the tooltip hidden. Anything
-- unreadable falls back to the full skin pass.
local function IsHiddenEmptyQueue(root)
    if Safety.Read(root, "IsShown") ~= false then return false end
    return Safety.Read(Field(root, "statusEntriesPool"), "GetNumActive") == 0
end

function SharedChrome:OnQueueStatusUpdated()
    -- This callback fires after QueueStatusFrameMixin:Update has released,
    -- acquired, sorted and anchored every statusEntriesPool entry.
    local root = _G.QueueStatusFrame
    if root and IsHiddenEmptyQueue(root) then return end
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

local callbacks = {
    { key = "queue", event = QUEUE_UPDATED_CALLBACK, method = SharedChrome.OnQueueStatusUpdated },
    { key = "customization-set", event = CUSTOMIZATION_SET_CALLBACK,
        method = SharedChrome.OnCustomizationSet },
    { key = "customization-category", event = CUSTOMIZATION_CATEGORY_CALLBACK,
        method = SharedChrome.OnCustomizationCategory },
    { key = "character-show", event = CHAR_CUSTOMIZE_SHOW_CALLBACK,
        method = SharedChrome.OnCharacterCustomizeShown },
}

local function RegisterCallbacks()
    for index = 1, #callbacks do
        local callback = callbacks[index]
        if not SharedChrome.callbackState[callback.key] then
            EventRegistry:RegisterCallback(callback.event, callback.method, SharedChrome)
            SharedChrome.callbackState[callback.key] = true
        end
    end
end

local function UnregisterCallbacks()
    for index = 1, #callbacks do
        local callback = callbacks[index]
        if SharedChrome.callbackState[callback.key] then
            EventRegistry:UnregisterCallback(callback.event, SharedChrome)
            SharedChrome.callbackState[callback.key] = nil
        end
    end
end

local function OnAddonLoaded(addon)
    SharedChrome.waitingAddons[addon] = nil
    if SharedChrome.activeOwnerCount == 0 then return end
    InstallHooks()
    RegisterCallbacks()
    local kinds = addonKinds[addon]
    for index = 1, #kinds do
        RequestKindForOwners(kinds[index])
    end
end

local function ScheduleAddonLoads()
    for addon in pairs(addonKinds) do
        if not SharedChrome.waitingAddons[addon] and not NS.Client.IsAddOnLoaded(addon) then
            SharedChrome.waitingAddons[addon] = true
            EventUtil.ContinueOnAddOnLoaded(addon, function() OnAddonLoaded(addon) end)
        end
    end
end

function SharedChrome.Apply(owner)
    local state = Owners.State(owner)
    if not state.active then
        state.active = true
        SharedChrome.activeOwnerCount = SharedChrome.activeOwnerCount + 1
    end

    ScheduleAddonLoads()
    RegisterCallbacks()
    InstallHooks()

    if NS.IsCombatLocked() then
        local _, reason = Owners.RunOrDefer(state, "apply", ApplyAllNow)
        return false, reason or "combat"
    end
    local applied = ApplyAllNow(state)
    return true, applied > 0 and "applied" or "waiting"
end

function SharedChrome.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = SharedChrome.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    Owners.Release(state)
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
