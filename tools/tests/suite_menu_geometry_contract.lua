-- Real-host retained headers and Nameplates hover-art visibility across lazy tabs.
local root = assert(arg[1]):gsub("\\", "/")
local host = arg[3] or (root .. "/../MidnightSimpleUnitFrames-7.0")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { locale = "deDE", clientScriptBindings = true,
    beforeCore = function(world)
        world.widgets.Methods.SetParent = function(self, parent)
            if self.parent == parent then return end
            if self.parent then
                for _,list in ipairs({self.parent.children,self.parent.regions}) do
                    for i=#list,1,-1 do if list[i]==self then table.remove(list,i) end end
                end
            end
            self.parent=parent
            if parent then
                local kind=self:GetObjectType()
                local list=(kind=="Texture" or kind=="FontString") and parent.regions or parent.children
                list[#list+1]=self
            end
        end
        for _,name in ipairs({"SetSize","SetWidth","SetHeight"}) do
            local setter=world.widgets.Methods[name]
            world.widgets.Methods[name]=function(self,...)
                local w,h=self:GetWidth(),self:GetHeight()
                setter(self,...)
                if (self._msuf2ControlKind=="segment" or self._msuf2StickyPageHeaderRecord)
                    and (self:GetWidth()~=w or self:GetHeight()~=h) then
                    MenuWorld.FireScript(self,"OnSizeChanged",self:GetWidth(),self:GetHeight())
                end
            end
        end
    end })
local env, M, world = mw.env, mw.M, mw.world
world.widgets.Methods.GetUnboundedStringWidth = function(self) return self:GetStringWidth() end
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
Load("MSUF_Suite_Options", P)



env.GameTooltip = {SetOwner=function() end, SetText=function() end, AddLine=function() end, Show=function() end, Hide=function() end}
local width, checks = 1300, 0
M.GetContentMetrics=function() return width,900 end
M.Theme.ReducedMotionEnabled=function() return true end
local function Check(ok,message) checks=checks+1; assert(ok,message) end
local function CheckHeader(entry)
    Check(entry.pageHeaders and #entry.pageHeaders>0, "page has no navigation header")
    local workspace=entry.context.suiteWorkspace
    if workspace then
        Check(workspace.chooseTab and not workspace.selector,"workspace replaced direct tabs with dropdown")
    end
    local choices=0
    for _,record in ipairs(entry.pageHeaders or {}) do
        local section=record.section
        for _,child in ipairs({section:GetChildren()}) do
            if child._msuf2ControlKind=="segment" and child.buttons then
                local _,_,_,x=child:GetPoint()
                Check((x or 0)+child:GetWidth()<=section:GetWidth()+.01,"tab strip exceeds header")
                for _,button in ipairs(child.buttons) do
                    if workspace and section==workspace.header then
                        choices=choices+1
                        Check(button:IsVisible(),"direct workspace tab is hidden")
                        local caption=button._msuf2Label
                        Check(caption._msuf2FontRole=="control","workspace tab kept its action-button font")
                        Check(button:GetWidth()>=caption:GetStringWidth()+20,"workspace caption clips at this width")
                        local selected=workspace.selected
                        MenuWorld.FireScript(button,"OnClick")
                        Check(workspace.selected==button._msuf2Value,"direct tab click did not select its area")
                        for id,group in pairs(workspace.groups) do
                            Check(group.frame:IsShown()==(id==workspace.selected),"tab click showed wrong settings group")
                        end
                        workspace.select(selected)
                    end
                    local _,relative,_,bx=button:GetPoint()
                    if relative==child then
                        Check((bx or 0)+button:GetWidth()<=child:GetWidth()+.01,"choice exceeds tab strip")
                    end
                end
            end
        end
    end
    if workspace then Check(choices==#workspace.spec.tabs,"a workspace area has no visible tab") end
    local ui=entry.context.dataTextWorkspace
    if ui then
        local panel = ui.navigation
        local selector = assert(entry.context.dataTextBarSelector)
        local function Bounds(widget, name)
            local point, relative, anchor, x, y = widget:GetPoint()
            Check(point=="TOPLEFT" and relative==panel and anchor=="TOPLEFT", name.." lost its header anchor")
            local right, bottom = x+widget:GetWidth(), y-widget:GetHeight()
            Check(y<=-32 and bottom>=-panel:GetHeight(), name.." clips the DataTexts header vertically")
            Check(x>=16 and right<=panel:GetWidth()-16+.01, name.." clips the DataTexts header horizontally")
            return x, y, right, bottom
        end
        local _, top, right, bottom = Bounds(selector, "Bar selector")
        local addX, addTop, addRight, addBottom = Bounds(ui.buttons.add, "Add bar")
        local deleteX, deleteTop = Bounds(ui.buttons.delete, "Delete bars")
        Check(addTop==deleteTop and addRight<deleteX, "DataTexts actions do not share one row")
        if panel:GetWidth()>=520 then
            Check(right<addX and math.abs(top+bottom-addTop-addBottom)<.01,
                "Bar selector is not aligned beside the DataTexts actions")
        else
            Check(bottom>addTop, "DataTexts actions overlap the selector at narrow widths")
        end
    end
end
if arg[4] == "fixture" then
    return { env = env, M = M, world = world, mw = mw, P = P, MenuWorld = MenuWorld }
end
for _,page in ipairs({"suite_bags","suite_damageMeter","suite_dataTexts"}) do
    local first
    for _,size in ipairs({1300,680,950,620,1300}) do
        M.SelectPage("home")
        width=size
        assert(M.SelectPage(page),page)
        mw:RunTimers(1000)
        local entry=M.cache[page]
        first=first or entry
        Check(entry==first,page.." resize recreated widgets")
        CheckHeader(entry)
    end
end
-- A narrow FIRST open must retain the same direct navigation as a cached resize.
for _,page in ipairs({"suite_damageMeter","suite_bags"}) do
    for _,size in ipairs({620,720,900}) do
        M.SelectPage("home")
        M.InvalidatePage(page)
        width=size
        assert(M.SelectPage(page))
        mw:RunTimers(1000)
        CheckHeader(M.cache[page])
    end
end
M.SelectPage("home")
M.InvalidatePage("suite_dataTexts")
Suite.Suite.Config("dataTexts").barIds="1,2,3,4,5,6"
for _,size in ipairs({1300,680,950,620,1300}) do
    M.SelectPage("home")
    width=size
    assert(M.SelectPage("suite_dataTexts"))
    mw:RunTimers(1000)
    CheckHeader(M.cache.suite_dataTexts)
end
local W=M.Widgets
local captured={}
local grid=P.RuleGrid
P.RuleGrid=function(...)
    local y,entries=grid(...)
    for _,entry in ipairs(entries or {}) do if entry.widget then captured[entry.rule.key]=entry.widget end end
    return y,entries
end
M.SelectPage("suite_nameplates")
mw:RunTimers(1000)
for _,spec in ipairs(P.NameplateSections) do
    for _,tab in ipairs(spec.tabs or {}) do if spec.select then spec.select(tab.id) end end
end
for key,button in pairs(captured) do
    local hover=button._msuf2ToggleRowHover
    if hover then
        Check(not hover:IsShown(),key.." idle hover artwork is shown")
        local hit=button._msuf2LabelHit
        MenuWorld.FireScript(hit,"OnEnter")
        if button:IsEnabled() then Check(hover:IsShown(),key.." hover feedback missing") end
        MenuWorld.FireScript(hit,"OnLeave")
        Check(not hover:IsShown(),key.." leave retained hover artwork")
        W.SetControlShown(button,false)
        W.SetControlShown(button,true)
        Check(not hover:IsShown(),key.." reopen exposed hover artwork")
        W.SetControlEnabled(button,false)
        MenuWorld.FireScript(hit,"OnEnter")
        Check(not hover:IsShown(),key.." disabled hover artwork is shown")
    end
end
Check(checks>200,"missing real Nameplates coverage")
print("PASS menu geometry/idle-toggle lifecycle "..flavor.." "..checks.." checks")
