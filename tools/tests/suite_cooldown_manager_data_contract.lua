local root=assert(arg[1],"repository root required")
-- Offline contract for the cooldown manager data plane (Presets, Catalog,
-- Resolve, Index in MSUF_Suite_CooldownManager). Blizzard APIs are
-- identity-style stubs over prepared tables; secret values are sentinel tables
-- that raise on any comparison, arithmetic, concatenation, indexing or tostring.

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

------------------------------------------------------------------ static checks
-- TOC order; Presets.lua is plain data plus one class lookup (CDM table only).
local FILES={"Presets.lua","Catalog.lua","Resolve.lua","Index.lua"}
local HEADER,DATA_HEADER="local _,P=...\nlocal NS,S=P.NS,P.Suite\nlocal C=P.CDM\n","local _,P=...\nlocal C=P.CDM\n"
for _,file in ipairs(FILES) do
    local path=root.."/MSUF_Suite_CooldownManager/"..file
    assert(loadfile(path))
    local handle=assert(io.open(path,"rb"))
    local text=handle:read("*a"):gsub("\r","")
    handle:close()
    local header=file=="Presets.lua" and DATA_HEADER or HEADER
    assert(text:sub(1,#header)==header,file.." header")
    -- The data plane only decides which unit an entry watches; it anchors no
    -- frame, so no aura container can be anchored (to another container or
    -- anything else) from here. Placement belongs to Auras/Layout.
    for _,word in ipairs({"pcall","loadstring","setfenv","hooksecurefunc","OnUpdate","GetDataProvider","SetLayoutData",
        "CooldownViewerSettings:","TriggerEvent","SetPoint","SetAllPoints","ClearAllPoints","Claude","Anthropic"}) do
        assert(not text:find(word,1,true),file.." must not use "..word)
    end
end

------------------------------------------------------------------ core catalog (moduleAddons patched locally)
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",IsRetail=true,SupportsEvent=function() return true end}}
WOW_PROJECT_ID,WOW_PROJECT_MAINLINE=1,1
local store={}
MSUF_EncodeCompactTable=function(t,prefix) local n=#store+1;store[n]=t;return prefix..":"..n end
MSUF_TryDecodeCompactString=function(s) local n=tonumber(s:match("^MSUF3:(%d+)$"));return n and store[n] or nil end
local NS={}
for _,f in ipairs({"Core/Platform.lua","Core/Database.lua","Core/SuiteCatalog.lua"}) do
    assert(loadfile(root.."/MSUF_Suite/"..f))("MSUF_Suite",NS)
end
local B=NS.CatalogBuild
local original=B.Module
B.Module=function(mid,spec)
    if mid=="cooldownManager" then
        local catalog,order=NS.SuiteCatalog,NS.SuiteOrder
        spec.id,spec.addon,spec.controls,spec.rules,spec.conflicts=mid,"MSUF_Suite_CooldownManager",{},{},spec.conflicts or {}
        catalog[mid],order[#order+1]=spec,mid
        B.Add(mid,B.Bool("enabled","Enable module",false))
        return spec
    end
    return original(mid,spec)
end
assert(loadfile(root.."/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite",NS)
local CDM=NS.CDM

------------------------------------------------------------------ WoW world
Enum={SpellBookSpellBank={Player=0,Pet=1},CompressionMethod={Deflate=0}}
local SECRET_ID=Secret()
local sets={[0]={101,102,103,104,107},[1]={111,112,SECRET_ID},[2]={201,202,203},[3]={301},[4]={},
    [5]={501,502,101},[6]={601},[7]={701,702},[8]={801}}
local function Info(id,category,spell,extra)
    local info={cooldownID=id,spellID=spell,linkedSpellIDs={},selfAura=false,hasAura=false,charges=false,
        isKnown=true,isInvisible=false,flags=0,category=category}
    for k,v in pairs(extra or {}) do info[k]=v end
    return info
end
local infos={
    [101]=Info(101,0,1001,{hasAura=true,selfAura=true}),
    [102]=Info(102,0,1002),
    [103]=Info(103,0,1004,{flags=2}),
    [104]=Info(104,0,1005,{isKnown=false}),
    [107]=Info(107,0,nil),                                    -- 12.1.5 record without a spell
    [111]=Info(111,1,1111,{overrideSpellID=Secret()}),       -- secret field must be dropped
    [112]=Info(112,1,1112,{charges=true}),
    [201]=Info(201,2,2001,{selfAura=true,linkedSpellIDs={2002}}),
    [202]=Info(202,2,2003),
    [203]=Info(203,2,2004,{flags=6}),                         -- HideByDefault with the 12.1.5 flag 4 set
    [301]=Info(301,3,3001,{selfAura=true}),
    [501]=Info(501,5,5001,{spellCategoryID=30}),
    [502]=Info(502,5,5002,{isInvisible=true}),
    [601]=Info(601,6,6001,{selfAura=true}),
    [701]=Info(701,7,nil,{equipSlot=13}),
    [702]=Info(702,7,nil,{equipSlot=14,isKnown=false}),
    [801]=Info(801,8,8001,{equipSlot=13,buffSlot=1,selfAura=true}),
}
local layoutBlob,layouts,cborCalls="",{},0
C_CooldownViewer={
    GetCooldownViewerCategorySet=function(category,allow) assert(allow==true);return sets[category] or {} end,
    GetCooldownViewerCooldownInfo=function(id) assert(not IsSecret(id));return infos[id] end,
    GetLayoutData=function() return layoutBlob end,
}
C_EncodingUtil={
    DecodeBase64=function(s) return s end,
    DecompressString=function(s,method) assert(method==0);return s end,
    DeserializeCBOR=function(s) cborCalls=cborCalls+1;return layouts[s] end,
}
local specIndex=3
UnitClass=function() return "Mage","MAGE",8 end
C_SpecializationInfo={GetSpecialization=function() return specIndex end}
local names={[1001]="Fire Blast",[1002]="Pyroblast",[1003]="Hot Pyroblast",[1005]="Unlearned",[1111]="Blink",[1112]="Shift",
    [2001]="Buff",[2003]="Debuff",[3001]="Bar buff",[5001]="Potion spell",[5002]="Racial",[6001]="Agnostic",[8001]="Trinket proc",
    [9001]="Custom",[9002]="Custom base",[9003]="Custom override",[9004]="Other spec",[9101]="Aura",[9102]="Dot"}
local textures={}
for id in pairs(names) do textures[id]={id+100000,id+200000,nil} end
textures[1001]={1,2,3}                                        -- conditional icon wins
local overrides={[9002]=9003}
local charges={[9003]=2,[1112]=3}
local ranged={[1001]=true,[1002]=true,[9002]=true,[1112]=true}
local known={[9001]=true,[9002]=true,[1001]=true}
-- Harmful spells (C_Spell.IsSpellHarmful): 2003 is the buff bar's debuff
-- (Deathstalker's Mark), 9101 is harmful but listed as an explicit "a" key,
-- 3001 answers with a secret. harmfulCalls counts every question per ID.
local harmful,harmfulCalls={[2003]=true,[9101]=true,[3001]="secret"},{}
local function AskHarmful(id)
    assert(type(id)=="number" and not IsSecret(id),"harmful lookups take a plain spell ID")
    harmfulCalls[id]=(harmfulCalls[id] or 0)+1
    local answer=harmful[id]
    if answer=="secret" then return Secret() end
    return answer==true
end
C_Spell={
    GetSpellName=function(id) assert(type(id)=="number");return names[id] end,
    GetSpellTexture=function(id) local t=textures[id];if t then return t[1],t[2],t[3] end end,
    GetBaseSpell=function(id) return id end,
    GetSpellCharges=function(id) local max=charges[id];if max then return {maxCharges=max,currentCharges=Secret()} end end,
    SpellHasRange=function(id) return ranged[id]==true end,
    GetSpellCooldownDuration=function() end,
    IsSpellHarmful=AskHarmful,
}
C_SpellBook={
    FindSpellOverrideByID=function(id) return overrides[id] end,
    IsSpellKnownOrInSpellBook=function(id,bank) return bank==nil and known[id]==true end,
}
local equipped,equippedTex={[13]=5555},{[13]=5556}
GetInventoryItemID=function(unit,slot) assert(unit=="player");return equipped[slot] end
GetInventoryItemTexture=function(unit,slot) assert(unit=="player");return equippedTex[slot] end
C_PaperDollInfo={GetInventorySlotInfoForInvSlot=function(slot) return slot,136528,false,"SLOT" end}
C_Item={
    GetItemIconByID=function(id) return ({[7001]=777,[5555]=5556})[id] end,
    GetItemNameByID=function(id) return ({[7001]="Potion",[5555]="Trinket A"})[id] end,
    GetItemSpell=function(id) if id==7001 then return "Drink",7101 end end,
}
C_EventUtils={IsEventValid=function() return true end}
local gateFrame
CreateFrame=function()
    local frame={events={},scripts={}}
    function frame:RegisterEvent(event) self.events[event]=true end
    function frame:UnregisterAllEvents() self.events={} end
    function frame:SetScript(key,fn) self.scripts[key]=fn end
    gateFrame=gateFrame or frame
    return frame
end

------------------------------------------------------------------ bootstrap stub + files
local S={Public=function(v) return not IsSecret(v) end,Text=function(v) return v end}
local P={NS=NS,Suite=S}
P.CDM={M={},EMPTY={},state={},views={},plans={},bars={},entries={},lists=CDM.CleanLists(nil),spells=CDM.CleanSpells(nil),
    wipe=function(t) for k in pairs(t) do t[k]=nil end return t end,}
local C=P.CDM
-- The shared constants and helpers load first, as in the TOC.
assert(loadfile(root.."/MSUF_Suite_CooldownManager/Const.lua"))("MSUF_Suite_CooldownManager",P)
for _,file in ipairs(FILES) do
    assert(loadfile(root.."/MSUF_Suite_CooldownManager/"..file))("MSUF_Suite_CooldownManager",P)
end
local Catalog,Resolve,Index=C.Catalog,C.Resolve,C.Index
assert(Catalog and Resolve and Index)

local function Keys(list)
    local out={}
    for i=1,#list do local v=list[i];out[i]=type(v)=="table" and v.key or tostring(v) end
    return table.concat(out,",")
end
local function Same(label,got,want) assert(got==want,label..": got "..tostring(got).." want "..tostring(want)) end

------------------------------------------------------------------ slot categories
-- The catalog's slot categories and the runtime's bar map say the same:
-- trinkets (equipment slot pool 7) join Essential, Potions and racials keeps
-- potions and healthstones (5) only. Pool 7 follows Essential's own entries.
local function Cats(key) return table.concat(CDM.SLOTS[CDM.SLOT_INDEX[key]].categories,",") end
Same("ess categories",Cats("ess"),"0,7")
Same("ext categories",Cats("ext"),"5")
for _,def in ipairs(CDM.SLOTS) do
    for _,cat in ipairs(def.categories) do
        assert(Catalog.BAR_OF[cat]==def.key,def.key.." lists category "..cat.." that the runtime maps elsewhere")
    end
end
for cat,bar in pairs(Catalog.BAR_OF) do
    local listed=false
    for _,c in ipairs(CDM.SLOTS[CDM.SLOT_INDEX[bar]].categories) do if c==cat then listed=true end end
    assert(listed,"category "..cat.." maps to "..bar.." but the catalog slot does not list it")
end
assert(Catalog.BAR_OF[7]=="ess" and Catalog.BAR_OF[5]=="ext" and Catalog.TAIL[7]==true and not Catalog.TAIL[0],"trinket tail")

------------------------------------------------------------------ per-spell choices
-- Stack features validate like every other field: glow from N applications,
-- stack text colored from N (0 = off, at most 99, whole numbers) and a
-- six-digit hex color. Malformed values are dropped before anything is
-- stored; an entry left with nothing disappears.
local F=CDM.SPELL_FIELDS
for _,field in ipairs({"stackGlow","stackColorAt","stackColor","glowStyle","glowColor","auraGlow","sound","lossSound"}) do
    assert(type(F[field])=="function",field.." has no validator")
end
for _,v in ipairs({0,1,5,99}) do assert(F.stackGlow(v) and F.stackColorAt(v),"stack threshold "..v.." refused") end
for _,v in ipairs({-1,100,2.5,0/0,math.huge,"3",true,{}}) do
    assert(not F.stackGlow(v) and not F.stackColorAt(v),"stack threshold "..tostring(v).." accepted")
end
assert(F.stackColor("ff5a3c") and F.stackColor("FFAA00"),"hex stack colors")
for _,v in ipairs({"ff5a3","ff5a3c0","#ff5a3c","gg5a3c","",0xff5a3c,true}) do
    assert(not F.stackColor(v),"stack color "..tostring(v).." accepted")
end
Same("stack color default",CDM.SPELL_DEFAULTS.stackColor,"ff5a3c")
assert(F.stackColor(CDM.SPELL_DEFAULTS.stackColor),"the default is a valid value")
-- Blizzard Cooldown Manager sounds are sound kits.
assert(F.sound("kit:8959") and F.lossSound("kit:8959") and not F.sound("kit:") and not F.sound("kit:12a"),"kit sounds")
local cleanSpells=CDM.CleanSpells({e={
    a9101={stackGlow=3,stackColorAt=2,stackColor="3cff5a",glowStyle=2,glowColor="00ff00",auraGlow=true,sound="kit:8959"},
    a9102={stackGlow=100,stackColorAt=-1,stackColor="red",bogus=true},
    b101={stackGlow=0,stackColorAt=1,stackColor="FF5A3C",glowStyle=5,glowColor="xyz"},
    d9103={stackGlow=2.5,readyGlow=true},
}})
local sp=cleanSpells.e.a9101
assert(sp.stackGlow==3 and sp.stackColorAt==2 and sp.stackColor=="3cff5a" and sp.glowStyle==2 and sp.glowColor=="00ff00"
    and sp.auraGlow==true and sp.sound=="kit:8959","valid stack and glow choices are kept")
assert(cleanSpells.e.a9102==nil,"an entry with only malformed choices is dropped")
sp=cleanSpells.e.b101
assert(sp.stackGlow==0 and sp.stackColorAt==1 and sp.stackColor=="FF5A3C" and sp.glowStyle==nil and sp.glowColor==nil,
    "0 and 1 are kept; a bad style or color is dropped")
sp=cleanSpells.e.d9103
assert(sp.stackGlow==nil and sp.readyGlow==true,"a fractional stack count is dropped, the rest of the entry stays")
-- Data string round trip: what is stored is already clean, and decoding
-- cleans again.
local spellText=assert(CDM.Codec.EncodeSpells({v=1,e={
    a9101={stackGlow=3,stackColorAt=2,stackColor="3cff5a",glowStyle=4,glowColor="00ff00"},
    a9102={stackGlow=-4,stackColor="ff5a3"},
}}))
assert(spellText~="","encoded")
local stored=MSUF_TryDecodeCompactString(spellText)
assert(stored.e.a9101 and stored.e.a9102==nil,"malformed entries never reach the stored string")
local decoded=CDM.Codec.DecodeSpells(spellText)
sp=decoded.e.a9101
assert(sp.stackGlow==3 and sp.stackColorAt==2 and sp.stackColor=="3cff5a" and sp.glowStyle==4 and sp.glowColor=="00ff00",
    "stack choices survive the data string")
assert(decoded.e.a9102==nil)
stored.e.a9101.stackGlow=150
assert(CDM.Codec.DecodeSpells(spellText).e.a9101.stackGlow==nil,"a damaged stored value is dropped on decode")
Same("only malformed",CDM.Codec.EncodeSpells({e={a1={stackGlow=500,stackColor="nope"}}}),"")

------------------------------------------------------------------ readiness gate
-- Loading the runtime creates no frame (the options page loads it with the
-- module off); the gate exists only while Blizzard's data is missing.
assert(gateFrame==nil,"the readiness gate is created lazily")
local essSet=sets[0]
sets[0]={}
assert(not Catalog.Ready() and Catalog.Rebuild()==false and Catalog.generation==0,"not ready before data")
assert(gateFrame and gateFrame.events.COOLDOWN_VIEWER_DATA_LOADED and gateFrame.events.VARIABLES_LOADED
    and gateFrame.events.PLAYER_ENTERING_WORLD,"before login the gate waits for all three events")
local firstGate=gateFrame
assert(not Catalog.Ready() and gateFrame==firstGate,"one gate frame")
for _,event in ipairs({"VARIABLES_LOADED","PLAYER_ENTERING_WORLD"}) do gateFrame.scripts.OnEvent(gateFrame,event) end
assert(not Catalog.Ready())
gateFrame.scripts.OnEvent(gateFrame,"COOLDOWN_VIEWER_DATA_LOADED")
assert(Catalog.Ready() and next(gateFrame.events)==nil and gateFrame.scripts.OnEvent==nil,"gate completes and unregisters")
sets[0]=essSet

------------------------------------------------------------------ catalog: defaults
assert(Catalog.Rebuild()==true)
local gen=Catalog.generation
Same("order",Keys(Catalog.order),"101,102,103,104,107,111,112,201,202,203,301,701,702,801,501,502,601")
-- Trinkets (pool 7) join the end of Essential; Potions and racials keeps
-- potions and healthstones (pool 5).
Same("ess",Keys(Catalog.byBar.ess),"101,102,107,701")
Same("uti",Keys(Catalog.byBar.uti),"111,112")
Same("buf",Keys(Catalog.byBar.buf),"201,202,801,601")
Same("bar",Keys(Catalog.byBar.bar),"301")
Same("ext",Keys(Catalog.byBar.ext),"501,502")
local recs=Catalog.records
assert(recs[104].known==false and recs[702].known==false,"unlearned records stay in the catalog, off the bar lists")
assert(recs[103].category==-1 and recs[103].family==1,"HideByDefault 0 -> -1")
assert(recs[203].category==-2 and recs[203].family==2,"HideByDefault 2 -> -2 via bit test")
assert(recs[107].spell==nil and recs[107].known and recs[701].spell==nil and recs[701].equipSlot==13,"nil spell records kept")
assert(recs[111].override==nil,"secret override dropped")
assert(recs[101]~=infos[101] and recs[201].linked~=infos[201].linkedSpellIDs and recs[201].linked[1]==2002,"whitelisted copies")
assert(recs[102].linked==C.EMPTY and recs[501].spellCategory==30)
-- Only fields the runtime reads are kept.
for _,field in ipairs({"buffSlot","invisible","hideByDefault","pos"}) do
    assert(recs[801][field]==nil and recs[103][field]==nil,"unread record field kept: "..field)
end
assert(Catalog.unknown==nil and Catalog.alerts==nil and Catalog.layoutActive==nil,"unread catalog lists kept")
assert(recs[101].key=="b101" and recs[601].bar=="buf" and recs[601].family==2 and recs[501].bar=="ext")
assert(recs[701].bar=="ess" and recs[701].category==7 and recs[701].family==1 and recs[702].bar=="ess","trinkets on Essential")
-- Bars that hold an equipment slot, learned or not (gear changes matter there).
local function Set(t)
    local list={}
    for key in pairs(t) do list[#list+1]=key end
    table.sort(list)
    return table.concat(list,",")
end
Same("equip bars",Set(Catalog.equipBars),"buf,ess")
infos[101].spellID=424242
assert(recs[101].spell==1001,"record does not alias Blizzard's table")
infos[101].spellID=1001
local content=Catalog.content
assert(Catalog.Rebuild()==false and Catalog.generation==gen+1,"unchanged rebuild still counts a generation")
assert(Catalog.content==content,"an unchanged rebuild keeps the content generation (preset lists stay)")
-- Invisible entries follow Blizzard's own switch.
CDM_HIDE_INVISIBLE_ITEMS=true
assert(Catalog.Rebuild()==true and recs[502]==nil and Keys(Catalog.byBar.ext)=="501")
assert(Catalog.content==content+1,"a changed rebuild moves the content generation")
CDM_HIDE_INVISIBLE_ITEMS=nil
assert(Catalog.Rebuild()==true and recs[502] and Keys(Catalog.byBar.ext)=="501,502")

------------------------------------------------------------------ catalog: layout versions
local function Layout(key,data) layouts[key]=data;layoutBlob="1|"..key;Catalog.Rebuild() end
-- v5: saved order merge (unknown 999 dropped), pool item 7 -> Essential,
-- Utility item moved to hidden (-1), a HideByDefault item moved back to Utility.
local L5={[1]={102,999,101,111},[2]={[0]={701},[-1]={111},[1]={103}},[3]={[101]={{1,1,5}}}}
Layout("L5",{[1]=5,[2]={[83]=7},[3]={[83]={[7]=L5}},[4]={[7]="Mine"}})
Same("v5 order",Keys(Catalog.order),"102,101,111,103,104,107,112,201,202,203,301,701,702,801,501,502,601")
Same("v5 ess",Keys(Catalog.byBar.ess),"102,101,107,701")
Same("v5 uti",Keys(Catalog.byBar.uti),"103,112")
Same("v5 ext",Keys(Catalog.byBar.ext),"501,502")
assert(recs[111].category==-1 and recs[701].category==0 and recs[701].bar=="ess" and recs[103].bar=="uti")
assert(Catalog.specTag==83)
-- Decoded once per distinct string.
local calls=cborCalls
Catalog.Rebuild();Catalog.Rebuild()
Same("decode cache",cborCalls,calls)
-- A secret layout string keeps the last decoded layout.
layoutBlob=Secret()
Catalog.Rebuild()
Same("secret blob keeps layout",Keys(Catalog.byBar.ess),"102,101,107,701")
-- A saved order that puts a pool trinket first still ends Essential with it
-- (a trinket moved into Essential keeps its saved place, v5 above); one moved
-- into the potion pool (5) goes to Potions and racials.
Layout("LT",{[1]=5,[2]={[83]=7},[3]={[83]={[7]={[1]={701,102,101}}}}})
Same("tail order",Keys(Catalog.order),"701,102,101,103,104,107,111,112,201,202,203,301,702,801,501,502,601")
Same("tail ess",Keys(Catalog.byBar.ess),"102,101,107,701")
Layout("LP",{[1]=5,[2]={[83]=7},[3]={[83]={[7]={[2]={[5]={701}}}}}})
Same("pool 5 ess",Keys(Catalog.byBar.ess),"101,102,107")
Same("pool 5 ext",Keys(Catalog.byBar.ext),"701,501,502")
assert(recs[701].category==5 and recs[701].bar=="ext" and recs[702].bar=="ess")
Same("equip bars follow the move",Set(Catalog.equipBars),"buf,ess,ext")
-- v5 explicit starter layout.
Layout("L5S",{[1]=5,[2]={[83]=0},[3]={[83]={[7]=L5}}})
Same("starter",Keys(Catalog.byBar.ess),"101,102,107,701")
-- v4 without an active entry: lowest layout ID stands in for pairs().
Layout("L4",{[1]=4,[2]={},[3]={[83]={[9]={[2]={[1]={101}}},[4]={[2]={[1]={102}}}}}})
Same("v4 fallback",Keys(Catalog.byBar.uti),"102,111,112")
-- v2/v3: active layout by name, else the lowest name.
Layout("L2",{[1]=2,[2]={[83]="B"},[3]={[83]={A={[2]={[1]={101}}},B={[2]={[1]={107}}}}}})
Same("v2 by name",Keys(Catalog.byBar.uti),"107,111,112")
Layout("L3",{[1]=3,[2]={[83]="Gone"},[3]={[83]={A={[2]={[1]={101}}},B={[2]={[1]={107}}}}}})
Same("v3 fallback",Keys(Catalog.byBar.uti),"101,111,112")
-- v1: layouts keyed by name, no active map.
Layout("L1",{[1]=1,[3]={[83]={Solo={[1]={112,111}}}}})
Same("v1 order",Keys(Catalog.byBar.uti),"112,111")
-- Other spec's layout, unknown save format, unknown encoding: defaults.
Layout("LX",{[1]=5,[2]={[84]=3},[3]={[84]={[3]={[2]={[1]={101}}}}}})
Same("other tag",Keys(Catalog.byBar.uti),"111,112")
Layout("L6",{[1]=6,[3]={[83]={[1]={[2]={[1]={101}}}}}})
Same("format 6 ignored",Keys(Catalog.byBar.uti),"111,112")
layouts.L5b=layouts.L5;layoutBlob="2|L5b";Catalog.Rebuild()
Same("encoding 2 ignored",Keys(Catalog.byBar.ess),"101,102,107,701")
layoutBlob="garbage";Catalog.Rebuild()
Same("no envelope",Keys(Catalog.byBar.ess),"101,102,107,701")
-- No spec tag: Blizzard falls back to the defaults, so do we.
specIndex=nil;layoutBlob="1|L5";Catalog.Rebuild()
Same("nil tag",Keys(Catalog.byBar.ess),"101,102,107,701")
assert(Catalog.specTag==nil)
specIndex=3;layoutBlob="";Catalog.Rebuild()
Same("back to defaults",Keys(Catalog.byBar.ess),"101,102,107,701")
Same("equip bars back",Set(Catalog.equipBars),"buf,ess")
-- Blizzard's layout callbacks rebuild only when the saved string moved.
assert(Catalog.LayoutStale()==false,"the decoded layout is current")
layoutBlob="1|L5"
assert(Catalog.LayoutStale()==true,"a saved layout change is stale")
layoutBlob=Secret()
assert(Catalog.LayoutStale()==true,"an unreadable layout counts as changed")
layoutBlob=""
assert(Catalog.LayoutStale()==false)

------------------------------------------------------------------ resolve
local function View(def,extra)
    local v={key=def.key,index=CDM.SLOT_INDEX[def.key],kind=def.kind or 1,builtin=def.builtin==true,on=def.builtin==true,
        title=def.title,range=true,usable=true,procGlow=true,showAura=true,charges=true,assist=false}
    for k,value in pairs(extra or {}) do v[k]=value end
    return v
end
local viewExtra={
    ess={assist=true},
    ext={usable=false,range=false},
    c1={on=true,procGlow=false,showAura=false,usable=false},
    c2={on=true,kind=2},
    c3={on=false,kind=1},
    c4={on=true,kind=3},
}
for _,def in ipairs(CDM.SLOTS) do C.views[def.key]=View(def,viewExtra[def.key]) end
C.lists=CDM.CleanLists({specs={[63]={
    ess={"b101","s9001"},
    c1={"b102","s9002","i7001","e13","a9101","s1001","s9004"},
    c2={"a9101","d9102","b201","b112"},
    c3={"b107"},
}},hidden={[63]={b111=true}}})
C.spells=CDM.CleanSpells({e={b101={procGlow=false},b102={procGlow=true}}})
C.state.specID=63
local plans,changed=Resolve.Build()
assert(plans==C.plans and changed==true)
Same("r ess",Keys(plans.ess.entries),"b101,s9001")               -- b102 claimed by c1, b107 by the hidden c3, the trinket (b701) by c1's e13
Same("r uti",Keys(plans.uti.entries),"b112")                     -- b111 hidden; b112 on c2 is the wrong family
Same("r buf",Keys(plans.buf.entries),"b202,b801,b601")           -- b201 claimed by c2; b801 is a trinket buff, not the slot
Same("r bar",Keys(plans.bar.entries),"b301")
Same("r ext",Keys(plans.ext.entries),"b501,b502")                -- no racial is named or known here
Same("r def",Keys(plans.def.entries),"")                         -- no Mage defensive exists in this world
Same("r c1",Keys(plans.c1.entries),"b102,s9002,i7001,e13,s1001") -- a9101 wrong family, s9004 unlearned
Same("r c2",Keys(plans.c2.entries),"a9101,d9102,b201")
assert(plans.c3==nil and plans.c5==nil and #plans.c4.entries==0 and plans.c4.kind==3 and plans.c2.kind==2)
local E=C.entries
local e=E.s9002
assert(e.src=="s" and e.id==9002 and e.family==1 and e.base==9002 and e.override==9003 and e.spell==9003)
assert(e.charges==true and e.hasRange==true and e.known==true and e.texture==109002 and e.name=="Custom override")
assert(e.slot=="c1" and e.index==2 and e.ov==C.EMPTY and e.auraIDs==nil and e.linked==C.EMPTY)
assert(E.s9001.charges==false and E.s9001.override==nil and E.s9001.spell==9001)
e=E.i7001
assert(e.src=="i" and e.itemID==7001 and e.spell==7101 and e.texture==777 and e.name=="Potion" and e.known)
e=E.e13
assert(e.src=="e" and e.equipSlot==13 and e.itemID==5555 and e.texture==5556 and e.name=="Trinket A" and e.spell==nil)
-- Explicit aura keys pick their unit by kind: "a" the player (even for a
-- harmful spell), "d" the target.
e=E.a9101
assert(e.family==2 and e.unit=="player" and e.auraIDs[9101] and e.selfAura and e.hasAura,"an a key watches the player")
e=E.d9102
assert(e.family==2 and e.unit=="target" and e.auraIDs[9102] and not e.selfAura,"a d key watches the target")
-- Every Blizzard aura entry watches exactly one unit: the target when any of
-- its aura IDs (base, override, tooltip, linked) is harmful, else the player.
-- Blizzard's selfAura is not used, and the automatic unit is never "both":
-- only the per-spell "Track on" choice (below) watches both units.
e=E.b201
assert(e.family==2 and e.selfAura and e.unit=="player" and e.auraIDs[2001] and e.auraIDs[2002] and e.linked[1]==2002)
assert(E.b202.unit=="target" and not E.b202.selfAura,"a harmful spell on a buff bar (Deathstalker's Mark) is a target aura")
assert(E.b301.unit=="player","a secret harmful answer counts as helpful")
assert(E.b801.unit=="player" and E.b601.unit=="player")
e=E.b101
assert(e.family==1 and e.hasAura and e.auraIDs[1001] and e.unit=="player" and e.texture==3 and e.hasRange and e.ov.procGlow==false,
    "a cooldown that shows its buff watches one unit too")
assert(E.b102.unit==nil and E.b102.auraIDs==nil and E.b112.unit==nil,"cooldowns without an aura watch no unit")
for key,entry in pairs(E) do
    if entry.src=="b" and entry.auraIDs then
        assert(entry.unit=="player" or entry.unit=="target",key.." watches "..tostring(entry.unit))
    end
end
-- Only Blizzard aura entries ask: explicit keys and plain cooldowns never do.
assert(harmfulCalls[9101]==nil and harmfulCalls[9102]==nil,"explicit aura keys never ask")
assert(harmfulCalls[1002]==nil and harmfulCalls[1112]==nil and harmfulCalls[9001]==nil,"cooldowns without an aura never ask")
assert(harmfulCalls[2003]==1 and harmfulCalls[1001]==1 and harmfulCalls[3001]==1,"aura entries ask")
assert(E.b701==nil,"c1 lists the trinket's slot (e13): Blizzard's record for it shows on no other bar")
assert(E.b501.texture=="Interface/ICONS/INV_POTION_54" and E.b501.spellCategory==30)
assert(E.b102.ov.procGlow==true and E.b102.hasRange and E.b102.spell==1002)
-- Entry tables survive rebuilds with their runtime fields.
E.b101.icon,E.b101.cooling="ICON",true
local b101,b102=E.b101,E.b102
local gens=plans.ess.gen
plans,changed=Resolve.Build()
assert(changed==false and plans.ess.gen==gens and E.b101==b101 and b101.icon=="ICON" and b101.cooling==true)
assert(Resolve.touched[1]==nil and next(Resolve.auraTouched)==nil,"an unchanged rebuild touches no entry")
-- A refill that changes an entry in place (a talent swaps an icon or an
-- override) keeps every plan and reports only that entry.
textures[1001]={7,8,9}
overrides[9002]=9004
plans,changed=Resolve.Build()
assert(changed==false and plans.ess.gen==gens and b101.texture==9 and E.s9002.override==9004,"entries refill in place")
Same("touched",Keys(Resolve.touched),"b101,s9002,s1001")
assert(not Resolve.auraTouched[b101] and not Resolve.auraTouched[E.s9002],"no aura IDs moved")
textures[1001],overrides[9002]={1,2,3},9003
plans=Resolve.Build()
Same("touched back",Keys(Resolve.touched),"b101,s9002,s1001")
-- A new linked spell moves the aura IDs Blizzard's entry watches.
infos[101].linkedSpellIDs={1099}
Catalog.Rebuild()
plans,changed=Resolve.Build()
assert(changed==false and b101.auraIDs[1099] and Resolve.auraTouched[b101],"aura IDs follow the catalog")
infos[101].linkedSpellIDs={}
Catalog.Rebuild()
plans=Resolve.Build()
assert(not b101.auraIDs[1099] and Resolve.auraTouched[b101])
plans=Resolve.Build()
assert(Resolve.touched[1]==nil,"settled")

------------------------------------------------------------------ aura units
local function TouchedKeys()
    local set={}
    for i=1,#Resolve.touched do set[Resolve.touched[i].key]=true end
    return Set(set)
end
local function AuraTouchedKeys()
    local set={}
    for entry in pairs(Resolve.auraTouched) do set[entry.key]=true end
    return Set(set)
end
local function AskedTotal()
    local n=0
    for _,count in pairs(harmfulCalls) do n=n+count end
    return n
end
-- The harmful answer is cached per spell ID: seven builds and two catalog
-- rebuilds above asked each ID once, and more of them ask nothing.
for id,count in pairs(harmfulCalls) do Same("asked "..id,count,1) end
local asked=AskedTotal()
Resolve.Build();Catalog.Rebuild();Resolve.Build()
Same("cached answers",AskedTotal(),asked)
-- Any harmful aura ID moves the entry to the target, and back to the player
-- when it goes; the change reaches the entry's container (auraTouched).
-- Override (a talent that turns a buff into a debuff):
harmful[6002]=true
infos[601].overrideSpellID=6002
Catalog.Rebuild()
plans,changed=Resolve.Build()
assert(changed==false and E.b601.unit=="target" and E.b601.auraIDs[6002],"a harmful override watches the target")
Same("override touched",AuraTouchedKeys(),"b601")
Same("asked 6002",harmfulCalls[6002],1)
infos[601].overrideSpellID=nil
Catalog.Rebuild()
Resolve.Build()
assert(E.b601.unit=="player" and Resolve.auraTouched[E.b601],"the override gone, the player again")
-- Tooltip spell:
harmful[8002]=true
infos[801].overrideTooltipSpellID=8002
Catalog.Rebuild()
Resolve.Build()
assert(E.b801.unit=="target" and E.b801.tooltip==8002 and E.b801.auraIDs[8002],"a harmful tooltip spell watches the target")
Same("tooltip touched",AuraTouchedKeys(),"b801")
infos[801].overrideTooltipSpellID=nil
Catalog.Rebuild()
Resolve.Build()
assert(E.b801.unit=="player" and Resolve.auraTouched[E.b801])
-- Linked spell (after helpful IDs, a selfAura entry):
harmful[2005]=true
infos[201].linkedSpellIDs={2002,2005}
Catalog.Rebuild()
Resolve.Build()
assert(E.b201.unit=="target" and E.b201.selfAura and E.b201.auraIDs[2005],"a harmful linked spell watches the target")
Same("linked touched",AuraTouchedKeys(),"b201")
infos[201].linkedSpellIDs={2002}
Catalog.Rebuild()
Resolve.Build()
assert(E.b201.unit=="player" and Resolve.auraTouched[E.b201])
-- Secret IDs never reach the question (the stub raises on one): the catalog
-- drops a secret linked or tooltip ID, and a plain harmful ID next to it
-- still decides.
harmful[6003]=true
infos[601].linkedSpellIDs,infos[601].overrideTooltipSpellID={Secret(),6003},Secret()
Catalog.Rebuild()
Resolve.Build()
assert(E.b601.unit=="target" and #E.b601.linked==1 and E.b601.linked[1]==6003 and E.b601.tooltip==nil
    and E.b601.auraIDs[6003],"secret IDs are dropped, the plain harmful one decides")
Same("secret neighbours touched",AuraTouchedKeys(),"b601")
Same("asked 6003",harmfulCalls[6003],1)
infos[601].linkedSpellIDs,infos[601].overrideTooltipSpellID={},nil
Catalog.Rebuild()
Resolve.Build()
assert(E.b601.unit=="player" and not E.b601.auraIDs[6003] and Resolve.auraTouched[E.b601])
-- selfAura decides nothing: flipped both ways, no unit moves.
infos[201].selfAura,infos[202].selfAura=false,true
Catalog.Rebuild()
Resolve.Build()
assert(not E.b201.selfAura and E.b201.unit=="player" and E.b202.selfAura and E.b202.unit=="target","selfAura is not the unit")
Same("selfAura moves no container",AuraTouchedKeys(),"")
infos[201].selfAura,infos[202].selfAura=true,false
Catalog.Rebuild()
Resolve.Build()
-- Without C_Spell.IsSpellHarmful the global IsHarmfulSpell answers; without
-- either, an aura is the player's. Cached answers are not asked again.
-- While C_Spell.IsSpellHarmful exists it answers and the global is never asked.
local globalAsked=0
IsHarmfulSpell=function() globalAsked=globalAsked+1;return false end
harmful[3004]=true
infos[301].linkedSpellIDs={3004}
Catalog.Rebuild()
Resolve.Build()
assert(E.b301.unit=="target" and harmfulCalls[3004]==1 and globalAsked==0,"C_Spell.IsSpellHarmful answers first")
local isSpellHarmful=C_Spell.IsSpellHarmful
C_Spell.IsSpellHarmful=nil
harmful[3005]=true
IsHarmfulSpell=AskHarmful
infos[301].linkedSpellIDs={3005}
Catalog.Rebuild()
Resolve.Build()
assert(E.b301.unit=="target" and harmfulCalls[3005]==1 and harmfulCalls[3001]==1,"the global answers new IDs")
IsHarmfulSpell=nil
harmful[3006]=true
infos[301].linkedSpellIDs={3006}
Catalog.Rebuild()
Resolve.Build()
assert(E.b301.unit=="player" and harmfulCalls[3006]==nil,"no API, no target")
C_Spell.IsSpellHarmful=isSpellHarmful
infos[301].linkedSpellIDs={}
Catalog.Rebuild()
Resolve.Build()
assert(E.b301.unit=="player" and not E.b301.auraIDs[3006] and Resolve.auraTouched[E.b301],"linked IDs cleared")
for id,count in pairs(harmfulCalls) do Same("asked once "..id,count,1) end

-- Per-spell "Track on" (auraUnit): 1 automatic, 2 me, 3 target, 4 both.
-- Stored values are whole numbers 1-4; the page's "Automatic" (0) clears
-- the field.
for _,v in ipairs({1,2,3,4}) do assert(F.auraUnit(v),"auraUnit "..v.." refused") end
for _,v in ipairs({0,5,-1,2.5,0/0,math.huge,"3",true,{}}) do
    assert(not F.auraUnit(v),"auraUnit "..tostring(v).." accepted")
end
assert(CDM.CleanSpells({e={b202={auraUnit=0}}}).e.b202==nil,"Automatic (0) is never stored")
Same("track round trip",CDM.Codec.DecodeSpells(CDM.Codec.EncodeSpells({e={b202={auraUnit=3}}})).e.b202.auraUnit,3)
local BASE_SPELLS={b101={procGlow=false},b102={procGlow=true}}
local function Track(map)
    local e={}
    for key,fields in pairs(BASE_SPELLS) do e[key]={procGlow=fields.procGlow} end
    for key,v in pairs(map) do e[key]=e[key] or {};e[key].auraUnit=v end
    C.spells=CDM.CleanSpells({e=e})
    plans,changed=Resolve.Build()
end
-- The choice replaces the automatic unit on every entry that watches one
-- (Blizzard aura entries, cooldowns that show their buff, explicit keys);
-- an entry without a unit never gets one. It is applied before the refill
-- is compared, so each entry whose unit moved resyncs its container.
Track({b202=2,b201=3,b301=4,b601=1,b101=4,a9101=3,d9102=2,b102=3})
assert(changed==false,"a unit choice moves no entry between bars")
assert(E.b202.unit=="player","2: a harmful aura tracked on me")
assert(E.b201.unit=="target","3: a helpful aura tracked on the target")
assert(E.b301.unit=="both" and E.b101.unit=="both","4: both units")
assert(E.b601.unit=="player","1: automatic")
assert(E.a9101.unit=="target" and E.d9102.unit=="player","explicit keys follow the choice too")
assert(E.b102.unit==nil and E.b102.auraIDs==nil,"a cooldown without an aura gets no unit")
assert(E.b202.ov.auraUnit==2 and E.b102.ov.auraUnit==3)
Same("track touched",TouchedKeys(),"a9101,b101,b201,b202,b301,d9102")
Same("track aura touched",AuraTouchedKeys(),"a9101,b101,b201,b202,b301,d9102")
-- The same choices again: nothing moves.
asked=AskedTotal()
Track({b202=2,b201=3,b301=4,b601=1,b101=4,a9101=3,d9102=2,b102=3})
assert(Resolve.touched[1]==nil and next(Resolve.auraTouched)==nil,"an unchanged choice resyncs nothing")
Same("choices ask nothing",AskedTotal(),asked)
-- Changed choices: only those entries resync. 1 is automatic, not a unit of
-- its own: the harmful b202 goes back to the target.
Track({b202=1,b201=3,b301=3,b601=1,b101=4,a9101=3,d9102=2,b102=3})
assert(E.b301.unit=="target" and E.b202.unit=="target","3: the target; 1: automatic (harmful)")
Same("changed choices touched",AuraTouchedKeys(),"b202,b301")
-- A choice equal to the automatic unit moves nothing (b601 from automatic to
-- me, b801 from no choice to me).
Track({b202=1,b201=3,b301=3,b601=2,b801=2,b101=4,a9101=3,d9102=2,b102=3})
assert(E.b601.unit=="player" and E.b801.unit=="player")
Same("same as automatic",AuraTouchedKeys(),"")
-- A choice holds when the automatic unit moves under it: a harmful override
-- arrives on b601 (tracked on me) and it stays on the player. Its aura IDs
-- moved, so it still resyncs; nothing else does.
infos[601].overrideSpellID=6002
Catalog.Rebuild()
Track({b202=1,b201=3,b301=3,b601=2,b801=2,b101=4,a9101=3,d9102=2,b102=3})
assert(changed==false and E.b601.unit=="player" and E.b601.auraIDs[6002],"the choice beats a harmful override")
Same("choice under override",AuraTouchedKeys(),"b601")
infos[601].overrideSpellID=nil
Catalog.Rebuild()
Track({b202=1,b201=3,b301=3,b601=2,b801=2,b101=4,a9101=3,d9102=2,b102=3})
assert(E.b601.unit=="player" and not E.b601.auraIDs[6002])
Same("override gone under a choice",AuraTouchedKeys(),"b601")
-- Cleared: every entry is back on its automatic unit, and each one that
-- moved resyncs.
Track({})
assert(E.b202.unit=="target" and E.b201.unit=="player" and E.b301.unit=="player" and E.b601.unit=="player"
    and E.b801.unit=="player" and E.b101.unit=="player" and E.a9101.unit=="player" and E.d9102.unit=="target"
    and E.b102.unit==nil,"automatic again")
Same("cleared touched",AuraTouchedKeys(),"a9101,b101,b201,b301,d9102")
-- A stored value outside 1-4 (a damaged string) means automatic: nothing moves.
C.spells={v=1,e={b101={procGlow=false},b102={procGlow=true},b202={auraUnit=7},b201={auraUnit="3"},b301={auraUnit=0/0},
    a9101={auraUnit=0},d9102={auraUnit=true}}}
plans,changed=Resolve.Build()
assert(changed==false and E.b202.unit=="target" and E.b201.unit=="player" and E.b301.unit=="player"
    and E.a9101.unit=="player" and E.d9102.unit=="target","a malformed choice is automatic")
Same("malformed touched",AuraTouchedKeys(),"")
Track({})
assert(Resolve.touched[1]==nil,"settled")
-- Per-spec lists and hidden sets: spec 64 has none.
C.state.specID=64
local s9002=E.s9002
plans,changed=Resolve.Build()
assert(changed==true)
Same("64 ess",Keys(plans.ess.entries),"b101,b102,b107,b701")
Same("64 uti",Keys(plans.uti.entries),"b111,b112")
Same("64 buf",Keys(plans.buf.entries),"b201,b202,b801,b601")
assert(#plans.c1.entries==0 and #plans.c2.entries==0)
assert(E.b102==b102 and b102.slot=="ess" and b102.index==2,"moved entry keeps its table")
assert(E.s9002==nil and s9002.slot==nil and s9002.index==nil,"entries that left are released")
-- No list names the trinket's slot here: Blizzard's record ends Essential and
-- routes as it did on Potions and racials (equipment slot and item
-- cooldowns, bag events, no use count).
e=E.b701
assert(e.spell==nil and e.equipSlot==13 and e.itemID==5555 and e.texture==5556 and e.name=="Trinket A")
assert(e.slot=="ess" and e.index==4 and e.family==1 and e.category==7 and e.known,"the trinket ends the Essential bar")
Index.Rebuild()
Same("64 byEquip 13",Keys(Index.byEquip[13]),"b701")
Same("64 byItem 5555",Keys(Index.byItem[5555]),"b701")
Same("64 bags",Keys(Index.bags),"b701")
assert(Index.byEquip[13][1]==e and Index.byItem[5555][1]==e and Index.bags[1]==e,"trinket routes on Essential")
local counted=false
for i=1,#Index.counted do if Index.counted[i]==e then counted=true end end
assert(not counted,"a trinket has no use count")
-- Preview: unlearned Blizzard entries and placeholders on empty shown bars.
C.state.specID=63
C.state.preview=true
plans=Resolve.Build()
-- Unlearned trinkets stay after Essential's own entries; the learned one
-- (slot 13) is c1's e13.
Same("p ess",Keys(plans.ess.entries),"b101,s9001,b104,b702")
Same("p ext",Keys(plans.ext.entries),"b501,b502")
Same("p c1",Keys(plans.c1.entries),"b102,s9002,i7001,e13,s1001,s9004")
Same("p c4",Keys(plans.c4.entries),"pc4_1,pc4_2,pc4_3")
Same("p def",Keys(plans.def.entries),"pdef_1,pdef_2,pdef_3")     -- unnamed preset spells never fill it
e=plans.c4.entries[2]
assert(e.src=="p" and e.texture==134400 and e.family==2 and e.slot=="c4" and e.index==2 and e.known and E[e.key]==e)
-- Aura placeholders count in the player part (one container, no target row).
for i=1,#plans.c4.entries do Same("placeholder unit "..i,plans.c4.entries[i].unit,"player") end
assert(plans.def.entries[1].unit==nil,"a cooldown placeholder watches no unit")
assert(E.b104.known==false)
C.state.preview=false
plans=Resolve.Build()
assert(#plans.c4.entries==0 and E.pc4_1==nil and E.b104==nil)
-- Options helpers.
Same("keys c3",Keys(Resolve.Keys("c3")),"b107")
Same("keys ess",Keys(Resolve.Keys("ess")),"b101,s9001,b104,b702")
local d=Resolve.Describe("s9004",{})
assert(d and d.known==false and d.name=="Other spec" and Resolve.Describe("s424242")==nil and Resolve.Describe("zz")==nil)
assert(C.entries.s9004==nil,"Describe leaves live entries alone")

------------------------------------------------------------------ picker rows
-- Rows carry their spell IDs, so the picker finds a Blizzard entry by the ID
-- players know. Trinket slots are the page's own section, never a second
-- copy here.
local rows=Catalog.List(1)
local byKey={}
for _,row in ipairs(rows) do byKey[row.key]=row end
assert(byKey.b101.slot=="ess" and byKey.b102.slot=="c1" and byKey.b104.known==false and byKey.b103.category==-1)
assert(byKey.b201==nil and byKey.e13==nil and byKey.e14==nil and rows[#rows].key:sub(1,1)=="b","no trinket rows")
assert(byKey.b101.spell==1001 and byKey.b102.spell==1002 and byKey.b107.spell==nil,"rows carry the spell ID")
assert(byKey.b701 and byKey.b701.slot==nil,"the trinket record has no home while c1 lists its slot")
rows=Catalog.List(2)
byKey={}
for _,row in ipairs(rows) do byKey[row.key]=row end
assert(byKey.b201.slot=="c2" and byKey.b203 and byKey.b801 and byKey.b101==nil and byKey.e13==nil)
assert(byKey.b201.spell==2001 and byKey.b801.spell==8001)

------------------------------------------------------------------ index
Index.Rebuild()
Same("cooldown",Keys(Index.cooldown),"b101,s9001,b112,b501,b502,b102,s9002,i7001,e13,s1001")
Same("charged",Keys(Index.charged),"b112,s9002")
Same("ranged",Keys(Index.ranged),"b101,b112,b102,s9002,s1001")
Same("usable",Keys(Index.usable),"b101,s9001,b112")
Same("proc",Keys(Index.proc),"s9001,b112,b501,b502,b102")
Same("items",Keys(Index.items),"b501,i7001,e13")
Same("aura",Keys(Index.aura),"b202,b801,b601,b301,a9101,d9102,b201")
Same("overlay",Keys(Index.overlay),"b101")
Same("assist",Keys(Index.assist),"b101,s9001")
Same("bySpell 1001",Keys(Index.bySpell[1001]),"b101,s1001")
Same("bySpell 9003",Keys(Index.bySpell[9003]),"s9002")
Same("byItem 5555",Keys(Index.byItem[5555]),"e13")
Same("byEquip 13",Keys(Index.byEquip[13]),"e13")
Same("byCategory 30",Keys(Index.byCategory[30]),"b501")
-- Item cooldowns reach real items only; potion categories follow their
-- SPELL_UPDATE_COOLDOWN payload. Use counts matter where counts show.
Same("bags",Keys(Index.bags),"i7001,e13")
Same("counted",Keys(Index.counted),"b101,s9001,b112,b502,b102,s9002,s1001")
-- The trinket slot routes from its one home (c1's e13); the spec 64 block
-- above covers Blizzard's record on Essential.
assert(E.b701==nil and Index.byEquip[13][1]==E.e13 and Index.byItem[5555][1]==E.e13,"one route per equipment slot")
-- A category of 0 is no category (0 is truthy): a plain spell stays out of
-- the bag lists and keeps its use count.
E.b101.spellCategory=0
Index.Rebuild()
Same("items, category 0",Keys(Index.items),"b501,i7001,e13")
Same("counted, category 0",Keys(Index.counted),"b101,s9001,b112,b502,b102,s9002,s1001")
assert(Index.byCategory[0]==nil,"category 0 must not be routed")
E.b101.spellCategory=nil
Index.Rebuild()
Same("byBase 1002",Keys(Index.byBase[1002]),"b102")
Same("byBase aura",Keys(Index.byBase[9101]),"a9101")
Same("catalog byBase",Keys(Catalog.byBase[1002]),"b102")
local hits,last=0,nil
local function Hit(entry) hits=hits+1;last=entry end
Same("ForSpell shared base",Index.ForSpell(1001,nil,Hit),2)
Same("ForItem",Index.ForItem(5555,Hit),1)
Same("byEquip",#Index.byEquip[13],1)
Same("ForCategory",Index.ForCategory(30,Hit),1)
Same("ForSpell miss",Index.ForSpell(424242,nil,Hit),0)
Same("ForSpell secret",Index.ForSpell(Secret(),Secret(),Hit),0)
Same("ForItem secret",Index.ForItem(Secret(),Hit),0)
-- Override arrives: record and live entry follow; base + override dedupe.
textures[1002]={4242,4243,nil}
assert(Catalog.OnOverride(1002,1003)==true and recs[102].override==1003)
assert(b102.override==1003 and b102.spell==1003 and b102.prevOverride==nil and b102.texture==4242 and b102.name=="Hot Pyroblast")
assert(Catalog.OnOverride(Secret(),5)==false and Catalog.OnOverride(1002,1003)==false)
-- A base nothing tracks costs one lookup per map (records, live entries).
local misses=0
local counting={__index=function() misses=misses+1 end}
setmetatable(Catalog.byBase,counting);setmetatable(Index.byBase,counting)
assert(Catalog.OnOverride(424242,5)==false and misses==2,"an untracked override base cost "..misses.." lookups")
setmetatable(Catalog.byBase,nil);setmetatable(Index.byBase,nil)
-- In combat the new ID is routed without a rebuild, once, cooldown entries only.
Same("not routed yet",Index.ForSpell(1003,nil,Hit),0)
Index.AddSpell(b102,1003);Index.AddSpell(b102,1003)
Same("routed once",Index.ForSpell(1003,nil,Hit),1)
Index.AddSpell(E.b201,777)
assert(Index.bySpell[777]==nil,"aura entries take no cooldown routes")
Index.Rebuild()
hits=0
Same("ForSpell dedupe",Index.ForSpell(1003,1002,Hit),1)
assert(hits==1 and last==b102)
Same("ForSpell override only",Index.ForSpell(1003,nil,Hit),1)
-- Override removed: the previous override ID still routes to the entry.
assert(Catalog.OnOverride(1002,nil)==true and b102.override==nil and b102.prevOverride==1003 and b102.spell==1002)
Index.Rebuild()
Same("previous override",Index.ForSpell(1003,nil,Hit),1)
Same("resolve keeps override",Resolve.Build() and b102.override,nil)

-- Zero allocation in the hot lookup (two lists with dedupe, and one list).
Catalog.OnOverride(1002,1003)
Index.Rebuild()
Index.ForSpell(1003,1002,Hit);Index.ForSpell(1001,nil,Hit)
collectgarbage("collect")
collectgarbage("stop")
local before=collectgarbage("count")
for _=1,1000 do
    Index.ForSpell(1003,1002,Hit)
    Index.ForSpell(1001,nil,Hit)
    Index.ForItem(5555,Hit)
    Catalog.OnOverride(424242,5)
    Index.ForBase(424242,Hit)
end
local after=collectgarbage("count")
collectgarbage("restart")
assert(after==before,"ForSpell allocated "..((after-before)*1024).." bytes")

-- Late load: the Essential set is already filled, so the fallback reports
-- ready at once and no gate frame is ever made.
local lateFrame
local create=CreateFrame
CreateFrame=function(...) lateFrame=create(...);return lateFrame end
local late={NS=NS,Suite=S,CDM={EMPTY={},state={},views={},plans={},entries={},Const=C.Const,wipe=C.wipe}}
assert(loadfile(root.."/MSUF_Suite_CooldownManager/Catalog.lua"))("MSUF_Suite_CooldownManager",late)
assert(lateFrame==nil and late.CDM.Catalog.Ready() and lateFrame==nil,"ready without a gate frame")
assert(late.CDM.Catalog.Rebuild()==true and #late.CDM.Catalog.byBar.ess==4)
-- Loaded after login with Blizzard's data still missing: only the data
-- event is left to wait for.
IsLoggedIn=function() return true end
sets[0]={}
late={NS=NS,Suite=S,CDM={EMPTY={},state={},views={},plans={},entries={},Const=C.Const,wipe=C.wipe}}
assert(loadfile(root.."/MSUF_Suite_CooldownManager/Catalog.lua"))("MSUF_Suite_CooldownManager",late)
assert(not late.CDM.Catalog.Ready() and lateFrame and lateFrame.events.COOLDOWN_VIEWER_DATA_LOADED
    and not lateFrame.events.VARIABLES_LOADED and not lateFrame.events.PLAYER_ENTERING_WORLD,"after login only the data event")
lateFrame.scripts.OnEvent(lateFrame,"COOLDOWN_VIEWER_DATA_LOADED")
assert(late.CDM.Catalog.Ready() and next(lateFrame.events)==nil,"the data event completes the gate")
CreateFrame,IsLoggedIn,sets[0]=create,nil,essSet

------------------------------------------------------------------ presets: data
-- Every class has a list; racials and the bag-item categories Blizzard draws
-- icons for carry plain IDs, none listed twice.
local Presets=C.Presets
local function Unique(label,ids)
    assert(type(ids)=="table" and #ids>0,label.." empty")
    local seen={}
    for i=1,#ids do
        local id=ids[i]
        assert(type(id)=="number" and id>0 and math.floor(id)==id and not seen[id],label..": "..tostring(id))
        seen[id]=true
    end
end
for classID=1,13 do Unique("defensives "..classID,Presets.DEFENSIVES[classID]) end
Unique("racials",Presets.RACIALS)
for _,category in ipairs({4,30,1711,2566}) do Unique("category "..category,Presets.CATEGORY_ITEMS[category]) end
-- The class is UnitClass's third return; an unknown class has no list.
assert(Presets.Defensives()==Presets.DEFENSIVES[8],"Mage list")
UnitClass=function() return "Warrior","WARRIOR",1 end
assert(Presets.Defensives()==Presets.DEFENSIVES[1],"Warrior list")
UnitClass=function() return nil end
assert(Presets.Defensives()==C.EMPTY,"no class, no list")
UnitClass=function() return "Mage","MAGE",8 end

------------------------------------------------------------------ presets: resolve
-- World: Ice Block on Utility with Ice Cold linked (two preset IDs, one
-- entry), Mirror Image linked from an Essential entry, Blazing Barrier as a
-- Utility override, Ice Barrier unlearned on Utility. Alter Time (learned)
-- and Greater Invisibility (unlearned) have no Blizzard entry. Arcane Torrent
-- is this character's racial; Berserking and Stoneform are other races'.
sets[0]={101,102,103,104,107,105}
sets[1]={111,112,SECRET_ID,113,114,115}
infos[105]=Info(105,0,1006,{linkedSpellIDs={55342}})
infos[113]=Info(113,1,45438,{linkedSpellIDs={414658}})
infos[114]=Info(114,1,1114,{overrideSpellID=235313})
infos[115]=Info(115,1,11426,{isKnown=false})
for id,name in pairs({[1006]="Frostbolt",[1114]="Barrier",[45438]="Ice Block",[55342]="Mirror Image",
    [235313]="Blazing Barrier",[11426]="Ice Barrier",[342245]="Alter Time",[110959]="Greater Invisibility",
    [28730]="Arcane Torrent",[26297]="Berserking",[20594]="Stoneform"}) do
    names[id],textures[id]=name,{id+100000,id+200000,nil}
end
known[342245],known[28730]=true,true
assert(Catalog.Rebuild()==true,"preset records arrive")
local BASE={ess={"b101","s9001"},c1={"b102","s9002","i7001","e13","a9101","s1001","s9004"},
    c2={"a9101","d9102","b201","b112"},c3={"b107"}}
local function SetLists(slots,hide)
    local spec,hidden={},{b111=true}
    for slot,list in pairs(BASE) do spec[slot]=list end
    for slot,list in pairs(slots or {}) do spec[slot]=list end
    for key in pairs(hide or {}) do hidden[key]=true end
    C.lists=CDM.CleanLists({specs={[63]=spec},hidden={[63]=hidden}})
end
local function Bars(label,want)
    for slot,keys in pairs(want) do Same(label.." "..slot,Keys(plans[slot] and plans[slot].entries or {}),keys) end
end
SetLists()
C.state.specID,C.state.preview=63,false
plans=Resolve.Build()
-- Defensives in preset order claim their Blizzard entries (base, linked or
-- override ID) off Essential and Utility; unlearned and unnamed spells drop
-- out. The racial follows Blizzard's Potions and racials entries.
Bars("preset",{def="b113,s342245,b105,b114",ess="b101,s9001",uti="b112",ext="b501,b502,s28730"})
e=E.b113
assert(e.src=="b" and e.slot=="def" and e.index==1 and e.name=="Ice Block" and e.known)
e=E.s342245
assert(e.src=="s" and e.family==1 and e.slot=="def" and e.index==2 and e.known and e.name=="Alter Time" and e.texture==442245)
assert(E.b105.index==3 and E.b105.linked[1]==55342 and E.b114.spell==235313 and E.b114.name=="Blazing Barrier")
assert(E.s28730.src=="s" and E.s28730.slot=="ext" and E.s28730.index==3)
assert(E.s110959==nil and E.b115==nil and E.s26297==nil and E.s20594==nil and E.s414658==nil,"unlearned presets stay out")
-- Preview: the unlearned Blizzard entry dims on Defensives like any other;
-- preset-only spells stay hidden (other builds' talents, other races' racials).
C.state.preview=true
plans=Resolve.Build()
Bars("preset p",{def="b113,s342245,b105,b114,b115",uti="b112",ess="b101,s9001,b104,b702",ext="b501,b502,s28730"})
assert(E.b115.known==false and E.b115.slot=="def" and E.s110959==nil and E.s26297==nil and E.s20594==nil)
C.state.preview=false
-- The preset claims only while Defensives is shown: switched off, its
-- spells go back to their Blizzard bars.
C.views.def.on=false
plans=Resolve.Build()
Bars("preset off",{ess="b101,s9001,b105",uti="b112,b113,b114",ext="b501,b502,s28730"})
assert(plans.def==nil and E.s342245==nil,"a preset-only spell has no bar while Defensives is off")
C.views.def.on=true
plans=Resolve.Build()
Bars("preset on",{def="b113,s342245,b105,b114",uti="b112"})
-- A spec without lists or hidden entries gets the same preset.
C.state.specID=64
plans=Resolve.Build()
Bars("preset 64",{def="b113,s342245,b105,b114",ess="b101,b102,b107,b701",uti="b111,b112",ext="b501,b502,s28730"})
C.state.specID=63
-- User lists claim first: presets take only what is left.
SetLists({c1={"b102","s9002","i7001","e13","a9101","s1001","s9004","b114","s28730"}})
plans=Resolve.Build()
Bars("claim",{c1="b102,s9002,i7001,e13,s1001,b114,s28730",def="b113,s342245,b105",uti="b112",ext="b501,b502"})
-- A user list for Defensives replaces the preset: its entries ignore the
-- hidden set, the preset's Blizzard entries return to their own bars and the
-- preset-only spell is gone. A listed preset spell (the options page copies
-- the preset on the first edit) still stays hidden while unlearned.
SetLists({def={"b111","b112","s110959"}})
plans=Resolve.Build()
Bars("list",{def="b111,b112",ess="b101,s9001,b105",uti="b113,b114",ext="b501,b502,s28730"})
assert(E.s342245==nil and E.b111.slot=="def" and E.b112.index==2)
C.state.preview=true
plans=Resolve.Build()
Bars("list p",{def="b111,b112",uti="b113,b114,b115"})
C.state.preview=false
SetLists({def={}})
plans=Resolve.Build()
Bars("empty list",{def="",ess="b101,s9001,b105",uti="b112,b113,b114"})
-- The hidden set removes preset entries (Defensives and the racial); a
-- hidden Blizzard entry does not fall back to its own bar.
SetLists(nil,{b113=true,s342245=true,s28730=true})
plans=Resolve.Build()
Bars("hidden",{def="b105,b114",uti="b112",ess="b101,s9001",ext="b501,b502"})
-- A hidden trinket leaves Essential like any other Blizzard entry.
SetLists(nil,{b701=true})
plans=Resolve.Build()
Bars("hidden trinket",{ess="b101,s9001",ext="b501,b502,s28730"})
assert(E.b701==nil,"a hidden trinket has no entry")
-- A user list for Potions and racials keeps the racial after Blizzard's entries.
SetLists({ext={"b501"}})
plans=Resolve.Build()
Bars("ext list",{ext="b501,b502,s28730",ess="b101,s9001"})
-- A trinket the user listed on Potions and racials (lists from before
-- trinkets moved) stays there: explicit lists claim first.
SetLists({ext={"b701","b501"}})
plans=Resolve.Build()
Bars("ext trinket list",{ext="b701,b501,b502,s28730",ess="b101,s9001"})
assert(E.b701.slot=="ext" and E.b701.index==1)
-- An equipment slot has one home, like a spell: the first bar (menu order)
-- that lists it (e13). Blizzard's record for the same slot then stays off
-- every bar, that one included, so the trinket shows once.
SetLists({ess={"b101","e13","s9001"}})
plans=Resolve.Build()
Bars("e13 on ess",{ess="b101,e13,s9001",c1="b102,s9002,i7001,s1001"})
assert(E.e13.slot=="ess" and E.b701==nil,"one icon per equipment slot on a bar")
C.state.preview=true
plans=Resolve.Build()
Bars("e13 on ess p",{ess="b101,e13,s9001,b104,b702"})
C.state.preview=false
-- The slot listed on Potions and racials (where the picker's trinket rows
-- used to go) takes the trinket off Essential; c1's later e13 yields.
SetLists({ext={"e13"}})
plans=Resolve.Build()
Bars("e13 on ext",{ext="e13,b501,b502,s28730",ess="b101,s9001",c1="b102,s9002,i7001,s1001",buf="b202,b801,b601"})
assert(E.e13.slot=="ext" and E.b701==nil,"one home per equipment slot")
C.state.preview=true
plans=Resolve.Build()
Bars("e13 on ext p",{ess="b101,s9001,b104,b702",ext="e13,b501,b502,s28730"})
C.state.preview=false
Same("keys ess (e13 on ext)",Keys(Resolve.Keys("ess")),"b101,s9001,b104,b702")
SetLists()
plans=Resolve.Build()
Bars("e13 on c1",{ess="b101,s9001",c1="b102,s9002,i7001,e13,s1001"})
-- Released, the slot goes back to Blizzard's record on Essential.
SetLists({c1={"b102"}})
plans=Resolve.Build()
Bars("e13 released",{ess="b101,s9001,b701",c1="b102"})
assert(E.b701.slot=="ess" and E.e13==nil)
-- Explicit unlearned spells preview; preset spells never do, listed or not.
SetLists({c1={"s9004","s26297","s110959"}})
C.state.preview=true
plans=Resolve.Build()
Bars("explicit p",{c1="s9004",def="b113,s342245,b105,b114,b115",ext="b501,b502,s28730"})
assert(E.s9004.known==false and E.s26297==nil and E.s110959==nil)
C.state.preview=false
plans=Resolve.Build()
Bars("explicit",{c1=""})
-- The preset follows the class, rebuilt with the catalog generation.
UnitClass=function() return "Warrior","WARRIOR",1 end
Catalog.Rebuild()
SetLists()
plans=Resolve.Build()
Bars("warrior",{def="",ess="b101,s9001,b105",uti="b112,b113,b114",ext="b501,b502,s28730"})
UnitClass=function() return "Mage","MAGE",8 end
Catalog.Rebuild()
plans=Resolve.Build()
Bars("mage again",{def="b113,s342245,b105,b114"})
-- Options helpers: the keys a bar holds include unlearned Blizzard entries
-- (the page dims them) but, like every preview, no unlearned preset spell.
Same("keys def",Keys(Resolve.Keys("def")),"b113,s342245,b105,b114,b115")
Same("keys ext",Keys(Resolve.Keys("ext")),"b501,b502,s28730")
Same("keys ess (presets)",Keys(Resolve.Keys("ess")),"b101,s9001,b104,b702")

------------------------------------------------------------------ presets: healthstones
-- Potions and racials offers the Healthstone and the Demonic Healthstone
-- (Presets.CONSUMABLES, plain item entries) after Blizzard's entries and
-- before the racial. A learned Blizzard record of the same spellCategory,
-- on any bar, replaces its item, so each healthstone shows once. Both kinds
-- hide while the bags hold none (hideEmpty); potions and spells never do.
local CONSUMABLES=Presets.CONSUMABLES
assert(#CONSUMABLES==2 and CONSUMABLES[1].item==5512 and CONSUMABLES[1].category==1711
    and CONSUMABLES[2].item==224464 and CONSUMABLES[2].category==2566,"the Healthstone, then the Demonic Healthstone")
for i=1,#CONSUMABLES do
    local c=CONSUMABLES[i]
    assert(Presets.CATEGORY_ITEMS[c.category][1]==c.item,"item "..c.item.." counts for its category")
end
-- An item the client has no icon for makes no entry and no key for the page.
Bars("no stone icons",{ext="b501,b502,s28730"})
local itemIcons={[7001]=777,[5555]=5556,[5512]=538745,[224464]=538744}
local itemNames={[7001]="Potion",[5555]="Trinket A",[5512]="Healthstone",[224464]="Demonic Healthstone"}
local getIcon,getName=C_Item.GetItemIconByID,C_Item.GetItemNameByID
C_Item.GetItemIconByID=function(id) return itemIcons[id] end
C_Item.GetItemNameByID=function(id) return itemNames[id] end
plans=Resolve.Build()
Bars("healthstones",{ext="b501,b502,i5512,i224464,s28730",ess="b101,s9001"})
Same("keys ext (healthstones)",Keys(Resolve.Keys("ext")),"b501,b502,i5512,i224464,s28730")
e=E.i5512
assert(e.src=="i" and e.itemID==5512 and e.slot=="ext" and e.index==3 and e.known and e.hideEmpty==true
    and e.texture==538745 and e.name=="Healthstone","the Healthstone item entry")
assert(E.i224464.index==4 and E.i224464.hideEmpty==true and E.s28730.index==5,"potions, healthstones, racial")
assert(E.b501.hideEmpty==false and E.b502.hideEmpty==false and E.b101.hideEmpty==false and E.s28730.hideEmpty==false,
    "potions and spells never hide")
-- Routed like any bag item: contents and item cooldowns.
Index.Rebuild()
local function Has(list,entry) for i=1,#list do if list[i]==entry then return true end end return false end
Same("byItem 5512",Keys(Index.byItem[5512]),"i5512")
assert(Has(Index.items,E.i5512) and Has(Index.bags,E.i5512) and Has(Index.items,E.i224464) and Has(Index.bags,E.i224464),
    "healthstones follow bag contents and item cooldowns")
-- The per-spec hidden set removes one like the racial.
SetLists(nil,{i5512=true})
plans=Resolve.Build()
Bars("stone hidden",{ext="b501,b502,i224464,s28730"})
assert(E.i5512==nil,"a removed healthstone has no entry")
-- A user list for Potions and racials keeps them after Blizzard's entries,
-- in place when the list names one.
SetLists({ext={"b501"}})
plans=Resolve.Build()
Bars("stones after a list",{ext="b501,b502,i5512,i224464,s28730"})
SetLists({ext={"i224464","b502"}})
plans=Resolve.Build()
Bars("listed stone",{ext="i224464,b502,b501,i5512,s28730"})
-- User lists claim first: a healthstone listed on a custom bar lives there.
SetLists({c1={"b102","s9002","i7001","e13","a9101","s1001","s9004","i5512"}})
plans=Resolve.Build()
Bars("stone on c1",{c1="b102,s9002,i7001,e13,s1001,i5512",ext="b501,b502,i224464,s28730"})
-- The preset claims only while Potions and racials is shown.
SetLists()
C.views.ext.on=false
plans=Resolve.Build()
assert(plans.ext==nil and E.i5512==nil and E.i224464==nil,"no healthstone entry while the bar is off")
C.views.ext.on=true
-- Blizzard's own records: a learned Healthstone record on Potions and
-- racials, and a Demonic Healthstone record a Blizzard layout moved to
-- Essential, each replace their item. Both hide while empty.
local essSetPresets,extSet=sets[0],sets[5]
sets[0]={101,102,103,104,107,105,504}
sets[5]={501,502,101,503}
infos[503]=Info(503,5,5003,{spellCategoryID=1711})
infos[504]=Info(504,0,5004,{spellCategoryID=2566})
Catalog.Rebuild()
plans=Resolve.Build()
Bars("blizzard stones",{ext="b501,b502,b503,s28730",ess="b101,s9001,b504"})
assert(E.i5512==nil and E.i224464==nil and E.b503.hideEmpty==true and E.b504.hideEmpty==true,"one healthstone each, Blizzard's")
assert(E.b503.texture=="Interface/ICONS/Warlock_ Healthstone" and E.b504.texture=="Interface/ICONS/Warlock_ Bloodstone")
Same("keys ext (blizzard stones)",Keys(Resolve.Keys("ext")),"b501,b502,b503,s28730")
-- An unlearned record does not count: the item stands in for it, and the
-- record stays out of previews and the page's keys next to it.
infos[503].isKnown=false
Catalog.Rebuild()
plans=Resolve.Build()
Bars("unlearned stone record",{ext="b501,b502,i5512,s28730"})
C.state.preview=true
plans=Resolve.Build()
Bars("unlearned stone record p",{ext="b501,b502,i5512,s28730"})
C.state.preview=false
Same("keys ext (unlearned record)",Keys(Resolve.Keys("ext")),"b501,b502,i5512,s28730")
-- A healthstone has two keys, its item and Blizzard's record, and a list can
-- hold either (the page saves the keys the bar shows). Both name one entry:
-- the learned record, else the item that stands in for it, at the list's
-- place. A list saved while the item stood in, after the record is learned:
SetLists({ext={"b501","b502","i5512","s28730"}})
plans=Resolve.Build()
Bars("listed stand-in",{ext="b501,b502,i5512,s28730"})
infos[503].isKnown=true
Catalog.Rebuild()
plans=Resolve.Build()
Bars("listed stand-in learned",{ext="b501,b502,b503,s28730"})
assert(E.i5512==nil and E.b503.index==3,"the record takes the item's place")
Same("keys ext (listed stand-in learned)",Keys(Resolve.Keys("ext")),"b501,b502,b503,s28730")
-- A list saved while the record was learned, after it is unlearned:
SetLists({ext={"b501","b502","b503","s28730"}})
plans=Resolve.Build()
Bars("listed record",{ext="b501,b502,b503,s28730"})
infos[503].isKnown=false
Catalog.Rebuild()
plans=Resolve.Build()
Bars("listed record unlearned",{ext="b501,b502,i5512,s28730"})
assert(E.b503==nil and E.i5512.index==3,"the item takes the record's place")
C.state.preview=true
plans=Resolve.Build()
Bars("listed record unlearned p",{ext="b501,b502,i5512,s28730"})
C.state.preview=false
Same("keys ext (listed record unlearned)",Keys(Resolve.Keys("ext")),"b501,b502,i5512,s28730")
-- A list that already holds both keys shows one, at the first one's place.
SetLists({ext={"i5512","b501","b503"}})
plans=Resolve.Build()
Bars("both keys",{ext="i5512,b501,b502,s28730"})
infos[503].isKnown=true
Catalog.Rebuild()
plans=Resolve.Build()
Bars("both keys learned",{ext="b503,b501,b502,s28730"})
Same("keys ext (both keys)",Keys(Resolve.Keys("ext")),"b503,b501,b502,s28730")
-- One home: a listed item takes its learned record along, off Blizzard's bar.
SetLists({c1={"b102","e13","i5512"},ext={"i224464"}})
plans=Resolve.Build()
Bars("stones listed as items",{c1="b102,e13,b503",ext="b504,b501,b502,s28730",ess="b101,s9001"})
assert(E.i5512==nil and E.i224464==nil and E.b503.slot=="c1" and E.b504.slot=="ext","one healthstone each")
SetLists()
infos[503].isKnown=false
sets[0],sets[5],infos[503],infos[504]=essSetPresets,extSet,nil,nil
C_Item.GetItemIconByID,C_Item.GetItemNameByID=getIcon,getName
Catalog.Rebuild()
plans=Resolve.Build()
Bars("stones gone",{ext="b501,b502,s28730"})

-- Across every catalog generation, spec and preview above, each spell ID was
-- asked whether it is harmful once.
for id,count in pairs(harmfulCalls) do Same("asked once in the run "..id,count,1) end

print("cooldown manager data contract ok: "..#Catalog.order.." records, "..#Index.cooldown.." cooldown entries")
