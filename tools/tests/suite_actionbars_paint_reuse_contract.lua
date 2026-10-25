-- Actual flush and isolated unit runner, with deterministic paint/native sinks.
-- A record version stands for opaque action state; the dispatcher never reads it.
local root = assert(arg[1])
local source, mode = arg[2] or root .. "/MSUF_Suite_ActionBars/Flush.lua", arg[3] or "strict"
local function Read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local runtime = Read(root .. "/MSUF_Suite_Modules/Runtime.lua")
local first = assert(runtime:find("function S.NewUnitRunner()", 1, true))
local last = assert(runtime:find("------------------------------------------------------------------ CVar ownership", first, true))
local runner = "local S, NS = ...\nlocal Dispatch = S.Dispatch\n" .. runtime:sub(first, last - 1)
local function New()
    local w = { now=10, timers={}, paints=0, refills=0, reads=0, errors=0, native=0, depth=0 }
    local S = { Dispatch=function(fn, ...) local ok, result=pcall(fn, ...); if ok then return result end w.errors=w.errors+1 end }
    local NS = { Finish=function(fn, ...) fn(...); return true end, IsCombatLocked=function() return w.combat end }
    assert(loadstring(runner, "@" .. root .. "/MSUF_Suite_Modules/Runtime.lua"))(S, NS)
    local ab = { bars={}, BAR_COUNT=2, M={active=true,config={}}, ENUM={PROC_GLOW={PIXEL=2}} }
    local map = {}
    for bi=1,2 do
        local bar={owned=true,buttons={},filled={},visible=true,index=bi}
        ab.bars[bi]=bar
        for i=1,3 do
            local rec={bar=bar,slot=(bi-1)*3+i,filled=true,wanted=1,value=0}
            bar.buttons[i],bar.filled[i]=rec,rec
            map[rec.slot]={rec}
        end
    end
    local function Paint(rec)
        w.paints=w.paints+1
        if w.paintHook then w.paintHook(rec) end
        if rec.fail and rec.fail>0 then rec.fail=rec.fail-1;error("paint sink failure") end
        w.reads=w.reads+1;rec.value=rec.wanted
    end
    local function Refill(bar)
        w.refills=w.refills+1
        if w.refillHook then w.refillHook(bar) end
        if bar.fail and bar.fail>0 then bar.fail=bar.fail-1;error("refill sink failure") end
    end
    local function PaintBar(bar)
        if not bar.owned or bar.native then return end
        for i=1,#bar.buttons do Paint(bar.buttons[i]) end
        Refill(bar)
    end
    local function Walk(fn)
        for bi=1,2 do
            local bar=ab.bars[bi]
            if not bar.native and bar.visible then for i=1,#bar.filled do fn(bar.filled[i]) end end
        end
    end
    local function Native() w.native=w.native+1 end
    local function Other() end
    ab.Painter={slotMap=map,Visible=function(b) return b.visible end,Paint=Paint,PaintBar=PaintBar,Refill=Refill,
        Walk=Walk,WalkNative=function(fn) fn() end,Cooldown=Other,Usable=Other,State=Other,Count=Other,
        GlowCheck=Other,AllKeyTexts=Other,Icon=Other,SpellRouted=function() return false end}
    ab.NativeButtons={Feedback=Native,State=Native,Count=Native,Color=Native,Retint=Other}
    ab.Execute=Other;ab.SNIPPET={GRID="grid"};ab.UpdateRouting=Other
    local env=setmetatable({GetTime=function() return w.now end,
        C_Timer={After=function(delay,fn) w.timers[#w.timers+1]={fn=fn,at=w.now+delay} end}}, {__index=_G})
    local chunk=assert(loadfile(source));setfenv(chunk,env);chunk("MSUF_Suite_ActionBars",{NS=NS,Suite=S,ActionBars=ab})
    w.ab,w.map=ab,map
    function w:Slot(slot) ab.Dirty.slots[slot]=true;ab.Dirty.Schedule() end
    function w:Fire()
        local timer=table.remove(self.timers,1);assert(timer,"missing scheduled flush")
        self.now=math.max(self.now,timer.at);timer.fn()
    end
    function w:Counts() self.paints,self.refills,self.reads,self.native=0,0,0,0 end
    return w
end
local function Bar(w,i) return w.ab.bars[i or 1] end
local function Ready(w)
    for _,bar in pairs(w.ab.bars) do for _,rec in ipairs(bar.buttons) do
        if rec.value~=0 then assert(rec.value==rec.wanted,"stale painted value") end
    end end
end
local cases={}
cases.slot=function(w) w:Slot(1) end
cases.bar=function(w) w.ab.MarkBar(Bar(w)) end
cases.overlap=function(w) w.ab.MarkBar(Bar(w));w:Slot(1) end
cases.shared=function(w)
    w.map[1][2]=Bar(w,2).buttons[1];w.ab.MarkBar(Bar(w));w:Slot(1)
end
cases.both_bars=function(w)
    w.map[1][2]=Bar(w,2).buttons[1];w.ab.MarkBar(Bar(w));w.ab.MarkBar(Bar(w,2));w:Slot(1)
end
cases.cooldown=function(w) w.ab.Mark("cooldown") end
cases.hidden=function(w) Bar(w).visible=false;cases.overlap(w) end
cases.native=function(w)
    local b=Bar(w);b.native=true;for _,r in ipairs(b.buttons) do r.native=true end
    cases.overlap(w)
end
cases.unowned=function(w) Bar(w).owned=false;cases.overlap(w) end
local expected={slot={1,1},bar={3,1},overlap={4,2},shared={5,3},both_bars={8,4},cooldown={0,0},hidden={0,0},native={0,0},unowned={1,1}}
local saved={overlap={3,1},shared={4,2},both_bars={6,2}}
-- Accepted dispatcher trade versus the original: standalone bar +10 VM,
-- slot +5, hidden/native +4, unowned +7; cooldown unchanged. Full real
-- Paint+Flush overlap saves 695/1250 VM for one/two duplicate slots.
-- These limits count only real Flush/runner; paint/native costs stay separate.
local vmLimits={slot=270,bar=240,overlap=288,shared=327,both_bars=345,
    cooldown=237,hidden=268,native=267,unowned=300}
local candidate=mode=="strict"
local summaries={}
local function Instructions(fn)
    local count=0
    debug.sethook(function()
        local info=debug.getinfo(2,"S")
        if info and (info.source=="@"..source or info.source=="@"..root.."/MSUF_Suite_Modules/Runtime.lua") then count=count+1 end
    end,"",1)
    fn();debug.sethook();return count
end
for name,setup in pairs(cases) do
    local w=New();setup(w);local vm=Instructions(function() w:Fire() end);Ready(w)
    local e=(candidate and saved[name]) or expected[name]
    assert(w.paints==e[1] and w.refills==e[2],name..": wrong paint/refill count "..w.paints.."/"..w.refills)
    summaries[name]={vm,w.paints,w.refills,w.reads}
    if candidate then assert(vm<=vmLimits[name],name..": dispatcher VM budget exceeded "..vm) end
    if name=="overlap" then
        Bar(w).buttons[1].wanted=2;w:Counts();w:Slot(1);w:Fire()
        assert(w.paints==1 and Bar(w).buttons[1].value==2,"reuse escaped its flush")
    end
end
-- Any fresh public mark must invalidate reuse, even an already-pending slot.
for _,kind in ipairs({"slot","bar","full","state"}) do
    local w=New();local b=Bar(w);local once=false
    w.paintHook=function(rec)
        if once or rec~=b.buttons[2] then return end;once=true;b.buttons[1].wanted=2
        if kind=="slot" then w:Slot(1)
        elseif kind=="bar" then w.ab.MarkBar(b)
        elseif kind=="full" then w.ab.MarkAll()
        else w.ab.Mark("state") end
    end
    cases.overlap(w);w:Fire()
    assert(w.paints>=4 and b.buttons[1].value==2,"new "..kind.." mark was absorbed")
end
-- The first bar's marker already exists when the second bar emits a fresh slot mark.
do
    local w=New();local painted,changed
    w.paintHook=function(rec)
        if not painted then painted=rec.bar
        elseif rec.bar~=painted and not changed then
            changed=true;painted.buttons[1].wanted=4;w:Slot(painted.buttons[1].slot)
        end
    end
    w.ab.MarkBar(Bar(w));w.ab.MarkBar(Bar(w,2));w:Slot(1);w:Slot(4);w:Fire()
    assert(changed and painted.buttons[1].value==4,"post-marker slot mark was absorbed")
end
-- A partial bar paint or final refill failure never establishes reuse.
for _,where in ipairs({"paint","refill"}) do
    local w=New();local b=Bar(w)
    if where=="paint" then
        b.buttons[2].fail=1
        w.paintHook=function(rec) if rec.fail and rec.fail>0 then b.buttons[1].wanted=2 end end
    else
        b.fail=1
        w.refillHook=function(bar) if bar.fail and bar.fail>0 then bar.buttons[1].wanted=2 end end
    end
    cases.overlap(w);w:Fire()
    assert(w.errors==1 and b.buttons[1].value==2,"failed bar did not preserve independent slot work")
    w.paintHook=function(rec) rec.wanted=3 end
    w.ab.Mark("state");w:Fire()
    for _,rec in ipairs(b.buttons) do assert(rec.value==3,"bar retry was lost") end
end
-- A pending refill retry must retain its unit-runner identity across a full paint.
do
    local w=New();local b=Bar(w);b.fail=1
    w:Slot(1);w:Fire();assert(w.errors==1)
    cases.overlap(w);w:Fire()
    b.fail=1;w:Slot(1);w:Fire();assert(w.errors==2)
    w:Counts();w.ab.Mark("state");w:Fire()
    assert(w.refills==1,"fresh refill failure lost its retry after full-bar reuse")
end
-- Re-mark from the final refill prevents reuse, even after every button was painted.
do
    local w=New();local once=false
    w.refillHook=function(bar)
        if once then return end;once=true;bar.buttons[1].wanted=3;w:Slot(1)
    end
    cases.overlap(w);w:Fire()
    assert(w.paints==4 and Bar(w).buttons[1].value==3,"late mark was discarded")
end
-- Clear pending work/disable, then re-enable: no reuse or record may leak.
do
    local w=New();cases.overlap(w);w.ab.Dirty.Reset();w:Fire();assert(w.paints==0)
    w.ab.M.active=false;cases.overlap(w);w:Fire();assert(w.paints==0)
    w.ab.Dirty.Reset();w.ab.M.active=true;w:Slot(1);w:Fire();assert(w.paints==1)
end
-- Allocation excludes setup and the modeled table-allocating timer, measures the real Flush.
do
    local minimum=math.huge
    for attempt=1,2 do
        local w=New();cases.overlap(w);w:Fire();w:Counts()
        cases.overlap(w);local callback=w.timers[1].fn;w.timers={}
        collectgarbage("collect");collectgarbage("stop")
        local before=collectgarbage("count");callback();local delta=collectgarbage("count")-before
        collectgarbage("restart");minimum=math.min(minimum,delta)
    end
    assert(minimum<=0.001,"warm flush allocated "..minimum.." KiB")
    print("ALLOCATION_KIB\t"..minimum)
end
for name,r in pairs(summaries) do print(string.format("CASE\t%s\t%d\t%d\t%d\t%d",name,unpack(r))) end
print("PASS: real Flush/runner; reuse, native/hidden, reentry, failures, retry identity, lifecycle; "..mode)
