local _, NS = ...

-- Exact, clean-room styling for four static Blizzard layouts whose useful
-- child chrome is not covered by the conservative catalog traversal.
-- Names and lifecycles were verified against Gethe/wow-ui-source
-- upstream/live 8ea15b61e45c0ed4eba01439c90757f86eb78d34:
--
--   Blizzard_Calendar/Mainline/{Blizzard_Calendar.xml,
--     Blizzard_CalendarTemplates.xml,Blizzard_Calendar.lua}
--   Blizzard_UIPanels_Game/Mainline/{MerchantFrame.xml,TradeFrame.xml,
--     TradeFrame.lua}
--   Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.xml
--
-- Every target below is created synchronously by its owning Blizzard addon.
-- This module therefore needs only one-shot LoD continuations. It does not
-- hook Blizzard code, poll, install timers, or traverse foreign frame trees.
-- UI mutations are limited to reversible Surface and Cosmetics operations.
local LegacyWindows = {
    owners = {},
    waiting = {},
    surfaceTargets = setmetatable({}, { __mode = "k" }),
}
NS.LegacyWindows = LegacyWindows

local Field = NS.Safety.Field
local Kit = NS.AdapterKit
local Fade = Kit.Fade

local DEFAULT_OWNER = "blizzardWindows"
local CALENDAR_DAY_COUNT = 42

local ROW_SPEC = Kit.SurfaceSpec("card", 4, 1, true)

local groups = {
    {
        id = "calendar-days",
        category = "calendar",
        addon = "Blizzard_Calendar",
        root = "CalendarFrame",
    },
    {
        id = "merchant-rows",
        category = "npc",
        addon = "Blizzard_UIPanels_Game",
        root = "MerchantFrame",
    },
    {
        id = "trade-rows",
        category = "npc",
        addon = "Blizzard_UIPanels_Game",
        root = "TradeFrame",
    },
    {
        id = "achievement-chrome",
        category = "journal",
        addon = "Blizzard_AchievementUI",
        root = "AchievementFrame",
    },
}

local calendarChrome = {
    "CalendarFrameTopLeftTexture",
    "CalendarFrameTopMiddleTexture",
    "CalendarFrameTopRightTexture",
    "CalendarFrameLeftTopTexture",
    "CalendarFrameLeftMiddleTexture",
    "CalendarFrameLeftBottomTexture",
    "CalendarFrameRightTopTexture",
    "CalendarFrameRightMiddleTexture",
    "CalendarFrameRightBottomTexture",
    "CalendarFrameBottomLeftTexture",
    "CalendarFrameBottomMiddleTexture",
    "CalendarFrameBottomRightTexture",
    "CalendarWeekday1Background",
    "CalendarWeekday2Background",
    "CalendarWeekday3Background",
    "CalendarWeekday4Background",
    "CalendarWeekday5Background",
    "CalendarWeekday6Background",
    "CalendarWeekday7Background",
    "CalendarMonthBackground",
    "CalendarYearBackground",
}

local tradeChrome = {
    "TradeRecipientBotLeftCorner",
    "TradeRecipientLeftBorder",
    "TradeRecipientBG",
}

local achievementChrome = {
    "AchievementFrameMetalBorderLeft",
    "AchievementFrameMetalBorderRight",
    "AchievementFrameMetalBorderBottom",
    "AchievementFrameMetalBorderTop",
    "AchievementFrameMetalBorderTopLeft",
    "AchievementFrameMetalBorderTopRight",
    "AchievementFrameMetalBorderBottomLeft",
    "AchievementFrameMetalBorderBottomRight",
    "AchievementFrameWoodBorderTopLeft",
    "AchievementFrameWoodBorderTopRight",
    "AchievementFrameWoodBorderBottomLeft",
    "AchievementFrameWoodBorderBottomRight",
    "AchievementFrameCategoriesBG",
}

local achievementBackdropChrome = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}

local achievementHeaderChrome = { "Left", "Right" }

local function CategoryEnabled(category)
    return NS.GenericWindows.IsCategoryEnabled(category)
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = LegacyWindows.owners[owner]
    if not state then
        state = {
            owner = owner,
            ownerKey = tostring(owner),
            active = false,
            groups = {},
            deferred = {},
        }
        LegacyWindows.owners[owner] = state
    end
    return state
end

-- Each group is its own skin context and cosmetic owner.
local function GroupState(state, spec)
    local group = state.groups[spec.id]
    if not group then
        group = {
            owner = state.ownerKey .. ":legacy-windows:" .. spec.id,
            surfaces = Kit.WeakSet(),
        }
        state.groups[spec.id] = group
    end
    return group
end

local function FadeGlobal(group, name)
    local region = _G[name]
    if not region then return false end
    Fade(group, region)
    return true
end

local function Attach(group, target)
    -- Surface has one registry slot per target. Do not take ownership of a
    -- surface installed by GenericWindows or another focused adapter.
    if target and NS.Registry.GetSurface(target) and not LegacyWindows.surfaceTargets[target] then
        return true
    end
    if not Kit.Attach(group, target, ROW_SPEC) then return false end
    LegacyWindows.surfaceTargets[target] = true
    return true
end

local function StaticResult(found, expected)
    if found <= 0 then return false, "missing" end
    if found < expected then return true, "partial" end
    return true, "applied"
end

local function SkinCalendar(_, group)
    local found = 0
    for index = 1, CALENDAR_DAY_COUNT do
        local button = _G["CalendarDayButton" .. index]
        if button then
            found = found + 1
            Attach(group, button)
            -- Only the parchment normal texture is decorative. EventTexture,
            -- EventBackgroundTexture, PendingInviteTexture, OverlayFrame,
            -- DarkFrame, the highlight, and CalendarTodayFrame remain native.
            Fade(group, NS.Safety.Call(button, "GetNormalTexture"))
        end
    end
    for index = 1, #calendarChrome do
        FadeGlobal(group, calendarChrome[index])
    end
    -- WeekdaySelectedTexture, CalendarTodayTexture/Glow, event markers and
    -- all day-state overlays are intentionally absent from calendarChrome.
    return StaticResult(found, CALENDAR_DAY_COUNT)
end

local function SkinNamedRows(group, prefix, count)
    local found = 0
    for index = 1, count do
        local name = prefix .. index
        local row = _G[name]
        if row then
            found = found + 1
            Attach(group, row)
            Fade(group, Field(row, "SlotTexture"))
            FadeGlobal(group, name .. "NameFrame")
        end
    end
    return found
end

local function SkinMerchant(_, group)
    -- ItemButton, icon/quality, MoneyFrame, AltCurrencyFrame, repair/sell
    -- controls, layout and scripts remain entirely Blizzard-owned.
    return StaticResult(SkinNamedRows(group, "MerchantItem", 12), 12)
end

local function SkinTrade(_, group)
    local found = SkinNamedRows(group, "TradeRecipientItem", 7)
        + SkinNamedRows(group, "TradePlayerItem", 7)
    for index = 1, #tradeChrome do
        FadeGlobal(group, tradeChrome[index])
    end
    -- Preserve both item buttons and Alert animations. In particular, never
    -- touch TradeHighlightPlayer/Recipient/PlayerEnchant/RecipientEnchant,
    -- TradePlayerInputMoneyFrame (forbidden), either money inset/amount/edit
    -- box, or TradeRecipientMoneyBg.
    return StaticResult(found, 14)
end

local function SkinAchievements(root, group)
    local found = 0
    for index = 1, #achievementChrome do
        if FadeGlobal(group, achievementChrome[index]) then
            found = found + 1
        end
    end

    Kit.FadeFields(group, Field(root, "Header") or _G.AchievementFrameHeader, achievementHeaderChrome)
    Kit.FadeFields(group, root, achievementBackdropChrome)
    Fade(group, Kit.Path(root, "HeaderDetails", "TopTileStreaks"))

    -- These exact frames contain only their structural material textures as
    -- direct Texture regions. FontStrings and every child card/control remain
    -- untouched; the generic catalog continues to own the root Glass shell.
    Kit.FadeTextures(group, _G.AchievementFrameAchievements)
    Fade(group, Field(_G.AchievementFrameSummary, "Background"))
    Kit.FadeTextures(group, _G.AchievementFrameStatsBG)
    FadeGlobal(group, "AchievementFrameComparisonBackground")
    Fade(group, Field(_G.AchievementFrameComparison, "Dark"))
    Kit.FadeTextures(group, Field(root, "SearchResults"))

    -- WaterMark, guild emblems, header data, achievement cards, shields,
    -- icons, reward art and progress fills are semantic and stay untouched.
    return StaticResult(found, #achievementChrome)
end

local groupSkinners = {
    ["calendar-days"] = SkinCalendar,
    ["merchant-rows"] = SkinMerchant,
    ["trade-rows"] = SkinTrade,
    ["achievement-chrome"] = SkinAchievements,
}

local function DisableGroup(state, spec)
    local group = state and state.groups[spec.id]
    if not group then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    for target in pairs(group.surfaces) do
        if LegacyWindows.surfaceTargets[target] then
            NS.Surface.SetVisible(target, false)
        end
    end
    NS.Cosmetics.RestoreOwner(group.owner)
    state.groups[spec.id] = nil
    return true
end

local function ApplyGroup(spec, state)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled(spec.category) then
        DisableGroup(state, spec)
        return true, "disabled"
    end

    local root = _G[spec.root]
    if not root then
        return false, NS.Client.IsAddOnLoaded(spec.addon) and "missing" or "waiting"
    end
    return groupSkinners[spec.id](root, GroupState(state, spec))
end

local function DeferredKey(state, suffix)
    return "legacy-windows:" .. state.ownerKey .. ":" .. suffix
end

local Schedule

local function ApplyGroupOrDefer(spec, state)
    if not state or not state.active then return false, "disabled" end
    if not NS.IsCombatLocked() then return ApplyGroup(spec, state) end

    local key = DeferredKey(state, "apply:" .. spec.id)
    state.deferred[key] = true
    NS.CombatGate.RunOrDefer(key, function()
        local current = LegacyWindows.owners[state.owner]
        if current then current.deferred[key] = nil end
        if current and current.active then
            local applied, reason = ApplyGroup(spec, current)
            if not applied and reason == "waiting" then Schedule(spec) end
        end
    end)
    return false, "combat"
end

local function ApplyGroupForOwners(spec)
    for _, state in pairs(LegacyWindows.owners) do
        if state.active and CategoryEnabled(spec.category) then
            local applied, reason = ApplyGroupOrDefer(spec, state)
            if not applied and reason == "waiting" then Schedule(spec) end
        end
    end
end

Schedule = function(spec)
    if LegacyWindows.waiting[spec.id] then return true end
    if NS.Client.IsAddOnLoaded(spec.addon) then return false end
    LegacyWindows.waiting[spec.id] = true
    local scheduled = Kit.ContinueOnAddOnLoaded(spec.addon, function()
        LegacyWindows.waiting[spec.id] = nil
        ApplyGroupForOwners(spec)
    end)
    if not scheduled then LegacyWindows.waiting[spec.id] = nil end
    return scheduled
end

local function DisableNow(owner)
    local state = LegacyWindows.owners[owner]
    if not state then return true end
    for index = 1, #groups do
        DisableGroup(state, groups[index])
    end
    LegacyWindows.owners[owner] = nil
    return true
end

function LegacyWindows.Apply(owner)
    local state = OwnerState(owner)
    Kit.CancelDeferred(state)
    state.active = true

    local enabled, applied, waiting, queued, failed = 0, 0, 0, 0, 0
    for index = 1, #groups do
        local spec = groups[index]
        if CategoryEnabled(spec.category) then enabled = enabled + 1 end
        local success, reason = ApplyGroupOrDefer(spec, state)
        if success then
            if reason ~= "disabled" then applied = applied + 1 end
        elseif reason == "waiting" and Schedule(spec) then
            waiting = waiting + 1
        elseif reason == "combat" then
            queued = queued + 1
        elseif reason ~= "disabled" then
            failed = failed + 1
        end
    end

    if enabled == 0 then return true, "disabled" end
    if queued > 0 and applied == 0 and waiting == 0 and failed == 0 then
        return false, "combat"
    end
    if failed > 0 and applied == 0 and waiting == 0 and queued == 0 then
        return false, "missing"
    end
    if failed > 0 or queued > 0 or (waiting > 0 and applied > 0) then
        return true, "partial"
    end
    if waiting > 0 then return true, "waiting" end
    return true, "applied"
end

function LegacyWindows.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = LegacyWindows.owners[owner]
    if not state then return true end

    state.active = false
    Kit.CancelDeferred(state)
    if NS.IsCombatLocked() then
        local key = DeferredKey(state, "disable")
        state.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            local current = LegacyWindows.owners[owner]
            if current then current.deferred[key] = nil end
            if current and not current.active then DisableNow(owner) end
        end)
        return false, "combat"
    end
    return DisableNow(owner)
end

function LegacyWindows.GetWaitingCount()
    local count = 0
    for _ in pairs(LegacyWindows.waiting) do count = count + 1 end
    return count
end

return LegacyWindows
