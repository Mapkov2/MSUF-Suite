local _, Suite = ...
local Finite, Public, InCombat, Dispatch = Suite.Finite, Suite.Public, Suite.InCombat, Suite.Dispatch
local retail = Suite.Client.isMainline and not Suite.Client.isForever

-- PaperDollFrame uses the native rating and effective bonus on both clients
-- (live 297d7aaa, forever 9dc84f0d). The Retail rating curve identity and
-- units were checked against SimulationCraft's Midnight sc_enums.hpp and
-- player_t::apply_combat_rating_dr.
local RATING_CURVE = 21024
local firstDRPoint

local function Number(value)
    if Finite(value) and value >= 0 and value < 1e9 then return value end
end

-- C_CurveUtil.EvaluateGameCurve raises for a curve the client does not ship.
-- The rating curve is probed once as its own error boundary (the error is
-- reported, not swallowed) and an unusable curve is remembered, so the DR
-- details fail closed without raising on every refresh.
local ratingCurve -- nil: not probed yet, false: unavailable, else the function

local function ProbeCurve(curve)
    curve(RATING_CURVE, 1)
    return true
end

local function RatingCurve()
    if ratingCurve == nil then
        local curve = C_CurveUtil.EvaluateGameCurve
        ratingCurve = curve and Dispatch(ProbeCurve, curve) == true and curve or false
    end
    return ratingCurve or nil
end

-- Reuse one result per rating. DR describes the marginal return of the NEXT
-- rating point, not a blanket penalty on all existing rating or the total stat.
-- The first reduced segment is discovered from the native curve once rather
-- than assuming a threshold or rating conversion for every client version.
local function FirstDRPoint(curve)
    if firstDRPoint then return firstDRPoint end
    local high = 200
    local value = Number(curve(RATING_CURVE, high))
    if not value or high - value < .001 then return nil end
    local low = 0
    for _ = 1, 18 do
        local middle = (low + high) / 2
        value = Number(curve(RATING_CURVE, middle))
        if not value then return nil end
        if middle - value > .00001 then high = middle else low = middle end
    end
    firstDRPoint = low
    return firstDRPoint
end

function Suite.ReadCharacterRating(index, result, withDR)
    result.rating, result.bonus, result.penalty, result.loss = nil, nil, nil, nil
    result.inDR, result.lostRating = nil, nil
    if InCombat() or not Finite(index) or index < 1 then return result end
    local rating = Number(GetCombatRating(index))
    local bonus = Number(GetCombatRatingBonus(index))
    result.rating, result.bonus = rating, bonus
    if not withDR or not retail or not rating or not bonus then return result end
    local timerunning = PlayerIsTimerunning()
    if not Public(timerunning) or timerunning then return result end
    local perPoint = Number(GetCombatRatingBonusForCombatRatingValue(index, 1))
    if not perPoint or perPoint <= 0 then return result end
    local curve = RatingCurve()
    if not curve then return result end
    local baseline = Number(curve(RATING_CURVE, 1))
    if not baseline or math.abs(baseline - 1) > .001 then return result end
    local raw = rating * perPoint
    local effective = Number(curve(RATING_CURVE, raw))
    local nextPoint = Number(curve(RATING_CURVE, raw + perPoint))
    -- Fail closed on unavailable curves, different units, unusual scaling or
    -- stale client contracts. Mastery stays in rating-derived mastery POINTS.
    if not effective or not nextPoint or effective > raw + .001
        or math.abs(effective - bonus) > math.max(.02, bonus * .002)
        or nextPoint < effective or nextPoint - effective > perPoint * 1.002 then
        return result
    end
    result.penalty = math.max(0, math.min(100, 100 * (1 - (nextPoint - effective) / perPoint)))
    if result.penalty < .05 then result.penalty = 0 end
    result.loss = raw > 0 and math.max(0, 100 * (raw - effective) / raw) or 0
    result.lostRating = math.max(0, (raw - effective) / perPoint)
    if result.penalty == 0 then
        result.inDR = 0
    else
        local onset = FirstDRPoint(curve)
        if onset then result.inDR = math.max(0, rating - onset / perPoint) end
    end
    return result
end
