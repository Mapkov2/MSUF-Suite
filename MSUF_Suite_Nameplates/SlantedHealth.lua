local _, P = ...
local NS = P.NS
local Style = NS.NameplateStyle
local Gradient = Style.Gradient
local Slant = {}
P.SlantedHealth = Slant

local states = setmetatable({}, { __mode = "k" })
local overlays = setmetatable({}, { __mode = "k" })
Slant.CreateRim = Style.CreateShapeRim

local function NewMask(bar, writable, direction)
    return { mask = Style.CreateShapeMask(bar, direction), writable = writable, direction = direction }
end

local function ReplaceMask(state, key, region, mask, rebind)
    local previous = state[key]
    if previous == region and not (rebind and region) then return true end
    if previous and not state.writable(previous) or region and not state.writable(region) then return false end
    mask = mask or state.mask
    if previous then previous:RemoveMaskTexture(mask) end
    if region then region:AddMaskTexture(mask) end
    state[key] = region
    return true
end

local function MaskRegions(state, fill, back)
    local fillDone = ReplaceMask(state, "fill", fill)
    local backDone = ReplaceMask(state, "back", back)
    return fillDone and backDone
end

-- The cast outline owns this lease. Its callers use the existing protected
-- write guard and replay after a native change of cast texture.
function Slant.MaskCast(cast, lease, enabled, writable, mutable, direction)
    local state = lease.castMask
    if not enabled then return not state or MaskRegions(state) end
    local fill, back = cast:GetStatusBarTexture(), cast.Background
    if not NS.Public(fill) or not NS.Public(back) then return false end
    if state and state.fill == fill and state.back == back and state.direction == direction then return true end
    if mutable and not mutable(cast) then return false end
    if not state then
        state = NewMask(cast, writable, direction)
        lease.castMask = state
    elseif state.direction ~= direction then
        Style.SetShapeMaskMedia(state.mask, direction)
        state.direction = direction
    end
    return MaskRegions(state, fill, back)
end

local function BindVisual(state, health, visual)
    local active = state.active == true
    if active and visual.slantRim and visual.direction ~= state.direction then
        Style.SetShapeRimMedia(visual.slantRim, state.direction)
        visual.direction = state.direction
    end
    if active == (visual.slanted == true) and not state.visualPending then return true end
    local role = ReplaceMask(state, "role", active and visual.fill or nil, state.fillMask)
    local backdrop = ReplaceMask(state, "backdrop", active and visual.back or nil)
    state.visualPending = not (role and backdrop)
    if state.visualPending then return false end
    if active and not visual.slantRim then
        visual.slantRim = Slant.CreateRim(health, "OVERLAY", 7, state.direction)
        visual.direction = state.direction
    end
    visual.paintSlantedRim = active and Style.PaintSlantedRim or nil
    visual.slanted, visual.borderColor, visual.borderSize = active, nil, nil
    visual.slantMask = active and state.fillMask or nil
    if visual.gradient then Gradient.SetMask(visual.gradient, visual.slantMask) end
    if not active and visual.slantRim then visual.slantRim:Hide() end
    return true
end

local function ShapeChanged(enabled, direction, hover)
    return enabled ~= (Slant.enabled == true) or enabled and (Slant.direction ~= direction or Slant.hover ~= hover)
end

function Slant.SharedChanged(config)
    local enabled, direction, power, hover = Style.NameplateShapeSettings(config)
    return ShapeChanged(enabled, direction, hover) or enabled and Slant.power ~= power
end

function Slant.Configure(config)
    local enabled, direction, power, hover = Style.NameplateShapeSettings(config)
    local changed = ShapeChanged(enabled, direction, hover)
    Slant.enabled, Slant.direction, Slant.power, Slant.hover = enabled, direction, power, hover
    Slant.rounded = type(direction) == "table"
    return changed
end

local function MaskHealth(state, health, fill, back, reset)
    local fillDone = ReplaceMask(state, "fill", fill, state.fillMask)
    if fillDone and fill then
        Style.FitShapeFillMask(state, health, fill)
    elseif fillDone and state.fillAnchor then
        state.fillMask:ClearAllPoints()
        state.fillMask:SetAllPoints(health)
        state.fillAnchor, state.fillWidth = nil, nil
    end
    local backDone = ReplaceMask(state, "back", back, nil, reset)
    return fillDone and backDone
end

-- These native effects draw separate quads, including the selection
-- brighten and the aggro flash. Blizzard still owns their visibility.
local function MaskChrome(state, uf, health, enabled)
    local selection, dim, flash, border
    if enabled then
        selection, dim, flash, border = uf.selectionHighlight, health.deselectedOverlay, uf.aggroFlash, health.selectedBorder
        if not NS.Public(selection) or not NS.Public(dim) or not NS.Public(flash) or not NS.Public(border) then return false end
    end
    local selected = ReplaceMask(state, "selection", selection, state.fillMask)
    local dimmed = ReplaceMask(state, "dim", dim)
    local flashed = ReplaceMask(state, "flash", flash)
    local bordered = ReplaceMask(state, "nativeBorder", border)
    local regions = enabled and overlays[health]
    local hovered = ReplaceMask(state, "mouseHighlight", Slant.hover and regions and regions.mouseHighlight or nil)
    local patterned = ReplaceMask(state, "pattern", regions and regions.pattern or nil, state.fillMask)
    return selected and dimmed and flashed and bordered and hovered and patterned
end

-- Only publish a new overlay once it has the mask required by its plate.
-- The region stays here while a protected write is waiting for replay.
function Slant.AcquireOverlay(uf, health, key, create)
    local regions = overlays[health]
    if not regions then
        regions = {}
        overlays[health] = regions
    end
    local texture = regions[key]
    if not texture then
        texture = create(health)
        regions[key] = texture
    end
    local state = states[health]
    if not state or not state.active or key == "mouseHighlight" and not Slant.hover then return texture end
    local mask = key == "pattern" and state.fillMask or state.mask
    if ReplaceMask(state, key, texture, mask) then return texture end
    state.pending = true
    P.Textures.RetryShape(uf)
end

function Slant.OnLayout(uf)
    if not Slant.enabled then return end
    local bars = uf.HealthBarsContainer
    local health = bars and bars.healthBar
    if not NS.Public(health) or not health then return end
    local state = states[health]
    if state and state.active and state.fill and not NS.InCombat() and state.writable(health) then
        Style.FitShapeFillMask(state, health, state.fill)
    end
end

function Slant.FillMask(health)
    local state = states[health]
    return state and state.active and state.fillMask or nil
end

-- Clipping belongs to the texture lease, including pool reuse and restoration.
-- The native status bar continues to own and draw health and its reaction tint.
function Slant.Apply(uf, health, styled, writable, reset, visuals)
    if not NS.Public(health) then return false end
    if not health then return true end
    local state = states[health]
    local enabled = styled and Slant.enabled
    if enabled then
        local prefix = P.PlatePrefix(uf)
        enabled = prefix == "enemy" or Slant.rounded and prefix == "friendly"
    end
    if enabled then
        local nameOnly = P.HealthNameOnly(uf)
        enabled = NS.Public(nameOnly) and nameOnly ~= true
    end
    if not enabled and not state then return true end
    if not writable(health) then return false end
    local fill, back
    if enabled then
        fill, back = health:GetStatusBarTexture(), health.bgTexture
        if not NS.Public(fill) or not fill or not NS.Public(back) then return false end
    end
    if state and not state.pending and not state.visualPending and not reset and state.active == (enabled == true)
        and state.direction == Slant.direction and state.hover == Slant.hover
        and state.fill == fill and state.back == back then return true end
    if NS.InCombat() then
        local protected = uf:IsProtected()
        if not NS.Public(protected) or protected ~= false then return false end
    end
    if not state then
        state = NewMask(health, writable, Slant.direction)
        state.fillMask = Style.CreateShapeMask(health, Slant.direction)
        states[health] = state
    elseif state.direction ~= Slant.direction then
        state.direction = Slant.direction
        Style.SetShapeMaskMedia(state.mask, state.direction)
        Style.SetShapeMaskMedia(state.fillMask, state.direction)
    end
    state.hover = Slant.hover
    local healthDone = MaskHealth(state, health, fill, back, reset)
    local chromeDone = MaskChrome(state, uf, health, enabled)
    state.pending = not (healthDone and chromeDone)
    if state.pending then return false end
    local active = enabled == true
    if state.active ~= active then
        state.active = active
        local colors = P.AuraColors
        if colors then colors.SetSlantMask(uf, active and state.fillMask or nil) end
    end
    local visual = visuals and visuals[health]
    return not visual or BindVisual(state, health, visual)
end

function Slant.BindVisual(health, visual)
    local state = states[health]
    return not state or BindVisual(state, health, visual)
end
