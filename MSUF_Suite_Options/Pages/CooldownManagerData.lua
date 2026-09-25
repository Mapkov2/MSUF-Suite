local _, P = ...
-- Cooldown manager page, shared state and edits: bar selection, list, bar and
-- per-spell edits (one history entry per gesture; gestures that drop data
-- offer an Undo line). The pooled editors (spell tiles and picker in
-- CooldownManagerWidgets.lua, sound picker and per-spell popover in
-- CooldownManagerPopover.lua) build on the helpers exported here.
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local CDM = Suite and Suite.CDM
local ID, PAGE = "cooldownManager", "suite_cooldownManager"
if not (CDM and P.catalog and P.catalog[ID]) then return end

local RULES, SLOTS, KEYS = P.catalog[ID].rules, CDM.SLOTS, CDM.KEYS
local REF_KEYS = { KEYS.ess, KEYS.buf, KEYS.bar }
local EMPTY = {}
local QUESTION = 134400
local RUNTIME = "MSUF_Suite_CooldownManager"
-- Icon crop of every spell texture the page draws.
local CROP_MIN, CROP_MAX = 0.08, 0.92
local floor, min, format = math.floor, math.min, string.format

local Page = P.CDMPage or {}
P.CDMPage = Page
Page.ID, Page.PAGE, Page.CROP_MIN, Page.CROP_MAX = ID, PAGE, CROP_MIN, CROP_MAX
Page.QUESTION = QUESTION
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
Page.Plain, Page.EntryKey = Plain, EntryKey
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
        if type(load) ~= "function" then
            Page.loadFailed = "LoadAddOn unavailable"
            return false
        end
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
    if info and info.GetSpecialization then
        index = info.GetSpecialization()
    elseif type(_G.GetSpecialization) == "function" then
        index = _G.GetSpecialization()
    end
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
-- An explicit order that matches what the bar shows now, followed by listed
-- entries it cannot show right now (unlearned talents keep their place).
local function Materialize(lists, spec, slot)
    local slots = lists.specs[spec]
    if not slots then
        slots = {}
        lists.specs[spec] = slots
    end
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
        local slots = lists.specs[spec]
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
        if P.Get(ID, key) ~= value then
            Page.Fail("That changed since, so it cannot be undone.")
            return false
        end
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
        or label == "Restore raid essentials" and format(Tr("%s is back to its raid essentials."), Page.BarName(slot))
        or label == "Restore spec defaults" and format(Tr("%s is back to its spec defaults."), Page.BarName(slot))
        or format(Tr("%s follows Blizzard's list again."), Page.BarName(slot))
    local ok, reason = Page.WithUndo(text, LIST_KEYS, function() return Page.ClearList(slot) end)
    if not ok then Page.Fail(reason) end
    return ok
end
function Page.ImportBlizzardWithUndo()
    local ok, reason = Page.WithUndo("Imported Blizzard's cooldown layout for this specialization.", LIST_KEYS,
        Page.ImportBlizzard)
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
    if not ok then
        Page.Fail(added)
        return false
    end
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
    if not slot then
        Page.Fail("All six custom bars are in use.")
        return false
    end
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
    if not ok then
        Page.Fail(reason)
        return false
    end
    if Page.selected == slot then
        local first = "ess"
        for i = 1, #SLOTS do
            if Page.IsOn(SLOTS[i].key) then
                first = SLOTS[i].key
                break
            end
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
    if not free then
        Page.Fail("All six custom bars are in use.")
        return false
    end
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
            if not headed then
                n = AddValue(n + 1, "header", "Turn a bar back on", true)
                headed = true
            end
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
    if from then
        Page.CopyBarSettings(from, slot)
    elseif value == "show" then
        if Page.SlotInfo(slot).custom then Page.EnableBar(slot) else P.Set(ID, KEYS[slot].on, true) end
    elseif value == "hide" then
        P.Set(ID, KEYS[slot].on, false)
    elseif value == "rename" then
        Page.Select(slot)
        Page.FocusName()
    elseif value == "move" then
        P.MoveOnScreen(ID, slot)
    elseif value == "reset" then
        Page.ResetBar(slot)
    elseif value == "delete" then
        Page.DeleteBar(slot)
    end
end
function Page.OpenBarMenu(owner, slot)
    slot = slot or Page.selected
    if P.Combat() or not (W.OpenDropdown and owner and KEYS[slot]) then return false end
    local custom, on = Page.SlotInfo(slot).custom, Page.IsOn(slot)
    local n = 1
    MenuItem(n, on and "hide" or "show", on and "Hide this bar" or "Show this bar")
    if custom then
        n = n + 1
        MenuItem(n, "rename", "Rename this bar")
    end
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
Page.Media = Media
function Page.PlaySound(value)
    if type(value) ~= "string" or value == "" then return end
    if S.CooldownManagerPlaySound then
        S.CooldownManagerPlaySound(value)
        return
    end
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
