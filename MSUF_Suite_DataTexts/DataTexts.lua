local _, P = ...
local NS, S = P.NS, P.Suite
local Appearance = P.Appearance
local GoldLedger = P.GoldLedger
local Standard = P.DataTextStandard
local Extra = P.DataTextSources
local Actions = P.DataTextActions
local M = { bars = {}, pool = {}, barIDs = {}, presentIDs = {}, due = {}, values = {}, events = {} }
local ID = "dataTexts"
local SLOT_COUNT = 6
local BADGE = "Interface\\AddOns\\MSUF_Suite_DataTexts\\Media\\BagMedallion.tga"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local Snap, ApplyColor = Appearance.Snap, Appearance.Color
local SOURCES, SAMPLED, INTERVAL = Standard.SOURCES, Standard.SAMPLED, Standard.INTERVAL
local READER, EVENT_SOURCES = Standard.READER, Standard.EVENT_SOURCES
local NO_VALUE = P.NO_VALUE
local floor = math.floor
local Finite = S.Finite
local nativeBagBar, nativeBagBarWasShown, nativeBagDriver, nativeBagHooked
local nativeBagShowHooks = setmetatable({}, { __mode = "k" })
local healthCurve
-- Rebind alternates between two active-source sets and reuses its event set.
local activeSetA, activeSetB, wantedEvents = {}, {}, {}
-- Per-bar setting names, built once so event paths never concatenate keys.
local BAR_KEYS = {}
local function BarKeys(i)
    if BAR_KEYS[i] then return BAR_KEYS[i] end
    local prefix = "bar" .. i
    BAR_KEYS[i] = {
        prefix = prefix, enabled = prefix .. "Enabled", visibility = prefix .. "Visibility",
        injured = prefix .. "LoadCondShowWhenInjured", instance = prefix .. "LoadCondHideInInstance",
        housing = prefix .. "LoadCondHideInHousing",
    }
    return BAR_KEYS[i]
end

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function InInstance()
    local inside = IsInInstance()
    return inside == true or inside == 1
end

local function InHousing()
    return C_Housing.IsInsideHouseOrPlot() == true
end

-- Full health maps to 0 (hidden), anything less to 1 (shown). Retail and
-- WoW Forever both have UnitHealthPercent with curve support.
local function HealthCurve()
    if not healthCurve then
        healthCurve = C_CurveUtil.CreateCurve()
        healthCurve:SetType(Enum.LuaCurveType.Step)
        healthCurve:AddPoint(0, 1)
        healthCurve:AddPoint(1, 0)
    end
    return healthCurve
end

local function RefreshHealthAlpha(bar)
    if not bar or not bar.visual then return end
    if S.editMode or not M.config[bar.injuredKey] then
        bar.visual:SetAlpha(1)
        return
    end
    -- Health can be secret. The curve result goes straight into SetAlpha
    -- without Lua comparison, arithmetic or string conversion.
    bar.visual:SetAlpha(UnitHealthPercent("player", false, HealthCurve()))
end

-- Retail and Forever keep backpack and bag slots on a separate BagsBar.
-- The bag DataText is the visible entry point while this option is on;
-- Blizzard still owns item movement and the actual container windows.
local function SyncNativeBagBar()
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return
    end
    local frame = _G.BagsBar
    if M.active and M.config and M.config.hideBlizzardBagBar == true and frame then
        if nativeBagBar ~= frame then
            nativeBagBar = frame
            nativeBagBarWasShown = frame:IsShown() == true
        end
        if not nativeBagDriver then
            RegisterStateDriver(frame, "visibility", "hide")
            nativeBagDriver = true
        end
        frame:Hide()
        if not nativeBagShowHooks[frame] then
            frame:HookScript("OnShow", SyncNativeBagBar)
            nativeBagShowHooks[frame] = true
        end
        -- WoW Forever only: its mouse-and-keyboard action bar setup shows the bag bar.
        if not nativeBagHooked and _G.MainActionBar_InitializeMKB then
            hooksecurefunc("MainActionBar_InitializeMKB", SyncNativeBagBar)
            nativeBagHooked = true
        end
    elseif nativeBagBar then
        if nativeBagDriver then UnregisterStateDriver(nativeBagBar, "visibility") end
        nativeBagDriver = nil
        local restoreFrame, wasShown = nativeBagBar, nativeBagBarWasShown
        nativeBagBar, nativeBagBarWasShown = nil, nil
        if wasShown then restoreFrame:Show() end
    end
end

local function Format(key)
    if Extra.Has(key) then return Extra.Format(key) end
    return Standard.Format(key)
end

local function Tooltip(button)
    if not M.active or not button.source then return end
    local title = S.Text(NS.DataTextSources[button.sourceIndex] or "")
    if button.extra then
        Actions.Tooltip(button, title)
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, 1, .82, .36)
    if Standard.TooltipLines(GameTooltip, button, M.config) then Actions.GoldTooltip(GameTooltip) end
    GameTooltip:Show()
end

local function HideTooltip(button)
    Actions.Leave(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

-- Built-in places open Blizzard windows out of combat; Actions.lua decides
-- for the additional sources.
local function Click(button, mouse)
    if not button.source then return end
    if button.extra then
        Actions.Click(button, mouse or "LeftButton")
    elseif not NS.IsCombatLocked() then
        Standard.Click(button)
    end
end

-- Mouseover bars: only a real hover change rebinds the sampled sources.
local function SetHover(bar, hovered)
    if M.config[bar.visibilityKey] ~= 4 or bar.hover == hovered then return end
    bar.hover = hovered
    bar.frame:SetAlpha(hovered and 1 or 0)
    M:Rebind()
end

local function SlotEnter(button)
    SetHover(button.bar, true)
    Actions.hovered = button
    Actions.Attach(button)
    Tooltip(button)
end

local function SlotLeave(button)
    -- The secure overlay over this place took the pointer: still hovered.
    if Actions.Covers(button) then return end
    if Actions.hovered == button then Actions.hovered = nil end
    HideTooltip(button)
    if not button.bar.frame:IsMouseOver() then SetHover(button.bar, false) end
end
Actions.enter, Actions.leave = SlotEnter, SlotLeave

local function BarEnter(frame) SetHover(frame.bar, true) end

local function BarLeave(frame)
    if not frame:IsMouseOver() then SetHover(frame.bar, false) end
end

-- A bar that hides takes the secure overlay and popup of its places along.
local function BarShownChanged(frame)
    if not frame:IsVisible() then
        local owner = Actions.Owner()
        if owner and owner.bar.frame == frame then Actions.Detach() end
        local popup = Actions.popup
        if popup and popup.owner and popup.owner.bar.frame == frame then Actions.ClosePopup() end
    end
    if not M.styling then M:Rebind() end
end

local function CreateEdge(frame, layer, from, to)
    local texture = S.CreateTexture(frame, nil, layer)
    texture:SetPoint(from)
    texture:SetPoint(to)
    return texture
end

-- Places are ordinary buttons (no secure template), so a bar may move,
-- resize, show and hide in combat. Actions.lua runs protected clicks.
local function CreateSlot(bar, slot)
    local button = S.CreateFrame("Button", nil, bar.visual)
    button.bar, button.slot = bar, slot
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", Click)
    button:SetScript("OnEnter", SlotEnter)
    button:SetScript("OnLeave", SlotLeave)
    -- Only volume places take the wheel; the others leave it to the camera.
    button:SetScript("OnMouseWheel", Actions.Wheel)
    button:EnableMouseWheel(false)
    local text = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", button, "LEFT", 5, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    button.label = text
    return button
end

local function AssignBarKeys(bar, index)
    local keys = BarKeys(index)
    local prefix = keys.prefix
    bar.index, bar.prefix = index, prefix
    bar.enabledKey, bar.visibilityKey = keys.enabled, keys.visibility
    bar.layoutKey, bar.widthKey, bar.heightKey = prefix .. "Layout", prefix .. "Width", prefix .. "Height"
    bar.injuredKey, bar.instanceKey, bar.housingKey = keys.injured, keys.instance, keys.housing
end

local function CreateBadge(bar)
    local badge = S.CreateFrame("Button", nil, bar.visual)
    badge.bar, badge.source, badge.sourceIndex, badge.text = bar, "bags", 3, Standard.LABELS.bags
    badge:RegisterForClicks("LeftButtonUp")
    badge:SetScript("OnClick", Click)
    badge:SetScript("OnEnter", SlotEnter)
    badge:SetScript("OnLeave", SlotLeave)
    local badgeArt = S.CreateTexture(badge, nil, "OVERLAY")
    badgeArt:SetAllPoints(badge)
    badgeArt:SetTexture(BADGE)
    bar.badge = badge
end

local function CreateBar(index)
    if M.bars[index] then return M.bars[index] end
    local recycled = table.remove(M.pool)
    if recycled then
        AssignBarKeys(recycled, index)
        recycled.hover = false
        M.bars[index] = recycled
        return recycled
    end
    local frame = S.CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    local visual = S.CreateFrame("Frame", nil, frame)
    visual:SetAllPoints(frame)
    local background = S.CreateTexture(visual, nil, "BACKGROUND")
    background:SetAllPoints(visual)
    local gradient = S.CreateTexture(visual, nil, "BACKGROUND")
    gradient:SetAllPoints(visual)
    gradient:SetTexture("Interface\\Buttons\\WHITE8X8")
    local top = CreateEdge(visual, "BORDER", "TOPLEFT", "TOPRIGHT")
    top:SetHeight(1)
    local bottom = CreateEdge(visual, "BORDER", "BOTTOMLEFT", "BOTTOMRIGHT")
    bottom:SetHeight(1)
    local left = CreateEdge(visual, "BORDER", "TOPLEFT", "BOTTOMLEFT")
    left:SetWidth(1)
    local right = CreateEdge(visual, "BORDER", "TOPRIGHT", "BOTTOMRIGHT")
    right:SetWidth(1)
    local accent = CreateEdge(visual, "ARTWORK", "BOTTOMLEFT", "BOTTOMRIGHT")
    accent:SetHeight(1)
    local bar = {
        frame = frame, visual = visual, background = background, gradient = gradient,
        border = { top, bottom, left, right },
        accent = accent, dividers = {}, slots = {},
    }
    AssignBarKeys(bar, index)
    frame.bar = bar
    M.bars[index] = bar
    CreateBadge(bar)
    for slot = 1, SLOT_COUNT do bar.slots[slot] = CreateSlot(bar, slot) end
    frame:SetScript("OnEnter", BarEnter)
    frame:SetScript("OnLeave", BarLeave)
    frame:SetScript("OnShow", BarShownChanged)
    frame:SetScript("OnHide", BarShownChanged)
    return bar
end

local function Visible(bar)
    if not bar.frame:IsVisible() then return false end
    if S.editMode then return true end
    if M.config[bar.visibilityKey] == 4 then return bar.hover == true end
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
            if relayout and self.config[bar.layoutKey] == 2 then Layout(bar) end
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
            for _, bar in pairs(self.bars) do RefreshHealthAlpha(bar) end
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
            self.context:Event(event, OnEvent, true,
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

-- "Out of combat" and "In combat" are state drivers as well: the client
-- decides combat, and PLAYER_REGEN_DISABLED fires before lockdown starts.
local function MacroVisibility(c, bar)
    local rules, n = {}, 0
    local injured = c[bar.injuredKey] == true
    for _, condition in ipairs(NS.DataTextLoadConditions) do
        local suffix, macro = condition[1], condition[3]
        if macro and c[bar.prefix .. "LoadCond" .. suffix] == true
            and not (injured and (suffix == "HideNoTarget" or suffix == "HideOutOfCombat"
                or suffix == "HideOutOfCombatNoTarget")) then
            n = n + 1
            rules[n] = macro
        end
    end
    local mode = c[bar.visibilityKey]
    if n == 0 and mode ~= 2 and mode ~= 3 then return nil end
    if mode == 2 then table.insert(rules, 1, "[combat] hide")
    elseif mode == 3 then table.insert(rules, 1, "[nocombat] hide") end
    rules[#rules + 1] = "show"
    return table.concat(rules, "; ")
end

-- Visibility macros depend on settings only: they are built when a bar is
-- refreshed, and UpdateVisibility (zone and housing events) reads the cached
-- strings. Edit Mode reveals bars out of combat.
local EDIT_PREFIX = "[nocombat] show; "
local BLOCKED, BLOCKED_EDIT = "hide", EDIT_PREFIX .. "hide"
local function CacheVisibility(c, bar)
    local expression = MacroVisibility(c, bar)
    bar.visibilityMacro = expression
    bar.visibilityEditMacro = expression and EDIT_PREFIX .. expression
end

local function SetVisibilityDriver(bar, expression)
    if bar.visibilityDriver == expression then return true end
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return false
    end
    if bar.visibilityDriver then UnregisterStateDriver(bar.frame, "visibility") end
    bar.visibilityDriver = nil
    if expression then
        RegisterStateDriver(bar.frame, "visibility", expression)
        bar.visibilityDriver = expression
    end
    return true
end

function M:UpdateVisibility()
    local c = self.config
    self.styling = true
    for i, bar in pairs(self.bars) do
        local mode = c[bar.visibilityKey]
        if mode ~= 4 then bar.hover = false end
        local enabled = self.presentIDs[i] and c[bar.enabledKey] == true
        local blocked = enabled and (c[bar.instanceKey] and InInstance()
            or c[bar.housingKey] and InHousing())
        local expression
        if enabled then
            expression = S.editMode and bar.visibilityEditMacro or bar.visibilityMacro
            if expression and blocked then expression = S.editMode and BLOCKED_EDIT or BLOCKED end
        end
        if SetVisibilityDriver(bar, expression) and not expression then
            bar.frame:SetShown(enabled and (S.editMode or not blocked))
        end
        bar.frame:SetAlpha((S.editMode or mode ~= 4 or bar.hover) and 1 or 0)
        RefreshHealthAlpha(bar)
    end
    self.styling = false
    self:Rebind()
end

local function StyleSlot(button, style, font)
    button.label:SetText(NO_VALUE)
    S.SetStyledFont(button.label, font, style.fontSize, OUTLINES[style.textOutline] or "OUTLINE",
        style.fontRendering, style.fontShadow, style.fontShadowOpacity, style.fontShadowDistance)
    button.label:SetJustifyH(ALIGN[style.textAlign] or "CENTER")
    button.label:SetTextColor(1, 1, 1)
end

local function PlaceBar(bar, c)
    local prefix, frame = bar.prefix, bar.frame
    local pixel = S.PixelUnit() or 1
    bar.pixelUnit = pixel
    frame:ClearAllPoints()
    local point = NS.DataTextPoints[c[prefix .. "Point"]] or "BOTTOM"
    local dock = c[prefix .. "Dock"] or 1
    if dock > 1 then point = ({ "", "TOP", "BOTTOM", "LEFT", "RIGHT" })[dock] end
    frame:SetPoint(point, UIParent, point, Snap(c[prefix .. "X"], pixel), Snap(c[prefix .. "Y"], pixel))
    bar.vertical = c[prefix .. "Vertical"] == true
    local span = bar.vertical and UIParent:GetHeight() or UIParent:GetWidth()
    bar.length = Snap(c[prefix .. "FullScreen"] and span or c[bar.widthKey], pixel)
    local thickness = Snap(c[bar.heightKey], pixel)
    frame:SetSize(bar.vertical and thickness or bar.length, bar.vertical and bar.length or thickness)
    if dock > 1 then
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
    button:EnableMouseWheel(button.extra ~= nil and button.extra.kind == "audio")
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
    local bar = CreateBar(index)
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
    CacheVisibility(c, bar)
end

function M:Refresh()
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return
    end
    if self.config.trackAltGold then GoldLedger.Capture() end
    self.styling = true
    Clear(self.values)
    Clear(BAR_KEYS)
    NS.SuiteCatalog.dataTexts.prepareConfig(self.config)
    self.barIDs = NS.DataTextBarIDs(self.config)
    Clear(self.presentIDs)
    for _, i in ipairs(self.barIDs) do self.presentIDs[i] = true end
    for i, bar in pairs(self.bars) do
        if not self.presentIDs[i] then
            SetVisibilityDriver(bar, nil)
            bar.frame:Hide()
            bar.visual:SetAlpha(1)
            for slot = 1, SLOT_COUNT do HideTooltip(bar.slots[slot]) end
            self.bars[i] = nil
            self.pool[#self.pool + 1] = bar
        end
    end
    for _, i in ipairs(self.barIDs) do
        if self.config[BarKeys(i).enabled] then RefreshBar(i) end
    end
    self.styling = false
    self:UpdateVisibility()
    self:RegisterMovers()
    Extra.PrepareHearths()
    SyncNativeBagBar()
end

local function AddonLoaded(_, _, addon)
    if addon == "Blizzard_MainMenuBarBagButtons" then SyncNativeBagBar() end
end

local function ScaleChanged(module)
    if NS.IsCombatLocked() then
        S.Queue(ID)
    else
        module:Refresh()
    end
end

function M:Enable()
    self:Refresh()
    SyncNativeBagBar()
    self.context:Event("ADDON_LOADED", AddonLoaded, true)
    self.context:Event("UI_SCALE_CHANGED", ScaleChanged)
    self.context:Event("DISPLAY_SIZE_CHANGED", ScaleChanged)
end

function M:Disable()
    Actions.Disable()
    Extra.Disable()
    SyncNativeBagBar()
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
        SetVisibilityDriver(bar, nil)
        bar.frame:Hide()
        bar.visual:SetAlpha(1)
        if owned then
            for i = 1, SLOT_COUNT do HideTooltip(bar.slots[i]) end
        end
    end
end

local movers
local function Mover(index)
    local keys = BarKeys(index)
    local prefix = keys.prefix
    return {
        label = M.config[prefix .. "Name"] or S.Text("DataTexts bar %d"):format(index), order = 690 + index,
        centerPopup = true,
        getFrame = function() return M.bars[index] and M.bars[index].frame end,
        isEnabled = function() return M.presentIDs[index] and M.config[keys.enabled] == true end,
        xKey = prefix .. "X", yKey = prefix .. "Y", pointKey = prefix .. "Point",
        point = function() return NS.DataTextPoints[M.config[prefix .. "Point"]] or "BOTTOM" end,
        historyKeys = { prefix .. "Width", prefix .. "Height" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 180, max = 900, step = 1,
                get = function() return S.Config(ID)[prefix .. "Width"] end,
                set = function(value) return S.Set(ID, prefix .. "Width", value) end },
            { id = "height", label = "Height", kind = "number", min = 18, max = 100, step = 1,
                get = function() return S.Config(ID)[prefix .. "Height"] end,
                set = function(value) return S.Set(ID, prefix .. "Height", value) end },
        },
    }
end

function M:RegisterMovers()
    movers = movers or {}
    Clear(movers)
    S.UnregisterEditElements(ID)
    for _, i in ipairs(self.barIDs) do
        if self.bars[i] then
            movers[i] = Mover(i)
            S.RegisterOwnedMover(ID, "bar" .. i, movers[i])
        end
    end
end

S.Install(ID, M)
