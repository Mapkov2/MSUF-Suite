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

local frameStates = setmetatable({}, { __mode = "k" })
local activeFrames = setmetatable({}, { __mode = "k" })
local callbacksRegistered = false

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Path(object, ...)
    for index = 1, select("#", ...) do
        object = SafeField(object, select(index, ...))
        if not object then return nil end
    end
    return object
end

local function ObjectType(object)
    local getter = SafeField(object, "GetObjectType")
    if type(getter) ~= "function" then return "" end
    local ok, value = pcall(getter, object)
    return ok and type(value) == "string" and value or ""
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("world map " .. tostring(label), message)
    end
end

local function TrackSurface(state, target)
    if state and target then state.surfaces[target] = true end
end

local function Attach(state, target, spec)
    if not target or NS.IsCombatLocked() or not NS.Surface or not NS.Safety
        or not NS.Safety.CanDecorate(target, true) then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local ok, surface = pcall(NS.Surface.Attach, target, spec)
    if ok and surface then
        TrackSurface(state, target)
        return true
    end
    if not ok then Report("surface", surface) end
    return false
end

local function Fade(state, region)
    if not region or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" then
        return false
    end
    local ok, result = pcall(NS.Cosmetics.Fade, region, state.owner)
    if not ok then Report("fade", result) end
    return ok and result == true
end

local function FadeFields(state, target, fields)
    for index = 1, #(fields or {}) do
        Fade(state, SafeField(target, fields[index]))
    end
end

local function FadeNineSlice(state, target)
    if not target or not NS.Cosmetics or type(NS.Cosmetics.FadeNineSlice) ~= "function" then
        return
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, target, state.owner)
    if not ok then Report("nine slice", message) end
end

local function DirectRegions(frame)
    local getter = SafeField(frame, "GetRegions")
    if type(getter) ~= "function" then return {} end
    local ok, regions = pcall(function() return { getter(frame) } end)
    return ok and regions or {}
end

local function FadeDirectTextures(state, frame)
    local regions = DirectRegions(frame)
    local surface = NS.Registry and NS.Registry.GetSurface(frame) or nil
    for index = 1, #regions do
        local region = regions[index]
        local owned = surface and (region == surface.fill or region == surface.edge
            or region == surface.depth or region == surface.highlight
            or region == surface.pushed or region == surface.disabled)
        if ObjectType(region) == "Texture" and not owned then
            Fade(state, region)
        end
    end
end

local function FadeNormalTexture(state, button)
    local getter = SafeField(button, "GetNormalTexture")
    if type(getter) ~= "function" then return end
    local ok, texture = pcall(getter, button)
    if ok then Fade(state, texture) end
end

local function SkinButton(state, button, spec)
    if not button or NS.IsCombatLocked() or not NS.ControlSkin or not NS.Safety
        or not NS.Safety.CanControl(button, true) then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    spec.useControlShape = spec.useControlShape ~= false
    local ok, applied = pcall(NS.ControlSkin.ApplyButton, button, state.owner, spec)
    if ok and applied then
        TrackSurface(state, button)
        return true
    end
    if not ok then Report("control", applied) end
    return false
end

local function SkinNavBar(state, navBar)
    if not navBar then return end

    Attach(state, navBar, { role = "navigation", radius = 6, inset = 0 })
    FadeDirectTextures(state, navBar)
    FadeDirectTextures(state, SafeField(navBar, "overlay"))
    FadeFields(state, navBar, {
        "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
        "InsetBorderLeft", "InsetBorderRight",
    })

    local list = SafeField(navBar, "navList")
    if type(list) == "table" then
        local count = math.min(#list, WorldMapSkin.navButtonLimit)
        for index = 1, count do
            local button = list[index]
            if button then
                SkinButton(state, button, {
                    role = "navigation",
                    activeRole = "navigationActive",
                    active = index == #list,
                    radius = 6,
                    pillHeight = 24,
                    inset = 1,
                    regions = { "selected" },
                })
                -- NavButtonTemplate's tiled normal texture is anonymous and
                -- otherwise remains above the replacement material. Arrow and
                -- menu glyph textures are separate and remain semantic.
                FadeNormalTexture(state, button)
                SkinButton(state, SafeField(button, "MenuArrowButton"), {
                    role = "button", radius = 4, pillHeight = 20, inset = 4,
                })
            end
        end
    end

    local overflow = SafeField(navBar, "overflow") or SafeField(navBar, "overflowButton")
    if overflow then
        SkinButton(state, overflow, { role = "button", radius = 4, inset = 3 })
        FadeNormalTexture(state, overflow)
    end
end

local function SkinOverlayControls(state, frame)
    local overlays = SafeField(frame, "overlayFrames")
    if type(overlays) == "table" then
        local count = math.min(#overlays, WorldMapSkin.overlayLimit)
        for index = 1, count do
            local control = overlays[index]
            if control ~= SafeField(frame, "NavBar") then
                local objectType = ObjectType(control)
                if objectType == "Button" or objectType == "DropdownButton" then
                    SkinButton(state, control, {
                        role = "button",
                        radius = 6,
                        pillHeight = 24,
                        inset = 2,
                        regions = { "Background", "Border" },
                    })
                end
            end
        end
    end

    local sideToggle = SafeField(frame, "SidePanelToggle")
    if sideToggle then
        SkinButton(state, SafeField(sideToggle, "OpenButton"), {
            role = "button", radius = 6, inset = 2,
        })
        SkinButton(state, SafeField(sideToggle, "CloseButton"), {
            role = "button", radius = 6, inset = 2,
        })
    end
end

local function SkinQuestTabs(state, questLog)
    local displayMode = SafeField(questLog, "displayMode")
    local tabs = {
        SafeField(questLog, "QuestsTab"),
        SafeField(questLog, "EventsTab"),
        SafeField(questLog, "MapLegendTab"),
    }
    for index = 1, #tabs do
        local tab = tabs[index]
        if tab then
            local active = displayMode ~= nil and SafeField(tab, "displayMode") == displayMode
            Attach(state, tab, {
                role = active and "navigationActive" or "navigation",
                radius = 6,
                inset = 2,
            })
            FadeFields(state, tab, { "Background", "SelectedTexture" })
        end
    end
end

local function SkinQuestLog(state, questLog)
    if not questLog then return end

    if NS.GenericWindows and type(NS.GenericWindows.ApplyFrame) == "function" then
        local ok, applied = pcall(NS.GenericWindows.ApplyFrame, questLog, state.owner, {
            role = "panel",
            rootSurface = false,
            childSurfaces = false,
            maxDepth = 6,
            maxNodes = 420,
            allowImplicitProtected = true,
        })
        if not ok then Report("quest log traversal", applied) end
    end

    -- QuestMapFrame and its display-mode children are full-area wrappers over
    -- the WorldMap shell. Their native parchment is faded below, but another
    -- material fill at every level would compound Glass back to near-opaque.
    Attach(state, questLog, {
        role = "panel", radius = 8, inset = 0, fillVisible = false,
    })
    Fade(state, SafeField(questLog, "VerticalSeparator"))
    SkinQuestTabs(state, questLog)

    local quests = SafeField(questLog, "QuestsFrame")
    local scroll = SafeField(quests, "ScrollFrame")
    local details = SafeField(quests, "DetailsFrame")
    local campaign = SafeField(quests, "CampaignOverview")
    local story = Path(scroll, "Contents", "StoryHeader")
    local rewards = Path(details, "RewardsFrameContainer", "RewardsFrame")

    local events = SafeField(questLog, "EventsFrame")
    local legend = SafeField(questLog, "MapLegend")
    Attach(state, quests, {
        role = "panel", radius = 6, inset = 0, fillVisible = false,
    })
    Attach(state, details, {
        role = "panel", radius = 6, inset = 0, fillVisible = false,
    })
    Attach(state, events, {
        role = "panel", radius = 6, inset = 0, fillVisible = false,
    })
    Attach(state, legend, {
        role = "panel", radius = 6, inset = 0, fillVisible = false,
    })
    Attach(state, story, { role = "card", radius = 4, inset = 1, listItem = true })
    Attach(state, rewards, { role = "card", radius = 4, inset = 0 })

    FadeFields(state, scroll, { "Background", "Edge" })
    FadeFields(state, SafeField(scroll, "BorderFrame"), { "Border", "TopDetail", "Shadow" })
    FadeFields(state, story, { "Background", "Divider" })
    FadeFields(state, details, { "Bg", "SealMaterialBG" })
    FadeFields(state, SafeField(details, "BorderFrame"), { "Border", "TopDetail", "Shadow" })
    FadeDirectTextures(state, SafeField(details, "BackFrame"))
    FadeFields(state, rewards, { "Background", "Bottom", "Top" })
    Fade(state, SafeField(campaign, "BG"))
    FadeFields(state, SafeField(campaign, "BorderFrame"), {
        "Border", "TopDetail", "Shadow",
    })
    FadeFields(state, SafeField(campaign, "ScrollFrame"), {
        "TopShadow", "BottomShadow",
    })
    FadeFields(state, SafeField(events, "ScrollBox"), { "Background" })
    FadeFields(state, SafeField(events, "BorderFrame"), {
        "Border", "TopDetail", "Shadow",
    })
    FadeDirectTextures(state, events)
    FadeFields(state, SafeField(legend, "ScrollFrame"), { "Background", "Edge" })
    FadeFields(state, SafeField(legend, "BorderFrame"), {
        "Border", "TopDetail", "Shadow",
    })
    Fade(state, Path(questLog, "QuestSessionManagement", "BG"))
end

local function SkinFrame(frame, state)
    if not frame or NS.IsCombatLocked() then return false, "combat" end
    if not NS.Safety or not NS.Safety.CanDecorate(frame, true) then
        return false, "protected-frame"
    end

    if not Attach(state, frame, { role = "shell", radius = 8, inset = 0 }) then
        return false, "shell-failed"
    end
    Attach(state, SafeField(frame, "TitleCanvasSpacerFrame"), {
        role = "navigation", radius = 6, inset = 0,
    })

    local border = SafeField(frame, "BorderFrame")
    FadeFields(state, border, { "Bg", "TopTileStreaks", "InsetBorderTop", "Underlay" })
    FadeNineSlice(state, SafeField(border, "NineSlice"))

    SkinButton(state, SafeField(border, "CloseButton"), {
        role = "button", radius = 4, inset = 2,
    })
    local maxMin = SafeField(border, "MaximizeMinimizeFrame")
    SkinButton(state, SafeField(maxMin, "MaximizeButton"), {
        role = "button", radius = 4, inset = 2,
    })
    SkinButton(state, SafeField(maxMin, "MinimizeButton"), {
        role = "button", radius = 4, inset = 2,
    })

    SkinNavBar(state, SafeField(frame, "NavBar"))
    SkinOverlayControls(state, frame)
    SkinQuestLog(state, SafeField(frame, "QuestLog"))
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
        if state.active then SkinQuestLog(state, SafeField(frame, "QuestLog")) end
    end
end

local function RegisterCallbacks()
    if callbacksRegistered or not EventRegistry
        or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end
    callbacksRegistered = true
    EventRegistry:RegisterCallback("WorldMapOnShow", WorldMapSkin.OnWorldMapShown, WorldMapSkin)
    EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", WorldMapSkin.OnQuestLogModeChanged, WorldMapSkin)
end

local function UnregisterCallbacksIfIdle()
    if not callbacksRegistered or next(activeFrames) ~= nil then return end
    callbacksRegistered = false
    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("WorldMapOnShow", WorldMapSkin)
        EventRegistry:UnregisterCallback("QuestLog.SetDisplayMode", WorldMapSkin)
    end
end

function WorldMapSkin.Apply(frame, owner)
    frame = frame or _G.WorldMapFrame
    owner = owner or "worldMap"
    if not frame then return false, "missing-frame" end
    if NS.IsCombatLocked() then return false, "combat" end

    local state = frameStates[frame]
    if not state then
        state = { surfaces = WeakSet() }
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

    if NS.GenericWindows and type(NS.GenericWindows.Disable) == "function" then
        NS.GenericWindows.Disable(owner)
    else
        if NS.ControlSkin then NS.ControlSkin.DisableOwner(owner) end
        if NS.Cosmetics then NS.Cosmetics.RestoreOwner(owner) end
    end

    if state then
        for target in pairs(state.surfaces) do
            NS.Surface.SetVisible(target, false)
        end
    end
    UnregisterCallbacksIfIdle()
    return true
end
