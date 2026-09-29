local root = assert(arg[1], "repository root required")
local module, callback
local calls = 0
local secret = {}
local function Public(value) return value ~= secret end
local S = {
    Install = function(_, value) module = value end,
    Public = Public,
    PublicText = function(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end,
    Finite = function(value) return Public(value) and type(value) == "number" and value == value end,
    Text = function(value) return value end,
}
local forbidden = false
local NS = { Safety = { IsForbidden = function() return forbidden end } }
GameTooltip = { rows = {}, AddDoubleLine = function(self, left, right)
    self.rows[#self.rows + 1] = { left = left, right = right }
end }
DUNGEON_SCORE = "Dungeon Score"
Enum = { TooltipDataType = { Unit = 8 }, TooltipDataLineType = { UnitName = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, func)
    assert(kind == 8 and not callback)
    callback = func
end }
local isPlayer, score = true, 2221.6
UnitIsPlayer = function(token)
    assert(token == "mouseover")
    return isPlayer
end
C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function(token)
    assert(token == "mouseover")
    calls = calls + 1
    return score and { currentSeasonScore = score }
end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipMPlusScore.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.active = true
module:Enable()
module:Enable()
local data = { lines = { { type = 2, unitToken = "mouseover" } } }
callback(GameTooltip, data)
assert(#GameTooltip.rows == 1 and GameTooltip.rows[1].right == "2222" and calls == 1,
    "public player score was not rounded and displayed once")
callback(GameTooltip, { lines = {
    { type = 2, unitToken = "mouseover" }, { leftText = DUNGEON_SCORE },
} })
assert(#GameTooltip.rows == 1 and calls == 1,
    "native Blizzard dungeon score was duplicated")
callback(GameTooltip, { lines = { { type = 2, unitToken = secret } } })
callback(GameTooltip, { lines = { { type = secret, unitToken = "mouseover" } } })
callback({}, data)
assert(calls == 1, "unknown or foreign tooltip data queried player rating")
isPlayer = secret
callback(GameTooltip, data)
isPlayer = false
callback(GameTooltip, data)
assert(calls == 1, "non-public or non-player unit queried rating")
isPlayer = true
score = secret
callback(GameTooltip, data)
score = 0
callback(GameTooltip, data)
assert(#GameTooltip.rows == 1, "secret or zero score was shown")
forbidden = true
callback(GameTooltip, data)
assert(calls == 3, "forbidden tooltip read an M+ score")
module.active = false
module:Disable()
callback(GameTooltip, data)
assert(calls == 3, "disabled tooltip module kept querying scores")
print("Suite M+ tooltip public-data and lifecycle passed")
