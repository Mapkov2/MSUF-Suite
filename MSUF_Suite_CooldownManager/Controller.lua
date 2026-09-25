local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Lifecycle, the settings reader, one dirty mask with a prebuilt next-frame
-- flush, the event map, spec detection, the assisted-combat source, movers
-- and the exports for the options page and MSUF.
--
-- Refresh runs on every setting change (slider ticks included). It reads the
-- flat settings into per-bar views in place, bumps the generation of each
-- group that changed and marks only the work that setting needs; the flush
-- then runs in dependency order: catalog, resolve, index, structure (icons
-- before aura overlays), style, cooldown state, effects, layout, visibility.
-- A resolve passes on only what changed: bars whose plan moved sync, lay out
-- and repaint; entries that kept their place but changed refresh alone.
-- Events register only while something consumes them. Cooldown events
-- refresh their entries at once, inside the event, because isOnGCD is only
-- trustworthy there; the other hot events mark entries and share the flush.
-- Hot handlers guard payloads with the client's issecretvalue directly.
local M = C.M
local CDM = NS.CDM
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local ID = "cooldownManager"
local Public = S.Public
local issecret = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil
local EMPTY = C.EMPTY
local pairs, type, next = pairs, type, next
local ceil, huge = math.ceil, math.huge
local wipe = C.wipe
local K = C.Const
local GCD = K.GCD_CATEGORY
local QUIET = 2   -- seconds without sounds after loading screens and activation

------------------------------------------------------------------ settings work (spec 8.1)
-- What a change of one bar setting dirties, by suffix:
--  layout   bar geometry: layoutGen and one layout pass
--  flow     aura container flow (aura bars only; cooldown icons are placed by the layout)
--  style    icon look: styleGen, restyle of icons and aura buttons
--  restyle  look without a generation (tooltips, frame layer, aura glow look)
--  behavior behaviorGen and a refresh of the bar's cooldown entries
--  index    event routing membership (Index.Rebuild, event registration)
--  overlay  aura overlays on cooldown icons   aura  aura containers of aura bars
--  visible  visibility driver and opacity     resolve  what the bar holds
--  bar      buff bar look                     keybind  keybind texts and events
local WORK = {}
local function Work(list, flags)
    for i = 1, #list do
        local work = WORK[list[i]] or {}
        for key, value in pairs(flags) do work[key] = value end
        WORK[list[i]] = work
    end
end
Work({ "x", "y", "anchor", "side", "gap" }, { layout = true })
Work({ "align", "spacing", "perRow", "maxIcons", "vertical", "grow" }, { layout = true, flow = true })
Work({ "size", "height", "barWidth", "barHeight" }, { layout = true, flow = true, style = true })
Work({ "on" }, { layout = true, resolve = true, visible = true })
Work({ "kind" }, { layout = true, flow = true, resolve = true, style = true, behavior = true, bar = true })
Work({ "zoom", "border", "borderColor", "borderClass", "swipeAlpha", "edge", "cdText", "cdSize", "stackSize", "stackPos",
    "keybindSize", "keybindPos", "textTop" }, { style = true })
-- Counts: the icon's text switch (style), the count read back when shown
-- again (behavior) and use-count routing (index).
Work({ "stackText" }, { style = true, behavior = true, index = true })
Work({ "keybind" }, { style = true, keybind = true })
Work({ "desat", "cdAlpha", "readyAlpha", "hideReady", "rangeColor", "bling" }, { behavior = true })
-- The glow look also styles aura glows: aura buttons of aura bars and the
-- overlays of cooldown bars restyle through their diffed sync.
Work({ "glowStyle", "glowColor", "glowTint" }, { behavior = true, restyle = true })
Work({ "range", "usable", "procGlow", "readyGlow", "charges", "assist" }, { behavior = true, index = true })
Work({ "showAura" }, { behavior = true, index = true, overlay = true })
Work({ "showMissing", "keepSlots", "auraGlow", "pandemic" }, { behavior = true, aura = true })
Work({ "vis", "hideMounted", "hideVehicle", "alpha", "oocAlpha" }, { visible = true })
Work({ "tooltips" }, { restyle = true })
Work({ "strata" }, { restyle = true, visible = true })
Work({ "barTexture", "barColor", "barClass", "barBgAlpha", "barIcon", "barIconSide", "barName", "barTime", "barFill" }, { bar = true })
Work({ "name" }, { named = true })
-- A fresh view (first read, activation) does everything once.
local FRESH = { layout = true, style = true, behavior = true, index = true, visible = true, resolve = true, named = true }
C.SettingWork = WORK
local COLOR = { borderColor = { "borderR", "borderG", "borderB" }, glowColor = { "glowR", "glowG", "glowB" },
    rangeColor = { "rangeR", "rangeG", "rangeB" }, barColor = { "barR", "barG", "barB" } }
local OUTLINE = { "OUTLINE", "THICKOUTLINE", "" }
local CHANNEL = { "Master", "SFX", "Dialog" }

-- Per slot: suffixes, their keys and work records as arrays (built-in bars
-- have a fixed kind and title, so those two rules are skipped).
local SUFFIX, KEY, WORKS = {}, {}, {}
for i = 1, #SLOTS do
    local def = SLOTS[i]
    local s, keys, w = {}, {}, {}
    for suffix, key in pairs(KEYS[def.key]) do
        if not (def.builtin and (suffix == "kind" or suffix == "name")) then
            s[#s + 1], keys[#keys + 1], w[#w + 1] = suffix, key, WORK[suffix] or EMPTY
        end
    end
    SUFFIX[i], KEY[i], WORKS[i] = s, keys, w
end

------------------------------------------------------------------ dirty mask
-- keysLater: keybind texts after a resolve, through the coalesced request.
local dirty = { catalog = false, resolve = false, index = false, events = false, cooldowns = false, usable = false, effects = false,
    keybinds = false, keysLater = false, alerts = false, layout = false, visibility = false }
-- Per slot: sync (structure), style, behavior (entry refresh), visible
-- (driver and alpha), laid (layout of that bar only).
local sync, style, behavior, visible, laid, marked = {}, {}, {}, {}, {}, {}
local hit = {}
-- The plan (and its generation) each bar was last synced with.
local seenPlan, seenGen = {}, {}
-- staleRoutes: an override arrived in combat and was routed without a
-- rebuild; seedLater: category entries wait for combat to end.
local staleRoutes, seedLater = false, false
local scheduled, first, captureWait, pendingCapture, optionsPreview = false, true, false, nil, false
local events = {}
local specName, specIcon
local lastLists, lastSpells
local seenHex = {}
-- SPELL_UPDATE_USABLE has no spell payload. Bound its visible-icon sweep to
-- ten times per second in combat storms, with one trailing refresh so the
-- final state is never lost. Other events and show edges still paint now.
local USABLE_INTERVAL = .1
local usableNext, usableArmed = 0, false

local Flush
local function Schedule()
    if scheduled or not M.active then return end
    scheduled = true
    local timer = _G.C_Timer
    if timer and timer.After then
        timer.After(0, Flush)
    else
        Flush()
    end
end
C.Schedule = Schedule

-- MSUF follows our Essential bar (MSUF_GetSuiteCooldownAnchor): one
-- notification per frame when that bar appears or goes. MSUF defers its own
-- work in combat.
local anchorNotify = false
local function FireAnchorChanged()
    anchorNotify = false
    local registry = _G.EventRegistry
    if registry and registry.TriggerEvent then registry:TriggerEvent("MSUFSuite.CooldownManager.AnchorChanged") end
end
function C.AnchorChanged()
    if anchorNotify then return end
    anchorNotify = true
    local timer = _G.C_Timer
    if timer and timer.After then
        timer.After(0, FireAnchorChanged)
    else
        FireAnchorChanged()
    end
end

-- Marks in one frame merge to the one that refreshes most: "full" (texture,
-- state, effects) over "charges" (state and count) over "recharge" (the
-- recharge swipe and count, SPELL_UPDATE_CHARGES) over "count" (the count
-- alone, SPELL_UPDATE_USES) over "item" (bag contents: potion and
-- healthstone entries keep their cooldown).
local RANK = { item = 1, count = 2, recharge = 3, charges = 4, full = 5 }
local function Mark(entry, reason)
    local pending = marked[entry]
    if pending == nil or RANK[reason] > RANK[pending] then marked[entry] = reason end
    Schedule()
end

local function ResetDirty()
    for key in pairs(dirty) do dirty[key] = false end
    wipe(sync)
    wipe(style)
    wipe(behavior)
    wipe(visible)
    wipe(laid)
    wipe(marked)
end
local function Pending()
    for _, on in pairs(dirty) do
        if on then
            return true
        end
    end
    return next(sync) ~= nil or next(style) ~= nil or next(behavior) ~= nil or next(visible) ~= nil or next(laid) ~= nil
        or next(marked) ~= nil
end

------------------------------------------------------------------ reading settings
local function ReadGlobals(config, all)
    local state = C.state
    local text = all
    local raid = config.raidEssentials ~= false
    if all or state.raidEssentials ~= raid then state.raidEssentials, dirty.resolve = raid, true end
    local font, flags = S.ResolveFont(config.font), OUTLINE[config.fontOutline] or "OUTLINE"
    if state.font ~= font or state.fontFlags ~= flags or state.fontRendering ~= config.fontRendering
        or state.fontShadow ~= config.fontShadow or state.fontShadowOpacity ~= config.fontShadowOpacity
        or state.fontShadowDistance ~= config.fontShadowDistance then
        state.font, state.fontFlags, state.fontRendering = font, flags, config.fontRendering
        state.fontShadow, state.fontShadowOpacity, state.fontShadowDistance =
            config.fontShadow, config.fontShadowOpacity, config.fontShadowDistance
        text = true
    end
    if seenHex.cd ~= config.cdColor then
        seenHex.cd, text = config.cdColor, true
        state.cdR, state.cdG, state.cdB = S.RGB(config.cdColor)
    end
    if seenHex.stack ~= config.stackColor then
        seenHex.stack, text = config.stackColor, true
        state.stackR, state.stackG, state.stackB = S.RGB(config.stackColor)
    end
    if seenHex.key ~= config.keybindColor then
        seenHex.key, text = config.keybindColor, true
        state.keyR, state.keyG, state.keyB = S.RGB(config.keybindColor)
    end
    if seenHex.th ~= config.thresholdColor then
        seenHex.th, text = config.thresholdColor, true
        state.thR, state.thG, state.thB = S.RGB(config.thresholdColor)
    end
    if state.threshold ~= config.thresholdSeconds then state.threshold, text = config.thresholdSeconds, true end
    local gcd = config.showGCD == true
    if all or state.showGCD ~= gcd then state.showGCD, dirty.cooldowns = gcd, true end
    local glow = config.readyGlowCombat == true
    if all or state.readyGlowCombat ~= glow then state.readyGlowCombat, dirty.effects = glow, true end
    local mute, channel = config.muteSounds == true, CHANNEL[config.soundChannel] or "Master"
    if all or state.muteSounds ~= mute or state.soundChannel ~= channel then state.muteSounds, state.soundChannel, dirty.alerts = mute, channel, true end
    return text
end

-- Views are rebuilt in place. Each changed setting adds its work (WORK) to
-- the slot's hit set; the set then bumps generations and marks work once.
-- A position drag or an opacity slider never syncs structure, a behavior
-- tick rebuilds the routing index only when membership can change.
local function ReadViews(config, all, text)
    for i = 1, #SLOTS do
        local def = SLOTS[i]
        local slot = def.key
        local view = C.views[slot]
        local fresh = all or view == nil
        if not view then
            view = { key = slot, index = i, builtin = def.builtin == true, kind = def.kind, title = S.Text(def.title),
                styleGen = 0, layoutGen = 0, behaviorGen = 0 }
            C.views[slot] = view
        end
        local suffixes, keys, works = SUFFIX[i], KEY[i], WORKS[i]
        for j = 1, #keys do
            local suffix, value = suffixes[j], config[keys[j]]
            if view[suffix] ~= value then
                view[suffix] = value
                for key in pairs(works[j]) do hit[key] = true end
                local color = COLOR[suffix]
                if color then view[color[1]], view[color[2]], view[color[3]] = S.RGB(value) end
            end
        end
        if fresh then
            for key in pairs(FRESH) do
                hit[key] = true
            end
        end
        if text then hit.style = true end
        if not def.builtin then
            if view.kind ~= 1 and view.kind ~= 2 and view.kind ~= 3 then view.kind = 1 end
            if hit.named then
                local name = view.name
                view.title = type(name) == "string" and name ~= "" and name or S.Text(def.title)
            end
        end
        if next(hit) ~= nil then
            local aura = view.kind == 2 or view.kind == 3
            if hit.layout then
                view.layoutGen = view.layoutGen + 1
                dirty.layout = true
            end
            if hit.style then view.styleGen = view.styleGen + 1 end
            if hit.style or hit.restyle then style[slot] = true end
            if hit.behavior then
                view.behaviorGen = view.behaviorGen + 1
                behavior[slot] = true
            end
            if hit.index then dirty.index = true end
            if hit.visible then visible[slot] = true end
            -- Structure: aura containers follow flow, aura and buff bar
            -- settings; cooldown bars only their aura overlays.
            if fresh or (aura and (hit.flow or hit.aura or hit.bar)) or (not aura and hit.overlay) then sync[slot] = true end
            if hit.resolve then dirty.resolve = true end
            if hit.keybind then dirty.keybinds, dirty.events = true, true end
            wipe(hit)
        end
    end
end

-- The data strings are decoded only when they changed. Per-spell choices
-- reach cooldown entries through the behavior refresh and aura buttons and
-- overlays through a structural sync.
local function DecodeData(config)
    local lists, spells = config.listsData, config.spellsData
    if lists ~= lastLists then
        lastLists = lists
        C.lists = CDM.Codec.DecodeLists(lists)
        dirty.resolve = true
    end
    if spells ~= lastSpells then
        lastSpells = spells
        C.spells = CDM.Codec.DecodeSpells(spells)
        dirty.resolve, dirty.alerts, dirty.index = true, true, true
        for i = 1, #SLOTS do
            local slot = SLOTS[i].key
            behavior[slot], sync[slot] = true, true
        end
    end
end

------------------------------------------------------------------ spec
local function UpdateSpec()
    local info = _G.C_SpecializationInfo
    local id, name, icon
    local index = info and info.GetSpecialization and info.GetSpecialization()
    if Public(index) and type(index) == "number" and index > 0 and info.GetSpecializationInfo then
        local sid, sname, _, sicon = info.GetSpecializationInfo(index)
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

------------------------------------------------------------------ preview mode
local function PreviewChanged()
    dirty.resolve, dirty.cooldowns, dirty.effects, dirty.layout, dirty.visibility = true, true, true, true, true
    Schedule()
end
-- MSUF Edit Mode wins over the options page; both suspend the bar rules.
local function ApplyPreview()
    local mode = (S.editMode == true and "edit") or (optionsPreview and "options") or nil
    if C.Preview.SetMode(mode) then PreviewChanged() end
end

------------------------------------------------------------------ first-run capture
local function PersistCapture()
    local values = pendingCapture
    if not values or not M.active then
        pendingCapture = nil
        return
    end
    if NS.IsCombatLocked() then return end
    pendingCapture = nil
    S.SetMany(ID, values)
end
-- Plain finite numbers; settings rounded and clamped to their rule (K.Clamp).
local Finite = S.Finite
local Clamp = K.Clamp
-- A stand-in view for Layout.Point while converting saved positions.
local pointProbe = {}

-- Saved settings from before CDM.DEFAULTS_VERSION: every bar setting goes
-- back to its current default once; bar contents and spell choices stay.
local function Outdated(config)
    return type(config) == "table" and (tonumber(config.defaultsVersion) or 0) < CDM.DEFAULTS_VERSION
end
local function ResetDefaults(values, config)
    local catalog = NS.SuiteCatalog and NS.SuiteCatalog[ID]
    local rules = catalog and catalog.rules or EMPTY
    if (tonumber(config.defaultsVersion) or 0) < 1 then
        local keep = CDM.DEFAULTS_KEEP
        for key, rule in pairs(rules) do
            if not keep[key] and values[key] == nil and config[key] ~= rule.default then values[key] = rule.default end
        end
    else
        local version = tonumber(config.defaultsVersion) or 0
        local uiW, uiH = UIParent and UIParent:GetWidth(), UIParent and UIParent:GetHeight()
        local center = version < 3 and Finite(uiW) and Finite(uiH)
        for i = 1, #SLOTS do
            local def = SLOTS[i]
            local keys = KEYS[def.key]
            local anchor = values[keys.anchor] or config[keys.anchor]
            if anchor ~= 1 then
                if version < 2 and values[keys.x] == nil then values[keys.x], values[keys.y] = 0, 0 end
            elseif center and values[keys.x] == nil then
                if def.custom and config[keys.on] ~= true then
                    -- Unused custom bars start in the middle of the screen.
                    values[keys.x], values[keys.y] = 0, 0
                else
                    -- Free x/y used to count from the same point of UIParent.
                    pointProbe.kind = config[keys.kind] or def.kind or 1
                    pointProbe.vertical = keys.vertical and config[keys.vertical] == true or false
                    pointProbe.grow = keys.grow and config[keys.grow] or nil
                    local dx, dy = K.EdgeOffset(C.Layout.Point(pointProbe), uiW, uiH)
                    values[keys.x], values[keys.y] = Clamp(keys.x, (config[keys.x] or 0) + dx), Clamp(keys.y, (config[keys.y] or 0) + dy)
                end
            end
        end
    end
    values.defaultsVersion = CDM.DEFAULTS_VERSION
    return values
end
local Convert
-- The Essential bar's view takes x/y at once, so this flush already places
-- it there; the settings follow a frame later.
local function Reposition(x, y)
    local view = C.views.ess
    if not view or x == nil then return end
    view.x, view.y = x, y
    view.layoutGen = view.layoutGen + 1
    dirty.layout = true
end
-- Screen position (x/y from the screen center) of the riding Essential
-- bar's growth edge: from its frame, else (bar off, a stand-in shown) from
-- Blizzard's bar plus the current offset; nil when neither is readable.
local function RideToFree()
    local keys = KEYS.ess
    local free = Convert("ess", nil, nil, true)
    if free and free[keys.x] ~= nil then return free[keys.x], free[keys.y] end
    local view = C.views.ess
    if not (view and UIParent) then return nil end
    local vx, vy = C.Layout.ViewerPoint(view)
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    if not (Finite(vx) and Finite(vy) and Finite(uiW) and Finite(uiH)) then return nil end
    return Clamp(keys.x, vx + (view.x or 0) - uiW / 2), Clamp(keys.y, vy + (view.y or 0) - uiH / 2)
end
-- The Essential bar's x/y mean an offset from Blizzard's bar while the
-- layout rides it (Layout.RidesViewer: MSUF follows Blizzard's bar and the
-- Essential bar is not attached) and a screen position while it is free;
-- attached, they are an offset from its attach point and are never
-- rewritten here (only the flag follows). On each switch the values are
-- rewritten so the bar does not jump; when nothing is readable nothing is
-- written and the next Refresh tries again. Written a frame later with the
-- capture; a switch back before that drops the rewrite.
local function SyncViewerOffset()
    local config = M.config
    if type(config) ~= "table" or NS.IsCombatLocked() then return end
    local on = C.Layout.RidesViewer("ess") == true
    local saved = config.essOnViewer == true
    local waiting = pendingCapture and pendingCapture.essOnViewer
    local keys = KEYS.ess
    if waiting == nil then
        if saved == on then return end
    elseif waiting == on then
        return
    elseif saved == on then
        pendingCapture[keys.x], pendingCapture[keys.y], pendingCapture.essOnViewer = nil, nil, nil
        if next(pendingCapture) == nil then pendingCapture = nil end
        Reposition(config[keys.x], config[keys.y])
        return
    end
    local values = pendingCapture or {}
    -- Free again: the place the bar has now, unless a pending capture
    -- already holds a screen position.
    if on then
        values[keys.x], values[keys.y] = 0, 0
    elseif values[keys.x] == nil and C.Layout.Free("ess") then
        local x, y = RideToFree()
        if x == nil then return end
        values[keys.x], values[keys.y] = x, y
    end
    values.essOnViewer = on
    pendingCapture = values
    Reposition(values[keys.x], values[keys.y])
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(0, PersistCapture) end
end
-- Blizzard's bar positions become ours once, before the takeover hides
-- them. Settings are written a frame later: SetMany re-applies the module.
local function Capture()
    captureWait = false
    local config = M.config
    local values
    -- Positions are read only on the first run and the full reset.
    if type(config) ~= "table" or config.captured ~= true or (tonumber(config.defaultsVersion) or 0) < 1 then
        values = C.Native.Capture()
    end
    if Outdated(config) then values = ResetDefaults(values or {}, config) end
    if values then
        pendingCapture = values
        local timer = _G.C_Timer
        if timer and timer.After then timer.After(0, PersistCapture) end
    end
    C.Native.Apply()
end

------------------------------------------------------------------ hot event handlers
-- Prebuilt callbacks; per-event values travel through these upvalues.
local stamp, curSpell, curRange = 0, nil, nil
local function RefreshCooldown(entry)
    if entry.cdStamp == stamp or not entry.icon then return end
    entry.cdStamp = stamp
    if C.Time.Refresh(entry, "cooldown") then C.Layout.Request(entry.slot) end
end
local function EachCooldown(fn)
    local list = C.Index.cooldown
    for i = 1, #list do fn(list[i]) end
end
local function SetCategorySpell(entry) entry.catSpell = curSpell end

-- SPELL_UPDATE_COOLDOWN: nil or unreadable spell = all; category payloads
-- (potions, healthstones) name the spell that started the category; a GCD
-- start touches every icon only while icons show the GCD. A payload value
-- that is secret counts as absent.
local function OnCooldown(_, _, spellID, baseSpellID, category, recovery, itemID)
    stamp = stamp + 1
    if (issecret and issecret(spellID)) or spellID == nil then return EachCooldown(RefreshCooldown) end
    local index = C.Index
    local item = not (issecret and issecret(itemID)) and itemID or nil
    if item and not (issecret and issecret(category)) and category and category ~= 0 then
        curSpell = not (issecret and issecret(baseSpellID)) and baseSpellID or spellID
        if index.ForCategory(category, SetCategorySpell) > 0 then index.ForCategory(category, RefreshCooldown) end
    end
    if C.state.showGCD and not (issecret and issecret(recovery)) and recovery == GCD then return EachCooldown(RefreshCooldown) end
    index.ForSpell(spellID, baseSpellID, RefreshCooldown)
    if item then index.ForItem(item, RefreshCooldown) end
end

local countedSet = C.Index.countedSet
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
    local list = C.Index.charged
    for i = 1, #list do
        local entry = list[i]
        local icon = entry.icon
        if icon and icon.chargeSet then Mark(entry, "recharge") end
    end
end
-- SPELL_UPDATE_USES: the count alone (Time "count"), for entries that show
-- counts; the cooldown stays with SPELL_UPDATE_COOLDOWN.
local function OnUses(_, _, spellID, baseSpellID) C.Index.ForSpell(spellID, baseSpellID, MarkCount) end
-- Item cooldowns: items and equipment slots only. Potion and healthstone
-- entries follow their category payload in SPELL_UPDATE_COOLDOWN.
local function OnBag()
    local list = C.Index.bags
    for i = 1, #list do MarkItem(list[i]) end
end
-- Bag contents changed: potion counts are recounted once, then every item
-- and category entry refreshes.
local function OnBagContents()
    C.Time.BagsChanged()
    local list = C.Index.items
    for i = 1, #list do MarkItem(list[i]) end
end
-- Visibility keeps transparent bars in the plan. Only visible icons need
-- a usability read; Visibility.Paint catches up on the show edge. The
-- trailing refresh of a throttle window is one shared callback behind an
-- armed flag (no timer object per window); a disable does not cancel it,
-- the callback finds the module inactive.
local function UsableWindowDone()
    usableArmed = false
    if not M.active then return end
    usableNext = GetTime() + USABLE_INTERVAL
    dirty.usable = true
    Schedule()
end
local function OnUsable()
    if dirty.usable or usableArmed then return end
    local list = C.Index.usable
    for i = 1, #list do
        local entry = list[i]
        local bar = C.bars[entry.slot]
        if entry.icon and bar and bar.hidden ~= true and not entry.outOfRange then
            local now = GetTime()
            local timer = _G.C_Timer
            if now >= usableNext or not (timer and timer.After) then
                usableNext = now + USABLE_INTERVAL
                dirty.usable = true
                Schedule()
            else
                usableArmed = true
                timer.After(usableNext - now, UsableWindowDone)
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
    if (issecret and issecret(spellID)) or spellID == nil then return EachCooldown(Retexture) end
    C.Index.ForSpell(spellID, nil, Retexture)
end

local function ProcOn(entry) C.Effects.Proc(entry, true) end
local function ProcOff(entry) C.Effects.Proc(entry, false) end
local function OnGlowShow(_, _, spellID) C.Index.ForSpell(spellID, nil, ProcOn) end
local function OnGlowHide(_, _, spellID) C.Index.ForSpell(spellID, nil, ProcOff) end

-- Only the entry holding the check for this spell follows its update.
local function RangeEntry(entry)
    if entry.rangeSpell == curSpell then C.Effects.Range(entry, curRange) end
end
local function OnRange(_, _, spell, inRange, checksRange)
    if (issecret and issecret(spell)) or spell == nil then return end
    curSpell, curRange = spell, nil
    if not (issecret and (issecret(checksRange) or issecret(inRange))) and checksRange then curRange = inRange end
    C.Index.ForSpell(spell, nil, RangeEntry)
end

local function OnTarget()
    local list = C.Index.ranged
    for i = 1, #list do C.Effects.ReadRange(list[i]) end
    C.Auras.TargetChanged()
end
-- The target's disposition can flip without a retarget (a duel, a charm):
-- target aura containers pause while it is friendly. Other units: one compare.
local function OnFaction(_, _, unit)
    if not (issecret and issecret(unit)) and unit == "target" then
        local react = C.Auras.TargetReaction
        if react then react() end
    end
end
-- A restriction ended (M+ key, PvP match, encounter): aura restyles that
-- sealed buttons held back run next frame, not at the next combat end.
-- Registered only while aura containers or overlays exist.
local RESTRICTION_OFF = _G.Enum and _G.Enum.AddOnRestrictionState and _G.Enum.AddOnRestrictionState.Inactive or 0
local function OnRestriction(_, _, _, state)
    if Public(state) and state == RESTRICTION_OFF and (next(C.Auras.pending) or C.Alerts.pending) then
        local timer = _G.C_Timer
        if timer and timer.After then
            timer.After(0, C.Auras.FlushPending)
        else
            C.Auras.FlushPending()
        end
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
    C.Index.AddSpell(entry, entry.override)
end
local function OnOverride(_, _, base, override)
    if not C.Catalog.OnOverride(base, override) then return end
    if C.Index.ForBase(base, Overridden) == 0 then return end
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
local function OnLayoutChanged()
    if C.Catalog.LayoutStale() then
        dirty.catalog = true
        Schedule()
    end
end
-- Trinket slots and slots an entry tracks; other gear changes cost a lookup.
local function OnEquipment(_, _, slot)
    if Public(slot) and slot ~= nil and slot ~= 13 and slot ~= 14 and not C.Index.byEquip[slot] then return end
    dirty.catalog, dirty.resolve = true, true
    Schedule()
end
local function OnBindings() C.Keybinds.Request(true) end

local function AlertsWanted()
    local list = C.Index.aura
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
    local state = C.state
    state.inCombat = NS.IsCombatLocked()
    state.soundQuietUntil = GetTime() + QUIET
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
            if view.kind == 2 or view.kind == 3 then sync[slot] = true end
        end
    end
    dirty.layout = true
    Schedule()
end

------------------------------------------------------------------ assisted combat (spec 10.4)
-- With Blizzard's highlight on, its own change callback feeds us; otherwise
-- a 0.2 s poll runs in combat only.
local assistMode, assistTicker
local function Suggested(spell)
    if Public(spell) and type(spell) == "number" then return spell end
end
local function OnHighlight()
    if assistMode ~= "callback" then return end
    local manager = _G.AssistedCombatManager
    C.Effects.Assist(Suggested(type(manager) == "table" and manager.lastNextCastSpellID or nil))
end
local function Poll()
    local api = _G.C_AssistedCombat
    C.Effects.Assist(Suggested(api and api.GetNextCastSpell and api.GetNextCastSpell(true)))
end
local function StopPoll()
    if assistTicker then
        assistTicker:Cancel()
        assistTicker = nil
    end
end
local function StartPoll()
    if assistTicker or assistMode ~= "poll" or not C.state.inCombat then return end
    local timer = _G.C_Timer
    if timer and timer.NewTicker then assistTicker = timer.NewTicker(.2, Poll) end
    Poll()
end
local function HighlightOn()
    local cvar = _G.C_CVar
    local value = cvar and cvar.GetCVar and cvar.GetCVar("assistedCombatHighlight")
    return Public(value) and value == "1"
end
local function UpdateAssist()
    local api, mode = _G.C_AssistedCombat, nil
    if #C.Index.assist > 0 and api and api.GetNextCastSpell then
        local available = true
        if api.IsAvailable then available = api.IsAvailable() end
        if Public(available) and available then mode = HighlightOn() and "callback" or "poll" end
    end
    if mode ~= assistMode then
        StopPoll()
        assistMode = mode
        if mode == "callback" then
            if M.context:Callback("AssistedCombatManager.OnAssistedHighlightSpellChange", OnHighlight) then
                OnHighlight()
            else
                assistMode = "poll"
            end
        end
        if not mode then C.Effects.Assist(nil) end
    end
    StartPoll()
end

------------------------------------------------------------------ category seeds
-- Category entries start from the last spell that started their category.
-- The source is read out of combat only; seeded icons refresh.
local function SeedCategories()
    local get = _G.C_Spell and _G.C_Spell.GetLastCategoryCooldownSource
    if not get then return end
    local list = C.Index.items
    for i = 1, #list do
        local entry = list[i]
        local category = entry.spellCategory
        if category and category ~= 0 and not entry.catSpell then
            local spell, item = get(category)
            if Public(spell) and type(spell) == "number" and spell > 0 and Public(item) and item then
                entry.catSpell = spell
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
    C.Effects.CombatChanged(true)
    C.Visibility.CombatChanged()
    C.Visibility.FlushPending()
    C.Auras.FlushPending()
    C.Layout.CombatEnded()
    if assistMode == "poll" then
        StopPoll()
        C.Effects.Assist(nil)
    end
    if captureWait and C.Catalog.Ready() then Capture() end
    if pendingCapture then PersistCapture() end
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

------------------------------------------------------------------ event map (spec 8.3)
local function Want(event, on, handler)
    on = on and true or false
    if (events[event] == true) == on then return end
    events[event] = on or nil
    if on then
        M.context:Event(event, handler, true)
    else
        M.context:RemoveEvent(event)
    end
end
local function TargetWatch()
    local list = C.Index.aura
    for i = 1, #list do
        if list[i].unit ~= "player" then
            return true
        end
    end
    list = C.Index.overlay
    for i = 1, #list do
        if list[i].unit ~= "player" then
            return true
        end
    end
    return false
end
local function KeybindWatch()
    for slot, plan in pairs(C.plans) do
        local view = C.views[slot]
        if plan.kind == 1 and view and view.keybind and #plan.entries > 0 then return true end
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
    return #C.Index.items > 0
end
local function UpdateEvents()
    local index = C.Index
    local cooldown = #index.cooldown > 0
    Want("SPELL_UPDATE_COOLDOWN", cooldown, OnCooldown)
    Want("SPELL_UPDATE_USES", #index.counted > 0, OnUses)
    Want("SPELL_UPDATE_ICON", cooldown, OnIcon)
    Want("SPELL_UPDATE_CHARGES", #index.charged > 0, OnCharges)
    Want("BAG_UPDATE_COOLDOWN", #index.bags > 0, OnBag)
    Want("BAG_UPDATE_DELAYED", #index.items > 0, OnBagContents)
    Want("SPELL_UPDATE_USABLE", #index.usable > 0, OnUsable)
    Want("SPELL_RANGE_CHECK_UPDATE", #index.ranged > 0, OnRange)
    local proc = #index.proc > 0
    Want("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", proc, OnGlowShow)
    Want("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", proc, OnGlowHide)
    Want("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", cooldown or #index.aura > 0, OnOverride)
    local target = TargetWatch()
    Want("PLAYER_TARGET_CHANGED", #index.ranged > 0 or target, OnTarget)
    Want("UNIT_FACTION", target, OnFaction)
    Want("ADDON_RESTRICTION_STATE_CHANGED", #index.aura > 0 or #index.overlay > 0, OnRestriction)
    Want("PLAYER_EQUIPMENT_CHANGED", EquipWatch(), OnEquipment)
    local keys = KeybindWatch()
    Want("UPDATE_BINDINGS", keys, OnBindings)
    Want("ACTIONBAR_SLOT_CHANGED", keys, OnBindings)
end
-- Catalog, combat, scale and loading-screen events while the module runs.
local CATALOG_EVENTS = { "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED" }
local function CoreEvents()
    for i = 1, #CATALOG_EVENTS do Want(CATALOG_EVENTS[i], true, OnCatalog) end
    Want("PLAYER_ENTERING_WORLD", true, OnWorld)
    Want("PLAYER_REGEN_DISABLED", true, OnCombatStart)
    Want("PLAYER_REGEN_ENABLED", true, OnCombatEnd)
    Want("UI_SCALE_CHANGED", true, OnScale)
    Want("DISPLAY_SIZE_CHANGED", true, OnScale)
end

------------------------------------------------------------------ flush (spec 8.2)
-- After a resolve: bars whose plan appeared, went or changed its list
-- sync, lay out and repaint; entries that kept their place but changed on
-- refill refresh alone (their aura containers sync when their aura IDs
-- moved). Routing, sounds and keybind texts follow only a real change.
local function Resolved(any)
    local plans = C.plans
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local plan = plans[slot]
        local gen = plan and plan.gen
        if seenPlan[slot] ~= plan or seenGen[slot] ~= gen then
            seenPlan[slot], seenGen[slot] = plan, gen
            sync[slot], visible[slot], laid[slot] = true, true, true
            any = true
        end
    end
    local R = C.Resolve
    local touched, auraTouched = R.touched, R.auraTouched
    for i = 1, #touched do
        local entry = touched[i]
        if entry.icon then Mark(entry, "full") end
        local slot = entry.slot
        if slot and (entry.family == 2 or auraTouched[entry]) then sync[slot] = true end
    end
    if any or touched[1] ~= nil then dirty.index, dirty.alerts, dirty.keysLater = true, true, true end
end

local function MarkPlans(only)
    for slot, plan in pairs(C.plans) do
        if plan.kind == 1 and (not only or only[slot]) then
            local list = plan.entries
            for i = 1, #list do marked[list[i]] = "full" end
        end
    end
end

local function RefreshMarked()
    for entry, reason in pairs(marked) do
        marked[entry] = nil
        if entry.icon and entry.slot then
            if reason == "full" then C.Icons.Texture(entry) end
            if C.Time.Refresh(entry, reason) then C.Layout.Request(entry.slot) end
            if reason == "full" then C.Effects.Update(entry) end
        end
    end
end

-- Flush steps, in dependency order.

-- Catalog, resolve, routing index and event registration.
local function FlushData(locked)
    if dirty.catalog then
        dirty.catalog = false
        if UpdateSpec() then dirty.resolve = true end
        -- A changed catalog may move equipment slot records between bars.
        if C.Catalog.Rebuild() then dirty.resolve, dirty.events = true, true end
        if captureWait and C.Catalog.Ready() and not locked then Capture() end
    end
    if dirty.resolve then
        dirty.resolve = false
        local _, any = C.Resolve.Build()
        C.Preview.Decorate()
        Resolved(any)
    end
    if dirty.index then
        dirty.index, dirty.events, staleRoutes = false, true, false
        C.Index.Rebuild()
        if locked then
            seedLater = true
        else
            SeedCategories()
        end
    end
    if dirty.events then
        dirty.events = false
        UpdateEvents()
        UpdateAssist()
    end
end

-- Structure (icons before aura overlays) or, without it, the look.
local function FlushStructure()
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if sync[slot] then
            sync[slot], style[slot], laid[slot] = nil, nil, true
            C.Icons.Sync(slot)
            C.Auras.Sync(slot)
        elseif style[slot] then
            style[slot] = nil
            C.Icons.Style(slot)
            C.Auras.Restyle(slot)
        end
    end
end

-- Cooldown state of marked entries, usability of visible icons, effects.
local function FlushEntries()
    if dirty.cooldowns then
        dirty.cooldowns = false
        MarkPlans(nil)
    end
    if next(behavior) then
        MarkPlans(behavior)
        wipe(behavior)
    end
    RefreshMarked()
    if dirty.usable then
        dirty.usable = false
        local list = C.Index.usable
        for i = 1, #list do
            local entry = list[i]
            local bar = C.bars[entry.slot]
            if entry.icon and bar and bar.hidden ~= true and not entry.outOfRange then C.Effects.Usable(entry) end
        end
    end
    if dirty.effects then
        dirty.effects = false
        C.Effects.CombatChanged()
    end
end

-- Keybind setting changes push cached texts now; resolves wait for the
-- coalesced request. Aura sounds follow their entries.
local function FlushTextsAndSounds()
    if dirty.keybinds then
        dirty.keybinds, dirty.keysLater = false, false
        C.Keybinds.Refresh()
    end
    if dirty.keysLater then
        dirty.keysLater = false
        if KeybindWatch() then
            C.Keybinds.Request(false)
        end
    end
    if dirty.alerts then
        dirty.alerts = false
        if AlertsWanted() then
            C.Alerts.SyncAuraSounds()
        end
    end
end

-- Layout (all bars or the marked ones), then visibility.
local function FlushPlacement()
    if dirty.layout then
        dirty.layout = false
        wipe(laid)
        C.Layout.ApplyAll()
    else
        for i = 1, #SLOTS do
            local slot = SLOTS[i].key
            if laid[slot] then
                laid[slot] = nil
                C.Layout.Apply(slot)
            end
        end
        C.Layout.Flush()
    end
    if dirty.visibility then
        dirty.visibility = false
        wipe(visible)
        C.Visibility.ApplyAll()
    else
        for slot in pairs(visible) do
            visible[slot] = nil
            C.Visibility.Apply(slot)
        end
    end
end

Flush = function()
    if not M.active then
        scheduled = false
        ResetDirty()
        return
    end
    FlushData(NS.IsCombatLocked())
    FlushStructure()
    FlushEntries()
    FlushTextsAndSounds()
    FlushPlacement()
    scheduled = false
    if Pending() or next(C.Layout.dirty) then Schedule() end
end

------------------------------------------------------------------ lifecycle (spec 8.1)
function M:Enable()
    local state = C.state
    state.inCombat = NS.IsCombatLocked()
    state.soundQuietUntil = GetTime() + QUIET
    C.Layout.InvalidateScale()
    C.Resolve.SpellsChanged()
    first, captureWait, pendingCapture = true, false, nil
    -- Blizzard's layout is read before the takeover touches its bars; on a
    -- fresh login the capture waits for Blizzard's data.
    if self.config.captured ~= true or Outdated(self.config) then
        if C.Catalog.Ready() then
            Capture()
        else
            captureWait = true
        end
    end
    self.context:Callback("CooldownViewerSettings.OnPendingChanges", OnLayoutChanged)
    self.context:Callback("CooldownViewerSettings.OnHide", OnLayoutChanged)
    self:Refresh()
end

function M:Refresh()
    local config = self.config
    local all = first
    first = false
    local text = ReadGlobals(config, all)
    ReadViews(config, all, text)
    DecodeData(config)
    if all then dirty.catalog, dirty.resolve, dirty.layout, dirty.visibility, dirty.events, dirty.keybinds = true, true, true, true, true, true end
    ApplyPreview()
    if not captureWait then
        C.Native.Apply()
        SyncViewerOffset()
    end
    if S.editMode then
        C.Layout.ForgetAnchors()
        dirty.layout = true
    end
    CoreEvents()
    if Pending() then Schedule() end
end

-- The options page's preview request outlives a disable: the page turns it
-- off when it closes, and a re-enable while it is open applies it again.
function M:Disable()
    usableNext = 0
    C.Preview.SetMode(nil)
    C.Preview.ReleaseAll()
    StopPoll()
    assistMode, captureWait, pendingCapture = nil, false, nil
    C.Alerts.ReleaseAll()
    C.Auras.ReleaseAll()
    C.Effects.ReleaseAll()
    C.Icons.ReleaseAll()
    C.Layout.HideAll()
    C.Visibility.ReleaseAll()
    C.Native.Release()
    C.Keybinds.Clear()
    for event in pairs(events) do
        events[event] = nil
        self.context:RemoveEvent(event)
    end
    -- The next activation starts from a clean slate.
    wipe(C.plans)
    wipe(C.entries)
    wipe(C.Layout.dirty)
    wipe(seenPlan)
    wipe(seenGen)
    staleRoutes, seedLater = false, false
    C.Index.Rebuild()
    ResetDirty()
    first = true
end

------------------------------------------------------------------ movers
local movers = {}
local function Control(id, key)
    local rule = S.catalog[ID].rules[key]
    return { id = id, label = S.Text(rule.label), kind = "number", min = rule.min, max = rule.max, step = 1,
        get = function() return S.Config(ID)[key] end,
        set = function(value) return S.Set(ID, key, value) end }
end
local ICON_CONTROLS, BAR_CONTROLS = { "size", "spacing", "perRow" }, { "barWidth", "barHeight" }
-- Free bars move in MSUF Edit Mode; attached bars follow their parent.
local function Mover(i)
    local def = SLOTS[i]
    local slot, keys = def.key, KEYS[def.key]
    local list = keys.size and ICON_CONTROLS or BAR_CONTROLS
    local controls, history = {}, {}
    for j = 1, #list do
        local key = keys[list[j]]
        if key then
            controls[#controls + 1] = Control(list[j], key)
            history[#history + 1] = key
        end
    end
    return { label = def.title, order = 700 + i, xKey = keys.x, yKey = keys.y, extraControls = controls, historyKeys = history,
        getFrame = function()
            local bar = C.bars[slot]
            return bar and bar.frame
        end,
        point = function()
            local view = C.views[slot]
            return view and C.Layout.Point(view) or "TOP"
        end,
        place = function(x, y) return C.Layout.DragPlace(slot, x, y) end,
        isEnabled = function()
            local view = C.views[slot]
            return M.active == true and view ~= nil and view.on == true and C.plans[slot] ~= nil and C.Layout.Movable(slot)
        end }
end
function M:RegisterMovers()
    for i = 1, #SLOTS do
        movers[i] = movers[i] or Mover(i)
        S.RegisterOwnedMover(ID, SLOTS[i].key, movers[i])
    end
end

------------------------------------------------------------------ exports (spec 11.6)
-- A loaded but inactive module answers from a cold snapshot of the saved
-- settings; nothing is flushed while it is off. No catalog events run then,
-- so the Blizzard snapshot is rebuilt whenever the specialization moved.
local function Cold()
    if M.active then return end
    local config = S.Config(ID)
    if type(config) ~= "table" then return end
    ReadGlobals(config, false)
    ReadViews(config, false, false)
    DecodeData(config)
    UpdateSpec()
    local catalog = C.Catalog
    if catalog.generation == 0 or catalog.specTag ~= C.state.specTag then catalog.Rebuild() end
    ResetDirty()
end

local keyScratch, describe, homes = {}, {}, {}
local function Spells()
    local spells = C.spells
    return type(spells) == "table" and type(spells.e) == "table" and spells.e or EMPTY
end

-- The bar's keys for the current spec in display order, unlearned ones
-- included; hidden marks what a bar rule hides in live play.
function S.CooldownManagerBarEntries(slot)
    local rows = {}
    if not CDM.SLOT_INDEX[slot] then return rows end
    Cold()
    local keys = C.Resolve.Keys(slot, keyScratch)
    local view = C.views[slot] or EMPTY
    local cap = view.maxIcons
    if type(cap) ~= "number" or cap <= 0 then cap = nil end
    local spells = Spells()
    for i = 1, #keys do
        local key = keys[i]
        local live = C.entries[key]
        if live and live.slot ~= slot then live = nil end
        local desc = live or C.Resolve.Describe(key, describe)
        if desc then
            local ov = spells[key]
            if type(ov) ~= "table" then ov = EMPTY end
            local hide = ov.hideReady
            if hide == nil then hide = view.hideReady == true end
            -- An empty Healthstone (Time: entry.empty) leaves its bar too.
            local hidden = (cap ~= nil and #rows >= cap) or (hide and live ~= nil and desc.family == 1 and not live.cooling)
                or (live ~= nil and live.empty == true) or false
            rows[#rows + 1] = { key = key, name = desc.name, texture = ov.icon or desc.texture, known = desc.known ~= false, family = desc.family,
                hasAura = desc.hasAura == true, hidden = hidden == true }
        end
    end
    return rows
end

-- Read the active Blizzard CooldownViewer layout for this specialization.
-- Order and category moves come from Catalog.Rebuild; hidden pseudo-categories
-- are absent. Include unlearned entries so a talent switch keeps its layout.
-- This only returns a copy: importing is an explicit options-page action.
function S.CooldownManagerBlizzardSnapshot()
    Cold()
    local catalog = C.Catalog
    if not catalog.Ready() then return nil, "Blizzard's cooldown list is not ready yet." end
    catalog.Rebuild()
    if not C.state.specTag or catalog.specTag ~= C.state.specTag then
        return nil, "Blizzard's cooldown list is not ready yet."
    end
    local bars = { ess = {}, uti = {}, buf = {}, bar = {}, ext = {} }
    local count = 0
    for slot, list in pairs(bars) do
        for pass = 1, 2 do
            for i = 1, #catalog.order do
                local rec = catalog.records[catalog.order[i]]
                if rec and rec.bar == slot and (catalog.TAIL[rec.category] == true) == (pass == 2) then
                    list[#list + 1] = rec.key
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil, "Blizzard's cooldown list is empty." end
    return bars
end

-- Picker rows of one family; slot is the bar each entry lives on now.
function S.CooldownManagerCatalogEntries(family)
    Cold()
    wipe(homes)
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local keys = C.Resolve.Keys(slot, keyScratch)
        for j = 1, #keys do
            if homes[keys[j]] == nil then homes[keys[j]] = slot end
        end
    end
    local rows = C.Catalog.List(family)
    for i = 1, #rows do rows[i].slot = homes[rows[i].key] end
    return rows
end

function S.CooldownManagerRenderPreview(parent, slot, maxWidth, maxHeight)
    if not CDM.SLOT_INDEX[slot] or type(parent) ~= "table" then return nil end
    Cold()
    return C.Preview.Render(parent, slot, maxWidth, maxHeight)
end
function S.CooldownManagerReleasePreview(parent)
    C.Preview.Release(parent)
end
function S.CooldownManagerSimulate(on)
    return C.Preview.Simulate(on)
end
-- The options page keeps every bar visible while it is open. A request made
-- while the module is off is kept and applies once it is enabled; the
-- result says whether the preview runs now.
function S.CooldownManagerSetPreview(on)
    on = on == true
    if on and NS.IsCombatLocked() then return false end
    if optionsPreview ~= on then
        optionsPreview = on
        if M.active then ApplyPreview() end
    end
    return M.active == true or not on
end

-- Moves with every Blizzard catalog rebuild; the page's tile memo keys on it.
function S.CooldownManagerGeneration() return C.Catalog.generation end

-- The page asks several times per repaint: the client is read at most once
-- per frame (catalog events keep the state current while the module runs).
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

function S.CooldownManagerStatus()
    if not M.active then return nil end
    local mode, reason = C.Native.Mode()
    local text = S.Text(mode == 2 and "Blizzard's cooldown bars keep running invisibly." or "Blizzard's cooldown bars are off.")
    if reason then text = text .. " " .. reason end
    if not C.Catalog.Ready() then text = text .. " " .. S.Text("Waiting for Blizzard's cooldown data.") end
    return text
end

function S.CooldownManagerPlaySound(value)
    return C.Alerts.Play(value, true)
end

local offsetScratch = {}
-- Size of a bar's content as the layout will draw it. Cooldown bars count
-- their shown icons; aura bars reserve every entry within maxIcons, player
-- entries first and target-row entries (Auras.TargetRow) from a new line,
-- as Layout.PlaceAuras draws them.
local function Extent(view, plan)
    local list = plan.entries
    if plan.kind == 1 then
        local n, preview = 0, C.state.preview
        for i = 1, #list do
            local entry = list[i]
            if entry.icon and (preview or not entry.hidden) then n = n + 1 end
        end
        return C.Layout.Offsets(view, n, offsetScratch)
    end
    local cap = view.maxIcons
    if type(cap) ~= "number" or cap <= 0 then cap = #list end
    local n1, n2 = 0, 0
    for i = 1, #list do
        if n1 + n2 >= cap then break end
        if C.Auras.TargetRow(list[i]) then
            n2 = n2 + 1
        else
            n1 = n1 + 1
        end
    end
    local w, h, sp, per, vertical = C.Layout.Metrics(view)
    -- Fixed places on one line keep target entries on that line (Layout.PlaceAuras).
    local _, ordered, split = C.Layout.FixedAuras(view, list)
    if ordered or split then n1, n2 = n1 + n2, 0 end
    local lines = ceil(n1 / per) + ceil(n2 / per)
    if lines == 0 then return w, h end
    local along, across = w, h
    if vertical then along, across = h, w end
    local full = n1 > n2 and n1 or n2
    if full > per then full = per end
    local extent, depth = full * along + (full - 1) * sp, lines * across + (lines - 1) * sp
    if vertical then return depth, extent end
    return extent, depth
end

-- Grow direction and orientation move the growth-edge anchor. The new x/y
-- keep the bar's center where it is now (free bars that are shown only).
Convert = function(slot, grow, vertical, anyAnchor)
    local keys = KEYS[slot]
    if not keys then return nil end
    local values = {}
    if grow ~= nil and keys.grow then values[keys.grow] = grow end
    if vertical ~= nil and keys.vertical then values[keys.vertical] = vertical end
    local view, bar, plan = C.views[slot], C.bars[slot], C.plans[slot]
    if not (M.active and view and bar and bar.shown and plan and (anyAnchor or C.Layout.Free(slot)) and UIParent) then return values end
    local left, bottom, w, h = bar.frame:GetRect()
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    if not (Finite(left) and Finite(bottom) and Finite(w) and Finite(h) and Finite(uiW) and Finite(uiH)) then return values end
    local oldGrow, oldVertical = view.grow, view.vertical
    if grow ~= nil then view.grow = grow end
    if vertical ~= nil then view.vertical = vertical end
    local nw, nh = Extent(view, plan)
    local point = C.Layout.Point(view)
    view.grow, view.vertical = oldGrow, oldVertical
    local dx, dy = K.EdgeOffset(point, nw, nh)
    values[keys.x], values[keys.y] = Clamp(keys.x, left + w / 2 - uiW / 2 + dx), Clamp(keys.y, bottom + h / 2 - uiH / 2 + dy)
    return values
end
function S.CooldownManagerConvertGrow(slot, grow)
    if grow ~= 1 and grow ~= 2 then return nil end
    return Convert(slot, grow, nil)
end
function S.CooldownManagerConvertVertical(slot, vertical)
    return Convert(slot, nil, vertical == true)
end
-- The Essential bar riding Blizzard's bar after an attach change counts
-- its x/y from that bar: turning free it keeps its place as an offset from
-- it (zero when a rectangle is unreadable). The flag travels with the
-- values, so SyncViewerOffset finds nothing to convert on that Refresh.
local function RideAnchor(values, anchor)
    local view = C.views.ess
    if not (M.active and view) then return end
    local old = view.anchor
    view.anchor = anchor
    local rides = C.Layout.RidesViewer("ess") == true
    view.anchor = old
    values.essOnViewer = rides
    if not rides then return end
    local keys = KEYS.ess
    values[keys.x], values[keys.y] = 0, 0
    local bar = C.bars.ess
    local vx, vy = C.Layout.ViewerPoint(view)
    if not (vx and bar and bar.shown) then return end
    local left, bottom, w, h = bar.frame:GetRect()
    if not (Finite(left) and Finite(bottom) and Finite(w) and Finite(h)) then return end
    local point = C.Layout.Point(view)
    local x = point == "LEFT" and left or point == "RIGHT" and left + w or left + w / 2
    local y = point == "TOP" and bottom + h or point == "BOTTOM" and bottom or bottom + h / 2
    values[keys.x], values[keys.y] = Clamp(keys.x, x - vx), Clamp(keys.y, y - vy)
end
-- Attach changes keep the bar on screen: to Free, the x/y that hold its
-- current place; to a bar or unit frame, a zero offset from that anchor.
function S.CooldownManagerConvertAnchor(slot, anchor)
    local keys = KEYS[slot]
    if not keys or type(anchor) ~= "number" then return nil end
    local values
    if anchor == 1 then
        values = Convert(slot, nil, nil, true) or {}
    else
        values = { [keys.x] = 0, [keys.y] = 0 }
    end
    values[keys.anchor] = anchor
    if slot == "ess" then RideAnchor(values, anchor) end
    return values
end
function S.CooldownManagerMovable(slot) return C.Layout.Movable(slot) end

-- MSUF resolves its "anchor to cooldown bars" targets through this.
NS.CooldownManager = NS.CooldownManager or {}
NS.CooldownManager.GetAnchorFrame = function(viewerName) return C.Native.AnchorFrame(viewerName) end

S.Install(ID, M)



