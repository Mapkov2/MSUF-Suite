-- Real-host cold tabs, exact settings, legacy preview routes and rebuild ownership.
local root = assert(arg[1]):gsub("\\", "/")
local host = arg[3] or (root .. "/../MidnightSimpleUnitFrames-7.0")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { locale = "deDE", clientScriptBindings = true })
local env, M, world = mw.env, mw.M, mw.world
world.widgets.Methods.SetTextHeight = function(self, value) self.textHeight=value end
world.widgets.Methods.SetPointsOffset = function(self,x,y) self.pointsOffset={x,y} end
for _,name in ipairs({"SetStartPoint","SetEndPoint","SetThickness"}) do
    if not world.widgets.Methods[name] then world.widgets.Methods[name]=function(self,...) self[name.."Args"]={...} end end
end
env.C_SpecializationInfo = {GetSpecialization=function() return 1 end,
    GetSpecializationInfo=function() return flavor=="Forever" and 1482 or 71,"Fixture specialization" end}
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
    GetAddOnMetadata = function() end, IsAddOnLoaded = function(name) local loaded = name:find("^MSUF") ~= nil or name:find("^MidnightSimpleUnitFrames") ~= nil return loaded, loaded end,
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
env.C_CVar.GetCVar = function() return "1" end
env.C_GameRules = { IsGameRuleActive = function() return false end }
Load("MSUF_Suite", {})
local Suite, P = env.MSUFSuite, {}
assert(Suite.Database.Initialize(nil))
Suite.Suite.Config("nameplates").enabled = true
if arg[4]=="fallback" then M.RegisterSearchTargetResolver=nil end
Load("MSUF_Suite_Options", P)


local enforce=arg[4]~='measure'
P.InvalidateSearch()
local api=M.Search._CoreAPI
local function Ready()
    api.GetSearchRecords()
    local ready=false
    if api.WhenIndexReady then assert(api.WhenIndexReady(function() ready=true end)) else mw:RunTimers(1000); ready=true end
    for i=1,1000 do if ready then break end; mw:RunTimers(1000) end
    assert(ready,'index did not settle')
    return api.GetSearchRecords()
end
local built,widgets,panels={}, {},{}
local RuleGrid=P.RuleGrid
P.RuleGrid=function(ctx,parent,page,id,rules,...)
    if id=='nameplates' then
        for _,section in ipairs(P.NameplateSections) do
            for _,tab in ipairs(section.tabs or {}) do
                if rules==tab.rules then
                    local key=section.key..':'..tab.id
                    built[key]=(built[key] or 0)+1
                    panels[key]=parent
                end
            end
        end
    end
    local y,entries=RuleGrid(ctx,parent,page,id,rules,...)
    if id=='nameplates' then for _,entry in ipairs(entries) do if entry.widget then widgets[entry.rule.key]=entry.widget end end end
    return y,entries
end
local records={}
for _,record in ipairs(Ready()) do
    local setting=record.exactTarget and record.exactTarget.settingKey
    if setting and setting:find('^msufsuite%.nameplates%.') then records[setting]=record end
end
local cases={
    {'enemyTextMode','enemy:text'}, {'enemyTargetStyle','enemy:target'},
    {'friendlyCastHeight','friendly:castbar'}, {'selectionBorder','signals:selection'},
    {'friendlyNpcDebuffs','auras:general'},
}
local saved={}
for _,case in ipairs(cases) do
    assert(records['msufsuite.nameplates.'..case[1]],'missing cold record '..case[1])
    saved[case[1]]=P.Get('nameplates',case[1])
end
assert(not M.cache.suite_nameplates,'target page was prebuilt by cold search')
if enforce then
    local record=records['msufsuite.nameplates.enemyTextMode']
    local selected,anchored,exact=(M.Search._RoutingAPI or api).OpenSearchTarget(record.key,record.label,record.label,record.anchor,record.route,record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact,'first cold page target failed')
    assert(widgets.enemyTextMode and widgets.enemyTextMode:IsVisible(),'first cold page target hidden')
end
assert(M.SelectPage('suite_nameplates'))
mw:RunTimers(1000)
local bySection={}
for key in pairs(built) do local section=key:match('^([^:]+)'); bySection[section]=(bySection[section] or 0)+1 end
for section,n in pairs(bySection) do
    print('initial '..section..' grids='..n)
    if enforce then assert(n<=1,'opening one section built hidden tabs: '..section..' '..n) end
end
local function Open(case)
    assert(M.SelectPage('home'))
    Ready()
    local record=records['msufsuite.nameplates.'..case[1]]
    local selected,anchored,exact=(M.Search._RoutingAPI or api).OpenSearchTarget(record.key,record.label,record.label,record.anchor,record.route,record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact,'cold target did not resolve exactly: '..case[1])
    if widgets[case[1]] and not widgets[case[1]]:IsVisible() then
        local p=widgets[case[1]]
        for i=1,12 do if not p then break end
            print('HIDDEN',i,p:GetName(),p:IsShown(),p.sectionId,p._msufSuiteArea,p._msuf2ExactTabView and p._msuf2ExactTabView.value)
            p=p:GetParent()
        end
    end
    assert(widgets[case[1]] and widgets[case[1]]:IsVisible(),'target is hidden: '..case[1])
    assert(panels[case[2]] and panels[case[2]]:IsVisible(),'correct tab did not become visible: '..case[2])
    assert(built[case[2]]==1,'tab was rebuilt: '..case[2])
end
for _,case in ipairs(cases) do Open(case); Open(case) end
-- Direct preview handles retain the legacy enemy aliases.
assert(P.SelectNameplatesEnemyTab('appearance'))
assert(panels['enemy:bar']:IsVisible(),'legacy appearance did not select bar')
assert(P.SelectNameplatesEnemyTab('elements'))
assert(panels['enemy:markers']:IsVisible(),'legacy elements did not select markers')
assert(built['enemy:markers']==1,'preview alias rebuilt markers')
for key,value in pairs(saved) do assert(P.Get('nameplates',key)==value,'navigation changed setting '..key) end
for key,n in pairs(built) do assert(n==1,'one panel built multiple times '..key) end
assert(M.SelectPage('home'))
M.InvalidatePage('suite_nameplates')
built,widgets,panels={},{},{}
Open({'enemyOuterFrame','enemy:frame'})
print('PASS real host Nameplates cold tab/exact search/legacy preview parity '..flavor)
