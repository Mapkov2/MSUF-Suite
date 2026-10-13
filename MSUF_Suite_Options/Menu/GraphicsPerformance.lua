local _, P = ...
local Suite = P.Suite
local Graphics = {}
P.GraphicsPerformance = Graphics

-- Native owners: upstream/live and upstream/forever, Blizzard_Settings_Shared/
-- Mainline/GraphicsOverrides.lua and SettingsDefinitions_Shared/Graphics.lua.
-- Quality CVars use zero-based indices. This service runs only on a click;
-- no login, profile, instance, event or timer callback applies a preset.
local DEFINITIONS = {
    { key = "graphicsShadowQuality", label = "Shadow quality", balanced = "2", raid = "1" },
    { key = "graphicsLiquidDetail", label = "Liquid detail", balanced = "1", raid = "1" },
    { key = "graphicsSSAO", label = "Ambient occlusion", balanced = "0", raid = "0" },
    { key = "graphicsDepthEffects", label = "Depth effects", balanced = "0", raid = "0" },
    { key = "graphicsComputeEffects", label = "Compute effects", balanced = "0", raid = "0" },
    { key = "graphicsViewDistance", label = "View distance", balanced = "4", raid = "2", slider = true },
    { key = "graphicsEnvironmentDetail", label = "Environment detail", balanced = "4", raid = "2", slider = true },
    { key = "graphicsGroundClutter", label = "Ground clutter", balanced = "2", raid = "0", slider = true },
    { key = "graphicsSpellDensity", label = "Spell density", balanced = "0", raid = "0",
        capability = "IsSpellVisualDensitySystemSupported" },
    { key = "graphicsProjectedTextures", label = "Projected textures", balanced = "1", raid = "1", toggle = true },
    { key = "RAIDsettingsEnabled", label = "Separate raid and dungeon graphics", raid = "1", toggle = true },
    { key = "ResampleAlwaysSharpen", label = "Resample sharpening", optional = "sharpen", value = "1", toggle = true },
    { key = "Contrast", label = "Contrast", optional = "contrast", value = "55" },
    { key = "Sound_EnableReverb", label = "Audio reverb", optional = "reverb", value = "0", toggle = true },
}
local byKey = {}
for _, definition in ipairs(DEFINITIONS) do
    byKey[definition.key] = definition
    if definition.key:sub(1, 8) == "graphics" then
        byKey["raidG" .. definition.key:sub(2)] = definition
    end
end

local function Read(key)
    local value = C_CVar.GetCVar(key)
    if Suite.IsSecret(value) or type(value) ~= "string" or #value > 64 then return nil end
    return value
end

local function Same(left, right)
    if left == nil or right == nil then return false end
    if left == right then return true end
    local a, b = tonumber(left), tonumber(right)
    return a ~= nil and b ~= nil and a == b
end

local function Supported(definition, key, wanted)
    if definition.capability then
        local value = C_VideoOptions.IsSpellVisualDensitySystemSupported()
        if Suite.IsSecret(value) or value ~= true then return false end
    end
    if definition.key:sub(1, 8) == "graphics" and not definition.slider then
        local status = IsGraphicsSettingValueSupported(key, tonumber(wanted), key:sub(1, 4) == "raid")
        return not Suite.IsSecret(status) and type(status) == "number" and status == 0
    end
    return true
end

local function ClientKey()
    local flavor = Suite.Client.flavor
    if flavor == "Mainline" or flavor == "Forever" then return flavor end
end

local function Recovery(create)
    local root, client = Suite.RootDB, ClientKey()
    if not root or not client then return nil end
    if type(root.graphicsRecovery) ~= "table" then
        if not create then return nil end
        root.graphicsRecovery = {}
    end
    if type(root.graphicsRecovery[client]) ~= "table" then
        if not create then return nil end
        root.graphicsRecovery[client] = {}
    end
    return root.graphicsRecovery[client]
end

local function Display(definition, value)
    if definition.toggle then return value == "0" and P.Tr("Off") or P.Tr("On") end
    if definition.slider then return tostring((tonumber(value) or 0) + 1) end
    if definition.key == "graphicsSpellDensity" then
        if value == "0" then return P.Tr("Essential") end
        if value == "1" then return P.Tr("Reduced") end
        if value == "2" then return P.Tr("All") end
    elseif definition.key ~= "Contrast" then
        local quality = definition.key == "graphicsShadowQuality" or definition.key == "graphicsLiquidDetail"
        if value == "0" then return quality and P.Tr("Low") or P.Tr("Disabled") end
        if value == "1" then return quality and P.Tr("Fair") or P.Tr("Low") end
        if value == "2" then return P.Tr("Medium") end
        if value == "3" then return P.Tr("High") end
        if value == "4" then return P.Tr("Ultra") end
        if value == "5" and quality then return P.Tr("Ultra High") end
    end
    return value
end

function Graphics.Plan(mode, options)
    if not ClientKey() or (mode ~= "balanced" and mode ~= "raid") then return {} end
    local rows = {}
    for _, definition in ipairs(DEFINITIONS) do
        local wanted = definition[mode]
        if definition.optional and options and options[definition.optional] then wanted = definition.value end
        local key = definition.key
        if mode == "raid" and key:sub(1, 8) == "graphics" then key = "raidG" .. key:sub(2) end
        local current = wanted and Read(key) or nil
        if current and not Supported(definition, key, wanted) then current = nil end
        if current then
            rows[#rows + 1] = { key = key, before = current, value = wanted, label = definition.label,
                from = Display(definition, current), to = Display(definition, wanted) }
        end
    end
    return rows
end

function Graphics.PendingCount()
    local count = 0
    for key, entry in pairs(Recovery(false) or {}) do
        if byKey[key] and type(entry) == "table" then count = count + 1 end
    end
    return count
end

local function ValidEntry(key, entry)
    return byKey[key] ~= nil and type(entry) == "table"
        and type(entry.before) == "string" and #entry.before <= 64 and tonumber(entry.before) ~= nil
        and type(entry.applied) == "string" and #entry.applied <= 64 and tonumber(entry.applied) ~= nil
end

-- A stale preview never changes anything. Snapshot every changed CVar before
-- the first write, including the RAIDsettingsEnabled switch applied last.
function Graphics.Apply(rows)
    if P.Combat() then return nil, "combat" end
    if not ClientKey() or not Suite.RootDB or #rows == 0 then return nil, "unavailable" end
    for _, row in ipairs(rows) do
        local definition = byKey[row.key]
        if not definition or not Supported(definition, row.key, row.value)
            or not Same(Read(row.key), row.before) then return nil, "stale" end
    end
    local saved, created = Recovery(true), {}
    for _, row in ipairs(rows) do
        if not Same(row.before, row.value) then
            if not ValidEntry(row.key, saved[row.key]) then
                saved[row.key] = { before = row.before, applied = row.value }
                created[row.key] = true
            end
        end
    end
    local result = { changed = 0, failed = 0 }
    for _, row in ipairs(rows) do
        if not Same(row.before, row.value) then
            if P.Combat() then return result, "combat" end
            local previous = saved[row.key].applied
            saved[row.key].applied = row.value
            C_CVar.SetCVar(row.key, row.value)
            local actual = Read(row.key)
            if Same(actual, row.value) then
                saved[row.key].applied = actual
                result.changed = result.changed + 1
            else
                result.failed = result.failed + 1
                if Same(actual, row.before) then
                    if created[row.key] then saved[row.key] = nil else saved[row.key].applied = previous end
                elseif actual and tonumber(actual) then
                    saved[row.key].applied = actual
                end
            end
        end
    end
    return result
end

-- Restore only values still matching our last successful write. A manual
-- edit wins. Unreadable/unavailable values retain their backup for a retry.
function Graphics.Restore()
    if P.Combat() then return nil, "combat" end
    local saved = Recovery(false)
    local result = { changed = 0, failed = 0, preserved = 0 }
    for key, entry in pairs(saved or {}) do
        if not ValidEntry(key, entry) then
            saved[key] = nil
        else
            local current = Read(key)
            if current == nil then
                result.failed = result.failed + 1
            elseif not Same(current, entry.applied) then
                result.preserved = result.preserved + 1
                saved[key] = nil
            else
                if P.Combat() then return result, "combat" end
                local supported = Supported(byKey[key], key, entry.before)
                if supported then C_CVar.SetCVar(key, entry.before) end
                local actual = supported and Read(key) or nil
                if supported and Same(actual, entry.before) then
                    saved[key] = nil
                    result.changed = result.changed + 1
                else
                    result.failed = result.failed + 1
                    if actual and tonumber(actual) then entry.applied = actual end
                end
            end
        end
    end
    return result
end
