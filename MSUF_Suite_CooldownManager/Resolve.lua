local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Settings, spell lists and the Blizzard snapshot -> one plan per shown bar.
-- Rules: explicit list entries claim their key for the first bar that lists
-- them ("one spell, one home"); built-in bars follow Blizzard's order for
-- their categories minus hidden and claimed entries, and append new Blizzard
-- entries after an explicit list; custom bars show their list only; an entry
-- of the wrong family for the bar is skipped. Entry tables are reused by key
-- so runtime fields (icon, cooling, glows) survive a rebuild. Cold path.
local Public=S.Public
local type,pairs,tonumber=type,pairs,tonumber
local EMPTY=C.EMPTY
local wipe=wipe or table.wipe or function(t) for k in pairs(t) do t[k]=nil end return t end
local CDM=NS.CDM
local SLOTS=CDM.SLOTS
local Catalog=C.Catalog
local Num=Catalog.Num

local Resolve={}
C.Resolve=Resolve

local KIND_FAMILY={1,2,2}
local SOURCE_FAMILY={s=1,i=1,e=1,a=2,d=2}
local PLACEHOLDER_TEXTURE,PLACEHOLDER_COUNT=134400,3
local placeholderKeys={}
for i=1,#SLOTS do
    local slot,keys=SLOTS[i].key,{}
    for n=1,PLACEHOLDER_COUNT do keys[n]="p"..slot.."_"..n end
    placeholderKeys[slot]=keys
end

-- Keys are parsed once per distinct string.
local srcOf,idOf={},{}
local function Parse(key)
    local src=srcOf[key]
    if src==nil then
        src=false
        if type(key)=="string" and CDM.ValidEntryKey(key) then src,idOf[key]=key:sub(1,1),tonumber(key:sub(2)) end
        srcOf[key]=src
    end
    return src,idOf[key]
end
local function FamilyOf(key)
    local src,id=Parse(key)
    if src=="b" then
        local rec=Catalog.records[id]
        return rec and rec.family
    end
    return src and SOURCE_FAMILY[src] or nil
end
Resolve.FamilyOf=FamilyOf

------------------------------------------------------------------ plain lookups
local function HasRange(spell)
    local has=spell and C_Spell and C_Spell.SpellHasRange
    local result=has and has(spell)
    return Public(result) and result==true
end
-- maxCharges is NeverSecret; checked anyway.
local function Charged(spell)
    local get=spell and C_Spell and C_Spell.GetSpellCharges
    local info=get and get(spell)
    if not (Public(info) and type(info)=="table") then return false end
    local max=info.maxCharges
    return Public(max) and type(max)=="number" and max>1
end
local function Known(spell)
    local book=C_SpellBook
    local check=book and (book.IsSpellKnownOrInSpellBook or book.IsSpellKnown)
    if not check then return true end
    local known=check(spell)
    if Public(known) and known==true then return true end
    local pet=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if pet==nil then return false end
    known=check(spell,pet)
    return Public(known) and known==true
end
local function BaseSpell(id)
    local get=C_Spell and C_Spell.GetBaseSpell
    return get and Num(get(id)) or id
end
local function OverrideOf(base)
    local find=C_SpellBook and C_SpellBook.FindSpellOverrideByID
    local id=find and Num(find(base))
    if id and id~=base then return id end
end

------------------------------------------------------------------ entry fill
local function SetOverride(e,override)
    if e.override~=override then e.prevOverride=e.override; e.override=override end
end
local function AuraSet(set,a,b,c,linked)
    if set then wipe(set) else set={} end
    if a then set[a]=true end
    if b then set[b]=true end
    if c then set[c]=true end
    if linked then for i=1,#linked do set[linked[i]]=true end end
    return set
end
-- Resets the source fields; auraIDs is left for the caller so its table is reused.
local function Clear(e,src,id,family)
    e.src,e.id,e.family,e.category=src,id,family,nil
    e.selfAura,e.hasAura,e.charges,e.hasRange=false,false,false,false
    e.equipSlot,e.itemID,e.spellCategory,e.tooltip=nil,nil,nil,nil
    e.linked,e.unit=EMPTY,nil
end

local function FillBlizzard(e,rec)
    local base,override,family=rec.spell,rec.override,rec.family
    Clear(e,"b",rec.id,family)
    SetOverride(e,override)
    e.base,e.tooltip,e.spell,e.linked,e.category=base,rec.tooltip,override or base,rec.linked,rec.category
    e.selfAura,e.hasAura,e.charges,e.known=rec.selfAura,rec.hasAura,rec.charges,rec.known
    e.equipSlot,e.spellCategory=rec.equipSlot,rec.spellCategory
    e.itemID=rec.equipSlot and Catalog.EquipItem(rec.equipSlot) or nil
    e.hasRange=family==1 and base~=nil and HasRange(base)
    e.texture,e.name=Catalog.RecordTexture(rec),Catalog.RecordName(rec)
    if family==2 or rec.hasAura then
        e.auraIDs=AuraSet(e.auraIDs,base,override,rec.tooltip,rec.linked)
        -- Blizzard's viewer looks for every tracked aura on the player and on
        -- the target (selfAura is not used for that), so a debuff such as
        -- Deathstalker's Mark shows from a buff bar too.
        e.unit="both"
    else
        e.auraIDs=nil
    end
    return true
end
local function FillSpell(e,id)
    local name=Catalog.SpellName(id)
    if not name then return false end
    local base=BaseSpell(id)
    local override=OverrideOf(base)
    local spell=override or base
    Clear(e,"s",id,1)
    SetOverride(e,override)
    e.base,e.spell=base,spell
    e.charges,e.known,e.hasRange=Charged(spell),Known(base),HasRange(base)
    e.texture,e.name=Catalog.SpellTexture(base),Catalog.SpellName(spell) or name
    e.auraIDs=nil
    return true
end
local function FillItem(e,id)
    local icon=Catalog.ItemIcon(id)
    if not icon then return false end
    local spell=Catalog.ItemSpell(id)
    Clear(e,"i",id,1)
    SetOverride(e,nil)
    e.base,e.spell,e.itemID,e.known=spell,spell,id,true
    e.texture,e.name=icon,Catalog.ItemName(id)
    e.auraIDs=nil
    return true
end
local function FillEquip(e,slot)
    local item=Catalog.EquipItem(slot)
    local spell=item and Catalog.ItemSpell(item) or nil
    Clear(e,"e",slot,1)
    SetOverride(e,nil)
    e.base,e.spell,e.equipSlot,e.itemID,e.known=spell,spell,slot,item,item~=nil
    e.texture=Catalog.EquipTexture(slot)
    e.name=item and Catalog.ItemName(item) or Catalog.SlotLabel(slot)
    e.auraIDs=nil
    return true
end
local function FillAura(e,src,id)
    local name,texture=Catalog.SpellName(id),Catalog.SpellTexture(id)
    if not (name or texture) then return false end
    Clear(e,src,id,2)
    SetOverride(e,nil)
    e.base,e.spell,e.known=id,id,true
    e.selfAura,e.hasAura=src=="a",true
    e.texture,e.name=texture,name
    e.auraIDs=AuraSet(e.auraIDs,id)
    e.unit=src=="a" and "player" or "target"
    return true
end
local function Fill(e,key)
    local src,id=Parse(key)
    if src=="b" then
        local rec=Catalog.records[id]
        return rec~=nil and FillBlizzard(e,rec)
    elseif src=="s" then return FillSpell(e,id)
    elseif src=="i" then return FillItem(e,id)
    elseif src=="e" then return FillEquip(e,id)
    elseif src=="a" or src=="d" then return FillAura(e,src,id) end
    return false
end

------------------------------------------------------------------ presets
-- Preset rows (Presets.lua): spell IDs become the Blizzard entry that tracks
-- the spell when the catalog has one (base, override or linked ID), so the
-- row claims it off Essential/Utility; otherwise a plain spell entry. Built
-- once per catalog generation. Unlearned spells drop out in Materialize.
-- presetSpell: plain spell keys that come only from a preset; unlearned ones
-- stay hidden even in previews (every race's racial, other specs' spells).
local presetKeys,presetGen,presetSeen,spellKey,presetSpell={},nil,{},{},{}
local function PresetLists()
    local gen=Catalog.generation
    if presetGen==gen then return presetKeys end
    presetGen=gen
    wipe(spellKey); wipe(presetSpell)
    for _,rec in pairs(Catalog.records) do
        if rec.family==1 then
            local key=rec.key
            if rec.spell and not spellKey[rec.spell] then spellKey[rec.spell]=key end
            if rec.override and not spellKey[rec.override] then spellKey[rec.override]=key end
            local linked=rec.linked
            for i=1,#(linked or EMPTY) do if not spellKey[linked[i]] then spellKey[linked[i]]=key end end
        end
    end
    local Presets=C.Presets
    for i=1,#SLOTS do
        local def=SLOTS[i]
        local ids=Presets and (def.preset=="defensives" and Presets.Defensives()
            or def.preset=="racials" and Presets.RACIALS) or nil
        if ids then
            local out=presetKeys[def.key] or {}
            local n=0
            wipe(presetSeen)
            for j=1,#ids do
                local id=ids[j]
                local key=spellKey[id]
                if not key then
                    -- A replaced spell and its replacement share one entry.
                    local base=BaseSpell(id)
                    key=spellKey[base]
                    if not key then key="s"..base; presetSpell[key]=true end
                end
                if not presetSeen[key] then presetSeen[key]=true; n=n+1; out[n]=key end
            end
            for j=#out,n+1,-1 do out[j]=nil end
            presetKeys[def.key]=out
        end
    end
    return presetKeys
end

------------------------------------------------------------------ claims and collection
local claimed,used,keys,tmp,placed,planCache={},{},{},{},{},{}

local function SpecData()
    local specID,lists=C.state.specID,C.lists
    local specLists,hidden=nil,EMPTY
    if specID~=nil and type(lists)=="table" then
        local specs=lists.specs
        specLists=type(specs)=="table" and specs[specID] or nil
        if type(specLists)~="table" then specLists=nil end
        local h=type(lists.hidden)=="table" and lists.hidden[specID]
        if type(h)=="table" then hidden=h end
    end
    return specLists,hidden
end
local function KindOf(i)
    local def=SLOTS[i]
    local view=C.views[def.key]
    return view and view.kind or def.kind or 1
end
-- The list a bar holds first: the user's list for this spec, or for the
-- Defensives row its preset while the user has none.
local function ListOf(i,specLists,presets)
    local def=SLOTS[i]
    local list=specLists and specLists[def.key]
    if type(list)=="table" then return list,true end
    if def.preset=="defensives" then return presets[def.key],false end
end
local function ClaimList(list,slot,family)
    for j=1,#list do
        local key=list[j]
        if claimed[key]==nil and FamilyOf(key)==family then claimed[key]=slot end
    end
end
-- A key is claimed by the first bar (menu order) whose list holds it and whose
-- kind can show it, so a bar switched to another kind releases its entries.
-- User lists claim first, presets take what is left.
local function Claim(specLists,presets)
    wipe(claimed)
    for pass=1,2 do
        for i=1,#SLOTS do
            local def=SLOTS[i]
            local family=KIND_FAMILY[KindOf(i)]
            local list,explicit=ListOf(i,specLists,presets)
            if list and explicit==(pass==1) then
                -- A preset only claims while its bar is shown; switched off,
                -- its spells go back to their Blizzard bars.
                local view=C.views[def.key]
                if explicit or (view and view.on) then ClaimList(list,def.key,family) end
            end
            if pass==2 and def.preset=="racials" and presets[def.key] then
                local view=C.views[def.key]
                if view and view.on then ClaimList(presets[def.key],def.key,family) end
            end
        end
    end
end
local function Collect(i,kind,specLists,hidden,preview,out,presets)
    local def=SLOTS[i]
    local slot,family=def.key,KIND_FAMILY[kind]
    local n=0
    wipe(used)
    local list,explicit=ListOf(i,specLists,presets)
    if list then
        for j=1,#list do
            local key=list[j]
            if claimed[key]==slot and not used[key] and (explicit or not hidden[key]) then
                used[key]=true; n=n+1; out[n]=key
            end
        end
    end
    if def.builtin and family then
        local records=Catalog.records
        -- Unlearned entries only in preview; they sit in Blizzard's global order.
        local source=preview and Catalog.order or Catalog.byBar[slot]
        for j=1,#(source or EMPTY) do
            local rec=records[source[j]]
            if rec and rec.bar==slot and rec.family==family then
                local key=rec.key
                local owner=claimed[key]
                if not used[key] and not hidden[key] and (owner==nil or owner==slot) then
                    used[key]=true; n=n+1; out[n]=key
                end
            end
        end
    end
    local extra=def.preset=="racials" and presets[slot]
    if extra then
        for j=1,#extra do
            local key=extra[j]
            if claimed[key]==slot and not used[key] and not hidden[key] then used[key]=true; n=n+1; out[n]=key end
        end
    end
    for j=#out,n+1,-1 do out[j]=nil end
    return n
end

------------------------------------------------------------------ refill changes
-- An entry that stays on its bar can still change on refill (a talent swaps
-- the override or the texture, a trinket swap changes the item). Those are
-- collected so the controller refreshes just them instead of every bar:
-- touched = entries whose filled fields changed, auraTouched = the subset
-- whose aura IDs or watched unit changed (their containers need a sync).
local WATCH={"spell","base","override","tooltip","texture","name","charges","hasRange","known","hasAura","selfAura",
    "unit","equipSlot","itemID","spellCategory","linked","family","category"}
local touched,auraTouched,was,wasIDs={},{},{},{}
Resolve.touched,Resolve.auraTouched=touched,auraTouched
local function Snapshot(e)
    for i=1,#WATCH do was[i]=e[WATCH[i]] end
    wipe(wasIDs)
    local ids=e.auraIDs
    if ids then for id in pairs(ids) do wasIDs[id]=true end end
end
local function SameIDs(ids)
    local n=0
    if ids then
        for id in pairs(ids) do
            if not wasIDs[id] then return false end
            n=n+1
        end
    end
    for _ in pairs(wasIDs) do n=n-1 end
    return n==0
end
local function Compare(e)
    local diff=false
    for i=1,#WATCH do
        if was[i]~=e[WATCH[i]] then diff=true;break end
    end
    local aura=was[12]~=e.unit or was[10]~=e.hasAura or not SameIDs(e.auraIDs)
    if diff or aura then touched[#touched+1]=e end
    if aura then auraTouched[e]=true end
end

------------------------------------------------------------------ build
local function Materialize(key,slot,index,preview,spells)
    if placed[key] then return nil end
    local entries=C.entries
    local old=entries[key]
    local e=old or {key=key}
    if old then Snapshot(old) end
    if not Fill(e,key) or not (e.known or preview and not presetSpell[key]) then return nil end
    if old then Compare(old) end
    local ov=spells[key]
    e.slot,e.index,e.ov=slot,index,type(ov)=="table" and ov or EMPTY
    entries[key],placed[key]=e,true
    return e
end
local function Placeholder(slot,n,family)
    local key=placeholderKeys[slot][n]
    local e=C.entries[key] or {key=key}
    Clear(e,"p",n,family)
    SetOverride(e,nil)
    e.base,e.spell,e.known=nil,nil,true
    e.texture,e.name,e.auraIDs=PLACEHOLDER_TEXTURE,nil,nil
    if family==2 then e.unit="player" end
    e.slot,e.index,e.ov=slot,n,EMPTY
    C.entries[key],placed[key]=e,true
    return e
end
local function Fold(plan,kind,n)
    local list=plan.entries
    local diff=plan.kind~=kind or #list~=n
    for j=1,n do
        if list[j]~=tmp[j] then list[j]=tmp[j]; diff=true end
    end
    for j=#list,n+1,-1 do list[j]=nil end
    plan.kind=kind
    if diff then plan.gen=plan.gen+1 end
    return diff
end

-- Returns C.plans and whether any bar's entry list changed. Each plan's gen
-- increments when its list changes; Resolve.touched lists entries that kept
-- their place but changed on refill. view.maxIcons is applied by the layout.
function Resolve.Build()
    local views,plans,entries=C.views,C.plans,C.entries
    local preview=C.state.preview==true
    local specLists,hidden=SpecData()
    local spells=type(C.spells)=="table" and type(C.spells.e)=="table" and C.spells.e or EMPTY
    local presets=PresetLists()
    Claim(specLists,presets)
    wipe(placed);wipe(touched);wipe(auraTouched)
    local any=false
    for i=1,#SLOTS do
        local slot=SLOTS[i].key
        local view=views[slot]
        if view and view.on then
            local kind=KindOf(i)
            local plan=planCache[slot]
            if not plan then plan={slot=slot,entries={},gen=0}; planCache[slot]=plan end
            local count=Collect(i,kind,specLists,hidden,preview,keys,presets)
            local n=0
            for j=1,count do
                local e=Materialize(keys[j],slot,n+1,preview,spells)
                if e then n=n+1; tmp[n]=e end
            end
            if preview and n==0 then
                local family=KIND_FAMILY[kind] or 1
                for p=1,PLACEHOLDER_COUNT do n=n+1; tmp[n]=Placeholder(slot,p,family) end
            end
            for j=#tmp,n+1,-1 do tmp[j]=nil end
            if Fold(plan,kind,n) or plans[slot]~=plan then any=true end
            plans[slot]=plan
        elseif plans[slot] then
            plans[slot]=nil
            any=true
        end
    end
    -- Entries that left every bar lose their place; Icons releases their frames.
    for key,e in pairs(entries) do
        if not placed[key] then entries[key]=nil; e.slot,e.index=nil,nil end
    end
    return plans,any
end

------------------------------------------------------------------ options helpers
-- Keys a bar would hold for the current spec, shown or not, unlearned
-- Blizzard entries included (the page dims them). Cold.
function Resolve.Keys(slot,out)
    out=out or {}
    local i=CDM.SLOT_INDEX[slot]
    if not i then wipe(out); return out end
    local specLists,hidden=SpecData()
    local presets=PresetLists()
    Claim(specLists,presets)
    local n=Collect(i,KindOf(i),specLists,hidden,true,out,presets)
    -- Preset-only spells the character does not know never show (Materialize).
    local m=0
    for j=1,n do
        local key=out[j]
        local _,id=Parse(key)
        if not presetSpell[key] or Known(BaseSpell(id)) then m=m+1; out[m]=key end
    end
    for j=n,m+1,-1 do out[j]=nil end
    return out
end
-- Fills a caller-owned table with the entry fields for one key without
-- touching the live entries. Nil when the key resolves to nothing.
function Resolve.Describe(key,out)
    out=out or {}
    if not Fill(out,key) then return nil end
    out.key=key
    return out
end
