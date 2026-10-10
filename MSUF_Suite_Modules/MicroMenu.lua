local NS = assert(_G.MSUFSuite, "MSUF_Suite is required")
local S = NS.Suite
-- The Suite's one micro menu: which of Blizzard's micro buttons the Minimap's
-- middle-click flyout and the DataTexts "Micro menu" place offer, in which
-- order, under which label and whether each can be used. Both surfaces draw
-- the micro buttons as secure "click" rows: a row's hardware click makes
-- SecureActionButton_OnClick click the Blizzard micro button from secure
-- code, because a Blizzard panel opened from an addon's click runs tainted
-- and can later block talent changes or group finder sign-ups. The game menu
-- row is the one plain row (see GAME_MENU).
-- Listed are the micro buttons Blizzard put into its micro menu (the
-- layoutIndex MicroMenuMixin:AddButton sets) that are shown: Forever's menu
-- leaves PlayerSpellsMicroButton and AchievementMicroButton out, Retail's game
-- rules can drop others. Each entry: button name, Blizzard's label global,
-- English fallback.
local ENTRIES = {
    { "CharacterMicroButton", "CHARACTER_BUTTON", "Character" },
    { "ProfessionMicroButton", "PROFESSIONS_BUTTON", "Professions" },
    { "PlayerSpellsMicroButton", "PLAYER_SPELLS_BUTTON", "Talents and spellbook" },
    { "SpellbookMicroButton", "SPELLBOOK_ABILITIES_BUTTON", "Spellbook" },
    { "TalentMicroButton", "TALENTS_BUTTON", "Talents" },
    { "LegacyMicroButton", "LEGACY_BUTTON", "Legacy" },
    { "AchievementMicroButton", "ACHIEVEMENT_BUTTON", "Achievements" },
    { "QuestLogMicroButton", "QUESTLOG_BUTTON", "Quest log" },
    { "HousingMicroButton", "HOUSING_BUTTON", "Housing" },
    { "GuildMicroButton", "GUILD", "Guild" },
    { "LFDMicroButton", "DUNGEONS_BUTTON", "Group finder" },
    { "CollectionsMicroButton", "COLLECTIONS", "Collections" },
    { "EJMicroButton", "ADVENTURE_JOURNAL", "Adventure Guide" },
    { "HelpMicroButton", "HELP_BUTTON", "Help" },
    { "StoreMicroButton", "BLIZZARD_STORE", "Shop" },
}
-- The game menu button acts only while the cursor is over it
-- (MainMenuMicroButtonMixin:OnClick starts with self:IsMouseOver()), so a
-- secure click from a menu row does nothing. The DataTexts menu therefore
-- offers the game menu as a plain row (S3.2): its entry has an action and no
-- button. The Minimap does not offer it.
local GAME_MENU = { "MainMenuMicroButton", "MAINMENU_BUTTON", "Game menu" }

local function Usable(frame)
    return type(frame) == "table" and not NS.Safety.IsForbidden(frame)
end

-- Blizzard buttons whose own OnClick opens a Blizzard window the way the
-- player's click or key binding does; a secure "click" on one runs that
-- opener from secure code. CharacterMicroButton runs
-- ToggleCharacter("PaperDollFrame") (CharacterMicroButtonMixin:OnClick),
-- the minimap's zone text button runs ToggleWorldMap()
-- (MinimapZoneTextButtonMixin:OnClick, Blizzard_Minimap/Mainline), on
-- Retail and WoW Forever. On Retail the character window's currency tab runs
-- CharacterFrame:ToggleTokenFrame() (CharacterFrameTabButtonMixin:OnClick),
-- as the TOGGLECURRENCY binding does. WoW Forever has no such button: its
-- character window (Camelot/CharacterFrame.xml) has no CharacterFrameTab3,
-- and its currency side tab, CharacterFrameModeTab5, is a Frame that opens
-- the tab from OnMouseUp and has no Click for a secure "click". There the
-- currency places open the character window on its last tab
-- (S.TogglePanel). The Suite's minimap leaves the zone text button shown at
-- alpha 0 (Context:HideControl), so it stays clickable.
local PANEL_BUTTONS = {
    character = function() return _G.CharacterMicroButton end,
    worldMap = function()
        local cluster = _G.MinimapCluster
        return Usable(cluster) and cluster.ZoneTextButton or nil
    end,
    -- Blizzard_UIPanels_Game creates the character window at startup.
    currency = function() return CharacterFrameTab3 end,
}
-- A tab of a closed window is shown but not visible: TokenFrameMixin:Update
-- shows the currency tab while the player has currencies.
local WINDOW_TABS = { currency = true }
-- WoW Forever's Gamepad UI (S.GamepadUI, Dialogs.lua) hides the micro menu
-- and the bag bar (MainActionBar_InitializeGamepad, Blizzard_ActionBar/
-- Shared/MainActionBar.lua: MicroMenu:Hide(), BagsBar:Hide()), so their
-- buttons are shown but never visible. A hidden button still takes Click():
-- Blizzard's own gamepad radial clicks these micro buttons there
-- (MicroMenuButtonHandler:action, Blizzard_Gamepad/UI/Radials/
-- GamepadRadial.lua: self.button:Click("LeftButton")). Under the Gamepad UI a
-- button therefore counts while it is shown and enabled, and a window whose
-- usual button is missing, or that the Suite opens from its own code
-- elsewhere, opens through one of these Blizzard buttons instead:
--   bags        MainMenuBarBackpackButton: BaseBagSlotButtonMixin:BagSlotOnClick
--               runs ToggleBag(0), the combined bags as the radial's
--               ToggleBackpack_Combined (a held item goes into the backpack);
--   calendar    GameTimeFrame: GameTimeFrame_OnClick runs ToggleCalendar
--               (Blizzard_Minimap/Mainline/GameTime.lua);
--   clock       TimeManagerClockButton: TimeManagerClockButton_OnClick runs
--               TimeManager_Toggle (Blizzard_TimeManager, loaded at login);
--   professions ProfessionMicroButton: ToggleProfessionsBook;
--   questLog    QuestLogMicroButton: ToggleQuestLog, the world map with its
--               quest log (Blizzard_WorldMap);
--   journal     EJMicroButton: ToggleEncounterJournal;
--   currency    CharacterMicroButton: Forever has no currency tab button
--               (above), so the character window opens on its paper doll;
--   worldMap    QuestLogMicroButton while the zone text button is missing.
local function QuestLogButton() return QuestLogMicroButton end
local GAMEPAD_BUTTONS = {
    bags = function() return MainMenuBarBackpackButton end,
    calendar = function() return GameTimeFrame end,
    clock = function() return TimeManagerClockButton end,
    professions = function() return ProfessionMicroButton end,
    questLog = QuestLogButton,
    journal = function() return EJMicroButton end,
    currency = function() return CharacterMicroButton end,
    worldMap = QuestLogButton,
}

local function Ready(button, panel, gamepad)
    if not Usable(button) then return false end
    local visible
    if WINDOW_TABS[panel] or gamepad then visible = button:IsShown() else visible = button:IsVisible() end
    local enabled = button:IsEnabled()
    return S.Public(visible) and visible == true and S.Public(enabled) and enabled == true
end

-- The Blizzard button that opens panel ("character", "worldMap" or
-- "currency"; under the Gamepad UI also the GAMEPAD_BUTTONS panels), or nil
-- while it is missing, forbidden, hidden or disabled: the caller then opens
-- the window through S.TogglePanel. Out of combat, when a place offers its
-- secure click.
function S.PanelButton(panel)
    local gamepad = S.GamepadUI()
    local find = PANEL_BUTTONS[panel]
    local button = find and find()
    if Ready(button, panel, gamepad) then return button end
    if not gamepad then return nil end
    find = GAMEPAD_BUTTONS[panel]
    button = find and find()
    if Ready(button, panel, gamepad) then return button end
end

-- Whether the Suite's own code may open or close a Blizzard window now: the
-- panel manager refuses addon calls in combat lockdown
-- (CheckProtectedFunctionsAllowed, UIParentPanelManager.lua on every client:
-- "Interface action failed because of an AddOn"), and under the Gamepad UI
-- such a call leaves the frame controls manager tainted (Dialogs.lua).
function S.CanOpenNativeWindow()
    return not NS.IsCombatLocked() and not S.GamepadUI()
end

-- Opens or closes the window of panel without Blizzard's button: a place
-- whose S.PanelButton is missing, or a click that cannot be secure (the
-- minimap's middle-click). ToggleWorldMap and ToggleCharacter would run the
-- world map's display-state code (QuestLogOwnerMixin:HandleUserActionToggleSelf)
-- and CharacterFrame's tab and sub-frame code inside the addon's call.
-- ShowUIPanel and HideUIPanel hand both windows, panels of Blizzard's panel
-- manager (RegisterUIPanel, UIPanelWindows), to the secure
-- FramePositionDelegate: the map opens as OpenWorldMap opens it
-- (HandleUserActionOpenSelf), the character window on the tab the player
-- used last. The game rules that disable a window are honoured, and the
-- panel manager refuses addon calls in combat. Blizzard_WorldMap and
-- Blizzard_UIPanels_Game load at startup on Retail and WoW Forever. Under the
-- Gamepad UI nothing opens from here (S.CanOpenNativeWindow): the places
-- click Blizzard's buttons instead (S.PanelButton).
function S.TogglePanel(panel)
    if not S.CanOpenNativeWindow() then return end
    local window, rule = CharacterFrame, Enum.GameRule.CharacterPanelDisabled
    if panel == "worldMap" then window, rule = WorldMapFrame, Enum.GameRule.WorldMapDisabled end
    if C_GameRules.IsGameRuleActive(rule) then return end
    S.Dispatch(NS.Finish, window:IsShown() and HideUIPanel or ShowUIPanel, window)
end

-- Opens or closes the game menu out of combat, as GameMenuFrame_Show and
-- GameMenuFrame_EscapePressed do (Blizzard_GameMenu): ShowUIPanel and
-- HideUIPanel hand GameMenuFrame to Blizzard's secure FramePositionDelegate,
-- so its OnShow builds the menu buttons from secure code. The panel manager
-- refuses addon calls in combat. Blizzard_GameMenu loads at startup on Retail
-- and WoW Forever. Under the Gamepad UI the game menu stays with the pad's
-- own menu button (S.CanOpenNativeWindow): no secure click reaches it,
-- because MainMenuMicroButtonMixin:OnClick needs the cursor over the button.
function S.ToggleGameMenu()
    if not S.CanOpenNativeWindow() then return end
    if GameMenuFrame:IsShown() then
        PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
        S.Dispatch(NS.Finish, HideUIPanel, GameMenuFrame)
    else
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        S.Dispatch(NS.Finish, ShowUIPanel, GameMenuFrame)
    end
end

local function Put(list, count, button, entry, action)
    local item = list[count]
    if not item then
        item = {}
        list[count] = item
    end
    local enabled = button:IsEnabled()
    item.button, item.action = not action and button or nil, action
    item.label = S.BlizzardText(entry[2], entry[3])
    -- The plain game menu row runs addon code: shown but off under the
    -- Gamepad UI (S.ToggleGameMenu).
    item.enabled = S.Public(enabled) and enabled == true and not (action and S.GamepadUI())
end

-- Fills list with the offered entries in Blizzard's order: list[i] is
-- { button, action, label, enabled }, the tables reused across calls (entries
-- past the returned count are stale). A row clicks entry.button through its
-- secure "click" action, or runs entry.action (a plain row) when the entry
-- has no button. gameMenu also offers the game menu, last, as a plain row
-- that follows the enabled state of Blizzard's game menu button. Returns the
-- number of entries. Out of combat, when a menu opens.
function S.MicroMenuEntries(list, gameMenu)
    local count = 0
    for i = 1, #ENTRIES do
        local entry = ENTRIES[i]
        local button = _G[entry[1]]
        if Usable(button) and button.layoutIndex ~= nil and button:IsShown() then
            count = count + 1
            Put(list, count, button, entry)
        end
    end
    local game = gameMenu and _G[GAME_MENU[1]]
    if Usable(game) then
        count = count + 1
        Put(list, count, game, GAME_MENU, S.ToggleGameMenu)
    end
    return count
end
