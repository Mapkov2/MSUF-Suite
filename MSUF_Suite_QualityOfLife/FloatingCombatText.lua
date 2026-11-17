local _, P = ...
local NS, S = P.NS, P.Suite
local ID, CAPACITY = "floatingCombatText", 24
local DAMAGE_CVAR = "floatingCombatTextCombatDamage_v2"
local DIRECT = { inCombat = true, direct = true }
local FULL_MITIGATION = { ABSORB = true, BLOCK = true, RESIST = true }
local MELEE_WINDOW, RANGED_WINDOW, CAST_WINDOW = 1.3, 2, 2.5
-- Forever's Enum.PlayerSwingType, defined in SwingTimerDocumentation.lua.
local OFF_HAND, RANGED = 1, 2
local M = {}

local function ReleasePlateSlot(self, plate)
    local count = self.activePlates[plate]
    self.activePlates[plate] = count > 1 and count - 1 or nil
end

local function Finished(animation)
    local slot, owner = animation.slot, animation.owner
    ReleasePlateSlot(owner, slot.plate)
    slot.plate = nil
    slot.frame:Hide()
end

local function ClearSlots(self, plate)
    if plate and not self.activePlates[plate] then return end
    for i = 1, CAPACITY do
        local slot = self.slots[i]
        if slot.plate and (not plate or slot.plate == plate) then
            slot.animation:Stop()
            Finished(slot.animation)
        end
    end
end

local function NewText(frame)
    local text = S.CreateFontString(frame, nil, "OVERLAY")
    text:SetAllPoints(frame)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text:SetTextColor(1, 0.82, 0)
    return text
end

local function Create(self)
    if self.slots then return end
    self.slots, self.plates, self.activePlates = {}, {}, {}
    for i = 1, CAPACITY do
        local frame = S.CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("HIGH")
        frame:EnableMouse(false)
        local normal, critical = NewText(frame), NewText(frame)
        critical:Hide()
        local animation = frame:CreateAnimationGroup()
        animation:SetScript("OnFinished", Finished)
        local move = animation:CreateAnimation("Translation")
        move:SetOrder(1)
        move:SetOffset(0, 42)
        local fade = animation:CreateAnimation("Alpha")
        fade:SetOrder(1)
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        local slot = { frame = frame, normal = normal, critical = critical, text = normal,
            animation = animation, move = move, fade = fade, x = ((i - 1) % 3 - 1) * 14 }
        animation.slot, animation.owner = slot, self
        self.slots[i] = slot
        frame:Hide()
    end
    self.cursor = 0
end

local function Style(self)
    ClearSlots(self)
    local c = self.config
    local critSize = c.fontSize * c.critScale / 100
    local font = S.ResolveFont(c.font) or S.GlobalFontPath()
    for i = 1, CAPACITY do
        local slot = self.slots[i]
        slot.anchor = nil
        slot.frame:ClearAllPoints()
        slot.frame:SetSize(math.max(120, critSize * 6), critSize * 1.5)
        S.SetFont(slot.normal, font, c.fontSize, "OUTLINE")
        S.SetFont(slot.critical, font, critSize, "OUTLINE")
        slot.move:SetDuration(c.duration)
        slot.fade:SetStartDelay(c.duration * .45)
        slot.fade:SetDuration(c.duration * .55)
    end
end

local function Paint(self, plate, flag, amount)
    self.cursor = self.cursor % CAPACITY + 1
    local slot = self.slots[self.cursor]
    local previous = slot.plate
    if previous then slot.animation:Stop() end
    if previous ~= plate then
        if previous then ReleasePlateSlot(self, previous) end
        self.activePlates[plate] = (self.activePlates[plate] or 0) + 1
        slot.plate = plate
    end
    if slot.anchor ~= plate then
        slot.frame:ClearAllPoints()
        slot.frame:SetPoint("BOTTOM", plate, "TOP", slot.x, self.config.offset)
        slot.anchor = plate
    end
    local critical = flag == "CRITICAL" or flag == "CRUSHING"
    local text = critical and slot.critical or slot.normal
    if slot.text ~= text then
        slot.text:Hide()
        text:Show()
        slot.text = text
    end
    -- UNIT_COMBAT's amount is secret on Forever. Pass it directly to the C text sink.
    text:SetFormattedText("%s", amount)
    if not previous then slot.frame:Show() end
    slot.animation:Play()
end

local function EnemyPlate(unit, plate)
    if not S.Public(plate) or type(plate) ~= "table" or NS.Safety.IsForbidden(plate) then return end
    local attackable = UnitCanAttack("player", unit)
    if S.Public(attackable) and attackable then return plate end
end

local function FindTarget(self)
    local plate = EnemyPlate("target", C_NamePlate.GetNamePlateForUnit("target"))
    if plate ~= self.targetPlate then
        self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
        self.targetPlate = plate
    end
end

local function TargetChanged(self)
    self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
    FindTarget(self)
end

local function WorldChanged(self)
    ClearSlots(self)
    wipe(self.plates)
    TargetChanged(self)
    local plates = C_NamePlate.GetNamePlates()
    for i = 1, #plates do
        local plate = plates[i]
        if S.Public(plate) and type(plate) == "table" and not NS.Safety.IsForbidden(plate) and plate.GetUnit then
            local unit = plate:GetUnit()
            if S.Public(unit) and type(unit) == "string" then self.plates[unit] = EnemyPlate(unit, plate) end
        end
    end
end

local function PlateAdded(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local plate = EnemyPlate(unit, C_NamePlate.GetNamePlateForUnit(unit))
    local previous = self.plates[unit]
    if previous and previous ~= plate then ClearSlots(self, previous) end
    self.plates[unit] = plate
    if not self.targetPlate and plate then FindTarget(self) end
end

local function PlateRemoved(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local plate = self.plates[unit]
    if not plate then return end
    self.plates[unit] = nil
    if plate == self.targetPlate then
        self.targetPlate = nil
        self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
    end
    ClearSlots(self, plate)
end

-- The public action events provide timing, not attribution. A consumed window
-- can admit at most one hit, and never carries over to a new target.
local function Swing(self, _, _, swingType)
    if not self.targetPlate or not S.Public(swingType) then return end
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
    if not self.targetPlate or not S.Public(spellID) or type(spellID) ~= "number" then return end
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
        self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
        return false
    end
    return true
end

local function Wound(unit, action, flag)
    return S.Public(action) and action == "WOUND" and S.Public(unit) and S.Public(flag)
        and not FULL_MITIGATION[flag]
end

local function AllHits(self, _, unit, action, flag, amount)
    if not Wound(unit, action, flag) then return end
    if unit == "target" then
        if self.targetPlate then Paint(self, self.targetPlate, flag, amount) end
    else
        local plate = self.plates[unit]
        -- The target has its own UNIT_COMBAT alias. Ignore its duplicate nameplate event.
        if plate and plate ~= self.targetPlate then Paint(self, plate, flag, amount) end
    end
end

local function EstimatedHits(self, _, unit, action, flag, amount, school)
    if not self.targetPlate or not Wound(unit, action, flag) or unit ~= "target" or not Claim(self, school) then return end
    Paint(self, self.targetPlate, flag, amount)
end

local function Listen(self)
    local context, estimate = self.context, self.config.hitSource == 1
    if estimate == self.estimate then return end
    self.estimate = estimate
    self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
    context:RemoveEvent("UNIT_COMBAT")
    if estimate then
        context:Event("UNIT_COMBAT", EstimatedHits, nil, "target")
        context:Event("PLAYER_SWING", Swing, DIRECT)
        context:Event("UNIT_SPELLCAST_SUCCEEDED", Cast, nil, "player")
    else
        context:Event("UNIT_COMBAT", AllHits, DIRECT)
        context:RemoveEvent("PLAYER_SWING")
        context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

function M:Refresh()
    Style(self)
    Listen(self)
    if self.config.hideBlizzard then
        if not self.hidesBlizzard then
            self.hidesBlizzard = self.context:CVar(DAMAGE_CVAR, 0)
        end
    elseif self.hidesBlizzard then
        S.RestoreCVar(ID, DAMAGE_CVAR)
        self.hidesBlizzard = nil
    end
end

function M:Enable()
    Create(self)
    WorldChanged(self)
    self.context:Event("NAME_PLATE_UNIT_ADDED", PlateAdded)
    self.context:Event("NAME_PLATE_UNIT_REMOVED", PlateRemoved)
    self.context:Event("PLAYER_TARGET_CHANGED", TargetChanged)
    self.context:Event("PLAYER_ENTERING_WORLD", WorldChanged)
    self:Refresh()
end

function M:Disable()
    if not self.slots then return end
    ClearSlots(self)
    wipe(self.plates)
    self.targetPlate, self.estimate, self.hidesBlizzard = nil, nil, nil
    self.mainHandUntil, self.offHandUntil, self.castUntil = nil, nil, nil
end

S.Install(ID, M)
