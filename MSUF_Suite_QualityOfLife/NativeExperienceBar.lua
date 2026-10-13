local _, P = ...
local NS, S = P.NS, P.Suite
local Native = { enabled = false, all = false }
P.NativeExperienceBar = Native
local states, managerAlpha = {}, {}
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

-- Blizzard owns the shared containers, their fades and bar selection. Only
-- the XP child and the chrome of a container currently showing XP become
-- transparent. All snapshots live here, never on a Blizzard frame or table.
local function Fade(region, saved)
    if not region then return end
    local record = saved[region]
    if not record then
        record = { alpha = region:GetAlpha() }
        saved[region] = record
    end
    region:SetAlpha(0)
end

local function Restore(saved)
    for region, record in pairs(saved) do
        -- GetAlpha can be secret; its snapshot only returns to this C sink.
        region:SetAlpha(record.alpha)
        saved[region] = nil
    end
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
        saved = { alpha = bar:GetAlpha(), mouse = HideMouse(bar) }
        local tick = bar.ExhaustionTick or bar.Tick
        if tick then saved.tickMouse = HideMouse(tick) end
        state.bars[bar] = saved
        bar:SetAlpha(0)
    elseif not hidden and saved then
        bar:SetAlpha(saved.alpha)
        RestoreMouse(saved.mouse)
        if saved.tickMouse then RestoreMouse(saved.tickMouse) end
        state.bars[bar] = nil
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
