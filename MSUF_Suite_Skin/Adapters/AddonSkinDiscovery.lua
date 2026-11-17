local _, NS = ...

-- Some supported addons intentionally keep their anonymous settings windows
-- private. Inspect top-level windows only after an exact addon launcher,
-- login or explicit enable. No global mouse listener, CreateFrame hook or ticker.
local Skins, Safety = NS.AddonSkins, NS.Safety
local requested, queued, scan = {}, false, nil
local MAX_WINDOW_NODES, MAX_WINDOW_DEPTH = 128, 2

local function Origin(frame)
    if not Safety.Public(frame) or Safety.IsForbidden(frame) or Safety.IsCompositorManaged(frame) then return nil end
    local source = Safety.Read(frame, "GetSourceLocation")
    if type(source) ~= "string" then return nil end
    local addon = source:gsub("\\", "/"):match("[Aa]dd[Oo]ns/([^/]+)/")
    return addon and Skins.byAddon[addon:lower()] or nil
end
Skins.Origin = Origin

local function IsWindow(frame)
    if Safety.Read(frame, "GetObjectType") ~= "Frame" or not NS.AddonSkinVisuals.Safe(frame) then return false end
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    local screenWidth, screenHeight = Safety.Read(UIParent, "GetWidth"), Safety.Read(UIParent, "GetHeight")
    if type(width) ~= "number" or type(height) ~= "number" or width < 160 or height < 80 then return false end
    if type(screenWidth) ~= "number" or type(screenHeight) ~= "number" then return false end
    return (width < screenWidth * 0.9 or height < screenHeight * 0.9)
        and Safety.Read(frame, "IsMouseEnabled") == true
end

local function Append(depth, ...)
    for index = 1, select("#", ...) do
        local at = #scan.nodes + 1
        scan.nodes[at], scan.depths[at] = select(index, ...), depth
    end
end

local function Visit(frame, depth)
    if not Safety.Public(frame) or Safety.IsForbidden(frame) or Safety.IsCompositorManaged(frame) then return end
    local id = Origin(frame)
    if id and (scan.requested.all or scan.requested[id]) and Skins.IsEnabled(id) and IsWindow(frame) then
        Skins.Watch(frame, id)
        return
    end
    if id and Skins.IsEnabled(id) and depth < MAX_WINDOW_DEPTH then
        Append(depth + 1, Safety.Call(frame, "GetChildren"))
    end
end

local function DiscoverNow()
    if not Skins.IsEnabled() then scan, queued, requested = nil, false, {} return end
    if NS.IsCombatLocked() then NS.Registry.QueueJob(DiscoverNow) return end
    if not scan then
        scan = { nodes = {}, depths = {}, requested = requested }
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
    scan, queued = nil, false
    if next(requested) then
        queued = true
        NS.Registry.QueueJob(DiscoverNow)
    end
end

function Skins.Discover(id)
    if not Skins.IsEnabled(id) then return end
    requested[id or "all"] = true
    if queued then return end
    queued = true
    NS.Registry.QueueJob(DiscoverNow)
end
