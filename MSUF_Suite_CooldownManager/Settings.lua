local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Settings in and out. Refresh runs on every setting change
-- (slider ticks included): the reader turns the flat settings into per-bar
-- views in place, bumps the generation of each group that changed and marks
-- only the work that setting needs (the dirty mask, Flush.lua). Settings go
-- the other way once: Blizzard's bar positions on the first run, the
-- defaults reset of an older profile, and the Essential bar's x/y when it
-- starts or stops riding Blizzard's bar.
local M = C.M
local CDM = NS.CDM
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local ID = "cooldownManager"
local pairs, type, next = pairs, type, next
local wipe = C.wipe
local K = C.Const
local KIND, AURA_KINDS = K.KIND, K.AURA_KINDS
local Flush = C.Flush
local dirty, sync, style, behavior, visible = Flush.dirty, Flush.sync, Flush.style, Flush.behavior, Flush.visible
local Settings = {}
C.Settings = Settings

------------------------------------------------------------------ settings work
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
Work({ "cooldownFixed" }, { layout = true })
Work({ "overflow", "maxIcons" }, { resolve = true })
Work({ "shareContents" }, { resolve = true })
Work({ "cooldownDuration" }, { layout = true, style = true, behavior = true, index = true, overlay = true })
Work({ "laterPerRow", "laterSize" }, { layout = true, style = true })
Work({ "size", "height", "barWidth", "barHeight" }, { layout = true, flow = true, style = true })
Work({ "on" }, { layout = true, resolve = true, visible = true })
Work({ "kind" }, { layout = true, flow = true, resolve = true, style = true, behavior = true, bar = true })
Work({ "zoom", "border", "borderColor", "borderClass", "swipeAlpha", "edge", "cdText", "cdSize", "stackSize", "stackPos",
    "keybindSize", "keybindPos", "keybindBadge", "keybindBackground", "keybindBorder", "keybindPadding", "textTop" }, { style = true })
-- Counts: the icon's text switch (style), the count read back when shown
-- again (behavior) and use-count routing (index).
Work({ "stackText" }, { style = true, behavior = true, index = true })
Work({ "keybind" }, { style = true, keybind = true })
Work({ "desat", "cdAlpha", "readyAlpha", "hideReady", "rangeColor", "bling" }, { behavior = true })
-- The glow look also styles aura glows: aura buttons of aura bars and the
-- overlays of cooldown bars restyle through their diffed sync.
Work({ "glowStyle", "glowColor", "glowTint" }, { behavior = true, restyle = true })
Work({ "range", "usable", "procGlow", "readyGlow", "readyResources", "fullChargeGlow", "charges", "assist" }, { behavior = true, index = true })
Work({ "chargeSwipe", "chargeEdge" }, { style = true, behavior = true })
Work({ "showAura" }, { behavior = true, index = true, overlay = true })
Work({ "showMissing", "keepSlots", "auraGlow", "pandemic" }, { behavior = true, aura = true })
Work({ "vis", "hideMounted", "hideVehicle", "alpha", "oocAlpha" }, { visible = true })
Work({ "tooltips" }, { restyle = true })
Work({ "strata" }, { restyle = true, visible = true })
Work({ "layer" }, { layout = true, aura = true, restyle = true })
Work({ "barTexture", "barColor", "barClass", "barBgAlpha", "barIcon", "barIconSide", "barName", "barTime", "barFill",
    "barStacks", "barStackMax", "barStackEach", "barStackMarks", "barStackColorAt", "barStackColor", "barChargeSegments",
    "barChargeDim" }, { bar = true, style = true, behavior = true })
Work({ "barStacks" }, { index = true })
Work({ "name" }, { named = true })
-- A fresh view (first read, activation) does everything once.
local FRESH = { layout = true, style = true, behavior = true, index = true, visible = true, resolve = true, named = true }
C.Diagnostics.SettingWork = WORK
-- A bar setting nobody listed above does all of it, so a new setting is
-- never silently ignored (the action bars do the same).
local EVERYTHING = {}
for _, work in pairs(WORK) do
    for flag in pairs(work) do EVERYTHING[flag] = true end
end
local COLOR = { borderColor = { "borderR", "borderG", "borderB" }, glowColor = { "glowR", "glowG", "glowB" },
    rangeColor = { "rangeR", "rangeG", "rangeB" }, barColor = { "barR", "barG", "barB" } }
local OUTLINE = { "OUTLINE", "THICKOUTLINE", "" }
-- Globals whose change re-registers events (the assisted icon's sources and
-- the keybind watch); its size and place only repaint it (Refresh does).
local EVENT_GLOBALS = { "assistIcon", "assistIconKeybind", "assistIconGCD", "keybindStable" }
local PLACE_GLOBALS = { "assistIconSize", "assistIconX", "assistIconY" }
local CHANNEL = { "Master", "SFX", "Dialog" }

-- Per slot: suffixes, their keys and work records as arrays (built-in bars
-- have a fixed kind and title, so those two rules are skipped).
local SUFFIX, KEY, WORKS = {}, {}, {}
for i = 1, #SLOTS do
    local def = SLOTS[i]
    local s, keys, w = {}, {}, {}
    for suffix, key in pairs(KEYS[def.key]) do
        if not (def.builtin and (suffix == "kind" or suffix == "name")) then
            s[#s + 1], keys[#keys + 1], w[#w + 1] = suffix, key, WORK[suffix] or EVERYTHING
        end
    end
    SUFFIX[i], KEY[i], WORKS[i] = s, keys, w
end

------------------------------------------------------------------ reading settings
local hit = {}
local seenHex = {}
local lastLists, lastSpells

-- Fonts and text colors (the result: their change restyles every bar), the
-- GCD display, the combat glow and the sound options.
function Settings.ReadGlobals(config, all)
    local state = C.state
    local text = all
    local raid = config.raidEssentials ~= false
    if all or state.raidEssentials ~= raid then state.raidEssentials, dirty.resolve = raid, true end
    local font, flags = S.ResolveFont(config.font) or S.GlobalFontPath(), OUTLINE[config.fontOutline] or "OUTLINE"
    if state.fontEpoch ~= _G.MSUF_FontApplyEpoch then
        state.fontEpoch = _G.MSUF_FontApplyEpoch
        text = true
    end
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
    if all or state.showGCD ~= gcd then state.showGCD, dirty.cooldowns, dirty.index = gcd, true, true end
    local glow = config.readyGlowCombat == true
    if all or state.readyGlowCombat ~= glow then state.readyGlowCombat, dirty.effects = glow, true end
    local allGlows = config.allGlowsCombat == true
    state.pressFeedback = config.pressFeedback == true
    for i = 1, #EVENT_GLOBALS do
        local key = EVENT_GLOBALS[i]
        if state[key] ~= config[key] then
            state[key], dirty.events = config[key], true
            if key == "keybindStable" then dirty.keybinds = true end
        end
    end
    for i = 1, #PLACE_GLOBALS do
        local key = PLACE_GLOBALS[i]
        state[key] = config[key]
    end
    local stocked = config.potionStockIcon == true
    if all or state.potionStockIcon ~= stocked then state.potionStockIcon, dirty.cooldowns = stocked, true end
    if all or state.allGlowsCombat ~= allGlows then
        state.allGlowsCombat, dirty.effects = allGlows, true
        for i = 1, #SLOTS do sync[SLOTS[i].key] = true end
    end
    local mute, channel = config.muteSounds == true, CHANNEL[config.soundChannel] or "Master"
    if all or state.muteSounds ~= mute or state.soundChannel ~= channel then
        state.muteSounds, state.soundChannel, dirty.alerts = mute, channel, true
    end
    -- Text styled outside the bars (the assisted icon) follows this count.
    if text then state.textGen = (state.textGen or 0) + 1 end
    return text
end

-- Views are rebuilt in place. Each changed setting adds its work (WORK) to
-- the slot's hit set; the set then bumps generations and marks work once.
-- A position drag or an opacity slider never syncs structure, a behavior
-- tick rebuilds the routing index only when membership can change.
function Settings.ReadViews(config, all, text)
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
            local kind = view.kind
            if kind ~= KIND.COOLDOWN and kind ~= KIND.AURA_ICON and kind ~= KIND.AURA_BAR then
                view.kind = KIND.COOLDOWN
            end
            if hit.named then
                local name = view.name
                view.title = type(name) == "string" and name ~= "" and name or S.Text(def.title)
            end
        end
        if next(hit) ~= nil then
            local aura = AURA_KINDS[view.kind] == true
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
function Settings.DecodeData(config)
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

------------------------------------------------------------------ first-run capture
local captureWait, pendingCapture = false, nil
local captureConfig
local function PersistCapture()
    local values = pendingCapture
    if not values or not M.active or M.config ~= captureConfig or S.Config(ID) ~= captureConfig then
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
    local rules = NS.SuiteCatalog[ID].rules
    if (tonumber(config.defaultsVersion) or 0) < 1 then
        local keep = CDM.DEFAULTS_KEEP
        for key, rule in pairs(rules) do
            if not keep[key] and values[key] == nil and config[key] ~= rule.default then values[key] = rule.default end
        end
    else
        local version = tonumber(config.defaultsVersion) or 0
        local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
        local center = version < 3 and Finite(uiW) and Finite(uiH)
        for i = 1, #SLOTS do
            local def = SLOTS[i]
            local keys = KEYS[def.key]
            local anchor = values[keys.anchor] or config[keys.anchor]
            if anchor ~= K.ANCHOR.FREE then
                if version < 2 and values[keys.x] == nil then values[keys.x], values[keys.y] = 0, 0 end
            elseif center and values[keys.x] == nil then
                if def.custom and config[keys.on] ~= true then
                    -- Unused custom bars start in the middle of the screen.
                    values[keys.x], values[keys.y] = 0, 0
                else
                    -- Free x/y used to count from the same point of UIParent.
                    pointProbe.kind = config[keys.kind] or def.kind or KIND.COOLDOWN
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
    local free = C.Convert("ess", nil, nil, true)
    if free and free[keys.x] ~= nil then return free[keys.x], free[keys.y] end
    local view = C.views.ess
    if not view then return nil end
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
function Settings.SyncViewerOffset()
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
    C_Timer.After(0, PersistCapture)
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
        C_Timer.After(0, PersistCapture)
    end
    C.Native.Apply()
end

-- Activation: Blizzard's layout is read before the takeover touches its
-- bars; on a fresh login the capture waits for Blizzard's data.
function Settings.BeginCapture(config)
    if captureConfig == config then return end
    captureConfig = config
    captureWait, pendingCapture = false, nil
    if config.captured ~= true or Outdated(config) then
        if C.Catalog.Ready() then
            Capture()
        else
            captureWait = true
        end
    end
end
function Settings.CaptureWaiting() return captureWait end
-- A waiting capture runs once Blizzard's data is in, never under lockdown.
function Settings.CaptureWhenReady(locked)
    if captureWait and C.Catalog.Ready() and not locked then Capture() end
end
-- Combat end: a waiting capture, and settings combat kept from being written.
function Settings.CaptureAfterCombat()
    if captureWait and C.Catalog.Ready() then Capture() end
    if pendingCapture then PersistCapture() end
end
function Settings.ForgetCapture()
    captureConfig = nil
    captureWait, pendingCapture = false, nil
end
