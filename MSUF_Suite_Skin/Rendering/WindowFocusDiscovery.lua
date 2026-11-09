local _, NS = ...

-- A combat reload can precede the skin catalog's own LoD initialization.
-- Discover only its reviewed, explicit names; painting remains deferred.
local OWNER = "blizzardWindows"
local SOCIAL_OWNER = OWNER .. ":social-ui"
local entries, addonEntries, pending = {}, {}, {}
local initialized, active, pendingCount = false, false, 0
local loader = CreateFrame("Frame")

local function Enabled()
    return NS.DB.enabled ~= false and NS.DB.skins.blizzardWindows ~= false
end

local function EntryEnabled(entry)
    return NS.GenericWindows.IsCategoryEnabled(entry.category)
        and (not entry.addon or NS.Client.HasAddOn(entry.addon) ~= false)
end

local function Build(dedicated)
    if initialized then return end
    initialized = true
    -- The dedicated Forever skin tracks this root even on a combat load.
    local excluded = { OpacityFrame = true, LegacySystemFrame = true }
    for _, name in pairs(dedicated) do excluded[name] = true end
    for _, entry in ipairs(NS.BlizzardCatalog.entries) do
        if NS.BlizzardCatalog.IsEntryGlassReady(entry) then
            local names = {}
            for _, name in ipairs(entry.frames) do
                if type(name) == "string" and not excluded[name] then names[#names + 1] = name end
            end
            if #names > 0 then
                local record = { entry = entry, names = names, owner = entry.id == "social-ui" and SOCIAL_OWNER or OWNER }
                entries[#entries + 1] = record
                if entry.addon then
                    local bucket = addonEntries[entry.addon]
                    if not bucket then bucket = {} addonEntries[entry.addon] = bucket end
                    bucket[#bucket + 1] = record
                end
            end
        end
    end
end

local function Track(record)
    if not EntryEnabled(record.entry) then return end
    for _, name in ipairs(record.names) do
        NS.WindowControls.TrackFocus(NS.Safety.Field(_G, name), record.owner)
    end
end

local function Stop()
    active, pendingCount = false, 0
    for addon in pairs(pending) do pending[addon] = nil end
    loader:UnregisterEvent("ADDON_LOADED")
    NS.WindowFocus.ReleaseOwner(OWNER)
    NS.WindowFocus.ReleaseOwner(SOCIAL_OWNER)
end

local function Discover(enabled, dedicated)
    Stop()
    if not enabled or not Enabled() then return end
    Build(dedicated)
    active = true
    for _, record in ipairs(entries) do
        local entry = record.entry
        if EntryEnabled(entry) then
            if not entry.addon or NS.Client.IsAddOnLoaded(entry.addon) then
                Track(record)
            elseif not pending[entry.addon] then
                pending[entry.addon] = addonEntries[entry.addon]
                pendingCount = pendingCount + 1
            end
        end
    end
    if pendingCount > 0 then loader:RegisterEvent("ADDON_LOADED") end
end

loader:SetScript("OnEvent", function(_, _, addon)
    local bucket = pending[addon]
    if not active or not bucket then return end
    if not Enabled() then
        Stop()
        return
    end
    pending[addon], pendingCount = nil, pendingCount - 1
    for _, record in ipairs(bucket) do Track(record) end
    if pendingCount == 0 then loader:UnregisterEvent("ADDON_LOADED") end
end)

NS.Adapters.SetWindowFocusDiscovery(Discover, Stop)
