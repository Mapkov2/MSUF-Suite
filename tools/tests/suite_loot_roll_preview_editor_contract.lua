-- The loot roll preview editor over the real painter, the real shared layer
-- rail and the real QoL preview: exact click targets per row element, preview-
-- only layers (no profile writes), availability, hover sync and lifecycle.
local root = assert(arg[1], "repository root required")
local created = 0
-- Keyboard input calls are restricted in combat lockdown (EnableKeyboard is a
-- protected function, SetPropagateKeyboardInput has restrictions): any such
-- call while `lockdown` is set fails the contract.
local lockdown = false
local function Unlocked(name) assert(not lockdown, name .. " called during combat lockdown") end

local Widget
local function Fire(widget, script, ...)
    if widget.scripts[script] then widget.scripts[script](widget, ...) end
    for _, hook in ipairs(widget.hooks[script] or {}) do hook(widget, ...) end
end

local function FireHide(widget)
    Fire(widget, "OnHide")
    for _, child in ipairs(widget.children) do
        if child.shown then FireHide(child) end
    end
end

local everyWidget = {}
Widget = function(parent, kind)
    created = created + 1
    local w = { parent = parent, kind = kind or "Frame", shown = true, scripts = {}, hooks = {}, points = {},
        children = {}, width = 0, height = 0, scale = 1, text = "" }
    if parent then parent.children[#parent.children + 1] = w end
    everyWidget[#everyWidget + 1] = w
    function w:SetScript(event, callback) self.scripts[event] = callback end
    function w:GetScript(event) return self.scripts[event] end
    function w:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function w:ClearAllPoints() self.points = {} end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:SetAllPoints(region) self.allPoints = region end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetWidth(width) self.width = width end
    function w:SetHeight(height) self.height = height end
    function w:GetWidth() return self.width end
    function w:GetHeight() return self.height end
    function w:SetScale(scale) self.scale = scale end
    function w:GetScale() return self.scale end
    function w:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function w:SetFrameStrata() end
    function w:SetFrameLevel(level) self.level = level end
    function w:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel() + 1 or 0) end
    function w:EnableMouse(mouse) self.mouse = mouse end
    function w:RegisterForClicks(...) self.clicks = { ... } end
    function w:EnableKeyboard(enabled) Unlocked("EnableKeyboard") self.keyboard = enabled end
    function w:SetPropagateKeyboardInput(value) Unlocked("SetPropagateKeyboardInput") self.propagate = value end
    function w:SetMovable(value) self.movable = value end
    function w:RegisterForDrag() self.nativeDrag = true end
    function w:GetNumPoints() return #self.points end
    function w:GetPoint(index) return unpack(self.points[index or 1]) end
    function w:IsObjectType(kind) return self.kind == kind end
    function w:SetParent(parent) self.parent = parent end
    function w:SetEnabled(enabled) self.enabled = enabled end
    function w:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function w:Show()
        local was = self.shown
        self.shown = true
        if not was then Fire(self, "OnShow") end
    end
    function w:Hide()
        local visible = self:IsVisible()
        self.shown = false
        if visible then FireHide(self) end
    end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:SetText(text) self.text = text end
    function w:GetText() return self.text end
    function w:GetStringWidth() return #tostring(self.text or "") * 6 end
    function w:GetUnboundedStringWidth() return #tostring(self.text or "") * 6 end
    function w:GetStringHeight() return 16 end
    function w:CreateTexture() return Widget(self, "Texture") end
    function w:CreateFontString() return Widget(self, "FontString") end
    function w:SetClipsChildren() end
    function w:RegisterEvent() end
    function w:UnregisterAllEvents() end
    for _, name in ipairs({ "SetValue", "SetTexCoord", "SetColorTexture", "SetTexture", "SetAtlas", "SetAlpha",
        "SetJustifyH", "SetWordWrap", "SetTextColor", "SetStatusBarColor", "SetStatusBarTexture", "SetMinMaxValues",
        "SetOrientation" }) do
        w[name] = function(self, value) self["value" .. name] = value end
    end
    return w
end

UIParent = Widget()
CreateFrame = function(kind, _, parent) return Widget(parent, kind) end
GetTime = function() return 100 end
ITEM_QUALITY_COLORS = { [3] = { r = 0, g = .44, b = .87 }, [4] = { r = .64, g = .21, b = .93 } }
GameTooltip = Widget()
function GameTooltip:IsOwned() return false end
local cursorX, cursorY, mouseDown, focus = 0, 0, false, nil
GetCursorPosition = function() return cursorX, cursorY end
IsMouseButtonDown = function() return mouseDown end
IsControlKeyDown = function() return false end
IsShiftKeyDown, IsAltKeyDown = IsControlKeyDown, IsControlKeyDown
GetCurrentKeyBoardFocus = function() return focus end
InCombatLockdown = function() return lockdown end
wipe = function(list) for key in pairs(list) do list[key] = nil end return list end

-- The real loot roll catalog: rules, offset elements and defaults.
local catalog, B = { SuiteCatalog = {}, Text = function(text) return text end, AnchorLabels = { "Center" } }, {}
local function Rule(key, label, default, minimum, maximum)
    return { key = key, label = label, default = default, min = minimum, max = maximum }
end
B.Number = Rule
function B.Bool(key, label, default) return Rule(key, label, default == true) end
function B.Choice(key, label, default) return Rule(key, label, default) end
function B.Font(key, label) return Rule(key, label, "") end
function B.Module(id) catalog.SuiteCatalog[id] = { rules = {} } end
function B.Add(id, rule) catalog.SuiteCatalog[id].rules[rule.key] = rule end
function B.Section(id, _, _, list) for _, rule in ipairs(list) do B.Add(id, rule) end end
catalog.CatalogBuild = { ForAddon = function() return B end }
catalog.AddQoLVisualStyle = function(id) B.Add(id, Rule("look", "MSUF style", 1)) end
catalog.AddQoLTextStyle = function() end
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/LootRolls.lua"))("MSUF_Suite", catalog)
local rules = catalog.SuiteCatalog.lootRolls.rules
local config = {}
for key, rule in pairs(rules) do config[key] = rule.default end
for _, element in ipairs(catalog.LootRollElements) do
    local x, y = rules[element.xKey], rules[element.yKey]
    assert(x.hidden and y.hidden and x.default == 0 and y.default == 0 and x.min == -200 and y.max == 200,
        "offset rules must be hidden, start at 0 and stay in range: " .. element.id)
    local size = rules[element.sizeKey]
    assert(size and not size.hidden and size.lootElement == element.id and size.default == 0 and size.min == 0
        and size.max == element.maxSize, "size rule must start automatic and belong to its element: " .. element.id)
end
local function Snapshot()
    local copy = {}
    for key, value in pairs(config) do copy[key] = value end
    return copy
end
local function Same(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

local function RGB() return .1, .1, .1 end
local Suite = {
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(text) return text end,
    CreateFrame = function(_, _, parent) return Widget(parent, "Frame") end,
    CreateTexture = function(parent) return Widget(parent, "Texture") end,
    CreateFontString = function(parent) return Widget(parent, "FontString") end,
    ResolveFont = function() return "Fonts\\FRIZQT__.TTF" end,
    GlobalFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
    RGB = RGB, QoLStyle = function() return {} end, QoLStyleText = function(region, _, _, size) region.fontSize = size end,
    QoLColor = function() end, PlaceEdges = function() end, Install = function() end,
    Config = function(id) assert(id == "lootRolls") return config end,
    Client = { isForever = false }, GlossMaterial = { Available = function() return true end },
    IsSecret = function() return false end, Number = function(value) return type(value) == "number" end,
    LootRollElements = catalog.LootRollElements,
}
assert(loadfile(root .. "/MSUF_Suite/Core/PreviewKit.lua"))("MSUF_Suite", Suite)
local qol = { NS = { AnchorPoints = { "CENTER" }, AnchorLabels = {} }, Suite = Suite, LootRollData = {} }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootRollView.lua"))("MSUF_Suite_QualityOfLife", qol)
local loadedRuntime = false
C_AddOns = { LoadAddOn = function(name)
    assert(name == "MSUF_Suite_QualityOfLife" and not loadedRuntime)
    loadedRuntime = true
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootRolls.lua"))("MSUF_Suite_QualityOfLife", qol)
end }

local combat, opened, tooltips, writes, profile = false, nil, {}, 0, 1
-- The host's X/Y bar, recorded: its deps are the preview's whole contract.
local barDeps
local SelectionBar = {
    Create = function(box, deps)
        barDeps = deps
        local bar = Widget(box)
        for _, key in ipairs({ "swatch", "label", "axisX", "axisY", "openButton", "resetButton" }) do bar[key] = Widget(bar) end
        bar.editX, bar.editY = Widget(bar, "EditBox"), Widget(bar, "EditBox")
        return bar
    end,
    Refresh = function() end,
    CycleHandle = function(box, backwards)
        local list, selected = barDeps.HandleList(), box._selectedHandle
        local index = 0
        for position, target in ipairs(list) do if target == selected then index = position end end
        index = backwards and (index <= 1 and #list or index - 1) or (index >= #list and 1 or index + 1)
        return barDeps.SelectHandle(nil, list[index])
    end,
}
local P = {
    S = Suite, Suite = Suite, Gates = {}, Tr = function(text) return text end,
    Combat = function() return combat end,
    T = { colors = { accent = { 1, .8, .2 }, border = { .1, .1, .1 }, text = { 1, 1, 1 }, muted = { .6, .6, .6 } },
        Font = function(parent, _, text) local label = Widget(parent, "FontString") label.text = text return label end,
        Button = function(parent, label, width, height)
            local button = Widget(parent, "Button")
            button.label, button.width, button.height = label, width, height
            return button
        end },
    Text = function(parent, text) local label = Widget(parent, "FontString") label.text = text return label end,
    SetTranslatedText = function(label, text) label.text = text end,
    HM = { SkipHistoryCheckpoint = function(widget) widget.noHistory = true end,
        SetCommandAction = function(widget, spec) widget.command = spec end,
        SetSearchTargetPrepare = function(widget, prepare) widget.prepare = prepare end },
    -- The real setting rows, recorded: one control per rule, as W.SettingsRows makes them.
    RuleGrid = function(ctx, parent, page, id, list, y, width, _, section, _, _, editWhileOff)
        assert(ctx and page == "suite_qualityOfLife" and id == "lootRolls" and section and editWhileOff == true)
        local entries = {}
        for index, rule in ipairs(list) do
            local control = Widget(parent, "Slider")
            control.rule = rule
            entries[index] = { rule = rule, widget = control }
        end
        return y - 58 * #list, entries
    end,
    SetMany = function(id, values)
        assert(id == "lootRolls" and not combat, "profile write in combat")
        writes = writes + 1
        for key, value in pairs(values) do config[key] = value end
        return true
    end,
    ProfileGuard = function()
        local token = profile
        return function() return profile == token end
    end,
    M = { AddTooltip = function(widget, title, text) tooltips[widget] = { title, text } end,
        PreviewSelectionBar = SelectionBar,
        RegisterSearchWidget = function(widget, meta) widget.searchMeta = meta end,
        TrackRefresh = function(ctx, callback) ctx.refresh[#ctx.refresh + 1] = callback end,
        SearchBridge = { OpenSearchTarget = function(page, _, _, _, _, exact)
            assert(page == "suite_qualityOfLife")
            opened = exact.settingKey
            return true, true, true
        end } },
    QoLView = { FindFeature = function(id) return { id = id } end,
        GetFeaturePage = function() return "suite_qualityOfLife" end,
        FeatureSectionId = function() return "suite_qualityOfLife_lootRolls" end },
    Meta = function(_, id, key) return { settingKey = "msufsuite." .. id .. "." .. key } end,
    catalog = catalog.SuiteCatalog,
    XPBarPreviewEditor = { Bind = function() error("XP editor bound to the loot preview") end },
}
for _, file in ipairs({ "Menu/PreviewCanvas.lua", "Menu/PreviewInteraction.lua", "Pages/LootRollPreviewMove.lua",
    "Pages/LootRollPreviewProperties.lua", "Pages/LootRollPreviewEditor.lua", "Pages/QualityOfLifePreview.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Options/" .. file))("MSUF_Suite_Options", P)
end

local function Click(widget, mouse)
    return widget.scripts.OnClick(widget, mouse or "LeftButton")
end
local function Opens(target, key, message)
    opened = nil
    assert(target:IsShown(), message .. ": target hidden")
    Click(target)
    assert(opened == "msufsuite.lootRolls." .. key, message .. ": opened " .. tostring(opened))
end

local before = Snapshot()
local ctx, page = { refresh = {} }, Widget(UIParent)
local bottom = P.BuildQoLIndicatorPreview(ctx, page, "lootRolls", 720, -42)
local ui = assert(ctx.qolIndicatorPreviews.lootRolls)
local editor, view = assert(ui.lootEditor, "loot preview has no editor"), assert(ui.stage.suiteLootRollPreview)
assert(view.viewCount == 3 and #editor.rows == 3, "sample rows did not get targets")
assert(#editor.layerButtons == #P.LootRollPreviewEditor.Layers and editor.chips.shown, "layer rail missing")
assert(editor.chips.points[1][5] < -42 - ui.height and bottom < editor.chips.points[1][5] - editor.chips.height,
    "layer rail overlaps the stage or the settings below")

-- Every painted element opens its own setting; the window keeps the gap target.
local first, last = editor.rows[1], editor.rows[3]
Opens(ui.targets.width, "width", "window")
Opens(first.rows, "look", "row background")
Opens(first.icon, "rowHeight", "item icon")
Opens(first.name, "fontSize", "item name")
Opens(first.details, "showItemLevel", "item details")
Opens(first.timer, "urgentTimer", "countdown bar")
Opens(first.remaining, "urgentTimer", "countdown seconds")
assert(not first.result:IsShown(), "an open roll showed a result target")
Opens(last.result, "showResults", "result text")
assert(not last.timer:IsShown() and not last.buttons[1]:IsShown(), "finished roll kept roll targets")
local counted = 0
for slot, action in ipairs(view.rows[1].actions) do
    local shown = action.button:IsShown()
    assert(first.buttons[slot]:IsShown() == shown, "button target does not follow its button")
    if shown then
        Opens(first.buttons[slot], "showCounts", "roll button")
        if action.count:IsShown() then
            counted = counted + 1
            Opens(first.counts[slot], "showCounts", "roll count")
            assert(first.counts[slot]:GetFrameLevel() > first.buttons[slot]:GetFrameLevel())
        end
    end
end
assert(counted == 3, "sample Need, Greed and Pass counts lack targets")
assert(first.buttons[5]:GetFrameLevel() > first.rows:GetFrameLevel()
    and first.rows:GetFrameLevel() > ui.targets.width:GetFrameLevel(), "targets are stacked wrongly")
assert(tooltips[first.name][1] == "Font size", "target tooltip does not name its setting")
assert(tooltips[first.name][2]:find("Drag", 1, true) and not tooltips[first.rows][2]:find("Drag", 1, true),
    "move hint on the wrong targets")
assert(editor.kit:Selected() and Same(before, config), "a click did not select or wrote to the profile")
editor.kit:Release()

-- Layers are local to the preview: no profile write, painter state survives.
local chips = {}
for _, chip in ipairs(editor.layerButtons) do chips[chip.key] = chip end
local row = view.rows[1]
Click(chips.name)
assert(editor.layers.name == false and not row.name:IsShown() and not first.name:IsShown(), "name layer stayed")
Click(chips.name)
assert(row.name:IsShown() and first.name:IsShown(), "name layer did not return")
Click(chips.timer)
ui.Paint()
assert(not row.timer:IsShown() and not row.remaining:IsShown() and not first.timer:IsShown(), "timer layer stayed")
Click(chips.timer)
assert(row.timer:IsShown() and row.remaining:IsShown() and first.timer:IsShown(),
    "showing the countdown layer again left the cached painter bar hidden")
Click(chips.rows)
assert(not row.background:IsShown() and not first.rows:IsShown() and ui.targets.width:IsShown())
Click(chips.rows)
assert(row.background:IsShown() and first.rows:IsShown())
assert(chips.icon.command.set(false) and not row.item:IsShown() and chips.icon.command.get() == false)
assert(chips.icon.command.set(true) and row.item:IsShown())
opened = nil
Click(chips.counts, "RightButton")
assert(opened == "msufsuite.lootRolls.showCounts", "right-click did not open the layer setting")
assert(Same(before, config), "a preview layer or target changed the profile")

-- A layer whose settings paint nothing is unavailable and refuses to toggle.
config.showCounts = false
ui.Paint()
assert(editor.layerAvailable.counts == false and not first.counts[1]:IsShown())
assert(chips.counts.command.set(false) == false and editor.layers.counts == nil, "unavailable layer toggled")
config.showCounts, config.showItemLevel, config.showBind = true, false, false
ui.Paint()
assert(editor.layerAvailable.details == false and editor.layerAvailable.counts == true and not first.details:IsShown())
config.showItemLevel, config.showBind = true, true
ui.Paint()

-- Hover names the layer on the rail; another target hiding keeps that mark.
Fire(first.name, "OnEnter")
assert(editor._msuf2SelectedPreviewLayerKey == "name" and first.name._suitePreviewSelectionEdges.selected)
first.icon:Hide()
assert(editor._msuf2SelectedPreviewLayerKey == "name", "an unrelated hidden target cleared the hover mark")
Fire(first.name, "OnLeave")
assert(editor._msuf2SelectedPreviewLayerKey == nil and not first.name._suitePreviewSelectionEdges.selected)
ui.Paint()
Fire(chips.buttons, "OnEnter")
ui.Paint()
assert(first.buttons[5]._suitePreviewSelectionEdges.selected, "chip hover did not outline its elements")
Fire(chips.buttons, "OnLeave")
assert(not first.buttons[5]._suitePreviewSelectionEdges.selected, "chip outline stayed")

-- Warm paints allocate nothing; fewer rows drop their targets.
local warm = created
ui.Paint()
ui.Paint()
assert(created == warm, "warm paint created frames")
config.maxRows = 2
ui.Paint()
assert(view.viewCount == 2 and not last.rows:IsShown() and not last.result:IsShown(), "unpainted row kept targets")
config.maxRows = 6
ui.Paint()
assert(last.rows:IsShown() and last.result:IsShown())

-- Moving: a drag follows in every row and writes once, on release.
local rows = view.rows
local function NameAt(index) return rows[index].name.points[1][4], rows[index].name.points[1][5] end
local start = {}
for index = 1, 3 do start[index] = { NameAt(index) } end
local writesBefore = writes
cursorX, cursorY, mouseDown = 100, 100, true
Fire(first.name, "OnMouseDown", "LeftButton")
assert(editor.kit:Selected() == first.name and editor.claim, "press did not select and claim the name")
assert(ui.stage.keyboard == true, "selection did not take the arrow and Tab keys")
cursorX, cursorY = 112, 93
Fire(first.name, "OnUpdate")
for index = 1, 3 do
    local x, y = NameAt(index)
    assert(x == start[index][1] + 12 and y == start[index][2] - 7, "row " .. index .. " name did not follow the drag")
end
assert(writes == writesBefore and config.nameOffsetX == 0, "a drag wrote before release")
assert(rows[2].name.points[1][4] and editor.rows[2].name._suitePreviewSelectionEdges.selected,
    "the selected element is not outlined in every row")
mouseDown = false
Fire(first.name, "OnMouseUp", "LeftButton")
opened = nil
Click(first.name)
assert(writes == writesBefore + 1 and config.nameOffsetX == 12 and config.nameOffsetY == -7, "release did not write once")
assert(opened == nil and editor.claim == nil, "a finished drag also opened the settings or kept its claim")
assert(NameAt(2) == start[2][1] + 12, "the repaint lost the moved name")
assert(editor.kit:Arrow(1, 0) and config.nameOffsetX == 13 and config.nameOffsetY == -7, "arrow did not nudge")
-- A drag into another profile than its own never commits.
cursorX, cursorY, mouseDown = 0, 0, true
Fire(first.icon, "OnMouseDown", "LeftButton")
cursorX = 20
Fire(first.icon, "OnUpdate")
profile = profile + 1
mouseDown = false
Fire(first.icon, "OnMouseUp", "LeftButton")
assert(config.iconOffsetX == 0 and editor.claim == nil, "a drag committed into a profile it did not begin in")

-- The X/Y bar: one entry per element, clamped writes, reset, no stray commit.
assert(editor.bar and barDeps, "no X/Y bar")
local names = {}
for index, target in ipairs(barDeps.HandleList()) do names[index] = target._label end
assert(table.concat(names, ",") == "Icon,Name,Details,Result,Remaining time,Timer bar,Buttons", table.concat(names, ","))
assert(barDeps.WriteOffsets(ui.stage, first.details, 999, -4) and config.detailsOffsetX == 200
    and config.detailsOffsetY == -4, "bar write was not clamped to the rule")
assert(barDeps.ResetOffsets(ui.stage, first.details) and config.detailsOffsetX == 0 and config.detailsOffsetY == 0)
assert(barDeps.WriteOffsets(ui.stage, first.rows, 4, 4) == false, "rows moved")
assert(barDeps.ReadOffsets(ui.stage, first.name) == 13)
editor.kit:Select(first.name)
local typedFor
function editor.bar.editX:ClearFocus()
    typedFor = editor.kit:Selected()
    focus = nil
end
focus = editor.bar.editX
editor.kit:Select(first.icon)
assert(typedFor == first.name and editor.kit:Selected() == first.icon, "typed X/Y text went to the new selection")
assert(ui.stage.scripts.OnKeyDown(ui.stage, "TAB") and editor.kit:Selected().element.id == "name", "Tab did not cycle")
assert(ui.stage.scripts.OnKeyDown(ui.stage, "ESCAPE") and editor.kit:Selected() == nil, "Escape kept the selection")
barDeps.ResetOffsets(ui.stage, first.name)
assert(config.nameOffsetX == 0 and Same(before, config), "offsets did not return to the defaults")

-- Sizes: the selected element shows its own size row; the grid leaves them out.
local Properties = P.LootRollPreviewProperties
local function SizeShown()
    local shown
    for id, body in pairs(editor.sizeViews) do
        if body:IsShown() then
            assert(not shown, "two size rows shown at once")
            shown = id
        end
    end
    return shown
end
assert(SizeShown() == "name", "the size panel does not start on the name")
editor.kit:Select(first.icon)
assert(SizeShown() == "icon", "selecting the icon did not show its size")
editor.kit:Select(first.counts[1])
assert(SizeShown() == "buttons", "a roll count did not show the button size")
editor.kit:Release()
assert(SizeShown() == "buttons", "releasing the selection hid the size row")
local sizeRow = editor.sizeViews.timer.children[1]
assert(sizeRow.rule.key == "timerSize" and sizeRow.searchMeta.settingKey == "msufsuite.lootRolls.timerSize")
assert(sizeRow.prepare() and SizeShown() == "timer", "search did not show the found element's size")
local gridKeys, all = {}, {}
for key, rule in pairs(rules) do all[#all + 1] = rule end
for _, rule in ipairs(Properties.GridRules(all)) do gridKeys[rule.key] = true end
assert(not gridKeys.nameSize and not gridKeys.buttonsSize and gridKeys.fontSize and gridKeys.width,
    "the settings grid shows element sizes or lost its own rules")
config.nameSize = 18
ui.Paint()
assert(view.rows[1].name.fontSize == 18 and view.rows[3].name.fontSize == 18, "the name size did not reach the preview")
config.nameSize = 0
ui.Paint()
for _, widget in ipairs(everyWidget) do
    assert(widget.scripts.OnUpdate == nil, "a preview frame kept an OnUpdate script outside a drag")
end

-- Combat: the edge event (before the lockdown) drops the drag, the selection
-- and the keys; during the lockdown nothing shows and no keyboard call runs.
cursorX, cursorY, mouseDown = 0, 0, true
Fire(first.remaining, "OnMouseDown", "LeftButton")
cursorX = 30
Fire(first.remaining, "OnUpdate")
writesBefore = writes
combat = true
ui.stage.scripts.OnEvent(ui.stage, "PLAYER_REGEN_DISABLED")
for _, hook in ipairs(ui.stage.hooks.OnEvent) do hook(ui.stage, "PLAYER_REGEN_DISABLED") end
assert(editor.kit:Selected() == nil and editor.kit.drag == nil and editor.claim == nil and ui.stage.keyboard == false,
    "the combat edge kept the selection, drag or keys")
assert(not first.name:IsShown() and not first.buttons[1]:IsShown() and writes == writesBefore, "targets shown in combat")
lockdown, mouseDown = true, false
ui.Paint()
assert(not editor.kit:Arrow(1, 0) and barDeps.SelectHandle(nil, first.name) == false, "moved in combat")
page:Hide()
page:Show()
ui.Paint()
lockdown, combat = false, false
ui.Paint()
assert(first.name:IsShown() and config.remainingOffsetX == 0, "targets did not return after combat")

-- Combat and a hidden page never navigate or toggle.
combat, opened = true, nil
Click(first.name)
assert(opened == nil, "combat click navigated")
combat = false
page:Hide()
opened = nil
Click(first.name)
assert(opened == nil and chips.name.command.set(false) == false and editor.layers.name ~= false,
    "hidden preview navigated or toggled")
assert(Same(before, config) and loadedRuntime and not config.enabled)
for _, widget in ipairs(everyWidget) do
    assert(widget.scripts.OnUpdate == nil, "a preview frame kept an OnUpdate script")
end
print("loot roll preview editor: exact targets, preview layers, sizes, moving, availability, hover sync and lifecycle OK")
