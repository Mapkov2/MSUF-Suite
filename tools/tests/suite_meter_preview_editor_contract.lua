local root = assert(arg[1]):gsub("\\", "/")
local host = root .. "/../MidnightSimpleUnitFrames"
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { locale = "deDE" })
local env, M, world = mw.env, mw.M, mw.world
-- Client visibility includes every ancestor; the generic widget stubs only
-- model each region's own shown flag.
world.widgets.Methods.IsVisible = function(self)
    local parent = self:GetParent()
    return self:IsShown() and (not parent or parent:IsVisible())
end
env.InCombatLockdown, env.UnitAffectingCombat = function() return false end, function() return false end
env.GetCurrentKeyBoardFocus = function() return nil end
env.IsControlKeyDown, env.IsShiftKeyDown = function() return false end, function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
env.C_AddOns = {
    GetAddOnMetadata = function() end, IsAddOnLoaded = function() return true, true end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end, LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local function Load(addon, namespace)
    local file = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local source = file:read("*a"); file:close()
    for line in source:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            assert(ok, tostring(message))
        end
    end
end
Load("MSUF_Suite", {})
local Suite, P = env.MSUFSuite, {}
assert(Suite.Database.Initialize(nil))
Suite.Suite.Config("damageMeter").enabled = true
Load("MSUF_Suite_Options", P)
local c = P.S.Config("damageMeter")
local ui, paints = nil, 0
-- Native window-shaped sample; the real runtime's anchors are checked by
-- suite_meter_menu_preview_contract. Navigation uses the real host below.
P.S.DamageMeterDrawMenuPreview = function(parent, index)
    assert(ui.ctx.wrapper:IsVisible() and M.activeKey == "suite_damageMeter", "preview painted before its owning page was shown")
    paints = paints + 1
    if parent.meterTestWindow then
        local win = parent.meterTestWindow
        win.index = index
        return win
    end
    local function Frame(kind, owner, width, height, x, y)
        local frame = env.CreateFrame(kind, nil, owner)
        frame:SetSize(width, height); frame:SetPoint("TOPLEFT", owner, "TOPLEFT", x or 0, y or 0)
        return frame
    end
    local win = { frame = Frame("Frame", parent, 260, 170), buttons = {}, rows = {}, capacity = 3, overall = false }
    win.header, win.body = Frame("Button", win.frame, 260, 22), Frame("Frame", win.frame, 258, 148, 1, -23)
    win.title, win.timer = win.header:CreateFontString(), win.header:CreateFontString()
    win.title:SetSize(100, 18); win.timer:SetSize(30, 18)
    for _, key in ipairs({ "settings", "reset", "session", "type" }) do win.buttons[key] = Frame("Button", win.header, 18, 18) end
    for i = 1, 3 do
        local row = Frame("Button", win.body, 258, 18, 0, -(i - 1) * 20)
        row.nameText, row.valueText, row.rankText, row.icon = row:CreateFontString(), row:CreateFontString(), row:CreateFontString(), row:CreateTexture()
        row.bar, row.track = env.CreateFrame("StatusBar", nil, row), row:CreateTexture()
        local fill = row.bar:CreateTexture()
        row.bar.GetStatusBarTexture = function() return fill end
        win.rows[i] = row
    end
    parent.meterTestWindow = win
    return win
end
local build = P.BuildMeterMenuPreview
P.BuildMeterMenuPreview = function(workspace, ...)
    ui = workspace
    return build(workspace, ...)
end
-- Build and refresh while hidden, at the same settings revision. Selecting
-- this cached page must wake its fixed preview without changing the picker.
local cold = assert(M.BuildPageEntry("suite_damageMeter", false))
M.RunEntryRefreshers(cold)
assert(paints == 0, "hidden page build painted its preview")
assert(M.SelectPage("suite_damageMeter"))
mw:RunTimers()
local ctx = assert(M.cache.suite_damageMeter)
local preview = assert(ui and ui.meterPreview, "page did not build its preview")
local E, targets = P.MeterPreviewEditor, preview.targets
-- The real capture state: the arrow bindings the menu set for this preview and the keyboard of each
-- element (the kit keeps no memo flag of its own).
local nudgeBox = "MSUF_SuiteMeterPreview_ActiveNudgeBox"
for _, element in ipairs(preview.handles) do
    element.EnableKeyboard = function(self, on) self.keyboardOn = on == true end
end
local function Capturing()
    if env[nudgeBox] ~= nil then return true end
    for _, element in ipairs(preview.handles) do if element.keyboardOn then return true end end
    return false
end
assert(targets and preview.selection and #preview.layerButtons == 9, "interactive preview did not build")
assert(preview.selected() == 1 and paints > 0, "initial window 1 preview required a picker change")
local priorPaints = paints
assert(M.SelectPage("home"))
mw:RunTimers()
assert(paints == priorPaints, "leaving the meter repainted its hidden fixed preview")
-- The native dock reparents/shows the header before the page wrapper. A
-- refresh in that phase must wait for the post-show activation callback.
M.SetActivePageHeader(ctx)
ui.refreshPreview()
assert(paints == priorPaints, "docked header painted while its owning page was hidden")
assert(M.SelectPage("suite_damageMeter"))
mw:RunTimers()
assert(paints > priorPaints and preview.selected() == 1, "reopening cached meter lost its initial preview")
for _, target in ipairs({ targets.title, targets.timer, targets.buttons.settings, targets.buttons.reset, targets.buttons.session, targets.buttons.type }) do
    assert(target:GetFrameLevel() > targets.header:GetFrameLevel(), "header surface can intercept an element hit")
end
local function Click(handle, expectedKey, section)
    local shell = ui.sections[section]
    assert(shell, "missing target section")
    local entry = P.HM.GetSectionEntry(shell)
    if entry and entry.SetOpenImmediate then entry.SetOpenImmediate(false) end
    handle:GetScript("OnClick")(handle, "LeftButton")
    mw:RunTimers()
    local exact = P.Meta("suite_damageMeter", "damageMeter", expectedKey,
        expectedKey:match("^action%.") and "action" or "setting", section)
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_damageMeter", exact)
    assert(widget and widget:IsVisible(), "click failed to resolve the exact visible control: " .. expectedKey)
    assert(ui.selected == shell._suiteWorkspaceTab, "click left the owning tab hidden")
    assert(entry and entry.open, "click left the owning accordion closed")
    local highlight = ctx.wrapper._msuf2SearchHighlight
    assert(highlight and highlight:IsShown(), "click did not highlight a control")
    local _, _, _, _, y = highlight:GetPoint(1)
    local expectedY = -math.max(0, math.max(0, ctx.wrapper:GetTop() - widget:GetTop()) - 8)
    assert(math.abs(y - expectedY) < .01, "highlight belongs to the accordion instead of the exact control")
end
Click(targets.rows[1].name, "leftSize", "suite_damageMeter_text")
Click(targets.rows[1].value, "rightSize", "suite_damageMeter_text")
Click(targets.rows[1].icon, "iconStyle", "suite_damageMeter_bars")
Click(targets.rows[1].rank, "rank", "suite_damageMeter_text")
Click(targets.rows[1].barHit, "barHeight", "suite_damageMeter_bars")
Click(targets.title, "titleSize", "suite_damageMeter_window")
Click(targets.timer, "headerTimerSize", "suite_damageMeter_timer")
Click(targets.buttons.type, "w1Type", "suite_damageMeter_windows")
Click(targets.buttons.session, "w1Session", "suite_damageMeter_windows")
Click(targets.buttons.settings, "windowCount", "suite_damageMeter_general")
Click(targets.buttons.reset, "action.reset_data", "suite_damageMeter_damageMeter_module")
Click(targets.body, "w1Width", "suite_damageMeter_windows")
local selectedIndex = preview.selected
-- Change the page's actual picker closure, then exercise real exact preparation.
debug.setupvalue(selectedIndex, 1, 2)
c.windowCount = 1
assert(E.Open(preview, targets.buttons.type))
mw:RunTimers()
assert(selectedIndex() == 2, "exact navigation changed the explicitly selected inactive window")
debug.setupvalue(selectedIndex, 1, 1)
preview.selected = selectedIndex
local owner, handle = preview.viewport, targets.rows[1].name
E.Select(preview, handle)
assert(preview._msuf2SelectedPreviewLayerKey == "name", "selected element did not emphasize its layer")
local nameRegion = preview.stage.meterTestWindow.rows[1].nameText
nameRegion:SetWidth(160)
nameRegion.GetStringWidth = function() return 50 end
E.Refresh(preview)
assert(handle:GetWidth() == 50, "name click target covers the empty bar instead of its rendered text")
local x, y = 100, 100
env.GetCursorPosition = function() return x, y end
preview.stage.GetEffectiveScale = function() return .5 end
handle:GetScript("OnMouseDown")(handle, "LeftButton")
x, y = 110, 95
handle:GetScript("OnMouseUp")(handle, "LeftButton")
assert(c.nameOffsetX == 20 and c.nameOffsetY == -10, "scaled drag did not persist native offsets")
handle:GetScript("OnKeyDown")(handle, "RIGHT")
assert(c.nameOffsetX == 21, "arrow key did not nudge the selected element: " .. tostring(c.nameOffsetX)
    .. " selected=" .. tostring(owner._selectedHandle == handle) .. " visible=" .. tostring(handle:IsVisible()))
-- The preview kit's handle controller keeps the menu's steps: Shift 5, Ctrl 10.
env.IsShiftKeyDown = function() return true end
handle:GetScript("OnKeyDown")(handle, "RIGHT")
env.IsShiftKeyDown = function() return false end
assert(c.nameOffsetX == 26, "Shift must nudge a preview element by 5: " .. tostring(c.nameOffsetX))
env.IsControlKeyDown = function() return true end
handle:GetScript("OnKeyDown")(handle, "LEFT")
env.IsControlKeyDown = function() return false end
assert(c.nameOffsetX == 16, "Ctrl must nudge a preview element by 10: " .. tostring(c.nameOffsetX))
handle:GetScript("OnKeyDown")(handle, "UP")
assert(c.nameOffsetY == -9, "an up arrow must raise the element by 1: " .. tostring(c.nameOffsetY))
handle:GetScript("OnKeyDown")(handle, "DOWN")
assert(c.nameOffsetY == -10 and preview.kit and preview.handles == preview.kit.list,
    "the meter preview runs on the kit")
-- A drag that begins while another element is selected: the selection the press makes repaints the
-- preview, and that repaint must neither cancel the drag nor lose its claim on the window.
for _, other in ipairs({ targets.body, targets.header, targets.title }) do
    E.Select(preview, other)
    c.nameOffsetX, c.nameOffsetY = 20, -10
    x, y = 100, 100
    handle:GetScript("OnMouseDown")(handle, "LeftButton")
    assert(preview.kit.drag and preview.kit.drag.entry.region == handle,
        "pressing an element while " .. other._label .. " was selected lost the drag")
    x = 120
    handle:GetScript("OnMouseUp")(handle, "LeftButton")
    assert(c.nameOffsetX == 60 and c.nameOffsetY == -10,
        "a drag begun from " .. other._label .. " did not move the element: " .. tostring(c.nameOffsetX))
end
-- The claim belongs to its drag: a click, or a commit refused in combat, leaves nothing behind for
-- the next arrow or X/Y write, which are not drags.
E.Select(preview, handle)
c.nameOffsetX, c.nameOffsetY = 20, -10
x, y = 100, 100
handle:GetScript("OnMouseDown")(handle, "LeftButton")
handle:GetScript("OnMouseUp")(handle, "LeftButton")
assert(handle.dragToken == nil, "a click left its drag claim behind")
preview.selected = function() return 2 end
handle:GetScript("OnKeyDown")(handle, "RIGHT")
assert(c.nameOffsetX == 21, "an arrow after a click was refused as a stale drag: " .. tostring(c.nameOffsetX))
preview.selected = function() return 1 end
handle:GetScript("OnMouseDown")(handle, "LeftButton")
x = 140
preview.inCombat = true
handle:GetScript("OnMouseUp")(handle, "LeftButton")
preview.inCombat = false
assert(c.nameOffsetX == 21 and handle.dragToken == nil, "combat did not refuse the commit, or left its claim behind")
world.widgets:AdvanceTime(1)
preview.selected = function() return 2 end
handle:GetScript("OnKeyDown")(handle, "RIGHT")
assert(c.nameOffsetX == 22, "an arrow after a refused drag commit was refused as a stale drag: " .. tostring(c.nameOffsetX))
preview.selected = function() return 1 end
c.nameOffsetX, c.nameOffsetY = 16, -10
E.Select(preview, handle)
-- Order, not count: what a selection, a press, a release, a repaint and an arrow do to the keyboard,
-- the panels and the settings, as the old code did them (it is the oracle for these sequences).
do
    local log = {}
    local function Log(entry) log[#log + 1] = entry end
    local setBindings, sbRefresh, setMany = M.SetPreviewArrowBindings, M.PreviewSelectionBar.Refresh, P.SetMany
    M.SetPreviewArrowBindings = function(box, enabled, spec) Log("bindings:" .. tostring(enabled)); return setBindings(box, enabled, spec) end
    M.PreviewSelectionBar.Refresh = function(box) Log("sb"); return sbRefresh(box) end
    P.SetMany = function(id, values) Log("write"); return setMany(id, values) end
    local propsRefresh = P.MeterPreviewProperties.Refresh
    P.MeterPreviewProperties.Refresh = function(p) Log("properties"); return propsRefresh(p) end
    local startMoving, stopMoving = handle.StartMoving, handle.StopMovingOrSizing
    handle.StartMoving = function(self) Log("startMoving"); return startMoving(self) end
    handle.StopMovingOrSizing = function(self) Log("stopMoving"); return stopMoving(self) end
    for _, element in ipairs(preview.handles) do
        local base = element.EnableKeyboard
        element.EnableKeyboard = function(self, on) Log("kbd:" .. tostring(self._label) .. ":" .. tostring(on)); return base(self, on) end
    end
    local function Took()
        local out = log
        log = {}
        return out
    end
    local function InOrder(entries, ...)
        local at = 1
        for _, want in ipairs({ ... }) do
            local found
            for i = at, #entries do
                if entries[i] == want then found = i; break end
            end
            assert(found, "'" .. want .. "' missing or out of order in: " .. table.concat(entries, " "))
            at = found + 1
        end
    end
    E.Select(preview, nil)
    Took()
    E.Select(preview, handle)
    InOrder(Took(), "kbd:Name:true", "bindings:true", "sb", "properties")
    E.Select(preview, targets.title)
    InOrder(Took(), "kbd:Name:false", "kbd:Title:true", "bindings:true", "sb", "properties")
    E.Select(preview, nil)
    Took()
    local before = c.nameOffsetX
    x, y = 100, 100
    handle:GetScript("OnMouseDown")(handle, "LeftButton")
    InOrder(Took(), "kbd:Name:true", "bindings:true", "sb", "properties", "startMoving")
    -- A repaint of the preview in the middle of a drag leaves the drag alone.
    ui.refreshPreview()
    Took()
    x = 120
    handle:GetScript("OnMouseUp")(handle, "LeftButton")
    InOrder(Took(), "stopMoving", "write")
    assert(c.nameOffsetX == before + 40, "a repaint during the drag took the drag away: " .. tostring(c.nameOffsetX))
    world.widgets:AdvanceTime(1)
    handle:GetScript("OnKeyDown")(handle, "RIGHT")
    local nudged = Took()
    InOrder(nudged, "write")
    for _, entry in ipairs(nudged) do assert(entry ~= "startMoving" and entry ~= "stopMoving", "an arrow moved the element by hand") end
    M.SetPreviewArrowBindings, M.PreviewSelectionBar.Refresh, P.SetMany = setBindings, sbRefresh, setMany
    P.MeterPreviewProperties.Refresh = propsRefresh
    handle.StartMoving, handle.StopMovingOrSizing = nil, nil
    c.nameOffsetX, c.nameOffsetY = 16, -10
    E.Select(preview, handle)
end
assert(P.M.PreviewSelectionBar, "exact offset editor missing")
local deps = owner._msuf2SelectionDeps
assert(deps.WriteOffsets(owner, handle, 33, -8))
assert(c.nameOffsetX == 33 and c.nameOffsetY == -8, "exact X/Y did not reach settings")
assert(deps.ResetOffsets(owner, handle))
assert(c.nameOffsetX == 0 and c.nameOffsetY == 0, "reset did not restore defaults")
assert(deps.WriteOffsets(owner, handle, 21, -10))
-- Use the real bar's dependency callbacks through the same owner as Minimap.
assert(preview.selection:IsShown(), "exact offset editor is hidden")
local beforeX = c.nameOffsetX
handle:GetScript("OnMouseDown")(handle, "LeftButton")
preview.selected = function() return 2 end
x = x + 10
handle:GetScript("OnMouseUp")(handle, "LeftButton")
assert(c.nameOffsetX == beforeX, "window switch committed a stale drag")
preview.selected = function() return 1 end
local prior = c.w1X
targets.body:GetScript("OnMouseDown")(targets.body, "LeftButton")
x = x + 5
targets.body:GetScript("OnMouseUp")(targets.body, "LeftButton")
assert(c.w1X == prior and c.w2X == P.catalog.damageMeter.rules.w2X.default, "preview background moved a live window")
assert(not preview.kit.drag and not targets.header.canMove, "window/header retained an Edit Mode drag")
for _, button in ipairs(preview.layerButtons) do
    local key = button.key
    button:GetScript("OnClick")(button, "LeftButton")
    assert(preview.layers[key] == false, "layer failed to turn off")
    if key == "name" then
        assert(not targets.rows[1].name:IsShown() and targets.rows[1].value:IsShown(), "name layer hid its sibling")
    end
    if key == "bars" then
        assert(preview.stage.meterTestWindow.rows[1]:IsShown() and targets.rows[1].name:IsShown(), "bar paint layer hid row children")
        assert(not preview.stage.meterTestWindow.rows[1].bar:GetStatusBarTexture():IsShown(), "bar paint layer left its fill visible")
    end
    button:GetScript("OnClick")(button, "LeftButton")
end
for _, width in ipairs({ 300, 420, 720 }) do
    preview.availableWidth = width
    P.MeterPreviewLayers.Layout(preview)
    for _, button in ipairs(preview.layerButtons) do
        local _, _, _, bx = button:GetPoint(1)
        assert(bx + button:GetWidth() <= width, "localized layer rail clipped")
    end
end
-- Every icon shares the same offsets, in both class and specialization mode.
local R = P.MeterPreviewProperties
local icon, barHit = targets.rows[1].icon, targets.rows[1].barHit
local function UserSet(widget, value)
    assert(widget:GetScript("OnValueChanged"), "native slider input missing")
    widget:GetScript("OnValueChanged")(widget, value, true)
end
-- A native range change may clamp and fire OnValueChanged without user input.
-- Merely selecting a different element must never write that clamped value.
local savedSessionSize, savedLeftSize = c.sessionSize, c.leftSize
c.sessionSize, c.leftSize = 64, 11
E.Select(preview, targets.buttons.session)
local sizeWidget = preview.properties.grid.controls.size
local nativeRange = sizeWidget.SetMinMaxValues
sizeWidget.SetMinMaxValues = function(self, low, high)
    local value = self:GetValue()
    nativeRange(self, low, high)
    if value < low or value > high then self:GetScript("OnValueChanged")(self, math.max(low, math.min(high, value)), false) end
end
E.Select(preview, targets.rows[1].name)
assert(c.leftSize == 11, "selection range clamp mutated name font")
sizeWidget.SetMinMaxValues = nativeRange
c.sessionSize, c.leftSize = savedSessionSize, savedLeftSize
E.Select(preview, targets.header)
assert(preview.properties.label:GetText() == P.Tr("Applies to all windows"), "header size scope claims to affect only the selected window")
ui.refreshPreview()
assert(preview.scope == P.Tr("Applies to all windows") and preview.hint == P.Tr("Sample values. Click an element to open its settings."),
    "static header hint advertises live window movement")
assert(not preview.selection:IsShown() and not Capturing(), "header surface retained a window offset editor")
local savedWindowX, savedWindowY = c.w1X, c.w1Y
c.w1X, c.w1Y = savedWindowX + 37, savedWindowY - 29
local windowX, windowY = c.w1X, c.w1Y
preview.properties.reset:GetScript("OnClick")(preview.properties.reset, "LeftButton")
assert(c.w1X == windowX and c.w1Y == windowY, "header reset moved the live window")
c.w1X, c.w1Y = savedWindowX, savedWindowY
local _, _, _, _, propertiesY = preview.properties:GetPoint(1)
assert(propertiesY == -8, "static header retained a phantom offset toolbar gap")
E.Select(preview, targets.title)
local _, _, _, _, movableY = preview.properties:GetPoint(1)
assert(preview.selection:IsShown() and movableY == -40, "header text properties overlap the offset toolbar")
E.Select(preview, targets.body)
assert(preview.properties.label:GetText() == P.Tr("Only the selected window"), "window size scope claims to affect every window")
assert(not preview.selection:IsShown(), "window surface retained a window offset editor")
E.Select(preview, targets.header)
for field, control in pairs(preview.properties.grid.controls) do
    local title = P.HM.GetControlTitle(control)
    local slot = preview.properties.slots[field]
    assert(control:GetParent() == slot and title:GetParent() == slot, "native property parts escape their visibility container")
    for _, part in ipairs({ control, title, control.editBox, control.minusButton, control.plusButton }) do
        assert(part:IsVisible() == (field == "size"), "inactive native property parts remain visible")
    end
end
E.Select(preview, barHit)
assert(preview.propertiesHeight > 0)
E.Select(preview, nil)
assert(preview.propertiesHeight == 0)
E.Select(preview, barHit)
assert(preview.propertiesHeight > 0, "reselecting prior element leaves visible properties with zero reserved height")
assert(not preview.viewport.clipsChildren and preview.stage.clipsChildren, "sample clipping hides the offset toolbar")
assert(not rawget(preview.properties, "samplePicker"), "individual icon dropdown survived simplification")
for _, style in ipairs({ Suite.DamageMeterIconStyle.CLASS, Suite.DamageMeterIconStyle.SPEC }) do
    c.iconStyle = style
    ui.refreshPreview()
    E.Select(preview, icon)
    local beforeIconX = c.iconOffsetX
    icon:GetScript("OnMouseDown")(icon, "LeftButton")
    x = x + 9
    icon:GetScript("OnMouseUp")(icon, "LeftButton")
    assert(c.iconOffsetX == beforeIconX + 18, "icon drag did not write shared class/spec offsets")
    UserSet(preview.properties.grid.controls.size, 29)
    UserSet(preview.properties.grid.controls.layer, 30)
    assert(c.iconSize == 29 and c.iconLayer == 30, "icon properties did not write shared size/layer")
end
-- Each header control owns its offset and size; execute the actual drag lifecycle.
local priorHeight, priorIconSize = c.headerHeight, c.headerIconSize
c.headerHeight, c.headerIconSize = 14, 30
E.Select(preview, targets.buttons.session)
assert(R.Read(preview, targets.buttons.session, "size") == 14, "Auto header button size differs from the runtime clamp")
c.headerHeight, c.headerIconSize = priorHeight, priorIconSize
for _, kind in ipairs({ "settings", "reset", "session", "type" }) do
    local target = targets.buttons[kind]
    local sibling = kind == "reset" and "session" or "reset"
    local beforeSibling, beforeTitle = c[sibling .. "OffsetX"], c.titleOffsetX
    local beforeHeaderX = c[kind .. "OffsetX"]
    target:GetScript("OnMouseDown")(target, "LeftButton")
    x = x + 7
    target:GetScript("OnMouseUp")(target, "LeftButton")
    assert(c[kind .. "OffsetX"] == beforeHeaderX + 14, "header drag did not write its own offset")
    assert(c[sibling .. "OffsetX"] == beforeSibling and c.titleOffsetX == beforeTitle, "header drag moved a sibling")
    UserSet(preview.properties.grid.controls.size, 27)
    assert(c[kind .. "Size"] == 27, "header size wrote the shared group size")
end
for _, spec in ipairs({ { targets.title, "titleOffsetX", "titleSize" }, { targets.timer, "headerTimerOffsetX", "headerTimerSize" } }) do
    local before = c[spec[2]]
    spec[1]:GetScript("OnMouseDown")(spec[1], "LeftButton")
    x = x + 6
    spec[1]:GetScript("OnMouseUp")(spec[1], "LeftButton")
    assert(c[spec[2]] == before + 12, "header text drag failed")
    UserSet(preview.properties.grid.controls.size, 19)
    assert(c[spec[3]] == 19, "header text size failed")
end
E.Select(preview, targets.body)
UserSet(preview.properties.grid.controls.width, 480)
UserSet(preview.properties.grid.controls.height, 260)
assert(c.w1Width == 480 and c.w1Height == 260, "window preview size changed the wrong settings")
E.Select(preview, targets.rows[1].name)
UserSet(preview.properties.grid.controls.size, 15)
assert(c.leftSize == 15, "name font size failed")
E.Select(preview, targets.rows[1].value)
UserSet(preview.properties.grid.controls.size, 16)
assert(c.rightSize == 16, "value font size failed")
E.Select(preview, barHit)
UserSet(preview.properties.grid.controls.size, 24)
assert(c.barHeight == 24, "bar height failed")
E.Select(preview, icon)
preview.properties.reset:GetScript("OnClick")(preview.properties.reset, "LeftButton")
assert(c.iconOffsetX == 0 and c.iconOffsetY == 0 and c.iconSize == 0 and c.iconLayer == -1, "icon reset did not restore shared defaults")
-- The native font sink reports wrapping; the headless world has no font rasterizer.
preview.properties.label.GetStringHeight = function() return preview.availableWidth < 540 and 28 or 12 end
for _, width in ipairs({ 200, 300, 420, 720 }) do
    preview.availableWidth = width
    E.Select(preview, icon)
    local extra = math.max(0, math.ceil(preview.properties.label:GetStringHeight()) - 12)
    assert(preview.propertiesHeight == 50 + (width >= 540 and 48 or 96) + extra, "icon controls lack reserved space")
    assert(preview.properties.label:GetWidth() == width, "properties label did not follow narrow width")
    local title = P.HM.GetControlTitle(preview.properties.grid.controls.size)
    local _, _, _, _, sizeY = title:GetParent():GetPoint(1)
    assert(-sizeY >= preview.properties.label:GetStringHeight() + 8, "wrapped scope hint overlaps size control")
    for _, control in pairs(preview.properties.grid.controls) do
        if control:IsVisible() then
            local _, _, _, bx = control:GetPoint(1)
            assert(bx + control:GetWidth() <= width, "element property clipped at narrow width")
        end
    end
end
-- Long localized field labels grow their row before the next field/reset.
local layerTitle = P.HM.GetControlTitle(preview.properties.grid.controls.layer)
layerTitle.GetStringHeight = function() return 42 end
local function Fraction(point)
    return point:find("LEFT", 1, true) and 0 or point:find("RIGHT", 1, true) and 1 or .5
end
local function ToolbarLeft(region)
    if region == preview.selection then return 0 end
    local point, relative, anchor, dx = region:GetPoint(1)
    return ToolbarLeft(relative) + Fraction(anchor) * relative:GetWidth() + (dx or 0) - Fraction(point) * region:GetWidth()
end
for _, width in ipairs({ 200, 259, 260, 300, 420, 599, 600, 720 }) do
    preview.availableWidth = width
    preview.properties.lastWidth = nil
    E.Select(preview, icon)
    local widget, slot = preview.properties.grid.controls.layer, preview.properties.slots.layer
    local _, _, _, _, inputY = widget:GetPoint(1)
    local _, _, _, _, slotY = slot:GetPoint(1)
    local _, _, _, _, resetY = preview.properties.reset:GetPoint(1)
    assert(-inputY >= 50 and slot:GetHeight() >= -inputY + 24, "wrapped field title overlaps its slider")
    assert(-resetY >= -slotY + slot:GetHeight() + 4, "wrapped field title pushes a slider over reset")
    local bar = preview.selection
    for _, part in ipairs({ bar.axisX, bar.axisY, bar.openButton, bar.resetButton, bar.label }) do
        local left = ToolbarLeft(part)
        local _, _, _, _, dy = part:GetPoint(1)
        assert(left >= 0 and left + part:GetWidth() <= width, "narrow toolbar part escapes its width")
        assert(-dy + part:GetHeight() <= bar:GetHeight(), "narrow toolbar part escapes its height: " .. width .. "/" .. part:GetHeight() .. "/" .. dy .. "/" .. bar:GetHeight())
    end
    if width < 600 then
        local _, _, _, _, axisY = bar.axisY:GetPoint(1)
        local _, _, _, _, actionY = bar.openButton:GetPoint(1)
        assert(-actionY >= -axisY + bar.axisY:GetHeight() + 4, "narrow toolbar action buttons overlap X/Y inputs")
    else
        assert(ToolbarLeft(bar.axisY) + bar.axisY:GetWidth() <= ToolbarLeft(bar.resetButton), "wide toolbar actions overlap X/Y inputs")
    end
    for _, target in ipairs({ targets.body, targets.header, targets.title, targets.timer, targets.buttons.session, icon, barHit,
        targets.rows[1].name, targets.rows[1].value }) do
        E.Select(preview, target)
        local _, _, _, _, chipsY = preview.chips:GetPoint(1)
        local reserved = preview.selectionHeight + preview.propertiesHeight + 8
        assert(-chipsY == reserved, "property panel overlaps the preview layers")
        local footerBottom = ui.header:GetTop() - preview.footer:GetBottom()
        assert(footerBottom <= ui.header:GetHeight(), "preview footer escapes the fixed header")
    end
end
E.Select(preview, icon)
-- Early combat event fires while native lockdown still reports false.
local beforeCombat = c.iconOffsetX
owner:GetScript("OnEvent")(owner, "PLAYER_REGEN_DISABLED")
UserSet(preview.properties.grid.controls.size, 17)
preview.properties.reset:GetScript("OnClick")(preview.properties.reset, "LeftButton")
assert(not deps.WriteOffsets(owner, icon, 99, 99), "early combat wrote icon offsets")
assert(c.iconOffsetX == beforeCombat and c.iconSize == 0, "early combat wrote icon settings")
owner:GetScript("OnEvent")(owner, "PLAYER_REGEN_ENABLED")
E.Select(preview, handle)
world.widgets:AdvanceTime(1)
owner:GetScript("OnEvent")(owner, "PLAYER_REGEN_DISABLED")
assert(not Capturing(), "combat retained keyboard capture")
handle:GetScript("OnKeyDown")(handle, "RIGHT")
assert(c.nameOffsetX == beforeX, "combat nudge changed settings")
owner:GetScript("OnEvent")(owner, "PLAYER_REGEN_ENABLED")
handle:GetScript("OnMouseDown")(handle, "LeftButton")
assert(preview.kit.drag and Capturing(), "a press on a selected element did not start a drag with the keyboard")
owner:GetScript("OnHide")(owner)
assert(not preview.kit.drag and not Capturing(), "hidden preview retained a drag or keyboard capture")
for _, target in ipairs(preview.handles) do assert(not target:GetScript("OnUpdate"), "preview introduced polling") end
print("meter preview editor: exact controls/highlights, lazy tabs, drag/scale, windows, layers and lifecycle passed (" .. flavor .. ")")
