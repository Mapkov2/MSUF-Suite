local _, P = ...
local NS, S = P.NS, P.Suite
local M = { bars = {}, due = {}, values = {}, events = {} }
local ID = "dataTexts"
local BAR_COUNT, SLOT_COUNT = 3, 6
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local SOURCES = {
    gold = true, sessionGold = true, bags = true, durability = true, clock = true,
    fps = true, latency = true, coordinates = true, location = true, xp = true,
}
local SAMPLED = { clock = true, fps = true, latency = true, coordinates = true }
local INTERVAL = { fps = 2, latency = 5, coordinates = 0.5 }
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
    coordinates = "ToggleWorldMap", location = "ToggleWorldMap",
}
local LABELS = {
    gold = S.Text("Gold"), sessionGold = S.Text("Session"), bags = S.Text("Bags"),
    durability = S.Text("Durability"), clock = S.Text("Time"), fps = S.Text("FPS"),
    latency = S.Text("World"), coordinates = S.Text("Coords"), location = S.Text("Zone"), xp = S.Text("XP"),
}
local TEXT = {
    current = S.Text("Current"),
    sinceLogin = S.Text("Since login"),
    homeWorld = S.Text("Home / World"),
    level = S.Text("Level"),
}
local NO_VALUE = "—"
local floor = math.floor
local nativeBagBar, nativeBagBarWasShown, nativeBagDriver, nativeBagHooked
local nativeBagShowHooks = setmetatable({}, { __mode = "k" })
local healthCurve
-- Rebind alternates between two active-source sets and reuses its event set.
local activeSetA, activeSetB, wantedEvents = {}, {}, {}

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local inside = IsInInstance()
    return inside == true or inside == 1
end

local function InHousing()
    local fn = C_Housing and C_Housing.IsInsideHouseOrPlot
    return type(fn) == "function" and fn() == true
end

local function RefreshHealthAlpha(bar)
    if not bar or not bar.visual then return end
    if S.editMode or not M.config[bar.prefix .. "LoadCondShowWhenInjured"] then
        bar.visual:SetAlpha(1)
        return
    end
    local percent = UnitHealthPercent
    local curveAPI = C_CurveUtil
    local curveType = Enum and Enum.LuaCurveType
    if type(percent) == "function" and curveAPI and type(curveAPI.CreateCurve) == "function"
        and curveType and curveType.Step then
        if not healthCurve then
            healthCurve = curveAPI.CreateCurve()
            healthCurve:SetType(curveType.Step)
            healthCurve:AddPoint(0, 1)
            healthCurve:AddPoint(1, 0)
        end
        -- Midnight health can be secret. The curve result goes straight into
        -- SetAlpha without Lua comparison, arithmetic or string conversion.
        bar.visual:SetAlpha(percent("player", false, healthCurve))
    elseif type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
        local current, maximum = UnitHealth("player"), UnitHealthMax("player")
        if not S.Public(current) or not S.Public(maximum) then
            bar.visual:SetAlpha(1)
        else
            bar.visual:SetAlpha(maximum > 0 and current < maximum and 1 or 0)
        end
    else
        -- If this client lacks a safe health path, keep the bar usable.
        bar.visual:SetAlpha(1)
    end
end

-- Retail and Forever keep backpack and bag slots on a separate BagsBar.
-- The bag DataText is the visible entry point while this option is on;
-- Blizzard still owns item movement and the actual container windows.
local function SyncNativeBagBar()
    if not NS.Client.isMainline then return end
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
        if not nativeBagDriver and type(RegisterStateDriver) == "function" then
            RegisterStateDriver(frame, "visibility", "hide")
            nativeBagDriver = true
        end
        frame:Hide()
        if not nativeBagShowHooks[frame] and type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", SyncNativeBagBar)
            nativeBagShowHooks[frame] = true
        end
        if not nativeBagHooked and type(hooksecurefunc) == "function"
            and type(_G.MainActionBar_InitializeMKB) == "function" then
            hooksecurefunc("MainActionBar_InitializeMKB", SyncNativeBagBar)
            nativeBagHooked = true
        end
    elseif nativeBagBar then
        if nativeBagDriver and type(UnregisterStateDriver) == "function" then
            UnregisterStateDriver(nativeBagBar, "visibility")
        end
        nativeBagDriver = nil
        local restoreFrame, wasShown = nativeBagBar, nativeBagBarWasShown
        nativeBagBar, nativeBagBarWasShown = nil, nil
        if wasShown then restoreFrame:Show() end
    end
end

local Finite = S.Finite

local function Time()
    local value = type(GetTime) == "function" and GetTime()
    return Finite(value) and value or 0
end

local function MoneyText(amount)
    local gold, silver, copper = floor(amount / 10000), floor(amount % 10000 / 100), amount % 100
    local text = gold > 0 and gold .. "g" or nil
    if silver > 0 then text = text and text .. " " .. silver .. "s" or silver .. "s" end
    if copper > 0 or not text then text = text and text .. " " .. copper .. "c" or copper .. "c" end
    return text
end

local function SignedMoneyText(delta)
    return (delta > 0 and "+" or delta < 0 and "−" or "") .. MoneyText(math.abs(delta))
end

local function SessionBaseline()
    if NS.goldSessionCaptured ~= true or type(UnitGUID) ~= "function" then return nil end
    local guid = UnitGUID("player")
    if not S.Public(guid) or type(guid) ~= "string" then return nil end
    local root = NS.RootDB
    local baseline = type(root) == "table" and type(root.suiteGold) == "table" and root.suiteGold[guid] or nil
    return Finite(baseline) and baseline or nil
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
        if Finite(free) and Finite(total) then return free .. "/" .. total end
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
    local value, severity = FORMATTERS[key](S.ReadInfoSource(READER[key] or key))
    return LABELS[key], value or NO_VALUE, severity
end

local function Tooltip(button)
    if not M.active or not GameTooltip or not button.source then return end
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
    elseif key == "latency" then
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
    if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function Click(button)
    if NS.IsCombatLocked() or not button.source then return end
    local name = CLICK[button.source]
    if name and type(_G[name]) == "function" then
        _G[name]()
    elseif button.source == "durability" and type(ToggleCharacter) == "function" then
        ToggleCharacter("PaperDollFrame")
    elseif button.source == "clock" and type(ToggleCalendar) == "function" then
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
    local prefix = "bar" .. index
    local bar = {
        frame = frame, visual = visual, background = background, border = { top, bottom, left, right },
        accent = accent, dividers = {}, slots = {}, index = index, prefix = prefix,
        visibilityKey = prefix .. "Visibility", layoutKey = prefix .. "Layout",
    }
    frame.bar = bar
    M.bars[index] = bar
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

local function ApplyStyle(bar)
    local style = bar.style
    local background = bar.background
    background:SetShown(style.backgroundEnabled == true)
    if style.backgroundEnabled then
        local path = style.backgroundTexture ~= "" and S.ResolveTexture(style.backgroundTexture)
        if path then
            background:SetTexture(path)
            local r, g, b = S.RGB(style.backgroundColor)
            background:SetVertexColor(r, g, b, style.backgroundOpacity / 100)
        else
            ApplyColor(background, style.backgroundColor, style.backgroundOpacity / 100)
        end
    end
    for i = 1, 4 do
        local edge = bar.border[i]
        edge:SetShown(style.borderEnabled == true)
        if style.borderEnabled then
            ApplyColor(edge, style.borderColor, .85)
            if i <= 2 then edge:SetHeight(style.borderSize) else edge:SetWidth(style.borderSize) end
        end
    end
    bar.accent:SetShown(style.accentEnabled == true)
    if style.accentEnabled then ApplyColor(bar.accent, style.accentColor, .9) end
    for _, divider in pairs(bar.dividers) do ApplyColor(divider, style.separatorColor, .8) end
end

local function Display(label, value, severity, style)
    local valueColor = severity == "bad" and style.warningColor or style.valueColor
    if style.showLabels then
        return label .. ": " .. value,
            "|cff" .. style.labelColor .. label .. ": |r|cff" .. valueColor .. value .. "|r"
    end
    return value, "|cff" .. valueColor .. value .. "|r"
end

-- Slot widths: equal shares, or (auto layout) text widths scaled to fill the bar.
local function SlotWidths(bar, visible, widths)
    local c, style = M.config, bar.style
    local configuredWidth = c[bar.prefix .. "Width"]
    local gaps = (#visible - 1) * style.gap
    if c[bar.layoutKey] ~= 2 then
        if bar.frame:GetWidth() ~= configuredWidth then bar.frame:SetWidth(configuredWidth) end
        for i = 1, #visible do widths[i] = (configuredWidth - gaps) / #visible end
        return
    end
    local total = 0
    for i, button in ipairs(visible) do
        local measure = button.label.GetUnboundedStringWidth or button.label.GetStringWidth
        widths[i] = math.max(44, math.ceil(measure(button.label)) + 2 * style.padding)
        total = total + widths[i]
    end
    local needed = math.min(900, math.max(configuredWidth, total + gaps))
    if bar.frame:GetWidth() ~= needed then bar.frame:SetWidth(needed) end
    local ratio = (needed - gaps) / total
    for i = 1, #widths do widths[i] = widths[i] * ratio end
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
    divider:SetPoint("CENTER", bar.frame, "LEFT", x + style.gap / 2, 0)
    divider:SetSize(style.separatorSize, math.max(6, height - 2 * style.padding))
    divider:Show()
end

local function Layout(bar)
    local style = bar.style
    local visible, widths = {}, {}
    for i = 1, SLOT_COUNT do
        local button = bar.slots[i]
        if button.source then visible[#visible + 1] = button end
    end
    for _, divider in pairs(bar.dividers) do divider:Hide() end
    if #visible == 0 then return end
    SlotWidths(bar, visible, widths)
    local height = M.config[bar.prefix .. "Height"]
    local x = 0
    for i, button in ipairs(visible) do
        button:ClearAllPoints()
        button:SetPoint("LEFT", bar.frame, "LEFT", x, 0)
        button:SetSize(widths[i], height)
        local inset = math.max(0, math.min(style.padding, floor((widths[i] - 4) / 2)))
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", inset, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        x = x + widths[i]
        if i < #visible then
            if style.separatorEnabled then PlaceDivider(bar, i, x, height) end
            x = x + style.gap
        end
    end
end

-- force repaints unchanged values: a bar that just became visible still
-- shows whatever it displayed before it was hidden.
function M:UpdateSource(key, force)
    if not self.activeSources or not self.activeSources[key] then return end
    local label, value, severity = Format(key)
    local record = self.values[key]
    if record and not force and record.label == label and record.value == value
        and record.severity == severity then
        return
    end
    if not record then
        record = {}
        self.values[key] = record
    end
    record.label, record.value, record.severity = label, value, severity
    for _, bar in pairs(self.bars) do
        if Visible(bar) then
            local relayout = false
            for i = 1, SLOT_COUNT do
                local button = bar.slots[i]
                if button.source == key then
                    local text, display = Display(label, value, severity, bar.style)
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
    return now + (key == "clock" and NextClock() or INTERVAL[key])
end

local TickDataTexts
function M:Schedule()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    local now, soonest = Time(), nil
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
    local now = Time()
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
                self.due[key] = Time() + INTERVAL.coordinates
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
    for i = 1, BAR_COUNT do
        local prefix = "bar" .. i
        local mode = self.config[prefix .. "Visibility"]
        if self.config[prefix .. "Enabled"] and (mode == 2 or mode == 3)
            and not (self.bars[i] and self.bars[i].visibilityDriver) then
            wantedEvents.PLAYER_REGEN_DISABLED = true
            wantedEvents.PLAYER_REGEN_ENABLED = true
        end
        if self.config[prefix .. "Enabled"] and self.config[prefix .. "LoadCondShowWhenInjured"] then
            wantedEvents.UNIT_HEALTH = true
            wantedEvents.UNIT_MAXHEALTH = true
        end
        local housingAPI = C_Housing and C_Housing.IsInsideHouseOrPlot
        local housing = self.config[prefix .. "LoadCondHideInHousing"] and type(housingAPI) == "function"
        if self.config[prefix .. "Enabled"] and (self.config[prefix .. "LoadCondHideInInstance"]
            or housing) then
            wantedEvents.PLAYER_ENTERING_WORLD = true
            wantedEvents.ZONE_CHANGED_NEW_AREA = true
        end
        if self.config[prefix .. "Enabled"] and housing then
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
            for i = 1, SLOT_COUNT do
                local key = bar.slots[i].source
                if key then active[key] = true end
            end
        end
    end
    self.activeSources = active
    SyncEvents(self, active)
    local now, sampledChanged = Time(), false
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
    local injured = c[bar.prefix .. "LoadCondShowWhenInjured"] == true
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

local function SetVisibilityDriver(bar, expression)
    if bar.visibilityDriver == expression then return true end
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return false
    end
    if bar.visibilityDriver and type(UnregisterStateDriver) == "function" then
        UnregisterStateDriver(bar.frame, "visibility")
    end
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
            local enabled = c[bar.prefix .. "Enabled"] == true
            local blocked = enabled and (c[bar.prefix .. "LoadCondHideInInstance"] and InInstance()
                or c[bar.prefix .. "LoadCondHideInHousing"] and InHousing())
            local expression
            if enabled and type(RegisterStateDriver) == "function" then
                expression = MacroVisibility(c, bar)
                if expression and blocked then expression = "hide" end
                if expression and S.editMode then expression = "[nocombat] show; " .. expression end
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
    frame:ClearAllPoints()
    local point = NS.DataTextPoints[c[prefix .. "Point"]] or "BOTTOM"
    frame:SetPoint(point, UIParent, point, c[prefix .. "X"], c[prefix .. "Y"])
    frame:SetSize(c[prefix .. "Width"], c[prefix .. "Height"])
    bar.style = NS.DataTextEffectiveStyle(c, index)
    ApplyStyle(bar)
    local style = bar.style
    local font = S.ResolveFont(style.font) or FONT
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
end

function M:Refresh()
    self.styling = true
    Clear(self.values)
    for i = 1, BAR_COUNT do
        if self.config["bar" .. i .. "Enabled"] then RefreshBar(i) end
    end
    self.styling = false
    self:UpdateVisibility()
    self:RegisterMovers()
    SyncNativeBagBar()
end

local function AddonLoaded(_, _, addon)
    if addon == "Blizzard_MainMenuBarBagButtons" then SyncNativeBagBar() end
end

function M:Enable()
    self:Refresh()
    SyncNativeBagBar()
    if NS.Client.isMainline then self.context:Event("ADDON_LOADED", AddonLoaded, true) end
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
    local owned = GameTooltip and GameTooltip:GetOwner()
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
            local index, prefix = i, "bar" .. i
            movers[i] = {
                label = "DataTexts bar " .. i, order = 690 + i,
                getFrame = function() return M.bars[index] and M.bars[index].frame end,
                isEnabled = function() return M.config[prefix .. "Enabled"] == true end,
                xKey = prefix .. "X", yKey = prefix .. "Y", pointKey = prefix .. "Point",
                point = function() return NS.DataTextPoints[M.config[prefix .. "Point"]] or "BOTTOM" end,
                historyKeys = { prefix .. "Width", prefix .. "Height" },
                extraControls = {
                    { id = "width", label = "Width", kind = "number", min = 180, max = 900, step = 1,
                        get = function() return S.Config(ID)[prefix .. "Width"] end,
                        set = function(value) return S.Set(ID, prefix .. "Width", value) end },
                },
            }
        end
    end
    for i = 1, BAR_COUNT do S.RegisterOwnedMover(ID, "bar" .. i, movers[i]) end
end

S.Install(ID, M)
