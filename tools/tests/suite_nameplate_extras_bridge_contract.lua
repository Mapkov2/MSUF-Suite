local root = assert(arg[1])
local power, aura, class, known = 4,false,"ROGUE",{}
local specCalls = 0
Enum = { PowerType = { ComboPoints=4, HolyPower=9, SoulShards=7, Essence=19, ArcaneCharges=16, Chi=12, Runes=5 } }
function UnitClass() return class,class end
C_SpecializationInfo = { GetSpecialization = function() specCalls=specCalls+1 return 1 end,
    GetSpecializationInfo = function() return 103 end }
C_SpellBook = { IsSpellKnown = function(id) return known[id]==true end }
C_Spell = { GetSpellInfo = function(id) return {minRange=id==75 and 5 or 0,maxRange=30} end }
local read, max = function() return 2 end, function() return 5 end
local host = { CPBuilders = { ClassPowerType = function() return power,1,aura end }, CPClient = {UnitPower=read,UnitPowerMax=max} }
local s = { HostBridge = {Namespace=function() return host end}, Public=function() return true end,
    Finite=function(v) return type(v)=="number" end,Client={isForever=false} }
assert(loadfile(root.."/MSUF_Suite/Core/HostBridgeNameplateExtras.lua"))("Suite",s)
local b=s.HostBridge
local p,r,m,token=b.NameplateResource()
assert(p==4 and r==read and m==max and token=="COMBO_POINTS", "client combo provider was bypassed")
power=11
assert(b.NameplateResource()==nil,"continuous power was turned into hundreds of pips")
power,aura="AURA",true
assert(b.NameplateResource()==nil)
known[1752]=true
assert(b.NameplateRangeSpell(true)==0,"friendly range fell back to a harmful spell")
s.Client.isForever=true
local calls=specCalls
assert(b.NameplateRangeSpell(false)==1752 and calls==specCalls,"Forever read Retail specializations")
class="HUNTER";known={[75]=true}
assert(b.NameplateRangeSpell(false)==0,"minimum-range spell produced a false melee range result")
class="DRUID";known={[5176]=true,[5221]=true}
s.Client.isForever=false
assert(b.NameplateRangeSpell(false)==5221,"class range did not follow the current specialization")
print("Nameplate bridge: host resource provider, pip modes, friendly class fallback, Retail spec and Forever boundary passed")
