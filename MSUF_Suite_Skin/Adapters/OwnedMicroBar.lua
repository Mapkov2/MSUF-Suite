local _, NS = ...

-- MSKIN owns the bar shell, position and grid policy. Blizzard keeps the
-- MicroMenu frame, every native MicroButton, scripts, alerts and click state.
-- The complete MicroMenu is moved as one unit only outside combat; individual
-- buttons are never reparented or replaced.
--
-- Grid ownership without assigning Blizzard fields: GridLayoutFrameMixin.Layout
-- reads isHorizontal, stride, childXPadding/childYPadding and
-- layoutFramesGoingRight/Up from MicroMenu, and Edit Mode writes them
-- (EditModeMicroMenuSystemMixin). Values assigned by addon code would taint
-- every later Edit Mode pass that reads them (MicroMenuContainerMixin:Layout
-- reads isHorizontal first). The owned bar therefore never assigns them: it
-- anchors MicroMenu's layout children itself with GridLayoutUtil and its own
-- parameters, sizes MicroMenu to their extents the way ResizeLayoutMixin does,
-- and re-applies that after every native MicroMenu:Layout (post-hook) while
-- the bar owns the menu.
--
-- Nor does it run Blizzard code that writes MicroMenu or Edit Mode fields:
-- SetOverrideScale (overrideScale) and ResetMicroMenuPosition (stride,
-- overrideScale and Edit Mode's UpdateSystem pass, which writes systemInfo,
-- isHorizontal, normalScale ...) would run tainted from here, and Blizzard
-- reads those fields again in combat (vehicle exit runs ResetMicroMenuPosition
-- from MainActionBar's OnShow, right before protected StanceBar calls). The
-- bar scales the menu with the widget method, re-asserting it after a native
-- UpdateScale, and hands the menu back by reparenting it to its container and
-- placing it the way Blizzard's own layout does (HandBack); Blizzard's next
-- secure reset or layout pass then runs on untouched fields.
--
-- The grid and companion placement lives in OwnedMicroBarLayout.lua, the
-- visibility driver, health gate and mouseover reveal in
-- OwnedMicroBarVisibility.lua and the MSUF Edit Mode element in
-- OwnedMicroBarEditMode.lua; all three load before this file.
local OwnedMicroBar = {
    active = false,
    suspended = false,
}
NS.OwnedMicroBar = OwnedMicroBar

local Field = NS.Safety.Field
local Read = NS.Safety.Read
local Public = NS.Safety.Public
local HasMethod = NS.Safety.HasMethod
local Dispatch = NS.Safety.Dispatch
local Kit = NS.AdapterKit
local ParentIs = Kit.ParentIs

local Layout = NS.OwnedMicroBarLayout
local Settings = Layout.Settings
local Clamp = NS.Clamp
local ReadNumber = Layout.ReadNumber
local PerLine = Layout.PerLine
local LayoutButtons = Layout.LayoutButtons
local AnchorCompanions = Layout.AnchorCompanions
local PlaceNativeGrid = Layout.PlaceNativeGrid
local IsOwnedMode = Layout.IsOwnedMode

local Visibility = NS.OwnedMicroBarVisibility
local ApplyVisibility = Visibility.Apply
local RefreshHealthGate = Visibility.RefreshHealthGate

local EditMode = NS.OwnedMicroBarEditMode

local BAR_NAME = "MapkoSkinMicroBar"
local HEALTH_GATE_NAME = "MapkoSkinMicroBarHealthGate"
local MOVER_NAME = "MapkoSkinMicroBarMover"
local REAPPLY_KEY = "micro-menu:owned-reapply"
local FOREVER_PORTRAIT_SPACE = 48
local PORTRAIT_LEFT_INSET = 9
local RULE_LEFT_INSET = 62
local FOREVER_RING = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\ForeverPortraitRing.tga"
local MIDNIGHT_RING = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\MidnightPortraitRing.tga"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local PORTRAIT_MATERIALS = { forever = true, modern = true, midnightDark = true }
local PORTRAIT_ICON_STYLES = { bold = true, blizzardIcons = true }

local bar, healthGate
local mover
local portrait, portraitRing, topRule, bottomRule
local portraitEnabled = false
local activeRoot
-- The MicroMenu the bar took, until it hands it back.
local takenRoot
local hookedRoots = setmetatable({}, { __mode = "k" })
local hookedGlobals = {}
local desired = false
local ScheduleReapply

local eventFrame = CreateFrame("Frame")

local function CanOwn(target)
    return NS.Safety.CanControl(target, true) == true
end

-- MicroMenuSkin's single OnEnter/OnLeave script hook per native button calls
-- these, so hovering a button keeps a mouseover-only bar revealed.
OwnedMicroBar.HoverEnter = Visibility.HoverEnter
OwnedMicroBar.HoverLeave = Visibility.HoverLeave
OwnedMicroBar.TrackHoverButtons = Visibility.TrackHoverButtons

-- Shell -----------------------------------------------------------------------------

local function SavePosition()
    local settings = Settings()
    if not settings or not bar then return false end
    local point, _, relativePoint, x, y = bar:GetPoint(1)
    if type(point) ~= "string" or not Public(point) then return false end
    settings.layoutPoint = point
    settings.layoutRelativePoint =
        type(relativePoint) == "string" and Public(relativePoint) and relativePoint or point
    settings.layoutX = type(x) == "number" and Public(x) and math.floor(x + 0.5) or 0
    settings.layoutY = type(y) == "number" and Public(y) and math.floor(y + 0.5) or 0
    settings.positionPreset = "custom"
    return true
end

local function ApplyPosition(settings)
    if not bar then return false end
    local point = type(settings.layoutPoint) == "string"
        and settings.layoutPoint or "BOTTOMRIGHT"
    local relativePoint = type(settings.layoutRelativePoint) == "string"
        and settings.layoutRelativePoint or point
    bar:ClearAllPoints()
    bar:SetPoint(point, UIParent, relativePoint,
        Clamp(settings.layoutX, -4096, 4096), Clamp(settings.layoutY, -4096, 4096))
    return true
end

local function SetMoverVisible(visible)
    if not mover then return end
    mover:SetShown(visible == true and not EditMode.registered and not NS.IsCombatLocked())
end

local function ApplyShell(root, settings, horizontal, scale)
    local barMaterial = settings.barMaterial
    local buttonCount = Field(root, "numButtons")
    local perLine = PerLine(settings)
    if type(buttonCount) ~= "number" then buttonCount = perLine end
    portraitEnabled = PORTRAIT_MATERIALS[barMaterial] == true
        and PORTRAIT_ICON_STYLES[settings.iconStyle] == true
        and horizontal and perLine >= buttonCount

    local portraitSpace = portraitEnabled and FOREVER_PORTRAIT_SPACE or 0
    root:ClearAllPoints()
    root:SetPoint("CENTER", bar, "CENTER", portraitSpace / 2, 0)

    local rootScale = ReadNumber(root, "GetScale", scale)
    local width = math.max(1, ReadNumber(root, "GetWidth", 1) * rootScale)
    local height = math.max(1, ReadNumber(root, "GetHeight", 1) * rootScale)
    local padding = math.floor(Clamp(settings.padding, 0, 16) + 0.5)
    local shellHeight = height + padding * 2
    if portraitEnabled and barMaterial == "forever" then
        -- Native button hit boxes are taller than our visible 32px plates.
        -- Size the owned shell to the artwork so its frame stays compact.
        shellHeight = math.max(42, Clamp(settings.buttonSize, 20, 32) * scale + padding * 2 + 2)
    end
    bar:SetSize(width + padding * 2 + portraitSpace, shellHeight)
    portrait:SetShown(portraitEnabled)
    portraitRing:SetShown(portraitEnabled)
    topRule:SetShown(portraitEnabled)
    bottomRule:SetShown(portraitEnabled)
    if not portraitEnabled then return end

    portraitRing:SetTexture(barMaterial == "forever" and FOREVER_RING or MIDNIGHT_RING)
    portraitRing:SetDesaturated(barMaterial == "midnightDark")
    if barMaterial == "midnightDark" then
        portraitRing:SetVertexColor(0.84, 0.85, 0.82, 1)
    else
        portraitRing:SetVertexColor(1, 1, 1, 1)
    end
    local r, g, b, a = NS.Theme.GetColor("microBarBorder")
    topRule:SetColorTexture(r, g, b, a * 0.82)
    bottomRule:SetColorTexture(r, g, b, a * 0.52)
    SetPortraitTexture(portrait, "player")
end

-- Grid, shell and companions for the current settings (out of combat). The
-- help button's quadrant depends on where the sized shell ended up.
local function LayoutOwned(root, settings)
    local horizontal = LayoutButtons(root, settings)
    ApplyShell(root, settings, horizontal, Clamp(settings.scale, 0.50, 1.50))
    AnchorCompanions(root, settings, horizontal, bar)
end

-- The scale MicroMenuMixin:UpdateScale would give the owned size: its game
-- rule factor stays part of the result.
local function OwnedScale(settings)
    local scale = Clamp(settings.scale, 0.50, 1.50)
    local factor = C_GameRules.GetGameRuleAsFloat(Enum.GameRule.MicrobarScale)
    if type(factor) == "number" and factor ~= 0 then return scale * factor end
    return scale
end

local function ApplyGrid(root, settings)
    root:SetScale(OwnedScale(settings))
    LayoutOwned(root, settings)
end

-- Native state --------------------------------------------------------------------------

-- Puts the menu where Blizzard's own reset leaves it, without running that
-- reset from addon code: in MicroMenuContainer (Blizzard_MicroMenu makes it
-- with MicroMenu on both clients), on its native grid, anchored by
-- MicroMenuMixin:AnchorToMenuContainer and scaled by UpdateScale (both only
-- place and scale the menu and write no field), with the queue eye, FPS text
-- and help button around the native orientation.
local function HandBack(root)
    local container = MicroMenuContainer
    FrameUtil.SetParentMaintainRenderLayering(root, container)
    PlaceNativeGrid(root)
    root:AnchorToMenuContainer(Layout.ContainerPosition(container))
    root:UpdateScale()
    AnchorCompanions(root, Settings(), Field(root, "isHorizontal") == true, container)
end

local function RestoreNative(root)
    if not root or root ~= takenRoot or not CanOwn(root) then
        return false
    end
    if not ParentIs(root, bar) then
        -- Blizzard currently owns an override (vehicle, pet battle or a full-
        -- screen flow). Its next ResetMicroMenuPosition restores native state.
        return true, "yielded"
    end
    HandBack(root)
    return true, "handed-back"
end

-- Edit Mode -----------------------------------------------------------------------------

-- MSUF Edit Mode (OwnedMicroBarEditMode.lua) replaces the legacy mover.
local function EnsureEditRegistration()
    if EditMode.registered then return true end
    if EditMode.Register() then SetMoverVisible(false) end
    return EditMode.registered
end

-- Edit Mode's undo applies the restored settings to the menu the bar holds.
local function ApplyToActiveRoot(settings)
    return OwnedMicroBar.Apply(activeRoot, settings)
end

-- Frames ------------------------------------------------------------------------------

local function OnMoverDragStart()
    local settings = Settings()
    if NS.IsCombatLocked() or not OwnedMicroBar.active or not settings
        or settings.locked ~= false then
        return
    end
    bar:StartMoving()
end

local function OnMoverDragStop()
    bar:StopMovingOrSizing()
    if SavePosition() then ScheduleReapply() end
end

local function CreatePortrait()
    portrait = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    portrait:SetSize(44, 44)
    portrait:SetPoint("LEFT", bar, "LEFT", PORTRAIT_LEFT_INSET, 0)
    local mask = bar:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture(PORTRAIT_MASK)
    mask:SetAllPoints(portrait)
    portrait:AddMaskTexture(mask)
    portraitRing = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    portraitRing:SetTexture(FOREVER_RING)
    portraitRing:SetSize(54, 54)
    portraitRing:SetPoint("CENTER", portrait, "CENTER")
    topRule = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    topRule:SetPoint("TOPLEFT", bar, "TOPLEFT", RULE_LEFT_INSET, -1)
    topRule:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, -1)
    topRule:SetHeight(1)
    bottomRule = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    bottomRule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", RULE_LEFT_INSET, 1)
    bottomRule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 1)
    bottomRule:SetHeight(1)
    portrait:Hide()
    portraitRing:Hide()
    topRule:Hide()
    bottomRule:Hide()
    bar._msufForeverPortrait = portrait
    bar._msufForeverPortraitRing = portraitRing
end

-- The mover is a UIParent sibling, not a child of the protected bar. It can
-- disappear on combat start without mutating Blizzard controls.
local function CreateMover()
    mover = CreateFrame("Button", MOVER_NAME, UIParent)
    mover:SetAllPoints(bar)
    mover:SetFrameStrata("TOOLTIP")
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.10, 0.45, 0.95, 0.34)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(NS.L["Drag to move the Micro Bar"])
end

local function EnsureFrames()
    if bar and mover then return true end

    healthGate = CreateFrame("Frame", HEALTH_GATE_NAME, UIParent)
    healthGate:SetAllPoints(UIParent)
    healthGate:EnableMouse(false)
    -- The gate is an alpha-only parent. Keep it at UIParent's level so the
    -- owned shell retains its former level; FrameUtil preserves MicroMenu's
    -- native level when reparenting. An extra level here puts the shell fill
    -- in front of Blizzard's icons and darkens them.
    healthGate:SetFrameLevel(UIParent:GetFrameLevel())
    bar = CreateFrame("Frame", BAR_NAME, healthGate)
    bar:SetSize(1, 1)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(false)
    bar:SetScript("OnEnter", Visibility.HoverEnter)
    bar:SetScript("OnLeave", Visibility.HoverLeave)
    bar:Hide()
    Visibility.Attach(OwnedMicroBar, bar, healthGate)
    EditMode.Attach(OwnedMicroBar, bar, ApplyPosition, ApplyToActiveRoot)

    CreatePortrait()
    CreateMover()

    -- Allocate the structural regions before the native MicroMenu becomes a
    -- child. Afterwards the owned root is implicitly protected, so refreshes
    -- should only repaint already-created regions.
    if NS.Surface.Attach(bar, { role = "microBar" }) then
        NS.Surface.SetVisible(bar, false)
    end

    mover:SetScript("OnDragStart", OnMoverDragStart)
    mover:SetScript("OnDragStop", OnMoverDragStop)
    return true
end

-- Hooks and events ------------------------------------------------------------------------

-- True while the bar still holds the menu Blizzard left with it. Then the bar
-- is only placed again (after combat, a loading screen, a pet battle or a
-- drag) and the buttons repaint their state art. Once Blizzard took the menu
-- (vehicle, pet battle, a full-screen flow or Edit Mode's reset) the bar must
-- take it back and the buttons need their full skin again.
local function HoldsMenu(settings)
    return not OwnedMicroBar.suspended and IsOwnedMode(settings)
        and activeRoot ~= nil and ParentIs(activeRoot, bar)
end

local function PlaceAgain(root, settings)
    ApplyPosition(settings)
    ApplyGrid(root, settings)
    ApplyVisibility(settings)
    SetMoverVisible(settings.locked == false)
    EditMode.RefreshOwner()
end

local function Reapply()
    if not desired or not OwnedMicroBar.active then return end
    local settings = Settings()
    if HoldsMenu(settings) and NS.MicroMenuSkin.RefreshButtonStates() then
        PlaceAgain(activeRoot, settings)
    else
        NS.MicroMenuSkin.RefreshActive()
    end
end

ScheduleReapply = function()
    if not desired then return end
    NS.CombatGate.RunOrDefer(REAPPLY_KEY, Reapply)
end

local function OnNativeReset(root)
    if desired and OwnedMicroBar.active and root == activeRoot then
        ScheduleReapply()
    end
end

-- Blizzard's UpdateScale (Edit Mode's Micro Menu size, a layout load) sets
-- its own scale on the menu the bar holds; the owned scale comes back at
-- once. While Blizzard overrides the menu (overrideScale) it keeps its own.
local function OnNativeScale(root)
    if not desired or not OwnedMicroBar.active or OwnedMicroBar.suspended
        or root ~= activeRoot or not ParentIs(root, bar) or Field(root, "overrideScale") ~= nil then
        return
    end
    local settings = Settings()
    if not IsOwnedMode(settings) then return end
    if NS.IsCombatLocked() and not NS.Safety.CanControl(root) then
        ScheduleReapply()
        return
    end
    root:SetScale(OwnedScale(settings))
end

-- Blizzard runs MicroMenu:Layout on show and after MarkDirty. When its cached
-- grid no longer matches the children it re-anchors them from its own fields;
-- put the owned grid back right after, in the same frame.
local function OnNativeLayout(root)
    if not desired or not OwnedMicroBar.active or OwnedMicroBar.suspended
        or root ~= activeRoot or not ParentIs(root, bar) then
        return
    end
    local settings = Settings()
    if not IsOwnedMode(settings) then return end
    if not NS.IsCombatLocked() then
        LayoutOwned(root, settings)
        return
    end
    -- An unprotected menu gets its buttons back at once; the shell and the
    -- native companions follow once combat ends.
    if NS.Safety.CanControl(root) then
        LayoutButtons(root, settings)
    end
    ScheduleReapply()
end

-- The hooks run inside Blizzard's own calls, so each is its own error
-- boundary: a failing pass is reported and Blizzard's caller goes on.
local function OnNativeResetHook(root)
    Dispatch(OnNativeReset, root)
end

local function OnNativeLayoutHook(root)
    Dispatch(OnNativeLayout, root)
end

local function OnNativeScaleHook(root)
    Dispatch(OnNativeScale, root)
end

-- Blizzard took the menu (vehicle, pet battle, a full-screen flow). Out of
-- combat the reapply hides the bar at once; in combat it waits, so the empty
-- shell turns invisible until then (alpha is allowed in combat) and stays
-- suspended. Taking the menu back restores its alpha (Visibility.Apply).
local function OnNativeOverride()
    if desired and OwnedMicroBar.active and bar and activeRoot and NS.IsCombatLocked()
        and not ParentIs(activeRoot, bar) then
        OwnedMicroBar.suspended = true
        bar:SetAlpha(0)
    end
    ScheduleReapply()
end

local function OnNativeOverrideHook()
    Dispatch(OnNativeOverride)
end

local function HookRootMethod(root, method, callback)
    local hooked = hookedRoots[root]
    if not hooked then
        hooked = {}
        hookedRoots[root] = hooked
    end
    if not hooked[method] and Kit.HookFunction(root, method, callback) then
        hooked[method] = true
    end
end

local function HookGlobal(name, callback)
    if not hookedGlobals[name] and Kit.HookGlobal(name, callback) then
        hookedGlobals[name] = true
    end
end

local function EnsureHooks(root)
    HookRootMethod(root, "ResetMicroMenuPosition", OnNativeResetHook)
    HookRootMethod(root, "OverrideMicroMenuPosition", OnNativeOverrideHook)
    HookRootMethod(root, "Layout", OnNativeLayoutHook)
    HookRootMethod(root, "UpdateScale", OnNativeScaleHook)
    HookGlobal("MicroMenuBar_SetFullScreenFrame", OnNativeOverrideHook)
    HookGlobal("MicroMenuBar_ClearFullScreenFrame", OnNativeOverrideHook)
end

local eventsRegistered, addonListening = false, false
local loadEventsRegistered = {}

local function SyncLoadEvents(settings)
    local housing = settings and settings.loadHideInHousing
    local zone = settings and (settings.loadHideInInstance or housing)
    local health = settings and settings.loadShowWhenInjured
    local wanted = {
        ZONE_CHANGED_NEW_AREA = zone,
        HOUSE_PLOT_ENTERED = housing,
        HOUSE_PLOT_EXITED = housing,
        UNIT_HEALTH = health,
        UNIT_MAXHEALTH = health,
    }
    for event, registered in pairs(loadEventsRegistered) do
        if registered and not wanted[event] then
            eventFrame:UnregisterEvent(event)
            loadEventsRegistered[event] = nil
        end
    end
    for event, active in pairs(wanted) do
        if active and not loadEventsRegistered[event] and NS.Client.SupportsEvent(event) then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                eventFrame:RegisterUnitEvent(event, "player")
            else
                eventFrame:RegisterEvent(event)
            end
            loadEventsRegistered[event] = true
        end
    end
end

local function StopAddonListening()
    if addonListening then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addonListening = false
    end
end

local function RegisterEvents(settings)
    if not eventsRegistered then
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
        eventFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player")
        if NS.Client.SupportsEvent("INPUT_DEVICE_INTERFACE_TRANSITION") then
            eventFrame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
        end
        eventsRegistered = true
    end
    SyncLoadEvents(settings)
    if not EditMode.registered and not addonListening then
        eventFrame:RegisterEvent("ADDON_LOADED")
        addonListening = true
    end
end

local function UnregisterEvents()
    if eventsRegistered then
        eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:UnregisterEvent("PET_BATTLE_CLOSE")
        eventFrame:UnregisterEvent("UNIT_PORTRAIT_UPDATE")
        eventFrame:UnregisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
        eventsRegistered = false
    end
    for event in pairs(loadEventsRegistered) do
        eventFrame:UnregisterEvent(event)
        loadEventsRegistered[event] = nil
    end
    StopAddonListening()
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then
        if EnsureEditRegistration() then StopAddonListening() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        SetMoverVisible(false)
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- Blizzard's own listener hides MicroMenu for WoW Forever's Gamepad UI
        -- (MainActionBar_InitializeGamepad) and shows it for mouse and keyboard;
        -- the shell follows once it has (Visibility.Apply).
        C_Timer.After(0, ScheduleReapply)
    elseif event == "UNIT_PORTRAIT_UPDATE" then
        -- Registered for the player unit only.
        if portraitEnabled and not NS.IsCombatLocked() then
            SetPortraitTexture(portrait, "player")
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        RefreshHealthGate(Settings())
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "HOUSE_PLOT_ENTERED"
        or event == "HOUSE_PLOT_EXITED" then
        if NS.IsCombatLocked() or OwnedMicroBar.suspended then
            ScheduleReapply()
        else
            ApplyVisibility(Settings())
        end
    else
        ScheduleReapply()
    end
end)

-- API -------------------------------------------------------------------------------------

function OwnedMicroBar.Apply(root, settings)
    settings = settings or Settings()
    desired = IsOwnedMode(settings)
    if not desired then
        OwnedMicroBar.Disable(root)
        return root, "blizzard"
    end
    if NS.IsCombatLocked() then return nil, "combat" end
    if not root or not CanOwn(root) or not EnsureFrames() then
        return nil, "unavailable"
    end

    activeRoot = root
    OwnedMicroBar.active = true
    RegisterEvents(settings)
    EnsureHooks(root)

    -- Blizzard's fullscreen clear path leaves MicroMenu on UIParent; the bar
    -- takes it from there too and hands it back to the container (HandBack).
    local parent = Read(root, "GetParent")
    if parent ~= bar and parent ~= _G.MicroMenuContainer and parent ~= UIParent then
        OwnedMicroBar.suspended = true
        Visibility.ClearDriver()
        bar:Hide()
        SetMoverVisible(false)
        return root, "blizzard-override"
    end

    takenRoot = root
    OwnedMicroBar.suspended = false
    if parent ~= bar then FrameUtil.SetParentMaintainRenderLayering(root, bar) end
    ApplyPosition(settings)
    ApplyGrid(root, settings)
    ApplyVisibility(settings)
    if EnsureEditRegistration() then StopAddonListening() end
    SetMoverVisible(settings.locked == false)
    EditMode.RefreshOwner()
    return bar, "owned"
end

-- Places the owned grid, shell and companions again for the current settings,
-- for example after the set of shown buttons changed. Skins stay untouched.
function OwnedMicroBar.Relayout(root)
    local settings = Settings()
    if not OwnedMicroBar.active or OwnedMicroBar.suspended or NS.IsCombatLocked()
        or not root or root ~= activeRoot or not ParentIs(root, bar)
        or not IsOwnedMode(settings) then
        return false
    end
    LayoutOwned(root, settings)
    return true
end

function OwnedMicroBar.Disable(root)
    desired = false
    root = root or activeRoot
    if NS.IsCombatLocked() then return false, "combat" end
    local success = true
    if root and root == takenRoot then
        success = RestoreNative(root) ~= false
    end
    Visibility.Reset()
    if bar then
        bar:EnableMouse(false)
        bar:SetAlpha(1)
    end
    if healthGate then healthGate:SetAlpha(1) end
    SetMoverVisible(false)
    if bar then bar:Hide() end
    UnregisterEvents()
    OwnedMicroBar.active = false
    OwnedMicroBar.suspended = false
    portraitEnabled = false
    activeRoot = nil
    takenRoot = nil
    EditMode.RefreshOwner()
    return success, success and "disabled" or "partial"
end

function OwnedMicroBar.GetFrames()
    return bar, mover
end

-- The MicroMenu the bar holds, if any.
function OwnedMicroBar.GetRoot()
    return activeRoot
end

function OwnedMicroBar.OpenEditMode()
    if NS.IsCombatLocked() or not EnsureEditRegistration() then return false end
    return EditMode.Enter()
end
