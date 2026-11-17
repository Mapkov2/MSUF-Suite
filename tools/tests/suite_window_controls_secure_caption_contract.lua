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
--        [WindowControls.lua] [WindowControlDelegate.lua] [WindowControlPolicy.lua] [WindowControlChrome.lua]
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1):gsub('arg%[[35]%] or ', '') .. [[
return { NS = NS, Frame = Frame, frames = createdFrames, jobs = combatJobs }
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
        function frame:SetAllPoints(target) self:SetPoint("TOPLEFT", target, "TOPLEFT") end
        local hide = frame.Hide
        function frame:Hide()
            local wasShown = self.shown
            hide(self)
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        return frame
    end
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

    -- Options: a secure anchor protects its target and that frame's ancestors.
    -- A managed window without a native opener (Settings) has no way back but
    -- ShowUIPanel, which the skin may not run: it offers no minimize, and the
    -- plain cell and tab never drive the panel manager.
    UIPanelWindows.SettingsPanel = { area = "center", checkFit = 1 }
    local plainSettings = Frame("SettingsPanel", UIParent)
    plainSettings.ClosePanelButton = Frame(nil, plainSettings, "Button")
    plainSettings.ClosePanelButton.scripts.OnClick = function() HideUIPanel(plainSettings) end
    Check(W.Attach(plainSettings, "plainSettings"), flavor .. ": Settings did not attach")
    local plain = W.states[plainSettings]
    Check(plain.minimize and not plain.minimize.shown, flavor .. ": Settings offered minimize without a native opener")
    plain.minimize.scripts.OnClick(plain.minimize)
    Hover(plain.minimize)
    Check(plainSettings.shown and not plain.minimized and not delegate.shown and #skinCalls == 0,
        flavor .. ": Settings minimized without a secure way back")
    plain.minimized = true
    plain.restore.scripts.OnClick(plain.restore, "LeftButton")
    plain.minimized = false
    Check(#skinCalls == 0, flavor .. ": a Settings restore tab ran ShowUIPanel from the skin")
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
    character.CloseButton = Frame(nil, character, "Button")
    character.CloseButton.scripts.OnClick = function() HideUIPanel(character) end
    local micro = Frame("CharacterMicroButton", UIParent, "Button")
    function micro:IsEnabled() return true end
    micro.scripts.OnClick = function()
        if character:IsShown() then HideUIPanel(character) else ShowUIPanel(character) end
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
    Check(W.SuiteAction(character, {}, "minimize") == false and character.shown and #skinCalls == 0,
        flavor .. ": the Suite minimize hid the Character window from addon code")
    Check(W.SuiteAction(character, {}, "bindMinimize", suiteCell) == true,
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

    if flavor == "Forever" then
        UIPanelWindows.PlayerSpellsFrame = { area = "left" }
        local spells = Frame("PlayerSpellsFrame", UIParent)
        _G.PlayerSpellsFrame = spells
        spells.CloseButton, spells.SpellBookFrame = Frame(nil, spells, "Button"), Frame(nil, spells)
        spells.TalentsFrame, spells.SpecFrame = Frame(nil, spells), Frame(nil, spells)
        function spells:IsInspecting() return self.inspecting == true end
        spells.CloseButton.scripts.OnClick = function()
            HideUIPanel(spells)
            spells.SpellBookFrame.shown, spells.TalentsFrame.shown = false, false
        end
        local book = Frame("SpellbookMicroButton", UIParent, "Button")
        local talents = Frame("TalentMicroButton", UIParent, "Button")
        _G.SpellbookMicroButton, _G.TalentMicroButton = book, talents
        function book:IsEnabled() return not self.disabled end
        talents.IsEnabled = book.IsEnabled
        for _, opener in ipairs({ book, talents }) do
            opener.scripts.OnClick = function()
                spells.SpellBookFrame.shown, spells.TalentsFrame.shown = opener == book, opener == talents
                ShowUIPanel(spells)
            end
        end
        spells.SpellBookFrame.shown, spells.TalentsFrame.shown, spells.SpecFrame.shown = false, false, true
        Check(W.Attach(spells, "playerSpells"), "spellbook controls did not attach")
        local panel = W.states[spells]
        panel.minimize.scripts.OnClick(panel.minimize, "LeftButton")
        Check(spells.shown and #skinCalls == 0, "the skin hid the specialization view from addon code")
        Check(not panel.minimize.shown, "the specialization view offered minimize without a native restore button")
        spells.TalentsFrame.shown, spells.SpecFrame.shown, spells.inspecting = true, false, true
        Check(W.Attach(spells, "playerSpells"), "inspected talent controls did not attach")
        panel.minimize.scripts.OnClick(panel.minimize, "LeftButton")
        Check(spells.shown and #skinCalls == 0, "the skin hid inspected talents from addon code")
        Check(not panel.minimize.shown, "inspected talents offered minimize without a native restore button")
        spells.inspecting = false
        for _, opener in ipairs({ book, talents }) do
            spells.SpellBookFrame.shown, spells.TalentsFrame.shown = opener == book, opener == talents
            Check(W.Attach(spells, "playerSpells") and panel.minimize.shown, "a supported spell page lost minimize")
            panel.minimize.scripts.OnClick(panel.minimize, "LeftButton")
            Check(spells.shown and #skinCalls == 0, "the skin hid the spellbook from addon code")
            Hover(panel.minimize)
            Check(delegate:GetAttribute("clickbutton1") == spells.CloseButton, "spellbook minimize skipped Blizzard's close")
            opener.disabled = true
            SecureClick(delegate, "LeftButton")
            Check(spells.shown and not panel.restore.shown, "a stale hover minimized the spellbook without a native restore button")
            opener.disabled = false
            Hover(panel.minimize)
            SecureClick(delegate, "LeftButton")
            panel.restore.scripts.OnClick(panel.restore, "LeftButton")
            Check(not spells.shown and #skinCalls == 0, "the skin reopened the spellbook from addon code")
            Hover(panel.restore)
            Check(delegate:GetAttribute("clickbutton1") == opener, "spellbook restore skipped the active native page")
            opener.disabled = true
            SecureClick(delegate, "LeftButton")
            Check(not spells.shown and panel.restore.shown, "a stale hover clicked a disabled spellbook opener")
            opener.disabled = false
            Hover(panel.restore)
            SecureClick(delegate, "LeftButton")
            Check(spells.shown and #skinCalls == 0, "spellbook restore did not use Blizzard's button")
        end
    end

    -- Camelot's overview lives inside ProfessionsFrame and uses the native
    -- profession micro button. A crafting page still needs its spell route.
    UIPanelWindows.ProfessionsFrame = { area = "left" }
    local professions = Frame("ProfessionsFrame", UIParent)
    _G.ProfessionsFrame = professions
    professions.CloseButton = Frame(nil, professions, "Button")
    professions.BookPage = Frame(nil, professions)
    professions.CraftingPage = Frame(nil, professions)
    professions.CraftingPage:Hide()
    professions.CloseButton.scripts.OnClick = function()
        HideUIPanel(professions)
        professions.BookPage:Hide()
    end
    local professionMicro = Frame("ProfessionMicroButton", UIParent, "Button")
    _G.ProfessionMicroButton = professionMicro
    function professionMicro:IsEnabled() return true end
    function professionMicro:GetToggledFrame()
        if flavor == "Forever" then return professions end
    end
    professionMicro.scripts.OnClick = function()
        professions.BookPage:Show()
        ShowUIPanel(professions)
    end
    Check(W.Attach(professions, "professions"), "professions caption did not attach")
    local professionCaption = W.states[professions]
    if flavor == "Forever" then
        Check(professionCaption.minimize.shown, "the Forever professions overview did not offer minimize")
        Hover(professionCaption.minimize)
        Check(delegate:GetAttribute("clickbutton1") == professions.CloseButton, "profession minimize skipped Blizzard's X")
        SecureClick(delegate, "LeftButton")
        Check(not professions.shown and professionCaption.restore.shown, "the minimized profession overview lost its restore tab")
        Hover(professionCaption.restore)
        Check(delegate:GetAttribute("clickbutton1") == professionMicro, "the overview restore skipped Blizzard's professions button")
        SecureClick(delegate, "LeftButton")
        Check(professions.shown and professions.BookPage.shown and not professionCaption.restore.shown,
            "the native restore did not return to the professions overview")
        professions.BookPage:Hide()
        Check(NS.WindowControlPolicy.Opener(professionCaption) == nil,
            "a hidden overview incorrectly supplied the crafting page's opener")
    else
        Check(not professionCaption.minimize.shown, "Retail ProfessionsFrame used the standalone book's opener")
    end
    _G.ProfessionMicroButton, _G.ProfessionsFrame, UIPanelWindows.ProfessionsFrame = nil, nil, nil

    -- The AddOn list keeps unapplied changes: no click reaches its X.
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
    SecureClick(delegate, "LeftButton")
    Check(addons.shown and closes == 0 and not list.minimized and not list.restore.shown,
        flavor .. ": minimize closed the AddOn list over unapplied changes")
    Check(#skinCalls == 0, flavor .. ": the skin drove the panel manager: " .. table.concat(skinCalls, ", "))
end
print("Window controls secure caption: " .. checks .. " checks passed")
