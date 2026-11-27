local _, NS = ...
local Number, String, Public = NS.Number, NS.String, NS.Public

-- The Statistics page reads every statistic of every category (26 categories,
-- about 170 rows). Its values change only with achievement criteria, so a
-- reopen or tab switch reuses the last complete read. Blizzard's own
-- StatisticsFrame refreshes on show and on CRITERIA_UPDATE
-- (Blizzard_Statistics/Camelot/StatisticsFrame.lua:97-110). The cache drops on
-- CRITERIA_UPDATE or RECEIVED_ACHIEVEMENT_LIST (AchievementInfoDocumentation.lua,
-- Forever and Retail). The watcher is registered only while a read is cached
-- and unregisters on its first event. An empty read is never cached: the
-- achievement data may not be loaded yet.
local Statistics = {}
NS.Statistics = Statistics
local cache = { groups = {} }
local watcher
-- Pages' buffer helpers, handed over by Statistics.Read.
local Group, Row

local function IsTable(value)
    return Public(value) and type(value) == "table"
end

local function ReadStatisticsCategory(buffer, category)
    local title = String(GetCategoryInfo(category))
    local count = Number(GetCategoryNumAchievements(category))
    if not title or not count or count < 1 then return end
    local group
    for index = 1, count do
        local quantity, skip, statistic = GetStatistic(category, index)
        statistic = Number(statistic)
        if Public(skip) and not skip and statistic then
            local name = String(select(2, GetAchievementInfo(statistic)))
            if name then
                group = group or Group(buffer, title)
                local value = String(quantity)
                local amount = Number(quantity) or (value and Number(tonumber(value)))
                Row(group, name, amount and amount > 0 and amount)
            end
        end
    end
end

local function ReadStatistics(buffer)
    local categories = GetStatisticsCategoryList()
    if not IsTable(categories) then return end
    -- Blizzard also handles sparse ordinal keys in the returned category list.
    local keys, count = buffer.keys, 0
    for index, category in pairs(categories) do
        if Number(index) and Number(category) then
            count = count + 1
            keys[count] = index
        end
    end
    for index = #keys, count + 1, -1 do keys[index] = nil end
    table.sort(keys)
    for index = 1, count do ReadStatisticsCategory(buffer, categories[keys[index]]) end
end

local function Invalidate(self)
    self:UnregisterAllEvents()
    cache.valid = nil
end

-- Fills groups with the cached statistics groups (shared, read-only) and
-- returns it, or returns nil when nothing could be read.
function Statistics.Read(groups, Buffer, group, row, Finish)
    if not cache.valid then
        Group, Row = group, row
        local buffer = Buffer(cache.groups)
        ReadStatistics(buffer)
        if buffer.count == 0 then return nil end
        Finish(buffer, cache.groups)
        if not watcher then
            watcher = CreateFrame("Frame")
            watcher:SetScript("OnEvent", Invalidate)
        end
        watcher:RegisterEvent("CRITERIA_UPDATE")
        watcher:RegisterEvent("RECEIVED_ACHIEVEMENT_LIST")
        cache.valid = true
    end
    local source = cache.groups
    for index = 1, #source do groups[index] = source[index] end
    for index = #groups, #source + 1, -1 do groups[index] = nil end
    return groups
end

-- The module stops: forget the read and stop listening.
function Statistics.Drop()
    if watcher then watcher:UnregisterAllEvents() end
    cache.valid = nil
end
