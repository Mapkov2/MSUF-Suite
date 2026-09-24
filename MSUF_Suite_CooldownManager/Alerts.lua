local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Sounds and speech. Ready alerts for cooldowns play from Lua with a 1 s
-- throttle per entry; aura gain and loss sounds are registered with
-- C_UnitAuras.AddAuraSound, so Blizzard plays them without any Lua per aura
-- event. Nothing plays while muted or during the short silence after a
-- loading screen (C.state.soundQuietUntil, set by the controller).
local L={pending=false}
C.Alerts=L

local GetTime,InCombatLockdown=GetTime,InCombatLockdown
local pairs,type,tonumber=pairs,type,tonumber
local wipe=table.wipe or wipe
local Public=S.Public
local EMPTY=C.EMPTY or {}
local THROTTLE=1
local TRIGGER=_G.Enum and _G.Enum.UnitAuraSoundTrigger or EMPTY
local ADDED,REMOVED=TRIGGER.Added or 0,TRIGGER.Removed or 2

local kinds,args={},{}                   -- parsed sound values, once per distinct value
local last=setmetatable({},{__mode="k"}) -- entry -> time of its last ready alert
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
    L.pending=false
    L.released=true
end

-- Diagnostics and tests: live native registrations and their counts.
function L.Registrations()
    local n=0
    for _ in pairs(have) do n=n+1 end
    return n,have
end
