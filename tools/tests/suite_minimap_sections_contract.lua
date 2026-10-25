local root = assert(arg[1])
local originalLoad, override = loadfile, os.getenv("MINIMAP_SECTIONS_SOURCE")
if override then
    loadfile = function(path)
        return originalLoad(path:match("/Pages/MinimapSections%.lua$") and override or path)
    end
end
SUITE_OPTIONS_FIXTURE = true
local F = assert(loadfile(root .. "/tools/tests/suite_options_menu_contract.lua"))()
SUITE_OPTIONS_FIXTURE = nil
loadfile = originalLoad
local P, M, S = F.optionsNS, F.M, F.S
local attachReset = P.AttachSectionReset
P.AttachSectionReset = function(ctx, body, title, reset, copy, extend)
    local result = attachReset(ctx, body, title, reset, copy, extend)
    if extend then
        local popup = F.Widget("ResetPopup")
        popup.heading = F.Widget("FontString")
        function popup:Show()
            local entering = not self.shown
            self.shown = true
            if entering and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        extend(popup)
    end
    return result
end
local function Check(value, message) assert(value, message) end
local function Widget(ctx, key)
    for _, widget in ipairs(ctx.widgets) do
        if widget.meta and widget.meta.settingKey == "msufsuite.minimap." .. key then return widget end
    end
end
local function Same(config, before)
    for key, value in pairs(config) do Check(before[key] == value, "navigation changed " .. key) end
    for key, value in pairs(before) do Check(config[key] == value, "navigation removed " .. key) end
end
for _, width in ipairs({ 360, 720, 1100 }) do
    local ctx = { key = "suite_minimap", width = width, refreshers = {}, widgets = {}, sections = {},
        pageItems = {}, entry = { sections = {} } }
    F.SetCurrent(ctx)
    M.pages.suite_minimap.build(ctx)
    local menu = assert(ctx.minimapSections, "Minimap needs grouped sections")
    Check(#ctx.sections == 10, "expected nine settings accordions plus the module card")
    Check(ctx.pageItems[1] == "fixed-preview", "preview no longer precedes settings")
    Check(menu.groups.information and menu.groups.buttons and menu.groups.decoration, "group missing")
    local config, before = S.Config("minimap"), {}
    config.enabled = false
    for key, value in pairs(config) do before[key] = value end
    local info = menu.groups.information
    Check(info.views.info_weather == nil, "unselected information controls built eagerly")
    for _, section in ipairs({ "info_clock", "info_fps", "info_location", "info_weather", "info_difficulty", "info_colors" }) do
        Check(menu:SelectMinimapSettings(section), "could not select " .. section)
        Check(info.selected == section and info.views[section].frame:IsShown(), "wrong information editor")
        Check(info.selector:GetWidth() <= width - 32, "selector escapes narrow section")
    end
    Same(config, before)
    local resolver = P.HM.GetMissingSectionResolver(ctx.entry)
    local parent = assert(resolver("suite_minimap_info_clock"), "cold section link did not resolve")
    Check(parent == info.body and info.selected == "info_clock", "section link selected wrong display")
    menu:SelectMinimapSettings("info_weather")
    Check(Widget(ctx, "infoWeather").enabled == false, "new editor ignored initial module gating")
    Check(info.popup, "closed information reset does not name its selected item")
    info.popup.heading:SetText(P.Tr("Information displays"))
    info.popup:Show()
    Check(info.popup.heading.text == P.Tr("Weather"), "reset popup names the wrong display")
    local clock = assert(Widget(ctx, "infoClock24Hour"), "clock setting missing")
    P.HM.GetSearchTargetPrepare(clock)()
    Check(info.selected == "info_clock", "warm search did not select clock")
    Check(info.popup.heading.text == P.Tr("Clock"), "open reset popup kept a stale selected display")
    local fps = assert(F.registeredControls["menu2.suite_minimap.minimap.preview.infoFPS"])
    fps.scripts.OnClick(fps, "LeftButton")
    Check(info.selected == "info_fps", "clicking the preview did not select its information editor")
    menu:SelectMinimapSettings("info_weather")
    config.infoWeatherSize, config.infoClockSize = 21, 19
    config.infoWeatherX, config.infoClockX = 45, 63
    Check(info.body._msufSuiteSectionReset(), "selected display reset failed")
    Check(config.infoWeatherSize == P.catalog.minimap.rules.infoWeatherSize.default, "selected display not reset")
    Check(config.infoClockSize == 19, "reset changed a different display")
    Check(config.infoWeatherX == P.catalog.minimap.rules.infoWeatherX.default, "selected offsets not reset")
    Check(config.infoClockX == 63, "reset changed another display's position")
    local combat, selected = P.Combat, info.selected
    P.Combat = function() return true end
    Check(not menu:SelectMinimapSettings("info_durability"), "combat selection built a new editor")
    Check(info.selected == selected, "combat refusal changed the current editor")
    Check(menu:SelectMinimapSettings("info_clock"), "combat blocked an existing read-only editor")
    Check(info.selected == "info_clock", "combat selected the wrong existing editor")
    P.Combat = combat
    local function Focus(section)
        return assert(menu:ResolveMinimapSection(section), "preview link did not resolve")
    end
    Check(Focus("style_presets") == menu.sections.style_presets, "ordinary preview fallback was lost")
    Check(Focus("info_fps") == info.body and info.selected == "info_fps", "preview did not select FPS")
    local decoration = menu.groups.decoration
    Check(Focus("style_glow") == decoration.body and decoration.selected == "style_glow", "glow preview route wrong")
    local buttons = menu.groups.buttons
    Check(Focus("dungeon") == buttons.body and buttons.selected == "dungeon", "group finder preview route wrong")
    if P.Suite.Client.isForever then
        Check(not menu:SelectMinimapSettings("specialization"), "Forever has a specialization editor")
    else
        Check(menu:SelectMinimapSettings("specialization"), "Retail lost specialization settings")
    end
    Check(F.registeredControls["menu2.suite_minimap.minimap.style.preset.12"], "Class Style tile is missing")
    for _, fn in ipairs(ctx.refreshers) do fn() end
end
print("Minimap grouped sections: nine accordions, narrow widths, lazy editors, exact routes and scoped reset passed")
