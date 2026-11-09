-- Chat audit: the keyword notices follow the instance group's chat, the other
-- chat addons count as conflicts, a setting is greyed while the switch it
-- depends on is off (the menu only, never the stored value), and the locked
-- main window has an Edit Mode mover.
local root = assert(arg[1])
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local P, S, Suite = F.optionsNS, F.S, F.Suite
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b or type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.000001, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local CONFLICTS = { "EllesmereUIChat", "ElvUI", "Glass", "Glassy", "Prat-3.0", "Chattynator", "Chatter", "DaylightUI_Chat" }

------------------------------------------------------------------ conflicts
-- Any of these chat addons switches the module off; the module's own late
-- load handler (Controller.lua) is checked below against the same list.
do
    local original = Suite.Client.IsAddOnLoaded
    assert(S.Availability("chat"), "harness: the chat module is unavailable without a conflict")
    for _, name in ipairs(CONFLICTS) do
        Suite.Client.IsAddOnLoaded = function(addon) return addon == name or original(addon) end
        local ok, why = S.Availability("chat")
        eq(ok, false, name .. " does not switch the chat module off")
        eq(why, "Managed by " .. name, name .. " status")
    end
    Suite.Client.IsAddOnLoaded = original
end

------------------------------------------------------------------ dependent settings
-- A rule with a switch is greyed while the switch is off and says which one to
-- turn on; flipping the switch never rewrites the stored value of the rule.
local rules = P.catalog.chat.rules
local function Usable(key) return P.RuleEnabled("chat", rules[key]) end
local function Reason(key)
    local ok, why = P.RuleEnabled("chat", rules[key], nil, true)
    eq(ok, false, key .. " is not greyed")
    return why
end
local function Links(switch, dependents)
    local stored = {}
    for _, key in ipairs(dependents) do stored[key] = P.Get("chat", key) end
    assert(P.Set("chat", switch, false))
    assert(Usable(switch), switch .. " greys itself")
    for _, key in ipairs(dependents) do
        assert(not Usable(key), key .. " stays editable while " .. switch .. " is off")
        eq(Reason(key), ('Turn on "%s" to change this.'):format(P.Tr(rules[switch].label)), key .. " reason")
        eq(P.Get("chat", key), stored[key], key .. " lost its value while greyed")
    end
    assert(P.Set("chat", switch, true))
    for _, key in ipairs(dependents) do assert(Usable(key), key .. " stays greyed with " .. switch .. " on") end
end

Links("lockWindowSize", { "windowWidth", "windowHeight" })
Links("lockWindowPosition", { "windowX", "windowY" })
Links("saveHistory", { "historyLines" })
Links("allTimestamps", { "timestampFormat" })
Links("copyMessages", { "copyButtonX", "copyButtonY" })

-- The idle fade is a delay where 0 means off, not a switch.
do
    assert(P.Set("chat", "idleSeconds", 0))
    assert(Usable("idleSeconds"), "the fade delay greys itself")
    for _, key in ipairs({ "idleAlpha", "idleFadeDuration" }) do
        assert(not Usable(key), key .. " stays editable without a fade delay")
    end
    assert(P.Set("chat", "idleSeconds", 12))
    for _, key in ipairs({ "idleAlpha", "idleFadeDuration" }) do
        assert(Usable(key), key .. " stays greyed with a fade delay")
    end
end

-- Speech bubbles: the shared look and each source's MSUF look need the
-- styling; a source's own look needs its MSUF look, and each part of it the
-- own look. A part follows the whole chain, not only its own switch.
do
    local shared = { "bubbleFont", "bubbleFontSize", "bubbleTextColor", "bubbleBackground", "bubbleAlpha",
        "bubbleBorder", "bubblePadding", "bubbleMaxWidth" }
    local parts = { "bubbleFont", "bubbleSize", "bubbleText", "bubbleFill", "bubbleOpacity", "bubbleEdge",
        "bubblePad", "bubbleWidth" }
    local sources = P.Suite.ChatBubbleSources
    assert(#sources > 0, "harness: no bubble source")
    local styles = {}
    for _, source in ipairs(sources) do styles[#styles + 1] = "bubbleStyle" .. source.key end
    for _, key in ipairs(shared) do styles[#styles + 1] = key end
    Links("styleBubbles", styles)
    assert(Usable("hideInstanceBubbles"), "turning bubbles off inside instances needs no bubble styling")
    for _, source in ipairs(sources) do
        local own, style, ownParts = "bubbleOwn" .. source.key, "bubbleStyle" .. source.key, {}
        for _, part in ipairs(parts) do ownParts[#ownParts + 1] = part .. source.key end
        Links(style, { own })
        Links(own, ownParts)
        -- With the styling off the own look is moot even while its switches are on.
        assert(P.Set("chat", "styleBubbles", false))
        for _, key in ipairs(ownParts) do
            assert(not Usable(key), key .. " stays editable without bubble styling")
            eq(Reason(key), ('Turn on "%s" to change this.'):format(P.Tr(rules.styleBubbles.label)), key .. " chain")
        end
        assert(P.Set("chat", "styleBubbles", true))
    end
end

------------------------------------------------------------------ chat module and mover
-- Controller.lua on its own, over the real catalog and the real Edit Mode
-- element registration (MSUF_Suite_Modules/EditMode.lua).
local config, catalogNS = Support.CatalogDefaults(root, "chat")
local registered, applied, events, combat = {}, {}, {}, false
local ns = { DB = {}, IsCombatLocked = function() return combat end,
    InCombat = function() return combat end,
    Safety = { IsForbidden = function() return false end } }
local suite = { catalog = catalogNS.SuiteCatalog, states = { chat = { active = true } }, instances = {},
    Text = function(text) return text end, Config = function() return config end,
    Finite = function(value) return type(value) == "number" and value == value end,
    CanOpenNativeWindow = function() return not combat end,
    Apply = function(id) applied[#applied + 1] = id end,
    Dispatch = function(callback, ...) return callback(...) end }
function suite.SetMany(_, values) for key, value in pairs(values) do config[key] = value end return true end
function suite.Set(id, key, value) return suite.SetMany(id, { [key] = value }) end
function suite.CommitEditPosition(id, values) return not combat and suite.SetMany(id, values) end
local moverRefreshes = 0
MSUF_EditModeAPI = {
    RefreshOwner = function(owner)
        assert(owner == "MSUFSuite.chat")
        moverRefreshes = moverRefreshes + 1
    end,
    RegisterElement = function(owner, element) registered[owner .. "/" .. element.id] = element return true end,
    RegisterSessionListener = function() end, IsActive = function() return false end,
}
local nativeEnabled = true
local nativeRecord = { isEnabled = function() return nativeEnabled end }
MSUF_EM2 = { ExternalElements = { GetRecord = function(key)
    assert(key == "external:msuf.blizzard:chat", "chat suppressed an unrelated mover")
    return nativeRecord
end } }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("test", ns)
assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("test", { NS = ns, Suite = suite })

-- Window handling is the Window.lua file's business; the controller only
-- needs these to start.
local chatNS = { NS = ns, Suite = suite }
assert(loadfile(root .. "/MSUF_Suite_Chat/Shared.lua"))("MSUF_Suite_Chat", chatNS)
local chat = chatNS.Chat
chat.StopInputAnimations = function() end
chat.ApplyClockSettings, chat.RefreshClocks, chat.DisableClock = function() end, function() end, function() end
chat.DockGeometry, chat.UpdateWindowMoverBounds, chat.DockSelection = function() end, function() end, function() end
chat.MessagesRefresh, chat.BubblesRefresh = function() end, function() end
function suite.Install(id, module) eq(id, "chat"); eq(module, chat.M, "installed module") end
hooksecurefunc = function() end
Constants = { ChatFrameConstants = { MaxChatWindows = 0 } }
CHAT_FRAMES = {}
local cornerPatches = {
    nativeClamp = { "Positions", 'self.context:Property(frame, "IsClampedToScreen", "SetClampedToScreen", false)', '' },
    firstMove = { "Controller", 'moveValues = { lockWindowPosition = true }',
        'isEnabled = function() return self.config.lockWindowPosition == true end, moveValues = {}' },
    adoptAnchor = { "Controller", 'moveValues = { lockWindowPosition = true }', 'moveValues = {}' },
    undoAnchor = { "Controller", 'historyKeys = { "lockWindowPosition" }', 'historyKeys = {}' },
}
local function LoadChat(name)
    local path = root .. "/MSUF_Suite_Chat/" .. name .. ".lua"
    local patch = arg[2] and cornerPatches[arg[2]]
    if patch and patch[1] == name then
        local file = assert(io.open(path, "rb")); local source = file:read("*a"); file:close()
        local first, last = source:find(patch[2], 1, true)
        assert(first, "mutation site missing")
        assert(loadstring(source:sub(1, first-1) .. patch[3] .. source:sub(last+1), "@" .. path))("MSUF_Suite_Chat", chatNS)
    else
        assert(loadfile(path))("MSUF_Suite_Chat", chatNS)
    end
end
LoadChat("Positions")
LoadChat("Floating")
LoadChat("SpamFilter")
LoadChat("Controller")
local module = chat.M
module.config, module.active = config, true
module.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
    clampBefore = {}, pointsBefore = {},
    Property = function(self, frame, getter, setter, value)
        if self.clampBefore[frame] == nil then self.clampBefore[frame] = frame[getter](frame) end
        frame[setter](frame, value)
    end,
    RestoreProperty = function(self, frame, setter)
        if self.clampBefore[frame] ~= nil then
            frame[setter](frame, self.clampBefore[frame]); self.clampBefore[frame] = nil
        end
    end,
    Anchor = function(self, frame, ...)
        if not self.pointsBefore[frame] then self.pointsBefore[frame] = frame.points end
        frame:ClearAllPoints(); frame:SetPoint(...)
    end,
    RestorePoints = function(self, frame)
        if self.pointsBefore[frame] then frame.points = self.pointsBefore[frame]; self.pointsBefore[frame] = nil end
    end,
}
module:Enable()

-- Every conflict of the catalog that loads after the module takes it out of
-- service; unrelated addons do not.
for _, name in ipairs(catalogNS.SuiteCatalog.chat.conflicts) do
    applied = {}
    events.ADDON_LOADED(module, "ADDON_LOADED", name)
    eq(#applied, 1, name .. " loading late did not re-evaluate the chat module")
    eq(applied[1], "chat", name .. " re-evaluated another module")
end
assert(#catalogNS.SuiteCatalog.chat.conflicts == #CONFLICTS, "the conflict list changed: update the contract")
applied = {}
events.ADDON_LOADED(module, "ADDON_LOADED", "Details")
eq(#applied, 0, "an unrelated addon re-evaluated the chat module")

-- The mover: the main window's position belongs to the Suite while it is
-- anchored, as offsets of its bottom left corner from the screen's.
local frame = { points = {} }
function frame:GetScale() return self.scale or 1 end
function frame:GetEffectiveScale() return self:GetScale() * UIParent:GetEffectiveScale() end
function frame:GetLeft() return self.left or config.windowX end
function frame:GetBottom() return self.bottom or config.windowY end
function frame:IsClampedToScreen() return self.clamped ~= false end
function frame:SetClampedToScreen(value) self.clamped = value end
function frame:ClearAllPoints() self.points = {} end
function frame:SetPoint(...) self.points = { ... } end
ChatFrame1 = frame
module.visuals = { [frame] = {} }
UIParent = UIParent or {}
function UIParent:GetLeft() return 10 end
function UIParent:GetBottom() return 20 end
function UIParent:GetEffectiveScale() return 0.75 end
-- No geometry before the first position refresh: retain saved-coordinate fallback.
module.positionFrame = nil
module:RegisterMovers()
local element = registered["MSUFSuite.chat/window"]
assert(element, "the chat window has no Edit Mode mover")
eq(element.label, "Chat window", "mover label")
assert(element.isEnabled(), "the active chat has no mover before its first Suite anchor")
assert(not nativeRecord.isEnabled(), "the oversized native mover still competes before the first Suite anchor")
config.lockWindowPosition, config.windowX, config.windowY = true, 12, 12
module:RegisterMovers()
assert(not nativeRecord.isEnabled(), "native and Suite chat movers compete for the same frame")
assert(moverRefreshes == 1, "claim transition did not synchronize visible host movers")
module:RegisterMovers()
assert(moverRefreshes == 1, "unchanged chat claim refreshes all host movers")
assert(element.isEnabled(), "no mover for the anchored window")
local controls = {}
for _, control in ipairs(element.extraControls) do controls[control.id] = control end
local ruleX, ruleY = catalogNS.SuiteCatalog.chat.rules.windowX, catalogNS.SuiteCatalog.chat.rules.windowY
eq(controls.windowX.max, ruleX.max, "X field range")
eq(controls.windowY.min, ruleY.min, "Y field range")
local state = element.captureState()
assert(element.movePosition({ state = state, deltaX = 30, deltaY = -10, phase = "drag" }), "drag refused")
eq(frame.points[1], "BOTTOMLEFT", "anchor point")
eq(frame.points[2], UIParent, "anchor frame")
eq(frame.points[3], "BOTTOMLEFT", "anchor frame point")
eq(frame.points[4], 42, "dragged X")
eq(frame.points[5], 2, "dragged Y")
eq(config.windowX, 12, "a drag preview wrote the saved position")
assert(element.movePosition({ state = state, deltaX = 30, deltaY = -10, phase = "commit" }), "commit refused")
eq(config.windowX, 42, "committed X")
eq(config.windowY, 2, "committed Y")
assert(element.restoreState(state), "undo refused")
eq(config.windowX, 12, "undone X")
for _, scale in ipairs({ 0.5, 1, 1.5 }) do
    frame.scale, frame.left, frame.bottom = scale, 30 + 10 / scale, 210 + 20 / scale
    module.positionFrame = frame
    local liveState = element.captureState()
    eq(liveState.values.windowX, 12, "capture retains saved undo X")
    eq(liveState.values.windowY, 12, "capture retains saved undo Y")
    assert(element.movePosition({ state = liveState, deltaX = 30 * scale, deltaY = -10 * scale, phase = "drag" }))
    eq(frame.points[4], 60, "drag starts at visible X")
    eq(frame.points[5], 200, "drag starts at visible Y")
    eq(config.windowX, 12, "visible-origin preview does not save")
    assert(element.movePosition({ state = liveState, deltaX = 30 * scale, deltaY = -10 * scale, phase = "commit" }))
    eq(config.windowX, 60, "visible-origin committed X")
    eq(config.windowY, 200, "visible-origin committed Y")
    assert(element.restoreState(liveState))
    eq(config.windowX, 12, "visible-origin undo X")
    eq(config.windowY, 12, "visible-origin undo Y")
    eq(controls.windowX.get(), 30, "popup reads visible X")
    eq(controls.windowY.get(), 210, "popup reads visible Y")
    assert(controls.windowX.set(60))
    eq(config.windowX, 60, "numeric X applies requested value")
    eq(config.windowY, 210, "numeric X preserves visible Y")
    assert(element.restoreState(liveState))
    assert(controls.windowY.set(200))
    eq(config.windowX, 30, "numeric Y preserves visible X")
    eq(config.windowY, 200, "numeric Y applies requested value")
    assert(element.restoreState(liveState))
end
-- Reproduce the native Selection's 32px dead margin, not just SetPoint arguments.
do
    local left, bottom, setPoint = frame.GetLeft, frame.GetBottom, frame.SetPoint
    frame.scale, config.windowX, config.windowY, config.lockWindowPosition = 1, 12, 12, false
    frame.points, frame.clamped = { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 32 }, true
    module.context.clampBefore, module.context.pointsBefore = {}, {}
    module.visuals[frame], module.positionFrame = {}, frame
    function frame:GetLeft() return UIParent:GetLeft() + (self.points[4] or 0) end
    function frame:GetBottom() return UIParent:GetBottom() + (self.points[5] or 0) end
    function frame:SetPoint(point, relative, edge, x, y)
        if self.clamped then x, y = math.max(32, x), math.max(32, y) end
        self.points = { point, relative, edge, x, y }
    end
    local beforeMove = element.captureState()
    eq(beforeMove.origin.windowX, 32, "native corner origin X")
    eq(beforeMove.origin.windowY, 32, "native corner origin Y")
    assert(beforeMove.values.lockWindowPosition == false, "capture lost native ownership")
    assert(element.movePosition({ state = beforeMove, deltaX = -32, deltaY = -32, phase = "drag" }))
    eq(frame.points[4], 0, "native clamp keeps an invisible left margin")
    eq(frame.points[5], 0, "native clamp keeps an invisible bottom margin")
    assert(config.lockWindowPosition == false, "preview adopted ownership before release")
    assert(element.movePosition({ state = beforeMove, deltaX = -32, deltaY = -32, phase = "commit" }))
    assert(config.lockWindowPosition, "first completed move did not adopt the anchor")
    eq(config.windowX, 0, "corner committed X"); eq(config.windowY, 0, "corner committed Y")
    local afterMove = element.captureState()
    assert(element.restoreState(beforeMove))
    chat.ApplyWindowPosition(module, module.visuals[frame], frame, true)
    assert(not config.lockWindowPosition and frame.clamped, "undo retained Suite clamp/anchor ownership")
    eq(frame.points[4], 32, "undo lost original native X")
    eq(frame.points[5], 32, "undo lost original native Y")
    EditModeManagerFrame = { HookScript = function() end, IsShown = function() return false end }
    assert(element.restoreState(afterMove))
    chat.ApplyWindowPosition(module, module.visuals[frame], frame, true)
    assert(config.lockWindowPosition and not frame.clamped, "redo lost Suite corner ownership")
    eq(frame.points[4], 0, "redo corner X"); eq(frame.points[5], 0, "redo corner Y")
    assert(element.restoreState(beforeMove))
    chat.ApplyWindowPosition(module, module.visuals[frame], frame, true)
    frame.GetLeft, frame.GetBottom, frame.SetPoint = left, bottom, setPoint
end
frame.scale, frame.left, frame.bottom, module.positionFrame = nil, nil, nil, nil
eq(controls.windowX.positionAxis, "x", "X control identifies its coordinate axis")
eq(controls.windowY.positionAxis, "y", "Y control identifies its coordinate axis")

config.lockWindowPosition = false
module:RegisterMovers()
assert(not nativeRecord.isEnabled(), "clearing a saved anchor restored the oversized competing mover")
assert(moverRefreshes == 1, "clearing an anchor needlessly refreshed all host movers")
assert(element.isEnabled(), "clearing an anchor stranded the active chat mover")
config.lockWindowPosition, suite.states.chat.active = true, false
assert(not element.isEnabled(), "the mover of a stopped module stays")

-- Host records can be recreated after an adapter reload. The bridge claims
-- the replacement at the next edit session; releasing preserves native policy.
config.lockWindowPosition, suite.states.chat.active = true, true
module:RegisterMovers()
nativeRecord = { isEnabled = function() return nativeEnabled end }
ns.HostBridge.RefreshSuppressedEditElements()
assert(not nativeRecord.isEnabled(), "replacement native mover escaped the chat claim")
chat.DisableClock, chat.MessagesDisable, chat.FadeDisable = function() end, function() end, function() end
chat.BubblesDisable, chat.HistoryDisable = function() end, function() end
module.visuals = {}
-- Controller captures these two functions at load, so reload with release stubs.
chat.ReleaseNativeControls, chat.HideCopyDialog = function() end, function() end
assert(loadfile(root .. "/MSUF_Suite_Chat/Controller.lua"))("MSUF_Suite_Chat", { NS = ns, Suite = suite, Chat = chat })
module:Disable()
assert(nativeRecord.isEnabled(), "disabling Suite chat left the native mover suppressed")
nativeEnabled = false
assert(not nativeRecord.isEnabled(), "claim release overwrote native availability")
nativeEnabled = true
local registerMover = suite.RegisterOwnedMover
suite.RegisterOwnedMover = function() return false end
module:RegisterMovers()
assert(nativeRecord.isEnabled(), "failed Suite mover registration stranded the native mover")
suite.RegisterOwnedMover = registerMover

-- Detached movers own preview bounds. A commit saves only that native
-- window, and native dock/close/reuse never inherits another window's state.
do
    Constants.ChatFrameConstants.MaxChatWindows = 4
    local saves = {}
    local function Native(index, x, y, scale)
        local native = { points = { "TOPRIGHT", UIParent, "TOPRIGHT", -20, -30 },
            x = x, y = y, index = index, shown = true, scale = scale }
        function native:GetID() return self.index end
        function native:IsShown() return self.shown end
        function native:GetEffectiveScale() return self.scale * UIParent:GetEffectiveScale() end
        function native:GetLeft() return self.x end
        function native:GetBottom() return self.y end
        function native:GetWidth() return 320 end
        function native:GetHeight() return 140 end
        function native:ClearAllPoints() assert(not combat); self.points = {} end
        function native:SetPoint(...)
            assert(not combat)
            self.points = { ... }
            local point, _, _, px, py = ...
            assert(point == "BOTTOMLEFT")
            self.x = px + UIParent:GetLeft() / self.scale
            self.y = py + UIParent:GetBottom() / self.scale
        end
        return native
    end
    local guild, loot = Native(3, 180, 200, .75), Native(4, 450, 230, 1)
    ChatFrame3, ChatFrame4 = guild, loot
    function FCF_SavePositionAndDimensions(native) saves[#saves + 1] = native:GetID() end
    function suite.CreateFrame()
        local proxy = { shown = false }
        function proxy:EnableMouse() end
        function proxy:SetAlpha() end
        function proxy:SetScale() end
        function proxy:ClearAllPoints() self.point = nil end
        function proxy:SetPoint(...) self.point = { ... } end
        function proxy:SetSize(w, h) self.w, self.h = w, h end
        function proxy:GetWidth() return self.w or 330 end
        function proxy:GetHeight() return self.h or 166 end
        function proxy:IsShown() return self.shown end
        function proxy:Show() self.shown = true end
        function proxy:Hide() self.shown = false end
        return proxy
    end
    function chat.HeaderTop() return 20 end
    MSUF_EditModeAPI.GetCapabilities = function() return { positionFields = true } end
    module.active, suite.editMode = true, true
    chat.UpdateFloatingMoverBounds(module)
    module:RegisterMovers()
    local g, l = registered["MSUFSuite.chat/floating3"], registered["MSUFSuite.chat/floating4"]
    assert(g and l and g.getFrame() ~= l.getFrame(), "detached windows share a mover")
    assert(not g.extraControls and not l.extraControls, "detached window has duplicate coordinates")
    local opened, attempts
    MSUF_EditModeAPI.EnterEditMode = function(owner, id)
        attempts = (attempts or 0) + 1
        opened = owner .. "/" .. id
        return id == "floating4"
    end
    assert(suite.ChatOpenDetachedMover(4) and opened == "MSUFSuite.chat/floating4", "preview opened the wrong mover")
    attempts = 0
    assert(not suite.ChatOpenDetachedMover(3) and attempts == 1, "failed exact mover opened another window")
    g.onSessionChanged(true, "enter")
    local before = g.captureState()
    eq(before.x, 125, "scaled floating X")
    eq(before.y, 130, "scaled floating Y")
    assert(g.restoreState(before) and guild.points[1] == "TOPRIGHT" and #saves == 0, "unchanged discard saved a new anchor")
    assert(g.movePosition({ state = before, deltaX = 30, deltaY = -15, phase = "preview" }))
    eq(guild.x, 180, "preview moved Blizzard's frame")
    eq(#saves, 0, "preview saved native geometry")
    assert(g.movePosition({ state = before, deltaX = 30, deltaY = -15, phase = "commit" }))
    eq(guild.x, 220, "native commit used the wrong scale")
    eq(guild.y, 180, "native commit moved the wrong Y")
    eq(loot.x, 450, "moving Guild moved Loot")
    eq(#saves, 1, "one commit did not produce one native save")
    eq(saves[1], 3, "mover persisted the wrong native window")
    combat = true
    assert(not g.restoreState(before) and #saves == 1, "combat replay wrote native chat geometry")
    combat = false
    assert(g.restoreState(before) and guild.x == 180, "undo did not restore the detached window")
    guild.isDocked = true
    chat.UpdateFloatingMoverBounds(module)
    assert(not g.isEnabled() and l.isEnabled(), "docking Guild removed the wrong mover")
    g.onSessionChanged(true, "enter")
    guild.isDocked = false
    chat.FloatingWindowClosed(guild)
    assert(not g.restoreState(before), "a reused tab slot accepted stale mover history")
    local afterUndock = g.captureState()
    assert(g.movePosition({ state = afterUndock, deltaX = 15, deltaY = 0, phase = "commit" }))
    assert(guild.x == 200, "late detach could not move")
    g.onSessionChanged(false, "discard")
    eq(guild.x, 180, "discard lost the baseline of a newly detached window")

    Constants.ChatFrameConstants.MaxChatWindows = 5
    MSUF_EditModeAPI.GetCapabilities = nil
    ChatFrame5 = Native(5, 120, 160, 1)
    module:RegisterMovers()
    local legacy = registered["MSUFSuite.chat/floating5"]
    assert(legacy.extraControls and #legacy.extraControls == 2, "legacy host has no numeric detached position fields")
    local nativeDeleted, renames, layouts, title = 0, 0, 0, "Loot"
    function suite.PublicText(value) return type(value) == "string" end
    function GetChatWindowInfo(index) return index == 4 and title or "Guild" end
    function FCF_SetWindowName(frame, name)
        eq(frame, loot, "rename changed another chat frame")
        title, renames = name, renames + 1
    end
    function FCF_DockUpdate() layouts = layouts + 1 end
    function FCF_IsChatWindowIndexReserved(index) return index <= 3 end
    function FCF_IsChatWindowIndexActive(index) return _G["ChatFrame" .. index]:IsShown() end
    function IsBuiltinChatWindow() return false end
    function FCF_GetCurrentChatFrameID() return CURRENT_CHAT_FRAME_ID end
    function FCF_PopInWindow() nativeDeleted = nativeDeleted + 1 end
    ChatFrame5.isTemporary = true
    local choices = {}
    eq(suite.ChatDeletableTabs(choices), 1, "reserved/temporary chat is deletable")
    eq(choices[1].index, 4, "wrong native tab eligible for deletion")
    combat = true
    suite.ChatDeleteTabs(choices)
    assert(not suite.ChatRenameTab(choices[1], "Raid"), "rename accepted in combat")
    combat = false
    eq(nativeDeleted, 0, "delete accepted in combat")
    assert(not suite.ChatRenameTab(choices[1], "  "), "rename accepted a blank name")
    assert(suite.ChatRenameTab(choices[1], "Loot") and renames == 0 and layouts == 0, "same name caused a native write")
    title = "Renamed elsewhere"
    assert(not suite.ChatRenameTab(choices[1], "Raid"), "rename used a stale name snapshot")
    title = "Loot"
    chat.FloatingWindowClosed(loot)
    suite.ChatDeleteTabs(choices)
    eq(nativeDeleted, 0, "delete accepted a reused native slot")
    assert(not suite.ChatRenameTab(choices[1], "Raid"), "rename accepted a reused slot with the same title")
    suite.ChatDeletableTabs(choices)
    assert(suite.ChatRenameTab(choices[1], "  Raid Loot  "), "valid native rename was refused")
    assert(title == "Raid Loot" and renames == 1 and layouts == 1, "rename did not save through Blizzard and update the dock")
    local rebuilt = 0
    CURRENT_CHAT_FRAME_ID, DEFAULT_CHAT_FRAME = 4, { GetID = function() return 1 end }
    ChatConfigFrame = {
        IsShown = function() return true end,
        ChatTabManager = {
            UpdateSelection = function(_, index) CURRENT_CHAT_FRAME_ID = index end,
            UpdateTabDisplay = function() rebuilt = rebuilt + 1 end,
        },
    }
    suite.ChatDeletableTabs(choices)
    suite.ChatDeleteTabs(choices)
    eq(nativeDeleted, 1, "confirmed native close did not run")
    eq(CURRENT_CHAT_FRAME_ID, 1, "filter panel still points at a closed tab")
    eq(rebuilt, 1, "filter panel did not rebuild after closing a tab")
    ChatConfigFrame = nil
    ChatFrame5 = nil
    ChatFrame3, ChatFrame4 = nil, nil
    suite.editMode = false
    chat.HideFloatingMovers(module)
    Constants.ChatFrameConstants.MaxChatWindows = 0
end

------------------------------------------------------------------ keyword notices
-- A random dungeon, raid finder or battleground group talks on the instance
-- chat events; they count as raid chat while that group is a raid and as party
-- chat otherwise. The group is asked only when a phrase matched.
local SECRET = setmetatable({}, { __tostring = function() error("secret formatted") end })
local clock, printed, asked = 1000, {}, {}
local homeRaid, instanceRaid = false, false
GetTime = function() return clock end
GetServerTime = function() return clock end
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInRaid = function(category)
    asked[#asked + 1] = category
    if category == LE_PARTY_CATEGORY_INSTANCE then return instanceRaid end
    return homeRaid
end
local alerts
local keywordSuite = {
    Text = function(text) return text end,
    PublicText = function(value) if value ~= SECRET and type(value) == "string" then return value end end,
    Finite = function(value) return value ~= SECRET and type(value) == "number" and value == value end,
    Print = function(text) printed[#printed + 1] = text end,
    Notifications = { Push = function() return true end },
    ToolListWindow = { Close = function() end, Edit = function() end },
    Install = function(_, module) alerts = module end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/KeywordAlerts.lua"))("MSUF_Suite_QualityOfLife",
    { NS = {}, Suite = keywordSuite })
local listening = {}
local function Start(settings)
    local base = { words = "ready", party = false, raid = false, guild = false, say = false, channels = false,
        cooldown = 30, sound = false }
    for key, value in pairs(settings) do base[key] = value end
    for event in pairs(listening) do listening[event] = nil end
    printed, asked = {}, {}
    alerts.config = base
    alerts.context = {
        Event = function(_, event, callback) listening[event] = callback end,
        RemoveEvent = function(_, event) listening[event] = nil end,
    }
    alerts:Enable()
    return base
end
local function Say(event, text)
    local callback = listening[event]
    assert(callback, event .. " is not watched")
    callback(alerts, event, text, "Tank")
end
local INSTANCE_EVENTS = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

-- Party chat covers the instance group while it is a party.
Start({ party = true })
for _, event in ipairs(INSTANCE_EVENTS) do assert(listening[event], event .. " is not watched with party chat on") end
instanceRaid = false
Say("CHAT_MSG_INSTANCE_CHAT", "Ready check")
eq(#printed, 1, "a dungeon finder group's chat was not noticed")
eq(asked[1], LE_PARTY_CATEGORY_INSTANCE, "the group type asked about the home group")
clock = clock + 31
Say("CHAT_MSG_INSTANCE_CHAT_LEADER", "ready now")
eq(#printed, 2, "the instance leader's chat was not noticed")
-- A raid finder group is raid chat, which this setting leaves out.
clock = clock + 31
instanceRaid = true
Say("CHAT_MSG_INSTANCE_CHAT", "ready")
eq(#printed, 2, "a raid finder group counted as party chat")
-- The skipped message used no cooldown: the same phrase is noticed at once with raid chat on.
alerts.config.raid = true
Say("CHAT_MSG_INSTANCE_CHAT", "ready")
eq(#printed, 3, "a skipped message started the phrase's cooldown")

-- Raid chat alone covers the raid group but not the party.
Start({ raid = true })
for _, event in ipairs(INSTANCE_EVENTS) do assert(listening[event], event .. " is not watched with raid chat on") end
instanceRaid = true
Say("CHAT_MSG_INSTANCE_CHAT_LEADER", "ready")
eq(#printed, 1, "a raid finder group's chat was not noticed")
clock = clock + 31
instanceRaid = false
Say("CHAT_MSG_INSTANCE_CHAT", "ready")
eq(#printed, 1, "a dungeon finder group counted as raid chat")

-- Neither chat selected: no instance listener. Other scopes keep their events and never ask the group.
Start({ guild = true })
for _, event in ipairs(INSTANCE_EVENTS) do assert(not listening[event], event .. " is watched without party or raid chat") end
Start({ party = true, raid = true })
Say("CHAT_MSG_PARTY", "ready")
Say("CHAT_MSG_RAID", "ready again")
eq(#asked, 0, "the group type was asked for a home chat event")
clock = clock + 31
instanceRaid = false
Say("CHAT_MSG_INSTANCE_CHAT", "no phrase here")
eq(#asked, 0, "the group type was asked for a message no phrase matched")
Say("CHAT_MSG_INSTANCE_CHAT", SECRET)
eq(#asked, 0, "a restricted instance message was read")
Start({ party = true })
alerts.config.party = false
alerts:Refresh()
for _, event in ipairs(INSTANCE_EVENTS) do assert(not listening[event], event .. " stays watched after party chat went off") end
print("Chat audit: conflicts, greyed dependents, window mover and instance keyword notices passed")
