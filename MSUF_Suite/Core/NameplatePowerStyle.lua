local _, NS = ...
local Style = NS.NameplateStyle
local Gradient = Style.Gradient

-- The enemy resource row is Suite-owned. Runtime and preview use the same
-- art and anchors, with the cast container reserving the native cast space.
local EnemyPower, NO_ENEMY_POWER = {}, { enabled = false }
Style.EnemyPower = EnemyPower
local POWER_WHITE = "Interface\\Buttons\\WHITE8X8"
local RESOURCES = {
    [2] = { "Mana", "MANA" }, [3] = { "Rage", "RAGE" }, [4] = { "Focus", "FOCUS" },
    [5] = { "Energy", "ENERGY" }, [6] = { "RunicPower", "RUNIC_POWER" },
}

function EnemyPower.Resource(choice)
    local resource = RESOURCES[choice or 1]
    if resource then return Enum.PowerType[resource[1]], resource[2] end
end

local function PowerNumber(value, fallback, minimum, maximum)
    if not NS.Finite(value) then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

function EnemyPower.Plan(config, previous)
    local enabled = config.enemyPowerEnabled == true and config.enemy == true and config.look ~= 2
    if not enabled then return NO_ENEMY_POWER end
    local chunked = config.enemyPowerChunked == true
    local smooth = not chunked and config.enemyPowerSmooth ~= false
    local placement = config.enemyPowerDetached and 3 or config.enemyPowerEmbed and 2 or 1
    local source = config.enemyPowerSource or 1
    local detachedWidth = PowerNumber(config.enemyPowerDetachedWidth, 0, 0, 800)
    local detachedHeight = PowerNumber(config.enemyPowerDetachedHeight, 6, 2, 80)
    local layer = placement == 3 and PowerNumber(config.enemyPowerDetachedLayer, 6, 0, 30) or placement == 2 and 2 or 0
    local border = config.enemyPowerBorder and PowerNumber(config.enemyPowerBorderSize, 1, 0, 6) or 0
    local borderColor = config.enemyPowerBorderColor or "000000"
    local lossColor = config.enemyPowerLossColor or "ffffff"
    local byType = config.enemyPowerByType ~= false
    local width = PowerNumber(config.enemyPowerWidth, 0, -20, 120)
    local height = PowerNumber(config.enemyPowerHeight, 4, 2, 18)
    local x = PowerNumber(config.enemyPowerOffsetX, 0, -2048, 2048)
    local y = PowerNumber(config.enemyPowerOffsetY, 0, -2048, 2048)
    local color = config.enemyPowerColor or "337be6"
    local background = config.enemyPowerBackgroundColor or "10151d"
    local alpha = PowerNumber(config.enemyPowerBackgroundAlpha, 80, 0, 100) / 100
    local fillKey, backgroundTextureKey = config.powerFillTexture or "", config.powerBackgroundTexture or ""
    local gradient = Gradient and Gradient.Plan(config, "power", previous and previous.gradient)
    if previous and previous.enabled and previous.smooth == smooth and previous.chunked == chunked
        and previous.placement == placement and previous.source == source and previous.layer == layer
        and previous.detachedWidth == detachedWidth and previous.detachedHeight == detachedHeight
        and previous.border == border and previous.borderColor == borderColor and previous.lossColor == lossColor
        and previous.byType == byType
        and previous.width == width and previous.height == height and previous.x == x and previous.y == y
        and previous.colorKey == color and previous.gradient == gradient
        and previous.backgroundKey == background and previous.backgroundAlpha == alpha
        and previous.fillKey == fillKey and previous.backgroundTextureKey == backgroundTextureKey then
        return previous
    end
    return {
        enabled = true,
        smooth = smooth,
        chunked = chunked,
        placement = placement,
        source = source,
        detachedWidth = detachedWidth,
        detachedHeight = detachedHeight,
        layer = layer,
        border = border,
        borderColor = borderColor,
        lossColor = lossColor,
        interpolation = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut or nil,
        byType = byType,
        width = width,
        height = height,
        x = x,
        y = y,
        colorKey = color,
        color = { NS.RGB(color) },
        backgroundKey = background,
        background = { NS.RGB(background) },
        backgroundAlpha = alpha,
        fillKey = fillKey,
        backgroundTextureKey = backgroundTextureKey,
        fillTexture = NS.ResolveTexture(fillKey) or POWER_WHITE,
        backgroundTexture = NS.ResolveTexture(backgroundTextureKey),
        gradient = gradient,
    }
end

function EnemyPower.Create(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:EnableMouse(false)
    bar:Hide()
    bar:SetStatusBarTexture(POWER_WHITE)
    bar.enemyPowerBackground = bar:CreateTexture(nil, "BACKGROUND")
    bar.enemyPowerBackground:SetAllPoints(bar)
    return bar
end

function EnemyPower.Height(plan)
    return plan.placement == 3 and plan.detachedHeight or plan.height
end

function EnemyPower.GeometryChanged(previous, plan)
    return not previous or previous.placement ~= plan.placement or previous.width ~= plan.width
        or previous.x ~= plan.x or previous.y ~= plan.y or previous.detachedWidth ~= plan.detachedWidth
        or previous.layer ~= plan.layer
end

function EnemyPower.Place(bar, health, bottom, plan)
    local halfWidth = plan.placement == 3 and 0 or plan.width / 2
    bar:ClearAllPoints()
    if plan.placement == 3 and plan.detachedWidth > 0 then
        bar:SetPoint("CENTER", health, "CENTER", plan.x, plan.y)
        bar:SetWidth(plan.detachedWidth)
        return
    end
    if plan.placement == 3 then
        bar:SetPoint("LEFT", health, "LEFT", plan.x - halfWidth, plan.y)
        bar:SetPoint("RIGHT", health, "RIGHT", plan.x + halfWidth, plan.y)
        return
    elseif plan.placement == 2 then
        bar:SetPoint("BOTTOM", health, "BOTTOM", 0, plan.y)
    else
        bar:SetPoint("TOP", bottom, "BOTTOM", 0, plan.y - 1)
    end
    bar:SetPoint("LEFT", health, "LEFT", plan.x - halfWidth, 0)
    bar:SetPoint("RIGHT", health, "RIGHT", plan.x + halfWidth, 0)
end

function EnemyPower.Paint(bar, plan, r, g, b)
    local previous = bar.enemyPowerPlan
    if previous ~= plan then
        bar.enemyPowerPlan = plan
        if previous and previous.fillTexture ~= plan.fillTexture or not previous and plan.fillTexture ~= POWER_WHITE then
            local fill = bar:GetStatusBarTexture()
            fill:SetTexture(plan.fillTexture)
        end
        if plan.gradient or bar.powerGradient then
            bar.powerGradient = Gradient.Paint(bar, bar.powerGradient, bar:GetStatusBarTexture(), plan.gradient)
        end
        local height = EnemyPower.Height(plan)
        if not previous or EnemyPower.Height(previous) ~= height then bar:SetHeight(height) end
        if (previous and previous.layer or 0) ~= plan.layer then
            bar.enemyPowerBaseLevel = bar.enemyPowerBaseLevel or bar:GetFrameLevel()
            bar:SetFrameLevel(bar.enemyPowerBaseLevel + plan.layer)
        end
        if plan.border > 0 and not bar.enemyPowerBorder then bar.enemyPowerBorder = Style.CreateBorder(bar) end
        if bar.enemyPowerBorder then Style.PaintBorder(bar.enemyPowerBorder, bar, plan.border, plan.borderColor) end
        if not previous or previous.backgroundKey ~= plan.backgroundKey or previous.backgroundAlpha ~= plan.backgroundAlpha
            or previous.backgroundTexture ~= plan.backgroundTexture then
            local background = plan.background
            local texture = bar.enemyPowerBackground
            if plan.backgroundTexture then
                texture:SetTexture(plan.backgroundTexture)
                texture:SetVertexColor(background[1], background[2], background[3], plan.backgroundAlpha)
            else
                texture:SetVertexColor(1, 1, 1, 1)
                texture:SetColorTexture(background[1], background[2], background[3], plan.backgroundAlpha)
            end
        end
    end
    if r == nil then r, g, b = unpack(plan.color) end
    if bar.enemyPowerR ~= r or bar.enemyPowerG ~= g or bar.enemyPowerB ~= b then
        bar:SetStatusBarColor(r, g, b)
        bar.enemyPowerR, bar.enemyPowerG, bar.enemyPowerB = r, g, b
    end
end

local function NewLoss(bar)
    local trail = CreateFrame("StatusBar", nil, bar)
    trail:EnableMouse(false)
    trail:SetAllPoints(bar)
    trail:SetStatusBarTexture(POWER_WHITE)
    local fill = trail:GetStatusBarTexture()
    fill:SetBlendMode("ADD")
    local clip = trail:CreateMaskTexture()
    clip:SetTexture(POWER_WHITE)
    clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    fill:AddMaskTexture(clip)
    local animation = trail:CreateAnimationGroup()
    local fade = animation:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.4)
    fade:SetDuration(0.6)
    animation:SetScript("OnFinished", function() trail:Hide() end)
    trail:Hide()
    return { bar = trail, animation = animation }
end

function EnemyPower.StopLoss(bar)
    local trail = bar.enemyPowerLoss
    if trail then
        trail.animation:Stop()
        trail.bar:Hide()
    end
end

function EnemyPower.LossRange(bar, maximum)
    local trail = bar.enemyPowerLoss
    if trail then trail.bar:SetMinMaxValues(0, maximum) end
end

function EnemyPower.PaintLoss(bar, plan, maximum)
    if not plan.chunked then
        if bar.enemyPowerLoss then EnemyPower.StopLoss(bar) end
        return
    end
    local trail = bar.enemyPowerLoss
    if not trail then
        trail = NewLoss(bar)
        bar.enemyPowerLoss = trail
        EnemyPower.LossRange(bar, maximum)
    end
    if trail.color ~= plan.lossColor then
        trail.color = plan.lossColor
        trail.bar:SetStatusBarColor(NS.RGB(plan.lossColor))
    end
end

function EnemyPower.PreviewLoss(bar, plan, power)
    if not plan.chunked and not bar.enemyPowerLoss then return end
    EnemyPower.PaintLoss(bar, plan, 100)
    if plan.chunked then
        local trail = bar.enemyPowerLoss.bar
        trail:SetValue(math.min(100, power + 24))
        trail:Show()
    end
end

function EnemyPower.SnapshotLoss(bar, value)
    local trail = bar.enemyPowerLoss
    if not trail or trail.animation:IsPlaying() then return end
    local old = bar:GetValue()
    if NS.Public(old) and NS.Public(value) and old <= value then return end
    trail.bar:SetValue(old)
    trail.bar:Show()
    trail.animation:Play()
end

function EnemyPower.TextValue(mode)
    if mode == 2 then return true, false, "%d / %d" end
    if mode == 3 then return false, true, "%.0f%%" end
    return false, false, "%d"
end

function EnemyPower.PaintText(bar, config, font)
    local label = bar.enemyPowerText
    if config.enemyPowerTextVisible ~= true then
        if label then label:Hide() end
        return
    end
    if not label then
        label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bar.enemyPowerText = label
    end
    local anchor = NS.AnchorPoints[config.enemyPowerTextAnchor or 5]
    label:ClearAllPoints()
    label:SetPoint(anchor, bar, anchor, config.enemyPowerTextOffsetX or 0, config.enemyPowerTextOffsetY or 0)
    label:SetFont(font, config.enemyPowerTextSize or 10, "OUTLINE")
    label:SetTextColor(NS.RGB(config.enemyPowerTextColor or "ffffff"))
    label:Show()
    return label
end

function EnemyPower.SetValue(bar, value, interpolation)
    interpolation = interpolation or Enum.StatusBarInterpolation.Immediate
    if not NS.Public(value) then
        bar.enemyPowerValue = nil
        bar:SetValue(value, interpolation)
    elseif bar.enemyPowerValue ~= value or bar.enemyPowerInterpolation ~= interpolation then
        bar.enemyPowerValue, bar.enemyPowerInterpolation = value, interpolation
        bar:SetValue(value, interpolation)
    end
end
