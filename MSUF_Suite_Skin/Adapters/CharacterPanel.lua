local _, NS = ...

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call
local Public = Safety.Public
local HasMethod = Safety.HasMethod
local ParentIs = NS.AdapterKit.ParentIs

-- Owner state, deferral and the shared PaperDoll primitives live in
-- PaperDollChrome.lua, which loads right before this file.
local Chrome = NS.PaperDollChrome

---------------------------------------------------------------------------------------------
-- CharacterPanel
--
-- Clean-room Character/PaperDoll coverage verified against
-- Gethe/wow-ui-source upstream/live at
-- 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4:
--
--   Blizzard_UIPanels_Game/Mainline/CharacterFrame.xml
--   Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml
--   Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua
-- Forever uses upstream/forever c6e89983 Camelot/CharacterFrame.xml: its native
-- LeftPaneHost, RightPaneHost and ModeTabs remain responsible for content,
-- sizing, selection and click behavior.
--
-- Blizzard keeps ownership of the model scene, equipment slots, scripts,
-- item/state data and pooled stat lifecycle. Wide equipment geometry is owned
-- reversibly by GearAnnotations, after the exact native UpdateSize completion.
---------------------------------------------------------------------------------------------
local DEFAULT_OWNER = "blizzardWindows"
local MAX_STAT_ROWS = 64

local modelArtNames = {
    "CharacterModelFrameBackgroundTopLeft",
    "CharacterModelFrameBackgroundTopRight",
    "CharacterModelFrameBackgroundBotLeft",
    "CharacterModelFrameBackgroundBotRight",
    "CharacterModelFrameBackgroundOverlay",
    "PaperDollInnerBorderTopLeft",
    "PaperDollInnerBorderTopRight",
    "PaperDollInnerBorderBottomLeft",
    "PaperDollInnerBorderBottomRight",
    "PaperDollInnerBorderLeft",
    "PaperDollInnerBorderRight",
    "PaperDollInnerBorderTop",
    "PaperDollInnerBorderBottom",
    "PaperDollInnerBorderBottom2",
}
-- The first four entries of modelArtNames: Forever tints them instead of fading.
local MODEL_BACKGROUND_COUNT = 4

-- Runtime state lives in weak-keyed side tables, never in fields on
-- Blizzard's frames: the Forever tab rail per CharacterFrame, the label and
-- rule the skin adds to each native mode tab, and the model backdrop
-- colours it replaced.
local foreverNavs = setmetatable({}, { __mode = "k" })
local tabParts = setmetatable({}, { __mode = "k" })
local modelColors = setmetatable({}, { __mode = "k" })

local slotNames = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterShirtSlot",
    "CharacterTabardSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}

local statCategoryFields = {
    "ItemLevelCategory",
    "AttributesCategory",
    "EnhancementsCategory",
}

local FOREVER_VIEWS = {
    { "ReputationFrame", "ReputationDetailFrame" },
    { "TokenFrame", "DetailFrame" },
    { "SkillsFrame", "SkillDetailFrame" },
    { "PVPRankFrame", "DetailFrame" },
    { "StatisticsFrame" },
}

local FOREVER_TAB_FALLBACKS = {
    "Character", "Reputation", "Skills", "PvP", "Currency", "Statistics",
}

local PANE_SPEC = Chrome.Spec("panel", 4, 0)
local DETAIL_SPEC = Chrome.Spec("card", 4, 0)
local NAVIGATION_TAB_SPEC = Chrome.Spec("navigation", 4, 1, true, "navigationActive")
local FOREVER_TAB_SPEC = {
    role = "navigation", activeRole = "navigationActive",
    fillVisible = false, border = 0, radius = 2, inset = 0,
    allowImplicitProtected = true,
}
local STAT_ROW_SPEC = Chrome.Spec("card", 2, 1, true)
local STATS_CARD_SPEC = Chrome.Spec("card", 5, 0)
local STATS_PANEL_SPEC = Chrome.Spec("panel", 5, 0)
local STAT_HEADER_SPEC = Chrome.Spec("card", 3, 1, false)
local MODEL_SPEC = Chrome.Spec("card", 6, 0)
local SIDEBAR_TAB_SPEC = Chrome.Spec("navigation", 5, 1, true)
-- ControlSkin copies these; one per native selection state.
local sidebarControlSpecs = {}
for _, active in ipairs({ true, false }) do
    sidebarControlSpecs[active] = {
        role = "navigation",
        activeRole = "navigationActive",
        active = active,
        useControlShape = true,
        pillHeight = 32,
        radius = 5,
        inset = 1,
        regions = { "TabBg", "Hider", "Highlight" },
        allowImplicitProtected = true,
    }
end

local Fade, Attach, Track = Chrome.Fade, Chrome.Attach, Chrome.Track

-- nil when the region cannot answer (missing, forbidden or secret).
local function IsShown(region)
    local shown = Call(region, "IsShown")
    if shown == nil or not Public(shown) then return nil end
    return shown == true
end

local function FadeAtlasRegions(state, atlas, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Call(region, "GetAtlas") == atlas then Fade(state, region) end
    end
end

local function ForeverLook()
    return NS.Client.isForever and NS.DB and NS.DB.theme
        and NS.DB.theme.look == "foreverGlass"
end

-- Forever mode tabs ------------------------------------------------------------------------

local function CaptureGeometry(frame)
    if not HasMethod(frame, "GetNumPoints") or not HasMethod(frame, "GetWidth")
        or not HasMethod(frame, "GetHeight") or not HasMethod(frame, "ClearAllPoints")
        or not HasMethod(frame, "SetPoint") or not HasMethod(frame, "SetSize") then
        return nil
    end
    local count = frame:GetNumPoints()
    if type(count) ~= "number" or count > 4 then return nil end
    local snapshot = { width = frame:GetWidth(), height = frame:GetHeight(), points = {} }
    snapshot.strata = Safety.Read(frame, "GetFrameStrata")
    if HasMethod(frame, "GetFrameLevel") then snapshot.level = frame:GetFrameLevel() end
    for index = 1, count do
        snapshot.points[index] = { frame:GetPoint(index) }
    end
    return snapshot
end

local function CanMoveForever(frame)
    return frame ~= nil and NS.Safety.CanCreateRegions(frame, true)
        and not NS.Safety.GetProtection(frame)
end

local function RestoreGeometry(frame, snapshot)
    if not frame or not snapshot then return end
    frame:ClearAllPoints()
    for index = 1, #snapshot.points do
        frame:SetPoint(unpack(snapshot.points[index]))
    end
    frame:SetSize(snapshot.width, snapshot.height)
    if snapshot.strata and HasMethod(frame, "SetFrameStrata") then
        frame:SetFrameStrata(snapshot.strata)
    end
    if snapshot.level and HasMethod(frame, "SetFrameLevel") then
        frame:SetFrameLevel(snapshot.level)
    end
end

local function RestoreTitle(state, root)
    local title = Field(root, "TitleText")
    if title then NS.Cosmetics.Restore(title, state.owner) end
end

local function RestoreForeverTabs(state, root)
    local nav = root and foreverNavs[root]
    if not nav or not nav.active then return end
    nav.active, nav.restoring = false, true
    for index, tab in ipairs(nav.tabs) do
        RestoreGeometry(tab, nav.tabGeometry[index])
        local parts = tabParts[tab]
        if parts then
            parts.label:Hide()
            parts.rule:Hide()
        end
        local icon = Field(tab, "Icon")
        if icon then NS.Cosmetics.Restore(icon, state.owner) end
    end
    RestoreGeometry(nav.container, nav.containerGeometry)
    if HasMethod(root, "UpdateTabLayout") then root:UpdateTabLayout() end
    if nav.header then nav.header:Hide() end
    if nav.headerRule then nav.headerRule:Hide() end
    RestoreTitle(state, root)
    nav.restoring = false
end

-- Captures the native tab geometry once; nil when a tab cannot be moved.
local function EnsureForeverNav(root, container, tabs)
    local nav = foreverNavs[root]
    if nav then return nav end
    local original = CaptureGeometry(container)
    if not original or not CanMoveForever(container) then return nil end
    nav = { container = container, containerGeometry = original, tabs = {}, tabGeometry = {} }
    for index = 1, #tabs do
        local tab = tabs[index]
        local geometry = CaptureGeometry(tab)
        if not geometry or not CanMoveForever(tab) then return nil end
        nav.tabs[index], nav.tabGeometry[index] = tab, geometry
    end
    foreverNavs[root] = nav
    return nav
end

local function PlaceForeverTab(state, root, container, tab, index, visualIndex, tabWidth)
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", container, "TOPLEFT", (visualIndex - 1) * tabWidth, 0)
    tab:SetSize(tabWidth, 30)
    local icon = Field(tab, "Icon")
    if icon then Fade(state, icon) end
    local parts = tabParts[tab]
    if not parts then
        parts = { label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
            rule = tab:CreateTexture(nil, "OVERLAY") }
        parts.label:SetPoint("CENTER", tab, "CENTER", 0, 1)
        parts.rule:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 10, 1)
        parts.rule:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -10, 1)
        parts.rule:SetHeight(2)
        tabParts[tab] = parts
    end
    local labelText = tab.tooltipText
    parts.label:SetText(type(labelText) == "string" and labelText ~= "" and labelText
        or FOREVER_TAB_FALLBACKS[index] or tostring(index))
    parts.label:SetWidth(tabWidth - 4)
    parts.label:Show()
    local selected = root.selectedTab == index
    parts.label:SetTextColor(NS.Theme.GetColor(selected and "accent" or "text"))
    parts.rule:SetColorTexture(NS.Theme.GetColor("accent"))
    parts.rule:SetShown(selected)
end

local function PositionForeverTabs(state, root)
    if not ForeverLook() or not CanMoveForever(root) then
        RestoreForeverTabs(state, root)
        return false
    end
    local container = Field(root, "ModeTabs")
    local tabs = Field(container, "Tabs")
    local width = HasMethod(root, "GetWidth") and root:GetWidth()
    if type(tabs) ~= "table" or #tabs < 3 or #tabs > 8
        or type(width) ~= "number" or width < 550
        or not HasMethod(container, "SetFrameStrata")
        or not HasMethod(container, "SetFrameLevel")
        or not HasMethod(root, "GetFrameLevel") then
        RestoreForeverTabs(state, root)
        return false
    end
    local nav = EnsureForeverNav(root, container, tabs)
    if not nav or nav.restoring then return false end
    if not nav.header then
        nav.header = container:CreateTexture(nil, "ARTWORK", nil, -7)
        nav.headerRule = container:CreateTexture(nil, "ARTWORK", nil, -6)
        nav.headerRule:SetHeight(1)
    end
    nav.header:SetColorTexture(NS.Theme.GetColor("microBarFill"))
    nav.headerRule:SetColorTexture(NS.Theme.GetColor("microBarBorder"))

    local visibleCount = 0
    for _, tab in ipairs(nav.tabs) do
        if IsShown(tab) ~= false then visibleCount = visibleCount + 1 end
    end
    if visibleCount == 0 then
        nav.header:Hide()
        nav.headerRule:Hide()
        return false
    end
    nav.header:Show()
    nav.headerRule:Show()
    nav.active = true
    local usable = math.min(384, width - 24)
    local tabWidth = math.min(64, math.floor(usable / visibleCount))
    -- The native reputation/currency lists use HIGH strata. Keep their native
    -- tabs above those panes when presenting the tabs inside the window.
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(math.max(520, root:GetFrameLevel() + 50))
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -26)
    container:SetSize(tabWidth * visibleCount, 30)
    nav.header:ClearAllPoints()
    nav.header:SetPoint("TOPLEFT", container, "TOPLEFT", -4, 2)
    nav.header:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 4, -2)
    nav.headerRule:ClearAllPoints()
    nav.headerRule:SetPoint("BOTTOMLEFT", nav.header, "BOTTOMLEFT", 0, 0)
    nav.headerRule:SetPoint("BOTTOMRIGHT", nav.header, "BOTTOMRIGHT", 0, 0)
    local visualIndex = 0
    for index, tab in ipairs(nav.tabs) do
        if IsShown(tab) ~= false then
            visualIndex = visualIndex + 1
            PlaceForeverTab(state, root, container, tab, index, visualIndex, tabWidth)
        end
    end
    RestoreTitle(state, root)
    return true
end

local function SkinForeverPanes(state, root)
    if not NS.Client.isForever then return end
    local left = Field(root, "LeftPaneHost")
    local right = Field(root, "RightPaneHost")
    if Attach(state, left, PANE_SPEC) then
        FadeAtlasRegions(state, "UI-Character-Info-General-BG", Call(left, "GetRegions"))
    end
    if Attach(state, right, PANE_SPEC) then
        FadeAtlasRegions(state, "UI-Character-Info-Stat-BG", Call(right, "GetRegions"))
        Fade(state, Field(right, "StoneBg"))
    end
end

local function SkinForeverSubframes(state, root)
    if not ForeverLook() or not state.active or NS.IsCombatLocked() then
        return
    end
    -- Camelot already supplies the faction, currency, skills, PvP and
    -- statistics views. Decorate their exact native list and detail hosts as
    -- each Blizzard subframe becomes available; keep its data and scripts.
    for index = 1, #FOREVER_VIEWS do
        local spec = FOREVER_VIEWS[index]
        local view = _G[spec[1]]
        if view and ParentIs(view, root) then
            local list = Field(view, "ScrollBox")
            local detail = spec[2] and Field(view, spec[2])
            if list then Attach(state, list, PANE_SPEC) end
            if detail then Attach(state, detail, DETAIL_SPEC) end
        end
    end
end

local function SkinForeverModeTabs(state, root)
    if not NS.Client.isForever or not state.active or NS.IsCombatLocked() then return end
    local container = Field(root, "ModeTabs")
    local tabs = Field(container, "Tabs")
    if type(tabs) ~= "table" then return end
    Attach(state, container, PANE_SPEC)
    local foreverLook = ForeverLook()
    for index = 1, #tabs do
        local tab = tabs[index]
        if tab then
            local attached
            if foreverLook then
                attached = NS.Surface.Attach(tab, FOREVER_TAB_SPEC) ~= nil
                if attached then Track(state, tab) end
            else
                attached = Attach(state, tab, NAVIGATION_TAB_SPEC)
            end
            if attached then
                Fade(state, Field(tab, "Background"))
                Fade(state, Field(tab, "SelectedTexture"))
                Fade(state, Field(tab, "HighlightTexture"))
                NS.Surface.SetActive(tab, root.selectedTab == index)
            end
        end
    end
    PositionForeverTabs(state, root)
end

-- Stats, model, slots and sidebar ------------------------------------------------------

local function SkinStatRow(state, row)
    if not row then return false end
    Fade(state, Field(row, "Background"))
    if row.Label and row.Value and NS.CharacterStats.StylesRows(_G.CharacterStatsPane) then
        -- The stat-card pass supplies the final spec once for these exact rows.
        Track(state, row)
        return true
    end
    return Attach(state, row, STAT_ROW_SPEC, true)
end

local function SkinStatHeader(state, frame, modern)
    Fade(state, Field(frame, "Background"))
    -- The dedicated pass owns the final section spec; do not paint a boxed
    -- header only to replace it again in the same update.
    if modern then
        Track(state, frame)
    else
        Attach(state, frame, STAT_HEADER_SPEC, true)
    end
end

local function FormatItemLevel(state, frame)
    local value = Field(frame, "Value")
    if not HasMethod(value, "SetText") or not Safety.CanDecorate(value, true) then return end
    -- upstream/live 09b9db79 Mainline/PaperDollFrame.lua and upstream/forever
    -- Camelot/PaperDollFrame.lua use the first two native results for available
    -- and equipped level. Keep their precision; native stat updates also cover
    -- bag/equipment changes, so no inventory scan or extra event loop is needed.
    local available, equipped = NS.AdapterKit.ReadValues(GetAverageItemLevel)
    if type(equipped) ~= "number" or equipped ~= equipped or equipped < 0 then return end
    local text = string.format("%.2f", equipped)
    if type(available) == "number" and available > equipped then
        local maximum = string.format("%.2f", available)
        if maximum ~= text then text = text .. " / " .. maximum end
    end
    -- Blizzard's text from this update, unless the skin's own text is still
    -- shown (a skin pass without a native update in between).
    local shown = Safety.Read(value, "GetText")
    if shown ~= state.itemLevelText or frame ~= state.itemLevelFrame then
        state.itemLevelNative = shown
    end
    value:SetText(text)
    state.itemLevelFrame, state.itemLevelText = frame, text
end

local function SkinStats(state)
    local pane = CharacterStatsPane
    if not state.active or NS.IsCombatLocked() then
        return false
    end

    Fade(state, Field(pane, "ClassBackground"))
    -- Runs after every native stats update (the player's auras queue one):
    -- surfaces that are current are left alone.
    Attach(state, pane, NS.GearAnnotations.IsWide() and STATS_CARD_SPEC or STATS_PANEL_SPEC, true)
    local pool = Field(pane, "statsFramePool")
    local enumerable = HasMethod(pool, "EnumerateActive")
    local modern = enumerable and NS.CharacterStats.StylesRows(pane)

    for index = 1, #statCategoryFields do
        local category = Field(pane, statCategoryFields[index])
        if category then SkinStatHeader(state, category, modern) end
    end
    local itemLevel = Field(pane, "ItemLevelFrame")
    if itemLevel then
        SkinStatHeader(state, itemLevel, modern)
        FormatItemLevel(state, itemLevel)
    end

    if enumerable then
        -- ObjectPoolMixin:EnumerateActive() returns object -> true. Only the
        -- object key is touched; Blizzard owns every value. Retail has far
        -- fewer than 64 active rows; the bound keeps a foreign pool finite.
        local iterator, invariant, control = pool:EnumerateActive()
        for _ = 1, MAX_STAT_ROWS do
            local row = iterator(invariant, control)
            if row == nil then break end
            control = row
            SkinStatRow(state, row)
        end
    end
    NS.CharacterStats.Apply(pane, state.owner)
    return true
end

local function RestoreModelColors(model)
    local colors = modelColors[model]
    if not colors then return end
    for region, color in pairs(colors) do
        region:SetVertexColor(unpack(color))
    end
    modelColors[model] = nil
end

local function SkinModel(state)
    if not state.active or NS.IsCombatLocked() then return false end
    local model = CharacterModelScene
    local foreverLook = ForeverLook()
    if foreverLook then
        local saved = modelColors[model]
        if not saved then
            saved = {}
            modelColors[model] = saved
        end
        for index = 1, MODEL_BACKGROUND_COUNT do
            local region = _G[modelArtNames[index]]
            if region and NS.Safety.CanDecorate(region, true)
                and HasMethod(region, "GetVertexColor") and HasMethod(region, "SetVertexColor") then
                NS.Cosmetics.Restore(region, state.owner)
                if not saved[region] then
                    saved[region] = { region:GetVertexColor() }
                end
                region:SetVertexColor(0.36, 0.44, 0.54, saved[region][4] or 1)
            end
        end
    else
        RestoreModelColors(model)
    end
    for index = foreverLook and MODEL_BACKGROUND_COUNT + 1 or 1, #modelArtNames do
        Fade(state, _G[modelArtNames[index]])
    end
    return Attach(state, model, MODEL_SPEC)
end

local function SkinSidebarTab(state, tab)
    local hider = Field(tab, "Hider")
    if NS.Safety.CanControl(tab, true)
        and NS.ControlSkin.ApplyButton(tab, state.owner, sidebarControlSpecs[IsShown(hider) == false]) then
        Track(state, tab)
        return true
    end
    Fade(state, Field(tab, "TabBg"))
    Fade(state, hider)
    Fade(state, Field(tab, "Highlight"))
    return Attach(state, tab, SIDEBAR_TAB_SPEC)
end

local function SkinSidebar(state)
    if not state.active or NS.IsCombatLocked() then return false end
    local container = _G.PaperDollSidebarTabs
    Fade(state, Field(container, "DecorLeft"))
    Fade(state, Field(container, "DecorRight"))
    local applied = false
    local sidebars = _G.PAPERDOLL_SIDEBARS
    for index = 1, sidebars and #sidebars or 3 do
        local tab = _G["PaperDollSidebarTab" .. index]
        if tab then
            applied = SkinSidebarTab(state, tab) or applied
        end
    end
    return applied
end

local function SkinForeverTabsAndViews(state)
    local root = _G.CharacterFrame
    SkinForeverModeTabs(state, root)
    SkinForeverSubframes(state, root)
end

local function RepositionForeverTabs(state)
    PositionForeverTabs(state, _G.CharacterFrame)
end

local function RefreshForeverLook(state)
    SkinForeverTabsAndViews(state)
    SkinModel(state)
end

local function CharacterView() return NS.CharacterDetails.views[_G.CharacterFrame] end

-- UpdateSize finishes the native PaperDoll resize. ShowSubFrame assigns
-- activeSubframe AFTER showing the PaperDoll child, so reflow the existing
-- snapshots here; do not perform another inventory/tooltip scan.
local function RelayoutPaperDoll(state)
    local view = CharacterView()
    NS.GearAnnotations.ApplyLayout(view)
    if view and view.wide then
        for _, row in ipairs(view.rows) do
            NS.GearAnnotations.Update(view, row, row.slotName)
        end
        NS.GearAnnotations.UpdateSummary(view)
    end
    NS.EQoLCharacter.Refresh()
    SkinStats(state)
end

local CharacterPanel
local panel
local InstallHooks

local function ApplyNow(state)
    local root = _G.CharacterFrame
    if not root or not state.active then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end

    Fade(state, Field(root, "Background"))
    Chrome.FadePortraits(state, root, _G.CharacterFramePortrait)
    Chrome.SkinInset(state, Field(root, "Inset"))
    Chrome.SkinInset(state, Field(root, "InsetRight") or _G.CharacterFrameInsetRight)
    SkinForeverPanes(state, root)

    NS.CharacterDetails.Apply(root, "character", state.owner)

    SkinModel(state)
    SkinStats(state)
    panel:SkinAllSlots(state)
    SkinSidebar(state)
    SkinForeverModeTabs(state, root)
    SkinForeverSubframes(state, root)
    NS.EQoLCharacter.Apply(state.owner)
    InstallHooks()
    return true, "applied"
end

-- Blizzard_UIPanels_Game is not load-on-demand (12.1.0, 12.1.5, Forever), so
-- CharacterFrame exists before this skin loads: no wait for its addon.
panel = Chrome.New({
    prefix = "character-panel",
    addon = "Blizzard_UIPanels_Game",
    rootName = "CharacterFrame",
    slotNames = slotNames,
    applyNow = ApplyNow,
    applyOrWait = ApplyNow,
})
panel.skinAllSlots = function(state) return panel:SkinAllSlots(state) end

CharacterPanel = {
    owners = panel.owners,
    tabParts = tabParts,
    exactSlots = panel.exactSlots,
    hooks = {},
}
NS.CharacterPanel = CharacterPanel

-- During combat the layout pass waits for combat to end, while Blizzard's
-- resize already happened: the moved regions follow it at once (its own
-- error boundary).
local function OnUpdateSize()
    if NS.IsCombatLocked() then
        Safety.Dispatch(NS.GearAnnotations.FollowNativeSize, CharacterView())
    end
    panel:ForActiveOwners("layout", RelayoutPaperDoll)
end
-- During combat the stats pass waits for combat to end; the skin's own stat
-- details follow the rows Blizzard just reassigned at once (paint only, its
-- own error boundary like every pass).
local function OnStatsUpdated()
    if NS.IsCombatLocked() then Safety.Dispatch(NS.CharacterStats.SyncDetails, _G.CharacterStatsPane) end
    panel:ForActiveOwners("stats", SkinStats)
end
local function OnSlotUpdated(slot) panel:RefreshSlot(slot) end
local function OnSidebarUpdated() panel:ForActiveOwners("sidebar", SkinSidebar) end
local function OnModeTabSelected() panel:ForActiveOwners("mode-tabs", SkinForeverTabsAndViews) end
local function OnTabLayout() panel:ForActiveOwners("mode-tabs-layout", RepositionForeverTabs) end

local function OnPaperDollBackground(model)
    if model == _G.CharacterModelScene then
        panel:ForActiveOwners("model", SkinModel)
    end
end

local function HookOnce(key, target, method, callback)
    local hooks = CharacterPanel.hooks
    if hooks[key] then return end
    if target == nil then
        if type(_G[method]) ~= "function" then return end
        hooksecurefunc(method, callback)
    else
        if not HasMethod(target, method) then return end
        hooksecurefunc(target, method, callback)
    end
    hooks[key] = true
end

InstallHooks = function()
    local root = _G.CharacterFrame
    if root and CharacterPanel.layoutRoot ~= root and HasMethod(root, "UpdateSize") then
        hooksecurefunc(root, "UpdateSize", OnUpdateSize)
        CharacterPanel.layoutRoot = root
    end
    HookOnce("stats", nil, "PaperDollFrame_UpdateStats", OnStatsUpdated)
    HookOnce("slots", nil, "PaperDollItemSlotButton_Update", OnSlotUpdated)
    HookOnce("sidebar", nil, "PaperDollFrame_UpdateSidebarTabs", OnSidebarUpdated)
    -- SetPaperDollBackground rewrites the native race background and its
    -- overlay alpha every time the paper doll opens. Re-assert only our
    -- cosmetic suppression after that native update; the model and textures
    -- remain Blizzard-owned.
    HookOnce("modelBackground", nil, "SetPaperDollBackground", OnPaperDollBackground)
    if NS.Client.isForever and root then
        HookOnce("modeTabs", root, "SetSelectedModeTabByFrame", OnModeTabSelected)
        HookOnce("tabLayout", root, "UpdateTabLayout", OnTabLayout)
    end
end

function CharacterPanel.Apply(owner)
    return panel:Activate(owner or DEFAULT_OWNER)
end

function CharacterPanel.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = panel.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    state.active = false
    RestoreModelColors(_G.CharacterModelScene)
    RestoreForeverTabs(state, _G.CharacterFrame)
    NS.EQoLCharacter.Disable(owner)
    NS.CharacterStats.Disable(_G.CharacterStatsPane, owner)
    NS.CharacterDetails.Disable(_G.CharacterFrame, owner)
    -- Gives back Blizzard's own item-level text from its last update rather
    -- than running PaperDoll code (which writes the stat frame's tooltip
    -- fields) from the skin.
    local itemLevel, native = state.itemLevelFrame, state.itemLevelNative
    local value = itemLevel and Field(itemLevel, "Value")
    if type(native) == "string" and Safety.Read(value, "GetText") == state.itemLevelText then
        value:SetText(native)
    end
    state.itemLevelFrame, state.itemLevelText, state.itemLevelNative = nil, nil, nil
    panel:Release(state)
    -- The parent blizzardWindows adapter restores the shared IconSkin,
    -- ControlSkin and Cosmetics owner exactly once through GenericWindows.
    return true
end

local function RefreshForeverLooks() panel:ForActiveOwners("mode-tabs-theme", RefreshForeverLook) end
local previousLook

NS.Registry.AddListener(CharacterPanel, function(_, domain, key)
    local look = NS.DB and NS.DB.theme and NS.DB.theme.look
    local changed = previousLook ~= look
    previousLook = look
    if not NS.Client.isForever or (domain ~= "profile" and not changed
        and not (domain == "theme" and key == "look")) then
        return
    end
    NS.Registry.QueueJob(RefreshForeverLooks)
end)

return CharacterPanel
