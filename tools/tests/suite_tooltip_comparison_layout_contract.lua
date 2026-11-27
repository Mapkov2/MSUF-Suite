local root = assert(arg[1])
local private = { DB = { enabled = true }, NS = {} }
local secret = {}
local combat = false
issecretvalue = function(value) return rawequal(value, secret) end
securecallfunction = function(callback, ...) return callback(...) end
private.NS.Finite = function(value)
    return not issecretvalue(value) and type(value) == "number" and math.abs(value) < math.huge
end
private.NS.InCombat = function() return combat end
assert(loadfile(root .. "/MSUF_Suite/Appearance/Safety.lua"))("MSUF_Suite", private)
assert(loadfile(root .. "/MSUF_Suite_Tooltips/TooltipComparisonLayout.lua"))("MSUF_Suite_Tooltips", private)
local Layout = private.TooltipComparisonLayout

local pending
C_Timer = { After = function(_, job)
    assert(not pending, "comparison updates queued duplicate timers")
    pending = job
end }
local function Flush()
    local job = assert(pending, "comparison did not schedule its settlement")
    pending = nil
    job()
end

local function Frame(x, y, w, h, scale, cap)
    local frame = { x = x, y = y, w = w, h = h, scale = scale, cap = cap or 0, shown = true, writes = 0 }
    function frame:IsShown() return self.shown end
    function frame:GetAlpha() return self.alpha or 1 end
    function frame:GetNumPoints() return #self.points end
    function frame:GetPoint(index) return "TOP", self.points[index] end
    function frame:HookScript(script, callback)
        if script == "OnShow" then
            assert(not self.onShow)
            self.onShow = callback
        else
            assert(script == "OnSizeChanged" and not self.resized)
            self.resized = callback
        end
    end
    function frame:Show()
        self.shown = true
        if self.onShow then self.onShow(self) end
    end
    function frame:IsForbidden() return self.forbidden end
    function frame:IsProtected() return self.protected == true, self.protected == true end
    function frame:IsAnchoringSecret() return self.secretAnchor == true end
    function frame:IsAnchoringRestricted() return self.restricted == true end
    function frame:GetOwner() return self.owner end
    function frame:GetAnchorType() return "ANCHOR_NONE" end
    function frame:GetEffectiveScale() return self.scale end
    function frame:GetRect()
        if self.missingBounds then return end
        local s = self.scale
        return self.x / s, self.y / s, self.w / s, self.h / s
    end
    function frame:GetTop() return (self.y + self.h + self.cap) / self.scale end
    function frame:ClearAllPoints() self.cleared = true end
    function frame:SetPoint(point, relativeTo, relativePoint, left, top)
        assert(self.owner and self.cleared, "wrote to the main tooltip or left conflicting native points")
        assert(point == "TOP" and relativeTo == self.owner and relativePoint == "TOPLEFT", "invalid comparison anchor")
        self.cleared = false
        self.writes = self.writes + 1
        self.points = { relativeTo }
        self.x = relativeTo.x + left * self.scale - self.w / 2
        self.y = relativeTo.y + relativeTo.h + top * self.scale - self.h
        if self.resized then self.resized(self) end
    end
    return frame
end

local manager, item, first, second
local function Setup(screenWidth, screenHeight, itemX, itemY, itemWidth, itemHeight)
    UIParent = Frame(6, 9, screenWidth, screenHeight, 0.9)
    item = Frame(itemX, itemY, itemWidth, itemHeight, 1.2, 15)
    first = Frame(0, 0, 350, 265, 0.8, 40)
    second = Frame(0, 0, 350, 242, 1.1, 24)
    first.owner, second.owner = item, item
    GameTooltip = item
    manager = { tooltip = item, anchorFrame = item }
end

local function Header(frame) return frame, 0 end
local function Update() Layout.Update(manager, item, first, second, Header, first.shown, second.shown) end
local function Right(frame) return frame.x + frame.w end
local function Top(frame) return frame.y + frame.h + frame.cap end
local function Intersects(a, b)
    return math.min(Right(a), Right(b)) > math.max(a.x, b.x)
        and math.min(Top(a), Top(b)) > math.max(a.y, b.y)
end
local function Inside(frame)
    return frame.x >= UIParent.x and Right(frame) <= Right(UIParent)
        and frame.y >= UIParent.y and Top(frame) <= Top(UIParent)
end
local function AssertRepaired(message)
    assert(first.writes == 1 and second.writes == 1 and item.writes == 0, "comparison placement failed: " .. message)
    assert(Inside(first) and Inside(second), "comparison clipped: " .. message)
    assert(not Intersects(first, second) and not Intersects(first, item)
        and not Intersects(second, item), "comparison overlapped: " .. message)
end

-- The native right-side chain has two horizontally clamped frames at the edge,
-- including after appended item details make the shared tooltip wider.
local function NativeRight()
    second.x = math.min(Right(item), Right(UIParent) - second.w)
    first.x = math.min(Right(second), Right(UIParent) - first.w)
    first.y, second.y = item.y + item.h - first.h, item.y + item.h - second.h
    first.points, second.points = { item, second }, { item, item }
end

local function NativeSingleRight()
    first.x = math.min(Right(item), Right(UIParent) - first.w)
    first.y = item.y + item.h - first.h
    first.points = { item, item }
    second.shown = false
end

local function AssertSingleRepaired(message)
    assert(first.writes == 1 and second.writes == 0 and item.writes == 0, "single comparison placement failed: " .. message)
    assert(Inside(first) and not Intersects(first, item), "single comparison clipped or overlapped: " .. message)
end

Setup(1632, 906, 1310, 60, 325, 550)
NativeSingleRight()
assert(Intersects(first, item), "fixture did not reproduce the Guild News overlap")
Update()
AssertSingleRepaired("one equipped item at the right edge")
assert(Right(first) < item.x and not pending, "single comparison missed the available space on the left")
Update()
assert(first.writes == 1, "a settled single comparison was reanchored")

Setup(1632, 906, 1310, 60, 325, 550)
for _ = 1, 3 do
    NativeSingleRight()
    item.shown, first.writes = false, 0
    Layout.Update(manager, item, first, second, Header, true, nil)
    assert(first.writes == 0, "anchored before the main item tooltip was shown")
    item:Show()
    AssertSingleRepaired("Guild News rebuilds and displays the item after the native comparison callback")
    Flush()
    assert(first.writes == 1, "settlement moved the comparison again after OnShow")
end

NativeSingleRight()
item.shown, first.writes = false, 0
Update()
second.shown = true
item:Show()
Flush()
assert(first.writes == 0 and second.writes == 0, "stale single comparison moved after the second one appeared")

Setup(1632, 906, 1310, 60, 325, 550)
NativeSingleRight()
item.shown = false
Update()
item.missingBounds = true
item:Show()
assert(first.writes == 0, "OnShow used unsettled geometry")
item.missingBounds = false
Flush()
AssertSingleRepaired("the initial OnShow had no geometry")

Setup(680, 1050, 35, 660, 585, 290)
NativeSingleRight()
Update()
AssertSingleRepaired("a narrow viewport required a single comparison below")
assert(Top(first) < item.y, "single comparison overlapped the item instead of moving below")

Setup(1600, 900, 200, 360, 450, 280)
NativeSingleRight()
Update()
assert(first.writes == 0 and not pending, "a valid single comparison was reanchored")
item.w = 1250
NativeSingleRight()
item.resized(item)
Flush()
AssertSingleRepaired("the item gained width after Blizzard positioned its comparison")

Setup(1632, 906, 1310, 60, 325, 550)
NativeSingleRight()
first.points = { UIParent }
Update()
assert(first.writes == 0 and not pending, "single comparison replaced an external anchor")
NativeSingleRight()
item.shown = false
Update()
item.shown = true
first.shown = false
Flush()
assert(first.writes == 0, "closing the single comparison did not cancel its pending reflow")

Setup(1280, 900, 146, 426, 790, 300)
NativeRight()
assert(first.x == second.x and Intersects(first, second), "fixture did not reproduce the same-edge collision")
Update()
assert(not pending, "settled comparisons waited until another frame to separate")
AssertRepaired("two equally wide comparisons at the right edge")
assert(Top(first) < item.y and Top(second) < item.y, "comparison row did not fit below the wide tooltip")
Update()
assert(first.writes == 1 and second.writes == 1, "a settled comparison was reanchored")

Setup(1280, 900, 146, 250, 745, 390)
NativeRight()
Update()
AssertRepaired("two comparisons stacked in the only available side")
assert(first.x == second.x and Top(second) < first.y, "stack did not reserve room for both comparison headers")

Setup(1280, 900, 381, 300, 518, 410)
NativeRight()
Update()
AssertRepaired("two comparisons fitted on opposite sides")
assert(Right(first) < item.x and second.x > Right(item), "available side columns were not used")

Setup(1920, 900, 1100, 400, 460, 360)
NativeRight()
Update()
AssertRepaired("the opposite side had room for the native row")
assert(Right(second) < first.x and Right(first) < item.x, "room for a horizontal row on the left was missed")

Setup(680, 1050, 35, 660, 585, 290)
NativeRight()
Update()
AssertRepaired("a narrow viewport required a column below the item")
assert(math.abs(first.x - second.x) < 0.0001 and Top(first) < item.y and Top(second) < first.y,
    "comparisons did not form a safe column")

Setup(1600, 900, 200, 360, 450, 280)
NativeRight()
Update()
assert(first.writes == 0 and second.writes == 0 and not pending, "a valid native chain did work")
item.w = 1050
NativeRight()
item.resized(item)
first.resized(first)
Flush()
AssertRepaired("late width growth before settlement")
assert(not pending, "moving a comparison scheduled another settlement")

Setup(1280, 900, 146, 426, 790, 300)
NativeRight()
local function Delay()
    second.missingBounds = true
    Update()
    second.missingBounds = false
end
Delay()
assert(first.writes == 0 and second.writes == 0, "moved a comparison before its geometry settled")
Flush()
AssertRepaired("geometry became available on the next frame")

Setup(1280, 900, 146, 426, 790, 300)
NativeRight()
Delay()
second.shown = false
Flush()
assert(first.writes == 0 and second.writes == 0, "hiding a comparison did not cancel a pending reflow")
second.shown = true
Delay()
manager.tooltip = Frame(0, 0, 400, 400, 1)
Flush()
assert(first.writes == 0 and second.writes == 0, "switching the tooltip owner did not cancel a pending reflow")
manager.tooltip = item
manager.anchorFrame = Frame(0, 0, 400, 400, 1)
Update()
assert(not pending and first.writes == 0, "an embedded or externally anchored comparison was moved")
manager.anchorFrame = item
Delay()
combat = true
Flush()
Update()
assert(not pending and first.writes == 0 and second.writes == 0, "comparison anchoring ran at the combat boundary")
combat = false
Delay()
private.DB.enabled = false
Flush()
assert(first.writes == 0 and second.writes == 0, "disabling the addon did not cancel the pending reflow")
private.DB.enabled = true
Delay()
Layout.Update()
Flush()
assert(first.writes == 0 and second.writes == 0, "the previous pair was moved after the native pair was cleared")

for _, state in ipairs({ "forbidden", "protected", "restricted", "secretAnchor" }) do
    second[state] = true
    Update()
    if pending then Flush() end
    assert(first.writes == 0 and second.writes == 0, "partially moved a comparison marked " .. state)
    second[state] = nil
end
second.points = { UIParent }
Update()
assert(first.writes == 0 and second.writes == 0, "replaced an external addon's anchor")
NativeRight()
function second:GetRect() return secret, self.y, self.w, self.h end
Update()
Flush()
assert(first.writes == 0 and second.writes == 0 and not pending, "used secret geometry or retried without an event")
function second:GetRect() return nil end
Update()
Flush()
assert(first.writes == 0 and second.writes == 0 and not pending, "used missing geometry or retried without an event")

print("item comparison reflow: single and dual edge collisions, native positions, visibility and safety passed")
