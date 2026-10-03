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
    function frame:IsMouseOver() return false end
    function frame:GetFrameLevel() return self.frameLevel or 1 end
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
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetMovable(value) GeometryWrite(self); self.movable = value end
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
local NS = {
    -- The skin's locale table (Locales/Localization.lua) is ready before
    -- any of this runs; here every key reads as itself.
    L = setmetatable({}, { __index = function(_, key) return key end }),
    DB = { enabled = true, skins = { blizzardWindows = true },
        windowControls = { enabled = true, scales = {}, positions = {} } },
    Theme = { GetColor = function() return 0.2, 0.3, 0.4, 1 end },
    Registry = { AddListener = function() end, QueueJob = QueueJob },
    BlizzardCatalog = { FindByFrame = function(name)
        if name == "CharacterFrame" or name == "InspectFrame" then return { category = "character" } end
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
    Client = { isForever = false },
    -- Blizzard.lua's adapter registry, which always loads with this file.
    Adapters = { ApplyAll = function() adapterPasses = adapterPasses + 1 end },
}
-- The real guards and layout limits, not stubs.
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
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
state.grip.scripts.OnUpdate(state.grip)
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

-- Stored scales wait out combat and never touch a protected panel; a panel
-- that became protected loses its grip and title strip.
local scaleBefore = character.scale
NS.DB.windowControls.scales.CharacterFrame = 1.25
combat = true
NS.WindowControls.Refresh()
Check(character.scale == scaleBefore, "a profile refresh scaled a panel in combat")
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
Check(NS.WindowControls.states[spells].grip:GetFrameLevel() == spells:GetFrameLevel() + 20,
    "Forever layering changed the Retail spellbook controls")
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

-- Forever's portrait chrome is above its content pages: PlayerSpells sets
-- NineSlice to 5500; professions inherits the portrait level 500, above its
-- CraftingPage/BookPage at 100. Our grip must render above that chrome and
-- follow subsequent native frame-level changes without touching the pages.
do
    local previousSpellbook = _G.PlayerSpellsFrame
    NS.Client.isForever = true
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
            NS.Client.isForever = false
            Check(not NS.WindowControls.Attach(panel, "foreverBooks"), "Retail gained the protected spellbook exception")
            NS.Client.isForever = true
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
    Check(not lfg.moving and not lfgState.grip.scripts.OnUpdate and lfg.scale == scale,
        "Forever geometry changed during combat")
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

-- Inspect skips the generic window adapter. Its dedicated, load-on-demand
-- adapter must still reach the real window controls after Blizzard loads it.
local inspectLoaded
NS.Client.IsAddOnLoaded = function() return false end
EventUtil = { ContinueOnAddOnLoaded = function(addon, callback)
    Check(addon == "Blizzard_InspectUI", "Inspect waited for the wrong addon")
    inspectLoaded = callback
end }
NS.AdapterKit = { WeakSet = function() return setmetatable({}, { __mode = "k" }) end }
NS.GenericWindows = { IsCategoryEnabled = function() return true end }
NS.Surface = { Attach = function() return true end, SetVisible = function() end }
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
print("Suite window controls: " .. checks .. " checks passed")
