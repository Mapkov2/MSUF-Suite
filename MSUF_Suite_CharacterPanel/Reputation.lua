local _, NS = ...
local Number, Text = NS.Number, NS.Text
local ReadFactionReputation = NS.Suite.ReadFactionReputation
local StandingLabel = NS.Suite.ReputationStandingLabel
local Reputation = {}
NS.Reputation = Reputation

local STANDING, PROGRESS, REMAINING, PERCENT = 1, 2, 3, 4
local NEXT = 1
local NEXT_RANK, PROGRESS_LABEL = Text("Next rank"), Text("Progress")
local UNTIL, REWARD_AVAILABLE = Text("%s until %s"), Text("Reward available")
local REPUTATION = Text("Reputation")
-- Standard faction bands from Hated to Exalted. Require the current native
-- endpoints to match before estimating a more distant rank from this ladder.
local threshold = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }

function Reputation.Options(config)
    if not config then return false, STANDING, NEXT end
    return config.showReputationBars == true, config.reputationValue or STANDING, config.reputationGoal or NEXT
end

function Reputation.OptionsKey(config)
    local bars, value, goal = Reputation.Options(config)
    return (bars and 100 or 0) + value * 10 + goal
end

local function TargetProgress(info, reaction, goal, current, maximum)
    if reaction >= goal then return 1, 1, true end
    local target = threshold[goal]
    local lower, upper = Number(info.currentReactionThreshold), Number(info.nextReactionThreshold)
    local standing = Number(info.currentStanding)
    if target and standing and lower == threshold[reaction] and upper == threshold[reaction + 1] then
        -- A fixed goal spans the standard ladder from its floor. Keeping
        -- the origin fixed lets the bar advance through negative rank changes.
        local origin = threshold[1]
        return standing - origin, target - origin, false
    end
    if reaction + 1 == goal then return current, maximum, false end
end

local function ProgressText(current, maximum)
    return REPUTATION_PROGRESS_FORMAT:format(BreakUpLargeNumbers(current), BreakUpLargeNumbers(maximum))
end

local function RemainingText(current, maximum, goalLabel)
    return UNTIL:format(BreakUpLargeNumbers(maximum - current), goalLabel)
end

local function Tooltip(tip, details)
    tip:AddDoubleLine(REPUTATION, details.standing)
    if not details.capped then
        tip:AddDoubleLine(PROGRESS_LABEL, ProgressText(details.current, details.maximum))
    end
    if details.pending then
        tip:AddLine(REWARD_AVAILABLE)
    elseif details.goal then
        tip:AddLine(RemainingText(details.current, details.maximum, details.goal))
    end
    if details.nextGoal then
        tip:AddLine(UNTIL:format(BreakUpLargeNumbers(details.nextRemaining), details.nextGoal))
    end
end

local function Display(mode, standing, details, fill)
    if mode == PROGRESS and not details.capped then
        return ProgressText(details.current, details.maximum)
    elseif mode == REMAINING then
        if details.pending then return REWARD_AVAILABLE end
        if details.goal then return RemainingText(details.current, details.maximum, details.goal) end
    elseif mode == PERCENT then
        return string.format("%.0f%%", fill * 100)
    end
    return standing
end

function Reputation.Populate(row, info, sex, showBars, valueMode, goal)
    local detailed = showBars or valueMode ~= STANDING or goal ~= NEXT
    local kind, standing, current, maximum, capped, nextLevel, pending = ReadFactionReputation(info, sex, detailed)
    row.value = standing or row.value
    if not standing or not detailed then return end

    local goalLabel, nextGoal, nextRemaining
    local reaction = Number(info.reaction)
    if kind == "standing" then
        local nativeGoal = StandingLabel(nextLevel, sex)
        if reaction and threshold[reaction] and goal ~= NEXT then
            local progress, total, reached = TargetProgress(info, reaction, goal, current, maximum)
            if progress then
                if nativeGoal and goal ~= nextLevel then
                    nextGoal, nextRemaining = nativeGoal, math.max(0, maximum - math.max(0, current))
                end
                current, maximum, capped = progress, total, reached
                goalLabel = StandingLabel(goal, sex)
            end
        end
        goalLabel = goalLabel or nativeGoal
    elseif kind == "renown" and nextLevel then
        goalLabel = RENOWN_LEVEL_LABEL:format(nextLevel)
    elseif not capped then
        goalLabel = NEXT_RANK
    end

    if not current or not maximum or maximum <= 0 then return end
    current = math.min(maximum, math.max(0, current))
    local fill = current / maximum
    if showBars then
        row.reputationFill = fill
        if kind == "standing" and reaction and threshold[reaction] then row.reputationReaction = reaction
        elseif kind == "friendship" then row.reputationReaction = 5 end
    end
    local details = row.reputationDetails
    if not details then
        details = {}
        row.reputationDetails = details
    end
    details.standing, details.goal, details.capped, details.pending = standing, goalLabel, capped, pending
    details.current, details.maximum = current, maximum
    details.nextGoal, details.nextRemaining = nextGoal, nextRemaining
    row.value = Display(valueMode, standing, details, fill)
    row.tooltip, row.tooltipArgument = Tooltip, details
end

local sample = { reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 640 }

function Reputation.Sample(row, config)
    row.value = "640 / 3000"
    row.reputationFill, row.reputationReaction, row.tooltip, row.tooltipArgument = nil, nil, nil, nil
    local bars, value, goal = Reputation.Options(config)
    if bars or value ~= STANDING or goal ~= NEXT then
        Reputation.Populate(row, sample, Number(UnitSex("player")) or false, bars, value, goal)
    end
end
