local _, NS = ...
if NS.Client.isForever then return end

-- Shared spellbook discovery for the minimap and action bar presets.
local Public, Finite, Text = NS.Public, NS.Finite, NS.PublicText
-- Public spell records identify these dungeon teleport flyouts. The client
-- supplies their complete learned contents, localized labels and spell data.
-- Source: nether.wowhead.com/tooltip/spell/<id>, verified 2026-09-30.
local SEEDS = { [131204] = true, [159898] = true, [354464] = true,
    [393273] = true, [410071] = true, [410078] = true, [410080] = true,
    [424142] = true, [424153] = true, [424163] = true, [424167] = true,
    [445269] = true, [445418] = true, [1254400] = true, [1254572] = true,
    [1254555] = true, [1254551] = true }

-- Destination facts verified against public spell tooltips and Raider.IO
-- /api/v1/mythic-plus/static-data. Native GetMapUIInfo resolves game map IDs.
local CHALLENGES = {
    [159896] = 169, -- Iron Docks
    [159898] = 161, -- Skyreach
    [159899] = 165, -- Shadowmoon Burial Grounds
    [159900] = 166, -- Grimrail Depot
    [159901] = 168, -- The Everbloom
    [354462] = 376, -- The Necrotic Wake
    [354463] = 379, -- Plaguefall
    [354464] = 375, -- Mists of Tirna Scithe
    [354465] = 378, -- Halls of Atonement
    [354466] = 381, -- Spires of Ascension
    [354467] = 382, -- Theater of Pain
    [354468] = 377, -- De Other Side
    [354469] = 380, -- Sanguine Depths
    [393256] = 399, -- Ruby Life Pools
    [393262] = 400, -- The Nokhud Offensive
    [393267] = 405, -- Brackenhide Hollow
    [393273] = 402, -- Algeth'ar Academy
    [393276] = 404, -- Neltharus
    [393279] = 401, -- The Azure Vault
    [393283] = 406, -- Halls of Infusion
    [393222] = 403, -- Uldaman: Legacy of Tyr
    [410071] = 245, -- Freehold
    [410078] = 206, -- Neltharion's Lair
    [410080] = 438, -- The Vortex Pinnacle
    [424142] = 456, -- Throne of the Tides
    [424153] = 199, -- Black Rook Hold
    [424163] = 198, -- Darkheart Thicket
    [424167] = 248, -- Waycrest Manor
    [445269] = 501, -- The Stonevault
    [445418] = 353, -- Siege of Boralus
    [445416] = 502, -- City of Threads
    [445414] = 505, -- The Dawnbreaker
    [445424] = 507, -- Grim Batol
    [445443] = 500, -- The Rookery
    [445444] = 499, -- Priory of the Sacred Flame
    [445440] = 506, -- Cinderbrew Meadery
    [445441] = 504, -- Darkflame Cleft
    [1254400] = 557, -- Windrunner Spire
    [1254572] = 558, -- Magisters' Terrace
    [1254555] = 556, -- Pit of Saron
    [1254551] = 239, -- Seat of the Triumvirate
    [1254557] = 161, -- Skyreach
    [1254559] = 560, -- Maisara Caverns
    [1254563] = 559, -- Nexus-Point Xenas
    [1286801] = 584, -- The Blinding Vale
    [1286804] = 585, -- Voidscar Arena
    [1286807] = 586, -- Den of Nalorakk
    [1286809] = 587, -- Murder Row
    [1286812] = 588, -- Altar of Fangs
    [1286828] = 250, -- Temple of Sethraliss
    [1286831] = 249, -- Kings' Rest
}
for spell in pairs(CHALLENGES) do SEEDS[spell] = true end

local function Field(data, key)
    if Public(data) and type(data) == "table" and Public(data[key]) then return data[key] end
end

-- A dungeon name the way spell descriptions quote it ("Teleport to the
-- entrance of the Stonevault", "... der Steingruft"): lower case, without a
-- leading article or a wing after ":" ("Tazavesh: Streets of Wonder").
-- Names shorter than four letters match nothing.
local ARTICLES = { the = true, der = true, die = true, das = true, le = true, la = true, les = true,
    el = true, los = true, las = true, il = true, lo = true, gli = true, os = true, as = true, o = true, a = true }
local function Quoted(name)
    local text = name:lower():match("^[^:]*")
    local first, rest = text:match("^(%S+)%s+(.+)$")
    if first and ARTICLES[first] then text = rest end
    text = text:gsub("^l'", ""):gsub("^l\226\128\153", "")
    return #text >= 4 and text or false
end

-- MapOf's answers per spell for the season Season() read last; a
-- description the client has not loaded yet is read again next time.
local described, describedFor = {}, nil

-- The current Mythic+ season as the client's Mythic+ tab lists it:
-- { [challenge map] = quoted native name or false }, or nil while the client
-- has not sent it yet. The first miss asks for it once;
-- CHALLENGE_MODE_MAPS_UPDATE reports its arrival. key names the season.
local seasonRequested
local function Season()
    local maps = C_ChallengeMode.GetMapTable()
    local season, ids = nil, {}
    if Public(maps) and type(maps) == "table" then
        for i = 1, math.min(#maps, 32) do
            local map = maps[i]
            if Finite(map) then
                local name = Text((C_ChallengeMode.GetMapUIInfo(map)))
                season = season or {}
                season[map] = name and Quoted(name) or false
                ids[#ids + 1] = map
            end
        end
    end
    if not season and not seasonRequested then
        seasonRequested = true
        C_MythicPlus.RequestMapInfo()
    end
    table.sort(ids)
    local key = table.concat(ids, ",")
    if key ~= describedFor then described, describedFor = {}, key end
    return season, key
end

-- The challenge map a portal leads to: its verified destination, or else
-- the season dungeon whose quoted name its native description holds
-- ("Teleport to the entrance of <dungeon>"), the longest name when several
-- fit. A new season's portals therefore need no new CHALLENGES entry; the
-- group-join suggestion still uses only verified destinations.
local function MapOf(spellID, season)
    local map = CHALLENGES[spellID]
    if map or not season then return map end
    if described[spellID] ~= nil then return described[spellID] or nil end
    local text = Text(C_Spell.GetSpellDescription(spellID))
    if not text then return nil end
    text = text:lower()
    local best, length = false, 0
    for id, name in pairs(season) do
        if name and #name > length and text:find(name, 1, true) then best, length = id, #name end
    end
    described[spellID] = best
    return best or nil
end

local function AddSpell(spells, spellID, unlearned)
    if not Finite(spellID) or spells[spellID] then return end
    local known = C_SpellBook.IsSpellKnown(spellID)
    if not Public(known) or known ~= true then
        if unlearned then unlearned[spellID] = true end
        return
    end
    local info = C_Spell.GetSpellInfo(spellID)
    local name = Text(Field(info, "name"))
    if not name then return end
    local destination, mapID
    if CHALLENGES[spellID] then
        local dungeon, _, _, _, _, gameMap = C_ChallengeMode.GetMapUIInfo(CHALLENGES[spellID])
        destination = Text(dungeon)
        if Finite(gameMap) and gameMap > 0 then mapID = gameMap end
    end
    spells[spellID] = { id = spellID, name = name, icon = Field(info, "iconID"), mapID = mapID,
        destination = destination or Text(C_Spell.GetSpellSubtext(spellID)) }
end

-- A flyout holds dungeon teleports when it holds a seed or, like the flyout
-- of a new expansion, a portal to a current season dungeon (MapOf).
local function ReadFlyout(spells, id, season, unlearned)
    if not Finite(id) then return end
    local _, _, count = GetFlyoutInfo(id)
    if not Finite(count) or count < 1 or count > 100 then return end
    local slots, recognized = {}, false
    for i = 1, count do
        local spell, override = GetFlyoutSlotInfo(id, i)
        if Finite(spell) then
            recognized = recognized or SEEDS[spell] == true
            slots[#slots + 1] = Finite(override) and override > 0 and override or spell
        end
    end
    if season and not recognized then
        for _, spell in ipairs(slots) do
            if MapOf(spell, season) then
                recognized = true
                break
            end
        end
    end
    if recognized then for _, spell in ipairs(slots) do AddSpell(spells, spell, unlearned) end end
end

-- The learned portals by name, the season key and the season they were read
-- with. unlearned (optional) collects the portals not learned yet.
local function LearnedPortals(unlearned)
    local season, key = Season()
    local spells = {}
    for spell in pairs(SEEDS) do AddSpell(spells, spell, unlearned) end
    local lines = C_SpellBook.GetNumSpellBookSkillLines()
    if Finite(lines) then
        for i = 1, math.min(lines, 20) do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            local offset, count = Field(line, "itemIndexOffset"), Field(line, "numSpellBookItems")
            if Finite(offset) and Finite(count) then
                for slot = offset + 1, offset + math.min(count, 500) do
                    local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                    if Field(item, "itemType") == Enum.SpellBookItemType.Flyout then
                        ReadFlyout(spells, Field(item, "actionID"), season, unlearned)
                    end
                end
            end
        end
    end
    local ordered = {}
    for _, spell in pairs(spells) do ordered[#ordered + 1] = spell end
    table.sort(ordered, function(a, b) return a.name < b.name end)
    return ordered, key, season
end

-- The season keeps one learned portal per map, preferring its newer spell.
local function ForSeason(spells, season)
    local shown, slot = {}, {}
    for _, spell in ipairs(spells) do
        local map = MapOf(spell.id, season)
        if map and season[map] ~= nil then
            local index = slot[map]
            if not index then
                shown[#shown + 1] = spell
                slot[map] = #shown
            elseif spell.id > shown[index].id then
                shown[index] = spell
            end
        end
    end
    return shown
end

NS.DungeonPortalBook = {
    Read = LearnedPortals,
    Season = Season,
    ForSeason = ForSeason,
    MapOf = MapOf,
    Field = Field,
}
