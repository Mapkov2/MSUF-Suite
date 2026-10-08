-- Real options fixtures: selection lifecycle, navigation and old host support.
local root = assert(arg[1], "repository root required")
local originalLoad, P = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    if path:match("/Menu/PreviewInteraction%.lua$") then
        return function(addon, namespace) P = namespace; return chunk(addon, namespace) end
    end
    return chunk
end
assert(originalLoad(root .. "/tools/tests/suite_options_menu_contract.lua"))()
loadfile = originalLoad
local I = assert(P and P.PreviewInteraction, "preview selection owner is absent")
local T, M = P.T, P.M
local ctx = { refreshers = {} }
local parent = CreateFrame("Frame", nil, UIParent)
local first, second = CreateFrame("Button", nil, parent), CreateFrame("Button", nil, parent)
local clicks = 0
T.colors.accent = { .12, .23, .34 }
local tooltips, addTooltip, create = {}, M.AddTooltip, CreateFrame
M.AddTooltip = function(owner, title, help)
    assert(owner.kind == "Frame" or owner.kind == "Button", "help is attached to a non-interactive FontString")
    tooltips[#tooltips + 1] = { owner = owner, title = title, help = help }
end
CreateFrame = function(...)
    local widget = create(...)
    function widget:EnableMouse(value) self._testMouseEnabled = value end
    return widget
end
local bar = I.Bar(ctx, parent, 400, "Sample values. Click a data text to edit it.")
assert(bar._testMouseEnabled and #tooltips == 2 and tooltips[1].owner == bar
    and tooltips[2].owner == bar.button, "sample help is inaccessible on its footer hit areas")
M.AddTooltip, CreateFrame = addTooltip, create
assert(not bar.button.enabled, "an empty preview offered a settings action")
I.Select(bar, first, "Minimap", function() clicks = clicks + 1 end)
assert(bar.button.enabled and first._suitePreviewSelectionEdges[1]:IsShown(), "selection lacks feedback")
bar.button:GetScript("OnClick")(bar.button)
assert(clicks == 1, "selection action lost its navigation callback")
local edges = first._suitePreviewSelectionEdges
I.Select(bar, second, "Data texts", function() clicks = clicks + 10 end, 3)
assert(not edges[1]:IsShown() and second._suitePreviewSelectionEdges[1]:IsShown(), "selection kept two outlines")
assert(second._suitePreviewSelectionEdges[1]:GetHeight() == 3, "scaled samples lost their marker thickness")
T.colors.accent = { .71, .62, .53 }
I.Refresh(bar)
local r, g, b = unpack(second._suitePreviewSelectionEdges[1].color)
assert(r == .71 and g == .62 and b == .53, "existing marker did not follow a palette edit")
bar:GetScript("OnHide")(bar)
assert(not second._suitePreviewSelectionEdges[1]:IsShown(), "hidden preview retained its marker")
bar:GetScript("OnShow")(bar)
assert(second._suitePreviewSelectionEdges[1]:IsShown(), "returning preview lost selection feedback")
second:Hide()
I.Refresh(bar)
assert(not bar.button.enabled and bar._suitePreviewTarget == nil, "hidden element retained an actionable selection")
bar.button:GetScript("OnClick")(bar.button)
assert(clicks == 1, "a stale element still opened settings")
I.Select(bar, first, "Minimap", function() clicks = clicks + 100 end)
assert(first._suitePreviewSelectionEdges == edges, "selection allocated fresh markers on every click")
I.Select(bar, nil)
assert(not edges[1]:IsShown() and not bar.button.enabled, "explicit deselection retained action or outline")
local chrome, tooltip = M.PreviewHelpers, M.AddTooltip
M.PreviewHelpers, M.AddTooltip = nil, nil
local older = I.Bar({ refreshers = {} }, parent, 240)
I.Select(older, first, "Minimap", function() clicks = clicks + 100 end)
older.button:GetScript("OnClick")(older.button)
assert(clicks == 101, "older host helpers prevented navigation")
M.PreviewHelpers, M.AddTooltip = chrome, tooltip
for _, width in ipairs({ 184, 240, 400, 520 }) do
    local narrow = I.Bar({ refreshers = {} }, parent, width)
    -- The real fixture's Theme.Button ignores size args; inspect layout
    -- with an explicit native-like button factory for the long-label case below.
    assert(narrow:GetWidth() == width and narrow.label:GetWidth() > 0, "selection row exceeds a narrow canvas")
end
local font, button = T.Font, T.Button
T.Font = function(...)
    local label = font(...)
    label:SetText("Einstellungen öffnen")
    return label
end
T.Button = function(owner, text, width, height)
    local control = button(owner, text)
    control:SetSize(width, height)
    return control
end
local long = I.Bar({ refreshers = {} }, parent, 320)
assert(long.button:GetWidth() >= #"Einstellungen öffnen" * 7 + 28, "localized settings action is clipped")
assert(long.label:GetWidth() + long.button:GetWidth() + 28 <= long:GetWidth(), "localized selection label overlaps action")
T.Font, T.Button = font, button
-- The real DataTexts view follows external editor selection too.
local data = P.S.Config("dataTexts")
data.bar1Slot1, data.bar1Slot2, data.bar1Enabled = 2, 3, true
local chosen
local view = P.DataTextsPreview.Build({ refreshers = {} }, parent, 1,
    { config = data, onSelect = function(slot) chosen = slot end })
view.slots[1]:GetScript("OnClick")(view.slots[1])
view:SetSelectedSlot(2)
view.selection.button:GetScript("OnClick")(view.selection.button)
assert(chosen == 2 and view.selection._suitePreviewTarget == view.slots[2], "external slot selection left the settings action stale")
assert(not view.slots[1]._suitePreviewSelectionEdges[1]:IsShown(), "external slot selection left its former marker")
data.bar1Slot2 = 0
view:Refresh()
assert(not view.selection.button.enabled, "removed data source kept a stale selection action")
assert(not view.host.scripts.OnUpdate and not bar.scripts.OnUpdate, "preview selection introduced polling")
-- Paint may hide the selected ActionBar tile after the earlier row refresh.
local config = P.S.Config("actionbars")
config.bar1Buttons, config.bar1ShowEmpty = 2, true
local actionCtx = { refreshers = {} }
P.ActionBarPreview.Build(actionCtx, parent, -20, 520, 200, function() return 1 end)
local action = actionCtx._msufSuiteActionBarPreview
for _, refresh in ipairs(actionCtx.refreshers) do refresh() end
I.Select(action.selection, action.tiles[2], "Action buttons", function() end)
config.bar1Buttons = 1
for _, refresh in ipairs(actionCtx.refreshers) do refresh() end
assert(not action.tiles[2]:IsShown() and not action.selection.button.enabled
    and action.selection._suitePreviewTarget == nil, "hidden action tile retained an actionable selection")
print("preview interactions: real navigation, selection, palette, lifecycle, old host and data editor checks passed")
