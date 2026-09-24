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

------------------------------------------------------------------ clock, timers, combat
local combat,secure=false,0
local now=100
InCombatLockdown=function() return combat end
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
function Region:SetPoint(...) self.points[#self.points+1]={...} end
function Region:ClearAllPoints() self.points={} end
function Region:SetAllPoints(target) self.points={{"ALL",target}} end
function Region:SetSize(w,h) self.width,self.height=w,h end
function Region:SetWidth(w) self.width=w end
function Region:SetHeight(h) self.height=h end
function Region:SetDrawLayer() end
function Region:SetBlendMode(mode) self.blend=mode end
function Region:GetBlendMode() return self.blend or "BLEND" end
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
local function NewFrame(kind,name,parent,templates)
    nextId=nextId+1;created=created+1
    local frame=setmetatable({kind=kind,name=name,id=nextId,attrs={},scripts={},hooks={},children={},points={},events={},
        shown=true,alpha=1,width=0,height=0,mouse=true,level=1},Frame)
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
function Frame:Show()
    Guard(self,"Show")
    local was=Visible(self)
    self.shown=true
    if not was and Visible(self) then Fire(self,"OnShow") end
end
function Frame:Hide()
    Guard(self,"Hide")
    self.hideCalls=(self.hideCalls or 0)+1
    local was=Visible(self)
    self.shown=false
    if was then Fire(self,"OnHide") end
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
function Frame:SetFrameLevel(value) self.level=value end
function Frame:GetFrameLevel() return self.level end
function Frame:RegisterForClicks(...) self.clickTypes={...} end
function Frame:RegisterForDrag() end
function Frame:GetID() return 0 end
function Frame:SetChecked(value) assert(not IsSecret(value));self.checked=value and true or false end
function Frame:GetChecked() return self.checked end
function Frame:SetButtonState(state) self.state=state end
function Frame:GetNormalTexture() return self.NormalTexture end
function Frame:GetPushedTexture() return self.PushedTexture end
function Frame:GetHighlightTexture() return self.HighlightTexture end
function Frame:GetCheckedTexture() return self.CheckedTexture end
function Frame:CreateTexture(_,layer) local region=NewRegion("Texture",self);region.layer=layer;return region end
function Frame:CreateFontString(_,layer) local region=NewRegion("FontString",self);region.layer=layer;return region end
-- Cooldown sinks. SetCooldown refuses secrets (AllowedWhenUntainted).
function Frame:SetCooldown(start,duration,modRate)
    assert(not IsSecret(start) and not IsSecret(duration) and not IsSecret(modRate),"secret passed to SetCooldown")
    self.cooldown={start,duration};self.object=nil
end
function Frame:SetCooldownFromDurationObject(object) assert(type(object)=="table" and object.duration,"not a duration object");self.object=object;self.cooldown=nil end
function Frame:Clear() self.object,self.cooldown=nil,nil;self.clears=(self.clears or 0)+1 end
function Frame:SetSwipeColor(...) self.swipe={...} end
function Frame:SetDrawEdge() end
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
    for _,key in ipairs({"Count","HotKey","Name"}) do frame[key]=NewRegion("FontString",frame) end
    for _,key in ipairs({"cooldown","chargeCooldown","lossOfControlCooldown"}) do frame[key]=NewFrame("Cooldown",nil,frame) end
end
TEMPLATES.ActionButtonTemplate=function(frame)
    ActionRegions(frame)
    -- BaseActionButtonMixin_OnAttributeChanged -> UpdateFlyout.
    frame.scripts.OnAttributeChanged=function() flyoutUpdates=flyoutUpdates+1 end
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
SecureHandlerWrapScript=function(frame,script,header,pre)
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

------------------------------------------------------------------ client API
UIParent=NewFrame("Frame","UIParent")
UIParent.width,UIParent.height=1024,768
GetPhysicalScreenSize=function() return 1024,768 end
GameFontHighlightSmall={GetFont=function() return "Fonts\\FRIZQT__.TTF",12,"" end}
RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43}}
UnitClass=function() return "Warrior","WARRIOR" end
Enum={LuaCurveType={Step=1}}
local secretEval=false
local function Curve()
    local curve={points={}}
    function curve:SetType(value) self.type=value end
    function curve:AddPoint(x,y) assert(not IsSecret(x) and not IsSecret(y));self.points[#self.points+1]={x,y} end
    function curve:ClearPoints() self.points={} end
    return curve
end
C_CurveUtil={CreateCurve=Curve}
local function Duration(slot,ignoreGCD)
    local object={duration=true,slot=slot,ignoreGCD=ignoreGCD}
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
local calls,rangeEnabled,ranges={cooldown=0,usable=0,texture=0},{},{}
local rangeOn,rangeOff=0,0
C_ActionBar={
    HasAction=function(slot) return actions[slot]~=nil end,
    GetActionTexture=function(slot) calls.texture=calls.texture+1;local a=actions[slot];return a and a.texture end,
    GetActionDisplayCount=function(slot) local a=actions[slot];return a and a.count or "" end,
    GetActionCooldown=function(slot)
        calls.cooldown=calls.cooldown+1
        local a=actions[slot]
        return a and a.cooldown or {isActive=false,isEnabled=true,startTime=0,duration=0,modRate=1}
    end,
    GetActionCooldownDuration=function(slot,ignoreGCD) return Duration(slot,ignoreGCD) end,
    GetActionCharges=function(slot) local a=actions[slot];return a and a.charges or {isActive=false,maxCharges=1,currentCharges=1} end,
    GetActionChargeDuration=function(slot) return Duration(slot) end,
    GetActionLossOfControlCooldownInfo=function() return {isActive=false,shouldReplaceNormalCooldown=false} end,
    GetActionLossOfControlCooldownDuration=function(slot) return Duration(slot) end,
    IsUsableAction=function(slot) calls.usable=calls.usable+1;local a=actions[slot];if not a then return false,false end;return a.usable~=false,a.noMana==true end,
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
GetActionInfo=function(slot) local a=actions[slot];if a then return a.kind,a.id,a.sub end end
local overlayed,alerts={},{}
C_SpellActivationOverlay={IsSpellOverlayed=function(id) assert(not IsSecret(id));return overlayed[id]==true end}
ActionButtonSpellAlertManager={
    ShowAlert=function(_,button) alerts[button]=true end,
    HideAlert=function(_,button) alerts[button]=nil end,
}
local tooltip={}
GameTooltip={SetOwner=function(self,owner) self.owner=owner end,GetOwner=function(self) return self.owner end,
    SetAction=function(_,slot) tooltip.slot=slot end,Hide=function(self) self.owner=nil;tooltip.slot=nil end}
GameTooltip_SetDefaultAnchor=function(tip,owner) tip.owner=owner end
local bindings,overrides,overrideWrites,overrideClears={},{},0,0
GetBindingKey=function(command) local keys=bindings[command];if keys then return unpack(keys) end end
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
hooksecurefunc=function(name,hook)
    local original=assert(_G[name],"hook target "..name)
    _G[name]=function(...) original(...);hook(...) end
end
local native={}
ActionButtonDown=function(id) native[#native+1]="down"..id end
ActionButtonUp=function(id) native[#native+1]="up"..id end
MultiActionButtonDown=function(bar,id) native[#native+1]=bar..id end
MultiActionButtonUp=function() end
local editElements={}
MSUF_EditModeAPI={RegisterElement=function(owner,element) editElements[element.id]=element;return true end,
    RefreshOwner=function() end,UnregisterOwner=function() end,RegisterSessionListener=function() end,IsActive=function() return false end}
C_AddOns={IsAddOnLoaded=function() return false end,
    DoesAddOnExist=function(name) return type(name)=="string" and name:match("^MSUF_Suite")~=nil end}

------------------------------------------------------------------ Blizzard frames
local function Buttons(prefix,parent,count,small)
    for i=1,count do
        local button=NewFrame("CheckButton",prefix..i,parent,"SecureActionButtonTemplate")
        if small then ActionRegions(button) end
        button:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    end
end
local MainBar=NewFrame("Frame","MainActionBar",UIParent)
MainBar.implicit=true
MainBar.attrs.actionpage=1
MainBar.cx,MainBar.cy,MainBar.numRows,MainBar.numButtonsShowable,MainBar.isHorizontal,MainBar.buttonPadding=512,40,1,12,true,2
MainBar.ActionBarPageNumber={UpButton=NewFrame("Button",nil,MainBar),DownButton=NewFrame("Button",nil,MainBar)}
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
for _,file in ipairs({"Platform","Database","SuiteCatalog","Catalog/ActionBars","Suite","Bindings"}) do
    assert(loadfile(root.."/MSUF_Suite/Core/"..file..".lua"))("MSUF_Suite",Suite)
end
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil));Suite.Suite.Normalize(Suite.DB)
local private={}
local before=created
for _,file in ipairs({"Surfaces","Runtime","EditMode"}) do
    assert(loadfile(root.."/MSUF_Suite_Modules/"..file..".lua"))("MSUF_Suite_Modules",private)
end
for _,file in ipairs({"Bootstrap","Bars","Paging","Blizzard","Visibility",
    "Bindings","Style","Paint","Controller"}) do
    assert(loadfile(root.."/MSUF_Suite_ActionBars/"..file..".lua"))("MSUF_Suite_ActionBars",private)
end
assert(created==before,"loading the runtime created frames")
local S,AB=Suite.Suite,private.ActionBars
Suite.Client.isForever=true
assert(S.catalog.actionbars.available(),
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

------------------------------------------------------------------ paging
conditions["bar:2"]=true;barPage=2;Drivers();RunTimers()
assert(Bar(1).header.attrs.actionpage==2 and Button(1,1).button.attrs.action==13 and Button(1,1).slot==13)
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
combat=false
RunTimers()
-- Custom paging: modifiers and opt-outs stop the mirror and route bar 1 keys.
assert(S.SetMany("actionbars",{disableFormPaging=true}))
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
RunTimers()
local cooldownCalls=calls.cooldown
for _=1,5 do Event("ACTIONBAR_UPDATE_COOLDOWN") end
RunTimers()
local walk=calls.cooldown-cooldownCalls
assert(walk>0,"cooldown walk ran")
cooldownCalls=calls.cooldown
now=now+.2
Event("ACTIONBAR_UPDATE_COOLDOWN");Event("SPELL_UPDATE_COOLDOWN")
assert(#timers==1,"one flush per burst")
RunTimers()
assert(calls.cooldown-cooldownCalls==walk,"same-frame events share one walk")
cooldownCalls=calls.cooldown
local start=now
Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(calls.cooldown-cooldownCalls==walk and now>=start+.1-1e-9,"storm cap delays the next walk")
RunTimers()
-- Secret cooldowns: duration objects only, no comparisons.
actions[61].cooldown={isActive=true,isEnabled=true,startTime=Secret(),duration=Secret(),modRate=Secret()}
actions[61].charges={isActive=true,maxCharges=3,currentCharges=Secret(),cooldownStartTime=Secret(),cooldownDuration=Secret(),chargeModRate=Secret()}
actions[61].count=Secret()
actions[61].remaining=5
assert(S.SetMany("actionbars",{desaturateCooldown=true,cooldownAlpha=40,hideEmptyCharges=true}))
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");Event("SPELL_UPDATE_CHARGES");RunTimers()
assert(b61.cooldown.object and b61.cooldown.object.slot==61 and not b61.cooldown.cooldown,"secret cooldown via duration object")
assert(b61.chargeCooldown.object,"secret recharge via duration object")
assert(IsSecret(b61.Count.text) and b61.Count.alpha==1,"secret count reaches SetText only")
assert(b61.icon.desaturation==1 and b61.alpha==.4,"curve-driven cooldown feedback")
assert(AB.desatCurve.points[2][2]==1 and AB.alphaCurve.points[2][2]==.4)
secretEval=true
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(IsSecret(b61.icon.desaturation) and IsSecret(b61.alpha),"secret evaluations go straight to the sinks")
secretEval=false
Fire(b61.cooldown,"OnCooldownDone")
actions[61].remaining=0;actions[61].cooldown={isActive=false,isEnabled=true,startTime=0,duration=0,modRate=1}
Fire(b61.cooldown,"OnCooldownDone")
assert(b61.icon.desaturation==0 and b61.alpha==1 and b61.cooldown.clears,"cooldown end restores the button")
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
local references=AB.RangeReferences()
assert(references>0)
assert(S.Set("actionbars","bar2Visibility",6))
assert(not rangeEnabled[61] and AB.RangeReferences()<references,"hidden bars release range checks")
assert(S.Set("actionbars","bar2Visibility",1))
RunTimers()
assert(rangeEnabled[61],"shown bars re-acquire")
-- Proc glows by spell id; secret payloads fall back to a full rescan.
overlayed[61]=true
Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",61)
assert(alerts[b61],"Blizzard spell alert on the matching button")
overlayed[61]=nil
Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",61)
assert(not alerts[b61])
Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",Secret());RunTimers()
assert(S.Set("actionbars","procGlow",2))
overlayed[61]=true;Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",61)
assert(not alerts[b61] and Button(2,1).glowEdges and Button(2,1).glowEdges[1].shown,"pixel border glow")
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
assert(not M.context.frame.events.ACTION_RANGE_CHECK_UPDATE and AB.RangeReferences()==0,
    "disabled range coloring kept range checks or its event listener")
assert(S.Set("actionbars","rangeColoring",true));RunTimers()
assert(M.context.frame.events.ACTION_RANGE_CHECK_UPDATE and AB.RangeReferences()>0,
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
MultiActionButtonDown("MultiBarBottomLeft",1)
assert(b61.state=="PUSHED")
-- Checked state and equipped border.
actions[61].current=true;actions[61].equipped=true
Event("ACTIONBAR_UPDATE_STATE");Event("PLAYER_EQUIPMENT_CHANGED");now=now+1;RunTimers()
assert(b61.checked==true and b61.Border.shown)
assert(S.Set("actionbars","castHighlight",false));RunTimers()
assert(b61.checked==false)

------------------------------------------------------------------ plain (Classic) cooldowns
Suite.Client.hasSecrets=false
AB.ResolveAPI()
actions[61].cooldown={isActive=true,isEnabled=true,startTime=10,duration=8,modRate=1}
actions[61].remaining=nil
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(b61.cooldown.cooldown and b61.cooldown.cooldown[2]==8 and not b61.cooldown.object,"plain cooldown numbers")
assert(b61.icon.desaturation==1 and b61.alpha==.4)
actions[61].cooldown={isActive=true,isEnabled=true,startTime=10,duration=1.2,modRate=1}
now=now+1;Event("ACTIONBAR_UPDATE_COOLDOWN");RunTimers()
assert(b61.icon.desaturation==0 and b61.alpha==1,"the global cooldown is excluded")
Suite.Client.hasSecrets=true
AB.ResolveAPI()

------------------------------------------------------------------ style
assert(Button(2,1).button.icon.unmasked,"square icons drop the template mask")
assert(#Suite.ActionBarLookPresets == 3 or (Suite.ActionBarLookPresets[1]
    and Suite.ActionBarLookPresets[2] and Suite.ActionBarLookPresets[3]),
    "Action Bar Blue, Dark and Forever looks are missing")
assert(S.Config("actionbars").look == 2 and S.Config("actionbars").borderColor == "575b58",
    "new Retail Action Bars did not use Midnight Dark")
assert(Button(2,1).borderEdges[1].shown
    and math.abs(Button(2,1).borderEdges[1].color[1] - 87 / 255) < .01)
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

------------------------------------------------------------------ movers and exports
M:RegisterMovers()
local element=assert(editElements.bar3,"mover for bar 3")
assert(element.getFrame()==Bar(3).header and element.label=="Action bar 3" and #element.extraControls==7)
for _,control in ipairs(element.extraControls) do assert(#control.label<=40 and control.id:match("^[%w_]+$")) end
assert(element.isEnabled() and not editElements.bar6.isEnabled(),"Never bars have no mover")
local horizontal,vertical=element.extraControls[5],element.extraControls[6]
assert(S.SetMany("actionbars",{bar4Buttons=12,bar4Rows=1,bar4Vertical=true})
    and editElements.bar4.extraControls[5].get() and not editElements.bar4.extraControls[6].get(),
    "popup orientation follows the visible row even with column-first fill")
assert(horizontal.id=="horizontal" and vertical.id=="vertical" and horizontal.get() and not vertical.get(),
    "popup starts in horizontal layout")
assert(vertical.set(true) and c.bar3Vertical and c.bar3Rows==c.bar3Buttons and vertical.get() and not horizontal.get(),
    "vertical popup control makes a single column")
assert(Bar(3).header.width==40 and Bar(3).header.height==502,"vertical popup control lays out the bar")
assert(vertical.set(false)==false and vertical.get(),"active orientation cannot be deselected")
element.extraControls[1].set(4)
assert(c.bar3Buttons==4 and c.bar3Rows==4 and Bar(3).header.width==40 and Bar(3).header.height==166,
    "changing button count keeps a vertical bar in one column")
assert(horizontal.set(true) and not c.bar3Vertical and c.bar3Rows==1 and horizontal.get() and not vertical.get(),
    "horizontal popup control makes a single row")
assert(Bar(3).header.width==166 and Bar(3).header.height==40,"horizontal popup control lays out the bar")
assert(element.extraControls[2].set(2) and not horizontal.get() and not vertical.get(),
    "custom grids remain available without a misleading orientation selection")
local mouseover=element.extraControls[7]
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
local clears=overrideClears
assert(S.Set("actionbars","enabled",false))
assert(overrideClears==clears+1 and not next(overrides),"disable clears override bindings")
assert(S.Status("actionbars")==AB.RELOAD_MESSAGE,"reload message after disable")
for index=1,12 do assert(not Bar(index).header.shown,"suite bars hide on disable") end
assert(not next(M.context.frame.events),"no events while disabled")
assert(AB.RangeReferences()==0)
local count=created
assert(S.Set("actionbars","enabled",true))
RunTimers()
assert(created==count,"re-enable reuses frames")
assert(Bar(1).header.shown and overrides["CTRL-BUTTON4"]=="MSUFSuiteBar9Button1" and S.Status("actionbars")=="Active")
assert(MultiBarBottomLeft.reparented==1 and ActionButton5.hideCalls==1,"disposal ran once per session")
print("Action bars: secure disposal, import, owned buttons, paging (vehicle, forms, opt-outs, modifiers), routing, click and drag wraps, grid reveal, visibility and mouseover, dispatcher dedupe/cap/secrets, range, glows, style, movers, quick keybind, disable and re-enable passed")
