local _, private = ...
local NS, S = private.NS, private.Suite
local Mode, Key, RoleKey = private.Mode, private.Key, private.RoleKey
local LOOK_BLIZZARD = Mode.LOOK_BLIZZARD
local Style = NS.NameplateStyle
local Gradient = Style.Gradient
local outlineSizes = {}
local Layout, Roles, Text, Power, Threat = private.Layout, private.Roles, private.Text, private.Power, private.Threat
local Level, CastTime, CVars, Auras, Status = private.Level, private.CastTime, private.CVars, private.Auras, private.Status
local KickReady, Selection, AuraColors = private.KickReady, private.Selection, private.AuraColors
local Decor, Mouseover, Names = private.Decor, private.Mouseover, private.FriendlyNames
local FilterFriendlyName, RestoreFriendlyName = Names.Filter, Names.Restore
local NameText = private.NameText
local AuraDisplay, Extensions = private.AuraDisplay, private.Extensions
local Textures = private.Textures
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
    castTimes = setmetatable({}, { __mode = "k" }),
    kicks = setmetatable({}, { __mode = "k" }),
    levelLabels = setmetatable({}, { __mode = "k" }),
    nativeLevelAlphas = setmetatable({}, { __mode = "k" }),
    -- Unit frames whose plate a write held back (Layout, Level, CastTime,
    -- Auras): the end of combat applies those plates again.
    pendingPlates = setmetatable({}, { __mode = "k" }),
}

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local RestorePlateFonts = private.HealthAppearance.RestoreFonts

-- The color overlay follows Blizzard's filled StatusBar texture. No health,
-- cast progress or aura value is read or cached by this module.
local function Visual(bar, markerOwner)
    local visual = M.visuals[bar]
    if visual then return visual end
    visual = Style.CreateBorder(bar)
    visual.back = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    visual.back:SetAllPoints(bar)
    visual.back:Hide()
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

local function ShowVisual(texture, shown)
    if (texture._msufShown == true) == shown then return end
    texture:SetShown(shown)
    texture._msufShown = shown
end

local function HideVisual(visual)
    if not visual then return end
    ShowVisual(visual.back, false)
    ShowVisual(visual.fill, false)
    if visual.gradient then Gradient.Paint(nil, visual.gradient) end
    Style.PaintTarget(visual, nil, false)
    ShowVisual(visual.elite, false)
    ShowVisual(visual.quest, false)
    Style.PaintBorder(visual, nil, 0)
end

local Prefix = private.PlatePrefix
local scopes = private.SkinScopes
local suppressed = scopes.suppressed
local scopedSkins, ApplyAuras = false, Auras.Apply

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
    facts.wantsQuest = quest or color and M.config.enemyQuestColors and M.config.enemyQuestEnabled ~= false
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

local PaintHealth, PaintTarget, PaintFonts = private.HealthAppearance.Bind(M, ShowVisual, outlineSizes, Safe)

local function Paint(uf)
    if not M.active or not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    local prefix, unit = Prefix(uf), M.units[health]
    CastTime.Paint(cast, prefix, unit, uf)
    KickReady.Paint(cast, prefix, unit)
    Threat.Apply(uf)
    Extensions.BeforeNameFilter(uf)
    FilterFriendlyName(uf, prefix)
    if Status.Paint then Status.Paint(uf, prefix, unit) end
    Level.PaintNative(uf, prefix)
    Level.Paint(uf, prefix, unit)
    Layout.Apply(uf, prefix, M.config)
    if Power.enemyEnabled then Power.ApplyEnemy(uf, health, prefix, unit) end
    local styled = prefix and M.config.look ~= LOOK_BLIZZARD and M.config[prefix] == true
    local outline, borderSize, borderColor
    if not styled then
        if M.targetUF == uf then M.targetUF = nil end
        HideVisual(M.visuals[health])
        if Text.shared and prefix and M.config[prefix] then
            PaintFonts(uf, health, cast, prefix)
        else
            RestorePlateFonts(uf, health, cast)
        end
    else
        local visual = Visual(health, uf)
        outline = visual
        borderSize, borderColor = PaintHealth(health, visual, prefix)
        if M.healthGradient or visual.gradient then Gradient.PaintHealth(health, visual, M.healthGradient, uf, M.pendingPlates) end
        PaintTarget(uf, health, visual, prefix)
        PaintFonts(uf, health, cast, prefix)
    end
    if Mouseover.textInUse then Mouseover.Apply(uf, health, prefix, styled) end
    if Selection.inUse then Selection.Apply(health, styled == true, uf, prefix, outline, borderSize, borderColor) end
    if Decor.inUse then Decor.Paint(uf, health, cast, prefix, unit) end
    -- DoT colors are applied after the role tint.
    AuraColors.Apply(uf, unit, prefix == "enemy")
    if NameText.inUse then NameText.Apply(uf, prefix, unit) end
    if M.extras then private.EasyFeatures.Paint(uf, health, cast, prefix, unit, styled, M.roles[health]) end
    AuraDisplay.Apply(uf, unit, prefix == "enemy")
    if Extensions.inUse then Extensions.Apply(uf, health, cast, prefix, unit) end
end

local PaintPlate = Paint
local function PaintTexturedPlate(uf)
    Textures.Paint(uf, PaintPlate)
end
local function PaintFocusAdded(uf) Textures.PaintAdded(uf, PaintPlate) end
local PaintAdded = PaintPlate

local function RestorePlate(uf, keepUnit, recycled)
    if M.extras then private.EasyFeatures.Restore(uf, not keepUnit) end
    if Textures.inUse then Textures.Restore(uf, recycled) end
    if Power.enemyEnabled then Power.RestoreEnemy(uf) end
    if keepUnit then NameText.Suspend(uf) else NameText.Release(uf) end
    AuraDisplay.Restore(uf)
    Extensions.Restore(uf)
    AuraColors.Restore(uf)
    Threat.Restore(uf)
    Mouseover.Restore(uf)
    RestoreFriendlyName(uf.name)
    Level.PaintNative(uf, nil)
    Level.Hide(uf)
    if Status.Restore then Status.Restore(uf) end
    Layout.Restore(uf, recycled)
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    CastTime.Restore(cast)
    KickReady.Restore(cast)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return Text.CancelHealth(health) end
    Decor.Restore(health)
    M.roles[health] = nil
    if not keepUnit then M.units[health] = nil end
    if M.facts[health] then Facts(health) end
    HideVisual(M.visuals[health])
    Selection.Restore(health)
    RestorePlateFonts(uf, health, cast)
end

local SuppressSkin = scopes.Bind(M, RestorePlate)

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
    ApplyAuras(uf)
end

local function EachPlate(callback)
    local plates = C_NamePlate.GetNamePlates()
    for i = 1, #plates do callback(plates[i]) end
end

-- Group/role changes affect facts, colors and name filtering, not presentation
-- (2026-10-26 M+ trace: 60 Paint and 380 Text.Apply in one roster burst).
local function RefreshActive(self, contextOnly, auraColors)
    for unit, uf in pairs(self.activeUnits) do
        if Safe(uf) then
            SetRole(uf, unit)
            local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
            if contextOnly and Safe(health) and not (scopedSkins and not scopes.Allowed(uf, unit) or suppressed[uf]) then
                local prefix = Prefix(uf)
                local visual = health and self.visuals[health]
                local styled = prefix and self.config.look ~= LOOK_BLIZZARD and self.config[prefix]
                if styled and not visual then Paint(uf)
                else
                    FilterFriendlyName(uf, prefix)
                    if styled then PaintHealth(health, visual, prefix) end
                    if auraColors then AuraColors.Apply(uf, unit, prefix == "enemy") end
                end
            elseif not contextOnly or Safe(health) then
                Paint(uf)
            end
        end
    end
    if Roles.learnedLieutenant then
        Roles.learnedLieutenant = false
        RefreshActive(self, contextOnly)
    end
end

-- A lieutenant level seen for the first time in this context can make the
-- plates classified before it bosses: those are classified once more.
local function AfterClassify(self)
    if not Roles.learnedLieutenant then return end
    Roles.learnedLieutenant = false
    RefreshActive(self, true)
end

local ClearQuest, BeginName = Roles.ClearQuest, NameText.Begin
local function OnAdded(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    ClearQuest(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local uf = Safe(plate) and plate.UnitFrame
    if not Safe(uf) then return end
    CoverPlate(uf)
    self.activeUnits[unit] = uf
    BeginName(uf)
    SetRole(uf, unit)
    if self.extras then private.EasyFeatures.Added() end
    PaintAdded(uf)
    ApplyAuras(uf)
    if Roles.learnedLieutenant then AfterClassify(self) end
end

local function OnRemoved(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = self.activeUnits[unit]
    self.activeUnits[unit] = nil
    Roles.ClearQuest(unit)
    if self.targetUF == uf then self.targetUF = nil end
    if self.focusUF == uf then self.focusUF = nil end
    if uf then
        suppressed[uf] = nil
        scopes.RestoreVisibility(uf)
        -- ClearUnit runs before the driver releases the pooled frame. If
        -- the frame still has a unit, perform the full visible rollback.
        local nativeUnit = Safe(uf) and uf.unit
        RestorePlate(uf, nil, S.Public(nativeUnit) and nativeUnit == nil)
    end
end

local function RefreshRole(uf)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local prefix = Prefix(uf)
    local visual = health and M.visuals[health]
    if not Safe(health) or not prefix or not visual or M.config.look == LOOK_BLIZZARD or not M.config[prefix]
        or scopedSkins and suppressed[uf] then
        Paint(uf)
        return
    end
    PaintHealth(health, visual, prefix)
    if M.extras then private.EasyFeatures.Role(uf, M.roles[health]) end
end

local function RefreshTarget(uf)
    if not Safe(uf) then return end
    if scopedSkins and suppressed[uf] then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local prefix = Prefix(uf)
    local visual = health and M.visuals[health]
    if not Safe(health) or not prefix or not visual or M.config.look == LOOK_BLIZZARD or not M.config[prefix] then
        Paint(uf)
        return
    end
    PaintTarget(uf, health, visual, prefix)
    if Decor.inUse then
        Decor.Paint(uf, health, uf.CastBarsContainer and uf.CastBarsContainer.castBar, prefix, M.units[health])
    end
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
    if Extensions.usesMetadata then Extensions.OnMetadata() end
    if not module.usesQuests then return end
    Roles.ClearQuest()
    if not Roles.inInstance and next(module.activeUnits) then module.questJob:Request() end
end

local function OnTargetChanged(self)
    if self.extras then private.EasyFeatures.Selection("target") end
    Extensions.OnSelection()
    local previous = self.targetUF
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local current = Safe(plate) and plate.UnitFrame
    if self.config.auraDisplayEnabled then AuraDisplay.TargetChanged(current) end
    if Decor.inUse then Decor.TargetChanged(current) end
    if Safe(previous) then RefreshTarget(previous) end
    if Safe(current) and current ~= previous then RefreshTarget(current) end
end

-- Faction changes repaint the plate. Level, classification and power display
-- refresh facts, flags refresh the base role, and threat checks only threat rules.
local FACT_EVENTS = { UNIT_LEVEL = true, UNIT_CLASSIFICATION_CHANGED = true, UNIT_DISPLAYPOWER = true }

-- The skin and extensions both need a mapping in activeUnits.
local function OnUnitChanged(module, event, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = module.activeUnits[unit]
    if not uf then return end
    if Extensions.inUse then Extensions.OnUnit(module, event, unit) end
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
        if event == "UNIT_DISPLAYPOWER" and Power.enemyEnabled then Power.EnemyResourceChanged(uf, unit) end
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


local function OnScopedUnitChanged(module, event, unit)
    if S.Public(unit) and type(unit) == "string" then
        local uf = module.activeUnits[unit]
        if Safe(uf) then
            if not scopes.Allowed(uf, unit) then return SuppressSkin(uf) end
            if suppressed[uf] then
                SetRole(uf, unit)
                Paint(uf)
                return
            end
        end
    end
    OnUnitChanged(module, event, unit)
end

local function RepaintAuraColors(module)
    for unit, uf in pairs(module.activeUnits) do
        if not suppressed[uf] then
            local enemy = Prefix(uf) == "enemy"
            AuraColors.Apply(uf, unit, enemy)
            AuraDisplay.Apply(uf, unit, enemy)
        end
    end
end

-- World/area/level changes can reset native level badges and geometry. Keep
-- their full pass; subzone steps take it only when the role context changed.
local FULL_CONTEXT = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_LEVEL_UP = true, ZONE_CHANGED = true }
local function OnContextChanged(module, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        AuraColors.Configure(module.config, true)
        AuraDisplay.Configure(module.config, true)
    end
    local changed = Roles.RefreshContext()
    Extensions.OnContext(changed, event)
    if event == "ZONE_CHANGED" and not changed then return end
    CancelQuestRefresh(module)
    Roles.ClearQuest()
    RefreshActive(module, not FULL_CONTEXT[event], event == "PLAYER_SPECIALIZATION_CHANGED")
    -- A specialization brings other interrupt spells: casts that already run
    -- take the kick-ready look again (KickReady.Paint).
    if event == "PLAYER_SPECIALIZATION_CHANGED" then CastTime.Repaint() end
end

local function OnFocusChanged(module)
    if module.extras then private.EasyFeatures.Selection("focus") end
    Extensions.OnSelection()
    local plate = C_NamePlate.GetNamePlateForUnit("focus")
    local current = Safe(plate) and plate.UnitFrame or nil
    if not Safe(current) then current = nil end
    Textures.RefreshFocus(module, current, SetRole, Paint)
    module.focusUF = current
end

-- Observe Blizzard's font reset. Never call frame setup ourselves.
local function OnFrameOptions(uf)
    if not M.active then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not health or not M.units[health] then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    Text.Invalidate(uf.name)
    if NameText.inUse then NameText.Invalidate(uf) end
    Text.Invalidate(health.Text)
    Text.Invalidate(health.LeftText)
    Text.Invalidate(health.RightText)
    if cast then
        Text.Invalidate(cast.Text)
        Text.Invalidate(cast.CastTargetNameText)
    end
    Paint(uf)
end

-- The shown plates whose unit frame a held-back write named, in Blizzard's
-- plate order. The set empties before the pass, so a write the pass itself
-- has to hold back waits for the next end of combat.
local due = {}
local function ApplyPending(pending)
    local plates, count = C_NamePlate.GetNamePlates(), 0
    for i = 1, #plates do
        local plate = plates[i]
        if Safe(plate) and pending[plate.UnitFrame] then
            count = count + 1
            due[count] = plate
        end
    end
    for uf in pairs(pending) do pending[uf] = nil end
    for i = 1, count do
        local plate = due[i]
        if suppressed[plate.UnitFrame] then suppressed[plate.UnitFrame] = nil end
        if not scopedSkins then scopes.RestoreVisibility(plate.UnitFrame) end
        ApplyPlate(plate)
        due[i] = nil
    end
end

-- Only the plates a write held back are applied again; the others are current
-- (2026-10-11 raid trace: a module-wide flag repainted every shown plate).
-- Quests to read again (Roles.RetryQuests) still take every plate.
local function OnCombatEnded(module)
    Extensions.OnCombatEnded()
    Status.Flush()
    AuraDisplay.Resume()
    NS.SyncFriendlyNameplates(module)
    -- CVar writes held back for combat (CVars.Apply).
    if module.cvarsPending then CVars.Apply(module) end
    NameText.FlushRestores()
    local retryQuests = Roles.RetryQuests()
    local pending = module.pendingPlates
    if not next(pending) then
        if retryQuests then
            CancelQuestRefresh(module)
            RefreshActive(module)
        end
        return
    end
    if retryQuests then
        for uf in pairs(pending) do pending[uf] = nil end
        EachPlate(ApplyPlate)
    elseif next(pending) then
        ApplyPending(pending)
    end
end

local UNIT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
    "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL", "UNIT_DISPLAYPOWER" }
local CONTEXT_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
    "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED" }
local AURA_CONFIG_EVENTS = { "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" }

local function OnAuraSpellsChanged(module)
    if Extensions.usesRange then Extensions.RangeSpellChanged() end
    if not module.auraSpellsListening then return end
    AuraColors.Configure(module.config, true)
    AuraDisplay.Configure(module.config, true)
    RepaintAuraColors(module)
end

-- Blizzard's Edit Mode feeds aura containers sample auras: on 12.1.0 the DoT
-- colors hide while it is open (AuraColors.SetEditMode).
local function OnEditModeEnter()
    AuraDisplay.SetEditMode(true)
    AuraColors.SetEditMode(true)
    RepaintAuraColors(M)
end
local function OnEditModeExit()
    AuraDisplay.SetEditMode(false)
    AuraColors.SetEditMode(false)
    RepaintAuraColors(M)
end

-- Every plate listener also runs in combat (the context's allowCombat, kept
-- explicit should the module ever move frames itself): restyling a native
-- plate is not protected, and each handler checks combat where it matters.
local function Listen(self, event, callback)
    self.context:Event(event, callback, IN_COMBAT)
end

local function RefreshAggro(module, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = module.activeUnits[unit]
    if not uf and (unit == "target" or unit == "focus") then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        uf = Safe(plate) and plate.UnitFrame
        if Safe(uf) then unit = uf.unit end
    end
    if Safe(uf) and not suppressed[uf] then
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        if Safe(health) then Selection.ThreatChanged(health, unit) end
    end
end

local function OnHighlightThreat(module, event, unit)
    local neutralEvent = event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_FLAGS"
    local handler = neutralEvent and module.neutralHandler or module.unitEvents
    handler(module, event, unit)
    if event == "UNIT_THREAT_SITUATION_UPDATE" and S.Public(unit) and unit == "player" then
        RefreshAggro(module, "target")
        RefreshAggro(module, "focus")
        return
    end
    RefreshAggro(module, unit)
end

function M:OnAggroTargetChanged(unit)
    if self.active and Selection.aggroEnabled then RefreshAggro(self, unit) end
end

function M:AggroHighlightSettingChanged()
    local config = self.config
    return not config.highlightAggroOverride and config.look ~= LOOK_BLIZZARD and config.enemy == true
        and Selection.aggroEnabled ~= Style.AggroHighlightEnabled(config)
end

local function ConfigureUnitEvents(module)
    local handler = scopedSkins and OnScopedUnitChanged or OnUnitChanged
    local neutral, aggro = Extensions.NeutralHandler(module.config), Selection.aggroEnabled
    if handler == module.unitEvents and neutral == module.neutralHandler and aggro == module.aggroEvents then return end
    module.unitEvents, module.neutralHandler, module.aggroEvents = handler, neutral, aggro
    for _, event in ipairs(UNIT_EVENTS) do
        local callback = handler
        if event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_FLAGS" then
            callback = aggro and OnHighlightThreat or neutral or handler
        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            callback = aggro and OnHighlightThreat or handler
        end
        Listen(module, event, callback)
    end
end

function M:Enable()
    self.questJob = self.context:Coalesce(QUEST_DELAY, QuestPass)
    Textures.ObserveHostStyles(self)
    if not self.fontHook then
        self.fontHook = true
        private.HookPlates("ApplyFrameOptions", OnFrameOptions)
    end
    Listen(self, "NAME_PLATE_UNIT_ADDED", OnAdded)
    Listen(self, "NAME_PLATE_UNIT_REMOVED", OnRemoved)
    Listen(self, "PLAYER_TARGET_CHANGED", OnTargetChanged)
    Listen(self, "PLAYER_FOCUS_CHANGED", OnFocusChanged)
    self.unitEvents, self.castListening, self.questListening = nil, nil, nil
    for _, event in ipairs(CONTEXT_EVENTS) do Listen(self, event, OnContextChanged) end
    Listen(self, "PLAYER_REGEN_ENABLED", OnCombatEnded)
    Listen(self, "CVAR_UPDATE", NS.SyncFriendlyNameplates)
    Power.Enable(self)
    Threat.Enable(self)
    self:Refresh()
end

function M:Refresh()
    CancelQuestRefresh(self)
    local c = self.config
    local bars = Style.BarSettings(c, not c.barsOverride and Style.SharedBars())
    self.barSettings = bars
    self.castbarStyle = Textures.SharedCastbar(c, self.castbarStyle)
    self.healthGradient = Gradient and Gradient.Plan(bars, "health", self.healthGradient)
    outlineSizes.enemy = Style.OutlineSize(bars.enemyOutlineMode, bars.enemyBorderEnabled, bars.enemyBorderSize, bars.hideHealthBarBorders)
    outlineSizes.friendly = Style.OutlineSize(bars.friendlyOutlineMode, bars.friendlyBorderEnabled, bars.friendlyBorderSize, bars.hideHealthBarBorders)
    scopedSkins, ApplyAuras = scopes.Configure()
    local repaintTextures = Textures.Configure(bars, self.castbarStyle)
    Textures.PrepareFocus()
    Paint = Textures.inUse and PaintTexturedPlate or PaintPlate
    PaintAdded = Textures.focusFill and PaintFocusAdded or Paint
    if scopedSkins then
        PaintAdded = scopes.Wrap(PaintAdded)
        Paint = scopes.Wrap(Paint)
    end
    Decor.Configure(self)
    Layout.Configure(self.config)
    Roles.Configure(self.config)
    Text.Configure(self.config, self.castbarStyle)
    NameText.Configure(self.config)
    self.targetConfig = Style.TargetConfig(self.config, bars)
    self.friendlyTargetConfig = Style.TargetConfig(self.config, bars, "friendly")
    Power.ConfigureEnemy()
    Auras.Configure(c)
    CVars.Apply(self)
    Threat.Refresh()
    KickReady.Configure()
    Selection.Configure(bars)
    if private.EasyFeatures then private.EasyFeatures.Configure(self) end
    self.extras = private.EasyFeatures and private.EasyFeatures.enabled
    Mouseover.Configure()
    AuraColors.Configure(self.config)
    AuraDisplay.Configure(self.config)
    Status.Configure(self)
    Extensions.Configure(self)
    CastTime.SyncEvents(self)
    Roles.SyncQuestEvents(self, OnQuestLogChanged, Extensions.usesMetadata)
    ConfigureUnitEvents(self)
    local auraListeners = self.config.auraColorsEnabled or NS.NameplateAuraDisplay.Active(self.config)
    for _, event in ipairs(AURA_CONFIG_EVENTS) do
        if auraListeners or Extensions.usesRange and (event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED"
            or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED") then
            Listen(self, event, OnAuraSpellsChanged)
        elseif self.auraSpellsListening or self.rangeSpellsListening then
            self.context:RemoveEvent(event)
        end
    end
    self.rangeSpellsListening = Extensions.usesRange
    if auraListeners then
        self.context:Callback("EditMode.Enter", OnEditModeEnter)
        self.context:Callback("EditMode.Exit", OnEditModeExit)
        -- Reconcile Edit Mode state in case it changed while the module was off.
        AuraColors.SetEditMode(EditModeManagerFrame:IsEditModeActive(), false)
        AuraDisplay.SetEditMode(EditModeManagerFrame:IsEditModeActive())
        self.auraSpellsListening = true
    elseif self.auraSpellsListening then
        self.context:RemoveCallback("EditMode.Enter")
        self.context:RemoveCallback("EditMode.Exit")
        self.auraSpellsListening = nil
    end
    EachPlate(ApplyPlate)
    if repaintTextures then Textures.RestoreAll() end
    Status.EndRefresh()
    AfterClassify(self)
end

function M:ResetCVarBaseline()
    self.rarityBefore = nil
    self.infoTextApplied = nil
    self.flagsBefore = nil
end

function M:Disable()
    CancelQuestRefresh(self)
    self.active = false
    self.friendlyVisibility, self.friendlyVisibilityPending, self.friendlyVisibilityWriting, self.friendlyNpcNamesOnly = nil, nil, nil, nil
    if private.EasyFeatures then private.EasyFeatures.Configure(self) end
    self.castbarStyle = nil
    scopes.Disable()
    scopedSkins = nil
    if Textures.Configure({}) then Textures.RestoreAll() end
    Textures.PrepareFocus()
    Paint, PaintAdded = PaintPlate, PaintPlate
    Extensions.Disable()
    AuraDisplay.Release()
    self.auraSpellsListening, self.rangeSpellsListening = nil, nil
    Decor.Disable()
    Power.Disable()
    Threat.Disable()
    self:ResetCVarBaseline()
    Layout.RestoreAll()
    self.targetUF, self.focusUF = nil, nil
    Roles.ClearQuest()
    for unit, uf in pairs(self.activeUnits) do
        suppressed[uf] = nil
        scopes.RestoreVisibility(uf)
        RestorePlate(uf)
        self.activeUnits[unit] = nil
    end
    for _, visual in pairs(self.visuals) do
        HideVisual(visual)
    end
    Status.Disable()
    Level.RestoreNative()
    Auras.Restore()
    KickReady.Disable()
    Mouseover.Disable()
    Selection.RestoreAll()
end

Layout.Bind(M)
Textures.Bind(M.visuals)
Text.Bind(M)
NameText.Bind(M)
Level.Bind(M)
CastTime.Bind(M)
KickReady.Bind(M, CastTime.Repaint)
Selection.Bind(M)
Mouseover.Bind(M)
Names.Bind(M)
Auras.Bind(M)
AuraColors.Bind(M, RepaintAuraColors)
AuraDisplay.Bind(M, RepaintAuraColors, Listen)
Extensions.Bind(M)
S.Install("nameplates", M)
