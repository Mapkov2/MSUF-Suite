local _, P = ...
local M, W, T, Tr = P.M, P.W, P.T, P.Tr
local ID = "nameplates"
local SB, H = M.PreviewSelectionBar, M.PreviewHelpers or {}
local Layers = P.NameplatesEditorLayers
local AURA_KIND, AuraGroup = Layers.AURA_KIND, Layers.AuraGroup
local Register, OpenSetting = Layers.Register, Layers.OpenSetting
local Editor = {}
P.NameplatesEditor = Editor
Editor.Layout = P.NameplatesPreviewLayout.Apply
-- The layer rules of NameplatesEditorLayers.lua, as methods of the preview.
Editor.LayerOn, Editor.LayerAvailable, Editor.LayerActive = Layers.On, Layers.Available, Layers.Active
local DELTA = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local RAID_MARK_NAMES = { [0] = "Off", [1] = "Star", [2] = "Circle", [3] = "Diamond",
    [4] = "Triangle", [5] = "Moon", [6] = "Blue square", [7] = "Cross", [8] = "Skull" }
local ENEMY_ELEMENT_SETTINGS = { Name = true, Level = true, HealthText = true, Classification = true,
    RaidIcon = true, Cast = true, CastText = true, CastTime = true,
    CastIcon = true, CastShield = true, CastTarget = true }
local ELEMENT_SETTING = {
    Name = "enemyTextMode", Level = "enemyLevelEnabled", HealthText = "enemyTextMode", Cast = "enemyCastEnabled",
    CastText = "enemyCastSpellName", CastTime = "enemyCastTimeEnabled", RaidIcon = "enemyRaidIcon",
    Classification = "enemyRarityIcon", CastIcon = "enemyCastSpellIcon",
    CastTarget = "enemyCastSpellTarget",
}
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Round(v) return math.floor(v + 0.5) end

local function Focus(ui, handle)
    local section = handle and ui.sections and ui.sections[handle.section]
    if handle and handle._npSettingsTab then
        section = P.SelectNameplatesEnemyTab(handle._npSettingsTab) or section
    end
    if section and W.FocusCollapsibleSection then W.FocusCollapsibleSection(section, { persist = true, flash = true }) end
    if handle then
        local key = handle._npSettingKey
        local kind = handle._key and handle._key:match("%.([%a]+)$")
        if kind and AURA_KIND[kind] then
            local group = AuraGroup(ui)
            key = group and group .. AURA_KIND[kind] or "friendlyNpcDebuffs"
        elseif handle._key and handle._key:find("%.SoftTarget$", 1, false) then
            key = ui.sampleKind == "enemy" and (ui.softInteract and "softTargetInteract" or "softTargetEnemy")
                or "softTargetFriend"
        end
        OpenSetting(key, handle._label)
    end
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
    if self.RefreshSizeSelection then self:RefreshSizeSelection() end
end

local function Nudge(ui, dx, dy)
    local handle = ui.body._selectedHandle
    if P.Combat() or not ui.body:IsShown() or not handle or not handle:IsShown() then return false end
    if H.IsTextInputFocused and H.IsTextInputFocused() then return false end
    local focus = GetCurrentKeyBoardFocus()
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
    self._npDragged = false
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
    local moved = math.abs(dx) + math.abs(dy) >= 3
    self._npDragged = moved
    if not P.Combat() and moved then
        Write(ui, self, drag.ox + dx / drag.scale, drag.oy + dy / drag.scale)
        if H.NotePreviewElementMoved then H.NotePreviewElementMoved() end
    else
        ui:Paint()
    end
end

function Editor:Bind(handle, id, label, keyX, keyY, section)
    handle.previewUI, handle._key, handle._label = self, id, label
    handle._color, handle.keyX, handle.keyY, handle.section = { 0.3, 0.74, 1 }, keyX, keyY, section
    local enemyElement = id:match("^enemy%.(.+)$")
    if enemyElement and ENEMY_ELEMENT_SETTINGS[enemyElement] then
        handle._npSettingsTab = "elements"
        handle._npSettingKey = ELEMENT_SETTING[enemyElement]
    elseif id == "enemy.Health" then
        handle._npSettingKey = "enemyHealthWidthDelta"
    elseif id == "friendly.Health" then
        handle._npSettingKey = "friendlyHealthWidthDelta"
    elseif id == "friendly.Classification" or id == "friendly.Cast" or id == "friendly.CastText"
        or id == "friendly.CastIcon" or id == "friendly.CastTarget" then
        local element = id:match("^friendly%.(.+)$")
        handle._npSettingsTab = "elements"
        handle._npSettingKey = ELEMENT_SETTING[element]
    elseif id == "friendly.Name" or id == "friendly.HealthText" or id == "friendly.Level" then
        handle._npSettingKey = id == "friendly.Level" and "friendlyLevelEnabled" or "friendlyNamesOnly"
    elseif id == "personal.Power" then
        handle._npSettingKey = "personalPowerSkin"
    elseif id == "enemy.target" or id == "friendly.target" then
        handle._npSettingKey = id == "enemy.target" and "enemyTargetMarker" or "enemyTargetHideFriendly"
    elseif id == "enemy.elite" or id == "enemy.quest"
        or id == "friendly.elite" or id == "friendly.quest" then
        handle._npSettingKey = id:match("^enemy") and (id:find("elite") and "enemyEliteMarker" or "enemyQuestMarker")
            or (id:find("elite") and "friendlyEliteMarker" or "friendlyQuestMarker")
    elseif id:match("%.SoftTarget$") then
        handle._npSettingKey = id:match("^enemy") and "softTargetEnemy" or "softTargetFriend"
    elseif AURA_KIND[id:match("%.([%a]+)$")] then
        handle._npSettingKey = "enemyNpcAuraMode"
    end
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
        if button == "RightButton" or button == "LeftButton"
            and (handle._npSettingsTab or handle._npSettingKey) and not handle._npDragged then
            Focus(self, handle)
        end
    end)
    handle:SetScript("OnEnter", function()
        handle.outline(1, "4ebaff")
        self.hint:SetText(Tr(label) .. " · " .. Tr(handle._npSettingsTab
            and "Drag to move; click for Blizzard settings" or "Drag to move; right-click for settings"))
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
    if self.contextButton then
        self.contextButton:SetText(Tr(self.inDungeon and "Dungeon / raid" or "Outdoor"))
    end
    if self.zoomLabel then self.zoomLabel:SetText(string.format("%d%%", Round(self.zoom * 100))) end
    self:LayoutLayerRail()
    for _, button in ipairs(self.layerButtons or {}) do
        if button.Refresh then button:Refresh()
        else button:SetAlpha(self:LayerActive(button.layerKey) and 1 or 0.42) end
    end
    if self.sampleButton then
        self.sampleButton:SetText(Tr(self.personal and "Personal plate" or self.sampleKind == "enemy"
            and "Enemy plate" or "Friendly plate"))
    end
    if self.roleButton then self.roleButton:SetShown(self.sampleKind == "enemy" and not self.enemyPlayer) end
    if self.enemyTypeButton then self.enemyTypeButton:SetShown(self.sampleKind == "enemy") end
    if self.softTypeButton then self.softTypeButton:SetShown(self.sampleKind == "enemy") end
    if self.questButton then self.questButton:SetShown(self.sampleKind == "enemy") end
    if self.friendlyTypeButton then self.friendlyTypeButton:SetShown(self.sampleKind == "friendly" and not self.personal) end
    for _, choice in ipairs(self.raidChoices or {}) do
        choice.outline(self.raidMarked and self.raidIndex == choice.index and 1 or 0, "4ebaff")
    end
    for _, button in ipairs(self.friendlyButtons or {}) do
        button:SetShown(self.sampleKind == "friendly" and not self.personal)
    end
    local selected = self.body._selectedHandle
    if selected and not selected:IsShown() then self:Select(nil) end
    self:RefreshSelection()
end

local function Button(ui, parent, key, label, width, x, action)
    local button = T.Button(parent, Tr(label), width, 20)
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
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
    ui.contextButton = Button(ui, tools, "context", "Outdoor", 128, 188,
        function() ui.inDungeon = not ui.inDungeon; ui:Paint() end)
    local samples = CreateFrame("Frame", nil, body)
    ui.samples = samples
    samples:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8)
    samples:SetSize(540, 20)
    ui.sampleButton = Button(ui, samples, "plateKind", "Enemy / Friendly / Personal", 124, 0, function()
        if ui.sampleKind == "enemy" then
            ui.sampleKind, ui.personal = "friendly", false
        elseif not ui.personal then
            ui.sampleKind, ui.personal = "friendly", true
        else
            ui.sampleKind, ui.personal = "enemy", false
        end
        ui:Select(nil)
        ui:Paint()
    end)
    ui.roleButton = Button(ui, samples, "role", "Enemy type", 88, 130, function()
        ui.previewRole = nil
        P.Set(ID, "enemyPreviewRole", P.Get(ID, "enemyPreviewRole") % #P.Suite.NameplateStyle.Roles + 1)
        ui:Paint()
    end)
    ui.enemyTypeButton = Button(ui, samples, "enemyType", "NPC / player", 112, 224, function()
        ui.enemyPlayer = not ui.enemyPlayer
        ui:Select(nil)
        ui:Paint()
    end)
    ui.softTypeButton = Button(ui, samples, "softType", "Soft: enemy / interact", 126, 342, function()
        ui.softInteract = not ui.softInteract
        ui:Select(nil)
        ui:Paint()
    end)
    ui.questButton = Button(ui, samples, "questSample", "Quest", 58, 472, function()
        if P.Get(ID, "look") == 2 then OpenSetting("look", "Look"); return end
        ui.enemyPlayer = false
        ui.previewRole, ui.previewRoleSource = 5, P.Get(ID, "enemyPreviewRole")
        ui.raidMarked, ui.layers.questMarker = false, true
        if not P.Get(ID, "enemyQuestMarker") then P.Set(ID, "enemyQuestMarker", true) end
        ui:Paint()
        if ui.questMarkerHandle and ui.questMarkerHandle:IsShown() then ui:Select(ui.questMarkerHandle) end
    end)
    ui.friendlyButtons = {}
    ui.friendlyButtons[1] = Button(ui, samples, "friendlyMode", "Friendly player display", 146, 130, function()
        OpenSetting("friendlyNamesOnly", "Friendly player display")
    end)
    ui.friendlyButtons[2] = Button(ui, samples, "friendlyGroup", "Group / outsider", 114, 282, function()
        ui.friendlyOutsider = not ui.friendlyOutsider
        ui:Paint()
    end)
    ui.friendlyTypeButton = Button(ui, samples, "friendlyType", "Player / elite NPC", 112, 402, function()
        ui.friendlyElite = not ui.friendlyElite
        ui:Select(nil)
        ui:Paint()
    end)
    if H.EnsurePreviewBackgroundButton then
        local background = H.EnsurePreviewBackgroundButton(body, samples)
        if background then background:ClearAllPoints(); background:SetPoint("RIGHT", canvas, "TOPRIGHT", -8, -18) end
    end
    ui.tools = tools
end

local function BuildRaidPalette(ui)
    local strip = CreateFrame("Frame", nil, ui.canvas)
    ui.raidPalette = strip
    strip:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -8, -39)
    strip:SetSize(165, 22)
    local title = T.Font(strip, "GameFontDisableSmall", Tr("RAID MARKS"), T.colors.muted)
    title:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 1)
    ui.raidChoices = {}
    for index = 1, 8 do
        local button = CreateFrame("Button", nil, strip)
        button:SetSize(18, 18)
        button:SetPoint("LEFT", strip, "LEFT", (index - 1) * 21, 0)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.index = index
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index)
        local border = P.Suite.NameplateStyle.CreateBorder(button)
        button.outline = function(size, color)
            P.Suite.NameplateStyle.PaintBorder(border, button, size, color)
        end
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" or not ui:LayerAvailable("raidIcon") then
                Layers.Focus(ui, "elements", "raidIcon")
                return
            end
            ui.raidMarked = not (ui.raidMarked and ui.raidIndex == index)
            ui.raidIndex = ui.raidMarked and index or 0
            ui.layers.raidIcon = true
            ui:Paint()
        end)
        button:SetScript("OnEnter", function()
            ui.hint:SetText(Tr("Raid mark: %s"):format(Tr(RAID_MARK_NAMES[index])) .. " · "
                .. Tr("Click to preview; right-click for settings"))
        end)
        button:SetScript("OnLeave", function() ui.hint:SetText(Tr(ui.help)) end)
        Register(button, "raidMark." .. index, Tr("Raid mark: %s"):format(Tr(RAID_MARK_NAMES[index])))
        ui.raidChoices[index] = button
    end
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
                local values = {
                    [handle.keyX] = rules[handle.keyX].default,
                    [handle.keyY] = rules[handle.keyY].default,
                }
                P.NameplatesSize.ResetValues(handle, values, rules)
                local ok = P.SetMany(ID, values)
                ui:Paint()
                return ok ~= false
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
        P.NameplatesSize.Build(ui, bar, body)
        if SB.CreatePicker then
            local picker = SB.CreatePicker(body, tools)
            picker:SetPoint("RIGHT", tools, "RIGHT", 0, 0)
            picker:SetWidth(152)
        end
        ui.selection = bar
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

function Editor.Create(ctx, builder, sections)
    local section, toolbar, record = W.FixedPreviewSection(ctx, builder, { title = Tr("Nameplate preview"), height = 162, gap = 8 })
    if not section then return end
    local inInstance, instanceType = _G.IsInInstance()
    local inDungeon = P.Suite.Public(instanceType) and P.Suite.Public(inInstance)
        and inInstance == true and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
    local ui = setmetatable({ ctx = ctx, sections = sections, handles = {}, renderers = {}, layers = {},
        sampleKind = "enemy", zoom = 1, panX = 0, panY = 0, compact = true,
        softTargetSample = true, aggroSample = true,
        layoutWidth = math.max(640, (section._msuf2Width or builder.width or 720) - 28),
        inDungeon = inDungeon, help = "Select an element for X/Y and available size · Drag or arrow keys: move · Tab: select · Wheel: zoom" }, { __index = Editor })
    ui.previewRole, ui.previewRoleSource = nil, P.Get(ID, "enemyPreviewRole")
    P.ShowNameplatesElementsSample = function()
        ui.sampleKind = "enemy"
        ui.previewRole = nil
        ui.previewRoleSource = P.Get(ID, "enemyPreviewRole")
        ui:Paint()
    end
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -38)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -38)
    body:SetHeight(116)
    ui.body, body.previewUI, body._handleList = body, ui, ui.handles
    local canvas = CreateFrame("Frame", nil, body, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    canvas:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    canvas:SetHeight(108)
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
    ui.hint:SetPoint("LEFT", section.title or toolbar, section.title and "RIGHT" or "LEFT", section.title and 12 or 160, 0)
    ui.hint:SetPoint("RIGHT", toolbar, "RIGHT", -154, 0)
    ui.hint:SetJustifyH("LEFT")
    ui.hint:SetWordWrap(false)
    ui.hint:SetMaxLines(1)
    BuildTools(ui)
    BuildRaidPalette(ui)
    BuildSelection(ui)
    Layers.Build(ui)
    BuildInput(ui)
    P.NameplatesPreviewLayout.Attach(ui, section, toolbar, record)
    ui:Layout()
    M.TrackRefresh(ctx, function() ui:Paint() end)
    return ui
end
