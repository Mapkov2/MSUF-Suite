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

local DEFAULT_OWNER = "socialUI"
local SOCIAL_ADDON = "Blizzard_SocialUI"

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

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Path(object, ...)
    for index = 1, select("#", ...) do
        object = SafeField(object, select(index, ...))
        if not object then return nil end
    end
    return object
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("social UI " .. tostring(label), message)
    end
end

local function OwnerState(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = SocialUISkin.owners[parentOwner]
    if not state then
        state = {
            parentOwner = parentOwner,
            skinOwner = tostring(parentOwner) .. ":social-ui",
            active = false,
            frame = nil,
            surfaces = WeakSet(),
            cards = WeakSet(),
            tabs = WeakSet(),
            scrollBoxes = WeakSet(),
            deferred = {},
        }
        SocialUISkin.owners[parentOwner] = state
    end
    return state, parentOwner
end

local function CanDecorate(target)
    return target and NS.Safety
        and NS.Safety.CanDecorate(target, true)
end

local function CanCreateRegions(target)
    return target and NS.Safety
        and NS.Safety.CanCreateRegions(target, true)
end

local function CanControl(target)
    return target and NS.Safety
        and NS.Safety.CanControl(target, true)
        and NS.Safety.CanCreateRegions(target, true)
end

local function TrackSurface(state, target)
    if state and target then state.surfaces[target] = true end
end

local function Fade(state, region)
    if not state or not region or NS.IsCombatLocked() or not CanDecorate(region)
        or not NS.Cosmetics or type(NS.Cosmetics.Fade) ~= "function" then
        return false
    end
    local ok, faded = pcall(NS.Cosmetics.Fade, region, state.skinOwner)
    if not ok then Report("fade", faded) end
    return ok and faded == true
end

local function FadeFields(state, target, fields)
    for index = 1, #(fields or {}) do
        Fade(state, SafeField(target, fields[index]))
    end
end

local function FadeNineSlice(state, nineSlice)
    if not state or not nineSlice or NS.IsCombatLocked() or not CanDecorate(nineSlice)
        or not NS.Cosmetics or type(NS.Cosmetics.FadeNineSlice) ~= "function" then
        return false
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, nineSlice, state.skinOwner)
    if not ok then Report("nine slice", message) end
    return ok == true
end

local function Attach(state, target, spec)
    if not state or not target or NS.IsCombatLocked() or not CanCreateRegions(target)
        or not NS.Surface or type(NS.Surface.Attach) ~= "function" then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local ok, surface = pcall(NS.Surface.Attach, target, spec)
    if ok and surface then
        TrackSurface(state, target)
        return true
    end
    if not ok then Report("surface", surface) end
    return false
end

local function SkinButton(state, button, spec)
    if not state or not button or NS.IsCombatLocked() or not CanControl(button)
        or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function" then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    spec.useControlShape = spec.useControlShape ~= false
    local ok, applied = pcall(NS.ControlSkin.ApplyButton,
        button, state.skinOwner, spec)
    if ok and applied then
        TrackSurface(state, button)
        return true
    end
    if not ok then Report("button", applied) end
    return false
end

local function SkinSearchBox(state, searchBox)
    if not state or not searchBox or NS.IsCombatLocked() or not CanControl(searchBox)
        or not NS.ControlSkin or type(NS.ControlSkin.ApplySearchBox) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.ControlSkin.ApplySearchBox,
        searchBox, state.skinOwner, {
            role = "input",
            radius = 4,
            inset = 1,
            useControlShape = true,
            allowImplicitProtected = true,
        })
    if ok and applied then
        TrackSurface(state, searchBox)
        return true
    end
    if not ok then Report("search box", applied) end
    return false
end

local broadcastInputBorderFields = {
    "TopLeftBorder", "TopRightBorder", "TopBorder",
    "BottomLeftBorder", "BottomRightBorder", "BottomBorder",
    "LeftBorder", "RightBorder", "MiddleBorder",
}

local function SkinBattleNetDialog(state, dialog, broadcast)
    if not dialog then return false end
    local applied = Attach(state, dialog, {
        role = "popup", radius = 8, inset = 0,
    })
    local border = SafeField(dialog, "Border")
    if border then
        FadeNineSlice(state, border)
        Fade(state, SafeField(border, "Bg"))
    end
    if broadcast then
        local editBox = SafeField(dialog, "EditBox")
        applied = SkinSearchBox(state, editBox) or applied
        FadeFields(state, editBox, broadcastInputBorderFields)
        applied = SkinButton(state, SafeField(dialog, "UpdateButton"), {
            role = "buttonPrimary", radius = 5, inset = 1,
        }) or applied
        applied = SkinButton(state, SafeField(dialog, "CancelButton"), {
            role = "button", radius = 5, inset = 1,
        }) or applied
    end
    return applied
end

local ApplyState

local function DeferredKey(state, suffix)
    return "social-ui:" .. tostring(state.parentOwner) .. ":" .. tostring(suffix)
end

local function DeferApply(state, suffix)
    if not state or not state.active or not NS.CombatGate
        or type(NS.CombatGate.RunOrDefer) ~= "function" then
        return false, "disabled"
    end
    local parentOwner = state.parentOwner
    local key = DeferredKey(state, suffix)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = SocialUISkin.owners[parentOwner]
        if current then current.deferred[key] = nil end
        if current and current.active then
            local ok, applied, applyReason = pcall(ApplyState, current)
            if not ok then
                Report("deferred apply", applied)
            elseif applied == false and applyReason ~= "missing" then
                Report("deferred apply", applyReason)
            end
        end
    end)
    if ran then state.deferred[key] = nil end
    return ran == true, reason
end

local function ApplyOrDefer(state, suffix)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return DeferApply(state, suffix) end
    local ok, applied, reason = pcall(ApplyState, state)
    if not ok then
        Report(suffix, applied)
        return false, "failed"
    end
    return applied, reason
end

local function SkinBattleNetBar(state, frame)
    local bar = SafeField(frame, "BattleNetBar")
    if not bar then return end

    Attach(state, bar, {
        role = "navigation", radius = 6, inset = 0, keepGlassFill = false,
    })
    Fade(state, SafeField(bar, "Background"))

    local controls = SafeField(bar, "ControlsContainer")
    if not controls then return end
    Fade(state, SafeField(controls, "BattleNetBackground"))

    SkinButton(state, SafeField(controls, "OnlineStatusDropdown"), {
        role = "button", radius = 4, inset = 1,
        regions = { "Background" },
    })
    SkinButton(state, SafeField(controls, "BattleNetMenuButton"), {
        role = "button", radius = 4, inset = 1,
        regions = { "NormalTexture", "PushedTexture", "HighlightTexture" },
    })
end

local function SkinContent(state, content)
    if not content then return end

    FadeFields(state, content, { "TopDivider", "BottomDivider" })
    local filterBar = SafeField(content, "FilterBar")
    SkinSearchBox(state, SafeField(filterBar, "SearchBar"))
    SkinButton(state, SafeField(filterBar, "SearchFilterDropdown"), {
        role = "button", radius = 4, inset = 1,
        regions = { "Background" },
    })
    SkinButton(state, SafeField(content, "ActionButton"), {
        role = "button", activeRole = "buttonPrimary", radius = 5, inset = 1,
    })
end

local function IsShown(region)
    local getter = SafeField(region, "IsShown")
    if type(getter) ~= "function" then return false end
    local ok, shown = pcall(getter, region)
    return ok and shown == true
end

local function IsDescendantOf(target, ancestor)
    if not target or not ancestor then return false end
    local current = target
    for _ = 1, 12 do
        if current == ancestor then return true end
        local getter = SafeField(current, "GetParent")
        if type(getter) ~= "function" then return false end
        local ok, parent = pcall(getter, current)
        if not ok or not parent or parent == current then return false end
        current = parent
    end
    return false
end

local function SkinSocialCard(state, card, selected)
    if not state or not state.active or not card then return false end
    if not SafeField(card, "Background") or not SafeField(card, "PresenceHolder")
        or not SafeField(card, "PartyButton") or not SafeField(card, "GameIconHolder")
        or not SafeField(card, "TextHolder") or not SafeField(card, "StateDisplay")
        or not SafeField(card, "FriendName") then
        return false
    end
    state.cards[card] = true
    if NS.IsCombatLocked() then return false end
    local attached = Attach(state, card, {
        role = "card", activeRole = "navigationActive",
        radius = 5, inset = 0, listItem = true,
    })
    Fade(state, SafeField(card, "Background"))
    if attached and selected ~= nil and NS.Surface
        and type(NS.Surface.SetActive) == "function" then
        pcall(NS.Surface.SetActive, card, selected == true)
    end
    return attached
end

local function SkinSocialTab(state, tab, selected)
    if not state or not state.active or not tab then return false end
    state.tabs[tab] = true
    if NS.IsCombatLocked() then return false end
    local attached = Attach(state, tab, {
        role = "navigation", activeRole = "navigationActive",
        radius = 5, inset = 1,
    })
    -- Keep Icon, Count, SelectedTexture, TabGlow and HighlightTexture native.
    Fade(state, SafeField(tab, "Background"))
    if selected == nil then selected = IsShown(SafeField(tab, "SelectedTexture")) end
    if attached and NS.Surface and type(NS.Surface.SetActive) == "function" then
        pcall(NS.Surface.SetActive, tab, selected == true)
    end
    return attached
end

local function EnumerateActive(source, methodName, callback)
    local method = SafeField(source, methodName)
    if type(method) ~= "function" or type(callback) ~= "function" then return false end
    local ok, iterator, invariant, control = pcall(method, source)
    if not ok or type(iterator) ~= "function" then return false end
    for _ = 1, 64 do
        local iterOk, value = pcall(iterator, invariant, control)
        if not iterOk or value == nil then break end
        control = value
        callback(value)
    end
    return true
end

local function SkinTabs(state)
    local frame = state and state.frame
    return EnumerateActive(frame, "EnumerateTabs", function(tab)
        SkinSocialTab(state, tab)
    end)
end

local function ScrollBoxInitializedEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterFriendCards(state)
    local scrollBox = Path(state and state.frame, "FriendsList", "ScrollBox")
    local event = ScrollBoxInitializedEvent()
    if not scrollBox or not event then return false end

    if not state.scrollBoxes[scrollBox]
        and type(SafeField(scrollBox, "RegisterCallback")) == "function" then
        local function OnInitialized(_, card)
            SkinSocialCard(state, card)
        end
        local ok, message = pcall(scrollBox.RegisterCallback, scrollBox,
            event, OnInitialized, state)
        if ok then
            state.scrollBoxes[scrollBox] = event
        else
            Report("friends cards", message)
        end
    end

    local forEach = SafeField(scrollBox, "ForEachFrame")
    if type(forEach) == "function" then
        pcall(forEach, scrollBox, function(card) SkinSocialCard(state, card) end)
    end
    return state.scrollBoxes[scrollBox] ~= nil
end

local function InstallLifecycleHooks()
    if SocialUISkin.hooksInstalled or type(hooksecurefunc) ~= "function" then return end
    local installed = false

    if type(FriendsListSocialCardMixin) == "table"
        and type(FriendsListSocialCardMixin.Initialize) == "function" then
        local ok = pcall(hooksecurefunc, FriendsListSocialCardMixin, "Initialize", function(card)
            for _, state in pairs(SocialUISkin.owners) do
                local friendsList = SafeField(state.frame, "FriendsList")
                if state.active and IsDescendantOf(card, friendsList) then
                    SkinSocialCard(state, card)
                end
            end
        end)
        installed = ok or installed
    end

    if type(FriendsListSocialCardMixin) == "table"
        and type(FriendsListSocialCardMixin.SetSelected) == "function" then
        local ok = pcall(hooksecurefunc, FriendsListSocialCardMixin, "SetSelected", function(card, selected)
            if NS.IsCombatLocked() then return end
            for _, state in pairs(SocialUISkin.owners) do
                if state.active and state.cards[card] and NS.Surface
                    and type(NS.Surface.SetActive) == "function" then
                    pcall(NS.Surface.SetActive, card, selected == true)
                end
            end
        end)
        installed = ok or installed
    end

    if type(SocialUITabMixin) == "table" and type(SocialUITabMixin.SetChecked) == "function" then
        local ok = pcall(hooksecurefunc, SocialUITabMixin, "SetChecked", function(tab, checked)
            if NS.IsCombatLocked() then return end
            for _, state in pairs(SocialUISkin.owners) do
                if state.active and state.tabs[tab] and NS.Surface
                    and type(NS.Surface.SetActive) == "function" then
                    pcall(NS.Surface.SetActive, tab, checked == true)
                end
            end
        end)
        installed = ok or installed
    end

    if type(SocialUIFrameMixin) == "table" and type(SocialUIFrameMixin.RefreshTabs) == "function" then
        local ok = pcall(hooksecurefunc, SocialUIFrameMixin, "RefreshTabs", function(frame)
            if NS.IsCombatLocked() then return end
            for _, state in pairs(SocialUISkin.owners) do
                if state.active and state.frame == frame then SkinTabs(state) end
            end
        end)
        installed = ok or installed
    end

    SocialUISkin.hooksInstalled = installed
end

ApplyState = function(state)
    local frame = state and state.frame
    if not state or not state.active or not frame then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not CanCreateRegions(frame) then return false, "protected" end

    if not Attach(state, frame, { role = "shell", radius = 8, inset = 0 }) then
        return false, "shell"
    end

    FadeNineSlice(state, SafeField(frame, "NineSlice"))
    FadeFields(state, frame, {
        "Bg", "TopTileStreaks", "TopFade", "BottomFade",
    })
    Fade(state, Path(frame, "PortraitContainer", "portrait"))

    SkinButton(state, SafeField(frame, "CloseButton"), {
        role = "button", radius = 4, inset = 2,
    })
    SkinBattleNetBar(state, frame)
    SkinBattleNetDialog(state, SafeField(frame, "BattleNetUnavailableNoticeFrame"), false)
    SkinBattleNetDialog(state, SafeField(frame, "BattleNetBroadcastFrame"), true)

    for index = 1, #CONTENT_KEYS do
        SkinContent(state, SafeField(frame, CONTENT_KEYS[index]))
    end
    InstallLifecycleHooks()
    RegisterFriendCards(state)
    SkinTabs(state)

    return true, "applied"
end

local function IsAddonLoaded()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, SOCIAL_ADDON)
        return ok and (loaded == true or (loaded == nil and loadedOrLoading == true))
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, SOCIAL_ADDON)
        return ok and loaded == true
    end
    return _G.SocialUIFrame ~= nil
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

local function ScheduleLoad()
    if SocialUISkin.waiting then return true end
    if IsAddonLoaded() or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end

    SocialUISkin.waiting = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, SOCIAL_ADDON, function()
        SocialUISkin.waiting = false
        if not ApplyForActiveOwners() then
            Report("addon load", "SocialUIFrame is missing")
        end
    end)
    if not ok then
        SocialUISkin.waiting = false
        Report("addon load", message)
    end
    return ok == true
end

local function CancelDeferred(state)
    if not state then return end
    for key in pairs(state.deferred) do
        if NS.CombatGate and type(NS.CombatGate.Cancel) == "function" then
            NS.CombatGate.Cancel(key)
        end
        state.deferred[key] = nil
    end
end

local function DisableNow(state)
    if not state then return true end
    state.active = false
    CancelDeferred(state)

    for scrollBox, event in pairs(state.scrollBoxes) do
        local unregister = SafeField(scrollBox, "UnregisterCallback")
        if type(unregister) == "function" then
            pcall(unregister, scrollBox, event, state)
        end
    end
    state.scrollBoxes = WeakSet()
    state.cards = WeakSet()
    state.tabs = WeakSet()

    if NS.ControlSkin and type(NS.ControlSkin.DisableOwner) == "function" then
        pcall(NS.ControlSkin.DisableOwner, state.skinOwner)
    end
    if NS.Cosmetics and type(NS.Cosmetics.RestoreOwner) == "function" then
        pcall(NS.Cosmetics.RestoreOwner, state.skinOwner)
    end
    if NS.Surface and type(NS.Surface.SetVisible) == "function" then
        for target in pairs(state.surfaces) do
            pcall(NS.Surface.SetVisible, target, false)
        end
    end

    SocialUISkin.owners[state.parentOwner] = nil
    return true
end

function SocialUISkin.Apply(parentOwner)
    local state
    state, parentOwner = OwnerState(parentOwner)
    CancelDeferred(state)
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
        CancelDeferred(state)
        if NS.CombatGate and type(NS.CombatGate.RunOrDefer) == "function" then
            local key = DeferredKey(state, "disable")
            state.deferred[key] = true
            NS.CombatGate.RunOrDefer(key, function()
                local current = SocialUISkin.owners[parentOwner]
                if current then
                    current.deferred[key] = nil
                    DisableNow(current)
                end
            end)
        end
        return false, "combat"
    end

    return DisableNow(state)
end

return SocialUISkin
