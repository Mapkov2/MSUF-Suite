local root = assert(arg[1]):gsub("\\", "/")
local flavor, host = arg[2] or "Mainline", arg[3] or root .. "/../MidnightSimpleUnitFrames"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(host, flavor, { locale = "deDE" })
local env, M, world = mw.env, mw.M, mw.world
world.widgets.Methods.GetUnboundedStringWidth = function(self) return self:GetStringWidth() end
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
        follow = { "ChatPreview.lua", 'follow = handle.follow, ', '' },
        previewCombat = { "MSUF_Suite_Chat/Positions.lua", 'not self.preview and NS.InCombat()', 'NS.InCombat()' },
        parent = { "ChatPreview.lua", 'region:IsObjectType("FontString") and region:GetParent() or region', 'region' },
        static = { "ChatPreviewPositions.lua", '    if not spec.prefix then return 0, 0 end', '' },
        clipping = { "ChatPreview.lua", 'ui.canvas:SetClipsChildren(true)', 'ui.canvas:SetClipsChildren(true) ui.viewport:SetClipsChildren(true)' },
        resize = { "ChatPreview.lua", 'if not token or token.width ~= ui.width or token.scale ~= ui.stage:GetEffectiveScale() then', 'if not token then' },
        origin = { "ChatPreviewPositions.lua", 'if spec.icon and not P.Get(ID, spec.prefix .. "Moved") then', 'if false then' },
        reset = { "ChatPreviewPositions.lua", 'if spec.icon then values[prefix .. "Moved"] = false end', '' },
        profile = { "ChatPreview.lua", 'token.current() and token.config == P.S.Config(ID)', 'true' },
        legacy = { "ChatPreview.lua", 'if P.W.FocusCollapsibleSection then P.W.FocusCollapsibleSection(body, { flash = true }) end', '' },
        inputProfile = { "ChatPreviewPositions.lua",
            'if not current or not current() or config ~= P.S.Config(ID) or not body:IsVisible() then return end', '' },
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
local c = Suite.Suite.Config("chat")
c.enabled, c.lockWindowPosition, c.copyMessages = true, true, true
-- Real surface/font providers and Chat painters; do not enable native Chat.
File("MSUF_Suite_Modules/Runtime.lua", "MSUF_Suite_Modules", {})
File("MSUF_Suite_Modules/Surfaces.lua", "MSUF_Suite_Modules", {})
local runtime = { NS = Suite, Suite = Suite.Suite }
for _, file in ipairs({ "Shared", "Appearance", "MinimalChrome", "Unread", "Sidebar", "Positions", "CompleteMessages", "Window", "PreviewSnapshot", "Preview" }) do
    File("MSUF_Suite_Chat/" .. file .. ".lua", "MSUF_Suite_Chat", runtime)
end
if arg[4] == "positions" then return { runtime = runtime, env = env, Suite = Suite, world = world, c = c } end
Load("MSUF_Suite_Options", P)
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
Check(#parts.icons == 5 and #ui.handles == 12, "preview omitted interactive elements")
Check(ui.canvas.clipsChildren ~= false, "preview art has no clip owner")
Check(not ui.viewport.clipsChildren, "selection toolbar is clipped below its own viewport")
local bridge = M.SearchBridge
local function Exact(key, section)
    local meta = P.Meta("suite_chat", "chat", key, "setting", "suite_chat_" .. section)
    local called, opened, focused = bridge.OpenSearchTarget("suite_chat", "", nil, nil, {}, meta)
    mw:RunTimers()
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget("suite_chat", meta)
    Check(called and opened and focused and widget and widget:IsVisible(), "exact Chat target failed: " .. key)
    return widget
end
for key, spec in pairs(R.keys) do
    local input = Exact(key, spec.section)
    Check(input:IsObjectType("EditBox"), "coordinate is still a slider: " .. key)
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
M.SearchBridge = realBridge
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
local function FocusEdit(input, text)
    input:GetScript("OnEditFocusGained")(input)
    input:SetText(text)
end
local function Enter(input)
    input:GetScript("OnEnterPressed")(input)
    mw:RunTimers()
end
local input = Exact("copyButtonX", "tools")
FocusEdit(input, "123")
Check(Suite.Database.Create("chat-preview-input", true), "input profile fixture could not be created")
Check(Suite.Database.Activate("chat-preview-input"), "input profile fixture could not be activated")
mw:RunTimers()
local preserved = P.Get("chat", "copyButtonX")
Enter(input)
Check(P.Get("chat", "copyButtonX") == preserved, "pending coordinate text wrote into another profile")
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
    local handle = ui.targets[prefix]
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
Check(tx == -5 + 31 and ty == -15, "input runtime painter omitted offsets")
Check(parts.textClip.clipsChildren, "native message clipping missing")
combat = true
P.S.ChatPaintMenuPreview(parts, P.S.Config("chat"))
tx, ty = Point(parts.lines)
Check(tx == 17 and ty == 12, "combat repaint lost the saved sample text position")
tx, ty = Point(parts.tabGroup)
Check(tx == -23 and ty == 22, "combat repaint lost the saved sample tab position")
tx, ty = Point(parts.input)
Check(tx == -5 + 31 and ty == -15, "combat repaint lost the saved sample input position")
combat = false

print("Chat interactive preview " .. flavor .. ": " .. checks .. " checks passed")

if arg[4] == "native" then return { ui = ui, P = P, env = env, runtime = runtime, Suite = Suite, R = R } end
