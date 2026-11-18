local _, NS = ...
local S = NS.Suite
local Compass = { slotWidth = 112, fallbackWidth = 32 }
NS.Compass = Compass

local HALF_ARC, TICK_MIN, TICK_MAX = 60, -90, 450
local SLOT_HEIGHT, MIN_SLOT_WIDTH = 18, 48
local SLIDE_SECONDS, PIXEL_HYSTERESIS = .05, .75
local floor, abs = math.floor, math.abs

local function SetAnchor(view, pixels)
    view.anchorPixels = pixels
    view.rail:SetPoint("LEFT", view.frame, "CENTER", pixels * view.unitsPerPixel, 0)
end

local function SlideToSample(view)
    local target, anchor = view.offsetPixels, view.anchorPixels
    if target == anchor then return end
    if anchor then
        local period = view.periodPixels
        local half = period * .5
        local delta = (target - anchor + half) % period - half
        if delta ~= 0 and abs(delta) <= view.maxSlidePixels then
            local shift = delta * view.unitsPerPixel
            if shift ~= view.slideOffset then
                view.slide:SetOffset(shift, 0)
                view.slideOffset = shift
            end
            view.slideTarget = target
            view.motion:Play()
            return
        end
    end
    SetAnchor(view, target)
end

local function FinishSlide(view)
    local target = view.slideTarget
    if not target then return end
    view.slideTarget = nil
    SetAnchor(view, target)
    SlideToSample(view)
end

function Compass.New(parent, compact, createFrame, createTexture)
    local frame = createFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame:SetClipsChildren(true)
    frame:Hide()
    local rail = createFrame("Frame", nil, frame)
    rail:EnableMouse(false)
    local motion = rail:CreateAnimationGroup()
    local slide = motion:CreateAnimation("Translation")
    slide:SetDuration(SLIDE_SECONDS)
    local baseline = compact and 3 or 6
    local base = createTexture(frame, nil, "BACKGROUND")
    base:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, baseline)
    base:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, baseline)
    base:SetHeight(1)
    base:SetColorTexture(.76, .83, .9, .24)
    local cursor = createTexture(frame, nil, "OVERLAY")
    cursor:SetPoint("BOTTOM", frame, "BOTTOM")
    cursor:SetSize(2, baseline)
    local marks, cardinals = {}, {}
    local north, east, south, west = (NS.Text("N E S W")):match("^(%S+) (%S+) (%S+) (%S+)$")
    local labels = { north or "N", east or "E", south or "S", west or "W" }
    for degree = TICK_MIN, TICK_MAX, 15 do
        local major = degree % 90 == 0
        local tick = createTexture(rail, nil, "ARTWORK")
        local height = major and 7 or 4
        if compact then height = major and 4 or 2 end
        tick:SetSize(1, height)
        tick:SetColorTexture(.85, .91, .96, major and .8 or .4)
        if major then
            local label = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetText(labels[(degree % 360) / 90 + 1])
            label:SetTextColor(.95, .97, 1)
            label:SetPoint("BOTTOM", tick, "TOP", 0, compact and 0 or 2)
            cardinals[degree / 90] = label
        end
        marks[#marks + 1] = { degree = degree, tick = tick }
    end
    local view = { frame = frame, rail = rail, motion = motion, slide = slide, cursor = cursor,
        marks = marks, cardinals = cardinals, baseline = baseline, compact = compact }
    motion:SetScript("OnFinished", function() FinishSlide(view) end)
    return view
end

function Compass.Reset(view)
    if view.slideTarget then
        view.slideTarget = nil
        view.motion:Stop()
        SetAnchor(view, view.offsetPixels)
    end
    view.offsetPixels, view.anchorPixels = nil, nil
end

function Compass.Layout(view, width, unitsPerPixel, font, color)
    if view.width ~= width or view.unitsPerPixel ~= unitsPerPixel then
        Compass.Reset(view)
        view.width, view.unitsPerPixel = width, unitsPerPixel
        -- Each 360-degree repeat occupies whole physical pixels at the seam.
        view.periodPixels = floor(width * (360 / (HALF_ARC * 2)) / unitsPerPixel + .5)
        view.pixelsPerDegree = view.periodPixels / 360
        view.maxSlidePixels = (-TICK_MIN - HALF_ARC) * view.pixelsPerDegree
        view.step = view.pixelsPerDegree * unitsPerPixel
        local height = view.compact and SLOT_HEIGHT or 34
        view.frame:SetSize(width, height)
        view.rail:SetSize((TICK_MAX - TICK_MIN) * view.step, height)
        for _, mark in ipairs(view.marks) do
            mark.tick:SetPoint("BOTTOM", view.rail, "BOTTOMLEFT", (mark.degree - TICK_MIN) * view.step, view.baseline)
        end
    end
    if view.font ~= font or not view.fontSet then
        view.font, view.fontSet = font, true
        for _, label in pairs(view.cardinals) do S.SetFont(label, font, view.compact and 10 or 12, "OUTLINE") end
    end
    if view.color ~= color or not view.colorSet then
        view.color, view.colorSet = color, true
        local r, g, b = NS.RGB(color)
        view.cursor:SetColorTexture(r, g, b, .96)
    end
end

-- Keep the anchor and the clipped labels stable while the client slides the tape.
-- New readings replace only the queued destination until the current slide ends.
function Compass.Paint(view, bearing)
    local offset = (TICK_MIN - bearing) * view.pixelsPerDegree
    local pixels = floor(offset + .5)
    local previous = view.offsetPixels
    if pixels == previous then return end
    if previous then
        local distance = abs(offset - previous)
        if distance < PIXEL_HYSTERESIS or distance > view.periodPixels - PIXEL_HYSTERESIS then return end
    end
    view.offsetPixels = pixels
    if not view.slideTarget then SlideToSample(view) end
end

local function HideSlot(button, slot)
    if slot.showing then
        Compass.Reset(slot.view)
        slot.view.frame:Hide()
        button.label:Show()
        slot.showing = nil
    end
end

function Compass.ClearSlot(button)
    local slot = button.dataCompass
    if not slot then return end
    HideSlot(button, slot)
    slot.width, slot.degrees, slot.bearing = nil, nil, nil
end

function Compass.LayoutSlot(button, available, height, inset, pixel, color)
    local slot = button.dataCompass
    if not slot then
        slot = {}
        button.dataCompass = slot
    end
    local width = available - 2 * inset
    slot.width = width >= MIN_SLOT_WIDTH and height >= SLOT_HEIGHT and width or nil
    if not slot.width then
        HideSlot(button, slot)
        return
    end
    slot.pixel, slot.font, slot.color = pixel, button.label:GetFont(), color
    if slot.view then
        Compass.Layout(slot.view, width, pixel, slot.font, color)
        if slot.showing then Compass.Paint(slot.view, slot.bearing) end
    end
end

local function WholeDegrees(bearing)
    return bearing and floor(bearing + .5) % 360 or false
end

local function DegreeText(degrees)
    return degrees and degrees .. "\194\176" or "\226\128\148"
end

function Compass.SlotText(button)
    local slot = button.dataCompass
    return DegreeText(WholeDegrees(slot and slot.bearing))
end

function Compass.PaintSlot(button, bearing, createFrame, createTexture)
    local slot = button.dataCompass
    slot.bearing = bearing
    if bearing and slot.width then
        local view = slot.view
        if not view then
            view = Compass.New(button, true, createFrame, createTexture)
            view.frame:SetPoint("CENTER", button, "CENTER")
            Compass.Layout(view, slot.width, slot.pixel, slot.font, slot.color)
            slot.view = view
        end
        Compass.Paint(view, bearing)
        if not slot.showing then
            slot.showing, slot.degrees = true, nil
            button.label:Hide()
            view.frame:Show()
        end
    else
        HideSlot(button, slot)
        local degrees = WholeDegrees(bearing)
        if degrees ~= slot.degrees then
            slot.degrees = degrees
            button.label:SetText(DegreeText(degrees))
        end
    end
end
