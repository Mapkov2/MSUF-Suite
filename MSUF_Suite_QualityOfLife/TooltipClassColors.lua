local _, P = ...
local S = P.Suite

-- Recolors a player's name after Blizzard built the unit tooltip: the text
-- of the name line takes the class color; Blizzard's line data stays as
-- Blizzard wrote it (TooltipLines.lua).
local M = {}

local function ColorName(_, data)
    local unit, name = S.TooltipLines.UnitName(data)
    if not name then return end
    local player = UnitIsPlayer(unit)
    if not S.Public(player) or player ~= true then return end
    local _, class = UnitClass(unit)
    class = S.PublicText(class)
    local color = class and RAID_CLASS_COLORS[class]
    if color then name:SetTextColor(color.r, color.g, color.b) end
end

function M:Enable() S.TooltipLines.Add(self, "Unit", ColorName) end
function M:Refresh() end
function M:Disable() end

S.Install("tooltipClassColors", M)
