local _, NS = ...

-- Camelot loads Blizzard_GroupFinder_VanillaStyle on demand. Its LFGParentFrame
-- is a different window from Retail's PVEFrame. Keep Blizzard's role icons,
-- category IDs, result rows, scripts, and secure listing controls intact.
-- Mainline templates and native selection lifecycle checked against
-- Gethe/wow-ui-source forever e3ecc27b (1.60.1.70205).
local ForeverGroupFinder = {
    active = false,
    hooks = {},
    scrollBoxes = setmetatable({}, { __mode = "k" }),
    surfaces = setmetatable({}, { __mode = "k" }),
    selectionHooks = setmetatable({}, { __mode = "k" }),
    rows = setmetatable({}, { __mode = "k" }),
}
NS.ForeverGroupFinder = ForeverGroupFinder

local Safety = NS.Safety
local Kit = NS.AdapterKit

local ADDON = "Blizzard_GroupFinder_VanillaStyle"
local OWNER = "blizzardWindows:forever-group-finder"
ForeverGroupFinder.owner = OWNER
local ROOT_MODE = {
    role = "shell", maxDepth = 0, maxNodes = 1,
    childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}
local PANEL_MODE = {
    role = "panel", maxDepth = 0, maxNodes = 1,
    fillVisible = false, childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}
local CARD_SPEC = {
    role = "card", activeRole = "navigationActive", radius = 5,
    inset = 0, listItem = true, allowImplicitProtected = true,
    regions = { "Icon", "Cover", "HighlightTexture" },
}
local TAB_SPEC = {
    role = "navigation", activeRole = "navigationActive", radius = 4,
    inset = 0, allowImplicitProtected = true,
}
local RESULT_SPEC = {
    role = "card", activeRole = "navigationActive", radius = 4,
    inset = 0, listItem = true, allowImplicitProtected = true,
    regions = { "ResultBG", "Selected", "Highlight" },
}
local WHO_SPEC = {
    role = "card", activeRole = "navigationActive", radius = 4,
    inset = 0, listItem = true, allowImplicitProtected = true,
    regions = { "Background", "Selected" },
}
local FILTER_SPEC = {
    role = "button", radius = 4, inset = 1, allowImplicitProtected = true,
    regions = { "Background" },
}
local BUTTON_SPEC = {
    role = "button", radius = 4, inset = 1, allowImplicitProtected = true,
}
-- LargeSideTabButtonTemplate is a Frame, not a Button. It has no native
-- state-texture setters, so use the surface renderer for the background and
-- selection. Its native HIGHLIGHT layer retains mouseover (Surface's automatic
-- hover overlay applies only to Buttons).
local SIDE_TAB_SPEC = {
    role = "navigation", activeRole = "navigationActive", radius = 4,
    inset = 0, allowImplicitProtected = true,
}
local CONTENT_MODE = {
    rootSurface = false, maxDepth = 0, maxNodes = 1,
    childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}
local INPUT_MODE = {
    role = "input", radius = 4, maxDepth = 0, maxNodes = 1,
    childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}
local BROWSE_CONTROLS = {
    "CategoryDropdown", "ActivityDropdown", "RefreshButton", "SendMessageButton", "GroupInviteButton",
}
local LISTING_CONTROLS = { "BackButton", "PostButton" }
-- The role strip's background has no parentKey, so it is found by its atlas.
local ROLE_BACKGROUND_ATLAS = "groupfinder-roles-background"
local PORTRAIT_BACKGROUND_PATH = "interface\\framegeneral\\ui-background-rock"
local PANEL_TABS = { "Tab1", "Tab2", "Tab3" }
local MODE_TABS = { "ListingTab", "BrowsingTab", "WhoListingTab" }
local SkinLoadedWindow

local function RequestRefresh()
    if not ForeverGroupFinder.active then return end
    NS.CombatGate.RunOrDefer(OWNER .. ":refresh", SkinLoadedWindow)
end

-- Apply activates the adapter on Forever only.
local function Ready()
    return ForeverGroupFinder.active and not NS.IsCombatLocked()
        and NS.GenericWindows.IsCategoryEnabled("group")
end

local function Fade(region)
    if region and Safety.CanDecorate(region, true) then
        NS.Cosmetics.Fade(region, OWNER)
    end
end

-- Forever 1.60.1.70009 rebuilt the insets: LFGListingInsetTemplate and the
-- browse inset carry CustomBG plus a common-insideframe Border instead of
-- InsetFrameTemplate's Bg and NineSlice. Both shapes are faded.
local function FadeInset(inset)
    if not inset then return end
    Fade(inset.CustomBG)
    Fade(inset.Bg)
    Fade(inset.Border)
    NS.Cosmetics.FadeNineSlice(inset.NineSlice, OWNER)
end

-- Stone header and the two scroll lines above a result list.
local function FadeListChrome(frame)
    if not frame then return end
    Fade(frame.Bg)
    Fade(frame.BarTop)
    Fade(frame.BarMiddle)
end

local function FadeRoleRegions(...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Safety.Read(region, "GetAtlas") == ROLE_BACKGROUND_ATLAS then
            Fade(region)
        end
    end
end

local function FadeRoleBackground(roles)
    FadeRoleRegions(Safety.Call(roles, "GetRegions"))
end

local function SkinCategoryCards()
    if not Ready() then
        if NS.IsCombatLocked() then RequestRefresh() end
        return
    end
    local listing = _G.LFGListingFrame
    local view = listing and listing.CategoryView
    local buttons = view and view.CategoryButtons
    if not buttons then return end
    for index = 1, #buttons do
        local button = buttons[index]
        if button and button.Icon and button.Cover and button.Label
            and Safety.CanCreateRegions(button, true) then
            NS.ControlSkin.ApplyButton(button, OWNER, CARD_SPEC)
        end
    end
end

local function SkinButton(button, spec)
    if not button or not Safety.CanCreateRegions(button, true) then return end
    -- These verified controls carry their semantic icon separately (Icon).
    -- ControlSkin replaces hover/pressed/disabled art, but not normal art.
    local normal = Safety.Call(button, "GetNormalTexture")
    if NS.ControlSkin.ApplyButton(button, OWNER, spec or BUTTON_SPEC) then Fade(normal) end
end

local function SyncSelection(frame, region, selectionBehavior)
    -- Browse's pool reset only hides the parent: Selected can still describe
    -- the previous result. The native model is keyed by current elementData.
    local selected = Safety.Read(selectionBehavior, "IsSelected", frame)
    if type(selected) ~= "boolean" then selected = Safety.Read(region, "IsShown") == true end
    NS.Surface.SetActive(frame, selected)
end

local function OnSelectionChanged(frame)
    if not ForeverGroupFinder.rows[frame] and not ForeverGroupFinder.surfaces[frame] then return end
    if not Ready() then
        if NS.IsCombatLocked() then RequestRefresh() end
        return
    end
    SyncSelection(frame, frame.Selected or frame.SelectedTexture, ForeverGroupFinder.rows[frame])
end

local function HookSelection(frame, method)
    if ForeverGroupFinder.selectionHooks[frame] then return end
    if Kit.HookFunction(frame, method, Safety.Isolated(OnSelectionChanged)) then
        ForeverGroupFinder.selectionHooks[frame] = true
    end
end

-- A post-hook on Blizzard's global: the card pass is its own error boundary,
-- so a raising pass never reaches Blizzard's caller.
local function OnCategoryButtonsUpdated()
    Safety.Dispatch(SkinCategoryCards)
end

local function SkinResultRow(row, kind, selectionBehavior)
    if not Ready() then
        if NS.IsCombatLocked() then RequestRefresh() end
        return
    end
    if not row or not Safety.CanCreateRegions(row, true) then return end
    if kind == "activity" and row.NameButton and row.CheckButton then
        NS.Checkmarks.TrackFrame(row, OWNER)
        NS.Checkmarks.TrackFrame(row.CheckButton, OWNER)
        NS.Checkmarks.TrackFrame(row.ExpandOrCollapseButton, OWNER)
        return
    end
    if kind == "browse" and row.ResultBG and (row.Name or row.CategoryLabel) then
        NS.ControlSkin.ApplyButton(row, OWNER, RESULT_SPEC)
        SkinButton(Kit.Path(row, "DataDisplay", "DelistButton"))
    elseif kind == "who" and row.Background and row.Name then
        NS.ControlSkin.ApplyButton(row, OWNER, WHO_SPEC)
        SkinButton(row.InviteButton)
        HookSelection(row, "SetSelected")
    else
        return
    end
    ForeverGroupFinder.rows[row] = selectionBehavior or true
    SyncSelection(row, row.Selected, selectionBehavior)
end

-- One registration per list, built once: CallbackRegistry passes it first.
local function OnRowInitialized(registration, row)
    SkinResultRow(row, registration.kind, registration.selectionBehavior)
end

local function RegisterRows(scrollBox, kind, selectionBehavior)
    if not scrollBox then return end
    local registration = ForeverGroupFinder.scrollBoxes[scrollBox]
    if not registration then
        registration = { kind = kind }
        registration.visit = function(row)
            SkinResultRow(row, registration.kind, registration.selectionBehavior)
        end
        registration.event = Kit.RegisterRowCallback(scrollBox, Safety.Isolated(OnRowInitialized), registration)
        if not registration.event then return end
        ForeverGroupFinder.scrollBoxes[scrollBox] = registration
    end
    registration.selectionBehavior = selectionBehavior
    -- ForEachRow waits for the list view Blizzard builds on initialization.
    Kit.ForEachRow(scrollBox, registration.visit)
end

local function SkinFrame(frame, mode)
    if frame and Safety.CanCreateRegions(frame, true) then
        NS.GenericWindows.ApplyFrame(frame, OWNER, mode)
    end
end

local function FadePortraitBackground(region, expectedName)
    if Safety.Read(region, "GetName") == expectedName then
        Fade(region)
        return
    end
    local path = Safety.Read(region, "GetTextureFilePath") or Safety.Read(region, "GetTexture")
    if type(path) == "string" and path:lower():gsub("/", "\\") == PORTRAIT_BACKGROUND_PATH then
        Fade(region)
    end
end

local function SkinPortraitPanel(frame)
    if not frame then return end
    SkinFrame(frame, PANEL_MODE)
    -- Browse redeclares $parentBg/Bg for its stone header. The inherited
    -- PortraitFrame background may remain a direct region after its member
    -- is displaced, above the shell's BACKGROUND -7 fill. Match only this
    -- source-verified name/file, including inherited regions without a key.
    local name = Safety.Read(frame, "GetName")
    Kit.ForEachRegion(frame, FadePortraitBackground, type(name) == "string" and name .. "Bg" or false)
end

local function SkinPanels(listing, browse, who)
    SkinPortraitPanel(listing)
    SkinPortraitPanel(browse)
    SkinPortraitPanel(who)

    FadeRoleBackground(listing.RolesSection)
    FadeInset(listing.Inset)
    Fade(listing.DividerFrame and listing.DividerFrame.Divider)
    FadeListChrome(listing.ActivityView)
    Fade(browse.BackgroundArt)
    FadeListChrome(browse)
    FadeInset(browse.Inset)
    if who then
        Fade(who.BackgroundArt)
        Fade(who.headerBackground)
        Fade(who.insideFrame)
        FadeListChrome(who)
        SkinButton(who.FilterDropdown, FILTER_SPEC)
    end
end

local function SkinControls(listing, browse, who)
    for index = 1, #BROWSE_CONTROLS do
        local key = BROWSE_CONTROLS[index]
        SkinButton(browse[key], key:find("Dropdown", 1, true) and FILTER_SPEC or BUTTON_SPEC)
    end
    for index = 1, #LISTING_CONTROLS do SkinButton(listing[LISTING_CONTROLS[index]]) end
    SkinButton(Kit.Path(listing, "GroupRoleButtons", "RolePollButton"))
    SkinButton(Kit.Path(listing, "GroupRoleButtons", "RoleDropdown"), FILTER_SPEC)
    SkinButton(who and who.WhoSearch)
    local activity = listing.ActivityView
    if not activity then return end
    SkinFrame(activity, CONTENT_MODE)
    SkinButton(activity.PlayStyleDropdown, FILTER_SPEC)
    NS.Checkmarks.TrackFrame(Kit.Path(activity, "LevelRangesCheckbox", "Checkbox"), OWNER)
    -- Paint the input container; Blizzard's secure EditBox and its text/paste
    -- restrictions remain under the native input-scrollframe lifecycle.
    SkinFrame(activity.Comment, INPUT_MODE)
    RegisterRows(activity.ScrollBox, "activity")
end

local function SkinTabs(parent)
    for index = 1, #PANEL_TABS do
        local tab = parent[PANEL_TABS[index]]
        if tab and Safety.CanCreateRegions(tab, true) then
            NS.ControlSkin.ApplyTab(tab, OWNER, TAB_SPEC)
        end
    end
    for index = 1, #MODE_TABS do
        local tab = parent[MODE_TABS[index]]
        if tab and Kit.Ensure(ForeverGroupFinder, tab, SIDE_TAB_SPEC) then
            Fade(tab.Background)
            Fade(tab.SelectedTexture)
            if tab.TabGlow then NS.Cosmetics.SuppressVertexAlpha(tab.TabGlow, OWNER) end
            SyncSelection(tab, tab.SelectedTexture)
            HookSelection(tab, "SetChecked")
        end
    end
end

local function InstallHooks()
    local hooks = ForeverGroupFinder.hooks
    if not hooks.category then
        hooks.category = Kit.HookGlobal("LFGListingCategorySelection_UpdateCategoryButtons", OnCategoryButtonsUpdated)
    end
    if not hooks.selection then
        hooks.selection = Kit.HookGlobal("LFGBrowseSearchEntry_SetSelection", Safety.Isolated(OnSelectionChanged))
    end
end

SkinLoadedWindow = function()
    if not Ready() then return false, "combat" end
    local parent = _G.LFGParentFrame
    local listing = _G.LFGListingFrame
    local browse = _G.LFGBrowseFrame
    if not parent or not listing or not browse then return false, "missing" end
    local who = _G.LFGWhoListFrame
    SkinFrame(parent, ROOT_MODE)
    SkinPanels(listing, browse, who)
    SkinControls(listing, browse, who)
    SkinTabs(parent)
    SkinCategoryCards()
    RegisterRows(browse.ScrollBox, "browse", browse.selectionBehavior)
    RegisterRows(who and who.ScrollBox, "who", who and who.selectionBehavior)

    InstallHooks()
    return true, "applied"
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", Safety.Isolated(function(_, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= ADDON then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")
    if not ForeverGroupFinder.active then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(OWNER .. ":load", SkinLoadedWindow)
    else
        SkinLoadedWindow()
    end
end))

function ForeverGroupFinder.Apply()
    -- Blizzard_GroupFinder_VanillaStyle ships with Forever only.
    if not NS.Client.isForever then return true, "disabled" end
    if not NS.GenericWindows.IsCategoryEnabled("group") then
        ForeverGroupFinder.Disable()
        return true, "disabled"
    end
    ForeverGroupFinder.active = true
    -- Waiting for Blizzard's native load needs no paint or protected writes.
    -- Register even in combat, so a load after combat ends is still observed.
    if not _G.LFGParentFrame then
        if NS.Client.HasAddOn(ADDON) == false then return true, "unavailable" end
        eventFrame:RegisterEvent("ADDON_LOADED")
        return true, "waiting"
    end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(OWNER .. ":apply", SkinLoadedWindow)
        return true, "waiting"
    end
    return SkinLoadedWindow()
end

function ForeverGroupFinder.Disable()
    ForeverGroupFinder.active = false
    eventFrame:UnregisterEvent("ADDON_LOADED")
    NS.CombatGate.Cancel(OWNER .. ":load")
    NS.CombatGate.Cancel(OWNER .. ":apply")
    NS.CombatGate.Cancel(OWNER .. ":refresh")
    for scrollBox, registration in pairs(ForeverGroupFinder.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, registration.event, registration)
        ForeverGroupFinder.scrollBoxes[scrollBox] = nil
    end
    for frame in pairs(ForeverGroupFinder.surfaces) do NS.Surface.SetVisible(frame, false) end
    return NS.GenericWindows.Disable(OWNER)
end

return ForeverGroupFinder
