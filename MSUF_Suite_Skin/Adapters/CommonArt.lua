local _, NS = ...

-- Exact art suppression for the Group Finder family. The identifiers below
-- are clean-room mappings verified against Gethe/wow-ui-source upstream/live
-- at 710f59e457317676c0f699e6addaf2c405c2a1a4:
--
--   Blizzard_GroupFinder/Mainline/PVEFrame.xml
--   Blizzard_GroupFinder/Mainline/LFDFrame.xml
--   Blizzard_GroupFinder/Mainline/LFGList.xml
--   Blizzard_GroupFinder/Mainline/LFGList.lua
--   Blizzard_GroupFinder/Shared/RaidFinder.xml
--   Blizzard_GroupFinder/Shared/ScenarioFinder.xml
--
-- No Blizzard method, script, mixin, or frame field is replaced. The module
-- only addresses explicitly named globals/parentKey paths and subscribes to
-- ScrollBoxListMixin.Event.OnInitializedFrame for Blizzard-owned pooled rows.
local CommonArt = {
    owners = {},
    activeOwnerCount = 0,
    scrollBoxes = setmetatable({}, { __mode = "k" }),
    navigationIndicators = setmetatable({}, { __mode = "k" }),
    categoryUpdateHooked = false,
}
NS.CommonArt = CommonArt

local Field = NS.Safety.Field
local Kit = NS.AdapterKit
local Fade = Kit.Fade
local SurfaceSpec = Kit.SurfaceSpec

local DEFAULT_OWNER = "blizzardWindows"

-- These are XML regions with a global $parent-derived name and no parentKey.
-- A bounded child walk cannot resolve them through PVEFrame fields.
local exactGlobalRegions = {
    "PVEFrameBlueBg",
    "PVEFrameTLCorner",
    "PVEFrameTRCorner",
    "PVEFrameBRCorner",
    "PVEFrameBLCorner",
    "PVEFrameLLVert",
    "PVEFrameRLVert",
    "PVEFrameBottomLine",
    "PVEFrameTopLine",
    "PVEFrameTopFiligree",
    "PVEFrameBottomFiligree",

    "LFDParentFrameRoleBackground",
    "LFDParentFrameTopTileStreaks",
    "LFDQueueFrameBackground",

    "RaidFinderFrameRoleBackground",
    "RaidFinderQueueFrameBackground",

    "ScenarioQueueFrameBackground",
}

-- Anonymous parentKey panels are intentionally listed as exact paths. They
-- have no GetName() value, so GenericWindows' name-token panel classifier
-- cannot identify them. Semantic dungeon/activity/role textures are omitted.
local panelSpecs = {
    { root = "LFDParentFrame", role = "panel", fade = { "TopTileStreaks" } },
    { root = "LFDParentFrame", path = { "Inset" }, role = "card", nineSlice = true },
    { root = "RaidFinderFrame", role = "panel" },
    { root = "RaidFinderFrame", path = { "Inset" }, role = "card", nineSlice = true },
    { root = "ScenarioFinderFrame", role = "panel" },
    { root = "ScenarioFinderFrame", path = { "Inset" }, role = "card", nineSlice = true },
    { root = "ScenarioFinderFrame", path = { "Queue" }, role = "panel", fade = { "Bg" } },

    { root = "LFGListFrame", path = { "CategorySelection" }, role = "panel" },
    {
        root = "LFGListFrame",
        path = { "CategorySelection", "Inset" },
        role = "card",
        fade = { "CustomBG" },
        nineSlice = true,
    },
    { root = "LFGListFrame", path = { "NothingAvailable" }, role = "panel" },
    {
        root = "LFGListFrame",
        path = { "NothingAvailable", "Inset" },
        role = "card",
        fade = { "CustomBG" },
        nineSlice = true,
    },
    { root = "LFGListFrame", path = { "SearchPanel" }, role = "panel" },
    {
        root = "LFGListFrame",
        path = { "SearchPanel", "ResultsInset" },
        role = "card",
        nineSlice = true,
    },
    { root = "LFGListFrame", path = { "ApplicationViewer" }, role = "panel", fade = { "InfoBackground" } },
    {
        root = "LFGListFrame",
        path = { "ApplicationViewer", "Inset" },
        role = "card",
        nineSlice = true,
    },
    { root = "LFGListFrame", path = { "EntryCreation" }, role = "panel" },
    {
        root = "LFGListFrame",
        path = { "EntryCreation", "Inset" },
        role = "card",
        fade = { "CustomBG" },
        nineSlice = true,
    },
    {
        root = "LFGListFrame",
        path = { "EntryCreation", "ActivityFinder", "Dialog" },
        role = "popup",
        fade = { "Bg" },
        nineSliceFields = { "Border", "BorderFrame" },
    },
}

-- Surface keeps a reference to its spec, so each panel gets one at load.
for index = 1, #panelSpecs do
    local spec = panelSpecs[index]
    spec.surface = SurfaceSpec(spec.role, spec.role == "popup" and 8 or 6, 0)
end

-- PVE's four navigation buttons are bespoke art buttons with no slice fields;
-- GenericWindows therefore correctly avoids guessing. Here their verified
-- decorative bg/ring regions can be replaced while the dungeon/raid icons and
-- labels remain Blizzard-owned and visible.
local navigationButtons = { "groupButton1", "groupButton2", "groupButton3", "groupButton4" }

-- Blizzard switches exactly one of these content panels with Show/Hide when a
-- left navigation button is selected. Parenting our active decoration to the
-- matching content panel gives us native selection synchronization without a
-- script hook, polling, timer, or recurring event listener.
local navigationPanels = {
    standard = {
        "LFDParentFrame",
        "RaidFinderFrame",
        "LFGListPVEStub",
    },
    scenarios = {
        "LFDParentFrame",
        "ScenarioFinderFrame",
        "RaidFinderFrame",
        "LFGListPVEStub",
    },
}

local scrollBoxSpecs = {
    {
        root = "LFGListFrame",
        path = { "SearchPanel", "ScrollBox" },
        kind = "searchResult",
    },
    {
        root = "LFGListFrame",
        path = { "ApplicationViewer", "ScrollBox" },
        kind = "applicant",
    },
    {
        -- PVEFrame -> GroupFinderFrame -> LFGListFrame -> EntryCreation ->
        -- ActivityFinder -> Dialog -> ScrollBox is deeper than the generic
        -- maxDepth=6 traversal.
        root = "LFGListFrame",
        path = { "EntryCreation", "ActivityFinder", "Dialog", "ScrollBox" },
        kind = "activity",
    },
}

local SHELL_SPEC = SurfaceSpec("shell", 8, 0)

local NAVIGATION_SPEC = {
    role = "navigation",
    useControlShape = true,
    pillHeight = 48,
    radius = 8,
    inset = 2,
    regions = { "bg", "ring" },
}

-- CategorySelection cards are created dynamically by
-- LFGListCategorySelection_AddButton. Blizzard refreshes their category/filter
-- identity and selection texture in LFGListCategorySelection_UpdateCategoryButtons,
-- so that update is the single native lifecycle point we follow. The icon
-- strips are decorative; button identity, label, scripts, anchors, and enabled
-- state remain entirely Blizzard-owned.
local CATEGORY_CARD_SPEC = {
    role = "card",
    activeRole = "navigationActive",
    useControlShape = true,
    pillHeight = 46,
    radius = 6,
    inset = 2,
    -- These are large navigation cards, not dense result rows. Keep the
    -- themed fill visible while hover and active remain separate states.
    listItem = false,
    regions = { "Icon", "Cover", "SelectedTexture", "HighlightTexture" },
}

local function RowSpec(pillHeight, regions)
    return {
        role = "card",
        activeRole = "navigationActive",
        useControlShape = true,
        pillHeight = pillHeight,
        radius = 4,
        inset = 1,
        listItem = true,
        regions = regions,
        allowImplicitProtected = true,
    }
end

local rowSpecs = {
    -- BackgroundTexture communicates filtered/applied/selected state through
    -- red/green/yellow atlases in LFGListSearchEntry_Update and is deliberately
    -- preserved. ResultBG and Highlight are neutral Blizzard chrome.
    searchResult = RowSpec(46, { "ResultBG", "Highlight" }),
    applicant = RowSpec(24, { "Background" }),
    activity = RowSpec(24, {}),
}

local panelArtFields = { "Bg", "Background" }

local function Resolve(rootName, path)
    local root = _G[rootName]
    return path and Kit.PathOf(root, path) or root
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonArt.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = Kit.WeakSet(),
            deferred = {},
        }
        CommonArt.owners[owner] = state
    end
    return state
end

local function CategoryCardSelected(selection, button)
    local selectedCategory = Field(selection, "selectedCategory")
    local categoryID = Field(button, "categoryID")
    if selectedCategory == nil or categoryID == nil or selectedCategory ~= categoryID then
        return false
    end
    return Field(selection, "selectedFilters") == Field(button, "filters")
end

local function SkinCategoryCard(state, selection, button)
    -- ControlSkin copies the spec synchronously, so the shared table can carry
    -- this card's selection for exactly one call.
    CATEGORY_CARD_SPEC.active = CategoryCardSelected(selection, button)
    local skinned = Kit.SkinControl(state, button, CATEGORY_CARD_SPEC)
    CATEGORY_CARD_SPEC.active = nil
    return skinned
end

local function SkinCategoryCards(selection, state)
    if not selection or not state.active or NS.IsCombatLocked() then
        return false
    end
    local buttons = Field(selection, "CategoryButtons")
    if type(buttons) ~= "table" then
        return false
    end
    local applied = false
    for index = 1, #buttons do
        applied = SkinCategoryCard(state, selection, buttons[index]) or applied
    end
    return applied
end

local function ScheduleCategoryCards(selection, state)
    if not selection or not state.active then
        return false
    end
    local owner = state.owner
    local key = "common-art:category-cards:" .. tostring(owner)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = CommonArt.owners[owner]
        if current then
            current.deferred[key] = nil
            if current.active then
                SkinCategoryCards(selection, current)
            end
        end
    end)
    return ran == true, reason
end

local function OnCategoryButtonsUpdated(selection)
    for _, state in pairs(CommonArt.owners) do
        if state.active then
            ScheduleCategoryCards(selection, state)
        end
    end
end

local function InstallCategoryUpdateHook()
    if not CommonArt.categoryUpdateHooked then
        CommonArt.categoryUpdateHooked = Kit.HookGlobal(
            "LFGListCategorySelection_UpdateCategoryButtons", OnCategoryButtonsUpdated)
    end
    return CommonArt.categoryUpdateHooked
end

local usedIndicators = {}

local function SkinNavigationFamily(state)
    local scenarios = NS.Safety.Read(_G.PVEFrame, "ScenariosEnabled") == true
    local panelNames = scenarios and navigationPanels.scenarios or navigationPanels.standard
    local navigation = _G.GroupFinderFrame
    for index = 1, #navigationButtons do
        local button = Field(navigation, navigationButtons[index])
        Kit.SkinControl(state, button, NAVIGATION_SPEC)
        local panel = panelNames[index] and _G[panelNames[index]] or nil
        if button and panel
            and Kit.SelectionIndicator(state, CommonArt.navigationIndicators, button, panel, true) then
            usedIndicators[button] = true
        end
    end
    for button, indicator in pairs(CommonArt.navigationIndicators) do
        if not usedIndicators[button] then indicator:Hide() end
    end
    for button in pairs(usedIndicators) do
        usedIndicators[button] = nil
    end
end

local function ApplyPanelSpec(spec, state)
    local target = Resolve(spec.root, spec.path)
    if not target then
        return false
    end
    Kit.Attach(state, target, spec.surface)
    if spec.fade then
        Kit.FadeFields(state, target, spec.fade)
    end
    if spec.nineSlice then
        Kit.FadeNineSlice(state, Field(target, "NineSlice"))
        Kit.FadeFields(state, target, panelArtFields)
    end
    for index = 1, #(spec.nineSliceFields or {}) do
        local field = Field(target, spec.nineSliceFields[index])
        Kit.FadeNineSlice(state, field)
        Kit.FadeFields(state, field, panelArtFields)
    end
    return true
end

local function SkinRowForOwners(row, kind)
    -- The finder can remain visible while combat starts. Dynamic cosmetic rows
    -- are optional, so never enqueue traversal or mutate them in combat.
    if not row or NS.IsCombatLocked() then return end
    for _, state in pairs(CommonArt.owners) do
        if state.active then
            Kit.SkinControl(state, row, rowSpecs[kind])
        end
    end
end

-- Registered once per ScrollBox as callback(registration, row).
local function OnRowInitialized(registration, row)
    SkinRowForOwners(row, registration.kind)
end

local function RegisterScrollBox(scrollBox, kind)
    if not scrollBox or CommonArt.scrollBoxes[scrollBox] then
        return false
    end
    local registration = { kind = kind }
    registration.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, registration)
    if not registration.event then return false end
    CommonArt.scrollBoxes[scrollBox] = registration
    Kit.ForEachRow(scrollBox, function(row) SkinRowForOwners(row, kind) end)
    return true
end

local function ApplyNow(state)
    if not state.active then
        return false, "disabled"
    end

    Kit.Attach(state, _G.PVEFrame, SHELL_SPEC)
    for index = 1, #exactGlobalRegions do
        Fade(state, _G[exactGlobalRegions[index]])
    end
    SkinNavigationFamily(state)
    for index = 1, #panelSpecs do
        ApplyPanelSpec(panelSpecs[index], state)
    end
    InstallCategoryUpdateHook()
    ScheduleCategoryCards(Resolve("LFGListFrame", { "CategorySelection" }), state)
    for index = 1, #scrollBoxSpecs do
        local spec = scrollBoxSpecs[index]
        RegisterScrollBox(Resolve(spec.root, spec.path), spec.kind)
    end
    return _G.PVEFrame ~= nil, _G.PVEFrame and "applied" or "missing"
end

function CommonArt.Apply(owner)
    local state = OwnerState(owner)
    if not state.active then
        state.active = true
        CommonArt.activeOwnerCount = CommonArt.activeOwnerCount + 1
    end
    -- Blizzard_GroupFinder is a non-LoD Mainline addon. A missing root here is
    -- therefore an incompatible/missing client surface, not a reason to keep a
    -- second ADDON_LOADED dispatcher alive.
    if not _G.PVEFrame then
        return false, "missing"
    end
    if NS.IsCombatLocked() then
        return false, "combat"
    end
    return ApplyNow(state)
end

local function UnregisterScrollBoxes()
    for scrollBox, registration in pairs(CommonArt.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, registration.event, registration)
    end
    CommonArt.scrollBoxes = Kit.WeakSet()
end

function CommonArt.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonArt.owners[owner]
    if not state then
        return true
    end
    state.active = false
    Kit.CancelDeferred(state)
    Kit.HideSurfaces(state)
    Kit.HideIndicators(CommonArt.navigationIndicators)
    CommonArt.owners[owner] = nil
    CommonArt.activeOwnerCount = math.max(0, CommonArt.activeOwnerCount - 1)
    if CommonArt.activeOwnerCount == 0 then
        UnregisterScrollBoxes()
    end

    -- The parent blizzardWindows adapter owns the shared ControlSkin and
    -- Cosmetics restoration and performs it exactly once after this disable.
    return true
end

-- Read-only diagnostic for the focused runtime smoke and `/dump` debugging.
-- The frame remains wholly owned by MapkoSkin; callers receive no state.
function CommonArt.GetNavigationIndicator(button)
    return CommonArt.navigationIndicators[button]
end

return CommonArt
