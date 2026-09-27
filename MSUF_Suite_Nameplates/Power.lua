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
    return bar and not NS.Safety.IsForbidden(bar) and type(bar.SetPointsOffset) == "function"
        and type(bar.GetStatusBarTexture) == "function"
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
        if NS.IsCombatLocked() then owner.needsRefresh = true; return end
        visual.edges = Style.CreateBorder(bar).edges
    end
    if visual and visual.edges then
        if NS.IsCombatLocked() then owner.needsRefresh = true; return end
        Style.PaintBorder(visual, bar,
            active and config.personalPowerSkin and config.personalPowerBorderSize or 0,
            config.personalPowerBorderColor)
    end
    if visual and (force or (visual.offsetX or 0) ~= x or (visual.offsetY or 0) ~= y) then
        if x ~= 0 or y ~= 0 or (visual.offsetX or 0) ~= 0 or (visual.offsetY or 0) ~= 0 then
            if NS.IsCombatLocked() then owner.needsRefresh = true; return end
            bar:SetPointsOffset(x, y)
        end
        visual.offsetX, visual.offsetY = x, y
    end
end

function Power.Refresh(force)
    if not owner then return end
    if not Requested() then
        for bar in pairs(visuals) do Paint(bar) end
        return
    end
    local driver = _G.NamePlateDriverFrame
    if not driver or NS.Safety.IsForbidden(driver) then return end
    if not hooked and type(driver.SetupClassNameplateBars) == "function" then
        hooksecurefunc(driver, "SetupClassNameplateBars", function()
            if Requested() then Power.Refresh(true) end
        end)
        hooked = true
    end
    local mana = type(driver.GetClassNameplateManaBar) == "function"
        and driver:GetClassNameplateManaBar() or nil
    local alternate = type(driver.GetClassNameplateAlternatePowerBar) == "function"
        and driver:GetClassNameplateAlternatePowerBar() or nil
    local x, y = owner.config.personalPowerOffsetX or 0, owner.config.personalPowerOffsetY or 0
    Paint(mana, force, x, y)
    -- Blizzard anchors alternate power to mana when mana is shown. Moving
    -- both would apply the displacement twice to the alternate bar.
    local manaShown = mana and type(mana.IsShown) == "function" and mana:IsShown()
    local altRoot = not mana or (NS.Public(manaShown) and manaShown == false)
    Paint(alternate, force, altRoot and x or 0, altRoot and y or 0)
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
