local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Sounds and speech. Ready alerts for cooldowns play from Lua with a 1 s
-- throttle per entry; aura gain and loss sounds from files are registered
-- with C_UnitAuras.AddAuraSound, so Blizzard plays them without any Lua per
-- aura event. Known Blizzard CDM kits resolve to their sound files; only
-- unknown kits need the aura-button sensor (Auras.lua) through PlayAura.
-- Nothing plays while muted or during the short silence after a loading
-- screen (C.state.soundQuietUntil, set by the controller).
local L={pending=false}
C.Alerts=L

local GetTime,InCombatLockdown=GetTime,InCombatLockdown
local pairs,type,tonumber=pairs,type,tonumber
local wipe=C.wipe
local Public=S.Public
local EMPTY=C.EMPTY
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
local kitParams={}                       -- reused Blizzard cooldown alert params
local armed=false

-- Retail SoundKitEntry.db2, build 12.1.0.69933: the FileDataID behind each
-- kit offered by Blizzard's Cooldown Viewer. Forever 1.60.1.70009 has the
-- same files: 67 mappings match its SoundKitEntry.db2, and the remaining 26
-- Short sound files are present in its CASC although their kits are absent
-- from that table. Each mapped kit has one file.
-- Files can be played by the same runtime path as SharedMedia and registered
-- with C_UnitAuras.AddAuraSound; unknown kits retain the PlaySound fallback.
-- Data: https://wago.tools/db2/SoundKitEntry/csv?build=12.1.0.69933
-- PATCH CHECK: After Retail or Forever patches, compare Blizzard's
-- CooldownViewerSoundAlertData.lua with SoundKitEntry.db2 in both clients;
-- also check that the Forever Short files remain in CASC. Update this map
-- when kits or FileDataIDs change, then test cooldown-ready and aura gain/loss
-- playback in each game client. These IDs are client assets, not user files.
local KIT_FILE={
    [316401]=7466002,[316406]=7466004,[316407]=7466006,[316409]=7466010,
    [316411]=7466012,[316412]=7466014,[316413]=7466016,[316414]=7466018,
    [316415]=7466020,[316419]=7466026,[316425]=7466036,[316430]=7466046,
    [316433]=7466048,[316434]=7466050,[316436]=7466054,[316442]=7466062,
    [316446]=7466070,[316447]=7466072,[316453]=7466082,[316460]=7466092,
    [316476]=7466096,[316477]=7466098,[316482]=7466108,[316484]=7466112,
    [316486]=7466116,[316492]=7466124,[316493]=7466126,[316501]=7466138,
    [316509]=7466148,[316528]=7466899,[316531]=7466901,[316532]=7466903,
    [316535]=7466911,[316536]=7466913,[316540]=7466915,[316712]=7466945,
    [316713]=7466947,[316715]=7466951,[316717]=7466955,[316718]=7466957,
    [316719]=7466959,[316722]=7466965,[316723]=7466967,[316731]=7467017,
    [316733]=7467021,[316735]=7467023,[316736]=7467025,[316737]=7467027,
    [316738]=7467029,[316739]=7467031,[316740]=7467033,[316745]=7464792,
    [316746]=7464794,[316748]=7464798,[316749]=7464800,[316765]=7467074,
    [316766]=7467076,[316768]=7467080,[316769]=7467082,[316770]=7467072,
    [316771]=7467084,[316773]=7467088,[316774]=7467090,[316775]=7467092,
    [316776]=7467094,[316778]=7467098,[316779]=7467100,[353387]=7962208,
    [353388]=7962210,[353389]=7962212,[353392]=7962218,[353393]=7962222,
    [353395]=7962224,[353397]=7962228,[353399]=7962230,[353400]=7962232,
    [353402]=7962234,[353404]=7962236,[353405]=7962238,[353406]=7962240,
    [353407]=7962242,[353408]=7962244,[353410]=7962246,[353417]=7962256,
    [353419]=7962258,[353420]=7962260,[353421]=7962262,[353423]=7962266,
    [353424]=7962220,[353425]=7962248,[353426]=7962268,[353427]=7962270,
    [353428]=7962272,
}
local kitFiles=KIT_FILE

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
        local file=kitFiles[arg]
        if file and type(PlaySoundFile)=="function" and PlaySoundFile(file,channel)==true then return true end
        local sound=_G.C_Sound
        if sound and type(sound.PlaySoundWithOptions)=="function" then
            kitParams.soundKitID,kitParams.uiSoundSubType=arg,channel
            return sound.PlaySoundWithOptions(kitParams)==true
        end
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
local function IsKit(value)
    if type(value)~="string" then return false end
    local kind,id=Parse(value)
    return kind=="kit" and kitFiles[id]==nil
end
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
    -- The shipped CDM kits resolve to files. Unknown kits still play from
    -- the aura button's sensor instead (PlayAura).
    local kind,id=Parse(value)
    if kind~="lsm" and kind~="file" and not (kind=="kit" and kitFiles[id]) then return end
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
    if kind=="kit" then file=kitFiles[file] end
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
    local secrets=_G.C_Secrets
    local restricted=secrets and secrets.ShouldAurasBeSecret and secrets.ShouldAurasBeSecret()
    if restricted~=nil and (not Public(restricted) or restricted) then L.pending=true;return end
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
            if not id then L.pending=true end
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
