local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Isolated options data for an inactive specialization. No runtime state,
-- spellbook knowledge or equipment of the current character is substituted.
local CDM = NS.CDM
local Editor = {}
C.Editor = Editor
local EMPTY, Public = C.EMPTY, S.Public
local function Plain(value) if Public(value) then return value end end
local function Number(value)
    value = Plain(value)
    if type(value) == "number" and value > 0 and value < 2147483648 and value == math.floor(value) then return value end
end
local function Text(value)
    value = Plain(value)
    if type(value) == "string" and #value <= 240 then return value end
end

-- Metadata only, separate from profile settings and undo. Capture while the
-- options page asks for data, never from a cooldown or combat event.
local rememberedProfile, rememberedSpec, rememberedGeneration
function Editor.Remember()
    local root = NS.RootDB
    local spec = C.state.specID
    local profile = NS.Database and NS.Database.GetActiveProfileName()
    if not root or not spec or not profile or NS.InCombat() then return end
    local generation = C.Catalog.generation
    if rememberedProfile == profile and rememberedSpec == spec and rememberedGeneration == generation then return end
    rememberedProfile, rememberedSpec, rememberedGeneration = profile, spec, generation
    local rows = {}
    for i = 1, math.min(#C.Catalog.order, 600) do
        local rec = C.Catalog.records[C.Catalog.order[i]]
        if rec and CDM.ValidEntryKey(rec.key) then
            rows[#rows + 1] = { key = rec.key, name = Text(C.Catalog.RecordName(rec)), texture = Number(C.Catalog.RecordTexture(rec)),
                spell = Number(rec.spell), override = Number(rec.override), family = rec.family, slot = rec.bar,
                tail = C.Catalog.TAIL[rec.category] == true, known = rec.known == true, equipSlot = Number(rec.equipSlot),
                spellCategory = Number(rec.spellCategory), hasAura = rec.hasAura == true, linked = {} }
            local copy = rows[#rows].linked
            for j = 1, #(rec.linked or EMPTY) do
                local id = Number(rec.linked[j])
                if id then copy[#copy + 1] = id end
            end
        end
    end
    if #rows == 0 then return end
    rows.defaults, rows.knownSpells = {}, {}
    for slot, list in pairs(C.Catalog.defaultByBar) do
        local copy = {}
        for i = 1, #list do if CDM.ValidEntryKey(list[i]) then copy[#copy + 1] = list[i] end end
        rows.defaults[slot] = copy
    end
    local _, _, classID = UnitClass("player")
    local presets = { C.Presets.RaidEssentials(spec) or EMPTY, C.Presets.Defensives(classID), C.Presets.RACIALS }
    for _, ids in ipairs(presets) do
        for i = 1, #ids do rows.knownSpells[ids[i]] = C.EntryFill.Known(ids[i]) == true end
    end
    root.cdmEditorCatalog = root.cdmEditorCatalog or {}
    local mine = root.cdmEditorCatalog[profile] or {}
    root.cdmEditorCatalog[profile] = mine
    mine[spec] = rows
end

local function Describe(key, family, saved)
    local kind, id = CDM.EntryKind(key), CDM.EntryID(key)
    local spell, base, override, linked, texture, name, hasAura
    if kind == "b" then
        local info = Plain(C_CooldownViewer.GetCooldownViewerCooldownInfo(id))
        if type(info) == "table" then
            base, override = Number(info.spellID), Number(info.overrideSpellID)
            spell = override or base
            local ids = Plain(info.linkedSpellIDs)
            if type(ids) == "table" then
                linked = {}
                for i = 1, math.min(#ids, 32) do
                    local value = Number(ids[i])
                    if value then linked[#linked + 1] = value end
                end
            end
            hasAura = Plain(info.hasAura) == true
        end
    elseif kind == "a" and CDM.AURA_GROUPS[id] then
        -- A group's own name; its icon is the first source this client knows.
        local group = CDM.AURA_GROUPS[id]
        name = S.Text(group.name)
        for i = 1, #group.ids do
            texture = texture or Number(C_Spell.GetSpellTexture(group.ids[i]))
        end
    elseif kind == "s" or kind == "a" or kind == "d" then
        spell = id
    elseif kind == "i" then
        name, texture = Text(C_Item.GetItemNameByID(id)), Number(C_Item.GetItemIconByID(id))
    elseif kind == "e" then
        name = string.format(S.Text("Trinket slot %d"), id - 12)
    end
    if spell then
        name, texture = Text(C_Spell.GetSpellName(spell)), Number(C_Spell.GetSpellTexture(spell))
    end
    saved = type(saved) == "table" and saved or EMPTY
    name, texture = name or Text(saved.name), texture or Number(saved.texture)
    return { key = key, family = family, spell = spell or Number(saved.spell), base = Number(saved.spell) or base,
        override = Number(saved.override) or override, linked = type(saved.linked) == "table" and saved.linked or linked, name = name or key,
        texture = texture or C.Const.QUESTION_ICON, known = true, hasAura = hasAura or saved.hasAura == true, unavailable = name == nil }
end

local CATEGORY = C.Catalog.BAR_OF
local AURA = Enum.CooldownViewerCategory
local AURA_CATEGORY = { [AURA.TrackedBuff] = true, [AURA.TrackedBar] = true,
    [AURA.SpecAgnosticTracked] = true, [AURA.EquipSlotTracked] = true }
local function Add(context, key, slot, family, saved)
    if not CDM.ValidEntryKey(key) or not CDM.SLOT_INDEX[slot] then return end
    local row = context.records[key]
    if not row then
        row = Describe(key, family, saved)
        context.records[key] = row
        context.order[#context.order + 1] = key
        row.slot = slot
        if saved then
            row.known, row.equipSlot = saved.known, Number(saved.equipSlot)
            row.tail, row.spellCategory = saved.tail == true, Number(saved.spellCategory)
        end
    end
    return row
end
local function SavedCatalog(context)
    local root = NS.RootDB
    local all = root and root.cdmEditorCatalog
    local mine = type(all) == "table" and all[context.profile]
    local rows = type(mine) == "table" and mine[context.spec]
    if type(rows) ~= "table" then return end
    for i = 1, math.min(#rows, 600) do
        local row = rows[i]
        if type(row) == "table" and (row.family == 1 or row.family == 2) then
            Add(context, row.key, row.slot, row.family, row)
        end
    end
    context.observed = #context.order > 0
    context.knownSpells = type(rows.knownSpells) == "table" and rows.knownSpells or EMPTY
    local defaults = type(rows.defaults) == "table" and rows.defaults or EMPTY
    for slot, list in pairs(defaults) do
        if CDM.SLOT_INDEX[slot] and type(list) == "table" then
            local copy = {}
            for i = 1, math.min(#list, 600) do
                if context.records[list[i]] then copy[#copy + 1] = list[i] end
            end
            context.defaultByBar[slot] = copy
        end
    end
end
local function GuideCatalog(context)
    local guide = C.GuideProfiles[context.spec]
    if not guide then return end
    local order, moves = guide.order or EMPTY, guide.moves or EMPTY
    for i = 1, math.min(#order, 600) do
        local id = order[i]
        local category = moves[id]
        if category == nil then
            local info = Plain(C_CooldownViewer.GetCooldownViewerCooldownInfo(id))
            local value = type(info) == "table" and Plain(info.category)
            if type(value) == "number" then category = value end
        end
        local slot = CATEGORY[category]
        if slot then Add(context, "b" .. id, slot, AURA_CATEGORY[category] and 2 or 1) end
    end
end
local function Preset(context, ids, slot, spellKey)
    if not ids then return end
    local list, seen = {}, {}
    context.presets[slot] = list
    for i = 1, #ids do
        local id = ids[i]
        local key = spellKey[id] or "s" .. id
        local row = Add(context, key, slot, 1)
        if row and not row.unavailable and not seen[key]
            and (spellKey[id] or context.knownSpells[id] ~= false)
            and (slot ~= "ext" or context.knownSpells[id] == true) then
            seen[key] = true
            list[#list + 1] = key
        end
    end
end
local function Defaults(context)
    SavedCatalog(context)
    if not context.observed then GuideCatalog(context) end
    context.catalogCount = #context.order
    context.catalogUnavailable = not context.observed and context.catalogCount == 0
    local spellKey = {}
    for i = 1, #context.order do
        local row = context.records[context.order[i]]
        if not context.observed and row.slot ~= "ext" then
            local list = context.defaultByBar[row.slot]
            if not list then
                list = {}
                context.defaultByBar[row.slot] = list
            end
            list[#list + 1] = row.key
        end
        if row.family == 1 then
            if row.base and not spellKey[row.base] then spellKey[row.base] = row.key end
            if row.spell and not spellKey[row.spell] then spellKey[row.spell] = row.key end
            if row.override and not spellKey[row.override] then spellKey[row.override] = row.key end
            for j = 1, math.min(#(row.linked or EMPTY), 600) do
                local id = Number(row.linked[j])
                if id and not spellKey[id] then spellKey[id] = row.key end
            end
        end
    end
    local guide = not context.observed and C.GuideProfiles[context.spec]
    if guide and guide.buffIcons then
        local list = {}
        context.defaultByBar.buf = list
        for i = 1, #guide.buffIcons do
            local key = "b" .. guide.buffIcons[i]
            local row = context.records[key]
            if row and row.slot == "buf" then list[#list + 1] = key end
        end
    end
    Preset(context, context.config.raidEssentials ~= false and C.Presets.RaidEssentials(context.spec) or nil, "ess", spellKey)
    Preset(context, C.Presets.Defensives(context.classID), "def", spellKey)
    -- A foreign character's race cannot be inferred from its class.
    Preset(context, C.Presets.RACIALS, "ext", spellKey)
end
-- Item/native healthstone aliases have one owner, as in Resolve.Canon.
-- Only saved knowledge may establish the learned native record.
local function Aliases(context)
    local covered = {}
    for i = 1, context.catalogCount do
        local row = context.records[context.order[i]]
        local category = row.spellCategory
        local old = category and covered[category]
        if context.observed and row.known == true and category
            and (not old or CDM.EntryID(row.key) < CDM.EntryID(old)) then covered[category] = row.key end
    end
    local extra = context.presets.ext or {}
    context.presets.ext = extra
    for i = #C.Presets.CONSUMABLES, 1, -1 do
        local item = C.Presets.CONSUMABLES[i]
        local key, native = "i" .. item.item, covered[item.category]
        if native then
            context.alias[key] = native
        else
            context.stand[item.category] = key
            Add(context, key, "ext", 1)
            table.insert(extra, 1, key)
        end
    end
    for i = 1, context.catalogCount do
        local row = context.records[context.order[i]]
        local stand = row.known == false and row.spellCategory and context.stand[row.spellCategory]
        if stand then context.alias[row.key] = stand end
    end
end
local function Family(context, slot)
    local def = CDM.SLOTS[CDM.SLOT_INDEX[slot]]
    local kind = def.custom and context.config[CDM.KEYS[slot].kind] or def.kind
    return kind == CDM.KIND.COOLDOWN and 1 or 2
end
local function ListOf(context, def, defaultsOnly)
    local slot = def.key
    if def.custom and context.config[CDM.KEYS[slot].shareContents] then
        return context.lists.shared[slot] or EMPTY, true
    end
    local list = (context.lists.specs[context.spec] or EMPTY)[slot]
    if list and not (defaultsOnly and list.inherit) then return list, true end
    if slot == "ess" or def.preset == "defensives" then return context.presets[slot], false end
    -- As Resolve: spec defaults only with the spec's profile row.
    if context.presets.ess then return context.defaultByBar[slot], false end
end
local function Claim(context, list, slot)
    for i = 1, list and #list or 0 do
        local key = context.alias[list[i]] or list[i]
        local row = context.records[key] or Add(context, key, slot, Family(context, slot))
        if row and row.family == Family(context, slot) and not context.claims[key] then
            context.claims[key] = slot
            if CDM.EntryKind(key) == "e" then context.slotHome[CDM.EntryID(key)] = slot end
        end
    end
end
local function Claims(context)
    for _, def in ipairs(CDM.SLOTS) do
        if def.custom and context.config[CDM.KEYS[def.key].shareContents] then Claim(context, ListOf(context, def), def.key) end
    end
    for _, def in ipairs(CDM.SLOTS) do
        local list, explicit = ListOf(context, def)
        if explicit then Claim(context, list, def.key) end
    end
    local list, explicit = ListOf(context, CDM.SLOTS[CDM.SLOT_INDEX.def])
    if not explicit and context.config[CDM.KEYS.def.on] then Claim(context, list, "def") end
    for _, def in ipairs(CDM.SLOTS) do
        local list, explicit = ListOf(context, def, true)
        if def.key ~= "def" and not explicit and context.config[CDM.KEYS[def.key].on] then Claim(context, list, def.key) end
        if def.preset == "racials" and context.config[CDM.KEYS[def.key].on] then Claim(context, context.presets[def.key], def.key) end
    end
end
local function Offer(context, slot, key, seen, rows, explicit, listed)
    key = listed and context.alias[key] or key
    local row, owner = context.records[key], context.claims[key]
    local hidden = (context.lists.hidden[context.spec] or EMPTY)[key]
    if not row or row.family ~= Family(context, slot) or seen[key] or (owner and owner ~= slot) then return end
    if listed and owner ~= slot or hidden and not explicit then return end
    local stand = row.spellCategory and context.stand[row.spellCategory]
    if not listed and stand and context.claims[stand] then return end
    local equip = row.equipSlot
    if equip and (seen["e" .. equip] or context.slotHome[equip] and context.slotHome[equip] ~= slot) then return end
    seen[key] = true
    rows[#rows + 1] = row
end
local function CollectList(context, slot, list, explicit, seen, rows)
    for i = 1, list and #list or 0 do Offer(context, slot, list[i], seen, rows, explicit, true) end
end
local function FillEssential(context, slot, seen, rows)
    local count = 0
    for _, row in ipairs(rows) do if row.known ~= false and not row.equipSlot then count = count + 1 end end
    for _, key in ipairs(context.defaultByBar.ess or EMPTY) do
        if count >= 4 then break end
        local row = context.records[key]
        if row and row.known ~= false and not row.equipSlot then
            local before = #rows
            Offer(context, slot, key, seen, rows)
            if #rows > before then count = count + 1 end
        end
    end
    for i = 1, context.catalogCount do
        local row = context.records[context.order[i]]
        if row.slot == slot and row.equipSlot then Offer(context, slot, row.key, seen, rows) end
    end
end
local function Bars(context)
    local replace = context.lists.replace[context.spec] or EMPTY
    for _, def in ipairs(CDM.SLOTS) do
        local slot, rows, seen = def.key, {}, {}
        context.bars[slot] = rows
        local list, explicit = ListOf(context, def)
        local inherited = explicit and list.inherit and ListOf(context, def, true) or nil
        CollectList(context, slot, inherited, false, seen, rows)
        CollectList(context, slot, list, explicit, seen, rows)
        local strict = inherited ~= nil or list ~= nil and not explicit and (slot == "ess" or context.defaultByBar[slot] ~= nil) or replace[slot]
        if def.builtin and not strict then
            for pass = 1, 2 do
                for i = 1, context.catalogCount do
                    local key = context.order[i]
                    local row = context.records[key]
                    if row.slot == slot and (row.tail == true) == (pass == 2) then Offer(context, slot, key, seen, rows) end
                end
            end
        elseif slot == "ess" and (not explicit or inherited) then
            FillEssential(context, slot, seen, rows)
        end
        if def.preset == "racials" then CollectList(context, slot, context.presets[slot], false, seen, rows) end
    end
end

local cache
local function Signature(config)
    local sig, weight = 0, 1
    for _, def in ipairs(CDM.SLOTS) do
        local keys = CDM.KEYS[def.key]
        local kind = def.custom and config[keys.kind] or def.kind
        sig = sig + ((kind or 1) + (config[keys.on] and 4 or 0) + (def.custom and config[keys.shareContents] and 8 or 0)) * weight
        weight = weight * 16
    end
    return sig
end
function Editor.Context(spec, classID, config, classToken)
    local profile = NS.Database and NS.Database.GetActiveProfileName()
    local signature = Signature(config)
    if cache and cache.spec == spec and cache.classToken == classToken and cache.profile == profile and cache.config == config
        and cache.listsText == config.listsData and cache.spellsText == config.spellsData
        and cache.generation == C.Catalog.generation and cache.raid == config.raidEssentials
        and cache.signature == signature then return cache end
    cache = { spec = spec, classID = classID, classToken = Text(classToken), views = {}, profile = profile, config = config, generation = C.Catalog.generation,
        listsText = config.listsData, spellsText = config.spellsData, raid = config.raidEssentials,
        records = {}, order = {}, claims = {}, alias = {}, stand = {}, slotHome = {}, presets = {},
        defaultByBar = {}, knownSpells = EMPTY, bars = {}, signature = signature }
    cache.lists = CDM.Codec.DecodeLists(config.listsData)
    cache.choices = CDM.EffectiveSpells(CDM.Codec.DecodeSpells(config.spellsData), spec)
    Defaults(cache)
    Aliases(cache)
    Claims(cache)
    Bars(cache)
    return cache
end
-- Preview-only view: native class coloring follows the selected class.
-- The live view is never swapped, and warm paints reuse the copied view.
function Editor.View(context, slot, source)
    local r, g, b = S.ClassRGB(context.classToken)
    local view = context.views[slot]
    if not view then
        view = {}
        context.views[slot] = view
    end
    if view.editorStyle ~= source.styleGen or view.editorLayout ~= source.layoutGen
        or view.editorBehavior ~= source.behaviorGen or view.editorR ~= r or view.editorG ~= g or view.editorB ~= b then
        local restyle = view.editorStyle ~= source.styleGen or view.editorR ~= r or view.editorG ~= g or view.editorB ~= b
        local generation = (view.styleGen or 0) + (restyle and 1 or 0)
        for key, value in pairs(source) do view[key] = value end
        view.styleGen = generation
        if r then
            if source.borderClass then view.borderClass, view.borderR, view.borderG, view.borderB = false, r, g, b end
            if source.barClass then view.barClass, view.barR, view.barG, view.barB = false, r, g, b end
        end
        -- MSUF's skin (also one the source dropped) and the decoration made
        -- from this view, so the skinned icon style reads its own colors.
        view.skin = source.skin
        C.Const.Decor(view)
        view.editorStyle, view.editorLayout, view.editorBehavior = source.styleGen, source.layoutGen, source.behaviorGen
        view.editorR, view.editorG, view.editorB = r, g, b
    end
    return view
end
function S.CooldownManagerRememberCatalog()
    Editor.Remember()
end
function S.CooldownManagerEditorContext(spec, classID, classToken)
    if not Number(spec) or not Number(classID) then return nil end
    C.Cold()
    Editor.Remember()
    return Editor.Context(spec, classID, S.Config("cooldownManager"), classToken)
end
