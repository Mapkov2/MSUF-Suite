local root = assert(arg[1], "Suite root required") .. "/MSUF_Suite_Skin/"
local function Noop() end
local function True() return true end
local locked, categoryEnabled = false, true
InCombatLockdown = function() return locked end
securecallfunction = function(callback, ...) return callback(...) end
hooksecurefunc = function(object, method, callback)
    local previous = object[method]
    object[method] = function(...)
        previous(...)
        callback(...)
    end
end

local function Texture(atlas)
    local region = { alpha = 1, atlas = atlas }
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAtlas() return self.atlas end
    function region:GetObjectType() return "Texture" end
    function region:IsShown() return self.shown == true end
    return region
end

local function Frame()
    local frame = { shown = true, scripts = {}, events = {}, regions = {} }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    frame.HookScript = frame.SetScript
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:IsVisible() return self.shown end
    function frame:IsProtected() return self.protected == true, self.explicit == true end
    function frame:GetChecked() return self.checked end
    function frame:GetNormalTexture() return self.NormalTexture end
    function frame:GetHighlightTexture() return self.HighlightTexture end
    function frame:CreateTexture()
        assert(not self.explicit and not (locked and self.protected), "protected texture creation")
        local texture = Texture()
        texture.points = {}
        function texture:ClearAllPoints() self.points = {} end
        function texture:SetPoint(point, relative, _, x, y) self.points[point] = { relative, x, y } end
        function texture:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
        texture.SetVertexColor = Noop
        function texture:Show() self.visible = true end
        function texture:Hide() self.visible = false end
        self.regions[#self.regions + 1] = texture
        return texture
    end
    return frame
end
local loader
CreateFrame = function()
    loader = Frame()
    return loader
end

local surfaces, pending, tint, listeners, motions = {}, {}, {}, {}, {}
local paints, allocations, controls, scrollbars, tints = 0, 0, 0, 0, 0
local color = { 0.7, 0.7, 0.7, 1 }
local material = { from = "background", to = "background", border = "border" }
local NS = {
    DB = { enabled = true, skins = {}, theme = { gradient = false, materialDepth = 0, gradientStrength = 1 } },
    Client = { isForever = true, HasAddOn = True },
    IsCombatLocked = function() return locked end,
    CombatGate = {
        RunOrDefer = function(key, callback)
            assert(locked, "unexpected replay outside combat")
            pending[key] = callback
        end,
        Cancel = function(key) pending[key] = nil end,
    },
    Registry = {
        AddListener = function(owner, callback) listeners[owner] = callback end,
        RemoveListener = function(owner) listeners[owner] = nil end,
        GetSurface = function(frame) return surfaces[frame] end,
        RegisterSurface = function(frame, state)
            surfaces[frame] = state
            allocations = allocations + 1
        end,
    },
    Theme = {
        GetMaterial = function() return material end,
        GetColorTable = function() return color end,
        GetColor = function() return unpack(color) end,
        GetMaterialOpacity = function() return 1 end,
        GetBorderOpacity = function() return 1 end,
    },
    Geometry = {
        Resolve = function() return { fill = "fixture-fill", edge = "fixture-edge" } end,
        ConfigureShape = function() paints = paints + 1 end,
    },
    WindowControls = {
        TrackFocus = Noop,
        Attach = function()
            assert(not locked, "window geometry in combat")
            controls = controls + 1
        end,
    },
    BlizzardYellow = { TrackFrame = Noop },
    Checkmarks = { TrackTexture = function(texture, _, role)
        if not texture then return false end
        tint[texture] = role
        tints = tints + 1
        return true
    end },
    ContentMotion = { Watch = Noop },
    ScrollBarSkin = { Apply = function()
        scrollbars = scrollbars + 1
        return true
    end },
    GenericWindows = {
        IsCategoryEnabled = function(category) return category ~= "character" or categoryEnabled end,
        ApplyDescendant = function() error("Legacy System used a generic traversal") end,
    },
}
for _, path in ipairs({ "Core/Safety.lua", "Core/Cosmetics.lua", "Adapters/AdapterKit.lua", "Rendering/Surface.lua" }) do
    assert(loadfile(root .. path))("Suite", NS)
end
NS.AdapterKit.SetMotionProvider(function(frame, owner) motions[frame] = owner end, Noop)
NS.GenericWindows.Disable = function(owner)
    NS.Cosmetics.RestoreOwner(owner)
    for frame, motionOwner in pairs(motions) do
        if motionOwner == owner then motions[frame] = nil end
    end
    tint = {}
    return true
end
NS.ControlSkin = {
    ApplyButton = function(frame, _, spec)
        if frame.isClose then
            frame.originalNormal = frame.NormalTexture
            frame.NormalTexture = Texture("suite-close-glyph")
        end
        return NS.Surface.Attach(frame, spec)
    end,
    ApplySearchBox = function(frame, _, spec) return NS.Surface.Attach(frame, spec) end,
}

local adapterPath = arg[2] or root .. "Adapters/ForeverLegacyTree.lua"
local retail = { Client = { isForever = false } }
assert(loadfile(adapterPath))("Suite", retail)
assert(retail.ForeverLegacyTree.Apply() and not loader, "Retail touched the Forever loader")
assert(loadfile(adapterPath))("Suite", NS)
local adapter = NS.ForeverLegacyTree
categoryEnabled = false
assert(adapter.Apply() and not loader.events.ADDON_LOADED, "disabled category registered the loader")
categoryEnabled = true
locked = true
assert(adapter.Apply() and loader.events.ADDON_LOADED, "combat startup missed native load-on-demand")

local function Ringed()
    local button = Frame()
    button.NormalTexture, button.PushedTexture = Texture("tree-icon"), Texture("tree-icon")
    button.CircleMask, button.Ring = Texture("circle-mask"), Texture("ring")
    button.Background, button.SelectedGlow = Texture(), Texture()
    return button
end

local window, page, panel, selection = Frame(), Frame(), Frame(), Frame()
LegacySystemFrame = window
window.TreePage = page
window.currentPage = 1
window.Bg, window.TopTileStreaks = Texture(), Texture()
window.CloseButton = Frame()
window.CloseButton.isClose, window.CloseButton.NormalTexture = true, Texture("native-close")
window.RewardTrackPage, window.ChallengesPage = Frame(), Frame()
local rewardPage, challengePage = window.RewardTrackPage, window.ChallengesPage
rewardPage.shown, challengePage.shown = false, false
rewardPage.Background, challengePage.Background = Texture("reward-background"), Texture("challenge-background")

local function Progress(parent, key)
    local bar = Frame()
    parent[key] = bar
    parent.ProgressBarBackground = Texture("bar-back")
    bar.ProgressBarFrame, bar.fill = Texture("bar-frame"), Texture("native-fill")
    function bar:GetStatusBarTexture() return self.fill end
    return bar
end
local rewardBar = Progress(rewardPage, "LegacyRewardProgressBar")
local track = Frame()
rewardPage.LegacyRewardProgressFrame = track
function track:GetElements() return self.elements end
function rewardPage:SetupRewardTrack(cards) track.elements = cards end
track.LeftButton = Frame()
track.LeftButton.NormalTexture = Texture("native-arrow")
rewardPage.Icon = Texture("progress-shield")

local function RewardCard(level)
    local card = Frame()
    card.info = { level = level }
    card.lastEarnedBackgroundFrameAtlas = "native-current"
    card.RewardCardBG, card.Highlight = Texture("native-locked"), Texture("native-locked")
    card.Icon, card.IconBorder = Texture("reward-icon"), Texture("reward-border")
    card.LevelSquare, card.EarnedCheckmark = Texture("threshold"), Texture("earned")
    function card:Refresh(_, displayLevel)
        self.RewardCardBG.atlas = displayLevel == self.info.level and "native-current" or "native-locked"
        self.Icon.desaturated = self.info.level > displayLevel
        self.EarnedCheckmark.shown = self.info.level <= displayLevel
    end
    return card
end

ScrollBoxListMixin = { Event = { OnInitializedFrame = "initialized" } }
local function Pane()
    local pane = Frame()
    local box = Frame()
    pane.ScrollBox, pane.ScrollBar = box, Frame()
    box.rows = {}
    function box:RegisterCallback(event, callback, owner)
        assert(event == "initialized" and type(owner) == "string" and not self.initializer,
            "row callbacks and scroll motion must share the skin owner")
        self.initializer, self.owner = callback, owner
    end
    function box:UnregisterCallback(event, owner)
        assert(event == "initialized" and owner == self.owner)
        self.initializer, self.owner = nil, nil
    end
    function box:ForEachFrame(visit)
        for _, row in ipairs(self.rows) do visit(row) end
    end
    function box:InitRow(row)
        self.rows[1] = row
        if self.initializer then self.initializer(self.owner, row) end
    end
    return pane
end
challengePage.CategoryList, challengePage.DetailPane = Pane(), Pane()
challengePage.CategoryList.SearchBox, challengePage.CategoryList.FilterDropdown = Frame(), Frame()
challengePage.LegacyChallengePointSummary = Frame()
local pointsBar = Progress(challengePage.LegacyChallengePointSummary, "PointsBar")
challengePage.VerticalDivider = Frame()
local divider = Texture("Legacy-Tree-Frame-divider-Vertical")
challengePage.VerticalDivider.regions[1] = divider
local categoryRow, detailRow = Frame(), Frame()
categoryRow.NormalTexture, categoryRow.HighlightTexture = Texture("category"), Texture("category-selected")
categoryRow.NotificationIcon = Texture("new")
function categoryRow:SetSelected(selected) self.selected = selected end
detailRow.Background, detailRow.BackgroundTop = Texture("collapsed"), Texture("expanded")
detailRow.BackgroundMiddle, detailRow.BackgroundBottom = Texture("expanded"), Texture("expanded")
detailRow.TitleBar, detailRow.SelectedOverlay = Texture("title"), Texture("selected")
detailRow.Icon, detailRow.Shield, detailRow.Check = Texture("achievement"), Texture("points"), Texture("earned")
function detailRow:IsSelected() return self.selected end
local function RefreshChallengeArt(self, selected)
    self.selected = selected
    self.SelectedOverlay.shown = selected
    self.Background.atlas = selected and "expanded" or "collapsed"
end
detailRow.RefreshStateArt = RefreshChallengeArt
local categoryBox, detailBox = challengePage.CategoryList.ScrollBox, challengePage.DetailPane.ScrollBox
categoryBox.rows[1], detailBox.rows[1] = categoryRow, detailRow

local objective = Frame()
objective.Background, objective.Check = Texture("criteria-bg"), Texture("criteria-check")
local objectiveBar = Progress(objective, "ProgressBar")
LegacyChallengeObjectives = Frame()
local activeObjectives = {}
LegacyChallengeObjectives.criteriaPool = { EnumerateActive = function() return pairs(activeObjectives) end }
function LegacyChallengeObjectives:Display(row) activeObjectives[row] = true end
local tabs = { "LegacyRewardTrackTab", "LegacyChallengeTab", "LegacyTreeTab" }
for _, key in ipairs(tabs) do
    local tab = Frame()
    tab.Icon, tab.Mask, tab.Background, tab.SelectedTexture = Texture("tab"), Texture("mask"), Texture(), Texture()
    window[key] = tab
end
function window:SelectPage(index) self.currentPage = index end
page.Background, page.VerticalDivider = Texture("tree-background"), { VerticalDivider = Texture() }
page.LegacyTreePointSummary = Frame()
page.LegacyTreePointSummary.Border = Texture()
page.LegacyTreeTraitPanel, page.LegacyTreeSelectionPanel = panel, selection
panel.SearchBox, panel.SearchPreviewContainer, panel.SpentPointsFrame = Frame(), Frame(), Frame()
panel.SearchPreviewContainer.Background = Texture("search-row-bg")
panel.ApplyButton, panel.ResetButton, panel.UndoButton = Frame(), Frame(), Frame()
panel.ApplyButton.NormalTexture = Texture("apply-button")
panel.ResetButton.Icon, panel.UndoButton.Icon = Texture("reset"), Texture("undo")
panel.SelectedTreeIcon = Ringed()
panel.SpentPointsFrame.Background = Texture()
panel.ResetButton.protected, panel.UndoButton.explicit = true, true

local nodes = {}
function panel:EnumerateAllTalentButtons()
    local index = 0
    return function()
        index = index + 1
        return nodes[index]
    end
end
function panel:RegisterCallback(event, callback, owner) self[event] = { callback, owner } end
function panel:UnregisterCallback(event, owner)
    assert(self[event][2] == owner)
    self[event] = nil
end
function selection:RefreshTreeButtons()
    self.treeButtons = { Ringed(), Ringed(), Ringed() }
end
function selection:UpdateSelection(index)
    for i, button in ipairs(self.treeButtons) do button.checked = i == index end
end
selection:RefreshTreeButtons()

loader.scripts.OnEvent(loader, "ADDON_LOADED", "Blizzard_LegacySystem")
assert(not loader.events.ADDON_LOADED, "native load listener was left registered")
assert(rewardPage.Background.alpha == 0 and challengePage.Background.alpha == 0 and divider.alpha == 0,
    "legacy page backgrounds were left visible on a cold combat open")
assert(rewardPage.Icon.alpha == 1 and tint[rewardBar.fill] == "accentBright" and tint[pointsBar.fill] == "accentBright",
    "progress did not get theme colors or the shield was hidden")
assert(track.LeftButton.NormalTexture.alpha == 1 and scrollbars == 2, "native arrows or scrollbar styling lost")
assert(surfaces[challengePage.CategoryList.SearchBox] and surfaces[challengePage.CategoryList.FilterDropdown])
assert(surfaces[categoryRow] and categoryRow.NormalTexture.alpha == 0 and categoryRow.NotificationIcon.alpha == 1,
    "active category row was not styled safely")
assert(surfaces[detailRow] and detailRow.BackgroundTop.alpha == 0 and detailRow.Icon.alpha == 1
    and detailRow.Shield.alpha == 1 and detailRow.Check.alpha == 1, "expanded challenge chrome or native state incorrect")
assert(tint[detailRow.TitleBar] == "buttonFill")
detailRow.accountWide = true
detailRow:RefreshStateArt(false)
assert(tint[detailRow.TitleBar] == "accent", "recycled account-wide row lost its title distinction")
categoryRow:SetSelected(true)
detailRow:RefreshStateArt(true)
assert(surfaces[categoryRow].active and surfaces[detailRow].active)
categoryRow:SetSelected(false)
detailRow:RefreshStateArt(false)
assert(not surfaces[categoryRow].active and not surfaces[detailRow].active,
    "recycled rows kept their old selection")

local freshDetail = Frame()
freshDetail.Background, freshDetail.Icon = Texture("new-row"), Texture("achievement")
freshDetail.SelectedOverlay = Texture("selected")
freshDetail.RefreshStateArt, freshDetail.IsSelected = RefreshChallengeArt, detailRow.IsSelected
detailBox:InitRow(freshDetail)
assert(surfaces[freshDetail] and freshDetail.Background.alpha == 0 and freshDetail.Icon.alpha == 1,
    "new challenge row was not themed on initialization")
LegacyChallengeObjectives:Display(objective)
assert(surfaces[objective] and objective.Background.alpha == 0 and objective.Check.alpha == 1
    and tint[objectiveBar.fill] == "accentBright", "newly acquired objectives lost their theme or checkmark")

local card = RewardCard(15)
rewardPage:SetupRewardTrack({ card })
assert(surfaces[card] and card.RewardCardBG.alpha == 0 and card.Highlight.alpha == 0
    and card.Icon.alpha == 1 and tint[card.LevelSquare] == "rim", "late reward cards were not skinned")
card:Refresh(1, 1, false)
assert(card.Icon.desaturated and not card.EarnedCheckmark.shown and not surfaces[card].active)
card.Highlight.shown = true
card.scripts.OnEnter(card)
assert(surfaces[card].active, "hover state lost after replacing the native highlight")
card.Highlight.shown = false
card.scripts.OnLeave(card)
assert(not surfaces[card].active)
card:Refresh(15, 15, false)
assert(card.EarnedCheckmark.shown and not card.Icon.desaturated and surfaces[card].active
    and card.RewardCardBG.alpha == 0, "reward update restored old art or lost milestone state")
assert(surfaces[window] and window.Bg.alpha == 0 and page.Background.alpha == 0, "cold combat shell/tree absent")
assert(surfaces[panel.SearchBox] and surfaces[panel.SearchPreviewContainer], "combat search was left native")
assert(window.CloseButton.NormalTexture.alpha == 1 and window.CloseButton.originalNormal.alpha == 1,
    "close glyph was hidden")
assert(panel.ApplyButton.NormalTexture.alpha == 0 and panel.ResetButton.Icon.alpha == 1, "action art incorrect")
assert(not surfaces[panel.ResetButton] and not surfaces[panel.UndoButton] and controls == 0, "protection guard failed")
assert(surfaces[window.LegacyRewardTrackTab].active, "initial tab selection missing")
window:SelectPage(3)
assert(surfaces[window.LegacyTreeTab].active and not surfaces[window.LegacyRewardTrackTab].active)
for _, tabKey in ipairs(tabs) do
    local tab = window[tabKey]
    local edge = surfaces[tab].edge
    assert(edge.layer == "OVERLAY" and edge.points.TOPLEFT[1] == tab.Icon and edge.points.TOPLEFT[2] == -1
        and edge.points.BOTTOMRIGHT[1] == tab.Icon and edge.points.BOTTOMRIGHT[2] == 1,
        "selected tab outline does not fit the native icon")
    assert(tab.Icon.alpha == 1 and tab.Mask.alpha == 1, "tab icon or mask was modified")
end

local function CheckRing(button)
    assert(button.NormalTexture.alpha == 1 and button.PushedTexture.alpha == 1
        and button.CircleMask.alpha == 1, "masked category icon lost")
    assert(tint[button.Ring] == "rim", "ring has no theme role")
end
for _, button in ipairs(selection.treeButtons) do CheckRing(button) end
CheckRing(panel.SelectedTreeIcon)
assert(selection.treeButtons[1].Background.alpha == 0, "selector background still native")
selection:UpdateSelection(1)
assert(surfaces[selection.treeButtons[1]].active)
selection:RefreshTreeButtons()
selection:UpdateSelection(1)
assert(surfaces[selection.treeButtons[1]].active, "recycled same-index selection lost")
selection:UpdateSelection(3)
assert(surfaces[selection.treeButtons[3]].active and not surfaces[selection.treeButtons[1]].active)

local node = Frame()
node.regions = { Texture("talent-state-border"), Texture("Talents-Square-Box-c60"), Texture("talent-icon") }
local event = assert(panel.TalentButtonAcquired)
nodes[1] = node
event[1](event[2], node)
assert(surfaces[node] and surfaces[node].spec.fillVisible == false, "new node has no theme edge")
assert(node.regions[1].alpha == 1 and node.regions[3].alpha == 1 and tint[node.regions[2]] == "buttonFillAlt",
    "native talent states or rank art were incorrectly skinned")
local warmPaints, warmAllocations = paints, allocations
for _ = 1, 50 do
    event[1](event[2], node)
    window:SelectPage(3)
    selection:UpdateSelection(3)
    card:Refresh(15, 15, false)
end
assert(paints == warmPaints and allocations == warmAllocations, "warm path repaints or walks the tree")

categoryRow.protected, freshDetail.protected, card.protected = true, true, true
categoryRow:SetSelected(true)
freshDetail:RefreshStateArt(true)
card:Refresh(1, 1, false)
assert(not surfaces[categoryRow].active and not surfaces[freshDetail].active and surfaces[card].active,
    "protected selection changed before unlock")
locked = false
local key, replay = next(pending)
assert(key and replay, "no deferred window controls")
pending[key] = nil
replay()
assert(controls == 1 and surfaces[panel.ResetButton] and not surfaces[panel.UndoButton], "protection replay incorrect")
assert(surfaces[categoryRow].active and surfaces[freshDetail].active and not surfaces[card].active,
    "combat replay missed existing reward or challenge selection")
local beforeTint = tints
for owner, listener in pairs(listeners) do listener(owner, "color", "accentBright") end
assert(tints == beforeTint + 3, "individual palette changes did not repaint the three progress fills")
assert(adapter.Disable() and not panel.TalentButtonAcquired and not next(pending))
assert(window.Bg.alpha == 1 and page.Background.alpha == 1 and not surfaces[window].visible,
    "disable did not restore native art")
assert(rewardPage.Background.alpha == 1 and challengePage.Background.alpha == 1 and card.RewardCardBG.alpha == 1
    and detailRow.BackgroundTop.alpha == 1 and not categoryBox.initializer and not detailBox.initializer
    and not tint[rewardBar.fill] and not next(motions), "disable left page art, motion, or row callbacks owned")
selection:UpdateSelection(2)
assert(not surfaces[selection.treeButtons[2]].visible, "disabled selection hook painted")
assert(adapter.Apply() and panel.TalentButtonAcquired and surfaces[window].visible)
assert(surfaces[selection.treeButtons[2]].active)
selection:UpdateSelection(3)
assert(not surfaces[selection.treeButtons[2]].active and surfaces[selection.treeButtons[3]].active,
    "first selection after re-enabling left the previous category active")
categoryEnabled = false
assert(adapter.Apply() and not surfaces[window].visible and not panel.TalentButtonAcquired,
    "profile disabling the category did not release an active skin")
categoryEnabled = true

locked = true
window.protected = true
assert(adapter.Apply())
assert(page.Background.alpha == 1 and rewardPage.Background.alpha == 1 and challengePage.Background.alpha == 1
    and not surfaces[window].visible, "native backdrop lost behind protected shell")
locked = false
local fallbackKey, fallback = next(pending)
pending[fallbackKey] = nil
fallback()
assert(page.Background.alpha == 0 and surfaces[window].visible, "backdrop did not replay with the shell")
assert(adapter.Disable())

print("Forever Legacy: cold combat, reward and challenge reuse, native art, lifecycle and warm budget passed")
