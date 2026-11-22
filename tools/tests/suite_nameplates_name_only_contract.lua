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
local private = { NS = NS, Suite = { Public = Public, Finite = Finite }, Mode = { GROUP_NAMES_ONLY = 3, SHOW = 2 },
    RoleKey = { Caster = { color = "enemyCasterColor" }, Neutral = { color = "enemyNeutralColor" } } }
UnitReaction = function() return reaction end
UnitAffectingCombat = function() return fighting end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = .2, g = .6, b = .8 } }
local nameHooks = {}
hooksecurefunc = function(name, handler, callback)
    if type(name) == "table" then
        assert(handler == "SetVertexColor" or handler == "SetTextColor" or handler == "SetFontObject"
            or handler == "SetStatusBarColor" or handler == "SetIsTarget")
        name.hooked = name.hooked or {}
        assert(not name.hooked[handler])
        name.hooked[handler] = true
        local original = name[handler]
        name[handler] = function(...)
            original(...)
            callback(...)
        end
    else
        assert(name == "CompactUnitFrame_UpdateName")
        nameHooks[#nameHooks + 1] = handler
    end
end
local function nativeUpdate(uf)
    for _, hook in ipairs(nameHooks) do hook(uf) end
end

local function Region(alpha)
    local region = { alpha = alpha, r = .3, g = .4, b = .5, a = .9, vr = 1, vg = 1, vb = 1, va = 1 }
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(value) self.alpha = value end
    function region:GetTextColor()
        self.reads = (self.reads or 0) + 1
        return self.r, self.g, self.b, self.a
    end
    function region:GetVertexColor() return self.vr, self.vg, self.vb, self.va end
    function region:SetVertexColor(r, g, b, a)
        self.vertexWrites = (self.vertexWrites or 0) + 1
        self.vr, self.vg, self.vb, self.va = r, g, b, a
        self.glyphR, self.glyphG, self.glyphB = r, g, b
    end
    function region:GetText() return self.text end
    function region:SetText(text) self.text = text end
    function region:IsShown() return true end
    function region:IsForbidden() return false end
    function region:SetTextColor(r, g, b, a)
        self.writes = (self.writes or 0) + 1
        if self.refuseOnce then self.refuseOnce = nil return end
        self.r, self.g, self.b, self.a = r, g, b, a
        self.glyphR, self.glyphG, self.glyphB = r, g, b
    end
    function region:SetFontObject(font)
        self.r, self.g, self.b, self.a = unpack(font)
        self.glyphR, self.glyphG, self.glyphB = self.r, self.g, self.b
    end
    function region:IsProtected() return self.protected or false end
    function region:CanBeAccessedInContext() return self.access == nil or self.access end
    return region
end

assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/FriendlyNames.lua"))("Nameplates", private)
local Names = private.FriendlyNames
-- Mirror Skin.Paint, including the separate player font pass.
local function Paint(uf, unit, role)
    local active, paintPlayerName = Names.ApplyNameOnly(uf, unit, role)
    if paintPlayerName then Names.PaintNameOnly(uf) end
    return active
end
local config = { enemyPlateNameOnly = true, enemyPlateNameClassColor = true, neutralPlateNameOnly = true,
    neutralPlateNameTypeColor = true, enemyCasterColor = "b2334c", enemyNeutralColor = "e5db00", friendlyNPCs = 2 }
local owner = { config = config, active = true, pendingPlates = {} }
Names.Bind(owner)
Names.ConfigureNameOnly()

local uf = { isFriend = false, isPlayer = true, name = Region(1), HealthBarsContainer = Region(.8),
    CastBarsContainer = Region(.6), AurasFrame = Region(.5), RaidTargetFrame = Region(.4),
    IsProtected = function() return false end }
UnitIsPlayer = function() return uf.isPlayer end
assert(Paint(uf, "nameplate1"))
assert(uf.HealthBarsContainer.alpha == 0 and uf.CastBarsContainer.alpha == 0 and uf.AurasFrame.alpha == 0)
assert(uf.RaidTargetFrame.alpha == 0 and uf.name.alpha == 1, "name-only suppressed the name or retained a marker")
Names.PaintNameOnly(uf)
assert(uf.name.r == .2 and uf.name.g == .6 and uf.name.b == .8 and uf.name.a == .9)
uf.name:SetTextColor(.6, .7, .9, .9)
nativeUpdate(uf)
assert(uf.name.r == .2, "native name refresh erased the class color")

config.enemyPlateNameOnly = false
assert(not Paint(uf, "nameplate1"))
assert(uf.HealthBarsContainer.alpha == .8 and uf.CastBarsContainer.alpha == .6 and uf.AurasFrame.alpha == .5)
assert(uf.name.r == .6 and uf.name.g == .7, "leaving name-only did not release the native color")
local idleReads, idleWrites = uf.name.reads, uf.name.writes
for _ = 1, 1000 do nativeUpdate(uf) end
assert(uf.name.reads == idleReads and uf.name.writes == idleWrites, "a released plate still touched the font color")

uf.isPlayer, reaction = false, 4
assert(Paint(uf, "nameplate1", "Caster"), "Neutral did not use its own setting")
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0,
    "a neutral caster name used its hostile NPC type color instead of the neutral palette")
local reads, writes, fontReads = paletteReads, uf.name.writes, uf.name.reads
for _ = 1, 1000 do nativeUpdate(uf) end
assert(paletteReads == reads and uf.name.writes == writes and uf.name.reads <= fontReads + 1000,
    "unchanged native refreshes exceeded one font read or repeated palette work")
combat, fighting = true, true
assert(Paint(uf, "nameplate1") and Names.NameOnlyScope(uf) == "neutral",
    "combat alone moved a neutral NPC out of Neutral Name only")
uf.name:SetTextColor(1, 1, 1, .9)
nativeUpdate(uf)
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0,
    "the native combat name refresh replaced the neutral palette")
fighting = secret
assert(Paint(uf, "nameplate1"), "an unreadable combat state replaced a public neutral reaction")
reaction = 3
assert(Names.NeutralDisplayChanged(uf, "nameplate1") and not Paint(uf, "nameplate1")
    and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1,
    "a genuinely hostile reaction retained the prior neutral override")
combat, reaction = false, 5

uf.isFriend, fighting = true, false
assert(not Paint(uf, "nameplate1"), "Neutral setting affected a Friendly NPC")
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
assert(Paint(uf, "nameplate1"), "Friendly NPC display did not enter name-only")
assert(uf.name.r == .1 and uf.name.g == .8 and uf.name.b == .3, "unclassified friendly NPC lost its reaction color")
assert(Paint(uf, "nameplate1", "Caster") and uf.name.g == .8, "a friendly caster used the enemy palette")
local friendlyReads = friendlyPaletteReads
-- A neutral quest giver can share Blizzard's friendly template with the
-- friendly NPC next to it. Each display choice must work in both directions.
config.neutralPlateNameOnly, reaction = false, 4
Names.ConfigureNameOnly()
assert(not Paint(uf, "nameplate1") and uf.HealthBarsContainer.alpha == .8,
    "Neutral Health bars fell through to Friendly NPC Name only on a friendly-template neutral")
reaction = 5
assert(Paint(uf, "nameplate1") and uf.name.g == .8, "a friendly quest NPC did not recover its own name color")
config.friendlyNPCs, config.neutralPlateNameOnly, reaction = 2, true, 4
Names.ConfigureNameOnly()
assert(Paint(uf, "nameplate1") and uf.name.g == .86, "Friendly Health bars stole the neutral name")
reaction = 5
assert(not Paint(uf, "nameplate1") and uf.HealthBarsContainer.alpha == .8,
    "a friendly quest NPC retained the neutral name-only mode")
local npcHealth = Region(1)
function npcHealth:IsShowOnlyName() return self.nativeNames end
function npcHealth:SetShowOnlyName(on) self.nativeNames = on end
function npcHealth:SetIsTarget() uf.name.glyphR, uf.name.glyphG, uf.name.glyphB = 1, 1, 1 end
uf.HealthBarsContainer.healthBar, uf.showOnlyName, npcHealth.nativeNames = npcHealth, true, true
Names.SyncNPCHealth(uf, "friendlyNpc", false)
assert(not npcHealth.nativeNames, "the friendly-player CVar still hid a friendly NPC's requested bar")
combat = true
Names.SyncNPCHealth(uf, "friendlyPlayer", false)
assert(not npcHealth.nativeNames and owner.pendingPlates[uf], "combat changed native component visibility")
combat = false
Names.SyncNPCHealth(uf, "friendlyPlayer", false)
assert(npcHealth.nativeNames, "a recycled player lost Blizzard's native display")
reaction = 4
assert(Paint(uf, "nameplate1"))
for _, selected in ipairs({true, false}) do
    Names.PaintNameOnly(uf, true)
    npcHealth:SetIsTarget(selected)
    assert(uf.name.glyphR == .9 and uf.name.glyphG == .86 and uf.name.glyphB == 0,
        "native target presentation after PLAYER_TARGET_CHANGED left the neutral NPC white")
    npcHealth:SetIsTarget(selected)
    Names.PaintNameOnly(uf, true)
    assert(uf.name.glyphG == .86 and uf.name.glyphB == 0, "selection order changed the neutral name")
end
uf.HealthBarsContainer.healthBar, uf.showOnlyName, reaction = nil, nil, 5
config.friendlyNPCs = NS.NameplateExtensions.NPC_PLATE_NAME_ONLY
Names.ConfigureNameOnly()
assert(Paint(uf, "nameplate1"))
friendlyReads = friendlyPaletteReads
uf.name:SetTextColor(1, 1, 1, .9)
for _ = 1, 1000 do nativeUpdate(uf) end
assert(uf.name.g == .8 and friendlyPaletteReads == friendlyReads, "native refresh lost or repeatedly read the friendly palette")
reaction = 4
assert(Paint(uf, "nameplate1", "Caster") and Names.NameOnlyScope(uf) == "neutral" and uf.name.g == .86,
    "a neutral NPC on a friendly plate used the friendly palette")
reaction = 5
NS.HostBridge.NPCNameColor = function() end
Names.ConfigureNameOnly()
assert(Paint(uf, "nameplate1") and uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0,
    "an older host without a reaction palette lost the standard friendly green")
local actualPlayer = UnitIsPlayer
UnitIsPlayer = function() return false end
uf.isPlayer = true
uf.HealthBarsContainer.healthBar = npcHealth
function npcHealth:GetStatusBarColor() return 1, .5, .1 end
assert(Paint(uf, "nameplate1") and uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0,
    "a trainer treated as a player for display took its class color")
npcHealth:SetIsTarget(true)
assert(uf.name.glyphR == 0 and uf.name.glyphG == 1, "selecting a friendly trainer lost its NPC color")
uf.HealthBarsContainer.healthBar = nil
UnitIsPlayer = actualPlayer
assert(not Paint(uf, "nameplate2"), "Friendly NPC mode affected a friendly player")

uf.isPlayer = false
uf.HealthBarsContainer.protected = true
uf.CastBarsContainer.access = secret
combat = true
assert(Paint(uf, "nameplate3"))
assert(uf.HealthBarsContainer.alpha == .8 and uf.CastBarsContainer.alpha == .6 and owner.pendingPlates[uf],
    "protected or inaccessible layers were modified in combat")
combat, uf.CastBarsContainer.access = false, nil
assert(Paint(uf, "nameplate3") and uf.HealthBarsContainer.alpha == 0)
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
assert(not Paint(uf, "nameplate3") and uf.HealthBarsContainer.alpha == .8,
    "an attackable neutral lost its health bar in the split mode")
attackable = false
assert(Names.NeutralDisplayChanged(uf, "nameplate3") and Paint(uf, "nameplate3")
    and Names.KeepsQuestText(uf), "a nonattackable neutral did not show its name with quest text")
uf.isFriend, fighting = true, true
assert(Paint(uf, "nameplate3") and Names.NameOnlyScope(uf) == "neutral",
    "a nonattackable quest NPC used the health bar because it was friendly-routed or in combat")
attackable = secret
assert(not Paint(uf, "nameplate3") and uf.HealthBarsContainer.alpha == .8,
    "unreadable attackability hid a health bar")
local before = attackReads
attackable, exists = false, false
assert(not Paint(uf, "nameplate3") and attackReads == before, "a stale unit was treated as nonattackable")

exists, fighting, uf.isFriend = true, false, false
config.neutralNameOnlyMode = NS.NameplateExtensions.NEUTRAL_NAMES_ATTACKABLE
Names.ConfigureNameOnly()
assert(not Paint(uf, "nameplate3"), "the inverse hid a nonattackable health bar")
attackable = true
assert(Paint(uf, "nameplate3") and not Names.KeepsQuestText(uf), "the inverse did not show just the attackable name")
fighting = true
assert(Names.NeutralDisplayChanged(uf, "nameplate3") and not Paint(uf, "nameplate3")
    and uf.HealthBarsContainer.alpha == .8, "engaging an attackable neutral did not restore its health bar")

config.neutralNameOnlyMode, fighting = nil, false
Names.ConfigureNameOnly()
before = attackReads
assert(Paint(uf, "nameplate3") and attackReads == before, "legacy name-only behavior started reading attackability")

-- A profile can enable the shared formatter after Name only registered its
-- native hook. Both normal entry points must leave NPC color to Name only.
local paintCalls, formats, sharedEnabled = 0, 0, true
NS.IsCombatLocked = function() return combat end
NS.NameplateText = {
    Compile = function() return { enabled = sharedEnabled, shared = sharedEnabled and {} or nil } end,
    Format = function(_, raw) formats = formats + 1 return raw:sub(1, 8) end,
    PaintColor = function(label)
        paintCalls = paintCalls + 1
        label:SetTextColor(1, 1, 1, 1)
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
    uf.name:SetTextColor(rgb[1], rgb[2], rgb[3], .9)
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
assert(uf.name.text == "Neutral creature", "leaving both modes did not restore the original name")
assert(uf.name.r == 1 and uf.name.g == 0 and uf.name.b == 0 and uf.name.a == .9,
    "turning both tints off restored a cached name-only tint instead of the last native color")

config.enemyPlateNameOnly, uf.isPlayer, reaction = true, true, 3
local class
UnitClass = function() return nil, class end
Names.ConfigureNameOnly()
assert(Paint(uf, uf.unit) and not Names.OwnsColor(uf))
class = "MAGE"
nativeUpdate(uf)
assert(uf.name.r == .2 and uf.name.g == .6, "the first unreadable class permanently disabled class color")
uf.name.a = .5
nativeUpdate(uf)
Names.RestoreNameOnly(uf)
assert(uf.name.r == 1 and uf.name.g == 0 and uf.name.a == .5, "an alpha change lost the underlying native tint")

class = "PRIEST"
RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
assert(Paint(uf, uf.unit) and uf.name.g == 1, "the recycled plate inherited the previous class")

-- Blizzard can give NPCs a player's template and a real UnitClass. Its
-- display flag must not send a priest trainer through player class coloring.
UnitIsPlayer = function() return false end
local trainerClassReads = 0
UnitClass = function() trainerClassReads = trainerClassReads + 1 return "Priest", "PRIEST" end
uf.isFriend, reaction = true, 5
config.friendlyNPCs, config.neutralPlateNameOnly = 5, true
Names.ConfigureNameOnly()
assert(Paint(uf, uf.unit) and Names.NameOnlyScope(uf) == "friendlyNpc" and uf.name.r == 0 and uf.name.g == 1,
    "a friendly trainer on a player template lost its green name")
uf.isFriend, reaction = false, 4
assert(Paint(uf, uf.unit) and Names.NameOnlyScope(uf) == "neutral" and uf.name.g == .86,
    "a neutral trainer on a player template lost its neutral name")
assert(trainerClassReads == 0, "looked up the priest trainer's class to choose an NPC color")

-- On Forever, changing vertex tint alone left the selected NPC's glyphs white.
Names.RestoreNameOnly(uf)
uf.isPlayer, uf.isFriend, reaction = false, true, 4
uf.name:SetText("Neutral quest giver")
uf.name:SetVertexColor(1, 0, 1, .35)
uf.name:SetTextColor(1, 1, 1, .75)
config.neutralPlateNameOnly, config.friendlyNPCs = true, 5
Names.ConfigureNameOnly()
assert(Paint(uf, uf.unit) and Names.NameOnlyScope(uf) == "neutral")
assert(uf.name.glyphR == .9 and uf.name.glyphG == .86 and uf.name.glyphB == 0 and uf.name.a == .75)
assert(uf.name.text == "Neutral quest giver" and uf.name.vr == 1 and uf.name.vg == 1 and uf.name.vb == 1
    and uf.name.va == .35 and uf.name.alpha == 1, "a vertex tint multiplied the configured glyph or changed opacity")
uf.name:SetVertexColor(1, 1, 1, 1)
assert(uf.name.glyphR == .9 and uf.name.glyphG == .86 and uf.name.glyphB == 0,
    "Blizzard's late vertex write left the NPC white while its font still reported the configured yellow")
uf.name:SetFontObject({ 1, 1, 1, .6 })
assert(uf.name.glyphR == .9 and uf.name.glyphG == .86 and uf.name.a == .6,
    "a font change after the final paint erased the glyph color")
local stableWrites, stableReads = uf.name.writes, paletteReads
for _ = 1, 1000 do nativeUpdate(uf) end
assert(uf.name.writes == stableWrites and paletteReads == stableReads,
    "stable updates rewrote the glyph color or recalculated the palette")
Paint(uf, uf.unit)
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.b == 0 and uf.name.a == .6,
    "the frame-options refresh left a neutral NPC white")
uf.name:SetTextColor(1, 0, 0, .55)
nativeUpdate(uf)
assert(uf.name.r == .9 and uf.name.g == .86 and uf.name.a == .55, "native text color reset lost neutral tint or opacity")
Names.RestoreNameOnly(uf)
assert(uf.name.r == 1 and uf.name.g == 0 and uf.name.a == .55, "release did not restore native red and opacity")
reaction = 5
assert(Paint(uf, uf.unit) and uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0 and uf.name.a == .55,
    "the same frame could not display a friendly NPC")
uf.name:SetTextColor(1, 1, 1, .55)
nativeUpdate(uf)
assert(uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0 and uf.name.a == .55,
    "the native name refresh left a friendly NPC white")
uf.name.GetTextColor = function(self) return self.r, self.g, self.b end
uf.name.alpha = .35
uf.name:SetTextColor(1, 1, 1, 1)
nativeUpdate(uf)
assert(uf.name.g == 1 and uf.name.r == 0 and uf.name.a == 1 and uf.name.alpha == .35,
    "RGB-only readback lost the native setter's explicit alpha or copied the region opacity")
local previousWrites = uf.name.writes
uf.name:SetAlpha(.4)
nativeUpdate(uf)
assert(uf.name.writes == previousWrites, "changing region opacity caused a redundant color write")
Names.RestoreNameOnly(uf)
assert(uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1 and uf.name.a == 1 and uf.name.alpha == .4,
    "RGB-only release lost the native white or its last explicit font alpha")
assert(Paint(uf, uf.unit))
uf.name.GetTextColor = function(self) return self.r, self.g, self.b, secret end
uf.name:SetTextColor(1, 1, 1, 1)
local lastWrites = uf.name.writes
nativeUpdate(uf)
assert(uf.name.writes == lastWrites, "a restricted opacity was treated as missing")

-- Each pool lease gets a native white baseline. The first requested tint can
-- be refused or take effect later. Neither outcome should poison the cache.
Names.RestoreNameOnly(uf)
uf.name, uf.isFriend, reaction = Region(1), true, 4
local label = uf.name
label:SetTextColor(1, 1, 1, .7)
label.refuseOnce = true
assert(Paint(uf, uf.unit) and label.g == 1 and label.b == 1)
nativeUpdate(uf)
assert(label.r == .9 and label.g == .86 and label.b == 0 and label.a == .7,
    "an initial white readback permanently suppressed the neutral name color")
Names.RestoreNameOnly(uf)
label.refuseOnce = true
assert(Paint(uf, uf.unit))
label.r, label.g, label.b, label.a = .9, .86, 0, .4
Names.RestoreNameOnly(uf)
assert(label.r == 1 and label.g == 1 and label.b == 1 and label.a == .4,
    "a delayed tint leaked onto a recycled name or changed its opacity")
reaction, uf.isFriend, config.enemyPlateNameTypeColor = 3, false, true
UnitSelectionColor = function(unit) assert(unit == uf.unit) return 1, .15, .1 end
Names.ConfigureNameOnly()
assert(Paint(uf, uf.unit) and label.r == 1 and label.g == .15 and label.b == .1 and trainerClassReads == 0,
    "an unclassified NPC with no role palette lost its native unit color")
Names.RestoreNameOnly(uf)
UnitSelectionColor = function() return secret, secret, secret end
assert(Paint(uf, uf.unit) and not Names.OwnsColor(uf), "a restricted unit color became an NPC tint")
Names.RestoreNameOnly(uf)
local barR, barG, barB, barReads = .25, .7, .85, 0
uf.healthBar = { GetStatusBarColor = function()
    barReads = barReads + 1
    return barR, barG, barB
end, SetStatusBarColor = function(_, r, g, b)
    barR, barG, barB = r, g, b
end }
local friendlyPalette = {0, 1, 0}
NS.HostBridge.NPCNameColor = function() return unpack(friendlyPalette) end
reaction, uf.isFriend = 5, true
Names.ConfigureNameOnly()
assert(Paint(uf, uf.unit))
assert(label.r == barR and label.g == barG and label.b == barB, "the friendly glyph did not use the hidden bar's actual RGB")
uf.healthBar:SetStatusBarColor(1, 1, 1)
assert(label.r == 0 and label.g == 1 and label.b == 0, "a white stock or priest bar erased the friendly NPC reaction")
uf.healthBar:SetStatusBarColor(.25, .7, .85)
label:SetTextColor(1, 1, 1, .8)
assert(label.r == barR and label.g == barG and label.a == .8, "a later font writer left the friendly NPC white")
uf.healthBar:SetStatusBarColor(.4, .4, .4)
assert(label.r == .4 and label.g == .4 and label.b == .4, "a native bar recolor needed a target change")
friendlyPalette = {0, .15, 1}
Names.RefreshFriendlyPalette(true)
assert(label.r == 0 and label.g == .15 and label.b == 1, "editing Friendly NPC Color did not recolor the visible NPC")
local previousReads, previousWrites = barReads, label.writes
for _ = 1, 1000 do nativeUpdate(uf) uf.healthBar:SetStatusBarColor(.4, .4, .4) end
assert(previousReads == barReads and previousWrites == label.writes, "an override kept sampling its hidden bar or writing a stable color")
Names.RestoreNameOnly(uf)
label:SetTextColor(1, 1, 1, .75)
assert(label.r == 1 and label.g == 1 and label.b == 1, "a pooled label was still owned after leaving name-only")
reaction, uf.isFriend, config.enemyPlateNameTypeColor = 3, false, false
assert(Paint(uf, uf.unit) and label.r == .4, "an untinted name-only NPC missed its normal bar color")
assert(Names.RefreshRole(uf, "Caster", "e5db00") and label.r == .9 and label.g == .86, "resolved bar role did not reach a name-only NPC")
assert(Names.RefreshRole(uf, "Caster", nil) and label.r == .4, "removing a role did not restore the native bar color")
Names.RestoreNameOnly(uf)
uf.name = Region(1)
local getFont = uf.name.GetTextColor
uf.name.GetTextColor = function() return secret, secret, secret, secret end
assert(Paint(uf, uf.unit) and uf.name.writes == nil, "a withheld initial font baseline was inspected or replaced")
uf.name:SetTextColor(1, 1, 1, .6)
assert(uf.name.r == .4 and uf.name.g == .4 and uf.name.b == .4 and uf.name.a == .6,
    "the first public font write left the text white while the getter was withheld")
uf.name.GetTextColor = getFont
uf.name:SetVertexColor(.4, .4, .4, .35)
assert(uf.name.vr == 1 and uf.name.vg == 1 and uf.name.vb == 1 and uf.name.va == .35 and uf.name.a == .6,
    "even a matching vertex tint would darken the glyph a second time")
local activeWrites = uf.name.writes
combat, uf.name.access = true, false
uf.name:SetVertexColor(1, 1, 1, 1)
assert(uf.name.writes == activeWrites and uf.name.glyphB == 1 and owner.pendingPlates[uf],
    "wrote a restricted label or failed to defer its native color change")
combat, uf.name.access = false, true
Paint(uf, uf.unit)
assert(uf.name.glyphB == .4, "a deferred vertex change survived combat replay on a matching font readback")
uf.name:SetVertexColor(1, 0, 0, .45)
assert(uf.name.glyphR == .4 and uf.name.glyphG == .4 and uf.name.a == .6,
    "a conflicting vertex update changed the NPC color or its separate opacity")
Names.RestoreNameOnly(uf)
assert(uf.name.vr == 1 and uf.name.vg == 0 and uf.name.vb == 0 and uf.name.va == .45
    and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1 and uf.name.a == .6,
    "release did not restore both independent native tints and opacities")
local releasedWrites = uf.name.writes
uf.name:SetVertexColor(.1, .2, .3, 1)
uf.name:SetFontObject({1, 1, 1, .8})
assert(uf.name.writes == releasedWrites, "a released NPC still handled vertex or font changes")
assert(Paint(uf, uf.unit))
combat, uf.name.access = true, false
Names.RestoreNameOnly(uf)
uf.name:SetVertexColor(.8, .1, .2, 1)
combat, uf.name.access = false, true
assert(Paint(uf, uf.unit) and uf.name.glyphR == .4 and uf.name.glyphG == .4,
    "a new occupant inherited a matching cached font color after its predecessor's blocked release")
Names.RestoreNameOnly(uf)
assert(uf.name.vr == .8 and uf.name.vg == .1 and uf.name.vb == .2 and uf.name.va == 1
    and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1 and uf.name.a == .8,
    "the new lease restored the previous occupant's baseline")
uf.name.GetVertexColor = function(self) return self.vr, self.vg, self.vb end
assert(Paint(uf, uf.unit))
uf.name:SetVertexColor(.1, .3, .8, .25)
uf.name:SetTextColor(.7, .2, .6, .65)
nativeUpdate(uf)
assert(uf.name.vr == 1 and uf.name.vg == 1 and uf.name.va == .25 and uf.name.a == .65,
    "an RGB-only vertex getter lost an explicit vertex alpha or imported the font alpha")
Names.RestoreNameOnly(uf)
assert(uf.name.vr == .1 and uf.name.vg == .3 and uf.name.va == .25
    and uf.name.r == .7 and uf.name.g == .2 and uf.name.a == .65,
    "release mixed an RGB-only vertex channel with the font channel")
assert(Paint(uf, uf.unit))
uf.name:SetVertexColor(.2, .5, .8)
uf.name:SetFontObject({ .4, .4, .4, .3 })
Names.RestoreNameOnly(uf)
assert(uf.name.vr == .2 and uf.name.va == nil and uf.name.r == .4 and uf.name.a == .3,
    "an omitted vertex alpha or a new matching font object inherited an old baseline")
UnitIsPlayer = function() return secret end
assert(not Paint(uf, uf.unit) and trainerClassReads == 0, "restricted identity triggered class coloring")
print("Name-only scope selection, color, combat deferral and restoration passed")
