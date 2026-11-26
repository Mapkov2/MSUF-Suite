local _, Suite = ...
local Hub = {}
Suite.HUDVisibility = Hub
local listeners, scopes, alpha, hoverReveal = {}, {}, 1, false

function Hub.Register(scope, repaint)
    listeners[scope] = repaint
end

function Hub.Factor(scope, hovered)
    if not scopes[scope] or hovered and hoverReveal then return 1 end
    return alpha
end

-- The owner publishes a fresh scope table after settings changes and
-- reuses that immutable selection on its state transitions.
function Hub.Changed(newScopes, newAlpha, newHover)
    if newScopes == scopes and newAlpha == alpha and newHover == hoverReveal then return end
    local oldScopes, oldAlpha, oldHover = scopes, alpha, hoverReveal
    scopes, alpha, hoverReveal = newScopes, newAlpha, newHover
    for key, paint in pairs(listeners) do
        if oldScopes[key] ~= scopes[key] or scopes[key] and (alpha ~= oldAlpha or hoverReveal ~= oldHover) then
            Suite.Dispatch(paint)
        end
    end
end
