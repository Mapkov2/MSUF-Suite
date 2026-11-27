local _, NS = ...

-- Window geometry, separate from cosmetic skinning: only reviewed top-level Blizzard
-- panels, native controls win, no global frame scans or permanent OnUpdate.
local WindowControls = { states = setmetatable({}, { __mode = "k" }) }
NS.WindowControls = WindowControls
local TrackFocus, ReleaseFocus = function() end, function() end
function WindowControls.SetFocusProvider(track, release) TrackFocus, ReleaseFocus = track, release end
function WindowControls.TrackFocus(frame, owner) return TrackFocus(frame, owner) end
local GeometryChanged, GeometryInteraction = function() end, function() end
function WindowControls.SetGeometryMotionProvider(geometry, interaction)
    GeometryChanged, GeometryInteraction = geometry, interaction
end

local Safety = NS.Safety
local Policy = NS.WindowControlPolicy
local Chrome = NS.WindowControlChrome
local Delegate = NS.WindowControlDelegate
local CanChangeFrameGeometry = Policy.CanControl
local function PublicNumber(value) return Safety.Public(value) and type(value) == "number" end

local activeStates = setmetatable({}, { __mode = "k" })
local activeInventory = setmetatable({}, { __mode = "k" })
local controlStates = setmetatable({}, { __mode = "k" })

local FOREVER_CHARACTER_DOCK = { x = 0, y = 0 }
-- Our controls sit this many levels above their panel.
local CONTROL_LEVEL_OFFSET = 15
local GRIP_LEVEL_OFFSET = 20
local function IsCombat() return NS.IsCombatLocked() end
local function Enabled()
    local db = NS.DB
    return db and db.enabled ~= false and db.blizzardWindowsEnabled ~= false and db.windowControls
        and db.windowControls.enabled ~= false
        and db.skins and db.skins.blizzardWindows ~= false
end

local function CommitWithHistory(label, key, commit)
    if not IsCombat() then
        return NS.SuiteCore().HostBridge.WithMenuHistory(label, "suite:skin.windowControls." .. key, commit)
    end
    return commit()
end

local function ClampScale(value)
    local limits = NS.WindowLayoutLimits
    return math.max(limits.minScale, math.min(limits.maxScale, value))
end

local function Controlled(state)
    return Enabled() and next(state.owners) ~= nil and CanChangeFrameGeometry(state.frame)
end

local CONTROL_KEYS = { "grip", "titleDrag", "minimize", "maximize", "closeCell", "toggleCell" }
local function SafeControls(state)
    local implicit = not IsCombat()
    for _, key in ipairs(CONTROL_KEYS) do
        if state[key] and not Safety.CanDecorate(state[key], implicit) then return false end
    end
    return true
end

local function HasCaption(state)
    return not state.suitePresentation and (state.maximize or state.minimize or state.sizeToggle or state.closeOnly)
end

local function Maximized(state) return state.name == "WorldMapFrame" and Safety.Read(state.frame, "IsMaximized") == true end

local InstallPanelPositionHook

local function ApplyStoredScale(state)
    if not CanChangeFrameGeometry(state.frame) or state.fit or state.drag then return end
    local frame, scale = state.frame, state.originalScale
    if not Maximized(state) then
        local limits = NS.WindowLayoutLimits
        local scales = NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales
        local stored = scales and scales[state.name]
        if type(stored) == "number" and stored >= limits.minScale and stored <= limits.maxScale then
            scale = stored
            state.customScale = true
            InstallPanelPositionHook()
        elseif state.customScale or state.suiteScaleCapped then
            state.customScale = false
        elseif state.suiteBounds then
            scale = Safety.Read(frame, "GetScale")
        else
            return
        end
    end
    if type(scale) == "number" then
        local fit = state.suiteBounds and Policy.FitGeometry(state)
        state.suiteScaleCapped = fit and fit < scale or nil
        if state.suiteScaleCapped then scale = fit end
        local current = frame:GetScale()
        if PublicNumber(current) and current ~= scale then frame:SetScale(scale) end
    end
end

local function StoredPoint(state)
    local controls = NS.DB and NS.DB.windowControls
    return controls and controls.positions and controls.positions[state.name]
end

-- Repair only the root anchor after native layout returns. In particular, the
-- Forever map and mailbox can finish opening before this callback runs.
local function QueuePosition(state)
    if state.positionQueued or activeStates[state.frame] ~= state or state.moving or state.drag
        or state.fit or state.park or not StoredPoint(state)
        or not Controlled(state) or Safety.Read(state.frame, "IsShown") ~= true then return end
    if not state.replayPosition then
        state.replayPosition = function()
            state.positionQueued = nil
            if activeStates[state.frame] ~= state or state.moving or state.drag or state.fit or state.park or not Controlled(state)
                or Safety.Read(state.frame, "IsShown") ~= true or Maximized(state) then return end
            local point = StoredPoint(state)
            if point and Policy.PlaceWindow(state, point) then
                state.customPosition = true
                Policy.WatchPosition(state, QueuePosition)
            end
        end
    end
    state.positionQueued = true
    C_Timer.After(0, state.replayPosition)
end

local function ApplyStoredPosition(state)
    if not CanChangeFrameGeometry(state.frame) or not Enabled() or state.moving or Maximized(state) then return end
    if state.park then return Policy.HoldPark(state) end
    if state.fit then
        Policy.ReleasePositionClamp(state)
        return Chrome.Fit(state)
    end
    local point = StoredPoint(state)
    local defaultPosition = not point and state.name == "CharacterFrame"
        and NS.Client.isForever and NS.DB.theme.look == "foreverGlass"
    if defaultPosition then point = FOREVER_CHARACTER_DOCK end
    if not point then
        if state.customPosition and not state.suiteConstrained then Policy.RestoreNativePosition(state) end
        if state.suiteBounds then
            local position = Policy.ScreenPosition(state.frame)
            if position and Policy.PlaceWindow(state, position, true) then
                state.customPosition, state.suiteConstrained = true, true
            end
        end
        return
    end
    if not Policy.PlaceWindow(state, point) then return end
    if SafeControls(state) then
        Chrome.PlaceGrip(state.grip, state)
        Chrome.PlaceTitleDrag(state.titleDrag, state)
    end
    state.customPosition = true
    state.suiteConstrained = nil
    state.defaultPosition = defaultPosition == true
    if not defaultPosition then Policy.WatchPosition(state, QueuePosition) end
    InstallPanelPositionHook()
end

local positionHooked = false
local suspendPositionHook = false

-- Blizzard positions the mailbox while it is still hidden.
local function OnPanelPositionsUpdated(currentFrame)
    Policy.CapturePanels(WindowControls.states)
    if suspendPositionHook or not Enabled() then return end
    if NS.Client.isForever and Safety.Public(currentFrame) and currentFrame
        and currentFrame == Safety.Field(_G, "MailFrame") then return NS.Registry.QueueJob(WindowControls.Refresh) end
    for frame, state in pairs(activeStates) do
        if state.park then
            Policy.HoldPark(state)
        elseif Controlled(state) and frame:IsShown() and not Policy.DeferMailLayout(state) and not Policy.DeferMapLayout(state) then
            if not state.drag then ApplyStoredScale(state) end
            ApplyStoredPosition(state)
            if state.name == "BankFrame" and SafeControls(state) then Chrome.PlaceGrip(state.grip, state) end
            if HasCaption(state) and SafeControls(state) then
                Chrome.FollowPanels(state, Chrome.Level(state) + CONTROL_LEVEL_OFFSET)
            end
        end
    end
end

-- Native fit changes reapply stored geometry only to visible, safe windows.
InstallPanelPositionHook = function()
    if positionHooked then return end
    positionHooked = true
    hooksecurefunc("UpdateUIPanelPositions", OnPanelPositionsUpdated)
    hooksecurefunc("UpdateScaleForFitForOpenPanels", WindowControls.Refresh)
end

local function SavePosition(state, point)
    local frame = state.frame
    if not point then return false end
    local positions = NS.DB.windowControls.positions
    CommitWithHistory(NS.L["Move %s"]:format(Chrome.Title(state)), "positions." .. state.name, function()
        positions[state.name] = point
        return true
    end)
    state.customPosition = true
    if not CanChangeFrameGeometry(frame) then NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow) return true end
    ApplyStoredPosition(state)
    -- The caption's glyphs sit on whole screen pixels of the new place.
    if HasCaption(state) and not IsCombat() then Chrome.ShowCaption(state, Chrome.Level(state) + CONTROL_LEVEL_OFFSET) end
    return true
end

local function Restore(state)
    if not state or not state.minimized or not Policy.CanChangeVisibility(state) then return false end
    if state.park then
        local restored = Policy.RestorePark(state)
        if restored then ApplyStoredPosition(state) end
        return restored
    end
    if Policy.SecureOnly(state) then return false end
    state.frame:Show()
    return state.frame:IsShown() == true -- OnPanelShow drops the tab.
end

local function ToggleFit(state)
    if NS.Client.IsGamepadUI() or not state or state.moving or state.drag
        or not Controlled(state) or not SafeControls(state) then return end
    if Chrome.ToggleFit(state, Policy.CaptureNativePoints) then
        if state.fit then InstallPanelPositionHook() end
        WindowControls.Refresh()
        GeometryChanged(state.frame)
        if state.fit then state.fit.initialScale, state.fit.initialX, state.fit.initialY = nil, nil, nil end
    end
end
local function PrepareMinimize(state)
    if not state or state.minimized or state.moving or state.drag or NS.Client.IsGamepadUI()
        or not Controlled(state) or Safety.Read(state.frame, "IsShown") ~= true then return false end
    if not Policy.CanChangeVisibility(state) then Chrome.SyncMinimize(state) return false end
    return Policy.PrepareRestoreTab(state)
end
local function FinishMinimize(state)
    if state.frame:IsShown() then
        state.minimized = false
    else
        state.restore:Show()
    end
end

local function Minimize(state)
    if not state then return end
    local park = Policy.NeedsPark(state)
    if park and (IsCombat() or Policy.CanNativeMinimize(state) or not Policy.CanPark(state)) then return end
    if not PrepareMinimize(state) then return end
    if park then return Policy.Park(state, InstallPanelPositionHook) end
    state.frame:Hide()
    FinishMinimize(state)
end

local function OnRestoreClick(bar, mouseButton)
    local state = controlStates[bar]
    if not state then return end
    if mouseButton == "RightButton" and not state.park then
        state.minimized = false
        activeStates[state.frame] = state.frame:IsShown() and state or nil
        bar:Hide()
    else
        Restore(state)
    end
end

local function OnMinimizeClick(button)
    Minimize(controlStates[button])
end
local function OnMaximizeClick(button)
    ToggleFit(controlStates[button])
end

-- Scale grip. The drag follows the cursor from a transient OnUpdate that clears
-- itself on release/hide, or if its panel becomes protected in combat.

local function EndDrag(state)
    local grip, drag = state.dragGrip or state.grip, state.drag
    grip:SetScript("OnUpdate", nil)
    if not drag then return end
    state.drag, state.dragGrip = nil, nil
    GeometryInteraction(state.frame, false)
    if not CanChangeFrameGeometry(state.frame) or not Safety.CanDecorate(grip, not IsCombat()) then return end
    if grip:IsMouseOver() then grip:SetButtonState("NORMAL") end
    local scale = state.frame:GetScale()
    -- A press that changed nothing (a click, or A on the grip under Forever's
    -- Gamepad UI) stores nothing and leaves no history entry.
    if not PublicNumber(scale) or scale == drag.scale then return end
    if NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales then
        local value = math.floor(scale * 100 + 0.5) / 100
        CommitWithHistory(NS.L["Scale %s"]:format(Chrome.Title(state)), "scales." .. state.name, function()
            NS.DB.windowControls.scales[state.name] = value
            return true
        end)
        state.customScale = true
        InstallPanelPositionHook()
        if state.customPosition then ApplyStoredPosition(state) end
        if SafeControls(state) and not state.suitePresentation then
            if HasCaption(state) then Chrome.ShowCaption(state, Chrome.Level(state) + CONTROL_LEVEL_OFFSET) end
            Chrome.PlaceGrip(state.grip, state)
            Chrome.PlaceTitleDrag(state.titleDrag, state)
        end
    end
end

local function UpdateDrag(state)
    local drag = state.drag
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then
        EndDrag(state)
        return
    end
    if not CanChangeFrameGeometry(state.frame) or not state.frame:IsShown() then
        EndDrag(state)
        return
    end
    local x, y = GetCursorPosition()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local current = state.frame:GetScale()
    if not PublicNumber(current) then return end
    local delta = ((x - drag.x) + (drag.y - y)) * 0.5
    local scale = ClampScale(drag.scale + delta / drag.pixels)
    scale = math.floor(scale * 100 + 0.5) / 100
    local fit = state.suiteBounds and Policy.FitGeometry(state)
    if fit then scale = math.min(scale, fit) end
    if scale ~= current then
        state.frame:SetScale(scale)
        if state.name == "BankFrame" and SafeControls(state) then Chrome.PlaceGrip(state.grip, state) end
    end
end

local function OnGripUpdate(grip)
    local state = controlStates[grip]
    if state and state.drag then
        UpdateDrag(state)
    else
        grip:SetScript("OnUpdate", nil)
    end
end

local function BeginDrag(state, grip)
    if not CanChangeFrameGeometry(state.frame) or not SafeControls(state) or not Enabled() or Maximized(state) or state.fit then return end
    if state.inventory and not state.customScale and not state.customPosition then Policy.CaptureNativeBagLayout(state) end
    local x, y = GetCursorPosition()
    local frame = state.frame
    local width, height
    if state.suiteBounds then width, height = state.suiteBounds.width, state.suiteBounds.height
    else width, height = frame:GetWidth(), frame:GetHeight() end
    local effective, scale = frame:GetEffectiveScale(), frame:GetScale()
    if type(x) ~= "number" or type(y) ~= "number" or not (PublicNumber(width) and PublicNumber(height)
        and PublicNumber(effective) and PublicNumber(scale)) or effective <= 0 or scale <= 0 then return end
    local pixels = math.max(width, height) * effective / scale
    if pixels <= 0 then return end
    local drag = state.dragStart or {}
    state.dragStart = drag
    drag.x, drag.y = x, y
    drag.scale, drag.pixels = scale, pixels
    grip = grip or state.grip
    controlStates[grip] = state
    state.drag, state.dragGrip = drag, grip
    GeometryInteraction(frame, true)
    grip:SetScript("OnUpdate", OnGripUpdate)
end

local function OnGripMouseDown(grip, mouseButton)
    if mouseButton == "LeftButton" then BeginDrag(controlStates[grip]) end
end

local function OnGripRelease(grip)
    EndDrag(controlStates[grip])
end

local function OnGripEnter(grip)
    GameTooltip:SetOwner(grip, "ANCHOR_RIGHT")
    GameTooltip:SetText(NS.L["Drag to scale this window"])
    GameTooltip:Show()
end

local function OnGripLeave()
    GameTooltip:Hide()
end

local function CreateGrip(state)
    local grip = Safety.CreateChildFrame("Button", Chrome.Parent(state))
    controlStates[grip] = state
    grip:SetSize(20, 20)
    grip:SetFrameLevel(Chrome.Level(state) + GRIP_LEVEL_OFFSET)
    if state.name == "BankFrame" then grip:SetClampedToScreen(true) end
    Chrome.PlaceGrip(grip, state)
    if state.name == "WorldMapFrame" or state.name == "BankFrame" then
        Chrome.StyleGrip(grip)
    else
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    end
    grip:RegisterForClicks("LeftButtonUp")
    grip:SetScript("OnMouseDown", OnGripMouseDown)
    grip:SetScript("OnMouseUp", OnGripRelease)
    grip:SetScript("OnHide", OnGripRelease)
    grip:SetScript("OnEnter", OnGripEnter)
    grip:SetScript("OnLeave", OnGripLeave)
    return grip
end

local function EndMove(state)
    if not state.moving then return end
    local frame = state.frame
    -- Protected movement waits for combat end; safe panels stop and save at once.
    if IsCombat() and Safety.GetProtection(frame) then
        if not state.stopPending then
            state.stopPending = true
            state.stopPoint = Policy.ScreenPosition(frame) or StoredPoint(state)
            NS.CombatGate.RunOrDefer("windowControls:move:" .. state.name, function() EndMove(state) end)
        end
        return
    end
    state.moving = false
    GeometryInteraction(frame, false)
    state.titleDrag:UnregisterEvent("GLOBAL_MOUSE_UP")
    state.titleDrag:UnregisterEvent("PLAYER_REGEN_DISABLED")
    local point, interrupted = state.stopPoint, state.stopPending
    state.stopPoint, state.stopPending = nil, nil
    if Safety.IsForbidden(frame) then return end
    frame:StopMovingOrSizing()
    if state.nativeMovable == false then frame:SetMovable(false) end
    state.nativeMovable = nil
    if not interrupted then point = Policy.ScreenPosition(frame) end
    SavePosition(state, point)
end

local function BeginMove(state)
    if IsCombat() or not Controlled(state) or not SafeControls(state) or Maximized(state) or state.fit then return end
    if state.inventory and not state.customScale and not state.customPosition then Policy.CaptureNativeBagLayout(state) end
    local frame = state.frame
    local movable = Safety.Read(frame, "IsMovable")
    state.nativeMovable = movable
    if movable == false then frame:SetMovable(true) end
    -- StartMoving raises on a frame that is not movable.
    if Safety.Read(frame, "IsMovable") ~= true then
        if movable == false then frame:SetMovable(false) end
        state.nativeMovable = nil
        return
    end
    Policy.ReleasePositionClamp(state)
    frame:StartMoving()
    state.moving = true
    GeometryInteraction(frame, true)
    state.titleDrag:RegisterEvent("GLOBAL_MOUSE_UP")
    state.titleDrag:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function OnTitleDragStart(strip)
    BeginMove(controlStates[strip])
end

local function OnTitleRelease(strip)
    EndMove(controlStates[strip])
end

local function CreateTitleDrag(state)
    -- The title area of standard Blizzard panels is clear (and below it on
    -- Forever): the drag target stays there, away from portraits and buttons.
    local strip = Safety.CreateChildFrame("Frame", Chrome.Parent(state))
    controlStates[strip] = state
    Chrome.PlaceTitleDrag(strip, state)
    strip:SetFrameLevel(Chrome.Level(state) + CONTROL_LEVEL_OFFSET)
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", OnTitleDragStart)
    strip:SetScript("OnDragStop", OnTitleRelease)
    -- No OnMouseUp/OnMouseDown on this Frame: Forever's SmartNavigation reads both
    -- with GetScript on every non-Button of a panel it scans (Blizzard_GamepadSmart-
    -- Navigation/Utility.lua:196-206); the skin's handler tainted that secure scan and
    -- the gamepad bindings after it (B on the Game Menu: SetPreferredGamepadInteract-
    -- Target blocked). Release net: GLOBAL_MOUSE_UP, registered only while moving.
    strip:SetScript("OnEvent", OnTitleRelease)
    strip:SetScript("OnHide", OnTitleRelease)
    return strip
end

local function Settles(state)
    return HasCaption(state) and activeStates[state.frame] == state and Controlled(state) and SafeControls(state)
end
local function ShowControls(state)
    if state.suitePresentation then
        state.titleDrag:Hide()
        state.grip:Hide()
        Chrome.HideCaption(state)
        return
    end
    local level = Chrome.Level(state)
    if HasCaption(state) then
        Chrome.ShowCaption(state, level + CONTROL_LEVEL_OFFSET)
        Chrome.Settle(state, level + CONTROL_LEVEL_OFFSET, Settles)
    end
    if Maximized(state) then
        state.titleDrag:Hide()
        state.grip:Hide()
        return
    end
    Chrome.PlaceGrip(state.grip, state)
    Chrome.PlaceTitleDrag(state.titleDrag, state)
    Policy.SetLevel(state.titleDrag, level + CONTROL_LEVEL_OFFSET)
    Policy.SetLevel(state.grip, level + GRIP_LEVEL_OFFSET)
    if state.fit then
        state.titleDrag:Hide()
        state.grip:Hide()
    else
        state.titleDrag:Show()
        state.grip:Show()
    end
end

-- Controls off: a panel the grip scaled gets Blizzard's scale back (the
-- stored scale stays and returns with the controls).
local function RestoreNativeScale(state, releasing)
    local mayChange = releasing and Policy.CanChangeGeometry or CanChangeFrameGeometry
    if not state.customScale or not mayChange(state.frame) then return end
    state.customScale = false
    if type(state.originalScale) == "number" then state.frame:SetScale(state.originalScale) end
end

local function HideControls(state, releasing)
    activeInventory[state.frame] = nil
    if IsCombat() and (state.park or not CanChangeFrameGeometry(state.frame) or not SafeControls(state)) then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return
    end
    if state.moving then EndMove(state) end
    if state.drag then EndDrag(state) end
    if state.park then Policy.RestorePark(state)
    elseif state.minimized then
        Restore(state)
        state.minimized = false
        state.restore:Hide()
        activeStates[state.frame] = state.frame:IsShown() and state or nil
    end
    Chrome.LeaveFit(state)
    Policy.ReleasePositionClamp(state)
    state.titleDrag:Hide()
    state.grip:Hide()
    Chrome.HideCaption(state)
    RestoreNativeScale(state, releasing)
    if state.customPosition and not IsCombat() then Policy.RestoreNativePosition(state, releasing) end
end

local function EnsureCaption(state)
    local frame, name = state.frame, state.name
    if state.maximize or state.closeOnly or NS.Client.IsGamepadUI() then return end
    if not state.close then state.close = Chrome.FindClose(frame, name) end
    if not state.minimize and Policy.IsMinimizable(name) then
        state.restore = Chrome.CreateRestore(state, OnRestoreClick)
        controlStates[state.restore] = state
        state.minimize = Chrome.CreateMinimize(state, state.close, CONTROL_LEVEL_OFFSET, OnMinimizeClick)
        controlStates[state.minimize] = state
        Delegate.Bind(state, PrepareMinimize, FinishMinimize)
    end
    if not state.close then return end
    local toggle = state.sizeToggle or Chrome.NativeSizeToggle(frame, state.close)
    if not toggle and Chrome.HasNativeCaption(frame, name, state.close) then
        state.nativeCaption = true
        return
    end
    if toggle and not state.sizeToggle then Chrome.FollowSizeToggle(state, toggle) end
    local button = Chrome.CreateCaption(state, CONTROL_LEVEL_OFFSET, OnMaximizeClick)
    if button then controlStates[button] = state end
end

local function OnPanelShow(frame, afterNative)
    local state = WindowControls.states[frame]
    if not state or Safety.IsForbidden(frame) then return end
    if state.park and Policy.ResumePark(state, Controlled(state)) then return end
    activeStates[frame] = state
    if not afterNative and Policy.DeferMailLayout(state) then
        if IsCombat() then QueuePosition(state) end
        return
    end
    if state.inventory then activeInventory[frame] = Controlled(state) and state or nil end
    if state.restore then
        state.minimized = false
        if Safety.CanDecorate(state.restore, not IsCombat()) then state.restore:Hide() end
    end
    local deferred = Policy.DeferMapLayout(state, afterNative)
    if not deferred and IsCombat() and not CanChangeFrameGeometry(frame) then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        deferred = true
    end
    if deferred then
        if IsCombat() then QueuePosition(state) end
        if IsCombat() and HasCaption(state) and SafeControls(state) then Chrome.ShowCaption(state, Chrome.Level(state) + CONTROL_LEVEL_OFFSET) end
        return
    end
    if Controlled(state) then
        -- Restore scale first because the saved position depends on it.
        if not state.drag then ApplyStoredScale(state) end
        ApplyStoredPosition(state)
        if IsCombat() and not SafeControls(state) then
            NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
            return
        end
        EnsureCaption(state)
        ShowControls(state)
    else
        HideControls(state)
    end
end

-- Native bag layout resets the scale and anchors of every shown bag. Only
-- owned, visible native inventory roots participate; closed history stays cold.
local function OnContainerPositionsUpdated()
    for frame, state in pairs(activeInventory) do
        if state.park then
            Policy.HoldPark(state)
        elseif Controlled(state) then
            if state.customScale or state.customPosition then Policy.CaptureNativeBagLayout(state) end
            if not Policy.DeferMailLayout(state) then
                if not state.drag then ApplyStoredScale(state) end
                ApplyStoredPosition(state)
            end
        elseif IsCombat() and not Policy.CanChangeGeometry(frame) then
            NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        else
            activeInventory[frame] = nil
        end
    end
end

local containerHooked = false
local function TrackInventory(state)
    if not state.inventory then return end
    if state.frame:IsShown() then activeInventory[state.frame] = state end
    if not containerHooked and Safety.HasMethod(_G, "UpdateContainerFrameAnchors") then
        hooksecurefunc("UpdateContainerFrameAnchors", OnContainerPositionsUpdated)
        containerHooked = true
    end
end

local function OnPanelHide(frame)
    local state = WindowControls.states[frame]
    if not state then return end
    -- A parked window restores its native anchors after close. Minimized and
    -- clamped windows can also owe a release when their controls were disabled.
    if not state.park and not state.minimized and not state.positionClamp then
        NS.Registry.CancelJob(state.replayShow)
    end
    if state.park and not frame:IsShown() then Policy.ParkClosed(state) end
    activeInventory[frame] = nil
    if not state.minimized then activeStates[frame] = nil end
    if state.drag then EndDrag(state) end
    if state.moving then EndMove(state) end
    if state.fit then Chrome.EndFit(state) end
    if state.restore and not state.minimized then state.restore:Hide() end
end

local function PrepareHiddenPosition(state)
    if IsCombat() or not Policy.UsesPositionClamp(state) or state.park then return end
    if not Controlled(state) then return Policy.ReleasePositionClamp(state) end
    if state.positionClamp or StoredPoint(state) then
        ApplyStoredScale(state)
        ApplyStoredPosition(state)
    end
end

function WindowControls.Attach(frame, owner)
    TrackFocus(frame, owner)
    if not Enabled() then return false end
    local name, _, panel = Policy.Eligible(frame)
    local state = WindowControls.states[frame]
    if not name then
        -- A panel that became protected keeps no grip or drag strip.
        if state and (state.inventory or Safety.GetProtection(frame)) then HideControls(state) end
        return false
    end
    if state then
        state.owners[owner or "blizzardWindows"] = true
        TrackInventory(state)
        if frame:IsShown() then OnPanelShow(frame) else PrepareHiddenPosition(state) end
        return true
    end
    state = {
        frame = frame,
        name = name,
        panel = panel,
        inventory = Policy.IsInventory(frame),
        originalScale = Safety.Read(frame, "GetScale"),
        nativePoints = Policy.CaptureNativePoints(frame),
        replayKey = "windowControls:show:" .. name,
        owners = { [owner or "blizzardWindows"] = true },
    }
    WindowControls.states[frame] = state
    TrackInventory(state)
    if frame:IsShown() then activeStates[frame] = state end
    state.replayShow = function()
        if frame:IsShown() then OnPanelShow(frame, true)
        elseif state.park then Policy.RestorePark(state)
        elseif (state.minimized or state.positionClamp) and not Controlled(state) then HideControls(state, not next(state.owners)) end
    end
    state.grip = CreateGrip(state)
    local deferLayout = Policy.DeferMapLayout(state)
    if not deferLayout then ApplyStoredScale(state) end
    state.titleDrag = CreateTitleDrag(state)
    if not deferLayout then ApplyStoredPosition(state) elseif IsCombat() then QueuePosition(state) end
    EnsureCaption(state)
    ShowControls(state)
    frame:HookScript("OnShow", OnPanelShow)
    frame:HookScript("OnHide", OnPanelHide)
    return true
end

function WindowControls.DisableOwner(owner)
    ReleaseFocus(owner)
    for _, state in pairs(WindowControls.states) do
        state.owners[owner] = nil
        if not next(state.owners) then
            HideControls(state, true)
        end
    end
end

local function RefreshHiddenClamps()
    for frame, state in pairs(WindowControls.states) do
        if Policy.UsesPositionClamp(state) and Safety.Read(frame, "IsShown") == false then PrepareHiddenPosition(state) end
    end
end

function WindowControls.SetEnabled(enabled)
    if IsCombat() then return false, "combat" end
    NS.DB.windowControls.enabled = enabled == true
    NS.Registry.NotifyListeners("windowControls", "enabled")
    if enabled then NS.Adapters.ApplyAll() end
    RefreshHiddenClamps()
    WindowControls.Refresh()
    return true
end

function WindowControls.Refresh()
    for frame in pairs(activeStates) do
        if Safety.Read(frame, "IsShown") then OnPanelShow(frame)
        elseif not Controlled(activeStates[frame]) then HideControls(activeStates[frame]) end
    end
    return true
end

local function RefreshQueued()
    RefreshHiddenClamps()
    WindowControls.Refresh()
end

local function RecolorMinimize()
    for _, state in pairs(activeStates) do
        if SafeControls(state) then
            if state.name == "WorldMapFrame" or state.name == "BankFrame" then Chrome.RecolorGrip(state.grip) end
            if state.inventory then Chrome.RecolorControl(state.titleDrag) end
            Chrome.RecolorCaption(state)
            if state.restore then Chrome.RecolorControl(state.restore) end
        elseif IsCombat() then NS.CombatGate.RunOrDefer("windowControls:colors", RecolorMinimize) end
    end
end

-- Coalesce settings writes before repainting the visible windows.
function WindowControls:OnThemeChanged(domain, key)
    if domain == "profile" or domain == "theme" and key == "look" then NS.Registry.QueueJob(RefreshQueued) end
    if domain ~= "theme" and domain ~= "color" and domain ~= "appearance" and domain ~= "profile"
        and domain ~= "windowAction" then return end
    NS.Registry.QueueJob(RecolorMinimize)
end

NS.Registry.AddListener(WindowControls, WindowControls.OnThemeChanged)

function WindowControls.ResetScales()
    if IsCombat() then return false, "combat" end
    NS.DB.windowControls.scales = {}
    for _, state in pairs(WindowControls.states) do
        if state.fit then Chrome.LeaveFit(state) end
        if type(state.originalScale) == "number" and CanChangeFrameGeometry(state.frame) then
            state.frame:SetScale(state.originalScale)
        end
        state.customScale = false
    end
    RefreshHiddenClamps()
    WindowControls.Refresh()
    return true
end

local function FinishRestore(state)
    Policy.RestoreNativePosition(state)
    return true
end

function WindowControls.ResetPositions()
    if IsCombat() then return false, "combat" end
    for _, state in pairs(WindowControls.states) do
        if state.moving then EndMove(state) end
        if state.fit then Chrome.LeaveFit(state) end
        if state.park then Policy.RestorePark(state) end
    end
    NS.DB.windowControls.positions = {}
    -- Blizzard's layout pass must not move panels back while they return
    -- to their native anchors. Each restore is its own boundary, so a failed
    -- one is reported and the layout hook always resumes.
    local failed = false
    suspendPositionHook = true
    for _, state in pairs(WindowControls.states) do
        if state.customPosition and not Safety.Dispatch(FinishRestore, state) then
            failed = true
        end
    end
    suspendPositionHook = false
    -- Reset returns to the selected look's default placement on Forever.
    for _, state in pairs(WindowControls.states) do
        if next(state.owners) then ApplyStoredPosition(state) end
    end
    WindowControls.Refresh()
    if failed then return false, "error" end
    return true
end

function WindowControls.ResetLayout()
    if IsCombat() then return false, "combat" end
    local scaled = WindowControls.ResetScales()
    local moved = WindowControls.ResetPositions()
    return scaled and moved
end

function WindowControls.SetSuitePresentation(frame, visible)
    local state = WindowControls.states[frame]
    if not state or state.suitePresentation == visible then return end
    state.suitePresentation = visible
    if Controlled(state) and Safety.Read(frame, "IsShown") == true and SafeControls(state) then
        if IsCombat() then NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        else ShowControls(state) end
    end
end

function WindowControls.SuiteAction(frame, bounds, action, control)
    local state = WindowControls.states[frame]
    if action == "moveStop" then return state and EndMove(state) end
    if action == "scaleStop" then return state and state.grip and EndDrag(state) end
    if action == "release" then
        if not state then return end
        state.suiteBounds = nil
        state.suiteConstrained, state.suitePresentation = nil, nil
        if state.fit and not IsCombat() then Chrome.LeaveFit(state) end
        if not IsCombat() then
            ApplyStoredScale(state)
            ApplyStoredPosition(state)
        end
        if state.owners.suiteCharacterPanel then WindowControls.DisableOwner("suiteCharacterPanel") end
        return
    end
    if IsCombat() or frame ~= CharacterFrame then return end
    if (not state or not Controlled(state)) and not WindowControls.Attach(frame, "suiteCharacterPanel") then return end
    state = WindowControls.states[frame]
    if not Controlled(state) then return end
    local prepare = state.suiteBounds == nil
    state.suiteBounds = bounds
    if prepare or action == "prepare" then
        ApplyStoredScale(state)
        ApplyStoredPosition(state)
    end
    -- The Suite's own cell (control) minimizes as ours: Blizzard's X through the delegate.
    if action == "bindMinimize" then
        if control and state.restore then Delegate.BindMinimize(control, state, PrepareMinimize, FinishMinimize) end
        return control ~= nil and state.restore ~= nil
    end
    if action == "maximize" then ToggleFit(state)
    elseif action == "minimize" and state.restore then
        Minimize(state)
    elseif action == "moveStart" then BeginMove(state)
    elseif action == "scaleStart" then BeginDrag(state, control) end
    return action == "minimize" and state.minimized == true or action ~= "minimize" and state.fit ~= nil
end
return WindowControls
