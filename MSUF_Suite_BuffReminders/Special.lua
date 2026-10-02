local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public = S.Public
local EVENTS = { "PET_BAR_UPDATE", "PET_UI_UPDATE", "UNIT_PET" }
-- A demon's other looks report their own creature family. The family a look
-- has is learned when a new pet appears within SUMMON_SECONDS after the
-- player started a summon spell of a known demon, and it is kept in the
-- account-wide MSUFSuiteDemonLooks (family -> demon key): the game's
-- families are the same for every character.
local SUMMON_SECONDS = 10
local summons, summonsFrom = {}, nil

-- summon spell -> demon, built once from the catalog's demon list.
local function Summons()
    local demons = NS.BuffReminderDemons
    if summonsFrom ~= demons then
        R.Clear(summons)
        for _, demon in ipairs(demons) do
            for _, spell in ipairs(demon.spells) do summons[spell] = demon end
        end
        summonsFrom = demons
    end
    return summons
end

local function Looks()
    local looks = _G.MSUFSuiteDemonLooks
    if type(looks) ~= "table" then
        looks = {}
        _G.MSUFSuiteDemonLooks = looks
    end
    return looks
end

local function PetGUID()
    local guid = UnitGUID("pet")
    return Public(guid) and guid or nil
end

-- callback(module, event, unit, target, castGUID, spellID): the player
-- started a cast; a summon of a known demon is remembered for its pet.
local function SummonSent(self, _, _, _, _, spellID)
    if not Public(spellID) then return end
    local demon = Summons()[spellID]
    if not demon then return end
    self.summonDemon, self.summonAt, self.summonPet = demon, GetTime(), PetGUID()
end

function R.SyncSpecialEvents(self, callback)
    local c = self.config
    local wanted = not self.suspended and (c.petPassiveWarning or c.demonChoiceWarning)
    for _, event in ipairs(EVENTS) do
        if wanted then R.Listen(self, event, callback)
        else self.context:RemoveEvent(event) end
    end
    if not self.suspended and c.demonChoiceWarning then
        R.Listen(self, "UNIT_SPELLCAST_SENT", SummonSent, "player")
    else
        self.context:RemoveEvent("UNIT_SPELLCAST_SENT")
    end
end

-- The demon a family belongs to: a base family, a look learned from the
-- summon the player just made, or a look learned before.
local function DemonOf(self, family)
    for _, demon in ipairs(NS.BuffReminderDemons) do
        if demon.family == family then return demon end
    end
    local pending = self.summonDemon
    if pending and GetTime() - self.summonAt <= SUMMON_SECONDS and PetGUID() ~= self.summonPet then
        self.summonDemon = nil
        Looks()[family] = pending.key
        return pending
    end
    local key = Looks()[family]
    for _, demon in ipairs(NS.BuffReminderDemons) do
        if demon.key == key then return demon end
    end
end

-- The summoned demon against the demons the player ticked. A family no base
-- demon and no learned look names is never judged. No warning is possible
-- without a known summon spell of a ticked demon.
local function ReadDemon(self)
    self.wrongDemon = nil
    if not self.config.demonChoiceWarning then return end
    local _, class = UnitClass("player")
    if not Public(class) or class ~= "WARLOCK" then return end
    local _, family = UnitCreatureFamily("pet")
    if not Public(family) or type(family) ~= "number" then return end
    local current = DemonOf(self, family)
    if not current then return end
    -- One known summon of a ticked demon is enough.
    local chosen = false
    for _, demon in ipairs(NS.BuffReminderDemons) do
        if self.config[demon.key] ~= false then
            for _, spell in ipairs(demon.spells) do
                if R.Known(spell) then chosen = true; break end
            end
        end
        if chosen then break end
    end
    if chosen then self.wrongDemon = self.config[current.key] == false end
end

-- Blizzard's pet bar names the stance actions by token (PetActionBar.lua);
-- the passive stance is active when its token reports active.
function R.ReadPet(self)
    self.petPassive, self.wrongDemon = nil, nil
    local c = self.config
    if not (c.petPassiveWarning or c.demonChoiceWarning) or NS.IsCombatLocked() then return end
    local exists, dead = UnitExists("pet"), UnitIsDeadOrGhost("pet")
    if not Public(exists) or exists ~= true or not Public(dead) or dead ~= false then return end
    ReadDemon(self)
    if not c.petPassiveWarning then return end
    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, _, token, active = GetPetActionInfo(i)
        if Public(name) and name == "PET_MODE_PASSIVE" and Public(token) and token == true
            and Public(active) then self.petPassive = active == true; return end
    end
end

function R.ReadHealthstone(self)
    self.healthstoneMissing = nil
    if not self.config.healthstoneFromWarlock or not self.groupClasses or not self.groupClasses.WARLOCK then return end
    local stones = NS.Client.isForever and R.FOREVER_HEALTHSTONES or R.HEALTHSTONES
    local unknown = false
    for _, id in ipairs(stones) do
        local count = R.ItemCount(id)
        if count and count > 0 then self.healthstoneMissing = false; return end
        if count == nil then unknown = true end
    end
    if not unknown then self.healthstoneMissing = true end
end

-- One line per active notice, in this order.
local NOTICES = {
    { field = "petPassive", text = "Pet is set to passive." },
    { field = "healthstoneMissing", text = "No Healthstone in your bags, and a Warlock is here." },
    { field = "soulstoneMissing", text = "Your Soulstone is on nobody in the group." },
    { field = "beaconMissing", text = "One of your Beacons is on nobody in the group." },
    { field = "wrongDemon", text = "This demon is not one you chose; summon another." },
}

-- Runs on every evaluation; the text is rebuilt only when the set of active
-- notices changed.
function R.SpecialText(self, allowed)
    local mask = 0
    if allowed then
        for i, notice in ipairs(NOTICES) do
            if self[notice.field] then mask = mask + 2 ^ (i - 1) end
        end
    end
    if self.specialMask == mask then return end
    self.specialMask = mask
    local text = ""
    for i, notice in ipairs(NOTICES) do
        if mask % 2 ^ i >= 2 ^ (i - 1) then
            text = text == "" and S.Text(notice.text) or text .. "\n" .. S.Text(notice.text)
        end
    end
    self.specialText = text
    local label = self.specialWarning
    if not label and text ~= "" then
        label = S.CreateFontString(self.host, nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOP", self.host, "BOTTOM", 0, -6)
        self.specialWarning = label
    end
    if label then label:SetText(text); label:SetShown(text ~= "") end
end

-- No notice line (Edit Mode preview, disable).
function R.HideSpecialText(self)
    R.SpecialText(self, false)
end
