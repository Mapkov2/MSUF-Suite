local _, NS = ...
local S = NS.Suite

function S.OpenPlanner()
    if NS.InCombat() then
        NS.Print(NS.Text("Unavailable on this client or in combat."))
        return false
    end
    local planner = S.PlanningTools
    if not planner or not planner.Active() then return S.Open("planningTools") end
    local window = planner.Board.window
    if window and window:IsShown() and window.owner == planner.owner then
        planner.Board.Dismiss(planner.owner)
        return true
    end
    return planner.Window.Open("characters")
end

SLASH_MSUFPLANNER1 = "/plan"
SlashCmdList.MSUFPLANNER = function() S.OpenPlanner() end
