local _, P = ...
local Samples = {}
P.MenuSamples = Samples

function Samples.Bags(ui)
    return P.BuildBagsMenuPreview(ui)
end

function Samples.Meter(ui, selected, setSelected)
    return P.BuildMeterMenuPreview(ui, selected, setSelected)
end
