local _, NS = ...
local Safety, Suite = NS.Safety, NS.NS
local Layout = {}
NS.TooltipComparisonLayout = Layout

-- Use screen pixels for both measurements and placement. The main tooltip
-- can be scaled independently of the comparisons and UIParent.
local EDGE, GAP, TOLERANCE = 4, 8, 1
local screen, item, first, second = {}, {}, {}, {}

local function Header(frame, styledHeader)
    local custom, padding = styledHeader(frame)
    if custom then return custom, padding end
    local badge = Safety.Field(frame, "CompareHeader")
    if Safety.Public(badge) and Safety.Read(badge, "IsShown") == true then return badge, 0 end
end

local function Bounds(frame, rect, styledHeader)
    local x, y, width, height = Safety.Call(frame, "GetRect")
    local scale = Safety.Read(frame, "GetEffectiveScale")
    local finite = Suite.Finite
    if not (finite(x) and finite(y) and finite(width) and finite(height) and finite(scale))
        or width <= 0 or height <= 0 or scale <= 0 then return end

    rect.left, rect.bottom, rect.width = x * scale, y * scale, width * scale
    rect.right = rect.left + rect.width
    rect.top = rect.bottom + height * scale
    rect.scale, rect.cap = scale, 0
    local header, padding
    if styledHeader then header, padding = Header(frame, styledHeader) end
    if header then
        local top, headerScale = Safety.Read(header, "GetTop"), Safety.Read(header, "GetEffectiveScale")
        if finite(top) and finite(headerScale) and headerScale > 0 then
            rect.cap = math.max(0, (top + padding) * headerScale - rect.top)
            rect.top = rect.top + rect.cap
        end
    end
    rect.height = rect.top - rect.bottom
    return true
end

local function Inside(rect)
    return rect.left >= screen.left - TOLERANCE and rect.right <= screen.right + TOLERANCE
        and rect.bottom >= screen.bottom - TOLERANCE and rect.top <= screen.top + TOLERANCE
end

local function Intersects(a, b)
    return math.min(a.right, b.right) - math.max(a.left, b.left) > TOLERANCE
        and math.min(a.top, b.top) - math.max(a.bottom, b.bottom) > TOLERANCE
end

local function Beside(left, bottom, right, top, rowWidth, rowHeight, hasSecond)
    local spaceLeft, spaceRight = item.left - left - GAP, right - item.right - GAP
    local onLeft = spaceLeft > spaceRight
    local space = math.max(spaceLeft, spaceRight)
    if rowHeight <= top - bottom then
        local y = math.min(top, math.max(item.top, bottom + rowHeight))
        if rowWidth <= space then
            if not hasSecond then
                local x = onLeft and item.left - GAP - first.width or item.right + GAP
                return x, y
            end
            if onLeft then return item.left - GAP - first.width, y, item.left - GAP - rowWidth, y end
            return item.right + GAP + second.width + GAP, y, item.right + GAP, y
        end
        if hasSecond and first.width <= spaceLeft and second.width <= spaceRight then
            return item.left - GAP - first.width, y, item.right + GAP, y
        end
        if hasSecond and second.width <= spaceLeft and first.width <= spaceRight then
            return item.right + GAP, y, item.left - GAP - second.width, y
        end
    end
    if not hasSecond then return end

    local height = first.height + GAP + second.height
    if math.max(first.width, second.width) <= space and height <= top - bottom then
        local y = math.min(top, math.max(item.top, bottom + height))
        local x = item.right + GAP
        if onLeft then return item.left - GAP - first.width, y, item.left - GAP - second.width, y - first.height - GAP end
        return x, y, x, y - first.height - GAP
    end
end

local function Across(left, bottom, right, top, rowWidth, rowHeight, hasSecond)
    local above, below = top - item.top - GAP, item.bottom - bottom - GAP
    if rowWidth <= right - left and rowHeight <= math.max(above, below) then
        local x = math.min(right - rowWidth, math.max(left, item.left))
        local y = above > below and item.top + GAP + rowHeight or item.bottom - GAP
        return x, y, x + first.width + GAP, y
    end
    if not hasSecond then return end
    local columnWidth = math.max(first.width, second.width)
    if columnWidth > right - left then return end
    local columnHeight = first.height + GAP + second.height
    if columnHeight <= math.max(above, below) then
        local x = math.min(right - columnWidth, math.max(left, item.left))
        local y = above > below and item.top + GAP + columnHeight or item.bottom - GAP
        return x, y, x, y - first.height - GAP
    end
    local firstX = math.min(right - first.width, math.max(left, item.left))
    local secondX = math.min(right - second.width, math.max(left, item.left))
    if first.height <= above and second.height <= below then
        return firstX, item.top + GAP + first.height, secondX, item.bottom - GAP
    end
    if second.height <= above and first.height <= below then
        return firstX, item.bottom - GAP, secondX, item.top + GAP + second.height
    end
end

local function CanAnchor(tip)
    return Safety.CanControl(tip) and Safety.Read(tip, "IsAnchoringSecret") == false
        and Safety.Read(tip, "IsAnchoringRestricted") == false
end

local function CanMove(tip, owner, other)
    if Safety.Read(tip, "GetOwner") ~= owner or Safety.Read(tip, "GetAnchorType") ~= "ANCHOR_NONE"
        or not CanAnchor(tip) then return end
    local count = Safety.Read(tip, "GetNumPoints")
    if type(count) ~= "number" or count < 1 or count > 3 then return end
    for i = 1, count do
        local _, relative = Safety.Call(tip, "GetPoint", i)
        if not Safety.Public(relative) or relative ~= owner and (not other or relative ~= other) then return end
    end
    return true
end

local function Place(tip, owner, x, y, rect)
    local center = x + rect.width / 2
    local bodyTop = y - rect.cap
    tip:ClearAllPoints()
    -- The native manager always replaces TOP, including when it cycles an
    -- equipped item without clearing the previous layout first.
    tip:SetPoint("TOP", owner, "TOPLEFT", (center - item.left) / rect.scale, (bodyTop - item.top + item.cap) / rect.scale)
end

local function Reflow(owner, primary, secondary, headerFor)
    if not (Bounds(UIParent, screen) and Bounds(owner, item, headerFor) and Bounds(primary, first, headerFor))
        or secondary and not Bounds(secondary, second, headerFor) then return false end
    if Inside(first) and not Intersects(first, item) and (not secondary
        or Inside(second) and not Intersects(first, second) and not Intersects(second, item)) then return end

    local left, right, bottom, top = screen.left + EDGE, screen.right - EDGE, screen.bottom + EDGE, screen.top - EDGE
    local width, height = first.width, first.height
    if secondary then width, height = width + GAP + second.width, math.max(height, second.height) end
    local firstX, firstY, secondX, secondY = Beside(left, bottom, right, top, width, height, secondary ~= nil)
    if not firstX then
        firstX, firstY, secondX, secondY = Across(left, bottom, right, top, width, height, secondary ~= nil)
    end
    if not firstX or not CanAnchor(owner) or not CanMove(primary, owner, secondary)
        or secondary and not CanMove(secondary, owner, primary) then return end

    Place(primary, owner, firstX, firstY, first)
    if secondary and CanMove(secondary, owner, primary) then Place(secondary, owner, secondX, secondY, second) end
end

local manager, owner, primary, secondary, hiddenComparison, headerFor
local running, queued
local watched = setmetatable({}, { __mode = "k" })

local function ActiveComparisons()
    if not owner or not NS.DB.enabled or Suite.InCombat() then return end
    local tooltip, anchor = Safety.Field(manager, "tooltip"), Safety.Field(manager, "anchorFrame")
    return Safety.Public(tooltip) and tooltip == owner and Safety.Public(anchor) and anchor == owner
        and Safety.Read(primary, "IsShown") == true and (not secondary or Safety.Read(secondary, "IsShown") == true)
        and (not hiddenComparison or Safety.Read(hiddenComparison, "IsShown") ~= true)
end

local function OwnerVisible()
    local alpha = Safety.Read(owner, "GetAlpha")
    return type(alpha) == "number" and alpha > 0 and Safety.Read(owner, "IsShown") == true
end

local function Arrange()
    running = true
    local result = Safety.Dispatch(Reflow, owner, primary, secondary, headerFor)
    running = false
    return result
end

local function Settle()
    queued = false
    if not running and ActiveComparisons() and OwnerVisible() then Arrange() end
end

local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, Settle)
end

local function Resized(frame)
    if not running and (frame == owner or frame == primary or frame == secondary) and ActiveComparisons() then Queue() end
end

local function OwnerShown(frame)
    if frame == owner and not running and ActiveComparisons() and OwnerVisible() and Arrange() == false then Queue() end
end

local function Watch(frame, onShow)
    if watched[frame] or not Safety.HasMethod(frame, "HookScript") or not Safety.CanControl(frame) then return end
    frame:HookScript("OnSizeChanged", Resized)
    if onShow then frame:HookScript("OnShow", onShow) end
    watched[frame] = true
end

-- Repair clamped comparisons after their native anchors are set. Item post-calls
-- can run before the owner is shown, or before final lines change its size.
function Layout.Update(comparisonManager, itemTooltip, firstTooltip, secondTooltip, getHeader, firstShown, secondShown)
    if running then return end
    manager, owner, primary, secondary, hiddenComparison, headerFor = nil, nil, nil, nil, nil, nil
    if not Safety.Public(itemTooltip) or not itemTooltip or itemTooltip ~= GameTooltip and itemTooltip ~= ItemRefTooltip then return end
    if not (Safety.Public(firstShown) and firstShown == true and Safety.Public(secondShown))
        or not Safety.Public(firstTooltip) or not firstTooltip then return end
    if secondShown == true and (not Safety.Public(secondTooltip) or not secondTooltip) then return end
    manager, owner, primary, headerFor = comparisonManager, itemTooltip, firstTooltip, getHeader
    if secondShown == true then
        secondary = secondTooltip
    elseif Safety.Public(secondTooltip) then
        hiddenComparison = secondTooltip
    end
    if not ActiveComparisons() then return end
    Watch(owner, OwnerShown)
    Watch(primary)
    if secondary then Watch(secondary) end
    if not OwnerVisible() or Arrange() == false then Queue() end
end
