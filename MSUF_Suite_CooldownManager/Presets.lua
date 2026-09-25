local _,P=...
local C=P.CDM
-- Default contents of the Defensives bar: personal defensive cooldowns per
-- class (classID), strongest first, then the class's raid-wide damage
-- reduction. Talent choices and replaced spells are listed side by side:
-- the bar only shows spells the character knows, so an entry for another
-- build costs nothing. Healer throughput cooldowns and externals stay on the
-- Blizzard bars. A user list for the bar replaces this default.
local Presets={}
C.Presets=Presets

local DEFENSIVES={
    [1]={ -- Warrior
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
    [2]={ -- Paladin
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
    [3]={ -- Hunter
        186265,  -- Aspect of the Turtle
        264735,  -- Survival of the Fittest
        109304,  -- Exhilaration
    },
    [4]={ -- Rogue
        31224,   -- Cloak of Shadows
        5277,    -- Evasion
        199754,  -- Riposte
        1966,    -- Feint
        185311,  -- Crimson Vial
    },
    [5]={ -- Priest
        47585,   -- Dispersion
        19236,   -- Desperate Prayer
        586,     -- Fade
        15286,   -- Vampiric Embrace
    },
    [6]={ -- Death Knight
        48792,   -- Icebound Fortitude
        55233,   -- Vampiric Blood
        48707,   -- Anti-Magic Shell
        49039,   -- Lichborne
        48743,   -- Death Pact
        219809,  -- Tombstone
        194679,  -- Rune Tap
        51052,   -- Anti-Magic Zone
    },
    [7]={ -- Shaman
        108271,  -- Astral Shift
        108270,  -- Stone Bulwark Totem
        198103,  -- Earth Elemental
    },
    [8]={ -- Mage
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
    [9]={ -- Warlock
        104773,  -- Unending Resolve
        108416,  -- Dark Pact
        132413,  -- Shadow Bulwark
        17767,   -- Shadow Bulwark (pet)
    },
    [10]={ -- Monk
        115203,  -- Fortifying Brew
        243435,  -- Fortifying Brew
        122470,  -- Touch of Karma
        115176,  -- Zen Meditation
        122278,  -- Dampen Harm
        122783,  -- Diffuse Magic
    },
    [11]={ -- Druid
        61336,   -- Survival Instincts
        22812,   -- Barkskin
        102558,  -- Incarnation: Guardian of Ursoc
        200851,  -- Rage of the Sleeper
        108238,  -- Renewal
        22842,   -- Frenzied Regeneration
    },
    [12]={ -- Demon Hunter
        198589,  -- Blur
        196555,  -- Netherwalk
        187827,  -- Metamorphosis (Vengeance)
        204021,  -- Fiery Brand
        263648,  -- Soul Barrier
        196718,  -- Darkness
    },
    [13]={ -- Evoker
        363916,  -- Obsidian Scales
        374348,  -- Renewing Blaze
        374227,  -- Zephyr
    },
}
Presets.DEFENSIVES=DEFENSIVES

-- Raid essentials for Retail 12.1. Each row is a specialization ID and is
-- intentionally short: major throughput windows and the buttons needed to
-- prepare them. Talent alternatives may coexist; Resolve shows only learned
-- spells. Personal defensives, consumables and racials have their own bars.
-- Sources: current Wowhead Midnight Season 2 rotation/cooldown guides. The
-- Warcraft Logs candidate reports in the local audit still need cast/buff
-- verification. The client's CooldownViewer catalog decides which spell can
-- be tracked.
local RAID_ESSENTIALS={
    [62]={365350,321507,12051},                         -- Arcane Mage
    [63]={190319,153561,108853},                        -- Fire Mage
    [64]={205021,153595,84714},                         -- Frost Mage: Comet Storm replaces Ray of Frost after use
    [65]={31884,375576,31821,114165,200025,6940},      -- Holy Paladin, incl. Blessing of Sacrifice
    [66]={31884,389539,375576,432472},                  -- Protection Paladin: Avenging Wrath / Sentinel choice
    [70]={31884,375576,343527,255937,427453},          -- Retribution Paladin
    [71]={107574,167105,227847,1269383},               -- Arms Warrior
    [72]={1719,107574,227847,385059},                   -- Fury Warrior
    [73]={107574,385952,2565},                          -- Protection Warrior
    [102]={194223,102560,202770,205636,391528},        -- Balance Druid
    [103]={106951,102543,274837,5217,391528},          -- Feral Druid: current Convoke talent spell
    [104]={50334,204066,391528,1261870},                -- Guardian Druid
    [105]={740,33891,391528,132158,102342},            -- Restoration Druid, incl. Nature's Swiftness and Ironbark
    [250]={49028,439843},                               -- Blood Death Knight
    [251]={51271,439843,47568,279302,1249658,196770}, -- Frost Death Knight: Deathbringer and Breath options
    [252]={42650,1233448,1247378},                    -- Unholy Death Knight
    [253]={19574,34026,466930},                       -- Beast Mastery Hunter
    [254]={288613,19434,257044,212431,260243,466930}, -- Marksmanship Hunter: Explosive Shot / Volley choices
    [255]={1250646,259495,1261193},                   -- Survival Hunter
    [256]={472433,421453,194509,10060,62618,33206},   -- Discipline Priest, incl. Barrier and Pain Suppression
    [257]={64843,47788,200183,120517,10060},           -- Holy Priest, incl. Power Infusion
    [258]={10060,228260,263165,120644},                -- Shadow Priest
    [259]={360194,385627,1856,5938},                    -- Assassination Rogue: Shiv for Deathstalker
    [260]={13750,315508,1277933,51690,13877,381989},  -- Outlaw Rogue
    [261]={185313,121471,280719,426591,1856},          -- Subtlety Rogue
    [262]={191634,114050,198067,443454},               -- Elemental Shaman
    [263]={384352,114051,197214,444995},               -- Enhancement Shaman: Ascendance replaces Doom Winds
    [264]={114052,98008,108280,378081,444995},         -- Restoration Shaman: Surging Totem for Totemic
    [265]={1257052,442726,205180},                     -- Affliction Warlock
    [266]={265187,104316,1276452,1276467,1276672},     -- Demonology Warlock
    [267]={1122,80240,152108,442726},                  -- Destruction Warlock
    [268]={132578,325153,1241059,119582},              -- Brewmaster Monk
    [269]={1249625,123904,1251001,322109,443028},      -- Windwalker Monk: Zenith, Xuen, Fists of Fury, Touch of Death, Conduit
    [270]={116680,115310,388615,322118,325197,116849,443028}, -- Mistweaver Monk: Revival/Restoral, Yu'lon/Chi-Ji, Cocoon, Conduit
    [577]={191427,198013,258860,370965},               -- Havoc Demon Hunter
    [581]={212084,207407,390163},                       -- Vengeance Demon Hunter
    [1467]={375087,357210,433874,357208,359073,370553}, -- Devastation Evoker: base and steerable Deep Breath
    [1468]={370537,359816,363534,370553,357170},       -- Preservation Evoker, incl. Time Dilation
    [1473]={395152,403631,409311,404977,370553},       -- Augmentation Evoker, incl. Tip the Scales
    [1480]={1217605,473728,1221150,1246167},          -- Devourer Demon Hunter: cast, not the 1217607 aura
}
Presets.RAID_ESSENTIALS=RAID_ESSENTIALS

function Presets.RaidEssentials(specID)
    return RAID_ESSENTIALS[specID]
end

-- Active racial abilities, appended to the Potions and racials bar. Blizzard's
-- catalog does not list them; only the character's own racial is known.
local RACIALS={
    7744,    -- Will of the Forsaken
    20549,   -- War Stomp
    20572,33697,33702, -- Blood Fury
    28730,25046,50613,69179,80483,129597,155145,202719,232633, -- Arcane Torrent
    20594,   -- Stoneform
    26297,   -- Berserking
    28880,59542,59543,59544,59545,59547,59548,121093,370626,416250, -- Gift of the Naaru
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
    1237885,1287685, -- Haranir racial
}
Presets.RACIALS=RACIALS

-- Bag consumables on the Potions and racials bar, in this order after
-- Blizzard's entries and before the racial. Warlocks with Pact of Gluttony
-- create the Demonic Healthstone. Each one stands in for Blizzard's record
-- of its spellCategory while the catalog has no learned record, and shows
-- only while the bags hold it (hideEmpty).
Presets.CONSUMABLES={
    {item=5512,category=1711},   -- Healthstone
    {item=224464,category=2566}, -- Demonic Healthstone
}

-- Bag items behind Blizzard's potion and healthstone entries (spellCategory),
-- every quality rank: their counts add up to the number shown on the icon.
Presets.CATEGORY_ITEMS={
    [4]={241308,241309,245897,245898,241288,241289,245902,245903,271886,271887,274763,274764}, -- combat potions
    [30]={241304,241305,271883,271884}, -- health potions
    [1711]={5512},                     -- Healthstone
    [2566]={224464},                   -- Demonic Healthstone
}

-- Spell IDs of the player's class, strongest first; C.EMPTY when unknown.
function Presets.Defensives()
    local classID=select(3,UnitClass("player"))
    return classID and DEFENSIVES[classID] or C.EMPTY
end
