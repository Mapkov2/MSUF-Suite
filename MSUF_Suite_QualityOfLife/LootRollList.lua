local _, P = ...
local S = P.Suite
local History, Data = P.LootRollHistory, P.LootRollData
local List = {}
P.LootRollList = List

local PLAYER_WIDTH, HISTORY_WIDTH, ROW_HEIGHT = 348, 244, 24
local SIDE_POINTS = {
    { "TOPLEFT", "TOPRIGHT", 6, 0 }, { "TOPRIGHT", "TOPLEFT", -6, 0 },
    { "TOPLEFT", "BOTTOMLEFT", 0, -6 }, { "BOTTOMLEFT", "TOPLEFT", 0, 6 },
}

local function Text(parent, align)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    text:SetJustifyH(align or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function Button(parent, width, label, click)
    local button = S.CreateFrame("Button", nil, parent)
    button:SetSize(width, ROW_HEIGHT)
    local highlight = S.CreateTexture(button, nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, .12)
    button.label = Text(button, "CENTER")
    button.label:SetAllPoints()
    button.label.initialText = label
    button:SetScript("OnClick", click)
    return button
end

local function HideTooltip(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function ItemTooltip(button)
    if not button.entry or not button.entry.link then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(button.entry.link)
    if button.owner.config.showAuctionPrice then Data.AddAuctionPrice(GameTooltip, button.entry) end
    GameTooltip:Show()
end

local function ItemButton(parent, width, click)
    local button = Button(parent, width, "", click)
    button.label:SetJustifyH("LEFT")
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 29, 0)
    button.label:SetPoint("RIGHT", -4, 0)
    button.icon = S.CreateTexture(button, nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("LEFT", 5, 0)
    button:SetScript("OnEnter", ItemTooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
    return button
end

local function PaintItem(button, entry, fallback)
    if button.entry and (not entry or button.entry.link ~= entry.link) then HideTooltip(button) end
    button.entry = entry
    button.label:SetText(entry and entry.name or fallback)
    button.icon:SetShown(entry ~= nil)
    if entry then button.icon:SetTexture(entry.icon or 134400) end
end

local function MovePage(pane, delta)
    pane.offset = math.max(0, math.min(pane.total - #pane.rows, pane.offset + delta))
    pane.paint(pane.panel)
end

local function MakePane(panel, parent, width, count, paint)
    local pane = S.CreateFrame("Frame", nil, parent)
    pane:SetSize(width, count * ROW_HEIGHT + 82)
    pane:EnableMouse(true)
    pane:EnableMouseWheel(true)
    pane.rows, pane.panel, pane.paint, pane.offset, pane.total = {}, panel, paint, 0, 0
    pane:SetScript("OnMouseWheel", function(self, delta) MovePage(self, -delta) end)
    pane.previous = Button(pane, 26, "<", function() MovePage(pane, -#pane.rows) end)
    pane.previous:SetPoint("BOTTOMLEFT", 4, 4)
    pane.next = Button(pane, 26, ">", function() MovePage(pane, #pane.rows) end)
    pane.next:SetPoint("LEFT", pane.previous, "RIGHT", 33, 0)
    pane.range = Text(pane, "CENTER")
    pane.range:SetPoint("LEFT", pane.previous, "RIGHT")
    pane.range:SetPoint("RIGHT", pane.next, "LEFT")
    return pane
end

local function UpdatePage(pane, count)
    pane.total = count
    local size = #pane.rows
    pane.offset = math.max(0, math.min(pane.offset, count - size))
    pane.previous:SetShown(count > size)
    pane.next:SetShown(count > size)
    pane.previous:SetEnabled(pane.offset > 0)
    pane.next:SetEnabled(pane.offset + size < count)
    pane.range:SetText(count > size and ("%d/%d"):format(pane.offset + size, count) or "")
end

local function PlayerRow(pane, index)
    local row = S.CreateFrame("Frame", nil, pane)
    row:SetPoint("TOPLEFT", 6, -50 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", pane, "RIGHT", -6, 0)
    row:SetHeight(ROW_HEIGHT)
    row.background = S.CreateTexture(row, nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.icon = S.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetSize(15, 15)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name, row.choice, row.roll, row.wins = Text(row), Text(row, "CENTER"), Text(row, "RIGHT"), Text(row, "RIGHT")
    row.name:SetPoint("LEFT", 25, 0)
    row.name:SetPoint("RIGHT", row, "CENTER", -9, 0)
    row.wins:SetPoint("RIGHT", -5, 0)
    row.wins:SetWidth(41)
    row.roll:SetPoint("RIGHT", row.wins, "LEFT", -8, 0)
    row.roll:SetWidth(32)
    row.choice:SetPoint("LEFT", row.name, "RIGHT", 3, 0)
    row.choice:SetPoint("RIGHT", row.roll, "LEFT", -3, 0)
    return row
end

local function ClassIcon(row, player)
    local coords = player.class and CLASS_ICON_TCOORDS[player.class]
    row.icon:SetShown(coords ~= nil)
    if coords then
        row.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        row.icon:SetTexCoord(unpack(coords))
    end
end

local function PaintPlayer(panel, row, player, index)
    row:SetShown(player ~= nil)
    if not player then return end
    local config = panel.owner.config
    local wins = panel.owner.lootWins[player.key]
    ClassIcon(row, player)
    row.name:SetText(player.winner and S.Text("Winner: %s"):format(player.coloredName) or player.coloredName)
    row.choice:SetText(player.label)
    row.roll:SetText(player.roll or "")
    row.wins:SetText(wins or "")
    local highlighted = config.highlightExtremeRolls and (player.roll == 1 or player.roll == 100)
    if highlighted then row.roll:SetTextColor(1, .78, .2)
    else row.roll:SetTextColor(unpack(panel.textColor)) end
    if player.winner then row.background:SetColorTexture(.18, .46, .23, .40)
    else row.background:SetColorTexture(1, 1, 1, index % 2 == 1 and .04 or .08) end
end

local function PaintPlayers(panel)
    local entry, pane = panel.entry, panel.players
    local players = entry and entry.players
    local count = players and #players or 0
    UpdatePage(pane, count)
    for index, row in ipairs(pane.rows) do
        PaintPlayer(panel, row, players and players[index + pane.offset], index)
    end
    PaintItem(pane.item, entry, S.Text("Roll participants"))
    pane.result:SetText(entry and entry.statusText or "")
    pane.empty:SetText(entry and S.Text("Roll details are unavailable.") or "")
    pane.empty:SetShown(count == 0)
    if pane.share then pane.share:SetShown(entry and entry.finished == true and entry.link ~= nil or false) end
end

local function PaintArchive(panel)
    local pane, owner = panel.items, panel.owner
    local count = #owner.archiveOrder
    UpdatePage(pane, count)
    if not owner.archive[panel.token] then panel.token = owner.archiveOrder[count] end
    panel.entry = owner.archive[panel.token]
    pane.empty:SetShown(count == 0)
    for index, row in ipairs(pane.rows) do
        local token = owner.archiveOrder[count - pane.offset - index + 1]
        local entry = owner.archive[token]
        row:SetShown(entry ~= nil)
        PaintItem(row, entry)
        row.selected:SetShown(entry ~= nil and token == panel.token)
    end
    PaintPlayers(panel)
end

local function Style(panel, config)
    if panel.styled then return end
    panel.styled = true
    local palette = S.QoLStyle(config)
    local r, g, b = S.RGB(palette.background)
    panel.background:SetColorTexture(r, g, b, .98)
    r, g, b = S.RGB(palette.border)
    S.PlaceEdges(panel.edges, panel.frame, 1, r, g, b, 1)
    panel.textColor = { S.RGB(palette.text) }
    local font = S.ResolveFont(config.font) or S.GlobalFontPath()
    for _, region in ipairs(panel.texts) do
        S.QoLStyleText(region, config, font, math.min(13, config.fontSize))
        region:SetTextColor(unpack(panel.textColor))
        if region.initialText then region:SetText(region.initialText) end
    end
end

local function PreparePanel(owner, history)
    local parent = owner.previewParent
    local frame = S.CreateFrame("Frame", nil, parent or UIParent)
    if not parent then
        frame:SetFrameStrata(history and "DIALOG" or "HIGH")
        frame:SetFrameLevel(100)
        frame:SetClampedToScreen(true)
    end
    frame:Hide()
    local panel = { owner = owner, frame = frame, texts = {}, edges = {} }
    panel.background = S.CreateTexture(frame, nil, "BACKGROUND")
    panel.background:SetAllPoints()
    for index = 1, 4 do panel.edges[index] = S.CreateTexture(frame, nil, "BORDER") end
    if not parent then
        local close = Button(frame, 22, "X", function()
            if not history then owner:ToggleParticipants(panel.entry) else frame:Hide() end
        end)
        close:SetPoint("TOPRIGHT", -3, -4)
        close:SetFrameLevel(frame:GetFrameLevel() + 3)
        panel.texts[#panel.texts + 1] = close.label
    end
    return panel
end

local function StylePane(panel, pane)
    for _, region in ipairs({ pane.previous.label, pane.next.label, pane.range, pane.empty }) do
        panel.texts[#panel.texts + 1] = region
    end
end

local function CreateArchive(panel)
    local pane = MakePane(panel, panel.frame, HISTORY_WIDTH, 9, PaintArchive)
    pane:SetPoint("TOPLEFT")
    local title = Text(pane)
    title:SetPoint("TOPLEFT", 10, -11)
    pane.empty = Text(pane)
    pane.empty:SetPoint("TOPLEFT", 10, -44)
    pane.empty.initialText = S.Text("No loot rolls recorded yet.")
    title.initialText = S.Text("Loot roll history")
    panel.texts[#panel.texts + 1] = title
    for index = 1, 9 do
        local row = ItemButton(pane, HISTORY_WIDTH - 12, function(button)
            if not button.entry or History.Link(button.entry) then return end
            panel.token, panel.players.offset = button.entry.token, 0
            PaintArchive(panel)
        end)
        row.owner = panel.owner
        row:SetPoint("TOPLEFT", 6, -50 - (index - 1) * ROW_HEIGHT)
        row.selected = S.CreateTexture(row, nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(.25, .55, 1, .25)
        pane.rows[index] = row
        panel.texts[#panel.texts + 1] = row.label
    end
    StylePane(panel, pane)
    panel.items = pane
end

local function CreatePlayers(panel, history)
    local count = history and 9 or 6
    local pane = MakePane(panel, panel.frame, PLAYER_WIDTH, count, PaintPlayers)
    pane:SetPoint("TOPRIGHT")
    pane.item = ItemButton(pane, PLAYER_WIDTH - 35, function(button) History.Link(button.entry) end)
    pane.item.owner = panel.owner
    pane.item:SetPoint("TOPLEFT", 5, -3)
    pane.result = Text(pane)
    pane.result:SetPoint("TOPLEFT", 10, -32)
    pane.result:SetPoint("RIGHT", -59, 0)
    local wins = Text(pane, "RIGHT")
    wins:SetPoint("TOPRIGHT", -10, -32)
    wins.initialText = S.Text("Wins")
    pane.empty = Text(pane, "CENTER")
    pane.empty:SetPoint("CENTER")
    panel.texts[#panel.texts + 1] = pane.item.label
    panel.texts[#panel.texts + 1] = pane.result
    panel.texts[#panel.texts + 1] = wins
    if not panel.owner.previewParent then
        pane.share = Button(pane, 105, S.Text("Share result"), function() History.Share(panel.entry) end)
        pane.share:SetPoint("BOTTOMRIGHT", -6, 4)
        panel.texts[#panel.texts + 1] = pane.share.label
        if not history then
            local button = Button(pane, 98, S.Text("History"), function() panel.owner:ToggleRollHistory() end)
            button:SetPoint("RIGHT", pane.share, "LEFT", -4, 0)
            panel.texts[#panel.texts + 1] = button.label
        end
    end
    for index = 1, count do
        local row = PlayerRow(pane, index)
        pane.rows[index] = row
        for _, region in ipairs({ row.name, row.choice, row.roll, row.wins }) do
            panel.texts[#panel.texts + 1] = region
        end
    end
    StylePane(panel, pane)
    panel.players = pane
end

local function Create(owner, history)
    local panel = PreparePanel(owner, history)
    CreatePlayers(panel, history)
    panel.frame:SetSize(history and HISTORY_WIDTH + PLAYER_WIDTH or PLAYER_WIDTH, panel.players:GetHeight())
    if history then
        CreateArchive(panel)
        panel.frame:SetPoint("CENTER")
    end
    return panel
end

function List.DrawTest(owner, viewport)
    local panel = owner.rollListPanel
    if not panel then
        panel = Create(owner, false)
        owner.rollListPanel = panel
        panel.entry = owner.entry
        panel.frame:SetPoint("CENTER")
    end
    local frame = panel.frame
    if not frame:IsShown() then panel.players.offset = 0 end
    local config = owner.config
    panel.styled = nil
    Style(panel, config)
    frame:SetScale(math.min(config.participantsScale / 100, viewport.width / frame:GetWidth(),
        viewport.height / frame:GetHeight()))
    PaintPlayers(panel)
    frame:Show()
    return frame
end

function List.ToggleHistory(owner, recent)
    local panel = owner.rollHistoryPanel
    local latest = owner.archiveOrder[#owner.archiveOrder]
    if panel and panel.frame:IsShown() and (not recent or panel.token == latest and panel.items.offset == 0) then
        panel.frame:Hide()
        return
    end
    panel = panel or Create(owner, true)
    if recent then panel.token, panel.items.offset, panel.players.offset = latest, 0, 0 end
    owner.rollHistoryPanel = panel
    Style(panel, owner.config)
    PaintArchive(panel)
    panel.frame:Show()
end

local function AnchorSide(owner, frame)
    local selected = owner.config.participantsSide
    local left, bottom, width, height = owner.host:GetRect()
    if not left then return SIDE_POINTS[selected] or SIDE_POINTS[1] end
    local scale = UIParent:GetEffectiveScale()
    local hostScale, listScale = owner.host:GetEffectiveScale() / scale, frame:GetEffectiveScale() / scale
    local screenWidth, screenHeight = UIParent:GetSize()
    local neededWidth, neededHeight = (frame:GetWidth() + 6) * listScale, (frame:GetHeight() + 6) * listScale
    local space = {
        screenWidth - (left + width) * hostScale - neededWidth,
        left * hostScale - neededWidth,
        bottom * hostScale - neededHeight,
        screenHeight - (bottom + height) * hostScale - neededHeight,
    }
    local best = selected or 1
    if space[best] < 0 then
        for index, free in ipairs(space) do
            if free > space[best] then best = index end
        end
    end
    return SIDE_POINTS[best]
end

local function ShowParticipants(owner, entry)
    local panel = owner.rollListPanel or Create(owner, false)
    owner.rollListPanel = panel
    if panel.key ~= (entry.rollID or entry.token) then panel.players.offset = 0 end
    panel.entry, panel.key = entry, entry.rollID or entry.token
    local frame = panel.frame
    Style(panel, owner.config)
    frame:SetScale(owner.config.participantsScale / 100)
    local side = AnchorSide(owner, frame)
    frame:ClearAllPoints()
    frame:SetPoint(side[1], owner.host, side[2], side[3], side[4])
    PaintPlayers(panel)
    frame:Show()
end

function List.Update(owner, blocked)
    local panel = owner.rollHistoryPanel
    if panel and panel.frame:IsShown() then
        if blocked then
            panel.frame:Hide()
        else
            Style(panel, owner.config)
            PaintArchive(panel)
        end
    end
    if not blocked then
        local first, selected
        for _, entry in ipairs(owner.visibleEntries) do
            if owner.openRoll ~= nil and (entry.rollID or entry.token) == owner.openRoll then
                selected = entry
            end
            if not first and entry.players then first = entry end
        end
        owner.firstRollListKey = first and (first.rollID or first.token)
        if selected then return ShowParticipants(owner, selected) end
        if first and (owner.config.showParticipants or owner.showingTest) and owner.rollListClosed ~= owner.firstRollListKey then
            return ShowParticipants(owner, first)
        end
        if #owner.visibleEntries == 0 then owner.rollListClosed = nil end
    end
    if owner.rollListPanel then owner.rollListPanel.frame:Hide() end
    owner.openRoll, owner.firstRollListKey = nil, nil
end

function List.Invalidate(owner)
    if owner.rollListPanel then owner.rollListPanel.styled = nil end
    if owner.rollHistoryPanel then owner.rollHistoryPanel.styled = nil end
end
