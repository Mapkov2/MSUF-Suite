local _, P = ...
local NS, S = P.NS, P.Suite
-- Bar 1 paging. One state driver on the bar 1 header; the restricted
-- handler rewrites each button's action and mirrors the page onto
-- MainActionBar so native ACTIONBUTTONn keys fire the slot the icons show.
-- Rule: the page handler never uses CallMethod, which would taint the one
-- secure pass in which Blizzard evaluates vehicle and override transitions.
local AB = P.ActionBars
local M = AB.M

-- Vehicle, override, possess and temporary shapeshift pages resolve inside
-- the handler with Blizzard's own priority (ActionBarController_UpdateAll:
-- vehicle > override > temporary shapeshift > bonus bar on page 1 > page).
-- Distinct state names make transitions between them re-run the handler.
AB.SNIPPET.PAGE_STATE = [[
local state=self:GetAttribute("state-page")
local page=tonumber(state)
if not page then
    if HasVehicleActionBar and HasVehicleActionBar() then page=GetVehicleBarIndex()
    elseif HasOverrideActionBar and HasOverrideActionBar() then page=GetOverrideBarIndex()
    elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then page=GetTempShapeshiftBarIndex()
    elseif HasBonusActionBar and HasBonusActionBar() and GetActionBarPage()==1 then page=GetBonusBarIndex()
    elseif GetActionBarPage then page=GetActionBarPage() end
end
page=tonumber(page) or 1
if page<1 then page=1 end
self:SetAttribute("actionpage",page)
if self:GetAttribute("mirror") then
    local main=self:GetFrameRef("main")
    if main then main:SetAttribute("actionpage",page) end
end
self:ChildUpdate("page",page)
]]
AB.SNIPPET.PAGE_CHILD = [[
local page=tonumber(message) or 1
self:SetAttribute("action",(self:GetAttribute("index") or 1)+(page-1)*12)
]] .. AB.SNIPPET.BUTTON

local SPECIAL = "[vehicleui] vehicle; [overridebar] override; [possessbar] possess; [shapeshift] shapeshift; "
local MANUAL = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
local FORMS = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "

-- Skyriding only exists on the Mainline client. Elsewhere bonus bar 5 is
-- the possess bar, which must keep paging.
local function SkyridingOptOut(config)
    return config.disableSkyridingPaging and NS.Client.flavor == "Mainline"
end

-- True when bar 1 must not follow Blizzard's native page: its keys then
-- click the suite buttons instead of the hidden Blizzard ones.
function AB.CustomPaging(config)
    return config.pagingModifiers or config.disableFormPaging or SkyridingOptOut(config) or false
end

-- Blizzard's order: vehicle/override/possess, manual pages 2-6 (which beat
-- forms, as Blizzard applies the bonus bar only on page 1), class forms,
-- bonus bar 5, page 1. Modifier paging, when enabled, wins over manual
-- pages and forms but never over vehicle or override bars.
function AB.PageDriver(config)
    local driver = SPECIAL
    if config.pagingModifiers then
        driver = driver .. "[mod:shift] " .. config.pageShift .. "; [mod:ctrl] " .. config.pageCtrl .. "; [mod:alt] " .. config.pageAlt .. "; "
    end
    driver = driver .. MANUAL
    if not config.disableFormPaging then driver = driver .. FORMS end
    if not SkyridingOptOut(config) then driver = driver .. "[bonusbar:5] 11; " end
    return driver .. "1"
end

-- Registers (or keeps) the bar 1 driver. Re-registering an unchanged driver
-- would blink the bar, so the string is cached.
function AB.ApplyPaging()
    local bar = AB.bars[1]
    if not bar or NS.IsCombatLocked() then return end
    local header = bar.header
    if not bar.pageReady then
        header:SetAttribute("_onstate-page", AB.SNIPPET.PAGE_STATE)
        for i = 1, #bar.buttons do bar.buttons[i].button:SetAttribute("_childupdate-page", AB.SNIPPET.PAGE_CHILD) end
        local main = AB.Frame("MainActionBar")
        if main then SecureHandlerSetFrameRef(header, "main", main) end
        bar.pageReady = true
    end
    local mirror = not AB.CustomPaging(M.config)
    local changed = header:GetAttribute("mirror") ~= mirror
    header:SetAttribute("mirror", mirror)
    local driver = AB.PageDriver(M.config)
    if bar.pageDriver ~= driver then
        bar.pageDriver = driver
        RegisterStateDriver(header, "page", driver)
    elseif changed then
        AB.Execute(header, AB.SNIPPET.PAGE_STATE)
    end
end

function AB.StopPaging()
    local bar = AB.bars[1]
    if not bar or not bar.pageDriver then return end
    UnregisterStateDriver(bar.header, "page")
    bar.pageDriver = nil
end

-- Lua mirror of the page for painting: button n of bar 1 shows slot
-- n + (page - 1) * 12, exactly what the restricted handler assigns.
function AB.PageSlots(bar, page)
    page = tonumber(page)
    if not page or page < 1 then page = 1 end
    for i = 1, #bar.buttons do
        local rec = bar.buttons[i]
        rec.slot = rec.index + (page - 1) * 12
    end
    bar.page = page
end
