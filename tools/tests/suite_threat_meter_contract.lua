local root = assert(arg[1])
local function Widget(parent)
    local w = { parent = parent, shown = true, wheelCalls = 0 }
    for _, key in ipairs({ "SetStatusBarTexture", "SetMinMaxValues", "SetAllPoints", "ClearAllPoints", "SetJustifyH" }) do w[key] = function() end end
    function w:SetScript(key, value) self[key] = value end
    function w:EnableMouseWheel(value) self.wheel, self.wheelCalls = value, self.wheelCalls + 1 end
    function w:SetPoint(...) self.point = {...} end
    function w:SetScale(value) self.scale = value end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetShown(value) self.shown = value end
    function w:Hide() self.shown = false end
    function w:SetColorTexture(...) self.color = {...} end
    function w:SetStatusBarColor(...) self.color = {...} end
    function w:SetValue(value) self.value = value end
    function w:SetText(value) self.text = value end
    return w
end
local units = { player=true, party1=true, pet=true, target=true, targettarget=true, focus=true }
local threats = { player={false,1,90,99,9000}, party1={true,3,100,100,10000}, pet={false,0,25,25,2500} }
local friendly = true
UIParent = Widget()
UnitExists=function(unit) return units[unit] end
UnitCanAssist=function(_,unit) return unit=="target" and friendly end
UnitCanAttack=function(_,unit) return unit=="targettarget" or unit=="focus" or unit=="target" and not friendly end
UnitDetailedThreatSituation=function(unit,enemy) assert(enemy=="targettarget" or enemy=="focus" or enemy=="target"); return unpack(threats[unit] or {}) end
UnitName=function(unit) return unit end
UnitClass=function() return "Warrior","WARRIOR" end
UnitIsUnit=function(a,b) return a==b end
IsInRaid=function() return false end
GetNumGroupMembers=function() return 2 end
RAID_CLASS_COLORS={WARRIOR={r=.7,g=.5,b=.3}}
wipe=function(t) for k in pairs(t) do t[k]=nil end end
local queued, delays, sounds = {}, {}, 0
C_Timer={After=function(delay,callback) delays[#delays+1]=delay; queued[#queued+1]=callback end}
SOUNDKIT={RAID_WARNING=1}
PlaySound=function() sounds=sounds+1 end
local S={}
local NS={Suite=S,MSUFMedia={barTexture="bar"},Dispatch=function(callback,...) return callback(...) end}
S.Public=function(v) return v~="secret" end
S.Finite=function(v) return S.Public(v) and type(v)=="number" and v==v end
S.CreateFrame=function(_,_,parent) return Widget(parent) end
S.CreateTexture=function(parent) return Widget(parent) end
S.CreateFontString=S.CreateTexture
S.GlobalFontPath=function() return "font" end
S.SetStyledFont=function() end
-- Formats are translated, then filled in: the test locale marks the lookup.
S.Text=function(v) return v=="%.1f%% of pull" and "pull %.1f%%" or v end
local movers={}
S.RegisterOwnedMover=function(_,key,spec) movers[key]=spec end
S.Install=function(id,m) assert(id=="threatMeter"); S.module=m end
assert(loadfile(root.."/MSUF_Suite_QualityOfLife/ThreatMeter.lua"))("test",{NS=NS,Suite=S})
local m=S.module
m.active=true
m.config={rows=1,width=260,rowHeight=20,fontSize=11,scale=100,mainX=0,mainY=0,focusX=100,focusY=100,
    windows=3,includePets=true,showThreshold=true,pullAlert=90,numberMode=1}
local events={}
local TimerContext=dofile(root.."/tools/tests/suite_test_support.lua").ModuleTimers(root,S,NS)
m.context=TimerContext("threatMeter",m,{Event=function(_,name,callback) events[name]=callback end})
m:Enable()
m:RegisterMovers() -- the controller registers movers after Enable
assert(m.records.main[1].unit=="party1" and #m.records.main==3 and m.windows.focus.shown,
    "native hostile target, sorted roster, pets or focus window missing")
assert(movers.focus.visible() and movers.main.visible(), "target and focus windows lack their movers")
assert(sounds==1 and m.windows.main.rows[1].marker.shown,"pull threshold mark or alert missing")
m:Update(); assert(sounds==1,"alert repeated without crossing its threshold")
assert(m.windows.main.wheel==true,"more members than rows did not enable scrolling")
threats.player={true,3,100,100,12000}
m:Update()
assert(not m.windows.main.rows[1].marker.shown and sounds==1,
    "already tanking player received a false takeover threshold or alert")
threats.player={false,1,90,99,9000}
m:Update()
m.windows.main.OnMouseWheel(nil,-1)
assert(m.windows.main.rows[1].text.text:find("player",1,true),"scrolling did not reveal remaining participants")
m.config.numberMode=3;m:Refresh()
assert(m.windows.main.rows[1].text.text:find("pull 90.0%",1,true),"the pull share did not use the translated format")
threats.player={false,1,"secret",99,9000}
m:Update();assert(#m.records.main==2,"restricted threat was sorted or displayed")
m.config.includePets=false;m.config.windows=1;m:Refresh()
assert(#m.records.main==1 and not m.windows.focus.shown and not movers.focus.visible(),"pet/focus opt-out ignored")
-- With no more members than rows the wheel goes back to the camera.
local wheelCalls=m.windows.main.wheelCalls
assert(m.windows.main.wheel==false,"the meter kept the mouse wheel without anything to scroll")
m:Update()
assert(m.windows.main.wheelCalls==wheelCalls,"the wheel state was rewritten on every repaint")
m.config.windows=2;m:Refresh()
assert(m.enemies.main=="focus" and not m.windows.focus.shown,"the focus-only window did not watch the focus")
m.config.windows=1;m:Refresh()
m.config.pullAlert=0;threats.player={false,1,95,99,9500};sounds=0
m:Update();assert(sounds==0,"a disabled alert still played")
events.UNIT_TARGET(m,"UNIT_TARGET","nameplate12")
events.UNIT_THREAT_LIST_UPDATE(m,"UNIT_THREAT_LIST_UPDATE","nameplate12")
assert(#queued==0,"unrelated world threat/target events scheduled a roster scan")
events.UNIT_THREAT_LIST_UPDATE(m,"UNIT_THREAT_LIST_UPDATE","targettarget")
events.UNIT_THREAT_LIST_UPDATE(m,"UNIT_THREAT_LIST_UPDATE","targettarget")
assert(#queued==1 and delays[1]>=.2,"threat bursts were not throttled to a few repaints per second")
m.active=false;m:Disable();queued[1]()
assert(not m.windows.main.shown,"late callback reopened disabled meter")
print("suite_threat_meter_contract: OK")
