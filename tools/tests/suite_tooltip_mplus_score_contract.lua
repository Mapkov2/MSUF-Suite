local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module
local calls, reported = 0, {}
local secret = {}
local function Public(value) return value ~= secret end
local S = {
    Install = function(_, value) module = value end,
    Public = Public,
    PublicText = function(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end,
    Finite = function(value) return Public(value) and type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Dispatch = Support.Dispatcher(reported),
}
local forbidden = false
local NS = { Safety = { IsForbidden = function() return forbidden end } }
GameTooltip = { rows = {}, AddDoubleLine = function(self, left, right)
    self.rows[#self.rows + 1] = { left = left, right = right }
end }
DUNGEON_SCORE = "Dungeon Score"
Enum = { TooltipDataType = { Unit = 8 }, TooltipDataLineType = { UnitName = 2 } }
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
local tooltips = Support.TooltipFixture(root, S, NS)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipMPlusScore.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.active = true
module:Enable()
module:Enable()
assert(#tooltips.post[8] == 1 and not next(tooltips.pre), "the score post-call was registered twice")
local function Run(tooltip, data) tooltips.Run(8, tooltip, data) end
local data = { lines = { { type = 2, unitToken = "mouseover", lineIndex = 1 } } }
Run(GameTooltip, data)
assert(#GameTooltip.rows == 1 and GameTooltip.rows[1].right == "2222" and calls == 1,
    "public player score was not rounded and displayed once")
Run(GameTooltip, { lines = {
    { type = 2, unitToken = "mouseover", lineIndex = 1 }, { leftText = DUNGEON_SCORE },
} })
assert(#GameTooltip.rows == 1 and calls == 1,
    "native Blizzard dungeon score was duplicated")
Run(GameTooltip, { lines = { { type = 2, unitToken = secret } } })
Run(GameTooltip, { lines = { { type = secret, unitToken = "mouseover" } } })
Run({}, data)
assert(calls == 1, "unknown or foreign tooltip data queried player rating")
isPlayer = secret
Run(GameTooltip, data)
isPlayer = false
Run(GameTooltip, data)
assert(calls == 1, "non-public or non-player unit queried rating")
isPlayer = true
score = secret
Run(GameTooltip, data)
score = 0
Run(GameTooltip, data)
assert(#GameTooltip.rows == 1, "secret or zero score was shown")
forbidden = true
Run(GameTooltip, data)
assert(calls == 3, "forbidden tooltip read an M+ score")
module.active = false
module:Disable()
Run(GameTooltip, data)
assert(calls == 3 and #reported == 0, "disabled tooltip module kept querying scores")
print("Suite M+ tooltip public-data and lifecycle passed")
