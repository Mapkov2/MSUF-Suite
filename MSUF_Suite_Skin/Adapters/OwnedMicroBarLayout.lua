local _, NS = ...

-- Placement for the owned Micro Bar (OwnedMicroBar.lua, which loads after
-- this file): MicroMenu's button grid and the native companions around it.
-- Like the rest of the owned bar it writes no Blizzard layout field; see the
-- OwnedMicroBar.lua header for why.
local Layout = {
    MAX_BUTTONS_PER_LINE = NS.MicroMenuMaxButtonsPerLine,
}
NS.OwnedMicroBarLayout = Layout

local Field = NS.Safety.Field
local Call = NS.Safety.Call
local Public = NS.Safety.Public
local HasMethod = NS.Safety.HasMethod
-- SharedXML utilities, loaded before any addon on every client.
local GridLayoutUtil = _G.GridLayoutUtil
local AnchorUtil = _G.AnchorUtil

local HELP_BUTTON_OFFSET = 25

-- The Micro Menu settings of the active profile.
function Layout.Settings()
    return NS.DB and NS.DB.icons and NS.DB.icons.microMenu
end

local Clamp = NS.Clamp

-- A readable number from target:methodName(), or fallback.
function Layout.ReadNumber(target, methodName, fallback)
    local value = Call(target, methodName)
    if type(value) == "number" and Public(value) then return value end
    return fallback
end
local ReadNumber = Layout.ReadNumber

function Layout.PerLine(settings)
    return math.floor(Clamp(settings.buttonsPerLine, 1, Layout.MAX_BUTTONS_PER_LINE) + 0.5)
end
local PerLine = Layout.PerLine

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
-- with these parameters. Returns false without a stride or layout children.
local function PlaceGrid(root, horizontal, stride, spacingX, spacingY, goingRight, goingUp)
    if type(stride) ~= "number" then return false end
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
function Layout.PlaceNativeGrid(root)
    return PlaceGrid(root, root.isHorizontal, root.stride, root.childXPadding,
        root.childYPadding, root.layoutFramesGoingRight, root.layoutFramesGoingUp)
end

local function OwnedGrowth(settings)
    local growth = settings.growth or "RIGHT_DOWN"
    return growth == "RIGHT_DOWN" or growth == "RIGHT_UP",
        growth == "RIGHT_UP" or growth == "LEFT_UP"
end

-- Places the owned grid; returns the owned orientation.
function Layout.LayoutButtons(root, settings)
    local horizontal = settings.orientation ~= "vertical"
    local spacing = math.floor(Clamp(settings.spacing, -8, 16) + 0.5)
    local goingRight, goingUp = OwnedGrowth(settings)
    PlaceGrid(root, horizontal, PerLine(settings), spacing, spacing, goingRight, goingUp)
    return horizontal
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
    local help = HelpOpenWebTicketButton
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

-- The container's quadrant in the client's own enum: Retail has
-- MicroMenuContainer:GetPosition, Forever FrameUtil.GetScreenQuadrant.
local function ContainerPosition(container)
    -- Forever lacks MicroMenuContainer:GetPosition.
    if HasMethod(container, "GetPosition") then
        return container:GetPosition()
    end
    -- Retail (12.1.0, 12.1.5) lacks FrameUtil.GetScreenQuadrant.
    if container and FrameUtil.GetScreenQuadrant then
        return FrameUtil.GetScreenQuadrant(container)
    end
end
Layout.ContainerPosition = ContainerPosition

-- MicroMenuMixin:Layout re-anchors the queue eye and the framerate text around
-- Blizzard's Edit Mode container using MicroMenu's orientation. Their own
-- UpdatePosition APIs take the orientation, so pass the owned one. Queue and
-- FPS stay with that container by native contract; the help button follows
-- the owned bar (Retail) or the container quadrant (Forever), as the
-- native Layout used to place it.
function Layout.AnchorCompanions(root, settings, horizontal, bar)
    local container = _G.MicroMenuContainer
    local position = ContainerPosition(container)
    if position ~= nil then
        -- Retail's MicroMenu anchors the queue eye itself; Forever has no such method.
        if type(root.UpdateQueueStatusAnchors) == "function" then
            Call(_G.QueueStatusButton, "UpdatePosition", position, horizontal)
            Call(_G.QueueStatusFrame, "UpdatePosition", position, horizontal)
        end
        local defaultPosition = EditModeSystemMixin.IsInDefaultPosition(container)
        Call(_G.FramerateFrame, "UpdatePosition", position, horizontal, defaultPosition)
    end
    -- Forever lacks MicroMenuPositionEnum (Retail only).
    local left, bottom = Quadrant(_G.MicroMenuPositionEnum and bar or container, settings)
    AnchorHelpButton(root, horizontal, left, bottom)
end

return Layout
