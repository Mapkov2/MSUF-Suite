local _, P = ...
local NS, M = P.NS, P.BagsModule
local Actions = {}
P.InventoryActions = Actions

-- Physical cleanup and display sorting are separate operations. Native sort
-- completion invalidates slot data through BAG_UPDATE; no random order survives.
function Actions.Cleanup()
    if not M.active or NS.InCombat() then return false end
    local kind = GetCursorInfo()
    if not NS.Public(kind) or kind ~= nil or StackSplitFrame:IsShown() then return false end
    local view = P.InventoryView
    view.scroll, view.selected = 0, "all"
    C_Container.SortBags()
    view.Request()
    return true
end
