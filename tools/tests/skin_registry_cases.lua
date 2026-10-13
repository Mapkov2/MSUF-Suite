return function(root,mode,faultIndex)

local combat=false
local scheduled,reported,deferred={}, {},{}
local nativeCalls=0
C_Timer={After=function(_,callback) scheduled[#scheduled+1]=callback end}
local NS={Safety={},IsCombatLocked=function() return combat end,
    CombatGate={RunOrDefer=function(key,callback) deferred[key]=callback end}}
NS.Safety.Dispatch=function(fn,...)
    nativeCalls=nativeCalls+1
    local result={coroutine.resume(coroutine.create(fn),...)}
    if not result[1] then reported[#reported+1]=result[2];return end
    return unpack(result,2,table.maxn(result))
end
assert(loadfile(root.."/MSUF_Suite_Skin/Core/Registry.lua"))("MSUF_Suite_Skin",NS)
local R=NS.Registry
local keep,painted,attempts={},0,0
local function Paint() painted=painted+1 end
for i=1,3 do
    local target={}
    keep[i]=target
    R.RegisterSurface(target,{refresh=Paint},{"palette"})
end
local selected,order=nil,0
local set=mode=="token" and R.tokenConsumers.palette or R.surfaces
for target in pairs(set) do
    order=order+1
    if order==faultIndex then selected=target end
end
if selected then
    R.surfaces[selected].refresh=function() attempts=attempts+1;error("independent surface failure") end
end
local jobs=0
local function Job() jobs=jobs+1 end
local function Queue()
    R.QueueRefresh(mode=="token" and "palette" or nil)
    R.QueueJob(Job);R.QueueJob(Job)
end
local function Flush()
    local count=#scheduled
    for i=1,count do local callback=scheduled[i];scheduled[i]=nil;callback() end
    assert(#scheduled==0,"surface failure rearmed unbounded retry")
end
Queue()
if mode=="combat" then
    combat=true;Flush()
    assert(painted==0 and jobs==0 and #reported==0,"combat pass refreshed surfaces")
    local callback=assert(deferred["registry:queued"],"combat queue not deferred")
    deferred["registry:queued"]=nil
    combat=false;callback()
else Flush() end
local expected=selected and 2 or 3
assert(painted==expected,"one faulty surface skipped healthy targets: "..painted.."/"..expected)
assert(jobs==1,"surface failure skipped/doubled queued job")
assert(#reported==(selected and 1 or 0) and attempts==(selected and 1 or 0),"surface error retry/report contract changed")
if selected then
    R.surfaces[selected].refresh=Paint
    Queue();Flush()
    assert(painted==5 and jobs==2 and #reported==1,"later explicit refresh did not recover failed target")
end
-- One outer pass, one isolated boundary per surface and one queued job.
assert(nativeCalls == (selected and 10 or 5), "registry native Dispatch budget regressed")
print(("independent registry %s fault=%d paints=%d native_dispatches=%d passed"):
    format(mode,faultIndex,painted,nativeCalls))

end
