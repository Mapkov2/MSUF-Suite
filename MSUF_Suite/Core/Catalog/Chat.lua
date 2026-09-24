local _, NS = ...
local B = NS.CatalogBuild

local function Available()
    if not NS.Client.isMainline then
        return false, "Chat styling is available in Retail and Forever"
    end
    local frame = _G.ChatFrame1
    if not frame or type(frame.CreateTexture) ~= "function" then
        return false, "Blizzard chat is not ready"
    end
    return true
end

B.Module("chat", {
    title = "Chat",
    description = "Style Blizzard's native chat windows, tabs and input line. Links, channels, filters, docking and message delivery remain Blizzard-owned.",
    page = "suite_chat", optIn = true, available = Available,
    conflicts = { "EllesmereUIChat", "ElvUI" },
})

local id = "chat"
local midnight = {
    panelColor = "0a1220", panelAlpha = 74,
    borderColor = "41627a", borderAlpha = 78, borderSize = 1,
    accentColor = "57c7df", accentAlpha = 88,
    tabActiveColor = "f4f7fb", tabInactiveColor = "aab5c2",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true,
    inputColor = "0a1522", inputAlpha = 86,
    padding = 4, fontSize = 0,
}
local midnightDark = {
    panelColor = "151719", panelAlpha = 82,
    borderColor = "575b58", borderAlpha = 78, borderSize = 1,
    accentColor = "b9ab86", accentAlpha = 78,
    tabActiveColor = "e9e9e4", tabInactiveColor = "b9bdb9",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true,
    inputColor = "111315", inputAlpha = 88,
    padding = 4, fontSize = 0,
}
local forever = {
    panelColor = "14181b", panelAlpha = 77,
    borderColor = "9f8960", borderAlpha = 85, borderSize = 1,
    accentColor = "d8b66a", accentAlpha = 92,
    tabActiveColor = "f1e3c4", tabInactiveColor = "d4dce2",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true,
    inputColor = "111517", inputAlpha = 88,
    padding = 4, fontSize = 0,
}

NS.ChatLookPresets = { [1] = midnight, [2] = midnightDark, [3] = forever }
NS.ChatLookVisualKeys = {}
for key in pairs(midnight) do NS.ChatLookVisualKeys[key] = true end
local initial = NS.Client.isForever and forever or midnightDark

B.Section(id, "look", "Choose a look", {
    B.Choice("look", "Style preset", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom" }),
})
B.Section(id, "window", "Chat window", {
    B.Color("panelColor", "Background color", initial.panelColor),
    B.Number("panelAlpha", "Background opacity (percent)", initial.panelAlpha, 0, 100, 5),
    B.Color("borderColor", "Border color", initial.borderColor),
    B.Number("borderAlpha", "Border opacity (percent)", initial.borderAlpha, 0, 100, 5),
    B.Number("borderSize", "Border thickness", initial.borderSize, 0, 4),
    B.Number("padding", "Background padding", initial.padding, 0, 16),
})
B.Section(id, "tabs", "Tabs and accent", {
    B.Bool("tabPanel", "Dark tab strip", initial.tabPanel),
    B.Bool("tabAccent", "Underline chat tabs", initial.tabAccent),
    B.Color("tabActiveColor", "Active tab text", initial.tabActiveColor),
    B.Color("tabInactiveColor", "Other tab text", initial.tabInactiveColor),
    B.Color("accentColor", "Accent color", initial.accentColor),
    B.Number("accentAlpha", "Accent opacity (percent)", initial.accentAlpha, 0, 100, 5),
})
B.Section(id, "sidebar", "Button sidebar", {
    B.Bool("sidebarPanel", "Use MSUF chat icons and button sidebar", initial.sidebarPanel),
    B.Number("sidebarWidth", "Sidebar width", initial.sidebarWidth, 20, 48),
})
B.Section(id, "input", "Input line", {
    B.Bool("inputPanel", "Show input background", initial.inputPanel),
    B.Color("inputColor", "Input background color", initial.inputColor),
    B.Number("inputAlpha", "Input opacity (percent)", initial.inputAlpha, 0, 100, 5),
})
B.Section(id, "text", "Message text", {
    B.Number("fontSize", "Font size (0: follow Blizzard / MSUF Fonts)", 0, 0, 24),
    B.Font("font", "Message font (default: follow Blizzard / MSUF Fonts)"),
    B.Choice("fontOutline", "Text outline", 1, { "Follow Blizzard", "Outline", "Thick outline", "None" }),
    B.Choice("fontRendering", "Font rendering", 3, { "Smooth", "Sharp / pixel", "Slug" }),
    B.Choice("fontShadow", "Text shadow", 1, { "Follow Blizzard", "On", "Off" }),
    B.Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    B.Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
})
local textRules = NS.SuiteCatalog[id].rules
textRules.font.defaultLabel = "Blizzard / MSUF Fonts (default)"
for _, key in ipairs({ "fontShadowOpacity", "fontShadowDistance" }) do
    textRules[key].requiresChoice = { key = "fontShadow", values = { [2] = true } }
end
