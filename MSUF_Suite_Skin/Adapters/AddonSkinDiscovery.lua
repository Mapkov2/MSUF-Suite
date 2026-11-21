local _, NS = ...

-- Some supported addons intentionally keep their anonymous settings windows
-- private. Inspect top-level windows only after an exact addon launcher,
-- login or explicit enable. No global mouse listener, CreateFrame hook or ticker.
local Skins, Safety = NS.AddonSkins, NS.Safety
local requested, queued, scan = {}, false, nil
local MAX_WINDOW_NODES, MAX_WINDOW_DEPTH = 128, 2
local MAX_FOUND_FOLDERS, MAX_ROOTS_PER_FOLDER = 32, 12
local found, scanCallback = {}, nil
local watched = setmetatable({}, { __mode = "k" })
local registered = {}

local function Options()
    local opts = NS.DB and NS.DB.addonSkins
    return opts and opts.discovered
end

local function Folder(frame)
    local source = Safety.Read(frame, "GetSourceLocation")
    if type(source) ~= "string" then return end
    local name, path = source:match("[Aa][Dd][Dd][Oo][Nn][Ss][/\\]([^/\\]+)[/\\](.*)")
    return name, path
end

local function Origin(frame)
    if not Safety.Public(frame) or Safety.IsForbidden(frame) or Safety.IsCompositorManaged(frame) then return nil end
    local name = Folder(frame)
    return name and Skins.byAddon[name:lower()] or nil
end
Skins.Origin = Origin

local function IsWindow(frame, confined)
    if Safety.Read(frame, "GetObjectType") ~= "Frame" or not NS.AddonSkinVisuals.Safe(frame) then return false end
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    local screenWidth, screenHeight = Safety.Read(UIParent, "GetWidth"), Safety.Read(UIParent, "GetHeight")
    if type(width) ~= "number" or type(height) ~= "number" or width < 160 or height < 80 then return false end
    if type(screenWidth) ~= "number" or type(screenHeight) ~= "number" then return false end
    local narrow, short = width < screenWidth * 0.9, height < screenHeight * 0.9
    return (confined and narrow and short or not confined and (narrow or short))
        and Safety.Read(frame, "IsMouseEnabled") == true
end

local function CanDiscover(name, path, frame)
    if not NS.ValidDiscoveredAddon(name) or not path then return false end
    local key = name:lower()
    if registered[key] or Skins.byAddon[key] or key:match("^blizzard_") or key:match("^msuf")
        or key:match("^midnightsimpleunitframes") or key:match("^mapkoskin") then return false end
    path = path:lower():gsub("\\", "/")
    if ("/" .. path):match("/libs?/") or ("/" .. path):match("/externallibs/") then return false end
    if not IsWindow(frame, true) or Safety.Read(frame, "GetParent") ~= UIParent then return false end
    if not NS.Client.HasAddOn(name) or not NS.Client.IsAddOnLoaded(name) then return false end
    if Safety.Read(frame, "GetFrameStrata") == "TOOLTIP" then return false end
    local slice = Safety.Field(frame, "NineSlice")
    return Safety.Read(frame, "GetBackdrop") ~= nil
        or (Safety.Public(slice) and slice ~= nil and Safety.Field(frame, "TitleContainer") ~= nil)
end

local function Release(watch)
    if not watch.applied then return end
    NS.AddonSkinVisuals.Release(watch.owner)
    watch.applied = false
end

local function Paint(frame, watch)
    local prefs = Options()
    if not prefs or not prefs[watch.name] or not Skins.IsEnabled() or registered[watch.name:lower()] then
        Release(watch)
        return
    end
    if watch.applied or Safety.Read(frame, "IsVisible") ~= true then return end
    local name, path = Folder(frame)
    if name ~= watch.name or not CanDiscover(name, path, frame) then return end
    watch.applied = NS.AddonSkinVisuals.ApplyDiscovered(frame, watch.owner) == true
end

local function Shown(frame)
    local watch = watched[frame]
    local prefs = Options()
    if watch and prefs and not watch.applied and Skins.IsEnabled() and prefs[watch.name] then
        NS.Registry.QueueJob(watch.paint)
    end
end

local function Watch(frame, name)
    local watch = watched[frame]
    if not watch then
        if not Safety.HasMethod(frame, "HookScript") then return end
        watch = { name = name, owner = {} }
        watch.paint = function() Paint(frame, watch) end
        watched[frame] = watch
        frame:HookScript("OnShow", Shown)
    end
    if watch.name == name then NS.Registry.QueueJob(watch.paint) end
end

local function DiscoverUnknown(frame, name, path)
    if not CanDiscover(name, path, frame) then return end
    if scan.preferences and scan.preferences[name] then Watch(frame, name) end
    if not scan.requested.find or Safety.Read(frame, "IsVisible") ~= true then return end
    local group = scan.found[name]
    if not group then
        if scan.foundCount >= MAX_FOUND_FOLDERS then return end
        group = {}
        scan.found[name], scan.foundCount = group, scan.foundCount + 1
    end
    if #group < MAX_ROOTS_PER_FOLDER then group[#group + 1] = frame end
end

local function Append(depth, ...)
    for index = 1, select("#", ...) do
        local at = #scan.nodes + 1
        scan.nodes[at], scan.depths[at] = select(index, ...), depth
    end
end

local function Visit(frame, depth)
    if not Safety.Public(frame) or Safety.IsForbidden(frame) or Safety.IsCompositorManaged(frame) then return end
    local name, path = Folder(frame)
    local id = name and Skins.byAddon[name:lower()]
    if not id and depth == 0 and name and (scan.requested.find or (scan.preferences and scan.preferences[name])) then
        DiscoverUnknown(frame, name, path)
    end
    if not id or Skins.byID[id].exact or not (scan.requested.all or scan.requested[id]) or not Skins.IsEnabled(id) then
        return
    end
    if IsWindow(frame) then
        Skins.Watch(frame, id)
        return
    end
    if depth < MAX_WINDOW_DEPTH then
        Append(depth + 1, Safety.Call(frame, "GetChildren"))
    end
end

local function DiscoverNow()
    if not Skins.IsEnabled() then
        scan, queued, requested, scanCallback = nil, false, {}, nil
        return
    end
    if NS.IsCombatLocked() then NS.Registry.QueueJob(DiscoverNow) return end
    if not scan then
        scan = { nodes = {}, depths = {}, requested = requested,
            found = {}, foundCount = 0, preferences = requested.all and Options() or nil,
            callback = requested.find and scanCallback or nil }
        if requested.find then scanCallback = nil end
        requested = {}
        Append(0, Safety.Call(UIParent, "GetChildren"))
    end
    -- Process newest windows first, and continue on subsequent frames until
    -- the finite snapshot is exhausted. A large UI never loses its tail.
    for _ = 1, MAX_WINDOW_NODES do
        local at = #scan.nodes
        if at == 0 then break end
        local frame, depth = scan.nodes[at], scan.depths[at]
        scan.nodes[at], scan.depths[at] = nil, nil
        Visit(frame, depth)
    end
    if #scan.nodes > 0 then C_Timer.After(0, DiscoverNow) return end
    local completed = scan
    scan, queued = nil, false
    if completed.requested.find then
        found = completed.found
        if completed.callback then Safety.Dispatch(completed.callback) end
    end
    if not queued and next(requested) then
        queued = true
        NS.Registry.QueueJob(DiscoverNow)
    end
end

function Skins.Discover(id)
    local entry = id and Skins.byID[id]
    if not Skins.IsEnabled(id) or id and (not entry or entry.exact) then return end
    requested[id or "all"] = true
    if queued then return end
    queued = true
    NS.Registry.QueueJob(DiscoverNow)
end


function Skins.ScanWindows(callback)
    if NS.IsCombatLocked() or not Skins.IsEnabled() then return false end
    requested.find, scanCallback = true, callback
    if not queued then
        queued = true
        NS.Registry.QueueJob(DiscoverNow)
    end
    return true
end

function Skins.DiscoveredWindows()
    local result, prefs = {}, Options()
    if not prefs then return result end
    for name, frames in pairs(found) do
        result[#result + 1] = { name = name, windows = #frames, enabled = prefs[name] == true }
    end
    for name in pairs(prefs) do
        if not found[name] then result[#result + 1] = { name = name, windows = 0, enabled = true } end
    end
    table.sort(result, function(left, right) return left.name:lower() < right.name:lower() end)
    return result
end

function Skins.SetDiscovered(name, enabled)
    if NS.IsCombatLocked() or not Skins.IsEnabled() then return false end
    local prefs = Options()
    if not prefs or not NS.ValidDiscoveredAddon(name) then return false end
    if enabled then
        local targets = found[name]
        if not targets or registered[name:lower()] then return false end
        local count = 0
        for _ in pairs(prefs) do count = count + 1 end
        if not prefs[name] and count >= NS.MaxDiscoveredAddons then return false end
        prefs[name] = true
        for _, frame in ipairs(targets) do Watch(frame, name) end
    else
        prefs[name] = nil
        for frame, watch in pairs(watched) do
            if watch.name == name then Paint(frame, watch) end
        end
    end
    return true
end

function Skins.ReconcileDiscovered()
    for _, watch in pairs(watched) do NS.Registry.QueueJob(watch.paint) end
end

function Skins.TransferDiscovered(name, status)
    if not Safety.Public(name) or type(name) ~= "string" then return end
    local key = name:lower()
    registered[key] = status == true or nil
    for _, watch in pairs(watched) do
        if watch.name:lower() == key then NS.Registry.QueueJob(watch.paint) end
    end
end
