local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
if not NS.Client.isForever then return end

local SOURCE, MIN_LEVEL = "sleepingBag", 14
local Guide = {}
local window

-- Quest IDs and locations checked against Naowh Forever 1.2.32 (Discovery).
-- The first two stops share a faction-specific quest. Each intermediate
-- stop stays current until the player accepts the quest offered there.
local WESTFALL = { map = 1436, x = .375, y = .507 }
local BARRENS = { map = 1413, x = .464, y = .739 }
local COMMON = {
    { map = 1442, x = .408, y = .526, nextQuest = 79980, name = Suite.Text("Pocket Litter"),
        tip = Suite.Text("Take the mountain trail northeast of Sun Rock Retreat (50.9, 52.3). "
            .. "At the abandoned camp, search the belongings on the crate, turn in the quest and accept the next one.") },
    { map = 1442, x = .396, y = .499, nextQuest = 79974, name = Suite.Text("Mound of Dirt"),
        tip = Suite.Text("Climb the slope north of the camp. "
            .. "Jump from the edge onto the ledge with the dirt pile, turn in the quest there and accept the next one.") },
    { map = 1432, x = .495, y = .128, nextQuest = 79975, name = Suite.Text("Carved Figurine"),
        tip = Suite.Text("At the dam in northern Loch Modan, drop onto the stone heads on the Wetlands side. "
            .. "Use the figurine to turn in the quest and accept the next one.") },
    { map = 1424, x = .873, y = .496, nextQuest = 79976, name = Suite.Text("Messenger Bag"),
        tip = Suite.Text("Use the broken cart on the Hillsbrad side of Thoradin's Wall to climb up. "
            .. "Jump from rock to rock inside the wall, then look outside on the right for the hanging bag. "
            .. "Turn in the quest and accept the final one.") },
    { map = 1417, x = .225, y = .242, completedQuest = 79976, name = Suite.Text("Hastily Rolled-Up Satchel"),
        tip = Suite.Text("Open the satchel just below the hanging bag and turn in the final quest to claim the sleeping bag.") },
}
local ROUTES = {}
for _, faction in ipairs({ "Alliance", "Horde" }) do
    local first, second, quest = WESTFALL, BARRENS, 79008
    if faction == "Horde" then first, second, quest = BARRENS, WESTFALL, 79007 end
    local route = {
        { map = first.map, x = first.x, y = first.y, nextQuest = quest, name = Suite.Text("Burned-Out Remains"),
            tip = faction == "Alliance"
                and Suite.Text("Search the remains by the wrecked cart at the Alexston Farmstead and accept the quest.")
                or Suite.Text("Search the remains at the ruined tower south of Camp Taurajo and accept the quest.") },
        { map = second.map, x = second.x, y = second.y, nextQuest = 79192, name = Suite.Text("Burned-Out Remains"),
            tip = faction == "Alliance"
                and Suite.Text("At the ruined tower south of Camp Taurajo, use the remains to turn in the note and accept the next quest.")
                or Suite.Text("Find the wrecked cart at the Alexston Farmstead. Use the remains there to turn in the note and accept the next quest.") },
    }
    for _, step in ipairs(COMMON) do route[#route + 1] = step end
    ROUTES[faction] = route
end

local function PlayerRoute()
    local faction = UnitFactionGroup("player")
    if Suite.Public(faction) then return ROUTES[faction] end
end

-- Get the current character's progress from Blizzard after login as well as
-- after quest updates. An unreadable flag defers selecting a new waypoint.
local function CurrentStep(route)
    if not route then return nil end
    for index = #route, 1, -1 do
        local step = route[index]
        local finished = C_QuestLog.IsQuestFlaggedCompleted(step.completedQuest or step.nextQuest)
        if not Suite.Public(finished) then return nil end
        if finished == true then return index + 1 end
        if step.nextQuest then
            local accepted = C_QuestLog.IsOnQuest(step.nextQuest)
            if not Suite.Public(accepted) then return nil end
            if accepted == true then return index + 1 end
        end
    end
    return 1
end

local function PlayerReady()
    local level = UnitLevel("player")
    return Suite.Finite(level) and level >= MIN_LEVEL
end

local function Destination(step)
    local name = step.name
    local mapInfo = C_Map.GetMapInfo(step.map)
    local zone = Suite.Public(mapInfo) and mapInfo and Suite.PublicText(mapInfo.name)
    return zone and ("%s (%s)"):format(name, zone) or name
end

local function Track(route, index)
    local step = route[index]
    if not Navigation.Select({ map = step.map, x = step.x, y = step.y, step = index,
        name = Destination(step), list = Suite.Text("Cozy Sleeping Bag") }, SOURCE) then return false end
    Suite.Print(step.tip)
    return true
end

function Navigation.StopSleepingBag()
    if Navigation.selectedSource ~= SOURCE then return false end
    local ownPin = Navigation.IsSelectedPoint(C_Map.GetUserWaypoint())
    Navigation.selected, Navigation.selectedSource = nil, nil
    if ownPin then C_Map.ClearUserWaypoint() end
    return true
end

local function Rows()
    local route, index = Guide.route, Guide.index
    local rows = {}
    for number, step in ipairs(route or {}) do
        rows[number] = { key = number, checked = index ~= nil and number < index,
            label = Destination(step), detail = step.tip }
    end
    return rows
end

local function Status()
    if not PlayerReady() then return Suite.Text("Available from level %d."):format(MIN_LEVEL) end
    local route, index = Guide.route, Guide.index
    if not index then return "" end
    if not route[index] then return Suite.Text("Sleeping bag quest chain complete.") end
    return Suite.Text("Next stop (%s)"):format(Destination(route[index]))
end

local function Start()
    local route = PlayerRoute()
    local index = CurrentStep(route)
    if not index or not route[index] or not PlayerReady() then return end
    Guide.route, Guide.index = route, index
    if Track(route, index) then
        window.selected = index
        Suite.ToolListWindow.Refresh(Guide)
    else
        window:SetStatus(Suite.Text("The waypoint could not be activated."))
    end
end

local function CanStart()
    local route, index = Guide.route, Guide.index
    return index ~= nil and route[index] ~= nil and PlayerReady()
end

local SPEC = { title = "Cozy Sleeping Bag", rows = Rows, status = Status,
    help = "Activate the current waypoint to follow the quest chain. Select a step to read its instructions.",
    actions = {
        { label = "Activate waypoint", enabled = CanStart, run = Start },
        { label = "Stop navigation", enabled = function() return Navigation.selectedSource == SOURCE end,
            run = function()
                Navigation.StopSleepingBag()
                Suite.ToolListWindow.Refresh(Guide)
            end },
    },
}

function Navigation.OpenSleepingBag()
    if not Navigation.owner or NS.InCombat() then return end
    local route = PlayerRoute()
    local index = CurrentStep(route)
    Guide.route, Guide.index = route, index
    window = Suite.ToolListWindow.Open(Guide, SPEC)
    if window then
        window.selected = index and math.min(index, #route)
        Suite.ToolListWindow.Refresh(Guide)
    end
    return window
end

function Navigation.RefreshSleepingBag()
    local tracking = Navigation.selectedSource == SOURCE
    local shown = Suite.ToolListWindow.IsOpen(Guide)
    if not (tracking or shown) or NS.InCombat() then return end
    local route = PlayerRoute()
    local index = CurrentStep(route)
    if tracking then
        local pin = C_Map.GetUserWaypoint()
        local followed = C_SuperTrack.IsSuperTrackingUserWaypoint()
        if not Suite.Public(pin) or not Suite.Public(followed) then return end
        if followed ~= true or not Navigation.IsSelectedPoint(pin) then
            Navigation.StopSleepingBag()
        elseif index and index ~= Navigation.selected.step then
            if not route[index] then
                Navigation.StopSleepingBag()
                Suite.Print(Suite.Text("Sleeping bag quest chain complete."))
            elseif not Track(route, index) then
                return -- Retry after the next quest or world update.
            end
            if shown then window.selected = math.min(index, #route) end
        end
    end
    if shown then
        Guide.route, Guide.index = route, index
        Suite.ToolListWindow.Refresh(Guide)
    end
end

function Navigation.DisableSleepingBag()
    Navigation.StopSleepingBag()
    Suite.ToolListWindow.Close(Guide)
    window = nil
end
