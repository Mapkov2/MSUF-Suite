local _, NS = ...

local Field = NS.Safety.Field
local Call = NS.Safety.Call
local Public = NS.Safety.Public

local function HasMethod(target, name)
    return type(target) == "table" and type(target[name]) == "function"
end

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

---------------------------------------------------------------------------------------------
-- PaperDollChrome: shared by CharacterPanel (below) and InspectPanel (next in the
-- TOC). Per-owner state, combat deferral, waiting for the load-on-demand
-- window addon, and the decorative primitives both PaperDoll windows use.
---------------------------------------------------------------------------------------------
local Chrome = {}
Chrome.__index = Chrome
NS.PaperDollChrome = Chrome

-- Surface specs are shared per call site; Surface.Attach stores, never edits them.
function Chrome.Spec(role, radius, inset, listItem, activeRole)
    return {
        role = role,
        radius = radius,
        inset = inset,
        listItem = listItem == true,
        activeRole = activeRole,
        allowImplicitProtected = true,
    }
end

local SLOT_SPEC = Chrome.Spec("button", 4, 0, true)
local INSET_SPEC = Chrome.Spec("panel", 5, 0)

function Chrome.Track(state, target)
    if target then state.surfaces[target] = true end
end

function Chrome.Fade(state, region)
    if not region or NS.IsCombatLocked() or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    return NS.Cosmetics.Fade(region, state.owner) == true
end

function Chrome.FadeNineSlice(state, target)
    local nineSlice = Field(target, "NineSlice")
    if not nineSlice or NS.IsCombatLocked() or not NS.Safety.CanDecorate(nineSlice, true) then
        return false
    end
    NS.Cosmetics.FadeNineSlice(nineSlice, state.owner)
    return true
end

function Chrome.Attach(state, target, spec)
    if not target or NS.IsCombatLocked() or not NS.Safety.CanCreateRegions(target, true)
        or not NS.Surface.Attach(target, spec) then
        return false
    end
    state.surfaces[target] = true
    return true
end

function Chrome.SkinInset(state, inset)
    if not inset then return false end
    Chrome.FadeNineSlice(state, inset)
    Chrome.Fade(state, Field(inset, "Bg"))
    Chrome.Fade(state, Field(inset, "Background"))
    return Chrome.Attach(state, inset, INSET_SPEC)
end

-- The window portrait lives under several names across clients.
function Chrome.FadePortraits(state, root, globalPortrait)
    Chrome.Fade(state, globalPortrait)
    Chrome.Fade(state, Field(root, "Portrait"))
    Chrome.Fade(state, Field(root, "portrait"))
    local container = Field(root, "PortraitContainer")
    Chrome.Fade(state, Field(container, "Portrait"))
    Chrome.Fade(state, Field(container, "portrait"))
end

-- config: prefix (deferral keys), addon, rootName, slotNames, applyNow(state),
-- applyOrWait(state) (applies once the root exists, else waits for the addon),
-- optional initState(state) and slotIcon(slot) fallback.
function Chrome.New(config)
    config.owners = {}
    config.exactSlots = WeakSet()
    config.waiting = false
    return setmetatable(config, Chrome)
end

function Chrome:OwnerState(owner)
    local state = self.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = WeakSet(),
            deferred = {},
            jobs = {},
        }
        if self.initState then self.initState(state) end
        self.owners[owner] = state
    end
    return state
end

-- Runs callback(state) now, or once after combat. A suffix always maps to the
-- same callback, so its combat job and key are built once per owner.
function Chrome:RunOrDefer(state, suffix, callback)
    if not state.active then return false end
    if not NS.IsCombatLocked() then
        callback(state)
        return true
    end
    local job = state.jobs[suffix]
    if not job then
        local key = self.prefix .. ":" .. suffix .. ":" .. tostring(state.owner)
        local owners = self.owners
        job = { key = key }
        job.run = function()
            local current = owners[state.owner]
            if current then current.deferred[key] = nil end
            if current and current.active then callback(current) end
        end
        state.jobs[suffix] = job
    end
    state.deferred[job.key] = true
    NS.CombatGate.RunOrDefer(job.key, job.run)
    return false, "combat"
end

function Chrome:ForActiveOwners(suffix, callback)
    for _, state in pairs(self.owners) do
        if state.active then self:RunOrDefer(state, suffix, callback) end
    end
end

function Chrome:SkinSlot(state, slot)
    if not state.active or not slot or not self.exactSlots[slot] or NS.IsCombatLocked() then
        return false
    end
    Chrome.Attach(state, slot, SLOT_SPEC)
    local icon = Field(slot, "Icon") or Field(slot, "icon")
        or (self.slotIcon and self.slotIcon(slot))
    local border = Field(slot, "IconBorder") or Field(slot, "iconBorder")
    if icon and border then
        NS.IconSkin.Apply(slot, state.owner, {
            icon = icon,
            nativeBorder = border,
            allowImplicitProtected = true,
        })
    end
    return true
end

function Chrome:SkinAllSlots(state)
    if not state.active or NS.IsCombatLocked() then return false end
    local applied = false
    for index = 1, #self.slotNames do
        local name = self.slotNames[index]
        local slot = _G[name]
        if slot then
            self.exactSlots[slot] = true
            Chrome.Fade(state, _G[name .. "Frame"])
            applied = self:SkinSlot(state, slot) or applied
        end
    end
    return applied
end

-- Native slot updates: one slot now, or, in combat, one bounded pass over
-- all slots after PLAYER_REGEN_ENABLED for the whole combat window.
function Chrome:RefreshSlot(slot)
    if not self.exactSlots[slot] then return end
    local skinAll = self.skinAllSlots
    for _, state in pairs(self.owners) do
        if state.active then
            if NS.IsCombatLocked() then
                self:RunOrDefer(state, "slots", skinAll)
            else
                self:SkinSlot(state, slot)
            end
        end
    end
end

function Chrome:ApplyForActiveOwners()
    self:ForActiveOwners("apply", self.applyOrWait)
end

-- True while waiting for the window addon to load.
function Chrome:ScheduleLoad()
    if self.waiting then return true end
    if NS.Client.IsAddOnLoaded(self.addon) or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    self.waiting = true
    EventUtil.ContinueOnAddOnLoaded(self.addon, function()
        self.waiting = false
        self:ApplyForActiveOwners()
    end)
    return true
end

local function CategoryEnabled()
    return NS.GenericWindows.IsCategoryEnabled("character")
end

function Chrome:Activate(owner)
    if not CategoryEnabled() then return true, "disabled" end
    local state = self:OwnerState(owner)
    state.active = true
    if NS.IsCombatLocked() then
        self:RunOrDefer(state, "apply", self.applyOrWait)
        return false, "combat"
    end
    if not _G[self.rootName] then
        if self:ScheduleLoad() then return true, "waiting" end
        return false, "missing"
    end
    return self.applyNow(state)
end

-- Cancels deferred work, hides this owner's surfaces and forgets the owner.
function Chrome:Release(state)
    state.active = false
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
    for target in pairs(state.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
    self.owners[state.owner] = nil
end

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
    if HasMethod(frame, "GetFrameStrata") then snapshot.strata = frame:GetFrameStrata() end
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
    local nav = root and root._msufForeverTabs
    if not nav or not nav.active then return end
    nav.active, nav.restoring = false, true
    for index, tab in ipairs(nav.tabs) do
        RestoreGeometry(tab, nav.tabGeometry[index])
        if tab._msufForeverLabel then tab._msufForeverLabel:Hide() end
        if tab._msufForeverRule then tab._msufForeverRule:Hide() end
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
    local nav = root._msufForeverTabs
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
    root._msufForeverTabs = nav
    return nav
end

local function PlaceForeverTab(state, root, container, tab, index, visualIndex, tabWidth)
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", container, "TOPLEFT", (visualIndex - 1) * tabWidth, 0)
    tab:SetSize(tabWidth, 30)
    local icon = Field(tab, "Icon")
    if icon then Fade(state, icon) end
    if not tab._msufForeverLabel then
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", tab, "CENTER", 0, 1)
        tab._msufForeverLabel = label
        local rule = tab:CreateTexture(nil, "OVERLAY")
        rule:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 10, 1)
        rule:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -10, 1)
        rule:SetHeight(2)
        tab._msufForeverRule = rule
    end
    local labelText = tab.tooltipText
    tab._msufForeverLabel:SetText(type(labelText) == "string" and labelText ~= "" and labelText
        or FOREVER_TAB_FALLBACKS[index] or tostring(index))
    tab._msufForeverLabel:SetWidth(tabWidth - 4)
    tab._msufForeverLabel:Show()
    local selected = root.selectedTab == index
    tab._msufForeverLabel:SetTextColor(NS.Theme.GetColor(selected and "accent" or "text"))
    tab._msufForeverRule:SetColorTexture(NS.Theme.GetColor("accent"))
    tab._msufForeverRule:SetShown(selected)
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
        if view and Call(view, "GetParent") == root then
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
    return Attach(state, row, STAT_ROW_SPEC)
end

local function SkinStatHeader(state, frame, modern)
    Fade(state, Field(frame, "Background"))
    -- The dedicated pass owns the final section spec; do not paint a boxed
    -- header only to replace it again in the same update.
    if modern then
        Track(state, frame)
    else
        Attach(state, frame, STAT_HEADER_SPEC)
    end
end

local function SkinStats(state)
    local pane = _G.CharacterStatsPane
    if not pane or not state.active or NS.IsCombatLocked() then
        return false
    end

    Fade(state, Field(pane, "ClassBackground"))
    Attach(state, pane, NS.GearAnnotations.IsWide() and STATS_CARD_SPEC or STATS_PANEL_SPEC)
    local pool = Field(pane, "statsFramePool")
    local enumerable = HasMethod(pool, "EnumerateActive")
    local modern = enumerable and NS.CharacterStats.StylesRows(pane)

    for index = 1, #statCategoryFields do
        local category = Field(pane, statCategoryFields[index])
        if category then SkinStatHeader(state, category, modern) end
    end
    local itemLevel = Field(pane, "ItemLevelFrame")
    if itemLevel then SkinStatHeader(state, itemLevel, modern) end

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
    local colors = model and model._msufForeverBackgroundColors
    if not colors then return end
    for region, color in pairs(colors) do
        region:SetVertexColor(unpack(color))
    end
    model._msufForeverBackgroundColors = nil
end

local function SkinModel(state)
    if not state.active or NS.IsCombatLocked() then return false end
    local model = _G.CharacterModelScene
    local foreverLook = ForeverLook()
    if model and foreverLook then
        local saved = model._msufForeverBackgroundColors
        if not saved then
            saved = {}
            model._msufForeverBackgroundColors = saved
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
    for index = 1, 3 do
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

-- UpdateSize finishes the native PaperDoll resize. ShowSubFrame assigns
-- activeSubframe AFTER showing the PaperDoll child, so reflow the existing
-- snapshots here; do not perform another inventory/tooltip scan.
local function RelayoutPaperDoll(state)
    local view = NS.CharacterDetails.views[_G.CharacterFrame]
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

local function ApplyOrWait(state)
    if _G.CharacterFrame then
        ApplyNow(state)
    else
        panel:ScheduleLoad()
    end
end

panel = Chrome.New({
    prefix = "character-panel",
    addon = "Blizzard_UIPanels_Game",
    rootName = "CharacterFrame",
    slotNames = slotNames,
    applyNow = ApplyNow,
    applyOrWait = ApplyOrWait,
})
panel.skinAllSlots = function(state) return panel:SkinAllSlots(state) end

CharacterPanel = {
    owners = panel.owners,
    exactSlots = panel.exactSlots,
    hooks = {},
}
NS.CharacterPanel = CharacterPanel

local function OnUpdateSize() panel:ForActiveOwners("layout", RelayoutPaperDoll) end
local function OnStatsUpdated() panel:ForActiveOwners("stats", SkinStats) end
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
    panel:Release(state)
    -- The parent blizzardWindows adapter restores the shared IconSkin,
    -- ControlSkin and Cosmetics owner exactly once through GenericWindows.
    return true
end

NS.Registry.AddListener(CharacterPanel, function(_, domain, key)
    if not NS.Client.isForever or (domain ~= "profile"
        and not (domain == "theme" and key == "look")) or not _G.CharacterFrame then
        return
    end
    panel:ForActiveOwners("mode-tabs-theme", RefreshForeverLook)
end)

return CharacterPanel
