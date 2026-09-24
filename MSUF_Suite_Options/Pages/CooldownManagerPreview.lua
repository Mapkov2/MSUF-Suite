local _, P = ...
-- Cooldown manager page: docked preview. The runtime draws the selected bar
-- with its own icon and layout code; the stage cancels the menu's scale so the
-- bar shows at its in-game size. Bar chips select a bar and take dropped tiles.
local Page = P.CDMPage
if not Page then return end
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local ID, PAGE = Page.ID, Page.PAGE
local SLOTS = Suite.CDM.SLOTS
local SECTION = "suite_cooldownManager_preview"
local COMPACT, EXPANDED, STRIP_ROW = 132, 330, 24
local max, min, floor, abs, format = math.max, math.min, math.floor, math.abs, string.format

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

local function ChipClick(self)
    if self.add then Page.OpenAddBar(self); return end
    Page.Select(self.slot)
end
local function ChipEnter(self)
    if self.add then
        Page.ShowTip(self, Tr("Add a bar"), Tr("Up to six custom bars for cooldowns, buff icons or buff bars."))
        return
    end
    local slot = self.slot
    local state = Page.KindName(Page.Kind(slot)) .. (Page.IsOn(slot) and "" or ("  -  " .. Tr("off")))
    Page.ShowTip(self, Page.BarName(slot), state, Tr("Click to edit this bar. Drop a spell tile here to move it."))
end
local function ChipLeave(self) Page.HideTip(self) end
local function NewChip(ui, slot)
    local chip = Page.Button(ui.strip, "", 96, 20, ChipClick)
    chip.slot = slot
    chip.drop = chip:CreateTexture(nil, "OVERLAY")
    chip.drop:SetAllPoints(chip)
    local r, g, b = Page.Color("accent", 0.30, 0.74, 1.00)
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
local function PlaceChip(ui, chip, text, x, row, width)
    if chip.label ~= text then chip.label = text; Page.ButtonText(chip, text) end
    local w = T.MeasureButtonWidth and T.MeasureButtonWidth(chip, 64, 170) or 110
    chip:SetWidth(w)
    if x > 0 and x + w > width then x, row = 0, row + 1 end
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", ui.strip, "TOPLEFT", x, -row * STRIP_ROW)
    return x + w + 4, row
end
-- Enabled bars plus the selected one; returns the strip height.
local function PaintStrip(ui, width)
    local x, row = 0, 0
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local chip = ui.chips[slot]
        local on = Page.IsOn(slot)
        local show = on or slot == Page.selected
        chip:SetShown(show)
        if show then
            x, row = PlaceChip(ui, chip, Page.BarName(slot), x, row, width)
            chip:SetActive(slot == Page.selected)
            chip:SetAlpha(on and 1 or 0.6)
        end
    end
    local add = ui.addChip
    local free = Page.FreeCustom() ~= nil
    add:SetShown(free)
    if free then x, row = PlaceChip(ui, add, Tr("+ Add bar"), x, row, width) end
    ui.strip:SetHeight((row + 1) * STRIP_ROW)
    return (row + 1) * STRIP_ROW
end

------------------------------------------------------------------ preview
local function HandleEnter(self)
    self.hover:Show()
    local slot = Page.selected
    Page.ShowTip(self, Page.BarName(slot), Page.Movable(slot) and Tr("Drag to move this bar.")
        or Page.AttachedText(slot),
        Tr("Click to open its layout."))
end
local function HandleLeave(self) self.hover:Hide(); Page.HideTip(self) end
-- The drawn bar follows the cursor while the button is held (the only
-- per-frame work, cleared on release, hide and combat); the release writes
-- the new offset and the next paint centers the drawing again.
local function Recenter(self)
    local frame = self.target
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", self.stage, "CENTER", 0, 0)
    end
end
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
    local frame = self.target
    if frame then
        -- Offsets count in the drawing's own scale.
        local own = tonumber((frame:GetScale())) or 1
        if own <= 0 then own = 1 end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", self.stage, "CENTER", dx / own, dy / own)
    end
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
    if not x or P.Combat() then Recenter(self); return end
    local scale = Page.Scale(_G.UIParent)
    local dx, dy = (x - startX) / scale, (y - startY) / scale
    if not dragged and abs(dx) + abs(dy) < 3 then Page.FocusSection("layout"); return end
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
    if not Page.IsOn(slot) then text = text .. "  " .. Tr("This bar is off.")
    elseif Page.Movable(slot) then
        local label = P.Get(ID, Page.Key("anchor")) == 1 and "Position %d, %d." or "Offset %d, %d from its anchor."
        text = text .. "  " .. format(Tr(label), P.Get(ID, Page.Key("x")), P.Get(ID, Page.Key("y")))
    end
    local status = S.CooldownManagerStatus and S.CooldownManagerStatus()
    if type(status) == "string" and status ~= "" then text = text .. "  " .. status end
    return text
end

function Page.BuildPreview(ctx, b, ui)
    local section, toolbar, record = W.FixedPreviewSection(ctx, b, { title = Tr("Bar preview"), height = 180, gap = 8 })
    if not section then return end
    local width = max(260, (section._msuf2Width or b.width or 720) - 28)
    local state = { compact = true }
    local hint = T.Font(toolbar, "GameFontDisableSmall", Tr("Click a bar to edit it; drop spell tiles on a bar to move them."), T.colors.muted)
    hint:SetPoint("LEFT", toolbar, "LEFT", 150, 0)
    hint:SetPoint("RIGHT", toolbar, "RIGHT", -200, 0)
    hint:SetJustifyH("LEFT")
    local simulate = Page.Button(toolbar, "Simulate", 84, 22, function() Page.SetSimulate(not Page.simulating) end)
    simulate:SetPoint("RIGHT", toolbar, "RIGHT", -106, 0)
    simulate:HookScript("OnEnter", function(self)
        Page.ShowTip(self, Tr("Simulate"), Tr("Plays sample cooldowns, glows and buffs on your bars while this page is open."))
    end)
    simulate:HookScript("OnLeave", ChipLeave)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(simulate, P.Meta(PAGE, ID, "preview.simulate", "action", SECTION), "Simulate", "button")
    end

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -40)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -40)
    body:SetHeight(COMPACT)
    if body.SetClipsChildren then body:SetClipsChildren(true) end
    ui.previewBody = body
    ui.strip = CreateFrame("Frame", nil, body)
    ui.strip:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    ui.strip:SetSize(width, STRIP_ROW)
    ui.chips = {}
    for i = 1, #SLOTS do ui.chips[SLOTS[i].key] = NewChip(ui, SLOTS[i].key) end
    ui.addChip = NewChip(ui, nil)
    ui.addChip.add = true

    local canvas = CreateFrame("Frame", nil, body)
    canvas:SetPoint("TOPLEFT", ui.strip, "BOTTOMLEFT", 0, -4)
    canvas:SetSize(width, COMPACT - STRIP_ROW - 22)
    local background = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints(canvas)
    background:SetColorTexture(0.07, 0.09, 0.12, 0.97)
    local chrome = M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(canvas, "canvas", T) end
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetAllPoints(canvas)
    ui.stage = stage
    local message = T.Font(canvas, "GameFontHighlightSmall", "", T.colors.muted)
    message:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    message:SetWidth(width - 40)

    local handle = CreateFrame("Button", nil, canvas)
    handle:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 0) + 30)
    handle:RegisterForClicks("LeftButtonUp")
    handle.hover = handle:CreateTexture(nil, "OVERLAY")
    handle.hover:SetAllPoints(handle)
    local r, g, b = Page.Color("accent", 0.30, 0.74, 1.00)
    handle.hover:SetColorTexture(r, g, b, 0.14)
    handle.hover:Hide()
    handle._key, handle._color = "bar", { r, g, b }
    handle:SetScript("OnEnter", HandleEnter)
    handle:SetScript("OnLeave", HandleLeave)
    handle:SetScript("OnMouseDown", HandleDown)
    handle:SetScript("OnMouseUp", HandleUp)
    handle:SetScript("OnHide", HandleHide)
    handle.stage = stage
    handle:Hide()
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(handle, P.Meta(PAGE, ID, "preview.bar", "action", SECTION), "Selected bar", "button")
    end
    ui.handle = handle

    local handles = { handle }
    local selection
    local bar = M.PreviewSelectionBar
    if bar and bar.Create then
        selection = bar.Create(body, {
            Tr = Tr,
            Theme = function() return T end,
            HandleList = function() return handles end,
            HandleLabel = function() return Page.BarName(Page.selected) end,
            IsPlaced = function(item) return item:IsShown() and Page.Movable(Page.selected) end,
            ReadOffsets = function() return P.Get(ID, Page.Key("x")), P.Get(ID, Page.Key("y")) end,
            WriteOffsets = function(_, _, x, y) return Page.WriteOffsets(x, y) end,
            NudgeDelta = function(_, dx, dy)
                return Page.WriteOffsets(P.Get(ID, Page.Key("x")) + dx, P.Get(ID, Page.Key("y")) + dy)
            end,
            ResetOffsets = function()
                local rules = P.catalog[ID].rules
                return Page.WriteOffsets(rules[Page.Key("x")].default, rules[Page.Key("y")].default)
            end,
            OpenSettings = function() Page.FocusSection("layout") end,
            SelectHandle = function() return true end,
            UpdateHint = function() end,
        })
        selection:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -8)
        selection:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -8)
    end
    local status = T.Font(body, "GameFontDisableSmall", "", T.colors.muted)
    status:SetWidth(width - 4)
    status:SetJustifyH("LEFT")

    local function Render()
        local render = S.CooldownManagerRenderPreview
        if not render then
            Page.SetRaw(message, Page.EditorBlocked() or Tr("The preview needs the cooldown manager."))
            message:Show()
            handle:Hide()
            return
        end
        local scale = Page.Scale(_G.UIParent) / Page.Scale(canvas)
        stage:SetScale(scale)
        local w = (tonumber(canvas:GetWidth()) or width) / scale
        local h = (tonumber(canvas:GetHeight()) or 80) / scale
        local frame = render(stage, Page.selected, max(40, w - 12), max(20, h - 8))
        handle.target = frame
        if frame then
            -- A drag in progress keeps the drawing under the cursor.
            if not handle.dragging then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", stage, "CENTER", 0, 0)
            end
            handle:ClearAllPoints()
            handle:SetAllPoints(frame)
            handle:Show()
            message:Hide()
        else
            message:SetText(Tr("Nothing to show on this bar yet."))
            message:Show()
            handle:Hide()
        end
    end
    local function Paint()
        if P.Combat() then return end
        -- The layout on screen keeps the runtime's preview mode on (the
        -- module may have been switched on while the page is open).
        if ui.live then Page.Activate() end
        local stripHeight = PaintStrip(ui, width)
        local room = state.compact and (COMPACT - 22) or (EXPANDED - 60)
        canvas:SetHeight(max(40, room - stripHeight))
        Render()
        handle._label = Page.BarName(Page.selected)
        body._selectedHandle = handle:IsShown() and Page.Movable(Page.selected) and handle or nil
        simulate:SetEnabled(S.CooldownManagerSimulate ~= nil and Page.Running())
        simulate:SetActive(Page.simulating == true)
        Page.SetRaw(status, StatusText())
        if selection and bar.Refresh then bar.Refresh(body) end
    end
    ui.PaintPreview = Paint

    function body:ApplyCompactPreviewPresentation(compact)
        state.compact = compact == true
        if selection and bar.SetShown then bar.SetShown(body, not state.compact) end
        status:ClearAllPoints()
        if selection and not state.compact then
            status:SetPoint("TOPLEFT", selection, "BOTTOMLEFT", 2, -6)
        else
            status:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 2, -4)
        end
        Paint()
    end
    body:SetScript("OnHide", function() Page.Deactivate(ui) end)
    body:ApplyCompactPreviewPresentation(true)
    local expander = W.AttachFixedPreviewExpander(section, toolbar, body, {
        pageKey = ctx.key,
        wrapper = ctx.wrapper,
        compactHeight = COMPACT,
        compactTop = -40,
        expandedHeight = EXPANDED,
        expandedTop = -40,
        expandedSectionHeight = 40 + EXPANDED + 8,
        onStateChanged = function() Paint() end,
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
            Paint()
            -- The runtime may have loaded just now: repaint tiles and gates.
            P.Refresh()
        end
    end
    M.TrackRefresh(ctx, Paint)
end
