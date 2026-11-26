local _, P = ...
local NS, S = P.NS, P.Suite
local Data = NS.ActionBarFlyouts
local Sources = {}
P.ActionBars.FlyoutSources = Sources

local Public, Finite = S.Public, S.Finite
local FOREVER = NS.Client.isForever
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local CONSUMABLE, KEY = 0, 13 -- Enum.ItemClass
local SUBCLASSES = { food = 5, potion = 1, bandage = 7 } -- Enum.ItemConsumableSubclass

local function Rank(id)
    local _, _, _, level, minimum = C_Item.GetItemInfo(id)
    return (Finite(minimum) and minimum or 0) * 10000 + (Finite(level) and level or 0)
end

local function Matches(group, id)
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    if not Finite(class) then return false end
    if group == "keys" then return class == KEY end
    if class ~= CONSUMABLE or not Finite(subclass) or subclass ~= SUBCLASSES[group] then return false end
    local usable = C_Item.IsUsableItem(id)
    return Public(usable) and usable == true
end

-- Retail's ChallengesKeystoneSlotMixin:OnReceiveDrag accepts a keystone
-- from the cursor (Blizzard_ChallengesUI/Mainline/Blizzard_ChallengesUI.lua
-- at ab5cb850a3f65e742959e379c4689353a2f4549f). Its link identifies it across seasons.
local function KeystoneLink(bag, slot)
    local link = S.PublicText(C_Container.GetContainerItemLink(bag, slot))
    if link and link:find("|Hkeystone:", 1, true) then return link end
end

local function ReadBag(found, seen, group, bag, slots, keyring)
    for slot = 1, Finite(slots) and math.min(slots, 200) or 0 do
        local id = C_Container.GetContainerItemID(bag, slot)
        if Finite(id) and id > 0 and not seen[id] then
            if group == "keystone" then
                local link = KeystoneLink(bag, slot)
                if link then
                    found[#found + 1] = { id = id, bag = bag, slot = slot, link = link }
                    seen[id] = true
                end
            elseif keyring or Matches(group, id) then
                found[#found + 1] = { id = id, rank = Rank(id) }
                seen[id] = true
            end
        end
    end
end

function Sources.BagItems(group)
    local found, seen = {}, {}
    if (group == "keys" and not FOREVER) or (group == "keystone" and FOREVER) then return found end
    for bag = 0, LAST_BAG do
        ReadBag(found, seen, group, bag, C_Container.GetContainerNumSlots(bag))
    end
    -- Camelot/MainMenuBarBagButtons.lua reads this native container the same way.
    if group == "keys" and Finite(KEYRING_CONTAINER) then
        ReadBag(found, seen, group, KEYRING_CONTAINER, C_Container.GetContainerNumSlots(KEYRING_CONTAINER), true)
    end
    table.sort(found, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.id > b.id
    end)
    return found
end

function Sources.KeystoneStillInSlot(item)
    return KeystoneLink(item.bag, item.slot) == item.link
end

-- Blizzard_ActionBar/Shared/SpellFlyout.lua uses the known flag and base spell
-- for casting, with the override for the icon (live ab5cb850a3f65e742959e379c4689353a2f4549f,
-- Forever c01a87b549bbc19e0f284c1616d18654c91297de).
local function ReadNative(spells, id)
    local _, _, slots = GetFlyoutInfo(id)
    if not Finite(slots) or slots < 1 or slots > Data.MAX_ENTRIES then return end
    for index = 1, slots do
        local spell, override, known = GetFlyoutSlotInfo(id, index)
        if Public(known) and known == true and Finite(spell) and spell > 0 then
            spells[#spells + 1] = { id = spell, iconSpell = Finite(override) and override > 0 and override or spell }
        end
    end
end

-- Forever also presents individual trainer spells in the spellbook.
-- The original capital spells and the learned Dalaran teleport (1308652).
local FOREVER_MAGE_SPELLS = {
    magePortals = { 10059, 11416, 11419, 11417, 11418, 11420 },
    mageTeleports = { 3561, 3562, 3565, 3567, 3563, 3566, 1308652 },
}

-- Highest known rank first for ranked utility. Each group contributes one button.
local SHAMAN_UTILITY = { { 8012, 370 }, { 8143 }, { 8177 }, { 8166 }, { 8170 }, { 526 }, { 2870 } }
local function ShamanUtility(spells)
    local _, class = UnitClass("player")
    if not Public(class) or class ~= "SHAMAN" then return end
    for _, ranks in ipairs(SHAMAN_UTILITY) do
        for _, spell in ipairs(ranks) do
            local known = IsPlayerSpell(spell)
            if Public(known) and known == true then
                spells[#spells + 1] = { id = spell }
                break
            end
        end
    end
end

function Sources.BookSpells(group)
    local spells = {}
    local mageBooks = Data.MAGE_BOOKS[group]
    if mageBooks then
        local _, class = UnitClass("player")
        if not Public(class) or class ~= "MAGE" then return spells end
        for _, id in ipairs(mageBooks) do ReadNative(spells, id) end
        if FOREVER then
            for _, id in ipairs(FOREVER_MAGE_SPELLS[group]) do
                local known = IsPlayerSpell(id)
                if Public(known) and known == true then spells[#spells + 1] = { id = id } end
            end
        end
    elseif group == Data.SHAMAN_BOOK then
        if FOREVER then ShamanUtility(spells) end
    elseif group == "dungeonSeason" then
        local book = NS.DungeonPortalBook
        if book then
            local learned, _, season = book.Read()
            if season then spells = book.ForSeason(learned, season) end
        end
    elseif not FOREVER then
        ReadNative(spells, group)
    end
    return spells
end
