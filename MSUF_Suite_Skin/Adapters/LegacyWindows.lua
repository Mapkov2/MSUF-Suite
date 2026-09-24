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

local DEFAULT_OWNER = "blizzardWindows"

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

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function IsCombatLocked()
    return type(NS.IsCombatLocked) == "function" and NS.IsCombatLocked() == true
end

local function IsLoaded(addon)
    if type(addon) ~= "string" or addon == "" then return true end
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
        if not ok then return false end
        return loaded == true or (loaded == nil and loadedOrLoading == true)
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, addon)
        return ok and loaded == true
    end
    return false
end

local function CategoryEnabled(category)
    if not NS.GenericWindows
        or type(NS.GenericWindows.IsCategoryEnabled) ~= "function" then
        return true
    end
    local ok, enabled = pcall(NS.GenericWindows.IsCategoryEnabled, category)
    return not ok or enabled ~= false
end

local function OwnerKey(owner)
    return tostring(owner or DEFAULT_OWNER)
end

local function GetOwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = LegacyWindows.owners[owner]
    if not state then
        state = {
            owner = owner,
            ownerKey = OwnerKey(owner),
            active = false,
            groups = {},
            deferred = {},
        }
        LegacyWindows.owners[owner] = state
    end
    return state, owner
end

local function GetGroupState(state, spec)
    local group = state.groups[spec.id]
    if not group then
        group = {
            owner = state.ownerKey .. ":legacy-windows:" .. spec.id,
            surfaces = WeakSet(),
        }
        state.groups[spec.id] = group
    end
    return group
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("legacy windows " .. tostring(label), message)
    end
end

local function Fade(group, region)
    if not group or not region or IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    local ok, faded = pcall(NS.Cosmetics.Fade, region, group.owner)
    if not ok then Report("fade", faded) end
    return ok and faded == true
end

local function FadeGlobal(group, name)
    local region = _G[name]
    if not region then return false end
    Fade(group, region)
    return true
end

local function FadeDirectTextures(group, frame)
    if not frame or type(SafeField(frame, "GetRegions")) ~= "function" then return end
    pcall(function()
        local function Visit(...)
            for index = 1, select("#", ...) do
                local region = select(index, ...)
                local objectType = type(SafeField(region, "GetObjectType")) == "function"
                    and region:GetObjectType() or nil
                if objectType == "Texture" then Fade(group, region) end
            end
        end
        Visit(frame:GetRegions())
    end)
end

local function ExistingSurface(target)
    if not NS.Registry or type(NS.Registry.GetSurface) ~= "function" then
        return nil
    end
    local ok, surface = pcall(NS.Registry.GetSurface, target)
    return ok and surface or nil
end

local function Attach(group, target)
    if not group or not target or IsCombatLocked() or not NS.Surface
        or type(NS.Surface.Attach) ~= "function" or not NS.Safety
        or not NS.Safety.CanCreateRegions(target, true) then
        return false
    end

    -- Surface has one registry slot per target. Do not take ownership of a
    -- surface installed by GenericWindows or another focused adapter.
    local existing = ExistingSurface(target)
    if existing and not LegacyWindows.surfaceTargets[target] then
        return true
    end

    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = "card",
        radius = 4,
        inset = 1,
        listItem = true,
        allowImplicitProtected = true,
    })
    if ok and surface then
        LegacyWindows.surfaceTargets[target] = true
        group.surfaces[target] = true
        return true
    end
    if not ok then Report("surface", surface) end
    return false
end

local function NormalTexture(button)
    local getter = SafeField(button, "GetNormalTexture")
    if type(getter) ~= "function" then return nil end
    local ok, texture = pcall(getter, button)
    return ok and texture or nil
end

local function StaticResult(found, expected)
    if found <= 0 then return false, "missing" end
    if found < expected then return true, "partial" end
    return true, "applied"
end

local function SkinCalendar(_, group)
    local found = 0
    for index = 1, 42 do
        local button = _G["CalendarDayButton" .. index]
        if button then
            found = found + 1
            Attach(group, button)
            -- Only the parchment normal texture is decorative. EventTexture,
            -- EventBackgroundTexture, PendingInviteTexture, OverlayFrame,
            -- DarkFrame, the highlight, and CalendarTodayFrame remain native.
            Fade(group, NormalTexture(button))
        end
    end
    for index = 1, #calendarChrome do
        FadeGlobal(group, calendarChrome[index])
    end
    -- WeekdaySelectedTexture, CalendarTodayTexture/Glow, event markers and
    -- all day-state overlays are intentionally absent from calendarChrome.
    return StaticResult(found, 42)
end

local function SkinNamedRows(group, prefix, count)
    local found = 0
    for index = 1, count do
        local name = prefix .. index
        local row = _G[name]
        if row then
            found = found + 1
            Attach(group, row)
            Fade(group, SafeField(row, "SlotTexture"))
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

    local header = SafeField(root, "Header") or _G.AchievementFrameHeader
    Fade(group, SafeField(header, "Left"))
    Fade(group, SafeField(header, "Right"))
    for index = 1, #achievementBackdropChrome do
        Fade(group, SafeField(root, achievementBackdropChrome[index]))
    end
    Fade(group, SafeField(SafeField(root, "HeaderDetails"), "TopTileStreaks"))

    -- These exact frames contain only their structural material textures as
    -- direct Texture regions. FontStrings and every child card/control remain
    -- untouched; the generic catalog continues to own the root Glass shell.
    FadeDirectTextures(group, _G.AchievementFrameAchievements)
    Fade(group, SafeField(_G.AchievementFrameSummary, "Background"))
    FadeDirectTextures(group, _G.AchievementFrameStatsBG)
    FadeGlobal(group, "AchievementFrameComparisonBackground")
    Fade(group, SafeField(_G.AchievementFrameComparison, "Dark"))
    FadeDirectTextures(group, SafeField(root, "SearchResults"))

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
    if IsCombatLocked() then return false, "combat" end

    if NS.Surface and type(NS.Surface.SetVisible) == "function" then
        for target in pairs(group.surfaces) do
            if LegacyWindows.surfaceTargets[target] then
                pcall(NS.Surface.SetVisible, target, false)
            end
        end
    end
    if NS.Cosmetics and type(NS.Cosmetics.RestoreOwner) == "function" then
        pcall(NS.Cosmetics.RestoreOwner, group.owner)
    end
    state.groups[spec.id] = nil
    return true
end

local function ApplyGroup(spec, state)
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled(spec.category) then
        DisableGroup(state, spec)
        return true, "disabled"
    end

    local root = _G[spec.root]
    if not root then
        return false, IsLoaded(spec.addon) and "missing" or "waiting"
    end
    local skinner = groupSkinners[spec.id]
    if type(skinner) ~= "function" then return false, "missing" end
    return skinner(root, GetGroupState(state, spec))
end

local function ExecuteGroup(spec, state)
    local ok, applied, reason = pcall(ApplyGroup, spec, state)
    if not ok then
        Report(spec.id, applied)
        return false, "failed"
    end
    return applied, reason
end

local function DeferredKey(state, suffix)
    return "legacy-windows:" .. state.ownerKey .. ":" .. suffix
end

local Schedule

local function ApplyGroupOrDefer(spec, state)
    if not state or not state.active then return false, "disabled" end
    if not IsCombatLocked() then return ExecuteGroup(spec, state) end

    local key = DeferredKey(state, "apply:" .. spec.id)
    state.deferred[key] = true
    NS.CombatGate.RunOrDefer(key, function()
        local current = LegacyWindows.owners[state.owner]
        if current then current.deferred[key] = nil end
        if current and current.active then
            local applied, reason = ExecuteGroup(spec, current)
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
    if IsLoaded(spec.addon) or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end

    LegacyWindows.waiting[spec.id] = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, spec.addon, function()
        LegacyWindows.waiting[spec.id] = nil
        ApplyGroupForOwners(spec)
    end)
    if not ok then
        LegacyWindows.waiting[spec.id] = nil
        Report("load " .. spec.id, message)
        return false
    end
    return true
end

local function CancelDeferred(state)
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
    end
    state.deferred = {}
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
    local state
    state, owner = GetOwnerState(owner)
    CancelDeferred(state)
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
    CancelDeferred(state)
    if IsCombatLocked() then
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
