local root=assert(arg[1])
local function Widget()
    local w={shown=true}
    for _,key in ipairs({"SetAllPoints","SetJustifyH","ClearAllPoints","SetFontString","SetExpiredText","SetUpdateInterval",
        "SetDesiredUnitCount","SetMinInterval","SetDefaultAbbreviation"}) do w[key]=function() end end
    function w:SetPoint(...) self.point={...} end
    function w:SetSize(a,b) self.width,self.height=a,b end
    function w:SetScale(v) self.scale=v end
    function w:SetColorTexture(...) self.color={...} end
    function w:SetTextColor(...) self.color={...} end
    function w:SetText(v) self.text=v end
    function w:SetScript(k,v) self[k]=v end
    function w:SetShown(v) self.shown=v end
    function w:Hide() self.shown=false end
    function w:SetEnabled(v) self.enabled=v end
    function w:SetTimeFromEnd(finish,duration) self.finish,self.duration=finish,duration end
    function w:SetDuration(v) self.bound=v end
    function w:SetFormatter(v) self.formatter=v end
    function w:GetID() return 3 end
    return w
end
local now,taxi=100,false
GetTime=function() return now end
UnitOnTaxi=function() return taxi end
UnitClass=function() return "Warrior","WARRIOR" end
RAID_CLASS_COLORS={WARRIOR={r=.7,g=.5,b=.3}}
UIParent=Widget()
wipe=function(t) for k in pairs(t) do t[k]=nil end end
local nodes={{"A",0,0},{"B",.5,.5},{"C",1,1}}
NumTaxiNodes=function() return 3 end
TaxiNodeName=function(i) return nodes[i][1] end
TaxiNodeGetType=function(i) return i==1 and "CURRENT" or "REACHABLE" end
TaxiNodePosition=function(i) return nodes[i][2],nodes[i][3] end
GetNumRoutes=function(i) return i-1 end
TaxiGetDestX=function(i,part) return nodes[part+1][2] end
TaxiGetDestY=function(i,part) return nodes[part+1][3] end
local hooks,events={},{}
hooksecurefunc=function(name,fn) hooks[name]=fn end
local early=0
TaxiRequestEarlyLanding=function() early=early+1;hooks.TaxiRequestEarlyLanding() end
GameTooltip=Widget();GameTooltip.AddLine=function(self,line) self.line=line end;GameTooltip.Show=function() end
C_DurationUtil={CreateDuration=Widget,CreateDurationTextBinding=Widget}
local formatters=0
C_StringUtil={CreateSecondsFormatter=function() formatters=formatters+1;return Widget() end}
Enum={SecondsFormatterInterval={Seconds=0},SecondsFormatterAbbreviation={OneLetter=2}}
local S={}
local state={}
-- The runtime's per-profile module state (MSUF_Suite/Core/Suite.lua).
S.ModuleState=function(id) assert(id=="flightTimer");return state end
S.Public=function(v) return v~="secret" end
S.Finite=function(v) return S.Public(v) and type(v)=="number" and v==v end
S.CreateFrame=Widget;S.CreateTexture=Widget;S.CreateFontString=Widget
S.SetStyledFont=function() end;S.GlobalFontPath=function() return "font" end
S.Text=function(v) return v end
local movers={}
S.RegisterOwnedMover=function(id,element,spec) assert(id=="flightTimer");movers[element]=spec end
S.Install=function(id,m) assert(id=="flightTimer");S.module=m end
assert(loadfile(root.."/MSUF_Suite_QualityOfLife/FlightTimer.lua"))("test",{NS={},Suite=S})
local m=S.module
m.active=true;m.config={width=340,scale=100,x=0,y=0,fontSize=12,showStops=true,routePreview=true,classColor=true,hideDisplay=false}
m.context={Event=function(_,name,callback) events[name]=callback end}
m:Enable()
assert(not next(movers),"Enable registered the mover; the controller does it through RegisterMovers")
-- The controller registers the movers right after Enable (S.RefreshEditMover).
m:RegisterMovers()
assert(movers.flight and movers.flight.getFrame()==m.host and movers.flight.xKey=="x","flight timer mover missing")
events.TAXIMAP_OPENED(m)
assert(formatters==1 and m.binding.formatter,"the remaining time is not formatted by the client's seconds formatter")
assert(m.routes[3].key=="A > B > C","native route stops were not reconstructed")
hooks.TaxiNodeOnButtonEnter(Widget())
assert(GameTooltip.line=="A → B → C","taxi route preview lost intermediate stops")
-- The client's takeoff order: TakeTaxiNode returns before the flight starts,
-- PLAYER_CONTROL_LOST arrives while UnitOnTaxi is still false, the taxi flag
-- follows with UNIT_FLAGS.
local function TakeOff(at)
    now=at;hooks.TakeTaxiNode(3)
    events.PLAYER_CONTROL_LOST(m,"PLAYER_CONTROL_LOST")
    now=at+.5;taxi=true;events.UNIT_FLAGS(m,"UNIT_FLAGS","player")
end
local function Landed(at)
    now=at;taxi=false;events.PLAYER_CONTROL_GAINED(m,"PLAYER_CONTROL_GAINED")
end
TakeOff(100)
assert(m.host.shown and m.host.title.text=="A → C" and not m.binding.enabled,
    "takeoff dropped the chosen route, or a first journey invented an estimate")
Landed(160)
assert(state.timings["A > B > C"]==60 and not m.host.shown,"completed flight did not learn its time from takeoff")
TakeOff(200)
assert(m.binding.enabled and m.duration.finish==260,"learned flight ETA not natively bound")
m.host.land.OnClick();assert(early==1,"manual early-landing action missing")
Landed(215)
assert(state.timings["A > B > C"]==60,"early landing overwrote full route duration")
-- A refused choice followed by an unrelated loss of control (a stun) never
-- reaches the taxi flag; that is no journey.
now=300;hooks.TakeTaxiNode(3)
now=302;events.PLAYER_CONTROL_LOST(m,"PLAYER_CONTROL_LOST")
now=302.5;events.UNIT_FLAGS(m,"UNIT_FLAGS","player")
Landed(306)
assert(state.timings["A > B > C"]==60,"refused request or unrelated control loss fabricated flight timing")
-- A flight long after the last choice has no known route.
now=310;hooks.TakeTaxiNode(3)
now=330;events.PLAYER_CONTROL_LOST(m,"PLAYER_CONTROL_LOST")
taxi=true;events.UNIT_FLAGS(m,"UNIT_FLAGS","player")
assert(m.host.title.text=="Flight route unavailable","a stale choice was taken as the current route")
Landed(390)
assert(state.timings["A > B > C"]==60,"a flight on an unknown route taught a route time")
-- Enabling/reloading in flight has no captured route and must not learn a partial trip.
taxi=true;now=400;m.current,m.departed,m.requested=nil,nil,nil
events.UNIT_FLAGS(m,"UNIT_FLAGS","player")
Landed(415)
assert(state.timings["A > B > C"]==60,"reload-in-flight replaced the full learned route")
TakeOff(500)
local old=state;state={};m:Refresh()
Landed(530)
assert(next(state.timings)==nil and old.timings["A > B > C"]==60,"profile switch wrote a foreign in-progress route")
-- UNIT_FLAGS and the control events fire for far more than flights. A storm
-- of them, on the ground or in the air, lays nothing out, draws nothing
-- again and allocates nothing.
local fonts, texts = 0, 0
S.SetStyledFont = function() fonts = fonts + 1 end
local titleText = m.host.title.SetText
m.host.title.SetText = function(self, value) texts = texts + 1; titleText(self, value) end
for _, flying in ipairs({ false, true }) do
    taxi = flying
    events.UNIT_FLAGS(m, "UNIT_FLAGS", "player")
    fonts, texts = 0, 0
    collectgarbage("collect"); collectgarbage("stop")
    local memory = collectgarbage("count")
    for _ = 1, 1000 do
        events.UNIT_FLAGS(m, "UNIT_FLAGS", "player")
        events.PLAYER_CONTROL_GAINED(m, "PLAYER_CONTROL_GAINED")
    end
    local allocated = collectgarbage("count") - memory
    collectgarbage("restart")
    assert(fonts == 0 and texts == 0 and allocated < 1,
        "flag and control events laid out, redrew or allocated the flight display: " .. allocated .. " KB")
end
Landed(now)
assert(next(state.timings) == nil and not m.host.shown, "the event storm taught or kept a flight")
TakeOff(600)
m.active=false;m:Disable();Landed(650)
assert(next(state.timings)==nil and not m.host.shown,"disabled flight timer recorded or reopened")
print("suite_flight_timer_contract: OK")
