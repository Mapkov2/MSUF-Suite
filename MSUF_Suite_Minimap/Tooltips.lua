local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local TOOLTIP, KIND = NS.MinimapInfoTooltip, NS.MinimapInstanceKind
-- Hover details for the clock, FPS and latency texts: instance lockouts or Great
-- Vault progress. Data is read and its events are registered only while such a
-- tooltip is owned; leaving the text releases both.
local owner, mode
local SCALE_SOURCE = "minimap"
local scaleOwner, scaleHooked
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
    if value == TOOLTIP.VAULT then return NS.Client.HasAddOn("Blizzard_WeeklyRewards") end
    return true
end

local function Owned(button)
    return not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:GetOwner() == button
end

-- The scale itself is composed by NS.TooltipScale: this session only sets its
-- percent, and ending it takes just that percent back.
local function EndScaleSession()
    if not scaleOwner then return end
    scaleOwner = nil
    NS.TooltipScale.Set(SCALE_SOURCE, nil)
end

-- Scale only the Suite tooltip session. OnHide ends it; shared tooltip reuse
-- without a hide deliberately retains it until that hide. Never hook shared
-- tooltip methods to intercept another owner.
function MM.ScaleTooltip(button)
    local tooltip = _G.GameTooltip
    if not M.active or NS.Safety.IsForbidden(tooltip) or tooltip:GetOwner() ~= button then return end
    local scale = M.config.tooltipScale or 100
    if not S.Finite(scale) or scale == 100 then return EndScaleSession() end
    if not scaleHooked then
        tooltip:HookScript("OnHide", EndScaleSession)
        scaleHooked = true
    end
    scaleOwner = button
    NS.TooltipScale.Set(SCALE_SOURCE, scale)
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
    if not button or scaleOwner == button then EndScaleSession() end
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
            and (c.tooltipInstanceKind == KIND.ALL or c.tooltipInstanceKind == KIND.RAIDS and raid
                or c.tooltipInstanceKind == KIND.DUNGEONS and not raid) then
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

local function Vault(tooltip)
    waitingForItems = NS.WeeklyRewards.AppendTooltip(tooltip, M.config.tooltipRewardLevels)
end

local function Draw()
    if not owner or not M.active or not MM.InfoVisible() or NS.Safety.IsForbidden(owner)
        or not owner:IsVisible() or not Owned(owner) then
        MM.HideInfoTooltip()
        return
    end
    GameTooltip:ClearLines()
    GameTooltip:SetText(S.Text(mode == TOOLTIP.LOCKOUTS and "Instance lockouts" or "Great Vault"))
    if S.CanShowMinimapTooltip(mode) then
        if mode == TOOLTIP.LOCKOUTS then Lockouts(GameTooltip) else Vault(GameTooltip) end
    else
        waitingForItems = false
        GameTooltip:AddLine(S.Text("Unavailable on this client."), .85, .7, .45)
    end
    if mode == TOOLTIP.VAULT and waitingForItems then
        MM.Listen("GET_ITEM_INFO_RECEIVED", "tooltip", Changed)
    else
        MM.Unlisten("GET_ITEM_INFO_RECEIVED", "tooltip")
    end
    GameTooltip:Show()
end

Changed = function()
    if mode == TOOLTIP.VAULT then NS.WeeklyRewards.Invalidate() end
    Draw()
end

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
    local selected = (key == "Clock" or key == "FPS" or key == "Latency") and M.config["info" .. key .. "Tooltip"]
        or TOOLTIP.VALUE
    if selected == TOOLTIP.VALUE then
        owner, mode = button, TOOLTIP.VALUE
        return false
    end
    if selected == TOOLTIP.NONE then return true end
    if NS.Safety.IsForbidden(GameTooltip) then return true end
    owner, mode = button, selected
    if selected == TOOLTIP.VAULT then NS.WeeklyRewards.Invalidate() end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    MM.ScaleTooltip(button)
    Draw()
    if not S.CanShowMinimapTooltip(selected) then return true end
    if selected == TOOLTIP.LOCKOUTS then
        MM.Listen("UPDATE_INSTANCE_INFO", "tooltip", Changed)
        RequestLockouts()
    else
        MM.Listen("WEEKLY_REWARDS_UPDATE", "tooltip", Changed)
    end
    return true
end
