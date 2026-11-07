local _, P = ...
local L, Interaction = {}, P.PreviewInteraction
P.ChatPreviewLayers = L

local LAYERS = {
    { "window", "Window", "window", "lockWindowPosition" },
    { "tabs", "Tabs and accent", "tabs", "tabHeight" },
    { "text", "Messages", "text", "fontSize" },
    { "input", "Input line", "input", "inputWidth" },
    { "sidebar", "Sidebar", "sidebar", "sidebarPanel" },
    { "clock", "Clock", "tabs", "headerClock" },
    { "tools", "Buttons", "tools", "copyMessages" },
}

-- Only remember regions we hid. Undo the mask before the shared painter or a
-- layer toggle so settings still decide which art exists in the preview.
function L.Restore(ui)
    for index = #ui.masked, 1, -1 do
        ui.masked[index]:Show()
        ui.masked[index] = nil
    end
end

local function Mask(ui, region)
    if region and region:IsShown() then
        ui.masked[#ui.masked + 1] = region
        region:Hide()
    end
end

function L.Paint(ui)
    local parts, layers = ui.parts, ui.layers
    local visual = parts.visual
    if layers.window == false then
        Mask(ui, ui.targets.window)
        if visual then
            Mask(ui, visual.panel)
            Mask(ui, visual.gradientLeft)
            Mask(ui, visual.gradientRight)
            for _, edge in ipairs(visual.edges) do Mask(ui, edge) end
        end
    end
    if layers.tabs == false then
        Mask(ui, parts.tabGroup)
        Mask(ui, parts.strip)
        Mask(ui, visual and visual.headerRule)
    end
    if layers.text == false then
        Mask(ui, parts.textClip)
        for _, handle in ipairs(ui.messageHandles) do Mask(ui, handle) end
    end
    if layers.input == false then Mask(ui, parts.input) end
    if layers.sidebar == false then Mask(ui, parts.sidebar) end
    if layers.clock == false and visual and visual.headerClock then
        Mask(ui, visual.headerClock)
        Mask(ui, ui.extraLinks and ui.extraLinks[visual.headerClock])
    end
    if layers.tools == false then
        Mask(ui, parts.copy)
        Mask(ui, parts.toolbar)
        Mask(ui, parts.resizeGrip)
    end
    Interaction.RefreshLayerRail(ui)
end

function L.Layout(ui, offset)
    local chips, width = ui.chips, ui.width
    chips:ClearAllPoints()
    chips:SetPoint("TOPLEFT", ui.viewport, "BOTTOMLEFT", 0, -8 - offset)
    if ui.layerWidth ~= width then
        ui.layerWidth = width
        Interaction.LayoutLayerRail(ui, width)
    end
    return chips:GetHeight() + 8
end

function L.Build(ui, toggle, open)
    ui.layers, ui.masked = {}, {}
    Interaction.BuildLayerRail(ui, ui.header, LAYERS, toggle, function(spec)
        if spec[1] == "tools" and P.Get("chat", "headerToolbar") then
            return open({ section = "tabs", control = "headerToolbar" })
        end
        return open({ section = spec[3], control = spec[4] })
    end)
end
