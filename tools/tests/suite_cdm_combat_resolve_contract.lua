local root = assert(arg[1], "repository root required")
-- Combat resolves in stages (ResolveStages.lua). The 2026-10-28 M+ trace ran
-- 56 resolves after combat catalog changes, 1.78 ms each, every one in one
-- frame. In combat a build now takes its inputs and keys in one frame,
-- fills at most Resolve.STEP entries per frame into shadows, and lands in
-- one frame. This contract holds:
--   * nothing a reader sees moves before the landing (plans, entries, every
--     entry field, aura sets, the refill inputs);
--   * what lands is exactly what an immediate build makes, live entry
--     tables and aura set tables kept, and touched names the live entries;
--   * a staged build reads the same client data as an immediate one;
--   * a resolve request, an override or a retexture restarts it; past two
--     restarts, and in previews, the build runs at once;
--   * no frame of a staged build costs half an immediate build.
-- "measure" (arg 2) prints the numbers only.
local measureOnly = arg[2] == "measure"
local W = dofile(root .. "/tools/tests/cdm_data_world.lua")(root)
local C, NS = W.C, W.NS
local CDM = NS.CDM
local Catalog, Resolve = C.Catalog, C.Resolve
local checks = 0
local function Check(value, message)
    checks = checks + 1
    if not measureOnly then assert(value, message) end
end

------------------------------------------------------------------ fixture
-- The trace-sized catalog plus custom bars with every key kind (spell,
-- item, equipment slot, buff, debuff): every fill path is staged.
local SPELL_CATEGORY = C.Const.SPELL_CATEGORY
local POTIONS = { SPELL_CATEGORY.COMBAT_POTION, SPELL_CATEGORY.HEALTH_POTION, SPELL_CATEGORY.HEALTHSTONE }
local function Add(category, count, make)
    local list = {}
    for i = 1, count do
        local id = 1000 + category * 100 + i
        list[i] = id
        local info = { cooldownID = id, spellID = 50000 + id, linkedSpellIDs = {}, selfAura = false, hasAura = false,
            charges = false, isKnown = true, isInvisible = false, flags = 0, category = category }
        if make then make(info, i) end
        W.infos[id] = info
    end
    W.sets[category] = list
end
Add(0, 14, function(info, i) info.charges, info.isKnown, info.flags = i % 4 == 0, i <= 12, i == 14 and 2 or 0 end)
Add(1, 14, function(info, i) info.isKnown = i ~= 7 end)
Add(2, 20, function(info, i)
    info.hasAura, info.selfAura = true, i % 2 == 0
    if i % 5 == 0 then info.linkedSpellIDs = { 60000 + i, 61000 + i } end
end)
Add(3, 14, function(info) info.hasAura, info.selfAura = true, true end)
Add(5, 6, function(info, i) info.spellCategoryID = POTIONS[i] end)
Add(6, 4, function(info) info.hasAura = true end)
Add(7, 2, function(info, i) info.spellID, info.equipSlot = nil, 12 + i end)
Add(8, 2, function(info, i) info.equipSlot, info.hasAura = 12 + i, true end)
W.Views()
C.views.c1.on = true
C.views.c2.on, C.views.c2.kind = true, CDM.KIND.AURA_ICON
W.known[9001], W.known[9002] = true, true
C.lists = CDM.CleanLists({ specs = { [63] = { c1 = { "s9001", "i7001", "e13", "s9002" }, c2 = { "a9101", "d9102" } } } })
C.state.specID = 63
assert(Catalog.Rebuild() == true)
Resolve.Build()

------------------------------------------------------------------ what a reader sees
local function Value(value)
    if type(value) ~= "table" then return tostring(value) end
    if value == C.EMPTY then return "{}" end
    local list = {}
    for k, v in pairs(value) do list[#list + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(list)
    return tostring(value):sub(1, 6) == "table:" and "{" .. table.concat(list, ",") .. "}" or tostring(value)
end
local function Seen()
    local out, keys = {}, {}
    for key in pairs(C.entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local entry, fields = C.entries[key], {}
        for field, value in pairs(entry) do
            fields[#fields + 1] = field .. "=" .. (field == "ov" and tostring(value) or Value(value))
        end
        table.sort(fields)
        out[#out + 1] = key .. "@" .. tostring(entry) .. ":" .. table.concat(fields, ";")
    end
    for _, def in ipairs(CDM.SLOTS) do
        local plan, list = C.plans[def.key], {}
        for i, entry in ipairs(plan and plan.entries or {}) do list[i] = tostring(entry) end
        out[#out + 1] = def.key .. "=" .. (plan and (tostring(plan) .. "/" .. plan.gen .. "/" .. tostring(plan.hasTimers)) or "-")
            .. ":" .. table.concat(list, ",")
    end
    out[#out + 1] = "gen=" .. tostring(C.state.entryGen)
    return table.concat(out, "\n")
end
local function Touched()
    local list = {}
    for i, entry in ipairs(Resolve.touched) do list[i] = entry.key .. "@" .. tostring(entry) end
    table.sort(list)
    return table.concat(list, ",")
end
local function Natives()
    local out = {}
    for name, n in pairs(W.natives) do out[#out + 1] = name .. "=" .. n end
    table.sort(out)
    return table.concat(out, ",")
end

------------------------------------------------------------------ costs
W.Reset()
local immediateVM = W.Cost(Resolve.Build)
local immediateNatives = Natives()
-- One staged build: VM per call, natives over all calls, every call but
-- the last returns nil and leaves the readers' view alone.
local function Staged(fresh, between)
    W.Reset()
    local seen, calls, peak, total = Seen(), 0, 0, 0
    local plans, any
    repeat
        local vm, p, a = W.Cost(Resolve.Build, true, fresh and calls == 0)
        calls, total, plans, any = calls + 1, total + vm, p, a
        if vm > peak then peak = vm end
        if plans == nil then
            Check(Seen() == seen, "a staged resolve changed what readers see before it landed (call " .. calls .. ")")
            if between then between(calls) end
        end
    until plans ~= nil or calls > 40
    return plans, any, calls, peak, total
end
local plans, any, calls, peak, total = Staged(true)
print(("CDM combat resolve: immediate build vm=%d; staged %d calls, max vm %d per frame, total %d"):format(immediateVM, calls,
    peak, total))
Check(plans == C.plans and any == false and calls > 2, "an unchanged staged build did not land unchanged over frames")
Check(Natives() == immediateNatives, "a staged build read other client data than an immediate one: " .. Natives()
    .. " / " .. immediateNatives)
-- 2026-10-29, 76 records and 66 entries: one frame of 67085 VM before;
-- staged 8988 (inputs), 7508 (keys), fills of 4444-11084, landing 14244
-- (93177 in all). Budget: the measured peak +1 %, under a quarter.
Check(peak * 4 < immediateVM and peak <= 14386, "a staged resolve frame exceeded its VM budget")

------------------------------------------------------------------ equivalence
-- A change on a shown entry: the landing applies it to the live table,
-- touched names it, and an immediate build afterwards finds nothing to do.
do
    W.infos[1001].overrideTooltipSpellID, W.infos[1201].linkedSpellIDs = 1234, { 62001 }
    Catalog.Rebuild()
    local live, buff = C.entries.b1001, C.entries.b1201
    local ids = buff.auraIDs
    plans, any = Staged(true)
    Check(plans ~= nil and C.entries.b1001 == live and live.tooltip == 1234, "the landing replaced or missed a live entry")
    Check(buff.auraIDs == ids and ids[62001] == true, "the landing replaced the live aura set or missed its change")
    Check(Touched():find("b1001@" .. tostring(live), 1, true) and Touched():find("b1201@" .. tostring(buff), 1, true),
        "touched does not name the live entries")
    local landed = Seen()
    local _, again = Resolve.Build()
    Check(again == false and #Resolve.touched == 0 and Seen():gsub("gen=%d+", "") == landed:gsub("gen=%d+", ""),
        "the staged result differs from an immediate build")
    W.infos[1001].overrideTooltipSpellID, W.infos[1201].linkedSpellIDs = nil, {}
    Catalog.Rebuild()
    Resolve.Build()
end
-- Every field a fill writes is in Resolve.FILL: a fill into an empty
-- table writes nothing else (all key kinds of the fixture).
do
    local FILL = {}
    for _, field in ipairs(Resolve.FILL) do FILL[field] = true end
    FILL.auraIDs, FILL.key = true, true
    for key in pairs(C.entries) do
        local probe = setmetatable({}, { __newindex = function(t, field, value)
            Check(FILL[field], "a fill writes " .. field .. " (" .. key .. "), which a staged build does not land")
            rawset(t, field, value)
        end })
        C.EntryFill.Fill(probe, key)
        C.AuraTimers.Classify(probe)
    end
end

------------------------------------------------------------------ restarts
do
    W.Reset()
    Check(Resolve.Build(true, true) == nil, "first stage")
    Check(Resolve.Build(true, false) == nil, "second stage")
    -- An override while staging (Catalog.OnOverride) fills again.
    Catalog.OnOverride(51001, 51999)
    W.Reset()
    Check(Resolve.Build(true, false) == nil and (W.natives.GetSpellTexture or 0) == 0, "an override did not restart the stage")
    Check(Resolve.Build(true, true) == nil, "a fresh request did not restart the stage")
    Check(Resolve.Build(true, true) ~= nil, "a third restart did not build at once")
    Catalog.OnOverride(51001, nil)
    Resolve.Build()
    -- Previews build at once.
    C.state.preview = true
    Check(Resolve.Build(true, true) ~= nil, "a preview staged its build")
    C.state.preview = false
    Resolve.Build()
    -- An immediate build drops a staged one.
    Check(Resolve.Build(true, true) == nil, "stage to drop")
    Resolve.Build()
    Check(Resolve.Build(true, false) == nil and Resolve.stage.i == 0, "a dropped stage was continued")
    Staged(false)
end

-- Any override restarts a stage, also one no live entry follows: a key
-- new to the stage may.
do
    Check(Resolve.Build(true, true) == nil and Resolve.Build(true, false) == nil and Resolve.Build(true, false) == nil
        and Resolve.stage.i >= 1, "stage for an untracked override")
    Catalog.OnOverride(424242, 1)
    Check(Resolve.Build(true, false) == nil and Resolve.stage.i == 0, "an override of a base no live entry follows kept the stage")
    Staged(false)
end

print("CDM combat resolve: " .. checks .. " checks passed")
