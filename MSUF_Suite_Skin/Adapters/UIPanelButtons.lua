local _, NS = ...

-- UIPanelButtonTemplate is the source of Blizzard's legacy red three-piece
-- buttons. Modern Blizzard UI uses SharedButtonTemplate and its red/gold-red
-- size variants instead. Catalog traversal covers buttons that already belong
-- to a verified Blizzard root; narrowly scoped visibility and art-kit hooks
-- cover both families elsewhere without replacing any action, hover, or state
-- script.
--
-- Blizzard binds these handlers when a button is created: SecureUIPanelTemplates
-- .xml binds `<OnShow function="UIPanelButton_OnShow"/>` to the function value,
-- and Mixin() copies ButtonControllerMixin.OnShow and UIButtonMixin's
-- SetButtonArtKit onto every instance (and into IconButtonMixin,
-- SquareIconButtonMixin and ThreeSliceButtonMixin at SharedXML load). Hooking
-- the global or mixin therefore only reaches buttons created after this
-- load-on-demand addon; the buttons that already existed are adopted once by
-- hooking their own instance handlers.
local UIPanelButtons = {
    active = false,
    adopted = false,
    staticPopupLoadRegistered = false,
    hooks = {},
    tracked = setmetatable({}, { __mode = "k" }),
    pendingIconArtKits = setmetatable({}, { __mode = "k" }),
}
NS.UIPanelButtons = UIPanelButtons

local Field = NS.Safety.Field
local Call = NS.Safety.Call

local OWNER = "uipanel-buttons"
local DEFER_KEY = "uipanel-buttons:late"
local STATIC_POPUP_COUNT = 4
local regions = { "Left", "Middle", "Right", "Center" }
local sharedRegions = { "Left", "Center", "Right" }
local sharedRedAtlases = {
    ["128-RedButton"] = true,
    ["128-GoldRedButton"] = true,
}
local artKitMixins = {
    "UIButtonMixin", "IconButtonMixin", "SquareIconButtonMixin", "ThreeSliceButtonMixin",
}
local STATIC_POPUP_SPEC = {
    role = "button", activeRole = "buttonPrimary", useControlShape = true,
    pillHeight = 20, inset = 1, allowImplicitProtected = true,
}
local LEGACY_SPEC = { role = "button", useControlShape = true, regions = regions }
local SHARED_SPEC = { role = "button", useControlShape = true, regions = sharedRegions }

-- Native handlers captured before hooking; an instance still holding one of
-- them was created before this addon loaded.
local native = {}
local InstallHooks

local function Enabled()
    return UIPanelButtons.active
        and NS.DB and NS.DB.enabled ~= false
        and (not NS.DB.skins or NS.DB.skins.blizzardWindows ~= false)
end

local function SkinQuickJoin(button)
    local changed = NS.Checkmarks.TrackTexture(Field(button, "FriendsButton"), OWNER, "blizzardExpand")
    changed = NS.Checkmarks.TrackTexture(Field(button, "QueueButton"), OWNER, "blizzardExpand")
        or changed
    changed = NS.Checkmarks.TrackTexture(Field(button, "FlashingLayer"), OWNER, "blizzardExpandHover")
        or changed
    changed = NS.Checkmarks.TrackTexture(Call(button, "GetHighlightTexture"), OWNER, "blizzardExpandHover")
        or changed
    return changed
end

-- StaticPopupButtonTemplate is not a UIPanelButtonTemplate. It owns four full
-- UI-DialogBox-Button state textures and an optional pulse glow, so the
-- UIPanelButton_OnShow hook never sees it. Keep Blizzard's click/text/enable
-- logic, but replace those exact visual states before a death popup can first
-- appear in combat.
local function SkinStaticPopupButton(button)
    local nativeNormal = Call(button, "GetNormalTexture")
    local state, reason = NS.ControlSkin.ApplyButton(button, OWNER, STATIC_POPUP_SPEC)
    if not state then return false, reason end
    if nativeNormal then NS.Cosmetics.Fade(nativeNormal, OWNER) end
    local flash = Field(button, "Flash")
    if flash then NS.Cosmetics.SuppressVertexAlpha(flash, OWNER) end
    return true
end

local function SkinButton(button, family)
    if not Enabled() or not button then
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
        return false, "combat"
    end
    if not NS.Safety.CanControl(button, family == "staticpopup") then
        return false, "protected"
    end

    if family == "icon" then
        return NS.Checkmarks.TrackButton(button, OWNER)
    elseif family == "dialogclose" or family == "dialogminimize" then
        local kind = family == "dialogclose" and "close" or "minimize"
        local state, reason = NS.WindowActionSkin.SyncNativeVisual(button, OWNER, kind)
        return state ~= nil, reason
    elseif family == "quickjoin" then
        return SkinQuickJoin(button)
    elseif family == "staticpopup" then
        return SkinStaticPopupButton(button)
    end

    local state, reason
    if family == "shared" then
        state, reason = NS.ControlSkin.ApplyThreeSliceButton(button, OWNER, SHARED_SPEC)
    else
        state, reason = NS.ControlSkin.ApplyUIPanelButton(button, OWNER, LEGACY_SPEC)
    end
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
-- The same button is reachable through several native references; collect
-- each once in this scratch set, which is emptied again after every popup.
local popupButtons = {}

local function AddPopupButton(button)
    if button then popupButtons[button] = true end
end

local function SkinStaticPopup(popup)
    if not popup then return false end
    local list = Call(popup, "GetButtons")
    if type(list) == "table" then
        for index = 1, #list do AddPopupButton(list[index]) end
    end
    local container = Field(popup, "ButtonContainer")
    list = Field(container, "Buttons")
    if type(list) == "table" then
        for index = 1, #list do AddPopupButton(list[index]) end
    end
    local name = Call(popup, "GetName")
    for index = 1, STATIC_POPUP_COUNT do
        AddPopupButton(Field(container, "Button" .. index))
        AddPopupButton(Field(popup, "Button" .. index))
        if type(name) == "string" and name ~= "" then
            AddPopupButton(_G[name .. "Button" .. index])
        end
    end
    AddPopupButton(Field(popup, "ExtraButton"))

    local applied = false
    for button in pairs(popupButtons) do
        popupButtons[button] = nil
        UIPanelButtons.tracked[button] = "staticpopup"
        applied = SkinButton(button, "staticpopup") == true or applied
    end
    return applied
end

local function PrimeStaticPopups()
    if not NS.GenericWindows.IsCategoryEnabled("utility") then
        return false
    end
    local applied = false
    for index = 1, STATIC_POPUP_COUNT do
        applied = SkinStaticPopup(_G["StaticPopup" .. index]) or applied
    end
    return applied
end

local function OnGameDialogButtonsSetup(popup)
    if not Enabled() or NS.IsCombatLocked() then return end
    SkinStaticPopup(popup)
end

local function OnGameDialogCloseSetup(popup, dialogInfo)
    if not Enabled() or not popup or not dialogInfo or not dialogInfo.closeButton then return end
    local button = Field(popup, "CloseButton")
    if not button then return end
    local family = dialogInfo.closeButtonIsHide and "dialogclose" or "dialogminimize"
    UIPanelButtons.tracked[button] = family
    NS.WindowActionSkin.AdoptNativeVisual(button, OWNER,
        family == "dialogclose" and "close" or "minimize")
end

local function RegisterStaticPopupLoad()
    if UIPanelButtons.staticPopupLoadRegistered then return end
    if not EventUtil or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then return end
    UIPanelButtons.staticPopupLoadRegistered = true
    EventUtil.ContinueOnAddOnLoaded("Blizzard_StaticPopup_Game", function()
        InstallHooks()
        if not Enabled() then return end
        if NS.IsCombatLocked() then
            NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
            return
        end
        PrimeStaticPopups()
    end)
end

local function OnUIPanelButtonShown(button)
    -- Visibility callbacks can run while opening combat UI. Do not retain or
    -- mutate a foreign control in that path; the next out-of-combat show (or a
    -- bounded adapter refresh) will capture it.
    if not button or NS.IsCombatLocked() then return end
    UIPanelButtons.tracked[button] = "legacy"
    SkinButton(button, "legacy")
end

local function IsSharedRedButton(button)
    return sharedRedAtlases[Field(button, "atlasName")] == true
        and button.Left ~= nil and button.Center ~= nil and button.Right ~= nil
end

local function OnSharedButtonShown(controller)
    if NS.IsCombatLocked() then return end
    local button = Call(controller, "GetParent")
    if not IsSharedRedButton(button) then return end
    UIPanelButtons.tracked[button] = "shared"
    SkinButton(button, "shared")
end

local function OnIconArtChanged(button, artKit)
    if not button then return end
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
    local wasAction = NS.WindowActionSkin.IsApplied(button) == true
    if (wasAction or actionKind)
        and not NS.WindowActionSkin.SyncButtonArtKit(button, OWNER, artKit, actionKind) then
        if NS.WindowActionSkin.GetOwner(button) ~= OWNER then
            UIPanelButtons.tracked[button] = nil
        end
        return
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
    if NS.WindowActionSkin.IsApplied(button) then
        NS.WindowActionSkin.Refresh(button)
    end
end

-- Adopted (pre-existing) buttons ----------------------------------------------

-- Another adapter (catalog traversal, an icon tree) already skins this control.
-- It already works, so an adopted handler leaves it alone.
local function OwnedElsewhere(button)
    local buttonOwners = NS.Checkmarks.buttonOwners
    local owner = NS.ControlSkin.GetOwner(button) or NS.WindowActionSkin.GetOwner(button)
        or (buttonOwners and buttonOwners[button])
    return owner ~= nil and owner ~= OWNER
end

local function OnAdoptedPanelButtonShown(button)
    if not OwnedElsewhere(button) then OnUIPanelButtonShown(button) end
end

local function OnAdoptedControllerShown(controller)
    if not OwnedElsewhere(Call(controller, "GetParent")) then OnSharedButtonShown(controller) end
end

local function OnAdoptedArtKitChanged(button, artKit)
    if not OwnedElsewhere(button) then OnIconArtChanged(button, artKit) end
end

-- Mixin copies and XML key values are plain instance fields: rawget reads them
-- without running any foreign __index handler.
local function AdoptFrame(frame)
    if native.setButtonArtKit and rawget(frame, "SetButtonArtKit") == native.setButtonArtKit then
        hooksecurefunc(frame, "SetButtonArtKit", OnAdoptedArtKitChanged)
        -- A later-created button reports its initial art kit from InitButton;
        -- an adopted one is caught up with the kit it already shows.
        local artKit = rawget(frame, "buttonArtKit")
        if NS.Checkmarks.IsRedButtonArtKit(artKit) then OnAdoptedArtKitChanged(frame, artKit) end
    end
    if native.controllerOnShow and rawget(frame, "OnShow") == native.controllerOnShow then
        hooksecurefunc(frame, "OnShow", OnAdoptedControllerShown)
    end
    if native.legacyOnShow and frame:GetScript("OnShow") == native.legacyOnShow then
        frame:HookScript("OnShow", OnAdoptedPanelButtonShown)
    end
end

-- One bounded pass over the existing frames, once per session and only after
-- the feature is first enabled.
local function AdoptExistingButtons()
    if UIPanelButtons.adopted or type(EnumerateFrames) ~= "function" then return end
    UIPanelButtons.adopted = true
    local frame = EnumerateFrames()
    while frame do
        if not NS.Safety.IsForbidden(frame) then AdoptFrame(frame) end
        frame = EnumerateFrames(frame)
    end
end

-- Hooks ------------------------------------------------------------------------

-- GameDialogMixin is copied onto StaticPopup1-4 when Blizzard_StaticPopup_Game
-- creates them, so hook those four instances.
local function HookStaticPopups()
    local hooked = UIPanelButtons.hooks
    for index = 1, STATIC_POPUP_COUNT do
        local popup = _G["StaticPopup" .. index]
        if popup and not hooked[popup] then
            if type(Field(popup, "SetupButtons")) == "function" then
                hooksecurefunc(popup, "SetupButtons", OnGameDialogButtonsSetup)
                hooked.staticPopup = true
            end
            if type(Field(popup, "SetupCloseButton")) == "function" then
                hooksecurefunc(popup, "SetupCloseButton", OnGameDialogCloseSetup)
            end
            hooked[popup] = true
        end
    end
end

InstallHooks = function()
    local hooked = UIPanelButtons.hooks
    if not hooked.legacy and type(_G.UIPanelButton_OnShow) == "function" then
        native.legacyOnShow = _G.UIPanelButton_OnShow
        hooksecurefunc("UIPanelButton_OnShow", OnUIPanelButtonShown)
        hooked.legacy = true
    end

    local controller = _G.ButtonControllerMixin
    if not hooked.shared and type(Field(controller, "OnShow")) == "function" then
        native.controllerOnShow = controller.OnShow
        hooksecurefunc(controller, "OnShow", OnSharedButtonShown)
        hooked.shared = true
    end

    local setArtKit = Field(_G.UIButtonMixin, "SetButtonArtKit")
    if not hooked.icon and type(setArtKit) == "function" then
        native.setButtonArtKit = setArtKit
        for index = 1, #artKitMixins do
            local mixin = _G[artKitMixins[index]]
            if Field(mixin, "SetButtonArtKit") == setArtKit then
                hooksecurefunc(mixin, "SetButtonArtKit", OnIconArtChanged)
            end
        end
        hooked.icon = true
    end

    if not hooked.closeBorder and type(_G.UIPanelCloseButton_SetBorderAtlas) == "function" then
        hooksecurefunc("UIPanelCloseButton_SetBorderAtlas", OnCloseButtonBorderChanged)
        hooked.closeBorder = true
    end

    HookStaticPopups()

    return hooked.legacy or hooked.shared or hooked.icon or hooked.staticPopup or false
end

function UIPanelButtons.Refresh()
    if not Enabled() then
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(DEFER_KEY, UIPanelButtons.Refresh)
        return false, "combat"
    end

    local pending = UIPanelButtons.pendingIconArtKits
    UIPanelButtons.pendingIconArtKits = setmetatable({}, { __mode = "k" })
    for button, artKit in pairs(pending) do
        OnIconArtChanged(button, artKit)
    end

    PrimeQuickJoinToast()
    PrimeStaticPopups()
    for button, family in pairs(UIPanelButtons.tracked) do
        SkinButton(button, family)
    end
    return true
end

function UIPanelButtons.Apply()
    UIPanelButtons.active = true
    if not InstallHooks() then
        return false, "unavailable"
    end
    RegisterStaticPopupLoad()
    if not NS.IsCombatLocked() then AdoptExistingButtons() end
    return UIPanelButtons.Refresh()
end

function UIPanelButtons.Disable()
    UIPanelButtons.active = false
    NS.CombatGate.Cancel(DEFER_KEY)
    UIPanelButtons.pendingIconArtKits = setmetatable({}, { __mode = "k" })
    NS.Checkmarks.UntrackOwner(OWNER)
    local disabled = NS.ControlSkin.DisableOwner(OWNER)
    NS.Cosmetics.RestoreOwner(OWNER)
    return disabled
end

-- Install as soon as the rendering primitives exist, so buttons Blizzard
-- creates from now on are observed at creation. The hooks stay inert until
-- Apply activates the feature.
InstallHooks()

return UIPanelButtons
