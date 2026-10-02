local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- The event map, specialization detection, the assisted-combat source and
-- the combat edges. Events register only while something consumes them.
-- Cooldown events refresh their entries at once, inside the event, because
-- isOnGCD is only trustworthy there; the other hot events mark entries and
-- share the flush (Flush.lua). Hot handlers guard payloads with the client's
-- issecretvalue directly.
local M = C.M
local SLOTS = NS.CDM.SLOTS
local Public = S.Public
local issecret = _G.issecretvalue
local EMPTY = C.EMPTY
local pairs, type, next = pairs, type, next
local K = C.Const
local GCD, GCD_SPELL = K.GCD_CATEGORY, K.GCD_SPELL
local TRINKET1, TRINKET2 = K.TRINKET1, K.TRINKET2
local KIND, AURA_KINDS = K.KIND, K.AURA_KINDS
local QUIET = 2   -- seconds without sounds after loading screens and activation
local Flush, Settings = C.Flush, C.Settings
local dirty, sync, style = Flush.dirty, Flush.sync, Flush.style
local Mark, Schedule = Flush.Mark, Flush.Schedule
local CaptureWhenReady, CaptureAfterCombat = Settings.CaptureWhenReady, Settings.CaptureAfterCombat
local Events = {}
C.Events = Events
-- Every layer the hot handlers call loads before this file, so its
-- functions are resolved once here: an event costs no module lookup.
-- Index.Rebuild wipes the routing arrays in place, never replaces them.
local Index, Effects = C.Index, C.Effects
local Refresh, BagsChanged, Request = C.Time.Refresh, C.Time.BagsChanged, C.Layout.Request
local ForSpell, ForBase, ForCategory, ForItem, AddSpell =
    Index.ForSpell, Index.ForBase, Index.ForCategory, Index.ForItem, Index.AddSpell
local Proc, Range, ReadRange, Assist = Effects.Proc, Effects.Range, Effects.ReadRange, Effects.Assist
local UsableShown = Effects.UsableShown
local cooldownEntries, chargedEntries, usableEntries = Index.cooldown, Index.charged, Index.usable
local bagEntries, itemEntries, rangedEntries = Index.bags, Index.items, Index.ranged

-- staleRoutes: an override arrived in combat and was routed without a
-- rebuild; seedLater: category entries wait for combat to end.
local staleRoutes, seedLater = false, false
local events = {}
-- SPELL_UPDATE_USABLE has no spell payload. Bound its visible-icon sweep to
-- five times per second for ordinary tinting, ten for resource-ready glows.
-- The cold index selects the interval. A trailing refresh keeps the final
-- state; range, target and show edges still paint immediately.
local USABLE_INTERVAL = .2
local usableNext, usableArmed = 0, false

-- Loading screens and activation: combat state is read fresh and sounds
-- stay quiet for a moment.
local function EnterWorld()
    local state = C.state
    state.inCombat = NS.IsCombatLocked()
    state.soundQuietUntil = GetTime() + QUIET
end
Events.EnterWorld = EnterWorld

------------------------------------------------------------------ spec
local specName, specIcon
local function UpdateSpec()
    local id, name, icon
    local index = C_SpecializationInfo.GetSpecialization()
    if Public(index) and type(index) == "number" and index > 0 then
        local sid, sname, _, sicon = C_SpecializationInfo.GetSpecializationInfo(index)
        if Public(sid) and type(sid) == "number" and sid > 0 then
            id = sid
            name = Public(sname) and type(sname) == "string" and sname or nil
            icon = Public(sicon) and sicon or nil
        end
    end
    specName, specIcon = name, icon
    local state, tag = C.state, C.Catalog.SpecTag()
    if state.specID == id and state.specTag == tag then return false end
    state.specID, state.specTag = id, tag
    return true
end
Events.UpdateSpec = UpdateSpec

-- The options page asks several times per repaint: the client is read at
-- most once per frame (catalog events keep the state current while the
-- module runs).
local specFrame
function S.CooldownManagerSpec()
    local now = GetTime()
    if specFrame ~= now then
        specFrame = now
        if UpdateSpec() and M.active then
            dirty.catalog, dirty.resolve = true, true
            Schedule()
        end
    end
    return C.state.specID, specName, specIcon
end

------------------------------------------------------------------ hot event handlers
-- Prebuilt callbacks; per-event values travel through these upvalues.
local stamp, curSpell, curItem, curRange = 0, nil, nil, nil
local function RefreshCooldown(entry)
    if entry.cdStamp == stamp or not entry.icon then return end
    entry.cdStamp = stamp
    if Refresh(entry, "cooldown") then Request(entry.slot) end
end
local function EachCooldown(fn)
    for i = 1, #cooldownEntries do fn(cooldownEntries[i]) end
end
local function SetCategorySpell(entry) entry.catSpell, entry.catItem = curSpell, curItem end

-- SPELL_UPDATE_COOLDOWN: nil or unreadable spell = all; category payloads
-- (potions, healthstones) name the spell that started the category; a GCD
-- start touches every icon only while icons show the GCD. A payload value
-- that is secret counts as absent.
local function OnCooldown(_, _, spellID, baseSpellID, category, recovery, itemID)
    stamp = stamp + 1
    if C.state.assistIcon and (issecret(spellID) or spellID == nil or spellID == GCD_SPELL
        or not issecret(recovery) and recovery == GCD) then Effects.RecommendationGCD() end
    local item = not issecret(itemID) and itemID or nil
    local categoryItem = item and not issecret(category) and category and category ~= 0
    if categoryItem then
        curSpell = not issecret(baseSpellID) and baseSpellID or (not issecret(spellID) and spellID or nil)
        curItem = item
        ForCategory(category, SetCategorySpell)
    end
    if issecret(spellID) or spellID == nil then return EachCooldown(RefreshCooldown) end
    if categoryItem then ForCategory(category, RefreshCooldown) end
    if not issecret(recovery) and recovery == GCD then
        local list = Index.gcd
        for i = 1, #list do RefreshCooldown(list[i]) end
    end
    ForSpell(spellID, baseSpellID, RefreshCooldown)
    if item then ForItem(item, RefreshCooldown) end
end

local countedSet = Index.countedSet
local function MarkCount(entry)
    if countedSet[entry] then
        Mark(entry, "count")
    end
end
local function MarkItem(entry) Mark(entry, "item") end
-- SPELL_UPDATE_CHARGES names no spell. Spending a charge arrives with the
-- spell's SPELL_UPDATE_COOLDOWN and a charge coming back with the recharge
-- swipe's OnCooldownDone (Blizzard's viewer never registers this event), so
-- only entries whose recharge swipe runs refresh it and their count (Time
-- "recharge"); entries with every charge cost one read each.
local function OnCharges()
    for i = 1, #chargedEntries do
        local entry = chargedEntries[i]
        local icon = entry.icon
        if icon and icon.chargeSet then Mark(entry, "recharge") end
    end
end
-- SPELL_UPDATE_USES: the count alone (Time "count"), for entries that show
-- counts; the cooldown stays with SPELL_UPDATE_COOLDOWN.
local function OnUses(_, _, spellID, baseSpellID) ForSpell(spellID, baseSpellID, MarkCount) end
-- Item cooldowns: items and equipment slots only. Potion and healthstone
-- entries follow their category payload in SPELL_UPDATE_COOLDOWN.
local function OnBag()
    for i = 1, #bagEntries do MarkItem(bagEntries[i]) end
end
-- Bag contents changed: potion counts are recounted once, then every item
-- and category entry refreshes.
local function OnBagContents()
    BagsChanged()
    for i = 1, #itemEntries do MarkItem(itemEntries[i]) end
end
-- Visibility keeps transparent bars in the plan. Only visible icons need
-- a usability read; Visibility.Paint catches up on the show edge. The
-- trailing refresh of a throttle window is one shared callback behind an
-- armed flag (no timer object per window); a disable does not cancel it,
-- the callback finds the module inactive.
local function UsableWindowDone()
    usableArmed = false
    if not M.active then return end
    usableNext = GetTime() + (Index.usableInterval or USABLE_INTERVAL)
    dirty.usable = true
    Schedule()
end
local function OnUsable()
    if dirty.usable or usableArmed then return end
    for i = 1, #usableEntries do
        if UsableShown(usableEntries[i]) then
            local now = GetTime()
            if now >= usableNext then
                usableNext = now + (Index.usableInterval or USABLE_INTERVAL)
                dirty.usable = true
                Schedule()
            else
                usableArmed = true
                C_Timer.After(usableNext - now, UsableWindowDone)
            end
            return
        end
    end
end

-- SPELL_UPDATE_ICON names the base spell (nil = all).
local function Retexture(entry)
    local catalog, tex = C.Catalog, nil
    if entry.src == "b" then
        local rec = catalog.records[entry.id]
        tex = rec and catalog.RecordTexture(rec)
    elseif entry.src == "s" then
        tex = catalog.SpellTexture(entry.base)
    end
    if tex and tex ~= entry.texture then
        entry.texture = tex
        C.state.entryGen = (C.state.entryGen or 0) + 1
        C.Icons.Texture(entry)
    end
end
local function OnIcon(_, _, spellID)
    if issecret(spellID) or spellID == nil then return EachCooldown(Retexture) end
    ForSpell(spellID, nil, Retexture)
end

local function ProcOn(entry) Proc(entry, true) end
local function ProcOff(entry) Proc(entry, false) end
local function OnGlowShow(_, _, spellID) ForSpell(spellID, nil, ProcOn) end
local function OnGlowHide(_, _, spellID) ForSpell(spellID, nil, ProcOff) end

-- Only the entry holding the check for this spell follows its update.
local function RangeEntry(entry)
    if entry.rangeSpell == curSpell then Range(entry, curRange) end
end
local function OnRange(_, _, spell, inRange, checksRange)
    if issecret(spell) or spell == nil then return end
    curSpell, curRange = spell, nil
    if not (issecret(checksRange) or issecret(inRange)) and checksRange then curRange = inRange end
    ForSpell(spell, nil, RangeEntry)
end

local function OnTarget()
    for i = 1, #rangedEntries do ReadRange(rangedEntries[i]) end
    C.Auras.TargetChanged()
end
-- The target's disposition can flip without a retarget (a duel, a charm):
-- target aura containers pause while it is friendly. Other units: one compare.
local function OnFaction(_, _, unit)
    if not issecret(unit) and unit == "target" then
        C.Auras.TargetReaction()
    end
end
-- A restriction ended (M+ key, PvP match, encounter): aura restyles that
-- sealed buttons held back run next frame, not at the next combat end.
-- Registered only while aura containers or overlays exist.
local RESTRICTION_OFF = Enum.AddOnRestrictionState.Inactive
local function OnRestriction(_, _, _, state)
    if Public(state) and state == RESTRICTION_OFF then
        if next(C.Auras.pending) or C.Alerts.pending then C_Timer.After(0, C.Auras.FlushPending) end
        if C.ActionGlows.pending then C_Timer.After(0, C.ActionGlows.Refresh) end
    end
end

-- The override changes spell, texture and routing of entries with that
-- base. Both lookups are by base spell: a base nothing tracks costs two
-- reads. The new ID is routed at once; the full index rebuild waits for
-- the end of combat.
local function Overridden(entry)
    if entry.src ~= "b" and entry.src ~= "s" then return end
    if entry.icon then Mark(entry, "full") end
    if entry.auraIDs and entry.slot then sync[entry.slot] = true end
    AddSpell(entry, entry.override)
end
local function OnOverride(_, _, base, override)
    if not C.Catalog.OnOverride(base, override) then return end
    if ForBase(base, Overridden) == 0 then return end
    if C.state.inCombat then
        staleRoutes = true
    else
        dirty.index = true
    end
    Schedule()
end

------------------------------------------------------------------ cold event handlers
local RESOLVING = { SPELLS_CHANGED = true, TRAIT_CONFIG_UPDATED = true, ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true }
local function OnCatalog(_, event)
    dirty.catalog = true
    -- Learned state of custom spells and per-spec lists follow these.
    if RESOLVING[event] then
        dirty.resolve = true
        C.Resolve.SpellsChanged()
    end
    Schedule()
end
-- Blizzard's layout callbacks carry no payload here and also fire for its
-- own in-memory merges: rebuild only when the saved layout string moved.
function Events.OnLayoutChanged()
    if C.Catalog.LayoutStale() then
        dirty.catalog = true
        Schedule()
    end
end
-- Trinket slots and slots an entry tracks; other gear changes cost a lookup.
local function OnEquipment(_, _, slot)
    if Public(slot) and slot ~= nil and slot ~= TRINKET1 and slot ~= TRINKET2 and not Index.byEquip[slot] then return end
    dirty.catalog, dirty.resolve = true, true
    Schedule()
end
local function OnBindings()
    C.Keybinds.Request(true)
    C.ActionGlows.RouteChanged()
end
Events.OnBindings = OnBindings
-- The suite action bars started, stopped or changed their form pages: the
-- key texts they answered are stale, and their glows may start or stop.
function Events.OnActionBars()
    C.Keybinds.Request(true)
    C.ActionGlows.RouteChanged(true)
end
local function OnActionPage()
    if C.state.keybindStable == false then C.Keybinds.Request(true) end
    C.ActionGlows.RouteChanged()
end
Events.OnActionPage = OnActionPage

local function AlertsWanted()
    local list = Index.aura
    for i = 1, #list do
        local ov = list[i].ov
        if ov and ov ~= EMPTY and ((ov.sound and ov.sound ~= "") or (ov.lossSound and ov.lossSound ~= "")) then return true end
    end
    return (C.Alerts.Registrations()) > 0
end

-- Loading screens: a short silence, then a rebuild that passes on what
-- changed; visibility sources re-read their state (a transition during the
-- loading screen may have had no event).
local function OnWorld()
    EnterWorld()
    if AlertsWanted() then C.Alerts.SyncAuraSounds() end
    C.Resolve.SpellsChanged()
    dirty.catalog, dirty.resolve, dirty.visibility = true, true, true
    Schedule()
end

-- The pixel grid moved: every look and position, aura container flow too.
local function OnScale()
    C.Layout.InvalidateScale()
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local view = C.views[slot]
        if view then
            view.styleGen, view.layoutGen = view.styleGen + 1, view.layoutGen + 1
            style[slot] = true
            if AURA_KINDS[view.kind] then sync[slot] = true end
        end
    end
    dirty.layout = true
    Schedule()
end

------------------------------------------------------------------ assisted combat
-- With Blizzard's highlight on, its own change callback feeds us; otherwise
-- a 0.2 s poll runs in combat only.
local assistMode, assistTicker
local function Suggested(spell)
    if Public(spell) and type(spell) == "number" then return spell end
end
local function OnHighlight()
    if assistMode ~= "callback" then return end
    Assist(Suggested(AssistedCombatManager.lastNextCastSpellID))
end
local function Poll()
    Assist(Suggested(C_AssistedCombat.GetNextCastSpell(true)))
end
local function StopPoll()
    if assistTicker then
        assistTicker:Cancel()
        assistTicker = nil
    end
end
local function StartPoll()
    if assistTicker or assistMode ~= "poll" or not C.state.inCombat then return end
    assistTicker = C_Timer.NewTicker(.2, Poll)
    Poll()
end
-- Blizzard's highlight callback source is AssistedCombatManager, a table
-- only Retail loads (Forever's Blizzard_ActionBar.toc lists its file for the
-- mainline game type): on Forever the poll is the only source.
local function HighlightOn()
    if NS.Client.isForever then return false end
    local value = C_CVar.GetCVar("assistedCombatHighlight")
    return Public(value) and value == "1"
end
local function UpdateAssist()
    local mode
    if #Index.assist > 0 or C.state.assistIcon and HighlightOn() then
        local available = C_AssistedCombat.IsAvailable()
        if Public(available) and available then mode = HighlightOn() and "callback" or "poll" end
    end
    if mode ~= assistMode then
        StopPoll()
        assistMode = mode
        if mode == "callback" then
            M.context:Callback("AssistedCombatManager.OnAssistedHighlightSpellChange", OnHighlight)
            OnHighlight()
        end
        if not mode then Assist(nil) end
    end
    StartPoll()
end
Events.OnAssistPolicyChanged = UpdateAssist

------------------------------------------------------------------ category seeds
-- Category entries retain the last item and spell that started their category.
-- The source is read out of combat only; seeded icons refresh.
local function SeedCategories()
    local get = C_Spell.GetLastCategoryCooldownSource
    for i = 1, #itemEntries do
        local entry = itemEntries[i]
        local category = entry.spellCategory
        if category and category ~= 0 and not entry.catItem then
            local spell, item = get(category)
            if Public(item) and type(item) == "number" and item > 0 then
                entry.catItem = item
                entry.catSpell = Public(spell) and type(spell) == "number" and spell > 0 and spell or nil
                if entry.icon then Mark(entry, "full") end
            end
        end
    end
end

------------------------------------------------------------------ combat edges
local function OnCombatStart()
    local state = C.state
    state.inCombat = true
    C.Preview.Simulate(false)
    C.Effects.CombatChanged(true)
    C.Visibility.CombatChanged()
    UpdateAssist()
end
-- Protected work parked during combat (aura structure, state drivers,
-- sounds, the first-run capture) runs here, and so do the routing rebuild
-- and category seeds combat held back.
local function OnCombatEnd()
    C.state.inCombat = false
    if C.Resolve.ResumeConditions() then
        dirty.resolve = true
        Schedule()
    end
    C.Effects.CombatChanged(true)
    C.Visibility.CombatChanged()
    C.Visibility.FlushPending()
    C.Auras.FlushPending()
    C.ActionGlows.Refresh()
    C.Layout.CombatEnded()
    if assistMode == "poll" then
        StopPoll()
        Assist(nil)
    end
    CaptureAfterCombat()
    if staleRoutes then
        staleRoutes = false
        dirty.index = true
        Schedule()
    end
    if seedLater then
        seedLater = false
        SeedCategories()
    end
end

------------------------------------------------------------------ event map
-- Context:Event's third argument: the handler also runs in combat.
local ALLOW_COMBAT = true
local function Want(event, on, handler)
    on = on and true or false
    if (events[event] == true) == on then return end
    events[event] = on or nil
    if on then
        M.context:Event(event, handler, ALLOW_COMBAT)
    else
        M.context:RemoveEvent(event)
    end
end
local function TargetWatch()
    local list = Index.aura
    for i = 1, #list do
        if list[i].unit ~= "player" then
            return true
        end
    end
    list = Index.overlay
    for i = 1, #list do
        if list[i].unit ~= "player" then
            return true
        end
    end
    return false
end
local function KeybindWatch()
    if C.state.assistIcon and C.state.assistIconKeybind then return true end
    for slot, plan in pairs(C.plans) do
        local view = C.views[slot]
        if plan.kind == KIND.COOLDOWN and view and view.keybind and #plan.entries > 0 then return true end
    end
    return false
end
-- Gear changes matter to every shown bar that holds an equipment slot
-- record, learned or not (the trinkets on Essential, trinket buffs, any bar
-- a Blizzard layout moved one to), and to custom item entries.
local function EquipWatch()
    local views = C.views
    for bar in pairs(C.Catalog.equipBars) do
        local view = views[bar]
        if view and view.on then return true end
    end
    return #itemEntries > 0
end
local function UpdateEvents()
    local cooldown = #cooldownEntries > 0
    Want("SPELL_UPDATE_COOLDOWN", cooldown or C.state.assistIcon and C.state.assistIconGCD, OnCooldown)
    Want("SPELL_UPDATE_USES", #Index.counted > 0, OnUses)
    Want("SPELL_UPDATE_ICON", cooldown, OnIcon)
    Want("SPELL_UPDATE_CHARGES", #Index.charged > 0, OnCharges)
    Want("BAG_UPDATE_COOLDOWN", #Index.bags > 0, OnBag)
    Want("BAG_UPDATE_DELAYED", #Index.items > 0, OnBagContents)
    Want("SPELL_UPDATE_USABLE", #Index.usable > 0, OnUsable)
    Want("SPELL_RANGE_CHECK_UPDATE", #Index.ranged > 0, OnRange)
    local proc = #Index.proc > 0
    Want("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", proc, OnGlowShow)
    Want("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", proc, OnGlowHide)
    Want("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", cooldown or #Index.aura > 0, OnOverride)
    local target = TargetWatch()
    Want("PLAYER_TARGET_CHANGED", #Index.ranged > 0 or target, OnTarget)
    Want("UNIT_FACTION", target, OnFaction)
    Want("ADDON_RESTRICTION_STATE_CHANGED", #Index.aura > 0 or #Index.overlay > 0 or C.ActionGlows.wanted, OnRestriction)
    Want("PLAYER_EQUIPMENT_CHANGED", EquipWatch(), OnEquipment)
    local keys = KeybindWatch()
    Want("UPDATE_BINDINGS", keys, OnBindings)
    Want("ACTIONBAR_SLOT_CHANGED", keys or C.ActionGlows.wanted, OnBindings)
    Want("ACTIONBAR_PAGE_CHANGED", keys and C.state.keybindStable == false or C.ActionGlows.wanted, OnActionPage)
    Want("UPDATE_SHAPESHIFT_FORM", keys and C.state.keybindStable == false or C.ActionGlows.wanted, OnActionPage)
end
-- Catalog, combat, scale and loading-screen events while the module runs.
local CATALOG_EVENTS = { "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED" }
function Events.CoreEvents()
    for i = 1, #CATALOG_EVENTS do Want(CATALOG_EVENTS[i], true, OnCatalog) end
    Want("PLAYER_ENTERING_WORLD", true, OnWorld)
    Want("PLAYER_REGEN_DISABLED", true, OnCombatStart)
    Want("PLAYER_REGEN_ENABLED", true, OnCombatEnd)
    Want("UI_SCALE_CHANGED", true, OnScale)
    Want("DISPLAY_SIZE_CHANGED", true, OnScale)
end

-- A release under lockdown parks state driver work (visibility drivers,
-- glow combat gates), and the module's own PLAYER_REGEN_ENABLED goes with
-- its events: this standalone listener applies it once combat ends.
local parkedListener
local function ReleaseParked(frame)
    if NS.IsCombatLocked() then return end
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    C.Visibility.FlushPending()
    C.AuraGlows.FlushGates()
end

-- Disable: the poll stops, every event goes and routing work parked for the
-- end of combat is dropped; parked driver work keeps its combat end.
function Events.Release(context)
    usableNext = 0
    StopPoll()
    assistMode = nil
    for event in pairs(events) do
        events[event] = nil
        context:RemoveEvent(event)
    end
    staleRoutes, seedLater = false, false
    if C.Visibility.HasPending() or C.AuraGlows.HasParkedGates() then
        if not parkedListener then
            parkedListener = S.CreateFrame("Frame")
            parkedListener:SetScript("OnEvent", ReleaseParked)
        end
        parkedListener:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

------------------------------------------------------------------ data units of the flush
-- Spec and catalog (a waiting first-run capture runs once Blizzard's data
-- is in), the routing index with its category seeds, event registration,
-- and the keybind and sound watches after a resolve.
local function CatalogUnit(locked)
    if UpdateSpec() then dirty.resolve = true end
    -- A changed catalog may move equipment slot records between bars.
    if C.Catalog.Rebuild() then dirty.resolve, dirty.events = true, true end
    CaptureWhenReady(locked)
end
local function IndexUnit(locked)
    staleRoutes = false
    Index.Rebuild()
    if locked then
        seedLater = true
    else
        SeedCategories()
    end
end
local function EventsUnit()
    UpdateEvents()
    UpdateAssist()
end
local function KeysLaterUnit()
    if KeybindWatch() then C.Keybinds.Request(false) end
end
local function AlertsUnit()
    if AlertsWanted() then C.Alerts.SyncAuraSounds() end
end
Flush.BindDataUnits(CatalogUnit, IndexUnit, EventsUnit, KeysLaterUnit, AlertsUnit)
