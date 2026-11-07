local _, NS = ...

-- Shared with MSUF Menu2. Reverse playback of the native ease-in moves from
-- the rendered pose to the destination with a fast start and a soft stop.
function NS.ConfigureDisclosure(animation)
    animation:SetDuration(0.150)
    animation:SetSmoothing("IN")
end
