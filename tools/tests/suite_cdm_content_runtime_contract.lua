local root = assert(arg[1], "repository root required")
-- Cooldown manager content (package cdm11-D), runtime half, on the runtime
-- contract's harness (the module is active, its bars live):
--  * The haste buff entry: one aura entry that looks for every Bloodlust
--    source in one group of one container (EntryFill.FillGroup), keeps the
--    plain a<spellID> entry of the same spell unchanged, drops out on a
--    client that knows none of the sources, and survives the foreign
--    specialization editor.
--  * The spell groups of the picker (Presets.CATEGORY_*, S.CooldownManagerGroupKeys):
--    well-formed data for every class and specialization, only known spells,
--    Blizzard's entry key where the catalog tracks the spell, plain spell
--    keys for shared groups, each key once.
--  * The ready pulse (ReadyPulse.lua): off costs nothing (no frame), on
--    builds one pooled frame lazily, honors "only in combat", queues at most
--    three behind the one on screen, writes size, place and hold time only
--    when they change, has no OnUpdate, pulses for a hidden bar and lets go
--    with the module.
--   lua suite_cdm_content_runtime_contract.lua <suiteRoot>
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
local CDM, KEYS = Suite.CDM, Suite.CDM.KEYS
local config = S.Config(ID)
module.config = config
module.context = S.NewContext(ID)
module.active = true
module:Enable()
Run()
do (function()
local spec = C.state.specID
local checks, failures = 0, {}
local function Check(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end

------------------------------------------------------------------ the haste buff entry
local KEY = CDM.HASTE_KEY
local group = CDM.AURA_GROUPS[CDM.EntryID(KEY)]
Check(group and CDM.ValidEntryKey(KEY) and KEY == "a" .. CDM.EntryID(KEY), "the haste key is a valid aura key")
Check(CDM.EntryID(KEY) > 1000000000, "its number is not a spell ID")
local seen, set = {}, {}
for i = 1, #group.ids do
    local id = group.ids[i]
    Check(type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id], "source IDs are positive integers, once each")
    seen[id] = true
end
for _, id in ipairs({ 2825, 32182, 80353, 90355, 264667, 309658, 390386 }) do
    Check(seen[id], "the haste buff lacks source " .. id)
end
Check(seen[group.spell], "the group's icon spell is one of its sources")
for _, lockout in ipairs({ 57723, 57724, 80354, 95809, 160455, 264689, 390435 }) do
    Check(not seen[lockout], "the Sated lockout " .. lockout .. " is no haste source")
end

-- The client knows some sources: fake names and icons for them.
local nameOf, textureOf = C_Spell.GetSpellName, C_Spell.GetSpellTexture
local fake = {}
C_Spell.GetSpellName = function(id) return fake[id] and ("Source " .. id) or nameOf(id) end
C_Spell.GetSpellTexture = function(id)
    if fake[id] then return 7000 + id, 7000 + id end
    return textureOf(id)
end
local function Know(...)
    for id in pairs(fake) do fake[id] = nil end
    for i = 1, select("#", ...) do fake[(select(i, ...))] = true end
end
local out = {}
Know(2825, 32182, 80353, 390386)
Check(C.Resolve.Describe(KEY, out) == out, "the haste entry resolves")
Check(out.src == "a" and out.family == 2 and out.unit == "player" and out.auraHelpful and out.hasAura and out.selfAura,
    "it is a helpful player aura entry")
Check(out.id == CDM.EntryID(KEY) and out.spell == 2825 and out.base == 2825, "its spell is the group's, its id the key's")
Check(out.name == "Bloodlust (any source)" and out.texture == 9825, "one name for the group, the icon of the first known source")
local count = 0
for id in pairs(out.auraIDs) do
    count = count + 1
    Check(seen[id], "a foreign aura ID in the set: " .. id)
end
Check(count == #group.ids, "every source is looked for, known to this client or not (" .. count .. ")")
-- The same table filled with the plain aura entry of Bloodlust alone.
local plain = C.Resolve.Describe("a2825", out)
Check(plain == out and out.name == "Source 2825" and out.spell == 2825, "a plain a2825 entry is unchanged")
local plainCount = 0
for _ in pairs(out.auraIDs) do plainCount = plainCount + 1 end
Check(plainCount == 1 and out.auraIDs[2825], "a plain aura entry looks for its own spell only, and the reused set was wiped")
-- A source other than Bloodlust gives the icon when the first is unknown.
Know(80353)
Check(C.Resolve.Describe(KEY, {}).texture == 7000 + 80353, "the first known source gives the icon")
-- A client that knows none of the sources (WoW Forever) has no such entry.
Know()
Check(C.Resolve.Describe(KEY, {}) == nil, "no source known: no entry")

-- On a bar: one entry, one group of the player's container with every source.
Know(2825, 32182, 80353, 390386)
local lists = config.listsData
config.listsData = assert(Codec.EncodeLists({ v = 1, specs = { [spec] = { buf = { KEY } } } }))
module:Refresh()
Run()
local live = C.entries[KEY]
Check(live and live.slot == "buf" and live.src == "a" and live.name == "Bloodlust (any source)", "the entry sits on its bar")
local rows = S.CooldownManagerBarEntries("buf")
local found = 0
for _, row in ipairs(rows) do
    if row.key == KEY then
        found = found + 1
        Check(row.family == 2 and row.hasAura and row.known and row.name == "Bloodlust (any source)", "the page's row of the entry")
    end
end
Check(found == 1, "the entry is listed once")
local frame = C.bars.buf.frame
local host = C.bars.buf.auraHost or frame
local player
for i = 1, #all do
    local w = all[i]
    if w.kind == "AuraContainer" and (w.parent == host or w.parent == frame) and w.shown and w.enabled and w.unit == "player" then
        player = w
    end
end
Check(player, "the bar has its player container")
local holders = 0
for _, g in pairs(player.groups or {}) do
    if g.on and g.ids and g.ids[2825] then
        holders = holders + 1
        local n = 0
        for _ in pairs(g.ids) do n = n + 1 end
        for _, id in ipairs(group.ids) do Check(g.ids[id], "the group looks for source " .. id) end
        Check(n == #group.ids, "the group looks for the sources and nothing else (" .. n .. ")")
    end
end
Check(holders == 1, "exactly one group carries the haste sources, so one icon shows (" .. holders .. ")")

-- The foreign specialization editor draws the entry by its own name.
config.listsData = assert(Codec.EncodeLists({ v = 1, specs = { [266] = { bar = { KEY } } }, replace = { [266] = { bar = true } } }))
module:Refresh()
Run()
local context = S.CooldownManagerEditorContext(266, 9)
local row = context.bars.bar[1]
Check(row and row.key == KEY and row.family == 2 and not row.unavailable and row.name == "Bloodlust (any source)",
    "the editor describes the haste entry")
Check(row.texture == 9825 or row.texture == 7000 + 2825, "the editor shows a source's icon (" .. tostring(row.texture) .. ")")
Know()
config.listsData = lists
C_Spell.GetSpellName, C_Spell.GetSpellTexture = nameOf, textureOf

------------------------------------------------------------------ spell groups: data
local Presets = C.Presets
local CLASSES = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 }
local SPECS = { 62, 63, 64, 65, 66, 70, 71, 72, 73, 102, 103, 104, 105, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260,
    261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 577, 581, 1467, 1468, 1473, 1480 }
local isClass, isSpec = {}, {}
for _, id in ipairs(CLASSES) do isClass[id] = true end
for _, id in ipairs(SPECS) do isSpec[id] = true end
local function WellFormed(label, list)
    Check(type(list) == "table" and #list > 0, label .. " is a non-empty list")
    local ids = {}
    for i = 1, #list do
        local id = list[i]
        Check(type(id) == "number" and id > 0 and id == math.floor(id) and id < 2147483648, label .. " holds a spell ID")
        Check(not ids[id], label .. " lists " .. id .. " twice")
        ids[id] = true
    end
end
Check(#Presets.CATEGORY_ORDER == 6, "six groups")
local groupNames = {}
for _, name in ipairs(Presets.CATEGORY_ORDER) do
    Check(not groupNames[name], "group " .. name .. " once")
    groupNames[name] = true
    local byClass, bySpec = Presets.CATEGORY_CLASS[name], Presets.CATEGORY_SPEC[name]
    Check(byClass or bySpec, "group " .. name .. " has data")
    for classID, list in pairs(byClass or {}) do
        Check(isClass[classID], name .. " names the unknown class " .. tostring(classID))
        WellFormed(name .. " of class " .. classID, list)
    end
    for specID, list in pairs(bySpec or {}) do
        Check(isSpec[specID], name .. " names the unknown specialization " .. tostring(specID))
        WellFormed(name .. " of specialization " .. specID, list)
    end
end
for _, classID in ipairs(CLASSES) do
    for _, name in ipairs({ "interrupts", "crowdcontrol", "movement" }) do
        Check(Presets.CATEGORY_CLASS[name][classID], "every class has " .. name .. " (class " .. classID .. ")")
    end
end
for _, specID in ipairs(SPECS) do
    Check(Presets.CATEGORY_SPEC.offensive[specID], "every specialization has offensive cooldowns (" .. specID .. ")")
end
Check(Presets.CATEGORY_CLASS.battlerez[6] and Presets.CATEGORY_CLASS.battlerez[9] and Presets.CATEGORY_CLASS.battlerez[11]
    and Presets.CATEGORY_CLASS.battlerez[2], "the four classes with a combat resurrection")
Check(Presets.CATEGORY_CLASS.interrupts[8][1] == 2139 and Presets.CATEGORY_CLASS.interrupts[1][1] == 6552,
    "interrupts lead with the class's main kick")
local a, b = Presets.Category("interrupts", 8, 63)
Check(a == Presets.CATEGORY_CLASS.interrupts[8] and b == C.EMPTY, "a class list answers with an empty specialization list")
a, b = Presets.Category("offensive", 8, 63)
Check(a == C.EMPTY and b == Presets.CATEGORY_SPEC.offensive[63], "offensive cooldowns answer per specialization")
a, b = Presets.Category("nothing", 8, 63)
Check(a == C.EMPTY and b == C.EMPTY, "an unknown group answers empty")

------------------------------------------------------------------ spell groups: the character's known spells
-- Mage (class 8). Known: Counterspell (a Blizzard entry here), Frost Nova,
-- Polymorph, Blink, and the offensive cooldown of the other specialization.
local isKnown = C_SpellBook.IsSpellKnownOrInSpellBook
local mine = { [2139] = true, [122] = true, [118] = true, [1953] = true, [190319] = true, [365350] = true }
C_SpellBook.IsSpellKnownOrInSpellBook = function(id) return mine[id] == true end
local records, order = C.Catalog.records, C.Catalog.order
records[9991] = { id = 9991, key = "b9991", spell = 2139, linked = C.EMPTY, family = 1, known = true }
order[#order + 1] = 9991
local texture = C_Spell.GetSpellTexture
C_Spell.GetSpellTexture = function(id) return 5000 + id end
local groups = S.CooldownManagerGroupKeys()
local function List(list) return table.concat(list, ",") end
Check(List(groups.interrupts) == "b9991" and groups.interrupts.icon == 5000 + 2139, "a tracked spell gives Blizzard's key and its icon")
Check(List(groups.crowdcontrol) == "s118,s122", "known spells in the group's order, unknown ones dropped (" .. List(groups.crowdcontrol) .. ")")
Check(List(groups.movement) == "s1953" and #groups.dispels == 0 and #groups.battlerez == 0, "no known spell: an empty group")
local offensive = spec == 62 and "s365350" or spec == 63 and "s190319" or ""
Check(List(groups.offensive) == offensive, "offensive cooldowns follow the specialization (" .. spec .. ": " .. List(groups.offensive) .. ")")
Check(List(S.CooldownManagerGroupKeys(true).interrupts) == "s2139", "shared groups take spell keys only")
-- A spell listed twice, or once as a replaced base and once as its
-- replacement, counts once.
local dispels = Presets.CATEGORY_CLASS.dispels[8]
Presets.CATEGORY_CLASS.dispels[8] = { 475, 475, 30449 }
mine[475] = true
Check(List(S.CooldownManagerGroupKeys().dispels) == "s475", "a spell listed twice is one key")
Presets.CATEGORY_CLASS.dispels[8] = dispels
-- A client that knows none of them (WoW Forever) adds nothing.
for id in pairs(mine) do mine[id] = nil end
groups = S.CooldownManagerGroupKeys()
for _, name in ipairs(Presets.CATEGORY_ORDER) do Check(#groups[name] == 0, name .. " adds nothing when nothing is known") end
records[9991], order[#order] = nil, nil
C_SpellBook.IsSpellKnownOrInSpellBook, C_Spell.GetSpellTexture = isKnown, texture

------------------------------------------------------------------ the ready pulse
local rules = S.catalog[ID].rules
Check(rules[KEYS.ess.readyPulse].default == false and rules[KEYS.c1.readyPulse].default == false, "the pulse is off by default")
Check(rules.pulseCombat.default == true and rules.pulseSize.default == 96 and rules.pulseHold.default == 0.5
    and rules.pulseY.default == 120, "the pulse's General settings and their defaults")
Check(KEYS.buf.readyPulse == nil and KEYS.bar.readyPulse == nil, "buff bars have no ready pulse")
-- The client's scale animation and its order, origin and hold.
local Widget = getmetatable(UIParent)
for _, name in ipairs({ "SetOrder", "SetScaleFrom", "SetScaleTo", "SetOrigin" }) do
    Widget[name] = Widget[name] or function(self, ...)
        self.calls[name] = (self.calls[name] or 0) + 1
    end
end
local setDuration = Widget.SetDuration
Widget.SetDuration = function(self, seconds)
    self.duration = seconds
    return setDuration(self, seconds)
end
local function Ready(texture, slot)
    C.Alerts.Ready({ slot = slot or "ess", family = 1, texture = texture, ov = C.EMPTY, key = "s" .. texture })
end
local function Combat(on)
    C.state.inCombat = on
end
-- The pulse frame is the one frame of UIParent with an animation group and a hold.
local function Pulse()
    local count, first = 0, nil
    for i = 1, #UIParent.children do
        local w = UIParent.children[i]
        if w.group and w.hold then
            count, first = count + 1, first or w
        end
    end
    return first, count
end
-- Off: nothing is made, however often a cooldown comes back.
Check(not C.views.ess.readyPulse and not C.views.c1.readyPulse, "no bar pulses by default")
Combat(true)
for i = 1, 50 do Ready(100 + i) end
Check(not Pulse(), "a bar without the pulse makes no frame")
-- On, out of combat: "Pulse only in combat" holds it back, still no frame.
config[KEYS.ess.readyPulse] = true
config.pulseSize, config.pulseY, config.pulseHold = 80, 150, 1.5
module:Refresh()
Run()
Check(C.views.ess.readyPulse == true and C.state.pulseCombat == true and C.state.pulseSize == 80 and C.state.pulseY == 150
    and C.state.pulseHold == 1.5, "the bar's switch and the General settings reach the view and the state")
Combat(false)
Ready(201)
Check(not Pulse(), "out of combat nothing pulses while 'Pulse only in combat' is on")
-- A bar without the switch stays silent even in combat.
Combat(true)
Ready(202, "uti")
Check(not Pulse(), "another bar makes no pulse")
-- In combat: one pooled frame, made now.
Combat(true)
Ready(301)
local frame, made = Pulse()
Check(frame and made == 1, "the first pulse makes one frame")
Check(frame.shown and frame.group.playing and frame.icon.tex == 301, "it shows the spell's icon and plays")
Check(frame.w == 80 and frame.h == 80 and frame.point[1] == "CENTER" and frame.point[2] == UIParent and frame.point[5] == 150,
    "size and place come from the General settings, in the screen center")
Check(frame.hold.duration == 1.5 and frame.strata == "HIGH" and not frame.scripts.OnUpdate, "hold time, layer, no OnUpdate")
Check(frame.calls.EnableMouse >= 1, "the pulse takes no clicks")
NoOnUpdate()
-- Three wait behind it; a fourth drops the oldest.
for _, id in ipairs({ 302, 303, 304, 305, 306 }) do Ready(id) end
Check(frame.icon.tex == 301, "a pulse that arrives while one plays waits")
local sizeCalls, placeCalls = frame.calls.SetSize, frame.calls.SetPoint
local function Finish()
    frame.group.playing = false
    frame.group.scripts.OnFinished(frame.group)
end
local shownIcons = {}
for _ = 1, 3 do
    Finish()
    shownIcons[#shownIcons + 1] = frame.icon.tex
    Check(frame.shown and frame.group.playing, "the next pulse starts when the last one has faded")
end
Check(table.concat(shownIcons, ",") == "304,305,306", "at most three wait, the oldest dropped first (" .. table.concat(shownIcons, ",") .. ")")
Finish()
Check(not frame.shown and not frame.group.playing, "the queue ran dry: the frame hides")
Check(frame.calls.SetSize == sizeCalls and frame.calls.SetPoint == placeCalls and frame.hold.calls.SetDuration == 1,
    "size, place and hold time are written once while they stay the same")
Check(select(2, Pulse()) == 1, "pulses reuse the frame")
-- A change of the settings applies to the next pulse, and only then.
config.pulseSize, config.pulseY, config.pulseHold = 120, 40, 0.25
module:Refresh()
Run()
Check(frame.w == 80 and frame.calls.SetSize == sizeCalls, "a settings change writes nothing by itself")
Combat(true)
Ready(307)
Check(frame.w == 120 and frame.h == 120 and frame.point[5] == 40 and frame.hold.duration == 0.25 and frame.icon.tex == 307,
    "the next pulse uses the new size, place and hold time")
-- A hidden bar still pulses, an entry without an icon pulses with the question mark.
config[KEYS.ess.vis] = CDM.VIS.HIDDEN
module:Refresh()
Run()
Finish()
Combat(true)
Ready(308)
Check(frame.shown and frame.icon.tex == 308, "a bar its conditions hide still pulses")
Finish()
Combat(true)
C.Alerts.Ready({ slot = "ess", family = 1, ov = C.EMPTY })
Check(frame.icon.tex == C.Const.QUESTION_ICON, "a spell without an icon pulses with the question mark")
-- Out of combat when the General switch allows it; aura entries never pulse.
Finish()
config.pulseCombat = false
module:Refresh()
Run()
Combat(false)
Ready(309)
Check(frame.shown and frame.icon.tex == 309, "'Pulse only in combat' off: pulses out of combat too")
Finish()
C.Alerts.Ready({ slot = "ess", family = 2, texture = 310, ov = C.EMPTY })
Check(not frame.shown, "buffs do not pulse")
-- The module lets go: the pulse on screen and the queue disappear.
Combat(false)
Ready(311)
Ready(312)
C.Alerts.ReleaseAll()
Check(not frame.shown and not frame.group.playing, "releasing the module stops the pulse")
Ready(313)
Check(frame.shown and frame.icon.tex == 313 and select(2, Pulse()) == 1, "the queue was cleared with it")
Finish()
Check(not frame.shown, "nothing waited behind it")
Widget.SetDuration = setDuration
module.active = false; module:Disable(); module.context:Release(); Run(5)
if #failures > 0 then error("suite_cdm_content_runtime_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_content_runtime_contract: " .. checks .. " checks passed")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
