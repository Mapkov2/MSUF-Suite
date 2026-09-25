local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

local function Frame(name, parent, kind)
    local frame = {
        name = name, parent = parent, kind = kind or "Frame", shown = true,
        scale = 1, width = 600, height = 500, left = 100, top = 800,
        movable = true, scripts = {}, hooks = {},
    }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetObjectType() return self.kind end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return self.scale end
    function frame:GetEffectiveScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:IsResizable() return self.resizable end
    function frame:IsProtected() return self.protected or false, false end
    function frame:IsForbidden() return false end
    function frame:IsShown() return self.shown end
    function frame:IsMouseOver() return false end
    function frame:GetFrameLevel() return 1 end
    function frame:GetLeft() return self.left end
    function frame:GetTop() return self.top end
    function frame:GetNumPoints() return 1 end
    function frame:GetPoint() return self.anchorName or "CENTER", UIParent, "CENTER", 0, 0 end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetFrameLevel() end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetMovable(value) self.movable = value end
    function frame:IsMovable() return self.movable end
    function frame:RegisterForDrag() end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:RegisterForClicks() end
    function frame:SetButtonState() end
    function frame:SetNormalTexture() end
    function frame:SetHighlightTexture() end
    function frame:SetPushedTexture() end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
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
        return {
            SetAllPoints = function() end,
            SetColorTexture = function(self, ...) self.color = { ... } end,
        }
    end
    function frame:CreateFontString()
        return {
            SetPoint = function() end, SetJustifyH = function() end,
            SetText = function() end, SetTextColor = function() end,
        }
    end
    return frame
end

UIParent = Frame("UIParent")
UIParent.width, UIParent.height = 1920, 1080
GetCursorPosition = function() return _G.cursorX or 0, _G.cursorY or 0 end
InCombatLockdown = function() return _G.combat or false end
UIPanelWindows = { CharacterFrame = { area = "left" }, MerchantFrame = { area = "left" },
    ContainerFrameCombinedBags = { area = "left" } }
HideUIPanel = function(frame) frame:Hide() end
ShowUIPanel = function(frame) frame:Show() end
CreateFrame = function(kind, _, parent) return Frame(nil, parent, kind) end
local panelPositionHook
UpdateUIPanelPositions = function(frame)
    if frame then frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -90) end
    if panelPositionHook then panelPositionHook() end
end
hooksecurefunc = function(name, callback)
    assert(name == "UpdateUIPanelPositions")
    panelPositionHook = callback
end
local historyCalls = 0
MSUF2 = { RunWithHistory = function(_, _, fn)
    historyCalls = historyCalls + 1
    return fn()
end }

local NS = {
    DB = { enabled = true, skins = { blizzardWindows = true },
        windowControls = { enabled = true, scales = {}, positions = {} } },
    Theme = { GetColor = function() return 0.2, 0.3, 0.4, 1 end },
    Registry = { AddListener = function() end },
    BlizzardCatalog = { FindByFrame = function(name)
        if name == "CharacterFrame" then return { category = "character" } end
        if name == "MerchantFrame" then return { category = "npc" } end
        if name == "ContainerFrameCombinedBags" then return { category = "inventory" } end
    end },
    IsCombatLocked = function() return InCombatLockdown() end,
}
-- The real guards and layout limits, not stubs.
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))("MSUF_Suite_Skin", NS)

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
character:Hide()
character:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -90)
character:Show()
Check(character.point[4] == NS.DB.windowControls.positions.CharacterFrame.x / character.scale,
    "reopening the panel lost its saved position")
state.minimize.scripts.OnClick(state.minimize)
Check(not character.shown and state.restore.shown, "minimize did not leave a restore tab")
state.restore.scripts.OnClick(state.restore, "LeftButton")
Check(character.shown and not state.restore.shown, "restore did not reopen the panel")
Check(NS.WindowControls.SetEnabled(false) and not state.grip.shown
    and not state.minimize.shown and not state.titleDrag.shown,
    "disabling controls left live buttons")
Check(NS.WindowControls.SetEnabled(true) and state.grip.shown
    and state.minimize.shown and state.titleDrag.shown, "reenabling controls failed")
NS.DB.windowControls.scales.CharacterFrame = 1.11
NS.WindowControls:OnThemeChanged("profile")
Check(character.scale == 1.11, "profile restore did not reapply saved scale")
NS.DB.windowControls.positions.CharacterFrame = { x = 325, y = -140 }
NS.WindowControls:OnThemeChanged("profile")
Check(character.point[4] == 325 / character.scale,
    "profile restore did not reapply saved position")
NS.DB.windowControls.enabled = false
NS.WindowControls:OnThemeChanged("profile")
Check(not state.grip.shown and not state.minimize.shown,
    "history restore did not hide disabled controls")
NS.DB.windowControls.enabled = true
NS.WindowControls:OnThemeChanged("profile")

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
Check(not NS.WindowControls.Attach(other, "blizzardWindows"), "combat created frame controls")
combat = false
Check(NS.WindowControls.ResetScales() and character.scale == 1
    and NS.DB.windowControls.scales.CharacterFrame == nil, "reset failed")
Check(NS.WindowControls.ResetPositions()
    and NS.DB.windowControls.positions.CharacterFrame == nil
    and character.point[1] == "TOPLEFT" and character.point[4] == 30,
    "position reset did not return to Blizzard layout")

-- Forever's authored placement is a virtual default, not a saved position.
NS.Client = { isForever = true }
NS.DB.theme = { look = "foreverGlass" }
NS.WindowControls:OnThemeChanged("theme", "look")
Check(state.defaultPosition and character.point[4] == 0
    and NS.DB.windowControls.positions.CharacterFrame == nil,
    "Forever character default was not docked without saving a position")
Check(state.titleDrag.shown and state.titleDrag.mouseEnabled,
    "Forever character title is not available for mouse dragging")
UpdateUIPanelPositions(character)
Check(character.point[4] == 0, "Blizzard reflow displaced the Forever dock")
NS.DB.windowControls.positions.CharacterFrame = { x = 325, y = -140 }
NS.WindowControls:OnThemeChanged("profile")
Check(not state.defaultPosition and character.point[4] == 325,
    "saved position did not override the Forever dock")
Check(NS.WindowControls.ResetPositions() and state.defaultPosition
    and character.point[4] == 0,
    "reset did not restore the Forever default")
NS.DB.theme.look = "midnight"
NS.WindowControls:OnThemeChanged("theme", "look")
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
state.grip.scripts.OnUpdate(state.grip)
Check(state.grip.scripts.OnUpdate == nil and state.drag == nil,
    "hiding the panel left the scale drag running")
character:Show()
IsMouseButtonDown = nil
Check(state.grip.scripts.OnMouseDown == settingsGrip.scripts.OnMouseDown
    and state.titleDrag.scripts.OnDragStart == settingsTitle.scripts.OnDragStart,
    "window controls allocate script handlers per panel")
print("Suite window controls: " .. checks .. " checks passed")
