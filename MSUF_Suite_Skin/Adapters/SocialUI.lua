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
-- paints only verified backgrounds plus explicit shell/divider/control fields,
-- outside combat and without changing geometry.
local SocialUISkin = {
    owners = {},
    waiting = false,
    hooksInstalled = false,
}
NS.SocialUISkin = SocialUISkin

local Field = NS.Safety.Field
local Kit = NS.AdapterKit

local DEFAULT_OWNER = "socialUI"
local SOCIAL_ADDON = "Blizzard_SocialUI"
local TAB_LIMIT = 64

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

local function OwnerState(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = SocialUISkin.owners[parentOwner]
    if not state then
        state = {
            parentOwner = parentOwner,
            owner = tostring(parentOwner) .. ":social-ui",
            active = false,
            frame = nil,
            surfaces = Kit.WeakSet(),
            cards = Kit.WeakSet(),
            tabs = Kit.WeakSet(),
            scrollBoxes = Kit.WeakSet(),
            deferred = {},
        }
        state.visitCard = function(card) SkinSocialCard(state, card) end
        SocialUISkin.owners[parentOwner] = state
    end
    return state
end

local function SkinBattleNetDialog(state, dialog, broadcast)
    if not dialog then return false end
    local applied = Kit.Attach(state, dialog, DIALOG_SPEC)
    local border = Field(dialog, "Border")
    if border then
        Kit.FadeNineSlice(state, border)
        Kit.Fade(state, Field(border, "Bg"))
    end
    if broadcast then
        local editBox = Field(dialog, "EditBox")
        applied = Kit.SkinControl(state, editBox, SEARCH_SPEC, "ApplySearchBox") or applied
        Kit.FadeFields(state, editBox, broadcastInputBorderFields)
        applied = Kit.SkinControl(state, Field(dialog, "UpdateButton"), UPDATE_SPEC) or applied
        applied = Kit.SkinControl(state, Field(dialog, "CancelButton"), CANCEL_SPEC) or applied
    end
    return applied
end

local function SkinBattleNetBar(state, frame)
    local bar = Field(frame, "BattleNetBar")
    if not bar then return end

    Kit.Attach(state, bar, BATTLE_NET_BAR_SPEC)
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
    if not state or not state.active or not card or not Kit.HasFields(card, SOCIAL_CARD_FIELDS) then
        return false
    end
    state.cards[card] = true
    if NS.IsCombatLocked() then return false end
    local attached = Kit.Attach(state, card, CARD_SPEC)
    Kit.Fade(state, Field(card, "Background"))
    return attached
end

local function SkinSocialTab(state, tab)
    if not state or not state.active or not tab then return false end
    state.tabs[tab] = true
    if NS.IsCombatLocked() then return false end
    local attached = Kit.Attach(state, tab, TAB_SPEC)
    -- Keep Icon, Count, SelectedTexture, TabGlow and HighlightTexture native.
    Kit.Fade(state, Field(tab, "Background"))
    if attached then
        NS.Surface.SetActive(tab, Kit.IsShown(Field(tab, "SelectedTexture")))
    end
    return attached
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

local function OnFriendCardInitialized(state, card)
    SkinSocialCard(state, card)
end

local function RegisterFriendCards(state)
    local scrollBox = Kit.Path(state.frame, "FriendsList", "ScrollBox")
    if not scrollBox then return false end
    if not state.scrollBoxes[scrollBox] then
        state.scrollBoxes[scrollBox] = Kit.RegisterRowCallback(scrollBox,
            OnFriendCardInitialized, state)
    end
    Kit.ForEachRow(scrollBox, state.visitCard)
    return state.scrollBoxes[scrollBox] ~= nil
end

local function OnCardInitialize(card)
    for _, state in pairs(SocialUISkin.owners) do
        if state.active and Kit.IsDescendantOf(card, Field(state.frame, "FriendsList")) then
            SkinSocialCard(state, card)
        end
    end
end

-- Mirrors Blizzard's own selection into the active state of our surface.
local function SyncActive(target, trackedKey, active)
    if NS.IsCombatLocked() then return end
    for _, state in pairs(SocialUISkin.owners) do
        if state.active and state[trackedKey][target] then
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

local function OnTabsRefreshed(frame)
    if NS.IsCombatLocked() then return end
    for _, state in pairs(SocialUISkin.owners) do
        if state.active and state.frame == frame then SkinTabs(state) end
    end
end

local function InstallLifecycleHooks()
    if SocialUISkin.hooksInstalled then return end
    local installed = Kit.HookFunction(_G.FriendsListSocialCardMixin, "Initialize", OnCardInitialize)
    installed = Kit.HookFunction(_G.FriendsListSocialCardMixin, "SetSelected", OnCardSelected)
        or installed
    installed = Kit.HookFunction(_G.SocialUITabMixin, "SetChecked", OnTabChecked) or installed
    installed = Kit.HookFunction(_G.SocialUIFrameMixin, "RefreshTabs", OnTabsRefreshed) or installed
    SocialUISkin.hooksInstalled = installed
end

local function ApplyState(state)
    local frame = state and state.frame
    if not state or not state.active or not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanCreateRegions(frame, true) then return false, "protected" end
    if not Kit.Attach(state, frame, SHELL_SPEC) then return false, "shell" end

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
    InstallLifecycleHooks()
    RegisterFriendCards(state)
    SkinTabs(state)

    return true, "applied"
end

local function DeferredKey(state, suffix)
    return "social-ui:" .. tostring(state.parentOwner) .. ":" .. tostring(suffix)
end

local function DeferApply(state, suffix)
    if not state or not state.active then return false, "disabled" end
    local parentOwner = state.parentOwner
    local key = DeferredKey(state, suffix)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = SocialUISkin.owners[parentOwner]
        if current then current.deferred[key] = nil end
        if current and current.active then
            local applied, applyReason = ApplyState(current)
            if applied == false and applyReason ~= "missing" then
                NS.ReportError("social UI deferred apply", applyReason)
            end
        end
    end)
    if ran then state.deferred[key] = nil end
    return ran == true, reason
end

local function ApplyOrDefer(state, suffix)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return DeferApply(state, suffix) end
    return ApplyState(state)
end

local function ApplyForActiveOwners()
    local frame = _G.SocialUIFrame
    if not frame then return false end
    for _, state in pairs(SocialUISkin.owners) do
        if state.active then
            state.frame = frame
            ApplyOrDefer(state, "load")
        end
    end
    return true
end

local function OnSocialLoaded()
    SocialUISkin.waiting = false
    if not ApplyForActiveOwners() then
        NS.ReportError("social UI addon load", "SocialUIFrame is missing")
    end
end

local function ScheduleLoad()
    if SocialUISkin.waiting then return true end
    if NS.Client.IsAddOnLoaded(SOCIAL_ADDON) then return false end
    SocialUISkin.waiting = true
    if not Kit.ContinueOnAddOnLoaded(SOCIAL_ADDON, OnSocialLoaded) then
        SocialUISkin.waiting = false
        return false
    end
    return true
end

local function DisableNow(state)
    if not state then return true end
    state.active = false
    Kit.CancelDeferred(state)

    for scrollBox, event in pairs(state.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, event, state)
    end
    state.scrollBoxes = Kit.WeakSet()
    state.cards = Kit.WeakSet()
    state.tabs = Kit.WeakSet()

    NS.ControlSkin.DisableOwner(state.owner)
    NS.Cosmetics.RestoreOwner(state.owner)
    Kit.HideSurfaces(state)

    SocialUISkin.owners[state.parentOwner] = nil
    return true
end

function SocialUISkin.Apply(parentOwner)
    local state = OwnerState(parentOwner)
    Kit.CancelDeferred(state)
    state.active = true
    state.frame = _G.SocialUIFrame
    if not state.frame then
        if ScheduleLoad() then return true, "waiting" end
        return false, "missing"
    end
    return ApplyOrDefer(state, "apply")
end

function SocialUISkin.Disable(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = SocialUISkin.owners[parentOwner]
    if not state then return true end

    if NS.IsCombatLocked() then
        state.active = false
        Kit.CancelDeferred(state)
        local key = DeferredKey(state, "disable")
        state.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            local current = SocialUISkin.owners[parentOwner]
            if current then
                current.deferred[key] = nil
                DisableNow(current)
            end
        end)
        return false, "combat"
    end

    return DisableNow(state)
end

return SocialUISkin
