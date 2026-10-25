-- Run the existing real motion lifecycle world, then measure its exact skin
-- operations. Baseline overlays never replace a file in the working tree.
local root = assert(arg[1]):gsub("\\", "/")
arg[1] = root
local baseline = os.getenv("SUITE_A4_BASELINE")
local originalLoad = loadfile
if baseline then
    loadfile = function(path)
        local relative = path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2)
        local candidate = relative and baseline .. "/" .. relative
        local handle = candidate and io.open(candidate, "rb")
        if handle then handle:close(); return originalLoad(candidate) end
        return originalLoad(path)
    end
end
local file = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
-- Only register newly created shim functions during the native-count pass.
-- Recording texture assets/gradients makes the visual receipts meaningful.
source = source:gsub("    return region\nend", [[
    function region:SetTexture(asset) self.asset = asset end
    function region:SetGradient(direction, first, last)
        self.direction, self.first, self.last = direction, first, last
    end
    function region:SetDrawLayer(layer, level) self.layer, self.level = layer, level end
    if nativePass then B.Methods(region, native) end
    return region
end]], 1)
source = source:gsub("    return target\nend", [[
    if nativePass then B.Methods(target, native) end
    return target
end]], 1)
local preamble = [[
local B = dofile(arg[1] .. "/tools/tests/skin_surface_bench.lua")
local native, nativePass = {}, false
local function SetNativePass(value) nativePass = value end
]]
local tail = [[
NS.Theme.SetAppearance("menuAnimations", true)
NS.Theme.SetAppearance("reduceMotion", false)
local probe = Target("Button", parent)
local probeState = Surface.SkinOwnedButton(probe, { role = "button", motion = true })
local function Upvalue(fn, wanted)
    for index = 1, 60 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
    error("missing real upvalue " .. wanted)
end
local canRefresh = Upvalue(probeState.refresh, "CanRefreshState")
native[issecretvalue], native[InCombatLockdown], native[CreateColor] = true, true, true
B.Methods(probe, native)
B.Methods(clock, native)
for _, key in ipairs({"fill", "edge", "depth", "highlight", "pushed", "disabled", "hoverOverlay"}) do
    if probeState[key] then B.Methods(probeState[key], native) end
end
local function Measure(label, callback, prepare)
    return B.Measure(label, callback, native, prepare, SetNativePass)
end
local vm, kb, calls = Measure("CanRefreshState-1100", function()
    for _ = 1, 1100 do assert(canRefresh(probeState)) end
end)
assert(kb < 1, "CanRefreshState allocated without the tracer")
vm, kb, calls = Measure("RefreshState-100", function()
    for _ = 1, 100 do assert(probeState.refresh(probeState)) end
end)
B.Limit(calls, 5600, "surface refresh safety")
assert(kb < 1, "warmed RefreshState allocated")
vm, kb, calls = Measure("unchanged-visible-100", function()
    for _ = 1, 100 do assert(Surface.SetVisible(probe, true)) end
end)
B.Limit(vm, 15500, "unchanged visibility")
B.Limit(calls, 700, "unchanged visibility natives")
local menuTargets, menuStates, menuClient
local serial = 0
local function PrepareMenu()
    serial = serial + 1
    menuClient = assert(api:RegisterAddon("A4Menu" .. serial))
    menuTargets, menuStates = {}, {}
    for index = 1, 20 do menuTargets[index] = Target("Button", parent, index * 100, 0) end
end
local spec = { role = "navigation", activeRole = "navigationActive", ownedArt = true, paletteMotion = true }
local function MenuOpen()
    for index = 1, #menuTargets do
        assert(menuClient:SkinButton(menuTargets[index], spec))
        menuStates[index] = assert(NS.Registry.GetSurface(menuTargets[index]))
    end
end
vm, kb, calls = Measure("menu-open-20-skins", MenuOpen, PrepareMenu)
B.Limit(kb, 380, "cold menu lazy motion")
for _, current in ipairs(menuStates) do
    if not os.getenv("SUITE_A4_MEASURE_ONLY") then
        assert(not current.paletteMotion.channels, "idle palette allocated spring channels")
        assert(not current.motion or not current.motion.channels, "idle surface allocated spring channels")
    end
end
local function PrepareSelection()
    for index = 1, #menuTargets do assert(menuClient:SetActive(menuTargets[index], false)) end
end
vm, kb, calls = Measure("page-switch-20-selections", function()
    for index = 1, #menuTargets do assert(menuClient:SetActive(menuTargets[index], index == 1)) end
end, PrepareSelection)
B.Limit(calls, 850, "selection protection pass")
local painted = Upvalue(probeState.refresh, "OnPalettePainted")
local material = NS.Theme.GetMaterial("button")
local snapshots
local function PrepareSnapshots()
    snapshots = {}
    for index = 1, 100 do snapshots[index] = { target = probe, spec = { paletteMotion = true } } end
end
vm, kb, calls = Measure("palette-first-paint-100", function()
    for index = 1, #snapshots do painted(snapshots[index], material) end
end, PrepareSnapshots)
B.Limit(kb, 100, "lazy palette records")
-- Real animation safety predicate, with fresh results on each object pass.
probe:Fire("OnEnter")
local safe = probeState.motion.safe
probe:Fire("OnLeave"); Tick()
vm, kb, calls = Measure("motion-safety-100", function()
    for _ = 1, 100 do assert(safe(probeState.motion)) end
end)
B.Limit(calls, 1100, "single object safety pass")
local getProtection, getVisible = probe.IsProtected, probe.IsVisible
probe.forbidden = true; assert(not safe(probeState.motion))
probe.forbidden, probe.protected = false, true; assert(not safe(probeState.motion))
local activeBefore, visibleBefore = probeState.active, probeState.visible
assert(not Surface.SetActive(probe, true) and not Surface.SetVisible(probe, false))
assert(probeState.active == activeBefore and probeState.visible == visibleBefore,
    "a new protection answer was bypassed by a prior setter pass")
probe.protected = false; assert(safe(probeState.motion))
probe.IsProtected = function() return secret, false end
assert(not safe(probeState.motion), "secret protection reused a public answer")
probe.IsProtected = function() return false, secret end
assert(not safe(probeState.motion), "secret explicit protection was ignored")
probe.IsProtected = getProtection
probe.IsVisible = function() return secret end
assert(not safe(probeState.motion), "secret visibility reached a truth test")
probe.IsVisible = getVisible; assert(safe(probeState.motion))
-- A cold record still uses the dynamic restore guard on hide/disable. The
-- deferred reset after combat must also work before spring promotion.
local cold = Target("Button", parent)
local coldState = Surface.SkinOwnedButton(cold, { role = "button", motion = true })
if not os.getenv("SUITE_A4_MEASURE_ONLY") then
    assert(not coldState.motion.channels, "cold surface allocated spring channels")
end
local writes = 0
local oldVertex = coldState.hoverOverlay.SetVertexColor
coldState.hoverOverlay.SetVertexColor = function(self, ...)
    writes = writes + 1; return oldVertex(self, ...)
end
cold.forbidden = true; cold:Fire("OnHide"); cold:Fire("OnDisable")
assert(writes == 0, "cold forbidden hide wrote artwork")
cold.forbidden, cold.protected, lockdown = false, true, true
clock:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
cold:Fire("OnHide"); cold:Fire("OnDisable")
assert(writes == 0 and Motion.deferred[coldState.motion], "cold protected hide bypassed combat deferral")
lockdown = false
clock:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
assert(writes > 0 and not Motion.deferred[coldState.motion], "cold restore did not resume after combat")
-- The first actual palette animation promotes the snapshot in place once.
local saved = menuStates[1].paletteMotion
local initial = saved.current[1]
NS.Theme.ApplyPreset("glass")
Surface.Refresh(menuTargets[1])
assert(saved == menuStates[1].paletteMotion and saved.channels and saved.index)
assert(saved.current[1] == initial, "lazy palette lost its pre-transition color")
local channels = saved.channels
Tick()
NS.Theme.ApplyPreset("midnight")
Surface.Refresh(menuTargets[1])
assert(saved.channels == channels, "palette did not reuse its channels")
Tick()
-- State and visual receipts: full lifecycle assertions above cover gestures,
-- selection order, interrupted travel, native resets, combat and releases.
local rows = {}
local function Add(key, value) rows[#rows + 1] = key .. "=" .. tostring(value) end
local function Color(key, value)
    if not value then return end
    Add(key .. ".r", value.r); Add(key .. ".g", value.g)
    Add(key .. ".b", value.b); Add(key .. ".a", value.a)
end
for index, current in ipairs(menuStates) do
    Add(index .. ".visible", current.visible); Add(index .. ".active", current.active)
    for _, key in ipairs({"fill", "edge", "highlight", "pushed", "disabled"}) do
        local region = current[key]
        local prefix = index .. "." .. key
        Add(prefix .. ".asset", region.asset); Add(prefix .. ".shown", region.shown)
        Add(prefix .. ".alpha", region.alpha); Add(prefix .. ".layer", region.layer)
        Add(prefix .. ".level", region.level); Add(prefix .. ".direction", region.direction)
        for channel = 1, 4 do Add(prefix .. ".color" .. channel, region.color[channel]) end
        Color(prefix .. ".from", region.first); Color(prefix .. ".to", region.last)
        for point, value in pairs(region.points) do
            Add(prefix .. "." .. point .. ".x", value.x); Add(prefix .. "." .. point .. ".y", value.y)
            Add(prefix .. "." .. point .. ".relativePoint", value.relativePoint)
            assert(value.relative == current.target, "surface anchor changed its owner")
        end
    end
end
table.sort(rows)
local receipt = os.getenv("SUITE_A4_RECEIPT")
if receipt then
    local output = assert(io.open(receipt, "wb"))
    output:write(table.concat(rows, "\n"), "\n"); output:close()
end
assert(foreignWrites == 0, "skin pass touched foreign geometry")
print("A4 surface behavior and visual receipts: " .. #rows .. " fields")
-- Make the trade explicit: lazy channels move their one-time allocation
-- from menu construction to the first real palette animation.
local function PrepareTransition()
    Motion.StopAll()
    NS.Theme.ApplyPreset("midnight")
    snapshots = {}
    for index = 1, 100 do
        local target = Target("Frame", parent)
        snapshots[index] = { target = target, spec = { paletteMotion = true }, visible = true,
            fill = target:CreateTexture(), edge = target:CreateTexture() }
        painted(snapshots[index], material)
    end
    NS.Theme.ApplyPreset("glass")
end
Measure("first-palette-transition-100", function()
    for index = 1, #snapshots do painted(snapshots[index], material) end
end, PrepareTransition)
Motion.StopAll()
]]
assert(loadstring(preamble .. source .. "\n" .. tail, "@a4-motion-world"))()
