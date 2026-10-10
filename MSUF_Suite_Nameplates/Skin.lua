local _, private = ...
local NS, S = private.NS, private.Suite
local Mode, Key, RoleKey = private.Mode, private.Key, private.RoleKey
local LOOK_BLIZZARD = Mode.LOOK_BLIZZARD
local Style = NS.NameplateStyle
local Border = Style.PaintBorder
local Layout, Roles, Text, Power, Threat = private.Layout, private.Roles, private.Text, private.Power, private.Threat
local Level, CastTime, CVars, Auras = private.Level, private.CastTime, private.CVars, private.Auras
local KickReady = private.KickReady
local LevelBadgeShown = private.Geometry.LevelBadgeShown
local IN_COMBAT = { inCombat = true }
local M = {
    visuals = setmetatable({}, { __mode = "k" }),
    roles = setmetatable({}, { __mode = "k" }),
    facts = setmetatable({}, { __mode = "k" }),
    units = setmetatable({}, { __mode = "k" }),
    activeUnits = {},
    auraHooks = setmetatable({}, { __mode = "k" }),
    auraButtons = setmetatable({}, { __mode = "k" }),
    friendlyNames = setmetatable({}, { __mode = "k" }),
    raidIcons = setmetatable({}, { __mode = "k" }),
    castTimes = setmetatable({}, { __mode = "k" }),
    kicks = setmetatable({}, { __mode = "k" }),
    levelLabels = setmetatable({}, { __mode = "k" }),
    nativeLevelAlphas = setmetatable({}, { __mode = "k" }),
}

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function Color(texture, hex, alpha)
    local r, g, b = S.RGB(hex)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetColorTexture(r, g, b, alpha or 1)
end

local RestoreFont = Text.Restore

local function RestorePlateFonts(uf, health, cast)
    RestoreFont(uf.name)
    RestoreFont(health.Text)
    RestoreFont(health.LeftText)
    RestoreFont(health.RightText)
    if cast then
        RestoreFont(cast.Text)
        RestoreFont(cast.CastTargetNameText)
        CastTime.Restore(cast)
    end
end

-- The color overlay follows Blizzard's filled StatusBar texture. No health,
-- cast progress or aura value is read or cached by this module.
local function Visual(bar, markerOwner)
    local visual = M.visuals[bar]
    if visual then return visual end
    visual = Style.CreateBorder(bar)
    visual.back = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    visual.back:SetAllPoints(bar)
    -- Blizzard may reapply its StatusBar texture after plate setup. A higher
    -- sublayer keeps the role tint visible without repainting health ticks.
    visual.fill = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    visual.fill:Hide()
    visual.elite = markerOwner:CreateTexture(nil, "OVERLAY", nil, 7)
    visual.elite:Hide()
    visual.quest = markerOwner:CreateTexture(nil, "OVERLAY", nil, 7)
    visual.quest:Hide()
    M.visuals[bar] = visual
    return visual
end

local function HideVisual(visual)
    if not visual then return end
    visual.back:Hide()
    visual.fill:Hide()
    Style.PaintTarget(visual, nil, false)
    visual.elite:Hide()
    visual.quest:Hide()
    for i = 1, 4 do visual.edges[i]:Hide() end
end

local function Prefix(uf)
    local value = uf.isFriend
    if not S.Public(value) or type(value) ~= "boolean" then return nil end
    return value and "friendly" or "enemy"
end

-- The unit facts of one plate (its health bar), reused while the plate lives:
-- marker, quest, kind (the type role) and the threat-independent part of the
-- color role (Roles.Base). Plate setup, faction, level, classification and
-- power display changes read them; flags re-read only the base role; threat
-- events reuse everything and only evaluate the threat rules (Roles.Get).
local function Facts(health)
    local facts = M.facts[health]
    if not facts then
        facts = {}
        M.facts[health] = facts
    end
    facts.marker, facts.quest, facts.kind, facts.colored, facts.wantsQuest = nil, nil, nil, false, false
    facts.eligible = false
    return facts
end

local function ReadFacts(uf, unit, facts)
    local prefix = Prefix(uf)
    if M.config.look == LOOK_BLIZZARD or not prefix or not M.config[prefix] then return end
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local focus = UnitIsUnit(unit, "focus")
    if S.Public(focus) and focus == true then M.focusUF = uf end
    if not S.Public(uf.isPlayer) or uf.isPlayer ~= false then return end
    local color = prefix == "enemy" and M.config.enemyRoleColors and Roles.allowed
    local keys = Key[prefix]
    local elite, quest = M.config[keys.EliteMarker], M.config[keys.QuestMarker]
    if not color and not elite and not quest then return end
    local classification = UnitClassification(unit)
    if not S.Public(classification) then classification = false end
    if elite then facts.marker = Roles.Marker(unit, classification) end
    facts.wantsQuest = quest or color and M.config.enemyQuestColors
    if facts.wantsQuest then facts.quest = Roles.Quest(unit) end
    if color and M.active then
        facts.colored = true
        facts.kind = Roles.Classify(unit, classification)
        Roles.Base(facts, unit, uf)
    end
end

-- Unit metadata is refreshed on identity/threat/quest events, never health ticks.
local function SetRole(uf, unit)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    M.units[health] = unit
    local facts = Facts(health)
    ReadFacts(uf, unit, facts)
    M.roles[health] = facts.colored and Roles.Get(facts, unit, uf) or nil
end

local function PaintMarker(texture, health, kind, enabled, size, x, y, color, anchor, variant)
    if not enabled then
        texture:Hide()
        return
    end
    Style.PaintMarker(texture, kind, size, color, variant)
    if texture._msufX ~= x or texture._msufY ~= y or texture._msufAnchor ~= anchor then
        Style.PlaceMarker(texture, health, kind, x, y, anchor)
        texture._msufX, texture._msufY, texture._msufAnchor = x, y, anchor
    end
    texture:Show()
end

local function PaintFill(health, visual, prefix)
    local role = prefix == "enemy" and M.config.enemyRoleColors and M.roles[health]
    if role and M.config[RoleKey[role].enabled] == false then role = nil end
    local fillTexture = health:GetStatusBarTexture()
    if not role or not Safe(fillTexture) then
        visual.fill:Hide()
        return
    end
    if visual.fillTarget ~= fillTexture then
        visual.fill:ClearAllPoints()
        visual.fill:SetAllPoints(fillTexture)
        visual.fillTarget = fillTexture
    end
    local hex = M.config[RoleKey[role].color]
    if visual.fillColor ~= hex then
        Color(visual.fill, hex)
        visual.fillColor = hex
    end
    visual.fill:Show()
end

local function PaintHealth(health, visual, prefix)
    local c, keys = M.config, Key[prefix]
    local backColor = c[keys.BackdropColor]
    local backAlpha = (c[keys.BackdropAlpha] or 100) / 100
    if visual.backColor ~= backColor or visual.backAlpha ~= backAlpha then
        Color(visual.back, backColor, backAlpha)
        visual.backColor, visual.backAlpha = backColor, backAlpha
    end
    Border(visual, health, c[keys.BorderEnabled] == false and 0 or c[keys.BorderSize], c[keys.BorderColor])
    visual.back:SetShown(c[keys.BackdropEnabled] ~= false and backAlpha > 0)
    PaintFill(health, visual, prefix)
    local facts = M.facts[health]
    local marker, quest = facts and facts.marker, facts and facts.quest
    PaintMarker(visual.elite, health, "elite", c[keys.EliteMarker] and marker,
        c[keys.EliteMarkerSize] or 14, c[keys.EliteOffsetX] or -13,
        c[keys.EliteOffsetY] or 0, c.enemyMinibossColor, c[keys.EliteMarkerAnchor], marker)
    PaintMarker(visual.quest, health, "quest", c[keys.QuestMarker] and quest,
        c[keys.QuestMarkerSize] or 15, c[keys.QuestOffsetX] or 0,
        c[keys.QuestOffsetY] or 17, c.enemyQuestColor, c[keys.QuestMarkerAnchor])
end

-- The arrows keep clear of the level badge or number beside the bar.
local function TargetGaps(uf, unit)
    local setup = NamePlateSetupOptions
    local badge = not NS.Client.isForever or M.config.levelAppearance == Mode.LEVEL_BADGE
    local classic = badge and S.Public(setup.useClassicHealthBar) and setup.useClassicHealthBar == true
    local width = classic and setup.levelIconWidth
    local rightGap = S.Finite(width) and width + 4 or classic and 19 or 0
    local leftWidth = setup.playerLevelDiffWidth
    local diffGap = badge and LevelBadgeShown(uf, unit) == true
        and (S.Finite(leftWidth) and leftWidth > 0 and leftWidth + (NS.Client.isForever and 5 or 4)
            or (NS.Client.isForever and 33 or 20)) or 0
    if not NS.Client.isForever then return rightGap, diffGap end
    local label = M.levelLabels[uf]
    local number = Safe(label) and label:IsShown()
    return math.max(rightGap, diffGap), number and (label._suiteLevelWidth or 24) + 4 or 0
end

local function PaintTarget(uf, health, visual, prefix)
    local unit = M.units[health]
    local target = unit and UnitIsUnit(unit, "target")
    local visible = M.config.enemyTargetMarker and (prefix == "enemy" or M.config.enemyTargetHideFriendly == false)
        and S.Public(target) and target == true
    if visible then M.targetUF = uf elseif M.targetUF == uf then M.targetUF = nil end
    local rightGap, leftGap = TargetGaps(uf, unit)
    Style.PaintTarget(visual, health, visible, M.targetConfig, uf, rightGap, leftGap)
end

local function RestoreFriendlyName(name)
    local alpha = name and M.friendlyNames[name]
    if alpha == nil then return end
    if Safe(name) then name:SetAlpha(alpha) end
    M.friendlyNames[name] = nil
end

local function FilterFriendlyName(uf, prefix)
    local name = uf.name
    if not Safe(name) then return end
    if M.config.friendlyNamesOnly ~= Mode.GROUP_NAMES_ONLY
        or prefix ~= "friendly" or not S.Public(uf.isPlayer) or uf.isPlayer ~= true then
        RestoreFriendlyName(name)
        return
    end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local unit = health and M.units[health]
    if not unit then
        RestoreFriendlyName(name)
        return
    end
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if not S.Public(party) or not S.Public(raid) then
        RestoreFriendlyName(name)
        return
    end
    if party or raid then
        RestoreFriendlyName(name)
        return
    end
    if M.friendlyNames[name] == nil then
        local alpha = name:GetAlpha()
        if not NS.Finite(alpha) then return end
        M.friendlyNames[name] = alpha
        -- Alpha survives Blizzard's ordinary name Show()/Hide() refreshes.
        name:SetAlpha(0)
    end
end

local function PaintRaidIcon(uf, prefix)
    local frame = uf.RaidTargetFrame
    local icon = frame and frame.RaidTargetIcon
    if not Safe(icon) then return end
    local original = M.raidIcons[icon]
    local hide = M.active and M.config.look ~= LOOK_BLIZZARD and M.config.enemy and prefix == "enemy"
        and M.config.enemyRaidIcon == false
    if not hide then
        if original ~= nil then
            icon:SetAlpha(original)
            M.raidIcons[icon] = nil
        end
    elseif original == nil then
        local alpha = icon:GetAlpha()
        if S.Finite(alpha) then
            icon:SetAlpha(0)
            M.raidIcons[icon] = alpha
        end
    end
end

local function PaintFonts(uf, health, cast, prefix)
    local c, keys = M.config, Key[prefix]
    Text.Apply(uf.name, Text.styles[prefix], c[keys.NameSize] or 0)
    if prefix == "enemy" then
        Text.Apply(health.Text, Text.styles.enemy, c.enemyHealthTextSize or 0)
        Text.Apply(health.LeftText, Text.styles.enemy, c.enemyHealthTextSize or 0)
        Text.Apply(health.RightText, Text.styles.enemy, c.enemyHealthTextSize or 0)
    else
        RestoreFont(health.Text)
        RestoreFont(health.LeftText)
        RestoreFont(health.RightText)
    end
    if not cast then return end
    local style, size = Text.styles[keys.Cast], c[keys.CastSize] or 0
    Text.Apply(cast.Text, style, size)
    Text.Apply(cast.CastTargetNameText, style, size)
    local time = M.castTimes[cast]
    if time and time.unit then Text.Apply(time.label, style, size) end
end

local function Paint(uf)
    if not M.active or not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    local prefix = Prefix(uf)
    CastTime.Paint(cast, prefix, M.units[health])
    KickReady.Paint(cast, prefix, M.units[health])
    Threat.Apply(uf)
    FilterFriendlyName(uf, prefix)
    PaintRaidIcon(uf, prefix)
    Level.PaintNative(uf, prefix)
    Level.Paint(uf, prefix, M.units[health])
    Layout.Apply(uf, prefix, M.config)
    if M.config.look == LOOK_BLIZZARD or not prefix or not M.config[prefix] then
        if M.targetUF == uf then M.targetUF = nil end
        HideVisual(M.visuals[health])
        RestorePlateFonts(uf, health, cast)
    else
        local visual = Visual(health, uf)
        PaintHealth(health, visual, prefix)
        PaintTarget(uf, health, visual, prefix)
        PaintFonts(uf, health, cast, prefix)
    end
    -- Last: the role tint, arrows and fonts come first whatever the DoT
    -- colors do (AuraColors.lua).
    private.AuraColors.Apply(uf, M.units[health], prefix == "enemy")
end

local function RestorePlate(uf)
    private.AuraColors.Restore(uf)
    Threat.Restore(uf)
    RestoreFriendlyName(uf.name)
    Level.PaintNative(uf, nil)
    Level.Hide(uf)
    PaintRaidIcon(uf)
    Layout.Restore(uf)
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    CastTime.Restore(cast)
    KickReady.Restore(cast)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    M.roles[health], M.units[health] = nil, nil
    if M.facts[health] then Facts(health) end
    HideVisual(M.visuals[health])
    RestorePlateFonts(uf, health, cast)
end

------------------------------------------------------------------ plate hooks
-- Blizzard copies NamePlateUnitFrameMixin's methods into each unit frame it
-- creates (BaseNamePlateUnitFrameTemplate, mixin="NamePlateUnitFrameMixin")
-- and NamePlateDriverFrame pools those frames for the session. A hook on the
-- mixin reaches the frames created after it; a frame that still holds the
-- unhooked method gets a hook of its own when the Suite meets it.
local plateHooks = {}

local function CoverPlate(uf)
    for i = 1, #plateHooks do
        local hook = plateHooks[i]
        if uf[hook.method] == hook.original then hooksecurefunc(uf, hook.method, hook.callback) end
    end
end

-- Once per method and session (a secure hook cannot be removed). The shown
-- plates are covered by the plate pass (ApplyPlate) that follows every hook.
function private.HookPlates(method, callback)
    plateHooks[#plateHooks + 1] = { method = method, original = NamePlateUnitFrameMixin[method], callback = callback }
    hooksecurefunc(NamePlateUnitFrameMixin, method, callback)
end

local function ApplyPlate(plate)
    if not Safe(plate) or not Safe(plate.UnitFrame) then return end
    local uf, unit = plate.UnitFrame, plate.unitToken
    CoverPlate(uf)
    if not M.active then
        RestorePlate(uf)
        return
    end
    if S.Public(unit) and type(unit) == "string" then
        M.activeUnits[unit] = uf
        SetRole(uf, unit)
    else
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        if Safe(health) then M.roles[health], M.units[health] = nil, nil end
    end
    Paint(uf)
    Auras.Apply(uf)
end

local function EachPlate(callback)
    local plates = C_NamePlate.GetNamePlates()
    for i = 1, #plates do callback(plates[i]) end
end

-- Classifies and repaints every active plate. A lieutenant level seen for
-- the first time on the way bosses the plates classified before it, so the
-- pass then runs once more.
local function RefreshActive(self)
    for unit, uf in pairs(self.activeUnits) do
        if Safe(uf) then
            SetRole(uf, unit)
            Paint(uf)
        end
    end
    if Roles.learnedLieutenant then
        Roles.learnedLieutenant = false
        RefreshActive(self)
    end
end

-- A lieutenant level seen for the first time in this context can make the
-- plates classified before it bosses: those are classified once more.
local function AfterClassify(self)
    if not Roles.learnedLieutenant then return end
    Roles.learnedLieutenant = false
    RefreshActive(self)
end

local function OnAdded(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    Roles.ClearQuest(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local uf = Safe(plate) and plate.UnitFrame
    if not Safe(uf) then return end
    CoverPlate(uf)
    self.activeUnits[unit] = uf
    SetRole(uf, unit)
    Paint(uf)
    Auras.Apply(uf)
    if Roles.learnedLieutenant then AfterClassify(self) end
end

local function OnRemoved(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = self.activeUnits[unit]
    self.activeUnits[unit] = nil
    Roles.ClearQuest(unit)
    if self.targetUF == uf then self.targetUF = nil end
    if uf then RestorePlate(uf) end
end

local function RefreshRole(uf)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local prefix = Prefix(uf)
    local visual = health and M.visuals[health]
    if not Safe(health) or not prefix or not visual or M.config.look == LOOK_BLIZZARD or not M.config[prefix] then
        Paint(uf)
        return
    end
    PaintHealth(health, visual, prefix)
end

local function RefreshTarget(uf)
    if not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local prefix = Prefix(uf)
    local visual = health and M.visuals[health]
    if not Safe(health) or not prefix or not visual or M.config.look == LOOK_BLIZZARD or not M.config[prefix] then
        Paint(uf)
        return
    end
    PaintTarget(uf, health, visual, prefix)
end

local function CancelQuestRefresh(module)
    module.questJob:Cancel()
end

-- A quest log change can only change quest facts: each visible plate that
-- asks for them re-reads its quest state, and only a changed plate repaints
-- its health skin. Classification and markers stay cached.
local function RefreshQuests(module)
    for unit, uf in pairs(module.activeUnits) do
        local health = Safe(uf) and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        local facts = health and module.facts[health]
        if facts and facts.wantsQuest then
            local before, role = facts.quest, module.roles[health]
            facts.quest = Roles.Quest(unit)
            if facts.colored then
                Roles.Base(facts, unit, uf)
                module.roles[health] = Roles.Get(facts, unit, uf)
            end
            if before ~= facts.quest or role ~= module.roles[health] then RefreshRole(uf) end
        end
    end
end

-- Quest logs can emit several updates together: one pass a second after
-- the first (module.questJob) is enough, and no persistent ticker or plate
-- work runs while idle.
local QUEST_DELAY = 1
local function QuestPass(module)
    if not Roles.inInstance then RefreshQuests(module) end
end

local function OnQuestLogChanged(module)
    Roles.ClearQuest()
    if Roles.inInstance or not (module.config.enemyQuestColors or module.config.enemyQuestMarker
        or module.config.friendlyQuestMarker) then return end
    if not next(module.activeUnits) then return end
    module.questJob:Request()
end

local function OnTargetChanged(self)
    local previous = self.targetUF
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local current = Safe(plate) and plate.UnitFrame
    if Safe(previous) then RefreshTarget(previous) end
    if Safe(current) and current ~= previous then RefreshTarget(current) end
end

-- What a unit event changes on its plate. UNIT_FACTION can turn the plate
-- friendly or hostile (Blizzard re-reads isFriend then) and repaints it;
-- level, classification and power display re-read the unit facts; flags
-- re-read the base role; threat re-evaluates only the threat rules.
local FACT_EVENTS = { UNIT_LEVEL = true, UNIT_CLASSIFICATION_CHANGED = true, UNIT_DISPLAYPOWER = true }

local function OnUnitChanged(module, event, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = module.activeUnits[unit]
    if not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    local facts = module.facts[health]
    if event == "UNIT_FACTION" or not facts then
        SetRole(uf, unit)
        Paint(uf)
        return
    end
    local role, marker, quest = module.roles[health], facts.marker, facts.quest
    if FACT_EVENTS[event] then
        SetRole(uf, unit)
        AfterClassify(module)
        if event == "UNIT_LEVEL" then
            Level.Paint(uf, Prefix(uf), unit)
            -- The target arrows keep clear of a level badge that came or went.
            if M.targetUF == uf then RefreshTarget(uf) end
        end
    elseif facts.colored then
        if event == "UNIT_FLAGS" then Roles.Base(facts, unit, uf) end
        module.roles[health] = Roles.Get(facts, unit, uf)
    end
    if not module.visuals[health] or role ~= module.roles[health]
        or marker ~= facts.marker or quest ~= facts.quest then
        RefreshRole(uf)
    end
end

local function OnCastChanged(module, event, unit)
    if not module.active or not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = module.activeUnits[unit]
    if not Safe(uf) then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    local state = cast and module.castTimes[cast]
    if state and state.unit == unit then CastTime.Refresh(state, unit, event) end
    if cast then KickReady.OnCast(cast, unit, event) end
end

-- MSUF's interrupt-ready settings were applied: repaint the castbars of the
-- shown plates (KickReady.lua decides from MSUF's switch and look).
local function RepaintCasts()
    for _, uf in pairs(M.activeUnits) do
        local health = Safe(uf) and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        local cast = health and uf.CastBarsContainer and uf.CastBarsContainer.castBar
        if cast then KickReady.Paint(cast, Prefix(uf), M.units[health]) end
    end
end

-- Subzone steps (ZONE_CHANGED) fire often while moving; they repaint only
-- when the context the colors depend on changed.
local function OnContextChanged(module, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        private.AuraColors.Configure(module.config, true)
    end
    local changed = Roles.RefreshContext()
    if event == "ZONE_CHANGED" and not changed then return end
    CancelQuestRefresh(module)
    Roles.ClearQuest()
    RefreshActive(module)
end

local function OnFocusChanged(module)
    local previous = module.focusUF
    local plate = C_NamePlate.GetNamePlateForUnit("focus")
    local current = Safe(plate) and plate.UnitFrame
    local function Refresh(uf)
        if not Safe(uf) then return end
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        local unit = health and module.units[health]
        if unit then
            SetRole(uf, unit)
            Paint(uf)
        end
    end
    Refresh(previous)
    if current ~= previous then Refresh(current) end
    module.focusUF = current
end

-- Observe Blizzard's font reset. Never call frame setup ourselves.
local function OnFrameOptions(uf)
    if not M.active then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not health or not M.units[health] then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    Text.Invalidate(uf.name)
    Text.Invalidate(health.Text)
    Text.Invalidate(health.LeftText)
    Text.Invalidate(health.RightText)
    if cast then
        Text.Invalidate(cast.Text)
        Text.Invalidate(cast.CastTargetNameText)
    end
    Paint(uf)
end

local function OnCombatEnded(module)
    local retryQuests = Roles.RetryQuests()
    if not module.needsRefresh then
        if retryQuests then
            CancelQuestRefresh(module)
            RefreshActive(module)
        end
        return
    end
    module.needsRefresh = false
    EachPlate(ApplyPlate)
    Power.Reapply()
end

local UNIT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
    "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL", "UNIT_DISPLAYPOWER" }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP" }
local CONTEXT_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
    "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED" }
local AURA_CONFIG_EVENTS = { "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" }

local function RepaintAuraColors(module)
    for unit, uf in pairs(module.activeUnits) do private.AuraColors.Apply(uf, unit, Prefix(uf) == "enemy") end
end

local function OnAuraSpellsChanged(module)
    private.AuraColors.Configure(module.config, true)
    RepaintAuraColors(module)
end

-- Blizzard's Edit Mode feeds aura containers sample auras: on 12.1.0 the DoT
-- colors hide while it is open (AuraColors.SetEditMode).
local function OnEditModeEnter() private.AuraColors.SetEditMode(true) end
local function OnEditModeExit() private.AuraColors.SetEditMode(false) end

-- Every plate listener also runs in combat (the context's allowCombat, kept
-- explicit should the module ever move frames itself): restyling a native
-- plate is not protected, and each handler checks combat where it matters.
local function Listen(self, event, callback)
    self.context:Event(event, callback, IN_COMBAT)
end

function M:Enable()
    self.questJob = self.context:Coalesce(QUEST_DELAY, QuestPass)
    if not self.fontHook then
        self.fontHook = true
        private.HookPlates("ApplyFrameOptions", OnFrameOptions)
    end
    Listen(self, "NAME_PLATE_UNIT_ADDED", OnAdded)
    Listen(self, "NAME_PLATE_UNIT_REMOVED", OnRemoved)
    Listen(self, "PLAYER_TARGET_CHANGED", OnTargetChanged)
    Listen(self, "PLAYER_FOCUS_CHANGED", OnFocusChanged)
    for _, event in ipairs(UNIT_EVENTS) do Listen(self, event, OnUnitChanged) end
    for _, event in ipairs(CAST_EVENTS) do Listen(self, event, OnCastChanged) end
    Listen(self, "QUEST_LOG_UPDATE", OnQuestLogChanged)
    for _, event in ipairs(CONTEXT_EVENTS) do Listen(self, event, OnContextChanged) end
    Listen(self, "PLAYER_REGEN_ENABLED", OnCombatEnded)
    Power.Enable(self)
    Threat.Enable(self)
    self:Refresh()
end

function M:Refresh()
    CancelQuestRefresh(self)
    Layout.Configure(self.config)
    Roles.Configure(self.config)
    Text.Configure(self.config)
    self.targetConfig = Style.TargetConfig(self.config)
    CVars.Apply(self)
    Threat.Refresh()
    KickReady.Configure()
    private.AuraColors.Configure(self.config)
    if self.config.auraColorsEnabled then
        for _, event in ipairs(AURA_CONFIG_EVENTS) do Listen(self, event, OnAuraSpellsChanged) end
        self.context:Callback("EditMode.Enter", OnEditModeEnter)
        self.context:Callback("EditMode.Exit", OnEditModeExit)
        -- Edit Mode may have opened or closed while the module was off; the
        -- plate pass below repaints.
        private.AuraColors.SetEditMode(EditModeManagerFrame:IsEditModeActive(), false)
        self.auraSpellsListening = true
    elseif self.auraSpellsListening then
        for _, event in ipairs(AURA_CONFIG_EVENTS) do self.context:RemoveEvent(event) end
        self.auraSpellsListening = nil
    end
    EachPlate(ApplyPlate)
    AfterClassify(self)
    Power.Refresh()
end

function M:Disable()
    CancelQuestRefresh(self)
    self.active = false
    self.auraSpellsListening = nil
    Power.Disable()
    Threat.Disable()
    self.rarityBefore = nil
    self.infoTextApplied = nil
    Layout.RestoreAll()
    self.targetUF, self.focusUF = nil, nil
    Roles.ClearQuest()
    for unit, uf in pairs(self.activeUnits) do
        RestorePlate(uf)
        self.activeUnits[unit] = nil
    end
    for _, visual in pairs(self.visuals) do
        HideVisual(visual)
    end
    Level.RestoreNative()
    Auras.Restore()
    KickReady.Disable()
end

Layout.Bind(M)
Text.Bind(M)
Level.Bind(M)
CastTime.Bind(M)
KickReady.Bind(M, RepaintCasts)
Auras.Bind(M)
private.AuraColors.Bind(M, RepaintAuraColors)
S.Install("nameplates", M)
