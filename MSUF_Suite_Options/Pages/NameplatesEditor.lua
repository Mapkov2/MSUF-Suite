local _, P = ...
local M, W, T, Tr = P.M, P.W, P.T, P.Tr
local ID, PAGE = "nameplates", "suite_nameplates"
local SB, H = M.PreviewSelectionBar, M.PreviewHelpers or {}
local Editor = {}
P.NameplatesEditor = Editor
local DELTA = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Round(v) return math.floor(v + 0.5) end
local function Register(widget, key, label)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(widget, P.Meta(PAGE, ID, "preview." .. key, "action", "suite_nameplates_preview"), label, "button")
    end
end
local function Focus(ui, handle)
    local section = handle and ui.sections and ui.sections[handle.section]
    if section and W.FocusCollapsibleSection then W.FocusCollapsibleSection(section, { persist = true, flash = true }) end
end
local function Write(ui, handle, x, y)
    if P.Combat() then return false end
    local rules = P.catalog[ID].rules
    local xr, yr = rules[handle.keyX], rules[handle.keyY]
    if not xr or not yr then return false end
    local ok = P.SetMany(ID, { [handle.keyX] = Clamp(Round(x), xr.min, xr.max),
        [handle.keyY] = Clamp(Round(y), yr.min, yr.max) })
    ui:Paint()
    return ok ~= false
end
local function Read(handle) return P.Get(ID, handle.keyX), P.Get(ID, handle.keyY) end

function Editor:Select(handle)
    local previous = self.body._selectedHandle
    if previous and previous ~= handle then previous:EnableKeyboard(false) end
    self.body._selectedHandle = handle
    local active = handle and handle:IsShown() and not P.Combat() and self.body:IsShown() or false
    if handle then handle:EnableKeyboard(active) end
    if M.SetPreviewArrowBindings then M.SetPreviewArrowBindings(self.body, active, self.bindings) end
    if active and H.FocusKeyboardTarget then
        H.FocusKeyboardTarget(self.body, handle, false, { selectedField = "_selectedHandle" })
    elseif not active and H.ReleaseKeyboardCapture then H.ReleaseKeyboardCapture(self.body) end
    self:RefreshSelection()
end

function Editor:RefreshSelection()
    local selected = self.body._selectedHandle
    for _, handle in ipairs(self.handles) do
        handle.outline(handle == selected and 1 or 0, "4ebaff")
    end
    if SB then SB.Refresh(self.body) end
end

local function Nudge(ui, dx, dy)
    local handle = ui.body._selectedHandle
    if P.Combat() or not ui.body:IsShown() or not handle or not handle:IsShown() then return false end
    if H.IsTextInputFocused and H.IsTextInputFocused() then return false end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus:IsObjectType("EditBox") then return false end
    local step = H.NudgeStep and H.NudgeStep() or (IsControlKeyDown() and 10 or IsShiftKeyDown() and 5 or 1)
    if H.ShouldSkipDuplicateNudge and H.ShouldSkipDuplicateNudge(ui.body, dx * step, dy * step) then return true end
    local x, y = Read(handle)
    return Write(ui, handle, x + dx * step, y + dy * step)
end

local function Key(self, key)
    local ui = self.previewUI
    if key == "ESCAPE" then
        ui:CancelDrag()
        ui:Select(nil)
        self:SetPropagateKeyboardInput(false)
    elseif key == "TAB" and SB and SB.CycleHandle then
        self:SetPropagateKeyboardInput(not SB.CycleHandle(ui.body, IsShiftKeyDown()))
    else
        local d = DELTA[key]
        self:SetPropagateKeyboardInput(not (d and Nudge(ui, d[1], d[2])))
    end
end

function Editor:CancelDrag()
    local handle = self.dragging
    if handle then handle:StopMovingOrSizing(); handle._npDrag = nil; self.dragging = nil end
    if self.panning then self.stage:StopMovingOrSizing(); self.panning = nil end
    self:Paint()
end

local function Start(self, button)
    if button and button ~= "LeftButton" then return end
    local ui = self.previewUI
    if P.Combat() or self._npDrag then return end
    ui:Select(self)
    local x, y = GetCursorPosition()
    local ox, oy = Read(self)
    self._npDrag = { x = x, y = y, ox = ox, oy = oy, scale = self:GetEffectiveScale() }
    ui.dragging = self
    self:StartMoving()
end

local function Stop(self, button)
    if button and button ~= "LeftButton" then return end
    local ui, drag = self.previewUI, self._npDrag
    if not drag then return end
    self:StopMovingOrSizing()
    self._npDrag, ui.dragging = nil, nil
    local x, y = GetCursorPosition()
    local dx, dy = x - drag.x, y - drag.y
    if not P.Combat() and math.abs(dx) + math.abs(dy) >= 3 then
        Write(ui, self, drag.ox + dx / drag.scale, drag.oy + dy / drag.scale)
        if H.NotePreviewElementMoved then H.NotePreviewElementMoved() end
    else
        ui:Paint()
    end
end

function Editor:Bind(handle, id, label, keyX, keyY, section)
    handle.previewUI, handle._key, handle._label = self, id, label
    handle._color, handle.keyX, handle.keyY, handle.section = { 0.3, 0.74, 1 }, keyX, keyY, section
    local border = P.Suite.NameplateStyle.CreateBorder(handle)
    handle.outline = function(size, color) P.Suite.NameplateStyle.PaintBorder(border, handle, size, color) end
    handle:EnableMouse(true)
    handle:SetMovable(true)
    handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    handle:RegisterForDrag("LeftButton")
    handle:EnableMouseWheel(true)
    handle:SetScript("OnMouseWheel", function(_, delta)
        self.zoom = Clamp(self.zoom + delta * 0.1, 0.5, 2)
        self:Paint()
    end)
    handle:SetScript("OnMouseDown", Start)
    handle:SetScript("OnMouseUp", Stop)
    handle:SetScript("OnDragStart", Start)
    handle:SetScript("OnDragStop", Stop)
    handle:SetScript("OnClick", function(_, button)
        self:Select(handle)
        if button == "RightButton" then Focus(self, handle) end
    end)
    handle:SetScript("OnEnter", function()
        handle.outline(1, "4ebaff")
        self.hint:SetText(Tr(label) .. " · " .. Tr("Drag to move; right-click for settings"))
    end)
    handle:SetScript("OnLeave", function() self:RefreshSelection(); self.hint:SetText(Tr(self.help)) end)
    handle:SetScript("OnKeyDown", Key)
    handle:SetScript("OnHide", function()
        if handle._npDrag then handle:StopMovingOrSizing(); handle._npDrag = nil; self.dragging = nil end
        if self.body._selectedHandle == handle then self:Select(nil) end
    end)
    self.handles[#self.handles + 1] = handle
    Register(handle, id, label)
end

function Editor:Paint()
    if self.dragging or self.panning then return end
    self.stage:ClearAllPoints()
    self.stage:SetPoint("CENTER", self.canvas, "CENTER", self.panX, self.panY)
    self.stage:SetScale(self.zoom)
    for _, render in ipairs(self.renderers) do render() end
    if self.zoomLabel then self.zoomLabel:SetText(string.format("%d%%", Round(self.zoom * 100))) end
    self:RefreshSelection()
end

local function Button(ui, parent, key, label, width, x, action)
    local button = T.Button(parent, Tr(label), width, 20)
    button:SetPoint("LEFT", parent, "LEFT", x, 0)
    button:SetScript("OnClick", action)
    Register(button, key, label)
    return button
end

local function BuildTools(ui)
    local body, canvas = ui.body, ui.canvas
    local tools = CreateFrame("Frame", nil, body)
    tools:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -4)
    tools:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -4)
    tools:SetHeight(22)
    Button(ui, tools, "fit", "Fit", 36, 0, function()
        ui.panX, ui.panY = 0, 0
        ui.zoom = Clamp((canvas:GetWidth() - 40) / 600, 0.5, 1)
        ui:Paint()
    end)
    Button(ui, tools, "actual", "1:1", 36, 40, function() ui.zoom = 1; ui:Paint() end)
    Button(ui, tools, "zoomOut", "-", 24, 80, function() ui.zoom = Clamp(ui.zoom - 0.1, 0.5, 2); ui:Paint() end)
    ui.zoomLabel = T.Font(tools, "GameFontDisableSmall", "100%", T.colors.text)
    ui.zoomLabel:SetPoint("LEFT", tools, "LEFT", 112, 0)
    Button(ui, tools, "zoomIn", "+", 24, 156, function() ui.zoom = Clamp(ui.zoom + 0.1, 0.5, 2); ui:Paint() end)
    Button(ui, tools, "context", "Outdoor / Dungeon", 128, 188, function() ui.inDungeon = not ui.inDungeon; ui:Paint() end)
    Button(ui, tools, "health", "Health", 56, 320, function() ui.health = ui.health == 100 and 53 or 100; ui:Paint() end)
    Button(ui, tools, "cast", "Cast", 48, 380, function() ui.hideCast = not ui.hideCast; ui:Paint() end)
    Button(ui, tools, "target", "Target", 54, 432, function() ui.hideTarget = not ui.hideTarget; ui:Paint() end)
    Button(ui, tools, "interrupt", "Shield", 54, 490, function() ui.uninterruptible = not ui.uninterruptible; ui:Paint() end)
    local samples = CreateFrame("Frame", nil, body)
    samples:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8)
    samples:SetSize(300, 20)
    Button(ui, samples, "role", "Enemy type", 88, 0, function()
        P.Set(ID, "enemyPreviewRole", P.Get(ID, "enemyPreviewRole") % #P.Suite.NameplateStyle.Roles + 1)
        ui:Paint()
    end)
    Button(ui, samples, "friendlyMode", "Friendly: bars / names", 146, 94, function()
        P.Set(ID, "friendlyNamesOnly", P.Get(ID, "friendlyNamesOnly") == 2 and 3 or 2)
        ui:Paint()
    end)
    Button(ui, samples, "friendlyGroup", "Group / outsider", 114, 246, function()
        ui.friendlyOutsider = not ui.friendlyOutsider
        ui:Paint()
    end)
    Button(ui, samples, "friendlyFocus", "Friendly focus", 106, 366, function()
        ui.friendlyFocus = not ui.friendlyFocus
        ui:Paint()
    end)
    if H.EnsurePreviewBackgroundButton then
        local background = H.EnsurePreviewBackgroundButton(body, samples)
        if background then background:ClearAllPoints(); background:SetPoint("RIGHT", canvas, "TOPRIGHT", -8, -18) end
    end
    ui.tools = tools
end

local function BuildSelection(ui)
    local body, tools = ui.body, ui.tools
    if SB then
        local bar = SB.Create(body, {
            Tr = Tr, Theme = function() return T end, HandleList = function() return ui.handles end,
            HandleLabel = function(handle) return handle._label end,
            IsPlaced = function(handle) return handle:IsShown() end,
            ReadOffsets = function(_, handle) return Read(handle) end,
            WriteOffsets = function(_, handle, x, y) return Write(ui, handle, x, y) end,
            SelectHandle = function(_, handle) ui:Select(handle); return true end,
            ResetOffsets = function(_, handle)
                local rules = P.catalog[ID].rules
                return Write(ui, handle, rules[handle.keyX].default, rules[handle.keyY].default)
            end,
            NudgeDelta = function(_, dx, dy)
                local handle = body._selectedHandle
                if not handle then return false end
                local x, y = Read(handle)
                return Write(ui, handle, x + dx, y + dy)
            end,
            OpenSettings = function(_, handle) Focus(ui, handle) end,
        })
        bar:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -5)
        bar:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -5)
        if SB.CreatePicker then
            local picker = SB.CreatePicker(body, tools)
            picker:SetPoint("RIGHT", tools, "RIGHT", 0, 0)
            picker:SetWidth(152)
        end
    end
end

local function BuildInput(ui)
    local body, canvas, stage = ui.body, ui.canvas, ui.stage
    ui.bindings = { ownerName = "MSUF_SuiteNameplatesPreview_NudgeOwner", activeName = "MSUF_SuiteNameplatesPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteNameplatesPreview_Nudge", onClick = function(_, dx, dy) return Nudge(ui, dx, dy) end }
    body:EnableKeyboard(true)
    body:SetPropagateKeyboardInput(true)
    body:SetScript("OnKeyDown", Key)
    canvas:SetScript("OnMouseWheel", function(_, delta) ui.zoom = Clamp(ui.zoom + delta * 0.1, 0.5, 2); ui:Paint() end)
    canvas:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or ui.panning then return end
        local x, y = GetCursorPosition()
        ui.panning = { x = x, y = y }
        stage:StartMoving()
    end)
    canvas:SetScript("OnMouseUp", function()
        local pan = ui.panning
        if not pan then return end
        stage:StopMovingOrSizing()
        ui.panning = nil
        local x, y = GetCursorPosition()
        local scale = canvas:GetEffectiveScale()
        ui.panX, ui.panY = ui.panX + (x - pan.x) / scale, ui.panY + (y - pan.y) / scale
        ui:Paint()
    end)
    body:SetScript("OnHide", function() ui:CancelDrag(); ui:Select(nil) end)
    body:RegisterEvent("PLAYER_REGEN_DISABLED")
    body:SetScript("OnEvent", function() ui:CancelDrag(); ui:Select(nil) end)
end

local function BuildExpander(ui, section, toolbar, record)
    local body, canvas, tools, ctx = ui.body, ui.canvas, ui.tools, ui.ctx
    if W.AttachFixedPreviewExpander then
        function body:ApplyCompactPreviewPresentation(compact)
            canvas:SetHeight(compact and 108 or 226)
            tools:SetShown(not compact)
            if SB then SB.SetShown(body, not compact) end
            ui:Paint()
        end
        local expander = W.AttachFixedPreviewExpander(section, toolbar, body, { pageKey = ctx.key, wrapper = ctx.wrapper,
            compactHeight = 116, compactTop = -38, expandedHeight = 300, expandedTop = -38, expandedSectionHeight = 348 })
        if record then record.onActivate = function()
            if expander and M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview() then expander:Open("NAMEPLATES_PREVIEW") end
            ui:Paint()
        end end
    end
end

function Editor.Create(ctx, builder, sections)
    local section, toolbar, record = W.FixedPreviewSection(ctx, builder, { title = Tr("Nameplate preview"), height = 348, gap = 8 })
    if not section then return end
    local ui = setmetatable({ ctx = ctx, sections = sections, handles = {}, renderers = {}, zoom = 1, panX = 0, panY = 0,
        inDungeon = false, help = "Drag elements · Arrows: move · Shift: 5 · Ctrl: 10 · Tab: select · Wheel: zoom" }, { __index = Editor })
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -38)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -38)
    body:SetHeight(300)
    ui.body, body.previewUI, body._handleList = body, ui, ui.handles
    local canvas = CreateFrame("Frame", nil, body, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    canvas:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    canvas:SetHeight(226)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    ui.canvas = canvas
    if H.ApplyPreviewChrome then H.ApplyPreviewChrome(canvas, "canvas", T) end
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetSize(600, 180)
    stage:SetMovable(true)
    ui.stage = stage
    ui.hint = T.Font(toolbar, "GameFontDisableSmall", Tr(ui.help), T.colors.muted)
    ui.hint:SetPoint("LEFT", toolbar, "LEFT", 132, 0)
    ui.hint:SetPoint("RIGHT", toolbar, "RIGHT", -26, 0)
    ui.hint:SetJustifyH("LEFT")
    BuildTools(ui)
    BuildSelection(ui)
    BuildInput(ui)
    BuildExpander(ui, section, toolbar, record)
    M.TrackRefresh(ctx, function() ui:Paint() end)
    return ui
end
