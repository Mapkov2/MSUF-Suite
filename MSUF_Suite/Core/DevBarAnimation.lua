local _, Suite = ...
local Text = Suite.DevBarAnimationText
local Animation = {}
Suite.DevBarAnimation = Animation

local SAMPLE_INTERVAL = 0.25
local CYCLE = 3
local TEXT_INTERVAL = 1 / 30
local driver, selectedKind, oneAtATime, elapsed, nextSample
local animateText, nextText = false, 0
local bars, owners, categories, seen, active, surfaces
local gradientDirections = { "left", "right", "up", "down" }
local kinds = { all = true, health = true, power = true, class = true, cast = true, swing = true }

-- The real StatusBar keeps receiving gameplay values and native timers.
-- Stop the temporary alpha animation to reveal its current fill immediately.
local function Hide(surface)
    surface.overlay:Hide()
    surface.mute:Stop()
    local muted = surface.gradientMutes
    if muted then
        for i, group in pairs(muted) do
            group:Stop()
            muted[i] = nil
        end
    end
end

function Animation.Stop()
    if not selectedKind then return end
    selectedKind = nil
    driver:SetScript("OnUpdate", nil)
    driver:UnregisterAllEvents()
    for source, surface in pairs(active) do
        Hide(surface)
        active[source] = nil
    end
    Text.Clear()
    wipe(bars)
    wipe(owners)
    wipe(categories)
    wipe(seen)
end

function Animation.IsRunning()
    return selectedKind ~= nil
end

function Animation.IsTextEnabled()
    return animateText
end

function Animation.SetTextEnabled(value)
    animateText = value == true
    if not animateText then Text.Clear() end
    nextSample, nextText = 0, 0
end

local function CreateOverlay(source)
    local overlay = CreateFrame("StatusBar", nil, source)
    if overlay:IsProtected() then return false end
    overlay:Hide()
    overlay:EnableMouse(false)
    overlay:SetAllPoints(source)
    overlay:SetMinMaxValues(0, 1)
    return overlay
end

local function MuteRegion(region)
    local group = region:CreateAnimationGroup()
    group:SetToFinalAlpha(false)
    group:SetLooping("REPEAT")
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(0)
    alpha:SetDuration(1)
    return group
end

local function SourceFill(source)
    if not Suite.Public(source) or not source or source:IsForbidden() then return end
    local visible, opacity = source:IsVisible(), source:GetEffectiveAlpha()
    if not Suite.Public(visible) or not visible or not Suite.Finite(opacity) or opacity <= 0 then return end
    local fill = source:GetStatusBarTexture()
    if Suite.Public(fill) and fill and not Suite.Safety.IsForbidden(fill) then return fill end
end

local function Asset(fill)
    local asset = fill:GetTexture()
    if not Suite.Public(asset) then return end
    if type(asset) == "string" or type(asset) == "number" then return asset end
end

local function CanPaintChannel(value, allowSecret)
    return Suite.Finite(value) or (allowSecret and Suite.IsSecret(value))
end

local function MirrorStyle(surface, source, fill, alpha, hasHealthTint, allowSecret)
    local overlay = surface.overlay
    local asset = Asset(fill)
    local level = source:GetFrameLevel()
    local orientation, reversed, rotates = source:GetOrientation(), source:GetReverseFill(), source:GetRotatesTexture()
    if not asset
        or not Suite.Finite(level) or not CanPaintChannel(alpha, allowSecret)
        or (not Suite.IsSecret(alpha) and alpha <= 0)
        or not (Suite.Public(orientation) and Suite.Public(reversed) and Suite.Public(rotates)) then return false end
    local r, g, b, a
    if not hasHealthTint then
        r, g, b, a = fill:GetVertexColor()
        if not (CanPaintChannel(r, allowSecret) and CanPaintChannel(g, allowSecret)
            and CanPaintChannel(b, allowSecret) and CanPaintChannel(a, allowSecret)) then return false end
    end
    if surface.asset ~= asset then
        if not overlay:SetStatusBarTexture(asset) then return false end
        surface.asset = asset
    end
    if not hasHealthTint then overlay:SetStatusBarColor(r, g, b, a) end
    overlay:SetFrameLevel(level)
    overlay:SetOrientation(orientation)
    overlay:SetReverseFill(reversed)
    overlay:SetRotatesTexture(rotates)
    overlay:GetStatusBarTexture():SetAlpha(alpha)
    return true
end

local function UpdateGradientLayer(surface, muted, i, liveRegion, demoRegion, alpha)
    local group
    if demoRegion and demoRegion:IsShown() then
        demoRegion:SetAlpha(alpha)
        if Suite.Public(liveRegion) and liveRegion and not Suite.Safety.IsForbidden(liveRegion) then
            group = surface.mutes[liveRegion] or MuteRegion(liveRegion)
            surface.mutes[liveRegion] = group
        end
    end
    local previous = muted[i]
    if previous ~= group then
        if previous then previous:Stop() end
        muted[i] = group
    end
    if group and not group:IsPlaying() then group:Play() end
end

local function ApplyGradientArt(surface, apply, spec, live, alpha)
    if not ((spec and spec.enabled == true) or surface.gradients) then return end
    local demo = apply(surface, surface.overlay, spec, "gradients")
    local muted = surface.gradientMutes or {}
    surface.gradientMutes = muted
    for i = 1, #gradientDirections do
        local key = gradientDirections[i]
        UpdateGradientLayer(surface, muted, i, live and live[key], demo and demo[key], alpha)
    end
end

local function Paint(surface, progress)
    if surface.tint then
        local r, g, b = surface.tint(surface.health, progress)
        surface.overlay:SetStatusBarColor(r, g, b, 1)
    end
    surface.overlay:SetValue(progress)
end

local function Show(index, progress)
    local source = bars[index]
    local fill = SourceFill(source)
    if not fill then return end

    local surface = surfaces[source]
    if surface == false then return end
    if not surface then
        local overlay = CreateOverlay(source)
        if not overlay then
            surfaces[source] = false
            return
        end
        surface = { overlay = overlay, mutes = {} }
        surfaces[source] = surface
    end
    local kind, owner = categories[index], owners[index]
    local tint, health, applyArt, liveGradients
    if kind == "health" or kind == "playerHealth" then
        tint, health, applyArt, liveGradients = Suite.HostBridge.LiveHealthStyle(owner, kind == "playerHealth")
    end
    -- Sample base alpha before applying our own native alpha animation.
    local alpha
    if surface.fill == fill and active[source] then alpha = surface.alpha else alpha = fill:GetAlpha() end
    local gradient = health and health.barGradient
    local allowSecret = tint ~= nil or (applyArt and gradient and gradient.enabled == true)
    if not MirrorStyle(surface, source, fill, alpha, tint, allowSecret) then return end
    surface.alpha, surface.tint, surface.health = alpha, tint, health
    if surface.fill ~= fill then
        local mute = surface.mutes[fill] or MuteRegion(fill)
        if surface.mute then surface.mute:Stop() end
        surface.mutes[fill], surface.mute, surface.fill = mute, mute, fill
    end
    Paint(surface, progress)
    if not active[source] then
        active[source] = surface
        surface.overlay:Show()
        surface.mute:Play()
    elseif not surface.mute:IsPlaying() then
        surface.mute:Play()
    end
    seen[source] = true
    if applyArt then
        ApplyGradientArt(surface, applyArt, gradient, liveGradients, alpha)
    end
    if animateText then
        Text.Bind(owner, source, kind, progress, oneAtATime, CYCLE / 2, MuteRegion)
    end
end

local function Collect(source, owner, kind)
    local fill = SourceFill(source)
    if not fill or seen[source] or not Asset(fill) then return end
    seen[source] = true
    local index = #bars + 1
    bars[index], owners[index], categories[index] = source, owner, kind
end

local function Refresh(progress, cycle)
    wipe(bars)
    wipe(owners)
    wipe(categories)
    wipe(seen)
    Suite.HostBridge.VisitLiveBars(selectedKind, Collect)
    wipe(seen)
    if animateText then Text.BeginSample() end
    if oneAtATime and #bars > 0 then
        Show(cycle % #bars + 1, progress)
    else
        for i = 1, #bars do Show(i, progress) end
    end
    for source, surface in pairs(active) do
        if not seen[source] then
            Hide(surface)
            active[source] = nil
        end
    end
    if animateText then Text.EndSample() end
end

local function Update(_, delta)
    if Suite.InCombat() or Suite.HostBridge.IsBarPreviewActive() then
        Animation.Stop()
        return
    end
    elapsed = elapsed + delta
    local cycle = math.floor(elapsed / CYCLE)
    local progress = 1 - math.abs(elapsed % CYCLE * (2 / CYCLE) - 1)
    if elapsed >= nextSample then
        nextSample = elapsed + SAMPLE_INTERVAL
        if not Suite.Dispatch(Suite.Finish, Refresh, progress, cycle) then Animation.Stop() end
    else
        for _, surface in pairs(active) do Paint(surface, progress) end
        if animateText and elapsed >= nextText then
            nextText = elapsed + TEXT_INTERVAL
            Text.Write(progress)
        end
    end
end

function Animation.Start(kind, sequential)
    if Suite.IsSecret(kind) or not kinds[kind] then return false, "invalid" end
    Animation.Stop()
    if Suite.InCombat() then return false, "combat" end
    if Suite.HostBridge.IsBarPreviewActive() then return false, "preview" end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnEvent", Animation.Stop)
        bars, owners, categories, seen, active, surfaces = {}, {}, {}, {}, {}, {}
    end
    selectedKind, oneAtATime, elapsed, nextSample, nextText = kind, sequential, 0, 0, 0
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnUpdate", Update)
    Update(driver, 0)
    return Animation.IsRunning()
end
