-- Appended inside the existing real motion world's lexical scope.
local measureOnly = os.getenv("SUITE_A7_MEASURE_ONLY")
local function Require(value, message)
    if not measureOnly then Check(value, message) end
end
NS.Theme.SetAppearance("menuAnimations", true)
NS.Theme.SetAppearance("reduceMotion", false)
native[issecretvalue], native[InCombatLockdown], native[CreateColor], native[CreateFrame] = true, true, true, true
B.Methods(UIParent, native)
local sequence, targets, pageRoot, pageClient, serial = 0, nil, nil, nil, 0
local directOwner = {}
local function Prepare(count, hidden)
    NS.ContentMotion.StopOwner(directOwner)
    sequence = sequence + 1
    if pageClient then pageClient:ReleaseAll() end
    pageClient = host
    pageRoot = Target("Frame", UIParent)
    pageRoot.children, targets = {}, {}
    suite.Public = NS.Safety.Public
    MSUFSuite, MSUF2_Window = suite, pageRoot
    for index = 1, count do
        local frame = Target("Button", pageRoot, index * 10, 0)
        targets[index], pageRoot.children[index] = frame, frame
    end
    if hidden then pageRoot:Hide() end
    providedClient = pageClient
    compatibilitySuite.Skin.RegisterMenu = function(frame, _, contentOnly)
        return pageClient:RegisterMenu(frame, contentOnly)
    end
end
local function Measure(label, callback, prepare)
    return B.Measure(label, callback, native, prepare, SetNativePass)
end
local function PageSwitch()
    serial = serial + 1
    pageCallback(pageRoot, serial)
end
for _, count in ipairs({ 20, 300 }) do
    Measure("Content.Play-cold-" .. count, function()
        serial = serial + 1
        assert(NS.ContentMotion.Play(pageRoot, directOwner, serial))
    end, function() Prepare(count) end)
    local vm, kb, calls = Measure("page-switch-cold-" .. count, PageSwitch, function() Prepare(count) end)
    Require(vm < 2200 and calls < 60, "page switch walked descendants")
    local function FinishedPage()
        local record = NS.ContentMotion.records[pageRoot]
        record.group:Stop()
        record.group.scripts.OnFinished(record.group)
    end
    vm, kb, calls = Measure("page-switch-warm-" .. count, PageSwitch, FinishedPage)
    Require(vm < 2300 and kb < 1 and calls < 60, "warm page switch scales with its children")
    local record = NS.ContentMotion.records[pageRoot]
    Check(record.target == pageRoot and #record.group.animations == 1
        and record.alpha.Duration == 0.12 and record.alpha.Smoothing == "OUT"
        and record.toAlpha == pageRoot:GetAlpha(), "page fade presentation changed")
    Require(NS.MenuMotion.states[pageRoot] == nil, "explicit page acquired a tree observer")
    for _, child in ipairs(targets) do
        Check(NS.ContentMotion.records[child] == nil, "page fade touched a child")
    end
    pageClient:ReleaseAll()
end

local spec = { role = "navigation", activeRole = "navigationActive", ownedArt = true, motion = false, paletteMotion = true }
local function Requests()
    for _, frame in ipairs(targets) do
        assert(pageClient:SkinButton(frame, spec))
        assert(pageClient:SetActive(frame, true))
        assert(pageClient:Refresh(frame))
    end
end
local function ShowPage()
    pageRoot:Show()
    -- Native OnShow propagates to descendants when their parent becomes visible.
    for _, frame in ipairs(targets) do frame:Fire("OnShow") end
end
local vm, kb, calls = Measure("hidden-window-40", Requests, function() Prepare(40, true) end)
Require(vm < 100000 and kb < 60 and calls < 2900, "hidden window built skin art")
for _, frame in ipairs(targets) do
    Require(NS.Registry.GetSurface(frame) == nil, "unseen surface was skinned")
end
vm, kb, calls = Measure("build-show-window-40", function() Requests(); ShowPage() end, function() Prepare(40, true) end)
Require(vm < 300000 and kb < 730 and calls < 8300, "first show repeated the pending selection paint")
for _, frame in ipairs(targets) do
    local visual = assert(NS.Registry.GetSurface(frame))
    Check(visual.kind == "button" and visual.active and visual.visible and visual.spec.role == "navigation",
        "first show lost the final requested state")
    Check(visual.fill.shown and visual.edge.shown and frame.slots.Highlight == visual.highlight
        and frame.slots.Pushed == visual.pushed and frame.slots.Disabled == visual.disabled,
        "visible skin receipt differs")
end
print("RECEIPT window=40 navigation active fill edge highlight pushed disabled; page=single-alpha OUT 0.12; native-input=unchanged")
local rows = {}
local function Add(key, value) rows[#rows + 1] = key .. "=" .. tostring(value) end
local function Color(key, value)
    if not value then return end
    for _, channel in ipairs({ "r", "g", "b", "a" }) do Add(key .. "." .. channel, value[channel]) end
end
for index, frame in ipairs(targets) do
    local state = NS.Registry.GetSurface(frame)
    Add(index .. ".visible", state.visible)
    Add(index .. ".active", state.active)
    Add(index .. ".ownerAlpha", frame:GetAlpha())
    for _, key in ipairs({ "fill", "edge", "highlight", "pushed", "disabled", "depth" }) do
        local region = state[key]
        if region then
            local prefix = index .. "." .. key
            Add(prefix .. ".asset", region.asset)
            Add(prefix .. ".shown", region.shown)
            Add(prefix .. ".alpha", region.alpha)
            Add(prefix .. ".direction", region.direction)
            for channel = 1, 4 do Add(prefix .. ".color" .. channel, region.color[channel]) end
            Color(prefix .. ".from", region.first)
            Color(prefix .. ".to", region.last)
            for point, value in pairs(region.points) do
                Add(prefix .. "." .. point .. ".x", value.x)
                Add(prefix .. "." .. point .. ".y", value.y)
                Add(prefix .. "." .. point .. ".relativePoint", value.relativePoint)
                Check(value.relative == frame, "skin anchor lost its owner")
            end
        end
    end
end
table.sort(rows)
if os.getenv("SUITE_A7_RECEIPT") then
    local file = assert(io.open(os.getenv("SUITE_A7_RECEIPT"), "wb"))
    file:write(table.concat(rows, "\n"), "\n")
    file:close()
end
print("VISUAL RECEIPT " .. #rows .. " fields")

Prepare(2, true)
Requests()
local first, second = targets[1], targets[2]
pageClient:Release(first)
ShowPage()
Require(NS.Registry.GetSurface(first) == nil and NS.Registry.GetSurface(second) ~= nil,
    "released hidden skin was resurrected")
Prepare(2, true)
Requests()
pageClient:RefreshAll()
Require(NS.Registry.GetSurface(targets[1]) == nil, "RefreshAll forced hidden skin creation")
pageClient:ReleaseAll()
ShowPage()
Require(NS.Registry.GetSurface(targets[1]) == nil, "ReleaseAll resurrected pending skin")

vm, kb, calls = Measure("tab-container-register-300", function()
    assert(pageClient:RegisterMenu(pageRoot, true))
end, function() Prepare(300, true) end)
local tab = pageRoot
Require(calls < 80, "authored tab scanned children")
tab:Show()
Check(NS.ContentMotion.records[tab] and NS.ContentMotion.records[tab].group:IsPlaying(),
    "authored tab lost its first opening fade")
pageClient:ReleaseAll()
Check(not NS.ContentMotion.records[tab].group:IsPlaying(), "tab release retained motion")
local secretTarget = Target("Frame", UIParent)
local accepted, reason = pageClient:RegisterMenu(secretTarget, secret)
Require(not accepted and reason == "invalid-options", "secret menu mode was accepted")
pageClient:Release(secretTarget)
Check(foreignWrites == 0, "menu lifecycle changed foreign alpha or anchors")
print("Suite menu lifecycle: hidden coalescing, release, page and tab receipts passed")

-- Real bridge lifecycle: native parent show precedes SelectPage on reopen.
Prepare(300)
local bridgeMenu = { cache = { home = { wrapper = pageRoot } }, activeKey = "home" }
bridgeMenu.SelectPage = function(key) bridgeMenu.activeKey = key end
suite.HostBridge.WatchMenuContent(bridgeMenu, pageCallback, function(frame)
    return pageClient:RegisterMenu(frame, true)
end)
bridgeMenu.SelectPage("home")
local opening = NS.ContentMotion.records[pageRoot]
local plays = opening.group.plays
pageRoot:Hide()
pageRoot:Show()
bridgeMenu.SelectPage("home")
Require(opening.group.plays == plays + 1, "cached page reopen lost or duplicated its fade")
Require(NS.MenuMotion.states[pageRoot] == nil, "bridge registered the page tree")
local rebuilt = Target("Frame", UIParent)
bridgeMenu.cache.home.wrapper = rebuilt
bridgeMenu.SelectPage("home")
Require(NS.ContentMotion.records[rebuilt] ~= nil, "same-key rebuilt wrapper lost its fade")
pageClient:ReleaseAll()
pageRoot:Hide()
pageRoot:Show()
Require(opening.group:IsPlaying(), "reacquired page lost its opening fade")

-- The lazy scope is exactly Options; foreign/other host controls retain eager
-- art when first shown in combat. No native combat writes are introduced.
local foreign = assert(api:RegisterAddon("A7Foreign"))
local function EagerFallback(message)
    local frame = Target("Button", pageRoot)
    frame:Hide()
    assert(pageClient:SkinButton(frame, spec))
    Check(NS.Registry.GetSurface(frame) ~= nil, message)
    pageClient:Release(frame)
end
local optionsRoot = MSUF2_Window
MSUF2_Window = nil
EagerFallback("unbuilt Options root deferred unrelated host art")
MSUF2_Window = optionsRoot
local optionsSurface = suite.HostBridge.IsOptionsSurface
suite.HostBridge.IsOptionsSurface = nil
EagerFallback("older Suite bridge lost eager host art")
suite.HostBridge.IsOptionsSurface = optionsSurface
local hiddenForeign = Target("Button", UIParent)
hiddenForeign:Hide()
assert(foreign:SkinButton(hiddenForeign, spec))
local eager = assert(NS.Registry.GetSurface(hiddenForeign))
lockdown = true
hiddenForeign:Show()
Check(NS.Registry.GetSurface(hiddenForeign) == eager, "foreign combat first-show lost prepared art")
lockdown = false
local otherHost = Target("Button", UIParent)
otherHost:Hide()
assert(host:SkinButton(otherHost, spec))
Check(NS.Registry.GetSurface(otherHost) ~= nil, "non-Options host skin became lazy")

-- Real host bridge acknowledgement and fallback suppression use 'applied'.
Prepare(1, true)
local accepted, reason = host:SkinFrame(pageRoot, { role = "shell" })
Check(accepted and reason == "applied", "hidden host skin rejected fallback ownership")
ShowPage()
local shell = assert(NS.Registry.GetSurface(pageRoot))
Check(shell.spec.role == "shell" and shell.spec.motion == false and shell.visible,
    "first-show shell changed host motion policy")
print("RECEIPT reopen=one-fade rebuild=fade reacquire=fade foreign-combat=eager shell=host-motion-off")
