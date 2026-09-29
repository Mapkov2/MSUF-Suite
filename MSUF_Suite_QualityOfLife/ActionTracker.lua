local _, P = ...
local NS, S = P.NS, P.Suite
local ID, POINTS = "actionTracker", NS.AnchorPoints
local MAX_ROWS, FALLBACK_ICON = 8, 134400
local M = {}

-- The examples exist only in Edit Mode. Live rows come exclusively from the
-- player's successful spellcast event, never from combat-log inference.
local SAMPLE_IDS = { 2098, 53, 2098, 1766, 2098 }
local samples

local function Samples()
    if samples then return samples end
    samples = {}
    for index, spellID in ipairs(SAMPLE_IDS) do
        local info = C_Spell.GetSpellInfo(spellID)
        if not S.Public(info) or type(info) ~= "table" then info = nil end
        samples[index] = {
            name = info and S.PublicText(info.name) or S.Text("Action"),
            icon = info and S.Finite(info.iconID) and info.iconID or FALLBACK_ICON,
        }
    end
    return samples
end

local function NewRow(host)
    local frame = S.CreateFrame("Frame", nil, host)
    frame:EnableMouse(false)
    local panel = S.CreateTexture(frame, nil, "BACKGROUND")
    panel:SetAllPoints(frame)
    local stripe = S.CreateTexture(frame, nil, "BORDER")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(2)
    local rule = S.CreateTexture(frame, nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    local icon = S.CreateTexture(frame, nil, "ARTWORK")
    icon:SetPoint("LEFT", frame, "LEFT", 3, 0)
    icon:SetTexCoord(.07, .93, .07, .93)
    local name = S.CreateFontString(frame, nil, "OVERLAY")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local marker = S.CreateFontString(frame, nil, "OVERLAY")
    marker:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    marker:SetJustifyH("CENTER")
    return { frame = frame, panel = panel, stripe = stripe, rule = rule,
        icon = icon, name = name, marker = marker }
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    host:EnableMouse(false)
    self.host, self.rows = host, {}
    for index = 1, MAX_ROWS do self.rows[index] = NewRow(host) end
    host:Hide()
end

local function Layout(self)
    local c = self.config
    local iconsOnly = c.displayPreset == 2
    local width = iconsOnly and c.rowHeight or c.width
    local height = c.rows * c.rowHeight + (c.rows - 1) * c.rowGap
    local point = POINTS[c.point] or "CENTER"
    self.host:SetSize(width, height)
    self.host:SetScale(c.scale / 100)
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
    for index, row in ipairs(self.rows) do
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", self.host, "TOPLEFT", 0, -(index - 1) * (c.rowHeight + c.rowGap))
        row.frame:SetSize(width, c.rowHeight)
        local iconSize = c.rowHeight - (iconsOnly and 2 or 4)
        row.icon:ClearAllPoints()
        if iconsOnly then row.icon:SetPoint("CENTER", row.frame, "CENTER", 0, 0)
        else row.icon:SetPoint("LEFT", row.frame, "LEFT", 3, 0) end
        row.icon:SetSize(iconSize, iconSize)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.marker, "LEFT", -5, 0)
        row.name:SetHeight(c.rowHeight - 2)
        row.marker:SetWidth(not iconsOnly and c.showChevron and 12 or 0)
    end
end

local function Style(self)
    local c = self.config
    local iconsOnly = c.displayPreset == 2
    local pr, pg, pb = S.RGB(c.panelColor)
    local br, bg, bb = S.RGB(c.borderColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    local tr, tg, tb = S.RGB(c.textColor)
    local font = S.ResolveFont(c.font) or S.GlobalFontPath()
    for _, row in ipairs(self.rows) do
        row.panel:SetColorTexture(pr, pg, pb, c.panelOpacity / 100)
        row.stripe:SetColorTexture(ar, ag, ab, .78)
        row.rule:SetColorTexture(br, bg, bb, .7)
        S.SetFont(row.name, font, c.fontSize, "OUTLINE")
        row.name:SetTextColor(tr, tg, tb)
        S.SetFont(row.marker, font, c.fontSize + 2, "OUTLINE")
        row.marker:SetText(">")
        row.marker:SetTextColor(ar, ag, ab)
        row.panel:SetShown(not iconsOnly)
        row.stripe:SetShown(not iconsOnly)
        row.rule:SetShown(not iconsOnly)
        row.marker:SetShown(not iconsOnly and c.showChevron)
        row.name:SetShown(not iconsOnly and c.showNames)
    end
end

local function Paint(self)
    local entries = S.editMode and Samples() or self.history
    local count = math.min(self.config.rows, #entries)
    for index, row in ipairs(self.rows) do
        local entry = index <= count and entries[index]
        if entry then
            row.icon:SetTexture(entry.icon)
            row.name:SetText(entry.name)
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end
    self.host:SetShown(count > 0)
end

local function CancelHide(self)
    if self.hideTimer then self.hideTimer:Cancel(); self.hideTimer = nil end
end

local function ScheduleHide(self)
    CancelHide(self)
    local delay = self.config.hideAfter
    if S.editMode or delay == 0 or not self.lastCastAt then return end
    local remaining = delay - (GetTime() - self.lastCastAt)
    if remaining <= 0 then
        self.history = {}
        Paint(self)
        return
    end
    local timer
    timer = C_Timer.NewTimer(remaining, function()
        if not self.active or self.hideTimer ~= timer then return end
        self.hideTimer = nil
        self.history = {}
        Paint(self)
    end)
    self.hideTimer = timer
end

local function Cast(self, _, _, _, spellID)
    -- This event is SecretWhenUnitSpellCastRestricted in upstream/live.
    -- Guard the ID and every field before comparisons, indexing or storage.
    if not S.Finite(spellID) or spellID <= 0 then return end
    local info = C_Spell.GetSpellInfo(spellID)
    if not S.Public(info) or type(info) ~= "table" then return end
    local name, icon = S.PublicText(info.name), info.iconID
    if not name or not S.Finite(icon) or icon <= 0 then return end
    local history = self.history
    for index = MAX_ROWS, 2, -1 do history[index] = history[index - 1] end
    history[1] = { name = name, icon = icon }
    self.lastCastAt = GetTime()
    if not S.editMode then Paint(self) end
    ScheduleHide(self)
end

function M:Enable()
    Create(self)
    self.history = {}
    self.lastCastAt = nil
    Layout(self)
    Style(self)
    Paint(self)
    self.context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, true, "player")
    self:RegisterMovers()
end

function M:Refresh()
    Layout(self)
    Style(self)
    Paint(self)
    ScheduleHide(self)
end

function M:Disable()
    CancelHide(self)
    self.history = {}
    self.lastCastAt = nil
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "actions", {
        label = "Action tracker", order = 628,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "rowHeight", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 150, max = 420, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "rowHeight", label = "Row height", kind = "number", min = 24, max = 48, step = 1,
                get = function() return S.Config(ID).rowHeight end,
                set = function(value) return S.Set(ID, "rowHeight", value) end },
            { id = "scale", label = "Scale %", kind = "number", min = 50, max = 200, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
