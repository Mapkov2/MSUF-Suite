-- Owned overview only: no installation, saved settings or optional addon loads.
local root = assert(arg[1], "repository root required")
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local Suite = H.Setup({ root = root, uiWidth = 800, uiHeight = 600 })
local Preview, Model = assert(Suite.InstallerPreview), assert(Suite.InstallerPreviewModel)
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Copy(item) end
    return copy
end
local saved, rootDB = Copy(MSUF_DB), Copy(Suite.RootDB)
local frames = { player = { width = 275, height = 40, offsetX = -326, offsetY = -180 },
    bars = { classPowerWidthMode = "player", classPowerOffsetX = 0, classPowerOffsetY = -41, classPowerHeight = 4 } }
local modules = { actionbars = { enabled = true, bar3Point = 7, bar3X = 2480, bar3Y = 236,
    bar3Buttons = 12, bar3Rows = 12, bar3Size = 40, bar3Spacing = 2,
    bar5Point = 7, bar5X = 2520, bar5Y = 233, bar5Buttons = 12, bar5Rows = 12,
    bar5Size = 40, bar5Spacing = 2, bar5Visibility = Suite.ActionBarEnum.VISIBILITY.NEVER },
    dataTexts = { enabled = true, bar1Enabled = true, bar1Point = 8, bar1X = 1020, bar1Y = 170,
        bar1Width = 521, bar1Height = 26 },
    cooldownManager = { enabled = true, ess_x = -14, ess_y = -218, ess_size = 40, ess_spacing = 0 },
    damageMeter = { enabled = true, bgColor = "101010", borderColor = "333333", barColor = "e6ecf2" } }
local profile, original = { suite = { modules = modules } }, Copy(modules)
local function ByKey(scene, key)
    for _, item in ipairs(scene) do if item.key == key then return item end end
end
Suite.Client.isForever = true
local scene = Model.Build(profile, frames, "classic")
local player, resource = assert(ByKey(scene, "player")), assert(ByKey(scene, "resource"))
assert(player.x == 816.5 and player.y == 880, "factory player does not use CENTER offsets")
assert(resource.x == 816.5 and resource.y == 923 and resource.width == 275,
    "resource offsets did not resolve relative to the player TOPLEFT")
assert(ByKey(scene, "bar5") == nil, "a permanently hidden action bar appears in the overview")
local right = assert(ByKey(scene, "bar3"))
assert(right.x == 2480 and right.width == 40 and right.height == 502,
    "Modern installer edge conversion changed its action bar geometry")
assert(ByKey(scene, "data1").x == 2039, "Modern data text did not stay on the right edge")
assert(ByKey(scene, "cooldowns").y == 938, "sample Essential row ignores its staged screen offset")
assert(Equal(modules, original), "preview edge anchoring edited the cached factory")
Suite.Client.isForever = false
local modern = Model.Build(profile, frames, "classic")
assert(modern.resource.x == 816.5 and modern.resource.y == 923 and not modern.playerPower,
    "Modern inherited the Retail-Forever resource stack")
local retail = Model.Build(profile, frames, "forever")
local stacked, essential = assert(ByKey(retail, "resource")), assert(ByKey(retail, "cooldowns"))
assert(stacked.x == essential.x and stacked.width == essential.width and stacked.y == essential.y - 18,
    "Retail installer resource-stack follow-up is absent from the sample")
local power = assert(ByKey(retail, "playerPower"))
assert(power.y + power.height == essential.y - 4, "detached sample power loses the Essential gap")
assert(frames.bars.classPowerWidthMode == "player" and frames.bars.classPowerOffsetY == -41,
    "sample stack altered the cached frame factory")
local disabled = Model.Build(profile, frames, "classic", { actionbars = false, dataTexts = false })
assert(not ByKey(disabled, "bar1") and not ByKey(disabled, "data1"), "module choices do not reach the preview")
assert(Equal(modules, original), "preview choices changed cached module enable states")
local window = H.Widget("Frame")
window:SetSize(580, 470)
function window:SetScale(scale) self.scale = scale end
Preview.Build(window, function() return profile end, function() return frames end)
assert(not window.layoutPreview:IsShown(), "overview is visible outside the profile step")
Preview.Show(window, true, "classic")
assert(window:GetWidth() == 940 and window.scale < 1 and window:GetWidth() * window.scale <= 768,
    "expanded installer escapes a small viewport")
local regions = #window.layoutPreview.regions
-- Reused row textures must regain full opacity when they become icons.
local compactModules = { damageMeter = modules.damageMeter }
local compactProfile = { suite = { modules = compactModules } }
local current = compactProfile
local pooledWindow = H.Widget("Frame")
pooledWindow:SetSize(580, 470)
Preview.Build(pooledWindow, function() return current end, function() return nil end)
Preview.Show(pooledWindow, true, "forever")
local pooled = pooledWindow.layoutPreview.regions[1]
assert(pooled.details[1]:GetAlpha() == .8, "sample meter does not use muted rows")
current = { suite = { modules = { actionbars = modules.actionbars } } }
Preview.Show(pooledWindow, true, "forever")
assert(pooledWindow.layoutPreview.regions[1] == pooled and pooled.details[1]:GetAlpha() == 1,
    "pooled icons retained the meter's muted alpha")
Preview.Show(window, true, "classic")
assert(#window.layoutPreview.regions == regions, "refresh allocated another set of overview widgets")
Preview.Show(window, false, "classic")
assert(window:GetWidth() == 580 and window.scale == 1 and not window.layoutPreview:IsShown(),
    "leaving the profile step retained its expanded layout")
-- Host bridges cache successes, retry unavailable exports, and choose the
-- same host factory as ApplyClassic/ApplyForever on both supported clients.
local bridge, decode = Suite.HostBridge, MSUF_TryDecodeCompactString
MSUF_TryDecodeCompactString = nil
assert(bridge.FactoryFramePreview("classic") == nil, "missing host codec did not fail closed")
local decodes, last = 0
MSUF_TryDecodeCompactString = function(compact)
    decodes, last = decodes + 1, compact
    return { payload = frames }
end
MSUF_NS.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = "MSUF3:new-host"
assert(bridge.FactoryFramePreview("classic") == frames and last == "MSUF3:new-host", "host factory was ignored")
assert(bridge.FactoryFramePreview("classic") == frames and decodes == 1, "frame factory was decoded every refresh")
Suite.Client.isForever = true
MSUF_NS.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT = "MSUF3:forever-host"
assert(bridge.FactoryFramePreview("forever") == frames and last == "MSUF3:forever-host", "Forever host factory was ignored")
MSUF_TryDecodeCompactString = decode
assert(Equal(MSUF_DB, saved) and Equal(Suite.RootDB, rootDB) and #H.appliedScales == 0,
    "overview changed saved settings or applied a global UI scale")
assert(next(H.loaded) == nil and #H.reported == 0, "overview loaded an optional addon or raised a client error")
print("installer overview: resource anchors, hidden bars, module choices, viewport, cache and read-only state passed")
