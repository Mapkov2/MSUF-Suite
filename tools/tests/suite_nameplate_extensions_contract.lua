local root = assert(arg[1])
local secret = setmetatable({}, {
    __add = function() error("secret arithmetic") end, __sub = function() error("secret arithmetic") end,
    __lt = function() error("secret comparison") end, __le = function() error("secret comparison") end,
    __tostring = function() error("secret stringification") end,
})
local function IsSecret(value) return rawequal(value, secret) end
local function Finite(value) return not IsSecret(value) and type(value) == "number" and value == value end
local combat, now, target, focus, instance = false, 10, "nameplate1", nil, "none"
local reads, writes, created, hooks, ranges, casts, identities = {}, 0, 0, {}, {}, {}, {}
local function Read(key) reads[key] = (reads[key] or 0) + 1 end
local function CountReads() local count = 0 for _, n in pairs(reads) do count = count + n end return count end
local function RGB(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end
local NewFrame
NewFrame = function(parent)
    created = created + 1
    local f = { parent = parent, shown = true, alpha = 1, scale = 1, level = 1, points = {}, labels = {}, textures = {} }
    local function Write(self, alpha)
        assert(not self.forbidden, "forbidden write")
        assert(alpha or not (combat and self:IsProtected()), "protected write in combat")
        writes = writes + 1
    end
    function f:IsForbidden() return self.forbidden == true end
    function f:IsProtected() return self.protected == true or self.parent and self.parent:IsProtected() or false end
    function f:IsAnchoringRestricted() return self.restricted == true end
    function f:GetAlpha() return self.alpha end
    function f:SetAlpha(value) Write(self, true) self.alpha = value end
    function f:SetAlphaFromBoolean(value, yes, no)
        Write(self, true)
        self.alpha = IsSecret(value) and secret or value and yes or no
        self.booleanAlpha = { yes, no }
    end
    function f:GetScale() return self.scale end
    function f:SetScale(value) Write(self) self.scale = value end
    function f:GetFrameLevel() return self.level end
    function f:GetPoint(index) return unpack(self.points[index or 1] or {}) end
    function f:GetWidth() return self.size and self.size[1] or 14 end
    function f:SetFrameLevel(value) Write(self) self.level = value end
    function f:ClearAllPoints() Write(self) self.points = {} end
    function f:SetPoint(...) Write(self) self.points[#self.points + 1] = { ... } end
    function f:SetAllPoints(region) Write(self) self.anchor = region end
    function f:SetParent(region) Write(self) self.parent = region end
    function f:GetParent() return self.parent end
    function f:EnableMouse(value) Write(self) self.mouse = value end
    function f:SetText(value) Write(self) self.text = value end
    function f:SetFormattedText(format, ...)
        Write(self)
        for i = 1, select("#", ...) do if IsSecret(select(i, ...)) then self.text = secret return end end
        self.text = string.format(format, ...)
    end
    function f:SetFont(...) Write(self) self.font = { ... } end
    function f:SetTextColor(...) Write(self) self.color = { ... } end
    function f:SetAtlas(value) Write(self) self.atlas = value end
    function f:SetSize(...) Write(self) self.size = { ... } end
    function f:SetColorTexture(...) Write(self) self.color = { ... } end
    function f:SetShown(value) Write(self) self.shown = value end
    function f:Show() self:SetShown(true) end
    function f:Hide() self:SetShown(false) end
    function f:IsShown() return self.shown end
    function f:SetScript(event, callback) self[event] = callback end
    function f:HookScript(event, callback) self["hook" .. event] = callback end
    function f:RegisterEvent(event) self.events = self.events or {} self.events[event] = true end
    function f:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function f:CreateTexture()
        local texture = NewFrame(self)
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function f:CreateFontString() local label = NewFrame(self) self.labels[#self.labels + 1] = label return label end
    function f:CreateAnimationGroup()
        local group = { playing = false }
        function group:CreateAnimation()
            return { SetFromAlpha = function() end, SetToAlpha = function() end, SetDuration = function() end }
        end
        function group:SetLooping() end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        return group
    end
    function f:CanChangeHitTestPoints() return self.canHit ~= false end
    function f:GetHitTestPoints() return self.hitPoints or {} end
    function f:SetHitTestPoints(points) assert(self:CanChangeHitTestPoints()) self.hitPoints = points writes = writes + 1 end
    function f:ClearAllHitTestPoints() assert(self:CanChangeHitTestPoints()) self.hitPoints = {} writes = writes + 1 end
    return f
end
UIParent = NewFrame()
CreateFrame = function(_, _, parent) return NewFrame(parent) end
canaccesstable = function(value) return not IsSecret(value) end
GetTime = function() return now end
UnitExists = function(unit) Read("exists") return unit ~= "focus" or focus ~= nil end
UnitCanAttack = function(_, unit) Read("attack") return unit ~= "focus" or focus ~= nil end
UnitIsUnit = function(unit, other) Read("identity") return unit == (other == "target" and target or focus) end
UnitCastingDuration = function(unit) Read("cast") return casts[unit] and {} or nil end
UnitChannelDuration = function() Read("cast") end
UnitClassification = function() Read("classification") return "normal" end
UnitName = function(unit) Read("name") return unit == "player" and "Tester" or identities[unit] or "Enemy" end
UnitNameFromGUID = function(guid) Read("interrupter") return IsSecret(guid) and secret or "Interrupter" end
local identityRestricted, unitClass = false, "MAGE"
UnitClass = function() Read("class") return "Mage", unitClass end
UnitFactionGroup = function() Read("faction") return "Horde" end
GetClassAtlas = function(class) return "classicon-" .. class end
UnitPower = function() Read("power") return secret end
UnitPowerMax = function() Read("powerMax") return secret end
UnitGetTotalAbsorbs = function() Read("absorbs") return secret end
UnitDetailedThreatSituation = function(unit)
    Read("threat")
    if unit == "player" then return false, 1, secret, 30, 50 end
    return true, 3, 100, 100, 80
end
UnitHealthPercent = function(_, predicted, curve) Read("health") assert(curve and predicted == false) return secret end
GetGuildInfo = function() Read("guild") return "Test Guild" end
IsInInstance = function() Read("context") return instance ~= "none", instance end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return identityRestricted end }
C_ChallengeMode = { IsChallengeModeActive = function() return true end }
C_ScenarioInfo = { GetUnitCriteriaProgressValues = function() Read("forces") return 5, 1.25 end }
C_Spell = {
    DoesSpellExist = function(spell) Read("spell") return spell == 123 end,
    IsSpellInRange = function(_, unit) Read("range") return ranges[unit] end,
}
C_CurveUtil = { CreateCurve = function()
    Read("curve")
    local curve = { points = {} }
    function curve:SetType() end
    function curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
    return curve
end }
Enum = { LuaCurveType = { Step = 1 }, TooltipDataLineType = { None = 0, UnitName = 2, QuestTitle = 17, QuestPlayer = 18, QuestObjective = 8 } }
C_TooltipInfo = { GetUnit = function()
    Read("tooltip")
    return { lines = {
        { type = 2, leftText = "Enemy" }, { type = 0, leftText = "Enemy title" },
        { type = 17, leftText = "Completed quest" }, { type = 8, leftText = "8/8 enemies defeated" },
        { type = 17, leftText = "Quest" }, { type = 8, leftText = "2/8 enemies defeated" },
    } }
end }
NamePlateSetupOptions = { useClassicCastBar = false, spellNameInsideCastBar = false, castIconHeight = 12, horizontalScale = 1 }
hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...) original(...) callback(...) end
end
local NS = {
    IsSecret = IsSecret, Public = function(value) return not IsSecret(value) end, Finite = Finite, RGB = RGB,
    Text = function(value) return value end, IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function(frame) return frame and frame:IsForbidden() end },
    Client = { isForever = false }, Dispatch = function(fn, ...) return fn(...) end,
}
local registrations = {}
local S = {
    Public = NS.Public, Finite = Finite, RGB = RGB, CreateFrame = function() return NewFrame() end,
    GlobalFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
    SetFont = function(label, ...) label:SetFont(...) end,
    SetNativeSpellRange = function(_, spell, enabled) registrations[spell] = enabled end,
}
NS.NameplateStyle = {
    CreateBorder = function() return {} end,
    PaintBorder = function(border, _, size, color) border.size, border.color = size, color end,
}
local P = {
    NS = NS, Suite = S, Mode = { LOOK_BLIZZARD = 2 },
    Geometry = { Point = function(region, ...) region:SetPoint(...) end },
    Text = { styles = { enemy = {}, friendly = {} } },
    Roles = { Quest = function() return true end, Classify = function() return "Caster" end,
        QuestObjectiveIncomplete = function(text) return text == "2/8 enemies defeated" end },
    Layout = { Reapply = function() end, Restore = function() end, Observe = function() end },
    HookPlates = function(method, callback) hooks[method] = callback end,
}
local jobs, timers, tickers = {}, {}, {}
local ctx = { callbacks = {} }
function ctx:Event(event, callback) self.callbacks[event] = callback end
function ctx:RemoveEvent(event) self.callbacks[event] = nil end
function ctx:Ticker(interval, callback) tickers[callback] = interval end
function ctx:After(delay, callback) timers[callback] = now + delay end
function ctx:Cancel(callback) tickers[callback], timers[callback] = nil, nil end
function ctx:Coalesce(_, callback)
    local job = { callback = callback }
    function job:Request() self.pending = true end
    function job:Cancel() self.pending = false end
    jobs[#jobs + 1] = job
    return job
end
local M = { active = true, context = ctx, config = { enemy = true, friendly = true, look = 3 }, activeUnits = {}, pendingPlates = {}, facts = {} }
local legacyMax = 0
P.Power = { SetExtraTextEvents = function(wanted)
    if wanted then
        ctx:Event("UNIT_MAXPOWER", function(module, event, unit)
            legacyMax = legacyMax + 1
            P.Extensions.OnUnit(module, event, unit)
        end)
    else ctx:RemoveEvent("UNIT_MAXPOWER") end
end }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Core", NS)
for _, file in ipairs({ "ExtensionLayout", "ExtensionText", "ExtensionEffects", "ExtensionResources", "Extensions" }) do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file .. ".lua"))("Plates", P)
end
local X = P.Extensions
X.Bind(M)
local beforeCreated, beforeReads = created, CountReads()
X.Configure(M)
assert(created == beforeCreated and CountReads() == beforeReads and next(ctx.callbacks) == nil and next(tickers) == nil,
    "disabled extensions must allocate no frame, query no gameplay data and register no listeners/tickers")
local plates = {}
C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit == "target" and target or unit] end }
local function Plate(unit, friend)
    local plate, uf = NewFrame(UIParent), NewFrame(UIParent)
    plate.UnitFrame, plate.unitToken = uf, unit
    uf.isFriend, uf.isPlayer, uf.showOnlyName = friend == true, false, false
    uf.name, uf.HealthBarsContainer, uf.CastBarsContainer = NewFrame(uf), NewFrame(uf), NewFrame(uf)
    local health, cast = NewFrame(uf.HealthBarsContainer), NewFrame(uf.CastBarsContainer)
    uf.HealthBarsContainer.healthBar, uf.CastBarsContainer.castBar = health, cast
    cast.Icon, cast.Text, cast.Border = NewFrame(cast), NewFrame(cast), NewFrame(cast)
    uf.RaidTargetFrame = NewFrame(uf)
    plates[unit], M.activeUnits[unit] = plate, uf
    return plate, uf, health, cast
end
local plate, uf, health, cast = Plate("nameplate1")
local _, uf2, health2, cast2 = Plate("nameplate2")
local friendly, friendUF, friendHealth, friendCast = Plate("nameplate3", true)
local function Apply(frame, bar, casting, side, unit) X.Apply(frame, bar, casting, side or "enemy", unit or "nameplate1") end
local function Refresh()
    X.Configure(M)
    Apply(uf, health, cast)
    Apply(uf2, health2, cast2, "enemy", "nameplate2")
    Apply(friendUF, friendHealth, friendCast, "friendly", "nameplate3")
end
beforeCreated, beforeReads = created, CountReads()
local beforeWrites = writes
for _ = 1, 1000 do
    Apply(uf, health, cast)
    X.OnUnit(M, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
    X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate1", secret, secret, 1)
    X.OnSelection()
    X.OnContext()
end
assert(created == beforeCreated and CountReads() == beforeReads and writes == beforeWrites,
    "1000 disabled lifecycle loops have zero native reads, writes and allocations")
M.config = { enemy = true, friendly = true, look = 2, plateContextEnabled = true, executePulseEnabled = true,
    focusReminderEnabled = true, plateRangeEnabled = true, plateRangeSpell = 123, targetClassResources = true }
X.Configure(M)
assert(created == beforeCreated and CountReads() == beforeReads and next(tickers) == nil,
    "the Blizzard look keeps saved extension settings dormant")
M.config = { enemy = true, friendly = true, look = 3 }
M.config.enemyNameDuringCast, M.config.enemyNameCastAlpha = 2, 25
M.config.interruptFeedbackEnabled, M.config.interruptFeedbackDuration, M.config.interruptFeedbackWho = true, 1.2, true
Refresh()
X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate1", secret, secret, 42)
assert(uf.name.alpha == .25, "cast start dims native name")
X.OnCast(M, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", secret, secret, secret, 43)
assert(uf.name.alpha == .25, "late interrupt for another cast must not stop current cast")
X.OnCast(M, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", secret, secret, secret, 42)
assert(uf.name.alpha == 1 and reads.interrupter == 1 and next(timers), "interrupt restores name and owns bounded feedback")
now = 12
for callback in pairs(timers) do callback(M) end
assert(next(timers) == nil, "finished feedback has no timer")
X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate1", secret, secret, 44)
cast.hookOnHide(cast)
assert(uf.name.alpha == 1, "native cast hiding resets the name when a stop event is unavailable")
X.OnCast(M, "UNIT_SPELLCAST_CHANNEL_START", "nameplate1", secret, secret, 45)
X.OnCast(M, "UNIT_SPELLCAST_CHANNEL_STOP", "nameplate1", secret, secret, "Interrupter", 45)
assert(uf.name.alpha == 1 and reads.interrupter == 2, "channel stop uses fifth-argument cast ID and fourth-argument interrupter")
X.OnCast(M, "UNIT_SPELLCAST_EMPOWER_START", "nameplate1", secret, secret, 46)
X.OnCast(M, "UNIT_SPELLCAST_EMPOWER_STOP", "nameplate1", secret, secret, false, "Interrupter", 46)
assert(uf.name.alpha == 1 and reads.interrupter == 3, "empower stop uses sixth-argument cast ID and fifth-argument interrupter")
X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate1", secret, secret, 47)
X.BeforeNameFilter(uf)
assert(uf.name.alpha == 1, "friendly-name filtering sees the alpha before cast dimming")
uf.name:SetAlpha(0)
Apply(uf, health, cast)
assert(uf.name.alpha == 0, "cast dimming preserves an external name filter")
X.BeforeNameFilter(uf)
uf.name:SetAlpha(1)
X.OnCast(M, "UNIT_SPELLCAST_STOP", "nameplate1", secret, secret, 47)
M.config.enemyRaidRelativeAnchor, M.config.enemyCastIconRelativeAnchor, M.config.enemyCastForeground = 2, 3, true
M.config.focusScaleEnabled, M.config.focusScalePercent = true, 120
focus = "nameplate1"
Refresh()
assert(uf.scale == 1.2 and cast.level == uf.level + 10, "focus scale and cast foreground")
assert(uf.RaidTargetFrame.points[1][2] == uf.name and cast.Icon.points[1][2] == cast, "relative anchors target native regions")
assert(cast.points[1][2] == uf.CastBarsContainer, "custom icon breaks native bar/icon anchor cycle")
M.config.plateClickboxEnabled, M.config.plateClickboxWidth, M.config.plateClickboxHeight = true, 180, 50
M.config.friendlyPlateClickThrough = true
Refresh()
assert(plate.hitPoints[1].offsetX == -90 and plate.hitPoints[2].offsetY == -25, "custom clickbox dimensions")
assert(#friendly.hitPoints == 0, "friendly click-through uses native empty hit-test anchors")
M.config.plateContextEnabled, M.config.enemyNpcWorldVisible = true, false
plate.canHit = false
Refresh()
assert(uf.alpha == 1, "visibility waits for hit-test permission")
plate.canHit = true
Apply(uf, health, cast)
assert(uf.alpha == 0 and #plate.hitPoints == 0, "hidden context has no click area")
M.config.enemyNpcWorldVisible = true
M.config.plateRangeEnabled, M.config.plateRangeSpell, M.config.plateRangeAlpha = true, 123, 35
M.config.plateRangeText = true
ranges.nameplate1, ranges.nameplate2 = true, false
Refresh()
assert(uf.alpha == 1 and uf2.alpha == .35 and registrations[123] == true, "range fade and shared spell registration")
local rangeReads = reads.range
beforeWrites, beforeCreated = writes, created
for _ = 1, 100 do for callback in pairs(tickers) do callback(M) end end
assert(reads.range == rangeReads + 100, "100 range ticks query only the one eligible non-target enemy")
assert(writes == beforeWrites and created == beforeCreated, "unchanged range polling performs no native writes or allocations")
ctx.callbacks.SPELL_RANGE_CHECK_UPDATE(M, "SPELL_RANGE_CHECK_UPDATE", 123, secret, true)
assert(IsSecret(uf.alpha) and uf.booleanAlpha[1] == 1 and uf.booleanAlpha[2] == .35,
    "secret range reaches the native boolean alpha sink")
ctx.callbacks.SPELL_RANGE_CHECK_UPDATE(M, "SPELL_RANGE_CHECK_UPDATE", 123, nil, false)
assert(uf.alpha == 1, "unknown range clears the prior secret range sink")
combat, uf2.protected, ranges.nameplate2 = true, true, true
for callback in pairs(tickers) do callback(M) end
assert(uf2.alpha == 1, "range alpha changes immediately on protected frames during combat")
combat, uf2.protected = false, false
ranges.nameplate2 = nil
for callback in pairs(tickers) do callback(M) end
assert(uf2.alpha == 1, "unknown range differs from out of range")
M.config.executePulseEnabled, M.config.extraText1Source, M.config.extraText2Source = true, 8, 9
M.config.extraText3Source, M.config.extraText4Source = 6, 7
Refresh()
assert(reads.health > 0, "execute uses native health-to-curve sink")
ctx.callbacks.UNIT_MAXPOWER(M, "UNIT_MAXPOWER", "nameplate1")
assert(legacyMax == 1, "power label preserves existing maximum-power subscriber")
local foundDifference, foundSecret = false, false
for _, label in ipairs(uf.labels) do
    if rawequal(label.text, secret) then foundSecret = true elseif label.text == "-30" then foundDifference = true end
end
assert(foundSecret and foundDifference, "opaque resources/threat reach text sinks and public threat difference is correct")
M.config.extraText1Source, M.config.extraText2Source, M.config.extraText3Source, M.config.extraText4Source = 3, 4, 5, 10
Refresh()
local texts = {}
for _, label in ipairs(uf.labels) do if not IsSecret(label.text) then texts[label.text or ""] = true end end
assert(texts["2/8 enemies defeated"] and texts["Test Guild"] and texts["Enemy title"] and texts["+1.25%"], "native metadata text sources")
local oldTooltip = reads.tooltip
X.OnUnit(M, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(reads.tooltip == oldTooltip, "threat updates never rescan tooltips")
assert(ctx.callbacks.SCENARIO_CRITERIA_UPDATE == nil and ctx.callbacks.SCENARIO_UPDATE == nil,
    "enemy forces are cached per plate without per-kill metadata listeners")
X.OnContext(false)
assert(reads.tooltip == oldTooltip, "unchanged context does not rescan plate metadata")
X.Restore(uf2)
M.activeUnits.nameplate2 = nil
assert(next(tickers) ~= nil, "remaining target retains shared native range interest")
X.Restore(uf)
assert(next(tickers) == nil and registrations[123] == false, "last enemy removal stops polling and releases range")
M.activeUnits.nameplate1 = uf
Apply(uf, health, cast)
combat, uf.protected = true, true
local before = writes
M.active = false
X.Disable()
assert(writes >= before and uf.scale == 1.2, "protected restore is deferred")
combat, uf.protected = false, false
X.OnCombatEnded()
assert(uf.scale == 1 and uf.alpha == 1 and uf.name.alpha == 1 and cast.level == 1, "combat-end restoration restores native appearance")
assert(next(tickers) == nil and next(timers) == nil and next(ctx.callbacks) == nil, "disabled extensions release all owned subscriptions")
local available, reason = NS.NameplateExtensions.Capability("lockout")
assert(available == false and reason:find("duration"))
assert(NS.NameplateExtensions.Capability("lineOfSight") == false)
NS.Client.isForever = true
assert(NS.NameplateExtensions.Capability("resources") == false)
assert(NS.NameplateExtensions.Kind(secret, false) == nil and NS.NameplateExtensions.Context(secret) == nil)

-- Settings edits can remove the final feature while the module stays active.
NS.Client.isForever, M.active = false, true
M.config = { enemy = true, friendly = true, look = 3, focusScaleEnabled = true, focusScalePercent = 120 }
Refresh()
assert(uf.scale == 1.2)
M.config.focusScaleEnabled = false
X.Configure(M)
assert(uf.scale == 1 and X.inUse == false, "removing the final feature restores every active plate immediately")

-- Retail's native mechanic frame follows the target and returns to the
-- personal display. Forever's TOC excludes this class mechanic family.
NS.Client.isForever, M.active = false, true
local playerPlate = Plate("player", true)
local mechanic, driver = NewFrame(playerPlate), NewFrame(UIParent)
NamePlateDriverFrame = driver
function driver:GetClassNameplateBar() return mechanic end
function driver:GetClassNameplateManaBar() end
function driver:GetClassNameplateAlternatePowerBar() end
function driver:SetupClassNameplateBars()
    mechanic:SetParent(playerPlate)
    mechanic:ClearAllPoints()
    mechanic:SetPoint("TOP", playerPlate.UnitFrame.HealthBarsContainer, "BOTTOM", 0, -4)
end
M.config = { enemy = true, friendly = true, look = 3, targetClassResources = true }
X.Configure(M)
assert(mechanic.parent == plate, "Retail native resource bar anchors to target")
target = "nameplate2"
driver:SetupClassNameplateBars()
assert(mechanic.parent == plates.nameplate2, "native setup hook reapplies the current target")
mechanic:Hide()
driver:SetupClassNameplateBars()
assert(not mechanic.shown, "resource anchoring preserves native mechanic visibility")
combat, mechanic.protected, target = true, true, "nameplate1"
X.OnSelection()
assert(mechanic.parent == plates.nameplate2 and mechanic.alpha == 0, "blocked target reparent hides a stale pooled resource bar")
combat, mechanic.protected = false, false
X.OnCombatEnded()
assert(mechanic.parent == plate and mechanic.alpha == 1, "deferred resource anchor restores its original opacity")
mechanic.restricted, target = true, "nameplate2"
X.OnSelection()
assert(mechanic.parent == plate and mechanic.alpha == 0, "restricted anchors defer reparenting outside combat too")
mechanic.restricted = false
X.OnCombatEnded()
assert(mechanic.parent == plates.nameplate2 and mechanic.alpha == 1)
M.config.targetClassResources = false
X.Configure(M)
assert(mechanic.parent == playerPlate and mechanic.points[1][1] == "TOP", "disabling restores the native personal anchor")
NS.Client.isForever, M.config.targetClassResources = true, true
X.Configure(M)
assert(mechanic.parent == playerPlate, "Forever never reanchors unloaded native mechanic bars")

-- Identity markers share the plate lifecycle and respect restricted identities.
NS.Client.isForever, uf.isPlayer = false, true
M.config = { enemy = true, friendly = true, look = 3, enemyIdentityIcons = 4 }
Refresh()
local classIcon, factionIcon = uf.textures[1], uf.textures[2]
assert(classIcon.atlas == "classicon-MAGE" and factionIcon.atlas == "UI-HUD-UnitFrame-Player-PVP-HordeIcon")
unitClass = secret
Apply(uf, health, cast)
assert(classIcon.shown == false and factionIcon.shown, "restricted class values never reach a Lua atlas lookup")
identityRestricted = true
Apply(uf, health, cast)
assert(not classIcon.shown and not factionIcon.shown, "restricted identity hides both extra markers")
identityRestricted, unitClass, NS.Client.isForever = false, "MAGE", true
Apply(uf, health, cast)
assert(factionIcon.atlas == "UI-HUD-UnitFrame-SmallCircle-Horde", "Forever uses its loaded native faction style")
uf.isPlayer = false
local beforeIdentity = CountReads()
Apply(uf, health, cast)
assert(not classIcon.shown and not factionIcon.shown and CountReads() == beforeIdentity,
    "an NPC recycled onto a player plate clears identity art without identity reads")
uf.PlayerLevelDiffFrame = NewFrame(uf)
uf.PlayerLevelDiffFrame:SetPoint("CENTER", uf, "LEFT", -2, 0)
M.config = { enemy = true, friendly = true, look = 3, enemyRaidRelativeAnchor = 2 }
Refresh()
M.config.enemyRaidRelativeAnchor = 1
X.Configure(M)
assert(uf.RaidTargetFrame.points[1][4] == -16, "Forever restoration keeps the native left-side level-badge reservation")

local protectedFrame = NewFrame()
function protectedFrame:IsProtected() return secret end
combat = true
assert(P.ExtensionLayout.Mutable({ uf = protectedFrame, owner = M }, protectedFrame) == false,
    "secret protection status denies geometry writes")
combat = false
M.config = { enemy = true, friendly = true, look = 3, extraText1Source = 8, enemyNameDuringCast = 2 }
Refresh()
combat, uf.protected = true, true
X.Restore(uf)
for _, label in ipairs(uf.labels) do assert(label.alpha == 0, "pending pooled restoration clears old text immediately") end
plates.nameplate9, M.activeUnits.nameplate9, M.activeUnits.nameplate1 = plate, uf, nil
Apply(uf, health, cast, "enemy", "nameplate9")
X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate9", secret, secret, 90)
X.OnSelection()
for _, label in ipairs(uf.labels) do assert(label.alpha == 0, "the next unit cannot resume a pending old occupant") end
combat, uf.protected = false, false
X.OnCombatEnded()
Apply(uf, health, cast, "enemy", "nameplate9")
assert(uf.labels[1].alpha == 1, "the new occupant resumes its own text after a safe rebind")
print("nameplate extensions contract passed: lifecycle, pooling, secrets, layout, click permission, range budget, text, restoration")
