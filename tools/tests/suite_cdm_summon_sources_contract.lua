-- Native summon source lifecycle: CDM may be disabled in the saved CVar,
-- already invisible, acquired late, pooled, or rebuilt during combat.
local root=assert(arg[1])
local wanted,locked,queued,sourceCalls,childReads=false,false,0,0,0
local cvar,saved,writes="0",nil,0
local M={active=true,config={blizzard=1}}
local S={Public=function(v) return type(v)~="table" or not v.secret end,
    Text=function(v) return v end,Number=function(v) return type(v)=="number" end}
function S.Queue() queued=queued+1 end
function S.RestoreCVar()
    if saved~=nil then cvar,saved=saved,nil;writes=writes+1 end
end
local ctx={}
M.context=ctx
function ctx:CVar(_,v)
    if saved==nil then saved=cvar end
    cvar=v;writes=writes+1
end
local state,callbacks={},{}
local methods={}
local function Frame(fields)
    local f=setmetatable({}, {__index=function(self,k) return methods[k] or state[self][k] end,
        __newindex=function() error("native frame field write") end})
    state[f]=fields or {}
    return f
end
function methods:SetAlpha(v) state[self].alpha=v;writes=writes+1 end
function methods:EnableMouse(v) state[self].mouse=v end
function methods:SetMouseClickEnabled(v) state[self].click=v end
function methods:SetMouseMotionEnabled(v) state[self].motion=v end
function methods:GetChildren() childReads=childReads+1;return unpack(state[self].children or {}) end
function ctx:Alpha(f,v) f:SetAlpha(v) end
function ctx:RestoreProperty(f) f:SetAlpha(1) end
function ctx:RemoveEvent() end
local hookCount=0
function hooksecurefunc(f,method,callback)
    assert(type(f[method])=="function", "hook must target a native method")
    hookCount=hookCount+1
    callbacks[f]=callbacks[f] or {}
    assert(not callbacks[f][method],"duplicate native hook")
    callbacks[f][method]=callback
end
local function Call(f,method,...)
    f[method](f,...)
    local callback=callbacks[f] and callbacks[f][method]
    if callback then callback(f,...) end
end
local viewers={}
for _,name in ipairs({"EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer","BuffBarCooldownViewer"}) do
    local f=Frame({alpha=1,children={},OnAcquireItemFrame=function() end})
    _G[name]=f;viewers[#viewers+1]=f
end
local existing=Frame({layoutIndex=1,cooldownID=701,totemData={slot=1,spellID={secret=true}},
    RefreshTotemData=function() end})
state[viewers[1]].children[1]=existing
local T={generation=0,NeedsSources=function() return wanted end}
function T.Source(f)
    if f.cooldownID==701 then sourceCalls=sourceCalls+1 end
end
local C={M=M,AuraTimers=T,Const={BLIZZARD={OFF=1,INVISIBLE=2}},Layout={MSUFAnchor=function() return false,false end}}
local P={CDM=C,Suite=S,NS={CDM={KEYS={}},Safety={IsForbidden=function() return false end},
    IsCombatLocked=function() return locked end}}
assert(loadfile(arg[2] or root.."/MSUF_Suite_CooldownManager/Native.lua"))("MSUF_Suite_CooldownManager",P)
local N=C.Native
N.Apply()
assert(cvar=="0" and hookCount==0,"ordinary bars leave native viewers off")
wanted,T.generation=true,1
N.Apply()
assert(N.Mode()==2 and cvar=="1" and sourceCalls==1,"summon sources must be enabled and seeded after route creation")
assert(M.config.blizzard==1,"native source requirement cannot mutate saved mode")
for _,f in ipairs(viewers) do assert(state[f].alpha==0,"native source viewers remain invisible") end
local hooks,reads,calls,changed=hookCount,childReads,sourceCalls,writes
for i=1,1000 do N.Apply() end
assert(hookCount==hooks and childReads==reads and sourceCalls==calls and writes==changed,
    "unchanged source requirement repeats no hook, child scan, seed or CVar write")
Call(existing,"RefreshTotemData")
assert(sourceCalls==calls+1,"native refresh forwards its already associated slot")
local later=Frame({layoutIndex=2,RefreshTotemData=function() end})
Call(viewers[1],"OnAcquireItemFrame",later)
assert(callbacks[later].RefreshTotemData,"acquire precedes cooldownID assignment, so source hook cannot depend on ID yet")
state[later].cooldownID=701
Call(later,"RefreshTotemData")
assert(sourceCalls==calls+2,"a late item works after native ID assignment")
hooks=hookCount
Call(viewers[1],"OnAcquireItemFrame",later)
assert(hookCount==hooks,"pooled items keep one observer")
locked=true;T.generation=2
calls,reads,changed=sourceCalls,childReads,writes
N.Apply()
assert(queued==1 and childReads==reads and sourceCalls==calls and writes==changed,"combat defers native mode/seed writes")
locked=false;N.Apply()
assert(sourceCalls==calls+1,"deferred generation is seeded after combat")
wanted=false;T.generation=3;N.Apply()
assert(cvar=="0" and N.Mode()==1,"removing the last summon releases the CVar")
calls=sourceCalls;Call(existing,"RefreshTotemData")
assert(sourceCalls==calls,"native source observers are inert without consumers")
M.config.blizzard=2;N.Apply()
assert(cvar=="0" and state[viewers[1]].alpha==0,"explicit invisible mode preserves originally-off CVar")
wanted=true;T.generation=4;N.Apply()
assert(cvar=="1","adding a timer to an already invisible viewer must enable its sources")
N.Release()
assert(cvar=="0" and saved==nil,"release restores originally-off CVar")
calls=sourceCalls;Call(existing,"RefreshTotemData")
assert(sourceCalls==calls,"release leaves source observers inert")
for _,f in ipairs(viewers) do assert(state[f].alpha==1,"release restores native viewer alpha") end
N.Apply()
assert(sourceCalls==calls+1,"re-enable seeds an existing mid-cast source")
N.Release()
print("suite_cdm_summon_sources_contract: OK")
