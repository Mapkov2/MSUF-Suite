local _, P = ...
local NS = P.NS
local Layout = {}
P.BagLayout = Layout

function Layout.Frame(frame)
    if not frame or NS.Safety.IsForbidden(frame) then return false end
    local protected = frame:IsProtected()
    if NS.IsSecret(protected) then return false end
    return protected == false
end

-- Stock containers and ItemButtons are unprotected. Check the actual pool
-- on every combat layout; another addon may have changed its protection.
-- Items is Blizzard's current slot array, including empty slots.
function Layout.CanRender(event)
    if not NS.InCombat(event) then return true end
    local frame = P.InventoryView.frame
    if not Layout.Frame(frame) then return false end
    local items = frame.Items
    for i = 1, #items do
        if not Layout.Frame(items[i]) then return false end
    end
    return true
end

function Layout.Scale(context, frame, value)
    if NS.IsCombatLocked() then
        context:UnprotectedProperty(frame, "GetScale", "SetScale", value)
    else
        context:Scale(frame, value)
    end
end

function Layout.Alpha(context, frame, value)
    if NS.IsCombatLocked() then
        context:UnprotectedProperty(frame, "GetAlpha", "SetAlpha", value)
    else
        context:Alpha(frame, value)
    end
end

function Layout.Anchor(context, frame, point, relative, relativePoint, x, y)
    if NS.IsCombatLocked() then
        context:UnprotectedAnchor(frame, point, relative, relativePoint, x, y)
    else
        context:Anchor(frame, point, relative, relativePoint, x, y)
    end
end

function Layout.Position(context, frame, point, x, y)
    if NS.IsCombatLocked() then
        context:UnprotectedAnchor(frame, point, UIParent, point, x, y)
    else
        context:Position(frame, point, x, y)
    end
end

function Layout.RestoreProperty(context, frame, setter)
    if not NS.IsCombatLocked() or Layout.Frame(frame) then context:RestoreProperty(frame, setter) end
end

function Layout.RestorePoints(context, frame)
    if not NS.IsCombatLocked() or Layout.Frame(frame) then context:RestorePoints(frame) end
end

function Layout.HideControl(context, frame, hidden)
    if NS.IsCombatLocked() then
        context:HideUnprotected(frame, hidden)
    else
        context:HideControl(frame, hidden)
    end
end
