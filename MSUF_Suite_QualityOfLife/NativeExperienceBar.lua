local _, P = ...
local NS, S = P.NS, P.Suite
local Native = { enabled = false, all = false }
P.NativeExperienceBar = Native
local states, managerAlpha, hiddenAlpha, alphaHooks = {}, {}, {}, {}
local cleanupFrame, cleanupOwner

local function CancelCleanup()
    cleanupOwner = nil
    if cleanupFrame then cleanupFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end

local function FinishCleanup(_, event)
    if NS.InCombat(event) then return end
    local owner = cleanupOwner
    CancelCleanup()
    if owner then Native.Sync(owner, false, event) end
end

local function DeferCleanup(self)
    cleanupOwner = self
    if not cleanupFrame then
        cleanupFrame = S.CreateFrame("Frame")
        cleanupFrame:SetScript("OnEvent", FinishCleanup)
    end
    cleanupFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Blizzard owns selection and container fades. Keep suppression in side
-- tables so late native/skin alpha writes cannot reveal hidden XP or chrome.
local function AlphaChanged(region, alpha)
    local record = hiddenAlpha[region]
    if not record or record.writing then return end
    -- The requested alpha may be secret: retain it only for restoration.
    record.alpha = alpha
    record.writing = true
    region:SetAlpha(0)
    record.writing = nil
end

local function Fade(region, saved)
    if not region then return end
    local record = saved[region]
    if record then return record end
    record = { alpha = region:GetAlpha(), writing = true }
    saved[region], hiddenAlpha[region] = record, record
    if not alphaHooks[region] then
        alphaHooks[region] = true
        hooksecurefunc(region, "SetAlpha", AlphaChanged)
    end
    region:SetAlpha(0)
    record.writing = nil
    return record
end

local function RestoreRegion(region, saved)
    local record = saved[region]
    -- Release before writing so the hook cannot suppress restoration.
    saved[region], hiddenAlpha[region] = nil, nil
    region:SetAlpha(record.alpha)
end

local function Restore(saved)
    for region in pairs(saved) do RestoreRegion(region, saved) end
end

local function Chrome(state, layoutChanged)
    local container = state.container
    local hidden = Native.enabled and (Native.all or container:GetShownBar() == state.xp)
    if hidden then
        if state.chromeHidden and not layoutChanged then return end
        Fade(container.BarFrameTexture, state.chrome)
        -- Forever's keyboard/gamepad layout also has pooled divider frames.
        local pool = container.HorizontalDividersPool
        if pool then
            for divider in pool:EnumerateActive() do Fade(divider, state.chrome) end
        end
    elseif state.chromeHidden then
        Restore(state.chrome)
    end
    state.chromeHidden = hidden
end

local function BarChanged(container)
    local state = states[container]
    if state and (Native.enabled or state.chromeHidden) then Chrome(state) end
end

local function LayoutChanged(container)
    local state = states[container]
    if state and (Native.enabled or state.chromeHidden) then Chrome(state, true) end
end

local function Adopt(container, xp)
    local state = states[container]
    if state then return state end
    state = { container = container, xp = xp, chrome = {}, bars = {} }
    states[container] = state
    -- XP:OnShow runs before shownBarIndex changes. This post-hook observes
    -- the final assignment, including a swap deferred by a native fade.
    hooksecurefunc(container, "ApplyPendingBarToShow", BarChanged)
    if container.UpdateDividers then hooksecurefunc(container, "UpdateDividers", LayoutChanged) end
    return state
end

local function HideMouse(frame)
    local saved = { frame = frame, click = frame:IsMouseClickEnabled(), motion = frame:IsMouseMotionEnabled() }
    frame:EnableMouse(false)
    return saved
end

local function RestoreMouse(saved)
    saved.frame:SetMouseClickEnabled(saved.click)
    saved.frame:SetMouseMotionEnabled(saved.motion)
end

local function SetBarHidden(state, bar, hidden)
    local saved = state.bars[bar]
    if hidden and not saved then
        saved = Fade(bar, state.bars)
        saved.mouse = HideMouse(bar)
        local tick = bar.ExhaustionTick or bar.Tick
        if tick then saved.tickMouse = HideMouse(tick) end
    elseif not hidden and saved then
        RestoreRegion(bar, state.bars)
        RestoreMouse(saved.mouse)
        if saved.tickMouse then RestoreMouse(saved.tickMouse) end
    end
end

local function SyncBars(state)
    for _, bar in pairs(state.container.bars) do
        SetBarHidden(state, bar, Native.enabled and (Native.all or bar == state.xp))
    end
end

function Native.Sync(self, enabled, event)
    -- Lifecycle/mouse changes wait for combat to end, including the early
    -- PLAYER_REGEN_DISABLED edge. Native swaps only use the alpha C sink.
    if NS.InCombat(event) or NS.IsCombatLocked() then
        -- Stop marks a failed module inactive before Disable. Core Apply
        -- cannot replay its cleanup, so a one-shot owned event returns it.
        if enabled == false then DeferCleanup(self) else S.Queue("xpBar") end
        return
    end
    CancelCleanup()
    Native.all = enabled == true and self.config.hideBlizzardTracking == true
    Native.enabled = enabled == true and (self.config.hideBlizzard == true or Native.all)
    if not Native.all then Restore(managerAlpha) end
    if Native.enabled then
        local manager, info = _G.StatusTrackingBarManager, _G.StatusTrackingBarInfo
        if not manager or not info then return end
        if Native.all then Fade(manager, managerAlpha) end
        for _, container in ipairs(manager.barContainers) do
            local xp = container.bars[info.BarsEnum.Experience]
            if xp then
                local state = Adopt(container, xp)
                SyncBars(state)
                Chrome(state)
            end
        end
    else
        for _, state in pairs(states) do
            SyncBars(state)
            Chrome(state)
        end
    end
end

function Native.AddonLoaded(self, _, addon)
    if addon == "Blizzard_ActionBar" or addon == "Blizzard_StatusTrackingBar" then Native.Sync(self, true) end
end
