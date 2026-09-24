local _, NS = ...

-- Clean-room adapter for Blizzard_EncounterJournal (Retail 12.1).
-- All ownership is external. The adapter observes Blizzard's public callback
-- registries, never replaces scripts, and only touches verified visual fields.

local EncounterJournalSkin = {
    states = setmetatable({}, { __mode = "k" }),
}
NS.EncounterJournalSkin = EncounterJournalSkin

local CALLBACK_TAB_SET = "EncounterJournal.TabSet"
local CALLBACK_JOURNEY_CHANGED = "JourneysFrameMixin.FactionChanged"
local RegisterAllScrollBoxes

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then
        return nil
    end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Path(object, ...)
    for index = 1, select("#", ...) do
        object = SafeField(object, select(index, ...))
        if not object then
            return nil
        end
    end
    return object
end

local function IsUnsafe(target)
    return not NS.Safety or not NS.Safety.CanCreateRegions(target, true)
end

local function IsUnsafeControl(target)
    return not NS.Safety or not NS.Safety.CanControl(target, true)
        or not NS.Safety.CanCreateRegions(target, true)
end

local function NewState(frame, owner)
    return {
        frame = frame,
        owner = owner,
        active = false,
        surfaces = WeakSet(),
        rows = WeakSet(),
        textColors = setmetatable({}, { __mode = "k" }),
        textRoles = setmetatable({}, { __mode = "k" }),
        vertexColors = setmetatable({}, { __mode = "k" }),
        vertexRoles = setmetatable({}, { __mode = "k" }),
        scrollBoxes = WeakSet(),
        eventCallbacks = {},
        deferred = {},
    }
end

local function GetState(frame, owner)
    local state = EncounterJournalSkin.states[frame]
    if not state then
        state = NewState(frame, owner)
        EncounterJournalSkin.states[frame] = state
    end
    state.owner = owner or state.owner
    return state
end

local function ReadTextColor(fontObject)
    local getter = SafeField(fontObject, "GetTextColor")
    if type(getter) ~= "function" then
        return nil
    end
    local ok, r, g, b, a = pcall(getter, fontObject)
    if not ok or type(r) ~= "number" then
        return nil
    end
    return { r, g, b, tonumber(a) or 1 }
end

local function SameColor(left, right)
    return left and right
        and left[1] == right[1]
        and left[2] == right[2]
        and left[3] == right[3]
        and left[4] == right[4]
end

local function ThemeColor(role)
    return { NS.Theme.GetColor(role) }
end

local function SetThemeTextColor(state, fontObject, role, recapture)
    if not fontObject or type(SafeField(fontObject, "SetTextColor")) ~= "function" then
        return false
    end

    local current = ReadTextColor(fontObject)
    local previousRole = state.textRoles[fontObject]
    if not state.textColors[fontObject] then
        state.textColors[fontObject] = current
    elseif recapture and previousRole and current
        and not SameColor(current, ThemeColor(previousRole)) then
        -- Blizzard may swap a tab's native font state before this callback.
        -- Capture only a color which is observably not one installed by us.
        state.textColors[fontObject] = current
    end

    state.textRoles[fontObject] = role
    local r, g, b, a = NS.Theme.GetColor(role)
    fontObject:SetTextColor(r, g, b, a)
    return true
end

local function ReadVertexColor(texture)
    local getter = SafeField(texture, "GetVertexColor")
    if type(getter) ~= "function" then
        return nil
    end
    local ok, r, g, b, a = pcall(getter, texture)
    if not ok or type(r) ~= "number" then
        return nil
    end
    return { r, g, b, tonumber(a) or 1 }
end

local function SetThemeVertexColor(state, texture, role)
    if not texture or type(SafeField(texture, "SetVertexColor")) ~= "function" then
        return false
    end
    if not state.vertexColors[texture] then
        state.vertexColors[texture] = ReadVertexColor(texture)
    end
    state.vertexRoles[texture] = role
    local r, g, b, a = NS.Theme.GetColor(role)
    texture:SetVertexColor(r, g, b, a)
    return true
end

local function AttachSurface(state, target, spec)
    if not target or IsUnsafe(target) then
        return nil
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local ok, surface = pcall(NS.Surface.Attach, target, spec)
    if ok and surface then
        state.surfaces[target] = true
        NS.Surface.SetVisible(target, true)
        return surface
    end
    return nil
end

local function Fade(state, region)
    if region then
        pcall(NS.Cosmetics.Fade, region, state.owner)
    end
end

local function FadeNineSlice(state, nineSlice)
    if nineSlice then
        pcall(NS.Cosmetics.FadeNineSlice, nineSlice, state.owner)
    end
end

local function FadeChrome(state, frame)
    if not frame then
        return
    end
    for _, key in ipairs({
        "Bg", "BG", "Background", "Backdrop", "TopTileStreaks",
        "BottomTileStreaks", "BackgroundTile", "BackgroundTexture",
    }) do
        Fade(state, SafeField(frame, key))
    end
    FadeNineSlice(state, SafeField(frame, "NineSlice"))
    FadeNineSlice(state, SafeField(frame, "Border"))
end

local function CollectRegions(frame)
    local getter = SafeField(frame, "GetRegions")
    if type(getter) ~= "function" then
        return {}
    end

    local regions = {}
    local function Capture(...)
        for index = 1, select("#", ...) do
            regions[#regions + 1] = select(index, ...)
        end
    end
    local ok = pcall(function() Capture(getter(frame)) end)
    return ok and regions or {}
end

local function IsLargeRegion(region, minimumWidth, minimumHeight)
    local widthGetter = SafeField(region, "GetWidth")
    local heightGetter = SafeField(region, "GetHeight")
    local width, height
    if type(widthGetter) == "function" then
        local ok, value = pcall(widthGetter, region)
        if ok and type(value) == "number" then width = value end
    end
    if type(heightGetter) == "function" then
        local ok, value = pcall(heightGetter, region)
        if ok and type(value) == "number" then height = value end
    end
    return (not width or width == 0 or width >= minimumWidth)
        and (not height or height == 0 or height >= minimumHeight)
end

local function FadeExactAtlas(state, exactFrame, atlas, minimumWidth, minimumHeight)
    if not exactFrame or type(atlas) ~= "string" then
        return false
    end
    local faded = false
    for _, region in ipairs(CollectRegions(exactFrame)) do
        local getAtlas = SafeField(region, "GetAtlas")
        if type(getAtlas) == "function" then
            local ok, value = pcall(getAtlas, region)
            if ok and value == atlas
                and IsLargeRegion(region, minimumWidth or 1, minimumHeight or 1) then
                Fade(state, region)
                faded = true
            end
        end
    end
    return faded
end

local function ButtonText(button)
    local text = SafeField(button, "Text") or SafeField(button, "text")
    if text then
        return text
    end
    local getter = SafeField(button, "GetFontString")
    if type(getter) == "function" then
        local ok, value = pcall(getter, button)
        if ok then
            return value
        end
    end
    return nil
end

local function TrackControl(state, target, result)
    if result then
        state.surfaces[target] = true
        return true
    end
    return false
end

local function SkinButton(state, button, primary)
    if not button or IsUnsafeControl(button) then
        return false
    end
    local spec = {
        role = primary and "buttonPrimary" or "button",
        activeRole = "buttonPrimary",
        useControlShape = true,
        pillHeight = 28,
        inset = 1,
        allowImplicitProtected = true,
    }
    local result
    if SafeField(button, "Left") and SafeField(button, "Center") and SafeField(button, "Right") then
        local ok, value = pcall(NS.ControlSkin.ApplyThreeSliceButton, button, state.owner, spec)
        result = ok and value
    else
        local ok, value = pcall(NS.ControlSkin.ApplyButton, button, state.owner, spec)
        result = ok and value
    end
    if TrackControl(state, button, result) then
        SetThemeTextColor(state, ButtonText(button), primary and "title" or "text", true)
        return true
    end
    return false
end

local function TabSelected(tab)
    local getter = SafeField(tab, "IsSelected")
    if type(getter) == "function" then
        local ok, selected = pcall(getter, tab)
        if ok then
            return selected == true
        end
    end
    local active = SafeField(tab, "MiddleActive")
        or SafeField(tab, "LeftActive") or SafeField(tab, "RightActive")
    local shown = SafeField(active, "IsShown")
    if type(shown) == "function" then
        local ok, selected = pcall(shown, active)
        if ok then
            return selected == true
        end
    end
    return SafeField(tab, "isSelected") == true
end

local function SkinTab(state, tab)
    if not tab or IsUnsafeControl(tab) then
        return false
    end
    local ok, result = pcall(NS.ControlSkin.ApplyTab, tab, state.owner, {
        role = "navigation",
        activeRole = "navigationActive",
        useControlShape = true,
        pillHeight = 28,
        inset = 1,
        allowImplicitProtected = true,
    })
    if ok and result then
        state.surfaces[tab] = true
        pcall(NS.ControlSkin.Refresh, tab)
        SetThemeTextColor(state, ButtonText(tab), TabSelected(tab) and "accentBright" or "muted", true)
        return true
    end
    return false
end

local function SkinSearchBox(state, searchBox)
    if not searchBox or IsUnsafeControl(searchBox) then
        return
    end
    local ok, result = pcall(NS.ControlSkin.ApplySearchBox, searchBox, state.owner, {
        role = "input",
        useControlShape = true,
        pillHeight = 28,
        inset = 1,
        allowImplicitProtected = true,
    })
    if ok and result then
        state.surfaces[searchBox] = true
    end
    SetThemeTextColor(state, searchBox, "text")
    SetThemeTextColor(state, SafeField(searchBox, "Instructions"), "muted")
end

local function SkinTutorial(state)
    local contents = Path(state.frame, "TutorialsFrame", "Contents")
    if not contents or IsUnsafe(contents) then
        return
    end

    -- This is deliberately the only region enumeration in the adapter. The
    -- parent identity and exact atlas prevent unrelated semantic art from being
    -- suppressed. The verified atlas is the large tutorial parchment layer.
    FadeExactAtlas(state, contents, "adventureguide-tutorial-rpe", 480, 220)
    AttachSurface(state, contents, {
        role = "card",
        radius = 8,
        inset = 8,
        allowImplicitProtected = true,
    })
    SetThemeTextColor(state, SafeField(contents, "Header"), "title")
    SetThemeTextColor(state, SafeField(contents, "Description"), "text")
    Fade(state, SafeField(contents, "Divider"))
    SkinButton(state, SafeField(contents, "StartButton"), true)
end

local function SkinSuggestionCard(state, card)
    if not card or IsUnsafe(card) then
        return
    end
    Fade(state, SafeField(card, "bg"))
    AttachSurface(state, card, {
        role = "card",
        radius = 8,
        inset = 2,
        allowImplicitProtected = true,
    })

    local center = SafeField(card, "centerDisplay")
    SetThemeTextColor(state, Path(center, "title", "text"), "title")
    SetThemeTextColor(state, Path(center, "description", "text"), "text")
    SetThemeTextColor(state, Path(card, "reward", "text"), "muted")
    SkinButton(state, SafeField(card, "button"), true)
end

local function SkinSuggestions(state)
    local suggest = SafeField(state.frame, "suggestFrame")
    if not suggest or IsUnsafe(suggest) then
        return
    end
    AttachSurface(state, suggest, {
        role = "panel",
        radius = 8,
        inset = 1,
        allowImplicitProtected = true,
    })
    SkinSuggestionCard(state, SafeField(suggest, "Suggestion1"))
    SkinSuggestionCard(state, SafeField(suggest, "Suggestion2"))
    SkinSuggestionCard(state, SafeField(suggest, "Suggestion3"))
end

local function SkinInstanceSelect(state)
    local instanceSelect = SafeField(state.frame, "instanceSelect")
    if not instanceSelect or IsUnsafe(instanceSelect) then
        return
    end
    Fade(state, SafeField(instanceSelect, "bg"))
    Fade(state, SafeField(instanceSelect, "evergreenBg"))
    AttachSurface(state, instanceSelect, {
        role = "panel",
        radius = 8,
        inset = 2,
        allowImplicitProtected = true,
    })
    SetThemeTextColor(state, SafeField(instanceSelect, "Title"), "title")
end

local function SkinEncounterDetail(state)
    local encounter = SafeField(state.frame, "encounter")
    if not encounter or IsUnsafe(encounter) then
        return
    end
    AttachSurface(state, encounter, {
        role = "panel",
        radius = 8,
        inset = 1,
        allowImplicitProtected = true,
    })

    local instance = SafeField(encounter, "instance")
    if instance and not IsUnsafe(instance) then
        Fade(state, SafeField(instance, "loreBG"))
        Fade(state, SafeField(instance, "titleBG"))
        AttachSurface(state, instance, {
            role = "card",
            radius = 8,
            inset = 2,
            allowImplicitProtected = true,
        })
        SetThemeTextColor(state, SafeField(instance, "title"), "title")
    end

    local info = SafeField(encounter, "info")
    if info and not IsUnsafe(info) then
        FadeChrome(state, info)
        AttachSurface(state, info, {
            role = "panel",
            radius = 8,
            inset = 1,
            allowImplicitProtected = true,
        })
        SetThemeTextColor(state, SafeField(info, "instanceTitle"), "title")
        SetThemeTextColor(state, SafeField(info, "encounterTitle"), "title")
        for _, key in ipairs({ "overviewTab", "lootTab", "bossTab", "modelTab" }) do
            SkinTab(state, SafeField(info, key))
        end
    end
end

local function SkinMonthlyActivities(state)
    local monthly = SafeField(state.frame, "MonthlyActivitiesFrame")
    if not monthly or IsUnsafe(monthly) then
        return
    end
    Fade(state, SafeField(monthly, "Bg"))
    AttachSurface(state, monthly, {
        role = "panel",
        radius = 8,
        inset = 1,
        allowImplicitProtected = true,
    })

    local filterList = SafeField(monthly, "FilterList")
    if filterList and not IsUnsafe(filterList) then
        Fade(state, SafeField(filterList, "Bg"))
        AttachSurface(state, filterList, {
            role = "card",
            radius = 6,
            inset = 1,
            allowImplicitProtected = true,
        })
    end

    local themeContainer = SafeField(monthly, "ThemeContainer")
    for _, key in ipairs({ "Top", "Bottom", "Left", "Right", "FilterList" }) do
        Fade(state, SafeField(themeContainer, key))
    end

    local header = SafeField(monthly, "HeaderContainer")
    SetThemeTextColor(state, SafeField(header, "Title"), "title")
    SetThemeTextColor(state, SafeField(header, "Month"), "text")
    SetThemeTextColor(state, SafeField(header, "TimeLeft"), "muted")
    SetThemeTextColor(state, SafeField(monthly, "RestrictedText"), "danger")

    local threshold = SafeField(monthly, "ThresholdContainer")
    SetThemeTextColor(state, Path(threshold, "TextContainer", "Points"), "text")
    SetThemeTextColor(state, Path(threshold, "TextContainer", "ProgressText"), "muted")
end

local function SkinJourneys(state)
    local journeys = SafeField(state.frame, "JourneysFrame")
    if not journeys or IsUnsafe(journeys) then
        return
    end
    AttachSurface(state, journeys, {
        role = "panel",
        radius = 8,
        inset = 1,
        allowImplicitProtected = true,
    })
    FadeChrome(state, SafeField(journeys, "BorderFrame"))

    local progress = SafeField(journeys, "JourneyProgress")
    if progress and not IsUnsafe(progress) then
        AttachSurface(state, progress, {
            role = "panel",
            radius = 8,
            inset = 2,
            allowImplicitProtected = true,
        })
        SetThemeTextColor(state, SafeField(progress, "JourneyName"), "title")
        SetThemeTextColor(state, Path(progress, "ProgressDetailsFrame", "JourneyLevel"), "title")
        SetThemeTextColor(state, Path(progress, "ProgressDetailsFrame", "JourneyLevelProgress"), "text")
        SkinButton(state, SafeField(progress, "OverviewBtn"))
    end

    local overview = SafeField(journeys, "JourneyOverview")
    if overview and not IsUnsafe(overview) then
        AttachSurface(state, overview, {
            role = "panel",
            radius = 8,
            inset = 2,
            allowImplicitProtected = true,
        })
        SetThemeTextColor(state, SafeField(overview, "JourneyName"), "title")
        SetThemeTextColor(state, SafeField(overview, "JourneyDescription"), "text")
        SetThemeTextColor(state, SafeField(overview, "HighlightLabel"), "muted")
        SetThemeTextColor(state, SafeField(overview, "LevelText"), "accentBright")
        SkinButton(state, SafeField(overview, "OverviewBtn"))
    end
end

local function SkinLootJournals(state)
    local loot = SafeField(state.frame, "LootJournal")
    if loot and not IsUnsafe(loot) then
        FadeExactAtlas(state, loot, "loottab-background", 400, 200)
        AttachSurface(state, loot, {
            role = "panel",
            radius = 8,
            inset = 1,
            allowImplicitProtected = true,
        })
    end

    local items = SafeField(state.frame, "LootJournalItems")
    if items and not IsUnsafe(items) then
        FadeExactAtlas(state, items, "loottab-background", 400, 200)
        AttachSurface(state, items, {
            role = "panel",
            radius = 8,
            inset = 1,
            allowImplicitProtected = true,
        })
        local itemSets = SafeField(items, "ItemSetsFrame")
        if itemSets and not IsUnsafe(itemSets) then
            AttachSurface(state, itemSets, {
                role = "card",
                radius = 6,
                inset = 1,
                allowImplicitProtected = true,
            })
        end
    end
end

local function SkinRootStatic(state)
    local frame = state.frame
    if not frame or IsUnsafe(frame) then
        return false
    end

    if NS.GenericWindows and not state.genericApplied then
        local ok, applied = pcall(NS.GenericWindows.ApplyFrame, frame, state.owner, {
            role = "shell",
            radius = 8,
            maxDepth = 8,
            maxNodes = 900,
            allowImplicitProtected = true,
            registerDynamicRows = false,
        })
        state.genericApplied = ok and applied == true
    end

    if not AttachSurface(state, frame, {
        role = "shell",
        radius = 8,
        inset = 0,
        allowImplicitProtected = true,
    }) then
        return false
    end
    FadeChrome(state, frame)
    FadeChrome(state, SafeField(frame, "inset"))
    SetThemeTextColor(state, Path(frame, "TitleContainer", "TitleText"), "title")
    SkinSearchBox(state, SafeField(frame, "searchBox"))

    for _, key in ipairs({
        "JourneysTab", "MonthlyActivitiesTab", "suggestTab", "dungeonsTab",
        "raidsTab", "LootJournalTab", "TutorialsTab",
    }) do
        SkinTab(state, SafeField(frame, key))
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

local function SkinDynamicRow(state, row)
    if not state.active or not row or IsUnsafe(row) then
        return
    end
    AttachSurface(state, row, {
        role = "card",
        radius = 6,
        inset = 1,
        listItem = true,
        allowImplicitProtected = true,
    })
    state.rows[row] = true

    -- These are verified decorative card layers; icon, portrait, encounter
    -- image, reward and status textures are intentionally left untouched.
    Fade(state, SafeField(row, "Background"))
    Fade(state, SafeField(row, "Backplate"))

    for _, key in ipairs(rowTitleFields) do
        SetThemeTextColor(state, SafeField(row, key), "title", true)
    end
    for _, key in ipairs(rowTextFields) do
        SetThemeTextColor(state, SafeField(row, key), "text", true)
    end
    for _, key in ipairs(rowMutedFields) do
        SetThemeTextColor(state, SafeField(row, key), "muted", true)
    end

    local textContainer = SafeField(row, "TextContainer")
    SetThemeTextColor(state, SafeField(textContainer, "NameText"), "title", true)
    SetThemeTextColor(state, SafeField(textContainer, "ConditionsText"), "text", true)
end

local function EnumerateActivePool(state, pool)
    local getter = SafeField(pool, "GetNextActive")
    if type(getter) ~= "function" then
        return 0
    end
    local count, current = 0, nil
    while count < 64 do
        local ok, object = pcall(getter, pool, current)
        if not ok or not object or object == current then
            break
        end
        current = object
        count = count + 1
        SkinDynamicRow(state, object)
    end
    return count
end

local function PrewarmPool(state, pool, desiredCount)
    desiredCount = math.max(0, math.min(32, tonumber(desiredCount) or 0))
    if desiredCount == 0 or not pool then
        return
    end

    local active = EnumerateActivePool(state, pool)
    local acquire = SafeField(pool, "Acquire")
    local release = SafeField(pool, "Release")
    if type(acquire) ~= "function" or type(release) ~= "function" then
        return
    end

    local acquired = {}
    for _ = active + 1, desiredCount do
        local ok, object = pcall(acquire, pool)
        if not ok or not object then
            break
        end
        acquired[#acquired + 1] = object
        SkinDynamicRow(state, object)
    end
    for index = #acquired, 1, -1 do
        pcall(release, pool, acquired[index])
    end
end

local function RefreshJourneyPools(state, factionID)
    local journeys = SafeField(state.frame, "JourneysFrame")
    local progressPool = Path(journeys, "JourneyProgress", "rewardPool")
    EnumerateActivePool(state, progressPool)

    local highlightsPool = Path(journeys, "JourneyOverview", "Highlights", "highlightPool")
    EnumerateActivePool(state, highlightsPool)
    if factionID and C_MajorFactions and type(C_MajorFactions.GetMajorFactionData) == "function" then
        local ok, data = pcall(C_MajorFactions.GetMajorFactionData, factionID)
        local highlights = ok and data and data.highlights
        if type(highlights) == "table" then
            PrewarmPool(state, highlightsPool, #highlights)
        end
    end
end

local function RefreshDynamicTables(state, factionID)
    local encounter = SafeField(state.frame, "encounter")
    for _, collection in ipairs({
        SafeField(encounter, "usedHeaders"),
        SafeField(encounter, "freeHeaders"),
        Path(state.frame, "MonthlyActivitiesFrame", "thresholdFrames"),
    }) do
        if type(collection) == "table" then
            for _, row in pairs(collection) do
                SkinDynamicRow(state, row)
            end
        end
    end
    RefreshJourneyPools(state, factionID)
end

local function SafeRefresh(state, includeStatic, factionID)
    if not state or not state.active then
        return
    end
    local ok, message = pcall(function()
        if includeStatic then
            SkinRootStatic(state)
        end
        RefreshDynamicTables(state, factionID)
    end)
    if not ok then
        NS.ReportError("encounter journal refresh", message)
    end
end

local function QueueRefresh(state, suffix, callback)
    if not state or not state.active then
        return
    end
    local key = "encounterJournal:" .. tostring(suffix)
    local function Run()
        state.deferred[key] = nil
        if state.active then
            local ok, message = pcall(callback)
            if not ok then
                NS.ReportError("encounter journal callback", message)
            end
        end
    end
    if NS.IsCombatLocked() then
        state.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, Run)
    else
        Run()
    end
end

function EncounterJournalSkin:OnTabSet(frame)
    local state = self.activeState
    if not state or (frame and frame ~= state.frame) then
        return
    end
    QueueRefresh(state, "tab", function()
        SafeRefresh(state, true)
        RegisterAllScrollBoxes(state)
    end)
end

function EncounterJournalSkin:OnJourneyChanged(factionID)
    local state = self.activeState
    if not state then
        return
    end
    QueueRefresh(state, "journey", function()
        SafeRefresh(state, false, factionID)
    end)
end

function EncounterJournalSkin:OnScrollBoxInitialized(row)
    local state = self.activeState
    if not state or not row then
        return
    end
    QueueRefresh(state, "row:" .. tostring(row), function()
        SkinDynamicRow(state, row)
    end)
end

local function RefreshThemeColors(state)
    for fontObject, role in pairs(state.textRoles) do
        if fontObject and type(SafeField(fontObject, "SetTextColor")) == "function" then
            local r, g, b, a = NS.Theme.GetColor(role)
            fontObject:SetTextColor(r, g, b, a)
        end
    end
    for texture, role in pairs(state.vertexRoles) do
        if texture and type(SafeField(texture, "SetVertexColor")) == "function" then
            local r, g, b, a = NS.Theme.GetColor(role)
            texture:SetVertexColor(r, g, b, a)
        end
    end
end

function EncounterJournalSkin:OnThemeChanged()
    local state = self.activeState
    if state and state.active and not NS.IsCombatLocked() then
        RefreshThemeColors(state)
        pcall(NS.ControlSkin.RefreshOwner, state.owner)
    end
end

local function ScrollEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterScrollBox(state, scrollBox)
    local event = ScrollEvent()
    if not event or not scrollBox or state.scrollBoxes[scrollBox]
        or type(SafeField(scrollBox, "RegisterCallback")) ~= "function" then
        return
    end

    local ok = pcall(scrollBox.RegisterCallback, scrollBox, event,
        EncounterJournalSkin.OnScrollBoxInitialized, EncounterJournalSkin)
    if not ok then
        return
    end
    state.scrollBoxes[scrollBox] = true

    local forEach = SafeField(scrollBox, "ForEachFrame")
    if type(forEach) == "function" then
        pcall(forEach, scrollBox, function(row)
            SkinDynamicRow(state, row)
        end)
    end
end

RegisterAllScrollBoxes = function(state)
    local frame = state.frame
    local scrollBoxes = {
        Path(frame, "instanceSelect", "ScrollBox"),
        Path(frame, "searchResults", "ScrollBox"),
        Path(frame, "encounter", "info", "BossesScrollBox"),
        Path(frame, "encounter", "info", "LootContainer", "ScrollBox"),
        Path(frame, "JourneysFrame", "JourneysList"),
        Path(frame, "MonthlyActivitiesFrame", "ScrollBox"),
        Path(frame, "MonthlyActivitiesFrame", "FilterList", "ScrollBox"),
        Path(frame, "LootJournal", "ScrollBox"),
        Path(frame, "LootJournalItems", "ItemSetsFrame", "ScrollBox"),
    }
    for index = 1, #scrollBoxes do
        RegisterScrollBox(state, scrollBoxes[index])
    end
end

local function RegisterEventCallback(state, event, method)
    if state.eventCallbacks[event] or not EventRegistry
        or type(SafeField(EventRegistry, "RegisterCallback")) ~= "function" then
        return
    end
    local ok = pcall(EventRegistry.RegisterCallback, EventRegistry, event, method, EncounterJournalSkin)
    if ok then
        state.eventCallbacks[event] = true
    end
end

local function RegisterCallbacks(state)
    RegisterEventCallback(state, CALLBACK_TAB_SET, EncounterJournalSkin.OnTabSet)
    RegisterEventCallback(state, CALLBACK_JOURNEY_CHANGED, EncounterJournalSkin.OnJourneyChanged)
    RegisterAllScrollBoxes(state)
    NS.Registry.AddListener(EncounterJournalSkin, EncounterJournalSkin.OnThemeChanged)
end

local function UnregisterCallbacks(state)
    if EventRegistry and type(SafeField(EventRegistry, "UnregisterCallback")) == "function" then
        for event in pairs(state.eventCallbacks) do
            pcall(EventRegistry.UnregisterCallback, EventRegistry, event, EncounterJournalSkin)
        end
    end
    state.eventCallbacks = {}

    local event = ScrollEvent()
    if event then
        for scrollBox in pairs(state.scrollBoxes) do
            local unregister = SafeField(scrollBox, "UnregisterCallback")
            if type(unregister) == "function" then
                pcall(unregister, scrollBox, event, EncounterJournalSkin)
            end
        end
    end
    state.scrollBoxes = WeakSet()
    NS.Registry.RemoveListener(EncounterJournalSkin)
end

local function RestoreTextColors(state)
    for fontObject, original in pairs(state.textColors) do
        local role = state.textRoles[fontObject]
        local current = ReadTextColor(fontObject)
        if original and role and SameColor(current, ThemeColor(role))
            and type(SafeField(fontObject, "SetTextColor")) == "function" then
            fontObject:SetTextColor(original[1], original[2], original[3], original[4])
        end
    end
    state.textColors = setmetatable({}, { __mode = "k" })
    state.textRoles = setmetatable({}, { __mode = "k" })
end

local function RestoreVertexColors(state)
    for texture, original in pairs(state.vertexColors) do
        local role = state.vertexRoles[texture]
        local current = ReadVertexColor(texture)
        if original and role and SameColor(current, ThemeColor(role))
            and type(SafeField(texture, "SetVertexColor")) == "function" then
            texture:SetVertexColor(original[1], original[2], original[3], original[4])
        end
    end
    state.vertexColors = setmetatable({}, { __mode = "k" })
    state.vertexRoles = setmetatable({}, { __mode = "k" })
end

local function RestoreState(state)
    state.active = false
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
    end
    state.deferred = {}
    UnregisterCallbacks(state)

    pcall(NS.ControlSkin.DisableOwner, state.owner)
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    RestoreTextColors(state)
    RestoreVertexColors(state)
    pcall(NS.Cosmetics.RestoreOwner, state.owner)
    if NS.GenericWindows then
        pcall(NS.GenericWindows.Disable, state.owner)
    end
    state.genericApplied = false
    state.rows = WeakSet()
end

function EncounterJournalSkin.Apply(frame, owner)
    frame = frame or _G.EncounterJournal
    owner = owner or "encounterJournal"
    if not frame then
        return false, "missing"
    end
    if IsUnsafe(frame) then
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

    local ok, applied = pcall(SkinRootStatic, state)
    if not ok or not applied then
        if not ok then
            NS.ReportError("encounter journal apply", applied)
        end
        RestoreState(state)
        if EncounterJournalSkin.activeState == state then
            EncounterJournalSkin.activeState = nil
        end
        return false, "failed"
    end

    RegisterCallbacks(state)
    RefreshDynamicTables(state)
    PrewarmPool(state, Path(frame, "JourneysFrame", "JourneyProgress", "rewardPool"), 4)
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
        pcall(NS.ControlSkin.DisableOwner, owner)
        pcall(NS.Cosmetics.RestoreOwner, owner)
    end
    if EncounterJournalSkin.activeState == state then
        EncounterJournalSkin.activeState = nil
    end
    return true
end

return EncounterJournalSkin
