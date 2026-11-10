local root = assert(arg[1])
local combat, object, cursor, related = false, true, 1, false
local inReach, plateAvailable, dead = false, true, false
local cvars = { SoftTargetInteractOnlyInRange = "1", SoftTargetIconGameObject = "0", SoftTargetInteractArc = "0",
    outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2", raidGraphicsOutlineMode = "1" }
local savedBefore, tooltip = {}, nil
local cursorReads, tooltipReads = 0, 0
local hasCursor = true
local writes, events, created = {}, {}, 0
local timers, nativeWrites, animationStarts = {}, 0, 0
local function Region()
    created = created + 1
    local r = { shown = false }
    function r:Hide() self.shown = false end
    function r:Show() self.shown = true end
    function r:IsShown() return self.shown end
    function r:SetTexture(v) self.texture = v end
    function r:GetTexture() return self.texture end
    function r:SetPoint(...) self.point = {...} end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetAlpha(v) self.alpha = v end
    function r:SetScale(v) self.scale = v end
    function r:SetFrameStrata(v) self.strata = v end
    function r:ClearAllPoints() self.point = nil end
    function r:CreateAnimationGroup()
        local a = {}
        function a:SetLooping() end
        function a:Play() animationStarts = animationStarts + 1; self.playing = true end
        function a:Stop() self.playing = false end
        function a:CreateAnimation()
            return { SetFromAlpha = function() end, SetToAlpha = function() end, SetDuration = function() end,
                SetOrder = function() end, SetStartDelay = function() end, SetOffset = function() end }
        end
        return a
    end
    for _, key in ipairs({"EnableMouse", "SetBlendMode", "SetAllPoints", "SetColorTexture",
        "SetRotation", "SetVertexColor"}) do r[key] = function() end end
    for key, method in pairs(r) do
        if key:match("^Set") or key == "Show" or key == "Hide" or key == "ClearAllPoints" then
            local native = method
            r[key] = function(...)
                nativeWrites = nativeWrites + 1
                return native(...)
            end
        end
    end
    return r
end
UIParent = Region()
local secret = {}
local plate = setmetatable({ IsForbidden = function() return false end },
    { __newindex = function() error("native frame write") end })
C_NamePlate = { GetNamePlateForUnit = function()
    if plateAvailable and (inReach or cvars.SoftTargetInteractOnlyInRange == "0") then return plate end
end }
-- World objects do not need to exist as normal units (native CompactUnitFrame_UpdateVisible).
UnitExists = function() return false end
UNIT_SKINNABLE_LEATHER = "Kürschnerbar"
UnitIsGameObject = function() return object end
UnitIsDead = function(unit)
    assert(unit == "softinteract")
    return dead
end
SetUnitCursorTexture = function(texture, unit, _, includeLowPriority)
    assert(unit == "softinteract" and includeLowPriority, "object probe omitted low-priority cursors")
    cursorReads = cursorReads + 1
    texture.texture = cursor
    return hasCursor
end
GetFileIDFromPath = function(path)
    if path:find("Mine", 1, true) then return 1 end
    if path:find("GatherHerbs", 1, true) then return 2 end
    if path == "Interface\\Cursor\\Skin.blp" then return 4 end
    if path == "Interface\\Cursor\\UnableSkinAlliance" then return 5 end
    if path:find("Skin", 1, true) then return 0 end
    return 3
end
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return related end }
Enum = { TooltipDataLineType = { QuestObjective = 8 } }
C_TooltipInfo = { GetUnit = function(unit)
    assert(unit == "softinteract")
    tooltipReads = tooltipReads + 1
    return tooltip
end }
C_CVar = { GetCVar = function(key) return cvars[key] end }
local module
local S = { CreateFrame = Region, CreateTexture = Region, Public = function(v) return v ~= secret end,
    Finite = function(v) return type(v) == "number" end, RGB = function() return 1, .8, .2 end,
    GamepadUI = function() return false end, InstanceKind = function() return "world" end,
    RestoreCVar = function(_, key)
        if savedBefore[key] ~= nil then cvars[key] = savedBefore[key]; savedBefore[key] = nil end
    end,
    Install = function(_, value) module = value end }
local P = { Suite = S, NS = { InCombat = function(event) return combat or event == "PLAYER_REGEN_DISABLED" end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GlimmerVisuals.lua"))("test", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Glimmer.lua"))("test", P)
module.active = true
module.config = { ore = true, herb = true, quest = true, other = false, hideInstances = true,
    skinning = true, range = 15, style = 1, size = 80, opacity = 85, color = "ffd166", offsetY = -20, pulse = true }
module.context = { Event = function(_, key, callback) events[key] = callback end,
    RemoveEvent = function(_, key) events[key] = nil end,
    After = function(_, delay, callback) assert(delay == 1 or delay == 0.1); timers[callback] = true end,
    Cancel = function(_, callback) timers[callback] = nil end,
    CVar = function(_, key, value, adoptCurrent)
        writes[#writes + 1] = {key, value}
        if savedBefore[key] == nil or adoptCurrent then savedBefore[key] = cvars[key] end
        cvars[key] = tostring(value)
        if events.CVAR_UPDATE then events.CVAR_UPDATE(module, "CVAR_UPDATE", key) end
        return true
    end }
module:Enable()
assert(module.host.shown and module.host.point[2] == plate,
    "game-object ore was rejected while UnitExists is false or before direct interaction range")
assert(#writes == 7 and cvars.SoftTargetInteractOnlyInRange == "0" and cvars.SoftTargetInteractArc == "2",
    "native object range or camera selection was not configured")
assert(module.host.strata == "BACKGROUND", "world glimmer renders above ordinary UI windows")
local baseline = created
local tooltipBaseline = tooltipReads
local nativeBaseline, startsBaseline = nativeWrites, animationStarts
for i = 1, 20 do events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED") end
assert(created == baseline and #writes == 7, "events allocate surfaces or rewrite CVars")
assert(tooltipReads == tooltipBaseline, "recognized gathering targets queried tooltip data")
assert(nativeWrites == nativeBaseline and animationStarts == startsBaseline,
    "unchanged events repainted the effect or restarted its animation")
assert(cvars.outlineModeShowLootEffectWhenDisabled == "1" and cvars.graphicsOutlineMode == "2"
    and cvars.raidGraphicsOutlineMode == "1", "native quest sparkle changed the player's outline settings")
-- Budget the event/classification path independently of the unchanged renderer.
-- Native tooltip tables are requested only for the new unknown-object fallback.
-- Measured 2026-11-05: 101 instructions/event, zero Lua KB; 2% VM headroom.
local liveShow = P.GlimmerVisuals.Show
local budgetCursorReads = cursorReads
P.GlimmerVisuals.Show = function() end
local handler = events.PLAYER_SOFT_INTERACT_CHANGED
local function Burst()
    for _ = 1, 100 do handler(module, "PLAYER_SOFT_INTERACT_CHANGED") end
end
Burst()
local source = debug.getinfo(handler, "S").source
local instructions = 0
debug.sethook(function()
    if debug.getinfo(2, "S").source == source then instructions = instructions + 1 end
end, "", 1)
Burst()
debug.sethook()
local minimumKB = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local beforeKB = collectgarbage("count")
    Burst()
    local used = collectgarbage("count") - beforeKB
    collectgarbage("restart")
    minimumKB = math.min(minimumKB, used)
end
P.GlimmerVisuals.Show = liveShow
assert(instructions <= 103 * 100, "known-object event instruction budget grew")
assert(minimumKB <= .01, "known-object events allocated Lua data")
assert(cursorReads - budgetCursorReads == 400 and tooltipReads == tooltipBaseline,
    "known-object events repeated native cursor reads or queried tooltip data")
print(string.format("glimmer known-object budget: %.0f instructions/event, %.3f KB/100 events", instructions / 100, minimumKB))
cursor = 2
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(module.host.shown, "herb hidden")
module.config.herb = false
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "category toggle ignored")
cursor, related = 20, true
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(module.host.shown, "quest object hidden while UnitExists is false")
-- The native plate may arrive after the target-change event.
plateAvailable = false
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown and module.host.point == nil, "missing anchor retained its effect")
plateAvailable = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.host.shown and module.host.point[2] == plate, "late game-object plate never acquired its effect")
-- File names and the game's newer cursor names also identify quest/gather objects.
related = false
for _, texture in ipairs({ "Interface\\Cursor\\QuestTurnIn", "Cursor Crosshair_ImportantQuest_64",
    "Cursor Crosshair_Recurring_64", "Cursor Crosshair_Wrapper_64" }) do
    cursor = texture
    events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
    assert(module.host.shown, "quest cursor name did not select the quest effect: " .. texture)
end
module.config.herb = true
cursor = "Interface\\Cursor\\UnableGatherHerbs"
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(module.host.shown, "herb cursor filename was not recognized")
-- Some quest orbs/objects only report their objective through the native tooltip.
cursor, hasCursor = nil, false
tooltip = { lines = { { type = 0 }, { type = Enum.TooltipDataLineType.QuestObjective } } }
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(module.host.shown, "tooltip-only quest object was not highlighted")
module.config.quest = false
local reads = tooltipReads
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(not module.host.shown and tooltipReads == reads, "disabled quest category still read its tooltip")
module.config.quest = true
for _, data in ipairs({ secret, { lines = secret }, { lines = { secret } }, { lines = { { type = secret } } } }) do
    tooltip = data
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(not module.host.shown, "private tooltip data selected a quest effect")
end
tooltip, hasCursor = nil, true
cursor = 20
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(not module.host.shown, "unrelated interactable object bypassed its disabled category")
module.config.other = true
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(module.host.shown, "other interactable object switch stopped working")
module.config.other = false
object = secret
reads = cursorReads
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown and cursorReads == reads, "private object state reached the cursor probe")
object, cursor = false, 4
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "living unit highlighted as a skinnable corpse")
dead, cursor = true, 20
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "ordinary loot cursor highlighted as a skinnable corpse")
cursor = 4
events.LOOT_CLOSED(module, "LOOT_CLOSED")
assert(module.host.shown and module.host.point[2] == plate, "looting did not reveal the now skinnable corpse")
for _, texture in ipairs({ 5, "Interface\\Cursor\\SkinHorde.blp", "UnableSkin", "Cursor Skin",
    "Cursor UnableSkin", "Cursor Crosshair_Skin_64", "Crosshair_UnableSkin_64" }) do
    cursor = texture
    events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
    assert(module.host.shown, "skinning cursor variant was not recognized")
end
for _, texture in ipairs({ "Interface\\Cursor\\EngineerSkin.blp", secret }) do
    cursor = texture
    events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
    assert(not module.host.shown, "a non-skinning or private cursor highlighted a corpse")
end
cursor, dead = 4, secret
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "private death state highlighted a corpse")
dead = true
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(module.host.shown, "skinning cursor did not highlight a dead unit")
module.config.skinning = false
module:Refresh()
assert(not module.host.shown and not events.LOOT_CLOSED, "turning off skinning left its effect or loot listener active")
reads = cursorReads
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(cursorReads == reads, "disabled skinning still probed the corpse")
module.config.skinning = true
module:Refresh()
assert(module.host.shown and events.LOOT_CLOSED, "re-enabling skinning did not restore the effect and loot listener")
cursor, hasCursor = 20, false
events.LOOT_CLOSED(module, "LOOT_CLOSED")
assert(not module.host.shown, "ordinary corpse without a skinning tooltip was highlighted")
local retryLoot = assert(next(timers), "loot close did not schedule a deferred corpse refresh")
tooltip = { lines = { { leftText = "|cffff2020" .. UNIT_SKINNABLE_LEATHER .. "|r" } } }
timers[retryLoot] = nil
retryLoot(module)
assert(module.host.shown, "localized skinning tooltip did not reveal the corpse without a cursor")
do
    local label = UNIT_SKINNABLE_LEATHER
    UNIT_SKINNABLE_LEATHER, tooltip = nil, { lines = { {} } }
    events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
    assert(not module.host.shown, "missing localized text matched an empty tooltip line")
    UNIT_SKINNABLE_LEATHER = label
end
tooltip = { lines = { { leftText = secret } } }
events.LOOT_CLOSED(module, "LOOT_CLOSED")
assert(not module.host.shown, "private tooltip text left a stale effect")
timers[retryLoot] = nil
retryLoot(module)
tooltip, dead, hasCursor = nil, false, true
object, cursor, related = true, secret, true
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "secret cursor must not select an effect")
cursor, hasCursor = 1, secret
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "private cursor result selected an effect")
hasCursor = true
cursor = 1
for style = 1, 5 do module.config.style = style; module:Refresh(); assert(module.host.shown) end
events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
assert(not module.host.shown and not module.host.pulse.playing, "combat-edge cleanup failed")
assert(cvars.outlineModeShowLootEffectWhenDisabled == "1", "combat removed native quest sparkles")
for _, glint in ipairs(module.host.glints) do assert(not glint.group.playing, "hidden glint kept animating") end
combat = true
local before = #writes
module:Refresh()
assert(#writes == before and module.pending, "combat changed CVars")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(module.host.shown and not module.pending, "deferred refresh lost")
-- Accessibility presets can turn object icons off while the module runs.
cvars.SoftTargetIconGameObject = "0"
events.CVAR_UPDATE(module, "CVAR_UPDATE", "softtargeticongameobject")
assert(cvars.SoftTargetIconGameObject == "1" and module.host.shown, "Accessibility change broke object anchors")
assert(savedBefore.SoftTargetIconGameObject == "0",
    "recovery did not retain the player's latest icon choice")
combat = true
before = #writes
cvars.SoftTargetInteractOnlyInRange = "1"
events.CVAR_UPDATE(module, "CVAR_UPDATE", "SoftTargetInteractOnlyInRange")
assert(#writes == before and module.pending and not module.host.shown, "combat CVar repair did not defer")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(cvars.SoftTargetInteractOnlyInRange == "0" and module.host.shown and not module.pending,
    "object anchor did not recover after combat")
assert(savedBefore.SoftTargetInteractOnlyInRange == "1", "deferred repair lost the player's last range choice")
combat = true
cvars.SoftTargetIconGameObject = "0"
events.CVAR_UPDATE(module, "CVAR_UPDATE", "SoftTargetIconGameObject")
cvars.SoftTargetIconGameObject = "1"
events.CVAR_UPDATE(module, "CVAR_UPDATE", "SoftTargetIconGameObject")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(savedBefore.SoftTargetIconGameObject == "1", "combat flip back lost the latest external choice")
before = #writes
events.CVAR_UPDATE(module, "CVAR_UPDATE", "SoftTargetIconGameObject")
events.CVAR_UPDATE(module, "CVAR_UPDATE", "unrelated")
events.CVAR_UPDATE(module, "CVAR_UPDATE", secret)
assert(#writes == before, "unchanged, unrelated or private CVar event rewrote settings")
-- Graphics presets may reset the engine sparkle after their own delayed work.
cvars.outlineModeShowLootEffectWhenDisabled = "0"
events.CVAR_UPDATE(module, "CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled")
events.CVAR_UPDATE(module, "CVAR_UPDATE", "graphicsQuality")
assert(next(timers) and cvars.outlineModeShowLootEffectWhenDisabled == "0", "sparkle repair did not wait for graphics")
local sparkleRepair = next(timers)
timers[sparkleRepair] = nil
sparkleRepair(module)
assert(cvars.outlineModeShowLootEffectWhenDisabled == "1", "graphics preset disabled native sparkles")
for _, preset in ipairs({ "graphicsQuality", "raidGraphicsQuality" }) do
    events.CVAR_UPDATE(module, "CVAR_UPDATE", preset)
    assert(timers[sparkleRepair], "graphics preset did not schedule the shared sparkle repair")
    timers[sparkleRepair] = nil
    sparkleRepair(module)
end
combat = true
cvars.outlineModeShowLootEffectWhenDisabled = "0"
events.CVAR_UPDATE(module, "CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled")
timers[sparkleRepair] = nil
sparkleRepair(module)
assert(module.pendingSparkle and cvars.outlineModeShowLootEffectWhenDisabled == "0", "combat sparkle repair wrote a CVar")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(not module.pendingSparkle and cvars.outlineModeShowLootEffectWhenDisabled == "1", "sparkle repair lost combat replay")
module.config.questSparkle = false
module:Refresh()
assert(not next(timers) and cvars.outlineModeShowLootEffectWhenDisabled == "0", "disabling native sparkle did not restore it")
module.config.questSparkle = true
module:Refresh()
-- Native mapping still exists during the removal event. An unrelated
-- removal cannot hide this overlay, while the current plate must release.
local getPlate=C_NamePlate.GetNamePlateForUnit
C_NamePlate.GetNamePlateForUnit=function(unit) if unit=="nameplate2" then return {} end return plate end
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate2")
assert(module.host.shown, "unrelated removal hid the interact target")
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not module.host.shown and module.host.point==nil, "removed native anchor retained")
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(not module.host.shown, "removed anchor was reacquired before being added")
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.host.shown, "reused plate did not resume the overlay")
C_NamePlate.GetNamePlateForUnit=getPlate
object = false
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not module.host.shown, "stale target effect")
-- A queued disable can run before this module's combat-end event.
for _, key in ipairs({ "SoftTargetIconGameObject", "SoftTargetInteractOnlyInRange" }) do
    local wanted = key == "SoftTargetIconGameObject" and "1" or "0"
    local alternate = wanted == "1" and "0" or "1"
    for _, choice in ipairs({ alternate, wanted }) do
        module:Enable()
        combat = true
        cvars[key] = alternate
        events.CVAR_UPDATE(module, "CVAR_UPDATE", key)
        cvars[key] = choice
        events.CVAR_UPDATE(module, "CVAR_UPDATE", key)
        combat = false
        module:Disable()
        assert(savedBefore[key] == choice and cvars[key] == choice,
            "disable before module regen lost the external choice: " .. key)
        assert(not next(module.changedCVars) and not module.pending and not next(timers), "disable retained pending CVar changes")
    end
end
module:Disable()
assert(not module.host.shown and not module.host.pulse.playing, "disable retained effect")
-- The menu preview uses separate owned surfaces and the exact live painter.
local preview = Region()
local worldPoint = module.host.point
local cvars = #writes
local sample = S.DrawGlimmerPreview(preview, module.config, {}, { width=220, height=190, scale=1 })
assert(sample ~= module.host and sample.effect ~= module.host, "preview reused the live host")
assert(sample.sample.texture == "Interface\\Cursor\\GatherHerbs", "preview has no object sample")
local createdPreview = created
for style = 1, 5 do
    module.config.style = style
    local again = S.DrawGlimmerPreview(preview, module.config, {}, { width=220, height=190, scale=1 })
    assert(again == sample and created == createdPreview, "preview recreated its effect")
    assert(sample.effect.width == module.config.size and sample.effect.alpha == module.config.opacity/100)
    assert(sample.effect.pulse.playing, "preview pulse is not active")
end
assert(#writes == cvars and module.host.point == worldPoint, "preview changed live state or CVars")
S.HideGlimmerPreview(preview)
assert(not sample.shown and not sample.effect.shown and not sample.effect.pulse.playing and not sample.effect.point,
    "hidden preview retained its animation or anchor")
print("suite_glimmer_contract: ok")
