local _, P = ...
-- Cooldown manager page: docked preview, the main editor of the selected
-- bar. The runtime draws the bar with its own icon and layout code; the stage
-- cancels the menu's scale so the bar shows at its in-game size. Bar chips
-- select a bar and take dropped spells; the drawn icons are edited in place
-- through the buttons of CooldownManagerPreviewIcons.lua (loaded first).
local Page = P.CDMPage
local S, M, W, T, Tr = P.S, P.M, P.W, P.T, P.Tr
local ID, PAGE = Page.ID, Page.PAGE
local SLOTS = P.Suite.CDM.SLOTS
local SECTION = Page.PREVIEW_SECTION
local COMPACT, EXPANDED, STRIP_ROW = 132, 330, 24
-- The hint (or note) line under the canvas, the + tile beside the drawing
-- and the rim around it that still drags the whole bar.
local LINE, RIM = 18, 6
local PLUS, PLUS_GAP = Page.PREVIEW_PLUS, Page.PREVIEW_PLUS_GAP
local max, min, floor, abs, format = math.max, math.min, math.floor, math.abs, string.format
local BuildDrag, DragCancel = Page.BuildPreviewIcons, Page.CancelPreviewDrag
local PaintHits, PaintMarks, FollowPopover = Page.PaintPreviewIcons, Page.PaintPreviewMarks, Page.FollowPreviewPopover
local DOT = " \194\183 "
-- Joined text cannot be looked up, so each part translates on its own.
local HINT = Tr("Click a spell for its settings") .. DOT .. Tr("drag to reorder or onto a bar above") .. DOT
    .. Tr("middle-click removes") .. DOT .. Tr("+ adds")
local TIP = Tr("Click: settings") .. DOT .. Tr("Drag: reorder") .. DOT .. Tr("Middle-click: remove")

------------------------------------------------------------------ activation
-- The runtime keeps every bar visible while the page is open (rules
-- suspended) and stops its sample animation when the page closes. Idempotent:
-- the preview repaint calls it too, so enabling the module while the page is
-- open (or a runtime that loaded after combat) starts the preview mode.
function Page.Activate()
    if P.Combat() then return end
    Page.EnsureRuntime()
    if S.CooldownManagerSetPreview and S.CooldownManagerSetPreview(true) ~= false then Page.previewOn = true end
    -- The runtime ends the simulation on its own (combat, module off); the
    -- toggle shows what actually runs.
    if Page.simulating and S.CooldownManagerSimulate then
        Page.simulating = S.CooldownManagerSimulate(true) == true
    end
end
-- Each layout of the page (Menu2 keeps one per window size) owns its own
-- stage. Only the layout that is live turns the preview mode off, so a
-- cached layout hiding late never stops the one on screen.
function Page.Deactivate(ui)
    ui = ui or Page.ui
    local stage = ui and ui.stage
    if stage and S.CooldownManagerReleasePreview then S.CooldownManagerReleasePreview(stage) end
    if ui then ui.live = false end
    if ui and Page.ui ~= ui then return end
    if Page.simulating and S.CooldownManagerSimulate then S.CooldownManagerSimulate(false) end
    Page.simulating = false
    if Page.previewOn and S.CooldownManagerSetPreview then S.CooldownManagerSetPreview(false) end
    Page.previewOn = false
    Page.ClosePopups()
    -- The note's 8 s timer never outlives the page.
    Page.ClearNote()
end
function Page.SetSimulate(on)
    if P.Combat() or not S.CooldownManagerSimulate then return false end
    -- The runtime refuses while the module is off or in combat.
    Page.simulating = S.CooldownManagerSimulate(on == true) == true
    P.Refresh()
    return Page.simulating
end

-- x/y of the selected bar: its place when free, an offset from its attach
-- point otherwise.
function Page.WriteOffsets(x, y)
    if P.Combat() then return false end
    local xKey, yKey = Page.Key("x"), Page.Key("y")
    local rules = P.catalog[ID].rules
    x = max(rules[xKey].min, min(rules[xKey].max, floor((tonumber(x) or 0) + 0.5)))
    y = max(rules[yKey].min, min(rules[yKey].max, floor((tonumber(y) or 0) + 0.5)))
    return P.SetMany(ID, { [xKey] = x, [yKey] = y }) == true
end

------------------------------------------------------------------ bar chips
function Page.ChipUnderCursor()
    local chips = Page.ui and Page.ui.chips
    if not chips then return nil end
    for i = 1, #SLOTS do
        local chip = chips[SLOTS[i].key]
        if chip and chip:IsVisible() and chip:IsMouseOver() then return chip.slot end
    end
end
function Page.HighlightChip(slot)
    local chips = Page.ui and Page.ui.chips
    if not chips then return end
    for i = 1, #SLOTS do
        local chip = chips[SLOTS[i].key]
        if chip then chip.drop:SetShown(slot ~= nil and chip.slot == slot) end
    end
end

-- Left click selects the bar, right click opens its actions.
local function ChipClick(self, button)
    if self.add then
        Page.OpenAddBar(self)
        return
    end
    if button == "RightButton" then
        Page.OpenBarMenu(self, self.slot)
        return
    end
    Page.Select(self.slot)
end
local function ChipEnter(self)
    if self.add then
        Page.ShowTip(self, Tr("Add a bar"), Tr("Up to six custom bars for cooldowns, buff icons or timer bars."))
        return
    end
    local slot = self.slot
    local state = Page.KindName(Page.Kind(slot)) .. (Page.IsOn(slot) and "" or ("  -  " .. Tr("off")))
    Page.ShowTip(self, Page.BarName(slot), state,
        Tr("Click to edit this bar, right-click for its actions. Drop a spell here to move it to this bar."))
end
local function ChipLeave(self) Page.HideTip(self) end
local function NewChip(ui, slot)
    local chip = Page.Button(ui.strip, "", 96, 20, ChipClick)
    if chip.RegisterForClicks then chip:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    chip.slot = slot
    chip.drop = chip:CreateTexture(nil, "OVERLAY")
    chip.drop:SetAllPoints(chip)
    local r, g, b = Page.Accent()
    chip.drop:SetColorTexture(r, g, b, 0.35)
    chip.drop:Hide()
    chip:HookScript("OnEnter", ChipEnter)
    chip:HookScript("OnLeave", ChipLeave)
    if M.RegisterControlMetadata then
        local info = slot and Page.SlotInfo(slot)
        M.RegisterControlMetadata(chip, P.Meta(PAGE, ID, "preview.bar." .. (slot or "add"), "action", SECTION),
            info and info.title or "Add a bar", "button")
    end
    return chip
end
-- Measures a chip when its caption changes and moves it when its place
-- changes: a repaint of the same strip writes nothing.
local function PlaceChip(ui, chip, text, x, row, width)
    if chip._cdmText ~= text then
        chip._cdmText = text
        Page.ButtonText(chip, text)
        local w = T.MeasureButtonWidth and T.MeasureButtonWidth(chip, 64, 170) or 110
        chip._cdmWidth = w
        chip:SetWidth(w)
    end
    local w = chip._cdmWidth
    if x > 0 and x + w > width then x, row = 0, row + 1 end
    if chip._cdmX ~= x or chip._cdmRow ~= row then
        chip._cdmX, chip._cdmRow = x, row
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", ui.strip, "TOPLEFT", x, -row * STRIP_ROW)
    end
    return x + w + 4, row
end
local function ShowChip(chip, show)
    if chip._cdmShown ~= show then
        chip._cdmShown = show
        chip:SetShown(show)
    end
end
-- Every listed bar: shown ones, the built-in bars and custom bars that were
-- set up; bars that are off are dimmed. Returns the strip height.
local function PaintStrip(ui, width)
    local x, row = 0, 0
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local chip = ui.chips[slot]
        local show = Page.Listed(slot)
        ShowChip(chip, show)
        if show then
            x, row = PlaceChip(ui, chip, Page.BarName(slot), x, row, width)
            local active, alpha = slot == Page.selected, Page.IsOn(slot) and 1 or 0.5
            if chip._cdmActive ~= active then
                chip._cdmActive = active
                chip:SetActive(active)
            end
            if chip._cdmAlpha ~= alpha then
                chip._cdmAlpha = alpha
                chip:SetAlpha(alpha)
            end
        end
    end
    local add = ui.addChip
    local free = Page.FreeCustom() ~= nil
    ShowChip(add, free)
    if free then x, row = PlaceChip(ui, add, Tr("+ Add bar"), x, row, width) end
    local height = (row + 1) * STRIP_ROW
    if ui.stripHeight ~= height then
        ui.stripHeight = height
        ui.strip:SetHeight(height)
    end
    return height
end

------------------------------------------------------------------ preview
local function HandleEnter(self)
    if P.Combat() then return end
    self.hover:Show()
    local slot = Page.selected
    Page.ShowTip(self, Page.BarName(slot), Page.Movable(slot) and Tr("Drag the bar's edge to move it on screen.")
        or Page.AttachedText(slot),
        Tr("Click to open its Basics: size and attachment."))
end
local function HandleLeave(self)
    self.hover:Hide()
    Page.HideTip(self)
end
-- The drawing sits left of center by half the + tile beside it (stage
-- units, counted in the drawing's own scale), so both stay centered.
local function Place(self, dx, dy)
    local frame = self.target
    if not frame then return end
    local own = tonumber((frame:GetScale())) or 1
    if own <= 0 then own = 1 end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", self.stage, "CENTER", ((self.baseX or 0) + dx) / own, dy / own)
end
-- The drawn bar follows the cursor while the button is held (the only
-- per-frame work, cleared on release, hide and combat); the release writes
-- the new offset and the next paint centers the drawing again.
local function Recenter(self) Place(self, 0, 0) end
local function StopDrag(self)
    self:SetScript("OnUpdate", nil)
    self.dragging = nil
end
local function HandleDrag(self)
    if P.Combat() or not self.downX then
        self.downX, self.downY = nil, nil
        StopDrag(self)
        Recenter(self)
        return
    end
    local x, y = Page.Cursor()
    if not x then return end
    local scale = Page.Scale(_G.UIParent)
    local dx, dy = (x - self.downX) / scale, (y - self.downY) / scale
    if not self.dragging then
        if abs(dx) + abs(dy) < 3 then return end
        self.dragging = true
        Page.HideTip(self)
    end
    Place(self, dx, dy)
end
local function HandleDown(self, button)
    if button ~= "LeftButton" or P.Combat() then return end
    self.downX, self.downY = Page.Cursor()
    if self.downX and Page.Movable(Page.selected) then self:SetScript("OnUpdate", HandleDrag) end
end
local function HandleUp(self, button)
    if button ~= "LeftButton" or not self.downX then return end
    local startX, startY = self.downX, self.downY
    local dragged = self.dragging
    self.downX, self.downY = nil, nil
    StopDrag(self)
    local x, y = Page.Cursor()
    if not x or P.Combat() then
        Recenter(self)
        return
    end
    local scale = Page.Scale(_G.UIParent)
    local dx, dy = (x - startX) / scale, (y - startY) / scale
    if not dragged and abs(dx) + abs(dy) < 3 then
        Page.FocusSection("basics")
        return
    end
    local slot = Page.selected
    if not Page.Movable(slot) then
        Page.Note(Page.AttachedText(slot), nil, true)
        return
    end
    if not Page.WriteOffsets(P.Get(ID, Page.Key("x")) + dx, P.Get(ID, Page.Key("y")) + dy) then Recenter(self) end
end
local function HandleHide(self)
    self.downX, self.downY = nil, nil
    StopDrag(self)
end

-- Spec, the bar's place (so a drag or nudge shows its result) and the
-- runtime's takeover note.
local function StatusText()
    local _, specName = Page.Spec()
    local slot = Page.selected
    local text = specName and format(Tr("Spells for %s."), specName) or ""
    if not Page.IsOn(slot) then
        text = text .. "  " .. Tr("This bar is off.")
    elseif Page.Movable(slot) then
        local label = P.Get(ID, Page.Key("anchor")) == 1 and "Position %d, %d." or "Offset %d, %d from its anchor."
        text = text .. "  " .. format(Tr(label), P.Get(ID, Page.Key("x")), P.Get(ID, Page.Key("y")))
    end
    local status = S.CooldownManagerStatus and S.CooldownManagerStatus()
    if type(status) == "string" and status ~= "" then text = text .. "  " .. status end
    return text
end


------------------------------------------------------------------ build
-- Toolbar: a short hint and Simulate, whose tooltip says why it is greyed.
local function SimulateEnter(self)
    Page.ShowTip(self, Tr("Simulate"), Tr("Plays sample cooldowns, glows and buffs on your bars while this page is open."),
        not Page.Running() and Tr("Turn the cooldown manager on in Basics to play it.") or nil)
end
local function BuildToolbar(ui, toolbar)
    local hint = T.Font(toolbar, "GameFontDisableSmall", "Pick a bar below. Drag the bar's edge to move it.", T.colors.muted)
    hint:SetPoint("LEFT", toolbar, "LEFT", 150, 0)
    hint:SetPoint("RIGHT", toolbar, "RIGHT", -200, 0)
    hint:SetJustifyH("LEFT")
    local simulate = Page.Button(toolbar, "Simulate", 84, 22, function() Page.SetSimulate(not Page.simulating) end)
    simulate:SetPoint("RIGHT", toolbar, "RIGHT", -106, 0)
    simulate:SetMotionScriptsWhileDisabled(true)
    simulate:HookScript("OnEnter", SimulateEnter)
    simulate:HookScript("OnLeave", ChipLeave)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(simulate, P.Meta(PAGE, ID, "preview.simulate", "action", SECTION), "Simulate", "button")
    end
    ui.simulate = simulate
end

local function BuildStrip(ui, body)
    ui.strip = CreateFrame("Frame", nil, body)
    ui.strip:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    ui.strip:SetSize(ui.width, STRIP_ROW)
    ui.chips = {}
    for i = 1, #SLOTS do ui.chips[SLOTS[i].key] = NewChip(ui, SLOTS[i].key) end
    ui.addChip = NewChip(ui, nil)
    ui.addChip.add = true
end

-- The stage inside the canvas cancels the menu's scale; the message stands
-- in while nothing is drawn.
local function BuildCanvas(ui, body)
    local canvas = CreateFrame("Frame", nil, body)
    canvas:SetPoint("TOPLEFT", ui.strip, "BOTTOMLEFT", 0, -4)
    canvas:SetSize(ui.width, COMPACT - STRIP_ROW - 22)
    local background = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints(canvas)
    background:SetColorTexture(0.07, 0.09, 0.12, 0.97)
    local chrome = M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(canvas, "canvas", T) end
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetAllPoints(canvas)
    local message = T.Font(canvas, "GameFontHighlightSmall", "", T.colors.muted)
    message:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    message:SetWidth(ui.width - 40)
    ui.stage, ui.canvas, ui.message = stage, canvas, message
end

-- The rim around the drawing: hover, click for Basics, drag to move.
local function BuildHandle(ui)
    local canvas = ui.canvas
    local handle = CreateFrame("Button", nil, canvas)
    handle:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 0) + 30)
    handle:RegisterForClicks("LeftButtonUp")
    handle.hover = handle:CreateTexture(nil, "OVERLAY")
    handle.hover:SetAllPoints(handle)
    local r, g, b = Page.Accent()
    handle.hover:SetColorTexture(r, g, b, 0.14)
    handle.hover:Hide()
    handle._key, handle._color = "bar", { r, g, b }
    handle:SetScript("OnEnter", HandleEnter)
    handle:SetScript("OnLeave", HandleLeave)
    handle:SetScript("OnMouseDown", HandleDown)
    handle:SetScript("OnMouseUp", HandleUp)
    handle:SetScript("OnHide", HandleHide)
    handle.stage = ui.stage
    handle:Hide()
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(handle, P.Meta(PAGE, ID, "preview.bar", "action", SECTION), "Selected bar", "button")
    end
    ui.handle = handle
end

-- One line under the canvas: the hint, or the last note with its Undo.
local function BuildNoteLine(ui, body)
    local canvas = ui.canvas
    local line = T.Font(body, "GameFontDisableSmall", HINT, T.colors.muted)
    line:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 2, -4)
    line:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", -88, -4)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    local undo = Page.Button(body, "Undo", 80, LINE, Page.RunUndo)
    undo:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -1)
    undo:Hide()
    ui.previewLine, ui.previewUndo = line, undo
    ui.PaintPreviewNote = function()
        if Page.note then
            Page.SetRaw(line, Page.note)
            if Page.noteError then line:SetTextColor(1, 0.4, 0.35) else line:SetTextColor(Page.TextColor()) end
        else
            line:SetText(HINT)
            line:SetTextColor(Page.MutedColor())
        end
        undo:SetShown(Page.undo ~= nil)
    end
end

-- Menu2's selection bar (expanded preview): nudges and resets the selected
-- bar's x/y; its settings button opens Basics.
local function ReadOffsets() return P.Get(ID, Page.Key("x")), P.Get(ID, Page.Key("y")) end
local function BuildSelection(ui, body)
    local bar = M.PreviewSelectionBar
    if not (bar and bar.Create) then return end
    local handles = { ui.handle }
    local selection = bar.Create(body, {
        Tr = Tr,
        Theme = function() return T end,
        HandleList = function() return handles end,
        HandleLabel = function() return Page.BarName(Page.selected) end,
        IsPlaced = function(item) return item:IsShown() and Page.Movable(Page.selected) end,
        ReadOffsets = ReadOffsets,
        WriteOffsets = function(_, _, x, y) return Page.WriteOffsets(x, y) end,
        NudgeDelta = function(_, dx, dy)
            local x, y = ReadOffsets()
            return Page.WriteOffsets(x + dx, y + dy)
        end,
        ResetOffsets = function()
            local rules = P.catalog[ID].rules
            return Page.WriteOffsets(rules[Page.Key("x")].default, rules[Page.Key("y")].default)
        end,
        OpenSettings = function() Page.FocusSection("basics") end,
        SelectHandle = function() return true end,
        UpdateHint = function() end,
    })
    selection:SetPoint("TOPLEFT", ui.canvas, "BOTTOMLEFT", 0, -(LINE + 6))
    selection:SetPoint("TOPRIGHT", ui.canvas, "BOTTOMRIGHT", 0, -(LINE + 6))
    ui.selection, ui.selectionBar = selection, bar
end

-- Draws the selected bar through the runtime at its in-game size.
local function Render(ui)
    local render, canvas, handle, message = S.CooldownManagerRenderPreview, ui.canvas, ui.handle, ui.message
    if not render then
        Page.SetRaw(message, Page.EditorBlocked() or Tr("The preview needs the cooldown manager."))
        message:Show()
        handle:Hide()
        return nil
    end
    local scale = Page.Scale(_G.UIParent) / Page.Scale(canvas)
    if ui.stageScale ~= scale then
        ui.stageScale = scale
        ui.stage:SetScale(scale)
    end
    local w = (tonumber(canvas:GetWidth()) or ui.width) / scale
    local h = (tonumber(canvas:GetHeight()) or 80) / scale
    -- Room for the + tile right of the drawing; both stay centered.
    local room = (PLUS + PLUS_GAP) / scale
    handle.baseX = -room / 2
    local frame = render(ui.stage, Page.selected, max(40, w - 12 - room), max(20, h - 8))
    handle.target = frame
    if frame then
        -- A drag in progress keeps the drawing under the cursor.
        if not handle.dragging then Recenter(handle) end
        -- The rim around the icons still drags the whole bar.
        if handle.frame ~= frame then
            handle.frame = frame
            handle:ClearAllPoints()
            handle:SetPoint("TOPLEFT", frame, "TOPLEFT", -RIM, RIM)
            handle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", RIM, -RIM)
        end
        handle:Show()
        message:Hide()
    else
        Page.SetRaw(message, Tr("Nothing to show on this bar yet."))
        message:Show()
        handle:Hide()
    end
    return frame
end
local function Paint(ui)
    if P.Combat() then return end
    -- The layout on screen keeps the runtime's preview mode on (the module
    -- may have been switched on while the page is open).
    if ui.live then Page.Activate() end
    local stripHeight = PaintStrip(ui, ui.width)
    local room = ui.compact and (COMPACT - 22 - LINE - 2) or (EXPANDED - 60 - LINE - 2)
    local height = max(40, room - stripHeight)
    if ui.canvasHeight ~= height then
        ui.canvasHeight = height
        ui.canvas:SetHeight(height)
    end
    local frame = Render(ui)
    PaintHits(ui, frame, frame ~= nil and not Page.EditorBlocked())
    FollowPopover(ui)
    local handle, body = ui.handle, ui.previewBody
    handle._label = Page.BarName(Page.selected)
    body._selectedHandle = handle:IsShown() and Page.Movable(Page.selected) and handle or nil
    ui.simulate:SetEnabled(S.CooldownManagerSimulate ~= nil and Page.Running())
    ui.simulate:SetActive(Page.simulating == true)
    Page.SetRaw(ui.status, StatusText())
    if ui.selection and ui.selectionBar.Refresh then ui.selectionBar.Refresh(body) end
end
-- The compact preview keeps the status under the note line; expanded, the
-- selection bar comes in between.
local function ApplyCompact(body, compact)
    local ui = body._cdmUI
    ui.compact = compact == true
    local selection, bar, status = ui.selection, ui.selectionBar, ui.status
    if selection and bar.SetShown then bar.SetShown(body, not ui.compact) end
    status:ClearAllPoints()
    if selection and not ui.compact then
        status:SetPoint("TOPLEFT", selection, "BOTTOMLEFT", 2, -6)
    else
        status:SetPoint("TOPLEFT", ui.canvas, "BOTTOMLEFT", 2, -(LINE + 4))
    end
    Paint(ui)
end

function Page.BuildPreview(ctx, b, ui)
    local section, toolbar, record = W.FixedPreviewSection(ctx, b, { title = Tr("Bar preview"), height = 180, gap = 8 })
    if not section then return end
    ui.width, ui.compact = max(260, (section._msuf2Width or b.width or 720) - 28), true
    -- Tooltip lines, translated once: hovering allocates nothing.
    ui.tips = { hint = Tr(TIP), unlearned = Tr("Not learned right now."), sampleTitle = Tr("Sample icon"),
        sample = Tr("This bar has no spells yet. Click to add some."), plusTitle = Tr("Add spells"),
        plus = Tr("Pick cooldowns, buffs, trinkets or custom IDs for this bar.") }
    BuildToolbar(ui, toolbar)
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -40)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -40)
    body:SetHeight(COMPACT)
    body:SetClipsChildren(true)
    body._cdmUI, ui.previewBody = ui, body
    BuildStrip(ui, body)
    BuildCanvas(ui, body)
    BuildHandle(ui)
    BuildDrag(ui)
    BuildNoteLine(ui, body)
    BuildSelection(ui, body)
    ui.status = T.Font(body, "GameFontDisableSmall", "", T.colors.muted)
    ui.status:SetWidth(ui.width - 4)
    ui.status:SetJustifyH("LEFT")
    ui.PaintPreview = function() Paint(ui) end
    ui.PaintHitMarks = function() PaintMarks(ui) end
    body.ApplyCompactPreviewPresentation = ApplyCompact
    body:SetScript("OnHide", function()
        DragCancel(ui.drag)
        Page.Deactivate(ui)
    end)
    body:ApplyCompactPreviewPresentation(true)
    ui.PaintPreviewNote()
    local expander = W.AttachFixedPreviewExpander(section, toolbar, body, {
        pageKey = ctx.key,
        wrapper = ctx.wrapper,
        compactHeight = COMPACT,
        compactTop = -40,
        expandedHeight = EXPANDED,
        expandedTop = -40,
        expandedSectionHeight = 40 + EXPANDED + 8,
        onStateChanged = ui.PaintPreview,
    })
    if record then
        record.onActivate = function()
            -- Menu2 may show a cached layout without building it again: the
            -- layout being shown takes over the page state.
            Page.ui = ui
            ui.live = true
            if ui.grid then ui.grid.valid = false end
            Page.Activate()
            if expander and M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview() then
                expander:Open("SUITE_COOLDOWN_MANAGER_PREVIEW_ACTIVE")
            end
            Paint(ui)
            -- The runtime may have loaded just now: repaint tiles and gates.
            P.Refresh()
        end
    end
    M.TrackRefresh(ctx, ui.PaintPreview)
end
