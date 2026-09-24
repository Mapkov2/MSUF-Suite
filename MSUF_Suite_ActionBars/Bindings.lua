local _,P=...;local NS,S=P.NS,P.Suite
-- Key routing. Bars 2-8 (and bar 1 while it follows Blizzard's page) keep
-- the native commands: the key fires the hidden Blizzard button, which is the
-- only queue-safe route for empowered spells and press-and-hold repeat.
-- One owner frame routes keys to the suite buttons with override click
-- bindings where a native command cannot express the slot: bars 9/10 (their
-- own commands), bar 1 with custom paging or paging opt-outs (Blizzard's
-- page would differ from the icons), and flyout slots (the flyout must open
-- on a visible button). Routing changes only out of combat; a signature
-- skips unchanged rebuilds.
local AB=P.ActionBars
local M=AB.M
local concat=table.concat

local function Keys(command,...)
    if type(GetBindingKey)~="function" then return end
    return GetBindingKey(command,...)
end

-- Short key text: CTRL/ALT/SHIFT/META become C/A/S/M, mouse buttons M4,
-- wheel MwU/MwD, numpad N1 and N+ style. Gamepad keys keep Blizzard's glyph
-- markup. No range dot.
local NAMED={MOUSEWHEELUP="MwU",MOUSEWHEELDOWN="MwD",MIDDLEMOUSE="M3",CAPSLOCK="Caps",SPACE="Spc",BACKSPACE="Bs",
    INSERT="Ins",DELETE="Del",HOME="Hm",END="End",PAGEUP="PU",PAGEDOWN="PD",ESCAPE="Esc",ENTER="Ent",TAB="Tab",
    NUMPADDECIMAL="N.",NUMPADPLUS="N+",NUMPADMINUS="N-",NUMPADMULTIPLY="N*",NUMPADDIVIDE="N/",
    UP="Up",DOWN="Dn",LEFT="Lt",RIGHT="Rt"}
local MODIFIERS={SHIFT="S",CTRL="C",ALT="A",META="M"}
local textCache={}
function AB.KeyText(key)
    if type(key)~="string" or key=="" then return "" end
    local cached=textCache[key]
    if cached then return cached end
    local text
    if key:find("PAD",1,true) and not key:find("NUMPAD",1,true) and type(GetBindingText)=="function" then
        text=GetBindingText(key,true)
    else
        local mods,base="",key
        while true do
            local mod,rest=base:match("^(%u+)%-(.+)$")
            local short=mod and MODIFIERS[mod]
            if not short then break end
            mods,base=mods..short,rest
        end
        local short=NAMED[base] or base:match("^BUTTON(%d+)$") and "M"..base:match("^BUTTON(%d+)$")
            or base:match("^NUMPAD(%d)$") and "N"..base:match("^NUMPAD(%d)$")
        text=mods..(short or base)
    end
    textCache[key]=text
    return text
end

function AB.BindingText(rec)
    return AB.KeyText((Keys(rec.command)))
end

local function IsFlyout(slot)
    if not slot or type(GetActionInfo)~="function" then return false end
    local kind=GetActionInfo(slot)
    return S.Public(kind) and kind=="flyout"
end
AB.IsFlyoutSlot=IsFlyout

-- Whether a suite button's keys must click it instead of the native command.
function AB.ClickRouted(rec)
    local index=rec.bar.index
    if index>=9 then return true end
    if index==1 and AB.CustomPaging(M.config) then return true end
    return IsFlyout(rec.slot) or IsFlyout(rec.base)
end

local parts={}
-- Rebuilds the override click bindings. Out of combat only: in combat the
-- rebuild waits for PLAYER_REGEN_ENABLED.
function AB.UpdateRouting(force)
    if not M.active then return end
    if NS.IsCombatLocked() or type(SetOverrideBindingClick)~="function" then AB.routingPending=true;return end
    AB.routingPending=nil
    local count=0
    for i=1,#AB.owned do
        local rec=AB.owned[i]
        if AB.ClickRouted(rec) then
            local a,b=Keys(rec.command)
            if a then count=count+1;parts[count]=a.."\1"..rec.name end
            if b then count=count+1;parts[count]=b.."\1"..rec.name end
        end
    end
    for i=count+1,#parts do parts[i]=nil end
    local signature=concat(parts,"\2")
    if not force and signature==AB.routingSignature then return end
    AB.routingSignature=signature
    local owner=AB.bindingOwner
    if not owner then owner=S.CreateFrame("Frame");AB.bindingOwner=owner end
    ClearOverrideBindings(owner)
    for i=1,count do
        local key,name=parts[i]:match("^(.-)\1(.+)$")
        SetOverrideBindingClick(owner,false,key,name,"Keybind")
    end
end

function AB.ClearRouting()
    if AB.bindingOwner and type(ClearOverrideBindings)=="function" then ClearOverrideBindings(AB.bindingOwner) end
    AB.routingSignature,AB.routingPending=nil,nil
end

-- Mirrors ActionButtonUseKeyDown and the action bar lock onto the secure
-- grid controller read by the click and drag wraps.
function AB.UpdateClickAttributes()
    local grid=AB.grid
    if not grid or NS.IsCombatLocked() then return end
    local keydown=type(GetCVarBool)=="function" and GetCVarBool("ActionButtonUseKeyDown") and true or false
    local unlocked=not (type(GetCVarBool)=="function" and GetCVarBool("lockActionBars"))
    if grid:GetAttribute("keydown")~=keydown then grid:SetAttribute("keydown",keydown) end
    if grid:GetAttribute("unlocked")~=unlocked then grid:SetAttribute("unlocked",unlocked) end
end

-- Native keys press the hidden Blizzard button, so the visible suite button
-- gets its pushed state from post-hooks on Blizzard's binding handlers. The
-- Up hooks restore it; no polling.
local NATIVE_BAR={}
for index=2,8 do NATIVE_BAR[AB.NATIVE_BARS[index]]=index end
local function Native(index,id,down)
    if not M.active then return end
    local bar=AB.bars[index]
    local rec=bar and bar.buttons[tonumber(id) or 0]
    if not rec or AB.ClickRouted(rec) then return end
    if AB.SetPushed then AB.SetPushed(rec,down) end
end
function AB.HookNativePresses()
    if AB.nativeHooked or type(hooksecurefunc)~="function" then return end
    AB.nativeHooked=true
    if type(ActionButtonDown)=="function" then
        hooksecurefunc("ActionButtonDown",function(id) Native(1,id,true) end)
    end
    if type(ActionButtonUp)=="function" then
        hooksecurefunc("ActionButtonUp",function(id) Native(1,id,false) end)
    end
    if type(MultiActionButtonDown)=="function" then
        hooksecurefunc("MultiActionButtonDown",function(bar,id) local index=NATIVE_BAR[bar];if index then Native(index,id,true) end end)
    end
    if type(MultiActionButtonUp)=="function" then
        hooksecurefunc("MultiActionButtonUp",function(bar,id) local index=NATIVE_BAR[bar];if index then Native(index,id,false) end end)
    end
end
