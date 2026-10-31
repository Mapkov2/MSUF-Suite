local _, P = ...
local NS, S = P.NS, P.Suite

-- The keystone lists of other addons, read through their public API and only
-- when an addon has loaded them already (LibStub). The Suite embeds neither
-- library and speaks neither wire format. Both serve Retail only, and the
-- keystone window is a Retail module (catalog `available`).
--   LibKeystone      Register(object, callback), Request("PARTY" or "GUILD");
--                    callback(level, challengeMapID, rating, name, channel)
--   LibOpenRaid-1.0  RegisterCallback(object, "KeystoneUpdate", member) and
--                    RequestKeystoneDataFromParty, FromRaid and FromGuild();
--                    object[member](name, info), info.level, info.mythicPlusMapID
-- Every answer goes to the sink that the last Request was given.
local Sources = { SUITE = "Suite", attached = {} }
P.KeystoneSources = Sources

local KEYSTONE = { source = "LibKeystone", library = "LibKeystone" }
local OPENRAID = { source = "LibOpenRaid", library = "LibOpenRaid-1.0" }
local LIBRARIES = { KEYSTONE, OPENRAID }
local KEYSTONE_SCOPE = { PARTY = "group", GUILD = "guild" }

-- Precedence of the sources, which settles equal answers: the Suite's own
-- protocol first, then the libraries.
Sources.order = { Sources.SUITE, KEYSTONE.source, OPENRAID.source }

local function Deliver(source, name, mapID, level, scope)
    if Sources.sink then Sources.sink(source, name, mapID, level, scope) end
end

local function InRaid()
    local raid = IsInRaid()
    return S.Public(raid) and raid == true
end

-- LibKeystone names the channel of every answer.
function KEYSTONE.OnAnswer(level, mapID, _, name, channel)
    Deliver(KEYSTONE.source, name, mapID, level, KEYSTONE_SCOPE[channel])
end

function KEYSTONE.Attach(lib) lib.Register(KEYSTONE, KEYSTONE.OnAnswer) end
function KEYSTONE.Detach(lib) lib.Unregister(KEYSTONE) end

-- LibKeystone reaches the party and the guild, not a raid.
function KEYSTONE.Ask(lib, mode)
    if mode == "group" and InRaid() then return false end
    lib.Request(mode == "guild" and "GUILD" or "PARTY")
    return true
end

-- LibOpenRaid does not name the channel of an answer: after a guild request
-- every answer counts, after a group request those of group members.
local function OpenRaidScope(name)
    if Sources.mode == "guild" then return "guild" end
    local party, raid = UnitInParty(name), UnitInRaid(name)
    if S.Public(party) and party == true or S.Public(raid) and raid ~= nil then return "group" end
end

-- The library calls object[member] without self.
function OPENRAID.OnUpdate(name, info)
    if type(info) ~= "table" then return end
    Deliver(OPENRAID.source, name, info.mythicPlusMapID, info.level, OpenRaidScope(name))
end

function OPENRAID.Attach(lib) lib.RegisterCallback(OPENRAID, "KeystoneUpdate", "OnUpdate") end
function OPENRAID.Detach(lib) lib.UnregisterCallback(OPENRAID, "KeystoneUpdate", "OnUpdate") end

function OPENRAID.Ask(lib, mode)
    if mode == "guild" then return lib.RequestKeystoneDataFromGuild() end
    if InRaid() then return lib.RequestKeystoneDataFromRaid() end
    return lib.RequestKeystoneDataFromParty()
end

local function Library(provider)
    local stub = _G.LibStub
    return type(stub) == "table" and type(stub.GetLibrary) == "function"
        and stub:GetLibrary(provider.library, true) or nil
end

-- The library, with the provider's callback registered once per library
-- object (again when an addon replaced it). A library that raises stays
-- unattached and is tried again by the next request.
local function Attach(provider)
    local lib = Library(provider)
    if not lib then return nil end
    if Sources.attached[provider] ~= lib then
        if not S.Dispatch(NS.Finish, provider.Attach, lib) then return nil end
        Sources.attached[provider] = lib
    end
    return lib
end

local function Ask(provider, mode)
    local lib = Attach(provider)
    if not lib then return false end
    local ok, sent = S.Dispatch(NS.Finish, provider.Ask, lib, mode)
    return ok == true and sent == true
end

-- Asks every loaded library for the keys of mode ("group" or "guild") and
-- returns how many requests went out. sink(source, name, mapID, level, scope)
-- receives the answers; scope ("group" or "guild") says which kind of request
-- an answer belongs to.
function Sources.Request(mode, sink)
    Sources.sink, Sources.mode = sink, mode
    local asked = 0
    for _, provider in ipairs(LIBRARIES) do
        if Ask(provider, mode) then asked = asked + 1 end
    end
    return asked
end

function Sources.Detach()
    for provider, lib in pairs(Sources.attached) do
        S.Dispatch(provider.Detach, lib)
        Sources.attached[provider] = nil
    end
    Sources.sink = nil
end
