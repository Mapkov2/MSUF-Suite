local _, P = ...
local NS, S = P.NS, P.Suite
local Native = { enabled = false }
P.NativeExperienceBar = Native
local states = {}
local cleanupFrame, cleanupOwner

local function CancelCleanup()
    cleanupOwner = nil
    if cleanupFrame then cleanupFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end

local function FinishCleanup()
    if NS.InCombat() then return end
    local owner = cleanupOwner
    CancelCleanup()
    if owner then Native.Sync(owner, false) end
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
    local hidden = Native.enabled and container:GetShownBar() == state.xp
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
    state = { container = container, xp = xp, chrome = {} }
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

local function HideXP(state)
    if state.saved then return end
    local xp, tick = state.xp, state.xp.ExhaustionTick
    local saved = { alpha = xp:GetAlpha(), mouse = HideMouse(xp) }
    if tick then saved.tickMouse = HideMouse(tick) end
    state.saved = saved
    xp:SetAlpha(0)
end

local function RestoreXP(state)
    local saved = state.saved
    if not saved then return end
    state.xp:SetAlpha(saved.alpha)
    RestoreMouse(saved.mouse)
    if saved.tickMouse then RestoreMouse(saved.tickMouse) end
    state.saved = nil
end

function Native.Sync(self, enabled)
    -- Lifecycle/mouse changes wait for combat to end, including the early
    -- PLAYER_REGEN_DISABLED edge. Native swaps only use the alpha C sink.
    if NS.InCombat() then
        -- Stop marks a failed module inactive before Disable. Core Apply
        -- cannot replay its cleanup, so a one-shot owned event returns it.
        if enabled == false then DeferCleanup(self) else S.Queue("xpBar") end
        return
    end
    CancelCleanup()
    Native.enabled = enabled == true and self.config.hideBlizzard == true
    if Native.enabled then
        local manager, info = _G.StatusTrackingBarManager, _G.StatusTrackingBarInfo
        if not manager or not info then return end
        for _, container in ipairs(manager.barContainers) do
            local xp = container.bars[info.BarsEnum.Experience]
            if xp then
                local state = Adopt(container, xp)
                HideXP(state)
                Chrome(state)
            end
        end
    else
        for _, state in pairs(states) do
            RestoreXP(state)
            Chrome(state)
        end
    end
end

function Native.AddonLoaded(self, _, addon)
    if addon == "Blizzard_ActionBar" or addon == "Blizzard_StatusTrackingBar" then Native.Sync(self, true) end
end
