local _, P = ...
local S, Compass = P.Suite, P.NS.Compass
local Heading = S.CompassHeading
local Slots = {}
P.DataTextCompass = Slots

local places = {}
local preview

local function Reset(button)
    local slot = button.dataCompass
    if slot and slot.showing then Compass.Reset(slot.view) end
end

local function Paint(_, bearing)
    for button in pairs(places) do Compass.PaintSlot(button, bearing, S.CreateFrame, S.CreateTexture) end
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
            Paint(Slots, 90)
            Heading.Watch(Slots)
        else
            Paint(Slots, Heading.Read())
            Heading.Watch(Slots, Paint)
        end
    else
        Heading.Watch(Slots)
    end
end
