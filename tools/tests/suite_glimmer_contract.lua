local root = assert(arg[1])
local combat, exists, object, cursor, related = false, true, true, 1, false
local writes, events, created = {}, {}, 0
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
    function r:ClearAllPoints() self.point = nil end
    function r:CreateAnimationGroup()
        local a = {}
        function a:SetLooping() end
        function a:Play() self.playing = true end
        function a:Stop() self.playing = false end
        function a:CreateAnimation()
            return { SetFromAlpha = function() end, SetToAlpha = function() end, SetDuration = function() end }
        end
        return a
    end
    for _, key in ipairs({"EnableMouse", "SetFrameStrata", "SetBlendMode", "SetAllPoints", "SetColorTexture",
        "SetRotation", "SetVertexColor"}) do r[key] = function() end end
    return r
end
UIParent = Region()
local secret = {}
local plate = setmetatable({ IsForbidden = function() return false end },
    { __newindex = function() error("native frame write") end })
C_NamePlate = { GetNamePlateForUnit = function() return plate end }
UnitExists = function() return exists end
UnitIsGameObject = function() return object end
SetUnitCursorTexture = function(texture) texture.texture = cursor; return true end
GetFileIDFromPath = function(path)
    if path:find("Mine", 1, true) then return 1 end
    if path:find("GatherHerbs", 1, true) then return 2 end
    return 3
end
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return related end }
local module
local S = { CreateFrame = Region, CreateTexture = Region, Public = function(v) return v ~= secret end,
    Finite = function(v) return type(v) == "number" end, RGB = function() return 1, .8, .2 end,
    GamepadUI = function() return false end, InstanceKind = function() return "world" end,
    Install = function(_, value) module = value end }
local P = { Suite = S, NS = { InCombat = function(event) return combat or event == "PLAYER_REGEN_DISABLED" end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GlimmerVisuals.lua"))("test", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Glimmer.lua"))("test", P)
module.active = true
module.config = { ore = true, herb = true, quest = true, other = false, hideInstances = true,
    range = 15, style = 1, size = 80, opacity = 85, color = "ffd166", offsetY = -20, pulse = true }
module.context = { Event = function(_, key, callback) events[key] = callback end,
    CVar = function(_, key, value) writes[#writes + 1] = {key, value}; return true end }
module:Enable()
assert(module.host.shown and #writes == 4 and module.host.point[2] == plate, "ore glimmer not anchored")
local baseline = created
for i = 1, 20 do events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED") end
assert(created == baseline and #writes == 4, "events allocate surfaces or rewrite CVars")
cursor = 2
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(module.host.shown, "herb hidden")
module.config.herb = false
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "category toggle ignored")
cursor, related = 20, true
events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
assert(module.host.shown, "quest object hidden")
object = false
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "unit highlighted as game object")
object, cursor = true, secret
events.PLAYER_SOFT_INTERACT_CHANGED(module, "PLAYER_SOFT_INTERACT_CHANGED")
assert(not module.host.shown, "secret cursor must not select an effect")
cursor = 1
for style = 1, 5 do module.config.style = style; module:Refresh(); assert(module.host.shown) end
events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
assert(not module.host.shown and not module.host.pulse.playing, "combat-edge cleanup failed")
combat = true
local before = #writes
module:Refresh()
assert(#writes == before and module.pending, "combat changed CVars")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(module.host.shown and not module.pending, "deferred refresh lost")
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
exists = false
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not module.host.shown, "stale target effect")
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
