local _, P = ...
-- Cooldown manager page, pooled editors: popups (they close with the menu, on
-- combat and on a click elsewhere) and the spell tiles. The spell picker is
-- in CooldownManagerPicker.lua.
local Page = P.CDMPage
local S, M, W, T, Tr = P.S, P.M, P.W, P.T, P.Tr
local CDM = P.Suite.CDM
local ID = Page.ID
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local TILE, GAP = 36, 6
local CROP_MIN, CROP_MAX = Page.CROP_MIN, Page.CROP_MAX
local floor, max, min, format = math.floor, math.max, math.min, string.format
local Public, Plain, EntryKey, SetIcon = Page.Public, Page.Plain, Page.EntryKey, Page.SetIcon
local Accent, SetRaw = Page.Accent, Page.SetRaw

------------------------------------------------------------------ popups
local function Button(parent, text, width, height, onClick)
    local button = T.Button(parent, text or "", width, height or 22, { noSearch = true })
    button._msuf2SkipHistoryCheckpoint = true
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end
local function Label(parent, template, text, colorName)
    local label = T.Font(parent, template or "GameFontHighlightSmall", text or "", T.colors and T.colors[colorName or "text"])
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end
-- Captions built from data skip the locale lookup and the search index.
local ButtonText = P.SetButtonText
Page.Button, Page.Label, Page.ButtonText = Button, Label, ButtonText

-- The cursor in screen pixels.
local function Cursor()
    return GetCursorPosition()
end
local function Scale(frame)
    local scale = frame:GetEffectiveScale()
    return scale > 0 and scale or 1
end
Page.Cursor, Page.Scale = Cursor, Scale

local function ShowTip(owner, title, first, second, third)
    local tip = GameTooltip
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(title or "", 1, 1, 1)
    if first and first ~= "" then tip:AddLine(first, 0.82, 0.82, 0.82, true) end
    if second and second ~= "" then tip:AddLine(second, 0.82, 0.82, 0.82, true) end
    if third and third ~= "" then
        local r, g, b = Accent()
        tip:AddLine(third, r, g, b, true)
    end
    tip:Show()
end
local function HideTip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
Page.ShowTip, Page.HideTip = ShowTip, HideTip

-- Popups close with the menu, on combat and on a click elsewhere. The event
-- frame listens only while one of them is open.
local watch
local function AnyPopup()
    for i = 1, #Page.popups do if Page.popups[i]:IsShown() then return true end end
    return false
end
local function MouseOver(frame)
    return frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver() and true or false
end
local function OnWatchEvent(_, event)
    if event ~= "GLOBAL_MOUSE_DOWN" then
        Page.ClosePopups()
        return
    end
    if MouseOver(_G.MSUF2NativeDropdownList) then return end
    for i = 1, #Page.popups do if MouseOver(Page.popups[i]) then return end end
    for i = 1, #Page.popups do
        local popup = Page.popups[i]
        if popup:IsShown() and not MouseOver(popup.anchor) then popup:Hide() end
    end
end
local function Watch()
    local open = AnyPopup()
    if open and not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", OnWatchEvent)
    end
    if not watch then return end
    if open then
        watch:RegisterEvent("PLAYER_REGEN_DISABLED")
        watch:RegisterEvent("GLOBAL_MOUSE_DOWN")
    else
        watch:UnregisterAllEvents()
    end
end
local function PopupShown() Watch() end
local function PopupHidden(self)
    -- Hidden together with the menu: stay closed when the menu returns.
    if self:IsShown() then self:Hide() end
    if self.OnClosed then self:OnClosed() end
    HideTip(self)
    Watch()
end
function Page.NewPopup(width, height)
    local parent = M.frame or _G.UIParent
    local panel = M.CreateMenuPopupPanel and M.CreateMenuPopupPanel(parent, {}) or nil
    if not panel then
        panel = CreateFrame("Frame", nil, parent)
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        local fill = panel:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(panel)
        fill:SetColorTexture(0.02, 0.03, 0.06, 0.97)
        panel:EnableMouse(true)
    end
    panel:SetSize(width, height)
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel:HookScript("OnShow", PopupShown)
    panel:HookScript("OnHide", PopupHidden)
    Page.popups[#Page.popups + 1] = panel
    return panel
end
function Page.ClosePopups(keep)
    for i = 1, #Page.popups do
        local popup = Page.popups[i]
        if popup ~= keep and popup:IsShown() then popup:Hide() end
    end
    if Page.dropdownOpen and W.CloseDropdown then W.CloseDropdown({ immediate = true }) end
    Page.dropdownOpen = nil
end
-- Closes the popups whose anchor went out of sight (a closed spell list),
-- then those anchored inside them; the preview keeps its own open.
function Page.CloseOrphans()
    for _ = 1, 2 do
        for i = 1, #Page.popups do
            local popup = Page.popups[i]
            local anchor = popup.anchor
            if popup:IsShown() and anchor and anchor.IsVisible and not anchor:IsVisible() then popup:Hide() end
        end
    end
end
function Page.PlacePopup(popup, anchor)
    popup.anchor = anchor
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
end

local function Wheel(self, delta)
    self:SetVerticalScroll(max(0, min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 48)))
end
function Page.ScrollArea(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", Wheel)
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, parent) end
    return scroll, content
end
local function ClearFocus(self) self:ClearFocus() end
Page.ClearFocusScript = ClearFocus
function Page.SearchBox(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    if T.SkinEditBox then T.SkinEditBox(box) end
    box.placeholder = Label(box, "GameFontDisableSmall", placeholder, "muted")
    box.placeholder:SetPoint("LEFT", box, "LEFT", 6, 0)
    box:SetScript("OnEscapePressed", ClearFocus)
    box:SetScript("OnEnterPressed", ClearFocus)
    box:SetScript("OnTextChanged", function(self, userInput)
        self.placeholder:SetShown((self:GetText() or "") == "")
        onChange(self, userInput)
    end)
    return box
end
-- Plain, lower-case search text; protected names never reach string functions.
-- Spell IDs (base, override and the tooltip's) make Blizzard entries
-- findable by the ID players know; rows without them are found by name and key.
local function SearchID(id)
    if Public(id) and type(id) == "number" and id > 0 then return " " .. format("%d", id) end
    return ""
end
function Page.SearchText(name, key, spell, override, tooltip)
    local text = Public(name) and type(name) == "string" and name:lower() or ""
    if tooltip == spell or tooltip == override then tooltip = nil end
    return text .. " " .. (key or "") .. SearchID(spell) .. SearchID(override) .. SearchID(tooltip)
end
function Page.Query(box)
    local text = box:GetText() or ""
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

------------------------------------------------------------------ spell tiles
local Grid = {}
Grid.__index = Grid

local function PaintEdge(tile, lit)
    if lit then
        local r, g, b = Accent()
        tile.edge:SetColorTexture(r, g, b, 1)
    else
        tile.edge:SetColorTexture(0.12, 0.15, 0.20, 1)
    end
end
-- Marks what the popover belongs to: a spell tile, or a preview icon (which
-- brings its own Light).
local function Light(anchor, on)
    if not anchor then return end
    if anchor.edge then
        PaintEdge(anchor, on)
    elseif anchor.Light then
        anchor:Light(on)
    end
end
Page.Light = Light
local function PopoverOn(anchor)
    local popover = Page.popover
    return popover ~= nil and popover:IsShown() and popover.anchor == anchor
end

-- Why a listed entry is not shown in play (runtime rows may say which rule
-- hides it: "cap", "ready" or "empty"); already translated.
function Page.HiddenText(hiddenBy)
    if hiddenBy == "cap" then return Tr("Beyond this bar's Maximum icons.") end
    if hiddenBy == "ready" then return Tr("Hidden while ready (Hide icons that are ready).") end
    if hiddenBy == "empty" then return Tr("None in your bags right now.") end
    return Tr("Hidden right now by a bar rule.")
end
-- An entry past Maximum icons that Send excess cooldowns to moves to
-- another bar (runtime rows: movedTo); already translated.
function Page.MovedText(slot)
    return format(Tr("Past Maximum icons: shown on %s."), Page.BarName(slot))
end
local function TileEnter(self)
    if self.grid.dragTile then return end
    PaintEdge(self, true)
    if self.plus then
        ShowTip(self, Tr("Add spells"), format(Tr("Pick cooldowns, buffs, trinkets or custom IDs for %s."), Page.BarName(Page.selected)))
        return
    end
    local state = not self.known and Tr("Not learned right now.") or self.hidden and Page.HiddenText(self.hiddenBy)
        or self.movedTo and Page.MovedText(self.movedTo) or nil
    ShowTip(self, Public(self.name) and self.name or self.key, Page.Identity(self.key) .. (state and ("\n" .. state) or ""),
        Tr("Click: spell options. Middle-click: remove. Drag: reorder, or drop on a bar in the preview."),
        Page.CustomLine(self.key))
end
local function TileLeave(self)
    PaintEdge(self, PopoverOn(self))
    HideTip(self)
end
local function TileDown(self, button)
    self.suppressClick = nil
    if button ~= "LeftButton" or self.plus or not self.key or P.Combat() then return end
    local x, y = Cursor()
    if not x then return end
    local grid = self.grid
    grid.pressTile, grid.pressX, grid.pressY = self, x, y
    grid.host:SetScript("OnUpdate", grid.onUpdate)
end
local function TileUp(self, button)
    if button ~= "LeftButton" then return end
    local grid = self.grid
    if grid.dragTile then
        self.suppressClick = true
        grid:Drop()
    else
        grid:CancelDrag()
    end
end
local function TileClick(self, button)
    if self.suppressClick then
        self.suppressClick = nil
        return
    end
    if P.Combat() then return end
    if self.plus then
        Page.TogglePicker(self)
        return
    end
    if not self.key then return end
    if button == "MiddleButton" then
        Page.ClosePopups()
        Page.RemoveWithUndo(Page.selected, self.key, Public(self.name) and self.name or nil)
        return
    end
    Page.TogglePopover(self)
end

local function NewTile(grid, index, plus)
    local tile = CreateFrame("Button", nil, grid.host)
    tile:SetSize(TILE, TILE)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    tile.grid, tile.index, tile.plus = grid, index, plus
    tile.edge = tile:CreateTexture(nil, "BACKGROUND")
    tile.edge:SetAllPoints(tile)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    local r, g, b = Accent()
    if plus then
        tile.icon:SetColorTexture(0.05, 0.07, 0.11, 1)
        for i = 1, 2 do
            local line = tile:CreateTexture(nil, "OVERLAY")
            line:SetPoint("CENTER", tile, "CENTER", 0, 0)
            line:SetSize(i == 1 and 14 or 2, i == 1 and 2 or 14)
            line:SetColorTexture(r, g, b, 1)
        end
    else
        -- Marks: accent dot = own spell options; amber strip = hidden by a bar rule.
        tile.mark = tile:CreateTexture(nil, "OVERLAY")
        tile.mark:SetSize(7, 7)
        tile.mark:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -2, -2)
        tile.mark:SetColorTexture(r, g, b, 1)
        tile.ruleMark = tile:CreateTexture(nil, "OVERLAY")
        tile.ruleMark:SetHeight(3)
        tile.ruleMark:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 1, 1)
        tile.ruleMark:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
        tile.ruleMark:SetColorTexture(1, 0.62, 0.18, 0.95)
    end
    PaintEdge(tile, false)
    tile:SetScript("OnMouseDown", TileDown)
    tile:SetScript("OnMouseUp", TileUp)
    tile:SetScript("OnClick", TileClick)
    tile:SetScript("OnEnter", TileEnter)
    tile:SetScript("OnLeave", TileLeave)
    return tile
end

local function EntryFamily(entry, slot)
    local family = Plain(entry.family)
    if family == 1 or family == 2 then return family end
    return CDM.IsAuraKey(entry.key) and 2 or Page.Family(slot)
end

function Page.CreateTileGrid(_, parent, x, y, width)
    local grid = setmetatable({ tiles = {}, byKey = {}, count = 0, width = width }, Grid)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    host:SetSize(width, TILE)
    grid.host = host
    grid.plus = NewTile(grid, 0, true)
    grid.message = Label(host, "GameFontHighlightSmall", "", "muted")
    grid.message:SetPoint("LEFT", grid.plus, "RIGHT", 10, 0)
    grid.message:SetWidth(max(80, width - TILE - 20))
    grid.message:SetWordWrap(true)
    local r, g, b = Accent()
    grid.marker = host:CreateTexture(nil, "OVERLAY")
    grid.marker:SetSize(2, TILE + 6)
    grid.marker:SetColorTexture(r, g, b, 1)
    grid.marker:Hide()
    grid.onUpdate = function() grid:Update() end
    -- A closed list ends its drag and closes what its tiles opened; the page
    -- itself hiding closes everything (Page.Deactivate).
    host:SetScript("OnHide", function()
        grid:CancelDrag()
        Page.CloseOrphans()
    end)
    return grid
end
-- The tile of an entry on the selected bar, and the entry after it in the
-- bar's list (nil when it is last). The preview reads both.
function Grid:Tile(key) return key and self.byKey[key] or nil end
function Grid:NextKey(key)
    local tile = self.byKey[key]
    local nextTile = tile and tile.index < self.count and self.tiles[tile.index + 1] or nil
    return nextTile and nextTile.key or nil
end

-- What the tiles depend on: bar, spec, lists, per-spell choices, Blizzard's
-- catalog, which bars are on and their types, the bar's cap and ready rule,
-- and where its excess cooldowns go (its overflow and that bar's own). A
-- settings write that changes none of these (a slider tick of the look or
-- layout) asks the runtime for nothing and moves no tile.
local function BarsSignature()
    local sig = 0
    for i = 1, #SLOTS do
        local info = SLOTS[i]
        sig = sig * 2 + (Page.IsOn(info.key) and 1 or 0)
        if info.custom then sig = sig * 4 + (tonumber(P.Get(ID, KEYS[info.key].kind)) or 1) end
    end
    return sig
end
function Grid:Same(slot, blocked)
    local k = KEYS[slot]
    -- The catalog generation comes with the cooldown manager addon.
    local generation = S.CooldownManagerGeneration
    local gen = generation and generation() or 0
    local spec = Page.Spec() or 0
    local lists, spells = P.Get(ID, "listsData"), P.Get(ID, "spellsData")
    local cap = k.maxIcons and P.Get(ID, k.maxIcons) or 0
    local hide = k.hideReady and P.Get(ID, k.hideReady) or false
    local route = k.overflow and P.Get(ID, k.overflow) or 1
    local target = SLOTS[route - 1]
    local chain = target and KEYS[target.key].overflow and P.Get(ID, KEYS[target.key].overflow) or 1
    local sig, running, source = BarsSignature(), Page.Running(), S.CooldownManagerBarEntries
    local same = self.valid == true and self.mSlot == slot and self.mBlocked == blocked and self.mGen == gen
        and self.mSpec == spec and self.mLists == lists and self.mSpells == spells and self.mCap == cap
        and self.mHide == hide and self.mSig == sig and self.mRunning == running and self.mSource == source
        and self.mRoute == route and self.mChain == chain
    self.valid = true
    self.mSlot, self.mBlocked, self.mGen, self.mSpec, self.mLists, self.mSpells = slot, blocked, gen, spec, lists, spells
    self.mCap, self.mHide, self.mSig, self.mRunning, self.mSource = cap, hide, sig, running, source
    self.mRoute, self.mChain = route, chain
    return same
end

-- Fills one pooled tile from a runtime entry. Returns true while the
-- client has not loaded the entry's icon yet (asked again next refresh).
local function PaintTile(tile, entry, key, slot, spells, lit)
    tile.key, tile.name, tile.texture = key, entry.name, entry.texture
    tile.known, tile.hidden, tile.family = Plain(entry.known) ~= false, Plain(entry.hidden) == true, EntryFamily(entry, slot)
    -- Optional runtime fields: the rule that hides it, and the unit
    -- "Automatic" tracks its buff on.
    tile.hiddenBy, tile.unit, tile.movedTo = Plain(entry.hiddenBy), Plain(entry.unit), Plain(entry.movedTo)
    -- A cooldown that tracks a buff shows it on the icon (stack options).
    tile.aura = tile.family == 2 or Plain(entry.hasAura) == true
    SetIcon(tile.icon, tile.texture)
    tile.icon:SetDesaturated(not tile.known)
    tile:SetAlpha(tile.known and 1 or 0.55)
    tile.mark:SetShown(spells[key] ~= nil)
    tile.ruleMark:SetShown(tile.hidden)
    PaintEdge(tile, lit)
    tile:Show()
    return Public(tile.texture) and tile.texture == nil
end

-- Tiles for the entries (pooled; one per key), then the unused ones hidden.
-- Returns the tile count, the tile of the open popover's entry and whether
-- an icon is still loading.
function Grid:PaintTiles(entries, slot, openKey, fromGrid)
    -- Own options in effect for this specialization, as the runtime reads them.
    local spells = Page.EffectiveSpells()
    local count, openTile, loading = 0, nil, false
    local byKey = self.byKey
    for key in pairs(byKey) do byKey[key] = nil end
    for i = 1, entries and #entries or 0 do
        local entry = entries[i]
        local key = EntryKey(entry)
        if key then
            count = count + 1
            local tile = self.tiles[count]
            if not tile then
                tile = NewTile(self, count, false)
                self.tiles[count] = tile
            end
            if byKey[key] == nil then byKey[key] = tile end
            if PaintTile(tile, entry, key, slot, spells, fromGrid and key == openKey) then loading = true end
            if key == openKey then openTile = tile end
        end
    end
    for i = count + 1, #self.tiles do
        local tile = self.tiles[i]
        tile.key = nil
        tile:Hide()
    end
    self.count = count
    return count, openTile, loading
end

-- Rows of tiles with the + tile last; returns the tiles per row.
function Grid:Layout(count)
    local perRow = max(1, floor((self.width + GAP) / (TILE + GAP)))
    for i = 1, count + 1 do
        local tile = i <= count and self.tiles[i] or self.plus
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", self.host, "TOPLEFT", ((i - 1) % perRow) * (TILE + GAP), -floor((i - 1) / perRow) * (TILE + GAP))
    end
    return perRow
end

-- Lays out the selected bar's entries; returns the grid height.
function Grid:Refresh()
    local slot = Page.selected
    local blocked = Page.EditorBlocked()
    local popover = Page.popover
    if self:Same(slot, blocked) then
        -- Bar values shown as hints in the open popover may have changed.
        if popover and popover:IsShown() then Page.PaintPopover() end
        return self.height
    end
    local entries = not blocked and Page.Entries(slot) or nil
    local openKey = popover and popover:IsShown() and popover.slot == slot and popover.key or nil
    -- A popover opened from the preview stays on its preview icon.
    local fromGrid = openKey ~= nil and popover.anchor ~= nil and popover.anchor.grid == self
    local count, openTile, loading = self:PaintTiles(entries, slot, openKey, fromGrid)
    local perRow = self:Layout(count)
    self.plus:SetShown(entries ~= nil)
    if blocked then
        SetRaw(self.message, blocked)
    elseif count == 0 then
        SetRaw(self.message, Tr("No spells yet. Click + to add some."))
    else
        self.message:SetText("")
    end
    self.message:SetShown(count == 0)
    if popover and popover:IsShown() then
        if openTile then
            popover.hasAura, popover.unit = openTile.aura, openTile.unit
            if fromGrid then Page.PlacePopup(popover, openTile) end
            Page.PaintPopover()
        else
            popover:Hide()
        end
    end
    local rows = floor(count / perRow) + 1
    local height = rows * (TILE + GAP) - GAP
    self.host:SetHeight(height)
    self.height = height
    if loading then self.valid = false end
    -- The preview marks its icons from these tiles.
    local ui = self.ui
    if ui and ui.PaintHitMarks then ui.PaintHitMarks() end
    return height
end

-- The dragged icon under the cursor, shared by the list and the preview.
function Page.ShowGhost(texture)
    local ghost = Page.ghost
    if not ghost then
        ghost = CreateFrame("Frame", nil, _G.UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetSize(TILE, TILE)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetAllPoints(ghost)
        ghost.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
        ghost:SetAlpha(0.8)
        Page.ghost = ghost
    end
    SetIcon(ghost.icon, texture)
    ghost:Show()
end
function Page.MoveGhost(x, y)
    local ghost = Page.ghost
    if not ghost then return end
    local uiScale = Scale(_G.UIParent)
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT", x / uiScale, y / uiScale)
end
function Page.HideGhost()
    if Page.ghost then Page.ghost:Hide() end
end
-- A drop onto another bar's chip moves the entry there; a drop on this bar
-- puts it before beforeKey (last without one). One history entry.
function Page.CommitDrop(key, family, name, slot, beforeKey)
    if slot then
        local ok, reason = Page.MoveEntry(key, slot, nil, family)
        if ok then Page.Note(format(Tr("Moved %s to %s."), name, Page.BarName(slot))) else Page.Fail(reason) end
        return ok
    end
    if beforeKey == key then return true end
    local ok, reason = Page.MoveEntry(key, Page.selected, beforeKey, family)
    if not ok then Page.Fail(reason) end
    return ok
end

-- Drag: 3 px threshold, OnUpdate only while the left button is held.
function Grid:Update()
    if P.Combat() then
        self:CancelDrag()
        return
    end
    local x, y = Cursor()
    if not x then return end
    if not self.dragTile then
        local scale = Scale(self.host)
        local dx, dy = (x - self.pressX) / scale, (y - self.pressY) / scale
        if dx * dx + dy * dy < 9 then return end
        self:StartDrag()
    end
    Page.MoveGhost(x, y)
    self:Target(x)
end
function Grid:StartDrag()
    local tile = self.pressTile
    self.dragTile = tile
    Page.ClosePopups()
    Page.ShowGhost(tile.texture)
    tile:SetAlpha(0.3)
end
function Grid:Target(cursorX)
    self.dropTile, self.dropAfter, self.dropSlot = nil, nil, nil
    local chipSlot = Page.ChipUnderCursor()
    if chipSlot and chipSlot ~= Page.selected then
        self.dropSlot = chipSlot
        self.marker:Hide()
        Page.HighlightChip(chipSlot)
        return
    end
    Page.HighlightChip(nil)
    for i = 1, self.count do
        local tile = self.tiles[i]
        if tile:IsMouseOver() then
            local left, width = tile:GetLeft(), tile:GetWidth()
            local after = type(left) == "number" and type(width) == "number"
                and cursorX / Scale(tile) > left + width / 2 or false
            self.dropTile, self.dropAfter = tile, after
            self.marker:ClearAllPoints()
            self.marker:SetPoint("CENTER", tile, after and "RIGHT" or "LEFT", after and GAP / 2 or -GAP / 2, 0)
            self.marker:Show()
            return
        end
    end
    if self.plus:IsMouseOver() then
        self.dropTile, self.dropAfter = self.plus, false
        self.marker:ClearAllPoints()
        self.marker:SetPoint("CENTER", self.plus, "LEFT", -GAP / 2, 0)
        self.marker:Show()
        return
    end
    self.marker:Hide()
end
function Grid:Drop()
    local tile, target, after, slot = self.dragTile, self.dropTile, self.dropAfter, self.dropSlot
    local key, family, name = tile.key, tile.family, Public(tile.name) and tile.name or tile.key
    self:CancelDrag()
    if slot then
        Page.CommitDrop(key, family, name, slot)
        return
    end
    if not target then return end
    local beforeKey
    if target ~= self.plus then
        if after then beforeKey = self:NextKey(target.key) else beforeKey = target.key end
    end
    Page.CommitDrop(key, family, name, nil, beforeKey)
end
function Grid:CancelDrag()
    self.host:SetScript("OnUpdate", nil)
    local tile = self.dragTile
    if tile then tile:SetAlpha(tile.known and 1 or 0.55) end
    local dragging = tile ~= nil
    self.pressTile, self.dragTile, self.dropTile, self.dropAfter, self.dropSlot = nil, nil, nil, nil, nil
    self.marker:Hide()
    if dragging then
        Page.HideGhost()
        Page.HighlightChip(nil)
    end
end
