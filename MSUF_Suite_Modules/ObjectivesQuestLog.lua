local _, P = ...
local O, S = P.Objectives, P.Suite
local Finite, Public = S.Finite, S.Public
local Read = O.Read
local MIN = math.min
local DUNGEON = S.BlizzardText("DUNGEON", "Dungeon")

-- Snapshots keep the quest log's actual headers. A collapsed section can omit
-- its quests, so those entries can fall back to the quest's own map.
function O.ReadQuestLog(list, c)
    list.logUsage, list.namedSections, list.sectionByName = nil, nil, nil
    local headers = list.questHeaders
    if headers then for id in pairs(headers) do headers[id] = nil end end
    if not (c.groupQuestsByHeader or c.showQuestLogCount) then return end
    local count, accepted = C_QuestLog.GetNumQuestLogEntries()
    if c.showQuestLogCount then
        -- The total quota also covers hidden quests and world quests.
        local limit = Read(C_QuestLog.GetMaxNumQuestsCanAccept)
        if Finite(accepted) and Finite(limit) and limit > 0 then
            list.logUsage = ("%d/%d"):format(accepted, limit)
        end
    end
    if not c.groupQuestsByHeader then return end
    list.namedSections, list.sectionByName = {}, {}
    if not Finite(count) then return end
    headers = headers or {}
    list.questHeaders = headers
    local header
    for index = 1, MIN(count, 512) do
        local info = Read(C_QuestLog.GetInfo, index)
        if type(info) == "table" then
            if Public(info.isHeader) and info.isHeader then
                header = Public(info.title) and type(info.title) == "string" and info.title or nil
            elseif Finite(info.questID) and info.questID > 0 then
                headers[info.questID] = header
            end
        end
    end
end

local function Header(list, id)
    local header = list.questHeaders and list.questHeaders[id]
    if header then return header end
    local mapID = Read(GetQuestUiMapID, id, true)
    if not Finite(mapID) or mapID <= 0 then return end
    local info = Read(C_Map.GetMapInfo, mapID)
    if type(info) == "table" and Public(info.name) and type(info.name) == "string" then return info.name end
end

local function DifficultyColor(level)
    local color = Read(GetQuestDifficultyColor, level)
    if type(color) ~= "table" or not Finite(color.r) or not Finite(color.g) or not Finite(color.b) then return end
    local floor = math.floor
    return ("|cff%02x%02x%02x"):format(floor(color.r * 255 + .5), floor(color.g * 255 + .5), floor(color.b * 255 + .5))
end

local function AddToSection(list, entry)
    local header = Header(list, entry.id)
    if not header or header == "" then return end
    local section = list.sectionByName[header]
    if not section then
        local key = "questLog:" .. header
        section = { key = key, rowKey = "section:" .. key, title = header, entries = {} }
        list.sectionByName[header] = section
        list.namedSections[#list.namedSections + 1] = section
    end
    entry.questHeader = header
    section.entries[#section.entries + 1] = entry
end

function O.ApplyQuestLog(list, entry, c)
    local id = entry.id
    if c.groupQuestsByHeader then AddToSection(list, entry) end
    if c.showQuestLevel or c.questDifficultyColor then
        local level = Read(C_QuestLog.GetQuestDifficultyLevel, id)
        if Finite(level) and level > 0 then
            local label = c.showQuestLevel and ("[%d] %s"):format(level, entry.title) or entry.title
            local color = c.questDifficultyColor and DifficultyColor(level)
            entry.questLabel = color and (color .. label .. "|r") or label
        end
    end
    if c.showDungeonBadge then
        local tag = Read(C_QuestLog.GetQuestTagInfo, id)
        if type(tag) == "table" and Finite(tag.tagID) and tag.tagID == Enum.QuestTag.Dungeon then
            entry.dungeonBadge = DUNGEON
        end
    end
end

function O.PaintQuestBadge(self, row, item, inset)
    local badge = row.questBadge
    if not item.dungeonBadge then
        if badge then badge:Hide() end
        return inset
    end
    if not badge then
        badge = S.CreateFontString(row, nil, "OVERLAY")
        badge:SetJustifyH("RIGHT")
        row.questBadge = badge
    end
    S.SetStyledFont(badge, self.font, math.max(9, self.config.objectiveSize - 1), P.NS.HUDTextArgs(self.config))
    badge:SetText(item.dungeonBadge)
    badge:SetTextColor(unpack(self.mutedRGB))
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    badge:Show()
    local width = badge:GetStringWidth()
    return inset + (Finite(width) and width or 40) + 6
end

function O.PaintQuestProgress(self, row, item, inset, size)
    local label = row.questProgress
    if not item.progressText then
        if label then label:Hide() end
        return inset
    end
    if not label then
        label = S.CreateFontString(row, nil, "OVERLAY")
        label:SetJustifyH("RIGHT")
        row.questProgress = label
    end
    if row.progressTextRevision ~= self.textRevision then
        S.SetStyledFont(label, self.font, size, P.NS.HUDTextArgs(self.config))
        row.progressTextRevision = self.textRevision
    end
    label:SetText(item.progressText)
    label:SetTextColor(unpack(item.done and self.completeRGB or self.textRGB))
    label:ClearAllPoints()
    label:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    label:Show()
    local width = label:GetStringWidth()
    return inset + (Finite(width) and width or 40) + 8
end
