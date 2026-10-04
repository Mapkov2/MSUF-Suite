local _, NS = ...

-- Visibility of the owned Micro Bar (OwnedMicroBar.lua, which loads after
-- this file): the secure visibility driver with the load conditions, the
-- "show when injured" health gate and the mouseover reveal. OwnedMicroBar
-- hands over its frames once with Attach; until then nothing here acts.
local Visibility = {}
NS.OwnedMicroBarVisibility = Visibility

local Call = NS.Safety.Call
local Public = NS.Safety.Public
local Settings = NS.OwnedMicroBarLayout.Settings

local VISIBILITY_DRIVERS = {
    combat = "[combat] show; hide",
    outOfCombat = "[combat] hide; show",
}
local HOVER_GRACE = 0.12

-- Load conditions that the "show when injured" rule overrides.
local INJURED_OVERRIDES = {
    loadHideNoTarget = true,
    loadHideOutOfCombat = true,
    loadHideOutOfCombatNoTarget = true,
}

local owner, bar, healthGate, healthCurve
local visibilityDriver, editSession, hoverTimer
local hoverButtons = setmetatable({}, { __mode = "k" })
-- Reused for every driver built below; the result is a string.
local driverRules = {}

-- owner is the OwnedMicroBar table (active, suspended); bar and healthGate
-- are its frames, created once.
function Visibility.Attach(ownedBar, barFrame, gateFrame)
    owner, bar, healthGate = ownedBar, barFrame, gateFrame
end

local function IsTrue(value)
    return Public(value) and value == true
end

local function CancelHoverTimer()
    if hoverTimer then
        hoverTimer:Cancel()
        hoverTimer = nil
    end
end

local function MouseInside()
    if IsTrue(Call(bar, "IsMouseOver")) then return true end
    for button in pairs(hoverButtons) do
        if IsTrue(Call(button, "IsMouseOver")) then return true end
    end
    return false
end

local function MouseoverActive()
    local settings = Settings()
    return bar ~= nil and owner.active and not owner.suspended and not editSession
        and settings and settings.visibility == "mouseover"
end

function Visibility.HoverEnter()
    CancelHoverTimer()
    if MouseoverActive() then bar:SetAlpha(1) end
end

local function HideAfterGrace()
    hoverTimer = nil
    if MouseoverActive() and not MouseInside() then bar:SetAlpha(0) end
end

function Visibility.HoverLeave()
    if not MouseoverActive() then return end
    CancelHoverTimer()
    hoverTimer = C_Timer.NewTimer(HOVER_GRACE, HideAfterGrace)
end

-- The native buttons that keep a mouseover-only bar revealed while hovered.
function Visibility.TrackHoverButtons(buttons)
    hoverButtons = setmetatable({}, { __mode = "k" })
    for button in pairs(buttons) do
        hoverButtons[button] = true
    end
end

function Visibility.ClearDriver()
    if visibilityDriver then
        UnregisterStateDriver(bar, "visibility")
        visibilityDriver = nil
    end
end

local function InInstance()
    local inside = IsInInstance()
    return inside == true or inside == 1
end

local function InHousing()
    return C_Housing.IsInsideHouseOrPlot() == true
end

function Visibility.RefreshHealthGate(settings)
    if not healthGate then return end
    if editSession or not (settings and settings.loadShowWhenInjured) then
        healthGate:SetAlpha(1)
        return
    end
    if not healthCurve then
        healthCurve = C_CurveUtil.CreateCurve()
        healthCurve:SetType(Enum.LuaCurveType.Step)
        healthCurve:AddPoint(0, 1)
        healthCurve:AddPoint(1, 0)
    end
    -- Keep Midnight's secret health in Blizzard's curve and pass its result
    -- directly to native alpha, independently of mouseover alpha.
    healthGate:SetAlpha(UnitHealthPercent("player", false, healthCurve))
end
local RefreshHealthGate = Visibility.RefreshHealthGate

-- Blizzard hid the menu the bar holds (WoW Forever's Gamepad UI hides
-- MicroMenu in MainActionBar_InitializeGamepad): no empty shell stays behind.
local function MenuHiddenByBlizzard()
    local menu = owner and owner.GetRoot and owner.GetRoot()
    return menu ~= nil and Call(menu, "IsShown") == false
end

-- The secure visibility driver for the mode plus the enabled load conditions.
local function ConditionalDriver(settings, mode)
    if not settings then return VISIBILITY_DRIVERS[mode] end
    local rules, count = driverRules, 0
    for index = #rules, 1, -1 do rules[index] = nil end
    local injured = settings.loadShowWhenInjured == true
    for _, condition in ipairs(NS.MicroMenuLoadConditions) do
        local key, macro = condition[1], condition[3]
        if macro and settings[key] == true and not (injured and INJURED_OVERRIDES[key]) then
            count = count + 1
            rules[count] = macro
        end
    end
    if count == 0 then return VISIBILITY_DRIVERS[mode] end
    if mode == "combat" then
        table.insert(rules, 1, "[nocombat] hide")
    elseif mode == "outOfCombat" then
        table.insert(rules, 1, "[combat] hide")
    end
    rules[#rules + 1] = "show"
    return table.concat(rules, "; ")
end

function Visibility.Apply(settings)
    if not bar or NS.IsCombatLocked() then return false end
    CancelHoverTimer()
    local mode = editSession and "always" or (settings and settings.visibility) or "always"
    local blocked = not editSession and (MenuHiddenByBlizzard() or settings and (settings.loadHideInInstance
        and InInstance() or settings.loadHideInHousing and InHousing()))
    local driver = mode ~= "never" and not editSession and ConditionalDriver(settings, mode) or nil
    if blocked and driver then driver = "hide" end
    if visibilityDriver ~= driver then
        Visibility.ClearDriver()
        if driver then
            RegisterStateDriver(bar, "visibility", driver)
            visibilityDriver = driver
        end
    end
    bar:EnableMouse(mode == "mouseover")
    bar:SetAlpha(mode == "mouseover" and (MouseInside() and 1 or 0) or 1)
    if mode == "never" or blocked and not driver then
        bar:Hide()
    elseif not driver then
        bar:Show()
    end
    RefreshHealthGate(settings)
    return true
end

-- MSUF Edit Mode shows the bar with no driver while a session runs.
function Visibility.SetEditSession(enabled)
    editSession = enabled == true
end

-- Drops the hover timer, the driver, the Edit Mode session and the tracked
-- buttons (the owned bar was disabled).
function Visibility.Reset()
    CancelHoverTimer()
    Visibility.ClearDriver()
    editSession = false
    hoverButtons = setmetatable({}, { __mode = "k" })
end

return Visibility
