local _, P = ...
local S = P.Suite

-- The unit-name tooltip line carries the token Blizzard used to build the
-- tooltip. Do not reconstruct a unit from GUIDs or read protected chat text.
local M = {}
local MAX_LINES = 20

-- Blizzard shows the score itself for some tooltips; never add a second one.
local function NativeScore(lines)
    local label = S.PublicText(_G.DUNGEON_SCORE)
    if not label then return false end
    for i = 2, math.min(#lines, MAX_LINES) do
        local line = lines[i]
        if S.Public(line) and type(line) == "table" and S.PublicText(line.leftText) == label then return true end
    end
    return false
end

local function UnitTooltip(tooltip, data)
    local unit = S.TooltipLines.UnitName(data)
    if not unit or NativeScore(data.lines) then return end
    local player = UnitIsPlayer(unit)
    if not S.Public(player) or player ~= true then return end
    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
    if not S.Public(summary) or type(summary) ~= "table" then return end
    local score = summary.currentSeasonScore
    if not S.Finite(score) or score <= 0 then return end
    S.TooltipLines.Line(tooltip, "Mythic+ season score", tostring(math.floor(score + .5)), 1, .82, .42)
end

function M:Enable() S.TooltipLines.Add(self, "Unit", UnitTooltip) end
function M:Refresh() end
function M:Disable() end

S.Install("tooltipMPlusScore", M)
