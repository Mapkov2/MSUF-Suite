local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Event routing. Rebuilt (cold) after a resolve that changed something:
-- spell, base, category, item and equip-slot maps to the entries on shown
-- bars, plus consumer arrays so each event walks only the entries that care
-- and registers only while an array is non-empty. The For* lookups run
-- inside combat events: no allocation, callbacks are prebuilt by the caller,
-- and the two-list spell case dedupes through one reused set. A lookup that
-- matches nothing costs one or two table reads. Payload guards call the
-- client's issecretvalue directly (no Lua wrapper on hot paths).
local pairs=pairs
local SLOTS=NS.CDM.SLOTS
local K=C.Const
local issecret=type(_G.issecretvalue)=="function" and _G.issecretvalue or nil

-- countedSet: the counted entries by entry, for SPELL_UPDATE_USES routing.
local Index={bySpell={},byBase={},byCategory={},byItem={},byEquip={},countedSet={},
    cooldown={},charged={},counted={},ranged={},usable={},proc={},ready={},items={},bags={},aura={},overlay={},assist={}}
C.Index=Index

local ARRAYS={"cooldown","charged","counted","ranged","usable","proc","ready","items","bags","aura","overlay","assist"}
local MAPS={"bySpell","byBase","byCategory","byItem","byEquip"}
local pool={}
local seen={}

local function Release(map)
    for key,list in pairs(map) do
        for i=#list,1,-1 do list[i]=nil end
        pool[#pool+1]=list
        map[key]=nil
    end
end
-- An entry adds all its IDs in a row, so a repeated ID (base == tooltip, an
-- override also listed as linked) is caught by comparing with the last item.
local function Add(map,key,e)
    if key==nil then return end
    local list=map[key]
    if not list then
        local n=#pool
        list=pool[n]
        if list then pool[n]=nil else list={} end
        map[key]=list
    end
    if list[#list]~=e then list[#list+1]=e end
end
local function Push(list,e) list[#list+1]=e end

local function AddCooldown(e,view)
    local bySpell=Index.bySpell
    Push(Index.cooldown,e)
    Add(bySpell,e.base,e)
    Add(bySpell,e.override,e)
    Add(bySpell,e.tooltip,e)
    local linked=e.linked
    for i=1,#linked do Add(bySpell,linked[i],e) end
    -- The override may already be gone when its cooldown event arrives.
    Add(bySpell,e.prevOverride,e)
    -- A category of 0 is no category (plain spells), and 0 is truthy in Lua.
    local spell,category=e.spell,e.spellCategory
    if category==0 then category=nil end
    Add(Index.byCategory,category,e)
    Add(Index.byItem,e.itemID,e)
    Add(Index.byEquip,e.equipSlot,e)
    local item=e.src=="i" or e.src=="e" or e.equipSlot~=nil
    local ov=e.ov
    if e.charges then Push(Index.charged,e) end
    -- Use counts (SPELL_UPDATE_USES) only matter where spell counts show
    -- (the entry's or the bar's choice); items and potion categories show
    -- their bag count instead.
    if spell and view and not item and not category and K.Choice(ov.stackText,K.BarStacks(view,true)) then
        Push(Index.counted,e)
        Index.countedSet[e]=true
    end
    if e.hasRange and view and view.range then Push(Index.ranged,e) end
    -- Equipment-slot entries have no usable query or tint state to refresh.
    -- Explicit item entries still use IsUsableItem, even with an equip slot.
    if spell and view and view.usable
        and (e.src=="i" or not (e.equipSlot or e.src=="e")) then
        Push(Index.usable,e)
    end
    if spell and view and K.Pick(ov,view,"procGlow") then Push(Index.proc,e) end
    -- Ready glows flip on combat edges only where one is wanted.
    if view and K.Pick(ov,view,"readyGlow") then Push(Index.ready,e) end
    -- Item, equipment-slot (custom entries, or Blizzard's trinkets on whichever
    -- bar holds them, Essential by default) and potion-category entries follow
    -- bag contents; only real items follow item cooldowns
    -- (categories arrive through SPELL_UPDATE_COOLDOWN's category payload).
    if item or category then Push(Index.items,e) end
    if item then Push(Index.bags,e) end
    if e.hasAura and e.auraIDs and view and K.Pick(ov,view,"showAura") then Push(Index.overlay,e) end
    if spell and view and view.assist then Push(Index.assist,e) end
end

function Index.Rebuild()
    for i=1,#MAPS do Release(Index[MAPS[i]]) end
    for i=1,#ARRAYS do
        local list=Index[ARRAYS[i]]
        for j=#list,1,-1 do list[j]=nil end
    end
    for e in pairs(seen) do seen[e]=nil end
    C.wipe(Index.countedSet)
    local plans,views=C.plans,C.views
    local byBase=Index.byBase
    for i=1,#SLOTS do
        local slot=SLOTS[i].key
        local plan=plans[slot]
        if plan then
            local view,entries=views[slot],plan.entries
            local cooldownBar=plan.kind==1
            for j=1,#entries do
                local e=entries[j]
                -- Placeholders never read live state.
                if e.src~="p" then
                    -- Override updates find their entries by base spell.
                    Add(byBase,e.base,e)
                    if cooldownBar then
                        if e.family==1 then AddCooldown(e,view) end
                    elseif e.family==2 then
                        Push(Index.aura,e)
                    end
                end
            end
        end
    end
end

-- An override that arrived in combat routes its new ID without a rebuild.
-- Cooldown entries only; the next rebuild drops IDs that are gone.
function Index.AddSpell(e,id)
    if id==nil or e.family~=1 then return end
    local list=Index.bySpell[id]
    if list then
        for i=1,#list do if list[i]==e then return end end
    end
    Add(Index.bySpell,id,e)
end

------------------------------------------------------------------ lookups
local function Each(list,fn)
    if not list then return 0 end
    local n=#list
    for i=1,n do fn(list[i]) end
    return n
end

-- SPELL_UPDATE_COOLDOWN / USES / RANGE / GLOW payloads: spellID (base or
-- override) and optional baseSpellID. Each matching entry is called once.
function Index.ForSpell(spellID,baseSpellID,fn)
    local bySpell=Index.bySpell
    local a,b
    if not (issecret and issecret(spellID)) and spellID then a=bySpell[spellID] end
    if not (issecret and issecret(baseSpellID)) and baseSpellID then b=bySpell[baseSpellID] end
    if a==b then b=nil end
    if not a then a,b=b,nil end
    if not a then return 0 end
    if not b then return Each(a,fn) end
    local n=#a
    for i=1,n do local e=a[i]; seen[e]=true; fn(e) end
    for i=1,#b do
        local e=b[i]
        if not seen[e] then n=n+1; fn(e) end
    end
    for i=1,#a do seen[a[i]]=nil end
    return n
end
function Index.ForBase(base,fn)
    if (issecret and issecret(base)) or not base then return 0 end
    return Each(Index.byBase[base],fn)
end
function Index.ForCategory(category,fn)
    if (issecret and issecret(category)) or not category then return 0 end
    return Each(Index.byCategory[category],fn)
end
function Index.ForItem(itemID,fn)
    if (issecret and issecret(itemID)) or not itemID then return 0 end
    return Each(Index.byItem[itemID],fn)
end
