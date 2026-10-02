local _, P = ...
local NS, S = P.NS, P.Suite

-- Deliberately limited to known profession-appearance auras. Fishing's
-- appearance aura is excluded: removing it can also remove Underlight perks.
local SPELLS = {
    [394003] = "alchemy",
    [388658] = "blacksmithing",
    [391775] = "cooking",
    [394008] = "enchanting",
    [394007] = "engineering",
    [394005] = "herbalism",
    [394016] = "inscription",
    [394015] = "jewelcrafting",
    [394006] = "mining",
    [394011] = "skinning",
    [391312] = "tailoring",
    [394001] = "leatherworking",
}
local SPELL_IDS = { 394003, 388658, 391775, 394008, 394007, 394005,
    394016, 394015, 394001, 394006, 394011, 391312 }
-- Public spell + aura records: nether.wowhead.com/tooltip/spell/<id>, 2026-09-30.
local COSMETICS = { [16739] = "orbDeception", [16591] = "noggenfoggerSkeleton",
    [24708] = "holidayCostumes", [24709] = "holidayCostumes", [24710] = "holidayCostumes",
    [24711] = "holidayCostumes", [24712] = "holidayCostumes", [24713] = "holidayCostumes" }
local MAX_ATTEMPTS = 512
local M = { attempted = {}, attemptCount = 0 }

local function StopEvents(self)
    self.context:RemoveEvent("UNIT_AURA")
    self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
end

local function Block(self)
    self.blocked = true
    StopEvents(self)
    NS.Print(S.Text("Profession appearance removal was blocked by the client."))
end

local function Selected(self, spellID)
    local rule = SPELLS[spellID]
    return rule and self.config[rule] == true or self.extraSpells and self.extraSpells[spellID] == true
end

local function CancelKnownAura(self, aura)
    if self.blocked or not S.Public(aura) or type(aura) ~= "table" then return end
    local spellID, instanceID = aura.spellId, aura.auraInstanceID
    if not S.Finite(spellID) or not Selected(self, spellID)
        or not S.Finite(instanceID) or instanceID <= 0
        or not S.Public(aura.isHelpful) or aura.isHelpful ~= true
        or self.attempted[instanceID] or self.attemptCount >= MAX_ATTEMPTS then return end
    -- Mark before the restricted API call: a synchronous UNIT_AURA or a
    -- refused cancellation must never trigger an unbounded retry loop.
    self.attempted[instanceID] = true
    self.attemptCount = self.attemptCount + 1
    -- Restrictions may change between client builds. Fail closed after one
    -- refusal instead of retrying on every herb or node.
    if not S.QoLRestrictedCall(C_UnitAuras.CancelAuraByInstanceID, "player", instanceID) then
        Block(self)
    end
end

local function ScanKnown(self)
    if not self.active or self.blocked or NS.IsCombatLocked() then return end
    for _, spellID in ipairs(self.scanIDs or SPELL_IDS) do
        if Selected(self, spellID) then
            -- A restricted aura comes back as nothing (RequiresNonSecretAura).
            CancelKnownAura(self, C_UnitAuras.GetPlayerAuraBySpellID(spellID))
            if self.blocked then return end
        end
    end
end

local function RescanKnown(self)
    self.attempted, self.attemptCount = {}, 0
    ScanKnown(self)
end

local function UnitAura(self, _, unit, update)
    if not self.active or self.blocked or NS.IsCombatLocked()
        or not S.Public(unit) or unit ~= "player"
        or not S.Public(update) or type(update) ~= "table"
        or not S.Public(update.isFullUpdate) then return end
    if update.isFullUpdate == true then
        ScanKnown(self)
        return
    end
    local removed = update.removedAuraInstanceIDs
    if S.Public(removed) and type(removed) == "table" then
        for _, instanceID in ipairs(removed) do
            if S.Finite(instanceID) and self.attempted[instanceID] then
                self.attempted[instanceID] = nil
                self.attemptCount = self.attemptCount - 1
            end
        end
    end
    local added = update.addedAuras
    if S.Public(added) and type(added) == "table" then
        -- The event delta avoids a full aura scan on every player aura change.
        for i = 1, math.min(#added, 100) do CancelKnownAura(self, added[i]) end
    end
end

function M:Refresh()
    self.extraSpells, self.scanIDs = {}, {}
    for _, spellID in ipairs(SPELL_IDS) do self.scanIDs[#self.scanIDs + 1] = spellID end
    for spellID, rule in pairs(COSMETICS) do
        if self.config[rule] == true then
            self.extraSpells[spellID] = true
            self.scanIDs[#self.scanIDs + 1] = spellID
        end
    end
    local text = self.config.cosmeticSpellIDs or ""
    local extraCount = 0
    for idText in text:gmatch("%d+") do
        local id = tonumber(idText)
        if S.Finite(id) and id > 0 and id ~= 394009 and not SPELLS[id] and not self.extraSpells[id]
            and extraCount < 24 then
            self.extraSpells[id] = true
            self.scanIDs[#self.scanIDs + 1] = id
            extraCount = extraCount + 1
        end
    end
    self.blocked = nil
    self.attempted, self.attemptCount = {}, 0
    local any = false
    for _, spellID in ipairs(self.scanIDs) do
        if Selected(self, spellID) then
            any = true
            break
        end
    end
    if not any then
        StopEvents(self)
        return
    end
    self.context:Event("UNIT_AURA", UnitAura, nil, "player")
    self.context:Event("PLAYER_ENTERING_WORLD", RescanKnown)
    self.context:Event("PLAYER_REGEN_ENABLED", RescanKnown)
    ScanKnown(self)
end

function M:Enable() self:Refresh() end

function M:Disable()
    StopEvents(self)
    self.blocked = nil
    self.attempted, self.attemptCount = {}, 0
end

S.Install("professionAppearance", M)
