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
