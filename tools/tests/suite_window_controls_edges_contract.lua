-- Window controls at the edges of Blizzard's panel manager, with the real
-- Safety, Defaults, DefaultsLooks, WindowControlChrome and WindowControls.
-- The panel manager model follows upstream/live (same in upstream/forever)
-- Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua: ShowUIPanel
-- refuses a left panel while a center panel without allowOtherPanels is open;
-- a center panel with centerFrameSkipAnchoring (the Game Menu,
-- Mainline/UIPanelWindows.lua) is never anchored by it; checkFit panels get
-- SetScale(1) before they show (FrameUtil.UpdateScaleForFitSpecific).
-- Usage: lua suite_window_controls_edges_contract.lua <Suite root>
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end

local combat = false
local function GeometryWrite(frame)
    assert(not (frame.protected and combat), "protected geometry write in combat on " .. tostring(frame.name))
end

local function Region(kind)
    local region = { kind = kind }
    function region:SetAllPoints() end
    function region:SetPoint() end
    function region:SetJustifyH() end
    function region:SetText(text) self.text = text end
    function region:SetColorTexture(...) self.color = { ... } end
    function region:SetTextColor(...) self.textColor = { ... } end
    return region
end

local function Frame(name, parent, kind)
    local frame = {
        name = name, parent = parent, kind = kind or "Frame", shown = false,
        scale = 1, width = 600, height = 500, left = 100, top = 800,
        movable = true, scripts = {}, hooks = {}, textures = {}, fontStrings = {},
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
    function frame:IsProtected() return self.protected or false, false end
    function frame:IsForbidden() return false end
    function frame:IsShown() return self.shown end
    function frame:IsMouseOver() return false end
    function frame:GetFrameLevel() return self.frameLevel or 1 end
    function frame:GetLeft() return self.left end
    function frame:GetTop() return self.top end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetPoint() if self.point then return unpack(self.point, 1, 5) end end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetHeight(height) self.height = height end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        GeometryWrite(self)
        self.point = { point, relativeTo, relativePoint, x, y }
    end
    function frame:ClearAllPoints() GeometryWrite(self); self.point = nil end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetMovable(value) self.movable = value end
    function frame:IsMovable() return self.movable end
    function frame:RegisterForDrag() end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:StartMoving() GeometryWrite(self); self.moving = true end
    function frame:StopMovingOrSizing() GeometryWrite(self); self.moving = false end
    function frame:RegisterForClicks() end
    function frame:SetButtonState() end
    function frame:SetNormalTexture() end
    function frame:SetHighlightTexture() end
    function frame:SetPushedTexture() end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        self.hooks[script] = self.hooks[script] or {}
        table.insert(self.hooks[script], callback)
    end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
    end
    function frame:CreateTexture()
        local texture = Region("Texture")
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function frame:CreateFontString()
        local text = Region("FontString")
        self.fontStrings[#self.fontStrings + 1] = text
        return text
    end
    return frame
end

UIParent = Frame("UIParent")
UIParent.width, UIParent.height, UIParent.shown = 1920, 1080, true
GetCursorPosition = function() return 0, 0 end
InCombatLockdown = function() return combat end
IsMouseButtonDown = function() return true end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function(kind, _, parent) return Frame(nil, parent, kind) end
MSUF2 = { RunWithHistory = function(_, _, commit) return commit() end }

------------------------------------------------------------------ panel manager
UIPanelWindows = {
    CharacterFrame = { area = "left", pushable = 3, whileDead = 1 },
    GameMenuFrame = { area = "center", pushable = 0, whileDead = 1, centerFrameSkipAnchoring = true },
    SettingsPanel = { area = "center", pushable = 0, whileDead = 1, checkFit = 1 },
}
local slots = {}
-- The delegate's own layout pass. Blizzard runs it inside the panel manager:
-- after a fit it does not go through the global UpdateUIPanelPositions.
local function LayoutPanels()
    local left = slots.left
    if left then
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", "UIParent", "TOPLEFT", 30 / left.scale, -90 / left.scale)
    end
    local center = slots.center
    if center and not UIPanelWindows[center.name].centerFrameSkipAnchoring then
        center:ClearAllPoints()
        center:SetPoint("TOP", "UIParent", "TOP", 0, -116 / center.scale)
    end
end
UpdateUIPanelPositions = function() LayoutPanels() end
local function Fit(frame)
    frame:SetScale(1)
    if frame.width > UIParent.width or frame.height > UIParent.height then
        frame:SetScale(math.min(UIParent.width / frame.width, UIParent.height / frame.height))
    end
end
ShowUIPanel = function(frame)
    local attributes = UIPanelWindows[frame.name]
    local center = slots.center
    if center and center ~= frame and attributes.area ~= "center" then return end
    if attributes.checkFit == 1 then Fit(frame) end
    slots[attributes.area] = frame
    if not attributes.centerFrameSkipAnchoring then UpdateUIPanelPositions(frame) end
    frame:Show()
end
HideUIPanel = function(frame)
    for key, panel in pairs(slots) do
        if panel == frame then slots[key] = nil end
    end
    frame:Hide()
end
-- UI_SCALE_CHANGED -> GameEvent.HandleUiScaleChanged -> this global.
UpdateScaleForFitForOpenPanels = function()
    for _, frame in pairs(slots) do Fit(frame) end
    LayoutPanels()
end
local hookCalls = {}
hooksecurefunc = function(name, post)
    assert(name == "UpdateUIPanelPositions" or name == "UpdateScaleForFitForOpenPanels",
        "unexpected secure hook " .. tostring(name))
    hookCalls[name] = (hookCalls[name] or 0) + 1
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        post(...)
    end
end

------------------------------------------------------------------ skin
local palette = { buttonFill = { 0.1, 0.1, 0.1, 0.9 }, popup = { 0.2, 0.2, 0.2, 0.95 }, text = { 0.9, 0.9, 0.9, 1 } }
local listeners, queued, deferred = {}, {}, {}
local function NextFrame()
    local jobs = queued
    queued = {}
    for _, job in ipairs(jobs) do job() end
end
local NS = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    DB = { enabled = true, skins = { blizzardWindows = true }, theme = { look = "midnight" },
        windowControls = { enabled = true, scales = {}, positions = {} } },
    Theme = { GetColor = function(role) return unpack(palette[role] or { 1, 1, 1, 1 }) end },
    Surface = { SkinOwnedButton = function() return true end },
    Registry = {
        AddListener = function(owner, callback) listeners[owner] = callback end,
        QueueJob = function(job)
            for _, pending in ipairs(queued) do if pending == job then return end end
            queued[#queued + 1] = job
        end,
    },
    BlizzardCatalog = { FindByFrame = function(name)
        if name == "CharacterFrame" then return { category = "character" } end
    end },
    IsCombatLocked = function() return combat end,
    CombatGate = { RunOrDefer = function(key, callback)
        if combat then deferred[key] = callback; return false end
        callback()
        return true
    end },
    Client = { isForever = false, IsGamepadUI = function() return false end },
    Adapters = { ApplyAll = function() end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Defaults.lua", "Core/DefaultsLooks.lua",
    "Rendering/WindowControlChrome.lua", "Rendering/WindowControls.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local WindowControls = NS.WindowControls
local function Notify(domain, key)
    for owner, callback in pairs(listeners) do callback(owner, domain, key) end
    NextFrame()
end
local function EndCombat()
    combat = false
    local jobs = deferred
    deferred = {}
    for _, job in pairs(jobs) do job() end
end
local function At(frame, point, x, y)
    local anchor = frame.point
    return anchor ~= nil and anchor[1] == point and anchor[4] == x and anchor[5] == y
end
local function Painted(region, role, field)
    local expected, actual = palette[role], region[field or "color"]
    if not actual then return false end
    for index = 1, 4 do
        if math.abs(actual[index] - expected[index]) > 1e-6 then return false end
    end
    return true
end

local character = Frame("CharacterFrame", UIParent)
character.CloseButton = Frame(nil, character, "Button")
ShowUIPanel(character)
Check(WindowControls.Attach(character, "blizzardWindows"), "the Character window was not attached")
local characterState = WindowControls.states[character]

------------------------------------------------------------------ CX-S2-01, first grip resize
-- Nothing stored yet this session: the first grip resize stores a scale, and a
-- UI scale change right after it (Blizzard fits every open panel) brings that
-- scale back.
Check(hookCalls.UpdateScaleForFitForOpenPanels == nil, "the UI scale hook was installed before anything was stored")
local cursorX = 0
GetCursorPosition = function() return cursorX, 0 end
local characterGrip = characterState.grip
characterGrip.scripts.OnMouseDown(characterGrip, "LeftButton")
cursorX = -240 -- ((x - 0) + (0 - 0)) / 2 over max(600, 500) pixels: 1 - 0.2.
characterGrip.scripts.OnUpdate(characterGrip)
characterGrip.scripts.OnMouseUp(characterGrip)
GetCursorPosition = function() return 0, 0 end
Check(character.scale == 0.8 and NS.DB.windowControls.scales.CharacterFrame == 0.8,
    "the first grip resize did not scale and store the Character window")
UpdateScaleForFitForOpenPanels()
Check(character.scale == 0.8, "a UI scale change reset the first grip resize of the session")
Check(WindowControls.ResetScales() and character.scale == 1, "the window scale reset failed")

------------------------------------------------------------------ R-S3-F5 / H-S3-03
-- The minimize button and the restore tab follow a look, colour or profile
-- change (DatabaseProfiles.ApplyActiveSettings notifies domain "profile").
local minimize, restore = characterState.minimize, characterState.restore
Check(Painted(minimize.textures[1], "buttonFill") and Painted(minimize.fontStrings[1], "text", "textColor")
    and Painted(restore.textures[1], "popup"), "the window controls were not painted from the theme")
palette.buttonFill, palette.popup, palette.text = { 0.3, 0.1, 0.1, 0.8 }, { 0.1, 0.3, 0.1, 0.7 }, { 1, 0.8, 0, 1 }
Notify("color", "popup")
Check(Painted(minimize.textures[1], "buttonFill") and Painted(minimize.fontStrings[1], "text", "textColor"),
    "a colour change did not repaint the minimize button")
Check(Painted(restore.textures[1], "popup"), "a colour change did not repaint the restore tab")
-- A profile with another look (Database.SetActiveProfile).
palette.buttonFill, palette.popup, palette.text = { 0.5, 0.5, 0.6, 0.9 }, { 0.6, 0.5, 0.5, 0.9 }, { 0.7, 0.7, 1, 1 }
Notify("profile", "activate")
Check(Painted(minimize.textures[1], "buttonFill") and Painted(minimize.fontStrings[1], "text", "textColor")
    and Painted(restore.textures[1], "popup"), "a profile switch left the window controls in the old colours")

------------------------------------------------------------------ R-S3-F1
-- A title drag that combat interrupts: the unprotected Character window stops
-- where the mouse released it (StopMovingOrSizing is restricted on protected
-- frames only, SimpleFrameAPIDocumentation.lua) and is saved there; only its
-- anchor waits for the end of combat.
local strip = characterState.titleDrag
strip.scripts.OnDragStart(strip)
Check(character.moving and characterState.moving, "the title drag did not start")
combat = true
character.left, character.top = 420, 840
strip.scripts.OnDragStop(strip)
Check(not character.moving and not characterState.moving,
    "a drag released in combat kept the window glued to the cursor")
local saved = NS.DB.windowControls.positions.CharacterFrame
Check(saved and saved.x == 420 and saved.y == 840 - UIParent.height,
    "a drag released in combat did not save where it was dropped")
character.left, character.top = 700, 300 -- The cursor wanders on during the fight.
EndCombat()
Check(At(character, "TOPLEFT", 420, 840 - UIParent.height) and NS.DB.windowControls.positions.CharacterFrame == saved,
    "after combat the window was not anchored where it was dropped")
UpdateUIPanelPositions(character)
Check(At(character, "TOPLEFT", 420, 840 - UIParent.height), "Blizzard's panel layout moved the dropped window")

------------------------------------------------------------------ H-S3-02
-- At login the hidden Game Menu is 260 x 1 (MainMenuFrameTemplate; its
-- buttons are laid out only once it shows). Its saved position still applies
-- on the first Esc of the session.
local menu = Frame("GameMenuFrame", UIParent)
menu.width, menu.height = 260, 1
menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
NS.DB.windowControls.positions.GameMenuFrame = { x = 40, y = -60 }
Check(WindowControls.Attach(menu, "gameMenu") and WindowControls.states[menu],
    "the Game Menu got no window controls at login")
ShowUIPanel(menu)
menu.height = 450
Check(At(menu, "TOPLEFT", 40, -60), "the first Esc of the session ignored the saved Game Menu position")
HideUIPanel(menu)

------------------------------------------------------------------ H-S3-01
-- Neither ShowUIPanel nor UpdateUIPanelPositions anchors the Game Menu: a reset,
-- or a profile without its position, puts it back on its own CENTER anchor.
local function AtNative(frame)
    return At(frame, "CENTER", 0, 0) and frame.point[2] == UIParent and frame.point[3] == "CENTER"
end
ShowUIPanel(menu)
Check(WindowControls.ResetPositions() and NS.DB.windowControls.positions.GameMenuFrame == nil,
    "the window position reset failed")
Check(AtNative(menu), "a position reset left the Game Menu where it was dragged")
HideUIPanel(menu)
ShowUIPanel(menu)
Check(AtNative(menu), "reopening the Game Menu after a reset moved it off its own anchor")
NS.DB.windowControls.positions.GameMenuFrame = { x = 40, y = -60 }
Notify("profile", "activate")
Check(At(menu, "TOPLEFT", 40, -60), "a profile with a Game Menu position did not place it")
NS.DB.windowControls.positions.GameMenuFrame = nil
Notify("profile", "activate")
Check(AtNative(menu), "a profile without a Game Menu position left it at the old one")
HideUIPanel(menu)

------------------------------------------------------------------ CX-S2-02
-- ShowUIPanel refuses the minimized Character window while the Game Menu is
-- open: its restore tab stays for another try.
minimize.scripts.OnClick(minimize)
Check(not character.shown and restore.shown and characterState.minimized, "the Character window did not minimize")
ShowUIPanel(menu)
restore.scripts.OnClick(restore, "LeftButton")
Check(not character.shown, "the model let a left panel open over the Game Menu")
Check(restore.shown and characterState.minimized, "a refused restore lost the window's restore tab")
HideUIPanel(menu)
restore.scripts.OnClick(restore, "LeftButton")
Check(character.shown and not restore.shown and not characterState.minimized,
    "the restore tab did not bring the window back once the Game Menu closed")

------------------------------------------------------------------ CX-S2-01
-- A UI scale change while Settings stays open: Blizzard fits every open panel
-- (UpdateScaleForFitForOpenPanels: SetScale(1), then its own layout pass, which
-- does not go through the global UpdateUIPanelPositions). The grip's scale and
-- the stored place come back after it.
local settings = Frame("SettingsPanel", UIParent)
settings.width, settings.height = 920, 724
settings.ClosePanelButton = Frame(nil, settings, "Button")
NS.DB.windowControls.scales.SettingsPanel = 0.8
NS.DB.windowControls.positions.SettingsPanel = { x = 300, y = -120 }
Check(WindowControls.Attach(settings, "settings"), "Settings got no window controls")
ShowUIPanel(settings)
Check(settings.scale == 0.8 and At(settings, "TOPLEFT", 300 / 0.8, -120 / 0.8),
    "opening Settings lost its stored scale or place")
UpdateScaleForFitForOpenPanels()
Check(settings.scale == 0.8, "a UI scale change left Settings at Blizzard's fit scale")
Check(At(settings, "TOPLEFT", 300 / 0.8, -120 / 0.8), "a UI scale change left Settings at Blizzard's place")
Check(hookCalls.UpdateScaleForFitForOpenPanels == 1, "the UI scale hook was installed more than once")
-- In combat the skin leaves Blizzard's fit alone, and puts its scale and
-- place back once combat ends.
combat = true
UpdateScaleForFitForOpenPanels()
Check(settings.scale == 1, "the skin rescaled a panel in combat")
EndCombat()
Check(settings.scale == 0.8 and At(settings, "TOPLEFT", 300 / 0.8, -120 / 0.8),
    "after a UI scale change in combat Settings kept Blizzard's fit scale")
HideUIPanel(settings)

Check(#reported == 0, "window controls reported errors: " .. table.concat(reported, "; "))
print("Suite window controls edges: " .. checks .. " checks passed")
