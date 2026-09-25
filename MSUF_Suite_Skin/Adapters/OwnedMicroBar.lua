local _, NS = ...

-- MSKIN owns the bar shell, position and grid policy. Blizzard keeps the
-- MicroMenu frame, every native MicroButton, scripts, alerts and click state.
-- The complete MicroMenu is moved as one unit only outside combat; individual
-- buttons are never reparented or replaced.
--
-- Grid ownership without Blizzard fields: GridLayoutFrameMixin.Layout reads
-- isHorizontal, stride, childXPadding/childYPadding and layoutFramesGoingRight
-- /Up from MicroMenu, and Edit Mode writes them (EditModeMicroMenuSystemMixin).
-- Values written by addon code would taint every later Edit Mode pass that
-- reads them (MicroMenuContainerMixin:Layout reads isHorizontal first). The
-- owned bar therefore never writes them: it anchors MicroMenu's layout
-- children itself with GridLayoutUtil and its own parameters, sizes MicroMenu
-- to their extents the way ResizeLayoutMixin does, and re-applies that after
-- every native MicroMenu:Layout (post-hook) while the bar owns the menu.
local OwnedMicroBar = {
    active = false,
    suspended = false,
}
NS.OwnedMicroBar = OwnedMicroBar

local Field = NS.Safety.Field
local Call = NS.Safety.Call
local Public = NS.Safety.Public

-- Exactly one boolean, also for a missing target (Field returns no value then).
local function HasMethod(target, name)
    return type(target) == "table" and type(target[name]) == "function"
end
-- SharedXML utilities, loaded before any addon on every client.
local GridLayoutUtil = _G.GridLayoutUtil
local AnchorUtil = _G.AnchorUtil

local BAR_NAME = "MapkoSkinMicroBar"
local HEALTH_GATE_NAME = "MapkoSkinMicroBarHealthGate"
local MOVER_NAME = "MapkoSkinMicroBarMover"
local REAPPLY_KEY = "micro-menu:owned-reapply"
local FOREVER_PORTRAIT_SPACE = 48
local MAX_BUTTONS_PER_LINE = NS.Client.isForever and 14 or 13
local PORTRAIT_LEFT_INSET = 9
local RULE_LEFT_INSET = 62
local HELP_BUTTON_OFFSET = 25
local FOREVER_RING = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\ForeverPortraitRing.tga"
local MIDNIGHT_RING = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\MidnightPortraitRing.tga"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local EDIT_OWNER, EDIT_ID = "MSUFSuite.Skin", "microBar"
local VISIBILITY_DRIVERS = {
    combat = "[combat] show; hide",
    outOfCombat = "[combat] hide; show",
}
local HOVER_GRACE = 0.12
local PORTRAIT_MATERIALS = { forever = true, modern = true, midnightDark = true }
local PORTRAIT_ICON_STYLES = { bold = true, blizzardIcons = true }

local bar, healthGate, healthCurve
local mover
local portrait, portraitRing, topRule, bottomRule
local portraitEnabled = false
local activeRoot
local nativeState
local suppressResetHook = false
local hookedRoots = setmetatable({}, { __mode = "k" })
local hookedGlobals = {}
local desired = false
local ScheduleReapply
local editRegistered = false
local editProfile, editEpoch = nil, 0
local visibilityDriver, editSession, hoverTimer
local hoverButtons = setmetatable({}, { __mode = "k" })

local eventFrame = CreateFrame("Frame")

local function Settings()
    return NS.DB and NS.DB.icons and NS.DB.icons.microMenu
end

local function IsTrue(value)
    return Public(value) and value == true
end

local function ReadNumber(target, methodName, fallback)
    local value = Call(target, methodName)
    if type(value) == "number" and Public(value) then return value end
    return fallback
end

local function ProfileEpoch()
    if editProfile ~= NS.DB then
        editProfile, editEpoch = NS.DB, editEpoch + 1
    end
    return editEpoch
end

local function CanOwn(target)
    return NS.Safety.CanControl(target, true) == true
end

local function SetParentMaintainRenderLayering(target, parent)
    local frameUtil = _G.FrameUtil
    if frameUtil and type(frameUtil.SetParentMaintainRenderLayering) == "function" then
        frameUtil.SetParentMaintainRenderLayering(target, parent)
    else
        target:SetParent(parent)
    end
end

local function IsOwnedMode(settings)
    return settings and settings.layoutMode == "owned"
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

-- Visibility and hover -----------------------------------------------------------

local function CancelHoverTimer()
    if hoverTimer then
        hoverTimer:Cancel()
        hoverTimer = nil
    end
end

local function MouseInside()
    if IsTrue(Call(bar, "IsMouseOver")) then return true end
    for button in pairs(hoverButtons) do
        if IsTrue(Call(button, "IsMouseOver")) then return true end
    end
    return false
end

local function MouseoverActive()
    local settings = Settings()
    return OwnedMicroBar.active and not OwnedMicroBar.suspended and not editSession
        and settings and settings.visibility == "mouseover" and bar ~= nil
end

local function HoverEnter()
    CancelHoverTimer()
    if MouseoverActive() then bar:SetAlpha(1) end
end

local function HideAfterGrace()
    hoverTimer = nil
    if MouseoverActive() and not MouseInside() then bar:SetAlpha(0) end
end

local function HoverLeave()
    if not MouseoverActive() then return end
    CancelHoverTimer()
    local timer = _G.C_Timer
    if timer and type(timer.NewTimer) == "function" then
        hoverTimer = timer.NewTimer(HOVER_GRACE, HideAfterGrace)
    elseif not MouseInside() then
        bar:SetAlpha(0)
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

local function InInstance()
    if type(_G.IsInInstance) ~= "function" then return false end
    local inside = _G.IsInInstance()
    return inside == true or inside == 1
end

local function InHousing()
    local housing = _G.C_Housing
    local check = housing and housing.IsInsideHouseOrPlot
    return type(check) == "function" and check() == true
end

local function RefreshHealthGate(settings)
    if not healthGate then return end
    if editSession or not (settings and settings.loadShowWhenInjured) then
        healthGate:SetAlpha(1)
        return
    end
    local percent, curveAPI = _G.UnitHealthPercent, _G.C_CurveUtil
    local curveType = _G.Enum and _G.Enum.LuaCurveType
    if type(percent) == "function" and curveAPI and type(curveAPI.CreateCurve) == "function"
        and curveType and curveType.Step then
        if not healthCurve then
            healthCurve = curveAPI.CreateCurve()
            healthCurve:SetType(curveType.Step)
            healthCurve:AddPoint(0, 1)
            healthCurve:AddPoint(1, 0)
        end
        -- Keep Midnight's secret health in Blizzard's curve and pass its
        -- result directly to native alpha, independently of mouseover alpha.
        healthGate:SetAlpha(percent("player", false, healthCurve))
    elseif type(_G.UnitHealth) == "function" and type(_G.UnitHealthMax) == "function" then
        local current, maximum = _G.UnitHealth("player"), _G.UnitHealthMax("player")
        local secret = _G.issecretvalue
        if type(secret) == "function" and (secret(current) or secret(maximum)) then
            healthGate:SetAlpha(1)
        else
            healthGate:SetAlpha(maximum > 0 and current < maximum and 1 or 0)
        end
    else
        healthGate:SetAlpha(1)
    end
end

-- Load conditions that the "show when injured" rule overrides.
local INJURED_OVERRIDES = {
    loadHideNoTarget = true,
    loadHideOutOfCombat = true,
    loadHideOutOfCombatNoTarget = true,
}

-- The secure visibility driver for the mode plus the enabled load conditions.
local function ConditionalDriver(settings, mode)
    if not settings then return VISIBILITY_DRIVERS[mode] end
    local rules, count = {}, 0
    local injured = settings.loadShowWhenInjured == true
    for _, condition in ipairs(NS.MicroMenuLoadConditions) do
        local key, macro = condition[1], condition[3]
        if macro and settings[key] == true and not (injured and INJURED_OVERRIDES[key]) then
            count = count + 1
            rules[count] = macro
        end
    end
    if count == 0 then return VISIBILITY_DRIVERS[mode] end
    if mode == "combat" then
        table.insert(rules, 1, "[nocombat] hide")
    elseif mode == "outOfCombat" then
        table.insert(rules, 1, "[combat] hide")
    end
    rules[#rules + 1] = "show"
    return table.concat(rules, "; ")
end

local function ApplyVisibility(settings)
    if not bar or NS.IsCombatLocked() then return false end
    CancelHoverTimer()
    local mode = editSession and "always" or (settings and settings.visibility) or "always"
    local blocked = not editSession and settings and (settings.loadHideInInstance and InInstance()
        or settings.loadHideInHousing and InHousing())
    local driver = mode ~= "never" and not editSession and ConditionalDriver(settings, mode) or nil
    if blocked and driver then driver = "hide" end
    if driver and type(_G.RegisterStateDriver) ~= "function" then mode, driver = "always", nil end
    if visibilityDriver ~= driver then
        ClearVisibilityDriver()
        if driver then
            _G.RegisterStateDriver(bar, "visibility", driver)
            visibilityDriver = driver
        end
    end
    bar:EnableMouse(mode == "mouseover")
    bar:SetAlpha(mode == "mouseover" and (MouseInside() and 1 or 0) or 1)
    if mode == "never" or blocked and not driver then
        bar:Hide()
    elseif not driver then
        bar:Show()
    end
    RefreshHealthGate(settings)
    return true
end

-- MicroMenuSkin's single OnEnter/OnLeave script hook per native button calls
-- these, so hovering a button keeps a mouseover-only bar revealed.
OwnedMicroBar.HoverEnter = HoverEnter
OwnedMicroBar.HoverLeave = HoverLeave

function OwnedMicroBar.TrackHoverButtons(buttons)
    hoverButtons = setmetatable({}, { __mode = "k" })
    for button in pairs(buttons) do
        hoverButtons[button] = true
    end
end

-- Grid ------------------------------------------------------------------------------

-- One cached GridLayoutUtil layout and anchor: the owned settings rarely change.
local gridCache = {}

local function GridLayout(root, horizontal, stride, spacingX, spacingY, goingRight, goingUp)
    local cache = gridCache
    if cache.layout and cache.root == root and cache.horizontal == horizontal
        and cache.stride == stride and cache.spacingX == spacingX and cache.spacingY == spacingY
        and cache.goingRight == goingRight and cache.goingUp == goingUp then
        return cache.layout, cache.anchor
    end
    -- Same construction as GridLayoutFrameMixin.Layout: multipliers pick the
    -- growth direction and the anchor corner follows it.
    local xMultiplier = goingRight and 1 or -1
    local yMultiplier = goingUp and 1 or -1
    local layout
    if horizontal then
        layout = GridLayoutUtil.CreateStandardGridLayout(stride, spacingX, spacingY, xMultiplier, yMultiplier)
    else
        layout = GridLayoutUtil.CreateVerticalGridLayout(stride, spacingX, spacingY, xMultiplier, yMultiplier)
    end
    local anchorPoint
    if goingUp then
        anchorPoint = goingRight and "BOTTOMLEFT" or "BOTTOMRIGHT"
    else
        anchorPoint = goingRight and "TOPLEFT" or "TOPRIGHT"
    end
    cache.layout, cache.anchor = layout, AnchorUtil.CreateAnchor(anchorPoint, root, anchorPoint)
    cache.root, cache.horizontal, cache.stride = root, horizontal, stride
    cache.spacingX, cache.spacingY = spacingX, spacingY
    cache.goingRight, cache.goingUp = goingRight, goingUp
    return cache.layout, cache.anchor
end

-- ResizeLayoutMixin.Layout's size rule, measured instead of called: calling it
-- would write Blizzard's dirty flag from addon code.
local function FitToChildren(root, children)
    local scale = ReadNumber(root, "GetEffectiveScale", 1)
    if scale <= 0 then scale = 1 end
    local left, right, top, bottom
    for index = 1, #children do
        local x, y, width, height = Call(children[index], "GetScaledRect")
        if x == nil or not Public(x) or not Public(y) or not Public(width) or not Public(height) then
            x, y, width, height = 1, 1, 1, 1
        else
            x, y, width, height = x / scale, y / scale, width / scale, height / scale
        end
        left = left and math.min(left, x) or x
        right = right and math.max(right, x + width) or x + width
        bottom = bottom and math.min(bottom, y) or y
        top = top and math.max(top, y + height) or y + height
    end
    if left then
        root:SetSize(right - left, top - bottom)
    else
        root:SetSize(1, 1)
    end
end

-- Anchors MicroMenu's layout children like GridLayoutFrameMixin.Layout would
-- with these parameters. Returns false when the client has no grid layout.
local function PlaceGrid(root, horizontal, stride, spacingX, spacingY, goingRight, goingUp)
    if not GridLayoutUtil or not AnchorUtil or type(stride) ~= "number" then return false end
    local children = Call(root, "GetLayoutChildren")
    if type(children) ~= "table" then return false end
    if #children > 0 then
        local layout, anchor = GridLayout(root, horizontal, stride, spacingX, spacingY,
            goingRight, goingUp)
        GridLayoutUtil.ApplyGridLayout(children, anchor, layout)
    end
    FitToChildren(root, children)
    return true
end

-- Puts back Blizzard's own grid, read from its untouched fields. Its cached
-- layout still matches those fields, so Blizzard's next Layout keeps it.
local function PlaceNativeGrid(root)
    return PlaceGrid(root, root.isHorizontal, root.stride, root.childXPadding,
        root.childYPadding, root.layoutFramesGoingRight, root.layoutFramesGoingUp)
end

local function OwnedGrowth(settings)
    local growth = settings.growth or "RIGHT_DOWN"
    return growth == "RIGHT_DOWN" or growth == "RIGHT_UP",
        growth == "RIGHT_UP" or growth == "LEFT_UP"
end

local function PerLine(settings)
    return math.floor(Clamp(settings.buttonsPerLine, 1, MAX_BUTTONS_PER_LINE) + 0.5)
end

-- Companions --------------------------------------------------------------------------

-- left, bottom: which screen quadrant holds the frame's center. Without a
-- readable center the saved anchor decides, as it will once the bar is placed.
local function Quadrant(frame, settings)
    local frameX, frameY = Call(frame, "GetCenter")
    local screenX, screenY = Call(UIParent, "GetCenter")
    if type(frameX) == "number" and type(frameY) == "number"
        and type(screenX) == "number" and type(screenY) == "number"
        and Public(frameX) and Public(frameY) and Public(screenX) and Public(screenY) then
        return frameX < screenX, frameY < screenY
    end
    local point = tostring(settings.layoutPoint or "BOTTOMRIGHT")
    local left = point:find("LEFT", 1, true) ~= nil
    local bottom = point:find("BOTTOM", 1, true) ~= nil
    if not left and point:find("RIGHT", 1, true) == nil then
        left = (tonumber(settings.layoutX) or 0) <= 0
    end
    if not bottom and point:find("TOP", 1, true) == nil then
        bottom = (tonumber(settings.layoutY) or 0) <= 0
    end
    return left, bottom
end

-- The first and last native button by layoutIndex, hidden ones included,
-- exactly as MicroMenuMixin:GetEdgeButton collects them.
local function EdgeButtons(...)
    local first, last
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        local layoutIndex = Field(child, "layoutIndex")
        if type(layoutIndex) == "number" then
            if not first or layoutIndex < first.layoutIndex then first = child end
            if not last or layoutIndex > last.layoutIndex then last = child end
        end
    end
    return first, last
end

-- MicroMenuMixin:UpdateHelpTicketButtonAnchor with the owned orientation:
-- the ticket button sits above/below the button on the outer screen edge.
local function AnchorHelpButton(root, horizontal, left, bottom)
    local help = _G.HelpOpenWebTicketButton
    if not help then return end
    local first, last = EdgeButtons(root:GetChildren())
    if not first then return end
    local firstX, firstY = first:GetCenter()
    local lastX, lastY = last:GetCenter()
    if not firstX or not lastX then return end
    local edge
    if horizontal then
        if left then
            edge = firstX > lastX and first or last
        else
            edge = firstX < lastX and first or last
        end
    elseif bottom then
        edge = firstY > lastY and first or last
    else
        edge = firstY < lastY and first or last
    end
    help:SetPoint("CENTER", edge, "CENTER", 0, bottom and HELP_BUTTON_OFFSET or -HELP_BUTTON_OFFSET)
end

-- The container's quadrant in the client's own enum (Retail/Classic:
-- MicroMenuContainer:GetPosition, Forever: FrameUtil.GetScreenQuadrant).
local function ContainerPosition(container)
    if HasMethod(container, "GetPosition") then
        return container:GetPosition()
    end
    local frameUtil = _G.FrameUtil
    if container and frameUtil and type(frameUtil.GetScreenQuadrant) == "function" then
        return frameUtil.GetScreenQuadrant(container)
    end
end

-- MicroMenuMixin:Layout re-anchors the queue eye and the framerate text around
-- Blizzard's Edit Mode container using MicroMenu's orientation. Their own
-- UpdatePosition APIs take the orientation, so pass the owned one. Queue and
-- FPS stay with that container by native contract; the help button follows
-- the owned bar (Retail/Classic) or the container quadrant (Forever), as the
-- native Layout used to place it.
local function AnchorCompanions(root, settings, horizontal)
    local container = _G.MicroMenuContainer
    local position = ContainerPosition(container)
    if position ~= nil then
        if type(root.UpdateQueueStatusAnchors) == "function" then
            Call(_G.QueueStatusButton, "UpdatePosition", position, horizontal)
            Call(_G.QueueStatusFrame, "UpdatePosition", position, horizontal)
        end
        local editSystem = _G.EditModeSystemMixin
        local defaultPosition = editSystem and type(editSystem.IsInDefaultPosition) == "function"
            and editSystem.IsInDefaultPosition(container)
        Call(_G.FramerateFrame, "UpdatePosition", position, horizontal, defaultPosition)
    end
    local left, bottom = Quadrant(_G.MicroMenuPositionEnum and bar or container, settings)
    AnchorHelpButton(root, horizontal, left, bottom)
end

-- Places the owned grid; returns the owned orientation.
local function LayoutButtons(root, settings)
    local horizontal = settings.orientation ~= "vertical"
    local spacing = math.floor(Clamp(settings.spacing, -8, 16) + 0.5)
    local goingRight, goingUp = OwnedGrowth(settings)
    PlaceGrid(root, horizontal, PerLine(settings), spacing, spacing, goingRight, goingUp)
    return horizontal
end

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
    if not bar or not UIParent then return false end
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
    mover:SetShown(visible == true and not editRegistered and not NS.IsCombatLocked())
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
    if type(_G.SetPortraitTexture) == "function" then
        _G.SetPortraitTexture(portrait, "player")
    end
end

-- Grid, shell and companions for the current settings (out of combat). The
-- help button's quadrant depends on where the sized shell ended up.
local function LayoutOwned(root, settings)
    local horizontal = LayoutButtons(root, settings)
    ApplyShell(root, settings, horizontal, Clamp(settings.scale, 0.50, 1.50))
    AnchorCompanions(root, settings, horizontal)
end

local function ApplyGrid(root, settings)
    local scale = Clamp(settings.scale, 0.50, 1.50)
    -- SetOverrideScale is Blizzard's API for a temporarily reparented menu;
    -- ResetMicroMenuPosition clears it again.
    if HasMethod(root, "SetOverrideScale") then
        root:SetOverrideScale(scale)
    else
        root:SetScale(scale)
    end
    LayoutOwned(root, settings)
end

-- Native state --------------------------------------------------------------------------

local function CapturePoints(frame)
    local points = {}
    for index = 1, math.floor(ReadNumber(frame, "GetNumPoints", 0)) do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        if type(point) == "string" then
            points[#points + 1] = {
                point, relativeTo, relativePoint,
                type(x) == "number" and Public(x) and x or 0,
                type(y) == "number" and Public(y) and y or 0,
            }
        end
    end
    return points
end

local function CaptureNative(root)
    if nativeState and nativeState.root == root then return end
    nativeState = {
        root = root,
        parent = Call(root, "GetParent"),
        points = CapturePoints(root),
        overrideScale = Field(root, "overrideScale"),
    }
end

-- Only for a MicroMenu without ResetMicroMenuPosition.
local function RestoreFallback(root, state)
    if state.parent then SetParentMaintainRenderLayering(root, state.parent) end
    root:ClearAllPoints()
    for index = 1, #state.points do
        root:SetPoint(unpack(state.points[index]))
    end
    local hasOverride = HasMethod(root, "SetOverrideScale")
    if state.overrideScale ~= nil then
        if hasOverride then root:SetOverrideScale(state.overrideScale) else root:SetScale(state.overrideScale) end
    elseif HasMethod(root, "ClearOverrideScale") then
        root:ClearOverrideScale()
    end
end

local function RestoreNative(root)
    local state = nativeState
    if not root or not state or state.root ~= root or not CanOwn(root) then
        return false
    end
    if Call(root, "GetParent") ~= bar then
        -- Blizzard currently owns an override (vehicle, pet battle or a full-
        -- screen flow). Its next ResetMicroMenuPosition restores native state.
        return true, "yielded"
    end

    suppressResetHook = true
    PlaceNativeGrid(root)
    local reset = HasMethod(root, "ResetMicroMenuPosition")
    if reset then
        root:ResetMicroMenuPosition()
    else
        RestoreFallback(root, state)
    end
    suppressResetHook = false
    return true, reset and "reset" or "restored"
end

-- Edit Mode -----------------------------------------------------------------------------

local function EditAPI()
    local api = _G.MSUF_EditModeAPI
    if type(api) == "table" and type(api.RegisterElement) == "function" then
        return api
    end
end

local function RoundTenth(value)
    if value >= 0 then return math.floor(value * 10 + 0.5) / 10 end
    return math.ceil(value * 10 - 0.5) / 10
end

local function PlaceEditPosition(state, x, y, commit)
    local settings = Settings()
    if not settings or not bar or NS.IsCombatLocked() or not UIParent then return false end
    if type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or math.abs(x) > 4096 or math.abs(y) > 4096 then
        return false
    end
    if commit then
        settings.layoutPoint = state.point
        settings.layoutRelativePoint = state.relativePoint
        settings.layoutX = RoundTenth(x)
        settings.layoutY = RoundTenth(y)
        settings.positionPreset = "custom"
        return ApplyPosition(settings)
    end
    bar:ClearAllPoints()
    bar:SetPoint(state.point, UIParent, state.relativePoint, x, y)
    return true
end

local function EditState()
    local settings = Settings()
    if not settings then return nil end
    return {
        epoch = ProfileEpoch(),
        point = settings.layoutPoint,
        relativePoint = settings.layoutRelativePoint,
        x = settings.layoutX,
        y = settings.layoutY,
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
        get = function()
            local settings = Settings()
            return settings and settings[key]
        end,
        set = function(value) return NS.MicroMenuSkin.SetOption(key, value) end,
    }
end

local function OrientationToggle(orientation, label)
    return {
        id = orientation, label = label, kind = "toggle",
        get = function()
            local settings = Settings()
            return settings and settings.orientation == orientation
        end,
        set = function(on)
            return on and NS.MicroMenuSkin.SetOption("orientation", orientation) or false
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
    OrientationToggle("vertical", "Vertical"),
    OrientationToggle("horizontal", "Horizontal"),
}

local editElement = {
    id = EDIT_ID, label = "Micro Bar", group = "MSUF Suite", order = 450,
    getFrame = function() return bar end,
    isEnabled = function()
        return OwnedMicroBar.active and not OwnedMicroBar.suspended
            and IsOwnedMode(Settings()) and NS.DB.skins.microMenu ~= false
    end,
    captureState = EditState,
    restoreState = function(state)
        if not ValidEditState(state) or not PlaceEditPosition(state, state.x, state.y, true) then
            return false
        end
        local settings = Settings()
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
        local defaults = NS.Defaults.icons and NS.Defaults.icons.microMenu
        local settings = Settings()
        if not defaults or not settings or NS.IsCombatLocked() then return false end
        settings.layoutPoint = defaults.layoutPoint
        settings.layoutRelativePoint = defaults.layoutRelativePoint
        settings.layoutX, settings.layoutY = defaults.layoutX, defaults.layoutY
        settings.positionPreset = defaults.positionPreset
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
        local open = _G.MSUF2_Open
        if type(open) ~= "function" then return false end
        open("suite_skin")
        return true
    end,
}

local function EnsureEditRegistration()
    if editRegistered or not bar then return editRegistered end
    local api = EditAPI()
    if not api then return false end
    editRegistered = api.RegisterElement(EDIT_OWNER, editElement) == true
    if editRegistered then SetMoverVisible(false) end
    return editRegistered
end

local function RefreshEditOwner()
    local api = EditAPI()
    if editRegistered and api and api.RefreshOwner then api.RefreshOwner(EDIT_OWNER) end
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

local function EnsureFrames()
    if bar and mover then return true end
    if type(CreateFrame) ~= "function" or not UIParent then return false end

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
    if NS.Surface.Attach(bar, { role = "microBar" }) then
        NS.Surface.SetVisible(bar, false)
    end

    mover:SetScript("OnDragStart", OnMoverDragStart)
    mover:SetScript("OnDragStop", OnMoverDragStop)
    return true
end

-- Hooks and events ------------------------------------------------------------------------

local function Reapply()
    if desired and OwnedMicroBar.active then
        NS.MicroMenuSkin.RefreshActive()
    end
end

ScheduleReapply = function()
    if not desired or suppressResetHook then return end
    NS.CombatGate.RunOrDefer(REAPPLY_KEY, Reapply)
end

local function OnNativeReset(root)
    if not suppressResetHook and desired and OwnedMicroBar.active and root == activeRoot then
        ScheduleReapply()
    end
end

-- Blizzard runs MicroMenu:Layout on show and after MarkDirty. When its cached
-- grid no longer matches the children it re-anchors them from its own fields;
-- put the owned grid back right after, in the same frame.
local function OnNativeLayout(root)
    if not desired or not OwnedMicroBar.active or OwnedMicroBar.suspended
        or root ~= activeRoot or Call(root, "GetParent") ~= bar then
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

local function HookRootMethod(root, method, callback)
    local hooked = hookedRoots[root]
    if not hooked then
        hooked = {}
        hookedRoots[root] = hooked
    end
    if not hooked[method] and HasMethod(root, method) then
        hooksecurefunc(root, method, callback)
        hooked[method] = true
    end
end

local function HookGlobal(name, callback)
    if not hookedGlobals[name] and type(_G[name]) == "function" then
        hooksecurefunc(name, callback)
        hookedGlobals[name] = true
    end
end

local function EnsureHooks(root)
    HookRootMethod(root, "ResetMicroMenuPosition", OnNativeReset)
    HookRootMethod(root, "OverrideMicroMenuPosition", ScheduleReapply)
    HookRootMethod(root, "Layout", OnNativeLayout)
    HookGlobal("MicroMenuBar_SetFullScreenFrame", ScheduleReapply)
    HookGlobal("MicroMenuBar_ClearFullScreenFrame", ScheduleReapply)
end

local eventsRegistered, addonListening = false, false
local loadEventsRegistered = {}

local function SyncLoadEvents(settings)
    local housingAPI = _G.C_Housing and _G.C_Housing.IsInsideHouseOrPlot
    local housing = settings and settings.loadHideInHousing and type(housingAPI) == "function"
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
        eventsRegistered = true
    end
    SyncLoadEvents(settings)
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
    elseif event == "UNIT_PORTRAIT_UPDATE" then
        -- Registered for the player unit only.
        if portraitEnabled and not NS.IsCombatLocked() and type(_G.SetPortraitTexture) == "function" then
            _G.SetPortraitTexture(portrait, "player")
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

    local parent = Call(root, "GetParent")
    if parent == UIParent and not nativeState and HasMethod(root, "ResetMicroMenuPosition") then
        -- Blizzard's fullscreen clear path deliberately leaves MicroMenu on
        -- UIParent. Establish the canonical Edit Mode state before taking the
        -- first reversible snapshot.
        suppressResetHook = true
        root:ResetMicroMenuPosition()
        suppressResetHook = false
        parent = Call(root, "GetParent")
    end
    if parent ~= bar and parent ~= _G.MicroMenuContainer and parent ~= UIParent then
        OwnedMicroBar.suspended = true
        ClearVisibilityDriver()
        bar:Hide()
        SetMoverVisible(false)
        return root, "blizzard-override"
    end

    CaptureNative(root)
    OwnedMicroBar.suspended = false
    if parent ~= bar then SetParentMaintainRenderLayering(root, bar) end
    ApplyPosition(settings)
    ApplyGrid(root, settings)
    ApplyVisibility(settings)
    if EnsureEditRegistration() then StopAddonListening() end
    SetMoverVisible(settings.locked == false)
    RefreshEditOwner()
    return bar, "owned"
end

function OwnedMicroBar.Disable(root)
    desired = false
    root = root or activeRoot
    if NS.IsCombatLocked() then return false, "combat" end
    local success = true
    if root and nativeState and nativeState.root == root then
        success = RestoreNative(root) ~= false
    end
    CancelHoverTimer()
    ClearVisibilityDriver()
    editSession = false
    hoverButtons = setmetatable({}, { __mode = "k" })
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
    nativeState = nil
    RefreshEditOwner()
    return success, success and "disabled" or "partial"
end

function OwnedMicroBar.GetFrames()
    return bar, mover
end

function OwnedMicroBar.OpenEditMode()
    if NS.IsCombatLocked() or not EnsureEditRegistration() then return false end
    local api = EditAPI()
    return api and api.EnterEditMode and api.EnterEditMode(EDIT_OWNER, EDIT_ID) == true
end
