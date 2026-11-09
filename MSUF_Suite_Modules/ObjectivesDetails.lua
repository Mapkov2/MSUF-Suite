local _, P = ...
local NS, S, O = P.NS, P.Suite, P.Objectives
local ITEM_SOURCES = { "quests", "world", "bonus" }
local SYMBOLS = { focused = "*", campaign = "C", important = "!", complete = "?", world = "W", bonus = "+", quests = "!" }

local function ScenarioHeaderShown(header)
    if header.desiredSetID then header:RegisterForWidgetSet(header.desiredSetID) end
end

local function ScenarioHeaderHidden(header)
    header.layoutRetry = nil
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
function O.PaintScenarioHeader(row, item, width, rowHeight)
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
        -- Match the native StageBlock: stage-set widgets share the same corner.
        header.verticalAnchorPoint, header.verticalRelativePoint = "TOPLEFT", "TOPLEFT"
        header:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -3)
        header:HookScript("OnShow", ScenarioHeaderShown)
        header:HookScript("OnHide", ScenarioHeaderHidden)
        header:HookScript("OnSizeChanged", ScenarioHeaderSizeChanged)
        row.scenarioHeader = header
    end
    if header.desiredSetID ~= setID then header.layoutRetry = nil end
    header.desiredSetID = setID
    if rowHeight then
        -- Native ResizeLayout needs a sized, shown row before reading its rect.
        row:SetHeight(rowHeight)
        row:Show()
    end
    header:RegisterForWidgetSet(setID)
    header:Show()
    local headerWidth, headerHeight = header:GetWidth(), header:GetHeight()
    local hasWidgets = header:HasAnyWidgetsShowing()
    -- ResizeLayout returns 1x1 while GetScaledRect is unresolved. Keep its
    -- children transparent until one deferred native layout has valid extents.
    if headerWidth <= 1 or headerHeight <= 1 or not hasWidgets then
        header:SetAlpha(0)
        if hasWidgets and not header.layoutRetry then
            header.layoutRetry = true
            header:MarkDirty()
        end
        row.text:Show()
        return 0
    end
    header.layoutRetry = nil
    header:SetAlpha(1)
    local scale = math.min(1, math.max(1, width - 42) / headerWidth)
    header:SetScale(scale)
    row.text:Hide()
    row.collapse:ClearAllPoints()
    row.collapse:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
    return headerHeight * scale + 6
end

-- One clipped body drives the objective lines and the rows below them. Their
-- anchors follow the body's height in the client; the tick never walks rows.
local function AnchorQuestRow(row, target, point, offset)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", target, point, 0, offset)
end

local function PaintQuestMotion(body, height)
    body.heightNow = height
    body:SetHeight(math.max(.01, height))
    local self = body.tracker
    local contentHeight = body.baseHeight + height
    self.content:SetHeight(contentHeight)
    local hostHeight = math.min(body.maxHeight, math.max(body.minHeight, contentHeight + body.chrome))
    if body.hostHeight ~= hostHeight then
        body.hostHeight = hostHeight
        self.host:SetHeight(hostHeight)
    end
end

function O.StopQuestMotion(self, layoutChanged)
    local body = self.questMotion
    if not body or not body.owner then return false end
    body:SetScript("OnUpdate", nil)
    local flat = body.flat
    for i = body.first, #flat do
        local row = self.rows[flat[i].key]
        if i <= body.last then
            row:SetParent(self.content)
            row:EnableMouse(true)
        end
        AnchorQuestRow(row, self.content, "TOPLEFT", -row.layoutY)
    end
    if not layoutChanged and body.heightNow ~= body.fullHeight then PaintQuestMotion(body, body.fullHeight) end
    body.owner, body.flat, body.refreshAfter = nil, nil, nil
    body:Hide()
    return true
end

local function StepQuestMotion(body, elapsed)
    body.elapsed = body.elapsed + elapsed
    local progress = body.elapsed / body.duration
    if progress >= 1 then
        if body.targetHeight == 0 or body.refreshAfter then O.Render(body.tracker, true) end
        if body.owner then O.StopQuestMotion(body.tracker) end
        return
    end
    local eased = progress * progress * (3 - 2 * progress)
    PaintQuestMotion(body, body.startHeight + (body.targetHeight - body.startHeight) * eased)
end

function O.AimQuestMotion(body, closing)
    body.startHeight, body.targetHeight = body.heightNow, closing and 0 or body.fullHeight
    body.elapsed, body.duration = 0, closing and .150 or .200
    body.owner.collapse.glyph:SetText(closing and "+" or "-")
end

function O.StartQuestMotion(self, owner, closing)
    local flat = self.previousFlat
    if not flat then return end
    local first
    for i = 1, #flat do
        if self.rows[flat[i].key] == owner then
            first = i + 1
            break
        end
    end
    if not first or not flat[first] or flat[first].kind ~= "line" then return end
    local last = first
    while flat[last + 1] and flat[last + 1].kind == "line" do last = last + 1 end
    local firstRow, lastRow = self.rows[flat[first].key], self.rows[flat[last].key]
    local top, bottom = firstRow.layoutY, lastRow.layoutY + lastRow.layoutHeight
    local body = self.questMotion
    if not body then
        body = S.CreateFrame("Frame", nil, self.content)
        body:SetClipsChildren(true)
        body.tracker = self
        self.questMotion = body
    end
    body.owner, body.flat, body.first, body.last = owner, flat, first, last
    body.fullHeight = bottom - top
    body.baseHeight = self.content:GetHeight() - body.fullHeight
    body.chrome = self.headerHeight + 5
    body.maxHeight = self.config.height
    body.minHeight = S.editMode and 160 or body.chrome
    body.hostHeight = self.host:GetHeight()
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -top)
    body:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -top)
    PaintQuestMotion(body, closing and body.fullHeight or 0)
    body:Show()
    for i = first, last do
        local row = self.rows[flat[i].key]
        row:EnableMouse(false)
        row:SetParent(body)
        AnchorQuestRow(row, body, "TOPLEFT", top - row.layoutY)
    end
    for i = last + 1, #flat do
        local row = self.rows[flat[i].key]
        AnchorQuestRow(row, body, "BOTTOMLEFT", bottom - row.layoutY)
    end
    O.AimQuestMotion(body, closing)
    body:SetScript("OnUpdate", StepQuestMotion)
    return true
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
                        if entry.group == "focused" then
                            focused = true
                            break
                        end
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
        S.SetStyledFont(row.questBadge, self.font, c.entrySize or 15, NS.HUDTextArgs(c))
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
        if item.questIconAtlas then
            row.questIcon:SetAtlas(item.questIcon)
        else
            row.questIcon:SetTexture(item.questIcon)
        end
        row.questIcon:SetSize(16, 16)
        row.questIcon:Show()
        if row.questBadge then row.questBadge:Hide() end
    end
    return 31
end
