local _, P = ...
local Suite, S, T = P.Suite, P.S, P.T
local Model, Interaction = Suite.CharacterTabs, P.PreviewInteraction
local ID, CARD = "characterPanel", "card"
local Direct = {}
Direct.__index = Direct
P.CharacterPreviewContent = Direct

local function ScreenRect(frame)
    local x, y, width, height = frame:GetRect()
    local scale = frame:GetEffectiveScale()
    if not (Suite.Finite(x) and Suite.Finite(y) and Suite.Finite(width) and Suite.Finite(height)
        and Suite.Finite(scale) and scale > 0) then return end
    return { left = x * scale, right = (x + width) * scale, bottom = y * scale, top = (y + height) * scale }
end

local function Contains(rect, x, y)
    return x >= rect.left and x <= rect.right and y >= rect.bottom and y <= rect.top
end

local function Intersects(a, b)
    return a.left < b.right and a.right > b.left and a.bottom < b.top and a.top > b.bottom
end

local function RowBefore(a, b) return a.index < b.index end

local function Capture(self)
    local viewport = ScreenRect(self.scroll)
    if not viewport then return end
    local cards = {}
    for _, handle in ipairs(self.handles) do
        if handle.generation == self.generation and handle:IsVisible() then
            local index = handle.cardIndex
            local actor = handle.kind == CARD and handle.actor or handle.actor:GetParent()
            local card = cards[index]
            if not card then
                local bounds = ScreenRect(actor)
                if bounds and Intersects(bounds, viewport) then
                    card = { index = index, actor = actor, bounds = bounds, rows = {} }
                    cards[index] = card
                end
            end
            if card then
                if handle.kind == CARD then
                    card.title = handle.native
                else
                    local bounds = ScreenRect(handle.native)
                    if bounds and Intersects(bounds, viewport) then
                        card.rows[#card.rows + 1] = { index = handle.rowIndex, frame = handle.native,
                            center = (bounds.top + bounds.bottom) / 2 }
                    end
                end
            end
        end
    end
    for _, card in pairs(cards) do table.sort(card.rows, RowBefore) end
    return cards, viewport
end

local function TargetCard(claim, x, y)
    local source, best, distance = claim.handle
    for index, card in pairs(claim.cards) do
        if (source.kind ~= CARD or index ~= source.cardIndex) and Contains(card.bounds, x, y) then
            local bounds = card.bounds
            local dx, dy = x - (bounds.left + bounds.right) / 2, y - (bounds.top + bounds.bottom) / 2
            local gap = dx * dx + dy * dy
            if not distance or gap < distance or gap == distance and index < best.index then
                best, distance = card, gap
            end
        end
    end
    return best
end

local function TargetRow(claim, card, y)
    local source = claim.handle
    if card.index ~= source.cardIndex and #claim.tab.cards[card.index].rows >= Model.RowLimit then return end
    local rows = card.rows
    for _, row in ipairs(rows) do
        if y >= row.center then return row.index, row.frame, false end
    end
    local last = rows[#rows]
    if last then return last.index + 1, last.frame, true end
    if #claim.tab.cards[card.index].rows == 0 then return 1, card.title or card.actor, true end
end

local function Drop(claim, dx, dy)
    if not claim.cards then return end
    local x = claim.pointerX + dx * claim.scale
    local y = claim.pointerY + dy * claim.scale
    if not Contains(claim.viewport, x, y) then return end
    local card = TargetCard(claim, x, y)
    if not card then return end
    local source = claim.handle
    if source.kind == CARD then
        local after = card.index > source.cardIndex
        return card.index + (after and 1 or 0), nil, card.actor, after
    end
    local rowIndex, anchor, after = TargetRow(claim, card, y)
    if not rowIndex or card.index == source.cardIndex
        and (rowIndex == source.rowIndex or rowIndex == source.rowIndex + 1) then return end
    return card.index, rowIndex, anchor, after
end

local function NewMarker(canvas)
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetFrameLevel(canvas:GetFrameLevel() + 28)
    local fill = frame:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(frame)
    local color = T.colors.accent
    fill:SetColorTexture(color[1], color[2], color[3], 1)
    return frame
end

local function Mark(self, handle, anchor, after)
    if not anchor then
        if self.markerAnchor then self.marker:Hide() end
        self.markerAnchor = nil
        return
    end
    if self.markerAnchor == anchor and self.markerAfter == after and self.markerKind == handle.kind then return end
    local marker = self.marker or NewMarker(self.canvas)
    self.marker, self.markerAnchor, self.markerAfter, self.markerKind = marker, anchor, after, handle.kind
    marker:ClearAllPoints()
    if handle.kind == CARD then
        local side = after and "RIGHT" or "LEFT"
        local offset = after and 3 or -3
        marker:SetPoint("TOP", anchor, "TOP" .. side, offset, 0)
        marker:SetPoint("BOTTOM", anchor, "BOTTOM" .. side, offset, 0)
        marker:SetWidth(2)
    else
        local side = after and "BOTTOM" or "TOP"
        marker:SetPoint("LEFT", anchor, side .. "LEFT", 0, after and -1 or 1)
        marker:SetPoint("RIGHT", anchor, side .. "RIGHT", 0, after and -1 or 1)
        marker:SetHeight(2)
    end
    marker:Show()
end

local function Bound(claim)
    local handle, actor = claim.handle, claim.actor
    if handle.directToken ~= claim.anchorToken then return false end
    if handle.kind == CARD then return actor.previewCardIndex == handle.cardIndex end
    return actor.previewRowIndex == handle.rowIndex and actor:GetParent().previewCardIndex == handle.cardIndex
end

local function Draw(claim, dx, dy)
    local actor = claim.actor
    actor:ClearAllPoints()
    actor:SetPoint(claim.point, claim.relative, claim.relativePoint, claim.x + dx, claim.y + dy)
    actor.panelX = nil
end

local function Position(self, x, y)
    if self.feedback and (self.lastX ~= x or self.lastY ~= y) then
        self.lastX, self.lastY = x, y
        self.feedback(x, y)
    end
end

local function Offset(claim, dx, dy)
    return Model.ClampPosition(claim.handle.kind, claim.offsetX + dx, claim.offsetY + dy)
end

local function Follow(handle, dx, dy)
    local self, claim = handle.direct, handle.direct.claim
    if not claim or claim.finished or claim.handle ~= handle or not Bound(claim) then return end
    local x, y
    if self.editor.positionMode then
        x, y = Offset(claim, dx, dy)
        dx, dy = x - claim.offsetX, y - claim.offsetY
    end
    if dx == claim.dx and dy == claim.dy then return end
    claim.dx, claim.dy = dx, dy
    Draw(claim, dx, dy)
    if self.editor.positionMode then
        Position(self, x, y)
    else
        local _, _, anchor, after = Drop(claim, dx, dy)
        Mark(self, handle, anchor, after)
    end
end

local function Source(self, handle)
    local tab = self.editor.tab
    local card = tab and tab.cards[handle.cardIndex]
    return handle.kind == CARD and card or card and card.rows[handle.rowIndex]
end

local function Press(self, handle)
    local entry = Source(self, handle)
    if not entry then return end
    local claim = self.ops.claim(self.editor, handle)
    if not self.ops.current(self.editor, claim) then return end
    local actor = handle.actor
    local point, relative, relativePoint, x, y = actor:GetPoint(1)
    local scale = actor:GetEffectiveScale()
    if not (point and Suite.Finite(x) and Suite.Finite(y) and Suite.Finite(scale) and scale > 0) then return end
    claim.handle, claim.actor, claim.tab = handle, actor, self.editor.tab
    claim.point, claim.relative, claim.relativePoint = point, relative or actor:GetParent(), relativePoint or point
    claim.x, claim.y, claim.dx, claim.dy = x, y, 0, 0
    claim.level, claim.scale = actor:GetFrameLevel(), scale
    if self.editor.positionMode then
        claim.offsetX, claim.offsetY = Model.Position(entry)
        Position(self, claim.offsetX, claim.offsetY)
    else
        local cursorX, cursorY = GetCursorPosition()
        if not (Suite.Finite(cursorX) and Suite.Finite(cursorY)) then return end
        claim.pointerX, claim.pointerY = cursorX, cursorY
        claim.cards, claim.viewport = Capture(self)
    end
    self.claim, handle.cancelled = claim, nil
end

local function Drag(handle, phase)
    local self, claim = handle.direct, handle.direct.claim
    if phase == "press" then return Press(self, handle) end
    if not claim or claim.handle ~= handle then return end
    if phase == "start" and Bound(claim) then
        claim.actor:SetFrameLevel(self.canvas:GetFrameLevel() + 25)
    elseif phase == "stop" or phase == "cancel" then
        claim.finished = true
        if Bound(claim) then
            Draw(claim, 0, 0)
            claim.actor:SetFrameLevel(claim.level)
        end
        Mark(self)
        if phase == "cancel" then self.claim, handle.cancelled = nil, true end
    elseif phase == "done" then
        self.claim = nil
    end
end

local function Move(handle, dx, dy)
    local self, claim = handle.direct, handle.direct.claim
    if not claim or not Bound(claim) or not self.ops.current(self.editor, claim) then return false end
    local scale = claim.actor:GetEffectiveScale()
    if not Suite.Finite(scale) or scale ~= claim.scale then return false end
    if self.editor.positionMode then
        local x, y = Offset(claim, dx, dy)
        if x == claim.offsetX and y == claim.offsetY then return false end
        return self.ops.position(self.editor, claim, handle, x, y)
    end
    local cardIndex, rowIndex = Drop(claim, dx, dy)
    if not cardIndex then return false end
    return self.ops.reorder(self.editor, claim, handle, cardIndex, rowIndex)
end

local function Click(handle, button, moved)
    if moved or handle.cancelled then return end
    local self = handle.direct
    local entry = Source(self, handle)
    if not entry or P.Combat() then return end
    if self.editor.positionMode then Position(self, Model.Position(entry)) end
    self.ops.click(handle, button, moved)
end

local function ReadDrag() return 0, 0 end

local function NewHandle(self, frame)
    local handle = CreateFrame("Button", nil, frame)
    handle:SetAllPoints(frame)
    handle:SetFrameLevel(frame:GetFrameLevel() + 1)
    handle.direct, handle.native, handle.editor, handle.directToken = self, frame, self.editor, 0
    self.drag:Add(handle, handle, ReadDrag, function(x, y) return Move(handle, x, y) end,
        { select = false, follow = Follow })
    self.handles[#self.handles + 1] = handle
    self.byFrame[frame] = handle
    return handle
end

function Direct:Visit(kind, frame, cardIndex, rowIndex, actor)
    local handle = self.byFrame[frame] or NewHandle(self, frame)
    if handle.generation ~= self.generation - 1 or handle.kind ~= kind or handle.cardIndex ~= cardIndex
        or handle.rowIndex ~= rowIndex or handle.actor ~= actor then
        handle.directToken = handle.directToken + 1
    end
    handle.kind, handle.cardIndex, handle.rowIndex, handle.actor = kind, cardIndex, rowIndex, actor
    handle.generation = self.generation
    handle:Show()
end

function Direct:Bind()
    self.generation = self.generation + 1
    if self.editor.tab then self.preview:VisitContent(self.visitor) end
    for _, handle in ipairs(self.handles) do
        if handle.generation ~= self.generation then handle:Hide() end
    end
    local picker = self.editor.picker
    if picker and picker:IsShown() and picker.claim and not self.ops.current(self.editor, picker.claim) then picker:Hide() end
end

function Direct:Cancel()
    self.drag:Release()
    self.claim = nil
    Mark(self)
    Position(self)
end

function Direct:Detach()
    if not self.preview then return end
    self:Cancel()
    self.preview:SetContentChanging(nil)
    self.preview:SetContentChanged(nil)
    for _, handle in ipairs(self.handles) do handle:Hide() end
    self.preview = nil
end

function Direct:Attach(preview, feedback, changed)
    if self.feedback ~= feedback then
        Position(self)
        self.feedback = feedback
    end
    if self.preview == preview then
        if changed then self:Bind() end
        return
    end
    self:Detach()
    if self.lastPreview ~= preview then
        self.drag:Clear()
        self.handles, self.byFrame, self.marker = {}, {}, nil
        self.lastPreview = preview
    end
    self.preview, self.scroll, self.canvas = preview, preview.view.report.scroll, preview.view.report.canvas
    preview:SetContentChanging(self.beforePaint)
    preview:SetContentChanged(self.afterPaint)
    self:Bind()
end

function Direct.New(editor, ops)
    local self = setmetatable({ editor = editor, ops = ops, handles = {}, byFrame = {}, generation = 0 }, Direct)
    local host = Suite.PreviewKit.NewHost(nil, { frame = editor.parent })
    self.drag = Interaction.Handles(host, { keys = false, pixels = true, threshold = 4, manualDrag = true,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end, drag = Drag, click = Click,
        tip = function(handle, hovered) Interaction.Outline(handle, hovered) end })
    self.visitor = function(...) self:Visit(...) end
    self.beforePaint = function() self:Cancel() end
    self.afterPaint = function() self:Bind() end
    return self
end

function Direct.Install(Content, ops)
    function Content:AttachPreview(preview, id, positionMode, feedback)
        local tab = Model.Find(S.Config(ID), id)
        local changed = self.tab ~= tab or self.selectedID ~= id or self.positionMode ~= (positionMode == true)
        if changed then self:Cancel() end
        if self.root:IsShown() then self.root:Hide() end
        self.active, self.tab, self.selectedID, self.positionMode = true, tab, id, positionMode == true
        self.directPreview = preview
        if not self.direct then self.direct = Direct.New(self, ops) end
        self.direct:Attach(preview, feedback, changed)
    end

    function Content:DetachPreview()
        if not self.directPreview then return end
        self:Cancel()
        self.direct:Detach()
        self.directPreview, self.active, self.tab, self.selectedID = nil, false, nil, nil
    end

    function Content:OpenContent(anchor)
        if self.active and self.tab and not P.Combat() then ops.picker(self, anchor, ops.claim(self, anchor)) end
    end

    function Content:OpenTabActions(anchor)
        if self.active and self.tab then ops.tabActions(self, anchor) end
    end
end
