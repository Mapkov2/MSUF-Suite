local _, P = ...
local NS, S = P.NS, P.Suite
local R = {}
P.ExtensionResources = R
local owner, requested, hooked, anchored, anchoredPlate
local faded, fadedAlpha

local function Safe(frame)
    return not NS.IsSecret(frame) and frame and not NS.Safety.IsForbidden(frame)
end

local function Mutable(frame, parent)
    if not Safe(frame) or NS.IsSecret(parent) or parent and not Safe(parent) then return false end
    local restricted = frame:IsAnchoringRestricted()
    if NS.IsSecret(restricted) or restricted ~= false then return false end
    if parent then
        restricted = parent:IsAnchoringRestricted()
        if NS.IsSecret(restricted) or restricted ~= false then return false end
    end
    if not NS.IsCombatLocked() then return true end
    local protected = frame:IsProtected()
    if NS.IsSecret(protected) or protected ~= false then return false end
    if parent then
        protected = parent:IsProtected()
        if NS.IsSecret(protected) or protected ~= false then return false end
    end
    return true
end

local function FadePending(bar)
    if Safe(bar) and not faded then
        local alpha = bar:GetAlpha()
        if NS.IsSecret(alpha) or S.Finite(alpha) then faded, fadedAlpha = bar, alpha end
    end
    if faded then faded:SetAlpha(0) end
    R.pending = true
    return false
end

local function RestoreAlpha()
    if faded and Safe(faded) then faded:SetAlpha(fadedAlpha) end
    faded, fadedAlpha = nil, nil
end

local function Shown(frame)
    if not Safe(frame) then return false end
    local shown = frame:IsShown()
    return not NS.IsSecret(shown) and shown == true
end

-- Reproduce only the native mechanic-frame anchor. The driver still owns
-- the selected class/spec bar, power data and visibility decisions.
local function NativeAnchor(bar)
    local driver = NamePlateDriverFrame
    local plate = C_NamePlate.GetNamePlateForUnit("player")
    if not Safe(plate) then
        if not Mutable(bar, UIParent) then return false end
        bar:Hide()
        bar:SetParent(UIParent)
        return true
    end
    if not Mutable(bar, plate) or not Safe(plate.UnitFrame) then return false end
    local bottom = plate.UnitFrame.HealthBarsContainer
    local mana, alternate = driver:GetClassNameplateManaBar(), driver:GetClassNameplateAlternatePowerBar()
    if Shown(mana) then bottom = mana end
    if Shown(alternate) then bottom = alternate end
    if not Safe(bottom) or not Mutable(bar, bottom) then return false end
    local padding = bar.paddingOverride
    if not S.Finite(padding) then padding = -4 end
    bar:SetParent(plate)
    bar:ClearAllPoints()
    P.Geometry.Point(bar, "TOP", bottom, "BOTTOM", 0, padding)
    return true
end

function R.Release()
    if anchored and Safe(anchored) and not NativeAnchor(anchored) then
        return FadePending(anchored)
    end
    RestoreAlpha()
    anchored, anchoredPlate, R.pending = nil, nil, nil
    return true
end

function R.Refresh(nativeReset)
    if nativeReset then RestoreAlpha() anchored, anchoredPlate = nil, nil end
    if not requested or not owner.active then return R.Release() end
    local driver = NamePlateDriverFrame
    if not Safe(driver) or not driver.GetClassNameplateBar then return true end
    local bar = driver:GetClassNameplateBar()
    if not Safe(bar) then return R.Release() end
    local attack = UnitCanAttack("player", "target")
    local plate = not NS.IsSecret(attack) and attack == true and C_NamePlate.GetNamePlateForUnit("target")
    if not Safe(plate) or not Safe(plate.UnitFrame) then return R.Release() end
    if anchored == bar and anchoredPlate == plate then return true end
    if not Mutable(bar, plate) then
        return FadePending(anchored or bar)
    end
    local health = plate.UnitFrame.HealthBarsContainer
    if not Safe(health) or not Mutable(bar, health) then
        return FadePending(anchored or bar)
    end
    if anchored and anchored ~= bar and not R.Release() then return false end
    bar:SetParent(plate)
    bar:ClearAllPoints()
    P.Geometry.Point(bar, "BOTTOM", health, "TOP", 0, 24)
    RestoreAlpha()
    anchored, anchoredPlate, R.pending = bar, plate, nil
    return true
end

local function NativeSetup()
    if requested or anchored then R.Refresh(true) end
end

function R.Configure(module, plan)
    owner = module
    requested = plan.enabled and plan.resources and not NS.Client.isForever
    local driver = NamePlateDriverFrame
    if requested and not hooked and Safe(driver) and driver.SetupClassNameplateBars then
        hooked = true
        hooksecurefunc(driver, "SetupClassNameplateBars", NativeSetup)
    end
    return R.Refresh()
end

function R.Disable()
    requested = false
    return R.Release()
end
