local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "targetDotEstimate"
local Module = { rates = {}, effects = {}, count = 0 }
local MAX_AURAS = 32
local FILTER = "HARMFUL|PLAYER"
local IN_COMBAT = { inCombat = true }
local Finite = S.Finite
local function Clear(self)
    self.count = 0
    if self.shade then self.shade:Hide() end
end

-- Read a single explicit total and duration. Skip mixed damage and ranges.
-- Spell power snapshots and mitigation are outside the estimate.
local function PeriodicRate(description, locale)
    if description:find("%%") or description:find("%d+%s*%-%s*%d+")
        or description:find("%d+%s*–%s*%d+") then return end
    local pattern = locale == "deDE" and "(%d[%.%d]*) [^%d%.]-schaden[^%d%.]-(%d+) Sek"
        or "(%d[,%d]*) [^%d%.]-damage over (%d+) sec"
    local first, last, amount, seconds = description:find(pattern)
    if not first and locale == "deDE" then
        pattern = "im Verlauf von (%d+) Sek%.? (%d[%.%d]*) [^%d%.]-schaden"
        first, last, seconds, amount = description:find(pattern)
    end
    if not first or description:find(pattern, last + 1) then return end
    local before = description:sub(first - 1, first - 1)
    if before == "," or before == "." then return end
    amount = tonumber((amount:gsub("[,.]", "")))
    seconds = tonumber(seconds)
    if amount and seconds and amount > 0 and seconds > 0 and seconds <= 120 then return amount / seconds, seconds end
end

local function Spell(self, id)
    local saved = self.rates[id]
    if saved ~= nil then return saved end
    if self.rateCount >= 48 then
        wipe(self.rates)
        self.rateCount = 0
    end
    local description = S.PublicText(C_Spell.GetSpellDescription(id))
    if not description or description == "" then return end
    local rate, duration = PeriodicRate(description, self.locale)
    saved = rate and { rate = rate, duration = duration } or false
    self.rates[id] = saved
    self.rateCount = self.rateCount + 1
    return saved
end

local function BindFill(self, bar, event)
    local fill, reverse = bar:GetStatusBarTexture(), bar:GetReverseFill()
    if not S.Public(fill) or not fill or not S.Public(reverse) then return false end
    if fill == self.fill and reverse == self.reverse then return true end
    if NS.InCombat(event) or not NS.Safety.CanAnchor(fill) then return false end
    local edge = reverse and "LEFT" or "RIGHT"
    self.shade:ClearAllPoints()
    self.shade:SetPoint(edge, fill, edge)
    self.fill, self.reverse = fill, reverse
    return true
end

local shades = setmetatable({}, { __mode = "k" })
local function Prepare(self)
    local bar = NS.HostBridge.TargetHealthAnchor()
    if bar ~= self.bar then
        if self.shade then self.shade:Hide() end
        self.bar, self.fill, self.shade = nil, nil, nil
        if not bar or not NS.Safety.CanAnchor(bar) then return end
        local shade = shades[bar]
        if not shade then
            shade = bar:CreateTexture(nil, "OVERLAY", nil, 1)
            shades[bar] = shade
        end
        self.bar, self.shade = bar, shade
        shade:Hide()
    end
    -- Bind while out of combat, before the first DoT can start the fight.
    if bar then BindFill(self, bar) end
end

local function Paint(self, event)
    local shade, bar = self.shade, self.bar
    if not shade or self.count == 0 then return end
    local restricted = C_Secrets.ShouldAurasBeSecret()
    if not S.Public(restricted) or restricted ~= false then
        shade:Hide()
        return
    end
    local health, maximum = UnitHealth("target"), UnitHealthMax("target")
    if not Finite(health) or not Finite(maximum) or health <= 0 or maximum <= 0 then
        shade:Hide()
        return
    end
    local width, height = bar:GetWidth(), bar:GetHeight()
    if not Finite(width) or width <= 0 or not Finite(height) or height <= 0 then
        shade:Hide()
        return
    end
    local now, estimate = GetTime(), 0
    for index = 1, self.count do
        local effect = self.effects[index]
        estimate = estimate + effect.rate * math.max(0, math.min(effect.duration, effect.expires - now))
    end
    if estimate <= 0 or not BindFill(self, bar, event) then
        shade:Hide()
        return
    end
    shade:SetSize(math.max(.5, width * math.min(health, estimate) / maximum), height)
    local opacity = self.config.opacity / 100
    if estimate >= health then
        shade:SetColorTexture(.96, .46, .30, opacity)
    else
        shade:SetColorTexture(1, .78, .37, opacity * .67)
    end
    shade:Show()
end

local function AddEffect(self, aura)
    if not S.Public(aura) or type(aura) ~= "table" or not canaccesstable(aura) then return end
    local id, duration, expires = aura.spellId, aura.duration, aura.expirationTime
    if not Finite(id) or id <= 0 or not Finite(duration) or duration <= 0
        or not Finite(expires) or expires <= 0 then return end
    local info = Spell(self, id)
    if not info or math.abs(info.duration - duration) > .25 then return end
    self.count = self.count + 1
    local index = self.count
    local effect = self.effects[index]
    effect.rate, effect.duration, effect.expires = info.rate, duration, expires
end

local function Update(self, event)
    self.count = 0
    if not NS.InCombat(event) then Prepare(self) end
    local secret = C_Secrets.ShouldAurasBeSecret()
    local hostile = UnitCanAttack("player", "target")
    if S.Public(secret) and secret == false and S.Public(hostile) and hostile == true then
        local auras = C_UnitAuras.GetUnitAuras("target", FILTER, MAX_AURAS)
        if S.Public(auras) and type(auras) == "table" and canaccesstable(auras) then
            for index = 1, math.min(MAX_AURAS, #auras) do AddEffect(self, auras[index]) end
        end
    end
    if self.count > 0 then Paint(self, event) else Clear(self) end
end

local function SpellsChanged(self)
    wipe(self.rates)
    self.rateCount = 0
    Update(self)
end

function Module:Refresh() Update(self) end

function Module:Enable()
    self.locale = GetLocale()
    self.rateCount = 0
    for index = 1, MAX_AURAS do self.effects[index] = self.effects[index] or {} end
    self.context:Event("UNIT_AURA", Update, IN_COMBAT, "target")
    self.context:Event("UNIT_HEALTH", Paint, IN_COMBAT, "target")
    self.context:Event("PLAYER_TARGET_CHANGED", Update, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_DISABLED", Update, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", Update, IN_COMBAT)
    self.context:Event("PLAYER_ENTERING_WORLD", Update, IN_COMBAT)
    self.context:Event("SPELLS_CHANGED", SpellsChanged, IN_COMBAT)
    Update(self)
end

function Module:Disable() Clear(self) end

S.Install(ID, Module)
