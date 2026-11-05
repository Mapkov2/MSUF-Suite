local _, P = ...
local S = P.Suite
local Visuals = {}
P.GlimmerVisuals = Visuals
local SEGMENTS = 32
local TAU = math.pi * 2

local HALO = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR = "Interface\\Cooldown\\star4"
local GLINTS = {
    { -.28, -.15, .17 }, { .12, -.28, .12 }, { .30, -.02, .20 }, { -.10, .10, .13 },
    { .20, .22, .16 }, { -.32, .26, .11 }, { .02, .37, .14 }, { .34, .34, .10 },
}

local function CreateGlints(frame)
    frame.glints = {}
    for index = 1, #GLINTS do
        local texture = frame.parts[index]
        local group = texture:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local delay = (index - 1) * .13
        local rise = group:CreateAnimation("Translation")
        rise:SetOrder(1)
        rise:SetDuration(.70 + index * .025)
        rise:SetStartDelay(delay)
        local brighten = group:CreateAnimation("Alpha")
        brighten:SetOrder(1)
        brighten:SetStartDelay(delay)
        brighten:SetFromAlpha(0)
        brighten:SetToAlpha(.9)
        brighten:SetDuration(.18)
        local fade = group:CreateAnimation("Alpha")
        fade:SetOrder(2)
        fade:SetFromAlpha(.9)
        fade:SetToAlpha(0)
        fade:SetDuration(.45 + index * .035)
        frame.glints[index] = { group = group, rise = rise }
    end
end

function Visuals.Create(parent)
    local frame = S.CreateFrame("Frame", nil, parent or UIParent)
    frame:EnableMouse(false)
    if not parent then frame:SetFrameStrata("BACKGROUND") end
    frame:Hide()
    frame.glow = S.CreateTexture(frame, nil, "OVERLAY")
    local halo = GetFileIDFromPath(HALO)
    frame.glow:SetTexture(S.Finite(halo) and halo > 0 and halo or STAR)
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetPoint("CENTER", frame, "CENTER")
    frame.parts = {}
    for index = 1, SEGMENTS do
        local texture = S.CreateTexture(frame, nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        frame.parts[index] = texture
    end
    CreateGlints(frame)
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
    for index, glint in ipairs(GLINTS) do
        local texture = frame.parts[index]
        texture:SetTexture(STAR)
        texture:SetBlendMode("ADD")
        Part(frame, index, glint[1] * size, glint[2] * size,
            size * glint[3], size * glint[3], 0, r, g, b)
        frame.glints[index].rise:SetOffset(0, size * .20)
    end
end

local function Stop(frame)
    frame.pulse:Stop()
    for _, glint in ipairs(frame.glints) do glint.group:Stop() end
end

local function Animate(frame, config)
    if not config.pulse then
        Stop(frame)
        for index = 1, #GLINTS do frame.parts[index]:SetAlpha(1) end
        return
    end
    frame.pulse:Play()
    if config.style == 1 or config.style == 3 then
        for index, glint in ipairs(frame.glints) do
            frame.parts[index]:SetAlpha(0)
            glint.group:Play()
        end
    end
end

function Visuals.Paint(frame, config)
    Stop(frame)
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
        frame.glow:SetSize(size * 1.4, size * 1.4)
        frame.glow:SetAlpha(.30)
        frame.glow:Show()
        Sparkles(frame, size, r, g, b)
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
    if not frame.active then return end
    Stop(frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame.active, frame.anchor = nil, nil
end

function Visuals.Show(frame, plate, config)
    local changed = frame.style ~= config.style or frame.size ~= config.size
        or frame.color ~= config.color or frame.opacity ~= config.opacity
    if frame.anchor ~= plate or frame.offsetY ~= config.offsetY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", plate, "CENTER", 0, config.offsetY)
        frame.anchor, frame.offsetY = plate, config.offsetY
    end
    if changed then
        Visuals.Paint(frame, config)
        frame.style, frame.size, frame.color, frame.opacity = config.style, config.size, config.color, config.opacity
    end
    if changed or not frame.active or frame.animated ~= config.pulse then
        Animate(frame, config)
        frame.animated = config.pulse
    end
    if not frame.active then frame:Show() end
    frame.active = true
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
