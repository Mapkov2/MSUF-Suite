local root=assert(arg[1],"repository root required")
-- Offline contract for the action bar runtime (MSUF_Suite_Modules/ActionBars).
-- The harness emulates the secure environment: restricted snippets run in a
-- sandbox that only offers the restricted API, state drivers resolve macro
-- conditions, wrapped scripts follow SecureHandlers.lua, and every protected
-- write from insecure code during combat raises ADDON_ACTION_BLOCKED.
-- Secret values are sentinels that raise on comparison, arithmetic,
-- concatenation, indexing and tostring.

------------------------------------------------------------------ secrets
local SecretMT={}
local function Raise(what) return function() error("secret value used: "..what,2) end end
for _,key in ipairs({"__add","__sub","__mul","__div","__mod","__pow","__unm","__concat","__lt","__le","__eq","__call"}) do
    SecretMT[key]=Raise(key)
end
SecretMT.__index=Raise("index");SecretMT.__newindex=Raise("assignment");SecretMT.__tostring=Raise("tostring")
local function Secret() return setmetatable({},SecretMT) end
local function IsSecret(value) return getmetatable(value)==SecretMT end
issecretvalue=IsSecret

------------------------------------------------------------------ callback isolation
-- The client's securecallfunction reports an error to the error handler and
-- returns nothing; the caller goes on. Here errors still raise unless a test
-- expects one; a coroutine then holds the error back from the caller.
local dispatch={expect=false,errors={}}
securecallfunction=function(fn,...)
    if not dispatch.expect then return fn(...) end
    local results={coroutine.resume(coroutine.create(fn),...)}
    if results[1] then return unpack(results,2,table.maxn(results)) end
    dispatch.errors[#dispatch.errors+1]=tostring(results[2])
end

------------------------------------------------------------------ clock, timers, combat
local combat,secure=false,0
local now=100
InCombatLockdown=function() return combat end
UnitAffectingCombat=function(unit) return unit=="player" and combat end
GetTime=function() return now end
local timers={}
C_Timer={After=function(delay,fn) timers[#timers+1]={at=now+(delay or 0),fn=fn} end}
local function RunTimers()
    local guard=0
    while #timers>0 do
        guard=guard+1;assert(guard<500,"timer loop")
        table.sort(timers,function(a,b) return a.at<b.at end)
        local timer=table.remove(timers,1)
        if timer.at>now then now=timer.at end
        timer.fn()
    end
end
-- One frame: only the timers already due run; later ones stay queued.
local function RunDue()
    local guard=0
    while true do
        guard=guard+1;assert(guard<500,"timer loop")
        local index
        for i=1,#timers do if timers[i].at<=now then index=i;break end end
        if not index then return end
        table.remove(timers,index).fn()
    end
end

-- Lua VM instructions of fn(...) with the GC stopped (deterministic for one
-- interpreter build): the budgets of the hot paths. A budget holds the
-- instructions measured on 2026-10-01 before the wave-1 restructuring plus
-- 2 %; a path may get cheaper, never dearer.
local function Cost(fn,...)
    local n=0
    collectgarbage("stop")
    debug.sethook(function() n=n+1 end,"",1)
    fn(...)
    debug.sethook()
    collectgarbage("restart")
    return n
end
local function Budget(label,used,baseline)
    assert(used<=math.floor(baseline*1.02),
        ("%s: %d instructions, budget %d (+2%%)"):format(label,used,math.floor(baseline*1.02)))
end

------------------------------------------------------------------ frames
local Frame,Region={},{}
Frame.__index=Frame;Region.__index=Region
local nextId,created=0,0
local function IsProtected(frame)
    if frame.explicit or frame.implicit then return true end
    for child in pairs(frame.children or {}) do if IsProtected(child) then return true end end
    return false
end
local function Guard(frame,what)
    if combat and secure==0 and IsProtected(frame) then error("ADDON_ACTION_BLOCKED: "..what.." "..tostring(frame.name),3) end
end
local function Visible(frame)
    while frame do
        if not frame.shown then return false end
        frame=frame.parent
    end
    return true
end
local function EffectiveAlpha(region)
    local alpha=region.alpha
    local parent=region.parent
    while parent do
        alpha=alpha*parent.alpha
        parent=parent.parent
    end
    return alpha
end
local function Fire(frame,script,...)
    local handler=frame.scripts[script]
    if handler then handler(frame,...) end
    local hooks=frame.hooks[script]
    if hooks then
        -- Post-hooks are addon code: insecure even inside secure dispatch.
        local saved=secure;secure=0
        for i=1,#hooks do hooks[i](frame,...) end
        secure=saved
    end
end
local function NewRegion(kind,parent)
    return setmetatable({kind=kind,parent=parent,shown=true,alpha=1,points={}},Region)
end
function Region:SetTexture(value) self.texture=value;self.atlas=nil end
function Region:GetTexture() return self.texture end
function Region:SetAtlas(value) self.atlas=value end
function Region:GetAtlas() return self.atlas end
function Region:SetColorTexture(r,g,b,a) self.color={r,g,b,a};self.texture="color" end
function Region:SetVertexColor(r,g,b,a) assert(not IsSecret(r),"vertex color from a secret");self.vertex={r,g,b,a} end
function Region:SetDesaturation(value) self.desaturation=value end
function Region:SetTexCoord(...) self.coords={...} end
function Region:SetAlpha(value) self.alpha=value end
function Region:GetAlpha() return self.alpha end
function Region:Show() self.shown=true end
function Region:Hide() self.shown=false end
function Region:SetShown(value) self.shown=value and true or false end
function Region:IsShown() return self.shown end
function Region:SetSwipeTexture(texture) self.swipeTexture=texture end
function Region:SetPoint(...) self.points[#self.points+1]={...} end
function Region:ClearAllPoints() self.points={} end
function Region:SetAllPoints(target) self.points={{"ALL",target}} end
function Region:SetSize(w,h) self.width,self.height=w,h end
function Region:SetWidth(w) self.width=w end
function Region:SetHeight(h) self.height=h end
function Region:SetDrawLayer() end
function Region:SetBlendMode(mode) self.blend=mode end
function Region:GetBlendMode() return self.blend or "BLEND" end
function Region:SetRotation(value) self.rotation=value end
function Region:AddMaskTexture(mask) self.mask=mask end
function Region:RemoveMaskTexture(mask) self.unmasked=mask end
function Region:SetFont(path,size,flags) self.font={path,size,flags};return true end
function Region:SetText(value) self.text=value end
function Region:GetText() return self.text end
function Region:SetTextColor(r,g,b) self.textColor={r,g,b} end
function Region:SetShadowOffset(x,y) self.shadowOffset={x,y} end
function Region:SetShadowColor(r,g,b,a) self.shadowColor={r,g,b,a} end
function Region:SetJustifyH() end
function Region:SetWordWrap() end

local TEMPLATES={}
local allFrames={}
local function NewFrame(kind,name,parent,templates)
    nextId=nextId+1;created=created+1
    local frame=setmetatable({kind=kind,name=name,id=nextId,attrs={},scripts={},hooks={},children={},points={},events={},
        shown=true,alpha=1,width=0,height=0,mouse=true,level=1},Frame)
    allFrames[#allFrames+1]=frame
    if parent then frame.parent=parent;parent.children[frame]=true end
    if name then _G[name]=frame end
    if type(templates)=="string" then
        for template in templates:gmatch("[^,%s]+") do assert(TEMPLATES[template],"unknown template "..template)(frame) end
    end
    return frame
end
CreateFrame=NewFrame
function Frame:GetName() return self.name end
function Frame:IsForbidden() return false end
function Frame:IsProtected() return IsProtected(self),self.explicit==true end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent)
    Guard(self,"SetParent")
    if self.parent then self.parent.children[self]=nil end
    self.parent=parent
    if parent then parent.children[self]=true end
    self.reparented=(self.reparented or 0)+1
    self.securelyReparented=secure>0
end
function Frame:GetChildren()
    local list={}
    for child in pairs(self.children) do list[#list+1]=child end
    table.sort(list,function(a,b) return a.id<b.id end)
    return unpack(list)
end
-- A frame that becomes visible or invisible passes OnShow/OnHide on to its
-- shown children, which change visibility with it (the client does the same).
local function Cascade(frame,script)
    Fire(frame,script)
    for _,child in ipairs({frame:GetChildren()}) do
        if child.shown then Cascade(child,script) end
    end
end
function Frame:Show()
    Guard(self,"Show")
    local was=Visible(self)
    self.shown=true
    if not was and Visible(self) then Cascade(self,"OnShow") end
end
function Frame:Hide()
    Guard(self,"Hide")
    self.hideCalls=(self.hideCalls or 0)+1
    local was=Visible(self)
    self.shown=false
    if was then Cascade(self,"OnHide") end
end
function Frame:SetShown(value) if value then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return Visible(self) end
function Frame:SetAlpha(value) self.alpha=value end
function Frame:GetAlpha() return self.alpha end
function Frame:SetPoint(...) Guard(self,"SetPoint");self.points[#self.points+1]={...} end
function Frame:ClearAllPoints() Guard(self,"ClearAllPoints");self.points={} end
function Frame:SetAllPoints(target) Guard(self,"SetAllPoints");self.points={{"ALL",target}} end
function Frame:GetPoint(i) local point=self.points[i or 1];if point then return unpack(point) end end
function Frame:GetNumPoints() return #self.points end
function Frame:SetSize(w,h) Guard(self,"SetSize");self.width,self.height=w,h end
function Frame:SetWidth(w) Guard(self,"SetWidth");self.width=w end
function Frame:SetHeight(h) Guard(self,"SetHeight");self.height=h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetSize() return self.width,self.height end
function Frame:GetCenter() return self.cx,self.cy end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetScale() return 1 end
function Frame:SetAttribute(name,value)
    Guard(self,"SetAttribute "..tostring(name))
    self.attrs[name]=value
    Fire(self,"OnAttributeChanged",name,value)
end
function Frame:GetAttribute(name) return self.attrs[name] end
function Frame:SetScript(script,handler) self.scripts[script]=handler end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:HookScript(script,handler)
    self.hooks[script]=self.hooks[script] or {}
    table.insert(self.hooks[script],handler)
end
function Frame:HasScript() return true end
function Frame:RegisterEvent(event) self.events[event]=true end
function Frame:UnregisterEvent(event) self.events[event]=nil end
function Frame:UnregisterAllEvents() self.events={};self.strippedEvents=true end
function Frame:EnableMouse(value) Guard(self,"EnableMouse");self.mouse=value and true or false end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:EnableMouseMotion(value) Guard(self,"EnableMouseMotion");self.motion=value end
function Frame:IsMouseOver() return self.mouseOver==true end
function Frame:SetFrameStrata(value) self.strata=value end
function Frame:StopAnimating() self.animationStops=(self.animationStops or 0)+1 end
function Frame:SetFrameLevel(value) self.level=value end
function Frame:GetFrameLevel() return self.level end
function Frame:RegisterForClicks(...) self.clickTypes={...} end
function Frame:RegisterForDrag() end
function Frame:GetID() return self.nativeID or 0 end
function Frame:SetChecked(value) assert(not IsSecret(value));self.checked=value and true or false end
function Frame:GetChecked() return self.checked end
function Frame:SetButtonState(state) self.state=state end
function Frame:GetNormalTexture() return self.NormalTexture end
function Frame:GetPushedTexture() return self.PushedTexture end
function Frame:GetHighlightTexture() return self.HighlightTexture end
function Frame:GetCheckedTexture() return self.CheckedTexture end
function Frame:CreateMaskTexture() return NewRegion("MaskTexture",self) end
function Frame:SetHighlightTexture(file) self.HighlightTexture=NewRegion("Texture",self);self.HighlightTexture:SetTexture(file) end
function Frame:SetNormalAtlas(atlas) self.normalAtlas=atlas end
function Frame:SetPushedAtlas(atlas) self.pushedAtlas=atlas end
function Frame:SetDisabledAtlas(atlas) self.disabledAtlas=atlas end
function Frame:SetHighlightAtlas(atlas) self.highlightAtlas=atlas end
-- Button:Click runs the button's OnClick like a click on it.
function Frame:Click(button) Fire(self,"OnClick",button or "LeftButton",false) end
function Frame:CreateTexture(_,layer) local region=NewRegion("Texture",self);region.layer=layer;return region end
function Frame:CreateFontString(_,layer) local region=NewRegion("FontString",self);region.layer=layer;return region end
-- Cooldown sinks. SetCooldown refuses secrets (AllowedWhenUntainted).
function Frame:SetCooldown(start,duration,modRate)
    assert(not IsSecret(start) and not IsSecret(duration) and not IsSecret(modRate),"secret passed to SetCooldown")
    self.cooldown={start,duration};self.object=nil
end
function Frame:SetCooldownFromDurationObject(object)
    assert(type(object)=="table" and object.duration,"not a duration object")
    if object.zero then
        if self.object or self.cooldown then self:Clear() end
    else
        self.object=object;self.cooldown=nil
    end
end
function Frame:Clear() self.object,self.cooldown=nil,nil;self.clears=(self.clears or 0)+1 end
function Frame:SetSwipeColor(...) self.swipe={...} end
function Frame:SetDrawEdge() end
function Frame:SetSwipeTexture(texture) self.swipeTexture=texture end
function Frame:GetChecked() return self.checked end
function Frame:SetDrawBling() end
function Frame:SetHideCountdownNumbers(value) self.hideNumbers=value end
function Frame:GetCountdownFontString() self.countdown=self.countdown or NewRegion("FontString",self);return self.countdown end

------------------------------------------------------------------ restricted environment
local Handles=setmetatable({},{__mode="k"})
local Handle={}
Handle.__index=Handle
local function H(frame)
    if not frame then return nil end
    local handle=Handles[frame]
    if not handle then handle=setmetatable({frame=frame},Handle);Handles[frame]=handle end
    return handle
end
local function Usable(handle)
    if combat and not IsProtected(handle.frame) then error("Invalid frame handle") end
    return handle.frame
end
local actions,special,pressHold,modified={},{},{},{}
local pickupModifier, pickupWrites = "SHIFT", 0
GetModifiedClick = function(action)
    assert(action == "PICKUPACTION")
    return pickupModifier
end
SetModifiedClick = function(action, value)
    assert(action == "PICKUPACTION")
    pickupModifier, pickupWrites = value, pickupWrites + 1
end
local barPage=1
local RENV={tonumber=tonumber,tostring=tostring,floor=math.floor,
    HasAction=function(slot) return actions[slot]~=nil end,
    GetActionInfo=function(slot) local a=actions[slot];if a then return a.kind,a.id,a.sub end end,
    IsPressHoldReleaseSpell=function(id) return pressHold[id]==true end,
    IsModifiedClick=function(what) return modified[what]==true end,
    GetActionBarPage=function() return barPage end,
    HasVehicleActionBar=function() return special.vehicle==true end,GetVehicleBarIndex=function() return 12 end,
    HasOverrideActionBar=function() return special.override==true end,GetOverrideBarIndex=function() return 18 end,
    HasTempShapeshiftActionBar=function() return special.temp==true end,GetTempShapeshiftBarIndex=function() return 16 end,
    HasBonusActionBar=function() return special.bonus~=nil end,GetBonusBarIndex=function() return 6+(special.bonus or 0) end}
local NILABLE={newstate=true,stateid=true,message=true,scriptid=true,button=true,down=true,kind=true,value=true}
local snippetRuns=0
local function RunSnippet(frame,body,vars,control,...)
    assert(type(body)=="string","snippet body missing")
    local fn=assert(loadstring(body))
    local env=setmetatable({self=H(frame),control=H(control or frame)},{__index=function(_,key)
        local value=RENV[key]
        if value==nil and not NILABLE[key] then error("restricted snippet read unknown global "..tostring(key),2) end
        return value
    end,__newindex=function(_,key) error("restricted snippet wrote global "..tostring(key),2) end})
    for key,value in pairs(vars) do rawset(env,key,value) end
    setfenv(fn,env)
    snippetRuns=snippetRuns+1
    secure=secure+1
    local results={fn(...)}
    secure=secure-1
    return unpack(results)
end
function Handle:GetAttribute(name) assert(not name:match("^_"),"restricted read of "..name);return Usable(self).attrs[name] end
function Handle:SetAttribute(name,value) assert(not name:match("^_"),"restricted write of "..name);Usable(self):SetAttribute(name,value) end
function Handle:GetFrameRef(label) return Usable(self).attrs["frameref-"..label] end
function Handle:Show(skip) local frame=Usable(self);frame:Show();if not skip then frame:SetAttribute("statehidden",nil) end end
function Handle:Hide(skip) local frame=Usable(self);frame:Hide();if not skip then frame:SetAttribute("statehidden",true) end end
function Handle:IsShown() return Usable(self):IsShown() end
function Handle:GetParent() return H(Usable(self).parent) end
function Handle:SetParent(parent) assert(parent.frame.explicit,"SetParent needs an explicitly protected parent");Usable(self):SetParent(parent.frame) end
function Handle:SetAlpha(value) Usable(self):SetAlpha(value) end
function Handle:EnableMouse(value) Usable(self):EnableMouse(value) end
function Handle:RunAttribute(name,...) local frame=Usable(self);return RunSnippet(frame,frame.attrs[name],{},frame,...) end
function Handle:ChildUpdate(id,message)
    local frame=Usable(self)
    for _,child in ipairs({frame:GetChildren()}) do
        if IsProtected(child) then
            local body=child.attrs["_childupdate-"..id] or child.attrs["_childupdate"]
            if body then RunSnippet(child,body,{scriptid=id,message=message},frame) end
        end
    end
end
local function StateHandler(frame,name,value)
    local id=type(name)=="string" and name:match("^state%-(.+)")
    local body=id and frame.attrs["_onstate-"..id]
    if body then RunSnippet(frame,body,{stateid=id,newstate=value},frame) end
end
local clicks,flyoutUpdates={},0
TEMPLATES.SecureFrameTemplate=function(frame) frame.explicit=true end
TEMPLATES.SecureHandlerBaseTemplate=function(frame) frame.explicit=true end
TEMPLATES.SecureHandlerStateTemplate=function(frame) frame.explicit=true;frame.scripts.OnAttributeChanged=StateHandler end
TEMPLATES.SecureActionButtonTemplate=function(frame)
    frame.explicit=true
    frame.scripts.OnClick=function(self,button,down) clicks[#clicks+1]={frame=self,button=button,down=down,keydown=self.attrs.useOnKeyDown} end
end
local function ActionRegions(frame)
    for _,key in ipairs({"icon","IconMask","NormalTexture","PushedTexture","HighlightTexture","CheckedTexture","SlotArt","SlotBackground",
        "Flash","Border","NewActionTexture","SpellHighlightTexture"}) do frame[key]=NewRegion("Texture",frame) end
    frame.HighlightTexture.atlas="UI-HUD-ActionBar-IconFrame-Mouseover"
    -- Mainline/ActionButtonTemplate.xml puts counts and keys on a child
    -- overlay; its OnLoad also exposes those regions on the action button.
    local overlay=NewFrame("Frame",nil,frame)
    frame.TextOverlayContainer=overlay
    for _,key in ipairs({"Count","HotKey"}) do
        overlay[key]=NewRegion("FontString",overlay)
        frame[key]=overlay[key]
    end
    frame.Name=NewRegion("FontString",frame)
    for _,key in ipairs({"cooldown","chargeCooldown","lossOfControlCooldown"}) do frame[key]=NewFrame("Cooldown",nil,frame) end
end
TEMPLATES.ActionButtonTemplate=function(frame)
    ActionRegions(frame)
    -- BaseActionButtonMixin_OnAttributeChanged -> UpdateFlyout.
    frame.scripts.OnAttributeChanged=function() flyoutUpdates=flyoutUpdates+1 end
end
ActionButtonSpellAlertMixin={}
TEMPLATES.ActionButtonSpellAlertTemplate=function(frame)
    frame.shown=false
    local function Animation()
        return {Play=function(self) self.playing=true end,Stop=function(self) self.playing=false end}
    end
    frame.ProcStartAnim,frame.ProcLoop=Animation(),Animation()
end
SecureHandlerExecute=function(frame,body)
    assert(not combat,"Cannot use SecureHandlers API during combat")
    assert(frame.explicit,"Header frame must be explicitly protected")
    RunSnippet(frame,body,{},frame)
end
SecureHandlerSetFrameRef=function(frame,label,target)
    assert(not combat,"Cannot use SecureHandlers API during combat")
    frame.attrs["frameref-"..label]=H(target)
end
local pickups={}
local cursor
GetCursorInfo=function() return cursor end
SecureHandlerWrapScript=function(frame,script,header,pre,post)
    assert(not combat and header.explicit,"invalid wrap")
    local original=frame.scripts[script]
    local wrapped
    if script=="OnClick" then
        wrapped=function(self,button,down)
            local newbutton=RunSnippet(self,pre,{button=button,down=down},header)
            if newbutton==false then return end
            if newbutton then button=tostring(newbutton) end
            if original then original(self,button,down) end
        end
    elseif script=="OnDragStart" or script=="OnReceiveDrag" then
        wrapped=function(self,button)
            local kind,value=GetCursorInfo()
            local pickup,target=RunSnippet(self,pre,{button=button,kind=kind,value=value},header)
            if pickup==false then return end
            if pickup then assert(pickup=="action");pickups[#pickups+1]=target;return end
            if original then original(self,button) end
        end
    elseif script=="OnShow" or script=="OnHide" then
        -- Wrapped_ShowHide (SecureHandlers.lua): the pre-body runs for a
        -- protected frame (or out of combat), false aborts, then the original
        -- handler, then the post-body when the pre-body returned a message.
        wrapped=function(self,...)
            local allow,message
            if not combat or IsProtected(self) then allow,message=RunSnippet(self,pre,{},header) end
            if allow==false then return end
            if original then original(self,...) end
            if post and message~=nil then RunSnippet(self,post,{message=message},header) end
        end
    else
        error("unexpected wrap "..script)
    end
    frame.scripts[script]=wrapped
    frame.wraps=(frame.wraps or 0)+1
end

-- State drivers evaluate macro conditions against `conditions`.
local conditions={}
local function Trim(text) return (text:gsub("^%s+",""):gsub("%s+$","")) end
local function Test(condition)
    condition=Trim(condition)
    local negated=condition:match("^no(%a+)$")
    if negated and condition~="none" then return not conditions[negated] end
    return conditions[condition]==true
end
local function Evaluate(values)
    for clause in (values..";"):gmatch("(.-);") do
        clause=Trim(clause)
        if clause:sub(1,1)~="[" then return clause end
        local matched,rest=false,clause
        while rest:sub(1,1)=="[" do
            local group,after=rest:match("^%[([^%]]*)%](.*)$")
            local all=true
            for part in (group..","):gmatch("(.-),") do if not Test(part) then all=false end end
            if all then matched=true end
            rest=after
        end
        if matched then return Trim(rest) end
    end
end
local drivers={}
local function Resolve(frame,state,values)
    local value=Evaluate(values)
    value=tonumber(value) or value
    if frame.attrs["state-"..state]~=value then
        secure=secure+1
        frame:SetAttribute("state-"..state,value)
        secure=secure-1
    end
end
RegisterStateDriver=function(frame,state,values)
    assert(not combat,"driver registration in combat")
    drivers[frame]=drivers[frame] or {}
    drivers[frame][state]=values
    Resolve(frame,state,values)
end
UnregisterStateDriver=function(frame,state)
    assert(not combat,"driver removal in combat")
    if drivers[frame] then drivers[frame][state]=nil end
end
local function Drivers()
    for frame,list in pairs(drivers) do for state,values in pairs(list) do Resolve(frame,state,values) end end
end
local function Click(frame,button,down)
    Fire(frame,"PreClick",button,down);Fire(frame,"OnClick",button,down);Fire(frame,"PostClick",button,down)
end

-- The client sends an event to every frame registered for it.
local function Broadcast(event,...)
    for _,frame in ipairs(allFrames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,event,...) end
    end
end
local printed={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,text) printed[#printed+1]=text end}

------------------------------------------------------------------ client API
UIParent=NewFrame("Frame","UIParent")
UIParent.width,UIParent.height=1024,768
GetPhysicalScreenSize=function() return 1024,768 end
GameFontHighlightSmall={GetFont=function() return "Fonts\\FRIZQT__.TTF",12,"" end}
RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43}}
UnitClass=function() return "Warrior","WARRIOR" end
C_ClassColor={GetClassColor=function() return {r=.78,g=.61,b=.43} end}
Enum={LuaCurveType={Step=1}}
-- SpellConstantsDocumentation.lua: the global cooldown's start recovery category.
Constants={SpellCooldownConsts={GLOBAL_RECOVERY_CATEGORY=133}}
local secretEval=false
-- Slots for which the client returns no duration object (seen on 12.1).
local noDuration={}
local function Curve()
    local curve={points={}}
    function curve:SetType(value) self.type=value end
    function curve:AddPoint(x,y) assert(not IsSecret(x) and not IsSecret(y));self.points[#self.points+1]={x,y} end
    function curve:ClearPoints() self.points={} end
    return curve
end
C_CurveUtil={CreateCurve=Curve}
local function Duration(slot,ignoreGCD)
    if noDuration[slot] then return nil end
    local action=actions[slot]
    local object={duration=true,slot=slot,ignoreGCD=ignoreGCD,
        zero=not (action and action.cooldown and action.cooldown.isActive)}
    function object:EvaluateRemainingDuration(curve)
        assert(curve and curve.points,"curve required")
        if secretEval then return Secret() end
        local a=actions[slot]
        local remaining=a and a.remaining or 0
        local value=curve.points[1][2]
        for _,point in ipairs(curve.points) do if remaining>=point[1] then value=point[2] end end
        return value
    end
    return object
end
local calls,rangeEnabled,ranges={cooldown=0,duration=0,charges=0,loc=0,usable=0,texture=0,usableBySlot={}},{},{}
calls.chargesBySlot={}
-- C_Spell.GetOverrideSpell answers the spell itself without an override.
local spellOverrides={}
C_Spell={GetOverrideSpell=function(id) assert(not IsSecret(id),"secret spell ID reached GetOverrideSpell");return spellOverrides[id] or id end}
local locCount=0
C_LossOfControl={GetActiveLossOfControlDataCountByUnit=function(unit)
    assert(unit=="player")
    return locCount
end}
local rangeOn,rangeOff=0,0
C_ActionBar={
    -- Crafting quality exists for item actions only (CraftingQualityInfo).
    GetProfessionQualityInfo=function(slot)
        calls.quality=(calls.quality or 0)+1
        local a=actions[slot]
        return a and a.quality and {iconInventory=a.quality} or nil
    end,
    IsItemAction=function(slot) local a=actions[slot];return a~=nil and a.kind=="item" end,
    HasAction=function(slot) return actions[slot]~=nil end,
    GetActionTexture=function(slot) calls.texture=calls.texture+1;local a=actions[slot];return a and a.texture end,
    GetActionDisplayCount=function(slot) local a=actions[slot];return a and a.count or "" end,
    GetActionCooldown=function(slot)
        calls.cooldown=calls.cooldown+1
        local a=actions[slot]
        return a and a.cooldown or {isActive=false,isEnabled=true,startTime=0,duration=0,modRate=1}
    end,
    GetActionCooldownDuration=function(slot,ignoreGCD)
        calls.duration=calls.duration+1
        return Duration(slot,ignoreGCD)
    end,
    GetActionCharges=function(slot)
        calls.charges=calls.charges+1
        calls.chargesBySlot[slot]=(calls.chargesBySlot[slot] or 0)+1
        local a=actions[slot]
        return a and a.charges or {isActive=false,maxCharges=0,currentCharges=0}
    end,
    GetActionChargeDuration=function(slot)
        local object=Duration(slot)
        if not object then return nil end
        local a=actions[slot];local charges=a and a.charges
        -- Charge duration follows the recharge, independently of the main GCD.
        object.zero=not IsSecret(charges) and not (charges and charges.isActive)
        return object
    end,
    GetActionLossOfControlCooldownInfo=function()
        calls.loc=calls.loc+1
        return {isActive=false,shouldReplaceNormalCooldown=false}
    end,
    GetActionLossOfControlCooldownDuration=function(slot) return Duration(slot) end,
    IsUsableAction=function(slot)
        calls.usable=calls.usable+1
        calls.usableBySlot[slot]=(calls.usableBySlot[slot] or 0)+1
        local a=actions[slot]
        if not a then return false,false end
        return a.usable~=false,a.noMana==true
    end,
    IsCurrentAction=function(slot) local a=actions[slot];return a and a.current==true or false end,
    IsAutoRepeatAction=function() return false end,
    IsEquippedAction=function(slot) local a=actions[slot];return a and a.equipped==true or false end,
    UsesActionText=function(slot) local a=actions[slot];return a and a.text~=nil or false end,
    GetActionText=function(slot) local a=actions[slot];return a and a.text end,
    IsActionInRange=function(slot) return ranges[slot] end,
    EnableActionRangeCheck=function(slot,on)
        if on then rangeEnabled[slot]=true;rangeOn=rangeOn+1 else rangeEnabled[slot]=nil;rangeOff=rangeOff+1 end
    end,
}
local infoReads=0
GetActionInfo=function(slot)
    infoReads=infoReads+1
    local a=actions[slot]
    if a then return a.kind,a.id,a.sub end
end
-- Flyout 7 (slot 49) holds two spells; both clients have these globals.
local flyoutSpells={[7]={701,702}}
GetFlyoutInfo=function(id) local list=flyoutSpells[id];return "Flyout","",list and #list or 0,true end
GetFlyoutSlotInfo=function(id,index) local list=flyoutSpells[id];return list and list[index] end
local overlayed,alerts,assistedAction={},{},{}
C_SpellActivationOverlay={IsSpellOverlayed=function(id) assert(not IsSecret(id));return overlayed[id]==true end}
ActionButtonSpellAlertManager={
    ShowAlert=function(_,button)
        alerts[button]=true
        -- Like the manager's GetAlertFrame: the frame appears on the first
        -- proc; the assisted-combat rotation action's alert lives on the
        -- button's AssistedCombatRotationFrame.
        local host=button
        if assistedAction[button] then
            button.AssistedCombatRotationFrame=button.AssistedCombatRotationFrame or NewFrame("Frame",nil,button)
            host=button.AssistedCombatRotationFrame
        end
        host.SpellActivationAlert=host.SpellActivationAlert or NewFrame("Frame",nil,host)
        host.SpellActivationAlert:Show()
    end,
    HideAlert=function(_,button) alerts[button]=nil end,
}
-- Blizzard_ActionBar/Mainline/AssistedCombatManager.lua (Retail; Forever
-- does not load it). Candidates are Blizzard's own buttons only (its
-- ActionBarButtonEventsFrame list); a button's highlight frame appears on its
-- first recommendation, at alpha 1. Recommend models the manager's OnUpdate
-- seeing a new C_AssistedCombat.GetNextCastSpell answer.
AssistedCombatManager={candidates={}}
function AssistedCombatManager:SetAssistedHighlightFrameShown(button,shown)
    local frame=button.AssistedCombatHighlightFrame
    if shown then
        if not frame then
            frame=NewFrame("Frame",nil,button)
            button.AssistedCombatHighlightFrame=frame
        end
        frame:Show()
    elseif frame then
        frame:Hide()
    end
end
function AssistedCombatManager:UpdateAllAssistedHighlightFramesForSpell(spell)
    for button,candidate in pairs(self.candidates) do
        self:SetAssistedHighlightFrameShown(button,spell~=nil and candidate==spell)
    end
end
local function Recommend(spell)
    AssistedCombatManager.lastNextCastSpellID=spell
    AssistedCombatManager:UpdateAllAssistedHighlightFramesForSpell(spell)
end
-- A spell lands on one of Blizzard's buttons (ActionButton.OnActionChanged).
function AssistedCombatManager:OnActionButtonActionChanged(button,spell)
    self.candidates[button]=spell
    self:SetAssistedHighlightFrameShown(button,self.lastNextCastSpellID~=nil and spell==self.lastNextCastSpellID)
end
-- The cooldown manager learns from this event that the key texts of the
-- suite bars changed.
local BINDINGS_EVENT,triggered="MSUFSuite.ActionBars.BindingsChanged",{}
EventRegistry={
    RegisterCallback=function() end,UnregisterCallback=function() end,
    TriggerEvent=function(_,event) triggered[event]=(triggered[event] or 0)+1 end,
}
local tooltip={}
GameTooltip={SetOwner=function(self,owner) self.owner=owner end,GetOwner=function(self) return self.owner end,
    SetAction=function(_,slot) tooltip.slot=slot end,Hide=function(self) self.owner=nil;tooltip.slot=nil end}
GameTooltip_SetDefaultAnchor=function(tip,owner) tip.owner=owner end
local bindings,overrides,overrideWrites,overrideClears={},{},0,0
local bindingReads=0
GetBindingKey=function(command)
    bindingReads=bindingReads+1
    local keys=bindings[command]
    if keys then return unpack(keys) end
end
GetBindingText=function(key) return key end
SetOverrideBindingClick=function(owner,priority,key,name,button)
    assert(not combat,"override binding in combat")
    assert(priority==false and button=="Keybind")
    overrides[key]=name;overrideWrites=overrideWrites+1
end
ClearOverrideBindings=function()
    assert(not combat,"override clear in combat")
    for key in pairs(overrides) do overrides[key]=nil end
    overrideClears=overrideClears+1
end
local cvars={ActionButtonUseKeyDown=true,lockActionBars=true}
GetCVarBool=function(name) return cvars[name]==true end
local toggles={true,false,true,true,false,false,false}
GetActionBarToggles=function() return unpack(toggles) end
local forms=0
GetNumShapeshiftForms=function() return forms end
local petActions={}
GetPetActionInfo=function(i) return petActions[i] end
hooksecurefunc=function(target,method,hook)
    if type(target)=="table" then
        local original=assert(target[method],"hook method "..tostring(method))
        target[method]=function(self,...) original(self,...);hook(self,...) end
        return
    end
    local name=target
    hook=method
    local original=assert(_G[name],"hook target "..name)
    _G[name]=function(...) original(...);hook(...) end
end
local native={}
ActionButtonDown=function(id) native[#native+1]="down"..id end
ActionButtonUp=function(id) native[#native+1]="up"..id end
MultiActionButtonDown=function(bar,id) native[#native+1]=bar..id end
MultiActionButtonUp=function() end
ActionButton_UpdateCooldownNumberHidden=function(button)
    button.cooldown:SetHideCountdownNumbers(false)
end
local editElements={}
MSUF_EditModeAPI={RegisterElement=function(owner,element) editElements[element.id]=element;return true end,
    RefreshOwner=function() end,UnregisterOwner=function() end,RegisterSessionListener=function() end,IsActive=function() return false end}
C_AddOns={IsAddOnLoaded=function() return false end,LoadAddOn=function() end,
    DoesAddOnExist=function(name) return type(name)=="string" and name:match("^MSUF_Suite")~=nil end,
    GetAddOnEnableState=function() return 2 end}
UnitGUID=function() return "Player-Test" end
UnitName=function() return "Tester" end
GetRealmName=function() return "Realm" end

------------------------------------------------------------------ Blizzard frames
local function Buttons(prefix,parent,count,small)
    parent.actionButtons=parent.actionButtons or {}
    for i=1,count do
        local button=NewFrame("CheckButton",prefix..i,parent,"SecureActionButtonTemplate")
        button.nativeID=i
        button.bar=parent
        button.index=i
        parent.actionButtons[i]=button
        ActionRegions(button)
        button.SpellActivationAlert=NewFrame("Frame",nil,button)
        button.UpdateUsable=function(self,action,usable,noMana)
            if usable==nil then usable,noMana=C_ActionBar.IsUsableAction(self.attrs.action) end
            self.icon:SetVertexColor(usable and 1 or noMana and .5 or .4,usable and 1 or noMana and .5 or .4,usable and 1 or noMana and 1 or .4)
        end
        button.UpdateState=function(self)
            self:SetChecked(C_ActionBar.IsCurrentAction(self.attrs.action))
        end
        button:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    end
end
local MainBar=NewFrame("Frame","MainActionBar",UIParent)
MainBar.implicit=true
MainBar.attrs.actionpage=1
MainBar.cx,MainBar.cy,MainBar.numRows,MainBar.numButtonsShowable,MainBar.isHorizontal,MainBar.buttonPadding=512,40,1,12,true,2
-- Blizzard_ActionBar/Mainline/MainActionBar.xml (Retail and Forever): the page
-- buttons live on the ActionBarPageNumber child; their OnClick pages the bar.
local pageClicks={}
do
    local pager=NewFrame("Frame",nil,MainBar)
    pager.UpButton=NewFrame("Button",nil,pager)
    pager.DownButton=NewFrame("Button",nil,pager)
    pager.UpButton.scripts.OnClick=function() pageClicks[#pageClicks+1]="up" end
    pager.DownButton.scripts.OnClick=function() pageClicks[#pageClicks+1]="down" end
    MainBar.ActionBarPageNumber=pager
end
MainBar.Selection=NewFrame("Frame",nil,MainBar)
MainBar:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
Buttons("ActionButton",MainBar,12)
local multibars={"MultiBarBottomLeft","MultiBarBottomRight","MultiBarRight","MultiBarLeft","MultiBar5","MultiBar6","MultiBar7"}
for index,name in ipairs(multibars) do
    local bar=NewFrame("Frame",name,UIParent)
    bar.implicit=true
    bar:RegisterEvent("ACTIONBAR_SHOWGRID")
    bar.cx,bar.cy,bar.numRows,bar.numButtonsShowable,bar.isHorizontal,bar.buttonPadding=300+index,80,1,12,true,2
    Buttons(name.."Button",bar,12)
end
MultiBarBottomLeft.visibility="InCombat"
for _,name in ipairs(multibars) do
    local bar=_G[name]
    function bar:UpdateShownButtons()
        secure=secure+1
        for _,button in ipairs(self.actionButtons) do
            local grid=(button.attrs.showgrid or 0)>0
            button:SetShown(button.index<=self.numButtonsShowable and not button.attrs.statehidden
                and (grid or actions[button.attrs.action]~=nil))
        end
        secure=secure-1
    end
end
MultiBarRight.isHorizontal,MultiBarRight.numRows,MultiBarRight.numButtonsShowable=false,2,10
for _,name in ipairs({"StanceBar","PetActionBar"}) do
    local bar=NewFrame("Frame",name,UIParent)
    bar.implicit=true
    bar:RegisterEvent("PET_BAR_UPDATE")
end
PetActionBar.shown=false
Buttons("StanceButton",StanceBar,10,true)
Buttons("PetActionButton",PetActionBar,10,true)
local leave=NewFrame("Button","MainMenuBarVehicleLeaveButton",MainBar)
leave.shown=false
local quick=NewFrame("Frame","QuickKeybindFrame",UIParent,"SecureFrameTemplate")
quick.shown=false
quick.scripts.OnShow=function() quick.shownSecurely=secure>0 end
SpellFlyout=NewFrame("Frame","SpellFlyout",UIParent)
SpellFlyout.shown=false

------------------------------------------------------------------ load the suite
local Suite={}
MSUFSuite=Suite
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",SupportsEvent=function() return true end}}
SlashCmdList={}
MSUF_PixelLayoutRegion=function(frame) return frame end
for _,file in ipairs({"Platform","Database","SuiteCatalog","Catalog/ActionBars","Bindings",
    "Catalog/DataTexts","NameplateStyle","SuiteMigrations","Suite"}) do
    assert(loadfile(root.."/MSUF_Suite/Core/"..file..".lua"))("MSUF_Suite",Suite)
end
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil));Suite.Suite.Normalize(Suite.DB)
local private={}
local before=created
for _,file in ipairs({"Surfaces","Runtime","EditMode"}) do
    assert(loadfile(root.."/MSUF_Suite_Modules/"..file..".lua"))("MSUF_Suite_Modules",private)
end
local RUNTIME={"Bootstrap","Bars","Decorations","Blizzard","Paging","Visibility",
    "Bindings","Style","Paint","NativeButtons","Flush","Events","Controller"}
for _,file in ipairs(RUNTIME) do
    assert(loadfile(root.."/MSUF_Suite_ActionBars/"..file..".lua"))("MSUF_Suite_ActionBars",private)
end
-- The TOC lists the runtime in this order. The paint passes split along
-- their seams: button painting (Paint), Blizzard's reused buttons
-- (NativeButtons), the dirty mask and flush (Flush), the event map
-- (Events); each resolves what it uses from the earlier ones at load.
do
    local handle=assert(io.open(root.."/MSUF_Suite_ActionBars/MSUF_Suite_ActionBars_Mainline.toc","rb"))
    local toc=handle:read("*a"):gsub("\r","")
    handle:close()
    local listed={}
    for line in toc:gmatch("[^\n]+") do
        if line:sub(1,1)~="#" and line:match("%.lua$") then listed[#listed+1]=line:gsub("%.lua$","") end
    end
    assert(#listed==#RUNTIME,"the TOC lists "..#listed.." runtime files")
    for i=1,#RUNTIME do assert(listed[i]==RUNTIME[i],"TOC order: expected "..RUNTIME[i].." at "..i) end
end
assert(created==before,"loading the runtime created frames")
-- Globals both clients always have (Blizzard's Retail and Forever UI source)
-- are called, never probed; the harness above stubs them.
for _,file in ipairs({"Bars","Blizzard","Visibility","Bindings","Style","Paint","NativeButtons","Flush","Events",
    "Controller"}) do
    local handle=assert(io.open(root.."/MSUF_Suite_ActionBars/"..file..".lua","rb"))
    local text=handle:read("*a")
    handle:close()
    for _,api in ipairs({"GetBindingKey","GetActionInfo","SetOverrideBindingClick","ClearOverrideBindings","GetCVarBool",
        "hooksecurefunc","ActionButtonDown","ActionButtonUp","MultiActionButtonDown","MultiActionButtonUp",
        "GetFlyoutInfo","GetFlyoutSlotInfo","GetNumShapeshiftForms","SecureHandlerExecute","SecureHandlerSetFrameRef",
        "GetPetActionInfo","GetCursorInfo","UnitClass","GetTime","C_Timer"}) do
        assert(not text:find("type("..api..")",1,true),file..".lua probes "..api)
    end
    assert(not text:find("not C_Timer",1,true),file..".lua probes C_Timer")
    for _,probe in ipairs({"if C_Timer","_G.C_Timer","_G.EventRegistry","_G.C_ActionBar","_G.C_LossOfControl",
        "_G.SpellFlyout","_G.ActionButtonSpellAlertManager","type(_G.ActionButtonSpellAlertMixin)",
        "type(ActionButton_UpdateCooldownNumberHidden)","if GameTooltip_SetDefaultAnchor",".UpdateShownButtons) ==",
        ".UpdateUsable) ==",".UpdateState) =="}) do
        assert(not text:find(probe,1,true),file..".lua probes: "..probe)
    end
    -- The runtime files load before any of their functions runs: modules of
    -- this addon are used, never probed.
    for _,probe in ipairs({"AB%.(%u%w*) and AB%.%1","if AB%.%u%w* then","and AB%.%u%w* then AB%."}) do
        assert(not text:find(probe),file..".lua probes one of its own modules: "..probe)
    end
    if file=="Controller" then
        local decorations=assert(io.open(root.."/MSUF_Suite_ActionBars/Decorations.lua","rb"))
        local body=decorations:read("*a"):match("function AB%.StyleDecoration%(.-\nend\n")
        decorations:close()
        assert(body and not body:find("pairs({",1,true),"StyleDecoration builds a table per button")
    end
    -- The flush runs its units through the suite's shared runner (Runtime.lua).
    if file=="Flush" then assert(text:find("S.NewUnitRunner()",1,true),"the flush lost the shared unit runner") end
end
local S,AB=Suite.Suite,private.ActionBars
-- The original full-feature contract exercises the suite-painted fallback.
-- The Retail native-reuse path has a separate branch below.
local nativeReuse=arg[2]=="native"
AB.nativeReuse=nativeReuse
Suite.Client.isForever=true
assert(S.catalog.actionbars.available==nil and S.Availability("actionbars"),
    "Forever availability must not run the broken compiler or hard-block the module")
Suite.Client.isForever=false
local M=AB.M
local c=S.Config("actionbars")
assert(Suite.Client.hasSecrets,"harness must model a secret client")
local function Event(name,...)
    local frame=M.context.frame
    assert(frame.events[name],name.." is not registered")
    frame.scripts.OnEvent(frame,name,...)
end
local function Bar(index) return assert(AB.bars[index],"bar "..index) end
local function Button(index,i) return assert(Bar(index).buttons[i],"button "..index..":"..i) end

-- Actions: bar 1 page 1 and page 2, one spell on bar 2 (slot 61), a flyout
-- on bar 3 (slot 49), an empower spell on bar 4 (slot 25).
for slot=1,12 do actions[slot]={kind="spell",id=1000+slot,texture=100+slot} end
for slot=13,18 do actions[slot]={kind="spell",id=2000+slot,texture=200+slot} end
actions[61]={kind="spell",id=61,texture=61,count="3"}
actions[49]={kind="flyout",id=7,texture=49}
actions[25]={kind="spell",id=25,texture=25}
pressHold[25]=true
bindings.ACTIONBUTTON1={"1"};bindings.ACTIONBUTTON2={"2"}
bindings.MULTIACTIONBAR1BUTTON1={"SHIFT-1"};bindings.MULTIACTIONBAR2BUTTON1={"F"}
bindings.MSUFSUITE_BAR9_BUTTON1={"CTRL-BUTTON4","MOUSEWHEELUP"}
bindings.SHAPESHIFTBUTTON1={"Z"};bindings.BONUSACTIONBUTTON2={"ALT-3"}
forms=2
petActions[1]="Attack"

------------------------------------------------------------------ enable
S.started=true
local builtBefore=created
c.enabled = false
assert(S.Set("actionbars","enabled",true))
assert(M.active and S.states.actionbars.active and S.Status("actionbars")=="Active")
RunTimers()
local frames=created-builtBefore
assert(c.imported==true,"first enable must import Blizzard's layout")
assert((triggered[BINDINGS_EVENT] or 0)>0,"starting the bars did not tell the cooldown manager its key texts changed")
assert(c.pickupModifier == 1 and pickupWrites == 0,
    "the default must preserve Blizzard's pickup modifier")
assert(S.Set("actionbars", "pickupModifier", 3) and pickupModifier == "CTRL" and pickupWrites == 1,
    "an explicit Ctrl choice must update Blizzard's pickup action")
M:Refresh()
assert(pickupWrites == 1, "unrelated refreshes must not rewrite the pickup modifier")
assert(S.Set("actionbars", "pickupModifier", 1))
pickupModifier = "ALT"
M:Refresh()
assert(pickupModifier == "ALT" and pickupWrites == 1,
    "returning to Blizzard's setting must stop overriding external changes")

-- Zero fade must fully hide stack text, including native child overlays,
-- while the header keeps its nonzero Forever hover hit target. Hover still
-- reveals the bar in combat and count repaints must not undo the fade.
Suite.Client.isForever=true
for _,index in ipairs({1,2,9}) do
    local bar,button=Bar(index),Button(index,1).button
    assert(bar.header.alpha==.01 and EffectiveAlpha(button.Count)==0,
        "zero-opacity bar left stack text visible: "..index)
    combat=true
    Fire(button,"OnEnter",true)
    assert(EffectiveAlpha(button.Count)==1,"hover did not restore stack text")
    Fire(button,"OnLeave",true)
    button.Count:SetAlpha(1)
    assert(EffectiveAlpha(button.Count)==0,"count repaint escaped the bar fade")
    combat=false
end
Suite.Client.isForever=false
-- 0% and 1% share the header alpha, but only 0% hides the text overlay.
assert(S.Set("actionbars","bar2FadeAlpha",1))
assert(Bar(2).header.alpha==.01 and EffectiveAlpha(Button(2,1).button.Count)==.01,
    "nonzero fade did not restore stack text at the configured opacity")
assert(S.Set("actionbars","bar2FadeAlpha",0))
assert(EffectiveAlpha(Button(2,1).button.Count)==0,"zero fade retained the text overlay")
assert(S.Set("actionbars","bar2ClickThrough",true))
assert(EffectiveAlpha(Button(2,1).button.Count)==0 and not Bar(2).header.mouse and Bar(2).header.motion,
    "click-through changed zero fade or disabled hover motion")
assert(S.Set("actionbars","bar2ClickThrough",false))

if nativeReuse then
    assert(not Bar(1).native and not Bar(9).native and not Bar(10).native,
        "custom paging and extra bars lost their suite buttons")
    for index=2,8 do
        local bar=Bar(index)
        assert(bar.native,"Retail bar did not choose native buttons: "..index)
        assert(_G[AB.NATIVE_BARS[index]].numButtonsShowable==(index==4 and 10 or 12),
            "the suite wrote Blizzard's icon count (a tainted value its secure pass reads)")
        for i=1,12 do
            local rec=Button(index,i)
            local button=_G[AB.NATIVE_BUTTONS[index]..i]
            assert(rec.button==button and rec.native and button.parent==bar.header and button.securelyReparented,
                "native button not adopted securely: "..index..":"..i)
            assert(_G[AB.NATIVE_BARS[index]].actionButtons[i]==button and button:GetID()==i
                and bar.header.attrs.actionpage==math.floor((AB.FIRST_SLOT[index]-1)/12)+1,
                "native command lookup or fixed page diverged")
            -- An insecure write to a field Blizzard's secure code reads would
            -- taint UpdateAction, proc alerts and tooltips.
            assert(button.bar==_G[AB.NATIVE_BARS[index]],"a reused button lost Blizzard's bar field")
            assert(button.attrs.action==AB.FIRST_SLOT[index]+i-1 and button.attrs.index==i,
                "native button lost its action slot")
            assert(not button.strippedEvents,"native painter lost its events")
            assert(math.floor((button.attrs.showgrid or 0)/8)%2==1,
                "native showgrid guard missing")
            -- Blizzard's flyout code takes the direction from the attribute
            -- and never asks the hidden bar.
            assert(button.attrs.flyoutDirection~=nil,"a reused button has no flyoutDirection attribute")
        end
    end
    assert(Button(4,11).button.attrs.statehidden and not Button(4,11).button.shown,
        "suite count must cap native bar 4: "..tostring(c.bar4Buttons).."/"..tostring(Bar(4).count).."/"..tostring(Button(4,11).button.attrs.statehidden).."/"..tostring(Button(4,11).button.shown))
    c.bar2ShowEmpty=false;M:Refresh()
    assert(Button(2,2).button.attrs.statehidden and not Button(2,2).button.shown,
        "suite must hide empty native slots")
    c.bar4Buttons=12;M:Refresh()
    assert(Button(4,11).button.shown and not Button(4,11).button.attrs.statehidden,
        "suite must reveal buttons beyond the imported Blizzard count")
    -- Blizzard's hidden bar still runs its own plan (spellbook grids, Edit
    -- Mode icon counts) and caps at its count; the suite's plan follows.
    MultiBarRight:UpdateShownButtons()
    assert(Button(4,11).button.shown and Button(4,12).button.shown,
        "Blizzard's icon count capped suite buttons out of combat")
    -- In combat Blizzard's plan still runs (UpdateAction calls
    -- self.bar:UpdateShownButtons); the restricted OnHide wrap answers at
    -- once, and a button the suite hid stays hidden.
    combat=true
    MultiBarRight:UpdateShownButtons()
    assert(Button(4,11).button.shown and Button(4,12).button.shown,"Blizzard's icon count capped suite buttons in combat")
    MultiBarBottomLeft:UpdateShownButtons()
    assert(not Button(2,2).button.shown and Button(2,2).button.attrs.statehidden,"Blizzard's plan showed a slot the suite hid")
    combat=false
    Event("PLAYER_REGEN_ENABLED");RunTimers()
    assert(Button(4,11).button.shown,"the suite's plan did not hold after combat")
    -- Blizzard plans on every UpdateAction: a slot burst out of combat runs
    -- the suite's plan once per bar on the next flush, never per call; in
    -- combat the bar waits for combat end.
    local execute,grids=SecureHandlerExecute,{}
    local function GridRuns()
        local total=0
        for _,count in pairs(grids) do total=total+count end
        return total
    end
    SecureHandlerExecute=function(frame,body)
        if body==AB.SNIPPET.GRID then grids[frame]=(grids[frame] or 0)+1 end
        return execute(frame,body)
    end
    for _=1,12 do MultiBarRight:UpdateShownButtons();MultiBarBottomLeft:UpdateShownButtons() end
    assert(GridRuns()==0 and Button(4,11).button.shown and Button(4,12).button.shown,
        "Blizzard's plan ran the suite's plan synchronously or capped suite buttons before the flush")
    RunTimers()
    assert(grids[Bar(4).header]==1 and grids[Bar(2).header]==1 and GridRuns()==2,
        "a plan burst did not run the suite's plan exactly once per bar")
    grids={}
    combat=true
    for _=1,12 do MultiBarRight:UpdateShownButtons() end
    RunTimers()
    assert(GridRuns()==0 and Button(4,11).button.shown,"the suite's plan ran in combat")
    combat=false
    Event("PLAYER_REGEN_ENABLED");RunTimers()
    assert(grids[Bar(4).header]==1,"the plan parked in combat did not run once after combat")
    SecureHandlerExecute=execute
    c.bar4Buttons=10;M:Refresh()
    c.bar2ShowEmpty=true;M:Refresh()
    assert(Button(2,2).button.shown and not Button(2,2).button.attrs.statehidden,
        "suite show-empty option was lost")
    c.bar2ShowEmpty=false;M:Refresh()
    c.bar2Visibility=6;M:Refresh()
    assert(not Bar(2).header:IsShown(),"suite visibility did not hide the native bar")
    c.bar2Visibility=1;M:Refresh()
    assert(Bar(2).header:IsShown(),"suite visibility did not reveal the native bar")
    c.bar2Visibility=2;M:Refresh()
    assert(not Bar(2).header:IsShown(),"combat-only native bar was shown out of combat")
    conditions.combat=true;combat=true;Drivers()
    assert(Bar(2).header:IsShown() and Button(2,1).button:IsVisible(),
        "suite driver did not reveal native buttons in combat")
    conditions.combat=nil;Drivers();combat=false
    assert(not Bar(2).header:IsShown(),"suite driver did not hide native buttons after combat")
    c.bar2Visibility=1;M:Refresh()
    ranges[61]=false
    Event("ACTION_RANGE_CHECK_UPDATE",61,false,true)
    assert(Button(2,1).button.icon.vertex[1]==AB.style.rr,"native range color missing")
    local usableBefore=calls.usable
    Button(2,1).button:UpdateUsable()
    assert(calls.usable==usableBefore+1 and Button(2,1).button.icon.vertex[1]==AB.style.rr,
        "native usable hook either duplicated the API call or lost the range tint")
    ranges[61]=true
    Event("ACTION_RANGE_CHECK_UPDATE",61,true,true)
    assert(Button(2,1).button.icon.vertex[1]==1,"native range reset did not restore usability")
    c.bar2Visibility=2;M:Refresh()
    ranges[61]=false
    conditions.combat=true;combat=true;Drivers()
    assert(Button(2,1).button.icon.vertex[1]==AB.style.rr,
        "native range color was not reacquired when the bar appeared in combat")
    conditions.combat=nil;Drivers();combat=false
    c.bar2Visibility=1;c.rangeColoring=false;M:Refresh()
    assert(Button(2,1).button.icon.vertex[1]==1,
        "disabling suite range color left a native button tinted")
    c.rangeColoring=true;M:Refresh()
    c.castHighlight=false;M:Refresh()
    actions[61].current=true
    Button(2,1).button:UpdateState()
    assert(not Button(2,1).button.checked,"suite cast-highlight setting was ignored")
    c.castHighlight=true;M:Refresh()
    Button(2,1).button:UpdateState()
    assert(Button(2,1).button.checked,"native cast-highlight state was not restored")
    c.procGlow=2;overlayed[61]=true;M:Refresh()
    assert(Button(2,1).glow and Button(2,1).glowEdges and Button(2,1).button.SpellActivationAlert.alpha==0,
        "pixel proc glow must replace Blizzard's glow")
    c.procGlow=3;M:Refresh()
    assert(not Button(2,1).glow and Button(2,1).button.SpellActivationAlert.alpha==0,
        "none proc glow must hide native alert")
    c.procGlow=1;M:Refresh()
    assert(Button(2,1).button.SpellActivationAlert.alpha==1,
        "Blizzard proc glow must be restored")
    -- Blizzard creates a reused button's alert on its first proc, after the
    -- style pass: the Pixel border and None glows keep it invisible.
    local late=Button(2,3).button
    for mode=2,3 do
        c.procGlow=mode;M:Refresh()
        late.SpellActivationAlert=nil
        ActionButtonSpellAlertManager:ShowAlert(late)
        assert(late.SpellActivationAlert and late.SpellActivationAlert.alpha==0,
            "Blizzard's spell alert showed on a reused button with glow mode "..mode)
    end
    c.procGlow=1;M:Refresh()
    late.SpellActivationAlert=nil
    ActionButtonSpellAlertManager:ShowAlert(late)
    assert(late.SpellActivationAlert.alpha==1,"the Blizzard glow mode hid Blizzard's spell alert")
    -- The assisted-combat rotation action's alert sits on the rotation frame
    -- and follows the same rule, whether it already shows or appears later.
    local rotation=Button(2,4).button
    assistedAction[rotation]=true
    ActionButtonSpellAlertManager:ShowAlert(rotation)
    local rotationAlert=rotation.AssistedCombatRotationFrame.SpellActivationAlert
    assert(rotationAlert.alpha==1,"the Blizzard glow mode hid the rotation frame's spell alert")
    c.procGlow=2;M:Refresh()
    assert(rotationAlert.alpha==0,"the Pixel border glow left the rotation frame's spell alert showing")
    for mode=2,3 do
        c.procGlow=mode;M:Refresh()
        rotation.AssistedCombatRotationFrame.SpellActivationAlert=nil
        ActionButtonSpellAlertManager:ShowAlert(rotation)
        assert(rotation.AssistedCombatRotationFrame.SpellActivationAlert.alpha==0,
            "the rotation frame's spell alert showed with glow mode "..mode)
    end
    c.procGlow=1;M:Refresh()
    assert(rotation.AssistedCombatRotationFrame.SpellActivationAlert.alpha==1,
        "the Blizzard glow mode did not restore the rotation frame's spell alert")
    assistedAction[rotation]=nil
    -- Post-hooks inside Blizzard's call chains run isolated: an error is
    -- reported and never reaches the alert manager's caller.
    c.procGlow=2;M:Refresh()
    local alert,errors=late.SpellActivationAlert,#dispatch.errors
    alert.SetAlpha=function() alert.SetAlpha=nil;error("alert hook failed") end
    dispatch.expect=true
    ActionButtonSpellAlertManager:ShowAlert(late)
    dispatch.expect=false
    assert(#dispatch.errors==errors+1 and dispatch.errors[errors+1]:find("alert hook failed",1,true),
        "a raising alert hook reached Blizzard's alert manager")
    c.procGlow=1;M:Refresh()
    -- Blizzard highlights its own (reused) buttons. Under a Suite style its
    -- highlight frame stays invisible, also one Blizzard creates after the
    -- style pass, and the ring follows Blizzard's decision.
    do
        local nativeRec=Button(2,1)
        assert(c.assistStyle==2,"the recommendation default does not cover every bar")
        Recommend(61)
        AssistedCombatManager:OnActionButtonActionChanged(nativeRec.button,61)
        local frame=nativeRec.button.AssistedCombatHighlightFrame
        assert(frame and frame.shown and frame.alpha==0 and nativeRec.assist and nativeRec.assist.shown,
            "a Blizzard highlight frame created between recommendations showed instead of the ring")
        Recommend(nil)
        assert(not nativeRec.assist.shown,"the ring outlived Blizzard's recommendation")
        assert(S.Set("actionbars","assistStyle",1) and frame.alpha==1,"the Blizzard style did not restore Blizzard's highlight")
        Recommend(61)
        assert(frame.shown and frame.alpha==1 and not nativeRec.assist.shown,"the Blizzard style drew the Suite ring")
        Recommend(nil)
        AssistedCombatManager.candidates[nativeRec.button]=nil
        assert(S.Set("actionbars","assistStyle",2))
    end
    c.hideEmptyCharges=true;actions[61].charges={maxCharges=2,currentCharges=0};M:Refresh()
    assert(Button(2,1).button.Count.alpha==0,"native empty-charge count did not hide")
    local chargeCalls=calls.charges
    actions[61].charges.currentCharges=1;Event("SPELL_UPDATE_CHARGES");RunTimers()
    assert(Button(2,1).button.Count.alpha==1,"native charge count did not return: "..tostring(Button(2,1).button.Count.alpha).."/"..tostring(Button(2,1).button:IsVisible()).."/"..tostring(c.hideEmptyCharges).."/"..tostring(calls.charges-chargeCalls))
    c.cooldownNumbers=false;M:Refresh()
    ActionButton_UpdateCooldownNumberHidden(Button(2,1).button)
    assert(Button(2,1).button.cooldown.hideNumbers,
        "Blizzard CVAR update overrode suite cooldown-number setting")
    c.cooldownNumbers=true;M:Refresh()
    actions[61].cooldown={isActive=true,duration=8}
    actions[61].remaining=8
    c.desaturateCooldown=true;c.cooldownAlpha=50;M:Refresh()
    local cooldownCalls=calls.cooldown
    AB.RefreshNative()
    assert(calls.cooldown==cooldownCalls,"native cooldown feedback allocated cooldown info tables")
    assert(Button(2,1).button.icon.desaturation==1 and Button(2,1).button.alpha==.5,
        "native duration feedback lost suite cooldown effects")
    actions[61].remaining=0;AB.RefreshNative()
    assert(Button(2,1).button.icon.desaturation==0 and Button(2,1).button.alpha==1,
        "native duration feedback did not clear when ready")
    assert(Button(1,1).button.name=="MSUFSuiteBar1Button1" and Button(9,1).button.name=="MSUFSuiteBar9Button1")
    assert(not AB.ClickRouted(Button(3,1)),"adopted flyout still routed to a second button")
    assert(overrides["CTRL-BUTTON4"]=="MSUFSuiteBar9Button1" and not overrides.F,
        "native commands and extra-bar routing diverged")
    RunTimers()
    local painted=calls.texture
    AB.MarkBar(Bar(2));RunTimers()
    assert(calls.texture==painted,"suite repainted a native button")
    now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(calls.texture==painted,"native cooldown event repainted textures through suite")
    print("Action bars native reuse: Retail bars 2-8 adopted, suite painter skipped, custom bars retained, routing passed")
    return
end

-- Disposal: Blizzard bars neutralised, never destroyed or Hide()n.
local hidden=AB.hidden
assert(hidden and hidden.explicit and not hidden.shown,"hidden parent must be protected and hidden")
for _,name in ipairs(multibars) do
    local bar=_G[name]
    assert(bar.parent==hidden and bar.securelyReparented,name.." must move securely under the hidden parent")
    assert(not bar.hideCalls and bar.strippedEvents and not next(bar.events),name.." must keep its shown state and lose its events")
end
for _,name in ipairs({"StanceBar","PetActionBar"}) do
    local bar=_G[name]
    assert(bar.parent==hidden and not bar.hideCalls and bar.events.PET_BAR_UPDATE,name.." keeps its events so Blizzard paints adopted buttons")
end
assert(MainBar.parent==UIParent and MainBar.alpha==0 and MainBar.mouse==false and not MainBar.hideCalls,"main bar stays in its chain")
assert(MainBar.events.ACTIONBAR_PAGE_CHANGED,"main bar keeps its events for vehicle transitions")
assert(MainBar.ActionBarPageNumber.UpButton.mouse==false and MainBar.Selection.mouse==false)
assert(leave.parent==UIParent,"vehicle leave button leaves the invisible main bar")
for _,prefix in ipairs({"ActionButton","MultiBarBottomLeftButton","MultiBar7Button"}) do
    local twin=_G[prefix.."5"]
    assert(twin.attrs.statehidden==true and not twin.shown and twin.strippedEvents,"twin "..prefix.." hidden quietly")
    assert(twin.parent~=hidden and not twin.reparented,"twins stay under their bars for native commands")
end
MainBar.alpha=1;MainBar:Hide();MainBar:Show()
assert(MainBar.alpha==0,"OnShow post-hook re-applies alpha")

-- Import: positions and grids only; every Suite bar keeps mouseover defaults.
for index=1,12 do
    assert(c["bar"..index.."Visibility"]==4,"import replaced mouseover default: "..index)
end
for index=1,10 do
    local header=Bar(index).header
    assert(header.mouse == true and header.motion == true and header.alpha == 0.01,
        "Forever mouseover header is not hittable while faded: "..index)
end
assert(c.bar1Point==5 and c.bar1X==0 and c.bar1Y==-344,"bar 1 imported as a centre offset")
assert(c.bar4Vertical and c.bar4Buttons==10 and c.bar4Rows==5,"vertical Blizzard bars count columns")

-- Owned frames: 10 bars x 12 secure buttons with wraps and explicit slots.
for index=1,10 do
    local bar=Bar(index)
    assert(bar.header.explicit and bar.header.name=="MSUFSuiteBar"..index)
    for i=1,12 do
        local rec=Button(index,i)
        local button=rec.button
        assert(button.name=="MSUFSuiteBar"..index.."Button"..i and button.explicit and button.wraps==3)
        assert(button.attrs.type=="action" and button.attrs.typerelease=="actionrelease" and button.attrs.index==i)
        assert(button.clickTypes[1]=="AnyDown" and button.clickTypes[2]=="AnyUp")
        if index>1 then assert(button.attrs.action==AB.FIRST_SLOT[index]+i-1,"explicit slot on bar "..index) end
    end
end
assert(Bar(1).header.attrs.actionpage==1 and Button(1,5).button.attrs.action==5)
assert(MainBar.attrs.actionpage==1 and Bar(1).header.attrs.mirror==true)
-- Empty slots follow showEmpty: bar 2 hides empty buttons only when set so.
assert(Button(2,1).button.shown and Button(2,2).button.shown,"bar 2 shows empty slots by default")
assert(Button(9,1).button.shown,"bar 9 shows empty slots")
-- Press-and-hold follows the spell in the restricted environment.
assert(Button(4,1).button.attrs.pressAndHoldAction==true and Button(4,2).button.attrs.pressAndHoldAction==nil)
assert(Button(2,1).button.attrs.pressAndHoldAction==false)

-- Stance and pet: Blizzard's buttons move into the suite headers.
local stance,pet=Bar(11),Bar(12)
assert(StanceButton1.parent==stance.header and StanceButton1.securelyReparented and PetActionButton1.parent==pet.header)
assert(StanceButton1.shown and StanceButton2.shown and not StanceButton3.shown and StanceButton3.attrs.statehidden==true,"stance caps at forms")
assert(PetActionButton1.shown and not PetActionButton2.shown and PetActionButton2.attrs.statehidden==nil,"empty pet slot waits for Blizzard")
assert(stance.buttons[1].keyText.text=="Z" and pet.buttons[2].keyText.text=="A3" and StanceButton1.HotKey.alpha==0)

-- Paint: textures, counts, key text, flyout routing.
local b61=Button(2,1).button
assert(b61.icon.texture==61 and b61.Count.text=="3","mouseover bars keep their buttons painted")
assert(S.Set("actionbars","bar2Visibility",1));RunTimers()
assert(b61.icon.texture==61 and b61.Count.text=="3" and b61.HotKey.text=="S1")
assert(Button(1,1).button.HotKey.text=="1" and Button(9,1).button.HotKey.text=="CM4")
assert(overrides["CTRL-BUTTON4"]=="MSUFSuiteBar9Button1" and overrides.MOUSEWHEELUP=="MSUFSuiteBar9Button1","bar 9 keys click suite buttons")
assert(overrides.F=="MSUFSuiteBar3Button1","flyout slots route to the visible button")
assert(not overrides["1"] and not overrides["SHIFT-1"],"native commands stay native")
local writes=overrideWrites
AB.UpdateRouting();assert(overrideWrites==writes,"unchanged routing must be skipped")
-- Crafting quality badges: item actions only, on Retail and Forever alike
-- (ActionBarActionButtonMixin:UpdateProfessionQuality on both clients).
do
    local saved=actions[16]
    actions[16]={kind="item",id=5016,texture=516,quality="Professions-Icon-Quality-Tier3-Inv"}
    Suite.Client.isForever=true
    Event("ACTIONBAR_SLOT_CHANGED",16);RunTimers()
    local rec=Button(9,4)
    assert(rec.slot==16 and rec.quality and rec.quality.shown and rec.quality.atlas=="Professions-Icon-Quality-Tier3-Inv",
        "Forever lost the crafting quality badge")
    Suite.Client.isForever=false
    local reads=calls.quality
    Event("ACTIONBAR_SLOT_CHANGED",13);RunTimers()
    assert(calls.quality==reads,"a spell action asked for a crafting quality")
    actions[16]=saved
    Event("ACTIONBAR_SLOT_CHANGED",16);RunTimers()
    assert(not rec.quality.shown,"the crafting quality badge outlived its item")
end

------------------------------------------------------------------ paging
local actionsChanged=triggered["MSUFSuite.ActionBars.ActionsChanged"] or 0
conditions["bar:2"]=true;barPage=2;Drivers();RunTimers()
assert(Bar(1).header.attrs.actionpage==2 and Button(1,1).button.attrs.action==13 and Button(1,1).slot==13)
assert((triggered["MSUFSuite.ActionBars.ActionsChanged"] or 0)>actionsChanged,
    "a bar 1 page change did not tell the cooldown manager its glows moved")
assert(MainBar.attrs.actionpage==2,"page mirrored onto MainActionBar")
assert(Button(1,7).button.shown and Button(1,1).button.icon.texture==213)
conditions["bar:2"]=nil;barPage=1
combat=true
conditions.vehicleui=true;special.vehicle=true;Drivers()
assert(Bar(1).header.attrs.actionpage==12 and Button(1,1).button.attrs.action==133,"vehicle page resolves in combat")
assert(not Bar(1).header.shown and not Bar(2).header.shown and Bar(12).header.attrs["state-vis"],"vehicle UI hides bars 1-11")
conditions.vehicleui=nil;special.vehicle=nil
conditions["bonusbar:1"]=true;special.bonus=1;Drivers()
assert(Bar(1).header.attrs.actionpage==7 and MainBar.attrs.actionpage==7 and Bar(1).header.shown,"form page")
-- Key texts follow bindings only: a page flip repaints without reading them.
local pageKeyReads=bindingReads
RunDue()
assert(bindingReads==pageKeyReads and Button(1,1).slot==73,"a page flip re-read the key bindings")
combat=false
RunTimers()
-- Custom paging: modifiers and opt-outs stop the mirror and route bar 1 keys.
local bindingEvents=triggered[BINDINGS_EVENT] or 0
assert(S.SetMany("actionbars",{disableFormPaging=true}))
assert((triggered[BINDINGS_EVENT] or 0)>bindingEvents,"the forms opt-out did not tell the cooldown manager its key texts changed")
RunTimers()
assert(Bar(1).header.attrs.actionpage==1 and Bar(1).header.attrs.mirror==false,"forms opt-out keeps page 1")
assert(overrides["1"]=="MSUFSuiteBar1Button1" and overrides["2"]=="MSUFSuiteBar1Button2","opt-out routes bar 1 keys")
MainBar.attrs.actionpage=7
conditions["mod:shift"]=true
assert(S.SetMany("actionbars",{disableFormPaging=false,pagingModifiers=true,pageShift=3}))
RunTimers()
assert(Bar(1).header.attrs.actionpage==3 and MainBar.attrs.actionpage==7,"modifier page is suite-only")
conditions["mod:shift"]=nil;conditions["bonusbar:1"]=nil;special.bonus=nil
assert(S.SetMany("actionbars",{pagingModifiers=false}))
RunTimers()
assert(Bar(1).header.attrs.actionpage==1 and MainBar.attrs.actionpage==1 and not overrides["1"],"native routing restored")

------------------------------------------------------------------ combat start
-- QoL party effects may rotate the secure headers (S.VisitPartyActionBars).
-- PLAYER_REGEN_DISABLED arrives before the lockdown, the last moment to stop
-- them: no header turns while its buttons take clicks in combat.
do
    local before={}
    for index=1,12 do before[index]=Bar(index).header.animationStops or 0 end
    Event("PLAYER_REGEN_DISABLED")
    for index=1,10 do
        assert(Bar(index).header.animationStops==before[index]+1,"combat start left bar "..index.." animating")
    end
end

------------------------------------------------------------------ bindings in combat
combat=true
bindings.MSUFSUITE_BAR10_BUTTON3={"G"}
Event("UPDATE_BINDINGS")
assert(not overrides.G and AB.routingPending,"routing waits for combat to end")
assert(Button(10,3).button.HotKey.text=="G","key text is cosmetic and updates in combat")
combat=false
Event("PLAYER_REGEN_ENABLED")
assert(overrides.G=="MSUFSuiteBar10Button3")

------------------------------------------------------------------ click wraps and drags
Click(Button(2,1).button,"Keybind",true)
local last=clicks[#clicks]
assert(last.button=="LeftButton" and last.keydown==true,"routed keys follow ActionButtonUseKeyDown")
Click(Button(2,1).button,"LeftButton",true)
last=clicks[#clicks]
assert(last.button=="LeftButton" and last.keydown==false,"mouse clicks act on release")
Click(Button(2,1).button,"Keybind",false)
assert(Button(2,1).button.state=="NORMAL")
combat=true
c.bar5ShowEmpty=false
local empty=Button(5,4).button
modified.PICKUPACTION=true
Fire(Button(2,1).button,"OnDragStart","LeftButton")
assert(pickups[#pickups]==61,"secure pickup in combat")
assert(Bar(5).header.attrs.gridmask==4,"combat drags reveal empty slots on every bar")
cursor="spell"
Fire(Button(2,2).button,"OnReceiveDrag","LeftButton")
assert(pickups[#pickups]==62 and Bar(5).header.attrs.gridmask==0 and Button(2,2).button.shown,"drop on an empty slot ends the reveal")
modified.PICKUPACTION=nil;cursor=nil
combat=false
Fire(Button(2,2).button,"OnDragStart","LeftButton")
assert(pickups[#pickups]==62,"locked bars without the modifier do not pick up")

------------------------------------------------------------------ show empty and drag reveal (Lua side)
assert(S.Set("actionbars","bar5ShowEmpty",true))
assert(S.Set("actionbars","bar5ShowEmpty",false))
RunTimers()
assert(not empty.shown and empty.attrs.statehidden==true,"empty slot parked")
cursor="item"
Event("CURSOR_CHANGED");RunTimers()
assert(empty.shown and Bar(5).header.attrs.gridmask==2,"dragging reveals empty slots")
cursor=nil
Event("CURSOR_CHANGED");RunTimers()
assert(not empty.shown and Bar(5).header.attrs.gridmask==0)
assert(S.Set("actionbars","bar6Visibility",6))
assert(not Bar(6).header.shown)
cursor="spell";Event("ACTIONBAR_SHOWGRID");RunTimers()
assert(Bar(6).header.shown,"showOnDrag reveals Never bars while dragging")
cursor=nil;Event("ACTIONBAR_HIDEGRID");RunTimers()
assert(not Bar(6).header.shown)
combat=true;cursor="spell";Event("ACTIONBAR_SHOWGRID");RunTimers()
assert(not Bar(6).header.shown and AB.dragPending,"combat drags from outside wait")
combat=false;cursor=nil;Event("PLAYER_REGEN_ENABLED");RunTimers()
assert(not AB.dragPending)

------------------------------------------------------------------ visibility and mouseover
assert(S.SetMany("actionbars",{bar3Visibility=4,bar3Alpha=80,bar3FadeAlpha=10,bar4Visibility=4,bar4FadeAlpha=30}))
RunTimers()
local h3,h4=Bar(3).header,Bar(4).header
assert(h3.shown and h3.alpha==.1 and h4.alpha==.3 and h3.motion==true,"mouseover bars fade")
combat=true
Fire(Button(3,2).button,"OnEnter",true)
assert(h3.alpha==.8 and h4.alpha==.3,"hover reveals the hovered bar (alpha only, allowed in combat)")
assert(tooltip.slot==50 or tooltip.slot==nil)
h3.mouseOver=true
Fire(Button(3,2).button,"OnLeave",true)
assert(h3.alpha==.8,"moving inside the bar keeps it revealed")
h3.mouseOver=false
Fire(Button(3,2).button,"OnLeave",true)
assert(h3.alpha==.1)
combat=false
assert(S.Set("actionbars","mouseoverShowAll",true))
Fire(h3,"OnEnter",true)
assert(h3.alpha==.8 and h4.alpha==1,"show-all reveals every mouseover bar")
Fire(h3,"OnLeave",true)
assert(h4.alpha==.3)
assert(S.SetMany("actionbars",{bar3Visibility=2}))
assert(drivers[h3].vis=="[petbattle][vehicleui] hide; [combat] show; hide" and not h3.shown)
conditions.combat=true;combat=true;Drivers()
assert(h3.shown,"in-combat bar shows through its driver in combat")
conditions.combat=nil;Drivers();combat=false
assert(not h3.shown)
conditions.petbattle=true;Drivers()
assert(not Bar(1).header.shown and not pet.header.shown)
conditions.petbattle=nil;conditions.pet=true;Drivers()
assert(Bar(1).header.shown and pet.header.shown,"pet bar needs a pet")
-- Placement preview forces bars (except Never) visible at full alpha.
S.SetEditMode(true)
assert(h3.shown and not Bar(6).header.shown and Bar(5).header.attrs.gridmask==8 and h4.alpha==1)
S.SetEditMode(false)
assert(not h3.shown and Bar(5).header.attrs.gridmask==0)

------------------------------------------------------------------ dispatcher
-- Cooldown events as the client sends them (SpellBookDocumentation.lua,
-- ActionBarFrameDocumentation.lua): SPELL_UPDATE_COOLDOWN names a spell
-- (nil: every cooldown; startRecoveryCategory 133: a global cooldown
-- starts), ACTIONBAR_UPDATE_COOLDOWN names nothing. Spell actions without
-- charges follow their spell; every other button follows the action bar
-- event; a nil spell, a global cooldown and loss of control repaint all.
local function SpellCooldown(spell,base,recovery,category) Event("SPELL_UPDATE_COOLDOWN",spell,base,category,recovery) end
local function AllCooldowns() Event("SPELL_UPDATE_COOLDOWN") end
-- A spell's cooldown change: its spell event, then the action bar event.
local function SpellChanged(spell) SpellCooldown(spell);Event("ACTIONBAR_UPDATE_COOLDOWN") end
-- The cooldown and recharge duration reads of one slot while fn runs: the
-- painter's resolved getters, wrapped for the scenario only.
local function SlotReads(slot,fn)
    local api=AB.Painter.api
    local cooldown,charge,cooldowns,charges=api.CooldownDuration,api.ChargeDuration,0,0
    api.CooldownDuration=function(at,...) if at==slot then cooldowns=cooldowns+1 end return cooldown(at,...) end
    api.ChargeDuration=function(at,...) if at==slot then charges=charges+1 end return charge(at,...) end
    fn()
    api.CooldownDuration,api.ChargeDuration=cooldown,charge
    return cooldowns,charges
end
RunTimers()
local cooldownCalls=calls.duration
local infoCalls=calls.cooldown
for _=1,5 do AllCooldowns() end
RunTimers()
local walk=calls.duration-cooldownCalls
assert(walk>0,"cooldown walk ran")
assert(calls.cooldown==infoCalls,"default cooldown walk allocated info tables")
cooldownCalls=calls.duration
now=now+.2
assert(M.context.frame.events.SPELL_UPDATE_COOLDOWN,
    "spell actions lost their SPELL_UPDATE_COOLDOWN route")
assert(not M.context.frame.events.SPELL_UPDATE_USABLE,
    "Retail action bars retained the redundant global spell usability event")
AllCooldowns()
assert(#timers==1,"one flush per burst")
RunTimers()
assert(calls.duration-cooldownCalls==walk,"same-frame events share one walk")
calls.chargeBaseline=calls.charges
now=now+.2;AllCooldowns();RunTimers()
assert(calls.charges==calls.chargeBaseline,
    "uncharged actions allocated a charge info table on every cooldown walk")
do
    local rec=Button(2,1)
    local saved,setting=AB.Painter.api.Charges,c.hideEmptyCharges
    c.hideEmptyCharges=true
    local queries,result=0,nil
    AB.Painter.api.Charges=function() queries=queries+1;return result end
    AB.Painter.Paint(rec)
    assert(queries==1 and rec.button.Count.alpha==1,
        "a full paint repeated a nil charge query or hid the count")
    result=Secret();AB.Painter.Paint(rec)
    assert(queries==2 and rec.button.Count.alpha==1,
        "a full paint repeated or inspected a secret charge result")
    AB.Painter.api.Charges=saved;c.hideEmptyCharges=setting
    AB.Painter.Paint(rec)
end
-- Flush: one capped cooldown walk over every filled button.
now=now+1
Budget("action bars flush: a cooldown walk",Cost(function() AllCooldowns();RunTimers() end),2444)
cooldownCalls=calls.duration
local start=now
AllCooldowns();RunTimers()
assert(calls.duration-cooldownCalls==walk and now>=start+.1-1e-9,"storm cap delays the next walk")
RunTimers()
------------------------------------------------------------------ cooldown routes
-- The 2026-10-02 raid trace: 1,463 ACTIONBAR_UPDATE_COOLDOWN, 7,653 button
-- cooldown reads (681 KiB of duration objects) in 120 s, because every
-- payload-less event repainted every filled button. Native reads per event
-- are counted at the C_ActionBar stand-ins (calls.duration: cooldown
-- duration objects, calls.charges: charge info tables).
do
    -- An item and a macro next to the spell action on bar 2.
    actions[62]={kind="item",id=5062,texture=562}
    actions[63]={kind="macro",id=3,sub="spell",texture=563}
    Event("ACTIONBAR_SLOT_CHANGED",62);Event("ACTIONBAR_SLOT_CHANGED",63);now=now+1;RunTimers()
    local item,macro=Button(2,2).button,Button(2,3).button
    assert(item.icon.texture==562 and macro.icon.texture==563,"item and macro actions were not painted")
    -- The payload-less event: only the buttons the spell event cannot keep
    -- current (the item, the macro, the flyout), never the spell actions.
    local reads,charges=calls.duration,calls.charges
    now=now+1
    local used=Cost(function() Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers() end)
    local others=calls.duration-reads
    assert(others>=2 and others<walk and calls.charges==charges,
        "ACTIONBAR_UPDATE_COOLDOWN read "..others.." of "..walk.." buttons")
    -- Measured 2026-10-02 (wave 4) on this fixture (20 spell buttons, the
    -- item, the macro): before, this event ran the full walk, 2654
    -- instructions and 22 duration reads; now 1309 and 2 (1313 since the
    -- walk consumes the spell marks of the buttons it paints, 2026-10-03).
    Budget("action bars flush: an ACTIONBAR_UPDATE_COOLDOWN walk",used,1313)
    -- A named spell: its own button only (one native duration read), by
    -- the spell or by the base an override names.
    reads=calls.duration
    now=now+1
    used=Cost(function() SpellCooldown(1001);RunTimers() end)
    assert(calls.duration-reads==1,"a named spell cooldown read "..(calls.duration-reads).." buttons, not its own one")
    -- 552 instructions, 1 duration read (measured 2026-10-02); 564 since the
    -- secret base and category tests and the category fallback (2026-10-03).
    Budget("action bars flush: a named SPELL_UPDATE_COOLDOWN",used,564)
    reads=calls.duration
    SpellCooldown(91001,1001);RunTimers()
    assert(calls.duration-reads==1,"an override's cooldown did not reach its base spell's button")
    reads=calls.duration
    SpellCooldown(424242);RunTimers()
    assert(calls.duration==reads,"a spell on no button read cooldowns")
    -- A global cooldown start, a nil spell or an unreadable payload: every
    -- button, as before.
    -- A cooldown category (other spells and items can share it; no event
    -- for the peers is documented) and an unreadable base or category too.
    for _,send in ipairs({
        function() SpellCooldown(1002,nil,133) end,
        function() Event("SPELL_UPDATE_COOLDOWN",Secret(),1002,nil,0) end,
        function() SpellCooldown(1002,nil,Secret()) end,
        function() SpellCooldown(1002,nil,nil,77) end,
        function() SpellCooldown(1002,Secret()) end,
        function() SpellCooldown(1002,nil,nil,Secret()) end,
    }) do
        reads=calls.duration
        now=now+1;send();RunTimers()
        assert(calls.duration-reads==walk+2,"a global, unnamed, categorized or unreadable cooldown missed buttons")
    end
    -- Category 0 is no category: the named spell only.
    reads=calls.duration
    now=now+1;SpellCooldown(1002,nil,nil,0);RunTimers()
    assert(calls.duration-reads==1,"category 0 repainted every button")
    -- A shared category started by a spell on no button (an item, a racial's
    -- partner) still reaches a spell button that shares it.
    actions[3].cooldown={isActive=true,isEnabled=true,startTime=now,duration=90,modRate=1}
    now=now+1;SpellCooldown(55555,nil,nil,88);Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    local third=Button(1,3).button
    assert(third.cooldown.object and not third.cooldown.object.zero,
        "a shared category cooldown missed a spell button that shares it")
    actions[3].cooldown=nil
    now=now+1;SpellChanged(1003);RunTimers()
    assert(not third.cooldown.object,"the shared category cooldown did not end")
    -- The spell swipe itself: shown by its spell event, cleared by the next.
    actions[1].cooldown={isActive=true,isEnabled=true,startTime=now,duration=8,modRate=1}
    now=now+1;SpellChanged(1001);RunTimers()
    local first=Button(1,1).button
    assert(first.cooldown.object and first.cooldown.object.slot==1 and not first.cooldown.object.zero,
        "a spell's cooldown did not show from its spell event")
    actions[1].cooldown={isActive=false,isEnabled=true,startTime=0,duration=0,modRate=1}
    now=now+1;SpellChanged(1001);RunTimers()
    assert(not first.cooldown.object,"a spell's ended cooldown kept its swipe")
    -- Item and macro swipes follow the action bar event.
    actions[62].cooldown={isActive=true,isEnabled=true,startTime=now,duration=30,modRate=1}
    actions[63].cooldown={isActive=true,isEnabled=true,startTime=now,duration=12,modRate=1}
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(item.cooldown.object and not item.cooldown.object.zero and macro.cooldown.object
        and not macro.cooldown.object.zero,"an item or macro cooldown waited for a spell event")
    actions[62].cooldown,actions[63].cooldown=nil,nil
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(not item.cooldown.object and not macro.cooldown.object,"an ended item or macro cooldown kept its swipe")
    -- A new charge epoch (SPELL_UPDATE_CHARGES, spells, forms) puts every
    -- spell action back on the action bar event until a read proves it has
    -- no charges again.
    reads=calls.duration
    now=now+1;Event("SPELL_UPDATE_CHARGES");Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(calls.duration-reads==walk+2,"a new charge epoch left spell actions off the action bar event")
    reads=calls.duration
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(calls.duration-reads==others,"spell actions without charges stayed on the action bar event")
    -- A spell that gained charges stays on the action bar event, which
    -- also brings its recharge back.
    actions[2].charges={isActive=true,maxCharges=2,currentCharges=1}
    now=now+1;Event("SPELL_UPDATE_CHARGES");Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    local second=Button(1,2).button
    assert(second.chargeCooldown.object and not second.chargeCooldown.object.zero,"a recharge did not show")
    -- Its spell event and the action bar event in one flush read it once:
    -- one cooldown and one recharge duration (measured 2026-10-03: two of
    -- each before the action bar walk consumed the spell mark).
    do
        now=now+1
        local cooldowns,charges=SlotReads(2,function() SpellChanged(1002);RunTimers() end)
        assert(cooldowns==1 and charges==1,"a charge action read "..cooldowns.." cooldown and "..charges
            .." recharge durations for one event pair")
        now=now+1
        Budget("action bars flush: a charge action's spell and action bar events",
            Cost(function() SpellChanged(1002);RunTimers() end),1606)
    end
    actions[2].charges.isActive=false
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(not second.chargeCooldown.object,"a recharge that came back kept its swipe")
    actions[2].charges=nil
    now=now+1;Event("SPELL_UPDATE_CHARGES");Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    -- A slot change moves the route; the old spell keeps reaching the button
    -- for one change only.
    actions[1]={kind="spell",id=1201,texture=101}
    Event("ACTIONBAR_SLOT_CHANGED",1);now=now+1;RunTimers()
    reads=calls.duration
    SpellCooldown(1201);RunTimers()
    assert(calls.duration-reads==1,"the new spell of a slot did not reach its button")
    reads=calls.duration
    SpellCooldown(1001);RunTimers()
    assert(calls.duration-reads==1,"the previous spell of a slot lost its one-change alias")
    -- An override with the same art: the icon event re-reads the action.
    actions[1].id=1301
    now=now+1;Event("SPELL_UPDATE_ICON");RunTimers()
    reads=calls.duration
    SpellCooldown(1301);RunTimers()
    assert(calls.duration-reads==1,"a same-art override kept the old spell's route")
    reads=calls.duration
    SpellCooldown(1001);RunTimers()
    assert(calls.duration==reads,"a spell two changes back still read its old button")
    -- An override the action itself reports (GetActionInfo), dropped before
    -- its last cooldown event, which names the old override without a base
    -- (Blizzard keeps previousOverrideSpellID for this order).
    actions[1]={kind="spell",id=91001,texture=191}
    Event("ACTIONBAR_SLOT_CHANGED",1);now=now+1;RunTimers()
    actions[1]={kind="spell",id=1001,texture=101}
    now=now+1;Event("SPELL_UPDATE_ICON");RunTimers()
    actions[1].cooldown={isActive=true,isEnabled=true,startTime=now,duration=12,modRate=1}
    now=now+1
    local slotReads=SlotReads(1,function() SpellCooldown(91001);Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers() end)
    assert(slotReads==1 and first.cooldown.object and not first.cooldown.object.zero,
        "the late cooldown event of a dropped override did not repaint its button")
    actions[1].cooldown=nil
    now=now+1;SpellChanged(1001);RunTimers()
    -- An override the client applies to the action's base spell
    -- (C_Spell.GetOverrideSpell) with the same art, then dropped.
    spellOverrides[1001]=92001
    now=now+1;Event("SPELL_UPDATE_ICON");RunTimers()
    assert(Button(1,1).cdOverride==92001,"the base spell's override was not listed")
    now=now+1
    slotReads=SlotReads(1,function() SpellCooldown(92001);RunTimers() end)
    assert(slotReads==1,"an override's own cooldown event missed its base spell's button")
    spellOverrides[1001]=nil
    now=now+1;Event("SPELL_UPDATE_ICON");RunTimers()
    actions[1].cooldown={isActive=true,isEnabled=true,startTime=now,duration=12,modRate=1}
    now=now+1
    slotReads=SlotReads(1,function() SpellCooldown(92001);Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers() end)
    assert(slotReads==1 and first.cooldown.object and not first.cooldown.object.zero,
        "the late cooldown event of a dropped base-spell override did not repaint its button")
    actions[1].cooldown=nil
    now=now+1;SpellChanged(1001);RunTimers()
    actions[1]={kind="spell",id=1001,texture=101}
    Event("ACTIONBAR_SLOT_CHANGED",1)
    -- Clearing a button drops its route.
    actions[62],actions[63]=nil,nil
    Event("ACTIONBAR_SLOT_CHANGED",62);Event("ACTIONBAR_SLOT_CHANGED",63);now=now+1;RunTimers()
    assert(not Button(2,2).cdSpell and not Button(2,3).cdSpell)
    reads=calls.duration
    now=now+1;SpellCooldown(1001);RunTimers()
    assert(calls.duration-reads==1,"the restored spell lost its route")
    -- Bar 1 on an override page (above slot 120, with the skyriding, vehicle,
    -- possess and temporary shapeshift pages) still shows: Blizzard's own
    -- buttons take those cooldowns from ACTIONBAR_UPDATE_COOLDOWN, and no spell
    -- event may name them, so its buttons stay off the spell routes there.
    actions[205]={kind="spell",id=4205,texture=405}
    conditions.overridebar=true;special.override=true;Drivers();now=now+1;RunTimers()
    local override=Button(1,1)
    assert(Bar(1).header.attrs.actionpage==18 and override.slot==205 and Bar(1).header.shown
        and override.button.icon.texture==405,"bar 1 did not show the override page")
    assert(override.cdSpell==nil,"an override page spell joined the spell cooldown routes")
    actions[205].cooldown={isActive=true,isEnabled=true,startTime=now,duration=20,modRate=1}
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(override.button.cooldown.object and override.button.cooldown.object.slot==205
        and not override.button.cooldown.object.zero,"an override page spell missed its ACTIONBAR_UPDATE_COOLDOWN swipe")
    actions[205].cooldown=nil
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(not override.button.cooldown.object,"an override page spell kept its ended swipe")
    conditions.overridebar=nil;special.override=nil;Drivers();now=now+1;RunTimers()
    actions[205]=nil
    assert(override.slot==1 and override.cdSpell==1001,"bar 1 back on its own page lost the spell route")
    -- Bars 6-8 hold fixed player slots above 120 (145-180): their spells keep
    -- the route, so ACTIONBAR_UPDATE_COOLDOWN reads them no more.
    actions[145]={kind="spell",id=4145,texture=445}
    assert(S.Set("actionbars","bar6Visibility",1));Event("ACTIONBAR_SLOT_CHANGED",145);now=now+1;RunTimers()
    local sixth=Button(6,1)
    assert(sixth.slot==145 and sixth.filled and sixth.cdSpell==4145,"a bar 6 spell lost its spell cooldown route")
    now=now+1
    local fixedReads=SlotReads(145,function() Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers() end)
    assert(fixedReads==0,"ACTIONBAR_UPDATE_COOLDOWN read a routed bar 6 spell")
    now=now+1
    fixedReads=SlotReads(145,function() SpellCooldown(4145);RunTimers() end)
    assert(fixedReads==1,"a bar 6 spell's cooldown event missed its button")
    actions[145]=nil
    assert(S.Set("actionbars","bar6Visibility",6));Event("ACTIONBAR_SLOT_CHANGED",145);now=now+1;RunTimers()
end
-- The cap's trailing flush has its own flag: a page change while it waits
-- (a form swap in combat) still repaints bar 1 on the next frame.
actions[73]={kind="spell",id=3073,texture=373}
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunDue()
Event("ACTIONBAR_UPDATE_COOLDOWN");RunDue()
assert(#timers==1 and timers[1].at>now,"the cap arms one trailing flush")
local keyReads=bindingReads
combat=true
conditions["bonusbar:1"]=true;special.bonus=1;Drivers()
RunDue()
assert(Button(1,1).slot==73 and Button(1,1).button.icon.texture==373,"a page change waited for the cooldown cap")
assert(bindingReads==keyReads,"a page change re-read the key bindings")
conditions["bonusbar:1"]=nil;special.bonus=nil;Drivers()
RunDue()
assert(Button(1,1).slot==1 and Button(1,1).button.icon.texture==101)
combat=false
RunTimers()
actions[61].cooldown={isActive=true,isEnabled=true,startTime=now,duration=8,modRate=1}
now=now+1;SpellChanged(61);RunTimers()
assert(b61.cooldown.object and b61.cooldown.object.slot==61,
    "duration-only path did not show an active cooldown")
actions[61].cooldown={isActive=false,isEnabled=true,startTime=0,duration=0,modRate=1}
now=now+1;SpellChanged(61);RunTimers()
assert(not b61.cooldown.object and not b61.cooldown.cooldown and calls.cooldown==infoCalls,
    "duration-only path did not clear an inactive cooldown without info tables")
local locReads=calls.loc
now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(calls.loc==locReads,"no active loss of control still scanned action slots")
locCount=1
Event("LOSS_OF_CONTROL_ADDED","player",1);RunTimers()
assert(calls.loc>locReads,"active loss of control did not scan action slots")
locReads=calls.loc
locCount=0
now=now+.2;Event("LOSS_OF_CONTROL_UPDATE","player");RunTimers()
assert(calls.loc==locReads,"ended loss of control kept scanning action slots")
now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(calls.loc==locReads,"subsequent cooldown event resumed loss-of-control scans")
-- Secret cooldowns: duration objects only, no comparisons.
actions[61].cooldown={isActive=true,isEnabled=true,startTime=Secret(),duration=Secret(),modRate=Secret()}
actions[61].charges={isActive=true,maxCharges=3,currentCharges=Secret(),cooldownStartTime=Secret(),cooldownDuration=Secret(),chargeModRate=Secret()}
actions[61].count=Secret()
actions[61].remaining=5
assert(S.SetMany("actionbars",{desaturateCooldown=true,cooldownAlpha=40,hideEmptyCharges=true}))
infoCalls=calls.cooldown
calls.combinedChargeBaseline=calls.chargesBySlot[61] or 0
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");Event("SPELL_UPDATE_CHARGES");RunTimers()
assert(calls.chargesBySlot[61]==calls.combinedChargeBaseline+1,
    "same-flush charge and cooldown events repeated the action's native query")
assert(calls.cooldown==infoCalls,
    "cooldown feedback allocated action cooldown info tables")
assert(b61.cooldown.object and b61.cooldown.object.slot==61 and not b61.cooldown.cooldown,"secret cooldown via duration object")
assert(b61.chargeCooldown.object,"secret recharge via duration object")
assert(IsSecret(b61.Count.text) and b61.Count.alpha==1,"secret count reaches SetText only")
do
    local before=calls.chargesBySlot[61]
    for _=1,20 do now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers() end
    assert(calls.chargesBySlot[61]==before and b61.chargeCooldown.object,
        "a known charge action allocated info tables on pure cooldown events")
    actions[61].charges.isActive=false
    now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(calls.chargesBySlot[61]==before and not b61.chargeCooldown.object,
        "native zero recharge duration did not clear the swipe without info")
    actions[61].charges.isActive=true
    now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(b61.chargeCooldown.object,"native recharge duration did not resume the swipe")
    -- No duration object from the client (BugSack, 12.1): the known-charge
    -- fast path, the swipe and the feedback clear instead of erroring.
    local errors=#dispatch.errors
    noDuration[61]=true
    now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(#dispatch.errors==errors,"a missing duration object raised an error")
    assert(not b61.chargeCooldown.object and not b61.cooldown.object,"a missing duration object kept a swipe")
    assert(b61.icon.desaturation==0 and b61.alpha==1,"a missing duration object kept the cooldown feedback")
    noDuration[61]=nil
    now=now+.2;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
    assert(b61.chargeCooldown.object and b61.cooldown.object,"the swipe did not resume after a missing duration object")
end
do
    local reader,errors=AB.Painter.api.Charges,#dispatch.errors
    local raised=false
    AB.Painter.api.Charges=function(slot)
        if slot==61 and not raised then raised=true;error("combined charge read failed") end
        return reader(slot)
    end
    actions[61].charges={isActive=false,maxCharges=3,currentCharges=0}
    dispatch.expect=true
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");Event("SPELL_UPDATE_CHARGES");RunTimers()
    dispatch.expect=false;AB.Painter.api.Charges=reader
    assert(#dispatch.errors==errors+1 and b61.Count.alpha==0,
        "a failed combined cooldown walk lost the uncapped count update")
    actions[61].charges={isActive=true,maxCharges=3,currentCharges=Secret()}
    now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");Event("SPELL_UPDATE_CHARGES");RunTimers()
    assert(b61.Count.alpha==1,"the combined cooldown retry kept a stale count")
end
assert(b61.icon.desaturation==1 and b61.alpha==.4,"curve-driven cooldown feedback")
assert(AB.desatCurve.points[2][2]==1 and AB.alphaCurve.points[2][2]==.4)
secretEval=true
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(IsSecret(b61.icon.desaturation) and IsSecret(b61.alpha),"secret evaluations go straight to the sinks")
secretEval=false
actions[61].savedCharges=actions[61].charges
actions[61].charges=Secret()
cooldownCalls=calls.cooldown
now=now+1;Event("SPELL_UPDATE_CHARGES");RunTimers()
assert(b61.chargeCooldown.object,
    "an unreadable charge result cleared a previously visible recharge")
assert(calls.cooldown==cooldownCalls,
    "Retail charge-only event repeated the cooldown walk")
actions[61].charges=actions[61].savedCharges
actions[61].savedCharges=nil
Fire(b61.cooldown,"OnCooldownDone")
actions[61].remaining=0;actions[61].cooldown={isActive=false,isEnabled=true,startTime=0,duration=0,modRate=1}
Fire(b61.cooldown,"OnCooldownDone")
assert(b61.icon.desaturation==0 and b61.alpha==1 and b61.cooldown.clears,"cooldown end restores the button")
local normalClears,chargeClears=b61.cooldown.clears,b61.chargeCooldown.clears
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(b61.cooldown.clears==normalClears and b61.chargeCooldown.clears==chargeClears,
    "Inactive cooldowns were repeatedly cleared during a spell storm")
actions[61].charges={isActive=false,maxCharges=3,currentCharges=0}
Event("SPELL_UPDATE_CHARGES");now=now+1;RunTimers()
assert(b61.Count.alpha==0,"readable zero charges hide the count")
-- Usable tint and range.
actions[61].usable=false;actions[61].noMana=true
Event("ACTION_USABLE_CHANGED",{{slot=61,usable=false,noMana=true}})
assert(b61.icon.vertex[3]==1 and b61.icon.vertex[1]==.5,"no-mana tint")
assert(rangeEnabled[61],"visible filled slots hold a range check")
local registrations=rangeOn
AB.MarkBar(Bar(2));RunTimers()
assert(rangeOn==registrations,"repaint registered the same range check again")
actions[145]={kind="spell",id=145,texture=145}
assert(S.Set("actionbars","bar6Visibility",1));RunTimers()
assert(rangeEnabled[145],"extended action bar needs range events")
assert(S.Set("actionbars","bar6Visibility",6))
assert(not rangeEnabled[145],"hidden extended bar retained its range check")
Event("ACTION_RANGE_CHECK_UPDATE",61,false,true)
assert(math.abs(b61.icon.vertex[1]-0.8)<.01,"out of range tint")
Event("ACTION_RANGE_CHECK_UPDATE",61,true,true)
assert(b61.icon.vertex[1]==.5,"back in range restores the usable tint")
Event("ACTION_RANGE_CHECK_UPDATE",61,Secret(),true)
assert(b61.icon.vertex[1]==.5,"secret range payload never compared")
-- An owned button should not query usability while range tint covers it;
-- the return edge must read the current answer before repainting.
Event("ACTION_RANGE_CHECK_UPDATE",1,false,true)
calls.rangeGateReads=calls.usableBySlot[1] or 0
actions[1].usable=false
Event("ACTION_USABLE_CHANGED",{{slot=1}})
assert((calls.usableBySlot[1] or 0)==calls.rangeGateReads
    and Button(1,1).button.icon.vertex[1]==AB.style.rr,
    "out-of-range owned action queried hidden usability")
Event("ACTION_RANGE_CHECK_UPDATE",1,true,true)
assert((calls.usableBySlot[1] or 0)==calls.rangeGateReads+1
    and Button(1,1).button.icon.vertex[1]==.4,
    "owned action did not recover unusable tint on range return")
calls.rangeGateReads=calls.usableBySlot[1]
Event("ACTION_RANGE_CHECK_UPDATE",1,true,true)
assert(calls.usableBySlot[1]==calls.rangeGateReads,
    "unchanged range event repeated an owned usability query")
actions[1].usable=true
Event("ACTION_USABLE_CHANGED",{{slot=1,usable=true,noMana=false}})
assert(Button(1,1).button.icon.vertex[1]==1,"owned action did not accept usable payload")
-- Hot events of a visible suite button (instructions, GC stopped): usable
-- reports and range edges repaint its tint, proc glows show and hide. These
-- budgets hold the instructions measured on 2026-10-02 at q11/merge, before
-- the named modes of wave 3, plus 2 %.
do
    local function Usable(on) Event("ACTION_USABLE_CHANGED",{{slot=61,usable=on,noMana=not on}}) end
    Budget("actionbars: a usable report pair",Cost(function() Usable(true);Usable(false) end),461)
    Budget("actionbars: a range edge pair",Cost(function()
        Event("ACTION_RANGE_CHECK_UPDATE",61,false,true);Event("ACTION_RANGE_CHECK_UPDATE",61,true,true)
    end),412)
end
-- Usability follows Blizzard's buttons (ActionButton.lua, Retail and
-- Forever): slot payloads, plus one full re-read when the mount display
-- changes; target changes walk nothing. Suite buttons on slots the payload
-- never named (bar 9: slots 13-24 have no Blizzard button) follow
-- ACTIONBAR_UPDATE_USABLE, which re-reads only those.
do
    local events=M.context.frame.events
    assert(not events.PLAYER_TARGET_CHANGED,"a target change walks every button's usability")
    actions[1].usable=false
    local reads=calls.usableBySlot[1] or 0
    now=now+1;Event("PLAYER_MOUNT_DISPLAY_CHANGED");RunTimers()
    assert(calls.usableBySlot[1]==reads+1 and Button(1,1).button.icon.vertex[1]==.4,
        "a mount display change did not re-read usability")
    actions[1].usable=true
    now=now+1;Event("PLAYER_MOUNT_DISPLAY_CHANGED");RunTimers()
    assert(Button(1,1).button.icon.vertex[1]==1)
    actions[13].usable=false
    local named,unnamed=calls.usableBySlot[1] or 0,calls.usableBySlot[13] or 0
    now=now+1;Event("ACTIONBAR_UPDATE_USABLE");RunTimers()
    assert(calls.usableBySlot[13]==unnamed+1 and Button(9,1).button.icon.vertex[1]==.4,
        "a suite button on a slot ACTION_USABLE_CHANGED never named went stale")
    assert((calls.usableBySlot[1] or 0)==named,"ACTIONBAR_UPDATE_USABLE re-read a slot the payload tracks")
    actions[13].usable=true
    now=now+1;Event("ACTIONBAR_UPDATE_USABLE");RunTimers()
    assert(Button(9,1).button.icon.vertex[1]==1)
end
-- Every flush unit runs isolated: a raising bar paint is reported, the
-- units after it still run, and the bar gets its paint back once.
do
    local info,errors=GetActionInfo,#dispatch.errors
    GetActionInfo=function() GetActionInfo=info;error("paint failed") end
    bindings.MSUFSUITE_BAR9_BUTTON1={"F9"}
    dispatch.expect=true
    AB.MarkBar(Bar(9));AB.Mark("keys");RunTimers()
    dispatch.expect=false
    assert(#dispatch.errors==errors+1 and dispatch.errors[errors+1]:find("paint failed",1,true),
        "a raising bar paint was not reported")
    assert(Button(9,1).button.HotKey.text==S.KeyText("F9"),"a raising bar paint stopped the key texts after it")
    local reads=infoReads
    AB.Mark("state");RunTimers()
    assert(infoReads>reads,"the raising bar paint was not retried")
    bindings.MSUFSUITE_BAR9_BUTTON1={"CTRL-BUTTON4","MOUSEWHEELUP"}
    AB.Mark("keys");RunTimers()
end
local references=AB.Diagnostics.RangeReferences()
assert(references>0)
assert(S.Set("actionbars","bar2Visibility",6))
assert(not rangeEnabled[61] and AB.Diagnostics.RangeReferences()<references,"hidden bars release range checks")
assert(S.Set("actionbars","bar2Visibility",1))
RunTimers()
assert(rangeEnabled[61],"shown bars re-acquire")
-- Proc glows by spell id; secret payloads fall back to a full rescan.
-- The suite plays Blizzard's alert template itself: no entry in the
-- manager's shared table, which Blizzard walks for its own buttons.
overlayed[61]=true
local flyouts=0
for index=1,10 do
    local bar=AB.bars[index]
    if not bar.native and bar.header:IsVisible() then
        for _,rec in ipairs(bar.filled) do
            if actions[rec.slot] and actions[rec.slot].kind=="flyout" then flyouts=flyouts+1 end
        end
    end
end
local reads=infoReads
Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",61)
assert(infoReads-reads==flyouts,"a proc glow event read action info for spell buttons: "..(infoReads-reads))
local alert=b61.SpellActivationAlert
assert(alert and alert.shown and alert.ProcStartAnim.playing and alert.width==b61.width*1.4,
    "Blizzard spell alert on the matching button")
-- A proc glow pair on the Blizzard alert (instructions, GC stopped).
Budget("actionbars: a proc glow pair, Blizzard alert",Cost(function()
    Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",61);Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",61)
end),1555)
assert(not next(alerts),"a suite button entered Blizzard's shared spell alert table")
overlayed[61]=nil
Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",61)
assert(not alert.shown and not alert.ProcStartAnim.playing and not next(alerts))
Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",Secret());RunTimers()
assert(S.Set("actionbars","procGlow",2))
overlayed[61]=true;Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",61)
assert(not alerts[b61] and Button(2,1).glowEdges and Button(2,1).glowEdges[1].shown,"pixel border glow")
Budget("actionbars: a proc glow pair, pixel border",Cost(function()
    Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",61);Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",61)
end),1820)
-- A new highlight color reaches a pixel glow that is already showing.
local highlightColor=c.interactionColor
assert(not c.interactionClassColor and S.Set("actionbars","interactionColor","00ff00"))
local glowEdge=Button(2,1).glowEdges[1]
assert(glowEdge.shown and glowEdge.color[1]==0 and glowEdge.color[2]==1 and glowEdge.color[3]==0,
    "a showing pixel glow kept the old highlight color")
assert(S.Set("actionbars","interactionColor",highlightColor))
overlayed[61]=nil;Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",61)
assert(not Button(2,1).glowEdges[1].shown)
assert(S.Set("actionbars","procGlow",3));RunTimers()
assert(not M.context.frame.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW
    and not M.context.frame.events.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE,
    "disabled proc glows kept high-frequency spell listeners")
assert(S.Set("actionbars","procGlow",2));RunTimers()
assert(M.context.frame.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW,
    "enabling proc glows did not restore their listener")
assert(S.Set("actionbars","rangeColoring",false));RunTimers()
assert(not M.context.frame.events.ACTION_RANGE_CHECK_UPDATE and AB.Diagnostics.RangeReferences()==0,
    "disabled range coloring kept range checks or its event listener")
assert(S.Set("actionbars","rangeColoring",true));RunTimers()
assert(M.context.frame.events.ACTION_RANGE_CHECK_UPDATE and AB.Diagnostics.RangeReferences()>0,
    "enabling range coloring did not restore its listener and checks")
-- Slot changes in combat repaint, park later.
combat=true
actions[62]={kind="spell",id=62,texture=62}
Event("ACTIONBAR_SLOT_CHANGED",62);RunTimers()
assert(Button(2,2).button.icon.texture==62,"slot change repaints in combat")
actions[64]=nil
combat=false
-- Native key presses show the pushed state on the suite button.
ActionButtonDown(2)
assert(Button(1,2).button.state=="PUSHED" and native[#native]=="down2")
ActionButtonUp(2)
assert(Button(1,2).button.state=="NORMAL")
-- The press hooks run inside Blizzard's binding handlers, isolated: an
-- error is reported and never reaches Blizzard's handler.
do
    local button,errors=Button(1,2).button,#dispatch.errors
    button.SetButtonState=function() button.SetButtonState=nil;error("press hook failed") end
    dispatch.expect=true
    ActionButtonDown(2)
    dispatch.expect=false
    assert(#dispatch.errors==errors+1 and dispatch.errors[errors+1]:find("press hook failed",1,true),
        "a raising press hook reached Blizzard's binding handler")
    ActionButtonUp(2)
end
MultiActionButtonDown("MultiBarBottomLeft",1)
assert(b61.state=="PUSHED")
-- Checked state and equipped border.
actions[61].current=true;actions[61].equipped=true
Event("ACTIONBAR_UPDATE_STATE");Event("PLAYER_EQUIPMENT_CHANGED");now=now+1;RunTimers()
assert(b61.checked==true and b61.Border.shown)
assert(S.Set("actionbars","castHighlight",false));RunTimers()
assert(b61.checked==false)

------------------------------------------------------------------ cooldown feedback off
-- Turning the feedback off clears what the duration curves painted.
actions[61].cooldown={isActive=true,isEnabled=true,startTime=now,duration=8,modRate=1}
actions[61].remaining=5
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(b61.icon.desaturation==1 and b61.alpha==.4 and not b61.cooldown.cooldown,"duration curves paint the feedback")
assert(S.SetMany("actionbars",{desaturateCooldown=false,cooldownAlpha=100}));RunTimers()
assert(b61.icon.desaturation==0 and b61.alpha==1,
    "duration-only path did not clear previous cooldown feedback")

------------------------------------------------------------------ style
assert(Button(2,1).button.icon.unmasked,"square icons drop the template mask")
assert(#Suite.ActionBarLookPresets == 3 or (Suite.ActionBarLookPresets[1]
    and Suite.ActionBarLookPresets[2] and Suite.ActionBarLookPresets[3]),
    "Action Bar Blue, Dark and Forever looks are missing")
assert(S.Config("actionbars").look == 5 and S.Config("actionbars").borderColor == "333333",
    "new Retail Action Bars did not use Clean Modern")
assert(Button(2,1).borderEdges[1].shown
    and math.abs(Button(2,1).borderEdges[1].color[1] - 51 / 255) < .01)
assert(S.SetMany("actionbars",{borderClassColor=true,highlightStyle=2,pushedStyle=4,iconZoom=10}))
local style=Button(2,1)
assert(math.abs(style.borderEdges[1].color[1]-.78)<.01 and style.button.HighlightTexture.color and style.button.PushedTexture.alpha==0)
assert(style.button.icon.coords[1]==.1)
assert(S.Set("actionbars","highlightStyle",3))
assert(style.button.HighlightTexture.atlas=="UI-HUD-ActionBar-IconFrame-Mouseover","Blizzard style restores the template art")
assert(S.SetMany("actionbars",{fontOutline=2,fontRendering=2,fontShadow=true,
    fontShadowOpacity=75,fontShadowDistance=2}))
assert(style.button.Count.font[3]=="THICKOUTLINE,MONOCHROME"
    and style.button.Count.shadowColor[4]==0.75 and style.button.Count.shadowOffset[1]==2,
    "Action Bar text effects did not apply")
assert(S.Set("actionbars","fontRendering",3))
assert(style.button.Count.font[3]=="OUTLINE,SLUG" and style.button.Count.shadowColor[4]==0,
    "Action Bar Slug retained a shadow")
assert(Button(2,1).button.cooldown.hideNumbers==false and Button(2,1).button.chargeCooldown.hideNumbers==false)
assert(S.Set("actionbars","cooldownNumbers",false))
assert(Button(2,1).button.cooldown.hideNumbers==true and Button(2,1).button.chargeCooldown.hideNumbers==true)

-- Explicit anchors and independent offsets affect text only; the cooldown
-- clamp responds to actual button size, including charge countdowns.
do
    assert(S.SetMany("actionbars", { bar2Size=16, bar2CooldownSize=30, bar2CooldownPoint=3,
        bar2CooldownX=4, bar2CooldownY=-5, bar2KeybindPoint=8, bar2KeybindX=7 }))
    local button=Button(2,1).button
    local text=button.cooldown:GetCountdownFontString()
    assert(text.font[2]==6 and text.points[1][1]=="TOP" and text.points[1][4]==4 and text.points[1][5]==-5,
        "cooldown anchor/offset or small-button clamp failed")
    assert(button.chargeCooldown:GetCountdownFontString().font[2]==6,"charge countdown escaped clamp")
    local keyText=Button(2,1).owned and not Button(2,1).native and button.HotKey or Button(2,1).keyText
    assert(keyText.points[1][1]=="BOTTOMLEFT" and keyText.points[1][4]==7,
        "independent keybind anchor failed")
    assert(S.SetMany("actionbars", { bar2CooldownAutoSize=false }))
    assert(text.font[2]==30,"explicit font size was not restored when auto fit was off")
    assert(S.SetMany("actionbars", { bar2Size=40, bar2CooldownAutoSize=true, bar2CooldownPoint=1,
        bar2CooldownX=0, bar2CooldownY=0, bar2KeybindPoint=1, bar2KeybindX=0 }))
    local old=c.bar2Visibility
    assert(S.ToggleActionBar(2) and c.bar2Visibility==6 and c.bar2ResumeVisibility==old)
    assert(S.ToggleActionBar(2) and c.bar2Visibility==old,"bar toggle lost resume mode")
    combat=true
    assert(not S.ToggleActionBar(2) and c.bar2Visibility==old,"bar toggle changed protected state in combat")
    assert(printed[#printed] and printed[#printed]:find("Action bar 2 switches when combat ends.",1,true),
        "a bar toggle pressed in combat was silent")
    combat=false;Broadcast("PLAYER_REGEN_ENABLED")
    assert(c.bar2Visibility==6 and c.bar2ResumeVisibility==old,"a bar toggle pressed in combat never switched the bar")
    -- Pressed twice in combat, the second press cancels the first.
    combat=true
    S.ToggleActionBar(2);S.ToggleActionBar(2)
    assert(printed[#printed]:find("Action bar 2 stays as it is.",1,true),"a cancelled bar toggle was silent")
    combat=false;Broadcast("PLAYER_REGEN_ENABLED")
    assert(c.bar2Visibility==6,"a cancelled bar toggle still switched the bar")
    assert(S.ToggleActionBar(2) and c.bar2Visibility==old,"bar toggle lost resume mode after combat")
    local driver=AB.PageDriver({pagingTarget=true,pageFriendly=3,pageHostile=4})
    assert(driver:find("[help] 3; [harm] 4;",1,true) and driver:find("[vehicleui]",1,true)==1)
    assert(AB.CustomPaging({pagingTarget=true}),"target paging did not route native key commands")
end

-- Static ornaments and custom feedback reuse native state/geometry.
do
    assert(S.SetMany("actionbars",{bar1LeftEndcap=2,bar1RightEndcap=3,bar1LeftEndcapSize=42,
        bar1LeftEndcapX=-7,bar1Background=true,bar1BackgroundPaddingX=9,bar1BackgroundPaddingY=3,
        bar1BackgroundX=5,bar1BackgroundBorder=2,buttonShape=2,borderArt=2}))
    local rec=Button(1,1)
    assert(Bar(1).LeftEndcap.width==42 and Bar(1).RightEndcap.pieces[4].shown,"independent endcaps not laid out")
    assert(Bar(1).background.points[1][4]==-4 and Bar(1).background.points[1][5]==3,"axis background geometry incorrect")
    assert(rec.shapeMask and rec.button.icon.mask==rec.shapeMask and rec.button.cooldown.swipeTexture:find("TempPortraitAlphaMask",1,true))
    assert(rec.borderArt.shown and rec.edgeHost:GetFrameLevel()>rec.button.cooldown:GetFrameLevel())
    AB.SetPushed(rec,true);assert(rec.stateArt.shown,"pressed textured frame missing")
    AB.SetPushed(rec,false);assert(not rec.stateArt.shown)
    -- Endcaps and the bar background border wear the resolved border color
    -- (the class color with "Class-colored border"), placed once per layout.
    assert(S.Set("actionbars","borderClassColor",true))
    local piece,edge=Bar(1).RightEndcap.pieces[1],Bar(1).backgroundEdges[1]
    assert(math.abs(piece.color[1]-.78)<.01 and math.abs(edge.color[1]-.78)<.01,
        "endcaps or the bar background border ignored the class-colored border")
    assert(S.Set("actionbars","borderClassColor",false) and math.abs(piece.color[1]-AB.style.br)<.01,
        "endcaps kept the class color")
    do
        local placeEdges,placed=S.PlaceEdges,0
        S.PlaceEdges=function(set,...) if set==Bar(1).backgroundEdges then placed=placed+1 end;return placeEdges(set,...) end
        assert(S.Set("actionbars","bar1BackgroundBorder",3))
        S.PlaceEdges=placeEdges
        assert(placed==1,"a background border tick placed its edges "..placed.." times")
    end
    -- Round buttons: a ring for the mouseover border and for the pixel glow.
    local highlightBefore=c.highlightStyle
    assert(S.SetMany("actionbars",{highlightStyle=1,procGlow=2}))
    assert(rec.hoverRing and rec.hoverRing.shown and rec.hoverRing.layer=="HIGHLIGHT" and not rec.hoverEdges[1].shown,
        "a round button kept a square mouseover border")
    overlayed[1001]=true;Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",1001)
    assert(rec.glowRing and rec.glowRing.shown and not (rec.glowEdges and rec.glowEdges[1].shown),
        "a round button kept a square pixel glow")
    overlayed[1001]=nil;Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",1001)
    assert(not rec.glowRing.shown,"the round pixel glow stayed")
    assert(S.Set("actionbars","highlightStyle",highlightBefore))
    assert(S.SetMany("actionbars",{buttonShape=1,borderArt=1,bar1LeftEndcap=1,bar1RightEndcap=1}))
    assert(not rec.hoverRing.shown,"a square button kept the round mouseover border")
    AB.SetPushed(rec,true);assert(not rec.stateArt.shown,"old textured state survived style switch")
    AB.SetPushed(rec,false)
    -- The spellbook of Retail and Forever: Blizzard_PlayerSpells'
    -- PlayerSpellsFrame.SpellBookFrame (the addon loads on demand).
    PlayerSpellsFrame=NewFrame("Frame",nil,UIParent)
    PlayerSpellsFrame.SpellBookFrame=NewFrame("Frame",nil,PlayerSpellsFrame)
    PlayerSpellsFrame.SpellBookFrame:Show();PlayerSpellsFrame:Hide()
    local neverBefore=c.bar6Visibility
    assert(S.Set("actionbars","showOnPanels",true) and not AB.panelsOpen,"hidden spellbook parent revealed bars")
    assert(S.Set("actionbars","bar6Visibility",6))
    PlayerSpellsFrame:Show()
    -- The reveal follows the implicit hides and leaves Never bars hidden.
    assert(AB.panelsOpen and Bar(1).visDriver:find("[petbattle][vehicleui] hide; [nocombat] show; ",1,true)==1,
        "spellbook reveal missing or ahead of the vehicle and pet battle hides: "..Bar(1).visDriver)
    assert(Bar(6).visDriver=="hide" and not Bar(6).header.shown,"the spellbook reveal showed a Never bar")
    conditions.vehicleui=true;Drivers()
    assert(not Bar(1).header.shown,"the spellbook reveal showed bar 1 over the vehicle UI")
    conditions.vehicleui=nil;conditions.petbattle=true;Drivers()
    assert(not Bar(1).header.shown and not Bar(2).header.shown,"the spellbook reveal showed bars over a pet battle")
    conditions.petbattle=nil;Drivers()
    -- Closed in combat: the reveal waits for combat to end, then drops.
    combat=true
    PlayerSpellsFrame:Hide()
    assert(AB.panelsOpen and AB.panelPending,"harness: a spellbook closed in combat parks the reveal")
    combat=false;Event("PLAYER_REGEN_ENABLED");RunTimers()
    assert(not AB.panelsOpen and not AB.panelPending and not Bar(1).visDriver:find("[nocombat] show;",1,true)
        and Bar(5).header.attrs.gridmask==0,"the spellbook reveal outlived combat")
    assert(S.Set("actionbars","showOnPanels",false) and S.Set("actionbars","bar6Visibility",neverBefore))
    PlayerSpellsFrame=nil
    assert(S.Set("actionbars","pageArrows",true))
    local arrows=assert(Bar(1).pageArrows,"page arrows did not appear beside bar 1")
    local pager=MainBar.ActionBarPageNumber
    assert(arrows.shown and arrows.buttons[1]:GetAttribute("type")=="click"
        and arrows.buttons[1]:GetAttribute("clickbutton")==pager.UpButton
        and arrows.buttons[2]:GetAttribute("clickbutton")==pager.DownButton,"arrows must route to native page actions")
    assert(arrows.buttons[1].normalAtlas=="ui-hud-actionbar-pageuparrow-up"
        and arrows.buttons[2].highlightAtlas=="ui-hud-actionbar-pagedownarrow-mouseover",
        "page arrows must wear Blizzard's page arrow atlases, not font glyphs")
    -- SecureActionButton_OnClick (Blizzard_FrameXML/SecureTemplates.lua): an
    -- addon's secure button acts on the press while its useOnKeyDown (default:
    -- the ActionButtonUseKeyDown CVar, on here) is set, else on the release;
    -- the "click" action then clicks its clickbutton. Only the registered
    -- click kinds ever arrive.
    local function HardwareClick(frame)
        local keydown=frame.attrs.useOnKeyDown
        if keydown==nil then keydown=cvars.ActionButtonUseKeyDown==true end
        for _,kind in ipairs(frame.clickTypes or {}) do
            local down=kind:find("Down",1,true)~=nil
            if (down and keydown) or (not down and not keydown) then
                if frame.attrs.type=="click" then frame.attrs.clickbutton:Click("LeftButton") end
                return
            end
        end
    end
    HardwareClick(arrows.buttons[1]);HardwareClick(arrows.buttons[2])
    assert(pageClicks[1]=="up" and pageClicks[2]=="down","a page arrow click never reached Blizzard's page button")
    assert(S.Set("actionbars","pageArrows",false) and not arrows.shown)
    -- Recommendation ring: Blizzard's candidates are its own (hidden) buttons,
    -- so a suite button matches the spell its paint cached.
    assert(c.assistStyle==2,"the recommendation default does not cover bar 1")
    Recommend(1001)
    assert(rec.assist and rec.assist.shown and rec.assist.ring.shown and not rec.assist.fill.shown,
        "the ring missed bar 1's recommended spell")
    assert(S.Set("actionbars","assistStyle",4) and rec.assist.ring.shown and rec.assist.fill.shown)
    Recommend(nil);assert(S.Set("actionbars","assistStyle",1));Recommend(1001)
    assert(S.Set("actionbars","assistStyle",4) and rec.assist.shown,"the cached recommendation was omitted on a style change")
    -- A slider tick of an unrelated setting re-reads no action for the rings.
    local reads=infoReads
    assert(S.Set("actionbars","bar3Alpha",60) and infoReads==reads,"an unrelated setting re-read every action for the rings")
    Recommend(1002)
    assert(not rec.assist.shown and Button(1,2).assist.shown,"native recommendation change did not move feedback")
    -- A recommendation change only moves which rings show: no ring is laid
    -- out or colored again while its look stays the same.
    do
        local rings,writes={rec.assist,Button(1,2).assist},0
        for _,holder in ipairs(rings) do
            for _,name in ipairs({"SetSize","SetPoint","ClearAllPoints"}) do
                local real=getmetatable(holder).__index[name]
                holder[name]=function(...) writes=writes+1;return real(...) end
            end
            local real=getmetatable(holder.ring).__index.SetVertexColor
            holder.ring.SetVertexColor=function(...) writes=writes+1;return real(...) end
        end
        for i=1,6 do Recommend(i%2==1 and 1001 or 1002) end
        assert(writes==0,"a recommendation change laid the rings out again ("..writes.." writes)")
        assert(not rec.assist.shown and Button(1,2).assist.shown,"the last recommendation is not shown")
        assert(S.Set("actionbars","assistX",3) and writes>0,"a ring setting did not lay the ring out")
        assert(S.Set("actionbars","assistX",0))
        for _,holder in ipairs(rings) do
            holder.SetSize,holder.SetPoint,holder.ClearAllPoints,holder.ring.SetVertexColor=nil,nil,nil,nil
        end
    end
    -- Bar 1 changes page in combat: the ring follows the spell, not the button.
    combat=true
    conditions["bar:2"]=true;barPage=2;Drivers();RunDue()
    assert(Button(1,2).slot==14 and not Button(1,2).assist.shown,"the ring stayed on a button whose page changed")
    conditions["bar:2"]=nil;barPage=1;Drivers();RunDue()
    assert(Button(1,2).assist.shown,"the ring did not come back with the page")
    combat=false
    assert(S.Set("actionbars","assistStyle",1) and not Button(1,2).assist.shown,"custom feedback lingered after native style restored")
    Recommend(nil)
end

------------------------------------------------------------------ keybind export
-- The cooldown manager's icons show the key of the suite button that
-- presses a spell: bar order first (bar 9 owns slots 13-24, bar 10 slots
-- 109-120), bar 1's form pages last.
local spellSlots={}
C_ActionBar.FindSpellActionButtons=function(spell) return spellSlots[spell] or {} end
spellSlots[1001]={1}
spellSlots[61]={61}
spellSlots[2013]={13}
spellSlots[2110]={110}
spellSlots[2075]={75}
spellSlots[2076]={62,75}
spellSlots[3000]={}
bindings.MSUFSUITE_BAR10_BUTTON2={"CTRL-SPACE"}
assert(S.ActionBarsBindingForSpell(1001)=="1" and S.ActionBarsBindingForSpell(61)=="S1","native command keys")
do
    local visited, context = {}, {}
    local function Visit(button, passed) assert(passed==context);visited[button]=true end
    assert(S.ForEachActionBarButtonForSpell(1001,Visit,context)==1 and visited[Button(1,1).button],"public spell visitor missed current action button")
    combat=true;assert(S.ForEachActionBarButtonForSpell(1001,Visit,context)==0);combat=false
    assert(S.ForEachActionBarButtonForSpell("secret",Visit,context)==0,"spell visitor accepted non-public ID")
end
assert(S.ActionBarsBindingForSpell(2013)=="CM4","bar 9 presses slots 13-24")
assert(S.ActionBarsBindingForSpell(2110)=="CSpc","bar 10 presses slots 109-120, not bar 1's keys")
bindings.ACTIONBUTTON3={"3"}
assert(S.ActionBarsBindingForSpell(2075)=="3","form pages take bar 1's keys")
assert(S.ActionBarsBindingForSpell(2076)=="3","an unbound bar slot falls back to a form page key")
assert(S.ActionBarsBindingForSpell(3000)=="","a spell on no button has no key")
c.disableFormPaging=true
assert(S.ActionBarsBindingForSpell(2075)=="","bar 1 never pages to forms with the opt-out")
c.disableFormPaging=false
-- Bar 1's custom pages press their slots with bar 1's keys: a target page
-- with the plain key, a modifier page with the modifier held while that
-- combination has no binding of its own.
GetBindingAction=function(key)
    for command,keys in pairs(bindings) do
        for _,bound in ipairs(keys) do if bound==key then return command end end
    end
    return ""
end
spellSlots[4050]={50}
assert(S.ActionBarsBindingForSpell(4050)=="","harness: slot 50 starts without a key")
c.pagingTarget,c.pageFriendly,c.pageHostile=true,1,5
assert(S.ActionBarsBindingForSpell(4050)=="2","a spell on the hostile target page lost bar 1's key")
c.pagingTarget=false
c.pagingModifiers,c.pageShift,c.pageCtrl,c.pageAlt=true,5,2,3
assert(S.ActionBarsBindingForSpell(4050)==S.KeyText("SHIFT-2"),"a spell on the Shift page lost its modified key")
bindings.TOGGLEAUTORUN={"SHIFT-2"}
assert(S.ActionBarsBindingForSpell(4050)=="","a modified key bound elsewhere was shown for bar 1")
bindings.TOGGLEAUTORUN=nil
c.pagingModifiers,c.pageShift,c.pageCtrl,c.pageAlt=false,2,3,4
bindings.ACTIONBUTTON3=nil
bindings.MSUFSUITE_BAR10_BUTTON2=nil

------------------------------------------------------------------ settings work
-- A slider tick does the work of its setting only: bar 3's size restyles
-- bar 3's buttons, its opacity restyles and lays out nothing.
local restore={bar3Size=c.bar3Size,bar3Alpha=c.bar3Alpha,iconZoom=c.iconZoom}
local styled={}
local styleButton=AB.StyleButton
AB.StyleButton=function(rec) styled[rec.bar.index]=(styled[rec.bar.index] or 0)+1;return styleButton(rec) end
local layoutBar=AB.LayoutBar
local laid={}
AB.LayoutBar=function(bar) laid[bar.index]=(laid[bar.index] or 0)+1;return layoutBar(bar) end
assert(S.Set("actionbars","bar3Size",44))
assert(styled[3]==12 and laid[3]==1 and not styled[2] and not laid[2],"a bar size tick restyled or moved other bars")
styled,laid={},{}
assert(S.Set("actionbars","bar3Alpha",55))
assert(not next(styled) and not next(laid) and Bar(3).header.alpha==.55,"an opacity tick restyled or moved bars")
assert(S.Set("actionbars","iconZoom",8))
local total=0
for _,n in pairs(styled) do total=total+n end
assert(total==#AB.owned+#AB.adopted and not next(laid),"a global look change must restyle every button, move none")
styled={}
M:Refresh()
assert(not next(styled) and not next(laid),"a refresh without changes did work")
-- Every per-bar catalog setting has its key and its own work: none falls
-- back to rebuilding its bar, let alone everything.
for key,rule in pairs(S.catalog.actionbars.rules) do
    if rule.bar then
        local suffix=key:match("^bar%d+(.+)$")
        assert(AB.KEYS[rule.bar][suffix]==key,"per-bar setting without a key: "..key)
        assert(AB.BAR_WORK[suffix],"per-bar setting without its own work: "..key)
    end
end
-- The MSUF layer reaches the bar's header and only lays that bar out.
do
    local surfaces={}
    MSUF_NS.UF={Layers={
        ApplyOwnedSurface=function(frame,layer) surfaces[#surfaces+1]={frame=frame,layer=layer};return false end,
        ElementLevel=function(layer,_,detail) return layer*32+detail end}}
    local bindingEvents=triggered[BINDINGS_EVENT] or 0
    assert(S.Set("actionbars","bar3Layer",12))
    local reached=false
    for _,call in ipairs(surfaces) do reached=reached or call.frame==Bar(3).header and call.layer==12 end
    assert(reached,"the bar 3 MSUF layer never reached its header")
    assert(laid[3]==1 and not laid[2] and not next(styled) and (triggered[BINDINGS_EVENT] or 0)==bindingEvents,
        "an MSUF layer tick did more than lay out its bar")
    styled,laid={},{}
    assert(S.Set("actionbars","bar3Layer",-1))
    MSUF_NS.UF=nil
    styled,laid={},{}
    -- The gamepad rule only changes visibility (Forever; hidden on Retail).
    assert(S.catalog.actionbars.rules.bar3HideGamepad.hidden,"Retail offers the Forever gamepad rule")
    assert(S.Set("actionbars","bar3HideGamepad",true) and not next(styled) and not next(laid),
        "the gamepad rule restyled or moved bars")
    assert(S.Set("actionbars","bar3HideGamepad",false))
end
AB.StyleButton,AB.LayoutBar=styleButton,layoutBar
assert(S.SetMany("actionbars",restore))
-- Mover specs are built once per bar, not on every refresh.
local specs={}
local register=S.RegisterOwnedMover
S.RegisterOwnedMover=function(id,element,spec) specs[element]=specs[element] or {};table.insert(specs[element],spec);return register(id,element,spec) end
M:RegisterMovers();M:RegisterMovers()
assert(specs.bar3 and specs.bar3[1]==specs.bar3[2],"mover specs were rebuilt")
S.RegisterOwnedMover=register

------------------------------------------------------------------ UI scale
-- A new UI scale or resolution moves the pixel grid: one refresh per burst,
-- next frame, snaps every bar again (here 1.5 UI units per pixel).
RunTimers()
assert(S.Set("actionbars","bar3Size",40) and Button(3,1).button.width==40)
GetPhysicalScreenSize=function() return 800,512 end
Event("UI_SCALE_CHANGED");Event("DISPLAY_SIZE_CHANGED")
assert(#timers==1,"a scale burst must share one refresh")
RunTimers()
assert(Button(3,1).button.width==40.5,"a UI scale change left the bars on the old pixel grid")
GetPhysicalScreenSize=function() return 1024,768 end
combat=true
local queue,queued=S.Queue,nil
S.Queue=function(id) queued=id;return queue(id) end
Event("DISPLAY_SIZE_CHANGED");RunTimers()
S.Queue=queue
assert(queued=="actionbars" and Button(3,1).button.width==40.5,"a scale refresh in combat must wait for combat to end")
combat=false
S.Apply("actionbars")
assert(Button(3,1).button.width==40,"the queued scale refresh did not re-snap the bars")

------------------------------------------------------------------ movers and exports
M:RegisterMovers()
local element=assert(editElements.bar3,"mover for bar 3")
local function PopupControl(mover, id)
    for _, control in ipairs(mover.extraControls) do
        if control.id == id then return control end
    end
end
assert(element.getFrame()==Bar(3).header and element.label=="Action bar 3" and #element.extraControls==9)
assert(PopupControl(element,"bar3X") and PopupControl(element,"bar3Y"),
    "action bar popup omitted exact position controls")
for _,control in ipairs(element.extraControls) do assert(#control.label<=40 and control.id:match("^[%w_]+$")) end
assert(element.isEnabled() and not editElements.bar6.isEnabled(),"Never bars have no mover")
local horizontal,vertical=PopupControl(element,"horizontal"),PopupControl(element,"vertical")
assert(S.SetMany("actionbars",{bar4Buttons=12,bar4Rows=1,bar4Vertical=true})
    and PopupControl(editElements.bar4,"horizontal").get() and not PopupControl(editElements.bar4,"vertical").get(),
    "popup orientation follows the visible row even with column-first fill")
assert(horizontal.id=="horizontal" and vertical.id=="vertical" and horizontal.get() and not vertical.get(),
    "popup starts in horizontal layout")
assert(vertical.set(true) and c.bar3Vertical and c.bar3Rows==c.bar3Buttons and vertical.get() and not horizontal.get(),
    "vertical popup control makes a single column")
assert(Bar(3).header.width==40 and Bar(3).header.height==502,"vertical popup control lays out the bar")
assert(vertical.set(false)==false and vertical.get(),"active orientation cannot be deselected")
PopupControl(element,"buttons").set(4)
assert(c.bar3Buttons==4 and c.bar3Rows==4 and Bar(3).header.width==40 and Bar(3).header.height==166,
    "changing button count keeps a vertical bar in one column")
assert(horizontal.set(true) and not c.bar3Vertical and c.bar3Rows==1 and horizontal.get() and not vertical.get(),
    "horizontal popup control makes a single row")
assert(Bar(3).header.width==166 and Bar(3).header.height==40,"horizontal popup control lays out the bar")
assert(PopupControl(element,"rows").set(2) and not horizontal.get() and not vertical.get(),
    "custom grids remain available without a misleading orientation selection")
local mouseover=PopupControl(element,"mouseover")
assert(S.Set("actionbars","bar3Visibility",2) and not mouseover.get())
mouseover.set(true);assert(c.bar3Visibility==5,"mouseover keeps the combat rule")
mouseover.set(false);assert(c.bar3Visibility==2)
local popupState=element.captureState()
assert(popupState.values.bar3Buttons==4 and popupState.values.bar3Rows==2
    and popupState.values.bar3Visibility==2, "Edit Mode omitted popup settings from history")
assert(S.SetMany("actionbars",{bar3Buttons=6,bar3Rows=3,bar3Size=51,bar3Spacing=5,bar3Visibility=4})
    and element.restoreState(popupState)
    and c.bar3Buttons==4 and c.bar3Rows==2 and c.bar3Size==40
    and c.bar3Visibility==2, "Edit Mode undo did not restore popup controls")
assert(S.ActionBarAvailable(8) and not S.ActionBarAvailable(13))
assert(S.OpenQuickKeybind() and quick.shown and quick.shownSecurely,"quick keybind opens through the restricted environment")
combat=true;assert(not S.OpenQuickKeybind());combat=false

------------------------------------------------------------------ disable and re-enable
do
    local oldForever,oldInput,oldPad=Suite.Client.isForever,InputUtil,C_GamePad
    local input,devices=true,{1}
    Suite.Client.isForever=true
    InputUtil={IsGamepadUIEnabled=function() return input end}
    C_GamePad={GetAllDeviceIDs=function() return devices end}
    assert(S.SetMany("actionbars",{bar1Visibility=1,bar1HideGamepad=true,bar2Visibility=1,bar2HideGamepad=false}))
    RunTimers()
    assert(not Bar(1).header.shown and Bar(2).header.shown,"connected active gamepad only hides selected bars")
    devices={};Event("GAME_PAD_DISCONNECTED")
    assert(Bar(1).header.shown,"disconnect restores the normal visibility driver")
    devices={1};input=false;Event("INPUT_DEVICE_INTERFACE_TRANSITION")
    assert(Bar(1).header.shown,"connected inactive gamepad leaves bars visible")
    input=true;combat=true
    local oldQueue,queued=S.Queue,nil
    S.Queue=function(id) queued=id;return oldQueue(id) end
    Event("GAME_PAD_ACTIVE_CHANGED")
    S.Queue=oldQueue
    assert(queued=="actionbars" and Bar(1).header.shown,"combat gamepad changes defer protected visibility")
    combat=false;S.Apply("actionbars")
    assert(not Bar(1).header.shown,"the deferred gamepad visibility applies outside combat")
    combat=true;devices={};Event("GAME_PAD_DISCONNECTED")
    devices={1};Event("GAME_PAD_CONNECTED");devices={};Event("GAME_PAD_DISCONNECTED")
    combat=false;S.Apply("actionbars")
    assert(Bar(1).header.shown,"combat exit uses the latest connected device state")
    Suite.Client.isForever=oldForever
    InputUtil,C_GamePad=oldInput,oldPad
    assert(S.Set("actionbars","bar1HideGamepad",false));RunTimers()
    assert(Bar(1).header.shown and not M.context.frame.events.GAME_PAD_ACTIVE_CHANGED,"other client flavors release gamepad triggers")
end
local clears=overrideClears
local enabledEvents=triggered[BINDINGS_EVENT] or 0
-- Every release step runs isolated: the first one raising is reported, and
-- the steps after it still stop paging, hide the bars, clear the override
-- bindings and tell the cooldown manager (asserted below).
do
    local stopDispatcher,errors=AB.StopDispatcher,#dispatch.errors
    AB.StopDispatcher=function() error("dispatcher stop failed") end
    dispatch.expect=true
    assert(S.Set("actionbars","enabled",false))
    dispatch.expect=false
    AB.StopDispatcher=stopDispatcher
    assert(#dispatch.errors==errors+1 and dispatch.errors[errors+1]:find("dispatcher stop failed",1,true),
        "the raising release step was not reported")
    stopDispatcher()
end
assert((triggered[BINDINGS_EVENT] or 0)>enabledEvents and not S.ActionBarsBindingForSpell(1001),
    "stopping the bars did not tell the cooldown manager its key texts changed")
assert(overrideClears==clears+1 and not next(overrides),"disable clears override bindings")
assert(S.Status("actionbars")==AB.RELOAD_MESSAGE,"reload message after disable")
for index=1,12 do assert(not Bar(index).header.shown,"suite bars hide on disable") end
assert(not next(M.context.frame.events),"no events while disabled")
assert(AB.Diagnostics.RangeReferences()==0)
local count=created
assert(S.Set("actionbars","enabled",true))
RunTimers()
assert(created==count,"re-enable reuses frames")
assert(Bar(1).header.shown and overrides["CTRL-BUTTON4"]=="MSUFSuiteBar9Button1" and S.Status("actionbars")=="Active")
assert(MultiBarBottomLeft.reparented==1 and ActionButton5.hideCalls==1,"disposal ran once per session")
print("Action bars: secure disposal, import, owned buttons, paging (vehicle, forms, opt-outs, modifiers), routing, click and drag wraps, grid reveal, visibility and mouseover, dispatcher dedupe/cap/secrets, range, glows, style, movers, quick keybind, disable and re-enable passed")
