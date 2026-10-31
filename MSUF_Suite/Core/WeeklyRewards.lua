local _, S = ...
-- One native provider shared by optional Minimap and DataTexts consumers.
-- No listener or request is installed here; each visible owner owns its events.
local W = {}
S.WeeklyRewards = W
local function NonNegative(value) return S.Finite(value) and value >= 0 end
local function Text(value) return S.PublicText(value) end
function W.Available()
    return not S.Client.isForever and S.Client.HasAddOn("Blizzard_WeeklyRewards")
end
local loaded, activities, ready, summary
function W.Invalidate() loaded, activities, ready, summary = nil, nil, nil, nil end
local function Snapshot()
    if loaded then return activities, ready end
    loaded = true
    if not W.Available() then return end
    local rewards = C_WeeklyRewards.HasAvailableRewards()
    ready = S.Public(rewards) and rewards == true
    local data = C_WeeklyRewards.GetActivities()
    if S.Public(data) and type(data) == "table" then activities = data end
    return activities, ready
end
function W.Summary()
    if summary then return summary end
    local activities, ready = Snapshot()
    if ready then
        summary = S.Text("Reward available")
        return summary
    end
    if not S.Public(activities) or type(activities) ~= "table" then return nil end
    local complete, total = 0, 0
    for i = 1, math.min(#activities, 36) do
        local a = activities[i]
        if S.Public(a) and type(a) == "table" and NonNegative(a.threshold) and a.threshold > 0
            and NonNegative(a.progress) then
            total = total + 1
            if a.progress >= a.threshold then complete = complete + 1 end
        end
    end
    summary = S.Text("%d / %d slots"):format(complete, total)
    return summary
end

local waitingForItems
local function RewardLevel(activity, levels)
    if not levels or not NonNegative(activity.id) then return nil end
    local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
    if not Text(link) or link == "" then return nil end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if S.Public(level) and level == nil then waitingForItems = true end
    return NonNegative(level) and math.floor(level) or nil
end

local function ActivityLabel(kind)
    local types = Enum.WeeklyRewardChestThresholdType
    if kind == types.Raid then return S.Suite.BlizzardText("RAIDS", "Raids") end
    if kind == types.Activities then return S.Suite.BlizzardText("DUNGEONS", "Dungeons") end
    if kind == types.RankedPvP then return S.Text("Rated PvP") end
    if kind == types.World then return S.Text("World activities") end
end

local function ActivityLevel(activity)
    local types = Enum.WeeklyRewardChestThresholdType
    local level = activity.level
    if activity.type == types.Raid then
        local name = GetDifficultyInfo(level)
        return Text(name) or S.Text("Difficulty %d"):format(level)
    elseif activity.type == types.RankedPvP then
        local name = PVPUtil.GetTierName(level)
        return Text(name) or S.Text("Tier %d"):format(level)
    elseif activity.type == types.World then
        return S.Text("Tier %d"):format(level)
    end
    if NonNegative(activity.activityTierID) then
        local difficulty = C_WeeklyRewards.GetDifficultyIDForActivityTier(activity.activityTierID)
        if NonNegative(difficulty) and difficulty == DifficultyUtil.ID.DungeonHeroic then
            return S.Suite.BlizzardText("PLAYER_DIFFICULTY2", "Heroic")
        end
    end
    return S.Text("Keystone level %d"):format(level)
end

function W.AppendTooltip(tooltip, levels)
    waitingForItems = false
    local activities, ready = Snapshot()
    if ready then tooltip:AddLine(S.Text("A weekly reward is available."), .45, 1, .45) end
    if not S.Public(activities) or type(activities) ~= "table" then
        tooltip:AddLine(S.Text("Weekly reward information unavailable."))
        return
    end
    local shown = 0
    for index = 1, math.min(#activities, 36) do
        local activity = activities[index]
        if S.Public(activity) and type(activity) == "table" and NonNegative(activity.type) and NonNegative(activity.index)
            and NonNegative(activity.progress) and NonNegative(activity.threshold) and activity.threshold > 0 then
            local category = ActivityLabel(activity.type)
            if category then
                local complete = activity.progress >= activity.threshold
                local progress = math.floor(math.min(activity.progress, activity.threshold)) ..
                    "/" .. math.floor(activity.threshold)
                local label = category .. " " .. math.floor(activity.index)
                if complete and NonNegative(activity.level) and activity.level > 0 then
                    label = label .. " - " .. ActivityLevel(activity)
                end
                if complete and levels then
                    local level = RewardLevel(activity, levels)
                    progress = S.Text("%s / Item level %s"):format(progress, level or "--")
                end
                tooltip:AddDoubleLine(label, progress, 1, 1, 1, complete and .45 or .85, complete and 1 or .85, .55)
                shown = shown + 1
            end
        end
    end
    if shown == 0 then tooltip:AddLine(S.Text("No weekly reward progress available."), .75, .8, .9) end
    return waitingForItems
end
