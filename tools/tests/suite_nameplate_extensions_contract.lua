local root = assert(arg[1])
local secret = setmetatable({}, {
    __add = function() error("secret arithmetic") end, __sub = function() error("secret arithmetic") end,
    __lt = function() error("secret comparison") end, __le = function() error("secret comparison") end,
    __tostring = function() error("secret stringification") end,
})
local function IsSecret(value) return rawequal(value, secret) end
local function Finite(value) return not IsSecret(value) and type(value) == "number" and value == value end
local combat, now, target, focus, instance = false, 10, "nameplate1", nil, "none"
local mounted, resting, stealthed, vehicle, grouped, housing, reaction, fighting =
    false, false, false, false, false, false, 2, false
local healthFraction = {}
IsMounted = function() return mounted end
IsResting = function() return resting end
IsStealthed = function() return stealthed end
UnitHasVehicleUI = function() return vehicle end
UnitInVehicle = function() return vehicle end
IsInGroup = function() return grouped end
C_Housing = { IsInsideHouseOrPlot = function() return housing end }
UnitReaction = function(unit) return unit == "nameplate3" and 5 or unit == "nameplate2" and reaction or 2 end
UnitAffectingCombat = function(unit) return unit == "nameplate2" and fighting or false end
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
UnitExists = function(unit)
    Read("exists")
    if unit == "target" then return target ~= nil end
    return unit ~= "focus" or focus ~= nil
end
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
UnitHealthPercent = function(unit, predicted, curve)
    Read("health")
    assert(curve and predicted == false)
    local fraction = healthFraction[unit]
    if IsSecret(fraction) or fraction == nil then return secret end
    local value
    for _, point in ipairs(curve.points) do
        if fraction < point[1] then break end
        value = point[2]
    end
    return value
end
GetGuildInfo = function() Read("guild") return "Test Guild" end
IsInInstance = function() Read("context") return instance ~= "none", instance end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return identityRestricted end }
C_ChallengeMode = { IsChallengeModeActive = function() return true end }
C_ScenarioInfo = { GetUnitCriteriaProgressValues = function() Read("forces") return 5, 1.25 end }
C_Spell = {
    DoesSpellExist = function(spell) Read("spell") return spell == 123 or spell == 456 end,
    EnableSpellRangeCheck = function() end,
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
NamePlateUnitFrameMixin = { UpdateHitTestArea = function() end }
hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...) original(...) callback(...) end
end
local NS = {
    IsSecret = IsSecret, Public = function(value) return not IsSecret(value) end, Finite = Finite, RGB = RGB,
    Text = function(value) return value end, IsCombatLocked = function() return combat end,
    InCombat = function(event)
        if event == "PLAYER_REGEN_DISABLED" then return true end
        if event == "PLAYER_REGEN_ENABLED" then return false end
        return combat
    end,
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
    Layout = { Reapply = function() end, Restore = function() end, Observe = function() end,
        CastWidthDelta = function(_, c, side) return c[side .. "CastWidthDelta"] or 0 end },
    HookPlates = function(method, callback) hooks[method] = callback end,
}
local jobs, timers, tickers = {}, {}, {}
local ctx = { callbacks = {}, unitFilters = {} }
function ctx:Event(event, callback, _, units)
    if not self.callbacks[event] then self.unitFilters[event] = units end
    self.callbacks[event] = callback
end
function ctx:RemoveEvent(event) self.callbacks[event], self.unitFilters[event] = nil, nil end
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
NS.AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
NS.AnchorLabels = NS.AnchorPoints
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Core", NS)
for _, file in ipairs({ "ExtensionLayout", "ExtensionText", "ExtensionEffects", "Extensions" }) do
    local path = file == "ExtensionEffects" and os.getenv("SUITE_EFFECTS_OVERRIDE")
        or root .. "/MSUF_Suite_Nameplates/" .. file .. ".lua"
    assert(loadfile(path))("Plates", P)
end
local X = P.Extensions
X.Bind(M)
local beforeCreated, beforeReads = created, CountReads()
X.Configure(M)
assert(created == beforeCreated and CountReads() == beforeReads and next(ctx.callbacks) == nil and next(tickers) == nil,
    "disabled extensions must allocate no frame, query no gameplay data and register no listeners/tickers")
local plates = {}
P.UnitKinds = {}
UnitIsPlayer = function(unit) return plates[unit] and plates[unit].UnitFrame.isPlayer == true end
C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit == "target" and target or unit] end }
local function Plate(unit, friend)
    local plate, uf = NewFrame(UIParent), NewFrame(UIParent)
    plate.UnitFrame, plate.unitToken = uf, unit
    uf.isFriend, uf.isPlayer, uf.showOnlyName = friend == true, false, false
    uf.name, uf.HealthBarsContainer, uf.CastBarsContainer = NewFrame(uf), NewFrame(uf), NewFrame(uf)
    local health, cast = NewFrame(uf.HealthBarsContainer), NewFrame(uf.CastBarsContainer)
    health.fill, health.bgTexture, health.totalAbsorb = NewFrame(health), NewFrame(health), NewFrame(health)
    function health:GetStatusBarTexture() return self.fill end
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
    focusReminderEnabled = true, plateRangeEnabled = true, plateRangeSpell = 123 }
X.Configure(M)
assert(created == beforeCreated and CountReads() == beforeReads and next(tickers) == nil,
    "the Blizzard look keeps saved extension settings dormant")
M.config = { enemy = true, friendly = true, look = 3 }
M.config.enemyRaidRelativeAnchor = 2
local beforeCast = reads.cast or 0
Refresh()
assert(not X.usesCasts and (reads.cast or 0) == beforeCast and not cast.hookOnShow and not cast.hookOnHide,
    "an unrelated extension armed or queried cast effects")
M.config.enemyNameDuringCast, M.config.enemyNameCastAlpha = 2, 25
casts.nameplate1 = true
Refresh()
assert(X.usesCasts and uf.name.alpha == .25 and cast.hookOnShow and not friendCast.hookOnShow,
    "turning on cast dimming mid-cast missed its side or installed hooks on the disabled side")
casts.nameplate1, M.config.enemyNameDuringCast = nil, 1
Refresh()
beforeCast = reads.cast or 0
cast.hookOnShow(cast)
cast.hookOnHide(cast)
X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate1", secret, secret, 2)
assert(not X.usesCasts and (reads.cast or 0) == beforeCast and uf.name.alpha == 1,
    "turning cast dimming off left work in retained native hooks")
M.config.enemyRaidRelativeAnchor, M.config.enemyNameDuringCast = 1, 2
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
uf.name:SetAlpha(.8)
Apply(uf, health, cast)
assert(uf.name.alpha == .2, "cast dimming ignored the native name's opacity")
X.BeforeNameFilter(uf)
assert(uf.name.alpha == .8, "ending cast dimming lost the native name's original opacity")
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
assert(uf.alpha == 1 and uf2.alpha == 1 and registrations[123] == true and next(tickers) == nil,
    "range must register only the target without polling or fading off-target plates")
ctx.callbacks.SPELL_RANGE_CHECK_UPDATE(M, "SPELL_RANGE_CHECK_UPDATE", 123, secret, true)
assert(IsSecret(uf.alpha) and uf.booleanAlpha[1] == 1 and uf.booleanAlpha[2] == .35,
    "secret range reaches the native boolean alpha sink")
ctx.callbacks.SPELL_RANGE_CHECK_UPDATE(M, "SPELL_RANGE_CHECK_UPDATE", 123, nil, false)
assert(uf.alpha == 1, "unknown range clears the prior secret range sink")
target = "nameplate2"
X.OnSelection()
assert(uf2.alpha == .35 and uf.alpha == 1, "target switch seeds the new target and clears the old target")
target = "nameplate1"
X.OnSelection()
M.config.executePulseEnabled = true
M.config.enemyExtraTextResource, M.config.enemyExtraTextAbsorb = true, true
M.config.enemyExtraTextThreat, M.config.enemyExtraTextTankThreat = true, true
Refresh()
assert(reads.health > 0, "execute uses native health-to-curve sink")
ctx.callbacks.UNIT_MAXPOWER(M, "UNIT_MAXPOWER", "nameplate1")
assert(legacyMax == 1, "power label preserves existing maximum-power subscriber")
local foundDifference, foundSecret = false, false
for _, label in ipairs(uf.labels) do
    if rawequal(label.text, secret) then foundSecret = true elseif label.text == "-30" then foundDifference = true end
end
assert(foundSecret and foundDifference, "opaque resources/threat reach text sinks and public threat difference is correct")
M.config.enemyExtraTextQuest, M.config.enemyExtraTextGuild = true, true
M.config.enemyExtraTextTitle, M.config.enemyExtraTextForces = true, true
Refresh()
local texts = {}
for _, label in ipairs(uf.labels) do if not IsSecret(label.text) then texts[label.text or ""] = true end end
assert(texts["2/8 enemies defeated"] and texts["Test Guild"] and texts["Enemy title"] and texts["+1.25%"]
    and texts["-30"], "metadata and threat indicators can run together")
local oldTooltip = reads.tooltip
X.OnUnit(M, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(reads.tooltip == oldTooltip, "threat updates never rescan tooltips")
assert(ctx.callbacks.SCENARIO_CRITERIA_UPDATE == nil and ctx.callbacks.SCENARIO_UPDATE == nil,
    "enemy forces are cached per plate without per-kill metadata listeners")
X.OnContext(false)
assert(reads.tooltip == oldTooltip, "unchanged context does not rescan plate metadata")
X.Restore(uf2)
M.activeUnits.nameplate2 = nil
assert(next(tickers) == nil and registrations[123], "remaining target retains only native range interest")
X.Restore(uf)
assert(next(tickers) == nil and registrations[123] == false and not ctx.callbacks.SPELL_RANGE_CHECK_UPDATE,
    "target removal releases the native range registration and listener")
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
assert(NS.NameplateExtensions.Kind(secret, false) == nil and NS.NameplateExtensions.Context(secret) == nil)

-- Settings edits can remove the final feature while the module stays active.
NS.Client.isForever, M.active = false, true
M.config = { enemy = true, friendly = true, look = 3, focusScaleEnabled = true, focusScalePercent = 120 }
Refresh()
assert(uf.scale == 1.2)
M.config.focusScaleEnabled = false
X.Configure(M)
assert(uf.scale == 1 and X.inUse == false, "removing the final feature restores every active plate immediately")

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
M.config = { enemy = true, friendly = true, look = 3, enemyExtraTextResource = true, enemyNameDuringCast = 2 }
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
do
    local model = NS.NameplateExtensions
    local inherited = model.Plan({ plateContextEnabled = true, enemyNpcOpacity = 45 })
    local neutral = model.Plan({ plateContextEnabled = true, enemyNpcOpacity = 45, neutralNpcContextOverride = true, neutralNpcOpacity = 80 })
    local old = { plateContextEnabled = true, enemyNpcOpacity = 64, enemyNpcDungeonVisible = false }
    model.SeparateContexts(old)
    assert(old.neutralNpcOpacity == 64 and old.neutralNpcDungeonVisible == false, "neutral lost its old effective rules")
    old.enemyContextEnabled, old.enemyNpcOpacity, old.friendlyNpcContextEnabled = false, 31, false
    model.SeparateContexts(old)
    local separate = model.Plan(old)
    assert(separate.kinds.enemyNpc.alpha == 1 and separate.kinds.neutralNpc.alpha == .64
        and old.friendlyContextEnabled and not old.friendlyNpcContextEnabled, "context switches are coupled after normalization")
    local _, inheritedAlpha = model.Visibility(inherited, "neutralNpc", "World", false)
    local _, neutralAlpha = model.Visibility(neutral, "neutralNpc", "World", false)
    assert(inheritedAlpha == 0.45 and neutralAlpha == 0.8, "neutral opacity did not inherit or override correctly")
    local hidden = model.Plan({ neutralNpcContextOverride = true, neutralNpcWorldVisible = false })
    assert(not model.Visibility(hidden, "neutralNpc", "World", false) and model.Visibility(hidden, "enemyNpc", "World", false))
    assert(model.Kind(false, false, 4, false) == "neutralNpc" and model.Kind(false, false, 4, true) == "enemyNpc")
    local c = { enemyHealthWidthDelta = 30, neutralNpcHealthWidthDelta = 12, neutralNpcSizeOverride = true }
    assert(model.HealthDimensions(c, "enemy", "neutralNpc") == 12 and model.HealthDimensions(c, "enemy", "enemyNpc") == 30)
end

do
    plates.nameplate1, M.activeUnits.nameplate1, M.activeUnits.nameplate9 = plate, uf, nil
    M.config = { enemy = true, friendly = true, look = 3, enemyHideInCombat = true }
    plate.hitPoints = { { point = "TOPLEFT", relativePoint = "TOPLEFT", relativeTo = health, offsetX = 0, offsetY = 0 } }
    reaction = 4
    Refresh()
    assert(uf.alpha == 1 and uf2.alpha == 1 and friendUF.alpha == 1)
    ctx.callbacks.PLAYER_REGEN_DISABLED(M, "PLAYER_REGEN_DISABLED")
    assert(uf.alpha == 0 and #plate.hitPoints == 0 and uf2.alpha == 1 and friendUF.alpha == 1,
        "combat rule failed at the event edge or affected a different plate type")
    X.OnCombatEnded()
    assert(uf.alpha == 1 and #plate.hitPoints > 0, "leaving combat did not restore the visible plate")
    local function CheckToggle(key, event, assign, global, unit)
        M.config.enemyHideInCombat = nil
        M.config[key] = true
        Refresh()
        assign(true)
        if global then X.OnContext(false, event) else ctx.callbacks[event](M, event, unit) end
        assert(uf.alpha == 0 and friendUF.alpha == 1, key .. " did not hide only enemies")
        assign(false)
        if global then X.OnContext(false, event) else ctx.callbacks[event](M, event, unit) end
        assert(uf.alpha == 1, key .. " did not restore on change")
        M.config[key] = nil
    end
    CheckToggle("enemyHideMounted", "PLAYER_MOUNT_DISPLAY_CHANGED", function(value) mounted = value end)
    CheckToggle("enemyHideResting", "PLAYER_UPDATE_RESTING", function(value) resting = value end)
    CheckToggle("enemyHideStealthed", "UPDATE_STEALTH", function(value) stealthed = value end)
    CheckToggle("enemyHideInVehicle", "UNIT_ENTERED_VEHICLE", function(value) vehicle = value end, false, "player")
    CheckToggle("enemyHideInGroup", "GROUP_ROSTER_UPDATE", function(value) grouped = value end, true)
    CheckToggle("enemyHideSolo", "GROUP_ROSTER_UPDATE", function(value) grouped = not value end, true)
    CheckToggle("enemyHideInInstance", "ZONE_CHANGED_NEW_AREA", function(value) instance = value and "party" or "none" end, true)
    NS.Client.isForever = false
    CheckToggle("enemyHideInHousing", "HOUSE_PLOT_ENTERED", function(value) housing = value end)

    M.config.enemyHideOutOfCombat = true
    Refresh()
    assert(uf.alpha == 0, "the out-of-combat rule needs no target change")
    ctx.callbacks.PLAYER_REGEN_DISABLED(M, "PLAYER_REGEN_DISABLED")
    assert(uf.alpha == 1)
    M.config.enemyHideOutOfCombat, M.config.enemyHideNoTarget = nil, true
    Refresh()
    target = nil
    X.OnSelection()
    assert(uf.alpha == 0, "the no-target rule missed a target loss")
    target = "nameplate1"
    X.OnSelection()
    assert(uf.alpha == 1)
    M.config.enemyHideNoTarget, M.config.enemyHideOutOfCombatNoTarget = nil, true
    Refresh()
    target = nil
    X.OnSelection()
    assert(uf.alpha == 0, "the combined rule missed a target change")
    ctx.callbacks.PLAYER_REGEN_DISABLED(M, "PLAYER_REGEN_DISABLED")
    assert(uf.alpha == 1, "the combined rule hid enemies at combat start")
    X.OnCombatEnded()
    assert(uf.alpha == 0, "the combined rule missed combat end")
    M.config.enemyHideOutOfCombat = true
    M.config.enemyShowWhenInjured = true
    healthFraction.nameplate1 = 1
    Refresh()
    assert(not ctx.callbacks.PLAYER_REGEN_DISABLED and uf.alpha == 0 and #plate.hitPoints > 0,
        "health-only mode must replace the three combat/target conditions and keep native clicks")
    healthFraction.nameplate1 = .98
    ctx.callbacks.UNIT_HEALTH(M, "UNIT_HEALTH", "nameplate1")
    assert(uf.alpha == 1, "injured enemy was not revealed")
    M.config.plateContextEnabled, M.config.enemyNpcOpacity = true, 60
    Refresh()
    assert(uf.alpha == .6, "health gate overwrote the configured opacity")
    healthFraction.nameplate1 = secret
    ctx.callbacks.UNIT_MAXHEALTH(M, "UNIT_MAXHEALTH", "nameplate1")
    assert(IsSecret(uf.alpha) and uf2.alpha == .6 and friendUF.alpha == 1,
        "only the enemy health curve may receive a secret and must pass it to native alpha")
    M.config.enemyShowWhenInjured, M.config.enemyHideOutOfCombat, M.config.enemyHideOutOfCombatNoTarget = nil, nil, nil
    M.config.plateContextEnabled = false
    Refresh()
    assert(uf.alpha == 1 and not ctx.callbacks.UNIT_HEALTH and not ctx.callbacks.UNIT_MAXHEALTH,
        "disabling the visibility rules did not restore alpha or release health subscriptions")
end

do
    local fade = NS.NameplateExtensions.ReadOpacity({ enemyFadeHealthBackground = 20 }, "enemy")
    assert(fade.text == .2, "background fade left health text visible with Keep Text off")
    fade = NS.NameplateExtensions.ReadOpacity({ enemyFadeHealth = 30, enemyFadeHealthBackground = 20,
        enemyFadeKeepText = true }, "enemy")
    assert(fade.text == 1, "Keep Text did not protect against both health layers")
    M.config = { enemy = true, friendly = true, look = 3, enemyFadeHealth = 40, enemyFadeHealthBackground = 65,
        enemyFadePower = 50, enemyFadePowerBackground = 75, enemyFadeKeepPrediction = true,
        enemyFadeOutOfCombat = true, enemyFadeOutOfCombatAlpha = 50, plateContextEnabled = true, enemyNpcOpacity = 80 }
    local power = NewFrame(health)
    power.fill, power.enemyPowerBackground = NewFrame(power), NewFrame(power)
    function power:GetStatusBarTexture() return self.fill end
    P.Power.EnemyBar = function(frame) if frame == uf then return power end end
    health.fill.alpha, health.bgTexture.alpha = .8, .8
    Refresh()
    assert(math.abs(health.fill.alpha - .32) < 1e-6 and math.abs(health.bgTexture.alpha - .52) < 1e-6)
    assert(uf.alpha == .4 and uf2.alpha == .8 and friendUF.alpha == 1 and health.totalAbsorb.alpha == 1
        and power.fill.alpha == .5 and power.enemyPowerBackground.alpha == .75,
        "layer multipliers, exclusions, neutral scope or whole-plate composition are wrong")
    ctx.callbacks.PLAYER_REGEN_DISABLED(M, "PLAYER_REGEN_DISABLED")
    assert(uf.alpha == .8 and power.fill.alpha == .5)
    X.OnCombatEnded()
    assert(uf.alpha == .4)
    M.config.enemyFadeKeepPrediction = false
    Refresh()
    assert(health.totalAbsorb.alpha == .4)
    local previous = health.fill
    health.fill = NewFrame(health)
    Apply(uf, health, cast)
    assert(previous.alpha == .8 and health.fill.alpha == .4, "native fill replacement lost restoration")
    X.Restore(uf)
    assert(uf.alpha == 1 and health.fill.alpha == 1 and health.bgTexture.alpha == .8 and health.totalAbsorb.alpha == 1
        and power.fill.alpha == 1 and power.enemyPowerBackground.alpha == 1, "pooled plate kept a layer opacity")
    M.config = { enemy = true, friendly = true, look = 3 }
    Refresh()
    assert(not ctx.callbacks.PLAYER_REGEN_DISABLED and not X.inUse, "inactive opacity kept a combat subscription")
end

do
    local config = { enemy = true, friendly = true, look = 3,
        enemyClickboxEnabled = true, enemyClickboxWidth = 200, neutralClickboxEnabled = true, neutralClickboxWidth = 100,
        friendlyNpcClickboxEnabled = true, friendlyNpcClickboxWidth = 60,
        enemyRangeEnabled = true, enemyRangeSpell = 123, enemyRangeAlpha = 35,
        friendlyNpcRangeEnabled = true, friendlyNpcRangeSpell = 456, friendlyNpcRangeAlpha = 25,
        enemyExtraTextResource = true, friendlyNpcExtraTextTitle = true }
    local neutral = plates.nameplate2
    M.active = true
    M.config, reaction, fighting, target = config, 4, false, "nameplate1"
    ranges.nameplate1, ranges.nameplate3 = false, false
    Refresh()
    assert(plate.hitPoints[1].offsetX == -100 and neutral.hitPoints[1].offsetX == -50
        and friendly.hitPoints[1].offsetX == -30, "click areas must respect each plate type")
    assert(uf.alpha == .35 and uf2.alpha == 1 and friendUF.alpha == 1
        and registrations[123] and not registrations[456], "range limits leaked between types")
    local function HasText(frame, value)
        for _, label in ipairs(frame.labels) do
            if label.shown and rawequal(label.text, value) then return true end
        end
    end
    assert(HasText(uf, secret) and HasText(friendUF, "Enemy title"), "extra text must use the selected plate type")
    target = "nameplate3"
    X.OnSelection()
    assert(registrations[123] == false and registrations[456] and uf.alpha == 1 and friendUF.alpha == .25,
        "changing target types must switch the registered spell and fade only the new target")
    X.Disable()
end
do
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteMigrations.lua"))("Core", NS)
    local config = { plateClickboxEnabled = true, plateClickboxWidth = 200, plateRangeEnabled = true,
        plateRangeSpell = 123, friendlyPlateClickThrough = true, extraText1Source = 5, extraText1Side = 3,
        friendlyClickboxWidth = 125 }
    NS.SuiteMigrationSteps.NameplateTypeSettings({ nameplates = config })
    assert(config.enemyClickboxWidth == 200 and config.neutralClickboxWidth == 200
        and config.friendlyNpcClickboxWidth == 200 and config.friendlyClickboxWidth == 125)
    assert(config.enemyRangeSpell == 123 and config.neutralRangeSpell == 123
        and not config.friendlyRangeEnabled and not config.friendlyNpcRangeEnabled)
    assert(config.friendlyNpcPlateClickThrough and config.friendlyNpcExtraText1Source == 5
        and config.friendlyExtraText1Source == 5 and not config.enemyExtraText1Source)
    config.enemyExtraText2Source, config.enemyExtraText2Color, config.enemyExtraText2X = 8, "abc123", 17
    config.enemyExtraText3Source, config.enemyExtraText3X = 8, 42
    config.enemyStatusThreat, config.enemyStatusThreatAnchor, config.enemyStatusThreatSize = true, 4, 36
    config.enemyStatusThreatLayer = 9
    config.neutralExtraTextThreat = false
    NS.SuiteMigrationSteps.NameplateTextIndicators({ nameplates = config })
    assert(config.friendlyNpcExtraTextTitle and config.friendlyExtraTextTitle and not config.enemyExtraTextTitle)
    assert(config.enemyExtraTextResource and config.enemyExtraTextResourceColor == "abc123"
        and config.enemyExtraTextResourceX == 17 and config.enemyExtraTextResourceY == -12
        and config.enemyExtraTextResourceAnchor == 2)
    assert(config.enemyExtraTextThreat and config.enemyExtraTextThreatSize == 36 and config.neutralExtraTextThreat == false
        and config.enemyExtraTextThreatLayer == 9)
    assert(NS.NameplateExtensions.TextPoints[config.enemyExtraTextThreatAnchor][3] == "LEFT")
    assert(config.extraText1Source == nil and config.enemyExtraText2Source == nil and config.enemyStatusThreat == nil)
end
do
    local chosen, resolves = 123, 0
    NS.HostBridge = { NameplateRangeSpell = function(friendly)
        resolves = resolves + 1
        return friendly and 0 or chosen
    end }
    M.active, target = true, "nameplate1"
    M.config = { look = 3, enemy = true, friendly = true, enemyRangeEnabled = true, enemyRangeAuto = true }
    Refresh()
    assert(registrations[123], "automatic range did not use the native target subscription")
    local n = resolves
    for _ = 1, 100 do Apply(uf, health, cast) end
    assert(resolves == n, "plate paints repeatedly resolved the class spell")
    chosen = 456
    X.RangeSpellChanged()
    assert(registrations[123] == false and registrations[456], "class spell change retained the previous native subscription")
    X.Disable()
    M.active = true
    M.config = { look = 3, enemy = true, friendly = true, interruptFeedbackEnabled = true }
    M.castbarStyle = { interruptDuration = .25, interruptR = .1, interruptG = .2, interruptB = .3 }
    local shakes, surface = 0, nil
    P.CastAppearance = { StopFeedback = function() end, ShakeFeedback = function(bar, overlay)
        assert(bar == cast and overlay.shown)
        shakes, surface = shakes + 1, overlay
    end }
    Refresh()
    X.OnCast(M, "UNIT_SPELLCAST_START", "nameplate1", nil, nil, 100)
    X.OnCast(M, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", nil, nil, "Interrupter", 100)
    local at = next(timers)
    assert(at and timers[at] == now + .25, "custom interrupt text ignored the shared duration")
    assert(shakes == 1 and surface, "visible custom interrupt feedback missed the shared shake")
    X.Disable()
    M.castbarStyle = nil
end
do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("Plates", P)
    P.Auras = { RestorePlate = function() end, Apply = function() end }
    local scopes = P.SkinScopes
    local suppress = scopes.Bind(M, function() end)
    local outer, unit = Plate("nameplate4")
    unit.unit, unit.alpha = "nameplate4", .8
    local nativePoints = { { point = "TOPLEFT" } }
    outer.hitPoints = nativePoints
    local access = true
    function unit:CanBeAccessedInContext() return access end
    local nativeSetAlpha = unit.SetAlpha
    function unit:SetAlpha(alpha)
        assert(access == true, "wrote alpha on an inaccessible unit frame")
        nativeSetAlpha(self, alpha)
    end

    combat, M.config.enemySkinEnabled = true, false
    scopes.Configure()
    suppress(unit)
    assert(unit.alpha == 0 and #outer.hitPoints == 0, "scope did not hide the unit and its hit region")

    outer.canHit, M.config.enemySkinEnabled = false, true
    scopes.Configure()
    assert(unit.alpha == .8 and #outer.hitPoints == 0 and M.pendingPlates[unit],
        "blocked outer hit-test restore also blocked restoring unit frame alpha")
    unit:SetAlpha(.65)
    outer.canHit = true
    scopes.RestoreVisibility(unit)
    assert(unit.alpha == .65 and outer.hitPoints == nativePoints and not scopes.OnHitTest(unit),
        "later hit-test restore overwrote released alpha or kept the lease")

    M.config.enemySkinEnabled = false
    scopes.Configure()
    suppress(unit)
    access, M.config.enemySkinEnabled = secret, true
    M.pendingPlates[unit] = nil
    scopes.Configure()
    assert(unit.alpha == 0 and outer.hitPoints == nativePoints and M.pendingPlates[unit],
        "unreadable frame access affected independently restored hit-test points")
    access = true
    assert(scopes.OnHitTest(unit) and unit.alpha == .65 and not scopes.OnHitTest(unit),
        "native hit-area refresh did not retry the still-owned alpha")
end
do
    local showQuest, related = true, true
    P.IsSkinSuppressed = nil
    P.FriendlyNames = { nameOnlyEnabled = true, IsNameOnly = function() return showQuest end,
        KeepsQuestText = function() return showQuest end }
    P.Roles.Quest = function() return related end
    M.active = true
    M.config = { enemy = true, look = 3, neutralPlateNameOnly = true, neutralNameOnlyMode = 2 }
    local _, npc, npcHealth, npcCast = Plate("nameplate4")
    P.UnitKinds[npc] = "neutralNpc"
    X.Configure(M)
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    local label = npc.labels[1]
    assert(label and #npc.labels == 1 and label:IsShown() and label.text == "2/8 enemies defeated"
        and X.usesMetadata, "split name-only did not show the available quest objective on its own")
    local before = reads.tooltip
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    assert(reads.tooltip == before, "repainting a stable quest label rescanned its tooltip")
    related = false
    X.OnUnit(M, "UNIT_NAME_UPDATE", "nameplate4")
    assert(not label:IsShown(), "an unavailable objective was left visible")
    showQuest, related = false, true
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    showQuest = true
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    assert(label:IsShown(), "the returning quest label did not recover after the health bar transition")
    M.config.neutralExtraTextTitle, M.config.neutralFadeHealth = true, 35
    X.Configure(M)
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    local title = npc.labels[2]
    assert(title and title:GetAlpha() == .35 and label:GetAlpha() == .35,
        "a new subtitle or an existing quest label escaped the text fade")
    M.config.neutralFadeKeepText = true
    X.Configure(M)
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    assert(title:GetAlpha() == 1 and label:GetAlpha() == 1, "Keep Text left extra labels faded")
    assert(label:IsShown() and title and title:IsShown() and title.text == "Enemy title",
        "NPC title was missing from the name-only plate or hid the existing quest objective")
    local point, owner, relative = title:GetPoint()
    assert(point == "TOP" and owner == npc.name and relative == "BOTTOM",
        "name-only NPC title is not directly below the name")
    P.FriendlyNames.KeepsQuestText = function() return false end
    Apply(npc, npcHealth, npcCast, "enemy", "nameplate4")
    assert(title:IsShown() and not label:IsShown(), "title-only display kept the quest text")
    local getUnit = C_TooltipInfo.GetUnit
    do
        local function FlushMetadata()
            for _, job in ipairs(jobs) do
                if job.pending then job.pending = false job.callback(M) end
            end
        end
        local questLog = X.OnQuestMetadata or X.OnMetadata
        local function AdvanceSparse(seconds)
            now = now + seconds
            for callback, deadline in pairs(timers) do
                if deadline <= now then timers[callback] = nil callback(M) end
            end
            FlushMetadata()
        end
        local count, titleText, instance = {}, "First title", 401
        local weak, serial = setmetatable({}, { __mode = "v" }), 0
        local function TrackData(lines)
            local data = { dataInstanceID = instance, lines = lines }
            serial = serial + 1
            weak[serial] = data
            return data
        end
        C_TooltipInfo.GetUnit = function(unit)
            count[unit] = (count[unit] or 0) + 1
            local lines = { { type = 2, leftText = "Enemy" } }
            if titleText then lines[2] = { type = 0, leftText = titleText } end
            lines[3], lines[4] = { type = 17, leftText = "Quest" }, { type = 8, leftText = "3/8 enemies defeated" }
            return TrackData(lines)
        end
        local unit = "nameplate4"
        X.OnUnit(M, "UNIT_NAME_UPDATE", unit)
        local firstLease = serial
        collectgarbage("collect")
        assert(weak[firstLease], "active native tooltip instance lost its backing data")
        local beforeQuest = count[unit]
        for i = 1, 21 do
            questLog()
            if i % 4 == 0 or i == 21 then FlushMetadata() end
        end
        assert(count[unit] == beforeQuest, "quest-log churn queried a title-only NPC")
        local sparse = assert(ctx.callbacks.TOOLTIP_DATA_UPDATE)
        local phase = assert(ctx.callbacks.UNIT_PHASE)
        titleText = "Late title"
        sparse(M, "TOOLTIP_DATA_UPDATE", 402)
        sparse(M, "TOOLTIP_DATA_UPDATE", secret)
        FlushMetadata()
        assert(count[unit] == beforeQuest, "unrelated or secret tooltip ID queried a bound title")
        sparse(M, "TOOLTIP_DATA_UPDATE", 401)
        sparse(M, "TOOLTIP_DATA_UPDATE", 401)
        FlushMetadata()
        assert(count[unit] == beforeQuest + 1 and title.text == titleText, "sparse title was not delivered once")
        collectgarbage("collect")
        assert(not weak[firstLease], "replaced native tooltip object remained retained")
        local other = "nameplate5"
        local _, otherNPC, otherHealth, otherCast = Plate(other)
        P.UnitKinds[otherNPC] = "neutralNpc"
        P.FriendlyNames.KeepsQuestText = function(frame) return frame == otherNPC end
        Apply(otherNPC, otherHealth, otherCast, "enemy", other)
        local beforeOther = count[other]
        questLog()
        FlushMetadata()
        assert(count[unit] == beforeQuest + 1 and count[other] == beforeOther + 1,
            "mixed profile did not limit quest events to the visible quest consumer")
        sparse(M, "TOOLTIP_DATA_UPDATE", 401)
        FlushMetadata()
        assert(count[unit] == beforeQuest + 2 and count[other] == beforeOther + 2,
            "two bindings sharing a data instance did not both update")
        titleText = "Phased title"
        phase(M, "UNIT_PHASE", unit)
        FlushMetadata()
        assert(title.text == titleText and count[other] == beforeOther + 2, "phase refresh skipped or touched a sibling")
        local previousTarget = target
        target, npc.unit = unit, unit
        function plates.nameplate4:CanBeAccessedInContext() return true end
        function npc:CanBeAccessedInContext() return true end
        titleText = "Target alias phase"
        phase(M, "UNIT_PHASE", "target")
        FlushMetadata()
        assert(title.text == titleText, "phase delivery through a target alias missed its bound plate")
        titleText = "Target alias name"
        ctx.callbacks.UNIT_NAME_UPDATE(M, "UNIT_NAME_UPDATE", "target")
        assert(title.text == titleText, "name delivery through a target alias missed its bound plate")
        target = previousTarget
        titleText = "Quest turned in"
        ctx.callbacks.QUEST_TURNED_IN(M, "QUEST_TURNED_IN", 123)
        FlushMetadata()
        assert(title.text == titleText, "a real quest transition did not invalidate the title")
        instance, titleText = secret, nil
        C_TooltipInfo.GetUnit = function(key)
            count[key] = (count[key] or 0) + 1
            local lines = { { type = 2 } }
            if titleText then lines[2] = { type = 0, leftText = titleText } end
            return TrackData(lines)
        end
        X.OnUnit(M, "UNIT_NAME_UPDATE", unit)
        local missingReads = count[unit]
        for i = 1, 20 do sparse(M, "TOOLTIP_DATA_UPDATE", 1000 + i) FlushMetadata() end
        assert(count[unit] == missingReads, "unrelated notifications synchronously probed an unidentified tooltip")
        AdvanceSparse(.5)
        assert(count[unit] == missingReads + 1, "one unidentified burst performed more than one probe")
        instance, titleText = 901, "Recovered"
        sparse(M, "TOOLTIP_DATA_UPDATE", 901)
        AdvanceSparse(.5)
        assert(count[unit] == missingReads + 1, "persistently unresolved instance did not back off")
        AdvanceSparse(.5)
        assert(title.text == titleText, "a sparse lookup with an initially unavailable ID never recovered")
        titleText = "Global update"
        sparse(M, "TOOLTIP_DATA_UPDATE", nil)
        FlushMetadata()
        assert(title.text == titleText, "global sparse delivery failed")
        P.FriendlyNames.KeepsQuestText = function() return false end
        Apply(otherNPC, otherHealth, otherCast, "enemy", other)
        titleText = nil
        X.OnUnit(M, "UNIT_NAME_UPDATE", unit)
        titleText = "Missing text recovered"
        beforeOther = count[other]
        sparse(M, "TOOLTIP_DATA_UPDATE", secret)
        FlushMetadata()
        assert(title.text == titleText and count[other] == beforeOther,
            "invalid sparse delivery missed the missing title or reparsed a populated sibling")
        local lastLease = serial
        sparse(M, "TOOLTIP_DATA_UPDATE", 901)
        local restore = P.ExtensionLayout.Restore
        P.ExtensionLayout.Restore = function() return false end
        X.Restore(npc)
        collectgarbage("collect")
        assert(not weak[lastLease], "a protected layout restore retained the released native tooltip")
        P.ExtensionLayout.Restore = restore
        X.Restore(otherNPC)
        X.OnCombatEnded()
        instance, titleText = 902, "Rebound"
        Apply(npc, npcHealth, npcCast, "enemy", unit)
        local rebound = count[unit]
        FlushMetadata()
        sparse(M, "TOOLTIP_DATA_UPDATE", 901)
        FlushMetadata()
        assert(title.text == titleText and count[unit] == rebound, "released binding or stale ID repainted a pooled NPC")
        local oldConfig = M.config
        M.config = { enemy = true, look = 3, enemyExtraTextTitle = true, enemyHideMounted = true }
        X.Configure(M)
        local hiddenToken = "nameplate27"
        local _, hiddenNPC, hiddenHealth, hiddenCast = Plate(hiddenToken)
        P.UnitKinds[hiddenNPC] = "enemyNpc"
        instance, titleText = 927, "Before hiding"
        Apply(hiddenNPC, hiddenHealth, hiddenCast, "enemy", hiddenToken)
        local lease, visibleReads = serial, count[hiddenToken]
        assert(hiddenNPC.labels[1] and hiddenNPC.labels[1].text == titleText, "fixture needs a visible enemy title")
        mounted = true
        ctx.callbacks.PLAYER_MOUNT_DISPLAY_CHANGED(M,"PLAYER_MOUNT_DISPLAY_CHANGED")
        assert(hiddenNPC.alpha == 0, "fixture needs an enemy hidden by its public load condition")
        collectgarbage("collect")
        assert(not weak[lease], "a binding hidden by load rules retained its native tooltip")
        sparse(M, "TOOLTIP_DATA_UPDATE", 927)
        FlushMetadata()
        X.OnUnit(M, "UNIT_NAME_UPDATE", hiddenToken)
        assert(count[hiddenToken] == visibleReads, "a hidden plate read its tooltip for sparse or name data")
        titleText = "Visible again"
        mounted = false
        ctx.callbacks.PLAYER_MOUNT_DISPLAY_CHANGED(M,"PLAYER_MOUNT_DISPLAY_CHANGED")
        assert(hiddenNPC.alpha == 1 and hiddenNPC.labels[1].text == titleText and count[hiddenToken] == visibleReads + 1,
            "showing a filtered plate did not refresh its title once")
        X.Restore(hiddenNPC)
        mounted = true
        ctx.callbacks.PLAYER_MOUNT_DISPLAY_CHANGED(M, "PLAYER_MOUNT_DISPLAY_CHANGED")
        Apply(hiddenNPC, hiddenHealth, hiddenCast, "enemy", hiddenToken)
        assert(count[hiddenToken] == visibleReads + 1, "first binding queried an already filtered plate")
        mounted = false
        ctx.callbacks.PLAYER_MOUNT_DISPLAY_CHANGED(M, "PLAYER_MOUNT_DISPLAY_CHANGED")
        assert(count[hiddenToken] == visibleReads + 2 and hiddenNPC.labels[1].text == titleText,
            "a plate first acquired while filtered did not paint its initial title on reveal")
        X.Restore(hiddenNPC)
        M.config = oldConfig
        X.Configure(M)
        Apply(npc, npcHealth, npcCast, "enemy", unit)
        P.FriendlyNames.KeepsQuestText = function() return false end
    end
    C_TooltipInfo.GetUnit = function()
        return { lines = { { type = 2, leftText = "Enemy" }, { type = 0, leftText = secret } } }
    end
    X.OnUnit(M, "UNIT_NAME_UPDATE", "nameplate4")
    assert(title:IsShown() and IsSecret(title.text), "a secret NPC title did not reach its label unread")
    C_TooltipInfo.GetUnit = getUnit
    X.OnUnit(M, "UNIT_NAME_UPDATE", "nameplate4")
    assert(title:IsShown() and title.text == "Enemy title", "name update did not restore the public title")
    -- An open-world innkeeper can keep a secret identity: its title still
    -- shows, quest text needs a public identity, PvP instances read nothing.
    P.FriendlyNames.KeepsQuestText = function() return true end
    identityRestricted = true
    X.OnUnit(M, "UNIT_NAME_UPDATE", "nameplate4")
    assert(title:IsShown() and title.text == "Enemy title" and not label:IsShown(),
        "a restricted identity hid the NPC title or kept its quest text")
    P.Roles.inInstance, P.Roles.instanced = true, false
    X.OnUnit(M, "UNIT_NAME_UPDATE", "nameplate4")
    assert(not title:IsShown(), "a PvP instance read a restricted NPC title")
    P.Roles.inInstance, P.Roles.instanced, identityRestricted = nil, nil, false
    X.OnUnit(M, "UNIT_NAME_UPDATE", "nameplate4")
    assert(title:IsShown() and label:IsShown(), "a public identity did not bring title and quest text back")
    X.Restore(npc)
    assert(not label:IsShown() and not title:IsShown(), "a released plate retained its text")
end
-- Roster-only refresh calls the group filter without a full plate paint.
-- The cast effect releases the native name before the group filter claims it.
do
    local grouped = true
    UnitInParty = function() return grouped end
    UnitInRaid = function() return false end
    P.Mode.GROUP_NAMES_ONLY = 3
    P.Mouseover = { textInUse = false }
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/FriendlyNames.lua"))("Plates", P)
    local names = P.FriendlyNames
    names.Bind(M)
    M.active, M.friendlyNames, M.units = true, {}, {}
    M.config = { friendly = true, look = 3, friendlyNamesOnly = 3, friendlyNameDuringCast = 3 }
    local unit = "nameplate8"
    local _, player, bar, castingBar = Plate(unit, true)
    local native = player.name
    player.isPlayer, P.UnitKinds[player], M.units[bar] = true, "friendlyPlayer", unit
    native:SetAlpha(.8)
    casts[unit] = true
    X.Configure(M)
    Apply(player, bar, castingBar, "friendly", unit)
    assert(native.alpha == 0)
    names.Filter(player, "friendly")
    assert(native.alpha == 0, "checking an unfiltered group member canceled the active cast fade")
    grouped = false
    names.Filter(player, "friendly")
    assert(M.friendlyNames[native] == .8 and native.alpha == 0, "roster refresh captured the cast's hidden alpha")
    local getAlpha = native.GetAlpha
    native.GetAlpha = function() error("casting sampled the hidden native group-filter alpha") end
    Apply(player, bar, castingBar, "friendly", unit)
    native.GetAlpha = getAlpha
    grouped = true
    names.Filter(player, "friendly")
    assert(native.alpha == 0 and M.friendlyNames[native] == nil, "joining mid-cast canceled the configured cast fade")
    casts[unit] = nil
    X.OnCast(M, "UNIT_SPELLCAST_STOP", unit, secret, secret, 123)
    assert(native.alpha == .8 and M.friendlyNames[native] == nil, "a cast hid the released group member")
    grouped = false
    names.Filter(player, "friendly")
    native.forbidden, grouped = true, true
    names.Filter(player, "friendly")
    assert(M.friendlyNames[native] == .8 and M.pendingPlates[player], "a denied restore forgot its native alpha")
    native.forbidden = false
    names.Filter(player, "friendly")
    assert(native.alpha == .8 and M.friendlyNames[native] == nil, "a released plate kept the group filter's zero")
end
-- The native name-cache event updates health, even on a visible enemy bar
-- whose name was unavailable when Blizzard assigned the frame.
do
    local names = P.FriendlyNames
    P.Mode.ALL_NAMES_ONLY, P.Mode.NPC_NAMES_ONLY = 2, 4
    P.SkinScopes = { suppressed = {} }
    S.NameplateUnits = { "nameplate1", "nameplate9" }
    M.config = { enemy = true, enemySkinEnabled = true, enemyNameVisible = true, enemyNameMouseover = false,
        enemyPlateNameOnly = false, friendlyNamesOnly = 1, look = 3 }
    local unit = "nameplate9"
    local plate, npc = Plate(unit)
    npc.unit, npc.optionTable, P.UnitKinds[npc] = unit, {}, "enemyNpc"
    function npc.name:GetText() return self.text end
    function npc:ShouldShowName() return not self.widgetsOnlyMode end
    function plate:CanBeAccessedInContext() return true end
    function npc:CanBeAccessedInContext() return not self.inaccessible end
    local repaired = 0
    securecallfunction = function(f, ...) return f(...) end
    CompactUnitFrame_UpdateName = function(f)
        repaired = repaired + 1
        f.name:SetText(UnitName(f.unit))
    end
    names.ConfigureNameOnly()
    X.Configure(M)
    local update = assert(ctx.callbacks.UNIT_NAME_UPDATE, "Show name on an enemy health bar never registered the name-cache event")
    identities[unit] = "Murloc Tidehunter"
    update(M, "UNIT_NAME_UPDATE", "nameplate404")
    npc.name:Hide()
    update(M, "UNIT_NAME_UPDATE", unit)
    npc.name:Show()
    npc.widgetsOnlyMode = true
    update(M, "UNIT_NAME_UPDATE", unit)
    assert(repaired == 0 and npc.name.text == nil, "repaired a hidden, widgets-only or unmapped plate")
    npc.widgetsOnlyMode = false
    update(M, "UNIT_NAME_UPDATE", unit)
    assert(npc.name.text == identities[unit] and repaired == 1, "late enemy name missing from the visible health bar")
    update(M, "UNIT_NAME_UPDATE", unit)
    assert(repaired == 1, "rewrote a populated native name")
    npc.name:SetText(nil)
    M.config.enemyNameVisible = nil -- legacy default-on configuration
    names.ConfigureNameOnly()
    assert(names.repairKinds.enemyNpc, "an enemy bar missed the initial name check")
    names.RepairMissing(npc, unit)
    assert(npc.name.text == identities[unit] and repaired == 2, "name-cache event before frame mapping left the health bar blank")
    local filter = assert(ctx.unitFilters.UNIT_NAME_UPDATE, "name-cache event lacks unit filter")
    local hasTarget = false
    for _, token in ipairs(filter) do if token == "target" then hasTarget = true end end
    assert(hasTarget and #S.NameplateUnits == 2, "target alias absent from the native filter or shared units modified")
    target = unit
    npc.name:SetText(nil)
    M.activeUnits[unit] = uf
    update(M, "UNIT_NAME_UPDATE", "target")
    M.activeUnits[unit] = npc
    npc.inaccessible = true
    update(M, "UNIT_NAME_UPDATE", "target")
    npc.inaccessible = false
    assert(repaired == 2 and not npc.name.text, "target alias used an inaccessible or recycled frame")
    update(M, "UNIT_NAME_UPDATE", "target")
    assert(repaired == 3 and npc.name.text == identities[unit], "target alias did not repair the selected canonical plate")
    M.config.enemyNameVisible = false
    names.ConfigureNameOnly()
    X.Configure(M)
    assert(not ctx.callbacks.UNIT_NAME_UPDATE, "hidden full-bar names kept the name-cache subscriber")
end
print("nameplate extensions contract passed: lifecycle, pooling, secrets, layout, click permission, range budget, text, restoration, visibility and opacity")
