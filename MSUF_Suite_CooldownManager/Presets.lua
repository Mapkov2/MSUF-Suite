local _, P = ...
local C = P.CDM
-- Default contents of the Defensives bar: personal defensive cooldowns per
-- class (classID), strongest first, then the class's raid-wide damage
-- reduction. Talent choices and replaced spells are listed side by side:
-- the bar only shows spells the character knows, so an entry for another
-- build costs nothing. Healer throughput cooldowns and externals stay on the
-- Blizzard bars. A user list for the bar replaces this default.
local Presets = {}
C.Presets = Presets
local SPELL_CATEGORY = C.Const.SPELL_CATEGORY

local DEFENSIVES = {
    [1] = { -- Warrior
        871,     -- Shield Wall
        12975,   -- Last Stand
        118038,  -- Die by the Sword
        184364,  -- Enraged Regeneration
        383762,  -- Bitter Immunity
        23920,   -- Spell Reflection
        392966,  -- Spell Block
        1160,    -- Demoralizing Shout
        97462,   -- Rallying Cry
    },
    [2] = { -- Paladin
        642,     -- Divine Shield
        31850,   -- Ardent Defender
        86659,   -- Guardian of Ancient Kings
        212641,  -- Guardian of Ancient Kings (glyphed)
        389539,  -- Sentinel
        387174,  -- Eye of Tyr
        498,     -- Divine Protection
        403876,  -- Divine Protection (Retribution)
        184662,  -- Shield of Vengeance
        205191,  -- Eye for an Eye
        633,     -- Lay on Hands
    },
    [3] = { -- Hunter
        186265,  -- Aspect of the Turtle
        264735,  -- Survival of the Fittest
        109304,  -- Exhilaration
    },
    [4] = { -- Rogue
        31224,   -- Cloak of Shadows
        5277,    -- Evasion
        199754,  -- Riposte
        1966,    -- Feint
        185311,  -- Crimson Vial
    },
    [5] = { -- Priest
        47585,   -- Dispersion
        19236,   -- Desperate Prayer
        586,     -- Fade
        15286,   -- Vampiric Embrace
    },
    [6] = { -- Death Knight
        48792,   -- Icebound Fortitude
        55233,   -- Vampiric Blood
        48707,   -- Anti-Magic Shell
        49039,   -- Lichborne
        48743,   -- Death Pact
        219809,  -- Tombstone
        194679,  -- Rune Tap
        51052,   -- Anti-Magic Zone
    },
    [7] = { -- Shaman
        108271,  -- Astral Shift
        108270,  -- Stone Bulwark Totem
        198103,  -- Earth Elemental
    },
    [8] = { -- Mage
        45438,   -- Ice Block
        414658,  -- Ice Cold
        342245,  -- Alter Time
        110959,  -- Greater Invisibility
        55342,   -- Mirror Image
        235450,  -- Prismatic Barrier
        235313,  -- Blazing Barrier
        11426,   -- Ice Barrier
        414660,  -- Mass Barrier
    },
    [9] = { -- Warlock
        104773,  -- Unending Resolve
        108416,  -- Dark Pact
        132413,  -- Shadow Bulwark
        17767,   -- Shadow Bulwark (pet)
    },
    [10] = { -- Monk
        115203,  -- Fortifying Brew
        243435,  -- Fortifying Brew
        122470,  -- Touch of Karma
        115176,  -- Zen Meditation
        122278,  -- Dampen Harm
        122783,  -- Diffuse Magic
    },
    [11] = { -- Druid
        61336,   -- Survival Instincts
        22812,   -- Barkskin
        102558,  -- Incarnation: Guardian of Ursoc
        200851,  -- Rage of the Sleeper
        108238,  -- Renewal
        22842,   -- Frenzied Regeneration
    },
    [12] = { -- Demon Hunter
        198589,  -- Blur
        196555,  -- Netherwalk
        187827,  -- Metamorphosis (Vengeance)
        204021,  -- Fiery Brand
        263648,  -- Soul Barrier
        196718,  -- Darkness
    },
    [13] = { -- Evoker
        363916,  -- Obsidian Scales
        374348,  -- Renewing Blaze
        374227,  -- Zephyr
    },
}
Presets.DEFENSIVES = DEFENSIVES

-- Raid essentials for Retail 12.1. Each row is a specialization ID and is
-- intentionally short: major throughput windows and the buttons needed to
-- prepare them. Talent alternatives may coexist; Resolve shows only learned
-- spells. Personal defensives, consumables and racials have their own bars.
-- Sources: current Wowhead Midnight Season 2 rotation/cooldown guides. The
-- Warcraft Logs candidate reports in the local audit still need cast/buff
-- verification. The client's CooldownViewer catalog decides which spell can
-- be tracked.
local RAID_ESSENTIALS = {
    [62] = { 365350, 321507, 12051 },                         -- Arcane Mage
    [63] = { 190319, 153561, 108853 },                        -- Fire Mage
    [64] = { 205021, 153595, 84714 },                         -- Frost Mage: Comet Storm replaces Ray of Frost after use
    [65] = { 31884, 375576, 31821, 114165, 200025, 6940 },      -- Holy Paladin, incl. Blessing of Sacrifice
    [66] = { 31884, 389539, 375576, 432472 },                  -- Protection Paladin: Avenging Wrath / Sentinel choice
    [70] = { 31884, 375576, 343527, 255937, 427453 },          -- Retribution Paladin
    [71] = { 107574, 167105, 227847, 1269383 },               -- Arms Warrior
    [72] = { 1719, 107574, 227847, 385059 },                   -- Fury Warrior
    [73] = { 107574, 385952, 2565 },                          -- Protection Warrior
    [102] = { 194223, 102560, 202770, 205636, 391528 },        -- Balance Druid
    [103] = { 106951, 102543, 274837, 5217, 391528 },          -- Feral Druid: current Convoke talent spell
    [104] = { 50334, 204066, 391528, 1261870 },                -- Guardian Druid
    [105] = { 740, 33891, 391528, 132158, 102342 },            -- Restoration Druid, incl. Nature's Swiftness and Ironbark
    [250] = { 49028, 439843 },                               -- Blood Death Knight
    [251] = { 51271, 439843, 47568, 279302, 1249658, 196770 }, -- Frost Death Knight: Deathbringer and Breath options
    [252] = { 42650, 1233448, 1247378 },                    -- Unholy Death Knight
    [253] = { 19574, 34026, 466930 },                       -- Beast Mastery Hunter
    [254] = { 288613, 19434, 257044, 212431, 260243, 466930 }, -- Marksmanship Hunter: Explosive Shot / Volley choices
    [255] = { 1250646, 259495, 1261193 },                   -- Survival Hunter
    [256] = { 472433, 421453, 194509, 10060, 62618, 33206 },   -- Discipline Priest, incl. Barrier and Pain Suppression
    [257] = { 64843, 47788, 200183, 120517, 10060 },           -- Holy Priest, incl. Power Infusion
    [258] = { 10060, 228260, 263165, 120644 },                -- Shadow Priest
    [259] = { 360194, 385627, 1856, 5938 },                    -- Assassination Rogue: Shiv for Deathstalker
    [260] = { 13750, 315508, 1277933, 51690, 13877, 381989 },  -- Outlaw Rogue
    [261] = { 185313, 121471, 280719, 426591, 1856 },          -- Subtlety Rogue
    [262] = { 191634, 114050, 198067, 443454 },               -- Elemental Shaman
    [263] = { 384352, 114051, 197214, 444995 },               -- Enhancement Shaman: Ascendance replaces Doom Winds
    [264] = { 114052, 98008, 108280, 378081, 444995 },         -- Restoration Shaman: Surging Totem for Totemic
    [265] = { 1257052, 442726, 205180 },                     -- Affliction Warlock
    [266] = { 265187, 104316, 1276452, 1276467, 1276672 },     -- Demonology Warlock
    [267] = { 1122, 80240, 152108, 442726 },                  -- Destruction Warlock
    [268] = { 132578, 325153, 1241059, 119582 },              -- Brewmaster Monk
    [269] = { 1249625, 123904, 1251001, 322109, 443028 },      -- Windwalker Monk: Zenith, Xuen, Fists of Fury, Touch of Death, Conduit
    [270] = { 116680, 115310, 388615, 322118, 325197, 116849, 443028 }, -- Mistweaver Monk: Revival/Restoral, Yu'lon/Chi-Ji, Cocoon, Conduit
    [577] = { 191427, 198013, 258860, 370965 },               -- Havoc Demon Hunter
    [581] = { 212084, 207407, 390163 },                       -- Vengeance Demon Hunter
    [1467] = { 375087, 357210, 433874, 357208, 359073, 370553 }, -- Devastation Evoker: base and steerable Deep Breath
    [1468] = { 370537, 359816, 363534, 370553, 357170 },       -- Preservation Evoker, incl. Time Dilation
    [1473] = { 395152, 403631, 409311, 404977, 370553 },       -- Augmentation Evoker, incl. Tip the Scales
    [1480] = { 1217605, 473728, 1221150, 1246167 },          -- Devourer Demon Hunter: cast, not the 1217607 aura
}
Presets.RAID_ESSENTIALS = RAID_ESSENTIALS

function Presets.RaidEssentials(specID)
    return RAID_ESSENTIALS[specID]
end

-- Active racial abilities, appended to the Potions and racials bar. Retail's
-- Blizzard catalog does not list them; only the character's own racial is
-- known. WoW Forever keeps the Vanilla IDs (the last group), and its catalog
-- lists the racial as a Utility record hidden by default (Perception 20600,
-- in game): the preset claims that record for this bar.
local RACIALS = {
    7744,    -- Will of the Forsaken
    20549,   -- War Stomp
    20572, 33697, 33702, -- Blood Fury
    28730, 25046, 50613, 69179, 80483, 129597, 155145, 202719, 232633, -- Arcane Torrent
    20594,   -- Stoneform
    26297,   -- Berserking
    28880, 59542, 59543, 59544, 59545, 59547, 59548, 121093, 370626, 416250, -- Gift of the Naaru
    58984,   -- Shadowmeld
    59752,   -- Will to Survive
    265221,  -- Fireblood
    20589,   -- Escape Artist
    255654,  -- Bull Rush
    68992,   -- Darkflight
    69070,   -- Rocket Jump
    107079,  -- Quaking Palm
    274738,  -- Ancestral Call
    255647,  -- Light's Judgment
    256948,  -- Spatial Rift
    260364,  -- Arcane Pulse
    287712,  -- Haymaker
    291944,  -- Regeneratin'
    312411,  -- Bag of Tricks
    312924,  -- Hyper Organic Light Originator
    357214,  -- Wing Buffet
    368970,  -- Tail Swipe
    436344,  -- Azerite Surge
    1237885, 1287685, -- Haranir racial
    -- WoW Forever (Vanilla IDs)
    20600,   -- Perception
    20580,   -- Shadowmeld
    20577,   -- Cannibalize
    20554, 26296, -- Berserking
}
Presets.RACIALS = RACIALS

-- Bag consumables on the Potions and racials bar, in this order after
-- Blizzard's entries and before the racial. Warlocks with Pact of Gluttony
-- create the Demonic Healthstone. Each one stands in for Blizzard's record
-- of its spellCategory while the catalog has no learned record, and shows
-- only while the bags hold it (hideEmpty).
Presets.CONSUMABLES = {
    { item = 5512, category = SPELL_CATEGORY.HEALTHSTONE },
    { item = 224464, category = SPELL_CATEGORY.DEMONIC_HEALTHSTONE },
}

-- Bag items behind Blizzard's potion and healthstone entries (spellCategory),
-- every quality rank: their counts add up to the number shown on the icon.
Presets.CATEGORY_ITEMS = {
    [SPELL_CATEGORY.COMBAT_POTION] = { 241308, 241309, 245897, 245898, 241288, 241289, 245902, 245903, 271886, 271887, 274763, 274764 },
    [SPELL_CATEGORY.HEALTH_POTION] = { 241304, 241305, 271883, 271884 },
    [SPELL_CATEGORY.HEALTHSTONE] = { 5512 },
    [SPELL_CATEGORY.DEMONIC_HEALTHSTONE] = { 224464 },
}

-- Spell IDs of the player's class, strongest first; C.EMPTY when unknown.
function Presets.Defensives(classID)
    classID = classID or select(3, UnitClass("player"))
    return classID and DEFENSIVES[classID] or C.EMPTY
end

-- Spell groups the picker adds to a bar in one step (Page.AddGroup): the
-- character's known spells of one kind. Class lists (classID) hold every
-- spell of the kind a class can know, talent and specialization choices side
-- by side: only known spells are added, so an entry for another build costs
-- nothing. Major offensive cooldowns are per specialization (specID), taken
-- from RAID_ESSENTIALS above and from the cooldown type table of LibOpenRaid
-- (LGPL; spell IDs only). Interrupts follow MSUF's interrupt table.
-- Retail 12.1 IDs; a client that lacks a spell (WoW Forever) never adds it.
local CATEGORY_CLASS = {
    interrupts = {
        [1] = { 6552, 386071 },            -- Pummel, Disrupting Shout
        [2] = { 96231, 31935 },            -- Rebuke, Avenger's Shield
        [3] = { 147362, 187707 },          -- Counter Shot, Muzzle
        [4] = { 1766 },                    -- Kick
        [5] = { 15487 },                   -- Silence
        [6] = { 47528 },                   -- Mind Freeze
        [7] = { 57994 },                   -- Wind Shear
        [8] = { 2139 },                    -- Counterspell
        [9] = { 19647, 119914, 89766 },    -- Spell Lock, Axe Toss (command, pet)
        [10] = { 116705 },                 -- Spear Hand Strike
        [11] = { 106839, 78675 },          -- Skull Bash, Solar Beam
        [12] = { 183752, 202137 },         -- Disrupt, Sigil of Silence
        [13] = { 351338 },                 -- Quell
    },
    crowdcontrol = {
        [1] = { 5246, 46968, 107570 },     -- Intimidating Shout, Shockwave, Storm Bolt
        [2] = { 853, 115750, 20066, 10326 }, -- Hammer of Justice, Blinding Light, Repentance, Turn Evil
        -- Freezing Trap, Binding Shot, Intimidation, Scatter Shot, Bursting Shot, Implosive Trap, Tar Trap
        [3] = { 187650, 109248, 19577, 213691, 186387, 462031, 187698 },
        [4] = { 408, 1833, 1776, 2094, 6770 }, -- Kidney Shot, Cheap Shot, Gouge, Blind, Sap
        [5] = { 8122, 64044, 88625, 9484, 108920, 205364 }, -- Psychic Scream, Psychic Horror, Holy Word: Chastise, Shackle Undead, Void Tendrils, Dominate Mind
        [6] = { 108194, 221562, 207167, 49576 }, -- Asphyxiate (two), Blinding Sleet, Death Grip
        [7] = { 51514, 192058, 51490, 51485, 305483, 197214 }, -- Hex, Capacitor Totem, Thunderstorm, Earthgrab Totem, Lightning Lasso, Sundering
        -- Polymorph, Frost Nova, Ring of Frost, Dragon's Breath, Supernova, Blast Wave, Mass Polymorph, Snowdrift
        [8] = { 118, 122, 113724, 31661, 157980, 157981, 383121, 389794 },
        [9] = { 5782, 30283, 5484, 6789, 710, 6358 }, -- Fear, Shadowfury, Howl of Terror, Mortal Coil, Banish, Seduction
        [10] = { 115078, 116844, 119381 }, -- Paralysis, Ring of Peace, Leg Sweep
        -- Mighty Bash, Incapacitating Roar, Mass Entanglement, Typhoon, Cyclone, Entangling Roots, Hibernate, Ursol's Vortex, Maim
        [11] = { 5211, 99, 102359, 132469, 33786, 339, 2637, 102793, 22570 },
        [12] = { 179057, 217832, 211881, 202138, 207684 }, -- Chaos Nova, Imprison, Fel Eruption, Sigil of Chains, Sigil of Misery
        [13] = { 360806, 358385, 372048 }, -- Sleep Walk, Landslide, Oppressing Roar
    },
    movement = {
        [1] = { 100, 6544, 3411, 385952 }, -- Charge, Heroic Leap, Intervene, Shield Charge
        [2] = { 1044, 190784 },            -- Blessing of Freedom, Divine Steed
        [3] = { 781, 186257 },             -- Disengage, Aspect of the Cheetah
        [4] = { 2983, 36554, 195457 },     -- Sprint, Shadowstep, Grappling Hook
        [5] = { 73325, 121536 },           -- Leap of Faith, Angelic Feather
        [6] = { 212552, 48265 },           -- Wraith Walk, Death's Advance
        [7] = { 192063, 79206, 2645, 192077 }, -- Gust of Wind, Spiritwalker's Grace, Ghost Wolf, Wind Rush Totem
        [8] = { 1953, 212653 },            -- Blink, Shimmer
        [9] = { 48020, 111400 },           -- Demonic Circle: Teleport, Burning Rush
        [10] = { 109132, 115008, 119996, 116841 }, -- Roll, Chi Torpedo, Transcendence: Transfer, Tiger's Lust
        [11] = { 1850, 106898, 77761, 77764, 102401, 252216 }, -- Dash, Stampeding Roar (three), Wild Charge, Tiger Dash
        [12] = { 195072, 198793 },         -- Fel Rush, Vengeful Retreat
        [13] = { 358267 },                 -- Hover
    },
    battlerez = {
        [2] = { 391054 },                  -- Intercession
        [6] = { 61999 },                   -- Raise Ally
        [9] = { 20707 },                   -- Soulstone
        [11] = { 20484 },                  -- Rebirth
    },
    dispels = {
        [2] = { 4987, 213644 },            -- Cleanse, Cleanse Toxins
        [3] = { 19801 },                   -- Tranquilizing Shot
        [5] = { 527, 528, 213634, 32375 }, -- Purify, Dispel Magic, Purify Disease, Mass Dispel
        [7] = { 77130, 51886, 370, 378773, 383013 }, -- Purify Spirit, Cleanse Spirit, Purge, Greater Purge, Poison Cleansing Totem
        [8] = { 475, 30449 },              -- Remove Curse, Spellsteal
        [9] = { 89808, 132411, 19505 },    -- Singe Magic (two), Devour Magic
        [10] = { 115450, 218164 },         -- Detox (healer, other)
        [11] = { 2782, 88423, 2908 },      -- Remove Corruption, Nature's Cure, Soothe
        [12] = { 278326 },                 -- Consume Magic
        [13] = { 360823, 365585, 374251 }, -- Naturalize, Expunge, Cauterizing Flame
    },
}
local CATEGORY_SPEC = {
    offensive = {
        [62] = { 365350, 321507 },                     -- Arcane Surge, Touch of the Magi
        [63] = { 190319, 153561 },                     -- Combustion, Meteor
        [64] = { 12472, 205021, 153595, 84714 },       -- Icy Veins, Ray of Frost, Comet Storm, Frozen Orb
        [65] = { 31884, 375576, 216331 },              -- Avenging Wrath, Divine Toll, Avenging Crusader
        [66] = { 31884, 389539, 375576, 327193 },      -- Avenging Wrath, Sentinel, Divine Toll, Moment of Glory
        -- Wrath, Toll, Execution Sentence, Wake of Ashes, Hammer of Light, Crusade, Final Reckoning
        [70] = { 31884, 375576, 343527, 255937, 427453, 231895, 343721 },
        [71] = { 107574, 167105, 227847, 1269383, 152277 }, -- Avatar, Colossus Smash, Bladestorm, Ravager
        [72] = { 1719, 107574, 227847, 385059, 46924 }, -- Recklessness, Avatar, Bladestorm, Odyn's Fury
        [73] = { 107574, 228920 },                     -- Avatar, Ravager
        [102] = { 194223, 102560, 202770, 205636, 391528 }, -- Celestial Alignment, Incarnation, Fury of Elune, Force of Nature, Convoke
        [103] = { 106951, 102543, 274837, 5217, 391528 }, -- Berserk, Incarnation, Feral Frenzy, Tiger's Fury, Convoke
        [104] = { 50334, 204066, 391528 },             -- Berserk, Lunar Beam, Convoke
        [105] = { 33891, 391528 },                     -- Incarnation: Tree of Life, Convoke
        [250] = { 49028, 439843 },                     -- Dancing Rune Weapon, Reaper's Mark
        -- Pillar of Frost, Reaper's Mark, Empower Rune Weapon, Frostwyrm's Fury, Breath of Sindragosa, Remorseless Winter
        [251] = { 51271, 439843, 47568, 279302, 1249658, 196770 },
        [252] = { 42650, 1233448, 1247378, 275699, 207289 }, -- Army of the Dead, Apocalypse, Unholy Assault
        [253] = { 19574, 34026, 466930, 359844, 193530, 201430 }, -- Bestial Wrath, Kill Command, Call of the Wild, Aspect of the Wild, Stampede
        [254] = { 288613, 19434, 257044, 212431, 260243, 466930 }, -- Trueshot, Aimed Shot, Rapid Fire, Explosive Shot, Volley
        [255] = { 1250646, 259495, 1261193, 266779, 186289 }, -- Wildfire Bomb, Coordinated Assault, Aspect of the Eagle
        [256] = { 472433, 421453, 194509, 10060, 123040, 34433 }, -- Evangelism, Ultimate Penitence, Radiance, Power Infusion, Mindbender, Shadowfiend
        [257] = { 200183, 10060 },                     -- Apotheosis, Power Infusion
        -- Power Infusion, Void Eruption, Void Torrent, Halo, Mindbender, Shadowfiend, Dark Ascension, Voidwraith
        [258] = { 10060, 228260, 263165, 120644, 200174, 34433, 391109, 451235 },
        [259] = { 360194, 385627, 79140 },             -- Deathmark, Kingsbane, Vendetta
        [260] = { 13750, 315508, 1277933, 51690, 13877, 381989 }, -- Adrenaline Rush, Roll the Bones, Killing Spree, Blade Flurry, Keep It Rolling
        [261] = { 185313, 121471, 280719, 426591, 384631 }, -- Shadow Dance, Shadow Blades, Secret Technique, Flagellation
        [262] = { 191634, 114050, 198067, 443454, 192249 }, -- Stormkeeper, Ascendance, Fire Elemental, Storm Elemental
        [263] = { 384352, 114051, 197214, 444995, 51533 }, -- Doom Winds, Ascendance, Sundering, Feral Spirit
        [264] = { 114052 },                            -- Ascendance
        [265] = { 1257052, 442726, 205180, 386997 },   -- Malevolence, Summon Darkglare, Soul Rot
        [266] = { 265187, 104316, 1276452, 1276467, 1276672, 267217, 111898 }, -- Demonic Tyrant, Call Dreadstalkers, Nether Portal, Grimoire: Felguard
        [267] = { 1122, 80240, 152108, 442726, 113858 }, -- Summon Infernal, Havoc, Cataclysm, Malevolence, Dark Soul: Instability
        [268] = { 132578, 325153, 1241059 },           -- Invoke Niuzao, Exploding Keg
        [269] = { 1249625, 123904, 1251001, 322109, 443028, 137639, 152173 }, -- Zenith, Xuen, Touch of Death, Celestial Conduit, Storm Earth and Fire, Serenity
        [270] = { 322118, 325197, 443028 },            -- Invoke Yu'lon, Invoke Chi-Ji, Celestial Conduit
        [577] = { 191427, 198013, 258860, 370965 },    -- Metamorphosis, Eye Beam, Essence Break, The Hunt
        [581] = { 212084, 207407, 390163 },            -- Fel Devastation, Soul Carver, Elysian Decree
        [1467] = { 375087, 357210, 433874, 357208, 359073, 370553 }, -- Dragonrage, Deep Breath (two), Fire Breath, Eternity Surge, Tip the Scales
        [1468] = { 357208, 359073, 370553 },           -- Fire Breath, Eternity Surge, Tip the Scales
        [1473] = { 395152, 403631, 409311, 404977, 370553, 442204 }, -- Ebon Might, Breath of Eons, Prescience, Time Skip, Tip the Scales
        [1480] = { 1217605, 473728, 1221150, 1246167 }, -- Devourer: the casts, not the 1217607 aura
    },
}
Presets.CATEGORY_ORDER = { "interrupts", "crowdcontrol", "movement", "battlerez", "dispels", "offensive" }
Presets.CATEGORY_CLASS, Presets.CATEGORY_SPEC = CATEGORY_CLASS, CATEGORY_SPEC

-- The spell IDs of one group for a class and specialization: the class's
-- list, then the specialization's; C.EMPTY for a kind the class lacks.
function Presets.Category(name, classID, specID)
    local byClass, bySpec = CATEGORY_CLASS[name], CATEGORY_SPEC[name]
    return byClass and byClass[classID] or C.EMPTY, bySpec and bySpec[specID] or C.EMPTY
end
