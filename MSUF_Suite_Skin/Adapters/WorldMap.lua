local _, NS = ...

-- Purpose-built World Map and Quest Log chrome. The implementation is based
-- on Gethe/wow-ui-source upstream/live 31c7f7b9c:
--
--   Blizzard_WorldMap/Blizzard_WorldMap.xml and .lua
--   Blizzard_WorldMap/Blizzard_WorldMapTemplates.xml and .lua
--   Blizzard_MapCanvas/Blizzard_MapCanvas.xml and .lua
--   Blizzard_UIPanels_Game/Mainline/QuestMapFrame.xml
--   Blizzard_FrameXML/Mainline/NavigationBar.xml and .lua
--
-- Map tiles, pins, exploration overlays, quest icons and other semantic map
-- content are intentionally never recolored or hidden. Only exact chrome,
-- navigation controls and quest-panel materials are replaced.

local WorldMapSkin = {
    overlayLimit = 32,
    navButtonLimit = 16,
}
NS.WorldMapSkin = WorldMapSkin

local Field = NS.Safety.Field
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade
local FadeFields = Kit.FadeFields
local Attach = Kit.Attach
local SkinControl = Kit.SkinControl

local SHOW_CALLBACK = "WorldMapOnShow"
local DISPLAY_MODE_CALLBACK = "QuestLog.SetDisplayMode"

local frameStates = setmetatable({}, { __mode = "k" })
local activeFrames = setmetatable({}, { __mode = "k" })
local callbacksRegistered = false

local SHELL_SPEC = { role = "shell", radius = 8, inset = 0 }
local TITLE_SPEC = { role = "navigation", radius = 6, inset = 0 }
local NAV_BAR_SPEC = { role = "navigation", radius = 6, inset = 0 }
local TAB_SPEC = { role = "navigation", radius = 6, inset = 2 }
local ACTIVE_TAB_SPEC = { role = "navigationActive", radius = 6, inset = 2 }
-- QuestMapFrame and its display-mode children are full-area wrappers over
-- the WorldMap shell. Their native parchment is faded, but another material
-- fill at every level would compound Glass back to near-opaque.
local QUEST_LOG_SPEC = { role = "panel", radius = 8, inset = 0, fillVisible = false }
local QUEST_PANEL_SPEC = { role = "panel", radius = 6, inset = 0, fillVisible = false }
local STORY_SPEC = { role = "card", radius = 4, inset = 1, listItem = true }
local REWARDS_SPEC = { role = "card", radius = 4, inset = 0 }

local WINDOW_BUTTON_SPEC = { role = "button", radius = 4, inset = 2 }
local NAV_BUTTON_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    radius = 6,
    pillHeight = 24,
    inset = 1,
    regions = { "selected" },
}
local MENU_ARROW_SPEC = { role = "button", radius = 4, pillHeight = 20, inset = 4 }
local OVERFLOW_SPEC = { role = "button", radius = 4, inset = 3 }
local OVERLAY_SPEC = {
    role = "button",
    radius = 6,
    pillHeight = 24,
    inset = 2,
    regions = { "Background", "Border" },
}
local SIDE_TOGGLE_SPEC = { role = "button", radius = 6, inset = 2 }

local QUEST_LOG_MODE = {
    role = "panel",
    rootSurface = false,
    childSurfaces = false,
    maxDepth = 6,
    maxNodes = 420,
    allowImplicitProtected = true,
}

local BORDER_FRAME_ART = { "Border", "TopDetail", "Shadow" }
local QUEST_TABS = { "QuestsTab", "EventsTab", "MapLegendTab" }
local NAV_BAR_INSET_BORDERS = {
    "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
    "InsetBorderLeft", "InsetBorderRight",
}

local function SkinNavButton(state, button, active)
    -- The active flag is copied by ControlSkin before this shared spec changes.
    NAV_BUTTON_SPEC.active = active
    SkinControl(state, button, NAV_BUTTON_SPEC)
    NAV_BUTTON_SPEC.active = nil
    -- NavButtonTemplate's tiled normal texture is anonymous and otherwise
    -- remains above the replacement material. Arrow and menu glyph textures
    -- are separate and remain semantic.
    Fade(state, NS.Safety.Call(button, "GetNormalTexture"))
    SkinControl(state, Field(button, "MenuArrowButton"), MENU_ARROW_SPEC)
end

local function SkinNavBar(state, navBar)
    if not navBar then return end

    Attach(state, navBar, NAV_BAR_SPEC)
    Kit.FadeNativeTextures(state, navBar)
    Kit.FadeNativeTextures(state, Field(navBar, "overlay"))
    FadeFields(state, navBar, NAV_BAR_INSET_BORDERS)

    local list = Field(navBar, "navList")
    if type(list) == "table" then
        for index = 1, math.min(#list, WorldMapSkin.navButtonLimit) do
            local button = list[index]
            if button then SkinNavButton(state, button, index == #list) end
        end
    end

    local overflow = Field(navBar, "overflow") or Field(navBar, "overflowButton")
    if overflow then
        SkinControl(state, overflow, OVERFLOW_SPEC)
        Fade(state, NS.Safety.Call(overflow, "GetNormalTexture"))
    end
end

local function SkinOverlayControls(state, frame)
    local overlays = Field(frame, "overlayFrames")
    if type(overlays) == "table" then
        local navBar = Field(frame, "NavBar")
        for index = 1, math.min(#overlays, WorldMapSkin.overlayLimit) do
            local control = overlays[index]
            local objectType = control ~= navBar and Kit.ObjectType(control)
            if objectType == "Button" or objectType == "DropdownButton" then
                SkinControl(state, control, OVERLAY_SPEC)
            end
        end
    end

    local sideToggle = Field(frame, "SidePanelToggle")
    if sideToggle then
        SkinControl(state, Field(sideToggle, "OpenButton"), SIDE_TOGGLE_SPEC)
        SkinControl(state, Field(sideToggle, "CloseButton"), SIDE_TOGGLE_SPEC)
    end
end

local function SkinQuestTabs(state, questLog)
    local displayMode = Field(questLog, "displayMode")
    for index = 1, #QUEST_TABS do
        local tab = Field(questLog, QUEST_TABS[index])
        if tab then
            local active = displayMode ~= nil and Field(tab, "displayMode") == displayMode
            Attach(state, tab, active and ACTIVE_TAB_SPEC or TAB_SPEC)
            FadeFields(state, tab, { "Background", "SelectedTexture" })
        end
    end
end

local function SkinQuestLog(state, questLog)
    if not questLog then return end

    NS.GenericWindows.ApplyFrame(questLog, state.owner, QUEST_LOG_MODE)
    Attach(state, questLog, QUEST_LOG_SPEC)
    Fade(state, Field(questLog, "VerticalSeparator"))
    SkinQuestTabs(state, questLog)

    local quests = Field(questLog, "QuestsFrame")
    local scroll = Field(quests, "ScrollFrame")
    local details = Field(quests, "DetailsFrame")
    local campaign = Field(quests, "CampaignOverview")
    local story = Path(scroll, "Contents", "StoryHeader")
    local rewards = Path(details, "RewardsFrameContainer", "RewardsFrame")
    local events = Field(questLog, "EventsFrame")
    local legend = Field(questLog, "MapLegend")

    Attach(state, quests, QUEST_PANEL_SPEC)
    Attach(state, details, QUEST_PANEL_SPEC)
    Attach(state, events, QUEST_PANEL_SPEC)
    Attach(state, legend, QUEST_PANEL_SPEC)
    Attach(state, story, STORY_SPEC)
    Attach(state, rewards, REWARDS_SPEC)

    FadeFields(state, scroll, { "Background", "Edge" })
    FadeFields(state, Field(scroll, "BorderFrame"), BORDER_FRAME_ART)
    FadeFields(state, story, { "Background", "Divider" })
    FadeFields(state, details, { "Bg", "SealMaterialBG" })
    FadeFields(state, Field(details, "BorderFrame"), BORDER_FRAME_ART)
    Kit.FadeNativeTextures(state, Field(details, "BackFrame"))
    FadeFields(state, rewards, { "Background", "Bottom", "Top" })
    Fade(state, Field(campaign, "BG"))
    FadeFields(state, Field(campaign, "BorderFrame"), BORDER_FRAME_ART)
    FadeFields(state, Field(campaign, "ScrollFrame"), { "TopShadow", "BottomShadow" })
    FadeFields(state, Field(events, "ScrollBox"), { "Background" })
    FadeFields(state, Field(events, "BorderFrame"), BORDER_FRAME_ART)
    Kit.FadeNativeTextures(state, events)
    FadeFields(state, Field(legend, "ScrollFrame"), { "Background", "Edge" })
    FadeFields(state, Field(legend, "BorderFrame"), BORDER_FRAME_ART)
    Fade(state, Path(questLog, "QuestSessionManagement", "BG"))
end

local function SkinFrame(frame, state)
    if not frame or NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety.CanDecorate(frame, true) then return false, "protected-frame" end
    if not Attach(state, frame, SHELL_SPEC) then return false, "shell-failed" end
    Attach(state, Field(frame, "TitleCanvasSpacerFrame"), TITLE_SPEC)

    local border = Field(frame, "BorderFrame")
    FadeFields(state, border, { "Bg", "TopTileStreaks", "InsetBorderTop", "Underlay" })
    Kit.FadeNineSlice(state, Field(border, "NineSlice"))

    SkinControl(state, Field(border, "CloseButton"), WINDOW_BUTTON_SPEC)
    local maxMin = Field(border, "MaximizeMinimizeFrame")
    SkinControl(state, Field(maxMin, "MaximizeButton"), WINDOW_BUTTON_SPEC)
    SkinControl(state, Field(maxMin, "MinimizeButton"), WINDOW_BUTTON_SPEC)

    SkinNavBar(state, Field(frame, "NavBar"))
    SkinOverlayControls(state, frame)
    SkinQuestLog(state, Field(frame, "QuestLog"))
    return true
end

function WorldMapSkin:OnWorldMapShown()
    if NS.IsCombatLocked() then return end
    for frame, state in pairs(activeFrames) do
        if state.active then SkinFrame(frame, state) end
    end
end

function WorldMapSkin:OnQuestLogModeChanged()
    if NS.IsCombatLocked() then return end
    for frame, state in pairs(activeFrames) do
        if state.active then SkinQuestLog(state, Field(frame, "QuestLog")) end
    end
end

local function RegisterCallbacks()
    if callbacksRegistered then return end
    callbacksRegistered = Kit.RegisterEventCallback(SHOW_CALLBACK,
        WorldMapSkin.OnWorldMapShown, WorldMapSkin)
    if callbacksRegistered then
        Kit.RegisterEventCallback(DISPLAY_MODE_CALLBACK, WorldMapSkin.OnQuestLogModeChanged, WorldMapSkin)
    end
end

local function UnregisterCallbacksIfIdle()
    if not callbacksRegistered or next(activeFrames) ~= nil then return end
    callbacksRegistered = false
    Kit.UnregisterEventCallback(SHOW_CALLBACK, WorldMapSkin)
    Kit.UnregisterEventCallback(DISPLAY_MODE_CALLBACK, WorldMapSkin)
end

function WorldMapSkin.Apply(frame, owner)
    frame = frame or _G.WorldMapFrame
    owner = owner or "worldMap"
    if not frame then return false, "missing-frame" end
    if NS.IsCombatLocked() then return false, "combat" end

    local state = frameStates[frame]
    if not state then
        state = { surfaces = Kit.WeakSet() }
        frameStates[frame] = state
    end
    state.owner = owner
    state.active = true
    activeFrames[frame] = state

    local applied, reason = SkinFrame(frame, state)
    if not applied then
        state.active = false
        activeFrames[frame] = nil
        return false, reason
    end
    RegisterCallbacks()
    if NS.QuestText then NS.QuestText.Activate(frame, owner) end
    return true
end

function WorldMapSkin.Disable(frame, owner)
    frame = frame or _G.WorldMapFrame
    owner = owner or "worldMap"
    if not frame then return false, "missing-frame" end
    if NS.IsCombatLocked() then return false, "combat" end

    local state = frameStates[frame]
    if state then
        state.active = false
        activeFrames[frame] = nil
    end

    NS.GenericWindows.Disable(owner)

    if state then
        if NS.QuestText then NS.QuestText.Deactivate(frame, owner) end
        Kit.HideSurfaces(state)
    end
    UnregisterCallbacksIfIdle()
    return true
end
