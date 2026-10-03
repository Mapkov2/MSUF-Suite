local _, P = ...
local NS, S = P.NS, P.Suite
local ID, CAPACITY = "selfCombatText", 20
local POINTS = NS.AnchorPoints
local IN_COMBAT = { inCombat = true }
local M = {}

-- Blizzard_CombatText/Shared/CombatText.lua on live and forever reads this
-- synchronous event immediately. Its payload is a public message type;
-- GetCurrentEventInfo's numbers may be secret and reach only the C text sink.
local KINDS = {
    DAMAGE = 1, SPELL_DAMAGE = 1, DAMAGE_SHIELD = 1, SPLIT_DAMAGE = 1,
    DAMAGE_CRIT = 2, SPELL_DAMAGE_CRIT = 2,
    BLOCK = 5, SPELL_BLOCK = 5, RESIST = 5, SPELL_RESIST = 5, ABSORB = 5, SPELL_ABSORB = 5,
    HEAL = 3, PERIODIC_HEAL = 3, HEAL_ABSORB = 3, PERIODIC_HEAL_ABSORB = 3,
    HEAL_CRIT = 4, PERIODIC_HEAL_CRIT = 4, HEAL_CRIT_ABSORB = 4,
}

local function Finished(animation)
    animation.owner:Hide()
end

local function Clear(self)
    if not self.slots then return end
    for i = 1, CAPACITY do
        local slot = self.slots[i]
        slot.animation:Stop()
        slot.frame:Hide()
    end
    self.cursor = 0
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    self.host, self.slots = host, {}
    for i = 1, CAPACITY do
        local frame = S.CreateFrame("Frame", nil, host)
        frame:EnableMouse(false)
        local text = S.CreateFontString(frame, nil, "OVERLAY")
        text:SetAllPoints(frame)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(false)
        local animation = frame:CreateAnimationGroup()
        animation.owner = frame
        animation:SetLooping("NONE")
        animation:SetScript("OnFinished", Finished)
        local move = animation:CreateAnimation("Translation")
        move:SetOrder(1)
        local fade = animation:CreateAnimation("Alpha")
        fade:SetOrder(1)
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        self.slots[i] = { frame = frame, text = text, animation = animation, move = move, fade = fade }
        frame:Hide()
    end
    host:Hide()
end

local function Layout(self)
    Clear(self)
    local c, host = self.config, self.host
    self.normalSize, self.critSize = c.fontSize, c.fontSize * c.critScale / 100
    self.damageR, self.damageG, self.damageB = S.RGB(c.damageColor)
    self.healR, self.healG, self.healB = S.RGB(c.healColor)
    host:SetSize(c.width, c.distance + self.critSize * 2)
    host:ClearAllPoints()
    local point = POINTS[c.point] or "CENTER"
    host:SetPoint(point, UIParent, point, c.x, c.y)
    local upward = c.direction == 1
    for i = 1, CAPACITY do
        local slot = self.slots[i]
        slot.frame:SetSize(c.width * .65, self.critSize * 1.5)
        slot.frame:ClearAllPoints()
        -- Four narrow lanes spread bursts without inspecting values, walking
        -- active messages or changing any position during the animation.
        local x = ((i - 1) % 4 - 1.5) * c.width * .12
        slot.frame:SetPoint(upward and "BOTTOM" or "TOP", host,
            upward and "BOTTOM" or "TOP", x, 0)
        S.SetFont(slot.text, nil, c.fontSize, "OUTLINE")
        slot.size, slot.kind = c.fontSize, nil
        slot.move:SetOffset(0, upward and c.distance or -c.distance)
        slot.move:SetDuration(c.duration)
        slot.fade:SetStartDelay(c.duration * .6)
        slot.fade:SetDuration(c.duration * .4)
    end
    host:Show()
end

local function Paint(self, slot, kind, amount)
    local heal, crit = kind >= 3, kind == 2 or kind == 4
    local size = crit and self.critSize or self.normalSize
    if slot.size ~= size then
        slot.text:SetFontHeight(size)
        slot.size = size
    end
    local color = heal and 3 or 1
    if slot.kind ~= color then
        if heal then
            slot.text:SetTextColor(self.healR, self.healG, self.healB)
        else
            slot.text:SetTextColor(self.damageR, self.damageG, self.damageB)
        end
        slot.kind = color
    end
    -- No comparisons, concatenation, tonumber, arithmetic or Lua formatting
    -- on amount. SetFormattedText accepts secret arguments even when tainted.
    slot.text:SetFormattedText(heal and "+%s" or "-%s", amount)
    slot.frame:SetAlpha(1)
    slot.frame:Show()
end

local function CombatText(self, _, messageType)
    if not self.active or self.preview then return end
    local kind = KINDS[messageType]
    if not kind then return end
    local heal = kind == 3 or kind == 4
    if (heal and not self.config.showHealing) or (not heal and not self.config.showDamage) then return end
    -- This getter is meaningful only inside COMBAT_TEXT_UPDATE: never defer it.
    local first, second = self.api.GetCurrentEventInfo()
    if kind == 5 then
        -- Partial mitigation carries damage in the first field. Blizzard
        -- uses the second field (arg3) to distinguish full block/resist
        -- notices; a public nil there carries no damage message.
        if S.Public(second) and second == nil then return end
        kind = 1
    end
    self.cursor = self.cursor % self.config.maxMessages + 1
    local slot = self.slots[self.cursor]
    slot.animation:Stop()
    if heal then Paint(self, slot, kind, second) else Paint(self, slot, kind, first) end
    slot.animation:Play()
end

local function SelectUnit(self)
    -- Same player/vehicle selection as Blizzard's UpdateDisplayedMessages.
    -- This API selects a shared engine stream; preserve the previous owner.
    local unit = UnitHasVehicleUI("player") and "vehicle" or "player"
    if self.api.GetActiveUnit() ~= unit then self.api.SetActiveUnit(unit) end
    self.ownedUnit = unit
end

local function UnitChanged(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" or unit == "player" then SelectUnit(self) end
end

local function Preview(self)
    self.preview = S.editMode == true
    if not self.preview then return end
    if self.config.showDamage then Paint(self, self.slots[1], 2, "1234") end
    if self.config.showHealing then Paint(self, self.slots[4], 3, "567") end
end

local function HideBlizzard(self)
    local frame = _G.CombatText
    if not frame then return false end
    -- live/forever CombatText.xml has no OnHide script and no protected
    -- template. Hiding it also suspends Blizzard's otherwise-idle OnUpdate.
    if not frame:IsForbidden() and not frame:IsProtected() then
        self.context:Property(frame, "IsShown", "SetShown", false)
    end
    self.context:RemoveEvent("ADDON_LOADED")
    return true
end

local function NativeLoaded(self, _, addon)
    if addon == "Blizzard_CombatText" then HideBlizzard(self) end
end

function M:Enable()
    self.api = C_CombatText
    self.previousUnit = self.api.GetActiveUnit()
    Create(self)
    Layout(self)
    -- Suite's declared CVar ownership also recovers after a crash or when
    -- this load-on-demand addon is disabled. Later external changes win.
    self.context:CVar("enableFloatingCombatText", 0)
    if not HideBlizzard(self) then self.context:Event("ADDON_LOADED", NativeLoaded, IN_COMBAT) end
    SelectUnit(self)
    self.context:Event("COMBAT_TEXT_UPDATE", CombatText, IN_COMBAT)
    self.context:Event("PLAYER_ENTERING_WORLD", UnitChanged, IN_COMBAT)
    self.context:Event("UNIT_ENTERED_VEHICLE", UnitChanged, IN_COMBAT, "player")
    self.context:Event("UNIT_EXITING_VEHICLE", UnitChanged, IN_COMBAT, "player")
    Preview(self)
end

function M:Refresh()
    HideBlizzard(self)
    Layout(self)
    Preview(self)
end

function M:HideEditPreview()
    Clear(self)
    self.preview = false
end

function M:Disable()
    Clear(self)
    if self.host then self.host:Hide() end
    if self.api and self.previousUnit and self.api.GetActiveUnit() == self.ownedUnit then
        self.api.SetActiveUnit(self.previousUnit)
    end
    self.previousUnit, self.ownedUnit, self.preview = nil, nil, false
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "text", {
        label = "Own combat text", order = 658,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "fontSize", "distance", "direction" },
        sizeKeys = { "width", "fontSize", "distance" },
    })
end

S.Install(ID, M)
