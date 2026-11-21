local _, P = ...
local NS, S = P.NS, P.Suite
local Finite = NS.Finite
-- The native backpack and equipped bag buttons retain their own input.
-- Secure conditions hide the bar. Mouseover changes its alpha.
local NativeBagBar = {}
P.NativeBagBar = NativeBagBar
local M = P.BagsModule
local MODE = NS.BagsBarVisibility
local driverFrame, driverWasShown, driver, deviceHooks
local nativeBagShowHooks = setmetatable({}, { __mode = "k" })
local hoverRoots = setmetatable({}, { __mode = "k" })
local hoverFrame, hoverAlpha, hoverApplied, hoverTimer
local events, requested
local Sync

local function CancelHoverTimer()
    if not hoverTimer then return end
    hoverTimer:Cancel()
    hoverTimer = nil
end

local function SetHoverAlpha(shown)
    local frame = hoverFrame
    if not frame then return end
    local current = frame:GetAlpha()
    if not Finite(current) then return end
    local alpha = (shown or S.editMode) and hoverAlpha or 0
    if current ~= alpha then frame:SetAlpha(alpha) end
    hoverApplied = alpha
end

local function SampleHover()
    hoverTimer = nil
    if not hoverFrame then return end
    local over = hoverFrame:IsMouseOver()
    SetHoverAlpha(NS.Public(over) and over == true)
end

local function HoverEnter(widget)
    if not hoverFrame or hoverRoots[widget] ~= hoverFrame then return end
    CancelHoverTimer()
    SetHoverAlpha(true)
end

local function HoverLeave(widget)
    if not hoverFrame or hoverRoots[widget] ~= hoverFrame then return end
    CancelHoverTimer()
    hoverTimer = C_Timer.NewTimer(.12, SampleHover)
end

local function HookHover(widget, root)
    if hoverRoots[widget] == root then return end
    if not hoverRoots[widget] then
        widget:HookScript("OnEnter", HoverEnter)
        widget:HookScript("OnLeave", HoverLeave)
    end
    hoverRoots[widget] = root
    for _, child in ipairs({ widget:GetChildren() }) do HookHover(child, root) end
end

local function ReleaseHover()
    if not hoverFrame then return end
    CancelHoverTimer()
    local frame, alpha, applied = hoverFrame, hoverAlpha, hoverApplied
    hoverFrame, hoverAlpha, hoverApplied = nil, nil, nil
    M.context:RestoreProperty(frame, "SetMouseMotionEnabled")
    local current = frame:GetAlpha()
    if Finite(current) and current == applied then frame:SetAlpha(alpha) end
end

local function ApplyHover(frame)
    if hoverFrame ~= frame then
        ReleaseHover()
        local alpha = frame:GetAlpha()
        if not Finite(alpha) then return end
        hoverFrame, hoverAlpha = frame, alpha
        HookHover(frame, frame)
        -- Follow the mouse across gaps between the native buttons.
        M.context:Property(frame, "IsMouseMotionEnabled", "SetMouseMotionEnabled", true)
    end
    CancelHoverTimer()
    SampleHover()
end

local function ReleaseDriver()
    if not driverFrame then return end
    local frame, wasShown = driverFrame, driverWasShown
    driverFrame, driverWasShown, driver = nil, nil, nil
    UnregisterStateDriver(frame, "visibility")
    if wasShown and not S.GamepadUI() and not frame:IsShown() then frame:Show() end
end

local function DriverFor(config, mode)
    if S.editMode then return nil end
    if mode == MODE.NEVER then return "hide" end
    local clauses = {}
    if mode == MODE.IN_COMBAT then clauses[1] = "[nocombat] hide" end
    if mode == MODE.OUT_OF_COMBAT then clauses[1] = "[combat] hide" end
    for _, condition in ipairs(NS.BagsBarConditions) do
        if config[condition[1]] then clauses[#clauses + 1] = condition[3] end
    end
    if #clauses == 0 then return nil end
    return "[petbattle] hide; " .. table.concat(clauses, "; ") .. "; show"
end

local function ApplyDriver(frame, expression)
    if driverFrame ~= frame then
        ReleaseDriver()
        driverFrame, driverWasShown = frame, frame:IsShown() == true
    end
    if driver ~= expression then
        if driver then UnregisterStateDriver(frame, "visibility") end
        driver = expression
        RegisterStateDriver(frame, "visibility", expression)
    end
    if expression == "hide" or SecureCmdOptionParse(expression) == "hide" then frame:Hide() end
end

local function OnEvent(frame, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Blizzard_MainMenuBarBagButtons" then return end
    frame:UnregisterEvent(event)
    Sync()
end

local function WaitFor(event)
    if not events then
        events = S.CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent(event)
end

Sync = function()
    if NS.IsCombatLocked() then
        WaitFor("PLAYER_REGEN_ENABLED")
        return
    end
    if events then events:UnregisterAllEvents() end
    local frame = _G.BagsBar
    if requested and not frame then WaitFor("ADDON_LOADED") end
    local config = requested and M.active and frame and not S.GamepadUI() and M.config
    local mode = config and config.bagBarVisibility
    local hover = mode == MODE.MOUSEOVER
    local expression = config and DriverFor(config, mode)
    if (hover or expression) and not nativeBagShowHooks[frame] then
        frame:HookScript("OnShow", Sync)
        nativeBagShowHooks[frame] = true
    end
    if hover then ApplyHover(frame) else ReleaseHover() end
    if expression and (expression == "hide" or frame:IsShown() or driverFrame == frame and driverWasShown) then
        ApplyDriver(frame, expression)
    else
        ReleaseDriver()
    end
end

function NativeBagBar.Refresh()
    requested = true
    -- Forever swaps the native mouse and Gamepad bars outside this module.
    if not deviceHooks and NS.Client.isForever and _G.MainActionBar_InitializeMKB and _G.MainActionBar_InitializeGamepad then
        hooksecurefunc("MainActionBar_InitializeMKB", Sync)
        hooksecurefunc("MainActionBar_InitializeGamepad", Sync)
        deviceHooks = true
    end
    Sync()
end

function NativeBagBar.Disable()
    requested = nil
    Sync()
end
