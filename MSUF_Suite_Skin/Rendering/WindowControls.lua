local _, NS = ...

-- Window geometry is deliberately separate from cosmetic skinning.  Only
-- reviewed, top-level Blizzard panels are candidates; native controls win.
-- No global frame scans or permanent OnUpdate; geometry is gated below.
local WindowControls = { states = setmetatable({}, { __mode = "k" }) }
NS.WindowControls = WindowControls

local Safety = NS.Safety

-- Panels placed by us, re-placed after Blizzard's panel layout runs.
local positionedStates = setmetatable({}, { __mode = "k" })
-- Our own grip, drag strip, minimize and restore frames, mapped to their
-- panel state so every control shares one set of script handlers.
local controlStates = setmetatable({}, { __mode = "k" })

local FOREVER_CHARACTER_DOCK = { x = 0, y = 0 }
local RESTORE_WIDTH = 154
-- Our controls sit this many levels above their panel.
local CONTROL_LEVEL_OFFSET = 15
local GRIP_LEVEL_OFFSET = 20

local specialPanels = {
    SettingsPanel = true, AddonList = true, PlayerSpellsFrame = true,
    GameMenuFrame = true, ProfessionsFrame = true,
    -- Forever's dedicated skin applies this outer container; its three
    -- PortraitFrame panes follow it and are not generic catalog roots.
    LFGParentFrame = true,
}
local nativeMinimize = {
    WorldMapFrame = true, PlayerSpellsFrame = true,
}
-- Closing an NPC or transient panel can end its game interaction.  Only
-- persistent, player-opened windows get a restore tab.
local minimizablePanels = {
    CharacterFrame = true, FriendsFrame = true, PVEFrame = true,
    PVPUIFrame = true, ProfessionsBookFrame = true,
    CollectionsJournal = true, EncounterJournal = true,
    SettingsPanel = true, AddonList = true,
    LFGParentFrame = true,
}
local excludedCategories = {
    hud = true, inventory = true, tutorial = true, utility = true,
}

local function Limits()
    return NS.WindowLayoutLimits
end

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
    local menu = _G.MSUF2
    if menu and type(menu.RunWithHistory) == "function" and not IsCombat() then
        return menu.RunWithHistory(label, "suite:skin.windowControls." .. key, commit)
    end
    return commit()
end

local function IsBag(name)
    return name:find("^ContainerFrame") or name:find("^BankFrame")
        or name:find("^Bag") or name:find("^Bags")
end

local function CanChangeFrameGeometry(frame)
    if IsCombat() or Safety.IsForbidden(frame) then return false end
    local protected, explicit = Safety.GetProtection(frame)
    if explicit then return false end
    -- Forever's plain spellbook root contains the native secure assisted-
    -- combat button. Only this exact container may use public geometry APIs
    -- out of combat; the secure button and all other protected roots stay out.
    return not protected or (NS.Client.isForever and frame == Safety.Field(_G, "PlayerSpellsFrame"))
end

local function Eligible(frame)
    if not frame or Safety.IsForbidden(frame) then return nil end
    if not CanChangeFrameGeometry(frame) then return nil end
    local name = Safety.Read(frame, "GetName")
    if type(name) ~= "string" or name == "" or IsBag(name) then return nil end
    if name == "LFGParentFrame" and not NS.Client.isForever then return nil end
    local entry = NS.BlizzardCatalog.FindByFrame(name)
    local standalone = specialPanels[name]
    local panel = UIPanelWindows[name]
    if not (entry or standalone) or not (panel or standalone) then return nil end
    if panel and panel.area == "full" then return nil end
    if entry and excludedCategories[entry.category] then return nil end
    local parent = Safety.Read(frame, "GetParent")
    if parent ~= UIParent and not (standalone and parent == nil) then return nil end
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    -- The Game Menu is 1 high until its first opening lays out its buttons
    -- (MainMenuFrameTemplate): listed panels need the width only.
    if type(width) ~= "number" or type(height) ~= "number"
        or width < 240 or height < 170 and not standalone then return nil end
    return name, entry, panel
end

local function ValidClose(candidate)
    if candidate and Safety.Read(candidate, "GetObjectType") == "Button"
        and not Safety.GetProtection(candidate) then
        return candidate
    end
end

local function FindClose(frame, name)
    return ValidClose(Safety.Field(frame, "ClosePanelButton"))
        or ValidClose(Safety.Field(Safety.Field(frame, "Border"), "CloseButton"))
        or ValidClose(_G[name .. "CloseButton"])
        or ValidClose(Safety.Field(frame, "CloseButton"))
end

local function ClampScale(value)
    local limits = Limits()
    return math.max(limits.minScale, math.min(limits.maxScale, value))
end

local function CanChangeGeometry(state)
    return CanChangeFrameGeometry(state.frame)
end

-- The controls are on for this panel: Window controls are enabled, an
-- owner still skins it and it can be controlled.
local function Controlled(state)
    return Enabled() and next(state.owners) ~= nil and CanChangeGeometry(state)
end

local function ApplyStoredScale(state)
    if not CanChangeGeometry(state) then return end
    local limits = Limits()
    local scales = NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales
    local stored = scales and scales[state.name]
    local scale
    if type(stored) == "number" and stored >= limits.minScale and stored <= limits.maxScale then
        scale = stored
        state.customScale = true
    elseif state.customScale then
        scale = state.originalScale
        state.customScale = false
    end
    if type(scale) == "number" and state.frame:GetScale() ~= scale then
        state.frame:SetScale(scale)
    end
end

-- The panel's own anchors, when they are all readable. Anchors of a panel
-- inside secret-anchored layout come back as secrets and are not kept.
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

local function RestoreNativePosition(state)
    if not CanChangeGeometry(state) then return end
    state.customPosition = false
    state.defaultPosition = false
    positionedStates[state.frame] = nil
    -- The panel manager never anchors the Game Menu (centerFrameSkipAnchoring).
    if state.panel and not state.panel.centerFrameSkipAnchoring then
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

local InstallPanelPositionHook

local function ApplyStoredPosition(state)
    if not CanChangeGeometry(state) or not Enabled() or state.moving then return end
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
    -- Keep the external map grip beside its scrollbar when a saved panel is moved right.
    if state.name == "WorldMapFrame" then width = width + 21 * ratio end
    local x = math.max(0, math.min(uiWidth - math.min(uiWidth, width), point.x))
    local y = math.max(-math.max(0, uiHeight - height), math.min(0, point.y))
    state.frame:ClearAllPoints()
    state.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / ratio, y / ratio)
    state.customPosition = true
    state.defaultPosition = defaultPosition == true
    positionedStates[state.frame] = state
    -- Whichever path placed it (attach, profile switch, reopen, save), the
    -- panel layout hook keeps it there.
    InstallPanelPositionHook()
end

local positionHooked = false
local suspendPositionHook = false

-- Blizzard's panel layout re-anchors open panels; ours move back after it.
local function OnPanelPositionsUpdated()
    if suspendPositionHook or IsCombat() or not Enabled() then return end
    for frame, state in pairs(positionedStates) do
        if frame:IsShown() then
            ApplyStoredPosition(state)
        end
    end
end

InstallPanelPositionHook = function()
    if positionHooked then return end
    positionHooked = true
    hooksecurefunc("UpdateUIPanelPositions", OnPanelPositionsUpdated)
end

-- The window's own (localized) title, else a name derived from its frame.
local function WindowTitle(state)
    local frame = state.frame
    local title = Safety.Call(frame, "GetTitleText")
        or Safety.Field(Safety.Field(frame, "TitleContainer"), "TitleText")
    local text = Safety.Read(title, "GetText")
    -- Forever's outer container has no title region; all three child panes
    -- use this same localized native caption.
    if state.name == "LFGParentFrame" then text = Safety.Field(_G, "LFG_TITLE") end
    if type(text) == "string" and text ~= "" then return text end
    return (state.name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2"))
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
    CommitWithHistory(NS.L["Move %s"]:format(WindowTitle(state)), "positions." .. state.name, function()
        positions[state.name] = { x = x, y = y }
        return true
    end)
    state.customPosition = true
    NS.CombatGate.RunOrDefer("windowControls:move:" .. state.name, function() ApplyStoredPosition(state) end)
    return true
end

local function PaintControl(button, glyph)
    button:SetSize(22, 22)
    button:SetFrameLevel(button:GetParent():GetFrameLevel() + CONTROL_LEVEL_OFFSET)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(glyph)
    NS.WindowControlChrome.PaintControl(button, "buttonFill", label)
end

local function Restore(state)
    if IsCombat() or not state or not state.minimized then return false end
    if state.panel and not NS.Client.IsGamepadUI() then
        ShowUIPanel(state.frame)
    else
        state.frame:Show()
    end
    -- OnPanelShow drops the tab. Blizzard can refuse the panel (a center
    -- panel such as the Game Menu is open): the tab stays for another try.
    return state.frame:IsShown() == true
end

local function Minimize(state)
    if IsCombat() or NS.Client.IsGamepadUI() or not state or state.minimized then return end
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
    state.restoreLabel:SetText(WindowTitle(state) .. "  +")
    state.minimized = true
    if state.panel then
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

-- Restore tab handlers.

local function OnRestoreDragStart(bar)
    if not IsCombat() then bar:StartMoving() end
end

local function OnRestoreDragStop(bar)
    bar:StopMovingOrSizing()
end

local function OnRestoreClick(bar, mouseButton)
    local state = controlStates[bar]
    if not state then return end
    if mouseButton == "RightButton" then
        state.minimized = false
        bar:Hide()
    else
        Restore(state)
    end
end

local function OnMinimizeClick(button)
    Minimize(controlStates[button])
end

local function CreateRestore(state)
    local bar = CreateFrame("Button", nil, UIParent)
    controlStates[bar] = state
    bar:SetSize(RESTORE_WIDTH, 26)
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:SetScript("OnDragStart", OnRestoreDragStart)
    bar:SetScript("OnDragStop", OnRestoreDragStop)
    NS.WindowControlChrome.PaintControl(bar, "popup")
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    state.restoreLabel = label
    bar:SetScript("OnClick", OnRestoreClick)
    bar:Hide()
    return bar
end

-- Scale grip. The drag follows the cursor from a transient OnUpdate that
-- clears itself as soon as the mouse button is up, combat starts or the
-- panel hides.

local function EndDrag(state)
    local grip = state.grip
    grip:SetScript("OnUpdate", nil)
    if not state.drag then return end
    state.drag = nil
    if grip:IsMouseOver() then grip:SetButtonState("NORMAL") end
    local scale = state.frame:GetScale()
    if NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales then
        local value = math.floor(scale * 100 + 0.5) / 100
        CommitWithHistory(NS.L["Scale %s"]:format(WindowTitle(state)), "scales." .. state.name, function()
            NS.DB.windowControls.scales[state.name] = value
            return true
        end)
        state.customScale = true
    end
end

local function UpdateDrag(state)
    local drag = state.drag
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then
        EndDrag(state)
        return
    end
    if not CanChangeGeometry(state) or not state.frame:IsShown() then
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
    if not CanChangeGeometry(state) or not Enabled() then return end
    local x, y = GetCursorPosition()
    local frame = state.frame
    local width, height = frame:GetWidth(), frame:GetHeight()
    local parentScale = UIParent:GetEffectiveScale()
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

local function ControlParent(state)
    -- WorldMap's root can be LOW while its border and quest log are HIGH.
    -- Inherit the visible border's strata without changing native frames.
    if state.name == "WorldMapFrame" then
        local border = Safety.Field(state.frame, "BorderFrame")
        if Safety.CanDecorate(border, true) and Safety.Read(border, "GetParent") == state.frame then return border end
    end
    return state.frame
end

local function ControlBaseLevel(state)
    local parent = ControlParent(state)
    local level = parent:GetFrameLevel()
    -- Map and Forever spellbook/professions chrome sits above its root.
    -- Keep our small controls above the portrait border too; only our own
    -- frames change level.
    if state.name == "WorldMapFrame"
        or (NS.Client.isForever and (state.name == "PlayerSpellsFrame" or state.name == "ProfessionsFrame")) then
        local borderLevel = Safety.Read(Safety.Field(parent, "NineSlice"), "GetFrameLevel")
        if type(borderLevel) == "number" then level = math.max(level, borderLevel) end
    end
    return level
end

local function CreateGrip(state)
    local grip = Safety.CreateChildFrame("Button", ControlParent(state))
    controlStates[grip] = state
    grip:SetSize(20, 20)
    grip:SetFrameLevel(ControlBaseLevel(state) + GRIP_LEVEL_OFFSET)
    if state.name == "WorldMapFrame" then
        -- Clear quest scrolling and keep the grip above a maximized map's bottom edge.
        grip:SetPoint("BOTTOMLEFT", state.frame, "BOTTOMRIGHT", 1, 3)
        grip:SetClampedToScreen(true)
    elseif NS.Client.isForever and state.name == "ProfessionsFrame" then
        -- Leave the Create button, right tab column and lower footer clear.
        grip:SetPoint("TOPLEFT", state.frame, "BOTTOMRIGHT", 1, -1)
    else
        grip:SetPoint("BOTTOMRIGHT", state.frame, "BOTTOMRIGHT", -3, 3)
    end
    if state.name == "WorldMapFrame" then
        NS.WindowControlChrome.StyleGrip(grip)
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

-- Title-strip move.

local function EndMove(state)
    if not state.moving then return end
    local frame = state.frame
    -- Only a protected panel waits for the end of combat to stop; any other
    -- stops where it was dropped, and in combat only its anchor waits.
    if IsCombat() and Safety.GetProtection(frame) then
        NS.CombatGate.RunOrDefer("windowControls:move:" .. state.name, function() EndMove(state) end)
        return
    end
    state.moving = false
    if Safety.IsForbidden(frame) then return end
    frame:StopMovingOrSizing()
    if state.nativeMovable == false then frame:SetMovable(false) end
    state.nativeMovable = nil
    SavePosition(state)
end

local function BeginMove(state)
    if not CanChangeGeometry(state) or not Enabled() then return end
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
end

local function OnTitleDragStart(strip)
    BeginMove(controlStates[strip])
end

local function OnTitleRelease(strip)
    EndMove(controlStates[strip])
end

local function CreateTitleDrag(state)
    -- Standard Blizzard panel headers leave the title area clear.  Keep the
    -- drag target inside that strip, away from portraits and window buttons.
    -- The Forever navigation sits below the title, so this strip stays free.
    local strip = Safety.CreateChildFrame("Frame", ControlParent(state))
    controlStates[strip] = state
    strip:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 50, -1)
    strip:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -110, -1)
    strip:SetHeight(24)
    strip:SetFrameLevel(ControlBaseLevel(state) + CONTROL_LEVEL_OFFSET)
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", OnTitleDragStart)
    strip:SetScript("OnDragStop", OnTitleRelease)
    strip:SetScript("OnMouseUp", OnTitleRelease)
    strip:SetScript("OnHide", OnTitleRelease)
    return strip
end

local function ShowControls(state)
    local level = ControlBaseLevel(state)
    state.titleDrag:SetFrameLevel(level + CONTROL_LEVEL_OFFSET)
    state.grip:SetFrameLevel(level + GRIP_LEVEL_OFFSET)
    state.titleDrag:Show()
    state.grip:Show()
    if state.minimize then
        if NS.Client.IsGamepadUI() then state.minimize:Hide() else state.minimize:Show() end
    end
end

-- Controls off: a panel the grip scaled gets Blizzard's scale back (the
-- stored scale stays and returns with the controls).
local function RestoreNativeScale(state)
    if not state.customScale or not CanChangeGeometry(state) then return end
    state.customScale = false
    if type(state.originalScale) == "number" then state.frame:SetScale(state.originalScale) end
end

local function HideControls(state)
    if state.moving then EndMove(state) end
    if state.drag then EndDrag(state) end
    if state.minimized then Restore(state) end
    state.titleDrag:Hide()
    state.grip:Hide()
    if state.minimize then state.minimize:Hide() end
    RestoreNativeScale(state)
    if state.defaultPosition and not IsCombat() then RestoreNativePosition(state) end
end

local function CanMinimize(name)
    return minimizablePanels[name] == true and not nativeMinimize[name]
end

local function PlaceMinimize(button, frame, close)
    local anchor = close and Safety.Read(close, "GetPoint", 1)
    if type(anchor) == "string" and anchor:find("TOP", 1, true) then
        button:SetPoint("RIGHT", close, "LEFT", -3, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -4)
    end
end

local function CreateMinimize(state, close)
    local button = Safety.CreateChildFrame("Button", state.frame)
    controlStates[button] = state
    PaintControl(button, "-")
    PlaceMinimize(button, state.frame, close)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", OnMinimizeClick)
    return button
end

-- Hooked once per panel. The invisible title strip takes the clicks of the
-- title area, so it only comes back while the controls are on, an owner
-- still skins the panel and the panel can be controlled.
local function OnPanelShow(frame)
    local state = WindowControls.states[frame]
    if not state then return end
    if state.restore then
        state.minimized = false
        state.restore:Hide()
    end
    if IsCombat() then return end
    if Controlled(state) then
        ShowControls(state)
        -- Blizzard fits checkFit panels (PlayerSpellsFrame, ProfessionsFrame,
        -- Settings) to the screen with SetScale(1) as they open: the stored
        -- scale comes back first, then the position, which depends on it.
        ApplyStoredScale(state)
    else
        state.titleDrag:Hide()
    end
    ApplyStoredPosition(state)
end

local function OnPanelHide(frame)
    local state = WindowControls.states[frame]
    if not state then return end
    if state.moving then EndMove(state) end
    if state.restore and not state.minimized then state.restore:Hide() end
end

function WindowControls.Attach(frame, owner)
    if not Enabled() or IsCombat() then return false end
    local name, _, panel = Eligible(frame)
    local state = WindowControls.states[frame]
    if not name then
        -- A panel that became protected keeps no grip or drag strip.
        if state and Safety.GetProtection(frame) then HideControls(state) end
        return false
    end
    if state then
        state.owners[owner or "blizzardWindows"] = true
        ApplyStoredScale(state)
        ApplyStoredPosition(state)
        ShowControls(state)
        return true
    end
    local close = FindClose(frame, name)
    state = {
        frame = frame,
        name = name,
        panel = panel,
        originalScale = frame:GetScale(),
        nativePoints = CaptureNativePoints(frame),
        owners = { [owner or "blizzardWindows"] = true },
    }
    WindowControls.states[frame] = state
    state.grip = CreateGrip(state)
    ApplyStoredScale(state)
    if close and CanMinimize(name) and not Safety.Field(frame, "MinimizeButton")
        and not _G[name .. "MinimizeButton"] then
        state.restore = CreateRestore(state)
        state.minimize = CreateMinimize(state, close)
    end
    state.titleDrag = CreateTitleDrag(state)
    state.titleDrag:Show()
    ApplyStoredPosition(state)
    frame:HookScript("OnShow", OnPanelShow)
    frame:HookScript("OnHide", OnPanelHide)
    return true
end

function WindowControls.DisableOwner(owner)
    for _, state in pairs(WindowControls.states) do
        state.owners[owner] = nil
        if not next(state.owners) then
            HideControls(state)
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
    if IsCombat() then return false, "combat" end
    local enabled = Enabled()
    for _, state in pairs(WindowControls.states) do
        if enabled and Controlled(state) then
            if not state.drag then ApplyStoredScale(state) end
            if not state.moving then ApplyStoredPosition(state) end
            ShowControls(state)
        else
            HideControls(state)
        end
    end
    return true
end

local function RefreshQueued() WindowControls.Refresh() end

local function RecolorMinimize()
    local Chrome = NS.WindowControlChrome
    for _, state in pairs(WindowControls.states) do
        if state.name == "WorldMapFrame" then Chrome.RecolorGrip(state.grip) end
        if state.minimize then Chrome.RecolorControl(state.minimize) end
        if state.restore then Chrome.RecolorControl(state.restore) end
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
        if type(state.originalScale) == "number" and CanChangeGeometry(state) then
            state.frame:SetScale(state.originalScale)
        end
        state.customScale = false
    end
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
