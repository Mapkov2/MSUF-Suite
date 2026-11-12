local _, P = ...
local NS, S = P.NS, P.Suite
local View = {}
P.LootRollView = View

local MAX_ROWS, GROW_UP = 12, 2
local ACTIONS = {
    { id = 1, label = "Need", flag = "canNeed", atlas = "lootroll-toast-icon-need-up" },
    { id = 2, label = "Greed", flag = "canGreed", atlas = "lootroll-toast-icon-greed-up" },
    { id = 4, label = "Transmog", flag = "canTransmog", atlas = "lootroll-toast-icon-transmog-up" },
    { id = 3, label = "Disenchant", flag = "canDisenchant" },
    { id = 0, label = "Pass", atlas = "lootroll-toast-icon-pass-up" },
}

-- The controller supplies public, sanitized records. No native roll readers,
-- event subscriptions or replacement of Blizzard controls live in this painter.
local function QualityColor(entry)
    local color = S.Finite(entry.quality) and ITEM_QUALITY_COLORS[entry.quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function HideTooltip(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function IsPreview(self)
    return self.previewParent ~= nil or self.showingSamples == true
end

local function ItemTooltip(button)
    local row = button.row
    if IsPreview(row.owner) or not row.entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if row.entry.link then GameTooltip:SetHyperlink(row.entry.link)
    else GameTooltip:SetText(row.entry.name or "") end
    GameTooltip:Show()
end

local function RollTooltip(button)
    local row, action = button.row, button.action
    local entry = row.entry
    if IsPreview(row.owner) or not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.Text(action.label))
    local names = entry.rollNames and entry.rollNames[action.id]
    if names and names ~= "" then
        GameTooltip:AddLine(names, 1, 1, 1, true)
    elseif not entry.counts or (entry.counts[action.id] or 0) > 0 then
        GameTooltip:AddLine(S.Text("Roll details are unavailable."), .7, .7, .7, true)
    else
        GameTooltip:AddLine(S.Text("No rolls yet."), .7, .7, .7, true)
    end
    GameTooltip:Show()
end

local function Choose(button)
    local row = button.row
    local owner, entry = row.owner, row.entry
    if IsPreview(owner) or not entry or not entry.rollID or entry.choice ~= nil or entry.cancelled or entry.finished then return end
    if button.action.id ~= 0 and entry[button.action.flag] ~= true then return end
    owner:Choose(entry, button.action.id)
end

local function Text(parent, justify)
    local region = S.CreateFontString(parent, nil, "OVERLAY")
    region:SetJustifyH(justify or "LEFT")
    region:SetWordWrap(false)
    return region
end

local function Edges(parent)
    local edges = {}
    for index = 1, 4 do edges[index] = S.CreateTexture(parent, nil, "BORDER") end
    return edges
end

local function NewAction(row, action)
    local button = S.CreateFrame("Button", nil, row.frame)
    button.row, button.action = row, action
    button:SetScript("OnClick", Choose)
    button:SetScript("OnEnter", RollTooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    icon:SetAllPoints(button)
    if action.atlas then
        icon:SetAtlas(action.atlas)
    else
        icon:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant")
        icon:SetTexCoord(.08, .92, .08, .92)
    end
    local highlight = S.CreateTexture(button, nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(1, 1, 1, .12)
    local count = Text(button, "CENTER")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -2)
    count:SetSize(17, 12)
    local backdrop = S.CreateTexture(button, nil, "ARTWORK")
    backdrop:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -2)
    backdrop:SetSize(17, 12)
    backdrop:SetColorTexture(0, 0, 0, .78)
    return { button = button, icon = icon, count = count, backdrop = backdrop, action = action }
end

local function NewRow(owner)
    local frame = S.CreateFrame("Frame", nil, owner.host)
    frame:EnableMouse(false)
    local row = { owner = owner, frame = frame, actions = {} }
    row.background = S.CreateTexture(frame, nil, "BACKGROUND")
    row.background:SetAllPoints(frame)
    row.border = Edges(frame)
    row.item = S.CreateFrame("Button", nil, frame)
    row.item.row = row
    row.item:SetScript("OnEnter", ItemTooltip)
    row.item:SetScript("OnLeave", HideTooltip)
    row.item:SetScript("OnHide", HideTooltip)
    row.icon = S.CreateTexture(row.item, nil, "ARTWORK")
    row.icon:SetAllPoints(row.item)
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.iconBorder = Edges(row.item)
    row.name, row.details, row.status = Text(frame), Text(frame), Text(frame)
    row.remaining = Text(frame, "RIGHT")
    row.timer = S.CreateFrame("StatusBar", nil, frame)
    row.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.timer:SetMinMaxValues(0, 1000)
    row.timer:EnableMouse(false)
    for _, action in ipairs(ACTIONS) do row.actions[#row.actions + 1] = NewAction(row, action) end
    frame:Hide()
    return row
end

function View.Create(self)
    if self.host then return end
    self.host = S.CreateFrame("Frame", nil, self.previewParent or UIParent)
    self.host:EnableMouse(false)
    if not self.previewParent then self.host:SetFrameStrata("HIGH") end
    self.rows = {}
    for index = 1, MAX_ROWS do self.rows[index] = NewRow(self) end
    self.host:Hide()
end

local function RowHeight(config)
    return math.max(config.rowHeight, config.fontSize + 43)
end

-- Element sizes, once per layout into one reused table: 0 keeps each
-- element's automatic size. Layout and paint read them; the tick never does.
local function Sizes(self)
    local config, sizes = self.config, self.sizes
    if not sizes then
        sizes = {}
        self.sizes = sizes
    end
    local height = RowHeight(config)
    sizes.icon = config.iconSize > 0 and config.iconSize or height - 12
    sizes.name = config.nameSize > 0 and config.nameSize or config.fontSize
    sizes.details = config.detailsSize > 0 and config.detailsSize or math.max(9, config.fontSize - 1)
    sizes.result = config.resultSize > 0 and config.resultSize or config.fontSize
    sizes.remaining = config.remainingSize > 0 and config.remainingSize or config.fontSize
    sizes.timer = config.timerSize > 0 and config.timerSize or 2
    sizes.button = config.buttonsSize > 0 and config.buttonsSize or 23
    return sizes
end

local function PlaceRow(self, row, index)
    local config, sizes = self.config, self.sizes
    local height, width = RowHeight(config), config.width
    local iconSize = sizes.icon
    row.frame:ClearAllPoints()
    local offset = (index - 1) * (height + config.rowGap)
    if config.growth == GROW_UP then
        row.frame:SetPoint("BOTTOMLEFT", self.host, "BOTTOMLEFT", 0, offset)
    else
        row.frame:SetPoint("TOPLEFT", self.host, "TOPLEFT", 0, -offset)
    end
    row.frame:SetSize(width, height)
    -- Element offsets (Options' X/Y editor) apply here, on layout only.
    row.item:ClearAllPoints()
    row.item:SetPoint("LEFT", row.frame, "LEFT", 6 + config.iconOffsetX, config.iconOffsetY)
    row.item:SetSize(iconSize, iconSize)
    local nameX, nameY = config.nameOffsetX, config.nameOffsetY - 6
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.frame, "TOPLEFT", iconSize + 14 + nameX, nameY)
    row.name:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", nameX - 39, nameY)
    row.name:SetHeight(sizes.name + 3)
    row.remaining:ClearAllPoints()
    row.remaining:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", config.remainingOffsetX - 7, config.remainingOffsetY - 6)
    row.remaining:SetSize(math.max(29, math.ceil(sizes.remaining * 2.4)), sizes.remaining + 3)
    row.details:ClearAllPoints()
    row.details:SetPoint("BOTTOMLEFT", row.frame, "BOTTOMLEFT", iconSize + 14 + config.detailsOffsetX, 10 + config.detailsOffsetY)
    row.details:SetHeight(sizes.details + 3)
    row.status:ClearAllPoints()
    row.status:SetPoint("BOTTOMLEFT", row.frame, "BOTTOMLEFT", iconSize + 14 + config.resultOffsetX, 10 + config.resultOffsetY)
    row.status:SetHeight(sizes.result + 2)
    local timerX, timerY = config.timerOffsetX, config.timerOffsetY + 4
    row.timer:ClearAllPoints()
    row.timer:SetPoint("BOTTOMLEFT", row.frame, "BOTTOMLEFT", 5 + timerX, timerY)
    row.timer:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", timerX - 5, timerY)
    row.timer:SetHeight(sizes.timer)
end

function View.Layout(self)
    View.Create(self)
    Sizes(self)
    local config = self.config
    local count = math.min(#self.visibleEntries, config.maxRows, MAX_ROWS)
    self.viewCount = count
    local height = math.max(1, count * RowHeight(config) + math.max(0, count - 1) * config.rowGap)
    self.host:SetSize(config.width, height)
    local viewport = self.previewViewport
    if viewport then
        self.host:SetScale(math.min(viewport.scale, viewport.width / config.width, viewport.height / height))
    else
        self.host:ClearAllPoints()
        local point = NS.AnchorPoints[config.point] or "CENTER"
        self.host:SetPoint(point, UIParent, point, config.x, config.y)
        self.host:SetScale(config.scale / 100)
    end
    for index = 1, count do PlaceRow(self, self.rows[index], index) end
end

local function StyleRow(self, row, entry)
    local config, palette = self.config, S.QoLStyle(self.config)
    local font = S.ResolveFont(config.font) or S.GlobalFontPath()
    local red, green, blue = S.RGB(palette.border)
    row.borderRed, row.borderGreen, row.borderBlue = red, green, blue
    S.QoLColor(row.background, palette.background, .94)
    S.PlaceEdges(row.border, row.frame, 1, red, green, blue, 1)
    row.urgent = false
    local qr, qg, qb = QualityColor(entry)
    S.PlaceEdges(row.iconBorder, row.item, 1, qr, qg, qb, 1)
    local sizes = self.sizes
    S.QoLStyleText(row.name, config, font, sizes.name)
    row.name:SetTextColor(qr, qg, qb)
    local tr, tg, tb = S.RGB(palette.text)
    local mr, mg, mb = S.RGB(palette.muted)
    S.QoLStyleText(row.details, config, font, sizes.details)
    row.details:SetTextColor(mr, mg, mb)
    S.QoLStyleText(row.status, config, font, sizes.result)
    row.status:SetTextColor(tr, tg, tb)
    S.QoLStyleText(row.remaining, config, font, sizes.remaining)
    row.remaining:SetTextColor(tr, tg, tb)
    local ar, ag, ab = S.RGB(palette.accent)
    row.timer:SetStatusBarColor(ar, ag, ab, 1)
    for _, action in ipairs(row.actions) do
        S.QoLStyleText(action.count, config, font, 9)
        action.count:SetTextColor(1, 1, 1)
    end
end

local function Details(config, entry)
    local text = ""
    if config.showItemLevel and S.Finite(entry.itemLevel) then
        text = string.format(S.Text("Item level %d"), entry.itemLevel)
    end
    if config.showBind and entry.bindOnPickUp then
        local bind = S.Text("Bind on pickup")
        text = text == "" and bind or text .. "  |  " .. bind
    end
    if S.Finite(entry.count) and entry.count > 1 then
        local count = string.format("x%d", entry.count)
        text = text == "" and count or text .. "  |  " .. count
    end
    return text
end

local function Actions(self, row, entry)
    local displayActions = (entry.rollID ~= nil or IsPreview(self)) and not entry.finished
    local actionable = displayActions and entry.choice == nil and not entry.cancelled
    local shown, buttonsX, buttonsY = 0, self.config.buttonsOffsetX - 9, self.config.buttonsOffsetY + 9
    local size = self.sizes.button
    local step = size + 6
    for index = #row.actions, 1, -1 do
        local action = row.actions[index]
        local eligible = action.action.id == 0 or entry[action.action.flag] == true
        local count = entry.counts and entry.counts[action.action.id]
        local counted = S.Finite(count) and count > 0
        local available = displayActions and (eligible or counted)
        action.button:SetShown(available)
        action.button:EnableMouse(available and not IsPreview(self))
        action.icon:SetAlpha(actionable and eligible and 1 or .6)
        if available then
            action.button:ClearAllPoints()
            action.button:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", buttonsX - shown * step, buttonsY)
            action.button:SetSize(size, size)
            local hasCount = self.config.showCounts and counted
            action.count:SetShown(hasCount)
            action.backdrop:SetShown(hasCount)
            if hasCount then action.count:SetText(count) end
            shown = shown + 1
        end
    end
    local width = math.max(1, self.config.width - self.sizes.icon - 30 - shown * step)
    row.details:SetWidth(width)
    row.status:SetWidth(width)
    row.details:SetShown(actionable)
    row.status:SetShown(not actionable)
    return actionable
end

local function TimerShown(row, shown)
    if row.timerShown == shown then return end
    row.timerShown = shown
    row.timer:SetShown(shown)
    row.remaining:SetShown(shown)
end

local function Urgency(row, urgent)
    if row.urgent == urgent then return end
    row.urgent = urgent
    local red, green, blue = row.borderRed, row.borderGreen, row.borderBlue
    if urgent then red, green, blue = 1, .16, .12 end
    for _, edge in ipairs(row.border) do edge:SetColorTexture(red, green, blue, 1) end
end

local function PaintCountdown(self, row, entry, left)
    left = math.max(0, left)
    if not row.maximum then
        row.maximum = math.max(1, S.Finite(entry.duration) and entry.duration or left)
    end
    local tick = math.ceil(left * 10)
    if row.timerTick ~= tick then
        row.timerTick = tick
        row.timer:SetValue(math.min(1000, 1000 * left / row.maximum))
    end
    local second = math.ceil(left)
    if row.timerSecond ~= second then
        row.timerSecond = second
        row.remaining:SetText(second)
    end
    Urgency(row, self.config.urgentTimer == true and left <= self.config.urgentSeconds)
end

local function PaintRow(self, row, entry)
    if row.entry ~= entry then
        row.maximum, row.timerTick, row.timerSecond = nil, nil, nil
    end
    row.entry = entry
    StyleRow(self, row, entry)
    row.icon:SetTexture(entry.icon or 134400)
    row.name:SetText(entry.name or "")
    row.details:SetText(Details(self.config, entry))
    local actionable = Actions(self, row, entry)
    row.status:SetText(entry.statusText or (not actionable and S.Text("Waiting for result") or ""))
    row.item:EnableMouse(not IsPreview(self))
    local staticTimer = IsPreview(self) and S.Finite(entry.remaining) and not entry.finished
    local hasTimer = (S.Finite(entry.endsAt) or staticTimer) and not entry.finished
    TimerShown(row, hasTimer)
    if staticTimer then PaintCountdown(self, row, entry, entry.remaining) end
    if not hasTimer then row.timerTick, row.timerSecond = nil, nil end
    row.frame:Show()
end

function View.Paint(self)
    View.Layout(self)
    for index, row in ipairs(self.rows) do
        local entry = index <= self.viewCount and self.visibleEntries[index]
        if entry then
            PaintRow(self, row, entry)
        else
            row.entry = nil
            row.frame:Hide()
        end
    end
    self.host:SetShown(self.viewCount > 0)
end

function View.Tick(self, now)
    local ticking = false
    for index = 1, self.viewCount or 0 do
        local row = self.rows[index]
        local entry = row.entry
        if entry and S.Finite(entry.endsAt) and not entry.finished then
            local left = math.max(0, entry.endsAt - now)
            ticking = ticking or left > 0
            PaintCountdown(self, row, entry, left)
        elseif entry and IsPreview(self) and S.Finite(entry.remaining) and not entry.finished then
            PaintCountdown(self, row, entry, entry.remaining)
        end
    end
    return ticking
end
