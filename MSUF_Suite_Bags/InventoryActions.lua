local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
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
    P.PhysicalSort.Stop()
    C_Container.SortBags()
    view.Request()
    return true
end

local function BuildSortMenu(owner, root)
    root:CreateButton(S.Text("Clean up bags"), Actions.Cleanup)
    P.PhysicalSort.AddMenu(owner, root)
end

function Actions.SortMenu(button)
    if M.active and not NS.InCombat() then S.ContextMenu(button, BuildSortMenu) end
end
