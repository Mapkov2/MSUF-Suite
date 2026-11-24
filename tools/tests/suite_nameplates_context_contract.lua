local root = assert(arg[1])
local override = os.getenv("SUITE_NAMEPLATES_SKIN_OVERRIDE")
local secret = setmetatable({}, { __tostring = function() error("secret text") end })
local counts, events, plates, units, members = {}, {}, {}, {}, {}
local module
local instance, grouped, tank, pvp, reference = "party", true, true, nil, 90
local partyName, raidName, guidReads = false, nil, 0
local combat = false
local function Count(key) counts[key] = (counts[key] or 0) + 1 end
local function Public(value) return not rawequal(value, secret) end
local function Finite(value) return Public(value) and type(value) == "number" end
local function Nothing() end
local function Region()
    local r = { shown = true, alpha = .7, path = "native", size = 10, flags = "" }
    function r:Show()
        local wasShown = self.shown
        self.shown = true
        local hooks = self.scriptHooks and self.scriptHooks.OnShow
        if not wasShown and hooks then
            for i = 1, #hooks do hooks[i](self) end
        end
    end
    function r:HookScript(script, callback)
        self.scriptHooks = self.scriptHooks or {}
        local hooks = self.scriptHooks[script] or {}
        self.scriptHooks[script] = hooks
        hooks[#hooks + 1] = callback
    end
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
    function r:GetTextColor()
        self.fontReads = (self.fontReads or 0) + 1
        return self.textR or 1, self.textG or 1, self.textB or 1, self.textA or 1
    end
    function r:SetTextColor(red, green, blue, alpha)
        self.textR, self.textG, self.textB, self.textA = red, green, blue, alpha
    end
    function r:SetVertexColor(red, green, blue, alpha)
        self.vertexR, self.vertexG, self.vertexB, self.vertexA = red, green, blue, alpha
    end
    function r:GetVertexColor() return self.vertexR or 1, self.vertexG or 1, self.vertexB or 1, self.vertexA or 1 end
    function r:IsProtected() return false end
    r.ClearAllPoints = Nothing
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
UnitIsPlayer = function(unit) return units[unit].plate.UnitFrame.isPlayer end
UnitIsTapDenied = function(unit) return units[unit].tapped end
UnitReaction = function(unit) return units[unit] and units[unit].reaction or 2 end
UnitAffectingCombat = function(unit) return units[unit] and units[unit].fighting == true end
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
local SharedStyle = { AnchorPoints = {}, AnchorLabels = {} }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", SharedStyle)
setmetatable(Style, { __index = SharedStyle.NameplateStyle })
local function RGB(hex)
    if hex == "e5db00" then return .9, .86, 0 end
    if hex == "lost" then return .85, .05, .1 end
    return hex, 0, 0
end
local NS = { NameplateStyle = Style, Client = {}, Finite = Finite, RGB = RGB, IsSecret = function(value) return not Public(value) end,
    InCombat = function() return combat end,
    IsCombatLocked = function() return true end, Safety = {
    IsForbidden = function(frame) return frame.forbidden end,
} }
local S = { Public = Public, Finite = Finite, RGB = RGB,
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
Component("Layout", "Bind Configure Apply Restore RestoreAll Observe")
Component("Power", "Enable ConfigureEnemy Refresh Reapply Disable SetExtraTextEvents")
Component("Threat", "Enable Apply Restore Disable Refresh")
Component("Level", "Bind PaintNative Paint Hide RestoreNative")
Component("CastTime", "Bind Paint Restore Refresh")
Component("CVars", "Apply InstanceChanged")
Component("Auras", "Bind Configure Apply Restore")
Component("KickReady", "Bind Paint Restore Configure Disable OnCast")
Component("Mouseover", "Bind Configure Restore Disable")
Component("Selection", "Bind Apply Restore Configure RestoreAll")
Component("Decor", "Configure Paint Restore Disable TargetChanged")
Component("AuraColors", "Bind Configure Apply Restore SetEditMode")
Component("AuraDisplay", "Bind Configure Apply Restore Release Resume SetEditMode TargetChanged")
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("MSUF_Suite", NS)
private.AuraColors.Apply = function(frame)
    assert(not frame.forbidden and not frame.HealthBarsContainer.healthBar.forbidden,
        "specialization applied aura colors to a forbidden plate")
    Count("AuraColors.Apply")
end
NS.AnchorPoints, NS.AnchorLabels = {}, {}
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Roles.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Text.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/FriendlyNames.lua"))("nameplates", private)
NS.HostBridge = NS.HostBridge or {}
NS.HostBridge.NameFormatter = function() return nil end
NS.NameplatePortableText = { Stored = function() end, Resolve = function() end }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateText.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/NameText.lua"))("nameplates", private)
-- Keep presentation mocked while exercising the relocated real cast router
-- and the entirely disabled extension lifecycle alongside this context test.
local castPresentation = private.CastTime
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastTime.lua"))("nameplates", private)
private.CastTime.Paint, private.CastTime.Restore = castPresentation.Paint, castPresentation.Restore
private.CastTime.Refresh = castPresentation.Refresh
for _, file in ipairs({ "ExtensionLayout", "ExtensionText", "ExtensionEffects", "Extensions", "Status" }) do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file .. ".lua"))("nameplates", private)
end
NS.ResolveTexture = function() end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastSettings.lua"))("Nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Textures.lua"))("nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/HealthAppearance.lua"))("nameplates", private)
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
    RemoveEvent = function(_, event) events[event] = nil end,
    Coalesce = function() return { Cancel = Nothing, Request = Nothing } end,
    Cancel = Nothing,
}
for i = 1, 5 do
    local unit = "nameplate" .. i
    local frame, health = Region(), Region()
    frame.name, frame.isFriend, frame.isPlayer = Region(), i == 3, i == 3
    frame.optionTable = { usePlayerForAggroHighlightThreat = true }
    frame.HealthBarsContainer = Region()
    frame.HealthBarsContainer.healthBar = health
    health.texture, health.Text = Region(), Region()
    if i <= 2 then
        local cast = Region()
        cast.Text, cast.CastTargetNameText = Region(), Region()
        frame.CastBarsContainer = Region()
        frame.CastBarsContainer.castBar = cast
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
        if info.source:match("Skin.lua$") or info.source:match("HealthAppearance.lua$") then
            if info.name == "PaintAdded" then Count("Paint")
            elseif info.name == "Paint" or info.name == "PaintFonts" then Count(info.name) end
        end
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
    -- Friendly NPC Name only switches between plates and world names here.
    assert(counts["CVars.InstanceChanged"] == 1, "leaving the instance kept its friendly NPC display")
    Replay("PLAYER_ROLES_ASSIGNED")
    assert(not counts["CVars.InstanceChanged"], "an unchanged instance state applied the CVars again")
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
    local mob, frame = units.nameplate1, plates[1].UnitFrame
    local held = mob.held
    mob.held = nil
    module.config.neutralPlateNameOnly, module.config.neutralPlateNameTypeColor = true, true
    module.config.enemyNeutralColor, mob.reaction = "e5db00", 4
    module:Refresh()
    assert(module.roles[frame.HealthBarsContainer.healthBar] == "ThreatLost"
        and frame.name.textR == .85 and frame.name.textG == .05, "neutral NPC lost its actual threat bar color")
    mob.lead, mob.threat = nil, nil
    Event("UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
    assert(private.FriendlyNames.NameOnlyScope(frame) == "neutral" and frame.name.textR == .9)
    local reads = frame.name.fontReads
    Event("UNIT_FACTION", "nameplate1")
    assert(frame.name.fontReads == reads + 1, "an unchanged plate paint checked the same font color more than once")
    -- This pooled frame previously drew ordinary health bars. Selecting the
    -- NPC must refresh its current name even while the old visual is cached.
    assert(module.visuals[frame.HealthBarsContainer.healthBar])
    frame.name:SetTextColor(1, 0, 0, 1)
    units.target = mob
    Event("PLAYER_TARGET_CHANGED")
    units.target = nil
    assert(frame.name.textR == .9 and frame.name.textG == .86,
        "selecting a name-only NPC with a cached bar visual left a red name")
    frame.name:SetTextColor(1, 1, 1, 1)
    Event("PLAYER_TARGET_CHANGED")
    assert(frame.name.textR == .9 and frame.name.textG == .86,
        "clearing the target left the previous neutral name white")
    local oldNPCs, oldTint = module.config.friendlyNPCs, module.config.friendlyNpcPlateNameTypeColor
    module.config.friendlyNPCs, module.config.friendlyNpcPlateNameTypeColor = 5, true
    local oldPalette = NS.HostBridge.NPCNameColor
    NS.HostBridge.NPCNameColor = function() return 0, 1, 0 end
    frame.isFriend, mob.friendly, mob.reaction = true, true, 5
    module:Refresh()
    assert(private.FriendlyNames.NameOnlyScope(frame) == "friendlyNpc" and frame.name.textG == 1)
    -- The plate keeps isFriend=true when the now-readable reaction is 4.
    -- Selection can arrive before any faction or flags notification.
    mob.reaction, units.target = 4, mob
    frame.name:SetTextColor(1, 1, 1, 1)
    Event("PLAYER_TARGET_CHANGED")
    assert(private.FriendlyNames.NameOnlyScope(frame) == "neutral" and frame.name.textG == .86,
        "selection replayed a stale friendly tint on a neutral NPC")
    local health = frame.HealthBarsContainer.healthBar
    -- The Suite listener can miss acquisition when the native driver still
    -- hasn't attached its UnitFrame to the base in NAME_PLATE_UNIT_ADDED.
    Event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    mob.plate.UnitFrame = nil
    Event("NAME_PLATE_UNIT_ADDED", "nameplate1")
    mob.plate.UnitFrame = frame
    assert(not module.activeUnits.nameplate1 and not module.units[health])
    local getPlates = C_NamePlate.GetNamePlates
    C_NamePlate.GetNamePlates = function() error("selecting an unobserved plate scanned other units") end
    for _, unsettled in ipairs({ secret, "target", "nameplate4" }) do
        frame.unit = unsettled
        Event("PLAYER_TARGET_CHANGED")
        assert(not module.activeUnits.nameplate1 and not module.activeUnits.target and not module.units[health],
            "target recovery adopted a restricted, aliased or stale native unit")
    end
    frame.unit = "nameplate1"
    Event("PLAYER_TARGET_CHANGED")
    C_NamePlate.GetNamePlates = getPlates
    assert(module.activeUnits.nameplate1 == frame and module.units[health] == "nameplate1"
        and private.FriendlyNames.NameOnlyScope(frame) == "neutral" and frame.name.textG == .86,
        "selecting a settled frame after a missed native acquisition left it unmanaged")
    module.config.neutralPlateNameOnly = false
    module:Refresh()
    assert(private.PlatePrefix(frame) == "enemy" and module.roles[health] == "Neutral"
        and not private.FriendlyNames.IsNameOnly(frame) and frame.HealthBarsContainer.alpha == .7,
        "selecting Neutral Health bars used the Friendly NPC settings for the same target")
    module.config.neutralPlateNameOnly = true
    module:Refresh()
    units.target, frame.isFriend, mob.friendly = nil, false, false
    NS.HostBridge.NPCNameColor = oldPalette
    module.config.friendlyNPCs, module.config.friendlyNpcPlateNameTypeColor = oldNPCs, oldTint
    combat, mob.fighting = true, true
    Event("UNIT_FLAGS", "nameplate1")
    assert(private.FriendlyNames.NameOnlyScope(frame) == "neutral" and frame.name.textR == .9,
        "combat entry changed the neutral name or its color")
    mob.reaction = 2
    Event("UNIT_FLAGS", "nameplate1")
    assert(not private.FriendlyNames.IsNameOnly(frame) and frame.HealthBarsContainer.alpha == .7 and frame.name.textR == 1,
        "a real faction change did not release the neutral name-only display")
    combat, mob.fighting, mob.reaction = false, nil, nil
    mob.lead, mob.threat, mob.held = 3, 3, held
    module.config.neutralPlateNameOnly, module.config.neutralPlateNameTypeColor = nil, nil
    module:Disable()
end
assert(guidReads == 0, "context refresh read group GUIDs")
-- Native threat level 2 may receive its own color; the default keeps the
-- combined warning and restricted threat still falls through to NPC type.
module.config.enemyOtherTankEnabled = false
private.Roles.Configure(module.config)
local facts = { eligible = true, rest = "Melee" }
local frame = plates[1].UnitFrame
units.nameplate1.lead = 2
assert(private.Roles.Get(facts, "nameplate1", frame) == "ThreatWarning")
module.config.enemyThreatTransitionEnabled = true
assert(private.Roles.Get(facts, "nameplate1", frame) == "ThreatTransition")
units.nameplate1.lead = 1
assert(private.Roles.Get(facts, "nameplate1", frame) == "ThreatWarning")
units.nameplate1.lead = 3
assert(private.Roles.Get(facts, "nameplate1", frame) == "ThreatLost")
units.nameplate1.lead = secret
assert(private.Roles.Get(facts, "nameplate1", frame) == "Melee")
print("Suite nameplates: combat roster/role/spec replay matches full paints with zero presentation calls on Retail/Forever")
