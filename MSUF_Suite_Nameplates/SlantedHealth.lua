local _, P = ...
local NS = P.NS
local Style = NS.NameplateStyle
local Gradient = Style.Gradient
local Slant = {}
P.SlantedHealth = Slant

local states = setmetatable({}, { __mode = "k" })
Slant.CreateRim = Style.CreateSlantedRim

local function NewMask(bar, writable)
    return { mask = Style.CreateSlantedMask(bar), writable = writable }
end

local function ReplaceMask(state, key, region, mask)
    local previous = state[key]
    if previous == region then return true end
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
function Slant.MaskCast(cast, lease, enabled, writable, mutable)
    local state = lease.castMask
    if not enabled then return not state or MaskRegions(state) end
    local fill, back = cast:GetStatusBarTexture(), cast.Background
    if not NS.Public(fill) or not NS.Public(back) then return false end
    if state and state.fill == fill and state.back == back then return true end
    if mutable and not mutable(cast) then return false end
    if not state then
        state = NewMask(cast, writable)
        lease.castMask = state
    end
    return MaskRegions(state, fill, back)
end

local function PaintVisual(state, health, visual)
    state.visual = visual
    local active = state.active == true
    if active == (visual.slanted == true) then return end
    ReplaceMask(state, "role", active and visual.fill or nil, state.fillMask)
    ReplaceMask(state, "backdrop", active and visual.back or nil)
    if active and not visual.slantRim then
        visual.slantRim = Slant.CreateRim(health, "OVERLAY", 7)
        visual.paintSlantedRim = Style.PaintSlantedRim
    end
    visual.slanted, visual.borderColor = active, nil
    visual.slantMask = active and state.fillMask or nil
    if visual.gradient then Gradient.SetMask(visual.gradient, visual.slantMask) end
    if not active and visual.slantRim then visual.slantRim:Hide() end
end

function Slant.Configure(config)
    local enabled = config.look ~= 2 and config.enemySlantedHealth == true
    local changed = enabled ~= (Slant.enabled == true)
    Slant.enabled = enabled
    return changed
end

local function MaskHealth(state, health, fill, back)
    local fillDone = ReplaceMask(state, "fill", fill, state.fillMask)
    if fillDone and fill then
        Style.FitSlantedFillMask(state, health, fill)
    elseif fillDone and state.fillAnchor then
        state.fillMask:ClearAllPoints()
        state.fillMask:SetAllPoints(health)
        state.fillAnchor, state.fillWidth = nil, nil
    end
    local backDone = ReplaceMask(state, "back", back)
    return fillDone and backDone
end

function Slant.OnLayout(uf)
    if not Slant.enabled then return end
    local bars = uf.HealthBarsContainer
    local health = bars and bars.healthBar
    if not NS.Public(health) or not health then return end
    local state = states[health]
    if state and state.active and state.fill and not NS.InCombat() and state.writable(health) then
        Style.FitSlantedFillMask(state, health, state.fill)
    end
end

function Slant.FillMask(health)
    local state = states[health]
    return state and state.active and state.fillMask or nil
end

-- Clipping belongs to the texture lease, including pool reuse and restoration.
-- The native status bar continues to own and draw health and its reaction tint.
function Slant.Apply(uf, health, styled, writable)
    if not NS.Public(health) then return false end
    if not health then return true end
    local state = states[health]
    local enabled = styled and Slant.enabled and P.PlatePrefix(uf) == "enemy"
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
    if state and state.active == (enabled == true) and state.fill == fill and state.back == back then return true end
    if NS.InCombat() then
        local protected = uf:IsProtected()
        if not NS.Public(protected) or protected ~= false then return false end
    end
    if not state then
        state = NewMask(health, writable)
        state.fillMask = Style.CreateSlantedMask(health)
        states[health] = state
    end
    if not MaskHealth(state, health, fill, back) then return false end
    state.active = enabled == true
    if state.visual then PaintVisual(state, health, state.visual) end
    return true
end

function Slant.Visual(health, visual)
    local state = states[health]
    if state then PaintVisual(state, health, visual) end
end
