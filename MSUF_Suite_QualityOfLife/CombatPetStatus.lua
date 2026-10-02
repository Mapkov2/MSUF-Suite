local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local ID = "combatPetStatus"
-- Classes with a summoned pet, by the spellbook spell that summons it (Call
-- Pet 1, Summon Imp). The class alone is not enough: Marksmanship hunters
-- learn Call Pet only through a talent, and a warlock who knows Grimoire of
-- Sacrifice plays without a demon on purpose.
local PET_SUMMONS = { HUNTER = 883, WARLOCK = 688 }
local PETLESS = { WARLOCK = 108503 }

local function Known(spellID)
    local known = C_SpellBook.IsSpellKnown(spellID)
    return S.Public(known) and known == true
end

local function ExpectsPet(class)
    local summon = PET_SUMMONS[class]
    if not summon or not Known(summon) then return false end
    local petless = PETLESS[class]
    return not (petless and Known(petless))
end

local CARD = { width = 200, height = 34, fill = { .08, .07, .08, .91 }, stripe = 3 }

local function Create(self)
    if self.host then return end
    local host, bg, stripe = S.QoLCard(CARD)
    local label = S.CreateFontString(host, nil, "OVERLAY")
    label:SetPoint("CENTER")
    S.SetFont(label, nil, 14, "OUTLINE")
    host:Hide()
    self.host, self.bg, self.stripe, self.label = host, bg, stripe, label
end

local function Place(self)
    local c = self.config
    S.PaintQoLCard(ID, c, self.bg)
    S.PlaceHost(self.host, c)
end

local function Update(self, event)
    if not self.active or not self.host then return end
    if S.editMode then
        self.label:SetText(S.Text("Pet missing"))
        self.label:SetTextColor(1, .8, .43)
        self.stripe:SetColorTexture(1, .68, .3)
        self.host:Show()
        return
    end
    if self.config.combatOnly and not NS.InCombat(event) then
        self.host:Hide()
        return
    end
    local exists = UnitExists("pet")
    if not S.Public(exists) then self.host:Hide() return end
    if exists == true then
        local dead = UnitIsDeadOrGhost("pet")
        if not S.Public(dead) or dead ~= true or not self.config.showDead then
            self.host:Hide()
            return
        end
        self.label:SetText(S.Text("Pet dead"))
        self.label:SetTextColor(1, .48, .42)
        self.stripe:SetColorTexture(1, .32, .28)
    else
        if not self.config.showMissing or not self.petClass and not self.config.anyClass then
            self.host:Hide()
            return
        end
        self.label:SetText(S.Text("Pet missing"))
        self.label:SetTextColor(1, .8, .43)
        self.stripe:SetColorTexture(1, .68, .3)
    end
    self.host:Show()
end

local function OnEvent(self, event)
    Update(self, event)
end

-- Talent and specialization changes reach the spellbook.
local function OnSpellsChanged(self, event)
    self.petClass = ExpectsPet(self.classFile)
    Update(self, event)
end

local function SyncEvents(self)
    local c, context = self.config, self.context
    if c.showMissing or c.showDead then
        context:Event("UNIT_PET", OnEvent, true, "player")
    else
        context:RemoveEvent("UNIT_PET")
    end
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS" }) do
        if c.showDead then context:Event(event, OnEvent, true, "pet")
        else context:RemoveEvent(event) end
    end
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        if c.combatOnly then context:Event(event, OnEvent, true)
        else context:RemoveEvent(event) end
    end
    if c.showMissing and PET_SUMMONS[self.classFile] then
        context:Event("SPELLS_CHANGED", OnSpellsChanged, true)
    else
        context:RemoveEvent("SPELLS_CHANGED")
    end
end

function M:Enable()
    self.classFile = S.PublicText(UnitClassBase("player"))
    self.petClass = ExpectsPet(self.classFile)
    Create(self)
    Place(self)
    self.context:Event("PLAYER_ENTERING_WORLD", OnEvent, true)
    SyncEvents(self)
    Update(self)
    self:RegisterMovers()
end

function M:Refresh()
    S.SetFont(self.label, nil, 14, "OUTLINE")
    Place(self)
    SyncEvents(self)
    Update(self)
end

function M:Disable()
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "warning", {
        label = "Pet status", order = 646,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "scale" },
        sizeKeys = { "scale" },
    })
end

S.Install(ID, M)
