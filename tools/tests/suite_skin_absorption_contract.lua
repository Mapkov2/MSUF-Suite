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
-- The skin's profile names follow the Suite's rule (MSUF_Suite/Core/Database.lua).
dofile(arg[1] .. "/tools/tests/suite_test_support.lua").SuiteProfileNames(arg[1])
WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
-- Retail and Forever scale MicroMenu by this game rule (0: no factor).
C_GameRules = C_GameRules or {}
C_GameRules.GetGameRuleAsFloat = C_GameRules.GetGameRuleAsFloat or function() return 0 end
Enum.GameRule = Enum.GameRule or { MicrobarScale = 1 }
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
-- Retail and Forever always have these APIs, so the Suite skin calls them
-- without an existence check. The stand-ins keep what this fixture did
-- without them: timers run at once, the player is not logged in yet, no
-- font object is listed, every event and installed addon is known.
C_Timer = { After = function(_, callback) callback() end }
securecallfunction = function(callback, ...) return callback(...) end
IsLoggedIn = function() return false end
GetFonts = function() return {} end
RAID_CLASS_COLORS = {}
EventUtil.ContinueAfterAllEvents = function() end
C_AddOns.DoesAddOnExist = function() return true end
C_EventUtils = { IsEventValid = function() return true end }
UIPanelWindows = {}
UpdateUIPanelPositions = function() end
ShowUIPanel = function(frame) frame:Show() end
HideUIPanel = function(frame) frame:Hide() end
IsMouseButtonDown = function() return true end
GameTooltip = { SetOwner = function() end, SetText = function() end, Show = function() end,
    Hide = function() end }
PlaySound = function() end
IsControlKeyDown = function() return false end
IsShiftKeyDown = function() return false end
-- Setters every client has that the fixture's regions lack; the skin calls
-- them on its own textures, font strings and frames.
do
    local function Noop() end
    local fixtureRegion = new_region
    new_region = function(...)
        local region = fixtureRegion(...)
        region.SetWordWrap = region.SetWordWrap or Noop
        region.SetMaxLines = region.SetMaxLines or Noop
        region.SetClipsChildren = region.SetClipsChildren or Noop
        region.SetSnapToPixelGrid = region.SetSnapToPixelGrid or Noop
        region.SetTexelSnappingBias = region.SetTexelSnappingBias or Noop
        return region
    end
end
-- Every frame has a level; the fixture's SetFrameLevel only records calls.
function Frame:GetFrameLevel() return 0 end
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
-- Client APIs the Blizzard window adapters and the owned Micro Bar call
-- without an existence check (Retail and Forever have them). The stand-ins
-- keep this fixture's former results: no global callback ever fires, the
-- hover grace ends at once, no instance or house, full-alpha health gate,
-- plain reparenting, and no secure driver or portrait art to model.
EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }
C_Timer.NewTimer = function(_, callback)
    callback()
    return { Cancel = function() end }
end
IsInInstance = function() return false end
C_Housing = { IsInsideHouseOrPlot = function() return false end }
Enum = Enum or {}
Enum.LuaCurveType = { Step = 1 }
C_CurveUtil = { CreateCurve = function()
    return { SetType = function(self, kind) self.kind = kind end,
        AddPoint = function(self, x, y) self[x] = y end }
end }
UnitHealthPercent = function() return 1 end
RegisterStateDriver = function() end
UnregisterStateDriver = function() end
SetPortraitTexture = function() end
FrameUtil = FrameUtil or {}
FrameUtil.SetParentMaintainRenderLayering = FrameUtil.SetParentMaintainRenderLayering
    or function(frame, parent) frame:SetParent(parent) end
EditModeSystemMixin = EditModeSystemMixin or { IsInDefaultPosition = function() return true end }
function Frame:RegisterUnitEvent(event, unit)
    self.events[event] = true
    self.unitEvents = self.unitEvents or {}
    self.unitEvents[event] = unit
end
-- Frames and globals of Blizzard addons that load at startup on 12.1.0,
-- 12.1.5 and Forever (none is load-on-demand); the skin reads them without a
-- check.
CommunitiesFrame = new_frame("Frame", "CommunitiesFrame", UIParent)
CommunitiesFrame.Chat = new_frame("Frame", nil, CommunitiesFrame)
CommunitiesFrameMixin = { Event = { DisplayModeChanged = "DisplayModeChanged", ClubSelected = "ClubSelected" } }
DeveloperConsole = new_frame("Frame", "DeveloperConsole", UIParent)
GeneralDockManager = new_frame("Frame", "GeneralDockManager", UIParent)
CHAT_FRAMES = {}
ChangeChatColor = ChangeChatColor or function() end
CharacterModelScene = CharacterModelScene or new_frame("ModelScene", "CharacterModelScene", UIParent)
CharacterStatsPane = CharacterStatsPane or new_frame("Frame", "CharacterStatsPane", UIParent)
QuestInfoRewardsFrame = new_frame("Frame", "QuestInfoRewardsFrame", UIParent)
QuestInfoRewardsFrame.XPFrame = new_frame("Frame", "QuestInfoXPFrame", QuestInfoRewardsFrame)
QuestInfoObjectivesFrame = new_frame("Frame", "QuestInfoObjectivesFrame", UIParent)
QuestInfoObjectivesFrame.Objectives = {}
QuestInfoSealFrame = new_frame("Frame", "QuestInfoSealFrame", UIParent)
QuestFrameGreetingPanel = QuestFrameGreetingPanel or new_frame("Frame", "QuestFrameGreetingPanel", UIParent)
QuestFrameGreetingPanel.titleButtonPool = QuestFrameGreetingPanel.titleButtonPool
    or { EnumerateActive = function() return function() end end }
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
-- A SharedButtonTemplate red button: its controller's show skins it.
local function SharedRedButton(name)
    local button = new_frame("Button", name, UIParent)
    button.atlasName = "128-RedButton"
    button.Left, button.Center, button.Right = button:CreateTexture(), button:CreateTexture(), button:CreateTexture()
    local controller = new_frame("Frame", nil, button)
    controller.OnShow = ButtonControllerMixin.OnShow
    return button, controller
end
preexisting.shared, preexisting.sharedController = SharedRedButton("ContractPreexistingSharedButton")
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
-- The split files' private bridge tables (NS.*Shared, the catalog data) are
-- taken off the namespace by the files that read them, so nothing internal
-- stays reachable through _G.MapkoSkin: no other addon can reach the public
-- API's client registry or add a DeepWindows window family.
for key in pairs(namespace) do
    assert(type(key) ~= "string" or not key:find("Shared$") and key ~= "BlizzardCatalogData",
        "a private bridge table stayed on _G.MapkoSkin: " .. tostring(key))
end
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
    -- Shown shared red buttons are skinned, adopted and new ones alike.
    preexisting.sharedController:OnShow()
    local laterShared, laterController = SharedRedButton("ContractLaterSharedButton")
    laterController:OnShow()
    for _, button in ipairs({ preexisting.shared, laterShared }) do
        assert(panelButtons.tracked[button] == "shared"
            and namespace.ControlSkin.GetOwner(button) == "uipanel-buttons",
            "a shown shared red button was not skinned: " .. button:GetName())
    end
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

    -- A button whose icon border an adapter skins through IconSkin belongs
    -- to that adapter: a public API client cannot claim it.
    local iconButton = new_frame("Button", "AdapterIconOwnerContract", UIParent)
    iconButton.Icon = iconButton:CreateTexture()
    iconButton.IconBorder = iconButton:CreateTexture()
    assert(namespace.IconSkin.Apply(iconButton, "adapter-icon-contract"),
        "IconSkin did not skin the adapter's item button")
    local claimed, claimReason = client:SkinFrame(iconButton, { role = "panel" })
    assert(not claimed and claimReason == "already-owned",
        "a public API client claimed a button IconSkin owns: " .. tostring(claimReason))
    namespace.IconSkin.DisableOwner("adapter-icon-contract")
    client:ReleaseAll()
    client:Unregister()
end
assert(namespace.DB.typography.sharedMediaFont == "MapkoSkin - Expressway ExtraBold")
assert(namespace.DB.typography.followMSUF == true,
    "Suite skin profiles must follow the MSUF font until a separate skin face is chosen")
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
local defaultLook = "cleanModern"
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
    assert(namespace.Theme.ApplyLook("midnightDark"))
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
    assert(namespace.Theme.StyleProfile(previousDark, "midnightDark"))
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
    assert(namespace.Theme.ApplyLook(defaultLook))
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
    -- 12.1 hierarchy getters (GetParent, GetRegions, GetChildren) can return
    -- secrets. A secret is skipped before it is compared, used as a key or
    -- indexed; indexing this stand-in raises the way a secret would.
    local previousSecret, previousAccess = issecretvalue, canaccessvalue
    local secret = setmetatable({}, { __index = function() error("a secret was indexed") end })
    issecretvalue = function(value) return value == secret end
    canaccessvalue = function() return false end

    local previousShell = namespace.DB.theme.shellOpacity
    namespace.DB.theme.shellOpacity = 0.4
    local panel = CreateFrame("Frame", "SecretParentPanel", UIParent)
    function panel:GetParent() return secret end
    assert(namespace.Surface.Attach(panel, { role = "panel" }),
        "a glass panel whose parent is secret was not skinned")
    namespace.DB.theme.shellOpacity = previousShell

    local holder = CreateFrame("Frame", "SecretRegionFrame", UIParent)
    local gold = holder:CreateFontString()
    gold:SetTextColor(1, 0.82, 0, 1)
    holder.regions = { secret, gold }
    assert(namespace.BlizzardYellow.TrackFrame(holder) == 1,
        "a secret region stopped the gold text pass")
    local dropdown = CreateFrame("Button", "SecretRegionDropdown", UIParent)
    dropdown.Text = dropdown:CreateFontString()
    dropdown.Text:SetTextColor(1, 0.82, 0, 1)
    dropdown.regions = { secret, dropdown.Text }
    assert(namespace.BlizzardYellow.TrackDropdown(dropdown) == 1,
        "a secret region stopped the dropdown label pass")

    local tree = CreateFrame("Frame", "SecretChildTree", UIParent)
    local visibleChild = CreateFrame("Button", "SecretTreeVisibleChild")
    function tree:GetChildren() return secret, visibleChild end
    local _, nodes = namespace.Checkmarks.TrackControlTree(tree, "secret-tree")
    assert(nodes == 2, "a secret child stopped the control tree walk")
    namespace.Checkmarks.TrackFrame(tree, "secret-tree")
    local iconButton = CreateFrame("Button", "SecretParentIconButton", UIParent)
    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon.GetParent = function() return secret end
    local iconClient = assert(namespace.GetAPI(2, 1):RegisterAddon("SecretParentIconContract", { integrationVersion = 1 }))
    local skinned, iconReason = iconClient:SkinIcon(iconButton, { icon = icon, nativeBorder = icon })
    assert(not skinned and iconReason == "foreign-region",
        "an icon whose parent is secret was not refused as foreign: " .. tostring(iconReason))
    iconClient:ReleaseAll()

    -- A tab whose IsSelected answer is secret falls back to its active art.
    local tab = CreateFrame("Button", "SecretSelectedTab", UIParent)
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do
        tab[key] = tab:CreateTexture(nil, "BACKGROUND")
    end
    function tab:IsSelected() return secret end
    assert(namespace.ControlSkin.ApplyTab(tab, "secret-tab", {}),
        "a tab with a secret selection was not skinned")
    assert(namespace.Registry.GetSurface(tab).active == true,
        "a tab whose IsSelected answer is secret ignored its shown active art")
    -- Later refreshes of these frames must not meet the stand-in again.
    panel.GetParent, tree.GetChildren, tab.IsSelected = nil, nil, nil
    holder.regions, dropdown.regions = { gold }, { dropdown.Text }
    issecretvalue, canaccessvalue = previousSecret, previousAccess
    namespace.ControlSkin.DisableOwner("secret-tab")
    namespace.Checkmarks.UntrackOwner("secret-tree")
    namespace.BlizzardYellow.Restore()
end
do
    -- Repeated visits reuse what they learned: atlas names are lowered once,
    -- a region's type is asked once, and no apply lists every client font.
    local lower, lowered = string.lower, 0
    local checkbox = CreateFrame("CheckButton", "CachedAtlasCheckbox", UIParent)
    local check = checkbox:CreateTexture(nil, "ARTWORK")
    check:SetAtlas("checkmark-minimal")
    checkbox:SetCheckedTexture(check)
    namespace.Checkmarks.TrackButton(checkbox, "cache-contract")
    string.lower = function(...) lowered = lowered + 1; return lower(...) end
    namespace.Checkmarks.TrackButton(checkbox, "cache-contract")
    string.lower = lower
    assert(lowered == 0, "a revisited button lowered its atlas names again: " .. lowered)
    namespace.Checkmarks.UntrackOwner("cache-contract")

    local row = CreateFrame("Button", "CachedRegionRow", UIParent)
    local label = row:CreateFontString()
    label:SetTextColor(1, 0.82, 0, 1)
    row.regions = { label }
    namespace.Surface.Attach(row, { role = "card" })
    local objectType, typeReads = label.GetObjectType, 0
    function label:GetObjectType()
        typeReads = typeReads + 1
        return objectType(self)
    end
    namespace.Surface.Attach(row, { role = "card" })
    assert(typeReads == 0, "a re-attached surface asked its regions for their type again")
    label:SetTextColor(1, 0.82, 0, 1)
    namespace.Surface.Attach(row, { role = "card" })
    local r, g = label:GetTextColor()
    assert(not (r == 1 and g == 0.82), "a re-initialized row kept native gold after re-attach")

    local previousFonts = GetFonts
    local fontLists = 0
    GetFonts = function()
        fontLists = fontLists + 1
        return { "ContractCatalogFont" }
    end
    local font = new_region("Font")
    font:SetTextColor(1, 0.82, 0, 1)
    _G.ContractCatalogFont = font
    local names = namespace.BlizzardFontNames
    names[#names + 1] = "ContractCatalogFont"
    namespace.BlizzardYellow.Apply()
    namespace.BlizzardYellow.Apply()
    names[#names] = nil
    local fontR, fontG = font:GetTextColor()
    assert(not (fontR == 1 and fontG == 0.82), "a catalog font kept native gold")
    assert(fontLists <= 1, "every gold text apply listed all client fonts again: " .. fontLists)
    GetFonts, _G.ContractCatalogFont = previousFonts, nil
    namespace.BlizzardYellow.Restore()
end
-- An exact Retail MinimalScrollBar contract (ScrollBarSkin's minimal kind).
local function MinimalScrollBar(name)
    local scroll = new_frame("EventFrame", name)
    local track = new_frame("Frame", name .. "Track", scroll)
    local thumb = new_frame("Frame", name .. "Thumb", track)
    local back = new_frame("Button", name .. "Back", scroll)
    local forward = new_frame("Button", name .. "Forward", scroll)
    track.Begin, track.Middle, track.End = new_region(), new_region(), new_region()
    track.Begin.alpha, track.Middle.alpha, track.End.alpha = 1, 1, 1
    track.Thumb = thumb
    thumb.Begin, thumb.Middle, thumb.End = new_region(), new_region(), new_region()
    thumb.Begin:SetVertexColor(0.12, 0.23, 0.34, 0.91)
    back.Texture, forward.Texture = new_region(), new_region()
    local nativeFields = {
        [thumb] = {
            upBeginTexture = "minimal-scrollbar-small-thumb-top",
            upMiddleTexture = "minimal-scrollbar-small-thumb-middle",
            upEndTexture = "minimal-scrollbar-small-thumb-bottom",
            overBeginTexture = "minimal-scrollbar-small-thumb-top-over",
            overMiddleTexture = "minimal-scrollbar-small-thumb-middle-over",
            overEndTexture = "minimal-scrollbar-small-thumb-bottom-over",
            downBeginTexture = "minimal-scrollbar-small-thumb-top-down",
            downMiddleTexture = "minimal-scrollbar-small-thumb-middle-down",
            downEndTexture = "minimal-scrollbar-small-thumb-bottom-down",
        },
        [back] = {
            normalTexture = "minimal-scrollbar-arrow-top",
            overTexture = "minimal-scrollbar-arrow-top-over",
            downTexture = "minimal-scrollbar-arrow-top-down",
            disabledTexture = "minimal-scrollbar-arrow-top",
        },
        [forward] = {
            normalTexture = "minimal-scrollbar-arrow-bottom",
            overTexture = "minimal-scrollbar-arrow-bottom-over",
            downTexture = "minimal-scrollbar-arrow-bottom-down",
            disabledTexture = "minimal-scrollbar-bottom-top",
        },
    }
    for object, fields in pairs(nativeFields) do
        for key, atlas in pairs(fields) do object[key] = atlas end
    end
    scroll.Track, scroll.Back, scroll.Forward = track, back, forward
    function scroll:SetScrollPercentage(value) self.scrollPercentage = value end
    function scroll:GetScrollPercentage() return self.scrollPercentage or 0 end
    function scroll:GetTrack() return self.Track end
    function scroll:GetThumb() return self.Track.Thumb end
    function scroll:GetBackStepper() return self.Back end
    function scroll:GetForwardStepper() return self.Forward end
    return scroll, thumb, back, forward
end
do
    -- Color ownership (Safety.SameColor): a color we wrote still counts as
    -- ours when it reads back at 8-bit precision (COLOR_OWN), a color another
    -- addon set close to ours does not, and Blizzard's own gold is classified
    -- with the looser COLOR_NATIVE.
    local function Near(value) return value < 0.5 and value + 0.001 or value - 0.001 end
    local function Away(value) return value < 0.5 and value + 0.01 or value - 0.01 end
    local holder = CreateFrame("Frame", "ColorOwnershipHolder", UIParent)
    local foreignText = holder:CreateFontString()
    foreignText:SetTextColor(1, 0.825, 0.005, 1)
    local ownText = holder:CreateFontString()
    ownText:SetTextColor(1, 0.82, 0, 1)
    holder.regions = { foreignText, ownText }
    assert(namespace.BlizzardYellow.TrackFrame(holder) == 2, "near-native gold was not recognized")
    local r, g, b, a = foreignText:GetTextColor()
    foreignText:SetTextColor(Away(r), g, b, a)
    r, g, b, a = ownText:GetTextColor()
    ownText:SetTextColor(Near(r), g, b, a)
    namespace.BlizzardYellow.Restore()
    assert(foreignText:GetTextColor() ~= 1, "gold text restore took back a foreign color close to ours")
    r, g = ownText:GetTextColor()
    assert(r == 1 and g == 0.82, "gold text restore missed our color read back at 8-bit precision")

    local foreignMark = holder:CreateTexture(nil, "ARTWORK")
    foreignMark:SetVertexColor(1, 0.82, 0, 1)
    local ownMark = holder:CreateTexture(nil, "ARTWORK")
    ownMark:SetVertexColor(1, 0.82, 0, 1)
    assert(namespace.Checkmarks.TrackTexture(foreignMark, "color-contract", "checkmark")
        and namespace.Checkmarks.TrackTexture(ownMark, "color-contract", "checkmark"))
    r, g, b, a = foreignMark:GetVertexColor()
    foreignMark:SetVertexColor(Away(r), g, b, a)
    r, g, b, a = ownMark:GetVertexColor()
    ownMark:SetVertexColor(Near(r), g, b, a)
    namespace.Checkmarks.UntrackOwner("color-contract")
    assert(foreignMark:GetVertexColor() ~= 1, "checkmark restore took back a foreign color close to ours")
    r, g = ownMark:GetVertexColor()
    assert(r == 1 and g == 0.82, "checkmark restore missed our color read back at 8-bit precision")

    local faded = holder:CreateTexture(nil, "BORDER")
    faded:SetVertexColor(0.3, 0.5, 0.7, 1)
    assert(namespace.Cosmetics.SuppressVertexAlpha(faded, "color-contract"))
    faded:SetVertexColor(Near(0.3), 0.5, Near(0.7), 0)
    assert(namespace.Cosmetics.Restore(faded, "color-contract"))
    assert(select(4, faded:GetVertexColor()) == 1,
        "a suppressed vertex alpha read back at 8-bit precision was not restored")

    -- Scroll bar tints read back at 8-bit precision are still ours on a
    -- theme refresh and on disable.
    local scroll, thumb, back, forward = MinimalScrollBar("ColorOwnershipScrollBar")
    local tintedRegions = { thumb.Begin, thumb.Middle, thumb.End, back.Texture, forward.Texture }
    local function ReadTintsBack()
        for _, region in ipairs(tintedRegions) do
            local tintR, tintG, tintB, tintA = region:GetVertexColor()
            region:SetVertexColor(Near(tintR), tintG, tintB, tintA)
        end
    end
    assert(namespace.ScrollBarSkin.Apply(scroll, "scroll-color-contract"), "the color contract scroll bar was not skinned")
    ReadTintsBack()
    assert(namespace.ScrollBarSkin.Refresh(scroll) == true,
        "a scroll bar refresh took its own tints read back at 8-bit precision for foreign ones")
    ReadTintsBack()
    assert(namespace.ScrollBarSkin.DisableOwner("scroll-color-contract")
        and thumb.Begin:GetVertexColor() == 0.12,
        "scroll bar disable left its tints read back at 8-bit precision behind")

    -- A secret channel never matches: it is rejected before any arithmetic.
    local previousSecret, previousAccess = issecretvalue, canaccessvalue
    issecretvalue = function(value) return value == 0.5 end
    canaccessvalue = function() return false end
    local secretMatched = namespace.Safety.SameColor(0.5, 0.2, 0.2, 1, 0.5, 0.2, 0.2, 1)
        or namespace.Safety.SameColor(0.2, 0.2, 0.2, 0.5, 0.2, 0.2, 0.2, 0.5)
    issecretvalue, canaccessvalue = previousSecret, previousAccess
    assert(not secretMatched, "Safety.SameColor compared a secret color channel")

    -- Rendering and API code use Safety's shared readers, not local copies;
    -- color matches go through Safety.ColorMatches with one argument order.
    for _, file in ipairs({ "Rendering/MicroMenuVisual.lua", "Core/PublicAPI.lua" }) do
        assert(not read("MSUF_Suite_Skin/" .. file):find("local function HasMethod", 1, true),
            file .. " keeps its own copy of Safety.HasMethod")
    end
    for _, file in ipairs({ "Core/BlizzardYellow.lua", "Core/Checkmarks.lua", "Rendering/ScrollBarSkin.lua" }) do
        local source = read("MSUF_Suite_Skin/" .. file)
        assert(not source:find("local function ShowsColor", 1, true)
            and not source:find("local function ShowsOwnColor", 1, true)
            and not source:find("local function MatchesColor", 1, true),
            file .. " keeps its own color match wrapper")
    end
    assert(not read("MSUF_Suite_Skin_Options/Shell/Widgets.lua"):find("local function SameColor", 1, true),
        "the options' 8-bit color check shadows the shared Safety.SameColor name")
    assert(not read("MSUF_Suite_Skin/Rendering/IconSkin.lua"):find("hook quality update functions", 1, true),
        "IconSkin still claims that no quality update is hooked")
end
do
    -- Engine listeners react only to the settings they depend on, and the
    -- writes of one frame (slider ticks, color-picker moves) refresh once.
    local Registry = namespace.Registry
    local owner = "listener-contract"
    local counts = { icon = 0, scroll = 0, action = 0 }
    local function Count(region, method, key)
        local original = region[method]
        region[method] = function(self, ...)
            counts[key] = counts[key] + 1
            return original(self, ...)
        end
    end
    local iconButton = CreateFrame("Button", "ListenerContractIconButton", UIParent)
    iconButton.Icon = iconButton:CreateTexture(nil, "ARTWORK")
    iconButton.IconBorder = iconButton:CreateTexture(nil, "OVERLAY")
    local iconState = assert(namespace.IconSkin.Apply(iconButton, owner, {}), "the item border was not skinned")
    Count(iconState.lines[1], "SetColorTexture", "icon")
    local scroll, thumb = MinimalScrollBar("ListenerContractScrollBar")
    assert(namespace.ScrollBarSkin.Apply(scroll, owner), "the scroll bar was not skinned")
    Count(thumb.Begin, "SetVertexColor", "scroll")
    local action = CreateFrame("Button", "ListenerContractCloseButton", UIParent)
    for _, slot in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
        local texture = action:CreateTexture(nil, "ARTWORK")
        texture:SetAtlas(slot == "Normal" and "RedButton-Exit" or "RedButton-Exit-" .. slot)
        action["Set" .. slot .. "Texture"](action, texture)
    end
    local actionState = assert(namespace.WindowActionSkin.Apply(action, owner, "close"),
        "the window action was not skinned")
    Count(actionState.glyphs.normal, "SetVertexColor", "action")
    local function ResetCounts() counts.icon, counts.scroll, counts.action = 0, 0, 0 end

    ResetCounts()
    -- Item borders write only a changed colour, so the stored border colour
    -- changes first (and the border draws it, not the native quality colour):
    -- a repaint, wanted or not, then shows in the count.
    local storedStyle = namespace.DB.theme.iconBorderStyle
    namespace.DB.theme.iconBorderStyle = "theme"
    local storedBorder = namespace.DB.theme.colors.iconBorder
    local storedRed = storedBorder[1]
    storedBorder[1] = storedRed > 0.5 and storedRed - 0.25 or storedRed + 0.25
    Registry.NotifyListeners("color", "accent")
    Registry.NotifyListeners("appearance", "shellOpacity")
    Registry.NotifyListeners("geometry", "radius")
    assert(counts.icon == 0 and counts.scroll == 0 and counts.action == 0,
        ("an unrelated setting repainted item borders %d, scroll bars %d, window actions %d times")
            :format(counts.icon, counts.scroll, counts.action))
    Registry.NotifyListeners("color", "iconBorder")
    Registry.NotifyListeners("color", "accentBright")
    Registry.NotifyListeners("color", "blizzardClose")
    assert(counts.icon > 0 and counts.scroll > 0 and counts.action > 0,
        "a color an engine surface uses did not repaint it")
    storedBorder[1] = storedRed

    local theme = namespace.DB.theme
    local look, preset, opacity = theme.look, theme.preset, theme.shellOpacity
    local borderR, borderG, borderB, borderA = namespace.Theme.GetColor("iconBorder")
    local queued = {}
    local previousTimer = _G.C_Timer
    _G.C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
    local refreshAll, fullRefreshes = Registry.RefreshAll, 0
    Registry.RefreshAll = function(...)
        fullRefreshes = fullRefreshes + 1
        return refreshAll(...)
    end
    -- The public appearance signal (MSUF menus and Suite HUD modules repaint
    -- on it) goes out once per frame for each distinct domain and key.
    local signals = {}
    hooksecurefunc(namespace.PublicAPI.API, "OnAppearanceChanged", function(_, domain, key)
        signals[#signals + 1] = tostring(domain) .. ":" .. tostring(key)
    end)
    ResetCounts()
    for step = 1, 5 do
        assert(namespace.Theme.SetAppearance("shellOpacity", 0.5 + step * 0.05))
        assert(namespace.Theme.SetColor("iconBorder", step * 0.1, borderG, borderB, borderA))
    end
    assert(fullRefreshes == 0 and counts.icon == 0,
        "every settings write refreshed the surfaces and item borders at once")
    assert(#signals == 0, "the appearance signal went out for every settings write")
    local index = 1
    while queued[index] do
        queued[index]()
        index = index + 1
    end
    assert(fullRefreshes == 1 and counts.icon == 1,
        ("a frame of settings writes refreshed the surfaces %d and the item borders %d times")
            :format(fullRefreshes, counts.icon))
    table.sort(signals)
    assert(#signals == 2 and signals[1] == "appearance:shellOpacity" and signals[2] == "color:iconBorder",
        "a frame of settings writes sent the appearance signals " .. table.concat(signals, ", "))
    Registry.RefreshAll = refreshAll
    _G.C_Timer = previousTimer
    namespace.Theme.SetAppearance("shellOpacity", opacity)
    namespace.Theme.SetColor("iconBorder", borderR, borderG, borderB, borderA)
    theme.look, theme.preset, theme.iconBorderStyle = look, preset, storedStyle
    namespace.IconSkin.DisableOwner(owner)
    namespace.ScrollBarSkin.DisableOwner(owner)
    namespace.WindowActionSkin.DisableOwner(owner)
end
do
    -- Micro Button state changes (SetNormal, SetPushed, hover) repaint the
    -- overlay and re-check the borrowed performance bar without allocating.
    -- These stand-in regions store what is written and allocate nothing, so
    -- any growth below comes from the skin.
    local function Noop() end
    local quiet = { IsForbidden = function() return false end,
        IsProtected = function() return false, false end }
    for _, name in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetTexture", "SetTexCoord",
        "SetVertexColor", "SetGradient", "SetDesaturated", "SetShown", "Show", "Hide", "SetAtlas",
        "SetIgnoreParentAlpha", "SetIgnoreParentScale", "SetAllPoints", "SetColorTexture",
        "AddMaskTexture", "RemoveMaskTexture", "ClearTextureSlice", "SetTextureSliceMargins",
        "SetTextureSliceMode", "SetDrawLayer" }) do
        quiet[name] = Noop
    end
    local quietMeta = { __index = quiet }
    local function Quiet() return setmetatable({}, quietMeta) end
    local button = Quiet()
    function button.CreateTexture() return Quiet() end
    function button.CreateMaskTexture() return Quiet() end
    local stateTextures = { Normal = Quiet(), Highlight = Quiet(), Pushed = Quiet(), Disabled = Quiet() }
    function button.GetNormalTexture() return stateTextures.Normal end
    function button.GetHighlightTexture() return stateTextures.Highlight end
    function button.GetPushedTexture() return stateTextures.Pushed end
    function button.GetDisabledTexture() return stateTextures.Disabled end
    local bar = setmetatable({ texture = "bar", layer = "ARTWORK", subLevel = 0,
        left = 0, right = 1, top = 0, bottom = 1, width = 2, height = 10,
        point = "LEFT", relativeTo = button, relativePoint = "LEFT", x = 0, y = 0 }, quietMeta)
    function bar:GetNumPoints() return 1 end
    function bar:GetPoint() return self.point, self.relativeTo, self.relativePoint, self.x, self.y end
    function bar:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point, self.relativeTo, self.relativePoint, self.x, self.y = point, relativeTo, relativePoint, x, y
    end
    function bar:GetAtlas() return self.atlas end
    function bar:GetTexture() return self.texture end
    function bar:SetColorTexture() self.atlas, self.texture = nil, "flat" end
    function bar:SetTexture(texture) self.atlas, self.texture = nil, texture end
    function bar:SetAtlas(atlas) self.atlas = atlas end
    function bar:GetTexCoord() return self.left, self.right, self.top, self.bottom end
    function bar:SetTexCoord(left, right, top, bottom)
        self.left, self.right, self.top, self.bottom = left, right, top, bottom
    end
    function bar:GetDrawLayer() return self.layer, self.subLevel end
    function bar:SetDrawLayer(layer, subLevel) self.layer, self.subLevel = layer, subLevel end
    function bar:GetWidth() return self.width end
    function bar:GetHeight() return self.height end
    function bar:SetSize(width, height) self.width, self.height = width, height end
    function bar:GetVertexColor() return 0.2, 0.9, 0.2, 1 end
    button.MainMenuBarPerformanceBar = bar

    local settings = namespace.CopyValue(namespace.DB.icons.microMenu)
    settings.iconStyle, settings.hoverStyle, settings.buttonBackground = "bold", "softFill", true
    local visual = namespace.MicroMenuVisual
    local STATES = { "normal", "pushed", "normal", "highlight", "pressed", "disabled" }
    local function Cycle()
        for _, stateName in ipairs(STATES) do
            visual.Apply(button, "MainMenuMicroButton", settings, stateName)
            visual.Refresh(button, settings, stateName)
        end
    end
    Cycle()
    assert(bar.width == 2 and bar.layer == "OVERLAY" and bar.texture == "flat",
        "the Micro Bar did not borrow the performance bar")
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 25 do Cycle() end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    assert(grown < 1, ("Micro Button state changes allocated %.1f KB"):format(grown))
    assert(visual.Restore(button) and bar.layer == "ARTWORK" and bar.texture == "bar"
        and bar.point == "LEFT", "the performance bar was not returned as found")
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
assert(#namespace.LookOrder == 5
    and namespace.LookOrder[1] == "cleanModern"
    and namespace.LookOrder[2] == "midnight"
    and namespace.LookOrder[3] == "foreverGlass"
    and namespace.LookOrder[4] == "midnightDark"
    and namespace.LookOrder[5] == "classColor",
    "Skinning menu must expose Clean Modern, Blue, Forever, Dark and Class Style")
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
assert(namespace.Defaults.icons.microMenu.preset == "modern"
    and namespace.Defaults.icons.microMenu.iconStyle == "bold"
    and (simulateForever or (namespace.Defaults.icons.microMenu.spacing == 5
        and namespace.Defaults.icons.microMenu.padding == 5))
    and namespace.Defaults.icons.microMenu.tint == "theme"
    and namespace.Defaults.hud.objectiveTrackerStyle == nil
    and namespace.Defaults.skins.objectiveTracker == nil,
    "fresh Suite skin profile must leave Blizzard tracker styling out")
if not simulateForever then
    local factory = namespace.CopyValue(namespace.Defaults)
    factory.revision = 50
    factory.icons.microMenu.spacing = 1
    factory.icons.microMenu.padding = 6
    factory.icons.microMenu.layoutX = -518
    namespace.Database.Normalize(factory)
    assert(factory.icons.microMenu.spacing == 5 and factory.icons.microMenu.padding == 5,
        "old Retail panel-side Micro Bar did not reach the DataTexts top")
    local previous = namespace.CopyValue(namespace.Defaults)
    previous.revision = 51
    previous.icons.microMenu.padding = 6
    namespace.Database.Normalize(previous)
    assert(previous.icons.microMenu.spacing == 5 and previous.icons.microMenu.padding == 5,
        "revision 51 Micro Bar retained its 1-2px top-edge mismatch")
    local custom = namespace.CopyValue(namespace.Defaults)
    custom.revision = 50
    custom.icons.microMenu.spacing = 2
    namespace.Database.Normalize(custom)
    assert(custom.icons.microMenu.spacing == 2,
        "Micro Bar alignment migration replaced custom grid spacing")
    local moved = namespace.CopyValue(namespace.Defaults)
    moved.revision = 50
    moved.icons.microMenu.spacing = 1
    moved.icons.microMenu.layoutX = -400
    namespace.Database.Normalize(moved)
    assert(moved.icons.microMenu.spacing == 1,
        "Micro Bar alignment migration changed a freely positioned bar")
    local originalMicro = namespace.DB.icons.microMenu
    namespace.DB.icons.microMenu = namespace.CopyValue(namespace.Defaults.icons.microMenu)
    assert(namespace.MicroMenuSkin.ApplyPreset("modern")
        and namespace.DB.icons.microMenu.padding == 5
        and namespace.DB.icons.microMenu.scale == 0.7,
        "reapplying Modern lost the panel-edge alignment")
    assert(namespace.MicroMenuSkin.ApplyPreset("blizzard")
        and namespace.MicroMenuSkin.ApplyPreset("modern")
        and namespace.DB.icons.microMenu.padding == 5
        and namespace.DB.icons.microMenu.scale == 0.7,
        "returning from Blizzard Micro Buttons lost the panel-edge alignment")
    assert(namespace.Theme.ApplyLook("midnight")
        and namespace.DB.icons.microMenu.padding == 5,
        "changing Suite looks lost the panel-edge alignment")
    assert(namespace.Theme.ApplyLook(defaultLook))
    namespace.DB.icons.microMenu = originalMicro
end
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
    local previousDriver, previousUndriver = _G.RegisterStateDriver, _G.UnregisterStateDriver
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
    -- MicroMenuMixin on Retail and Forever: anchor in the container and
    -- Blizzard's own scale; neither writes a field.
    function root:AnchorToMenuContainer()
        if self:GetParent() ~= container then return end
        self:ClearAllPoints()
        self:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end
    function root:UpdateScale() self:SetScale(1) end
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
    assert(registeredElement.label == namespace.L["Micro Bar"] and registeredElement.group == namespace.L["MSUF Suite"]
        and registeredElement.extraControls[1].label == namespace.L["Per line"]
        and registeredElement.extraControls[5].label == namespace.L["Vertical"],
        "Micro Bar joined MSUF Edit Mode without localized labels")
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
    _G.Enum = { LuaCurveType = { Step = 1 }, GameRule = Enum.GameRule }
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
    _G.RegisterStateDriver, _G.UnregisterStateDriver = previousDriver, previousUndriver
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
    function root:AnchorToMenuContainer() end
    function root:UpdateScale() self:SetScale(1) end
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
        if preset == "modern" then
            local plate = namespace.MicroMenuVisual.GetState(buttons[1]).plate
            local previousLook = namespace.DB.theme.look
            namespace.DB.theme.look = "cleanModern"
            namespace.MicroMenuSkin.RefreshActive()
            assert(plate:IsDesaturated(), "Clean Modern retained the blue Micro Bar plate")
            namespace.DB.theme.look = "midnight"
            namespace.MicroMenuSkin.RefreshActive()
            assert(not plate:IsDesaturated(), "Midnight lost its blue Micro Bar plate")
            namespace.DB.theme.look = previousLook
            namespace.MicroMenuSkin.RefreshActive()
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
    -- Four state methods per button, the guild tabard, one container and the
    -- owned bar's MicroMenu hooks (its UpdateScale keeps the owned scale);
    -- re-applying presets must not add more.
    assert(MSKIN_TEST_SECURE_HOOK_COUNT - hooksBefore <= #buttons * 4 + 5,
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
assert(looks == 5 and palettes >= 5,
    "Client look catalog or palette collection changed")

local private = {}
_G.MSUFSuite = { Database = _G.MSUFSuite.Database, Client = {
    AttachControllerWindow = function() end,
    PauseControllerWindow = function() end,
    ResumeControllerWindow = function() end,
    RaiseControllerCursor = function() end,
} }
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
do
    -- The look note belongs to the preview panel it is drawn on.
    local looksPage = host.pages.looks
    local note = looksPage._mskinLookNoteTitle:GetParent()
    local noteParent = note:GetParent()
    local parentSurface = namespace.Registry.GetSurface(noteParent)
    assert(noteParent ~= looksPage and parentSurface and parentSurface.spec.role == "navigation",
        "the look note is not a child of the preview panel")
    -- Showing the host again repaints the current page.
    local repaints = 0
    options.TrackRefresh(function() repaints = repaints + 1 end)
    local onShow = host:GetScript("OnShow")
    assert(type(onShow) == "function", "the embedded host does not repaint when it is shown")
    onShow(host)
    assert(repaints == 1, "showing the embedded host did not refresh the options")
end
do
    -- A query is split into words once, not once per search record.
    local gmatch, splits = string.gmatch, 0
    string.gmatch = function(...) splits = splits + 1; return gmatch(...) end
    options.SearchSettings("window opacity", 8)
    string.gmatch = gmatch
    assert(splits <= 1, "the skin search split the query once per record: " .. splits)
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
do
    local retail = { Client = { flavor = "Mainline", isMainline = true, isForever = false } }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", retail)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", retail)
    assert(retail.Defaults.theme.look == "cleanModern" and #retail.LookOrder == 5,
        "the Retail skin client did not start with Clean Modern")
end
do
    -- Classic project IDs are no Suite client any more.
    local classic = {}
    local previousProject, previousEvent = WOW_PROJECT_ID, GameEvent
    WOW_PROJECT_ID, WOW_PROJECT_CLASSIC, GameEvent = 2, 2, nil
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Client.lua"))("MSUF_Suite_Skin", classic)
    WOW_PROJECT_ID, WOW_PROJECT_CLASSIC, GameEvent = previousProject, nil, previousEvent
    assert(classic.Client.flavor == "Unknown" and not classic.Client.isMainline,
        "the skin engine still maps a Classic client")
    -- The Suite copy is canonical: the vendor script refuses to overwrite it
    -- unless it is told to on purpose. The run points at a checkout that does
    -- not exist, so even a script without the guard could not copy anything.
    local guarded = assert(io.open(root .. "/tools/vendor-suite-skin.py", "rb"))
    local guardedSource = guarded:read("*a")
    guarded:close()
    assert(guardedSource:find('"--force-overwrite-suite"', 1, true),
        "the vendor script has no --force-overwrite-suite guard")
    local python = os.getenv("MSUF_PYTHON")
        or [[C:\Users\Marco\AppData\Local\Programs\Python\Python312-32\python.exe]]
    local pythonFile = io.open(python, "rb")
    if pythonFile then
        pythonFile:close()
        local run = assert(io.popen('""' .. python .. '" "' .. root .. '/tools/vendor-suite-skin.py" "'
            .. root .. '/no-such-mapkoskin-checkout" 2>&1"'))
        local output = run:read("*a")
        run:close()
        assert(output:find("Refusing to vendor", 1, true)
            and output:find("--force-overwrite-suite", 1, true),
            "the vendor script ran without --force-overwrite-suite: " .. output)
    end
    local vendor = assert(io.open(root .. "/tools/vendor-suite-skin.py", "rb"))

    local vendorSource = vendor:read("*a")
    vendor:close()
    assert(not vendorSource:find('"Vanilla"', 1, true) and not vendorSource:find('"Mists"', 1, true)
        and not vendorSource:find('"TBC"', 1, true), "the vendor script still writes Classic TOCs")
end
-- The Suite ships the Mainline TOC only; Forever loads it too.
for _, addon in ipairs({ "MSUF_Suite_Skin", "MSUF_Suite_Skin_Options" }) do
    for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
        local stale = io.open(root .. "/" .. addon .. "/" .. addon .. "_" .. flavor .. ".toc", "rb")
        if stale then stale:close() end
        assert(not stale, addon .. " still ships a " .. flavor .. " TOC")
    end
end
if not simulateForever then
    local msufRoot = assert(arg[3], "Retail MSUF root required for the Suite Skin Menu2 contract")
    Frame.SetToplevel = Frame.SetToplevel or function() end
    namespace.PublicAPI.playerReady = true
    namespace.DB.enabled = true
    local suiteApi, apiReason = namespace.GetAPI(2, 1)
    assert(suiteApi and suiteApi:IsEnabled(), "Suite API unavailable for MSUF: "
        .. tostring(apiReason) .. " ready=" .. tostring(namespace.PublicAPI.playerReady)
        .. " migrating=" .. tostring(namespace.migrationOnly))
    assert(not namespace.migrationOnly, "Suite Skin remained in migration-only mode")
    function Frame:HookScript(script, callback)
        local previous = self:GetScript(script)
        self:SetScript(script, function(...)
            if previous then previous(...) end
            callback(...)
        end)
    end
    _G.MSUF_DB = { general = {} }
    _G.MSUF_SetFontChecked = function(fs, font, size, flags)
        fs:SetFont(font, size, flags)
        return true
    end
    local menu = {}
    function menu.Lines(value) return value:gmatch("[^\r\n]+") end
    function menu.WordList(value)
        local words = {}
        for word in value:gmatch("%S+") do words[#words + 1] = word end
        return words
    end
    function menu.AssignNamedValues(target, names, ...)
        local index = 0
        for name in names:gmatch("%S+") do index = index + 1; target[name] = select(index, ...) end
    end
    function menu.Tr(value) return value end
    menu.Translate = menu.Tr
    function menu.FindPageEntry() return nil end
    local msuf = { MSUF2 = menu, Translate = menu.Tr,
        ExportPublic = function(key, value) _G[key] = value end }
    local function LoadMSUF(path)
        return assert(loadfile(msufRoot .. "/" .. path))("MidnightSimpleUnitFrames", msuf)
    end
    LoadMSUF("MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua")
    LoadMSUF("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua")
    LoadMSUF("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua")
    local theme = menu.Theme
    local shell = new_frame("Frame", "SuiteSkinMenuShell", UIParent)
    local host = new_frame("Frame", "SuiteSkinMenuHost", shell)
    shell.host = host
    menu.frame = shell
    local veil = menu.ShowFocusVeil(host, "dropdown", { referenceFrame = shell })
    assert(veil and veil._msuf2FocusDim and veil._msuf2FocusDim:IsShown()
        and not namespace.Registry.GetSurface(veil),
        "Suite Skin turned the dropdown veil into an opaque panel")
    menu.ResetFocusVeil("dropdown")
    local nav = theme.Button(host, "Auras", 120, 24)
    nav._msuf2NavItem = true
    nav:RefreshVisual()
    nav:SetActive(true)
    assert(nav._msuf2SkinnedSelectionCue and nav._msuf2SkinnedSelectionCue.line:IsShown(),
        "Suite Skin did not show the active Auras navigation cue: active="
            .. tostring(msuf.MenuSkin.IsActive()) .. " surface="
            .. tostring(namespace.Registry.GetSurface(nav)))
    assert(nav._msuf2SkinnedSelectionCue.wash.colorTexture[4] >= 0.18
        and nav._msuf2SkinnedSelectionCue.line.colorTexture[4] >= 0.90
        and nav._msuf2SkinnedSelectionCue.line.width >= 3,
        "Suite Skin Auras selection cue is too faint")
    local choice = theme.Button(host, "Debuffs", 96, 24)
    choice._msuf2SegmentChoice = true
    choice:SetActive(true)
    assert(choice._msuf2SkinnedSelectionCue and choice._msuf2SkinnedSelectionCue.line:IsShown(),
        "Suite Skin did not show the selected Debuffs cue")
    choice:SetActive(false)
    assert(not choice._msuf2SkinnedSelectionCue.line:IsShown(),
        "Suite Skin kept the Debuffs cue after deselection")
end
print("Suite skin: " .. looks .. " looks, " .. palettes .. " palettes, all submenus, migration and Forever route passed")
]=]
assert(loadstring(fixture .. contract, "suite skin integration fixture"))()
