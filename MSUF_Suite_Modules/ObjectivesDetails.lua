local _, P = ...
local NS, S, O = P.NS, P.Suite, P.Objectives
local ITEM_SOURCES = { "quests", "world", "bonus" }
local SYMBOLS = { focused = "*", campaign = "C", important = "!", complete = "?", world = "W", bonus = "+", quests = "!" }

local function ScenarioHeaderShown(header)
    if header.desiredSetID then header:RegisterForWidgetSet(header.desiredSetID) end
end

local function ScenarioHeaderHidden(header)
    header:RegisterForWidgetSet(nil)
end

local function ScenarioHeaderSizeChanged(header)
    if header.desiredSetID and header:IsVisible() then
        header:GetParent().layoutHeight = nil
        O.RequestScenarioLayout()
    end
end

-- Keep Blizzard's Delve header: its tier, lives, rewards and spell tooltips
-- carry data that the scenario criteria do not expose (e.g. Nemesis groups).
-- The native container owns widget updates; Suite only reacts to size changes.
function O.PaintScenarioHeader(row, item, width)
    local setID = item.scenarioHeaderSetID
    local header = row.scenarioHeader
    if not setID then
        if header then
            header.desiredSetID = nil
            header:RegisterForWidgetSet(nil)
            header:Hide()
        end
        row.text:Show()
        return 0
    end
    if not header then
        header = S.CreateFrame("Frame", nil, row, "UIWidgetContainerTemplate")
        header.verticalAnchorPoint, header.verticalRelativePoint = "TOPLEFT", "TOPLEFT"
        header:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -3)
        header:HookScript("OnShow", ScenarioHeaderShown)
        header:HookScript("OnHide", ScenarioHeaderHidden)
        header:HookScript("OnSizeChanged", ScenarioHeaderSizeChanged)
        row.scenarioHeader = header
    end
    header.desiredSetID = setID
    header:RegisterForWidgetSet(setID)
    local headerWidth, headerHeight = header:GetWidth(), header:GetHeight()
    if headerWidth <= 0 or headerHeight <= 0 or not header:HasAnyWidgetsShowing() then
        row.text:Show()
        return 0
    end
    local scale = math.min(1, math.max(1, width - 42) / headerWidth)
    header:SetScale(scale)
    header:Show()
    row.text:Hide()
    row.collapse:ClearAllPoints()
    row.collapse:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
    return headerHeight * scale + 6
end

function O.ApplyHeading(self, c)
    local shown = c.showHeader ~= false
    self.title:SetShown(shown)
    self.count:SetShown(shown)
    self.divider:SetShown(shown)
    self.headerClick:SetShown(shown)
    local height = shown and math.max(40, (c.titleSize or 18) + 23) or 8
    if self.headerHeight ~= height then
        self.headerHeight = height
        self.divider:ClearAllPoints()
        self.divider:SetPoint("TOPLEFT", 11, 7 - height)
        self.divider:SetPoint("TOPRIGHT", -11, 7 - height)
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", 7, -height)
        self.scroll:SetPoint("BOTTOMRIGHT", -7, 5)
    end
end

-- A separate secure action keeps the ordinary tracker unprotected. Its item
-- changes only out of combat, from the same current entries the tracker uses.
function O.UpdateQuestItem(self, disabled)
    if NS.IsCombatLocked() then return end
    local link, focused
    if not disabled and self.active and self.config.showQuestItems ~= false then
        for i = 1, #ITEM_SOURCES do
            local list = self.sources[ITEM_SOURCES[i]]
            if list then
                for j = 1, list.count do
                    local entry = list[j]
                    if entry.itemLink and (not link or entry.group == "focused") then
                        link = entry.itemLink
                        if entry.group == "focused" then focused = true; break end
                    end
                end
            end
            if focused then break end
        end
    end
    local button = self.questItemShortcut
    if not button and link then
        button = S.CreateFrame("Button", "MSUFSuiteQuestItem", UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type1", "item")
        button:Hide()
        self.questItemShortcut = button
    end
    if button and button.itemLink ~= link then
        button:SetAttribute("item1", link)
        button.itemLink = link
    end
end

function O.PaintQuestIcon(self, row, item, c, color)
    local style = c.questIconStyle or 1
    local wanted = item.kind == "entry" and item.questID and style > 1
    if not wanted then
        if row.questBadge then row.questBadge:Hide() end
        if row.questIcon then row.questIcon:Hide() end
        return 12
    end
    if style == 2 then
        if not row.questBadge then
            row.questBadge = S.CreateFontString(row, nil, "OVERLAY")
            row.questBadge:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.questBadge:SetWidth(16)
        end
        S.SetStyledFont(row.questBadge, self.font, c.entrySize or 15, "OUTLINE", 1, true, 70, 1)
        row.questBadge:SetText(SYMBOLS[item.group] or "!")
        row.questBadge:SetTextColor(color[1], color[2], color[3])
        row.questBadge:Show()
        if row.questIcon then row.questIcon:Hide() end
    else
        if not item.questIcon then
            if row.questIcon then row.questIcon:Hide() end
            if row.questBadge then row.questBadge:Hide() end
            return 12
        end
        if not row.questIcon then
            row.questIcon = S.CreateTexture(row, nil, "ARTWORK")
            row.questIcon:SetPoint("LEFT", row, "LEFT", 10, 0)
        end
        if item.questIconAtlas then row.questIcon:SetAtlas(item.questIcon)
        else row.questIcon:SetTexture(item.questIcon) end
        row.questIcon:SetSize(16, 16)
        row.questIcon:Show()
        if row.questBadge then row.questBadge:Hide() end
    end
    return 31
end
