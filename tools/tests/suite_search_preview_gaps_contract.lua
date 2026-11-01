local root = assert(arg[1]):gsub("\\", "/")
local host = arg[3] or (root .. "/../MidnightSimpleUnitFrames-7.0")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { locale = "deDE" })
local env, M, world = mw.env, mw.M, mw.world
-- Client visibility includes every ancestor; the generic widget stubs only
-- model each region's own shown flag.
world.widgets.Methods.IsVisible = function(self)
    local parent = self:GetParent()
    return self:IsShown() and (not parent or parent:IsVisible())
end
env.InCombatLockdown, env.UnitAffectingCombat = function() return false end, function() return false end
env.GetCurrentKeyBoardFocus = function() return nil end
env.IsControlKeyDown, env.IsShiftKeyDown = function() return false end, function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
env.C_AddOns = {
    GetAddOnMetadata = function() end, IsAddOnLoaded = function(name) local loaded = name ~= "EllesmereUIDamageMeters" return loaded, loaded end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end, LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local function Load(addon, namespace)
    local file = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local source = file:read("*a"); file:close()
    for line in source:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            assert(ok, tostring(message))
        end
    end
end
Load("MSUF_Suite", {})
local Suite, P = env.MSUFSuite, {}
assert(Suite.Database.Initialize(nil))
Suite.Suite.Config("damageMeter").enabled = true
Load("MSUF_Suite_Options", P)

local api=M.Search._CoreAPI
local function Ready()
    api.GetSearchRecords()
    local ready=false
    if api.WhenIndexReady then assert(api.WhenIndexReady(function() ready=true end)) else mw:RunTimers(1000); ready=true end
    for i=1,1000 do if ready then break end; mw:RunTimers(1000) end
    assert(ready,"index did not settle")
    return api.GetSearchRecords()
end
local function Find(stage,key,control)
    local count=0
    for _,row in ipairs(Ready()) do
        local exact=row.exactTarget or {}
        if key and exact.settingKey==key or control and exact.controlId==control then count=count+1 end
    end
    print("FIND",stage,key or control,count)
    return count
end
print("CAPABILITY",M.CastbarSuiteNameplatesSupported())
Find("cold-shared-size",nil,P.Meta("suite_damageMeter","damageMeter","preview.size","ephemeral","suite_damageMeter_bars").controlId)
Find("cold","general.classPowerPreviewGuidesEnabled")
Find("cold",nil,"menu2.classpower.class-power-preview.animation.toggle")
Find("cold","general.kickReadyShowNameplates")
for _,key in ipairs({"settings","reset","session","type","target"}) do
    Find("cold","msufsuite.damageMeter."..key.."Size")
end

local c = P.S.Config("damageMeter")
local ui, paints = nil, 0
-- Native window-shaped sample; the real runtime's anchors are checked by
-- suite_meter_menu_preview_contract. Navigation uses the real host below.
P.S.DamageMeterDrawMenuPreview = function(parent, index, details)
    assert(ui.ctx.wrapper:IsVisible() and M.activeKey == "suite_damageMeter", "preview painted before its owning page was shown")
    paints = paints + 1
    if parent.meterTestWindow then
        local win = parent.meterTestWindow
        win.index = index
        win.previewTimerShown, win.detailsSample = c.timer, details == true
        return win
    end
    local function Frame(kind, owner, width, height, x, y)
        local frame = env.CreateFrame(kind, nil, owner)
        frame:SetSize(width, height); frame:SetPoint("TOPLEFT", owner, "TOPLEFT", x or 0, y or 0)
        return frame
    end
    local win = { frame = Frame("Frame", parent, 260, 170), buttons = {}, rows = {}, capacity = 3, overall = false }
    win.panel = Frame("Button", win.frame, 258, 148)
    win.detailsSample = details == true
    win.sampleTimer = Frame("Frame", parent, 104, 34)
    win.previewTimerShown = c.timer
    win.header, win.body = Frame("Button", win.frame, 260, 22), Frame("Frame", win.frame, 258, 148, 1, -23)
    win.title, win.timer = win.header:CreateFontString(), win.header:CreateFontString()
    win.title:SetSize(100, 18); win.timer:SetSize(30, 18)
    for _, key in ipairs({ "settings", "reset", "session", "type", "target" }) do win.buttons[key] = Frame("Button", win.header, 18, 18) end
    for i = 1, 3 do
        local row = Frame("Button", win.body, 258, 18, 0, -(i - 1) * 20)
        row.nameText, row.valueText, row.rankText, row.icon = row:CreateFontString(), row:CreateFontString(), row:CreateFontString(), row:CreateTexture()
        row.bar, row.track = env.CreateFrame("StatusBar", nil, row), row:CreateTexture()
        local fill = row.bar:CreateTexture()
        row.bar.GetStatusBarTexture = function() return fill end
        win.rows[i] = row
    end
    parent.meterTestWindow = win
    return win
end
local build = P.BuildMeterMenuPreview
P.BuildMeterMenuPreview = function(workspace, ...)
    ui = workspace
    return build(workspace, ...)
end

local records = {}
for _, record in ipairs(Ready()) do
    local key = record.exactTarget and record.exactTarget.settingKey
    if key then records[key] = record end
end
c.settingsSize = nil
local saved = {}
for _, button in ipairs({"settings", "reset", "session", "type", "target"}) do
    for _, suffix in ipairs({"Size", "OffsetX", "OffsetY"}) do
        local key = button..suffix
        saved[key] = P.Get("damageMeter", key)
        assert(records["msufsuite.damageMeter."..key], "missing cold setting: "..key)
    end
end
assert(M.activeKey ~= "suite_damageMeter", "fixture prebuilt the target page")
local function CheckRoutes()
    for _, button in ipairs({"settings", "reset", "session", "type", "target"}) do
        for _, suffix in ipairs({"Size", "OffsetX", "OffsetY"}) do
            local key = button..suffix
            assert(M.SelectPage("home"))
            local record = records["msufsuite.damageMeter."..key]
            Ready()
            local query = P.Tr("Damage meter") .. " " .. P.Tr(({settings="Window settings",reset="Reset combat data",session="Fight",type="Meter",target="Filter damage by target"})[button]) .. " " .. record.label
            local ranked, matched = api.SearchPages(query), false
            for i=1,math.min(6,#ranked) do if ranked[i].exactTarget and ranked[i].exactTarget.settingKey == record.exactTarget.settingKey then matched=true end end
            if not matched then print("QUERY",query); for i=1,math.min(12,#ranked) do print(i,ranked[i].label,ranked[i].exactTarget and ranked[i].exactTarget.settingKey) end end
            assert(matched, "contextual query missed top six: "..key)
            local selected, anchored, exact = api.OpenSearchTarget(record.key, record.label, record.label, record.anchor, record.route, record.exactTarget)
            mw:RunTimers()
            assert(selected and anchored and exact, "not exact: "..key)
            local found = assert(M.RuntimeControlCatalog.Get(record.exactTarget.controlId), key)
            assert(found.widget and found.widget:IsVisible(), "setting widget hidden: "..key)
        end
    end
end
CheckRoutes()
for key in pairs(ui.meterPreview.layers) do ui.meterPreview.layers[key] = false end
c.headerVisible, c.headerSelectors, c.targetSelector = false, false, false
ui.refreshPreview()
CheckRoutes()
for key,value in pairs(saved) do assert(P.Get("damageMeter",key)==value, "search changed value: "..key) end
assert(c.headerVisible == false and c.headerSelectors == false and c.targetSelector == false,
    "search enabled a hidden element")
if M.InvalidateSearchProvider and api.WhenIndexReady then
    local originalProbe = M.CastbarSuiteNameplatesSupported
    local available = false
    M.CastbarSuiteNameplatesSupported = function() return available end
    assert(M.InvalidateSearchProvider("MSUF_Suite"))
    assert(Find("provider-off", "general.kickReadyShowNameplates") == 0)
    available = true
    assert(M.InvalidateSearchProvider("MSUF_Suite"))
    assert(Find("provider-on", "general.kickReadyShowNameplates") == 1)
    available = false
    assert(M.InvalidateSearchProvider("MSUF_Suite"))
    assert(Find("provider-off-again", "general.kickReadyShowNameplates") == 0)
    M.CastbarSuiteNameplatesSupported = originalProbe
end
assert(rawget(c, "settingsSize") == nil, "search materialized an absent override")
print("SEARCH_PREVIEW_GAPS_PASS")
