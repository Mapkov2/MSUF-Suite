local _, P = ...
local M, W, T, Tr = P.M, P.W, P.T, P.Tr
local ID = "nameplates"
local SB, H = M.PreviewSelectionBar, M.PreviewHelpers or {}
local Layers = P.NameplatesEditorLayers
local AURA_KIND = Layers.AURA_KIND
local AURA_ELEMENT = Layers.AuraElement
local Register, OpenSetting = Layers.Register, Layers.OpenSetting
local Kit = P.Suite.PreviewKit
local Snap = P.PreviewSnap
local Tools = P.NameplatesEditorTools
local Elements = P.NameplatesElements
local Ghosts = P.NameplatesEditorGhosts
local Public = P.Suite.Public
local Layout = P.NameplatesPreviewLayout
local Editor = {}
P.NameplatesEditor = Editor
Editor.Layout = Layout.Apply
-- The layer rules of NameplatesEditorLayers.lua, as methods of the preview.
Editor.LayerOn, Editor.LayerAvailable, Editor.LayerActive = Layers.On, Layers.Available, Layers.Active
local ENEMY_ELEMENT_SETTINGS = { Name = true, Level = true, HealthText = true, Classification = true,
    RaidIcon = true, Cast = true, CastText = true, CastTime = true,
    CastIcon = true, CastShield = true, CastTarget = true }
local ELEMENT_SETTING = {
    Name = "enemyNameSize", Level = "enemyLevelEnabled", HealthText = "enemyHealthTextSize", Cast = "enemyCastHeight",
    CastText = "enemyCastSize", CastTime = "enemyCastTimeSize", RaidIcon = "enemyRaidIcon",
    Classification = "enemyRarityIcon", CastIcon = "enemyCastSpellIcon",
    CastTarget = "enemyCastSize",
}
local FRIENDLY_ELEMENTS = { Name = "friendlyNameSize", HealthText = "friendlyHealthTextSize", Level = "friendlyLevelEnabled",
    RaidIcon = "friendlyRaidIcon", Cast = "friendlyCastHeight", CastText = "friendlyCastSize", CastTime = "friendlyCastTimeSize",
    CastIcon = "friendlyCastIconSize", CastTarget = "friendlyCastSize" }
local function NoPreview() end
P.ShowNameplatesSample, P.EditNameplatesPreview = NoPreview, NoPreview
P.ShowNameplatesAuraSample = NoPreview
P.PreviewNameplateStatus, P.PreviewNameplateOpacity, P.PreviewNameplateHighlight = NoPreview, NoPreview, NoPreview
P.SelectNameplateStatusPreview = NoPreview

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Round(v) return math.floor(v + 0.5) end

local function Focus(ui, handle)
    if not handle or P.Combat() then return end
    if Layers.NPCWorldNames(ui) then
        OpenSetting("friendlyNPCs")
        return
    end
    local key = handle._npSettingKey
    local kind = handle._key and AURA_ELEMENT[handle._key:match("%.([%a]+)$")]
    if kind and AURA_KIND[kind] then
        key = Layers.AuraSetting(ui, kind)
    elseif handle._key and handle._key:find("%.SoftTarget$", 1, false) then
        key = ui.sampleKind == "enemy" and (ui.softInteract and "softTargetInteract" or "softTargetEnemy")
            or "softTargetFriend"
    end
    if handle._key and handle._key:match("%.Health$") then
        key = P.NameplatesSize.Keys(handle) or key
    end
    if handle._key and handle._key:match("%.CastShield$") then return Layers.Focus(ui, "castbar", "castShield") end
    if P.OpenNameplateStatusItem(ui.sampleKind, handle.keyX, ui.scope) then return end
    if OpenSetting(key) then return end
    local section = ui.sections and ui.sections[handle.section]
    if handle._npSettingsTab then
        section = P.SelectNameplatesEnemyTab(handle._npSettingsTab) or section
    end
    if section and W.FocusCollapsibleSection then W.FocusCollapsibleSection(section, { persist = true, flash = true }) end
end
local function CenteredNameKey(handle)
    local key = handle.previewCenterNameKey
    return key and P.Get(ID, key) and key or nil
end

local function Read(handle)
    local x = CenteredNameKey(handle) and 0 or P.Get(ID, handle.keyX)
    return x, P.Get(ID, handle.keyY)
end

local function Write(ui, handle, x, y, dragged)
    if P.Combat() or Layers.NPCWorldNames(ui) or ui.groupPreviewEnabled then return false end
    local rules = P.catalog[ID].rules
    local xr, yr = rules[handle.keyX], rules[handle.keyY]
    if not xr or not yr then return false end
    local center = CenteredNameKey(handle)
    local oldX, oldY = P.Get(ID, handle.keyX), P.Get(ID, handle.keyY)
    local leaveCenter = center and Round(x) ~= 0
    if leaveCenter then
        x, y = Layout.ManualNameOffsets(handle, x, y)
        if not x then return false end
    elseif center then
        x = oldX
    end
    x, y = Clamp(Round(x), xr.min, xr.max), Clamp(Round(y), yr.min, yr.max)
    if not leaveCenter and oldX == x and oldY == y then
        -- The followed handle can cross the clamp even when the final
        -- coordinates equal the profile. Place it back after this drag.
        if dragged then ui.host:Request("offset") end
        return true
    end
    local values = { [handle.keyX] = x, [handle.keyY] = y }
    if leaveCenter then values[center] = false end
    local ok = P.SetMany(ID, values) ~= false
    if ok then Layout.KeepViewport(ui) end
    -- P.SetMany already requests Menu2's refresh. The editor only schedules
    -- a separate paint when the host doesn't provide that refresh path.
    if not M.RequestRefresh then ui.host:Request("offset") end
    return ok
end
local function CanEdit(handle)
    local ui = handle.previewUI
    if Layers.NPCWorldNames(ui) or ui.groupPreviewEnabled then return false end
    local visible = handle:IsVisible()
    return P.Suite.Public(visible) and visible
end

local function RememberHiddenSelection(ui, handle)
    local def = Elements.ForHandle(handle)
    ui.inspectedKey, ui.suspendedSelection = def and def.key, def and handle
end

function Editor:Select(handle)
    self.inspectedKey, self.suspendedSelection = nil, nil
    self.kit:Select(handle and CanEdit(handle) and handle or nil)
end

function Editor:RefreshSelection(inPaint)
    local selected = self.body._selectedHandle
    local def = Elements.Current(self)
    for _, handle in ipairs(self.handles) do
        handle.outline(0, "4ebaff")
        P.PreviewInteraction.Outline(handle, handle == selected)
    end
    if SB then SB.Refresh(self.body) end
    if self.selectionDef ~= def then
        self.selectionDef = def
        if not inPaint and not self.compact and not self.groupPreviewEnabled then self:LayoutElements() end
    end
    if self.RefreshSizeSelection then self:RefreshSizeSelection() end
    P.NameplatesInspector.Refresh(self)
    Tools.RefreshSelection(self)
    if not inPaint and self.selectedTools and not self.compact and not self.groupPreviewEnabled then
        Layout.Samples(self)
        if self.fitMode then Layout.UpdateViewport(self) end
    end
    if self.workspace then P.NameplatesWorkspace.Highlight(self.workspace, def and def.group) end
end

function Editor:CanMoveHandle(handle) return CanEdit(handle) and not Layers.NPCWorldNames(self) end

function Editor:CancelDrag()
    self.kit:Cancel()
    Layout.StopPan(self)
    self:Paint()
end

-- Which Blizzard setting a preview element opens when it is clicked.
local function BindSetting(handle, id)
    local enemyElement = id:match("^enemy%.(.+)$")
    local friendlyElement = id:match("^friendly%.(%a+)$")
    if P.Suite.NameplateStyle.StatusByKey and P.Suite.NameplateStyle.StatusByKey[enemyElement or friendlyElement] then
        local side, element = id:match("^(%a+)%.(%a+)$")
        handle._npSettingKey = side .. element
    elseif enemyElement and ENEMY_ELEMENT_SETTINGS[enemyElement] then
        handle._npSettingsTab = "elements"
        handle._npSettingKey = ELEMENT_SETTING[enemyElement]
    elseif id == "enemy.Health" then
        handle._npSettingKey = "enemyHealthWidthDelta"
    elseif id == "friendly.Health" then
        handle._npSettingKey = "friendlyHealthWidthDelta"
    elseif friendlyElement and FRIENDLY_ELEMENTS[friendlyElement] then
        handle._npSettingKey = FRIENDLY_ELEMENTS[friendlyElement]
        handle.section = friendlyElement == "RaidIcon" and "friendlyMarkers"
            or friendlyElement:match("^Cast") and "friendlyCast" or "friendlyText"
    elseif id == "friendly.Classification" then
        handle._npSettingKey = "enemyRarityIcon"
        handle.section = "friendlyMarkers"
    elseif id == "enemy.Power" then
        handle._npSettingKey = "enemyPowerEnabled"
    elseif id == "enemy.PowerText" then
        handle._npSettingKey = "enemyPowerTextSize"
        handle.section = "enemyText"

    elseif id:match("%.CastShield$") then
        handle._npSettingsTab = "cast"
    end
end

local function FollowHandle(handle, dx, dy)
    local points = handle.previewDragPoints
    if not points or (handle.previewDragX == dx and handle.previewDragY == dy) then return end
    handle.previewDragX, handle.previewDragY = dx, dy
    handle:ClearAllPoints()
    for _, point in ipairs(points) do
        handle:SetPoint(point[1], point[2], point[3], (point[4] or 0) + dx, (point[5] or 0) + dy)
    end
end

local function TrackHandleDrag(ui, handle, phase)
    if phase == "start" then
        local points = {}
        for i = 1, handle:GetNumPoints() do points[i] = { handle:GetPoint(i) } end
        handle.previewDragPoints = points
        handle.previewDragX, handle.previewDragY = 0, 0
        ui.dragging = handle
        ui.snapper:Begin(handle)
    else
        if phase == "cancel" or phase == "done" then
            handle.previewDragPoints, handle.previewDragX, handle.previewDragY = nil, nil, nil
        end
        ui.dragging = nil
        ui.snapper:End()
    end
end

-- A drag snaps to the other elements of its own sample plate and to the
-- plate's center, as Edit Mode snaps a frame to other frames and the screen.
local function SampleCell(ui, region)
    local frame = region
    while frame and frame:GetParent() ~= ui.stage do frame = frame:GetParent() end
    -- A region placed on the stage itself has no plate to snap within.
    if frame ~= region then return frame end
end

local function NewSnapper(ui)
    return Snap.New({ layer = ui.canvas,
        targets = function(region) return Snap.Targets(region, ui.handles, SampleCell(ui, region)) end,
        lines = function(region, add)
            local cell = SampleCell(ui, region)
            if not cell then return end
            local x, y = cell:GetCenter()
            local scale = cell:GetEffectiveScale()
            if Public(x) and Public(y) and Public(scale) and x and y then add(x * scale, y * scale) end
        end })
end

function Editor:Bind(handle, id, label, keyX, keyY, section)
    handle.previewUI, handle._key, handle._label = self, id, label
    handle._color, handle.keyX, handle.keyY, handle.section = { 0.3, 0.74, 1 }, keyX, keyY, section
    BindSetting(handle, id)
    local border = P.Suite.NameplateStyle.CreateBorder(handle)
    handle.outline = function(size, color) P.Suite.NameplateStyle.PaintBorder(border, handle, size, color) end
    self.kit:Add(id, handle, function() return Read(handle) end, function(x, y, dragged) return Write(self, handle, x, y, dragged) end,
        { can = CanEdit, follow = FollowHandle })
    Layout.BindHandleInput(self, handle)
    Register(handle, id, label)
end

local function InDungeon()
    local inInstance, instanceType = _G.IsInInstance()
    return P.Suite.Public(instanceType) and P.Suite.Public(inInstance)
        and inInstance == true and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
end

function Editor:Paint()
    if self.dragging or self.panning then return end
    self.inDungeon = InDungeon()
    local config = P.S.Config(ID)
    local style = P.Suite.NameplateStyle
    self.barSettings = style.BarSettings(config, not config.barsOverride and style.SharedBars())
    if not P.NameplatesMultiPreview.Paint(self) then
        for _, render in ipairs(self.renderers) do render() end
    end
    for _, button in ipairs(self.layerButtons or {}) do
        P.PreviewInteraction.RefreshLayerButton(button, self:LayerActive(button.layerKey))
    end
    if self.snapButton then P.PreviewInteraction.RefreshLayerButton(self.snapButton, Snap.Enabled()) end
    Tools.RefreshSamples(self)
    for _, choice in ipairs(self.raidChoices or {}) do
        choice.outline(self.raidMarked and self.raidIndex == choice.index and 1 or 0, "4ebaff")
    end
    local selected = self.body._selectedHandle
    if selected and not CanEdit(selected) then
        RememberHiddenSelection(self, selected)
        self.kit:Select(nil)
    elseif not selected and self.suspendedSelection and not P.Combat() then
        local handle = self.suspendedSelection
        local def = Elements.ForHandle(handle)
        if def and def.key == self.inspectedKey and CanEdit(handle) then self:Select(handle) end
    end
    self:RefreshSelection(true)
    if not self.compact and not self.groupPreviewEnabled then
        self:LayoutElements()
        Layout.Samples(self)
    end
    Ghosts.Refresh(self)
    Layout.UpdateViewport(self)
end

-- Position and size back to their defaults (the selection bar's Reset and
-- the inspector share it).
function Editor:ResetHandle(handle)
    if Layers.NPCWorldNames(self) or P.Combat() then return false end
    local rules = P.catalog[ID].rules
    local values = {
        [handle.keyX] = rules[handle.keyX].default,
        [handle.keyY] = rules[handle.keyY].default,
    }
    P.NameplatesSize.ResetValues(handle, values, rules)
    local ok = P.SetMany(ID, values)
    self:Paint()
    return ok ~= false
end

function Editor:OpenHandleSettings(handle) Focus(self, handle) end

local function BuildElementPicker(ui, tools)
    local picker = T.Button(tools, "Elements", 110, 20)
    Layout.StyleButton(picker)
    picker:SetScript("OnClick", function()
        if P.Combat() or not ui:CanPickElement() then return end
        P.AnchoredContextMenu(picker, function(_, menu) ui:BuildElementMenu(menu) end)
    end)
    Register(picker, "selectElement", "Elements")
    ui.elementPicker = picker
end

local function BuildSelection(ui)
    local body, tools = ui.body, ui.tools
    if SB then
        local bar = SB.Create(body, {
            Tr = Tr, Theme = function() return T end, HandleList = function() return ui.handles end,
            HandleLabel = function(handle) return handle._label end,
            IsPlaced = CanEdit,
            ReadOffsets = function(_, handle) return Read(handle) end,
            WriteOffsets = function(_, handle, x, y) return Write(ui, handle, x, y) end,
            SelectHandle = function(_, handle)
                ui:Select(handle)
                return true
            end,
            ResetOffsets = function(_, handle) return ui:ResetHandle(handle) end,
            NudgeDelta = function(_, dx, dy) return ui.kit:Nudge(dx, dy) end,
        })
        bar:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -5)
        bar:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -5)
        P.NameplatesSize.Build(ui, bar, body)
        ui.selection = bar
    end
    BuildElementPicker(ui, tools)
end

local function BuildInput(ui)
    local body = ui.body
    ui.bindings.onClick = function(_, dx, dy) return ui.kit:Arrow(dx, dy) end
    Layout.BindViewportInput(ui)
    local function Release()
        ui:CancelDrag()
        ui:Select(nil)
    end
    -- Combat start ends a drag and drops the selection. Only a shown preview
    -- holds either, so the event is registered while it shows (TrackCombat).
    body:SetScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        Release()
        ui.host:Deactivate()
    end)
    body:SetScript("OnEvent", Release)
end

-- After P.NameplatesPreviewLayout.Attach, which owns the body's OnShow script.
local function TrackCombat(ui)
    local body = ui.body
    body:HookScript("OnShow", function(self)
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        ui.host:Activate()
    end)
    if body:IsVisible() then
        body:RegisterEvent("PLAYER_REGEN_DISABLED")
        ui.host:Activate()
    end
end

-- The page's area header shows the matching sample (NameplatesWorkspace.lua).
local SAMPLE_LABELS = { enemy = "Enemy", neutral = "Neutral", friendly = "Friendly", friendlyNpc = "Friendly NPC" }

function Editor:ShowSample(kind, scope)
    scope = scope or kind
    if self.sampleKind == kind and self.scope == scope then return end
    self.sampleKind, self.scope = kind, scope
    self.friendlyElite = scope == "friendlyNpc"
    self.statusSample, self.allStatusSamples, self.opacitySample = nil, nil, nil
    self.statusOffsetSample = nil
    if self.highlightSample == "aggro" and scope ~= "enemy" then self.highlightSample = nil end
    self.auraSample, self.sharedAuraText, self.textSample = nil, nil, nil
    self.castSample, self.interruptedSample, self.sampleScenario, self.questSample = nil, nil, nil, nil
    self.editFullPlate = nil
    self.enemyPlayer = false
    self.previewRole = scope == "neutral" and 8 or nil
    self.previewRoleSource = P.Get(ID, "enemyPreviewRole")
    if self.title then
        P.SetTranslatedText(self.title, Tr("Preview – %s"):format(Tr(SAMPLE_LABELS[scope] or SAMPLE_LABELS[kind])))
    end
    self:Select(nil)
    self:Paint()
end

local ELEMENTS = { anchor = "Health", text = "Name", cast = "Cast", status = "RaidIcon", power = "Power" }

local function SelectElement(editor, element)
    local prefix = editor.sampleKind
    local scope = editor.scope or prefix
    local entry = editor.kit.entries[scope .. "." .. element] or editor.kit.entries[prefix .. "." .. element]
    if entry and CanEdit(entry.region) then editor:Select(entry.region) end
end

function Editor:ShowAuraSample(key)
    if self.sampleKind ~= "enemy" or self.scope ~= "enemy" then return end
    local player = key:match("^enemyPlayer") ~= nil
    if (not player and not key:match("^enemyNpc")) or player == (self.enemyPlayer == true) then return end
    self.enemyPlayer = player
    self:Select(nil)
    self:Paint()
end

local TEXT_LAYERS = { Name = "name", HealthText = "healthText", PowerText = "enemyPower" }
local CAST_LAYERS = { CastText = "castText", CastTime = "castTime", CastIcon = "castIcon",
    CastShield = "castShield", CastTarget = "castTarget" }

function Editor:Edit(context, element, interrupted, sharedAuraText)
    if P.Combat() then return end
    self.interruptedSample = interrupted == true
    self.castSample = context == "cast" and (element or "Cast") or nil
    self.auraSample = context == "auras" and element or nil
    self.sharedAuraText = sharedAuraText
    if self.groupPreviewEnabled then P.NameplatesMultiPreview.Set(self, false) end
    self.layerContext = context
    local layer = context == "text" and TEXT_LAYERS[element]
    self.textSample = layer and element or nil
    self.editFullPlate = element == "Health" or element == "HealthText" or self.castSample == "CastShield" or self.auraSample ~= nil
        or context == "status" and self.statusOffsetSample == "Level"
    if context == "anchor" then self.layers.health = true end
    if layer then self.layers[layer], self.layers.health = true, true end
    if context == "power" then self.layers.enemyPower = true end
    if self.castSample then
        self.layers.cast = true
        local castLayer = CAST_LAYERS[self.castSample]
        if castLayer then self.layers[castLayer] = true end
    end
    if self.auraSample then
        self.layers[AURA_ELEMENT[element] or "auras"] = true
        if element:match("^Tracked") then self.targetSample = true end
    end
    if context ~= "highlight" then self.highlightSample = nil end
    if context ~= "status" then self.statusSample, self.allStatusSamples, self.statusOffsetSample = nil, nil, nil end
    if context ~= "opacity" then self.opacitySample = nil end
    local expander = self.expander
    if expander and not expander.expanded then expander:Open("NAMEPLATES_PREVIEW") end
    self:Paint()
    if context == "status" and self.allStatusSamples then return end
    if context == "status" or context == "cast" then self:Select(nil) end
    SelectElement(self, element or ELEMENTS[context] or "Auras")
end

function Editor:SampleHighlight(sample, clear, fromLayer)
    if P.Combat() then return end
    if clear then
        self.layers[sample .. "Border"] = false
        self.highlightSample = nil
        self:Paint()
        return
    end
    self.highlightSample = sample
    self.layers[sample .. "Border"] = true
    self.layers.highlightBorders, self.layers.health = true, true
    if sample == "aggro" then self.statusSample, self.statusOffsetSample = nil, nil end
    if fromLayer then
        if self.groupPreviewEnabled then P.NameplatesMultiPreview.Set(self, false) end
        self:Paint()
    else
        self:Edit("highlight")
        self:Select(nil)
    end
end

local STATUS_PREVIEW_LAYERS = {
    Level = "level", RaidIcon = "raidIcon", Classification = "classification", elite = "eliteMarker", quest = "questMarker",
    focusMarker = "focusMarker", SoftTarget = "softTarget", target = "target", Threshold = "threshold",
}

local function ShowStatusLayers(editor, element, all)
    editor.layers.status = true
    if all then
        for _, layer in pairs(STATUS_PREVIEW_LAYERS) do editor.layers[layer] = true end
    elseif STATUS_PREVIEW_LAYERS[element] then
        editor.layers[STATUS_PREVIEW_LAYERS[element]] = true
    end
    if all or element == "Aggro" then
        editor.layers.threatFlash, editor.layers.threatHighlight = true, true
    end
end

function Editor:FocusStatusOffset(key, element, sample)
    ShowStatusLayers(self, sample)
    self.statusSample, self.allStatusSamples, self.statusOffsetSample = sample, false, element
    self:Edit("status", element)
    local handle = self.body._selectedHandle
    if handle and self.selection then
        if key == handle.keyX then return self.selection.axisX end
        if key == handle.keyY then return self.selection.axisY end
    end
    return self.selection
end

local CAST_PICKER = {
    { "Cast", "Castbar" }, { "CastIcon", "Blizzard spell icon" }, { "CastText", "Spell name" },
    { "CastTime", "Cast time" }, { "CastTarget", "Spell target" }, { "CastShield", "Blizzard interrupt shield" },
}

local function AuraPicker(ui, menu, add, includeNative)
    local model = P.Suite.NameplateAuraDisplay
    if includeNative then
        for _, row in ipairs(model.NativeRows) do
            if ui.scope ~= "friendlyNpc" or row.key == "debuff" then add(menu, row.label, "auras", row.element) end
        end
    end
    for _, row in ipairs(model.Containers) do
        local group = menu:CreateButton(Tr(row.label))
        add(group, "Position", "auras", row.element)
        add(group, "Cooldown Text", "auras", row.element .. "Time")
        add(group, "Stack Count", "auras", row.element .. "Stack")
    end
    add(menu, "Aura countdown position", "auras", "CustomOneTime", true)
    add(menu, "Aura stack position", "auras", "CustomOneStack", true)
end

local function MenuSelection(ui)
    return function(parent, label, context, element, shared)
        parent:CreateButton(Tr(label), function() ui:Edit(context, element, false, shared) end)
    end
end

local function StatusPicker(ui, menu)
    P.NameplatesStatus.PreviewItems(menu, ui.scope or ui.sampleKind, function(element, sample)
        if not P.Combat() then ui:FocusStatusOffset(nil, element, sample) end
    end)
end

function Editor:OpenElementPositions(button, group)
    if P.Combat() or not self:CanPickElement() then return end
    if group == "power" then return self:Edit("text", "PowerText") end
    P.AnchoredContextMenu(button, function(_, menu)
        if group == "auras" then AuraPicker(self, menu, MenuSelection(self))
        else StatusPicker(self, menu) end
    end)
end

function Editor:BuildElementMenu(menu)
    local Add = MenuSelection(self)
    Add(menu, "Health bar", "anchor", "Health")
    local text = menu:CreateButton(Tr("Text"))
    Add(text, "Name", "text", "Name")
    Add(text, "HP Text", "text", "HealthText")
    if self.sampleKind == "enemy" then
        Add(menu, "Resource Bar", "power", "Power")
        Add(text, "Power Text", "text", "PowerText")
    end
    local cast = menu:CreateButton(Tr("Castbar"))
    for _, entry in ipairs(CAST_PICKER) do Add(cast, entry[2], "cast", entry[1]) end
    AuraPicker(self, menu:CreateButton(Tr("Auras")), Add, true)
    StatusPicker(self, menu:CreateButton(Tr("Status icons")))
end

function Editor:CanPickElement()
    return not Layers.NPCWorldNames(self) and P.Get(ID, "enabled") ~= false and P.Get(ID, "look") ~= 2
        and P.Suite.NameplateExtensions.SkinEnabled(P.S.Config(ID), self.scope or self.sampleKind)
end

-- The kit host and its handles: lifecycle and drag, select, nudge and commit.
local function BuildKit(ui)
    local body = ui.body
    ui.host = Kit.NewHost(nil, { frame = body, paint = function() ui:Paint() end })
    ui.bindings = { ownerName = "MSUF_SuiteNameplatesPreview_NudgeOwner", activeName = "MSUF_SuiteNameplatesPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteNameplatesPreview_Nudge" }
    ui.kit = P.PreviewInteraction.Handles(ui.host, {
        owner = body, bindings = ui.bindings, pixels = true, manualDrag = true, ownsCommitPaint = true,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        escape = function()
            ui.inspectedKey = nil
            ui:CancelDrag()
            ui:Select(nil)
        end,
        tab = SB and SB.CycleHandle and function(shift) return SB.CycleHandle(body, shift) end or nil,
        select = function(selected, previous)
            if selected then
                ui.inspectedKey, ui.suspendedSelection = nil, nil
            elseif previous and not previous:IsVisible() and body:IsVisible() and not P.Combat() then
                RememberHiddenSelection(ui, previous)
            end
            ui:RefreshSelection()
        end,
        drag = function(handle, phase) TrackHandleDrag(ui, handle, phase) end,
        snap = function(_, dx, dy, scale) return ui.snapper:Apply(dx, dy, scale) end,
        tip = function(handle, entering)
            -- A sample health bar shows the mouseover highlight.
            P.NameplatesPreviewDecor.Hover(handle, entering)
            if entering then
                handle.outline(1, "4ebaff")
                local opensSettings = handle._npSettingsTab or handle._npSettingKey
                    or P.NameplateStatusTarget(ui.sampleKind, handle.keyX, ui.scope)
                P.SetTranslatedText(ui.hint, Tr(handle._label) .. " - " .. Tr(opensSettings
                    and "Drag to move; click for settings" or "Drag to move; right-click for settings"))
            else
                handle.outline(0, "4ebaff")
                P.SetTranslatedText(ui.hint, ui.help)
            end
        end,
        click = function(handle, button, moved)
            if not CanEdit(handle) then return end
            if button == "RightButton" or button == "LeftButton"
                and not moved and (handle._npSettingsTab or handle._npSettingKey
                    or P.NameplateStatusTarget(ui.sampleKind, handle.keyX, ui.scope)) then
                Focus(ui, handle)
            end
        end,
    })
    ui.handles, body._handleList = ui.kit.list, ui.kit.list
end
Editor.BuildKit = BuildKit

local function BindPreviewActions(ui)
    P.ShowNameplatesSample = function(kind, scope) ui:ShowSample(kind, scope) end
    P.ShowNameplatesAuraSample = function(key) ui:ShowAuraSample(key) end
    P.EditNameplatesPreview = function(...) ui:Edit(...) end
    P.PreviewNameplateStatus = function(element, all)
        if P.Combat() then return end
        ShowStatusLayers(ui, element, all)
        if element == "Aggro" then
            ui.statusSample, ui.aggroSample = nil, true
        else
            ui.statusSample, ui.allStatusSamples = not all and element or nil, all == true
        end
        ui.statusOffsetSample = nil
        ui:Edit("status", element)
    end
    P.SelectNameplateStatusPreview = function(element)
        if P.Combat() then return end
        if ui.layerContext == "status" and not ui.allStatusSamples and ui.statusSample ~= element then
            P.PreviewNameplateStatus(element)
        else
            SelectElement(ui, element)
        end
    end
    P.PreviewNameplateOpacity = function(outOfCombat)
        if P.Combat() then return end
        ui.opacitySample = outOfCombat == true
        ui:Edit("opacity")
        ui:Select(nil)
    end
    P.PreviewNameplateHighlight = function(sample)
        if P.Combat() then return end
        if sample == "aggro" and ui.scope ~= "enemy" then P.NameplatesWorkspace.Open("enemy") end
        local plan = P.Suite.NameplateStyle.CompileHighlights(ui.barSettings or P.S.Config(ID))
        ui:SampleHighlight(sample or plan and (plan.target and "target" or plan.focus and "focus"
            or ui.scope == "enemy" and plan.aggro and "aggro" or plan.mouseover and "mouseover") or "target")
    end
    P.ShowNameplatesElementsSample = function()
        if ui.scope == "neutral" then return end
        ui.sampleKind = "enemy"
        ui.previewRole = nil
        ui.previewRoleSource = P.Get(ID, "enemyPreviewRole")
        ui:Paint()
    end
end

function Editor.Create(ctx, builder, sections)
    local section, toolbar, record = W.FixedPreviewSection(ctx, builder, { title = Tr("Nameplate preview"), height = 162, gap = 8 })
    if not section then return end
    local ui = setmetatable({ ctx = ctx, sections = sections, renderers = {}, layers = {},
        sampleKind = "enemy", zoom = 1, panX = 0, panY = 0, compact = true, layerContext = "anchor",
        softTargetSample = true, aggroSample = true,
        help = Tr("Select an element for X/Y and available size · Drag or arrow keys: move · Tab: select · Ctrl+wheel: zoom", true),
    }, { __index = Editor })
    ui.previewRole, ui.previewRoleSource = nil, P.Get(ID, "enemyPreviewRole")
    ui.title = section.title
    BindPreviewActions(ui)
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -38)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -38)
    body:SetHeight(116)
    ui.body, body.previewUI = body, ui
    BuildKit(ui)
    local canvas = CreateFrame("Frame", nil, body, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    canvas:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    canvas:SetHeight(108)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    ui.canvas = canvas
    if H.ApplyPreviewChrome then H.ApplyPreviewChrome(canvas, "canvas", T) end
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetSize(1, 1)
    stage:SetPoint("CENTER", canvas, "CENTER")
    ui.stage = stage
    ui.snapper = NewSnapper(ui)
    ui.hint = T.Font(toolbar, "GameFontDisableSmall", "", T.colors.muted)
    P.SetTranslatedText(ui.hint, ui.help)
    ui.hint:SetPoint("LEFT", section.title or toolbar, section.title and "RIGHT" or "LEFT", section.title and 12 or 160, 0)
    ui.hint:SetPoint("RIGHT", toolbar, "RIGHT", -154, 0)
    ui.hint:SetJustifyH("LEFT")
    ui.hint:SetWordWrap(false)
    ui.hint:SetMaxLines(1)
    Tools.Build(ui)
    Tools.BuildRaidPalette(ui)
    Tools.BuildSelection(ui)
    BuildSelection(ui)
    P.NameplatesElementPanel.Build(ui)
    P.NameplatesInspector.Build(ui)
    ui.guidesButton.layerKey = "guides"
    ui.layerButtons[#ui.layerButtons + 1] = ui.guidesButton
    ui.toolbar = toolbar
    P.NameplatesMultiPreview.Attach(ui)
    BuildInput(ui)
    P.NameplatesPreviewLayout.Attach(ui, section, toolbar, record)
    TrackCombat(ui)
    ui:Layout()
    M.TrackRefresh(ctx, function()
        if body:IsVisible() and not ui.host.active then ui.host:Activate() end
        ui.host:Request("settings")
    end)
    return ui
end
