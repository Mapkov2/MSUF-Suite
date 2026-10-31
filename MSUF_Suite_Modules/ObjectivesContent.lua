local _, P = ...
local NS, S = P.NS, P.Suite
local O = P.Objectives
local SOURCES, COLLECTORS = O.SOURCES, O.COLLECTORS
local NextEntry, AddLine, Read = O.NextEntry, O.AddLine, O.Read
local Public, Finite, Text = S.Public, S.Finite, S.PublicText

-- The modules of Blizzard's objective tracker that the first sources did not
-- cover (ObjectiveTrackerManager:Init lists them all): the Traveler's Log
-- (MonthlyActivitiesObjectiveTracker), Endeavors (InitiativeTasks), the
-- Adventure Guide's tracked collectibles (Adventure) and the zone's widget
-- block (UIWidget). Each source reads what its Blizzard module reads and
-- refreshes on the events that module listens to (see ObjectivesData.lua for
-- how the files fit together).
-- The Traveler's Log and Endeavors are Retail features: the Traveler's Log is
-- a Mainline-only part of Blizzard_EncounterJournal, and the Housing addons
-- load for the standard game type only, not in Forever's Camelot client. Nothing
-- can be tracked there, so the Suite offers neither.
local retail = not NS.Client.isForever
local MAX_TRACKED = 30

------------------------------------------------------------------ requirement lists
-- A tracked activity or task lists its open requirements, "3 / 5" as "3/5".
local function AddRequirementLines(entry, requirements)
    if not Public(requirements) or type(requirements) ~= "table" then return end
    for i = 1, #requirements do
        local requirement = requirements[i]
        if Public(requirement) and type(requirement) == "table"
            and Public(requirement.completed) and not requirement.completed then
            local text = Text(requirement.requirementText)
            if text then AddLine(entry, (text:gsub(" / ", "/"))) end
        end
    end
end

-- tracked is the client's { trackedIDs = { ... } } record; getInfo reads one
-- id; nameKey is the field that holds its name. Completed ones are not listed.
local function CollectRequirementEntries(list, group, tracked, getInfo, nameKey)
    local ids = Public(tracked) and type(tracked) == "table" and tracked.trackedIDs
    if not Public(ids) or type(ids) ~= "table" then return end
    for i = 1, math.min(#ids, MAX_TRACKED) do
        local id = ids[i]
        local info = Finite(id) and Read(getInfo, id)
        local name = type(info) == "table" and Text(info[nameKey])
        if name and Public(info.completed) and not info.completed then
            local entry = NextEntry(list, id, name, group)
            entry.tracked, entry.contentID = true, id
            AddRequirementLines(entry, info.requirementsList)
        end
    end
end

local function CollectTravelersLog(list)
    CollectRequirementEntries(list, "travelersLog", Read(C_PerksActivities.GetTrackedPerksActivities),
        C_PerksActivities.GetPerksActivityInfo, "activityName")
end

-- Blizzard's module asks the server for the neighborhood's initiative on
-- login and zone changes (InitiativeTasksObjectiveTracker); that module keeps
-- running behind the Suite's tracker, so NEIGHBORHOOD_INITIATIVE_UPDATED
-- delivers the data.
local function CollectEndeavors(list)
    CollectRequirementEntries(list, "endeavors", Read(C_NeighborhoodInitiative.GetTrackedInitiativeTasks),
        C_NeighborhoodInitiative.GetInitiativeTaskInfo, "taskName")
end

------------------------------------------------------------------ collectibles
local function NavigableTarget(targetType)
    local targets = Enum.ContentTrackingTargetType
    return targetType == targets.Vendor or targetType == targets.JournalEncounter
end

-- The line Blizzard adds under a vendor or encounter objective: why there is
-- no route, or the waypoint of the trackable the player super-tracks.
local function RouteLine(trackableType, trackableID)
    local results = Enum.ContentTrackingResult
    local result, mapID = C_ContentTracking.GetBestMapForTrackable(trackableType, trackableID, true)
    if not Public(result) or result == results.DataPending then return end
    if result ~= results.Success or not Finite(mapID) then return CONTENT_TRACKING_LOCATION_UNAVAILABLE end
    local navigation, navigable = C_ContentTracking.IsNavigable(trackableType, trackableID)
    if not Public(navigation) then return end
    if navigation == results.Failure or (navigation == results.Success and Public(navigable) and not navigable) then
        return CONTENT_TRACKING_ROUTE_UNAVAILABLE
    end
    local superType, superID = C_SuperTrack.GetSuperTrackedContent()
    if Public(superType) and Public(superID) and superType == trackableType and superID == trackableID then
        local waypoint = Text(C_ContentTracking.GetWaypointText(trackableType, trackableID))
        return waypoint and OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION:format(waypoint)
    end
end

local function AddCollectible(list, trackableType, trackableID)
    if not Finite(trackableID) then return end
    local targetType, targetID = C_ContentTracking.GetCurrentTrackingTarget(trackableType, trackableID)
    local title = Text(C_ContentTracking.GetTitle(trackableType, trackableID))
    if not Public(targetType) or not Finite(targetID) or not title then return end
    local entry = NextEntry(list, ContentTrackingUtil.MakeCombinedID(trackableType, trackableID), title, "collectibles")
    entry.tracked, entry.contentID, entry.contentType = true, trackableID, trackableType
    -- Plain text: the rows draw no hyperlinks.
    local objective = Text(C_ContentTracking.GetObjectiveText(targetType, targetID, false))
    local text = objective or Text(CONTENT_TRACKING_RETRIEVING_INFO)
    if text then AddLine(entry, text) end
    local route = objective and NavigableTarget(targetType) and RouteLine(trackableType, trackableID)
    if route then AddLine(entry, route) end
end

-- Blizzard's module only notes a collected appearance or decor item
-- (AdventureObjectiveTrackerMixin:OnTrackableItemCollected) and stops tracking
-- it in its next layout, which can be long after. The Suite stops it itself, as
-- that module does, in its next pass over the collectibles: one frame after the
-- event, so the module's own toast and sound still run. Objectives.lua listens
-- to these events only while collectibles are shown.
local COLLECTED_EVENTS = {
    TRANSMOG_COLLECTION_SOURCE_ADDED = function(sourceID) return Enum.ContentTrackingType.Appearance, sourceID end,
}
if retail then
    COLLECTED_EVENTS.HOUSE_DECOR_ADDED_TO_CHEST = function(_, decorID)
        return Enum.ContentTrackingType.Decor, decorID
    end
end
O.COLLECTED_EVENTS = COLLECTED_EVENTS

-- [combined id] = the type and id of a collected item still being tracked.
local collectedTypes, collectedIDs = {}, {}

function O.NoteCollected(event, ...)
    local trackableType, trackableID = COLLECTED_EVENTS[event](...)
    if Finite(trackableID) and C_ContentTracking.IsTracking(trackableType, trackableID) == true then
        local key = ContentTrackingUtil.MakeCombinedID(trackableType, trackableID)
        collectedTypes[key], collectedIDs[key] = trackableType, trackableID
    end
end

local function StopCollected()
    for key, trackableType in pairs(collectedTypes) do
        C_ContentTracking.StopTracking(trackableType, collectedIDs[key], Enum.ContentTrackingStopType.Collected)
        collectedTypes[key], collectedIDs[key] = nil, nil
    end
end

local function CollectCollectibles(list)
    StopCollected()
    -- Blizzard's cache of CONTENT_TRACKING_IS_ENABLED_UPDATE.
    if not ContentTrackingUtil.IsContentTrackingEnabled() then return end
    local types = Read(C_ContentTracking.GetCollectableSourceTypes)
    if type(types) ~= "table" then return end
    for i = 1, #types do
        local trackableType = types[i]
        local ids = Finite(trackableType) and Read(C_ContentTracking.GetTrackedIDs, trackableType)
        if type(ids) == "table" then
            for j = 1, math.min(#ids, MAX_TRACKED) do AddCollectible(list, trackableType, ids[j]) end
        end
    end
end

------------------------------------------------------------------ zone widgets
-- The widgets of the zone's objective set. Blizzard's container knows whether
-- any are showing, one layout pass after the widget events; its module marks
-- itself dirty then and the Suite follows (Objectives.lua hooks that). The row
-- draws the set through its own widget container, like a Delve header
-- (ObjectivesDetails.lua).
local function CollectZone(list)
    if ObjectiveTrackerUIWidgetContainer:HasAnyWidgetsShowing() ~= true then return end
    local setID, zone = Read(C_UIWidgetManager.GetObjectiveTrackerWidgetSetID), Text(GetRealZoneText())
    if not Finite(setID) or setID <= 0 or not zone then return end
    NextEntry(list, 0, zone, "zone").scenarioHeaderSetID = setID
end

------------------------------------------------------------------ registration
-- A source is collected only while its show setting is on.
local function Register(source, collect, showKey)
    SOURCES[#SOURCES + 1] = source
    COLLECTORS[source] = function(list, c)
        if c[showKey] then collect(list) end
    end
end

Register("collectibles", CollectCollectibles, "showCollectibles")
Register("zone", CollectZone, "showZoneEvents")
if retail then
    Register("travelersLog", CollectTravelersLog, "showTravelersLog")
    Register("endeavors", CollectEndeavors, "showEndeavors")
end

-- The events the new sources listen to, with the sources each changes:
-- Objectives.lua registers them and routes their requests. Quest log events,
-- CONTENT_TRACKING_UPDATE and SUPER_TRACKING_CHANGED are routed there.
local EVENTS = {
    TRACKING_TARGET_INFO_UPDATE = { "collectibles" },
    TRACKABLE_INFO_UPDATE = { "collectibles" },
    CONTENT_TRACKING_IS_ENABLED_UPDATE = { "collectibles" },
}
if retail then
    for _, event in ipairs({ "PERKS_ACTIVITIES_TRACKED_UPDATED", "PERKS_ACTIVITIES_TRACKED_LIST_CHANGED",
        "PERKS_ACTIVITY_COMPLETED" }) do
        EVENTS[event] = { "travelersLog" }
    end
    for _, event in ipairs({ "INITIATIVE_TASKS_TRACKED_UPDATED", "INITIATIVE_TASKS_TRACKED_LIST_CHANGED",
        "NEIGHBORHOOD_INITIATIVE_UPDATED" }) do
        EVENTS[event] = { "endeavors" }
    end
end
O.CONTENT_EVENTS = EVENTS
