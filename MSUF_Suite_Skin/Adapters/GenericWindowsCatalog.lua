local _, NS = ...

-- GenericWindows catalog entries (see GenericWindows.lua): the reviewed
-- Blizzard catalog, load-on-demand waiting, per-entry status and disable.
local GenericWindows = NS.GenericWindows
-- GenericWindows.lua's private helpers. This is their last reader
-- (GenericWindowsFrames.lua loads before it), so they are taken off NS
-- again: nothing internal stays reachable through _G.MapkoSkin.
local Shared = NS.GenericWindowsShared
NS.GenericWindowsShared = nil

local Kit = NS.AdapterKit

local DEFAULT_OWNER = Shared.DEFAULT_OWNER
local OwnerState = Shared.OwnerState
local OwnerKey = Shared.OwnerKey
local CatalogMode = Shared.CatalogMode
local ApplyFrameNow = Shared.ApplyFrameNow
local DeactivateOwner = Shared.DeactivateOwner

local entryStatus = {}
local entryOwners = {}

-- LoD handling uses one dormant dispatcher. It is registered only while at
-- least one catalog addon is outstanding, then unregistered immediately.
local pendingAddons = {}
local pendingAddonCount = 0
local loadFrame = CreateFrame("Frame")

local function IsAddonLoaded(addon)
    return type(addon) ~= "string" or addon == "" or NS.Client.IsAddOnLoaded(addon)
end

local function ById(left, right)
    return left.id < right.id
end

-- The catalog is static after load, so its glass-ready generic entries are
-- collected and sorted once.
local catalogEntries
local noEntries = {}

local function CatalogEntries()
    if catalogEntries then return catalogEntries end
    local catalog = NS.BlizzardCatalog
    local entries = {}
    if catalog.IsGlassContractValid() then
        for _, entry in ipairs(catalog.entries) do
            if type(entry.id) == "string" and entry.skipGeneric ~= true
                and catalog.IsEntryGlassReady(entry) then
                entries[#entries + 1] = entry
            end
        end
        table.sort(entries, ById)
    end
    catalogEntries = entries
    return entries
end

local function ResolveFrame(value)
    if type(value) == "string" then
        return _G[value]
    end
    if type(value) == "table" or type(value) == "userdata" then
        return value
    end
    return nil
end

local ApplyEntryIsolated

local function AddPending(entry, owner)
    local addon = entry.addon
    if type(addon) ~= "string" or addon == "" or IsAddonLoaded(addon)
        or NS.Client.HasAddOn(addon) == false then
        return false
    end
    local bucket = pendingAddons[addon]
    if not bucket then
        bucket = {}
        pendingAddons[addon] = bucket
        pendingAddonCount = pendingAddonCount + 1
    end
    bucket[entry.id .. ":" .. OwnerKey(owner)] = { entry = entry, owner = owner }
    loadFrame:RegisterEvent("ADDON_LOADED")
    return true
end

local function Enabled()
    if not NS.DB then
        return true
    end
    return NS.DB.enabled ~= false
        and (not NS.DB.skins or NS.DB.skins.blizzardWindows ~= false)
end

local categoryOrder = {
    "character", "inventory", "npc", "quest", "social", "group",
    "profession", "economy", "journal", "map", "calendar", "utility",
    "item-service", "expansion", "housing", "hud", "tutorial",
}

local metricTotalKeys = { "nodes", "surfaces", "controls", "scrollBars", "protected", "errors" }
local countedMetricKeys = { "surfaces", "controls", "scrollBars", "nodes", "fullscreenGuarded", "errors" }

function GenericWindows.IsCategoryEnabled(category)
    local categories = NS.DB and NS.DB.skinCategories
    return type(category) ~= "string" or not categories or categories[category] ~= false
end

local function SetEntryStatus(entry, owner, state)
    entryStatus[entry.id] = { state = state, frames = 0, owner = owner }
end

-- A Suite module that replaces this entry's surface keeps it while it runs
-- (Core/SuiteOwnership.lua).
local function SuiteOwnsEntry(entry)
    local ownership = NS.SuiteOwnership
    local surface = ownership.EntrySurface(entry.id)
    return surface ~= nil and ownership.Owns(surface)
end

-- Why an entry cannot be applied now, or nil when it can.
local function EntryBlocker(entry, owner)
    if not Enabled() then
        SetEntryStatus(entry, owner, "disabled")
        return "disabled"
    end
    if not GenericWindows.IsCategoryEnabled(entry.category) or SuiteOwnsEntry(entry) then
        SetEntryStatus(entry, owner, "disabled")
        entryOwners[entry.id] = owner
        return "disabled"
    end
    if entry.addon and NS.Client.HasAddOn(entry.addon) == false then
        SetEntryStatus(entry, owner, "unavailable")
        return "unavailable"
    end
    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-entry:" .. entry.id .. ":" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        SetEntryStatus(entry, owner, "queued")
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            GenericWindows.ApplyEntry(entry, owner)
        end)
        return "combat"
    end
    if entry.addon and not IsAddonLoaded(entry.addon) then
        AddPending(entry, owner)
        SetEntryStatus(entry, owner, "waiting")
        entryOwners[entry.id] = owner
        return "waiting"
    end
    return nil
end

local function AddMetrics(totals, metrics)
    for index = 1, #metricTotalKeys do
        local key = metricTotalKeys[index]
        totals[key] = totals[key] + (metrics[key] or 0)
    end
    if metrics.fullscreenGuarded == true then
        totals.fullscreenGuarded = totals.fullscreenGuarded + 1
    end
    totals.truncated = totals.truncated or metrics.truncated == true
end

local function ApplyEntryFrames(entry, owner)
    local applied, failed, protected = 0, 0, 0
    local totals = {
        nodes = 0, surfaces = 0, controls = 0, scrollBars = 0,
        protected = 0, errors = 0, fullscreenGuarded = 0,
        truncated = false,
    }
    local frames = type(entry.frames) == "table" and entry.frames or noEntries
    for index = 1, #frames do
        local frameValue = frames[index]
        local frame = ResolveFrame(frameValue)
        if frame then
            local frameMode = type(entry.frameModes) == "table"
                and type(frameValue) == "string" and entry.frameModes[frameValue]
                or nil
            local ok, reason, metrics = ApplyFrameNow(frame, owner, CatalogMode(frameMode or entry.mode))
            if ok then
                applied = applied + 1
            else
                failed = failed + 1
                if reason == "protected" then protected = protected + 1 end
            end
            if metrics then AddMetrics(totals, metrics) end
            -- The Macro adapter also starts independently of the catalog.
            -- Reapply after a late generic pass so pooled slot surfaces keep
            -- their specific artwork and selection style in either event order.
            if entry.id == "macros" then
                NS.MacroWindow.Apply(frame, owner)
            end
        else
            failed = failed + 1
        end
    end
    return applied, failed, protected, totals
end

function GenericWindows.ApplyEntry(entry, owner)
    owner = owner or DEFAULT_OWNER
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
        return false, "invalid"
    end
    local blocker = EntryBlocker(entry, owner)
    if blocker then return false, blocker end

    local applied, failed, protected, totals = ApplyEntryFrames(entry, owner)
    local state
    if applied > 0 and failed == 0 and totals.fullscreenGuarded == 0 then
        state = "applied"
    elseif applied > 0 then
        state = "partial"
    elseif protected > 0 then
        state = "protected"
    else
        state = "missing"
    end

    entryStatus[entry.id] = {
        state = state,
        frames = applied,
        failed = failed,
        owner = owner,
        metrics = totals,
    }
    entryOwners[entry.id] = owner
    return applied > 0, state
end

-- Each catalog entry is its own error boundary: an entry that raises is
-- reported, marked "error", and the remaining entries still apply.
ApplyEntryIsolated = function(entry, owner)
    if not Kit.Isolate(GenericWindows.ApplyEntry, entry, owner) then
        SetEntryStatus(entry, owner, "error")
        entryOwners[entry.id] = owner
    end
end

function GenericWindows.ScheduleLoadOnDemand(owner)
    owner = owner or DEFAULT_OWNER
    if not Enabled() then
        return 0
    end

    local scheduled = 0
    local entries = CatalogEntries()
    for index = 1, #entries do
        local entry = entries[index]
        if GenericWindows.IsCategoryEnabled(entry.category)
            and entry.addon and not IsAddonLoaded(entry.addon) and AddPending(entry, owner) then
            SetEntryStatus(entry, owner, "waiting")
            entryOwners[entry.id] = owner
            scheduled = scheduled + 1
        end
    end
    return scheduled
end

function GenericWindows.GetCategories()
    local counts = {}
    for index = 1, #categoryOrder do
        counts[categoryOrder[index]] = { id = categoryOrder[index], groups = 0, frames = 0 }
    end
    local entries = CatalogEntries()
    for index = 1, #entries do
        local entry = entries[index]
        local item = counts[entry.category]
        if item then
            item.groups = item.groups + 1
            item.frames = item.frames + #(entry.frames or noEntries)
        end
    end
    local result = {}
    for index = 1, #categoryOrder do
        result[#result + 1] = counts[categoryOrder[index]]
    end
    return result
end

function GenericWindows.SetCategoryEnabled(category, enabled)
    if NS.IsCombatLocked() or not NS.Defaults.skinCategories[category] then
        return false
    end
    NS.DB.skinCategories[category] = enabled == true
    local refreshed = NS.Adapters.Refresh("blizzardWindows")
    NS.Registry.NotifyListeners("category", category)
    return refreshed ~= nil
end

function GenericWindows.ApplyAll(owner)
    owner = owner or DEFAULT_OWNER
    if not Enabled() then
        GenericWindows.Disable(owner)
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-owner:" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            GenericWindows.ApplyAll(owner)
        end)
        return false, "combat"
    end

    local entries = CatalogEntries()
    for index = 1, #entries do
        ApplyEntryIsolated(entries[index], owner)
    end
    GenericWindows.ScheduleLoadOnDemand(owner)
    local counts = GenericWindows.GetCounts()
    local partial = counts.partial > 0 or counts.waiting > 0 or counts.queued > 0
        or counts.missing > 0 or counts.protected > 0 or counts.errors > 0
        or (counts.error or 0) > 0
    return true, partial and "partial" or "applied", counts
end

local function RemovePendingForOwner(owner)
    for addon, bucket in pairs(pendingAddons) do
        for key, request in pairs(bucket) do
            if request.owner == owner then
                bucket[key] = nil
            end
        end
        if next(bucket) == nil then
            pendingAddons[addon] = nil
            pendingAddonCount = math.max(0, pendingAddonCount - 1)
        end
    end
    if pendingAddonCount == 0 then
        loadFrame:UnregisterEvent("ADDON_LOADED")
    end
end

local function DisableNow(owner)
    NS.MacroWindow.Disable(owner)
    NS.WindowControls.DisableOwner(owner)
    DeactivateOwner(owner)

    RemovePendingForOwner(owner)
    for id, appliedOwner in pairs(entryOwners) do
        if appliedOwner == owner then
            entryStatus[id] = { state = "disabled", frames = 0, owner = owner }
        end
    end
    return true
end

function GenericWindows.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local ownerState = OwnerState(owner)
    Kit.CancelDeferred(ownerState)

    if NS.IsCombatLocked() then
        local key = "generic-owner:" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            DisableNow(owner)
        end)
        return false, "combat"
    end
    return DisableNow(owner)
end

function GenericWindows.GetStatus(id)
    local status = entryStatus[id]
    return status and status.state or "pending", status
end

function GenericWindows.GetStatusTable()
    local copy = {}
    for id, status in pairs(entryStatus) do
        local item = {}
        for key, value in pairs(status) do
            item[key] = value
        end
        copy[id] = item
    end
    return copy
end

function GenericWindows.GetCounts()
    local counts = {
        total = 0,
        applied = 0,
        partial = 0,
        waiting = 0,
        queued = 0,
        missing = 0,
        protected = 0,
        disabled = 0,
        pending = 0,
        frames = 0,
        surfaces = 0,
        controls = 0,
        scrollBars = 0,
        nodes = 0,
        fullscreenGuarded = 0,
        errors = 0,
        pendingAddons = pendingAddonCount,
    }

    local entries = CatalogEntries()
    counts.total = #entries
    for index = 1, #entries do
        local status = entryStatus[entries[index].id]
        local state = status and status.state or "pending"
        counts[state] = (counts[state] or 0) + 1
        if status then
            counts.frames = counts.frames + (status.frames or 0)
            local metrics = status.metrics
            if metrics then
                for keyIndex = 1, #countedMetricKeys do
                    local key = countedMetricKeys[keyIndex]
                    counts[key] = counts[key] + (metrics[key] or 0)
                end
            end
        end
    end
    return counts
end

function GenericWindows.GetAppliedCount()
    local counts = GenericWindows.GetCounts()
    return counts.applied + counts.partial
end

function GenericWindows.GetCatalogCount()
    return #CatalogEntries()
end

function GenericWindows.GetPendingAddonCount()
    return pendingAddonCount
end

function GenericWindows.GetTraversalLimits()
    return GenericWindows.maxDepth, GenericWindows.maxNodes
end

loadFrame:SetScript("OnEvent", function(self, event, addon)
    local bucket = event == "ADDON_LOADED" and pendingAddons[addon]
    if not bucket then
        return
    end

    -- The bucket leaves the queue first so an entry that loads further
    -- addons cannot see it again; every request is its own boundary.
    pendingAddons[addon] = nil
    pendingAddonCount = math.max(0, pendingAddonCount - 1)
    if pendingAddonCount == 0 then
        self:UnregisterEvent("ADDON_LOADED")
    end
    for _, request in pairs(bucket) do
        ApplyEntryIsolated(request.entry, request.owner)
    end
end)

return GenericWindows
