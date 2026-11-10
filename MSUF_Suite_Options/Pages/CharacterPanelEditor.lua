local _, P = ...
local Editor = {}
P.CharacterPanelEditor = Editor

local S, M, W, T, HM, Interaction = P.S, P.M, P.W, P.T, P.HM, P.PreviewInteraction
local Header, Model, Canvas = S.CharacterHeader, P.Suite.CharacterTabs, P.PreviewCanvas
local ID, PAGE = "characterPanel", "suite_hud"
local FIELD, TAB = "field", "tab"
local OWN, INSPECT = "own", "inspect"
local TABS_LAYER = "tabs"
local PREVIEW_TOP, GAP, TAB_HEIGHT = 66, 4, 25
local MODE_HEIGHT, ADD_WIDTH = 28, 32
local FIELD_HELP = "Drag or use arrows to move; click for settings."
local TAB_HELP = "Drag to reorder or select an element and use the arrows."
local LAYERS = { { TABS_LAYER, "Tabs" } }
local FIELDS = {}
for index, field in ipairs(Header.Fields) do
    LAYERS[index + 1] = { field.id, field.label }
    FIELDS[field.id] = field
end

function Editor.FieldSection(id)
    return PAGE .. "_" .. ID .. "_" .. id
end

function Editor.ResetOrder()
    local rules = P.catalog[ID].rules
    P.ResetRules(ID, { rules.headerOrder, rules.tabOrder, rules.inspectTabOrder })
end

local function OpenField(ui, field)
    if P.Combat() then return end
    local section = ui.ctx.characterHeaderSections and ui.ctx.characterHeaderSections[field.id]
    if not section then return end
    P.EnsureSectionContent(section)
    W.FocusCollapsibleSection(section, { persist = true, scroll = false, flash = false })
    local key = "msufsuite." .. ID .. "." .. field.prefix .. "Size"
    if P.Suite.HostBridge.OpenExactMenuSetting(M, PAGE, Editor.FieldSection(field.id), key) then return end
    W.FocusCollapsibleSection(section, { flash = true })
end

local function TabKind(ui)
    return ui.mode == OWN and TAB or "inspectTab"
end

local function TabKey(ui)
    return ui.mode == OWN and "tabOrder" or "inspectTabOrder"
end

local function PositionTab(handle)
    return handle.group == TAB and handle.spec.custom and handle.ui.mode == OWN and handle.ui.positionMode == true
end

local function ReadPosition(handle, config)
    if PositionTab(handle) then return Model.Position(Model.Find(config, handle.spec.id)) end
    if handle.group == TAB then return 0, 0 end
    return config[handle.xKey] or 0, config[handle.yKey] or 0
end

local function DrawnOffsets(handle)
    if PositionTab(handle) then return Model.Position(handle.spec) end
    if handle.group == TAB then return 0, 0 end
    return handle.x - handle.baseX, handle.baseY - handle.y
end

local function Neighbors(ui, handle)
    if not handle or handle.group ~= TAB then return end
    for index, entry in ipairs(ui.order) do
        if entry == handle.spec then return ui.order[index - 1], ui.order[index + 1] end
    end
end

local function RefreshSelection(ui)
    local handle = ui.direct and ui.direct:Selected() or ui.kit:Selected()
    local before, after = Neighbors(ui, handle)
    local enabled = handle and handle:IsVisible() and not P.Combat()
    local position = handle and (handle.group == FIELD or (ui.mode == OWN and ui.positionMode and handle.spec.custom)) or false
    ui.earlier:SetEnabled(enabled and (position or before ~= nil) or false)
    ui.later:SetEnabled(enabled and (position or after ~= nil) or false)
    if ui.hintGroup ~= position then
        ui.hintGroup = position
        P.SetTranslatedText(ui.hint, P.Suite.Text(position and FIELD_HELP or TAB_HELP))
    end
end

local function MoveTab(ui, handle, target, config)
    if not target then return false end
    local order = Header.Move(config, TabKind(ui), handle.spec.id, target.id)
    local key = TabKey(ui)
    if not order or order == config[key] then return false end
    return P.Set(ID, key, order) ~= false
end

local function DropTarget(handle, dx, dy)
    local ui = handle.ui
    local x = handle.layoutX + handle.layoutWidth / 2 + dx
    local y = handle.layoutY - TAB_HEIGHT / 2 + dy
    for _, entry in ipairs(ui.order) do
        local other = ui.tabs[entry.id]
        if other ~= handle and x >= other.layoutX and x <= other.layoutX + other.layoutWidth
            and y <= other.layoutY and y >= other.layoutY - TAB_HEIGHT then
            return other
        end
    end
end

local function CurrentDrag(handle, config)
    local claim, ui = handle.claim, handle.ui
    if not claim or not claim.current() or claim.config ~= config or claim.mode ~= ui.mode
        or claim.positionMode ~= ui.positionMode then return false end
    if handle.group == TAB then
        return claim.order == Header.Order(config, TabKind(ui))
    end
    local x, y = ReadPosition(handle, config)
    return x == claim.savedX and y == claim.savedY
end

local function WriteTabPosition(handle, config, x, y)
    x, y = Model.ClampPosition(TAB, x, y)
    local oldX, oldY = ReadPosition(handle, config)
    if x == oldX and y == oldY then return false end
    local tabs = Model.Copy(config)
    for _, tab in ipairs(tabs) do
        if tab.id == handle.spec.id then
            tab.x, tab.y = x, y
            local encoded = Model.Encode(tabs)
            return encoded ~= nil and P.Set(ID, "customTabs", encoded) ~= false
        end
    end
    return false
end

local function WritePosition(handle, x, y, dragged)
    local ui, config = handle.ui, S.Config(ID)
    if P.Combat() or not handle:IsVisible() or (dragged and not CurrentDrag(handle, config)) then return false end
    if handle.group == TAB then
        if PositionTab(handle) then return WriteTabPosition(handle, config, x, y) end
        if dragged then
            local target = DropTarget(handle, x, y)
            return MoveTab(ui, handle, target and target.spec, config)
        end
        local before, after = Neighbors(ui, handle)
        local delta = x ~= 0 and x or -y
        return MoveTab(ui, handle, delta < 0 and before or (delta > 0 and after), config)
    end
    x, y = Header.DragOffsets(ui.header, handle.spec.id, math.floor(x + .5), math.floor(y + .5))
    local oldX, oldY = ReadPosition(handle, config)
    if x == oldX and y == oldY then return false end
    return P.SetMany(ID, { [handle.xKey] = x, [handle.yKey] = y }) ~= false
end

local function PaintOutline(handle, hovering)
    if not handle then return end
    local ui = handle.ui
    Interaction.Outline(handle, handle:IsVisible() and (hovering or ui.kit:Selected() == handle or ui.drop == handle))
end

local function SetDrop(ui, target)
    if ui.drop == target then return end
    local previous = ui.drop
    ui.drop = target
    PaintOutline(previous)
    PaintOutline(target)
end

local function DrawDrag(handle, dx, dy)
    local claim = handle.claim
    if not claim then return end
    if handle.group == FIELD then
        local x, y = Header.DragOffsets(handle.ui.header, handle.spec.id, claim.x + dx, claim.y + dy)
        dx, dy = x - claim.x, y - claim.y
    elseif claim.positionMode and handle.spec.custom then
        local x, y = Model.ClampPosition(TAB, claim.x + dx, claim.y + dy)
        local scale = handle.ui.scale
        dx, dy = (x - claim.x) * scale, (y - claim.y) * scale
    else
        SetDrop(handle.ui, DropTarget(handle, dx, dy))
    end
    if claim.drawX == dx and claim.drawY == dy then return end
    claim.drawX, claim.drawY = dx, dy
    handle:ClearAllPoints()
    handle:SetPoint("TOPLEFT", claim.parent, "TOPLEFT", claim.left + dx, claim.top + dy)
end

local function DragPhase(handle, phase)
    local ui, claim = handle.ui, handle.claim
    if phase == "press" then
        local config = S.Config(ID)
        local savedX, savedY = ReadPosition(handle, config)
        local x, y = DrawnOffsets(handle)
        local parent = handle.group == FIELD and ui.header.frame or ui.host
        local left, top = handle.x, handle.y and -handle.y
        if handle.group == TAB then left, top = handle.layoutX, handle.layoutY end
        handle.cancelled = nil
        handle.claim = { current = P.ProfileGuard(), config = config, mode = ui.mode,
            order = ui.order, positionMode = ui.positionMode,
            x = x, y = y, parent = parent, left = left, top = top,
            savedX = savedX, savedY = savedY, drawX = 0, drawY = 0, level = handle:GetFrameLevel() }
    elseif phase == "start" and claim then
        handle:SetFrameLevel(claim.level + 8)
    elseif phase == "stop" or phase == "cancel" then
        if claim then
            DrawDrag(handle, 0, 0)
            handle:SetFrameLevel(claim.level)
        end
        SetDrop(ui)
        if phase == "cancel" then handle.claim, handle.cancelled = nil, true end
    elseif phase == "done" then
        handle.claim = nil
    end
end

local function Bind(ui, button, group, spec)
    button.ui, button.group, button.spec = ui, group, spec
    if group == FIELD then button.xKey, button.yKey = spec.prefix .. "X", spec.prefix .. "Y" end
    ui.kit:Add(button, button, function() return DrawnOffsets(button) end,
        function(x, y, dragged) return WritePosition(button, x, y, dragged) end,
        { follow = DrawDrag, scale = function()
            local scale = button:GetEffectiveScale()
            return PositionTab(button) and scale * ui.scale or scale
        end })
    HM.SkipHistoryCheckpoint(button)
    if group == FIELD then M.AddTooltip(button, spec.label, FIELD_HELP, { hook = true }) end
end

local function RecycleTabs(ui, config)
    local definitions = Model.Get(config)
    if ui.customDefinitions == definitions then return end
    ui.customDefinitions = definitions
    for id, button in pairs(ui.tabs) do
        if button.spec.custom and not Model.Find(config, id) then
            ui.tabs[id] = nil
            button:Hide()
            ui.freeTabs[#ui.freeTabs + 1] = button
        end
    end
end

local function EnsureTab(ui, spec)
    local button = ui.tabs[spec.id]
    if not button then
        button = spec.custom and table.remove(ui.freeTabs) or nil
        if not button then
            button = T.Button(ui.host, spec.label, 64, TAB_HEIGHT)
            Bind(ui, button, TAB, spec)
        end
        ui.tabs[spec.id] = button
    elseif button.spec == spec then
        return button
    end
    button.spec, button.cancelled = spec, nil
    P.SetButtonText(button, spec.label)
    return button
end

local function Sample()
    local class, spec, guild = P.Suite.Text("Priest"), P.Suite.Text("Holy"), P.Suite.Text("Example guild")
    return {
        [OWN] = { portrait = "player", name = "Mapko", level = 23, class = class,
            specialization = spec, guild = guild, zone = P.Suite.Text("Example zone"), itemLevel = "12" },
        [INSPECT] = { portrait = "player", name = "Alyra", level = 26, class = class,
            specialization = spec, guild = guild, itemLevel = "19" },
    }
end

local function LayoutTabs(ui, width, top, shown)
    local order, fontRevision = ui.order, S.FontRevision
    local add = shown and (ui.mode == OWN or #ui.hiddenTabs > 0)
    if ui.tabOrder == order and ui.tabWidth == width and ui.tabTop == top and ui.addVisible == add
        and ui.tabFontRevision == fontRevision and ui.tabsVisible == shown then return ui.tabRailHeight end
    ui.addVisible = add
    ui.tabOrder, ui.tabWidth, ui.tabTop, ui.tabFontRevision, ui.tabsVisible = order, width, top, fontRevision, shown
    local hasCustom = shown and ui.mode == OWN and #ui.customDefinitions > 0
    local bounds = Model.PositionBounds.tab
    local inset = hasCustom and bounds.x * ui.scale or 0
    local reachY = hasCustom and bounds.y * ui.scale or 0
    local right, step = width - inset, TAB_HEIGHT + GAP + 2 * reachY
    local x, row = inset, 0
    local painted = ui.shownTabs
    wipe(painted)
    if shown then
        for _, entry in ipairs(order) do
            local button = EnsureTab(ui, entry)
            painted[entry.id] = true
            local label = HM.GetControlLabel(button)
            local natural = math.max(57, math.ceil(label and label:GetUnboundedStringWidth() or 0) + 20)
            local buttonWidth = math.min(right - inset, 180, natural)
            if x > inset and x + buttonWidth > right then x, row = inset, row + 1 end
            local dx, dy = Model.Position(entry)
            button.layoutX = x + dx * ui.scale
            button.layoutY = -top - reachY - row * step + dy * ui.scale
            button.layoutWidth = buttonWidth
            button:ClearAllPoints()
            button:SetSize(buttonWidth, TAB_HEIGHT)
            button:SetPoint("TOPLEFT", ui.host, "TOPLEFT", button.layoutX, button.layoutY)
            x = x + buttonWidth + GAP
        end
    end
    if add then
        if x > inset and x + ADD_WIDTH > right then x, row = inset, row + 1 end
        ui.addTab:ClearAllPoints()
        ui.addTab:SetPoint("TOPLEFT", ui.host, "TOPLEFT", x, -top - reachY - row * step)
    end
    ui.addTab:SetShown(add)
    for id, button in pairs(ui.tabs) do button:SetShown(painted[id] == true) end
    ui.tabRailHeight = shown and top + (row + 1) * step or top
    return ui.tabRailHeight
end

local function LayoutHeader(ui, width, positionVisible, actionsVisible)
    if ui.previewWidth == width and ui.positionVisible == positionVisible and ui.actionsVisible == actionsVisible then return end
    ui.previewWidth, ui.positionVisible, ui.actionsVisible = width, positionVisible, actionsVisible
    ui.scale = math.min(1, width / Header.PreviewWidth)
    ui.header.frame:SetScale(ui.scale)
    ui.headerCanvas:SetSize(width, Header.Height * ui.scale)
    local columns = 2 + (positionVisible and 1 or 0) + (actionsVisible and 1 or 0)
    local buttonWidth = math.min(152, math.floor((width - (columns - 1) * GAP) / columns))
    ui.ownButton:SetWidth(buttonWidth)
    ui.inspectButton:SetWidth(buttonWidth)
    ui.positionButton:SetWidth(buttonWidth)
    ui.positionButton:SetShown(positionVisible)
    ui.addContent:Hide()
    ui.tabActions:SetShown(actionsVisible)
    if actionsVisible then
        ui.tabActions:SetWidth(buttonWidth)
        ui.tabActions:ClearAllPoints()
        ui.tabActions:SetPoint("TOPLEFT", positionVisible and ui.positionButton or ui.inspectButton, "TOPRIGHT", GAP, 0)
    end
    Interaction.LayoutLayerRail(ui, width)
end

local function RefreshLayers(ui, sample, tabs, header)
    ui.layers[TABS_LAYER] = tabs
    for index, field in ipairs(Header.Fields) do
        ui.layers[field.id] = header.buttons[field.id]:IsShown()
        local available = field.portrait or sample[field.id] ~= nil
        ui.layerButtons[index + 1]:SetEnabled(available)
    end
    Interaction.RefreshLayerRail(ui)
end

local Refresh

local function UpdateHeight(ui, height)
    if height == ui.height then return end
    ui.height = height
    ui.host:SetHeight(height)
    ui.heightChanged(PREVIEW_TOP + height)
end

local function SelectPreviewTab(ui, id)
    if id == ui.selectedTabs[ui.mode] or not Header.TabVisible(S.Config(ID), TabKind(ui), id) then return end
    ui.selectedTabs[ui.mode] = id
    ui.custom:Cancel()
    Refresh(ui)
end

local function ShowEditor(ui, shown, width)
    if ui.editorShown == shown then return end
    ui.editorShown = shown
    ui.headerCanvas:SetShown(shown)
    if not shown then
        P.SetButtonText(ui.addTab, P.Tr("Add tab"))
        ui.kit:Release()
        LayoutTabs(ui, width, 0, false)
        ui.custom:Refresh(width, 0, nil, false)
    end
end

local function LayoutFullToolbar(ui, width, own, custom)
    local showPosition = own and #ui.customDefinitions > 0
    local showAdd = own or #ui.hiddenTabs > 0
    if ui.toolbarWidth == width and ui.toolbarCustom == custom and ui.toolbarAdd == showAdd
        and ui.toolbarPosition == showPosition then return ui.toolbarHeight end
    ui.toolbarWidth, ui.toolbarCustom, ui.toolbarPosition, ui.toolbarAdd = width, custom, showPosition, showAdd
    local visible = { true, true, showAdd, showPosition, custom, true }
    local count = 0
    for _, shown in ipairs(visible) do if shown then count = count + 1 end end
    local columns = math.min(count, width >= 840 and 6 or width >= 420 and 3 or 2)
    local buttonWidth = math.min(152, math.floor((width - (columns - 1) * GAP) / columns))
    local slot = 0
    for index, button in ipairs(ui.toolbar) do
        local shown = visible[index]
        button:SetShown(shown)
        if shown then
            button:SetWidth(buttonWidth)
            button:ClearAllPoints()
            local x = (slot % columns) * (buttonWidth + GAP)
            button:SetPoint("TOPLEFT", ui.host, "TOPLEFT", x, -math.floor(slot / columns) * MODE_HEIGHT)
            slot = slot + 1
        end
    end
    ui.toolbarHeight = math.ceil(count / columns) * MODE_HEIGHT
    ui.fullCanvas:ClearAllPoints()
    ui.fullCanvas:SetPoint("TOPLEFT", 0, -ui.toolbarHeight)
    ui.fullCanvas:SetPoint("TOPRIGHT", 0, -ui.toolbarHeight)
    return ui.toolbarHeight
end

local function UpdateTabControls(ui)
    local unlocked = not P.Combat()
    local own = ui.mode == OWN
    local canAdd = unlocked and (#ui.hiddenTabs > 0 or (own and #ui.customDefinitions < Model.TabLimit))
    local canEdit = unlocked and (own or #ui.order > 1)
    if ui.canAdd ~= canAdd then
        ui.canAdd = canAdd
        ui.addTab:SetEnabled(canAdd)
    end
    if ui.canEdit ~= canEdit then
        ui.canEdit = canEdit
        ui.tabActions:SetEnabled(canEdit)
    end
end

local function TabClaim(ui, anchor)
    local config, kind = S.Config(ID), TabKind(ui)
    return { config = config, kind = kind, anchor = anchor, current = P.ProfileGuard(),
        order = ui.order, selected = ui.selectedTabs[ui.mode] }
end

local function CurrentTabs(ui, claim)
    return not P.Combat() and claim.current() and claim.config == S.Config(ID) and claim.kind == TabKind(ui)
        and claim.anchor:IsVisible() and Header.Order(claim.config, claim.kind) == claim.order
        and ui.selectedTabs[ui.mode] == claim.selected
end

local function AddTab(ui, anchor)
    if not ui.canAdd then return end
    local claim = TabClaim(ui, anchor)
    ui.custom:Add(anchor, ui.hiddenTabs, function(id)
        if not CurrentTabs(ui, claim) then return end
        local patch = Header.SetTabVisible(claim.config, claim.kind, id, true)
        if patch and P.SetMany(ID, patch) then SelectPreviewTab(ui, id) end
    end)
end

local function OpenTabActions(ui, anchor)
    if not ui.canEdit then return end
    if ui.mode == OWN and ui.customSelected then return ui.custom:OpenTabActions(anchor) end
    local claim = TabClaim(ui, anchor)
    P.ContextMenu(anchor, function(_, menu)
        if claim.kind == TAB then
            menu:CreateButton(P.Tr("Key bindings"), function()
                if CurrentTabs(ui, claim) then P.CharacterPanelBindings.Open(ui.ctx, claim.selected) end
            end)
            if Header.HomeTab(claim.config, TAB) == claim.selected then
                menu:CreateTitle(P.Tr("Character start tab"))
            else
                menu:CreateButton(P.Tr("Use as character start tab"), function()
                    if not CurrentTabs(ui, claim) then return end
                    local patch = Header.SetHomeTab(claim.config, claim.selected)
                    if patch then P.SetMany(ID, patch) end
                end)
            end
        end
        if #claim.order > 1 then
            menu:CreateButton(P.Tr("Hide tab"), function()
                if not CurrentTabs(ui, claim) then return end
                local patch = Header.SetTabVisible(claim.config, claim.kind, claim.selected, false)
                if patch then P.SetMany(ID, patch) end
            end)
        end
    end)
end

local function PaintFullPreview(ui, config, width, overrides)
    if not ui.preview and Canvas.Runtime("MSUF_Suite_CharacterPanel", "CharacterPanelPreview") then
        local function Select(id) SelectPreviewTab(ui, id) end
        ui.preview = S.CharacterPanelPreview.New(ui.fullCanvas, ui.sample, Select)
        ui.direct = P.CharacterPreviewHandles.Create(ui, ui.preview, Select, function(field) OpenField(ui, field) end,
            function() Refresh(ui) end, function() RefreshSelection(ui) end)
    end
    local preview = ui.preview
    ShowEditor(ui, not preview, width)
    if not preview then return false end
    local tab, own = ui.selectedTabs[ui.mode], ui.mode == OWN
    local custom = own and Model.Find(config, tab)
    local customID = custom and tab or nil
    if ui.attachedCustom ~= customID or ui.attachedOwn ~= own then ui.custom:DetachPreview() end
    ui.attachedCustom, ui.attachedOwn = customID, own
    local toolbarHeight = LayoutFullToolbar(ui, width, own, customID ~= nil)
    local height = preview:Paint(config, ui.mode, ui.order, tab, overrides, width)
    if ui.fullHeight ~= height then
        ui.fullHeight = height
        ui.fullCanvas:SetHeight(height)
    end
    ui.direct:Refresh(ui.order, own and ui.positionMode == true)
    if own then ui.custom:AttachPreview(preview, customID, ui.positionMode, ui.contentPosition) end
    if ui.fullLayerWidth ~= width then
        ui.fullLayerWidth = width
        Interaction.LayoutLayerRail(ui, width)
    end
    RefreshLayers(ui, ui.sample[ui.mode], overrides.tabs ~= false, preview.view.header)
    local layerTop = toolbarHeight + height + GAP
    if ui.layerTop ~= layerTop then
        ui.layerTop = layerTop
        ui.chips:SetPoint("TOPLEFT", ui.host, "TOPLEFT", 0, -layerTop)
    end
    RefreshSelection(ui)
    local hintHeight = math.max(34, math.ceil(ui.hint:GetStringHeight()) + 14)
    UpdateHeight(ui, layerTop + ui.chips:GetHeight() + hintHeight + GAP)
    return true
end

Refresh = function(ui)
    if not ui.host:IsVisible() then return end
    local width = math.floor(ui.host:GetWidth())
    if width < 24 then return end
    local config, sample = S.Config(ID), ui.sample[ui.mode]
    local overrides = ui.overrides[ui.mode]
    local kind = TabKind(ui)
    ui.order, ui.hiddenTabs = Header.Order(config, kind), Header.HiddenTabs(config, kind)
    local selected = ui.selectedTabs[ui.mode]
    if not Header.TabVisible(config, kind, selected) then
        selected = Header.HomeTab(config, kind)
        ui.selectedTabs[ui.mode] = selected
    end
    if ui.mode == OWN then ui.customSelected = Model.Find(config, selected) and selected or nil end
    RecycleTabs(ui, config)
    UpdateTabControls(ui)
    if PaintFullPreview(ui, config, width, overrides) then return end
    local tabs = overrides[TABS_LAYER] ~= false
    local ownTabs = ui.mode == OWN and tabs
    LayoutHeader(ui, width, ownTabs and #ui.customDefinitions > 0, tabs and not (ownTabs and ui.customSelected))
    ui.header:Render(config, sample, nil, Header.PreviewWidth, 0, overrides)
    local railHeight = LayoutTabs(ui, width, MODE_HEIGHT + Header.Height * ui.scale + GAP, tabs)
    RefreshLayers(ui, sample, tabs, ui.header)
    RefreshSelection(ui)
    if ui.actionsTop ~= railHeight then
        ui.actionsTop = railHeight
        ui.chips:SetPoint("TOPLEFT", ui.host, "TOPLEFT", 0, -railHeight - GAP)
    end
    local height = railHeight + ui.chips:GetHeight() + math.max(34, math.ceil(ui.hint:GetStringHeight()) + 14) + GAP
    height = ui.custom:Refresh(width, height, ui.customSelected, ownTabs, ui.positionMode, ui.scale)
    UpdateHeight(ui, height)
end

local function ChooseMode(ui, mode)
    if ui.mode == mode or P.Combat() then return end
    ui.kit:Release()
    if ui.direct then ui.direct:Release() end
    ui.custom:Cancel()
    ui.mode = mode
    ui.ownButton:SetAlpha(mode == OWN and 1 or .65)
    ui.inspectButton:SetAlpha(mode == INSPECT and 1 or .65)
    Refresh(ui)
    if ui.editorShown and mode == OWN and ui.customSelected then ui.kit:Select(ui.tabs[ui.customSelected]) end
end

local function Repaint(ui)
    if ui.direct then ui.direct:Cancel() end
    if ui.kit.drag then ui.kit:Cancel() else Refresh(ui) end
end

local function ModeButton(ui, mode, label)
    local button = T.Button(ui.host, label, 152, MODE_HEIGHT - GAP)
    button:SetAlpha(ui.mode == mode and 1 or .65)
    HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", function() ChooseMode(ui, mode) end)
    return button
end

local function PositionButton(ui)
    local button = T.Button(ui.host, "Position X/Y", 152, MODE_HEIGHT - GAP)
    button:SetAlpha(.65)
    HM.SkipHistoryCheckpoint(button)
    M.AddTooltip(button, "Position X/Y", "Drag to position elements or switch back to reorder.", { hook = true })
    button:SetScript("OnClick", function()
        if P.Combat() or ui.mode ~= OWN then return end
        ui.kit:Cancel()
        if ui.direct then ui.direct:Release() end
        ui.custom:Cancel()
        ui.positionMode = not ui.positionMode
        button:SetAlpha(ui.positionMode and 1 or .65)
        Refresh(ui)
    end)
    return button
end

local function Arrow(ui, label, direction)
    local button = T.Button(ui.host, label, 26, 25)
    HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", function()
        local controls = ui.direct or ui.kit
        controls:Nudge(direction, 0)
    end)
    M.AddTooltip(button, direction < 0 and "Move earlier" or "Move later", TAB_HELP, { hook = true })
    return button
end

local function ClickHandle(ui, handle, moved)
    if moved or handle.cancelled or P.Combat() then return end
    if handle.group == FIELD then OpenField(ui, handle.spec) return end
    SelectPreviewTab(ui, handle.spec.id)
end

local function CreateStage(ui)
    local host = ui.host
    ui.fullCanvas = CreateFrame("Frame", nil, host)
    ui.fullCanvas:SetPoint("TOPLEFT", 0, -MODE_HEIGHT)
    ui.fullCanvas:SetPoint("TOPRIGHT", 0, -MODE_HEIGHT)
    ui.headerCanvas = CreateFrame("Frame", nil, host)
    ui.headerCanvas:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -MODE_HEIGHT)
    ui.header = Header.Create(ui.headerCanvas, { field = function() end })
    ui.header.frame:SetPoint("TOPLEFT")
    local previewHost = P.Suite.PreviewKit.NewHost(nil, { frame = host, paint = function() Refresh(ui) end })
    ui.kit = Interaction.Handles(previewHost, {
        pixels = true, threshold = 4, manualDrag = true,
        pointerHeld = function() return IsMouseButtonDown("LeftButton") end,
        click = function(handle, _, moved) ClickHandle(ui, handle, moved) end,
        tip = PaintOutline, drag = DragPhase,
        mark = function(handle) PaintOutline(handle) end,
        select = function() RefreshSelection(ui) end,
    })
    for _, field in ipairs(Header.Fields) do Bind(ui, ui.header.buttons[field.id], FIELD, field) end
    for _, spec in ipairs(Header.Tabs) do EnsureTab(ui, spec) end
    for _, spec in ipairs(Header.InspectTabs) do EnsureTab(ui, spec) end
    ui.addTab = T.Button(host, "+", ADD_WIDTH, TAB_HEIGHT)
    HM.SkipHistoryCheckpoint(ui.addTab)
    M.AddTooltip(ui.addTab, "Add tab", nil, { hook = true })
    ui.addTab:SetScript("OnClick", function(button) AddTab(ui, button) end)
end

local function CreateRail(ui)
    Interaction.BuildLayerRail(ui, ui.host, LAYERS, function(key, enabled)
        local sample = ui.sample[ui.mode]
        if P.Combat() or (key ~= TABS_LAYER and sample[key] == nil) then return false end
        ui.overrides[ui.mode][key] = enabled
        Repaint(ui)
        return true
    end, function(spec)
        local field = FIELDS[spec[1]]
        if ui.direct then
            if field then ui.direct:SelectField(field.id) else ui.direct:SelectTab(ui.selectedTabs[ui.mode]) end
        elseif not field then
            if ui.layers[TABS_LAYER] then ui.kit:Select(ui.tabs[ui.order[1].id]) end
        else
            local handle = ui.header.buttons[field.id]
            if handle:IsVisible() then ui.kit:Select(handle) end
        end
        if field then OpenField(ui, field) end
        return true
    end)
    local host = ui.host
    ui.earlier = Arrow(ui, "<", -1)
    ui.earlier:SetPoint("TOPLEFT", ui.chips, "BOTTOMLEFT", 0, -GAP)
    ui.later = Arrow(ui, ">", 1)
    ui.later:SetPoint("TOPLEFT", ui.earlier, "TOPRIGHT", GAP, 0)
    ui.hint = T.Font(host, "GameFontHighlightSmall", TAB_HELP, T.colors.muted, "supporting")
    ui.hint:SetPoint("TOPLEFT", ui.later, "TOPRIGHT", 8, -5)
    ui.hint:SetPoint("TOPRIGHT", ui.chips, "BOTTOMRIGHT", -2, -GAP - 5)
    ui.hint:SetWordWrap(true)
end

local function CreateToolbar(ui)
    local host = ui.host
    ui.ownButton = ModeButton(ui, OWN, "Own character")
    ui.inspectButton = ModeButton(ui, INSPECT, "Inspect")
    ui.positionButton = PositionButton(ui)
    ui.addContent = T.Button(host, "Add content", 152, MODE_HEIGHT - GAP)
    ui.tabActions = T.Button(host, "Tab actions", 152, MODE_HEIGHT - GAP)
    HM.SkipHistoryCheckpoint(ui.addContent)
    HM.SkipHistoryCheckpoint(ui.tabActions)
    ui.addContent:SetScript("OnClick", function(button) ui.custom:OpenContent(button) end)
    ui.tabActions:SetScript("OnClick", function(button) OpenTabActions(ui, button) end)
    ui.ownButton:SetPoint("TOPLEFT")
    ui.inspectButton:SetPoint("TOPLEFT", ui.ownButton, "TOPRIGHT", GAP, 0)
    ui.positionButton:SetPoint("TOPLEFT", ui.inspectButton, "TOPRIGHT", GAP, 0)
    ui.toolbar = { ui.ownButton, ui.inspectButton, ui.addTab, ui.positionButton, ui.addContent, ui.tabActions }
end

function Editor.Build(ctx, parent, heightChanged)
    local host = CreateFrame("Frame", nil, parent)
    host:Hide()
    host:SetPoint("TOPLEFT", 16, -PREVIEW_TOP)
    host:SetPoint("TOPRIGHT", -16, -PREVIEW_TOP)
    host:SetHeight(1)
    local ui = { ctx = ctx, host = host, heightChanged = heightChanged, tabs = {}, shownTabs = {}, freeTabs = {},
        sample = Sample(), mode = OWN, layers = {}, selectedTabs = {}, overrides = { [OWN] = {}, [INSPECT] = {} } }
    CreateStage(ui)
    CreateRail(ui)
    ui.custom = P.CharacterCustomTabs.Create(ui, function(id)
        local changed = ui.customSelected ~= id
        ui.customSelected, ui.selectedTabs[OWN] = id, id
        if changed and id then ui.overrides[OWN].tabs = nil end
        Refresh(ui)
        if changed then
            if ui.direct and id then ui.direct:SelectTab(id)
            elseif not ui.direct then ui.kit:Select(ui.tabs[id]) end
        end
    end)
    CreateToolbar(ui)
    ui.contentPosition = function(x, y)
        ui.hintGroup = nil
        if x ~= nil then P.SetTranslatedText(ui.hint, P.Tr("Position: X %d, Y %d"):format(x, y))
        else RefreshSelection(ui) end
    end
    host:SetScript("OnShow", function() Refresh(ui) end)
    host:SetScript("OnHide", function()
        ui.kit:Release()
        ui.custom:Cancel()
        if ui.direct then ui.direct:Release() end
        if ui.preview then
            ui.custom:DetachPreview()
            ui.preview:Hide()
        end
    end)
    host:SetScript("OnSizeChanged", function(_, width)
        if ui.width ~= width then
            ui.width = width
            if ui.direct then ui.custom:Cancel() end
            Repaint(ui)
        end
    end)
    M.TrackRefresh(ctx, function() Repaint(ui) end)
    return host
end
