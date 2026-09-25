local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID = "skyriding"
local ASCENT, SECOND_WIND, SURGE = 372610, 425782, 361584
local RUN_SPEED = 7
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local BAR_TEXTURE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga"
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local PADDING = 12

local function ContentTop(c) return -math.max(29, c.fontSize + 17) end
local function RowHeight(c) return c.fontSize + c.barHeight + 7 + c.rowGap end
local function SurgeLane(c)
    return c.showWhirlingSurge and math.max(48, c.fontSize * 3 + 14) or 0
end

local function RGB(hex)
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

local function Paint(texture, hex, alpha)
    texture:SetColorTexture(RGB(hex))
    texture:SetAlpha(alpha or 1)
end

local function Tint(bar, hex)
    bar:SetStatusBarColor(RGB(hex))
end

local function Finite(value)
    return S.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Glide()
    local ok, flying, capable, speed = pcall(C_PlayerInfo.GetGlidingInfo)
    if not ok or not S.Public(flying) or not S.Public(capable) then return nil end
    return flying == true, capable == true, Finite(speed) and math.max(0, speed) or nil
end

local function Charges(spellID)
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or not S.Public(info) or type(info) ~= "table" then return nil end
    local current, maximum = info.currentCharges, info.maxCharges
    if not Finite(current) or not Finite(maximum) or maximum < 1 then return nil end
    current, maximum = math.max(0, math.floor(current)), math.floor(maximum)
    local progress = 0
    local start, duration = info.cooldownStartTime, info.cooldownDuration
    if current < maximum and Finite(start) and Finite(duration) and duration > 0 then
        progress = math.max(0, math.min(1, (GetTime() - start) / duration))
    end
    return current, maximum, progress, current < maximum and Finite(duration) and duration > 0
end

local function SurgeCooldown()
    if type(C_Spell.GetSpellCooldown) ~= "function" then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, SURGE)
    if not ok or not S.Public(info) or type(info) ~= "table" then return nil end
    local start, duration = info.startTime, info.duration
    if not Finite(start) or not Finite(duration) then return nil end
    if duration <= 1.5 then return 0 end
    return math.max(0, start + duration - GetTime())
end

local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(type(S.ResolveTexture) == "function" and S.ResolveTexture("MSUF Lucent", BAR_TEXTURE) or BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    bar.track = track
    return bar
end

local function NewRow(parent, label, count)
    local row = CreateFrame("Frame", nil, parent)
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

local function Create(self)
    if self.host then return end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    local panel = host:CreateTexture(nil, "BACKGROUND")
    panel:SetAllPoints(host)
    local edges = {}
    for i = 1, 4 do edges[i] = host:CreateTexture(nil, "OVERLAY") end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT")
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT")
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT")
    local divider = host:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, -23)
    divider:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, -23)
    local title = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetText("SKYRIDING")
    title:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, -7)
    title:SetJustifyH("LEFT")
    local state = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    state:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, -7)
    state:SetJustifyH("RIGHT")
    local vigor = NewRow(host, "VIGOR", 8)
    local wind = NewRow(host, "WIND", 4)
    local speed = NewBar(host)
    local speedText = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    speedText:SetText("SPEED")
    speedText:SetPoint("BOTTOMLEFT", speed, "TOPLEFT", 0, 3)
    speedText:SetJustifyH("LEFT")
    local speedValue = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    speedValue:SetPoint("BOTTOMRIGHT", speed, "TOPRIGHT", 0, 3)
    speedValue:SetJustifyH("RIGHT")
    local surge = CreateFrame("Frame", nil, host)
    local surgeLabel = surge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    surgeLabel:SetPoint("TOP", surge, "TOP", 0, 0)
    surgeLabel:SetText("SURGE")
    local surgeTrack = surge:CreateTexture(nil, "BACKGROUND")
    surgeTrack:SetPoint("BOTTOM", surge, "BOTTOM", 0, -2)
    surgeTrack:SetSize(32, 32)
    local icon = surge:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("BOTTOM", surge, "BOTTOM", 0, 0)
    icon:SetSize(28, 28)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, texture = pcall(C_Spell.GetSpellTexture, SURGE)
        if ok and S.Public(texture) and texture then icon:SetTexture(texture) end
    end
    local surgeText = surge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    surgeText:SetPoint("CENTER", icon, "CENTER")
    self.host, self.panel, self.edges, self.divider = host, panel, edges, divider
    self.title, self.state = title, state
    self.vigor, self.wind, self.speed, self.speedText, self.speedValue = vigor, wind, speed, speedText, speedValue
    self.surge, self.surgeLabel, self.surgeTrack, self.surgeIcon, self.surgeText =
        surge, surgeLabel, surgeTrack, icon, surgeText
end

local function Style(self)
    local c = self.config
    local texture = type(S.ResolveTexture) == "function" and S.ResolveTexture(c.barTexture, BAR_TEXTURE) or BAR_TEXTURE
    local font = type(S.ResolveFont) == "function" and S.ResolveFont(c.font) or nil
    font = font or FONT
    local flags = ({ "", "OUTLINE", "THICKOUTLINE" })[c.fontOutline] or ""
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
    for _, row in ipairs({ self.vigor, self.wind }) do
        for _, pip in ipairs(row.pips) do
            pip:SetStatusBarTexture(texture)
            Paint(pip.track, c.trackColor, c.trackOpacity / 100)
            Tint(pip, row == self.wind and c.windColor or c.accentColor)
        end
    end
    self.speed:SetStatusBarTexture(texture)
    Paint(self.speed.track, c.trackColor, c.trackOpacity / 100)
    Tint(self.speed, c.accentColor)
    if type(S.SetFont) == "function" then
        for _, label in ipairs({ self.title, self.state, self.vigor.label, self.vigor.count,
            self.wind.label, self.wind.count, self.speedText, self.speedValue, self.surgeLabel, self.surgeText }) do
            S.SetStyledFont(label, font, c.fontSize, flags, c.fontRendering,
                c.fontShadow, c.fontShadowOpacity, c.fontShadowDistance)
        end
    end
    self.look = { accent = c.accentColor, thrill = c.thrillColor }
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

local function ContentWidth(config)
    return config.width - PADDING * 2 - SurgeLane(config)
end

local function Layout(self)
    Create(self)
    local c, host = self.config, self.host
    local point = POINTS[c.point] or "CENTER"
    local contentTop, rowHeight = ContentTop(c), RowHeight(c)
    local surgeHeight = math.max(49, c.fontSize + 38)
    local y = contentTop
    if c.showSecondWind then y = y - rowHeight end
    if c.showVigor then y = y - rowHeight end
    if c.showSpeed then y = y - rowHeight end
    local height = math.max(-y + 10, c.showWhirlingSurge and (-contentTop + surgeHeight + 10) or 0)
    local contentWidth = ContentWidth(c)
    host:SetScale(c.scale / 100)
    host:SetSize(c.width, height)
    host:ClearAllPoints()
    host:SetPoint(point, UIParent, point, c.x, c.y)
    local pixel = 1 / math.max(0.1, host:GetEffectiveScale() or 1)
    local border = math.max(pixel, c.borderSize * pixel)
    self.edges[1]:SetHeight(border); self.edges[2]:SetHeight(border)
    self.edges[3]:SetWidth(border); self.edges[4]:SetWidth(border)
    self.divider:ClearAllPoints()
    self.divider:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, contentTop + 6)
    self.divider:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, contentTop + 6)
    self.divider:SetHeight(pixel)
    local headerWidth = c.width - PADDING * 2
    self.title:SetSize(headerWidth / 2 - 4, c.fontSize + 2)
    self.state:SetSize(headerWidth / 2 - 4, c.fontSize + 2)
    y = contentTop
    self.wind:SetShown(c.showSecondWind)
    if c.showSecondWind then LayoutRow(self.wind, contentWidth, y, self.windCount or 3, c); y = y - rowHeight end
    self.vigor:SetShown(c.showVigor)
    if c.showVigor then LayoutRow(self.vigor, contentWidth, y, self.vigorCount or 6, c); y = y - rowHeight end
    self.speed:SetShown(c.showSpeed)
    self.speedText:SetShown(c.showSpeed)
    self.speedValue:SetShown(c.showSpeed)
    if c.showSpeed then
        self.speed:ClearAllPoints()
        self.speed:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, y - c.fontSize - 6)
        self.speed:SetSize(contentWidth, c.barHeight)
        self.speedText:SetSize(contentWidth - 70, c.fontSize + 2)
        self.speedValue:SetSize(68, c.fontSize + 2)
    end
    self.surge:SetShown(c.showWhirlingSurge)
    self.surge:ClearAllPoints()
    self.surge:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PADDING, contentTop)
    self.surge:SetSize(SurgeLane(c) - 8, surgeHeight)
    self.surgeLabel:SetSize(SurgeLane(c) - 8, c.fontSize + 2)
    Style(self)
end

local function DrawRow(self, row, spellID, preview, maxPips)
    local current, maximum, progress, recharging
    if preview then
        maximum = spellID == SECOND_WIND and 3 or 6
        current, progress = maximum - 1, 0.5
    else
        current, maximum, progress, recharging = Charges(spellID)
    end
    local count = maximum and math.min(maxPips, maximum) or (spellID == SECOND_WIND and 3 or 6)
    local key = spellID == SECOND_WIND and "windCount" or "vigorCount"
    if self[key] ~= count then
        self[key] = count
        local c = self.config
        LayoutRow(row, ContentWidth(c),
            spellID == SECOND_WIND and ContentTop(c) or
                (c.showSecondWind and ContentTop(c) - RowHeight(c) or ContentTop(c)), count, c)
    end
    for i, pip in ipairs(row.pips) do
        if i <= count then
            pip:SetValue(not current and 0 or (i <= current and 1 or (i == current + 1 and progress or 0)))
            pip:SetAlpha(current and 1 or 0.35)
        end
    end
    row.count:SetText(current and (current .. "/" .. maximum) or "--")
    return recharging == true
end

local function SyncSpellEvents(self, visible, preview)
    local watchCharges = visible and not preview and (self.config.showVigor or self.config.showSecondWind)
    local watchCooldown = visible and not preview and self.config.showWhirlingSurge
    local context = self.context
    if watchCharges ~= self.watchCharges then
        self.watchCharges = watchCharges
        if watchCharges then context:Event("SPELL_UPDATE_CHARGES", self.spellChanged, true)
        else context:RemoveEvent("SPELL_UPDATE_CHARGES") end
    end
    if watchCooldown ~= self.watchCooldown then
        self.watchCooldown = watchCooldown
        if watchCooldown then context:Event("SPELL_UPDATE_COOLDOWN", self.spellChanged, true)
        else context:RemoveEvent("SPELL_UPDATE_COOLDOWN") end
    end
end

local function Update(self)
    if not self.active then return end
    local flying, capable, speed = Glide()
    local preview = S.editMode == true
    local visible = preview or (capable == true and (not self.config.airborneOnly or flying == true))
    self.host:SetShown(visible)
    SyncSpellEvents(self, visible, preview)
    if not visible then self.host:SetScript("OnUpdate", nil); self.ticking = false; return end
    self.state:SetText(preview and "PREVIEW" or (flying and "IN FLIGHT" or "READY"))
    local ticking = self.config.showSpeed and flying == true
    if self.config.showSecondWind then
        ticking = DrawRow(self, self.wind, SECOND_WIND, preview, 4) or ticking
    end
    if self.config.showVigor then
        ticking = DrawRow(self, self.vigor, ASCENT, preview, 8) or ticking
    end
    if self.config.showSpeed then
        local percent = preview and 760 or (speed and speed / RUN_SPEED * 100)
        if not flying and not preview then percent = 0 end
        local fraction = percent and math.max(0, math.min(1, percent / self.config.speedMax)) or 0
        self.speed:SetValue(fraction)
        self.speedValue:SetText(percent and ("%d%%"):format(math.floor(percent + 0.5)) or "--")
        Tint(self.speed, percent and percent >= self.config.thrillSpeed and self.look.thrill or self.look.accent)
        if percent and percent >= self.config.thrillSpeed and not preview then
            self.state:SetText((self.config.width < 300 or self.config.fontSize >= 16)
                and "THRILL" or "THRILL SPEED")
        end
    end
    if self.config.showWhirlingSurge then
        local remaining = preview and 12 or SurgeCooldown()
        self.surgeText:SetText(remaining and (remaining > 0 and tostring(math.ceil(remaining)) or "") or "--")
        self.surgeIcon:SetAlpha(remaining and (remaining > 0 and 0.45 or 1) or 0.35)
        ticking = (remaining and remaining > 0) or ticking
    end
    if ticking and not preview then
        if not self.ticking then
            self.host:SetScript("OnUpdate", function(_, elapsed)
                self.elapsed = (self.elapsed or 0) + elapsed
                if self.elapsed >= 0.1 then self.elapsed = 0; Update(self) end
            end)
            self.ticking = true
        end
    elseif self.ticking then
        self.host:SetScript("OnUpdate", nil)
        self.ticking = false
    end
end

function M:Enable()
    Layout(self)
    local context = self.context
    local function Changed() Update(self) end
    self.spellChanged = Changed
    context:Event("PLAYER_ENTERING_WORLD", Changed, true)
    context:Event("PLAYER_CAN_GLIDE_CHANGED", Changed, true)
    context:Event("PLAYER_IS_GLIDING_CHANGED", Changed, true)
    context:Event("PLAYER_MOUNT_DISPLAY_CHANGED", Changed, true)
    Update(self)
    self:RegisterMovers()
end

function M:Refresh()
    Layout(self)
    Update(self)
end

function M:Disable()
    if self.context then
        self.context:RemoveEvent("SPELL_UPDATE_CHARGES")
        self.context:RemoveEvent("SPELL_UPDATE_COOLDOWN")
    end
    self.watchCharges, self.watchCooldown = false, false
    if self.host then self.host:SetScript("OnUpdate", nil); self.host:Hide() end
    self.ticking, self.elapsed = false, 0
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
