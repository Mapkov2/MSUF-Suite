local root=assert(arg[1])
local Support=dofile(root..'/tools/tests/suite_test_support.lua')
local Suite,combat,shift={},false,false
MSUFSuite=Suite
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",SupportsEvent=function() return true end}}
SlashCmdList={}
InCombatLockdown=function() return combat end
IsShiftKeyDown=function() return shift end
local secret={}
issecretvalue=function(value) return value==secret end
-- HookScript adds a separate post-call binding: SetScript replaces only the
-- frame's own handler, and hooks run after it.
local function Frame()
    local f={scripts={},hooks={OnShow={},OnHide={}},events={},shown=false}
    function f:GetScript(key) return self.scripts[key] end
    function f:SetScript(key,value) self.scripts[key]=value end
    function f:HookScript(key,value) table.insert(self.hooks[key],value) end
    function f:RegisterEvent(key) self.events[key]=true end
    function f:UnregisterEvent(key) self.events[key]=nil end
    function f:UnregisterAllEvents() self.events={} end
    function f:IsForbidden() return false end
    function f:IsShown() return self.shown end
    function f:Show()
        if self.shown then return end
        self.shown=true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
        for _,hook in ipairs(self.hooks.OnShow) do hook(self) end
    end
    function f:Hide()
        assert(not combat,'history hidden in combat')
        if not self.shown then return end
        self.shown=false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
        for _,hook in ipairs(self.hooks.OnHide) do hook(self) end
    end
    return f
end
CreateFrame=Frame
MSUF_PixelLayoutRegion=function(frame) return frame end
local timers={}
C_Timer={NewTimer=function(delay,callback)
    local timer={delay=delay,callback=callback}
    function timer:Cancel() self.cancelled=true end
    timers[#timers+1]=timer
    return timer
end}
Support.Load(root,'MSUF_Suite',Suite,'Core/Suite.lua')
assert(loadfile(root..'/MSUF_Suite/Integrations/MapkoSkin.lua'))('MSUF_Suite',Suite)
assert(Suite.Database.Initialize(nil))
local private={}
for _,file in ipairs({'Surfaces','Runtime'}) do
    assert(loadfile(root..'/MSUF_Suite_Modules/'..file..'.lua'))('MSUF_Suite_Modules',private)
end
local quality={}
for _,file in ipairs({'Bootstrap','Merchant','QuestHelpers','Loot'}) do
    assert(loadfile(root..'/MSUF_Suite_QualityOfLife/'..file..'.lua'))('MSUF_Suite_QualityOfLife',quality)
end
local S=Suite.Suite
local module=S.instances.loot
module.config=S.Config('loot')
module.context=S.NewContext('loot')
module.active=true
module:Enable()
assert(not module.context.frame and #timers==0,'default module created idle work')
local function Event(name,...)
    local callback=module.context.callbacks[name]
    if callback then callback(module,name,...) end
end
local calls,count,locked={},3,{}
GetNumLootItems=function() return count end
GetLootSlotInfo=function(slot) return nil,nil,nil,nil,nil,locked[slot] or false end
LootSlot=function(slot) calls[#calls+1]=slot end
module.config.quickLoot=true
module:Refresh()
assert(#calls==0,'configuration collected loot')
locked[2]=true
Event('LOOT_READY',false)
assert(#calls==2 and calls[1]==3 and calls[2]==1,'locked loot or order changed')
Event('LOOT_OPENED',false)
assert(#calls==2,'duplicate batch on opened')
Event('LOOT_CLOSED')
shift=true
Event('LOOT_READY',false)
assert(#calls==2,'Shift bypass ignored')
module.config.lootModifier=3
module:Refresh()
Event('LOOT_READY',false)
assert(#calls==4,'Shift-only collection missing')
Event('LOOT_CLOSED')
shift=false
Event('LOOT_READY',false)
assert(#calls==4)
module.config.lootModifier=1
Event('LOOT_READY',true)
assert(#calls==4,'duplicated native auto-loot')
Event('LOOT_READY',secret)
count=secret
Event('LOOT_READY',false)
count=math.huge
Event('LOOT_READY',false)
count=2.5
Event('LOOT_READY',false)
assert(#calls==4,'invalid or secret count accepted')
count=3;locked[2]=secret
LootSlot=function(slot) calls[#calls+1]=slot;Event('LOOT_CLOSED') end
Event('LOOT_READY',false)
assert(#calls==5,'collection continued after synchronous close')
LootSlot=function(slot) calls[#calls+1]=slot;Event('LOOT_READY',false) end
Event('LOOT_READY',false)
assert(#calls==7,'reentrant collection duplicated slots')
module.config.quickLoot=false
module:Refresh()
assert(not module.context.callbacks.LOOT_READY and not module.context.callbacks.LOOT_OPENED and not module.context.callbacks.LOOT_CLOSED)
local imported={suite={modules={loot={enabled=true,quickLoot=true,manageHistory=true}}}}
S.SanitizeImport(imported)
assert(not imported.suite.modules.loot.quickLoot and imported.suite.modules.loot.manageHistory)
assert(S.catalog.loot.optIn,'setup preset must not enable loot automation')

local frame=Frame()
local shows,hides=0,0
local originalShow=function() shows=shows+1 end
local originalHide=function() hides=hides+1 end
frame:SetScript('OnShow',originalShow)
frame:SetScript('OnHide',originalHide)
module.config.manageHistory=true
module:Refresh()
assert(type(module.context.callbacks.ADDON_LOADED)=='function','late history frame had no addon callback')
GroupLootHistoryFrame=frame
Event('ADDON_LOADED','Blizzard_UIPanels_Game')
assert(module.history==frame and not module.context.callbacks.ADDON_LOADED,
    'late history frame was not attached or kept its load listener')
assert(frame:GetScript('OnShow')==originalShow and frame:GetScript('OnHide')==originalHide
    and #frame.hooks.OnShow==1 and #frame.hooks.OnHide==1,
    'history management replaced Blizzard handlers instead of hooking them')
module:Refresh()
assert(#timers==0,'hidden history started timer')
frame:Show()
assert(frame:IsShown() and shows==1 and timers[#timers].delay==0,'native show must finish before suppression')
timers[#timers].callback()
assert(not frame:IsShown() and hides==1,'native hide cleanup was lost')
module.config.historyMode=2
module.config.historyDelay=17
module:Refresh()
frame:Show()
local old=timers[#timers]
assert(old.delay==17)
frame:Hide()
assert(old.cancelled)
frame:Show()
old.callback()
assert(frame:IsShown(),'stale timer closed a later history window')
combat=true
timers[#timers].callback()
assert(frame:IsShown() and module.pendingHistory and module.context.callbacks.PLAYER_REGEN_ENABLED)
combat=false
Event('PLAYER_REGEN_ENABLED')
assert(not frame:IsShown() and not module.context.callbacks.PLAYER_REGEN_ENABLED)
frame:Show()
old=timers[#timers]
local external=function() end
frame:SetScript('OnShow',external)
module.active=false
module:Disable()
module.context:Release()
assert(old.cancelled and frame:GetScript('OnShow')==external and frame:GetScript('OnHide')==originalHide,'disable overwrote external handler')
old.callback()
assert(frame:IsShown() and not next(module.context.frame.events))
frame:Hide()
frame:SetScript('OnShow',originalShow)
module.active=true
module:Enable()
frame:Show()
assert(timers[#timers].delay==17,'reactivation lost history policy')
assert(#frame.hooks.OnShow==1 and #frame.hooks.OnHide==1,'reactivation hooked the history frame again')
module.config.manageHistory=false
module:Refresh()
assert(frame:GetScript('OnShow')==originalShow and frame:GetScript('OnHide')==originalHide)
assert(timers[#timers].cancelled and not module.context.callbacks.ADDON_LOADED)
print('Loot: collection rules, secret/locked slots, synchronous close, history timers, native handlers, disable and import passed')
