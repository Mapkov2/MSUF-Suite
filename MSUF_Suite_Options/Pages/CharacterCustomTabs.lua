local _, P = ...
local Suite, S, T, Tr, HM = P.Suite, P.S, P.T, P.Tr, P.HM
local Model, Header, Interaction = Suite.CharacterTabs, S.CharacterHeader, P.PreviewInteraction
local ID, KEY = "characterPanel", "customTabs"
local CARD, ROW = "card", "row"
local GAP, HEADER, LINE = 5, 25, 23
local CARD_VIEWPORT, SCROLL_GUTTER = 210, 18
local Picker = P.CharacterSourcePicker
local Content = {}
Content.__index = Content
P.CharacterCustomTabs = Content

local function Position(frame, parent, x, y, width)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    frame:SetWidth(width)
end

local function Label(widget, text)
    if widget.customText ~= text then
        widget.customText = text
        P.SetButtonText(widget, text)
    end
end

local function Button(parent, text, width, height, click)
    local button = T.Button(parent, text, width, height, { noSearch = true })
    HM.SkipHistoryCheckpoint(button)
    if click then button:SetScript("OnClick", click) end
    return button
end

local function Claim(self, anchor)
    local config = S.Config(ID)
    return { current = P.ProfileGuard(), config = config, raw = config[KEY], revision = self.revision,
        id = self.selectedID, anchor = anchor, anchorToken = anchor.directToken }
end

local function Current(self, claim)
    return self.active and claim and claim.revision == self.revision and claim.current()
        and claim.config == S.Config(ID) and claim.raw == claim.config[KEY]
        and claim.id == self.selectedID and claim.anchor:IsVisible() and claim.anchor.directToken == claim.anchorToken
        and (not claim.id or Model.Find(claim.config, claim.id) == self.tab)
end

local function Find(tabs, id)
    for index, tab in ipairs(tabs) do
        if tab.id == id then return tab, index end
    end
end

local function Editable(self, claim)
    if not Current(self, claim) then return end
    local tabs = Model.Copy(claim.config)
    return tabs, Find(tabs, claim.id)
end

local function Save(self, claim, tabs, selected)
    if not Current(self, claim) then return false end
    local encoded = Model.Encode(tabs)
    if encoded == nil or encoded == claim.raw or not P.Set(ID, KEY, encoded) then return false end
    self.changed(selected)
    return true
end

local function Ask(key, text, prior, accept)
    local dialog = P.AskText("character-custom-" .. key, Tr(text), accept, Model.NameLimit, Model.NameLimit)
    if not dialog then return end
    local edit = dialog:GetEditBox()
    edit:SetText(prior)
    edit:HighlightText()
end

local function CreateTab(self, claim, template)
    if not Current(self, claim) then return end
    local defaultName = Tr(template.id == "empty" and "New tab" or template.label)
    Ask("create", "Tab name", defaultName, function(name)
        local tabs = Editable(self, claim)
        if not tabs then return end
        local id = Model.Create(tabs, template.id, name)
        if id then Save(self, claim, tabs, id) end
    end)
end

function Content:Add(anchor, hidden, restore)
    if P.Combat() then return false end
    local create = self.active and #Model.Get(S.Config(ID)) < Model.TabLimit
    local hasHidden = hidden and #hidden > 0
    if not (create or hasHidden) then return false end
    local claim = create and Claim(self, anchor)
    P.ContextMenu(anchor, function(_, menu)
        if hasHidden then
            menu:CreateTitle(Tr("Built-in tabs"))
            for _, tab in ipairs(hidden) do
                menu:CreateButton(tab.label, function() restore(tab.id) end)
            end
        end
        if claim then
            menu:CreateTitle(Tr("Choose a tab template"))
            for _, template in ipairs(Model.Templates) do
                menu:CreateButton(Tr(template.label), function() CreateTab(self, claim, template) end)
            end
        end
    end)
    return true
end

local function Rename(self, claim, cardIndex, rowIndex)
    local tab = Model.Find(claim.config, claim.id)
    if not Current(self, claim) or not tab then return end
    local card = cardIndex and tab.cards[cardIndex]
    local prior = rowIndex and card.rows[rowIndex].label or card and card.title or tab.name
    local key = rowIndex and "row" or card and "card" or "tab"
    local prompt = rowIndex and "Row label" or card and "Card title" or "Tab name"
    Ask(key, prompt, prior, function(name)
        local tabs, edited = Editable(self, claim)
        if not edited then return end
        if rowIndex then edited.cards[cardIndex].rows[rowIndex].label = name
        elseif card then edited.cards[cardIndex].title = name
        else edited.name = name end
        Save(self, claim, tabs, edited.id)
    end)
end

local function Duplicate(self, claim)
    local tabs, tab = Editable(self, claim)
    if not tab or #tabs >= Model.TabLimit then return end
    local id = Model.Duplicate(tabs, tab.id)
    if id then Save(self, claim, tabs, id) end
end

local function DeleteTab(self, claim)
    P.Confirm("character-custom-delete-tab", Tr("Delete this tab?"), function()
        local tabs, tab, index = Editable(self, claim)
        if not tab then return end
        table.remove(tabs, index)
        local encoded = Model.Encode(tabs)
        local patch = encoded and Header.WithoutCustomTab(claim.config, tab.id, encoded)
        if patch and P.SetMany(ID, patch) then self.changed(nil) end
    end)
end

local function TabActions(self, anchor)
    if P.Combat() then return end
    local claim = Claim(self, anchor)
    P.ContextMenu(anchor, function(_, menu)
        menu:CreateButton(Tr("Key bindings"), function()
            if Current(self, claim) then P.CharacterPanelBindings.Open(self.ctx, claim.id) end
        end)
        if Header.HomeTab(claim.config, "tab") == claim.id then
            menu:CreateTitle(Tr("Character start tab"))
        else
            menu:CreateButton(Tr("Use as character start tab"), function()
                if not Current(self, claim) then return end
                local patch = Header.SetHomeTab(claim.config, claim.id)
                if patch then P.SetMany(ID, patch) end
            end)
        end
        menu:CreateButton(Tr("Rename tab"), function() Rename(self, claim) end)
        if #Model.Get(claim.config) < Model.TabLimit then
            menu:CreateButton(Tr("Duplicate tab"), function() Duplicate(self, claim) end)
        end
        if #Header.Order(claim.config, "tab") > 1 then
            menu:CreateButton(Tr("Delete tab"), function() DeleteTab(self, claim) end)
        end
    end)
end

local function LastOpenCard(tab)
    for index = #tab.cards, 1, -1 do
        local card = tab.cards[index]
        if #card.rows < Model.RowLimit then return card end
    end
end

local function AddRow(tab, source, cardIndex, rowIndex)
    if rowIndex then
        tab.cards[cardIndex].rows[rowIndex].source = source
        return true
    end
    local card
    if cardIndex then
        card = tab.cards[cardIndex]
        if #card.rows >= Model.RowLimit then return false end
    else
        card = LastOpenCard(tab)
        if not card then
            if #tab.cards >= Model.CardLimit then return false end
            card = Model.NewCard()
            tab.cards[#tab.cards + 1] = card
        end
    end
    card.rows[#card.rows + 1] = { source = source, label = "" }
    return true
end

local function AddFactionGroup(tab, entry)
    local slots = math.ceil(#entry.members / Model.RowLimit)
    if #tab.cards + slots > Model.CardLimit then return false end
    for index = 1, #entry.members, Model.RowLimit do
        local card = { title = entry.title, rows = {} }
        for member = index, math.min(index + Model.RowLimit - 1, #entry.members) do
            card.rows[#card.rows + 1] = { source = entry.members[member], label = "" }
        end
        tab.cards[#tab.cards + 1] = card
    end
    return true
end

local function Pick(self, frame, entry)
    local claim = frame.claim
    if not entry or not entry.enabled then return end
    local tabs, tab = Editable(self, claim)
    if not tab then frame:Hide() return end
    if entry.members then
        if not AddFactionGroup(tab, entry) then return end
    elseif entry.card then
        if #tab.cards >= Model.CardLimit then return end
        tab.cards[#tab.cards + 1] = Model.NewCard(entry.group)
    elseif not AddRow(tab, entry.id, frame.cardIndex, frame.rowIndex) then
        return
    end
    frame:Hide()
    Save(self, claim, tabs, tab.id)
end

local function OpenPicker(self, anchor, claim, cardIndex, rowIndex)
    if not Current(self, claim) then return end
    local room = rowIndex ~= nil
    if not room then
        if cardIndex then
            room = #self.tab.cards[cardIndex].rows < Model.RowLimit
        else
            room = #self.tab.cards < Model.CardLimit or LastOpenCard(self.tab) ~= nil
        end
    end
    self.picker = Picker.Open(self.picker, self.tab, anchor, claim, cardIndex, rowIndex, room,
        function(frame, entry) Pick(self, frame, entry) end)
end

local function Entry(tab, cardIndex, rowIndex)
    local card = tab and tab.cards[cardIndex]
    if rowIndex then return card and card.rows[rowIndex] end
    return card
end

local function PositionHint(self, x, y)
    local text
    if x then
        text = Tr("Position: X %d, Y %d"):format(x, y)
    elseif #self.tab.cards == 0 then
        text = Tr("Add content to build this tab.")
    elseif self.positionMode then
        text = Tr("Drag cards and values to position them.")
    else
        text = Tr("Click to edit. Drag to reorder.")
    end
    if text == self.hintText then return end
    self.hintText = text
    P.SetTranslatedText(self.hint, text)
end

local function RestoreHint(self)
    local handle = self.positionSelection
    local entry = self.positionMode and handle and Entry(self.tab, handle.cardIndex, handle.rowIndex)
    if entry then PositionHint(self, Model.Position(entry)) else PositionHint(self) end
end

local function ResetPositionAction(menu, self, claim, cardIndex, rowIndex)
    local x, y = Model.Position(Entry(self.tab, cardIndex, rowIndex))
    if x == 0 and y == 0 then return end
    menu:CreateButton(Tr("Reset position"), function()
        local tabs, tab = Editable(self, claim)
        if not tab then return end
        local entry = Entry(tab, cardIndex, rowIndex)
        entry.x, entry.y = 0, 0
        Save(self, claim, tabs, tab.id)
    end)
end

local function CardActions(self, handle)
    local claim, index = Claim(self, handle), handle.cardIndex
    local card = self.tab.cards[index]
    P.ContextMenu(handle, function(_, menu)
        if #card.rows < Model.RowLimit then
            menu:CreateButton(Tr("Add value"), function() OpenPicker(self, handle, claim, index) end)
        end
        menu:CreateButton(Tr("Rename card"), function() Rename(self, claim, index) end)
        ResetPositionAction(menu, self, claim, index)
        menu:CreateButton(Tr("Delete card"), function()
            P.Confirm("character-custom-delete-card", Tr("Delete this card?"), function()
                local tabs, tab = Editable(self, claim)
                if not tab then return end
                table.remove(tab.cards, index)
                Save(self, claim, tabs, tab.id)
            end)
        end)
    end)
end

local function RowActions(self, handle)
    local claim, cardIndex, rowIndex = Claim(self, handle), handle.cardIndex, handle.rowIndex
    local hasLabel = self.tab.cards[cardIndex].rows[rowIndex].label ~= ""
    P.ContextMenu(handle, function(_, menu)
        menu:CreateButton(Tr("Change data source"), function() OpenPicker(self, handle, claim, cardIndex, rowIndex) end)
        menu:CreateButton(Tr("Edit label"), function() Rename(self, claim, cardIndex, rowIndex) end)
        if hasLabel then
            menu:CreateButton(Tr("Use source label"), function()
                local tabs, tab = Editable(self, claim)
                if not tab then return end
                tab.cards[cardIndex].rows[rowIndex].label = ""
                Save(self, claim, tabs, tab.id)
            end)
        end
        ResetPositionAction(menu, self, claim, cardIndex, rowIndex)
        menu:CreateButton(Tr("Remove value"), function()
            local tabs, tab = Editable(self, claim)
            if not tab then return end
            table.remove(tab.cards[cardIndex].rows, rowIndex)
            Save(self, claim, tabs, tab.id)
        end)
    end)
end

local function DropCard(self, handle, y)
    -- Offsets can cross otherwise adjacent title centers. Pick the visible
    -- title nearest to the dragged one, then place in saved list order.
    local target, distance, after
    for index = 1, #self.tab.cards do
        local delta = y - (self.cards[index].drawY + HEADER / 2)
        local gap = math.abs(delta)
        if not distance or gap < distance then target, distance, after = index, gap, delta >= 0 end
    end
    local at = after and target + 1 or target
    if at == handle.cardIndex or at == handle.cardIndex + 1 then return end
    local card = self.cards[target]
    local mark = after and card.drawY + card.height + GAP / 2 or card.drawY - GAP / 2
    return at, nil, mark
end

local function DropRow(self, handle, y)
    for cardIndex, spec in ipairs(self.tab.cards) do
        local card = self.cards[cardIndex]
        if y >= card.drawY - GAP / 2 and y < card.drawY + card.height + GAP / 2 then
            if cardIndex ~= handle.cardIndex and #spec.rows >= Model.RowLimit then return end
            local at = #spec.rows + 1
            for index = 1, #spec.rows do
                if y < card.drawY + card.rows[index].drawY + LINE / 2 then at = index break end
            end
            if cardIndex == handle.cardIndex and (at == handle.rowIndex or at == handle.rowIndex + 1) then return end
            local row = at <= #spec.rows and card.rows[at]
            local top = row and row.drawY or HEADER + GAP + (at - 1) * (LINE + GAP)
            return cardIndex, at, card.drawY + top - GAP / 2
        end
    end
end

local function Drop(self, handle, dy)
    local card = self.cards[handle.cardIndex]
    local y = card.drawY + (handle.rowIndex and handle.drawY + LINE / 2 or HEADER / 2) - dy
    if y < 0 or y > self.contentHeight then return end
    if handle.kind == CARD then return DropCard(self, handle, y) end
    return DropRow(self, handle, y)
end

local function MarkDrop(self, y)
    if y == self.dropY then return end
    self.dropY = y
    if y then
        local inset = self.cardInset
        if self.claim.handle.kind == ROW then inset = inset + self.rowInset end
        Position(self.marker, self.overlay, inset, y, self.canvasWidth - 2 * inset)
    end
    self.marker:SetShown(y ~= nil)
end

local function DrawActor(claim, dx, dy)
    claim.actor:ClearAllPoints()
    claim.actor:SetPoint("TOPLEFT", claim.parent, "TOPLEFT", claim.x + dx, -claim.y + dy)
end

local function CanvasDelta(self, claim, dy)
    return dy - (self.scroll:GetVerticalScroll() - claim.scroll)
end

local function Offset(self, claim, dx, dy)
    return Model.ClampPosition(claim.handle.kind, claim.offsetX + dx / self.scale, claim.offsetY + dy / self.scale)
end

local function Follow(handle, dx, dy)
    local self, claim = handle.editor, handle.editor.claim
    if not claim or claim.handle ~= handle or claim.finished then return end
    local x, y
    if self.positionMode then
        x, y = Offset(self, claim, dx, dy)
        dx, dy = (x - claim.offsetX) * self.scale, (y - claim.offsetY) * self.scale
    else
        dy = CanvasDelta(self, claim, dy)
    end
    if claim.dx == dx and claim.dy == dy then return end
    claim.dx, claim.dy = dx, dy
    DrawActor(claim, dx, dy)
    if self.positionMode then
        PositionHint(self, x, y)
    else
        local _, _, mark = Drop(self, handle, dy)
        MarkDrop(self, mark)
    end
end

local function Elevate(handle, actor, level)
    actor:SetFrameLevel(level)
    if handle.kind ~= CARD then return end
    actor.title:SetFrameLevel(level + 1)
    for _, row in ipairs(actor.rows) do row:SetFrameLevel(level + 1) end
end

local function Drag(handle, phase)
    local self, claim = handle.editor, handle.editor.claim
    if phase == "press" then
        local card = self.cards[handle.cardIndex]
        claim = Claim(self, handle)
        claim.handle = handle
        claim.actor = handle.kind == CARD and card or handle
        claim.parent = handle.kind == CARD and self.canvas or card
        claim.x, claim.y = claim.actor.drawX, claim.actor.drawY
        claim.scroll = self.scroll:GetVerticalScroll()
        claim.level, claim.dx, claim.dy = claim.actor:GetFrameLevel(), 0, 0
        self.claim, handle.cancelled = claim, nil
        if self.positionMode then
            self.positionSelection = handle
            claim.offsetX, claim.offsetY = Model.Position(Entry(self.tab, handle.cardIndex, handle.rowIndex))
            PositionHint(self, claim.offsetX, claim.offsetY)
        end
    elseif not claim then
        return
    elseif phase == "start" then
        Elevate(handle, claim.actor, self.overlay:GetFrameLevel() + 1)
    elseif phase == "stop" or phase == "cancel" then
        claim.finished = true
        DrawActor(claim, 0, 0)
        MarkDrop(self)
        Elevate(handle, claim.actor, claim.level)
        if phase == "cancel" then
            self.claim, handle.cancelled = nil, true
            if self.tab then RestoreHint(self) end
        end
    elseif phase == "done" then
        self.claim = nil
        if self.tab then RestoreHint(self) end
    end
end

local function StorePosition(self, claim, handle, x, y)
    local tabs, tab = Editable(self, claim)
    if not tab then return false end
    local entry = Entry(tab, handle.cardIndex, handle.rowIndex)
    if not entry then return false end
    entry.x, entry.y = x, y
    return Save(self, claim, tabs, tab.id)
end

local function Reorder(self, claim, handle, cardIndex, rowIndex)
    local tabs, tab = Editable(self, claim)
    if not tab then return false end
    local sourceCard = handle.cardIndex
    if handle.kind == CARD then
        local card = table.remove(tab.cards, sourceCard)
        if cardIndex > sourceCard then cardIndex = cardIndex - 1 end
        table.insert(tab.cards, cardIndex, card)
    else
        local row = table.remove(tab.cards[sourceCard].rows, handle.rowIndex)
        if cardIndex == sourceCard and rowIndex > handle.rowIndex then rowIndex = rowIndex - 1 end
        table.insert(tab.cards[cardIndex].rows, rowIndex, row)
    end
    return Save(self, claim, tabs, tab.id)
end

local function Move(handle, dx, dy)
    local self, claim = handle.editor, handle.editor.claim
    if not Current(self, claim) then return false end
    if self.positionMode then
        local x, y = Offset(self, claim, dx, dy)
        if x == claim.offsetX and y == claim.offsetY then return false end
        return StorePosition(self, claim, handle, x, y)
    end
    if not self.scroll:IsMouseOver() then return false end
    local cardIndex, rowIndex = Drop(self, handle, CanvasDelta(self, claim, dy))
    if not cardIndex then return false end
    return Reorder(self, claim, handle, cardIndex, rowIndex)
end

local function Click(handle, _, moved)
    local self = handle.editor
    if moved or handle.cancelled or P.Combat() or not self.tab then return end
    if self.positionMode and not self.directPreview then
        self.positionSelection = handle
        RestoreHint(self)
    end
    if handle.kind == CARD then CardActions(self, handle) else RowActions(self, handle) end
end

local function ReadDrag() return 0, 0 end

local function Handle(self, parent, index, row)
    local height = row and LINE or HEADER
    local handle = Button(parent, "", 80, height)
    handle.editor, handle.kind, handle.cardIndex, handle.rowIndex = self, row and ROW or CARD, index, row
    self.drag:Add(handle, handle, ReadDrag, function(x, y) return Move(handle, x, y) end,
        { select = false, follow = Follow })
    return handle
end

local function NewCard(self, index)
    local card = CreateFrame("Frame", nil, self.canvas)
    local fill = card:CreateTexture(nil, "BACKGROUND")
    local color = T.colors.panel
    fill:SetAllPoints(card)
    fill:SetColorTexture(color[1], color[2], color[3], 1)
    card.rows = {}
    card.title = Handle(self, card, index)
    self.cards[index] = card
    return card
end

local function NewRow(self, card, cardIndex, rowIndex)
    local handle = Handle(self, card, cardIndex, rowIndex)
    local label = HM.GetControlLabel(handle)
    label:ClearAllPoints()
    label:SetPoint("LEFT", handle, "LEFT", 8, 0)
    label:SetPoint("RIGHT", handle, "RIGHT", -105, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local value = P.Text(handle, "", 0, 0, 89, T.colors.muted)
    value:ClearAllPoints()
    value:SetPoint("RIGHT", handle, "RIGHT", -8, 0)
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)
    handle.value = value
    card.rows[rowIndex] = handle
    return handle
end

local function CardHeight(spec)
    return HEADER + GAP + #spec.rows * (LINE + GAP)
end

local function DrawPosition(self, frame, parent, entry, left, top, width)
    local x, y = Model.Position(entry)
    frame.drawX, frame.drawY = left + x * self.scale, top - y * self.scale
    Position(frame, parent, frame.drawX, frame.drawY, width)
end

local function PaintCard(self, spec, index, top, width)
    local card = self.cards[index] or NewCard(self, index)
    card.top, card.height = top, CardHeight(spec)
    DrawPosition(self, card, self.canvas, spec, self.cardInset, top, width)
    card:SetHeight(card.height)
    Position(card.title, card, 0, 0, width)
    Label(card.title, spec.title)
    for rowIndex, row in ipairs(spec.rows) do
        local button = card.rows[rowIndex] or NewRow(self, card, index, rowIndex)
        local source = Model.Source(row.source)
        button.top = HEADER + GAP + (rowIndex - 1) * (LINE + GAP)
        DrawPosition(self, button, card, row, self.rowInset, button.top, width - 2 * self.rowInset)
        Label(button, row.label ~= "" and row.label or Picker.SourceText(source))
        local sample = Model.SourceAvailable(row.source) and source.sample
        P.SetTranslatedText(button.value, sample and tostring(sample) or "—")
        button:Show()
    end
    for rowIndex = #spec.rows + 1, #card.rows do card.rows[rowIndex]:Hide() end
    card:Show()
    return top + card.height + GAP
end

function Content:Cancel()
    self.revision = self.revision + 1
    self.drag:Release()
    if self.direct then self.direct:Cancel() end
    self.claim = nil
    if self.picker then self.picker:Hide() end
end

local function ScrollTo(self, offset)
    self.scroll:SetVerticalScroll(math.max(0, math.min(self.scrollRange, offset)))
end

local function LayoutCards(self, cards, width, top, reset)
    local cardBounds, rowBounds = Model.PositionBounds.card, Model.PositionBounds.row
    self.cardInset = math.min(cardBounds.x * self.scale, width / 5)
    self.rowInset = math.min(math.max(12, rowBounds.x * self.scale), width / 5)
    local verticalInset = #cards > 0 and (cardBounds.y + rowBounds.y) * self.scale or 0
    local contentHeight = 2 * verticalInset
    for _, spec in ipairs(cards) do contentHeight = contentHeight + CardHeight(spec) + GAP end
    local height = math.min(CARD_VIEWPORT, contentHeight)
    self.scrollRange = contentHeight - height
    local scrollable = self.scrollRange > 0
    self.scroll:EnableMouseWheel(scrollable)
    if scrollable then width = width - SCROLL_GUTTER end
    self.canvasWidth, self.contentHeight = width, contentHeight
    Position(self.scroll, self.root, 0, top, width)
    self.scroll:SetHeight(math.max(1, height))
    self.canvas:SetSize(width, math.max(1, contentHeight))
    local y = verticalInset
    for index, card in ipairs(cards) do y = PaintCard(self, card, index, y, width - 2 * self.cardInset) end
    for index = #cards + 1, #self.cards do self.cards[index]:Hide() end
    self.scroll:SetShown(height > 0)
    ScrollTo(self, reset and 0 or self.scroll:GetVerticalScroll())
    return top + height
end

function Content:Refresh(width, top, selectedID, visible, positionMode, scale)
    self:DetachPreview()
    local tab = visible and Model.Find(S.Config(ID), selectedID)
    positionMode, scale = positionMode == true, scale or 1
    local resetScroll = selectedID ~= self.selectedID
    local modeChanged = self.positionMode ~= positionMode
    if resetScroll or modeChanged then self.positionSelection = nil end
    self.active, self.selectedID = visible == true, selectedID
    if not tab then
        if self.root:IsShown() then self.root:Hide() end
        self.tab = nil
        return top
    end
    if self.tab == tab and self.width == width and self.top == top and self.root:IsShown()
        and not modeChanged and self.scale == scale and self.fontRevision == S.FontRevision then return top + self.height end
    self:Cancel()
    self.tab, self.width, self.top, self.fontRevision = tab, width, top, S.FontRevision
    self.positionMode, self.scale = positionMode, scale
    local buttonWidth = math.min(152, (width - GAP) / 2)
    Position(self.root, self.parent, 0, top, width)
    Position(self.add, self.root, 0, 0, buttonWidth)
    Position(self.actions, self.root, buttonWidth + GAP, 0, buttonWidth)
    Position(self.hint, self.root, 0, HEADER + GAP, width)
    RestoreHint(self)
    local hintHeight = self.positionMode and 34 or HEADER
    local cardsTop = HEADER + math.max(hintHeight, math.ceil(self.hint:GetStringHeight()) + GAP) + GAP
    local height = LayoutCards(self, tab.cards, width, cardsTop, resetScroll)
    self.height = height
    self.root:SetHeight(height)
    self.root:Show()
    return top + height
end

function Content.Create(ui, onChanged)
    local root = CreateFrame("Frame", nil, ui.host)
    local self = setmetatable({ root = root, parent = ui.host, ctx = ui.ctx, changed = onChanged, cards = {}, revision = 0 }, Content)
    local scroll = CreateFrame("ScrollFrame", nil, root, "ScrollFrameTemplate")
    scroll.ScrollBar:SetHideIfUnscrollable(true)
    scroll:SetScript("OnMouseWheel", function(frame, delta)
        if not self.positionMode or not self.drag.drag then ScrollTo(self, frame:GetVerticalScroll() - delta * 45) end
    end)
    self.scroll, self.scrollRange = scroll, 0
    self.canvas = CreateFrame("Frame", nil, scroll)
    self.canvas:SetSize(1, 1)
    scroll:SetScrollChild(self.canvas)
    self.overlay = CreateFrame("Frame", nil, self.canvas)
    self.overlay:SetAllPoints(self.canvas)
    self.overlay:SetFrameLevel(self.canvas:GetFrameLevel() + 8)
    self.marker = self.overlay:CreateTexture(nil, "OVERLAY")
    local accent = T.colors.accent
    self.marker:SetColorTexture(accent[1], accent[2], accent[3], 1)
    self.marker:SetHeight(2)
    self.marker:Hide()
    local host = Suite.PreviewKit.NewHost(nil, { frame = root })
    self.drag = Interaction.Handles(host, { keys = false, pixels = true, threshold = 4, manualDrag = true,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end, drag = Drag, click = Click })
    self.add = Button(root, "Add content", 152, HEADER, function(button) OpenPicker(self, button, Claim(self, button)) end)
    self.actions = Button(root, "Tab actions", 152, HEADER, function(button) TabActions(self, button) end)
    self.hint = P.Text(root, "", 0, 0, 280, T.colors.muted)
    root:HookScript("OnHide", function() self:Cancel() end)
    root:Hide()
    return self
end

P.CharacterPreviewContent.Install(Content, { claim = Claim, current = Current, reorder = Reorder,
    position = StorePosition, click = Click, picker = OpenPicker, tabActions = TabActions })
