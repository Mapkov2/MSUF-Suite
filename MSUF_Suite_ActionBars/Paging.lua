local _, P = ...
local NS, S = P.NS, P.Suite
-- Bar 1 paging. One state driver on the bar 1 header; the restricted
-- handler sets the page on Blizzard's adopted buttons. The suite-painted
-- fallback mirrors compatible pages to the original MainActionBar.
-- Bars 2 to 9 get a page driver only while their custom paging text is
-- valid; keys keep their binding owner (Blizzard's commands click the reused
-- buttons, bar 9's routed keys click its suite buttons), only the page moves.
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
if self:GetAttribute("actionpage")~=page then self:SetAttribute("actionpage",page) end
if self:GetAttribute("mirror") then
    local main=self:GetFrameRef("main")
    if main then main:SetAttribute("actionpage",page) end
end
self:ChildUpdate("page",page)
]]
local PAGE_ACTION = [[
local page=tonumber(message) or 1
local action=(self:GetAttribute("index") or 1)+(page-1)*12
if self:GetAttribute("action")~=action then self:SetAttribute("action",action) end
]]
AB.SNIPPET.PAGE_CHILD = PAGE_ACTION .. AB.SNIPPET.BUTTON
-- SecureTemplates resolves inherited actionpage through the stock button's
-- original bar before its current parent. An explicit page keeps native
-- casts and painting on the Suite's page while retaining the stock ID.
local PAGE_NATIVE_CHILD = [[
if message=="clear" then
    self:SetAttribute("actionpage",nil)
    return
end
]] .. PAGE_ACTION .. [[
if self:GetAttribute("actionpage")~=page then self:SetAttribute("actionpage",page) end
]] .. AB.SNIPPET.NATIVE_BUTTON
local CLEAR_NATIVE_PAGE = [[self:ChildUpdate("page","clear")]]

-- Custom paging of bars 2 to 9 (the "Paging" text, validated and normalized
-- by NS.ActionBarPaging): numeric states only. A page the validated driver
-- did not name falls back to the bar's own page, so even a stale driver can
-- never borrow a page the Lua side refused. Reused Blizzard buttons take the
-- explicit page like bar 1's (PAGE_NATIVE_CHILD); suite buttons their action.
local BAR_PAGE_STATE = [[
local home=self:GetAttribute("homepage") or 1
local page=tonumber(self:GetAttribute("state-page")) or home
if page~=home and not self:GetAttribute("allow-page-"..page) then page=home end
if self:GetAttribute("actionpage")~=page then self:SetAttribute("actionpage",page) end
self:ChildUpdate("page",page)
]]
-- Back on the bar's own page; reused Blizzard buttons then drop the explicit
-- page again and resolve it through their original bar, as before.
local BAR_PAGE_HOME = [[
local home=self:GetAttribute("homepage") or 1
if self:GetAttribute("actionpage")~=home then self:SetAttribute("actionpage",home) end
self:ChildUpdate("page",home)
if self:GetAttribute("nativepage") then self:ChildUpdate("page","clear") end
]]
-- Blizzard's special bars keep their precedence: while one is up, a custom
-- paged bar stays on its own page.
local NATIVE_FIRST = "[vehicleui][overridebar][possessbar][petbattle] "

local SPECIAL = "[vehicleui] vehicle; [overridebar] override; [possessbar] possess; [shapeshift] shapeshift; "
local FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE = 2, 6
local reservedAttribute, allowAttribute = {}, {}
for page = FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE do
    reservedAttribute[page] = "reserved-page-" .. page
    allowAttribute[page] = "allow-page-" .. page
end

-- The page claims of custom paging (NS.ActionBarPageClaims) of the running
-- configuration, refreshed by every paging pass. Any other table (a test, a
-- preview) gets its own answer.
local claimsConfig, claims
local function Claims(config)
    if config == claimsConfig and claims then return claims end
    return NS.ActionBarPageClaims(config)
end

-- Mouseover, combat and group rules can change in combat. Keep a fixed bar's
-- page reserved until the user explicitly turns that bar off. A page another
-- bar's custom paging claimed is reserved as well: one owner per page.
function AB.ReservedPage(config, page)
    return NS.ActionBarPageOwned(config, page) or Claims(config)[page] ~= nil
end

-- Bar 1's validated custom paging, or nil.
local function MainCustom(config)
    return NS.ActionBarPaging(config, 1, Claims(config)) or nil
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
        or SkyridingOptOut(config) or MainCustom(config) then return true end
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
-- pages and forms but never over vehicle or override bars. Custom paging
-- text replaces only the plain page 1 at the end, so every native and form
-- page keeps its precedence (turning form paging off hands forms to it).
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
    local custom = MainCustom(config)
    if custom then
        if custom.final then return driver .. custom.driver end
        driver = driver .. custom.driver .. "; "
    end
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
local function ApplyMainPaging(config)
    local bar = AB.bars[1]
    if not bar then return end
    local header = bar.header
    if not bar.pageReady then
        header:SetAttribute("_onstate-page", AB.SNIPPET.PAGE_STATE)
        local snippet = bar.native and PAGE_NATIVE_CHILD or AB.SNIPPET.PAGE_CHILD
        for i = 1, #bar.buttons do bar.buttons[i].button:SetAttribute("_childupdate-page", snippet) end
        if not bar.native then
            local main = AB.Frame("MainActionBar")
            if main then SecureHandlerSetFrameRef(header, "main", main) end
        end
        bar.pageReady = true
    end
    bar.customPaging = AB.CustomPaging(config)
    local mirror = not bar.native and not bar.customPaging
    local mirrorChanged = header:GetAttribute("mirror") ~= mirror
    if mirrorChanged then header:SetAttribute("mirror", mirror) end
    local reservedChanged = ApplyReservations(header, config)
    local state = header:GetAttribute("state-page")
    local driver = AB.PageDriver(config)
    local restarting = not bar.pageDriver
    if bar.pageDriver ~= driver then
        bar.pageDriver = driver
        RegisterStateDriver(header, "page", driver)
    end
    if (restarting or mirrorChanged or reservedChanged) and state == header:GetAttribute("state-page") then
        AB.Execute(header, AB.SNIPPET.PAGE_STATE)
    end
end

------------------------------------------------------------------ bars 2 to 9
-- The pages besides its own that a custom paged bar may show (2 to 6).
local function SetAllowed(header, parsed)
    local allowed = {}
    if parsed then
        for i = 1, #parsed.pages do allowed[parsed.pages[i]] = true end
    end
    for page = FIRST_MANUAL_PAGE, LAST_MANUAL_PAGE do
        local key, wanted = allowAttribute[page], allowed[page] or nil
        if header:GetAttribute(key) ~= wanted then header:SetAttribute(key, wanted) end
    end
end

-- The page handler goes on the header and its buttons once, on first use.
local function PrepareBar(bar, home)
    if bar.pageReady then return end
    local header = bar.header
    header:SetAttribute("homepage", home)
    header:SetAttribute("nativepage", bar.native or nil)
    header:SetAttribute("_onstate-page", BAR_PAGE_STATE)
    local snippet = bar.native and PAGE_NATIVE_CHILD or AB.SNIPPET.PAGE_CHILD
    for i = 1, #bar.buttons do bar.buttons[i].button:SetAttribute("_childupdate-page", snippet) end
    bar.pageReady = true
end

-- Back to the bar's own page with no driver; a no-op for a bar that never paged.
local function StopBarPaging(bar)
    if not bar.customPage then return end
    if bar.pageDriver then
        UnregisterStateDriver(bar.header, "page")
        bar.pageDriver = nil
    end
    SetAllowed(bar.header, nil)
    -- The header's actionpage write remaps the slots (Events.lua) while
    -- customPage still marks the bar.
    AB.Execute(bar.header, BAR_PAGE_HOME)
    bar.customPage = nil
    -- A stopped module ignores header writes; the next start remaps from here.
    AB.PageSlots(bar, NS.ActionBarHomePages[bar.index])
end

-- A bar with valid custom paging pages by it; any other bar (none, invalid,
-- switched off, a page another bar owns) stays on its own page.
local function ApplyBarPaging(bar, config)
    local home = NS.ActionBarHomePages[bar.index]
    local parsed = home and NS.ActionBarPaging(config, bar.index, claims)
    if not parsed then return StopBarPaging(bar) end
    local header = bar.header
    PrepareBar(bar, home)
    SetAllowed(header, parsed)
    local driver = NATIVE_FIRST .. home .. "; " .. parsed.driver
    if not parsed.final then driver = driver .. "; " .. home end
    bar.customPage = true
    if bar.pageDriver == driver then return end
    local state = header:GetAttribute("state-page")
    bar.pageDriver = driver
    RegisterStateDriver(header, "page", driver)
    if state == header:GetAttribute("state-page") then AB.Execute(header, BAR_PAGE_STATE) end
end

-- Out of combat only (the controller queues a refresh in combat).
function AB.ApplyPaging()
    if NS.IsCombatLocked() then return end
    local config = M.config
    claimsConfig, claims = config, NS.ActionBarPageClaims(config)
    ApplyMainPaging(config)
    for index = AB.ENUM.BAR.FIRST_NATIVE, #NS.ActionBarHomePages do
        local bar = AB.bars[index]
        if bar and bar.owned then ApplyBarPaging(bar, config) end
    end
end

function AB.StopPaging()
    for index = AB.ENUM.BAR.FIRST_NATIVE, #NS.ActionBarHomePages do
        local bar = AB.bars[index]
        if bar then StopBarPaging(bar) end
    end
    claimsConfig, claims = nil, nil
    local bar = AB.bars[1]
    if not bar or not bar.pageDriver then return end
    UnregisterStateDriver(bar.header, "page")
    bar.pageDriver = nil
    if bar.native then AB.Execute(bar.header, CLEAR_NATIVE_PAGE) end
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
