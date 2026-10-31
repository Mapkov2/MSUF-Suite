local _, P = ...
local S, B = P.Suite, P.PlanningTools.Board
-- Slim scroll bars that ease the wheel toward its target like MSUF's menu.
-- Only a moving or dragged scroller has an OnUpdate script. It clears on
-- arrival and on Stop, which the window calls when it hides, so a closed or
-- combat-hidden planner runs no code at all.
local SPEED, MAX_ELAPSED, EPSILON, MIN_THUMB = 14, .05, .45, 28
local Scroller = {}
Scroller.__index = Scroller

local function Clamp(self, value)
    return math.max(0, math.min(self.max, value))
end

local function Thumb(self)
    local bar, thumb = self.bar, self.thumb
    local height = bar:GetHeight()
    local size = math.max(MIN_THUMB, math.min(height, height * self.view / math.max(self.view + self.max, 1)))
    thumb:SetHeight(size)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, self.max > 0 and -(self.offset / self.max) * math.max(0, height - size) or 0)
end

function Scroller:Stop()
    self.target, self.dragY = nil, nil
    self.bar:SetScript("OnUpdate", nil)
end

function Scroller:Apply(offset)
    self.offset = Clamp(self, offset)
    Thumb(self)
    self.apply(self.owner, self.offset)
end

function Scroller:SetOffset(offset)
    self:Stop()
    self:Apply(offset)
end

-- Back to the top without painting; the next draw applies the offset.
function Scroller:Reset()
    self:Stop()
    self.offset = 0
end

local function Ease(bar, elapsed)
    local self = bar.scroller
    local target = Clamp(self, self.target or self.offset)
    local delta = target - self.offset
    if math.abs(delta) <= EPSILON then return self:SetOffset(target) end
    self:Apply(self.offset + delta * math.min(1, math.min(elapsed, MAX_ELAPSED) * SPEED))
end

function Scroller:ScrollTo(target)
    target = Clamp(self, target)
    if B.Reduced() or math.abs(target - self.offset) <= EPSILON then return self:SetOffset(target) end
    self.target, self.dragY = target, nil
    self.bar:SetScript("OnUpdate", Ease)
end

function Scroller:Wheel(delta)
    if self.max > 0 then self:ScrollTo((self.target or self.offset) - delta * self.step) end
end

function Scroller:SetRange(content, view)
    self.view, self.max = view, math.max(0, content - view)
    if self.max == 0 then self:Stop() end
    self.bar:SetShown(self.max > 0)
    if self.target then self.target = Clamp(self, self.target) end
    self.offset = Clamp(self, self.offset)
    Thumb(self)
end

local function CursorY(bar)
    local _, y = GetCursorPosition()
    return y / bar:GetEffectiveScale()
end

local function Drag(bar)
    local self = bar.scroller
    if not IsMouseButtonDown("LeftButton") or not self.dragY then return self:Stop() end
    local travel = math.max(1, bar:GetHeight() - self.thumb:GetHeight())
    self:Apply(self.dragStart - (CursorY(bar) - self.dragY) * self.max / travel)
end

local function Press(bar, button)
    local self = bar.scroller
    if button ~= "LeftButton" or self.max <= 0 then return end
    self.target, self.dragY, self.dragStart = nil, CursorY(bar), self.offset
    bar:SetScript("OnUpdate", Drag)
end

local function Release(bar)
    if bar.scroller.dragY then bar.scroller:Stop() end
end

local function Hover(bar, hover)
    B.Tint(bar.scroller.thumb, hover and "coreRaised" or "coreRim", hover and .9 or .68,
        hover and "pillEdgeHover" or "pillEdge")
    B.Tint(bar.scroller.track, "borderSoft", hover and 1 or .7)
end

-- owner reaches apply(owner, offset); step is the distance of one wheel notch.
function B.Scroller(owner, parent, apply, step)
    local bar = S.CreateFrame("Frame", nil, parent)
    bar:SetWidth(12)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    local track = B.Texture(bar, "BACKGROUND", "borderSoft", .7, "border")
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetWidth(2)
    local thumb = B.Texture(bar, "OVERLAY", "coreRim", .68, "pillEdge")
    thumb:SetWidth(5)
    local self = setmetatable({ owner = owner, bar = bar, track = track, thumb = thumb, apply = apply, step = step,
        offset = 0, max = 0, view = 0 }, Scroller)
    bar.scroller = self
    bar:SetScript("OnMouseDown", Press)
    bar:SetScript("OnMouseUp", Release)
    bar:SetScript("OnEnter", function() Hover(bar, true) end)
    bar:SetScript("OnLeave", function() Hover(bar, false) end)
    bar:SetScript("OnMouseWheel", function(_, delta) self:Wheel(delta) end)
    bar:Hide()
    return self
end
