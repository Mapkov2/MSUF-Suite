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
    elseif GetActionBarPage then
        page=GetActionBarPage()
        if page and self:GetAttribute("reserved-page-"..page) then page=1 end
    end
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
local FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE = 2, 6
local pageOwner, reservedAttribute = {}, {}
for page = FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE do
    reservedAttribute[page] = "reserved-page-" .. page
end
for index = AB.ENUM.BAR.FIRST_NATIVE, AB.ENUM.BAR.LAST_ACTION do
    local slot = AB.FIRST_SLOT[index]
    local page = slot and math.floor((slot - 1) / AB.BUTTONS) + 1
    if page and page >= FIRST_MANUAL_PAGE and page <= LAST_MANUAL_PAGE then
        pageOwner[page] = AB.KEYS[index].Visibility
    end
end

-- Mouseover, combat and group rules can change in combat. Keep a fixed bar's
-- page reserved until the user explicitly turns that bar off.
function AB.ReservedPage(config, page)
    local key = pageOwner[page]
    local mode = key and config[key]
    return mode ~= nil and mode ~= AB.ENUM.VISIBILITY.NEVER
end
-- Bonus bar 4 is the druid's Moonkin Form. It has its own opt-out, so a
-- healer who only passes through the form keeps bar 1 while cat and bear
-- keep their pages.
local FORMS = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; "
local MOONKIN = "[bonusbar:4] 10; "

-- Skyriding only exists on Retail. On Forever bonus bar 5 is the possess
-- bar, which must keep paging.
local function SkyridingOptOut(config)
    return config.disableSkyridingPaging and not NS.Client.isForever
end

-- True when bar 1 must not follow Blizzard's native page: its keys then
-- click the suite buttons instead of the hidden Blizzard ones.
function AB.CustomPaging(config)
    if config.pagingTarget or config.pagingModifiers or config.disableFormPaging or config.disableMoonkinPaging
        or SkyridingOptOut(config) then return true end
    for page = FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE do
        if AB.ReservedPage(config, page) then return true end
    end
    return false
end

local function AddPage(driver, condition, page, config)
    if AB.ReservedPage(config, page) then return driver end
    return driver .. condition .. page .. "; "
end

-- Blizzard's order: vehicle/override/possess, manual pages 2-6 (which beat
-- forms, as Blizzard applies the bonus bar only on page 1), class forms,
-- bonus bar 5, page 1. Modifier paging, when enabled, wins over manual
-- pages and forms but never over vehicle or override bars.
function AB.PageDriver(config)
    local driver = SPECIAL
    if config.pagingModifiers then
        driver = AddPage(driver, "[mod:shift] ", config.pageShift, config)
        driver = AddPage(driver, "[mod:ctrl] ", config.pageCtrl, config)
        driver = AddPage(driver, "[mod:alt] ", config.pageAlt, config)
    end
    if config.pagingTarget then
        driver = AddPage(driver, "[help] ", config.pageFriendly, config)
        driver = AddPage(driver, "[harm] ", config.pageHostile, config)
    end
    for page = FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE do
        driver = AddPage(driver, "[bar:" .. page .. "] ", page, config)
    end
    if not config.disableFormPaging then
        driver = driver .. FORMS
        if not config.disableMoonkinPaging then driver = driver .. MOONKIN end
    end
    if not SkyridingOptOut(config) then driver = driver .. "[bonusbar:5] 11; " end
    return driver .. "1"
end

-- The special states can fall back to Blizzard's numeric page. Keep their
-- fallback subject to the same reservation as the compiled ordinary clauses.
local function ApplyReservations(header, config)
    local changed = false
    for page = FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE do
        local key = reservedAttribute[page]
        local reserved = AB.ReservedPage(config, page) or nil
        if header:GetAttribute(key) ~= reserved then
            header:SetAttribute(key, reserved)
            changed = true
        end
    end
    return changed
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
    local config = M.config
    bar.customPaging = AB.CustomPaging(config)
    local mirror = not bar.customPaging
    local mirrorChanged = header:GetAttribute("mirror") ~= mirror
    if mirrorChanged then header:SetAttribute("mirror", mirror) end
    local reservedChanged = ApplyReservations(header, config)
    local state = header:GetAttribute("state-page")
    local driver = AB.PageDriver(config)
    if bar.pageDriver ~= driver then
        bar.pageDriver = driver
        RegisterStateDriver(header, "page", driver)
    end
    if (mirrorChanged or reservedChanged) and state == header:GetAttribute("state-page") then
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
