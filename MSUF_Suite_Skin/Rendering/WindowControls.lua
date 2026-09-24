local _, NS = ...

-- Window geometry is deliberately separate from cosmetic skinning.  Only
-- reviewed, top-level Blizzard panels are candidates; native controls win.
-- No global frame scans, permanent OnUpdate, or protected frame mutations.
local WindowControls = { states = setmetatable({}, { __mode = "k" }) }
NS.WindowControls = WindowControls
local positionedStates = setmetatable({}, { __mode = "k" })
local FOREVER_CHARACTER_DOCK = { x = 0, y = 0 }

local MIN_SCALE, MAX_SCALE = 0.70, 1.50
local RESTORE_WIDTH = 154
local specialPanels = {
    SettingsPanel = true, AddonList = true, PlayerSpellsFrame = true,
    GameMenuFrame = true, ProfessionsFrame = true,
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
}

local function IndexMember(object, key)
    return object[key]
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(IndexMember, object, key)
    if not ok then return nil end
    if type(issecretvalue) == "function" and issecretvalue(value)
        and (type(canaccessvalue) ~= "function" or not canaccessvalue(value)) then
        return nil
    end
    return value
end

local function SafeCall(object, method, ...)
    if not object then return nil end
    local fn = SafeField(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and issecretvalue(value)
        and (type(canaccessvalue) ~= "function" or not canaccessvalue(value)) then
        return nil
    end
    return value
end

local function IsCombat()
    return NS.IsCombatLocked and NS.IsCombatLocked()
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

local function Eligible(frame)
    if not frame or not NS.Safety or NS.Safety.IsForbidden(frame) then return nil end
    -- An ancestor with secure descendants is also excluded for geometry.
    local protected = NS.Safety.GetProtection(frame)
    if protected or IsCombat() then return nil end
    local name = SafeCall(frame, "GetName")
    if type(name) ~= "string" or name == "" or IsBag(name) then return nil end
    local entry = NS.BlizzardCatalog and NS.BlizzardCatalog.FindByFrame(name)
    local standalone = specialPanels[name]
    local panel = UIPanelWindows and UIPanelWindows[name]
    if not (entry or standalone) or not (panel or standalone) then return nil end
    if panel and panel.area == "full" then return nil end
    if entry and (entry.category == "hud" or entry.category == "inventory"
        or entry.category == "tutorial" or entry.category == "utility") then return nil end
    local parent = SafeCall(frame, "GetParent")
    if parent ~= UIParent and not (standalone and parent == nil) then return nil end
    local width, height = SafeCall(frame, "GetWidth"), SafeCall(frame, "GetHeight")
    if type(width) ~= "number" or type(height) ~= "number"
        or width < 240 or height < 170 then return nil end
    return name, entry, panel
end

local function ValidClose(candidate)
    if candidate and SafeCall(candidate, "GetObjectType") == "Button"
        and not NS.Safety.GetProtection(candidate)
        and not NS.Safety.IsForbidden(candidate) then
        return candidate
    end
end

local function FindClose(frame, name)
    return ValidClose(SafeField(frame, "ClosePanelButton"))
        or ValidClose(SafeField(SafeField(frame, "Border"), "CloseButton"))
        or ValidClose(_G[name .. "CloseButton"])
        or ValidClose(SafeField(frame, "CloseButton"))
end

local function ClampScale(value)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, value))
end

local function ApplyStoredScale(state)
    local scales = NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales
    local stored = scales and scales[state.name]
    local scale
    if type(stored) == "number" and stored >= MIN_SCALE and stored <= MAX_SCALE then
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

local function CaptureNativePoints(frame)
    local count = SafeCall(frame, "GetNumPoints")
    if type(count) ~= "number" or count < 1 or count > 8 then return nil end
    local points = {}
    for index = 1, count do
        local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, index)
        if not ok or type(point) ~= "string" then return nil end
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

local function RestoreNativePosition(state)
    state.customPosition = false
    state.defaultPosition = false
    positionedStates[state.frame] = nil
    if state.panel and type(UpdateUIPanelPositions) == "function" then
        UpdateUIPanelPositions(state.frame)
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
    if IsCombat() or not Enabled() or state.moving then return end
    local positions = NS.DB and NS.DB.windowControls and NS.DB.windowControls.positions
    local point = positions and positions[state.name]
    local defaultPosition = not point and state.name == "CharacterFrame"
        and NS.Client and NS.Client.isForever and NS.DB.theme.look == "foreverGlass"
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
    local x = math.max(0, math.min(uiWidth - math.min(uiWidth, width), point.x))
    local y = math.max(-math.max(0, uiHeight - height), math.min(0, point.y))
    state.frame:ClearAllPoints()
    state.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / ratio, y / ratio)
    state.customPosition = true
    state.defaultPosition = defaultPosition == true
    positionedStates[state.frame] = state
end

local positionHooked = false
local suspendPositionHook = false
local function InstallPanelPositionHook()
    if positionHooked or type(hooksecurefunc) ~= "function"
        or type(UpdateUIPanelPositions) ~= "function" then return end
    positionHooked = true
    hooksecurefunc("UpdateUIPanelPositions", function()
        if suspendPositionHook or IsCombat() or not Enabled() then return end
        for frame, state in pairs(positionedStates) do
            if frame:IsShown() then
                ApplyStoredPosition(state)
            end
        end
    end)
end

local function SavePosition(state)
    local frame = state.frame
    local left, top = SafeCall(frame, "GetLeft"), SafeCall(frame, "GetTop")
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then return false end
    local ratio = frame:GetEffectiveScale() / uiScale
    local uiHeight = UIParent:GetHeight()
    if type(left) ~= "number" or type(top) ~= "number"
        or type(uiHeight) ~= "number" or ratio <= 0 then return false end
    local positions = NS.DB.windowControls.positions
    local x = math.floor(left * ratio + 0.5)
    local y = math.floor((top * ratio - uiHeight) + 0.5)
    CommitWithHistory("Move " .. state.name, "positions." .. state.name, function()
        positions[state.name] = { x = x, y = y }
        return true
    end)
    state.customPosition = true
    InstallPanelPositionHook()
    ApplyStoredPosition(state)
    return true
end

local function PaintControl(button, glyph)
    button:SetSize(22, 22)
    button:SetFrameLevel(button:GetParent():GetFrameLevel() + 15)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(NS.Theme.GetColor("buttonFill"))
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(glyph)
    label:SetTextColor(NS.Theme.GetColor("text"))
    button._msufControlBackground = bg
    button._msufControlLabel = label
end

local function Restore(state)
    if IsCombat() or not state or not state.minimized then return false end
    state.minimized = false
    state.restore:Hide()
    if state.panel and type(ShowUIPanel) == "function" then
        ShowUIPanel(state.frame)
    else
        state.frame:Show()
    end
    return true
end

local function CreateRestore(state)
    local bar = CreateFrame("Button", nil, UIParent)
    bar:SetSize(RESTORE_WIDTH, 26)
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:SetScript("OnDragStart", function(self)
        if not IsCombat() then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(NS.Theme.GetColor("popup"))
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetText((state.name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2")) .. "  +")
    bar:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            state.minimized = false
            bar:Hide()
        else
            Restore(state)
        end
    end)
    bar:Hide()
    return bar
end

local function Minimize(state)
    if IsCombat() or not state or state.minimized then return end
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
    state.minimized = true
    if state.panel and type(HideUIPanel) == "function" then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
    if not frame:IsShown() then state.restore:Show()
    else state.minimized = false end
end

local function EndDrag(state)
    local grip = state.grip
    grip:SetScript("OnUpdate", nil)
    if not state.drag then return end
    state.drag = nil
    if grip:IsMouseOver() then grip:SetButtonState("NORMAL") end
    local frame = state.frame
    local scale = frame:GetScale()
    if NS.DB and NS.DB.windowControls and NS.DB.windowControls.scales then
        local value = math.floor(scale * 100 + 0.5) / 100
        CommitWithHistory("Scale " .. state.name, "scales." .. state.name, function()
            NS.DB.windowControls.scales[state.name] = value
            return true
        end)
        state.customScale = true
    end
end

local function UpdateDrag(state)
    local drag = state.drag
    if not drag then return end
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
        EndDrag(state)
        return
    end
    if IsCombat() or not state.frame:IsShown() then EndDrag(state); return end
    local x, y = GetCursorPosition()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local delta = ((x - drag.x) + (drag.y - y)) * 0.5
    local scale = ClampScale(drag.scale + delta / drag.pixels)
    scale = math.floor(scale * 100 + 0.5) / 100
    if scale ~= state.frame:GetScale() then state.frame:SetScale(scale) end
end

local function BeginDrag(state)
    if IsCombat() or not Enabled() then return end
    local x, y = GetCursorPosition()
    local frame = state.frame
    local width, height = frame:GetWidth(), frame:GetHeight()
    local parentScale = UIParent:GetEffectiveScale()
    if type(x) ~= "number" or type(y) ~= "number"
        or not width or not height or not parentScale or parentScale <= 0 then return end
    state.drag = {
        x = x, y = y, scale = frame:GetScale(),
        pixels = math.max(width, height) * parentScale,
    }
    state.grip:SetScript("OnUpdate", function() UpdateDrag(state) end)
end

local function CreateGrip(state)
    local grip = CreateFrame("Button", nil, state.frame)
    grip:SetSize(20, 20)
    grip:SetFrameLevel(state.frame:GetFrameLevel() + 20)
    grip:SetPoint("BOTTOMRIGHT", state.frame, "BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("LeftButtonUp")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then BeginDrag(state) end
    end)
    grip:SetScript("OnMouseUp", function() EndDrag(state) end)
    grip:SetScript("OnHide", function() EndDrag(state) end)
    grip:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(grip, "ANCHOR_RIGHT")
            GameTooltip:SetText("Drag to scale this window")
            GameTooltip:Show()
        end
    end)
    grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return grip
end

local function EndMove(state)
    if not state.moving then return end
    state.moving = false
    pcall(state.frame.StopMovingOrSizing, state.frame)
    if state.nativeMovable == false then
        pcall(state.frame.SetMovable, state.frame, false)
    end
    state.nativeMovable = nil
    SavePosition(state)
end

local function BeginMove(state)
    if IsCombat() or not Enabled() then return end
    local frame = state.frame
    state.nativeMovable = SafeCall(frame, "IsMovable")
    if state.nativeMovable == false then
        local ok = pcall(frame.SetMovable, frame, true)
        if not ok then return end
    end
    local ok = pcall(frame.StartMoving, frame)
    if not ok then
        if state.nativeMovable == false then pcall(frame.SetMovable, frame, false) end
        state.nativeMovable = nil
        return
    end
    state.moving = true
end

local function CreateTitleDrag(state)
    -- Standard Blizzard panel headers leave the title area clear.  Keep the
    -- drag target inside that strip, away from portraits and window buttons.
    local drag = CreateFrame("Frame", nil, state.frame)
    drag:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 50, -1)
    drag:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -110, -1)
    drag:SetHeight(24)
    drag:SetFrameLevel(state.frame:GetFrameLevel() + 15)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() BeginMove(state) end)
    drag:SetScript("OnDragStop", function() EndMove(state) end)
    drag:SetScript("OnMouseUp", function() EndMove(state) end)
    drag:SetScript("OnHide", function() EndMove(state) end)
    return drag
end

local function RefreshTitleDrag(state)
    -- The Forever navigation sits below the title, leaving this drag area free.
    state.titleDrag:Show()
end

local function CanMinimize(name)
    return minimizablePanels[name] == true and not nativeMinimize[name]
end

local function PlaceMinimize(button, frame, close)
    local anchor = close and SafeCall(close, "GetPoint", 1)
    if type(anchor) == "string" and anchor:find("TOP", 1, true) then
        button:SetPoint("RIGHT", close, "LEFT", -3, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -4)
    end
end

function WindowControls.Attach(frame, owner)
    if not Enabled() or IsCombat() then return false end
    local name, _, panel = Eligible(frame)
    if not name then return false end
    local state = WindowControls.states[frame]
    if state then
        state.owners[owner or "blizzardWindows"] = true
        ApplyStoredScale(state)
        ApplyStoredPosition(state)
        state.titleDrag:SetFrameLevel(frame:GetFrameLevel() + 15)
        RefreshTitleDrag(state)
        state.grip:Show()
        if state.minimize then state.minimize:Show() end
        return true
    end
    local close = FindClose(frame, name)
    state = { frame = frame, name = name, panel = panel,
        originalScale = frame:GetScale(),
        nativePoints = CaptureNativePoints(frame),
        owners = { [owner or "blizzardWindows"] = true } }
    WindowControls.states[frame] = state
    state.grip = CreateGrip(state)
    ApplyStoredScale(state)
    if close and CanMinimize(name) and not SafeField(frame, "MinimizeButton")
        and not _G[name .. "MinimizeButton"] then
        local button = CreateFrame("Button", nil, frame)
        PaintControl(button, "-")
        PlaceMinimize(button, frame, close)
        button:RegisterForClicks("LeftButtonUp")
        state.restore = CreateRestore(state)
        state.minimize = button
        button:SetScript("OnClick", function() Minimize(state) end)
    end
    state.titleDrag = CreateTitleDrag(state)
    RefreshTitleDrag(state)
    if NS.DB.windowControls.positions[name] or (name == "CharacterFrame"
        and NS.Client and NS.Client.isForever) then InstallPanelPositionHook() end
    ApplyStoredPosition(state)
    frame:HookScript("OnShow", function()
        if state.restore then
            state.minimized = false
            state.restore:Hide()
        end
        state.titleDrag:SetFrameLevel(frame:GetFrameLevel() + 15)
        RefreshTitleDrag(state)
        ApplyStoredPosition(state)
    end)
    frame:HookScript("OnHide", function()
        if state.moving then EndMove(state) end
        if state.restore and not state.minimized then state.restore:Hide() end
    end)
    return true
end

function WindowControls.DisableOwner(owner)
    for _, state in pairs(WindowControls.states) do
        state.owners[owner] = nil
        if not next(state.owners) then
            if state.moving then EndMove(state) end
            if state.drag then EndDrag(state) end
            if state.minimized then Restore(state) end
            state.titleDrag:Hide()
            state.grip:Hide()
            if state.minimize then state.minimize:Hide() end
            if state.defaultPosition and not IsCombat() then RestoreNativePosition(state) end
        end
    end
end

function WindowControls.SetEnabled(enabled)
    if IsCombat() then return false, "combat" end
    NS.DB.windowControls.enabled = enabled == true
    if enabled then
        if NS.Adapters then NS.Adapters.ApplyAll() end
    end
    WindowControls.Refresh()
    return true
end

function WindowControls.Refresh()
    local enabled = Enabled()
    for _, state in pairs(WindowControls.states) do
        if enabled and next(state.owners) then
            if not state.drag then ApplyStoredScale(state) end
            if not state.moving then ApplyStoredPosition(state) end
            state.titleDrag:SetFrameLevel(state.frame:GetFrameLevel() + 15)
            RefreshTitleDrag(state)
            state.grip:Show()
            if state.minimize then state.minimize:Show() end
        else
            if state.moving then EndMove(state) end
            if state.drag then EndDrag(state) end
            if state.minimized then Restore(state) end
            state.titleDrag:Hide()
            state.grip:Hide()
            if state.minimize then state.minimize:Hide() end
            if state.defaultPosition and not IsCombat() then RestoreNativePosition(state) end
        end
    end
end

function WindowControls:OnThemeChanged(domain, key)
    if domain == "profile" then self.Refresh() end
    if domain == "theme" and key == "look" then self.Refresh() end
    if domain ~= "theme" and domain ~= "color" and domain ~= "appearance" then return end
    for _, state in pairs(self.states) do
        local r, g, b, a = NS.Theme.GetColor("buttonFill")
        if state.minimize then
            state.minimize._msufControlBackground:SetColorTexture(r, g, b, a)
            state.minimize._msufControlLabel:SetTextColor(NS.Theme.GetColor("text"))
        end
    end
end

NS.Registry.AddListener(WindowControls, WindowControls.OnThemeChanged)

function WindowControls.ResetScales()
    if IsCombat() then return false, "combat" end
    NS.DB.windowControls.scales = {}
    for _, state in pairs(WindowControls.states) do
        if type(state.originalScale) == "number" then
            state.frame:SetScale(state.originalScale)
        end
        state.customScale = false
    end
    return true
end

function WindowControls.ResetPositions()
    if IsCombat() then return false, "combat" end
    for _, state in pairs(WindowControls.states) do
        if state.moving then EndMove(state) end
    end
    NS.DB.windowControls.positions = {}
    suspendPositionHook = true
    local success = true
    for _, state in pairs(WindowControls.states) do
        if state.customPosition then
            local ok, reason = pcall(RestoreNativePosition, state)
            if not ok then
                success = false
                if NS.ReportError then NS.ReportError("window position reset", reason) end
            end
        end
    end
    suspendPositionHook = false
    -- Reset returns to the selected look's default placement on Forever.
    for _, state in pairs(WindowControls.states) do
        if next(state.owners) then ApplyStoredPosition(state) end
    end
    return success
end

function WindowControls.ResetLayout()
    if IsCombat() then return false, "combat" end
    local scaled = WindowControls.ResetScales()
    local moved = WindowControls.ResetPositions()
    return scaled and moved
end

return WindowControls
