local _, NS = ...

-- Numy's !!AddonProfiler owns all measurements, updates and row values.
-- Only its UI construction and user-driven pin additions are observed.
local Skin = {}
NS.AddonProfilerSkin = Skin
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local rows = setmetatable({}, { __mode = "k" })
local resizeRoots = setmetatable({}, { __mode = "k" })

local function Resized(button)
    local frame = resizeRoots[button]
    if frame and NS.AddonSkins.IsEnabled("addonProfiler") and not NS.AddonSkins.cooperative.addonProfiler then
        NS.AddonSkins.RefreshFrame(frame)
    end
end

local function ObserveResize(frame)
    local button = Safety.Field(frame, "ResizeButton")
    if not Visuals.Safe(button) or not Safety.HasMethod(button, "HookScript") or resizeRoots[button] then return end
    resizeRoots[button] = frame
    button:HookScript("OnMouseUp", Resized)
end

local function Labels(owner, ...)
    for index = 1, math.min(select("#", ...), 64) do Visuals.Label(select(index, ...), owner) end
end

local function CreatedLabel(row)
    local record = rows[row]
    if not record or not record.owner or not NS.AddonSkins.IsEnabled("addonProfiler")
        or NS.AddonSkins.cooperative.addonProfiler then return end
    -- Runs only when the native pool actually constructs a FontString, never
    -- on Acquire/UpdateColumns, which the profiler also calls while measuring.
    Labels(record.owner, Safety.Call(row, "GetRegions"))
end

local function ObserveRow(row, owner)
    if not Visuals.Safe(row) or not Safety.HasMethod(row, "CreateFontString") then return end
    local record = rows[row]
    if not record then
        record = {}
        rows[row] = record
        hooksecurefunc(row, "CreateFontString", CreatedLabel)
    end
    record.owner = owner
    Labels(owner, Safety.Call(row, "GetRegions"))
end

local function Background(owner, ...)
    -- The reviewed PinContainer has one anonymous direct background Texture;
    -- icons, data rows and the main window's controls are child objects.
    for index = 1, math.min(select("#", ...), 16) do Visuals.Fade(select(index, ...), owner) end
end

function Skin.Paint(frame, owner)
    local addon = rawget(_G, "NumyAddonProfiler")
    if frame == Safety.Field(addon, "ProfilerFrame") then
        ObserveResize(frame)
        ObserveRow(Safety.Field(frame, "TotalRow"), owner)
        local box = Safety.Field(frame, "ScrollBox")
        if Visuals.Safe(box) and Safety.HasMethod(box, "ForEachFrame") then
            local count = 0
            box:ForEachFrame(function(row)
                count = count + 1
                if count <= 256 then ObserveRow(row, owner) end
            end)
        end
    elseif frame == Safety.Field(addon, "PinContainer") then
        Background(owner, Safety.Call(frame, "GetRegions"))
        local header = Safety.Field(frame, "Header")
        ObserveRow(header, owner)
        Visuals.Fade(Safety.Field(header, "BG"), owner)
        local pinned = Safety.Field(frame, "pinnedAddons")
        if type(pinned) == "table" then
            local count = 0
            for _, row in pairs(pinned) do
                count = count + 1
                if count > 256 then break end
                ObserveRow(row, owner)
            end
        end
    end
end

function Skin.Release(owner)
    for _, record in pairs(rows) do if record.owner == owner then record.owner = nil end end
end
