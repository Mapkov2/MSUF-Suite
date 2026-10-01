local _, P = ...
local NS, S = P.NS, P.Suite
local ID, M = "threatMeter", { units = {}, unitSet = {}, enemies = {}, records = {}, pools = {}, windows = {} }
-- Threat changes arrive in bursts during raid pulls; the meter repaints at
-- most this often instead of on every event.
local UPDATE_DELAY = .2
local MAX_ROWS = 20
-- windows: 1 target, 2 focus, 3 target and a second window for the focus.
local TARGET, FOCUS, BOTH = 1, 2, 3

local function Enemy(scope)
    if not S.Public(UnitExists(scope)) or not UnitExists(scope) then return end
    local hostile = UnitCanAttack("player", scope)
    if S.Public(hostile) and hostile then return scope end
    local friendly = UnitCanAssist("player", scope)
    if S.Public(friendly) and friendly then
        local unit = scope .. "target"
        local exists, attack = UnitExists(unit), UnitCanAttack("player", unit)
        if S.Public(exists) and exists and S.Public(attack) and attack then return unit end
    end
end

local function Roster(self)
    wipe(self.units)
    wipe(self.unitSet)
    local raid = IsInRaid()
    local count = GetNumGroupMembers()
    if not S.Public(raid) or not S.Finite(count) then return end
    if raid then
        for i = 1, math.min(40, count) do
            self.units[#self.units + 1] = "raid" .. i
            if self.config.includePets then self.units[#self.units + 1] = "raidpet" .. i end
        end
    else
        self.units[1] = "player"
        if self.config.includePets then self.units[#self.units + 1] = "pet" end
        for i = 1, math.min(4, math.max(0, count - 1)) do
            self.units[#self.units + 1] = "party" .. i
            if self.config.includePets then self.units[#self.units + 1] = "partypet" .. i end
        end
    end
    for _, unit in ipairs(self.units) do self.unitSet[unit] = true end
end

local function Descending(a, b)
    if a.threat == b.threat then return a.unit < b.unit end
    return a.threat > b.threat
end

local function NewWindow(self, key)
    local host = S.CreateFrame("Frame", nil, UIParent)
    -- The wheel scrolls only while more members are listed than rows fit
    -- (SetWheel); otherwise it stays with the camera.
    host:SetScript("OnMouseWheel", function(_, delta)
        host.offset = math.max(0, math.min(math.max(0, (host.total or 0) - self.config.rows), (host.offset or 0) - delta))
        self:Update()
    end)
    host.title = S.CreateFontString(host, nil, "OVERLAY")
    host.title:SetPoint("TOPLEFT", 4, -3)
    host.rows = {}
    for i = 1, MAX_ROWS do
        local bar = S.CreateFrame("StatusBar", nil, host)
        bar:SetStatusBarTexture(NS.MSUFMedia.barTexture)
        bar:SetMinMaxValues(0, 1)
        bar.background = S.CreateTexture(bar, nil, "BACKGROUND")
        bar.background:SetAllPoints(); bar.background:SetColorTexture(.05, .06, .08, .85)
        bar.text = S.CreateFontString(bar, nil, "OVERLAY")
        bar.text:SetPoint("LEFT", 4, 0); bar.text:SetPoint("RIGHT", -4, 0)
        bar.marker = S.CreateTexture(bar, nil, "OVERLAY")
        bar.marker:SetColorTexture(1, .25, .15, 1)
        host.rows[i] = bar
    end
    self.windows[key] = host
    return host
end

local function SetWheel(host, wanted)
    if host.wheel == wanted then return end
    host.wheel = wanted
    host:EnableMouseWheel(wanted)
end

local function Layout(self, key, host)
    local c = self.config
    if host.layoutSerial == self.layoutSerial then return end
    host.layoutSerial = self.layoutSerial
    host:SetScale(c.scale / 100); host:SetSize(c.width, 23 + c.rows * (c.rowHeight + 2))
    host:ClearAllPoints(); host:SetPoint("CENTER", UIParent, "CENTER", c[key .. "X"], c[key .. "Y"])
    local font = S.GlobalFontPath()
    S.SetStyledFont(host.title, font, c.fontSize, "OUTLINE", 1, true, 80, 1)
    for i, bar in ipairs(host.rows) do
        bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -23 - (i - 1) * (c.rowHeight + 2))
        bar:SetSize(c.width, c.rowHeight)
        S.SetStyledFont(bar.text, font, c.fontSize, "OUTLINE", 1, true, 80, 1)
    end
end

-- Readable threat rows for one enemy, highest first. Returns the highest
-- threat, the player's share of the pull threshold and that threshold.
local function Collect(self, key, enemy)
    local data = self.records[key]
    if not data then data = {}; self.records[key] = data end
    local pool = self.pools[key]
    if not pool then pool = {}; self.pools[key] = pool end
    wipe(data)
    local highest, playerScaled, threshold = 0, nil, nil
    if enemy then
        for _, unit in ipairs(self.units) do
            local exists = UnitExists(unit)
            if S.Public(exists) and exists then
                local tanking, _, scaled, raw, amount = UnitDetailedThreatSituation(unit, enemy)
                if S.Finite(amount) and amount >= 0 and S.Finite(scaled) and S.Finite(raw) then
                    local row = pool[unit]
                    if not row then row = {}; pool[unit] = row end
                    row.unit, row.threat, row.scaled, row.raw = unit, amount, scaled, raw
                    row.tanking = S.Public(tanking) and tanking
                    data[#data + 1] = row
                    highest = math.max(highest, amount)
                    local own = UnitIsUnit(unit, "player")
                    if S.Public(own) and own and S.Public(tanking) and tanking == false then
                        playerScaled = scaled
                        if scaled > 0 then threshold = amount * 100 / scaled end
                    end
                end
            end
        end
    elseif S.editMode then
        data[1] = { unit = "player", threat = 9000, scaled = 90, raw = 99, tanking = false }
        highest, threshold = 10000, 10000
    end
    table.sort(data, Descending)
    return data, highest, playerScaled, threshold
end

local function ValueText(c, record)
    if c.numberMode == 2 then return S.Text("%.1f%% of tank"):format(record.raw) end
    if c.numberMode == 3 then return S.Text("%.1f%% of pull"):format(record.scaled) end
    return string.format("%.0f", record.threat)
end

local function PaintRows(self, host, data, maximum, threshold)
    local c = self.config
    for i, bar in ipairs(host.rows) do
        local record = i <= c.rows and data[i + host.offset]
        bar:SetShown(record ~= nil and record ~= false)
        if record then
            bar:SetValue(record.threat / maximum)
            local _, class = UnitClass(record.unit)
            local color = S.Public(class) and RAID_CLASS_COLORS[class]
            bar:SetStatusBarColor(color and color.r or .45, color and color.g or .65, color and color.b or .9)
            local name = UnitName(record.unit)
            bar.text:SetText((S.Public(name) and name or "--") .. "  " .. ValueText(c, record))
            local marker = c.showThreshold and threshold and threshold > 0
            bar.marker:SetShown(marker == true)
            if marker then
                bar.marker:ClearAllPoints(); bar.marker:SetPoint("LEFT", bar, "LEFT", c.width * math.min(1, threshold / maximum), 0)
                bar.marker:SetSize(2, c.rowHeight)
            end
        end
    end
end

-- One sound when your share of the pull threshold first reaches the alert.
local function Alert(self, playerScaled)
    local at = self.config.pullAlert
    if S.editMode or at <= 0 then self.alerted = false; return end
    local reached = playerScaled ~= nil and playerScaled >= at
    if reached and not self.alerted then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    self.alerted = reached
end

local function Paint(self, key, scope)
    local c, host = self.config, self.windows[key] or NewWindow(self, key)
    local enemy = Enemy(scope)
    self.enemies[key] = enemy
    host:SetShown(enemy ~= nil or S.editMode == true)
    Layout(self, key, host)
    host.title:SetText(S.Text(key == "focus" and "Focus threat" or "Threat") .. "  "
        .. (enemy and (S.Public(UnitName(enemy)) and UnitName(enemy) or "--") or S.Text("Preview")))
    local data, highest, playerScaled, threshold = Collect(self, key, enemy)
    host.total = #data
    host.offset = math.max(0, math.min(host.offset or 0, math.max(0, #data - c.rows)))
    SetWheel(host, #data > c.rows)
    PaintRows(self, host, data, math.max(1, highest, c.showThreshold and threshold or 0), threshold)
    if key == "main" then Alert(self, playerScaled) end
end

function M:Update()
    if not self.active then return end
    local mode = self.config.windows
    Paint(self, "main", mode == FOCUS and "focus" or "target")
    if mode == BOTH then Paint(self, "focus", "focus")
    elseif self.windows.focus then self.windows.focus:Hide(); self.enemies.focus = nil end
end

local function Relevant(self, event, unit)
    if event == "UNIT_TARGET" then return S.Public(unit) and (unit == "target" or unit == "focus") end
    if event ~= "UNIT_THREAT_LIST_UPDATE" and event ~= "UNIT_THREAT_SITUATION_UPDATE" and event ~= "UNIT_PET" then
        return true
    end
    if not S.Public(unit) or type(unit) ~= "string" then return false end
    if event ~= "UNIT_THREAT_LIST_UPDATE" and (self.unitSet[unit] or unit == "player") then return true end
    for _, enemy in pairs(self.enemies) do
        local match = UnitIsUnit(unit, enemy)
        if S.Public(match) and match then return true end
    end
    return false
end

local function Changed(self, event, unit)
    if not Relevant(self, event, unit) then return end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then self.alerted = false end
    if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then Roster(self) end
    if self.pending then return end
    self.pending = true
    C_Timer.After(UPDATE_DELAY, self.flush)
end

function M:Enable()
    self.layoutSerial = (self.layoutSerial or 0) + 1
    self.generation = (self.generation or 0) + 1
    local generation = self.generation
    self.flush = function()
        if generation ~= self.generation then return end
        self.pending = false
        if self.active then self:Update() end
    end
    Roster(self)
    for _, event in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "GROUP_ROSTER_UPDATE", "UNIT_PET",
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "PLAYER_ENTERING_WORLD" }) do
        self.context:Event(event, Changed, true)
    end
    self:Update(); self:RegisterMovers()
end
function M:Refresh()
    self.layoutSerial = (self.layoutSerial or 0) + 1
    Roster(self); self:Update()
end
function M:Disable()
    self.generation = (self.generation or 0) + 1
    self.pending, self.alerted = false, false
    for _, host in pairs(self.windows) do host:Hide() end
end
function M:RegisterMovers()
    for _, key in ipairs({ "main", "focus" }) do
        S.RegisterOwnedMover(ID, key, { label = key == "focus" and "Focus threat" or "Threat meter", order = 650,
            getFrame = function() return self.windows[key] end, xKey = key .. "X", yKey = key .. "Y",
            point = function() return "CENTER" end, sizeKeys = { "width", "scale" },
            visible = function() return key ~= "focus" or self.config.windows == BOTH end })
    end
end
S.Install(ID, M)
