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
-- Usage: lua suite_window_controls_secure_caption_contract.lua <Suite root> [WindowControls.lua]
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = createdFrames }
]]
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
        function frame:SetAllPoints(target) self.allPoints = target end
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
    Fire(state.minimize, "OnEnter")
    local delegate = Delegate()
    Check(delegate and delegate.shown and delegate.owner == state.minimize and delegate.allPoints == state.minimize,
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
    Fire(state.restore, "OnEnter")
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
    Fire(state.minimize, "OnEnter")
    SecureClick(delegate, "LeftButton")
    Check(not map.shown and state.restore.shown, flavor .. ": the second minimize failed")
    state.restore.scripts.OnClick(state.restore, "LeftButton")
    Check(not map.shown and state.restore.shown and #skinCalls == 0 and skinMapCalls == 0,
        flavor .. ": the skin's own restore showed the map")

    -- The tab still moves; a drag never clicks the opener. A right click lets
    -- the window go without opening it.
    Fire(state.restore, "OnEnter")
    Fire(delegate, "OnDragStart")
    Check(state.restore.moving and delegate:GetAttribute("type1") == nil,
        flavor .. ": dragging the tab did not move it or would open the map")
    SecureClick(delegate, "LeftButton")
    Fire(delegate, "OnDragStop")
    Check(not map.shown and not state.restore.moving and not delegate.shown,
        flavor .. ": the tab drag opened the map or kept the delegate")
    Fire(state.restore, "OnEnter")
    Fire(delegate, "OnDragStart")
    Fire(delegate, "OnDragStop")
    Check(not map.shown and not state.restore.moving and not delegate.shown and state.restore.shown,
        flavor .. ": a drag without a click did not end on the tab")
    Fire(state.restore, "OnEnter")
    SecureClick(delegate, "RightButton")
    Check(not map.shown and not state.minimized and not state.restore.shown,
        flavor .. ": a right click on the tab opened the map or kept the tab")
    Blizzard(ShowUIPanel, map)

    -- The map goes only while Blizzard's map button can bring it back.
    function zoneText:IsEnabled() return false end
    Fire(state.minimize, "OnEnter")
    Check(not delegate.shown, flavor .. ": the map minimized without a secure way back")
    function zoneText:IsEnabled() return true end
    -- In combat and under the Gamepad UI the delegate stays away.
    _G.combat = true
    Fire(state.minimize, "OnEnter")
    Check(not delegate.shown, flavor .. ": the delegate was laid over the cell in combat")
    _G.combat = false
    NS.Client.IsGamepadUI = function() return true end
    Fire(state.minimize, "OnEnter")
    Check(not delegate.shown, flavor .. ": the delegate came under the Gamepad UI")
    NS.Client.IsGamepadUI = function() return false end

    -- A cell that hides under the pointer lets the delegate go.
    Fire(state.minimize, "OnEnter")
    Check(delegate.shown, flavor .. ": the delegate did not come back")
    state.minimize:Hide()
    Check(not delegate.shown and delegate.owner == nil, flavor .. ": a hidden cell kept the delegate")
    state.minimize:Show()

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
    Fire(hero.minimize, "OnEnter")
    Check(delegate:GetAttribute("clickbutton1") == character.CloseButton, flavor .. ": Character minimize skips its X")
    SecureClick(delegate, "LeftButton")
    Fire(hero.restore, "OnEnter")
    Check(delegate:GetAttribute("clickbutton1") == micro, flavor .. ": Character restore skips its micro button")
    SecureClick(delegate, "LeftButton")
    Check(character.shown and not hero.restore.shown and #skinCalls == 0,
        flavor .. ": the Character window went through the skin's panel calls")

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
    Fire(list.minimize, "OnEnter")
    SecureClick(delegate, "LeftButton")
    Check(addons.shown and closes == 0 and not list.minimized and not list.restore.shown,
        flavor .. ": minimize closed the AddOn list over unapplied changes")
    Check(#skinCalls == 0, flavor .. ": the skin drove the panel manager: " .. table.concat(skinCalls, ", "))
end
print("Window controls secure caption: " .. checks .. " checks passed")
