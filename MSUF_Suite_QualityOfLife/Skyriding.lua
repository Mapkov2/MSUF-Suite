local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID = "skyriding"
local ASCENT, SECOND_WIND, SURGE = 372610, 425782, 361584
local RUN_SPEED = 7
local TICK_SECONDS = 0.1
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE" }
local BAR_TEXTURE = P.MSUF_BAR_TEXTURE
local FONT = P.MSUF_FONT
local PADDING = 12
local GetGlidingInfo = C_PlayerInfo and C_PlayerInfo.GetGlidingInfo
local GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local Public, RGB = S.Public, S.RGB
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local TEXT = {
    title = S.Text("SKYRIDING"),
    vigor = S.Text("VIGOR"),
    wind = S.Text("WIND"),
    speed = S.Text("SPEED"),
    surge = S.Text("SURGE"),
    preview = S.Text("PREVIEW"),
    flying = S.Text("IN FLIGHT"),
    ready = S.Text("READY"),
    thrill = S.Text("THRILL"),
    thrillSpeed = S.Text("THRILL SPEED"),
}

local function ContentTop(c) return -max(29, c.fontSize + 17) end
local function RowHeight(c) return c.fontSize + c.barHeight + 7 + c.rowGap end
local function SurgeLane(c)
    return c.showWhirlingSurge and max(48, c.fontSize * 3 + 14) or 0
end
local function ContentWidth(c)
    return c.width - PADDING * 2 - SurgeLane(c)
end

local function Paint(texture, hex, alpha)
    texture:SetColorTexture(RGB(hex))
    texture:SetAlpha(alpha or 1)
end

local function Finite(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Frequent redraws write a FontString only when its content changed.
local function SetText(fontString, text)
    if fontString.shownText ~= text then
        fontString.shownText = text
        fontString:SetText(text)
    end
end

local function Glide()
    if not GetGlidingInfo then return nil end
    local flying, capable, speed = GetGlidingInfo()
    if not Public(flying) or not Public(capable) then return nil end
    return flying == true, capable == true, Finite(speed) and max(0, speed) or nil
end

-- Charge and cooldown tables are read once per spell event and cached; the
-- 10 Hz tick only advances the cached recharge progress.
local function ReadCharges(row)
    row.dirty = false
    row.current, row.maximum, row.start, row.duration = nil, nil, nil, nil
    local info = GetSpellCharges and GetSpellCharges(row.spellID)
    if not Public(info) or type(info) ~= "table" then return end
    local current, maximum = info.currentCharges, info.maxCharges
    if not Finite(current) or not Finite(maximum) or maximum < 1 then return end
    current, maximum = max(0, floor(current)), floor(maximum)
    row.current, row.maximum = current, maximum
    local start, duration = info.cooldownStartTime, info.cooldownDuration
    if current < maximum and Finite(duration) and duration > 0 then
        row.duration = duration
        row.start = Finite(start) and start or nil
    end
end

-- surgeEnd: nil when unknown, 0 when ready, otherwise the cooldown end time.
local function ReadSurge(self)
    self.surgeDirty = false
    self.surgeEnd = nil
    local info = GetSpellCooldown and GetSpellCooldown(SURGE)
    if not Public(info) or type(info) ~= "table" then return end
    local start, duration = info.startTime, info.duration
    if not Finite(start) or not Finite(duration) then return end
    self.surgeEnd = duration > 1.5 and start + duration or 0
end

local function MarkSpellsDirty(self)
    self.vigor.dirty, self.wind.dirty, self.surgeDirty = true, true, true
end

local function NewBar(parent)
    local bar = S.CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(S.ResolveTexture("MSUF Lucent", BAR_TEXTURE))
    bar:SetMinMaxValues(0, 1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    bar.track = track
    return bar
end

local function NewRow(parent, label, count, spellID)
    local row = S.CreateFrame("Frame", nil, parent)
    row.spellID, row.dirty, row.shownCurrent = spellID, true, false
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(label)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    row.count:SetJustifyH("RIGHT")
    row.pips = {}
    for i = 1, count do row.pips[i] = NewBar(row) end
    return row
end

local function CreateEdges(host)
    local edges = {}
    for i = 1, 4 do edges[i] = host:CreateTexture(nil, "OVERLAY") end
    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")
    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT")
    edges[4]:SetPoint("TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT")
    return edges
end

local function CreateHeaderText(host, point, x, justify)
    local text = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint(point, host, point, x, -7)
    text:SetJustifyH(justify)
    return text
end

local function CreateSurge(self, host)
    local surge = S.CreateFrame("Frame", nil, host)
    local surgeLabel = surge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    surgeLabel:SetPoint("TOP", surge, "TOP", 0, 0)
    surgeLabel:SetText(TEXT.surge)
    local surgeTrack = surge:CreateTexture(nil, "BACKGROUND")
    surgeTrack:SetPoint("BOTTOM", surge, "BOTTOM", 0, -2)
    surgeTrack:SetSize(32, 32)
    local icon = surge:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("BOTTOM", surge, "BOTTOM", 0, 0)
    icon:SetSize(28, 28)
    local texture = GetSpellTexture and GetSpellTexture(SURGE)
    if Public(texture) and texture then icon:SetTexture(texture) end
    local surgeText = surge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    surgeText:SetPoint("CENTER", icon, "CENTER")
    self.surge, self.surgeLabel, self.surgeTrack, self.surgeIcon, self.surgeText =
        surge, surgeLabel, surgeTrack, icon, surgeText
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    local panel = host:CreateTexture(nil, "BACKGROUND")
    panel:SetAllPoints(host)
    local divider = host:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, -23)
    divider:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, -23)
    local title = CreateHeaderText(host, "TOPLEFT", PADDING, "LEFT")
    title:SetText(TEXT.title)
    local state = CreateHeaderText(host, "TOPRIGHT", -PADDING, "RIGHT")
    local vigor = NewRow(host, TEXT.vigor, 8, ASCENT)
    local wind = NewRow(host, TEXT.wind, 4, SECOND_WIND)
    local speed = NewBar(host)
    local speedText = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    speedText:SetText(TEXT.speed)
    speedText:SetPoint("BOTTOMLEFT", speed, "TOPLEFT", 0, 3)
    speedText:SetJustifyH("LEFT")
    local speedValue = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    speedValue:SetPoint("BOTTOMRIGHT", speed, "TOPRIGHT", 0, 3)
    speedValue:SetJustifyH("RIGHT")
    self.host, self.panel, self.edges, self.divider = host, panel, CreateEdges(host), divider
    self.title, self.state = title, state
    self.vigor, self.wind, self.rows = vigor, wind, { vigor, wind }
    self.speed, self.speedText, self.speedValue = speed, speedText, speedValue
    CreateSurge(self, host)
    self.labels = { title, state, vigor.label, vigor.count, wind.label, wind.count,
        speedText, speedValue, self.surgeLabel, self.surgeText }
end

local function Style(self)
    local c = self.config
    local texture = S.ResolveTexture(c.barTexture, BAR_TEXTURE)
    local font = S.ResolveFont(c.font) or FONT
    local flags = OUTLINES[c.fontOutline] or ""
    Paint(self.panel, c.panelColor, c.panelOpacity / 100)
    for _, edge in ipairs(self.edges) do Paint(edge, c.borderColor, c.borderSize > 0 and 1 or 0) end
    Paint(self.divider, c.borderColor, c.borderSize > 0 and 0.6 or 0)
    Paint(self.surgeTrack, c.trackColor, c.trackOpacity / 100)
    self.title:SetTextColor(RGB(c.accentColor))
    self.state:SetTextColor(RGB(c.mutedColor))
    self.vigor.label:SetTextColor(RGB(c.mutedColor))
    self.wind.label:SetTextColor(RGB(c.mutedColor))
    self.vigor.count:SetTextColor(RGB(c.accentColor))
    self.wind.count:SetTextColor(RGB(c.windColor))
    self.speedText:SetTextColor(RGB(c.mutedColor))
    self.speedValue:SetTextColor(RGB(c.textColor))
    self.surgeLabel:SetTextColor(RGB(c.mutedColor))
    self.surgeText:SetTextColor(RGB(c.textColor))
    for _, row in ipairs(self.rows) do
        local r, g, b = RGB(row == self.wind and c.windColor or c.accentColor)
        for _, pip in ipairs(row.pips) do
            pip:SetStatusBarTexture(texture)
            Paint(pip.track, c.trackColor, c.trackOpacity / 100)
            pip:SetStatusBarColor(r, g, b)
        end
    end
    self.speed:SetStatusBarTexture(texture)
    Paint(self.speed.track, c.trackColor, c.trackOpacity / 100)
    -- The speed bar switches between these two colors while flying.
    self.accentR, self.accentG, self.accentB = RGB(c.accentColor)
    self.thrillR, self.thrillG, self.thrillB = RGB(c.thrillColor)
    self.speed:SetStatusBarColor(self.accentR, self.accentG, self.accentB)
    self.speedThrill = false
    for _, label in ipairs(self.labels) do
        S.SetStyledFont(label, font, c.fontSize, flags, c.fontRendering,
            c.fontShadow, c.fontShadowOpacity, c.fontShadowDistance)
    end
end

local function LayoutRow(row, width, y, count, c)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", PADDING, y)
    row:SetSize(width, RowHeight(c))
    row.label:SetSize(width - 50, c.fontSize + 2)
    row.count:SetSize(48, c.fontSize + 2)
    local gap = 3
    local cellWidth = (width - gap * (count - 1)) / count
    for i, pip in ipairs(row.pips) do
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (cellWidth + gap), -(c.fontSize + 5))
        pip:SetSize(cellWidth, c.barHeight)
        pip:SetShown(i <= count)
    end
end

local function LayoutSpeed(self, contentWidth, y)
    local c, shown = self.config, self.config.showSpeed
    self.speed:SetShown(shown)
    self.speedText:SetShown(shown)
    self.speedValue:SetShown(shown)
    if not shown then return end
    self.speed:ClearAllPoints()
    self.speed:SetPoint("TOPLEFT", self.host, "TOPLEFT", PADDING, y - c.fontSize - 6)
    self.speed:SetSize(contentWidth, c.barHeight)
    self.speedText:SetSize(contentWidth - 70, c.fontSize + 2)
    self.speedValue:SetSize(68, c.fontSize + 2)
end

local function Layout(self)
    Create(self)
    local c, host = self.config, self.host
    local point = POINTS[c.point] or "CENTER"
    local contentTop, rowHeight = ContentTop(c), RowHeight(c)
    local surgeHeight = max(49, c.fontSize + 38)
    local y = contentTop
    if c.showSecondWind then y = y - rowHeight end
    if c.showVigor then y = y - rowHeight end
    if c.showSpeed then y = y - rowHeight end
    local height = max(-y + 10, c.showWhirlingSurge and (-contentTop + surgeHeight + 10) or 0)
    local contentWidth = ContentWidth(c)
    host:SetScale(c.scale / 100)
    host:SetSize(c.width, height)
    host:ClearAllPoints()
    host:SetPoint(point, UIParent, point, c.x, c.y)
    local pixel = 1 / max(0.1, host:GetEffectiveScale() or 1)
    local border = max(pixel, c.borderSize * pixel)
    self.edges[1]:SetHeight(border)
    self.edges[2]:SetHeight(border)
    self.edges[3]:SetWidth(border)
    self.edges[4]:SetWidth(border)
    self.divider:ClearAllPoints()
    self.divider:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, contentTop + 6)
    self.divider:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, contentTop + 6)
    self.divider:SetHeight(pixel)
    local headerWidth = c.width - PADDING * 2
    self.title:SetSize(headerWidth / 2 - 4, c.fontSize + 2)
    self.state:SetSize(headerWidth / 2 - 4, c.fontSize + 2)
    y = contentTop
    self.wind:SetShown(c.showSecondWind)
    if c.showSecondWind then
        LayoutRow(self.wind, contentWidth, y, self.windCount or 3, c)
        y = y - rowHeight
    end
    self.vigor:SetShown(c.showVigor)
    if c.showVigor then
        LayoutRow(self.vigor, contentWidth, y, self.vigorCount or 6, c)
        y = y - rowHeight
    end
    LayoutSpeed(self, contentWidth, y)
    self.surge:SetShown(c.showWhirlingSurge)
    self.surge:ClearAllPoints()
    self.surge:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, contentTop)
    self.surge:SetSize(SurgeLane(c) - 8, surgeHeight)
    self.surgeLabel:SetSize(SurgeLane(c) - 8, c.fontSize + 2)
    Style(self)
end

local function SetPip(pip, value, alpha)
    if pip.shownValue ~= value then
        pip.shownValue = value
        pip:SetValue(value)
    end
    if pip.shownAlpha ~= alpha then
        pip.shownAlpha = alpha
        pip:SetAlpha(alpha)
    end
end

-- Returns true while a charge is recharging (the tick must keep running).
local function DrawRow(self, row, preview, maxPips, now)
    local current, maximum, progress, recharging = nil, nil, 0, false
    local fallback = row == self.wind and 3 or 6
    if preview then
        maximum = fallback
        current, progress = maximum - 1, 0.5
    else
        if row.dirty then ReadCharges(row) end
        current, maximum = row.current, row.maximum
        if row.duration then
            recharging = true
            if row.start then
                progress = max(0, min(1, (now - row.start) / row.duration))
                -- A finished recharge normally arrives as a spell event; read
                -- again on the next tick in case that event was coalesced.
                if progress >= 1 then row.dirty = true end
            end
        end
    end
    local count = maximum and min(maxPips, maximum) or fallback
    local key = row == self.wind and "windCount" or "vigorCount"
    if self[key] ~= count then
        self[key] = count
        local c = self.config
        local top = ContentTop(c)
        LayoutRow(row, ContentWidth(c), row == self.wind and top
            or (c.showSecondWind and top - RowHeight(c) or top), count, c)
    end
    local alpha = current and 1 or 0.35
    for i = 1, count do
        local value = 0
        if current then value = i <= current and 1 or (i == current + 1 and progress or 0) end
        SetPip(row.pips[i], value, alpha)
    end
    if row.shownCurrent ~= current or row.shownMaximum ~= maximum then
        row.shownCurrent, row.shownMaximum = current, maximum
        row.count:SetText(current and (current .. "/" .. maximum) or "--")
    end
    return recharging
end

local function DrawSpeed(self, flying, speed, preview)
    local c = self.config
    local percent = preview and 760 or (speed and speed / RUN_SPEED * 100)
    if not flying and not preview then percent = 0 end
    local fraction = percent and max(0, min(1, percent / c.speedMax)) or 0
    if self.speedFraction ~= fraction then
        self.speedFraction = fraction
        self.speed:SetValue(fraction)
    end
    local rounded = percent and floor(percent + 0.5) or false
    if self.speedRounded ~= rounded then
        self.speedRounded = rounded
        self.speedValue:SetText(rounded and ("%d%%"):format(rounded) or "--")
    end
    local thrill = percent and percent >= c.thrillSpeed or false
    if self.speedThrill ~= thrill then
        self.speedThrill = thrill
        if thrill then
            self.speed:SetStatusBarColor(self.thrillR, self.thrillG, self.thrillB)
        else
            self.speed:SetStatusBarColor(self.accentR, self.accentG, self.accentB)
        end
    end
    if thrill and not preview then
        return (c.width < 300 or c.fontSize >= 16) and TEXT.thrill or TEXT.thrillSpeed
    end
end

-- Returns true while the cooldown is counting down.
local function DrawSurge(self, preview, now)
    local remaining
    if preview then
        remaining = 12
    else
        if self.surgeDirty then ReadSurge(self) end
        local finish = self.surgeEnd
        if finish then remaining = finish > 0 and max(0, finish - now) or 0 end
    end
    local seconds = remaining and ceil(remaining) or false
    if self.surgeSeconds ~= seconds then
        self.surgeSeconds = seconds
        self.surgeText:SetText(seconds and (seconds > 0 and tostring(seconds) or "") or "--")
        self.surgeIcon:SetAlpha(seconds and (seconds > 0 and 0.45 or 1) or 0.35)
    end
    return remaining ~= nil and remaining > 0
end

local function SyncSpellEvents(self, visible, preview)
    local c, context = self.config, self.context
    local watchCharges = visible and not preview and (c.showVigor or c.showSecondWind)
    local watchCooldown = visible and not preview and c.showWhirlingSurge
    if watchCharges ~= self.watchCharges then
        self.watchCharges = watchCharges
        if watchCharges then
            -- Cached charges went stale while nobody listened.
            self.vigor.dirty, self.wind.dirty = true, true
            context:Event("SPELL_UPDATE_CHARGES", M.ChargesChanged, true)
        else
            context:RemoveEvent("SPELL_UPDATE_CHARGES")
        end
    end
    if watchCooldown ~= self.watchCooldown then
        self.watchCooldown = watchCooldown
        if watchCooldown then
            self.surgeDirty = true
            context:Event("SPELL_UPDATE_COOLDOWN", M.CooldownChanged, true)
        else
            context:RemoveEvent("SPELL_UPDATE_COOLDOWN")
        end
    end
end

local Update
local function Tick(_, elapsed)
    local self = M
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= TICK_SECONDS then
        self.elapsed = 0
        Update(self)
    end
end

local function SetTicking(self, ticking)
    if self.ticking == ticking then return end
    self.ticking, self.elapsed = ticking, 0
    self.host:SetScript("OnUpdate", ticking and Tick or nil)
end

Update = function(self)
    if not self.active then return end
    local c = self.config
    local flying, capable, speed = Glide()
    local preview = S.editMode == true
    local visible = preview or (capable == true and (not c.airborneOnly or flying == true))
    self.host:SetShown(visible)
    SyncSpellEvents(self, visible, preview)
    if not visible then
        SetTicking(self, false)
        return
    end
    local now = GetTime()
    local ticking = c.showSpeed and flying == true
    if c.showSecondWind then ticking = DrawRow(self, self.wind, preview, 4, now) or ticking end
    if c.showVigor then ticking = DrawRow(self, self.vigor, preview, 8, now) or ticking end
    local state = preview and TEXT.preview or (flying and TEXT.flying or TEXT.ready)
    if c.showSpeed then state = DrawSpeed(self, flying, speed, preview) or state end
    SetText(self.state, state)
    if c.showWhirlingSurge then ticking = DrawSurge(self, preview, now) or ticking end
    SetTicking(self, ticking and not preview)
end

-- Spell events only invalidate caches while the tick runs: the next tick
-- (at most 0.1 s later) draws them.
function M.ChargesChanged()
    M.vigor.dirty, M.wind.dirty = true, true
    if not M.ticking then Update(M) end
end

function M.CooldownChanged()
    M.surgeDirty = true
    if not M.ticking then Update(M) end
end

local function GlideChanged()
    MarkSpellsDirty(M)
    Update(M)
end

function M:Enable()
    Layout(self)
    local context = self.context
    context:Event("PLAYER_ENTERING_WORLD", GlideChanged, true)
    context:Event("PLAYER_CAN_GLIDE_CHANGED", GlideChanged, true)
    context:Event("PLAYER_IS_GLIDING_CHANGED", GlideChanged, true)
    context:Event("PLAYER_MOUNT_DISPLAY_CHANGED", GlideChanged, true)
    GlideChanged()
    self:RegisterMovers()
end

function M:Refresh()
    Layout(self)
    GlideChanged()
end

function M:Disable()
    if self.context then
        self.context:RemoveEvent("SPELL_UPDATE_CHARGES")
        self.context:RemoveEvent("SPELL_UPDATE_COOLDOWN")
    end
    self.watchCharges, self.watchCooldown = false, false
    if self.host then
        SetTicking(self, false)
        self.host:Hide()
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "flight", {
        label = "Skyriding HUD", order = 640, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        historyKeys = { "width", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 220, max = 600, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
        },
    })
end

S.Install(ID, M)
