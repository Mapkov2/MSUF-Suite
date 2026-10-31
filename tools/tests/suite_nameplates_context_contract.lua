local root = assert(arg[1])
local override = os.getenv("SUITE_NAMEPLATES_SKIN_OVERRIDE")
local secret = setmetatable({}, { __tostring = function() error("secret text") end })
local counts, events, plates, units, members = {}, {}, {}, {}, {}
local module
local instance, grouped, tank, pvp, reference = "party", true, true, nil, 90
local partyName, raidName, guidReads = false, nil, 0
local function Count(key) counts[key] = (counts[key] or 0) + 1 end
local function Public(value) return not rawequal(value, secret) end
local function Finite(value) return Public(value) and type(value) == "number" end
local function Nothing() end
local function Region()
    local r = { shown = true, alpha = .7, path = "native", size = 10, flags = "" }
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetShown(value) self.shown = value end
    function r:IsShown() return self.shown end
    function r:GetAlpha() return self.alpha end
    function r:SetAlpha(value) self.alpha = value end
    function r:GetFont() Count("GetFont"); return self.path, self.size, self.flags end
    function r:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
    function r:GetShadowColor() return 0, 0, 0, .6 end
    function r:GetShadowOffset() return 1, -1 end
    function r:SetShadowColor(_, _, _, alpha) self.shadow = alpha end
    function r:SetShadowOffset(x, y) self.shadowX, self.shadowY = x, y end
    function r:SetColorTexture(color) self.color = color end
    function r:SetAllPoints(target) self.target = target end
    r.SetVertexColor, r.ClearAllPoints = Nothing, Nothing
    function r:CreateTexture() return Region() end
    function r:GetStatusBarTexture() return self.texture end
    return r
end

local function Member(unit) return members[unit] end
UnitExists = function(unit) return Member(unit) ~= nil end
UnitGroupRolesAssigned = function(unit) return Member(unit) and Member(unit).role end
UnitGUID = function() guidReads = guidReads + 1; return secret end
UnitIsUnit = function() return false end
UnitInParty = function(unit)
    Count(unit == "player" and "PlayerParty" or "PlateParty")
    return unit == "player" and grouped or units[unit] and units[unit].friendly and partyName
end
UnitInRaid = function(unit) Count("PlateRaid"); return units[unit] and units[unit].friendly and raidName end
IsInRaid = function() return false end
IsInInstance = function() return instance ~= "none", instance end
GetInstanceInfo = function() return nil, instance, nil, nil, nil, nil, nil, nil, nil, false end
C_PvP = { GetZonePVPInfo = function() return pvp end }
PlayerUtil = { IsPlayerEffectivelyTank = function() return tank end }
UnitLevel = function(unit) return unit == "player" and reference or units[unit].level end
UnitEffectiveLevel = UnitLevel
UnitClassification = function(unit) return units[unit].classification end
UnitIsBossMob = function() return false end
UnitIsLieutenant = function(unit) return units[unit].lieutenant end
UnitIsTrivial = function() return false end
UnitHasPowerType = function() return false end
UnitIsDead = function() return false end
UnitIsConnected = function() return true end
UnitPlayerControlled = function() return false end
UnitIsTapDenied = function(unit) return units[unit].tapped end
UnitReaction = function() return 2 end
UnitCanAttack = function() return true end
UnitThreatSituation = function(unit, other) return units[other or unit].threat end
UnitThreatLeadSituation = function(_, unit) return units[unit].lead end
UnitDetailedThreatSituation = function(unit, mob)
    if unit == "player" then return false, units[mob].onList end
    local member = Member(unit)
    return member and member.occupant == units[mob].held
end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
C_QuestLog = { UnitIsRelatedToActiveQuest = function(unit) return units[unit].quest end }
C_TooltipInfo = { GetUnit = function() return nil end }
Enum = { PowerType = { Mana = 0 } }
NamePlateSetupOptions = {}
NamePlateUnitFrameMixin = { ApplyFrameOptions = Nothing }
hooksecurefunc = Nothing
EditModeManagerFrame = { IsEditModeActive = function() return false end }
C_NamePlate = { GetNamePlates = function() return plates end,
    GetNamePlateForUnit = function(unit) return units[unit] and units[unit].plate end }

local Style = {
    Font = function(key) return key end, FontFlags = function() return "" end,
    TargetConfig = function() return {} end,
    PaintBorder = Nothing,
    PaintTarget = function(visual, _, visible) visual.targetShown = visible end,
    PaintMarker = function(texture, _, _, _, variant) texture.variant = variant end,
    PlaceMarker = Nothing,
    CreateBorder = function()
        return { edges = { Region(), Region(), Region(), Region() } }
    end,
}
local NS = { NameplateStyle = Style, Client = {}, Finite = Finite, IsCombatLocked = function() return true end, Safety = {
    IsForbidden = function(frame) return frame.forbidden end,
} }
local S = { Public = Public, Finite = Finite, RGB = function(hex) return hex, 0, 0 end,
    SetFont = function(region, ...) region:SetFont(...) end,
    Install = function(_, owner) module = owner end }
local private = { NS = NS, Suite = S, Geometry = { LevelBadgeShown = function() return false end } }
local function Component(name, methods)
    local component = {}
    for method in methods:gmatch("%S+") do
        component[method] = function() Count(name .. "." .. method) end
    end
    private[name] = component
    return component
end
Component("Layout", "Bind Configure Apply Restore RestoreAll")
Component("Power", "Enable Refresh Reapply Disable")
Component("Threat", "Enable Apply Restore Disable Refresh")
Component("Level", "Bind PaintNative Paint Hide RestoreNative")
Component("CastTime", "Bind Paint Restore Refresh")
Component("CVars", "Apply")
Component("Auras", "Bind Apply Restore")
Component("KickReady", "Bind Paint Restore Configure Disable")
Component("Mouseover", "Bind Configure Restore Disable")
Component("Selection", "Apply Restore Configure RestoreAll")
Component("Decor", "Configure Paint Restore Disable TargetChanged")
Component("AuraColors", "Bind Configure Apply Restore SetEditMode")
private.AuraColors.Apply = function(frame)
    assert(not frame.forbidden and not frame.HealthBarsContainer.healthBar.forbidden,
        "specialization applied aura colors to a forbidden plate")
    Count("AuraColors.Apply")
end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Roles.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Text.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/FriendlyNames.lua"))("nameplates", private)
assert(loadfile(override or root .. "/MSUF_Suite_Nameplates/Skin.lua"))("nameplates", private)
local applyText = private.Text.Apply
private.Text.Apply = function(...) Count("Text.Apply"); return applyText(...) end
module.config = {
    look = 1, enemy = true, friendly = true, friendlyNamesOnly = 3,
    enemyRoleColors = true, enemyTankMode = true, enemyQuestColors = true,
    enemyEliteMarker = true, enemyQuestMarker = true, enemyOtherTankColor = "other",
    enemyBossColor = "boss", enemyMinibossColor = "lieutenant", enemyMeleeColor = "melee",
    enemyQuestColor = "quest", enemyTankModeColor = "tank", enemyThreatLostColor = "lost",
    enemyThreatWarningColor = "warning", enemyTappedColor = "tapped",
    enemyBackdropColor = "back", friendlyBackdropColor = "back",
}
module.context = {
    Event = function(_, event, callback) events[event] = callback end,
    Coalesce = function() return { Cancel = Nothing, Request = Nothing } end,
}
for i = 1, 5 do
    local unit = "nameplate" .. i
    local frame, health = Region(), Region()
    frame.name, frame.isFriend, frame.isPlayer = Region(), i == 3, i == 3
    frame.optionTable = { usePlayerForAggroHighlightThreat = true }
    frame.HealthBarsContainer = { healthBar = health }
    health.texture, health.Text = Region(), Region()
    if i <= 2 then
        local cast = Region()
        cast.Text, cast.CastTargetNameText = Region(), Region()
        frame.CastBarsContainer = { castBar = cast }
    end
    local plate = { UnitFrame = frame, unitToken = unit }
    plates[i] = plate
    units[unit] = { plate = plate, level = i < 3 and 82 - i or i == 3 and 90 or 90 - i,
        classification = "elite", lieutenant = i == 2 or i == 5, friendly = i == 3,
        threat = 3, lead = 3, held = "first", quest = false }
end
members.party1 = { role = "TANK", occupant = "first" }

local function Snapshot()
    local result = {}
    for _, plate in ipairs(plates) do
        local frame = plate.UnitFrame
        local health, name = frame.HealthBarsContainer.healthBar, frame.name
        local facts, visual = module.facts[health], module.visuals[health]
        for _, value in ipairs({ module.roles[health] or "none", facts.kind or "none", tostring(facts.quest),
            tostring(visual.fill.shown), visual.fill.color or "none", tostring(visual.quest.shown),
            tostring(visual.elite.shown), visual.elite.variant or "none", tostring(name.alpha),
            name.path, tostring(name.size), name.flags, tostring(name.shadow) }) do
            result[#result + 1] = value
        end
    end
    return table.concat(result, ",")
end

local function Event(event, unit)
    counts = {}
    debug.sethook(function()
        local info = debug.getinfo(2, "nS")
        if info.source:match("Skin.lua$") and (info.name == "Paint" or info.name == "PaintFonts") then Count(info.name) end
    end, "c")
    events[event](module, event, unit)
    debug.sethook()
end
local function Replay(event)
    Event(event)
    assert(not counts.Paint and not counts.PaintFonts and not counts["Text.Apply"] and not counts["Layout.Apply"],
        event .. " repeated presentation: Paint=" .. (counts.Paint or 0) .. ", Text.Apply=" .. (counts["Text.Apply"] or 0))
    assert(not counts["Level.Paint"] and not counts["CastTime.Paint"] and not counts["Auras.Apply"],
        event .. " repeated level, cast or aura presentation")
    local spec = event == "PLAYER_SPECIALIZATION_CHANGED"
    assert((counts["AuraColors.Configure"] or 0) == (spec and 1 or 0)
        and (counts["AuraColors.Apply"] or 0) == (spec and #plates or 0), "specialization DoT refresh changed")
    -- Kick-ready follows the specialization's interrupt spells: every shown
    -- cast once for a specialization change, never for roster or roles.
    assert((counts["KickReady.Paint"] or 0) == (spec and 2 or 0), event .. " changed the kick-ready repaint")
    local actual = Snapshot()
    Event("PLAYER_ENTERING_WORLD")
    assert(counts.Paint and counts["Layout.Apply"]
        and (module.config.look == 2 or counts.PaintFonts and counts["Text.Apply"]),
        "world entry lost its full presentation pass")
    assert(actual == Snapshot(), event .. " differed from full classification and painting")
end

for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    module.active = true
    module:Enable()
    -- The tank token stays party1 while its occupant changes. No GUID is readable.
    members.party1.occupant = "second"
    Replay("GROUP_ROSTER_UPDATE")
    assert(module.roles[plates[1].UnitFrame.HealthBarsContainer.healthBar] == "ThreatLost", "tank slot churn was skipped")
    units.nameplate1.level, units.nameplate2.level = 87, 86
    Event("UNIT_LEVEL", "nameplate1")
    Event("NAME_PLATE_UNIT_ADDED", "nameplate2")
    assert(counts.Paint == 1 and counts.PaintFonts == 1 and counts["Layout.Apply"] == 1,
        "lieutenant discovery repainted presentation on existing plates")
    assert(module.facts[plates[1].UnitFrame.HealthBarsContainer.healthBar].kind == "Boss", "plate add lost lieutenant discovery")
    units.nameplate1.level, units.nameplate2.level = 81, 80
    Event("PLAYER_ENTERING_WORLD")
    tank = false
    Replay("PLAYER_ROLES_ASSIGNED")
    tank, partyName = true, true
    units.nameplate1.lead, units.nameplate1.onList = 0, 0
    Replay("PLAYER_SPECIALIZATION_CHANGED")
    assert(module.roles[plates[1].UnitFrame.HealthBarsContainer.healthBar] == "TankMode", "tank spec did not update threat")
    module.visuals[plates[1].UnitFrame.HealthBarsContainer.healthBar] = nil
    Event("PLAYER_SPECIALIZATION_CHANGED")
    assert(counts.Paint == 1 and counts["AuraColors.Apply"] == #plates,
        "cold specialization fallback skipped presentation or applied aura colors twice")
    module.visuals[plates[3].UnitFrame.HealthBarsContainer.healthBar] = nil
    Event("PLAYER_SPECIALIZATION_CHANGED")
    assert(counts.Paint == 1 and counts.PlateParty == 2 and counts.PlateRaid == 2,
        "cold friendly fallback added membership queries beyond the two classification passes")
    for _, region in ipairs({ plates[1].UnitFrame, plates[1].UnitFrame.HealthBarsContainer.healthBar }) do
        region.forbidden = true
        Event("PLAYER_SPECIALIZATION_CHANGED")
        assert(counts["AuraColors.Apply"] == #plates - 1 and not counts.Paint,
            "specialization bypassed forbidden plate guards")
        region.forbidden = nil
    end
    units.nameplate1.lead, units.nameplate1.onList = 3, nil
    members.party1.role, partyName, raidName = "HEALER", false, secret
    Replay("GROUP_ROSTER_UPDATE")
    grouped, raidName = false, nil
    Replay("GROUP_ROSTER_UPDATE")
    assert(module.facts[plates[1].UnitFrame.HealthBarsContainer.healthBar].kind == "Boss"
        and module.facts[plates[4].UnitFrame.HealthBarsContainer.healthBar].kind == "Boss", "lieutenant reclassification was lost")
    instance, units.nameplate1.quest = "none", true
    Event("ZONE_CHANGED_NEW_AREA")
    Replay("PLAYER_ROLES_ASSIGNED")
    units.nameplate1.quest = false
    Replay("GROUP_ROSTER_UPDATE")
    assert(not module.visuals[plates[1].UnitFrame.HealthBarsContainer.healthBar].quest.shown, "roster kept stale quest marks")
    module.config.friendly = false
    module:Refresh()
    partyName = true
    Replay("GROUP_ROSTER_UPDATE")
    partyName = false
    Replay("GROUP_ROSTER_UPDATE")
    module.config.friendly = true
    module.config.look = 2
    module:Refresh()
    Replay("PLAYER_ROLES_ASSIGNED")
    module.config.look = 1
    module:Refresh()
    for _, event in ipairs({ "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
        Event(event)
        assert(counts.Paint and counts["Level.Paint"] and counts["Layout.Apply"], event .. " skipped native level/geometry work")
    end
    pvp = "combat"
    Event("ZONE_CHANGED")
    assert(counts.Paint and not private.Roles.allowed, "changed subzone lost its full pass or role gate")
    Event("ZONE_CHANGED")
    assert(not counts.Paint and not counts["Text.Apply"], "unchanged subzone repainted")
    pvp, instance, grouped, tank = nil, "party", true, true
    members.party1.role, members.party1.occupant = "TANK", "first"
    module:Disable()
end
assert(guidReads == 0, "context refresh read group GUIDs")
print("Suite nameplates: combat roster/role/spec replay matches full paints with zero presentation calls on Retail/Forever")
