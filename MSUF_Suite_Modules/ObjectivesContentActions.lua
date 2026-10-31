local _, P = ...
local S = P.Suite
local O = P.Objectives
local Public, Finite = S.Public, S.Finite
local OpenAchievement, WatchTogglePressed, Untrack = O.OpenAchievement, O.WatchTogglePressed, O.Untrack
local WindowAllowed = O.WindowAllowed

-- What the rows of the Traveler's Log, Endeavors and collectible groups do:
-- the targets of the header clicks of Blizzard's own modules (see
-- ObjectivesContent.lua). Each opens a window of Blizzard's panel manager,
-- which refuses the Suite's call in combat and under WoW Forever's Gamepad UI
-- would run the frame controls manager in it: they act only while
-- O.WindowAllowed allows (see ObjectivesActions.lua), and under the Gamepad UI
-- a click goes to the Blizzard button of the nearest window instead
-- (ContentPanelButton).

------------------------------------------------------------------ open
local function OpenTravelersLog(activityID)
    -- Loads the Adventure Guide on first use; a loaded addon is left alone.
    EncounterJournal_LoadUI()
    MonthlyActivitiesFrame_OpenFrameToActivity(activityID)
end

local function OpenEndeavor(taskID)
    HousingFramesUtil.OpenFrameToTaskID(taskID)
end

local function OpenProfession(recipeID)
    if not ProfessionsUtil.OpenProfessionFrameToRecipe(recipeID) then
        UIErrorsFrame:AddExternalErrorMessage(ADVENTURE_TRACKING_OPEN_PROFESSION_ERROR_TEXT)
    end
end

-- The target type and id of a collectible, or nil while it has none readable.
local function CollectibleTarget(trackableType, trackableID)
    local targetType, targetID = C_ContentTracking.GetCurrentTrackingTarget(trackableType, trackableID)
    if Public(targetType) and Finite(targetID) then return targetType, targetID end
end

-- An achievement or profession target opens its own window, anything else the
-- map of the trackable.
local function OpenCollectible(trackableID, trackableType)
    local targetType, targetID = CollectibleTarget(trackableType, trackableID)
    local targets = Enum.ContentTrackingTargetType
    if targetType == targets.Achievement then
        OpenAchievement(targetID)
    elseif targetType == targets.Profession then
        OpenProfession(targetID)
    else
        ContentTrackingUtil.OpenMapToTrackable(trackableType, trackableID)
    end
end

local function OpenAppearance(sourceID)
    if WindowAllowed() then TransmogUtil.OpenCollectionToItem(sourceID) end
end

-- The Blizzard button of the window nearest to a row's target, for a click
-- under the Gamepad UI (O.RowPreClick): the Adventure Guide for a Traveler's
-- Log activity, the professions window for a profession target, the world map
-- for the map of a collectible. Endeavors, achievements and the Housing window
-- have no button there.
function O.ContentPanelButton(button)
    if button.group == "travelersLog" then return S.PanelButton("journal") end
    if button.group ~= "collectibles" then return nil end
    local targetType = CollectibleTarget(button.contentType, button.contentID)
    local targets = Enum.ContentTrackingTargetType
    if targetType == targets.Profession then return S.PanelButton("professions") end
    if targetType ~= targets.Achievement then return S.PanelButton("worldMap") end
end

local OPEN = { travelersLog = OpenTravelersLog, endeavors = OpenEndeavor, collectibles = OpenCollectible }

local function Open(button)
    if not WindowAllowed() then return end
    OPEN[button.group](button.contentID, button.contentType)
end

------------------------------------------------------------------ clicks and menu
function O.UntrackContent(button)
    local group, id = button.group, button.contentID
    if group == "travelersLog" then
        C_PerksActivities.RemoveTrackedPerksActivity(id)
    elseif group == "endeavors" then
        C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(id)
    else
        C_ContentTracking.StopTracking(button.contentType, id, Enum.ContentTrackingStopType.Manual)
    end
end

function O.OnContentClick(button)
    if WatchTogglePressed() then
        Untrack(button)
    else
        Open(button)
    end
end

-- The same two entries as Blizzard's header menus; collectibles other than
-- appearances have no collection window to open.
function O.BuildContentMenu(root, button)
    local group, windows = button.group, S.CanOpenNativeWindow()
    if group == "travelersLog" then
        root:CreateButton(OBJECTIVES_VIEW_IN_TRAVELERS_LOG, function() Open(button) end):SetEnabled(windows)
    elseif group == "endeavors" then
        root:CreateButton(OBJECTIVES_VIEW_IN_ENDEAVORS_TAB, function() Open(button) end):SetEnabled(windows)
    elseif button.contentType == Enum.ContentTrackingType.Appearance then
        root:CreateButton(CONTENT_TRACKING_OPEN_JOURNAL_OPTION, function()
            OpenAppearance(button.contentID)
        end):SetEnabled(windows)
    end
    root:CreateButton(OBJECTIVES_STOP_TRACKING, function() Untrack(button) end)
end
