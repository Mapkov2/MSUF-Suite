local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Time sources for cooldown icons. Secret timing only reaches C sinks: the
-- swipe through duration objects, desaturation and opacity through step
-- curves evaluated C-side, counts through SetText. Lua branches only on
-- NeverSecret fields (isActive, isOnGCD, maxCharges, charge isActive),
-- HasSecretValues, or values that passed S.Public. Nothing here allocates:
-- the only new objects per event are the duration objects the C API returns.
local K=C.Const
local T={}
C.Time=T
local Public=S.Public
local EMPTY=C.EMPTY
local wipe=C.wipe
local Spell=_G.C_Spell or {}
local GetCooldown=Spell.GetSpellCooldown
local GetDuration=Spell.GetSpellCooldownDuration
local GetCharges=Spell.GetSpellCharges
local GetChargeDuration=Spell.GetSpellChargeDuration
local GetDisplayCount=Spell.GetSpellDisplayCount
local Item=_G.C_Item or {}
local Container=_G.C_Container or {}
local GetItemCooldown=Item.GetItemCooldown or Container.GetItemCooldown
local GetItemCount=Item.GetItemCount
local GetInventoryItemCooldown=_G.GetInventoryItemCooldown
local DurationUtil=_G.C_DurationUtil
local CreateDuration=DurationUtil and DurationUtil.CreateDuration
local GetTime=_G.GetTime
-- Ready alerts need a real cooldown of at least this long; items treat
-- anything up to a global cooldown as no cooldown.
local READY_MIN,GCD_MAX=2,1.5

------------------------------------------------------------------ curves
-- Resolved on bind and on behavior/choice changes only, never per event.
local function Curves(icon,entry,view)
    local ov=entry.ov or EMPTY
    icon.curveEntry,icon.curveOv,icon.curveGen=entry,ov,view.behaviorGen
    local desat=ov.desat or 1
    local on
    if desat==2 then on=false elseif desat==3 then on=true else on=view.desat==true end
    icon.desatCurve=on and K.DesatCurve() or nil
    local ready=ov.readyAlpha or view.readyAlpha or 100
    local cooling=ov.cdAlpha or view.cdAlpha or 100
    icon.readyAlpha,icon.coolAlpha=ready/100,cooling/100
    icon.alphaCurve=(ready~=100 or cooling~=100) and K.StepCurve(ready,cooling) or nil
    local hide=ov.hideReady
    if hide==nil then hide=view.hideReady==true end
    icon.hideReady=hide
    -- The item memo holds curve results: new curves repaint on the next refresh.
    icon.itemStart=nil
end

-- Desaturation and opacity. With a duration the curves run C-side (the
-- result may be secret and goes straight into the sink); without one the
-- icon shows its ready look through memoized plain writes.
local function Feedback(icon,duration)
    local desat,alpha=icon.desatCurve,icon.alphaCurve
    local tex=icon.tex
    if desat and duration then
        tex:SetDesaturation(duration:EvaluateRemainingDuration(desat))
        icon.fbDesat=nil
    elseif icon.fbDesat~=0 then
        icon.fbDesat=0
        tex:SetDesaturation(0)
    end
    if alpha and duration then
        icon:SetAlpha(duration:EvaluateRemainingDuration(alpha))
        icon.fbAlpha=nil
    else
        local value=alpha and icon.readyAlpha or 1
        if icon.fbAlpha~=value then icon.fbAlpha=value;icon:SetAlpha(value) end
    end
end
-- The look of an item cooldown on hold: desaturated at the cooling opacity,
-- through the same plain memos.
local function Held(icon)
    if icon.fbDesat~=1 then icon.fbDesat=1;icon.tex:SetDesaturation(1) end
    local value=icon.alphaCurve and icon.coolAlpha or 1
    if icon.fbAlpha~=value then icon.fbAlpha=value;icon:SetAlpha(value) end
end

-- cdReal marks a main swipe whose end is the end of the real cooldown (a
-- GCD-free spell duration or an item cooldown); Done reads it.
local function ClearMain(icon)
    icon.cdReal=nil
    if icon.cdSet~=false then icon.cdSet=false;icon.cd:Clear() end
end
local function ClearCharge(icon)
    local cooldown=icon.chargeCd
    if cooldown and icon.chargeSet~=false then icon.chargeSet=false;cooldown:Clear() end
end
local function CountOff(icon)
    if icon.countOff~=true then icon.countOff=true;icon.count:SetText("") end
end
local function ShowCount(icon,count)
    if icon.countOff~=false or icon.lastCount~=count then
        icon.countOff,icon.lastCount=false,count
        icon.count:SetText(count)
    end
end

------------------------------------------------------------------ spells
-- Is an active spell cooldown a real one (not only the GCD)? isOnGCD is
-- trusted inside SPELL_UPDATE_COOLDOWN handling; otherwise a plain
-- GCD-free duration answers exactly, else the last known state holds.
-- The second result is true when the answer is exact.
local function Real(info,duration,reason,previous)
    if reason=="cooldown" then
        local gcd=info.isOnGCD
        return not (Public(gcd) and gcd),true
    end
    if duration and not duration:HasSecretValues() then
        local active=duration:IsActive()
        if Public(active) then return active==true,true end
    end
    if previous~=nil then return previous,false end
    local gcd=info.isOnGCD
    return not (Public(gcd) and gcd),false
end

-- Returns the entry's cooling state. reason "expired": the main swipe held
-- the GCD-free duration and just ran out, so the real cooldown is over and
-- any isActive now is the GCD; nothing is queried for the main cooldown (a
-- new cooldown re-arms through SPELL_UPDATE_COOLDOWN). reason "recharge"
-- (SPELL_UPDATE_CHARGES, no payload): while the main swipe is clear a
-- charge is available, so only the recharge swipe and the count are read
-- and the main state holds; a main swipe that shows (no charge left, or the
-- GCD) is read in full.
local function SpellState(entry,icon,spell,reason)
    local cooling,exact=false,true
    if reason=="recharge" and icon.cdSet==true then reason="charges" end
    if reason=="expired" then
        ClearMain(icon)
        Feedback(icon,nil)
    elseif reason=="recharge" then
        cooling,exact=entry.cooling==true,false
    else
        local info=GetCooldown and GetCooldown(spell)
        local active=info and info.isActive
        if Public(active) and active then
            local ignoreGCD=C.state.showGCD~=true
            local duration=GetDuration and GetDuration(spell,ignoreGCD)
            if duration then
                icon.cd:SetCooldownFromDurationObject(duration,true)
                icon.cdSet,icon.cdReal=true,ignoreGCD
            else ClearMain(icon) end
            -- Desaturation, opacity and the ready check ignore the GCD.
            local base=duration
            if not ignoreGCD and GetDuration and (icon.desatCurve or icon.alphaCurve or reason~="cooldown") then
                base=GetDuration(spell,true)
            end
            Feedback(icon,base)
            cooling,exact=Real(info,base,reason,entry.cooling)
        else
            ClearMain(icon)
            Feedback(icon,nil)
        end
    end
    local charges=entry.charges~=false and GetCharges and GetCharges(spell)
    local maximum=charges and charges.maxCharges
    if Public(maximum) and type(maximum)=="number" and maximum>1 then
        local state=charges.isActive
        local recharging=Public(state) and state==true
        if recharging and GetChargeDuration then
            local duration=GetChargeDuration(spell)
            if duration then
                local cooldown=icon.chargeCd or C.Icons.ChargeCooldown(icon)
                cooldown:SetCooldownFromDurationObject(duration,true)
                icon.chargeSet=true
            else ClearCharge(icon) end
        else
            ClearCharge(icon)
        end
        -- A charge spell stays cooling until every charge is back. When the
        -- main answer was only the last known state (a GCD hides it), a plain
        -- "not recharging" settles it: every charge is back.
        if recharging then
            if not cooling and entry.cooling then cooling=true end
        elseif not exact and Public(state) and state==false then
            cooling=false
        end
    else
        ClearCharge(icon)
    end
    -- Potion and healthstone entries show their bag count (CategoryCount).
    local category=entry.spellCategory
    if category and category~=0 then return cooling end
    if icon.stackOn and GetDisplayCount then
        icon.count:SetText(GetDisplayCount(spell))
        icon.countOff,icon.lastCount=false,nil
    else
        CountOff(icon)
    end
    return cooling
end

------------------------------------------------------------------ bag counts
-- Bag counts change only with the bag contents: they are read once per
-- BagsChanged (BAG_UPDATE_DELAYED, a fresh icon, a release), then served
-- from these caches. Potion and healthstone entries (Blizzard spellCategory)
-- sum every quality rank behind the category (Presets.CATEGORY_ITEMS).
local totals,counts,countsStale={}, {}, true
function T.BagsChanged() countsStale=true end
local function Fresh()
    if countsStale then countsStale=false;wipe(totals);wipe(counts) end
end
local function Total(category)
    Fresh()
    local total=totals[category]
    if total then return total end
    total=0
    local presets=C.Presets
    local items=GetItemCount and presets and presets.CATEGORY_ITEMS[category]
    if items then
        for i=1,#items do
            local count=GetItemCount(items[i],false,true)
            if Public(count) and type(count)=="number" and count>0 then total=total+count end
        end
    end
    totals[category]=total
    return total
end
-- false when unreadable (never documented as secret, but guarded).
local function ItemCount(item)
    Fresh()
    local count=counts[item]
    if count==nil then
        count=GetItemCount and GetItemCount(item,false,true)
        if not (Public(count) and type(count)=="number") then count=false end
        counts[item]=count
    end
    return count
end
-- Returns true when the bags hold none; a hideEmpty entry reads its total
-- even while counts are off.
local function CategoryCount(icon,category,entry)
    local total=(icon.stackOn or entry.hideEmpty) and Total(category) or 0
    if total>0 and icon.stackOn then
        ShowCount(icon,total)
    else
        icon.lastCount=nil
        CountOff(icon)
    end
    return total==0
end

------------------------------------------------------------------ items
-- Item and equipment cooldowns have no duration API: plain numbers feed a
-- per-icon duration object that is reused, never recreated. The applied
-- start and length are memoized, so a repeated BAG_UPDATE_COOLDOWN with the
-- same cooldown writes nothing; the swipe's own OnCooldownDone ("expired")
-- or the plain end time retires it. Secret values clear the icon.
-- A cooldown on hold (enable 0 or false: Blizzard starts it when combat
-- ends, e.g. a Healthstone used in combat) shows no swipe, looks held and
-- counts as cooling, so no ready alert fires; the BAG_UPDATE_COOLDOWN that
-- starts it arms the swipe as a new cooldown. Returns the cooling state and
-- whether the bags hold none of the item.
local function ItemState(entry,icon,reason)
    local slot=entry.equipSlot or (entry.src=="e" and entry.id) or nil
    local item=entry.itemID or entry.id
    local start,length,enable
    if slot then
        if GetInventoryItemCooldown then start,length,enable=GetInventoryItemCooldown("player",slot) end
    elseif GetItemCooldown then
        start,length,enable=GetItemCooldown(item)
    end
    local cooling=false
    local plain=Public(start) and Public(length) and Public(enable) and type(start)=="number" and type(length)=="number"
    if plain and length>0 and (enable==false or enable==0) then
        if not icon.itemLock then
            -- The item was used: its own count is read again.
            icon.itemLock,icon.itemStart=true,nil
            if not slot then counts[item]=nil end
        end
        ClearMain(icon)
        Held(icon)
        cooling=true
    elseif plain and start>0 and length>0 then
        icon.itemLock=nil
        local gcd=C.state.showGCD==true
        if icon.itemStart==start and icon.itemLen==length and icon.itemGCD==gcd then
            if not icon.itemOver and (reason=="expired" or start+length<=GetTime()) then
                icon.itemOver=true
                ClearMain(icon)
                Feedback(icon,nil)
            end
            cooling=not icon.itemOver and length>GCD_MAX
        else
            -- A new cooldown means the item was used: its own count is read again.
            if not slot then counts[item]=nil end
            local over=start+length<=GetTime()
            icon.itemStart,icon.itemLen,icon.itemGCD,icon.itemOver=start,length,gcd,over
            cooling=not over and length>GCD_MAX
            local shown=false
            if not over and (cooling or gcd) then
                local duration=icon.itemDur
                if not duration and CreateDuration then duration=CreateDuration();icon.itemDur=duration end
                if duration then
                    duration:SetTimeFromStart(start,length)
                    icon.cd:SetCooldownFromDurationObject(duration,true)
                    icon.cdSet,icon.cdReal=true,true
                    shown=true
                    Feedback(icon,cooling and duration or nil)
                end
            end
            if not shown then ClearMain(icon);Feedback(icon,nil) end
        end
    else
        icon.itemStart,icon.itemLock=nil,nil
        ClearMain(icon)
        Feedback(icon,nil)
    end
    ClearCharge(icon)
    -- An empty healthstone (hideEmpty) shows no "0", not even in a preview.
    local count=not slot and (icon.stackOn or entry.hideEmpty) and ItemCount(item)
    if count and count~=1 and icon.stackOn and not (count==0 and entry.hideEmpty) then
        ShowCount(icon,count)
    else
        icon.lastCount=nil
        CountOff(icon)
    end
    return cooling,count==0
end

------------------------------------------------------------------ edges
local function Request(slotKey)
    local layout=C.Layout
    if layout and layout.Request then layout.Request(slotKey) end
end

-- Cooling edges drive ready alerts and ready glows; the start time is
-- plain GetTime at the edge, never a cooldown value.
local function Edge(entry,cooling)
    local was=entry.cooling
    entry.cooling=cooling
    if cooling then
        if not was then entry.coolStart=GetTime() end
    elseif was then
        local start=entry.coolStart
        entry.coolStart=nil
        if start and GetTime()-start>=READY_MIN then
            local alerts=C.Alerts
            if alerts and alerts.Ready then alerts.Ready(entry) end
        end
    end
    if was~=cooling then
        local fx=C.Effects
        if fx and fx.Update then fx.Update(entry) end
    end
end

-- reason: "cooldown" (SPELL_UPDATE_COOLDOWN, isOnGCD trustworthy),
-- "count" (SPELL_UPDATE_USES: the count only, see below), "recharge"
-- (SPELL_UPDATE_CHARGES: the charge part only, see SpellState), "charges"
-- (state and count), "item" (bag events), "done", "expired" (the main swipe
-- ran out, from Done), "full". Returns true when entry.hidden changed.
function T.Refresh(entry,reason)
    local icon=entry.icon
    if not icon or icon.sim or entry.src=="p" then return false end
    local view=C.views[entry.slot]
    if not view then return false end
    if reason=="count" then
        -- A use count moved: the count alone, as Blizzard's viewer does;
        -- swipes and state hold. Routed to spell entries that show counts.
        local spell=entry.spell
        if icon.stackOn and spell and GetDisplayCount then
            icon.count:SetText(GetDisplayCount(spell))
            icon.countOff,icon.lastCount=false,nil
        end
        return false
    end
    if icon.curveEntry~=entry or icon.curveOv~=entry.ov or icon.curveGen~=view.behaviorGen then Curves(icon,entry,view) end
    if reason=="full" then C.Icons.Apply(entry) end
    local cooling,empty
    if entry.equipSlot or entry.src=="i" or entry.src=="e" then
        cooling,empty=ItemState(entry,icon,reason)
    else
        -- Category entries (potions, healthstones) follow the spell that last
        -- started the category; the controller keeps entry.catSpell current.
        -- Bag events only move their count: the category's cooldown arrives
        -- with SPELL_UPDATE_COOLDOWN.
        local spell,category=entry.spell,entry.spellCategory
        if category==0 then category=nil end
        if category then spell=entry.catSpell end
        if category and reason=="item" then
            cooling=entry.cooling==true
        elseif spell then
            cooling=SpellState(entry,icon,spell,reason)
        else
            ClearMain(icon);ClearCharge(icon);Feedback(icon,nil)
            if not category then CountOff(icon) end
            cooling=false
        end
        if category then empty=CategoryCount(icon,category,entry) end
    end
    -- Healthstones (hideEmpty) leave their bar while the bags hold none;
    -- entry.empty keeps that answer for the options page.
    empty=entry.hideEmpty==true and empty==true
    entry.empty=empty
    local hidden=(not C.state.preview and ((icon.hideReady and not cooling) or empty)) and true or false
    local changed=(entry.hidden==true)~=hidden
    entry.hidden=hidden
    local was=entry.cooling
    Edge(entry,cooling)
    -- A flip without a cooling edge (a Healthstone leaving or joining the
    -- bags) re-evaluates the glows as well; Edge covers the others.
    if changed and was==cooling then
        local fx=C.Effects
        if fx and fx.Update then fx.Update(entry) end
    end
    return changed
end

-- OnCooldownDone of an icon's swipe (cooldown = icon.cd) or recharge edge
-- (icon.chargeCd): re-evaluate only that entry; a hideReady flip relayouts
-- its bar. A main swipe that held the real cooldown means "expired".
function T.Done(icon,cooldown)
    local entry=icon.entry
    if not entry or entry.icon~=icon or icon.inDone then return end
    if icon.sim or entry.src=="p" then Feedback(icon,nil);return end
    local reason="done"
    if cooldown~=nil and cooldown==icon.cd and icon.cdReal then reason="expired" end
    -- Guard: a swipe re-armed during the refresh must not re-enter.
    icon.inDone=true
    local changed=T.Refresh(entry,reason)
    icon.inDone=nil
    if changed then Request(entry.slot) end
end

-- Preview: a synthetic duration owns the icon until cleared; placeholders
-- never read live state.
function T.Simulate(entry,duration)
    local icon=entry.icon
    if not icon then return end
    local view=C.views[entry.slot]
    if view and (icon.curveEntry~=entry or icon.curveOv~=entry.ov or icon.curveGen~=view.behaviorGen) then Curves(icon,entry,view) end
    -- The live swipe is replaced either way: the item memo starts over.
    icon.itemStart,icon.itemLock=nil,nil
    if duration then
        icon.sim=duration
        icon.cd:SetCooldownFromDurationObject(duration,true)
        icon.cdSet,icon.cdReal=true,nil
        Feedback(icon,duration)
        return
    end
    icon.sim=nil
    ClearMain(icon)
    Feedback(icon,nil)
    if entry.src~="p" then T.Refresh(entry,"full") end
end
