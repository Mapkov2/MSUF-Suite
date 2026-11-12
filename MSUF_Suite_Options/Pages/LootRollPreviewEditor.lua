local _, P = ...
-- The loot roll preview as an element editor in the style of MSUF's unit and
-- group frame previews: every painted part of a sample row is a click target
-- for its exact setting, and a "Preview Layers" rail shows or hides each part.
-- Layer state belongs to this preview only; it never reaches the profile.
local Editor = {}
P.LootRollPreviewEditor = Editor
local S, HM, Interaction, Move = P.S, P.HM, P.PreviewInteraction, P.LootRollPreviewMove
local ID = "lootRolls"
local LAYER_HINT = "Right-click an element to open its section below."
-- { layer key, chip label, setting it opens, frame level above the window target }
local LAYERS = {
    { "rows", "Rows", "look", 0 },
    { "icon", "Icon", "rowHeight", 2 },
    { "name", "Name", "fontSize", 3 },
    { "details", "Details", "showItemLevel", 3 },
    { "result", "Result", "showResults", 3 },
    { "timer", "Countdown", "urgentTimer", 3 },
    { "buttons", "Buttons", "showCounts", 4 },
    { "counts", "Roll counts", "showCounts", 6 },
}
local BY_KEY = {}
for _, layer in ipairs(LAYERS) do BY_KEY[layer[1]] = layer end
Editor.Layers = LAYERS

function Editor.Open(editor, layer)
    if not layer or not editor.ui.stage:IsVisible() then return false end
    return editor.ui.OpenTarget(layer[3])
end

-- Hovering a chip outlines every part of that layer in the preview, as MSUF's
-- frame previews do; hovering a part names its layer on the rail (Move.Light).
local function Spotlight(editor, key, on)
    editor.spotlight = on and key or nil
    Move.Light(editor)
end

-- A plain button until the move controller enrolls it out of combat: mouse,
-- clicks, drag, keys and tooltip are all set there. element: the offsets a
-- drag writes (nil: opens its setting only).
local function NewTarget(editor, host, layer, element)
    local target = CreateFrame("Button", nil, host)
    target.editor, target.layer, target.element = editor, layer, element and Move.Elements[element]
    target._label = target.element and target.element.label or layer[2]
    target:SetFrameLevel(host:GetFrameLevel() + 30 + layer[4])
    target:Hide()
    HM.SkipHistoryCheckpoint(target)
    local list = editor.byLayer[layer[1]]
    list[#list + 1] = target
    editor.targets[#editor.targets + 1] = target
    if element then
        local group = editor.byElement[element]
        group[#group + 1] = target
    end
    return target
end

local function RowTargets(editor, host, index)
    local set = editor.rows[index]
    if set then return set end
    set = { buttons = {}, counts = {}, rows = NewTarget(editor, host, BY_KEY.rows) }
    for _, key in ipairs({ "icon", "name", "details", "result" }) do set[key] = NewTarget(editor, host, BY_KEY[key], key) end
    set.timer = NewTarget(editor, host, BY_KEY.timer, "timer")
    set.remaining = NewTarget(editor, host, BY_KEY.timer, "remaining")
    editor.rows[index] = set
    return set
end

-- A roll count moves with its buttons.
local function ActionTargets(editor, host, set, index)
    local button = set.buttons[index]
    if not button then
        button = NewTarget(editor, host, BY_KEY.buttons, "buttons")
        set.buttons[index] = button
        set.counts[index] = NewTarget(editor, host, BY_KEY.counts, "buttons")
    end
    return button, set.counts[index]
end

-- A target follows its painted region and exists only while that region does.
local function Place(target, region, shown)
    if region and target.region ~= region then
        target:ClearAllPoints()
        target:SetAllPoints(region)
        target.region = region
    end
    target:SetShown(region and shown == true or false)
end

local function PlaceText(target, region, shown)
    shown = shown and region:IsShown() and (region:GetText() or "") ~= ""
    if shown then
        local width = math.min(region:GetStringWidth() or 0, region:GetWidth() or 0)
        target:ClearAllPoints()
        target:SetPoint("LEFT", region, "LEFT", -2, 0)
        target:SetSize(math.max(12, width + 4), math.max(10, (region:GetHeight() or 0) + 4))
        target.region = nil
    end
    target:SetShown(shown == true)
end

local function PlaceTimer(target, bar, shown)
    if target.region ~= bar then
        target:ClearAllPoints()
        target:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, -2)
        target:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -2)
        target:SetHeight(7)
        target.region = bar
    end
    target:SetShown(shown and bar:IsShown())
end

local function BindRow(editor, host, index, row)
    local set, shown = RowTargets(editor, host, index), row and row.frame:IsShown()
    if not shown then
        for key, target in pairs(set) do if key ~= "buttons" and key ~= "counts" then target:Hide() end end
    else
        Place(set.rows, row.frame, row.background:IsShown())
        Place(set.icon, row.item, row.item:IsShown())
        PlaceText(set.name, row.name, true)
        PlaceText(set.details, row.details, true)
        PlaceText(set.result, row.status, true)
        PlaceTimer(set.timer, row.timer, true)
        Place(set.remaining, row.remaining, row.remaining:IsShown())
    end
    for slot = 1, math.max(#set.buttons, shown and #row.actions or 0) do
        local action = shown and row.actions[slot]
        local button, count = ActionTargets(editor, host, set, slot)
        Place(button, action and action.button, action and action.button:IsShown())
        Place(count, action and action.backdrop, action and action.button:IsShown() and action.count:IsShown())
    end
end

-- Hidden layers: only regions the painter showed are hidden and remembered, and
-- Restore shows them again before the next paint, so the painter's own state
-- (the countdown caches whether its bar is shown) never sees the mask.
local function Mask(editor, region)
    if region and region:IsShown() then
        editor.masked[#editor.masked + 1] = region
        region:Hide()
    end
end

function Editor.Restore(editor)
    local masked = editor.masked
    for index = #masked, 1, -1 do
        masked[index]:Show()
        masked[index] = nil
    end
end

local function MaskRow(editor, row)
    local hidden = editor.layers
    if hidden.rows == false then
        Mask(editor, row.background)
        for _, edge in ipairs(row.border) do Mask(editor, edge) end
    end
    if hidden.icon == false then Mask(editor, row.item) end
    if hidden.name == false then Mask(editor, row.name) end
    if hidden.details == false then Mask(editor, row.details) end
    if hidden.result == false then Mask(editor, row.status) end
    if hidden.timer == false then
        Mask(editor, row.timer)
        Mask(editor, row.remaining)
    end
    for _, action in ipairs(row.actions) do
        if hidden.buttons == false then Mask(editor, action.button) end
        if hidden.counts == false then
            Mask(editor, action.count)
            Mask(editor, action.backdrop)
        end
    end
end

-- A layer whose settings paint nothing is shown as unavailable on the rail.
local function Availability(editor, config)
    local available = editor.layerAvailable
    available.details = config.showItemLevel == true or config.showBind == true
    available.counts = config.showCounts == true
end

local function Toggle(editor, key, enabled)
    if not BY_KEY[key] or editor.layerAvailable[key] == false or not editor.ui.stage:IsVisible() then return false end
    editor.layers[key] = enabled == true
    editor.ui.Paint()
    return true
end

local function HookChips(editor)
    for _, chip in ipairs(editor.layerButtons) do
        local layer = BY_KEY[chip.key]
        P.M.AddTooltip(chip, layer[2], LAYER_HINT, { hook = true })
        chip:HookScript("OnEnter", function() Spotlight(editor, layer[1], true) end)
        chip:HookScript("OnLeave", function() Spotlight(editor, layer[1], false) end)
        chip:HookScript("OnHide", function() Spotlight(editor, layer[1], false) end)
    end
end

function Editor.Build(ui, parent, y, width)
    local editor = { ui = ui, layers = {}, layerAvailable = {}, masked = {}, rows = {}, byLayer = {},
        targets = {}, byElement = {} }
    for _, layer in ipairs(LAYERS) do editor.byLayer[layer[1]] = {} end
    for id in pairs(Move.Elements) do editor.byElement[id] = {} end
    ui.lootEditor = editor
    ui.restore = function() Editor.Restore(editor) end
    Availability(editor, S.Config(ID))
    y = Move.Build(editor, parent, y, width)
    y = P.LootRollPreviewProperties.Build(editor, parent, y, width)
    Interaction.BuildLayerRail(editor, parent, LAYERS,
        function(key, enabled) return Toggle(editor, key, enabled) end,
        function(layer) return Editor.Open(editor, layer) end)
    HookChips(editor)
    editor.chips:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    Interaction.LayoutLayerRail(editor, width)
    Interaction.RefreshLayerRail(editor)
    ui.Paint()
    return y - editor.chips:GetHeight() - 8
end

-- Runs after every paint of the sample rows: mask hidden layers, then fit the
-- targets to what is drawn. Rows past the painted count drop theirs, and in
-- combat no target shows (nothing opens or moves until it ends).
function Editor.Bind(ui, view)
    local editor = ui.lootEditor
    if not editor or not view or not view.rows then return end
    Availability(editor, view.config)
    local host, combat = view.host, P.Combat()
    for index = 1, math.max(#editor.rows, view.viewCount or 0) do
        local row = index <= (view.viewCount or 0) and view.rows[index] or nil
        if row and row.frame:IsShown() then MaskRow(editor, row) end
        BindRow(editor, host, index, not combat and row or nil)
    end
    Move.Bind(editor, view)
    Move.Light(editor)
    Interaction.RefreshLayerRail(editor)
end
