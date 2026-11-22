local _, P = ...
local NS, S = P.NS, P.Suite
local Feed, Display, Gains = NS.FloatingCombatFeed, P.FloatingTextDisplay, P.FloatingTextGains
local ID, CAPACITY = "floatingCombatText", 24
local ESTIMATED, ALL_ENEMIES = 1, 2
local DAMAGE_CVAR = "floatingCombatTextCombatDamage_v2"
local WORLD_TEXT_CVAR, HIDDEN_WORLD_TEXT_SCALE = Feed.WorldTextScale, 1000
local WORLD_TEXT_EVENT_KEY = WORLD_TEXT_CVAR:lower()
local DIRECT = { inCombat = true, direct = true }
local MELEE_WINDOW, RANGED_WINDOW, CAST_WINDOW = 1.3, 2, 2.5
-- Forever's Enum.PlayerSwingType from SwingTimerDocumentation.lua.
local OFF_HAND, RANGED = 1, 2
local M = {}

-- The type is public only on the paths checked below. The amount is opaque
-- and is handed straight to the renderer's FontString.
local Outcomes = {
    MISS = MISS or S.Text("Miss"), DODGE = DODGE or S.Text("Dodge"), PARRY = PARRY or S.Text("Parry"),
    BLOCK = BLOCK or S.Text("Block"), RESIST = RESIST or S.Text("Resist"), ABSORB = ABSORB or S.Text("Absorb"),
    IMMUNE = IMMUNE or S.Text("Immune"), EVADE = EVADE or S.Text("Evade"),
    DEFLECT = DEFLECT or S.Text("Deflect"), REFLECT = REFLECT or S.Text("Reflect"),
}
local FULL_MITIGATION = { ABSORB = true, BLOCK = true, RESIST = true }
local Formats = Gains.Formats
S.FloatingTextSamples = {
    { key = "hit", label = S.Text("Enemy damage"), route = "hit", format = "%s", value = "461" },
    { key = "crit", label = S.Text("Critical hit"), route = "hit", critical = true, format = "%s", value = "1,284" },
    { key = "dodge", label = Outcomes.DODGE, route = "avoid", value = Outcomes.DODGE },
    { key = "parry", label = Outcomes.PARRY, route = "avoid", value = Outcomes.PARRY },
    { key = "miss", label = Outcomes.MISS, route = "avoid", value = Outcomes.MISS },
    { key = "block", label = Outcomes.BLOCK, route = "avoid", value = Outcomes.BLOCK },
    { key = "absorb", label = Outcomes.ABSORB, route = "avoid", value = Outcomes.ABSORB },
    { key = "resist", label = Outcomes.RESIST, route = "avoid", value = Outcomes.RESIST },
    { key = "immune", label = Outcomes.IMMUNE, route = "avoid", value = Outcomes.IMMUNE },
    { key = "xp", label = S.Text("XP gained"), route = "xp", format = Formats.xp, value = 425 },
    { key = "level", label = S.Text("Level up"), route = "gain", critical = true, format = Formats.level, value = 42 },
    { key = "reputation", label = S.Text("Reputation"), route = "gain", format = Formats.reputation, value = "+125" },
    { key = "honor", label = S.Text("Honor"), route = "gain", format = Formats.honor, value = 48 },
    { key = "power", label = S.Text("Resource gain"), route = "power", format = Formats.power, value = 20 },
    { key = "enter", label = Gains.CombatStart, route = "combat", value = Gains.CombatStart },
    { key = "leave", label = Gains.CombatEnd, route = "combat", value = Gains.CombatEnd },
}

local function IsEnemy(unit)
    local enemy = UnitCanAttack("player", unit)
    return S.Public(enemy) and enemy == true
end

local function AccessiblePlate(plate)
    return S.Public(plate) and type(plate) == "table" and not NS.Safety.IsForbidden(plate)
end

local function GetPlate(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if AccessiblePlate(plate) then return plate end
end

local function ResetClaims(self)
    self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
end

local function TargetChanged(self)
    ResetClaims(self)
    self.targetEnemy = self.source and IsEnemy("target")
    self.targetPlate = self.trackPlates and self.targetEnemy and GetPlate("target") or nil
end

local function WorldChanged(self)
    self.display:Clear()
    wipe(self.plates)
    TargetChanged(self)
    Gains.WorldChanged(self)
    if not self.trackPlates then return end
    local plates = C_NamePlate.GetNamePlates()
    if not S.Public(plates) or type(plates) ~= "table" then return end
    for i = 1, #plates do
        local plate = plates[i]
        if AccessiblePlate(plate) and plate.GetUnit then
            local unit = plate:GetUnit()
            if S.Public(unit) and type(unit) == "string" and IsEnemy(unit) then self.plates[unit] = plate end
        end
    end
end

local function PlateAdded(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local plate = IsEnemy(unit) and GetPlate(unit) or nil
    local previous = self.plates[unit]
    if previous and previous ~= plate then self.display:Clear(previous) end
    self.plates[unit] = plate
    if plate and not self.targetPlate and self.targetEnemy then self.targetPlate = GetPlate("target") end
end

local function PlateRemoved(self, _, unit)
    if not S.Public(unit) then return end
    local plate = self.plates[unit]
    if not plate then return end
    self.plates[unit] = nil
    if plate == self.targetPlate then
        self.targetPlate = nil
        ResetClaims(self)
    end
    self.display:Clear(plate)
end

-- Swing and cast windows approximate attribution. The frames and event
-- payload do not identify who caused a hit to the target.
local function Swing(self, _, _, swingType)
    if not self.targetEnemy or not S.Public(swingType) then return end
    local now = GetTime()
    if swingType == OFF_HAND then
        self.offHandUntil = now + MELEE_WINDOW
    elseif swingType == RANGED then
        self.mainHandUntil = now + RANGED_WINDOW
    else
        self.mainHandUntil = now + MELEE_WINDOW
    end
end

local function Cast(self, _, _, _, spellID)
    if not self.targetEnemy or not S.Public(spellID) or type(spellID) ~= "number" then return end
    local harmful = C_Spell.IsSpellHarmful(spellID)
    if S.Public(harmful) and harmful then self.castUntil = GetTime() + CAST_WINDOW end
end

local function Claim(self, school)
    local mainHand, offHand, cast = self.mainHandUntil, self.offHandUntil, self.castUntil
    if not mainHand and not offHand and not cast then return false end
    local now = GetTime()
    if cast and cast >= now and S.Public(school) and school ~= Enum.Damageclass.MaskPhysical then
        self.castUntil = nil
    elseif mainHand and mainHand >= now then
        self.mainHandUntil = nil
    elseif offHand and offHand >= now then
        self.offHandUntil = nil
    elseif cast and cast >= now then
        self.castUntil = nil
    else
        ResetClaims(self)
        return false
    end
    return true
end

local function EnemyCombat(self, _, unit, action, flag, amount, school)
    if not S.Public(unit) or not S.Public(action) then return end
    local plate
    if unit == "target" then
        if not self.targetEnemy then return end
        plate = self.targetPlate
    elseif self.source == ALL_ENEMIES then
        plate = self.plates[unit]
        -- A target hit can also arrive on its nameplate token.
        if not plate or plate == self.targetPlate then return end
    else
        return
    end
    if not S.Public(flag) then flag = nil end
    local outcome = Outcomes[action]
    local damage = action == "WOUND"
    if damage and FULL_MITIGATION[flag] then
        outcome, damage = Outcomes[flag], false
    end
    if not damage and not outcome then return end
    if self.source == ESTIMATED and not Claim(self, school) then return end
    local display = self.display
    if damage and display.enabled.hit then
        display:Show("hit", flag == "CRITICAL" or flag == "CRUSHING", "%s", amount, plate)
    elseif outcome and display.enabled.avoid then
        display:Show("avoid", false, nil, outcome, plate)
    end
end

local function Listen(self)
    local c, display, context = self.config, self.display, self.context
    local source = Feed.Enemy() and (c.showHits or c.showAvoidance) and c.hitSource or false
    local track = source ~= false and (source == ALL_ENEMIES or display:NeedsPlate()) or false
    if self.source == source and self.trackPlates == track then return end
    self.source, self.trackPlates = source, track
    context:RemoveEvent("UNIT_COMBAT")
    context:RemoveEvent("PLAYER_SWING")
    context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED")
    if source == ALL_ENEMIES then
        context:Event("UNIT_COMBAT", EnemyCombat, DIRECT)
    elseif source then
        context:Event("UNIT_COMBAT", EnemyCombat, nil, "target")
        if source == ESTIMATED then
            context:Event("PLAYER_SWING", Swing, DIRECT)
            context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, nil, "player")
        end
    end
    if source then context:Event("PLAYER_TARGET_CHANGED", TargetChanged) else context:RemoveEvent("PLAYER_TARGET_CHANGED") end
    if track then
        context:Event("NAME_PLATE_UNIT_ADDED", PlateAdded)
        context:Event("NAME_PLATE_UNIT_REMOVED", PlateRemoved)
    else
        context:RemoveEvent("NAME_PLATE_UNIT_ADDED")
        context:RemoveEvent("NAME_PLATE_UNIT_REMOVED")
    end
    WorldChanged(self)
end

local function HiddenWorldTextScale()
    local scale = C_CVar.GetCVar(WORLD_TEXT_CVAR)
    if S.Public(scale) and tonumber(scale) == HIDDEN_WORLD_TEXT_SCALE then return scale end
end

local function WorldTextChanged(self, _, key)
    if not S.Public(key) or type(key) ~= "string" or key:lower() ~= WORLD_TEXT_EVENT_KEY then return end
    local hidden = HiddenWorldTextScale() ~= nil
    if hidden ~= self.worldTextHidden then
        self.worldTextHidden = hidden
        Gains.Refresh(self)
    end
end

local function ReleaseWorldText(self)
    if NS.InCombat() then return end
    self.context:RemoveEvent("CVAR_UPDATE")
    self.context:RemoveEvent("PLAYER_LOGOUT")
    S.RestoreCVar(ID, WORLD_TEXT_CVAR)
    self.ownsWorldText, self.worldTextHidden = nil, nil
end

local function ApplyWorldText(self)
    if not NS.Client.isForever or NS.InCombat() then return end
    if not self.config.hideBlizzardWorldText then
        ReleaseWorldText(self)
    elseif self.ownsWorldText then
        self.worldTextHidden = HiddenWorldTextScale() ~= nil
    else
        -- The native world renderer has no off switch. This scale puts its
        -- pop-ups off-screen and persists across the combat boundary.
        local hiddenScale = HiddenWorldTextScale() or HIDDEN_WORLD_TEXT_SCALE
        self.worldTextHidden = self.context:CVar(WORLD_TEXT_CVAR, hiddenScale) and HiddenWorldTextScale() ~= nil
        if self.worldTextHidden then
            self.ownsWorldText = true
            self.context:Event("CVAR_UPDATE", WorldTextChanged, true)
            self.context:Event("PLAYER_LOGOUT", ReleaseWorldText, true)
        else
            S.RestoreCVar(ID, WORLD_TEXT_CVAR)
        end
    end
end

function M:Refresh()
    local c = self.config
    ApplyWorldText(self)
    self.display:Configure(c, S.ResolveFont(c.font) or S.GlobalFontPath())
    Listen(self)
    Gains.Refresh(self)
    if self.source and c.showHits and c.hideBlizzard then
        if not self.hidesBlizzard then self.hidesBlizzard = self.context:CVar(DAMAGE_CVAR, 0) end
    elseif self.hidesBlizzard then
        S.RestoreCVar(ID, DAMAGE_CVAR)
        self.hidesBlizzard = nil
    end
end

function M:Enable()
    if not self.display then
        local host = S.CreateFrame("Frame", nil, UIParent)
        host:SetAllPoints(UIParent)
        host:SetFrameStrata("HIGH")
        host:EnableMouse(false)
        self.display, self.plates = Display.New(host, CAPACITY), {}
    end
    self.context:Event("PLAYER_ENTERING_WORLD", WorldChanged)
    self:Refresh()
end

function M:Disable()
    if not self.display then return end
    self.display:Clear()
    wipe(self.plates)
    self.source, self.trackPlates, self.hidesBlizzard = nil, nil, nil
    self.ownsWorldText, self.worldTextHidden = nil, nil
    self.targetEnemy, self.targetPlate = nil, nil
    ResetClaims(self)
    Gains.Disable(self)
end

S.Install(ID, M)
