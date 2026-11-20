local _, NS = ...

-- Reviewed native top-level windows. This is geometry policy, not a frame scan;
-- catalog membership alone never turns HUD, tooltips or nested panes into windows.
local Policy = {}
NS.WindowControlPolicy = Policy
local Safety = NS.Safety
local function PublicNumber(value) return Safety.Public(value) and type(value) == "number" end
local inventoryRoots = {
    BankFrame = true, ContainerFrameCombinedBags = true,
    ContainerFrame1 = true, ContainerFrame2 = true, ContainerFrame3 = true,
    ContainerFrame4 = true, ContainerFrame5 = true, ContainerFrame6 = true, ContainerFrame7 = true,
}

function Policy.IsInventory(frame)
    local name = Safety.Read(frame, "GetName")
    return inventoryRoots[name] == true and frame == Safety.Field(_G, name)
end

-- Fixed-layout exchange windows keep their size: their caption is the X
-- (and a minimize where one is offered) without a maximize cell.
local fixedPanels = { TradeFrame = true }
function Policy.CanFit(state) return not fixedPanels[state.name] end

local specialPanels = {
    MSUFSuiteSpellLearningFrame = true,
    SettingsPanel = true, AddonList = true, PlayerSpellsFrame = true,
    GameMenuFrame = true, ProfessionsFrame = true,
    SocialUIFrame = true, FriendsFrame = true, FriendsFriendsFrame = true,
    DeathRecapFrame = true, ClickBindingFrame = true, GuideFrame = true,
    SubscriptionInterstitialFrame = true, CurrencyTransferMenu = true,
    ChatConfigFrame = true, HelpFrame = true, CooldownViewerSettings = true,
    ColorPickerFrame = true, OpacityFrame = true, ScriptErrorsFrame = true,
    ModelPreviewFrame = true, EventTrace = true, TimeManagerFrame = true,
    -- Forever's dedicated skin applies this outer container; its three
    -- PortraitFrame panes follow it and are not generic catalog roots.
    LFGParentFrame = true,
}
local compactWidths = { OpacityFrame = 80, TimeManagerFrame = 220 }
local nativeParentRoots = { FriendsFrame = true, SocialUIFrame = true, ModelPreviewFrame = true }
local excludedCategories = {
    hud = true, inventory = true, tutorial = true, utility = true,
}

local function IsBag(name)
    return name:find("^ContainerFrame") or name:find("^BankFrame")
        or name:find("^Bag") or name:find("^Bags")
end

local function NativeBook(frame, name)
    return (name == "PlayerSpellsFrame" or name == "ProfessionsBookFrame"
        or name == "ProfessionsFrame" and NS.Client.isForever) and frame == Safety.Field(_G, name)
end

local function NativeFinder(frame, name)
    return (name == "PVEFrame" or name == "LFGParentFrame") and frame == Safety.Field(_G, name)
end

function Policy.CanChangeGeometry(frame)
    if Safety.IsForbidden(frame) then return false end
    local name = Safety.Read(frame, "GetName")
    local inventory = inventoryRoots[name]
    if inventory and not Policy.IsInventory(frame) then return false end
    local protected, explicit = Safety.GetProtection(frame)
    if explicit then return false end
    -- These outer containers may acquire implicit protection from their children.
    return not protected or (not NS.IsCombatLocked() and (inventory or NativeBook(frame, name) or NativeFinder(frame, name)))
end

-- Geometry release may run just after another Suite module claims the root.
-- Ordinary controls and callbacks additionally respect that current owner.
function Policy.CanControl(frame)
    if Policy.IsInventory(frame) and NS.SuiteOwnership.OwnsWindowGeometry(frame) then return false end
    return Policy.CanChangeGeometry(frame)
end

-- Blizzard can lay out its secure books and bags during combat. Set the screen
-- clamp while their geometry is writable so native slot changes keep the same
-- displayed top-left. Insets are signed edge deltas in the frame's own units
-- (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua, UpdateClampOffsets;
-- live 297d7aaa, forever 3d8abb1d).
function Policy.ReleasePositionClamp(state)
    local clamp = state.positionClamp
    if not clamp or not Policy.CanChangeGeometry(state.frame) then return end
    state.frame:SetClampRectInsets(clamp[1], clamp[2], clamp[3], clamp[4])
    state.frame:SetClampedToScreen(clamp.enabled)
    state.positionClamp = nil
end

function Policy.UsesPositionClamp(state)
    return state.inventory or NativeBook(state.frame, state.name)
end

local function PinPosition(state, left, right, top, bottom)
    local frame = state.frame
    if not Policy.UsesPositionClamp(state) or NS.IsCombatLocked() and not state.positionClamp then return end
    local l, r, t, b = Safety.Call(frame, "GetClampRectInsets")
    local enabled = Safety.Read(frame, "IsClampedToScreen")
    if enabled == nil or not (PublicNumber(l) and PublicNumber(r) and PublicNumber(t) and PublicNumber(b)) then return end
    if not state.positionClamp then state.positionClamp = { l, r, t, b, enabled = enabled } end
    if math.abs(l - left) > 0.001 or math.abs(r - right) > 0.001
        or math.abs(t - top) > 0.001 or math.abs(b - bottom) > 0.001 then
        frame:SetClampRectInsets(left, right, top, bottom)
    end
    if not enabled then frame:SetClampedToScreen(true) end
end

function Policy.ScreenPosition(frame)
    local left, top = Safety.Read(frame, "GetLeft"), Safety.Read(frame, "GetTop")
    local scale = Safety.Read(frame, "GetEffectiveScale")
    local uiHeight, uiScale = UIParent:GetHeight(), UIParent:GetEffectiveScale()
    if not (PublicNumber(left) and PublicNumber(top) and PublicNumber(scale) and PublicNumber(uiHeight)
        and PublicNumber(uiScale)) or uiScale <= 0 or scale <= 0 then return end
    local ratio = scale / uiScale
    return { x = math.floor(left * ratio + 0.5), y = math.floor(top * ratio - uiHeight + 0.5) }
end

function Policy.ScreenRatio(frame)
    local scale, uiScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if PublicNumber(scale) and PublicNumber(uiScale) and scale > 0 and uiScale > 0 then return scale / uiScale end
end

-- Leave the native title commands alone on crowded headers.
function Policy.PlaceExtraCaption(button, frame)
    local top, height = Safety.Read(frame, "GetTop"), UIParent:GetHeight()
    local ratio = Policy.ScreenRatio(frame)
    if type(top) == "number" and ratio and PublicNumber(height) and (top + 24) * ratio <= height then
        button:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -2, 2)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -36)
    end
end

-- Read existing attributes or registration without invoking the panel
-- manager's getter, which can initialize the native panel on its first read.
local function NativeFitExtra(frame, registered, attribute, field)
    local value = Safety.Read(frame, "GetAttribute", attribute)
    if type(value) == "number" then return value end
    value = Safety.Field(registered, field)
    return PublicNumber(value) and value or 0
end

function Policy.FitGeometry(state)
    local frame = state.frame
    local ratio, current = Policy.ScreenRatio(frame), frame:GetScale()
    local width, height = frame:GetWidth(), frame:GetHeight()
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if not ratio or not (PublicNumber(current) and PublicNumber(width) and PublicNumber(height)
        and PublicNumber(uiWidth) and PublicNumber(uiHeight)) or current <= 0 then return end
    local right, bottom, top = NS.WindowControlChrome.Footprint(state)
    local registered = Safety.Field(UIPanelWindows, state.name)
    if not Safety.Public(registered) then registered = nil end
    right = math.max(right, NativeFitExtra(frame, registered, "UIPanelLayout-checkFitExtraWidth", "checkFitExtraWidth"))
    bottom = math.max(bottom, NativeFitExtra(frame, registered, "UIPanelLayout-checkFitExtraHeight", "checkFitExtraHeight"))
    width, height = width + right, height + bottom + top
    if width <= 0 or height <= 0 then return end
    local scale = math.min((uiWidth - 16) / width, (uiHeight - 16) / height) * (current / ratio)
    if scale > 0 then return scale, current, -right / 2, (bottom - top) / 2 end
end

-- The panel's own anchors when all are readable (secret-anchored layout returns secrets).
function Policy.CaptureNativePoints(frame)
    local count = Safety.Read(frame, "GetNumPoints")
    if type(count) ~= "number" or count < 1 or count > 8 then return nil end
    local Public = Safety.Public
    local points = {}
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        if not Public(point) or not Public(relativeTo) or not Public(relativePoint)
            or not Public(x) or not Public(y) or type(point) ~= "string" then
            return nil
        end
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

local function AtPosition(frame, x, y)
    if Safety.Read(frame, "GetNumPoints") ~= 1 then return false end
    local point, parent, relative, dx, dy = frame:GetPoint(1)
    local public = Safety.Public
    return public(point) and public(parent) and public(relative) and PublicNumber(dx) and PublicNumber(dy)
        and point == "TOPLEFT" and parent == UIParent and relative == "TOPLEFT"
        and math.abs(dx - x) < 0.001 and math.abs(dy - y) < 0.001
end

function Policy.PlaceWindow(state, point)
    local frame = state.frame
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local uiScale = UIParent:GetEffectiveScale()
    local scale, width, height = frame:GetEffectiveScale(), frame:GetWidth(), frame:GetHeight()
    if not (PublicNumber(uiWidth) and PublicNumber(uiHeight) and PublicNumber(uiScale) and PublicNumber(scale)
        and PublicNumber(width) and PublicNumber(height) and PublicNumber(point.x) and PublicNumber(point.y))
        or uiScale <= 0 or scale <= 0 then return end
    local ratio = scale / uiScale
    local right, bottom, top = NS.WindowControlChrome.Footprint(state)
    local x = math.max(0, math.min(uiWidth - (width + right) * ratio, point.x)) / ratio
    local y = math.max(-math.max(0, uiHeight - (height + bottom) * ratio), math.min(-top * ratio, point.y)) / ratio
    PinPosition(state, -x, uiWidth / ratio - x - width, -y, height - uiHeight / ratio - y)
    if not AtPosition(frame, x, y) then
        state.placing = true
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        state.placing = nil
    end
    return true
end

-- Some native layout paths change the root without going through the public
-- panel-manager hook. Only observe a root after the player has placed it.
function Policy.WatchPosition(state, queue)
    if state.positionWatched then return end
    state.positionWatched = true
    local function Changed()
        if state.customPosition and not state.placing then queue(state) end
    end
    hooksecurefunc(state.frame, "SetPoint", Changed)
    hooksecurefunc(state.frame, "SetScale", Changed)
    state.frame:HookScript("OnSizeChanged", Changed)
end

function Policy.HasManagedVisibility(state)
    if state.panel or UIPanelWindows[state.name] then return true end
    local area = Safety.Call(state.frame, "GetAttribute", "UIPanelLayout-area")
    return not Safety.Public(area) or area ~= nil
end

function Policy.CanChangeVisibility(state)
    local managed = Policy.HasManagedVisibility(state)
    return (not managed or not NS.IsCombatLocked()) and Policy.CanChangeGeometry(state.frame), managed
end

-- Keep the current spell tab, profession page, recipe or Legacy page through minimize.
-- ProfessionsMixin:OnHide clears the native interaction and resets crafting.
local parkPageWindows = {
    PlayerSpellsFrame = true,
    ProfessionsFrame = true,
    ProfessionsBookFrame = true,
    LegacySystemFrame = true,
}

local function KeepPageOpen(state)
    if parkPageWindows[state.name] then return true end
    if state.name ~= "CharacterFrame" or state.suiteBounds then return false end
    -- Both clients' CharacterMicroButton always opens PaperDollFrame.
    local page = Safety.Field(state.frame, "activeSubframe")
    return not Safety.Public(page) or page ~= nil and page ~= "PaperDollFrame"
end

-- Only the top-level panels identified below reach this policy. Transient
-- dialogs have a native decision or interaction that must stay on screen.
local closeOnly = {
    ColorPickerFrame = true, OpacityFrame = true, DeathRecapFrame = true,
    SubscriptionInterstitialFrame = true, TradeFrame = true,
}
function Policy.IsMinimizable(name) return not closeOnly[name] end

-- Blizzard buttons whose own OnClick opens the window as the player's click or
-- key binding does (live and forever): MinimapZoneTextButtonMixin:OnClick runs
-- ToggleWorldMap (Blizzard_Minimap/Mainline/Minimap.lua), the micro buttons
-- (Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua) ToggleCharacter
-- ("PaperDollFrame"), ToggleAchievementFrame,
-- ToggleCollectionsJournal, ToggleEncounterJournal and, on WoW Forever,
-- ToggleGroupFinderFrame. The restore tab clicks one of
-- them from secure code (WindowControlDelegate.lua). A hidden micro button
-- still takes the click. A micro button that names its toggled frame
-- (GetToggledFrame: LFD names PVEFrame on live, LFGParentFrame on Forever's
-- vanilla-style finder) opens only that window.
local openers = {
    WorldMapFrame = { "MinimapCluster", "ZoneTextButton" }, CharacterFrame = { "CharacterMicroButton" },
    AchievementFrame = { "AchievementMicroButton" },
    CollectionsJournal = { "CollectionsMicroButton" }, EncounterJournal = { "EJMicroButton" },
    PVEFrame = { "LFDMicroButton" }, LFGParentFrame = { "LFDMicroButton" },
}

-- Match the secure click gate used by Blizzard_FrameXML/SecureTemplates.lua.
function Policy.CanNativeClick(button)
    local kind = Safety.Public(button) and Safety.Read(button, "GetObjectType")
    if kind ~= "Button" and kind ~= "CheckButton" then return false end
    local constrained = Safety.Call(button, "HasAccessConstraints")
    if not Safety.Public(constrained) or constrained then return false end
    local aspect = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptedInput
    if not aspect then return true end
    local forbidden = Safety.Call(button, "HasAnyForbiddenAspects", aspect)
    return Safety.Public(forbidden) and not forbidden
end

function Policy.Opener(state)
    local path = openers[state.name]
    if not path then return nil end
    local button = Safety.Field(_G, path[1])
    for index = 2, #path do button = Safety.Field(button, path[index]) end
    if not Policy.CanNativeClick(button) or Safety.Read(button, "IsEnabled") ~= true then return nil end
    local toggled = Safety.Call(button, "GetToggledFrame")
    if not Safety.Public(toggled) or (toggled ~= nil and toggled ~= state.frame) then return nil end
    return button
end

-- The skin leaves visibility to Blizzard. Managed windows: ShowUIPanel
-- and HideUIPanel (and a managed window's OnShow, which calls
-- UpdateUIPanelPositions) run the panel manager inside the caller's call. From
-- skin code its slots were written under MSUF_Suite_Skin's taint, the next M
-- showed the map from that pass and its OnShow registered QuestDataProvider's
-- Supertracking.OnChanged callback tainted: every quest pin's
-- SetPassThroughButtons (MapCanvasMixin:AcquirePin) was then blocked in combat.
-- The map and Forever's spell book also update protected pins or action
-- buttons from their own show/hide scripts.
function Policy.SecureOnly(state)
    return state.name == "WorldMapFrame" or KeepPageOpen(state) or Policy.HasManagedVisibility(state)
end

function Policy.CanNativeMinimize(state)
    if state.inventory or KeepPageOpen(state) then return false end
    return Policy.CanNativeClick(state.close) and Safety.Read(state.close, "IsEnabled") ~= false
        and Policy.Opener(state) ~= nil
end

function Policy.NeedsPark(state)
    return state.inventory or Policy.SecureOnly(state) or not state.close
end

function Policy.CanPark(state)
    if state.name == "WorldMapFrame" then return false end
    local restricted = Safety.Call(state.frame, "IsAnchoringRestricted")
    return Safety.Public(restricted) and not restricted
end

function Policy.OffersMinimize(state)
    return Policy.CanNativeMinimize(state) or not Policy.NeedsPark(state) or Policy.CanPark(state)
end

-- Some panels have no safe reopen button, and BankFrame's OnHide ends its
-- interaction. Keep the native panel shown and move its entire hit area below
-- the viewport. Blizzard can still close it via Escape or an interaction end.
local PARK_Y = -96

function Policy.HoldPark(state)
    local frame, park = state.frame, state.park
    if not state.minimized or not park then return end
    local top = Safety.Read(frame, "GetTop")
    if type(top) == "number" and top <= PARK_Y / 2 and Safety.Read(frame, "GetNumPoints") == 1 then return end
    if NS.IsCombatLocked() then return NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow) end
    if not Policy.CanChangeGeometry(frame) or not Policy.CanPark(state) then return end
    park.placing = true
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", park.x, PARK_Y)
    park.placing = nil
end

-- A native shortcut can select another page without showing the root again.
-- Let Blizzard finish the switch before returning the parked frame to view.
local function WatchCharacterPage(state)
    local frame = state.frame
    if state.name ~= "CharacterFrame" or not Safety.HasMethod(frame, "ShowSubFrame") then return end
    local requestedPark
    local function ReturnToView()
        if not state.minimized or state.park ~= requestedPark or Safety.Read(frame, "IsShown") ~= true then return end
        if NS.IsCombatLocked() then
            NS.CombatGate.RunOrDefer("windowControls:restoreCharacterPage", ReturnToView)
            return
        end
        requestedPark = nil
        if Policy.RestorePark(state) then state.replayShow() end
    end
    hooksecurefunc(frame, "ShowSubFrame", function()
        if state.suiteBounds or not state.park or not state.minimized then return end
        requestedPark = state.park
        NS.Registry.QueueJob(ReturnToView)
    end)
end

local function WatchPark(state)
    if state.parkWatched then return end
    state.parkWatched = true
    local function Relayout()
        if state.park and state.minimized and not state.park.placing then
            NS.Registry.QueueJob(state.replayShow)
        end
    end
    hooksecurefunc(state.frame, "SetPoint", Relayout)
    WatchCharacterPage(state)
end

function Policy.Park(state, installLayoutHook)
    local frame = state.frame
    local points, left = Policy.CaptureNativePoints(frame), Safety.Read(frame, "GetLeft")
    local clamped = Safety.Read(frame, "IsClampedToScreen")
    if not points or type(left) ~= "number" or type(clamped) ~= "boolean" then
        state.minimized = false
        return
    end
    -- Capture the actual pre-minimize anchors and native clamp condition.
    state.park = { points = points, x = left, clamped = clamped }
    if clamped then frame:SetClampedToScreen(false) end
    WatchPark(state)
    installLayoutHook()
    Policy.HoldPark(state)
    state.restore:Show()
end

function Policy.RestorePark(state)
    local frame, park = state.frame, state.park
    if NS.IsCombatLocked() then return NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow) end
    if not Policy.CanChangeGeometry(frame) or not Policy.CanPark(state) then return false end
    state.park, state.minimized = nil, false
    state.restore:Hide()
    frame:ClearAllPoints()
    for _, point in ipairs(park.points) do frame:SetPoint(unpack(point, 1, 5)) end
    if park.clamped then frame:SetClampedToScreen(true) end
    return true
end

function Policy.ResumePark(state, controlled)
    if state.minimized and (controlled or NS.IsCombatLocked()) and not NS.Client.IsGamepadUI() then
        Policy.HoldPark(state)
        return true
    end
    return not Policy.RestorePark(state)
end

function Policy.ParkClosed(state)
    state.minimized = false
    state.restore:Hide()
    NS.Registry.QueueJob(state.replayShow)
end

-- Camelot/BankFrame.lua anchors the page tabs to the window's right edge.
local bankTabWidth
function Policy.ExteriorWidth(state, default)
    if state.name ~= "BankFrame" or not NS.Client.isForever then return default end
    if not bankTabWidth then
        local atlas = Safety.Field(C_Texture, "GetAtlasInfo")
        bankTabWidth = Safety.Field(atlas and atlas("common-sidetab"), "width") or 0
    end
    return type(bankTabWidth) == "number" and math.max(bankTabWidth, default) or default
end

function Policy.PrepareRestoreTab(state)
    local chrome = NS.WindowControlChrome
    chrome.LeaveFit(state)
    local frame, uiScale = state.frame, UIParent:GetEffectiveScale()
    local left, top = Safety.Read(frame, "GetLeft"), Safety.Read(frame, "GetTop")
    local frameScale = Safety.Read(frame, "GetEffectiveScale")
    state.restore:ClearAllPoints()
    if type(left) == "number" and type(top) == "number" and type(frameScale) == "number" and PublicNumber(uiScale) and uiScale > 0 then
        state.restore:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * frameScale / uiScale, top * frameScale / uiScale)
    else
        state.restore:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
    state.restoreLabel:SetText(chrome.Title(state) .. "  +")
    state.minimized = true
    return true
end

-- Blizzard's panel manager places the windows of its slots
-- (FramePositionDelegate:UpdateUIPanelPositions, Blizzard_UIParentPanelManager/
-- Shared/UIParentPanelManager.lua, live and forever). The skin only reads that
-- layout: a pass run from its code runs, and writes, under its taint.
local SLOTS = { "left", "doublewide", "center", "right", "fullscreen" }
local FOLLOWERS = { left = { "center", "right" }, doublewide = { "right" }, center = { "right" } }

local function SlotOf(frame)
    for _, slot in ipairs(SLOTS) do
        if GetUIPanel(slot) == frame then return slot end
    end
end

-- Where Blizzard's pass anchored a window, written into layout with the scale
-- it divided by (TOPLEFT both offsets, a centred TOP window only y): read
-- right after the pass, before the skin rescales the window.
local function PanelLayout(frame, layout)
    if Safety.Read(frame, "GetNumPoints") ~= 1 then return nil end
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    local scale = Safety.Read(frame, "GetScale")
    if not Safety.Public(point) or not Safety.Public(relative) or not Safety.Public(relativePoint)
        or not PublicNumber(x) or not PublicNumber(y) or type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    layout[1], layout[2], layout[3], layout[4], layout[5] = point, relative, relativePoint, x, y
    layout.scale, layout.scaled = scale, point == "TOPLEFT"
    return layout
end

-- After Blizzard's pass (the UpdateUIPanelPositions post-hook): where it put
-- each controlled window that holds a slot.
function Policy.CapturePanels(states)
    for _, slot in ipairs(SLOTS) do
        local frame = GetUIPanel(slot)
        local state = frame and states[frame]
        if state and not state.park then state.panelLayout = PanelLayout(frame, state.panelLayout or {}) end
    end
end

-- Puts a window that still holds its slot back where Blizzard's last pass put it.
function Policy.RestorePanel(state)
    local layout, frame = state.panelLayout, state.frame
    if not layout or not SlotOf(frame) then return false end
    local scale = frame:GetScale()
    if not PublicNumber(scale) or scale <= 0 then return false end
    local ratio = layout.scale / scale
    local x, y = layout.scaled and layout[4] * ratio or layout[4], layout[5] * ratio
    frame:ClearAllPoints()
    frame:SetPoint(layout[1], layout[2], layout[3], x, y)
    return true
end

function Policy.CaptureNativeBagLayout(state)
    if state.name == "BankFrame" or not state.nativePoints or #state.nativePoints ~= 1 then return end
    local frame, saved = state.frame, state.nativePoints[1]
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    local public = Safety.Public
    local scale = frame:GetScale()
    if not public(point) or not public(relative) or not public(relativePoint)
        or not PublicNumber(x) or not PublicNumber(y) or not PublicNumber(scale) or scale <= 0 then return end
    saved[1], saved[2], saved[3], saved[4], saved[5] = point, relative, relativePoint, x, y
    state.originalScale = scale
end

function Policy.RestoreNativePosition(state, releasing)
    local mayChange = releasing and Policy.CanChangeGeometry or Policy.CanControl
    if not mayChange(state.frame) then return end
    Policy.ReleasePositionClamp(state)
    local panel = state.panel
    if panel and Safety.Read(state.frame, "GetAttribute", "UIPanelLayout-defined") == true then
        local area = Safety.Call(state.frame, "GetAttribute", "UIPanelLayout-area")
        if Safety.Public(area) and area == nil then panel = nil end
    end
    if NS.IsCombatLocked() and panel and not panel.centerFrameSkipAnchoring and not NS.Client.IsGamepadUI() then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return
    end
    state.customPosition = false
    state.defaultPosition = false
    -- The panel manager never anchors the Game Menu (centerFrameSkipAnchoring). Its
    -- own pass placed the panel (Policy.RestorePanel); it never runs from here.
    if panel and not panel.centerFrameSkipAnchoring then
        if not NS.Client.IsGamepadUI() then Policy.RestorePanel(state) end
    elseif state.nativePoints then
        state.frame:ClearAllPoints()
        for index = 1, #state.nativePoints do
            local point = state.nativePoints[index]
            state.frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
    else
        state.frame:ClearAllPoints()
        state.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- A window that changed width moves the windows Blizzard laid out after it by
-- that width (UIParent units), as the pass would. A centred "center" window
-- (TOP) and windows the skin placed itself stay; protected ones wait for
-- Blizzard's next pass.
local scratch = {}
function Policy.ShiftFollowers(root, delta)
    local followers = delta ~= 0 and FOLLOWERS[SlotOf(root) or ""]
    if not followers then return end
    -- Blizzard owns map placement during another panel's width change.
    local foreverMap = NS.Client.isForever and Safety.Field(_G, "WorldMapFrame")
    for _, slot in ipairs(followers) do
        local frame = GetUIPanel(slot)
        local controls = frame and NS.WindowControls.states[frame]
        local layout = frame and frame ~= root and frame ~= foreverMap and not (controls and controls.customPosition)
            and Policy.CanChangeGeometry(frame) and PanelLayout(frame, scratch)
        if layout and layout[1] == "TOPLEFT" and layout[2] == UIParent and layout[3] == "TOPLEFT" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", layout[4] + delta / layout.scale, layout[5])
        end
    end
end

-- Forever's native show and size transitions can rebuild pins and run the
-- protected reading emote. Replay saved geometry after native layout settles.
function Policy.DeferMapLayout(state, afterNative)
    if state.name ~= "WorldMapFrame" or not NS.Client.isForever then return false end
    if Safety.Read(state.frame, "IsShown") ~= true then return true end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return true
    end
    if afterNative then return false end
    NS.Registry.QueueJob(state.replayShow)
    return true
end

-- Blizzard switches the map's native size buttons while opening the panel.
-- Settle the caption after that stack, also under forced combat restrictions.
function Policy.MapCaptionCallback(state, repaint)
    if state.name ~= "WorldMapFrame" or not NS.Client.isForever then return repaint end
    local queued = false
    local function Settle()
        queued = false
        if Safety.Read(state.frame, "IsVisible") == true then repaint() end
    end
    return function()
        if queued then return end
        queued = true
        C_Timer.After(0, Settle)
    end
end

-- Forever opens all native bags and refreshes the inbox before its protected
-- reading emote. Leave that opening stack to Blizzard.
function Policy.MailIsOpen()
    return NS.Client.isForever and Safety.Read(Safety.Field(_G, "MailFrame"), "IsShown") == true
end

function Policy.DeferMailLayout(state)
    if not Policy.MailIsOpen() or (state.name ~= "MailFrame" and not state.inventory) then return false end
    NS.Registry.QueueJob(state.replayShow)
    return true
end

local focusCompanions = {
    OpenMailFrame = true, WorldMapFrame = true,
    BattleNetInviteFrame = true, AddFriendFrame = true, AuctionHouseMultisellProgressFrame = true,
    CatalogShopFrame = true, CatalogShopRefundFrame = true, CatalogShopTopUpFrame = true,
    CreateChannelPopup = true, CommunitiesAvatarPickerDialog = true, CommunitiesSettingsDialog = true,
    CommunitiesTicketManagerDialog = true, CovenantPreviewFrame = true,
    ExpansionTrialThanksForPlayingDialog = true, ExpansionTrialCheckPointDialog = true, GuildInviteFrame = true,
    GroupLootHistoryFrame = true, RolePollPopup = true, WardrobeCustomSetEditFrame = true,
    LFDRoleCheckPopup = true, LFGDungeonReadyPopup = true, LFGInvitePopup = true, LFGListApplicationDialog = true,
    LFGListInviteDialog = true, PVPFramePopup = true, PlunderstormFramePopup = true, PVPRoleCheckPopup = true,
    PVPReadyDialog = true, PVPReadyPopup = true, LFGReadyCheckPopup = true, ReportCheatingDialog = true,
    IslandsQueueFrame = true, PhotoSharingFrame = true, PhotoSharingBrowserFrame = true,
    PhotoSharingBrowserPopup = true, QuickJoinRoleSelectionFrame = true, RecruitAFriendRewardsFrame = true,
    RecruitAFriendRecruitmentFrame = true, ReportFrame = true, SecureTransferDialog = true, SplashFrame = true,
    PetBattleQueueReadyFrame = true, BankCleanUpConfirmationPopup = true, SideDressUpFrame = true,
    MasterLooterFrame = true, WowTokenRedemptionFrame = true, WowTokenDialog = true,
    NeighborhoodChangeNameDialog = true, HousingCharterRequestSignatureDialog = true,
    BuyHouseConfirmationDialog = true, MoveHouseConfirmationDialog = true, ImportHouseConfirmationDialog = true,
    AbandonHouseConfirmationDialog = true,
}
local focusParents = {
    CalendarViewHolidayFrame = "CalendarFrame", CalendarViewRaidFrame = "CalendarFrame",
    CalendarViewEventFrame = "CalendarFrame", CalendarCreateEventFrame = "CalendarFrame",
    CalendarMassInviteFrame = "CalendarFrame", CalendarEventPickerFrame = "CalendarFrame",
    CalendarTexturePickerFrame = "CalendarFrame", CurrencyTransferLog = "TokenFrame",
    SideDressUpFrame = "RecruitAFriendRewardsFrame",
}

local function IdentifyWindow(frame, focus)
    if not frame or Safety.IsForbidden(frame) then return nil end
    local name = Safety.Read(frame, "GetName")
    if type(name) ~= "string" or name == "" then return nil end
    -- Blizzard's social toasts have close buttons but are not focus windows.
    if focus and (name == "BNToastFrame" or name == "TimeAlertFrame") then return nil end
    local companion = focus and (focusCompanions[name] or focusParents[name])
    if companion and frame ~= Safety.Field(_G, name) then return nil end
    if IsBag(name) and not inventoryRoots[name] and not companion then return nil end
    if inventoryRoots[name] and not Policy.IsInventory(frame) then return nil end
    if name == "LFGParentFrame" and not NS.Client.isForever then return nil end
    local entry = NS.BlizzardCatalog.FindByFrame(name)
    local standalone = specialPanels[name] or inventoryRoots[name] or companion
    local panel = UIPanelWindows[name]
    if not (entry or standalone) then return nil end
    -- A catalogued, named top-level window can own its own visibility instead
    -- of registering with UIPanelWindows. Require a native caption on that path.
    if not (panel or standalone) then
        local close = Safety.Field(frame, "ClosePanelButton") or Safety.Field(frame, "CloseButton")
        if frame ~= Safety.Field(_G, name) or Safety.Read(close, "GetObjectType") ~= "Button" then return nil end
    end
    if panel and panel.area == "full" and not (focus and name == "WorldMapFrame") then return nil end
    if entry and excludedCategories[entry.category] and not standalone then return nil end
    local parent = Safety.Read(frame, "GetParent")
    if parent ~= UIParent and not inventoryRoots[name] and not (standalone and parent == nil)
        and not (nativeParentRoots[name] and parent == Safety.Read(_G, "GetAppropriateTopLevelParent"))
        and not (focus and focusParents[name] and parent == Safety.Field(_G, focusParents[name])) then return nil end
    if focus then return name, entry, panel end
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    -- Professions starts at width one; its native SetTab sizes the root after
    -- showing it. Our anchors follow that layout without another skin pass.
    local initialProfession = name == "ProfessionsFrame" and width == 1 and frame == Safety.Field(_G, name)
    -- The Game Menu similarly starts at height one before laying out buttons.
    if type(width) ~= "number" or type(height) ~= "number"
        or width < (compactWidths[name] or (inventoryRoots[name] and 120) or 240) and not initialProfession
        or height < 170 and not standalone then return nil end
    return name, entry, panel
end

function Policy.IdentifyWindow(frame)
    return IdentifyWindow(frame, false)
end

-- Native windows can start at width one before their first layout. Observation
-- does not need the size/protection permission required by move/scale controls.
function Policy.IdentifyFocusWindow(frame)
    return IdentifyWindow(frame, true)
end

function Policy.IsAnimationWindow(frame)
    local name = Policy.IdentifyFocusWindow(frame)
    return name ~= nil and frame == Safety.Field(_G, name)
        and not inventoryRoots[name] and not focusCompanions[name] and not focusParents[name]
        and name ~= "GameMenuFrame" and (name ~= "WorldMapFrame" or not NS.Client.isForever)
end

function Policy.Eligible(frame)
    if not Policy.CanControl(frame) then return nil end
    return Policy.IdentifyWindow(frame)
end
