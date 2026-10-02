local NS = assert(_G.MSUFSuite, "MSUF_Suite is required")
local S = NS.Suite
-- The Suite's one micro menu: which of Blizzard's micro buttons the Minimap's
-- middle-click flyout and the DataTexts "Micro menu" place offer, in which
-- order, under which label and whether each can be used. Both surfaces draw
-- these entries as secure "click" rows: a row's hardware click makes
-- SecureActionButton_OnClick click the Blizzard micro button from secure
-- code, because a Blizzard panel opened from an addon's click runs tainted
-- and can later block talent changes or group finder sign-ups.
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
-- secure click from a menu row does nothing and the Minimap does not offer
-- it. The DataTexts menu keeps its "Game menu" row (an owner decision, S3.2).
local GAME_MENU = { "MainMenuMicroButton", "MAINMENU_BUTTON", "Game menu" }

local function Usable(frame)
    return type(frame) == "table" and not NS.Safety.IsForbidden(frame)
end

local function Put(list, count, button, entry)
    local item = list[count]
    if not item then
        item = {}
        list[count] = item
    end
    local enabled = button:IsEnabled()
    item.button, item.label = button, S.BlizzardText(entry[2], entry[3])
    item.enabled = S.Public(enabled) and enabled == true
end

-- Fills list with the offered entries in Blizzard's order: list[i] is
-- { button, label, enabled }, the tables reused across calls (entries past
-- the returned count are stale). gameMenu also offers the game menu button,
-- last. Returns the number of entries. Out of combat, when a menu opens.
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
        Put(list, count, game, GAME_MENU)
    end
    return count
end
