local _, P = ...
-- Sorting and user moves operate on headers from the existing quest snapshot.
local O, S, NS = P.Objectives, P.Suite, P.NS
local ALPHABET, LEVEL, CUSTOM = 2, 3, 4

local function CustomOrder(config)
    local names, positions = {}, {}
    for title in (config.questZoneOrder or ""):gmatch("[^\n]+") do
        if not positions[title] and #names < 40 then
            names[#names + 1] = title
            positions[title] = #names
        end
    end
    return names, positions
end

function O.SortQuestGroups(source, config)
    local sections, mode = source.namedSections, config.questZoneSort
    if not sections or #sections < 2 then return end
    if (not mode or mode == 1) and not config.questCurrentZoneFirst then return end
    local _, positions
    if mode == CUSTOM then _, positions = CustomOrder(config) end
    table.sort(sections, function(a, b)
        if config.questCurrentZoneFirst and a.localZone ~= b.localZone then return a.localZone end
        if mode == ALPHABET and a.title ~= b.title then
            local compare = strcmputf8i and strcmputf8i(a.title, b.title)
            if compare and compare ~= 0 then return compare < 0 end
            return a.title < b.title
        end
        if mode == LEVEL and a.level ~= b.level then return a.level < b.level end
        if positions then
            local first, second = positions[a.title] or 41, positions[b.title] or 41
            if first ~= second then return first < second end
        end
        return a.ordinal < b.ordinal
    end)
end

local function Move(self, picked, target)
    local source = self.sources.quests
    local sections = source and source.namedSections
    if not sections or NS.InCombat() or picked == target then return end
    local names, seen, at, to = {}, {}
    for index, section in ipairs(sections) do
        names[index], seen[section.title] = section.title, true
        if section.key == picked then at = index end
        if section.key == target then to = index end
    end
    if not at or not to then return end
    if self.config.questCurrentZoneFirst and sections[at].localZone ~= sections[to].localZone then return end
    table.insert(names, to, table.remove(names, at))
    local saved = CustomOrder(self.config)
    for _, title in ipairs(saved) do
        if not seen[title] and #names < 40 then names[#names + 1] = title end
    end
    S.SetMany("objectives", { questZoneSort = CUSTOM, questZoneOrder = table.concat(names, "\n") })
end

local function SectionKey(button)
    local key = button.kind == "section" and button.collapseKey
    return key and key:sub(1, 9) == "questLog:" and key or nil
end

function O.QuestGroupMenu(self, button)
    local key = SectionKey(button)
    local source = self.sources.quests
    local sections = source and source.namedSections
    if not key or not sections or #sections < 2 or NS.InCombat() then return false end
    for index, section in ipairs(sections) do
        if section.key == key then
            local earlier, later = sections[index - 1], sections[index + 1]
            if self.config.questCurrentZoneFirst then
                if earlier and earlier.localZone ~= section.localZone then earlier = nil end
                if later and later.localZone ~= section.localZone then later = nil end
            end
            if not earlier and not later then return false end
            S.ContextMenu(button, function(_, root)
                if earlier then root:CreateButton(S.Text("Move group up"), function() Move(self, key, earlier.key) end) end
                if later then root:CreateButton(S.Text("Move group down"), function() Move(self, key, later.key) end) end
            end)
            return true
        end
    end
    return false
end

local function Start(self, button)
    if NS.InCombat() then return end
    self.dragZone = SectionKey(button)
end

local function Stop(self)
    local key = self.dragZone
    self.dragZone = nil
    if not key or NS.InCombat() then return end
    for _, row in pairs(self.rows) do
        local target = SectionKey(row)
        if target and row:IsVisible() and row:IsMouseOver() then
            Move(self, key, target)
            return
        end
    end
end

function O.BindQuestGroupDrag(self, button)
    local enabled = SectionKey(button) ~= nil
    if enabled == (button.questDrag == true) then return end
    button.questDrag = enabled or nil
    if enabled then
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", function(row) Start(self, row) end)
        button:SetScript("OnDragStop", function() Stop(self) end)
    else
        button:RegisterForDrag()
        button:SetScript("OnDragStart", nil)
        button:SetScript("OnDragStop", nil)
    end
end

function O.CombatFocus(self, source, config)
    if not config.focusQuestInCombat or not self.focusCombat or S.editMode or not source then return end
    local focus = source.focus
    if focus == nil then return end
    for i = 1, source.count do
        if source[i].id == focus then
            self.focusRows = self.focusRows or {}
            self.focusRows[1] = source[i]
            return self.focusRows
        end
    end
end
