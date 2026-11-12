local _, NS = ...

local LegacyTree = {}
NS.ForeverLegacyTree = LegacyTree
if not NS.Client.isForever then
    function LegacyTree.Apply() return true, "disabled" end
    LegacyTree.Disable = LegacyTree.Apply
    return
end

-- Forever Blizzard_LegacySystem (9dc84f0d). The ringed CheckButtons store
-- their category art in the normal and pushed states. Paint the cards
-- around these textures and the native talent states with owned surfaces.
local Kit = NS.AdapterKit
local Safety = NS.Safety
local Field = Safety.Field
local Read = Safety.Read
local Fade = Kit.Fade
local Ensure = Kit.Ensure
local Spec = Kit.SurfaceSpec

local ADDON = "Blizzard_LegacySystem"
local OWNER = "blizzardWindows:forever-legacy-system"
local REPLAY = OWNER .. ":paint"
local ACQUIRED = "TalentButtonAcquired"
local SHELL = Spec("shell", 8, 0)
local RAIL = Spec("panel", 6, 1, false, false, false)
local GRAPH = Spec("panel", 8, 1, false, false, false)
local CATEGORY = Spec("navigation", 8, -3, false, false, true, "navigationActive")
local TAB = Spec("navigation", 6, 1, false, false, true, "navigationActive")
CATEGORY.selectionEdge, TAB.selectionEdge = true, true
local POINTS = Spec("status", 6, 1)
local BADGE = Spec("status", 8, -1)
local POPUP = Spec("popup", 6, 0)
local NODE = Spec("card", 6, -2, false, false, false)
local BUTTON = { role = "button", useControlShape = true, pillHeight = 24, inset = 0 }
local PREVIEW_CHROME = { "Background", "BorderAnchor", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder" }
local REWARD_CARD = Spec("card", 8, 3, false, false, true, "navigationActive")
local CHALLENGE_CARD = Spec("card", 6, 2, false, false, true, "navigationActive")
local CHALLENGE_CATEGORY = Spec("navigation", 6, 1, false, false, true, "navigationActive")
local CRITERION = Spec("status", 4, 2)
REWARD_CARD.selectionEdge, CHALLENGE_CARD.selectionEdge, CHALLENGE_CATEGORY.selectionEdge = true, true, true
local FILTER = { role = "button", useControlShape = true, pillHeight = 20, inset = 1, regions = { "Background" } }
local REWARD_ARROWS = { "LeftButton", "RightButton", "JumpLeftButton", "JumpRightButton" }
local CHALLENGE_CHROME = { "Background", "BackgroundTop", "BackgroundMiddle", "BackgroundBottom", "SelectedOverlay" }
local TAB_KEYS = { "LegacyRewardTrackTab", "LegacyChallengeTab", "LegacyTreeTab" }

local state = {
    owner = OWNER, surfaces = Kit.WeakSet(), textColors = Kit.NewTextColors(),
    rows = Kit.WeakSet(), rewards = Kit.WeakSet(), bars = Kit.WeakSet(),
    scrollbars = Kit.WeakSet(), tintRoles = Kit.WeakSet(),
}
local rowHooks = Kit.WeakSet()
local rewardHooks = Kit.WeakSet()
local objectivesHook
local loadFrame = CreateFrame("Frame")
local Refresh

local function Enabled()
    return NS.DB.enabled ~= false and NS.DB.skins.blizzardWindows ~= false
        and NS.GenericWindows.IsCategoryEnabled("character")
end

local function RequestReplay()
    NS.CombatGate.RunOrDefer(REPLAY, Refresh)
end

local function CanPaint(target)
    if not target then return false end
    local combat = NS.IsCombatLocked()
    if Safety.CanCreateRegions(target, not combat) then return true end
    if combat then
        local protected, explicit = Safety.GetProtection(target)
        if protected and not explicit then RequestReplay() end
    end
    return false
end

local function ColorText(target, role, recapture)
    if Safety.CanDecorate(target, not NS.IsCombatLocked()) then
        Kit.SetTextColor(state.textColors, target, role, recapture)
    end
end

local function PaintButton(button, fadeNormal)
    if not button or state.surfaces[button] or not CanPaint(button) then return end
    local normal = fadeNormal and Safety.Call(button, "GetNormalTexture")
    if Kit.SkinControl(state, button, BUTTON) then Fade(state, normal) end
end

local function Tint(region, role)
    if NS.Checkmarks.TrackTexture(region, OWNER, role) then state.tintRoles[region] = role end
end

local function PaintRankPlate(region)
    if Read(region, "GetAtlas") == "Talents-Square-Box-c60" then
        Tint(region, "buttonFillAlt")
    end
end

local function PaintTalent(_, button)
    -- Acquired fires before Show, after art has been initialized. The edge
    -- and rank backing leave the native icon, rank and state signals intact.
    if state.surfaces[button] or not CanPaint(button) then return end
    if Ensure(state, button, NODE) then Kit.ForEachRegion(button, PaintRankPlate) end
end

local function SyncCategory(button)
    if state.surfaces[button] and CanPaint(button) then
        local checked = Read(button, "GetChecked") == true
        NS.Surface.SetActive(button, checked)
        return checked
    end
end

local function PaintCategories(panel)
    local buttons = Field(panel, "treeButtons")
    if not buttons then return end
    state.selectedTree = nil
    for index = 1, #buttons do
        local button = Field(buttons, index)
        if button and (state.surfaces[button] or CanPaint(button) and Ensure(state, button, CATEGORY)) then
            Fade(state, Field(button, "Background"))
            Fade(state, Field(button, "SelectedGlow"))
            Tint(Field(button, "Ring"), "rim")
            if SyncCategory(button) then state.selectedTree = index end
        end
    end
end

local function OnCategorySelected(panel, index)
    if not state.active or state.selectedTree == index then return end
    local buttons = Field(panel, "treeButtons")
    if not buttons then return end
    if state.selectedTree then SyncCategory(Field(buttons, state.selectedTree)) end
    SyncCategory(Field(buttons, index))
    state.selectedTree = index
end

local function OnCategoriesRebuilt(panel)
    if state.active then PaintCategories(panel) end
end

local function SetTabActive(root, index, active)
    local tab = index and Field(root, TAB_KEYS[index])
    if tab and state.surfaces[tab] and CanPaint(tab) then NS.Surface.SetActive(tab, active) end
end

local function PaintTabs(root)
    local page = Field(root, "currentPage")
    for index = 1, #TAB_KEYS do
        local tab = Field(root, TAB_KEYS[index])
        local painted, surface
        if CanPaint(tab) then painted, surface = Ensure(state, tab, TAB) end
        if painted then
            -- Shared with the Group Finder and Professions side tabs.
            Kit.FitSideTab(tab, surface)
            Fade(state, Field(tab, "Background"))
            local selected = Field(tab, "SelectedTexture")
            Fade(state, selected)
            NS.Surface.SetActive(tab, page == index)
        end
    end
    state.selectedPage = page
end

local function OnPageSelected(root, index)
    if not state.active or state.selectedPage == index then return end
    SetTabActive(root, state.selectedPage, false)
    SetTabActive(root, index, true)
    state.selectedPage = index
end

local function PaintShell(root)
    if CanPaint(root) and Ensure(state, root, SHELL) then
        Fade(state, Field(root, "Bg"))
        Fade(state, Field(root, "TopTileStreaks"))
        Kit.FadeNineSlice(state, Field(root, "NineSlice"))
        ColorText(Kit.Path(root, "TitleContainer", "TitleText"), "title")
        PaintButton(Field(root, "CloseButton"))
    end
    PaintTabs(root)
    if NS.IsCombatLocked() then
        NS.WindowControls.TrackFocus(root, OWNER)
        RequestReplay()
    else
        NS.WindowControls.Attach(root, OWNER)
        NS.ContentMotion.Watch(root, OWNER)
    end
end

local function PaintPoints(page, panel)
    local points = Field(page, "LegacyTreePointSummary")
    if CanPaint(points) and Ensure(state, points, POINTS) then
        Fade(state, Field(points, "Border"))
        ColorText(Field(points, "AvailablePointsLabel"), "text")
        ColorText(Kit.Path(points, "Shield", "Points"), "text")
    end
    local spent = Field(panel, "SpentPointsFrame")
    if CanPaint(spent) and Ensure(state, spent, BADGE) then
        Fade(state, Field(spent, "Background"))
        ColorText(Field(spent, "Text"), "text")
    end
end

local function PaintTree(page, panel, selection, shellReady)
    if CanPaint(panel) and Ensure(state, panel, GRAPH) then
        if shellReady then Fade(state, Field(page, "Background")) end
        Fade(state, Kit.Path(page, "VerticalDivider", "VerticalDivider"))
    end
    if CanPaint(selection) then Ensure(state, selection, RAIL) end
    PaintCategories(selection)
    PaintPoints(page, panel)
    local emblem = Field(panel, "SelectedTreeIcon")
    Tint(Field(emblem, "Ring"), "rim")
    ColorText(Field(emblem, "SelectedTreeLabel"), "title")
    local search = Field(panel, "SearchBox")
    if search and not state.surfaces[search] and CanPaint(search) then Kit.SkinSearchBox(state, search) end
    local preview = Field(panel, "SearchPreviewContainer")
    if CanPaint(preview) and Ensure(state, preview, POPUP) then Kit.FadeFields(state, preview, PREVIEW_CHROME) end
    PaintButton(Field(panel, "ApplyButton"), true)
    -- Reset/undo icons are separately keyed Icon regions. Leave their native
    -- art, highlight and disabled/desaturated state in control.
    local reset, undo = Field(panel, "ResetButton"), Field(panel, "UndoButton")
    if CanPaint(reset) then Ensure(state, reset, BUTTON) end
    if CanPaint(undo) then Ensure(state, undo, BUTTON) end
end

-- The track applies a native mask to these three textures while scrolling.
-- Tint them in place so the value, bar bounds and clipping stay native.
local function PaintProgress(bar, background)
    if not bar or state.bars[bar] or not CanPaint(bar) then return end
    Tint(background, "buttonFill")
    Tint(Field(bar, "ProgressBarFrame"), "rim")
    Tint(Safety.Call(bar, "GetStatusBarTexture"), "accentBright")
    ColorText(Field(bar, "Text"), "text")
    state.bars[bar] = true
end

local function SetRewardActive(card, record)
    local active = record.featured or record.hovered
    if active ~= record.active and CanPaint(card) and NS.Surface.SetActive(card, active) then
        record.active = active
    end
end

local function OnRewardRefresh(card, _, displayLevel, selected)
    local record = state.rewards[card]
    if not record then return end
    local level = Kit.Path(card, "info", "level")
    if not Safety.Public(level) or not Safety.Public(displayLevel) or not Safety.Public(selected) then return end
    record.featured = selected == true or level ~= nil and level == displayLevel
    SetRewardActive(card, record)
end

local function OnRewardHover(card)
    local record = state.rewards[card]
    if not record then return end
    record.hovered = Read(Field(card, "Highlight"), "IsShown") == true
    SetRewardActive(card, record)
end

local function PaintRewardCard(card)
    if not card then return end
    local record = state.rewards[card]
    if record then
        SetRewardActive(card, record)
        return
    end
    if not CanPaint(card) or not Ensure(state, card, REWARD_CARD) then return end
    local background, highlight = Field(card, "RewardCardBG"), Field(card, "Highlight")
    local atlas = Read(background, "GetAtlas")
    state.rewards[card] = {
        featured = atlas ~= nil and atlas == Field(card, "lastEarnedBackgroundFrameAtlas"),
        hovered = Read(highlight, "IsShown") == true,
    }
    -- RenownLevel:ApplyAlpha changes only the native labels. The card frame
    -- is clipped by the reward track's ClipFrame along with the owned art.
    Fade(state, background)
    Fade(state, highlight)
    Tint(Field(card, "LevelSquare"), "rim")
    Tint(Field(card, "IconBorder"), "rim")
    if not rewardHooks[card] then
        Kit.HookFunction(card, "Refresh", Safety.Isolated(OnRewardRefresh))
        card:HookScript("OnEnter", Safety.Isolated(OnRewardHover))
        card:HookScript("OnLeave", Safety.Isolated(OnRewardHover))
        rewardHooks[card] = true
    end
    SetRewardActive(card, state.rewards[card])
end

local function PaintRewardCards(page)
    if not state.active then return end
    local track = Field(page, "LegacyRewardProgressFrame")
    local cards = Safety.Read(track, "GetElements")
    if not cards then return end
    for index = 1, #cards do PaintRewardCard(Field(cards, index)) end
end

local function PaintRewards(page, shellReady)
    if not page then return end
    if shellReady and CanPaint(page) then Fade(state, Field(page, "Background")) end
    PaintProgress(Field(page, "LegacyRewardProgressBar"), Field(page, "ProgressBarBackground"))
    ColorText(Field(page, "Points"), "text")
    ColorText(Field(page, "PointsLabel"), "title")
    local track = Field(page, "LegacyRewardProgressFrame")
    for index = 1, #REWARD_ARROWS do
        local arrow = Field(track, REWARD_ARROWS[index])
        if arrow and not state.surfaces[arrow] and CanPaint(arrow) then Ensure(state, arrow, BUTTON) end
    end
    PaintRewardCards(page)
end

local function ColorChallengeCategory(row)
    if not state.surfaces[row] then return end
    local selected = Field(row, "selected")
    if Safety.Public(selected) then
        ColorText(Field(row, "ButtonText"), selected == true and "title" or "text", true)
    end
end

local function SyncChallengeCategory(row, selected)
    if state.surfaces[row] and Safety.Public(selected) and CanPaint(row) then
        NS.Surface.SetActive(row, selected == true)
        ColorChallengeCategory(row)
    end
end

local function PaintChallengeCategory(row)
    if state.surfaces[row] then
        SyncChallengeCategory(row, Field(row, "selected"))
        return
    end
    if not CanPaint(row) or not Ensure(state, row, CHALLENGE_CATEGORY) then return end
    -- These normal/highlight textures are category backgrounds. The
    -- collapse glyph and the new-challenge notification are separate.
    Fade(state, Safety.Call(row, "GetNormalTexture"))
    Fade(state, Safety.Call(row, "GetHighlightTexture"))
    if not rowHooks[row] then
        rowHooks[row] = Kit.HookFunction(row, "SetSelected", Safety.Isolated(SyncChallengeCategory))
        row:HookScript("OnEnter", Safety.Isolated(ColorChallengeCategory))
        row:HookScript("OnLeave", Safety.Isolated(ColorChallengeCategory))
    end
    SyncChallengeCategory(row, Field(row, "selected"))
end

local function SyncChallengeCard(row)
    if not state.surfaces[row] or not CanPaint(row) then return end
    local selected = Read(row, "IsSelected") == true
    NS.Surface.SetActive(row, selected)
    local completed = Field(row, "completed")
    if Safety.Public(completed) then
        local role = (selected or completed == true) and "text" or "muted"
        ColorText(Field(row, "Label"), role, true)
        ColorText(Field(row, "Description"), role, true)
        ColorText(Field(row, "HiddenDescription"), role, true)
    end
    local account = Field(row, "accountWide")
    if Safety.Public(account) then
        local titleRole = account == true and "accent" or "buttonFill"
        local title = Field(row, "TitleBar")
        if title and state.tintRoles[title] ~= titleRole then Tint(title, titleRole) end
    end
end

local function PaintChallengeCard(row)
    if state.surfaces[row] then
        SyncChallengeCard(row)
        return
    end
    if not CanPaint(row) or not Ensure(state, row, CHALLENGE_CARD) then return end
    Kit.FadeFields(state, row, CHALLENGE_CHROME)
    if not rowHooks[row] then
        rowHooks[row] = Kit.HookFunction(row, "RefreshStateArt", Safety.Isolated(SyncChallengeCard))
    end
    SyncChallengeCard(row)
end

local function OnChallengeCategory(_, row)
    if state.active and not state.surfaces[row] then PaintChallengeCategory(row) end
end

local function OnChallengeCard(_, row)
    if state.active and not state.surfaces[row] then PaintChallengeCard(row) end
end

local function PaintChallengeList(pane, paint, onRow)
    local scrollBox = Field(pane, "ScrollBox")
    if scrollBox and not state.rows[scrollBox] then
        state.rows[scrollBox] = Kit.RegisterRowCallback(scrollBox, Safety.Isolated(onRow), OWNER)
    end
    Kit.ForEachRow(scrollBox, paint)
    local bar = Field(pane, "ScrollBar")
    if bar and not state.scrollbars[bar] and CanPaint(bar) then
        local styled, reason = NS.ScrollBarSkin.Apply(bar, OWNER)
        if styled or reason == "combat" then state.scrollbars[bar] = true end
    end
end

local function PaintCriterion(row)
    if state.surfaces[row] or not CanPaint(row) or not Ensure(state, row, CRITERION) then return end
    Fade(state, Field(row, "Background"))
    PaintProgress(Field(row, "ProgressBar"), Field(row, "ProgressBarBackground"))
end

local function PaintObjectives(frame)
    if not state.active then return end
    Kit.ForEachActive(Field(frame, "criteriaPool"), math.huge, PaintCriterion)
end

local function PaintChallenges(page, shellReady)
    if not page then return end
    if shellReady and CanPaint(page) then Fade(state, Field(page, "Background")) end
    Kit.FadeAtlas(state, Field(page, "VerticalDivider"), "Legacy-Tree-Frame-divider-Vertical")
    local points = Field(page, "LegacyChallengePointSummary")
    PaintProgress(Field(points, "PointsBar"), Field(points, "ProgressBarBackground"))
    ColorText(Kit.Path(points, "Shield", "Points"), "text")
    local categories = Field(page, "CategoryList")
    local search = Field(categories, "SearchBox")
    if search and not state.surfaces[search] and CanPaint(search) then Kit.SkinSearchBox(state, search) end
    local filter = Field(categories, "FilterDropdown")
    if filter and not state.surfaces[filter] and CanPaint(filter) then Kit.SkinControl(state, filter, FILTER) end
    ColorText(Field(categories, "NoResultsText"), "muted")
    PaintChallengeList(categories, PaintChallengeCategory, OnChallengeCategory)
    PaintChallengeList(Field(page, "DetailPane"), PaintChallengeCard, OnChallengeCard)
    local objectives = Field(_G, "LegacyChallengeObjectives")
    if objectives and objectivesHook ~= objectives then
        if Kit.HookFunction(objectives, "Display", Safety.Isolated(PaintObjectives)) then objectivesHook = objectives end
    end
    PaintObjectives(objectives)
end

local function PaintLegacyPages(root)
    local shellReady = state.surfaces[root]
    PaintRewards(Field(root, "RewardTrackPage"), shellReady)
    PaintChallenges(Field(root, "ChallengesPage"), shellReady)
end

local function HookNative(root, selection)
    if state.hookedRoot == root then return end
    state.hookedRoot = root
    Kit.HookFunction(root, "SelectPage", Safety.Isolated(OnPageSelected))
    Kit.HookFunction(Field(root, "RewardTrackPage"), "SetupRewardTrack", Safety.Isolated(PaintRewardCards))
    Kit.HookFunction(selection, "UpdateSelection", Safety.Isolated(OnCategorySelected))
    Kit.HookFunction(selection, "RefreshTreeButtons", Safety.Isolated(OnCategoriesRebuilt))
end

local function OnThemeChanged(_, domain, key)
    if domain == "theme" or domain == "color" or domain == "appearance" or domain == "profile" then
        Kit.RefreshTextColors(state.textColors)
    end
    -- The shared texture listener has a fixed set of widget color keys.
    -- Local color edits also repaint the exact Legacy-only bindings.
    if domain == "color" then
        for region, role in pairs(state.tintRoles) do
            if role == key then NS.Checkmarks.TrackTexture(region, OWNER, role) end
        end
    end
end

Refresh = function()
    if not state.active or not Enabled() then return false, "disabled" end
    local root = Field(_G, "LegacySystemFrame")
    local page = Field(root, "TreePage")
    local panel = Field(page, "LegacyTreeTraitPanel")
    local selection = Field(page, "LegacyTreeSelectionPanel")
    if not panel or not selection or Safety.IsForbidden(root) then return false, "missing" end
    HookNative(root, selection)
    if not state.panel then
        panel:RegisterCallback(ACQUIRED, Safety.Isolated(PaintTalent), state)
        state.panel = panel
    end
    PaintShell(root)
    PaintTree(page, panel, selection, state.surfaces[root])
    PaintLegacyPages(root)
    for button in panel:EnumerateAllTalentButtons() do PaintTalent(state, button) end
    NS.Registry.AddListener(state, OnThemeChanged)
    return true, "applied"
end

loadFrame:SetScript("OnEvent", Safety.Isolated(function(_, _, addon)
    if addon ~= ADDON then return end
    loadFrame:UnregisterEvent("ADDON_LOADED")
    Refresh()
end))

function LegacyTree.Apply()
    if not Enabled() then
        local released, reason = LegacyTree.Disable()
        return released, reason or "disabled"
    end
    if state.active and state.panel and NS.IsCombatLocked() then return true, "applied" end
    state.active = true
    if not Field(_G, "LegacySystemFrame") then
        if NS.Client.HasAddOn(ADDON) == false then return true, "unavailable" end
        loadFrame:RegisterEvent("ADDON_LOADED")
        return true, "waiting"
    end
    loadFrame:UnregisterEvent("ADDON_LOADED")
    return Refresh()
end

function LegacyTree.Disable()
    if not state.active then return true end
    if NS.IsCombatLocked() then return false, "combat" end
    state.active = false
    state.selectedTree, state.selectedPage = nil, nil
    loadFrame:UnregisterEvent("ADDON_LOADED")
    NS.CombatGate.Cancel(REPLAY)
    NS.Registry.RemoveListener(state)
    if state.panel then
        state.panel:UnregisterCallback(ACQUIRED, state)
        state.panel = nil
    end
    for scrollBox, event in pairs(state.rows) do
        Kit.UnregisterRowCallback(scrollBox, event, OWNER)
    end
    Kit.RestoreTextColors(state.textColors)
    for target in pairs(state.surfaces) do NS.Surface.SetVisible(target, false) end
    state.surfaces, state.rows, state.rewards = Kit.WeakSet(), Kit.WeakSet(), Kit.WeakSet()
    state.bars, state.scrollbars, state.tintRoles = Kit.WeakSet(), Kit.WeakSet(), Kit.WeakSet()
    return NS.GenericWindows.Disable(OWNER)
end
