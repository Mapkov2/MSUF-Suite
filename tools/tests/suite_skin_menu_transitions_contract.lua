-- Real motion providers against native callback, pool and animation lifecycles.
local root = assert(arg[1])
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Noop() end
wipe = function(t) for key in pairs(t) do t[key] = nil end end
securecallfunction = function(callback, ...) return callback(...) end
local secret = {}
issecretvalue = function(value) return value == secret end
local lockdown, combat = false, false
InCombatLockdown = function() return lockdown end
local frames, groups, surfaces = {}, {}, {}
local foreignWrites, groupStops = 0, 0
local function AnimationGroup(target)
    local group = { target = target, animations = {}, scripts = {}, progress = 1 }
    groups[#groups + 1] = group
    function group:CreateAnimation(kind)
        local animation = { kind = kind, group = self }
        self.animations[#self.animations + 1] = animation
        for _, key in ipairs({ "Duration", "Smoothing", "FromAlpha", "ToAlpha", "Degrees" }) do
            animation["Set" .. key] = function(self, value) self[key] = value end
        end
        function animation:SetOffset(x, y) self.x, self.y = x, y end
        function animation:GetSmoothProgress() return self.group.progress end
        return animation
    end
    function group:SetScript(event, callback) self.scripts[event] = callback end
    function group:SetToFinalAlpha(value) self.finalAlpha = value end
    function group:Play(reverse)
        self.playing, self.reverse = true, reverse
        self.progress = reverse and 1 or 0
        self.plays = (self.plays or 0) + 1
    end
    function group:IsPlaying() return self.playing == true end
    function group:Stop() self.playing = false groupStops = groupStops + 1 end
    function group:Finish()
        self.playing = false
        if self.finalAlpha then self.target.alpha = self.animations[1].ToAlpha end
        if self.scripts.OnFinished then self.scripts.OnFinished(self) end
    end
    return group
end
local function Frame(parent, native)
    local frame = { parent = parent, native = native, hooks = {}, scripts = {}, events = {}, callbacks = {},
        shown = true, alpha = 1, top = 400, width = 500, height = 400, scale = 1, points = {} }
    frames[#frames + 1] = frame
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsProtected() return self.protected == true, self.protected == true end
    function frame:GetParent() return self.parent end
    function frame:GetObjectType() return self.kind or "Frame" end
    function frame:GetChildren() return unpack(self.children or {}) end
    function frame:HasScript() return true end
    function frame:GetScrollChild() return self.scrollChild end
    function frame:GetVerticalScroll() return self.scrollOffset or 0 end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetTop() return self.top end
    function frame:GetLeft() return self.left or 0 end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetAllPoints(parent) self.allPoints = parent end
    function frame:SetClipsChildren(value) self.clips = value end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetID() return self.id end
    function frame:GetEffectiveScale() return self.scale end
    function frame:GetAlpha() return self.alpha end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:IsShown() return self.shown end
    function frame:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:Fire(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    end
    function frame:Hide() self.shown = false self:Fire("OnHide") end
    function frame:Show() self.shown = true end
    function frame:EnableMouse(value) self.mouse = value end
    function frame:SetAlpha(value)
        if self.native then foreignWrites = foreignWrites + 1 end
        self.alpha = value
    end
    function frame:ClearAllPoints()
        if self.native then foreignWrites = foreignWrites + 1 end
        wipe(self.points)
    end
    function frame:SetPoint(...)
        if self.native then foreignWrites = foreignWrites + 1 end
        self.points[#self.points + 1] = { ... }
    end
    function frame:SetFrameStrata(value) self.strata = value end
    function frame:GetFrameStrata() return self.strata end
    function frame:SetFrameLevel(value) self.level = value end
    function frame:GetFrameLevel() return self.level end
    function frame:CreateAnimationGroup() return AnimationGroup(self) end
    function frame:CreateFontString()
        local label = Frame(self)
        label.font, label.text, label.color = { "font.ttf", 12, "" }, "", { 1, 1, 1, 1 }
        function label:SetFont(...) self.font = { ... } end
        function label:GetFont() return unpack(self.font) end
        function label:SetText(value) self.text = value end
        function label:GetText() return self.text end
        function label:SetTextColor(...) self.color = { ... } end
        function label:GetTextColor() return unpack(self.color) end
        label.SetJustifyH, label.SetJustifyV = Noop, Noop
        return label
    end
    function frame:CreateTexture()
        local texture = Frame(self)
        texture.SetAllPoints, texture.SetColorTexture = Noop, Noop
        function texture:SetTexture(value) self.texture = value end
        function texture:GetTexture() return self.texture end
        function texture:SetAtlas(value) self.atlas = value end
        function texture:GetAtlas() return self.atlas end
        function texture:SetVertexColor(...) self.color = { ... } end
        function texture:GetVertexColor() return unpack(self.color or { 1, 1, 1, 1 }) end
        function texture:SetDesaturated(value) self.desaturated = value end
        function texture:IsDesaturated() return self.desaturated end
        return texture
    end
    function frame:RegisterCallback(event, callback, owner)
        assert(event, "native callback event missing")
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = callback
    end
    function frame:UnregisterCallback(event, owner)
        if self.callbacks[event] then self.callbacks[event][owner] = nil end
    end
    function frame:TriggerEvent(event, ...)
        for owner, callback in pairs(self.callbacks[event] or {}) do callback(owner, ...) end
    end
    return frame
end
UIParent = Frame()
CreateFrame = function() return Frame() end
local listeners = {}
local NS = { DB = { enabled = true, theme = {} }, Client = { isForever = arg[2] == "Forever" },
    IsCombatLocked = function() return combat or lockdown end,
    Registry = { GetSurface = function(frame) return surfaces[frame] end,
        AddListener = function(owner, callback) listeners[owner] = callback end } }
local function Load(file)
    local path = root .. "/MSUF_Suite_Skin/" .. file
    local override = os.getenv("SUITE_TRANSITION_OVERRIDE_ROOT")
    if override then
        local candidate = override .. "/" .. file
        local handle = io.open(candidate, "rb")
        if handle then handle:close() path = candidate end
    end
    assert(loadfile(path))("MSUF_Suite_Skin", NS)
end
Load("Core/Safety.lua")
Load("Rendering/Motion.lua")
-- Load the real dropdown observer, preserving its callback registration route.
NS.Checkmarks = { dropdowns = {}, owners = {}, settingsCategoryLists = {}, TrackFrame = Noop }
NS.CheckmarksShared = { Field = NS.Safety.Field, Getter = NS.Safety.Read,
    CanTrack = function() return true end, WalkControlTree = Noop,
    OwnerSet = function(owner)
        local set = NS.Checkmarks.owners[owner] or {}
        NS.Checkmarks.owners[owner] = set
        return set
    end }
NS.BlizzardYellow = { TrackDropdown = Noop }
NS.GenericWindows = { ApplyFrame = function() return true end, Disable = function() return true end }
DropdownButtonMixin = { Event = { OnMenuOpen = "open", OnMenuClose = "close" } }
ScrollBoxListMixin = { Event = { OnLayout = "layout", OnReleasedFrame = "released", OnScroll = "scroll", OnInitializedFrame = "initialized" } }
Load("Core/CheckmarksMenus.lua")
Load("Rendering/FocusVeil.lua")
Load("Rendering/CollapseRows.lua")
Load("Adapters/AddonListMotion.lua")
Load("Adapters/AddonListGhosts.lua")
NS.PublicAPI = {}
Load("Rendering/ContentMotion.lua")
NS.GenericWindows.SetContentMotionProvider = function(track, release)
    NS.GenericWindows.trackContent, NS.GenericWindows.releaseContent = track, release
end
Load("Rendering/ResultMotion.lua")
local Veil, Addon = NS.FocusVeil, NS.AddonListMotion
local panel, dropdown = Frame(UIParent, true), Frame(nil, true)
dropdown.parent = panel
surfaces[panel] = { spec = { role = "shell" }, visible = true }
dropdown.IsMenuOpen, dropdown.GetMenuDescription = Noop, Noop
local menu = Frame(UIParent, true)
menu.strata, menu.level = "FULLSCREEN_DIALOG", 520
-- Modern compositor proxies cannot own extra artwork or frames.
menu.AttachTexture, menu.AttachFontString, menu.AttachFrame, menu.AttachTemplate = Noop, Noop, Noop, Noop
dropdown.menu = menu
Check(NS.Checkmarks.TrackDropdown(dropdown, "addonList"), "native dropdown not tracked")
dropdown:TriggerEvent("open", dropdown)
Check(Veil.root == panel and Veil.overlay.shown, "compositor menu did not dim its registered window")
Check(Veil.overlay.parent == UIParent and Veil.overlay.level == menu.level - 1
    and Veil.overlay.strata == menu.strata and Veil.overlay.mouse == false,
    "veil must sit below the popup without intercepting native input")
Check(Veil.overlay.points[1][2] == panel and Veil.overlay.points[2][2] == panel,
    "veil escaped its window bounds")
Veil.group:Finish()
Check(Veil.overlay.alpha == 1, "veil did not finish opening")
dropdown:TriggerEvent("close", dropdown, menu)
Check(Veil.hiding and Veil.group:IsPlaying(), "native close did not start fade-out")
NS.Checkmarks.UntrackDropdown(dropdown)
Check(not Veil.overlay.shown and not Veil.group:IsPlaying(), "untracking during fade retained the veil")
Check(not next(dropdown.callbacks.open) and not next(dropdown.callbacks.close), "dropdown callbacks leaked")
NS.Checkmarks.TrackDropdown(dropdown, "addonList")
dropdown:TriggerEvent("open", dropdown)
local oldLease = Veil.lease
local otherLease = {}
Veil.Open(otherLease, dropdown, menu)
Veil.group.progress = 0.5
Veil.Close(otherLease, menu)
Check(Veil.alpha.FromAlpha == 0.5, "retargeted fade jumped back to native alpha")
Veil.Open(otherLease, dropdown, menu)
Veil.Close(oldLease, menu)
Check(Veil.lease == otherLease and not Veil.hiding, "old pooled popup closed the new dropdown's veil")
Veil.Release(oldLease)
Check(Veil.lease == otherLease, "untracking another dropdown cleared the current veil")
panel:Hide()
Check(not Veil.overlay.shown, "root hide retained the veil")
panel:Show()
NS.DB.theme.reduceMotion = true
Veil.Open(otherLease, dropdown, menu)
Check(Veil.overlay.alpha == 1 and not Veil.group:IsPlaying(), "reduced motion must still dim instantly")
Veil.Close(otherLease, menu)
Check(not Veil.overlay.shown, "reduced motion close retained the veil")
NS.DB.theme.reduceMotion = nil
Veil.Open(otherLease, dropdown, menu)
listeners[Veil](Veil, "color", "hover")
Check(Veil.lease == otherLease and Veil.overlay.shown, "color change dropped an open menu's focus cue")
NS.DB.theme.reduceMotion = true
listeners[Veil](Veil, "motion", "reduceMotion")
Check(Veil.lease == otherLease and Veil.overlay.alpha == 1 and not Veil.group:IsPlaying(),
    "changing reduced motion dropped dimming while the menu stayed open")
NS.DB.theme.reduceMotion = nil
NS.DB.theme.dropdownDimming = false
listeners[Veil](Veil, "motion", "dropdownDimming")
Check(not Veil.overlay.shown, "disabling dimming did not release an open menu's veil")
Veil.Open(otherLease, dropdown, menu)
Check(not Veil.overlay.shown, "disabled dropdown dimming created a veil")
NS.DB.theme.dropdownDimming = nil
local unowned = Frame(UIParent, true)
Veil.Open(otherLease, unowned, menu)
Check(not Veil.overlay.shown, "an unregistered root received a fullscreen veil")
menu.level = secret
Veil.Open(otherLease, dropdown, menu)
Check(not Veil.overlay.shown, "secret menu geometry was consumed")
menu.level = 520

-- Legacy root-list OnShow occurs before ToggleDropDownMenu sets its strata.
local deferred = {}
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
local function Flush()
    local batch = deferred
    deferred = {}
    for _, callback in ipairs(batch) do callback() end
end
EventRegistry = Frame()
NS.Checkmarks.RegisterLegacyDropdowns()
local legacy, submenu = Frame(UIParent, true), Frame(UIParent, true)
legacy.id, legacy.dropdown, legacy.strata, legacy.level = 1, dropdown, "DIALOG", 300
submenu.id, submenu.dropdown, submenu.strata, submenu.level = 2, dropdown, "TOOLTIP", 400
NS.Checkmarks:OnLegacyDropdownShown(legacy)
Check(not Veil.overlay.shown, "legacy focus ran before final native strata")
legacy.strata = "TOOLTIP"
Flush()
Check(Veil.menu == legacy and Veil.overlay.strata == "TOOLTIP", "legacy popup final layer/owner was lost")
surfaces[panel].visible = false
listeners[Veil](Veil, "adapter", "addonList")
Check(not Veil.overlay.shown, "disabled root skin retained a legacy veil")
surfaces[panel].visible = true
NS.Checkmarks:OnLegacyDropdownShown(legacy)
Flush()
NS.Checkmarks:OnLegacyDropdownShown(submenu)
submenu:Hide()
Check(Veil.menu == legacy and not Veil.hiding, "legacy submenu close cleared the root focus cue")
legacy:Hide()
Check(Veil.hiding, "legacy root close did not fade the focus cue")
Veil.group:Finish()
Check(not Veil.overlay.shown, "legacy root close retained its veil")
legacy:Show()
NS.Checkmarks:OnLegacyDropdownShown(legacy)
legacy:Hide()
Flush()
Check(not Veil.overlay.shown, "a stale deferred legacy open resurrected the veil")
legacy:Show()
NS.Checkmarks:OnLegacyDropdownShown(legacy)
-- The shared pooled list can belong to another owner before the timer runs.
legacy.dropdown = Frame(UIParent, true)
Flush()
Check(not Veil.overlay.shown, "a recycled legacy list dimmed its previous owner")
legacy.dropdown = dropdown
NS.Checkmarks:OnLegacyDropdownShown(legacy)
NS.Checkmarks.TrackDropdown(dropdown, "addonList")
dropdown:TriggerEvent("open", dropdown)
Flush()
Check(Veil.menu == menu, "a stale legacy timer superseded a newer modern dropdown")
Veil.Clear()
NS.Checkmarks:OnLegacyDropdownShown(legacy)
NS.Checkmarks.ReleaseMenus()
Flush()
Check(not Veil.overlay.shown, "legacy release left a pending dimming callback")

-- Exercise native tree layout and pooled rows through the actual adapter.
local list = Frame(UIParent, true)
list.ScrollBox = Frame(list, true)
local scroll = list.ScrollBox
scroll.provider, scroll.offset, scroll.rows = {}, 0, {}
function scroll:GetDataProvider() return self.provider end
function scroll:GetDerivedScrollOffset() return self.offset end
function scroll:ForEachFrame(callback) for _, row in ipairs(self.rows) do callback(row) end end
local function Node(category, collapsed)
    return { data = { category = category }, collapsed = collapsed,
        GetData = function(self) return self.data end, IsCollapsed = function(self) return self.collapsed end,
        GetParent = function(self) return self.parent end }
end
local function Row(node, top)
    local row = Frame(scroll, true)
    row.node, row.top, row.height = node, top, 16
    function row:GetElementData() return self.node end
    if node.data.category then row.CollapseExpand = Frame(row, true) end
    return row
end
local category, childNode, followingNode = Node("Tools", true), Node(), Node("Other", true)
local header, child, following = Row(category, 400), Row(childNode, 376), Row(followingNode, 376)
childNode.parent = category
child.Title = child:CreateFontString()
child.Title:SetText("|Ticon:16|t Example")
child.Title.top = 376
child.Enabled = Frame(child)
child.Enabled.checked, child.Enabled.enabled = true, true
child.Enabled.GetChecked = function(self) return self.checked end
child.Enabled.IsEnabled = function(self) return self.enabled end
child.Enabled.checkedTexture = child.Enabled:CreateTexture()
child.Enabled.checkedTexture:SetTexture("checked")
child.Enabled.checkedTexture:SetDesaturated(true)
child.Enabled.GetCheckedTexture = function(self) return self.checkedTexture end
scroll.rows = { header, following }
Load("Adapters/Blizzard.lua")
local adapter = NS.Adapters.definitions.addonList
Check(adapter.apply(list, "addonList"), "AddonList adapter did not attach")
local state = Addon.states[list]
Check(state and state.registered, "AddonList callback observer missing")
local before = #groups
category.collapsed, following.top, scroll.rows = nil, 352, { header, child, following }
scroll:TriggerEvent("layout")
local childRecord, followingRecord = state.records[child], state.records[following]
Check(childRecord.group.reverse and childRecord.translation.y == 24 and childRecord.alpha.ToAlpha == 0,
    "expanded child did not reveal from its header")
Check(followingRecord.group.reverse and followingRecord.translation.y == 24,
    "following row did not move down from its previous position")
Check(state.records[header].rotation.Degrees == 90, "expand disclosure did not animate")
Check(child.alpha == 1 and following.alpha == 1, "row alpha ownership changed")
local warmGroups = #groups
childRecord.group.progress = 0.5
followingRecord.group.progress = 0.5
state.records[header].arrowGroup.progress = 0.5
category.collapsed, following.top, scroll.rows = true, 376, { header, following }
scroll:TriggerEvent("released", child, childNode)
scroll:TriggerEvent("layout")
Check(not childRecord.group:IsPlaying() and childRecord.node == nil, "released row animation leaked into the pool")
local ghost = childRecord.ghost
Check(ghost.group:IsPlaying() and ghost.frame.shown and state.ghostViewport.shown,
    "native nil-open category did not collapse its released child")
Check(ghost.fonts[1].text == "|Ticon:16|t Example" and ghost.textures[2].desaturated,
    "ghost lost inline icon text or partial checkbox state")
Check(ghost.alpha.FromAlpha == 0.5 and ghost.frame.points[1][5] == 4,
    "rapid collapse lost the partially revealed row position or alpha")
Check(state.ghostViewport.clips and state.ghostClip.clips and not ghost.frame.mouse,
    "ghost escaped the viewport or intercepted native input")
Check(followingRecord.translation.y == -12, "rapid collapse lost the current rendered position")
Check(state.records[header].rotation.Degrees == -45, "rapid disclosure retarget jumped to the old endpoint")
Check(#groups == warmGroups and warmGroups > before, "warm toggles allocated new animation groups")
scroll:TriggerEvent("layout")
Check(followingRecord.group:IsPlaying(), "unchanged duplicate layout cancelled an active transition")
scroll.offset = 20
scroll:TriggerEvent("scroll")
Check(not ghost.group:IsPlaying() and not state.ghostViewport.shown, "scroll retained a collapse ghost")
scroll:TriggerEvent("layout")
Check(not followingRecord.group:IsPlaying(), "scrolling must snap ongoing row motion")
scroll.provider = {}
category.collapsed, following.top, scroll.rows = false, 352, { header, child, following }
scroll:TriggerEvent("layout")
Check(not childRecord.group:IsPlaying() and not followingRecord.group:IsPlaying(), "search/provider rebuild animated as expansion")
following.alpha = 0.37
category.collapsed, following.top, scroll.rows = true, 376, { header, following }
scroll:TriggerEvent("layout")
Check(followingRecord.alpha.FromAlpha == 0.37 and followingRecord.alpha.ToAlpha == 0.37,
    "native non-default alpha was not preserved")
scroll.scale = 0.85
scroll:TriggerEvent("layout")
Check(not followingRecord.group:IsPlaying(), "scale change retained old coordinate motion")
scroll.height = 300
category.collapsed = false
scroll:TriggerEvent("layout")
Check(not followingRecord.group:IsPlaying(), "resize was treated as a toggle")
scroll.rows = { header }
category.collapsed = true
scroll:TriggerEvent("layout")
Check(state.records[header].arrowGroup:IsPlaying(), "last category collapse has no disclosure transition")
NS.DB.theme.menuAnimations = false
scroll:TriggerEvent("layout")
Check(not state.records[header].arrowGroup:IsPlaying(), "disabled menu motion retained disclosure animation")
NS.DB.theme.menuAnimations = nil
scroll:TriggerEvent("layout")
category.collapsed = false
scroll.rows = { header, child }
scroll:TriggerEvent("layout")
Check(childRecord.group:IsPlaying(), "protected-path fixture did not start a row transition")
child.protected = true
scroll:TriggerEvent("layout")
Check(not childRecord.group:IsPlaying(), "protected row was animated")
child.protected = false
category.collapsed = true
scroll.rows = { header }
scroll:TriggerEvent("released", child, childNode)
scroll.offset = 0 -- Native collapse can clamp the range before final layout.
scroll:TriggerEvent("layout")
Check(ghost.group:IsPlaying(), "native bottom-range clamp cancelled collapse")
ghost.group:Finish()
Check(not ghost.frame.shown and not state.ghostViewport.shown, "finished ghost retained its visual layer")
local idleStops = groupStops
for _ = 1, 10 do scroll:TriggerEvent("scroll") end
Check(groupStops == idleStops, "idle scrolling traversed and stopped cached ghosts")
category.collapsed = false
scroll.rows = { header, child }
scroll:TriggerEvent("layout")
Check(childRecord.group:IsPlaying(), "reuse fixture did not start a row transition")
child.node = Node()
scroll:TriggerEvent("layout")
Check(not childRecord.group:IsPlaying(), "pooled row reuse retained old motion")
category.collapsed = true
scroll.rows = { header }
scroll:TriggerEvent("layout")
category.collapsed = false
scroll.rows = { header, child }
scroll:TriggerEvent("layout")
Check(childRecord.group:IsPlaying(), "secret-path fixture did not start a row transition")
child.top = secret
scroll:TriggerEvent("layout")
Check(not childRecord.group:IsPlaying(), "secret geometry was animated")
child.top = 376
Veil.Open(otherLease, dropdown, menu)
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
end
Check(not Veil.overlay.shown and not state.records[header].arrowGroup:IsPlaying() and NS.Motion.combat,
    "combat event edge did not clean up before lockdown")
Veil.Open(otherLease, dropdown, menu)
Check(not Veil.overlay.shown, "a menu reopened its veil on the combat event edge")
NS.Motion.combat = false
scroll:TriggerEvent("layout")
category.collapsed = true
scroll:TriggerEvent("layout")
for owner, callback in pairs(listeners) do callback(owner, "profile") end
Check(not state.records[header].arrowGroup:IsPlaying(), "profile switch retained row motion")
category.collapsed = false
scroll:TriggerEvent("layout")
Check(state.records[header].arrowGroup:IsPlaying(), "first toggle after settings refresh lost its snapshot")
adapter.disable(list, "addonList")
Check(not state.active and not state.registered and not next(scroll.callbacks.layout), "adapter disable retained callbacks")
Check(foreignWrites == 0, "providers mutated native geometry or alpha")
for _, frame in ipairs(frames) do Check(not frame.scripts.OnUpdate, "transition provider installed a persistent frame clock") end
-- Complete an old ghost after the native pool has reused its frame.
Addon.Attach(list, "addonList")
category.collapsed, scroll.rows = false, { header, child }
child.node = childNode
scroll:TriggerEvent("layout")
category.collapsed, scroll.rows = true, { header }
scroll:TriggerEvent("released", child, childNode)
scroll:TriggerEvent("layout")
local replacement = Node()
replacement.parent = followingNode
followingNode.collapsed = false
child.node, scroll.rows = replacement, { header, following, child }
scroll:TriggerEvent("layout")
Check(ghost.group:IsPlaying() and ghost.node == childNode, "pool reuse repainted a playing ghost")
ghost.group:Finish()
Check(ghost.node == replacement, "finished ghost retained stale pooled row snapshot")
followingNode.collapsed = true
scroll:TriggerEvent("released", child, replacement)
Check(ghost.group:IsPlaying(), "reused row lost the next collapse animation")
Addon.DisableOwner("addonList")

-- Blizzard_CatalogShop can expose ScrollBox methods before SetView ran.
local cold = Frame(nil, true)
function cold:GetView() return self.view end
function cold:GetDataProvider() return self:GetView():GetDataProvider() end
NS.GenericWindows.trackContent(cold, "cold-native-view")
Check(NS.ResultMotion.states[cold].registered, "uninitialized list lost its layout observer")
cold.view = { provider = {}, GetDataProvider = function(self) return self.provider end }
cold:TriggerEvent("layout")
Check(NS.ResultMotion.states[cold].provider == cold.view.provider, "late native view was not adopted")
cold.view = nil
cold:TriggerEvent("layout")
NS.GenericWindows.releaseContent("cold-native-view")

-- OnLayout precedes the first native draw. Never show results, wait, then blank them.
local timers = {}
C_Timer.NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
local resultRequests, playContent = 0, NS.ContentMotion.Play
NS.ContentMotion.Play = function(...)
    resultRequests = resultRequests + 1
    return playContent(...)
end
NS.GenericWindows.trackContent(scroll, "results")
scroll.provider = {}
scroll:TriggerEvent("layout")
local resultRecord = NS.ContentMotion.records[scroll]
Check(resultRecord and resultRecord.group:IsPlaying() and #timers == 0,
    "native results were shown before a delayed fade blanked them")
Check(resultRecord.alpha.Duration == 0.12, "native result duration changed")
local resultPlays = resultRecord.group.plays
scroll:TriggerEvent("layout")
Check(resultRecord.group.plays == resultPlays and resultRequests == 1,
    "row recycling restarted or requested result fade")
resultRecord.group.progress = 0.5
scroll.provider = {}
scroll:TriggerEvent("layout")
Check(resultRecord.group.plays == resultPlays + 1 and resultRecord.alpha.FromAlpha == 0.5,
    "rapid native provider replacement restarted at transparent")
list:Hide()
scroll:Fire("OnHide")
Check(not resultRecord.group:IsPlaying() and #timers == 0, "hidden result view retained a fade or delayed callback")
list:Show()
NS.GenericWindows.releaseContent("results")
Check(not next(NS.ResultMotion.states[scroll].owners) and not NS.ResultMotion.states[scroll].registered,
    "result owner release retained native callbacks")
NS.ContentMotion.Play = playContent
print("Suite skin menu transitions (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")
if arg[3] == "coverage" then
    return { NS = NS, Frame = Frame, groups = groups, frames = frames, listeners = listeners,
        Load = Load, ForeignWrites = function() return foreignWrites end }
end
