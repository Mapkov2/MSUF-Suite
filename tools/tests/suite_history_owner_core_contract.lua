local root, host, flavor, mode = assert(arg[1]), assert(arg[2]), arg[3] or "Mainline", arg[4] or "contract"
local function Read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s:gsub("\r\n", "\n")
end
local World = assert(loadfile(host .. "/tools/tests/client_world.lua"))()
local world = World.New(host, flavor)
local loadOriginal = world.LoadFile
function world:LoadFile(path, addon, ns)
    local base, rel
    if path:sub(1, #host + 1) == host .. "/" then base, rel = os.getenv("MSUF_HISTORY_HOST_BASE"), path:sub(#host + 2)
    elseif path:sub(1, #root + 1) == root .. "/" then base, rel = os.getenv("MSUF_HISTORY_SUITE_BASE"), path:sub(#root + 2) end
    if base and rel then
        local target = base .. "/" .. rel
        local file = io.open(target, "rb")
        if file then file:close(); path = target end
    end
    return loadOriginal(self, path, addon, ns)
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env, core = world.env, world.core
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
env.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local frames = { general = {} }
env.MSUF_GlobalDB = { profiles = { Default = frames }, global = {} }
env.MSUF_DB, env.MSUF_ActiveProfile = frames, "Default"
local H, W, F, V = core.History, core.ProfileWorkbench, core.ProfileFields, core.ProfileVariants
local counts = { rootCapture = 0, rootRestore = 0, workbenchCapture = 0, workbenchRestore = 0,
    optionsCapture = 0, optionsRestore = 0, baseSettings = 0 }
local registerExternal = F.RegisterExternal
F.RegisterExternal = function(key, provider)
    local capture, restore = provider.Snapshot, provider.Restore
    provider.Snapshot = function(...) counts.rootCapture = counts.rootCapture + 1; return capture(...) end
    provider.Restore = function(...) counts.rootRestore = counts.rootRestore + 1; return restore(...) end
    return registerExternal(key, provider)
end
local registerWorkbench = W.RegisterProvider
W.RegisterProvider = function(key, provider)
    local capture, restore = provider.Capture, provider.Restore
    provider.Capture = function(...) counts.workbenchCapture = counts.workbenchCapture + 1; return capture(...) end
    provider.Restore = function(...) counts.workbenchRestore = counts.workbenchRestore + 1; return restore(...) end
    return registerWorkbench(key, provider)
end
local registerHistory = core.HistoryProviders.Register
core.HistoryProviders.Register = function(key, capture, restore, ...)
    if key == "MSUF_Suite" then
        local c, r = capture, restore
        capture = function(...) counts.optionsCapture = counts.optionsCapture + 1; return c(...) end
        restore = function(...) counts.optionsRestore = counts.optionsRestore + 1; return r(...) end
    end
    return registerHistory(key, capture, restore, ...)
end
local function Load(addon, ns)
    for line in Read(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc"):gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local ok, why = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, ns)
            assert(ok, addon .. "/" .. line .. ": " .. tostring(why))
        end
    end
    loaded[addon] = true
end
Load("MSUF_Suite", {})
local Suite = assert(env.MSUFSuite)
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
assert(Suite.ProfileVariants.Register())
local baseSettings = Suite.ProfileVariants.BaseSettings
Suite.ProfileVariants.BaseSettings = function(...) counts.baseSettings = counts.baseSettings + 1; return baseSettings(...) end
local options = {}
Load("MSUF_Suite_Options", options)
local function Reset() for key in pairs(counts) do counts[key] = 0 end end
local function Print(label)
    local keys = {}; for key in pairs(counts) do keys[#keys + 1] = key end; table.sort(keys)
    local out = { label }; for _, key in ipairs(keys) do out[#out + 1] = key .. "=" .. counts[key] end
    print(table.concat(out, " "))
end
if mode == "legacy" then
    local legacy = {}
    local legacyBase = assert(arg[5], "frozen original Suite source required")
    local ok, why = world:LoadFile(legacyBase .. "/MSUF_Suite_Options/Menu/Bridge.lua", "LegacyOptions", legacy)
    assert(ok, why)
    legacy.Refresh = function() end
    local state = assert(legacy.CaptureHistoryState())
    local name = Suite.Database.GetActiveProfileName()
    local oldProfile = state.root.profiles[name]
    local function ResetLegacy()
        Suite.RootDB.skinEnabled, Suite.Skin.enabled = true, true
        Suite.DB.suite.moduleState = { minimap = { detachedButtons = { "keep" } } }
    end
    local function Result()
        return { skin = Suite.RootDB.skinEnabled, layout = Suite.CopyValue(Suite.DB.suite.moduleState.minimap.detachedButtons) }
    end
    for _, explicit in ipairs({ false, true }) do
        if explicit then state.root.skinEnabled, oldProfile.layoutState = false, {}
        else state.root.skinEnabled, oldProfile.layoutState = nil, nil end
        ResetLegacy()
        assert(legacy.RestoreHistoryState(Suite.CopyValue(state)))
        local expected = Result()
        ResetLegacy()
        local saved = Suite.CopyValue(state)
        assert(options.RestoreHistoryState(state))
        assert(F.Equal(expected, Result()), "legacy Options absence/false/empty semantics changed")
        assert(F.Equal(state, saved), "legacy reader changed its saved point")
    end
    print("PASS real old/new Options readers: absent flags/layout preserved; false/empty restored")
    return
end
local overlayBase
if mode == "overlay" or mode == "overlay-contract" then
    overlayBase = Suite.DB.suite.modules.objectives.width
    Suite.DB.suite.modules.loot.quickLoot = true
    frames.profileVariants = { version = 1, entries = { { name = "History overlay", conditions = {}, patch = {
        { path = { "suiteModules", "objectives", "width" }, value = overlayBase + 100 },
        { path = { "player", "width" }, value = 321 },
    } } } }
    assert(V.Resolve(frames) and Suite.DB.suite.modules.objectives.width == overlayBase + 100, "real overlay did not resolve")
end
if mode == "refusal" then
    assert(H.RegisterHistoryProvider("refusing-owner", function() return false end, function() return true end))
    local before = F.CopySnapshot(env.MSUF_DB)
    local ok, point = pcall(H.CaptureGuidedTourRestorePoint)
    assert(ok and point == nil, "guided capture refusal raised instead of returning nil")
    assert(F.Equal(before, env.MSUF_DB), "capture refusal changed core settings")
    print("PASS guided capture refusal")
    return
end
Reset()
local point = assert(H.CaptureGuidedTourRestorePoint())
Print("CAPTURE " .. flavor)
local width = Suite.DB.suite.modules.objectives.width
if overlayBase then
    local captured = point.externalProviders["workbench:suiteSkin"]
    assert(captured.suite.modules.objectives.width == overlayBase and captured.suite.modules.loot.quickLoot == true,
        "canonical history captured overlaid value or lost automation")
    Suite.DB.suite.modules.objectives.titleSize = Suite.DB.suite.modules.objectives.titleSize + 1
else Suite.DB.suite.modules.objectives.width = width + 20 end
Reset()
assert(H.RestoreGuidedTourRestorePoint(point))
assert(Suite.DB.suite.modules.objectives.width == width)
Print("RESTORE " .. flavor)
for _ = 1, 6 do assert(H.CaptureGuidedTourRestorePoint()) end
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10 do assert(H.CaptureGuidedTourRestorePoint()) end
    minimum = math.min(minimum, (collectgarbage("count") - before) / 10)
    collectgarbage("restart")
end
print(("ALLOCATION %s %.6f KiB/snapshot"):format(flavor, minimum))
if mode == "contract" or mode == "overlay-contract" then
    Reset(); assert(H.CaptureGuidedTourRestorePoint())
    assert(counts.workbenchCapture == 1 and counts.optionsCapture == 0 and counts.rootCapture == 0,
        "current Suite settings still have overlapping history capture owners")
end
print("PASS real Core+Suite history probe " .. flavor)
