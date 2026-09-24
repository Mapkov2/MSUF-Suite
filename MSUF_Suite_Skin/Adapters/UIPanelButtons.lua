local _, NS = ...

-- UIPanelButtonTemplate is the source of Blizzard's legacy red three-piece
-- buttons. Modern Blizzard UI uses SharedButtonTemplate and its red/gold-red
-- size variants instead. Catalog traversal covers buttons that already belong
-- to a verified Blizzard root; these narrowly scoped visibility hooks cover
-- both families even when Blizzard constructed them before MapkoSkin loaded,
-- without scanning UIParent or replacing any action, hover, or state script.
local UIPanelButtons = {
    active = false,
    legacyHooked = false,
    sharedHooked = false,
    iconHooked = false,
    closeBorderHooked = false,
    staticPopupHooked = false,
    staticPopupCloseHooked = false,
    staticPopupLoadRegistered = false,
    tracked = setmetatable({}, { __mode = "k" }),
    pendingIconArtKits = setmetatable({}, { __mode = "k" }),
}
NS.UIPanelButtons = UIPanelButtons

local OWNER = "uipanel-buttons"
local DEFER_KEY = "uipanel-buttons:late"
local regions = { "Left", "Middle", "Right", "Center" }
local sharedRegions = { "Left", "Center", "Right" }
local sharedRedAtlases = {
    ["128-RedButton"] = true,
    ["128-GoldRedButton"] = true,
}
local InstallHooks

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Getter(object, method)
    local getter = SafeField(object, method)
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object)
    return ok and value or nil
end

local function Enabled()
    return UIPanelButtons.active
        and NS.DB and NS.DB.enabled ~= false
        and (not NS.DB.skins or NS.DB.skins.blizzardWindows ~= false)
end

local function SkinButton(button, family)
    if not Enabled() or not button then
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
        return false, "combat"
    end
    local allowImplicitProtected = family == "staticpopup"
    if not NS.Safety or not NS.Safety.CanControl(button, allowImplicitProtected) then
        return false, "protected"
    end

    if family == "icon" then
        if not NS.Checkmarks then return false, "unavailable" end
        return NS.Checkmarks.TrackButton(button, OWNER), nil
    end

    if family == "dialogclose" or family == "dialogminimize" then
        if not NS.WindowActionSkin then return false, "unavailable" end
        local kind = family == "dialogclose" and "close" or "minimize"
        local state, reason = NS.WindowActionSkin.SyncNativeVisual(button, OWNER, kind)
        return state ~= nil, reason
    end

    if family == "quickjoin" then
        if not NS.Checkmarks then return false, "unavailable" end
        local changed = false
        for _, definition in ipairs({
            { SafeField(button, "FriendsButton"), "blizzardExpand" },
            { SafeField(button, "QueueButton"), "blizzardExpand" },
            { SafeField(button, "FlashingLayer"), "blizzardExpandHover" },
            { Getter(button, "GetHighlightTexture"), "blizzardExpandHover" },
        }) do
            changed = NS.Checkmarks.TrackTexture(definition[1], OWNER, definition[2])
                or changed
        end
        return changed, nil
    end

    if family == "staticpopup" then
        local nativeNormal = Getter(button, "GetNormalTexture")
        local state, reason = NS.ControlSkin.ApplyButton(button, OWNER, {
            role = "button",
            activeRole = "buttonPrimary",
            useControlShape = true,
            pillHeight = 20,
            inset = 1,
            allowImplicitProtected = true,
        })
        if not state then return false, reason end

        -- StaticPopupButtonTemplate is not a UIPanelButtonTemplate. It owns
        -- four full UI-DialogBox-Button state textures and an optional pulse
        -- glow, so the generic UIPanelButton_OnShow hook can never see it.
        -- Keep Blizzard's click/text/enable logic, but replace those exact
        -- visual states before a death popup can first appear in combat.
        if nativeNormal then pcall(NS.Cosmetics.Fade, nativeNormal, OWNER) end
        local flash = SafeField(button, "Flash")
        if flash then pcall(NS.Cosmetics.SuppressVertexAlpha, flash, OWNER) end
        return true, nil
    end

    local shared = family == "shared"
    local apply = shared and NS.ControlSkin.ApplyThreeSliceButton
        or NS.ControlSkin.ApplyUIPanelButton
    local state, reason = apply(button, OWNER, {
        role = "button",
        useControlShape = true,
        regions = shared and sharedRegions or regions,
    })
    return state ~= nil, reason
end

-- QuickJoinToastButton is a permanently constructed Blizzard control whose
-- friends/queue glyph and native gold button body share the same atlas. Keep
-- the semantic glyph, but neutralize/recolor the exact four source-verified
-- textures instead of hiding the combined art or scanning adjacent UIParent.
local function PrimeQuickJoinToast()
    local button = _G.QuickJoinToastButton
    if not button then return false end
    UIPanelButtons.tracked[button] = "quickjoin"
    return SkinButton(button, "quickjoin")
end

-- The DEATH dialog is first shown while the player is dead and commonly still
-- combat-locked. Its four StaticPopup roots and button containers already
-- exist out of combat, so prime exactly those roots now. This avoids creating
-- regions or replacing button state textures from the death/combat path.
local function SkinStaticPopup(popup)
    if not popup then return false end

    local buttons = {}
    local seen = setmetatable({}, { __mode = "k" })
    local function Add(button)
        if button and not seen[button] then
            seen[button] = true
            buttons[#buttons + 1] = button
        end
    end

    local getButtons = SafeField(popup, "GetButtons")
    if type(getButtons) == "function" then
        pcall(function()
            local values = getButtons(popup)
            if type(values) == "table" then
                for index = 1, #values do Add(values[index]) end
            end
        end)
    end

    local container = SafeField(popup, "ButtonContainer")
    local array = SafeField(container, "Buttons")
    if type(array) == "table" then
        for index = 1, #array do Add(array[index]) end
    end
    for index = 1, 4 do
        Add(SafeField(container, "Button" .. index))
        Add(SafeField(popup, "Button" .. index))
        local name = Getter(popup, "GetName")
        if type(name) == "string" and name ~= "" then
            Add(_G[name .. "Button" .. index])
        end
    end
    Add(SafeField(popup, "ExtraButton"))

    local applied = false
    for index = 1, #buttons do
        local button = buttons[index]
        UIPanelButtons.tracked[button] = "staticpopup"
        local changed = SkinButton(button, "staticpopup")
        applied = changed == true or applied
    end
    return applied
end

local function PrimeStaticPopups()
    if NS.GenericWindows and type(NS.GenericWindows.IsCategoryEnabled) == "function"
        and not NS.GenericWindows.IsCategoryEnabled("utility") then
        return false
    end

    local applied = false
    for index = 1, 4 do
        local popup = _G["StaticPopup" .. index]
        applied = SkinStaticPopup(popup) or applied
    end
    return applied
end

local function OnGameDialogButtonsSetup(popup)
    if not Enabled() or NS.IsCombatLocked() then return end
    SkinStaticPopup(popup)
end

local function OnGameDialogCloseSetup(popup, dialogInfo)
    if not Enabled() or not popup or not dialogInfo or not dialogInfo.closeButton then return end
    local button = SafeField(popup, "CloseButton")
    if not button or not NS.WindowActionSkin then return end
    local family = dialogInfo.closeButtonIsHide and "dialogclose" or "dialogminimize"
    UIPanelButtons.tracked[button] = family
    local kind = family == "dialogclose" and "close" or "minimize"
    NS.WindowActionSkin.AdoptNativeVisual(button, OWNER, kind)
end

local function RegisterStaticPopupLoad()
    if UIPanelButtons.staticPopupLoadRegistered then return true end
    if not EventUtil or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    UIPanelButtons.staticPopupLoadRegistered = true
    local ok = pcall(EventUtil.ContinueOnAddOnLoaded, "Blizzard_StaticPopup_Game", function()
        InstallHooks()
        if not Enabled() then return end
        if NS.IsCombatLocked() then
            NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
            return
        end
        PrimeStaticPopups()
    end)
    if not ok then UIPanelButtons.staticPopupLoadRegistered = false end
    return ok == true
end

local function OnUIPanelButtonShown(button)
    if not button then
        return
    end
    -- Visibility callbacks can run while opening combat UI. Do not retain or
    -- mutate a foreign control in that path; the next out-of-combat show (or a
    -- bounded adapter refresh) will capture it.
    if NS.IsCombatLocked() then return end
    UIPanelButtons.tracked[button] = "legacy"
    SkinButton(button, "legacy")
end

local function IsSharedRedButton(button)
    if not button then return false end
    local ok, atlasName = pcall(function() return button.atlasName end)
    if not ok or not sharedRedAtlases[atlasName] then return false end
    return button.Left ~= nil and button.Center ~= nil and button.Right ~= nil
end

local function OnSharedButtonShown(controller)
    if NS.IsCombatLocked() then return end
    local ok, button = pcall(function() return controller and controller:GetParent() end)
    if not ok or not IsSharedRedButton(button) then return end
    UIPanelButtons.tracked[button] = "shared"
    SkinButton(button, "shared")
end

local function OnIconArtChanged(button, artKit)
    if not button or not NS.Checkmarks then return end
    local isRed = NS.Checkmarks.IsRedButtonArtKit(artKit)
    local wasTracked = UIPanelButtons.tracked[button] == "icon"

    if not Enabled() then
        UIPanelButtons.tracked[button] = isRed and "icon" or nil
        return
    end
    if NS.IsCombatLocked() then
        UIPanelButtons.pendingIconArtKits[button] = artKit
        NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
        return
    end

    local actionKind = NS.Checkmarks.DetectWindowAction(button)
    local wasAction = NS.WindowActionSkin
        and NS.WindowActionSkin.IsApplied(button) == true
    if (wasAction or actionKind) and NS.WindowActionSkin
        and type(NS.WindowActionSkin.SyncButtonArtKit) == "function" then
        local synced = NS.WindowActionSkin.SyncButtonArtKit(
            button, OWNER, artKit, actionKind)
        if not synced then
            if NS.WindowActionSkin.GetOwner(button) ~= OWNER then
                UIPanelButtons.tracked[button] = nil
            end
            return
        end
    end

    if isRed then
        UIPanelButtons.tracked[button] = "icon"
        SkinButton(button, "icon")
    elseif wasTracked or wasAction then
        NS.Checkmarks.UntrackButton(button, OWNER)
        UIPanelButtons.tracked[button] = nil
    end
end

local function OnCloseButtonBorderChanged(button)
    if NS.WindowActionSkin and NS.WindowActionSkin.IsApplied(button) then
        NS.WindowActionSkin.Refresh(button)
    end
end

InstallHooks = function()
    if not UIPanelButtons.legacyHooked
        and type(hooksecurefunc) == "function"
        and type(_G.UIPanelButton_OnShow) == "function" then
        hooksecurefunc("UIPanelButton_OnShow", OnUIPanelButtonShown)
        UIPanelButtons.legacyHooked = true
    end

    if not UIPanelButtons.sharedHooked
        and type(hooksecurefunc) == "function"
        and type(_G.ButtonControllerMixin) == "table"
        and type(_G.ButtonControllerMixin.OnShow) == "function" then
        hooksecurefunc(_G.ButtonControllerMixin, "OnShow", OnSharedButtonShown)
        UIPanelButtons.sharedHooked = true
    end

    if not UIPanelButtons.iconHooked
        and type(hooksecurefunc) == "function"
        and type(_G.UIButtonMixin) == "table"
        and type(_G.UIButtonMixin.SetButtonArtKit) == "function" then
        hooksecurefunc(_G.UIButtonMixin, "SetButtonArtKit", OnIconArtChanged)
        UIPanelButtons.iconHooked = true
    end


    if not UIPanelButtons.closeBorderHooked
        and type(hooksecurefunc) == "function"
        and type(_G.UIPanelCloseButton_SetBorderAtlas) == "function" then
        hooksecurefunc("UIPanelCloseButton_SetBorderAtlas", OnCloseButtonBorderChanged)
        UIPanelButtons.closeBorderHooked = true
    end

    if not UIPanelButtons.staticPopupHooked
        and type(hooksecurefunc) == "function"
        and type(_G.GameDialogMixin) == "table"
        and type(_G.GameDialogMixin.SetupButtons) == "function" then
        local ok = pcall(function()
            hooksecurefunc(_G.GameDialogMixin, "SetupButtons", OnGameDialogButtonsSetup)
        end)
        UIPanelButtons.staticPopupHooked = ok == true
    end


    if not UIPanelButtons.staticPopupCloseHooked
        and type(hooksecurefunc) == "function"
        and type(_G.GameDialogMixin) == "table"
        and type(_G.GameDialogMixin.SetupCloseButton) == "function" then
        local ok = pcall(function()
            hooksecurefunc(_G.GameDialogMixin, "SetupCloseButton", OnGameDialogCloseSetup)
        end)
        UIPanelButtons.staticPopupCloseHooked = ok == true
    end

    return UIPanelButtons.legacyHooked or UIPanelButtons.sharedHooked
        or UIPanelButtons.iconHooked or UIPanelButtons.staticPopupHooked
end

function UIPanelButtons.Refresh()
    if not Enabled() then
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
        return false, "combat"
    end

    local pending = {}
    for button, artKit in pairs(UIPanelButtons.pendingIconArtKits) do
        pending[#pending + 1] = { button, artKit }
        UIPanelButtons.pendingIconArtKits[button] = nil
    end
    for index = 1, #pending do
        OnIconArtChanged(pending[index][1], pending[index][2])
    end

    PrimeQuickJoinToast()
    PrimeStaticPopups()
    for button, family in pairs(UIPanelButtons.tracked) do
        SkinButton(button, family)
    end
    return true
end

function UIPanelButtons.Apply(owner)
    UIPanelButtons.active = true
    if not InstallHooks() then
        return false, "unavailable"
    end
    RegisterStaticPopupLoad()
    return UIPanelButtons.Refresh()
end

function UIPanelButtons.Disable()
    UIPanelButtons.active = false
    NS.CombatGate.Cancel(DEFER_KEY)
    UIPanelButtons.pendingIconArtKits = setmetatable({}, { __mode = "k" })
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(OWNER) end
    local disabled = NS.ControlSkin.DisableOwner(OWNER)
    NS.Cosmetics.RestoreOwner(OWNER)
    return disabled
end

function UIPanelButtons.GetTrackedCount()
    local count = 0
    for _ in pairs(UIPanelButtons.tracked) do
        count = count + 1
    end
    return count
end

function UIPanelButtons.IsHooked()
    return UIPanelButtons.legacyHooked == true and UIPanelButtons.sharedHooked == true
        and UIPanelButtons.iconHooked == true and UIPanelButtons.closeBorderHooked == true
        and UIPanelButtons.staticPopupHooked == true
        and UIPanelButtons.staticPopupCloseHooked == true
end

-- Install as soon as the rendering primitives exist. Blizzard buttons built
-- before custom addons are still captured the first time they become visible;
-- the hook remains observation-only until Apply activates the feature.
InstallHooks()
