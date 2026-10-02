local _, NS = ...

-- Glass review of the Blizzard window catalog. Catalog.lua (loaded before)
-- holds the entries and the review data; this file classifies every root once
-- at load and builds NS.BlizzardCatalog. An entry is fail-closed on its own: a
-- root without a matching reviewed classification keeps that entry closed,
-- and Catalog.GetGlassErrors() lists each reason. Whether the catalog as a
-- whole still matches its review (fingerprint, entry and root counts) is a
-- development contract checked by tools/tests, not at every load in game.
-- Taken off NS again: only the checked NS.BlizzardCatalog stays reachable
-- through _G.MapkoSkin.
local Data = NS.BlizzardCatalogData
NS.BlizzardCatalogData = nil
local entries = Data.entries
local dedicatedGlassOwners = Data.dedicatedOwners
local partialDedicatedGlass = Data.partialDedicated
local mixedGlassKinds = Data.mixedKinds
local standaloneGlass = Data.standalone
local nestedGlass = Data.nested
local sourceExclusions = Data.sourceExclusions

-- entry id -> kind of all its roots
local homogeneousGlassKinds = {}
for groupIndex = 1, #Data.homogeneousKinds do
    local group = Data.homogeneousKinds[groupIndex]
    for index = 1, #group.ids do
        homogeneousGlassKinds[group.ids[index]] = group.kind
    end
end

local glassByFrame = {}
local glassCounts = {
    total = 0,
    genericShell = 0,
    dedicated = 0,
    semanticContent = 0,
    semanticChrome = 0,
    semanticHUD = 0,
    full = 0,
    partial = 0,
    none = 0,
}
local glassErrors = {}
local glassReadyByEntry = {}

local function AddGlassError(entry, frameName, reason)
    glassErrors[#glassErrors + 1] = {
        id = entry and entry.id,
        frame = frameName,
        reason = reason,
    }
end

local function ModeForFrame(entry, frameName)
    return type(entry.frameModes) == "table" and entry.frameModes[frameName]
        or entry.mode
end

local function ResolveReviewedKind(entry, frameName)
    local mixed = mixedGlassKinds[entry.id]
    if mixed then return mixed[frameName] end
    return homogeneousGlassKinds[entry.id] or "generic-shell"
end

local function ModeMatchesKind(entry, frameName, kind)
    local mode = ModeForFrame(entry, frameName)
    if kind == "dedicated" then
        return entry.skipGeneric == true and dedicatedGlassOwners[entry.id] ~= nil
    end
    if entry.skipGeneric == true then return false end
    if kind == "semantic-hud" then
        return type(mode) == "table" and mode.rootSurface == false
            and mode.accentOnly == true
    end
    if kind == "semantic-content" then
        return type(mode) == "table" and mode.rootSurface == false
            and mode.accentOnly ~= true
    end
    if kind == "semantic-chrome" then
        return type(mode) == "table" and mode.rootSurface ~= false
            and mode.preserveRootArt == true and mode.fillVisible == false
            and mode.accentOnly ~= true
    end
    if kind == "generic-shell" then
        return type(mode) ~= "table" or (mode.rootSurface ~= false
            and mode.accentOnly ~= true
            and not (mode.preserveRootArt == true and mode.fillVisible == false))
    end
    return false
end

local kindReasons = {
    ["generic-shell"] = "reviewed-catalog-glass-shell",
    dedicated = "dedicated-clean-room-adapter",
    ["semantic-chrome"] = "semantic-art-edge-only",
    ["semantic-content"] = "native-semantic-content",
    ["semantic-hud"] = "native-secure-or-semantic-hud",
}

local kindCounters = {
    ["generic-shell"] = "genericShell",
    dedicated = "dedicated",
    ["semantic-content"] = "semanticContent",
    ["semantic-chrome"] = "semanticChrome",
    ["semantic-hud"] = "semanticHUD",
}

local function ResolveGlassContract(entry, frameName)
    local kind = ResolveReviewedKind(entry, frameName)
    if not kind then return nil, "root-classification-missing" end
    if not ModeMatchesKind(entry, frameName, kind) then
        return nil, "root-mode-contract-mismatch"
    end
    local owner = kind == "dedicated" and dedicatedGlassOwners[entry.id]
        or "GenericWindows"
    if not owner then return nil, "dedicated-owner-missing" end
    local support = "full"
    if kind == "semantic-hud" then
        support = "none"
    elseif kind == "semantic-content" or kind == "semantic-chrome"
        or (kind == "dedicated" and partialDedicatedGlass[entry.id]) then
        support = "partial"
    end
    return {
        kind = kind,
        owner = owner,
        support = support,
        reason = kindReasons[kind],
    }
end

local function ClassifyFrame(entry, frameName)
    if type(frameName) ~= "string" or frameName == "" then
        AddGlassError(entry, frameName, "frame-invalid")
        return false
    end
    if glassByFrame[frameName] then
        AddGlassError(entry, frameName, "frame-duplicate")
        return false
    end
    local contract, reason = ResolveGlassContract(entry, frameName)
    if not contract then
        AddGlassError(entry, frameName, reason or "contract-missing")
        return false
    end
    contract.id = entry.id
    contract.frame = frameName
    glassByFrame[frameName] = contract
    glassCounts.total = glassCounts.total + 1
    local counter = kindCounters[contract.kind]
    glassCounts[counter] = glassCounts[counter] + 1
    glassCounts[contract.support] = glassCounts[contract.support] + 1
    return true
end

for entryIndex = 1, #entries do
    local entry = entries[entryIndex]
    local ready = type(entry.id) == "string" and type(entry.frames) == "table"
    if not ready then
        AddGlassError(entry, nil, "entry-invalid")
    else
        for frameIndex = 1, #entry.frames do
            ready = ClassifyFrame(entry, entry.frames[frameIndex]) and ready
        end
    end
    glassReadyByEntry[entry] = ready
end

local flattened = {}
local byFrame = {}

for entryIndex = 1, #entries do
    local entry = entries[entryIndex]
    for frameIndex = 1, #entry.frames do
        local frameName = entry.frames[frameIndex]
        if not byFrame[frameName] then
            flattened[#flattened + 1] = frameName
            byFrame[frameName] = entry
        end
    end
end

local standaloneRootCount = 0
local standaloneSeen = {}
for index = 1, #standaloneGlass do
    local item = standaloneGlass[index]
    local valid = type(item.id) == "string" and type(item.addon) == "string"
        and type(item.owner) == "string" and type(item.roots) == "table"
        and (item.support == "full" or item.support == "partial")
    for rootIndex = 1, #(item.roots or {}) do
        local root = item.roots[rootIndex]
        standaloneRootCount = standaloneRootCount + 1
        if type(root) ~= "string" or root == "" or byFrame[root] or standaloneSeen[root] then
            valid = false
        end
        standaloneSeen[root] = true
    end
    if not valid then AddGlassError(item, nil, "standalone-contract-invalid") end
end

for index = 1, #nestedGlass do
    local item = nestedGlass[index]
    if type(item.id) ~= "string" or type(item.parent) ~= "string"
        or type(item.path) ~= "table" or #item.path == 0
        or type(item.owner) ~= "string" or not byFrame[item.parent] then
        AddGlassError(item, nil, "nested-contract-invalid")
    end
end

local exclusionSeen = {}
for index = 1, #sourceExclusions do
    local item = sourceExclusions[index]
    if type(item.frame) ~= "string" or item.frame == "" or byFrame[item.frame]
        or standaloneSeen[item.frame] or exclusionSeen[item.frame]
        or type(item.disposition) ~= "string" or item.disposition == "" then
        AddGlassError(item, item.frame, "source-exclusion-invalid")
    end
    exclusionSeen[item.frame] = true
end

if glassCounts.total ~= #flattened then
    AddGlassError(nil, nil, "catalog-glass-coverage:" .. glassCounts.total .. "/" .. #flattened)
end

-- The catalog is static after load, so it is classified exactly once here.
-- Each failure closes its own entry and is listed, with its reason, by
-- Catalog.GetGlassErrors(); the contract is valid while none is listed.
local glassContractValid = #glassErrors == 0

local Catalog = {
    entries = entries,
    frames = flattened,
    byFrame = byFrame,
    glass = {
        valid = glassContractValid,
        byFrame = glassByFrame,
        counts = glassCounts,
        errors = glassErrors,
        sourceRevision = Data.sourceRevision,
        standalone = standaloneGlass,
        standaloneRootCount = standaloneRootCount,
        nested = nestedGlass,
        sourceExclusions = sourceExclusions,
    },
}
NS.BlizzardCatalog = Catalog

function Catalog.GetFrames()
    return flattened
end

function Catalog.FindByFrame(frameName)
    return byFrame[frameName]
end

function Catalog.GetGlassErrors()
    local result = {}
    for index = 1, #glassErrors do
        result[index] = glassErrors[index]
    end
    return result
end

-- True for a catalog entry whose roots all passed review.
function Catalog.IsEntryGlassReady(entry)
    return glassReadyByEntry[entry] == true
end
Catalog.ValidateGlassEntry = Catalog.IsEntryGlassReady
