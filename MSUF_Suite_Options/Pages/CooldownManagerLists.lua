local _, P = ...
-- Cooldown manager page, lists and per-spell choices: read-only views decoded
-- from the stored strings (cached by string) and every list or spell edit,
-- one MSUF history entry per gesture (Page.Commit). Builds on the page state
-- of CooldownManagerData.lua, which loads first.
local Page = P.CDMPage
local S = P.S
local CDM = P.Suite.CDM
local FAMILY = CDM.FAMILY
local ID = Page.ID
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local EMPTY = {}
local EntryKey = Page.EntryKey

------------------------------------------------------------------ data
-- Read-only decoded views, cached by the stored string.
local cache = {}
function Page.ListsView()
    local text = P.Get(ID, "listsData")
    if cache.listsText ~= text then cache.listsText, cache.lists = text, CDM.Codec.DecodeLists(text) end
    return cache.lists
end
function Page.SpellOverrides()
    local text = P.Get(ID, "spellsData")
    if cache.spellsText ~= text then cache.spellsText, cache.spells = text, CDM.Codec.DecodeSpells(text) end
    return cache.spells
end
function Page.SpellField(key, field)
    local fields = Page.SpellFields(key)
    if fields then return fields[field] end
end
-- Every spell's choices in effect for the current specialization (shared
-- choices with this specialization's on top), as the runtime reads them.
local effectiveData, effectiveSpec, effectiveChoices
function Page.EffectiveSpells()
    local data = Page.SpellOverrides()
    local spec = Page.Spec()
    if not spec then return data.e end
    if effectiveData ~= data or effectiveSpec ~= spec then
        effectiveData, effectiveSpec = data, spec
        effectiveChoices = CDM.EffectiveSpells(data, spec)
    end
    return effectiveChoices
end
function Page.SpellFields(key, currentSpec)
    if not (currentSpec or Page.spellSpecScope) then return Page.SpellOverrides().e[key] end
    return Page.EffectiveSpells()[key]
end
local function SpellEditMap(data, create)
    if not Page.spellSpecScope then return data.e end
    local spec = Page.Spec()
    if not spec then return nil end
    data.s = data.s or {}
    if not data.s[spec] and create then data.s[spec] = {} end
    return data.s[spec]
end
function Page.OwnSpellFields(key)
    local map = SpellEditMap(Page.SpellOverrides())
    return map and map[key]
end
local function ListSlots(lists, spec, slot, create)
    if Page.SlotInfo(slot).custom and P.Get(ID, KEYS[slot].shareContents) then
        if create and not lists.shared then lists.shared = {} end
        return lists.shared
    end
    if create and not lists.specs[spec] then lists.specs[spec] = {} end
    return lists.specs[spec]
end
function Page.HasList(slot)
    local spec = Page.Spec()
    local slots = spec and ListSlots(Page.ListsView(), spec, slot)
    return slots ~= nil and slots[slot] ~= nil
end
-- The bar's list holds spells or items the player added (not Blizzard's).
function Page.HasOwnEntries(slot)
    local spec = Page.Spec()
    local slots = spec and ListSlots(Page.ListsView(), spec, slot)
    local list = slots and slots[slot]
    for i = 1, list and #list or 0 do
        if CDM.EntryKind(list[i]) ~= "b" then return true end
    end
    return false
end
function Page.HiddenCount()
    local spec = Page.Spec()
    local hidden = spec and Page.ListsView().hidden[spec]
    local count = 0
    if hidden then for _ in pairs(hidden) do count = count + 1 end end
    return count
end
-- Bar of an explicitly listed entry for the current specialization.
function Page.WhereIs(key)
    local spec = Page.Spec()
    if not spec then return end
    local lists = Page.ListsView()
    for _, info in ipairs(SLOTS) do
        local slots = ListSlots(lists, spec, info.key)
        local list = slots and slots[info.key]
        for i = 1, list and #list or 0 do if list[i] == key then return info.key end end
    end
end

local function IndexOf(list, key)
    if not list then return nil end
    for i = 1, #list do if list[i] == key then return i end end
end
local function Prune(lists, spec)
    local slots = lists.specs[spec]
    if slots then
        local replace = lists.replace and lists.replace[spec]
        for slot, list in pairs(slots) do
            if #list == 0 and not (replace and replace[slot]) then slots[slot] = nil end
        end
        if next(slots) == nil then lists.specs[spec] = nil end
    end
    local hidden = lists.hidden[spec]
    if hidden and next(hidden) == nil then lists.hidden[spec] = nil end
    local replace = lists.replace and lists.replace[spec]
    if replace and next(replace) == nil then lists.replace[spec] = nil end
end
Page.PruneLists = Prune
-- An explicit order that matches what the bar shows now, followed by listed
-- entries it cannot show right now (unlearned talents keep their place).
local function Materialize(lists, spec, slot)
    local slots = ListSlots(lists, spec, slot, true)
    local old, list = slots[slot], {}
    local shown = Page.Entries(slot) or EMPTY
    for i = 1, #shown do
        local key = EntryKey(shown[i])
        if key and not IndexOf(list, key) then list[#list + 1] = key end
    end
    if old then
        for i = 1, #old do if not IndexOf(list, old[i]) then list[#list + 1] = old[i] end end
    end
    slots[slot] = list
    if slot == "ess" and not old and P.Get(ID, "raidEssentials") ~= false then
        local replace = lists.replace[spec] or {}
        replace.ess = true
        lists.replace[spec] = replace
    end
    return list
end
-- One home per entry: drop it from the other bars and from the removed set.
local function Unclaim(lists, spec, key, keep)
    local slots = lists.specs[spec]
    if slots then
        for slot, list in pairs(slots) do
            if slot ~= keep then
                local at = IndexOf(list, key)
                if at then table.remove(list, at) end
            end
        end
    end
    for slot, list in pairs(lists.shared or EMPTY) do
        if slot ~= keep and P.Get(ID, KEYS[slot].shareContents) then
            local at = IndexOf(list, key)
            if at then table.remove(list, at) end
        end
    end
    local hidden = lists.hidden[spec]
    if hidden then hidden[key] = nil end
end

local COMBAT = "Finish combat before editing the suite"
-- Every list or spell gesture is one MSUF history entry.
function Page.Commit(label, lists, spells)
    if P.Combat() then return false, COMBAT end
    local values, err = {}, nil
    if lists then
        values.listsData, err = CDM.Codec.EncodeLists(lists)
        if not values.listsData then return false, err end
    end
    if spells then
        values.spellsData, err = CDM.Codec.EncodeSpells(spells)
        if not values.spellsData then return false, err end
    end
    local ok, reason
    P.WithHistory(label, "suite:cooldownManager.spells", function()
        if lists and spells then
            ok, reason = P.SetMany(ID, values)
        elseif lists then
            ok, reason = P.Set(ID, "listsData", values.listsData)
        else
            ok, reason = P.Set(ID, "spellsData", values.spellsData)
        end
        return ok
    end)
    if ok == nil then ok, reason = false, COMBAT end
    return ok == true, reason
end

local function Ready()
    if P.Combat() then return nil, COMBAT end
    local spec = Page.Spec()
    if not spec then return nil, "Your specialization is not known yet." end
    if not S.CooldownManagerBarEntries then return nil, "The cooldown manager is not loaded." end
    return spec
end
local function WrongFamily(family, slot)
    if family ~= FAMILY.COOLDOWN and family ~= FAMILY.AURA then return nil end
    if family == Page.Family(slot) then return nil end
    return Page.FamilyError(family)
end
-- One list gesture: decode, edit, prune, one history entry. `edit` returns
-- the history label to commit, true when nothing changes, or false and why.
local function EditLists(edit)
    local spec, err = Ready()
    if not spec then return false, err end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local label, reason = edit(lists, spec)
    if type(label) ~= "string" then return label == true, reason end
    Prune(lists, spec)
    return Page.Commit(label, lists)
end

function Page.AddEntry(slot, key, family)
    return EditLists(function(lists, spec)
        if not CDM.ValidEntryKey(key) then return false, "Invalid spell or item." end
        if KEYS[slot].shareContents and P.Get(ID, KEYS[slot].shareContents) and CDM.EntryKind(key) == "b" then
            return false, "Shared groups use explicit spell, aura or item IDs. Add this spell by name or ID."
        end
        local wrong = WrongFamily(family, slot)
        if wrong then return false, wrong end
        local hidden = lists.hidden[spec]
        local list = Materialize(lists, spec, slot)
        if IndexOf(list, key) and not (hidden and hidden[key]) then return true end
        if not IndexOf(list, key) then
            if #list >= CDM.LIMITS.entries then return false, "This bar is full." end
            list[#list + 1] = key
        end
        Unclaim(lists, spec, key, slot)
        return "Add to cooldown bar"
    end)
end

-- Built-in bars refill from Blizzard's list, so a Blizzard entry removed there
-- is hidden for this specialization. Elsewhere it only leaves the list (a
-- Blizzard entry then returns to its own bar).
function Page.RemoveEntry(slot, key)
    return EditLists(function(lists, spec)
        local slots = ListSlots(lists, spec, slot)
        local list = slots and slots[slot]
        local at = IndexOf(list, key)
        if at then table.remove(list, at) end
        -- Blizzard entries and preset spells come back unless hidden for this spec.
        local info = Page.SlotInfo(slot)
        if not info.custom and (CDM.EntryKind(key) == "b" or info.preset) then
            local hidden = lists.hidden[spec] or {}
            local count = 0
            for _ in pairs(hidden) do count = count + 1 end
            if count >= CDM.LIMITS.hidden then return false, "Too many removed spells." end
            hidden[key] = true
            lists.hidden[spec] = hidden
        elseif not at then
            return false, "It is not on this bar."
        end
        return "Remove from cooldown bar"
    end)
end

-- Moves (or reorders) an entry so it sits before `beforeKey` on `slot`, or last.
function Page.MoveEntry(key, slot, beforeKey, family)
    return EditLists(function(lists, spec)
        if not CDM.ValidEntryKey(key) then return false, "Invalid spell or item." end
        if KEYS[slot].shareContents and P.Get(ID, KEYS[slot].shareContents) and CDM.EntryKind(key) == "b" then
            return false, "Shared groups use explicit spell, aura or item IDs. Add this spell by name or ID."
        end
        local wrong = WrongFamily(family, slot)
        if wrong then return false, wrong end
        if beforeKey == key then return true end
        local list = Materialize(lists, spec, slot)
        local at = IndexOf(list, key)
        if at then
            table.remove(list, at)
        elseif #list >= CDM.LIMITS.entries then
            return false, "This bar is full."
        end
        local index = beforeKey and beforeKey ~= key and IndexOf(list, beforeKey) or (#list + 1)
        local hidden = lists.hidden[spec]
        if at and index == at and not (hidden and hidden[key]) then return true end
        table.insert(list, index, key)
        Unclaim(lists, spec, key, slot)
        return at and "Reorder cooldown bar" or "Move to another bar"
    end)
end

-- What dropping a bar's own list does: the Suite profile restores its spec
-- defaults; with it off, built-ins follow the active Blizzard layout.
function Page.ClearLabel(slot)
    local info = Page.SlotInfo(slot)
    if info.custom then return "Remove all spells" end
    if P.Get(ID, "raidEssentials") ~= false then
        if slot == "ess" then return "Restore raid essentials" end
        if slot == "uti" or slot == "buf" or slot == "bar" then return "Restore spec defaults" end
    end
    return info.preset == "defensives" and "Restore default spells" or "Reset to Blizzard's list"
end
function Page.ClearList(slot)
    return EditLists(function(lists, spec)
        local slots = ListSlots(lists, spec, slot)
        local replace = lists.replace and lists.replace[spec]
        if not (slots and slots[slot]) and not (replace and replace[slot]) then return true end
        if slots then slots[slot] = nil end
        if replace then replace[slot] = nil end
        return Page.ClearLabel(slot)
    end)
end

-- Transfer the active Blizzard CDM order and category assignments for the
-- current specialization. Other specs and Suite custom/defensive bars stay as
-- they are. A complete selection is marked so new Blizzard entries do not
-- silently append after import; the user can restore a Suite spec default later.
function Page.ImportBlizzard()
    local spec, err = Ready()
    if not spec then return false, err end
    local snapshot = S.CooldownManagerBlizzardSnapshot
    if type(snapshot) ~= "function" then return false, "Blizzard's cooldown list is not ready yet." end
    local bars, reason = snapshot()
    if not bars then return false, reason end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local slots = lists.specs[spec] or {}
    local reserved = {}
    local imported = {}
    for slot, list in pairs(slots) do
        if slot == "def" or (type(slot) == "string" and slot:match("^c[1-6]$")) then
            for i = 1, #list do reserved[list[i]] = true end
        end
    end
    local replace = lists.replace[spec] or {}
    for _, slot in ipairs({ "ess", "uti", "buf", "bar", "ext" }) do
        local source = bars[slot] or EMPTY
        local list = {}
        for i = 1, #source do
            local key = source[i]
            if not reserved[key] then
                list[#list + 1] = key
                imported[key] = true
            end
        end
        if #list > CDM.LIMITS.entries then return false, "Blizzard's list has too many entries for one bar." end
        slots[slot], replace[slot] = list, true
    end
    lists.specs[spec], lists.replace[spec] = slots, replace
    -- Blizzard's active layout is authoritative for copied entries. Keep
    -- removals of Suite-only entries and custom/defensive bar entries.
    local hidden = lists.hidden[spec]
    if hidden then
        for key in pairs(imported) do hidden[key] = nil end
    end
    Prune(lists, spec)
    return Page.Commit("Import Blizzard cooldown layout", lists)
end
function Page.RestoreHidden()
    return EditLists(function(lists, spec)
        if not lists.hidden[spec] then return true end
        lists.hidden[spec] = nil
        return "Show removed spells"
    end)
end
-- Puts key on bar `slot` of specialization `spec`, its one home there. A
-- full bar takes nothing, and the entry stays on its old bar. True when added.
local function CopyEntry(lists, spec, slot, key)
    local slots = lists.specs[spec] or {}
    lists.specs[spec] = slots
    local list = slots[slot] or {}
    slots[slot] = list
    local present = IndexOf(list, key)
    if not present and #list >= CDM.LIMITS.entries then return false end
    Unclaim(lists, spec, key, slot)
    if present then return false end
    list[#list + 1] = key
    return true
end
-- Custom entries only: Blizzard entries follow each specialization's own list.
function Page.CopyToSpecs(slot, key)
    local spec, err = Ready()
    if not spec then return false, err end
    if CDM.EntryKind(key) == "b" then return false, "Blizzard entries follow each specialization's own list." end
    -- A shared group's one list already applies to every specialization;
    -- its per-specialization lists are unused and other bars keep theirs.
    if KEYS[slot].shareContents and P.Get(ID, KEYS[slot].shareContents) then return true, 0 end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local changed = 0
    for _, other in ipairs(Page.ClassSpecs({})) do
        if other ~= spec then
            if CopyEntry(lists, other, slot, key) then changed = changed + 1 end
            Prune(lists, other)
        end
    end
    if changed == 0 then return true, 0 end
    local ok, reason = Page.Commit("Copy to all specializations", lists)
    return ok, ok and changed or reason
end
-- Every spell and item the player added to the bar goes to the same bar in
-- the other specializations, in its order, as one history entry. Returns
-- true plus the number of entries added and of specializations changed.
function Page.CopyListToSpecs(slot)
    local spec, err = Ready()
    if not spec then return false, err end
    if KEYS[slot].shareContents and P.Get(ID, KEYS[slot].shareContents) then return true, 0, 0 end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local own, keys = lists.specs[spec] and lists.specs[spec][slot], {}
    for i = 1, own and #own or 0 do
        if CDM.EntryKind(own[i]) ~= "b" then keys[#keys + 1] = own[i] end
    end
    if #keys == 0 then return false, "This bar has no spells or items you added." end
    local added, specs = 0, 0
    for _, other in ipairs(Page.ClassSpecs({})) do
        if other ~= spec then
            local before = added
            for i = 1, #keys do
                if CopyEntry(lists, other, slot, keys[i]) then added = added + 1 end
            end
            if added > before then specs = specs + 1 end
            Prune(lists, other)
        end
    end
    if added == 0 then return true, 0, 0 end
    local ok, reason = Page.Commit("Copy bar to all specializations", lists)
    if not ok then return false, reason end
    return true, added, specs
end

function Page.SetSpellField(key, field, value)
    if P.Combat() then return false, COMBAT end
    local valid = CDM.SPELL_FIELDS[field]
    if not CDM.ValidEntryKey(key) or not valid or (value ~= nil and not valid(value)) then return false, "Invalid value." end
    local spells = CDM.Codec.DecodeSpells(P.Get(ID, "spellsData"))
    local map = SpellEditMap(spells, value ~= nil)
    if not map then return value == nil, "Your specialization is not known yet." end
    local fields = map[key]
    if value == nil then
        if not fields or fields[field] == nil then return true end
        fields[field] = nil
        if next(fields) == nil then map[key] = nil end
    else
        if fields and fields[field] == value then return true end
        if not fields then
            local count = 0
            for _ in pairs(map) do count = count + 1 end
            if count >= CDM.LIMITS.spells then return false, "Too many spell choices." end
            fields = {}
            map[key] = fields
        end
        fields[field] = value
    end
    return Page.Commit("Spell option", nil, spells)
end
function Page.ResetSpell(key)
    if P.Combat() then return false, COMBAT end
    local spells = CDM.Codec.DecodeSpells(P.Get(ID, "spellsData"))
    local map = SpellEditMap(spells)
    if not map or not map[key] then return true end
    map[key] = nil
    return Page.Commit("Reset spell options", nil, spells)
end
-- A popover row that edits two fields resets both in one history entry.
function Page.ClearSpellFields(key, names)
    if P.Combat() then return false, COMBAT end
    local spells = CDM.Codec.DecodeSpells(P.Get(ID, "spellsData"))
    local map = SpellEditMap(spells)
    local fields = map and map[key]
    if not fields then return true end
    local changed = false
    for i = 1, #names do
        if fields[names[i]] ~= nil then fields[names[i]], changed = nil, true end
    end
    if not changed then return true end
    if next(fields) == nil then map[key] = nil end
    return Page.Commit("Spell option", nil, spells)
end
