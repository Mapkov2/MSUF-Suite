local root = assert(arg[1])
local FONT, OVERRIDE = "MSUF.ttf", "CombatOverride.ttf"
local CVAR = "floatingCombatTextCombatDamage_v2"
local WORLD_SCALE = "WorldTextScale_v2"
local NOOP = function() end
local cvar, font, now = "1", FONT, 0
local worldScale, worldWrites, clampWorldScale, inCombat = "1.25", 0, false, false
local frames, fontWrites, paints, anchors, clockReads, styleCalls = 0, 0, 0, 0, 0, 0
local secret = setmetatable({}, {
    __tostring = function() error("secret converted in Lua") end,
    __concat = function() error("secret concatenated in Lua") end,
    __add = function() error("secret arithmetic in Lua") end,
    __lt = function() error("secret compared in Lua") end,
    __le = function() error("secret compared in Lua") end,
})
local wideAmount = "12345678901234567890"
local methods = {
    SetFrameStrata = NOOP, EnableMouse = NOOP, SetFrameLevel = NOOP, GetFrameLevel = function() return 0 end,
    SetJustifyH = NOOP, SetJustifyV = NOOP, SetTextColor = NOOP,
    SetOrder = NOOP, SetFromAlpha = NOOP, SetToAlpha = NOOP,
    SetDuration = NOOP, SetStartDelay = NOOP,
}
local function New()
    return setmetatable({ events = {}, scripts = {} }, { __index = methods })
end
function methods:SetScript(event, fn)
    assert(event ~= "OnUpdate", "Combat text must use native animations")
    self.scripts[event] = fn
end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:RegisterUnitEvent(event, unit) self.events[event] = unit end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() wipe(self.events) end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:ClearAllPoints() self.anchor = nil end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetAllPoints(frame) self.bounds = frame end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
function methods:SetClipsChildren(value) self.clipsChildren = value end
function methods:SetPoint(point, plate, _, x, y)
    assert(not plate.forbidden)
    self.point, self.anchor, anchors = point, plate, anchors + 1
    self.x, self.y = x, y
end
function methods:SetOffset(x, y) self.offsetX, self.offsetY = x, y end
function methods:CreateAnimationGroup() return New() end
function methods:CreateAnimation() return New() end
-- Native animation calls, counted for the warm render budget below.
local animationCalls = { Play = 0, Stop = 0, Restart = 0 }
function methods:Play() animationCalls.Play = animationCalls.Play + 1; self.playing = true end
function methods:Stop() assert(self.playing); animationCalls.Stop = animationCalls.Stop + 1; self.playing = false end
-- AnimationGroup:Restart (SimpleAnimGroupAPIDocumentation) is Stop plus Play.
function methods:Restart()
    assert(self.playing, "Restart reached an idle line")
    animationCalls.Restart = animationCalls.Restart + 1
end
function methods:SetFormattedText(format, amount)
    if format == "%s" then assert(rawequal(amount, secret) or amount == wideAmount) end
    self.format, self.amount, paints = format, amount, paints + 1
end
function methods:SetText(text) self.label, paints = text, paints + 1 end

UIParent = New()
wipe = function(map) for key in pairs(map) do map[key] = nil end return map end
GetTime = function() clockReads = clockReads + 1; return now end
UnitName = function() return "Tester" end
GetRealmName = function() return "Test realm" end
Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 }, Damageclass = { MaskPhysical = 1 },
    PowerType = { Mana = 0, Rage = 1, ComboPoints = 4 } }
C_Spell = { IsSpellHarmful = function(spellID) return spellID == 11 end }
C_CVar = {
    GetCVar = function(key)
        assert(key == CVAR or key == WORLD_SCALE)
        return key == WORLD_SCALE and worldScale or cvar
    end,
    SetCVar = function(key, value)
        assert(key == CVAR or key == WORLD_SCALE)
        if key == WORLD_SCALE then
            assert(not inCombat, "Wrote the world-text CVar during combat")
            if tonumber(value) == 1000 then value = clampWorldScale and "5.000000" or "1000.000000" end
            worldScale = value
            worldWrites = worldWrites + 1
        else
            cvar = value
        end
        return true
    end,
}
local level, xp, maxXP, activeEvent, eventReads = 20, 880, 1000, nil, 0
UnitLevel = function() return level end
UnitXP = function() return xp end
UnitXPMax = function() return maxXP end
local pendingTimers = {}
C_Timer = { After = function(delay, callback)
    pendingTimers[#pendingTimers + 1] = { due = now + delay, callback = callback }
end }
local power, powerMax = { [0] = 80, [4] = 1 }, { [0] = 100, [4] = 5 }
UnitPower = function(unit, powerType)
    assert(unit == "player")
    return power[powerType or 0] or 0
end
UnitPowerMax = function(unit, powerType)
    assert(unit == "player")
    return powerMax[powerType] or 0
end
local honor, honorMax, honorLevel = 980, 1000, 8
local activeUnit, unitWrites, eventPowerToken = nil, 0, secret
C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
C_CombatText = { GetCurrentEventInfo = function()
    assert(activeEvent == "COMBAT_TEXT_UPDATE", "Read event data outside its synchronous dispatch")
    eventReads = eventReads + 1
    return secret, eventPowerToken
end, GetActiveUnit = function() return activeUnit end,
    SetActiveUnit = function(unit) activeUnit, unitWrites = unit, unitWrites + 1 end,
}
local function Plate(token)
    return { GetUnit = function() return token end }
end
local first, second, friendly = Plate("nameplate1"), Plate("nameplate2"), Plate("nameplate3")
local plates = { target = first, nameplate1 = first, nameplate2 = second, nameplate3 = friendly }
C_NamePlate = {
    GetNamePlateForUnit = function(token) return plates[token] end,
    GetNamePlates = function() return { plates.nameplate1, plates.nameplate2, friendly } end,
}
UnitCanAttack = function(_, unit) return unit ~= "nameplate3" end

local S = { instances = {} }
local NS = {
    Suite = S, RootDB = {}, Client = { isForever = true, SupportsEvent = function() return true end },
    Public = function(value) return not rawequal(value, secret) end,
    IsSecret = function(value) return rawequal(value, secret) end,
    Safety = { IsForbidden = function(plate) return plate.forbidden == true end },
    Dispatch = function(fn, ...) return fn(...) end,
    InCombat = function() return inCombat end,
    Skin = { Release = NOOP },
}
_G.MSUFSuite = NS
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeCombatText.lua"))("MSUF_Suite", NS)
S.catalog = NS.SuiteCatalog
local id = "floatingCombatText"
local spec = assert(S.catalog[id])
assert(spec.defaultEnabled and spec.rules.enabled.default and spec.available() and spec.cvars[CVAR])
assert(spec.rules.font.font and spec.rules.font.default == "", "Missing inherited font choice")
NS.Client.isForever = false
assert(spec.available(), "Combat text must be available on Retail")
NS.Client.isForever = true
S.CreateFrame = function() frames = frames + 1; return New() end
S.CreateFontString = New
S.HonorProgress = function()
    if NS.Finite(honor) and NS.Finite(honorLevel) then return honor, honorMax, honorLevel end
end
S.Public = NS.Public
NS.Finite = function(value) return type(value) == "number" end
NS.Text = function(text) return text end
S.RGB = function() return 1, .8, .1 end
S.GlobalFontPath = function() styleCalls = styleCalls + 1; return font end
S.ResolveFont = function(key) if key == "CombatTextFont" then return OVERRIDE end end
S.SetFont = function(text, path, size)
    assert(path == font or path == OVERRIDE)
    text.fontPath, text.fontSize, fontWrites = path, size, fontWrites + 1
end
local P = {}
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", P)
assert(loadfile(root .. "/MSUF_Suite_Modules/Timers.lua"))("MSUF_Suite_Modules", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/FloatingTextDisplay.lua"))("MSUF_Suite_QualityOfLife", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/FloatingTextGains.lua"))("MSUF_Suite_QualityOfLife", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/FloatingCombatText.lua"))("MSUF_Suite_QualityOfLife", P)
local M = assert(S.instances[id])
assert(frames == 0 and fontWrites == 0 and cvar == "1", "Inactive module performed work")
M.config = {}
for key, rule in pairs(spec.rules) do M.config[key] = rule.default end
M.context, M.active = S.NewContext(id), true
M:Enable()
assert(activeUnit == "player" and unitWrites == 1, "Cold gain stream was never initialized")
local D = M.display
M.config.showAvoidance = false
M:Refresh()
local function CheckTextGeometry()
    for _, slot in ipairs(D.slots) do
        assert(slot.frame.clipsChildren == false, "Animation holder can clip its text")
        for _, text in ipairs({ slot.normal, slot.critical }) do
            assert(text.point == "CENTER" and text.anchor == slot.frame and not text.bounds,
                "Text has fixed anchor bounds that truncate large amounts")
            assert(not text.width and not text.height, "Text must retain native content sizing")
            assert(text.wordWrap == false and text.nonSpaceWrap == false, "Damage numbers can wrap")
        end
    end
end
CheckTextGeometry()
local context = M.context
local function EmitOn(frame, event, ...)
    local unit = frame.events[event]
    if unit and (unit == true or unit == (...)) then frame.scripts.OnEvent(frame, event, ...) end
end
local function Emit(event, ...)
    activeEvent = event
    if context.frame then EmitOn(context.frame, event, ...) end
    if context.directFrame then EmitOn(context.directFrame, event, ...) end
    activeEvent = nil
end
local function FlushTimers()
    local timers = pendingTimers
    pendingTimers = {}
    for _, timer in ipairs(timers) do
        now = math.max(now, timer.due)
        timer.callback()
    end
end
local function CheckSpacing()
    for index, entry in ipairs(D.slots) do
        if entry.anchor then
            local visible = 0
            for otherIndex, other in ipairs(D.slots) do
                if entry.anchor == other.anchor then
                    visible = visible + 1
                    if otherIndex > index then
                        local bottom = entry.frame.y + math.min(0, entry.move.offsetY)
                        local top = entry.frame.y + entry.frame.height + math.max(0, entry.move.offsetY)
                        local otherBottom = other.frame.y + math.min(0, other.move.offsetY)
                        local otherTop = other.frame.y + other.frame.height + math.max(0, other.move.offsetY)
                        assert(top < otherBottom or otherTop < bottom,
                            "Damage numbers share overlapping animation paths")
                    end
                end
            end
            assert(visible <= D.placements[entry.placement].rows, "Burst grew beyond reserved lines")
        end
    end
end
local function Hit(unit, flag)
    Emit("UNIT_COMBAT", unit, "WOUND", flag or "", secret, 1)
    CheckSpacing()
end
assert(cvar == "0" and context.frame.events.UNIT_COMBAT == "target")
Hit("target")
assert(paints == 0 and clockReads == 0, "An unmatched hit spent work or appeared")
Emit("PLAYER_SWING", 2, Enum.PlayerSwingType.MainHand)
Hit("target", "CRITICAL")
assert(paints == 1 and D.slots[1].text == D.slots[1].critical
    and D.slots[1].text.fontSize == M.config.fontSize * M.config.critScale / 100)
Hit("target")
assert(paints == 1, "One swing admitted a second hit")
Emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 99)
Hit("target")
assert(paints == 1, "A helpful cast admitted damage")
Emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 11)
Hit("target")
Hit("target")
assert(paints == 2, "A harmful cast must admit one hit")
Emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 11)
plates.target = second
Emit("PLAYER_TARGET_CHANGED")
Hit("target")
assert(paints == 2, "A cast was carried over to a new target")
Emit("PLAYER_SWING", 2, Enum.PlayerSwingType.OffHand)
now = 3
Hit("target")
assert(paints == 2, "An expired swing admitted a hit")

M.config.hitSource = 2
M:Refresh()
assert(context.directFrame.events.UNIT_COMBAT and not context.frame.events.UNIT_COMBAT)
assert(not context.directFrame.events.PLAYER_SWING and not context.frame.events.UNIT_SPELLCAST_SUCCEEDED)
local created, styled, reads, fontResolves = frames, fontWrites, clockReads, styleCalls
for _ = 1, 32 do Hit("nameplate1") end
-- Render budget of a warm hit on a full four-line plate lane, which recycles
-- its oldest line: VM instructions of the owned event and render files (the
-- 2026-11-23 Retail raid trace sent 3,653 such hits in 30 s). Measured 182,
-- previously 231 (shifted row search, Stop plus Play, Lua secret wrapper).
local WARM_HIT_INSTRUCTIONS = 184
local owned = {
    ["@" .. root .. "/MSUF_Suite_QualityOfLife/FloatingCombatText.lua"] = true,
    ["@" .. root .. "/MSUF_Suite_QualityOfLife/FloatingTextDisplay.lua"] = true,
}
local instructions = 0
debug.sethook(function()
    local info = debug.getinfo(2, "S")
    if info and owned[info.source] then instructions = instructions + 1 end
end, "", 1)
for _ = 1, 64 do Hit("nameplate1") end
debug.sethook()
assert(instructions / 64 <= WARM_HIT_INSTRUCTIONS, ("A warm hit ran %.1f VM instructions, budget %d")
    :format(instructions / 64, WARM_HIT_INSTRUCTIONS))
local positionWrites = anchors
local played, stopped, restarted = animationCalls.Play, animationCalls.Stop, animationCalls.Restart
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 96 do Hit("nameplate1") end
local allocated = collectgarbage("count") - before
collectgarbage("restart")
assert(paints == 194 and frames == created and fontWrites == styled and styleCalls == fontResolves)
assert(clockReads == reads and anchors == positionWrites, "Warm all-hits path repeated work")
assert(allocated < 0.25, "Warm all-hits path allocated Lua data")
-- The recycled line restarts its animation in one native call (the trace
-- above: 3,619 Stop plus 3,653 Play calls).
assert(animationCalls.Restart - restarted == 96 and animationCalls.Stop == stopped
    and animationCalls.Play == played, "A recycled line was stopped and played instead of restarted")
Hit("target")
Hit("nameplate2")
Hit("nameplate3")
Hit("target", "ABSORB")
Hit(secret)
Emit("UNIT_COMBAT", "target", "HEAL", "", secret, 1)
Emit("UNIT_COMBAT", "target", secret, "", secret, 1)
assert(paints == 195, "Wrong target alias, ally, healing, mitigation or secret token was painted")
local slot = D.slots[D.cursor]
slot.animation.playing = false
slot.animation.scripts.OnFinished(slot.animation)
assert(not slot.frame.shown and not D.occupied[second], "Finished animation leaked a plate")
Emit("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not D.occupied[first])
for _, entry in ipairs(D.slots) do assert(not entry.frame.shown) end

-- Reserve complete animation paths, reuse the oldest burst entry and fill holes.
local function CheckOwners()
    for plate, head in pairs(D.head) do
        local mask, count, entry, previous = 0, 0, head, nil
        while entry do
            assert(entry.anchor == plate and entry.older == previous, "Broken plate queue")
            mask, count = mask + entry.rowBit, count + 1
            assert(count <= 4, "Plate queue has a cycle or too many entries")
            previous, entry = entry, entry.newer
        end
        assert(mask == D.occupied[plate] and previous == D.tail[plate], "Stale plate ownership")
    end
    for plate in pairs(D.occupied) do assert(D.head[plate] and D.tail[plate]) end
    for _, entry in ipairs(D.slots) do
        if entry.anchor then
            local linked = D.head[entry.anchor]
            while linked and linked ~= entry do linked = linked.newer end
            assert(linked, "Active slot is missing from its plate queue")
        else
            assert(not entry.older and not entry.newer, "Released slot retained links")
        end
    end
    CheckSpacing()
end
local function Finish(entry)
    entry.animation.playing = false
    entry.animation.scripts.OnFinished(entry.animation)
    CheckOwners()
end
for _ = 1, 4 do Hit("target", "CRITICAL") end
CheckOwners()
local oldest = D.head[second]
local oldestLine = oldest.row
Hit("target")
assert(D.tail[second] == oldest and oldest.row == oldestLine, "Full burst did not reuse its oldest line")
CheckOwners()
local middle = D.head[second].newer
local freeLine = middle.row
Finish(middle)
Hit("target", "CRITICAL")
assert(D.slots[D.cursor].row == freeLine, "A finished middle line was not reused")
CheckOwners()
-- More than six simultaneous enemies forces global pool recycling as well.
for index = 4, 11 do
    local unit = "nameplate" .. index
    plates[unit] = Plate(unit)
    Emit("NAME_PLATE_UNIT_ADDED", unit)
    for _ = 1, 5 do Hit(unit, "CRITICAL"); CheckOwners() end
end
for index = #D.slots, 1, -1 do
    local entry = D.slots[index]
    if entry.anchor then Finish(entry) end
end
assert(not next(D.occupied) and not next(D.head) and not next(D.tail),
    "Animation completion retained a plate queue")
for _ = 1, 4 do Hit("target") end
Emit("NAME_PLATE_UNIT_REMOVED", "nameplate2")
CheckOwners()
assert(not next(D.occupied) and not next(D.head) and not next(D.tail),
    "Nameplate removal retained reserved lines")
Emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
Emit("PLAYER_TARGET_CHANGED")

assert(spec.rules.hideBlizzardWorldText and spec.rules.hideBlizzardWorldText.default == false,
    "Missing opt-in Forever world-text setting")
assert(worldScale == "1.25" and worldWrites == 0, "Default settings changed native world text")

local function CheckWorldTextReplacement()
    local baselineXP = xp
    M.config.hideBlizzardWorldText, M.config.hideBlizzard = true, false
    M:Refresh()
    assert(tonumber(worldScale) == 1000 and worldWrites == 1 and cvar == "1",
        "World-text replacement depends on the separate damage setting")
    assert(context.directFrame.events.PLAYER_XP_UPDATE and M.config.showXP == false,
        "Suite XP did not start without changing the stored XP preference")

    inCombat = true
    Emit("PLAYER_REGEN_DISABLED")
    xp = xp + 20
    Emit("PLAYER_XP_UPDATE", "player")
    FlushTimers()
    assert(D.slots[D.cursor].text.format == "+%s XP" and D.slots[D.cursor].text.amount == 20,
        "Suite XP did not render with native world text hidden in combat")
    assert(tonumber(worldScale) == 1000 and worldWrites == 1, "Combat changed the world-text override")
    inCombat = false
    Emit("PLAYER_REGEN_ENABLED")

    -- Recreate the controller's memory with the persisted override still present.
    M:Disable()
    M:Enable()
    assert(tonumber(worldScale) == 1000 and worldWrites == 1, "Reload reapplied the unchanged override")
    M.config.hideBlizzardWorldText = false
    M:Refresh()
    assert(worldScale == "1.25" and worldWrites == 2, "Turning off the override lost the original world-text scale")
    assert(not context.directFrame.events.PLAYER_XP_UPDATE, "Restoring Blizzard kept the forced Suite XP listener")

    clampWorldScale, M.config.hideBlizzardWorldText = true, true
    M:Refresh()
    assert(worldScale == "1.25" and not context.directFrame.events.PLAYER_XP_UPDATE,
        "A clamped CVar left a partial override or duplicate XP")
    clampWorldScale = false
    M:Refresh()
    assert(tonumber(worldScale) == 1000 and context.directFrame.events.PLAYER_XP_UPDATE,
        "World-text override could not recover from a clamped CVar")
    worldScale = "1.6" -- A different owner changed the CVar.
    Emit("CVAR_UPDATE", "WORLDTEXTSCALE_V2")
    assert(not context.directFrame.events.PLAYER_XP_UPDATE, "External CVar edit brought back duplicate XP")
    M.config.hideBlizzardWorldText, M.config.hideBlizzard = false, true
    M:Refresh()
    assert(worldScale == "1.6", "Releasing the override erased a later external edit")

    M.config.hideBlizzardWorldText = true
    M:Refresh()
    inCombat = true
    Emit("PLAYER_LOGOUT")
    assert(tonumber(worldScale) == 1000, "A combat reload lost the active override")
    inCombat = false
    Emit("PLAYER_LOGOUT")
    assert(worldScale == "1.6", "Logging out left Blizzard world text hidden")
    M.config.hideBlizzardWorldText = false
    M:Refresh()
    xp = baselineXP
end
CheckWorldTextReplacement()

font = "New MSUF profile.ttf"
M.config.hideBlizzard = false
M:Refresh()
assert(D.slots[1].normal.fontPath == font and cvar == "1")
M.config.font = "CombatTextFont"
M:Refresh()
assert(D.slots[1].normal.fontPath == OVERRIDE and D.slots[1].critical.fontPath == OVERRIDE)
font = "Changed global MSUF font.ttf"
M:Refresh()
assert(D.slots[1].normal.fontPath == OVERRIDE, "Global font overrode the module's choice")
M.config.font = ""
M:Refresh()
assert(D.slots[1].normal.fontPath == font and D.slots[1].critical.fontPath == font)
M.config.hideBlizzard = true
M:Refresh()
assert(cvar == "0")
for _, override in ipairs({ "", "CombatTextFont" }) do
    M.config.font, M.config.fontSize, M.config.critScale = override, 48, 200
    M:Refresh()
    for index = 1, 48 do
        local flag = index <= 24 and "CRITICAL" or ""
        Emit("UNIT_COMBAT", "target", "WOUND", flag, wideAmount, 1)
        local entry = D.slots[D.cursor]
        local expected = flag == "CRITICAL" and entry.critical or entry.normal
        assert(entry.text == expected and entry.text.shown ~= false)
        assert(entry.text.amount == wideAmount and entry.text.fontSize == (flag == "CRITICAL" and 96 or 48),
            "Pool reuse lost the full amount or critical size")
        CheckTextGeometry()
        CheckSpacing()
    end
end
local function CheckForeverGainFeeds()
    local previousLevel, previousXP = level, xp
    M.config.hideBlizzardWorldText = true
    M.config.showHonor, M.config.showPower, M.config.showCombatState = true, true, true
    M:Refresh()
    inCombat = true
    Emit("PLAYER_REGEN_DISABLED")
    assert(D.slots[D.cursor].text.label == "Entering combat")

    -- The level signal completes a rollover even with no second XP update.
    xp = 10
    Emit("PLAYER_XP_UPDATE", "player")
    level = level + 1
    Emit("PLAYER_LEVEL_UP", level)
    FlushTimers()
    local foundXP, foundLevel
    for _, slot in ipairs(D.slots) do
        if slot.anchor then
            local format, amount = slot.text.format, slot.text.amount
            if format == "+%s XP" and amount == maxXP - previousXP + 10 then foundXP = true end
            if format == "Level %d" and amount == level then foundLevel = true end
        end
    end
    assert(foundXP, "Level-up rollover lost XP when no second XP update arrived")
    assert(foundLevel, "The level-up notification was lost when Blizzard world text was hidden")
    local count = paints
    Emit("CHAT_MSG_COMBAT_XP_GAIN", secret)
    Emit("PLAYER_XP_UPDATE", "player")
    FlushTimers()
    assert(paints == count, "Two XP signals printed the same gain twice")
    -- The level can also change first, while UnitXP still reports the old value.
    xp = 900
    Emit("PLAYER_XP_UPDATE", "player")
    FlushTimers()
    level = level + 1
    Emit("PLAYER_LEVEL_UP", level)
    xp = 25
    Emit("PLAYER_XP_UPDATE", "player")
    FlushTimers()
    assert(D.slots[D.cursor].text.format == "+%s XP" and D.slots[D.cursor].text.amount == 125,
        "A new level with the old XP counter produced a fabricated gain")
    M.config.showLevelUp = false
    M:Refresh()
    count = paints
    Emit("CHAT_MSG_COMBAT_XP_GAIN", secret)
    xp = xp + 12
    FlushTimers()
    assert(paints == count + 1 and D.slots[D.cursor].text.format == "+%s XP" and D.slots[D.cursor].text.amount == 12,
        "The additional XP signal did not wait for the player counter")

    count = paints
    honor, honorLevel = 15, honorLevel + 1
    Emit("HONOR_XP_UPDATE", "player")
    assert(paints == count + 1 and D.slots[D.cursor].text.format == "+%s Honor" and D.slots[D.cursor].text.amount == 35,
        "Honor was lost without a combat-text event or at an honor-level rollover")
    Emit("COMBAT_TEXT_UPDATE", "HONOR_GAINED")
    Emit("HONOR_XP_UPDATE", "player")
    assert(paints == count + 1, "Honor from the player counter and native feed was duplicated")
    local readableHonor = honor
    honor = secret
    Emit("COMBAT_TEXT_UPDATE", "HONOR_GAINED")
    assert(paints == count + 2 and D.slots[D.cursor].text.amount == secret,
        "Native honor was lost when the counter was unreadable")
    honor = readableHonor

    count = paints
    power[4] = 3
    Emit("UNIT_POWER_UPDATE", "target", "COMBO_POINTS")
    assert(paints == count, "A non-player power event produced a gain")
    Emit("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    assert(paints == count + 1 and D.slots[D.cursor].text.format == "+%s Resource" and D.slots[D.cursor].text.amount == 2,
        "A player resource increased without producing text")
    eventPowerToken = "COMBO_POINTS"
    Emit("COMBAT_TEXT_UPDATE", "ENERGIZE")
    eventPowerToken = secret
    Emit("COMBAT_TEXT_UPDATE", "ENERGIZE")
    power[4] = 1
    Emit("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    power[4] = secret
    eventPowerToken = "COMBO_POINTS"
    Emit("COMBAT_TEXT_UPDATE", "ENERGIZE")
    assert(paints == count + 2 and D.slots[D.cursor].text.amount == secret,
        "A restricted power counter prevented the native resource notification")
    count = count + 1
    activeUnit = "vehicle"
    Emit("COMBAT_TEXT_UPDATE", "ENERGIZE")
    assert(paints == count + 2 and D.slots[D.cursor].text.amount == secret,
        "The player counter swallowed a vehicle resource gain")
    count = count + 1
    activeUnit, eventPowerToken = "player", "ALTERNATE"
    Emit("COMBAT_TEXT_UPDATE", "ENERGIZE")
    assert(paints == count + 2, "A power type outside the player counters was dropped")
    count = count + 1
    eventPowerToken = secret
    Emit("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    Emit("UNIT_POWER_UPDATE", "player", secret)
    -- The next visible update seeds the baseline for each affected resource.
    Emit("UNIT_POWER_UPDATE", "player", "MANA")
    power[4] = 3
    Emit("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    assert(paints == count + 1, "Duplicate, spent or unreadable power produced a gain")
    power[0] = 90
    Emit("UNIT_POWER_UPDATE", "player", "MANA")
    power[0] = 93
    Emit("UNIT_POWER_UPDATE", "player", "MANA")
    assert(paints == count + 1, "Continuous regeneration interrupted progression text")
    FlushTimers()
    assert(paints == count + 2 and D.slots[D.cursor].text.amount == 13, "Primary power gains were not batched")
    power[4] = 4
    Emit("UNIT_DISPLAYPOWER", "player")
    Emit("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    assert(paints == count + 2, "A power reset produced a gain")

    inCombat = false
    Emit("PLAYER_REGEN_ENABLED")
    M.config.hideBlizzardWorldText = false
    M:Refresh()
    assert(not context.directFrame.events.HONOR_XP_UPDATE and not context.frame.events.UNIT_POWER_UPDATE
        and not context.directFrame.events.CHAT_MSG_COMBAT_XP_GAIN, "Opting out left the replacement feeds running")
    assert(context.directFrame.events.COMBAT_TEXT_UPDATE, "Opting out did not restore the original combat text feed")
    M.config.showHonor, M.config.showPower, M.config.showCombatState, M.config.showLevelUp = false, false, false, true
    M:Refresh()
    level, xp = previousLevel, previousXP
    eventReads = 0
end
CheckForeverGainFeeds()

M.active = false
M:Disable()
CheckOwners()
assert(not next(D.occupied) and not next(D.head) and not next(D.tail))
context:Release()
assert(cvar == "1" and not next(context.directFrame.events) and not next(context.frame.events))
-- Retail uses target-only events and screen placement by default, including
-- when there is no usable nameplate. Its UNIT_COMBAT remains source-less.
NS.Client.isForever = false
NS.Client.SupportsEvent = function(event) return event ~= "PLAYER_SWING" end
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeCombatText.lua"))("MSUF_Suite", NS)
S.catalog = NS.SuiteCatalog
local retail = S.catalog[id]
assert(retail.available() and retail.defaultEnabled and retail.rules.enabled.default)
assert(not retail.rules.hideBlizzardWorldText, "Forever-only option appeared on Retail")
M.config = { hideBlizzardWorldText = true }
local retailWorldWrites = worldWrites
for key, rule in pairs(retail.rules) do M.config[key] = rule.default end
assert(M.config.hitSource == 3 and M.config.hitSide == 3)
assert(retail.rules.hitSource.choices[1] == "Your spell hits (estimated)")
M.context, M.active = S.NewContext(id), true
context = M.context
plates.target = nil
activeUnit = "vehicle"
M:Enable()
assert(activeUnit == "vehicle" and unitWrites == 1, "Gain display stole the active unit from Own combat text")
assert(context.frame.events.UNIT_COMBAT == "target" and not context.directFrame.events.PLAYER_SWING)
assert(cvar == "1", "Retail must not hide Blizzard numbers by default")
assert(worldWrites == retailWorldWrites, "A stored Forever setting changed world text on Retail")
Hit("target", "CRITICAL")
local crit = D.slots[D.cursor]
assert(crit.anchor == D.sides[3] and crit.text == crit.critical and crit.text.amount == secret)
Hit("target", secret)
assert(D.slots[D.cursor].text == D.slots[D.cursor].normal, "Opaque crit flags must not be inspected")
Emit("UNIT_COMBAT", "target", "DODGE", "", secret, 1)
local dodge = D.slots[D.cursor]
assert(dodge.anchor == D.sides[2] and dodge.text.label == "Dodge")
Emit("UNIT_COMBAT", "target", "PARRY", "", secret, 1)
assert(D.slots[D.cursor].text.label == "Parry")
local prev = paints
Emit("UNIT_COMBAT", "player", "WOUND", "", secret, 1)
Emit("UNIT_COMBAT", "target", "HEAL", "CRITICAL", secret, 1)
Emit("COMBAT_TEXT_UPDATE", "DAMAGE")
Emit("COMBAT_TEXT_UPDATE", "HEAL_CRIT")
assert(paints == prev and eventReads == 0, "Own combat text fed the outgoing display")

assert(not context.directFrame.events.PLAYER_XP_UPDATE, "Default settings duplicate Blizzard's XP text")
xp = xp + 10
Emit("PLAYER_XP_UPDATE", "player")
assert(paints == prev, "Default settings displayed extra XP")
Emit("PLAYER_LEVEL_UP", level)
assert(D.slots[D.cursor].text.format == "Level %d", "Default XP setting disabled level-up notices")

M.config.showXP, M.config.gainSide = true, 1
M:Refresh()
xp = xp + 40
Emit("PLAYER_XP_UPDATE", "player")
assert(D.slots[D.cursor].anchor == D.sides[2], "XP did not inherit the saved progression position")
M.config.xpSide, M.config.showLevelUp = 3, false
M:Refresh()
assert(not context.directFrame.events.PLAYER_LEVEL_UP, "Level-up switch did not release its event")
xp = xp + 40
Emit("PLAYER_XP_UPDATE", "player")
assert(D.slots[D.cursor].anchor == D.sides[3], "XP did not move independently")
assert(D.slots[D.cursor].text.amount == 40 and D.slots[D.cursor].text.format == "+%s XP")
local afterXP = paints
Emit("PLAYER_XP_UPDATE", "player")
assert(paints == afterXP, "Repeated XP update printed twice")
xp = 170
Emit("PLAYER_XP_UPDATE", "player")
assert(paints == afterXP, "Rollover upset the baseline before level changed")
level = level + 1
Emit("PLAYER_LEVEL_UP", level)
Emit("PLAYER_XP_UPDATE", "player")
assert(D.slots[D.cursor].text.amount == 200, "XP lost across a level up")
Emit("COMBAT_TEXT_UPDATE", "FACTION")
local reputation = D.slots[D.cursor]
assert(eventReads == 1 and reputation.text.format == "%s Reputation" and reputation.text.amount == secret)
assert(reputation.anchor == D.sides[2], "XP placement moved the rest of the progression text")

M.config.scrollStyle, M.config.hitSide, M.config.avoidSide, M.config.showPower = 2, 2, 3, true
M:Refresh()
for _ = 1, 4 do Hit("target", "CRITICAL") end
assert(D.slots[D.cursor].anchor == D.sides[2] and D.slots[D.cursor].move.offsetY < 0)
CheckOwners()
Emit("UNIT_COMBAT", "target", "MISS", "", secret, 1)
assert(D.slots[D.cursor].anchor == D.sides[3])
assert(D.occupied[D.sides[2]] == 7, "Another lane evicted an active entry despite free pool slots")
Emit("COMBAT_TEXT_UPDATE", "ENERGIZE")
assert(eventReads == 2 and D.slots[D.cursor].text.format == "+%s Resource" and D.slots[D.cursor].text.amount == secret)
M.config.showHits, M.config.showAvoidance, M.config.showXP = false, false, false
M.config.showPower, M.config.showReputation, M.config.showCombatState = false, false, true
M:Refresh()
assert(not context.frame.events.UNIT_COMBAT and not context.directFrame.events.COMBAT_TEXT_UPDATE
    and not context.directFrame.events.PLAYER_XP_UPDATE, "Disabled event groups are still listening")
Emit("PLAYER_REGEN_DISABLED")
assert(D.slots[D.cursor].text.label == "Entering combat")
M.active = false
M:Disable()
context:Release()
CheckOwners()
assert(not next(D.occupied))
print("Floating combat text lifecycle and render budget passed on Forever and Mainline")
