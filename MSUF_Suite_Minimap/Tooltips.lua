local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- Hover details for the clock, FPS and latency texts: instance lockouts or Great
-- Vault progress. Data is read and its events are registered only while such a
-- tooltip is owned; leaving the text releases both.
local owner, mode
local waitingForItems = false
local Changed
local events = {"UPDATE_INSTANCE_INFO", "WEEKLY_REWARDS_UPDATE", "GET_ITEM_INFO_RECEIVED"}

local function Number(value)
    return S.Public(value) and type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function Text(value)
    return S.Public(value) and type(value) == "string" and value or nil
end

function S.CanShowMinimapTooltip(value)
    if value == 2 then
        return type(GetNumSavedInstances) == "function" and type(GetSavedInstanceInfo) == "function"
    elseif value == 3 then
        return NS.Client.HasAddOn("Blizzard_WeeklyRewards") and C_WeeklyRewards
            and type(C_WeeklyRewards.GetActivities) == "function"
            and Enum and type(Enum.WeeklyRewardChestThresholdType) == "table" or false
    end
    return true
end

local function Owned(button)
    return GameTooltip and not NS.Safety.IsForbidden(GameTooltip) and type(GameTooltip.GetOwner) == "function"
        and GameTooltip:GetOwner() == button
end

function S.HideMinimapInfoTooltip(button)
    if button and owner and button ~= owner then
        if Owned(button) then GameTooltip:Hide() end
        return
    end
    local previous = owner or button
    owner, mode = nil, nil
    waitingForItems = false
    if M.context then for _, event in ipairs(events) do MM.Unlisten(event, "tooltip") end end
    if previous and Owned(previous) then GameTooltip:Hide() end
end
MM.HideInfoTooltip = S.HideMinimapInfoTooltip

local function ResetText(seconds, extended)
    if not Number(seconds) then return "--" end
    local text
    if seconds <= 0 then text = S.Text("Expired")
    elseif type(SecondsToTime) == "function" then text = SecondsToTime(seconds, true, nil, 2)
    else text = math.ceil(seconds / 60) .. " " .. S.Text("minutes") end
    return extended and text .. " (" .. S.Text("Extended") .. ")" or text
end

local function Lockouts(tooltip)
    local c, shown, omitted = M.config, 0, 0
    local count = GetNumSavedInstances()
    if not Number(count) then tooltip:AddLine(S.Text("Instance information unavailable.")); return end
    for index = 1, math.min(math.floor(count), 200) do
        local name, _, reset, _, locked, extended, _, raid, _, difficulty, bosses, defeated = GetSavedInstanceInfo(index)
        if Text(name) and S.Public(locked) and S.Public(extended) and S.Public(raid)
            and (c.tooltipExpired or locked or extended)
            and (c.tooltipInstanceKind == 1 or c.tooltipInstanceKind == 2 and raid or c.tooltipInstanceKind == 3 and not raid) then
            if shown < c.tooltipRows then
                local label = name
                if Text(difficulty) and difficulty ~= "" then label = label .. " - " .. difficulty end
                if c.tooltipBossProgress and Number(bosses) and bosses > 0 and Number(defeated) then
                    label = label .. " (" .. math.floor(defeated) .. "/" .. math.floor(bosses) .. ")"
                end
                tooltip:AddDoubleLine(label, ResetText(reset, extended), 1, 1, 1, .75, .8, .9)
                shown = shown + 1
            else omitted = omitted + 1 end
        end
    end
    if c.tooltipWorldBosses and type(GetNumSavedWorldBosses) == "function" and type(GetSavedWorldBossInfo) == "function" then
        local total = GetNumSavedWorldBosses()
        if Number(total) then
            for index = 1, math.min(math.floor(total), 100) do
                local name, _, reset = GetSavedWorldBossInfo(index)
                if Text(name) then
                    if shown < c.tooltipRows then
                        tooltip:AddDoubleLine(name .. " (" .. S.Text("World boss") .. ")", ResetText(reset), 1, 1, 1, .75, .8, .9)
                        shown = shown + 1
                    else omitted = omitted + 1 end
                end
            end
        end
    end
    if shown == 0 then tooltip:AddLine(S.Text("No matching instance lockouts."), .75, .8, .9) end
    if omitted > 0 then tooltip:AddLine(string.format(S.Text("%d more entries; increase the row limit to show them."), omitted), .75, .8, .9, true) end
end

local function RewardLevel(activity)
    if not M.config.tooltipRewardLevels or not Number(activity.id)
        or type(C_WeeklyRewards.GetExampleRewardItemHyperlinks) ~= "function" then return nil end
    local reader = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
    if type(reader) ~= "function" then return nil end
    local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
    if not Text(link) or link == "" then return nil end
    local level = reader(link)
    if S.Public(level) and level == nil then waitingForItems = true end
    return Number(level) and math.floor(level) or nil
end

local function ActivityLabel(kind)
    local types = Enum.WeeklyRewardChestThresholdType
    if kind == types.Raid then return MM.Label("RAIDS", "Raids") end
    if kind == types.Activities then return MM.Label("DUNGEONS", "Dungeons") end
    if kind == types.RankedPvP then return S.Text("Rated PvP") end
    if kind == types.World then return S.Text("World activities") end
end

local function ActivityLevel(activity)
    local types = Enum.WeeklyRewardChestThresholdType
    local level = activity.level
    if activity.type == types.Raid then
        local name = type(GetDifficultyInfo) == "function" and GetDifficultyInfo(level)
        return Text(name) or S.Text("Difficulty") .. " " .. math.floor(level)
    elseif activity.type == types.RankedPvP then
        local name = PVPUtil and type(PVPUtil.GetTierName) == "function" and PVPUtil.GetTierName(level)
        return Text(name) or S.Text("Tier") .. " " .. math.floor(level)
    elseif activity.type == types.World then return S.Text("Tier") .. " " .. math.floor(level) end
    if Number(activity.activityTierID) and type(C_WeeklyRewards.GetDifficultyIDForActivityTier) == "function" then
        local difficulty = C_WeeklyRewards.GetDifficultyIDForActivityTier(activity.activityTierID)
        local heroic = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonHeroic
        if Number(difficulty) and Number(heroic) and difficulty == heroic then return MM.Label("PLAYER_DIFFICULTY2", "Heroic") end
    end
    return S.Text("Keystone level") .. " " .. math.floor(level)
end

local function Vault(tooltip)
    waitingForItems = false
    if type(C_WeeklyRewards.HasAvailableRewards) == "function" then
        local ready = C_WeeklyRewards.HasAvailableRewards()
        if S.Public(ready) and ready == true then tooltip:AddLine(S.Text("A weekly reward is available."), .45, 1, .45) end
    end
    local activities = C_WeeklyRewards.GetActivities()
    if not S.Public(activities) or type(activities) ~= "table" then
        tooltip:AddLine(S.Text("Weekly reward information unavailable.")); return
    end
    local shown = 0
    for index = 1, math.min(#activities, 36) do
        local activity = activities[index]
        if S.Public(activity) and type(activity) == "table" and Number(activity.type)
            and Number(activity.index) and Number(activity.progress) and Number(activity.threshold) and activity.threshold > 0 then
            local category = ActivityLabel(activity.type)
            if category then
                local complete = activity.progress >= activity.threshold
                local progress = math.floor(math.min(activity.progress, activity.threshold)) .. "/" .. math.floor(activity.threshold)
                local label = category .. " " .. math.floor(activity.index)
                if complete and Number(activity.level) and activity.level > 0 then
                    label = label .. " - " .. ActivityLevel(activity)
                end
                if complete and M.config.tooltipRewardLevels then
                    local level = RewardLevel(activity)
                    progress = progress .. " / " .. S.Text("Item level") .. " " .. (level or "--")
                end
                tooltip:AddDoubleLine(label, progress, 1, 1, 1, complete and .45 or .85, complete and 1 or .85, .55)
                shown = shown + 1
            end
        end
    end
    if shown == 0 then tooltip:AddLine(S.Text("No weekly reward progress available."), .75, .8, .9) end
end

local function Draw()
    if not owner or not M.active or not S.IsMinimapInfoVisible() or NS.Safety.IsForbidden(owner) or not owner:IsVisible() or not Owned(owner) then
        S.HideMinimapInfoTooltip(); return
    end
    GameTooltip:ClearLines()
    GameTooltip:SetText(S.Text(mode == 2 and "Instance lockouts" or "Great Vault"))
    if S.CanShowMinimapTooltip(mode) then
        if mode == 2 then Lockouts(GameTooltip) else Vault(GameTooltip) end
    else waitingForItems = false; GameTooltip:AddLine(S.Text("Unavailable on this client."), .85, .7, .45) end
    if mode == 3 and waitingForItems then MM.Listen("GET_ITEM_INFO_RECEIVED", "tooltip", Changed)
    else MM.Unlisten("GET_ITEM_INFO_RECEIVED", "tooltip") end
    GameTooltip:Show()
end

Changed = function() Draw() end

-- The server answers with UPDATE_INSTANCE_INFO; repeated hovers reuse the cache.
local RAID_INFO_INTERVAL = 30
local lastRequest
local function RequestLockouts()
    if type(RequestRaidInfo) ~= "function" then return end
    local now = type(GetTime) == "function" and GetTime()
    if Number(now) and lastRequest and now - lastRequest < RAID_INFO_INTERVAL then return end
    lastRequest = Number(now) and now or nil
    RequestRaidInfo()
end

function S.ShowMinimapInfoTooltip(button)
    S.HideMinimapInfoTooltip()
    if not M.active or not S.IsMinimapInfoVisible() then return true end
    local key = button.infoKey
    local selected = (key == "Clock" or key == "FPS" or key == "Latency") and M.config["info" .. key .. "Tooltip"] or 1
    if selected == 1 then owner, mode = button, 1; return false end
    if selected == 4 then return true end
    if not M.active or not GameTooltip or NS.Safety.IsForbidden(GameTooltip) then return true end
    owner, mode = button, selected
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    Draw()
    if not S.CanShowMinimapTooltip(selected) then return true end
    if selected == 2 then
        MM.Listen("UPDATE_INSTANCE_INFO", "tooltip", Changed)
        RequestLockouts()
    else
        MM.Listen("WEEKLY_REWARDS_UPDATE", "tooltip", Changed)
    end
    return true
end
