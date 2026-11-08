local _, NS = ...

-- Window geometry, separate from cosmetic skinning: only reviewed top-level Blizzard
-- panels, native controls win, no global frame scans or permanent OnUpdate.
local WindowControls = { states = setmetatable({}, { __mode = "k" }) }
NS.WindowControls = WindowControls
local TrackFocus, ReleaseFocus = function() end, function() end
function WindowControls.SetFocusProvider(track, release) TrackFocus, ReleaseFocus = track, release end
function WindowControls.TrackFocus(frame, owner) return TrackFocus(frame, owner) end

local Safety = NS.Safety
local Policy = NS.WindowControlPolicy
local Chrome = NS.WindowControlChrome
local CanChangeFrameGeometry = Policy.CanControl

local positionedStates = setmetatable({}, { __mode = "k" })
local activeStates = setmetatable({}, { __mode = "k" })
local activeInventory = setmetatable({}, { __mode = "k" })
-- Our grip, drag strip, minimize and restore frames -> panel state (shared handlers).
local controlStates = setmetatable({}, { __mode = "k" })

local FOREVER_CHARACTER_DOCK = { x = 0, y = 0 }
-- Our controls sit this many levels above their panel.
local CONTROL_LEVEL_OFFSET = 15
local GRIP_LEVEL_OFFSET = 20

local nativeMinimize = {
    WorldMapFrame = true, PlayerSpellsFrame = true,
}
-- Only persistent, player-opened windows get a restore tab (closing an NPC panel ends it).
local minimizablePanels = {
    CharacterFrame = true, FriendsFrame = true, PVEFrame = true,
    PVPUIFrame = true, ProfessionsBookFrame = true,
    CollectionsJournal = true, EncounterJournal = true,
    SettingsPanel = true, AddonList = true,
    LFGParentFrame = true, LegacySystemFrame = true,
}
local function IsCombat()
    return NS.IsCombatLocked()
end

local function Enabled()
    local db = NS.DB
    return db and db.enabled ~= false and db.windowControls
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

local function SafeControls(state)
    local implicit = not IsCombat()
    return Safety.CanDecorate(state.grip, implicit) and Safety.CanDecorate(state.titleDrag, implicit)
        and (not state.minimize or Safety.CanDecorate(state.minimize, implicit))
        and (not state.maximize or Safety.CanDecorate(state.maximize, implicit))
        and (not state.captionMin or Safety.CanDecorate(state.captionMin, implicit))
end

local function Maximized(state)
    return state.name == "WorldMapFrame" and Safety.Read(state.frame, "IsMaximized") == true
end

local InstallPanelPositionHook

local function ApplyStoredScale(state)
    if not CanChangeFrameGeometry(state.frame) or state.fit then return end
    if Maximized(state) then
        if state.frame:GetScale() ~= state.originalScale then state.frame:SetScale(state.originalScale) end
        return
    end
    local limits = NS.WindowLayoutLimits
    local scales = NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales
    local stored = scales and scales[state.name]
    local scale
    if type(stored) == "number" and stored >= limits.minScale and stored <= limits.maxScale then
        scale = stored
        state.customScale = true
        InstallPanelPositionHook()
    elseif state.customScale then
        scale = state.originalScale
        state.customScale = false
    end
    if type(scale) == "number" and state.frame:GetScale() ~= scale then
        state.frame:SetScale(scale)
    end
end

-- The panel's own anchors when all are readable (secret-anchored layout returns secrets).
local function CaptureNativePoints(frame)
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

local function CaptureNativeBagLayout(state)
    if state.name == "BankFrame" or not state.nativePoints or #state.nativePoints ~= 1 then return end
    local frame, saved = state.frame, state.nativePoints[1]
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    local public = Safety.Public
    if not public(point) or not public(relative) or not public(relativePoint) or not public(x) or not public(y) then return end
    saved[1], saved[2], saved[3], saved[4], saved[5] = point, relative, relativePoint, x, y
    state.originalScale = frame:GetScale()
end

local function RestoreNativePosition(state, releasing)
    local mayChange = releasing and Policy.CanChangeGeometry or CanChangeFrameGeometry
    if not mayChange(state.frame) then return end
    local panel = state.panel
    if panel and Safety.Read(state.frame, "GetAttribute", "UIPanelLayout-defined") == true then
        local area = Safety.Call(state.frame, "GetAttribute", "UIPanelLayout-area")
        if Safety.Public(area) and area == nil then panel = nil end
    end
    if IsCombat() and panel and not panel.centerFrameSkipAnchoring and not NS.Client.IsGamepadUI() then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return
    end
    state.customPosition = false
    state.defaultPosition = false
    positionedStates[state.frame] = nil
    -- The panel manager never anchors the Game Menu (centerFrameSkipAnchoring).
    if panel and not panel.centerFrameSkipAnchoring then
        -- Under the Gamepad UI Blizzard places the panel again when it next opens.
        if not NS.Client.IsGamepadUI() then UpdateUIPanelPositions(state.frame) end
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

local function ApplyStoredPosition(state)
    if not CanChangeFrameGeometry(state.frame) or not Enabled() or state.moving or Maximized(state) then return end
    if state.fit then return Chrome.Fit(state) end
    local positions = NS.DB and NS.DB.windowControls and NS.DB.windowControls.positions
    local point = positions and positions[state.name]
    local defaultPosition = not point and state.name == "CharacterFrame"
        and NS.Client.isForever and NS.DB.theme.look == "foreverGlass"
    if defaultPosition then point = FOREVER_CHARACTER_DOCK end
    if not point then
        if state.customPosition then RestoreNativePosition(state) end
        return
    end
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local uiScale = UIParent:GetEffectiveScale()
    if not uiWidth or not uiHeight or not uiScale or uiScale <= 0 then return end
    local ratio = state.frame:GetEffectiveScale() / uiScale
    if ratio <= 0 then return end
    local width, height = state.frame:GetWidth() * ratio, state.frame:GetHeight() * ratio
    local rightInset, bottomInset, topInset = Chrome.Footprint(state)
    width, height = width + rightInset * ratio, height + bottomInset * ratio
    local x = math.max(0, math.min(uiWidth - math.min(uiWidth, width), point.x))
    local y = math.max(-math.max(0, uiHeight - height), math.min(-topInset * ratio, point.y))
    state.frame:ClearAllPoints()
    state.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / ratio, y / ratio)
    if SafeControls(state) then
        Chrome.PlaceGrip(state.grip, state)
        Chrome.PlaceTitleDrag(state.titleDrag, state)
    end
    state.customPosition = true
    state.defaultPosition = defaultPosition == true
    positionedStates[state.frame] = state.frame:IsShown() and state or nil
    -- Keep custom placement after native panel layout.
    InstallPanelPositionHook()
end

local positionHooked = false
local suspendPositionHook = false

-- Blizzard's panel layout re-anchors open panels; ours move back after it.
local function OnPanelPositionsUpdated()
    if suspendPositionHook or not Enabled() then return end
    for frame, state in pairs(activeStates) do
        if Controlled(state) and frame:IsShown() and not Policy.DeferMapLayout(state) then
            if not state.drag then ApplyStoredScale(state) end
            ApplyStoredPosition(state)
            if (state.maximize or state.minimize) and SafeControls(state) then
                Chrome.ShowCaption(state, Chrome.Level(state) + CONTROL_LEVEL_OFFSET)
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

local function SavePosition(state)
    local frame = state.frame
    local left, top = Safety.Read(frame, "GetLeft"), Safety.Read(frame, "GetTop")
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then return false end
    local ratio = frame:GetEffectiveScale() / uiScale
    local uiHeight = UIParent:GetHeight()
    if type(left) ~= "number" or type(top) ~= "number"
        or type(uiHeight) ~= "number" or ratio <= 0 then return false end
    local positions = NS.DB.windowControls.positions
    local x = math.floor(left * ratio + 0.5)
    local y = math.floor((top * ratio - uiHeight) + 0.5)
    CommitWithHistory(NS.L["Move %s"]:format(Chrome.Title(state)), "positions." .. state.name, function()
        positions[state.name] = { x = x, y = y }
        return true
    end)
    state.customPosition = true
    if CanChangeFrameGeometry(frame) then ApplyStoredPosition(state)
    else NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow) end
    return true
end

local function Restore(state)
    if not state or not state.minimized then return false end
    local allowed, managed = Policy.CanChangeVisibility(state)
    if not allowed then return false end
    if managed and not NS.Client.IsGamepadUI() then
        ShowUIPanel(state.frame)
    else
        state.frame:Show()
    end
    -- OnPanelShow drops the tab. Blizzard can refuse the panel (a center
    -- panel such as the Game Menu is open): the tab stays for another try.
    return state.frame:IsShown() == true
end

local function ToggleFit(state)
    if NS.Client.IsGamepadUI() or not state or state.moving or state.drag
        or not Controlled(state) or not SafeControls(state) then return end
    if Chrome.ToggleFit(state, CaptureNativePoints) then
        if state.fit then InstallPanelPositionHook() end
        WindowControls.Refresh()
    end
end

local function Minimize(state)
    if NS.Client.IsGamepadUI() or not state or state.minimized or not Controlled(state) then return end
    local allowed, managed = Policy.CanChangeVisibility(state)
    if not allowed then Chrome.SyncMinimize(state) return end
    -- Native OnHide resets pending changes. Keep the editor open until the
    -- user explicitly applies or cancels them; never write its save flag.
    if state.name == "AddonList" and AddonList_HasAnyChanged() then return false end
    Chrome.LeaveFit(state)
    local frame = state.frame
    local left, top = frame:GetLeft(), frame:GetTop()
    local uiScale = UIParent:GetEffectiveScale()
    local frameScale = frame:GetEffectiveScale()
    state.restore:ClearAllPoints()
    if type(left) == "number" and type(top) == "number" and uiScale > 0 then
        state.restore:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            left * frameScale / uiScale, top * frameScale / uiScale)
    else
        state.restore:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
    state.restoreLabel:SetText(Chrome.Title(state) .. "  +")
    state.minimized = true
    if managed then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
    if frame:IsShown() then
        state.minimized = false
    else
        state.restore:Show()
    end
end

local function OnRestoreClick(bar, mouseButton)
    local state = controlStates[bar]
    if not state then return end
    if mouseButton == "RightButton" then
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
    local grip, drag = state.grip, state.drag
    grip:SetScript("OnUpdate", nil)
    if not drag then return end
    state.drag = nil
    if not CanChangeFrameGeometry(state.frame) or not Safety.CanDecorate(grip, not IsCombat()) then return end
    if grip:IsMouseOver() then grip:SetButtonState("NORMAL") end
    local scale = state.frame:GetScale()
    -- A press that changed nothing (a click, or A on the grip under Forever's
    -- Gamepad UI) stores nothing and leaves no history entry.
    if scale == drag.scale then return end
    if NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales then
        local value = math.floor(scale * 100 + 0.5) / 100
        CommitWithHistory(NS.L["Scale %s"]:format(Chrome.Title(state)), "scales." .. state.name, function()
            NS.DB.windowControls.scales[state.name] = value
            return true
        end)
        state.customScale = true
        InstallPanelPositionHook()
        if SafeControls(state) then
            if state.maximize or state.minimize then Chrome.ShowCaption(state, Chrome.Level(state) + CONTROL_LEVEL_OFFSET) end
            Chrome.PlaceGrip(grip, state)
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
    local delta = ((x - drag.x) + (drag.y - y)) * 0.5
    local scale = ClampScale(drag.scale + delta / drag.pixels)
    scale = math.floor(scale * 100 + 0.5) / 100
    if scale ~= state.frame:GetScale() then state.frame:SetScale(scale) end
end

local function OnGripUpdate(grip)
    local state = controlStates[grip]
    if state and state.drag then
        UpdateDrag(state)
    else
        grip:SetScript("OnUpdate", nil)
    end
end

local function BeginDrag(state)
    if not CanChangeFrameGeometry(state.frame) or not SafeControls(state) or not Enabled() or Maximized(state) or state.fit then return end
    if state.inventory and not state.customScale and not state.customPosition then CaptureNativeBagLayout(state) end
    local x, y = GetCursorPosition()
    local frame = state.frame
    local width, height = frame:GetWidth(), frame:GetHeight()
    local parentScale = frame:GetEffectiveScale() / frame:GetScale()
    if type(x) ~= "number" or type(y) ~= "number"
        or not width or not height or not parentScale or parentScale <= 0 then return end
    local drag = state.dragStart or {}
    state.dragStart = drag
    drag.x, drag.y = x, y
    drag.scale = frame:GetScale()
    drag.pixels = math.max(width, height) * parentScale
    state.drag = drag
    state.grip:SetScript("OnUpdate", OnGripUpdate)
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
    Chrome.PlaceGrip(grip, state)
    if state.name == "WorldMapFrame" then
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
        NS.CombatGate.RunOrDefer("windowControls:move:" .. state.name, function() EndMove(state) end)
        return
    end
    state.moving = false
    state.titleDrag:UnregisterEvent("GLOBAL_MOUSE_UP")
    if Safety.IsForbidden(frame) then return end
    frame:StopMovingOrSizing()
    if state.nativeMovable == false then frame:SetMovable(false) end
    state.nativeMovable = nil
    SavePosition(state)
end

local function BeginMove(state)
    if not CanChangeFrameGeometry(state.frame) or not SafeControls(state) or not Enabled() or Maximized(state) or state.fit then return end
    if state.inventory and not state.customScale and not state.customPosition then CaptureNativeBagLayout(state) end
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
    frame:StartMoving()
    state.moving = true
    state.titleDrag:RegisterEvent("GLOBAL_MOUSE_UP")
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

local function ShowControls(state)
    if Maximized(state) then
        state.titleDrag:Hide()
        state.grip:Hide()
        return
    end
    local level = Chrome.Level(state)
    if state.maximize or state.minimize then Chrome.ShowCaption(state, level + CONTROL_LEVEL_OFFSET) end
    Chrome.PlaceGrip(state.grip, state)
    Chrome.PlaceTitleDrag(state.titleDrag, state)
    state.titleDrag:SetFrameLevel(level + CONTROL_LEVEL_OFFSET)
    state.grip:SetFrameLevel(level + GRIP_LEVEL_OFFSET)
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
    if IsCombat() and (not CanChangeFrameGeometry(state.frame) or not SafeControls(state)) then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return
    end
    if state.moving then EndMove(state) end
    if state.drag then EndDrag(state) end
    if state.minimized then Restore(state) end
    Chrome.LeaveFit(state)
    state.titleDrag:Hide()
    state.grip:Hide()
    if state.minimize then state.minimize:Hide() end
    if state.maximize then state.maximize:Hide() end
    if state.captionMin then state.captionMin:Hide() end
    RestoreNativeScale(state, releasing)
    if state.customPosition and not IsCombat() then RestoreNativePosition(state, releasing) end
end

local function CanMinimize(name)
    return minimizablePanels[name] == true and not nativeMinimize[name]
end

local function EnsureCaption(state)
    if state.maximize or nativeMinimize[state.name] or NS.Client.IsGamepadUI() then return end
    local frame, name = state.frame, state.name
    if not state.close then state.close = Chrome.FindClose(frame, name) end
    if not state.close or Chrome.HasNativeCaption(frame, name, state.close) then return end
    if not state.minimize and CanMinimize(name) then
        state.restore = Chrome.CreateRestore(state, OnRestoreClick)
        controlStates[state.restore] = state
        state.minimize = Chrome.CreateMinimize(state, state.close, CONTROL_LEVEL_OFFSET, OnMinimizeClick)
        controlStates[state.minimize] = state
    end
    local button = Chrome.CreateCaption(state, CONTROL_LEVEL_OFFSET, OnMaximizeClick)
    if button then controlStates[button] = state end
end

-- Hooked once per panel. The invisible title strip takes the title area's clicks: it
-- comes back only while the controls are on, an owner skins and it can be controlled.
local function OnPanelShow(frame)
    local state = WindowControls.states[frame]
    if not state or Safety.IsForbidden(frame) then return end
    activeStates[frame] = state
    if state.inventory then activeInventory[frame] = Controlled(state) and state or nil end
    if state.restore then
        state.minimized = false
        state.restore:Hide()
    end
    if Policy.DeferMapLayout(state) then return end
    if IsCombat() and (not CanChangeFrameGeometry(frame) or not SafeControls(state)) then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return
    end
    if Controlled(state) then
        -- Blizzard fits checkFit panels (PlayerSpellsFrame, ProfessionsFrame,
        -- Settings) to the screen with SetScale(1) as they open: the stored
        -- scale comes back first, then the position, which depends on it.
        if not state.drag then ApplyStoredScale(state) end
        ApplyStoredPosition(state)
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
        if Controlled(state) then
            if state.customScale or state.customPosition then CaptureNativeBagLayout(state) end
            if not state.drag then ApplyStoredScale(state) end
            ApplyStoredPosition(state)
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
    positionedStates[frame] = nil
    activeInventory[frame] = nil
    if not state.minimized then activeStates[frame] = nil end
    if state.drag then EndDrag(state) end
    if state.moving then EndMove(state) end
    if state.fit then Chrome.EndFit(state) end
    if state.restore and not state.minimized then state.restore:Hide() end
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
        if frame:IsShown() then OnPanelShow(frame) end
        return true
    end
    state = {
        frame = frame,
        name = name,
        panel = panel,
        inventory = Policy.IsInventory(frame),
        originalScale = frame:GetScale(),
        nativePoints = CaptureNativePoints(frame),
        replayKey = "windowControls:show:" .. name,
        owners = { [owner or "blizzardWindows"] = true },
    }
    WindowControls.states[frame] = state
    TrackInventory(state)
    if frame:IsShown() then activeStates[frame] = state end
    state.replayShow = function()
        if frame:IsShown() then OnPanelShow(frame)
        elseif state.minimized and not Controlled(state) then HideControls(state) end
    end
    state.grip = CreateGrip(state)
    local deferLayout = Policy.DeferMapLayout(state)
    if not deferLayout then ApplyStoredScale(state) end
    state.titleDrag = CreateTitleDrag(state)
    if not deferLayout then ApplyStoredPosition(state) end
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

function WindowControls.SetEnabled(enabled)
    if IsCombat() then return false, "combat" end
    NS.DB.windowControls.enabled = enabled == true
    if enabled then NS.Adapters.ApplyAll() end
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

local function RefreshQueued() WindowControls.Refresh() end

local function RecolorMinimize()
    for _, state in pairs(activeStates) do
        if SafeControls(state) then
            if state.name == "WorldMapFrame" then Chrome.RecolorGrip(state.grip) end
            if state.inventory then Chrome.RecolorControl(state.titleDrag) end
            Chrome.RecolorCaption(state)
            if state.restore then Chrome.RecolorControl(state.restore) end
        elseif IsCombat() then NS.CombatGate.RunOrDefer("windowControls:colors", RecolorMinimize) end
    end
end

-- Once per frame of settings writes: a profile or look switch rebuilds the
-- controls, a colour write or a profile switch repaints them.
function WindowControls:OnThemeChanged(domain, key)
    if domain == "profile" or domain == "theme" and key == "look" then NS.Registry.QueueJob(RefreshQueued) end
    if domain ~= "theme" and domain ~= "color" and domain ~= "appearance" and domain ~= "profile" then return end
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
    WindowControls.Refresh()
    return true
end

-- RestoreNativePosition runs Blizzard's panel layout; true when it finished.
local function FinishRestore(state)
    RestoreNativePosition(state)
    return true
end

function WindowControls.ResetPositions()
    if IsCombat() then return false, "combat" end
    for _, state in pairs(WindowControls.states) do
        if state.moving then EndMove(state) end
        if state.fit then Chrome.LeaveFit(state) end
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

return WindowControls
