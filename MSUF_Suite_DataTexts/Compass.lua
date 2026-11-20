local _, P = ...
local S, Compass = P.Suite, P.NS.Compass
local Heading = S.CompassHeading
local Slots = {}
P.DataTextCompass = Slots

local places, markerViews = {}, {}
local preview

local function Reset(button)
    local slot = button.dataCompass
    if slot and slot.showing then Compass.Reset(slot.view) end
end

local function MarkerView(slot)
    local view = slot.width and slot.view
    if view and view.step and view.step > 0 then return view end
end

local function PublishMarkerViews()
    local count, changed = 0, false
    for button in pairs(places) do
        local slot = button.dataCompass
        local view = not preview and MarkerView(slot) or nil
        local step = view and view.step
        if view then
            count = count + 1
            if markerViews[count] ~= view or slot.markerStep ~= step then changed = true end
            markerViews[count] = view
        end
        slot.markerView, slot.markerStep = view, step
    end
    if #markerViews > count then
        for i = #markerViews, count + 1, -1 do markerViews[i] = nil end
        changed = true
    end
    if not changed then return end
    S.CompassMarkerViews = count > 0 and markerViews or nil
    if count == 0 then S.CompassMarkerBearing = nil end
    local callback = S.CompassMarkerViewsChanged
    if callback then S.Dispatch(callback) end
end

local function Paint(_, bearing, binding)
    S.CompassMarkerBearing = not preview and bearing or nil
    local checkViews = not (binding or preview)
    local changed = false
    for button in pairs(places) do
        Compass.PaintSlot(button, bearing, S.CreateFrame, S.CreateTexture)
        if checkViews and not changed then
            -- Fit bars can change a slot's layout between Bind calls, and a
            -- newly eligible slot may get its first tape on this very sample.
            local slot = button.dataCompass
            local view = MarkerView(slot)
            changed = view ~= slot.markerView or view ~= nil and view.step ~= slot.markerStep
        end
    end
    if changed then PublishMarkerViews() end
end

-- Targets belong to DataTexts' reusable lists. Keep only the currently
-- visible buttons and stop in-flight motion as soon as a bar stops sampling.
function Slots.Bind(targets)
    for button in pairs(places) do places[button] = false end
    for i = 1, targets and #targets or 0 do places[targets[i]] = true end
    for button, active in pairs(places) do
        if not active then
            places[button] = nil
            Reset(button)
            local slot = button.dataCompass
            if slot then slot.markerView, slot.markerStep = nil, nil end
        end
    end
    local editing = S.editMode == true
    if preview ~= editing then
        preview = editing
        for button in pairs(places) do Reset(button) end
    end
    if next(places) then
        if not P.NS.InCombat() then
            for button in pairs(places) do Compass.PrepareSlot(button, S.CreateFrame, S.CreateTexture) end
        end
        if editing then
            Paint(Slots, 90, true)
            Heading.Watch(Slots)
        else
            Paint(Slots, Heading.Read(), true)
            Heading.Watch(Slots, Paint)
        end
    else
        Heading.Watch(Slots)
    end
    PublishMarkerViews()
end
