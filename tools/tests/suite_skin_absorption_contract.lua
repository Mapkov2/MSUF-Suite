local suiteRoot = assert(arg[1], "Suite root required")
local skinRoot = assert(arg[2], "MapkoSkin source root required")
local file = assert(io.open(skinRoot .. "/tests/MapkoSkin/run.lua", "rb"))
local source = file:read("*a")
file:close()
local marker = "-- This existing contract suite models Retail. Other families have separate client tests."
local at = assert(source:find(marker, 1, true), "MapkoSkin smoke fixture changed")
-- Reuse MapkoSkin's mature WoW API fixture, then boot the Suite-owned TOC.
local fixture = source:sub(1, at - 1)
local contract = [=[
WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
UIParent.GetFrameLevel = function() return 0 end
local simulateForever = arg[3] == "Forever"
GameEvent = simulateForever and { RegisterCamelotEvents = function() end } or {}
_G.MSUFSuiteSkinMigrating = true
local old = {}
local oldTocFile = assert(io.open(arg[2] .. "/MapkoSkin/MapkoSkin_Mainline.toc", "rb"))
local oldToc = oldTocFile:read("*a")
oldTocFile:close()
assert(oldToc:find("## LoadOnDemand: 1", 1, true), "Old engine must not start automatically")
for line in oldToc:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line:match("%.lua$") then
        assert(loadfile(arg[2] .. "/MapkoSkin/" .. line:gsub("\\", "/")))("MapkoSkin", old)
    end
end
assert(old.migrationOnly and old.ready)
local oldLifecycle
for _, frame in ipairs(created_frames) do
    if frame.events.ADDON_LOADED and frame.events.PLAYER_LOGIN then oldLifecycle = frame; break end
end
assert(oldLifecycle)
oldLifecycle.scripts.OnEvent(oldLifecycle, "ADDON_LOADED", "MapkoSkin")
oldLifecycle.scripts.OnEvent(oldLifecycle, "PLAYER_LOGIN")
assert(_G.MapkoSkinDB and old.DB and not old.PublicAPI.playerReady,
    "Old engine applied skins during the data-only migration")
_G.MSUFSuiteSkinMigrating = nil
-- SharedXML grid utilities and unit events used by the owned Micro Bar.
GridLayoutUtil = { calls = {} }
function GridLayoutUtil.CreateStandardGridLayout(stride, xPadding, yPadding, xMultiplier, yMultiplier)
    return { horizontal = true, stride = stride, xPadding = xPadding, yPadding = yPadding,
        xMultiplier = xMultiplier, yMultiplier = yMultiplier }
end
function GridLayoutUtil.CreateVerticalGridLayout(stride, xPadding, yPadding, xMultiplier, yMultiplier)
    return { horizontal = false, stride = stride, xPadding = xPadding, yPadding = yPadding,
        xMultiplier = xMultiplier, yMultiplier = yMultiplier }
end
function GridLayoutUtil.ApplyGridLayout(regions, anchor, layout)
    GridLayoutUtil.calls[#GridLayoutUtil.calls + 1] = { regions = regions, anchor = anchor, layout = layout }
end
AnchorUtil = { CreateAnchor = function(point, relativeTo, relativePoint)
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint }
end }
function Frame:RegisterUnitEvent(event, unit)
    self.events[event] = true
    self.unitEvents = self.unitEvents or {}
    self.unitEvents[event] = unit
end
-- Blizzard frames created before the load-on-demand skin keep the native
-- handlers and mixin copies they were built with.
local preexisting = {
    legacyOnShow = UIPanelButton_OnShow,
    controllerOnShow = ButtonControllerMixin.OnShow,
    setArtKit = UIButtonMixin.SetButtonArtKit,
    setupButtons = GameDialogMixin.SetupButtons,
}
preexisting.legacy = new_frame("Button", "ContractPreexistingPanelButton", UIParent)
preexisting.legacy:SetScript("OnShow", preexisting.legacyOnShow)
function preexisting.legacy:HookScript(script, callback)
    self.hookedScripts = self.hookedScripts or {}
    self.hookedScripts[script] = callback
end
preexisting.icon = new_frame("Button", "ContractPreexistingIconButton", UIParent)
preexisting.icon.SetButtonArtKit = preexisting.setArtKit
preexisting.controller = new_frame("Frame", nil, preexisting.icon)
preexisting.controller.OnShow = preexisting.controllerOnShow
_G.StaticPopup1 = new_frame("Frame", "StaticPopup1", UIParent)
StaticPopup1.SetupButtons = preexisting.setupButtons
function EnumerateFrames(previous)
    if not previous then return created_frames[1] end
    for index = 1, #created_frames do
        if created_frames[index] == previous then return created_frames[index + 1] end
    end
end
local legacyFrameCount = #created_frames
local namespace = {}
local toc = read("MSUF_Suite_Skin/MSUF_Suite_Skin_Mainline.toc")
assert(toc:find("## LoadOnDemand: 1", 1, true))
assert(toc:find("## SavedVariables: MSUFSuiteSkinDB", 1, true))
assert(not toc:find("MapkoSkin_Suite", 1, true))
for line in toc:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line:match("%.lua$") then
        load_addon_file("MSUF_Suite_Skin/" .. line:gsub("\\", "/"), "MSUF_Suite_Skin", namespace)
    end
end
assert(namespace.ready and namespace.addonName == "MSUF_Suite_Skin")
local macroStarts = 0
local originalMacroStart = assert(namespace.MacroWindow.Start)
namespace.MacroWindow.Start = function(...)
    macroStarts = macroStarts + 1
    return originalMacroStart(...)
end
do
    local previousSuite, opened = _G.MSUFSuite
    _G.MSUFSuite = { Menu = { Open = function(page) opened = page; return true end } }
    assert(namespace.OpenOptions() and opened == "suite_skin",
        "Skin options entry point did not open the Suite's native Skinning page")
    _G.MSUFSuite = previousSuite
end
assert(namespace.Client.flavor == (simulateForever and "Forever" or "Mainline"))
assert(namespace.path == "Interface\\AddOns\\MSUF_Suite_Skin\\")
assert(_G.MapkoSkin == namespace and namespace.Suite == nil)
local lifecycle
for index = legacyFrameCount + 1, #created_frames do
    local frame = created_frames[index]
    if frame.events.ADDON_LOADED and frame.events.PLAYER_LOGIN then lifecycle = frame; break end
end
assert(lifecycle, "Suite skin lifecycle missing")
lifecycle.scripts.OnEvent(lifecycle, "ADDON_LOADED", "MSUF_Suite_Skin")
lifecycle.scripts.OnEvent(lifecycle, "PLAYER_LOGIN")
assert(macroStarts > 0, "Blizzard-window startup did not start the Macro adapter")
do
    local panelButtons = namespace.UIPanelButtons
    local legacy = preexisting.legacy
    assert(panelButtons.adopted and legacy.hookedScripts and legacy.hookedScripts.OnShow,
        "a UIPanelButton created before the skin loaded was not hooked")
    legacy.hookedScripts.OnShow(legacy)
    assert(panelButtons.tracked[legacy] == "legacy",
        "a UIPanelButton created before the skin loaded was not skinned when shown")
    assert(preexisting.icon.SetButtonArtKit ~= preexisting.setArtKit
        and preexisting.controller.OnShow ~= preexisting.controllerOnShow,
        "existing red button art-kit and shared-button controllers were not hooked")
    assert(StaticPopup1.SetupButtons ~= preexisting.setupButtons
        and GameDialogMixin.SetupButtons == preexisting.setupButtons,
        "StaticPopup1 kept its unhooked GameDialogMixin copy")
    _G.StaticPopup1, _G.EnumerateFrames = nil, nil
end
do
    local native = function() end
    _G.EditModeManagerFrameMixin = { SetHasActiveChanges = native }
    local manager = new_frame("Frame", "ContractEditModeManager", UIParent)
    manager.SetHasActiveChanges = native
    namespace.EditModeSkin.Apply(manager, "editmode-contract")
    assert(manager.SetHasActiveChanges ~= native
        and _G.EditModeManagerFrameMixin.SetHasActiveChanges == native,
        "Edit Mode hooked its mixin instead of the existing manager frame")
    namespace.EditModeSkin.Disable(manager, "editmode-contract")
    _G.EditModeManagerFrameMixin = nil

    local chat = new_frame("ScrollingMessageFrame", "ContractChatFrame", UIParent)
    chat.editBox = new_frame("EditBox", "ContractChatFrameEditBox", chat)
    chat.editBox.UpdateHeader = native
    local previousChat = _G.ChatFrame1
    _G.ChatFrame1 = chat
    namespace.ChatFramesSkin.Apply(chat, "chat-contract")
    assert(chat.editBox.UpdateHeader ~= native,
        "header updates of an existing chat edit box are not observed")
    namespace.ChatFramesSkin.Disable(chat, "chat-contract")
    _G.ChatFrame1 = previousChat
end
assert(namespace.DB and _G.MSUFSuiteSkinDB == namespace.RootDB)
do
    local api = namespace.GetAPI(2, 1)
    local client = assert(api:RegisterAddon("MidnightSimpleUnitFrames", { integrationVersion = 1 }))
    local nav = new_frame("Button", "SuiteMSUFNavigationContract", UIParent)
    assert(client:SkinButton(nav, {
        role = "navigation", activeRole = "navigationActive",
        listItem = true, active = true,
    }))
    local surface = namespace.Registry.GetSurface(nav)
    assert(surface and surface.spec.activeRole == "button",
        "Suite provider kept the bright blue MSUF navigation highlight")
    client:ReleaseAll()
end
assert(namespace.DB.typography.sharedMediaFont == "MapkoSkin - Expressway ExtraBold")
local looks, palettes = 0, 0
local function ColorsValid()
    for _, value in pairs(namespace.DB.theme.colors) do
        if type(value) == "table" then
            for index = 1, 4 do
                assert(type(value[index]) == "number" and value[index] == value[index]
                    and value[index] >= 0 and value[index] <= 1, "Invalid preset RGBA channel")
            end
        end
    end
end
for _, name in ipairs(namespace.LookOrder) do
    local ok, reason = namespace.Theme.ValidateLook(name)
    assert(ok, name .. ": " .. tostring(reason))
    local microBefore = namespace.DB.icons.microMenu
    local positionBefore = { microBefore.layoutPoint, microBefore.layoutRelativePoint,
        microBefore.layoutX, microBefore.layoutY, microBefore.orientation,
        microBefore.buttonsPerLine, microBefore.layoutMode }
    assert(namespace.Theme.ApplyLook(name), "Cannot apply look " .. name)
    assert(namespace.DB.theme.look == name)
    assert(namespace.DB.theme.preset == namespace.LookPresets[name].palette)
    local look = namespace.LookPresets[name]
    local micro = namespace.DB.icons.microMenu
    assert(micro.preset == look.microStyle,
        "Look did not apply its Micro Bar style: " .. name)
    local authored = namespace.MicroMenuPresetValues[look.microStyle]
    assert(micro.iconStyle == authored.iconStyle and micro.tint == authored.tint
        and micro.buttonBackground == authored.buttonBackground
        and micro.buttonBorder == authored.buttonBorder,
        "Look did not apply its Micro Bar artwork: " .. name)
    for index, key in ipairs({ "layoutPoint", "layoutRelativePoint", "layoutX", "layoutY",
        "orientation", "buttonsPerLine", "layoutMode" }) do
        assert(micro[key] == positionBefore[index], "Look changed Micro Bar layout: " .. name .. "/" .. key)
    end
    for key, value in pairs(namespace.LookPresets[name].geometry) do
        assert(namespace.DB.geometry[key] == value, "Look geometry mismatch: " .. name .. "/" .. key)
    end
    ColorsValid()
    looks = looks + 1
end
local glass = namespace.LookPresets.glass
local forever = namespace.LookPresets.foreverGlass
assert(forever and forever.dynamicPalette == nil, "Forever Glass must not inherit the player class color")
assert(forever.appearance.shellOpacity == 0.92
    and forever.appearance.panelOpacity == 0.92
    and forever.geometry.radius == 12
    and math.abs(namespace.PresetOverrides.foreverGlass.background[1] - 20 / 255) < 0.001,
    "Forever system windows did not restore the backed-up graphite look")
local defaultLook = simulateForever and "foreverGlass" or "midnightDark"
assert(namespace.Theme.ApplyLook(defaultLook), "client default look cannot be applied")
assert(namespace.Defaults.enabled and namespace.Defaults.skins.blizzardWindows,
    "Blizzard window skinning must be enabled on fresh profiles")
for category, enabled in pairs(namespace.Defaults.skinCategories) do
    assert(enabled == true, "Blizzard window category starts disabled: " .. category)
end
assert(namespace.BlizzardCatalog.glass.valid, "reviewed Blizzard glass catalog is invalid")
assert(not namespace.Adapters.definitions.objectiveTracker
    and not namespace.Adapters.definitions.objectiveTrackerAccents
    and not namespace.BlizzardCatalog.GetGlassContract("ObjectiveTrackerFrame")
    and not namespace.BlizzardCatalog.GetGlassContract("ObjectiveTrackerTopBannerFrame"),
    "Blizzard Objective Tracker skin is still registered")
for _, fontName in ipairs(namespace.BlizzardFontNames) do
    assert(fontName ~= "ObjectiveFont" and not fontName:match("^ObjectiveTracker"),
        "Blizzard Objective Tracker font remains skinned")
end
local macroShell
for _, entry in ipairs(namespace.BlizzardCatalog.entries) do
    if entry.id == "macros" then macroShell = entry.mode and entry.mode.role; break end
end
assert(macroShell == "popup", "Macro window still uses the translucent generic shell")
for _, frameName in ipairs({ "CharacterFrame", "PVEFrame", "ProfessionsFrame",
    "SettingsPanel", "GameMenuFrame", "AddonList", "MerchantFrame" }) do
    local coverage = namespace.BlizzardCatalog.GetGlassContract(frameName)
    if not coverage then
        for _, entry in ipairs(namespace.BlizzardCatalog.glass.standalone) do
            for _, rootName in ipairs(entry.roots) do
                if rootName == frameName then coverage = entry; break end
            end
            if coverage then break end
        end
    end
    assert(coverage and coverage.support ~= "none",
        "Midnight Dark does not cover Blizzard menu root " .. frameName)
end
if not simulateForever then
    local hover = namespace.Theme.GetColorTable("hover")
    assert(hover[1] == 168 / 255 and hover[2] == 173 / 255
        and namespace.DB.theme.hoverStyle == "outline",
        "Blizzard menu hover did not use a visible Dark outline")
    local hookCount = 0
    local function RecordHook(self, script, callback)
        hookCount = hookCount + 1
        self.hooks[script] = callback
    end
    local row = CreateFrame("Button", "DarkMenuRow")
    row.hooks = {}
    row.HookScript = RecordHook
    local surface = namespace.Surface.Attach(row, {
        role = "card", listItem = true, interactive = true,
    })
    local otherRow = CreateFrame("Button", "DarkMenuRowTwo")
    otherRow.hooks = {}
    otherRow.HookScript = RecordHook
    namespace.Surface.Attach(otherRow, { role = "card", listItem = true, interactive = true })
    namespace.Surface.Attach(row, { role = "card", listItem = true, interactive = true })
    assert(hookCount == 4 and row.hooks.OnEnter == otherRow.hooks.OnEnter
        and row.hooks.OnLeave == otherRow.hooks.OnLeave,
        "interactive surfaces allocate hover closures or hook a button twice")
    assert(surface and surface.hoverOverlay and surface.hoverOverlay.drawLayer == "HIGHLIGHT"
        and surface.hoverOverlay.texture:match("_edge1%.png$")
        and not surface.hoverOverlay.shown,
        "Blizzard menu row did not receive an outlined hover surface")
    row.hooks.OnEnter(row)
    assert(surface.hoverOverlay.shown, "hover did not reveal the menu outline")
    row.hooks.OnLeave(row)
    assert(not surface.hoverOverlay.shown, "leaving a menu row kept its outline")
    row.hooks.OnEnter(row)
    namespace.Surface.SetVisible(row, false)
    assert(not surface.hoverOverlay.shown, "disabling a menu left its hover outline visible")
    local selectedRow = CreateFrame("Button", "DarkSettingsCategory")
    local selection = namespace.Surface.Attach(selectedRow, {
        role = "navigation", activeRole = "navigationActive",
        listItem = true, activeEdge = true,
    })
    assert(selection and not selection.edge.shown,
        "inactive Settings category has a selection outline")
    namespace.Surface.SetActive(selectedRow, true)
    assert(selection.edge.shown and selection.edge.texture:match("_edge1%.png$"),
        "selected Settings category did not gain a clear outline")
    namespace.Surface.SetActive(selectedRow, false)
    assert(not selection.edge.shown, "old Settings category kept its selected outline")
    local previousDark = namespace.CopyValue(namespace.Defaults)
    previousDark.revision = 47
    previousDark.theme.hoverStyle = "softFill"
    previousDark.theme.hoverIntensity = 0.68
    previousDark.theme.colors.hover[1] = 66 / 255
    previousDark.theme.colors.hover[2] = 71 / 255
    previousDark.theme.colors.hover[3] = 67 / 255
    namespace.Database.Normalize(previousDark)
    assert(previousDark.theme.hoverStyle == "outline"
        and previousDark.theme.colors.hover[1] == 168 / 255,
        "saved factory Dark look did not gain the visible menu highlight")
    local customHover = namespace.CopyValue(previousDark)
    customHover.revision = 47
    customHover.theme.hoverStyle = "softFill"
    customHover.theme.hoverIntensity = 0.68
    customHover.theme.colors.hover[1] = 0.31
    namespace.Database.Normalize(customHover)
    assert(customHover.theme.hoverStyle == "softFill"
        and customHover.theme.colors.hover[1] == 0.31,
        "Dark hover migration overwrote a custom color")
end
do
    -- 12.x getters may return secret colors. Native gold is recolored only
    -- when its channels can be read; a secret is never compared or tracked.
    local function Label(parent, r, g, b)
        local label = parent:CreateFontString()
        label:SetTextColor(r, g, b, 1)
        label.colorWrites = 0
        local setTextColor = label.SetTextColor
        function label:SetTextColor(...)
            self.colorWrites = self.colorWrites + 1
            return setTextColor(self, ...)
        end
        return label
    end
    local previousSecret, previousAccess = issecretvalue, canaccessvalue
    local secretFrame = CreateFrame("Frame", "SecretGoldFrame", UIParent)
    local secretLabel = Label(secretFrame, 1, 0.82, 0)
    secretFrame.regions = { secretLabel }
    local secretTexture = secretFrame:CreateTexture(nil, "ARTWORK")
    secretTexture:SetVertexColor(1, 0.82, 0, 1)
    local vertexWrites = 0
    local setVertexColor = secretTexture.SetVertexColor
    function secretTexture:SetVertexColor(...)
        vertexWrites = vertexWrites + 1
        return setVertexColor(self, ...)
    end
    issecretvalue = function(value) return type(value) == "number" end
    canaccessvalue = function() return false end
    local tracked = namespace.BlizzardYellow.TrackFrame(secretFrame)
    local tinted = namespace.Checkmarks.TrackTexture(secretTexture, "secret-contract", "checkmark")
    issecretvalue, canaccessvalue = previousSecret, previousAccess
    assert(tracked == 0 and secretLabel.colorWrites == 0
        and namespace.BlizzardYellow.directStates[secretLabel] == nil,
        "Blizzard gold recolored text whose color was secret")
    assert(tinted == false and vertexWrites == 0 and namespace.Checkmarks.states[secretTexture] == nil,
        "checkmark tint compared a secret vertex color")
    assert(namespace.BlizzardYellow.TrackFrame(secretFrame) == 1 and secretLabel.colorWrites == 1,
        "Blizzard gold skipped readable native text")

    -- A dropdown label outside the button's regions is still visited, once,
    -- and a forbidden label is left alone.
    local dropdown = CreateFrame("Button", "GoldLabelDropdown", UIParent)
    dropdown.Text = Label(CreateFrame("Frame", nil, dropdown), 1, 0.82, 0)
    assert(namespace.BlizzardYellow.TrackDropdown(dropdown) == 1
        and dropdown.Text.colorWrites == 1, "dropdown label outside the regions was not recolored")
    local listed = CreateFrame("Button", "ListedLabelDropdown", UIParent)
    listed.Text = Label(listed, 1, 0.82, 0)
    listed.regions = { listed.Text }
    assert(namespace.BlizzardYellow.TrackDropdown(listed) == 1 and listed.Text.colorWrites == 1,
        "a dropdown label listed as a region was visited twice")
    local guarded = CreateFrame("Button", "ForbiddenLabelDropdown", UIParent)
    guarded.Text = Label(CreateFrame("Frame", nil, guarded), 1, 0.82, 0)
    function guarded.Text:IsForbidden() return true end
    assert(namespace.BlizzardYellow.TrackDropdown(guarded) == 0 and guarded.Text.colorWrites == 0,
        "a forbidden dropdown label was recolored")
    namespace.BlizzardYellow.Restore()
    namespace.Checkmarks.UntrackOwner("secret-contract")
end
do
    local previousSuite, appliedLook = _G.MSUFSuite, nil
    _G.MSUFSuite = { Suite = { ApplyGlobalLook = function(name)
        appliedLook = name
        return true
    end } }
    assert(namespace.Theme.ApplyLook("midnightDark") and appliedLook == "midnightDark",
        "Skinning preset did not propagate to the Suite")
    _G.MSUFSuite = previousSuite
    assert(namespace.Theme.ApplyLook(defaultLook), "client look could not be restored")
end
assert(namespace.Defaults.theme.look == defaultLook
    and namespace.Defaults.theme.preset == namespace.LookPresets[defaultLook].palette,
    "fresh skin profile did not start with the client's look")
assert(#namespace.LookOrder == 3
    and namespace.LookOrder[1] == "midnight"
    and namespace.LookOrder[2] == "midnightDark"
    and namespace.LookOrder[3] == "foreverGlass",
    "Skinning menu must expose Blue, Dark and Forever")
do
    local saved = namespace.CopyValue(namespace.Defaults)
    saved.revision = 33
    saved.theme.look = "foreverGlass"
    saved.theme.preset = "foreverGlass"
    saved.theme.colors.accent = { 0.21, 0.32, 0.43, 1 }
    namespace.Database.Normalize(saved)
    assert(saved.theme.look == "foreverGlass"
        and saved.theme.colors.accent[1] == 0.21,
        "new client defaults replaced an existing skin profile")
end
assert(namespace.Defaults.icons.microMenu.preset == (simulateForever and "forever" or "midnightDark")
    and namespace.Defaults.icons.microMenu.iconStyle == "bold"
    and namespace.Defaults.icons.microMenu.tint == "theme"
    and namespace.Defaults.hud.objectiveTrackerStyle == nil
    and namespace.Defaults.skins.objectiveTracker == nil,
    "fresh Suite skin profile must leave Blizzard tracker styling out")
do
    local profile = namespace.CopyValue(namespace.Defaults)
    profile.windowControls.scales.CharacterFrame = 1.23
    profile.windowControls.scales.MerchantFrame = 9
    profile.windowControls.positions.CharacterFrame = { x = 410, y = -210 }
    profile.windowControls.positions.MerchantFrame = { x = 99999, y = 0 }
    local imported = namespace.Database.SanitizeProfile(profile)
    assert(imported.windowControls.scales.CharacterFrame == 1.23
        and imported.windowControls.scales.MerchantFrame == nil
        and imported.windowControls.positions.CharacterFrame.x == 410
        and imported.windowControls.positions.MerchantFrame == nil,
        "per-window layout must survive profile import without accepting invalid values")
end
do
    local existing = namespace.CopyValue(namespace.Defaults)
    existing.revision = 30
    existing.theme.look = "midnight"
    existing.hud.objectiveTrackerStyle = "forever"
    existing.skins.objectiveTracker = false
    existing.skins.objectiveTrackerAccents = true
    existing.hud.objectiveTrackerHeaders = true
    existing.icons.microMenu.preset = "framed"
    namespace.Database.Normalize(existing)
    assert(existing.hud.objectiveTrackerStyle == nil
        and existing.hud.objectiveTrackerHeaders == nil
        and existing.skins.objectiveTracker == nil
        and existing.skins.objectiveTrackerAccents == nil
        and existing.icons.microMenu.preset == "forever",
        "migration must retire tracker styling and consolidate the old framed Micro Bar")
end
do
    for name, target in pairs({
        forever = "forever", modern = "modern", framed = "forever",
        midnight = "modern", class = "modern", minimal = "modern",
    }) do
        local previous = namespace.CopyValue(namespace.Defaults)
        previous.revision = 31
        previous.icons.microMenu.preset = name
        previous.icons.microMenu.iconStyle = "bold"
        previous.icons.microMenu.tint = "theme"
        previous.icons.microMenu.buttonBackground = true
        previous.icons.microMenu.layoutX = 91
        namespace.Database.Normalize(previous)
        assert(previous.icons.microMenu.preset == target
            and previous.icons.microMenu.barMaterial == target
            and previous.icons.microMenu.iconStyle == namespace.MicroMenuPresetValues[target].iconStyle
            and previous.icons.microMenu.tint == namespace.MicroMenuPresetValues[target].tint
            and previous.icons.microMenu.buttonBackground == namespace.MicroMenuPresetValues[target].buttonBackground
            and previous.icons.microMenu.layoutX == 91,
            "named Micro Bar migration did not replace glyphs without moving the bar: " .. name)
    end
    local previous = namespace.CopyValue(namespace.Defaults)
    previous.revision = 31
    previous.icons.microMenu.preset = "custom"
    previous.icons.microMenu.iconStyle = "bold"
    namespace.Database.Normalize(previous)
    assert(previous.icons.microMenu.iconStyle == "bold"
        and previous.icons.microMenu.barMaterial == "theme",
        "custom Micro Bar artwork was overwritten")
end
for key, value in pairs(namespace.Defaults.theme.colors) do
    local applied = namespace.DB.theme.colors[key]
    for channel = 1, 4 do
        assert(math.abs(value[channel] - applied[channel]) < 0.0001,
            "factory color diverges from applying the client look: " .. key)
    end
end
for key, value in pairs(namespace.LookPresets[defaultLook].appearance) do
    assert(namespace.Defaults.theme[key] == value, "factory appearance mismatch: " .. key)
end
for key, value in pairs(namespace.LookPresets[defaultLook].geometry) do
    assert(namespace.Defaults.geometry[key] == value, "factory geometry mismatch: " .. key)
end
assert(namespace.Theme.ApplyLook("foreverGlass"), "Forever Glass cannot be applied")
local gold = namespace.DB.theme.colors.checkmark
assert(math.abs(gold[1] - 216 / 255) < 0.001 and math.abs(gold[2] - 182 / 255) < 0.001
    and math.abs(gold[3] - 106 / 255) < 0.001, "Forever Glass checkmark is not MSUF gold")
local selected = namespace.DB.theme.colors.active
assert(math.abs(selected[1] - 54 / 255) < 0.001 and math.abs(selected[2] - 60 / 255) < 0.001
    and math.abs(selected[3] - 60 / 255) < 0.001, "Forever Glass selected fill is not MSUF graphite")
for name in pairs(namespace.PresetOverrides) do
    assert(namespace.Theme.ApplyPreset(name), "Cannot apply palette " .. name)
    assert(namespace.DB.theme.preset == name)
    ColorsValid()
    palettes = palettes + 1
end
for _, name in ipairs(namespace.MicroMenuPresets) do
    local preset = namespace.MicroMenuPresetValues[name]
    assert(preset, "Missing micro menu preset " .. name)
    if name == "blizzard" then
        assert(preset.layoutMode == "blizzard" and preset.iconStyle == "blizzard"
            and preset.tint == "native" and preset.barBackground == false
            and preset.buttonBackground == false and preset.barBorder == 0,
            "Blizzard preset does not restore the native Micro Bar")
    else
        assert(preset.layoutMode == "owned" and preset.iconStyle == "bold"
            and preset.tint == "theme" and preset.buttonBackground == false
            and preset.buttonBorder == 0 and preset.scale == 1
            and preset.barMaterial == name,
            "Micro Bar preset mismatch: " .. name)
    end
end
assert(#namespace.MicroMenuPresets == 4
    and namespace.MicroMenuPresetValues.forever.spacing ~= namespace.MicroMenuPresetValues.modern.spacing
    and namespace.MicroMenuPresetValues.forever.padding ~= namespace.MicroMenuPresetValues.modern.padding
    and namespace.Materials.microBarDark.border == "microBarBorder",
    "Micro Bar styles must keep three authored looks and Blizzard original")
do
    local colors = {}
    for _, entry in ipairs({ { "modern", "midnight" }, { "midnightDark", "midnightDark" },
        { "forever", "foreverGlass" } }) do
        assert(namespace.MicroMenuSkin.ApplyPreset(entry[1]))
        local actual = namespace.Theme.GetColorTable("microBarFill")
        local expected = namespace.PresetOverrides[entry[2]].microBarFill
            or namespace.BaseColors.microBarFill
        assert(actual[1] == expected[1] and actual[2] == expected[2],
            "Micro Bar look did not select its own palette: " .. entry[1])
        colors[#colors + 1] = actual
    end
    assert(colors[1][1] ~= colors[2][1] and colors[2][1] ~= colors[3][1],
        "Micro Bar Blue, Dark and Forever are not distinct")
end
for name in pairs(namespace.MicroMenuPositionPresets) do
    assert(type(name) == "string")
end
do
    local registeredOwner, registeredElement, enteredOwner, enteredId
    local previousEnum, previousCurve, previousPercent, previousHousing =
        _G.Enum, _G.C_CurveUtil, _G.UnitHealthPercent, _G.C_Housing
    _G.RegisterStateDriver = function(frame, attribute, driver)
        assert(attribute == "visibility")
        frame.visibilityDriver = driver
        -- The fixture is out of combat; WoW's secure state driver owns later transitions.
        frame:SetShown(driver == "[combat] hide; show")
    end
    _G.UnregisterStateDriver = function(frame, attribute)
        assert(attribute == "visibility")
        frame.visibilityDriver = nil
    end
    _G.MSUF_EditModeAPI = {
        RegisterElement = function(owner, element)
            registeredOwner, registeredElement = owner, element
            return true
        end,
        RefreshOwner = function() end,
        EnterEditMode = function(owner, id)
            enteredOwner, enteredId = owner, id
            return true
        end,
    }
    -- Model WoW's frame levels and FrameUtil's level-preserving reparent. A
    -- new parent normally adds one level; the native MicroMenu keeps level 2.
    local previousCreateFrame, previousFrameUtil = CreateFrame, FrameUtil
    CreateFrame = function(kind, name, parent, ...)
        local frame = previousCreateFrame(kind, name, parent, ...)
        if name == "MapkoSkinMicroBarHealthGate" or name == "MapkoSkinMicroBar" then
            frame.frameLevel = parent:GetFrameLevel() + 1
            function frame:GetFrameLevel() return self.frameLevel end
            function frame:SetFrameLevel(level) self.frameLevel = level end
        end
        return frame
    end
    FrameUtil = { SetParentMaintainRenderLayering = function(frame, parent)
        local level = frame:GetFrameLevel()
        frame:SetParent(parent)
        frame:SetFrameLevel(level)
    end }
    local container = new_frame("Frame", "MicroMenuContainer", UIParent)
    function container:GetFrameLevel() return 1 end
    _G.MicroMenuContainer = container
    local root = new_frame("Frame", "MicroMenu", container)
    root.frameLevel = 2
    function root:GetFrameLevel() return self.frameLevel end
    function root:SetFrameLevel(level) self.frameLevel = level end
    function root:SetParent(parent)
        self.parent = parent
        self.frameLevel = parent:GetFrameLevel() + 1
    end
    function root:MarkDirty() end
    function root:Layout() self:SetSize(180, 28) end
    function root:ResetMicroMenuPosition()
        self:SetParent(container)
        self:ClearAllPoints()
        self:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end
    function root:UpdateHelpTicketButtonAnchor() end
    local layoutChildren = {
        new_frame("Button", "OwnedGridChild1", root), new_frame("Button", "OwnedGridChild2", root),
    }
    function root:GetLayoutChildren() return layoutChildren end
    local settings = namespace.DB.icons.microMenu
    settings.layoutMode, settings.locked = "owned", false
    local bar, mode = namespace.OwnedMicroBar.Apply(root, settings)
    CreateFrame = previousCreateFrame
    assert(bar:GetParent():GetFrameLevel() == UIParent:GetFrameLevel()
        and bar:GetFrameLevel() < root:GetFrameLevel(),
        "Micro Bar shell can cover native icons after health-gate reparenting")
    local portraitUnit
    for _, frame in ipairs(created_frames) do
        if frame.unitEvents and frame.unitEvents.UNIT_PORTRAIT_UPDATE then
            portraitUnit = frame.unitEvents.UNIT_PORTRAIT_UPDATE
        end
    end
    assert(portraitUnit == "player", "Micro Bar portrait listened to every unit's portrait updates")
    assert(bar and mode == "owned" and registeredOwner == "MSUFSuite.Skin"
        and registeredElement.id == "microBar", "Micro Bar did not join MSUF Edit Mode")
    local _, legacyMover = namespace.OwnedMicroBar.GetFrames()
    assert(not legacyMover:IsShown(), "legacy drag handle overlapped the MSUF mover")
    local before = registeredElement.captureState()
    assert(registeredElement.isEnabled() and registeredElement.getFrame() == bar)
    assert(registeredElement.movePosition({ state = before, deltaX = 11, deltaY = -7, phase = "preview" }))
    assert(settings.layoutX == before.x and settings.layoutY == before.y,
        "Edit Mode preview wrote the saved position")
    assert(registeredElement.movePosition({ state = before, deltaX = 11, deltaY = -7, phase = "commit" }))
    assert(settings.layoutX ~= before.x or settings.layoutY ~= before.y,
        "Edit Mode commit did not save the position")
    assert(registeredElement.restoreState(before)
        and settings.layoutX == before.x and settings.layoutY == before.y,
        "Edit Mode discard did not restore the position")
    assert(registeredElement.resetPosition()
        and settings.positionPreset == (simulateForever and "bottomCenter" or "custom")
        and settings.layoutX == namespace.Defaults.icons.microMenu.layoutX
        and settings.layoutY == namespace.Defaults.icons.microMenu.layoutY,
        "Edit Mode reset did not restore the client's factory position")
    assert(namespace.OwnedMicroBar.OpenEditMode()
        and enteredOwner == registeredOwner and enteredId == "microBar")
    local controls = registeredElement.extraControls
    assert(type(controls) == "table" and #controls == 6,
        "Micro Bar Edit Mode popup is missing its basic layout controls")
    assert(controls[1].set(6) and controls[1].get() == 6
        and controls[2].set(4) and controls[2].get() == 4
        and controls[3].set(120) and controls[3].get() == 120
        and controls[4].set(8) and controls[4].get() == 8,
        "Micro Bar popup numeric controls did not save their settings")
    assert(controls[5].set(true) and controls[5].get() and not controls[6].get(),
        "Micro Bar popup Vertical control did not select vertical layout")
    namespace.OwnedMicroBar.Apply(root, settings)
    local placed = GridLayoutUtil.calls[#GridLayoutUtil.calls]
    assert(placed and placed.regions == layoutChildren and placed.anchor.relativeTo == root
        and placed.layout.horizontal == false and placed.layout.stride == 6
        and placed.layout.xPadding == 4 and placed.layout.yPadding == 4,
        "Micro Bar popup settings did not reach the owned runtime layout")
    for _, field in ipairs({ "isHorizontal", "stride", "isStacked", "childXPadding",
        "childYPadding", "layoutFramesGoingRight", "layoutFramesGoingUp", "oldGridSettings" }) do
        assert(root[field] == nil, "Micro Bar wrote Blizzard's MicroMenu layout field " .. field)
    end
    local placements = #GridLayoutUtil.calls
    root:Layout()
    assert(#GridLayoutUtil.calls == placements + 1
        and GridLayoutUtil.calls[#GridLayoutUtil.calls].layout.stride == 6,
        "a native MicroMenu layout pass did not restore the owned grid")
    assert(controls[6].set(true) and controls[6].get() and not controls[5].get(),
        "Micro Bar popup Horizontal control did not select horizontal layout")
    assert(registeredElement.restoreState(before)
        and settings.orientation == before.orientation
        and settings.buttonsPerLine == before.buttonsPerLine
        and settings.spacing == before.spacing
        and settings.scale == before.scale
        and settings.padding == before.padding,
        "Micro Bar popup controls did not restore through Edit Mode undo")
    settings.visibility = "never"
    assert(namespace.OwnedMicroBar.Apply(root, settings) == bar and not bar:IsShown(),
        "Never visibility did not hide the owned Micro Bar")
    registeredElement.onSessionChanged(true)
    assert(bar:IsShown() and bar.visibilityDriver == nil,
        "MSUF Edit Mode did not reveal a hidden Micro Bar")
    registeredElement.onSessionChanged(false)
    assert(not bar:IsShown(), "leaving Edit Mode did not restore Never visibility")
    settings.visibility = "combat"
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar.visibilityDriver == "[combat] show; hide" and not bar:IsShown(),
        "combat-only visibility did not register its secure driver")
    registeredElement.onSessionChanged(true)
    assert(bar:IsShown() and bar.visibilityDriver == nil,
        "Edit Mode did not suspend combat-only visibility")
    registeredElement.onSessionChanged(false)
    assert(bar.visibilityDriver == "[combat] show; hide" and not bar:IsShown(),
        "leaving Edit Mode did not restore combat-only visibility")
    settings.visibility = "outOfCombat"
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar.visibilityDriver == "[combat] hide; show" and bar:IsShown(),
        "out-of-combat visibility did not register its secure driver")
    settings.visibility = "mouseover"
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar.visibilityDriver == nil and bar:IsShown() and bar:GetAlpha() == 0,
        "mouseover visibility did not fade the owned Micro Bar")
    bar.scripts.OnEnter(bar)
    assert(bar:GetAlpha() == 1, "mouseover did not reveal the Micro Bar")
    bar.scripts.OnLeave(bar)
    assert(bar:GetAlpha() == 0, "leaving the Micro Bar did not hide it")
    settings.visibility = "always"
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar:IsShown() and bar:GetAlpha() == 1 and bar.visibilityDriver == nil,
        "Always visibility did not restore the Micro Bar")
    assert(settings.loadHideMounted == false and settings.loadShowWhenInjured == false,
        "Micro Bar load conditions changed existing defaults")
    assert(namespace.MicroMenuSkin.SetOption("loadHideMounted", true),
        "Micro Bar mounted option was rejected")
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar.visibilityDriver == "[mounted] hide; show",
        "Micro Bar mounted condition did not reach the secure driver")
    assert(namespace.MicroMenuSkin.SetOption("loadHideNoTarget", true)
        and namespace.MicroMenuSkin.SetOption("loadShowWhenInjured", true),
        "Micro Bar health/no-target options were rejected")
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar.visibilityDriver == "[mounted] hide; show",
        "health condition did not supersede the no-target rule")
    local healthGate = bar:GetParent()
    local healthValue = 0
    _G.Enum = { LuaCurveType = { Step = 1 } }
    _G.C_CurveUtil = { CreateCurve = function()
        return { SetType = function(self, value) self.kind = value end,
            AddPoint = function(self, x, y) self[x] = y end }
    end }
    _G.UnitHealthPercent = function(unit, includeAbsorbs, curve)
        assert(unit == "player" and includeAbsorbs == false and curve.kind == 1
            and curve[0] == 1 and curve[1] == 0)
        return healthValue
    end
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(healthGate.alpha == 0 and healthGate ~= UIParent,
        "full-health condition did not fade the native Micro Bar subtree")
    local loadEventFrame
    for _, frame in ipairs(created_frames) do
        if frame.events.UNIT_HEALTH and frame.events.HOUSE_PLOT_ENTERED == nil then
            loadEventFrame = frame
        end
    end
    assert(loadEventFrame and loadEventFrame.unitEvents.UNIT_HEALTH == "player",
        "Micro Bar health event did not limit updates to the player")
    healthValue = 1
    loadEventFrame.scripts.OnEvent(loadEventFrame, "UNIT_HEALTH", "player")
    assert(healthGate.alpha == 1, "health update did not restore the Micro Bar")
    settings.visibility = "mouseover"
    namespace.OwnedMicroBar.Apply(root, settings)
    healthValue = 0
    loadEventFrame.scripts.OnEvent(loadEventFrame, "UNIT_HEALTH", "player")
    bar.scripts.OnEnter(bar)
    assert(bar:GetAlpha() == 1 and healthGate.alpha == 0,
        "mouseover alpha overrode the Micro Bar health condition")
    registeredElement.onSessionChanged(true)
    assert(bar.visibilityDriver == nil and healthGate.alpha == 1,
        "Edit Mode did not reveal a health-hidden Micro Bar")
    registeredElement.onSessionChanged(false)
    assert(bar.visibilityDriver == "[mounted] hide; show" and healthGate.alpha == 0,
        "leaving Edit Mode did not restore Micro Bar load conditions")
    settings.visibility = "always"
    _G.C_Housing = { IsInsideHouseOrPlot = function() return false end }
    assert(namespace.MicroMenuSkin.SetOption("loadHideInHousing", true))
    namespace.OwnedMicroBar.Apply(root, settings)
    local housingEventFrame
    for _, frame in ipairs(created_frames) do
        if frame.events.HOUSE_PLOT_ENTERED then housingEventFrame = frame end
    end
    assert(housingEventFrame, "Micro Bar housing condition did not register its event")
    _G.C_Housing.IsInsideHouseOrPlot = function() return true end
    housingEventFrame.scripts.OnEvent(housingEventFrame, "HOUSE_PLOT_ENTERED")
    assert(bar.visibilityDriver == "hide", "housing entry did not hide the Micro Bar")
    _G.C_Housing.IsInsideHouseOrPlot = function() return false end
    housingEventFrame.scripts.OnEvent(housingEventFrame, "HOUSE_PLOT_EXITED")
    assert(bar.visibilityDriver == "[mounted] hide; show",
        "housing exit did not restore the Micro Bar rule")
    settings.loadHideMounted, settings.loadHideNoTarget = false, false
    settings.loadShowWhenInjured, settings.loadHideInHousing = false, false
    namespace.OwnedMicroBar.Apply(root, settings)
    assert(bar.visibilityDriver == nil and healthGate.alpha == 1,
        "clearing Micro Bar load conditions kept its driver or health fade")
    root.isHorizontal, root.stride, root.childXPadding, root.childYPadding = true, 13, -5, -5
    root.layoutFramesGoingRight, root.layoutFramesGoingUp = true, false
    assert(namespace.OwnedMicroBar.Disable(root))
    local nativeGrid = GridLayoutUtil.calls[#GridLayoutUtil.calls].layout
    assert(nativeGrid.horizontal and nativeGrid.stride == 13 and nativeGrid.xPadding == -5
        and nativeGrid.yMultiplier == -1, "disabling the Micro Bar did not restore Blizzard's grid")
    assert(not registeredElement.isEnabled(), "disabled Micro Bar remained movable")
    _G.Enum, _G.C_CurveUtil, _G.UnitHealthPercent, _G.C_Housing =
        previousEnum, previousCurve, previousPercent, previousHousing
    _G.RegisterStateDriver, _G.UnregisterStateDriver = nil, nil
    FrameUtil = previousFrameUtil
end
do
    local container = new_frame("Frame", "NativeMicroMenuContainer", UIParent)
    function container:Layout() end
    local root = new_frame("Frame", "MicroMenu", container)
    _G.MicroMenu, _G.MicroMenuContainer = root, container
    root.BorderArt = root:CreateTexture(nil, "BACKGROUND")
    root.BackgroundArt = root:CreateTexture(nil, "BACKGROUND")
    function root:MarkDirty() end
    function root:Layout() end
    function root:ResetMicroMenuPosition() self:SetParent(container) end
    function root:UpdateHelpTicketButtonAnchor() end

    local buttonNames = {
        "CharacterMicroButton", "ProfessionMicroButton",
    }
    if simulateForever then
        buttonNames[#buttonNames + 1] = "SpellbookMicroButton"
        buttonNames[#buttonNames + 1] = "TalentMicroButton"
        buttonNames[#buttonNames + 1] = "LegacyMicroButton"
    else
        buttonNames[#buttonNames + 1] = "PlayerSpellsMicroButton"
        buttonNames[#buttonNames + 1] = "AchievementMicroButton"
    end
    for _, name in ipairs({
        "QuestLogMicroButton", "HousingMicroButton",
        "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
        "EJMicroButton", "HelpMicroButton", "StoreMicroButton",
        "MainMenuMicroButton",
    }) do buttonNames[#buttonNames + 1] = name end
    local buttons = {}
    for _, name in ipairs(buttonNames) do
        local button = new_frame("Button", name, root)
        local createTexture = button.CreateTexture
        function button:CreateTexture(...)
            local sublevel = select(4, ...)
            assert(sublevel == nil or type(sublevel) == "number"
                and sublevel >= -8 and sublevel <= 7,
                "Micro Button texture sublevel is outside Blizzard's -8..7 range")
            return createTexture(self, ...)
        end
        button.Background = button:CreateTexture(nil, "BACKGROUND")
        button.Background:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Up")
        button.PushedBackground = button:CreateTexture(nil, "BACKGROUND")
        button.PushedBackground:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Down")
        for _, state in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do
            local texture = button:CreateTexture(nil, "ARTWORK")
            texture:SetAtlas("UI-HUD-MicroMenu-Character-Up")
            button["Set" .. state .. "Texture"](button, texture)
        end
        for _, method in ipairs({ "OnEnter", "OnLeave", "SetPushed", "SetNormal",
                "OnEnable", "OnDisable", "UpdateTabard" }) do
            button[method] = function() end
        end
        -- MainMenuBarMicroButtonMixin:OnShow/OnHide lay out Blizzard's container.
        function button:OnShow() MicroMenuContainer:Layout() end
        function button:OnHide() MicroMenuContainer:Layout() end
        function button:IsEnabled() return true end
        function button:GetButtonState() return "NORMAL" end
        function button:IsMouseOver() return self._microOver == true end
        function button:HookScript(script, callback)
            self.hoverHooks = self.hoverHooks or {}
            self.hoverHooks[script] = callback
        end
        _G[name], buttons[#buttons + 1] = button, button
    end
    root.numButtons = #buttons
    if simulateForever then
        assert(namespace.MicroMenuSkin.SetOption("buttonsPerLine", 14))
    end
    local hooksBefore = MSKIN_TEST_SECURE_HOOK_COUNT

    for _, preset in ipairs({ "modern", "midnightDark", "forever" }) do
        assert(namespace.MicroMenuSkin.ApplyPreset(preset))
        local applied = namespace.MicroMenuSkin.Apply(root, "native-art-contract")
        assert(applied, "Micro Bar native art did not apply: " .. preset)
        local bar = namespace.OwnedMicroBar.GetFrames()
        local surface = namespace.Registry.GetSurface(bar)
        assert(surface and surface.spec.role == (preset == "forever"
            and "microBarForever" or preset == "midnightDark" and "microBarDark"
            or "microBarModern"),
            "Micro Bar preset did not apply its distinct frame material: " .. preset)
        assert(root.BorderArt:GetAlpha() == (simulateForever and 0 or 1)
            and root.BackgroundArt:GetAlpha() == (simulateForever and 0 or 1),
            "Micro Bar changed the wrong client's native frame artwork")
        if preset == "forever" and simulateForever then
            assert(bar._msufForeverPortrait and bar._msufForeverPortrait:IsShown()
                and bar._msufForeverPortraitRing:IsShown()
                and bar._msufForeverPortraitRing.texture:find("ForeverPortraitRing.tga", 1, true)
                and bar:GetWidth() >= root:GetWidth() + 48
                and namespace.Materials.microBarForever.from == "microBarFill",
                "Forever Micro Bar lost its portrait and navy material")
            assert(bar:GetHeight() <= 46, "Forever Micro Bar shell is too tall")
            assert(bar._msufForeverPortrait:GetPoint(1) == "LEFT"
                and bar._msufForeverPortrait.points[1][4] == 9,
                "Forever portrait still overlaps the first button")
            assert(namespace.Defaults.icons.microMenu.buttonsPerLine == 14
                and namespace.DB.icons.microMenu.buttonsPerLine == 14,
                "Forever Micro Bar cannot fit all Camelot buttons")
        elseif preset == "modern" or preset == "midnightDark" then
            assert(bar._msufForeverPortrait and bar._msufForeverPortrait:IsShown()
                and bar._msufForeverPortraitRing:IsShown()
                and bar._msufForeverPortraitRing.texture:find("MidnightPortraitRing.tga", 1, true),
                "Midnight Micro Bar lost its portrait frame")
        end
        for _, button in ipairs(buttons) do
            local normal = button:GetNormalTexture()
            local visual = namespace.MicroMenuVisual.GetState(button)
            if preset == "forever" then
                assert(visual and visual.visible and visual.icon:IsShown()
                    and visual.plate:IsShown()
                    and visual.plate.texture:find("ForeverMicroPlate.tga", 1, true)
                    and normal:GetAtlas() == "UI-HUD-MicroMenu-Character-Up",
                    "Forever Micro Bar glyph did not replace the ornamental art")
            else
                assert(visual and visual.visible and visual.icon:IsShown()
                    and visual.plate:IsShown()
                    and visual.plate.texture:find("MidnightMicroPlate.tga", 1, true)
                    and normal:GetAtlas() == "UI-HUD-MicroMenu-Character-Up",
                    "Midnight Micro Bar did not apply its blue icon frame")
            end
        end
        if simulateForever and preset == "forever" then
            for _, name in ipairs({ "SpellbookMicroButton", "TalentMicroButton",
                    "LegacyMicroButton" }) do
                local state = namespace.MicroMenuVisual.GetState(_G[name])
                assert(state and state.visible and state.icon:IsShown()
                    and state.plate:IsShown()
                    and state.icon.texture:find("MapkoSkinMicroGlyphsBoldAtlas.png", 1, true)
                    and _G[name]:GetNormalTexture():GetAlpha() == 0,
                    "Camelot Micro Button kept Blizzard artwork: " .. name)
            end
        end
    end
    -- Four state methods per button, the guild tabard, one container and two
    -- MicroMenu hooks; re-applying presets must not add more.
    assert(MSKIN_TEST_SECURE_HOOK_COUNT - hooksBefore <= #buttons * 4 + 4,
        "Micro Bar installed more than four native hooks per button: "
            .. tostring(MSKIN_TEST_SECURE_HOOK_COUNT - hooksBefore))
    assert(namespace.MicroMenuSkin.ApplyPreset("blizzard"))
    assert(namespace.DB.icons.microMenu.layoutMode == "blizzard"
        and not namespace.OwnedMicroBar.active and root:GetParent() == container
        and root.BorderArt:GetAlpha() == 1 and root.BackgroundArt:GetAlpha() == 1
        and buttons[2]:GetNormalTexture():GetAlpha() == 1,
        "Blizzard preset did not restore the original bar and icons: "
            .. tostring(namespace.DB.icons.microMenu.layoutMode) .. " / "
            .. tostring(namespace.OwnedMicroBar.active) .. " / "
            .. tostring(root:GetParent() == container) .. " / "
            .. tostring(root.BorderArt:GetAlpha()) .. " / "
            .. tostring(root.BackgroundArt:GetAlpha()) .. " / "
            .. tostring(buttons[2]:GetNormalTexture():GetAlpha()))
    assert(namespace.MicroMenuSkin.SetOption("layoutMode", "owned")
        and namespace.DB.icons.microMenu.preset == "custom",
        "changing the Blizzard preset layout kept a misleading preset label")
    assert(namespace.MicroMenuSkin.ApplyPreset("forever")
        and namespace.OwnedMicroBar.active
        and root:GetParent() == namespace.OwnedMicroBar.GetFrames(),
        "Suite preset did not restore its own bar after Blizzard")
    if simulateForever then
        assert(namespace.MicroMenuSkin.ApplyPreset("forever"))
        local profession = _G.ProfessionMicroButton
        local nativeProfession = profession:GetNormalTexture()
        nativeProfession:SetAtlas("UI-HUD-MicroMenu-Professions-Up")
        local character = _G.CharacterMicroButton
        character.Portrait = character:CreateTexture(nil, "ARTWORK")
        character.Portrait:SetTexture("Interface\\CharacterFrame\\CharacterPortrait")
        character.Portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
        local guild = _G.GuildMicroButton
        guild.Emblem = guild:CreateTexture(nil, "OVERLAY")
        guild.HighlightEmblem = guild:CreateTexture(nil, "HIGHLIGHT")
        namespace.MicroMenuSkin.RefreshActive()
        assert(guild.Emblem:GetAlpha() == 0,
            "Suite glyph mode did not hide the native guild emblem")
        assert(namespace.MicroMenuSkin.SetOption("iconStyle", "blizzardIcons"),
            "Blizzard icons were not accepted as a separate artwork choice")
        local saved = namespace.Database.Normalize(namespace.CopyValue(namespace.DB))
        assert(saved.icons.microMenu.iconStyle == "blizzardIcons",
            "Blizzard icon choice was not preserved during profile normalization")
        local visual = namespace.MicroMenuVisual.GetState(profession)
        local characterVisual = namespace.MicroMenuVisual.GetState(character)
        local owned = namespace.OwnedMicroBar.GetFrames()
        assert(visual and not visual.visible and not visual.icon:IsShown()
            and nativeProfession:GetAtlas() == "UI-HUD-MicroMenu-Professions-Up"
            and nativeProfession:GetAlpha() == 1,
            "Blizzard icon mode did not show the native icon")
        assert(profession.Background:GetAlpha() == 0,
            "Blizzard icon mode kept the native button background")
        assert(root.BorderArt:GetAlpha() == 0,
            "Blizzard icon mode restored the native Forever frame")
        assert(owned._msufForeverPortraitRing:IsShown(),
            "Blizzard icon mode hid the Suite portrait ring")
        assert(characterVisual and not characterVisual.visible
            and character.Portrait:GetAlpha() == 1,
            "Character button hid Blizzard's live portrait")
        assert(guild.Emblem:GetAlpha() == 1 and guild.HighlightEmblem:GetAlpha() == 1,
            "Blizzard icon mode hid the native guild tabard emblem")
        nativeProfession:SetAtlas("UI-HUD-MicroMenu-Professions-Variant-Up")
        namespace.MicroMenuSkin.RefreshActive()
        assert(nativeProfession:GetAtlas() == "UI-HUD-MicroMenu-Professions-Variant-Up"
            and nativeProfession:GetAlpha() == 1,
            "Blizzard icon mode did not preserve a native icon update")
        assert(namespace.MicroMenuSkin.SetOption("iconStyle", "bold")
            and visual.icon.texture:find("MapkoSkinMicroGlyphsBoldAtlas.png", 1, true),
            "Switching from Blizzard icons did not restore Suite glyphs")
        assert(namespace.MicroMenuSkin.SetOption("iconStyle", "blizzard")
            and root.BorderArt:GetAlpha() == 1
            and root.BackgroundArt:GetAlpha() == 1,
            "Blizzard Micro Bar artwork did not restore on native icon selection")
        assert(namespace.MicroMenuSkin.ApplyPreset("forever")
            and root.BorderArt:GetAlpha() == 0,
            "Forever Micro Bar frame did not return after selecting its preset")
    end
    local queued = {}
    local previousTimer = _G.C_Timer
    _G.C_Timer = { After = function(delay, callback)
        assert(delay == 0)
        queued[#queued + 1] = callback
    end }
    local originalRefresh = namespace.MicroMenuSkin.RefreshActive
    local refreshes = 0
    namespace.MicroMenuSkin.RefreshActive = function(...)
        refreshes = refreshes + 1
        return originalRefresh(...)
    end
    buttons[1]:OnShow()
    buttons[2]:OnHide()
    assert(#queued == 1 and refreshes == 0,
        "Micro Bar layout events must coalesce into one deferred refresh")
    queued[1]()
    assert(refreshes == 1, "coalesced Micro Bar layout did not refresh")
    namespace.MicroMenuSkin.RefreshActive = originalRefresh
    _G.C_Timer = previousTimer
    assert(namespace.MicroMenuSkin.SetOption("visibility", "mouseover"))
    local bar = namespace.OwnedMicroBar.GetFrames()
    assert(bar:GetAlpha() == 0 and buttons[1].hoverHooks
        and buttons[1].hoverHooks.OnEnter and buttons[1].hoverHooks.OnLeave,
        "native Micro Bar buttons did not receive mouseover reveal hooks")
    buttons[1]._microOver = true
    buttons[1].hoverHooks.OnEnter(buttons[1])
    assert(bar:GetAlpha() == 1, "hovering a native button did not reveal the Micro Bar")
    buttons[1]._microOver = false
    buttons[1].hoverHooks.OnLeave(buttons[1])
    assert(bar:GetAlpha() == 0, "leaving a native button did not hide the Micro Bar")
    assert(namespace.MicroMenuSkin.ApplyPreset("modern")
        and namespace.DB.icons.microMenu.visibility == "mouseover",
        "changing Micro Bar look replaced the selected visibility rule")
    assert(namespace.MicroMenuSkin.Disable())
    assert(root.BorderArt:GetAlpha() == 1 and root.BackgroundArt:GetAlpha() == 1,
        "Blizzard's native Micro Bar frame did not restore on disable")
    for _, name in ipairs(buttonNames) do _G[name] = nil end
    _G.MicroMenu, _G.MicroMenuContainer = nil, nil
end
if simulateForever then
    local root = new_frame("Frame", "ProfessionsFrame", UIParent)
    local crafting = new_frame("Frame", "ProfessionsCraftingPage", root)
    local background = crafting:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("Profession-Background-Template2")
    crafting.regions = { background }
    root.CraftingPage = crafting
    local book = new_frame("Frame", "ProfessionsBookPage", root)
    local content = new_frame("Frame", "ProfessionsContentFrame", book)
    root.BookPage, book.ProfessionsContentFrame = book, content
    local cards = {}
    for _, key in ipairs({ "PrimaryProfession1", "PrimaryProfession2",
        "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }) do
        local card = new_frame("Frame", key, content)
        card.Background = card:CreateTexture(nil, "BACKGROUND")
        card.Icon = card:CreateTexture(nil, "ARTWORK")
        content[key] = card
        cards[#cards + 1] = card
    end
    _G.ProfessionsFrame = root
    namespace.DeepWindows.Apply("forever-professions-contract")
    assert(background:GetAlpha() == 0,
        "Forever crafting-page atlas retained its native art")
    for _, card in ipairs(cards) do
        assert(namespace.Registry.GetSurface(card)
            and card.Background:GetAlpha() == 0
            and card.Icon:GetAlpha() == 1,
            "Forever profession book card lost the MSUF surface or native icon")
    end
    namespace.DeepWindows.Disable("forever-professions-contract")
    namespace.GenericWindows.Disable("forever-professions-contract")
    assert(background:GetAlpha() == 1,
        "Forever profession background did not restore after disabling")
    _G.ProfessionsFrame = nil
end
assert(looks == 3 and palettes >= 5,
    "Client look catalog or palette collection changed")

local private = {}
local optionsToc = read("MSUF_Suite_Skin_Options/MSUF_Suite_Skin_Options_Mainline.toc")
assert(optionsToc:find("## LoadOnDemand: 1", 1, true))
for line in optionsToc:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line:match("%.lua$") then
        load_addon_file("MSUF_Suite_Skin_Options/" .. line:gsub("\\", "/"),
            "MSUF_Suite_Skin_Options", private)
    end
end
local options = assert(namespace.Options)
local pages = { "dashboard", "looks", "icons", "colors", "typography", "geometry",
    "skins", "coverage", "hud", "profiles", "advanced" }
for _, key in ipairs(pages) do assert(options.GetPageDefinition(key), "Missing skin submenu " .. key) end
local host = assert(options.Mount(new_frame("Frame", "SkinMount", UIParent), 980, 900))
assert(namespace.MountOptions(new_frame("Frame", "SuiteMenuMount", UIParent), 980, 900) == host,
    "Suite skin API did not mount its own embedded editor")
assert(host:ShowPage("looks") and host.key == "looks")
assert(host:ShowPage("skins") and host.key == "skins")
assert(host:ShowPage("profiles") and host.key == "profiles")
assert(host:ShowPage("advanced") and host.key == "advanced")
for _, key in ipairs(pages) do
    assert(host:ShowPage(key) and host.key == key, "embedded skin page failed to build: " .. key)
end
local searchHits = options.SearchSettings("opacity", 4)
assert(#searchHits > 0 and #searchHits <= 4 and searchHits[1].page and searchHits[1].pageLabel,
    "skin settings search returned no usable results")
host.search:SetText("opacity")
host.search.RefreshSearch()
assert(host.searchPopup:IsShown() and host.searchRows[1]:IsShown(), "embedded search showed no result rows")
host.searchRows[1]:GetScript("OnClick")(host.searchRows[1], "LeftButton")
assert(host.key == searchHits[1].page and not host.searchPopup:IsShown(),
    "embedded search result did not open its page")
options.SetMode("guided")
options.SetMode("expert")
assert(options.GetMode() == "expert" and options.SetMode("guided") and options.GetMode() == "guided",
    "skin options mode switch failed")
host:Hide()
assert(options.Open(), "standalone skin window did not open")
for _, key in ipairs(pages) do
    options.windowState.showPage(key)
    assert(options.windowState.activePage == key, "standalone skin page failed to build: " .. key)
end

local forever = {}
GameEvent = { RegisterCamelotEvents = function() end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Client.lua"))("MSUF_Suite_Skin", forever)
assert(forever.Client.flavor == "Forever" and forever.Client.isMainline
    and not forever.Client.modernEquipment, "Forever skin adapter route changed")
for _, flavor in ipairs({ "Mainline", "Mists", "TBC", "Vanilla" }) do
    local clientProfile = { Client = { flavor = flavor, isForever = false } }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", clientProfile)
    assert(clientProfile.Defaults.theme.look == "midnightDark"
        and #clientProfile.LookOrder == 3,
        "non-Forever skin client did not start with Midnight Dark: " .. flavor)
end
print("Suite skin: " .. looks .. " looks, " .. palettes .. " palettes, all submenus, migration and Forever route passed")
]=]
assert(loadstring(fixture .. contract, "suite skin integration fixture"))()
