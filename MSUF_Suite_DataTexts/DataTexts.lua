local _, P = ...
local NS, S = P.NS, P.Suite
local Appearance = P.Appearance
local GoldLedger = P.GoldLedger
local Standard = P.DataTextStandard
local Extra = P.DataTextSources
local Actions = P.DataTextActions
local Visibility, NativeBagBar = P.DataTextBarVisibility, P.DataTextNativeBagBar
local healthBars, GateHealth = Visibility.healthBars, Visibility.GateHealthBar
local M = P.DataTexts
local Bars, BarKeys = P.DataTextBars, P.DataTextBarKeys
local ID = "dataTexts"
local IN_COMBAT = { inCombat = true }
local SLOT_COUNT = P.SLOT_COUNT
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local Snap, ApplyColor = Appearance.Snap, Appearance.Color
local SOURCES, SAMPLED, INTERVAL = Standard.SOURCES, Standard.SAMPLED, Standard.INTERVAL
local READER, EVENT_SOURCES = Standard.READER, Standard.EVENT_SOURCES
local NO_VALUE = P.NO_VALUE
local floor = math.floor
local Finite = S.Finite
local VISIBILITY, LAYOUT, DOCK = NS.DataTextVisibility, NS.DataTextLayout, NS.DataTextDock
-- Rebind alternates between two active-source sets and reuses its event set.
local activeSetA, activeSetB, wantedEvents = {}, {}, {}
local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function Format(key)
    if Extra.Has(key) then return Extra.Format(key) end
    return Standard.Format(key)
end

local function Visible(bar)
    if not bar.frame:IsVisible() then return false end
    if S.editMode then return true end
    if M.config[bar.visibilityKey] == VISIBILITY.MOUSEOVER then return bar.hover == true end
    return bar.frame:GetAlpha() > 0
end

local function Display(label, value, severity, style, key, alternate)
    if key == "bags" and style.bagsPercent then value = alternate or NO_VALUE end
    local valueColor = severity == "bad" and style.warningColor or style.valueColor
    if style.showLabels and (key ~= "clock" or style.clockLabel) then
        local separator = style.labelColon and ": " or " "
        return label .. separator .. value,
            "|cff" .. style.labelColor .. label .. separator .. "|r|cff" .. valueColor .. value .. "|r"
    end
    return value, "|cff" .. valueColor .. value .. "|r"
end

local function Layout(bar)
    P.DataTextGeometry.Layout(bar, M.config, Extra)
end

-- force repaints unchanged values: a bar that just became visible still
-- shows whatever it displayed before it was hidden.
function M:UpdateSource(key, force)
    if not self.activeSources or not self.activeSources[key] then return end
    local label, value, severity, alternate = Format(key)
    local record = self.values[key]
    if record and not force and record.label == label and record.value == value
        and record.severity == severity and record.alternate == alternate then
        return
    end
    if not record then
        record = {}
        self.values[key] = record
    end
    record.label, record.value, record.severity, record.alternate = label, value, severity, alternate
    for _, bar in pairs(self.bars) do
        if Visible(bar) then
            local relayout = false
            if key == "bags" and bar.badge:IsShown() then
                bar.badge.text = Display(label, value, severity, bar.style, key, alternate)
            end
            for i = 1, SLOT_COUNT do
                local button = bar.slots[i]
                if button.source == key then
                    local text, display = Display(label, value, severity, bar.style, key, alternate)
                    if button.display ~= display then
                        button.label:SetText(display)
                        button.text, button.display = text, display
                        relayout = true
                    end
                    Extra.Paint(button)
                end
            end
            if relayout and self.config[bar.layoutKey] == LAYOUT.FIT then Layout(bar) end
        end
    end
end

local function NextClock()
    local stamp = S.ReadInfoSource("clockStamp")
    return Finite(stamp) and 60 - floor(stamp) % 60 or 60
end

local function NextSample(key, now)
    return now + ((key == "clock" or key == "date") and NextClock() or INTERVAL[key])
end

local TickDataTexts
function M:Schedule()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    local now, soonest = GetTime(), nil
    for key in pairs(self.activeSources or {}) do
        if SAMPLED[key] then
            local due = self.due[key] or now
            if not soonest or due < soonest then soonest = due end
        end
    end
    if soonest then self.timer = S.ScheduleDataTick("datatexts", math.max(.05, soonest - now), TickDataTexts) end
end

function M:Tick()
    self.timer = nil
    local now = GetTime()
    for key in pairs(self.activeSources or {}) do
        if SAMPLED[key] and (self.due[key] or 0) <= now + .001 then
            self:UpdateSource(key)
            self.due[key] = NextSample(key, now)
        end
    end
    self:Schedule()
end

TickDataTexts = function() M:Tick() end

local invalidated, invalidationMark = {}, 0
local function Invalidate(key)
    local raw = READER[key] or key
    if invalidated[raw] ~= invalidationMark then
        S.InvalidateSharedData(raw)
        invalidated[raw] = invalidationMark
    end
end

local function EnteredWorld(self)
    invalidationMark = invalidationMark + 1
    for key in pairs(self.activeSources or {}) do Invalidate(key) end
    for key in pairs(self.activeSources or {}) do self:UpdateSource(key) end
end

-- Visibility modes and load conditions run as state drivers, so combat
-- itself needs no handler. Combat edges only release and restore the secure
-- buttons (Actions.lua) and store the gold ledger.
local function CombatEdge(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Actions.Release()
        return
    end
    if self.config.trackAltGold then GoldLedger.Capture() end
    -- A Hearthstone looted or learned in combat is offered right away.
    if Extra.hearthDirty then
        Extra.hearthDirty = nil
        Extra.HearthsMayHaveChanged()
    end
    Actions.Resume()
end

local function OnEvent(self, event, unit)
    if event == "PLAYER_XP_UPDATE" and unit and unit ~= "player" then return end
    Extra.Changed(self, event)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit == "player" then
            for i = 1, #healthBars do GateHealth(healthBars[i]) end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if self.config.trackAltGold then GoldLedger.Capture() end
        self:UpdateVisibility()
        EnteredWorld(self)
        return
    end
    if event == "PLAYER_MONEY" and self.config.trackAltGold then GoldLedger.Capture() end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "HOUSE_PLOT_ENTERED"
        or event == "HOUSE_PLOT_EXITED" then
        self:UpdateVisibility()
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        CombatEdge(self, event)
        return
    end
    local keys = EVENT_SOURCES[event]
    local active = self.activeSources
    if not keys or not active then return end
    invalidationMark = invalidationMark + 1
    for i = 1, #keys do
        if active[keys[i]] then Invalidate(keys[i]) end
    end
    for i = 1, #keys do
        local key = keys[i]
        if active[key] then
            self:UpdateSource(key)
            if key == "coordinates" then
                self.due[key] = GetTime() + INTERVAL.coordinates
                self:Schedule()
            end
        end
    end
end

local function WantBarEvents(self)
    local c = self.config
    for _, i in ipairs(self.barIDs) do
        local keys = BarKeys(i)
        local enabled, housing = c[keys.enabled], c[keys.housing]
        if enabled and c[keys.injured] then
            wantedEvents.UNIT_HEALTH = true
            wantedEvents.UNIT_MAXHEALTH = true
        end
        if enabled and (c[keys.instance] or housing) then
            wantedEvents.PLAYER_ENTERING_WORLD = true
            wantedEvents.ZONE_CHANGED_NEW_AREA = true
        end
        if enabled and housing then
            wantedEvents.HOUSE_PLOT_ENTERED = true
            wantedEvents.HOUSE_PLOT_EXITED = true
        end
    end
end

local function SyncEvents(self, active)
    Clear(wantedEvents)
    Extra.WantedEvents(active, wantedEvents)
    for event, keys in pairs(EVENT_SOURCES) do
        for i = 1, #keys do
            if active[keys[i]] then
                wantedEvents[event] = true
                break
            end
        end
    end
    if next(active) or self.config.trackAltGold then wantedEvents.PLAYER_ENTERING_WORLD = true end
    if self.config.trackAltGold then
        wantedEvents.PLAYER_MONEY = true
        wantedEvents.PLAYER_REGEN_ENABLED = true
    end
    WantBarEvents(self)
    for event in pairs(self.events) do
        if not wantedEvents[event] then
            self.context:RemoveEvent(event)
            self.events[event] = nil
        end
    end
    for event in pairs(wantedEvents) do
        if not self.events[event] then
            self.context:Event(event, OnEvent, IN_COMBAT,
                (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and "player" or nil)
            self.events[event] = true
        end
    end
end

-- Recomputes which sources visible bars show. Sampled sources that stay
-- active keep their deadlines, so the shared timer is re-armed only when
-- the sampled set changes.
function M:Rebind()
    if not self.active or self.styling then return end
    local previous = self.activeSources
    local active = previous == activeSetA and activeSetB or activeSetA
    Clear(active)
    for _, bar in pairs(self.bars) do
        if Visible(bar) then
            if bar.badge:IsShown() then active.bags = true end
            for i = 1, SLOT_COUNT do
                local key = bar.slots[i].source
                if key then active[key] = true end
            end
        end
    end
    self.activeSources = active
    Extra.PruneConfigured(self, SOURCES)
    Extra.Rebind(self)
    SyncEvents(self, active)
    local now, sampledChanged = GetTime(), false
    for key in pairs(active) do
        self:UpdateSource(key, true)
        if SAMPLED[key] and not (previous and previous[key]) then
            self.due[key] = NextSample(key, now)
            sampledChanged = true
        end
    end
    if previous then
        for key in pairs(previous) do
            if not active[key] then
                self.values[key] = nil
                if SAMPLED[key] then
                    self.due[key] = nil
                    sampledChanged = true
                end
            end
        end
    end
    if sampledChanged then self:Schedule() end
end

-- Bar visibility (modes, load conditions, health gate): Visibility.lua.
function M:UpdateVisibility()
    Visibility.Apply(self)
    self:Rebind()
end

local function StyleSlot(button, style, font)
    button.label:SetText(NO_VALUE)
    S.SetStyledFont(button.label, font, style.fontSize, OUTLINES[style.textOutline] or "OUTLINE",
        style.fontRendering, style.fontShadow, style.fontShadowOpacity, style.fontShadowDistance)
    button.label:SetJustifyH(ALIGN[style.textAlign] or "CENTER")
    button.label:SetTextColor(1, 1, 1)
end

-- The screen edge each docked bar snaps to.
local DOCK_POINTS = { [DOCK.TOP] = "TOP", [DOCK.BOTTOM] = "BOTTOM", [DOCK.LEFT] = "LEFT", [DOCK.RIGHT] = "RIGHT" }
local function PlaceBar(bar, c)
    local prefix, frame = bar.prefix, bar.frame
    local pixel = S.PixelUnit() or 1
    bar.pixelUnit = pixel
    frame:ClearAllPoints()
    local point = NS.DataTextPoints[c[prefix .. "Point"]] or "BOTTOM"
    local dock = c[prefix .. "Dock"] or DOCK.FREE
    if dock ~= DOCK.FREE then point = DOCK_POINTS[dock] end
    frame:SetPoint(point, UIParent, point, Snap(c[prefix .. "X"], pixel), Snap(c[prefix .. "Y"], pixel))
    bar.vertical = c[prefix .. "Vertical"] == true
    local span = bar.vertical and UIParent:GetHeight() or UIParent:GetWidth()
    bar.length = Snap(c[prefix .. "FullScreen"] and span or c[bar.widthKey], pixel)
    local thickness = Snap(c[bar.heightKey], pixel)
    frame:SetSize(bar.vertical and thickness or bar.length, bar.vertical and bar.length or thickness)
    if dock ~= DOCK.FREE then
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, point, 0, 0)
    end
end

local function BarStyle(c, index, vertical)
    local style = NS.DataTextEffectiveStyle(c, index)
    if style.valueClassColor then
        local _, class = UnitClass("player")
        style.valueColor = S.Public(class) and S.ClassHex(class) or style.valueColor
    end
    if vertical then style.bagBadge = false end
    return style
end

-- One place of a bar: its source (a built-in key or a bound additional
-- source), its scale, wheel and background.
local function RefreshSlot(button, c, index, slot, style, font)
    local block = "bar" .. index .. "Slot" .. slot
    local choice = c[block]
    local key = NS.DataTextSourceKeys[choice]
    button.extra = nil
    button.source, button.sourceIndex = SOURCES[key] and key or nil, choice
    if Extra.kinds[key] then
        key = Extra.Bind(button, c, index, slot, key)
        SOURCES[key] = true
    end
    button:SetScale((c[block .. "Scale"] or 100) / 100)
    button:EnableMouseWheel(button.bar.mouseEnabled ~= false and button.extra ~= nil
        and button.extra.kind == "audio")
    local alpha = c[block .. "Alpha"] or 0
    if alpha > 0 and not button.blockFill then
        button.blockFill = S.CreateTexture(button, nil, "BACKGROUND")
        button.blockFill:SetAllPoints(button)
    end
    if button.blockFill then
        ApplyColor(button.blockFill, c[block .. "Background"] or "101010", alpha / 100)
        button.blockFill:SetShown(alpha > 0)
    end
    Extra.Paint(button)
    button.text, button.display = nil, nil
    button:SetShown(button.source ~= nil)
    if button.source then StyleSlot(button, style, font) end
end

local function RefreshBar(index)
    local c = M.config
    local bar = Bars.Create(index)
    local frame, layer = bar.frame, c[bar.prefix .. "Layer"]
    local restored = S.ApplyOwnedLayer(frame, layer)
    S.ApplyOwnedChildLayer(bar.visual, frame, layer, 1, restored)
    S.ApplyOwnedChildLayer(bar.badge, frame, layer, 2, restored)
    PlaceBar(bar, c)
    bar.style = BarStyle(c, index, bar.vertical)
    Appearance.Paint(bar)
    local style = bar.style
    local font = S.ResolveFont(style.font) or S.GlobalFontPath()
    for slot = 1, SLOT_COUNT do
        local button = bar.slots[slot]
        S.ApplyOwnedChildLayer(button, frame, layer, 2, restored)
        RefreshSlot(button, c, index, slot, style, font)
    end
    Layout(bar)
    Visibility.Cache(c, bar)
end

function M:Refresh()
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return
    end
    if self.config.trackAltGold then GoldLedger.Capture() end
    self.styling = true
    Clear(self.values)
    Bars.ResetKeys()
    NS.SuiteCatalog.dataTexts.prepareConfig(self.config)
    self.barIDs = NS.DataTextBarIDs(self.config)
    Clear(self.presentIDs)
    for _, i in ipairs(self.barIDs) do self.presentIDs[i] = true end
    for i, bar in pairs(self.bars) do
        if not self.presentIDs[i] then
            Visibility.SetDriver(bar, nil)
            bar.frame:Hide()
            bar.visual:SetAlpha(1)
            for slot = 1, SLOT_COUNT do Bars.HideTooltip(bar.slots[slot]) end
            self.bars[i] = nil
            self.pool[#self.pool + 1] = bar
        end
    end
    for _, i in ipairs(self.barIDs) do
        if self.config[BarKeys(i).enabled] then RefreshBar(i) end
    end
    self.styling = false
    self:UpdateVisibility()
    Extra.PrepareHearths()
    NativeBagBar.Sync()
end

local function ScaleChanged(module)
    if NS.IsCombatLocked() then
        S.Queue(ID)
    else
        module:Refresh()
        module:RegisterMovers()
    end
end

function M:Enable()
    self:Refresh()
    NativeBagBar.Sync()
    self.context:Event("ADDON_LOADED", NativeBagBar.AddonLoaded, IN_COMBAT)
    self.context:Event("UI_SCALE_CHANGED", ScaleChanged)
    self.context:Event("DISPLAY_SIZE_CHANGED", ScaleChanged)
end

function M:Disable()
    Visibility.Release()
    Actions.Disable()
    Extra.Disable()
    NativeBagBar.Sync()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    for event in pairs(self.events) do
        self.context:RemoveEvent(event)
        self.events[event] = nil
    end
    self.activeSources = nil
    Clear(self.values)
    Clear(self.due)
    local owned = GameTooltip:GetOwner()
    for _, bar in pairs(self.bars) do
        Visibility.SetDriver(bar, nil)
        bar.frame:Hide()
        bar.visual:SetAlpha(1)
        if owned then
            for i = 1, SLOT_COUNT do Bars.HideTooltip(bar.slots[i]) end
        end
    end
end

-- The bars' MSUF Edit Mode movers (Movers.lua); the shared Edit Mode runtime
-- calls this method too.
function M:RegisterMovers()
    P.DataTextMovers.Register(self)
end

S.Install(ID, M)
