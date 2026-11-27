local _, P = ...
-- Pixel-perfect snapping for the Suite's movable previews, by the rule MSUF
-- Edit Mode uses for frames (Shell/EditMode/MSUF_EditMode_Layout_Snap.lua):
-- on each axis the dragged region's three edges (min, center, max) are tried
-- against the three edges of every target and against fixed lines; the
-- nearest pair within the threshold wins, and a one-pixel guide marks the
-- edge it met. Distances are screen units, so snapping feels the same at
-- every preview zoom. Offsets come back as whole units of the region's own
-- scale: the drag shows exactly the value the page stores. Holding Alt places
-- freely. A page hands its kit `snap = function(...) return snapper:Apply(...) end`
-- and calls Begin when a drag starts moving and End when it ends.
local Snap = {}
P.PreviewSnap = Snap
local abs, floor = math.abs, math.floor
local Public = P.Suite.Public
local EMPTY = {}
local THRESHOLD = 8
local GUIDE_ALPHA = 0.9
local GUIDE_LEVEL = 40
local STATE_KEY = "MSUF_Suite_PreviewSnap"

-- One switch for every Suite preview, kept with the menu's persistent state.
local function State() return P.Suite.HostBridge.GetPersistentMenuState(P.M, STATE_KEY) end
function Snap.Enabled() return State().off ~= true end
function Snap.SetEnabled(on) State().off = not on or nil end

local function Round(value) return value >= 0 and floor(value + 0.5) or -floor(0.5 - value) end
Snap.Round = Round

-- A shown region's rectangle in screen units (its rect times its effective scale).
local function ScreenRect(region)
    local visible = region:IsVisible()
    if not (Public(visible) and visible) then return nil end
    local left, bottom, width, height = region:GetRect()
    local scale = region:GetEffectiveScale()
    if not (Public(left) and Public(bottom) and Public(width) and Public(height) and Public(scale)) then return nil end
    if not left or width <= 0 or height <= 0 then return nil end
    return left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale
end
Snap.ScreenRect = ScreenRect

-- True when frame moves with region: it is region, lies inside it or is
-- anchored to it, directly or through other regions below root. cache keeps
-- one drag's answers; a frame under test counts as fixed, which ends cycles.
local function MovesWith(frame, region, root, cache)
    if not frame or frame == root then return false end
    if frame == region then return true end
    local known = cache[frame]
    if known ~= nil then return known end
    cache[frame] = false
    local result = MovesWith(frame:GetParent(), region, root, cache)
    for index = 1, frame:GetNumPoints() do
        if result then break end
        local _, relative = frame:GetPoint(index)
        result = MovesWith(relative, region, root, cache)
    end
    cache[frame] = result
    return result
end

local function Inside(frame, root)
    while frame do
        if frame == root then return true end
        frame = frame:GetParent()
    end
    return false
end

-- The candidates a drag of region can meet: shown, inside root and not
-- carried along by the drag.
function Snap.Targets(region, candidates, root)
    local targets, cache = {}, {}
    for _, candidate in ipairs(candidates) do
        if candidate ~= region and Inside(candidate, root) and ScreenRect(candidate)
            and not MovesWith(candidate, region, root, cache) then
            targets[#targets + 1] = candidate
        end
    end
    return targets
end

local Snapper = {}
Snapper.__index = Snapper

-- opts: layer             the frame the guides are drawn in (it clips them)
--       targets(region)   regions to snap against (Snap.Targets filters a list)
--       lines(region, add) calls add(x, y) for fixed screen lines; nil = none on that axis
function Snap.New(opts)
    return setmetatable({ opts = opts, xs = {}, ys = {}, guides = {} }, Snapper)
end

local function AddEdges(list, low, high)
    local count = #list
    list[count + 1], list[count + 2], list[count + 3] = low, (low + high) / 2, high
end

-- Captures where region starts and the edges it may meet.
function Snapper:Begin(region)
    local xs, ys = self.xs, self.ys
    for index = #xs, 1, -1 do xs[index] = nil end
    for index = #ys, 1, -1 do ys[index] = nil end
    self.active = false
    self.lastDX, self.lastDY, self.lastScale = nil, nil, nil
    if not Snap.Enabled() then return end
    local left, bottom, right, top = ScreenRect(region)
    if not left then return end
    self.left, self.bottom, self.right, self.top = left, bottom, right, top
    for _, target in ipairs(self.opts.targets(region) or EMPTY) do
        local l, b, r, t = ScreenRect(target)
        if l then
            AddEdges(xs, l, r)
            AddEdges(ys, b, t)
        end
    end
    if self.opts.lines then
        self.opts.lines(region, function(x, y)
            if x then xs[#xs + 1] = x end
            if y then ys[#ys + 1] = y end
        end)
    end
    self.active = #xs > 0 or #ys > 0
end

-- The shift (screen units) that puts the nearest of the moving edges low,
-- center and high on a target edge, and that edge; nil beyond the threshold.
local function Nearest(low, high, list)
    local center = (low + high) / 2
    local best, shift, edge = THRESHOLD + 0.001, nil, nil
    for index = 1, #list do
        local target = list[index]
        local distance = target - low
        if abs(distance) < best then best, shift, edge = abs(distance), distance, target end
        distance = target - center
        if abs(distance) < best then best, shift, edge = abs(distance), distance, target end
        distance = target - high
        if abs(distance) < best then best, shift, edge = abs(distance), distance, target end
    end
    return shift, edge
end

local function GuideFrame(self)
    local layer, frame = self.opts.layer, self.frame
    if not frame then
        frame = CreateFrame("Frame", nil, layer)
        frame:SetAllPoints(layer)
        self.frame = frame
    end
    local level = layer:GetFrameLevel() + GUIDE_LEVEL
    if frame:GetFrameLevel() ~= level then frame:SetFrameLevel(level) end
    return frame
end

-- One physical pixel wide, on the pixel grid, at any UI scale and zoom.
local function PlaceGuide(guides, index, frame, edge, origin, scale, pixel)
    local guide = guides[index]
    if not edge then
        if guide and guide.previewOffset ~= nil then
            guide.previewOffset = nil
            guide:Hide()
        end
        return
    end
    if not guide then
        guide = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        guides[index] = guide
    end
    local offset = floor(edge / pixel + 0.5) * pixel / scale - origin
    local thickness = pixel / scale
    local color = P.T.colors.accent or P.T.colors.text
    local r, g, b = color[1], color[2], color[3]
    if guide.previewOffset == offset and guide.previewThickness == thickness
        and guide.previewR == r and guide.previewG == g and guide.previewB == b then return end
    guide.previewOffset, guide.previewThickness = offset, thickness
    guide.previewR, guide.previewG, guide.previewB = r, g, b
    guide:SetColorTexture(r, g, b, GUIDE_ALPHA)
    guide:ClearAllPoints()
    if index == 1 then
        guide:SetPoint("TOPLEFT", frame, "TOPLEFT", offset, 0)
        guide:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, 0)
        guide:SetWidth(thickness)
    else
        guide:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, offset)
        guide:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, offset)
        guide:SetHeight(thickness)
    end
    guide:Show()
end

-- Runs every drag frame: guide 1 is the vertical line, guide 2 the horizontal one.
function Snapper:ShowGuides(x, y)
    if x or y then
        local frame = GuideFrame(self)
        local scale = frame:GetEffectiveScale()
        local left, bottom = frame:GetRect()
        if Public(scale) and Public(left) and Public(bottom) and left and bottom and scale > 0 then
            local pixel = PixelUtil.GetPixelToUIUnitFactor()
            PlaceGuide(self.guides, 1, frame, x, left, scale, pixel)
            PlaceGuide(self.guides, 2, frame, y, bottom, scale, pixel)
            return
        end
    end
    PlaceGuide(self.guides, 1)
    PlaceGuide(self.guides, 2)
end

-- dx, dy: the drag's offset in region units; scale: screen units per unit.
-- Returns the snapped offset in whole units.
function Snapper:Apply(dx, dy, scale)
    local edgeX, edgeY
    if self.active and not IsAltKeyDown() and Public(scale) and scale and scale > 0 then
        if dx ~= self.lastDX or scale ~= self.lastScale then
            local move = dx * scale
            self.shiftX, self.edgeX = Nearest(self.left + move, self.right + move, self.xs)
        end
        if dy ~= self.lastDY or scale ~= self.lastScale then
            local move = dy * scale
            self.shiftY, self.edgeY = Nearest(self.bottom + move, self.top + move, self.ys)
        end
        self.lastDX, self.lastDY, self.lastScale = dx, dy, scale
        edgeX, edgeY = self.edgeX, self.edgeY
        if self.shiftX then dx = dx + self.shiftX / scale end
        if self.shiftY then dy = dy + self.shiftY / scale end
    end
    self:ShowGuides(edgeX, edgeY)
    return Round(dx), Round(dy)
end

function Snapper:End()
    self.active = false
    for _, guide in ipairs(self.guides) do guide:Hide() end
end
