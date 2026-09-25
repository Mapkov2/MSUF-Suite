local _, Private = ...
local NS=assert(_G.MSUFSuite,"MSUF_Suite is required")
local S=NS.Suite
Private.NS,Private.Suite=NS,S
S.editMode=_G.MSUF_UnitEditModeActive==true
local Context={}
Context.__index=Context
local Public
if type(issecretvalue)=="function" then
    local secretTest=issecretvalue
    Public=function(value) return not secretTest(value) end
else
    Public=function() return true end
end
local function Accessible(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end
local getCVar=C_CVar and C_CVar.GetCVar or GetCVar
local setCVar=C_CVar and C_CVar.SetCVar or SetCVar
local recoveryKey
local function Recovery(create)
    local root=NS.RootDB
    if not root then return nil end
    if not recoveryKey then
        local name=type(UnitName)=="function" and UnitName("player") or "player"
        local realm=type(GetRealmName)=="function" and GetRealmName() or "realm"
        if not Public(name) or not Public(realm) then return nil end
        recoveryKey=tostring(realm).."/"..tostring(name)
    end
    if type(root.suiteRecovery)~="table" then
        if not create then return nil end
        root.suiteRecovery={}
    end
    if type(root.suiteRecovery[recoveryKey])~="table" then
        if not create then return nil end
        root.suiteRecovery[recoveryKey]={}
    end
    return root.suiteRecovery[recoveryKey]
end
function S.RestoreSaved(id,onlyKey)
    local recovery=Recovery(false)
    local saved=recovery and recovery[id]
    if not saved or not getCVar or not setCVar then return end
    -- Records may come from SavedVariables; only known, bounded CVar names
    -- owned by this module are ever restored.
    local instance=S.instances[id]
    for key,entry in pairs(saved) do
        if (not onlyKey or key==onlyKey) and instance and instance.cvars and instance.cvars[key] and type(entry)=="table"
            and type(entry.before)=="string" and #entry.before<64 and type(entry.applied)=="string" then
            local current=getCVar(key)
            if Public(current) and current==entry.applied then setCVar(key,entry.before) end
        end
    end
    if onlyKey then saved[onlyKey]=nil end
    if not onlyKey or not next(saved) then recovery[id]=nil end
    if not next(recovery) then NS.RootDB.suiteRecovery[recoveryKey]=nil end
end
function S.RestoreCVar(id,key) S.RestoreSaved(id,key) end
function S.NewContext(id)
    return setmetatable({id=id,properties={},points={},callbacks={},fields={}},Context)
end
S.Public=Public
function S.Text(value) return NS.L and NS.L[value] or value end
function Context:Field(frame,key,value,refresh)
    if NS.IsCombatLocked() then S.Queue(self.id); return false end
    if not Accessible(frame) or not Public(frame[key]) or value==nil then return false end
    local record=self.fields[frame]
    if not record then record={values={},refresh=refresh}; self.fields[frame]=record end
    local saved=record.values[key]
    if not saved then saved={before=frame[key]}; record.values[key]=saved end
    local changed=frame[key]~=value
    if changed then frame[key]=value end
    saved.applied=value
    return changed
end
function Context:RestoreFields(frame)
    local record=self.fields[frame]
    if not record then return end
    local changed=false
    if Accessible(frame) then
        for key,saved in pairs(record.values) do
            if Public(frame[key]) and frame[key]==saved.applied then
                frame[key]=saved.before; changed=true
            end
        end
        if changed and record.refresh then record.refresh(frame) end
    end
    self.fields[frame]=nil
end
function Context:Skin()
    return NS.Skin.Acquire(self.id)
end
function Context:OwnSkin(method,target,options)
    self.ownedSkins=self.ownedSkins or {}
    self.ownedSkins[target]={method=method,options=options}
    local skin=self:Skin()
    if skin then skin[method](skin,target,options) end
end
function Context:RefreshOwnedSkins()
    if not self.ownedSkins then return end
    local skin=self:Skin()
    if not skin then return end
    for target,entry in pairs(self.ownedSkins) do
        skin[entry.method](skin,target,entry.options)
    end
end
function Context:Property(frame,getter,setter,value)
    if NS.IsCombatLocked() then S.Queue(self.id); return end
    if not Accessible(frame) or type(frame[getter])~="function" or type(frame[setter])~="function" then return end
    local current=frame[getter](frame)
    if not Public(current) then return end
    local props=self.properties[frame]
    if not props then props={}; self.properties[frame]=props end
    local record=props[setter]
    if not record then record={getter=getter,before=current}; props[setter]=record end
    if current~=value then frame[setter](frame,value) end
    local applied=frame[getter](frame)
    record.applied=Public(applied) and applied or value
end
function Context:Scale(frame,value) self:Property(frame,"GetScale","SetScale",value) end
function Context:Alpha(frame,value) self:Property(frame,"GetAlpha","SetAlpha",value) end
local function Pack(...) return {n=select("#",...),...} end
local function SameTuple(a,b)
    if a.n~=b.n then return false end
    for i=1,a.n do if not Public(a[i]) or not Public(b[i]) or a[i]~=b[i] then return false end end
    return true
end
-- Font triples and texture coordinates are cold configuration, never sampled
-- from action/cooldown events. Preserve foreign changes when releasing ownership.
function Context:Tuple(frame,getter,setter,...)
    if NS.IsCombatLocked() then S.Queue(self.id);return end
    if not Accessible(frame) or type(frame[getter])~="function" or type(frame[setter])~="function" then return end
    local before,wanted=Pack(frame[getter](frame)),Pack(...)
    for i=1,before.n do if not Public(before[i]) then return end end
    self.tuples=self.tuples or {}
    local values=self.tuples[frame] or {};self.tuples[frame]=values
    local record=values[setter] or {getter=getter,before=before};values[setter]=record
    if not SameTuple(before,wanted) then frame[setter](frame,unpack(wanted,1,wanted.n)) end
    record.applied=Pack(frame[getter](frame))
end
function Context:RestoreTuple(frame,setter)
    local values=self.tuples and self.tuples[frame]
    local record=values and values[setter]
    if not record then return end
    if Accessible(frame) and SameTuple(Pack(frame[record.getter](frame)),record.applied) then
        frame[setter](frame,unpack(record.before,1,record.before.n))
    end
    values[setter]=nil
    if not next(values) then self.tuples[frame]=nil end
end
function Context:RestoreProperty(frame,setter)
    local properties=self.properties[frame]
    local record=properties and properties[setter]
    if not record then return end
    if Accessible(frame) then
        local current=frame[record.getter](frame)
        if Public(current) and current==record.applied then frame[setter](frame,record.before) end
    end
    properties[setter]=nil
    if not next(properties) then self.properties[frame]=nil end
end
function Context:HideControl(frame,hidden)
    if not frame then return end
    if hidden then
        self:Alpha(frame,0)
        self:Property(frame,"IsMouseEnabled","EnableMouse",false)
    else
        self:RestoreProperty(frame,"SetAlpha")
        self:RestoreProperty(frame,"EnableMouse")
    end
end
function Context:Anchor(frame,point,relative,relativePoint,x,y)
    if NS.IsCombatLocked() then S.Queue(self.id); return end
    if not Accessible(frame) or not frame.GetNumPoints then return end
    local record=self.points[frame]
    if not record then
        record={before={}}
        for i=1,frame:GetNumPoints() do record.before[i]={frame:GetPoint(i)} end
        self.points[frame]=record
    end
    frame:ClearAllPoints(); frame:SetPoint(point,relative,relativePoint,x,y)
    local actualPoint,actualRelative,actualRelativePoint,actualX,actualY=frame:GetPoint(1)
    if Public(actualPoint) and Public(actualX) and Public(actualY) then
        record.point,record.x,record.y=actualPoint,actualX,actualY
        record.relative,record.relativePoint=actualRelative,actualRelativePoint
    end
end
function Context:Position(frame,point,x,y) self:Anchor(frame,point,UIParent,point,x,y) end
function Context:RestorePoints(frame)
    local record=self.points[frame]
    if not record or not Accessible(frame) then return end
    local point,relative,relativePoint,x,y=frame:GetPoint(1)
    if Public(point) and Public(relative) and Public(relativePoint) and Public(x) and Public(y)
        and frame:GetNumPoints()==1 and point==record.point and relative==record.relative
        and relativePoint==record.relativePoint and x==record.x and y==record.y then
        frame:ClearAllPoints()
        for i=1,#record.before do frame:SetPoint(unpack(record.before[i])) end
    end
    self.points[frame]=nil
end
function Context:CVar(key,value)
    if not getCVar or not setCVar then return false end
    local current=getCVar(key)
    if not Public(current) or current==nil then return false end
    value=tostring(value)
    local recovery=Recovery(true)
    if not recovery then return false end
    local record
    if recovery then
        recovery[self.id]=recovery[self.id] or {}
        record=recovery[self.id][key]
        if type(record)~="table" then record={before=current}; recovery[self.id][key]=record end
        record.applied=value
    end
    if current~=value then setCVar(key,value) end
    local applied=getCVar(key)
    if Public(applied) and type(applied)=="string" then record.applied=applied end
    return true
end
function Context:CVarMask(key,mask)
    if not CVarCallbackRegistry or type(CVarCallbackRegistry.SetCVarBitfieldMask)~="function" or not getCVar then return false end
    local before=getCVar(key)
    if not Public(before) or type(before)~="string" or before=="" then return false end
    -- These CVars contain Blizzard's encoded bit arrays, not decimal masks.
    -- Snapshot the original bytes, delegate encoding, then record the result.
    if not self:CVar(key,before) then return false end
    CVarCallbackRegistry:SetCVarBitfieldMask(key,mask)
    local applied=getCVar(key)
    if Public(applied) and type(applied)=="string" then self:CVar(key,applied) end
    return true
end
local function Dispatch(frame,event,...)
    local ctx=frame.context
    local module=S.instances[ctx.id]
    if not module.active then return end
    if event=="ADDON_LOADED" and module.addons and not module.addons[(...)] then return end
    if module.geometry and not (ctx.combatEvents and ctx.combatEvents[event]) and NS.IsCombatLocked() then S.Queue(ctx.id); return end
    local callback=ctx.callbacks[event]
    if callback then callback(module,event,...) end
end
function Context:Event(event,callback,allowCombat)
    if not NS.Client.SupportsEvent(event) then return end
    local alreadyRegistered=self.callbacks[event]~=nil
    if not self.frame then
        self.frame=S.CreateFrame("Frame"); self.frame.context=self
        self.frame:SetScript("OnEvent",Dispatch)
    end
    self.combatEvents=self.combatEvents or {}
    self.combatEvents[event]=allowCombat or nil
    self.callbacks[event]=callback
    if not alreadyRegistered then self.frame:RegisterEvent(event) end
end
function Context:RemoveEvent(event)
    if self.callbacks[event]==nil then return end
    self.callbacks[event]=nil
    if self.combatEvents then self.combatEvents[event]=nil end
    if self.frame then self.frame:UnregisterEvent(event) end
end
function Context:Callback(event,callback)
    if not EventRegistry or type(EventRegistry.RegisterCallback)~="function" then return false end
    self.registryCallbacks=self.registryCallbacks or {}
    if self.registryCallbacks[event] then return true end
    local ctx=self
    local function Invoke()
        local module=S.instances[ctx.id]
        if not module.active then return end
        if module.geometry and NS.IsCombatLocked() then S.Queue(ctx.id); return end
        callback(module)
    end
    self.registryCallbacks[event]=Invoke
    EventRegistry:RegisterCallback(event,Invoke,self)
    return true
end
function Context:Release()
    if self.tuples then
        for frame,values in pairs(self.tuples) do
            for setter in pairs(values) do self:RestoreTuple(frame,setter) end
        end
    end
    if self.frame then self.frame:UnregisterAllEvents() end
    for key in pairs(self.callbacks) do self.callbacks[key]=nil end
    if self.combatEvents then for key in pairs(self.combatEvents) do self.combatEvents[key]=nil end end
    if self.registryCallbacks then
        for event in pairs(self.registryCallbacks) do
            EventRegistry:UnregisterCallback(event,self)
            self.registryCallbacks[event]=nil
        end
    end
    for frame in pairs(self.fields) do self:RestoreFields(frame) end
    for frame,properties in pairs(self.properties) do
        if Accessible(frame) then
            for setter,record in pairs(properties) do
                local current=frame[record.getter](frame)
                if Public(current) and current==record.applied then frame[setter](frame,record.before) end
            end
        end
        self.properties[frame]=nil
    end
    for frame in pairs(self.points) do self:RestorePoints(frame) end
    NS.Skin.Release(self.id)
    S.RestoreSaved(self.id)
end
function S.Install(id,module)
    assert(S.catalog[id] and not S.instances[id],"Invalid suite module")
    module.id=id
    S.instances[id]=module
end
