local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}

local function ColorUnitName(tooltip, line)
    if not M.active or tooltip ~= _G.GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(line) or type(line) ~= "table" then return end

    -- Blizzard supplies the original unit token on this one name line. Its
    -- own line pre-call has already chosen the relationship color; replace it
    -- only for publicly identifiable players, before the line is rendered.
    local unit = S.PublicText(line.unitToken)
    if not unit then return end
    local player = UnitIsPlayer(unit)
    if not S.Public(player) or player ~= true then return end
    local _, class = UnitClass(unit)
    class = S.PublicText(class)
    if not class then return end
    local color = RAID_CLASS_COLORS[class]
    if color then line.leftColor = color end
end

function M:Enable()
    if self.hooked then return end
    TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.UnitName, ColorUnitName)
    self.hooked = true
end

function M:Refresh() end
function M:Disable() end

S.Install("tooltipClassColors", M)
