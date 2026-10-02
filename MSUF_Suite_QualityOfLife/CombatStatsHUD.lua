local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local M = {}
local ID = "combatStatsHUD"
-- look 6 is Class Style, whose shared palette is QoLVisualStyles[5]; look 5 is Custom.
local CUSTOM_LOOK, CLASS_LOOK, CLASS_PALETTE = 5, 6, 5
-- fps: 1 hidden, 2 below the stats, 3 on its own.
local FPS_HIDDEN, FPS_BELOW, FPS_ALONE = 1, 2, 3
-- valueFormat: percentages, combat ratings, or both on two lines; labelStyle:
-- short or full stat names (MSUF_Suite/Core/Catalog/QualityOfLifeHUD.lua).
local RATINGS, BOTH, FULL_NAMES = 2, 3, 2
local FIELDS = {
    { key = "showCrit", label = "CRIT", full = "Critical strike" },
    { key = "showHaste", label = "HASTE", full = "Haste" },
    { key = "showMastery", label = "MASTERY", full = "Mastery" },
    { key = "showVersatility", label = "VERS", full = "Versatility" },
    -- Each extra stat has its own switch and color.
    { key = "showLeech", color = "leechColor", label = "LEECH", full = "Leech", rating = "CR_LIFESTEAL",
        read = function() return GetLifesteal() end },
    { key = "showAvoidance", color = "avoidanceColor", label = "AVOID", full = "Avoidance", rating = "CR_AVOIDANCE",
        read = function() return GetAvoidance() end },
    { key = "showSpeed", color = "speedColor", label = "SPD", full = "Speed", rating = "CR_SPEED",
        read = function() return GetSpeed() end },
}
local FIRST_EXTRA = 5

local function Enabled(c, field)
    return c[field.key] == true
end

local function AnyEnabled(c)
    for i = 1, #FIELDS do if Enabled(c, FIELDS[i]) then return true end end
    return false
end

local function ReadPercent(fn)
    local value = fn()
    return S.Finite(value) and value or nil
end

-- Match Blizzard's PaperDollFrame crit display: the highest of melee,
-- ranged and the lowest spell-school value. One restricted school leaves the
-- result unknown rather than silently showing a misleading partial maximum.
local function ReadCrit()
    local melee = ReadPercent(GetCritChance)
    local ranged = ReadPercent(GetRangedCritChance)
    if not melee or not ranged then return nil end
    local spell
    for school = 2, 7 do
        local value = GetSpellCritChance(school)
        if not S.Finite(value) then return nil end
        spell = spell and math.min(spell, value) or value
    end
    if spell >= ranged and spell >= melee then return spell, _G.CR_CRIT_SPELL end
    if ranged >= melee then return ranged, _G.CR_CRIT_RANGED end
    return melee, _G.CR_CRIT_MELEE
end

local function ReadStats(config)
    local crit, critRating
    if config.showCrit then crit, critRating = ReadCrit() end
    local haste = config.showHaste and ReadPercent(GetHaste) or nil
    local mastery = config.showMastery and ReadPercent(GetMasteryEffect) or nil
    local versatility
    if config.showVersatility then
        local rating = CR_VERSATILITY_DAMAGE_DONE
        local fromRating = GetCombatRatingBonus(rating)
        local fromEffects = GetVersatilityBonus(rating)
        if S.Finite(fromRating) and S.Finite(fromEffects) then
            versatility = fromRating + fromEffects
        end
    end
    return crit, haste, mastery, versatility, critRating
end

local function ReadRating(rating)
    if S.Finite(rating) then
        local value = GetCombatRating(rating)
        if S.Finite(value) then return value end
    end
end

-- raw: the numbers include ratings; ratingsOnly: only ratings (else both
-- on two lines). Without raw the value shows as a percentage.
local function SetValue(field, value, rating, raw, ratingsOnly)
    local text
    if not raw then
        text = S.Finite(value) and string.format("%.1f%%", value) or "--"
    elseif ratingsOnly then
        text = S.Finite(rating) and string.format("%.0f", rating) or "--"
    else
        text = (S.Finite(value) and string.format("%.1f%%", value) or "--")
            .. "\n" .. (S.Finite(rating) and string.format("%.0f", rating) or "--")
    end
    if field.lastText ~= text then
        field.lastText = text
        field.value:SetText(text)
    end
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    host:SetSize(300, 42)
    host:EnableMouse(false)
    local bg = S.CreateTexture(host, nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.06, .08, .1, .92)
    local border = S.CreateTexture(host, nil, "BORDER")
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMLEFT", 0, 0)
    border:SetWidth(2)
    border:SetColorTexture(.85, .68, .36, 1)
    local fields = {}
    for i = 1, #FIELDS do
        local label = S.CreateFontString(host, nil, "OVERLAY")
        S.SetFont(label, nil, 10, "OUTLINE")
        label:SetText(S.Text(FIELDS[i].label))
        label:SetTextColor(.68, .74, .79)
        local value = S.CreateFontString(host, nil, "OVERLAY")
        S.SetFont(value, nil, 15, "OUTLINE")
        value:SetTextColor(1, .87, .56)
        fields[i] = { label = label, value = value }
    end
    host:Hide()
    self.host, self.bg, self.border, self.fields = host, bg, border, fields
end

-- The FPS key binding overrides the profile choice for this session only,
-- so it also works in combat and never writes a setting.
local function FPSPlacement(self)
    local wanted = self.fpsSession
    if wanted == nil then wanted = self.config.fps ~= FPS_HIDDEN end
    if not self.active or not (wanted or S.editMode) then return nil end
    if self.config.fps == FPS_BELOW then return FPS_BELOW end
    return FPS_ALONE
end

local function PaintFPS(self)
    local value = GetFramerate()
    self.fpsText:SetText(S.Finite(value) and string.format(self.fpsFormat, value) or self.fpsUnknown)
end

-- Cold: placement and the sampling ticker follow the settings, the session
-- toggle and Edit Mode, never a stat repaint.
local function UpdateFPS(self)
    local placement = FPSPlacement(self)
    if not placement then
        self.context:Cancel(PaintFPS)
        if self.fpsHost then self.fpsHost:Hide() end
        return
    end
    if not self.fpsHost then
        self.fpsHost = S.CreateFrame("Frame", nil, UIParent)
        self.fpsHost:SetSize(110, 24)
        self.fpsText = S.CreateFontString(self.fpsHost, nil, "OVERLAY")
        self.fpsText:SetAllPoints(self.fpsHost)
        S.SetStyledFont(self.fpsText, S.GlobalFontPath(), 14, "OUTLINE", 1, true, 70, 1)
        self.fpsFormat, self.fpsUnknown = S.Text("%.0f FPS"), S.Text("-- FPS")
    end
    self.fpsHost:ClearAllPoints()
    if placement == FPS_BELOW then
        self.fpsHost:SetPoint("TOP", self.host, "BOTTOM", 0, -4)
    else
        self.fpsHost:SetPoint("CENTER", UIParent, "CENTER", self.config.fpsX, self.config.fpsY)
    end
    self.fpsHost:SetScale(self.config.scale / 100)
    self.fpsHost:Show()
    PaintFPS(self)
    self.context:Ticker(1, PaintFPS)
end

function S.ToggleCombatStatsFPS()
    if not M.active then
        S.Print(S.Text("Turn on Secondary stats in the MSUF Suite options to use the FPS readout."))
        return
    end
    M.fpsSession = FPSPlacement(M) == nil
    UpdateFPS(M)
end

local function Colors(self)
    local c = self.config
    local muted, accent
    if c.look ~= CUSTOM_LOOK then
        local style = S.QoLPalette(c.look == CLASS_LOOK and CLASS_PALETTE or c.look)
        muted, accent = style.muted, style.accent
    end
    for i, field in ipairs(self.fields) do
        if muted then field.label:SetTextColor(S.RGB(muted)) else field.label:SetTextColor(.68, .74, .79) end
        local own = FIELDS[i].color
        if own then
            field.value:SetTextColor(S.RGB(c[own]))
        elseif accent then
            field.value:SetTextColor(S.RGB(accent))
        else
            field.value:SetTextColor(1, .87, .56)
        end
    end
end

local function Layout(self)
    local c = self.config
    local host = self.host
    host:SetSize(c.width, c.valueFormat == BOTH and 58 or 42)
    S.PlaceHost(host, c)
    self.bg:SetColorTexture(S.RGB(c.backgroundColor))
    self.bg:SetAlpha(c.opacity / 100)
    self.border:SetColorTexture(S.RGB(c.accentColor))
    Colors(self)
    local count = 0
    for i = 1, #FIELDS do
        if Enabled(c, FIELDS[i]) then count = count + 1 end
    end
    count = math.max(1, count)
    local visible = 0
    for i = 1, #FIELDS do
        local field, definition = self.fields[i], FIELDS[i]
        local shown = Enabled(c, definition)
        field.label:SetText(S.Text(c.labelStyle == FULL_NAMES and definition.full or definition.label))
        field.label:SetShown(shown)
        field.value:SetShown(shown)
        if shown then
            visible = visible + 1
            local x = (visible - .5) * c.width / count
            field.label:ClearAllPoints()
            field.label:SetPoint("TOP", host, "TOPLEFT", x, -5)
            field.value:ClearAllPoints()
            field.value:SetPoint("BOTTOM", host, "BOTTOMLEFT", x, 5)
        end
    end
end

-- PLAYER_REGEN_DISABLED arrives before the combat lockdown starts.
local function Wanted(self, event)
    return AnyEnabled(self.config) and (S.editMode or not self.config.combatOnly or NS.InCombat(event))
end

local function Update(self, event)
    if not self.active or not self.host then return end
    local visible = Wanted(self, event)
    self.host:SetShown(visible)
    if not visible then return end
    local c = self.config
    local ratingsOnly = c.valueFormat == RATINGS
    local raw = ratingsOnly or c.valueFormat == BOTH
    if S.editMode then
        for i = 1, #self.fields do SetValue(self.fields[i], 12.3 + i, 500 + i * 100, raw, ratingsOnly) end
        return
    end
    local crit, haste, mastery, versatility, critRating = ReadStats(c)
    SetValue(self.fields[1], crit, c.showCrit and raw and ReadRating(critRating), raw, ratingsOnly)
    SetValue(self.fields[2], haste, c.showHaste and raw and ReadRating(_G.CR_HASTE_MELEE), raw, ratingsOnly)
    SetValue(self.fields[3], mastery, c.showMastery and raw and ReadRating(_G.CR_MASTERY), raw, ratingsOnly)
    SetValue(self.fields[4], versatility, c.showVersatility and raw
        and ReadRating(_G.CR_VERSATILITY_DAMAGE_DONE), raw, ratingsOnly)
    -- Switched-off extra stats are not read.
    for i = FIRST_EXTRA, #FIELDS do
        local field = FIELDS[i]
        if c[field.key] then
            SetValue(self.fields[i], ReadPercent(field.read), raw and ReadRating(_G[field.rating]), raw, ratingsOnly)
        end
    end
end

-- Stat events request one repaint per short window (self.statsJob).
local STATS_DELAY = .05
local function Repaint(self)
    Update(self)
end

local STAT_EVENTS = {
    "COMBAT_RATING_UPDATE", "MASTERY_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
    "PLAYER_SPECIALIZATION_CHANGED",
    "UNIT_STATS", "UNIT_SPELL_HASTE", "UNIT_AURA",
}

local function SyncListeners(self, event)
    local want = Wanted(self, event)
    if want == self.listening then return end
    self.listening = want
    for i = 1, #STAT_EVENTS do
        local name = STAT_EVENTS[i]
        local unit = name:sub(1, 5) == "UNIT_" and "player" or nil
        if want then
            self.context:Event(name, self.statsJob, IN_COMBAT, unit)
        else
            self.context:RemoveEvent(name)
        end
    end
end

local function OnGate(self, event)
    SyncListeners(self, event)
    Update(self, event)
end

function M:Enable()
    self.statsJob = self.context:Coalesce(STATS_DELAY, Repaint)
    self.fpsChoice = self.config.fps
    Create(self)
    Layout(self)
    self.context:Event("PLAYER_ENTERING_WORLD", OnGate, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_DISABLED", OnGate, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", OnGate, IN_COMBAT)
    SyncListeners(self)
    Update(self)
    UpdateFPS(self)
    self:RegisterMovers()
end

function M:Refresh()
    -- A new FPS choice in the options replaces the session override.
    if self.fpsChoice ~= self.config.fps then self.fpsChoice, self.fpsSession = self.config.fps, nil end
    Layout(self)
    SyncListeners(self)
    Update(self)
    UpdateFPS(self)
end

-- The context's Release stops the repaint and the FPS ticker.
function M:Disable()
    if self.fpsHost then self.fpsHost:Hide() end
    self.listening = nil
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "fps", {
        label = "FPS", order = 646, getFrame = function() return self.fpsHost end,
        xKey = "fpsX", yKey = "fpsY", point = function() return "CENTER" end,
        visible = function() return FPSPlacement(self) == FPS_ALONE end,
    })
    S.RegisterOwnedMover(ID, "combat", {
        label = "Secondary stats", order = 645,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "scale" }, sizeKeys = { "width", "scale" },
    })
end

S.Install(ID, M)
