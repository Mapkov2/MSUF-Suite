-- The shared Quality of Life layer editor (MSUF_Suite_Options/Pages/
-- QoLLayerEditor.lua) for battle resurrection and the minimal loot window:
-- the rail toggles <key>Shown, layer panels follow the selection, targets
-- cover the runtime's regions with the background behind, a drag writes
-- clamped offsets and moves the drawing live, a fixed layer only selects,
-- release hands the stage back; the page lists layer sections after the
-- feature's own, and search routes a layer setting to its layer.
local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local Widget = {}
Widget.__index = Widget
local function New(parent)
    return setmetatable({ parent = parent, shown = true, level = parent and parent.level + 1 or 1, scale = 1 }, Widget)
end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:GetFrameLevel() return self.level end
function Widget:Hide() self.shown = false end
function Widget:Show() self.shown = true end
function Widget:SetShown(value) self.shown = value == true end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:SetParent(parent) self.parent = parent end
function Widget:SetScript(event, callback)
    self.scripts = self.scripts or {}
    self.scripts[event] = callback
end
function Widget:HookScript(event, callback)
    local previous = self.scripts and self.scripts[event]
    self:SetScript(event, function(...)
        if previous then previous(...) end
        callback(...)
    end)
end
function Widget:ClearFocus() self.scripts.OnEditFocusLost(self) end
function Widget:ClearAllPoints() self.all = nil end
function Widget:SetAllPoints(region) self.all = region end
function Widget:SetPoint() end
function Widget:SetWidth(width) self.width = width end
function Widget:SetHeight(height)
    if self.height == height then return end
    self.height = height
    if self.scripts and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self) end
end
function Widget:GetHeight() return self.height or 20 end
function Widget:SetBackdrop() end
function Widget:SetBackdropColor() end
function Widget:SetBackdropBorderColor() end
function Widget:GetEffectiveScale() return self.scale end
function Widget:GetScale() return self.scale end
function Widget:SetScale(scale) self.scale = scale end
function Widget:GetCenter() return 100, 100 end
function Widget:GetWidth() return 120 end
function Widget:GetRect() return 60, 80, 80, 40 end
function Widget:GetStringHeight() return 14 end
CreateFrame = function(_, _, parent) return New(parent) end

------------------------------------------------------------------ catalog
local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
for _, file in ipairs({ "SuiteCatalog", "Catalog/QualityOfLife", "Catalog/QualityOfLifeIndicators", "Catalog/LootWindow" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", catalogNS)
end
local catalog = catalogNS.SuiteCatalog
local profile = { lootWindow = {}, battleRes = {} }
for id, values in pairs(profile) do
    for key, rule in pairs(catalog[id].rules) do values[key] = rule.default end
end

------------------------------------------------------------------ menu stubs
local moved, hidden, writes, sets = {}, {}, {}, {}
local controllers = {}
local combat, profileEpoch = false, 0
local P = { catalog = catalog, T = { colors = { border = { 0, 0, 0, 1 }, text = { 1, 1, 1 } } }, HM = {}, M = {} }
P.Tr = function(text) return text end
P.W = { SwitchAt = function(panel, name) return New(panel) end }
P.M.BindBoolWidget = function(_, toggle, get, set) toggle.get, toggle.set = get, set end
P.RuleEnabled = function() return not combat end
P.GateControls = function() end
P.S = {
    MoveLootWindowPreviewLayer = function(_, key, x, y) moved[#moved + 1] = { "lootWindow", key, x, y } end,
    MoveBattleResPreviewLayer = function(_, key, x, y) moved[#moved + 1] = { "battleRes", key, x, y } end,
    HideLootWindowPreview = function(stage) hidden[#hidden + 1] = stage end,
    HideBattleResPreview = function(stage) hidden[#hidden + 1] = stage end,
}
P.HM.SkipHistoryCheckpoint = function() end
P.Combat = function() return combat end
P.ProfileGuard = function()
    local epoch = profileEpoch
    return function() return epoch == profileEpoch and not combat end
end
P.Get = function(id, key) return profile[id][key] end
P.Set = function(id, key, value)
    sets[#sets + 1] = { id, key, value }
    profile[id][key] = value
    return true
end
P.SetMany = function(id, values)
    writes[#writes + 1] = values
    for key, value in pairs(values) do profile[id][key] = value end
    return true
end
P.Text = function(parent) return New(parent) end
P.SectionRules = function(id, section, filter)
    local rules = {}
    for _, rule in pairs(catalog[id].rules) do
        if rule.section == section and (not filter or filter(rule)) then rules[#rules + 1] = rule end
    end
    return rules
end
P.RuleRow = function(_, id, rule)
    return {
        get = function() return P.Get(id, rule.key) end,
        set = function(value) P.Set(id, rule.key, value) end,
    }
end
local grids = {}
P.RuleGrid = function(_, panel, page, id, rules, top)
    local shown, entries = {}, {}
    for _, rule in ipairs(rules) do
        if not rule.hidden then
            shown[#shown + 1] = rule
            entries[#entries + 1] = { rule = rule, widget = New(panel) }
        end
    end
    grids[#grids + 1] = { id = id, rules = shown, page = page }
    return top - 40 * #shown, entries
end
local strips = {}
P.MenuWorkspace = {
    WrappingTabs = function(picker, values, choose)
        local row = New(picker.header)
        row:SetHeight(26)
        strips[#strips + 1] = { picker = picker, values = values, choose = choose }
        return row, choose
    end,
}
P.M.PreviewSelectionBar = {
    Create = function(stage, deps)
        stage.deps = deps
        local bar = New(stage)
        bar.editX, bar.editY = New(bar), New(bar)
        return bar
    end,
    Refresh = function(stage) stage.refreshed = true end,
}
P.PreviewInteraction = {
    Outline = function(handle, on) if handle then handle.outlined = on end end,
    LayoutSelectionBar = function(bar, width) bar:SetWidth(width) end,
    BuildLayerRail = function(owner, _, specs, toggle, open)
        owner.chips, owner.layerButtons, owner.toggle, owner.open = New(), {}, toggle, open
        for index, spec in ipairs(specs) do owner.layerButtons[index] = { key = spec[1] } end
    end,
    LayoutLayerRail = function() end,
    RefreshLayerRail = function(owner) owner.refreshed = (owner.refreshed or 0) + 1 end,
    Handles = function(_, opts)
        local controller = { entries = {} }
        function controller:Add(key, target, read, write, info)
            local entry = { target = target, read = read, write = write, info = info }
            self.entries[key], self.entries[target] = entry, entry
        end
        function controller:Select(target)
            self.selected = target
            opts.select(target)
        end
        function controller:Nudge(dx, dy)
            local entry = self.entries[self.selected]
            local x, y = entry.read()
            return entry.write(x + dx, y + dy)
        end
        function controller:Selected() return self.selected end
        function controller:Release()
            self.released = true
            self:Select(nil)
        end
        controllers[#controllers + 1] = controller
        return controller
    end,
}
for _, file in ipairs({ "QoLLayerEditor", "BattleResEditor", "LootWindowEditor" }) do
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. file .. ".lua"))("MSUF_Suite_Options", P)
end

------------------------------------------------------------------ loot window editor
local editor = P.LootWindowEditor
Check(editor.view == "suiteLootWindowPreview" and P.BattleResEditor.view == "suiteBattleResPreview",
    "each editor must name its runtime view")
Check(P.QoLLayerSection("lootWindow", "loot_window_icon")[1] == "icon" and not P.QoLLayerSection("lootWindow", "loot_feed")
    and P.QoLLayerSection("battleRes", "battle_res_timer"), "layer sections are not recognized")
local stage = New()
local ui = { stage = stage, targets = {}, width = 300, height = 190, ctx = {}, paints = 0 }
ui.Paint = function()
    ui.paints = ui.paints + 1
    ui.drawConfig = editor.PreviewConfig(ui, profile.lootWindow)
end
ui.OpenTarget = function(key) ui.opened = key end
local railBottom = editor.BuildRail(ui, New(), -20, 300)
Check(ui.offsetBar and railBottom < -48 and ui.offsetBar.width == 300, "the loot preview must reserve space for the host X/Y bar")
local controls, resized = {}, {}
Check(editor.BuildSettings ~= nil, "the loot editor must organize settings into submenus")
local bottom = editor.BuildSettings(ui, New(), -100, 300, "suite_qualityOfLife", "section", function(entries, prepare)
    for _, entry in ipairs(entries) do
        controls[entry.rule.key] = { widget = entry.widget, label = entry.rule.label, prepare = prepare }
    end
end, function() return -38 end, function(position) resized[#resized + 1] = position end)
Check(bottom < -100 and #grids == 8 and #strips == 2, "the loot editor must build one group per submenu")
for _, grid in ipairs(grids) do
    for _, rule in ipairs(grid.rules) do
        Check(not rule.key:match("[XY]$"), "an X/Y rule is visible below the preview: " .. rule.key)
    end
end
local general, settings = strips[1], strips[2]
Check(settings.picker.selected == "general" and general.picker.selected == "appearance"
    and #settings.values == 5 and #general.values == 3, "General and its appearance submenu must open first")
Check(controls.look.widget:IsVisible() and not controls.feedFadeOut.widget:IsVisible(), "only the active submenu should be visible")
controls.feedFadeOut.prepare()
Check(general.picker.selected == "feed" and controls.feedFadeOut.widget:IsVisible() and not controls.look.widget:IsVisible(),
    "search must reveal the feed submenu")
controls.fadeIn.prepare()
Check(general.picker.selected == "window" and controls.fadeIn.widget:IsVisible(), "window settings must have their own submenu")
controls.subtitleSize.prepare()
Check(settings.picker.selected == "subtitle" and controls.subtitleSize.widget:IsVisible() and not controls.fadeIn.widget:IsVisible()
    and #resized > 0 and resized[#resized] > bottom, "a layer tab must expose and size only its own settings")
for _, layer in ipairs(editor.layers) do
    local control = controls[layer[1] .. "Shown"]
    Check(control.widget.set ~= nil and control.label == layer[2], "each element needs its own named live visibility switch")
end
ui.toggle("background", true)
Check(profile.lootWindow.backgroundShown == false and ui.paints == 1 and ui.drawConfig.backgroundShown
    and settings.picker.selected == "subtitle" and #sets == 0, "preview visibility must not change the profile or open a submenu")
ui.open({ "background" })
Check(settings.picker.selected == "general" and general.picker.selected == "appearance"
    and controls.backgroundShown.widget:IsVisible(), "right-clicking the background must reveal Appearance")
controls.iconShown.widget.set(false)
Check(profile.lootWindow.iconShown == false and not editor.PreviewConfig(ui, profile.lootWindow).iconShown,
    "the switch in settings must change the saved visibility")
ui.toggle("icon", true)
Check(ui.drawConfig.iconShown and not profile.lootWindow.iconShown,
    "the preview may show an element that is disabled in game")
local otherProfile = { iconShown = false, nameShown = false }
Check(not editor.PreviewConfig(ui, otherProfile).nameShown and editor.PreviewConfig(ui, profile.lootWindow).nameShown,
    "preview defaults must follow the current profile before a local override")

-- Targets cover the drawing: background behind, the element layers above.
local host = New()
local view = { panel = New(host), bounds = {} }
for _, key in ipairs({ "icon", "name", "subtitle", "count" }) do view.bounds[key] = New(host) end
view.bounds.count.shown = false
editor.Bind(ui, host, view, editor.PreviewConfig(ui, profile.lootWindow))
local moves = controllers[1].entries
Check(ui.targets.background.all == view.panel and ui.targets.icon.all == view.bounds.icon and not ui.targets.count.shown,
    "targets must cover the painted regions")
Check(ui.targets.background.level < ui.targets.icon.level and ui.targets.icon.level < ui.targets.count.level,
    "the background must lie behind the elements")
Check(moves.background.write == nil and moves.background.info.follow == nil, "the fixed background must only select")
Check(ui.layers.background == true and ui.layers.subtitle == true, "the rail does not reflect the profile")
moves.icon.info.follow(nil, 6, -3)
Check(moved[1][1] == "lootWindow" and moved[1][2] == "icon" and moved[1][3] == 6 and moved[1][4] == -3,
    "a drag must move the drawing live")
Check(moves.icon.write(500.4, -2.6) and profile.lootWindow.iconX == 120 and profile.lootWindow.iconY == -3,
    "a drag must write clamped, rounded offsets")
Check(moves.icon.write(500, -3) == false and #writes == 1, "an unchanged position must not write")
local deps = stage.deps
ui.open({ "icon" })
local x, y = deps.ReadOffsets(stage, ui.targets.icon)
Check(ui.moves:Selected() == ui.targets.icon and deps.IsPlaced(ui.targets.icon) and x == 120 and y == -3,
    "the preview bar must follow a selected layer and read its stored offsets")
Check(not deps.IsPlaced(ui.targets.background) and not deps.IsPlaced(ui.targets.count),
    "fixed and hidden layers must not expose editable coordinates")
Check(deps.WriteOffsets(stage, ui.targets.icon, 11, -7) and deps.NudgeDelta(stage, 1, -1)
    and profile.lootWindow.iconX == 12 and profile.lootWindow.iconY == -8, "exact fields and nudge must move the same layer")
local dx, dy = deps.DefaultOffsets(stage, ui.targets.icon)
Check(dx == 0 and dy == 0, "reset must use the layer defaults")
deps.OpenSettings(stage, ui.targets.icon)
Check(ui.opened == "iconShown", "the settings button must jump to the selected layer")
local input = ui.offsetBar.editX
input.scripts.OnEditFocusGained(input)
profileEpoch = profileEpoch + 1
Check(not deps.WriteOffsets(stage, ui.targets.icon, 30, 20), "an edit begun on an old profile must not write")
ui.open({ "subtitle" })
Check(ui.offsetEdit == nil and ui.moves:Selected() == ui.targets.subtitle, "switching layers must clear the old input focus")
combat = true
Check(not deps.WriteOffsets(stage, ui.targets.subtitle, 10, 10), "combat must refuse exact position changes")
combat = false
editor.Release(ui)
Check(controllers[1].released and hidden[1] == stage, "release must hand the stage back")

------------------------------------------------------------------ battle resurrection parity
local battleUI = { stage = New(), targets = {}, width = 300, height = 190, ctx = {}, Paint = function() end }
P.BattleResEditor.BuildRail(battleUI, New(), -20, 300)
Check(battleUI.selectedLayer == "background" and not battleUI.offsetBar, "battle resurrection must retain its existing editor")
local battleRules = {}
P.BattleResEditor.BuildProperties(battleUI, New(), -100, 300, "suite_qualityOfLife", "section", function(entries)
    for _, entry in ipairs(entries) do battleRules[entry.rule.key] = entry.rule end
end)
for _, key in ipairs({ "count", "maximum", "timer" }) do
    local rule = battleRules[key .. "Point"]
    Check(rule and rule.section == "battle_res_" .. key and rule.default == 1
        and rule.choices[1] == "Default position" and #rule.choices == #catalogNS.AnchorLabels + 1
        and rule.choices[6] == "Center", key .. " must offer the default and nine anchor points in its layer settings")
end
local battleHost = New()
local battleView = { panel = New(battleHost), borderBounds = New(battleHost), icon = New(battleHost), title = New(battleHost),
    count = New(battleHost), maximum = New(battleHost), cooldown = New(battleHost), time = New(battleHost) }
P.BattleResEditor.Bind(battleUI, battleHost, battleView, profile.battleRes)
local battleMoves = controllers[2].entries
Check(battleUI.targets.timer.all == battleView.cooldown and battleUI.targets.border.all == battleView.borderBounds,
    "battle resurrection regions changed")
Check(battleUI.targets.border.level < battleUI.targets.icon.level and battleMoves.background.write ~= nil,
    "battle resurrection layers must keep their order and stay movable")
battleMoves.title.info.follow(nil, 2, 1)
Check(moved[2][1] == "battleRes" and moved[2][2] == "title", "battle resurrection drags must reach its runtime")

------------------------------------------------------------------ page wiring
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local page = Read("MSUF_Suite_Options/Pages/QualityOfLifeCatalog.lua")
Check(page:find('{ id = "lootWindow", title = "Minimal loot window", switch = "enabled", sections = { "loot_window", "loot_feed" }',
    1, true) and page:find("loot.quickLoot lootWindow lootRolls", 1, true), "the loot window is not on the Loot page")
Check(page:find("spec and spec.layers", 1, true) and not page:find("P.catalog.battleRes.layers", 1, true),
    "the page must list every layer editor's sections")
local details = Read("MSUF_Suite_Options/Pages/QualityOfLife.lua")
Check(details:find("if P.QoLLayerSection(group.id, section.key) then break end", 1, true),
    "the feature grid must leave layer sections to the editor")
local preview = Read("MSUF_Suite_Options/Pages/QualityOfLifePreview.lua")
Check(preview:find('lootWindow = "DrawLootWindowPreview"', 1, true) and preview:find("ui.stage[ui.editor.view]", 1, true),
    "the preview must draw the loot window and bind any editor to its own view")
local toc = Read("MSUF_Suite_Options/MSUF_Suite_Options_Mainline.toc")
local order = {}
for line in toc:gmatch("[^\r\n]+") do order[line] = #order + 1 order[#order + 1] = line end
Check(order["Pages\\QoLLayerEditor.lua"] < order["Pages\\BattleResEditor.lua"]
    and order["Pages\\LootWindowEditor.lua"] < order["Pages\\QualityOfLifePreview.lua"], "editor load order broken")

-- Search opens a layer setting on its layer.
local routing = { catalog = catalog, M = {}, OwnedTools = {}, QoLLayerSection = P.QoLLayerSection,
    Suite = { HostBridge = { RegisterSearchTargetResolver = function() end } } }
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/ToolRouting.lua"))("MSUF_Suite_Options", routing)
local target = { controlId = "c", settingKey = "msufsuite.lootWindow.iconSize", sectionId = "suite_qualityOfLife_lootWindow_x" }
local resolved, copy = routing.ResolveToolSearchTarget("suite_qualityOfLife", target)
Check(resolved == "suite_qualityOfLife" and copy ~= target and copy.controlId == nil and copy.sectionId == target.sectionId,
    "a loot window layer setting must open through its layer")
print("suite_qol_layer_editor_contract: ok (" .. checks .. " checks)")
