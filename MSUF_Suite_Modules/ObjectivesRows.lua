local _, P = ...
local O, S = P.Objectives, P.Suite

-- Reused display records for the objective tracker.
local function FlatSlot(flat, index, kind)
    local item = flat[index]
    if not item then
        item = {}
        flat[index] = item
        return item
    end
    -- A regular row writes all its fields on reuse. The preview and kind changes clear the old fields.
    if kind and item.kind == kind then return item end
    item.key, item.kind, item.group, item.text, item.height = nil, nil, nil, nil, nil
    item.collapsed, item.menuTitle, item.tracked, item.itemIcon, item.itemLink = nil, nil, nil, nil, nil
    item.progressText = nil
    item.findGroup, item.questGroupSearch, item.dungeonBadge = nil, nil, nil
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

local function AddFlat(flat, index, group, items, c, collapsedGroups, collapsedEntries, groups, sectionKeys, closingKey, zone)
    if #items == 0 then return index end
    index = index + 1
    local section = FlatSlot(flat, index, "section")
    local groupKey = zone and zone.key or group
    section.key, section.kind, section.group = zone and zone.rowKey or sectionKeys[group], "section", group
    section.collapseKey, section.collapsed = groupKey, collapsedGroups[groupKey] == true
    section.text = zone and zone.title or groups[group][1]
    local compact = c.compactQuestRows
    section.height = math.max(compact and 18 or 23, (c.sectionSize or 14) + (compact and 6 or 12))
    if section.collapsed then return index end
    local entryHeight = math.max(compact and 23 or 32, (c.entrySize or 15) + (compact and 8 or 19))
    local objectiveSize = c.objectiveSize or 13
    local objectiveHeight = compact and math.max(16, objectiveSize + 5) or math.max(24, objectiveSize + 13)
    local progressHeight = math.max(28, objectiveSize + 17)
    for i = 1, #items do
        local entry = items[i]
        local group = zone and entry.group or group
        local base = EntryBase(entry, group)
        local questID = not NOT_QUEST_GROUPS[group] and entry.id > 0 and entry.id or nil
        local achievementID = group == "achievements" and entry.id or nil
        local scenarioID = group == "scenario" and entry.scenarioID or nil
        local lines = entry.lines
        index = index + 1
        local item = flat[index]
        if not item or item.kind ~= "entry" then item = FlatSlot(flat, index) end
        item.key, item.kind, item.group = entry.entryKey, "entry", group
        item.text, item.height = entry.questLabel or entry.title, entryHeight
        item.dungeonBadge = entry.dungeonBadge
        item.menuTitle, item.tracked = entry.title, entry.tracked
        item.itemIcon, item.itemLink, item.timerEnd = entry.itemIcon, entry.itemLink, entry.timerEnd
        item.questIcon, item.questIconAtlas = entry.questIcon, entry.questIconAtlas
        item.scenarioHeaderSetID = entry.scenarioHeaderSetID
        item.findGroup, item.questGroupSearch = entry.findGroup, entry.questGroupSearch
        local collapsed = collapsedEntries[base] == true and base ~= closingKey
        item.hasLines, item.collapsed, item.collapseKey = lines.count > 0, collapsed, base
        item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
        item.recipeID, item.isRecraft = entry.recipeID, entry.isRecraft
        item.contentID, item.contentType = entry.contentID, entry.contentType
        if not collapsed then
            local lineKeys = entry.lineKeys
            for j = 1, lines.count do
                local line = lines[j]
                local key = lineKeys[j]
                if not key then
                    key = "line:" .. base .. ":" .. j
                    lineKeys[j] = key
                end
                index = index + 1
                item = flat[index]
                if not item or item.kind ~= "line" then item = FlatSlot(flat, index) end
                item.key, item.kind, item.group = key, "line", group
                item.text, item.done, item.percent, item.progressText = line.text, line.done, line.percent, line.progressText
                item.menuTitle, item.tracked = entry.title, entry.tracked
                item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
                item.recipeID, item.isRecraft = entry.recipeID, entry.isRecraft
                item.contentID, item.contentType = entry.contentID, entry.contentType
                item.height = line.percent and progressHeight or objectiveHeight
            end
        end
    end
    return index
end

local function SameItem(a, b, ignoreDeadline)
    if not b or a.key ~= b.key or a.kind ~= b.kind or a.group ~= b.group
        or a.text ~= b.text or a.height ~= b.height then return false end
    if a.kind == "section" then return a.collapsed == b.collapsed end
    if a.tracked ~= b.tracked or a.menuTitle ~= b.menuTitle
        or a.questID ~= b.questID or a.achievementID ~= b.achievementID
        or a.recipeID ~= b.recipeID or a.isRecraft ~= b.isRecraft
        or a.contentID ~= b.contentID or a.contentType ~= b.contentType
        or a.scenarioID ~= b.scenarioID then return false end
    if a.kind == "line" then return a.done == b.done and a.percent == b.percent and a.progressText == b.progressText end
    return a.itemIcon == b.itemIcon and a.itemLink == b.itemLink
        and (a.timerEnd == b.timerEnd or (ignoreDeadline and a.timerEnd and b.timerEnd))
        and a.questIcon == b.questIcon and a.questIconAtlas == b.questIconAtlas
        and a.scenarioHeaderSetID == b.scenarioHeaderSetID
        and a.findGroup == b.findGroup and a.questGroupSearch == b.questGroupSearch and a.dungeonBadge == b.dungeonBadge
        and a.hasLines == b.hasLines and a.collapsed == b.collapsed and a.collapseKey == b.collapseKey
end

function O.StyleRowText(self, text, size)
    if text.msufRowSize == size and text.msufRowFont == self.textRevision then return end
    text.msufRowSize, text.msufRowFont = size, self.textRevision
    S.SetStyledFont(text, self.font, size, unpack(self.rowFontArgs, 1, 5))
end

function O.AnchorRowWidget(widget, row, inset)
    if widget.msufRowInset == inset then return end
    widget.msufRowInset = inset
    widget:ClearAllPoints()
    widget:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
end

function O.AnchorRow(self, row, width, y)
    local styleChanged = row.layoutRevision ~= self.textRevision
    if styleChanged or row.layoutY ~= y then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    end
    if styleChanged or row.layoutWidth ~= width then row:SetWidth(width) end
    row.layoutY, row.layoutWidth, row.layoutRevision = y, width, self.textRevision
end

function O.MeasureRowText(self, row, item, width, left, right)
    local textWidth = math.max(1, width - left - right - 2)
    local styleChanged = row.measureRevision ~= self.textRevision or row.measureSize ~= row.text.msufRowSize
    if styleChanged or row.measureLeft ~= left then
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", left, 0)
    end
    -- An explicit width lets the height read measure the current wrap.
    if styleChanged or row.measureWidth ~= textWidth then row.text:SetWidth(textWidth) end
    if styleChanged or row.measureWidth ~= textWidth or row.measureText ~= item.text or not row.measureHeight then
        local height = row.text:GetStringHeight()
        row.measureHeight = S.Finite(height) and height > 0 and height + self.rowPadding or nil
        row.measureText, row.measureRevision = item.text, self.textRevision
        row.measureSize, row.measureWidth = row.text.msufRowSize, textWidth
    end
    row.measureLeft = left
    return math.max(item.height, row.measureHeight or 0)
end

O.FlatSlot, O.EntryBase, O.AddFlat, O.SameItem = FlatSlot, EntryBase, AddFlat, SameItem
