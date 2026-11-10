local root = assert(arg[1], "repository root required")
local runtimePath = arg[2] or root .. "/MSUF_Suite_QualityOfLife/LootRolls.lua"
local dataPath = arg[3] or root .. "/MSUF_Suite_QualityOfLife/LootRollData.lua"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local FrameMethods = {}
function FrameMethods:IsShown() return self.shown end
function FrameMethods:IsVisible() return self.shown end
function FrameMethods:SetShown(value) assert(not self.native, "native visibility replaced"); self.shown = value end
function FrameMethods:Show() assert(not self.native, "native Show called"); self.shown = true end
function FrameMethods:Hide() assert(not self.native, "native Hide would unregister roll events"); self.shown = false end
function FrameMethods:IsProtected() return self.protected end
function FrameMethods:IsMouseEnabled() return self.mouse end
function FrameMethods:EnableMouse(value) self.mouse = value end
function FrameMethods:GetParent() return self.parent end
function FrameMethods:SetParent(value) self.parent = value end
function FrameMethods:GetAlpha() return self.alpha end
function FrameMethods:SetAlpha(value) self.alpha = value end
function FrameMethods:SetScript(event, callback) self.scripts[event] = callback end
function FrameMethods:HookScript(event, callback)
    local callbacks = self.hooks[event]
    if not callbacks then callbacks = {}; self.hooks[event] = callbacks end
    callbacks[#callbacks + 1] = callback
end
local function Frame(native, parent)
    return setmetatable({ native = native, parent = parent, shown = false, protected = false,
        mouse = true, alpha = 1, scripts = {}, hooks = {}, rollID = 0 }, { __index = FrameMethods })
end

local function Setup(forever, prepare)
    local state = { records = {}, history = {}, activeIDs = {}, encounters = {}, events = {}, calls = {},
        muted = {}, properties = {}, native = {}, targets = {}, ticks = 0, paints = 0, pad = false }
    state.secret = setmetatable({}, { __tostring = function() error("secret formatted") end })
    local function Public(value) return not rawequal(value, state.secret) end
    local function Finite(value)
        return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    local S = { Public = Public, Finite = Finite, editMode = false,
        Text = function(value) return value end, GamepadUI = function() return state.pad end }
    S.PublicText = function(value)
        return Public(value) and type(value) == "string" and value ~= "" and value or nil
    end
    local NS = { Client = { isForever = forever }, AnchorPoints = { [5] = "CENTER" },
        Safety = { IsForbidden = function(frame) return frame.forbidden == true end },
        Dispatch = function(fn, ...) return fn(...) end }
    local clock = Support.Clock(100)
    state.clock, state.S = clock, S
    UIParent = Frame(false)
    UIParent.shown = true
    local muteParent = Frame(false)
    muteParent.shown = true
    local buttonKeys = { "NeedButton", "GreedButton", "TransmogButton", "DisenchantButton", "PassButton" }
    for i = 1, 4 do
        local native = Frame(true, UIParent)
        native.IconFrame = Frame(true, native)
        local owner = native
        if forever then
            owner = {}
            native.LootButtonContainer = owner
        end
        state.targets[native] = { native, native.IconFrame }
        for _, key in ipairs(buttonKeys) do
            owner[key] = Frame(true, native)
            state.targets[native][#state.targets[native] + 1] = owner[key]
        end
        -- Actual Blizzard parentArray does not need to have run OnShow yet.
        owner.LootButtons = nil
        state.native[i], _G["GroupLootFrame" .. i] = native, native
    end
    GamepadGroupLootRollFrame = Frame(true, UIParent)
    GamepadGroupLootRollFrame.mouse, GamepadGroupLootRollFrame.shown = true, true
    Enum = { EncounterLootDropRollState = {
        NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5,
    } }
    RAID_CLASS_COLORS = { MAGE = { colorStr = "ff40c7eb" } }
    GetActiveLootRollIDs = function() return state.activeIDs end
    GetLootRollItemInfo = function(id)
        local record = state.records[id]
        if not record or not record.ready then return nil end
        return 1000 + id, "Item " .. id, 1, 4, true, record.need, record.greed, record.disenchant,
            nil, nil, nil, nil, record.transmog
    end
    GetLootRollItemLink = function(id) return state.records[id] and state.records[id].link end
    GetLootRollTimeLeft = function(id)
        local record = state.records[id]
        return record and math.max(0, (record.endsAt - clock.now) * 1000)
    end
    C_Item = {
        GetItemInfo = function(link) return "Cached " .. link, link, 4, state.itemLevel, nil, nil, nil, nil, nil, 1000 end,
        GetDetailedItemLevelInfo = function() return state.itemLevel end,
    }
    state.itemLevel = 120
    C_LootHistory = {
        GetSortedInfoForDrop = function(encounter, key)
            return state.history[encounter] and state.history[encounter][key]
        end,
        GetSortedDropsForEncounter = function(encounter)
            local result = {}
            for _, entry in pairs(state.history[encounter] or {}) do result[#result + 1] = entry end
            return result
        end,
        GetAllEncounterInfos = function() return state.encounters end,
    }
    RollOnLoot = function(id, choice)
        state.calls[#state.calls + 1] = { id, choice }
        if state.cancelInsideCall then state:Cancel(id) end
    end
    S.Install = function(id, module) Check(id == "lootRolls", "runtime owns the dedicated module"); state.module = module end
    S.RegisterOwnedMover = function(id, element, spec)
        Check(id == "lootRolls" and element == "lootrolls", "uses shared mover registration")
        state.mover = spec
    end
    local View = {}
    function View.Create(module) module.host = module.host or Frame(false, module.previewParent or UIParent) end
    function View.Paint(module)
        View.Create(module)
        state.paints = state.paints + 1
        state.lastEntries = module.visibleEntries
    end
    function View.Tick() state.ticks = state.ticks + 1 end
    local P = { NS = NS, Suite = S, LootRollView = View }
    assert(loadfile(dataPath))("MSUF_Suite_QualityOfLife", P)
    assert(loadfile(runtimePath))("MSUF_Suite_QualityOfLife", P)
    local M = assert(state.module)
    M.config = { maxRows = 6, resultSeconds = 2, showResults = true, showItemLevel = true, point = 5 }
    M.context = Support.ModuleTimers(root, S, NS)("lootRolls", M, {
        Event = function(_, event, callback, options)
            Check(Support.InCombatOption(options), "loot events need the explicit in-combat route")
            state.events[event] = Support.EventCallback(callback)
        end,
        RemoveEvent = function(_, event) state.events[event] = nil end,
        Mute = function(_, frame)
            if frame.protected or frame.forbidden then return false end
            state.muted[frame] = state.muted[frame] or frame.parent
            frame.parent = muteParent
            return true
        end,
        Unmute = function(_, frame)
            if state.muted[frame] then frame.parent = state.muted[frame]; state.muted[frame] = nil end
        end,
        UnprotectedProperty = function(_, frame, getter, setter, value)
            if frame.protected or frame.forbidden then return false end
            state.properties[frame] = state.properties[frame] or {}
            local properties = state.properties[frame]
            properties[setter] = properties[setter] or { getter = getter, before = frame[getter](frame) }
            properties[setter].applied = value
            frame[setter](frame, value)
            return true
        end,
        RestoreProperty = function(_, frame, setter)
            local properties = state.properties[frame]
            local entry = properties and properties[setter]
            if not entry then return end
            if frame[entry.getter](frame) == entry.applied then frame[setter](frame, entry.before) end
            properties[setter] = nil
        end,
    })
    function state:Emit(event, ...)
        if self.events[event] then self.events[event](M, event, ...) end
    end
    function state:Drain() clock.Frame(0) end
    function state:Frame(seconds)
        clock.Frame(seconds)
        local update = M.host and M.host.shown and M.host.scripts.OnUpdate
        if update then update(M.host, seconds) end
        clock.Frame(0)
    end
    function state:SetRoll(id, link, slot, ready)
        self.records[id] = { link = link or "item:" .. id, endsAt = clock.now + 60, ready = ready ~= false,
            need = true, greed = true, disenchant = false, transmog = false }
        self.activeIDs[#self.activeIDs + 1] = id
        if slot then
            local frame = self.native[slot]
            frame.rollID, frame.shown = id, true
        end
    end
    function state:Start(id, link, slot, ready)
        self:SetRoll(id, link, slot, ready)
        self:Emit("START_LOOT_ROLL", id, 60000)
        if slot then for _, callback in ipairs(self.native[slot].hooks.OnShow or {}) do callback(self.native[slot]) end end
        self:Drain()
    end
    function state:Cancel(id)
        for i = #self.activeIDs, 1, -1 do if self.activeIDs[i] == id then table.remove(self.activeIDs, i) end end
        for _, frame in ipairs(self.native) do if frame.rollID == id then frame.shown = false end end
        self:Emit("CANCEL_LOOT_ROLL", id)
        self:Drain()
    end
    function state:Drop(key, link, winner)
        self.history[1] = self.history[1] or {}
        local entry = { itemHyperlink = link, rollInfos = {
            { playerName = "Participant", playerClass = "MAGE", state = 3 },
        }, startTime = clock.now, duration = 60 }
        entry[forever and "lootListKey" or "lootListID"] = key
        if winner then entry.winner = { playerName = winner, state = 3, roll = 98 } end
        self.history[1][key] = entry
        self.encounters = { { encounterID = 1, startTime = 100 } }
        return entry
    end
    function state:Publish(key) self:Emit("LOOT_HISTORY_UPDATE_DROP", 1, key); self:Drain() end
    function state:Disable()
        M.active = false
        M:Disable()
        M.context:CancelTimers()
        self.events = {}
    end
    function state:Enable() M.active = true; M:Enable(); self:Drain() end
    if prepare then prepare(state) end
    state:Enable()
    return state, M
end

local function Muted(state, slot, wanted)
    local frame = state.native[slot]
    Check((state.muted[frame] ~= nil) == wanted, "native presentation ownership for slot " .. slot)
    for _, control in ipairs(state.targets[frame]) do
        Check(control.mouse == not wanted, "restore/suppress every child click target for slot " .. slot)
    end
end

for _, forever in ipairs({ false, true }) do
    local state, M = Setup(forever)
    Check(not M.host.shown and not M.host.scripts.OnUpdate and not state.events.GET_ITEM_INFO_RECEIVED,
        "idle module must not show rows, poll or watch item data")
    Check(#state.calls == 0 and not state.mover, "enabling never rolls or registers a mover twice")
    M:RegisterMovers()
    Check(state.mover and state.mover.getFrame() == M.host, "mover points at the owned stack")
    state:Start(1, nil, 1)
    local entry = M.rolls[1]
    Check(M.host.shown and #M.visibleEntries == 1 and entry.itemLevel == 120, "new roll renders through real data")
    Muted(state, 1, true)
    Check(state.native[1].shown and GamepadGroupLootRollFrame.mouse, "native roll lifecycle and gamepad remain intact")
    Check(#state.calls == 0, "new loot never makes an automatic decision")
    state.records[1].need = false
    M:Choose(entry, 1)
    M:Choose(entry, 4)
    M:Choose(entry, 99)
    M:Choose(entry, state.secret)
    M:Choose({ rollID = 1 }, 2)
    Check(#state.calls == 0, "manual actions re-read eligibility and reject unavailable, invalid or foreign choices")
    M:Choose(entry, 2)
    Check(#state.calls == 1 and state.calls[1][1] == 1 and state.calls[1][2] == 2
        and not entry.choice and not entry.cancelled, "native confirmation remains pending after requested roll")
    state.records[1].need = true
    M:Choose(entry, 1)
    Check(#state.calls == 2 and not entry.choice, "cancelled native confirmation leaves choices retryable")
    state:Cancel(1)
    Check(entry.choice == 1 and entry.cancelled, "native cancel event commits the last requested choice")
    Muted(state, 1, false)
    state:Drop(11, "item:1", "Winner")
    state:Publish(11)
    Check(entry.finished and entry.status == "winner" and entry.statusName == "Winner", "unambiguous result reaches same row")
    state:Frame(2.1)
    Check(#M.order == 0 and not M.host.shown, "configured result timeout removes winner and idle stack")
    state:Start(2, nil, 2)
    state.pad = true
    state:Emit("INPUT_DEVICE_INTERFACE_TRANSITION")
    state:Drain()
    Check(not M.host.shown and not M.host.scripts.OnUpdate, "gamepad takes native input with no custom polling")
    Muted(state, 2, false)
    local calls = #state.calls
    M:Choose(M.rolls[2], 1)
    Check(#state.calls == calls, "gamepad fallback cannot invoke custom actions")
    state.pad = false
    state:Emit("INPUT_DEVICE_INTERFACE_TRANSITION")
    state:Drain()
    Muted(state, 2, true)
    state:Disable()
    Muted(state, 2, false)
    Check(not M.host.shown and not M.host.scripts.OnUpdate, "disable clears owned timer and stack")
    local paints = state.paints
    state:Frame(1)
    Check(state.paints == paints, "disabled late work is inert")
    state:Enable()
    Check(M.rolls[2] and #M.order == 1, "re-enable seeds the still-active roll once")
    Muted(state, 2, true)
    state:Disable()

    state, M = Setup(forever)
    state:Start(7, "item:identical", 1)
    state:Start(8, "item:identical", 2)
    state:Drop(71, "item:identical", "Winner A")
    state:Drop(72, "item:identical", "Winner B")
    state:Publish(71)
    state:Publish(72)
    Check(not M.rolls[7].finished and not M.rolls[8].finished
        and not M.rolls[7].statusName and not M.rolls[8].statusName,
        "identical hyperlinks never assign arbitrary winners to live roll IDs")
    state:Cancel(7)
    state:Cancel(8)
    local results = {}
    for _, visible in ipairs(M.visibleEntries) do
        if visible.finished then results[visible.statusName] = true; Check(not visible.rollID, "ambiguous results use history identity") end
    end
    Check(results["Winner A"] and results["Winner B"], "each ambiguous history result remains visible independently")
    state:Frame(2.1)
    Check(not M.host.shown and #M.historyOrder == 0, "independent results expire without active roll rows")

    state, M = Setup(forever)
    M.config.maxRows = 1
    state:Start(1, nil, 1)
    state:Start(2, nil, 2)
    Muted(state, 1, true)
    Muted(state, 2, false)
    Check(#M.visibleEntries == 1, "custom stack overflow preserves another native decision")
    for id = 3, 52 do state:Start(id) end
    Check(#M.order <= 48 and not M.rolls[52], "runtime history stays bounded without hiding unrepresented rolls")
    state.activeIDs = {}
    state:Emit("CANCEL_ALL_LOOT_ROLLS")
    state:Drain()
    Check(#M.order == 0 and not M.host.shown, "cancel-all cannot be resurrected by an old expiry or history")
    Muted(state, 1, false)
    Muted(state, 2, false)
    state:Disable()

    state, M = Setup(forever)
    state.itemLevel = nil
    state:Start(20, nil, 1, false)
    Check(not M.rolls[20] and not M.host.shown and state.events.GET_ITEM_INFO_RECEIVED,
        "late native item data keeps original input available")
    Muted(state, 1, false)
    state.records[20].ready = true
    state:Frame(.21)
    Check(M.rolls[20] and M.host.shown, "bounded initial retry acquires arriving item identity")
    Muted(state, 1, true)
    state.itemLevel = 150
    state:Emit("GET_ITEM_INFO_RECEIVED", 20, true)
    state:Drain()
    Check(M.rolls[20].itemLevel == 150 and not state.events.GET_ITEM_INFO_RECEIVED,
        "later item level updates row then releases cache events")
    state:Disable()

    state, M = Setup(forever, function(seed)
        seed:SetRoll(30, "item:seeded", 1)
        seed:Drop(301, "item:old", "Old winner")
        seed:Drop(302, "item:seeded")
    end)
    Check(M.rolls[30] and M.rolls[30].counts and M.rolls[30].counts[2] == 1,
        "unfinished pre-enable history seeds the active decision")
    for _, visible in ipairs(M.visibleEntries) do Check(visible.statusName ~= "Old winner", "old completed history is not replayed at enable") end
    state:Publish(301)
    for _, visible in ipairs(M.visibleEntries) do Check(visible.statusName ~= "Old winner", "ignored old result stays ignored on updates") end
    state:Disable()

    state, M = Setup(forever)
    state.S.editMode = true
    M:Refresh()
    Check(#M.visibleEntries == 3 and #M.order == 0, "edit mode gets three separate noninteractive examples")
    local samples = M.sampleEntries
    M:Choose(M.visibleEntries[1], 1)
    M:Refresh()
    M:Refresh()
    Check(#M.visibleEntries == 3 and #samples == 3 and #state.calls == 0,
        "repeated preview refresh does not clear or activate its samples")
    state:Start(40, nil, 1)
    Check(#samples == 3 and #M.order == 1, "real arrival does not mutate example buffer")
    Muted(state, 1, false)
    state.S.editMode = false
    M:Refresh()
    Check(#M.visibleEntries == 1 and M.visibleEntries[1] == M.rolls[40], "leaving edit mode restores only live entries")
    Muted(state, 1, true)
    state:Disable()

    state, M = Setup(forever)
    state:Drop(99, "item:independent", "Fresh winner")
    state:Publish(99)
    Check(M.host.shown and #M.order == 0 and M.host.scripts.OnUpdate,
        "a new independent result has a running expiry even without active rolls")
    state:Frame(2.1)
    Check(not M.host.shown and not M.host.scripts.OnUpdate and #M.historyOrder == 0, "standalone result expiry stops timer")
    state:Publish(99)
    Check(not M.host.shown and #M.historyOrder == 0, "expired completed history is not replayed by a repeated update")
    state:Start(50, nil, 1)
    local beforeTicks = state.ticks
    for i = 1, 1000 do state:Frame(.001) end
    Check(state.ticks - beforeTicks <= 11 and state.ticks > beforeTicks, "countdown painting is throttled instead of per-frame")
    state:Disable()

    state, M = Setup(forever)
    state:Start(61, "item:declined", 1)
    M:Choose(M.rolls[61], 1)
    state:Cancel(61)
    local declined = state:Drop(610, "item:declined")
    declined.rollInfos[2] = { playerName = "Self", playerClass = "MAGE", state = 5, isSelf = true }
    state:Publish(610)
    Check(M.rolls[61].choice == 0, "native history overrides a declined provisional Need request with actual Pass")
    state:Disable()
end
print("PASS loot-roll controller: " .. checks .. " checks on Retail and Forever with real data/timers")
