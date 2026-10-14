local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local IN_COMBAT = { inCombat = true }
-- Forever's spellbook filters low ranks with IsSpellBookItemLowRank
-- (Blizzard_PlayerSpells/SpellBook/Blizzard_SpellBookFrame.lua). Placement
-- uses the same spell cursor and action slots as Blizzard_ActionBar.
local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local SPELL_ITEM = Enum.SpellBookItemType.Spell
local ALL_BARS

local function SpellSlot(spell)
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spell, true, false)
    if S.Finite(slot) and S.Public(bank) and bank == PLAYER_BANK then return slot, bank end
end

local function Highest(spell)
    if not C_SpellBook.IsSpellBookItemLowRank then return false end
    local slot, bank = SpellSlot(spell)
    if not slot then return false end
    local low = C_SpellBook.IsSpellBookItemLowRank(slot, bank)
    return S.Public(low) and low == false
end

local function ActionSpell(slot)
    local kind, spell = GetActionInfo(slot)
    if S.Public(kind) and kind == "spell" and S.Finite(spell) then return spell end
end

-- Remember which placed spells were the highest known BEFORE learning.
-- A deliberately lower rank is never eligible with the default setting.
local function Observe(self, slot)
    local spell = ActionSpell(slot)
    if self.observed[slot] == spell then return end
    self.observed[slot] = spell
    self.eligible[slot] = spell and Highest(spell) and spell or nil
end

-- Native All includes keyboard/mouse and Forever's separate gamepad storage.
-- Enumerate placed spells once on enable or a full action-bar reset. Ordinary
-- slot changes update one entry; learning only walks the occupied cache.
local function ObserveAll(self)
    wipe(self.discovered)
    for slot in pairs(self.observed) do Observe(self, slot) end
    local count = C_SpellBook.GetNumSpellBookSkillLines()
    if not S.Finite(count) then return end
    for line = 1, count do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if S.Public(info) and type(info) == "table" and S.Finite(info.itemIndexOffset) and S.Finite(info.numSpellBookItems) then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local kind, spell = C_SpellBook.GetSpellBookItemType(slot, PLAYER_BANK)
                if S.Public(kind) and kind == SPELL_ITEM and S.Finite(spell) and not self.discovered[spell] then
                    self.discovered[spell] = true
                    local actions = C_ActionBar.FindSpellActionButtons(spell, ALL_BARS)
                    if S.Public(actions) and type(actions) == "table" then
                        for _, action in ipairs(actions) do
                            if S.Finite(action) and action > 0 then Observe(self, action) end
                        end
                    end
                end
            end
        end
    end
end

local function Blocked()
    if NS.InCombat() then return true end
    local cursor = GetCursorInfo()
    return not S.Public(cursor) or cursor ~= nil
end

local Flush
local function Resume(self)
    if not self.placing then self.job:Request() end
end

local function Wait(self, pending)
    if pending then
        self.context:Event("PLAYER_REGEN_ENABLED", Resume)
        self.context:Event("CURSOR_CHANGED", Resume, IN_COMBAT)
    else
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
        self.context:RemoveEvent("CURSOR_CHANGED")
    end
end

local function PlaceRank(slot, old, spell)
    C_Spell.PickupSpell(spell)
    local cursor, _, _, held = GetCursorInfo()
    if S.Public(cursor) and cursor == "spell" and S.Finite(held) and held == spell then
        if ActionSpell(slot) == old then PlaceAction(slot) end
    end
end

local function ClearOwnedCursor(slot, old, spell)
    local cursor, _, _, held = GetCursorInfo()
    if S.Public(cursor) and cursor == "spell" and S.Finite(held)
        and (held == spell or (held == old and ActionSpell(slot) == spell)) then ClearCursor() end
end

local function ReplaceSlot(self, slot, old, spell)
    -- Recheck identity immediately before pickup; a pending request never
    -- overwrites an action the player changed while combat/cursor blocked it.
    if Blocked() or ActionSpell(slot) ~= old then return false end
    self.placing = true
    NS.Dispatch(PlaceRank, slot, old, spell)
    NS.Dispatch(ClearOwnedCursor, slot, old, spell)
    self.placing = false
    if ActionSpell(slot) ~= spell then return false end
    self.observed[slot], self.eligible[slot] = spell, spell
    return true
end

local function Upgrade(self, spell)
    if not Highest(spell) then return 0 end
    local name = S.PublicText(C_Spell.GetSpellName(spell))
    if not name then return 0 end
    local count = 0
    for slot in pairs(self.observed) do
        local old = ActionSpell(slot)
        if old and old ~= spell and (self.config.replaceLowerRanks or self.eligible[slot] == old)
            and S.PublicText(C_Spell.GetSpellName(old)) == name then
            local bookSlot, bank = SpellSlot(old)
            local low = bookSlot and C_SpellBook.IsSpellBookItemLowRank(bookSlot, bank)
            if S.Public(low) and low == true and ReplaceSlot(self, slot, old, spell) then count = count + 1 end
        end
    end
    if count > 0 and self.config.report then
        local message = S.Text("Updated %d action slots to the new rank of %s."):format(count, name)
        NS.Print(message)
    end
    return count
end

Flush = function(self)
    if not self.active then return end
    if Blocked() then
        Wait(self, self.rescan or next(self.pending) ~= nil)
        return
    end
    Wait(self, false)
    if self.rescan then
        self.rescan = false
        ObserveAll(self)
    end
    for spell in pairs(self.pending) do
        Upgrade(self, spell)
        self.pending[spell] = nil
    end
end

local function Learned(self, _, spell, _, guildPerk)
    if not self.active or not S.Finite(spell) or spell <= 0 or spell ~= math.floor(spell)
        or not S.Public(guildPerk) or guildPerk == true then return end
    self.pending[spell] = true
    self.job:Request()
end

local function ActionChanged(self, _, slot)
    if self.placing or not S.Finite(slot) then return end
    if slot == 0 then
        for cached in pairs(self.observed) do Observe(self, cached) end
        self.rescan = true
        self.job:Request()
    elseif slot >= 1 and slot == math.floor(slot) then
        Observe(self, slot)
    end
end

function M:Enable()
    if not Enum.ActionBarSet then return end
    ALL_BARS = Enum.ActionBarSet.All
    self.placing, self.rescan = false, false
    self.pending, self.observed, self.eligible, self.discovered = {}, {}, {}, {}
    self.job = self.context:Coalesce(0, Flush)
    ObserveAll(self)
    self.context:Event("LEARNED_SPELL_IN_SKILL_LINE", Learned, IN_COMBAT)
    self.context:Event("ACTIONBAR_SLOT_CHANGED", ActionChanged, IN_COMBAT)
end

function M:Refresh() end

function M:Disable()
    self.placing = false
    Wait(self, false)
    self.context:RemoveEvent("LEARNED_SPELL_IN_SKILL_LINE")
    self.context:RemoveEvent("ACTIONBAR_SLOT_CHANGED")
    self.pending, self.observed, self.eligible, self.discovered = nil, nil, nil, nil
end

S.Install("autoUprank", M)
