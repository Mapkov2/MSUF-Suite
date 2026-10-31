local _, NS = ...
-- The one writer of GameTooltip's scale. Suite parts that scale the shared
-- tooltip (the tooltip scale of Quality of Life, the hover tooltips of the
-- Minimap) only set their percent here; the scale written is Blizzard's own
-- times every percent set. Blizzard's own scale is read once, while no Suite
-- percent applies, so no part takes another's result for the native scale.
-- Whoever sets a percent clears it when its tooltip hides, and the tooltip
-- gets Blizzard's scale back once none is left. Nothing is hooked here, and
-- without a percent the tooltip is not touched.
local T = {}
NS.TooltipScale = T
local DEFAULT_PERCENT = 100
local percents = {}
local native, applied

local function Composed()
    local percent = DEFAULT_PERCENT
    for _, value in pairs(percents) do percent = percent * value / DEFAULT_PERCENT end
    return percent
end

-- The client keeps a frame's scale as a 32-bit float, so the scale read back
-- matches the one written only approximately (Blizzard compares geometry
-- with ApproximatelyEqual, Blizzard_SharedXMLBase/MathUtil.lua).
local function StillApplied(tooltip)
    return ApproximatelyEqual(tooltip:GetScale(), applied)
end

local function Apply()
    local percent = Composed()
    if percent == DEFAULT_PERCENT and native == nil then return end
    local tooltip = GameTooltip
    if NS.Safety.IsForbidden(tooltip) then return end
    -- A scale another addon wrote replaces ours: nothing of the Suite applies
    -- then, and that scale is the one to compose with and to give back.
    if native ~= nil and not StillApplied(tooltip) then native, applied = nil, nil end
    if percent == DEFAULT_PERCENT then
        if native ~= nil then tooltip:SetScale(native) end
        native, applied = nil, nil
        return
    end
    if native == nil then
        local scale = tooltip:GetScale()
        if not NS.Finite(scale) or scale <= 0 then return end
        native = scale
    end
    applied = native * percent / DEFAULT_PERCENT
    tooltip:SetScale(applied)
end

-- percent: this source's share of the scale; nil or 100 for none.
function T.Set(source, percent)
    if NS.Finite(percent) and percent > 0 and percent ~= DEFAULT_PERCENT then
        percents[source] = percent
    else
        percents[source] = nil
    end
    Apply()
end
