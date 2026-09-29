local _, P = ...
local NS, S = P.NS, P.Suite
local Appearance = assert(P.Appearance)
local M = { bars = {}, due = {}, values = {}, events = {} }
local ID = "dataTexts"
local BAR_COUNT, SLOT_COUNT = 3, 6
local BADGE = "Interface\\AddOns\\MSUF_Suite_DataTexts\\Media\\BagMedallion.tga"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local function Snap(value, pixel)
    return math.floor(value / pixel + 0.5) * pixel
end
local SOURCES = {
    gold = true, sessionGold = true, bags = true, durability = true, clock = true,
    fps = true, latency = true, coordinates = true, location = true, xp = true,
    date = true, fpsLatency = true,
}
local SAMPLED = { clock = true, fps = true, latency = true, coordinates = true, date = true, fpsLatency = true }
local INTERVAL = { fps = 2, latency = 5, coordinates = 0.5, fpsLatency = 2 }
-- Displays that read another shared data source.
local READER = { clock = "clockTime", sessionGold = "gold" }
local EVENT_SOURCES = {
    PLAYER_MONEY = { "gold", "sessionGold" },
    BAG_UPDATE_DELAYED = { "bags" },
    UPDATE_INVENTORY_DURABILITY = { "durability" },
    PLAYER_EQUIPMENT_CHANGED = { "durability" },
    ZONE_CHANGED = { "location", "coordinates" },
    ZONE_CHANGED_INDOORS = { "location", "coordinates" },
    ZONE_CHANGED_NEW_AREA = { "location", "coordinates" },
    PLAYER_XP_UPDATE = { "xp" },
    PLAYER_LEVEL_UP = { "xp" },
    UPDATE_EXHAUSTION = { "xp" },
}
local CLICK = {
    gold = "OpenAllBags", sessionGold = "OpenAllBags", bags = "OpenAllBags",
    coordinates = "ToggleWorldMap", location = "ToggleWorldMap", date = "ToggleCalendar",
}
local LABELS = {
    gold = S.Text("Gold"), sessionGold = S.Text("Session"), bags = S.Text("Bags"),
    durability = S.Text("Durability"), clock = S.Text("Time"), fps = S.Text("FPS"),
    latency = S.Text("World"), coordinates = S.Text("Coords"), location = S.Text("Zone"), xp = S.Text("XP"),
    date = S.Text("Date"), fpsLatency = S.Text("FPS / World"),
}
local TEXT = {
    current = S.Text("Current"),
    sinceLogin = S.Text("Since login"),
    homeWorld = S.Text("Home / World"),
    level = S.Text("Level"),
}
local NO_VALUE = "—"
local floor = math.floor
local MoneyText = S.MoneyText
local nativeBagBar, nativeBagBarWasShown, nativeBagDriver, nativeBagHooked
local nativeBagShowHooks = setmetatable({}, { __mode = "k" })
local healthCurve
-- Rebind alternates between two active-source sets and reuses its event set.
local activeSetA, activeSetB, wantedEvents = {}, {}, {}
-- Layout reuses these for the shown slots of a bar and their widths.
local layoutSlots, layoutWidths = {}, {}
-- Per-bar setting names, built once so event paths never concatenate keys.
local BAR_KEYS = {}
for i = 1, BAR_COUNT do
    local prefix = "bar" .. i
    BAR_KEYS[i] = {
        prefix = prefix, enabled = prefix .. "Enabled", visibility = prefix .. "Visibility",
        injured = prefix .. "LoadCondShowWhenInjured", instance = prefix .. "LoadCondHideInInstance",
        housing = prefix .. "LoadCondHideInHousing",
    }
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

local Finite = S.Finite

-- Losses use the typographic minus sign (U+2212).
local function SignedMoneyText(delta)
    return (delta > 0 and "+" or delta < 0 and "−" or "") .. MoneyText(math.abs(delta))
end

-- This session's login gold (MSUF_Suite/Core/SessionGold.lua), or nil.
local function SessionBaseline()
    if NS.goldSessionCaptured ~= true then return nil end
    return NS.StoredSessionGold()
end

local function ApplyColor(region, hex, alpha)
    local r, g, b = S.RGB(hex)
    region:SetColorTexture(r, g, b, alpha)
end

-- Each formatter returns the display value (nil when unknown) and an
-- optional "bad" severity from the raw values of its shared data source.
local FORMATTERS = {
    gold = function(amount)
        if Finite(amount) then return floor(amount / 10000) .. "g" end
    end,
    sessionGold = function(amount)
        local baseline = SessionBaseline()
        if Finite(amount) and Finite(baseline) then
            local delta = amount - baseline
            return SignedMoneyText(delta), delta < 0 and "bad" or nil
        end
    end,
    bags = function(free, total)
        if Finite(free) and Finite(total) then
            return free .. "/" .. total, nil,
                total > 0 and floor((total - free) / total * 100 + .5) .. "%" or NO_VALUE
        end
    end,
    durability = function(lowest)
        if Finite(lowest) then return floor(lowest * 100 + .5) .. "%", lowest <= .2 and "bad" or nil end
    end,
    clock = function(hour, minute)
        if Finite(hour) and Finite(minute) then return string.format("%02d:%02d", hour, minute) end
    end,
    fps = function(rate)
        if Finite(rate) then return tostring(floor(rate + .5)), rate < 30 and "bad" or nil end
    end,
    latency = function(_, world)
        if Finite(world) then return floor(world + .5) .. " ms", world >= 200 and "bad" or nil end
    end,
    coordinates = function(x, y)
        if Finite(x) and Finite(y) then return string.format("%.1f, %.1f", x * 100, y * 100) end
    end,
    location = function(zone, subZone)
        if type(subZone) == "string" and subZone ~= "" then return subZone end
        if type(zone) == "string" and zone ~= "" then return zone end
    end,
    xp = function(_, current, maximum)
        if Finite(current) and Finite(maximum) and maximum > 0 then
            return string.format("%.1f%%", current * 100 / maximum)
        end
    end,
}

local function Format(key)
    if key == "date" then return LABELS[key], date("%d-%m-%Y") end
    if key == "fpsLatency" then
        local fps = S.ReadInfoSource("fps")
        local _, world = S.ReadInfoSource("latency")
        if Finite(fps) and Finite(world) then
            return LABELS[key], floor(fps + .5) .. " / " .. floor(world + .5) .. " ms",
                (fps < 30 or world >= 200) and "bad" or nil
        end
        return LABELS[key], NO_VALUE
    end
    local value, severity, alternate = FORMATTERS[key](S.ReadInfoSource(READER[key] or key))
    return LABELS[key], value or NO_VALUE, severity, alternate
end

local function Tooltip(button)
    if not M.active or not button.source then return end
    local key = button.source
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(NS.DataTextSources[button.sourceIndex] or key, 1, .82, .36)
    if key == "gold" or key == "sessionGold" then
        local amount = S.ReadInfoSource("gold")
        if Finite(amount) then
            GameTooltip:AddDoubleLine(TEXT.current, MoneyText(amount))
            local baseline = SessionBaseline()
            if baseline then GameTooltip:AddDoubleLine(TEXT.sinceLogin, SignedMoneyText(amount - baseline)) end
        end
    elseif key == "latency" or key == "fpsLatency" then
        local home, world = S.ReadInfoSource("latency")
        if Finite(home) and Finite(world) then
            GameTooltip:AddDoubleLine(TEXT.homeWorld, floor(home + .5) .. " / " .. floor(world + .5) .. " ms")
        end
    elseif key == "xp" then
        local level, current, maximum = S.ReadInfoSource("xp")
        if Finite(level) and Finite(current) and Finite(maximum) then
            GameTooltip:AddDoubleLine(TEXT.level .. " " .. level, current .. " / " .. maximum)
        end
    else
        GameTooltip:AddLine(button.text or NO_VALUE, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function HideTooltip(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function Click(button)
    if NS.IsCombatLocked() or not button.source then return end
    local name = CLICK[button.source]
    if name then
        _G[name]()
    elseif button.source == "durability" then
        ToggleCharacter("PaperDollFrame")
    elseif button.source == "clock" then
        ToggleCalendar()
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
    Tooltip(button)
end

local function SlotLeave(button)
    HideTooltip(button)
    if not button.bar.frame:IsMouseOver() then SetHover(button.bar, false) end
end

local function BarEnter(frame) SetHover(frame.bar, true) end

local function BarLeave(frame)
    if not frame:IsMouseOver() then SetHover(frame.bar, false) end
end

local function BarShownChanged()
    if not M.styling then M:Rebind() end
end

local function CreateEdge(frame, layer, from, to)
    local texture = S.CreateTexture(frame, nil, layer)
    texture:SetPoint(from)
    texture:SetPoint(to)
    return texture
end

local function CreateSlot(bar)
    local button = S.CreateFrame("Button", nil, bar.visual)
    button.bar = bar
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", Click)
    button:SetScript("OnEnter", SlotEnter)
    button:SetScript("OnLeave", SlotLeave)
    local text = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", button, "LEFT", 5, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    button.label = text
    return button
end

local function CreateBar(index)
    if M.bars[index] then return M.bars[index] end
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
    local keys = BAR_KEYS[index]
    local prefix = keys.prefix
    local bar = {
        frame = frame, visual = visual, background = background, gradient = gradient,
        border = { top, bottom, left, right },
        accent = accent, dividers = {}, slots = {}, index = index, prefix = prefix,
        enabledKey = keys.enabled, visibilityKey = keys.visibility, layoutKey = prefix .. "Layout",
        widthKey = prefix .. "Width", heightKey = prefix .. "Height",
        injuredKey = keys.injured, instanceKey = keys.instance, housingKey = keys.housing,
    }
    frame.bar = bar
    M.bars[index] = bar
    local badge = S.CreateFrame("Button", nil, visual)
    badge.bar, badge.source, badge.sourceIndex, badge.text = bar, "bags", 3, LABELS.bags
    badge:RegisterForClicks("LeftButtonUp")
    badge:SetScript("OnClick", Click)
    badge:SetScript("OnEnter", SlotEnter)
    badge:SetScript("OnLeave", SlotLeave)
    local badgeArt = S.CreateTexture(badge, nil, "OVERLAY")
    badgeArt:SetAllPoints(badge)
    badgeArt:SetTexture(BADGE)
    bar.badge = badge
    for slot = 1, SLOT_COUNT do bar.slots[slot] = CreateSlot(bar) end
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

-- Widths of the first count layout slots: equal shares, or (auto layout)
-- text widths scaled to fill the bar.
local function SlotWidths(bar, count)
    local c, style, widths = M.config, bar.style, layoutWidths
    local pixel = bar.pixelUnit or 1
    local configuredWidth = Snap(c[bar.widthKey], pixel)
    local inset = style.bagBadge and Snap(style.bagBadgeSize + 8, pixel) or 0
    local gaps = (count - 1) * Snap(style.gap, pixel)
    if c[bar.layoutKey] ~= 2 then
        if bar.frame:GetWidth() ~= configuredWidth then bar.frame:SetWidth(configuredWidth) end
        for i = 1, count do widths[i] = (configuredWidth - inset - gaps) / count end
        return
    end
    local total = 0
    for i = 1, count do
        -- The unbounded width: the label may be truncated by its current slot.
        widths[i] = math.max(44, math.ceil(layoutSlots[i].label:GetUnboundedStringWidth()) + 2 * style.padding)
        total = total + widths[i]
    end
    local needed = Snap(math.min(900, math.max(configuredWidth, total + gaps + inset)), pixel)
    if bar.frame:GetWidth() ~= needed then bar.frame:SetWidth(needed) end
    local ratio = (needed - inset - gaps) / total
    for i = 1, count do widths[i] = widths[i] * ratio end
end

local function PlaceDivider(bar, index, x, height)
    local style = bar.style
    local divider = bar.dividers[index]
    if not divider then
        divider = S.CreateTexture(bar.visual, nil, "ARTWORK")
        bar.dividers[index] = divider
        ApplyColor(divider, style.separatorColor, .8)
    end
    divider:ClearAllPoints()
    local pixel = bar.pixelUnit or 1
    divider:SetPoint("CENTER", bar.frame, "LEFT", Snap(x + Snap(style.gap, pixel) / 2, pixel), 0)
    divider:SetSize(style.separatorSize * pixel, Snap(math.max(6, height - 2 * Snap(style.padding, pixel)), pixel))
    divider:Show()
end

-- Auto-layout bars relayout on value changes, so this allocates nothing.
local function Layout(bar)
    local style, slots, widths = bar.style, layoutSlots, layoutWidths
    local pixel = bar.pixelUnit or 1
    local count = 0
    for i = 1, SLOT_COUNT do
        local button = bar.slots[i]
        if button.source then
            count = count + 1
            slots[count] = button
        end
    end
    for _, divider in pairs(bar.dividers) do divider:Hide() end
    if count == 0 then return end
    SlotWidths(bar, count)
    local height = Snap(M.config[bar.heightKey], pixel)
    local x = style.bagBadge and Snap(style.bagBadgeSize + 8, pixel) or 0
    local gap = Snap(style.gap, pixel)
    for i = 1, count do
        local button, width = slots[i], widths[i]
        local left, right = Snap(x, pixel), Snap(x + width, pixel)
        button:ClearAllPoints()
        button:SetPoint("LEFT", bar.frame, "LEFT", left, 0)
        button:SetSize(right - left, height)
        local inset = Snap(math.max(0, math.min(style.padding, floor((width - 4) / 2))), pixel)
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", inset, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        x = x + width
        if i < count then
            if style.separatorEnabled then PlaceDivider(bar, i, x, height) end
            x = x + gap
        end
    end
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

local function OnEvent(self, event, unit)
    if event == "PLAYER_XP_UPDATE" and unit and unit ~= "player" then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit == "player" then
            for i = 1, BAR_COUNT do RefreshHealthAlpha(self.bars[i]) end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        self:UpdateVisibility()
        EnteredWorld(self)
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "HOUSE_PLOT_ENTERED"
        or event == "HOUSE_PLOT_EXITED" then
        self:UpdateVisibility()
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        self:UpdateVisibility()
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

local function SyncEvents(self, active)
    Clear(wantedEvents)
    for event, keys in pairs(EVENT_SOURCES) do
        for i = 1, #keys do
            if active[keys[i]] then
                wantedEvents[event] = true
                break
            end
        end
    end
    if next(active) then wantedEvents.PLAYER_ENTERING_WORLD = true end
    local c = self.config
    for i = 1, BAR_COUNT do
        local keys = BAR_KEYS[i]
        local enabled, mode, housing = c[keys.enabled], c[keys.visibility], c[keys.housing]
        if enabled and (mode == 2 or mode == 3) and not (self.bars[i] and self.bars[i].visibilityDriver) then
            wantedEvents.PLAYER_REGEN_DISABLED = true
            wantedEvents.PLAYER_REGEN_ENABLED = true
        end
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
    if n == 0 then return nil end
    local mode = c[bar.visibilityKey]
    if mode == 2 then table.insert(rules, 1, "[combat] hide")
    elseif mode == 3 then table.insert(rules, 1, "[nocombat] hide") end
    rules[#rules + 1] = "show"
    return table.concat(rules, "; ")
end

-- Visibility macros depend on settings only: they are built when a bar is
-- refreshed, and UpdateVisibility (combat, zone and housing events) reads
-- the cached strings. Edit Mode reveals bars out of combat.
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
    local combat = NS.IsCombatLocked()
    self.styling = true
    for i = 1, BAR_COUNT do
        local bar = self.bars[i]
        if bar then
            local mode = c[bar.visibilityKey]
            if mode ~= 4 then bar.hover = false end
            local enabled = c[bar.enabledKey] == true
            local blocked = enabled and (c[bar.instanceKey] and InInstance()
                or c[bar.housingKey] and InHousing())
            local expression
            if enabled then
                expression = S.editMode and bar.visibilityEditMacro or bar.visibilityMacro
                if expression and blocked then expression = S.editMode and BLOCKED_EDIT or BLOCKED end
            end
            if SetVisibilityDriver(bar, expression) and not expression then
                bar.frame:SetShown(enabled and (S.editMode or not blocked and (mode ~= 2 and mode ~= 3
                    or mode == 2 and not combat or mode == 3 and combat)))
            end
            bar.frame:SetAlpha((S.editMode or mode ~= 4 or bar.hover) and 1 or 0)
            RefreshHealthAlpha(bar)
        end
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

local function RefreshBar(index)
    local c = M.config
    local bar = CreateBar(index)
    local prefix, frame = bar.prefix, bar.frame
    local pixel = S.PixelUnit() or 1
    bar.pixelUnit = pixel
    frame:ClearAllPoints()
    local point = NS.DataTextPoints[c[prefix .. "Point"]] or "BOTTOM"
    frame:SetPoint(point, UIParent, point, Snap(c[prefix .. "X"], pixel), Snap(c[prefix .. "Y"], pixel))
    frame:SetSize(Snap(c[bar.widthKey], pixel), Snap(c[bar.heightKey], pixel))
    bar.style = NS.DataTextEffectiveStyle(c, index)
    if bar.style.valueClassColor then
        local _, class = UnitClass("player")
        if S.Public(class) then
            local r, g, b = S.ClassRGB(class)
            if Finite(r) and Finite(g) and Finite(b) then
                bar.style.valueColor = string.format("%02x%02x%02x",
                    floor(r * 255 + .5), floor(g * 255 + .5), floor(b * 255 + .5))
            end
        end
    end
    Appearance.Paint(bar)
    local style = bar.style
    local font = S.ResolveFont(style.font) or S.GlobalFontPath()
    for slot = 1, SLOT_COUNT do
        local button = bar.slots[slot]
        local choice = c[prefix .. "Slot" .. slot]
        local key = NS.DataTextSourceKeys[choice]
        button.source, button.sourceIndex = SOURCES[key] and key or nil, choice
        button.text, button.display = nil, nil
        button:SetShown(button.source ~= nil)
        if button.source then StyleSlot(button, style, font) end
    end
    Layout(bar)
    CacheVisibility(c, bar)
end

function M:Refresh()
    self.styling = true
    Clear(self.values)
    for i = 1, BAR_COUNT do
        if self.config[BAR_KEYS[i].enabled] then RefreshBar(i) end
    end
    self.styling = false
    self:UpdateVisibility()
    self:RegisterMovers()
    SyncNativeBagBar()
end

local function AddonLoaded(_, _, addon)
    if addon == "Blizzard_MainMenuBarBagButtons" then SyncNativeBagBar() end
end

local function ScaleChanged(module)
    if NS.IsCombatLocked() then S.Queue(ID) else module:Refresh() end
end

function M:Enable()
    self:Refresh()
    SyncNativeBagBar()
    self.context:Event("ADDON_LOADED", AddonLoaded, true)
    self.context:Event("UI_SCALE_CHANGED", ScaleChanged)
    self.context:Event("DISPLAY_SIZE_CHANGED", ScaleChanged)
end

function M:Disable()
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
function M:RegisterMovers()
    if not movers then
        movers = {}
        for i = 1, BAR_COUNT do
            local index, keys = i, BAR_KEYS[i]
            local prefix = keys.prefix
            movers[i] = {
                label = "DataTexts bar " .. i, order = 690 + i,
                centerPopup = true,
                getFrame = function() return M.bars[index] and M.bars[index].frame end,
                isEnabled = function() return M.config[keys.enabled] == true end,
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
    end
    for i = 1, BAR_COUNT do S.RegisterOwnedMover(ID, "bar" .. i, movers[i]) end
end

S.Install(ID, M)
