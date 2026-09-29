local _, P = ...
local NS, S = P.NS, P.Suite

-- The unit-name tooltip line carries the token Blizzard used to build the
-- tooltip. Do not reconstruct a unit from GUIDs or read protected chat text.
local M = {}
local MAX_LINES = 20

local function UnitToken(data)
    if not S.Public(data.lines) or type(data.lines) ~= "table" then return end
    local lines = data.lines
    local nativeLabel = S.PublicText(_G.DUNGEON_SCORE)
    local token
    for i = 1, math.min(#lines, MAX_LINES) do
        local line = lines[i]
        if S.Public(line) and type(line) == "table" then
            if nativeLabel and S.PublicText(line.leftText) == nativeLabel then return end
            if S.Public(line.type) and line.type == Enum.TooltipDataLineType.UnitName then
                token = S.PublicText(line.unitToken)
            end
        end
    end
    return token
end

local function UnitTooltip(tooltip, data)
    if not M.active or tooltip ~= _G.GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" then return end
    local unit = UnitToken(data)
    if not unit then return end
    local player = UnitIsPlayer(unit)
    if not S.Public(player) or player ~= true then return end
    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
    if not S.Public(summary) or type(summary) ~= "table" then return end
    local score = summary.currentSeasonScore
    if not S.Finite(score) or score <= 0 then return end
    tooltip:AddDoubleLine(S.Text("Mythic+ season score"), tostring(math.floor(score + .5)),
        .65, .81, .87, 1, .82, .42)
end

function M:Enable()
    if self.hooked then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, UnitTooltip)
    self.hooked = true
end

function M:Refresh() end
function M:Disable() end

S.Install("tooltipMPlusScore", M)
