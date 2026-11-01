local _, P = ...
local S = P.Suite
local Visuals = {}
P.GlimmerVisuals = Visuals
local SEGMENTS = 32
local TAU = math.pi * 2

function Visuals.Create(parent)
    local frame = S.CreateFrame("Frame", nil, parent or UIParent)
    frame:EnableMouse(false)
    if not parent then frame:SetFrameStrata("HIGH") end
    frame:Hide()
    frame.glow = S.CreateTexture(frame, nil, "OVERLAY")
    frame.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetAllPoints()
    frame.parts = {}
    for index = 1, SEGMENTS do
        local texture = S.CreateTexture(frame, nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        frame.parts[index] = texture
    end
    frame.pulse = frame:CreateAnimationGroup()
    frame.pulse:SetLooping("BOUNCE")
    local alpha = frame.pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(.45)
    alpha:SetToAlpha(1)
    alpha:SetDuration(.8)
    frame.fade = alpha
    return frame
end

local function Part(frame, index, x, y, width, height, rotation, r, g, b)
    local texture = frame.parts[index]
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", frame, "CENTER", x, y)
    texture:SetSize(width, height)
    texture:SetRotation(rotation or 0)
    texture:SetVertexColor(r, g, b)
    texture:Show()
end

local function Ring(frame, size, r, g, b, count)
    count = count or SEGMENTS
    local radius = size * .4
    for index = 1, count do
        local angle = TAU * index / count
        Part(frame, index, math.cos(angle) * radius, math.sin(angle) * radius,
            TAU * radius / count + 1, 2, angle + math.pi / 2, r, g, b)
    end
end

local function Sparkles(frame, size, r, g, b)
    for index = 1, 8 do
        local angle = TAU * index / 8
        local radius = size * (index % 2 == 0 and .34 or .22)
        local texture = frame.parts[index]
        texture:SetTexture("Interface\\Cooldown\\star4")
        texture:SetBlendMode("ADD")
        Part(frame, index, math.cos(angle) * radius, math.sin(angle) * radius,
            size * .23, size * .23, angle, r, g, b)
    end
end

function Visuals.Paint(frame, config)
    local size = config.size
    local r, g, b = S.RGB(config.color)
    frame:SetSize(size, size)
    frame:SetAlpha(config.opacity / 100)
    frame.fade:SetFromAlpha(config.opacity * .0045)
    frame.fade:SetToAlpha(config.opacity / 100)
    frame.glow:Hide()
    for _, texture in ipairs(frame.parts) do
        texture:Hide()
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetBlendMode("BLEND")
        texture:SetAlpha(1)
    end
    if config.style == 1 then
        frame.glow:SetVertexColor(r, g, b)
        frame.glow:Show()
    elseif config.style == 2 then
        Ring(frame, size, r, g, b)
    elseif config.style == 3 then
        Sparkles(frame, size, r, g, b)
    elseif config.style == 4 then
        Ring(frame, size * .65, r, g, b, 30)
        Part(frame, 31, 0, size * .45, 4, size * 1.4, 0, r, g, b)
        Part(frame, 32, 0, size * .45, 12, size * 1.4, 0, r, g, b)
        frame.parts[32]:SetAlpha(.25)
    else
        local edge, length = size * .4, size * .2
        for index = 1, 4 do
            local x = index % 2 == 0 and 1 or -1
            local y = index <= 2 and 1 or -1
            Part(frame, index * 2 - 1, x * (edge - length / 2), y * edge, length, 2, 0, r, g, b)
            Part(frame, index * 2, x * edge, y * (edge - length / 2), 2, length, 0, r, g, b)
        end
    end
end

function Visuals.Hide(frame)
    frame.pulse:Stop()
    frame:Hide()
    frame:ClearAllPoints()
end

function Visuals.Show(frame, plate, config)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", plate, "CENTER", 0, config.offsetY)
    Visuals.Paint(frame, config)
    if config.pulse then frame.pulse:Play() else frame.pulse:Stop() end
    frame:Show()
end

-- The menu draws the same effect on a harmless sample, without a target or CVars.
function S.DrawGlimmerPreview(parent, config, _, viewport)
    local host = parent.glimmerPreview
    if not host then
        host = S.CreateFrame("Frame", nil, parent)
        host.effect = Visuals.Create(host)
        host.sample = S.CreateTexture(host, nil, "ARTWORK")
        host.sample:SetTexture("Interface\\Cursor\\GatherHerbs")
        host.sample:SetSize(32, 32)
        host.sample:SetPoint("CENTER", host, "CENTER")
        host:EnableMouse(false)
        parent.glimmerPreview = host
    end
    local extent = config.size * 2 + math.abs(config.offsetY) * 2 + 40
    local scale = viewport.scale or 1
    local fit = math.min(1, (viewport.width - 24) / (extent * scale), (viewport.height - 24) / (extent * scale))
    host:SetSize(extent, extent)
    host:SetScale(scale * fit)
    Visuals.Show(host.effect, host, config)
    return host
end

function S.HideGlimmerPreview(parent)
    local host = parent.glimmerPreview
    if host then
        Visuals.Hide(host.effect)
        host:Hide()
    end
end
