local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Spell -> short key text for icons on bars that show keybinds. Texts are
-- cached per spell (items per item ID); icons get theirs through
-- Icons.SetKeybind. Binding and action slot events drop the cache, bar
-- content changes only push cached texts (new spells are looked up once);
-- both arrive coalesced 0.2 s after the last request. Nothing here runs per
-- cooldown event.
local KB={map={}}
C.Keybinds=KB
local Public=S.Public
local type,pairs=type,pairs
local wipe=table.wipe or wipe or function(t) for k in pairs(t) do t[k]=nil end return t end
local DELAY=0.2

-- Action slot ranges and the binding command each range presses (in the
-- order a key is preferred). Bonus bar pages (forms, stances) press the main
-- bar keys and only count when no other slot has a key.
local RANGES={{1,12,"ACTIONBUTTON"},{61,72,"MULTIACTIONBAR1BUTTON"},{49,60,"MULTIACTIONBAR2BUTTON"},
    {25,36,"MULTIACTIONBAR3BUTTON"},{37,48,"MULTIACTIONBAR4BUTTON"},{145,156,"MULTIACTIONBAR5BUTTON"},
    {157,168,"MULTIACTIONBAR6BUTTON"},{169,180,"MULTIACTIONBAR7BUTTON"}}
local COMMAND,RANK={},{}
for rank=1,#RANGES do
    local range=RANGES[rank]
    for slot=range[1],range[2] do COMMAND[slot],RANK[slot]=range[3]..(slot-range[1]+1),rank end
end
for slot=73,120 do COMMAND[slot],RANK[slot]="ACTIONBUTTON"..((slot-73)%12+1),#RANGES+1 end
-- The same slots in key preference order (bonus bar pages last).
local ORDERED={}
for rank=1,#RANGES do
    local range=RANGES[rank]
    for slot=range[1],range[2] do ORDERED[#ORDERED+1]=slot end
end
for slot=73,120 do ORDERED[#ORDERED+1]=slot end

-- SHIFT-/CTRL-/ALT- become S/C/A, NUMPAD N, mouse BUTTON M, the wheel MWU/MWD.
local SHORT={{"SHIFT%-","S"},{"CTRL%-","C"},{"ALT%-","A"},{"MOUSEWHEELUP","MWU"},{"MOUSEWHEELDOWN","MWD"},
    {"NUMPAD","N"},{"BUTTON","M"}}
local shortCache={}
local function Short(key)
    local text=shortCache[key]
    if text then return text end
    text=key
    for i=1,#SHORT do text=text:gsub(SHORT[i][1],SHORT[i][2]) end
    shortCache[key]=text
    return text
end
KB.Short=Short

local function BoundKey(command)
    if type(GetBindingKey)~="function" then return nil end
    local key=GetBindingKey(command)
    if Public(key) and type(key)=="string" and key~="" then return key end
end

-- First key found, by range preference; "" when the spell has no key.
local function Lookup(spell)
    local export=S.ActionBarsBindingForSpell
    if type(export)=="function" then
        local text=export(spell)
        if Public(text) and type(text)=="string" and text~="" then return text end
    end
    local bar=_G.C_ActionBar
    local find=bar and bar.FindSpellActionButtons
    local slots=find and find(spell)
    if not (Public(slots) and type(slots)=="table") then return "" end
    local best,bestRank
    for i=1,#slots do
        local slot=slots[i]
        local rank=Public(slot) and RANK[slot]
        if rank and (not bestRank or rank<bestRank) then
            local key=BoundKey(COMMAND[slot])
            if key then best,bestRank=key,rank end
        end
    end
    return best and Short(best) or ""
end

function KB.Text(spell)
    if not spell then return "" end
    local text=KB.map[spell]
    if text==nil then
        text=Lookup(spell)
        KB.map[spell]=text
    end
    return text
end

-- Trinkets and other items sit on the bars as item actions, which
-- FindSpellActionButtons never matches (there is no item counterpart): one
-- scan of the ranged action slots per item, in the same key preference,
-- cached like spells.
local itemMap={}
local function ItemLookup(item)
    local info=_G.GetActionInfo
    if type(info)~="function" then return "" end
    for i=1,#ORDERED do
        local slot=ORDERED[i]
        local kind,id=info(slot)
        if Public(kind) and kind=="item" and Public(id) and id==item then
            local key=BoundKey(COMMAND[slot])
            if key then return Short(key) end
        end
    end
    return ""
end
-- An item entry (Blizzard's trinket records, the equipment-slot rows and
-- custom items) takes the key of its item action, else its use spell's.
function KB.EntryText(e)
    local item=e.itemID
    if item and (e.equipSlot or e.src=="e" or e.src=="i") then
        local text=itemMap[item]
        if text==nil then
            text=ItemLookup(item)
            itemMap[item]=text
        end
        if text~="" then return text end
    end
    -- Action slots hold the base spell of an override.
    return KB.Text(e.base or e.spell)
end

-- Cold: pushes key text to every entry of a cooldown bar that shows
-- keybinds, from the cache where it has the spell.
function KB.Refresh()
    for slot,plan in pairs(C.plans) do
        local view=C.views[slot]
        if plan.kind==1 and view and view.keybind then
            local entries=plan.entries
            for i=1,#entries do
                local e=entries[i]
                if e.src~="p" then
                    local text=KB.EntryText(e)
                    if e.keyText~=text then C.Icons.SetKeybind(e,text) end
                end
            end
        end
    end
end
-- Bindings or action slots changed: every text is looked up again.
function KB.Rebuild()
    wipe(KB.map)
    wipe(itemMap)
    KB.Refresh()
end

-- One pass 0.2 s after the last request of a burst; stale (binding and
-- action slot events) drops the cache first.
local armed,stale=false,false
local function Fire()
    armed=false
    local fresh=stale
    stale=false
    if not C.M.active then return end
    if fresh then KB.Rebuild() else KB.Refresh() end
end
function KB.Request(bindings)
    if bindings then stale=true end
    if armed then return end
    local timer=_G.C_Timer
    if not (timer and timer.After) then return Fire() end
    armed=true
    timer.After(DELAY,Fire)
end

function KB.Clear()
    wipe(KB.map)
    wipe(itemMap)
    stale=false
end
