local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local IN_COMBAT = { inCombat = true }
-- Forever's spellbook filters low ranks with IsSpellBookItemLowRank
-- (Blizzard_PlayerSpells/SpellBook/Blizzard_SpellBookFrame.lua). Placement
-- uses the same spell cursor and action slots as Blizzard_ActionBar.
local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local SPELL_ITEM = Enum.SpellBookItemType.Spell
-- Spell IDs are 32-bit; a longer run of digits in the exception list is no ID.
local MAX_SPELL_ID = 2147483647
local ALL_BARS

local function SpellSlot(spell)
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spell, true, false)
    if S.Finite(slot) and S.Public(bank) and bank == PLAYER_BANK then return slot, bank end
end

-- true: a lower rank; false: the highest known rank; nil: not readable.
local function LowRank(spell)
    if not C_SpellBook.IsSpellBookItemLowRank then return nil end
    local slot, bank = SpellSlot(spell)
    if not slot then return nil end
    local low = C_SpellBook.IsSpellBookItemLowRank(slot, bank)
    if S.Public(low) and type(low) == "boolean" then return low end
end

local function Highest(spell)
    return LowRank(spell) == false
end

local function ActionSpell(slot)
    local kind, spell = GetActionInfo(slot)
    if S.Public(kind) and kind == "spell" and S.Finite(spell) then return spell end
end

-- Exceptions name exact ranks by positive whole spell ID. The setter accepts
-- only digits, spaces and commas (Suite.lua ValidText); zero and oversized
-- numbers are ignored here.
local function ParseExceptions(text)
    local ids = {}
    if type(text) ~= "string" then return ids end
    for digits in text:gmatch("%d+") do
        local id = #digits <= 10 and tonumber(digits)
        if id and id > 0 and id <= MAX_SPELL_ID then ids[id] = true end
    end
    return ids
end

-- A listed rank stays where it is placed and is never placed for the player.
local function Excepted(self, old, spell)
    return self.except[old] == true or self.except[spell] == true
end

-- Without replaceLowerRanks only a slot seen at the then-highest rank changes.
local function Allowed(self, slot, old)
    return self.config.replaceLowerRanks == true or self.eligible[slot] == old
end

-- Remember which placed spells were the highest known BEFORE learning.
-- A deliberately lower rank is never eligible with the default setting.
local function Observe(self, slot)
    local spell = ActionSpell(slot)
    if self.observed[slot] == spell then return end
    self.observed[slot] = spell
    self.eligible[slot] = spell and Highest(spell) and spell or nil
end

local function ObservePlaced(self, spell)
    if self.discovered[spell] then return end
    self.discovered[spell] = true
    local actions = C_ActionBar.FindSpellActionButtons(spell, ALL_BARS)
    if S.Public(actions) and type(actions) == "table" then
        for _, action in ipairs(actions) do
            if S.Finite(action) and action > 0 then Observe(self, action) end
        end
    end
end

-- The explicit action names the single highest learned rank of each spell
-- name from the book itself. Two highest spells sharing a name are
-- ambiguous and never chosen.
local function NoteHighest(best, spell, bookSlot)
    if not C_SpellBook.IsSpellBookItemLowRank then return end
    local low = C_SpellBook.IsSpellBookItemLowRank(bookSlot, PLAYER_BANK)
    local name = S.Public(low) and low == false and S.PublicText(C_Spell.GetSpellName(spell))
    if not name then return end
    local known = best[name]
    if known == nil then
        best[name] = spell
    elseif known ~= spell then
        best[name] = false
    end
end

-- Native All includes keyboard/mouse and Forever's separate gamepad storage.
-- Enumerate placed spells once on enable, a full action-bar reset or the
-- explicit update action (best collects highest ranks). Ordinary slot
-- changes update one entry; learning only walks the occupied cache.
local function ObserveAll(self, best)
    wipe(self.discovered)
    for slot in pairs(self.observed) do Observe(self, slot) end
    local count = C_SpellBook.GetNumSpellBookSkillLines()
    if not S.Finite(count) then return end
    for line = 1, count do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if S.Public(info) and type(info) == "table" and S.Finite(info.itemIndexOffset) and S.Finite(info.numSpellBookItems) then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local kind, spell = C_SpellBook.GetSpellBookItemType(slot, PLAYER_BANK)
                if S.Public(kind) and kind == SPELL_ITEM and S.Finite(spell) then
                    ObservePlaced(self, spell)
                    if best then NoteHighest(best, spell, slot) end
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
    -- Recheck exceptions and identity immediately before pickup; a pending
    -- request never overwrites an action the player changed while combat or
    -- the cursor blocked it, nor a rank listed after it was queued.
    if Excepted(self, old, spell) or Blocked() or ActionSpell(slot) ~= old then return false end
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
        if old and old ~= spell and Allowed(self, slot, old)
            and S.PublicText(C_Spell.GetSpellName(old)) == name
            and LowRank(old) == true and ReplaceSlot(self, slot, old, spell) then count = count + 1 end
    end
    if count > 0 and self.config.report then
        local message = S.Text("Updated %d action slots to the new rank of %s."):format(count, name)
        NS.Print(message)
    end
    return count
end

------------------------------------------------------------------ explicit update
-- The explicit action is a deliberate request, so it always reports. It
-- follows replaceLowerRanks like the automatic path and names what it kept.
local function ReportPlan(count, kept)
    if count > 0 then
        NS.Print(S.Text("Updated %d action slots to your highest learned spell ranks."):format(count))
    else
        NS.Print(S.Text("No action slots were updated."))
    end
    if kept > 0 then
        NS.Print(S.Text('%d lower ranks you may have placed on purpose stayed. Turn on "Also replace deliberately lower ranks" to update them too.')
            :format(kept))
    end
end

-- The snapshot the explicit action takes when it is chosen: [action slot] =
-- placed lower rank, and [lower rank] = highest learned rank of its name.
local function BuildPlan(self)
    local best, plan, ranks, kept = {}, {}, {}, 0
    ObserveAll(self, best)
    for slot in pairs(self.observed) do
        local old = ActionSpell(slot)
        local name = old and S.PublicText(C_Spell.GetSpellName(old))
        local spell = name and best[name]
        if spell and spell ~= old and not Excepted(self, old, spell) and LowRank(old) == true then
            if Allowed(self, slot, old) then
                plan[slot], ranks[old] = old, spell
            else
                kept = kept + 1
            end
        end
    end
    return plan, ranks, kept
end

-- A slot is placed only while it still holds its snapshotted rank, its
-- target is still the highest and the current settings allow it. Work that
-- combat or a busy cursor interrupts stays for the next flush.
local function RunPlan(self)
    local plan, ranks, highest = self.plan, self.ranks, {}
    for slot, old in pairs(plan) do
        if Blocked() then return false end
        local spell = ranks[old]
        if highest[spell] == nil then highest[spell] = Highest(spell) end
        if highest[spell] and Allowed(self, slot, old) and ReplaceSlot(self, slot, old, spell) then
            self.planCount = self.planCount + 1
        end
        plan[slot] = nil
    end
    self.plan, self.ranks = nil, nil
    ReportPlan(self.planCount, self.planKept)
    return true
end

-- A snapshot's slot identities are void once the game replaces the bars.
local function CancelPlan(self)
    if not self.plan then return end
    self.plan, self.ranks = nil, nil
    NS.Print(S.Text("Your action bars changed before spell ranks could update. Choose Update placed spell ranks now again."))
end

Flush = function(self)
    if not self.active then return end
    if Blocked() then
        Wait(self, self.rescan or self.plan ~= nil or next(self.pending) ~= nil)
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
    if self.plan and not RunPlan(self) then Wait(self, true) end
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
        CancelPlan(self)
        for cached in pairs(self.observed) do Observe(self, cached) end
        self.rescan = true
        self.job:Request()
    elseif slot >= 1 and slot == math.floor(slot) then
        -- The player's own edit of a snapshotted slot wins over the request.
        if self.plan then self.plan[slot] = nil end
        Observe(self, slot)
    end
end

-- Public: the "Update placed spell ranks now" action of the options page.
-- Snapshots the placed lower ranks whose highest rank is already learned
-- and updates them now, or once combat has ended and the cursor is empty.
-- Exceptions and replaceLowerRanks apply as for automatic updates; macros
-- are never touched. Returns false while the helper is not running.
function M:UpdatePlacedRanks()
    if not self.active or not self.job then return false end
    self.plan, self.ranks, self.planKept = BuildPlan(self)
    self.planCount = 0
    if Blocked() then NS.Print(S.Text("Spell ranks will update once combat ends and your cursor is empty.")) end
    self.job:Request()
    return true
end

function M:Enable()
    if not Enum.ActionBarSet then return end
    ALL_BARS = Enum.ActionBarSet.All
    self.placing, self.rescan = false, false
    self.pending, self.observed, self.eligible, self.discovered = {}, {}, {}, {}
    self.except = ParseExceptions(self.config.exceptSpellIDs)
    self.job = self.context:Coalesce(0, Flush)
    ObserveAll(self)
    self.context:Event("LEARNED_SPELL_IN_SKILL_LINE", Learned, IN_COMBAT)
    self.context:Event("ACTIONBAR_SLOT_CHANGED", ActionChanged, IN_COMBAT)
end

-- Settings edits re-read the exception list; pending work checks it again.
function M:Refresh()
    self.except = ParseExceptions(self.config.exceptSpellIDs)
end

function M:Disable()
    self.placing = false
    Wait(self, false)
    self.context:RemoveEvent("LEARNED_SPELL_IN_SKILL_LINE")
    self.context:RemoveEvent("ACTIONBAR_SLOT_CHANGED")
    self.pending, self.observed, self.eligible, self.discovered = nil, nil, nil, nil
    self.plan, self.ranks, self.except = nil, nil, nil
end

S.Install("autoUprank", M)
