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
-- The fallback fixture provides no real host Refresh method on its buttons.
if not rawget(buttons.fps, "Refresh") then buttons.fps.Refresh = false end
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
local bridge = P.Suite.HostBridge
local open, exact = bridge.OpenExactMenuSetting
bridge.OpenExactMenuSetting = function(_, page, section, key)
    assert(page == "suite_minimap")
    exact = section .. ":" .. key
    return true
end
config.infoFPS = false
ui.Paint()
Click("fps")
assert(exact == "suite_minimap_info_fps:msufsuite.minimap.infoFPS" and not fps:IsShown() and config.infoFPS == false,
    "an off FPS display must jump to Show FPS without changing the profile or the preview")
config.infoFPS = true
ui.Paint()
assert(not buttons.fps._suiteLayerMuted and buttons.fps:GetAlpha() == 1, "legacy layer did not restore the active styling")
Click("text")
assert(not fps:IsShown(), "text group does not hide an enabled display")
Click("fps")
assert(fps:IsShown(), "enabling an individual preview layer must re-open its group")
Click("fps")
config.infoFPS = false
Click("hidden")
assert(not fps:IsShown(), "Hidden must honor an explicitly hidden preview layer")
ui.state.layers.fps = nil
ui.Paint()
assert(fps:IsShown(), "Hidden does not reveal automatic inactive layers")
assert(buttons.fps._suiteLayerMuted and buttons.fps:GetAlpha() < 1, "a visible preview sample lost the disabled styling")
exact = nil
Click("fps")
assert(exact == "suite_minimap_info_fps:msufsuite.minimap.infoFPS" and fps:IsShown() and config.infoFPS == false,
    "the visible disabled FPS example must still open Show FPS")
Click("hidden")
config.styleGlow, config.styleGlowAlpha = false, 0
ui.Paint()
Click("glow")
assert(exact == "suite_minimap_style_glow:msufsuite.minimap.styleGlow" and not ui.art.style.glow:IsShown()
    and config.styleGlow == false and config.styleGlowAlpha == 0, "an off glow must open its own enable switch")
config.styleGlow = true
Click("glow")
assert(exact == "suite_minimap_style_glow:msufsuite.minimap.styleGlowAlpha", "a transparent glow must open its opacity")
config.styleGlowAlpha = 50
ui.Paint()
Click("glow")
assert(not ui.art.style.glow:IsShown() and config.styleGlow, "preview-only hiding affected the glow setting")
bridge.OpenExactMenuSetting = open
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
config.infoDifficulty = false
for _, item in ipairs(ui.iconItems) do
    local key, setting = item.spec[1], item.spec[4]
    if setting and type(config[setting]) == "boolean" then config[setting] = true end
    if key == "folio" then config.showLanding = 1 end
    ui.Paint()
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
    config.zoomButtons = P.Suite.MinimapZoomButtons.ALWAYS
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
    local minus = ui.zoomItems[2].previewZoomOutGlyph
    assert(minus and minus.line.color[1] == .73 and minus.line:GetWidth() == 9 * ui.art.scale,
        "preview must show the shared minus at the lowest zoom")
    zoomOut.GetDisabledTexture = function() end
    ui.Paint()
    assert(not ui.zoomItems[2].previewIcon:IsShown() and minus.line:IsShown() and minus.line.color[4] == 1,
        "an unavailable native texture erased the preview's minus")
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
    P.S.MinimapElementPreviewShown = function(key)
        if key == "Tracking" then return false, true end
    end
    ui.Paint()
    assert(not icons.tracking.button:IsShown() and icons.compartment.button.points[1][5] == compartmentY,
        "a live mouseover-only button appeared or displaced the buttons after it")
    P.S.MinimapElementPreviewShown = nil
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
    assert(drawer.previewDrawerArt[1].atlas == "single-addon-art" and not drawer.previewIcon:IsShown(),
        "single addon button was replaced by a generic drawer toggle")
    single = nil
    local styles = P.Suite.MinimapDrawerStyle
    local media = "Interface\\AddOns\\MSUF_Suite\\Media\\"
    local previousStyle = config.drawerStyle
    for style, asset in pairs({
        [styles.FOREVER] = "SuiteIconForever.tga", [styles.MODERN] = "SuiteIconModern.tga", [styles.DARK] = "SuiteIconDark.tga",
    }) do
        config.drawerStyle = style
        ui.Paint()
        assert(drawer.previewIcon:IsShown() and drawer.previewIcon.texture == media .. asset
            and not drawer.previewDrawerArt[1]:IsShown(), "preview did not show the selected Suite badge")
    end
    config.drawerStyle = previousStyle
    P.S.MinimapDrawerPreviewSource = function() return true, nil, false end
    ui.state.layers.addons = nil
    ui.Paint()
    assert(not drawer:IsShown(), "mouseover drawer toggle appeared while runtime hid it")
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

-- Use the real runtime and options setters together, with the deferred menu refresh parked.
local H = assert(original(root .. "/tools/tests/suite_minimap_harness.lua"))()
local function CheckZoomArrangement(runtime)
    local layout, c = P.Suite.MinimapZoomLayout, runtime.config
    local scale = ui.art.scale
    local function Position(button)
        local point = button.points[1]
        return point[4], point[5]
    end
    local function Near(a, b) return math.abs(a - b) < .0001 end
    local function MatchPositions()
        local ix, iy = Position(runtime.map.ZoomIn)
        local ox, oy = Position(runtime.map.ZoomOut)
        local px, py = Position(ui.zoomItems[1])
        local mx, my = Position(ui.zoomItems[2])
        assert(Near(px, ix * scale) and Near(py, iy * scale) and Near(mx, ox * scale) and Near(my, oy * scale),
            "zoom arrangement reached only one view")
        return ix, iy, ox, oy
    end
    assert(P.SetMany("minimap", { zoomInX = 21, zoomInY = 154, zoomOutX = 1, zoomOutY = 158 }))
    local ix, iy, ox, oy = MatchPositions()
    assert(c.zoomLayout == layout.FREE and ix == 19 and iy == 181 and ox == -1 and oy == 160,
        "the default moved existing independently positioned buttons")
    for _, orientation in ipairs({ layout.ABOVE, layout.BELOW, layout.LEFT, layout.RIGHT }) do
        assert(P.Set("minimap", "zoomLayout", orientation))
        local px, py, mx, my = MatchPositions()
        local dx, dy = px - mx, py + 8.5 - my - 4.5
        assert(Near(px + mx, ix + ox) and Near(py + my, iy + oy), "aligning displaced the center of the pair")
        assert((orientation == layout.ABOVE and Near(dx, 0) and dy > 0)
            or (orientation == layout.BELOW and Near(dx, 0) and dy < 0)
            or (orientation == layout.LEFT and Near(dy, 0) and dx < 0)
            or (orientation == layout.RIGHT and Near(dy, 0) and dx > 0), "zoom orientation did not align button centers")
    end
    ix, iy, ox, oy = MatchPositions()
    assert(ui.zoomGroup:IsShown(), "visible zoom controls have no joint drag handle")
    local oldCursor = GetCursorPosition
    local cursorX, cursorY = 100, 100
    GetCursorPosition = function() return cursorX, cursorY end
    local group = ui.zoomGroup
    group:GetScript("OnMouseDown")(group, "LeftButton")
    cursorX, cursorY = cursorX + 12 * scale, cursorY - 5 * scale
    group:GetScript("OnUpdate")(group)
    local px, py = Position(ui.zoomItems[1])
    local mx, my = Position(ui.zoomItems[2])
    assert(Near(px, (ix + 12) * scale) and Near(py, (iy - 5) * scale)
        and Near(mx, (ox + 12) * scale) and Near(my, (oy - 5) * scale) and c.zoomGroupX == 0,
        "dragging the group did not move both preview buttons together before committing")
    group:GetScript("OnMouseUp")(group, "LeftButton")
    GetCursorPosition = oldCursor
    local gx, gy, hx, hy = MatchPositions()
    assert(c.zoomLayout == layout.RIGHT and Near(gx, ix + 12) and Near(gy, iy - 5)
        and Near(hx, ox + 12) and Near(hy, oy - 5), "the drag did not move the pair as one group")
    ui.kit:Select(ui.zoomItems[1])
    assert(ui.kit:Nudge(7, 4))
    local nx, ny, tx, ty = MatchPositions()
    assert(c.zoomLayout == layout.FREE and Near(nx, gx + 7) and Near(ny, gy + 4)
        and Near(tx, hx) and Near(ty, hy), "moving only plus displaced minus or lost the group offset")
    ui.kit:Select(ui.zoomItems[2])
    assert(ui.kit:Nudge(-4, 3))
    px, py, mx, my = MatchPositions()
    assert(Near(px, nx) and Near(py, ny) and Near(mx, tx - 4) and Near(my, ty + 3), "moving only minus displaced plus")
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    local minute = 33
    local runtime = H.New(root, client, { beforeModules = function(W)
        W.G.GetGameTime = function() return 9, minute end
        W.G.date = function() return { day = 22, month = 11, year = 2026, hour = 9 } end
        W.G.FormatShortDate = function() return "22.11.2026" end
    end })
    runtime.editModeReady = true
    H.Enable(runtime, { captured = true, infoClock = true, infoClock24Hour = true,
        infoClockDate = true, infoClockSize = 25, infoClockWidth = 120 })
    runtime.Step()
    local suite = P.S
    local oldConfig, oldSet, oldSetMany = suite.Config, suite.Set, suite.SetMany
    local oldRequest, oldMap, oldTimer = fixture.M.RequestRefresh, Minimap, C_Timer
    local flush
    C_Timer = { After = function(_, callback) flush = callback end }
    Minimap = runtime.map
    for _, button in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut }) do
        button.GetNormalTexture = function() end
        button.GetDisabledTexture = function() end
    end
    suite.Config = function(id) return id == "minimap" and runtime.config or oldConfig(id) end
    suite.Set, suite.SetMany = runtime.S.Set, runtime.S.SetMany
    suite.MinimapInfoPreviewSource = runtime.S.MinimapInfoPreviewSource
    suite.SetMinimapPreviewListener = runtime.S.SetMinimapPreviewListener
    suite.MinimapZoomPreviewShown = runtime.S.MinimapZoomPreviewShown
    fixture.M.RequestRefresh = function() end
    ui.state.layers.clock, ui.state.layers.zoom, ui.state.layers.hidden = nil, nil, false
    watcher:GetScript("OnShow")(watcher)
    local clock
    for _, item in ipairs(ui.textItems) do
        if item.spec[1] == "Clock" then clock = item end
    end
    local label = runtime.M.infoEntries.Clock.label
    local second = runtime.M.infoEntries.Clock.clockSecond
    assert(clock.label.text == "09:33  22.11.2026" and clock.label.text == label.text,
        client .. " preview lost the date shown by the live clock")
    assert(clock.label.width == 120 * ui.art.scale, "clock width diverged from its live truncation constraint")
    assert(P.SetMany("minimap", { infoClockDatePosition = 2, infoClockWidth = 96, size = 260 }))
    assert(clock.label.text == label.text and clock.label.text == "22.11.2026" and ui.art.scale == 94 / 260
        and clock.clockSecond.text == second.text and clock.clockSecond.text == "09:33" and clock.clockSecond:IsShown()
        and clock.label.width == 96 * ui.art.scale and clock.button.height == (25 * 2 + 8) * ui.art.scale,
        "settings did not repaint both views immediately with the same two-line clock geometry")
    assert(P.SetMany("minimap", { infoClockDatePosition = 3, infoClockWidth = 120 }))
    assert(clock.label.text == label.text and clock.label.text == "09:33"
        and clock.clockSecond.text == second.text and clock.clockSecond.text == "22.11.2026" and clock.clockSecond:IsShown()
        and clock.clockSecond.width == 120 * ui.art.scale,
        "reported below-clock date did not appear in both views")
    minute = 34
    runtime.Advance(61)
    assert(clock.label.text == label.text and clock.label.text:find("09:34", 1, true), "preview clock did not follow a live tick")
    assert(not ui.zoomItems[1]:IsShown(), "mouseover-only zoom shown while the live zoom holder is hidden")
    runtime.Fire(runtime.MM.catcher, "OnEnter")
    flush()
    assert(ui.zoomItems[1]:IsShown(), "preview did not follow the live zoom reveal")
    runtime.Fire(runtime.MM.catcher, "OnLeave")
    runtime.Advance(.2)
    flush()
    assert(not ui.zoomItems[1]:IsShown(), "preview did not follow the live zoom hide")
    assert(P.Set("minimap", "zoomButtons", P.Suite.MinimapZoomButtons.ALWAYS))
    assert(ui.zoomItems[1]:IsShown() and runtime.MM.zoomHolder:IsVisible(), "Always did not reveal both views immediately")
    CheckZoomArrangement(runtime)
    watcher:GetScript("OnHide")(watcher)
    flush()
    assert(P.RefreshMinimapPreview == nil, "hidden preview retained the synchronous settings callback")
    minute = 35
    runtime.Advance(61)
    assert(clock.label.text ~= label.text, "hidden preview received a live update")
    watcher:GetScript("OnShow")(watcher)
    assert(clock.label.text == label.text and clock.clockSecond.text == second.text, "reopened preview did not read the current clock")
    assert(P.Set("minimap", "infoClockDatePosition", 1))
    assert(clock.label.text == label.text and clock.label.text == "09:35  22.11.2026"
        and not clock.clockSecond:IsShown() and not second:IsShown(), "beside mode retained a second date row")
    watcher:GetScript("OnHide")(watcher)
    flush()
    suite.Config, suite.Set, suite.SetMany = oldConfig, oldSet, oldSetMany
    suite.MinimapInfoPreviewSource, suite.SetMinimapPreviewListener, suite.MinimapZoomPreviewShown = nil, nil, nil
    fixture.M.RequestRefresh, Minimap, C_Timer = oldRequest, oldMap, oldTimer
end
print("suite_minimap_preview_layers_contract: live clock, zoom and immediate settings parity passed")

do
    local oldDate, oldShortDate = date, FormatShortDate
    date = function() return { day = 22, month = 11, year = 2026 } end
    FormatShortDate = function() return "22.11.2026" end
    config.infoClock, config.infoClockDate, config.infoClockDatePosition = true, true, 3
    ui.Paint()
    for _, item in ipairs(ui.textItems) do
        if item.spec[1] == "Clock" then
            assert(item.clockSecond:IsShown() and item.clockSecond.text == "22.11.2026", "cold preview lost the configured date")
        end
    end
    date, FormatShortDate = oldDate, oldShortDate
    config.infoClockDate = false
end

do
    local oldMap, oldTimer = C_Map, C_Timer
    local tile, flush = 123, nil
    C_Map = {
        GetBestMapForUnit = function() return 1 end,
        GetMapArtLayers = function() return { { layerWidth = 512, layerHeight = 512, tileWidth = 256, tileHeight = 256 } } end,
        GetMapArtLayerTextures = function() return { tile } end,
        GetPlayerMapPosition = function() return { GetXY = function() return .2, .2 end } end,
    }
    C_Timer = { After = function(_, callback) flush = callback end }
    watcher:GetScript("OnShow")(watcher)
    assert(ui.art.tiles[5].texture == 123 and ui.art.fallback:IsShown(), "partial terrain exposed the preview's backplate")
    tile = 456
    watcher:GetScript("OnEvent")(watcher, "ZONE_CHANGED_NEW_AREA")
    flush()
    assert(ui.art.tiles[5].texture == 456, "terrain remained on the old zone after a transition")
    watcher:GetScript("OnHide")(watcher)
    C_Map, C_Timer = oldMap, oldTimer
end
