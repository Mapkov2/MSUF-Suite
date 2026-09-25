local _, NS = ...

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call

-- Shared helpers for the Blizzard window adapters. This file loads before
-- every adapter that uses them (see the TOC). Visual helpers take the
-- adapter's skin context: { owner = cosmetic/control owner key, surfaces =
-- optional weak set of surfaces to hide on disable }. They only act outside
-- combat, skip forbidden and protected targets, and never replace Blizzard
-- code. Adapters own implicitly protected Blizzard trees outside combat, so
-- every spec passed here is marked allowImplicitProtected.
local AdapterKit = {}
NS.AdapterKit = AdapterKit

local WEAK_KEYS = { __mode = "k" }

function AdapterKit.WeakSet()
    return setmetatable({}, WEAK_KEYS)
end

-- Follows a parentKey chain; nil as soon as one link is missing.
function AdapterKit.Path(object, ...)
    for index = 1, select("#", ...) do
        object = Field(object, (select(index, ...)))
        if not object then return nil end
    end
    return object
end

-- Same as Path for a key list stored as data.
function AdapterKit.PathOf(object, keys)
    for index = 1, #keys do
        object = Field(object, keys[index])
        if not object then return nil end
    end
    return object
end

-- True when every listed member is present: an exact template contract.
function AdapterKit.HasFields(object, fields)
    for index = 1, #fields do
        if not Field(object, fields[index]) then return false end
    end
    return true
end

function AdapterKit.ObjectType(object)
    local objectType = Safety.Read(object, "GetObjectType")
    return type(objectType) == "string" and objectType or nil
end

function AdapterKit.IsShown(region)
    return Safety.Read(region, "IsShown") == true
end

function AdapterKit.ParentIs(frame, parent)
    return parent ~= nil and Call(frame, "GetParent") == parent
end

function AdapterKit.IsDescendantOf(frame, ancestor, maxDepth)
    if not frame or not ancestor then return false end
    local current = frame
    for _ = 1, maxDepth or 12 do
        if current == ancestor then return true end
        local parent = Call(current, "GetParent")
        if not parent or parent == current then return false end
        current = parent
    end
    return current == ancestor
end

local function VisitValues(callback, a, b, c, ...)
    for index = 1, select("#", ...) do
        callback((select(index, ...)), a, b, c)
    end
end

-- callback(region, a, b, c) for each direct region, without a result table.
function AdapterKit.ForEachRegion(frame, callback, a, b, c)
    if Safety.IsForbidden(frame) or type((Field(frame, "GetRegions"))) ~= "function" then return end
    VisitValues(callback, a, b, c, frame:GetRegions())
end

-- callback(object, a, b) for at most limit active objects of a Blizzard pool.
function AdapterKit.ForEachActive(pool, limit, callback, a, b)
    if type((Field(pool, "EnumerateActive"))) ~= "function" then return 0 end
    local count = 0
    for object in pool:EnumerateActive() do
        if count >= limit then break end
        count = count + 1
        callback(object, a, b)
    end
    return count
end

-- Fires after Blizzard's row initializer, for new and for recycled rows.
function AdapterKit.RowInitializedEvent()
    local mixin = _G.ScrollBoxListMixin
    local events = type(mixin) == "table" and mixin.Event
    local event = type(events) == "table" and events.OnInitializedFrame
    return type(event) == "string" and event or nil
end

-- Registers callback(owner, row) for initialized rows. Returns the event
-- name needed for unregistration, or nil when the ScrollBox cannot register.
function AdapterKit.RegisterRowCallback(scrollBox, callback, owner)
    local event = AdapterKit.RowInitializedEvent()
    if not event or Safety.IsForbidden(scrollBox)
        or type((Field(scrollBox, "RegisterCallback"))) ~= "function" then
        return nil
    end
    scrollBox:RegisterCallback(event, callback, owner)
    return event
end

function AdapterKit.UnregisterRowCallback(scrollBox, event, owner)
    if type(event) == "string" and owner ~= nil
        and Safety.Invoke(scrollBox, "UnregisterCallback", event, owner) then
        return true
    end
    return false
end

-- ScrollBox:ForEachFrame indexes its view, which exists only after Blizzard
-- initialized the list. Paged content frames have no view and are always ready.
function AdapterKit.ForEachRow(scrollBox, callback)
    if Safety.IsForbidden(scrollBox) or type((Field(scrollBox, "ForEachFrame"))) ~= "function" then
        return false
    end
    if type(scrollBox.HasView) == "function" and scrollBox:HasView() ~= true then return false end
    scrollBox:ForEachFrame(callback)
    return true
end

-- hooksecurefunc raises when the hooked member is not a function, so both
-- helpers check first. A missing target (mixin not loaded) hooks nothing.
function AdapterKit.HookFunction(target, method, callback)
    if type(hooksecurefunc) ~= "function" or type((Field(target, method))) ~= "function" then
        return false
    end
    hooksecurefunc(target, method, callback)
    return true
end

function AdapterKit.HookGlobal(name, callback)
    if type(hooksecurefunc) ~= "function" or type(_G[name]) ~= "function" then return false end
    hooksecurefunc(name, callback)
    return true
end

function AdapterKit.RegisterEventCallback(event, callback, owner)
    local registry = _G.EventRegistry
    if type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then return false end
    registry:RegisterCallback(event, callback, owner)
    return true
end

function AdapterKit.UnregisterEventCallback(event, owner)
    local registry = _G.EventRegistry
    if type(registry) == "table" and type(registry.UnregisterCallback) == "function" then
        registry:UnregisterCallback(event, owner)
    end
end

-- Runs callback at once when the addon is loaded, otherwise once on its
-- ADDON_LOADED. False when the client has no EventUtil continuation.
function AdapterKit.ContinueOnAddOnLoaded(addon, callback)
    local util = _G.EventUtil
    if type(util) ~= "table" or type(util.ContinueOnAddOnLoaded) ~= "function" then return false end
    util.ContinueOnAddOnLoaded(addon, callback)
    return true
end

function AdapterKit.CancelDeferred(state)
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
end

local function CanPaint(target)
    return type(target) == "table" and not NS.IsCombatLocked() and Safety.CanDecorate(target, true)
end

local function CanCreateRegions(target)
    return type(target) == "table" and not NS.IsCombatLocked()
        and Safety.CanCreateRegions(target, true)
end

function AdapterKit.Fade(context, region)
    return CanPaint(region) and NS.Cosmetics.Fade(region, context.owner) == true
end

function AdapterKit.FadeFields(context, target, fields)
    for index = 1, #fields do
        AdapterKit.Fade(context, Field(target, fields[index]))
    end
end

-- Fades the nine standard pieces stored directly on nineSlice.
function AdapterKit.FadeNineSlice(context, nineSlice)
    if not CanPaint(nineSlice) then return false end
    NS.Cosmetics.FadeNineSlice(nineSlice, context.owner)
    return true
end

-- Zero vertex alpha survives Blizzard's own region-alpha animations.
function AdapterKit.SuppressVertexAlpha(context, region)
    return CanPaint(region) and NS.Cosmetics.SuppressVertexAlpha(region, context.owner) == true
end

local function IsSurfaceTexture(surface, region)
    return surface ~= nil and (region == surface.fill or region == surface.edge
        or region == surface.depth or region == surface.highlight
        or region == surface.pushed or region == surface.disabled)
end

local function FadeTextureRegion(region, context, exception, surface)
    if region ~= exception and not IsSurfaceTexture(surface, region)
        and AdapterKit.ObjectType(region) == "Texture" then
        AdapterKit.Fade(context, region)
    end
end

-- Fades every direct Texture region of an exact, verified decorative frame
-- except one semantic exception.
function AdapterKit.FadeTextures(context, frame, exception)
    AdapterKit.ForEachRegion(frame, FadeTextureRegion, context, exception, nil)
end

-- Same, but keeps the textures of the frame's own MapkoSkin surface.
function AdapterKit.FadeNativeTextures(context, frame)
    AdapterKit.ForEachRegion(frame, FadeTextureRegion, context, nil, NS.Registry.GetSurface(frame))
end

local function FadeAtlasRegion(region, context, atlas)
    if Safety.Read(region, "GetAtlas") == atlas then AdapterKit.Fade(context, region) end
end

function AdapterKit.FadeAtlas(context, frame, atlas)
    AdapterKit.ForEachRegion(frame, FadeAtlasRegion, context, atlas)
end

local function Track(context, target)
    local surfaces = context.surfaces
    if surfaces then surfaces[target] = true end
end

-- Surface keeps a reference to spec: pass tables that are not changed later.
function AdapterKit.Attach(context, target, spec)
    if not CanCreateRegions(target) then return false end
    spec.allowImplicitProtected = true
    local surface = NS.Surface.Attach(target, spec)
    if not surface then return false end
    Track(context, target)
    return true, surface
end

-- ControlSkin copies spec. method defaults to ApplyButton; other values are
-- ApplyTab, ApplySearchBox and ApplyThreeSliceButton.
function AdapterKit.SkinControl(context, control, spec, method)
    if not CanCreateRegions(control) then return false end
    spec.allowImplicitProtected = true
    if not NS.ControlSkin[method or "ApplyButton"](control, context.owner, spec) then return false end
    Track(context, control)
    return true
end

-- IconSkin reads its spec only during the call, so one scratch spec serves
-- every item button without a table per button.
local itemIconSpec = {}

function AdapterKit.SkinItemIcon(button, owner, icon, nativeBorder, allowImplicitProtected)
    itemIconSpec.icon = icon
    itemIconSpec.nativeBorder = nativeBorder
    itemIconSpec.allowImplicitProtected = allowImplicitProtected == true
    local state = NS.IconSkin.Apply(button, owner, itemIconSpec)
    itemIconSpec.icon = nil
    itemIconSpec.nativeBorder = nil
    return state ~= nil
end

function AdapterKit.HideSurfaces(context)
    for target in pairs(context.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
end

-- A surface spec built once at load. Unset flags keep Surface's defaults:
-- no list-item transparency, no forced edge and a visible fill.
function AdapterKit.SurfaceSpec(role, radius, inset, listItem, forceEdge, fillVisible)
    return {
        role = role,
        radius = radius,
        inset = inset or 0,
        listItem = listItem == true,
        forceEdge = forceEdge == true,
        fillVisible = fillVisible ~= false,
        allowImplicitProtected = true,
    }
end

local SELECTION_INDICATOR_SPEC = AdapterKit.SurfaceSpec("navigationActive", 8, 2, true, true)

-- An owned, mouse-transparent frame over a navigation button, parented to
-- the content panel Blizzard shows while that button is selected. Panel
-- visibility then mirrors the selection without a hook, timer or polling;
-- the transparent center keeps the native icon and label readable.
-- matchLevel also copies the button's strata and level.
function AdapterKit.SelectionIndicator(context, indicators, button, panel, matchLevel)
    if not button or not panel or not Safety.CanDecorate(panel, true) then return false end
    local indicator = indicators[button]
    if not indicator then
        indicator = CreateFrame("Frame", nil, panel)
        indicators[button] = indicator
    end
    indicator:SetParent(panel)
    indicator:ClearAllPoints()
    indicator:SetAllPoints(button)
    if matchLevel then
        local strata = Safety.Read(button, "GetFrameStrata")
        if type(strata) == "string" then indicator:SetFrameStrata(strata) end
        local level = Safety.Read(button, "GetFrameLevel")
        if type(level) == "number" then indicator:SetFrameLevel(level) end
    end
    indicator:EnableMouse(false)
    indicator:Show()
    if AdapterKit.Attach(context, indicator, SELECTION_INDICATOR_SPEC) then return true end
    indicator:Hide()
    return false
end

function AdapterKit.HideIndicators(indicators)
    for _, indicator in pairs(indicators) do
        indicator:Hide()
    end
end

-- Reversible theme text colors. The native color is captured once, or again
-- with recapture when Blizzard repainted the text since our last paint, and
-- is restored only while our color is still installed.
function AdapterKit.NewTextColors()
    return {
        originals = AdapterKit.WeakSet(),
        roles = AdapterKit.WeakSet(),
        installed = AdapterKit.WeakSet(),
    }
end

local function InstallTextColor(colors, fontObject, role)
    local installed = colors.installed[fontObject]
    if not installed then
        installed = {}
        colors.installed[fontObject] = installed
    end
    installed[1], installed[2], installed[3], installed[4] = NS.Theme.GetColor(role)
    fontObject:SetTextColor(installed[1], installed[2], installed[3], installed[4])
end

local function MatchesColor(color, r, g, b, a)
    return color ~= nil and r ~= nil
        and color[1] == r and color[2] == g and color[3] == b and color[4] == a
end

function AdapterKit.SetTextColor(colors, fontObject, role, recapture)
    if Safety.IsForbidden(fontObject) or type((Field(fontObject, "SetTextColor"))) ~= "function" then
        return false
    end
    local r, g, b, a = Safety.ReadColor(fontObject, "GetTextColor")
    local original = colors.originals[fontObject]
    if not original then
        if r then colors.originals[fontObject] = { r, g, b, a } end
    elseif recapture and r and not MatchesColor(colors.installed[fontObject], r, g, b, a) then
        original[1], original[2], original[3], original[4] = r, g, b, a
    end
    colors.roles[fontObject] = role
    InstallTextColor(colors, fontObject, role)
    return true
end

function AdapterKit.RefreshTextColors(colors)
    for fontObject, role in pairs(colors.roles) do
        InstallTextColor(colors, fontObject, role)
    end
end

function AdapterKit.RestoreTextColors(colors)
    for fontObject, original in pairs(colors.originals) do
        if MatchesColor(colors.installed[fontObject], Safety.ReadColor(fontObject, "GetTextColor")) then
            fontObject:SetTextColor(original[1], original[2], original[3], original[4])
        end
    end
    colors.originals = AdapterKit.WeakSet()
    colors.roles = AdapterKit.WeakSet()
    colors.installed = AdapterKit.WeakSet()
end

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

local Kit = AdapterKit
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

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = SharedChrome.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            deferred = {},
            surfaces = Kit.WeakSet(),
        }
        SharedChrome.owners[owner] = state
    end
    return state, owner
end

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
    local button = _G.AddonCompartmentFrame
    if not button then return false end

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

local function SkinQueueStatus(state)
    if not NS.GenericWindows.IsCategoryEnabled("hud") then return false end
    local root = _G.QueueStatusFrame
    if not root then return false end
    local applied = ApplyGeneric(root, state.owner, QUEUE_MODE)
    local pool = Field(root, "statusEntriesPool")
    if type((Field(pool, "EnumerateActive"))) == "function" then
        local count = 0
        for entry in pool:EnumerateActive() do
            if count >= QUEUE_ENTRY_LIMIT then break end
            count = count + 1
            applied = ApplyGeneric(entry, state.owner, QUEUE_ENTRY_MODE) or applied
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

local function ApplyKind(state, kind)
    if not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    local applied = kindSkinners[kind](state) == true
    return applied, applied and "applied" or "missing"
end

local function RunOrDefer(state, suffix, callback)
    if not state.active then return false, "disabled" end
    local owner = state.owner
    local key = "shared-chrome:" .. tostring(owner) .. ":" .. tostring(suffix)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = SharedChrome.owners[owner]
        if current then current.deferred[key] = nil end
        if current and current.active then callback(current) end
    end)
    return ran == true, reason
end

local function RequestKindForOwners(kind)
    for _, state in pairs(SharedChrome.owners) do
        if state.active then
            RunOrDefer(state, kind, function(current)
                ApplyKind(current, kind)
            end)
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

local function HookMixinMethod(key, mixin, method, callback)
    if SharedChrome.hooks[key] then return true end
    if not Kit.HookFunction(mixin, method, callback) then return false end
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
        if not SharedChrome.callbackState[callback.key]
            and Kit.RegisterEventCallback(callback.event, callback.method, SharedChrome) then
            SharedChrome.callbackState[callback.key] = true
        end
    end
end

local function UnregisterCallbacks()
    for index = 1, #callbacks do
        local callback = callbacks[index]
        if SharedChrome.callbackState[callback.key] then
            Kit.UnregisterEventCallback(callback.event, SharedChrome)
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
            if not Kit.ContinueOnAddOnLoaded(addon, function() OnAddonLoaded(addon) end) then
                SharedChrome.waitingAddons[addon] = nil
                return
            end
        end
    end
end

function SharedChrome.Apply(owner)
    local state = OwnerState(owner)
    if not state.active then
        state.active = true
        SharedChrome.activeOwnerCount = SharedChrome.activeOwnerCount + 1
    end

    ScheduleAddonLoads()
    RegisterCallbacks()
    InstallHooks()

    local applied = 0
    local ran, reason = RunOrDefer(state, "apply", function(current)
        applied = ApplyAllNow(current)
    end)
    if not ran then return false, reason or "combat" end
    return true, applied > 0 and "applied" or "waiting"
end

function SharedChrome.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = SharedChrome.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    state.active = false
    Kit.CancelDeferred(state)
    Kit.HideSurfaces(state)

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
