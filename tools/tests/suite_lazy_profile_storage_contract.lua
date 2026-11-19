local root = assert(arg[1])
local combat = false
local Suite = {
    IsCombatLocked = function() return combat end,
    InCombat = function() return combat end,
    IsSecret = function() return false end,
    Dispatch = function(callback, ...) return callback(...) end,
    Finish = function(callback, ...) return true, callback(...) end,
    OnProfileChanged = function() end,
    ProfileVariants = { CanMutate = function() return true end, OnActivated = function() end },
}

-- An isolated self-contained codec fixture, with no retained source tables.
local function Literal(value)
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) == "string" then return string.format("%q", value) end
    local fields = {}
    for key, child in pairs(value) do fields[#fields + 1] = "[" .. Literal(key) .. "]=" .. Literal(child) end
    return "{" .. table.concat(fields, ",") .. "}"
end

local decodes, encoding, refuseActivation = 0, true, false
local function Encode(profile)
    if profile.fixtureUnrepresentable then profile = { suite = profile.suite } end
    return "MSUF3:" .. Literal(profile)
end
local function Decode(payload)
    decodes = decodes + 1
    local read = loadstring("return " .. payload:sub(7))
    return read and read()
end
C_EncodingUtil = {
    SerializeCBOR = Encode, DeserializeCBOR = Decode, CompressString = Encode, DecompressString = Decode,
    EncodeBase64 = Encode, DecodeBase64 = Decode,
}
Suite.ProfileIO = {
    StorageCodec = function() if encoding then return Encode, Decode end end,
    RememberNameplateCVars = function() end,
    ActivateNameplateProfile = function() return not refuseActivation, "native activation refused" end,
}
local pending = {}
C_Timer = { After = function(delay, callback)
    assert(delay > 0, "legacy migration should be paced between frames")
    pending[#pending + 1] = callback
end }
local eventFrames = {}
function CreateFrame()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, callback) self.onEvent = callback end
    eventFrames[#eventFrames + 1] = frame
    return frame
end
local function Event(event)
    local observed = 0
    for _, frame in ipairs(eventFrames) do
        if frame.events[event] then
            frame.onEvent(frame, event)
            observed = observed + 1
        end
    end
    return observed
end

local function Tick()
    local callback = assert(table.remove(pending, 1))
    callback()
end
local function Drain()
    while #pending > 0 do Tick() end
end

local storage = loadfile(root .. "/MSUF_Suite/Core/ProfileStorage.lua")
if storage then storage("MSUF_Suite", Suite) end
assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", Suite)
local DB = Suite.Database

local function Profile(size)
    return { suite = { schema = 1, modules = { minimap = { size = size, enabled = false } } },
        moduleRuntime = { [9001] = "kept", [2] = { verbose = false } } }
end

local live, cold, older, unusual = Profile(123), Profile(234), Profile(345), Profile(456)
unusual.fixtureUnrepresentable = true
older.suite.modules.castbarArt = { texture = "before migration" }
local disk = { schema = 1, activeProfile = "Live",
    profiles = { Live = live, Cold = cold, Other = Profile(222), Older = older, Unusual = unusual },
    chatHistory = { lines = { "owned outside profiles" } },
}
assert(DB.Initialize(disk))
local store = Suite.RootDB
assert(Suite.DB == store.profiles.Live and Suite.DB ~= live and store.chatHistory == disk.chatHistory)
assert(type(store.profiles.Cold) == "table" and #pending == 1, "legacy storage never scheduled bounded packing")
combat = true
Tick()
assert(eventFrames[1].events.PLAYER_REGEN_ENABLED and #pending == 0 and decodes == 0,
    "profile packing did work during combat or kept polling")
combat = false
assert(Event("PLAYER_REGEN_ENABLED") == 1)
assert(not eventFrames[1].events.PLAYER_REGEN_ENABLED and #pending == 1, "leaving combat did not resume profile packing")
Tick()
assert(#pending == 1)
Drain()
assert(store.schema == 1 and type(store.profiles.Cold) == "string" and type(store.profiles.Other) == "string",
    "inactive profiles still occupy tables after migration")
assert(type(store.profiles.Older) == "table" and type(store.profiles.Unusual) == "table",
    "packing discarded a legacy value or a non-roundtripping field")
assert(type(disk.profiles.Cold) == "table" and store.profiles.Live == Suite.DB,
    "migration rewrote its input or detached the active profile")

decodes = 0
assert(DB.HasProfile("Cold") and not DB.HasProfile("Typo") and decodes == 0)
local projection = assert(DB.ReadProfile("Cold"))
assert(projection.suite.modules.minimap.enabled == false and projection.moduleRuntime[9001] == "kept")
assert(type(store.profiles.Cold) == "string" and decodes == 1, "read-only export pinned an inactive profile")

-- External profile sync writes through a borrowed table even after the old
-- packing timer has run or the active profile has been switched.
local borrowed = assert(DB.GetProfile("Cold"))
assert(DB.GetProfile("Cold") == borrowed and store.profiles.Cold == borrowed)
borrowed.suite.modules.minimap.size = 777
assert(store.profiles.Cold.suite.modules.minimap.size == 777)
DB.CompactInactive("Cold")
Drain()
borrowed.suite.modules.minimap.size = 778
assert(store.profiles.Cold == borrowed and DB.ReadProfile("Cold").suite.modules.minimap.size == 778,
    "a write through an editable profile reference was lost after a packing tick")

local before = Suite.DB
refuseActivation = true
assert(not DB.Activate("Cold") and Suite.DB == before and DB.GetActiveProfileName() == "Live")
Drain()
assert(store.profiles.Cold == borrowed)
refuseActivation = false
assert(DB.Activate("Cold") and Suite.DB == store.profiles.Cold and Suite.DB.suite.modules.minimap.size == 778)
Drain()
before.suite.modules.minimap.size = 125
assert(store.profiles.Live == before and DB.ReadProfile("Live").suite.modules.minimap.size == 125,
    "a previous active profile was replaced while runtime still held its table")
local supplied = Profile(210)
DB.StoreProfile("Supplied", supplied)
Drain()
supplied.suite.modules.minimap.size = 211
assert(store.profiles.Supplied == supplied and DB.ReadProfile("Supplied").suite.modules.minimap.size == 211)

local packedLive, packedOther = Encode(Profile(123)), store.profiles.Other
local damaged = "MSUF3:invalid payload"
store.profiles.Damaged = damaged
assert(DB.HasProfile("Damaged") and not DB.Activate("Damaged") and not DB.Create("Damaged"))
assert(store.profiles.Damaged == damaged and Suite.DB == store.profiles.Cold)

assert(Event("PLAYER_LOGOUT") == 1)
assert(DB.Initialize(store) and DB.ReadProfile("Live").suite.modules.minimap.size == 125
    and DB.ReadProfile("Cold").suite.modules.minimap.size == 778,
    "a late write through a held table was missing after reload")
Drain()

-- The format written by the former current development build (schema 2).
local reloaded = { schema = 2, activeProfile = "Live", profiles = {
    Live = packedLive, Other = packedOther, Damaged = damaged, Plain = Profile(333),
} }
decodes = 0
assert(DB.Initialize(reloaded) and decodes == 1, "reloading decoded profiles other than the active one")
Drain()
assert(type(Suite.RootDB.profiles.Other) == "string" and Suite.RootDB.profiles.Damaged == damaged)
local opened = Suite.RootDB
DB.GetProfile("Plain").suite.modules.minimap.size = 334
combat = true
assert(Event("ADDONS_UNLOADING") == 1)
-- A later logout listener still writes through the active profile table.
Suite.DB.suite.modules.minimap.size = 124
assert(Event("PLAYER_LOGOUT") == 1)
Drain()
combat = false
assert(opened.schema == 1 and opened.profiles.Live.suite.modules.minimap.size == 124
    and opened.profiles.Other.suite.modules.minimap.size == 222
    and opened.profiles.Plain.suite.modules.minimap.size == 334
    and opened.profiles.Damaged == nil and opened.recoveryPackedProfiles.Damaged == damaged
    and opened.profiles.Live == Suite.DB, "logout exported broken old-format data or discarded an unreadable blob")

if arg[2] then
    local previousSuite = {}
    assert(loadfile(arg[2] .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", previousSuite)
    assert(previousSuite.Database.Initialize(opened), "the exact older Suite rejected the materialized root")
    local previous = previousSuite.RootDB
    assert(previous.profiles.Live.suite.modules.minimap.size == 124
        and previous.profiles.Plain.suite.modules.minimap.size == 334
        and previous.profiles.Other.suite.modules.minimap.size == 222
        and previous.recoveryPackedProfiles.Damaged == damaged, "the old reader lost settings or unknown recovery data")
end

reloaded.activeProfile = "Damaged"
decodes = 0
assert(DB.Initialize(reloaded) and DB.GetActiveProfileName() == "Live" and decodes >= 2,
    "an unreadable active profile stopped the other profiles from starting")
assert(Suite.RootDB.profiles.Damaged == damaged)
Drain()
local corruptRoot = { schema = 2, activeProfile = "Damaged", profiles = { Damaged = damaged } }
local current = Suite.RootDB
assert(not DB.Initialize(corruptRoot) and Suite.RootDB == current and corruptRoot.profiles.Damaged == damaged,
    "an all-corrupt packed store was overwritten")

encoding = false
local priorDecodes = decodes
assert(DB.Initialize(reloaded), "an unavailable host codec blocked readable profiles")
local reduced = Suite.RootDB
assert(Event("ADDONS_UNLOADING") == 1)
assert(reduced.schema == 1 and Suite.DB == reduced.profiles.Plain and decodes == priorDecodes
    and reduced.recoveryPackedProfiles.Live == packedLive and reduced.recoveryPackedProfiles.Other == packedOther
    and reloaded.profiles.Live == packedLive, "no-codec recovery rewrote the original or discarded packed records")
assert(DB.HasProfile("Live") and not DB.Create("Live"), "a missing codec released the reserved saved profile name")

-- An old build can write a plain entry under a reserved name. Preserve both
-- versions rather than silently replacing either when the codec returns.
reduced.profiles.Live = Profile(888)
encoding = true
assert(DB.Initialize(reduced))
local recovered = Suite.RootDB
assert(DB.GetProfile("Other").suite.modules.minimap.size == 222 and DB.GetProfile("Live").suite.modules.minimap.size == 888)
assert(recovered.recoveryPackedProfiles.Live == packedLive)
assert(Event("PLAYER_LOGOUT") == 1 and recovered.recoveryPackedProfiles.Live == packedLive)
assert(DB.Delete("Live") and recovered.recoveryPackedProfiles.Live == packedLive,
    "deleting a visible collision erased a distinct parked profile")
assert(DB.Initialize(recovered))
assert(DB.GetProfile("Live").suite.modules.minimap.size == 123
    and not (Suite.RootDB.recoveryPackedProfiles and Suite.RootDB.recoveryPackedProfiles.Live),
    "the parked profile did not recover after the name became available")

encoding = false
assert(DB.Initialize(disk))
Drain()
assert(Suite.RootDB.schema == 1 and type(Suite.RootDB.profiles.Cold) == "table",
    "old host lost its existing table-mode behavior")
print("Suite profile storage contract passed")
