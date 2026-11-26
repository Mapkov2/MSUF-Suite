local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public = S.Public
local function NextSelfBuff(self)
    for _, entry in ipairs(self.list.entries or {}) do
        if entry.kind == "spell" and not entry.dismissed and not entry.ally
            and not entry.slot and not entry.notice and not entry.unit then
            if not entry.group and entry.present == false then return entry.spellName or entry.id end
            if entry.castBuff and entry.group and self.config.classBuff
                and R.GroupBuffOn("player", entry.aliases, entry.ranked, true) == false then
                return entry.spellName or entry.id
            end
        end
    end
end

local function ArmBuffClick(button, spell, unit)
    button:SetAttribute("spell1", spell)
    button:SetAttribute("unit", unit)
    button:SetAttribute("type1", "spell")
end

local function DisarmBuffClick(button, mouseButton)
    if mouseButton == "LeftButton" and button:GetAttribute("type1") and not NS.InCombat() then
        button:SetAttribute("type1", nil)
    end
end

local function GroupCastAllowed(self)
    local instance = self.environment.instanceType
    if not self.config.castGroupBuffs or not instance or instance == "arena" or instance == "pvp" then return false end
    local dead, vehicle = UnitIsDeadOrGhost("player"), UnitInVehicle("player")
    return Public(dead) and dead == false and Public(vehicle) and vehicle == false
end

function R.PrepareGroupBuffClick(self, button, mouseButton, down)
    local entry = button.entry
    if mouseButton ~= "LeftButton" or not entry or not entry.castBuff or NS.InCombat() then return end
    if (down == true) ~= SecureActionButton_ShouldUseOnKeyDown(button) then return end
    DisarmBuffClick(button, mouseButton)
    if not self.active or S.editMode or not self.view.allowed or not GroupCastAllowed(self) then return end
    local unit = R.MissingGroupCastUnit(entry.castBuff, entry.id, self.config.classBuff)
    -- An advance warning for our own active buff remains a self cast.
    if not unit and self.config.classBuff and entry.present == true and entry.expiresAt
        and R.GroupBuffOn("player", entry.aliases, entry.ranked, true) == true then
        unit = "player"
    end
    if unit then ArmBuffClick(button, entry.spellName or entry.id, unit) end
end

function R.FinishGroupBuffClick(button, mouseButton)
    if button.entry and button.entry.castBuff then DisarmBuffClick(button, mouseButton) end
end

local function FindGroupCast(buff)
    if not buff then return end
    local cast = R.RaidBuffCast(buff)
    if not cast then return end
    local unit = R.MissingGroupCastUnit(buff, cast, false)
    if unit then
        local name = NS.Client.isForever and R.RankName(cast)
        return name or cast, unit
    end
end

local function NextGroupBuff()
    local class = R.PlayerClass()
    if not class then return end
    local spell, unit = FindGroupCast(R.ClassBuff(class))
    if spell then return spell, unit end
    return FindGroupCast(R.ExtraClassBuff(class))
end

local function PrepareBuffKey(self, button, mouseButton, down)
    if mouseButton ~= "LeftButton" or down or NS.InCombat() then return end
    DisarmBuffClick(button, mouseButton)
    if not self.active or not self.view.buffKeyEnabled or S.editMode then return end
    if SecureCmdOptionParse("[petbattle][vehicleui] blocked") then return end
    local spell, unit
    if GroupCastAllowed(self) then spell, unit = NextGroupBuff() end
    if not spell and self.config.selfBuffKey and self.view.allowed then spell, unit = NextSelfBuff(self), "player" end
    if spell then ArmBuffClick(button, spell, unit) end
end

function R.EnsureBuffKey(self)
    local view = self.view
    if not view.buffKeyEnabled or view.selfBuffButton or NS.InCombat() then return end
    -- Blizzard's template performs the bound action only outside lockdown.
    -- Nothing needs to watch combat or refresh a target between key presses.
    local button = S.CreateFrame("Button", "MSUFSuiteSelfBuff", UIParent, "InsecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(_, mouseButton, down) PrepareBuffKey(self, button, mouseButton, down) end)
    button:SetScript("PostClick", DisarmBuffClick)
    view.selfBuffButton = button
end

function R.RefreshSpecialControls(self)
    R.StyleNotices(self)
    self.view.afterUpdate = R.SyncCursor
    self.view.buffKeyEnabled = self.config.selfBuffKey or self.config.castGroupBuffs
    R.EnsureBuffKey(self)
end

function R.ReleaseSpecialControls(self)
    R.HideSpecialText(self)
    R.CloseReadyRaidBuffNames(self)
    self.view.buffKeyEnabled = false
end

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
    local notices = self.notices
    notices.summonDemon, notices.summonAt, notices.summonPet = demon, GetTime(), PetGUID()
end

function R.SyncSpecialEvents(self, callback)
    local c = self.config
    local suspended = self.listen.suspended
    local wanted = not suspended and (c.petPassiveWarning or c.demonChoiceWarning or R.WantsSacrifice(self))
    if NS.Client.isForever then
        if not suspended and R.WantsForeverTracking(self) then
            R.Listen(self, "MINIMAP_UPDATE_TRACKING", callback)
        else
            self.context:RemoveEvent("MINIMAP_UPDATE_TRACKING")
        end
    end
    for _, event in ipairs(EVENTS) do
        if wanted then
            R.Listen(self, event, callback)
        else
            self.context:RemoveEvent(event)
        end
    end
    if not suspended and c.demonChoiceWarning then
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
    local notices = self.notices
    local pending = notices.summonDemon
    if pending and GetTime() - notices.summonAt <= SUMMON_SECONDS and PetGUID() ~= notices.summonPet then
        notices.summonDemon = nil
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
    local notices = self.notices
    notices.wrongDemon = nil
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
                if R.Known(spell) then
                    chosen = true
                    break
                end
            end
        end
        if chosen then break end
    end
    if chosen then notices.wrongDemon = self.config[current.key] == false end
end

-- Blizzard's pet bar names the stance actions by token (PetActionBar.lua);
-- the passive stance is active when its token reports active.
function R.ReadPet(self)
    local notices = self.notices
    notices.petPassive, notices.wrongDemon = nil, nil
    local c = self.config
    if not (c.petPassiveWarning or c.demonChoiceWarning) or NS.IsCombatLocked() then return end
    local exists, dead = UnitExists("pet"), UnitIsDeadOrGhost("pet")
    if not Public(exists) or exists ~= true or not Public(dead) or dead ~= false then return end
    ReadDemon(self)
    if not c.petPassiveWarning then return end
    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, _, token, active = GetPetActionInfo(i)
        if Public(name) and name == "PET_MODE_PASSIVE" and Public(token) and token == true
            and Public(active) then
            notices.petPassive = active == true
            return
        end
    end
end

function R.PetChanged(self)
    if self.stock.sacrifice ~= nil and R.SacrificeChanged(self) then
        self:Compile()
    else
        R.ReadPet(self)
    end
    self:Update("visual")
end

function R.ReadHealthstone(self)
    local notices, classes = self.notices, self.group.classes
    notices.healthstoneMissing = nil
    if not self.config.healthstoneFromWarlock or not classes or not classes.WARLOCK
        or not self.group.unitList or #self.group.unitList < 2 then return end
    local stones = NS.Client.isForever and R.FOREVER_HEALTHSTONES or R.HEALTHSTONES
    local unknown = false
    for _, id in ipairs(stones) do
        local count = R.ItemCount(id)
        if count and count > 0 then
            notices.healthstoneMissing = false
            return
        end
        if count == nil then unknown = true end
    end
    if not unknown then notices.healthstoneMissing = true end
end

-- One line per active notice, in this order; field is the notice's state
-- field (State.lua, notices).
local NOTICES = {
    { field = "petPassive", text = "Pet is set to passive." },
    { field = "healthstoneMissing", text = "No Healthstone in your bags, and a Warlock is here." },
    { field = "soulstoneMissing", text = "Your Soulstone is on nobody in the group.", ally = true },
    { field = "beaconMissing", text = "One of your Beacons is on nobody in the group.", ally = true },
    { field = "wrongDemon", text = "This demon is not one you chose; summon another." },
}

local NOTICE_GAP = 6

-- The notice lines follow the "Notice text size" setting and hang below the
-- row, or above it with a bottom anchor (R.PlaceNote); a settings change calls
-- this (Refresh) and the label's creation does.
function R.StyleNotices(self)
    local label = self.notices.label
    if not label then return end
    R.PlaceNote(label, self.view.host, self.config, true, NOTICE_GAP)
    R.StyleNote(label, GameFontNormal, self.config.noticeSize or R.Default("noticeSize"))
end

-- Runs on every evaluation; the text is rebuilt only when the set of active
-- notices changed.
function R.SpecialText(self, allowed)
    local notices = self.notices
    local mask = 0
    if allowed then
        for i, notice in ipairs(NOTICES) do
            if notices[notice.field] and (not notice.ally or R.CanRemindAlly(self)) then mask = mask + 2 ^ (i - 1) end
        end
    end
    if notices.mask == mask then return end
    notices.mask = mask
    local text = ""
    for i, notice in ipairs(NOTICES) do
        if mask % 2 ^ i >= 2 ^ (i - 1) then
            text = text == "" and S.Text(notice.text) or text .. "\n" .. S.Text(notice.text)
        end
    end
    notices.text = text
    local label = notices.label
    if not label and text ~= "" then
        label = S.CreateFontString(self.view.host, nil, "OVERLAY", "GameFontNormal")
        notices.label = label
        R.StyleNotices(self)
    end
    if label then
        label:SetText(text)
        label:SetShown(text ~= "")
    end
end

-- No notice line (Edit Mode preview, disable).
function R.HideSpecialText(self)
    R.SpecialText(self, false)
end
