local _, private = ...
local NS = private.NS
local Style = NS.NameplateStyle
local Power = {}
private.Power = Power

local owner
local visuals = setmetatable({}, { __mode = "k" })
local hooked

local function Requested()
    local config = owner and owner.config
    return owner and owner.active and config.look ~= 2
        and (config.personalPowerSkin or (config.personalPowerOffsetX or 0) ~= 0
            or (config.personalPowerOffsetY or 0) ~= 0)
end

local function Accessible(bar)
    return bar and not NS.Safety.IsForbidden(bar)
end

local function Paint(bar, force, targetX, targetY)
    if not Accessible(bar) then return end
    local config = owner.config
    local active = owner.active and config.look ~= 2
    local x = active and (targetX or 0) or 0
    local y = active and (targetY or 0) or 0
    local visual = visuals[bar]
    if active and (config.personalPowerSkin or x ~= 0 or y ~= 0) and not visual then
        visual = {}
        visuals[bar] = visual
    end
    if active and config.personalPowerSkin and visual and not visual.edges then
        if NS.IsCombatLocked() then
            owner.needsRefresh = true
            return
        end
        visual.edges = Style.CreateBorder(bar).edges
    end
    if visual and visual.edges then
        if NS.IsCombatLocked() then
            owner.needsRefresh = true
            return
        end
        Style.PaintBorder(visual, bar,
            active and config.personalPowerSkin and config.personalPowerBorderSize or 0,
            config.personalPowerBorderColor)
    end
    if visual and (force or (visual.offsetX or 0) ~= x or (visual.offsetY or 0) ~= y) then
        if x ~= 0 or y ~= 0 or (visual.offsetX or 0) ~= 0 or (visual.offsetY or 0) ~= 0 then
            if NS.IsCombatLocked() then
                owner.needsRefresh = true
                return
            end
            bar:SetPointsOffset(x, y)
        end
        visual.offsetX, visual.offsetY = x, y
    end
end

-- Paints the personal power bars; force writes their offsets again.
local function Refresh(force)
    if not owner then return end
    if not Requested() then
        for bar in pairs(visuals) do Paint(bar) end
        return
    end
    local driver = NamePlateDriverFrame
    if NS.Safety.IsForbidden(driver) then return end
    if not hooked then
        hooksecurefunc(driver, "SetupClassNameplateBars", function()
            if Requested() then Power.Reapply() end
        end)
        hooked = true
    end
    local mana = driver:GetClassNameplateManaBar()
    local alternate = driver:GetClassNameplateAlternatePowerBar()
    local x, y = owner.config.personalPowerOffsetX or 0, owner.config.personalPowerOffsetY or 0
    Paint(mana, force, x, y)
    -- Blizzard anchors alternate power to mana when mana is shown. Moving
    -- both would apply the displacement twice to the alternate bar.
    local manaShown = Accessible(mana) and mana:IsShown()
    local altRoot = not mana or (NS.Public(manaShown) and manaShown == false)
    Paint(alternate, force, altRoot and x or 0, altRoot and y or 0)
end
Power.Refresh = Refresh

-- After Blizzard set the bars up again (SetupClassNameplateBars), or after
-- combat held back a paint: every offset is written again.
function Power.Reapply()
    Refresh(true)
end

function Power.Enable(module)
    owner = module
    Power.Refresh()
end

function Power.Disable()
    if not owner then return end
    for bar in pairs(visuals) do Paint(bar) end
    owner = nil
end
