-- Profile variants across MSUF 7.0's real Retail and WoW Forever worlds
-- (tools/profile_corpus_golden.lua of the MSUF checkout): what a variant
-- sets of the cooldown manager is routed by the Suite's own code
-- (Core/ProfileClients.lua RouteProfile, with stand-ins for the Suite parts
-- it calls) while MSUF moves the variant's aura fields (AuraTransfer,
-- _msufAuraClients). A variant whose other fields are only auras keeps its
-- cooldown manager field through Retail -> WoW Forever -> Retail.
--
--   lua tools/tests/suite_profile_variants_host_contract.lua <Suite root> <MSUF 7.0 root>
local suiteRoot, root = assert(arg[1], "Suite root required"), assert(arg[2], "MSUF 7.0 root required")
local corpus = loadfile(root .. "/tools/profile_corpus_golden.lua")
if not corpus then
    print("suite_profile_variants_host_contract: SKIP (no tools/profile_corpus_golden.lua in " .. root .. ")")
    return
end
local C = corpus()
local function World(client)
    local w = C.NewWorld(root, client, "Portable-Realm")
    C.Login(w, {})
    return w
end
local function API(w) return w.core.PublicGlobals end
local function DB(w) return w.env.MSUF_DB end
local function Export(w) return assert(API(w).MSUF_ExportSelectionToString("all")) end
local CDM = "cooldownManager"

-- The Suite's ProfileClients.lua in world w, with the Suite parts it uses.
local function Clients(w, client, activeVariants)
    local env = w.env
    local enc, dec = API(w).MSUF_EncodeCompactTable, API(w).MSUF_TryDecodeCompactString
    local function Copy(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = Copy(x) end
        return o
    end
    local Suite = {
        Client = { isForever = client == "forever" },
        Dispatch = function(f, ...) return f(...) end,
        CopyValue = Copy,
        Finite = function(v) return v == v and v ~= math.huge and v ~= -math.huge end,
        ProfileIO = { StorageCodec = function() return function(t) return enc(t, "MSUF3") end, dec end,
            PrepareTable = function(t) return t end },
        SuiteCatalog = { [CDM] = { rules = { clientParked = { maxLength = 200000 } } },
            actionbars = { rules = { parkedSetup = { maxLength = 100000 } } } },
        Defaults = { suite = { modules = { [CDM] = {} } } },
        Database = { GetActiveProfileName = function() return "Default" end },
        ProfileVariants = {
            BaseProfile = function() return { suite = { modules = {} } } end,
            VariantFieldValue = function(_, _, value, remove) return value, true end,
        },
        HostBridge = {
            Namespace = function() return w.core end,
            FrameProfile = function() return { profileVariants = activeVariants } end,
        },
    }
    local chunk = assert(loadfile(suiteRoot .. "/MSUF_Suite/Core/ProfileClients.lua"))
    setfenv(chunk, setmetatable({ _G = env }, { __index = function(_, k) return env[k] ~= nil and env[k] or _G[k] end }))
    chunk("MSUF_Suite", Suite)
    return Suite.ProfileClients, enc, dec
end
local function Names(entries)
    local out = {}
    for _, e in ipairs(entries or {}) do
        local f = {}
        for _, field in ipairs(e.patch) do f[#f + 1] = table.concat(field.path, ".") .. "=" .. tostring(field.value) end
        out[#out + 1] = e.name .. "{" .. table.concat(f, ",") .. "}"
    end
    return table.concat(out, " ")
end
-- Route a bundle's frames on client `client` of world w: string of client
-- source whose Suite part parks `parked` (encoded) for the importing client.
local function Route(w, client, source, frames, parkedForMe, activeVariants)
    local Clients, enc, dec = Clients(w, client, activeVariants)
    local modules = { [CDM] = { clientParked = parkedForMe and enc(parkedForMe, "MSUF3") or "" } }
    local profile = { suite = { modules = modules } }
    local carried = { source = source, setups = {}, raw = { [CDM] = { settings = { listsData = source .. "-lists" }, revision = 1 } } }
    local offer, why, routed = Clients.RouteProfile(profile, carried, frames)
    assert(offer ~= nil, why)
    local parked = modules[CDM].clientParked ~= "" and dec(modules[CDM].clientParked) or nil
    return routed, parked
end

local retail = World("Mainline")
DB(retail).profileVariants = { version = 1, entries = { {
    name = "Arena", enabled = true, conditions = { context = "arena" },
    patch = { { path = { "auras3", "shared", "iconSize" }, value = 49 },
        { path = { "suiteModules", CDM, "cdColor" }, value = "ff0000" } },
} } }
local text = Export(retail)

local forever = World("Forever")
local routed, parked = Route(forever, "forever", "retail", text, nil, nil)
assert(parked and parked.client == "retail" and parked.variants.Arena[1].value == "ff0000", "Forever did not park Retail's field")
assert(API(forever).MSUF_ImportFromString(routed))
local back = Export(forever)

local home = World("Mainline")
local routedBack = Route(home, "retail", "forever", back, { v = 1, client = "retail", revision = 1, settings = {},
    variants = parked.variants }, nil)
assert(API(home).MSUF_ImportFromString(routedBack))
local result = Names(DB(home).profileVariants and DB(home).profileVariants.entries)
assert(result:find("auras3.shared.iconSize=49", 1, true) and result:find("suiteModules.cooldownManager.cdColor=ff0000", 1, true),
    "the round trip lost a field of Arena")
print("suite_profile_variants_host_contract: an aura-only variant kept its cooldown manager field through both clients")
