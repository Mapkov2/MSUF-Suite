local _, NS = ...

-- Native window render trees can draw above same-stratum UIParent siblings.
-- Raise only our veils to the dialog floor, retaining higher native strata.
-- Native rank/level remain separate for window overlap ordering.
local Layers = {}
NS.WindowFocusLayers = Layers

function Layers.Prepare(state)
    state.paintRank = math.max(5, state.rank)
    state.paintStrata = state.rank < 5 and "DIALOG" or state.strata
    state.paintLevel = state.level
end
