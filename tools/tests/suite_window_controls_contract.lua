local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

-- The client's securecallfunction reports an error and returns nothing.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
local function Reported(text)
    for index = 1, #reported do
        if reported[index]:find(text, 1, true) then return true end
    end
    return false
end

local function GeometryWrite(frame)
    assert(not frame.explicitProtected and not (frame.protected and (_G.combat or _G.combatEdge)),
        "contract: protected geometry write on " .. tostring(frame.name))
    frame.geometryWrites = (frame.geometryWrites or 0) + 1
end

local function Frame(name, parent, kind)
    local frame = {
        name = name, parent = parent, kind = kind or "Frame", shown = true,
        scale = 1, width = 600, height = 500, left = 100, top = 800,
        movable = true, scripts = {}, hooks = {},
    }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetObjectType() return self.kind end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return self.scale end
    function frame:GetEffectiveScale() return self.scale end
    function frame:SetScale(value) GeometryWrite(self); self.scale = value end
    function frame:IsResizable() return self.resizable end
    function frame:IsProtected() return self.protected or false, self.explicitProtected or false end
    function frame:IsForbidden() return false end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    function frame:IsMouseOver() return false end
    function frame:GetFrameLevel() return self.frameLevel or 1 end
    function frame:GetAlpha() return self.alpha or 1 end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetLeft() return self.left end
    function frame:GetTop() return self.top end
    function frame:GetNumPoints() return 1 end
    function frame:GetPoint() return self.anchorName or "CENTER", UIParent, "CENTER", 0, 0 end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetPoint(...) GeometryWrite(self); self.point = { ... } end
    function frame:ClearAllPoints() GeometryWrite(self); self.point = nil end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:GetFrameStrata()
        return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM"
    end
    function frame:SetFrameStrata(value) self.strata = value end
    function frame:SetClampedToScreen(value) self.clamped = value end
    function frame:SetMovable(value) GeometryWrite(self); self.movable = value end
    function frame:IsMovable() return self.movable end
    function frame:RegisterForDrag() end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:StartMoving() GeometryWrite(self); self.moving = true end
    function frame:StopMovingOrSizing() GeometryWrite(self); self.moving = false end
    function frame:RegisterForClicks() end
    function frame:SetButtonState() end
    function frame:SetNormalTexture(value) self.normalTexture = value end
    function frame:SetHighlightTexture() end
    function frame:SetPushedTexture() end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    -- Like the client: a hook on an empty script slot becomes its handler.
    function frame:GetScript(name)
        return self.scripts[name] or (self.hooks[name] and self.hooks[name][1])
    end
    function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function frame:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function frame:HookScript(name, callback)
        self.hooks[name] = self.hooks[name] or {}
        table.insert(self.hooks[name], callback)
    end
    function frame:Show()
        self.shown = true
        for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
    end
    function frame:Hide()
        self.shown = false
        for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
    end
    function frame:CreateTexture()
        local texture = { shown = true }
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        function texture:SetAllPoints() end
        function texture:SetColorTexture(...) self.color = { ... } end
        function texture:ClearAllPoints() self.point = nil end
        function texture:SetPoint(...) self.point = { ... } end
        function texture:SetSize(width, height) self.width, self.height = width, height end
        function texture:SetHeight(height) self.height = height end
        function texture:SetRotation(angle) self.angle = angle end
        function texture:SetSnapToPixelGrid(snap) self.snap = snap end
        function texture:SetTexelSnappingBias(bias) self.bias = bias end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        return texture
    end
    function frame:CreateLine()
        local line = {}
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = line
        function line:SetThickness(value) self.thickness = value end
        function line:Show() self.shown = true end
        function line:Hide() self.shown = false end
        function line:SetStartPoint(point, relativeTo, x, y)
            assert(type(relativeTo) == "table", "Line:SetStartPoint needs a relative region")
            self.startPoint = { point, relativeTo, x, y }
        end
        function line:SetEndPoint(point, relativeTo, x, y)
            assert(type(relativeTo) == "table", "Line:SetEndPoint needs a relative region")
            self.endPoint = { point, relativeTo, x, y }
        end
        function line:SetColorTexture(...) self.color = { ... } end
        return line
    end
    function frame:CreateFontString()
        return {
            SetPoint = function() end, SetJustifyH = function() end,
            SetText = function(self, text) self.text = text end, SetTextColor = function() end,
        }
    end
    return frame
end

UIParent = Frame("UIParent")
UIParent.width, UIParent.height = 1920, 1080
GetCursorPosition = function() return _G.cursorX or 0, _G.cursorY or 0 end
InCombatLockdown = function() return _G.combat or false end
-- Retail and Forever always have this; the left button stays held unless a
-- check below releases it.
IsMouseButtonDown = function() return true end
UIPanelWindows = { CharacterFrame = { area = "left" }, MerchantFrame = { area = "left" },
    ContainerFrameCombinedBags = { area = "left" } }
HideUIPanel = function(frame) frame:Hide() end
ShowUIPanel = function(frame) frame:Show() end
-- Forever's SmartNavigation post-hooks CreateFrame and rescans the panel above
-- the parent argument in the caller's (tainted) execution; skin controls inside
-- a Blizzard window are therefore created without one and parented afterwards.
local parentedCreates = 0
local createdFrames = {}
-- 12.x secret values: anything marked here reads as secret.
local secretValues = setmetatable({}, { __mode = "k" })
issecretvalue = function(value) return secretValues[value] == true end
CreateFrame = function(kind, _, parent)
    if parent ~= nil and parent ~= UIParent then parentedCreates = parentedCreates + 1 end
    local frame = Frame(nil, parent, kind)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
-- WoW Forever's SmartNavigation scans a panel it focuses or whose subtree gets
-- a new frame (Blizzard_GamepadSmartNavigation/SmartNavigation.lua:1612-1658,
-- Utility.lua:208-260) in secure code. SmartNavigation_CanFocusFrame
-- (Utility.lua:196-206) reads GetScript("OnMouseUp") and GetScript("OnMouseDown")
-- of every descendant that is not a Button or EditBox: a skin handler there is
-- a skin-tainted value in that execution (B on the Game Menu then had
-- SetPreferredGamepadInteractTarget blocked, MSUF_Suite_Skin blamed).
local function SkinHandlerSeenBySmartNavigation(panel)
    for _, frame in ipairs(createdFrames) do
        local ancestor = frame.parent
        while ancestor and ancestor ~= panel do ancestor = ancestor.parent end
        if ancestor == panel and frame.kind ~= "Button" and frame.kind ~= "EditBox"
            and (frame:GetScript("OnMouseUp") ~= nil or frame:GetScript("OnMouseDown") ~= nil) then
            return frame
        end
    end
end
local panelPositionHook
UpdateUIPanelPositions = function(frame)
    if frame then frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -90) end
    if panelPositionHook then panelPositionHook() end
end
hooksecurefunc = function(name, callback, method)
    if type(name) == "table" then
        local object, key, post = name, callback, method
        local native = object[key]
        object[key] = function(...) native(...) post(...) end
        return
    end
    -- The UI scale fit hook comes with it (suite_window_controls_edges_contract.lua).
    if name == "UpdateScaleForFitForOpenPanels" then return end
    assert(name == "UpdateUIPanelPositions")
    panelPositionHook = callback
end
local historyCalls = 0
MSUF2 = { RunWithHistory = function(_, _, fn)
    historyCalls = historyCalls + 1
    return fn()
end }

local adapterPasses = 0
local combatJobs = {}
-- Registry.QueueJob runs a job once on the next frame (Core/Registry.lua).
local queuedJobs = {}
local function QueueJob(job)
    for _, pending in ipairs(queuedJobs) do if pending == job then return end end
    queuedJobs[#queuedJobs + 1] = job
end
local function NextFrame()
    local jobs = queuedJobs
    queuedJobs = {}
    for _, job in ipairs(jobs) do job() end
end
local printed = {}
local NS = {
    Print = function(message) printed[#printed + 1] = message end,
    -- The skin's locale table (Locales/Localization.lua) is ready before
    -- any of this runs; here every key reads as itself.
    L = setmetatable({}, { __index = function(_, key) return key end }),
    DB = { enabled = true, skins = { blizzardWindows = true },
        windowControls = { enabled = true, scales = {}, positions = {} } },
    Theme = { GetColor = function() return 0.2, 0.3, 0.4, 1 end },
    Surface = { SkinOwnedButton = function(button, spec) button.surfaceSpec = spec; return true end },
    Registry = { AddListener = function() end, QueueJob = QueueJob },
    BlizzardCatalog = { FindByFrame = function(name)
        if name == "CharacterFrame" or name == "InspectFrame" then return { category = "character" } end
        if name == "WorldMapFrame" then return { category = "map" } end
        if name == "MerchantFrame" then return { category = "npc" } end
        if name == "ContainerFrameCombinedBags" then return { category = "inventory" } end
    end },
    IsCombatLocked = function() return InCombatLockdown() or _G.combatEdge == true end,
    CombatGate = { RunOrDefer = function(key, callback)
        if _G.combat or _G.combatEdge then combatJobs[key] = callback; return false end
        callback()
        return true
    end },
    -- Retail until the Forever check below; Client.lua loads before Defaults.
    Client = { isForever = false, IsGamepadUI = function() return false end },
    -- Blizzard.lua's adapter registry, which always loads with this file.
    Adapters = { ApplyAll = function() adapterPasses = adapterPasses + 1 end },
}
local core = { HostBridge = {} }
core.Suite = {}
assert(loadfile(root .. "/MSUF_Suite/Core/WindowCaption.lua"))("MSUF_Suite", core)
core.WindowCaption.PixelFactor = function() return nil end
NS.WindowActionSkin = NS.WindowActionSkin or { Yield = function() end }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", core)
NS.SuiteCore = function() return core end
local bridgeHistoryCalls, withHistory = 0, core.HostBridge.WithMenuHistory
core.HostBridge.WithMenuHistory = function(...)
    bridgeHistoryCalls = bridgeHistoryCalls + 1
    return withHistory(...)
end
-- The real guards and layout limits, not stubs.
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/WindowControlPolicy.lua"))("MSUF_Suite_Skin", NS)
local chromeFrames = #createdFrames
assert(loadfile(arg[3] or root .. "/MSUF_Suite_Skin/Rendering/WindowControlChrome.lua"))("MSUF_Suite_Skin", NS)
-- The frame that looks at opening windows (WindowControlChrome.lua); one frame passes.
local watcher = createdFrames[chromeFrames + 1]
local function Watch(elapsed) watcher.scripts.OnUpdate(watcher, elapsed) end
assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))("MSUF_Suite_Skin", NS)

-- Safety helpers always return a value, even when they refuse to read.
local Safety = NS.Safety
Check(type(Safety.Field(nil, "x")) == "nil" and select("#", Safety.Field(nil, "x")) == 1,
    "Safety.Field returned no value for a non-table")
Check(select("#", Safety.Call(nil, "X")) >= 1 and select("#", Safety.Read(nil, "X")) >= 1,
    "Safety.Call or Safety.Read returned no value for a non-table")
local probe = { IsForbidden = function() return false end, Quiet = function() end }
Check(select("#", Safety.Call(probe, "Missing")) >= 1 and select("#", Safety.Call(probe, "Quiet")) >= 1
    and type(Safety.Call(probe, "Quiet")) == "nil", "Safety.Call returned no value")
local forbidden = { IsForbidden = function() return true end, GetName = function() return "X" end }
Check(select("#", Safety.Call(forbidden, "GetName")) == 1 and Safety.Call(forbidden, "GetName") == nil
    and not Safety.Invoke(forbidden, "GetName"), "Safety called a method on a forbidden object")
Check(select(2, Safety.Call({ Pair = function() return 1, 2 end }, "Pair")) == 2,
    "Safety.Call dropped a result")

local character = Frame("CharacterFrame", UIParent)
character.CloseButton = Frame(nil, character, "Button")
Check(NS.WindowControls.Attach(character, "blizzardWindows"), "character panel was not attached")
local state = NS.WindowControls.states[character]
Check(state and state.grip and state.minimize and state.restore and not state.move,
    "window controls missing")
Check(state.titleDrag and state.titleDrag.mouseEnabled
    and state.titleDrag.parent == character,
    "window title is not a direct mouse drag target")
Check(parentedCreates == 0,
    "window controls passed a Blizzard window to CreateFrame (SmartNavigation rescans it tainted)")
Check(SkinHandlerSeenBySmartNavigation(character) == nil,
    "a skin Frame inside a Blizzard window has a mouse handler SmartNavigation reads (FV-2)")
-- The title strip's release net without a mouse handler: GLOBAL_MOUSE_UP,
-- registered only while the panel moves.
state.titleDrag.scripts.OnDragStart(state.titleDrag)
Check(character.moving and state.titleDrag.events and state.titleDrag.events.GLOBAL_MOUSE_UP,
    "a title drag did not watch for the mouse release")
state.titleDrag.scripts.OnEvent(state.titleDrag, "GLOBAL_MOUSE_UP", "LeftButton")
Check(not character.moving and not state.titleDrag.events.GLOBAL_MOUSE_UP,
    "a mouse release outside the title strip did not end the move")
NS.DB.windowControls.positions.CharacterFrame, historyCalls, bridgeHistoryCalls = nil, 0, 0
-- A grip press that changes nothing (a click, or A on the grip under Forever's
-- Gamepad UI, where SmartNavigation clicks it) stores no scale and no history.
state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
state.grip.scripts.OnMouseUp(state.grip)
Check(historyCalls == 0 and NS.DB.windowControls.scales.CharacterFrame == nil and not state.customScale,
    "a grip press that changed nothing wrote a scale and a history entry")
Check(state.minimize.point[1] == "TOPRIGHT",
    "a bottom Close action incorrectly moved the minimize button to the footer")
cursorX, cursorY = 500, 500
state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
Check(type(state.grip.scripts.OnUpdate) == "function", "drag lacks transient update")
cursorX, cursorY = 620, 440
state.grip.scripts.OnUpdate(state.grip)
state.grip.scripts.OnMouseUp(state.grip)
Check(character.scale > 1 and NS.DB.windowControls.scales.CharacterFrame == character.scale,
    "drag did not persist the panel scale")
Check(state.grip.scripts.OnUpdate == nil, "drag left a permanent update")
state.titleDrag.scripts.OnDragStart(state.titleDrag)
Check(character.moving, "title did not start dragging")
character.left, character.top = 420, 840
state.titleDrag.scripts.OnDragStop(state.titleDrag)
Check(not character.moving and NS.DB.windowControls.positions.CharacterFrame
    and NS.DB.windowControls.positions.CharacterFrame.x == math.floor(420 * character.scale + 0.5),
    "move did not persist a free position")
UpdateUIPanelPositions(character)
Check(character.point and character.point[4] ==
    NS.DB.windowControls.positions.CharacterFrame.x / character.scale,
    "Blizzard reflow replaced the saved position")
Check(historyCalls == 2, "move and scale were not committed through MSUF history")
Check(bridgeHistoryCalls == 2, "window geometry bypassed the Suite's host history boundary")
character:Hide()
character:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -90)
character:Show()
Check(character.point[4] == NS.DB.windowControls.positions.CharacterFrame.x / character.scale,
    "reopening the panel lost its saved position")
state.minimize.scripts.OnClick(state.minimize)
Check(not character.shown and state.restore.shown, "minimize did not leave a restore tab")
state.restore.scripts.OnClick(state.restore, "LeftButton")
Check(character.shown and not state.restore.shown, "restore did not reopen the panel")
-- WoW Forever's Gamepad UI: its frame controls manager follows ShowUIPanel and
-- HideUIPanel in the caller's context, so the skin never drives the panel
-- manager then (SetPreferredGamepadInteractTarget stayed blocked otherwise).
state.minimize.scripts.OnClick(state.minimize)
local panelCalls = 0
local nativeShow, nativeHide, nativeUpdate = ShowUIPanel, HideUIPanel, UpdateUIPanelPositions
ShowUIPanel = function(frame) panelCalls = panelCalls + 1; nativeShow(frame) end
HideUIPanel = function(frame) panelCalls = panelCalls + 1; nativeHide(frame) end
UpdateUIPanelPositions = function(frame) panelCalls = panelCalls + 1; nativeUpdate(frame) end
NS.Client.IsGamepadUI = function() return true end
state.restore.scripts.OnClick(state.restore, "LeftButton")
Check(character.shown and not state.restore.shown and panelCalls == 0,
    "restore drove the panel manager under the Gamepad UI")
NS.WindowControls.Refresh()
Check(not state.minimize.shown, "the Gamepad UI kept the skin's minimize button")
state.minimize.scripts.OnClick(state.minimize)
Check(character.shown and not state.restore.shown and panelCalls == 0,
    "minimize drove the panel manager under the Gamepad UI")
NS.Client.IsGamepadUI = function() return false end
ShowUIPanel, HideUIPanel, UpdateUIPanelPositions = nativeShow, nativeHide, nativeUpdate
NS.WindowControls.Refresh()
Check(state.minimize.shown, "the minimize button did not come back without the Gamepad UI")
Check(NS.WindowControls.SetEnabled(false) and not state.grip.shown
    and not state.minimize.shown and not state.titleDrag.shown,
    "disabling controls left live buttons")
Check(NS.WindowControls.SetEnabled(true) and state.grip.shown
    and state.minimize.shown and state.titleDrag.shown, "reenabling controls failed")
Check(adapterPasses == 1, "reenabling controls did not reapply the adapters")
NS.DB.windowControls.scales.CharacterFrame = 1.11
NS.WindowControls:OnThemeChanged("profile")
NextFrame()
Check(character.scale == 1.11, "profile restore did not reapply saved scale")
NS.DB.windowControls.positions.CharacterFrame = { x = 325, y = -140 }
NS.WindowControls:OnThemeChanged("profile")
NextFrame()
Check(character.point[4] == 325 / character.scale,
    "profile restore did not reapply saved position")
NS.DB.windowControls.enabled = false
NS.WindowControls:OnThemeChanged("profile")
NextFrame()
Check(not state.grip.shown and not state.minimize.shown,
    "history restore did not hide disabled controls")
NS.DB.windowControls.enabled = true
NS.WindowControls:OnThemeChanged("profile")
NextFrame()

local merchant = Frame("MerchantFrame", UIParent)
Check(NS.WindowControls.Attach(merchant, "blizzardWindows")
    and not NS.WindowControls.states[merchant].minimize,
    "transactional NPC panel should scale without a destructive minimize or close-button dependency")
local settings = Frame("SettingsPanel")
settings.resizable = true
settings.ClosePanelButton = Frame(nil, settings, "Button")
settings.ClosePanelButton.anchorName = "TOPRIGHT"
settings.CloseButton = Frame(nil, settings, "Button")
Check(NS.WindowControls.Attach(settings, "settings")
    and NS.WindowControls.states[settings].grip
    and NS.WindowControls.states[settings].titleDrag,
    "Blizzard Settings was wrongly excluded for native resizability")
Check(NS.WindowControls.states[settings].minimize.point[2] == settings.ClosePanelButton,
    "Settings minimize was anchored beside the bottom Close action instead of the top X")
Check(not NS.WindowControls.states[settings].move,
    "the visible Move control still obscures the Blizzard window")
cursorX, cursorY = 500, 500
local settingsGrip = NS.WindowControls.states[settings].grip
settingsGrip.scripts.OnMouseDown(settingsGrip, "LeftButton")
cursorX, cursorY = 600, 450
settingsGrip.scripts.OnUpdate(settingsGrip)
settingsGrip.scripts.OnMouseUp(settingsGrip)
Check(settings.scale > 1 and NS.DB.windowControls.scales.SettingsPanel == settings.scale,
    "the Settings resize grip is visible but cannot scale the window")
local settingsTitle = NS.WindowControls.states[settings].titleDrag
settingsTitle.scripts.OnDragStart(settingsTitle)
Check(settings.moving, "dragging the Settings title did not move the window")
settings.left, settings.top = 380, 760
settingsTitle.scripts.OnDragStop(settingsTitle)
Check(not settings.moving and NS.DB.windowControls.positions.SettingsPanel
    and NS.DB.windowControls.positions.SettingsPanel.x == math.floor(380 * settings.scale + 0.5),
    "dragging the Settings title did not persist its position")
local bags = Frame("ContainerFrameCombinedBags", UIParent)
bags.CloseButton = Frame(nil, bags, "Button")
Check(not NS.WindowControls.Attach(bags, "blizzardWindows"), "bags were modified")
local protected = Frame("CharacterFrame", UIParent)
protected.CloseButton = Frame(nil, protected, "Button")
protected.protected = true
Check(not NS.WindowControls.Attach(protected, "blizzardWindows"), "protected frame was modified")
combat = true
local other = Frame("CharacterFrame", UIParent)
other.CloseButton = Frame(nil, other, "Button")
Check(NS.WindowControls.Attach(other, "combat-create"), "safe combat window lost its controls")
other:Hide()
combat = false
NS.WindowControls.DisableOwner("combat-create")
Check(NS.WindowControls.ResetScales() and character.scale == 1
    and NS.DB.windowControls.scales.CharacterFrame == nil, "reset failed")
Check(NS.WindowControls.ResetPositions()
    and NS.DB.windowControls.positions.CharacterFrame == nil
    and character.point[1] == "TOPLEFT" and character.point[4] == 30,
    "position reset did not return to Blizzard layout")

-- Forever's authored placement is a virtual default, not a saved position.
NS.Client = { isForever = true, IsGamepadUI = function() return false end }
NS.DB.theme = { look = "foreverGlass" }
NS.WindowControls:OnThemeChanged("theme", "look")
NextFrame()
Check(state.defaultPosition and character.point[4] == 0
    and NS.DB.windowControls.positions.CharacterFrame == nil,
    "Forever character default was not docked without saving a position")
Check(state.titleDrag.shown and state.titleDrag.mouseEnabled,
    "Forever character title is not available for mouse dragging")
UpdateUIPanelPositions(character)
Check(character.point[4] == 0, "Blizzard reflow displaced the Forever dock")
NS.DB.windowControls.positions.CharacterFrame = { x = 325, y = -140 }
NS.WindowControls:OnThemeChanged("profile")
NextFrame()
Check(not state.defaultPosition and character.point[4] == 325,
    "saved position did not override the Forever dock")
Check(NS.WindowControls.ResetPositions() and state.defaultPosition
    and character.point[4] == 0,
    "reset did not restore the Forever default")
NS.DB.theme.look = "midnight"
NS.WindowControls:OnThemeChanged("theme", "look")
NextFrame()
Check(not state.defaultPosition and character.point[4] == 30,
    "switching away from Forever did not restore native placement")

-- The scale drag stops itself when the button is released outside the grip
-- or the panel hides, without waiting for OnMouseUp.
local mouseDown = true
IsMouseButtonDown = function() return mouseDown end
cursorX, cursorY = 500, 500
state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
cursorX, cursorY = 560, 470
state.grip.scripts.OnUpdate(state.grip)
mouseDown = false
state.grip.scripts.OnUpdate(state.grip)
Check(state.grip.scripts.OnUpdate == nil and state.drag == nil
    and NS.DB.windowControls.scales.CharacterFrame == character.scale,
    "a released mouse button did not end the scale drag")
mouseDown = true
state.grip.scripts.OnMouseDown(state.grip, "LeftButton")
character:Hide()
Check(state.grip.scripts.OnUpdate == nil and state.drag == nil,
    "hiding the panel left the scale drag running")
character:Show()
IsMouseButtonDown = function() return true end
Check(state.grip.scripts.OnMouseDown == settingsGrip.scripts.OnMouseDown
    and state.titleDrag.scripts.OnDragStart == settingsTitle.scripts.OnDragStart,
    "window controls allocate script handlers per panel")

-- A Blizzard panel layout that raises while a reset returns a panel to its
-- native anchors is reported, the reset says it failed, and the layout hook
-- still re-places saved panels afterwards.
NS.DB.windowControls.positions.CharacterFrame = { x = 200, y = -100 }
NS.WindowControls:OnThemeChanged("profile")
NextFrame()
local nativeLayout = UpdateUIPanelPositions
local failLayout = true
UpdateUIPanelPositions = function(frame)
    if failLayout then
        failLayout = false
        error("panel layout failed")
    end
    return nativeLayout(frame)
end
Check(NS.WindowControls.ResetPositions() == false and Reported("panel layout failed"),
    "a failed native restore was reported as a successful reset")
NS.DB.windowControls.positions.CharacterFrame = { x = 150, y = -60 }
NS.WindowControls:OnThemeChanged("profile")
NextFrame()
UpdateUIPanelPositions(character)
Check(character.point[4] == 150 / character.scale,
    "the panel layout hook stayed suspended after a failed reset")
UpdateUIPanelPositions = nativeLayout

-- Stored scales remain stable in combat for safe panels. Protected panels
-- retain their native geometry and lose their controls outside combat.
local scaleBefore = character.scale
NS.DB.windowControls.scales.CharacterFrame = 1.25
combat = true
NS.WindowControls.Refresh()
Check(character.scale == 1.25, "a safe combat profile refresh lost its selected scale")
scaleBefore = character.scale
combat = false
character.protected = true
NS.WindowControls.Refresh()
Check(character.scale == scaleBefore and not state.grip.shown and not state.titleDrag.shown,
    "a protected panel was scaled or kept its window controls")
character.protected = false
NS.WindowControls.Refresh()
Check(character.scale == 1.25 and state.grip.shown and state.titleDrag.shown,
    "a panel that is no longer protected did not get its controls back")
character.protected = true
Check(not NS.WindowControls.Attach(character, "blizzardWindows")
    and not state.grip.shown and not state.titleDrag.shown,
    "a panel that became protected kept its grip and drag strip")
character.protected = false
Check(#reported == 1, "window controls reported unexpected errors: " .. table.concat(reported, "; "))

-- The invisible title strip takes the title area's clicks: reopening a panel
-- brings it back only while the controls are on for a skinning owner and
-- the panel can be controlled.
Check(NS.WindowControls.Attach(character, "blizzardWindows") and state.titleDrag.shown,
    "the character panel did not get its controls back")
NS.WindowControls.DisableOwner("blizzardWindows")
character:Hide()
character:Show()
Check(not state.titleDrag.shown, "reopening a released panel showed its title strip")
Check(NS.WindowControls.Attach(character, "blizzardWindows") and state.titleDrag.shown,
    "the character panel was not controllable again")
NS.DB.enabled = false
NS.WindowControls.Refresh()
character:Hide()
character:Show()
Check(not state.titleDrag.shown, "reopening a panel with skinning off showed its title strip")
NS.DB.enabled = true
NS.WindowControls.Refresh()
character.protected = true
character:Hide()
character:Show()
Check(not state.titleDrag.shown, "reopening a protected panel showed its title strip")
character.protected = false

-- Blizzard fits a checkFit panel to the screen with SetScale(1) each time it
-- opens (UIPanelUpdateScaleForFit, UIParentPanelManager.lua): the grip's
-- scale comes back before the stored position is placed with it. Turning the
-- controls off gives the panel Blizzard's scale back; turning them on, the
-- stored one.
local spells = Frame("PlayerSpellsFrame", UIParent)
local previousSpellsFlavor = NS.Client.isForever
NS.Client.isForever = false
spells.NineSlice = Frame(nil, spells)
spells.NineSlice:SetFrameLevel(5500)
Check(NS.WindowControls.Attach(spells, "blizzardWindows"), "the spellbook panel was not attached")
Check(NS.WindowControls.states[spells].grip:GetFrameLevel() == spells.NineSlice:GetFrameLevel() + 20,
    "Mainline spellbook grip stayed beneath native chrome")
NS.Client.isForever = previousSpellsFlavor
NS.DB.windowControls.scales.PlayerSpellsFrame = 0.8
NS.DB.windowControls.positions.PlayerSpellsFrame = { x = 400, y = -100 }
Check(NS.WindowControls.Refresh() and spells.scale == 0.8, "the stored spellbook scale was not applied")
spells:Hide()
spells:SetScale(1)
spells:Show()
Check(spells.scale == 0.8, "opening a checkFit panel undid the grip's scale")
Check(spells.point and spells.point[4] == 400 / 0.8, "the stored position was placed before the stored scale")
Check(NS.WindowControls.SetEnabled(false) and spells.scale == 1, "turning the controls off kept the grip's scale")
spells:Hide()
spells:Show()
Check(spells.scale == 1, "a panel without controls got the grip's scale when it opened")
Check(NS.WindowControls.SetEnabled(true) and spells.scale == 0.8, "turning the controls on lost the stored scale")
NS.WindowControls.DisableOwner("blizzardWindows")
Check(spells.scale == 1, "releasing the panel kept the grip's scale")
Check(NS.WindowControls.Attach(spells, "blizzardWindows") and spells.scale == 0.8,
    "attaching the panel again lost the stored scale")
NS.DB.windowControls.scales.PlayerSpellsFrame, NS.DB.windowControls.positions.PlayerSpellsFrame = nil, nil
NS.WindowControls.Refresh()

-- Both clients raise portrait chrome above their content: PlayerSpells sets
-- NineSlice to 5500; professions inherits the portrait level 500, above its
-- CraftingPage/BookPage at 100. Our grip must render above that chrome and
-- follow subsequent native frame-level changes without touching the pages.
do
    local previousSpellbook = _G.PlayerSpellsFrame
    for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client.isForever = flavor == "Forever"
    for _, name in ipairs({ "PlayerSpellsFrame", "ProfessionsFrame" }) do
        local panel = Frame(name, UIParent)
        panel.NineSlice = Frame(nil, panel)
        panel.NineSlice:SetFrameLevel(name == "PlayerSpellsFrame" and 5500 or 500)
        local page = Frame(nil, panel)
        page:SetFrameLevel(100)
        if name == "PlayerSpellsFrame" then
            panel.SpellBookFrame = page
            -- Shared spellbook XML creates this explicitly secure button even
            -- in Camelot. Its outer portrait container is only implicitly secure.
            local secureButton = Frame(nil, page, "Button")
            secureButton.protected, secureButton.explicitProtected = true, true
            page.AssistedCombatRotationSpellFrame = { Button = secureButton }
            panel.protected, _G.PlayerSpellsFrame = true, panel
            local impostor = Frame(name, UIParent)
            impostor.protected = true
            Check(not NS.WindowControls.Attach(impostor, "foreverBooks"), "a named impostor bypassed protection")
        else
            panel.CraftingPage = page
        end
        Check(NS.WindowControls.Attach(panel, "foreverBooks"), name .. " did not attach")
        local controls = NS.WindowControls.states[panel]
        Check(controls.grip:GetFrameLevel() > panel.NineSlice:GetFrameLevel()
            and controls.titleDrag:GetFrameLevel() > panel.NineSlice:GetFrameLevel(),
            name .. " controls stayed beneath native portrait chrome/content")
        Check(not controls.minimize, name .. " gained a custom minimize that can end native interactions")
        if name == "ProfessionsFrame" then
            -- Native Create button: width80, height28, BOTTOMRIGHT(-9,+7)
            -- or y13 when minimized. Calculate the grip's actual rectangle.
            local anchor = controls.grip.point
            Check(anchor[2] == panel and anchor[3] == "BOTTOMRIGHT", "profession grip uses an unexpected anchor")
            local left = anchor[4] - (anchor[1] == "BOTTOMRIGHT" and controls.grip.width or 0)
            local top = anchor[5] + (anchor[1] == "TOPLEFT" and 0 or controls.grip.height)
            local right, bottom = left + controls.grip.width, top - controls.grip.height
            Check(left >= 0 and top <= 0, "profession grip overlaps the right tab column or lower footer")
            for _, createBottom in ipairs({ 7, 13 }) do
                Check(right <= -89 or left >= -9 or top <= createBottom or bottom >= createBottom + 28,
                    "profession grip intercepts the native Create button")
            end
        end
        panel.NineSlice:SetFrameLevel(panel.NineSlice:GetFrameLevel() + 50)
        panel:Hide()
        panel:Show()
        Check(controls.grip:GetFrameLevel() > panel.NineSlice:GetFrameLevel(),
            name .. " reopening did not refresh the grip level")
        Check(page:GetFrameLevel() == 100, name .. " controls changed the native content level")
        panel.left, panel.top = 100, 800
        cursorX, cursorY = 650, 350
        controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
        cursorX, cursorY = 760, 260
        controls.grip.scripts.OnUpdate(controls.grip)
        controls.grip.scripts.OnMouseUp(controls.grip)
        Check(panel.scale > 1 and math.abs(NS.DB.windowControls.scales[name] - panel.scale) < 0.001,
            name .. " grip did not save its scale")
        Check(panel.width == 600 and panel.height == 500 and not controls.grip.scripts.OnUpdate,
            name .. " scale changed native layout or left a running drag")
        local savedScale = panel.scale
        panel:Hide()
        panel:SetScale(1)
        panel:Show()
        Check(panel.scale == savedScale, name .. " native reopening lost the saved scale")
        if name == "PlayerSpellsFrame" then
            controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
            local beforeCombatScale, beforeCombatWrites = panel.scale, panel.geometryWrites
            combat = true
            cursorX, cursorY = 900, 100
            controls.grip.scripts.OnUpdate(controls.grip)
            Check(panel.scale == beforeCombatScale and panel.geometryWrites == beforeCombatWrites
                and not controls.grip.scripts.OnUpdate, "combat did not stop the protected spellbook scale drag")
            combat = false
            panel:SetMovable(false)
            controls.titleDrag.scripts.OnDragStart(controls.titleDrag)
            Check(panel.moving and panel.movable, "implicit spellbook root could not move outside combat")
            local writes = panel.geometryWrites
            combatEdge = true -- Suite refuses before InCombatLockdown changes.
            controls.titleDrag.scripts.OnDragStop(controls.titleDrag)
            combatEdge, combat = false, true
            panel:Hide()
            panel:Show()
            NS.WindowControls.Attach(panel, "foreverBooks")
            NS.WindowControls.Refresh()
            Check(panel.geometryWrites == writes and panel.moving
                and combatJobs["windowControls:move:PlayerSpellsFrame"],
                "ending spellbook movement during combat wrote protected geometry instead of deferring")
            combat = false
            local pending = combatJobs["windowControls:move:PlayerSpellsFrame"]
            combatJobs["windowControls:move:PlayerSpellsFrame"] = nil
            pending()
            Check(not panel.moving and not panel.movable
                and NS.DB.windowControls.positions[name], "deferred move did not restore native movability/save position")
            Check(page.AssistedCombatRotationSpellFrame.Button.geometryWrites == nil,
                "spellbook controls mutated the native secure button")
        end
        NS.WindowControls.DisableOwner("foreverBooks")
        Check(panel.scale == 1 and not controls.grip.shown, name .. " owner release kept its controls")
        Check(NS.WindowControls.Attach(panel, "foreverBooks") and panel.scale == savedScale,
            name .. " reattachment lost its saved scale")
        panel.protected, panel.explicitProtected = true, true
        Check(not NS.WindowControls.Attach(panel, "foreverBooks") and not controls.grip.shown,
            name .. " retained controls after becoming protected")
        local protectedWrites = panel.geometryWrites
        UpdateUIPanelPositions()
        Check(panel.geometryWrites == protectedWrites, name .. " position replay moved an explicitly protected panel")
        panel.protected, panel.explicitProtected = false, false
        NS.DB.windowControls.scales[name] = nil
        NS.DB.windowControls.positions[name] = nil
    end
    NS.WindowControls.DisableOwner("foreverBooks")
    end
    _G.PlayerSpellsFrame = previousSpellbook
    NS.Client.isForever = false
end

-- Forever's dedicated skin reaches WindowControls through GenericWindows,
-- but its outer LFG container has no catalog entry. The three PortraitFrame
-- panes remain anchored to it and must never gain separate geometry controls.
do
    local previousForever = NS.Client.isForever
    NS.Client.isForever = false
    LFG_TITLE = "Native localized group finder"
    local owner = "blizzardWindows:forever-group-finder"
    local lfg = Frame("LFGParentFrame", UIParent)
    lfg.width, lfg.height, lfg.movable = 458, 535, false
    UIPanelWindows.LFGParentFrame = { area = "left", pushable = 7, whileDead = 1 }
    LFGParentFrameCloseButton = Frame("LFGParentFrameCloseButton", lfg, "Button")
    LFGParentFrameCloseButton.anchorName = "TOPRIGHT"
    Check(not NS.WindowControls.Attach(lfg, owner), "Forever LFG geometry was enabled on Retail")
    NS.Client.isForever = true
    Check(NS.WindowControls.Attach(lfg, owner), "Forever LFG container was excluded from window controls")
    local lfgState = NS.WindowControls.states[lfg]
    Check(lfgState.titleDrag and lfgState.grip and lfgState.minimize and lfgState.restore,
        "Forever group finder lacks move, scale or minimize/restore controls")
    Check(lfgState.minimize.point[2] == LFGParentFrameCloseButton,
        "Forever minimize did not use the native global close button")
    for _, name in ipairs({ "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }) do
        Check(not NS.WindowControls.Attach(Frame(name, lfg), owner), "LFG child pane gained independent controls")
    end
    lfgState.titleDrag.scripts.OnDragStart(lfgState.titleDrag)
    Check(lfg.moving and lfg.movable, "Forever title drag did not temporarily make the container movable")
    lfg.left, lfg.top = 350, 820
    lfgState.titleDrag.scripts.OnDragStop(lfgState.titleDrag)
    Check(not lfg.moving and not lfg.movable and NS.DB.windowControls.positions.LFGParentFrame.x == 350,
        "Forever drag lost position or did not restore native movability")
    UpdateUIPanelPositions(lfg)
    Check(lfg.point[4] == 350, "native panel layout displaced the moved LFG container")
    cursorX, cursorY = 500, 500
    lfgState.grip.scripts.OnMouseDown(lfgState.grip, "LeftButton")
    cursorX, cursorY = 650, 400
    lfgState.grip.scripts.OnUpdate(lfgState.grip)
    lfgState.grip.scripts.OnMouseUp(lfgState.grip)
    local scale = lfg.scale
    Check(scale > 1 and NS.DB.windowControls.scales.LFGParentFrame == scale
        and lfg.width == 458 and lfg.height == 535 and not lfgState.grip.scripts.OnUpdate,
        "Forever grip did not persist scale while retaining the native pane layout")
    lfgState.minimize.scripts.OnClick(lfgState.minimize)
    Check(not lfg.shown and lfgState.restore.shown, "Forever LFG window did not minimize")
    Check(lfgState.restoreLabel.text == LFG_TITLE .. "  +", "Forever restore bar exposed the internal parent name")
    lfgState.restore.scripts.OnClick(lfgState.restore, "LeftButton")
    Check(lfg.shown and not lfgState.restore.shown and lfg.scale == scale,
        "Forever LFG window did not restore with its saved scale")
    combat = true
    lfgState.titleDrag.scripts.OnDragStart(lfgState.titleDrag)
    lfgState.grip.scripts.OnMouseDown(lfgState.grip, "LeftButton")
    Check(lfg.moving and lfgState.grip.scripts.OnUpdate and lfg.scale == scale,
        "safe Forever geometry controls were disabled in combat")
    lfgState.grip.scripts.OnMouseUp(lfgState.grip)
    lfgState.titleDrag.scripts.OnDragStop(lfgState.titleDrag)
    combat = false
    lfgState.minimize.scripts.OnClick(lfgState.minimize)
    combat = true
    lfg:Show() -- Native secure code can reopen a panel during combat.
    Check(not lfgState.minimized and not lfgState.restore.shown,
        "native combat reopen left both the LFG window and its restore tab visible")
    combat = false
    NS.WindowControls.DisableOwner(owner)
    lfg:Hide()
    lfg:Show()
    Check(not lfgState.titleDrag.shown and not lfgState.grip.shown and not lfgState.minimize.shown
        and lfg.scale == 1, "disabled Forever owner left controls or custom scale active")
    Check(NS.WindowControls.Attach(lfg, owner) and lfg.scale == scale
        and NS.WindowControls.states[lfg] == lfgState, "Forever re-enable lost stored scale or duplicated controls")
    lfg.protected = true
    NS.WindowControls.Refresh()
    Check(not lfgState.titleDrag.shown and not lfgState.grip.shown,
        "protected LFG container kept geometry controls")
    lfg.protected = false
    NS.WindowControls.DisableOwner(owner)
    NS.Client.isForever = previousForever
end

-- WorldMap's root can use LOW while BorderFrame and QuestLog stay HIGH
-- (Blizzard_WorldMap.xml / AttachQuestLog). Own controls must follow the
-- visible border, and the grip must leave the native scrollbar arrow clear.
do
    local previousForever = NS.Client.isForever
    UIPanelWindows.WorldMapFrame = { area = "left", pushable = 0 }
    for _, flavor in ipairs({ "Retail", "Forever" }) do
        NS.Client.isForever = flavor == "Forever"
        local map = Frame("WorldMapFrame", UIParent)
        map.width, map.height = 1035, 534
        map:SetFrameStrata("LOW")
        map.BorderFrame = Frame(nil, map)
        map.BorderFrame:SetFrameStrata("HIGH")
        map.BorderFrame:SetFrameLevel(80)
        map.BorderFrame.NineSlice = Frame(nil, map.BorderFrame)
        map.BorderFrame.NineSlice:SetFrameLevel(180)
        map.QuestLog = Frame("QuestMapFrame", map)
        map.QuestLog:SetFrameStrata("HIGH")
        map.QuestLog:SetFrameLevel(100)
        local owner = "worldMap:" .. flavor
        Check(NS.WindowControls.Attach(map, owner), flavor .. " map did not attach")
        local controls = NS.WindowControls.states[map]
        for _, control in ipairs({ controls.grip, controls.titleDrag }) do
            Check(control:GetFrameStrata() == "HIGH"
                and control:GetFrameLevel() > map.BorderFrame.NineSlice:GetFrameLevel(),
                flavor .. " map control is behind native map/quest chrome")
        end
        Check(controls.grip.point[1] == "BOTTOMLEFT" and controls.grip.point[2] == map
            and controls.grip.point[3] == "BOTTOMRIGHT" and controls.grip.point[4] > 0
            and controls.grip.point[5] >= 0, flavor .. " map grip overlaps the native quest scrollbar or falls below the screen")
        -- Native UpdateMaximizedSize can put the root bottom at screen y=0.
        -- Resolve the vertical anchor to prove the complete grip remains visible.
        local gripBottom = controls.grip.point[5]
        if controls.grip.point[1] == "TOPLEFT" then gripBottom = gripBottom - controls.grip.height end
        Check(gripBottom >= 0 and gripBottom + controls.grip.height <= UIParent.height,
            flavor .. " maximized map grip is outside the screen")
        Check(controls.grip.clamped == true,
            flavor .. " map grip can disappear after moving the root to the right screen edge")
        Check(controls.grip.surfaceSpec and controls.grip.surfaceSpec.role == "button"
            and controls.grip.surfaceSpec.radius == 4 and not controls.grip.normalTexture,
            flavor .. " map grip kept the old unframed artwork")
        Check(controls.grip.lines and #controls.grip.lines == 2
            and controls.grip.lines[1].thickness == 1 and controls.grip.lines[2].color[4] == 0.8,
            flavor .. " map grip lacks the crisp themed corner icon")
        NS.WindowControlChrome.StyleGrip(controls.grip)
        Check(#controls.grip.lines == 2, flavor .. " map grip style duplicated its icon")
        NS.DB.windowControls.positions.WorldMapFrame = { x = UIParent.width, y = -100 }
        NS.WindowControls.Refresh()
        Check(map.point[4] + map.width + 21 <= UIParent.width,
            flavor .. " saved map position clamps its grip over the native scrollbar")
        NS.DB.windowControls.positions.WorldMapFrame = nil
        NS.WindowControls.Refresh()
        cursorX, cursorY = 500, 500
        controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
        cursorX, cursorY = 700, 400
        controls.grip.scripts.OnUpdate(controls.grip)
        controls.grip.scripts.OnMouseUp(controls.grip)
        local scale = map.scale
        Check(scale > 1 and NS.DB.windowControls.scales.WorldMapFrame == scale
            and map.BorderFrame.scale == 1 and map.QuestLog.scale == 1
            and map.width == 1035 and map.height == 534 and not controls.grip.scripts.OnUpdate,
            flavor .. " map grip did not scale the root and retain native geometry")
        map:SetScale(1) -- Native panel fit before a reopen.
        map:Hide()
        map:Show()
        Check(map.scale == scale and controls.grip:GetFrameStrata() == "HIGH",
            flavor .. " map reopen lost scale or control strata")
        map.BorderFrame.NineSlice:SetFrameLevel(250)
        NS.WindowControls.Refresh()
        Check(controls.grip:GetFrameLevel() > 250 and controls.titleDrag:GetFrameLevel() > 250,
            flavor .. " map controls did not follow refreshed border levels")
        local previousColor = NS.Theme.GetColor
        NS.Theme.GetColor = function() return 0.9, 0.8, 0.7, 0.5 end
        NS.WindowControls:OnThemeChanged("color", "text")
        NextFrame()
        Check(controls.grip.lines[1].color[1] == 0.9 and controls.grip.lines[2].color[4] == 0.4,
            flavor .. " map grip icon retained its old palette")
        NS.Theme.GetColor = previousColor
        NS.WindowControls:OnThemeChanged("color", "text")
        NextFrame()
        combatEdge = true
        controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
        Check(controls.grip.scripts.OnUpdate and map.scale == scale,
            flavor .. " safe map grip failed at the combat edge")
        controls.grip.scripts.OnMouseUp(controls.grip)
        combatEdge = false
        NS.WindowControls.DisableOwner(owner)
        Check(not controls.grip.shown and not controls.titleDrag.shown and map.scale == 1,
            flavor .. " map owner release left controls or custom scale")
        NS.DB.windowControls.scales.WorldMapFrame = nil
    end
    NS.Client.isForever = previousForever
    UIPanelWindows.WorldMapFrame = nil
end

-- The map gets the Windows caption too: cells on its border (above the map
-- root's strata), a drawn cell over Blizzard's size toggle, our minimize.
do
    UIPanelWindows.WorldMapFrame = { area = "left", pushable = 0 }
    local map = Frame("WorldMapFrame", UIParent)
    map.width, map.height = 1035, 534
    map:SetFrameStrata("LOW")
    local border = Frame(nil, map)
    map.BorderFrame = border
    border:SetFrameStrata("HIGH")
    local close = Frame(nil, border, "Button")
    border.CloseButton = close
    close.left, close.top, close.width, close.height = 1111, 800, 24, 24
    function close:GetEffectiveScale() return map:GetEffectiveScale() end
    local toggle = Frame(nil, border)
    toggle.MaximizeButton, toggle.MinimizeButton = Frame(nil, toggle, "Button"), Frame(nil, toggle, "Button")
    toggle.MinimizeButton.shown = false
    border.MaximizeMinimizeFrame = toggle
    -- Blizzard's art regions and the corner socket that frames its buttons.
    local function Art()
        local region = { alpha = 1 }
        function region:GetAlpha() return self.alpha end
        function region:SetAlpha(value) self.alpha = value end
        return region
    end
    local art, corner = Art(), Art()
    function close:GetRegions() return art end
    map.NineSlice = { TopRightCorner = corner }
    function map:GetRight() return self.left + self.width end
    local yielded, actions = {}, NS.WindowActionSkin
    NS.WindowActionSkin = { Yield = function(button, yield) yielded[button] = yield end }
    Check(NS.WindowControls.Attach(map, "map-caption"), "the map caption did not attach")
    Check(yielded[close] and yielded[toggle.MaximizeButton] and yielded[toggle.MinimizeButton],
        "Blizzard's caption buttons kept the old action skin under the cells")
    Check(art.alpha == 0 and corner.alpha == 0 and NS.WindowControlChrome.IsFaded(close),
        "Blizzard's caption art or its corner socket shows under the cells")
    -- Guild, the AddOn list and Settings show Blizzard's buttons again while
    -- they open, past any alpha write: the next frame of the opening fades
    -- them again, and says so once in chat.
    Check(watcher.shown, "the opening window is not looked at")
    close.alpha, art.alpha = 1, 1
    Watch(0.02)
    Check(close.alpha == 0 and art.alpha == 0, "Blizzard's X stayed visible after the window opened")
    local function Reports()
        local found = {}
        for _, message in ipairs(printed) do
            if message:find("caption check: WorldMapFrame", 1, true) then found[#found + 1] = message end
        end
        return found
    end
    Check(#Reports() == 1 and Reports()[1]:find("WorldMapFrame 0.02s, X alpha 1.00, faded true", 1, true),
        "the opening did not report Blizzard's X under the cells")
    -- Under the pointer it fades at once, without a second report.
    close.alpha = 1
    for _, enter in ipairs(close.hooks.OnEnter) do enter(close) end
    Check(close.alpha == 0 and #Reports() == 1, "Blizzard's X stayed visible under the pointer")
    -- Back without its fade (the caption let it go) under a shown cell: faded too.
    local mapState = NS.WindowControls.states[map]
    NS.WindowControlChrome.HideCaption(mapState)
    mapState.closeCell:Show()
    Check(close.alpha == 1, "the caption did not let Blizzard's X go")
    Watch(0.02)
    Check(close.alpha == 0 and NS.WindowControlChrome.IsFaded(close), "Blizzard's X came back without its fade")
    -- Three seconds on, the opening is over: nothing looks any more.
    Watch(3)
    Check(not watcher.shown, "the look outlived the opening")
    art:SetAlpha(1)
    Check(art.alpha == 0, "an art region of Blizzard's X came back under the cells")
    local state = NS.WindowControls.states[map]
    -- The caption is laid out again once the window settled (next frame).
    close.top = 790
    NextFrame()
    Check(state.closeCell.point[5] == -10, "the caption did not follow the window's settled layout")
    close.top = 800
    NextFrame()
    Check(state.closeCell and state.closeCell.shown and state.closeCell.parent == border
        and state.toggleCell and state.toggleCell.shown and state.minimize and state.minimize.shown
        and state.minimize.parent == border and state.maximize and not state.maximize.shown,
        "the map lacks the Windows caption on its border")
    Check(toggle.alpha == 0 and close.alpha == 0, "the map shows Blizzard's caption art under the cells")
    -- A later alpha write (another skin pass) must not bring the old X back.
    close:SetAlpha(1)
    Check(close.alpha == 0, "Blizzard's X came back under the drawn cells")
    -- In combat the size toggle can read as protected: it stays faded under its cell.
    _G.combatEdge, toggle.protected = true, true
    NS.WindowControlChrome.ShowCaption(state, state.captionLevel)
    Check(state.toggleCell.shown and toggle.alpha == 0, "combat dropped the size toggle's cell")
    _G.combatEdge, toggle.protected, combatJobs["windowControls:captions"] = false, nil, nil
    NS.WindowControlChrome.ShowCaption(state, state.captionLevel)
    -- A layout read as secret in combat keeps the cells: the toggle's cell
    -- comes and goes with Blizzard's toggle, which stays faded.
    local secretWidth, mapWidth = {}, map.GetWidth
    secretValues[secretWidth] = true
    function map:GetWidth() return secretWidth end
    _G.combatEdge = true
    toggle:Hide()
    Check(not state.toggleCell.shown and state.closeCell.shown, "combat kept the cell of a hidden size toggle")
    toggle:Show()
    Check(state.toggleCell.shown and toggle.alpha == 0, "combat lost the cell of the returning size toggle")
    _G.combatEdge, map.GetWidth = false, mapWidth
    combatJobs[state.replayKey], combatJobs["windowControls:captions"] = nil, nil
    NS.WindowControlChrome.ShowCaption(state, state.captionLevel)
    NS.WindowControls.DisableOwner("map-caption")
    Check(close.alpha == 1 and toggle.alpha == 1 and not state.closeCell.shown, "releasing the map left its caption")
    close:SetAlpha(.5)
    Check(close.alpha == .5 and yielded[close] == false and yielded[toggle.MinimizeButton] == false,
        "a released X stayed under the caption's alpha guard or without its skin")
    Check(art.alpha == 1 and corner.alpha == 1 and not NS.WindowControlChrome.IsFaded(close),
        "releasing the map left Blizzard's caption art or its socket faded")
    NS.WindowActionSkin = actions
    UIPanelWindows.WorldMapFrame = nil
end

-- The caption is drawn once, when the window is attached, closed windows
-- too: a window first opened in combat has it already.
do
    local list = Frame("AddonList", UIParent)
    local close = Frame(nil, list, "Button")
    list.CloseButton, list.shown = close, false
    close.left, close.top, close.width, close.height = 676, 800, 24, 24
    local state = NS.WindowControls.Attach(list, "drawn-once") and NS.WindowControls.states[list]
    Check(state and state.closeCell and state.closeCell.shown and close.alpha == 0,
        "a closed window got no caption before it opened")
    NS.WindowControls.DisableOwner("drawn-once")
end

-- A window whose geometry waits for combat (protected there) still draws
-- its caption as it opens.
do
    local list = Frame("AddonList", UIParent)
    local close = Frame(nil, list, "Button")
    list.CloseButton, list.shown, close.shown = close, false, false
    close.left, close.top, close.width, close.height = 676, 800, 24, 24
    local state = NS.WindowControls.Attach(list, "combat-open") and NS.WindowControls.states[list]
    Check(state and not state.closeCell, "a window without its X got a caption")
    close.shown, list.protected, _G.combatEdge = true, true, true
    list:Show()
    Check(state.closeCell and state.closeCell.shown and close.alpha == 0,
        "a window opened in combat showed Blizzard's buttons instead of its caption")
    combatJobs[state.replayKey], combatJobs["windowControls:captions"] = nil, nil
    list.protected, _G.combatEdge = nil, false
    NS.WindowControls.DisableOwner("combat-open")
end

-- A window opening in combat gets its caption, but no look on every frame.
-- Once shown, combat keeps the caption as it is.
do
    local list = Frame("AddonList", UIParent)
    local close = Frame(nil, list, "Button")
    list.CloseButton = close
    close.left, close.top, close.width, close.height = 676, 800, 24, 24
    _G.combatEdge = true
    local state = NS.WindowControls.Attach(list, "combat-caption") and NS.WindowControls.states[list]
    Check(state and state.closeCell, "an unprotected window opened in combat lost its caption")
    Check(not watcher.shown, "a window opened in combat started a look on every frame")
    -- The window's width reads as secret (a protected window's layout in
    -- combat) and Blizzard writes the alpha of its X, now protected: the cells
    -- stay, the X stays faded, and the window is laid out again after combat.
    local secretWidth, width = {}, list.GetWidth
    secretValues[secretWidth] = true
    function list:GetWidth() return secretWidth end
    close.protected = true
    NS.WindowControlChrome.ShowCaption(state, state.captionLevel)
    close:SetAlpha(1)
    Check(state.closeCell:IsShown() and close.alpha == 0, "combat took the caption apart")
    Check(combatJobs[state.replayKey] == state.replayShow, "the caption is not laid out again after combat")
    combatJobs[state.replayKey], list.GetWidth, close.protected = nil, width, nil
    _G.combatEdge = false
    NS.WindowControls.DisableOwner("combat-caption")
end

-- Inspect skips the generic window adapter. Its dedicated, load-on-demand
-- adapter must still reach the real window controls after Blizzard loads it.
local inspectLoaded
NS.Client.IsAddOnLoaded = function() return false end
EventUtil = { ContinueOnAddOnLoaded = function(addon, callback)
    Check(addon == "Blizzard_InspectUI", "Inspect waited for the wrong addon")
    inspectLoaded = callback
end }
NS.Registry = NS.Registry or { AddListener = function() end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/AdapterKit.lua"))("MSUF_Suite_Skin", NS)
NS.GenericWindows = { IsCategoryEnabled = function() return true end }
NS.Surface = {
    Attach = function() return true end,
    Ensure = function() return true end,
    SetVisible = function() end,
}
NS.Cosmetics = { FadeNineSlice = function() end, RestoreOwner = function() end }
NS.CharacterDetails = { Apply = function() end, Disable = function() end }
NS.CombatGate = { Cancel = function() end }
PanelTemplates_GetSelectedTab = function() return 1 end
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/PaperDollChrome.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/InspectPanel.lua"))("MSUF_Suite_Skin", NS)
local inspectApplied, inspectReason = NS.InspectPanel.Apply("blizzardWindows")
Check(inspectApplied and inspectReason == "waiting" and inspectLoaded,
    "Inspect did not wait for the native panel")
InspectFrame = Frame("InspectFrame", UIParent)
InspectFrame.width, InspectFrame.height = 338, 424
UIPanelWindows.InspectFrame = { area = "left", pushable = 0 }
inspectLoaded()
local inspectState = NS.WindowControls.states[InspectFrame]
Check(inspectState and inspectState.grip and inspectState.titleDrag
    and not inspectState.minimize and not inspectState.restore,
    "the dedicated Inspect adapter omitted scaling or added destructive minimize")
cursorX, cursorY = 500, 500
inspectState.grip.scripts.OnMouseDown(inspectState.grip, "LeftButton")
cursorX, cursorY = 650, 400
inspectState.grip.scripts.OnUpdate(inspectState.grip)
inspectState.grip.scripts.OnMouseUp(inspectState.grip)
local inspectScale = InspectFrame.scale
Check(inspectScale > 1 and NS.DB.windowControls.scales.InspectFrame == inspectScale
    and inspectState.grip.scripts.OnUpdate == nil,
    "Inspect could not enlarge and save its scale without a permanent update")
InspectFrame:Hide()
InspectFrame:Show()
NS.InspectPanel.Apply("blizzardWindows")
Check(InspectFrame.scale == inspectScale and NS.WindowControls.states[InspectFrame] == inspectState,
    "reopening Inspect lost its scale or duplicated its controls")
NS.InspectPanel.Disable("blizzardWindows")
NS.WindowControls.DisableOwner("blizzardWindows")
Check(not inspectState.grip.shown and not inspectState.titleDrag.shown,
    "disabling the Blizzard window owner left Inspect controls active")

-- Surface keeps a reference to each spec: the contract that callers own it
-- and share or rewrite it only as documented is written next to Attach.
local surfaceFile = assert(io.open(root .. "/MSUF_Suite_Skin/Rendering/Surface.lua", "rb"))
local surfaceSource = surfaceFile:read("*a")
surfaceFile:close()
Check(surfaceSource:find("A spec is caller-owned and read-only here", 1, true)
    and surfaceSource:find("Surface never writes to a spec", 1, true),
    "Surface.Attach does not document who owns a surface spec")
-- Forever 1.60.1.70291 loads PetStableFrame and LegacySystemFrame. Use the
-- real catalog: the normal geometry fixture's small stub cannot prove that
-- their load-on-demand roots ever reach WindowControls in the client.
do
    local previousCatalog, previousClient = NS.BlizzardCatalog, NS.Client
    NS.Client = { isForever = false, IsGamepadUI = function() return false end }
    assert(loadfile(arg[4] or root .. "/MSUF_Suite_Skin/Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    Check(NS.BlizzardCatalog.FindByFrame("StableFrame") ~= nil
        and not NS.BlizzardCatalog.FindByFrame("PetStableFrame")
        and not NS.BlizzardCatalog.FindByFrame("LegacySystemFrame"),
        "Forever-only windows changed the Retail catalog")
    for _, name in ipairs({ "PetStableFrame", "LegacySystemFrame" }) do
        UIPanelWindows[name] = { area = "left", pushable = 1 }
        Check(not NS.WindowControls.Attach(Frame(name, UIParent), "retail"), name .. " gained controls on Retail")
        UIPanelWindows[name] = nil
    end
    local gamepad = false
    NS.Client = { isForever = true, IsGamepadUI = function() return gamepad end }
    assert(loadfile(arg[4] or root .. "/MSUF_Suite_Skin/Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    Check(NS.BlizzardCatalog.glass.valid, "Forever catalog has an unclassified window")
    for _, name in ipairs({ "PetStableFrame", "LegacySystemFrame" }) do
        local entry = NS.BlizzardCatalog.FindByFrame(name)
        Check(entry and entry.addon == (name == "PetStableFrame" and "Blizzard_StableUI" or "Blizzard_LegacySystem"),
            name .. " is absent from its native addon catalog")
        local panel = Frame(name, UIParent)
        panel.width, panel.height = 384, 512
        if name == "LegacySystemFrame" then panel.width, panel.height = 920, 575 end
        panel.NineSlice = Frame(nil, panel)
        panel.NineSlice:SetFrameLevel(500)
        panel.CloseButton = Frame(name .. "CloseButton", panel, "Button")
        panel.CloseButton:SetFrameLevel(510)
        panel.CloseButton.anchorName = "TOPRIGHT"
        local nativeClick = function() HideUIPanel(panel) end
        panel.CloseButton.scripts.OnClick = nativeClick
        UIPanelWindows[name] = { area = "left", pushable = 1, allowOtherPanels = 1 }
        local owner = "contract:" .. name
        Check(NS.WindowControls.Attach(panel, owner), name .. " did not attach")
        local controls = NS.WindowControls.states[panel]
        Check(controls.titleDrag:GetFrameLevel() > 500 and controls.grip:GetFrameLevel() > 500,
            name .. " geometry controls are behind native portrait chrome")
        Check(panel.CloseButton.scripts.OnClick == nativeClick and panel.CloseButton:GetFrameLevel() == 510,
            name .. " changed the native X script or frame level")
        if name == "LegacySystemFrame" then
            Check(controls.minimize and controls.restore and controls.minimize:GetFrameLevel() > 500,
                "Legacy minimize/restore is missing or behind its portrait chrome")
            Check(controls.minimize.point[2] == panel.CloseButton, "Legacy minimize misses the native X anchor")
            controls.minimize.scripts.OnClick(controls.minimize)
            Check(not panel.shown and controls.restore.shown, "Legacy window did not minimize")
            controls.restore.scripts.OnClick(controls.restore, "LeftButton")
            Check(panel.shown and not controls.restore.shown, "Legacy window did not restore")
        else
            Check(not controls.minimize and not controls.restore, "stable gained an NPC-closing minimize")
        end
        panel.NineSlice:SetFrameLevel(900)
        panel:Hide()
        panel:Show()
        Check(controls.titleDrag:GetFrameLevel() > 900 and controls.grip:GetFrameLevel() > 900
            and (not controls.minimize or controls.minimize:GetFrameLevel() > 900),
            name .. " controls did not follow native levels on reopen")
        panel.CloseButton:Hide() -- Blizzard's InitializeGamepad hides its X.
        gamepad = true
        NS.WindowControls.Refresh()
        Check(not panel.CloseButton.shown and (not controls.minimize or not controls.minimize.shown),
            name .. " forced mouse-only window buttons into Gamepad UI")
        gamepad = false
        NS.WindowControls.Refresh()
        Check(not panel.CloseButton.shown, name .. " took ownership of native close visibility")
        combatEdge = true
        controls.titleDrag.scripts.OnDragStart(controls.titleDrag)
        controls.grip.scripts.OnMouseDown(controls.grip, "LeftButton")
        Check(panel.moving and controls.grip.scripts.OnUpdate, name .. " lost safe controls at combat edge")
        controls.grip.scripts.OnMouseUp(controls.grip)
        controls.titleDrag.scripts.OnDragStop(controls.titleDrag)
        combatEdge = false
        NS.WindowControls.DisableOwner(owner)
        Check(not controls.titleDrag.shown and not controls.grip.shown
            and (not controls.minimize or not controls.minimize.shown), name .. " left disabled controls visible")
        panel.CloseButton.scripts.OnClick(panel.CloseButton)
        Check(not panel.shown, name .. " lost its native close action")
        panel.explicitProtected = true
        Check(not NS.WindowControls.Attach(panel, owner), name .. " bypassed explicit protection")
        UIPanelWindows[name] = nil
    end
    NS.BlizzardCatalog, NS.Client = previousCatalog, previousClient
end

do
    local panel = Frame("SettingsPanel", UIParent)
    local close = Frame(nil, panel, "Button")
    close.anchorName, close.left, close.top, close.height = "TOPRIGHT", 668, 803, 26
    panel.ClosePanelButton = close
    local nativeClose = function() panel:Hide() end
    close.scripts.OnClick = nativeClose
    close.SetPoint = function() error("the caption moved Blizzard's close button") end
    local originalScale = 0.8
    panel:SetScale(originalScale)
    function close:GetEffectiveScale() return panel:GetEffectiveScale() end
    local title = { GetStringWidth = function() return 250 end, GetRight = function() return 700 end,
        GetCenter = function() return 400 end, GetJustifyH = function() return "CENTER" end }
    function panel:GetTitleText() return title end
    local neighbor = Frame(nil, panel, "Button")
    neighbor.left, neighbor.top = 592, 798
    function neighbor:GetRight() return 610 end
    function neighbor:GetBottom() return 776 end
    function neighbor:GetEffectiveScale() return panel:GetEffectiveScale() end
    function panel:GetChildren() return close, neighbor end
    Check(NS.WindowControls.Attach(panel, "caption"), "could not attach the settings caption")
    local state = NS.WindowControls.states[panel]
    Check(state.maximize and state.maximize.shown and state.minimize.shown, "caption needs minimize, maximize and native close")
    -- One row of equal cells; the X cell is the part of Blizzard's X inside
    -- the panel (this X overhangs the top edge), and Blizzard's art fades.
    local closeCell = state.closeCell
    Check(closeCell and closeCell.shown and closeCell.point[1] == "TOPRIGHT" and closeCell.point[2] == panel
        and closeCell.point[5] == -1 and close.alpha == 0, "the X cell is not inside the panel over the faded native X")
    Check(state.maximize.point[2] == closeCell and state.minimize.point[2] == state.maximize,
        "caption buttons are not in Windows order beside the native X")
    Check(state.maximize.width == 28 and state.minimize.width == 28 and closeCell.width == 28
        and state.maximize.height == 22 and closeCell.height == 22,
        "caption crossed a native neighbor or followed the native X past the top edge")
    local dash, square = state.minimize.textures, state.maximize.textures
    Check(#dash == 2 and #square == 5, "caption still relies on native Line regions")
    Check(dash[2].height == 1 and square[2].height == 1 and square[4].height == 1,
        "caption lost a horizontal one-pixel bar")
    Check(square[3].width == 1 and square[5].width == 1,
        "maximize lost a vertical one-pixel bar")
    -- Glyphs sit on whole screen pixels at any scale (here 1.25 units per
    -- pixel), also where a cell itself sits between pixels: no rotated bars,
    -- no edge on part of a pixel, and no engine rounding that could drop one.
    core.WindowCaption.PixelFactor = function() return 1 end
    for _, cell in ipairs({ closeCell, state.maximize, state.minimize }) do cell.left, cell.top = 100.3, 799.6 end
    NS.WindowControls.Refresh()
    local pixel = 1 / closeCell:GetEffectiveScale()
    local function Whole(value) local steps = value / pixel return math.abs(steps - math.floor(steps + .5)) < 1e-6 end
    for _, cell in ipairs({ closeCell, state.maximize, state.minimize }) do
        for index = 2, #cell.textures do
            local bar = cell.textures[index]
            Check(not bar.shown or not bar.angle and bar.snap == false and bar.point[1] == "TOPLEFT" and bar.point[2] == cell
                and Whole(cell.left + bar.point[4]) and Whole(cell.top + bar.point[5]) and Whole(bar.width) and Whole(bar.height),
                "a caption glyph bar left the screen pixel grid, kept engine rounding or was rotated")
        end
        cell.left, cell.top = 100, 800
    end
    Check(#closeCell.textures > 9, "the X is not a pixel staircase")
    core.WindowCaption.PixelFactor = function() return nil end
    -- A pane can raise Blizzard's X far above the window root (Forever's LFG:
    -- 510 over a root at 1): the cells stay on top of it.
    close.frameLevel = 510
    NS.WindowControls.Refresh()
    Check(closeCell:GetFrameLevel() > 510 and state.maximize:GetFrameLevel() > 510
        and state.minimize:GetFrameLevel() > 510, "the caption cells sit under Blizzard's raised X")
    close.frameLevel = nil
    NS.WindowControls.Refresh()
    GetUIPanelAttribute = function(frame, key)
        return frame == panel and key == "checkFitExtraHeight" and 60 or nil
    end
    state.maximize.scripts.OnClick(state.maximize)
    Check(state.fit and panel.point[1] == "CENTER" and panel.scale == (1080 - 16) / 560,
        "maximize did not fit the native window and its extra height to the screen")
    Check(square[9].shown, "maximized window needs the overlapping restore glyph")
    state.maximize.scripts.OnClick(state.maximize)
    Check(not state.fit and panel.scale == originalScale and not square[9].shown,
        "restore did not return the original scale and maximize glyph")
    state.maximize.scripts.OnClick(state.maximize)
    Check(state.fit and NS.WindowControls.ResetScales() and not state.fit and panel.scale == originalScale,
        "scale reset left a transient maximize state or restored its old scale")
    state.maximize.scripts.OnClick(state.maximize)
    neighbor.GetRight = function() return 635 end
    NS.WindowControls.Refresh()
    Check(not state.fit and not state.maximize.shown and state.minimize.shown,
        "the smaller caption lost a safe minimize action or stayed maximized without Restore")
    neighbor.GetRight = function() return 664 end
    NS.WindowControls.Refresh()
    Check(not state.maximize.shown and not state.minimize.shown and close.shown,
        "a tight title must keep the native X clear")
    Check(close.scripts.OnClick == nativeClose, "caption replaced the native close handler")
    NS.WindowControls.DisableOwner("caption")
end

print("Suite window controls: " .. checks .. " checks passed")
