local _, P = ...
local S = P.Suite
local Display = {}
Display.__index = Display
P.FloatingTextDisplay, S.FloatingTextDisplay = Display, Display

local NAMEPLATE, LEFT, RIGHT = 1, 2, 3
local PLATE_ROWS, SIDE_ROWS, GAP = 4, 3, 8
local PLATE_TRAVEL = 42
local POINTS = { "CENTER", "RIGHT", "LEFT" }

local function Release(self, slot)
    local anchor = slot.anchor
    local mask = self.occupied[anchor] - slot.rowBit
    self.occupied[anchor] = mask > 0 and mask or nil
    if slot.older then slot.older.newer = slot.newer else self.head[anchor] = slot.newer end
    if slot.newer then slot.newer.older = slot.older else self.tail[anchor] = slot.older end
    slot.anchor, slot.older, slot.newer = nil, nil, nil
end

local function Finished(animation)
    local self, slot = animation.display, animation.slot
    Release(self, slot)
    self.freeCount = self.freeCount + 1
    self.free[self.freeCount] = slot
    slot.playing = false
    slot.frame:Hide()
end

function Display:Clear(anchor)
    if anchor and not self.occupied[anchor] then return end
    for i = 1, #self.slots do
        local slot = self.slots[i]
        if slot.anchor and (not anchor or slot.anchor == anchor) then
            if slot.playing then slot.animation:Stop() end
            Finished(slot.animation)
        end
    end
end

local function NewText(frame)
    local text = S.CreateFontString(frame, nil, "OVERLAY")
    -- A single anchor lets the font string size itself, including secret digits.
    text:SetPoint("CENTER", frame, "CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text:SetNonSpaceWrap(false)
    return text
end

local function NewSlot(self, parent, index)
    local frame = S.CreateFrame("Frame", nil, parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 5)
    frame:EnableMouse(false)
    frame:SetClipsChildren(false)
    local normal, critical = NewText(frame), NewText(frame)
    critical:Hide()
    local animation = frame:CreateAnimationGroup()
    local move, fade = animation:CreateAnimation("Translation"), animation:CreateAnimation("Alpha")
    animation.display = self
    animation:SetScript("OnFinished", Finished)
    move:SetOrder(1)
    fade:SetOrder(1)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    local slot = {
        frame = frame, normal = normal, critical = critical, text = normal, placement = NAMEPLATE,
        animation = animation, move = move, fade = fade, index = index,
    }
    animation.slot = slot
    frame:Hide()
    return slot
end

local function NewAnchor(parent)
    local frame = S.CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    return frame
end

function Display.New(parent, capacity)
    local self = setmetatable({ slots = {}, occupied = {}, head = {}, tail = {}, cursor = 0, parent = parent,
        free = {}, freeCount = capacity, recycleCursor = 0,
        sides = { [LEFT] = NewAnchor(parent), [RIGHT] = NewAnchor(parent) },
        placements = { {}, {}, {} }, colors = { hit = {}, avoid = {}, gain = {}, power = {}, combat = {} },
        routes = {}, enabled = {},
    }, Display)
    for i = 1, capacity do
        local slot = NewSlot(self, parent, i)
        self.slots[i], self.free[capacity - i + 1] = slot, slot
    end
    return self
end

local function StylePlacement(plan, side, height, distance, style)
    plan.rows = side == NAMEPLATE and PLATE_ROWS or SIDE_ROWS
    plan.dy = style == 2 and -distance or distance
    plan.dx = style == 3 and (side == LEFT and -distance or distance) * .65 or 0
    -- Reserve the full swept height so independent animations never cross.
    plan.step = height + distance + GAP
end

local function StyleRoutes(self, c)
    local route, enabled, colors = self.routes, self.enabled, self.colors
    route.hit, route.avoid = c.hitSide, c.avoidSide
    route.gain, route.power, route.combat = c.gainSide + 1, c.powerSide + 1, c.combatSide + 1
    enabled.hit, enabled.avoid, enabled.xp = c.showHits, c.showAvoidance, c.showXP
    enabled.power, enabled.reputation, enabled.honor = c.showPower, c.showReputation, c.showHonor
    enabled.combat = c.showCombatState
    local hit, avoid, gain, power, combat = colors.hit, colors.avoid, colors.gain, colors.power, colors.combat
    hit[1], hit[2], hit[3] = S.RGB(c.hitColor)
    avoid[1], avoid[2], avoid[3] = S.RGB(c.avoidColor)
    gain[1], gain[2], gain[3] = S.RGB(c.gainColor)
    power[1], power[2], power[3] = S.RGB(c.powerColor)
    combat[1], combat[2], combat[3] = S.RGB(c.combatColor)
end

function Display:Configure(c, font)
    self:Clear()
    StyleRoutes(self, c)
    local critSize = c.fontSize * c.critScale / 100
    local height = critSize * 1.5
    self.offset, self.height = c.offset, height
    StylePlacement(self.placements[NAMEPLATE], NAMEPLATE, height, PLATE_TRAVEL, 1)
    for side = LEFT, RIGHT do
        StylePlacement(self.placements[side], side, height, c.travel, c.scrollStyle)
        local anchor = self.sides[side]
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", self.parent, "CENTER", side == LEFT and -c.sideOffset or c.sideOffset, c.screenY)
    end
    for _, slot in ipairs(self.slots) do
        slot.positionAnchor, slot.positionRow, slot.motion = nil, nil, nil
        slot.normalColor, slot.criticalColor = nil, nil
        slot.frame:ClearAllPoints()
        slot.frame:SetSize(1, height)
        S.SetFont(slot.normal, font, c.fontSize, "OUTLINE")
        S.SetFont(slot.critical, font, critSize, "OUTLINE")
        slot.move:SetDuration(c.duration)
        slot.fade:SetStartDelay(c.duration * .45)
        slot.fade:SetDuration(c.duration * .55)
    end
end

function Display:NeedsPlate()
    return self.enabled.hit and self.routes.hit == NAMEPLATE
        or self.enabled.avoid and self.routes.avoid == NAMEPLATE
end

local function TakeSlot(self, anchor, rows)
    local mask = self.occupied[anchor] or 0
    local row, bit = 0, 1
    while mask % 2 == 1 do
        row, bit, mask = row + 1, bit * 2, math.floor(mask / 2)
    end
    local slot
    if row == rows then
        slot = self.head[anchor]
        row, bit = slot.row, slot.rowBit
    elseif self.freeCount > 0 then
        -- Keep other lanes intact while the pool still has idle slots.
        slot = self.free[self.freeCount]
        self.freeCount = self.freeCount - 1
    else
        self.recycleCursor = self.recycleCursor % #self.slots + 1
        slot = self.slots[self.recycleCursor]
    end
    self.cursor = slot.index
    local wasActive = slot.anchor ~= nil
    if wasActive then
        if slot.playing then slot.animation:Stop() end
        Release(self, slot)
    end
    self.occupied[anchor] = (self.occupied[anchor] or 0) + bit
    slot.anchor, slot.row, slot.rowBit = anchor, row, bit
    local tail = self.tail[anchor]
    slot.older = tail
    if tail then tail.newer = slot else self.head[anchor] = slot end
    self.tail[anchor] = slot
    return slot, wasActive
end

local function Position(self, slot, placement, plan)
    if slot.positionAnchor ~= slot.anchor or slot.positionRow ~= slot.row then
        local frame = slot.frame
        frame:ClearAllPoints()
        if placement == NAMEPLATE then
            frame:SetPoint("BOTTOM", slot.anchor, "TOP", 0, self.offset + slot.row * plan.step)
        else
            local y = (slot.row - (plan.rows - 1) / 2) * plan.step - plan.dy / 2
            frame:SetPoint(POINTS[placement], slot.anchor, "CENTER", 0, y)
        end
        slot.positionAnchor, slot.positionRow = slot.anchor, slot.row
    end
    if slot.motion ~= placement then
        slot.motion = placement
        slot.move:SetOffset(plan.dx, plan.dy)
    end
    if slot.placement ~= placement then
        slot.placement = placement
        local point = POINTS[placement]
        slot.normal:ClearAllPoints()
        slot.normal:SetPoint(point, slot.frame, point)
        slot.critical:ClearAllPoints()
        slot.critical:SetPoint(point, slot.frame, point)
    end
end

-- A format consumes its amount only at the FontString sink. The caller may
-- pass a secret value through this path without inspecting it.
function Display:Show(route, critical, format, amount, plate, stationary)
    local placement = self.routes[route]
    local anchor = placement == NAMEPLATE and plate or self.sides[placement]
    if not anchor then return end
    local plan = self.placements[placement]
    local slot, wasActive = TakeSlot(self, anchor, plan.rows)
    Position(self, slot, placement, plan)
    local text = critical and slot.critical or slot.normal
    if slot.text ~= text then
        slot.text:Hide()
        text:Show()
        slot.text = text
    end
    local colorKey = critical and "criticalColor" or "normalColor"
    if slot[colorKey] ~= route then
        local color = self.colors[route]
        text:SetTextColor(color[1], color[2], color[3])
        slot[colorKey] = route
    end
    if format then text:SetFormattedText(format, amount) else text:SetText(amount) end
    if not wasActive then slot.frame:Show() end
    slot.playing = not stationary
    if slot.playing then slot.animation:Play() end
    return slot
end
