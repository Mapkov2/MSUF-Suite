local _, NS = ...

-- Exact native-chrome adapter for Retail's Social UI. The field contract is
-- verified against Gethe/wow-ui-source upstream/live 8ea15b61e45c0ed4eba01439c90757f86eb78d34:
--
--   Blizzard_SocialUI/Mainline/SocialUI.xml and SocialUITemplates.xml
--   Blizzard_SocialUI/Mainline/SocialUI.lua
--   Blizzard_SocialUIShared/SocialUISharedTemplates.xml
--
-- Social-card data, icons, text, actions, pooled-tab state, ScrollBoxes,
-- spinners and side-window content remain entirely Blizzard-owned. The adapter
-- paints only verified backgrounds and explicit shell/divider/control fields.
-- Shared window controls own the root's saved position and scale.
local SocialUISkin = {
    hooksInstalled = false,
    frameHooks = setmetatable({}, { __mode = "k" }),
}
NS.SocialUISkin = SocialUISkin

local Safety, Kit = NS.Safety, NS.AdapterKit
local Field = Safety.Field

local DEFAULT_OWNER = "socialUI"
local TAB_LIMIT = 64
local TrackMotion, ReleaseMotion = function() end, function() end
function SocialUISkin.SetMotionProvider(track, release) TrackMotion, ReleaseMotion = track, release end


-- SocialUIFrameMixin:InitializeTabDefinitions creates these exact parentKeys.
-- The list is fixed deliberately; supported content is never discovered by
-- walking the frame tree.
local CONTENT_KEYS = {
    "FriendsList",
    "RecentAlliesList",
    "QuickJoinFrame",
    "FriendRequestsList",
    "RecruitAFriendFrame",
    "RaidFrame",
}

local SHELL_SPEC = { role = "shell", radius = 8, inset = 0 }
local DIALOG_SPEC = { role = "popup", radius = 8, inset = 0 }
local BATTLE_NET_BAR_SPEC = { role = "navigation", radius = 6, inset = 0, keepGlassFill = false }
local CARD_SPEC = {
    role = "card", activeRole = "navigationActive",
    radius = 5, inset = 0, listItem = true,
}
local TAB_SPEC = {
    role = "navigation", activeRole = "navigationActive",
    radius = 5, inset = 1,
}
local SEARCH_SPEC = { role = "input", radius = 4, inset = 1, useControlShape = true }
local CLOSE_SPEC = { role = "button", radius = 4, inset = 2 }
local DROPDOWN_SPEC = { role = "button", radius = 4, inset = 1, regions = { "Background" } }
local MENU_BUTTON_SPEC = {
    role = "button", radius = 4, inset = 1,
    regions = { "NormalTexture", "PushedTexture", "HighlightTexture" },
}
local ACTION_SPEC = { role = "button", activeRole = "buttonPrimary", radius = 5, inset = 1 }
local UPDATE_SPEC = { role = "buttonPrimary", radius = 5, inset = 1 }
local CANCEL_SPEC = { role = "button", radius = 5, inset = 1 }

local SHELL_FIELDS = { "Bg", "TopTileStreaks", "TopFade", "BottomFade" }
local CONTENT_DIVIDERS = { "TopDivider", "BottomDivider" }
local SOCIAL_CARD_FIELDS = {
    "Background", "PresenceHolder", "PartyButton", "GameIconHolder",
    "TextHolder", "StateDisplay", "FriendName",
}
local broadcastInputBorderFields = {
    "TopLeftBorder", "TopRightBorder", "TopBorder",
    "BottomLeftBorder", "BottomRightBorder", "BottomBorder",
    "LeftBorder", "RightBorder", "MiddleBorder",
}

local SkinSocialCard

-- Owner state per parent owner.
local Owners = Kit.NewOwners({
    prefix = "social-ui",
    default = DEFAULT_OWNER,
    keyField = "parentOwner",
    surfaces = true,
    init = function(state, parentOwner)
        state.owner = tostring(parentOwner) .. ":social-ui"
        state.cards = Kit.WeakSet()
        state.tabs = Kit.WeakSet()
        state.scrollBoxes = Kit.WeakSet()
        state.visitCard = function(card) SkinSocialCard(state, card) end
    end,
})
SocialUISkin.owners = Owners.owners

local function SkinBattleNetDialog(state, dialog, broadcast)
    if not Kit.Attach(state, dialog, DIALOG_SPEC) then return end
    local border = Field(dialog, "Border")
    if border then
        Kit.FadeNineSlice(state, border)
        Kit.Fade(state, Field(border, "Bg"))
    end
    if broadcast then
        local editBox = Field(dialog, "EditBox")
        if Kit.SkinControl(state, editBox, SEARCH_SPEC, "ApplySearchBox") then
            Kit.FadeFields(state, editBox, broadcastInputBorderFields)
        end
        Kit.SkinControl(state, Field(dialog, "UpdateButton"), UPDATE_SPEC)
        Kit.SkinControl(state, Field(dialog, "CancelButton"), CANCEL_SPEC)
    end
end

local function SkinBattleNetBar(state, frame)
    local bar = Field(frame, "BattleNetBar")
    if not Kit.Attach(state, bar, BATTLE_NET_BAR_SPEC) then return end
    Kit.Fade(state, Field(bar, "Background"))

    local controls = Field(bar, "ControlsContainer")
    if not controls then return end
    Kit.Fade(state, Field(controls, "BattleNetBackground"))
    Kit.SkinControl(state, Field(controls, "OnlineStatusDropdown"), DROPDOWN_SPEC)
    Kit.SkinControl(state, Field(controls, "BattleNetMenuButton"), MENU_BUTTON_SPEC)
end

local function SkinContent(state, content)
    if not content then return end
    Kit.FadeFields(state, content, CONTENT_DIVIDERS)
    local filterBar = Field(content, "FilterBar")
    Kit.SkinControl(state, Field(filterBar, "SearchBar"), SEARCH_SPEC, "ApplySearchBox")
    Kit.SkinControl(state, Field(filterBar, "SearchFilterDropdown"), DROPDOWN_SPEC)
    Kit.SkinControl(state, Field(content, "ActionButton"), ACTION_SPEC)
end

-- Selection is mirrored later by the SetSelected hook (OnCardSelected).
SkinSocialCard = function(state, card)
    if not state.active or not Safety.Public(card) or Safety.IsForbidden(card)
        or not Kit.HasFields(card, SOCIAL_CARD_FIELDS) then
        return false
    end
    if not Kit.Ensure(state, card, CARD_SPEC) then return false end
    state.cards[card] = true
    Kit.Fade(state, Field(card, "Background"))
    return true
end

local function SkinSocialTab(state, tab)
    if not state.active or not Kit.Ensure(state, tab, TAB_SPEC) then return false end
    state.tabs[tab] = true
    -- Keep Icon, Count, SelectedTexture, TabGlow and HighlightTexture native.
    Kit.Fade(state, Field(tab, "Background"))
    NS.Surface.SetActive(tab, Kit.IsShown(Field(tab, "SelectedTexture")))
    return true
end

local function SkinTabs(state)
    local frame = state.frame
    if NS.Safety.IsForbidden(frame) or type((Field(frame, "EnumerateTabs"))) ~= "function" then
        return false
    end
    local count = 0
    for tab in frame:EnumerateTabs() do
        if count >= TAB_LIMIT then break end
        count = count + 1
        SkinSocialTab(state, tab)
    end
    return true
end

-- The friends ScrollBox reports every new and recycled card here, after
-- FriendsListSocialCardMixin:Initialize, so this is the one card pass.
local function OnFriendCardInitialized(state, card)
    if state.active and not Kit.IsHidden(state.frame) then SkinSocialCard(state, card) end
end

local function RegisterFriendCards(state)
    TrackMotion(Kit.Path(state.frame, "RecentAlliesList", "ScrollBox"), state)
    local scrollBox = Kit.Path(state.frame, "FriendsList", "ScrollBox")
    if not Safety.CanDecorate(scrollBox, not NS.IsCombatLocked()) then return false end
    if not state.scrollBoxes[scrollBox] then
        state.scrollBoxes[scrollBox] = Kit.RegisterRowCallback(scrollBox,
            OnFriendCardInitialized, state)
    end
    Kit.ForEachRow(scrollBox, state.visitCard)
    return state.scrollBoxes[scrollBox] ~= nil
end

-- Mirrors Blizzard's own selection into the active state of our surface.
local function SyncActive(target, trackedKey, active)
    if not Safety.Public(active) or not Safety.Public(target) then return end
    for _, state in pairs(SocialUISkin.owners) do
        if state.active and state[trackedKey][target] and not Kit.IsHidden(state.frame) then
            NS.Surface.SetActive(target, active == true)
        end
    end
end

local function OnCardSelected(card, selected)
    SyncActive(card, "cards", selected)
end

local function OnTabChecked(tab, checked)
    SyncActive(tab, "tabs", checked)
end

-- RefreshTabStates only checks the selected tab (SetChecked on each), so a
-- tab this owner already skinned just follows its selection. Tabs from
-- before the SetChecked mixin hook are synced here as well.
local function SyncTabStates(state)
    local frame = state.frame
    if NS.Safety.IsForbidden(frame) or type((Field(frame, "EnumerateTabs"))) ~= "function" then
        return
    end
    local count = 0
    for tab in frame:EnumerateTabs() do
        if count >= TAB_LIMIT then break end
        count = count + 1
        if state.tabs[tab] then
            NS.Surface.SetActive(tab, Kit.IsShown(Field(tab, "SelectedTexture")))
        else
            SkinSocialTab(state, tab)
        end
    end
end

-- SocialUIFrameMixin:RefreshTabs releases the tab pool and acquires one tab
-- per available tab type; RefreshTabStates then checks the selected one.
-- Both run on SocialUIFrame's own copy of the mixin (Mixin() copied it when
-- Blizzard_SocialUI created the frame), so the frame instance is hooked.
local function OnTabsRefreshed(frame, statesOnly)
    if Kit.IsHidden(frame) then return end
    for _, state in pairs(SocialUISkin.owners) do
        if state.active and state.frame == frame then
            if statesOnly then SyncTabStates(state) else SkinTabs(state) end
        end
    end
end

local function OnTabsRebuilt(frame)
    OnTabsRefreshed(frame, false)
end

local function OnTabStatesRefreshed(frame)
    OnTabsRefreshed(frame, true)
end

-- Every hook runs inside Blizzard's own call (RefreshTabStates checks each
-- tab in a loop), so each is its own error boundary.
local Isolated = NS.Safety.Isolated

local OnTabsRebuiltHook = Isolated(OnTabsRebuilt)
local OnTabStatesRefreshedHook = Isolated(OnTabStatesRefreshed)
local OnCardSelectedHook = Isolated(OnCardSelected)
local OnTabCheckedHook = Isolated(OnTabChecked)

local function HookFrameTabs(frame)
    if not frame or SocialUISkin.frameHooks[frame] then return end
    local installed = Kit.HookFunction(frame, "RefreshTabs", OnTabsRebuiltHook)
    installed = Kit.HookFunction(frame, "RefreshTabStates", OnTabStatesRefreshedHook) or installed
    SocialUISkin.frameHooks[frame] = installed
end

-- Pooled cards and tabs are created later from their (hooked) mixins.
local function InstallLifecycleHooks(frame)
    HookFrameTabs(frame)
    if SocialUISkin.hooksInstalled then return end
    local installed = Kit.HookFunction(_G.FriendsListSocialCardMixin, "SetSelected", OnCardSelectedHook)
    installed = Kit.HookFunction(_G.SocialUITabMixin, "SetChecked", OnTabCheckedHook) or installed
    SocialUISkin.hooksInstalled = installed
end

local ApplyOrDefer

local function ApplyState(state)
    local frame = state.frame
    local locked = NS.IsCombatLocked()
    if not Safety.CanCreateRegions(frame, not locked) then
        return false, locked and "combat" or "protected"
    end
    local shell = Kit.Attach(state, frame, SHELL_SPEC)
    if shell or locked then NS.WindowControls.Attach(frame, state.owner) end
    if not shell then return false, "shell" end

    Kit.FadeNineSlice(state, Field(frame, "NineSlice"))
    Kit.FadeFields(state, frame, SHELL_FIELDS)
    Kit.Fade(state, Kit.Path(frame, "PortraitContainer", "portrait"))

    Kit.SkinControl(state, Field(frame, "CloseButton"), CLOSE_SPEC)
    SkinBattleNetBar(state, frame)
    SkinBattleNetDialog(state, Field(frame, "BattleNetUnavailableNoticeFrame"), false)
    SkinBattleNetDialog(state, Field(frame, "BattleNetBroadcastFrame"), true)

    for index = 1, #CONTENT_KEYS do
        SkinContent(state, Field(frame, CONTENT_KEYS[index]))
    end
    InstallLifecycleHooks(frame)
    RegisterFriendCards(state)
    SkinTabs(state)

    return true, "applied"
end

-- The pass a combat request runs afterwards, for the owner's state then.
local function ApplyAfterCombat(state)
    local applied, reason = ApplyOrDefer(state)
    if applied == false and reason ~= "missing" then
        NS.ReportError("social UI deferred apply", reason)
    end
end

ApplyOrDefer = function(state)
    if not state.active then return false, "disabled" end
    local frame = state.frame
    if not frame then return false, "missing" end
    -- The native OnShow initializes the selected tab and list before we paint.
    if Kit.DeferHidden(frame, state, ApplyOrDefer, state) then return true, "deferred" end
    if NS.IsCombatLocked() then
        -- Paint unprotected regions now and retry any protected parts after combat.
        Owners.RunOrDefer(state, "apply", ApplyAfterCombat)
    end
    return ApplyState(state)
end

local function DisableNow(state)
    if not state then return true end
    state.active = false
    ReleaseMotion(state)
    Kit.CancelDeferred(state)

    for scrollBox, event in pairs(state.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, event, state)
    end
    state.scrollBoxes = Kit.WeakSet()
    state.cards = Kit.WeakSet()
    state.tabs = Kit.WeakSet()

    NS.WindowControls.DisableOwner(state.owner)
    NS.ControlSkin.DisableOwner(state.owner)
    NS.Cosmetics.RestoreOwner(state.owner)
    Kit.HideSurfaces(state)

    Owners.Forget(state)
    return true
end

function SocialUISkin.Apply(parentOwner)
    local state = Owners.State(parentOwner)
    Kit.CancelDeferred(state)
    state.active = true
    -- Blizzard_SocialUI is not load-on-demand on 12.1.0, 12.1.5 and Forever:
    -- SocialUIFrame exists before this load-on-demand skin loads.
    state.frame = _G.SocialUIFrame
    return ApplyOrDefer(state)
end

-- In combat the disable runs once afterwards; Apply cancels it first.
function SocialUISkin.Disable(parentOwner)
    local state = SocialUISkin.owners[parentOwner or DEFAULT_OWNER]
    if not state then return true end
    return Owners.DisableOrDefer(state, DisableNow)
end

return SocialUISkin
