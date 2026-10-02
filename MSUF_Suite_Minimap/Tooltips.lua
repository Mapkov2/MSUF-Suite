local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- Hover details for the clock, FPS and latency texts: instance lockouts or Great
-- Vault progress. Data is read and its events are registered only while such a
-- tooltip is owned; leaving the text releases both.
local owner, mode
local scaleOwner, previousScale, appliedScale, scaleHooked
local waitingForItems = false
local Changed
local events = { "UPDATE_INSTANCE_INFO", "WEEKLY_REWARDS_UPDATE", "GET_ITEM_INFO_RECEIVED" }

-- Counts, levels, times and IDs: readable, finite and not negative.
local function NonNegative(value)
    return S.Finite(value) and value >= 0
end

local function Text(value)
    return S.Public(value) and type(value) == "string" and value or nil
end

-- The vault tooltip reads the data of Blizzard's weekly rewards addon.
function S.CanShowMinimapTooltip(value)
    if value == 3 then return NS.Client.HasAddOn("Blizzard_WeeklyRewards") end
    return true
end

local function Owned(button)
    return not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:GetOwner() == button
end

-- The client keeps a frame's scale as a 32-bit float, so the scale read back
-- matches the one written only approximately (Blizzard compares geometry
-- with ApproximatelyEqual, Blizzard_SharedXMLBase/MathUtil.lua).
local function RestoreTooltipScale()
    if not scaleOwner then return end
    local tooltip = _G.GameTooltip
    local restore, applied = previousScale, appliedScale
    scaleOwner, previousScale, appliedScale = nil, nil, nil
    if not NS.Safety.IsForbidden(tooltip) and ApproximatelyEqual(tooltip:GetScale(), applied) then
        tooltip:SetScale(restore)
    end
end

local function TooltipOwnerChanged(_, nextOwner)
    if scaleOwner and nextOwner ~= scaleOwner then RestoreTooltipScale() end
end

-- Scale only the Suite's current tooltip session. Returning a tooltip to a
-- different addon or Blizzard restores the previous value, unless another
-- owner has already changed it. The hook never reclaims the tooltip.
function MM.ScaleTooltip(button)
    local tooltip = _G.GameTooltip
    if not M.active or NS.Safety.IsForbidden(tooltip) or tooltip:GetOwner() ~= button then return end
    if scaleOwner ~= button then RestoreTooltipScale() end
    local scale = M.config.tooltipScale or 100
    if not S.Finite(scale) or scale == 100 then return end
    local before = tooltip:GetScale()
    if not S.Finite(before) or before <= 0 then return end
    if not scaleHooked then
        tooltip:HookScript("OnHide", RestoreTooltipScale)
        hooksecurefunc(tooltip, "SetOwner", TooltipOwnerChanged)
        scaleHooked = true
    end
    if not scaleOwner then previousScale = before end
    scaleOwner, appliedScale = button, previousScale * scale / 100
    tooltip:SetScale(appliedScale)
end

-- Hides the button's tooltip; without a button (or for the owner) it also
-- ends the detail tooltip and releases its data events.
function MM.HideInfoTooltip(button)
    if button and owner and button ~= owner then
        if Owned(button) then GameTooltip:Hide() end
        return
    end
    local previous = owner or button
    owner, mode = nil, nil
    waitingForItems = false
    if M.context then for _, event in ipairs(events) do MM.Unlisten(event, "tooltip") end end
    if previous and Owned(previous) then GameTooltip:Hide() end
    if not button or scaleOwner == button then RestoreTooltipScale() end
end

local function ResetText(seconds, extended)
    if not NonNegative(seconds) then return "--" end
    local text
    if seconds <= 0 then
        text = S.Text("Expired")
    else
        text = SecondsToTime(seconds, true, nil, 2)
    end
    return extended and S.Text("%s (Extended)"):format(text) or text
end

local function Lockouts(tooltip)
    local c, shown, omitted = M.config, 0, 0
    local count = GetNumSavedInstances()
    if not NonNegative(count) then
        tooltip:AddLine(S.Text("Instance information unavailable."))
        return
    end
    for index = 1, math.min(math.floor(count), 200) do
        local name, _, reset, _, locked, extended, _, raid, _, difficulty, bosses, defeated = GetSavedInstanceInfo(index)
        if Text(name) and S.Public(locked) and S.Public(extended) and S.Public(raid)
            and (c.tooltipExpired or locked or extended)
            and (c.tooltipInstanceKind == 1 or c.tooltipInstanceKind == 2 and raid
                or c.tooltipInstanceKind == 3 and not raid) then
            if shown < c.tooltipRows then
                local label = name
                if Text(difficulty) and difficulty ~= "" then label = label .. " - " .. difficulty end
                if c.tooltipBossProgress and NonNegative(bosses) and bosses > 0 and NonNegative(defeated) then
                    label = label .. " (" .. math.floor(defeated) .. "/" .. math.floor(bosses) .. ")"
                end
                tooltip:AddDoubleLine(label, ResetText(reset, extended), 1, 1, 1, .75, .8, .9)
                shown = shown + 1
            else
                omitted = omitted + 1
            end
        end
    end
    if c.tooltipWorldBosses then
        local total = GetNumSavedWorldBosses()
        if NonNegative(total) then
            for index = 1, math.min(math.floor(total), 100) do
                local name, _, reset = GetSavedWorldBossInfo(index)
                if Text(name) then
                    if shown < c.tooltipRows then
                        tooltip:AddDoubleLine(S.Text("%s (World boss)"):format(name), ResetText(reset), 1, 1, 1, .75, .8, .9)
                        shown = shown + 1
                    else
                        omitted = omitted + 1
                    end
                end
            end
        end
    end
    if shown == 0 then tooltip:AddLine(S.Text("No matching instance lockouts."), .75, .8, .9) end
    if omitted > 0 then
        tooltip:AddLine(
            string.format(S.Text("%d more entries; increase the row limit to show them."), omitted), .75, .8, .9, true)
    end
end

local function RewardLevel(activity)
    if not M.config.tooltipRewardLevels or not NonNegative(activity.id) then return nil end
    local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
    if not Text(link) or link == "" then return nil end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if S.Public(level) and level == nil then waitingForItems = true end
    return NonNegative(level) and math.floor(level) or nil
end

local function ActivityLabel(kind)
    local types = Enum.WeeklyRewardChestThresholdType
    if kind == types.Raid then return S.BlizzardText("RAIDS", "Raids") end
    if kind == types.Activities then return S.BlizzardText("DUNGEONS", "Dungeons") end
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
            return S.BlizzardText("PLAYER_DIFFICULTY2", "Heroic")
        end
    end
    return S.Text("Keystone level %d"):format(level)
end

local function Vault(tooltip)
    waitingForItems = false
    local ready = C_WeeklyRewards.HasAvailableRewards()
    if S.Public(ready) and ready == true then tooltip:AddLine(S.Text("A weekly reward is available."), .45, 1, .45) end
    local activities = C_WeeklyRewards.GetActivities()
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
                if complete and M.config.tooltipRewardLevels then
                    local level = RewardLevel(activity)
                    progress = S.Text("%s / Item level %s"):format(progress, level or "--")
                end
                tooltip:AddDoubleLine(label, progress, 1, 1, 1, complete and .45 or .85, complete and 1 or .85, .55)
                shown = shown + 1
            end
        end
    end
    if shown == 0 then tooltip:AddLine(S.Text("No weekly reward progress available."), .75, .8, .9) end
end

local function Draw()
    if not owner or not M.active or not MM.InfoVisible() or NS.Safety.IsForbidden(owner)
        or not owner:IsVisible() or not Owned(owner) then
        MM.HideInfoTooltip()
        return
    end
    GameTooltip:ClearLines()
    GameTooltip:SetText(S.Text(mode == 2 and "Instance lockouts" or "Great Vault"))
    if S.CanShowMinimapTooltip(mode) then
        if mode == 2 then Lockouts(GameTooltip) else Vault(GameTooltip) end
    else
        waitingForItems = false
        GameTooltip:AddLine(S.Text("Unavailable on this client."), .85, .7, .45)
    end
    if mode == 3 and waitingForItems then
        MM.Listen("GET_ITEM_INFO_RECEIVED", "tooltip", Changed)
    else
        MM.Unlisten("GET_ITEM_INFO_RECEIVED", "tooltip")
    end
    GameTooltip:Show()
end

Changed = function() Draw() end

-- The server answers with UPDATE_INSTANCE_INFO; repeated hovers reuse the cache.
local RAID_INFO_INTERVAL = 30
local lastRequest
local function RequestLockouts()
    local now = GetTime()
    if lastRequest and now - lastRequest < RAID_INFO_INTERVAL then return end
    lastRequest = now
    RequestRaidInfo()
end

-- Returns true when the button's tooltip is handled here (shown or
-- suppressed); false leaves the plain text tooltip to Info.lua.
function MM.ShowInfoTooltip(button)
    MM.HideInfoTooltip()
    if not M.active or not MM.InfoVisible() then return true end
    local key = button.infoKey
    local selected = (key == "Clock" or key == "FPS" or key == "Latency") and M.config["info" .. key .. "Tooltip"] or 1
    if selected == 1 then
        owner, mode = button, 1
        return false
    end
    if selected == 4 then return true end
    if NS.Safety.IsForbidden(GameTooltip) then return true end
    owner, mode = button, selected
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    MM.ScaleTooltip(button)
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
