local _, private = ...
local NS = private.NS
local Glow = {}
private.CastGlowStyle = Glow

local states = setmetatable({}, { __mode = "k" })
local SEGMENTS = 4

local function Accessible(region)
    if not NS.Public(region) or not region or NS.Safety.IsForbidden(region) then return false end
    if not region.CanBeAccessedInContext then return true end
    local allowed = region:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

local function Mutable(cast)
    if not Accessible(cast) then return false end
    if not NS.InCombat() then return true end
    local protected = cast:IsProtected()
    return NS.Public(protected) and protected == false
end

local function Stop(state)
    if not state.shown then return true end
    local overlay = state.overlay
    if not Accessible(overlay) then return false end
    if state.playing then
        state.animation:Stop()
        state.playing = nil
    end
    overlay:Hide()
    state.shown = nil
    return true
end

local function Remaining(cast)
    local shown, kind = cast:IsShown(), cast.barType
    if not NS.Public(shown) or not shown or not NS.Public(kind)
        or kind == "empowered" or kind == "interrupted" then return end
    local castActive, channel, empower = cast.casting, cast.channeling, cast.reverseChanneling
    if not NS.Public(castActive) or not NS.Public(channel) or not NS.Public(empower)
        or empower == true or not (castActive == true or channel == true) then return end
    -- The native driver counts down on channels and up on ordinary casts.
    local value, total = cast.value, cast.maxValue
    if not NS.Finite(value) or not NS.Finite(total) or total <= 0 then return end
    local remaining = channel == true and value or (total - value)
    if remaining > 0 then return math.min(remaining, total), total end
end

local function Build(cast, state)
    local overlay = cast:CreateTexture(nil, "ARTWORK", nil, 1)
    overlay:SetColorTexture(1, 1, 1, 1)
    overlay:SetBlendMode("BLEND")
    overlay:Hide()
    local group = overlay:CreateAnimationGroup()
    group:SetScript("OnFinished", function()
        state.playing = nil
        Stop(state)
    end)
    state.overlay, state.animation = overlay, group
    for i = 1, SEGMENTS do
        local step = group:CreateAnimation("Alpha")
        step:SetOrder(i)
        state[i] = step
    end
end

local function Anchor(state, fill, reset)
    if not Accessible(fill) or not Accessible(state.overlay) then return false end
    if reset or state.fill ~= fill then
        state.overlay:ClearAllPoints()
        state.overlay:SetAllPoints(fill)
        state.fill = fill
    end
    return true
end

local function Refresh(cast, state)
    local remaining, total = Remaining(cast)
    if not remaining then return Stop(state) end
    local fill = cast:GetStatusBarTexture()
    if not Accessible(fill) then
        Stop(state)
        return false
    end
    if not state.overlay then Build(cast, state) end
    if not Stop(state) or not Anchor(state, fill) then return false end
    -- Four native linear steps approximate the core's squared ramp.
    local progress = 1 - remaining / total
    local duration = remaining / SEGMENTS
    local delta = (1 - progress) / SEGMENTS
    for i = 1, SEGMENTS do
        local step = state[i]
        local nextProgress = i == SEGMENTS and 1 or progress + delta
        step:SetFromAlpha(progress * progress)
        step:SetToAlpha(nextProgress * nextProgress)
        step:SetDuration(duration)
        progress = nextProgress
    end
    state.playing, state.shown = true, true
    state.overlay:Show()
    state.animation:Play()
    return true
end

local function OnTimingChanged(cast)
    local state = NS.Public(cast) and cast and states[cast]
    if not state or not state.enabled then return end
    if Mutable(cast) then Refresh(cast, state) else Stop(state) end
end

local function OnNativeEnd(cast)
    local state = NS.Public(cast) and cast and states[cast]
    if state and state.shown then Stop(state) end
end

local function OnTextureChanged(cast)
    local state = NS.Public(cast) and cast and states[cast]
    if state and state.playing and (not Mutable(cast) or not Anchor(state, cast:GetStatusBarTexture())) then
        Stop(state)
    end
end

function Glow.Restore(cast)
    local state = NS.Public(cast) and cast and states[cast]
    if not state then return true end
    state.enabled = nil
    return Stop(state)
end

function Glow.Apply(cast, settings, reset)
    if not settings or settings.glow ~= true then return Glow.Restore(cast) end
    if not Mutable(cast) then return false end
    local state = states[cast]
    if not state then
        state = {}
        states[cast] = state
        hooksecurefunc(cast, "HandleCastStart", OnTimingChanged)
        hooksecurefunc(cast, "HandleCastDelayed", OnTimingChanged)
        hooksecurefunc(cast, "HandleChannelUpdateDelayed", OnTimingChanged)
        hooksecurefunc(cast, "SetStatusBarTexture", OnTextureChanged)
        hooksecurefunc(cast, "PlayFadeAnim", OnNativeEnd)
        hooksecurefunc(cast, "PlayInterruptAnims", OnNativeEnd)
        cast:HookScript("OnHide", OnNativeEnd)
    end
    state.enabled = true
    if not state.playing then return Refresh(cast, state) end
    if reset and not Anchor(state, cast:GetStatusBarTexture(), true) then
        Stop(state)
        return false
    end
    return true
end
