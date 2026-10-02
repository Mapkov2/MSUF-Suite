local _, P = ...
local NS, S = P.NS, P.Suite
local ID, POINTS = "actionTracker", NS.AnchorPoints
local MAX_ROWS, FALLBACK_ICON = 8, 134400
local IN_COMBAT = { inCombat = true }
local M = {}
-- displayPreset: standard rows or icons only; growth: down, up, right or
-- left; insertAnimation: none, fade in or pop in
-- (MSUF_Suite/Core/Catalog/QualityOfLife.lua).
local ICONS_ONLY = 2
local GROW_UP, GROW_RIGHT, GROW_LEFT = 2, 3, 4
local NO_ANIMATION, POP_IN = 1, 3

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
    self.header = S.CreateFontString(host, nil, "OVERLAY")
    self.header:SetJustifyH("LEFT")
    self.header:SetWordWrap(false)
    for index = 1, MAX_ROWS do self.rows[index] = NewRow(host) end
    host:Hide()
end

local function Layout(self)
    local c = self.config
    local iconsOnly = c.displayPreset == ICONS_ONLY
    local width = iconsOnly and c.rowHeight or c.width
    local growth = c.growth or 1
    local horizontal = growth == GROW_RIGHT or growth == GROW_LEFT
    local headerHeight = c.showHeader and not iconsOnly and (c.fontSize + 10) or 0
    local totalWidth = horizontal and c.rows * width + (c.rows - 1) * c.rowGap or width
    local height = horizontal and c.rowHeight or c.rows * c.rowHeight + (c.rows - 1) * c.rowGap
    local point = POINTS[c.point] or "CENTER"
    self.host:SetSize(totalWidth, height + headerHeight)
    self.header:ClearAllPoints()
    self.header:SetPoint("TOPLEFT", self.host, "TOPLEFT", 4, -2)
    self.header:SetSize(totalWidth - 8, headerHeight)
    self.header:SetShown(headerHeight > 0)
    self.host:SetScale(c.scale / 100)
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x, c.y)
    for index, row in ipairs(self.rows) do
        row.frame:ClearAllPoints()
        local offset = (index - 1) * ((horizontal and width or c.rowHeight) + c.rowGap)
        if growth == GROW_UP then row.frame:SetPoint("BOTTOMLEFT", self.host, "BOTTOMLEFT", 0, offset)
        elseif growth == GROW_RIGHT then row.frame:SetPoint("TOPLEFT", self.host, "TOPLEFT", offset, -headerHeight)
        elseif growth == GROW_LEFT then row.frame:SetPoint("TOPRIGHT", self.host, "TOPRIGHT", -offset, -headerHeight)
        else row.frame:SetPoint("TOPLEFT", self.host, "TOPLEFT", 0, -headerHeight - offset) end
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
    local iconsOnly = c.displayPreset == ICONS_ONLY
    local pr, pg, pb = S.RGB(c.panelColor)
    local br, bg, bb = S.RGB(c.borderColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    local tr, tg, tb = S.RGB(c.textColor)
    local font = S.ResolveFont(c.font) or S.GlobalFontPath()
    S.SetFont(self.header, font, c.fontSize, "OUTLINE")
    self.header:SetTextColor(tr, tg, tb)
    self.header:SetText(S.Text("Recent spells"))
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
    self.host:SetShown(count > 0 and (S.editMode or (not self.sessionHidden and self.contextVisible ~= false)))
end

local function ClearHistory(self)
    for index = #self.history, 1, -1 do self.history[index] = nil end
    Paint(self)
end

local function ExpireHistory(self)
    if self.pausedAt or not self.lastCastAt then return end
    ClearHistory(self)
end

-- The timeout is the deadline itself: every cast restarts it, a pause or a
-- setting without one cancels it, and Release drops it.
local function ScheduleHide(self)
    local delay = self.config.hideAfter
    if S.editMode or delay == 0 or not self.lastCastAt or self.pausedAt then
        self.context:Cancel(ExpireHistory)
        return
    end
    local remaining = delay - (GetTime() - self.lastCastAt)
    if remaining <= 0 then
        self.context:Cancel(ExpireHistory)
        ClearHistory(self)
        return
    end
    self.context:After(remaining, ExpireHistory)
end

local function PauseChanged(self, event)
    local now = GetTime()
    if self.config.pauseInCombat and NS.InCombat(event) then
        if not self.pausedAt then self.pausedAt = now end
    elseif self.pausedAt then
        if self.lastCastAt then self.lastCastAt = self.lastCastAt + now - self.pausedAt end
        self.pausedAt = nil
    end
    ScheduleHide(self)
end

local function AnimateNewest(self)
    local mode = self.config.insertAnimation or NO_ANIMATION
    if mode == NO_ANIMATION or S.editMode or self.contextVisible == false then return end
    local row = self.rows[1]
    local group
    if mode == POP_IN then group = row.pop else group = row.fade end
    if not group then
        group = row.frame:CreateAnimationGroup()
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(.18)
        if mode == POP_IN then
            local scale = group:CreateAnimation("Scale")
            scale:SetScaleFrom(.75, .75)
            scale:SetScaleTo(1, 1)
            scale:SetOrigin("CENTER", 0, 0)
            scale:SetDuration(.18)
            row.pop = group
        else row.fade = group end
    end
    if row.fade then row.fade:Stop() end
    if row.pop then row.pop:Stop() end
    group:Play()
end

local function Cast(self, _, _, _, spellID)
    -- This event is SecretWhenUnitSpellCastRestricted in upstream/live.
    -- Guard the ID and every field before comparisons, indexing or storage.
    if not S.Finite(spellID) or spellID <= 0 then return end
    local info = C_Spell.GetSpellInfo(spellID)
    if not S.Public(info) or type(info) ~= "table" then return end
    local name, icon = S.PublicText(info.name), info.iconID
    if not name or not S.Finite(icon) or icon <= 0 then return end
    if self.contextVisible == false then return end
    local history = self.history
    local entry = history[MAX_ROWS] or {}
    for index = MAX_ROWS, 2, -1 do history[index] = history[index - 1] end
    entry.name, entry.icon = name, icon
    history[1] = entry
    self.lastCastAt = GetTime()
    if self.pausedAt then self.pausedAt = self.lastCastAt end
    if not S.editMode then
        Paint(self)
        AnimateNewest(self)
    end
    ScheduleHide(self)
end

local function ContextChanged(self)
    local c = self.config
    local _, kind = GetInstanceInfo()
    if not S.Public(kind) then kind = nil end
    local key
    -- Delves report the scenario instance type; Blizzard's InstanceDifficulty
    -- asks C_DelvesUI (present on Retail and Forever).
    local delve = C_DelvesUI.HasActiveDelve()
    if S.Public(delve) and delve == true then key = "showDelves"
    elseif kind == "raid" then key = "showRaids"
    elseif kind == "party" then key = "showDungeons"
    elseif kind == "pvp" or kind == "arena" then key = "showPvP"
    else key = "showWorld" end
    self.contextVisible = c[key] ~= false
    if self.contextVisible then self.context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, IN_COMBAT, "player")
    else self.context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED") end
    Paint(self)
end

local function SyncEvents(self)
    local c = self.config
    if c.pauseInCombat then
        self.context:Event("PLAYER_REGEN_DISABLED", PauseChanged, IN_COMBAT)
        self.context:Event("PLAYER_REGEN_ENABLED", PauseChanged, IN_COMBAT)
    else
        self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    end
    if c.showDungeons == false or c.showRaids == false or c.showDelves == false
        or c.showPvP == false or c.showWorld == false then
        self.context:Event("PLAYER_ENTERING_WORLD", ContextChanged, IN_COMBAT)
        self.context:Event("ZONE_CHANGED_NEW_AREA", ContextChanged, IN_COMBAT)
        ContextChanged(self)
    else
        self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
        self.context:RemoveEvent("ZONE_CHANGED_NEW_AREA")
        self.contextVisible = true
        self.context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, IN_COMBAT, "player")
        Paint(self)
    end
end

function M:Enable()
    Create(self)
    self.history = {}
    self.lastCastAt = nil
    Layout(self)
    Style(self)
    Paint(self)
    SyncEvents(self)
    PauseChanged(self)
    self:RegisterMovers()
end

function M:Refresh()
    Layout(self)
    Style(self)
    Paint(self)
    SyncEvents(self)
    PauseChanged(self)
end

function M:Disable()
    self.history = {}
    self.lastCastAt, self.pausedAt = nil, nil
    for _, row in ipairs(self.rows or {}) do
        if row.fade then row.fade:Stop() end
        if row.pop then row.pop:Stop() end
    end
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "actions", {
        label = "Action tracker", order = 628,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "rowHeight", "scale" },
        sizeKeys = { "width", "rowHeight", "scale" },
    })
end

function S.SetActionTrackerSessionHidden(hidden)
    M.sessionHidden = hidden == true
    if M.active then Paint(M) end
end

S.Install(ID, M)
