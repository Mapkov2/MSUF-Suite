local root = assert(arg[1])
arg[4] = "fixture"
local F = assert(loadfile(root .. "/tools/tests/suite_menu_geometry_contract.lua"))()
local pack = dofile(root .. "/tools/tests/suite_test_support.lua").SuitePack(root, "ruRU")
local function Noop() end
local mode = "expert"
local fontScale = 1
local widths = {
    [pack["Guided"]] = 52, [pack["Addon skins"]] = 135, [pack.Controls] = 137,
}
local options = { ui = {}, widgetStates = {} }
local skin = { ColorOrder = {}, PaletteLabels = {}, IsCombatLocked = function() return false end,
    MenuMotion = { Track = Noop }, ContentMotion = { Play = Noop } }
local english
assert(loadfile(root .. "/MSUF_Suite_Skin/Locales/enUS.lua"))("MSUF_Suite_Skin", {
    RegisterLocale = function(_, values) english = values end,
})
skin.L = setmetatable({}, { __index = function(_, key)
    local source = english[key] or key
    return pack[source] or source
end })
local private = { NS = skin, Options = options }
local env = setmetatable({ _G = { MSUF2 = F.M } }, { __index = F.env })
local function Load(path)
    local chunk = assert(loadfile(root .. "/MSUF_Suite_Skin_Options/" .. path))
    setfenv(chunk, env)
    chunk("MSUF_Suite_Skin_Options", private)
end
Load("Shell/Widgets.lua")
local buttons, definitions = {}, {}
local function Frame(parent) return F.env.CreateFrame("Frame", nil, parent) end
function options.CreateText(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetText(text)
    function label:GetUnboundedStringWidth()
        local value = self:GetText()
        return (widths[value] or #value * 5) * fontScale
    end
    return label
end
function options.CreateButton(parent, text, width, height, click, role)
    local button = Frame(parent)
    button:SetSize(width, height)
    options.widgetStates[button] = { label = options.CreateText(button, text), role = role }
    buttons[text] = button
    return button
end
options.CreatePanel, options.CreateSearchBox, options.CreateDropdown = Frame, Frame, Frame
options.TrackRefresh, options.RefreshAll, options.CloseDropdown, options.SetButtonActive = Noop, Noop, Noop, Noop
options.CreateSectionTitle, options.CreateColorRow = Noop, Noop
function options.TrackAndRefresh(callback) callback() end
function options.GetMode() return mode end
function options.SetMode(value) mode = value end
function options.RegisterPage(key, label, builder) definitions[key] = { label = label, builder = builder } end
function options.GetPageDefinition(key) return definitions[key] end
function options.GetPageMeta() return {} end
function options.BuildPage(page, _, builder) builder(page) return true end
local scrollHost
function options.CreateScrollContainer(host)
    scrollHost = host
    return host, Frame(host)
end
options.RegisterPage("dashboard", skin.L.DASHBOARD, Noop)
options.RegisterPage("addonSkins", skin.L["Addon skins"], Noop)
Load("Pages/Colors.lua")
Load("Shell/Embedded.lua")

local host = assert(options.Mount(Frame(F.env.UIParent), 1040, 600))
local function Fits(button)
    return button:GetWidth() - 20 >= options.widgetStates[button].label:GetUnboundedStringWidth()
end
assert(Fits(host.buttons.addonSkins) and Fits(buttons[skin.L.Guided]), "localized embedded navigation captions clip")
assert(host:ShowPage("colors"))
local page = host.pages.colors
page:SetWidth(665)
F.MenuWorld.FireScript(page, "OnSizeChanged", 665, 500)
assert(Fits(buttons[skin.L.Controls]), "localized color-group caption clips")
local _, _, _, _, y = scrollHost:GetPoint(1)
assert(y < -192, "wrapped color groups overlap the color list")
local previous = host.rail:GetWidth()
fontScale = 1.18
F.M.Theme.RefreshTabLayouts(true)
assert(host.rail:GetWidth() > previous and Fits(host.buttons.addonSkins), "retained Skinning rail did not fit after zoom")
assert(Fits(buttons[skin.L.Controls]), "retained color selector clipped after zoom")
print("PASS localized Skinning rail and wrapped color selector")
