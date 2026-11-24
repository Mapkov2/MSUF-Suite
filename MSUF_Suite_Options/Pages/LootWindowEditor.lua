local _, P = ...
-- The minimal loot window preview's element editor (Pages/QoLLayerEditor.lua):
-- the background lies under the rows; each other layer covers its element in
-- every sample row, and a drag moves that element in all of them.
local S, Tr = P.S, P.Tr
local ID = "lootWindow"
local APPEARANCE = {
    look = true, scale = true, font = true, fontOutline = true, fontRendering = true,
    fontShadow = true, fontShadowOpacity = true, fontShadowDistance = true,
}

local function Region(view, key)
    if key == "background" then return view.panel end
    return view.bounds and view.bounds[key]
end

local editor = P.QoLLayerEditor(ID, {
    view = "suiteLootWindowPreview", region = Region, behind = 1, initial = "icon", offsets = true,
    previewLayers = true,
    move = function(view, key, x, y) S.MoveLootWindowPreviewLayer(view, key, x, y) end,
    hide = function(stage) S.HideLootWindowPreview(stage) end,
})
P.LootWindowEditor = editor

local function Panel(parent, width)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(width + 32)
    return panel
end

local function Tabs(ctx, parent, page, width, y, values, panels, onHeight)
    local picker = { ctx = ctx, header = parent, width = width + 32, selected = values[1].value,
        spec = { page = page, module = ID } }
    local row, choose
    local lastTop, lastBottom
    local function Layout()
        local top = y - row:GetHeight() - 10
        if top ~= lastTop then
            lastTop = top
            for _, panel in pairs(panels) do
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
            end
        end
        local bottom = top - panels[picker.selected]:GetHeight()
        if bottom ~= lastBottom then
            lastBottom = bottom
            onHeight(bottom)
        end
        return bottom
    end
    local function ShowSelected()
        for key, panel in pairs(panels) do panel:SetShown(picker.selected == key) end
    end
    row, choose = P.MenuWorkspace.WrappingTabs(picker, values, function(key)
        picker.selected = key
        ShowSelected()
        Layout()
        return true
    end)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    row:HookScript("OnSizeChanged", Layout)
    ShowSelected()
    Layout()
    return function(key) if key ~= picker.selected then choose(key) end end, Layout
end

local function Caption(panel, label, width, y)
    local title = P.Text(panel, label, 16, y, width, P.T.colors.text)
    return y - math.max(16, math.ceil(title:GetStringHeight() or 16)) - 8
end

local function Visibility(workspace, panel, rule, caption, y, prepare)
    local ctx, page, section = workspace.ctx, workspace.page, workspace.section
    local row = P.RuleRow(page, ID, rule, nil, section)
    local nextY = Caption(panel, caption, workspace.width - 64, y)
    local toggle = P.W.SwitchAt(panel, Tr(rule.label), workspace.width - 36, y, 0, "HIDDEN")
    P.M.BindBoolWidget(ctx, toggle, row.get, function(value)
        if P.RuleEnabled(ID, rule, nil, false, true) then row.set(value) end
    end, row)
    local entries = { { rule = rule, widget = toggle } }
    P.GateControls(ctx, ID, entries, nil, true)
    workspace.register(entries, prepare)
    return nextY - 4
end

local function Grid(workspace, panel, rules, y, prepare)
    local bottom, entries = P.RuleGrid(workspace.ctx, panel, workspace.page, ID, rules, y,
        workspace.width, nil, workspace.section, nil, nil, true)
    workspace.register(entries, prepare)
    return bottom
end

local function LayerPanel(workspace, panel, layer, y, caption, prepare, appearance)
    y = Visibility(workspace, panel, layer.rules[1], caption, y, prepare)
    if appearance then y = Caption(panel, "Appearance", workspace.width, y - 6) end
    local rules = {}
    for index = 2, #layer.rules do rules[#rules + 1] = layer.rules[index] end
    return Grid(workspace, panel, rules, y, prepare)
end

local function BuildGeneral(workspace, general, showGeneral)
    local width = workspace.width
    local style, window, feed = Panel(general, width), Panel(general, width), Panel(general, width)
    local select
    local function Prepare(key)
        return function()
            showGeneral()
            select(key)
        end
    end
    local prepareStyle = Prepare("appearance")
    local styleRules = P.SectionRules(ID, "loot_window", function(rule) return APPEARANCE[rule.key] end)
    local windowRules = P.SectionRules(ID, "loot_window", function(rule) return not APPEARANCE[rule.key] end)
    local y = Grid(workspace, style, styleRules, 0, prepareStyle)
    style:SetHeight(-LayerPanel(workspace, style, editor.layers[1], y - 10, "Background", prepareStyle))
    window:SetHeight(-Grid(workspace, window, windowRules, 0, Prepare("window")))
    feed:SetHeight(-Grid(workspace, feed, P.SectionRules(ID, "loot_feed"), 0, Prepare("feed")))
    select = Tabs(workspace.ctx, general, workspace.page, width, 0, {
        { value = "appearance", text = Tr("Appearance") },
        { value = "window", text = Tr("Loot window") },
        { value = "feed", text = Tr("Loot feed") },
    }, { appearance = style, window = window, feed = feed }, function(bottom) general:SetHeight(-bottom) end)
    return select
end

function editor.BuildSettings(ui, parent, y, width, page, section, register, buildFooter, resize)
    local workspace = { ctx = ui.ctx, page = page, section = section, width = width, register = register }
    local values, panels = { { value = "general", text = Tr("General") } }, { general = Panel(parent, width) }
    local select
    local general = BuildGeneral(workspace, panels.general, function() select("general") end)
    for _, layer in ipairs(editor.layers) do
        if not layer.fixed then
            local key = layer[1]
            local panel = Panel(parent, width)
            local prepare = function() select(key) end
            values[#values + 1] = { value = key, text = Tr(layer[2]) }
            panels[key] = panel
            panel:SetHeight(-LayerPanel(workspace, panel, layer, 0, "Visibility", prepare, true))
        end
    end
    local footer = Panel(parent, width)
    local footerBottom = buildFooter(footer)
    footer:SetHeight(-footerBottom)
    local layout, onResize
    select, layout = Tabs(ui.ctx, parent, page, width, y, values, panels, function(bottom)
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, bottom - 8)
        if onResize then onResize(bottom - 8 + footerBottom) end
    end)
    panels.general:HookScript("OnSizeChanged", layout)
    ui.openLayerSettings = function(key)
        if key == "background" then
            general("appearance")
            select("general")
        else
            select(key)
        end
    end
    onResize = resize
    return layout() - 8 + footerBottom
end
