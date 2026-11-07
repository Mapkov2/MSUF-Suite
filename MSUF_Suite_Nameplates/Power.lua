local _, private = ...
local NS = private.NS
local LOOK_BLIZZARD = private.Mode.LOOK_BLIZZARD
local Style = NS.NameplateStyle
local Power = {}
private.Power = Power

local owner
local visuals = setmetatable({}, { __mode = "k" })
local hooked, hookedDisplay

local function Requested()
    local config = owner and owner.config
    return owner and owner.active and config.look ~= LOOK_BLIZZARD
        and (config.personalPowerSkin or (config.personalPowerOffsetX or 0) ~= 0
            or (config.personalPowerOffsetY or 0) ~= 0)
end

local function Accessible(bar)
    return bar and not NS.Safety.IsForbidden(bar)
end

local function Paint(bar, force, x, y, size, color)
    if not Accessible(bar) then return end
    local visual = visuals[bar]
    if not visual and x == 0 and y == 0 and size == 0 then return end
    local oldX, oldY = visual and visual.offsetX or 0, visual and visual.offsetY or 0
    local move = oldX ~= x or oldY ~= y or force and (x ~= 0 or y ~= 0)
    local resize = (visual and visual.borderSize or 0) ~= size
        or size > 0 and visual.borderColor ~= color
    if not move and not resize then return end
    if NS.IsCombatLocked() then
        owner.needsRefresh = true
        return
    end
    if not visual then
        visual = {}
        visuals[bar] = visual
    end
    if resize then
        if not visual.edges then visual.edges = Style.CreateBorder(bar).edges end
        Style.PaintBorder(visual, bar, size, color)
    end
    if move then
        bar:SetPointsOffset(x, y)
        visual.offsetX, visual.offsetY = x, y
    end
end

local function PaintPower(bar, force, inheritOffset)
    local config = owner.config
    local x = not inheritOffset and config.personalPowerOffsetX or 0
    local y = not inheritOffset and config.personalPowerOffsetY or 0
    local size = config.personalPowerSkin and config.personalPowerBorderSize or 0
    Paint(bar, force, x, y, size, config.personalPowerBorderColor)
end

local function PaintDisplayAlternate(display, force)
    local hidden = display.hidePower
    if not NS.Public(hidden) then return end
    -- Both native clients attach the alternate bar to PowerBar when enabled.
    PaintPower(display.AlternatePowerBar, force, not hidden)
end

local function OnDisplayPowerAnchor(display)
    if Requested() and Accessible(display) then PaintPower(display.PowerBar, true) end
end

local function OnDisplayAlternateAnchor(display)
    if Requested() and Accessible(display) then PaintDisplayAlternate(display, true) end
end

local function RefreshDisplay(force)
    local display = PersonalResourceDisplayFrame
    if not Accessible(display) then return end
    if not hookedDisplay then
        hooksecurefunc(display, "UpdatePowerBarAnchor", OnDisplayPowerAnchor)
        hooksecurefunc(display, "UpdateAdditionalBarAnchors", OnDisplayAlternateAnchor)
        hookedDisplay = true
    end
    PaintPower(display.PowerBar, force)
    PaintDisplayAlternate(display, force)
end

-- Paints the personal power bars; force writes their offsets again.
local function Refresh(force)
    if not owner then return end
    if not Requested() then
        for bar in pairs(visuals) do Paint(bar, false, 0, 0, 0) end
        return
    end
    RefreshDisplay(force)
    local driver = NamePlateDriverFrame
    if not Accessible(driver) then return end
    if not hooked then
        hooksecurefunc(driver, "SetupClassNameplateBars", function()
            if Requested() then Power.Reapply() end
        end)
        hooked = true
    end
    local mana = driver:GetClassNameplateManaBar()
    local alternate = driver:GetClassNameplateAlternatePowerBar()
    PaintPower(mana, force)
    -- Blizzard anchors alternate power to mana when mana is shown. Moving
    -- both would apply the displacement twice to the alternate bar.
    local manaShown = Accessible(mana) and mana:IsShown()
    local altRoot = not mana or (NS.Public(manaShown) and manaShown == false)
    PaintPower(alternate, force, not altRoot)
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
    for bar in pairs(visuals) do Paint(bar, false, 0, 0, 0) end
    owner = nil
end
