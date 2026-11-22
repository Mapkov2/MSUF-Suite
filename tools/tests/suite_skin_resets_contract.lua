-- The Skinning page and the Suite's page resets, as a player meets them:
--  * Character Panel owns character view and equipment controls;
--  * "Reset section" on Fonts restores the font choice (followMSUF, face),
--    not just the face, and the Fonts section shows a font problem;
--  * "Reset page" on Skinning restores the factory look for the Suite too and
--    keeps both Skinning switches as the player set them;
--  * the run summary repaints when the skin changes, like the other HUDs;
--  * a loaded addon that restyles Blizzard's windows is named once in chat,
--    and nothing is ever switched off;
--  * a module page reset keeps whether the module is switched on, while the
--    factory reset still starts from the catalog defaults.
-- Usage: lua suite_skin_resets_contract.lua <Suite root>
local root = assert(arg[1], "Suite root required")
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local M, W, T, S, Suite, optionsNS = F.M, F.W, F.T, F.S, F.Suite, F.optionsNS

local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end
local function Noop() end

------------------------------------------------------------------ the skin engine
-- The engine of suite_options_menu_contract.lua with its real Defaults and,
-- here, the real Typography (the font choice is what the reset must restore).
local skin = { GetAPI = function() return nil end, addonName = "MSUF_Suite_Skin",
    Client = { isMainline = true, isForever = false, IsAddOnLoaded = function() return true end },
    L = setmetatable({}, { __index = function(_, key) return key end }), SourceText = function(key) return key end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", skin)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", skin)
skin.DB = skin.CopyValue(skin.Defaults)
skin.Surface = {
    Attach = function(frame) return frame end,
    SetVisible = function(frame, visible) frame.surfaceVisible = visible end,
}
skin.Surface.SkinOwnedButton = skin.Surface.Attach
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Theme.lua"))("MSUF_Suite_Skin", skin)
local ScrollTheme = skin.Theme
skin.Theme = {
    GetScrollBehavior = ScrollTheme.GetScrollBehavior,
    SetScrollBehavior = ScrollTheme.SetScrollBehavior,
    GetColor = function(key) return unpack(skin.DB.theme.colors[key]) end,
    GetColorTable = function(key) return skin.DB.theme.colors[key] end,
    ApplyLook = function(key) skin.DB.theme.look = key; return true end,
    SetAppearance = function(key, value) skin.DB.theme[key] = value; return true end,
    SetGeometry = function(key, value) skin.DB.geometry[key] = value; return true end,
    SetColor = function(key, r, g, b, a) skin.DB.theme.colors[key] = { r, g, b, a }; return true end,
}
local masterSwitches = 0
skin.Adapters = {
    SetBlizzardWindowsEnabled = function(value) skin.DB.blizzardWindowsEnabled = value; return true end,
    SetMasterEnabled = function(value) masterSwitches = masterSwitches + 1; skin.DB.enabled = value; return true end,
    SetEnabled = function(key, value) skin.DB.skins[key] = value; return true end,
    GetDefinitions = function() return { "settings" }, { settings = { labelKey = "SETTINGS" } } end,
    Refresh = function() return true end,
    ApplyAll = Noop,
}
skin.GenericWindows = {
    GetCategories = function() return { { id = "character" } } end,
    SetCategoryEnabled = function(key, value) skin.DB.skinCategories[key] = value; return true end,
}
skin.WindowActionSkin = { SetOption = function(key, value) skin.DB.icons.windowActions[key] = value; return true end }
skin.MicroMenuSkin = {
    SetOption = function(key, value) skin.DB.icons.microMenu[key] = value; return true end,
    ApplyPreset = function() return true end,
}
skin.CharacterDetails = {
    SetView = function(value) skin.DB.characterDetails.view = value; return true end,
    SetOption = function(key, value) skin.DB.characterDetails[key] = value; return true end,
    RefreshFonts = Noop,
}
skin.CharacterStats = { SetOption = function(key, value) skin.DB.characterStats[key] = value; return true end,
    RefreshFonts = Noop }
skin.Registry = { NotifyListeners = Noop, RefreshAll = Noop, QueueRefresh = Noop, AddListener = Noop, RemoveListener = Noop }
local addonWrites = {}
skin.AddonSkins = { SetOption = function(key, value)
    addonWrites[#addonWrites + 1] = key
    skin.DB.addonSkins[key] = value == true
    return true
end }
skin.Database = {
    GetProfileNames = function() return { "Default" } end,
    GetActiveProfileName = function() return "Default" end,
    CreateFactoryProfile = function() return skin.CopyValue(skin.Defaults) end,
    ResetAll = function() skin.DB = skin.CopyValue(skin.Defaults); return skin.DB end,
}
-- The real Typography on the client pieces it reads (suite_skin_msuf_font_contract.lua).
local function Font(path, size, flags)
    local object = { path = path, size = size, flags = flags }
    function object:GetFont() return self.path, self.size, self.flags end
    function object:SetFont(nextPath, nextSize, nextFlags)
        self.path, self.size, self.flags = nextPath, nextSize, nextFlags
        return true
    end
    return object
end
GameFontNormal, ChatFrame1 = Font("Blizzard.ttf", 14, ""), Font("Chat.ttf", 12, "")
NUM_CHAT_WINDOWS, CommunitiesFrame, DeveloperConsole = 1, { Chat = {} }, {}
GetFonts = function() return { "GameFontNormal" } end
EventUtil = { ContinueAfterAllEvents = Noop }
MSUF_GetFontPath = function() return "MSUF.ttf" end
skin.BlizzardFontNames = { "GameFontNormal" }
skin.Safety = { Public = function() return true end, Call = function(object, name) return object[name](object) end }
skin.SharedMedia = { FetchFont = function(name) return name == "Skin" and "Skin.ttf" or nil end,
    GetFontNames = function() return { "Skin" } end }
skin.CombatGate = { RunOrDefer = Noop, Cancel = Noop }
skin.IsCombatLocked = function() return false end
skin.SuiteCore = function() return F.Suite end
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Typography.lua"))("MSUF_Suite_Skin", skin)
MapkoSkin = skin
-- The default Suite meter owns Blizzard's meter; the harness cannot load its runtime.
S.states.damageMeter.error = nil

local function BuildSkinPage(key)
    key = key or "suite_skin"
    local ctx = { key = key, width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
    F.SetCurrent(ctx)
    M.pages[key].build(ctx)
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    return ctx
end
local function SectionOf(ctx, id)
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == id then return section end
    end
    error("no section " .. id)
end
local function ControlsOf(ctx, sectionId)
    local list = {}
    for _, widget in ipairs(ctx.widgets) do
        if widget.meta and widget.meta.sectionId == sectionId then list[#list + 1] = widget end
    end
    return list
end

------------------------------------------------------------------ the run summary follows the skin
do
    local api = { RegisterAddon = function() return { ReleaseAll = Noop } end, OnAppearanceChanged = Noop }
    skin.GetAPI = function() return api end
    Check(Suite.Skin.SetEnabled(true), "the skin did not switch on")
    Check(Suite.Skin.Acquire("resetsContract"), "the skin gave no client")
    local applied, previous = {}, S.Apply
    S.Apply = function(id) applied[#applied + 1] = id end
    for _, id in ipairs({ "objectives", "runSummary", "announcements" }) do S.states[id].active = true end
    api:OnAppearanceChanged("theme", "look")
    S.Apply = previous
    local repainted = {}
    for _, id in ipairs(applied) do repainted[id] = true end
    Check(repainted.objectives and repainted.announcements, "a skin change did not repaint the HUDs")
    Check(repainted.runSummary, "a skin change left an open run summary on the old look")
    for _, id in ipairs({ "objectives", "runSummary", "announcements" }) do S.states[id].active = false end
    skin.GetAPI = function() return nil end
end

------------------------------------------------------------------ a clashing window skin is named once
do
    local loadedAddOns, printed = {}, {}
    local isLoaded, realPrint = C_AddOns.IsAddOnLoaded, Suite.Print
    C_AddOns.IsAddOnLoaded = function(name)
        if loadedAddOns[name] then return true, true end
        return isLoaded(name)
    end
    Suite.Print = function(message) printed[#printed + 1] = message end
    local function Named(name)
        local count = 0
        for _, message in ipairs(printed) do
            if message:find(name, 1, true) then count = count + 1 end
        end
        return count
    end
    skin.DB.enabled = true
    Check(Suite.RootDB.skinConflictNotices == nil, "fixture: a notice was recorded already")
    Suite.Skin.SetEnabled(true)
    Check(#printed == 0, "the skin named an addon that is not loaded")
    loadedAddOns.ElvUI, loadedAddOns.Aurora = true, true
    masterSwitches = 0
    Suite.Skin.SetEnabled(true)
    Check(Named("ElvUI") == 1 and Named("Aurora") == 1 and #printed == 2,
        "the clashing addons were not named once each: " .. #printed)
    -- Again, off and on, and a later login: still the one notice.
    Suite.Skin.SetEnabled(true)
    Suite.Skin.SetEnabled(false)
    Suite.Skin.SetEnabled(true)
    Check(#printed == 2 and Suite.RootDB.skinConflictNotices.ElvUI == true, "a notice was repeated or not kept")
    -- It only informs: no switch of the skin, its windows or the other addon.
    Check(Suite.Skin.enabled == true and skin.DB.enabled == true and masterSwitches == 0,
        "the conflict notice switched something off")
    -- Windows the player left unskinned clash with nothing; the notice waits.
    loadedAddOns.DarkMode = true
    skin.DB.enabled = false
    Suite.Skin.SetEnabled(true)
    Check(Named("DarkMode") == 0, "the notice came although Blizzard windows are not skinned")
    skin.DB.enabled = true
    Suite.Skin.SetEnabled(true)
    Check(Named("DarkMode") == 1 and #printed == 3 and Named("NDui") == 0, "a later clash was not named once")
    C_AddOns.IsAddOnLoaded, Suite.Print = isLoaded, realPrint
end

------------------------------------------------------------------ WoW Forever: character controls
do
    local retail, forever = Suite.Client.modernEquipment, Suite.Client.isForever
    local section = "suite_hud_characterPanel_equipment"
    local function BuildEquipment()
        local ctx = { key = "suite_hud", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
        F.SetCurrent(ctx)
        local builder = W.PageBuilder(ctx)
        local original = builder.CollapsibleSection
        function builder:CollapsibleSection(...)
            local body = original(self, ...)
            body._msufSuiteHUDReveal = Noop
            return body
        end
        optionsNS.SkinPageKit.BuildCharacter(ctx, builder)
        for _, refresh in ipairs(ctx.refreshers) do refresh() end
        return ControlsOf(ctx, section)
    end
    Suite.Client.modernEquipment = true
    local controls = BuildEquipment()
    Check(#controls == 8, "the character section changed: " .. #controls .. " controls")
    for _, widget in ipairs(controls) do
        local reason = rawget(widget, "disabledReason")
        Check(widget.enabled and (not reason or reason() == nil),
            "a Retail character control is gated: " .. tostring(widget.meta.settingKey))
    end
    Suite.Client.modernEquipment, Suite.Client.isForever = false, true
    controls = BuildEquipment()
    Check(#controls == 8, "Forever lost a character control")
    for _, widget in ipairs(controls) do
        local reason = rawget(widget, "disabledReason")
        local key = widget.meta.settingKey
        local retailOnly = key:find("characterStats", 1, true) or key:find("wideLayout", 1, true)
        Check(widget.enabled == not retailOnly, "incorrect Forever availability for " .. key)
        Check(not retailOnly or reason and reason():find("only in Retail", 1, true), "missing availability reason for " .. key)
        if key == "msufsuite.skin.character.view" then
            widget.set("list")
            Check(skin.DB.characterDetails.view == "list", "Character view did not write through the moved control")
        end
    end
    local help
    for _, row in ipairs(optionsNS.SkinSearchRows()) do
        if row.sectionId == section and row.kind == "section" and row.pageKey == "suite_hud" then help = row.help end
    end
    Check(help and help:find("Suite Character Panel", 1, true), "search did not route equipment into Character Panel")
    Check(#ControlsOf(BuildSkinPage(), section) == 0, "Character controls remain in Skinning")
    Suite.Client.modernEquipment, Suite.Client.isForever = retail, forever
end

------------------------------------------------------------------ Addon skins in the actual Suite menu
do
    local ctx = BuildSkinPage()
    local ui = assert(ctx.suiteWorkspace)
    Check(ui.groups.addons ~= nil, "the Suite Skinning page has no Addon skins tab")
    local controls, rows = {}, {}
    for _, widget in ipairs(ControlsOf(ctx, "suite_skin_addon_skins")) do
        if widget.row then
            controls[widget.row.id] = widget
            rows[#rows + 1] = widget.row
        end
    end
    Check(#rows == 3 + #Suite.AddonSkinDefinitions, "the real Suite page must expose all skin toggles")
    local master = assert(controls["addonSkins.enabled"])
    Check(master.get() == false, "the new addon master is not opt-in")
    master.set(true)
    Check(skin.DB.addonSkins.enabled and addonWrites[#addonWrites] == "enabled",
        "the visible master did not call the addon skin owner")
    for _, entry in ipairs(Suite.AddonSkinDefinitions) do
        local widget = controls["addonSkins." .. entry.id]
        Check(widget and widget.get() == true, "missing addon toggle: " .. entry.label)
        widget.set(false)
        Check(widget.get() == false and addonWrites[#addonWrites] == entry.id,
            "an addon toggle did not use the addon skin owner: " .. entry.label)
        ui.select("style")
        local prepare = optionsNS.HM.GetSearchTargetPrepare(widget)
        Check(prepare and prepare() ~= false and ui.selected == "addons",
            "search did not reveal the Addon skins tab for " .. entry.label)
    end
    local current, ensure, create = MapkoSkin, Suite.Skin.EnsureEngine, CreateFrame
    MapkoSkin = nil
    Suite.Skin.EnsureEngine = function() error("cold addon search loaded the skin") end
    CreateFrame = function() error("cold addon search created a frame") end
    local indexed = {}
    for _, row in ipairs(optionsNS.SkinSearchRows()) do
        if row.sectionId == "suite_skin_addon_skins" and row.settingKey then indexed[row.settingKey] = true end
    end
    MapkoSkin, Suite.Skin.EnsureEngine, CreateFrame = current, ensure, create
    for _, key in ipairs(addonWrites) do
        Check(indexed["msufsuite.skin.addonSkins." .. key], "cold search lost addon setting: " .. key)
    end
    Check(indexed["msufsuite.skin.addonSkins.aceGUI"], "cold search lost AceGUI")
    local notified, notify = {}, skin.Registry.NotifyListeners
    skin.Registry.NotifyListeners = function(domain) notified[domain] = true end
    Check(optionsNS.SkinPageKit.ResetSkinSection(skin, "addon_skins", rows), "addon section reset failed")
    skin.Registry.NotifyListeners = notify
    Check(not skin.DB.addonSkins.enabled and skin.DB.addonSkins.aceGUI, "addon reset lost factory flags")
    for _, entry in ipairs(Suite.AddonSkinDefinitions) do
        Check(skin.DB.addonSkins[entry.id], "addon reset lost " .. entry.label)
    end
    Check(notified.addonSkins, "addon reset did not refresh discovery and AceGUI ownership")
end

------------------------------------------------------------------ Item tooltip previews and selection
do
    local unit = { unitTooltipMode = "ALWAYS" }
    local host = { GetUnitFrameTooltipSetting = function(key) return unit[key] end,
        SetUnitFrameTooltipSetting = function(key, value) unit[key] = value return true end }
    Suite.HostBridge.UnitFrameTooltipAPI = function() return host end
    local modes = { item = "suite", spell = "suite", unit = "suite", quest = "suite", loot = "suite" }
    local layoutPreset = "compact"
    local previousTooltips = Suite.Tooltips
    Suite.Tooltips = skin
    skin.DB.theme.tooltipLayout = Suite.CopyValue(Suite.TooltipAppearance.defaults.tooltipLayout)
    skin.DB.theme.itemTooltipStyle = "compact"
    skin.TooltipPalette = { choices = {}, IsActive = function() return false end, Title = function() return 1, 1, 1, 1 end }
    skin.ItemTooltipCard = {
        Create = function(parent)
            local frame = CreateFrame("Frame", nil, parent)
            return { frame = frame, icon = frame:CreateTexture(), title = frame:CreateFontString(),
                meta = frame:CreateFontString(), rule = frame:CreateTexture() }
        end,
        CreateOutline = function(parent)
            local frame = CreateFrame("Frame", nil, parent)
            return { frame = frame, edges = { frame:CreateTexture() } }
        end,
        PaintOutline = function(outline) outline.frame:Show() end,
        Draw = Noop, PlaceContent = Noop, HeaderHeight = function() return 48 end,
        SetUnifiedHeader = function(view, value) view.unified = value end,
        MatchesLootSurface = function()
            return skin.DB.theme.tooltipLayout.lootSurface == "match" or modes.loot == "custom"
        end,
        Setting = function(field) return skin.DB.theme.tooltipLayout[field] end,
        Set = function(field, value) skin.DB.theme.tooltipLayout[field] = value return true end,
        Range = function(field)
            if field == "height" then return 36, 48 end
            if field == "iconSize" then return 16, 38 end
            if field == "x" then return 4, 22 end
            return -5, 5
        end,
        Preset = function() return layoutPreset end,
        TypeStyle = function(kind) return modes[kind] end,
        SetTypeStyle = function(kind, value) modes[kind] = value return true end,
        SetOffsets = function(x, y)
            skin.DB.theme.tooltipLayout.x, skin.DB.theme.tooltipLayout.y = x, y
            return true
        end,
        SetPreset = function(value)
            layoutPreset = value
            return true
        end,
    }
    local ctx = BuildSkinPage("suite_tooltips")
    local section = SectionOf(ctx, "suite_skin_tooltips")
    optionsNS.EnsureSectionContent(section)
    local controls = ControlsOf(ctx, "suite_skin_tooltips")
    local preset
    for _, control in ipairs(ControlsOf(ctx, optionsNS.TooltipBasicsSection)) do
        if control.meta.settingKey == "msufsuite.skin.theme.itemTooltipStyle" then preset = control break end
    end
    Check(preset, "Basics did not build the tooltip preset")
    local itemMode, spellMode, unitMode = controls[1], controls[2], controls[3]
    local indexed = false
    for _, row in ipairs(optionsNS.SkinSearchRows()) do
        if row.pageKey == "suite_tooltips" and row.sectionId == optionsNS.TooltipBasicsSection
            and row.settingKey == "msufsuite.skin.theme.itemTooltipStyle" then
            indexed = true
        end
    end
    Check(indexed, "cold search missed the tooltip style chooser")
    local preview = assert(ctx.suiteWorkspace.tooltipPreview)
    Check(preview.root:IsShown() and #preview.layerButtons == 7, "the tooltip tab missed its frame layer")
    for _, button in ipairs(section._testButtons or {}) do
        Check(button.text ~= "Unitframe tooltips", "the tooltip subsection duplicated its Unit Frame settings link")
    end
    Check(skin.DB.theme.itemTooltipStyle == "compact", "the current tooltip style was not preserved by default")
    ctx.suiteWorkspace.select("layout")
    local title = preview.handles.title
    title.scripts.OnClick(title, "LeftButton")
    Check(preview.kit:Selected() == title and preview.header.frame:IsShown() and modes.item == "suite",
        "the compact title had no preview-only position editor")
    ctx.suiteWorkspace.select("appearance")
    Check(not preview.forceCard and not preview.header.frame:IsShown(), "the title editor leaked its sample style to Appearance")
    ctx.suiteWorkspace.select("layout")
    preset.set("detailed")
    itemMode.set("custom")
    unitMode.set("custom")
    Check(modes.item == "custom" and modes.unit == "custom" and modes.spell == "suite", "type styles were not independent")
    Check(spellMode.get() == "suite" and layoutPreset == "detailed", "selecting a type reset the layout")
    preview.sampleSelector.set(3)
    Check(preview.selected == 3 and preview.header.frame:IsShown(), "the unit sample missed the selected style")
    preview.stateSelector.set("combat")
    Check(preview.header.frame:IsShown() and modes.unit == "custom", "combat lost a supported tooltip style")
    preview.stateSelector.set("restricted")
    Check(preview.header.frame:IsShown() and not preview.compact:IsShown() and modes.unit == "custom",
        "restricted combat hid the selected unit style")
    preview.stateSelector.set("normal")
    Check(preview.header.frame:IsShown(), "leaving the combat preview did not clear restrictions")
    local heightHandle = preview.handles.rule
    local resize = preview.kit.entries[heightHandle]
    skin.DB.theme.tooltipLayout.height = 42
    resize.follow(heightHandle, 0, -5)
    Check(preview.dragSize.height == 47 and skin.DB.theme.tooltipLayout.height == 42,
        "following the resize wrote the saved header height")
    Check(resize.write(0, -47) and skin.DB.theme.tooltipLayout.height == 47,
        "committing resize did not save the header height")
    preview.kit.opts.drag(heightHandle, "done")
    preview.kit:Select(preview.handles.title)
    Check(preview.kit:Nudge(2, 1) and skin.DB.theme.tooltipLayout.x == 12 and skin.DB.theme.tooltipLayout.y == 1,
        "moving the preview did not update the layout coordinates")
    preview.layerButtons[2].scripts.OnClick(preview.layerButtons[2], "LeftButton")
    Check(not preview.header.title:IsShown() and skin.DB.theme.tooltipLayout.tint, "the Title layer modified saved settings")
    preset.set("compact")
    Check(layoutPreset == "compact" and modes.item == "custom" and modes.unit == "custom",
        "resetting the style changed which tooltips use it")
    modes.loot = "custom"
    preview.sampleSelector.set(5)
    Check(preview.header.unified and not preview.lootFill:IsShown(), "loot preview retained the native texture with matching selected")
    local unitSection = SectionOf(ctx, "suite_skin_unit_tooltips")
    optionsNS.EnsureSectionContent(unitSection)
    Check(#ControlsOf(ctx, "suite_skin_unit_tooltips") == 4, "the Suite did not build all four Core tooltip settings")
    local key, target = optionsNS.QoLOwners.Resolve("opt_misc", { settingKey = "general.unitTooltipMode" })
    Check(key == "suite_tooltips" and target.settingKey == "msufsuite.skin.unitTooltipMode", "a Core search target did not follow the moved control")
    Check(optionsNS.QoLOwners.PageFor("tooltipVisibility") == "suite_tooltips", "tooltip visibility stayed under Miscellaneous")
    local editor = SectionOf(ctx, "suite_skin_tooltip_builder")
    optionsNS.EnsureSectionContent(editor)
    Check(#ControlsOf(ctx, "suite_skin_tooltip_builder") >= 10, "the tooltip editor lost layout or data controls")
    local oldPage, oldTarget = optionsNS.QoLOwners.Resolve("suite_skin", {
        sectionId = "suite_skin_tooltip_builder", settingKey = "msufsuite.skin.theme.tooltipLayout.x",
    })
    Check(oldPage == "suite_tooltips" and oldTarget.sectionId == "suite_tooltips_preview",
        "saved Tooltip X/Y links did not reach the preview")
    for _, widget in ipairs(ControlsOf(ctx, "suite_skin_tooltip_builder")) do
        Check(not (widget.meta.settingKey or ""):match("tooltipLayout%.[xy]$"), "title offset slider remained in the menu")
    end

    local available, setMany = optionsNS.Available, optionsNS.SetMany
    local cfg = S.Config("tooltipDetails")
    local oldMode, oldEnabled = cfg.anchor, cfg.enabled
    local writes = 0
    optionsNS.Available = function(id)
        if id == "tooltipDetails" then return true end
        return available(id)
    end
    optionsNS.SetMany = function(id, values)
        if id ~= "tooltipDetails" then return setMany(id, values) end
        writes = writes + 1
        for key, value in pairs(values) do cfg[key] = value end
        return true
    end
    local function CheckAnchor(mode, xKey, yKey)
        cfg.anchor, cfg.enabled = mode, true
        preview.host:Paint("test")
        local button = preview.anchorButton
        Check(button:IsShown(), "the selected shared anchor had no preview handle")
        preview.kit:Select(button)
        Check(preview.kit:Nudge(2, 3), "the preview could not set shared anchor coordinates")
        local x, y = preview.kit.entries[button].read()
        Check(cfg[xKey] == x and cfg[yKey] == y, "anchor X/Y wrote a different mode")
        local count, point = writes, preview.frame.points[1]
        local entry = preview.kit.entries[button]
        preview.kit.opts.drag(button, "press")
        entry.follow(button, -10, 10)
        local moved = preview.frame.points[1]
        Check(writes == count and (point[4] ~= moved[4] or point[5] ~= moved[5]),
            "moving the anchor did not move just the sample")
        Check(entry.write(x - 10, y + 10, true) and writes == count + 1,
            "releasing the preview did not commit both coordinates together")
        preview.kit.opts.drag(button, "done")
        local page, target = optionsNS.QoLOwners.Resolve("suite_tooltips", {
            settingKey = "msufsuite.tooltipDetails." .. xKey,
        })
        Check(page == "suite_tooltips" and target.sectionId == "suite_tooltips_preview",
            "saved anchor link did not target the selected preview")
    end
    CheckAnchor(3, "fixedX", "fixedY")
    CheckAnchor(2, "cursorX", "cursorY")
    local anchorCtx = BuildSkinPage("suite_tooltips")
    local detailSection = "suite_qualityOfLife_tooltipDetails_tooltip_details"
    local feature = assert(anchorCtx.qualityOfLifeFeatureRows[detailSection])
    W.EnsureSectionContent(feature.body)
    local detailControls = ControlsOf(anchorCtx, detailSection)
    Check(#detailControls > 1, "the shared anchor settings were not built")
    for _, widget in ipairs(detailControls) do
        local key = widget.meta.settingKey or ""
        Check(not (key:match("tooltipDetails%.cursor[XY]$") or key:match("tooltipDetails%.fixed[XY]$")),
            "a shared anchor coordinate remained in the menu")
    end
    cfg.anchor, cfg.enabled = oldMode, oldEnabled
    cfg.cursorX, cfg.cursorY, cfg.fixedX, cfg.fixedY = nil, nil, nil, nil
    optionsNS.Available, optionsNS.SetMany = available, setMany
    local style = BuildSkinPage()
    Check(not style.suiteWorkspace.groups.tooltips, "controls were duplicated on Skinning")
    Suite.Tooltips = previousTooltips
    skin.ItemTooltipCard = nil
    Suite.HostBridge.UnitFrameTooltipAPI = function() end
end

------------------------------------------------------------------ The close X remains editable under Native window buttons
do
    skin.DB.icons.windowActions.style, skin.DB.icons.windowActions.closeStyle = "native", "bare"
    local ctx = BuildSkinPage()
    local controls = {}
    for _, widget in ipairs(ControlsOf(ctx, "suite_skin_icons")) do
        if widget.row then controls[widget.row.id] = widget end
    end
    local close = assert(controls["icons.windowActions.closeStyle"])
    Check(close.enabled and close.get() == "bare", "Native actions disabled the independent X style")
    Check(controls["icons.windowActions.closeGlyphSize"].enabled, "Suite X size is disabled under Native actions")
    Check(not controls["icons.windowActions.glyphSize"].enabled, "Native maximize/minimize size became editable")
    close.set("native")
    Check(not controls["icons.windowActions.closeGlyphSize"].enabled, "Native X still exposes a custom glyph size")
    close.set("soft")
    Check(controls["icons.windowActions.surfaceInset"].enabled, "a Soft X cannot edit its own surface under Native actions")
    local rows = {}
    for _, widget in pairs(controls) do rows[#rows + 1] = widget.row end
    Check(optionsNS.SkinPageKit.ResetSkinSection(skin, "icons", rows), "window-button section reset failed")
    Check(skin.DB.icons.windowActions.closeStyle == "bare", "window-button reset did not restore the Suite X")
end

------------------------------------------------------------------ Scroll behavior and its independent bounce toggle
do
    local ctx = BuildSkinPage()
    local controls = {}
    for _, widget in ipairs(ControlsOf(ctx, "suite_skin_shape")) do
        if widget.row then controls[widget.row.id] = widget end
    end
    local mode, bounce = controls["theme.smoothScrolling"], controls["theme.scrollEdgeBounce"]
    Check(mode and mode.rowKind == "dropdown" and mode.get() == "smooth", "default scroll behavior missing")
    Check(bounce and bounce.enabled == false, "bounce is actionable outside adaptive mode")
    mode.set("native")
    Check(mode.get() == "native" and skin.DB.theme.smoothScrolling == false, "native scroll mode was not saved")
    mode.set("adaptive")
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    Check(mode.get() == "adaptive" and skin.DB.theme.smoothScrolling == true and bounce.enabled,
        "adaptive scroll mode did not enable smoothing and its bounce control")
    bounce.set(false)
    Check(bounce.get() == false and mode.get() == "adaptive", "bounce toggle changed scroll behavior")
    local reset = rawget(SectionOf(ctx, "suite_skin_shape"), "_msufSuiteSectionReset")
    Check(reset() and mode.get() == "smooth" and bounce.get() == true,
        "appearance section reset did not restore scroll defaults")
end

------------------------------------------------------------------ Fonts: section reset and status
do
    local lines = {}
    local font = T.Font
    T.Font = function(...)
        local line = font(...)
        lines[#lines + 1] = line
        return line
    end
    local typography = skin.Typography
    Check(typography.SetSelection("arial") and typography.GetSelection() == "arial"
        and skin.DB.typography.followMSUF == false, "fixture: the font choice did not change")
    skin.DB.typography.customPath = "Interface\\Fonts\\Mine.ttf"
    local ctx = BuildSkinPage()
    local reset = rawget(SectionOf(ctx, "suite_skin_fonts"), "_msufSuiteSectionReset")
    Check(type(reset) == "function" and reset(), "the Fonts section reset did not run")
    Check(typography.GetSelection() == "msuf" and skin.DB.typography.followMSUF == true,
        "Reset section left the custom font choice: " .. typography.GetSelection())
    Check(skin.DB.typography.customPath == "" and skin.DB.typography.face == skin.Defaults.typography.face,
        "Reset section left the custom path or face")
    -- An unusable font is reported on the page (the engine records why).
    local function Status()
        for _, line in ipairs(lines) do
            if type(line.text) == "string" and line.text:find("chosen font", 1, true) then return line.text end
        end
    end
    ctx = BuildSkinPage()
    Check(Status() == nil, "the Fonts section shows a problem with a working font")
    Check(typography.SetSelection("custom") and typography.GetStatus().error == "invalid-path", "fixture: no font problem")
    lines = {}
    ctx = BuildSkinPage()
    Check(Status(), "the Fonts section does not show the font problem")
    T.Font = font
end

-- Master, Blizzard windows and Suite windows retain distinct preferences.
do
    local controls = {}
    for _, widget in ipairs(BuildSkinPage().widgets) do
        if widget.meta and widget.meta.settingKey then controls[widget.meta.settingKey] = widget end
    end
    controls["msufsuite.skin.enabled.windows"].set(false)
    Check(optionsNS.SkinningEnabled() and not skin.DB.blizzardWindowsEnabled, "native switch disabled the engine")
    Suite.Skin.SetEnabled(false)
    optionsNS.SetSkinningEnabled(false)
    optionsNS.SetSkinningEnabled(true)
    Check(not Suite.Skin.WindowsEnabled() and not skin.DB.blizzardWindowsEnabled,
        "master cycle overwrote a window preference")
    Suite.Skin.SetEnabled(true)
    optionsNS.SetSkinningEnabled(false)
    Check(not Suite.Skin.Acquire("masterProbe") and not Suite.Skin.WindowsEnabled(), "cached Suite skin ignored master")
    optionsNS.SetSkinningEnabled(true)
end

------------------------------------------------------------------ Skinning: Reset page
do
    local factoryLook = skin.Defaults.theme.look
    for _, switches in ipairs({ { false, false }, { true, true }, { false, true }, { true, false } }) do
        local windows, suiteWindows = switches[1], switches[2]
        Check(S.ApplyGlobalLook("midnight") and Suite.DB.suite.globalLook == "midnight", "fixture: look not set")
        skin.DB.theme.look = "midnight"
        skin.DB.enabled, skin.DB.blizzardWindowsEnabled = windows, not windows
        Check(Suite.Skin.SetEnabled(suiteWindows), "fixture: the Suite windows switch was refused")
        Check(optionsNS.ResetSkinPage(), "Reset page was refused")
        Check(skin.DB.theme.look == factoryLook, "Reset page kept the old skin look")
        Check(Suite.DB.suite.globalLook == factoryLook, "Reset page left the Suite on the old look: "
            .. tostring(Suite.DB.suite.globalLook))
        Check(skin.DB.enabled == windows and skin.DB.blizzardWindowsEnabled == (not windows) and Suite.Skin.enabled == suiteWindows
            and Suite.RootDB.skinEnabled == suiteWindows,
            ("Reset page changed the Skinning switches (%s/%s)"):format(tostring(windows), tostring(suiteWindows)))
    end
    Suite.Skin.SetEnabled(true)
end

------------------------------------------------------------------ module page reset keeps "enabled"
-- The factory reset replaces the profile (Database.StageFactoryReset) and
-- starts every module from the catalog; the page reset must not.
do
    local ids = {}
    for _, id in ipairs(Suite.SuiteOrder) do
        if S.catalog[id].page == "suite_qualityOfLife" then ids[#ids + 1] = id end
    end
    Check(#ids > 9, "fixture: Quality of Life lists too few modules")
    local probe = {}
    local function Flip()
        for _, id in ipairs(ids) do
            local config, rules = S.Config(id), S.catalog[id].rules
            config.enabled = not rules.enabled.default
            for key, rule in pairs(rules) do
                if key ~= "enabled" and type(rule.default) == "boolean" and not probe[id] then
                    probe[id] = key
                    config[key] = not rule.default
                end
            end
        end
    end
    Flip()
    Check(M.ResetPageToDefaults("suite_qualityOfLife"), "Quality of Life page reset failed")
    local probed = 0
    for _, id in ipairs(ids) do
        local rule = S.catalog[id].rules.enabled
        Check(S.Config(id).enabled == not rule.default, "a page reset switched " .. id .. " back to its factory state")
        if probe[id] then
            probed = probed + 1
            local expected = S.catalog[id].rules[probe[id]].default
            if optionsNS.QoLOwners.PageFor(id) then expected = not expected end
            Check(S.Config(id)[probe[id]] == expected, "page reset crossed owner for " .. id .. "." .. probe[id])
        end
    end
    Check(probed > 5, "fixture: too few modules had a second setting")
    -- One module, directly: off stays off, and on stays on.
    local id = ids[1]
    for _, state in ipairs({ false, true }) do
        S.Config(id).enabled = state
        Check(S.Reset(id) and S.Config(id).enabled == state, "S.Reset changed whether " .. id .. " runs")
    end
    -- The factory reset starts again from the catalog.
    for _, moduleId in ipairs(ids) do S.Config(moduleId).enabled = not S.catalog[moduleId].rules.enabled.default end
    Check(Suite.Database.StageFactoryReset(), "the factory reset was refused")
    for _, moduleId in ipairs(ids) do
        Check(Suite.DB.suite.modules[moduleId].enabled == S.catalog[moduleId].rules.enabled.default,
            "the factory reset kept " .. moduleId .. " switched the other way")
    end
end

print("Suite skin resets: " .. checks .. " checks passed")
