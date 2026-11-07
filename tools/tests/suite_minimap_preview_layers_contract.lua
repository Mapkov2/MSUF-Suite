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
SUITE_OPTIONS_FIXTURE = true
local fixture = assert(original(root .. "/tools/tests/suite_options_menu_contract.lua"))()
SUITE_OPTIONS_FIXTURE = nil
local ctx = { key = "suite_minimap", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
fixture.SetCurrent(ctx)
local create, watcher = CreateFrame
CreateFrame = function(...)
    local frame = create(...)
    if ui and frame:GetParent() == ui.body then watcher = frame end
    return frame
end
fixture.M.pages.suite_minimap.build(ctx)
CreateFrame, loadfile = create, original
assert(ui, "minimap preview did not build")
local buttons = {}
for _, button in ipairs(ui.layerButtons) do buttons[button.key] = button end
local config = P.S.Config("minimap")
for key in pairs(ui.state.layers) do ui.state.layers[key] = true end
ui.state.layers.guides, ui.state.layers.hidden = false, false
local function Click(key)
    local button = buttons[key]
    button:GetScript("OnClick")(button, "LeftButton")
end
local fps
for _, item in ipairs(ui.textItems) do
    if item.spec[1] == "FPS" then fps = item.button end
end
config.infoFPS = false
ui.Paint()
assert(not fps:IsShown(), "an inactive text should start hidden")
Click("fps")
assert(fps:IsShown() and fps.alpha == 0.38 and config.infoFPS == false,
    "enabling an inactive layer must show an editable sample without touching the profile")
Click("text")
assert(not fps:IsShown(), "text group does not hide an explicitly enabled sample")
Click("fps")
assert(fps:IsShown(), "enabling an individual layer must re-open its group")
Click("fps")
Click("hidden")
assert(not fps:IsShown(), "Hidden must honor an explicitly disabled layer")
ui.state.layers.fps = nil
ui.Paint()
assert(fps:IsShown(), "Hidden does not reveal automatic inactive layers")
Click("hidden")
config.styleGlow, config.styleGlowAlpha = false, 0
ui.Paint()
assert(not ui.art.style.glow:IsShown(), "disabled glow should start hidden")
Click("glow")
assert(ui.art.style.glow:IsShown() and config.styleGlow == false and config.styleGlowAlpha == 0,
    "enabling the glow layer must show a sample without touching the profile")
Click("glow")
assert(not ui.art.style.glow:IsShown(), "disabling the glow layer left its sample behind")
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
    if not item.button:IsShown() then Click(layer) end
    assert(item.button:IsShown(), "icon layer does not reveal " .. key)
    Click(layer)
    assert(not item.button:IsShown(), "icon layer does not hide " .. key)
    ui.state.layers[layer] = nil
    ui.Paint()
end
local focused
P.W.FocusCollapsibleSection = function(section) focused = section.sectionId end
for key, section in pairs({clock="info_clock",fps="info_fps",latency="info_latency",coordinates="info_coordinates",durability="info_durability",location="info_location",weather="info_weather",difficultyText="info_difficulty",zoom="behavior",compass="behavior"}) do
    focused = nil
    buttons[key]:GetScript("OnClick")(buttons[key], "RightButton")
    local owner = section:match("^info_") and "information" or section
    assert(focused == "suite_minimap_" .. owner, "layer opened the wrong settings: " .. key)
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

-- The common painter must match 70425 even before the optional runtime loads.
-- Widget absence differs from a hidden native widget and from an unbuilt root.
do
    local oldCluster, oldCalendar, oldCompartment = MinimapCluster, GameTimeFrame, AddonCompartmentFrame
    local oldBackdrop = MinimapBackdrop
    local available, shown = P.S.MinimapElementAvailable, P.S.MinimapElementPreviewShown
    P.S.MinimapElementAvailable, P.S.MinimapElementPreviewShown = nil, nil
    local function Frame(width, height)
        return {
            GetWidth=function() return width end, GetHeight=function() return height end,
            GetCenter=function() return 0,0 end, IsShown=function() return true end,
            GetEffectiveScale=function() return 1 end, IsEnabled=function() return true end,
            GetNormalTexture=function(self) return self.normal end,
        }
    end
    local function Texture(atlas, width, height)
        return {
            atlas=atlas, IsShown=function() return true end,
            GetAtlas=function(self) return self.atlas end, GetTexture=function() return nil end,
            GetTexCoord=function() return .1,.2,.12,.4,.7,.25,.72,.45 end, GetVertexColor=function() return 1,1,1,1 end,
            GetAlpha=function() return 1 end, GetSize=function() return width,height end,
            GetCenter=function() return 0,0 end, GetEffectiveScale=function() return 1 end,
            GetDesaturation=function() return 0 end,
        }
    end
    local tracking, calendar, mail, compartment = Frame(23,23), Frame(23,23), Frame(32,24), Frame(23,22)
    tracking.Button = Frame(23,23)
    tracking.Button.StateTexture = Texture("ui-hud-minimap-tracking-button",23,23)
    tracking.Button.AddTexture = Texture("ui-hud-minimap-tracking-button",23,23)
    tracking.Button.StateTexture.GetCenter = function() return 62, 44 end
    tracking.Button.StateTexture.GetEffectiveScale = function() return 2 end
    tracking.GetCenter = function() return 120, 90 end
    tracking.GetEffectiveScale = function() return 1 end
    calendar.StateTexture = Texture("ui-hud-minimap-calendar-button",23,23)
    mail.MailIcon = Texture("ui-hud-minimap-mail-icon",32,24)
    compartment.StateTexture = Texture("ui-hud-minimap-addon-indicator",23,22)
    compartment.Text = {
        IsShown=function() return true end,
        GetCenter=function() return 1, 0 end,
        GetEffectiveScale=function() return 1 end,
        GetFont=function() return "font", 12, "OUTLINE" end,
        GetText=function() return "7" end,
        GetTextColor=function() return 1, 1, 1, 1 end,
    }
    local oldMap, oldLanding = Minimap, ExpansionLandingPageMinimapButton
    local landing = Frame(35, 29)
    landing.normal = Texture("current-expansion-landing", 35, 29)
    ExpansionLandingPageMinimapButton = landing
    local zoomIn, zoomOut = Frame(17,17), Frame(17,9)
    zoomIn.normal = Texture("zoom-in",17,17)
    zoomOut.disabled = Texture("zoom-out",17,9)
    zoomOut.disabled.GetDesaturation = function() return 1 end
    zoomOut.IsEnabled = function() return false end
    zoomOut.GetDisabledTexture = function(self) return self.disabled end
    Minimap = { ZoomIn = zoomIn, ZoomOut = zoomOut }
    MinimapCluster = { Tracking=tracking, IndicatorFrame={ MailFrame=mail } }
    GameTimeFrame, AddonCompartmentFrame = calendar, compartment
    local external = Frame(32,32)
    external.visible = false
    external.IsShown = function(self) return self.visible end
    external.Icon,external.Border = Texture(nil,34,34),Texture(nil,42,42)
    external.Icon.GetTexture = function() return "Interface\\Icons\\Spell_nature_timestop" end
    external.Border.GetTexture = function() return "Interface\\Common\\RingBorder" end
    MinimapBackdrop = { ExternalEventURLButton = external }
    config.showTracking, config.showCalendar, config.showMail, config.showCompartment = true,true,true,true
    config.showCrafting, config.showDifficulty, config.infoDifficulty = true,true,false
    ui.state.layers.hidden = false
    ui.state.layers.blizzard = true
    ui.Paint()
    local icons = {}
    for _,item in ipairs(ui.iconItems) do icons[item.spec[1]] = item end
    assert(not icons.crafting.button:IsShown(), "70425 absent Crafting widget still occupies a preview slot")
    assert(not icons.difficulty.button:IsShown(), "70425 absent difficulty widget still appears")
    for key, atlas in pairs({tracking="ui-hud-minimap-tracking-button",calendar="ui-hud-minimap-calendar-button",
        mail="ui-hud-minimap-mail-icon",compartment="ui-hud-minimap-addon-indicator"}) do
        assert(icons[key].button.previewIcon.atlas == atlas, "preview must mirror native " .. key .. " texture")
    end
    local icon = icons.tracking.button.previewIcon
    assert(#icon.texCoords == 8 and icon.texCoords[1] == .1 and icon.texCoords[8] == .45,
        "native atlas lost the eight texture coordinates")
    local scale = config.elementSize / 23 * ui.art.scale
    assert(math.abs(icon.points[1][4] - 4 * scale) < .001 and math.abs(icon.points[1][5] + 2 * scale) < .001,
        "scaled native child is misplaced")
    assert(icons.compartment.button.previewNative.text.text == "7", "native button text is missing")
    assert(ui.zoomItems[1].previewIcon.atlas == "zoom-in" and ui.zoomItems[2].previewIcon.atlas == "zoom-out"
        and ui.zoomItems[2]:GetHeight() == 9 * ui.art.scale, "zoom controls lost their native art or dimensions")
    if not P.Suite.Client.isForever then
        assert(icons.folio.button.previewIcon.atlas == "current-expansion-landing"
            and math.abs(icons.folio.button:GetWidth() - 35 * config.elementSize / 21 * .8 * ui.art.scale) < .001,
            "folio did not mirror the current expansion button")
    end
    assert(icons.tracking.button.previewNative.add:IsShown(), "native additive hover layer is missing")
    assert(not icons.tracking.backdrop:IsShown() and not icons.tracking.edge:IsShown(),
        "runtime art has a permanent preview frame")
    local compartmentY = icons.compartment.button.points[1][5]
    Click("crafting")
    assert(icons.crafting.button:IsShown() and icons.crafting.button.points[1][5] < compartmentY
        and icons.compartment.button.points[1][5] == compartmentY, "an absent button sample shifted or covered a live slot")
    ui.state.layers.crafting = nil
    Click("tracking")
    assert(not icons.tracking.button:IsShown() and icons.compartment.button.points[1][5] == compartmentY,
        "hiding a live preview button re-packed the runtime row")
    ui.state.layers.tracking = nil
    assert(not icons.externalEvent.button:IsShown(), "native hidden event button appeared in preview")
    external.visible = true
    ui.Paint()
    local eventButton = icons.externalEvent.button
    assert(eventButton:IsShown() and eventButton.previewNative.border:IsShown(), "native event visibility/border not mirrored")
    assert(eventButton.previewIcon.appliedMask == eventButton.previewIconMask, "native event circular mask missing")
    for _, mapSize in ipairs({100,300,600}) do
        config.size = mapSize
        ui.Paint()
        local maskSize = config.elementSize * ui.art.scale
        assert(math.abs(eventButton.previewIconMask:GetWidth() - maskSize) < 0.001, "event mask follows hitbox instead of native artwork")
        assert(math.abs(eventButton.previewIcon:GetWidth() - maskSize * 34 / 32) < 0.001, "native event icon/frame ratio lost")
    end
    external.GetWidth = function() return {} end
    ui.Paint()
    local inset = math.min(2, eventButton:GetWidth() / 4, eventButton:GetHeight() / 4)
    assert(eventButton.previewIconMask:GetWidth() == eventButton:GetWidth() - 2 * inset,
        "compact fallback event mask has the wrong size")
    external.GetWidth = function() return 32 end
    assert(P.MinimapPreviewData.OffsetKeys("externalEvent") == nil, "event preview introduced unregistered offsets")
    local drawerSource = P.S.MinimapDrawerPreviewSource
    config.collectButtons = true
    local single = Frame(20, 20)
    local singleArt = Texture("single-addon-art", 20, 20)
    singleArt.GetObjectType = function() return "Texture" end
    singleArt.GetDrawLayer = function() return "ARTWORK", 1 end
    singleArt.GetBlendMode = function() return "BLEND" end
    single.GetRegions = function() return singleArt end
    P.S.MinimapDrawerPreviewSource = function() return true, single end
    ui.Paint()
    local drawer = icons.drawer.button
    assert(drawer.previewDrawerArt[1].atlas == "single-addon-art" and not drawer.previewDots[1]:IsShown(),
        "single addon button was replaced by a generic drawer toggle")
    single = nil
    ui.Paint()
    assert(drawer.previewDots[1]:IsShown() and not drawer.previewDrawerArt[1]:IsShown(),
        "drawer retained old addon artwork when its toggle returned")
    P.S.MinimapDrawerPreviewSource = function() return false end
    ui.Paint()
    assert(not drawer:IsShown(), "empty runtime drawer left a visible toggle")
    P.S.MinimapDrawerPreviewSource = drawerSource

    local timer, flush, calls = C_Timer, nil, 0
    C_Timer = { After = function(_, callback) calls, flush = calls + 1, callback end }
    local onEvent = assert(watcher:GetScript("OnEvent"), "native preview watcher missing")
    assert(watcher._events.MINIMAP_UPDATE_TRACKING, "native preview did not subscribe while visible")
    tracking.Button.StateTexture.atlas = "native-tracking-refreshed"
    onEvent(watcher, "MINIMAP_UPDATE_TRACKING")
    onEvent(watcher, "UPDATE_PENDING_MAIL")
    assert(calls == 1, "runtime changes in one frame did not coalesce")
    flush()
    assert(icons.tracking.button.previewIcon.atlas == "native-tracking-refreshed", "native event failed to refresh the button")
    watcher:GetScript("OnHide")(watcher)
    assert(next(watcher._events) == nil, "hidden preview still listens for native changes")
    C_Timer = timer
    tracking.Button.normal = Texture("legacy-tracking",13,14)
    tracking.Button.StateTexture,tracking.Button.AddTexture = nil,nil
    ui.Paint()
    assert(icons.tracking.button.previewIcon.atlas == "legacy-tracking", "legacy normal texture path broken")
    assert(not icons.tracking.button.previewNative.add:IsShown(), "legacy path retained modern hover overlay")
    -- A restricted geometry result must only choose the fallback, never arithmetic.
    local secret = {}
    tracking.GetWidth = function() return secret end
    ui.Paint()
    assert(icons.tracking.button.previewIcon:IsShown(), "unresolved native geometry lost its sample")
    MinimapCluster,GameTimeFrame,AddonCompartmentFrame = nil,nil,nil
    ui.Paint()
    assert(icons.crafting.button:IsShown(), "unbuilt native root must retain the editable cold sample")
    MinimapCluster,GameTimeFrame,AddonCompartmentFrame = oldCluster,oldCalendar,oldCompartment
    MinimapBackdrop, Minimap, ExpansionLandingPageMinimapButton = oldBackdrop, oldMap, oldLanding
    P.S.MinimapElementAvailable,P.S.MinimapElementPreviewShown = available,shown
end
print("suite_minimap_preview_layers_contract: native 70425 sources and absence passed")
