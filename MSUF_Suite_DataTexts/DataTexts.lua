local _, P = ...
local NS, S = P.NS, P.Suite
local M = { bars = {}, due = {}, values = {}, events = {} }
local ID = "dataTexts"
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }
local SOURCES = { gold = true, sessionGold = true, bags = true, durability = true, clock = true, fps = true,
    latency = true, coordinates = true, location = true, xp = true }
local SAMPLED = { clock = true, fps = true, latency = true, coordinates = true }
local INTERVAL = { fps = 2, latency = 5, coordinates = 0.5 }
local EVENT_SOURCES = {
    PLAYER_MONEY = { "gold", "sessionGold" }, BAG_UPDATE_DELAYED = { "bags" },
    UPDATE_INVENTORY_DURABILITY = { "durability" }, PLAYER_EQUIPMENT_CHANGED = { "durability" },
    ZONE_CHANGED = { "location", "coordinates" }, ZONE_CHANGED_INDOORS = { "location", "coordinates" },
    ZONE_CHANGED_NEW_AREA = { "location", "coordinates" },
    PLAYER_XP_UPDATE = { "xp" }, PLAYER_LEVEL_UP = { "xp" }, UPDATE_EXHAUSTION = { "xp" },
}
local CLICK = { gold = "OpenAllBags", sessionGold = "OpenAllBags", bags = "OpenAllBags", coordinates = "ToggleWorldMap",
    location = "ToggleWorldMap" }
local nativeBagBar, nativeBagBarWasShown, nativeBagDriver, nativeBagHooked
local nativeBagShowHooks = setmetatable({}, { __mode = "k" })

-- Retail and Forever keep backpack and bag slots on a separate BagsBar.
-- The bag DataText is the visible entry point while this option is on;
-- Blizzard still owns item movement and the actual container windows.
local function SyncNativeBagBar()
    if not NS.Client.isMainline then return end
    if NS.IsCombatLocked() then S.Queue(ID); return end
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

local function Number(value)
    return S.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function Time()
    local value = type(GetTime) == "function" and GetTime()
    return Number(value) and value or 0
end
local function RGB(hex) return S.RGB(hex) end
local function MoneyText(amount)
    local gold = math.floor(amount / 10000)
    local silver = math.floor(amount % 10000 / 100)
    local copper = amount % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. "c" end
    return table.concat(parts, " ")
end
local function SessionBaseline()
    if NS.goldSessionCaptured ~= true then return nil end
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or not S.Public(guid) or type(guid) ~= "string" then return nil end
    local root = NS.RootDB
    local baseline = type(root) == "table" and type(root.suiteGold) == "table" and root.suiteGold[guid] or nil
    return Number(baseline) and baseline or nil
end
local function ApplyColor(region, hex, alpha)
    local r, g, b = RGB(hex)
    region:SetColorTexture(r, g, b, alpha)
end
local function Format(key)
    local readerKey = key == "clock" and "clockTime" or key == "sessionGold" and "gold" or key
    local a, b, c = S.ReadInfoSource(readerKey)
    local label, value, severity = "", "—", nil
    if key == "gold" then
        label = "Gold"
        if Number(a) then value = math.floor(a / 10000) .. "g" end
    elseif key == "sessionGold" then
        label = "Session"
        local baseline = SessionBaseline()
        if Number(a) and Number(baseline) then
            local delta = a - baseline
            value = (delta > 0 and "+" or delta < 0 and "−" or "")
                .. MoneyText(math.abs(delta))
            severity = delta < 0 and "bad" or nil
        end
    elseif key == "bags" then
        label = "Bags"
        if Number(a) and Number(b) then value = a .. "/" .. b end
    elseif key == "durability" then
        label = "Durability"
        if Number(a) then value = math.floor(a * 100 + .5) .. "%"; severity = a <= .2 and "bad" or nil end
    elseif key == "clock" then
        label = "Time"
        if Number(a) and Number(b) then value = string.format("%02d:%02d", a, b) end
    elseif key == "fps" then
        label = "FPS"
        if Number(a) then value = tostring(math.floor(a + .5)); severity = a < 30 and "bad" or nil end
    elseif key == "latency" then
        label = "World"
        if Number(b) then value = math.floor(b + .5) .. " ms"; severity = b >= 200 and "bad" or nil end
    elseif key == "coordinates" then
        label = "Coords"
        if Number(a) and Number(b) then value = string.format("%.1f, %.1f", a * 100, b * 100) end
    elseif key == "location" then
        label = "Zone"
        if type(b) == "string" and b ~= "" then value = b
        elseif type(a) == "string" and a ~= "" then value = a end
    elseif key == "xp" then
        label = "XP"
        if Number(b) and Number(c) and c > 0 then value = string.format("%.1f%%", b * 100 / c) end
    end
    return label, value, severity
end

local function Tooltip(button)
    if not M.active or not GameTooltip or not button.source then return end
    local key = button.source
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(NS.DataTextSources[button.sourceIndex] or key, 1, .82, .36)
    if key == "gold" or key == "sessionGold" then
        local amount = S.ReadInfoSource("gold")
        if Number(amount) then
            GameTooltip:AddDoubleLine("Current", MoneyText(amount))
            local baseline = SessionBaseline()
            if baseline then
                local delta = amount - baseline
                GameTooltip:AddDoubleLine("Since login", (delta > 0 and "+" or delta < 0 and "−" or "")
                    .. MoneyText(math.abs(delta)))
            end
        end
    elseif key == "latency" then
        local home, world = S.ReadInfoSource("latency")
        if Number(home) and Number(world) then GameTooltip:AddDoubleLine("Home / World", math.floor(home + .5) .. " / " .. math.floor(world + .5) .. " ms") end
    elseif key == "xp" then
        local level, current, maximum = S.ReadInfoSource("xp")
        if Number(level) and Number(current) and Number(maximum) then
            GameTooltip:AddDoubleLine("Level " .. level, current .. " / " .. maximum)
        end
    else
        GameTooltip:AddLine(button.text or "—", 1, 1, 1)
    end
    GameTooltip:Show()
end
local function Click(button)
    if NS.IsCombatLocked() or not button.source then return end
    local name = CLICK[button.source]
    if name and type(_G[name]) == "function" then _G[name]()
    elseif button.source == "durability" and type(ToggleCharacter) == "function" then ToggleCharacter("PaperDollFrame")
    elseif button.source == "clock" and type(ToggleCalendar) == "function" then ToggleCalendar() end
end
local function HideTooltip(button)
    if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end
local function CreateBar(index)
    if M.bars[index] then return M.bars[index] end
    local frame = S.CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    local background = S.CreateTexture(frame, nil, "BACKGROUND")
    background:SetAllPoints(frame)
    local top = S.CreateTexture(frame, nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    local bottom = S.CreateTexture(frame, nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    local left = S.CreateTexture(frame, nil, "BORDER")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    local right = S.CreateTexture(frame, nil, "BORDER")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
    local accent = S.CreateTexture(frame, nil, "ARTWORK")
    accent:SetPoint("BOTTOMLEFT"); accent:SetPoint("BOTTOMRIGHT"); accent:SetHeight(1)
    local bar = { frame = frame, background = background, border = { top, bottom, left, right },
        accent = accent, dividers = {}, slots = {}, index = index }
    M.bars[index] = bar
    for slot = 1, 6 do
        local button = S.CreateFrame("Button", nil, frame)
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", Click)
        button:SetScript("OnEnter", function(self)
            if M.config["bar" .. index .. "Visibility"] == 4 then
                bar.hover = true; frame:SetAlpha(1); M:Rebind()
            end
            Tooltip(self)
        end)
        button:SetScript("OnLeave", function(self)
            HideTooltip(self)
            if M.config["bar" .. index .. "Visibility"] == 4 and not frame:IsMouseOver() then
                bar.hover = false; frame:SetAlpha(0); M:Rebind()
            end
        end)
        local text = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", button, "LEFT", 5, 0)
        text:SetPoint("RIGHT", button, "RIGHT", -5, 0)
        text:SetJustifyH("CENTER")
        text:SetWordWrap(false)
        button.label = text
        bar.slots[slot] = button
    end
    frame:SetScript("OnEnter", function()
        if M.config["bar" .. index .. "Visibility"] == 4 then
            bar.hover = true; frame:SetAlpha(1); M:Rebind()
        end
    end)
    frame:SetScript("OnLeave", function()
        if M.config["bar" .. index .. "Visibility"] == 4 and not frame:IsMouseOver() then
            bar.hover = false; frame:SetAlpha(0); M:Rebind()
        end
    end)
    frame:SetScript("OnShow", function() if not M.styling then M:Rebind() end end)
    frame:SetScript("OnHide", function() if not M.styling then M:Rebind() end end)
    return bar
end
local function Visible(bar)
    if not bar.frame:IsVisible() then return false end
    if S.editMode then return true end
    local mode = M.config["bar" .. bar.index .. "Visibility"]
    if mode == 4 then return bar.hover == true end
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
            local r, g, b = RGB(style.backgroundColor)
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
local function Layout(bar)
    local c, prefix = M.config, "bar" .. bar.index
    local style = bar.style
    local visible = {}
    for i = 1, 6 do
        local button = bar.slots[i]
        if button.source then visible[#visible + 1] = button end
    end
    for _, divider in pairs(bar.dividers) do divider:Hide() end
    if #visible == 0 then return end
    local configuredWidth = c[prefix .. "Width"]
    local gaps = (#visible - 1) * style.gap
    local remaining, widths = configuredWidth - gaps, {}
    if c[prefix .. "Layout"] == 2 then
        local total = 0
        for i, button in ipairs(visible) do
            local measure = button.label.GetUnboundedStringWidth or button.label.GetStringWidth
            widths[i] = math.max(44, math.ceil(measure(button.label)) + 2 * style.padding)
            total = total + widths[i]
        end
        local needed = math.min(900, math.max(configuredWidth, total + gaps))
        if bar.frame:GetWidth() ~= needed then bar.frame:SetWidth(needed) end
        remaining = needed - gaps
        local ratio = remaining / total
        for i = 1, #widths do widths[i] = widths[i] * ratio end
    else
        if bar.frame:GetWidth() ~= configuredWidth then bar.frame:SetWidth(configuredWidth) end
        for i = 1, #visible do widths[i] = remaining / #visible end
    end
    local x = 0
    for i, button in ipairs(visible) do
        button:ClearAllPoints()
        button:SetPoint("LEFT", bar.frame, "LEFT", x, 0)
        button:SetSize(widths[i], c[prefix .. "Height"])
        local inset = math.max(0, math.min(style.padding, math.floor((widths[i] - 4) / 2)))
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", inset, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        x = x + widths[i]
        if i < #visible then
            if style.separatorEnabled then
                local divider = bar.dividers[i]
                if not divider then
                    divider = S.CreateTexture(bar.frame, nil, "ARTWORK")
                    bar.dividers[i] = divider
                    ApplyColor(divider, style.separatorColor, .8)
                end
                divider:ClearAllPoints()
                divider:SetPoint("CENTER", bar.frame, "LEFT", x + style.gap / 2, 0)
                divider:SetSize(style.separatorSize, math.max(6, c[prefix .. "Height"] - 2 * style.padding))
                divider:Show()
            end
            x = x + style.gap
        end
    end
end
function M:UpdateSource(key)
    if not self.activeSources or not self.activeSources[key] then return end
    local label, value, severity = Format(key)
    local previous = self.values[key]
    if previous and previous.label == label and previous.value == value and previous.severity == severity then return end
    self.values[key] = { label = label, value = value, severity = severity }
    for _, bar in pairs(self.bars) do
        if Visible(bar) then
            local relayout = false
            for i = 1, 6 do
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
            if relayout and self.config["bar" .. bar.index .. "Layout"] == 2 then Layout(bar) end
        end
    end
end
local function NextClock()
    local stamp = S.ReadInfoSource("clockStamp")
    return Number(stamp) and 60 - math.floor(stamp) % 60 or 60
end
function M:Schedule()
    if self.timer then self.timer:Cancel(); self.timer = nil end
    local now, soonest = Time(), nil
    for key in pairs(self.activeSources or {}) do
        if SAMPLED[key] then
            local due = self.due[key] or now
            if not soonest or due < soonest then soonest = due end
        end
    end
    if soonest then self.timer = S.ScheduleDataTick("datatexts", math.max(.05, soonest - now), function() self:Tick() end) end
end
function M:Tick()
    self.timer = nil
    local now = Time()
    for key in pairs(self.activeSources or {}) do
        if SAMPLED[key] and (self.due[key] or 0) <= now + .001 then
            self:UpdateSource(key)
            self.due[key] = now + (key == "clock" and NextClock() or INTERVAL[key])
        end
    end
    self:Schedule()
end
local function OnEvent(self, event, unit)
    if event == "PLAYER_XP_UPDATE" and unit and unit ~= "player" then return end
    local keys = EVENT_SOURCES[event]
    if event == "PLAYER_ENTERING_WORLD" then
        local invalidated = {}
        for key in pairs(self.activeSources or {}) do
            local raw = key == "sessionGold" and "gold" or key == "clock" and "clockTime" or key
            if not invalidated[raw] then S.InvalidateSharedData(raw); invalidated[raw] = true end
        end
        for key in pairs(self.activeSources or {}) do
            self:UpdateSource(key)
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        self:UpdateVisibility()
        return
    end
    if not keys then return end
    local invalidated = {}
    for i = 1, #keys do
        local key = keys[i]
        if self.activeSources and self.activeSources[key] then
            local raw = key == "sessionGold" and "gold" or key
            if not invalidated[raw] then S.InvalidateSharedData(raw); invalidated[raw] = true end
        end
    end
    for i = 1, #keys do
        local key = keys[i]
        if self.activeSources and self.activeSources[key] then
            self:UpdateSource(key)
            if key == "coordinates" then self.due[key] = Time() + INTERVAL.coordinates; self:Schedule() end
        end
    end
end
function M:Rebind()
    if not self.active or self.styling then return end
    local wanted, active = {}, {}
    for _, bar in pairs(self.bars) do
        if Visible(bar) then
            for i = 1, 6 do
                local key = bar.slots[i].source
                if key then active[key] = true end
            end
        end
    end
    self.activeSources = active
    for event, keys in pairs(EVENT_SOURCES) do
        for i = 1, #keys do if active[keys[i]] then wanted[event] = true; break end end
    end
    if next(active) then wanted.PLAYER_ENTERING_WORLD = true end
    for i = 1, 3 do
        local prefix = "bar" .. i
        if self.config[prefix .. "Enabled"] and (self.config[prefix .. "Visibility"] == 2
            or self.config[prefix .. "Visibility"] == 3) then
            wanted.PLAYER_REGEN_DISABLED = true
            wanted.PLAYER_REGEN_ENABLED = true
        end
    end
    for event in pairs(self.events) do
        if not wanted[event] then self.context:RemoveEvent(event); self.events[event] = nil end
    end
    for event in pairs(wanted) do
        if not self.events[event] then self.context:Event(event, OnEvent, true); self.events[event] = true end
    end
    for key in pairs(active) do
        self.values[key] = nil
        self.due[key] = nil
        self:UpdateSource(key)
        if SAMPLED[key] then self.due[key] = Time() + (key == "clock" and NextClock() or INTERVAL[key]) end
    end
    self:Schedule()
end
function M:UpdateVisibility()
    self.styling = true
    for i = 1, 3 do
        local bar = self.bars[i]
        if bar then
            local prefix, mode = "bar" .. i, self.config["bar" .. i .. "Visibility"]
            local enabled = self.config[prefix .. "Enabled"] == true
            local combat = NS.IsCombatLocked()
            if mode ~= 4 then bar.hover = false end
            bar.frame:SetShown(enabled and (S.editMode or mode ~= 2 and mode ~= 3
                or mode == 2 and not combat or mode == 3 and combat))
            bar.frame:SetAlpha((S.editMode or mode ~= 4 or bar.hover) and 1 or 0)
        end
    end
    self.styling = false
    self:Rebind()
end
function M:Refresh()
    self.styling = true
    self.values = {}
    local c = self.config
    for i = 1, 3 do
        local prefix = "bar" .. i
        if c[prefix .. "Enabled"] then
            local bar = CreateBar(i)
            local frame = bar.frame
            frame:ClearAllPoints()
            local point = NS.DataTextPoints[c[prefix .. "Point"]] or "BOTTOM"
            frame:SetPoint(point, UIParent, point, c[prefix .. "X"], c[prefix .. "Y"])
            frame:SetSize(c[prefix .. "Width"], c[prefix .. "Height"])
            bar.style = NS.DataTextEffectiveStyle(c, i)
            ApplyStyle(bar)
            local style = bar.style
            local font = S.ResolveFont(style.font) or FONT
            for slot = 1, 6 do
                local button = bar.slots[slot]
                local choice = c[prefix .. "Slot" .. slot]
                local key = NS.DataTextSourceKeys[choice]
                button.source, button.sourceIndex = SOURCES[key] and key or nil, choice
                button.text, button.display = nil, nil
                button:SetShown(button.source ~= nil)
                if button.source then
                    button.label:SetText("—")
                    S.SetFont(button.label, font, style.fontSize, OUTLINES[style.textOutline] or "OUTLINE")
                    button.label:SetJustifyH(ALIGN[style.textAlign] or "CENTER")
                    button.label:SetTextColor(1, 1, 1)
                end
            end
            Layout(bar)
        end
    end
    self.styling = false
    self:UpdateVisibility()
    self:RegisterMovers()
    SyncNativeBagBar()
end
function M:Enable()
    self:Refresh()
    SyncNativeBagBar()
    if NS.Client.isMainline then
        self.context:Event("ADDON_LOADED", function(_, _, addon)
            if addon == "Blizzard_MainMenuBarBagButtons" then SyncNativeBagBar() end
        end, true)
    end
end
function M:Disable()
    SyncNativeBagBar()
    if self.timer then self.timer:Cancel(); self.timer = nil end
    for event in pairs(self.events) do self.context:RemoveEvent(event); self.events[event] = nil end
    self.activeSources, self.values, self.due = nil, {}, {}
    for _, bar in pairs(self.bars) do bar.frame:Hide() end
    if GameTooltip and GameTooltip:GetOwner() then
        for _, bar in pairs(self.bars) do
            for i = 1, 6 do if GameTooltip:IsOwned(bar.slots[i]) then GameTooltip:Hide(); break end end
        end
    end
end
function M:RegisterMovers()
    for i = 1, 3 do
        local index, prefix = i, "bar" .. i
        S.RegisterOwnedMover(ID, prefix, {
            label = "DataTexts bar " .. i, order = 690 + i,
            getFrame = function() return self.bars[index] and self.bars[index].frame end,
            isEnabled = function() return self.config[prefix .. "Enabled"] == true end,
            xKey = prefix .. "X", yKey = prefix .. "Y", pointKey = prefix .. "Point",
            point = function() return NS.DataTextPoints[self.config[prefix .. "Point"]] or "BOTTOM" end,
            historyKeys = { prefix .. "Width", prefix .. "Height" },
            extraControls = {
                { id = "width", label = "Width", kind = "number", min = 180, max = 900, step = 5,
                    get = function() return S.Config(ID)[prefix .. "Width"] end,
                    set = function(value) return S.Set(ID, prefix .. "Width", value) end },
            },
        })
    end
end
S.Install(ID, M)
