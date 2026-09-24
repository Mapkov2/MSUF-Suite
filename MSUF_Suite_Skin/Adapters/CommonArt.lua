local _, NS = ...

-- Exact art suppression for the Group Finder family.  The identifiers below
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
-- No Blizzard method, script, mixin, or frame field is replaced.  The module
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

-- Anonymous parentKey panels are intentionally listed as exact paths.  They
-- have no GetName() value, so GenericWindows' name-token panel classifier
-- cannot identify them.  Semantic dungeon/activity/role textures are omitted.
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

-- PVE's four navigation buttons are bespoke art buttons with no slice fields;
-- GenericWindows therefore correctly avoids guessing.  Here their verified
-- decorative bg/ring regions can be replaced while the dungeon/raid icons and
-- labels remain Blizzard-owned and visible.
local navigationSpecs = {
    { root = "GroupFinderFrame", path = { "groupButton1" } },
    { root = "GroupFinderFrame", path = { "groupButton2" } },
    { root = "GroupFinderFrame", path = { "groupButton3" } },
    { root = "GroupFinderFrame", path = { "groupButton4" } },
}

-- Blizzard switches exactly one of these content panels with Show/Hide when a
-- left navigation button is selected.  Parenting our active decoration to the
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

local function SafeField(object, key)
    if not object then
        return nil
    end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Resolve(rootName, path)
    local object = _G[rootName]
    for index = 1, #(path or {}) do
        object = SafeField(object, path[index])
        if not object then
            return nil
        end
    end
    return object
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonArt.owners[owner]
    if not state then
        state = {
            active = false,
            surfaces = setmetatable({}, { __mode = "k" }),
            deferred = {},
        }
        CommonArt.owners[owner] = state
    end
    return state, owner
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("common art " .. label, message)
    end
end

local function Fade(region, owner)
    if not region or not NS.Cosmetics or type(NS.Cosmetics.Fade) ~= "function" then
        return false
    end
    local ok, result = pcall(NS.Cosmetics.Fade, region, owner)
    if not ok then
        Report("fade", result)
        return false
    end
    return result == true
end

local function FadeNineSlice(nineSlice, owner)
    if not nineSlice or not NS.Cosmetics or type(NS.Cosmetics.FadeNineSlice) ~= "function" then
        return
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, nineSlice, owner)
    if not ok then
        Report("nine slice", message)
    end
end

local function TrackSurface(owner, target)
    local state = CommonArt.owners[owner]
    if state and target then
        state.surfaces[target] = true
    end
end

local function Attach(target, owner, role, radius, inset, listItem, forceEdge)
    if not target or not NS.Surface or type(NS.Surface.Attach) ~= "function"
        or not NS.Safety or not NS.Safety.CanDecorate(target, true) then
        return false
    end
    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = role or "panel",
        radius = radius or 6,
        inset = inset or 0,
        listItem = listItem == true,
        forceEdge = forceEdge == true,
        allowImplicitProtected = true,
    })
    if ok and surface then
        TrackSurface(owner, target)
        return true
    end
    if not ok then
        Report("surface", surface)
    end
    return false
end

local function SkinNavigation(button, owner)
    if not button or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function"
        or not NS.Safety or not NS.Safety.CanControl(button, true) then
        return false
    end
    local ok, state = pcall(NS.ControlSkin.ApplyButton, button, owner, {
        role = "navigation",
        useControlShape = true,
        pillHeight = 48,
        radius = 8,
        inset = 2,
        regions = { "bg", "ring" },
        allowImplicitProtected = true,
    })
    if ok and state then
        TrackSurface(owner, button)
        return true
    end
    if not ok then
        Report("navigation", state)
    end
    return false
end

-- CategorySelection cards are created dynamically by
-- LFGListCategorySelection_AddButton. Blizzard refreshes their category/filter
-- identity and selection texture in LFGListCategorySelection_UpdateCategoryButtons,
-- so that update is the single native lifecycle point we follow. The icon
-- strips are decorative; button identity, label, scripts, anchors, and enabled
-- state remain entirely Blizzard-owned.
local categoryCardRegions = {
    "Icon",
    "Cover",
    "SelectedTexture",
    "HighlightTexture",
}

local function CategoryCardSelected(selection, button)
    local selectedCategory = SafeField(selection, "selectedCategory")
    local categoryID = SafeField(button, "categoryID")
    if selectedCategory == nil or categoryID == nil or selectedCategory ~= categoryID then
        return false
    end
    return SafeField(selection, "selectedFilters") == SafeField(button, "filters")
end

local function SkinCategoryCard(selection, button, owner)
    if not button or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function"
        or not NS.Safety or not NS.Safety.CanControl(button, true) then
        return false
    end
    local ok, state = pcall(NS.ControlSkin.ApplyButton, button, owner, {
        role = "card",
        activeRole = "navigationActive",
        useControlShape = true,
        pillHeight = 46,
        radius = 6,
        inset = 2,
        -- These are large navigation cards, not dense result rows. Keep the
        -- themed fill visible while hover and active remain separate states.
        listItem = false,
        regions = categoryCardRegions,
        active = CategoryCardSelected(selection, button),
        allowImplicitProtected = true,
    })
    if ok and state then
        TrackSurface(owner, button)
        return true
    end
    if not ok then
        Report("category card", state)
    end
    return false
end

local function SkinCategoryCards(selection, owner)
    local state = CommonArt.owners[owner]
    if not selection or not state or not state.active or NS.IsCombatLocked() then
        return false
    end
    local buttons = SafeField(selection, "CategoryButtons")
    if type(buttons) ~= "table" then
        return false
    end
    local applied = false
    for index = 1, #buttons do
        applied = SkinCategoryCard(selection, buttons[index], owner) or applied
    end
    return applied
end

local function ScheduleCategoryCards(selection, owner)
    local state = CommonArt.owners[owner]
    if not selection or not state or not state.active then
        return false
    end
    local key = "common-art:category-cards:" .. tostring(owner)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = CommonArt.owners[owner]
        if current then
            current.deferred[key] = nil
            if current.active then
                SkinCategoryCards(selection, owner)
            end
        end
    end)
    return ran == true, reason
end

local function OnCategoryButtonsUpdated(selection)
    for owner, state in pairs(CommonArt.owners) do
        if state.active then
            ScheduleCategoryCards(selection, owner)
        end
    end
end

local function InstallCategoryUpdateHook()
    if CommonArt.categoryUpdateHooked then
        return true
    end
    if type(hooksecurefunc) ~= "function"
        or type(_G.LFGListCategorySelection_UpdateCategoryButtons) ~= "function" then
        return false
    end
    local ok = pcall(function()
        hooksecurefunc("LFGListCategorySelection_UpdateCategoryButtons", OnCategoryButtonsUpdated)
    end)
    CommonArt.categoryUpdateHooked = ok == true
    return CommonArt.categoryUpdateHooked
end

local function ScenariosEnabled()
    local frame = _G.PVEFrame
    local method = SafeField(frame, "ScenariosEnabled")
    if type(method) ~= "function" then
        return false
    end
    local ok, enabled = pcall(method, frame)
    return ok and enabled == true
end

local function ConfigureNavigationIndicator(indicator, button, panel)
    if type(SafeField(indicator, "SetParent")) == "function" then
        indicator:SetParent(panel)
    end
    if type(SafeField(indicator, "ClearAllPoints")) == "function" then
        indicator:ClearAllPoints()
    end
    if type(SafeField(indicator, "SetAllPoints")) == "function" then
        indicator:SetAllPoints(button)
    elseif type(SafeField(indicator, "SetPoint")) == "function" then
        indicator:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        indicator:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    end
    if type(SafeField(button, "GetFrameStrata")) == "function"
        and type(SafeField(indicator, "SetFrameStrata")) == "function" then
        local ok, strata = pcall(button.GetFrameStrata, button)
        if ok and strata then
            pcall(indicator.SetFrameStrata, indicator, strata)
        end
    end
    if type(SafeField(button, "GetFrameLevel")) == "function"
        and type(SafeField(indicator, "SetFrameLevel")) == "function" then
        local ok, level = pcall(button.GetFrameLevel, button)
        if ok and type(level) == "number" then
            pcall(indicator.SetFrameLevel, indicator, level)
        end
    end
    if type(SafeField(indicator, "EnableMouse")) == "function" then
        indicator:EnableMouse(false)
    end
    if type(SafeField(indicator, "Show")) == "function" then
        indicator:Show()
    end
end

local function SkinNavigationIndicator(button, panel, owner)
    if not button or not panel or type(CreateFrame) ~= "function"
        or not NS.Safety or not NS.Safety.CanDecorate(panel, true) then
        return false
    end

    local indicator = CommonArt.navigationIndicators[button]
    if not indicator then
        local ok, created = pcall(CreateFrame, "Frame", nil, panel)
        if not ok or not created then
            if not ok then
                Report("navigation indicator", created)
            end
            return false
        end
        indicator = created
        CommonArt.navigationIndicators[button] = indicator
    end

    ConfigureNavigationIndicator(indicator, button, panel)
    -- This owned frame sits above the Blizzard navigation button so parent
    -- visibility can synchronize selection without a hook. A transparent
    -- center preserves the native icon and label while the themed edge marks
    -- the selected entry.
    if Attach(indicator, owner, "navigationActive", 8, 2, true, true) then
        return true
    end
    if type(SafeField(indicator, "Hide")) == "function" then
        indicator:Hide()
    end
    return false
end

local function SkinNavigationFamily(owner)
    local panelNames = ScenariosEnabled() and navigationPanels.scenarios or navigationPanels.standard
    local used = setmetatable({}, { __mode = "k" })
    for index = 1, #navigationSpecs do
        local spec = navigationSpecs[index]
        local button = Resolve(spec.root, spec.path)
        SkinNavigation(button, owner)
        local panel = panelNames[index] and _G[panelNames[index]] or nil
        if button and panel and SkinNavigationIndicator(button, panel, owner) then
            used[button] = true
        end
    end
    for button, indicator in pairs(CommonArt.navigationIndicators) do
        if not used[button] and type(SafeField(indicator, "Hide")) == "function" then
            indicator:Hide()
        end
    end
end

local function ApplyPanelSpec(spec, owner)
    local target = Resolve(spec.root, spec.path)
    if not target then
        return false
    end
    Attach(target, owner, spec.role, spec.role == "popup" and 8 or 6, spec.inset)
    for index = 1, #(spec.fade or {}) do
        Fade(SafeField(target, spec.fade[index]), owner)
    end
    if spec.nineSlice then
        FadeNineSlice(SafeField(target, "NineSlice"), owner)
        Fade(SafeField(target, "Bg"), owner)
        Fade(SafeField(target, "Background"), owner)
    end
    for index = 1, #(spec.nineSliceFields or {}) do
        local field = SafeField(target, spec.nineSliceFields[index])
        FadeNineSlice(field, owner)
        Fade(SafeField(field, "Bg"), owner)
        Fade(SafeField(field, "Background"), owner)
    end
    return true
end

local rowRegions = {
    -- BackgroundTexture communicates filtered/applied/selected state through
    -- red/green/yellow atlases in LFGListSearchEntry_Update and is deliberately
    -- preserved.  ResultBG and Highlight are neutral Blizzard chrome.
    searchResult = { "ResultBG", "Highlight" },
    applicant = { "Background" },
    activity = {},
}

local function SkinRow(row, kind, owner)
    if not row or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function"
        or not NS.Safety or not NS.Safety.CanControl(row, true) then
        return false
    end
    local ok, state = pcall(NS.ControlSkin.ApplyButton, row, owner, {
        role = "card",
        activeRole = "navigationActive",
        useControlShape = true,
        pillHeight = kind == "searchResult" and 46 or 24,
        radius = 4,
        inset = 1,
        listItem = true,
        regions = rowRegions[kind] or {},
        allowImplicitProtected = true,
    })
    if ok and state then
        TrackSurface(owner, row)
        return true
    end
    if not ok then
        Report("row", state)
    end
    return false
end

local function SkinRowForOwner(row, kind, owner)
    local state = CommonArt.owners[owner]
    if not state or not state.active then
        return
    end
    -- The finder can remain visible while combat starts. Dynamic cosmetic rows
    -- are optional, so never enqueue traversal or mutate them in combat.
    if NS.IsCombatLocked() then
        return
    end
    SkinRow(row, kind, owner)
end

local function SkinRowForOwners(row, kind)
    for owner, state in pairs(CommonArt.owners) do
        if state.active then
            SkinRowForOwner(row, kind, owner)
        end
    end
end

local function ScrollBoxInitializedEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterScrollBox(scrollBox, kind)
    local event = ScrollBoxInitializedEvent()
    if not scrollBox or not event or CommonArt.scrollBoxes[scrollBox]
        or type(SafeField(scrollBox, "RegisterCallback")) ~= "function" then
        return false
    end

    local token = {}
    local function OnInitializedFrame(_, row)
        SkinRowForOwners(row, kind)
    end
    local ok, message = pcall(scrollBox.RegisterCallback, scrollBox, event, OnInitializedFrame, token)
    if not ok then
        Report("scroll box", message)
        return false
    end
    CommonArt.scrollBoxes[scrollBox] = { token = token, kind = kind }
    if type(SafeField(scrollBox, "ForEachFrame")) == "function" then
        pcall(scrollBox.ForEachFrame, scrollBox, function(row)
            SkinRowForOwners(row, kind)
        end)
    end
    return true
end

local function RegisterExactScrollBoxes()
    for index = 1, #scrollBoxSpecs do
        local spec = scrollBoxSpecs[index]
        RegisterScrollBox(Resolve(spec.root, spec.path), spec.kind)
    end
end

local function ApplyNow(owner)
    local state = CommonArt.owners[owner]
    if not state or not state.active then
        return false, "disabled"
    end

    Attach(_G.PVEFrame, owner, "shell", 8)
    for index = 1, #exactGlobalRegions do
        Fade(_G[exactGlobalRegions[index]], owner)
    end
    SkinNavigationFamily(owner)
    for index = 1, #panelSpecs do
        ApplyPanelSpec(panelSpecs[index], owner)
    end
    InstallCategoryUpdateHook()
    ScheduleCategoryCards(Resolve("LFGListFrame", { "CategorySelection" }), owner)
    RegisterExactScrollBoxes()
    return _G.PVEFrame ~= nil, _G.PVEFrame and "applied" or "missing"
end

local function ApplyOrDefer(owner)
    local state = CommonArt.owners[owner]
    if not state or not state.active then
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        return false, "combat"
    end
    return ApplyNow(owner)
end

function CommonArt.Apply(owner)
    local state
    state, owner = OwnerState(owner)
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
    return ApplyOrDefer(owner)
end

local function UnregisterScrollBoxes()
    local event = ScrollBoxInitializedEvent()
    if event then
        for scrollBox, registration in pairs(CommonArt.scrollBoxes) do
            local unregister = SafeField(scrollBox, "UnregisterCallback")
            if type(unregister) == "function" then
                pcall(unregister, scrollBox, event, registration.token)
            end
        end
    end
    CommonArt.scrollBoxes = setmetatable({}, { __mode = "k" })
end

function CommonArt.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonArt.owners[owner]
    if not state then
        return true
    end
    state.active = false
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
    end
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    for _, indicator in pairs(CommonArt.navigationIndicators) do
        if type(SafeField(indicator, "Hide")) == "function" then
            indicator:Hide()
        end
    end
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
