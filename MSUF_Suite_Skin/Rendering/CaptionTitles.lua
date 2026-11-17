local _, NS = ...

local Titles = {}
NS.CaptionTitles = Titles
local Safety = NS.Safety
local GAP = 6

local function CanAnchor(container)
    if not Safety.CanDecorate(container) or not Safety.HasMethod(container, "SetPoint") then return false end
    return not Safety.HasMethod(container, "IsAnchoringRestricted") or Safety.Read(container, "IsAnchoringRestricted") == false
end

-- Blizzard's portrait panels bound the title with a dedicated container.
-- Move only its existing top-right anchor, preserving the native caption's
-- left edge, vertical alignment, truncation and localization.
function Titles.Restore(state)
    state.titleLimit = nil
    local fit = state.titleFit
    if not fit or NS.IsCombatLocked() or not CanAnchor(fit.container) then return end
    local point, target, relative, x, y = Safety.Call(fit.container, "GetPoint", fit.index)
    if Safety.Public(point) and Safety.Public(target) and Safety.Public(relative)
        and Safety.Public(x) and Safety.Public(y)
        and point == "TOPRIGHT" and target == state.frame and relative == fit.relative
        and x == fit.applied and y == fit.y then
        fit.container:SetPoint(point, target, relative, fit.x, y)
    end
    state.titleFit = nil
end

local function Anchor(container, frame)
    local count = Safety.Read(container, "GetNumPoints")
    if type(count) ~= "number" then return end
    for index = 1, count do
        local point, target, relative, x, y = Safety.Call(container, "GetPoint", index)
        if Safety.Public(point) and Safety.Public(target) and Safety.Public(relative)
            and Safety.Public(x) and Safety.Public(y)
            and point == "TOPRIGHT" and target == frame and relative == "TOPRIGHT"
            and type(x) == "number" and type(y) == "number" then
            return index, x, y
        end
    end
end

local function Fit(state, edge, right, scale)
    if NS.IsCombatLocked() then return end
    local frame = state.frame
    local container = Safety.Field(frame, "TitleContainer")
    if not Safety.Public(container) or not CanAnchor(container) then return end
    local index, x, y = Anchor(container, frame)
    local containerScale = Safety.Read(container, "GetEffectiveScale")
    local left = Safety.Read(container, "GetLeft")
    if not index or type(left) ~= "number" or type(containerScale) ~= "number" or containerScale <= 0 then return end
    if (edge - GAP) * scale <= left * containerScale then return end
    local fit = state.titleFit
    local original = fit and fit.container == container and fit.applied == x and fit.y == y and fit.x or x
    local needed = math.min(original, (edge - right - GAP) * scale / containerScale)
    if needed == original then
        Titles.Restore(state)
    elseif needed ~= x then
        container:SetPoint("TOPRIGHT", frame, "TOPRIGHT", needed, y)
        state.titleFit = { container = container, index = index, relative = "TOPRIGHT", x = original, y = y, applied = needed }
    end
end

function Titles.Fit(state, edge, right, scale)
    if NS.IsCombatLocked() then return end
    state.titleLimit, state.titleRight, state.titleScale = edge, right, scale
    if not edge then return end
    if not state.fitTitle then
        state.fitTitle = function()
            if state.titleLimit and Safety.Read(state.frame, "IsVisible") == true then
                Fit(state, state.titleLimit, state.titleRight, state.titleScale)
            end
        end
    end
    NS.Registry.QueueJob(state.fitTitle)
end
