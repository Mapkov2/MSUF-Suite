-- Best raid records survive a serialized SavedVariables reload and profile changes.
-- The selected completed encounter is restored only in its own raid/difficulty.
local root = assert(arg[1], "repository root required")
local mode = arg[2] or "all"
local secret = setmetatable({}, {
    __tostring = function() error("secret converted to text") end,
    __concat = function() error("secret concatenated") end,
    __lt = function() error("secret compared") end,
    __le = function() error("secret compared") end,
})
local function Public(value) return value ~= secret end
local function Text(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function Widget()
    local w = { shown = false }
    function w:SetPoint() end
    function w:SetHeight(value) self.height = value end
    function w:SetText(value) assert(Public(value)); self.text = value end
    function w:SetFormattedText(format, ...) self.format, self.args = format, { ... } end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetTextColor() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
end
local function Serialize(value, seen)
    assert(Public(value), "a secret entered the saved database")
    local kind = type(value)
    if kind == "number" then assert(Finite(value)); return string.format("%.17g", value) end
    if kind == "string" then return string.format("%q", value) end
    if kind == "boolean" or kind == "nil" then return tostring(value) end
    assert(kind == "table", "non-persistable value: " .. kind)
    seen = seen or {}
    assert(not seen[value], "cyclic saved data")
    seen[value] = true
    local keys, items = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        items[#items + 1] = "[" .. Serialize(key, seen) .. "]=" .. Serialize(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(items, ",") .. "}"
end
local function Save(session) return "return " .. Serialize(session.ns.RootDB) end
local function Session(saved, options)
    options = options or {}
    local self = { guid = options.guid or "Player-A", instanceID = 2000, difficulty = 16,
        inside = true, kind = "raid", now = 100, encounter = false }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.UnitGUID = function(unit) assert(unit == "player"); return self.guid end
    env.IsInInstance = function() return self.inside, self.kind end
    env.GetInstanceInfo = function()
        return "Test Raid", self.kind, self.difficulty, "Mythic", 20, 0, false, self.instanceID, 20
    end
    env.C_InstanceEncounter = { IsEncounterInProgress = function() return self.encounter end }
    env.GetDifficultyInfo = function(id) return id == 16 and "Mythic" or "Normal" end
    env.GetTime = function() return self.now end
    env.UnitExists = function() return false end
    env.UnitName = function() return nil end
    env.UnitHealthPercent = function() return nil end
    env.CurveConstants = { ScaleTo100 = {} }
    local ns = { Client = { isForever = false }, Public = Public, PublicText = Text, Finite = Finite,
        IsSecret = function(value) return value == secret end,
        IsCombatLocked = function() return false end,
        ProfileVariants = { CanMutate = function() return true end, OnActivated = function() end },
        OnProfileChanged = function() end,
        Finish = function(fn, ...) return true, fn(...) end,
        -- The HUD text style reader (catalog HUD.lua); no real fonts here.
        HUDTextArgs = function() end,
    }
    local S = { Public = Public, PublicText = Text, Finite = Finite, Text = function(value) return value end,
        GlobalFontPath = function() return "font" end, SetStyledFont = function() end,
        CreateFrame = function() return Widget() end, CreateFontString = function() return Widget() end,
        Dispatch = function(fn, ...) return fn(...) end,
        ClockText = function(value)
            if not Finite(value) then return "--:--" end
            return string.format("%02d:%02d", math.floor(value / 60), math.floor(value % 60))
        end,
    }
    ns.Suite = S
    local function Load(path, addon, namespace)
        local chunk = assert(loadfile(root .. "/" .. path))
        setfenv(chunk, env)
        chunk(addon, namespace)
    end
    Load("MSUF_Suite/Core/Database.lua", "MSUF_Suite", ns)
    Load("MSUF_Suite/Core/CharacterData.lua", "MSUF_Suite", ns)
    S.CharacterData = ns.CharacterData
    local stored = saved and assert(loadstring(saved))() or {
        schema = 1, activeProfile = "Main", profiles = { Main = { suite = {} }, Other = { suite = {} } },
    }
    assert(ns.Database.Initialize(stored))
    env.MSUFSuiteDB = ns.RootDB -- The startup publication the client writes at logout/reload.
    local private = { NS = ns, Suite = S }
    Load("MSUF_Suite_Modules/RaidRecords.lua", "MSUF_Suite_Modules", private)
    Load("MSUF_Suite_Modules/Raid.lua", "MSUF_Suite_Modules", private)
    local context = { events = {}, ticker = false }
    function context:Coalesce() return { Request = function(job) job.pending = true end } end
    function context:Event(event, handler) self.events[event] = handler end
    function context:RemoveEvent(event) self.events[event] = nil end
    function context:Ticker() self.ticker = true end
    function context:Cancel() self.ticker = false end
    self.ns, self.S, self.H = ns, S, S.Raid
    self.owner = { active = true, config = { showRaid = true }, content = Widget(), context = context }
    return self
end
local function Pull(session, success, duration, percent)
    local H, owner = session.H, session.owner
    assert(H.Start(owner, 800, "Twin Guardians", 16))
    if success == 0 then H.Stage(owner, "DBM", 3, 3) end
    session.now = session.now + duration
    H.End(owner, 800, "Twin Guardians", 16, 20, success,
        percent and { { remainingHealthPercent = percent, creatureName = "Guardian" } } or {})
end
local function Blank(session, label)
    local view = assert(session.owner.raid)
    assert(view.encounterID == nil and view.difficultyID == nil, label .. ": stale encounter restored")
    assert(view.best.text == "BEST PULL  --" and view.fastest.text == "FASTEST KILL  --:--",
        label .. ": another encounter's best was shown")
end
if mode ~= "restore" then
    local late = Session()
    late.guid = nil
    assert(late.H.Start(late.owner, 810, "Late identity", 16))
    late.guid, late.now = "Player-A", 120
    late.H.End(late.owner, 810, "Late identity", 16, 20, 1, {})
    local data = late.ns.CharacterData("objectives")
    assert(data.raidRecords and data.raidRecords["810:16"] and data.raidRecords["810:16"].fastest == 20,
        "late character identity left the new fastest kill in an unsaved fallback table")
end
if mode == "late" then print("Suite raid best persistence: late identity passed"); return end
local first = Session()
Pull(first, 0, 55, .25)
Pull(first, 1, 20)
local firstData = first.ns.CharacterData("objectives")
assert(firstData.raidRecords["800:16"].best.remaining == 25
    and firstData.raidRecords["800:16"].bestPhases.DBM.stage == 3
    and firstData.raidRecords["800:16"].fastest == 20, "real encounter-end best writers did not run")
local saved = Save(first)
-- An unreadable identity through encounter end retains only aggregate pending
-- records. The first later show merges them without weakening saved bests.
local pending = Session(saved)
pending.guid = nil
Pull(pending, 0, 55, .10)
Pull(pending, 1, 25)
local pendingData = pending.ns.RootDB.suiteCharacters["Player-A"].objectives
assert(pendingData.raidRecords["800:16"].best.remaining == 25,
    "unknown identity wrote a character's saved data before it became readable")
pending.guid = "Player-A"
assert(pending.H.Show(pending.owner))
local pendingRecord = pendingData.raidRecords["800:16"]
assert(pendingRecord.best.remaining == 10 and pendingRecord.bestPhases.DBM.remaining == 10
    and pendingRecord.fastest == 20, "pending merge lost a stronger wipe/phase or weakened fastest kill")
assert(pendingData.raidLastEncounter.encounterID == 800 and pending.owner.raid.pendingEncounter == nil,
    "pending completed context was not published once")
local once = Serialize(pendingData)
assert(pending.H.Show(pending.owner))
assert(Serialize(pendingData) == once and pending.owner.raid.records == pendingData.raidRecords,
    "settled show remerged or detached pending records")
local weaker = Session(saved)
weaker.guid = nil
assert(weaker.H.Start(weaker.owner, 800, "Twin Guardians", 16))
weaker.H.Stage(weaker.owner, "DBM", 2, 2)
weaker.now = weaker.now + 50
weaker.H.End(weaker.owner, 800, "Twin Guardians", 16, 20, 0,
    { { remainingHealthPercent = .80, creatureName = "Guardian" } })
Pull(weaker, 1, 15)
weaker.guid = "Player-A"
assert(weaker.H.Show(weaker.owner))
local merged = weaker.ns.CharacterData("objectives").raidRecords["800:16"]
assert(merged.best.remaining == 25 and merged.bestPhases.DBM.stage == 3 and merged.fastest == 15,
    "pending merge weakened saved wipe/phase or discarded the faster pending kill")
-- Once bound, a transient unavailable accessor must not detach the real store.
local transient = Session(saved)
assert(transient.H.Show(transient.owner))
local bound = transient.owner.raid.records
transient.guid = nil
Pull(transient, 1, 12)
assert(transient.owner.raid.records == bound and bound["800:16"].fastest == 12,
    "temporary identity loss detached the already durable store")
assert(transient.ns.RootDB.suiteCharacters["Player-A"].objectives.raidRecords == bound,
    "bound updates no longer belong to SavedVariables")
local active = Session(saved)
assert(active.H.Start(active.owner, 800, "Twin Guardians", 16))
local pull = active.owner.raid.pull
active.H.Stage(active.owner, "DBM", 2, 2)
active.encounter = true
assert(active.H.Show(active.owner))
assert(active.owner.raid.pull == pull and active.owner.raid.stage == 2 and active.owner.context.ticker,
    "same-instance show interrupted the active pull")
active.instanceID = 2001
assert(active.H.Show(active.owner))
Blank(active, "active pull moved to another raid")
assert(active.owner.raid.pull == nil and not active.owner.context.ticker
    and active.owner.context.events.UNIT_HEALTH == nil,
    "cross-instance show retained the old pull or its health/timer work")
local reloaded = Session(saved)
assert(reloaded.ns.RootDB ~= first.ns.RootDB and reloaded.owner ~= first.owner, "reload reused live objects")
assert(reloaded.H.Show(reloaded.owner))
local view = reloaded.owner.raid
assert(view.encounterID == 800 and view.difficultyID == 16 and view.name.text == "Twin Guardians",
    "reload forgot the saved encounter selection despite retaining best values")
assert(view.best.text:find("PHASE 3", 1, true) and view.best.text:find("25.0%", 1, true)
    and view.fastest.text == "FASTEST KILL  00:20", "reload did not repaint persisted bests")
assert(view.pull == nil and view.stage == nil and view.lastTime == nil and view.lastResult == nil
    and view.elapsed.text == "--:--" and view.current.text == "LAST PULL  --"
    and view.phase.text == "PHASE  --" and not reloaded.owner.context.ticker,
    "restoring bests resurrected a live or completed pull")
assert(reloaded.ns.Database.Activate("Other"))
reloaded.H.Stop(reloaded.owner)
assert(reloaded.H.Show(reloaded.owner))
assert(reloaded.owner.raid.fastest.text == "FASTEST KILL  00:20", "profile change lost character bests")
local other = Session(saved, { guid = "Player-B" })
assert(other.H.Show(other.owner)); Blank(other, "other character")
for _, field in ipairs({ "instanceID", "difficulty" }) do
    local changed = Session(saved)
    changed[field] = field == "instanceID" and 2001 or 14
    assert(changed.H.Show(changed.owner)); Blank(changed, "different " .. field)
    local hidden = Session(saved)
    hidden[field] = secret
    assert(hidden.H.Show(hidden.owner)); Blank(hidden, "secret " .. field)
    hidden[field] = nil
    assert(hidden.H.Show(hidden.owner)); Blank(hidden, "missing " .. field)
end
-- Zone transitions can call Show again without stopping the reusable view.
reloaded.instanceID = 2001
assert(reloaded.H.Show(reloaded.owner)); Blank(reloaded, "reused view in another raid")
local engaged = Session(saved)
engaged.encounter = true
assert(engaged.H.Show(engaged.owner)); Blank(engaged, "reload into an unknown running encounter")
engaged.encounter = secret
assert(engaged.H.Show(engaged.owner)); Blank(engaged, "secret encounter state")
local legacy = Session(saved)
legacy.ns.CharacterData("objectives").raidLastEncounter = nil
local legacyBefore = Serialize(legacy.ns.CharacterData("objectives").raidRecords)
assert(legacy.H.Show(legacy.owner)); Blank(legacy, "legacy records without context")
assert(Serialize(legacy.ns.CharacterData("objectives").raidRecords) == legacyBefore, "legacy bests were mutated")
assert(legacy.H.Start(legacy.owner, 800, "Twin Guardians", 16))
assert(legacy.owner.raid.fastest.text == "FASTEST KILL  00:20", "legacy bests unavailable on next observed encounter")
-- An unavailable result cannot replace the descriptor of a completed encounter.
local unavailable = Session(saved)
assert(unavailable.H.Start(unavailable.owner, 801, "Other boss", 16))
unavailable.H.End(unavailable.owner, 801, "Other boss", 16, 20, secret, {})
local completed = unavailable.ns.CharacterData("objectives").raidLastEncounter
assert(completed and completed.encounterID == 800, "unknown result replaced the completed encounter selection")
-- The end event can precede the zone/show reconciliation. Never stamp the
-- old pull with the new raid's identity, or invent a scope unknown at start.
local movedEnd = Session(saved)
assert(movedEnd.H.Start(movedEnd.owner, 801, "Departed boss", 16))
movedEnd.instanceID, movedEnd.now = 2001, 125
movedEnd.H.End(movedEnd.owner, 801, "Departed boss", 16, 20, 1, {})
local movedSelection = movedEnd.ns.CharacterData("objectives").raidLastEncounter
assert(movedSelection.encounterID == 800 and movedSelection.instanceID == 2000,
    "end before zone reconciliation associated the old encounter with the new raid")
local unknownStart = Session(saved)
unknownStart.instanceID = nil
assert(unknownStart.H.Start(unknownStart.owner, 801, "Unknown origin", 16))
unknownStart.instanceID, unknownStart.now = 2000, 125
unknownStart.H.End(unknownStart.owner, 801, "Unknown origin", 16, 20, 1, {})
assert(unknownStart.ns.CharacterData("objectives").raidLastEncounter.encounterID == 800,
    "an encounter with unknown start scope invented a saved raid association")
-- A restored idle selection is no longer current once the client reports a
-- running encounter that this view never observed through ENCOUNTER_START.
local unseen = Session(saved)
assert(unseen.H.Show(unseen.owner))
assert(unseen.owner.raid.encounterID == 800, "saved idle selection did not restore")
unseen.encounter = true
assert(unseen.H.Show(unseen.owner))
Blank(unseen, "unobserved encounter after idle restore")
assert(not firstData.raidHistory and not firstData.history, "best-only storage grew a pull history")
print("Suite raid best persistence: serialized reload, best-only display, owner binding and context isolation passed")
