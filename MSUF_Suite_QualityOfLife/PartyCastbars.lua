local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "castEnhancements"
local Module = { rows = {}, finished = {} }
local UNITS = { "party1", "party2", "party3", "party4" }
local IN_COMBAT = { inCombat = true }
local WHITE = "Interface\\Buttons\\WHITE8x8"
local EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
}
local ENDS = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local function NewRow()
    local row = S.CreateFrame("StatusBar", nil, UIParent)
    row:SetStatusBarTexture(WHITE)
    row:EnableMouse(false)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(.065, .085, .11, .94)
    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetPoint("LEFT", row, "LEFT", 5, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    S.SetFont(name, nil, 10, "OUTLINE")
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPRIGHT", row, "TOPRIGHT")
    icon:SetTexCoord(.08, .92, .08, .92)
    local motion = row:CreateAnimationGroup()
    local fade = motion:CreateAnimation("Alpha")
    fade:SetFromAlpha(.45)
    fade:SetToAlpha(1)
    fade:SetDuration(.16)
    fade:SetSmoothing("OUT")
    row.label, row.icon, row.motion = name, icon, motion
    row:Hide()
    return row
end

local function Place(row, anchor, config)
    if not anchor or not NS.Safety.CanAnchor(anchor) then
        row:Hide()
        row.anchor = nil
        return
    end
    if row.anchor ~= anchor then
        row:Hide()
        row:SetParent(anchor)
        row:SetFrameLevel(anchor:GetFrameLevel() + 5)
    end
    row:ClearAllPoints()
    local edge = config.partyPosition == 2 and "TOP" or "BOTTOM"
    local point = config.partyPosition == 1 and "TOP" or "BOTTOM"
    local offset = config.partyPosition == 3 and 1 or config.partyPosition == 2 and 2 or -2
    row:SetPoint(point .. "LEFT", anchor, edge .. "LEFT", 0, offset)
    row:SetPoint(point .. "RIGHT", anchor, edge .. "RIGHT", 0, offset)
    row:SetHeight(config.partyHeight)
    row.icon:SetSize(config.partyHeight, config.partyHeight)
    row:SetStatusBarColor(S.RGB(config.partyColor))
    row.anchor = anchor
end

local function ReadCast(unit)
    local name, _, icon = UnitCastingInfo(unit)
    if not S.Public(name) or name ~= nil then return name, icon, UnitCastingDuration(unit), false end
    local channel, _, texture, _, _, _, _, _, empowered = UnitChannelInfo(unit)
    if not S.Public(channel) or channel ~= nil then
        local drains = not S.Public(empowered) or empowered ~= true
        return channel, texture, UnitChannelDuration(unit), drains
    end
end

local function Paint(self, unit, row, host)
    if not row then return end
    if not host or row.anchor ~= host or not host:IsVisible() then
        row:Hide()
        return
    end
    local name, icon, duration, channel = ReadCast(unit)
    if S.Public(name) and name == nil then
        row:Hide()
        return
    end
    local first = not row:IsShown()
    row.label:SetText(S.PublicText(name) or self.unknown)
    if S.Public(icon) then row.icon:SetTexture(icon) else row.icon:SetTexture(nil) end
    if S.Public(duration) and duration and row.SetTimerDuration then
        local direction = Enum.StatusBarTimerDirection
        row:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
            channel and direction.RemainingTime or direction.ElapsedTime)
    else
        row:SetMinMaxValues(0, 1)
        row:SetValue(1)
    end
    row:Show()
    if first and self.config.partyMotion then row.motion:Play() end
end

local function Bind(self, unit, anchor)
    local row = self.rows[unit]
    if anchor and not row then
        row = NewRow()
        self.rows[unit] = row
    end
    if row then Place(row, anchor, self.config) end
    return row
end

local function Layout(self)
    if NS.InCombat() or not self.config.party then return end
    for _, unit in ipairs(UNITS) do
        local anchor = self.api.PartyCastAnchor(unit)
        Paint(self, unit, Bind(self, unit, anchor), anchor)
    end
end

local function Clear(self)
    for _, row in pairs(self.rows) do
        row.motion:Stop()
        row:Hide()
    end
end

local function GroupChanged(self, event)
    if not NS.InCombat(event) then
        self.context:Coalesce(0, Layout):Request()
        return
    end
    for unit, row in pairs(self.rows) do Paint(self, unit, row, self.api.PartyCastAnchor(unit)) end
end

local function SettleEndedCasts(self)
    for unit in pairs(self.finished) do
        self.finished[unit] = nil
        Paint(self, unit, self.rows[unit], self.api.PartyCastAnchor(unit))
    end
end

local function OnCast(self, event, unit)
    if not S.PublicText(unit) then return end
    local row = self.rows[unit]
    if ENDS[event] then
        if row then
            self.finished[unit] = true
            self.context:Coalesce(0, SettleEndedCasts):Request()
        end
        return
    end
    local anchor = self.api.PartyCastAnchor(unit)
    if anchor and (not row or row.anchor ~= anchor) and not NS.InCombat() then row = Bind(self, unit, anchor) end
    Paint(self, unit, row, anchor)
end

function Module:Refresh()
    if not self.api then return end
    self.api.SetPlayerSpellCastColors(self.config.playerColors or "")
    for _, event in ipairs(EVENTS) do
        if self.config.party and NS.Client.SupportsEvent(event) then
            self.context:Event(event, OnCast, IN_COMBAT, UNITS)
        else
            self.context:RemoveEvent(event)
        end
    end
    if self.config.party then
        self.context:Event("GROUP_ROSTER_UPDATE", GroupChanged, IN_COMBAT)
        self.context:Event("PLAYER_ENTERING_WORLD", GroupChanged, IN_COMBAT)
        self.context:Event("PLAYER_REGEN_ENABLED", GroupChanged, IN_COMBAT)
        Layout(self)
    else
        self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
        self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
        self.context:Cancel(Layout)
        self.context:Cancel(SettleEndedCasts)
        Clear(self)
    end
end

function Module:Enable()
    self.api = NS.HostBridge.CastEnhancements()
    self.unknown = S.Text("Casting")
    self:Refresh()
end

function Module:Disable()
    Clear(self)
    for unit in pairs(self.finished) do self.finished[unit] = nil end
    if self.api then self.api.SetPlayerSpellCastColors("") end
end

S.Install(ID, Module)
