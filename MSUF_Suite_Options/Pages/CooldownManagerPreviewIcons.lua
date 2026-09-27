local _, P = ...
-- Cooldown manager page, preview icons: a pooled, invisible button lies on
-- every icon (or buff bar row) the runtime draws in the docked preview, plus
-- the + tile beside the drawing and the drag within it.
local Page = P.CDMPage
local M = P.M
local ID, PAGE = Page.ID, Page.PAGE
local SECTION = "suite_cooldownManager_preview"
-- The + tile beside the drawing (canvas units).
local PLUS, PLUS_GAP = 28, 6
Page.PREVIEW_SECTION, Page.PREVIEW_PLUS, Page.PREVIEW_PLUS_GAP = SECTION, PLUS, PLUS_GAP
local max, min, floor, abs = math.max, math.min, math.floor, math.abs

-- A pooled, invisible button lies on every drawn icon (or buff bar row):
-- hover outline and tooltip, click (left or right) for the spell's popover
-- under the icon, middle-click to remove, drag to reorder or onto a bar
-- chip. Sample icons of an empty bar and the + tile open the spell picker.
-- Nothing runs per frame except a drag; hovering allocates nothing.
local function Ring(hit, on)
    if hit.ringOn == on then return end
    hit.ringOn = on
    local lines = hit.lines
    for i = 1, #lines do lines[i]:SetShown(on) end
end
-- Popover state (Widgets calls it through Light).
local function HitLight(self, on)
    self.opened = on == true
    Ring(self, self.opened or self.hovered == true)
end
local function HitTile(hit)
    local grid = hit.key and hit.ui.grid
    return grid and grid:Tile(hit.key) or nil
end
local function HitName(hit, tile)
    return tile and Page.Public(tile.name) and tile.name or hit.key
end

local function HitEnter(self)
    local ui = self.ui
    if P.Combat() or ui.drag.active then return end
    self.hovered = true
    self.hover:Show()
    Ring(self, true)
    local tips = ui.tips
    if not self.key then
        Page.ShowTip(self, tips.sampleTitle, tips.sample)
        return
    end
    local tile = HitTile(self)
    local state = self.dimmed and tips.unlearned or tile and tile.hidden and Page.HiddenText(tile.hiddenBy) or nil
    Page.ShowTip(self, HitName(self, tile), tips.hint, state, Page.CustomLine(self.key))
end
local function HitLeave(self)
    self.hovered = false
    self.hover:Hide()
    Ring(self, self.opened == true)
    Page.HideTip(self)
end

-- Drag within the drawing. The flow (axis and direction from the first item
-- to the second) is read once when the drag starts; the marker moves only
-- when the target changes.
local function DragCancel(drag)
    drag.host:SetScript("OnUpdate", nil)
    local hit, active = drag.hit, drag.active
    if hit then hit.dim:SetShown(hit.dimmed == true) end
    drag.hit, drag.active, drag.key, drag.family, drag.name = nil, nil, nil, nil, nil
    drag.dropHit, drag.dropAfter, drag.dropSlot, drag.chip, drag.markTarget = nil, nil, nil, nil, nil
    drag.marker:Hide()
    if active then
        Page.HideGhost()
        Page.HighlightChip(nil)
    end
end
local function Flow(drag, ui)
    local axis, sign = "x", 1
    if ui.kind == 3 then axis, sign = "y", -1 end
    local first, second = ui.hits[1], ui.hits[2]
    if ui.hitCount >= 2 and first and second then
        local x1, y1 = first:GetCenter()
        local x2, y2 = second:GetCenter()
        if type(x1) == "number" and type(y1) == "number" and type(x2) == "number" and type(y2) == "number" then
            local dx, dy = x2 - x1, y2 - y1
            if abs(dx) >= abs(dy) then
                axis, sign = "x", dx >= 0 and 1 or -1
            else
                axis, sign = "y", dy >= 0 and 1 or -1
            end
        end
    end
    drag.axis, drag.sign = axis, sign
end
local function DragStart(drag)
    local hit = drag.hit
    local tile = HitTile(hit)
    drag.active, drag.key = true, hit.key
    drag.family = tile and tile.family or Page.Family(Page.selected)
    drag.name = HitName(hit, tile)
    Page.ClosePopups()
    Page.HideTip(hit)
    Page.ShowGhost(tile and tile.texture or nil)
    hit.dim:Show()
    Flow(drag, hit.ui)
end
local function Mark(drag, target, after)
    if drag.markTarget == target and drag.markAfter == after then return end
    drag.markTarget, drag.markAfter = target, after
    local marker = drag.marker
    if not target then
        marker:Hide()
        return
    end
    marker:ClearAllPoints()
    local lead = after == (drag.sign > 0)
    if drag.axis == "y" and not target.plus then
        marker:SetSize(max(8, (tonumber((target:GetWidth())) or 20) + 4), 2)
        marker:SetPoint("CENTER", target, lead and "TOP" or "BOTTOM", 0, 0)
    else
        marker:SetSize(2, max(8, (tonumber((target:GetHeight())) or 20) + 4))
        marker:SetPoint("CENTER", target, (lead and not target.plus) and "RIGHT" or "LEFT", 0, 0)
    end
    marker:Show()
end
local function DragTarget(drag, x, y)
    local ui = drag.hit.ui
    local chip = Page.ChipUnderCursor()
    if chip == Page.selected then chip = nil end
    if drag.chip ~= chip then
        drag.chip = chip
        Page.HighlightChip(chip)
    end
    drag.dropSlot = chip
    if chip then
        drag.dropHit = nil
        Mark(drag, nil)
        return
    end
    local target, after = nil, false
    for i = 1, ui.hitCount do
        local hit = ui.hits[i]
        if hit:IsMouseOver() then
            target = hit
            local cx, cy = hit:GetCenter()
            local scale = Page.Scale(hit)
            if type(cx) == "number" and type(cy) == "number" then
                local delta = drag.axis == "y" and (y / scale - cy) or (x / scale - cx)
                after = delta * drag.sign > 0
            end
            break
        end
    end
    if not target and ui.plus.pvShown and ui.plus:IsMouseOver() then target = ui.plus end
    drag.dropHit, drag.dropAfter = target, after
    Mark(drag, target, after)
end
local function DragDrop(drag)
    local ui = drag.hit.ui
    local key, family, name, slot = drag.key, drag.family, drag.name, drag.dropSlot
    local target, after = drag.dropHit, drag.dropAfter
    DragCancel(drag)
    if slot then
        Page.CommitDrop(key, family, name, slot)
        return
    end
    if not target then return end
    local beforeKey
    if target ~= ui.plus then
        local targetKey = target.key
        if not targetKey then return end
        if not after then
            beforeKey = targetKey
        elseif ui.grid and ui.grid:Tile(targetKey) then
            beforeKey = ui.grid:NextKey(targetKey)
        else
            local nextHit = target.index < ui.hitCount and ui.hits[target.index + 1] or nil
            beforeKey = nextHit and nextHit.key or nil
        end
    end
    Page.CommitDrop(key, family, name, nil, beforeKey)
end
local function DragUpdate(host)
    local drag = host.drag
    if P.Combat() or not drag.hit then
        DragCancel(drag)
        return
    end
    local x, y = Page.Cursor()
    if not x then return end
    if not drag.active then
        local scale = Page.Scale(host)
        local dx, dy = (x - drag.x) / scale, (y - drag.y) / scale
        if dx * dx + dy * dy < 9 then return end
        DragStart(drag)
    end
    Page.MoveGhost(x, y)
    DragTarget(drag, x, y)
end

local function HitDown(self, button)
    self.suppressClick = nil
    if button ~= "LeftButton" or not self.key or P.Combat() then return end
    local x, y = Page.Cursor()
    if not x then return end
    local drag = self.ui.drag
    DragCancel(drag)
    drag.hit, drag.x, drag.y = self, x, y
    drag.host:SetScript("OnUpdate", DragUpdate)
end
local function HitUp(self, button)
    if button ~= "LeftButton" then return end
    local drag = self.ui.drag
    if drag.active and drag.hit == self then
        self.suppressClick = true
        DragDrop(drag)
    elseif drag.hit == self then
        DragCancel(drag)
    end
end
local function HitClick(self, button)
    if self.suppressClick then
        self.suppressClick = nil
        return
    end
    local key = self.key
    if P.Combat() or key == nil then return end
    if not key then
        Page.TogglePicker(self)
        return
    end
    local tile = HitTile(self)
    if button == "MiddleButton" then
        Page.ClosePopups()
        Page.RemoveWithUndo(Page.selected, key, tile and Page.Public(tile.name) and tile.name or nil)
        return
    end
    if tile then Page.TogglePopover(tile, self) end
end
local function HitHide(self)
    local drag = self.ui.drag
    if drag.hit == self then DragCancel(drag) end
    if self.hovered then HitLeave(self) end
end

local function NewHit(ui, index)
    local hit = CreateFrame("Button", nil, ui.canvas)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    hit.ui, hit.index, hit.lines, hit.Light = ui, index, {}, HitLight
    hit.dim = hit:CreateTexture(nil, "ARTWORK")
    hit.dim:SetAllPoints(hit)
    hit.dim:SetColorTexture(0, 0, 0, 0.5)
    hit.dim:Hide()
    local r, g, b = Page.Accent()
    hit.hover = hit:CreateTexture(nil, "OVERLAY")
    hit.hover:SetAllPoints(hit)
    hit.hover:SetColorTexture(r, g, b, 0.16)
    hit.hover:Hide()
    -- Outline: top, bottom, left, right.
    local sides = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
        { "TOPRIGHT", "BOTTOMRIGHT" } }
    for i = 1, 4 do
        local line = hit:CreateTexture(nil, "OVERLAY", nil, 1)
        line:SetPoint(sides[i][1], hit, sides[i][1], 0, 0)
        line:SetPoint(sides[i][2], hit, sides[i][2], 0, 0)
        if i <= 2 then line:SetHeight(2) else line:SetWidth(2) end
        line:SetColorTexture(r, g, b, 1)
        line:Hide()
        hit.lines[i] = line
    end
    -- Marks, as on the spell tiles: accent dot = own spell options, amber
    -- strip = hidden in play by a bar rule.
    hit.mark = hit:CreateTexture(nil, "OVERLAY", nil, 2)
    hit.mark:SetSize(6, 6)
    hit.mark:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -2, -2)
    hit.mark:SetColorTexture(r, g, b, 1)
    hit.mark:Hide()
    hit.ruleMark = hit:CreateTexture(nil, "OVERLAY", nil, 2)
    hit.ruleMark:SetHeight(2)
    hit.ruleMark:SetPoint("BOTTOMLEFT", hit, "BOTTOMLEFT", 1, 1)
    hit.ruleMark:SetPoint("BOTTOMRIGHT", hit, "BOTTOMRIGHT", -1, 1)
    hit.ruleMark:SetColorTexture(1, 0.62, 0.18, 0.95)
    hit.ruleMark:Hide()
    hit.ringOn, hit.markOn, hit.ruleOn = false, false, false
    hit:SetScript("OnEnter", HitEnter)
    hit:SetScript("OnLeave", HitLeave)
    hit:SetScript("OnMouseDown", HitDown)
    hit:SetScript("OnMouseUp", HitUp)
    hit:SetScript("OnClick", HitClick)
    hit:SetScript("OnHide", HitHide)
    ui.hits[index] = hit
    return hit
end

local function PlusEnter(self)
    if P.Combat() or self.ui.drag.active then return end
    self.hover:Show()
    Page.ShowTip(self, self.ui.tips.plusTitle, self.ui.tips.plus)
end
local function PlusLeave(self)
    self.hover:Hide()
    Page.HideTip(self)
end
local function PlusClick(self)
    if P.Combat() then return end
    Page.TogglePicker(self)
end
local function NewPlus(ui)
    local plus = CreateFrame("Button", nil, ui.canvas)
    plus:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    plus.ui, plus.plus = ui, true
    local fill = plus:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(plus)
    fill:SetColorTexture(0.05, 0.07, 0.11, 0.92)
    local r, g, b = Page.Accent()
    for i = 1, 2 do
        local line = plus:CreateTexture(nil, "ARTWORK")
        line:SetPoint("CENTER", plus, "CENTER", 0, 0)
        line:SetSize(i == 1 and 12 or 2, i == 1 and 2 or 12)
        line:SetColorTexture(r, g, b, 1)
    end
    plus.hover = plus:CreateTexture(nil, "OVERLAY")
    plus.hover:SetAllPoints(plus)
    plus.hover:SetColorTexture(r, g, b, 0.2)
    plus.hover:Hide()
    plus:SetScript("OnEnter", PlusEnter)
    plus:SetScript("OnLeave", PlusLeave)
    plus:SetScript("OnClick", PlusClick)
    plus:Hide()
    plus.pvShown = false
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(plus, P.Meta(PAGE, ID, "preview.add", "action", SECTION), "Add spells", "button")
    end
    return plus
end

-- The marks follow the spell options and the spell list's tiles (which know
-- what a bar rule hides); called after either changes. Writes on change only.
local function PaintMarks(ui)
    local spells, grid = Page.SpellOverrides().e, ui.grid
    for i = 1, ui.hitCount do
        local hit = ui.hits[i]
        local key = hit.key
        local own = key and spells[key] ~= nil or false
        local tile = key and grid and grid:Tile(key)
        local hidden = tile ~= nil and tile ~= false and tile.hidden == true
        if hit.markOn ~= own then
            hit.markOn = own
            hit.mark:SetShown(own)
        end
        if hit.ruleOn ~= hidden then
            hit.ruleOn = hidden
            hit.ruleMark:SetShown(hidden)
        end
    end
end
-- Lays the buttons over what the runtime drew (see Preview.lua for the
-- holder fields). Writes only what changed.
local function PaintHits(ui, frame, editable)
    local items, keys, dims = frame and frame.items, frame and frame.keys, frame and frame.dim
    local count = editable and type(items) == "table" and type(keys) == "table" and tonumber(frame.count) or 0
    local level = (tonumber((ui.handle:GetFrameLevel())) or 0) + 4
    local shown = 0
    for i = 1, count do
        local region = items[i]
        if not region then break end
        local hit = ui.hits[i] or NewHit(ui, i)
        if hit.region ~= region then
            hit.region = region
            hit:ClearAllPoints()
            hit:SetAllPoints(region)
        end
        if hit:GetFrameLevel() ~= level then hit:SetFrameLevel(level) end
        hit.key = keys[i]
        if hit.key == nil then hit.key = false end
        local dim = type(dims) == "table" and dims[i] == true
        if hit.dimmed ~= dim then
            hit.dimmed = dim
            hit.dim:SetShown(dim)
        end
        if not hit.pvShown then
            hit.pvShown = true
            hit:Show()
        end
        shown = i
    end
    for i = shown + 1, #ui.hits do
        local hit = ui.hits[i]
        hit.key = nil
        if hit.pvShown ~= false then
            hit.pvShown = false
            hit:Hide()
        end
    end
    ui.hitCount, ui.kind = shown, frame and frame.kind or 1
    local plus, show = ui.plus, editable and frame ~= nil
    if show then
        -- As tall as one drawn icon (or row), within 16 and PLUS.
        local size, region = PLUS, shown > 0 and items[1] or nil
        local height = region and region:GetHeight()
        if Page.Public(height) and type(height) == "number" and height > 0 then
            local own = tonumber((frame:GetScale())) or 1
            size = max(16, min(PLUS, floor(height * own * (tonumber((ui.stage:GetScale())) or 1) + 0.5)))
        end
        if plus.size ~= size then
            plus.size = size
            plus:SetSize(size, size)
        end
        if plus.frame ~= frame then
            plus.frame = frame
            plus:ClearAllPoints()
            plus:SetPoint("LEFT", frame, "RIGHT", PLUS_GAP, 0)
        end
        if plus:GetFrameLevel() ~= level then plus:SetFrameLevel(level) end
    end
    if plus.pvShown ~= show then
        plus.pvShown = show
        plus:SetShown(show)
    end
    PaintMarks(ui)
end
-- An open popover follows its entry to the icon that holds it now.
local function FollowPopover(ui)
    local pop = Page.popover
    local anchor = pop and pop:IsShown() and pop.anchor
    if not (anchor and anchor.ui == ui and anchor.lines) then return end
    for i = 1, ui.hitCount do
        local hit = ui.hits[i]
        if hit.key == pop.key then
            Page.MovePopover(hit)
            return
        end
    end
    pop:Hide()
end

-- Icon buttons are pooled per drawn item; the + tile and the drag driver
-- (its OnUpdate runs only during a drag) are made once per layout.
local function BuildDrag(ui)
    local canvas = ui.canvas
    ui.hits, ui.hitCount = {}, 0
    ui.plus = NewPlus(ui)
    local drag = {}
    drag.host = CreateFrame("Frame", nil, canvas)
    drag.host:SetSize(1, 1)
    drag.host:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    drag.host:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 0) + 40)
    drag.host.drag = drag
    drag.host:SetScript("OnHide", function() DragCancel(drag) end)
    drag.marker = drag.host:CreateTexture(nil, "OVERLAY")
    drag.marker:SetColorTexture(Page.Accent())
    drag.marker:Hide()
    ui.drag = drag
end



-- Exports for the preview (CooldownManagerPreview.lua).
Page.BuildPreviewIcons = BuildDrag
Page.PaintPreviewIcons = PaintHits
Page.PaintPreviewMarks = PaintMarks
Page.FollowPreviewPopover = FollowPopover
Page.CancelPreviewDrag = DragCancel
