local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Sounds and speech. Ready alerts for cooldowns play from Lua with a 1 s
-- throttle per entry; aura gain and loss sounds from files are registered
-- with C_UnitAuras.AddAuraSound, so Blizzard plays them without any Lua per
-- aura event. That API takes files only: sound kits (Blizzard's Cooldown
-- Manager sounds) on aura entries play from a sensor in the aura button
-- (Auras.lua) through PlayAura. Nothing plays while muted or during the
-- short silence after a loading screen (C.state.soundQuietUntil, set by the
-- controller).
local L={pending=false}
C.Alerts=L

local GetTime,InCombatLockdown=GetTime,InCombatLockdown
local pairs,type,tonumber=pairs,type,tonumber
local wipe=table.wipe or wipe
local Public=S.Public
local EMPTY=C.EMPTY or {}
local THROTTLE=1
-- Container switches (ours, or an ancestor such as the UI being hidden for
-- a cinematic) show and hide aura buttons: their sensors keep quiet this
-- long after one.
local HUSH=.3
local TRIGGER=_G.Enum and _G.Enum.UnitAuraSoundTrigger or EMPTY
local ADDED,REMOVED=TRIGGER.Added or 0,TRIGGER.Removed or 2

local kinds,args={},{}                   -- parsed sound values, once per distinct value
local last=setmetatable({},{__mode="k"}) -- entry -> time of its last ready alert
local gained,lost={},{}                  -- entry key -> time of its last kit gain / loss sound
-- Kit edges wait one frame (FlushAura): entry key -> frame time of the
-- edge, and the hush gate of the container that heard it.
local gainAt,lossAt,gainGate,lossGate={},{},{},{}
local anyGate={}                         -- hush gate for callers without their own
local flushArmed=false
local have={}                            -- registration key -> {id, refs}
local want={}                            -- scratch: registration key -> refs
local regs={}                            -- registration key -> what to register
local info={}                            -- reused UnitAuraSoundInfo
local armed=false

------------------------------------------------------------------ sound values
-- "lsm:<name>", "kit:<soundKitID>", "file:<fileID>"; anything else is silent.
local function Parse(value)
    local kind=kinds[value]
    if kind~=nil then return kind,args[value] end
    kind=false
    if type(value)=="string" then
        local prefix,rest=value:match("^(%l+):(.+)$")
        if prefix=="lsm" then
            kind,args[value]="lsm",rest
        elseif prefix=="kit" or prefix=="file" then
            local id=tonumber(rest)
            if id and id>0 and id%1==0 then kind,args[value]=prefix,id end
        end
    end
    kinds[value]=kind
    return kind,args[value]
end

-- LibSharedMedia path or file ID; LSM maps its "None" entry to 1.
local function Media(name)
    local stub=_G.LibStub
    local media=type(stub)=="table" and type(stub.GetLibrary)=="function" and stub:GetLibrary("LibSharedMedia-3.0",true)
    local path=media and media:Fetch("sound",name,true)
    if type(path)=="string" and path~="" then return path end
    if type(path)=="number" and path>1 then return path end
end

local function Channel()
    local channel=C.state.soundChannel
    return (channel=="SFX" or channel=="Dialog") and channel or "Master"
end

local function Emit(value)
    local kind,arg=Parse(value)
    if not kind then return false end
    local channel=Channel()
    if kind=="kit" then
        return type(PlaySound)=="function" and PlaySound(arg,channel)==true
    end
    if kind=="lsm" then
        arg=Media(arg)
        if not arg then return false end
    end
    return type(PlaySoundFile)=="function" and PlaySoundFile(arg,channel)==true
end

-- Blizzard's text-to-speech with the player's chosen voice, rate and volume.
local function Speak(text)
    local voice,tts=_G.C_VoiceChat,_G.C_TTSSettings
    if type(text)~="string" or text=="" or not Public(text) then return false end
    if not (voice and type(voice.SpeakText)=="function") then return false end
    local id,rate,volume=0,0,100
    if tts then
        local types=_G.Enum and _G.Enum.TtsVoiceType
        if tts.GetVoiceOptionID then id=tts.GetVoiceOptionID(types and types.Standard or 0) or 0 end
        if tts.GetSpeechRate then rate=tts.GetSpeechRate() or 0 end
        if tts.GetSpeechVolume then volume=tts.GetSpeechVolume() or 100 end
    end
    voice.SpeakText(id,text,rate,volume,true)
    return true
end

-- Options preview: force plays even while muted or in the quiet window.
function L.Play(value,force)
    if type(value)~="string" or value=="" then return false end
    if not force then
        local st=C.state
        if st.muteSounds or GetTime()<(st.soundQuietUntil or 0) then return false end
    end
    return Emit(value)
end

-- A cooldown became ready (called by the time layer on the edge). Aura
-- entries sound through their native registrations instead.
function L.Ready(entry)
    local ov=entry and entry.ov
    if not ov or entry.family==2 then return end
    local sound,tts=ov.sound,ov.tts==true
    if sound=="" then sound=nil end
    if not sound and not tts then return end
    local st=C.state
    if st.muteSounds then return end
    local now=GetTime()
    if now<(st.soundQuietUntil or 0) then return end
    local prev=last[entry]
    if prev and now-prev<THROTTLE then return end
    last[entry]=now
    if sound then Emit(sound) end
    if tts then Speak(entry.name) end
end

------------------------------------------------------------------ aura kit sounds
-- "kit:<soundKitID>" values: aura entries play these from a sensor.
local function IsKit(value) return type(value)=="string" and Parse(value)=="kit" end
L.IsKit=IsKit

-- A container was switched (retarget, pause, rebuild, bar or UI shown or
-- hidden): its buttons shown or hidden now are no aura gains or losses.
-- gate: the container's record (fields hushFrom, hushUntil), so a retarget
-- never silences the player's buffs. Overlapping hushes merge into one
-- window; GetTime() is the frame's time, so a hush later in the same frame
-- still covers an edge heard before it.
local function Hush(gate)
    gate=gate or anyGate
    local now=GetTime()
    local till=gate.hushUntil
    if not till or now>till then gate.hushFrom=now end
    gate.hushUntil=now+HUSH
end
L.Hush=Hush
local function Hushed(gate,at)
    local from=gate and gate.hushFrom
    return from~=nil and at>=from and at<gate.hushUntil
end

-- One kit edge after its frame: mute, the quiet window after a loading
-- screen, the container's hush and a 1 s throttle per entry and direction.
local function Settle(key,at,loss,gate)
    local e=C.entries[key]
    local ov=e and e.ov
    if not ov or ov==EMPTY or e.family==1 then return end
    local value
    if loss then value=ov.lossSound else value=ov.sound end
    if not IsKit(value) then return end
    local st=C.state
    if st.muteSounds or at<(st.soundQuietUntil or 0) or Hushed(gate,at) or Hushed(anyGate,at) then return end
    local now=GetTime()
    local seen=loss and lost or gained
    local prev=seen[key]
    if prev and now-prev<THROTTLE then return end
    seen[key]=now
    Emit(value)
end

-- Next frame: an entry heard both hiding and showing is a button reset (a
-- full aura rebuild releases and re-acquires every button in one pass, and
-- a new aura instance swaps buttons), not a change: both edges drop.
local function FlushAura()
    flushArmed=false
    for key,at in pairs(gainAt) do
        gainAt[key]=nil
        local gate=gainGate[key]
        gainGate[key]=nil
        if lossAt[key] then lossAt[key],lossGate[key]=nil,nil
        else Settle(key,at,false,gate) end
    end
    for key,at in pairs(lossAt) do
        lossAt[key]=nil
        local gate=lossGate[key]
        lossGate[key]=nil
        Settle(key,at,true,gate)
    end
end

-- A sensor saw an aura entry's button show ("gain") or hide ("loss"). Only
-- entries with a kit value listen (files are native registrations); the
-- edge is decided one frame later (FlushAura). No aura data is read: the
-- sensor only knows it showed. Returns whether the edge was taken.
function L.PlayAura(key,which,gate)
    local e=type(key)=="string" and C.entries[key]
    local ov=e and e.ov
    if not ov or ov==EMPTY or e.family==1 then return false end
    if not (IsKit(ov.sound) or IsKit(ov.lossSound)) then return false end
    local st=C.state
    local now=GetTime()
    if st.muteSounds or now<(st.soundQuietUntil or 0) then return false end
    if which=="loss" then lossAt[key],lossGate[key]=now,gate
    else gainAt[key],gainGate[key]=now,gate end
    if flushArmed then return true end
    local timer=_G.C_Timer
    if timer and timer.After then
        flushArmed=true
        timer.After(0,FlushAura)
    else
        FlushAura()
    end
    return true
end

------------------------------------------------------------------ aura sounds
-- Registrations are counted per (unit, spell, trigger, channel, sound):
-- entries sharing one keep a single native registration.
local function Wanted(set,unit,trigger,channel,value)
    for spell in pairs(set) do
        local key=unit.."\031"..spell.."\031"..trigger.."\031"..channel.."\031"..value
        want[key]=(want[key] or 0)+1
        if not regs[key] then regs[key]={unit=unit,spell=spell,trigger=trigger,channel=channel,value=value} end
    end
end
local function Want(e,trigger,value,channel)
    if type(value)~="string" or value=="" then return end
    -- AddAuraSound takes files only; sound kits cannot be registered.
    -- Kits play from the aura button's sensor instead (PlayAura).
    local kind=Parse(value)
    if kind~="lsm" and kind~="file" then return end
    local auras=C.Auras
    local set=auras and auras.Ids(e)
    if not set then return end
    local unit=auras.UnitOf(e)
    if unit~="both" then return Wanted(set,unit,trigger,channel,value) end
    -- Blizzard entries watch the player and the target ("both" is no unit
    -- token). A native sound cannot check the caster or the target's
    -- disposition, so a self aura keeps to the player: a target
    -- registration would sound it again for a friendly target or yourself.
    Wanted(set,"player",trigger,channel,value)
    if not e.selfAura then Wanted(set,"target",trigger,channel,value) end
end

local function Register(add,reg)
    local kind,file=Parse(reg.value)
    if kind=="lsm" then file=Media(file) end
    if not file then return nil end
    info.unitToken,info.spellID,info.outputChannel=reg.unit,reg.spell,reg.channel
    if type(file)=="number" then info.soundFileID,info.soundFileName=file,nil
    else info.soundFileName,info.soundFileID=file,nil end
    local id=add(reg.trigger,info)
    if Public(id) and type(id)=="number" then return id end
end

local function QuietOver()
    armed=false
    if not L.released then L.SyncAuraSounds() end
end
local function Arm(wait)
    local timer=_G.C_Timer
    if armed or not (timer and timer.After) then return end
    armed=true
    timer.After(wait+.05,QuietOver)
end

-- Cold: after resolve, spell choices, mute/channel changes and loading
-- screens. Out of combat only; in combat it waits for FlushPending.
function L.SyncAuraSounds()
    L.released=false
    local auras=_G.C_UnitAuras
    local add,remove=auras and auras.AddAuraSound,auras and auras.RemoveAuraSound
    if type(add)~="function" or type(remove)~="function" then return end
    if InCombatLockdown() then L.pending=true;return end
    L.pending=false
    wipe(want)
    local st=C.state
    -- Inside the quiet window every registration is dropped and comes back
    -- when the window ends, so a loading screen cannot replay gain sounds.
    local wait=(st.soundQuietUntil or 0)-GetTime()
    if not st.muteSounds and wait<=0 then
        local channel=Channel()
        for _,plan in pairs(C.plans) do
            if plan.kind~=1 then
                local entries=plan.entries
                for i=1,#entries do
                    local e=entries[i]
                    local ov=e.ov
                    if ov and ov~=EMPTY and e.src~="p" and e.family~=1 then
                        Want(e,ADDED,ov.sound,channel)
                        Want(e,REMOVED,ov.lossSound,channel)
                    end
                end
            end
        end
    end
    for key,reg in pairs(have) do
        if not want[key] then
            have[key]=nil
            remove(reg.id)
        end
    end
    for key,refs in pairs(want) do
        local reg=have[key]
        if reg then
            reg.refs=refs
        else
            local id=Register(add,regs[key])
            if id then have[key]={id=id,refs=refs} end
        end
    end
    if wait>0 and not st.muteSounds then Arm(wait) end
end

function L.ReleaseAll()
    local auras=_G.C_UnitAuras
    local remove=auras and auras.RemoveAuraSound
    for key,reg in pairs(have) do
        have[key]=nil
        if remove then remove(reg.id) end
    end
    wipe(gained)
    wipe(lost)
    wipe(gainAt);wipe(lossAt);wipe(gainGate);wipe(lossGate)
    L.pending=false
    L.released=true
end

-- Diagnostics and tests: live native registrations and their counts.
function L.Registrations()
    local n=0
    for _ in pairs(have) do n=n+1 end
    return n,have
end
