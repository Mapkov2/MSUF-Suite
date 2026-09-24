local root = assert(arg[1], "repository root required")
local locales = {}
local NS = {
    Registry = { AddListener = function() end },
    IsCombatLocked = function() return false end,
    RegisterLocale = function(locale, values) locales[locale] = values end,
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Locales/enUS.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Locales/deDE.lua"))("MSUF_Suite_Skin", NS)
NS.L = locales.enUS
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/CharacterStats.lua"))("MSUF_Suite_Skin", NS)
local stats = assert(NS.CharacterStats)

local ratings = { 350, 120, 410, 0 }
local curveCalls = 0
local function Curve(id, value)
    assert(id == 21024)
    curveCalls = curveCalls + 1
    if value <= 30 then return value end
    if value <= 40 then return 30 + (value - 30) * .9 end
    return 39 + (value - 40) * .8
end
GetCombatRating = function(index) return ratings[index] end
GetCombatRatingBonus = function(index) return Curve(21024, ratings[index] * .1) end
GetCombatRatingBonusForCombatRatingValue = function(_, value) return value * .1 end
C_CurveUtil = { EvaluateGameCurve = Curve }
PlayerIsTimerunning = function() return false end
issecretvalue = function() return false end

local crit = stats.ReadRating(1, {})
assert(math.abs(crit.penalty - 10) < .001)
assert(math.abs(crit.inDR - 50) < .1 and math.abs(crit.lostRating - 5) < .001,
    "rating in DR and rating lost to DR were conflated")
assert(stats.DRBadge(crit) == "(10% DR, +50)")
assert(stats.DRBadge({ penalty = 20, inDR = 1240 }) == "(20% DR, +1.2k)")
local afterDiscovery = curveCalls
local mastery = stats.ReadRating(3, {})
assert(math.abs(mastery.inDR - 110) < .1 and math.abs(mastery.lostRating - 12) < .001)
assert(curveCalls - afterDiscovery < 8, "the first DR breakpoint was rediscovered for each stat")
local haste = stats.ReadRating(2, {})
assert(haste.penalty == 0 and haste.inDR == 0 and haste.lostRating == 0)
assert(stats.DRBadge(haste) == "(0% DR)", "zero DR should be visible in parentheses")

NS.L = locales.deDE
assert(stats.DRBadge(crit) == "(10% DR, +50)")
assert(string.format(NS.L.STATS_DR_AMOUNT, crit.inDR, crit.lostRating):find("Wertung", 1, true))
assert(stats.DRBadge({}) == "(DR ?)", "unknown data was rendered as verified zero DR")

local bonus = GetCombatRatingBonus
GetCombatRatingBonus = function() return 999 end
local unknown = stats.ReadRating(1, {})
assert(unknown.penalty == nil and unknown.inDR == nil and unknown.lostRating == nil)
GetCombatRatingBonus = bonus
PlayerIsTimerunning = function() return true end
unknown = stats.ReadRating(1, {})
assert(unknown.penalty == nil and unknown.inDR == nil)
print("Character stats DR: bracket amount, lost rating, visible zero, localization and fail-closed data passed")
