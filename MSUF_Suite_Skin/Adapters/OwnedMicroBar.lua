local _, NS = ...

-- MSKIN owns the bar shell, position and grid policy. Blizzard keeps the
-- MicroMenu frame, every native MicroButton, scripts, alerts and click state.
-- The complete MicroMenu is moved as one unit only outside combat; individual
-- buttons are never reparented or replaced.
local OwnedMicroBar = {
    active = false,
    suspended = false,
}
NS.OwnedMicroBar = OwnedMicroBar

local BAR_NAME = "MapkoSkinMicroBar"
local MOVER_NAME = "MapkoSkinMicroBarMover"
local REAPPLY_KEY = "micro-menu:owned-reapply"
local FOREVER_PORTRAIT_SPACE = 48
local MAX_BUTTONS_PER_LINE = NS.Client and NS.Client.isForever and 14 or 13
local PORTRAIT_LEFT_INSET = 9
local RULE_LEFT_INSET = 62
local FOREVER_RING = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\ForeverPortraitRing.tga"
local MIDNIGHT_RING = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\MidnightPortraitRing.tga"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local bar
local mover
local portrait, portraitRing, topRule, bottomRule
local portraitEnabled = false
local activeRoot
local nativeState
local suppressResetHook = false
local resetHookRoot
local overrideHookRoot
local setFullScreenHooked = false
local clearFullScreenHooked = false
local desired = false
local ScheduleReapply
local editRegistered = false
local editProfile, editEpoch = nil, 0
local EDIT_OWNER, EDIT_ID = "MSUFSuite.Skin", "microBar"
local VISIBILITY_DRIVERS = {
    combat = "[combat] show; hide",
    outOfCombat = "[combat] hide; show",
}
local HOVER_GRACE = 0.12
local visibilityDriver, editSession, hoverTimer
local hoverButtons = setmetatable({}, { __mode = "k" })
local hoverHooked = setmetatable({}, { __mode = "k" })

local eventFrame = CreateFrame("Frame")

local function Accessible(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value
end

local function ReadMember(target, key)
    if not target then return nil end
    local ok, value = pcall(function() return target[key] end)
    if not ok then return nil end
    return Accessible(value)
end

local function CallMethod(target, methodName, ...)
    local method = ReadMember(target, methodName)
    if type(method) ~= "function" then return false end
    return pcall(method, target, ...)
end

local function ReadNumber(target, methodName, fallback)
    local ok, value = CallMethod(target, methodName)
    value = ok and Accessible(value) or nil
    return type(value) == "number" and value or fallback
end

local function IsCombatLocked()
    return type(NS.IsCombatLocked) == "function" and NS.IsCombatLocked() == true
end

local function Settings()
    return NS.DB and NS.DB.icons and NS.DB.icons.microMenu
end

local function ProfileEpoch()
    if editProfile ~= NS.DB then
        editProfile, editEpoch = NS.DB, editEpoch + 1
    end
    return editEpoch
end

local function CanOwn(target)
    return NS.Safety and NS.Safety.CanControl(target, true) == true
end

local function SetParentMaintainRenderLayering(target, parent)
    local frameUtil = ReadMember(_G, "FrameUtil")
    local setParent = ReadMember(frameUtil, "SetParentMaintainRenderLayering")
    if type(setParent) == "function" then
        local ok = pcall(setParent, target, parent)
        if ok then return true end
    end
    return CallMethod(target, "SetParent", parent)
end

local function IsOwnedMode(settings)
    return settings and settings.layoutMode == "owned"
end

local function CancelHoverTimer()
    if hoverTimer then
        hoverTimer:Cancel()
        hoverTimer = nil
    end
end

local function MouseInside()
    local ok, over = CallMethod(bar, "IsMouseOver")
    if ok and Accessible(over) == true then return true end
    for button in pairs(hoverButtons) do
        ok, over = CallMethod(button, "IsMouseOver")
        if ok and Accessible(over) == true then return true end
    end
    return false
end

local function HoverEnter()
    CancelHoverTimer()
    local settings = Settings()
    if OwnedMicroBar.active and not OwnedMicroBar.suspended and not editSession
        and settings and settings.visibility == "mouseover" and bar then
        CallMethod(bar, "SetAlpha", 1)
    end
end

local function HoverLeave()
    local settings = Settings()
    if not OwnedMicroBar.active or OwnedMicroBar.suspended or editSession
        or not settings or settings.visibility ~= "mouseover" or not bar then return end
    CancelHoverTimer()
    local timer = ReadMember(_G, "C_Timer")
    if timer and type(ReadMember(timer, "NewTimer")) == "function" then
        hoverTimer = timer.NewTimer(HOVER_GRACE, function()
            hoverTimer = nil
            if OwnedMicroBar.active and not OwnedMicroBar.suspended and not editSession
                and Settings() and Settings().visibility == "mouseover" and not MouseInside() then
                CallMethod(bar, "SetAlpha", 0)
            end
        end)
    elseif not MouseInside() then
        CallMethod(bar, "SetAlpha", 0)
    end
end

local function ClearVisibilityDriver()
    if visibilityDriver then
        if type(_G.UnregisterStateDriver) == "function" then
            _G.UnregisterStateDriver(bar, "visibility")
        end
        visibilityDriver = nil
    end
end

local function ApplyVisibility(settings)
    if not bar or IsCombatLocked() then return false end
    CancelHoverTimer()
    local mode = editSession and "always" or (settings and settings.visibility) or "always"
    local driver = VISIBILITY_DRIVERS[mode]
    if driver and type(_G.RegisterStateDriver) ~= "function" then mode, driver = "always", nil end
    if visibilityDriver ~= driver then
        ClearVisibilityDriver()
        if driver then
            _G.RegisterStateDriver(bar, "visibility", driver)
            visibilityDriver = driver
        end
    end
    CallMethod(bar, "EnableMouse", mode == "mouseover")
    CallMethod(bar, "SetAlpha", mode == "mouseover" and (MouseInside() and 1 or 0) or 1)
    if mode == "never" then
        CallMethod(bar, "Hide")
    elseif not driver then
        CallMethod(bar, "Show")
    end
    return true
end

function OwnedMicroBar.TrackHoverButtons(buttons)
    hoverButtons = setmetatable({}, { __mode = "k" })
    for button in pairs(buttons or {}) do
        hoverButtons[button] = true
        if not hoverHooked[button] and type(ReadMember(button, "HookScript")) == "function" then
            button:HookScript("OnEnter", HoverEnter)
            button:HookScript("OnLeave", HoverLeave)
            hoverHooked[button] = true
        end
    end
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function CapturePoints(frame)
    local points = {}
    local count = math.floor(ReadNumber(frame, "GetNumPoints", 0) or 0)
    for index = 1, count do
        local ok, point, relativeTo, relativePoint, x, y =
            CallMethod(frame, "GetPoint", index)
        if ok and type(point) == "string" then
            x, y = Accessible(x), Accessible(y)
            points[#points + 1] = {
                point, relativeTo, relativePoint,
                type(x) == "number" and x or 0,
                type(y) == "number" and y or 0,
            }
        end
    end
    return points
end

local function CaptureNative(root)
    if nativeState and nativeState.root == root then return end
    local ok, parent = CallMethod(root, "GetParent")
    nativeState = {
        root = root,
        parent = ok and parent or nil,
        points = CapturePoints(root),
        childXPadding = ReadMember(root, "childXPadding"),
        childYPadding = ReadMember(root, "childYPadding"),
        isHorizontal = ReadMember(root, "isHorizontal"),
        stride = ReadMember(root, "stride"),
        layoutFramesGoingRight = ReadMember(root, "layoutFramesGoingRight"),
        layoutFramesGoingUp = ReadMember(root, "layoutFramesGoingUp"),
        isStacked = ReadMember(root, "isStacked"),
        overrideScale = ReadMember(root, "overrideScale"),
    }
end

local function RestoreGridFields(root)
    local state = nativeState
    if not state or state.root ~= root then return end
    pcall(function()
        root.childXPadding = state.childXPadding
        root.childYPadding = state.childYPadding
        root.isHorizontal = state.isHorizontal
        root.stride = state.stride
        root.layoutFramesGoingRight = state.layoutFramesGoingRight
        root.layoutFramesGoingUp = state.layoutFramesGoingUp
        root.isStacked = state.isStacked
    end)
end

local function MarkAndLayout(root)
    local marked = CallMethod(root, "MarkDirty")
    if not marked then pcall(function() root.oldGridSettings = nil end) end
    return CallMethod(root, "Layout")
end

local function RestoreFallback(root, state)
    if state.parent then SetParentMaintainRenderLayering(root, state.parent) end
    CallMethod(root, "ClearAllPoints")
    for index = 1, #(state.points or {}) do
        CallMethod(root, "SetPoint", unpack(state.points[index]))
    end
    if state.overrideScale ~= nil then
        if not CallMethod(root, "SetOverrideScale", state.overrideScale) then
            CallMethod(root, "SetScale", state.overrideScale)
        end
    else
        CallMethod(root, "ClearOverrideScale")
    end
    MarkAndLayout(root)
end

local function RestoreNative(root)
    local state = nativeState
    if not root or not state or state.root ~= root or not CanOwn(root) then
        return false
    end
    local ok, parent = CallMethod(root, "GetParent")
    if not ok or parent ~= bar then
        -- Blizzard currently owns an override (vehicle, pet battle or a full-
        -- screen flow). Its next ResetMicroMenuPosition restores native state.
        return true, "yielded"
    end

    suppressResetHook = true
    RestoreGridFields(root)
    local reset = CallMethod(root, "ResetMicroMenuPosition")
    if not reset then RestoreFallback(root, state) end
    suppressResetHook = false
    return true, reset and "reset" or "restored"
end

local function SavePosition()
    local settings = Settings()
    if not settings or not bar then return false end
    local ok, point, _, relativePoint, x, y = CallMethod(bar, "GetPoint", 1)
    point, relativePoint = Accessible(point), Accessible(relativePoint)
    x, y = Accessible(x), Accessible(y)
    if not ok or type(point) ~= "string" then return false end
    settings.layoutPoint = point
    settings.layoutRelativePoint =
        type(relativePoint) == "string" and relativePoint or point
    settings.layoutX = type(x) == "number" and math.floor(x + 0.5) or 0
    settings.layoutY = type(y) == "number" and math.floor(y + 0.5) or 0
    settings.positionPreset = "custom"
    return true
end

local function ApplyPosition(settings)
    if not bar or not UIParent then return false end
    local point = type(settings.layoutPoint) == "string"
        and settings.layoutPoint or "BOTTOMRIGHT"
    local relativePoint = type(settings.layoutRelativePoint) == "string"
        and settings.layoutRelativePoint or point
    local x = Clamp(settings.layoutX, -4096, 4096)
    local y = Clamp(settings.layoutY, -4096, 4096)
    if not CallMethod(bar, "ClearAllPoints") then return false end
    return CallMethod(bar, "SetPoint", point, UIParent, relativePoint, x, y)
end

local function SetMoverVisible(visible)
    if not mover then return end
    visible = visible == true and not editRegistered and not IsCombatLocked()
    CallMethod(mover, visible and "Show" or "Hide")
end

local function EditAPI()
    local api = ReadMember(_G, "MSUF_EditModeAPI")
    if type(api) == "table" and type(ReadMember(api, "RegisterElement")) == "function" then
        return api
    end
end

local function PlaceEditPosition(state, x, y, commit)
    local settings = Settings()
    if not settings or not bar or IsCombatLocked() or not UIParent then return false end
    if type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or math.abs(x) > 4096 or math.abs(y) > 4096 then
        return false
    end
    if commit then
        local function Round(value)
            return value >= 0 and math.floor(value * 10 + 0.5) / 10
                or math.ceil(value * 10 - 0.5) / 10
        end
        settings.layoutPoint = state.point
        settings.layoutRelativePoint = state.relativePoint
        settings.layoutX = Round(x)
        settings.layoutY = Round(y)
        settings.positionPreset = "custom"
        return ApplyPosition(settings)
    end
    return CallMethod(bar, "ClearAllPoints") and CallMethod(bar, "SetPoint",
        state.point, UIParent, state.relativePoint, x, y)
end

local function EditState()
    local settings = Settings()
    if not settings then return nil end
    return {
        epoch = ProfileEpoch(), point = settings.layoutPoint,
        relativePoint = settings.layoutRelativePoint,
        x = settings.layoutX, y = settings.layoutY,
        positionPreset = settings.positionPreset,
        orientation = settings.orientation,
        buttonsPerLine = settings.buttonsPerLine,
        spacing = settings.spacing,
        scale = settings.scale,
        padding = settings.padding,
    }
end

local function ValidEditState(state)
    return type(state) == "table" and state.epoch == ProfileEpoch()
        and type(state.point) == "string" and type(state.relativePoint) == "string"
        and type(state.x) == "number" and type(state.y) == "number"
        and (state.orientation == "horizontal" or state.orientation == "vertical")
        and type(state.buttonsPerLine) == "number" and state.buttonsPerLine >= 1
        and state.buttonsPerLine <= MAX_BUTTONS_PER_LINE
        and type(state.spacing) == "number" and state.spacing >= -8 and state.spacing <= 16
        and type(state.scale) == "number" and state.scale >= 0.5 and state.scale <= 1.5
        and type(state.padding) == "number" and state.padding >= 0 and state.padding <= 16
end

local function EditOption(key, label, minimum, maximum, step)
    return {
        id = key, label = label, kind = "number", min = minimum, max = maximum, step = step,
        get = function() local settings = Settings(); return settings and settings[key] end,
        set = function(value)
            return NS.MicroMenuSkin.SetOption(key, value)
        end,
    }
end

local editControls = {
    EditOption("buttonsPerLine", "Per line", 1, MAX_BUTTONS_PER_LINE, 1),
    EditOption("spacing", "Spacing", -8, 16, 1),
    {
        id = "size", label = "Size %", kind = "number", min = 50, max = 150, step = 1,
        get = function()
            local settings = Settings()
            return settings and math.floor((settings.scale or 1) * 100 + 0.5)
        end,
        set = function(value) return NS.MicroMenuSkin.SetOption("scale", value / 100) end,
    },
    EditOption("padding", "Padding", 0, 16, 1),
    {
        id = "vertical", label = "Vertical", kind = "toggle",
        get = function() local settings = Settings(); return settings and settings.orientation == "vertical" end,
        set = function(on) return on and NS.MicroMenuSkin.SetOption("orientation", "vertical") or false end,
    },
    {
        id = "horizontal", label = "Horizontal", kind = "toggle",
        get = function() local settings = Settings(); return settings and settings.orientation == "horizontal" end,
        set = function(on) return on and NS.MicroMenuSkin.SetOption("orientation", "horizontal") or false end,
    },
}

local function EnsureEditRegistration()
    if editRegistered or not bar then return editRegistered end
    local api = EditAPI()
    if not api then return false end
    local ok = api.RegisterElement(EDIT_OWNER, {
        id = EDIT_ID, label = "Micro Bar", group = "MSUF Suite", order = 450,
        getFrame = function() return bar end,
        isEnabled = function()
            local settings = Settings()
            return OwnedMicroBar.active and not OwnedMicroBar.suspended
                and IsOwnedMode(settings) and NS.DB.skins.microMenu ~= false
        end,
        captureState = EditState,
        restoreState = function(state)
            if not ValidEditState(state) then return false end
            local settings = Settings()
            local restored = PlaceEditPosition(state, state.x, state.y, true)
            if not restored then return false end
            settings.positionPreset = state.positionPreset
            settings.orientation = state.orientation
            settings.buttonsPerLine = state.buttonsPerLine
            settings.spacing = state.spacing
            settings.scale = state.scale
            settings.padding = state.padding
            local refreshed
            if NS.MicroMenuSkin.active then
                refreshed = NS.MicroMenuSkin.RefreshActive()
            else
                refreshed = OwnedMicroBar.Apply(activeRoot, settings)
            end
            return refreshed ~= false and refreshed ~= nil
        end,
        movePosition = function(request)
            local state = request and request.state
            if not ValidEditState(state) then return false end
            local scale = ReadNumber(bar, "GetScale", 1)
            if scale <= 0 then scale = 1 end
            local x = state.x + (tonumber(request.deltaX) or 0) / scale
            local y = state.y + (tonumber(request.deltaY) or 0) / scale
            return PlaceEditPosition(state, x, y, request.phase == "commit")
        end,
        resetPosition = function()
            local defaultName = NS.Defaults and NS.Defaults.icons and NS.Defaults.icons.microMenu
                and NS.Defaults.icons.microMenu.positionPreset or "bottomRight"
            local preset = NS.MicroMenuPositionPresets and NS.MicroMenuPositionPresets[defaultName]
            local settings = Settings()
            if not preset or not settings or IsCombatLocked() then return false end
            settings.layoutPoint = preset.point
            settings.layoutRelativePoint = preset.relativePoint or preset.point
            settings.layoutX, settings.layoutY = preset.x or 0, preset.y or 0
            settings.positionPreset = defaultName
            return ApplyPosition(settings)
        end,
        onSessionChanged = function(enabled)
            editSession = enabled == true
            if OwnedMicroBar.active and not OwnedMicroBar.suspended then
                ApplyVisibility(Settings())
            end
        end,
        extraControls = editControls,
        openSettings = function()
            local open = ReadMember(_G, "MSUF2_Open")
            if type(open) ~= "function" then return false end
            return pcall(open, "suite_skin")
        end,
    })
    editRegistered = ok == true
    if editRegistered then SetMoverVisible(false) end
    return editRegistered
end

local function EnsureFrames()
    if bar and mover then return true end
    if type(CreateFrame) ~= "function" or not UIParent then return false end

    bar = CreateFrame("Frame", BAR_NAME, UIParent)
    bar:SetSize(1, 1)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(false)
    bar:SetScript("OnEnter", HoverEnter)
    bar:SetScript("OnLeave", HoverLeave)
    bar:Hide()

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

    -- The mover is a UIParent sibling, not a child of the protected bar. It can
    -- disappear on combat start without mutating Blizzard controls.
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
    label:SetText("Drag MapkoSkin Micro Bar")

    -- Allocate the structural regions before the native MicroMenu becomes a
    -- child. Afterwards the owned root is implicitly protected, so refreshes
    -- should only repaint already-created regions.
    if NS.Surface and type(NS.Surface.Attach) == "function" then
        local surface = NS.Surface.Attach(bar, { role = "microBar" })
        if surface and type(NS.Surface.SetVisible) == "function" then
            NS.Surface.SetVisible(bar, false)
        end
    end

    mover:SetScript("OnDragStart", function()
        local settings = Settings()
        if IsCombatLocked() or not OwnedMicroBar.active or not settings
            or settings.locked ~= false then
            return
        end
        CallMethod(bar, "StartMoving")
    end)
    mover:SetScript("OnDragStop", function()
        CallMethod(bar, "StopMovingOrSizing")
        if SavePosition() then ScheduleReapply() end
    end)
    return true
end

local function PositionEnumFor(settings)
    local left, bottom
    local okBar, barX, barY = CallMethod(bar, "GetCenter")
    local okUI, uiX, uiY = CallMethod(UIParent, "GetCenter")
    barX, barY = Accessible(barX), Accessible(barY)
    uiX, uiY = Accessible(uiX), Accessible(uiY)
    if okBar and okUI and type(barX) == "number" and type(barY) == "number"
        and type(uiX) == "number" and type(uiY) == "number" then
        left = barX < uiX
        bottom = barY < uiY
    else
        local point = tostring(settings.layoutPoint or "BOTTOMRIGHT")
        local right = point:find("RIGHT", 1, true) ~= nil
        local top = point:find("TOP", 1, true) ~= nil
        left = point:find("LEFT", 1, true) ~= nil
        bottom = point:find("BOTTOM", 1, true) ~= nil
        if not left and not right then
            left = (tonumber(settings.layoutX) or 0) <= 0
        end
        if not top and not bottom then
            bottom = (tonumber(settings.layoutY) or 0) <= 0
        end
    end
    local values = ReadMember(_G, "MicroMenuPositionEnum") or {}
    if bottom then return left and values.BottomLeft or values.BottomRight end
    return left and values.TopLeft or values.TopRight
end

local function ApplyGrid(root, settings)
    local growth = settings.growth or "RIGHT_DOWN"
    local horizontal = settings.orientation ~= "vertical"
    local perLine = math.floor(Clamp(settings.buttonsPerLine, 1, MAX_BUTTONS_PER_LINE) + 0.5)
    local buttonCount = ReadMember(root, "numButtons")
    if type(buttonCount) ~= "number" then buttonCount = perLine end
    local spacing = math.floor(Clamp(settings.spacing, -8, 16) + 0.5)
    local scale = Clamp(settings.scale, 0.50, 1.50)
    portraitEnabled = (settings.barMaterial == "forever" or settings.barMaterial == "modern"
        or settings.barMaterial == "midnightDark")
        and (settings.iconStyle == "bold" or settings.iconStyle == "blizzardIcons")
        and horizontal and perLine >= buttonCount

    pcall(function()
        root.isHorizontal = horizontal
        root.stride = perLine
        root.isStacked = perLine < buttonCount
        root.childXPadding = spacing
        root.childYPadding = spacing
        root.layoutFramesGoingRight =
            growth == "RIGHT_DOWN" or growth == "RIGHT_UP"
        root.layoutFramesGoingUp =
            growth == "RIGHT_UP" or growth == "LEFT_UP"
    end)
    if not CallMethod(root, "SetOverrideScale", scale) then
        CallMethod(root, "SetScale", scale)
    end
    MarkAndLayout(root)
    CallMethod(root, "ClearAllPoints")
    local portraitSpace = portraitEnabled and FOREVER_PORTRAIT_SPACE or 0
    CallMethod(root, "SetPoint", "CENTER", bar, "CENTER", portraitSpace / 2, 0)

    local rootScale = ReadNumber(root, "GetScale", scale)
    local width = math.max(1, ReadNumber(root, "GetWidth", 1) * rootScale)
    local height = math.max(1, ReadNumber(root, "GetHeight", 1) * rootScale)
    local padding = math.floor(Clamp(settings.padding, 0, 16) + 0.5)
    local shellHeight = height + padding * 2
    if portraitEnabled and settings.barMaterial == "forever" then
        -- Native button hit boxes are taller than our visible 32px plates.
        -- Size the owned shell to the artwork so its frame stays compact.
        shellHeight = math.max(42, Clamp(settings.buttonSize, 20, 32) * scale
            + padding * 2 + 2)
    end
    CallMethod(bar, "SetSize", width + padding * 2 + portraitSpace, shellHeight)
    portrait:SetShown(portraitEnabled)
    portraitRing:SetShown(portraitEnabled)
    topRule:SetShown(portraitEnabled)
    bottomRule:SetShown(portraitEnabled)
    if portraitEnabled then
        portraitRing:SetTexture(settings.barMaterial == "forever" and FOREVER_RING or MIDNIGHT_RING)
        portraitRing:SetDesaturated(settings.barMaterial == "midnightDark")
        if settings.barMaterial == "midnightDark" then
            portraitRing:SetVertexColor(0.84, 0.85, 0.82, 1)
        else
            portraitRing:SetVertexColor(1, 1, 1, 1)
        end
        local r, g, b, a = NS.Theme.GetColor("microBarBorder")
        topRule:SetColorTexture(r, g, b, a * 0.82)
        bottomRule:SetColorTexture(r, g, b, a * 0.52)
        if type(_G.SetPortraitTexture) == "function" then
            _G.SetPortraitTexture(portrait, "player")
        end
    end

    -- Blizzard intentionally leaves Help attached to the external MicroMenu.
    -- Recalculate only that edge using the owned bar's quadrant; Queue and FPS
    -- remain with Blizzard's Edit Mode container by native contract.
    local position = PositionEnumFor(settings)
    if position then CallMethod(root, "UpdateHelpTicketButtonAnchor", position) end
    return true
end

local function Reapply()
    if not desired or not OwnedMicroBar.active or not NS.MicroMenuSkin then return end
    NS.MicroMenuSkin.RefreshActive()
end

ScheduleReapply = function()
    if not desired or suppressResetHook then return end
    if NS.CombatGate and type(NS.CombatGate.RunOrDefer) == "function" then
        NS.CombatGate.RunOrDefer(REAPPLY_KEY, Reapply)
    elseif not IsCombatLocked() then
        Reapply()
    end
end

local function OnNativeReset(root)
    if suppressResetHook then return end
    if desired and OwnedMicroBar.active and root == activeRoot then
        ScheduleReapply()
    end
end

local function EnsureHooks(root)
    if resetHookRoot ~= root
        and type(ReadMember(root, "ResetMicroMenuPosition")) == "function"
        and type(hooksecurefunc) == "function" then
        local ok = pcall(function()
            hooksecurefunc(root, "ResetMicroMenuPosition", OnNativeReset)
        end)
        if ok then resetHookRoot = root end
    end
    if overrideHookRoot ~= root
        and type(ReadMember(root, "OverrideMicroMenuPosition")) == "function"
        and type(hooksecurefunc) == "function" then
        local ok = pcall(function()
            hooksecurefunc(root, "OverrideMicroMenuPosition", ScheduleReapply)
        end)
        if ok then overrideHookRoot = root end
    end
    if not setFullScreenHooked
        and type(ReadMember(_G, "MicroMenuBar_SetFullScreenFrame")) == "function"
        and type(hooksecurefunc) == "function" then
        local ok = pcall(function()
            hooksecurefunc("MicroMenuBar_SetFullScreenFrame", ScheduleReapply)
        end)
        if ok then setFullScreenHooked = true end
    end
    if not clearFullScreenHooked
        and type(ReadMember(_G, "MicroMenuBar_ClearFullScreenFrame")) == "function"
        and type(hooksecurefunc) == "function" then
        local ok = pcall(function()
            hooksecurefunc("MicroMenuBar_ClearFullScreenFrame", ScheduleReapply)
        end)
        if ok then clearFullScreenHooked = true end
    end
end

local eventsRegistered, addonListening = false, false
local function RegisterEvents()
    if not eventsRegistered then
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
        eventFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
        eventsRegistered = true
    end
    if not editRegistered and not addonListening then
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
        eventsRegistered = false
    end
    if addonListening then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addonListening = false
    end
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if EnsureEditRegistration() and addonListening then
            eventFrame:UnregisterEvent("ADDON_LOADED")
            addonListening = false
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        SetMoverVisible(false)
        return
    end
    if event == "UNIT_PORTRAIT_UPDATE" then
        if unit == "player" and portraitEnabled and not IsCombatLocked()
            and type(_G.SetPortraitTexture) == "function" then
            _G.SetPortraitTexture(portrait, "player")
        end
        return
    end
    ScheduleReapply()
end)

function OwnedMicroBar.Apply(root, settings)
    settings = settings or Settings()
    desired = IsOwnedMode(settings)
    if not desired then
        OwnedMicroBar.Disable(root)
        return root, "blizzard"
    end
    if IsCombatLocked() then return nil, "combat" end
    if not root or not CanOwn(root) or not EnsureFrames() then
        return nil, "unavailable"
    end

    activeRoot = root
    OwnedMicroBar.active = true
    RegisterEvents()
    EnsureHooks(root)

    local ok, parent = CallMethod(root, "GetParent")
    local defaultParent = ReadMember(_G, "MicroMenuContainer")
    if ok and parent == UIParent and not nativeState then
        -- Blizzard's fullscreen clear path deliberately leaves MicroMenu on
        -- UIParent. Establish the canonical Edit Mode state before taking the
        -- first reversible snapshot.
        suppressResetHook = true
        CallMethod(root, "ResetMicroMenuPosition")
        suppressResetHook = false
        ok, parent = CallMethod(root, "GetParent")
    end
    if ok and parent ~= bar and parent ~= defaultParent and parent ~= UIParent then
        OwnedMicroBar.suspended = true
        ClearVisibilityDriver()
        CallMethod(bar, "Hide")
        SetMoverVisible(false)
        return root, "blizzard-override"
    end

    CaptureNative(root)
    OwnedMicroBar.suspended = false
    if parent ~= bar and not SetParentMaintainRenderLayering(root, bar) then
        return nil, "parent"
    end
    ApplyPosition(settings)
    ApplyGrid(root, settings)
    ApplyVisibility(settings)
    if EnsureEditRegistration() and addonListening then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addonListening = false
    end
    SetMoverVisible(settings.locked == false)
    local api = EditAPI()
    if editRegistered and api and api.RefreshOwner then api.RefreshOwner(EDIT_OWNER) end
    return bar, "owned"
end

function OwnedMicroBar.Disable(root)
    desired = false
    root = root or activeRoot
    if IsCombatLocked() then return false, "combat" end
    local success = true
    if root and nativeState and nativeState.root == root then
        local restored = RestoreNative(root)
        success = restored ~= false
    end
    CancelHoverTimer()
    ClearVisibilityDriver()
    editSession = false
    hoverButtons = setmetatable({}, { __mode = "k" })
    if bar then
        CallMethod(bar, "EnableMouse", false)
        CallMethod(bar, "SetAlpha", 1)
    end
    SetMoverVisible(false)
    if bar then CallMethod(bar, "Hide") end
    UnregisterEvents()
    OwnedMicroBar.active = false
    OwnedMicroBar.suspended = false
    portraitEnabled = false
    activeRoot = nil
    nativeState = nil
    local api = EditAPI()
    if editRegistered and api and api.RefreshOwner then api.RefreshOwner(EDIT_OWNER) end
    return success, success and "disabled" or "partial"
end

function OwnedMicroBar.GetSurfaceTarget(root, settings)
    if IsOwnedMode(settings or Settings()) and OwnedMicroBar.active
        and not OwnedMicroBar.suspended and activeRoot == root and bar then
        return bar, true
    end
    return root, false
end

function OwnedMicroBar.GetFrames()
    return bar, mover
end

function OwnedMicroBar.SavePosition()
    return SavePosition()
end

function OwnedMicroBar.RefreshMover()
    local settings = Settings()
    SetMoverVisible(OwnedMicroBar.active and settings and settings.locked == false)
end

function OwnedMicroBar.OpenEditMode()
    if IsCombatLocked() then return false end
    if not EnsureEditRegistration() then return false end
    local api = EditAPI()
    return api and api.EnterEditMode and api.EnterEditMode(EDIT_OWNER, EDIT_ID) == true
end
