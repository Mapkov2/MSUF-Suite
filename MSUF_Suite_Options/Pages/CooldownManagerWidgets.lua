local _, P = ...
-- Cooldown manager page, shared part: bar selection, list, bar and per-spell
-- edits (one history entry per gesture; gestures that drop data offer an
-- Undo line) and the pooled editors used by the page: spell tiles, spell
-- picker, per-spell popover and sound picker.
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local CDM = Suite and Suite.CDM
local ID, PAGE = "cooldownManager", "suite_cooldownManager"
if not (CDM and P.catalog and P.catalog[ID]) then return end

local RULES, SLOTS, KEYS = P.catalog[ID].rules, CDM.SLOTS, CDM.KEYS
local REF_KEYS = { KEYS.ess, KEYS.buf, KEYS.bar }
local EMPTY = {}
local QUESTION = 134400
local RUNTIME = "MSUF_Suite_CooldownManager"
local TILE, GAP = 36, 6
-- Icon crop of every spell texture the page draws.
local CROP_MIN, CROP_MAX = 0.08, 0.92
local floor, max, min, format = math.floor, math.max, math.min, string.format

local Page = P.CDMPage or {}
P.CDMPage = Page
Page.ID, Page.PAGE, Page.CROP_MIN, Page.CROP_MAX = ID, PAGE, CROP_MIN, CROP_MAX
Page.popups = Page.popups or {}
if not CDM.SLOT_INDEX[Page.selected or ""] then Page.selected = "ess" end

------------------------------------------------------------------ basics
-- The suite's own check when the runtime modules are loaded; the same test
-- otherwise.
local function Public(value)
    local public = S.Public
    if public then return public(value) end
    local check = _G.issecretvalue
    return not (type(check) == "function" and check(value))
end
Page.Public = Public
-- Runtime records are plain by contract. A protected field is treated as
-- missing instead of being tested; textures go straight to the texture sink.
local function Plain(value) if Public(value) then return value end end
local function EntryKey(entry)
    local key = type(entry) == "table" and entry.key
    if Public(key) and CDM.ValidEntryKey(key) then return key end
end
local function SetIcon(region, texture)
    if Public(texture) and not texture then texture = QUESTION end
    region:SetTexture(texture)
end
Page.SetIcon = SetIcon

local function Color(name, r, g, b)
    local color = T.colors and T.colors[name]
    if type(color) == "table" and type(color[1]) == "number" then return color[1], color[2], color[3] end
    return r, g, b
end
-- Theme colors with the page's fallbacks.
local function Accent() return Color("accent", 0.30, 0.74, 1.00) end
local function TextColor() return Color("text", 0.92, 0.94, 0.98) end
local function MutedColor() return Color("muted", 0.6, 0.65, 0.72) end
Page.Color, Page.Accent, Page.TextColor, Page.MutedColor = Color, Accent, TextColor, MutedColor

-- Spell and item names never go through the locale table: they are data, and
-- a protected value must not become a table key.
local function SetRaw(fontString, text)
    local raw = fontString._msuf2RawSetText or fontString.SetText
    raw(fontString, text or "")
end
Page.SetRaw = SetRaw

function Page.SlotInfo(slot) return SLOTS[CDM.SLOT_INDEX[slot] or 1] end
function Page.Kind(slot)
    local info = Page.SlotInfo(slot)
    if info.custom then return P.Get(ID, KEYS[info.key].kind) end
    return info.kind
end
function Page.Family(slot) return Page.Kind(slot) == 1 and 1 or 2 end
function Page.IsOn(slot) return P.Get(ID, KEYS[slot].on) == true end
-- Bars the strip and the bar list keep in view: every bar that is on or
-- selected, the built-in bars, and custom bars that were set up (named).
function Page.Listed(slot)
    if slot == Page.selected or Page.IsOn(slot) or not Page.SlotInfo(slot).custom then return true end
    return P.Get(ID, KEYS[slot].name) ~= ""
end
-- The bar a bar is attached to (nil: placed freely or on a unit frame).
local function AnchorBar(slot)
    local anchor = P.Get(ID, KEYS[slot].anchor)
    local target = type(anchor) == "number" and anchor >= 2 and SLOTS[anchor - 1] or nil
    return target and target.key or nil
end
-- The saved attachments lead from `from` to `slot`: attaching `slot` to
-- `from` would close a loop, and the runtime places every bar of a loop
-- freely.
function Page.Follows(from, slot)
    local cursor = from
    for _ = 1, #SLOTS do
        if cursor == slot then return true end
        cursor = AnchorBar(cursor)
        if not cursor then return false end
    end
    return false
end
function Page.InLoop(slot)
    local first = AnchorBar(slot)
    return first ~= nil and Page.Follows(first, slot)
end
-- The runtime's attach chain, read from the saved settings: the first shown
-- bar up the chain, or nil plus the switched-off bar whose place this one
-- takes (a bar that is off hands its attachment on to its own target).
function Page.Chain(slot)
    local cursor, standIn = slot, nil
    for _ = 1, #SLOTS do
        local anchor = P.Get(ID, KEYS[cursor].anchor)
        local target = type(anchor) == "number" and anchor >= 2 and SLOTS[anchor - 1] or nil
        if not target or target.key == slot then return nil, standIn end
        if Page.IsOn(target.key) then return target.key end
        standIn, cursor = target.key, target.key
    end
    return nil, standIn
end
-- Every bar can be dragged (attached bars shift from their anchor) except
-- the Essential bar while it rides Blizzard's bar for MSUF and a bar that
-- takes the place of a switched-off bar.
function Page.Movable(slot)
    local movable = S.CooldownManagerMovable
    return not movable or movable(slot) ~= false
end
-- Why a bar cannot be dragged; already translated.
function Page.AttachedText(slot)
    local _, standIn = Page.Chain(slot)
    if standIn then
        return format(Tr("This bar takes the place of %s, which is off. Move that bar, or attach this one elsewhere."),
            Page.BarName(standIn))
    end
    return Tr("This bar sits on Blizzard's Essential bar, which your MSUF frames follow. Move it in Blizzard's Edit Mode.")
end
-- The module runs (live bars exist, the simulation can play).
function Page.Running()
    local state = S.states and S.states[ID]
    return type(state) == "table" and state.active == true
end
-- Edit Mode opens on the selected bar, or on the first bar it can move.
function Page.MoveTarget()
    local selected = Page.selected
    if Page.IsOn(selected) and Page.Movable(selected) then return selected end
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if Page.IsOn(slot) and Page.Movable(slot) then return slot end
    end
end
function Page.BarName(slot)
    local info = Page.SlotInfo(slot)
    if info.custom then
        local name = P.Get(ID, KEYS[info.key].name)
        if type(name) == "string" and name ~= "" then return name end
    end
    return Tr(info.title)
end
-- One name per bar type everywhere on the page: the bar type list, "+ Add
-- bar", summaries and notes. Type 3 draws timer bars ("Buff bars" stays the
-- name of the built-in bar that shows them).
local KIND_NAMES = { "Cooldown bar", "Buff icon bar", "Timer bar" }
Page.KIND_NAMES = KIND_NAMES
function Page.KindName(kind) return Tr(KIND_NAMES[kind] or KIND_NAMES[1]) end
function Page.Key(suffix) return KEYS[Page.selected][suffix] end
-- Why an entry cannot go to a bar of the other family (untranslated).
function Page.FamilyError(family)
    return family == 1 and "That bar shows buffs." or "That bar shows cooldowns."
end

-- A template suffix applies to a bar when that bar's kind declares it.
-- Custom timer bars also keep the icon rules the runtime reads for them
-- (spacing, cap, icon crop and border, text switches and sizes); the
-- built-in Buff bars row has none of these and uses fixed values.
local KIND3_EXTRA = {}
for _, suffix in ipairs({ "spacing", "maxIcons", "zoom", "border", "borderColor", "borderClass", "cdText", "cdSize",
    "stackText", "stackSize", "stackPos", "textTop" }) do
    if KEYS.c1[suffix] then KIND3_EXTRA[suffix] = true end
end
Page.KIND3_EXTRA = KIND3_EXTRA
-- Custom buff bars of both types keep the bar's glow style and tint: the
-- runtime styles their aura glows ("glow while active", stack glows) with
-- them. The built-in Buffs and Buff bars rows have none (default look).
local AURA_EXTRA = { glowStyle = true, glowTint = true, glowColor = true }
Page.AURA_EXTRA = AURA_EXTRA
function Page.Relevant(slot, suffix)
    local key = KEYS[slot] and KEYS[slot][suffix]
    if not key or RULES[key].hidden then return false end
    if not Page.SlotInfo(slot).custom or suffix == "name" or suffix == "kind" then return true end
    local kind = Page.Kind(slot)
    if kind == 3 and KIND3_EXTRA[suffix] then return true end
    if (kind == 2 or kind == 3) and AURA_EXTRA[suffix] then return true end
    local ref = REF_KEYS[kind] or REF_KEYS[1]
    return ref[suffix] ~= nil
end

-- Controls are built from custom bar 1's rules; keyFn points them at the
-- selected bar. A suffix the bar lacks keeps the template key; its gate below
-- keeps that control disabled.
local TEMPLATE_SUFFIX = {}
for suffix, key in pairs(KEYS.c1) do TEMPLATE_SUFFIX[key] = suffix end
function Page.KeyFn(key)
    local suffix = TEMPLATE_SUFFIX[key]
    if not suffix then return key end
    return KEYS[Page.selected][suffix] or key
end
-- The sound channel means nothing while the module's sounds are muted.
P.Gates[ID] = function(rule)
    if rule.key == "soundChannel" then return P.Get(ID, "muteSounds") ~= true end
    if not TEMPLATE_SUFFIX[rule.key] then return true end
    return Page.Relevant(Page.selected, rule.suffix)
end

-- Text inputs commit on blur. An input remembers the bar it was focused on,
-- and a bar switch commits the pending text first, so a typed name always
-- lands on the bar it was typed for.
Page.inputs = Page.inputs or {}
local function InputFocusGained(self) self._cdmSlot = Page.selected end
local function InputFocusLost(self) self._cdmSlot = nil end
function Page.TrackInput(input)
    if not (input and input.HookScript) then return end
    input:HookScript("OnEditFocusGained", InputFocusGained)
    input:HookScript("OnEditFocusLost", InputFocusLost)
    Page.inputs[#Page.inputs + 1] = input
end
function Page.InputKey(input, key)
    local slot, suffix = input and input._cdmSlot, TEMPLATE_SUFFIX[key]
    local own = slot and suffix and KEYS[slot] and KEYS[slot][suffix]
    return own or Page.KeyFn(key)
end
function Page.CommitFocus()
    local inputs = Page.inputs
    for i = 1, #inputs do
        local input = inputs[i]
        if input.HasFocus and input:HasFocus() then input:ClearFocus() end
        input._cdmSlot = nil
    end
end

------------------------------------------------------------------ runtime access
-- The runtime addon owns the spell catalog and the preview renderer. It loads
-- on page activation, never in combat, and only where the module can run.
function Page.EnsureRuntime()
    if S.CooldownManagerBarEntries then return true end
    if Page.loadFailed or P.Combat() or not S.Availability(ID) then return false end
    if not Suite.Client.IsAddOnLoaded(RUNTIME) then
        local load = _G.C_AddOns and _G.C_AddOns.LoadAddOn or _G.LoadAddOn
        if type(load) ~= "function" then Page.loadFailed = "LoadAddOn unavailable"; return false end
        local loaded, reason = load(RUNTIME)
        if not loaded and not Suite.Client.IsAddOnLoaded(RUNTIME) then
            Page.loadFailed = tostring(reason or "not installed")
        end
    end
    return S.CooldownManagerBarEntries ~= nil
end

function Page.Entries(slot)
    local get = S.CooldownManagerBarEntries
    local list = get and get(slot)
    return type(list) == "table" and list or nil
end
function Page.Catalog(family)
    local get = S.CooldownManagerCatalogEntries
    local list = get and get(family)
    return type(list) == "table" and list or nil
end

-- Why the spell editor is empty, or nil when it can edit.
function Page.EditorBlocked()
    local ok, reason = S.Availability(ID)
    if not ok then return Tr(reason or "Unavailable on this client") end
    if not S.CooldownManagerBarEntries then
        if Page.loadFailed then return Tr("Cannot load MSUF_Suite_CooldownManager") .. ": " .. Page.loadFailed end
        if Suite.Client.IsAddOnLoaded(RUNTIME) then return Tr("The cooldown manager needs an update. Reload the interface.") end
        return Tr("Open this page out of combat to load the cooldown manager.")
    end
    if not Page.Spec() then return Tr("Your specialization is not known yet.") end
end

function Page.Spec()
    local get = S.CooldownManagerSpec
    if get then
        local id, name, icon = get()
        if Public(id) and type(id) == "number" and id > 0 then
            return id, Public(name) and type(name) == "string" and name or nil, Public(icon) and icon or nil
        end
    end
    local info = _G.C_SpecializationInfo
    local index
    if info and info.GetSpecialization then index = info.GetSpecialization()
    elseif type(_G.GetSpecialization) == "function" then index = _G.GetSpecialization() end
    if not Public(index) or type(index) ~= "number" or index < 1 then return nil end
    local lookup = info and info.GetSpecializationInfo or _G.GetSpecializationInfo
    if type(lookup) ~= "function" then return nil end
    local id, name, _, icon = lookup(index)
    if not Public(id) or type(id) ~= "number" or id <= 0 then return nil end
    return id, Public(name) and type(name) == "string" and name or nil, Public(icon) and icon or nil
end

function Page.ClassSpecs(out)
    local count = 0
    if type(_G.GetNumSpecializations) == "function" then count = _G.GetNumSpecializations() end
    local info = _G.C_SpecializationInfo
    local lookup = info and info.GetSpecializationInfo or _G.GetSpecializationInfo
    if not Public(count) or type(count) ~= "number" or type(lookup) ~= "function" then return out end
    for i = 1, min(count, 6) do
        local id = lookup(i)
        if Public(id) and type(id) == "number" and id > 0 then out[#out + 1] = id end
    end
    return out
end

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
    local fields = Page.SpellOverrides().e[key]
    if fields then return fields[field] end
end
function Page.HasList(slot)
    local spec = Page.Spec()
    local slots = spec and Page.ListsView().specs[spec]
    return slots ~= nil and slots[slot] ~= nil
end
-- The bar's list holds spells or items the player added (not Blizzard's).
function Page.HasOwnEntries(slot)
    local spec = Page.Spec()
    local slots = spec and Page.ListsView().specs[spec]
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
    local slots = spec and Page.ListsView().specs[spec]
    if not slots then return nil end
    for slot, list in pairs(slots) do
        for i = 1, #list do if list[i] == key then return slot end end
    end
end

local function IndexOf(list, key)
    if not list then return nil end
    for i = 1, #list do if list[i] == key then return i end end
end
local function Prune(lists, spec)
    local slots = lists.specs[spec]
    if slots then
        for slot, list in pairs(slots) do if #list == 0 then slots[slot] = nil end end
        if next(slots) == nil then lists.specs[spec] = nil end
    end
    local hidden = lists.hidden[spec]
    if hidden and next(hidden) == nil then lists.hidden[spec] = nil end
end
-- An explicit order that matches what the bar shows now, followed by listed
-- entries it cannot show right now (unlearned talents keep their place).
local function Materialize(lists, spec, slot)
    local slots = lists.specs[spec]
    if not slots then slots = {}; lists.specs[spec] = slots end
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
        if lists and spells then ok, reason = P.SetMany(ID, values)
        elseif lists then ok, reason = P.Set(ID, "listsData", values.listsData)
        else ok, reason = P.Set(ID, "spellsData", values.spellsData) end
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
    if family ~= 1 and family ~= 2 then return nil end
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
        local slots = lists.specs[spec]
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
        local wrong = WrongFamily(family, slot)
        if wrong then return false, wrong end
        local list = Materialize(lists, spec, slot)
        local at = IndexOf(list, key)
        if at then table.remove(list, at)
        elseif #list >= CDM.LIMITS.entries then return false, "This bar is full." end
        local index = beforeKey and beforeKey ~= key and IndexOf(list, beforeKey) or (#list + 1)
        local hidden = lists.hidden[spec]
        if at and index == at and not (hidden and hidden[key]) then return true end
        table.insert(list, index, key)
        Unclaim(lists, spec, key, slot)
        return at and "Reorder cooldown bar" or "Move to another bar"
    end)
end

-- What dropping a bar's own list does: built-in bars go back to Blizzard's
-- list, Defensives to the class preset, custom bars are emptied.
function Page.ClearLabel(slot)
    local info = Page.SlotInfo(slot)
    if info.custom then return "Remove all spells" end
    return info.preset == "defensives" and "Restore default spells" or "Reset to Blizzard's list"
end
function Page.ClearList(slot)
    return EditLists(function(lists, spec)
        local slots = lists.specs[spec]
        if not (slots and slots[slot]) then return true end
        slots[slot] = nil
        return Page.ClearLabel(slot)
    end)
end
function Page.RestoreHidden()
    return EditLists(function(lists, spec)
        if not lists.hidden[spec] then return true end
        lists.hidden[spec] = nil
        return "Show removed spells"
    end)
end
-- Custom entries only: Blizzard entries follow each specialization's own list.
function Page.CopyToSpecs(slot, key)
    local spec, err = Ready()
    if not spec then return false, err end
    if CDM.EntryKind(key) == "b" then return false, "Blizzard entries follow each specialization's own list." end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local changed = 0
    for _, other in ipairs(Page.ClassSpecs({})) do
        if other ~= spec then
            local slots = lists.specs[other] or {}
            lists.specs[other] = slots
            Unclaim(lists, other, key, slot)
            local list = slots[slot] or {}
            slots[slot] = list
            if not IndexOf(list, key) and #list < CDM.LIMITS.entries then
                list[#list + 1] = key
                changed = changed + 1
            end
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
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local own, keys = lists.specs[spec] and lists.specs[spec][slot], {}
    for i = 1, own and #own or 0 do
        if CDM.EntryKind(own[i]) ~= "b" then keys[#keys + 1] = own[i] end
    end
    if #keys == 0 then return false, "This bar has no spells or items you added." end
    local added, specs = 0, 0
    for _, other in ipairs(Page.ClassSpecs({})) do
        if other ~= spec then
            local slots = lists.specs[other] or {}
            lists.specs[other] = slots
            local before = added
            for i = 1, #keys do
                local key = keys[i]
                Unclaim(lists, other, key, slot)
                local list = slots[slot] or {}
                slots[slot] = list
                if not IndexOf(list, key) and #list < CDM.LIMITS.entries then
                    list[#list + 1] = key
                    added = added + 1
                end
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
    local fields = spells.e[key]
    if value == nil then
        if not fields or fields[field] == nil then return true end
        fields[field] = nil
        if next(fields) == nil then spells.e[key] = nil end
    else
        if fields and fields[field] == value then return true end
        if not fields then
            local count = 0
            for _ in pairs(spells.e) do count = count + 1 end
            if count >= CDM.LIMITS.spells then return false, "Too many spell choices." end
            fields = {}
            spells.e[key] = fields
        end
        fields[field] = value
    end
    return Page.Commit("Spell option", nil, spells)
end
function Page.ResetSpell(key)
    if P.Combat() then return false, COMBAT end
    local spells = CDM.Codec.DecodeSpells(P.Get(ID, "spellsData"))
    if not spells.e[key] then return true end
    spells.e[key] = nil
    return Page.Commit("Reset spell options", nil, spells)
end
-- A popover row that edits two fields resets both in one history entry.
function Page.ClearSpellFields(key, names)
    if P.Combat() then return false, COMBAT end
    local spells = CDM.Codec.DecodeSpells(P.Get(ID, "spellsData"))
    local fields = spells.e[key]
    if not fields then return true end
    local changed = false
    for i = 1, #names do
        if fields[names[i]] ~= nil then fields[names[i]], changed = nil, true end
    end
    if not changed then return true end
    if next(fields) == nil then spells.e[key] = nil end
    return Page.Commit("Spell option", nil, spells)
end

------------------------------------------------------------------ notes and undo
-- One short line under the spell tiles; it clears itself after 8 seconds
-- through Menu2's cancellable timer (nothing is scheduled in combat).
function Page.ClearNote()
    local task = Page.noteTask
    Page.noteTask, Page.note, Page.undo = nil, nil, nil
    if task and task.Cancel then task:Cancel() end
    if Page.ui and Page.ui.PaintNote then Page.ui.PaintNote() end
end
function Page.Note(text, undo, isError)
    local task = Page.noteTask
    Page.noteTask = nil
    if task and task.Cancel then task:Cancel() end
    Page.note, Page.undo, Page.noteError = text, undo, isError == true
    local timer = M.MenuTimer
    if text and timer and timer.After then Page.noteTask = timer.After(8, Page.ClearNote) end
    if Page.ui and Page.ui.PaintNote then Page.ui.PaintNote() end
end
function Page.Fail(reason) Page.Note(Tr(reason or "That did not work."), nil, true) end

-- A gesture that can drop data, with an 8 s Undo line. keys: the settings it
-- may change. The Undo puts them back as one history entry, and only while
-- nothing changed them since. Returns what `run` returned.
local LIST_KEYS = { "listsData" }
Page.LIST_KEYS = LIST_KEYS
local function Snapshot(keys)
    local out = {}
    for i = 1, #keys do out[keys[i]] = P.Get(ID, keys[i]) end
    return out
end
local function Restore(before, after)
    if P.Combat() then return false end
    local values = {}
    for key, value in pairs(after) do
        if P.Get(ID, key) ~= value then Page.Fail("That changed since, so it cannot be undone."); return false end
        if before[key] ~= value then values[key] = before[key] end
    end
    local restored
    P.WithHistory("Undo", "suite:cooldownManager.undo", function()
        -- Turning the module back on applies the suite look first; the other
        -- values follow it, so they come back exactly.
        if values.enabled == true then
            values.enabled = nil
            if not P.Set(ID, "enabled", true) then return false end
        end
        restored = P.SetMany(ID, values)
        return restored
    end)
    return restored
end
-- text: the note, or a function of run's extra results that returns it.
function Page.WithUndo(text, keys, run)
    local before = Snapshot(keys)
    local ok, reason, extra = run()
    if not ok then return false, reason end
    local after = Snapshot(keys)
    for key, value in pairs(after) do
        if before[key] ~= value then
            if type(text) == "function" then text = text(reason, extra) end
            Page.Note(text, function() return Restore(before, after) end)
            break
        end
    end
    return ok, reason, extra
end
-- Keys of one bar (plus its spell lists) for Page.WithUndo.
function Page.SlotKeys(slot, withLists)
    local keys = {}
    for _, key in pairs(KEYS[slot]) do keys[#keys + 1] = key end
    if withLists then keys[#keys + 1] = "listsData" end
    -- The Essential bar's x/y may count from Blizzard's bar.
    if slot == "ess" and RULES.essOnViewer then keys[#keys + 1] = "essOnViewer" end
    return keys
end

function Page.RemoveWithUndo(slot, key, name)
    local ok, reason = Page.WithUndo(format(Tr("Removed %s."), name or key), LIST_KEYS,
        function() return Page.RemoveEntry(slot, key) end)
    if not ok then Page.Fail(reason) end
    return ok
end
-- The Spell list's list-wide actions, each with its Undo line.
function Page.ClearWithUndo(slot)
    local label = Page.ClearLabel(slot)
    local text = label == "Remove all spells" and format(Tr("Removed every spell from %s."), Page.BarName(slot))
        or label == "Restore default spells" and format(Tr("%s is back to its default spells."), Page.BarName(slot))
        or format(Tr("%s follows Blizzard's list again."), Page.BarName(slot))
    local ok, reason = Page.WithUndo(text, LIST_KEYS, function() return Page.ClearList(slot) end)
    if not ok then Page.Fail(reason) end
    return ok
end
function Page.RestoreWithUndo()
    local count = Page.HiddenCount()
    local ok, reason = Page.WithUndo(format(Tr("Brought back the removed spells (%d)."), count), LIST_KEYS, Page.RestoreHidden)
    if not ok then Page.Fail(reason) end
    return ok
end
local function CopiedText(added, specs)
    return format(Tr("Copied %d entries to %d other specializations."), added, specs)
end
function Page.CopyListWithUndo(slot)
    local ok, added = Page.WithUndo(CopiedText, LIST_KEYS, function() return Page.CopyListToSpecs(slot) end)
    if not ok then Page.Fail(added); return false end
    if added == 0 then Page.Note(Tr("Your other specializations have them already.")) end
    return true
end
function Page.RunUndo()
    local undo = Page.undo
    Page.ClearNote()
    if undo then undo() end
end

------------------------------------------------------------------ bars
function Page.Select(slot)
    if type(slot) ~= "string" or not CDM.SLOT_INDEX[slot] then return false end
    if Page.selected ~= slot then
        Page.CommitFocus()
        Page.selected = slot
        Page.ClosePopups()
    end
    P.Refresh()
    return true
end
-- New bars prefer a custom slot that was never named; a used slot that is off
-- is reused only when no fresh one is left (second result true).
function Page.FreeCustom()
    local reuse
    for i = 1, #SLOTS do
        local info = SLOTS[i]
        if info.custom and not Page.IsOn(info.key) then
            if P.Get(ID, KEYS[info.key].name) == "" then return info.key, false end
            reuse = reuse or info.key
        end
    end
    return reuse, reuse ~= nil
end
local DEFAULT_NAMES = { "Cooldowns", "Buffs", "Timers" }
-- A free bar that would sit exactly on another shown free bar moves down a
-- step, so several new bars never stack on one spot.
local function Occupied(slot, x, y)
    for i = 1, #SLOTS do
        local other = SLOTS[i].key
        local k = KEYS[other]
        if other ~= slot and Page.IsOn(other) and P.Get(ID, k.anchor) == 1
            and P.Get(ID, k.x) == x and P.Get(ID, k.y) == y then return true end
    end
    return false
end
local function FreeSpot(slot, x, y)
    local low = RULES[KEYS[slot].y].min
    for _ = 1, #SLOTS do
        if not Occupied(slot, x, y) or y - 48 < low then break end
        y = y - 48
    end
    return x, y
end
-- A custom slot used before starts over as a new bar: settings back to
-- their defaults and its spells dropped from every specialization.
local function ResetSlot(slot, values)
    for _, key in pairs(KEYS[slot]) do
        local default = RULES[key].default
        if P.Get(ID, key) ~= default then values[key] = default end
    end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local changed = false
    for spec, slots in pairs(lists.specs) do
        if slots[slot] then
            slots[slot] = nil
            changed = true
            Prune(lists, spec)
        end
    end
    if changed then values.listsData = CDM.Codec.EncodeLists(lists) end
end
local function NewBarValues(slot, kind, reused)
    local keys = KEYS[slot]
    local values = {}
    if reused then ResetSlot(slot, values) end
    values[keys.on], values[keys.kind] = true, kind
    local name = Tr(DEFAULT_NAMES[kind]) .. " " .. slot:sub(2)
    if #name > RULES[keys.name].maxLength then name = "Bar " .. slot:sub(2) end
    values[keys.name] = name
    local anchor = values[keys.anchor] or P.Get(ID, keys.anchor)
    if anchor == 1 then
        local x, y = values[keys.x] or P.Get(ID, keys.x), values[keys.y] or P.Get(ID, keys.y)
        local nx, ny = FreeSpot(slot, x, y)
        if nx ~= x or ny ~= y then values[keys.x], values[keys.y] = nx, ny end
    end
    return values
end
-- A reused slot starts over; its old settings and spells come back with Undo.
function Page.AddBar(kind)
    if P.Combat() then return false end
    local slot, reused = Page.FreeCustom()
    if not slot then Page.Fail("All six custom bars are in use."); return false end
    kind = (kind == 2 or kind == 3) and kind or 1
    Page.CommitFocus()
    local ok
    if reused then
        ok = Page.WithUndo(format(Tr("%s was reset for the new bar."), Page.BarName(slot)), Page.SlotKeys(slot, true),
            function() return P.SetMany(ID, NewBarValues(slot, kind, true)) end)
    else
        ok = P.SetMany(ID, NewBarValues(slot, kind, false))
    end
    if ok then
        Page.selected = slot
        Page.ClosePopups()
        P.Refresh()
        Page.FocusName()
    end
    return ok
end
-- The name input of the selected custom bar takes the keyboard (a new or
-- renamed bar); Frame Basics comes into view first.
function Page.FocusName()
    local input = Page.ui and Page.ui.nameInput
    if P.Combat() or not (input and input.SetFocus) or not Page.SlotInfo(Page.selected).custom then return false end
    Page.FocusSection("bars")
    input:SetFocus()
    if input.HighlightText then input:HighlightText() end
    return true
end
-- A custom bar goes back to a free slot: default settings, no name, off, and
-- its spells gone from every specialization. One history entry, with Undo.
function Page.DeleteBar(slot)
    if P.Combat() or not Page.SlotInfo(slot).custom then return false end
    Page.CommitFocus()
    local ok, reason = Page.WithUndo(format(Tr("Deleted %s."), Page.BarName(slot)), Page.SlotKeys(slot, true), function()
        local values = {}
        ResetSlot(slot, values)
        if next(values) == nil then return true end
        return P.SetMany(ID, values)
    end)
    if not ok then Page.Fail(reason); return false end
    if Page.selected == slot then
        local first = "ess"
        for i = 1, #SLOTS do
            if Page.IsOn(SLOTS[i].key) then first = SLOTS[i].key; break end
        end
        Page.Select(first)
    end
    return true
end
-- Settings that make a bar what it is and where it sits never copy: name,
-- type, attachment, position and how it grows.
local COPY_SKIP = { on = true, name = true, kind = true, anchor = true, side = true, gap = true, x = true, y = true,
    vertical = true, grow = true, align = true }
function Page.CopyBarSettings(from, to)
    if P.Combat() or from == to or not (KEYS[from] and KEYS[to]) then return false end
    local values, keys = {}, {}
    for suffix, key in pairs(KEYS[to]) do
        local source = KEYS[from][suffix]
        if source and not COPY_SKIP[suffix] and Page.Relevant(to, suffix) and Page.Relevant(from, suffix) then
            local value = P.Get(ID, source)
            if P.Get(ID, key) ~= value then values[key], keys[#keys + 1] = value, key end
        end
    end
    if #keys == 0 then
        Page.Note(format(Tr("%s already looks like %s."), Page.BarName(to), Page.BarName(from)))
        return true
    end
    local ok, reason = Page.WithUndo(format(Tr("%s now uses the settings of %s."), Page.BarName(to), Page.BarName(from)),
        keys, function() return P.SetMany(ID, values) end)
    if not ok then Page.Fail(reason) end
    return ok
end
-- Kept by "Reset this bar's settings": identity, bar type and position.
local RESET_KEEP = { on = true, name = true, kind = true, x = true, y = true }
function Page.ResetBar(slot)
    if P.Combat() then return false end
    local k = KEYS[slot]
    local ok, reason = Page.WithUndo(format(Tr("Reset the settings of %s."), Page.BarName(slot)), Page.SlotKeys(slot),
        function()
            local values = {}
            for suffix, key in pairs(k) do
                if not RESET_KEEP[suffix] then values[key] = RULES[key].default end
            end
            -- x/y follow the attachment: an attached bar goes back flush on
            -- its anchor, a bar that becomes free keeps its place on screen.
            local anchor = RULES[k.anchor].default
            if anchor ~= 1 or P.Get(ID, k.anchor) ~= 1 then
                local moved = S.CooldownManagerConvertAnchor and S.CooldownManagerConvertAnchor(slot, anchor)
                if type(moved) == "table" then for key, value in pairs(moved) do values[key] = value end end
            end
            return P.SetMany(ID, values)
        end)
    if not ok then Page.Fail(reason) end
    return ok
end
-- Everything of the module: settings, every specialization's spell lists
-- and every spell's options. One history entry, and an Undo line.
function Page.ResetModule()
    if P.Combat() then return false end
    local keys = {}
    for key in pairs(RULES) do keys[#keys + 1] = key end
    return Page.WithUndo(Tr("The cooldown manager was reset: settings, spell lists and spell options."), keys, function()
        local done
        P.WithHistory("Reset cooldown manager", "suite:cooldownManager.reset", function()
            done = S.Reset(ID)
            return done
        end)
        return done == true
    end)
end
function Page.EnableBar(slot)
    if P.Combat() or not Page.SlotInfo(slot).custom then return false end
    Page.CommitFocus()
    local ok = P.Set(ID, KEYS[slot].on, true)
    if ok then
        Page.selected = slot
        Page.ClosePopups()
        P.Refresh()
    end
    return ok
end
-- New bars by type, then custom bars that are off but were named before.
local addValues = {}
local function AddValue(n, value, text, header)
    local item = addValues[n] or {}
    addValues[n] = item
    item.value, item.text, item.header, item.translate, item.tooltip = value, text, header, nil, nil
    -- Bar names are already translated (or typed by the player).
    if not header and type(value) == "string" then item.translate = false end
    return n
end
local function AddPicked(value)
    if type(value) == "string" then Page.EnableBar(value) else Page.AddBar(tonumber(value) or 1) end
end
function Page.OpenAddBar(owner)
    if P.Combat() then return false end
    local free, reused = Page.FreeCustom()
    if not free then Page.Fail("All six custom bars are in use."); return false end
    if not (W.OpenDropdown and owner) then return Page.AddBar(1) end
    -- Every slot was used: a new bar starts one of them over, and says which.
    local old = reused and Page.BarName(free) or nil
    local n = 0
    for kind = 1, #KIND_NAMES do
        n = AddValue(n + 1, kind, KIND_NAMES[kind])
        if old then
            local item = addValues[n]
            item.text, item.translate = format(Tr("%s (replaces %s)"), Tr(KIND_NAMES[kind]), old), false
            item.tooltip = format(Tr("All six custom bars were used before. The new bar starts %s over: its settings, and its spells in every specialization. You can undo it."), old)
        end
    end
    local headed = false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if SLOTS[i].custom and not Page.IsOn(slot) and P.Get(ID, KEYS[slot].name) ~= "" then
            if not headed then n = AddValue(n + 1, "header", "Turn a bar back on", true); headed = true end
            n = AddValue(n + 1, slot, Page.BarName(slot))
        end
    end
    for i = n + 1, #addValues do addValues[i] = nil end
    Page.dropdownOpen = true
    return W.OpenDropdown(owner, addValues, nil, AddPicked)
end

-- Bar actions: right-click on a bar chip, or "Bar actions" in Frame Basics.
-- One flat list (Menu2 lists do not nest): the actions, then the bars whose
-- settings can be copied onto this one.
local barMenu, COPY_VALUE, COPY_FROM = {}, {}, {}
for i = 1, #SLOTS do
    local key = SLOTS[i].key
    COPY_VALUE[key] = "copy:" .. key
    COPY_FROM[COPY_VALUE[key]] = key
end
local function MenuItem(n, value, text)
    local item = barMenu[n] or {}
    barMenu[n] = item
    item.value, item.text, item.header, item.translate, item.disabled, item.tooltip = value, text, nil, nil, nil, nil
    return item
end
local function BarPicked(value)
    local slot = Page.menuSlot
    if P.Combat() or not (slot and KEYS[slot]) then return end
    local from = COPY_FROM[value]
    if from then Page.CopyBarSettings(from, slot)
    elseif value == "show" then
        if Page.SlotInfo(slot).custom then Page.EnableBar(slot) else P.Set(ID, KEYS[slot].on, true) end
    elseif value == "hide" then P.Set(ID, KEYS[slot].on, false)
    elseif value == "rename" then
        Page.Select(slot)
        Page.FocusName()
    elseif value == "move" then P.MoveOnScreen(ID, slot)
    elseif value == "reset" then Page.ResetBar(slot)
    elseif value == "delete" then Page.DeleteBar(slot) end
end
function Page.OpenBarMenu(owner, slot)
    slot = slot or Page.selected
    if P.Combat() or not (W.OpenDropdown and owner and KEYS[slot]) then return false end
    local custom, on = Page.SlotInfo(slot).custom, Page.IsOn(slot)
    local n = 1
    MenuItem(n, on and "hide" or "show", on and "Hide this bar" or "Show this bar")
    if custom then n = n + 1; MenuItem(n, "rename", "Rename this bar") end
    n = n + 1
    local move = MenuItem(n, "move", "Move on screen")
    move.disabled = not (on and Page.Movable(slot) and P.Get(ID, "enabled"))
    if move.disabled then move.tooltip = Tr(on and "This bar cannot be moved on its own right now." or "Show this bar first.") end
    n = n + 1
    MenuItem(n, "reset", "Reset this bar's settings").tooltip = Tr("Keeps its name, type and position. You can undo it.")
    if custom then
        n = n + 1
        MenuItem(n, "delete", "Delete this bar").tooltip =
            Tr("Frees this custom bar: its settings, and its spells in every specialization. You can undo it.")
    end
    n = n + 1
    local header = MenuItem(n, "copy", "Copy settings from")
    header.header = true
    header.tooltip = Tr("Look, size, text, effects and visibility. The name, type and position stay.")
    for i = 1, #SLOTS do
        local other = SLOTS[i].key
        if other ~= slot and Page.Listed(other) then
            n = n + 1
            local item = MenuItem(n, COPY_VALUE[other], Page.BarName(other))
            item.translate = false
        end
    end
    for i = n + 1, #barMenu do barMenu[i] = nil end
    Page.menuSlot = slot
    Page.dropdownOpen = true
    return W.OpenDropdown(owner, barMenu, nil, BarPicked)
end
function Page.FocusSection(id)
    local body = Page.ui and Page.ui.sections and Page.ui.sections[id]
    if body and W.FocusCollapsibleSection then W.FocusCollapsibleSection(body, { persist = true, flash = true }) end
end
function Page.CanOpenBlizzardSettings()
    local panel = _G.CooldownViewerSettings
    return type(panel) == "table" and type(panel.TogglePanel) == "function" and not P.Combat()
end
-- Blizzard's panel sits below the MSUF window, so the menu steps aside.
function Page.OpenBlizzardSettings()
    if not Page.CanOpenBlizzardSettings() then return false end
    if M.frame and M.frame.Hide then M.frame:Hide() end
    _G.CooldownViewerSettings:TogglePanel()
    return true
end
local function Media()
    local stub = _G.LibStub
    return type(stub) == "table" and type(stub.GetLibrary) == "function" and stub:GetLibrary("LibSharedMedia-3.0", true) or nil
end
function Page.PlaySound(value)
    if type(value) ~= "string" or value == "" then return end
    if S.CooldownManagerPlaySound then S.CooldownManagerPlaySound(value); return end
    local name = value:match("^lsm:(.+)$")
    local lsm = name and Media()
    local path = lsm and lsm.Fetch and lsm:Fetch("sound", name, true)
    if path and type(_G.PlaySoundFile) == "function" then _G.PlaySoundFile(path, "Master") end
end
-- Blizzard's Cooldown Manager sound list, read only: CooldownViewerSoundData
-- maps Enum.CooldownViewerSoundCategory values to { soundEnum, soundKitID,
-- text } rows. Built once per table; the kits play as "kit:<soundKitID>".
local kitSounds = { groups = {}, names = {} }
local function CategoryTitle(id)
    local enum = _G.Enum and _G.Enum.CooldownViewerSoundCategory
    local key
    if type(enum) == "table" then
        for name, value in pairs(enum) do
            if value == id and type(name) == "string" then key = name end
        end
    end
    if not key then return format(Tr("Category %d"), id) end
    local text = _G["COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_" .. key:upper()]
    if type(text) == "string" and text ~= "" then return text end
    -- "War2" reads "War 2", "ShortSounds" reads "Short Sounds".
    return (key:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"))
end
local function KitGroup(id, rows)
    local group = { title = CategoryTitle(id) }
    for i = 1, #rows do
        local row = rows[i]
        local kit = type(row) == "table" and row.soundKitID or nil
        if type(kit) == "number" and kit > 0 and kit < 2147483648 and kit == floor(kit) then
            local text = row.text
            if type(text) ~= "string" or text == "" then text = Tr("Sound kit") .. " " .. format("%d", kit) end
            group[#group + 1] = { value = "kit:" .. format("%d", kit), text = text }
            kitSounds.names[kit] = text
        end
    end
    return group
end
function Page.BlizzardSounds()
    local data = _G.CooldownViewerSoundData
    if type(data) ~= "table" then return nil end
    if kitSounds.data == data then return kitSounds end
    local groups, ids = kitSounds.groups, {}
    for i = #groups, 1, -1 do groups[i] = nil end
    for kit in pairs(kitSounds.names) do kitSounds.names[kit] = nil end
    for id, rows in pairs(data) do
        if type(id) == "number" and type(rows) == "table" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for i = 1, #ids do
        local group = KitGroup(ids[i], data[ids[i]])
        if #group > 0 then groups[#groups + 1] = group end
    end
    kitSounds.data = data
    return kitSounds
end
function Page.SoundLabel(value)
    if type(value) ~= "string" or value == "" then return Tr("None") end
    local name = value:match("^lsm:(.+)$")
    if name then return name end
    local kit = value:match("^kit:(%d+)$")
    if kit then
        local known = Page.BlizzardSounds()
        return known and known.names[tonumber(kit)] or (Tr("Sound kit") .. " " .. kit)
    end
    local file = value:match("^file:(%d+)$")
    return file and (Tr("Sound file") .. " " .. file) or value
end
function Page.Identity(key)
    local kind, number = CDM.EntryKind(key), CDM.EntryID(key)
    if kind == "b" then return Tr("From Blizzard's Cooldown Manager") end
    if kind == "s" then return format(Tr("Spell %d"), number) end
    if kind == "i" then return format(Tr("Item %d"), number) end
    if kind == "e" then return format(Tr("Equipment slot %d"), number) end
    if kind == "a" then return format(Tr("Buff %d on you"), number) end
    return format(Tr("Debuff %d on your target"), number)
end

------------------------------------------------------------------ popups
local function Button(parent, text, width, height, onClick)
    local button = T.Button(parent, text and Tr(text) or "", width, height or 22, { noSearch = true })
    button._msuf2SkipHistoryCheckpoint = true
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end
local function Label(parent, template, text, colorName)
    local label = T.Font(parent, template or "GameFontHighlightSmall", text or "", T.colors and T.colors[colorName or "text"])
    if label.SetJustifyH then label:SetJustifyH("LEFT") end
    if label.SetWordWrap then label:SetWordWrap(false) end
    return label
end
-- Captions built from data skip the locale lookup and the search index.
local function ButtonText(button, text)
    local label = button._msuf2Label
    if label then SetRaw(label, text) else button:SetText(text) end
end
Page.Button, Page.Label, Page.ButtonText = Button, Label, ButtonText

local function Cursor()
    if type(_G.GetCursorPosition) ~= "function" then return nil end
    local x, y = _G.GetCursorPosition()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end
local function Scale(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    return type(scale) == "number" and scale > 0 and scale or 1
end
Page.Cursor, Page.Scale = Cursor, Scale

local function ShowTip(owner, title, first, second, third)
    local tip = _G.GameTooltip
    if not (tip and tip.SetOwner) then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(title or "", 1, 1, 1)
    if first and first ~= "" then tip:AddLine(first, 0.82, 0.82, 0.82, true) end
    if second and second ~= "" then tip:AddLine(second, 0.82, 0.82, 0.82, true) end
    if third and third ~= "" then
        local r, g, b = Accent()
        tip:AddLine(third, r, g, b, true)
    end
    tip:Show()
end
local function HideTip(owner)
    local tip = _G.GameTooltip
    if tip and tip.IsOwned and tip:IsOwned(owner) then tip:Hide() end
end
Page.ShowTip, Page.HideTip = ShowTip, HideTip

-- Popups close with the menu, on combat and on a click elsewhere. The event
-- frame listens only while one of them is open.
local watch
local function AnyPopup()
    for i = 1, #Page.popups do if Page.popups[i]:IsShown() then return true end end
    return false
end
local function MouseOver(frame)
    return frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver() and true or false
end
local function OnWatchEvent(_, event)
    if event ~= "GLOBAL_MOUSE_DOWN" then Page.ClosePopups(); return end
    if MouseOver(_G.MSUF2NativeDropdownList) then return end
    for i = 1, #Page.popups do if MouseOver(Page.popups[i]) then return end end
    for i = 1, #Page.popups do
        local popup = Page.popups[i]
        if popup:IsShown() and not MouseOver(popup.anchor) then popup:Hide() end
    end
end
local function Watch()
    local open = AnyPopup()
    if open and not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", OnWatchEvent)
    end
    if not watch then return end
    if open then
        watch:RegisterEvent("PLAYER_REGEN_DISABLED")
        if Suite.Client.SupportsEvent("GLOBAL_MOUSE_DOWN") then watch:RegisterEvent("GLOBAL_MOUSE_DOWN") end
    else
        watch:UnregisterAllEvents()
    end
end
local function PopupShown() Watch() end
local function PopupHidden(self)
    -- Hidden together with the menu: stay closed when the menu returns.
    if self:IsShown() then self:Hide() end
    if self.OnClosed then self:OnClosed() end
    HideTip(self)
    Watch()
end
function Page.NewPopup(width, height)
    local parent = M.frame or _G.UIParent
    local panel = M.CreateMenuPopupPanel and M.CreateMenuPopupPanel(parent, {}) or nil
    if not panel then
        panel = CreateFrame("Frame", nil, parent)
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        local fill = panel:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(panel)
        fill:SetColorTexture(0.02, 0.03, 0.06, 0.97)
        panel:EnableMouse(true)
    end
    panel:SetSize(width, height)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:Hide()
    panel:HookScript("OnShow", PopupShown)
    panel:HookScript("OnHide", PopupHidden)
    Page.popups[#Page.popups + 1] = panel
    return panel
end
function Page.ClosePopups(keep)
    for i = 1, #Page.popups do
        local popup = Page.popups[i]
        if popup ~= keep and popup:IsShown() then popup:Hide() end
    end
    if Page.dropdownOpen and W.CloseDropdown then W.CloseDropdown({ immediate = true }) end
    Page.dropdownOpen = nil
end
-- Closes the popups whose anchor went out of sight (a closed spell list),
-- then those anchored inside them; the preview keeps its own open.
function Page.CloseOrphans()
    for _ = 1, 2 do
        for i = 1, #Page.popups do
            local popup = Page.popups[i]
            local anchor = popup.anchor
            if popup:IsShown() and anchor and anchor.IsVisible and not anchor:IsVisible() then popup:Hide() end
        end
    end
end
function Page.PlacePopup(popup, anchor)
    popup.anchor = anchor
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
end

local function Wheel(self, delta)
    local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange()
    local value = self.GetVerticalScroll and self:GetVerticalScroll()
    if type(range) ~= "number" then range = 0 end
    if type(value) ~= "number" then value = 0 end
    self:SetVerticalScroll(max(0, min(range, value - delta * 48)))
end
function Page.ScrollArea(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", Wheel)
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, parent) end
    return scroll, content
end
local function ClearFocus(self) self:ClearFocus() end
function Page.SearchBox(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    if T.SkinEditBox then T.SkinEditBox(box) end
    box.placeholder = Label(box, "GameFontDisableSmall", placeholder, "muted")
    box.placeholder:SetPoint("LEFT", box, "LEFT", 6, 0)
    box:SetScript("OnEscapePressed", ClearFocus)
    box:SetScript("OnEnterPressed", ClearFocus)
    box:SetScript("OnTextChanged", function(self, userInput)
        self.placeholder:SetShown((self:GetText() or "") == "")
        onChange(self, userInput)
    end)
    return box
end
-- Plain, lower-case search text; protected names never reach string functions.
-- Spell IDs (base, override and the tooltip's) make Blizzard entries
-- findable by the ID players know; rows without them are found by name and key.
local function SearchID(id)
    if Public(id) and type(id) == "number" and id > 0 then return " " .. format("%d", id) end
    return ""
end
function Page.SearchText(name, key, spell, override, tooltip)
    local text = Public(name) and type(name) == "string" and name:lower() or ""
    if tooltip == spell or tooltip == override then tooltip = nil end
    return text .. " " .. (key or "") .. SearchID(spell) .. SearchID(override) .. SearchID(tooltip)
end
function Page.Query(box)
    local text = box:GetText() or ""
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

------------------------------------------------------------------ spell tiles
local Grid = {}
Grid.__index = Grid

local function PaintEdge(tile, lit)
    if lit then
        local r, g, b = Accent()
        tile.edge:SetColorTexture(r, g, b, 1)
    else
        tile.edge:SetColorTexture(0.12, 0.15, 0.20, 1)
    end
end
-- Marks what the popover belongs to: a spell tile, or a preview icon (which
-- brings its own Light).
local function Light(anchor, on)
    if not anchor then return end
    if anchor.edge then PaintEdge(anchor, on) elseif anchor.Light then anchor:Light(on) end
end
local function PopoverOn(anchor)
    local popover = Page.popover
    return popover ~= nil and popover:IsShown() and popover.anchor == anchor
end

-- Why a listed entry is not shown in play (runtime rows may say which rule
-- hides it: "cap", "ready" or "empty"); already translated.
function Page.HiddenText(hiddenBy)
    if hiddenBy == "cap" then return Tr("Beyond this bar's Maximum icons.") end
    if hiddenBy == "ready" then return Tr("Hidden while ready (Hide icons that are ready).") end
    if hiddenBy == "empty" then return Tr("None in your bags right now.") end
    return Tr("Hidden right now by a bar rule.")
end
local function TileEnter(self)
    if self.grid.dragTile then return end
    PaintEdge(self, true)
    if self.plus then
        ShowTip(self, Tr("Add spells"), format(Tr("Pick cooldowns, buffs, trinkets or custom IDs for %s."), Page.BarName(Page.selected)))
        return
    end
    local state = not self.known and Tr("Not learned right now.") or self.hidden and Page.HiddenText(self.hiddenBy) or nil
    ShowTip(self, Public(self.name) and self.name or self.key, Page.Identity(self.key) .. (state and ("\n" .. state) or ""),
        Tr("Click: spell options. Middle-click: remove. Drag: reorder, or drop on a bar in the preview."),
        Page.CustomLine(self.key))
end
local function TileLeave(self)
    PaintEdge(self, PopoverOn(self))
    HideTip(self)
end
local function TileDown(self, button)
    self.suppressClick = nil
    if button ~= "LeftButton" or self.plus or not self.key or P.Combat() then return end
    local x, y = Cursor()
    if not x then return end
    local grid = self.grid
    grid.pressTile, grid.pressX, grid.pressY = self, x, y
    grid.host:SetScript("OnUpdate", grid.onUpdate)
end
local function TileUp(self, button)
    if button ~= "LeftButton" then return end
    local grid = self.grid
    if grid.dragTile then
        self.suppressClick = true
        grid:Drop()
    else
        grid:CancelDrag()
    end
end
local function TileClick(self, button)
    if self.suppressClick then self.suppressClick = nil; return end
    if P.Combat() then return end
    if self.plus then Page.TogglePicker(self); return end
    if not self.key then return end
    if button == "MiddleButton" then
        Page.ClosePopups()
        Page.RemoveWithUndo(Page.selected, self.key, Public(self.name) and self.name or nil)
        return
    end
    Page.TogglePopover(self)
end

local function NewTile(grid, index, plus)
    local tile = CreateFrame("Button", nil, grid.host)
    tile:SetSize(TILE, TILE)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    tile.grid, tile.index, tile.plus = grid, index, plus
    tile.edge = tile:CreateTexture(nil, "BACKGROUND")
    tile.edge:SetAllPoints(tile)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    local r, g, b = Accent()
    if plus then
        tile.icon:SetColorTexture(0.05, 0.07, 0.11, 1)
        for i = 1, 2 do
            local line = tile:CreateTexture(nil, "OVERLAY")
            line:SetPoint("CENTER", tile, "CENTER", 0, 0)
            line:SetSize(i == 1 and 14 or 2, i == 1 and 2 or 14)
            line:SetColorTexture(r, g, b, 1)
        end
    else
        -- Marks: accent dot = own spell options; amber strip = hidden by a bar rule.
        tile.mark = tile:CreateTexture(nil, "OVERLAY")
        tile.mark:SetSize(7, 7)
        tile.mark:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -2, -2)
        tile.mark:SetColorTexture(r, g, b, 1)
        tile.ruleMark = tile:CreateTexture(nil, "OVERLAY")
        tile.ruleMark:SetHeight(3)
        tile.ruleMark:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 1, 1)
        tile.ruleMark:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
        tile.ruleMark:SetColorTexture(1, 0.62, 0.18, 0.95)
    end
    PaintEdge(tile, false)
    tile:SetScript("OnMouseDown", TileDown)
    tile:SetScript("OnMouseUp", TileUp)
    tile:SetScript("OnClick", TileClick)
    tile:SetScript("OnEnter", TileEnter)
    tile:SetScript("OnLeave", TileLeave)
    return tile
end

local function EntryFamily(entry, slot)
    local family = Plain(entry.family)
    if family == 1 or family == 2 then return family end
    return CDM.IsAuraKey(entry.key) and 2 or Page.Family(slot)
end

function Page.CreateTileGrid(_, parent, x, y, width)
    local grid = setmetatable({ tiles = {}, byKey = {}, count = 0, width = width }, Grid)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    host:SetSize(width, TILE)
    grid.host = host
    grid.plus = NewTile(grid, 0, true)
    grid.message = Label(host, "GameFontHighlightSmall", "", "muted")
    grid.message:SetPoint("LEFT", grid.plus, "RIGHT", 10, 0)
    grid.message:SetWidth(max(80, width - TILE - 20))
    if grid.message.SetWordWrap then grid.message:SetWordWrap(true) end
    local r, g, b = Accent()
    grid.marker = host:CreateTexture(nil, "OVERLAY")
    grid.marker:SetSize(2, TILE + 6)
    grid.marker:SetColorTexture(r, g, b, 1)
    grid.marker:Hide()
    grid.onUpdate = function() grid:Update() end
    -- A closed list ends its drag and closes what its tiles opened; the page
    -- itself hiding closes everything (Page.Deactivate).
    host:SetScript("OnHide", function()
        grid:CancelDrag()
        Page.CloseOrphans()
    end)
    return grid
end
-- The tile of an entry on the selected bar, and the entry after it in the
-- bar's list (nil when it is last). The preview reads both.
function Grid:Tile(key) return key and self.byKey[key] or nil end
function Grid:NextKey(key)
    local tile = self.byKey[key]
    local nextTile = tile and tile.index < self.count and self.tiles[tile.index + 1] or nil
    return nextTile and nextTile.key or nil
end

-- What the tiles depend on: bar, spec, lists, per-spell choices, Blizzard's
-- catalog, which bars are on and their types, and the bar's cap and ready
-- rule. A settings write that changes none of these (a slider tick of the
-- look or layout) asks the runtime for nothing and moves no tile.
local function BarsSignature()
    local sig = 0
    for i = 1, #SLOTS do
        local info = SLOTS[i]
        sig = sig * 2 + (Page.IsOn(info.key) and 1 or 0)
        if info.custom then sig = sig * 4 + (tonumber(P.Get(ID, KEYS[info.key].kind)) or 1) end
    end
    return sig
end
function Grid:Same(slot, blocked)
    local k = KEYS[slot]
    local generation = S.CooldownManagerGeneration
    local gen = generation and generation() or 0
    local spec = Page.Spec() or 0
    local lists, spells = P.Get(ID, "listsData"), P.Get(ID, "spellsData")
    local cap = k.maxIcons and P.Get(ID, k.maxIcons) or 0
    local hide = k.hideReady and P.Get(ID, k.hideReady) or false
    local sig, running, source = BarsSignature(), Page.Running(), S.CooldownManagerBarEntries
    local same = self.valid == true and self.mSlot == slot and self.mBlocked == blocked and self.mGen == gen
        and self.mSpec == spec and self.mLists == lists and self.mSpells == spells and self.mCap == cap
        and self.mHide == hide and self.mSig == sig and self.mRunning == running and self.mSource == source
    self.valid = true
    self.mSlot, self.mBlocked, self.mGen, self.mSpec, self.mLists, self.mSpells = slot, blocked, gen, spec, lists, spells
    self.mCap, self.mHide, self.mSig, self.mRunning, self.mSource = cap, hide, sig, running, source
    return same
end

-- Lays out the selected bar's entries; returns the grid height.
function Grid:Refresh()
    local slot = Page.selected
    local blocked = Page.EditorBlocked()
    if self:Same(slot, blocked) then
        -- Bar values shown as hints in the open popover may have changed.
        local popover = Page.popover
        if popover and popover:IsShown() then Page.PaintPopover() end
        return self.height
    end
    local entries = not blocked and Page.Entries(slot) or nil
    local spells = Page.SpellOverrides().e
    local popover = Page.popover
    local openKey = popover and popover:IsShown() and popover.slot == slot and popover.key or nil
    -- A popover opened from the preview stays on its preview icon.
    local fromGrid = openKey ~= nil and popover.anchor ~= nil and popover.anchor.grid == self
    local count, openTile, loading = 0, nil, false
    local byKey = self.byKey
    for key in pairs(byKey) do byKey[key] = nil end
    for i = 1, entries and #entries or 0 do
        local entry = entries[i]
        local key = EntryKey(entry)
        if key then
            count = count + 1
            local tile = self.tiles[count]
            if not tile then tile = NewTile(self, count, false); self.tiles[count] = tile end
            if byKey[key] == nil then byKey[key] = tile end
            tile.key, tile.name, tile.texture = key, entry.name, entry.texture
            -- An icon the client has not loaded yet: ask again next refresh.
            if Public(tile.texture) and tile.texture == nil then loading = true end
            tile.known, tile.hidden, tile.family = Plain(entry.known) ~= false, Plain(entry.hidden) == true, EntryFamily(entry, slot)
            -- Optional runtime fields: the rule that hides it, and the unit
            -- "Automatic" tracks its buff on.
            tile.hiddenBy, tile.unit = Plain(entry.hiddenBy), Plain(entry.unit)
            -- A cooldown that tracks a buff shows it on the icon (stack options).
            tile.aura = tile.family == 2 or Plain(entry.hasAura) == true
            SetIcon(tile.icon, tile.texture)
            tile.icon:SetDesaturated(not tile.known)
            tile:SetAlpha(tile.known and 1 or 0.55)
            tile.mark:SetShown(spells[tile.key] ~= nil)
            tile.ruleMark:SetShown(tile.hidden)
            if tile.key == openKey then openTile = tile end
            PaintEdge(tile, fromGrid and tile.key == openKey)
            tile:Show()
        end
    end
    for i = count + 1, #self.tiles do
        local tile = self.tiles[i]
        tile.key = nil
        tile:Hide()
    end
    self.count = count
    local perRow = max(1, floor((self.width + GAP) / (TILE + GAP)))
    for i = 1, count + 1 do
        local tile = i <= count and self.tiles[i] or self.plus
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", self.host, "TOPLEFT", ((i - 1) % perRow) * (TILE + GAP), -floor((i - 1) / perRow) * (TILE + GAP))
    end
    self.plus:SetShown(entries ~= nil)
    if blocked then SetRaw(self.message, blocked)
    elseif count == 0 then self.message:SetText(Tr("No spells yet. Click + to add some."))
    else self.message:SetText("") end
    self.message:SetShown(count == 0)
    if popover and popover:IsShown() then
        if openTile then
            popover.hasAura, popover.unit = openTile.aura, openTile.unit
            if fromGrid then Page.PlacePopup(popover, openTile) end
            Page.PaintPopover()
        else
            popover:Hide()
        end
    end
    local rows = floor(count / perRow) + 1
    local height = rows * (TILE + GAP) - GAP
    self.host:SetHeight(height)
    self.height = height
    if loading then self.valid = false end
    -- The preview marks its icons from these tiles.
    local ui = self.ui
    if ui and ui.PaintHitMarks then ui.PaintHitMarks() end
    return height
end

-- The dragged icon under the cursor, shared by the list and the preview.
function Page.ShowGhost(texture)
    local ghost = Page.ghost
    if not ghost then
        ghost = CreateFrame("Frame", nil, _G.UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetSize(TILE, TILE)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetAllPoints(ghost)
        ghost.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
        ghost:SetAlpha(0.8)
        Page.ghost = ghost
    end
    SetIcon(ghost.icon, texture)
    ghost:Show()
end
function Page.MoveGhost(x, y)
    local ghost = Page.ghost
    if not ghost then return end
    local uiScale = Scale(_G.UIParent)
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT", x / uiScale, y / uiScale)
end
function Page.HideGhost()
    if Page.ghost then Page.ghost:Hide() end
end
-- A drop onto another bar's chip moves the entry there; a drop on this bar
-- puts it before beforeKey (last without one). One history entry.
function Page.CommitDrop(key, family, name, slot, beforeKey)
    if slot then
        local ok, reason = Page.MoveEntry(key, slot, nil, family)
        if ok then Page.Note(format(Tr("Moved %s to %s."), name, Page.BarName(slot))) else Page.Fail(reason) end
        return ok
    end
    if beforeKey == key then return true end
    local ok, reason = Page.MoveEntry(key, Page.selected, beforeKey, family)
    if not ok then Page.Fail(reason) end
    return ok
end

-- Drag: 3 px threshold, OnUpdate only while the left button is held.
function Grid:Update()
    if P.Combat() then self:CancelDrag(); return end
    local x, y = Cursor()
    if not x then return end
    if not self.dragTile then
        local scale = Scale(self.host)
        local dx, dy = (x - self.pressX) / scale, (y - self.pressY) / scale
        if dx * dx + dy * dy < 9 then return end
        self:StartDrag()
    end
    Page.MoveGhost(x, y)
    self:Target(x)
end
function Grid:StartDrag()
    local tile = self.pressTile
    self.dragTile = tile
    Page.ClosePopups()
    Page.ShowGhost(tile.texture)
    tile:SetAlpha(0.3)
end
function Grid:Target(cursorX)
    self.dropTile, self.dropAfter, self.dropSlot = nil, nil, nil
    local chipSlot = Page.ChipUnderCursor and Page.ChipUnderCursor()
    if chipSlot and chipSlot ~= Page.selected then
        self.dropSlot = chipSlot
        self.marker:Hide()
        if Page.HighlightChip then Page.HighlightChip(chipSlot) end
        return
    end
    if Page.HighlightChip then Page.HighlightChip(nil) end
    for i = 1, self.count do
        local tile = self.tiles[i]
        if tile:IsMouseOver() then
            local left, width = tile:GetLeft(), tile:GetWidth()
            local after = type(left) == "number" and type(width) == "number"
                and cursorX / Scale(tile) > left + width / 2 or false
            self.dropTile, self.dropAfter = tile, after
            self.marker:ClearAllPoints()
            self.marker:SetPoint("CENTER", tile, after and "RIGHT" or "LEFT", after and GAP / 2 or -GAP / 2, 0)
            self.marker:Show()
            return
        end
    end
    if self.plus:IsMouseOver() then
        self.dropTile, self.dropAfter = self.plus, false
        self.marker:ClearAllPoints()
        self.marker:SetPoint("CENTER", self.plus, "LEFT", -GAP / 2, 0)
        self.marker:Show()
        return
    end
    self.marker:Hide()
end
function Grid:Drop()
    local tile, target, after, slot = self.dragTile, self.dropTile, self.dropAfter, self.dropSlot
    local key, family, name = tile.key, tile.family, Public(tile.name) and tile.name or tile.key
    self:CancelDrag()
    if slot then Page.CommitDrop(key, family, name, slot); return end
    if not target then return end
    local beforeKey
    if target ~= self.plus then
        if after then beforeKey = self:NextKey(target.key) else beforeKey = target.key end
    end
    Page.CommitDrop(key, family, name, nil, beforeKey)
end
function Grid:CancelDrag()
    self.host:SetScript("OnUpdate", nil)
    local tile = self.dragTile
    if tile then tile:SetAlpha(tile.known and 1 or 0.55) end
    local dragging = tile ~= nil
    self.pressTile, self.dragTile, self.dropTile, self.dropAfter, self.dropSlot = nil, nil, nil, nil, nil
    self.marker:Hide()
    if dragging then
        Page.HideGhost()
        if Page.HighlightChip then Page.HighlightChip(nil) end
    end
end

------------------------------------------------------------------ spell picker
local PICK_W, PICK_H = 340, 470
local picker

local function SortCatalog(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.known ~= b.known then return a.known end
    return a.sortName < b.sortName
end
local function Item(n, kind, text, key, texture, known, slot, family, spell, override, tooltip)
    local items = picker.items
    local item = items[n]
    if not item then item = {}; items[n] = item end
    item.kind, item.text, item.key, item.texture = kind, text, key, texture
    item.known, item.slot, item.family = known ~= false, slot, family
    item.search = kind == "entry" and Page.SearchText(text, key, spell, override, tooltip) or nil
    return item
end
-- Spell IDs of a catalog row, when the runtime provides them.
local function RowSpell(value)
    value = Plain(value)
    if type(value) == "number" and value > 0 then return value end
end
local function ResolveSpell(text)
    if text == "" then return nil end
    local spell = _G.C_Spell
    local id = tonumber(text)
    if not id and spell and spell.GetSpellIDForSpellIdentifier then
        id = spell.GetSpellIDForSpellIdentifier(text)
        if not Public(id) then id = nil end
    end
    if type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= floor(id) then return nil end
    local name = spell and spell.GetSpellName and spell.GetSpellName(id)
    if not Public(name) or type(name) ~= "string" then return nil end
    local texture = spell.GetSpellTexture and spell.GetSpellTexture(id)
    return id, name, Public(texture) and texture or nil
end
local function ResolveItem(text)
    local id = tonumber(text)
    if type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= floor(id) then return nil end
    local item = _G.C_Item
    if not item then return nil end
    local name = item.GetItemNameByID and item.GetItemNameByID(id)
    local texture = item.GetItemIconByID and item.GetItemIconByID(id)
    if not Public(name) then name = nil end
    if not Public(texture) then texture = nil end
    if name == nil and item.RequestLoadItemDataByID then item.RequestLoadItemDataByID(id) end
    if name == nil and texture == nil then return nil end
    return id, type(name) == "string" and name or format(Tr("Item %d"), id), texture
end

local function PickerRowEnter(self)
    self.hover:Show()
    local item = self.item
    if item and item.kind == "entry" then
        local first = not item.known and Tr("Not learned right now. You can add it anyway.") or nil
        local second = item.slot and item.slot ~= Page.selected and format(Tr("Picking it moves it from %s."), Page.BarName(item.slot)) or nil
        ShowTip(self, Public(item.text) and item.text or item.key, first, second)
    end
end
local function PickerRowLeave(self) self.hover:Hide(); HideTip(self) end
local function PickerRowClick(self)
    local item = self.item
    if not item or item.kind ~= "entry" or P.Combat() then return end
    Page.PickItem(item)
end
local function PickerRow(index)
    local row = picker.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, picker.content)
    row:SetSize(PICK_W - 40, 24)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    row.text = Label(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.text:SetWidth(PICK_W - 170)
    row.status = Label(row, "GameFontDisableSmall", "", "muted")
    row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.status:SetWidth(112)
    row.status:SetJustifyH("RIGHT")
    row:SetScript("OnClick", PickerRowClick)
    row:SetScript("OnEnter", PickerRowEnter)
    row:SetScript("OnLeave", PickerRowLeave)
    picker.rows[index] = row
    return row
end
local function PaintPickerRow(row, item)
    row.item = item
    local r, g, b = TextColor()
    if item.kind == "header" then
        r, g, b = Accent()
        row.icon:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.text:SetText(item.text)
        row.status:SetText("")
        row:SetAlpha(1)
    else
        row.icon:Show()
        SetIcon(row.icon, item.texture)
        row.icon:SetDesaturated(not item.known)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
        SetRaw(row.text, Public(item.text) and item.text or item.key)
        local status, alpha = "", 1
        if item.slot == Page.selected then status, alpha = Tr("On this bar"), 0.45
        elseif item.slot then status = format(Tr("On %s"), Page.BarName(item.slot))
        elseif picker.removed[item.key] then status = Tr("Removed")
        elseif not item.known then status = Tr("Not learned") end
        SetRaw(row.status, status)
        row:SetAlpha(item.known and alpha or min(alpha, 0.55))
    end
    row.text:SetTextColor(r, g, b)
end

function Page.FilterPicker()
    if not picker then return end
    local query = Page.Query(picker.search)
    local spec = Page.Spec()
    picker.removed = spec and Page.ListsView().hidden[spec] or EMPTY
    local items, count = picker.items, picker.count
    local any, section = false, nil
    for i = 1, count do
        local item = items[i]
        if item.kind == "header" then
            section = item
            item.match = false
        else
            item.match = query == "" or (item.search ~= nil and item.search:find(query, 1, true) ~= nil)
            if item.match and section then section.match = true; any = true end
        end
    end
    local shown = 0
    for i = 1, count do
        local item = items[i]
        if item.match then
            shown = shown + 1
            local row = PickerRow(shown)
            PaintPickerRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", picker.content, "TOPLEFT", 0, -(shown - 1) * 24)
            row:Show()
        end
    end
    for i = shown + 1, #picker.rows do picker.rows[i].item = nil; picker.rows[i]:Hide() end
    picker.shown = shown
    picker.content:SetHeight(max(1, shown * 24))
    picker.empty:SetText(any and "" or Tr("Nothing matches. Try a spell ID below."))
    picker.empty:SetShown(not any)
end

function Page.RebuildPicker()
    local slot = Page.selected
    local family = Page.Family(slot)
    SetRaw(picker.title, format(Tr("Add to %s"), Page.BarName(slot)))
    local n = 1
    Item(n, "header", Tr(family == 1 and "Blizzard cooldowns" or "Blizzard buffs"))
    local sorted, bySpell, equip = picker.sorted, picker.bySpell, picker.equip
    for i = #sorted, 1, -1 do sorted[i] = nil end
    for id in pairs(bySpell) do bySpell[id] = nil end
    equip[13], equip[14] = nil, nil
    local catalog = Page.Catalog(family) or EMPTY
    for i = 1, #catalog do
        local entry = catalog[i]
        local key = EntryKey(entry)
        if key and CDM.EntryKind(key) == "e" then
            -- Equipment slots belong to the trinket section below.
            equip[CDM.EntryID(key)] = entry
        elseif key then
            local record = picker.pool[i]
            if not record then record = {}; picker.pool[i] = record end
            record.entry, record.key, record.slot = entry, key, Plain(entry.slot)
            record.rank = record.slot == nil and 0 or record.slot == slot and 2 or 1
            record.known = Plain(entry.known) ~= false
            record.sortName = Public(entry.name) and type(entry.name) == "string" and entry.name:lower() or key
            record.spell, record.override = RowSpell(entry.spell), RowSpell(entry.override)
            record.tooltip = RowSpell(entry.tooltip)
            sorted[#sorted + 1] = record
        end
    end
    table.sort(sorted, SortCatalog)
    for i = 1, #sorted do
        local record = sorted[i]
        n = n + 1
        local item = Item(n, "entry", record.entry.name, record.key, record.entry.texture, record.known, record.slot,
            family, record.spell, record.override, record.tooltip)
        if record.spell and not bySpell[record.spell] then bySpell[record.spell] = item end
        if record.override and not bySpell[record.override] then bySpell[record.override] = item end
    end
    if family == 1 then
        n = n + 1
        Item(n, "header", Tr("Trinkets and items"))
        for trinket = 13, 14 do
            local key = "e" .. trinket
            local row = equip[trinket]
            local texture = type(_G.GetInventoryItemTexture) == "function" and _G.GetInventoryItemTexture("player", trinket) or nil
            if not Public(texture) or texture == nil then texture = row and Plain(row.texture) or nil end
            local itemID = type(_G.GetInventoryItemID) == "function" and _G.GetInventoryItemID("player", trinket) or nil
            local name = Public(itemID) and type(itemID) == "number" and _G.C_Item and _G.C_Item.GetItemNameByID
                and _G.C_Item.GetItemNameByID(itemID) or nil
            local label = format(Tr("Trinket slot %d"), trinket - 12)
            if Public(name) and type(name) == "string" then label = label .. ": " .. name end
            -- The runtime knows where the slot lives even without an explicit list.
            local home = row and Plain(row.slot) or Page.WhereIs(key)
            n = n + 1
            Item(n, "entry", label, key, texture, true, home, 1)
        end
    end
    picker.count = n
    picker.family = family
    picker.idTitle:SetText(Tr(family == 1 and "Custom spell or item ID" or "Custom aura ID"))
    picker.addA:SetText(Tr(family == 1 and "Add spell" or "Buff on me"))
    picker.addB:SetText(Tr(family == 1 and "Add item" or "Debuff on target"))
    Page.EchoCustom()
    Page.FilterPicker()
end

function Page.PickItem(item)
    if item.slot == Page.selected then return false end
    local name = Public(item.text) and item.text or item.key
    local from = item.slot
    local ok, reason = Page.AddEntry(Page.selected, item.key, item.family)
    if ok then
        item.slot = Page.selected
        local text = from and format(Tr("Moved %s from %s."), name, Page.BarName(from)) or format(Tr("Added %s."), name)
        SetRaw(picker.note, text)
        Page.Note(text)
    else
        picker.note:SetText(Tr(reason or "That did not work."))
    end
    Page.FilterPicker()
    return ok
end

function Page.EchoCustom()
    local text = (picker.idBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID, spellName, spellIcon = ResolveSpell(text)
    local itemID, itemName, itemIcon
    if picker.family == 1 then itemID, itemName, itemIcon = ResolveItem(text) end
    -- A spell Blizzard's Cooldown Manager already tracks is added as that
    -- entry, so it never shows twice.
    local blizzard = spellID and picker.bySpell[spellID] or nil
    picker.customSpell, picker.customItem, picker.customBlizzard = spellID, itemID, blizzard
    local r, g, b = MutedColor()
    if text == "" then
        picker.echo:SetText(Tr("Type an ID or a spell name."))
    elseif spellID or itemID then
        r, g, b = 0.35, 0.95, 0.45
        local parts = spellID and format(Tr("Spell %d"), spellID) .. ": " .. spellName or ""
        if blizzard then parts = parts .. " (" .. Tr("Blizzard's entry") .. ")" end
        if itemID then parts = parts .. (parts ~= "" and "  |  " or "") .. format(Tr("Item %d"), itemID) .. ": " .. itemName end
        SetRaw(picker.echo, parts)
    else
        r, g, b = 1, 0.35, 0.3
        picker.echo:SetText(Tr("No spell or item with this ID."))
    end
    picker.echo:SetTextColor(r, g, b)
    picker.echoIcon:SetTexture(spellIcon or itemIcon or QUESTION)
    picker.echoIcon:SetShown((spellID or itemID) ~= nil)
    picker.addA:SetEnabled(spellID ~= nil)
    picker.addB:SetEnabled(picker.family == 1 and itemID ~= nil or picker.family ~= 1 and spellID ~= nil)
end
local function AddCustom(prefix)
    if P.Combat() then return end
    local id = prefix == "i" and picker.customItem or picker.customSpell
    if not id then return end
    local blizzard = prefix ~= "i" and picker.customBlizzard or nil
    if blizzard then
        if blizzard.slot == Page.selected then
            picker.note:SetText(Tr("Blizzard's entry for this spell is already on this bar."))
        elseif Page.PickItem(blizzard) then
            picker.idBox:SetText("")
        end
        return
    end
    local key = prefix .. id
    local from = Page.WhereIs(key)
    local ok, reason = Page.AddEntry(Page.selected, key, (prefix == "a" or prefix == "d") and 2 or 1)
    if ok then
        local text = from and from ~= Page.selected and format(Tr("Moved %s from %s."), Page.Identity(key), Page.BarName(from))
            or format(Tr("Added %s."), Page.Identity(key))
        SetRaw(picker.note, text)
        Page.Note(text)
        picker.idBox:SetText("")
    else
        picker.note:SetText(Tr(reason or "That did not work."))
    end
end

local function EnsurePicker()
    if picker then return picker end
    picker = Page.NewPopup(PICK_W, PICK_H)
    Page.picker = picker
    picker.items, picker.rows, picker.sorted, picker.pool, picker.count = {}, {}, {}, {}, 0
    picker.bySpell, picker.equip = {}, {}
    picker.title = Label(picker, "GameFontNormal", "")
    picker.title:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -12)
    picker.title:SetWidth(PICK_W - 60)
    picker.close = Button(picker, "x", 22, 20, function() picker:Hide() end)
    picker.close:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -8, -8)
    picker.search = Page.SearchBox(picker, PICK_W - 28, Tr("Type a name or ID to filter"), Page.FilterPicker)
    picker.search:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -36)
    picker.scroll, picker.content = Page.ScrollArea(picker, PICK_W - 40)
    picker.scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -66)
    picker.scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -26, 132)
    picker.empty = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -72)
    picker.idTitle = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.idTitle:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 112)
    picker.idBox = Page.SearchBox(picker, 120, Tr("ID or name"), Page.EchoCustom)
    picker.idBox:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 16, 82)
    picker.addA = Button(picker, "", 90, 22, function() AddCustom(picker.family == 1 and "s" or "a") end)
    picker.addA:SetPoint("LEFT", picker.idBox, "RIGHT", 8, 0)
    picker.addB = Button(picker, "", 100, 22, function() AddCustom(picker.family == 1 and "i" or "d") end)
    picker.addB:SetPoint("LEFT", picker.addA, "RIGHT", 6, 0)
    picker.echoIcon = picker:CreateTexture(nil, "ARTWORK")
    picker.echoIcon:SetSize(16, 16)
    picker.echoIcon:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 56)
    picker.echoIcon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    picker.echo = Label(picker, "GameFontHighlightSmall", "")
    picker.echo:SetPoint("LEFT", picker.echoIcon, "RIGHT", 6, 0)
    picker.echo:SetWidth(PICK_W - 50)
    picker.note = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.note:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 16)
    picker.note:SetWidth(PICK_W - 28)
    picker.hint = Label(picker, "GameFontDisableSmall", Tr("Picks stay open so you can add several."), "muted")
    picker.hint:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 34)
    picker.OnClosed = function(self)
        self.search:ClearFocus()
        self.idBox:ClearFocus()
    end
    return picker
end

function Page.TogglePicker(anchor)
    if picker and picker:IsShown() and picker.anchor == anchor then picker:Hide(); return false end
    if P.Combat() or Page.EditorBlocked() then return false end
    EnsurePicker()
    Page.ClosePopups(picker)
    Page.PlacePopup(picker, anchor)
    picker.note:SetText("")
    picker.search:SetText("")
    picker.idBox:SetText("")
    if picker.scroll.SetVerticalScroll then picker.scroll:SetVerticalScroll(0) end
    Page.RebuildPicker()
    picker:Show()
    return true
end

------------------------------------------------------------------ sound picker
-- "None", the current value when no list below has it, Blizzard's Cooldown
-- Manager sounds by category, then the LibSharedMedia sounds. Items and rows
-- are pooled; a header shows while one of its rows matches the filter, and a
-- category name finds all of its sounds.
local SOUND_W, SOUND_H = 280, 400
local sounds

local function SoundRowClick(self)
    local item = self.item
    if not item or item.header or P.Combat() then return end
    local pick = sounds.onPick
    sounds:Hide()
    if pick then pick(item.value) end
end
local function SoundPlayClick(self)
    local item = self.row and self.row.item
    if item and not item.header then Page.PlaySound(item.value) end
end
local function SoundRowEnter(self) if self.item and not self.item.header then self.hover:Show() end end
local function SoundRowLeave(self) self.hover:Hide() end
local function SoundRow(index)
    local row = sounds.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, sounds.content)
    row:SetSize(SOUND_W - 40, 22)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.text = Label(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetWidth(SOUND_W - 100)
    row.play = Button(row, "Play", 44, 18, SoundPlayClick)
    row.play.row = row
    row.play:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnClick", SoundRowClick)
    row:SetScript("OnEnter", SoundRowEnter)
    row:SetScript("OnLeave", SoundRowLeave)
    sounds.rows[index] = row
    return row
end
local function PaintSoundRow(row, item)
    row.item = item
    SetRaw(row.text, item.text)
    local r, g, b
    if item.header == 2 then r, g, b = MutedColor()
    elseif item.header or item.value == sounds.current then r, g, b = Accent()
    else r, g, b = TextColor() end
    row.text:SetTextColor(r, g, b)
    row.play:SetShown(not item.header and item.value ~= "")
    row.hover:Hide()
end
function Page.FilterSounds()
    local query = Page.Query(sounds.search)
    local items = sounds.items
    -- Headers come before their rows: they are cleared before a row marks them.
    for i = 1, sounds.count do
        local item = items[i]
        if item.header then
            item.match = false
        else
            item.match = query == "" or item.search:find(query, 1, true) ~= nil
            if item.match then
                if item.section then item.section.match = true end
                if item.group then item.group.match = true end
            end
        end
    end
    local shown = 0
    for i = 1, sounds.count do
        local item = items[i]
        if item.match then
            shown = shown + 1
            local row = SoundRow(shown)
            PaintSoundRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", sounds.content, "TOPLEFT", 0, -(shown - 1) * 22)
            row:Show()
        end
    end
    for i = shown + 1, #sounds.rows do sounds.rows[i].item = nil; sounds.rows[i]:Hide() end
    sounds.content:SetHeight(max(1, shown * 22))
end
-- header: 1 section, 2 category. Rows are found by their category name too.
local function SoundItem(n, value, text, header, section, group)
    local item = sounds.items[n]
    if not item then item = {}; sounds.items[n] = item end
    item.value, item.text, item.header, item.section, item.group = value, text, header, section, group
    local search = type(text) == "string" and text:lower() or ""
    item.search = group and (search .. " " .. group.search) or search
    return item
end
local function KitListed(value, kits)
    local kit = kits and value:match("^kit:(%d+)$")
    return kit ~= nil and kits.names[tonumber(kit)] ~= nil
end
-- Blizzard's Cooldown Manager sounds, one header per category.
local function AddKitSounds(n, kits)
    local groups = kits and kits.groups or EMPTY
    if #groups == 0 then return n end
    n = n + 1
    local section = SoundItem(n, nil, Tr("Blizzard Cooldown Manager"), 1)
    for i = 1, #groups do
        local group = groups[i]
        n = n + 1
        local header = SoundItem(n, nil, group.title, 2, section)
        for j = 1, #group do
            n = n + 1
            SoundItem(n, group[j].value, group[j].text, nil, section, header)
        end
    end
    return n
end
local function AddMediaSounds(n)
    local lsm = Media()
    local names = lsm and lsm.List and lsm:List("sound") or EMPTY
    local section
    for i = 1, #names do
        local name = names[i]
        if type(name) == "string" and name ~= "" and #name <= 116 then
            if not section then n = n + 1; section = SoundItem(n, nil, Tr("Shared media"), 1) end
            n = n + 1
            SoundItem(n, "lsm:" .. name, name, nil, section)
        end
    end
    return n
end
local function EnsureSounds()
    if sounds then return sounds end
    sounds = Page.NewPopup(SOUND_W, SOUND_H)
    Page.soundPicker = sounds
    sounds.items, sounds.rows, sounds.count = {}, {}, 0
    sounds.title = Label(sounds, "GameFontNormal", Tr("Choose a sound"))
    sounds.title:SetPoint("TOPLEFT", sounds, "TOPLEFT", 12, -12)
    sounds.close = Button(sounds, "x", 22, 20, function() sounds:Hide() end)
    sounds.close:SetPoint("TOPRIGHT", sounds, "TOPRIGHT", -8, -8)
    sounds.search = Page.SearchBox(sounds, SOUND_W - 28, Tr("Filter sounds"), Page.FilterSounds)
    sounds.search:SetPoint("TOPLEFT", sounds, "TOPLEFT", 14, -36)
    sounds.scroll, sounds.content = Page.ScrollArea(sounds, SOUND_W - 40)
    sounds.scroll:SetPoint("TOPLEFT", sounds, "TOPLEFT", 12, -66)
    sounds.scroll:SetPoint("BOTTOMRIGHT", sounds, "BOTTOMRIGHT", -26, 12)
    sounds.OnClosed = function(self) self.search:ClearFocus(); self.onPick = nil end
    return sounds
end
function Page.OpenSoundPicker(anchor, current, onPick)
    if P.Combat() then return false end
    if sounds and sounds:IsShown() and sounds.anchor == anchor then sounds:Hide(); return false end
    EnsureSounds()
    current = type(current) == "string" and current or ""
    local kits = Page.BlizzardSounds()
    local n = 1
    SoundItem(n, "", Tr("None"))
    if current ~= "" and not current:find("^lsm:") and not KitListed(current, kits) then
        n = n + 1
        SoundItem(n, current, Page.SoundLabel(current))
    end
    n = AddMediaSounds(AddKitSounds(n, kits))
    sounds.count, sounds.current, sounds.onPick = n, current, onPick
    Page.ClosePopups(Page.popover)
    Page.PlacePopup(sounds, anchor)
    if Page.popover and sounds.SetFrameLevel then sounds:SetFrameLevel((Page.popover:GetFrameLevel() or 0) + 20) end
    sounds.search:SetText("")
    if sounds.scroll.SetVerticalScroll then sounds.scroll:SetVerticalScroll(0) end
    Page.FilterSounds()
    sounds:Show()
    return true
end

------------------------------------------------------------------ per-spell popover
-- Options of one entry, limited to its family and to what the runtime reads
-- for it. A missing value means "follow the bar": customised rows get the
-- accent label and a reset button, which sits in its own column right of
-- every control. Glow style and color style every glow of the entry (spell
-- alert, ready, buff while active and stack glows). Stack rows (0 = off)
-- serve buffs and cooldowns that show their buff; "Color stacks from" also
-- holds the stack color (its swatch opens a color list, reset clears both).
-- Every row explains itself on its label (help), without allocating.
local POP_W, POP_MAX = 360, 520
-- Label column and the x where every row's control starts.
local LABEL_W, POP_X = 150, 154
Page.POP_X = POP_X
local SWATCHES = { "ffd200", "ffffff", "ff4d4d", "4dff73", "4db8ff", "c78cff", "4dffff", "ff9933" }
local SWATCH_NAMES = { "Gold", "White", "Red", "Green", "Blue", "Purple", "Cyan", "Orange" }
local SWATCH, SWATCH_STEP, STACK_SWATCH = 13, 14, 18
-- The stack color of an entry that has none.
local STACK_COLOR = CDM.SPELL_DEFAULTS and CDM.SPELL_DEFAULTS.stackColor or "ff5a3c"
local SHOW_HIDE = { { 0, "Bar setting" }, { 2, "Show" }, { 3, "Hide" } }
local FROM_BOOL = { [true] = 2, [false] = 3 }
-- bar: the bar setting a missing value follows. fromBar: that setting's
-- value as a choice of the row. fallback: the hint when no bar setting
-- stands behind the row. switch: On or nothing (no bar setting to follow).
-- blizzardOnly: Blizzard's entries only (custom auras name their unit).
local ALL_FIELDS = {
    { key = "procGlow", label = "Spell alert glow", kind = "bool", cd = true, spellOnly = true, bar = "procGlow",
      help = "Glow while the game highlights this spell (spell alert)." },
    { key = "readyGlow", label = "Glow when ready", kind = "bool", cd = true, bar = "readyGlow",
      help = "Glow while the spell is ready. \"Ready glows only in combat\" in Frame Basics limits it to combat." },
    { key = "auraGlow", label = "Glow while active", kind = "bool", aura = true, bar = "auraGlow",
      help = "Glow while the buff is active." },
    { key = "glowStyle", label = "Glow style", kind = "choice", cd = true, aura = true,
      values = { { 0, "Bar setting" }, { 1, "Blizzard alert" }, { 2, "Marching ants" }, { 3, "Pulse" }, { 4, "Border" } },
      help = "Style of every glow of this spell: spell alert, ready, active buff and stack glows." },
    { key = "glowColor", label = "Glow color", kind = "color", cd = true, aura = true,
      help = "Tints every glow of this spell. Click the chosen color again to follow the bar." },
    { key = "desat", label = "Desaturate on cooldown", kind = "choice", cd = true,
      values = { { 0, "Bar setting" }, { 2, "Never" }, { 3, "Always" } },
      help = "Grey out the icon while the spell is on cooldown." },
    { key = "hideReady", label = "Hide when ready", kind = "bool", cd = true, bar = "hideReady",
      help = "Show the icon only while the spell is on cooldown." },
    { key = "readyAlpha", label = "Opacity when ready", kind = "number", cd = true, bar = "readyAlpha", step = 1, max = 100,
      help = "Icon opacity while the spell is ready. Shift steps by 5, Ctrl by 10." },
    { key = "cdAlpha", label = "Opacity on cooldown", kind = "number", cd = true, bar = "cdAlpha", step = 1, max = 100,
      help = "Icon opacity while the spell is on cooldown. Shift steps by 5, Ctrl by 10." },
    { key = "showAura", label = "Show active buff duration", kind = "bool", cd = true, spellOnly = true, bar = "showAura",
      help = "While the buff of this spell lasts, the icon shows its duration and stacks instead of the cooldown." },
    { key = "showMissing", label = "Show dimmed when missing", kind = "bool", aura = true, bar = "showMissing",
      help = "Keep the icon in its place, dimmed, while the buff is missing." },
    { key = "auraUnit", label = "Track on", kind = "choice", stack = true, blizzardOnly = true,
      values = { { 0, "Automatic" }, { 2, "Me" }, { 3, "Target" }, { 4, "Both" } },
      help = "Where the buff or debuff is looked for. Automatic: harmful spells on your target, all others on you." },
    { key = "stackGlow", label = "Glow at stacks", kind = "number", stack = true, off = true, step = 1, max = 99,
      help = "Glow while the buff has at least this many stacks." },
    { key = "stackColorAt", label = "Color stacks from", kind = "number", stack = true, off = true, step = 1, max = 99,
      color = "stackColor", help = "From this many stacks the number shows in the color on the right." },
    { key = "swipe", label = "Swipe", kind = "choice", cd = true, aura = true,
      values = { { 0, "Normal" }, { 2, "Reversed" }, { 3, "Hidden" } },
      help = "The dark sweep over the icon while it counts down." },
    { key = "timeText", label = "Countdown", auraLabel = "Seconds", kind = "choice", cd = true, aura = true,
      bar = "cdText", fromBar = FROM_BOOL, values = SHOW_HIDE,
      help = "Show or hide the countdown numbers of this spell. Bar setting follows the bar's Text section." },
    { key = "stackText", label = "Charges", auraLabel = "Stacks", kind = "choice", cd = true, aura = true,
      bar = "stackText", fromBar = FROM_BOOL, values = SHOW_HIDE,
      help = "Show or hide the charges, stacks or item count of this spell." },
    { key = "textTop", label = "Text on top", kind = "choice", cd = true, aura = true, bar = "textTop",
      fromBar = { 2, 3 }, values = { { 0, "Bar setting" }, { 2, "Stacks" }, { 3, "Countdown" } },
      help = "Which number is drawn on top when both show." },
    { key = "threshold", label = "Warn below (seconds)", kind = "number", cd = true, aura = true, step = 1, max = 10,
      fallback = "All bars",
      help = "The countdown turns to the warning color below this many seconds. All bars: the Text section's setting." },
    { key = "sound", label = "Sound when ready", auraLabel = "Sound when gained", kind = "sound", cd = true, aura = true,
      help = "Plays when the spell becomes ready (a buff: when you gain it)." },
    { key = "lossSound", label = "Sound when lost", kind = "sound", aura = true, help = "Plays when the buff ends." },
    { key = "tts", label = "Say the name when ready", kind = "bool", cd = true, switch = true,
      help = "Your computer says the spell's name when it becomes ready." },
    -- A buff shows the game's icon while active; its own icon only while missing.
    { key = "icon", label = "Icon file ID (Enter)", auraLabel = "Icon when missing (Enter)", kind = "icon", cd = true,
      aura = true, help = "Type a texture file ID and press Enter to show another icon. Empty follows the game." },
}
-- Rows exist for the fields the catalog stores.
local FIELDS = {}
for _, field in ipairs(ALL_FIELDS) do
    if CDM.SPELL_FIELDS[field.key] then FIELDS[#FIELDS + 1] = field end
end
Page.FIELDS = FIELDS
local function SwatchItem(value, text, hex)
    local r, g, b = P.RGB(hex)
    return { value = value, text = text, swatchColor = { r, g, b, 1 } }
end
-- Stack colors: "" is the default color (the field is cleared).
local COLOR_MENU = { SwatchItem("", "Default", STACK_COLOR) }
for i, hex in ipairs(SWATCHES) do COLOR_MENU[i + 1] = SwatchItem(hex, SWATCH_NAMES[i], hex) end
Page.COLOR_MENU = COLOR_MENU
for _, field in ipairs(FIELDS) do
    if field.values then
        field.menu = {}
        for i, pair in ipairs(field.values) do field.menu[i] = { value = pair[1], text = pair[2] } end
    end
    if field.color then field.clears = { field.key, field.color } end
end
local pop

-- aura: the entry is a buff, or a cooldown that shows the buff it tracks.
local function Applies(field, family, kind, aura)
    if field.blizzardOnly and kind ~= "b" then return false end
    if field.stack then return family == 2 or aura == true end
    if family == 2 then return field.aura == true end
    if not field.cd then return false end
    return not (field.spellOnly and (kind == "i" or kind == "e"))
end
Page.FieldApplies = Applies
local function BarValue(field)
    if field.key == "threshold" then return P.Get(ID, "thresholdSeconds") end
    local key = field.bar and KEYS[pop.slot] and KEYS[pop.slot][field.bar]
    if key then return P.Get(ID, key) end
end

-- "Own options: ..." for tooltips, built once per entry and stored string.
local customLines, customText = {}, nil
function Page.CustomLine(key)
    local text = P.Get(ID, "spellsData")
    if customText ~= text then
        for entry in pairs(customLines) do customLines[entry] = nil end
        customText = text
    end
    local line = customLines[key]
    if line == nil then
        local fields = Page.SpellOverrides().e[key]
        line = false
        if fields then
            local names = {}
            for i = 1, #FIELDS do
                local field = FIELDS[i]
                if fields[field.key] ~= nil or (field.color and fields[field.color] ~= nil) then names[#names + 1] = Tr(field.label) end
            end
            if #names > 0 then line = Tr("Own options") .. ": " .. table.concat(names, ", ") end
        end
        customLines[key] = line
    end
    return line or nil
end
-- A cooldown shows its buff, and so its stacks, only while "Show active
-- buff duration" applies to it; its stack rows are dimmed otherwise.
local function StacksShown(fields)
    if pop.family == 2 then return true end
    local value = fields and fields.showAura
    if value == nil then
        local key = KEYS[pop.slot] and KEYS[pop.slot].showAura
        value = key and P.Get(ID, key)
    end
    return value == true
end
local function SetField(field, value)
    local ok, reason = Page.SetSpellField(pop.key, field.key, value)
    if not ok then Page.Fail(reason) end
end
local function ResetClick(self)
    local field = self.row.field
    if not field.clears then SetField(field, nil); return end
    local ok, reason = Page.ClearSpellFields(pop.key, field.clears)
    if not ok then Page.Fail(reason) end
end
-- Three states follow, force on or force off; a switch is On or nothing.
local function BoolClick(self)
    local field = self.row.field
    if field.switch then SetField(field, self.value == true or nil); return end
    if Page.SpellField(pop.key, field.key) == self.value then SetField(field, nil) else SetField(field, self.value) end
end
local function ChoiceClick(self)
    local field = self.row.field
    local current = Page.SpellField(pop.key, field.key) or 0
    local function Pick(value)
        value = tonumber(value) or 0
        SetField(field, value ~= 0 and value or nil)
    end
    if W.OpenDropdown then
        Page.dropdownOpen = true
        W.OpenDropdown(self, field.menu, current, Pick)
        return
    end
    -- Without Menu2's list, step through the choices.
    local menu, index = field.menu, 1
    for i = 1, #menu do if menu[i].value == current then index = i end end
    Pick(menu[index % #menu + 1].value)
end
-- Fields with "off" start at 0 and clear themselves when stepped back to it.
local function StepClick(self)
    local field = self.row.field
    local current = Page.SpellField(pop.key, field.key)
    if current == nil then current = field.off and 0 or tonumber(BarValue(field)) or 0 end
    local multiplier = IsControlKeyDown and IsControlKeyDown() and 10
        or IsShiftKeyDown and IsShiftKeyDown() and 5 or 1
    local value = max(0, min(field.max, current + self.delta * field.step * multiplier))
    value = floor(value / field.step + 0.5) * field.step
    SetField(field, not (field.off and value == 0) and value or nil)
end
local function SwatchClick(self)
    local field = self.row.field
    if Page.SpellField(pop.key, field.key) == self.hex then SetField(field, nil) else SetField(field, self.hex) end
end
local function ColorClick(self)
    local name = self.row.field.color
    local current = Page.SpellField(pop.key, name) or ""
    local function Pick(value)
        local ok, reason = Page.SetSpellField(pop.key, name, value ~= "" and value or nil)
        if not ok then Page.Fail(reason) end
    end
    if W.OpenDropdown then
        Page.dropdownOpen = true
        W.OpenDropdown(self, COLOR_MENU, current, Pick)
        return
    end
    -- Without Menu2's list, step through the colors.
    local index = 1
    for i = 1, #COLOR_MENU do if COLOR_MENU[i].value == current then index = i end end
    Pick(COLOR_MENU[index % #COLOR_MENU + 1].value)
end
local function ColorEnter(self)
    ShowTip(self, Tr("Stack color"), Tr("Stacks show in this color from the number on the left."))
end
local function SoundClick(self)
    local field = self.row.field
    Page.OpenSoundPicker(self, Page.SpellField(pop.key, field.key) or "", function(value)
        SetField(field, value ~= "" and value or nil)
    end)
end
local function PlayClick(self) Page.PlaySound(Page.SpellField(pop.key, self.row.field.key)) end
local function IconCommit(self)
    local text = (self:GetText() or ""):gsub("%s", "")
    local id = tonumber(text)
    self:ClearFocus()
    if text == "" then SetField(self.row.field, nil)
    elseif id and id >= 1 and id < 2147483648 and id == floor(id) then SetField(self.row.field, id)
    else Page.Fail("Enter a texture file ID."); Page.PaintPopover() end
end

local function NewSwatch(row, size, onClick)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(size, size)
    swatch.edge = swatch:CreateTexture(nil, "BACKGROUND")
    swatch.edge:SetAllPoints(swatch)
    swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
    swatch.fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
    swatch.fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    swatch.row = row
    swatch:SetScript("OnClick", onClick)
    return swatch
end
local function NumberControls(row, field, x)
    row.minus = Button(row, "-", 22, 20, StepClick)
    row.minus.row, row.minus.delta = row, -1
    row.minus:SetPoint("LEFT", row, "LEFT", x, 0)
    row.value = Label(row, "GameFontHighlightSmall", "")
    row.value:SetWidth(36)
    row.value:SetJustifyH("CENTER")
    row.value:SetPoint("LEFT", row.minus, "RIGHT", 2, 0)
    row.plus = Button(row, "+", 22, 20, StepClick)
    row.plus.row, row.plus.delta = row, 1
    row.plus:SetPoint("LEFT", row.value, "RIGHT", 2, 0)
    if field.color then
        row.swatch = NewSwatch(row, STACK_SWATCH, ColorClick)
        row.swatch:SetPoint("LEFT", row.plus, "RIGHT", 8, 0)
        row.swatch:SetScript("OnEnter", ColorEnter)
        row.swatch:SetScript("OnLeave", HideTip)
    elseif not field.off then
        -- "Bar" (or the field's fallback) marks a value that follows the bar.
        row.hint = Label(row, "GameFontDisableSmall", "", "muted")
        row.hint:SetPoint("LEFT", row.plus, "RIGHT", 6, 0)
        row.hint:SetWidth(60)
    end
end

-- The label explains its row; a dimmed stack row also says why.
local STACK_DIM = "Needs \"Show active buff duration\": this icon shows the buff and its stacks only then."
local function LabelEnter(self)
    local row = self.row
    ShowTip(self, row.label:GetText(), Tr(row.field.help), row.dimmed and Tr(STACK_DIM) or nil)
end
local function Row(field)
    local row = pop.rows[field.key]
    if row then return row end
    row = CreateFrame("Frame", nil, pop.content)
    row:SetSize(POP_W - 40, 24)
    row.field = field
    row.label = Label(row, "GameFontHighlightSmall", "")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(LABEL_W)
    row.tip = CreateFrame("Frame", nil, row)
    row.tip:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.tip:SetSize(LABEL_W, 20)
    row.tip:EnableMouse(true)
    row.tip.row = row
    row.tip:SetScript("OnEnter", LabelEnter)
    row.tip:SetScript("OnLeave", HideTip)
    row.reset = Button(row, "Reset", 44, 20, ResetClick)
    row.reset.row = row
    row.reset:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local x, kind = POP_X, field.kind
    if kind == "bool" then
        row.on = Button(row, "On", 38, 20, BoolClick)
        row.on.row, row.on.value = row, true
        row.on:SetPoint("LEFT", row, "LEFT", x, 0)
        row.off = Button(row, "Off", 38, 20, BoolClick)
        row.off.row, row.off.value = row, false
        row.off:SetPoint("LEFT", row.on, "RIGHT", 4, 0)
        row.hint = Label(row, "GameFontDisableSmall", "", "muted")
        row.hint:SetPoint("LEFT", row.off, "RIGHT", 6, 0)
        row.hint:SetWidth(60)
    elseif kind == "choice" or kind == "sound" then
        row.choice = Button(row, "", kind == "sound" and 68 or 108, 20, kind == "sound" and SoundClick or ChoiceClick)
        row.choice.row = row
        row.choice:SetPoint("LEFT", row, "LEFT", x, 0)
        if kind == "sound" then
            row.play = Button(row, "Play", 38, 20, PlayClick)
            row.play.row = row
            row.play:SetPoint("LEFT", row.choice, "RIGHT", 2, 0)
        end
    elseif kind == "number" then
        NumberControls(row, field, x)
    elseif kind == "color" then
        row.swatches = {}
        for i, hex in ipairs(SWATCHES) do
            local swatch = NewSwatch(row, SWATCH, SwatchClick)
            swatch:SetPoint("LEFT", row, "LEFT", x + (i - 1) * SWATCH_STEP, 0)
            local r, g, b = P.RGB(hex)
            swatch.fill:SetColorTexture(r, g, b, 1)
            swatch.hex = hex
            row.swatches[i] = swatch
        end
    elseif kind == "icon" then
        local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        edit:SetSize(80, 20)
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)
        edit:SetMaxLetters(10)
        if T.SkinEditBox then T.SkinEditBox(edit) end
        edit.row = row
        edit:SetPoint("LEFT", row, "LEFT", x + 4, 0)
        edit:SetScript("OnEnterPressed", IconCommit)
        edit:SetScript("OnEscapePressed", ClearFocus)
        row.edit = edit
        row.preview = row:CreateTexture(nil, "ARTWORK")
        row.preview:SetSize(20, 20)
        row.preview:SetPoint("LEFT", edit, "RIGHT", 8, 0)
        row.preview:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    end
    pop.rows[field.key] = row
    return row
end

local function PaintNumber(row, field, value, companion)
    local shown = value
    if shown == nil then shown = field.off and 0 or tonumber(BarValue(field)) or 0 end
    SetRaw(row.value, field.off and shown == 0 and Tr("Off") or tostring(shown))
    row.value:SetAlpha(value ~= nil and 1 or 0.6)
    if row.hint then row.hint:SetText(value ~= nil and "" or Tr(field.fallback or "Bar")) end
    local swatch = row.swatch
    if swatch then
        local r, g, b = P.RGB(companion or STACK_COLOR)
        swatch.fill:SetColorTexture(r, g, b, 1)
        if companion then r, g, b = Accent() else r, g, b = 0, 0, 0 end
        swatch.edge:SetColorTexture(r, g, b, companion and 1 or 0.8)
        swatch:SetAlpha(shown > 0 and 1 or 0.5)
    end
end
local function PaintRow(row, fields)
    local field = row.field
    local value = fields and fields[field.key]
    local companion = field.color and fields and fields[field.color] or nil
    local custom = value ~= nil or companion ~= nil
    row.label:SetText(Tr(pop.family == 2 and field.auraLabel or field.label))
    local r, g, b
    if custom then r, g, b = Accent() else r, g, b = TextColor() end
    row.label:SetTextColor(r, g, b)
    row.reset:SetShown(custom)
    -- Stack rows of a cooldown whose buff is not shown stay editable, dimmed.
    row.dimmed = field.stack == true and not StacksShown(fields)
    row:SetAlpha(row.dimmed and 0.45 or 1)
    local kind = field.kind
    if kind == "bool" then
        if field.switch then
            row.on:SetActive(value == true)
            row.off:SetActive(value ~= true)
            row.hint:SetText("")
        else
            row.on:SetActive(value == true)
            row.off:SetActive(value == false)
            local bar = BarValue(field)
            SetRaw(row.hint, custom and "" or (Tr("Bar") .. ": " .. Tr(bar == true and "On" or "Off")))
        end
    elseif kind == "choice" then
        local menu, shown = field.menu, value
        -- A row that follows the bar names the bar's current choice.
        if shown == nil and field.fromBar then shown = field.fromBar[BarValue(field)] end
        local text = menu[1].text
        for i = 1, #menu do if menu[i].value == (shown or 0) then text = menu[i].text end end
        if value == nil and shown ~= nil then
            ButtonText(row.choice, Tr("Bar") .. ": " .. Tr(text))
        elseif value == nil and field.key == "auraUnit" and (pop.unit == "player" or pop.unit == "target") then
            -- What Automatic picked, when the runtime says so.
            ButtonText(row.choice, Tr(pop.unit == "target" and "Automatic: target" or "Automatic: you"))
        else
            row.choice:SetText(Tr(text))
        end
    elseif kind == "number" then
        PaintNumber(row, field, value, companion)
    elseif kind == "color" then
        local ar, ag, ab = Accent()
        for i = 1, #row.swatches do
            local swatch = row.swatches[i]
            if swatch.hex == value then swatch.edge:SetColorTexture(ar, ag, ab, 1)
            else swatch.edge:SetColorTexture(0, 0, 0, 0.8) end
        end
    elseif kind == "sound" then
        ButtonText(row.choice, custom and Page.SoundLabel(value) or Tr("None"))
        row.play:SetEnabled(custom)
    elseif kind == "icon" then
        if not (row.edit.HasFocus and row.edit:HasFocus()) then row.edit:SetText(custom and tostring(value) or "") end
        if value then row.preview:SetTexture(value) else SetIcon(row.preview, pop.texture) end
    end
end

local function RemoveClick()
    local key, slot, name = pop.key, pop.slot, Public(pop.entryName) and pop.entryName or nil
    pop:Hide()
    Page.RemoveWithUndo(slot, key, name)
end
local function MoveClick(self)
    local values, n = pop.moveValues, 0
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if slot ~= pop.slot and Page.IsOn(slot) then
            n = n + 1
            local item = values[n] or {}
            values[n] = item
            item.value, item.text, item.translate = slot, Page.BarName(slot), false
            item.disabled = Page.Family(slot) ~= pop.family
            item.tooltip = item.disabled and Tr(Page.FamilyError(pop.family)) or nil
        end
    end
    for i = n + 1, #values do values[i] = nil end
    if n == 0 then Page.Fail("Turn on another bar first."); return end
    if not W.OpenDropdown then return end
    Page.dropdownOpen = true
    W.OpenDropdown(self, values, nil, function(slot)
        local key, family = pop.key, pop.family
        local name = Public(pop.entryName) and pop.entryName or key
        pop:Hide()
        local ok, reason = Page.MoveEntry(key, slot, nil, family)
        if ok then Page.Note(format(Tr("Moved %s to %s."), name, Page.BarName(slot))) else Page.Fail(reason) end
    end)
end
local function ResetSpellClick()
    local ok, reason = Page.ResetSpell(pop.key)
    if not ok then Page.Fail(reason) end
end
local function CopyClick()
    local ok, result = Page.CopyToSpecs(pop.slot, pop.key)
    if not ok then Page.Fail(result); return end
    Page.Note(result == 0 and Tr("Every specialization already has it.")
        or format(Tr("Copied to %d specializations."), result))
end

local function EnsurePopover()
    if pop then return pop end
    pop = Page.NewPopup(POP_W, 300)
    Page.popover = pop
    pop.rows, pop.moveValues = {}, {}
    pop.icon = pop:CreateTexture(nil, "ARTWORK")
    pop.icon:SetSize(34, 34)
    pop.icon:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -12)
    pop.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    pop.title = Label(pop, "GameFontNormal", "")
    pop.title:SetPoint("TOPLEFT", pop.icon, "TOPRIGHT", 8, -2)
    pop.title:SetWidth(POP_W - 90)
    pop.sub = Label(pop, "GameFontDisableSmall", "", "muted")
    pop.sub:SetPoint("TOPLEFT", pop.title, "BOTTOMLEFT", 0, -4)
    pop.sub:SetWidth(POP_W - 90)
    pop.close = Button(pop, "x", 22, 20, function() pop:Hide() end)
    pop.close:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -8, -8)
    -- Header actions fit their captions (longer in other languages) and
    -- wrap onto a second line when they do not fit side by side.
    pop.actions = {
        Button(pop, "Remove from bar", 100, 22, RemoveClick), Button(pop, "Move to bar", 100, 22, MoveClick),
        Button(pop, "Reset this spell", 102, 22, ResetSpellClick), Button(pop, "Copy to all specs", 140, 22, CopyClick),
    }
    pop.remove, pop.move, pop.reset, pop.copy = pop.actions[1], pop.actions[2], pop.actions[3], pop.actions[4]
    for i = 1, #pop.actions do
        local width = T.MeasureButtonWidth and T.MeasureButtonWidth(pop.actions[i], 60, POP_W - 24)
        if type(width) == "number" and width > 0 then pop.actions[i]:SetWidth(width) end
    end
    pop.scope = Label(pop, "GameFontDisableSmall", Tr("These choices apply to this spell on every bar and specialization."),
        "muted")
    pop.scope:SetWidth(POP_W - 24)
    pop.scroll, pop.content = Page.ScrollArea(pop, POP_W - 40)
    pop.OnClosed = function(self)
        for _, row in pairs(self.rows) do if row.edit then row.edit:ClearFocus() end end
        Light(self.anchor, false)
    end
    return pop
end
-- Places the header actions (Copy only for the player's own entries) and
-- returns where the rows start; moves nothing when the set did not change.
local function PlaceActions(copy)
    if pop.placedCopy == copy then return pop.top end
    pop.placedCopy = copy
    pop.copy:SetShown(copy)
    local x, line = 12, 0
    for i = 1, copy and 4 or 3 do
        local button = pop.actions[i]
        local width = tonumber((button:GetWidth())) or 100
        if x > 12 and x + width > POP_W - 12 then x, line = 12, line + 1 end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", pop, "TOPLEFT", x, -54 - line * 26)
        x = x + width + 4
    end
    local y = 54 + (line + 1) * 26
    pop.scope:ClearAllPoints()
    pop.scope:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -y)
    pop.top = y + 20
    pop.scroll:ClearAllPoints()
    pop.scroll:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -pop.top)
    pop.scroll:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -26, 10)
    return pop.top
end

function Page.PaintPopover()
    if not pop then return end
    local fields = Page.SpellOverrides().e[pop.key]
    local kind = CDM.EntryKind(pop.key)
    SetIcon(pop.icon, pop.texture)
    SetRaw(pop.title, Public(pop.entryName) and pop.entryName or pop.key)
    SetRaw(pop.sub, Page.BarName(pop.slot) .. "  -  " .. Page.Identity(pop.key))
    pop.reset:SetEnabled(fields ~= nil)
    local top = PlaceActions(kind ~= "b")
    local y = 0
    for i = 1, #FIELDS do
        local field = FIELDS[i]
        local row = pop.rows[field.key]
        if Applies(field, pop.family, kind, pop.hasAura) then
            row = Row(field)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", pop.content, "TOPLEFT", 0, -y)
            PaintRow(row, fields)
            row:Show()
            y = y + 26
        elseif row then
            row:Hide()
        end
    end
    pop.content:SetHeight(max(1, y))
    pop:SetHeight(min(POP_MAX, top + y + 12))
end

-- Opens the entry of a spell tile, anchored under the tile or under anchor
-- (its icon in the preview). The same spell clicked there again closes it.
function Page.TogglePopover(tile, anchor)
    anchor = anchor or tile
    if pop and pop:IsShown() and pop.key == tile.key and pop.slot == Page.selected and pop.anchor == anchor then
        pop:Hide()
        return false
    end
    if P.Combat() or not tile.key then return false end
    EnsurePopover()
    Page.ClosePopups(pop)
    if pop:IsShown() and pop.anchor ~= anchor then Light(pop.anchor, false) end
    pop.key, pop.slot, pop.family, pop.hasAura = tile.key, Page.selected, tile.family, tile.aura == true
    pop.entryName, pop.texture, pop.unit = tile.name, tile.texture, tile.unit
    Page.PlacePopup(pop, anchor)
    if pop.scroll.SetVerticalScroll then pop.scroll:SetVerticalScroll(0) end
    Page.PaintPopover()
    pop:Show()
    Light(anchor, true)
    return true
end
-- The preview moves the open popover to the icon that now holds its entry.
function Page.MovePopover(anchor)
    if not (pop and pop:IsShown()) or pop.anchor == anchor then return end
    Light(pop.anchor, false)
    Page.PlacePopup(pop, anchor)
    Light(anchor, true)
end
