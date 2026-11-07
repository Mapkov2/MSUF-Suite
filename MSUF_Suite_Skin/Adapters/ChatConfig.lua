local _, NS = ...

-- The Mainline and Forever ChatConfigFrame use ChatTabArtTemplate for pooled
-- tabs and TooltipBorderBackdropTemplate for filter rows. The config owns
-- every click, selection and color swatch. The skin changes chrome and check tint.
local ChatConfigSkin = {}
NS.ChatConfigSkin = ChatConfigSkin

local Safety = NS.Safety
local Field, Read, Public = Safety.Field, Safety.Read, Safety.Public
local Kit = NS.AdapterKit
local Surface, Cosmetics, Checkmarks = NS.Surface, NS.Cosmetics, NS.Checkmarks

local REFRESH_KEY = "chat-config-skin"
local CATEGORY_COUNT = 7
local paneNames = {
    "ChatConfigCategoryFrame", "ChatConfigBackgroundFrame", "ChatConfigCombatSettingsFilters",
}
local filterGroups = {
    ChatConfigChatSettingsLeft = true, ChatConfigChannelSettingsLeft = true,
    ChatConfigOtherSettingsCombat = true, ChatConfigOtherSettingsPVP = true,
    ChatConfigOtherSettingsSystem = true, ChatConfigOtherSettingsCreature = true,
    ChatConfigTextToSpeechChannelSettingsLeft = true,
    CombatConfigMessageSourcesDoneBy = true, CombatConfigMessageSourcesDoneTo = true,
}
local tieredGroups = {
    CombatConfigMessageTypesLeft = true, CombatConfigMessageTypesRight = true, CombatConfigMessageTypesMisc = true,
}
local tabArt = {
    "Left", "Middle", "Right",
    "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}
local paneSpec = { role = "panel", radius = 4, inset = 0 }
local tabSpec = {
    role = "navigation", activeRole = "navigationActive", activeEdge = true,
    radius = 4, inset = 2, interactive = true,
}
local categorySpec = {
    role = "navigation", activeRole = "navigationActive", activeEdge = true,
    listItem = true, radius = 4, inset = 1, interactive = true,
}

local root, activeOwner, tabManager, hookedManager
local hookedGlobals = {}
local targets = Kit.WeakSet()

local function Attach(target, spec)
    if not Safety.CanCreateRegions(target) then return false end
    local surface = NS.Registry.GetSurface(target)
    if not surface or surface.visible == false or surface.spec ~= spec then
        if not Surface.Attach(target, spec) then return false end
    end
    targets[target] = true
    return true
end

local function FadeBackdrop(target)
    if Safety.CanDecorate(target) then
        Cosmetics.FadeNineSlice(Field(target, "NineSlice"), activeOwner)
    end
end

local function PaintCheckmark(texture)
    if texture and not Checkmarks.StillApplied(texture, activeOwner, "checkmark") then
        Checkmarks.TrackTexture(texture, activeOwner, "checkmark")
    end
end

local function PaintCheckButton(button)
    if not Public(button) or Read(button, "GetObjectType") ~= "CheckButton"
        or not Safety.CanDecorate(button) then return false end
    -- These two native states use file-based checkbox art, which the generic
    -- atlas scan cannot identify when the client exposes only a file ID.
    PaintCheckmark(Read(button, "GetCheckedTexture"))
    PaintCheckmark(Read(button, "GetDisabledCheckedTexture"))
    return true
end

local function PaintRows(...)
    for index = 1, select("#", ...) do
        local row = select(index, ...)
        if Public(row) and Safety.CanDecorate(row) and Field(row, "layoutType") == "TooltipDefaultLayout" then
            local check = Field(row, "CheckButton")
            if PaintCheckButton(check) then
                Cosmetics.FadeNineSlice(Field(row, "NineSlice"), activeOwner)
            end
        end
    end
end

local function PaintFilterGroup(group)
    FadeBackdrop(group)
    PaintRows(Safety.Call(group, "GetChildren"))
end

local function PaintChecks(...)
    for index = 1, select("#", ...) do PaintCheckButton(select(index, ...)) end
end

local function PaintTieredRow(row)
    if PaintCheckButton(row) then PaintChecks(Safety.Call(row, "GetChildren")) end
end

local function PaintTieredRows(...)
    for index = 1, select("#", ...) do PaintTieredRow(select(index, ...)) end
end

local function PaintTieredGroup(group)
    PaintTieredRows(Safety.Call(group, "GetChildren"))
end

local function PaintTabs()
    local tabs = Field(tabManager, "Tabs")
    if not Public(tabs) or type(tabs) ~= "table" then return end
    for index = 1, #tabs do
        local tab = tabs[index]
        local selectedArt = Public(tab) and not Safety.IsForbidden(tab) and Field(tab, "ActiveMiddle")
        if selectedArt and Read(tab, "IsShown") == true and Attach(tab, tabSpec) then
            -- FCFTab_UpdateColors changes the visible piece and repaints its
            -- vertex color, so restore the skin's alpha after each selection.
            for piece = 1, #tabArt do
                Cosmetics.Fade(Field(tab, tabArt[piece]), activeOwner)
            end
            Surface.SetActive(tab, Read(selectedArt, "IsShown") == true)
        end
    end
end

local function PaintCategories(selected)
    for index = 1, CATEGORY_COUNT do
        local button = _G["ChatConfigCategoryFrameButton" .. index]
        local locked = Read(button, "IsHighlightLocked")
        if selected then locked = selected == button end
        if type(locked) == "boolean" and Attach(button, categorySpec) then
            Cosmetics.Fade(Field(button, "Highlight"), activeOwner)
            Surface.SetActive(button, locked)
        end
    end
end

local function Refresh()
    if not activeOwner or NS.IsCombatLocked() or Kit.IsHidden(root) then return end
    for index = 1, #paneNames do
        local pane = _G[paneNames[index]]
        if Attach(pane, paneSpec) then FadeBackdrop(pane) end
    end
    for name in pairs(filterGroups) do PaintFilterGroup(_G[name]) end
    for name in pairs(tieredGroups) do PaintTieredGroup(_G[name]) end
    PaintTabs()
    PaintCategories()
end

local function CanRefresh()
    if not activeOwner or Kit.IsHidden(root) then return false end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(REFRESH_KEY, Refresh)
        return false
    end
    return true
end

local function OnSelectionUpdated(manager)
    if Public(manager) and manager == tabManager and CanRefresh() then Safety.Dispatch(PaintTabs) end
end

local function OnCategoryClicked(button)
    if Public(button) and CanRefresh() then Safety.Dispatch(PaintCategories, button) end
end

local function GroupName(group, groups)
    if not activeOwner or not Public(group) then return nil end
    local name = Read(group, "GetName")
    if groups[name] and _G[name] == group then return name end
end

local function OnFilterRowsChanged(group)
    if GroupName(group, filterGroups) and CanRefresh() then Safety.Dispatch(PaintFilterGroup, group) end
end

local function OnTieredGroupCreated(group)
    if GroupName(group, tieredGroups) and CanRefresh() then Safety.Dispatch(PaintTieredGroup, group) end
end

local function OnTieredRowChanged(group, index)
    local name = GroupName(group, tieredGroups)
    if name and Public(index) and type(index) == "number" and CanRefresh() then
        Safety.Dispatch(PaintTieredRow, _G[name .. "Checkbox" .. index])
    end
end

local configHooks = {
    ChatConfig_CreateCheckboxes = OnFilterRowsChanged,
    ChatConfig_UpdateCheckboxes = OnFilterRowsChanged,
    ChatConfig_CreateTieredCheckboxes = OnTieredGroupCreated,
    ChatConfig_UpdateTieredCheckboxes = OnTieredRowChanged,
    ChatConfigCategory_OnClick = OnCategoryClicked,
}

function ChatConfigSkin.Apply(frame, owner)
    if NS.IsCombatLocked() or not Safety.CanCreateRegions(frame) then return end
    root, activeOwner, tabManager = frame, owner, Field(frame, "ChatTabManager")
    if tabManager ~= hookedManager and Kit.HookFunction(tabManager, "UpdateSelection", OnSelectionUpdated) then
        hookedManager = tabManager
    end
    for name, callback in pairs(configHooks) do
        if not hookedGlobals[name] then hookedGlobals[name] = Kit.HookGlobal(name, callback) end
    end
    Refresh()
    return true
end

function ChatConfigSkin.Disable(owner)
    if activeOwner ~= owner then return end
    root, activeOwner, tabManager = nil, nil, nil
    NS.CombatGate.Cancel(REFRESH_KEY)
    for target in pairs(targets) do
        Surface.SetVisible(target, false)
        targets[target] = nil
    end
end

return ChatConfigSkin
