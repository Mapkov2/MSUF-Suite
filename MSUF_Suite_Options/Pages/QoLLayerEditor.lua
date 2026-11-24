local _, P = ...
-- The element editor of a Quality of Life preview whose catalog module has
-- layers (MSUF_Suite/Core/Catalog: NS.AddQoLLayers), in the style of MSUF's
-- frame previews: the "Preview Layers" rail shows or hides each layer,
-- right-click opens its settings, and a drag writes its <key>X/<key>Y offsets.
-- A layer marked fixed has no offsets and only selects. The module's runtime
-- draws; spec ties the editor to that drawing:
--   view               the stage field that holds the runtime's preview view
--   region(view, key)  the painted region of a layer
--   move(view, key, x, y)  re-anchors a layer while it is dragged
--   hide(stage)        releases the drawing when the stage hides
--   behind             leading layers under the others for hit tests
--   initial            the layer selected first (default: the first layer)
--   scale(view, region)  the scale of a region drawn at its own (optional)
--   offsets            show the host's exact X/Y controls for movable layers
--   previewLayers      keep layer-rail visibility in the preview
local Interaction = P.PreviewInteraction
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CANVAS = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

-- The layer whose section holds a setting of a layer editor (search reveals
-- that layer instead of a grid the page never builds).
function P.QoLLayerSection(id, section)
    local spec = P.catalog[id]
    for _, layer in ipairs(spec and spec.layers or {}) do
        if layer.section == section then return layer end
    end
end

local function Select(editor, ui, key)
    if ui.openLayerSettings then ui.openLayerSettings(key) end
    if ui.selectedLayer == key then return end
    ui.selectedLayer = key
    for index, layer in ipairs(editor.layers) do
        Interaction.Outline(ui.layerButtons[index], layer[1] == key, 1)
        if ui.layerPanels then ui.layerPanels[layer[1]]:SetShown(layer[1] == key) end
    end
end

local function PreviewConfig(editor, ui, config)
    if not ui.previewLayers then return config end
    if ui.previewSource ~= config then
        ui.previewSource = config
        ui.previewConfig = setmetatable({}, { __index = config })
    end
    local preview = ui.previewConfig
    for _, layer in ipairs(editor.layers) do
        local key = layer[1]
        local visible = ui.previewLayers[key]
        if visible == nil then visible = config[key .. "Shown"] ~= false end
        preview[key .. "Shown"] = visible
    end
    return preview
end

local function Focus(editor, ui, key)
    Select(editor, ui, key)
    if not ui.moves or P.Combat() then return end
    local handle = ui.targets[key]
    ui.moves:Select(handle and handle:IsShown() and handle or nil)
end

local function TrackOffsetInput(ui, input)
    input:HookScript("OnEditFocusGained", function()
        ui.offsetEdit = { input = input, target = ui.moves:Selected(), current = P.ProfileGuard() }
    end)
    input:HookScript("OnEditFocusLost", function()
        if ui.offsetEdit and ui.offsetEdit.input == input then ui.offsetEdit = nil end
    end)
end

local function BuildOffsetBar(editor, ui, parent, y, width)
    local selection = P.M.PreviewSelectionBar
    if not selection then return y end
    local rules = P.catalog[editor.id].rules
    local bar = selection.Create(ui.stage, {
        Tr = P.Tr, Theme = function() return P.T end,
        IsPlaced = function(handle)
            local entry = ui.moves and ui.moves.entries[handle]
            return entry ~= nil and entry.write ~= nil and handle:IsVisible()
        end,
        HandleLabel = function(handle) return handle.label end,
        ReadOffsets = function(_, handle) return ui.moves.entries[handle].read() end,
        WriteOffsets = function(_, handle, x, offsetY)
            local edit = ui.offsetEdit
            if edit and (edit.target ~= handle or not edit.current()) then return false end
            return ui.moves.entries[handle].write(x, offsetY)
        end,
        NudgeDelta = function(_, dx, dy) return ui.moves:Nudge(dx, dy) end,
        DefaultOffsets = function(_, handle)
            return rules[handle.layer .. "X"].default, rules[handle.layer .. "Y"].default
        end,
        OpenSettings = function(_, handle) return ui.OpenTarget(handle.layer .. "Shown") end,
    })
    bar:SetParent(parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    Interaction.LayoutSelectionBar(bar, width)
    TrackOffsetInput(ui, bar.editX)
    TrackOffsetInput(ui, bar.editY)
    ui.offsetBar = bar
    return y - bar:GetHeight() - 8
end

local function BuildRail(editor, ui, parent, y, width)
    local id = editor.id
    ui.stage:SetBackdrop(CANVAS)
    ui.stage:SetBackdropColor(.05, .07, .10, .8)
    ui.stage:SetBackdropBorderColor(unpack(P.T.colors.border))
    ui.layers = {}
    if editor.spec.previewLayers then ui.previewLayers = {} end
    Interaction.BuildLayerRail(ui, parent, editor.layers, function(key, enabled)
        if ui.previewLayers then
            ui.previewLayers[key], ui.layers[key] = enabled, enabled
            ui.Paint()
            return true
        end
        if P.Combat() then return false end
        Focus(editor, ui, key)
        local ok = P.Set(id, key .. "Shown", enabled)
        if ok then ui.Paint() end
        return ok
    end, function(layer)
        Focus(editor, ui, layer[1])
        return true
    end)
    ui.chips:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    Interaction.LayoutLayerRail(ui, width)
    Select(editor, ui, editor.spec.initial or editor.layers[1][1])
    y = y - ui.chips:GetHeight() - 8
    if editor.spec.offsets then y = BuildOffsetBar(editor, ui, parent, y, width) end
    return y
end

local function BuildProperties(editor, ui, parent, y, width, page, section, register)
    local height = 0
    ui.layerPanels = {}
    for _, layer in ipairs(editor.layers) do
        local key, label = layer[1], layer[2]
        local panel = CreateFrame("Frame", nil, parent)
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        panel:SetWidth(width + 32)
        local title = P.Text(panel, label, 16, 0, width, P.T.colors.text)
        local top = -math.max(16, math.ceil(title:GetStringHeight() or 16)) - 6
        local bottom, entries = P.RuleGrid(ui.ctx, panel, page, editor.id, layer.rules, top, width,
            nil, section, nil, nil, true)
        register(entries, function() Focus(editor, ui, key) end)
        panel:SetHeight(-bottom)
        panel:SetShown(ui.selectedLayer == key)
        ui.layerPanels[key] = panel
        height = math.max(height, -bottom)
    end
    return y - height - 8
end

local function NewController(editor, ui)
    local controller = Interaction.Handles({ frame = ui.stage, Paint = ui.Paint }, {
        owner = ui.stage, keys = false, keep = true, manualDrag = true, pointerHeld = IsMouseButtonDown and function()
            return IsMouseButtonDown("LeftButton")
        end,
        rekey = true,
        combat = function() return P.Combat() or not ui.stage:IsVisible() end,
        select = function(handle)
            if handle then Select(editor, ui, handle.layer) end
            if ui.offsetBar then P.M.PreviewSelectionBar.Refresh(ui.stage) end
        end,
        mark = function(handle, selected)
            Interaction.Outline(handle, selected)
            handle:SetFrameLevel(handle.level + (selected and 10 or 0))
        end,
    })
    if ui.offsetBar then
        local select = controller.Select
        function controller:Select(handle)
            if ui.offsetEdit and handle ~= self:Selected() then ui.offsetEdit.input:ClearFocus() end
            return select(self, handle)
        end
    end
    return controller
end

local function AddTarget(editor, ui, host, view, layer, priority)
    local id, key = editor.id, layer[1]
    local target = CreateFrame("Button", nil, host)
    target.layer, target.label, target.level = key, layer[2], host:GetFrameLevel() + priority
    target:SetFrameLevel(target.level)
    target:Hide()
    P.HM.SkipHistoryCheckpoint(target)
    local xKey, yKey = key .. "X", key .. "Y"
    local rules = P.catalog[id].rules
    local function Read() return P.Get(id, xKey) or 0, P.Get(id, yKey) or 0 end
    local function Write(x, y)
        if P.Combat() or not ui.stage:IsVisible() or not target:IsShown() then return false end
        x = math.min(rules[xKey].max, math.max(rules[xKey].min, math.floor(x + .5)))
        y = math.min(rules[yKey].max, math.max(rules[yKey].min, math.floor(y + .5)))
        local oldX, oldY = Read()
        if oldX == x and oldY == y then return false end
        return P.SetMany(id, { [xKey] = x, [yKey] = y })
    end
    local function Follow(_, dx, dy)
        local x, y = Read()
        editor.spec.move(view, key, x + dx, y + dy)
    end
    local movable = layer.fixed ~= true
    ui.moves:Add(key, target, Read, movable and Write or nil, {
        follow = movable and Follow or nil, scale = function() return host:GetEffectiveScale() end,
    })
    if movable and ui.offsetBar then
        target:SetScript("OnKeyDown", function(frame, pressed)
            if not P.Combat() then return ui.moves:Key(frame, pressed) end
        end)
    end
    ui.targets[key] = target
    return target
end

-- Fit the whole drawing, including layers dragged beyond it. Convert
-- scaled frame rectangles to stage coordinates before computing the bounds.
local function Fit(editor, ui, host, view)
    local stageScale, hostScale = ui.stage:GetEffectiveScale(), host:GetEffectiveScale()
    local cx, cy = host:GetCenter()
    if not cx then return end
    cx, cy = cx * hostScale, cy * hostScale
    local x, y = host:GetWidth() * hostScale / 2, host:GetHeight() * hostScale / 2
    local spec = editor.spec
    for _, layer in ipairs(editor.layers) do
        local region = spec.region(view, layer[1])
        if region and region:IsShown() then
            local left, bottom, width, height = region:GetRect()
            if left then
                local scale = spec.scale and spec.scale(view, region) or hostScale
                x = math.max(x, math.abs(left * scale - cx), math.abs((left + width) * scale - cx))
                y = math.max(y, math.abs(bottom * scale - cy), math.abs((bottom + height) * scale - cy))
            end
        end
    end
    local fit = math.min(1, (ui.width - 20) * stageScale / (2 * x), (ui.height - 20) * stageScale / (2 * y))
    if fit < 1 then host:SetScale(host:GetScale() * fit) end
end

local function SyncTarget(editor, ui, host, view, layer, index)
    local key = layer[1]
    -- Text and icons win hit tests over the larger layers behind them.
    local priority = index <= editor.spec.behind and index or 18 + index
    local target = ui.targets[key] or AddTarget(editor, ui, host, view, layer, priority)
    local region = editor.spec.region(view, key)
    if target.region ~= region then
        target:ClearAllPoints()
        if region then target:SetAllPoints(region) end
        target.region = region
    end
    target:SetShown(region ~= nil and region:IsShown())
end

local function Bind(editor, ui, host, view, config)
    if not ui.moves then ui.moves = NewController(editor, ui) end
    Fit(editor, ui, host, view)
    for index, layer in ipairs(editor.layers) do
        ui.layers[layer[1]] = config[layer[1] .. "Shown"] ~= false
        SyncTarget(editor, ui, host, view, layer, index)
    end
    Interaction.RefreshLayerRail(ui)
    local selected = ui.moves:Selected()
    if selected and not selected:IsShown() then ui.moves:Select(nil) end
    if ui.offsetBar then P.M.PreviewSelectionBar.Refresh(ui.stage) end
end

local function Release(editor, ui)
    if not ui.moves then return end
    ui.moves:Release()
    editor.spec.hide(ui.stage)
end

-- The editor of one module: QualityOfLifePreview.lua calls these as
-- editor.BuildRail(ui, ...), editor.BuildProperties(ui, ...),
-- editor.Bind(ui, host, ui.stage[editor.view], config) and editor.Release(ui).
function P.QoLLayerEditor(id, spec)
    local editor = { id = id, spec = spec, view = spec.view, layers = P.catalog[id].layers }
    editor.BuildRail = function(...) return BuildRail(editor, ...) end
    editor.BuildProperties = function(...) return BuildProperties(editor, ...) end
    editor.PreviewConfig = function(...) return PreviewConfig(editor, ...) end
    editor.Bind = function(...) return Bind(editor, ...) end
    editor.Release = function(...) return Release(editor, ...) end
    return editor
end
