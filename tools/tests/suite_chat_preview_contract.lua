local root = assert(arg[1]):gsub("\\", "/")
local flavor, host = arg[2] or "Mainline", arg[3] or root .. "/../MidnightSimpleUnitFrames"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { locale = "deDE", beforeCore = function(world)
    local widgets = world.widgets.Methods
    -- The host window draws caption glyphs with native Line methods.
    widgets.SetThickness = widgets.SetThickness or function(self, thickness) self.fixtureThickness = thickness end
    widgets.SetStartPoint = widgets.SetStartPoint or function(self, ...) self.fixtureStartPoint = { ... } end
    widgets.SetEndPoint = widgets.SetEndPoint or function(self, ...) self.fixtureEndPoint = { ... } end
end })
local env, M, world = mw.env, mw.M, mw.world
world.widgets.Methods.GetUnboundedStringWidth = function(self) return self:GetStringWidth() end
world.widgets.Methods.GetWrappedWidth = function(self) return self:GetStringWidth() end
world.widgets.Methods.SetPropagateKeyboardInput = function() end
local checks = 0
local function Check(value, text) checks = checks + 1 assert(value, text) end
world.widgets.Methods.IsVisible = function(self)
    local parent = self:GetParent()
    return self:IsShown() and (not parent or parent:IsVisible())
end
local create, combat, cursorX, cursorY = env.CreateFrame, false, 100, 100
env.CreateFrame = function(kind, name, parent, ...)
    Check(not parent or not parent:IsObjectType("FontString") and not parent:IsObjectType("Texture"), "native CreateFrame parent is not a Frame")
    return create(kind, name, parent, ...)
end
env.InCombatLockdown, env.UnitAffectingCombat = function() return combat end, function() return false end
env.GetCurrentKeyBoardFocus = function() return nil end
env.IsControlKeyDown, env.IsShiftKeyDown = function() return false end, function() return false end
env.GetCursorPosition = function() return cursorX, cursorY end
local tabDialogs, tabSlot, tabPrompt = 0, true
env.FCF_CanOpenNewWindow = function() return tabSlot end
env.FCF_IsChatWindowIndexReserved = function(index) return index <= 3 end
env.FCF_IsChatWindowIndexActive = function(index)
    local frame = env["ChatFrame" .. index]
    return frame and (frame:IsShown() or frame.isDocked)
end
env.IsBuiltinChatWindow = function(frame) return frame == env.ChatFrame1 end
env.Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
env.C_AddOns = {
    GetAddOnMetadata = function() end,
    IsAddOnLoaded = function(name) local on = name:find("^MSUF") ~= nil return on, on end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end, LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
env.BNGetNumFriends = function() return 0, 3 end
env.C_FriendList = { GetNumOnlineFriends = function() return 2 end }
for _, name in ipairs({ "QuickJoinToastButton", "ChatFrameChannelButton", "TextToSpeechButton", "ChatFrameMenuButton" }) do
    env[name] = env.CreateFrame("Button", name, env.UIParent)
end
local function File(path, addon, ns)
    local mutation = arg[4]
    local patches = {
        messagePriority = { "ChatPreview.lua", "ui.addHandle(ui, line, spec, 2)", "ui.addHandle(ui, line, spec, -1)" },
        messageHover = { "ChatPreview.lua", "local highlighted = hovered or selected", "local highlighted = selected" },
        messageLayer = { "ChatPreviewLayers.lua", "for _, handle in ipairs(ui.messageHandles) do Mask(ui, handle) end", "" },
        nativeDrag = { "ChatPreview.lua", "manualDrag = true, ", "" },
        demoTopic = { "ChatWorkspace.lua", 'sections = "tools text chatComfort_module sounds highlight"',
            'sections = "tools chatComfort_module sounds highlight"' },
        clickThreshold = { "ChatPreview.lua", "pixels = true, threshold = 4", "threshold = 2" },
        follow = { "ChatPreview.lua", 'follow = handle.follow, ', '' },
        layerMask = { "ChatPreviewLayers.lua", 'if layers.input == false then Mask(ui, parts.input) end', '' },
        previewCombat = { "MSUF_Suite_Chat/Positions.lua", 'not self.preview and NS.InCombat()', 'NS.InCombat()' },
        parent = { "ChatPreview.lua", 'region:IsObjectType("FontString") and region:GetParent() or region', 'region' },
        static = { "ChatPreviewPositions.lua", '    if not spec.prefix then return 0, 0 end', '' },
        clipping = { "ChatPreview.lua", 'ui.canvas:SetClipsChildren(true)', 'ui.canvas:SetClipsChildren(true) ui.viewport:SetClipsChildren(true)' },
        resize = { "ChatPreview.lua", 'if not token or token.width ~= ui.width or token.scale ~= Scale(ui, handle) then', 'if not token then' },
        origin = { "ChatPreviewPositions.lua", 'if spec.icon and not P.Get(ID, spec.prefix .. "Moved") then', 'if false then' },
        reset = { "ChatPreviewPositions.lua", 'if spec.icon then values[prefix .. "Moved"] = false end', '' },
        profile = { "ChatPreview.lua", 'token.current() and token.config == P.S.Config(ID)', 'true' },
        legacy = { "ChatPreview.lua", 'if P.W.FocusCollapsibleSection and P.W.FocusCollapsibleSection(body, { persist = true, flash = true }) then return true end', '' },
        sectionJump = { "ChatPreview.lua", 'if P.ChatPreviewLinks.Open(ui, spec) then return true end', '' },
        toolLink = { "ChatPreviewLinks.lua", '"headerToolbar", "animateInput", "copyMessages"',
            '"headerToolbar", "inputHeight", "copyMessages"' },
        clockLink = { "ChatPreviewLinks.lua", 'handle:SetShown(region:IsShown())', '' },
        legacyPersistence = { "ChatPreview.lua", 'persist = true, flash = true', 'flash = true' },
        navigationPlacement = { "ChatPreview.lua", 'handle.canMove and handle:IsVisible()',
            'handle.canMove and handle:IsVisible() and R.Allowed(handle.spec)' },
        navigationEnable = { "ChatPreview.lua", 'self.openButton:SetEnabled(enabled)',
            'self.openButton:SetEnabled(enabled and handle and R.Allowed(handle.spec))' },
        navigationCombat = { "ChatPreview.lua", 'ui.inCombat or P.Combat() or not ui.header:IsVisible()', 'not ui.header:IsVisible()' },
        accordion = { "ChatPreviewPositions.lua", 'if R.keys[rule.key] then positions', 'if false then positions' },
        axisProfile = { "ChatPreview.lua", 'if Valid() then return handler(...) end', 'if true then return handler(...) end' },
    }
    local patch = patches[mutation]
    if mutation == "original" and path == "MSUF_Suite_Options/Pages/Chat.lua" or patch and path:sub(-#patch[1]) == patch[1] then
        local sourcePath = mutation == "original" and assert(arg[5]) .. "/" .. path or root .. "/" .. path
        local sourceFile = assert(io.open(sourcePath, "rb"))
        local source = sourceFile:read("*a") sourceFile:close()
        if patch then
            local first, last = source:find(patch[2], 1, true)
            assert(first, "mutation site missing")
            source = source:sub(1, first - 1) .. patch[3] .. source:sub(last + 1)
        end
        local chunk = assert(loadstring(source, "@" .. sourcePath))
        setfenv(chunk, env)(addon, ns)
        return
    end
    local ok, message = world:LoadFile(root .. "/" .. path, addon, ns)
    assert(ok, tostring(message))
end
local function Load(addon, ns)
    local file = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local source = file:read("*a") file:close()
    for line in source:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then File(addon .. "/" .. line:gsub("\\", "/"), addon, ns) end
    end
end
Load("MSUF_Suite", {})
local Suite, P = env.MSUFSuite, {}
assert(Suite.Database.Initialize(nil))
Suite.Suite.AskText = function(_, data) tabDialogs, tabPrompt = tabDialogs + 1, data.callback end
Suite.Suite.CanOpenNativeWindow = function() return not combat end
local c = Suite.Suite.Config("chat")
c.enabled, c.lockWindowPosition, c.copyMessages = true, true, true
-- Real surface/font providers and Chat painters; do not enable native Chat.
File("MSUF_Suite_Modules/Runtime.lua", "MSUF_Suite_Modules", {})
File("MSUF_Suite_Modules/Surfaces.lua", "MSUF_Suite_Modules", {})
local runtime = { NS = Suite, Suite = Suite.Suite }
for _, file in ipairs({ "Shared", "HeaderClock", "InputAnimation", "Appearance", "MinimalChrome", "Unread", "Sidebar", "Positions", "Floating", "ToolbarGeometry", "Toolbar", "CompleteMessages", "Window", "PreviewSnapshot", "Preview" }) do
    File("MSUF_Suite_Chat/" .. file .. ".lua", "MSUF_Suite_Chat", runtime)
end
if arg[4] == "positions" then return { runtime = runtime, env = env, Suite = Suite, world = world, c = c } end
Load("MSUF_Suite_Options", P)
-- Cold provider rows must agree with the preview-only coordinate controls,
-- while searching for a whole section still opens that section's settings.
do
    local sections = {
        [P.Tr("Tabs and accent")] = "suite_chat_tabs",
        [P.Tr("Input line")] = "suite_chat_input",
        [P.Tr("Message text")] = "suite_chat_text",
    }
    local positions, found = {}, {}
    Check(not M.cache.suite_chat, "cold Chat search test started after page construction")
    for _, row in ipairs(P.SearchRows()) do
        if row.pageKey == "suite_chat" then
            if row.settingKey and row.settingKey:match("^msufsuite%.chat%..+[XY]$") then
                Check(row.sectionId == "suite_chat_preview", "cold Chat coordinate missed preview: " .. row.settingKey)
                positions[row.settingKey] = true
            elseif row.kind == "section" and sections[row.label] then
                Check(row.sectionId == sections[row.label], "Chat section search was redirected to preview: " .. row.label)
                found[row.label] = true
            end
        end
    end
    local count = 0
    for _ in pairs(positions) do count = count + 1 end
    Check(count == 20, "cold Chat provider omitted coordinate targets")
    for label in pairs(sections) do Check(found[label], "cold Chat provider omitted section: " .. label) end
    Check(not M.cache.suite_chat, "cold Chat provider built the page")
end
Check(P.ChatPreview ~= nil, "Chat interactive preview is missing")
local ui, build = nil, P.ChatPreview.Build
P.ChatPreview.Build = function(...)
    ui = build(...)
    return ui
end
Check(M.SelectPage("suite_chat"), "Chat page cannot open")
mw:RunTimers()
local ctx, E, R = M.cache.suite_chat, P.ChatPreview, P.ChatPreviewPositions
assert(ui, "Chat page did not build its interactive preview")
local parts = ui.parts
Check(ui.kit.host == ui.host and ui.handles == ui.kit.list, "preview bypassed the shared kit")
Check(parts.visual and parts.previewOwner and not next(runtime.Chat.M.visuals), "preview owns live chat visual state")
Check(ui.messageHandles and #ui.messageHandles == #parts.messageLines, "each demo message needs its own hit target")
Check(#parts.icons == 5 and #ui.handles == 14, "preview omitted interactive elements")
Check(ui.canvas.clipsChildren ~= false, "preview art has no clip owner")
Check(not ui.viewport.clipsChildren, "selection toolbar is clipped below its own viewport")
local bridge = M.SearchBridge
-- A preview link opens its own section, including a previously closed one.
for _, handle in ipairs(ui.handles) do
    local section = "suite_chat_" .. handle.spec.section
    local body = ui.ctx.chatSections[section]
    local entry = P.HM.GetSectionEntry(body)
    entry.SetOpenImmediate(false)
    handle:GetScript("OnMouseDown")(handle, "LeftButton")
    handle:GetScript("OnMouseUp")(handle, "LeftButton")
    handle:GetScript("OnClick")(handle, "LeftButton")
    mw:RunTimers()
    local meta = P.Meta("suite_chat", "chat", handle.spec.control, "setting", section)
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
    Check(entry.open and widget and widget:IsVisible(), "preview link missed its settings: " .. handle.spec.control)
end
-- Being unable to move an element must not prevent opening its settings.
Check(P.Set("chat", "lockWindowPosition", false), "navigation fixture could not unlock window")
E.Select(ui, ui.targets.window)
Check(ui.selection:IsShown() and ui.selection.openButton:IsEnabled(), "Open settings is disabled for the unlocked chat window")
Check(not ui.selection.resetButton:IsEnabled() and not ui.selection.axisX.minusButton:IsEnabled(), "unlocked window enables position edits")
local windowSection = P.HM.GetSectionEntry(ui.ctx.chatSections.suite_chat_window)
windowSection.SetOpenImmediate(false)
ui.selection.openButton:GetScript("OnClick")(ui.selection.openButton, "LeftButton")
mw:RunTimers()
Check(windowSection.open and not P.Get("chat", "lockWindowPosition"), "settings link changed window anchoring or stayed closed")
Check(P.Set("chat", "lockWindowPosition", true), "navigation fixture could not restore anchoring")
-- The combat-edge flag applies to links as well as drag/position writes.
local tabSection = P.HM.GetSectionEntry(ui.ctx.chatSections.suite_chat_tabs)
tabSection.SetOpenImmediate(false)
ui.viewport:GetScript("OnEvent")(ui.viewport, "PLAYER_REGEN_DISABLED")
Check(ui.viewport._msuf2SelectionDeps.OpenSettings(ui.viewport, ui.targets.tab) == false and not tabSection.open,
    "combat edge opened preview settings")
ui.viewport:GetScript("OnEvent")(ui.viewport, "PLAYER_REGEN_ENABLED")
local function Exact(key, section)
    local meta = P.Meta("suite_chat", "chat", key, "setting", "suite_chat_" .. section)
    local called, opened, focused = bridge.OpenSearchTarget("suite_chat", "", nil, nil, {}, meta)
    mw:RunTimers()
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
    Check(called and opened and focused and widget and widget:IsVisible(), "exact Chat target failed: " .. key)
    return widget
end
do
    local section = "suite_chat_chatComfort_module"
    local oldSection = "suite_qualityOfLife_dailyComfort_daily_comfort"
    local keys = { chatWheel = true, chatClassColors = true, noChatFade = true, whisperWindows = true }
    local seen = {}
    for _, row in ipairs(P.SearchRows()) do
        local key = row.settingKey and row.settingKey:match("^msufsuite%.chatComfort%.(.+)$")
        if keys[key] then
            Check(row.pageKey == "suite_chat" and row.sectionId == section and not seen[key], "duplicate or misplaced Chat behavior result")
            seen[key] = true
        end
        local legacy = row.settingKey and row.settingKey:match("^msufsuite%.dailyComfort%.(.+)$")
        Check(not keys[legacy], "moved Chat behavior remained searchable from Daily UI comforts")
    end
    for key in pairs(keys) do
        Check(seen[key], "Chat behavior setting absent from search: " .. key)
        local old = P.Meta("suite_qualityOfLife", "dailyComfort", key, "setting", oldSection)
        if key == "whisperWindows" then old.settingKey = nil end
        local called, opened, focused = bridge.OpenSearchTarget("suite_qualityOfLife", "", nil, nil, {}, old)
        mw:RunTimers()
        local meta = P.Meta("suite_chat", "chatComfort", key, "setting", section)
        local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
        Check(called and opened and focused and widget and widget:IsVisible()
            and ui.ctx.chatWorkspace.selected == "messages", "legacy bookmark missed Chat behavior: " .. key)
    end
    local daily = P.S.Config("dailyComfort")
    local comfort = P.S.Config("chatComfort")
    local originalMusic = daily.muteMusic
    daily.muteMusic = true
    comfort.enabled, comfort.noChatFade, comfort.whisperWindows = true, true, 3
    local card = ui.ctx.chatWorkspace.sections[section]
    Check(card._msufSuiteSectionReset() and comfort.enabled and not comfort.noChatFade
        and comfort.whisperWindows == 1 and daily.muteMusic, "Chat behavior reset escaped its four settings")
    daily.muteMusic, comfort.enabled = originalMusic, false
end
for key, spec in pairs(R.keys) do
    local input = Exact(key, spec.section)
    Check(ui.viewport._selectedHandle == ui.targets[spec.prefix], "exact search did not select preview target: " .. key)
    Check(input:GetParent() == ui.header, "coordinate still lives in an accordion: " .. key)
    P.HM.GetSearchTargetPrepare(input)()
    Check(ui.viewport._selectedHandle == ui.targets[spec.prefix], "search preparation did not select preview target: " .. key)
end
for _, handle in ipairs(ui.handles) do
    if not handle.canMove then
        handle:GetScript("OnClick")(handle, "LeftButton")
        mw:RunTimers()
        Check(ui.viewport._selectedHandle == handle, "static sample cannot be selected")
        Check(not ui.selection:IsShown(), "static element exposes invalid X/Y properties")
        -- Older selection bars query the offset callback for every selection.
        local x, y = ui.viewport._msuf2SelectionDeps.ReadOffsets(ui.viewport, handle)
        Check(x == 0 and y == 0, "static selection has invalid offset callbacks")
    end
end
local sx, sy = R.Read(ui, {})
Check(sx == 0 and sy == 0, "static offset callback is invalid")
local window = ui.targets.window
E.Select(ui, window)
local deps = ui.viewport._msuf2SelectionDeps
Check(deps ~= nil and ui.selection:IsShown(), "shared exact position bar is missing")
Check(deps.WriteOffsets(ui.viewport, window, 86, 42), "exact window write refused")
Check(c.windowX == 86 and c.windowY == 42, "exact values lost their saved identity")
local before, after = P.CaptureHistoryState(), nil
Check(deps.WriteOffsets(ui.viewport, window, -30, 0), "negative/zero positions refused")
after = P.CaptureHistoryState()
Check(P.RestoreHistoryState(before), "history restore refused")
c = P.S.Config("chat")
Check(c.windowX == 86 and c.windowY == 42, "undo lost the window position")
Check(P.RestoreHistoryState(after), "history redo refused")
c = P.S.Config("chat")
Check(c.windowX == -30 and c.windowY == 0, "redo lost negative or zero values")
mw:RunTimers()
E.Select(ui, window)
ui.stage.GetEffectiveScale = function() return .5 end
window:GetScript("OnMouseDown")(window, "LeftButton")
cursorX, cursorY = 110, 95
window:GetScript("OnMouseUp")(window, "LeftButton")
Check(c.windowX == -10 and c.windowY == -10, "drag ignored effective preview scale")
local previous = c.windowX
window:GetScript("OnMouseDown")(window, "LeftButton")
c.windowX = 300
cursorX = 120
window:GetScript("OnMouseUp")(window, "LeftButton")
Check(c.windowX == 300, "stale drag overwrote intervening settings")
local icon = ui.targets.sidebarButton1
parts.icons[1].GetCenter = function() return 210, 340 end
parts.sidebar.GetCenter = function() return 200, 300 end
c.sidebarPanel, c.sidebarButton1Moved = true, false
E.Select(ui, icon)
local x, y = R.Read(ui, icon.spec)
Check(x == 10 and y == 40, "unmoved icon did not read its automatic position")
icon:GetScript("OnMouseDown")(icon, "LeftButton")
cursorX = cursorX + 10
icon:GetScript("OnMouseUp")(icon, "LeftButton")
Check(c.sidebarButton1Moved and c.sidebarButton1X == 30 and c.sidebarButton1Y == 40, "first icon drag jumped from zero")
Check(deps.ResetOffsets(ui.viewport, icon), "selected icon reset failed")
Check(not c.sidebarButton1Moved and c.sidebarButton1X == 0 and c.sidebarButton1Y == 0, "reset did not restore automatic sidebar layout")
E.Select(ui, window)
window:GetScript("OnMouseDown")(window, "LeftButton")
ui.viewport:GetScript("OnEvent")(ui.viewport, "PLAYER_REGEN_DISABLED")
cursorX = cursorX + 20
window:GetScript("OnMouseUp")(window, "LeftButton")
Check(not ui.kit.drag and c.windowX == 300, "combat edge committed a held drag")
Check(not deps.WriteOffsets(ui.viewport, window, 12, 12), "combat exact field wrote")
ui.viewport:GetScript("OnEvent")(ui.viewport, "PLAYER_REGEN_ENABLED")
E.Select(ui, window)
window:GetScript("OnMouseDown")(window, "LeftButton")
local originalProfile = Suite.DB
Suite.DB = {}
cursorX = cursorX + 20
window:GetScript("OnMouseUp")(window, "LeftButton")
Suite.DB = originalProfile
Check(c.windowX == 300, "profile switch committed a stale drag")
E.Select(ui, window)
window:GetScript("OnMouseDown")(window, "LeftButton")
Suite.Registry.NotifyListeners("profile", "preview-profile-return")
cursorX = cursorX + 20
window:GetScript("OnMouseUp")(window, "LeftButton")
Check(P.Get("chat", "windowX") == 300, "profile epoch revived a stale drag")
Check(M.SelectPage("home"), "could not leave Chat")
mw:RunTimers()
-- The fixture models ancestor visibility, but native inherited OnHide
-- dispatch is delivered explicitly, as in the meter editor contract.
ui.viewport:GetScript("OnHide")(ui.viewport)
Check(not ui.kit.drag and not env.MSUF_SuiteChatPreview_ActiveNudgeBox, "hidden preview held keyboard or drag")
Check(not deps.WriteOffsets(ui.viewport, window, 12, 12), "hidden preview wrote coordinates")
Check(M.SelectPage("suite_chat"), "could not reopen Chat")
mw:RunTimers()
Check(c.windowX == 300, "reopening preview mutated saved position")
ui.viewport:GetScript("OnShow")(ui.viewport)
E.Select(ui, window)
window:GetScript("OnMouseDown")(window, "LeftButton")
ui.header:GetScript("OnSizeChanged")(ui.header, 300)
cursorX = cursorX + 10
window:GetScript("OnMouseUp")(window, "LeftButton")
Check(c.windowX == 300, "resize during drag committed a stale position")
ui.header:GetScript("OnSizeChanged")(ui.header, 720)
for _, width in ipairs({ 240, 300, 540, 720 }) do
    ui.header:GetScript("OnSizeChanged")(ui.header, width)
    E.Select(ui, window)
    Check(ui.selection:GetWidth() == ui.width, "position bar lost responsive width")
    local _, _, _, _, by = ui.selection.axisY:GetPoint(1)
    local _, _, _, _, ry = ui.selection.resetButton:GetPoint(1)
    Check(ui.width >= 650 or -ry >= -by + ui.selection.axisY:GetHeight(), "narrow position inputs overlap actions")
end
ui.header:GetScript("OnSizeChanged")(ui.header, 720)
local realBridge = M.SearchBridge
M.SearchBridge = nil
local shell = ui.ctx.chatSections.suite_chat_text
local entry = P.HM.GetSectionEntry(shell)
entry:SetOpenImmediate(false)
ui.targets.messageText:GetScript("OnClick")(ui.targets.messageText, "LeftButton")
Check(entry.open, "legacy preview click did not open its accordion")
Check(M.SelectPage("suite_chat"), "legacy link could not refresh its page")
mw:RunTimers()
Check(entry.open, "legacy preview link closed on page refresh")
M.SearchBridge = {}
entry:SetOpenImmediate(false)
ui.targets.messageText:GetScript("OnClick")(ui.targets.messageText, "LeftButton")
Check(entry.open, "legacy bridge without exact method did not open its accordion")
M.SearchBridge = realBridge
local focusSection = P.W.FocusCollapsibleSection
P.W.FocusCollapsibleSection = nil
ui.targets.messageText:GetScript("OnClick")(ui.targets.messageText, "LeftButton")
mw:RunTimers()
Check(ui.ctx.chatWorkspace.selected == "messages", "demo message did not open the Messages topic")
P.W.FocusCollapsibleSection = focusSection
-- Exact navigation must settle on the requested row, including a row far
-- below its accordion header. A second section scroll must not overwrite it.
do
    local meta = P.Meta("suite_chat", "chat", "tabHeight", "setting", "suite_chat_tabs")
    local record, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
    local anchor = record.anchor or widget
    local wrapper, scroll, child = ui.ctx.wrapper, M.scrollFrame, M.scrollChild
    local wrapperTop, anchorTop, childHeight = wrapper.GetTop, anchor.GetTop, child:GetHeight()
    wrapper.GetTop, anchor.GetTop = function() return 1000 end, function() return 300 end
    child:SetHeight(5000)
    ui.targets.tab:GetScript("OnClick")(ui.targets.tab, "LeftButton")
    mw:RunTimers()
    Check(math.abs(scroll:GetVerticalScroll() - 656) < .01, "Chat preview exact settings scroll was overwritten")
    local highlight = wrapper._msuf2SearchHighlight
    local _, _, _, _, y = highlight:GetPoint(1)
    Check(y == -692, "Chat preview highlighted its section instead of its exact control")
    wrapper.GetTop, anchor.GetTop = wrapperTop, anchorTop
    child:SetHeight(childHeight)
end
Check(P.SetMany("chat", { windowX = 97, windowY = -26, panelColor = "123456" }), "section setup failed")
Check(ui.ctx.chatSections.suite_chat_window._msufSuiteSectionReset(), "window section reset failed")
c = P.S.Config("chat")
Check(c.windowX == 12 and c.windowY == 12, "section reset omitted relocated coordinates")
Check(c.copyMessages, "window reset changed another section")
Check(P.SetMany("chat", { sidebarButton1Moved = true, sidebarButton1X = 50, sidebarButton1Y = 90 }), "sidebar reset setup failed")
Check(ui.ctx.chatSections.suite_chat_sidebar._msufSuiteSectionReset(), "sidebar section reset failed")
Check(not c.sidebarButton1Moved and c.sidebarButton1X == 0 and c.sidebarButton1Y == 0, "sidebar section reset omitted position state")
-- All native art uses the runtime painter, including texture/gradient/sidebar/input settings.
Check(P.SetMany("chat", { sidebarSide = 2, sidebarWidth = 36, inputTop = true, inputHeight = 38,
    panelGradient = true, minimalChrome = true, panelAlpha = 55, tabIndividualPanels = true }), "style write failed")
mw:RunTimers()
local point = parts.sidebar:GetPoint(1)
Check(point == "TOPLEFT" and parts.sidebar:GetWidth() == 36, "sidebar side/width absent from sample")
Check(parts.input:GetHeight() == 38 and parts.input:GetPoint(1) == "BOTTOMLEFT", "input placement/height absent from sample")
Check(parts.visual.gradientLeft:IsShown() and parts.visual.gradientLeft:GetWidth() == 50, "runtime gradient missing")
Check(P.Set("chat", "sidebarPanel", false), "sidebar off failed")
mw:RunTimers()
Check(not parts.sidebar:IsShown() and not R.Write(icon.spec, 1, 1), "hidden sidebar remains editable")
Check(not next(runtime.Chat.M.visuals) and not next(runtime.Chat.M.tabs), "sample leaked into native state")
Exact("sidebarButton1X", "sidebar")
Check(not P.Get("chat", "sidebarPanel"), "position search enabled the sidebar")
Check(ui.viewport._selectedHandle == icon, "disabled sidebar position is not selected in the preview")
for key, spec in pairs(R.keys) do
    local meta = P.Meta("suite_chat", "chat", key, "setting", "suite_chat_" .. spec.section)
    meta.settingKey = nil
    local called, opened, focused = bridge.OpenSearchTarget("suite_chat", "", nil, nil, {}, meta)
    mw:RunTimers()
    Check(called and opened and focused, "saved control-only position target failed: " .. key)
end
local function FocusEdit(input, text)
    input:GetScript("OnEditFocusGained")(input)
    input:SetText(text)
end
local function Enter(input)
    input:GetScript("OnEnterPressed")(input)
    mw:RunTimers()
end
Exact("copyButtonX", "tools")
local input = ui.selection.axisX.edit
FocusEdit(input, "123")
Check(Suite.Database.Create("chat-preview-input", true), "input profile fixture could not be created")
Check(Suite.Database.Activate("chat-preview-input"), "input profile fixture could not be activated")
mw:RunTimers()
local preserved = P.Get("chat", "copyButtonX")
Enter(input)
Check(P.Get("chat", "copyButtonX") == preserved, "pending toolbar text wrote into another profile")
FocusEdit(input, "-17")
Enter(input)
Check(P.Get("chat", "copyButtonX") == -17, "fresh numeric input failed after profile change")
FocusEdit(input, "invalid")
Enter(input)
Check(P.Get("chat", "copyButtonX") == -17, "invalid numeric text changed settings")
Check(P.Set("chat", "lockWindowPosition", true), "axis profile fixture could not anchor window")
E.Select(ui, window)
local axis = ui.selection.axisX.edit
FocusEdit(axis, "123")
Check(Suite.Database.Create("chat-preview-axis", true), "axis profile fixture could not be created")
Check(Suite.Database.Activate("chat-preview-axis"), "axis profile fixture could not be activated")
mw:RunTimers()
preserved = P.Get("chat", "windowX")
Enter(axis)
Check(P.Get("chat", "windowX") == preserved, "pending toolbar text wrote into another profile")
E.Select(ui, window)
FocusEdit(axis, "125")
E.Select(ui, ui.targets.copyButton)
preserved = P.Get("chat", "copyButtonX")
Enter(axis)
Check(P.Get("chat", "copyButtonX") == preserved, "pending toolbar text wrote to another element")
E.Select(ui, window)
FocusEdit(axis, "28")
Enter(axis)
Check(P.Get("chat", "windowX") == 28, "fresh toolbar input failed after profile change")
for _, handle in ipairs(ui.handles) do
    Check(handle.canMove, "a visible Chat element remains click-only")
end
local function Point(region)
    local _, _, _, x, y = region:GetPoint(1)
    return x, y
end
for index, prefix in ipairs({ "messageText", "tab", "input" }) do
    env.GetTime = function() return 1000 + index end
    local handle = prefix == "messageText" and ui.messageHandles[2] or ui.targets[prefix]
    Check(handle and handle.canMove, "missing movable " .. prefix)
    E.Select(ui, handle)
    Check(deps.WriteOffsets(ui.viewport, handle, 19, -8), "exact write refused: " .. prefix)
    mw:RunTimers()
    Check(P.Get("chat", prefix .. "X") == 19 and P.Get("chat", prefix .. "Y") == -8, "position did not persist")
    local exactState = P.CaptureHistoryState()
    local region = handle.followRegion
    local bx, by = Point(region)
    handle:GetScript("OnMouseDown")(handle, "LeftButton")
    cursorX, cursorY = cursorX + 8, cursorY + 6
    local update = handle:GetScript("OnUpdate")
    Check(update ~= nil, "drag has no visible follow")
    update(handle)
    local dx, dy = Point(region)
    Check(dx == bx + 16 and dy == by + 12, "drag does not move visible art: " .. prefix)
    Check(P.Get("chat", prefix .. "X") == 19, "drag wrote before release")
    handle:GetScript("OnMouseUp")(handle, "LeftButton")
    mw:RunTimers()
    Check(P.Get("chat", prefix .. "X") == 35 and P.Get("chat", prefix .. "Y") == 4, "drag runtime coordinates differ")
    Check(ui.kit:Arrow(1, -1), "arrow nudge refused: " .. prefix)
    Check(P.Get("chat", prefix .. "X") == 36 and P.Get("chat", prefix .. "Y") == 3, "arrow offset did not persist: " .. prefix .. "=" .. P.Get("chat", prefix .. "X") .. "," .. P.Get("chat", prefix .. "Y"))
    local movedState = P.CaptureHistoryState()
    Check(P.RestoreHistoryState(exactState), "new element undo failed")
    Check(P.Get("chat", prefix .. "X") == 19 and P.Get("chat", prefix .. "Y") == -8, "undo lost new positions")
    Check(P.RestoreHistoryState(movedState), "new element redo failed")
    Check(P.Get("chat", prefix .. "X") == 36 and P.Get("chat", prefix .. "Y") == 3, "redo lost new positions")
    mw:RunTimers()
    Check(deps.ResetOffsets(ui.viewport, handle), "new element reset refused")
    mw:RunTimers()
    Check(P.Get("chat", prefix .. "X") == 0 and P.Get("chat", prefix .. "Y") == 0, "new reset did not restore origin")
    Check(P.SetMany("chat", { [prefix .. "X"] = 47, [prefix .. "Y"] = -11 }), "reset fixture failed")
    Check(ui.ctx.chatSections["suite_chat_" .. handle.spec.section]._msufSuiteSectionReset(), "new section reset failed")
    Check(P.Get("chat", prefix .. "X") == 0 and P.Get("chat", prefix .. "Y") == 0, "section reset missed new positions")
end
Check(P.SetMany("chat", { messageTextX = 17, messageTextY = 12, tabX = -23, tabY = 19, inputX = 31, inputY = -13 }), "parity setup failed")
mw:RunTimers()
local tx, ty = Point(parts.lines)
Check(tx == 17 and ty == 12, "message text runtime painter omitted offsets")
tx, ty = Point(parts.tabGroup)
Check(tx == -23 and ty == 22, "tab runtime painter omitted offsets")
tx, ty = Point(parts.input)
Check(tx == 31 - P.Get("chat", "padding") and ty == -15 - P.Get("chat", "padding"), "input runtime painter omitted offsets")
Check(parts.textClip.clipsChildren, "native message clipping missing")
combat = true
P.S.ChatPaintMenuPreview(parts, P.S.Config("chat"))
tx, ty = Point(parts.lines)
Check(tx == 17 and ty == 12, "combat repaint lost the saved sample text position")
tx, ty = Point(parts.tabGroup)
Check(tx == -23 and ty == 22, "combat repaint lost the saved sample tab position")
tx, ty = Point(parts.input)
Check(tx == 31 - P.Get("chat", "padding") and ty == -15 - P.Get("chat", "padding"), "combat repaint lost the saved sample input position")
combat = false

for _, body in pairs(ui.ctx.chatSections) do P.EnsureSectionContent(body) end
mw:RunTimers()
for _, widget in ipairs(world.widgets.frames) do
    local meta = M.RuntimeControlCatalog.GetForWidget(widget)
    local key = meta and (meta.settingKey or ""):match("^msufsuite%.chat%.(.+)$")
    if key and R.keys[key] then
        Check(widget:GetParent() == ui.header, "coordinate still lives in an accordion: " .. key)
    end
end

-- Exercise the actual page/runtime preview with the appended compact look.
-- Model the native Alpha/Scale primitive instead of accepting unknown methods.
parts.input.IsProtected = function() return false end
world.widgets.Methods.CreateAnimationGroup = function(owner)
    local group = { animations = {}, plays = 0 }
    function group:CreateAnimation(kind)
        local animation = { kind = kind }
        function animation:SetFromAlpha(value) self.from = value end
        function animation:SetToAlpha(value) self.to = value end
        function animation:SetScaleFrom(...) self.from = { ... } end
        function animation:SetScaleTo(...) self.to = { ... } end
        function animation:SetOrigin(...) self.origin = { ... } end
        function animation:SetSmoothing(value) self.smoothing = value end
        function animation:SetOrder(value) self.order = value end
        function animation:SetOffset(x, y) self.offsetX, self.offsetY = x, y end
        function animation:SetDuration(value) self.duration = value end
        function animation:SetStartDelay(value) self.startDelay = value end
        self.animations[#self.animations + 1] = animation
        return animation
    end
    function group:SetScript(key, fn) self[key] = fn end
    function group:Stop() self.playing = false end
    function group:Play() self.playing = true; self.plays = self.plays + 1 end
    owner.chatTestAnimation = group
    return group
end
Check(P.Set("chat", "look", 8), "compact preset failed")
mw:RunTimers()
Check(parts.toolbar and parts.toolbar:IsShown() and #parts.toolbar.buttons == 5, "compact tools missing from preview")
Check(not parts.toolbar.buttons[1]:GetScript("OnClick"), "preview tools can create live chat tabs")
local function CheckLink(region, key, section, topic)
    local handle = ui.extraLinks and ui.extraLinks[region]
    Check(handle and not handle.canMove and handle.spec.control == key and handle.spec.section == section,
        "preview extra link has wrong settings identity: " .. key)
    local saved = {}
    for name in pairs(P.catalog.chat.rules) do saved[name] = P.Get("chat", name) end
    ui.ctx.chatWorkspace.select(topic == "extras" and "basics" or "extras")
    local body = ui.ctx.chatSections["suite_chat_" .. section]
    local entry = P.HM.GetSectionEntry(body)
    entry.SetOpenImmediate(false)
    handle:GetScript("OnClick")(handle, "LeftButton")
    mw:RunTimers()
    local meta = P.Meta("suite_chat", "chat", key, "setting", "suite_chat_" .. section)
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
    Check(entry.open and widget and widget:IsVisible() and ui.ctx.chatWorkspace.selected == topic,
        "preview extra link opened wrong topic/control: " .. key)
    Check(not ui.selection:IsShown() and not R.Allowed(handle.spec), "navigation link exposes position edits")
    for name, value in pairs(saved) do Check(P.Get("chat", name) == value, "preview link changed setting: " .. name) end
    Check(not next(runtime.Chat.M.visuals), "preview settings link activated native Chat")
end
for index, target in ipairs({
    { "headerToolbar", "tabs", "appearance" }, { "animateInput", "input", "input" },
    { "copyMessages", "tools", "messages" }, { "toolbarLocked", "tabs", "appearance" },
    { "look", "look", "basics" },
}) do CheckLink(parts.toolbar.buttons[index], target[1], target[2], target[3]) end
Check(not ui.extraLinks[parts.resizeGrip]:IsShown(), "locked resize grip intercepts preview clicks")
Check(not parts.copy:IsShown(), "duplicate copy control in compact preview")
local animation = parts.input.chatTestAnimation
Check(animation and animation.plays > 0 and #animation.animations == 3, "compact input animation preview missing")
local plays = animation.plays
Check(P.Set("chat", "inputAnimationDuration", 0.31), "animation duration refused")
mw:RunTimers()
Check(animation.plays == plays + 1 and animation.animations[3].duration == 0.31, "duration change did not replay native sample")
local replay
for _, widget in ipairs(world.widgets.frames) do
    if widget:GetText() == P.Tr("Preview input animation") and widget:GetScript("OnClick") then replay = widget end
end
Check(replay ~= nil, "input animation replay action is not available")
plays = animation.plays
replay:GetScript("OnClick")(replay)
Check(animation.plays == plays + 1, "input animation action did not replay the preview")
Check(P.Set("chat", "animateInput", false), "animation toggle refused")
mw:RunTimers()
Check(not animation.playing, "turning animation off did not stop the sample")
Check(P.Set("chat", "toolbarLocked", false), "unlock refused")
mw:RunTimers()
Check(parts.resizeGrip:IsShown() and not parts.toolbar.buttons[4].strokes[4]:IsShown(), "unlocked grip/state missing from preview")
CheckLink(parts.resizeGrip, "lockWindowSize", "window", "basics")
Check(P.Set("chat", "headerClock", true), "clock fixture refused")
mw:RunTimers()
CheckLink(parts.visual.headerClock, "headerClock", "tabs", "appearance")
local clockHandle = ui.extraLinks[parts.visual.headerClock]
local handleCount = #ui.handles
ui.runtimeRefresh()
Check(#ui.handles == handleCount, "preview repaint recreated navigation handles")
Check(P.Set("chat", "headerClock", false), "clock off fixture refused")
mw:RunTimers()
Check(not clockHandle:IsShown(), "hidden preview clock intercepts clicks")
Check(P.Set("chat", "look", 7), "immersive preset failed")
mw:RunTimers()
Check(not parts.toolbar:IsShown() and not parts.resizeGrip:IsShown(), "old preset retained compact controls")
for _, button in ipairs(parts.toolbar.buttons) do
    Check(not ui.extraLinks[button]:IsVisible(), "hidden preview toolbar intercepts clicks")
end
Check(not P.Get("chat", "hideNativeButtons"), "compact look left native controls hidden")

-- Topic navigation keeps one preview and reveals exact targets in hidden groups.
local topics = assert(ui.ctx.chatWorkspace, "Chat has no topic workspace")
Check(#topics.tabs.items == 5, "Chat topics are not directly selectable")
local function CheckTopicHighlight(expected)
    for _, item in ipairs(topics.tabs.items) do
        Check(item.button._msuf2Active == (item.id == expected), "Chat topic has the wrong active highlight: " .. item.id)
        Check(item.button._msuf2SegmentChoice == true, "Chat topic cannot show its active cue under menu skins")
    end
end
local previewIdentity = ui.ctx.chatPreviewUI
CheckTopicHighlight(topics.selected)
for _, item in ipairs(topics.tabs.items) do
    item.button:GetScript("OnClick")(item.button)
    Check(topics.selected == item.id, "topic button did not select its group")
    CheckTopicHighlight(item.id)
    for id, group in pairs(topics.groups) do Check(group.frame:IsShown() == (id == item.id), "multiple chat topics remain visible") end
    Check(ui.ctx.chatPreviewUI == previewIdentity and ui.header:IsVisible(), "topic navigation replaced or hid the preview")
end
for _, key in ipairs({ "enabled", "party" }) do
    topics.select("basics")
    local before = P.Get("keywordAlerts", "enabled")
    local meta = P.Meta("suite_chat", "keywordAlerts", key, "setting", "suite_chat_keywordAlerts_module")
    local called, opened, focused = bridge.OpenSearchTarget("suite_chat", "", nil, nil, {}, meta)
    mw:RunTimers()
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
    local prepared = {}
    for field, value in pairs(meta) do prepared[field] = value end
    prepared.prepareKind, prepared.prepareValue = "suiteWorkspace", key
    topics.select("basics")
    local record, preparedWidget, reason = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", prepared)
    Check(record and preparedWidget and preparedWidget:IsVisible() and topics.selected == "extras", "prepared keyword search failed: " .. tostring(reason))
    Check(called and opened and focused and topics.selected == "extras" and widget and widget:IsVisible(),
        "keyword notice search remained hidden: " .. key .. "/" .. tostring(called) .. "/" .. tostring(opened) .. "/" .. tostring(focused) .. "/" .. tostring(topics.selected) .. "/" .. tostring(widget and widget:IsVisible()) .. "/section=" .. tostring(topics.sections.suite_chat_keywordAlerts_module ~= nil))
    CheckTopicHighlight("extras")
    Check(P.Get("keywordAlerts", "enabled") == before, "search enabled keyword notices")
end
local originalWidth, originalWidthGetter = ui.header:GetWidth(), ui.header.GetWidth
ui.header.GetWidth = function() return 232 end
ui.header:SetWidth(232)
ui.header:GetScript("OnSizeChanged")(ui.header, 232, ui.header:GetHeight())
local nav = topics.tabs
-- Native size changes deliver this script after LayoutSelector changes the row.
nav:GetScript("OnSizeChanged")(nav, nav:GetWidth(), nav:GetHeight())
Check(nav:GetHeight() > 26 and (ui.navigationHeight or 0) > 0, "narrow Chat topics do not wrap")
local _, _, _, _, viewportY = ui.viewport:GetPoint(1)
Check(viewportY == -42 - ui.navigationHeight, "wrapped topics cover the preview")
for _, item in ipairs(nav.items) do
    local _, _, _, x, y = item.button:GetPoint(1)
    Check(x >= 0 and x + item.button:GetWidth() <= nav:GetWidth() and y <= 0, "wrapped topic escaped its row")
end
Check(ui.chips:GetHeight() > 50, "narrow Chat layer rail does not wrap")
for _, button in ipairs(ui.layerButtons) do
    local _, _, _, x, y = button:GetPoint(1)
    Check(x >= 10 and x + button:GetWidth() <= ui.chips:GetWidth() - 10 and y <= -25,
        "wrapped layer chip escaped the rail")
end
ui.header.GetWidth = originalWidthGetter
ui.header:SetWidth(originalWidth)
ui.header:GetScript("OnSizeChanged")(ui.header, originalWidth, ui.header:GetHeight())
nav:GetScript("OnSizeChanged")(nav, nav:GetWidth(), nav:GetHeight())
topics.select("basics")

if arg[4] == "native" then return { ui = ui, P = P, env = env, runtime = runtime, Suite = Suite, R = R } end

-- A hardware click can move one or two screen pixels before release.
-- The scaled-down sample must still open the exact input row.
do
    local topic = ui.ctx.chatWorkspace
    local body = ui.ctx.chatSections.suite_chat_input
    local entry = P.HM.GetSectionEntry(body)
    local input = ui.targets.input
    local key = P.Meta("suite_chat", "chat", "inputWidth", "setting", "suite_chat_input")
    local record, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", key)
    local anchor, wrapper = record.anchor or widget, ui.ctx.wrapper
    local wrapperTop, anchorTop = wrapper.GetTop, anchor.GetTop
    local child, childHeight = M.scrollChild, M.scrollChild:GetHeight()
    local scale = ui.stage.GetEffectiveScale
    local x, y = P.Get("chat", "inputX"), P.Get("chat", "inputY")
    ui.stage.GetEffectiveScale = function() return .325 end
    wrapper.GetTop, anchor.GetTop = function() return 1000 end, function() return 300 end
    child:SetHeight(5000)
    topic.select("basics")
    entry:SetOpenImmediate(false)
    input:GetScript("OnMouseDown")(input, "LeftButton")
    cursorX, cursorY = cursorX + 1, cursorY + 1
    input:GetScript("OnUpdate")(input)
    input:GetScript("OnMouseUp")(input, "LeftButton")
    input:GetScript("OnClick")(input, "LeftButton")
    mw:RunTimers()
    Check(topic.selected == "input" and entry.open and widget:IsVisible(), "small-scale click did not open the input accordion")
    CheckTopicHighlight("input")
    Check(P.Get("chat", "inputX") == x and P.Get("chat", "inputY") == y, "small-scale click changed the input position")
    Check(math.abs(M.scrollFrame:GetVerticalScroll() - 656) < .01, "small-scale click did not scroll to input width")
    local _, _, _, _, yOffset = wrapper._msuf2SearchHighlight:GetPoint(1)
    Check(yOffset == -692, "small-scale click did not highlight the input width row")

    topic.select("basics")
    entry:SetOpenImmediate(false)
    input:GetScript("OnMouseDown")(input, "LeftButton")
    cursorX = cursorX + 8
    input:GetScript("OnUpdate")(input)
    input:GetScript("OnMouseUp")(input, "LeftButton")
    input:GetScript("OnClick")(input, "LeftButton")
    mw:RunTimers()
    Check(P.Get("chat", "inputX") == math.floor(x + 8 / .325 + .5), "real drag lost its scaled coordinate")
    Check(topic.selected == "basics" and not entry.open, "a real drag followed the settings link")
    Check(P.SetMany("chat", { inputX = x, inputY = y }), "input click fixture could not restore the position")
    ui.stage.GetEffectiveScale = scale
    wrapper.GetTop, anchor.GetTop = wrapperTop, anchorTop
    child:SetHeight(childHeight)
    cursorX, cursorY = 100, 100
    mw:RunTimers()
end
-- Followed handles use only their own mouse gestures. A normal click must
-- keep the rendered region and its hit target anchored until WoW sends OnClick.
do
    topics.select("basics")
    local input = ui.targets.input
    local rewrites = 0
    local field, artwork = input.ClearAllPoints, parts.input.ClearAllPoints
    input.ClearAllPoints = function(frame) rewrites = rewrites + 1 return field(frame) end
    parts.input.ClearAllPoints = function(frame) rewrites = rewrites + 1 return artwork(frame) end
    input:GetScript("OnMouseDown")(input, "LeftButton")
    input:GetScript("OnMouseUp")(input, "LeftButton")
    input.ClearAllPoints, parts.input.ClearAllPoints = field, artwork
    Check(rewrites == 0, "input click rebuilt its hit target before OnClick")
    Check(not input:GetScript("OnDragStart") and not input:GetScript("OnDragStop"),
        "input click still competes with native drag")
    input:GetScript("OnClick")(input, "LeftButton")
    mw:RunTimers()
    CheckTopicHighlight("input")
    topics.select("basics")
    local messages = ui.targets.messageText
    local entry = P.HM.GetSectionEntry(ui.ctx.chatSections.suite_chat_text)
    entry:SetOpenImmediate(false)
    messages:GetScript("OnMouseDown")(messages, "LeftButton")
    messages:GetScript("OnMouseUp")(messages, "LeftButton")
    messages:GetScript("OnClick")(messages, "LeftButton")
    mw:RunTimers()
    Check(topics.selected == "messages" and entry.open, "demo message click missed the Message text accordion")
    CheckTopicHighlight("messages")
end

local chips = {}
for _, button in ipairs(ui.layerButtons) do chips[button.key] = button end
local function Toggle(key, mouse)
    local chip = assert(chips[key], "missing Chat layer " .. key)
    return chip:GetScript("OnClick")(chip, mouse or "LeftButton")
end
Check(#ui.layerButtons == 7 and ui.chips:IsVisible(), "Chat is missing its preview layer rail")
do
    local first, second, third = unpack(ui.messageHandles)
    local window = ui.targets.window
    local lines, sample = parts.messageLines, parts.sample
    local oldSampleRect = sample.GetRect
    local oldRects, oldWidths, oldHeights = {}, {}, {}
    local positions = { {100, 110}, {110, 130}, {105, 150} }
    local widths = {80, 60, 90}
    local oldComplete, oldHighlight = P.Get("chat", "completeMessages"), P.Get("chat", "highlightKeywords")
    sample.GetRect = function() return 100, 100, 300, 100 end
    for index, line in ipairs(lines) do
        oldRects[index], oldWidths[index], oldHeights[index] = line.GetRect, line.GetWrappedWidth, line.GetStringHeight
        line.GetRect = function() return positions[index][1], positions[index][2], 300, 16 end
        line.GetWrappedWidth = function() return widths[index] end
        line.GetStringHeight = function() return 14 end
    end
    Check(P.SetMany("chat", { completeMessages = false, highlightKeywords = false }), "message geometry fixture refused")
    mw:RunTimers()
    ui.runtimeRefresh()

    -- Resolve overlap from the actual hit sizes and anchors rather than
    -- invoking a preselected target's click handler.
    local function Pick(x, y)
        local left, bottom, width, height = sample:GetRect()
        local hit = x >= left and x < left + width and y >= bottom and y <= bottom + height and window or nil
        for _, row in ipairs(ui.messageHandles) do
            if row:IsVisible() and row:IsMouseEnabled() then
                local _, relative, _, dx, dy = row:GetPoint(1)
                local left, bottom, _, height = relative:GetRect()
                local top = bottom + height + dy
                left = left + dx
                if x >= left and x < left + row:GetWidth() and y <= top and y > top - row:GetHeight()
                    and (not hit or row:GetFrameLevel() > hit:GetFrameLevel()) then hit = row end
            end
        end
        return hit
    end
    local function Outlined(row)
        local edges = row._suitePreviewSelectionEdges
        return edges and edges[1]:IsShown()
    end
    Check(first:GetParent() == window:GetParent() and second:GetParent() == window:GetParent(),
        "message hits and the window do not share their stacking parent")
    Check(first:IsMouseEnabled() and second:IsMouseEnabled() and not third:IsMouseEnabled(),
        "hidden demo message is still clickable")
    Check(Pick(110, 118) == first and Pick(120, 138) == second and Pick(200, 138) == window,
        "visible demo messages do not take priority over the window")
    Check(first:GetWidth() == 80 and second:GetWidth() == 60 and second:GetHeight() == 14,
        "message hit is sized to its full row instead of rendered text")
    E.Select(ui, window)
    local hit = Pick(120, 138)
    hit:GetScript("OnEnter")(hit)
    Check(Outlined(hit) and not Outlined(first) and not Outlined(window), "hover did not highlight only its demo message")
    hit:GetScript("OnLeave")(hit)
    Check(not Outlined(hit) and Outlined(window), "leaving the message did not restore the selection cue")
    topics.select("basics")
    hit:GetScript("OnMouseDown")(hit, "LeftButton")
    hit:GetScript("OnMouseUp")(hit, "LeftButton")
    hit:GetScript("OnClick")(hit, "LeftButton")
    mw:RunTimers()
    Check(ui.viewport._selectedHandle == second and topics.selected == "messages",
        "physical hit did not select the message and open its topic")

    positions[1] = {90, 92}
    ui.runtimeRefresh()
    Check(first:GetWidth() == 70 and first:GetHeight() == 8 and Pick(100, 103) == first and Pick(102, 99) == nil,
        "message hit was not clipped at the window edge")
    lines[1]:SetTextColor(1, 1, 1, 0)
    P.ChatPreviewPaint.AnchorMessage(first)
    Check(not first:IsMouseEnabled() and Pick(100, 103) == window, "invisible message intercepts the window")
    E.Select(ui, "messageText")
    Check(ui.viewport._selectedHandle == second, "position selection did not pick the visible message")
    Check(Toggle("text") and not parts.textClip:IsShown() and Pick(120, 138) == window,
        "hiding the Messages layer left a message hit active")
    Exact("messageTextX", "text")
    Check(parts.textClip:IsVisible() and Pick(120, 138) == second, "position search did not restore the Messages layer")
    positions[1], positions[2] = {100, 220}, {110, 240}
    ui.runtimeRefresh()
    E.Select(ui, "messageText")
    Check(ui.viewport._selectedHandle == first and deps.IsPlaced(first) and not first:IsMouseEnabled(),
        "exact position editing is unavailable when all messages are clipped")
    sample.GetRect = oldSampleRect
    for index, line in ipairs(lines) do
        line.GetRect, line.GetWrappedWidth, line.GetStringHeight = oldRects[index], oldWidths[index], oldHeights[index]
    end
    Check(P.SetMany("chat", { completeMessages = oldComplete, highlightKeywords = oldHighlight }), "message geometry cleanup failed")
    mw:RunTimers()
    ui.runtimeRefresh()
end
local before = P.Get("chat", "inputWidth")
Check(P.Set("chat", "inputWidth", 344), "input width setter refused")
mw:RunTimers()
Check(parts.input:GetWidth() == 344, "input width did not reach the preview")
E.Select(ui, "input")
Check(Toggle("input"), "input layer toggle refused")
Check(not parts.input:IsShown() and not ui.targets.input:IsVisible(), "hidden input layer intercepts preview clicks")
Check(not ui.viewport._selectedHandle, "hidden layer retained selection")
Check(Toggle("input", "RightButton"), "input layer did not route to its width setting")
mw:RunTimers()
Check(topics.selected == "input" and P.Get("chat", "inputWidth") == 344, "layer navigation changed the input width")
Exact("inputX", "input")
Check(parts.input:IsShown() and ui.viewport._selectedHandle == ui.targets.input, "position search did not reveal the hidden input layer")
local toolbar = P.Get("chat", "headerToolbar")
Check(P.Set("chat", "headerToolbar", true), "toolbar layer fixture refused")
mw:RunTimers()
Check(Toggle("tools") and not parts.toolbar:IsShown(), "buttons layer did not hide the toolbar")
Check(Toggle("tools", "RightButton"), "buttons layer did not route to the toolbar setting")
mw:RunTimers()
Check(topics.selected == "appearance", "buttons layer missed the toolbar's topic")
Check(P.Set("chat", "headerToolbar", false), "copy layer fixture refused")
mw:RunTimers()
Check(Toggle("tools", "RightButton"), "buttons layer did not route to the copy setting")
mw:RunTimers()
Check(topics.selected == "messages", "buttons layer missed the copy button's topic")
Check(Toggle("tools") and P.Set("chat", "headerToolbar", toolbar), "buttons layer cleanup refused")
Check(Toggle("window") and not ui.targets.window:IsShown() and parts.input:IsVisible(), "window layer hid other layers")
Check(Toggle("window") and ui.targets.window:IsShown(), "window layer did not restore its handle")
Check(P.Set("chat", "headerClock", true), "layer clock fixture refused")
mw:RunTimers()
local clock = parts.visual.headerClock
local clockLink = ui.extraLinks[clock]
Check(Toggle("clock") and not clock:IsShown() and not clockLink:IsShown(), "clock layer left an invisible hit target")
Check(P.Set("chat", "headerClock", false), "clock off fixture refused")
mw:RunTimers()
Check(Toggle("clock") and not clock:IsShown() and not clockLink:IsShown(), "layer restored art disabled in settings")
Check(P.Set("chat", "inputWidth", before), "input width cleanup refused")
mw:RunTimers()
Check(parts.input:GetWidth() == parts.sample:GetWidth() + 2 * P.Get("chat", "padding"), "auto width does not match the padded preview")

do
    local rail = ui.windowRail
    Check(rail.create._msuf2Success and rail.create:IsEnabled(), "preview lacks a green native tab action")
    rail.create:GetScript("OnClick")(rail.create, "LeftButton")
    Check(tabDialogs == 1, "preview create did not open the naming dialog")
    Check(rail.delete._msuf2Danger and not rail.delete:IsEnabled(), "preview delete is active with reserved tabs only")
    tabSlot = false
    ui.runtimeRefresh()
    rail.create:GetScript("OnClick")(rail.create, "LeftButton")
    Check(not rail.create:IsEnabled() and tabDialogs == 1, "preview create bypassed native tab capacity")
    tabSlot = true
    local openedName, filters
    env.ChatConfigFrame = env.CreateFrame("Frame", nil, env.UIParent)
    env.ChatConfigFrame:Hide()
    env.ChatConfigFrame.ChatTabManager = { UpdateSelection = function(_, index) filters = index end }
    env.ShowUIPanel = function(frame) frame:Show() end
    env.FCF_OpenNewWindow = function(name) openedName = name; return {}, 5 end
    env.FCF_CopyChatSettings, env.FCF_DockUpdate = function() end, function() end
    combat = true
    tabPrompt("Guild")
    Check(not openedName and not filters and P.M.frame:IsShown(), "combat acceptance changed a tab or hid Suite")
    combat = false
    rail.create:GetScript("OnClick")(rail.create, "LeftButton")
    tabPrompt("Guild")
    Check(openedName == "Guild" and filters == 5 and env.ChatConfigFrame:IsShown(), "preview opened the wrong native filters")
    Check(not P.M.frame:IsShown(), "Suite obscures the native filters")
    env.ChatConfigFrame:Hide()
    P.M.frame:Show()

    local guild = env.CreateFrame("Frame", nil, env.UIParent)
    local loot = env.CreateFrame("Frame", nil, env.UIParent)
    guild:SetSize(440, 180)
    loot:SetSize(270, 210)
    env.ChatFrame3, env.ChatFrame4 = guild, loot
    env.GetChatWindowInfo = function(index) return index == 3 and "Guild" or "Loot" end
    local notify = ui.viewport:GetScript("OnEvent")
    notify(ui.viewport, "UPDATE_FLOATING_CHAT_WINDOWS")
    Check(rail.detached:IsShown() and #rail.choices == 2, "preview did not list both detached windows")
    Check(rail.card.index == 3 and rail.choices[2].text == "Loot  #4", "preview lost native chat names or slot identity")
    rail.selected = rail.choices[2]
    guild.isDocked = true
    notify(ui.viewport, "UPDATE_FLOATING_CHAT_WINDOWS")
    Check(#rail.choices == 1 and rail.card.index == 4 and rail.selected.index == 4, "redock changed the selected detached window")
    local trade = env.CreateFrame("Frame", nil, env.UIParent)
    trade.isDocked = true
    trade:Hide()
    env.ChatFrame5 = trade
    local names = { [3] = "Guild", [4] = "Loot", [5] = "Trade" }
    env.GetChatWindowInfo = function(index) return names[index] end
    local confirm, question
    local popped = {}
    local context, confirmDialog, openPicker = P.ContextMenu, P.Confirm, P.OpenDeletePicker
    local popup
    P.OpenDeletePicker = function(...)
        popup = openPicker(...) or popup
    end
    P.ContextMenu = function() error("Delete Chat Tabs opened a Blizzard context menu") end
    P.Confirm = function(_, text, callback) question, confirm = text, callback end
    env.FCF_GetCurrentChatFrameID = function() return filters end
    env.FCF_PopInWindow = function(frame)
        popped[#popped + 1] = frame
        frame.isDocked = false
        frame:Hide()
    end
    local function OpenDelete() rail.delete:GetScript("OnClick")(rail.delete, "LeftButton") end
    Check(rail.delete:IsEnabled() and not popup, "delete popup was missing or was built eagerly")
    OpenDelete()
    assert(popup)
    local first, second = popup.rows[1].toggle, popup.rows[2].toggle
    Check(popup:IsVisible() and popup.anchor == rail.delete and #popup.snapshot == 2, "wrong menu anchor or eligible tabs")
    Check(first._msuf2QuietCheckBox and second._msuf2QuietCheckBox and popup.apply._msuf2Danger,
        "delete popup did not use Menu2 checkbox and action styles")
    Check(P.HM.GetControlLabel(first):GetText() == "Loot  #4" and P.HM.GetControlLabel(second):GetText() == "Trade  #5",
        "delete picker missed a docked or floating user tab")
    popup.apply:GetScript("OnClick")(popup.apply)
    Check(not popup.apply:IsEnabled() and not confirm, "empty selection asked for confirmation")
    first:GetScript("OnClick")(first)
    Check(first:GetChecked() and popup.apply:IsEnabled(), "checking a row did not enable deletion")
    first:GetScript("OnClick")(first)
    Check(not first:GetChecked() and not popup.apply:IsEnabled(), "unchecking the last row left deletion enabled")
    first:GetScript("OnClick")(first)
    OpenDelete()
    Check(not popup:IsShown(), "pressing the anchor again did not close the popup")
    OpenDelete()
    Check(popup.rows[1].toggle == first and not first:GetChecked(),
        "reopening rebuilt the popup or kept its previous selection")
    local propagated
    popup.SetPropagateKeyboardInput = function(_, value) propagated = value end
    local keyDown = popup:GetScript("OnKeyDown")
    keyDown(popup, "A")
    Check(popup:IsShown() and propagated, "a regular key did not pass through the popup")
    keyDown(popup, "ESCAPE")
    Check(not popup:IsShown() and propagated == false, "Escape did not dismiss only the popup")
    OpenDelete()
    Check(propagated, "reopening retained Escape's keyboard capture")
    popup:GetScript("OnEvent")(popup, "PLAYER_REGEN_DISABLED")
    Check(not popup:IsShown(), "combat did not dismiss the popup")
    OpenDelete()
    first:GetScript("OnClick")(first)
    second:GetScript("OnClick")(second)
    Check(first:GetChecked() and second:GetChecked() and popup.apply:IsEnabled(), "multi-selection lost checked rows")
    popup.apply:GetScript("OnClick")(popup.apply)
    Check(not popup:IsShown() and #popped == 0 and question:find("Loot  #4", 1, true) and question:find("Trade  #5", 1, true),
        "delete did not confirm both selected tabs")
    confirm()
    Check(popped[1] == loot and popped[2] == trade and not rail.detached:IsShown(),
        "delete did not use Blizzard's close action for both selected windows")
    P.ContextMenu, P.Confirm, P.OpenDeletePicker = context, confirmDialog, openPicker
end

print("Chat interactive preview " .. flavor .. ": " .. checks .. " checks passed")
