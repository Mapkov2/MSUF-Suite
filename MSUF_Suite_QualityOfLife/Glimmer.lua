local _, P = ...
local NS, S = P.NS, P.Suite
local Visuals = P.GlimmerVisuals
local M = { cursors = {}, changedCVars = {} }
local UNIT = "softinteract"
local IN_COMBAT = { inCombat = true }
local SPARKLE = "outlineModeShowLootEffectWhenDisabled"
local CURSORS = { Mine = "ore", GatherHerbs = "herb", Quest = "quest", QuestTurnIn = "quest", QuestRepeatable = "quest",
    Skin = "skinning", SkinAlliance = "skinning", SkinHorde = "skinning" }
local CURSOR_WORDS = { mine = "ore", herb = "herb", quest = "quest", important = "quest",
    recurring = "quest", wrapper = "quest" }
local OBJECT_CVARS = { softtargeticongameobject = "SoftTargetIconGameObject",
    softtargetinteractonlyinrange = "SoftTargetInteractOnlyInRange" }
local EVENTS = { "CVAR_UPDATE", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

local function CursorKinds(self)
    for name, kind in pairs(CURSORS) do
        for _, prefix in ipairs({ "", "Unable" }) do
            local stem = prefix .. name
            self.cursors[stem:lower()] = kind
            local path = "Interface\\Cursor\\" .. stem
            local id = GetFileIDFromPath(path)
            if not S.Finite(id) or id <= 0 then id = GetFileIDFromPath(path .. ".blp") end
            if S.Finite(id) and id > 0 then self.cursors[id] = kind end
        end
    end
end

local function CursorCategory(self)
    local hasCursor = SetUnitCursorTexture(self.probe, UNIT, nil, true)
    if not S.Public(hasCursor) then return nil, true end
    if not hasCursor then return nil end
    local texture = self.probe:GetTexture()
    if not S.Public(texture) then return nil, true end
    local kind = self.cursors[texture]
    if kind then return kind end
    if type(texture) == "string" then
        local name = texture:lower()
        local file = name:match("[^\\/]+$")
        if file then
            local stem = file:gsub("^cursor ", "")
            stem = stem:match("^crosshair_(.+)_64$") or stem:gsub("%.blp$", "")
            kind = self.cursors[stem]
            if kind then return kind end
        end
        for word, category in pairs(CURSOR_WORDS) do
            if name:find(word, 1, true) then return category end
        end
    end
end

local function TooltipHasLine(field, expected)
    local data = C_TooltipInfo.GetUnit(UNIT)
    if not S.Public(data) or not data then return false end
    local lines = data.lines
    if not S.Public(lines) or not lines then return false end
    for _, line in ipairs(lines) do
        if S.Public(line) and line then
            local value = line[field]
            if S.Public(value) then
                if value == expected then return true end
                if field == "leftText" and type(value) == "string"
                    and value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == expected then return true end
            end
        end
    end
    return false
end

local function SkinningCategory(self)
    local dead = UnitIsDead(UNIT)
    if not S.Public(dead) or dead ~= true then return nil end
    local kind, private = CursorCategory(self)
    if private then return nil end
    if kind == "skinning" then return kind end
    local label = UNIT_SKINNABLE_LEATHER
    if label and TooltipHasLine("leftText", label) then return "skinning" end
end

local function Category(self)
    -- World objects are not normal units; the native nameplate controller checks this separately.
    local object = UnitIsGameObject(UNIT)
    if not S.Public(object) then return nil end
    if object ~= true then
        if self.config.skinning then return SkinningCategory(self) end
        return nil
    end
    local kind, private = CursorCategory(self)
    if private then return nil end
    if kind then return kind end
    local related = C_QuestLog.UnitIsRelatedToActiveQuest(UNIT)
    if S.Public(related) and related == true then return "quest" end
    if self.config.quest and TooltipHasLine("type", Enum.TooltipDataLineType.QuestObjective) then return "quest" end
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

local function LootClosed(self, event)
    Update(self, event)
    -- The interaction state can settle after the loot window closes.
    if not NS.InCombat(event) then self.context:After(0.1, Update) end
end

local function RememberCurrent(self, key)
    local current = C_CVar.GetCVar(key)
    if S.Public(current) and current ~= nil then self.context:CVar(key, current, true) end
end

local function ApplySparkle(self)
    if NS.InCombat() then
        self.pendingSparkle = true
        return
    end
    self.pendingSparkle = nil
    self.applying = true
    if self.config.questSparkle ~= false then
        self.context:CVar(SPARKLE, "1", self.changedCVars[SPARKLE])
    else
        self.context:Cancel(ApplySparkle)
        if self.changedCVars[SPARKLE] then RememberCurrent(self, SPARKLE) end
        S.RestoreCVar("glimmer", SPARKLE)
    end
    self.changedCVars[SPARKLE] = nil
    self.applying = nil
end

local function Apply(self)
    if NS.InCombat() then
        self.pending = true
        return Visuals.Hide(self.host)
    end
    self.pending = nil
    self.applying = true
    -- These native controls supply one nearby interactable object's anchor.
    -- Reassert required object controls while remembering the latest external choice.
    if not S.GamepadUI() then self.context:CVar("SoftTargetInteract", "3") end
    self.context:CVar("SoftTargetNameplateInteract", "1")
    self.context:CVar("SoftTargetIconGameObject", "1", self.changedCVars.SoftTargetIconGameObject)
    self.context:CVar("SoftTargetInteractOnlyInRange", "0", self.changedCVars.SoftTargetInteractOnlyInRange)
    self.changedCVars.SoftTargetIconGameObject, self.changedCVars.SoftTargetInteractOnlyInRange = nil, nil
    self.context:CVar("SoftTargetInteractRange", self.config.range)
    self.context:CVar("SoftTargetInteractArc", "2")
    self.applying = nil
    ApplySparkle(self)
    -- Looting or skinning can change the cursor without changing the interact target.
    if self.config.skinning then
        self.context:Event("LOOT_CLOSED", LootClosed, IN_COMBAT)
    else
        self.context:RemoveEvent("LOOT_CLOSED")
        self.context:Cancel(Update)
    end
    Update(self)
end

local function Event(self, event, unit)
    if event == "CVAR_UPDATE" then
        if self.applying or not S.Public(unit) or type(unit) ~= "string" then return end
        local name = unit:lower()
        if name == "graphicsquality" or name == "raidgraphicsquality" or name == SPARKLE:lower() then
            if self.config.questSparkle == false then return end
            if name == SPARKLE:lower() then
                local value = C_CVar.GetCVar(SPARKLE)
                if not S.Public(value) or value == nil or value == "1" then return end
                self.changedCVars[SPARKLE] = true
            end
            return self.context:After(1, ApplySparkle)
        end
        local key = OBJECT_CVARS[name]
        if not key then return end
        local value = C_CVar.GetCVar(key)
        local wanted = key == "SoftTargetIconGameObject" and "1" or "0"
        if not S.Public(value) or value == nil or value == wanted then return end
        -- The next safe apply adopts the current setting as the restore value.
        self.changedCVars[key] = true
        return Apply(self)
    end
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
    if event == "PLAYER_REGEN_ENABLED" and (self.pending or self.pendingSparkle) then return Apply(self) end
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
    self.applying = true
    -- The controller can disable us before our own combat-end callback runs.
    -- Adopting an unchanged current value records it without a native write.
    for key in pairs(self.changedCVars) do
        RememberCurrent(self, key)
        self.changedCVars[key] = nil
    end
    self.pending, self.pendingSparkle, self.plate, self.removedPlate, self.applying = nil, nil, nil, nil, nil
    self.context:Cancel(ApplySparkle)
    self.context:Cancel(Update)
    if self.host then Visuals.Hide(self.host) end
end

S.Install("glimmer", M)
