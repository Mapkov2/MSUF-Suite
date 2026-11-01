local _, P = ...
local NS, S = P.NS, P.Suite
local Visuals = P.GlimmerVisuals
local M = { cursors = {} }
local UNIT = "softinteract"
local IN_COMBAT = { inCombat = true }
local CURSORS = { Mine = "ore", GatherHerbs = "herb", Quest = "quest", QuestTurnIn = "quest", QuestRepeatable = "quest" }
local EVENTS = { "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

local function CursorKinds(self)
    for name, kind in pairs(CURSORS) do
        for _, prefix in ipairs({ "", "Unable" }) do
            local id = GetFileIDFromPath("Interface\\Cursor\\" .. prefix .. name)
            if S.Finite(id) and id > 0 then self.cursors[id] = kind end
        end
    end
end

local function Category(self)
    local exists = UnitExists(UNIT)
    if not S.Public(exists) or exists ~= true then return nil end
    local object = UnitIsGameObject(UNIT)
    if not S.Public(object) or object ~= true then return nil end
    if SetUnitCursorTexture(self.probe, UNIT) then
        local texture = self.probe:GetTexture()
        if not S.Public(texture) then return nil end
        local kind = self.cursors[texture]
        if kind then return kind end
    end
    local related = C_QuestLog.UnitIsRelatedToActiveQuest(UNIT)
    if S.Public(related) and related == true then return "quest" end
    return "other"
end

local function Update(self, event)
    if not self.host then return end
    if NS.InCombat(event) or S.editMode then return Visuals.Hide(self.host) end
    local instance = S.InstanceKind()
    if instance == nil or self.config.hideInstances and instance ~= "world" then
        return Visuals.Hide(self.host)
    end
    local category = Category(self)
    if not category or not self.config[category] then return Visuals.Hide(self.host) end
    local plate = C_NamePlate.GetNamePlateForUnit(UNIT)
    if not S.Public(plate) or not plate or plate == self.removedPlate then return Visuals.Hide(self.host) end
    local forbidden = plate:IsForbidden()
    if not S.Public(forbidden) or forbidden then return Visuals.Hide(self.host) end
    self.plate = plate
    Visuals.Show(self.host, plate, self.config)
end

local function Apply(self)
    if NS.InCombat() then
        self.pending = true
        return Visuals.Hide(self.host)
    end
    self.pending = nil
    -- These native controls supply one nearby interactable object's anchor.
    -- The context owns restoration; later external edits are not overwritten.
    if not S.GamepadUI() then self.context:CVar("SoftTargetInteract", "3") end
    self.context:CVar("SoftTargetNameplateInteract", "1")
    self.context:CVar("SoftTargetIconGameObject", "1")
    self.context:CVar("SoftTargetInteractRange", self.config.range)
    Update(self)
end

local function Event(self, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" or event == "NAME_PLATE_UNIT_ADDED" then
        local plate = S.Public(unit) and unit and C_NamePlate.GetNamePlateForUnit(unit)
        if S.Public(plate) and plate then
            if event == "NAME_PLATE_UNIT_REMOVED" and plate == self.plate then
                self.removedPlate, self.plate = plate, nil
                return Visuals.Hide(self.host)
            elseif event == "NAME_PLATE_UNIT_ADDED" and plate == self.removedPlate then
                self.removedPlate = nil
            end
        end
    end
    if event == "PLAYER_REGEN_ENABLED" and self.pending then return Apply(self) end
    Update(self, event)
end

function M:Enable()
    self.host = self.host or Visuals.Create()
    self.probe = self.probe or S.CreateTexture(self.host, nil, "BACKGROUND")
    self.probe:Hide()
    CursorKinds(self)
    for _, event in ipairs(EVENTS) do self.context:Event(event, Event, IN_COMBAT) end
    Apply(self)
end

function M:Refresh()
    Apply(self)
end

function M:Disable()
    self.pending, self.plate, self.removedPlate = nil, nil, nil
    if self.host then Visuals.Hide(self.host) end
end

S.Install("glimmer", M)
