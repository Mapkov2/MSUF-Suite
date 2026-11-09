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

local Safety = NS.Safety
local Field = Safety.Field
local Dispatch = Safety.Dispatch
local Kit = NS.AdapterKit
local Fade = Kit.Fade
local FadeFields = Kit.FadeFields
local Attach = Kit.Attach
local SkinControl = Kit.SkinControl

local SHOW_CALLBACK = "WorldMapOnShow"
local DISPLAY_MODE_CALLBACK = "QuestLog.SetDisplayMode"

local frameStates = setmetatable({}, { __mode = "k" })
local activeFrames = setmetatable({}, { __mode = "k" })
local callbacksRegistered = false
local questLogUpdateHooked = false

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
local QUEST_SEARCH_SPEC = {
    role = "input", radius = 6, inset = 0, pillHeight = 28,
    useControlShape = true, allowImplicitProtected = true,
}
local QUEST_COUNT_ART = { "Left", "Middle", "Right" }
local QUEST_HOVER_MATERIAL = { opacity = "control" }
local questHovers = Kit.WeakSet()
local hoverListening = false

-- Native QuestMapLogTitleButton_OnEnter owns the tooltip, map pin highlight
-- and difficulty colors. Add only a soft full-row plate beneath that content;
-- never replace the native scripts or read quest data into a second tooltip.
local function PaintQuestHover(row)
    local record = questHovers[row]
    if not record then return end
    if not Safety.CanDecorate(row, true) then
        if NS.IsCombatLocked() then NS.CombatGate.RunOrDefer(record.key, record.repaint) end
        return
    end
    local theme = NS.DB.theme
    if theme.hoverStyle == "off" then
        if record.suppressed then NS.Cosmetics.Restore(record.highlight, record.state.owner) end
        record.suppressed = false
    elseif record.state.active and not record.suppressed then
        Fade(record.state, record.highlight)
        record.suppressed = true
    end
    local visible = record.state.active and theme.hoverStyle ~= "off"
        and Safety.Read(row, "IsVisible") == true
        and (Safety.Read(row, "IsMouseOver") == true or Safety.Read(record.highlight, "IsShown") == true)
    if visible then
        local r, g, b, a = NS.Theme.GetColor("hover")
        local opacity = NS.Theme.GetMaterialOpacity(QUEST_HOVER_MATERIAL)
        record.fill:SetColorTexture(r, g, b, a * 0.22 * (theme.hoverIntensity or 1) * opacity)
    end
    visible = visible == true
    if visible ~= record.visible then
        record.fill:SetShown(visible)
        record.visible = visible
    end
end

local function RefreshQuestHovers()
    for row in pairs(questHovers) do PaintQuestHover(row) end
end

local function OnQuestHoverTheme(_, domain)
    if domain == "color" or domain == "theme" or domain == "profile" or domain == "appearance" then
        RefreshQuestHovers()
    end
end

local function EnsureQuestHover(row, state)
    local record = questHovers[row]
    if record and record.state == state and record.enabled then
        PaintQuestHover(row)
        return
    end
    local highlight = Field(row, "HighlightTexture")
    if not highlight or not Safety.CanDecorate(row, true) then return end
    if not record then
        local fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetAllPoints(row)
        fill:Hide()
        record = { fill = fill, highlight = highlight, visible = false, key = "world-map-quest-hover:" .. tostring(row) }
        record.repaint = function() PaintQuestHover(row) end
        questHovers[row] = record
        row:HookScript("OnEnter", PaintQuestHover)
        row:HookScript("OnLeave", PaintQuestHover)
        row:HookScript("OnHide", PaintQuestHover)
        row:HookScript("OnShow", PaintQuestHover)
    end
    record.state = state
    record.enabled = true
    -- Blizzard shows this yellow glow explicitly, independently of the
    -- button's GetHighlightTexture. Restore it with the adapter's owner.
    Fade(state, highlight)
    record.suppressed = true
    PaintQuestHover(row)
    if not hoverListening then
        NS.Registry.AddListener(WorldMapSkin, OnQuestHoverTheme)
        hoverListening = true
    end
end

local function SkinQuestSearch(state, scroll)
    local search = Field(scroll, "SearchBox")
    if search then NS.ControlSkin.ApplySearchBox(search, state.owner, QUEST_SEARCH_SPEC) end
    SkinControl(state, Field(scroll, "SettingsDropdown"), OVERFLOW_SPEC)
    local count = Field(_G, "QuestLogCount")
    if count and Safety.Read(count, "GetParent") == scroll then FadeFields(state, count, QUEST_COUNT_ART) end
end

local QUEST_LOG_MODE = {
    role = "panel",
    rootSurface = false,
    childSurfaces = false,
    maxDepth = 6,
    maxNodes = 420,
    allowImplicitProtected = true,
}

-- Quest log rows come from QuestScrollFrame's pools, which only
-- QuestLogQuests_Update fills (Blizzard_UIPanels_Game QuestMapFrame.lua,
-- Retail and Forever). The rows sit four levels below the quest log, so a
-- row keeps QUEST_LOG_MODE's depth with two levels of its own.
local QUEST_ROW_POOLS = {
    "titleFramePool", "objectiveFramePool", "headerFramePool",
    "campaignHeaderFramePool", "campaignHeaderMinimalFramePool",
    "covenantCallingsHeaderFramePool",
}
local QUEST_ROW_LIMIT = 256
local QUEST_ROW_MODE = {
    role = "panel",
    rootSurface = false,
    childSurfaces = false,
    maxDepth = 2,
    maxNodes = 60,
    allowImplicitProtected = true,
}

local BORDER_FRAME_ART = { "Border", "TopDetail", "Shadow" }
local QUEST_TABS = { "QuestsTab", "EventsTab", "MapLegendTab" }
local NAV_BAR_INSET_BORDERS = {
    "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
    "InsetBorderLeft", "InsetBorderRight",
}
local WINDOW_BORDER_ART = { "Bg", "TopTileStreaks", "InsetBorderTop", "Underlay" }
local QUEST_TAB_ART = { "Background", "SelectedTexture" }
local SCROLL_ART = { "Background", "Edge" }
local STORY_ART = { "Background", "Divider" }
local DETAILS_ART = { "Bg", "SealMaterialBG" }
local REWARDS_ART = { "Background", "Bottom", "Top" }
local CAMPAIGN_SCROLL_ART = { "TopShadow", "BottomShadow" }
local EVENTS_SCROLL_ART = { "Background" }

local function SkinNavButton(state, button, active)
    -- The active flag is copied by ControlSkin before this shared spec changes.
    NAV_BUTTON_SPEC.active = active
    SkinControl(state, button, NAV_BUTTON_SPEC)
    NAV_BUTTON_SPEC.active = nil
    -- NavButtonTemplate's tiled normal texture is anonymous and otherwise
    -- remains above the replacement material. Arrow and menu glyph textures
    -- are separate and remain semantic.
    Fade(state, Safety.Call(button, "GetNormalTexture"))
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
        Fade(state, Safety.Call(overflow, "GetNormalTexture"))
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
            FadeFields(state, tab, QUEST_TAB_ART)
        end
    end
end

-- Row visitors: callback(row, state, generation) for Kit.ForEachActive.
-- questRows maps each pooled row to the skin generation of its node pass.
-- Only rows within the quest log pass's depth took that pass; the caller
-- skips marking when its node limit cut the pass short.
local function MarkQuestRow(row, state, generation)
    EnsureQuestHover(row, state)
    NS.WorldMapQuests.PaintRow(row, state)
    if Kit.IsDescendantOf(row, state.questLog, QUEST_LOG_MODE.maxDepth) then
        state.questRows[row] = generation
    end
end

-- QuestLogQuests_Update repaints every reused title in Blizzard's quest
-- colors, so a row with its pass only has its gold text tracked again.
local function SkinQuestRow(row, state, generation)
    EnsureQuestHover(row, state)
    NS.WorldMapQuests.PaintRow(row, state)
    if state.questRows[row] == generation then
        NS.GenericWindows.RefreshDescendant(row, state.owner, QUEST_ROW_MODE)
        return
    end
    state.questRows[row] = generation
    NS.GenericWindows.ApplyDescendant(row, state.owner, QUEST_ROW_MODE)
end

-- Bounded and allocation-free: Blizzard's pools enumerate their active rows.
local function VisitQuestRows(state, questLog, visit)
    local scroll = Field(Field(questLog, "QuestsFrame"), "ScrollFrame")
    if not scroll then return end
    local generation = Kit.SkinGeneration()
    local budget = QUEST_ROW_LIMIT
    for index = 1, #QUEST_ROW_POOLS do
        if budget <= 0 then return end
        budget = budget - Kit.ForEachActive(Field(scroll, QUEST_ROW_POOLS[index]), budget,
            visit, state, generation)
    end
end

local function SkinQuestLog(state, questLog)
    if not questLog then return end

    local applied, _, metrics = NS.GenericWindows.ApplyFrame(questLog, state.owner, QUEST_LOG_MODE)
    if applied and metrics and not metrics.nodeLimited then
        state.questLog = questLog
        VisitQuestRows(state, questLog, MarkQuestRow)
    end
    Attach(state, questLog, QUEST_LOG_SPEC)
    Fade(state, Field(questLog, "VerticalSeparator"))
    SkinQuestTabs(state, questLog)

    local quests = Field(questLog, "QuestsFrame")
    local scroll = Field(quests, "ScrollFrame")
    SkinQuestSearch(state, scroll)
    local details = Field(quests, "DetailsFrame")
    local campaign = Field(quests, "CampaignOverview")
    local story = Kit.Path(scroll, "Contents", "StoryHeader")
    local rewards = Kit.Path(details, "RewardsFrameContainer", "RewardsFrame")
    local events = Field(questLog, "EventsFrame")
    local legend = Field(questLog, "MapLegend")

    Attach(state, quests, QUEST_PANEL_SPEC)
    Attach(state, details, QUEST_PANEL_SPEC)
    Attach(state, events, QUEST_PANEL_SPEC)
    Attach(state, legend, QUEST_PANEL_SPEC)
    Attach(state, story, STORY_SPEC)
    Attach(state, rewards, REWARDS_SPEC)

    FadeFields(state, scroll, SCROLL_ART)
    FadeFields(state, Field(scroll, "BorderFrame"), BORDER_FRAME_ART)
    FadeFields(state, story, STORY_ART)
    FadeFields(state, details, DETAILS_ART)
    FadeFields(state, Field(details, "BorderFrame"), BORDER_FRAME_ART)
    Kit.FadeNativeTextures(state, Field(details, "BackFrame"))
    FadeFields(state, rewards, REWARDS_ART)
    Fade(state, Field(campaign, "BG"))
    FadeFields(state, Field(campaign, "BorderFrame"), BORDER_FRAME_ART)
    FadeFields(state, Field(campaign, "ScrollFrame"), CAMPAIGN_SCROLL_ART)
    FadeFields(state, Field(events, "ScrollBox"), EVENTS_SCROLL_ART)
    FadeFields(state, Field(events, "BorderFrame"), BORDER_FRAME_ART)
    Kit.FadeNativeTextures(state, events)
    FadeFields(state, Field(legend, "ScrollFrame"), SCROLL_ART)
    FadeFields(state, Field(legend, "BorderFrame"), BORDER_FRAME_ART)
    Fade(state, Kit.Path(questLog, "QuestSessionManagement", "BG"))
end

local function SkinFrame(frame, state)
    if not frame or NS.IsCombatLocked() then return false, "combat" end
    if not Safety.CanDecorate(frame, true) then return false, "protected-frame" end
    if not Attach(state, frame, SHELL_SPEC) then return false, "shell-failed" end
    Attach(state, Field(frame, "TitleCanvasSpacerFrame"), TITLE_SPEC)

    local border = Field(frame, "BorderFrame")
    FadeFields(state, border, WINDOW_BORDER_ART)
    Kit.FadeNineSlice(state, Field(border, "NineSlice"))

    SkinControl(state, Field(border, "CloseButton"), WINDOW_BUTTON_SPEC)
    local maxMin = Field(border, "MaximizeMinimizeFrame")
    SkinControl(state, Field(maxMin, "MaximizeButton"), WINDOW_BUTTON_SPEC)
    SkinControl(state, Field(maxMin, "MinimizeButton"), WINDOW_BUTTON_SPEC)

    SkinNavBar(state, Field(frame, "NavBar"))
    SkinOverlayControls(state, frame)
    SkinQuestLog(state, Field(frame, "QuestLog"))
    state.generation = Kit.SkinGeneration()
    return true
end

-- WorldMapMixin:OnShow sets the player's map first, which can rebuild the
-- navigation bar. The rest of the window keeps what this skin generation
-- applied: the quest log's display-mode callback covers its panels, and
-- QuestLogQuests_Update its pooled rows. Rows Blizzard acquired in combat,
-- when that hook stays quiet, take their pass now.
function WorldMapSkin:OnWorldMapShown()
    if NS.IsCombatLocked() then return end
    for frame, state in pairs(activeFrames) do
        if state.active then
            if state.generation == Kit.SkinGeneration() then
                SkinNavBar(state, Field(frame, "NavBar"))
                VisitQuestRows(state, Field(frame, "QuestLog"), SkinQuestRow)
            else
                SkinFrame(frame, state)
            end
        end
    end
end

-- Blizzard can refill the pools while the map is closed. The existing
-- OnWorldMapShown pass catches up any rows that were skipped while hidden.
local function OnQuestLogUpdated()
    for frame, state in pairs(activeFrames) do
        if state.active and state.generation ~= nil and Safety.Read(frame, "IsVisible") == true then
            VisitQuestRows(state, Field(frame, "QuestLog"), SkinQuestRow)
        end
    end
end

-- Runs inside Blizzard's update, so the pass is its own error boundary.
local function OnQuestLogUpdatedHook()
    if not NS.IsCombatLocked() then Dispatch(OnQuestLogUpdated) end
end

function WorldMapSkin:OnQuestLogModeChanged()
    if NS.IsCombatLocked() then return end
    for frame, state in pairs(activeFrames) do
        if state.active then SkinQuestLog(state, Field(frame, "QuestLog")) end
    end
end

local function MapDisplayChanged()
    NS.WindowControls.Refresh()
end

local function RegisterCallbacks()
    if callbacksRegistered then return end
    EventRegistry:RegisterCallback(SHOW_CALLBACK, WorldMapSkin.OnWorldMapShown, WorldMapSkin)
    EventRegistry:RegisterCallback(DISPLAY_MODE_CALLBACK, WorldMapSkin.OnQuestLogModeChanged, WorldMapSkin)
    EventRegistry:RegisterCallback("WorldMapMaximized", MapDisplayChanged, WorldMapSkin)
    EventRegistry:RegisterCallback("WorldMapMinimized", MapDisplayChanged, WorldMapSkin)
    callbacksRegistered = true
end

local function UnregisterCallbacksIfIdle()
    if not callbacksRegistered or next(activeFrames) ~= nil then return end
    callbacksRegistered = false
    EventRegistry:UnregisterCallback("WorldMapMaximized", WorldMapSkin)
    EventRegistry:UnregisterCallback("WorldMapMinimized", WorldMapSkin)
    EventRegistry:UnregisterCallback(SHOW_CALLBACK, WorldMapSkin)
    EventRegistry:UnregisterCallback(DISPLAY_MODE_CALLBACK, WorldMapSkin)
end

function WorldMapSkin.Apply(frame, owner)
    frame = frame or _G.WorldMapFrame
    owner = owner or "worldMap"
    if not frame then return false, "missing-frame" end
    if NS.IsCombatLocked() then return false, "combat" end

    local state = frameStates[frame]
    if not state then
        state = { surfaces = Kit.WeakSet(), questRows = Kit.WeakSet() }
        frameStates[frame] = state
    end
    state.owner = owner
    state.active = true
    activeFrames[frame] = state
    NS.WorldMapQuests.Activate(state, frame)

    local applied, reason = SkinFrame(frame, state)
    if not applied then
        state.active = false
        activeFrames[frame] = nil
        NS.WorldMapQuests.Release(state)
        return false, reason
    end
    RegisterCallbacks()
    if not questLogUpdateHooked then
        questLogUpdateHooked = Kit.HookGlobal("QuestLogQuests_Update", OnQuestLogUpdatedHook)
    end
    NS.QuestText.Activate(frame, owner)
    -- The map is a native scroll canvas, not a menu list. Forever also owns
    -- overscroll layers; keep root fades and scroll translations off that tree.
    if NS.Client.isForever then NS.GenericWindows.TrackMenuMotion(Field(frame, "QuestLog"), owner) end
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
        state.generation = nil
        state.questRows = Kit.WeakSet()
        activeFrames[frame] = nil
        for _, record in pairs(questHovers) do
            if record.state == state then record.enabled, record.suppressed = false, false end
        end
        RefreshQuestHovers()
        NS.WorldMapQuests.Release(state)
    end

    NS.GenericWindows.Disable(owner)

    if state then
        NS.QuestText.Deactivate(frame, owner)
        Kit.HideSurfaces(state)
    end
    UnregisterCallbacksIfIdle()
    return true
end
