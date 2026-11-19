local _, P = ...
local Editor = {}
P.BattleResEditor = Editor
local ID = "battleRes"
local S, Interaction = P.S, P.PreviewInteraction
local layers = P.catalog[ID].layers
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CANVAS = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

local function Select(ui, key)
    if ui.selectedLayer == key then return end
    ui.selectedLayer = key
    for index, layer in ipairs(layers) do
        Interaction.Outline(ui.layerButtons[index], layer[1] == key, 1)
        if ui.layerPanels then ui.layerPanels[layer[1]]:SetShown(layer[1] == key) end
    end
end

local function Focus(ui, key)
    Select(ui, key)
    if not ui.moves then return end
    local handle = ui.targets[key]
    ui.moves:Select(handle and handle:IsShown() and handle or nil)
end

function Editor.BuildRail(ui, parent, y, width)
    ui.stage:SetBackdrop(CANVAS)
    ui.stage:SetBackdropColor(.05, .07, .10, .8)
    ui.stage:SetBackdropBorderColor(unpack(P.T.colors.border))
    ui.layers = {}
    Interaction.BuildLayerRail(ui, parent, layers, function(key, enabled)
        if P.Combat() then return false end
        Focus(ui, key)
        local ok = P.Set(ID, key .. "Shown", enabled)
        if ok then ui.Paint() end
        return ok
    end, function(layer)
        Focus(ui, layer[1])
        return true
    end)
    ui.chips:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    Interaction.LayoutLayerRail(ui, width)
    Select(ui, "background")
    return y - ui.chips:GetHeight() - 8
end

function Editor.BuildProperties(ui, parent, y, width, page, section, register)
    local height = 0
    ui.layerPanels = {}
    for _, layer in ipairs(layers) do
        local key, label = layer[1], layer[2]
        local panel = CreateFrame("Frame", nil, parent)
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        panel:SetWidth(width + 32)
        local title = P.Text(panel, label, 16, 0, width, P.T.colors.text)
        local top = -math.max(16, math.ceil(title:GetStringHeight() or 16)) - 6
        local bottom, entries = P.RuleGrid(ui.ctx, panel, page, ID, layer.rules, top, width,
            nil, section, nil, nil, true)
        register(entries, function() Focus(ui, key) end)
        panel:SetHeight(-bottom)
        panel:SetShown(ui.selectedLayer == key)
        ui.layerPanels[key] = panel
        height = math.max(height, -bottom)
    end
    return y - height - 8
end

local function NewController(ui)
    return Interaction.Handles({ frame = ui.stage, Paint = ui.Paint }, {
        owner = ui.stage, keys = false, keep = true, manualDrag = true, pointerHeld = IsMouseButtonDown and function()
            return IsMouseButtonDown("LeftButton")
        end,
        rekey = true,
        select = function(handle) if handle then Select(ui, handle.layer) end end,
        mark = function(handle, selected)
            Interaction.Outline(handle, selected)
            handle:SetFrameLevel(handle.level + (selected and 10 or 0))
        end,
    })
end

local function AddTarget(ui, host, view, key, priority)
    local target = CreateFrame("Button", nil, host)
    target.layer, target.level = key, host:GetFrameLevel() + priority
    target:SetFrameLevel(target.level)
    target:Hide()
    P.HM.SkipHistoryCheckpoint(target)
    local xKey, yKey = key .. "X", key .. "Y"
    local rules = P.catalog[ID].rules
    local function Read() return P.Get(ID, xKey), P.Get(ID, yKey) end
    local function Write(x, y)
        x = math.min(rules[xKey].max, math.max(rules[xKey].min, math.floor(x + .5)))
        y = math.min(rules[yKey].max, math.max(rules[yKey].min, math.floor(y + .5)))
        local oldX, oldY = Read()
        if oldX == x and oldY == y then return false end
        return P.SetMany(ID, { [xKey] = x, [yKey] = y })
    end
    local function Follow(_, dx, dy)
        local x, y = Read()
        S.MoveBattleResPreviewLayer(view, key, x + dx, y + dy)
    end
    ui.moves:Add(key, target, Read, Write, {
        follow = Follow, scale = function() return host:GetEffectiveScale() end,
    })
    ui.targets[key] = target
    return target
end

local function Region(view, key)
    if key == "background" then return view.panel end
    if key == "border" then return view.borderBounds end
    if key == "timer" then return view.compact and view.time or view.cooldown end
    return view[key]
end

-- Fit the whole drawing, including layers dragged beyond the card. Convert
-- scaled frame rectangles to stage coordinates before computing the bounds.
local function Fit(ui, host, view)
    local stageScale, hostScale = ui.stage:GetEffectiveScale(), host:GetEffectiveScale()
    local cx, cy = host:GetCenter()
    if not cx then return end
    cx, cy = cx * hostScale, cy * hostScale
    local x, y = host:GetWidth() * hostScale / 2, host:GetHeight() * hostScale / 2
    for _, layer in ipairs(layers) do
        local region = Region(view, layer[1])
        if region:IsShown() then
            local left, bottom, width, height = region:GetRect()
            if left then
                local scale = region == view.cooldown and region:GetEffectiveScale() or hostScale
                x = math.max(x, math.abs(left * scale - cx), math.abs((left + width) * scale - cx))
                y = math.max(y, math.abs(bottom * scale - cy), math.abs((bottom + height) * scale - cy))
            end
        end
    end
    local fit = math.min(1, (ui.width - 20) * stageScale / (2 * x), (ui.height - 20) * stageScale / (2 * y))
    if fit < 1 then host:SetScale(host:GetScale() * fit) end
end

local function SyncTarget(ui, host, view, layer, index)
    local key = layer[1]
    -- Text and the icon win hit tests over the larger background and border.
    local priority = index < 3 and index or 18 + index
    local target = ui.targets[key] or AddTarget(ui, host, view, key, priority)
    local region = Region(view, key)
    if target.region ~= region then
        target:ClearAllPoints()
        target:SetAllPoints(region)
        target.region = region
    end
    target:SetShown(region:IsShown())
end

function Editor.Bind(ui, host, view, config)
    if not ui.moves then ui.moves = NewController(ui) end
    Fit(ui, host, view)
    for index, layer in ipairs(layers) do
        ui.layers[layer[1]] = config[layer[1] .. "Shown"] ~= false
        SyncTarget(ui, host, view, layer, index)
    end
    Interaction.RefreshLayerRail(ui)
    local selected = ui.moves:Selected()
    if selected and not selected:IsShown() then ui.moves:Select(nil) end
end

function Editor.Release(ui)
    if not ui.moves then return end
    ui.moves:Release()
    S.HideBattleResPreview(ui.stage)
end
