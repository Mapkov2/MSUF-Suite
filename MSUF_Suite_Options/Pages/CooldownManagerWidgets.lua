local _, P = ...
-- Cooldown manager page, pooled editors: popups (they close with the menu, on
-- combat and on a click elsewhere), spell tiles and the spell picker.
local Page = P.CDMPage
if not Page then return end
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local CDM = Suite.CDM
local ID = Page.ID
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local EMPTY = {}
local QUESTION = Page.QUESTION
local TILE, GAP = 36, 6
local CROP_MIN, CROP_MAX = Page.CROP_MIN, Page.CROP_MAX
local floor, max, min, format = math.floor, math.max, math.min, string.format
local Public, Plain, EntryKey, SetIcon = Page.Public, Page.Plain, Page.EntryKey, Page.SetIcon
local Accent, TextColor, MutedColor, SetRaw = Page.Accent, Page.TextColor, Page.MutedColor, Page.SetRaw

------------------------------------------------------------------ popups
local function Button(parent, text, width, height, onClick)
    local button = T.Button(parent, text and Tr(text) or "", width, height or 22, { noSearch = true })
    button._msuf2SkipHistoryCheckpoint = true
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end
local function Label(parent, template, text, colorName)
    local label = T.Font(parent, template or "GameFontHighlightSmall", text or "", T.colors and T.colors[colorName or "text"])
    if label.SetJustifyH then label:SetJustifyH("LEFT") end
    if label.SetWordWrap then label:SetWordWrap(false) end
    return label
end
-- Captions built from data skip the locale lookup and the search index.
local function ButtonText(button, text)
    local label = button._msuf2Label
    if label then SetRaw(label, text) else button:SetText(text) end
end
Page.Button, Page.Label, Page.ButtonText = Button, Label, ButtonText

local function Cursor()
    if type(_G.GetCursorPosition) ~= "function" then return nil end
    local x, y = _G.GetCursorPosition()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end
local function Scale(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    return type(scale) == "number" and scale > 0 and scale or 1
end
Page.Cursor, Page.Scale = Cursor, Scale

local function ShowTip(owner, title, first, second, third)
    local tip = _G.GameTooltip
    if not (tip and tip.SetOwner) then return end
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
    local tip = _G.GameTooltip
    if tip and tip.IsOwned and tip:IsOwned(owner) then tip:Hide() end
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
        if Suite.Client.SupportsEvent("GLOBAL_MOUSE_DOWN") then watch:RegisterEvent("GLOBAL_MOUSE_DOWN") end
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
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
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
    local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange()
    local value = self.GetVerticalScroll and self:GetVerticalScroll()
    if type(range) ~= "number" then range = 0 end
    if type(value) ~= "number" then value = 0 end
    self:SetVerticalScroll(max(0, min(range, value - delta * 48)))
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
local function TileEnter(self)
    if self.grid.dragTile then return end
    PaintEdge(self, true)
    if self.plus then
        ShowTip(self, Tr("Add spells"), format(Tr("Pick cooldowns, buffs, trinkets or custom IDs for %s."), Page.BarName(Page.selected)))
        return
    end
    local state = not self.known and Tr("Not learned right now.") or self.hidden and Page.HiddenText(self.hiddenBy) or nil
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
    if grid.message.SetWordWrap then grid.message:SetWordWrap(true) end
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
-- catalog, which bars are on and their types, and the bar's cap and ready
-- rule. A settings write that changes none of these (a slider tick of the
-- look or layout) asks the runtime for nothing and moves no tile.
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
    local generation = S.CooldownManagerGeneration
    local gen = generation and generation() or 0
    local spec = Page.Spec() or 0
    local lists, spells = P.Get(ID, "listsData"), P.Get(ID, "spellsData")
    local cap = k.maxIcons and P.Get(ID, k.maxIcons) or 0
    local hide = k.hideReady and P.Get(ID, k.hideReady) or false
    local sig, running, source = BarsSignature(), Page.Running(), S.CooldownManagerBarEntries
    local same = self.valid == true and self.mSlot == slot and self.mBlocked == blocked and self.mGen == gen
        and self.mSpec == spec and self.mLists == lists and self.mSpells == spells and self.mCap == cap
        and self.mHide == hide and self.mSig == sig and self.mRunning == running and self.mSource == source
    self.valid = true
    self.mSlot, self.mBlocked, self.mGen, self.mSpec, self.mLists, self.mSpells = slot, blocked, gen, spec, lists, spells
    self.mCap, self.mHide, self.mSig, self.mRunning, self.mSource = cap, hide, sig, running, source
    return same
end

-- Lays out the selected bar's entries; returns the grid height.
function Grid:Refresh()
    local slot = Page.selected
    local blocked = Page.EditorBlocked()
    if self:Same(slot, blocked) then
        -- Bar values shown as hints in the open popover may have changed.
        local popover = Page.popover
        if popover and popover:IsShown() then Page.PaintPopover() end
        return self.height
    end
    local entries = not blocked and Page.Entries(slot) or nil
    local spells = Page.SpellOverrides().e
    local popover = Page.popover
    local openKey = popover and popover:IsShown() and popover.slot == slot and popover.key or nil
    -- A popover opened from the preview stays on its preview icon.
    local fromGrid = openKey ~= nil and popover.anchor ~= nil and popover.anchor.grid == self
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
            tile.key, tile.name, tile.texture = key, entry.name, entry.texture
            -- An icon the client has not loaded yet: ask again next refresh.
            if Public(tile.texture) and tile.texture == nil then loading = true end
            tile.known, tile.hidden, tile.family = Plain(entry.known) ~= false, Plain(entry.hidden) == true, EntryFamily(entry, slot)
            -- Optional runtime fields: the rule that hides it, and the unit
            -- "Automatic" tracks its buff on.
            tile.hiddenBy, tile.unit = Plain(entry.hiddenBy), Plain(entry.unit)
            -- A cooldown that tracks a buff shows it on the icon (stack options).
            tile.aura = tile.family == 2 or Plain(entry.hasAura) == true
            SetIcon(tile.icon, tile.texture)
            tile.icon:SetDesaturated(not tile.known)
            tile:SetAlpha(tile.known and 1 or 0.55)
            tile.mark:SetShown(spells[tile.key] ~= nil)
            tile.ruleMark:SetShown(tile.hidden)
            if tile.key == openKey then openTile = tile end
            PaintEdge(tile, fromGrid and tile.key == openKey)
            tile:Show()
        end
    end
    for i = count + 1, #self.tiles do
        local tile = self.tiles[i]
        tile.key = nil
        tile:Hide()
    end
    self.count = count
    local perRow = max(1, floor((self.width + GAP) / (TILE + GAP)))
    for i = 1, count + 1 do
        local tile = i <= count and self.tiles[i] or self.plus
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", self.host, "TOPLEFT", ((i - 1) % perRow) * (TILE + GAP), -floor((i - 1) / perRow) * (TILE + GAP))
    end
    self.plus:SetShown(entries ~= nil)
    if blocked then
        SetRaw(self.message, blocked)
    elseif count == 0 then
        self.message:SetText(Tr("No spells yet. Click + to add some."))
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
    local chipSlot = Page.ChipUnderCursor and Page.ChipUnderCursor()
    if chipSlot and chipSlot ~= Page.selected then
        self.dropSlot = chipSlot
        self.marker:Hide()
        if Page.HighlightChip then Page.HighlightChip(chipSlot) end
        return
    end
    if Page.HighlightChip then Page.HighlightChip(nil) end
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
        if Page.HighlightChip then Page.HighlightChip(nil) end
    end
end

------------------------------------------------------------------ spell picker
local PICK_W, PICK_H = 340, 470
local picker

local function SortCatalog(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.known ~= b.known then return a.known end
    return a.sortName < b.sortName
end
local function Item(n, kind, text, key, texture, known, slot, family, spell, override, tooltip)
    local items = picker.items
    local item = items[n]
    if not item then
        item = {}
        items[n] = item
    end
    item.kind, item.text, item.key, item.texture = kind, text, key, texture
    item.known, item.slot, item.family = known ~= false, slot, family
    item.search = kind == "entry" and Page.SearchText(text, key, spell, override, tooltip) or nil
    return item
end
-- Spell IDs of a catalog row, when the runtime provides them.
local function RowSpell(value)
    value = Plain(value)
    if type(value) == "number" and value > 0 then return value end
end
local function ResolveSpell(text)
    if text == "" then return nil end
    local spell = _G.C_Spell
    local id = tonumber(text)
    if not id and spell and spell.GetSpellIDForSpellIdentifier then
        id = spell.GetSpellIDForSpellIdentifier(text)
        if not Public(id) then id = nil end
    end
    if type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= floor(id) then return nil end
    local name = spell and spell.GetSpellName and spell.GetSpellName(id)
    if not Public(name) or type(name) ~= "string" then return nil end
    local texture = spell.GetSpellTexture and spell.GetSpellTexture(id)
    return id, name, Public(texture) and texture or nil
end
local function ResolveItem(text)
    local id = tonumber(text)
    if type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= floor(id) then return nil end
    local item = _G.C_Item
    if not item then return nil end
    local name = item.GetItemNameByID and item.GetItemNameByID(id)
    local texture = item.GetItemIconByID and item.GetItemIconByID(id)
    if not Public(name) then name = nil end
    if not Public(texture) then texture = nil end
    if name == nil and item.RequestLoadItemDataByID then item.RequestLoadItemDataByID(id) end
    if name == nil and texture == nil then return nil end
    return id, type(name) == "string" and name or format(Tr("Item %d"), id), texture
end

local function PickerRowEnter(self)
    self.hover:Show()
    local item = self.item
    if item and item.kind == "entry" then
        local first = not item.known and Tr("Not learned right now. You can add it anyway.") or nil
        local second = item.slot and item.slot ~= Page.selected and format(Tr("Picking it moves it from %s."), Page.BarName(item.slot)) or nil
        ShowTip(self, Public(item.text) and item.text or item.key, first, second)
    end
end
local function PickerRowLeave(self)
    self.hover:Hide()
    HideTip(self)
end
local function PickerRowClick(self)
    local item = self.item
    if not item or item.kind ~= "entry" or P.Combat() then return end
    Page.PickItem(item)
end
local function PickerRow(index)
    local row = picker.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, picker.content)
    row:SetSize(PICK_W - 40, 24)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    row.text = Label(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.text:SetWidth(PICK_W - 170)
    row.status = Label(row, "GameFontDisableSmall", "", "muted")
    row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.status:SetWidth(112)
    row.status:SetJustifyH("RIGHT")
    row:SetScript("OnClick", PickerRowClick)
    row:SetScript("OnEnter", PickerRowEnter)
    row:SetScript("OnLeave", PickerRowLeave)
    picker.rows[index] = row
    return row
end
local function PaintPickerRow(row, item)
    row.item = item
    local r, g, b = TextColor()
    if item.kind == "header" then
        r, g, b = Accent()
        row.icon:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.text:SetText(item.text)
        row.status:SetText("")
        row:SetAlpha(1)
    else
        row.icon:Show()
        SetIcon(row.icon, item.texture)
        row.icon:SetDesaturated(not item.known)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
        SetRaw(row.text, Public(item.text) and item.text or item.key)
        local status, alpha = "", 1
        if item.slot == Page.selected then
            status, alpha = Tr("On this bar"), 0.45
        elseif item.slot then
            status = format(Tr("On %s"), Page.BarName(item.slot))
        elseif picker.removed[item.key] then
            status = Tr("Removed")
        elseif not item.known then
            status = Tr("Not learned")
        end
        SetRaw(row.status, status)
        row:SetAlpha(item.known and alpha or min(alpha, 0.55))
    end
    row.text:SetTextColor(r, g, b)
end

function Page.FilterPicker()
    if not picker then return end
    local query = Page.Query(picker.search)
    local spec = Page.Spec()
    picker.removed = spec and Page.ListsView().hidden[spec] or EMPTY
    local items, count = picker.items, picker.count
    local any, section = false, nil
    for i = 1, count do
        local item = items[i]
        if item.kind == "header" then
            section = item
            item.match = false
        else
            item.match = query == "" or (item.search ~= nil and item.search:find(query, 1, true) ~= nil)
            if item.match and section then
                section.match = true
                any = true
            end
        end
    end
    local shown = 0
    for i = 1, count do
        local item = items[i]
        if item.match then
            shown = shown + 1
            local row = PickerRow(shown)
            PaintPickerRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", picker.content, "TOPLEFT", 0, -(shown - 1) * 24)
            row:Show()
        end
    end
    for i = shown + 1, #picker.rows do
        picker.rows[i].item = nil
        picker.rows[i]:Hide()
    end
    picker.shown = shown
    picker.content:SetHeight(max(1, shown * 24))
    picker.empty:SetText(any and "" or Tr("Nothing matches. Try a spell ID below."))
    picker.empty:SetShown(not any)
end

function Page.RebuildPicker()
    local slot = Page.selected
    local family = Page.Family(slot)
    SetRaw(picker.title, format(Tr("Add to %s"), Page.BarName(slot)))
    local n = 1
    Item(n, "header", Tr(family == 1 and "Blizzard cooldowns" or "Blizzard buffs"))
    local sorted, bySpell, equip = picker.sorted, picker.bySpell, picker.equip
    for i = #sorted, 1, -1 do sorted[i] = nil end
    for id in pairs(bySpell) do bySpell[id] = nil end
    equip[13], equip[14] = nil, nil
    local catalog = Page.Catalog(family) or EMPTY
    for i = 1, #catalog do
        local entry = catalog[i]
        local key = EntryKey(entry)
        if key and CDM.EntryKind(key) == "e" then
            -- Equipment slots belong to the trinket section below.
            equip[CDM.EntryID(key)] = entry
        elseif key then
            local record = picker.pool[i]
            if not record then
                record = {}
                picker.pool[i] = record
            end
            record.entry, record.key, record.slot = entry, key, Plain(entry.slot)
            record.rank = record.slot == nil and 0 or record.slot == slot and 2 or 1
            record.known = Plain(entry.known) ~= false
            record.sortName = Public(entry.name) and type(entry.name) == "string" and entry.name:lower() or key
            record.spell, record.override = RowSpell(entry.spell), RowSpell(entry.override)
            record.tooltip = RowSpell(entry.tooltip)
            sorted[#sorted + 1] = record
        end
    end
    table.sort(sorted, SortCatalog)
    for i = 1, #sorted do
        local record = sorted[i]
        n = n + 1
        local item = Item(n, "entry", record.entry.name, record.key, record.entry.texture, record.known, record.slot,
            family, record.spell, record.override, record.tooltip)
        if record.spell and not bySpell[record.spell] then bySpell[record.spell] = item end
        if record.override and not bySpell[record.override] then bySpell[record.override] = item end
    end
    if family == 1 then
        n = n + 1
        Item(n, "header", Tr("Trinkets and items"))
        for trinket = 13, 14 do
            local key = "e" .. trinket
            local row = equip[trinket]
            local texture = type(_G.GetInventoryItemTexture) == "function" and _G.GetInventoryItemTexture("player", trinket) or nil
            if not Public(texture) or texture == nil then texture = row and Plain(row.texture) or nil end
            local itemID = type(_G.GetInventoryItemID) == "function" and _G.GetInventoryItemID("player", trinket) or nil
            local name = Public(itemID) and type(itemID) == "number" and _G.C_Item and _G.C_Item.GetItemNameByID
                and _G.C_Item.GetItemNameByID(itemID) or nil
            local label = format(Tr("Trinket slot %d"), trinket - 12)
            if Public(name) and type(name) == "string" then label = label .. ": " .. name end
            -- The runtime knows where the slot lives even without an explicit list.
            local home = row and Plain(row.slot) or Page.WhereIs(key)
            n = n + 1
            Item(n, "entry", label, key, texture, true, home, 1)
        end
    end
    picker.count = n
    picker.family = family
    picker.idTitle:SetText(Tr(family == 1 and "Custom spell or item ID" or "Custom aura ID"))
    picker.addA:SetText(Tr(family == 1 and "Add spell" or "Buff on me"))
    picker.addB:SetText(Tr(family == 1 and "Add item" or "Debuff on target"))
    Page.EchoCustom()
    Page.FilterPicker()
end

function Page.PickItem(item)
    if item.slot == Page.selected then return false end
    local name = Public(item.text) and item.text or item.key
    local from = item.slot
    local ok, reason = Page.AddEntry(Page.selected, item.key, item.family)
    if ok then
        item.slot = Page.selected
        local text = from and format(Tr("Moved %s from %s."), name, Page.BarName(from)) or format(Tr("Added %s."), name)
        SetRaw(picker.note, text)
        Page.Note(text)
    else
        picker.note:SetText(Tr(reason or "That did not work."))
    end
    Page.FilterPicker()
    return ok
end

function Page.EchoCustom()
    local text = (picker.idBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID, spellName, spellIcon = ResolveSpell(text)
    local itemID, itemName, itemIcon
    if picker.family == 1 then itemID, itemName, itemIcon = ResolveItem(text) end
    -- A spell Blizzard's Cooldown Manager already tracks is added as that
    -- entry, so it never shows twice.
    local blizzard = spellID and picker.bySpell[spellID] or nil
    picker.customSpell, picker.customItem, picker.customBlizzard = spellID, itemID, blizzard
    local r, g, b = MutedColor()
    if text == "" then
        picker.echo:SetText(Tr("Type an ID or a spell name."))
    elseif spellID or itemID then
        r, g, b = 0.35, 0.95, 0.45
        local parts = spellID and format(Tr("Spell %d"), spellID) .. ": " .. spellName or ""
        if blizzard then parts = parts .. " (" .. Tr("Blizzard's entry") .. ")" end
        if itemID then parts = parts .. (parts ~= "" and "  |  " or "") .. format(Tr("Item %d"), itemID) .. ": " .. itemName end
        SetRaw(picker.echo, parts)
    else
        r, g, b = 1, 0.35, 0.3
        picker.echo:SetText(Tr("No spell or item with this ID."))
    end
    picker.echo:SetTextColor(r, g, b)
    picker.echoIcon:SetTexture(spellIcon or itemIcon or QUESTION)
    picker.echoIcon:SetShown((spellID or itemID) ~= nil)
    picker.addA:SetEnabled(spellID ~= nil)
    picker.addB:SetEnabled(picker.family == 1 and itemID ~= nil or picker.family ~= 1 and spellID ~= nil)
end
local function AddCustom(prefix)
    if P.Combat() then return end
    local id = prefix == "i" and picker.customItem or picker.customSpell
    if not id then return end
    local blizzard = prefix ~= "i" and picker.customBlizzard or nil
    if blizzard then
        if blizzard.slot == Page.selected then
            picker.note:SetText(Tr("Blizzard's entry for this spell is already on this bar."))
        elseif Page.PickItem(blizzard) then
            picker.idBox:SetText("")
        end
        return
    end
    local key = prefix .. id
    local from = Page.WhereIs(key)
    local ok, reason = Page.AddEntry(Page.selected, key, (prefix == "a" or prefix == "d") and 2 or 1)
    if ok then
        local text = from and from ~= Page.selected and format(Tr("Moved %s from %s."), Page.Identity(key), Page.BarName(from))
            or format(Tr("Added %s."), Page.Identity(key))
        SetRaw(picker.note, text)
        Page.Note(text)
        picker.idBox:SetText("")
    else
        picker.note:SetText(Tr(reason or "That did not work."))
    end
end

local function EnsurePicker()
    if picker then return picker end
    picker = Page.NewPopup(PICK_W, PICK_H)
    Page.picker = picker
    picker.items, picker.rows, picker.sorted, picker.pool, picker.count = {}, {}, {}, {}, 0
    picker.bySpell, picker.equip = {}, {}
    picker.title = Label(picker, "GameFontNormal", "")
    picker.title:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -12)
    picker.title:SetWidth(PICK_W - 60)
    picker.close = Button(picker, "x", 22, 20, function() picker:Hide() end)
    picker.close:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -8, -8)
    picker.search = Page.SearchBox(picker, PICK_W - 28, Tr("Type a name or ID to filter"), Page.FilterPicker)
    picker.search:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -36)
    picker.scroll, picker.content = Page.ScrollArea(picker, PICK_W - 40)
    picker.scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -66)
    picker.scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -26, 132)
    picker.empty = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -72)
    picker.idTitle = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.idTitle:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 112)
    picker.idBox = Page.SearchBox(picker, 120, Tr("ID or name"), Page.EchoCustom)
    picker.idBox:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 16, 82)
    picker.addA = Button(picker, "", 90, 22, function() AddCustom(picker.family == 1 and "s" or "a") end)
    picker.addA:SetPoint("LEFT", picker.idBox, "RIGHT", 8, 0)
    picker.addB = Button(picker, "", 100, 22, function() AddCustom(picker.family == 1 and "i" or "d") end)
    picker.addB:SetPoint("LEFT", picker.addA, "RIGHT", 6, 0)
    picker.echoIcon = picker:CreateTexture(nil, "ARTWORK")
    picker.echoIcon:SetSize(16, 16)
    picker.echoIcon:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 56)
    picker.echoIcon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    picker.echo = Label(picker, "GameFontHighlightSmall", "")
    picker.echo:SetPoint("LEFT", picker.echoIcon, "RIGHT", 6, 0)
    picker.echo:SetWidth(PICK_W - 50)
    picker.note = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.note:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 16)
    picker.note:SetWidth(PICK_W - 28)
    picker.hint = Label(picker, "GameFontDisableSmall", Tr("Picks stay open so you can add several."), "muted")
    picker.hint:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 34)
    picker.OnClosed = function(self)
        self.search:ClearFocus()
        self.idBox:ClearFocus()
    end
    return picker
end

function Page.TogglePicker(anchor)
    if picker and picker:IsShown() and picker.anchor == anchor then
        picker:Hide()
        return false
    end
    if P.Combat() or Page.EditorBlocked() then return false end
    EnsurePicker()
    Page.ClosePopups(picker)
    Page.PlacePopup(picker, anchor)
    picker.note:SetText("")
    picker.search:SetText("")
    picker.idBox:SetText("")
    if picker.scroll.SetVerticalScroll then picker.scroll:SetVerticalScroll(0) end
    Page.RebuildPicker()
    picker:Show()
    return true
end
