local root = assert(arg[1])
local support = dofile(root .. "/tools/tests/suite_test_support.lua")
local toc = support.TocFiles(root, "MSUF_Suite_Nameplates")
assert(table.concat(toc, ",") == "Bootstrap.lua,Layout.lua,Roles.lua,Text.lua,Skin.lua",
    "nameplate runtime must stay in its own optional addon")
local installed, events = nil, {}
local scans = 0
local combat = false
local hasMana = false
local classification, isBoss = "normal", false
local instanceType, unitLevel = "none", 90
local focusUnit, targetUnit, questUnit, tappedUnit = nil, nil, false, false
local threatStatus = nil
local threatCalls = {}
local isTank, grouped, onThreatList = false, false, false
PlayerUtil = { IsPlayerEffectivelyTank = function() return isTank end }
UnitInParty = function() return grouped end
CompactUnitFrame_IsOnThreatListWithPlayer = function() return onThreatList end
UnitIsUnit = function(unit, other)
    assert(unit == "nameplate1")
    return (other == "focus" and focusUnit == unit) or (other == "target" and targetUnit == unit)
end
UnitIsTapDenied = function() return tappedUnit end
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return questUnit end }
IsInInstance = function() return instanceType ~= "none", instanceType end
UnitLevel = function(unit) return unit == "player" and 90 or unitLevel end
UnitHasPowerType = function(unit, powerType)
    assert(unit == "nameplate1" and powerType == 0)
    return hasMana
end
UnitPowerType = function(unit)
    assert(unit == "nameplate1")
    if hasMana == "secret" then return "secret", "secret" end
    return hasMana and 0 or 3, hasMana and "MANA" or "ENERGY"
end
UnitClassification = function() return classification end
UnitIsBossMob = function() return isBoss end
UnitThreatSituation = function(...)
    threatCalls[#threatCalls + 1] = { "situation", ... }
    return threatStatus
end
UnitThreatLeadSituation = function(...)
    threatCalls[#threatCalls + 1] = { "lead", ... }
    return threatStatus
end

local nativeAnchor = {}
local function Region()
    local r = { shown = true }
    r.points = { { "CENTER", nativeAnchor, "CENTER", 0, 0 } }
    function r:SetTexture(value) self.texture, self.atlas = value, nil end
    function r:GetTexture() return self.texture end
    function r:SetAtlas(value) self.atlas, self.texture = value, "atlas-file" end
    function r:GetAtlas() return self.atlas end
    function r:SetTexCoord(...)
        local coords = { ... }
        if #coords == 4 then
            local l, r, t, b = unpack(coords)
            coords = { l, t, l, b, r, t, r, b }
        end
        self.coords = coords
    end
    function r:GetTexCoord() return unpack(self.coords or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
    function r:AddMaskTexture(mask) self.mask = mask end
    function r:RemoveMaskTexture(mask) if self.mask == mask then self.mask = nil end end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetVertexColor(...) self.vertexColor = { ... } end
    function r:SetAllPoints(target) self.allPoints = target end
    function r:SetPoint(point, ...)
        for i, old in ipairs(self.points) do
            if old[1] == point then self.points[i] = { point, ... }; return end
        end
        self.points[#self.points + 1] = { point, ... }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:GetNumPoints() return #self.points end
    function r:GetPoint() error("Can't measure restricted regions") end
    function r:SetPointsOffset(x, y)
        self.offsetX, self.offsetY = x, y
        self.offsetWrites = (self.offsetWrites or 0) + 1
    end
    function r:SetHeight(value) self.height = value end
    function r:SetWidth(value) self.width = value end
    function r:SetSize(width, height) self.width, self.height = width, height end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetAlpha(value) self.alpha = value end
    function r:GetAlpha() return self.alpha or 1 end
    function r:SetFrameLevel(value) self.level = value end
    function r:GetFrameLevel() return self.level or 1 end
    function r:EnableMouse(value) self.mouse = value end
    function r:CreateLine() return Region() end
    function r:SetStartPoint(...) self.startPoint = { ... } end
    function r:SetEndPoint(...) self.endPoint = { ... } end
    function r:SetThickness(value) self.thickness = value end
    function r:SetRotation(value) self.rotation = value end
    function r:CreateTexture(_, layer, _, sublevel)
        self.created = (self.created or 0) + 1
        local texture = Region()
        texture.layer, texture.sublevel = layer, sublevel or 0
        return texture
    end
    function r:CreateMaskTexture()
        self.masksCreated = (self.masksCreated or 0) + 1
        return Region()
    end
    function r:CreateFontString() return Region() end
    function r:SetFont(path, size, flags) self.font, self.fontSize, self.flags = path, size, flags or ""; return true end
    function r:GetFont()
        self.fontReads = (self.fontReads or 0) + 1
        return self.font, self.fontSize, self.flags or ""
    end
    function r:GetShadowColor() return 0, 0, 0, 0.6 end
    function r:GetShadowOffset() return 1, -1 end
    function r:SetShadowColor(...) self.shadow = { ... }; self.shadowColorWrites = (self.shadowColorWrites or 0) + 1 end
    function r:SetShadowOffset(...) self.shadowOffset = { ... }; self.shadowOffsetWrites = (self.shadowOffsetWrites or 0) + 1 end
    function r:SetText(value) self.text = value end
    function r:SetTextColor(...) self.textColor = { ... } end
    function r:SetJustifyH(value) self.justify = value end
    return r
end

CreateFrame = function(_, _, parent) local frame = Region(); frame.parent = parent; return frame end
MSUF_NS = {}
assert(loadfile(root .. "/../MidnightSimpleUnitFrames-Classic/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_BossTargetIndicator.lua"))("MidnightSimpleUnitFrames", MSUF_NS)

local bar, cast, name, aura = Region(), Region(), Region(), Region()
local raidFrame, raidIcon = Region(), Region()
raidIcon:SetAlpha(0.8)
raidFrame.RaidTargetIcon = raidIcon
NamePlateSetupOptions = { unitNameAnchorStyle = 1, useClassicCastBar = false, spellNameInsideCastBar = false }
-- Inspect the mock's anchor plus displacement directly. The production code
-- must never invoke GetPoint, which raises the reported FrameMeasurement error.
local function Placed(region, index, axis)
    return region.points[index][axis] + (axis == 4 and (region.offsetX or 0) or (region.offsetY or 0))
end
local auraButton = Region()
function auraButton:IsMouseClickEnabled() return self.mouseClickEnabled ~= false end
function auraButton:SetMouseClickEnabled(value)
    self.mouseClickEnabled = value
    self.mouseWrites = (self.mouseWrites or 0) + 1
end
aura.auraItemFramePool = { EnumerateActive = function()
    local delivered = false
    return function()
        if delivered then return nil end
        delivered = true
        return auraButton
    end
end }
function aura:RefreshAuras() end
name:SetFont("native-font", 10)
function bar:SetStatusBarColor(r, g, b)
    self.barColor = { r, g, b }
    if self.colorHook then self.colorHook(self) end
end
bar.barTexture = Region()
bar.barTexture:SetTexture("native-health")
bar.barColor = { 0.5, 0.5, 0.5 }
bar.Text = Region()
function bar:GetStatusBarTexture() return self.barTexture end
cast.statusTexture = Region()
cast.Text = Region()
cast.Text:SetFont("native-cast-font", 10, "")
cast.statusTexture:SetTexture("native-cast")
cast.Background = Region()
cast.Background:SetAlpha(.8)
-- Native cast rendering is exclusively Blizzard's, even with old skin keys.
function cast:GetStatusBarTexture() error("do not inspect native cast fill") end
function cast:SetStatusBarTexture() error("do not replace native cast fill") end
function cast:GetStatusBarColor() error("do not inspect native cast color") end
function cast:SetStatusBarColor() error("do not replace native cast color") end
function cast:CreateTexture() error("do not create cast overlays") end
function cast:UpdateBarFillTexture() error("do not invoke native cast logic") end
local healthContainer = Region()
healthContainer.healthBar = bar
local uf = {
    isFriend = false, isPlayer = false, name = name, AurasFrame = aura,
    RaidTargetFrame = raidFrame,
    HealthBarsContainer = healthContainer, CastBarsContainer = { castBar = cast },
}
uf.CreateTexture, uf.CreateFontString = bar.CreateTexture, bar.CreateFontString
function uf:UpdateAnchors()
    error("nameplate skin must not reenter native layout")
end
local plate = { UnitFrame = uf, unitToken = "nameplate1" }
function plate:ApplyFrameOptions()
    error("nameplate skin must not replay CompactUnitFrame setup or unit data")
end
CompactUnitFrame_UpdateHealthColor = function()
    error("nameplate skin must not manually recalculate Blizzard health color")
end

C_NamePlate = {
    GetNamePlates = function() scans = scans + 1; return { plate } end,
    GetNamePlateForUnit = function(unit)
        return (unit == "nameplate1" or (unit == "target" and targetUnit == "nameplate1") or (unit == "focus" and focusUnit == "nameplate1")) and plate or nil
    end,
}
local liveCVars = {
    nameplateSimplifiedTypes = string.char(1, 79), -- four simplified types
    nameplateInfoDisplay = string.char(1, 68), -- rarity icon only
    nameplateCastBarDisplay = string.char(1, 96), -- future sixth flag must survive
}
C_CVar = { GetCVar = function(key) return liveCVars[key] end }
NamePlateUnitFrameMixin = { ApplyFrameOptions = function() error("do not invoke native setup") end }
local layoutHook, fontHook
local layoutCallbacks = {}
MSUF_UpdateCastbarVisuals = function() end
hooksecurefunc = function(frame, method, callback)
    if type(frame) == "string" then error("do not install cast media hooks") end
    if frame == NamePlateUnitFrameMixin and method == "ApplyFrameOptions" then fontHook = callback; return end
    if frame == cast then error("do not hook native cast logic") end
    if frame == uf and method == "UpdateAnchors" then
        layoutCallbacks[#layoutCallbacks + 1] = callback
        layoutHook = function(frame) for _, fn in ipairs(layoutCallbacks) do fn(frame) end end
        return
    end
    assert(frame == aura and method == "RefreshAuras",
        "nameplate skin must not hook native layout")
end

local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Client = { IsAddOnLoaded = function() return true end },
    MSUFMedia = { barTexture = "fallback-msuf-texture" },
}
local cvars, restored = {}, {}
local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value end,
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end,
    SetFont = function(region, path, size, flags) region:SetFont(path or "fallback-font", size, flags) end,
    ResolveFont = function(key) return key ~= "" and key or nil end,
    RestoreCVar = function(_, key)
        restored[key] = true
        if key == "nameplateInfoDisplay" then liveCVars[key] = string.char(1, 68) end
    end,
    Install = function(_, module) installed = module end,
}
local context = {
    Event = function(_, event, callback) events[event] = callback end,
    CVar = function(_, key, value) cvars[key] = value; liveCVars[key] = value end,
}
local chunk = assert(loadfile(root .. "/MSUF_Suite_Nameplates/Skin.lua"))
NS.Suite = S
NS.RGB, NS.Public, NS.Finite, NS.ResolveFont = S.RGB, S.Public, S.Finite, S.ResolveFont
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
local private = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Layout.lua"))("MSUF_Suite_Nameplates", private)
for _, file in ipairs({ "Roles", "Text" }) do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file .. ".lua"))("MSUF_Suite_Nameplates", private)
end
chunk("MSUF_Suite_Nameplates", private)
local module = assert(installed)
module.context = context
module.config = {
    look = 1, enemy = true, friendly = true,
    nativeStyle = 2, nativeSize = 3, enemyTextMode = 4,
    enemyRarityIcon = 1, enemyRaidIcon = true,
    enemyRoleColors = true, enemyMeleeColor = "be301d", enemyCasterColor = "00bfff",
    enemyMinibossColor = "9370db", enemyBossColor = "ff00ff",
    enemyQuestColors = true, enemyQuestColor = "ff7e00", enemyTappedColor = "6e6e6e",
    enemyFocusColor = "ff00ff", enemyTargetColor = "ffffff", enemyTargetMarker = true,
    enemyTargetMarkerSize = 16, enemyColorsInDungeons = true, enemyColorsOutside = true,
    enemyTargetOffsetX = 0, enemyTargetOffsetY = 0,
    enemyEliteMarker = true, enemyEliteMarkerSize = 14, enemyEliteOffsetX = -13,
    enemyEliteOffsetY = 0, enemyQuestMarker = true, enemyQuestMarkerSize = 15,
    enemyQuestOffsetX = 0, enemyQuestOffsetY = 17,
    enemyTankMode = false, enemyThreatLostColor = "ff4d32",
    enemyThreatWarningColor = "ffbd38", enemyTrivialColor = "777777",
    enemyNeutralColor = "e5bd45",
    enemyBackdropColor = "080b10", friendlyBackdropColor = "080b10",
    enemyBorderColor = "111418", friendlyBorderColor = "111418",
    enemyBorderSize = 1, friendlyBorderSize = 1,
    enemyNameSize = 12, friendlyNameSize = 14,
    enemyCastSize = 11, enemyHealthTextSize = 11, enemyCastFont = "",
    enemyCastEnabled = 2, enemyCastDisplay = 2,
    enemyCastSpellName = true, enemyCastSpellIcon = false,
    enemyCastSpellTarget = false, enemyCastImportant = true, enemyCastTargetHighlight = true,
    -- Legacy settings must not reactivate cast rendering or media hooks.
    enemyCastSkin = true, enemyCastFollowMSUF = true, enemyCastBorderSize = 1,
    enemyCastBorderColor = "000000", enemyCastBackdropColor = "171a1e",
    enemyCastBackdropAlpha = 85, enemyCastFillColor = "f2c34e", enemyCastFillAlpha = 35,
    enemyCastTexture = "legacy-custom-cast",
    enemyNameFont = "", friendlyNameFont = "",
    friendlyCastTextEnabled = false,
    friendlyNamesOnly = 2, classColors = 1, friendlyNameClassColor = 2, friendlyRealm = 1,
    personalAuras = 1,
    auraClickthrough = false,
}
module.active = true
MSUF_GetCastbarTexture = function() error("do not link nameplate cast textures") end
MSUF_GetCastbarBackgroundTexture = function() error("do not link nameplate cast backgrounds") end
MSUF_GetCastbarBackgroundColor = function() return 0.1, 0.2, 0.3, 0.8 end
module:Enable()
assert(scans == 1)
assert(not layoutHook, "factory layout installed an unnecessary native layout hook")
assert(bar.barTexture.texture == "native-health")
assert(cast.statusTexture.texture == "native-cast" and not cast.created and cast.Background:GetAlpha() == .8,
    "nameplate skin changed the native cast fill/background")
assert(module.visuals[bar].borderColor == "111418"
    and module.visuals[bar].fill.color[1] == 0xbe / 255
    and module.visuals[bar].fill.allPoints == bar.barTexture and bar.barColor[1] == 0.5,
    "melee overlay must follow Blizzard's fill without recoloring its StatusBar")
assert(module.visuals[bar].fill.layer == "ARTWORK" and module.visuals[bar].fill.sublevel == 3,
    "role tint must remain above a native StatusBar texture reapplied after setup")
do
    local nameWrites, castWrites = name.shadowColorWrites, cast.Text.shadowColorWrites
    events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
    assert(name.shadowColorWrites == nameWrites and cast.Text.shadowColorWrites == castWrites,
        "unchanged unit metadata repainted native font shadows")
end
module.config.enemyColorsOutside = false
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
assert(not module.visuals[bar].fill:IsShown(), "outdoor color scope did not disable its overlay")
module.config.enemyColorsOutside = true
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
assert(module.visuals[bar].fill:IsShown(), "outdoor color scope did not restore its overlay")
-- Jundies/Platynator detects mana capability, not just the currently displayed
-- power. Exercise the real two-result API as well as the capability fallback.
do
    local nativePowerType, nativeHasPower = UnitPowerType, UnitHasPowerType
    local power, token, powerReads = nil, nil, 0
    UnitPowerType = function() powerReads = powerReads + 1; return power, token end
    local function Check(mana, currentPower, currentToken, expected)
        hasMana, power, token = mana, currentPower, currentToken
        local before = powerReads
        events.UNIT_DISPLAYPOWER(module, "UNIT_DISPLAYPOWER", "nameplate1")
        assert(module.roles[bar] == expected, "mana-capable caster or public power result lost its role")
        if type(mana) == "boolean" then assert(powerReads == before, "public mana capability performed a redundant power query") end
        local fill = module.visuals[bar].fill
        if expected then
            local r, g, b = S.RGB(module.config["enemy" .. expected .. "Color"])
            assert(fill:IsShown() and fill.color[1] == r and fill.color[2] == g and fill.color[3] == b,
                "role classification did not recolor the full health fill")
        else assert(not fill:IsShown(), "unknown role retained a previous NPC tint") end
    end
    Check(true, 3, "ENERGY", "Caster")
    Check(false, 0, "MANA", "Melee")
    classification, instanceType = "elite", "party"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    Check(true, 3, "ENERGY", "Caster")
    Check(false, 0, "MANA", "Melee")
    Check("secret", "secret", "MANA", "Caster")
    Check("secret", 0, "secret", "Caster")
    Check("secret", 3, "secret", "Melee")
    Check("secret", "secret", "secret", "Melee")
    UnitHasPowerType = nil
    Check(nil, nil, "MANA", "Caster")
    Check(nil, nil, nil, "Melee")
    UnitPowerType, UnitHasPowerType, hasMana = nativePowerType, nativeHasPower, false
    classification, instanceType = "normal", "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(scans == 1, "role refresh scanned all plates")
end
do
    local previousPvp = C_PvP
    C_PvP = { GetZonePVPInfo = function() return "combat" end }
    classification, instanceType, hasMana = "normal", "party", true
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(module.roles[bar] == "Caster" and module.visuals[bar].fill:IsShown(),
        "an outdoor PvP zone flag suppressed caster color inside a party instance")
    classification = nil
    events.UNIT_CLASSIFICATION_CHANGED(module, "UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    assert(module.roles[bar] == "Caster", "public mana hint lost caster color when classification was unavailable")
    instanceType, hasMana, classification = "none", false, "normal"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(module.roles[bar] == nil, "outdoor PvP zone inherited dungeon role colors")
    C_PvP = previousPvp
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
end
do
    local nativeTimer, nativeClassification = C_Timer, UnitClassification
    local timerCount, classificationReads, queued = 0, 0, {}
    C_Timer = { NewTimer = function(delay, callback)
        assert(delay == 1)
        timerCount = timerCount + 1
        local timer = { callback = callback }
        function timer:Cancel() self.cancelled = true end
        queued[#queued + 1] = timer
        return timer
    end }
    UnitClassification = function(unit)
        classificationReads = classificationReads + 1
        return nativeClassification(unit)
    end
    local active = module.activeUnits.nameplate1
    module.activeUnits.nameplate1 = nil
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 0, "quest update scheduled work without visible plates")
    module.activeUnits.nameplate1 = active
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 1 and classificationReads == 0,
        "quest updates performed repeated immediate plate classifications")
    queued[1].callback()
    assert(classificationReads == 1, "coalesced quest update missed the active plate")
    instanceType = "party"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    classificationReads = 0
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 1 and classificationReads == 0,
        "quest update scheduled work inside a dungeon")
    instanceType = "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 2 and not queued[2].cancelled)
    instanceType = "party"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(queued[2].cancelled and module.questTimer == nil,
        "context change left stale quest work scheduled")
    instanceType = "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    C_Timer, UnitClassification = nativeTimer, nativeClassification
end
assert(name.fontSize == 12 and name.points[1][1] == "CENTER"
    and cast.points[1][1] == "CENTER" and aura.points[1][1] == "CENTER",
    "native anchors changed")
assert(cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1"
    and cvars.nameplateUseClassColorForFriendlyPlayerUnitNames == "1")
assert(cvars.nameplateStyle == "0" and cvars.nameplateSize == "2"
    and cvars.nameplateForceShowUnitName == "1"
    and cvars.nameplateSimplifiedTypes == string.char(1, 76)
    and cvars.nameplateInfoDisplay == string.char(1, 71),
    "Jundies defaults did not request Blizzard's full enemy text and medium inside-bar layout")
assert(cvars.nameplateCastBarDisplay == string.char(1, 121),
    "Blizzard castbar display bits were not enabled")
assert(cvars.nameplateShowCastBars == "1",
    "Blizzard's native nameplate castbar was never enabled")
assert(restored.ShowClassColorInNameplate and restored.nameplateShowClassColor
    and restored.nameplateShowAllPersonalAuras)

events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(scans == 1, "combat exit scanned plates without deferred work")
combat = true
module:Refresh()
assert(not module.needsRefresh and scans == 2, "safe font/texture styling should work in combat")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(not module.needsRefresh and scans == 2, "combat exit should not redo cosmetic work")

events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(scans == 2 and name.points[1][1] == "CENTER", "event performed a scan or changed native anchors")
hasMana = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[2] == 0xbf / 255, "caster health fill missing")
classification = "rareelite"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 0x93 / 255, "rare health fill missing")
local elite = module.visuals[bar].elite
assert(elite:IsShown() and elite.atlas == "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"
    and elite.text == nil and elite.points[1][3] == "LEFT"
    and elite.points[1][4] == -13 and elite.width == 14,
    "elite marker must use a texture outside the name, never a font glyph inside the bar")
module.config.enemyEliteMarker = false
module:Refresh()
assert(not elite:IsShown(), "disabled elite marker retained a fragment over the name")
module.config.enemyEliteMarker = true
module.config.enemyEliteMarkerSize = 20
module.config.enemyEliteOffsetX = -20
module:Refresh()
assert(elite:IsShown() and elite.width == 20 and elite.points[1][4] == -20,
    "elite marker size/offset did not refresh after changing the setting")
isBoss = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1, "boss health fill missing")
isBoss, classification, instanceType, unitLevel = false, "elite", "party", 91
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 0x93 / 255, "lieutenant health fill missing")
unitLevel = 92
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1, "level-based boss health fill missing")
unitLevel, instanceType = 90, "none"
questUnit = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1 and module.visuals[bar].fill.color[2] == 0x7e / 255,
    "quest objective health color missing")
assert(module.visuals[bar].quest:IsShown() and module.visuals[bar].quest.atlas == "QuestNormal"
    and module.visuals[bar].quest.text == nil, "quest marker must use a texture, not a font glyph")
questUnit, tappedUnit = false, true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 0x6e / 255, "tapped health color missing")
tappedUnit, focusUnit = false, "nameplate1"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1 and module.visuals[bar].fill.color[2] == 0,
    "focus health color missing")
focusUnit, targetUnit = nil, "nameplate1"
events.PLAYER_FOCUS_CHANGED(module, "PLAYER_FOCUS_CHANGED")
local targetFontReads = name.fontReads
events.PLAYER_TARGET_CHANGED(module, "PLAYER_TARGET_CHANGED")
assert(name.fontReads == targetFontReads, "target change repainted nameplate typography")
local marker = module.visuals[bar].targetHost._msufBossTargetIndicator
assert(marker:IsShown() and marker.mirror:IsShown() and marker.width == 16
    and #marker.lines == 4 and marker._style == "DOUBLE_ARROW",
    "target arrows missing")
module.config.enemyTargetOffsetX = 9
module.config.enemyTargetOffsetY = -4
module:Refresh()
assert(marker.points[1][4] == -10
    and marker.points[1][5] == -4,
    "dragged target marker offsets did not reach the live skin")
targetUnit = nil
targetFontReads = name.fontReads
events.PLAYER_TARGET_CHANGED(module, "PLAYER_TARGET_CHANGED")
assert(not module.visuals[bar].targetHost:IsShown() and name.fontReads == targetFontReads,
    "target change repainted unrelated visuals or left arrows visible")
module.config.enemyTankMode = true
isTank, grouped, onThreatList = true, true, true
private.Roles.RefreshContext()
threatStatus = 3
local threatFontReads = name.fontReads
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1 and module.visuals[bar].fill.color[2] == 0x4d / 255,
    "tank lost-threat color missing")
assert(name.fontReads == threatFontReads, "threat color update repainted nameplate typography")
threatStatus = 2
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.visuals[bar].fill.color[2] == 0xbd / 255, "tank warning color missing")
module.config.enemyTankMode, threatStatus = false, nil
instanceType = "none"
isBoss, classification, hasMana, questUnit, tappedUnit = false, "secret", "secret", "secret", "secret"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].borderColor == "111418" and not module.visuals[bar].fill:IsShown(),
    "secret role must leave Blizzard's health fill and the plain border")
uf.isFriend = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(name.fontSize == 14 and bar.barTexture.texture == "native-health"
    and cast.statusTexture.texture == "native-cast", "friend style not applied or native texture changed")
uf.isFriend = "secret"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(not module.visuals[bar].back:IsShown(), "unknown faction retained a stale visual")
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not module.visuals[bar].fill:IsShown() and module.activeUnits.nameplate1 == nil,
    "removed plate retained a role overlay")
uf.isFriend = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.activeUnits.nameplate1 == uf)
module.config.auraClickthrough = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(auraButton.mouseClickEnabled == false, "aura clickthrough did not reach pooled button")
local auraWrites = auraButton.mouseWrites
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(auraButton.mouseWrites == auraWrites, "unchanged aura clickthrough repeated a protected setter")
module.config.auraClickthrough = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(auraButton.mouseClickEnabled == true, "aura clickthrough did not restore native clicks")
module.config.enemyRaidIcon = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(raidIcon:GetAlpha() == 0, "native raid icon was not hidden on an existing enemy plate")
module.active = false
module:Disable()
assert(raidIcon:GetAlpha() == 0.8, "disabling the module did not restore Blizzard's raid icon")
module.config.enemyRaidIcon = true
assert(scans == 5 and bar.barTexture.texture == "native-health"
    and not module.visuals[bar].back:IsShown(), "native frame was not restored")
assert(not module.visuals[bar].fill:IsShown() and name.font == "native-font" and name.fontSize == 10,
    "Jundies overlay or font remained after disabling")
assert(cast.statusTexture.texture == "native-cast" and cast.Background:GetAlpha() == .8,
    "disabling nameplates changed native cast rendering")
assert(events.NAME_PLATE_UNIT_ADDED and events.NAME_PLATE_UNIT_REMOVED and events.PLAYER_REGEN_ENABLED)
module.active = true
module.config.enemyRarityIcon = 3
module.config.enemyRaidIcon = false
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 67)
    and raidIcon:GetAlpha() == 0, "enemy icon switches did not hide native icons")
module.config.enemyRarityIcon = 2
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 71), "rarity icon switch lost health text flags")
module.config.enemyRarityIcon = 1
module.config.enemyRaidIcon = true
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 71) and raidIcon:GetAlpha() == 0.8,
    "native icon switches did not restore their prior state")
module.config.enemyTextMode, module.config.enemyRarityIcon = 1, 3
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1),
    "hiding the rarity icon while keeping Blizzard health text did not restore the original text flags")
module.config.enemyTextMode, module.config.enemyRarityIcon = 4, 1
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 71),
    "reverting the rarity switch did not restore the native icon with Jundies health text")
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 22, -6
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 0, -10
module:Refresh()
assert(layoutHook and Placed(name, 1, 4) == 22 and Placed(name, 1, 5) == -6
    and Placed(cast, 1, 5) == -10, "preview layout offsets did not reach Blizzard's regions")
layoutHook(uf)
assert(Placed(name, 1, 4) == 22, "layout post-hook accumulated an offset")
-- Emulate Blizzard rebuilding its anchors; the addon only receives the hook.
name:ClearAllPoints()
name:SetPoint("CENTER", nativeAnchor, "CENTER", 4, 2)
layoutHook(uf)
assert(Placed(name, 1, 4) == 26 and Placed(name, 1, 5) == -4, "native reanchor lost the custom offset")
combat = true
module.config.enemyNameOffsetX = 40
module:Refresh()
assert(Placed(name, 1, 4) == 26, "layout moved a native region in combat")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(Placed(name, 1, 4) == 44, "deferred layout change did not apply after combat")
-- A combat-time native layout can reset displacement before the deferred pass.
combat = true
name.offsetX, name.offsetY = 0, 0
layoutHook(uf)
assert(name.offsetX == 0, "layout post-hook wrote during combat")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(Placed(name, 1, 4) == 44, "native combat reset bypassed the offset cache on resume")
local layoutWrites = name.offsetWrites
events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
assert(name.offsetWrites == layoutWrites, "unit data events rewrote unchanged geometry")
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 0, 0
module.config.enemyCastOffsetY = 0
module:Refresh()
assert(Placed(name, 1, 4) == 4 and Placed(name, 1, 5) == 2 and Placed(cast, 1, 5) == 0,
    "reset did not restore the latest Blizzard anchors")
module.active = false
module:Disable()
-- New plates, cast skins and fonts must work on first appearance IN combat.
module.active, combat = true, true
classification, hasMana, isBoss, questUnit, tappedUnit, threatStatus = "normal", false, false, false, false, nil
isTank, grouped, onThreatList = false, false, false
module.config.enemyTankMode = false
module.visuals[bar] = nil
module:Refresh()
assert(module.visuals[bar].fill:IsShown(),
    "first combat appearance deferred the health skin until combat ended")
assert(name.fontSize == 12 and cvars.nameplateShowCastBars == "1")
combat = false

-- Focus disabled falls back to base type; tapped is independent of quest colors.
focusUnit = "nameplate1"
module.config.enemyFocusEnabled = false
module:Refresh()
assert(module.roles[bar] == "Melee", "disabled focus rule swallowed the base role")
focusUnit, tappedUnit = nil, true
module.config.enemyQuestColors = false
events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
assert(module.roles[bar] == "Tapped", "tapped color incorrectly required quest colors")
tappedUnit = false

-- EQoL uses lead threat for tanks: zero is safe, not lost. Warnings also work for damage/healers.
isTank, grouped, onThreatList = true, true, true
uf.optionTable = { usePlayerForAggroHighlightThreat = true }
module.config.enemyTankMode, module.config.enemyTankModeColor = true, "26d9ff"
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
threatStatus = 0
events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "nameplate1")
assert(module.roles[bar] == "TankMode", "safe tank aggro did not use the separate tank color")
assert(threatCalls[#threatCalls][1] == "lead" and threatCalls[#threatCalls][2] == "player"
    and threatCalls[#threatCalls][3] == "nameplate1", "tank threat did not follow Blizzard's nameplate API")
onThreatList = false
events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "nameplate1")
assert(module.roles[bar] == "Melee", "unengaged mob was colored as safe tank aggro")
isTank, threatStatus = false, 3
events.PLAYER_ROLES_ASSIGNED(module, "PLAYER_ROLES_ASSIGNED")
assert(module.roles[bar] == "ThreatLost", "damage/healer taking aggro was not highlighted")
assert(threatCalls[#threatCalls][1] == "situation" and threatCalls[#threatCalls][2] == "player"
    and threatCalls[#threatCalls][3] == "nameplate1", "damage threat did not follow Blizzard's nameplate API")
module.config.enemyThreatLostEnabled = false
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.roles[bar] == nil, "disabled threat override concealed Blizzard's active threat color")
threatStatus = "secret"
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.roles[bar] == "Melee" and module.visuals[bar].fill:IsShown()
    and module.visuals[bar].fill.color[1] == 0xbe / 255,
    "secret threat suppressed the ordinary NPC color")
uf.optionTable = nil
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(threatCalls[#threatCalls][1] == "situation" and threatCalls[#threatCalls][2] == "nameplate1"
    and threatCalls[#threatCalls][3] == nil,
    "default threat mode used the player-pair API without Blizzard's nameplate option")
threatStatus, grouped, instanceType = nil, false, "arena"
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
assert(module.roles[bar] == nil, "PvP inherited NPC role colors")
instanceType = "none"
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
UnitPlayerControlled = function() return true end
events.UNIT_FACTION(module, "UNIT_FACTION", "nameplate1")
assert(module.roles[bar] == nil, "player-controlled pet received an NPC type color")
UnitPlayerControlled = function() return "secret" end
events.UNIT_FACTION(module, "UNIT_FACTION", "nameplate1")
assert(module.roles[bar] == "Melee", "secret player-control hint suppressed an NPC role")
UnitPlayerControlled = nil

-- Role tint is an owned overlay; no user texture may replace Blizzard's fill.
module.config.enemyRoleColors = false
module:Refresh()
assert(bar.barTexture.texture == "native-health" and not module.visuals[bar].fill:IsShown())
focusUnit = "nameplate1"
events.PLAYER_FOCUS_CHANGED(module, "PLAYER_FOCUS_CHANGED")
assert(bar.barTexture.texture == "native-health", "focus changed Blizzard's native texture")
module.config.enemyRoleColors = true
module.config.enemyFocusEnabled = true
module:Refresh()
assert(module.roles[bar] == "Focus" and module.visuals[bar].fill:IsShown(),
    "focus role overlay was not restored")
module.config.enemyRoleColors = false
module.config.enemyFocusEnabled = false

bar.barTexture:SetAtlas("new-native-atlas")
layoutHook(uf)
assert(bar.barTexture.atlas == "new-native-atlas", "layout altered Blizzard's native texture")
focusUnit = nil
events.PLAYER_FOCUS_CHANGED(module, "PLAYER_FOCUS_CHANGED")
assert(bar.barTexture.atlas == "new-native-atlas", "former focus altered Blizzard's native texture")
module:Refresh()
assert(bar.barTexture.atlas == "new-native-atlas", "texture reset lost the latest native atlas")

-- Friendly target marker is attached to UnitFrame, also usable with a hidden health bar.
uf.isFriend, targetUnit = true, "nameplate1"
module.config.enemyTargetHideFriendly = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].targetHost:IsShown(), "friendly target marker option does nothing")
module.config.enemyTargetHideFriendly = true
module:Refresh()
assert(not module.visuals[bar].targetHost:IsShown())
uf.isFriend, targetUnit = false, nil

-- Font override off keeps Blizzard's locale face while SLUG/size/shadow still apply.
module.config.enemyCustomFont, module.config.enemyTextOutline, module.config.enemyTextShadow = false, 4, true
name:SetFont("locale-font", 10, "")
module:Refresh()
assert(name.font == "locale-font" and name.flags == "OUTLINE,SLUG" and name.shadow[4] == 1)
name:SetFont("updated-native-font", 14, "")
fontHook(uf)
assert(name.font == "updated-native-font" and name.fontSize == 12 and name.flags == "OUTLINE,SLUG")
name:SetShadowColor(0, 0, 0, 0.6)
fontHook(uf)
assert(name.shadow[4] == 1, "native frame-options reset left the cached shadow stale")
module.config.enemyTextEnabled = false
module:Refresh()
assert(name.font == "updated-native-font" and name.fontSize == 14 and name.flags == ""
    and name.shadow[4] == 0.6, "disabling typography did not restore Blizzard's latest font/shadow")

-- Marker anchors and size are functional, not just catalog entries.
module.config.enemyEliteMarkerAnchor, module.config.enemyEliteMarkerSize = 4, 48
classification, unitLevel = "worldboss", -1
module:Refresh()
assert(module.visuals[bar].elite.points[1][3] == "TOPRIGHT" and module.visuals[bar].elite.width == 48
    and module.visuals[bar].elite.atlas == "worldquest-icon-boss")

-- Quest cache distinguishes completed, party and unknown objectives without polling.
local tooltipReads = 0
Enum = { TooltipDataLineType = { QuestTitle = 1, QuestPlayer = 2, QuestObjective = 3 } }
UnitName = function() return "Player" end
local lines = { { type = 1 }, { type = 3, leftText = "5/5" } }
C_TooltipInfo = { GetUnit = function() tooltipReads = tooltipReads + 1; return { lines = lines } end }
questUnit = true
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == false and private.Roles.Quest("nameplate1") == false and tooltipReads == 1)
lines = { { type = 1 }, { type = 2, leftText = "Party Member" }, { type = 3, leftText = "0/5" } }
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == false, "party quest was treated as our objective")
lines = { { type = 1 }, { type = 3, leftText = "4/5" } }
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == true)
lines = { { type = 1 }, { type = 3, leftText = "secret" } }
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == nil and private.Roles.quests.nameplate1 == nil,
    "inaccessible quest text was cached as a completed objective")
local beforeScans = scans
events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "party1")
assert(scans == beforeScans and not events.UNIT_HEALTH, "unit metadata event triggered a global scan or health polling")
module:Disable()
assert(not module.visuals[bar].elite:IsShown())
-- Cast start/reuse is entirely native, including a plate created without a fill.
module.active = true
uf.isPlayer, uf.isFriend = false, false
cast.statusTexture = nil
module:Refresh()
assert(cast.statusTexture == nil and not cast.created)
combat = true
cast.statusTexture = Region()
cast.statusTexture:SetTexture("first-native-cast")
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(cast.statusTexture.texture == "first-native-cast")
cast.statusTexture = Region()
cast.statusTexture:SetTexture("next-native-cast")
events.UNIT_DISPLAYPOWER(module, "UNIT_DISPLAYPOWER", "nameplate1")
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(cast.statusTexture.texture == "next-native-cast" and not cast.created,
    "pooled cast was modified by the nameplate skin")
combat = false

-- Group name filtering is roster/event driven and restores the original alpha.
uf.isFriend, uf.isPlayer, grouped = true, true, false
name:SetAlpha(.7)
module.config.friendlyGroupOnly = true
module:Refresh()
assert(name:GetAlpha() == 0 and cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1")
local groupScans = scans
grouped = true
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == .7 and scans == groupScans)
grouped = false
UnitInRaid = function() return 2 end
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == .7, "raid member name hidden")
UnitInRaid = function() return "secret" end
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == .7, "secret membership was used for filtering")
UnitInRaid = function() return nil end
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == 0)
module:Disable()
assert(name:GetAlpha() == .7, "group filter not restored on disable")

-- The native classification texture is independently movable and reversible.
module.active, uf.isPlayer, uf.isFriend = true, false, false
module.config.enemyHealthOffsetX, module.config.enemyHealthOffsetY = 13, -4
module:Refresh()
assert(healthContainer.offsetX == 13 and healthContainer.offsetY == -4,
    "health drag did not move Blizzard's health container")
layoutHook(uf)
assert(healthContainer.offsetX == 13 and healthContainer.offsetY == -4,
    "Blizzard anchor rebuild lost the health position")
module.config.enemyHealthOffsetX, module.config.enemyHealthOffsetY = 0, 0
module:Refresh()
assert(healthContainer.offsetX == 0 and healthContainer.offsetY == 0,
    "reset did not restore Blizzard's health container")
local nativeElite = Region()
uf.ClassificationFrame = { classificationIndicator = nativeElite }
module.config.enemyClassificationOffsetX, module.config.enemyClassificationOffsetY = 17, -5
module:Refresh()
assert(Placed(nativeElite, 1, 4) == 17 and Placed(nativeElite, 1, 5) == -5)
layoutHook(uf)
assert(Placed(nativeElite, 1, 4) == 17)
module.config.enemyClassificationOffsetX, module.config.enemyClassificationOffsetY = 0, 0
module:Refresh()
assert(Placed(nativeElite, 1, 4) == 0 and Placed(nativeElite, 1, 5) == 0)

-- Modern Blizzard anchors the bar and spell name to the icon, while
-- Classic anchors the icon to the bar. Both must move as one cast group,
-- and an icon-only offset must not drag the progress bar along with it.
cast.Icon, cast.BorderShield, cast.CastTargetNameText, cast.Border = Region(), Region(), Region(), Region()
local function NativeCastAnchors(classic)
    NamePlateSetupOptions.useClassicCastBar = classic
    cast:ClearAllPoints(); cast.Icon:ClearAllPoints(); cast.Text:ClearAllPoints()
    cast.BorderShield:ClearAllPoints(); cast.CastTargetNameText:ClearAllPoints(); cast.Border:ClearAllPoints()
    cast.Border:SetPoint("CENTER", nativeAnchor, "CENTER", 0, 0)
    if classic then
        cast:SetPoint("TOPLEFT", nativeAnchor, "TOPLEFT", 0, 0)
        cast.Icon:SetPoint("LEFT", cast.Border, "LEFT", 0, 0)
        cast.Text:SetPoint("LEFT", cast, "LEFT", 2, 0)
        cast.BorderShield:SetPoint("RIGHT", cast, "RIGHT", 0, 0)
        cast.CastTargetNameText:SetPoint("TOPRIGHT", cast, "BOTTOMRIGHT", 0, 0)
    else
        cast:SetPoint("BOTTOM", cast.Icon, "TOP", 0, 0)
        cast:SetPoint("LEFT", nativeAnchor, "BOTTOMLEFT", 0, 0)
        cast:SetPoint("RIGHT", nativeAnchor, "BOTTOMRIGHT", 0, 0)
        cast.Icon:SetPoint("BOTTOMLEFT", nativeAnchor, "BOTTOMLEFT", 0, 0)
        cast.Text:SetPoint("LEFT", cast.Icon, "RIGHT", 2, 0)
        cast.BorderShield:SetPoint("RIGHT", cast.Icon, "RIGHT", 0, 0)
        cast.CastTargetNameText:SetPoint("LEFT", cast.Text, "RIGHT", 2, 0)
        cast.CastTargetNameText:SetPoint("RIGHT", cast, "RIGHT", -4, 0)
    end
end
NativeCastAnchors(false)
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 20, -10
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 9, -4
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 5, 2
module:Refresh()
assert(Placed(cast, 1, 4) == -9 and Placed(cast, 1, 5) == 4
    and Placed(cast, 2, 4) == 20 and Placed(cast, 2, 5) == -10)
assert(Placed(cast.Icon, 1, 4) == 29 and Placed(cast.Icon, 1, 5) == -14)
assert(Placed(cast.Text, 1, 4) == -2 and Placed(cast.Text, 1, 5) == 6)
assert(Placed(cast.CastTargetNameText, 1, 4) == -3 and Placed(cast.CastTargetNameText, 1, 5) == -2)
layoutHook(uf)
assert(Placed(cast.Icon, 1, 4) == 29, "cast group drifted on repeated layout")
NativeCastAnchors(true)
layoutHook(uf)
assert(Placed(cast, 1, 4) == 20 and Placed(cast, 1, 5) == -10
    and Placed(cast.Icon, 1, 4) == 9 and Placed(cast.Icon, 1, 5) == -4,
    "Classic cast anchor direction compounded the drag offset")
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 0, 0
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 0, 0
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 0, 0
module:Refresh()
assert(Placed(cast, 1, 4) == 0 and Placed(cast.Icon, 1, 4) == 0 and Placed(cast.Text, 1, 4) == 2)

-- Modern with spell name inside uses the opposite Icon -> bar dependency.
NamePlateSetupOptions.useClassicCastBar, NamePlateSetupOptions.spellNameInsideCastBar = false, true
cast:ClearAllPoints(); cast.Icon:ClearAllPoints(); cast.Text:ClearAllPoints()
cast.CastTargetNameText:ClearAllPoints()
cast:SetPoint("TOPLEFT", nativeAnchor, "TOPLEFT", 0, 0)
cast:SetPoint("BOTTOMRIGHT", nativeAnchor, "BOTTOMRIGHT", 0, 0)
cast.Icon:SetPoint("LEFT", cast, "LEFT", 0, 0)
cast.Text:SetPoint("LEFT", cast.Icon, "RIGHT", 2, 0)
cast.CastTargetNameText:SetPoint("LEFT", cast.Text, "RIGHT", 2, 0)
cast.CastTargetNameText:SetPoint("RIGHT", cast, "RIGHT", -4, 0)
layoutHook(uf)
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 20, -10
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 9, -4
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 5, 2
module:Refresh()
assert(#cast.points == 2 and cast.offsetX == 20 and cast.offsetY == -10)
assert(cast.Icon.offsetX == 9 and cast.Icon.offsetY == -4)
assert(cast.Text.offsetX == -4 and cast.Text.offsetY == 6)
assert(Placed(cast.CastTargetNameText, 1, 4) == -3 and Placed(cast.CastTargetNameText, 2, 4) == -4,
    "moving the spell name dragged/stretched the spell target text")
module:Disable()
assert(cast.offsetX == 0 and cast.Icon.offsetX == 0 and cast.Text.offsetX == 0
    and cast.CastTargetNameText.points[1][4] == 2, "disable did not restore cast links/displacement")
module.active = true
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 0, 0
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 0, 0
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 0, 0

-- The name, raid icon and classification must have independent offsets,
-- including a recycled enemy plate becoming a friendly names-only plate.
uf.RaidTargetFrame = Region()
uf.showOnlyName, uf.isFriend = true, true
module.config.friendlyNameOffsetX, module.config.friendlyNameOffsetY = 16, 3
module.config.friendlyRaidIconOffsetX, module.config.friendlyRaidIconOffsetY = 4, -6
module.config.friendlyClassificationOffsetX, module.config.friendlyClassificationOffsetY = 7, 2
module:Refresh()
assert(name.offsetX == 16 and name.offsetY == 3)
assert(uf.RaidTargetFrame.offsetX == -12 and uf.RaidTargetFrame.offsetY == -9)
assert(nativeElite.offsetX == 3 and nativeElite.offsetY == 8)
uf.isFriend = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(name.offsetX == 0 and uf.RaidTargetFrame.offsetX == 0 and nativeElite.offsetX == 0,
    "recycled plate retained the friendly drag layout")
uf.showOnlyName = false

-- Moving health text must not pull the name's right edge; moving an above-bar
-- name must not pull the debuff list's bottom anchor along with it.
NamePlateSetupOptions.unitNameAnchorStyle = 2
NamePlateConstants = { DEBUFF_PADDING_CVAR = "nameplateDebuffPadding" }
CVarCallbackRegistry = { GetCVarNumberOrDefault = function(_, key)
    assert(key == "nameplateDebuffPadding"); return 6
end }
bar.LeftText = Region()
aura.DebuffListFrame = Region()
name:ClearAllPoints()
name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 4, 2)
name:SetPoint("BOTTOMRIGHT", bar.Text, "BOTTOMLEFT", -2, 0)
aura.DebuffListFrame:ClearAllPoints()
aura.DebuffListFrame:SetPoint("LEFT", nativeAnchor, "LEFT", 0, 0)
aura.DebuffListFrame:SetPoint("BOTTOM", name, "TOP", 0, 6)
layoutHook(uf)
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 15, -3
module.config.enemyHealthTextOffsetX, module.config.enemyHealthTextOffsetY = -12, 5
module.config.enemyAurasOffsetX, module.config.enemyAurasOffsetY = 2, 8
module:Refresh()
assert(Placed(name, 2, 4) == 25 and Placed(name, 2, 5) == -8)
assert(bar.LeftText.offsetX == -12 and bar.LeftText.offsetY == 5)
assert(Placed(aura.DebuffListFrame, 1, 4) == 2 and Placed(aura.DebuffListFrame, 2, 4) == -13
    and Placed(aura.DebuffListFrame, 2, 5) == 17)
module:Disable()
assert(name.points[2][4] == -2 and name.points[2][5] == 0 and name.offsetX == 0
    and aura.DebuffListFrame.points[2][4] == 0 and aura.DebuffListFrame.points[2][5] == 6)
module.active = true
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 0, 0
module.config.enemyHealthTextOffsetX, module.config.enemyHealthTextOffsetY = 0, 0
module.config.enemyAurasOffsetX, module.config.enemyAurasOffsetY = 0, 0

-- Forever uses RIGHT (not BOTTOMRIGHT) above the bar. A shown level frame
-- owns that dynamic endpoint; it must never be replaced with a guessed link.
NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = "LEFT"
uf.PlayerLevelDiffFrame = Region()
name:ClearAllPoints()
name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 0, 2)
name:SetPoint("RIGHT", uf.PlayerLevelDiffFrame, "RIGHT", 0, 0)
module.config.enemyHealthTextOffsetX = 10
module:Refresh()
assert(#name.points == 2 and name.points[2][2] == uf.PlayerLevelDiffFrame)
uf.PlayerLevelDiffFrame:Hide()
name:ClearAllPoints()
name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 0, 2)
name:SetPoint("RIGHT", bar.Text, "LEFT", -2, 0)
layoutHook(uf)
assert(#name.points == 2 and name.points[2][1] == "RIGHT" and name.points[2][4] == -12)
module:Disable()
assert(name.points[2][1] == "RIGHT" and name.points[2][4] == -2)
NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = nil
module.config.enemyHealthTextOffsetX = 0
module.active = true

-- Shape/layout/anchor/direction use the actual MSUF boss renderer.
targetUnit = "nameplate1"
module.config.enemyTargetStyle, module.config.enemyTargetLayout = 11, 3
module:Refresh()
marker = module.visuals[bar].targetHost._msufBossTargetIndicator
assert(marker._style == "TRIPLE_ARROW" and #marker.lines == 6 and marker._layout == "BOTH_OUT")
module.config.enemyTargetStyle, module.config.enemyTargetLayout = 12, 1
module.config.enemyTargetAnchor, module.config.enemyTargetDirection = 2, 3
module:Refresh()
assert(marker._style == "DIAMOND" and marker._anchor == "TOP" and marker._direction == "UP"
    and not marker.mirror:IsShown() and not marker.lines[5]:IsShown())
module.config.enemyTargetStyle = 2
module:Refresh()
assert(marker._suiteAtlas:IsShown() and not marker.lines[1]:IsShown())
module.config.enemyTargetStyle = 12
module:Refresh()
assert(not marker._suiteAtlas:IsShown() and marker.lines[1]:IsShown() and not marker.lines[5]:IsShown())
module.config.enemyTargetStyle = 9
module:Refresh()
assert(not marker:IsShown() and module.visuals[bar].targetBorder.edges[1]:IsShown())
module:Disable()

do
    module.active, uf.isFriend, uf.isPlayer = true, false, false
    module.config.look = 3
    module.config.enemyRoleColors, module.config.enemyQuestColors = true, false
    classification, unitLevel, targetUnit, focusUnit = "normal", 90, nil, nil
    local nativeTexture = bar.barTexture.texture
    module:Refresh()
    assert(bar.barTexture.texture == nativeTexture and module.visuals[bar].fill:IsShown(),
        "role skin replaced Blizzard's health texture")
    uf.isFriend = true
end

-- Friendly NPC markers and cast text have their own live settings and restore.
do
    local c = module.config
    c.friendlyEliteMarker, c.friendlyQuestMarker, questUnit = true, true, true
    c.friendlyEliteOffsetX, c.friendlyEliteOffsetY, c.friendlyEliteMarkerSize = 23, 8, 19
    c.friendlyQuestOffsetX, c.friendlyQuestOffsetY = -30, 12
    c.friendlyCastTextEnabled, c.friendlyCastCustomFont, c.friendlyCastTextShadow = true, true, true
    c.friendlyCastFont, c.friendlyCastSize, c.friendlyCastOutline = "friendly-font", 18, 5
    classification, instanceType, focusUnit = "rareelite", "none", nil
    C_TooltipInfo, C_Secrets = nil, nil
    cast.Text:SetFont("friendly-native", 10, "")
    cast.CastTargetNameText:SetFont("friendly-target-native", 9, "")
    private.Roles.ClearQuest()
    module:Refresh()
    local visual = module.visuals[bar]
    assert(visual.elite:IsShown() and visual.elite.points[1][4] == 23 and visual.elite.width == 19
        and visual.quest:IsShown() and visual.quest.points[1][4] == -30, "friendly marker positions were not applied")
    assert(cast.Text.font == "friendly-font" and cast.Text.fontSize == 18 and cast.Text.flags == "THICKOUTLINE,SLUG"
        and cast.Text.shadow[4] == 1 and cast.CastTargetNameText.font == "friendly-font")
    c.friendlyCastTextEnabled = false
    c.friendlyEliteMarker, c.friendlyQuestMarker = false, false
    module:Refresh()
    assert(cast.Text.font == "friendly-native" and cast.CastTargetNameText.font == "friendly-target-native"
        and not visual.elite:IsShown() and not visual.quest:IsShown(), "friendly customizations were not reversible")
    c.friendlyNPCs, c.playerGuildNames, c.playerTitles = 3, 2, 3
    module:Refresh()
    assert(cvars.nameplateShowFriendlyNpcs == "0" and cvars.UnitNamePlayerGuild == "1" and cvars.UnitNamePlayerPVPTitle == "0")
    c.friendlyNPCs, c.playerGuildNames, c.playerTitles = 1, 1, 1
    module:Refresh()
    assert(restored.nameplateShowFriendlyNpcs and restored.UnitNamePlayerGuild and restored.UnitNamePlayerPVPTitle)
    c.enemyTargetStyle, c.enemyTargetMarker = 15, true
    uf.isFriend, targetUnit = false, "nameplate1"
    module:Refresh()
    assert(NS.NameplateStyle.TargetConfig(c).atlas[1] == "pvptalents-selectedarrow"
        and visual.targetHost._msufBossTargetIndicator._suiteAtlas.atlas == "pvptalents-selectedarrow")
end
module:Disable()
local disabledFontReads = name.fontReads
fontHook(uf)
assert(name.fontReads == disabledFontReads, "disabled nameplate hook still inspected plate fonts")
print("Suite nameplates: native lifecycle, cast customization, masks, friendly features, layout and restoration passed")

-- Keybinding is a manual Suite setting change, with no work in combat/off.
do
    NS.Text = function(value) return value end
    NS.ActionBarTitles = { [9] = "Suite bar 9", [10] = "Suite bar 10" }
    local writes = 0
    S.Config = function(id) assert(id == "nameplates"); return module.config end
    S.Set = function(id, key, value)
        assert(id == "nameplates" and key == "friendlyNPCs")
        writes = writes + 1
        module.config[key] = value
        return true
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Bindings.lua"))("MSUF_Suite", NS)
    module.config.enabled = true
    liveCVars.nameplateShowFriendlyNpcs = "0"
    assert(NS.ToggleFriendlyNPCNameplates() and module.config.friendlyNPCs == 2)
    liveCVars.nameplateShowFriendlyNpcs = "1"
    assert(NS.ToggleFriendlyNPCNameplates() and module.config.friendlyNPCs == 3)
    combat = true
    assert(not NS.ToggleFriendlyNPCNameplates())
    combat, module.config.enabled = false, false
    assert(not NS.ToggleFriendlyNPCNameplates())
    module.config.enabled, liveCVars.nameplateShowFriendlyNpcs = true, "secret"
    assert(not NS.ToggleFriendlyNPCNameplates() and writes == 2)
end
