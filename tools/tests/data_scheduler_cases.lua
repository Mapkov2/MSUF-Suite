return function(root,scenario)

local now,timers,reported=0,{},{}
local calls,handles,first={}, {},nil
local S={Public=function() return true end,Finite=function(v) return type(v)=="number" end,
    PublicText=function(v) return v end}
S.Dispatch=function(fn,...)
    local result={coroutine.resume(coroutine.create(fn),...)}
    if not result[1] then reported[#reported+1]=result[2] end
end
if scenario=="warm_budget" then S.Dispatch=function(fn) fn() end end
GetTime=function() return now end
C_Timer={NewTimer=function(delay,fn)
    local handle={at=now+delay,fn=fn}
    function handle:Cancel() self.cancelled=true end
    timers[#timers+1]=handle
    return handle
end}
assert(loadfile(root.."/MSUF_Suite_Modules/DataSources.lua"))("MSUF_Suite_Modules",{Suite=S})
local function Pending()
    local count=0
    for _,timer in ipairs(timers) do if not timer.fired and not timer.cancelled then count=count+1 end end
    return count
end
local function Advance(untilTime)
    local guard=0
    while true do
        local due
        for _,timer in ipairs(timers) do
            if not timer.fired and not timer.cancelled and timer.at<=untilTime
                and (not due or timer.at<due.at) then due=timer end
        end
        if not due then now=untilTime;return end
        guard=guard+1;assert(guard<100,"infinite scheduler loop")
        now=due.at;due.fired=true;due.fn()
    end
end
if scenario=="self_reschedule" then
    local count=0
    local function Own()
        count=count+1
        if count==1 then
            assert(S.ScheduleDataTick("one",2,Own)==handles.one,"self schedule changed task handle")
        end
    end
    handles.one=S.ScheduleDataTick("one",1,Own)
    Advance(1);assert(count==1 and Pending()==1,"self reschedule lost next deadline")
    Advance(2.99);assert(count==1,"self reschedule ran before deadline")
    Advance(3);assert(count==2 and Pending()==0,"self reschedule did not complete")
elseif scenario=="error_isolation" then
    S.ScheduleDataTick("one",1,function() error("independent expected failure") end)
    S.ScheduleDataTick("two",1,function() calls.two=(calls.two or 0)+1 end)
    Advance(1)
    assert(#reported==1 and calls.two==1 and Pending()==0,"raising callback interrupted ready batch")
    S.ScheduleDataTick("two",1,function() calls.two=calls.two+1 end)
    Advance(2);assert(calls.two==2 and Pending()==0,"raise left scheduler disarmed")
elseif scenario=="idle_cancel" then
    handles.one=S.ScheduleDataTick("one",1,function() error("cancelled callback") end)
    handles.one:Cancel();Advance(2)
    assert(Pending()==0 and #reported==0,"cancelled idle task retained native timer or fired")
elseif scenario=="warm_budget" then
    -- Allocation-free stand-ins separate fixture allocations from product work.
    local native,newTimers,cancels,timeReads={},0,0,0
    function native:Cancel() cancels=cancels+1 end
    C_Timer.NewTimer=function(_,fn) newTimers=newTimers+1;native.fn=fn;return native end
    GetTime=function() timeReads=timeReads+1;return now end
    S.Dispatch=function(fn) fn() end
    local function Tick() end
    local function Cycle()
        local a=S.ScheduleDataTick("one",1,Tick)
        local b=S.ScheduleDataTick("two",1,Tick)
        now=now+1
        native.fn()
        assert(a==handles.one and b==handles.two,"warm cycle replaced owner handles")
    end
    handles.one=S.ScheduleDataTick("one",1,Tick)
    handles.two=S.ScheduleDataTick("two",1,Tick)
    now=1;native.fn()
    for i=1,20 do Cycle() end
    local minimum
    for pass=1,2 do
        collectgarbage("collect");collectgarbage("stop")
        local before=collectgarbage("count")
        for i=1,1000 do Cycle() end
        local delta=collectgarbage("count")-before
        collectgarbage("restart")
        minimum=minimum and math.min(minimum,delta) or delta
    end
    assert(minimum<1,"warm scheduler allocated "..minimum.." KB")
    newTimers,cancels,timeReads=0,0,0
    local instructions=0
    debug.sethook(function() instructions=instructions+1 end,"",1)
    for i=1,100 do Cycle() end
    debug.sethook()
    -- Original 25,108; generation identity adds exactly 2,400 VM
    -- instructions per 100 two-owner cycles, with no extra native calls.
    assert(instructions <= 27508, "shared scheduler VM budget regressed")
    assert(timeReads == 400, "shared scheduler time-read budget regressed")
    assert(newTimers==100 and cancels==0,"shared scheduler native timer budget regressed")
    print(("budget instructions=%d native_timers=%d native_cancels=%d time_reads=%d warm_kb=%.6f"):
        format(instructions,newTimers,cancels,timeReads,minimum))
else
    local callbacks={}
    local function Replacement() calls.replacement=(calls.replacement or 0)+1 end
    local function Make(owner)
        return function()
            calls[owner]=(calls[owner] or 0)+1
            if not first then
                first=owner
                local other=owner=="one" and "two" or "one"
                if scenario=="cancel" or scenario=="cancel_replace" then handles[other]:Cancel() end
                if scenario~="cancel" then
                    local fn=scenario=="same_callback" and callbacks[other] or Replacement
                    assert(S.ScheduleDataTick(other,10,fn)==handles[other],"replacement changed reusable handle")
                end
            end
        end
    end
    callbacks.one,callbacks.two=Make("one"),Make("two")
    handles.one=S.ScheduleDataTick("one",1,callbacks.one)
    handles.two=S.ScheduleDataTick("two",1,callbacks.two)
    Advance(1)
    assert(#reported==0,"unexpected callback failure")
    assert((calls.one or 0)+(calls.two or 0)==1,"stale collected callback ran after cancel/replace")
    if scenario=="cancel" then
        assert(Pending()==0,"cancel-only retained timer")
    else
        assert(Pending()==1,"replacement lost shared native timer")
        Advance(10.99)
        assert((calls.one or 0)+(calls.two or 0)==1 and not calls.replacement,"replacement ran early")
        Advance(11)
        local total=(calls.one or 0)+(calls.two or 0)+(calls.replacement or 0)
        assert(total==2 and Pending()==0,"replacement did not run exactly at new deadline")
    end
end
print("independent scheduler "..scenario.." passed")

end
