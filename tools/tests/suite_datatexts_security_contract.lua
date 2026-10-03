-- DataTexts against the client's protection rules (clientSecurity harness):
-- places are ordinary buttons that may move in combat, protected clicks run
-- on secure buttons that never depend on a bar during combat, and combat
-- visibility follows the client's own combat state.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local hour, minute = 14, 3
local loaded, microClicks = {}, {}
local W = H.New(root, flavor, { clientSecurity = true, beforeModules = function(world)
    local G = world.G
    G.GetGameTime = function() return hour, minute end
    G.GetMoney = function() return 120000 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end,
    }
    G.PlayerHasToy = function() return false end
    G.C_Item = {
        GetItemCount = function(id) return id == 6948 and 1 or 0 end,
        GetItemInfo = function(id) return id == 6948 and "Hearthstone" or nil, nil, nil, nil, nil, nil, nil, nil, nil, 134414 end,
    }
    -- The deprecation fallbacks are off: only C_SpecializationInfo exists.
    G.GetSpecialization, G.GetSpecializationInfo = nil, nil
    G.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62, "Arcane", "", 135932 end,
    }
    G.C_Spell = { GetSpellCooldownDuration = function() return nil end }
    G.C_AddOns.LoadAddOn = function(name) loaded[#loaded + 1] = name end
    -- Blizzard's micro buttons; their own OnClick records whether it ran secure.
    -- layoutIndex marks the buttons Blizzard put into its micro menu
    -- (MicroMenuMixin:AddButton): Forever's menu leaves PlayerSpells out,
    -- Retail's has no separate Spellbook and Talent buttons.
    local unlisted = flavor == "Forever" and { PlayerSpellsMicroButton = true }
        or { SpellbookMicroButton = true, TalentMicroButton = true }
    for index, name in ipairs({ "CharacterMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton",
        "TalentMicroButton", "QuestLogMicroButton", "GuildMicroButton", "MainMenuMicroButton" }) do
        local native = world.New("Button", name, world.UIParent)
        native.tooltipText = name .. " tip"
        if not unlisted[name] then native.layoutIndex = index end
        native.scripts.OnClick = function(self)
            microClicks[#microClicks + 1] = { name = self.name, secure = world.secure }
        end
    end
    -- Blizzard_UIParentPanelManager: an addon's ShowUIPanel/HideUIPanel hand
    -- the panel to the secure FramePositionDelegate (refused in combat).
    world.panelCalls = {}
    local function Panel(shown)
        return function(frame)
            world.panelCalls[#world.panelCalls + 1] = { frame = frame, shown = shown, secure = world.secure }
            if not G.InCombatLockdown() then world.Blizzard(function() frame:SetShown(shown) end) end
        end
    end
    G.ShowUIPanel, G.HideUIPanel = Panel(true), Panel(false)
    G.SOUNDKIT = { IG_MAINMENU_OPEN = 850, IG_MAINMENU_QUIT = 851 }
    G.PlaySound = function(sound) world.sounds = (world.sounds or 0) + 1; world.lastSound = sound end
    G.GameMenuFrame = world.New("Frame", "GameMenuFrame", world.UIParent)
    G.GameMenuFrame:Hide()
    -- The minimap's zone text button opens the world map
    -- (MinimapZoneTextButtonMixin:OnClick); the openers record their callers.
    G.MinimapCluster.ZoneTextButton.scripts.OnClick = function()
        microClicks[#microClicks + 1] = { name = "ZoneTextButton", secure = world.secure }
    end
    -- The character window's currency tab runs CharacterFrame:ToggleTokenFrame()
    -- (CharacterFrameTabButtonMixin:OnClick).
    G.CharacterFrameTab3.scripts.OnClick = function()
        microClicks[#microClicks + 1] = { name = "CharacterFrameTab3", secure = world.secure }
    end
    world.opened = {}
    for _, name in ipairs({ "ToggleCharacter", "ToggleWorldMap" }) do
        G[name] = function(tab)
            world.opened[#world.opened + 1] = { name = name, tab = tab, secure = world.secure }
        end
    end
    -- MainMenuMicroButtonMixin:OnClick (Blizzard_MicroMenu/Mainline) acts only
    -- while the cursor is over the micro button itself.
    G.MainMenuMicroButton.scripts.OnClick = function(self)
        microClicks[#microClicks + 1] = { name = self.name, secure = world.secure }
        if not self:IsMouseOver() then return end
        if G.GameMenuFrame:IsShown() then G.HideUIPanel(G.GameMenuFrame) else G.ShowUIPanel(G.GameMenuFrame) end
    end
end })
local G, S, NS = W.G, W.S, W.Suite
function G.GameTooltip:SetItemByID(id) self.lines = { "item:" .. id } end
W.LoadAddon("MSUF_Suite_DataTexts")
local M = assert(S.instances.dataTexts)
local A = W.private.DataTextActions
local function Choice(key)
    for index, value in ipairs(NS.DataTextSourceKeys) do
        if value == key then return index end
    end
    error("unknown DataText source " .. key)
end
S.Start()
local c = S.Config("dataTexts")
assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true, bar1Layout = 2,
    bar1Slot1 = Choice("clock"), bar1Slot2 = Choice("hearth"), bar1Slot3 = Choice("specialization"),
    bar1Slot4 = Choice("audio"), bar1Slot5 = Choice("portals"), bar1Slot6 = Choice("microMenu"),
    bar2Enabled = true, bar2Visibility = 2, bar2Slot1 = Choice("fps"), bar2Slot2 = 1, bar2Slot3 = 1,
    bar3Enabled = true, bar3Visibility = 3, bar3Slot1 = Choice("gold"), bar3Slot2 = 1, bar3Slot3 = 1,
    bar4Enabled = true, bar4Slot1 = Choice("durability"), bar4Slot2 = Choice("coordinates"),
    bar4Slot3 = Choice("location"), bar4Slot4 = Choice("currency") }))
local bar = assert(M.bars[1])
local slots = bar.slots
local clock, hearth, spec, audio, portals, micro = slots[1], slots[2], slots[3], slots[4], slots[5], slots[6]

-- P0-1: no place and no bar is protected, explicitly or through a child.
for i = 1, 6 do
    assert(not slots[i]:IsProtected() and slots[i].template == nil, "DataText place " .. i .. " is protected")
end
assert(not bar.frame:IsProtected() and not bar.visual:IsProtected(), "a DataTexts bar became protected")
assert(clock.text == "Time: 14:03" and spec.text == "Specialization: Arcane",
    "clock or specialization (C_SpecializationInfo) did not render")
-- P3-1: only the volume place takes the mouse wheel; the others leave it to the camera.
for i = 1, 6 do
    assert(slots[i].wheel == (slots[i] == audio), "place " .. i .. " has the wrong mouse wheel state")
end

-- P1-1: the Hearthstone place uses the item through the secure overlay.
W.Fire(hearth, "OnEnter")
local overlay = assert(A.overlay, "hovering a Hearthstone place did not attach the secure overlay")
assert(overlay.protected and overlay.template == "SecureActionButtonTemplate" and overlay.parent == W.UIParent,
    "the overlay must be its own secure button in UIParent")
assert(overlay.shown and overlay.points[1][2] == hearth and overlay:GetAttribute("type1") == "item"
    and overlay:GetAttribute("item1") == "item:6948", "the overlay does not cover the Hearthstone place")
-- The client then moves the pointer onto the overlay: the place keeps its tooltip.
overlay.mouseOver, hearth.mouseOver, bar.frame.mouseOver = true, true, true
W.Fire(hearth, "OnLeave")
W.Fire(overlay, "OnEnter")
assert(G.GameTooltip.shown and G.GameTooltip.owner == hearth and overlay.shown,
    "moving onto the overlay hid the Hearthstone tooltip or the overlay")
W.Click(overlay)
local used = W.secureActions[#W.secureActions]
assert(used and used.frame == overlay and used.type == "item" and used.item == "item:6948",
    "clicking the Hearthstone place did not use the item through the secure action")
overlay.mouseOver, hearth.mouseOver = false, false
W.Fire(overlay, "OnLeave")
assert(not overlay.shown and #overlay.points == 0 and not G.GameTooltip.shown,
    "leaving the overlay kept it attached or kept the tooltip")

-- P2-12: Specialization clicks Blizzard's talent micro button securely.
local talents = flavor == "Forever" and "TalentMicroButton" or "PlayerSpellsMicroButton"
W.Fire(spec, "OnEnter")
assert(overlay.shown and overlay.points[1][2] == spec and overlay:GetAttribute("type1") == "click"
    and overlay:GetAttribute("clickbutton1") == G[talents], "the specialization place lacks the secure click")
W.Click(overlay)
assert(microClicks[#microClicks].name == talents and microClicks[#microClicks].secure,
    "the talent micro button was not clicked through the secure action")
-- Every mouse button opens the talents, as the place did before the overlay
-- (Blizzard's talent micro buttons ignore the button).
for _, mouse in ipairs({ "RightButton", "MiddleButton" }) do
    local clicks = #microClicks
    W.Click(overlay, mouse)
    assert(#microClicks == clicks + 1 and microClicks[#microClicks].name == talents
        and microClicks[#microClicks].secure, "a " .. mouse .. " on the specialization place did nothing")
end
W.Fire(overlay, "OnLeave")
-- The Hearthstone place keeps its item on the left button only.
W.Fire(hearth, "OnEnter")
assert(overlay:GetAttribute("type") == nil and overlay:GetAttribute("clickbutton") == nil,
    "the Hearthstone place kept the specialization's any-button click")
W.Fire(overlay, "OnLeave")

-- P2-12: the micro menu is a popup of secure rows that click the buttons.
-- It lists the Suite's one micro menu (S.MicroMenuEntries, the Minimap's
-- entries in Blizzard's order) and keeps its game menu row last (S3.2).
local beforeMicro = #microClicks
G.GuildMicroButton.enabled = false
W.Click(micro)
local popup = assert(A.popup, "the micro menu did not open its popup")
assert(popup.shown and popup:IsProtected() and popup.parent == W.UIParent, "the micro menu popup is not secure")
local expected = flavor == "Forever"
    and { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
        "GuildMicroButton", "MainMenuMicroButton" }
    or { "CharacterMicroButton", "PlayerSpellsMicroButton", "QuestLogMicroButton", "GuildMicroButton",
        "MainMenuMicroButton" }
local shared = {}
assert(S.MicroMenuEntries(shared, false) == #expected - 1, "the Minimap's micro menu lists other buttons")
for i, name in ipairs(expected) do
    local row = popup.rows[i]
    if i < #expected then
        assert(row and row.shown and row:GetAttribute("type") == "click" and row:GetAttribute("clickbutton") == G[name]
            and shared[i].button == G[name] and row.label.text == shared[i].label,
            "micro menu row " .. i .. " is not the shared secure click on " .. name)
    else
        -- S3.2: a secure click on the game menu button does nothing (it
        -- checks IsMouseOver), so the game menu is a plain row.
        assert(row and row.shown and row:GetAttribute("type") == nil and row:GetAttribute("clickbutton") == nil
            and row.label.text == "Game menu" and row.enabled, "the game menu row is not a plain, enabled row")
    end
end
assert(not (popup.rows[#expected + 1] and popup.rows[#expected + 1].shown), "the micro menu lists extra rows")
local first, guild = popup.rows[1], popup.rows[#expected - 1]
assert(first.label.text == "Character" and first.enabled and not guild.enabled,
    "micro menu rows lost the shared labels or a disabled button stayed clickable")
G.GuildMicroButton.enabled = true
W.Click(first)
assert(#microClicks == beforeMicro + 1 and microClicks[#microClicks].name == "CharacterMicroButton"
    and microClicks[#microClicks].secure and not popup.shown and #popup.points == 0,
    "a micro menu row did not click securely or did not close the popup")
-- S3.2: the game menu row opens the game menu out of combat through
-- Blizzard's panel manager, and closes it again; the popup closes either way.
W.Click(micro)
W.Click(popup.rows[#expected])
local opened = W.panelCalls[#W.panelCalls]
assert(G.GameMenuFrame.shown and opened and opened.frame == G.GameMenuFrame and opened.shown
    and W.lastSound == G.SOUNDKIT.IG_MAINMENU_OPEN and not popup.shown,
    "the game menu row did not open the game menu (S3.2)")
W.Click(micro)
W.Click(popup.rows[#expected])
assert(not G.GameMenuFrame.shown and W.panelCalls[#W.panelCalls].shown == false
    and W.lastSound == G.SOUNDKIT.IG_MAINMENU_QUIT and not popup.shown,
    "the game menu row did not close the open game menu")

-- Durability, Coordinates and Zone places open their window through the
-- secure overlay, which clicks Blizzard's own button: the character window
-- (CharacterMicroButton) and the world map (the minimap's zone text button).
local windows = assert(M.bars[4]).slots
local durability, coordinates, zone = windows[1], windows[2], windows[3]
for _, case in ipairs({ { durability, G.CharacterMicroButton, "CharacterMicroButton" },
    { coordinates, G.MinimapCluster.ZoneTextButton, "ZoneTextButton" },
    { zone, G.MinimapCluster.ZoneTextButton, "ZoneTextButton" } }) do
    local place, native, name = case[1], case[2], case[3]
    W.Fire(place, "OnEnter")
    assert(overlay.shown and overlay.points[1][2] == place and overlay:GetAttribute("type1") == "click"
        and overlay:GetAttribute("clickbutton1") == native and overlay:GetAttribute("clickbutton") == native,
        "the " .. place.source .. " place lacks the secure click on " .. name)
    for _, mouse in ipairs({ "LeftButton", "RightButton" }) do
        local clicks = #microClicks
        W.Click(overlay, mouse)
        assert(#microClicks == clicks + 1 and microClicks[#microClicks].name == name and microClicks[#microClicks].secure,
            "a " .. mouse .. " on the " .. place.source .. " place did not click " .. name .. " securely")
    end
    W.Fire(overlay, "OnLeave")
end
assert(#W.opened == 0, "a window place opened its window from the addon's code")
-- Without a visible Blizzard button the place opens the window through
-- Blizzard's panel manager (ShowUIPanel hands it to the secure
-- FramePositionDelegate); ToggleWorldMap would run the map's display-state
-- code inside the addon's call.
G.MinimapCluster.ZoneTextButton.shown = false
W.Fire(zone, "OnEnter")
assert(not (overlay.shown and overlay.points[1][2] == zone), "the overlay offered a click on a hidden button")
local panelCount = #W.panelCalls
W.Click(zone)
assert(#W.opened == 0 and #W.panelCalls == panelCount + 1 and W.panelCalls[#W.panelCalls].frame == G.WorldMapFrame
    and W.panelCalls[#W.panelCalls].shown and G.WorldMapFrame.shown,
    "the Zone place did not fall back to opening the world map through the panel manager")
W.Click(zone)
assert(#W.opened == 0 and not W.panelCalls[#W.panelCalls].shown and not G.WorldMapFrame.shown,
    "a second Zone click did not close the world map through the panel manager")
W.Fire(zone, "OnLeave")
G.MinimapCluster.ZoneTextButton.shown = true

-- The Currency place clicks the character window's currency tab from secure
-- code, even with the window closed: ToggleCharacter("TokenFrame") from the
-- place's own click ran CharacterFrame's tab and sub-frame code tainted.
local currency = windows[4]
W.Fire(currency, "OnEnter")
assert(overlay.shown and overlay.points[1][2] == currency and overlay:GetAttribute("type1") == "click"
    and overlay:GetAttribute("clickbutton1") == G.CharacterFrameTab3
    and overlay:GetAttribute("clickbutton") == G.CharacterFrameTab3,
    "the currency place lacks the secure click on the currency tab")
for _, mouse in ipairs({ "LeftButton", "RightButton" }) do
    local clicks = #microClicks
    W.Click(overlay, mouse)
    assert(#microClicks == clicks + 1 and microClicks[#microClicks].name == "CharacterFrameTab3"
        and microClicks[#microClicks].secure, "a " .. mouse .. " on the currency place did not click the tab securely")
end
W.Fire(overlay, "OnLeave")
-- A player without currencies has no currency tab: the place opens the
-- character window through the panel manager.
G.CharacterFrameTab3.shown = false
W.Fire(currency, "OnEnter")
assert(not (overlay.shown and overlay.points[1][2] == currency), "the overlay offered a click on a hidden currency tab")
panelCount = #W.panelCalls
W.Click(currency)
assert(#W.opened == 0 and #W.panelCalls == panelCount + 1 and W.panelCalls[#W.panelCalls].frame == G.CharacterFrame
    and W.panelCalls[#W.panelCalls].shown, "the currency place did not fall back to the character window")
W.Click(currency)
W.Fire(currency, "OnLeave")
G.CharacterFrameTab3.shown = true
assert(#W.opened == 0, "a currency place opened its window from the addon's code")

-- P2-1: the portal popup stays open while the pointer moves onto and between
-- its rows, and closes once the pointer rests outside.
if flavor == "Mainline" then
    S.LearnedDungeonPortals = function()
        return { { id = 11, name = "Path A", icon = 1 }, { id = 12, name = "Path B", icon = 2 } }
    end
    W.Fire(portals, "OnEnter")
    assert(popup.shown and popup.rows[1]:GetAttribute("type") == "spell" and popup.rows[2]:GetAttribute("spell") == 12
        and popup.rows[2].shown and not popup.rows[3].shown, "hovering the portal place did not list the learned portals")
    portals.mouseOver, popup.mouseOver = false, true
    W.Fire(portals, "OnLeave")
    W.Fire(popup, "OnLeave")
    W.Advance(.2)
    assert(popup.shown, "moving onto a portal row closed the popup")
    popup.mouseOver = false
    W.Fire(popup.rows[1], "OnLeave")
    W.Advance(.2)
    assert(not popup.shown and #popup.points == 0, "the popup stayed open after the pointer left it")
    W.Click(portals)
    assert(popup.shown, "clicking the portal place did not open the popup")
    W.Click(popup.rows[2])
    assert(W.secureActions[#W.secureActions].spell == 12 and not popup.shown, "a portal row did not cast its spell")
    -- Without the optional QualityOfLife export the place asks for it and opens nothing.
    S.LearnedDungeonPortals = nil
    W.Fire(portals, "OnEnter")
    assert(loaded[#loaded] == "MSUF_Suite_QualityOfLife" and not popup.shown,
        "a missing portal list opened a popup or did not request its addon")
    W.Fire(portals, "OnLeave")
    S.LearnedDungeonPortals = function() return { { id = 11, name = "Path A", icon = 1 } } end
    W.Click(portals)
    assert(popup.shown, "the portal popup did not reopen")
end

-- P1-4: "Out of combat" and "In combat" bars follow the client's combat
-- state through state drivers, also without load conditions.
local outOfCombat, inCombat = M.bars[2], M.bars[3]
assert(outOfCombat.visibilityDriver == "[combat] hide; show" and inCombat.visibilityDriver == "[nocombat] hide; show",
    "combat visibility modes did not use state drivers")
assert(outOfCombat.frame.shown and not inCombat.frame.shown, "combat visibility is wrong out of combat")

-- P0-1: combat starts while the overlay covers a place and the popup is open.
W.Fire(hearth, "OnEnter")
hearth.mouseOver = true
assert(overlay.shown, "the overlay did not attach before combat")
W.SetCombat(true)
assert(not overlay.shown and #overlay.points == 0, "the secure overlay still depends on a place in combat")
assert(not popup.shown and #popup.points == 0, "the secure popup still depends on a place in combat")
assert(not outOfCombat.frame.shown and inCombat.frame.shown, "combat visibility did not switch in combat")
-- A Fit-text bar relayouts in combat when the clock changes its width.
local width = bar.frame.width
minute, hour = 4, 23
G.GetGameTime = function() return hour, minute end
W.Advance(61)
assert(clock.text == "Time: 23:04", "the clock did not update in combat")
assert(bar.frame.width ~= nil and bar.frame.width >= width, "the Fit-text bar did not relayout in combat")
hearth.mouseOver = false
W.Fire(hearth, "OnLeave")
spec.mouseOver = true
W.Fire(spec, "OnEnter")
W.Click(spec)
assert(not overlay.shown and #overlay.points == 0, "the overlay attached in combat")
spec.mouseOver = false
W.Fire(spec, "OnLeave")
hearth.mouseOver = true
W.Fire(hearth, "OnEnter")
local actions = #W.secureActions
W.Click(hearth)
assert(#W.secureActions == actions and not overlay.shown, "a place performed a protected action in combat")
-- After combat the place under the pointer gets its overlay again.
W.SetCombat(false)
assert(overlay.shown and overlay.points[1][2] == hearth, "the overlay was not offered again after combat")
assert(outOfCombat.frame.shown and not inCombat.frame.shown, "combat visibility did not switch back")

-- Bag storms in combat never rescan the Hearthstone items (the overlay is
-- hidden); a Hearthstone looted in combat is offered right after combat.
hearth.mouseOver = false
W.Fire(hearth, "OnLeave")
local hearthCount, hearthReads = 0, 0
G.C_Item.GetItemCount = function(id)
    hearthReads = hearthReads + 1
    return id == 6948 and hearthCount or 0
end
W.Event("BAG_UPDATE_DELAYED")
assert(hearthReads > 0 and hearth.extra.hearth == nil, "an unowned Hearthstone stayed the place's choice")
W.SetCombat(true)
hearthReads, hearthCount = 0, 1
for _ = 1, 5 do W.Event("BAG_UPDATE_DELAYED"); W.Event("TOYS_UPDATED") end
assert(hearthReads == 0 and hearth.extra.hearth == nil, "bag updates in combat rescanned the Hearthstone items")
hearth.mouseOver = true
W.Fire(hearth, "OnEnter")
W.SetCombat(false)
assert(hearthReads > 0 and hearth.extra.hearth and hearth.extra.hearth.id == 6948,
    "a Hearthstone looted in combat was not chosen after combat")
assert(overlay.shown and overlay.points[1][2] == hearth and overlay:GetAttribute("item1") == "item:6948",
    "the Hearthstone looted in combat was not offered right after combat")
hearthReads = 0
W.SetCombat(true)
W.SetCombat(false)
assert(hearthReads == 0, "a combat without bag updates rescanned the Hearthstone items")

assert(S.Set("dataTexts", "enabled", false))
assert(not overlay.shown and #overlay.points == 0 and not popup.shown, "disabling DataTexts kept a secure frame")
print("Suite DataTexts client security: insecure places, secure overlay and popup, combat edges passed: " .. flavor)
