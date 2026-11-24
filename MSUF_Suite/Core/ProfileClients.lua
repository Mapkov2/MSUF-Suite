local _, Suite = ...
-- Profile strings between Retail and WoW Forever, two games with their own
-- cooldowns and spells. A profile holds the cooldown manager (Clients.MODULES)
-- of the client it is used on and parks the other client's in the module's
-- clientParked setting; the action bars (spells and keys of the bars a
-- character uses) live in the game, a string carries them, and the other
-- client's wait in actionbars.parkedSetup. So a string carries both clients
-- and a round trip loses neither:
--   export: the string names its client (envelope.client) and carries the
--     exporting character's action bars (envelope.actionBars[client]); the
--     parked values are ordinary settings of the profile.
--   import on client X: X's part is the string's when it has one (the state
--     it was exported in), else that of the profile the import goes into or
--     starts from (the active one), else the defaults. The other client's
--     part is the string's, else that profile's. The other client's action
--     bars are parked. What an import offers this character (Clients.Offer)
--     is written only after the player agreed: the spells of X's bars, and
--     the key bindings of the string's exporter on either client (the bars'
--     key commands are the same in both games; spells are not).
-- A part of the other client is parked as it came: only the client it
-- belongs to migrates and checks it, with its own rules, when it comes back.
-- The settings of Clients.MODULES an MSUF profile variant sets are a
-- client's too (profile variants below): they travel and park with them.
-- Strings of older builds name no client: they belong to the client their
-- key map names (actionBarKeys), else to the importing one, as before.
local Clients = {}
Suite.ProfileClients = Clients

local OTHER = { retail = "forever", forever = "retail" }
local PARKED, ACTIONBARS, SETUP = "clientParked", "actionbars", "parkedSetup"
local VERSION = 1
local MAX_KEYS, MAX_KEY_TEXT, MAX_SLOTS, MAX_SLOT, MAX_INDEPENDENT = 256, 64, 400, 1000, 24
local MAX_RAW_SETTINGS = 4000
local INVALID_SETTINGS, INVALID_BARS = "Invalid settings of the other WoW version", "Invalid action bars"
Clients.MODULES = { "cooldownManager" }

function Clients.Current()
    return Suite.Client.isForever and "forever" or "retail"
end

function Clients.Other(client)
    return OTHER[client]
end

local function Valid(client)
    return OTHER[client] ~= nil
end

local function ClientModule(id)
    for _, name in ipairs(Clients.MODULES) do
        if name == id then return true end
    end
    return false
end

-- ProfileIO.lua loads after this file.
local function IO()
    return Suite.ProfileIO
end

-- An encoded value no longer than the setting (rules[key] of module id)
-- that keeps it.
local function Encode(value, id, key)
    local encode = IO().StorageCodec()
    local text = encode and encode(value)
    if type(text) ~= "string" or text:sub(1, 6) ~= "MSUF3:" then return nil, "Profile codec unavailable on this client" end
    if #text > Suite.SuiteCatalog[id].rules[key].maxLength then return nil, "Suite profile is too large" end
    return text
end

local function Decode(text)
    local _, decode = IO().StorageCodec()
    if type(text) ~= "string" or text:sub(1, 6) ~= "MSUF3:" or not decode then return nil end
    local value = decode(text)
    return type(value) == "table" and value or nil
end

-- The client a parked value belongs to and the value: nil for none, false
-- for one that is unreadable or names no client.
local function Peek(text)
    if text == nil or text == "" then return nil end
    local value = Decode(text)
    if not value or not Valid(value.client) then return false end
    return value.client, value
end

-- A stored parked value of the other client as it is; "" for none, one of
-- this client or an unreadable one. Without a codec nothing can be read:
-- the value stays for the session that has one.
local function StoredParked(text)
    local _, decode = IO().StorageCodec()
    if not decode and type(text) == "string" and text:sub(1, 6) == "MSUF3:" then return text end
    return Peek(text) == OTHER[Clients.Current()] and text or ""
end

------------------------------------------------------------------ action bars
local function Whole(value, limit)
    return type(value) == "number" and value > 0 and value <= limit and value == math.floor(value)
end

local function Label(value)
    return type(value) == "string" and value ~= "" and #value <= 120 and not value:find("%c") and value or nil
end

-- Key -> action bar command. The action bar addon checks keys and commands
-- again before it writes one (MSUF_Suite_ActionBars/Snapshots.lua).
local function CleanKeys(keys)
    if keys == nil then return {} end
    if type(keys) ~= "table" then return nil end
    local clean, count = {}, 0
    for key, command in pairs(keys) do
        count = count + 1
        if count > MAX_KEYS or type(key) ~= "string" or type(command) ~= "string" or key == "" or command == ""
            or #key > MAX_KEY_TEXT or #command > MAX_KEY_TEXT then
            return nil
        end
        clean[key] = command
    end
    return clean
end

-- Slot -> spell ID.
local function CleanSlots(slots, limit)
    if slots == nil then return nil, true end
    if type(slots) ~= "table" then return nil, false end
    local clean, count = {}, 0
    for slot, spell in pairs(slots) do
        count = count + 1
        if count > MAX_SLOTS or not Whole(slot, limit) or not Whole(spell, 2147483647) then return nil, false end
        clean[slot] = spell
    end
    return clean, true
end

-- One character's action bars as a string carries them; nil when malformed.
-- class, spec and group say whose spells they are.
local function CleanSetup(setup)
    if type(setup) ~= "table" then return nil end
    local keys = CleanKeys(setup.keys)
    local slots, slotsOK = CleanSlots(setup.slots, MAX_SLOT)
    local independent, independentOK = CleanSlots(setup.independentSlots, MAX_INDEPENDENT)
    if not keys or not slotsOK or not independentOK then return nil end
    local class = setup.class
    if class ~= nil and not (type(class) == "string" and #class <= 20 and class:match("^[A-Z]+$")) then return nil end
    if setup.spec ~= nil and not Whole(setup.spec, 99999) then return nil end
    if setup.group ~= nil and setup.group ~= 1 and setup.group ~= 2 then return nil end
    if not next(keys) and not (slots and next(slots)) and not (independent and next(independent)) then return nil end
    return { keys = keys, slots = slots, independentSlots = independent, class = class, spec = setup.spec,
        group = setup.group, label = Label(setup.label) }
end
Clients.CleanSetup = CleanSetup

-- The exporting character's action bars for a profile string, under this
-- client; nil while the Suite action bars cannot read them.
function Clients.CaptureSetups()
    local transfers = Suite.ActionBarSnapshots
    local read = transfers and transfers.ProfileSetup
    local setup = read and CleanSetup((read()))
    return setup and { [Clients.Current()] = setup } or nil
end

------------------------------------------------------------------ profile variants
-- An MSUF profile variant can set settings of Clients.MODULES (fields with
-- the path suiteModules.<id>.<key> in the MSUF frame profile's
-- profileVariants). Those belong to the client they were recorded on, like
-- the module's settings: a bundle of the other client parks its own with
-- that client's settings (a parked value's variants: variant name -> fields
-- { key, value, remove }), and this client's come back into the variants
-- of the same name, from the string's parked part, else from the MSUF
-- profile the import starts from (the active one). A variant renamed or
-- deleted on one client no longer receives the other client's fields.
-- MSUF's own profile strings carry no Suite part: their variants import as
-- they are.
local VARIANT_ROOT, MAX_VARIANTS, MAX_FIELDS = "suiteModules", 16, 512

local function FieldValue(value)
    local kind = type(value)
    return kind == "boolean" or kind == "string" or kind == "number" and Suite.Finite(value)
end

-- A parked variant field { key, value, remove }, or nil.
local function CleanField(key, value, remove)
    if type(key) ~= "string" or key == "" or #key > 64 then return nil end
    if remove == true then return value == nil and { key = key, remove = true } or nil end
    if FieldValue(value) then return { key = key, value = value } end
end

-- A field of an MSUF profile variant that sets a setting of module id, as a
-- parked value keeps it; nil for any other field.
local function VariantField(field, id)
    local path = type(field) == "table" and field.path
    if type(path) ~= "table" or #path ~= 3 or path[1] ~= VARIANT_ROOT or path[2] ~= id then return nil end
    return CleanField(path[3], field.value, field.remove)
end

-- Variant fields by variant name as a parked value carries them; nil when
-- malformed.
local function CleanVariants(variants)
    if variants == nil then return {} end
    if type(variants) ~= "table" then return nil end
    local clean, count = {}, 0
    for name, fields in pairs(variants) do
        count = count + 1
        if count > MAX_VARIANTS or type(name) ~= "string" or name == "" or #name > 64 or type(fields) ~= "table"
            or #fields > MAX_FIELDS then
            return nil
        end
        local list = {}
        for index = 1, #fields do
            local field = fields[index]
            list[index] = type(field) == "table" and CleanField(field.key, field.value, field.remove) or nil
            if not list[index] then return nil end
        end
        clean[name] = list
    end
    return clean
end

-- The fields of module id the variants of an MSUF profile set, by name.
local function ProfileVariantFields(profile, id)
    local schema = type(profile) == "table" and profile.profileVariants
    local entries = type(schema) == "table" and schema.entries
    local out = {}
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local name = type(entry) == "table" and entry.name
        if type(name) == "string" and type(entry.patch) == "table" then
            for _, field in ipairs(entry.patch) do
                local clean = VariantField(field, id)
                if clean then
                    out[name] = out[name] or {}
                    out[name][#out[name] + 1] = clean
                end
            end
        end
    end
    return out
end

-- The variant entries MSUF keeps of this client's auras while a profile
-- is on the other client (State/Profiles/MSUF_ProfileProjection.lua
-- AuraTransfer: _msufAuraClients; Mainline is Retail's): a variant that
-- sets only auras besides these modules waits there, and MSUF merges it by
-- name into the variant of the same name when it returns.
local AURA_CLIENTS = { retail = "Mainline", forever = "Forever" }
local function WaitingVariants(profile)
    local carried = profile._msufAuraClients
    local clients = type(carried) == "table" and carried.clients
    local section = type(clients) == "table" and clients[AURA_CLIENTS[Clients.Current()]]
    local schema = type(section) == "table" and section.profileVariants
    return type(schema) == "table" and type(schema.entries) == "table" and schema.entries or {}
end

-- Gives mine (by variant name) of module id that no variant of the profile
-- took a variant of their own, for the variants MSUF keeps waiting: at the
-- place MSUF puts that variant back, with its conditions, so MSUF merges
-- the waiting fields into it.
local function AddWaiting(profile, id, mine, placed)
    for _, waiting in ipairs(WaitingVariants(profile)) do
        local name = type(waiting) == "table" and waiting.name
        if type(name) == "string" and mine[name] and #mine[name] > 0 and not placed[name] then
            placed[name] = true
            profile.profileVariants = type(profile.profileVariants) == "table" and profile.profileVariants
                or { version = 1, entries = {} }
            local entries = profile.profileVariants.entries
            -- MSUF refuses a malformed variant list itself.
            if type(entries) ~= "table" then return end
            local hotkey = waiting.hotkey
            for _, entry in ipairs(entries) do
                if type(entry) == "table" and entry.hotkey == hotkey then hotkey = nil end
            end
            local patch = {}
            for _, field in ipairs(mine[name]) do
                patch[#patch + 1] = { path = { VARIANT_ROOT, id, field.key }, value = field.value, remove = field.remove == true }
            end
            local order = waiting.auraOrder
            if type(order) ~= "number" or order % 1 ~= 0 or order < 1 or order > #entries + 1 then order = #entries + 1 end
            table.insert(entries, order, { name = name, enabled = waiting.enabled, conditions = Suite.CopyValue(waiting.conditions),
                hotkey = hotkey, patch = patch })
        end
    end
end

-- Takes the fields of module id out of the variants of an MSUF profile
-- (returns them by variant name) and puts mine (by variant name) in.
local function SwapVariantFields(profile, id, mine)
    local theirs, placed = ProfileVariantFields(profile, id), {}
    local schema = type(profile) == "table" and profile.profileVariants
    local entries = type(schema) == "table" and schema.entries
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        if type(entry) == "table" and type(entry.patch) == "table" then
            local kept = {}
            for _, field in ipairs(entry.patch) do
                local path = type(field) == "table" and field.path
                if not (type(path) == "table" and path[1] == VARIANT_ROOT and path[2] == id) then kept[#kept + 1] = field end
            end
            local name = type(entry.name) == "string" and entry.name
            for _, field in ipairs(name and mine[name] or {}) do
                kept[#kept + 1] = { path = { VARIANT_ROOT, id, field.key }, value = field.value, remove = field.remove == true }
            end
            if name then placed[name] = true end
            entry.patch = kept
        end
    end
    if type(profile) == "table" then AddWaiting(profile, id, mine, placed) end
    return theirs
end

-- The MSUF profiles a decoded MSUF profile string carries (State/
-- MSUF_FirstLoad.lua SelectSupportedDecodedProfile): the string's own, a
-- snapshot's payload and the full snapshot a Wago export embeds, which MSUF
-- imports when present (last).
local function StringProfiles(decoded)
    local out = {}
    if type(decoded.payload) == "table" then out[#out + 1] = decoded.payload end
    local full = decoded.msuf6
    if type(full) == "table" and type(full.payload) == "table" then out[#out + 1] = full.payload end
    if #out == 0 then out[1] = decoded end
    return out
end

-- Whether MSUF imports the profile variants a string carries (its option
-- Import profile variants, on unless MSUF says otherwise).
local function ImportsVariants()
    local host = Suite.HostBridge.Namespace()
    local review = type(host) == "table" and host.ProfileImportReview
    local options = type(review) == "table" and review.ImportOptions
    return type(options) ~= "function" or Suite.Dispatch(options) ~= false
end

-- The MSUF frame string of a bundle and, by module, the variant fields that
-- go with the string's other-client part: for a string of the other client
-- its own fields leave its variants and this client's (mine, by module) come
-- in; for a string of this client those of its parked part stay. No second
-- result when no variants are imported (the stored parked fields stay). nil
-- and why when a string of the other client cannot be read or written.
local function RouteFrames(frames, source, mine)
    if not ImportsVariants() then return frames end
    local decode, encode = _G.MSUF_TryDecodeCompactString, _G.MSUF_EncodeCompactTable
    local decoded = type(decode) == "function" and Suite.Dispatch(decode, frames) or nil
    local client = Clients.Current()
    if type(decoded) ~= "table" then
        if source == client then return frames end
        return nil, type(decode) == "function" and "Invalid suite profile" or "Profile codec unavailable on this client"
    end
    local profiles = StringProfiles(decoded)
    local imported = profiles[#profiles]
    -- No variants come: none of its own, none MSUF keeps waiting for this client.
    if type(imported.profileVariants) ~= "table" and #WaitingVariants(imported) == 0 then return frames end
    if source == client then return frames, false end
    local theirs = {}
    for _, id in ipairs(Clients.MODULES) do
        for _, profile in ipairs(profiles) do theirs[id] = SwapVariantFields(profile, id, mine[id] or {}) end
    end
    local text = type(encode) == "function" and Suite.Dispatch(encode, decoded, "MSUF3") or nil
    if type(text) ~= "string" or text:sub(1, 6) ~= "MSUF3:" then return nil, "Profile codec unavailable on this client" end
    return text, source == OTHER[client] and theirs or nil
end

------------------------------------------------------------------ cooldown manager
-- One module's settings of a parked value for this client, migrated and
-- checked like the settings of an imported string: nil and why when
-- malformed.
local function CleanModule(id, settings, revision)
    if type(settings) ~= "table" or revision ~= nil and type(revision) ~= "number" then return nil, INVALID_SETTINGS end
    local clean, why = IO().PrepareTable({ suite = { schema = 1, revision = revision, modules = { [id] = settings } } }, true)
    if not clean then return nil, why end
    local out = clean.suite.modules[id]
    out[PARKED] = nil
    return out
end

-- The other client's settings of a string as they came, with the revision
-- they were made at: plain values only; that client checks them again.
local function ParkRaw(id, client, settings, revision)
    if type(settings) ~= "table" or revision ~= nil and type(revision) ~= "number" then return nil, INVALID_SETTINGS end
    local values, count = {}, 0
    for key, value in pairs(settings) do
        count = count + 1
        local kind = type(value)
        if count > MAX_RAW_SETTINGS or type(key) ~= "string"
            or not (kind == "boolean" or kind == "string" or kind == "number" and Suite.Finite(value)) then
            return nil, INVALID_SETTINGS
        end
        if key ~= PARKED then values[key] = value end
    end
    return Encode({ v = VERSION, client = client, revision = revision, settings = values }, id, PARKED)
end

local function SameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not SameValue(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function NoneEmpty(variants)
    variants = CleanVariants(variants)
    return variants and next(variants) and variants or nil
end

-- A parked value of the other client with the given variant fields (by
-- variant name); one this build does not write, or that has them already,
-- stays as it is.
local function WithVariants(id, text, variants)
    local owner, value = Peek(text)
    if owner ~= OTHER[Clients.Current()] or value.v ~= VERSION then return text end
    variants = NoneEmpty(variants)
    if SameValue(NoneEmpty(value.variants), variants) then return text end
    local copy = Suite.CopyValue(value)
    copy.variants = variants
    return Encode(copy, id, PARKED)
end

-- The stored modules an import goes into or starts from: the active
-- profile's, without the variant overlay.
local function OwnModules()
    local name = Suite.Database.GetActiveProfileName()
    local base, why = Suite.ProfileVariants.BaseProfile(name)
    if not base then return nil, why or "Missing suite profile" end
    return base.suite and base.suite.modules or {}
end

-- One module of a string of client source: true, this client's settings
-- (nil: the stored ones stay) and the other client's parked value; false and
-- why when the string's part is malformed. prepared: the string's settings
-- as this client prepared them; raw and revision: as they came; mine: the
-- stored settings. The variant fields of the parked value go with the
-- variants an import brings (RouteFrames): theirs (by variant name) for a
-- string of the other client, false for one of this client (its parked
-- part keeps its own), nil when no variants come (the stored ones stay).
local function Merge(id, prepared, raw, revision, source, mine, theirs)
    local client = Clients.Current()
    local other = OTHER[client]
    local active, parked, why
    if source == client and type(prepared) == "table" then
        active = Suite.CopyValue(prepared)
        active[PARKED] = nil
    end
    local text = type(prepared) == "table" and prepared[PARKED] or nil
    local owner, value = Peek(text)
    if owner == false then return false, INVALID_SETTINGS end
    if owner == client and source ~= client and value.v == VERSION then
        active, why = CleanModule(id, value.settings, value.revision)
        if not active then return false, why end
    elseif owner == other and source ~= other then
        -- Also a newer format of the other client travels on as it is.
        parked = text
    end
    if source == other and raw ~= nil then
        parked, why = ParkRaw(id, other, raw, revision)
        if not parked then return false, why end
    end
    local stored = StoredParked(mine and mine[PARKED])
    if not parked then return true, active, stored end
    if theirs == nil then
        local owner2, kept = Peek(stored)
        theirs = owner2 and kept.variants or {}
    end
    if theirs then
        parked, why = WithVariants(id, parked, theirs)
        if not parked then return false, why end
    end
    return true, active, parked
end

-- This client's variant fields of module id for the frame profile of a
-- string of the other client: the string's parked part for this client
-- (prepared[PARKED]), else those of the active MSUF profile. Only fields
-- this build's variants may set (ProfileVariants.lua): MSUF refuses a
-- variant with any other.
local function MyVariants(id, prepared)
    local owner, value = Peek(type(prepared) == "table" and prepared[PARKED] or nil)
    local fields
    if owner == Clients.Current() and value.v == VERSION then
        fields = CleanVariants(value.variants) or {}
    else
        fields = ProfileVariantFields(Suite.HostBridge.FrameProfile(Suite.Database.GetActiveProfileName()), id)
    end
    local check = Suite.ProfileVariants.VariantFieldValue
    for name, list in pairs(fields) do
        local kept = {}
        for _, field in ipairs(list) do
            local checked, valid = check(id, field.key, field.value, field.remove)
            if valid then kept[#kept + 1] = { key = field.key, value = checked, remove = field.remove } end
        end
        fields[name] = kept
    end
    return fields
end

------------------------------------------------------------------ strings
-- The client a string belongs to: the one it names (false for a client this
-- build does not know: no part of it is this client's), the one the key map
-- of an older build names, else this one (as before).
function Clients.Source(envelope)
    if type(envelope) ~= "table" then return Clients.Current() end
    if envelope.client ~= nil then return Valid(envelope.client) and envelope.client or false end
    local keys, found = envelope.actionBarKeys, nil
    if type(keys) == "table" then
        for client in pairs(keys) do
            if found or not Valid(client) then return Clients.Current() end
            found = client
        end
    end
    return found or Clients.Current()
end

-- The settings of a module as a string carries them, and their revision.
local function RawModule(envelope, id)
    if type(envelope) ~= "table" then return nil end
    if envelope.format == 2 then
        if envelope.module ~= id then return nil end
        return envelope.settings, envelope.revision
    end
    local suite = type(envelope.profile) == "table" and envelope.profile.suite or nil
    if type(suite) ~= "table" or type(suite.modules) ~= "table" then return nil end
    return suite.modules[id], suite.revision
end

-- What a decoded envelope carries besides its prepared settings: its client,
-- the action bars by client (envelope.actionBars, or a key map of an older
-- build) and the raw settings of Clients.MODULES. nil and why when malformed.
function Clients.Carried(envelope)
    local carried = { source = Clients.Source(envelope), setups = {}, raw = {} }
    local bars = type(envelope) == "table" and envelope.actionBars or nil
    if bars ~= nil then
        if type(bars) ~= "table" then return nil, INVALID_BARS end
        for client, setup in pairs(bars) do
            -- A client this build does not know is not one of its games.
            if Valid(client) then
                local clean = CleanSetup(setup)
                if not clean then return nil, INVALID_BARS end
                carried.setups[client] = clean
            end
        end
    end
    local keys = type(envelope) == "table" and envelope.actionBarKeys or nil
    if type(keys) == "table" then
        for client, map in pairs(keys) do
            if Valid(client) and not carried.setups[client] then carried.setups[client] = CleanSetup({ keys = map }) end
        end
    end
    for _, id in ipairs(Clients.MODULES) do
        local settings, revision = RawModule(envelope, id)
        carried.raw[id] = { settings = settings, revision = revision }
    end
    return carried
end

-- Parks the other client's action bars in settings (an actionbars settings
-- table) and returns what an import offers this character (false for
-- nothing): the spells of this client's bars from the string, and the key
-- bindings of the string's exporter, also when that is the other client
-- (the bars' key commands are the same in both games, spells are not; the
-- key bindings this client parked earlier stand in when the exporter has
-- none). mine: the stored actionbars settings.
local function RouteSetups(settings, carried, mine)
    local client = Clients.Current()
    local other = OTHER[client]
    local offer, keep, why = carried.setups[client], nil, nil
    local text = settings[SETUP]
    local owner, value = Peek(text)
    if owner == false then return nil, INVALID_BARS end
    if owner == client and carried.source ~= client and not offer and value.v == VERSION then
        offer = CleanSetup(value.setup)
        if not offer then return nil, INVALID_BARS end
    elseif owner == other and carried.source ~= other then
        keep = text
    end
    local theirs = carried.setups[other]
    if theirs then
        keep, why = Encode({ v = VERSION, client = other, setup = theirs }, ACTIONBARS, SETUP)
        if not keep then return nil, why end
        if carried.source == other and next(theirs.keys) then
            offer = offer and Suite.CopyValue(offer) or {}
            offer.keys = Suite.CopyValue(theirs.keys)
        end
    end
    settings[SETUP] = keep or StoredParked(mine and mine[SETUP])
    return offer or false
end

-- A prepared full profile (IO.PrepareProfile) on this client, and the MSUF
-- frame string of its bundle (frames, optional). Returns this client's action
-- bars from the string (false for none: only the player's consent applies
-- them), nil and the frames to import. nil and why when the string's parts
-- are malformed.
function Clients.RouteProfile(profile, carried, frames)
    local own, why = OwnModules()
    if not own then return nil, why end
    local modules, theirs = profile.suite.modules, nil
    if frames then
        local mine = {}
        if carried.source ~= Clients.Current() then
            for _, id in ipairs(Clients.MODULES) do mine[id] = MyVariants(id, modules[id]) end
        end
        frames, theirs = RouteFrames(frames, carried.source, mine)
        if not frames then return nil, theirs end
    end
    for _, id in ipairs(Clients.MODULES) do
        local raw = carried.raw[id] or {}
        local ok, active, parked = Merge(id, modules[id], raw.settings, raw.revision, carried.source, own[id],
            type(theirs) == "table" and theirs[id] or theirs)
        if not ok then return nil, active end
        active = active or Suite.CopyValue(type(own[id]) == "table" and own[id] or Suite.Defaults.suite.modules[id] or {})
        active[PARKED] = parked
        modules[id] = active
    end
    modules[ACTIONBARS] = modules[ACTIONBARS] or {}
    local offer
    offer, why = RouteSetups(modules[ACTIONBARS], carried, own[ACTIONBARS])
    if offer == nil then return nil, why end
    return offer, nil, frames
end

-- A module string's settings (IO.PrepareModuleProfile) on this client: the
-- settings its import sets and this client's action bars (false for none).
-- A module of Clients.MODULES without a part for this client only parks;
-- this client's settings stay as they are.
function Clients.RouteModule(id, settings, carried)
    if not ClientModule(id) and id ~= ACTIONBARS then return settings, false end
    local own, why = OwnModules()
    if not own then return nil, why end
    if id == ACTIONBARS then
        local offer
        offer, why = RouteSetups(settings, carried, own[ACTIONBARS])
        if offer == nil then return nil, why end
        return settings, offer
    end
    local raw = carried.raw[id] or {}
    local ok, active, parked = Merge(id, settings, raw.settings, raw.revision, carried.source, own[id])
    if not ok then return nil, active end
    if not active then return { [PARKED] = parked }, false end
    active[PARKED] = parked
    return active, false
end

-- A profile that starts over (a factory install, MSUF's profile reset) is
-- for this client only: it keeps the other client's parked values of the
-- profile it replaces (name) or else starts from (the active one), never
-- values the factory data may carry. Returns profile.
function Clients.Carry(profile, name)
    local db = Suite.Database
    local source = name and db.ReadProfile(name) or db.ReadProfile(db.GetActiveProfileName())
    local modules = source and source.suite and source.suite.modules or {}
    local target = profile.suite.modules
    for _, id in ipairs(Clients.MODULES) do
        target[id] = target[id] or {}
        target[id][PARKED] = StoredParked(type(modules[id]) == "table" and modules[id][PARKED] or nil)
    end
    target[ACTIONBARS] = target[ACTIONBARS] or {}
    target[ACTIONBARS][SETUP] = StoredParked(type(modules[ACTIONBARS]) == "table" and modules[ACTIONBARS][SETUP] or nil)
    return profile
end

------------------------------------------------------------------ consent
-- This client's action bars from an import that succeeded. Nothing writes
-- them before the player agreed: the offer waits in the account's saved
-- variables for the importing character (the first one the action bars ask
-- on when its GUID could not be read), also through a reload, and the action
-- bar addon asks (MSUF_Suite_ActionBars/Snapshots.lua
-- Transfers.AskProfileSetup). A newer import replaces an unanswered offer.
function Clients.Offer(setup)
    setup = setup and CleanSetup(setup)
    if not setup or not Suite.RootDB then return end
    Suite.RootDB.actionBarOffer = { v = VERSION, client = Clients.Current(), guid = Suite.PublicText(UnitGUID("player")),
        setup = setup }
    -- The action bar addon asks now, or once it can (it returns false only
    -- while the Suite action bars are off).
    local transfers = Suite.ActionBarSnapshots
    local ask = transfers and transfers.AskProfileSetup
    if ask and ask() then return end
    Suite.Print(Suite.Text("This profile includes action bars. Turn on the Suite action bars to choose whether they apply."))
end
