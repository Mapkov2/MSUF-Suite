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
local private = { NS = NS, Suite = { Public = Public, Finite = Finite },
    Mode = { GROUP_NAMES_ONLY = 3, SHOW = 2, HIDE = 3, NPC_NAMES_ONLY = 4 },
    RoleKey = { Caster = { color = "enemyCasterColor" }, Neutral = { color = "enemyNeutralColor" } } }
UnitReaction = function() return reaction end
-- Skin.lua's plate hook registry (private.HookPlates) and the mixin it hooks.
local plateHooks = {}
private.HookPlates = function(method, callback) plateHooks[method] = callback end
NamePlateUnitFrameMixin = { UpdateShowOnlyName = function() end }
local dead, tapDenied = false, false
UnitIsDead = function() return dead end
UnitIsTapDenied = function() return tapDenied end
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
    function region:SetVertexColor(...)
        local r, g, b, a = ...
        self.vertexWrites, self.vertexArgs = (self.vertexWrites or 0) + 1, select("#", ...)
        self.vr, self.vg, self.vb, self.va = r, g, b, a
        self.glyphR, self.glyphG, self.glyphB = r, g, b
    end
    function region:GetText() return self.text end
    function region:SetText(text) self.text = text end
    function region:IsShown() return true end
    function region:IsForbidden() return false end
    -- An omitted alpha keeps the current one; the record shows whether a writer passed one.
    function region:SetTextColor(...)
        local r, g, b, a = ...
        self.writes, self.textArgs = (self.writes or 0) + 1, select("#", ...)
        if self.refuseOnce then self.refuseOnce = nil return end
        self.r, self.g, self.b = r, g, b
        if self.textArgs >= 4 then self.a = a end
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

-- A profile can enable the host's name-part resolver after Name only registered its
-- native hook. Both normal entry points must leave NPC color to Name only.
local paintCalls, formats, sharedEnabled = 0, 0, true
NS.IsCombatLocked = function() return combat end
NS.NameplateText = {
    Compile = function() return { displayName = sharedEnabled, shared = sharedEnabled and {} or nil } end,
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
        "a later host name hook replaced the neutral name-only palette")
    assert(uf.name.text == "Neutral " and formats > 0, "color ownership disabled the host name resolver")
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
-- Blizzard colors names through the vertex: an NPC name carries its color there too, so no combination
-- rule of the client can leave it white or tinted. On a FontString both setters reach its alpha: the
-- vertex is written as Blizzard writes it (RGB only) and the font color keeps its own known alpha.
assert(uf.name.text == "Neutral quest giver" and uf.name.vr == .9 and uf.name.vg == .86 and uf.name.vb == 0
    and uf.name.vertexArgs == 3 and uf.name.r == .9 and uf.name.a == .75 and uf.name.alpha == 1,
    "the NPC color missed a channel or passed an opacity")
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
-- Blizzard paints an NPC shown like a player in its class color; the name keeps the NPC's own color.
assert(label.r == 0 and label.g == 1 and label.b == 0 and barReads == 0,
    "a friendly NPC name took or sampled the hidden bar's class color")
uf.healthBar:SetStatusBarColor(1, 1, 1)
assert(label.r == 0 and label.g == 1 and label.b == 0, "a white stock or priest bar erased the friendly NPC reaction")
uf.healthBar:SetStatusBarColor(.25, .7, .85)
label:SetTextColor(1, 1, 1, .8)
assert(label.r == 0 and label.g == 1 and label.a == .8, "a later font writer left the friendly NPC white")
dead = true
uf.healthBar:SetStatusBarColor(.5, .5, .5)
assert(label.r == .5 and label.g == .5 and label.b == .5, "the native death recolor did not grey the friendly NPC")
dead, tapDenied = false, true
uf.healthBar:SetStatusBarColor(.9, .9, .9)
assert(label.r == .5 and label.g == .5, "a tapped NPC kept its reaction color")
tapDenied = false
uf.healthBar:SetStatusBarColor(.4, .4, .4)
assert(label.r == 0 and label.g == 1 and label.b == 0, "a native bar recolor leaked onto the friendly NPC name")
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
-- The white-name bug: a client that withholds the font getters still gets the NPC color on a new
-- label. Blizzard only ever writes the vertex, so waiting for a public font write never ended.
uf.name.GetTextColor = function() return secret, secret, secret, secret end
assert(Paint(uf, uf.unit) and uf.name.r == .4 and uf.name.vr == .4 and uf.name.glyphR == .4 and uf.name.glyphG == .4,
    "a withheld font getter left a new NPC name unpainted")
local withheldWrites = uf.name.writes
nativeUpdate(uf)
assert(uf.name.writes == withheldWrites, "a withheld readback alone rewrote the NPC color")
uf.name:SetVertexColor(1, 1, 1, 1)
assert(uf.name.glyphR == .4 and uf.name.vr == .4, "Blizzard's vertex write left the NPC white while the getters were withheld")
uf.name:SetTextColor(1, 1, 1, .6)
assert(uf.name.r == .4 and uf.name.g == .4 and uf.name.b == .4 and uf.name.a == .6,
    "a public font write left the text white while the getter was withheld")
uf.name.GetTextColor = getFont
uf.name:SetVertexColor(.4, .4, .4, .35)
assert(uf.name.vr == .4 and uf.name.vg == .4 and uf.name.vb == .4 and uf.name.va == .35 and uf.name.a == .6,
    "a matching native vertex write changed the NPC color or an opacity")
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
assert(uf.name.vr == 1 and uf.name.vg == 0 and uf.name.vb == 0 and uf.name.vertexArgs == 3
    and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1 and uf.name.a == .6,
    "release did not restore both native tints, the font opacity, or passed a vertex alpha")
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
assert(uf.name.vr == .8 and uf.name.vg == .1 and uf.name.vb == .2 and uf.name.vertexArgs == 3
    and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 1 and uf.name.a == .8,
    "the new lease restored the previous occupant's baseline")
uf.name.GetVertexColor = function(self) return self.vr, self.vg, self.vb end
assert(Paint(uf, uf.unit))
uf.name:SetVertexColor(.1, .3, .8, .25)
uf.name:SetTextColor(.7, .2, .6, .65)
nativeUpdate(uf)
assert(uf.name.vr == .4 and uf.name.vg == .4 and uf.name.vertexArgs == 3 and uf.name.a == .65,
    "an RGB-only vertex getter passed a vertex alpha or lost the font alpha")
Names.RestoreNameOnly(uf)
assert(uf.name.vr == .1 and uf.name.vg == .3 and uf.name.vertexArgs == 3
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
do
    assert(loadfile(root .. "/MSUF_Suite/Core/NameplateText.lua"))("Suite", NS)
    local custom = NS.NameplateText.CustomNameColor({ shared = { text = { nameColor = { r = .6, g = .25, b = .8 } } } })
    local portable = NS.NameplateText.CustomNameColor({ shared = { portable = {
        nameColorMode = "CUSTOM", nameColorR = .3, nameColorG = .8, nameColorB = .4,
    } } })
    assert(custom and custom.r == .6 and portable and portable.g == .8)
    assert(not NS.NameplateText.CustomNameColor({ shared = { textColor = { r = 1, g = 1, b = 1 } } }),
        "the default text color became an explicit override")

    Names.RestoreNameOnly(uf)
    UnitIsPlayer = function() return false end
    UnitSelectionColor = function() return .1, .8, .2 end
    reaction, uf.isFriend = 5, true
    config.friendlyNPCs, config.friendlyNpcPlateNameTypeColor = 5, false
    uf.healthBar:SetStatusBarColor(1, 1, 1)
    private.NameText.CustomNameColor = function(scope)
        assert(scope == "friendlyNpc")
        return custom
    end
    Names.ConfigureNameOnly()
    assert(Paint(uf, uf.unit) and uf.name.r == .6 and uf.name.b == .8,
        "a hidden white bar overrode the custom name text color")
    uf.healthBar:SetStatusBarColor(.4, .4, .4)
    assert(uf.name.r == .6 and uf.name.b == .8, "a later health tint overrode the custom name text color")

    private.NameText.CustomNameColor = nil
    uf.healthBar:SetStatusBarColor(1, 1, 1)
    Names.ConfigureNameOnly()
    assert(Paint(uf, uf.unit) and uf.name.r == 0 and uf.name.g == 1 and uf.name.b == 0,
        "a priest NPC's white class bar painted its name white with color by type disabled")
    reaction = 4
    config.neutralPlateNameOnly, config.neutralPlateNameTypeColor = true, false
    uf.isFriend = false
    Names.ConfigureNameOnly()
    uf.healthBar:SetStatusBarColor(.96, .55, .73)
    assert(Paint(uf, uf.unit) and Names.NameOnlyScope(uf) == "neutral"
        and uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 0,
        "a paladin NPC's pink class bar painted a neutral name with color by type disabled")
    reaction = secret
    uf.healthBar:SetStatusBarColor(.2, .2, .2)
    assert(uf.name.r == 1 and uf.name.g == 1 and uf.name.b == 0, "an unreadable reaction replaced the neutral color")
    reaction, uf.isFriend, config.neutralPlateNameTypeColor = 5, true, true
    Names.RestoreNameOnly(uf)
    uf.healthBar:SetStatusBarColor(1, 1, 1)

    reaction, uf.isFriend, config.enemyPlateNameTypeColor = 3, false, true
    Names.ConfigureNameOnly()
    assert(Paint(uf, uf.unit) and uf.name.g == .8 and uf.name.r == .1,
        "a white hidden bar discarded the public NPC reaction color while color by type was enabled")
    Names.RestoreNameOnly(uf)
end
-- NPCs Blizzard displays like players (UnitTreatAsPlayerForDisplay) arrive on friendly-player
-- plates: name only, in a player class color. Unless Show forces their bar (Keep Blizzard, Hide,
-- world names) they keep that native plate and take only their NPC color.
do
    Names.RestoreNameOnly(uf)
    UnitIsPlayer = function() return false end
    uf.name, uf.isPlayer, uf.isFriend, uf.showOnlyName, reaction, dead, tapDenied = Region(1), true, true, true, 5, false, false
    uf.healthBar, uf.HealthBarsContainer.alpha, config.friendlyNpcPlateNameTypeColor = nil, .8, true
    for _, mode in ipairs({ 1, 3, 4 }) do
        config.friendlyNPCs = mode
        Names.ConfigureNameOnly()
        uf.name:SetVertexColor(1, 1, 1, 1)
        assert(not Paint(uf, "nameplate5") and not Names.IsNameOnly(uf) and Names.OwnsColor(uf),
            "a player-style NPC changed its native plate or lost its NPC color in mode " .. mode)
        assert(uf.name.glyphR == 0 and uf.name.glyphG == 1 and uf.name.glyphB == 0 and uf.HealthBarsContainer.alpha == .8,
            "a player-style NPC kept its class-colored name or lost a native region in mode " .. mode)
        uf.name:SetVertexColor(.96, .55, .73, 1)
        assert(uf.name.glyphR == 0 and uf.name.glyphG == 1, "a native class-color repaint replaced the NPC color")
        assert(not Names.RefreshRole(uf, nil, nil), "a color-only NPC skipped the plate's own role refresh")
    end
    uf.showOnlyName = false
    assert(not Paint(uf, "nameplate5") and not Names.OwnsColor(uf), "an NPC with a native health bar was recolored")
    uf.showOnlyName = true
    config.friendlyNPCs = 2
    Names.ConfigureNameOnly()
    assert(not Paint(uf, "nameplate5") and not Names.OwnsColor(uf), "Show recolored a player-style NPC it gives a bar")
    config.friendlyNPCs, config.friendlyNpcSkinEnabled = 4, false
    Names.ConfigureNameOnly()
    assert(not Paint(uf, "nameplate5") and not Names.OwnsColor(uf), "a disabled Friendly NPC skin still recolored an NPC")
    config.friendlyNpcSkinEnabled = nil

    -- The native driver can handle NAME_PLATE_UNIT_ADDED after the Suite: showOnlyName is still unset
    -- at our paint. The unit and the CVar decide then; a value Blizzard did set always wins.
    local displayed, friend, namesCVar, cvarReads = true, true, true, 0
    UnitTreatAsPlayerForDisplay = function() return displayed end
    UnitIsFriend = function(a, b) assert(a == "player" and b == "nameplate6") return friend end
    C_CVar = { GetCVarBool = function(key)
        assert(key == "nameplateShowOnlyNameForFriendlyPlayerUnits")
        cvarReads = cvarReads + 1
        return namesCVar
    end }
    config.friendlyNPCs = 1
    Names.ConfigureNameOnly()
    Names.RestoreNameOnly(uf)
    uf.name, uf.showOnlyName = Region(1), nil
    assert(not Paint(uf, "nameplate6") and Names.OwnsColor(uf) and uf.name.glyphG == 1 and uf.name.glyphR == 0,
        "a player-style NPC painted before the native driver kept its class color")
    uf.name:SetVertexColor(.96, .55, .73, 1) -- the driver's later UpdateNameClassColor
    assert(uf.name.glyphR == 0 and uf.name.glyphG == 1, "the driver's late class color replaced the NPC color")
    for _, case in ipairs({ { "displayed", false }, { "friend", false }, { "friend", secret }, { "namesCVar", false } }) do
        Names.RestoreNameOnly(uf)
        displayed, friend, namesCVar = true, true, true
        if case[1] == "displayed" then displayed = case[2] elseif case[1] == "friend" then friend = case[2] else namesCVar = case[2] end
        assert(not Paint(uf, "nameplate6") and not Names.OwnsColor(uf), "an NPC Blizzard shows with a bar was recolored: " .. case[1])
    end
    displayed, friend, namesCVar = true, true, true
    uf.showOnlyName, cvarReads = false, 0
    assert(not Paint(uf, "nameplate6") and not Names.OwnsColor(uf) and cvarReads == 0,
        "the unit overrode the driver's own name-only decision")
    uf.showOnlyName = true
    assert(not Paint(uf, "nameplate6") and Names.OwnsColor(uf) and cvarReads == 0, "a set native field was read again")

    -- Death and tapping arrive as a native name repaint; an unreadable reaction resolves at the next one.
    dead = true
    uf.name:SetVertexColor(.5, .5, .5, 1)
    assert(uf.name.glyphR == .5 and uf.name.glyphG == .5 and uf.name.glyphB == .5, "a dead color-only NPC kept its reaction")
    dead = false
    uf.name:SetVertexColor(1, 1, 1, 1)
    assert(uf.name.glyphR == 0 and uf.name.glyphG == 1, "a resurrected color-only NPC stayed grey")
    Names.RestoreNameOnly(uf)
    uf.name, reaction = Region(1), secret
    assert(not Paint(uf, "nameplate6") and not Names.OwnsColor(uf), "an unreadable reaction became an NPC color")
    reaction = 4
    uf.name:SetVertexColor(1, 1, 1, 1)
    assert(Names.OwnsColor(uf) and uf.name.glyphR == 1 and uf.name.glyphG == 1 and uf.name.glyphB == 0,
        "a withheld reaction never colored the NPC once readable")
    Names.RestoreNameOnly(uf)
    UnitTreatAsPlayerForDisplay, UnitIsFriend, C_CVar, reaction = nil, nil, nil, 5
end

-- Without a Name only display Skin.Paint never calls ApplyNameOnly. Its NPC-on-name-only-plate branch
-- and Blizzard's UpdateShowOnlyName hook (either order) both reach SyncNPCHealth instead.
do
    config.enemyPlateNameOnly, config.neutralPlateNameOnly, config.friendlyNPCs = false, false, 1
    Names.ConfigureNameOnly()
    assert(not Names.nameOnlyEnabled and Names.nativeNpcNames, "Keep Blizzard turned on a Name only display")
    UnitIsPlayer = function() return false end
    uf.name, uf.unit, uf.showOnlyName, uf.isFriend, reaction = Region(1), "nameplate7", true, true, 5
    uf.HealthBarsContainer.healthBar, uf.HealthBarsContainer.alpha = nil, .8
    Names.SyncNPCHealth(uf, "friendlyNpc", false)
    assert(Names.OwnsColor(uf) and not Names.IsNameOnly(uf) and uf.name.glyphR == 0 and uf.name.glyphG == 1
        and uf.HealthBarsContainer.alpha == .8, "Keep Blizzard left a player-style NPC in its class color")
    uf.name:SetVertexColor(.96, .55, .73, 1)
    assert(uf.name.glyphR == 0 and uf.name.glyphG == 1, "a native class repaint won over the NPC color under Keep Blizzard")
    uf.showOnlyName = false -- the names-only CVar went off: Blizzard's UpdateShowOnlyName
    Names.SyncNPCHealth(uf, "friendlyNpc", false)
    assert(not Names.OwnsColor(uf), "an NPC back on its health bar kept the name-only color")
    uf.showOnlyName = true
    Names.SyncNPCHealth(uf, "neutralNpc", false)
    Names.SyncNPCHealth(uf, nil)
    assert(not Names.OwnsColor(uf), "a plate that is not a Friendly NPC took the color-only path")
    owner.active = false
    Names.SyncNPCHealth(uf, "friendlyNpc", false)
    assert(not Names.OwnsColor(uf), "a disabled module recolored an NPC")
    owner.active = true
    -- A faction change the Suite already recorded as hostile: Blizzard's UpdateShowOnlyName follows.
    Names.SyncNPCHealth(uf, "friendlyNpc", false)
    assert(Names.OwnsColor(uf) and plateHooks.UpdateShowOnlyName, "the native name-only hook was not registered")
    plateHooks.UpdateShowOnlyName(uf)
    assert(Names.OwnsColor(uf), "an unchanged native name-only plate lost its NPC color")
    uf.showOnlyName = false
    plateHooks.UpdateShowOnlyName(uf)
    assert(not Names.OwnsColor(uf) and uf.name.r ~= 0, "an NPC that lost its name-only plate kept the NPC color")
    uf.showOnlyName = true
    Names.SyncNPCHealth(uf, "friendlyNpc", false)
    config.friendlyNPCs = 2
    Names.ConfigureNameOnly()
    assert(not Names.OwnsColor(uf) and uf.name.r ~= 0, "switching to Show kept the color-only NPC")
    config.friendlyNPCs = 1
    Names.ConfigureNameOnly()
    Names.SyncNPCHealth(uf, "friendlyNpc", false)
    config.friendlyNPCs = 5
    Names.ConfigureNameOnly()
    assert(not Names.OwnsColor(uf), "switching to the Suite's own Name only kept a color-only state")
    Names.RestoreNameOnly(uf)
end

-- The reported bug (Friendly NPCs: Name only, a plain NPC): the name stayed white. Clients disagree
-- on how a FontString's vertex and text colors combine and can withhold both getters. Under each
-- rule (the vertex wins, the text wins, the last write wins), with Blizzard's name refresh before
-- and after our paint, the NPC must show its reaction color.
do
    Names.RestoreNameOnly(uf)
    UnitIsPlayer = function() return false end
    config.friendlyNPCs, config.friendlyNpcPlateNameTypeColor, config.enemyPlateNameOnly = 5, false, false
    reaction, dead, tapDenied, uf.isFriend, uf.isPlayer, uf.showOnlyName = 5, false, false, true, false, false
    uf.healthBar, uf.HealthBarsContainer.healthBar = nil, nil
    Names.ConfigureNameOnly()
    for _, model in ipairs({ "vertex", "text", "last" }) do
        for _, blizzardFirst in ipairs({ true, false }) do
            Names.RestoreNameOnly(uf)
            local label = Region(1)
            label.GetTextColor = function() return secret, secret, secret, secret end
            label.GetVertexColor = label.GetTextColor
            uf.name = label
            -- Both setters reach a FontString's alpha aspect: an explicit nil counts as 0 (the worst
            -- case), an omitted one keeps it. The name must stay visible without being targeted.
            local shown = 1
            for _, method in ipairs({ "SetVertexColor", "SetTextColor" }) do
                local set = label[method]
                label[method] = function(self, ...)
                    if select("#", ...) >= 4 then shown = select(4, ...) or 0 end
                    return set(self, ...)
                end
            end
            -- CompactUnitFrame_UpdateName: the text, then the vertex color (white outside Legacy).
            local function Refresh() label:SetText("Lieutenant Prenish") label:SetVertexColor(1, 1, 1) end
            local function Visible()
                if model == "vertex" then return label.vr, label.vg, label.vb end
                if model == "text" then return label.r, label.g, label.b end
                return label.glyphR, label.glyphG, label.glyphB
            end
            if blizzardFirst then Refresh() end
            assert(Paint(uf, "nameplate8") and Names.NameOnlyScope(uf) == "friendlyNpc", "Name only skipped a friendly NPC")
            local r, g, b = Visible()
            assert(not blizzardFirst or r == 0 and g == 1 and b == 0, ("our paint after Blizzard's left %s,%s,%s (%s wins)"):format(
                tostring(r), tostring(g), tostring(b), model))
            assert(shown == 1, "our paint hid the untargeted NPC name through a color alpha")
            Refresh()
            assert(shown == 1, "a native name refresh left the untargeted NPC name hidden")
            r, g, b = Visible()
            assert(r == 0 and g == 1 and b == 0, ("a friendly NPC showed %s,%s,%s (%s wins, Blizzard %s)"):format(
                tostring(r), tostring(g), tostring(b), model, blizzardFirst and "first" or "second"))
        end
    end
    -- A fade can be under way when we paint: its read-back alpha of 0 is never written into the color.
    Names.RestoreNameOnly(uf)
    local fading = Region(1)
    fading.GetTextColor = function() return 1, 1, 1, 0 end
    fading.GetVertexColor = fading.GetTextColor
    uf.name = fading
    assert(Paint(uf, "nameplate8") and fading.textArgs == 3 and fading.vertexArgs == 3 and fading.a == .9
        and fading.vr == 0 and fading.r == 0, "a read-back fade alpha was written into the NPC name color")
    -- Release gives both withheld channels Blizzard's white back, never an earlier lease's baseline.
    Names.RestoreNameOnly(uf)
    local label = Region(1)
    uf.name = label
    label:SetTextColor(.2, .3, .4, 1)
    assert(Paint(uf, "nameplate8"))
    Names.RestoreNameOnly(uf)
    assert(label.r == .2 and label.g == .3 and label.vr == 1, "a readable lease lost its native colors on release")
    assert(Paint(uf, "nameplate8"))
    label.GetTextColor = function() return secret, secret, secret, secret end
    label.GetVertexColor = label.GetTextColor
    assert(Paint(uf, "nameplate9") and label.r == 0 and label.vr == 0, "the pooled frame's next NPC stayed unpainted")
    Names.RestoreNameOnly(uf)
    assert(label.r == 1 and label.g == 1 and label.b == 1 and label.vr == 1 and label.vg == 1 and label.vb == 1,
        "a withheld lease kept the NPC color or restored an earlier lease's baseline")
end

-- Keep Blizzard is the default: its color-only NPCs follow per-label hooks, never a global hook.
do
    local hooks = #nameHooks
    nameHooks = {}
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/FriendlyNames.lua"))("Nameplates", private)
    private.FriendlyNames.Bind({ config = { friendlyNPCs = 1 }, active = true, pendingPlates = {} })
    private.FriendlyNames.ConfigureNameOnly()
    assert(private.FriendlyNames.nativeNpcNames and not private.FriendlyNames.nameOnlyEnabled and #nameHooks == 0
        and hooks > 0, "the default Friendly NPC display installed a global hook or a Name only display")
end
print("Name-only scope selection, color, combat deferral and restoration passed")
