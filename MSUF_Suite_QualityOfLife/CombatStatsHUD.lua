local _, P = ...
local NS, S = P.NS, P.Suite
local M = { generation = 0 }
local ID = "combatStatsHUD"
local FIELDS = {
    { key = "crit", label = "CRIT" },
    { key = "haste", label = "HASTE" },
    { key = "mastery", label = "MASTERY" },
    { key = "versatility", label = "VERS" },
}

local function Enabled(c, field)
    return c["show" .. field.key:sub(1, 1):upper() .. field.key:sub(2)] == true
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
    local melee = ReadPercent(_G.GetCritChance)
    local ranged = ReadPercent(_G.GetRangedCritChance)
    if not melee or not ranged then return nil end
    local spell
    for school = 2, 7 do
        local value = GetSpellCritChance(school)
        if not S.Finite(value) then return nil end
        spell = spell and math.min(spell, value) or value
    end
    return math.max(melee, ranged, spell)
end

local function ReadStats(config)
    local crit = config.showCrit and ReadCrit() or nil
    local haste = config.showHaste and ReadPercent(_G.GetHaste) or nil
    local mastery = config.showMastery and ReadPercent(_G.GetMasteryEffect) or nil
    local versatility
    if config.showVersatility then
        local rating = CR_VERSATILITY_DAMAGE_DONE
        local fromRating = GetCombatRatingBonus(rating)
        local fromEffects = GetVersatilityBonus(rating)
        if S.Finite(fromRating) and S.Finite(fromEffects) then
            versatility = fromRating + fromEffects
        end
    end
    return crit, haste, mastery, versatility
end

local function SetValue(field, value)
    local text = S.Finite(value) and string.format("%.1f%%", value) or "--"
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

local function Layout(self)
    local c = self.config
    local point = NS.AnchorPoints[c.point] or "CENTER"
    local host = self.host
    host:ClearAllPoints()
    host:SetPoint(point, UIParent, point, c.x, c.y)
    host:SetWidth(c.width)
    host:SetScale(c.scale / 100)
    self.bg:SetColorTexture(S.RGB(c.backgroundColor))
    self.bg:SetAlpha(c.opacity / 100)
    self.border:SetColorTexture(S.RGB(c.accentColor))
    if c.look and c.look ~= 5 then
        local style = S.QoLStyle(c)
        for _, field in ipairs(self.fields) do
            field.label:SetTextColor(S.RGB(style.muted))
            field.value:SetTextColor(S.RGB(style.accent))
        end
    else
        for _, field in ipairs(self.fields) do
            field.label:SetTextColor(.68, .74, .79)
            field.value:SetTextColor(1, .87, .56)
        end
    end
    local count = 0
    for i = 1, #FIELDS do
        if Enabled(c, FIELDS[i]) then count = count + 1 end
    end
    count = math.max(1, count)
    local visible = 0
    for i = 1, #FIELDS do
        local field = self.fields[i]
        local shown = Enabled(c, FIELDS[i])
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

local function Update(self)
    if not self.active or not self.host then return end
    local visible = AnyEnabled(self.config)
        and (S.editMode or not self.config.combatOnly or NS.IsCombatLocked())
    self.host:SetShown(visible)
    if not visible then return end
    if S.editMode then
        for i = 1, #self.fields do SetValue(self.fields[i], 12.3 + i) end
        return
    end
    local crit, haste, mastery, versatility = ReadStats(self.config)
    SetValue(self.fields[1], crit)
    SetValue(self.fields[2], haste)
    SetValue(self.fields[3], mastery)
    SetValue(self.fields[4], versatility)
end

local function Schedule(self)
    if self.pending then return end
    self.pending = true
    local generation = self.generation
    C_Timer.After(.05, function()
        if self.generation ~= generation then return end
        self.pending = false
        Update(self)
    end)
end

local STAT_EVENTS = {
    "COMBAT_RATING_UPDATE", "MASTERY_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
    "PLAYER_SPECIALIZATION_CHANGED",
    "UNIT_STATS", "UNIT_SPELL_HASTE", "UNIT_AURA",
}

local function SyncListeners(self)
    local want = AnyEnabled(self.config)
        and (S.editMode or not self.config.combatOnly or NS.IsCombatLocked())
    if want == self.listening then return end
    self.listening = want
    for i = 1, #STAT_EVENTS do
        local event = STAT_EVENTS[i]
        local unit = event:sub(1, 5) == "UNIT_" and "player" or nil
        if want then self.context:Event(event, Schedule, true, unit)
        else self.context:RemoveEvent(event) end
    end
end

local function OnGate(self)
    SyncListeners(self)
    Update(self)
end

function M:Enable()
    self.generation = self.generation + 1
    Create(self)
    Layout(self)
    self.context:Event("PLAYER_ENTERING_WORLD", OnGate, true)
    self.context:Event("PLAYER_REGEN_DISABLED", OnGate, true)
    self.context:Event("PLAYER_REGEN_ENABLED", OnGate, true)
    SyncListeners(self)
    Update(self)
    self:RegisterMovers()
end

function M:Refresh()
    Layout(self)
    SyncListeners(self)
    Update(self)
end

function M:Disable()
    self.generation = self.generation + 1
    self.pending = false
    self.listening = nil
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "combat", {
        label = "Secondary stats", order = 645,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 180, max = 480, step = 1,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "scale", label = "Scale %", kind = "number", min = 50, max = 200, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
