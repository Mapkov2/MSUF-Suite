local _, NS = ...

-- Checkmarks in Blizzard's menus (see Checkmarks.lua): modern dropdown
-- popups, the Settings category list, tabs and control rows, and the legacy
-- UIDropDownMenu lists. Each registration is reversible and bound to the
-- owner that asked for it.
local Checkmarks = NS.Checkmarks
-- Checkmarks.lua's private helpers: taken off NS again, so nothing internal
-- stays reachable through _G.MapkoSkin.
local Shared = NS.CheckmarksShared
NS.CheckmarksShared = nil
local Safety = NS.Safety
local BlizzardYellow = NS.BlizzardYellow
local Field = Shared.Field
local Getter = Shared.Getter
local CanTrack = Shared.CanTrack
local OwnerSet = Shared.OwnerSet
local WalkControlTree = Shared.WalkControlTree

local function LooksLikeDropdown(button)
    return button and type(button.RegisterCallback) == "function"
        and type(button.UnregisterCallback) == "function"
        and type(button.IsMenuOpen) == "function"
        and type(button.GetMenuDescription) == "function"
end

Checkmarks.IsDropdown = LooksLikeDropdown

------------------------------------------------------------------ dropdown popups
-- Blizzard pools the same MenuTemplateBase frames across unrelated dropdowns.
-- A shared owner prevents disabling dropdown A from hiding a pooled popup
-- currently reused by dropdown B.
local DROPDOWN_MENU_OWNER = "blizzard-dropdown-menus"

local DROPDOWN_POPUP_SPEC = {
    role = "popup",
    radius = 6,
    inset = 0,
    maxDepth = 6,
    maxNodes = 320,
    menuPopup = true,
    registerDynamicRows = true,
    allowImplicitProtected = true,
}

-- DropdownButtonMixin passes the registration owner (the state) first.
local function OnMenuOpen(state, dropdown)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled then return end
    dropdown = dropdown or state.button
    BlizzardYellow.TrackDropdown(dropdown)
    local menu = Field(dropdown, "menu")
    if not menu or not Safety.CanDecorate(menu, true) then return end
    -- Modern Blizzard_Menu proxies are compositor-managed: existing
    -- check/text regions remain safe to tint, but owned Surface creation is
    -- forbidden for their lifetime.
    if not Safety.IsCompositorManaged(menu) then
        NS.GenericWindows.ApplyFrame(menu, state.menuOwner, DROPDOWN_POPUP_SPEC)
    end
    Checkmarks.TrackFrame(menu, state.menuOwner)
end

function Checkmarks.UntrackDropdown(button)
    local state = Checkmarks.dropdowns[button]
    if not state then return false end
    if type(button.UnregisterCallback) == "function" then
        button:UnregisterCallback(state.event, state)
    end
    Checkmarks.dropdowns[button] = nil
    local ownerSet = Checkmarks.owners[state.owner]
    if ownerSet then ownerSet[button] = nil end
    if not next(Checkmarks.dropdowns) then
        NS.GenericWindows.Disable(DROPDOWN_MENU_OWNER)
    end
    return true
end

function Checkmarks.TrackDropdown(button, owner)
    if NS.IsCombatLocked() or not LooksLikeDropdown(button) or not CanTrack(button) then
        return false
    end
    -- Blizzard_Menu (DropdownButton.lua) loads first on Retail and Forever.
    local event = DropdownButtonMixin.Event.OnMenuOpen
    BlizzardYellow.TrackDropdown(button)
    local existing = Checkmarks.dropdowns[button]
    if existing and existing.owner == owner and existing.event == event then
        return true
    end
    if existing then Checkmarks.UntrackDropdown(button) end

    local state = { owner = owner, event = event, menuOwner = DROPDOWN_MENU_OWNER, button = button }
    button:RegisterCallback(event, OnMenuOpen, state)
    Checkmarks.dropdowns[button] = state
    local ownerSet = OwnerSet(owner)
    if ownerSet then ownerSet[button] = true end
    return true
end

------------------------------------------------------------------ Settings panel
local SETTINGS_CATEGORY_EVENT = "Settings.CategoryChanged"
local SETTINGS_TAB_KEYS = { "GameTab", "AddOnsTab" }

local SETTINGS_CATEGORY_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    useControlShape = true,
    pillHeight = 20,
    radius = 4,
    inset = 0,
    listItem = true,
    activeEdge = true,
    allowImplicitProtected = true,
}

local function CategorySelected(row)
    local texture = Field(row, "Texture")
    if Safety.Read(texture, "GetAtlas") ~= "Options_List_Active" then return false end
    local shown = Safety.Read(texture, "IsShown")
    return shown == nil or shown == true
end

local function SkinSettingsCategoryRow(state, row)
    if not state.active or NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled
        or not row or not CanTrack(row) then
        return false
    end
    -- The Settings ScrollBox dispatches its header and spacer Frame templates
    -- through the same initializer callback as actual category Buttons. Only
    -- SettingsCategoryListButtonTemplate owns this selection texture.
    local texture = Field(row, "Texture")
    if not texture then return false end
    NS.Cosmetics.Fade(texture, state.owner)
    Checkmarks.TrackButton(Field(row, "Toggle"), state.owner)
    local applied = NS.ControlSkin.ApplyButton(row, state.owner, SETTINGS_CATEGORY_SPEC)
    if applied then NS.Surface.SetActive(row, CategorySelected(row)) end
    return applied ~= nil
end

local function TrackSettingsButton(button, owner)
    return Checkmarks.TrackButton(button, owner)
end

local function TrackSettingsControlTree(state, root)
    if not state or not state.active or NS.IsCombatLocked() or not root then return false end
    return (WalkControlTree(root, state.owner, 4, 96, false, TrackSettingsButton))
end

-- ScrollBox:ForEachFrame passes only the row; the walked state rides along
-- here instead of in a closure per walk.
local walkingState

local function SkinWalkedCategoryRow(row)
    SkinSettingsCategoryRow(walkingState, row)
end

local function TrackWalkedControlRow(row)
    TrackSettingsControlTree(walkingState, row)
end

-- A row visit that raises is reported and the walked state is restored.
local function ForEachStateRow(state, scrollBox, visit)
    local previous = walkingState
    walkingState = state
    Safety.Dispatch(scrollBox.ForEachFrame, scrollBox, visit)
    walkingState = previous
end

local function RefreshSettingsCategories(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local scrollBox = state.scrollBox
    if type(Field(scrollBox, "ForEachFrame")) ~= "function" then return false end
    ForEachStateRow(state, scrollBox, SkinWalkedCategoryRow)
    return true
end

local function RefreshSettingsControls(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local scrollBox = state.settingsScrollBox
    if type(Field(scrollBox, "ForEachFrame")) ~= "function" then return false end
    ForEachStateRow(state, scrollBox, TrackWalkedControlRow)
    return true
end

local function RefreshSettingsTabs(state)
    if not state or not state.active or NS.IsCombatLocked() then
        return false
    end
    local panel = state.settingsPanel
    if not panel then return false end
    local changed = false
    for index = 1, #SETTINGS_TAB_KEYS do
        local tab = Field(panel, SETTINGS_TAB_KEYS[index])
        if tab and NS.ControlSkin.IsApplied(tab) then
            changed = NS.ControlSkin.Refresh(tab) == true or changed
        end
    end
    return changed
end

-- Callback registries pass the registration owner (the state) first.
local function OnCategoryChanged(state)
    RefreshSettingsCategories(state)
    -- Blizzard finishes DisplayCategory (including ScrollBox row
    -- initialization) before this event. Revisit the active rows so the
    -- very first Settings open receives the selected theme colors.
    RefreshSettingsControls(state)
    RefreshSettingsTabs(state)
end

local function OnTabSelected(state)
    RefreshSettingsTabs(state)
end

local function OnCategoryRowInitialized(state, row)
    SkinSettingsCategoryRow(state, row)
end

local function OnSettingsRowInitialized(state, row)
    TrackSettingsControlTree(state, row)
end

-- For the Settings panel's own callback registries (ScrollBoxes, tab group).
local function CanRegister(registry)
    return type(Field(registry, "RegisterCallback")) == "function"
end

local function CanUnregister(registry)
    return type(Field(registry, "UnregisterCallback")) == "function"
end

function Checkmarks.UntrackSettingsCategories(categoryList)
    local state = Checkmarks.settingsCategoryLists[categoryList]
    if not state then return false end
    state.active = false
    EventRegistry:UnregisterCallback(SETTINGS_CATEGORY_EVENT, state)
    if state.scrollRegistered and CanUnregister(state.scrollBox) then
        state.scrollBox:UnregisterCallback(state.scrollEvent, state)
    end
    if state.settingsScrollRegistered and CanUnregister(state.settingsScrollBox) then
        state.settingsScrollBox:UnregisterCallback(state.scrollEvent, state)
    end
    if state.tabRegistered and CanUnregister(state.tabGroup) then
        state.tabGroup:UnregisterCallback(state.tabEvent, state)
    end
    Checkmarks.settingsCategoryLists[categoryList] = nil
    local ownerSet = Checkmarks.owners[state.owner]
    if ownerSet then ownerSet[categoryList] = nil end
    return true
end

local function ResolveSettingsList(settingsPanel)
    return Getter(settingsPanel, "GetSettingsList")
        or Field(Field(settingsPanel, "Container"), "SettingsList")
end

-- TrackSettingsCategories has checked that the category ScrollBox takes
-- callbacks.
local function RegisterSettingsCallbacks(state)
    EventRegistry:RegisterCallback(SETTINGS_CATEGORY_EVENT, OnCategoryChanged, state)
    state.scrollBox:RegisterCallback(state.scrollEvent, OnCategoryRowInitialized, state)
    state.scrollRegistered = true
    local settingsScrollBox = state.settingsScrollBox
    if CanRegister(settingsScrollBox)
        and type(Field(settingsScrollBox, "ForEachFrame")) == "function" then
        settingsScrollBox:RegisterCallback(state.scrollEvent, OnSettingsRowInitialized, state)
        state.settingsScrollRegistered = true
    end
    if CanRegister(state.tabGroup) then
        state.tabGroup:RegisterCallback(state.tabEvent, OnTabSelected, state)
        state.tabRegistered = true
    end
end

function Checkmarks.TrackSettingsCategories(categoryList, owner, settingsPanel)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled or not categoryList
        or not CanTrack(categoryList) then
        return false
    end
    local scrollBox = Field(categoryList, "ScrollBox")
    if not CanRegister(scrollBox) or type(Field(scrollBox, "ForEachFrame")) ~= "function" then
        return false
    end
    local existing = Checkmarks.settingsCategoryLists[categoryList]
    if existing and existing.owner == owner then
        OnCategoryChanged(existing)
        return true
    elseif existing then
        Checkmarks.UntrackSettingsCategories(categoryList)
    end

    -- The row and tab events come from Blizzard_SharedXML (ScrollBox.lua,
    -- ButtonGroup.lua), loaded on Retail and Forever before any addon.
    local state = {
        owner = owner,
        categoryList = categoryList,
        scrollBox = scrollBox,
        scrollEvent = ScrollBoxListMixin.Event.OnInitializedFrame,
        settingsPanel = settingsPanel,
        active = true,
    }
    state.settingsScrollBox = Field(ResolveSettingsList(settingsPanel), "ScrollBox")
    state.tabGroup = Field(settingsPanel, "tabsGroup")
    state.tabEvent = ButtonGroupBaseMixin.Event.Selected
    RegisterSettingsCallbacks(state)

    Checkmarks.settingsCategoryLists[categoryList] = state
    local ownerSet = OwnerSet(owner)
    if ownerSet then ownerSet[categoryList] = true end
    OnCategoryChanged(state)
    return true
end

------------------------------------------------------------------ legacy dropdowns
local LEGACY_DROPDOWN_OWNER = "legacy-dropdown-menu"
local LEGACY_DROPDOWN_EVENT = "UIDropDownMenu.Show"

local LEGACY_DROPDOWN_SPEC = {
    role = "popup",
    radius = 6,
    inset = 0,
    maxDepth = 5,
    maxNodes = 260,
    menuPopup = true,
    legacyDropdown = true,
    registerDynamicRows = false,
    allowImplicitProtected = true,
}

function Checkmarks:OnLegacyDropdownShown(listFrame)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled or not listFrame then return end
    NS.GenericWindows.ApplyFrame(listFrame, LEGACY_DROPDOWN_OWNER, LEGACY_DROPDOWN_SPEC)
    Checkmarks.TrackFrame(listFrame, LEGACY_DROPDOWN_OWNER)
end

function Checkmarks.RegisterLegacyDropdowns()
    if Checkmarks.legacyRegistered then return true end
    EventRegistry:RegisterCallback(LEGACY_DROPDOWN_EVENT, Checkmarks.OnLegacyDropdownShown, Checkmarks)
    Checkmarks.legacyRegistered = true
    return true
end

local function Keys(set)
    local keys = {}
    for key in pairs(set) do keys[#keys + 1] = key end
    return keys
end

-- Releases every dropdown, every Settings list and the legacy dropdown skin
-- (part of Checkmarks.Restore).
function Checkmarks.ReleaseMenus()
    local dropdowns = Keys(Checkmarks.dropdowns)
    for index = 1, #dropdowns do Checkmarks.UntrackDropdown(dropdowns[index]) end
    local categoryLists = Keys(Checkmarks.settingsCategoryLists)
    for index = 1, #categoryLists do
        Checkmarks.UntrackSettingsCategories(categoryLists[index])
    end
    if Checkmarks.legacyRegistered then
        EventRegistry:UnregisterCallback(LEGACY_DROPDOWN_EVENT, Checkmarks)
    end
    Checkmarks.legacyRegistered = false
    NS.GenericWindows.Disable(LEGACY_DROPDOWN_OWNER)
end
