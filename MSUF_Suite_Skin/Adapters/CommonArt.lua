local _, NS = ...

-- Retail Group Finder chrome, verified against Gethe/wow-ui-source upstream/live
-- at ab5cb850a3f65e742959e379c4689353a2f4549f (12.1.5.70961):
--
--   Blizzard_GroupFinder/Blizzard_GroupFinder_Mainline.toc
--   Blizzard_GroupFinder/Mainline/PVEFrame.{xml,lua}
--   Blizzard_GroupFinder/Mainline/LFDFrame.xml
--   Blizzard_GroupFinder/Mainline/LFGFrame.xml
--   Blizzard_GroupFinder/Mainline/LFGList.xml
--   Blizzard_GroupFinder/Shared/RaidFinder.xml
--   Blizzard_GroupFinder/Shared/ScenarioFinder.xml
--   Blizzard_Menu/Mainline/MenuTemplates.xml
--   Blizzard_SharedXML/{Mainline/SharedUIPanelTemplates,Shared/InputBox/InputBoxTemplates}.xml
--
-- No Blizzard method, script, mixin, or frame field is replaced. The module
-- only addresses explicitly named globals/parentKey paths and subscribes to
-- ScrollBoxListMixin.Event.OnInitializedFrame for Blizzard-owned pooled rows.
local CommonArt = {
    activeOwnerCount = 0,
    scrollBoxes = setmetatable({}, { __mode = "k" }),
    navigationIndicators = setmetatable({}, { __mode = "k" }),
    categoryUpdateHooked = false,
    groupShowHooked = false,
    waitingForGroupFinder = false,
}
NS.CommonArt = CommonArt

local Field = NS.Safety.Field
local Dispatch = NS.Safety.Dispatch
local Kit = NS.AdapterKit
local Fade = Kit.Fade
local SurfaceSpec = Kit.SurfaceSpec
local Read = NS.Safety.Read
local SkinControl = Kit.SkinControl

local DEFAULT_OWNER = "blizzardWindows"
local GROUP_FINDER_ADDON = "Blizzard_GroupFinder"

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
    { root = "PVEFrame", path = { "Inset" }, role = "panel", nineSlice = true },
    { root = "LFDParentFrame", role = "panel", fade = { "TopTileStreaks" } },
    { root = "LFDParentFrame", path = { "Inset" }, role = "card", nineSlice = true },
    { root = "RaidFinderFrame", role = "panel" },
    { root = "RaidFinderFrame", path = { "Inset" }, role = "card", nineSlice = true },
    { root = "RaidFinderFrameBottomInset", role = "card", nineSlice = true },
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
    {
        root = "LFGListFrame",
        path = { "SearchPanel", "AutoCompleteFrame" },
        role = "popup",
        fade = { "BottomLeftBorder", "BottomRightBorder", "BottomBorder", "LeftBorder", "RightBorder" },
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
    { root = "LFDQueueFrame", path = { "Specific", "ScrollBox" }, kind = "dungeon" },
    { root = "LFDQueueFrame", path = { "Follower", "ScrollBox" }, kind = "dungeon" },
    { root = "ScenarioQueueFrame", path = { "Specific", "ScrollFrame" }, kind = "dungeon" },
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
local DESCRIPTION_SPEC = SurfaceSpec("input", 4, 0)
local DESCRIPTION_BORDER = {
    "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex", "BottomRightTex", "BottomTex", "LeftTex", "RightTex",
}

local BUTTON_SPEC = { role = "button", useControlShape = true, radius = 4, inset = 1, pillHeight = 24 }
local DROPDOWN_SPEC = {
    role = "button", useControlShape = true, radius = 4, inset = 1, pillHeight = 24, regions = { "Background" },
}
local INPUT_SPEC = { role = "input", useControlShape = true, radius = 4, inset = 0, pillHeight = 22 }
local STRETCH_BUTTON_SPEC = {
    role = "button", useControlShape = true, radius = 4, inset = 1, pillHeight = 24,
    regions = {
        "TopLeft", "TopMiddle", "TopRight", "MiddleLeft", "MiddleMiddle",
        "MiddleRight", "BottomLeft", "BottomMiddle", "BottomRight",
    },
}
local CHECKBOX_SPEC = { role = "input", shape = "continuous", radius = 4, inset = 2 }

local QUEUE_ROLES = { "RoleButtonTank", "RoleButtonHealer", "RoleButtonDPS", "RoleButtonLeader" }
local APPLICATION_ROLES = { "TankButton", "HealerButton", "DamagerButton" }
local CATEGORY_BUTTONS = { "StartGroupButton", "FindGroupButton" }
local SEARCH_BUTTONS = { "BackButton", "BackToGroupButton", "SignUpButton" }
local VIEWER_BUTTONS = {
    "RemoveEntryButton", "EditButton", "BrowseGroupsButton",
    "NameColumnHeader", "RoleColumnHeader", "ItemLevelColumnHeader", "RatingColumnHeader",
}
local ENTRY_BUTTONS = { "ListGroupButton", "CancelButton" }
local ENTRY_DROPDOWNS = { "GroupDropdown", "ActivityDropdown", "PlayStyleDropdown" }
local ENTRY_REQUIREMENTS = { "ItemLevel", "PvpItemLevel", "PVPRating", "MythicPlusRating", "VoiceChat" }
local ACTIVITY_BUTTONS = { "SelectButton", "CancelButton" }
local APPLICANT_BUTTONS = { "InviteButton", "InviteButtonSmall", "DeclineButton" }
local READY_ART = { "background", "bottomArt" }

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

-- The exact root, or the exact frame at path below it; nil when a link is
-- missing, never the root in its place.
local function Resolve(rootName, path)
    local root = _G[rootName]
    if path then return Kit.PathOf(root, path) end
    return root
end

-- Deferral keys are common-art:<owner>:<suffix>.
local Owners = Kit.NewOwners({
    prefix = "common-art",
    default = DEFAULT_OWNER,
    surfaces = true,
    init = function(state) state.rowButtons = Kit.WeakSet() end,
})
CommonArt.owners = Owners.owners

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

local ApplyDeferred

local function SkinCardsOf(state, selection)
    local root = Resolve("PVEFrame")
    if Kit.IsHidden(root) then
        state.painted = false
        Kit.DeferHidden(root, state, ApplyDeferred, state, nil, nil, 20)
        return
    end
    SkinCategoryCards(selection, state)
end

local function ScheduleCategoryCards(selection, state)
    if not selection or not state.active then
        return false
    end
    return Owners.RunOrDefer(state, "category-cards", SkinCardsOf, selection)
end

-- A post-hook on Blizzard's global: each owner's pass is its own error
-- boundary, so a raising pass never reaches Blizzard's caller.
local function OnCategoryButtonsUpdated(selection)
    for _, state in pairs(CommonArt.owners) do
        if state.active then
            Dispatch(ScheduleCategoryCards, selection, state)
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
    local nineSliceFields = spec.nineSliceFields
    for index = 1, nineSliceFields and #nineSliceFields or 0 do
        local field = Field(target, nineSliceFields[index])
        Kit.FadeNineSlice(state, field)
        Kit.FadeNineSlice(state, Field(field, "NineSlice"))
        Kit.FadeFields(state, field, panelArtFields)
    end
    return true
end

local function SkinButtons(state, frame, fields, spec)
    for index = 1, #fields do SkinControl(state, Field(frame, fields[index]), spec or BUTTON_SPEC) end
end

local function SkinIconButton(state, button, spec)
    local normal = NS.Safety.Call(button, "GetNormalTexture")
    if not SkinControl(state, button, spec) then return false end
    Fade(state, normal)
    return true
end

local function SkinDescription(state, description)
    -- Skin InputScrollFrame's outer shell. The EditBox keeps its native text and permissions.
    if Kit.Attach(state, description, DESCRIPTION_SPEC) then
        Kit.FadeFields(state, description, DESCRIPTION_BORDER)
    end
end

local function SkinQueueControls(state)
    SkinControl(state, LFDQueueFrameFindGroupButton, BUTTON_SPEC)
    SkinControl(state, RaidFinderFrameFindRaidButton, BUTTON_SPEC)
    SkinControl(state, ScenarioQueueFrameFindGroupButton, BUTTON_SPEC)
    SkinControl(state, Field(LFDQueueFrame, "TypeDropdown"), DROPDOWN_SPEC)
    SkinControl(state, Field(RaidFinderQueueFrame, "SelectionDropdown"), DROPDOWN_SPEC)
    SkinControl(state, Field(ScenarioQueueFrame, "Dropdown"), DROPDOWN_SPEC)
    for index = 1, #QUEUE_ROLES do
        local name = QUEUE_ROLES[index]
        local dungeon, raid = Resolve("LFDQueueFrame" .. name), Resolve("RaidFinderQueueFrame" .. name)
        Fade(state, Field(dungeon, "background"))
        Fade(state, Field(raid, "background"))
        SkinIconButton(state, Field(dungeon, "checkButton"), CHECKBOX_SPEC)
        SkinIconButton(state, Field(raid, "checkButton"), CHECKBOX_SPEC)
    end
    Kit.FadeAtlas(state, Field(LFDQueueFrame, "Follower"), "spec-dividerline")
end

local function SkinPremadeSearch(state, search, viewer)
    SkinControl(state, Field(search, "SearchBox"), INPUT_SPEC, "ApplySearchBox")
    SkinControl(state, Field(search, "FilterButton"), DROPDOWN_SPEC)
    SkinControl(state, Field(Field(search, "ScrollBox"), "StartGroupButton"), BUTTON_SPEC)
    SkinButtons(state, search, SEARCH_BUTTONS)
    SkinIconButton(state, Field(search, "RefreshButton"), BUTTON_SPEC)
    SkinIconButton(state, Field(viewer, "RefreshButton"), BUTTON_SPEC)
    SkinIconButton(state, Field(viewer, "AutoAcceptButton"), CHECKBOX_SPEC)
    SkinButtons(state, viewer, VIEWER_BUTTONS)
end

local function SkinPremadeEntry(state, entry)
    SkinButtons(state, entry, ENTRY_BUTTONS)
    SkinButtons(state, entry, ENTRY_DROPDOWNS, DROPDOWN_SPEC)
    SkinControl(state, Field(entry, "Name"), INPUT_SPEC, "ApplySearchBox")
    SkinDescription(state, Field(entry, "Description"))
    for index = 1, #ENTRY_REQUIREMENTS do
        local requirement = Field(entry, ENTRY_REQUIREMENTS[index])
        SkinIconButton(state, Field(requirement, "CheckButton"), CHECKBOX_SPEC)
        SkinControl(state, Field(requirement, "EditBox"), INPUT_SPEC, "ApplySearchBox")
    end
    SkinIconButton(state, Kit.Path(entry, "CrossFactionGroup", "CheckButton"), CHECKBOX_SPEC)
    SkinIconButton(state, Kit.Path(entry, "PrivateGroup", "CheckButton"), CHECKBOX_SPEC)
    local dialog = Kit.Path(entry, "ActivityFinder", "Dialog")
    SkinControl(state, Field(dialog, "EntryBox"), INPUT_SPEC, "ApplySearchBox")
    SkinButtons(state, dialog, ACTIVITY_BUTTONS)
end

local function SkinPremadeControls(state, list)
    local selection = Field(list, "CategorySelection")
    SkinButtons(state, selection, CATEGORY_BUTTONS)
    SkinPremadeSearch(state, Field(list, "SearchPanel"), Field(list, "ApplicationViewer"))
    SkinPremadeEntry(state, Field(list, "EntryCreation"))
    local application = LFGListApplicationDialog
    SkinDescription(state, Field(application, "Description"))
    for index = 1, #APPLICATION_ROLES do
        SkinIconButton(state, Kit.Path(application, APPLICATION_ROLES[index], "CheckButton"), CHECKBOX_SPEC)
    end
end

local function SkinDungeonReady(state)
    local dialog = LFGDungeonReadyDialog
    Kit.FadeFields(state, dialog, READY_ART)
    SkinControl(state, Field(dialog, "enterButton"), BUTTON_SPEC)
    SkinControl(state, Field(dialog, "leaveButton"), BUTTON_SPEC)
end

local function ScheduleDungeonReady(state)
    if not state.active or not LFGDungeonReadyPopup then return end
    if Kit.DeferHidden(LFGDungeonReadyPopup, state, ScheduleDungeonReady, state, nil, nil, 20) then return end
    Owners.RunOrDefer(state, "dungeon-ready", SkinDungeonReady)
end

local function SkinRowButton(state, button, spec)
    -- These child controls live for the pooled frame's lifetime. Rebinding
    -- an element only changes the native check or icon state.
    if button and not state.rowButtons[button] and SkinIconButton(state, button, spec) then
        state.rowButtons[button] = true
    end
end

local function SkinFinderRow(state, row, kind)
    if kind == "dungeon" then
        SkinRowButton(state, Field(row, "enableButton"), CHECKBOX_SPEC)
        NS.Checkmarks.TrackButton(Field(row, "expandOrCollapseButton"), state.owner)
        return
    end
    SkinControl(state, row, rowSpecs[kind])
    if kind == "searchResult" then
        SkinRowButton(state, Field(row, "CancelButton"), STRETCH_BUTTON_SPEC)
    elseif kind == "applicant" then
        for index = 1, #APPLICANT_BUTTONS do
            SkinRowButton(state, Field(row, APPLICANT_BUTTONS[index]), STRETCH_BUTTON_SPEC)
        end
    end
end

local function SkinRowForOwners(row, kind)
    if not row or NS.IsCombatLocked() then return end
    for _, state in pairs(CommonArt.owners) do
        if state.active then
            SkinFinderRow(state, row, kind)
        end
    end
end

local RefreshScrollBox

-- Registered once per ScrollBox as callback(registration, row).
local function OnRowInitialized(registration, row)
    if NS.IsCombatLocked() then
        if not registration.catchUp then
            registration.catchUp = true
            RefreshScrollBox(registration)
        end
        return
    end
    if registration.catchUp or Kit.IsHidden(registration.box[1]) then
        registration.catchUp = true
        RefreshScrollBox(registration)
        return
    end
    SkinRowForOwners(row, registration.kind)
end

RefreshScrollBox = function(registration)
    if CommonArt.activeOwnerCount == 0 then return end
    local scrollBox = registration.box[1]
    if not scrollBox or Kit.DeferHidden(scrollBox, registration, RefreshScrollBox, registration, nil, nil, 20) then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(registration.key, registration.refreshRows)
        return
    end
    NS.CombatGate.Cancel(registration.key)
    registration.catchUp = false
    Kit.ForEachRow(scrollBox, registration.visitRow)
end

local function RegisterScrollBox(scrollBox, kind)
    if not scrollBox or CommonArt.scrollBoxes[scrollBox] then
        return false
    end
    local registration = { kind = kind, catchUp = true, box = setmetatable({ scrollBox }, { __mode = "v" }) }
    registration.key = "common-art:rows:" .. tostring(scrollBox)
    registration.refreshRows = function() RefreshScrollBox(registration) end
    registration.visitRow = function(row) SkinRowForOwners(row, kind) end
    registration.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, registration)
    if not registration.event then return false end
    CommonArt.scrollBoxes[scrollBox] = registration
    RefreshScrollBox(registration)
    return true
end

local function ApplyNow(state)
    if not state.active or state.painted then return end

    if Kit.DeferHidden(Resolve("PVEFrame"), state, ApplyDeferred, state, nil, nil, 20) then return true, "waiting" end
    Kit.Attach(state, _G.PVEFrame, SHELL_SPEC)
    Fade(state, Field(PVEFrame, "shadows"))
    for index = 1, #exactGlobalRegions do
        Fade(state, _G[exactGlobalRegions[index]])
    end
    SkinNavigationFamily(state)
    for index = 1, #panelSpecs do
        ApplyPanelSpec(panelSpecs[index], state)
    end
    SkinQueueControls(state)
    SkinPremadeControls(state, LFGListFrame)
    InstallCategoryUpdateHook()
    ScheduleCategoryCards(Resolve("LFGListFrame", { "CategorySelection" }), state)
    for index = 1, #scrollBoxSpecs do
        local spec = scrollBoxSpecs[index]
        RegisterScrollBox(Resolve(spec.root, spec.path), spec.kind)
    end
    state.painted = true
end

ApplyDeferred = function(state)
    if not state.active or state.painted or state.paintScheduled then return end
    if not state.paintJob then
        state.paintJob = function()
            state.paintScheduled = false
            Owners.RunOrDefer(state, "visible", ApplyNow)
        end
    end
    state.paintScheduled = true
    C_Timer.After(0, state.paintJob)
end

local function OnNativeGroupShown()
    for _, state in pairs(CommonArt.owners) do Dispatch(ApplyDeferred, state) end
end

local function ArmFinder(state)
    if not CommonArt.groupShowHooked then
        -- PVEFrame_ShowFrame shows the shell before it selects and shows the
        -- group page. Queue the paint outside that native call stack.
        CommonArt.groupShowHooked = Kit.HookGlobal("GroupFinderFrame_ShowGroupFrame", OnNativeGroupShown)
    end
    ScheduleDungeonReady(state)
    if not Kit.DeferHidden(Resolve("PVEFrame"), state, ApplyDeferred, state, nil, nil, 20) then
        ApplyDeferred(state)
    end
    return true, "waiting"
end

local function OnGroupFinderLoaded()
    CommonArt.waitingForGroupFinder = false
    if not PVEFrame then return end
    for _, state in pairs(CommonArt.owners) do
        if state.active then Dispatch(ArmFinder, state) end
    end
end

function CommonArt.Apply(owner)
    if NS.Client.isForever then return true, "disabled" end
    local state = Owners.State(owner)
    if not state.active then
        state.active = true
        CommonArt.activeOwnerCount = CommonArt.activeOwnerCount + 1
    end
    state.painted = false
    if PVEFrame then return ArmFinder(state) end
    if NS.Client.IsAddOnLoaded(GROUP_FINDER_ADDON) then return false, "missing" end
    if not CommonArt.waitingForGroupFinder then
        CommonArt.waitingForGroupFinder = true
        EventUtil.ContinueOnAddOnLoaded(GROUP_FINDER_ADDON, OnGroupFinderLoaded)
    end
    return true, "waiting"
end

local function UnregisterScrollBoxes()
    for scrollBox, registration in pairs(CommonArt.scrollBoxes) do
        Kit.CancelHidden(registration)
        NS.CombatGate.Cancel(registration.key)
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
    Owners.Release(state)
    Kit.HideIndicators(CommonArt.navigationIndicators)
    CommonArt.activeOwnerCount = math.max(0, CommonArt.activeOwnerCount - 1)
    if CommonArt.activeOwnerCount == 0 then
        UnregisterScrollBoxes()
    end

    -- The parent blizzardWindows adapter owns the shared ControlSkin and
    -- Cosmetics restoration and performs it exactly once after this disable.
    return true
end

return CommonArt
