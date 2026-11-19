local _, P = ...
local M, W, T, Tr, HM = P.M, P.W, P.T, P.Tr, P.HM
local ID = "nameplates"
local SB, H = M.PreviewSelectionBar, M.PreviewHelpers or {}
local Layers = P.NameplatesEditorLayers
local AURA_KIND = Layers.AURA_KIND
local AURA_ELEMENT = Layers.AuraElement
local Register, OpenSetting = Layers.Register, Layers.OpenSetting
local Kit = P.Suite.PreviewKit
local Layout = P.NameplatesPreviewLayout
local Editor = {}
P.NameplatesEditor = Editor
Editor.Layout = Layout.Apply
-- The layer rules of NameplatesEditorLayers.lua, as methods of the preview.
Editor.LayerOn, Editor.LayerAvailable, Editor.LayerActive = Layers.On, Layers.Available, Layers.Active
local RAID_MARK_NAMES = { [0] = "Off", [1] = "Star", [2] = "Circle", [3] = "Diamond",
    [4] = "Triangle", [5] = "Moon", [6] = "Blue square", [7] = "Cross", [8] = "Skull" }
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
    if handle._key and handle._key:match("%.CastShield$") and P.OpenNameplateCastDetail(ui.sampleKind, "advanced") then return end
    if P.OpenNameplateStatusItem(ui.sampleKind, handle.keyX) then return end
    if OpenSetting(key) then return end
    local section = ui.sections and ui.sections[handle.section]
    if handle._npSettingsTab then
        section = P.SelectNameplatesEnemyTab(handle._npSettingsTab) or section
    end
    if section and W.FocusCollapsibleSection then W.FocusCollapsibleSection(section, { persist = true, flash = true }) end
end
local function Write(ui, handle, x, y)
    if P.Combat() or Layers.NPCWorldNames(ui) or ui.groupPreviewEnabled then return false end
    local rules = P.catalog[ID].rules
    local xr, yr = rules[handle.keyX], rules[handle.keyY]
    if not xr or not yr then return false end
    return P.SetMany(ID, { [handle.keyX] = Clamp(Round(x), xr.min, xr.max),
        [handle.keyY] = Clamp(Round(y), yr.min, yr.max) }) ~= false
end
local function Read(handle) return P.Get(ID, handle.keyX), P.Get(ID, handle.keyY) end
local function CanEdit(handle)
    local ui = handle.previewUI
    if Layers.NPCWorldNames(ui) or ui.groupPreviewEnabled then return false end
    local visible = handle:IsVisible()
    return P.Suite.Public(visible) and visible
end

function Editor:Select(handle) self.kit:Select(handle and CanEdit(handle) and handle or nil) end

function Editor:RefreshSelection()
    local selected = self.body._selectedHandle
    for _, handle in ipairs(self.handles) do
        handle.outline(0, "4ebaff")
        P.PreviewInteraction.Outline(handle, handle == selected)
    end
    if SB then SB.Refresh(self.body) end
    if self.elementPicker and selected ~= self.pickerSelection then
        self.pickerSelection = selected
        P.SetButtonText(self.elementPicker, selected and selected._label or Tr("Select"))
        if not self.compact and not self.groupPreviewEnabled then Layout.Tools(self) end
    end
    if self.RefreshSizeSelection then self:RefreshSizeSelection() end
end

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
    if not points then return end
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
        ui.dragging = handle
    else
        if phase == "cancel" or phase == "done" then handle.previewDragPoints = nil end
        ui.dragging = nil
    end
end

function Editor:Bind(handle, id, label, keyX, keyY, section)
    handle.previewUI, handle._key, handle._label = self, id, label
    handle._color, handle.keyX, handle.keyY, handle.section = { 0.3, 0.74, 1 }, keyX, keyY, section
    BindSetting(handle, id)
    local border = P.Suite.NameplateStyle.CreateBorder(handle)
    handle.outline = function(size, color) P.Suite.NameplateStyle.PaintBorder(border, handle, size, color) end
    self.kit:Add(id, handle, function() return Read(handle) end, function(x, y) return Write(self, handle, x, y) end,
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
        if button.Refresh then button:Refresh()
        else button:SetAlpha(self:LayerActive(button.layerKey) and 1 or 0.6) end
    end
    if self.roleButton then self.roleButton:SetShown(self.sampleKind == "enemy" and self.scope ~= "neutral" and not self.enemyPlayer) end
    if self.enemyTypeButton then self.enemyTypeButton:SetShown(self.sampleKind == "enemy" and self.scope ~= "neutral") end
    if self.softTypeButton then self.softTypeButton:SetShown(self.sampleKind == "enemy") end
    if self.questButton then self.questButton:SetShown(self.sampleKind == "enemy" and self.scope ~= "neutral") end
    for _, choice in ipairs(self.raidChoices or {}) do
        choice.outline(self.raidMarked and self.raidIndex == choice.index and 1 or 0, "4ebaff")
    end
    for _, button in ipairs(self.friendlyButtons or {}) do
        button:SetShown(self.sampleKind == "friendly" and self.scope ~= "friendlyNpc")
    end
    local selected = self.body._selectedHandle
    if selected and not CanEdit(selected) then self:Select(nil) end
    self:RefreshSelection()
    if not self.compact and not self.groupPreviewEnabled then
        self:LayoutLayerRail()
        Layout.Samples(self)
    end
    Layout.UpdateViewport(self)
end

local function Button(parent, key, label, width, action)
    local button = T.Button(parent, label, width, 20)
    Layout.StyleButton(button)
    button:SetScript("OnClick", action)
    Register(button, key, label)
    return button
end

local function BuildZoomTools(ui)
    local body, canvas = ui.body, ui.canvas
    local tools = CreateFrame("Frame", nil, body)
    tools:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -4)
    tools:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -4)
    ui.tools = tools
    tools:SetHeight(46)
    local fit = Button(tools, "fit", "Fit", 36, function() Layout.Fit(ui) end)
    local actual = Button(tools, "actual", "1:1", 36, function() Layout.SetZoom(ui, 1) end)
    local zoomOut = Button(tools, "zoomOut", "-", 24, function() Layout.StepZoom(ui, -1) end)
    ui.zoomLabel = T.Font(tools, "GameFontDisableSmall", "100%", T.colors.text)
    ui.zoomLabel:SetJustifyH("CENTER")
    ui.zoomLabel:SetWordWrap(false)
    local zoomIn = Button(tools, "zoomIn", "+", 24, function() Layout.StepZoom(ui, 1) end)
    ui.zoomControls = { { fit, 36 }, { actual, 36 }, { zoomOut, 24 }, { ui.zoomLabel, 40 }, { zoomIn, 24 } }
end

-- The row of sample switches in the preview canvas: plate kind, enemy type, quest and friendly options.
local function BuildSampleButtons(ui)
    local body, canvas = ui.body, ui.canvas
    local samples = CreateFrame("Frame", nil, body)
    ui.samples = samples
    samples:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8)
    samples:SetSize(540, 20)
    ui.roleButton = Button(samples, "role", "Enemy type", 88, function()
        ui.previewRole = nil
        P.Set(ID, "enemyPreviewRole", P.Get(ID, "enemyPreviewRole") % #P.Suite.NameplateStyle.Roles + 1)
        ui:Paint()
    end)
    ui.enemyTypeButton = Button(samples, "enemyType", "NPC / player", 112, function()
        ui.enemyPlayer = not ui.enemyPlayer
        ui:Select(nil)
        ui:Paint()
    end)
    ui.softTypeButton = Button(samples, "softType", "Soft: enemy / interact", 126, function()
        ui.softInteract = not ui.softInteract
        ui:Select(nil)
        ui:Paint()
    end)
    ui.questButton = Button(samples, "questSample", "Quest", 58, function()
        if P.Get(ID, "look") == 2 then
            OpenSetting("look")
            return
        end
        ui.enemyPlayer = false
        ui.previewRole, ui.previewRoleSource = 5, P.Get(ID, "enemyPreviewRole")
        ui.raidMarked, ui.layers.questMarker = false, true
        if not P.Get(ID, "enemyQuestMarker") then P.Set(ID, "enemyQuestMarker", true) end
        ui:Paint()
        if ui.questMarkerHandle and ui.questMarkerHandle:IsShown() then ui:Select(ui.questMarkerHandle) end
    end)
    ui.friendlyButtons = {}
    ui.friendlyButtons[1] = Button(samples, "friendlyMode", "Friendly player display", 146, function()
        OpenSetting("friendlyNamesOnly")
    end)
    ui.friendlyButtons[2] = Button(samples, "friendlyGroup", "Group / outsider", 114, function()
        ui.friendlyOutsider = not ui.friendlyOutsider
        ui:Paint()
    end)
    if H.EnsurePreviewBackgroundButton then
        local background = H.EnsurePreviewBackgroundButton(body, samples)
        if background then
            background:ClearAllPoints()
            background:SetPoint("RIGHT", canvas, "TOPRIGHT", -8, -18)
            ui.backgroundButton = background
        end
    end
    ui.sampleButtons = { ui.roleButton, ui.enemyTypeButton, ui.softTypeButton,
        ui.questButton, ui.friendlyButtons[1], ui.friendlyButtons[2] }
end

local function BuildTools(ui)
    BuildZoomTools(ui)
    local tools = ui.tools
    ui.targetStateButton = Button(tools, "targetSample", "Target / non-target", 126, function()
        ui.targetSample = ui.targetSample == false
        ui:Paint()
    end)
    ui.focusStateButton = Button(tools, "focusSample", "Focus sample", 96, function()
        ui.focusSample = not ui.focusSample
        ui:Paint()
    end)
    BuildSampleButtons(ui)
end

local function BuildRaidPalette(ui)
    local strip = CreateFrame("Frame", nil, ui.canvas)
    ui.raidPalette = strip
    strip:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -8, -39)
    strip:SetSize(165, 22)
    local title = T.Font(strip, "GameFontDisableSmall", "RAID MARKS", T.colors.muted)
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
            ui.layers.raidIcon, ui.layers.status = true, true
            ui:Paint()
        end)
        button:SetScript("OnEnter", function()
            P.SetTranslatedText(ui.hint, Tr("Raid mark: %s"):format(Tr(RAID_MARK_NAMES[index])) .. " - "
                .. Tr("Click to preview; right-click for settings"))
        end)
        button:SetScript("OnLeave", function() P.SetTranslatedText(ui.hint, ui.help) end)
        Register(button, "raidMark." .. index, Tr("Raid mark: %s"):format(Tr(RAID_MARK_NAMES[index])))
        ui.raidChoices[index] = button
    end
end

local function BuildElementPicker(ui, tools)
    local picker = T.Button(tools, "Select", 182, 20)
    Layout.StyleButton(picker)
    picker:SetScript("OnClick", function()
        if P.Combat() or not ui:CanPickElement() then return end
        P.AnchoredContextMenu(picker, function(_, menu) ui:BuildElementMenu(menu) end)
    end)
    Register(picker, "selectElement", "Select")
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
            WriteOffsets = function(_, handle, x, y)
                local ok = Write(ui, handle, x, y)
                ui:Paint()
                return ok
            end,
            SelectHandle = function(_, handle)
                ui:Select(handle)
                return true
            end,
            ResetOffsets = function(_, handle)
                if Layers.NPCWorldNames(ui) then return false end
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
    self.castSample, self.interruptedSample = nil, nil
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
    self.editFullPlate = element == "Health" or element == "HealthText" or self.auraSample ~= nil
        or context == "status" and self.statusOffsetSample == "Level"
    if context == "anchor" then self.layers.health = true end
    if layer then self.layers[layer], self.layers.health = true, true end
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
        self.highlightSample = nil
        self:Paint()
        return
    end
    self.highlightSample = sample
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

local function AuraPicker(ui, menu, add)
    local model = P.Suite.NameplateAuraDisplay
    for _, row in ipairs(model.NativeRows) do
        if ui.scope ~= "friendlyNpc" or row.key == "debuff" then add(menu, row.label, "auras", row.element) end
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

function Editor:BuildElementMenu(menu)
    local function Add(parent, label, context, element, shared)
        parent:CreateButton(Tr(label), function() self:Edit(context, element, false, shared) end)
    end
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
    AuraPicker(self, menu:CreateButton(Tr("Auras")), Add)
    local status = menu:CreateButton(Tr("Status icons"))
    P.NameplatesStatus.PreviewItems(status, self.scope or self.sampleKind, function(element, sample)
        if not P.Combat() then self:FocusStatusOffset(nil, element, sample) end
    end)
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
        owner = body, bindings = ui.bindings, pixels = true, manualDrag = true,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        escape = function()
            ui:CancelDrag()
            ui:Select(nil)
        end,
        tab = SB and SB.CycleHandle and function(shift) return SB.CycleHandle(body, shift) end or nil,
        select = function() ui:RefreshSelection() end,
        drag = function(handle, phase) TrackHandleDrag(ui, handle, phase) end,
        tip = function(handle, entering)
            -- A sample health bar shows the mouseover highlight.
            P.NameplatesPreviewDecor.Hover(handle, entering)
            if entering then
                handle.outline(1, "4ebaff")
                P.SetTranslatedText(ui.hint, Tr(handle._label) .. " - " .. Tr((handle._npSettingsTab or handle._npSettingKey)
                    and "Drag to move; click for settings" or "Drag to move; right-click for settings"))
            else
                ui:RefreshSelection()
                P.SetTranslatedText(ui.hint, ui.help)
            end
        end,
        click = function(handle, button, moved)
            if not CanEdit(handle) then return end
            if button == "RightButton" or button == "LeftButton"
                and (handle._npSettingsTab or handle._npSettingKey) and not moved then
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
    ui.hint = T.Font(toolbar, "GameFontDisableSmall", "", T.colors.muted)
    P.SetTranslatedText(ui.hint, ui.help)
    ui.hint:SetPoint("LEFT", section.title or toolbar, section.title and "RIGHT" or "LEFT", section.title and 12 or 160, 0)
    ui.hint:SetPoint("RIGHT", toolbar, "RIGHT", -154, 0)
    ui.hint:SetJustifyH("LEFT")
    ui.hint:SetWordWrap(false)
    ui.hint:SetMaxLines(1)
    BuildTools(ui)
    BuildRaidPalette(ui)
    BuildSelection(ui)
    Layers.Build(ui)
    ui.toolbar = toolbar
    P.NameplatesMultiPreview.Attach(ui)
    BuildInput(ui)
    P.NameplatesPreviewLayout.Attach(ui, section, toolbar, record)
    TrackCombat(ui)
    ui:Layout()
    M.TrackRefresh(ctx, function() ui:Paint() end)
    return ui
end
