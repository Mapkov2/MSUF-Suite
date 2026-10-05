local _, P = ...
-- Cooldown manager page, shared state and data: bar model, runtime access,
-- the sound catalog and entry names. List and per-spell edits (one history
-- entry per gesture) are in CooldownManagerLists.lua, bar edits and the note
-- line with its Undo in CooldownManagerBars.lua; the pooled editors (spell
-- tiles and picker in CooldownManagerWidgets.lua and CooldownManagerPicker.lua,
-- sound picker in CooldownManagerSounds.lua, per-spell popover in
-- CooldownManagerPopover.lua) build on the helpers exported here.
local Suite, S, T, Tr = P.Suite, P.S, P.T, P.Tr
local CDM = Suite.CDM
local KIND, FAMILY = CDM.KIND, CDM.FAMILY
local ID, PAGE = "cooldownManager", "suite_cooldownManager"

local RULES, SLOTS, KEYS = P.catalog[ID].rules, CDM.SLOTS, CDM.KEYS
local REF_KEYS = { KEYS.ess, KEYS.buf, KEYS.bar }
local QUESTION = 134400
local RUNTIME = "MSUF_Suite_CooldownManager"
-- Icon crop of every spell texture the page draws.
local CROP_MIN, CROP_MAX = 0.08, 0.92
local floor, min, format = math.floor, math.min, string.format

local Page = { popups = {}, inputs = {}, selected = "ess" }
P.CDMPage = Page
Page.ID, Page.PAGE, Page.CROP_MIN, Page.CROP_MAX = ID, PAGE, CROP_MIN, CROP_MAX
Page.QUESTION = QUESTION

------------------------------------------------------------------ basics
-- The suite's secret check (MSUF_Suite/Core/Platform.lua, always loaded).
local Public = Suite.Public
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
-- a protected value must not become a table key. Translated text takes the
-- same raw setter (P.SetTranslatedText).
Page.SetRaw = P.SetTranslatedText

function Page.SlotInfo(slot) return SLOTS[CDM.SLOT_INDEX[slot] or 1] end
function Page.Kind(slot)
    local info = Page.SlotInfo(slot)
    if info.custom then return P.Get(ID, KEYS[info.key].kind) end
    return info.kind
end
function Page.Family(slot) return Page.Kind(slot) == KIND.COOLDOWN and FAMILY.COOLDOWN or FAMILY.AURA end
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
    return S.states[ID].active == true
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
    return family == FAMILY.COOLDOWN and "That bar shows buffs." or "That bar shows cooldowns."
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
local TIMER_FIELDS = { barWidth=true, barHeight=true, barTexture=true, barColor=true, barClass=true,
    barBgAlpha=true, barIcon=true, barIconSide=true, barName=true, barTime=true, barFill=true }
function Page.Relevant(slot, suffix)
    local key = KEYS[slot] and KEYS[slot][suffix]
    if not key or RULES[key].hidden then return false end
    local kind = Page.Kind(slot)
    if suffix == "barStacks" or suffix == "barStackMax" or suffix == "barStackEach" or suffix == "barStackMarks"
        or suffix == "barStackColorAt" or suffix == "barStackColor" then return kind == KIND.AURA_BAR end
    if suffix == "barChargeSegments" or suffix == "barChargeDim" then return kind == KIND.COOLDOWN and P.Get(ID, KEYS[slot].cooldownDuration) == true end
    if kind == KIND.COOLDOWN and TIMER_FIELDS[suffix] then return P.Get(ID, KEYS[slot].cooldownDuration) == true end
    if not Page.SlotInfo(slot).custom or suffix == "name" or suffix == "kind" or suffix == "shareContents" then return true end
    if kind == KIND.AURA_BAR and KIND3_EXTRA[suffix] then return true end
    if (kind == KIND.AURA_ICON or kind == KIND.AURA_BAR) and AURA_EXTRA[suffix] then return true end
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
-- A section reset writes only the selected bar's own keys: a suffix the bar
-- lacks resolves to nothing, so P.ResetRules skips it instead of resetting
-- custom bar 1's template key.
function Page.ResetKeyFn(key)
    local suffix = TEMPLATE_SUFFIX[key]
    if not suffix then return key end
    return KEYS[Page.selected][suffix]
end
-- The sound channel means nothing while the module's sounds are muted.
P.Gates[ID] = function(rule)
    if rule.key == "soundChannel" then return P.Get(ID, "muteSounds") ~= true end
    if not TEMPLATE_SUFFIX[rule.key] then return true end
    return Page.Relevant(Page.selected, rule.suffix)
end

P.SearchPreparers[ID] = function(rule)
    if not rule.suffix or Page.Relevant(Page.selected, rule.suffix) then return end
    local fallback
    for _, slot in ipairs(SLOTS) do
        if Page.Relevant(slot.key, rule.suffix) then
            if Page.IsOn(slot.key) then return Page.Select(slot.key) end
            fallback = fallback or slot.key
        end
    end
    if fallback then Page.Select(fallback) end
end

-- Text inputs commit on blur. An input remembers the bar it was focused on,
-- and a bar switch commits the pending text first, so a typed name always
-- lands on the bar it was typed for.
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
-- on page activation, never in combat, and only where the module can run;
-- until then its S.CooldownManager* exports are nil.
function Page.EnsureRuntime()
    if S.CooldownManagerBarEntries then return true end
    if Page.loadFailed or P.Combat() or not S.Availability(ID) then return false end
    if not Suite.Client.IsAddOnLoaded(RUNTIME) then
        local loaded, reason = C_AddOns.LoadAddOn(RUNTIME)
        if not loaded and not Suite.Client.IsAddOnLoaded(RUNTIME) then
            Page.loadFailed = Suite.Client.LoadReasonText(reason, Tr("not installed"))
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
    if not ok then return Suite.StatusText(reason or "Unavailable on this client", Tr) end
    if not S.CooldownManagerBarEntries then
        if Page.loadFailed then return format(Tr("Cannot load %s: %s"), RUNTIME, Page.loadFailed) end
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
    local index = C_SpecializationInfo.GetSpecialization()
    if not Public(index) or type(index) ~= "number" or index < 1 then return nil end
    local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
    if not Public(id) or type(id) ~= "number" or id <= 0 then return nil end
    return id, Public(name) and type(name) == "string" and name or nil, Public(icon) and icon or nil
end

function Page.ClassSpecs(out)
    local count = GetNumSpecializations()
    if not Public(count) or type(count) ~= "number" then return out end
    for i = 1, min(count, 6) do
        local id = C_SpecializationInfo.GetSpecializationInfo(i)
        if Public(id) and type(id) == "number" and id > 0 then out[#out + 1] = id end
    end
    return out
end

local Media = Suite.SharedMedia
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
    -- PlaySoundFile is not referenced in Blizzard's UI source, so it is checked.
    if path and type(_G.PlaySoundFile) == "function" then _G.PlaySoundFile(path, "Master") end
end
-- Blizzard's Cooldown Manager sound list, read only: CooldownViewerSoundData
-- maps Enum.CooldownViewerSoundCategory values to { soundEnum, soundKitID,
-- text } rows. Built once per table; the kits play as "kit:<soundKitID>".
local kitSounds = { groups = {}, names = {} }
local function CategoryTitle(id)
    -- Blizzard_CooldownViewer defines it at startup on 12.1.0, 12.1.5 and Forever.
    local key
    for name, value in pairs(Enum.CooldownViewerSoundCategory) do
        if value == id and type(name) == "string" then key = name end
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
            if type(text) ~= "string" or text == "" then text = format(Tr("Sound kit %s"), format("%d", kit)) end
            group[#group + 1] = { value = "kit:" .. format("%d", kit), text = text }
            kitSounds.names[kit] = text
        end
    end
    return group
end
function Page.BlizzardSounds()
    local data = CooldownViewerSoundData
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
        return Page.BlizzardSounds().names[tonumber(kit)] or format(Tr("Sound kit %s"), kit)
    end
    local file = value:match("^file:(%d+)$")
    return file and format(Tr("Sound file %s"), file) or value
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
