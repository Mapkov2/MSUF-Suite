local _,P=...;local NS,S=P.NS,P.Suite
-- Damage meter runtime. The DamageMeter/*.lua files share the private table
-- below. Loading them touches nothing in the client: frames, events and timers
-- exist only while the module is active and has something to show.
local D={windows={},MAX=5,KEYS={},OVERALL=0,CURRENT=1,AVOIDABLE=8,DEATHS=9,ENEMY=10}
P.DamageMeter=D
local M={cvars={damageMeterEnabled=true},styleGen=0,events={}}
D.M=M
local Public=S.Public
local floor,format,huge=math.floor,string.format,math.huge

-- Enum.DamageMeterType values are identical on every client (catalog choice
-- index = value + 1). Dps/Hps lead with the rate, like Blizzard's meter;
-- interrupts and dispels are plain counts.
D.perSecond={[1]=true,[3]=true}
D.countOnly={[5]=true,[6]=true}

-- Per-window setting names, built once so paint and visibility paths never
-- concatenate keys.
local suffixes={"Type","Session","Width","Height","X","Y","Locked","HideDungeon","HideRaid","HidePvP","HideWorld"}
for i=1,D.MAX do
    local keys={}
    for _,suffix in ipairs(suffixes) do keys[suffix]="w"..i..suffix end
    D.KEYS[i]=keys
end

function D.Plain(value)
    return Public(value) and type(value)=="number" and value==value and value~=huge and value~=-huge
end
-- Plain junk (nil, NaN) becomes 0; secret values pass through for C sinks.
function D.Num(value)
    if Public(value) and not D.Plain(value) then return 0 end
    return value
end
function D.Count(list)
    if type(list)~="table" then return 0 end
    local count=#list
    return Public(count) and count or 0
end
-- Ambiguate accepts secret names; its result goes directly to text sinks.
-- Character-count shortening remains limited to public strings.
function D.Short(name)
    if Public(name) and type(name)~="string" then return "" end
    local config=M.config
    if not (config and config.showRealm) then
        local ambiguate=_G.Ambiguate
        name=type(ambiguate)=="function" and ambiguate(name,"short") or name
    end
    if not Public(name) then return name end
    local maxChars=config and config.nameMaxChars or 0
    if maxChars<=0 then return name end
    local index,chars=1,0
    while index<=#name and chars<maxChars do
        local first=name:byte(index)
        local bytes=first<128 and 1 or first<224 and 2 or first<240 and 3 or 4
        index=index+bytes
        chars=chars+1
    end
    if index>#name then return name end
    return name:sub(1,index-1)..(config.nameEllipsis and "..." or "")
end

-- Plain amounts: three significant digits with K/M/B units. Called only when
-- a row's plain value changed.
function D.Compact(value)
    local sign=""
    if value<0 then sign,value="-",-value end
    if value<999.5 then return sign..floor(value+.5) end
    local unit,divisor="K",1e3
    if value>=999.5e6 then unit,divisor="B",1e9 elseif value>=999.5e3 then unit,divisor="M",1e6 end
    value=value/divisor
    return format(value<9.995 and "%s%.2f%s" or value<99.95 and "%s%.1f%s" or "%s%.0f%s",sign,value,unit)
end
function D.Clock(seconds)
    seconds=floor(seconds)
    if seconds>=3600 then return format("%d:%02d:%02d",floor(seconds/3600),floor(seconds/60)%60,seconds%60) end
    return format("%d:%02d",floor(seconds/60),seconds%60)
end

-- Blizzard ships localized meter strings with Blizzard_DamageMeter on every
-- client; English fallbacks go through the suite locale.
function D.Text(global,english)
    local value=global and _G[global]
    if type(value)=="string" and value~="" then return value end
    return S.Text(english)
end
local typeGlobals={"DAMAGE_METER_TYPE_DAMAGE_DONE","DAMAGE_METER_TYPE_DPS","DAMAGE_METER_TYPE_HEALING_DONE",
    "DAMAGE_METER_TYPE_HPS","DAMAGE_METER_TYPE_ABSORBS","DAMAGE_METER_TYPE_INTERRUPTS","DAMAGE_METER_TYPE_DISPELS",
    "DAMAGE_METER_TYPE_DAMAGE_TAKEN","DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN","DAMAGE_METER_TYPE_DEATHS",
    "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN"}
function D.TypeName(meterType)
    local labels=NS.DamageMeterTypeLabels
    return D.Text(typeGlobals[meterType+1],labels and labels[meterType+1] or "")
end
function D.Blocked() return S.Text("Details are available after combat.") end

function D.API()
    local api=_G.C_DamageMeter
    if type(api)=="table" and type(api.GetCombatSessionFromType)=="function" then return api end
end
function D.SessionTypes()
    local enum=type(Enum)=="table" and Enum.DamageMeterSessionType
    D.OVERALL=enum and enum.Overall or 0
    D.CURRENT=enum and enum.Current or 1
end
-- GetSessionDurationSeconds is not SecretWhenInCombat; the value is still checked.
function D.Duration(sessionType)
    local api=D.API()
    local get=api and api.GetSessionDurationSeconds
    if type(get)~="function" then return nil end
    local value=get(sessionType)
    if D.Plain(value) and value>=0 then return value end
end
-- A new Current session can lag the combat edge by a moment; the local
-- combat clock caps a stale reading from the previous fight.
function D.LiveDuration()
    local value=D.Duration(D.CURRENT)
    if not M.inCombat or not M.combatStart or type(GetTime)~="function" then return value end
    local elapsed=GetTime()-M.combatStart
    if not value or value>elapsed+2 then return elapsed end
    return value
end

function S.DamageMeterAvailability()
    local api=D.API()
    if not api or type(Enum)~="table" or type(Enum.DamageMeterType)~="table" then
        return false,S.Text("This client has no combat meter data")
    end
    if type(api.IsDamageMeterAvailable)=="function" then
        local ok,reason=api.IsDamageMeterAvailable()
        if Public(ok) and ok==false then
            if Public(reason) and type(reason)=="string" and reason~="" then return false,reason end
            return false,S.Text("Combat meter data is unavailable")
        end
    end
    return true
end

-- One C API call per paint. Edit Mode shows sample rows while there is no
-- data; the options preview always shows them.
function D.FetchSession(win)
    if M.preview then return D.Sample(win.meterType) end
    local api=D.API()
    if not api or not M.available then return nil end
    local session
    if win.sessionID then
        if type(api.GetCombatSessionFromID)~="function" then return nil end
        session=api.GetCombatSessionFromID(win.sessionID,win.meterType)
    else
        session=api.GetCombatSessionFromType(win.sessionType,win.meterType)
    end
    if type(session)~="table" then session=nil end
    if M.forced and D.Count(session and session.combatSources)==0 then return D.Sample(win.meterType) end
    return session
end
function D.FetchSource(win,guid,creature)
    local api=D.API()
    if not api or not (guid or creature) then return nil end
    local get=win.sessionID and api.GetCombatSessionSourceFromID or api.GetCombatSessionSourceFromType
    if type(get)~="function" then return nil end
    local source=get(win.sessionID or win.sessionType,win.meterType,guid,creature)
    return type(source)=="table" and source or nil
end
-- The source getters refuse secret arguments from addon code. Only plain
-- identities go back into the API; in combat that leaves the local player's
-- own row, mapped to UnitGUID("player"). nil,nil means "blocked".
function D.Identity(source)
    local guid,creature=source.sourceGUID,source.sourceCreatureID
    if not Public(guid) or type(guid)~="string" or guid=="" then guid=nil end
    if not D.Plain(creature) or creature<=0 then creature=nil end
    if not guid and not creature then
        local isLocal=source.isLocalPlayer
        if Public(isLocal) and isLocal==true and type(UnitGUID)=="function" then
            local own=UnitGUID("player")
            if Public(own) and type(own)=="string" and own~="" then guid=own end
        end
    end
    return guid,creature
end

local samples={}
local sampleClasses={"WARRIOR","MAGE","PRIEST","HUNTER","ROGUE","DRUID","PALADIN"}
-- Static sample sessions for Edit Mode and the options preview (built once).
function D.Sample(meterType)
    local kind=D.countOnly[meterType] and "count" or "amount"
    local sample=samples[kind]
    if sample then return sample end
    local names=_G.LOCALIZED_CLASS_NAMES_MALE
    local list,total={},0
    for i,class in ipairs(sampleClasses) do
        local amount=kind=="count" and 15-2*i or floor(52e6/(i+.35))
        local name=type(names)=="table" and names[class] or class
        list[i]={name=name,classFilename=class,specIconID=0,totalAmount=amount,amountPerSecond=amount/95,
            isLocalPlayer=i==3,deathRecapID=0,deathTimeSeconds=17*i}
        total=total+amount
    end
    sample={combatSources=list,maxAmount=list[1].totalAmount,totalAmount=total,durationSeconds=95,isSample=true}
    samples[kind]=sample
    return sample
end
-- Identity test: never probe fields that C-returned sessions do not define.
function D.IsSample(session)
    return session~=nil and (session==samples.count or session==samples.amount)
end

local groupIndex,groups={},{}
local function ByAmount(a,b) return a.amount>b.amount end
-- EnemyDamageTaken: one enemy's spells regrouped by the attacking unit. Plain
-- data only (scratch tables are reused); any secret field returns nil and the
-- caller falls back to the spell list rendered through sinks.
function D.GroupSpells(source)
    local spells=source and source.combatSpells
    local count=D.Count(spells)
    if count==0 then return nil end
    for key in pairs(groupIndex) do groupIndex[key]=nil end
    local n,sum=0,0
    for i=1,count do
        local spell=spells[i]
        local details=spell.combatSpellDetails
        local name,amount=details and details.unitName,spell.totalAmount
        if not Public(name) or type(name)~="string" or name=="" or not D.Plain(amount) then return nil end
        local entry=groupIndex[name]
        if not entry then
            n=n+1
            entry=groups[n] or {}
            groups[n],groupIndex[name]=entry,entry
            local class,spec=details.unitClassFilename,details.specIconID
            entry.name,entry.amount=name,0
            entry.class=Public(class) and type(class)=="string" and class or ""
            entry.spec=D.Plain(spec) and spec or 0
        end
        entry.amount=entry.amount+amount
        sum=sum+amount
    end
    for i=#groups,n+1,-1 do groups[i]=nil end
    table.sort(groups,ByAmount)
    return groups,n,sum
end
