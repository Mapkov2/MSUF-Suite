-- Independent lifecycle and sink regressions. Each case runs in a fresh VM.
-- Fixtures supply native APIs; the actual product files supply every behavior.
local root, selected = assert(arg[1], "repository root required"), assert(arg[2], "case required")
local function PrefixFixture(name, marker, body)
    local handle=assert(io.open(root.."/tools/tests/"..name,"rb"))
    local source=handle:read("*a");handle:close()
    source=source:gsub("\r\n","\n")
    local edge=assert(source:find(marker,1,true),"fixture setup marker missing: "..name)
    assert(loadstring(source:sub(1,edge-1).."\n"..body,"@longterm:"..name))()
end

if selected == "run_summary" then
    PrefixFixture("suite_run_summary_contract.lua", "-- Counts the cards shown", [=[
local function Event(event,...)
    assert(context.events[event],"missing event "..event)(summary,event,...)
end
UnitGUID=function(unit) return unit=="player" and "Player-1" or nil end
UnitFullName=function() return "Player" end
C_SpecializationInfo={GetSpecialization=function() return 1 end,GetSpecializationInfo=function() return 62 end}
GetSpecializationInfoByID=function() return 62,"Arcane" end
GetAverageItemLevel=function() return 220,219 end
C_PlayerInfo={GetPlayerMythicPlusRatingSummary=function() return {currentSeasonScore=1100} end}
local readable=true
S.ReadDamageMeterTotals=function()
 if not readable then return nil end
 return {damage={['Player-1']=1000},damageTaken={['Player-1']=10},interrupts={['Player-1']=1},deaths={['Player-1']=0}}
end
info.members={{memberGUID='Player-1',name='Player'}}
summary.config.keepRuns=30
Event('CHALLENGE_MODE_START')
readable=false
combat=true
Event('CHALLENGE_MODE_COMPLETED')
assert(#state.history==1)
combat=false
summary.active=false
summary:Disable()
context:CancelTimers()
summary.active=true
summary:Enable()
print('history before unrelated combat end',#state.history)
Event('PLAYER_REGEN_ENABLED')
print('history after unrelated combat end',#state.history)
local duplicated = #state.history ~= 1
-- Saved history remains available, while a real new run has fresh aggregates.
summary:ShowHistory()
assert(summary.current==state.history[1], 'legitimate saved history became inaccessible')
summary:Close()
readable=true
local beforeNewRun=#state.history
Event('CHALLENGE_MODE_START')
info.level=16
Event('CHALLENGE_MODE_COMPLETED')
assert(#state.history==beforeNewRun+1 and state.history[1].level==16,
 'a new actual run after re-enable was not saved')
Event('CHALLENGE_MODE_COMPLETED_REWARDS')
assert(#state.history==beforeNewRun+1, 'reward update duplicated the actual new run')
print('real new run and reward dedup PASS; saved history accessible PASS')
assert(not duplicated, 'disable/re-enable duplicated a previous completion at unrelated combat end')

]=])
elseif selected == "meter" then
    PrefixFixture("suite_damage_meter_contract.lua", "-- The outline frames", [=[
local before=dispatches
D.MarkAll();D.PaintDirty()
assert(dispatches-before==2,'two eligible windows require exactly two native boundaries')
local vm=0
D.MarkAll()
debug.sethook(function() vm=vm+1 end,'',1)
D.PaintDirty()
debug.sethook()
assert(vm<=3344,'warm repaint exceeded accepted 3344 VM budget: '..vm)
print('warm two-window VM',vm,'baseline3308; accepted+36/+1.09% and+2 native calls')
-- Hidden/faded windows should add no isolation calls.
local origShown=heal.shown;heal.shown=false
before=dispatches
D.MarkAll();D.PaintDirty()
assert(dispatches-before==1,'one eligible window requires exactly one native boundary')
heal.shown=origShown

win.faded,heal.faded=true,true
before=dispatches;D.MarkAll();D.PaintDirty()
assert(dispatches-before==0,'faded windows dispatched paint work')
win.faded,heal.faded=nil,nil
local reports={}
local function Isolate(callback,...)
    local co=coroutine.create(callback)
    local ok,value=coroutine.resume(co,...)
    if not ok then reports[#reports+1]=value;return nil end
    return value
end
-- Platform caches the native securecallfunction at load. Replace that owner
-- seam with the client's report-and-return semantics for fault injection.
S.Dispatch=function(callback,...) return Isolate(callback,...) end
local savedPaint,healthy=D.Paint,0
local poison={poisoned=true}
heal.meterType,heal.sessionType,heal.sessionID=win.meterType,win.sessionType,win.sessionID
D.Paint=function(window,...)
    if window.index==1 then window.session=poison;error('injected window reader failure') end
    healthy=healthy+1
    return savedPaint(window,...)
end
local reads=api.fetch
D.MarkAll();Isolate(D.PaintDirty)
assert(#reports==1 and healthy==1,'one failing window prevented a healthy window from painting')
assert(heal.session~=poison and api.fetch==reads+1,'a failed window lent an incomplete snapshot')
print('one error report, one healthy paint, no incomplete snapshot reuse PASS')

]=])
elseif selected == "profile_catalog" then
local originalLoad,Suite=loadfile,nil
loadfile=function(path)
    local chunk=assert(originalLoad(path))
    return function(addon,ns)
        if path:find('Core/Profiles.lua',1,true) then Suite=ns end
        return chunk(addon,ns)
    end
end
assert(originalLoad(root..'/tools/tests/suite_profiles_contract.lua'))()
loadfile=originalLoad
assert(Suite)
local beforeName,afterName='Catalogue source','Catalogue renamed'
local profile=Suite.CopyValue(Suite.DB)
Suite.RootDB.profiles[beforeName]=profile
MSUF_GlobalDB.profiles[beforeName]={}
local rows={{key='b555',name='Saved foreign-spec spell',texture=1,family=1,slot='ess'}}
local catalog={[63]=rows}
Suite.RootDB.cdmEditorCatalog={[beforeName]=catalog}
assert(Suite.OnMSUFProfileLifecycle('rename',beforeName,afterName))
assert(Suite.RootDB.profiles[afterName]==profile and Suite.RootDB.profiles[beforeName]==nil,
 'real profile rename did not run')
local saved=Suite.RootDB.cdmEditorCatalog
print('profile renamed',Suite.RootDB.profiles[afterName]~=nil,
 'catalog under new name',saved[afterName]~=nil,'stale old metadata',saved[beforeName]~=nil)
assert(saved[afterName]==catalog and saved[beforeName]==nil,
 'profile rename lost its observed foreign-specialization catalog')
assert(Suite.Database.Delete(afterName))
assert(saved[afterName]==nil,'deleted profile retained observed catalog metadata')

local copyName='Catalogue copy'
Suite.RootDB.profiles[beforeName]=Suite.CopyValue(profile)
Suite.RootDB.cdmEditorCatalog[beforeName]=catalog
MSUF_GlobalDB.profiles[beforeName]={}
assert(Suite.OnMSUFProfileLifecycle('copy',beforeName,copyName))
assert(Suite.RootDB.profiles[copyName] and not Suite.RootDB.cdmEditorCatalog[copyName],
    'observed catalog metadata traveled with a profile copy')

elseif selected == "timer_pool" then
    PrefixFixture("suite_cooldown_manager_auras_contract.lua", "------------------------------------------------------------------ compact aura icon bar", [=[
function Methods:Clear() R[self].duration=nil end
function Methods:SetTimerDuration(duration) R[self].duration=duration end
function Methods:SetCooldownFromDurationObject(duration) R[self].duration=duration end
C_DurationUtil.CreateDuration=function()
    return {SetTimeFromStart=function(self,start,length) self.start,self.length=start,length end}
end
local createBinding=C_DurationUtil.CreateDurationTextBinding
C_DurationUtil.CreateDurationTextBinding=function()
    local binding=createBinding()
    function binding:Assign(template) self.template=template end
    function binding:SetFontString(fs) self.font=fs end
    function binding:SetDuration(duration) self.duration=duration end
    return binding
end
C.views.bar=View("bar",3)
local view=C.views.bar
view.pandemic=false
local before=#containers
local spells={2484,5394,8143,16191,51485,98008,108270,108280,157153,192058,
    192077,192222,198838,204331,204336,207399,355580,383013,383017,383019}
for _,id in ipairs(spells) do
    local entry=Aura("bar","a"..id,"a","player",Set(id),
        {base=id,spell=id,ov={timerSpell=id,timerDuration=30}})
    Plan("bar",3,{entry})
    A.Sync("bar")
end
print("one fixed external-timer slot; twenty identity replacements; containers added",#containers-before)
local oneSlotCount=#containers-before
local function Manual(id,seconds)
    return Aura("bar","a"..id,"a","player",Set(id),
        {base=id,spell=id,ov={timerSpell=id,timerDuration=seconds}})
end
local function TimerRow(i)
    local cell=L.Cell("bar",i)
    for object in pairs(R) do
        local row=object.timerRow
        if row and row.cell==cell then return row end
    end
    error("timer row absent at cell "..i)
end
local first,second=Manual(5394,12),Manual(8143,17)
Plan("bar",3,{first,second});A.Sync("bar")
local current=Live("bar","player")
local secondFormCount=#containers
local function Check(entries)
    local state=R[current]
    for i,entry in ipairs(entries) do
        local slot=state.slots["s"..i]
        assert(slot and slot.cand.includeSpellIDs[entry.spell] and Count(slot.cand.includeSpellIDs)==1,
            "native aura candidate filter is stale at cell "..i)
        local button=Acquired(current,"s"..i)
        assert(R[button].bind.bar==nil and R[button].bind.text==nil,
            "external native duration regions were rebound")
        local row=TimerRow(i)
        assert(row.key==entry.key and row.cast==entry.base and row.seconds==entry.ov.timerDuration,
            "manual row routing identity stale at cell "..i)
        C.AuraTimers.Cast(nil,nil,"player",nil,entry.base)
        assert(row.active and row.duration==row.manual and row.manual.length==entry.ov.timerDuration,
            "new spell cast reached stale duration at cell "..i)
        assert(row.binding.duration==row.manual and R[row.frame.part.bar].duration==row.manual
            and R[row.gate].duration==row.manual,"native timer sinks did not receive new duration")
    end
end
Check({first,second})
Plan("bar",3,{second,first});A.Sync("bar")
local afterSwap=Live("bar","player")
-- Original signature builds a new container here; the control must reuse it.
local reusedOnSwap=afterSwap==current
current=afterSwap
Check({second,first})
local newerFirst,newerSecond=Manual(98008,23),Manual(108280,29)
Plan("bar",3,{newerFirst,newerSecond});A.Sync("bar")
local afterNewIDs=Live("bar","player")
local reusedNewIDs=afterNewIDs==current
current=afterNewIDs
Check({newerFirst,newerSecond})
for i=1,2 do
    local row=TimerRow(i)
    R[row.gate].scripts.OnCooldownDone(row.gate)
    assert(not row.active,"manual completion did not retire timer")
end
for _,id in ipairs({5394,8143}) do C.AuraTimers.Cast(nil,nil,"player",nil,id) end
assert(not TimerRow(1).active and not TimerRow(2).active,"stale prior spell routes retained")
print("two timer slots: swapped and replaced filters; routing and all native duration sinks PASS",
    "reused on swap",reusedOnSwap,"reused new IDs",reusedNewIDs)
assert(oneSlotCount==1 and reusedOnSwap and reusedNewIDs and #containers==secondFormCount,
    "identity-only timer replacements grow permanent native container pool")

]=])
elseif selected == "datatext_style" then
local H=dofile(root..'/tools/tests/suite_minimap_harness.lua')
local W=H.New(root,arg[3] or 'Mainline',{beforeModules=function(world)
    world.G.GetFramerate=function() return 80 end
    world.G.GetNetStats=function() return 0,0,30,50 end
    world.G.UpdateAddOnMemoryUsage=function() end
    world.G.GetAddOnMemoryUsage=function() return 14940 end
    world.G.C_AddOns.GetNumAddOns=function() return 1 end
end})
W.LoadAddon('MSUF_Suite_DataTexts')
local S,NS=W.S,W.Suite
S.Config('dataTexts').enabled=false
S.Start()
assert(S.SetMany('dataTexts',{enabled=true,bar1Enabled=true,bar1Slot1=NS.DataTextSourceIndex.fpsLatency,
    bar1Slot2=NS.DataTextSourceIndex.memory,bar1Slot3=1,bar1Slot4=1,bar1Slot5=1,bar1Slot6=1,
    bar2Enabled=false,bar3Enabled=false,performanceLabels=true,colorMemoryUnit=true,memoryUnitColor='123456'}))
local M=S.instances.dataTexts
M:UpdateSource('fpsLatency',true)
M:UpdateSource('memory',true)
local bar=M.bars[1]
print('style flags',bar.style.performanceLabels,bar.style.colorMemoryUnit,bar.style.memoryUnitColor)
print('runtime FPS',bar.slots[1].text)
print('runtime Memory',bar.slots[2].text)
assert(bar.style.performanceLabels==true and bar.style.colorMemoryUnit==true and bar.style.memoryUnitColor=='123456',
    'DataText effective style discarded explicit display settings')
assert(bar.slots[1].text=='FPS: 80 MS: 50','runtime separate performance labels were ignored')
assert(bar.slots[2].text:find('|cff123456MB|r',1,true),'runtime memory unit color was ignored')
local P={Suite=NS,Tr=function(value) return value end}
assert(loadfile(root..'/MSUF_Suite_Options/Pages/DataTextsPreviewData.lua'))('MSUF_Suite_Options',P)
local preview=P.DataTextsPreviewData
assert(preview.Text('fpsLatency',bar.style,M.config,'bar1Slot1'):find('MS: ',1,true),
    'preview separate performance labels were ignored')
assert(preview.Text('memory',bar.style,M.config,'bar1Slot2'):find('|cff123456MB|r',1,true),
    'preview memory unit color was ignored')
assert(S.SetMany('dataTexts',{bar1StyleOverride=true,bar1PerformanceLabels=false,
    bar1ColorMemoryUnit=false,bar1MemoryUnitColor='654321'}))
M:UpdateSource('fpsLatency',true);M:UpdateSource('memory',true)
assert(not bar.style.performanceLabels and not bar.style.colorMemoryUnit,
    'per-bar false did not override shared true')
assert(not bar.slots[1].text:find('MS:',1,true) and not bar.slots[2].text:find('|cff654321MB|r',1,true),
    'disabled per-bar formatting stayed active')
assert(S.SetMany('dataTexts',{bar1PerformanceLabels=true,bar1ColorMemoryUnit=true}))
M:UpdateSource('fpsLatency',true);M:UpdateSource('memory',true)
assert(bar.slots[1].text=='FPS: 80 MS: 50' and bar.slots[2].text:find('|cff654321MB|r',1,true),
    'enabled per-bar formatting did not reach the runtime')
print('DataText shared/per-bar runtime and preview formatting PASS')

elseif selected == "preview_font" then
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local native, inherited = STANDARD_TEXT_FONT, "Interface\\AddOns\\MSUF\\Expressway.ttf"
GameFontHighlightSmall = { GetFont = function() return native, 12, "" end }
local S = {}
MSUFSuite = {
    Suite = S, HostBridge = { Menu2 = function() return {} end }, Database = {},
    Registry = { AddListener = function() end }, -- profile dialog behavior is outside this font probe
    FontRendering = { SLUG = 3, SHARP = 2 },
    GlobalFontPath = function() return inherited end,
    FontFileApplied = function(label, path) return label.path == path end,
}
MSUF2 = { Widgets = {}, Theme = {} }
local P = {}
assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))("MSUF_Suite", MSUFSuite)
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Bridge.lua"))("MSUF_Suite_Options", P)
local nativeCalls = 0
local function Label(rejected)
    return {
        SetFont = function(self, path, size, flags)
            nativeCalls = nativeCalls + 1
            if rejected and path == rejected then return false end
            self.path, self.size, self.flags = path, size, flags
            return true
        end,
        SetShadowColor = function() nativeCalls = nativeCalls + 1 end,
        SetShadowOffset = function() nativeCalls = nativeCalls + 1 end,
    }
end
local coldInherited, coldRejected = Label(), Label("missing.ttf")
P.StylePreviewFont(coldInherited, nil, 14, "OUTLINE", 2, true, 70, 1)
P.StylePreviewFont(coldRejected, "missing.ttf", 14, "OUTLINE", 2, true, 70, 1)
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
local warmInherited, warmRejected = Label(), Label("missing.ttf")
P.StylePreviewFont(warmInherited, nil, 14, "OUTLINE", 2, true, 70, 1)
P.StylePreviewFont(warmRejected, "missing.ttf", 14, "OUTLINE", 2, true, 70, 1)
print("nil path cold=" .. coldInherited.path .. " / warm=" .. warmInherited.path)
print("refused path coldflags=" .. coldRejected.flags .. " / warmflags=" .. warmRejected.flags)
local direct = Label()
S.SetStyledFont(direct, nil, 14, "OUTLINE", 2, true, 70, 1)
nativeCalls = 0
local vm = 0
debug.sethook(function() vm = vm + 1 end, "", 1)
S.SetStyledFont(direct, nil, 14, "OUTLINE", 2, true, 70, 1)
debug.sethook()
print("warm direct runtime styling VM=" .. vm .. " native sink calls=" .. nativeCalls)
assert(vm <= 114, "runtime font painter exceeded original 114 VM budget")
assert(nativeCalls == 3, "runtime font painter added native work")
local override = Label()
P.StylePreviewFont(override, "explicit.ttf", 14, "OUTLINE", 2, false)
assert(override.path == "explicit.ttf" and override.flags == "OUTLINE,MONOCHROME", "explicit font override lost")
assert(coldInherited.path == warmInherited.path, "inherited font changes when optional runtime loads")
assert(coldRejected.flags == warmRejected.flags, "fallback rendering flags change when optional runtime loads")
print("PASS cold/warm actual exported preview/runtime font parity")

do
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GameFontHighlightSmall = { GetFont = function() return STANDARD_TEXT_FONT, 12, "" end }
local config = { font="FancyFont", itemCountSize=12, fontRendering=2, qualityColor=false,
    inventoryView=1, bankView=1, showItemLevel=true, showBankItemLevel=true }
local inherited, fancy = "Interface\\Fonts\\Global.ttf", "Interface\\Fonts\\Fancy.ttf"
local S = { Config=function() return config end, BagsPaintPreviewWindow=function() end,
    BagsStylePreviewLabel=function() end }
MSUFSuite = { Suite=S, Database={}, SuiteCatalog={bags={rules={}}},
    Registry={AddListener=function() end}, -- profile dialog behavior is outside this font probe
    FontRendering={SLUG=3,SHARP=2}, HostBridge={Menu2=function() return {} end},
    GlobalFontPath=function() return inherited end,
    ResolveFont=function(key) if key == "FancyFont" then return fancy end end,
    FontFileApplied=function(label,path) return label.path == path end,
}
MSUF2 = { Widgets={}, Theme={} }
local P = {}
assert(loadfile(root.."/MSUF_Suite/Core/FontBridge.lua"))("MSUF_Suite",MSUFSuite)
assert(loadfile(root.."/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules",{})
assert(loadfile(root.."/MSUF_Suite_Options/Menu/Bridge.lua"))("MSUF_Suite_Options",P)
local methods = {}
local function Noop() end
local function Region()
    return setmetatable({}, {__index=function(_,key) return methods[key] or Noop end})
end
function methods:CreateTexture() return Region() end
function methods:GetStringHeight() return 14 end
function methods:SetFont(path,size,flags)
    if type(path) ~= "string" or not path:match("%.TTF$") and not path:match("%.ttf$") then return false end
    self.path,self.size,self.flags=path,size,flags;return true
end
local paint
P.PreviewCanvas = { Button=function() return Region() end, Text=function() return Region() end,
    Jump=Noop, Runtime=function() return true end, Changed=function() return true end,
    Watch=function(_,fn) paint=fn end }
P.SetTranslatedText=Noop
P.MenuWorkspace={FitHeader=Noop}
C_Item={GetItemQualityColor=function() return 1,1,1 end}
assert(loadfile(root.."/MSUF_Suite_Options/Pages/BagsPreview.lua"))("MSUF_Suite_Options",P)
local ui={header=Region(),width=600,selected="inventory",Focus=Noop}
P.BuildBagsMenuPreview(ui)
paint()
local custom=ui.bagsPreview.slots[1].count.path
config.font=""
paint()
local default=ui.bagsPreview.slots[1].count.path
print("bag count preview custom="..custom.." / inherited="..default)
assert(custom==fancy,"bag count preview did not resolve selected media key")
assert(default==inherited,"bag count preview did not inherit global font for empty key")
print("PASS actual Bags preview selected/inherited font")

end

elseif selected == "feedback_dump" then
local destination=assert(arg[3],"bytecode destination required")
local S = {
    USABLE = {USABLE=1, NO_POWER=2, UNUSABLE=3, OUT_OF_RANGE=4},
    USABLE_TINT = {},
    Public = function() return true end,
}
local NS = {IsSecret=function() return false end}
local AB = {
    M = {}, Diagnostics = {},
    ENUM = { PROC_GLOW={BLIZZARD=1, PIXEL=2, NONE=3},
        BUTTON_SHAPE={CIRCLE=2}, BAR={MAIN=1} },
}
assert(loadfile(root..'/MSUF_Suite_ActionBars/Paint.lua'))('MSUF_Suite_ActionBars',
    {NS=NS, Suite=S, ActionBars=AB})
local fn = assert(AB.Painter.CooldownFeedback)
local out=assert(io.open(destination, 'wb'))
out:write(string.dump(fn));out:close()
for i=1,10 do
    local name=debug.getupvalue(fn,i)
    if not name then break end
    print('upvalue '..i..' '..name)
end

else
    error("unknown engine case "..selected)
end
