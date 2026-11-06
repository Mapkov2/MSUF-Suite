local root=assert(arg[1])
local function Widget(parent)
    local w={shown=true,parent=parent}
    for _,key in ipairs({"SetAllPoints","SetJustifyH","ClearAllPoints","SetFontString","SetExpiredText","SetUpdateInterval",
        "SetDesiredUnitCount","SetMinInterval","SetDefaultAbbreviation","SetWordWrap","SetMaxLines"}) do w[key]=function() end end
    function w:SetPoint(...)
        self.point={...}
        if self.point[1]=="LEFT" then self.left=true end
        if self.point[1]=="RIGHT" then self.right=true end
    end
    function w:SetSize(a,b) self.width,self.height=a,b end
    function w:SetWidth(v) self.width=v end
    function w:SetAlpha(v) self.alpha=v end
    function w:GetStringHeight()
        if self.left and self.right then
            assert(self.parent and self.parent.width and self.parent.width>0,
                "opposing-anchor text measured before its parent width exists")
        end
        return self.fontSize or 12
    end
    function w:SetFormattedText(format,...) self.text=string.format(format,...) end
    function w:SetScale(v) self.scale=v end
    function w:SetColorTexture(...) self.color={...} end
    function w:SetTextColor(...) self.color={...} end
    function w:SetText(v)
        assert(not self.isFontString or self.fontSize,"flight text written before its font was assigned")
        self.text=v
    end
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
TaxiGetNodeSlot=function(i,part) return part+1 end
local hooks,events={},{}
hooksecurefunc=function(name,fn) hooks[name]=fn end
local early=0
TaxiRequestEarlyLanding=function() early=early+1;hooks.TaxiRequestEarlyLanding() end
GameTooltip=Widget();GameTooltip.AddLine=function(self,line) self.line=line end
GameTooltip.Show=function(self) self.shows=(self.shows or 0)+1 end
GameTooltip.ownerReads=0
-- Script hooks as the client runs them: after the original handler, on a show.
GameTooltip.scripts={}
function GameTooltip:HookScript(name,fn) self.scripts[name]=fn end
function GameTooltip:GetOwner() self.ownerReads=self.ownerReads+1;return self.owner end
Enum={FlightPathState={Current=0,Reachable=1,Unreachable=2}}
C_DurationUtil={CreateDuration=Widget,CreateDurationTextBinding=Widget}
local formatters=0
C_StringUtil={CreateSecondsFormatter=function() formatters=formatters+1;return Widget() end}
Enum.SecondsFormatterInterval,Enum.SecondsFormatterAbbreviation={Seconds=0},{OneLetter=2}
local S={}
local state={}
-- The runtime's per-profile module state (MSUF_Suite/Core/Suite.lua).
S.ModuleState=function(id) assert(id=="flightTimer");return state end
S.Public=function(v) return v~="secret" end
S.Finite=function(v) return S.Public(v) and type(v)=="number" and v==v end
S.CreateFrame=function(_,_,parent) return Widget(parent) end
S.CreateTexture=Widget
S.CreateFontString=function(parent) local label=Widget(parent);label.isFontString=true;return label end
S.SetStyledFont=function(label,path,size) label.fontSize=size end;
S.QoLStyleText=function(label,config,path,size) label.style=config; S.SetStyledFont(label,path,size) end;S.GlobalFontPath=function() return "font" end
S.Text=function(v) return v end
local movers={}
S.RegisterOwnedMover=function(id,element,spec) assert(id=="flightTimer");movers[element]=spec end
S.Install=function(id,m) assert(id=="flightTimer");S.module=m end
assert(loadfile((arg[2] or root).."/MSUF_Suite_QualityOfLife/FlightTimer.lua"))("test",{NS={Safety={IsForbidden=function(frame) return frame.forbidden==true end}},Suite=S})
local m=S.module
m.active=true;m.config={width=340,scale=100,x=0,y=0,fontSize=12,showStops=true,routePreview=true,classColor=true,hideDisplay=false}
local tickers={}
m.context={Event=function(_,name,callback) events[name]=callback end, Ticker=function(_,interval,callback)
    local handle={interval=interval,callback=callback,running=true}
    function handle:Cancel() self.running=false end
    tickers[#tickers+1]=handle
    return handle
end}
local function Tick()
    for _,handle in ipairs(tickers) do if handle.running then handle.callback(m) end end
end
local function Running()
    local count=0;for _,handle in ipairs(tickers) do if handle.running then count=count+1 end end;return count
end
m:Enable()
assert(not next(movers),"Enable registered the mover; the controller does it through RegisterMovers")
-- The controller registers the movers right after Enable (S.RefreshEditMover).
m:RegisterMovers()
assert(movers.flight and movers.flight.getFrame()==m.host and movers.flight.xKey=="x","flight timer mover missing")
events.TAXIMAP_OPENED(m)
assert(formatters==1 and m.binding.formatter,"the remaining time is not formatted by the client's seconds formatter")
assert(m.routes[3].key=="A > B > C","native route stops were not reconstructed")
hooks.TaxiNodeOnButtonEnter(Widget())
assert(GameTooltip.line=="A > B > C","taxi route preview lost intermediate stops")
-- FV-12a: the flight map (FlightMapFrame, what Forever's and many Retail
-- flight masters open) shows its nodes as pins whose tooltip is filled by
-- Blizzard and then shown; the route line joins it on that show.
do
    local function Pin(fields)
        local pin=Widget()
        pin.pinTemplate="FlightMap_FlightPointPinTemplate"
        pin.taxiNodeData={slotIndex=3,state=Enum.FlightPathState.Reachable}
        for key,value in pairs(fields or {}) do pin[key]=value end
        return pin
    end
    local function Hover(owner)
        GameTooltip.owner,GameTooltip.line,GameTooltip.shows=owner,nil,0
        assert(GameTooltip.scripts.OnShow,"the flight map pin tooltip is not watched")
        GameTooltip.scripts.OnShow(GameTooltip)
    end
    Hover(Pin())
    assert(GameTooltip.line=="A > B > C" and GameTooltip.shows==1,"flight map pin lost its route preview")
    Hover(Pin({taxiNodeData={slotIndex=2,state=Enum.FlightPathState.Reachable}}))
    assert(GameTooltip.line=="A > B","flight map pin showed another node's route")
    Hover(Pin({taxiNodeData={slotIndex=3,state=Enum.FlightPathState.Unreachable}}))
    assert(GameTooltip.line==nil,"an unreachable flight map node got a route")
    Hover(Pin({taxiNodeData={slotIndex=3,state=Enum.FlightPathState.Current}}))
    assert(GameTooltip.line==nil,"the current flight map node got a route")
    Hover(Pin({isMapLayerTransition=true}))
    assert(GameTooltip.line==nil,"a map transition point got a route")
    Hover(Pin({taxiNodeData={slotIndex="secret",state=Enum.FlightPathState.Reachable}}))
    assert(GameTooltip.line==nil,"a restricted slot index got a route")
    Hover(Pin({forbidden=true}))
    assert(GameTooltip.line==nil,"a forbidden owner was read")
    Hover(Pin({pinTemplate="WorldMap_POIPinTemplate"}))
    assert(GameTooltip.line==nil,"another map pin got a route line")
    Hover(nil)
    assert(GameTooltip.line==nil,"a tooltip without owner got a route line")
    Hover(Widget())
    assert(GameTooltip.line==nil,"an unrelated tooltip got a route line")
    m.config.routePreview=false
    Hover(Pin())
    assert(GameTooltip.line==nil,"the preview switch ignored the flight map")
    m.config.routePreview=true
    m.active=false
    Hover(Pin())
    assert(GameTooltip.line==nil,"a disabled flight timer previewed a route")
    m.active=true
    -- TAXIMAP_OPENED/CLOSED (live, ptr2 and forever; HandleTaxiMapOpened opens
    -- the old TaxiFrame or FlightMapFrame, both close on TAXIMAP_CLOSED): with no
    -- taxi map open the hook returns before it reads anything.
    assert(events.TAXIMAP_CLOSED,"the flight timer does not follow TAXIMAP_CLOSED")
    events.TAXIMAP_CLOSED(m)
    GameTooltip.ownerReads=0
    Hover(Pin())
    assert(GameTooltip.line==nil and GameTooltip.ownerReads==0,
        "a tooltip show with no taxi map open still did work")
    events.TAXIMAP_OPENED(m)
    Hover(Pin())
    assert(GameTooltip.line=="A > B > C" and GameTooltip.ownerReads==1,"reopening the taxi map did not restore the preview")
    m.mapOpen=nil
    GameTooltip.owner=nil
end
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
assert(m.host.shown and m.host.title.text=="A > C" and not m.binding.enabled,
    "takeoff dropped the chosen route, or a first journey invented an estimate")
assert(m.host.time.text=="0:00" and m.host.status.text=="Learning flight time" and Running()==1,
    "first flight has no visible elapsed clock")
assert(m.host.route.text=="B" and m.host.route.shown,"intermediate display repeats the full route")
for _,key in ipairs({"title","route","time","status","landText"}) do
    assert(m.host[key].style==m.config,"flight text bypassed shared QoL font rules: "..key)
end
now=125;Tick();assert(m.host.time.text=="0:25","unknown route elapsed clock does not advance")
local savedTick=tickers[#tickers]
Landed(160)
assert(Running()==0,"elapsed clock kept an idle timer after landing")
local oldText=m.host.time.text;savedTick.callback(m);assert(m.host.time.text==oldText,"late tick repainted after landing")
assert(state.timings["A > B > C"]==60 and not m.host.shown,"completed flight did not learn its time from takeoff")
TakeOff(200)
assert(m.binding.enabled and m.duration.finish==260 and Running()==0,"learned flight ETA not natively bound, or elapsed ticker still runs")
assert(m.host.status.text=="Remaining time","learned route countdown has no remaining-time caption")
m.host.land.OnClick();assert(early==1,"manual early-landing action missing")
assert(not m.host.land.enabled,"landing request left the manual button enabled")
assert(not m.binding.enabled and Running()==1 and m.host.status.text=="Elapsed time",
    "early landing kept an invalid full-route estimate")
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
m:Refresh()
assert(m.departed==400 and m.host.time.text=="0:00" and Running()==1,"mid-flight enable/refresh waits for another taxi event")
now=405;Tick();assert(m.host.time.text=="0:05","reload-in-flight clock failed to advance")
Landed(415)
assert(state.timings["A > B > C"]==60,"reload-in-flight replaced the full learned route")
TakeOff(500)
local old=state;state={};m:Refresh()
assert(m.departed==500.5 and not m.current and Running()==1,"profile switch does not reseed unknown flight elapsed time")
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
-- Exact native slot identity wins even when positions overlap.
do
    local original=TaxiGetNodeSlot
    TaxiGetNodeSlot=function() return 3 end
    nodes[2][2],nodes[2][3]=1,1
    events.TAXIMAP_OPENED(m)
    assert(m.routes[3].key=="A > C","co-located unrelated stop polluted route identity")
    nodes[2][2],nodes[2][3]=.5,.5
    TaxiGetNodeSlot=original
    events.TAXIMAP_OPENED(m)
end
-- A direct route has no duplicate second line; narrow/large-font layout fits.
now=580;hooks.TakeTaxiNode(2);taxi=true;events.UNIT_FLAGS(m,"UNIT_FLAGS","player")
assert(not m.host.route.shown,"direct route repeats its endpoints as stops")
m.config.width,m.config.fontSize=180,24;m:Refresh()
assert(m.host.land.width==160 and m.host.height>100,"narrow large-font footer has invalid geometry")
m.config.hideDisplay=true;m:Refresh();assert(Running()==0,"hidden display keeps elapsed work running")
m.config.hideDisplay=false;Landed(590)
assert(state.timings["A > B"]==10,"direct route did not learn its completed duration")
state.timings["A > B"]=nil
m.config.width,m.config.fontSize=340,12;m:Refresh()
TakeOff(600)
events.TAXIMAP_OPENED(m)
m.active=false;m:Disable();Landed(650)
assert(m.mapOpen==nil,"disabling left the taxi map flag set")
assert(Running()==0,"disable left elapsed work running")
assert(next(state.timings)==nil and not m.host.shown,"disabled flight timer recorded or reopened")
-- Cold enabling on an existing taxi needs no further native flag/control event.
now=700;taxi=true;m.active=true;m:Enable()
assert(m.departed==700 and m.host.time.text=="0:00" and Running()==1,"cold enable failed to seed a running flight")
now=705;Tick();assert(m.host.time.text=="0:05","cold-enabled flight clock stayed blank")
Landed(710);assert(next(state.timings)==nil,"cold enable learned a partial route")
m.active=false;m:Disable()
print("suite_flight_timer_contract: OK")
