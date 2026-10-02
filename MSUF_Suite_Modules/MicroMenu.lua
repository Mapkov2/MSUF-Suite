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

-- Opens or closes the game menu out of combat, as GameMenuFrame_Show and
-- GameMenuFrame_EscapePressed do (Blizzard_GameMenu): ShowUIPanel and
-- HideUIPanel hand GameMenuFrame to Blizzard's secure FramePositionDelegate,
-- so its OnShow builds the menu buttons from secure code. The panel manager
-- refuses addon calls in combat. Blizzard_GameMenu loads at startup on Retail
-- and WoW Forever.
function S.ToggleGameMenu()
    if NS.IsCombatLocked() then return end
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
    item.enabled = S.Public(enabled) and enabled == true
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
