local root = assert(arg[1], "repository root required"):gsub("\\", "/")
local baseline = os.getenv("SUITE_A1_BASELINE")
local originalLoad = loadfile
-- Read-only per-file baseline overlays; never roll back a working-tree file.
if baseline then
    loadfile = function(path)
        local relative = path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2)
        local candidate = relative and baseline .. "/" .. relative
        local handle = candidate and io.open(candidate, "rb")
        if handle then handle:close(); return originalLoad(candidate) end
        return originalLoad(path)
    end
end
local function RunContract(file, tail)
    local handle = assert(io.open(root .. "/tools/tests/" .. file, "rb"))
    local source = handle:read("*a"); handle:close()
    assert(loadstring(source .. "\n" .. tail, "@" .. file))()
end

RunContract("suite_skin_motion_contract.lua", [[
local B = dofile(root .. "/tools/tests/menu_apply_budgets.lua")
NS.Theme.SetAppearance("menuAnimations", true)
local target, owner, token = Target("Frame", UIParent), {}, 1
assert(client:AnimateContent(target, token))
local record = NS.ContentMotion.records[target]
local native = B.Methods(UIParent, B.Methods(target, B.Methods(record.group, B.Methods(record.alpha))))
native[issecretvalue] = true
local function Page()
    record.group.playing = false
    record.group.scripts.OnFinished(record.group)
    token = token + 1
    assert(client:AnimateContent(target, token))
end
local vm = B.Measure("page-switch", Page, native)
B.Limit(vm, 900, "settled page switch")
vm = B.Measure("interrupted-page-switch", function()
    record.group.progress = .5
    token = token + 1
    assert(client:AnimateContent(target, token))
end, native)
B.Limit(vm, 1080, "interrupted page switch")
local vm, kb, calls = B.Measure("unchanged-content", function()
    assert(client:AnimateContent(target, token))
end, native)
B.Limit(vm, 720, "unchanged content")
Page()
assert(record.alpha.FromAlpha == 0 and record.alpha.ToAlpha == .4 and record.alpha.Duration == .12)
assert(record.alpha.Smoothing == "OUT" and foreignWrites == 0)
local opening = Target("Frame", UIParent)
NS.ContentMotion.Watch(opening, owner)
opening:Hide(); opening:Show()
local openingRecord = NS.ContentMotion.records[opening]
native = B.Methods(opening, B.Methods(openingRecord.group, B.Methods(openingRecord.alpha)))
native[issecretvalue] = true
B.Measure("menu-open", function() opening:Hide(); opening:Show() end, native)
-- Protection remains dynamic even after successful cached animation reuse.
target.forbidden = true
assert(not client:AnimateContent(target, token + 1))
target.forbidden, target.protected = false, true
assert(not client:AnimateContent(target, token + 1))
target.protected = false
assert(client:AnimateContent(target, token + 1))
native = B.Methods(target)
native[issecretvalue] = true
vm = B.Measure("protection-100", function()
    for _ = 1, 100 do
        local protected, explicit = NS.Safety.GetProtection(target)
        assert(not protected and not explicit)
    end
end, native)
B.Limit(vm, 9000, "protection validation")
-- A completed child still yields to an opening parent, even for an old token.
NS.ContentMotion.StopOwner(owner)
local ancestor = Target("Frame", UIParent)
local child = Target("Frame", ancestor)
assert(NS.ContentMotion.Play(child, owner, 1))
local childRecord = NS.ContentMotion.records[child]
childRecord.group.playing = false
childRecord.group.scripts.OnFinished(childRecord.group)
assert(NS.ContentMotion.Play(ancestor, owner, 1))
assert(not NS.ContentMotion.Play(child, owner, 1), "duplicate child token bypassed opening ancestor")
]])

RunContract("suite_profile_variants_contract.lua", [[
local B = dofile(root .. "/tools/tests/menu_apply_budgets.lua")
Suite.Suite.Normalize(Suite.DB)
local modules = Suite.DB.suite.modules
local native = { [math.min] = true, [math.max] = true, [math.floor] = true }
local snapshot
local vm, kb = B.Measure("history-snapshot", function()
    local valid; snapshot, valid = provider.Snapshot(modules); assert(valid)
end, native)
assert(kb < 1024, "Suite snapshot exceeds 1 MB without the tracer")
B.Limit(vm, 450000, "snapshot validation")
local other = assert(provider.Snapshot(modules))
local original = snapshot.actionbars.enabled
other.actionbars.enabled = not original
assert(snapshot.actionbars.enabled == original and modules.actionbars.enabled == original,
    "mutable snapshots share rows with each other or the live profile")
assert(provider.Restore(modules, other) and modules.actionbars.enabled == not original)
assert(provider.Restore(modules, snapshot) and modules.actionbars.enabled == original)
local receiptPath = os.getenv("SUITE_A1_RECEIPT")
if receiptPath then
    local rows = {}
    for id, values in pairs(snapshot) do
        for key, value in pairs(values) do
            rows[#rows + 1] = id .. "." .. key .. "=" .. type(value) .. ":" .. tostring(value)
        end
    end
    table.sort(rows)
    local handle = assert(io.open(receiptPath, "wb"))
    handle:write(table.concat(rows, "\n")); handle:close()
end
local rule = Suite.SuiteCatalog.objectives.rules.width
assert(rule and type(rule.default) == "number")
local _, allocated = B.Measure("checked-value-14385", function()
    for i = 1, 14385 do assert(Suite.Suite.CheckProfileValue(rule, rule.default) == rule.default) end
end, native)
assert(allocated < 1, "scalar validation allocated")
]])

local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local W = H.New(root, arg[2] or "Mainline", { beforeModules = function(world)
    world.G.C_Container = { GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end }
    world.G.UnitLevel = function() return 20 end
    world.G.UnitXP = function() return 200 end
    world.G.UnitXPMax = function() return 1000 end
end })
W.LoadAddon("MSUF_Suite_DataTexts")
local S, G = W.S, W.G
local variants = assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))
setfenv(variants, G); variants("MSUF_Suite", W.Suite)
H.Enable(W)
assert(S.Set("dataTexts", "enabled", true))
assert(S.Set("dataTexts", "bar1Enabled", true))
local B = dofile(root .. "/tools/tests/menu_apply_budgets.lua")
local native = {}
for _, frame in ipairs(W.frames) do B.Methods(frame, native) end
native[G.issecretvalue], native[G.RegisterStateDriver], native[G.UnregisterStateDriver] = true, true, true
local registered, removed, refreshed = 0, 0, 0
local register, unregister = G.MSUF_EditModeAPI.RegisterElement, G.MSUF_EditModeAPI.UnregisterOwner
G.MSUF_EditModeAPI.RegisterElement = function(...)
    registered = registered + 1
    return register(...)
end
G.MSUF_EditModeAPI.UnregisterOwner = function(...)
    removed = removed + 1
    return unregister(...)
end
G.MSUF_EditModeAPI.RefreshOwner = function(owner)
    refreshed = refreshed + 1
    for key, mover in pairs(W.movers) do
        if key:sub(1, #owner + 1) == owner .. "/" then
            mover.receiptEnabled = mover.isEnabled()
            local frame = mover.getFrame()
            mover.receiptWidth = frame and frame:GetWidth()
        end
    end
end
local function Enter() S.SetEditMode(true) end
local function Leave() S.SetEditMode(false) end
-- Warm both visibility states before measuring just one transition.
Enter(); Leave()
registered, removed = 0, 0
B.Measure("edit-enter", Enter, native, Leave)
B.Measure("edit-exit", Leave, native, Enter)
if not os.getenv("SUITE_A1_MEASURE_ONLY") then
    assert(registered == 0 and removed == 0, "Edit Mode rebuilt unchanged DataTexts movers")
    assert(refreshed > 0, "unchanged registration skipped host handle refresh")
end
local barMover = assert(W.movers["MSUFSuite.dataTexts/bar1"])
assert(S.SetMany("dataTexts", { bar1FullScreen = false, bar1Vertical = false, bar1Layout = 1 }))
local oldWidth = barMover.getFrame():GetWidth()
assert(S.Set("dataTexts", "bar1Width", 321))
if not os.getenv("SUITE_A1_MEASURE_ONLY") then
    assert(barMover.receiptWidth ~= oldWidth and barMover.receiptWidth == barMover.getFrame():GetWidth(),
        "changed geometry left the mover stale: " .. tostring(oldWidth) .. "/" ..
        tostring(barMover.receiptWidth) .. "/" .. tostring(barMover.getFrame():GetWidth()))
end
assert(S.Set("dataTexts", "bar1Enabled", false))
if not os.getenv("SUITE_A1_MEASURE_ONLY") then
    assert(barMover.receiptEnabled == false, "disabled bar left its mover visible")
end
assert(S.Set("dataTexts", "bar1Enabled", true))
S.SetEditMode(false)
assert(S.Set("dataTexts", "bar1Name", "Renamed"))
assert(W.movers["MSUFSuite.dataTexts/bar1"].label == "Renamed", "renamed mover label is stale")
assert(S.Set("dataTexts", "enabled", false))
assert(not W.movers["MSUFSuite.dataTexts/bar1"])
assert(S.Set("dataTexts", "enabled", true))
assert(W.movers["MSUFSuite.dataTexts/bar1"], "re-enabled module lost its movers")
assert(S.SetMany("dataTexts", { barIds = "0", bar1Enabled = false }))
assert(not W.movers["MSUFSuite.dataTexts/bar1"], "removed bar retained its mover")
assert(S.SetMany("dataTexts", { barIds = "1", bar1Enabled = true }))
assert(W.movers["MSUFSuite.dataTexts/bar1"].getFrame() == S.instances.dataTexts.bars[1].frame,
    "pooled bar did not regain its mover")
local db = W.Suite.Database
local activeName = db.GetActiveProfileName()
local copy = W.Suite.CopyValue(W.Suite.DB)
copy.suite.modules.dataTexts.bar1Name = "Other profile"
assert(db.CreateFromProfile("A1 test profile", copy) and db.Activate("A1 test profile"))
assert(W.movers["MSUFSuite.dataTexts/bar1"].label == "Other profile")
assert(db.Activate(activeName) and W.movers["MSUFSuite.dataTexts/bar1"].label == "Renamed")
-- A nested/follower apply already paints the new state. Do not paint it again
-- when the outer Edit Mode loop reaches that module.
local owners
for i = 1, 20 do
    local name, value = debug.getupvalue(S.SetEditMode, i)
    if name == "owners" then owners = value; break end
end
local lead = assert(next(owners))
local other = lead == "dataTexts" and "minimap" or "dataTexts"
local leadInstance, otherInstance = S.instances[lead], S.instances[other]
local leadRefresh, otherRefresh, count = leadInstance.Refresh, otherInstance.Refresh, 0
leadInstance.Refresh = function(self) leadRefresh(self); S.Apply(other) end
otherInstance.Refresh = function(self) count = count + 1; otherRefresh(self) end
S.SetEditMode(true); S.SetEditMode(true); S.SetEditMode(false)
if not os.getenv("SUITE_A1_MEASURE_ONLY") then assert(count == 2, "nested transition applied twice") end
leadInstance.Refresh, otherInstance.Refresh = leadRefresh, otherRefresh
W.combat = true
S.SetEditMode(true)
assert(S.states.dataTexts.editMode ~= true, "combat apply refreshed a protected module")
S.SetEditMode(false)
W.combat = false
W.Event("PLAYER_REGEN_ENABLED")
assert(S.states.dataTexts.editMode ~= true, "queued transition restored stale Edit Mode")
print("PASS menu/apply snapshots, dynamic protection, mover rename and re-enable")
