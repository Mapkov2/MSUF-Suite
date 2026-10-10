local root = assert(arg[1])
local original, ui, P = loadfile
loadfile = function(path)
    local target = path
    local baseline, file = os.getenv("MINIMAP_LAYER_BASELINE"), os.getenv("MINIMAP_LAYER_FILE")
    if baseline and path == root .. "/" .. file then target = baseline .. "/" .. file end
    local chunk = assert(original(target))
    if path:match("/Pages/MinimapPreview%.lua$") then
        return function(addon, namespace)
            P = namespace
            local register = P.M.RegisterControlMetadata
            P.M.RegisterControlMetadata = function(widget, ...)
                if type(rawget(widget, "previewUI")) == "table" and widget.previewUI.state then ui = widget.previewUI end
                return register(widget, ...)
            end
            chunk(addon, namespace)
            local helperRoot = os.getenv("MINIMAP_HELPER_ROOT")
            if helperRoot then
                local shared = { Fallbacks = { Identity = function(value) return value end } }
                assert(original(helperRoot .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))(
                    "MSUF", { MSUF2 = shared, UF = { Clamp01 = function(value, fallback) return value or fallback end } })
                local H = shared.PreviewHelpers
                local layerHelpers = { CreateLayerButton = H.CreateLayerButton, LayerChipButtonOpts = H.LayerChipButtonOpts,
                    PreviewChromePalette = H.PreviewChromePalette, ApplyPreviewChrome = H.ApplyPreviewChrome,
                    FlowLayerChips = H.FlowLayerChips, RefreshSelectedLayerButtons = H.RefreshSelectedLayerButtons }
                local build = P.BuildMinimapPreview
                P.BuildMinimapPreview = function(...)
                    local previous = P.M.PreviewHelpers
                    P.M.PreviewHelpers = layerHelpers
                    build(...)
                    P.M.PreviewHelpers = previous
                end
            end
        end
    end
    return chunk
end
assert(original(root .. "/tools/tests/suite_options_menu_contract.lua"))()
loadfile = original
assert(ui, "minimap preview did not build")
local buttons = {}
for _, button in ipairs(ui.layerButtons) do buttons[button.key] = button end
local config = P.S.Config("minimap")
for key in pairs(ui.state.layers) do ui.state.layers[key] = true end
ui.state.layers.guides, ui.state.layers.hidden = false, false
for _, item in ipairs(ui.textItems) do config["info" .. item.spec[1]] = true end
ui.Paint()
for _, item in ipairs(ui.textItems) do
    local key = item.spec[1] == "Difficulty" and "difficultyText" or item.spec[3]
    local button = assert(buttons[key], "missing individual text layer: " .. key)
    assert(item.button:IsShown(), "enabled text missing from preview")
    button:GetScript("OnClick")(button, "LeftButton")
    assert(not item.button:IsShown(), "individual layer does not hide " .. key)
    for _, other in ipairs(ui.textItems) do
        if other ~= item then assert(other.button:IsShown(), "text layer hides a sibling") end
    end
    assert(config["info" .. item.spec[1]], "preview layer mutated runtime settings")
    button:GetScript("OnClick")(button, "LeftButton")
    assert(item.button:IsShown(), "individual layer does not restore " .. key)
    assert(item.button._previewLayerKey == key, "selection highlights the wrong layer")
end
buttons.text:GetScript("OnClick")(buttons.text, "LeftButton")
for _, item in ipairs(ui.textItems) do assert(not item.button:IsShown(), "text master lost its children") end
buttons.text:GetScript("OnClick")(buttons.text, "LeftButton")
assert(ui.art.arrow:IsShown(), "player arrow is missing")
buttons.player:GetScript("OnClick")(buttons.player, "LeftButton")
assert(not ui.art.arrow:IsShown(), "player arrow layer does not hide the arrow")
assert(ui.art.clip:IsShown(), "player arrow layer also hid the map")
buttons.player:GetScript("OnClick")(buttons.player, "LeftButton")
for _, key in ipairs({ "tracking", "calendar", "mail", "crafting", "compartment", "difficulty", "zoom", "compass" }) do
    assert(buttons[key], "native minimap component has no layer: " .. key)
end
for _, item in ipairs(ui.iconItems) do
    local key = item.spec[1]
    local layer = key == "drawer" and "addons" or key
    assert(buttons[layer], "icon has no layer: " .. key)
    buttons[layer]:GetScript("OnClick")(buttons[layer], "LeftButton")
    assert(not item.button:IsShown(), "icon layer does not hide " .. key)
    buttons[layer]:GetScript("OnClick")(buttons[layer], "LeftButton")
end
local focused
P.W.FocusCollapsibleSection = function(section) focused = section.sectionId end
for key, section in pairs({clock="info_clock",fps="info_fps",latency="info_latency",coordinates="info_coordinates",durability="info_durability",location="info_location",weather="info_weather",difficultyText="info_difficulty",zoom="behavior",compass="behavior"}) do
    focused = nil
    buttons[key]:GetScript("OnClick")(buttons[key], "RightButton")
    assert(focused == "suite_minimap_" .. section, "layer opened the wrong settings: " .. key)
end
for _, handle in ipairs(ui.handles) do
    if handle._key:match("^ornament_") then assert(handle._previewLayerKey == "ornament", "artwork selection lost its layer") end
end
for _, width in ipairs({ 420, 720, 1200 }) do
    ui.body:SetWidth(width)
    ui.LayoutLayers()
    for _, button in ipairs(ui.layerButtons) do
        local x = button.points[1][4]
        assert(x + button:GetWidth() <= width, "minimap layer escapes narrow rail")
    end
end
print("suite_minimap_preview_layers_contract: passed")
