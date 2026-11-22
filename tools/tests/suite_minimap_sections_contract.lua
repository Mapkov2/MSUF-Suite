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
local function CheckArtworkTransfer(artwork, config, customPath)
    local io = P.Suite.ProfileIO
    local encode, decode = MSUF_EncodeCompactTable, MSUF_TryDecodeCompactString
    local envelope
    MSUF_EncodeCompactTable = function(value, prefix)
        envelope = value
        return prefix .. ":minimap-fixture"
    end
    MSUF_TryDecodeCompactString = function(text)
        Check(text == "MSUF3:minimap-fixture", "unexpected profile payload")
        return envelope
    end
    local art = P.Suite.MinimapStyleTexture
    for _, choice in ipairs({ art.WAYFARER, art.ANTIQUE_MAP_FRAME }) do
        artwork.set(choice)
        local module, imported = io.PrepareModuleProfile(assert(io.ExportModule("minimap")), true)
        Check(module == "minimap" and imported.styleTexture == choice and imported.styleTexturePath == customPath,
            "bundled artwork choice did not survive profile transfer independently of the custom path")
        Check(config.styleTexture == imported.styleTexture, "profile transfer changed the chosen artwork")
    end
    MSUF_EncodeCompactTable, MSUF_TryDecodeCompactString = encode, decode
end
local function CheckArtwork(ctx, menu, config)
    Check(menu:SelectMinimapSettings("style_art"), "Decorative border editor is missing")
    local artwork = assert(Widget(ctx, "styleTexture"))
    local path = assert(Widget(ctx, "styleTexturePath"))
    local scale = assert(Widget(ctx, "styleScale"))
    local art = P.Suite.MinimapStyleTexture
    local wayfarerPath = "Interface\\AddOns\\MSUF_Suite\\Media\\WayfarerMinimapFrame.tga"
    local antiquePath = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\AntiqueMapFrame.tga"
    local values = artwork.row.values
    Check(values[9] and values[9].text == P.Tr("Wayfarer") and values[9].icon == wayfarerPath,
        "Wayfarer needs a direct artwork choice with a thumbnail")
    Check(values[10] and values[10].text == P.Tr("Antique map frame") and values[10].icon == antiquePath,
        "Antique map frame needs a direct artwork choice with a thumbnail")
    for _, choice in ipairs({ art.ARCANE_RING, art.EMBER_RING, art.ASTRAL_RING, art.STEEL_FRAME, art.PARCHMENT_SCROLL }) do
        local icon = values[choice].icon
        Check(type(icon) == "string" and icon == P.Suite.MinimapStyle.paths[choice], "Suite ornament has no texture thumbnail")
    end

    config.enabled = true
    Check(S.SetMany("minimap", { styleTexture = art.CUSTOM, styleTexturePath = wayfarerPath,
        shape = P.Suite.MinimapShape.SQUARE, styleAlpha = 100, styleScale = 100,
        stylePlacement = P.Suite.MinimapStylePlacement.ABOVE }), "could not load the existing Wayfarer artwork")
    M.RequestRefresh()
    local ui = assert(F.registeredControls["menu2.suite_minimap.minimap.preview.map"]).previewUI
    local overlay = ui.art.style.artOver
    Check(path.enabled and overlay:IsShown() and overlay.texture == wayfarerPath, "existing Wayfarer artwork changed")
    local width, height = overlay:GetWidth(), overlay:GetHeight()
    artwork.set(values[9].value)
    M.RequestRefresh()
    Check(config.styleTexture == 9 and overlay.texture == wayfarerPath and overlay:IsShown()
        and overlay:GetWidth() == width and overlay:GetHeight() == height, "Wayfarer choice changed the artwork geometry")
    Check(not path.enabled and scale.enabled, "bundled artwork has the wrong editing controls")
    artwork.set(values[10].value)
    Check(config.styleTexture == 10 and overlay.texture == antiquePath, "antique frame was not painted")
    artwork.set(art.CUSTOM)
    M.RequestRefresh()
    Check(path.enabled and path.get() == wayfarerPath, "selecting a bundled frame lost the custom path")
    local customPath = "Interface\\AddOns\\AnotherAddon\\Art.tga"
    path.set(customPath)
    Check(config.styleTexturePath == customPath and overlay.texture == customPath, "custom path is no longer editable")
    CheckArtworkTransfer(artwork, config, customPath)
end
local function CheckPerformanceColors(menu, config)
    local expected = { "infoGoodColor", "infoWarningColor", "infoBadColor" }
    local original, targetsBySection = {}, {}
    for _, key in ipairs(expected) do original[key] = config[key] end
    for _, section in ipairs({ "info_fps", "info_latency" }) do
        Check(menu:SelectMinimapSettings(section), "missing performance editor: " .. section)
        local shortcut = assert(menu.groups.information.views[section].frame.colorShortcut)
        local targets, byKey = shortcut.options.getTargets(), {}
        Check(#targets == 5 and shortcut.options.maxTargets >= #targets, "performance colors omitted from shortcut")
        for _, target in ipairs(targets) do
            Check(not byKey[target.settingKey], "duplicate contextual color")
            byKey[target.settingKey] = target
        end
        for _, key in ipairs(expected) do
            local target = assert(byKey["msufsuite.minimap." .. key], "missing shared color: " .. key)
            Check(target.sourceSettingKey == target.settingKey, "shared color uses a different search key")
            Check(target.label == P.Tr(P.catalog.minimap.rules[key].label), "shared color label differs from Colors")
        end
        targetsBySection[section] = byKey
    end
    local fps, latency = targetsBySection.info_fps, targetsBySection.info_latency
    for _, enabled in ipairs({ false, true }) do
        local previous = config.infoStatusColors
        config.infoStatusColors = enabled
        for _, key in ipairs(expected) do
            local settingKey = "msufsuite.minimap." .. key
            latency[settingKey].set(0.2, 0.4, 0.6)
            Check(config[key] == "336699", "shortcut wrote a disconnected color")
            local r, g, b = fps[settingKey].get()
            Check(math.abs(r - 0.2) < 0.001 and math.abs(g - 0.4) < 0.001 and math.abs(b - 0.6) < 0.001,
                "FPS does not share the latency color")
            local r0, g0, b0 = P.RGB(original[key])
            fps[settingKey].set(r0, g0, b0)
            Check(config[key] == original[key], "restoring a shared color did not restore its canonical setting")
        end
        config.infoStatusColors = previous
    end
    Check(menu:SelectMinimapSettings("info_clock"), "clock editor missing")
    for _, target in ipairs(menu.groups.information.views.info_clock.frame.colorShortcut.options.getTargets()) do
        Check(not fps[target.settingKey], "clock acquired unrelated performance colors")
    end
end
local function CheckTabs(ctx, workspace, width)
    local expected = { "basics", "appearance", "layout", "buttons", "information" }
    local row = assert(workspace.tabs)
    Check(#row.items == #expected, "Minimap has the wrong number of tabs")
    Check(ctx.pageItems[1] == "fixed-preview" and ctx.pageItems[2] == "fixed-preview",
        "preview and tabs must precede the scrolling sections")
    Check(ctx.fixedPreviews[1].section == workspace.header, "tabs must be docked above the interactive preview")
    Check(ctx.fixedPreviews[2].section.expander, "the second dock must contain the interactive preview")
    Check(workspace.header:GetHeight() >= row:GetHeight() + 24, "tab row exceeds the header")
    Check((row:GetHeight() > 26) == (width == 320), "tab row did not fit the available width")
    for i, id in ipairs(expected) do
        local item = row.items[i]
        Check(item.id == id, "Minimap tab out of order: " .. id)
        item.button.scripts.OnClick()
        Check(workspace.selected == id and workspace.groups[id].frame:IsShown(), "tab click did not reveal " .. id)
        for other, group in pairs(workspace.groups) do
            Check(group.frame:IsShown() == (other == id), "multiple Minimap tabs visible")
        end
    end
    workspace.select("basics")
    Check(workspace.sections.suite_minimap_behavior.title == P.Tr("Map behavior"), "map behavior header has no label")
end

for _, width in ipairs({ 320, 720, 1100 }) do
    local ctx = { key = "suite_minimap", width = width, refreshers = {}, widgets = {}, sections = {},
        pageItems = {}, entry = { sections = {} } }
    F.SetCurrent(ctx)
    M.pages.suite_minimap.build(ctx)
    local menu = assert(ctx.minimapSections, "Minimap needs grouped sections")
    local workspace = assert(ctx.suiteWorkspace, "Minimap needs settings tabs")
    local owned = 0
    for _, section in ipairs(ctx.sections) do
        if section.sectionId:match("^suite_minimap_") then owned = owned + 1 end
    end
    local navigation
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == "suite_minimap_navigation" then navigation = section end
    end
    Check(owned == 11 and navigation, "expected nine settings accordions, the module card and navigation")
    Check(ctx.pageItems[1] == "fixed-preview", "preview no longer precedes settings")
    Check(menu.groups.information and menu.groups.buttons and menu.groups.decoration, "group missing")
    local config, before = S.Config("minimap"), {}
    config.enabled = false
    for key, value in pairs(config) do before[key] = value end
    CheckTabs(ctx, workspace, width)
    Check(menu:SelectMinimapSettings("addons") and workspace.selected == "buttons", "Add-on buttons editor is missing")
    local drawerStyle = assert(Widget(ctx, "drawerStyle"), "drawer style is missing from Minimap's add-on settings")
    local styles = P.Suite.MinimapDrawerStyle
    local values = drawerStyle.row.values
    Check(drawerStyle.rowKind == "dropdown" and #values == 4 and values[styles.DARK].text == P.Tr("Midnight Dark"),
        "drawer style does not offer all palettes")
    drawerStyle.set(styles.DARK)
    Check(config.drawerStyle == styles.DARK, "drawer style editor did not store the selection")
    drawerStyle.set(before.drawerStyle)
    local visibility = assert(Widget(ctx, "drawerMouseover"), "drawer visibility is missing")
    local modes = visibility.row.values
    Check(visibility.rowKind == "dropdown" and visibility.parent == drawerStyle.parent
        and visibility.label == P.Tr("Drawer button visibility")
        and #modes == 2 and modes[1].text == P.Tr("Always") and modes[2].text == P.Tr("Mouseover"),
        "drawer visibility should offer Always and Mouseover next to the style")
    visibility.set(modes[2].value)
    Check(config.drawerMouseover == true and visibility.get() == modes[2].value, "Mouseover lost the saved boolean")
    visibility.set(modes[1].value)
    Check(config.drawerMouseover == false and visibility.get() == modes[1].value, "Always lost the saved boolean")
    visibility.set(before.drawerMouseover and modes[2].value or modes[1].value)
    local info = menu.groups.information
    Check(info.views.info_weather == nil, "unselected information controls built eagerly")
    for _, section in ipairs({ "info_clock", "info_fps", "info_location", "info_weather", "info_difficulty", "info_colors" }) do
        Check(menu:SelectMinimapSettings(section), "could not select " .. section)
        Check(info.selected == section and info.views[section].frame:IsShown(), "wrong information editor")
        Check(info.selector:GetWidth() <= width - 32, "selector escapes narrow section")
    end
    Same(config, before)
    CheckPerformanceColors(menu, config)
    Same(config, before)
    local resolver = P.HM.GetMissingSectionResolver(ctx.entry)
    workspace.select("layout")
    local parent = assert(resolver("suite_minimap_info_clock"), "cold section link did not resolve")
    Check(parent == info.body and workspace.selected == "information" and info.selected == "info_clock",
        "section link selected wrong tab or display")
    menu:SelectMinimapSettings("info_weather")
    Check(Widget(ctx, "infoWeather").enabled == false, "new editor ignored initial module gating")
    Check(info.popup, "closed information reset does not name its selected item")
    info.popup.heading:SetText(P.Tr("Information displays"))
    info.popup:Show()
    Check(info.popup.heading.text == P.Tr("Weather"), "reset popup names the wrong display")
    local clock = assert(Widget(ctx, "infoClock24Hour"), "clock setting missing")
    workspace.select("buttons")
    P.HM.GetSearchTargetPrepare(clock)()
    Check(workspace.selected == "information" and info.selected == "info_clock", "warm search did not reveal clock")
    Check(info.popup.heading.text == P.Tr("Clock"), "open reset popup kept a stale selected display")
    local fps = assert(F.registeredControls["menu2.suite_minimap.minimap.preview.infoFPS"])
    workspace.select("appearance")
    fps.scripts.OnClick(fps, "LeftButton")
    Check(workspace.selected == "information" and info.selected == "info_fps", "preview did not reveal the information editor")
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
    if width == 1100 then
        CheckArtwork(ctx, menu, config)
        Check(menu:SelectMinimapSettings("behavior"), "missing map behavior editor")
        local visibility, arrangement = assert(Widget(ctx, "zoomButtons")), assert(Widget(ctx, "zoomLayout"))
        local modes, placements = P.Suite.MinimapZoomButtons, P.Suite.MinimapZoomLayout
        visibility.set(modes.ALWAYS)
        M.RequestRefresh()
        Check(arrangement.enabled and #arrangement.row.values == 5, "zoom arrangement is missing its four alignments and free placement")
        arrangement.set(placements.LEFT)
        Check(config.zoomLayout == placements.LEFT, "arrangement did not write the live minimap setting")
        visibility.set(modes.HIDE)
        M.RequestRefresh()
        Check(not arrangement.enabled and config.zoomLayout == placements.LEFT, "hiding zoom buttons lost their arrangement")
    end
end
print("Minimap tabs, preview, narrow widths, lazy editors, exact routes and scoped reset passed")
