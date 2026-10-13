local root, case = assert(arg[1]), assert(arg[2])
local function Check(value, message) assert(value, message) end
local function GetUpvalue(fn, wanted)
    for index=1,100 do
        local name,value=debug.getupvalue(fn,index)
        if not name then break end
        if name==wanted then return value end
    end
    error('missing real upvalue '..wanted)
end
local reported={}
securecallfunction=function(callback,...)
    local result={pcall(callback,...)}
    if not result[1] then reported[#reported+1]=tostring(result[2]);return end
    return unpack(result,2)
end
issecretvalue=function() return false end
local methods={}
local function Void() end
local function Frame(parent)
    return setmetatable({parent=parent,shown=true,scripts={},height=58,width=520,heightWrites=0},
        {__index=function(_,key) return methods[key] or key:match('^%u') and Void or nil end})
end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(value) self.shown=value end
function methods:GetParent() return self.parent end
function methods:SetParent(value) self.parent=value end
function methods:SetScript(key,value) self.scripts[key]=value end
function methods:GetScript(key) return self.scripts[key] end
function methods:SetHeight(value) self.height=value;self.heightWrites=self.heightWrites+1 end
function methods:SetWidth(value) self.width=value end
function methods:SetSize(width,height) self.width,self.height=width,height end
function methods:GetHeight() return self.height end
function methods:GetWidth() return self.width end
function methods:GetFrameLevel() return 2 end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetVerticalScroll() return 0 end
function methods:CreateTexture() return Frame(self) end
function methods:CreateFontString() return Frame(self) end
function methods:SetText(value) self.text=value end
function methods:GetText() return self.text or '' end
function methods:GetFont() return self.font or 'NATIVE.TTF',self.fontSize or 11,'' end
function methods:SetFont(path,size) self.font,self.fontSize=path,size end
function methods:SetValue(value) self.value=value end
function methods:GetValue() return self.value or 0 end
function methods:GetStringHeight() return 14 end
CreateFrame=function(_,_,parent) return Frame(parent) end
UIParent=Frame()
C_Timer={After=function(_,callback) callback() end}
SOUNDKIT={IG_MAINMENU_OPTION_CHECKBOX_ON=1}
PlaySound=Void
IsControlKeyDown=function() return false end
IsShiftKeyDown=function() return false end
local DBRoot={}
local NS={path='Interface\\AddOns\\MSUF_Suite_Skin\\',Client={isMainline=true,isForever=false},L=setmetatable({}, {__index=function(_,key) return key end}),
    Database={GetRoot=function() return DBRoot end},Registry={AddListener=Void},
    IsCombatLocked=function() return false end,Theme={GetColor=function() return .2,.3,.4,1 end}}
local fault, activePage, attachAttempts=false,nil,0
local priorShell,priorMode
NS.Surface={Attach=function(frame,spec)
    if frame.parent==activePage and spec.role=='navigation' then
        attachAttempts=attachAttempts+1
        if fault then
            NS.Options.TrackRefresh(priorShell)
            NS.Options.TrackMode(priorMode)
            error('injected native surface attach failure after real Looks controls')
        end
    end
    return frame
end,SkinOwnedButton=Void,SetActive=Void,SetVisible=Void}
MSUFSuite={Client={PauseControllerWindow=Void,ResumeControllerWindow=Void}}
MapkoSkin=NS
local private={}
local function Load(addon,path,space)
    assert(loadfile(root..'/'..addon..'/'..path))(addon,space)
end
Load('MSUF_Suite_Skin','Core/Safety.lua',NS)
Load('MSUF_Suite_Skin','Adapters/AdapterKit.lua',NS)
Load('MSUF_Suite_Skin','Core/Defaults.lua',NS)
Load('MSUF_Suite_Skin','Core/DefaultsLooks.lua',NS)
NS.DB=NS.CopyValue(NS.Defaults)
Load('MSUF_Suite_Skin_Options','MSKIN_OptionsBootstrap.lua',private)
local O=NS.Options
local priorShellRuns,priorModeRuns=0,0
priorShell=function() priorShellRuns=priorShellRuns+1 end
priorMode=function() priorModeRuns=priorModeRuns+1 end
O.TrackRefresh(priorShell)
O.TrackMode(priorMode)
for _,path in ipairs({'Shell/Theme.lua','Shell/Widgets.lua','Shell/WidgetsInput.lua',
    'Shell/WidgetsDropdown.lua','Shell/Window.lua','Shell/Embedded.lua','Pages/Looks.lua'}) do
    Load('MSUF_Suite_Skin_Options',path,private)
end
O.GetPageMeta=function() return {simple=true} end
local realBuilder=assert(O.GetPageDefinition('looks')).builder
local builds=0
O.GetPageDefinition('looks').builder=function(page)
    builds=builds+1;activePage=page
    realBuilder(page)
end
local ShowEmbeddedPage=GetUpvalue(GetUpvalue(O.Mount,'CreateHost'),'ShowEmbeddedPage')
local ShowWindowPage=GetUpvalue(GetUpvalue(O.BuildWindow,'CreateWindow'),'ShowWindowPage')
local host=Frame();host.content=Frame(host);host.pages={};host.buttons={}
local window=Frame()
local state={window=window,pageHost=Frame(window),pageFrames={},navButtons={looks=Frame(window)},
    searchPopup=Frame(window),pageTitle=Frame(window),pageContext=Frame(window)}
local function ShowEmbedded() return ShowEmbeddedPage(host,'looks') end
local function ShowWindow() return ShowWindowPage(state,'looks') end
local show=case:find('window',1,true) and ShowWindow or ShowEmbedded
local function CurrentPage() return host.pages.looks or state.pageFrames.looks end
local function CallShow()
    local function Finish() return show()~=false end
    return NS.Safety.Dispatch(Finish)==true
end
if case=='nested-context' then
    local outer,inner=Frame(host),Frame(host)
    local beforeRuns,afterRuns=0,0
    local before=function() beforeRuns=beforeRuns+1 end
    local after=function() afterRuns=afterRuns+1 end
    O.BuildPage(outer,host,function()
        O.TrackRefresh(before)
        O.BuildPage(inner,host,realBuilder)
        O.TrackRefresh(after)
    end)
    Check(inner._mskinLookNoteText,'nested real Looks builder failed')
    outer:Hide()
    O.RefreshAll()
    print('nested outer hidden callback runs:',beforeRuns,afterRuns)
    Check(beforeRuns==0 and afterRuns==0,'nested page lost its outer registration context')
    Check(GetUpvalue(O.TrackRefresh,'buildingPage')==nil,'nested build left active context')
    print('PASS nested-context restores outer scope and ends global scope')
    return
end
if case=='normal-embedded' or case=='normal-window' then
    Check(CallShow(),'normal real Looks builder failed: '..tostring(reported[1]))
    Check(CurrentPage()._mskinLookNoteText,'normal Looks page incomplete')
    CurrentPage():Hide()
    local shells=0
    O.TrackRefresh(function() shells=shells+1 end)
    O.RefreshAll()
    Check(shells==1,'normal shell callback classification failed')
    Check(CallShow() and builds==1,'normal cached page was unnecessarily rebuilt')
    Check(#reported==0,'normal case reported an error')
    print('PASS '..case..' real Looks builder + shell visibility + cached reuse')
    return
end
fault=true
Check(not CallShow() and #reported==1 and reported[1]:find('injected native surface',1,true),
    'fault did not reach the real Looks builder path: '..tostring(reported[1]))
local broken=CurrentPage() or activePage
Check(broken and not broken._mskinLookNoteText,'expected partially built cached Looks page')
local orphanList=broken._mskinLooksContent
local entry=GetUpvalue(O.TrackRefresh,'buildingPage')
print('observed '..case..': cachedPartial='..tostring(CurrentPage()~=nil)..', staleContext='..tostring(entry~=nil)
    ..', partialRefreshers='..tostring(entry and #entry or 0)..', builds='..builds)
if case=='context' then
    broken:Hide()
    local shells=0
    O.TrackRefresh(function() shells=shells+1 end)
    O.RefreshAll()
    print('shell callback runs after hidden broken page:',shells)
    Check(shells==1,'builder error captured later shell callback into hidden partial page')
    local shellBefore=priorShellRuns
    O.TrackRefresh(priorShell)
    O.RefreshAll()
    Check(priorShellRuns==shellBefore+1,'failure lost or duplicated a pre-existing shell callback')
    O.TrackMode(priorMode)
    O.SetMode(O.GetMode()=='guided' and 'expert' or 'guided')
    Check(priorModeRuns==1,'failure lost or duplicated a pre-existing mode callback')
elseif case=='retry-embedded' or case=='retry-window' then
    fault=false
    Check(CallShow(),'retry still raised')
    print('retry builds:',builds,'surface attempts:',attachAttempts,'note completed:',broken._mskinLookNoteText~=nil)
    Check(CurrentPage()._mskinLookNoteText,'cached partial page bypassed builder on retry')
    Check(builds==2,'retry did not rebuild failed page')
elseif case=='retry-direct-mode' then
    fault=false
    local writes=orphanList.heightWrites
    O.BuildPage(broken,host,realBuilder)
    Check(broken._mskinLookNoteText,'direct BuildPage retry failed to complete real Looks builder')
    local mode=O.GetMode()=='guided' and 'expert' or 'guided'
    O.SetMode(mode)
    print('abandoned first controls list mode writes:',orphanList.heightWrites-writes)
    Check(orphanList.heightWrites==writes,'failed page kept an orphaned real StackRows mode listener')
elseif case=='recovery-newpage' then
    fault=false
    local replacement=Frame(host)
    activePage=replacement
    O.BuildPage(replacement,host,realBuilder)
    Check(replacement._mskinLookNoteText,'healthy later build failed')
    Check(GetUpvalue(O.TrackRefresh,'buildingPage')==nil,'healthy later build did not clear context')
    broken:Hide();replacement:Hide()
    local shells=0
    O.TrackRefresh(function() shells=shells+1 end)
    O.RefreshAll()
    Check(shells==1,'healthy later page failed to restore shell classification')
    print('PASS recovery-newpage healthy later real Looks build restores shell classification')
else error('unknown case '..case) end
