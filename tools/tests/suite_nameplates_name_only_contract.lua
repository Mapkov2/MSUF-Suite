local root = assert(arg[1])
local combat, reaction, fighting, paletteReads = false, 3, false, 0
local secret = {}
local function Public(value) return value ~= secret end
local function Finite(value) return type(value) == "number" end

local NS = { AnchorPoints = {}, AnchorLabels = {}, IsSecret = function(value) return value == secret end,
    InCombat = function() return combat end, Safety = { IsForbidden = function() return false end },
    RGB = function(hex)
        paletteReads = paletteReads + 1
        if hex == "e5db00" then return .9, .86, 0 end
        return .7, .2, .3
    end }
local private = { NS = NS, Suite = { Public = Public, Finite = Finite }, Mode = { GROUP_NAMES_ONLY = 3 },
    RoleKey = { Caster = { color = "enemyCasterColor" }, Neutral = { color = "enemyNeutralColor" } } }
UnitReaction = function() return reaction end
UnitAffectingCombat = function() return fighting end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = .2, g = .6, b = .8 } }
local nameHooks = {}
hooksecurefunc = function(name, handler)
    assert(name == "CompactUnitFrame_UpdateName")
    nameHooks[#nameHooks + 1] = handler
end
local function nativeUpdate(uf)
    for _, hook in ipairs(nameHooks) do hook(uf) end
end

local function Region(alpha)
    local region = { alpha = alpha, r = .3, g = .4, b = .5, a = .9 }
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(value) self.alpha = value end
    function region:GetTextColor() return self.r, self.g, self.b, self.a end
    function region:GetVertexColor()
        if self.rgbOnly then return self.r, self.g, self.b end
        return self.r, self.g, self.b, self.a
    end
    function region:GetText() return self.text end
    function region:SetText(text) self.text = text end
    function region:IsShown() return true end
    function region:IsForbidden() return false end
    function region:SetVertexColor(r, g, b, a)
        self.writes = (self.writes or 0) + 1
        self.r, self.g, self.b, self.a = r, g, b, a
    end
    function region:IsProtected() return self.protected or false end
    function region:CanBeAccessedInContext() return self.access or true end
    return region
end

assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/FriendlyNames.lua"))("Nameplates", private)
local Names = private.FriendlyNames
local config = { enemyPlateNameOnly = true, enemyPlateNameClassColor = true, neutralPlateNameOnly = true,
    neutralPlateNameTypeColor = true, enemyCasterColor = "b2334c", enemyNeutralColor = "e5db00", friendlyNPCs = 2 }
local owner = { config = config, active = true, pendingPlates = {} }
Names.Bind(owner)
Names.ConfigureNameOnly()

local uf = { isFriend = false, isPlayer = true, name = Region(1), HealthBarsContainer = Region(.8),
    CastBarsContainer = Region(.6), AurasFrame = Region(.5), RaidTargetFrame = Region(.4) }
assert(Names.ApplyNameOnly(uf, "nameplate1"))
assert(uf.HealthBarsContainer.alpha == 0 and uf.CastBarsContainer.alpha == 0 and uf.AurasFrame.alpha == 0)
assert(uf.RaidTargetFrame.alpha == 0 and uf.name.alpha == 1, "name-only suppressed the name or retained a marker")
Names.PaintNameOnly(uf)
assert(uf.name.r == .2 and uf.name.g == .6 and uf.name.b == .8 and uf.name.a == .9)
uf.name:SetVertexColor(.6, .7, .9, .9)
nativeUpdate(uf)
assert(uf.name.r == .2, "native name refresh erased the class color")

config.enemyPlateNameOnly = false
assert(not Names.ApplyNameOnly(uf, "nameplate1"))
assert(uf.HealthBarsContainer.alpha == .8 and uf.CastBarsContainer.alpha == .6 and uf.AurasFrame.alpha == .5)
assert(uf.name.r == .6 and uf.name.g == .7, "leaving name-only did not release the native color")

uf.isPlayer, reaction = false, 4
assert(Names.ApplyNameOnly(uf, "nameplate1", "Caster"), "Neutral did not use its own setting")
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0,
    "a neutral caster name used its hostile NPC type color instead of the neutral palette")
local reads, writes = paletteReads, uf.name.writes
for _ = 1, 1000 do nativeUpdate(uf) end
assert(paletteReads == reads and uf.name.writes == writes, "unchanged name refreshes parsed the palette or rewrote the label")
combat, fighting = true, true
assert(Names.ApplyNameOnly(uf, "nameplate1") and Names.NameOnlyScope(uf) == "neutral",
    "combat alone moved a neutral NPC out of Neutral Name only")
uf.name:SetVertexColor(1, 1, 1, .9)
nativeUpdate(uf)
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0,
    "the native combat name refresh replaced the neutral palette")
fighting = secret
assert(Names.ApplyNameOnly(uf, "nameplate1"), "an unreadable combat state replaced a public neutral reaction")
reaction = 3
assert(Names.NeutralDisplayChanged(uf, "nameplate1") and not Names.ApplyNameOnly(uf, "nameplate1")
    and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1,
    "a genuinely hostile reaction retained the prior neutral override")
combat, reaction = false, 5

uf.isFriend, fighting = true, false
assert(not Names.ApplyNameOnly(uf, "nameplate1"), "Neutral setting affected a Friendly NPC")
config.friendlyNPCs = NS.NameplateExtensions.NPC_PLATE_NAME_ONLY
config.friendlyNpcPlateNameTypeColor = true
NS.Finite = Finite
local friendlyPaletteReads = 0
NS.HostBridge = { NPCNameColor = function(kind)
    assert(kind == "friendly")
    friendlyPaletteReads = friendlyPaletteReads + 1
    return .1, .8, .3
end }
Names.ConfigureNameOnly()
assert(Names.ApplyNameOnly(uf, "nameplate1"), "Friendly NPC display did not enter name-only")
assert(uf.name.r == .1 and uf.name.g == .8 and uf.name.b == .3, "unclassified friendly NPC lost its reaction color")
assert(Names.ApplyNameOnly(uf, "nameplate1", "Caster") and uf.name.g == .8, "a friendly caster used the enemy palette")
local friendlyReads = friendlyPaletteReads
uf.name:SetVertexColor(1, 1, 1, .9)
for _ = 1, 1000 do nativeUpdate(uf) end
assert(uf.name.g == .8 and friendlyPaletteReads == friendlyReads, "native refresh lost or repeatedly read the friendly palette")
reaction = 4
assert(Names.ApplyNameOnly(uf, "nameplate1", "Caster") and Names.NameOnlyScope(uf) == "neutral" and uf.name.g == .86,
    "a neutral NPC on a friendly plate used the friendly palette")
reaction = 5
NS.HostBridge.NPCNameColor = function() end
Names.ConfigureNameOnly()
assert(Names.ApplyNameOnly(uf, "nameplate1") and uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0,
    "an older host without a reaction palette lost the standard friendly green")
uf.isPlayer = true
assert(not Names.ApplyNameOnly(uf, "nameplate2"), "Friendly NPC mode affected a friendly player")

uf.isPlayer = false
uf.HealthBarsContainer.protected = true
uf.CastBarsContainer.access = secret
combat = true
assert(Names.ApplyNameOnly(uf, "nameplate3"))
assert(uf.HealthBarsContainer.alpha == .8 and uf.CastBarsContainer.alpha == .6 and owner.pendingPlates[uf],
    "protected or inaccessible layers were modified in combat")
combat, uf.CastBarsContainer.access = false, nil
assert(Names.ApplyNameOnly(uf, "nameplate3") and uf.HealthBarsContainer.alpha == 0)
uf.CastBarsContainer.alpha = .25
Names.RestoreNameOnly(uf)
assert(uf.HealthBarsContainer.alpha == .8 and uf.CastBarsContainer.alpha == .25 and not Names.IsNameOnly(uf),
    "release overwrote an alpha changed by another owner")

local attackable, exists, attackReads = true, true, 0
UnitCanAttack = function() attackReads = attackReads + 1 return attackable end
UnitExists = function() return exists end
uf.isFriend, reaction, fighting = false, 4, false
config.friendlyNPCs, config.neutralNameOnlyMode = 2, NS.NameplateExtensions.NEUTRAL_BARS_ATTACKABLE
Names.ConfigureNameOnly()
assert(not Names.ApplyNameOnly(uf, "nameplate3") and uf.HealthBarsContainer.alpha == .8,
    "an attackable neutral lost its health bar in the split mode")
attackable = false
assert(Names.NeutralDisplayChanged(uf, "nameplate3") and Names.ApplyNameOnly(uf, "nameplate3")
    and Names.KeepsQuestText(uf), "a nonattackable neutral did not show its name with quest text")
uf.isFriend, fighting = true, true
assert(Names.ApplyNameOnly(uf, "nameplate3") and Names.NameOnlyScope(uf) == "neutral",
    "a nonattackable quest NPC used the health bar because it was friendly-routed or in combat")
attackable = secret
assert(not Names.ApplyNameOnly(uf, "nameplate3") and uf.HealthBarsContainer.alpha == .8,
    "unreadable attackability hid a health bar")
local before = attackReads
attackable, exists = false, false
assert(not Names.ApplyNameOnly(uf, "nameplate3") and attackReads == before, "a stale unit was treated as nonattackable")

exists, fighting, uf.isFriend = true, false, false
config.neutralNameOnlyMode = NS.NameplateExtensions.NEUTRAL_NAMES_ATTACKABLE
Names.ConfigureNameOnly()
assert(not Names.ApplyNameOnly(uf, "nameplate3"), "the inverse hid a nonattackable health bar")
attackable = true
assert(Names.ApplyNameOnly(uf, "nameplate3") and not Names.KeepsQuestText(uf), "the inverse did not show just the attackable name")
fighting = true
assert(Names.NeutralDisplayChanged(uf, "nameplate3") and not Names.ApplyNameOnly(uf, "nameplate3")
    and uf.HealthBarsContainer.alpha == .8, "engaging an attackable neutral did not restore its health bar")

config.neutralNameOnlyMode, fighting = nil, false
Names.ConfigureNameOnly()
before = attackReads
assert(Names.ApplyNameOnly(uf, "nameplate3") and attackReads == before, "legacy name-only behavior started reading attackability")

-- A profile can enable the shared formatter after Name only registered its
-- native hook. Both normal entry points must leave NPC color to Name only.
local paintCalls, formats, sharedEnabled = 0, 0, true
NS.IsCombatLocked = function() return combat end
NS.NameplateText = {
    Compile = function() return { enabled = sharedEnabled, shared = sharedEnabled and {} or nil } end,
    Format = function(_, raw) formats = formats + 1 return raw:sub(1, 8) end,
    PaintColor = function(label)
        paintCalls = paintCalls + 1
        label:SetVertexColor(1, 1, 1, 1)
        return true
    end,
}
assert(loadfile(root .. "/MSUF_Suite_Nameplates/NameText.lua"))("Nameplates", private)
owner.config.enemy, uf.name.text, uf.unit = true, "Neutral creature", "nameplate3"
owner.activeUnits = { nameplate3 = uf }
uf.IsForbidden, uf.IsProtected = uf.name.IsForbidden, uf.name.IsProtected
private.NameText.Bind(owner)
private.NameText.Configure(config)
private.NameText.Apply(uf, "enemy", uf.unit)
Names.PaintNameOnly(uf)
for _, rgb in ipairs({ { 1, 1, 1 }, { 1, 0, 0 } }) do
    uf.name:SetText("Neutral creature")
    uf.name:SetVertexColor(rgb[1], rgb[2], rgb[3], .9)
    nativeUpdate(uf)
    assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0 and uf.name.a == .9,
        "a later shared-formatting hook replaced the neutral name-only palette")
    assert(uf.name.text == "Neutral " and formats > 0, "color ownership disabled normal name formatting")
end
assert(paintCalls == 0, "shared name color wrote over an active NPC tint")
config.neutralPlateNameOnly = false
Names.ConfigureNameOnly()
private.NameText.Apply(uf, "enemy", uf.unit)
assert(paintCalls == 1 and uf.name.r == 1 and uf.name.g == 1, "shared color did not resume when leaving Name only")
sharedEnabled = false
private.NameText.Configure(config)
assert(uf.name.r == 1 and uf.name.g == 0 and uf.name.b == 0 and uf.name.a == .9,
    "turning both tints off restored a cached name-only tint instead of the last native color")

config.enemyPlateNameOnly, uf.isPlayer, reaction = true, true, 3
local class
UnitClass = function() return nil, class end
Names.ConfigureNameOnly()
assert(Names.ApplyNameOnly(uf, uf.unit) and not Names.OwnsColor(uf))
class = "MAGE"
nativeUpdate(uf)
assert(uf.name.r == .2 and uf.name.g == .6, "the first unreadable class permanently disabled class color")
uf.name.a = .5
nativeUpdate(uf)
Names.RestoreNameOnly(uf)
assert(uf.name.r == 1 and uf.name.g == 0 and uf.name.a == .5, "an alpha change lost the underlying native tint")

class = "PRIEST"
RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
assert(Names.ApplyNameOnly(uf, uf.unit) and uf.name.g == 1, "the recycled plate inherited the previous class")

-- Forever's selected neutral NPC reported friendly=true, reaction 4 and
-- three public vertex components. The font's own opacity need not be 1.
Names.RestoreNameOnly(uf)
uf.isPlayer, uf.isFriend, reaction = false, true, 4
uf.name.rgbOnly = true
uf.name:SetVertexColor(1, 1, 1, .75)
config.neutralPlateNameOnly, config.friendlyNPCs = true, 5
Names.ConfigureNameOnly()
assert(Names.ApplyNameOnly(uf, uf.unit) and Names.NameOnlyScope(uf) == "neutral")
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0 and uf.name.a == .75,
    "a friendly-routed neutral NPC with RGB-only vertex readback kept its white name")
uf.name:SetVertexColor(1, 0, 0, .55)
nativeUpdate(uf)
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.a == .55, "RGB-only native reset lost neutral tint or opacity")
Names.RestoreNameOnly(uf)
assert(uf.name.r == 1 and uf.name.g == 0 and uf.name.a == .55, "RGB-only release did not restore native red and opacity")
reaction = 5
assert(Names.ApplyNameOnly(uf, uf.unit) and uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0 and uf.name.a == .55,
    "the same RGB-only frame could not display a friendly NPC")
uf.name.GetTextColor = function(self) return self.r, self.g, self.b end
uf.name.alpha = .35
uf.name:SetVertexColor(1, 1, 1, 1)
nativeUpdate(uf)
assert(uf.name.g == 1 and uf.name.r == 0 and uf.name.a == .35, "two RGB-only getters lost the name's opacity")
uf.name.GetTextColor = function(self) return self.r, self.g, self.b, secret end
uf.name:SetVertexColor(1, 1, 1, 1)
local lastWrites = uf.name.writes
nativeUpdate(uf)
assert(uf.name.writes == lastWrites, "a restricted opacity was treated as missing")
print("Name-only scope selection, color, combat deferral and restoration passed")
