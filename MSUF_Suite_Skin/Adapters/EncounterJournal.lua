local _, NS = ...

-- Clean-room adapter for Blizzard_EncounterJournal (Retail 12.1).
-- All ownership is external. The adapter observes Blizzard's public callback
-- registries, never replaces scripts, and only touches verified visual fields.

local EncounterJournalSkin = {
    states = setmetatable({}, { __mode = "k" }),
}
NS.EncounterJournalSkin = EncounterJournalSkin

local Safety = NS.Safety
local Field = Safety.Field
local Dispatch = Safety.Dispatch
local SameColor = Safety.SameColor
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade
local Attach = Kit.Attach
local SetTextColor = Kit.SetTextColor

local CALLBACK_TAB_SET = "EncounterJournal.TabSet"
local CALLBACK_JOURNEY_CHANGED = "JourneysFrameMixin.FactionChanged"
local ROWS_JOB = "encounterJournal:rows"
local JOURNEY_POOLS_JOB = "encounterJournal:journey-pools"
local POOL_LIMIT = 64

local ROOT_MODE = {
    role = "shell",
    radius = 8,
    maxDepth = 8,
    maxNodes = 900,
    allowImplicitProtected = true,
    registerDynamicRows = false,
}

local SHELL_SPEC = { role = "shell", radius = 8, inset = 0 }
local PANEL_SPEC = { role = "panel", radius = 8, inset = 1 }
local PANEL_INSET_SPEC = { role = "panel", radius = 8, inset = 2 }
local CARD_SPEC = { role = "card", radius = 8, inset = 2 }
local SMALL_CARD_SPEC = { role = "card", radius = 6, inset = 1 }
local TUTORIAL_SPEC = { role = "card", radius = 8, inset = 8 }
local ROW_SPEC = { role = "card", radius = 6, inset = 1, listItem = true }

local BUTTON_SPEC = {
    role = "button",
    activeRole = "buttonPrimary",
    useControlShape = true,
    pillHeight = 28,
    inset = 1,
}
local PRIMARY_BUTTON_SPEC = {
    role = "buttonPrimary",
    activeRole = "buttonPrimary",
    useControlShape = true,
    pillHeight = 28,
    inset = 1,
}
local TAB_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    useControlShape = true,
    pillHeight = 28,
    inset = 1,
}

-- Exact atlases for the only region enumerations in this adapter. Parent
-- identity plus atlas and a minimum size keep unrelated semantic art native.
local TUTORIAL_ATLAS = { atlas = "adventureguide-tutorial-rpe", width = 480, height = 220 }
local LOOT_ATLAS = { atlas = "loottab-background", width = 400, height = 200 }

local chromeFields = {
    "Bg", "BG", "Background", "Backdrop", "TopTileStreaks",
    "BottomTileStreaks", "BackgroundTile", "BackgroundTexture",
}
local rootTabs = {
    "JourneysTab", "MonthlyActivitiesTab", "suggestTab", "dungeonsTab",
    "raidsTab", "LootJournalTab", "TutorialsTab",
}
local encounterTabs = { "overviewTab", "lootTab", "bossTab", "modelTab" }
local themeBorderFields = { "Top", "Bottom", "Left", "Right", "FilterList" }

local rowTitleFields = {
    "Name", "name", "SetName", "JourneyName", "JourneyCardName",
    "CategoryName", "Title", "RewardCardName", "HighlightTitle", "NameText",
}
local rowTextFields = {
    "Description", "description", "ItemLevel", "JourneyCardLevel",
    "JourneyCardProgress", "HighlightDescription", "ConditionsText", "Label",
}
local rowMutedFields = {
    "SpecName", "HighlightLevel", "TimeLeft", "ProgressText", "Points",
}

-- Row labels carry meaning in their color: completed, expired or unmet
-- Monthly Activities (MonthlyActivitiesButtonTextContainerMixin:UpdateTextColor),
-- legendary or unavailable powers (Blizzard_LootJournal.lua) and item set
-- quality (Blizzard_LootJournalItems.lua). Only the templates' plain colors
-- are themed: GameFontNormal gold, GameFontHighlight white and the parchment
-- brown of Blizzard_EncounterJournal.xml (Blizzard_Fonts_Shared FontStyles.xml
-- for the font objects), plus the skin's own Blizzard-yellow retint of that
-- gold (BlizzardYellow, read from the theme). Any other color stays
-- Blizzard's. Black (GameFontBlack) is Monthly Activities' completion signal:
-- it becomes the muted role, readable on the skin yet distinct from open
-- activities.
local PLAIN_ROW_COLORS = {
    { 1, 0.82, 0 },
    { 1, 1, 1 },
    { 0.25, 0.1484375, 0.02 },
}
local COMPLETED_ROW_COLOR = { 0, 0, 0 }
local COMPLETED_ROW_ROLE = "muted"

local scrollBoxPaths = {
    { "instanceSelect", "ScrollBox" },
    { "searchResults", "ScrollBox" },
    { "encounter", "info", "BossesScrollBox" },
    { "encounter", "info", "LootContainer", "ScrollBox" },
    { "JourneysFrame", "JourneysList" },
    { "MonthlyActivitiesFrame", "ScrollBox" },
    { "MonthlyActivitiesFrame", "FilterList", "ScrollBox" },
    { "LootJournal", "ScrollBox" },
    { "LootJournalItems", "ItemSetsFrame", "ScrollBox" },
}

local function CanCreateRegions(target)
    return Safety.CanCreateRegions(target, true)
end

local SkinDynamicRow

local function GetState(frame, owner)
    local state = EncounterJournalSkin.states[frame]
    if not state then
        state = {
            frame = frame,
            owner = owner,
            active = false,
            surfaces = Kit.WeakSet(),
            textColors = Kit.NewTextColors(),
            -- row label -> the role of its field
            rowLabels = Kit.WeakSet(),
            scrollBoxes = Kit.WeakSet(),
            eventCallbacks = {},
            deferred = {},
        }
        state.visitRow = function(row) SkinDynamicRow(state, row) end
        EncounterJournalSkin.states[frame] = state
    end
    state.owner = owner or state.owner
    return state
end

local function FadeChrome(state, frame)
    if not frame then return end
    Kit.FadeFields(state, frame, chromeFields)
    Kit.FadeNineSlice(state, Field(frame, "NineSlice"))
    Kit.FadeNineSlice(state, Field(frame, "Border"))
end

-- An unsized (0) or unreadable extent counts as large enough.
local function IsLargeRegion(region, minimumWidth, minimumHeight)
    local width = Safety.Read(region, "GetWidth")
    local height = Safety.Read(region, "GetHeight")
    width = type(width) == "number" and width or nil
    height = type(height) == "number" and height or nil
    return (not width or width == 0 or width >= minimumWidth)
        and (not height or height == 0 or height >= minimumHeight)
end

local function FadeLargeAtlasRegion(region, state, atlasSpec)
    if Safety.Read(region, "GetAtlas") == atlasSpec.atlas
        and IsLargeRegion(region, atlasSpec.width, atlasSpec.height) then
        Fade(state, region)
    end
end

local function ButtonText(button)
    return Field(button, "Text") or Field(button, "text") or (Safety.Call(button, "GetFontString"))
end

local function SkinButton(state, button, primary)
    local method = Field(button, "Left") and Field(button, "Center") and Field(button, "Right")
        and "ApplyThreeSliceButton" or "ApplyButton"
    if not Kit.SkinControl(state, button, primary and PRIMARY_BUTTON_SPEC or BUTTON_SPEC, method) then
        return false
    end
    SetTextColor(state.textColors, ButtonText(button), primary and "title" or "text", true)
    return true
end

local function TabSelected(tab)
    if type((Field(tab, "IsSelected"))) == "function" then
        return Safety.Read(tab, "IsSelected") == true
    end
    local active = Field(tab, "MiddleActive") or Field(tab, "LeftActive") or Field(tab, "RightActive")
    if type((Field(active, "IsShown"))) == "function" then
        return Kit.IsShown(active)
    end
    return Field(tab, "isSelected") == true
end

local function SkinTab(state, tab)
    if not Kit.SkinControl(state, tab, TAB_SPEC, "ApplyTab") then
        return false
    end
    NS.ControlSkin.Refresh(tab)
    SetTextColor(state.textColors, ButtonText(tab), TabSelected(tab) and "accentBright" or "muted", true)
    return true
end

local function SkinTutorial(state)
    local contents = Path(state.frame, "TutorialsFrame", "Contents")
    if not contents or not CanCreateRegions(contents) then
        return
    end
    -- The verified atlas is the large tutorial parchment layer.
    Kit.ForEachRegion(contents, FadeLargeAtlasRegion, state, TUTORIAL_ATLAS)
    Attach(state, contents, TUTORIAL_SPEC)
    SetTextColor(state.textColors, Field(contents, "Header"), "title")
    SetTextColor(state.textColors, Field(contents, "Description"), "text")
    Fade(state, Field(contents, "Divider"))
    SkinButton(state, Field(contents, "StartButton"), true)
end

local function SkinSuggestionCard(state, card)
    if not card or not CanCreateRegions(card) then
        return
    end
    Fade(state, Field(card, "bg"))
    Attach(state, card, CARD_SPEC)

    local center = Field(card, "centerDisplay")
    SetTextColor(state.textColors, Path(center, "title", "text"), "title")
    SetTextColor(state.textColors, Path(center, "description", "text"), "text")
    SetTextColor(state.textColors, Path(card, "reward", "text"), "muted")
    SkinButton(state, Field(card, "button"), true)
end

local function SkinSuggestions(state)
    local suggest = Field(state.frame, "suggestFrame")
    if not suggest or not CanCreateRegions(suggest) then
        return
    end
    Attach(state, suggest, PANEL_SPEC)
    SkinSuggestionCard(state, Field(suggest, "Suggestion1"))
    SkinSuggestionCard(state, Field(suggest, "Suggestion2"))
    SkinSuggestionCard(state, Field(suggest, "Suggestion3"))
end

local function SkinInstanceSelect(state)
    local instanceSelect = Field(state.frame, "instanceSelect")
    if not instanceSelect or not CanCreateRegions(instanceSelect) then
        return
    end
    Fade(state, Field(instanceSelect, "bg"))
    Fade(state, Field(instanceSelect, "evergreenBg"))
    Attach(state, instanceSelect, PANEL_INSET_SPEC)
    SetTextColor(state.textColors, Field(instanceSelect, "Title"), "title")
end

local function SkinEncounterDetail(state)
    local encounter = Field(state.frame, "encounter")
    if not encounter or not CanCreateRegions(encounter) then
        return
    end
    Attach(state, encounter, PANEL_SPEC)

    local instance = Field(encounter, "instance")
    if instance and CanCreateRegions(instance) then
        Fade(state, Field(instance, "loreBG"))
        Fade(state, Field(instance, "titleBG"))
        Attach(state, instance, CARD_SPEC)
        SetTextColor(state.textColors, Field(instance, "title"), "title")
    end

    local info = Field(encounter, "info")
    if info and CanCreateRegions(info) then
        FadeChrome(state, info)
        Attach(state, info, PANEL_SPEC)
        SetTextColor(state.textColors, Field(info, "instanceTitle"), "title")
        SetTextColor(state.textColors, Field(info, "encounterTitle"), "title")
        for index = 1, #encounterTabs do
            SkinTab(state, Field(info, encounterTabs[index]))
        end
    end
end

local function SkinMonthlyActivities(state)
    local monthly = Field(state.frame, "MonthlyActivitiesFrame")
    if not monthly or not CanCreateRegions(monthly) then
        return
    end
    Fade(state, Field(monthly, "Bg"))
    Attach(state, monthly, PANEL_SPEC)

    local filterList = Field(monthly, "FilterList")
    if filterList and CanCreateRegions(filterList) then
        Fade(state, Field(filterList, "Bg"))
        Attach(state, filterList, SMALL_CARD_SPEC)
    end
    Kit.FadeFields(state, Field(monthly, "ThemeContainer"), themeBorderFields)

    local colors = state.textColors
    local header = Field(monthly, "HeaderContainer")
    SetTextColor(colors, Field(header, "Title"), "title")
    SetTextColor(colors, Field(header, "Month"), "text")
    SetTextColor(colors, Field(header, "TimeLeft"), "muted")
    SetTextColor(colors, Field(monthly, "RestrictedText"), "danger")

    local threshold = Field(monthly, "ThresholdContainer")
    SetTextColor(colors, Path(threshold, "TextContainer", "Points"), "text")
    SetTextColor(colors, Path(threshold, "TextContainer", "ProgressText"), "muted")
end

local function SkinJourneys(state)
    local journeys = Field(state.frame, "JourneysFrame")
    if not journeys or not CanCreateRegions(journeys) then
        return
    end
    Attach(state, journeys, PANEL_SPEC)
    FadeChrome(state, Field(journeys, "BorderFrame"))

    local colors = state.textColors
    local progress = Field(journeys, "JourneyProgress")
    if progress and CanCreateRegions(progress) then
        Attach(state, progress, PANEL_INSET_SPEC)
        SetTextColor(colors, Field(progress, "JourneyName"), "title")
        SetTextColor(colors, Path(progress, "ProgressDetailsFrame", "JourneyLevel"), "title")
        SetTextColor(colors, Path(progress, "ProgressDetailsFrame", "JourneyLevelProgress"), "text")
        SkinButton(state, Field(progress, "OverviewBtn"))
    end

    local overview = Field(journeys, "JourneyOverview")
    if overview and CanCreateRegions(overview) then
        Attach(state, overview, PANEL_INSET_SPEC)
        SetTextColor(colors, Field(overview, "JourneyName"), "title")
        SetTextColor(colors, Field(overview, "JourneyDescription"), "text")
        SetTextColor(colors, Field(overview, "HighlightLabel"), "muted")
        SetTextColor(colors, Field(overview, "LevelText"), "accentBright")
        SkinButton(state, Field(overview, "OverviewBtn"))
    end
end

local function SkinLootJournals(state)
    local loot = Field(state.frame, "LootJournal")
    if loot and CanCreateRegions(loot) then
        Kit.ForEachRegion(loot, FadeLargeAtlasRegion, state, LOOT_ATLAS)
        Attach(state, loot, PANEL_SPEC)
    end

    local items = Field(state.frame, "LootJournalItems")
    if items and CanCreateRegions(items) then
        Kit.ForEachRegion(items, FadeLargeAtlasRegion, state, LOOT_ATLAS)
        Attach(state, items, PANEL_SPEC)
        local itemSets = Field(items, "ItemSetsFrame")
        if itemSets and CanCreateRegions(itemSets) then
            Attach(state, itemSets, SMALL_CARD_SPEC)
        end
    end
end

local function SkinRootStatic(state)
    local frame = state.frame
    if not frame or not CanCreateRegions(frame) then
        return false
    end

    if not state.genericApplied then
        state.genericApplied = NS.GenericWindows.ApplyFrame(frame, state.owner, ROOT_MODE) == true
    end

    if not Attach(state, frame, SHELL_SPEC) then
        return false
    end
    FadeChrome(state, frame)
    FadeChrome(state, Field(frame, "inset"))
    SetTextColor(state.textColors, Path(frame, "TitleContainer", "TitleText"), "title")
    Kit.SkinSearchBox(state, Field(frame, "searchBox"))

    for index = 1, #rootTabs do
        SkinTab(state, Field(frame, rootTabs[index]))
    end

    SkinInstanceSelect(state)
    SkinEncounterDetail(state)
    SkinMonthlyActivities(state)
    SkinJourneys(state)
    SkinSuggestions(state)
    SkinTutorial(state)
    SkinLootJournals(state)
    return true
end

-- Blizzard's template colors are classified; alpha does not matter.
local function IsNativeColor(r, g, b, color)
    return SameColor(r, g, b, nil, color[1], color[2], color[3], nil, Safety.COLOR_NATIVE)
end

local function IsPlainRowColor(r, g, b)
    for index = 1, #PLAIN_ROW_COLORS do
        if IsNativeColor(r, g, b, PLAIN_ROW_COLORS[index]) then return true end
    end
    -- BlizzardYellow wrote this one, so it reads back at our own precision.
    local yellowR, yellowG, yellowB = NS.Theme.GetColor("blizzardYellow")
    return SameColor(r, g, b, nil, yellowR, yellowG, yellowB, nil, Safety.COLOR_OWN)
end

-- Themes a row label while it shows a plain template color (or still our
-- color). Once Blizzard paints a meaningful color the label is released to it.
local function SetRowTextColor(state, fontObject, role)
    local r, g, b, a = Safety.ReadColor(fontObject, "GetTextColor")
    if not r then return end
    local colors = state.textColors
    state.rowLabels[fontObject] = role
    if IsNativeColor(r, g, b, COMPLETED_ROW_COLOR) then
        SetTextColor(colors, fontObject, COMPLETED_ROW_ROLE, true)
    elseif IsPlainRowColor(r, g, b) then
        SetTextColor(colors, fontObject, role, true)
    elseif Kit.ShowsTextColor(colors, fontObject, r, g, b, a) then
        -- Blizzard has not repainted since our pass: keep the role we chose.
        SetTextColor(colors, fontObject, colors.roles[fontObject] or role, true)
    else
        Kit.ForgetTextColor(colors, fontObject)
    end
end

-- A look change repaints every themed text. Row labels follow the same rule
-- as on initialization: one Blizzard recolored in place since our pass (an
-- activity that turned unmet, completed or expired) keeps Blizzard's color.
-- Clearing entries during pairs() is allowed; nothing is added meanwhile.
local function RefreshTextColors(state)
    local colors = state.textColors
    for fontObject, role in pairs(colors.roles) do
        local rowRole = state.rowLabels[fontObject]
        if rowRole then
            SetRowTextColor(state, fontObject, rowRole)
        else
            SetTextColor(colors, fontObject, role)
        end
    end
end

local function SetRowTextColors(state, row, fields, role)
    for index = 1, #fields do
        SetRowTextColor(state, Field(row, fields[index]), role)
    end
end

SkinDynamicRow = function(state, row)
    if not state.active or not row or not CanCreateRegions(row) then
        return
    end
    Attach(state, row, ROW_SPEC)

    -- These are verified decorative card layers; icon, portrait, encounter
    -- image, reward and status textures are intentionally left untouched.
    Fade(state, Field(row, "Background"))
    Fade(state, Field(row, "Backplate"))

    SetRowTextColors(state, row, rowTitleFields, "title")
    SetRowTextColors(state, row, rowTextFields, "text")
    SetRowTextColors(state, row, rowMutedFields, "muted")

    local textContainer = Field(row, "TextContainer")
    SetRowTextColor(state, Field(textContainer, "NameText"), "title")
    SetRowTextColor(state, Field(textContainer, "ConditionsText"), "text")
end

local function SkinActivePool(state, pool)
    if type((Field(pool, "GetNextActive"))) ~= "function" then
        return 0
    end
    local count, current = 0, nil
    while count < POOL_LIMIT do
        local object = pool:GetNextActive(current)
        if not object or object == current then
            break
        end
        current = object
        count = count + 1
        SkinDynamicRow(state, object)
    end
    return count
end

-- The reward and highlight cards Blizzard itself acquired. The pools are
-- never driven from here: frames that addon code acquires are created in
-- addon (tainted) execution.
local function RefreshJourneyPools(state)
    local journeys = Field(state.frame, "JourneysFrame")
    SkinActivePool(state, Path(journeys, "JourneyProgress", "rewardPool"))
    SkinActivePool(state, Path(journeys, "JourneyOverview", "Highlights", "highlightPool"))
end

-- Cards acquired in combat are painted in one pass once it ends.
local function FlushJourneyPools()
    local state = EncounterJournalSkin.activeState
    if not state then return end
    state.deferred[JOURNEY_POOLS_JOB] = nil
    if state.active then RefreshJourneyPools(state) end
end

-- JourneyProgressFrameMixin:SetRewards and JourneyOverviewHighlightsFrameMixin:
-- DisplayHighlights (Blizzard_Journeys.lua) release their pool, then acquire,
-- fill and show every card; their post-hooks skin the cards before they are
-- drawn. The pass is its own error boundary.
local function OnJourneyCardsAcquired()
    local state = EncounterJournalSkin.activeState
    if not state or not state.active then return end
    if NS.IsCombatLocked() then
        if not state.deferred[JOURNEY_POOLS_JOB] then
            state.deferred[JOURNEY_POOLS_JOB] = true
            NS.CombatGate.RunOrDefer(JOURNEY_POOLS_JOB, FlushJourneyPools)
        end
        return
    end
    Dispatch(RefreshJourneyPools, state)
end

-- Blizzard_Journeys.xml gives JourneyProgress and JourneyOverview.Highlights
-- their own copies of these mixins, and self:SetRewards() and
-- self.Highlights:DisplayHighlights() resolve on them, so the instances are
-- hooked, once each.
local journeyHooks = setmetatable({}, { __mode = "k" })

local function HookJourneyCards(frame, method)
    if not frame or journeyHooks[frame] then return end
    journeyHooks[frame] = Kit.HookFunction(frame, method, OnJourneyCardsAcquired)
end

local function HookJourneyPools(state)
    local journeys = Field(state.frame, "JourneysFrame")
    HookJourneyCards(Field(journeys, "JourneyProgress"), "SetRewards")
    HookJourneyCards(Path(journeys, "JourneyOverview", "Highlights"), "DisplayHighlights")
end

local function SkinRowCollection(state, collection)
    if type(collection) ~= "table" then return end
    for _, row in pairs(collection) do
        SkinDynamicRow(state, row)
    end
end

local function RefreshDynamicTables(state)
    local encounter = Field(state.frame, "encounter")
    SkinRowCollection(state, Field(encounter, "usedHeaders"))
    SkinRowCollection(state, Field(encounter, "freeHeaders"))
    SkinRowCollection(state, Path(state.frame, "MonthlyActivitiesFrame", "thresholdFrames"))
    RefreshJourneyPools(state)
end

local function Refresh(state, includeStatic)
    if not state or not state.active then
        return
    end
    if includeStatic then
        SkinRootStatic(state)
    end
    RefreshDynamicTables(state)
end

local function QueueRefresh(state, suffix, callback)
    if not state or not state.active then
        return
    end
    if not NS.IsCombatLocked() then
        callback()
        return
    end
    local key = "encounterJournal:" .. tostring(suffix)
    state.deferred[key] = true
    NS.CombatGate.RunOrDefer(key, function()
        state.deferred[key] = nil
        if state.active then callback() end
    end)
end

local RegisterAllScrollBoxes

function EncounterJournalSkin:OnTabSet(frame)
    local state = self.activeState
    if not state or (frame and frame ~= state.frame) then
        return
    end
    QueueRefresh(state, "tab", function()
        Refresh(state, true)
        RegisterAllScrollBoxes(state)
    end)
end

function EncounterJournalSkin:OnJourneyChanged()
    local state = self.activeState
    if not state then
        return
    end
    QueueRefresh(state, "journey", function()
        Refresh(state, false)
    end)
end

-- Rows initialized during combat are painted in one pass once it ends.
local function FlushCombatRows()
    local state = EncounterJournalSkin.activeState
    if not state then return end
    state.deferred[ROWS_JOB] = nil
    if not state.active then return end
    for scrollBox in pairs(state.scrollBoxes) do
        Kit.ForEachRow(scrollBox, state.visitRow)
    end
end

-- ScrollBox callback for every initialized (new or recycled) row.
function EncounterJournalSkin:OnScrollBoxInitialized(row)
    local state = self.activeState
    if not state or not state.active or not row then
        return
    end
    if NS.IsCombatLocked() then
        if not state.deferred[ROWS_JOB] then
            state.deferred[ROWS_JOB] = true
            NS.CombatGate.RunOrDefer(ROWS_JOB, FlushCombatRows)
        end
        return
    end
    SkinDynamicRow(state, row)
end

function EncounterJournalSkin:OnThemeChanged()
    local state = self.activeState
    if state and state.active and not NS.IsCombatLocked() then
        RefreshTextColors(state)
        NS.ControlSkin.RefreshOwner(state.owner)
    end
end

local function RegisterScrollBox(state, scrollBox)
    if not scrollBox or state.scrollBoxes[scrollBox] then
        return
    end
    local event = Kit.RegisterRowCallback(scrollBox,
        EncounterJournalSkin.OnScrollBoxInitialized, EncounterJournalSkin)
    if not event then
        return
    end
    state.scrollBoxes[scrollBox] = event
    Kit.ForEachRow(scrollBox, state.visitRow)
end

RegisterAllScrollBoxes = function(state)
    for index = 1, #scrollBoxPaths do
        RegisterScrollBox(state, Kit.PathOf(state.frame, scrollBoxPaths[index]))
    end
end

local function RegisterEventCallback(state, event, method)
    if not state.eventCallbacks[event] then
        EventRegistry:RegisterCallback(event, method, EncounterJournalSkin)
        state.eventCallbacks[event] = true
    end
end

local function RegisterCallbacks(state)
    RegisterEventCallback(state, CALLBACK_TAB_SET, EncounterJournalSkin.OnTabSet)
    RegisterEventCallback(state, CALLBACK_JOURNEY_CHANGED, EncounterJournalSkin.OnJourneyChanged)
    RegisterAllScrollBoxes(state)
    HookJourneyPools(state)
    NS.Registry.AddListener(EncounterJournalSkin, EncounterJournalSkin.OnThemeChanged)
end

local function UnregisterCallbacks(state)
    for event in pairs(state.eventCallbacks) do
        EventRegistry:UnregisterCallback(event, EncounterJournalSkin)
    end
    state.eventCallbacks = {}

    for scrollBox, event in pairs(state.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, event, EncounterJournalSkin)
    end
    state.scrollBoxes = Kit.WeakSet()
    NS.Registry.RemoveListener(EncounterJournalSkin)
end

local function RestoreState(state)
    state.active = false
    Kit.CancelDeferred(state)
    UnregisterCallbacks(state)

    NS.ControlSkin.DisableOwner(state.owner)
    Kit.HideSurfaces(state)
    Kit.RestoreTextColors(state.textColors)
    state.rowLabels = Kit.WeakSet()
    NS.Cosmetics.RestoreOwner(state.owner)
    NS.GenericWindows.Disable(state.owner)
    state.genericApplied = false
end

function EncounterJournalSkin.Apply(frame, owner)
    frame = frame or _G.EncounterJournal
    owner = owner or "encounterJournal"
    if not frame then
        return false, "missing"
    end
    if not CanCreateRegions(frame) then
        return false, "protected"
    end

    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("encounterJournal:apply", function()
            EncounterJournalSkin.Apply(_G.EncounterJournal or frame, owner)
        end)
        return false, "combat"
    end

    local previous = EncounterJournalSkin.states[frame]
    if previous and previous.active and previous.owner ~= owner then
        RestoreState(previous)
    end

    local state = GetState(frame, owner)
    state.active = true
    EncounterJournalSkin.activeState = state

    if not SkinRootStatic(state) then
        RestoreState(state)
        if EncounterJournalSkin.activeState == state then
            EncounterJournalSkin.activeState = nil
        end
        return false, "failed"
    end

    RegisterCallbacks(state)
    RefreshDynamicTables(state)
    return true
end

function EncounterJournalSkin.Disable(frame, owner)
    frame = frame or (EncounterJournalSkin.activeState and EncounterJournalSkin.activeState.frame)
        or _G.EncounterJournal
    if not frame then
        return true
    end

    NS.CombatGate.Cancel("encounterJournal:apply")
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("encounterJournal:disable", function()
            EncounterJournalSkin.Disable(frame, owner)
        end)
        return false, "combat"
    end

    local state = EncounterJournalSkin.states[frame]
    if state then
        RestoreState(state)
    elseif owner then
        NS.ControlSkin.DisableOwner(owner)
        NS.Cosmetics.RestoreOwner(owner)
    end
    if EncounterJournalSkin.activeState == state then
        EncounterJournalSkin.activeState = nil
    end
    return true
end

return EncounterJournalSkin
