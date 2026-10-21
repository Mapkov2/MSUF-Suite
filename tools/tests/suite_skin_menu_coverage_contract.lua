-- Real shared providers; no renderer or live combat/taint claim.
local root = assert(arg[1])
local before = arg[3]
arg[3] = "coverage"
local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
arg[3] = before
local NS, Frame, Load = H.NS, H.Frame, H.Load
local checks = 0
local function Check(value, why) checks = checks + 1 assert(value, why) end
local function Noop() end
local jobs = {}
NS.Registry.QueueJob = function(callback) jobs[callback] = true end
local function Flush()
    for _ = 1, 5 do
        if not next(jobs) then return end
        local pending = jobs
        jobs = {}
        for callback in pairs(pending) do callback() end
    end
    assert(not next(jobs), "unbounded menu rediscovery")
end
hooksecurefunc = function(target, key, callback)
    if type(target) == "string" then callback, key, target = key, target, _G end
    local original = assert(target[key], "missing native hook " .. key)
    target[key] = function(...)
        local result = { original(...) }
        callback(...)
        return unpack(result)
    end
end
PanelTemplates_SelectTab, PanelTemplates_DeselectTab = Noop, Noop
local nativeTracks, nativeReleases = {}, {}
NS.ScrollMotion = { Track = function(target, owner) nativeTracks[target] = owner end,
    ReleaseOwner = function(owner) nativeReleases[owner] = true end }
NS.GenericWindows.SetMenuMotionProvider = function(track, release)
    NS.GenericWindows.menuTrack, NS.GenericWindows.menuRelease = track, release
end
NS.AdapterKit = { SetMotionProvider = function(track, watch)
    NS.AdapterKit.track, NS.AdapterKit.watch = track, watch
end }
Load("Rendering/LegacyScrollMotion.lua")
NS.GenericWindows.SetCollapseMotionProvider = Noop
NS.SocialUISkin = { SetMotionProvider = Noop }
Load("Rendering/CollapseCollectionRows.lua")
Load("Rendering/CollapseCollections.lua")
Load("Rendering/MenuMotion.lua")
local Menus, Content, Legacy = NS.MenuMotion, NS.ContentMotion, NS.LegacyScrollMotion

local window, body, list = Frame(UIParent, true), Frame(nil, true), Frame(nil, true)
body.parent, list.parent = window, body
window.Content, window.children, body.children = body, { body }, { list }
list.provider = {}
list.GetDataProvider = function(self) return self.provider end
local row = Frame(list, true)
list.children = { row }
local pooledBody = Frame(row, true)
pooledBody.GetDataProvider = function() return {} end
row.children = { pooledBody }
local owner1, owner2 = {}, {}
Check(Menus.Track(window, owner1), "safe explicit menu refused")
Check(nativeTracks[list] and NS.ResultMotion.states[list], "nested modern list missed shared providers")
Check(not Menus.observers[row] and not nativeTracks[pooledBody], "pooled row was scanned for full-menu rediscovery")
Check(not Menus.Track({}, owner1), "plain table was treated as native menu")
local unsafe = Frame(nil, true)
unsafe.protected = true
Check(not Menus.Track(unsafe, owner1), "protected menu adopted")
unsafe.protected = false
unsafe.AttachTexture, unsafe.AttachFrame, unsafe.AttachFontString, unsafe.AttachTemplate = Noop, Noop, Noop, Noop
Check(not Menus.Track(unsafe, owner1), "compositor menu adopted")
Menus.Track(window, owner2)
Menus.Release(owner2, window)
Flush()
Check(Menus.OwnerFor(body) == owner1, "menu retained released latest owner")
Menus.SelectionChanged(Frame(window))
local bodyFade = Content.records[body]
Check(bodyFade and bodyFade.owner == owner1, "selection re-created a released owner")

-- Parent/child fades are exclusive for both native show notification orders.
Content.StopOwner(owner1)
local a, b = Frame(nil, true), Frame(nil, true)
b.parent = a
Content.Play(b, owner1, 1)
local childFade = Content.records[b]
Content.Play(a, owner1, 2)
Check(not childFade.group:IsPlaying(), "new ancestor left nested child fade active")
Content.Play(b, owner1, 3)
Check(not childFade.group:IsPlaying(), "child faded under active ancestor")
Content.records[a].group:Finish()
Content.Play(b, owner1, 4)
Check(childFade.group:IsPlaying(), "completed ancestor blocked child forever")
Check(not Content.Play(a, owner2, 5) and childFade.group:IsPlaying(),
    "refused foreign owner stopped another owner's descendant")
Content.StopOwner(owner1)

-- Legacy wheel/render retarget keeps native offset and thumb drag direct.
local scroll, scrollChild, bar = Frame(nil, true), Frame(nil, true), Frame(nil, true)
scroll.kind, scroll.scrollChild, scrollChild.parent = "ScrollFrame", scrollChild, scroll
scroll.scrollOffset = 0
Legacy.Track(scroll, owner1, bar)
scroll.scrollOffset = 42
scroll:Fire("OnVerticalScroll", 42)
local travel = Legacy.states[scroll].current
Check(travel and travel.move.y == -42 and travel.group.reverse and travel.move.Duration == 0.11,
    "legacy wheel did not receive finite render smoothing")
travel.group.progress = 0.5
scroll.scrollOffset = 84
scroll:Fire("OnVerticalScroll", 84)
Check(travel.move.y == -63, "legacy rapid wheel lost current visual offset")
bar:Fire("OnMouseDown", "LeftButton")
Check(not travel.group:IsPlaying(), "legacy thumb drag retained smoothing")
scroll.scrollOffset = 100
scroll:Fire("OnVerticalScroll", 100)
Check(not travel.group:IsPlaying() and scroll.scrollOffset == 100, "legacy drag changed native scroll ownership")
bar:Fire("OnMouseUp", "LeftButton")
scroll.scrollOffset = 120
scroll:Fire("OnVerticalScroll", 120)
Check(travel.group:IsPlaying(), "legacy wheel did not resume after drag")
local groups = #H.groups
scroll.scrollOffset = 140
scroll:Fire("OnVerticalScroll", 140)
Check(#H.groups == groups, "warm legacy wheel created more animation groups")
NS.DB.theme.smoothScrolling = false
scroll.scrollOffset = 160
scroll:Fire("OnVerticalScroll", 160)
Check(not travel.group:IsPlaying(), "smooth-scroll off retained legacy transform")
NS.DB.theme.smoothScrolling = nil
Legacy.ReleaseOwner(owner1)
scroll:Fire("OnVerticalScroll", 180)
Check(not travel.group:IsPlaying(), "released legacy owner resumed animation")

-- ScrollFrameTemplate already owns a modern controller; never smooth it twice.
local modernFrame, modernChild, modernBar = Frame(), Frame(), Frame()
modernFrame.kind, modernFrame.scrollChild, modernFrame.scrollOffset = "ScrollFrame", modernChild, 0
modernFrame.ScrollBar, modernChild.parent = modernBar, modernFrame
modernBar.CanInterpolateScroll = function() return true end
Legacy.Track(modernFrame, owner1)
modernFrame:Fire("OnVerticalScroll", 42)
Check(nativeTracks[modernBar] == owner1 and not Legacy.states[modernFrame],
    "native modern ScrollFrame controller was smoothed twice")

-- Actual programmatic modern and legacy tab events, preserving callbacks.
NS.ControlSkin = { states = {}, SetTabMotionProvider = function(track) NS.ControlSkin.track = track end,
    Refresh = function(tab, selected) NS.Surface.SetActive(tab, selected) return true end }
local selected = {}
NS.Surface = { SetActive = function(tab, value) selected[tab] = value end }
Load("Rendering/TabMotion.lua")
local tab = Frame(window, true)
function tab:SetTabSelected(value) self.nativeSelected = value end
NS.ControlSkin.states[tab] = { enabled = true, kind = "minimalTab" }
NS.ControlSkin.track(tab)
tab:SetTabSelected(true)
Check(tab.nativeSelected and selected[tab] == true, "native SetTabSelected missed skin selection")
PanelTemplates_DeselectTab(tab)
Check(selected[tab] == false, "legacy programmatic deselection missed skin")
PanelTemplates_SelectTab(tab)
Check(selected[tab] == true, "legacy programmatic selection missed skin")

-- Finished Settings event picks the visible list/canvas, including addon pages.
local changed, releaseSettings
NS.Checkmarks.SetSettingsMotionProvider = function(changedCallback, releaseCallback)
    changed, releaseSettings = changedCallback, releaseCallback
end
Load("Rendering/MenuMotion.lua")
Menus = NS.MenuMotion
local settings, vertical, canvas = Frame(), Frame(), Frame()
settings.GetSettingsList, settings.GetSettingsCanvas = function() return vertical end, function() return canvas end
vertical.shown, canvas.shown = true, false
local settingsState, category = { settingsPanel = settings }, {}
changed(settingsState, category)
Check(Content.records[vertical] and Content.records[vertical].group:IsPlaying(), "vertical Settings page did not fade")
vertical:Hide()
canvas.shown = true
changed(settingsState, {})
Check(Content.records[canvas] and Content.records[canvas].group:IsPlaying(), "addon Settings canvas did not fade")
releaseSettings(settingsState)
Check(not Content.records[canvas].group:IsPlaying(), "Settings release retained content animation")

-- Real Ace registration, pool reuse and late-loaded config windows.
NS.DB.skins = {}
local gui = { RegisterAsWidget = Noop, RegisterAsContainer = Noop, Release = Noop }
local dialog = { OpenFrames = {} }
function dialog:Open(name, container) self.OpenFrames[name] = container or self.OpenFrames[name] end
LibStub = { GetLibrary = function(_, name) return name == "AceGUI-3.0" and gui or dialog end }
local paints, restores = {}, {}
NS.GenericWindows.ApplyFrame = function(frame, owner)
    paints[frame] = (paints[frame] or 0) + 1
    Menus.Track(frame, owner)
    return true
end
NS.GenericWindows.Disable = function(owner) restores[owner] = true Menus.Release(owner) end
local function Widget(kind)
    local widget = { type = kind, frame = Frame(), content = Frame(), OnAcquire = Noop, AddChild = Noop }
    widget.frame.Content, widget.frame.children = widget.content, { widget.content }
    widget.content.parent = widget.frame
    return widget
end
local existing = Widget("Frame")
dialog.OpenFrames.Existing = existing
Load("Adapters/AddonMenus.lua")
Flush()
Check(paints[existing.frame] == 1, "already open AceConfig menu was missed")
local config = Widget("Frame")
gui:RegisterAsContainer(config)
config:OnAcquire()
Flush()
Check(paints[config.frame] == 1, "AceGUI root acquire was not coalesced")
local edit = Widget("EditBox")
gui:RegisterAsWidget(edit)
edit:OnAcquire()
Flush()
Check(not paints[edit.frame], "ordinary Ace widget was styled as an independent window")
local tabs = Widget("TabGroup")
function tabs:SelectTab(value) self.nativeToken = value self.content.painted = value end
tabs.parent, tabs.frame.parent = config, config.content
gui:RegisterAsContainer(tabs)
config:AddChild(tabs)
Flush()
config.content.children = { tabs.frame }
Menus.Track(config.frame, NS.AddonMenus.widgets[config].owner)
tabs:SelectTab("two")
Check(tabs.nativeToken == "two" and tabs.content.painted == "two", "Ace native tab callback was replaced")
gui:Release(config)
local configOwner = NS.AddonMenus.widgets[config].owner
Check(restores[configOwner], "Ace pool release retained owner")
config:OnAcquire()
Flush()
Check(paints[config.frame] >= 2, "pooled Ace config could not reacquire")
-- Pooled subcontainers must release their prior content owner even while both roots stay open.
local firstRoot, secondRoot, pooledTabs = Widget("Frame"), Widget("Frame"), Widget("TabGroup")
firstRoot.frame.Content, secondRoot.frame.Content, pooledTabs.frame.Content = nil, nil, nil
function pooledTabs:SelectTab(value) self.nativeToken = value end
gui:RegisterAsContainer(firstRoot)
gui:RegisterAsContainer(secondRoot)
gui:RegisterAsContainer(pooledTabs)
pooledTabs.parent, pooledTabs.frame.parent = firstRoot, firstRoot.content
firstRoot.content.children = { pooledTabs.frame }
firstRoot:AddChild(pooledTabs)
Flush()
pooledTabs:SelectTab("before")
local pooledFade = assert(Content.records[pooledTabs.content])
pooledFade.group:Finish()
pooledTabs.frame:Hide()
pooledTabs.content:Hide()
pooledTabs.frame.parent = UIParent
gui:Release(pooledTabs)
firstRoot.content.children = {}
pooledTabs.parent, pooledTabs.frame.parent = secondRoot, secondRoot.content
secondRoot.content.children = { pooledTabs.frame }
pooledTabs.frame:Show()
pooledTabs.content:Show()
pooledTabs:OnAcquire()
secondRoot:AddChild(pooledTabs)
Flush()
local pooledPlays = pooledFade.group.plays
pooledTabs:SelectTab("after")
Check(pooledFade.group.plays == pooledPlays + 1, "pooled Ace TabGroup cannot fade under a different config root")

-- Ace upgrades libraries in place: only replaced functions receive fresh hooks.
local addonEvents
for _, frame in ipairs(H.frames) do
    if frame.events.ADDON_LOADED then addonEvents = frame end
end
local installed = gui.RegisterAsContainer
addonEvents:Fire("OnEvent", "ADDON_LOADED", "Unrelated")
Check(gui.RegisterAsContainer == installed, "unchanged Ace method was hooked twice")
gui.RegisterAsContainer, gui.RegisterAsWidget, gui.Release = Noop, Noop, Noop
dialog.Open = function(self, name, widget) self.OpenFrames[name] = widget end
addonEvents:Fire("OnEvent", "ADDON_LOADED", "NewerAce")
local upgraded = Widget("Frame")
gui:RegisterAsContainer(upgraded)
local custom = Widget("CustomConfig")
dialog:Open("Upgraded", custom)
Flush()
Check(paints[upgraded.frame] == 1 and paints[custom.frame] == 1, "in-place Ace upgrade lost menu observers")

NS.DB.enabled = false
for owner, callback in pairs(H.listeners) do callback(owner, "adapter", "master") end
Flush()
Check(restores[configOwner] and not Menus.OwnerFor(upgraded.content), "master disable retained external menu skins")
NS.DB.enabled = true
Check(H.ForeignWrites() == 0, "coverage providers wrote native alpha or anchors")
for _, frame in ipairs(H.frames) do Check(not frame.scripts.OnUpdate, "coverage introduced idle frame polling") end
print("Suite menu coverage (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")
