-- The caption's minimize and the restore tab never drive Blizzard's panel
-- manager from the skin's code.
--
-- WoW Forever 1.60.1 (upstream/forever 4cd0ab752): ShowUIPanel, HideUIPanel and
-- UpdateUIPanelPositions run the FramePositionDelegate's attribute handler, the
-- window's OnShow/OnHide and what they write inside the caller's call. From the
-- skin's minimize the world map's hide ran under MSUF_Suite_Skin's taint; the
-- next M then showed the map from tainted code and every quest pin's
-- SetPassThroughButtons (MapCanvasMixin:AcquirePin) was blocked. Minimize and
-- restore now click Blizzard's own X and opener button through one secure
-- delegate (WindowControlDelegate.lua); the skin's plain handlers refuse the map.
-- Usage: lua suite_window_controls_secure_caption_contract.lua <Suite root>
--        [WindowControls.lua] [WindowControlDelegate.lua] [WindowControlPolicy.lua] [WindowControlChrome.lua] [MinimizedWindows.lua]
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1):gsub('arg%[[35]%] or ', '') .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs, NextFrame = NextFrame }
]]
fixture = fixture:gsub('loadfile%(root %.%. "/MSUF_Suite_Skin/Rendering/WindowControlDelegate.lua"%)',
    'loadfile(arg[3] or root .. "/MSUF_Suite_Skin/Rendering/WindowControlDelegate.lua")')
fixture = fixture:gsub('loadfile%(root %.%. "/MSUF_Suite_Skin/Rendering/WindowControlPolicy.lua"%)',
    'loadfile(arg[4] or root .. "/MSUF_Suite_Skin/Rendering/WindowControlPolicy.lua")')
fixture = fixture:gsub('loadfile%(root %.%. "/MSUF_Suite_Skin/Rendering/WindowControlChrome.lua"%)',
    'loadfile(arg[5] or root .. "/MSUF_Suite_Skin/Rendering/WindowControlChrome.lua")')
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

local function Fire(frame, script, ...)
    if frame.scripts[script] then frame.scripts[script](frame, ...) end
    for _, hook in ipairs(frame.hooks[script] or {}) do hook(frame, ...) end
end

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    _G.combat, _G.combatEdge = false, false
    -- Blizzard's code runs at depth > 0: inside a secure click or a native pass.
    local blizzard, skinCalls, skinMapCalls = 0, {}, 0
    local function Blizzard(action, ...)
        blizzard = blizzard + 1
        action(...)
        blizzard = blizzard - 1
    end
    local H = assert(loadstring(fixture, "@window_controls_secure_caption_fixture"))()
    local NS, Frame = H.NS, H.Frame
    NS.Client.isForever = flavor == "Forever"
    NS.DB.theme = { look = "midnight" }
    NS.CombatGate.Cancel = function(key) H.jobs[key] = nil end
    for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
        local native = _G[name]
        _G[name] = function(...)
            if blizzard == 0 then skinCalls[#skinCalls + 1] = name end
            return native(...)
        end
    end
    -- SecureActionButtonTemplate's attributes; protected writes wait for combat's end.
    local createFrame = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        local frame = createFrame(kind, name, parent, template)
        frame.template, frame.attributes = template, {}
        function frame:SetAttribute(key, value)
            assert(not (self.template and InCombatLockdown()), "contract: a secure attribute was written in combat")
            self.attributes[key] = value
        end
        function frame:GetAttribute(key) return self.attributes[key] end
        function frame:GetNumPoints() return self.point and 1 or 0 end
        function frame:GetPoint() return unpack(self.point or {}) end
        function frame:UnregisterAllEvents() self.events = nil end
        function frame:SetAllPoints(target) self:SetPoint("TOPLEFT", target, "TOPLEFT") end
        local hide = frame.Hide
        function frame:Hide()
            local wasShown = self.shown
            hide(self)
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        return frame
    end
    local core, dataTexts = NS.SuiteCore(), { showMinimizedWindows = false }
    core.AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
    core.Suite.Config = function(id) assert(id == "dataTexts"); return dataTexts end
    assert(loadfile(arg[6] or root .. "/MSUF_Suite/Core/MinimizedWindows.lua"))("MSUF_Suite", core)
    local taskbar = core.MinimizedWindows
    RegisterStateDriver = function(frame, state, values) frame.stateDriver = { state, values } end
    assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))("MSUF_Suite_Skin", NS)
    local W = NS.WindowControls

    -- The client's secure click: PreClick, then SecureActionButton_OnClick clicks
    -- the target's own OnClick from secure code ("type1"/"clickbutton1" for the
    -- left button, nothing for the right), then PostClick.
    local function SecureClick(button, mouseButton)
        Fire(button, "PreClick", mouseButton)
        local suffix = mouseButton == "RightButton" and "2" or "1"
        if button:GetAttribute("type" .. suffix) == "click" then
            local target = button:GetAttribute("clickbutton" .. suffix)
            Blizzard(target.scripts.OnClick, target, mouseButton)
        end
        Fire(button, "PostClick", mouseButton)
    end
    local function Hover(cell)
        function cell:IsMouseOver() return not self.movedAway end
        Fire(cell, "OnEnter")
    end
    local function Delegate()
        for _, frame in ipairs(H.frames) do
            if frame.template == "SecureActionButtonTemplate" then return frame end
        end
    end

    -- WoW's world map: BorderFrame's X runs UIPanelCloseButton_OnClick ->
    -- onCloseCallback -> HideParentPanel -> HideUIPanel(WorldMapFrame); the
    -- minimap's zone text runs ToggleWorldMap (MinimapZoneTextButtonMixin).
    UIPanelWindows.WorldMapFrame = { area = "left", pushable = 0 }
    local map = Frame("WorldMapFrame", UIParent)
    _G.WorldMapFrame = map
    map.width, map.height = 1035, 534
    map.BorderFrame = Frame(nil, map)
    map.BorderFrame:SetFrameStrata("HIGH")
    local close = Frame(nil, map.BorderFrame, "Button")
    map.BorderFrame.CloseButton = close
    close.scripts.OnClick = function() HideUIPanel(map) end
    local mapShow, mapHide = map.Show, map.Hide
    function map:Show() if blizzard == 0 then skinMapCalls = skinMapCalls + 1 end return mapShow(self) end
    function map:Hide() if blizzard == 0 then skinMapCalls = skinMapCalls + 1 end return mapHide(self) end
    ToggleWorldMap = function()
        if map:IsShown() then HideUIPanel(map) else ShowUIPanel(map) end
    end
    local zoneText = Frame(nil, UIParent, "Button")
    function zoneText:IsEnabled() return true end
    zoneText.scripts.OnClick = function() ToggleWorldMap() end
    MinimapCluster = Frame("MinimapCluster", UIParent)
    MinimapCluster.ZoneTextButton = zoneText

    Check(W.Attach(map, "worldMap"), flavor .. ": the map did not attach")
    local state = W.states[map]
    Check(state.minimize and state.restore, flavor .. ": the map lost its minimize and restore tab")

    -- Minimize: the pointer on the cell lays the delegate over it, which clicks
    -- Blizzard's X. No window is its parent, and combat hides it.
    Hover(state.minimize)
    local delegate = Delegate()
    Check(delegate and delegate.shown and delegate.owner == state.minimize,
        flavor .. ": the minimize cell did not get the secure delegate")
    Check(delegate.parent == UIParent and delegate.stateDriver and delegate.stateDriver[1] == "visibility"
        and delegate.stateDriver[2] == "[combat] hide", flavor .. ": the delegate is not a combat-hidden UIParent button")
    Check(delegate:GetAttribute("type1") == "click" and delegate:GetAttribute("clickbutton1") == close,
        flavor .. ": minimize does not click Blizzard's X")
    SecureClick(delegate, "LeftButton")
    Check(not map.shown and state.minimized and state.restore.shown,
        flavor .. ": minimize through Blizzard's X left no restore tab")
    Check(not delegate.shown and delegate.owner == nil, flavor .. ": the delegate stayed after its click")

    -- Restore: the delegate over the tab clicks the map's own opener.
    Hover(state.restore)
    Check(delegate.shown and delegate.owner == state.restore and delegate:GetAttribute("clickbutton1") == zoneText,
        flavor .. ": the restore tab does not click Blizzard's map button")
    SecureClick(delegate, "LeftButton")
    Check(map.shown and not state.minimized and not state.restore.shown,
        flavor .. ": restore through Blizzard's map button failed")
    Check(#skinCalls == 0 and skinMapCalls == 0,
        flavor .. ": the skin drove the panel manager or the map itself: " .. table.concat(skinCalls, ", "))

    -- Clicks the delegate did not take (no hover) never move the map from here.
    state.minimize.scripts.OnClick(state.minimize)
    Check(map.shown and not state.minimized and #skinCalls == 0 and skinMapCalls == 0,
        flavor .. ": the skin's own minimize hid the map")
    Hover(state.minimize)
    SecureClick(delegate, "LeftButton")
    Check(not map.shown and state.restore.shown, flavor .. ": the second minimize failed")
    state.restore.scripts.OnClick(state.restore, "LeftButton")
    Check(not map.shown and state.restore.shown and #skinCalls == 0 and skinMapCalls == 0,
        flavor .. ": the skin's own restore showed the map")

    -- The tab still moves; a drag never clicks the opener. A right click lets
    -- the window go without opening it.
    Hover(state.restore)
    Fire(delegate, "OnDragStart")
    Check(state.restore.moving and delegate:GetAttribute("type1") == nil,
        flavor .. ": dragging the tab did not move it or would open the map")
    SecureClick(delegate, "LeftButton")
    Fire(delegate, "OnDragStop")
    Check(not map.shown and not state.restore.moving and not delegate.shown,
        flavor .. ": the tab drag opened the map or kept the delegate")
    Hover(state.restore)
    Fire(delegate, "OnDragStart")
    Fire(delegate, "OnLeave")
    Check(delegate.owner == state.restore and state.restore.moving,
        flavor .. ": leaving the proxy ended the tab drag before mouse release")
    Fire(delegate, "OnDragStop")
    Check(not map.shown and not state.restore.moving and not delegate.shown and state.restore.shown,
        flavor .. ": a drag without a click did not end on the tab")
    Hover(state.restore)
    SecureClick(delegate, "RightButton")
    Check(not map.shown and not state.minimized and not state.restore.shown,
        flavor .. ": a right click on the tab opened the map or kept the tab")
    Blizzard(ShowUIPanel, map)

    -- The map goes only while Blizzard's map button can bring it back.
    function zoneText:IsEnabled() return false end
    Hover(state.minimize)
    Check(not delegate.shown, flavor .. ": the map minimized without a secure way back")
    function zoneText:IsEnabled() return true end
    -- In combat and under the Gamepad UI the delegate stays away.
    _G.combat = true
    Hover(state.minimize)
    Check(not delegate.shown, flavor .. ": the delegate was laid over the cell in combat")
    _G.combat = false
    NS.Client.IsGamepadUI = function() return true end
    Hover(state.minimize)
    Check(not delegate.shown, flavor .. ": the delegate came under the Gamepad UI")
    NS.Client.IsGamepadUI = function() return false end

    -- A cell that hides under the pointer lets the delegate go.
    Hover(state.minimize)
    Check(delegate.shown, flavor .. ": the delegate did not come back")
    state.minimize:Hide()
    Check(not delegate.shown and delegate.owner == nil, flavor .. ": a hidden cell kept the delegate")
    state.minimize:Show()

    -- Settings have no reversible native click. Park the actual window and
    -- keep unsaved controls live. The taskbar reuses both kinds of restore tab.
    UIPanelWindows.SettingsPanel = { area = "center", checkFit = 1 }
    local plainSettings = Frame("SettingsPanel", UIParent)
    plainSettings.ClosePanelButton = Frame(nil, plainSettings, "Button")
    plainSettings.ClosePanelButton.scripts.OnClick = function() HideUIPanel(plainSettings) end
    Check(W.Attach(plainSettings, "plainSettings"), flavor .. ": Settings did not attach")
    local plain = W.states[plainSettings]
    Check(plain.minimize and plain.minimize.shown, flavor .. ": Settings lost minimize without a native opener")
    Hover(plain.minimize)
    Check(not delegate.shown, flavor .. ": Settings bound a native toggle without a restore target")
    plain.minimize.scripts.OnClick(plain.minimize)
    Check(plainSettings.shown and plain.minimized and plain.restore.shown and plainSettings.point[3] == "BOTTOMLEFT",
        flavor .. ": Settings did not keep its native session when minimized")
    plainSettings:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    H.NextFrame()
    Check(plainSettings.point[3] == "BOTTOMLEFT", flavor .. ": native layout unparked the Settings window")
    Hover(state.minimize)
    SecureClick(delegate, "LeftButton")
    local legacyMap, legacyPlain = state.restore.point, plain.restore.point
    Check(legacyMap[2] == UIParent and legacyPlain[2] == UIParent, "taskbar was enabled by default")
    dataTexts.showMinimizedWindows = true
    taskbar.Refresh()
    local strip = state.restore.point[2]
    Check(strip ~= UIParent and plain.restore.point[2] == strip and plain.restore.point[4] ~= state.restore.point[4],
        flavor .. ": the two restore buttons did not share the taskbar")
    Check(strip:IsShown() and strip.textures and strip.textures[1].color[1] > 0.8 and strip.mouseEnabled == false,
        flavor .. ": the taskbar has no visible light background or intercepts mouse input")
    local wideWidth, wideHeight = strip:GetWidth(), strip:GetHeight()
    Check(wideWidth > state.restore:GetWidth() + plain.restore:GetWidth() and wideHeight > state.restore:GetHeight(),
        "the taskbar background does not contain both buttons")
    function state.restore:GetLeft() return UIParent:GetWidth() / 2 + self.point[4] end
    Hover(state.restore)
    local hitX = delegate.point[4]
    local previousWidth = UIParent.width
    UIParent.width = 270
    strip.scripts.OnEvent(strip, "DISPLAY_SIZE_CHANGED")
    Check(plain.restore.point[5] ~= state.restore.point[5], "narrow taskbar did not wrap its rows")
    Check(strip:GetWidth() < wideWidth and strip:GetHeight() > wideHeight, "the background did not wrap with its buttons")
    Check(delegate.point[4] ~= hitX and delegate.point[4] == state.restore:GetLeft(),
        "the secure restore hit area stayed at its old position when the taskbar wrapped")
    local first, second = plain.restore, state.restore
    if first.point[5] > second.point[5] then first, second = second, first end
    dataTexts.minimizedWindowsPoint = 3
    taskbar.Refresh()
    Check(strip.point[1] == "TOPRIGHT" and strip.point[2] == UIParent and strip.point[3] == "TOPRIGHT"
        and strip.point[4] < 0 and strip.point[5] < 0, "the taskbar did not move to the top-right corner")
    Check(first.point[5] > second.point[5] and taskbar.IsDocked(state.restore),
        "moving the taskbar did not keep the entries or wrap them down from the top")
    dataTexts.minimizedWindowsPoint = 7
    taskbar.Refresh()
    Check(strip.point[1] == "BOTTOMLEFT" and strip.point[4] > 0 and strip.point[5] > 0 and first.point[5] < second.point[5],
        "the bottom-left taskbar did not wrap upwards")
    UIParent.width = previousWidth
    dataTexts.showMinimizedWindows = false
    taskbar.Refresh()
    Check(state.restore.point[2] == legacyMap[2] and state.restore.point[4] == legacyMap[4]
        and plain.restore.point[2] == legacyPlain[2] and plain.restore.point[5] == legacyPlain[5],
        "turning off the taskbar did not return the individual tabs")
    Check(not strip:IsShown() and not strip.events, "turning off the taskbar left its background or resize events active")
    dataTexts.showMinimizedWindows = true
    taskbar.Refresh()
    Hover(state.restore)
    SecureClick(delegate, "LeftButton")
    Check(map.shown and not state.restore.shown and not taskbar.IsDocked(state.restore),
        "the docked map entry did not restore or remove itself")
    Check(strip:IsShown() and strip:GetWidth() < wideWidth, "restoring one window did not compact the taskbar")
    plain.restore.scripts.OnClick(plain.restore, "LeftButton")
    Check(plainSettings.shown and not plain.restore.shown and plainSettings.point[3] == "CENTER"
        and not strip:IsShown() and not strip.events,
        "the docked Settings entry did not restore or stop taskbar updates")
    Check(#skinCalls == 0, flavor .. ": a Settings restore ran the panel manager from addon code")
    dataTexts.showMinimizedWindows = false
    W.DisableOwner("plainSettings")
    plainSettings:Hide()

    -- The overlay must cover the scaled minimize cell without protecting
    -- its window, even while hovering when a click or drag begins.
    UIPanelWindows.CollectionsJournal = { area = "left", checkFit = 1 }
    local findByFrame = NS.BlizzardCatalog.FindByFrame
    NS.BlizzardCatalog.FindByFrame = function(name)
        if name == "CollectionsJournal" then return { category = "collections" } end
        return findByFrame(name)
    end
    local settings = Frame("CollectionsJournal", UIParent)
    UIParent.scale, settings.strata, settings.scale = 0.8, "HIGH", 1.2
    local settingsClose = Frame(nil, settings, "Button")
    settingsClose.left, settingsClose.top, settingsClose.height = 668, 803, 26
    function settingsClose:GetEffectiveScale() return settings:GetEffectiveScale() end
    settingsClose.scripts.OnClick = function() HideUIPanel(settings) end
    settings.CloseButton = settingsClose
    -- CollectionsMicroButtonMixin:OnClick runs ToggleCollectionsJournal.
    local collections = Frame("CollectionsMicroButton", UIParent, "Button")
    _G.CollectionsMicroButton = collections
    function collections:IsEnabled() return true end
    collections.scripts.OnClick = function()
        if settings:IsShown() then HideUIPanel(settings) else ShowUIPanel(settings) end
    end
    Check(W.Attach(settings, "settings"), flavor .. ": Collections did not attach")
    local options = W.states[settings]
    local minimize = options.minimize
    function minimize:GetEffectiveScale() return settings:GetEffectiveScale() end
    local function IsProtected(frame)
        local anchor = delegate.point and delegate.point[2]
        while anchor do
            if anchor == frame then return true end
            anchor = anchor.parent
        end
        return false
    end
    settings.IsProtected, minimize.IsProtected = IsProtected, IsProtected
    Hover(minimize)
    Check(not settings:IsProtected() and not minimize:IsProtected(),
        flavor .. ": hovering minimize protected Collections")
    local ratio = settings:GetEffectiveScale() / UIParent:GetEffectiveScale()
    Check(delegate.point[1] == "TOPLEFT" and delegate.point[2] == UIParent and delegate.point[3] == "BOTTOMLEFT"
        and delegate.point[4] == minimize:GetLeft() * ratio and delegate.point[5] == minimize:GetTop() * ratio
        and delegate.width == minimize:GetWidth() * ratio and delegate.height == minimize:GetHeight() * ratio
        and delegate:GetFrameStrata() == "HIGH",
        flavor .. ": the secure delegate missed the scaled Collections minimize cell")
    minimize.left = minimize.left + 6
    W.Refresh()
    Check(delegate.shown and delegate.owner == minimize and delegate.point[4] == minimize:GetLeft() * ratio,
        flavor .. ": the hover hit area did not follow the native panel relayout")
    Fire(options.titleDrag, "OnDragStart")
    Check(settings.moving, flavor .. ": hovering minimize blocked Collections movement")
    Fire(options.titleDrag, "OnDragStop")
    Fire(options.grip, "OnMouseDown", "LeftButton")
    Check(options.drag, flavor .. ": hovering minimize blocked Collections scaling")
    Fire(options.grip, "OnMouseUp", "LeftButton")
    options.maximize.scripts.OnClick(options.maximize)
    Check(options.fit, flavor .. ": hovering minimize blocked Collections maximize")
    options.maximize.scripts.OnClick(options.maximize)
    minimize.movedAway = true
    SecureClick(delegate, "LeftButton")
    Check(settings.shown and not options.restore.shown and not delegate.shown,
        flavor .. ": an old proxy rectangle closed Collections after the cell moved")
    minimize.movedAway = nil
    Hover(minimize)
    SecureClick(delegate, "LeftButton")
    Check(not settings.shown and options.restore.shown,
        flavor .. ": hovering minimize blocked the Collections click")
    options.restore.scripts.OnClick(options.restore, "LeftButton")
    Check(not settings.shown and options.restore.shown, flavor .. ": the skin's own restore showed Collections")
    Hover(options.restore)
    SecureClick(delegate, "LeftButton")
    Check(settings.shown and not options.restore.shown, flavor .. ": Collections did not restore")
    Check(#skinCalls == 0, flavor .. ": Collections minimize or restore ran the skin's panel calls")
    Hover(minimize)
    _G.combat = true
    delegate:Hide()
    _G.combat = false
    local finishRelease = H.jobs["windowControls:releaseDelegate"]
    Check(finishRelease and not delegate.shown, flavor .. ": combat hide did not queue cleanup")
    H.jobs["windowControls:releaseDelegate"] = nil
    finishRelease()
    Check(not delegate.point and not delegate.owner and not delegate:GetAttribute("clickbutton1"),
        flavor .. ": the secure delegate kept its position or target after combat")
    UIParent.scale = 1

    -- The Character window: its X and CharacterMicroButton (ToggleCharacter).
    local character = Frame("CharacterFrame", UIParent)
    _G.CharacterFrame = character
    local characterPages = {
        PaperDollFrame = Frame(nil, character),
        ReputationFrame = Frame(nil, character),
        TokenFrame = Frame(nil, character),
    }
    function character:ShowSubFrame(name)
        for key, page in pairs(characterPages) do page:SetShown(key == name) end
        self.activeSubframe = name
    end
    character:ShowSubFrame("PaperDollFrame")
    local characterCloses, characterOpens = 0, 0
    character.CloseButton = Frame(nil, character, "Button")
    character.CloseButton.scripts.OnClick = function()
        characterCloses = characterCloses + 1
        HideUIPanel(character)
    end
    local micro = Frame("CharacterMicroButton", UIParent, "Button")
    function micro:IsEnabled() return true end
    micro.scripts.OnClick = function()
        if character:IsShown() and character.activeSubframe == "PaperDollFrame" then
            HideUIPanel(character)
        else
            characterOpens = characterOpens + 1
            character:ShowSubFrame("PaperDollFrame")
            if not character:IsShown() then ShowUIPanel(character) end
        end
    end
    CharacterMicroButton = micro
    Check(W.Attach(character, "blizzardWindows"), flavor .. ": the Character window did not attach")
    local hero = W.states[character]
    Hover(hero.minimize)
    Check(delegate:GetAttribute("clickbutton1") == character.CloseButton, flavor .. ": Character minimize skips its X")
    SecureClick(delegate, "LeftButton")
    Hover(hero.restore)
    Check(delegate:GetAttribute("clickbutton1") == micro, flavor .. ": Character restore skips its micro button")
    SecureClick(delegate, "LeftButton")
    Check(character.shown and not hero.restore.shown and #skinCalls == 0,
        flavor .. ": the Character window went through the skin's panel calls")

    -- The Suite's character panel draws its own minimize cell over the native
    -- window (MSUF_Suite_CharacterPanel): no HideUIPanel from addon code, the
    -- same secure delegate over that cell instead.
    local suiteCell = Frame(nil, UIParent, "Button")
    -- The panel's layout plan always carries its size (GearGeometry.lua).
    local plan = { width = character:GetWidth(), height = character:GetHeight() }
    Check(W.SuiteAction(character, plan, "minimize") == false and character.shown and #skinCalls == 0,
        flavor .. ": the Suite minimize hid the Character window from addon code")
    Check(W.SuiteAction(character, plan, "bindMinimize", suiteCell) == true,
        flavor .. ": the Suite minimize cell got no secure delegate")
    Hover(suiteCell)
    Check(delegate.shown and delegate.owner == suiteCell
        and delegate:GetAttribute("clickbutton1") == character.CloseButton,
        flavor .. ": the Suite minimize cell skips Blizzard's X")
    SecureClick(delegate, "LeftButton")
    Check(not character.shown and hero.restore.shown and hero.minimized and #skinCalls == 0,
        flavor .. ": the Suite minimize cell did not minimize through Blizzard's X")
    Hover(hero.restore)
    SecureClick(delegate, "LeftButton")
    Check(character.shown and not hero.restore.shown and #skinCalls == 0,
        flavor .. ": the Suite-minimized Character window did not come back through its micro button")
    W.SuiteAction(character, nil, "release")

    local function ClickCaption(cell)
        Hover(cell)
        if delegate.shown and delegate.owner == cell then
            SecureClick(delegate, "LeftButton")
        else
            cell.scripts.OnClick(cell, "LeftButton")
        end
    end

    -- Exercise the caption's normal click routing with a native opener available.
    local function CheckPageMinimize(root, owner, page)
        Check(W.Attach(root, owner), root.name .. " controls did not attach")
        local panel = W.states[root]
        Check(panel.minimize.shown, root.name .. " lost its minimize button")
        ClickCaption(panel.minimize)
        Check(panel.park and panel.restore.shown and root.shown and root.point[3] == "BOTTOMLEFT",
            flavor .. ": " .. root.name .. " did not keep its current page open while minimized")
        Check(not delegate.shown and page.shown and not root:IsClampedToScreen(),
            root.name .. " changed pages, kept clamping, or armed a native click")
        W.Refresh()
        Check(panel.park and root.point[3] == "BOTTOMLEFT", root.name .. " reappeared during a UI layout pass")
        ClickCaption(panel.restore)
        Check(not panel.park and not panel.restore.shown and root.shown and root.point[3] == "CENTER",
            root.name .. " did not restore the original anchor")
        Check(not delegate.shown and page.shown and root:IsClampedToScreen(),
            root.name .. " did not restore the clamp and current page")
    end

    -- The micro button opens PaperDollFrame on both clients. Preserve
    -- secondary pages and their scroll state without invoking that opener.
    function character:GetPoint() return unpack(self.point) end
    character:SetClampedToScreen(true)
    character:SetPoint("CENTER", UIParent, "CENTER", 27, -13)
    local closesBefore, opensBefore = characterCloses, characterOpens
    for _, name in ipairs({ "ReputationFrame", "TokenFrame" }) do
        character:ShowSubFrame(name)
        local page = characterPages[name]
        page.scrollOffset = 42
        CheckPageMinimize(character, "blizzardWindows", page)
        Check(character.activeSubframe == name and page.scrollOffset == 42 and character.point[4] == 27
            and character.point[5] == -13, flavor .. ": Character restore changed its tab, scroll offset, or position")
        Check(characterCloses == closesBefore and characterOpens == opensBefore and #skinCalls == 0,
            flavor .. ": minimizing a secondary Character page ran a native panel action")
    end
    -- A native click on the character micro button while Reputation is parked
    -- selects PaperDoll on the same shown root. It should also bring it back.
    local function ParkOnReputation()
        character:ShowSubFrame("ReputationFrame")
        H.NextFrame()
        ClickCaption(hero.minimize)
        Check(hero.park and hero.restore.shown, flavor .. ": Reputation did not park before the shortcut")
    end

    ParkOnReputation()
    Blizzard(micro.scripts.OnClick, micro)
    H.NextFrame()
    Check(character.shown and character.activeSubframe == "PaperDollFrame" and not hero.park
        and not hero.restore.shown and character.point[4] == 27 and character.point[5] == -13,
        flavor .. ": native character shortcut left the selected page below the viewport")

    ParkOnReputation()
    _G.combat = true
    Blizzard(micro.scripts.OnClick, micro)
    H.NextFrame()
    Check(hero.park and H.jobs["windowControls:restoreCharacterPage"],
        flavor .. ": the shortcut moved the parked frame in combat or lost the pending restore")
    _G.combat = false
    Hover(hero.restore)
    Check(not delegate.shown, flavor .. ": a pending parked restore armed the native micro button")
    local restorePage = H.jobs["windowControls:restoreCharacterPage"]
    H.jobs["windowControls:restoreCharacterPage"] = nil
    restorePage()
    Check(not hero.park and not hero.restore.shown and character.activeSubframe == "PaperDollFrame",
        flavor .. ": the shortcut did not restore the selected page after combat")

    ParkOnReputation()
    Blizzard(HideUIPanel, character)
    H.NextFrame()
    Check(not character.shown and not hero.park and not hero.restore.shown,
        flavor .. ": a native close while parked left a dangling restore tab")

    local nativeClicks = 0
    local function NativeClick() nativeClicks = nativeClicks + 1 end
    UIPanelWindows.PlayerSpellsFrame = { area = "left" }
    local spells = Frame("PlayerSpellsFrame", UIParent)
    _G.PlayerSpellsFrame = spells
    spells.protected, spells.clamped = true, true
    spells.CloseButton = Frame(nil, spells, "Button")
    spells.CloseButton.scripts.OnClick = NativeClick
    spells.SpellBookFrame, spells.TalentsFrame, spells.SpecFrame = Frame(nil, spells), Frame(nil, spells), Frame(nil, spells)
    function spells:IsInspecting() return false end
    for _, name in ipairs({ "SpellbookMicroButton", "TalentMicroButton", "PlayerSpellsMicroButton" }) do
        local opener = Frame(name, UIParent, "Button")
        opener.scripts.OnClick = NativeClick
        function opener:IsEnabled() return true end
        _G[name] = opener
    end
    local spellPages = { spells.SpellBookFrame, spells.TalentsFrame, spells.SpecFrame }
    for _, activePage in ipairs(spellPages) do
        for _, page in ipairs(spellPages) do page:SetShown(page == activePage) end
        CheckPageMinimize(spells, "playerSpells", activePage)
    end
    spells:Hide()

    -- Forever embeds the overview in its crafting window. Retail has a
    -- separate overview and both clients can have a recipe selected.
    UIPanelWindows.ProfessionsFrame = { area = "left" }
    local professions = Frame("ProfessionsFrame", UIParent)
    _G.ProfessionsFrame = professions
    professions.clamped = true
    professions.CloseButton = Frame(nil, professions, "Button")
    professions.CloseButton.scripts.OnClick = NativeClick
    professions.BookPage, professions.CraftingPage = Frame(nil, professions), Frame(nil, professions)
    professions.CraftingPage:Hide()
    local professionBook = Frame("ProfessionsBookFrame", UIParent)
    _G.ProfessionsBookFrame = professionBook
    professionBook.clamped = true
    professionBook.CloseButton = Frame(nil, professionBook, "Button")
    professionBook.CloseButton.scripts.OnClick = NativeClick
    UIPanelWindows.ProfessionsBookFrame = { area = "left" }
    NS.BlizzardCatalog.FindByFrame = function(name)
        if name == "ProfessionsBookFrame" then return { category = "profession" } end
        return findByFrame(name)
    end
    local professionMicro = Frame("ProfessionMicroButton", UIParent, "Button")
    _G.ProfessionMicroButton = professionMicro
    function professionMicro:IsEnabled() return true end
    function professionMicro:GetToggledFrame()
        return flavor == "Forever" and professions or professionBook
    end
    professionMicro.scripts.OnClick = NativeClick
    C_TradeSkillUI = {
        GetBaseProfessionInfo = function() return { professionID = 164 } end,
        OpenTradeSkill = NativeClick,
    }
    if flavor == "Forever" then
        CheckPageMinimize(professions, "professions", professions.BookPage)
    else
        CheckPageMinimize(professionBook, "professions", professionBook)
    end
    professions.BookPage:Hide()
    professions.CraftingPage:Show()
    CheckPageMinimize(professions, "professions", professions.CraftingPage)
    Check(nativeClicks == 0, "minimizing a page ran a native close or recast")

    local professionCaption = W.states[professions]
    professionCaption.minimize.scripts.OnClick(professionCaption.minimize, "LeftButton")
    professions:Hide()
    H.NextFrame()
    Check(not professionCaption.park and not professionCaption.restore.shown,
        "a native close left a minimized professions tab behind")
    _G.ProfessionMicroButton, _G.ProfessionsFrame, _G.ProfessionsBookFrame = nil, nil, nil
    UIPanelWindows.ProfessionsFrame, UIPanelWindows.ProfessionsBookFrame = nil, nil

    if flavor == "Forever" then
        UIPanelWindows.LegacySystemFrame = { area = "left" }
        local legacy = Frame("LegacySystemFrame", UIParent)
        _G.LegacySystemFrame = legacy
        legacy.clamped = true
        legacy.CloseButton = Frame(nil, legacy, "Button")
        legacy.CloseButton.scripts.OnClick = NativeClick
        local legacyMicro = Frame("LegacyMicroButton", UIParent, "Button")
        _G.LegacyMicroButton = legacyMicro
        function legacyMicro:IsEnabled() return true end
        legacyMicro.scripts.OnClick = NativeClick
        NS.BlizzardCatalog.FindByFrame = function(name)
            if name == "LegacySystemFrame" then return { category = "character" } end
            return findByFrame(name)
        end
        local challenges = Frame(nil, legacy)
        CheckPageMinimize(legacy, "legacy", challenges)
        Check(nativeClicks == 0, "minimizing Legacy called the native close or reopened the window")
        legacy:Hide()
        UIPanelWindows.LegacySystemFrame, _G.LegacySystemFrame, _G.LegacyMicroButton = nil, nil, nil
    end

    -- The AddOn list can be parked with pending changes: no click reaches its X.
    local addons = Frame("AddonList", UIParent)
    _G.AddonList = addons
    UIPanelWindows.AddonList = { area = "center" }
    local closes = 0
    addons.CloseButton = Frame(nil, addons, "Button")
    addons.CloseButton.scripts.OnClick = function() closes = closes + 1; HideUIPanel(addons) end
    AddonList_HasAnyChanged = function() return true end
    Check(W.Attach(addons, "blizzardWindows"), flavor .. ": the AddOn list did not attach")
    local list = W.states[addons]
    Hover(list.minimize)
    Check(not delegate.shown, "AddonList bound a native click instead of preserving pending changes")
    list.minimize.scripts.OnClick(list.minimize, "LeftButton")
    Check(addons.shown and closes == 0 and list.minimized and list.restore.shown,
        flavor .. ": minimize cleared the AddOn list's unapplied changes")
    list.restore.scripts.OnClick(list.restore, "LeftButton")
    Check(#skinCalls == 0, flavor .. ": the skin drove the panel manager: " .. table.concat(skinCalls, ", "))
end
print("Window controls secure caption: " .. checks .. " checks passed")
