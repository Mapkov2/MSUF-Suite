local _, Suite = ...
local Storage = { LEGACY_SCHEMA = 2 }
Suite.ProfileStorage = Storage

local function Codec()
    local io, api = Suite.ProfileIO, C_EncodingUtil
    if io and io.StorageCodec and type(api) == "table"
        and type(api.SerializeCBOR) == "function" and type(api.DeserializeCBOR) == "function"
        and type(api.CompressString) == "function" and type(api.DecompressString) == "function"
        and type(api.EncodeBase64) == "function" and type(api.DecodeBase64) == "function" then
        return io.StorageCodec()
    end
end

function Storage.Available()
    return Codec() ~= nil
end

function Storage.IsPacked(value)
    return type(value) == "string" and value:sub(1, 6) == "MSUF3:"
end

function Storage.Decode(value)
    local _, decode = Codec()
    if not decode or not Storage.IsPacked(value) then return end
    local ok, profile = Suite.Dispatch(Suite.Finish, decode, value)
    if ok and type(profile) == "table" and type(profile.suite) == "table" then return profile end
end

-- Leave any value the host codec cannot preserve in its original table.
local function Equal(left, right)
    if Suite.IsSecret(left) or Suite.IsSecret(right) then return false end
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for key, value in pairs(left) do
        if Suite.IsSecret(key) or not Equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if Suite.IsSecret(key) or left[key] == nil then return false end
    end
    return true
end

local function Pack(profile)
    local encode = Codec()
    if not encode then return end
    local modules = profile.suite.modules
    -- The old castbar migration still reads plain entries at startup.
    if type(modules) == "table" and modules.castbarArt ~= nil then return end
    local ok, value = Suite.Dispatch(Suite.Finish, encode, profile)
    if not ok or not Storage.IsPacked(value) then return end
    if Equal(profile, Storage.Decode(value)) then return value end
end

-- Pace legacy upgrades outside combat. A writable entry stays in
-- SavedVariables until its replacement has round-tripped.
local PACK_DELAY = 0.15
local queues = setmetatable({}, { __mode = "k" })
local writable = setmetatable({}, { __mode = "k" })

-- Once a caller receives a writable profile, that table remains the
-- canonical copy for the rest of the session, even after a switch or rename.
function Storage.Pin(profile)
    if type(profile) == "table" then writable[profile] = true end
end

local function Packable(root, name, profile)
    return name ~= root.activeProfile and type(profile) == "table" and not writable[profile]
end
local regenFrame, saveFrame, savingRoot
local PackNext

local function PreservePacked(root, name, value)
    local recovery = root.recoveryPackedProfiles
    if not recovery then
        recovery = {}
        root.recoveryPackedProfiles = recovery
    end
    if recovery[name] and recovery[name] ~= value then
        -- An older release may have reused this name while it could not see
        -- the parked entry. Keep both byte strings if neither is readable.
        local archive = type(root.quarantinedProfiles) == "table" and root.quarantinedProfiles or {}
        archive[#archive + 1] = { name = name, profile = value }
        root.quarantinedProfiles = archive
    else
        recovery[name] = value
    end
end

local function WritePlainProfiles()
    local root = Suite.RootDB
    if not root then return end
    savingRoot, queues[root] = root, nil
    for name, value in pairs(root.profiles) do
        if Storage.IsPacked(value) then
            local profile = Storage.Decode(value)
            if not profile then PreservePacked(root, name, value) end
            root.profiles[name] = profile
        end
    end
end

-- Cold profile compression saves memory only within this session. Persist ordinary
-- profile tables before the client saves the addon's SavedVariables, leaving
-- their schema readable to older Suite releases. Writes after this handler
-- (such as the nameplate baseline at logout) still use the same root/table.
function Storage.WatchSave()
    if saveFrame then return end
    saveFrame = CreateFrame("Frame")
    saveFrame:SetScript("OnEvent", WritePlainProfiles)
    saveFrame:RegisterEvent("PLAYER_LOGOUT")
    saveFrame:RegisterEvent("ADDONS_UNLOADING")
end

local function Schedule(root, queue)
    C_Timer.After(PACK_DELAY, function() PackNext(root, queue) end)
end

local function WaitForCombat(queue)
    queue.paused = true
    if not regenFrame then
        regenFrame = CreateFrame("Frame")
        regenFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local root = Suite.RootDB
            local waiting = queues[root]
            if waiting and waiting.paused then
                waiting.paused = nil
                Schedule(root, waiting)
            end
        end)
    end
    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

PackNext = function(root, queue)
    if Suite.RootDB ~= root or savingRoot == root then
        queues[root] = nil
        return
    end
    if Suite.InCombat() then
        WaitForCombat(queue)
        return
    end
    local name = next(queue.names)
    queue.names[name] = nil
    local entry = root.profiles[name]
    if Packable(root, name, entry) then
        local packed = Pack(entry)
        if packed then
            Storage.WatchSave()
            root.profiles[name] = packed
        end
    end
    if next(queue.names) then Schedule(root, queue)
    else queues[root] = nil end
end

function Storage.Queue(root, name)
    if savingRoot == root or not name or not Packable(root, name, root.profiles[name])
        or not Storage.Available() then return end
    local queue = queues[root]
    if queue then
        queue.names[name] = true
        return
    end
    queue = { names = { [name] = true } }
    queues[root] = queue
    Schedule(root, queue)
end
