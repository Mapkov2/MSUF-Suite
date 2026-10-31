local _, P = ...
local O = P.Objectives

-- Reused display records for the objective tracker; no widget or client writes.
local function FlatSlot(flat, index)
    local item = flat[index]
    if not item then
        item = {}
        flat[index] = item
    end
    -- Both flat buffers survive refreshes. Clear fields that belong to another row kind.
    item.key, item.kind, item.group, item.text, item.height = nil, nil, nil, nil, nil
    item.collapsed, item.menuTitle, item.tracked, item.itemIcon, item.itemLink = nil, nil, nil, nil, nil
    item.findGroup, item.questGroupSearch = nil, nil
    item.questIcon, item.questIconAtlas = nil, nil
    item.scenarioHeaderSetID = nil
    item.timerEnd, item.hasLines, item.collapseKey = nil, nil, nil
    item.questID, item.achievementID, item.scenarioID = nil, nil, nil
    item.recipeID, item.isRecraft = nil, nil
    item.contentID, item.contentType = nil, nil
    item.done, item.percent = nil, nil
    return item
end

-- The groups whose entries are not quests: their ids are no quest ids.
local NOT_QUEST_GROUPS = {
    achievements = true, scenario = true, recipes = true,
    travelersLog = true, endeavors = true, collectibles = true, zone = true,
}

-- Row keys are cached per entry so an unchanged tracker builds no strings.
local function EntryBase(entry, group)
    if entry.keyGroup ~= group or entry.keyID ~= entry.id then
        entry.keyGroup, entry.keyID = group, entry.id
        entry.base = group .. ":" .. tostring(entry.id)
        entry.entryKey = "entry:" .. entry.base
        local lineKeys = entry.lineKeys or {}
        for j = #lineKeys, 1, -1 do lineKeys[j] = nil end
        entry.lineKeys = lineKeys
    end
    return entry.base
end

local function LineKey(entry, index)
    local key = entry.lineKeys[index]
    if not key then
        key = "line:" .. entry.base .. ":" .. index
        entry.lineKeys[index] = key
    end
    return key
end

local function AddFlat(flat, index, group, items, c, collapsedGroups, collapsedEntries, groups, sectionKeys)
    if #items == 0 then return index end
    index = index + 1
    local section = FlatSlot(flat, index)
    section.key, section.kind, section.group = sectionKeys[group], "section", group
    section.text = groups[group][1]
    section.height = math.max(23, (c.sectionSize or 14) + 12)
    section.collapsed = collapsedGroups[group] == true
    if collapsedGroups[group] then return index end
    local entryHeight = math.max(32, (c.entrySize or 15) + 19)
    local objectiveSize = c.objectiveSize or 13
    for i = 1, #items do
        local entry = items[i]
        local base = EntryBase(entry, group)
        local questID = not NOT_QUEST_GROUPS[group] and entry.id > 0 and entry.id or nil
        local achievementID = group == "achievements" and entry.id or nil
        local scenarioID = group == "scenario" and entry.scenarioID or nil
        local lines = entry.lines
        index = index + 1
        local item = FlatSlot(flat, index)
        item.key, item.kind, item.group = entry.entryKey, "entry", group
        item.text, item.height = entry.title, entryHeight
        item.menuTitle, item.tracked = entry.title, entry.tracked
        item.itemIcon, item.itemLink, item.timerEnd = entry.itemIcon, entry.itemLink, entry.timerEnd
        item.questIcon, item.questIconAtlas = entry.questIcon, entry.questIconAtlas
        item.scenarioHeaderSetID = entry.scenarioHeaderSetID
        item.findGroup, item.questGroupSearch = entry.findGroup, entry.questGroupSearch
        item.hasLines, item.collapsed, item.collapseKey = lines.count > 0, collapsedEntries[base] == true, base
        item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
        item.recipeID, item.isRecraft = entry.recipeID, entry.isRecraft
        item.contentID, item.contentType = entry.contentID, entry.contentType
        if not collapsedEntries[base] then
            for j = 1, lines.count do
                local line = lines[j]
                index = index + 1
                item = FlatSlot(flat, index)
                item.key, item.kind, item.group = LineKey(entry, j), "line", group
                item.text, item.done, item.percent = line.text, line.done, line.percent
                item.menuTitle, item.tracked = entry.title, entry.tracked
                item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
                item.recipeID, item.isRecraft = entry.recipeID, entry.isRecraft
                item.contentID, item.contentType = entry.contentID, entry.contentType
                item.height =math.max(line.percent and 28 or 24, objectiveSize + (line.percent and 17 or 13))
            end
        end
    end
    return index
end

local function SameItem(a, b)
    return b and a.key == b.key and a.kind == b.kind and a.group == b.group
        and a.text == b.text and a.height == b.height and a.done == b.done
        and a.percent == b.percent and a.tracked == b.tracked
        and a.questID == b.questID and a.achievementID == b.achievementID
        and a.recipeID == b.recipeID and a.isRecraft == b.isRecraft
        and a.contentID == b.contentID and a.contentType == b.contentType
        and a.scenarioID == b.scenarioID and a.collapsed == b.collapsed
        and a.itemIcon == b.itemIcon and a.itemLink == b.itemLink and a.timerEnd == b.timerEnd
        and a.questIcon == b.questIcon and a.questIconAtlas == b.questIconAtlas
        and a.scenarioHeaderSetID == b.scenarioHeaderSetID
        and a.findGroup == b.findGroup and a.questGroupSearch == b.questGroupSearch
        and a.hasLines == b.hasLines and a.menuTitle == b.menuTitle
        and a.collapseKey == b.collapseKey
end

O.FlatSlot, O.EntryBase, O.AddFlat, O.SameItem = FlatSlot, EntryBase, AddFlat, SameItem
