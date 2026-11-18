local root = assert(arg[1])
local FONT, OVERRIDE = "MSUF.ttf", "CombatOverride.ttf"
local CVAR = "floatingCombatTextCombatDamage_v2"
local NOOP = function() end
local cvar, font, now = "1", FONT, 0
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
    SetFrameStrata = NOOP, EnableMouse = NOOP,
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
function methods:Play() self.playing = true end
function methods:Stop() assert(self.playing); self.playing = false end
function methods:SetFormattedText(format, amount)
    assert(format == "%s" and (rawequal(amount, secret) or amount == wideAmount),
        "Amount must reach the native sink unchanged")
    self.amount, paints = amount, paints + 1
end

UIParent = New()
wipe = function(map) for key in pairs(map) do map[key] = nil end return map end
GetTime = function() clockReads = clockReads + 1; return now end
UnitName = function() return "Tester" end
GetRealmName = function() return "Test realm" end
Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 }, Damageclass = { MaskPhysical = 1 } }
C_Spell = { IsSpellHarmful = function(spellID) return spellID == 11 end }
C_CVar = {
    GetCVar = function(key) assert(key == CVAR); return cvar end,
    SetCVar = function(key, value) assert(key == CVAR); cvar = value; return true end,
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
    Safety = { IsForbidden = function(plate) return plate.forbidden == true end },
    Dispatch = function(fn, ...) return fn(...) end,
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
assert(not spec.available())
NS.Client.isForever = true
S.CreateFrame = function() frames = frames + 1; return New() end
S.CreateFontString = New
S.GlobalFontPath = function() styleCalls = styleCalls + 1; return font end
S.ResolveFont = function(key) if key == "CombatTextFont" then return OVERRIDE end end
S.SetFont = function(text, path, size)
    assert(path == font or path == OVERRIDE)
    text.fontPath, text.fontSize, fontWrites = path, size, fontWrites + 1
end
local P = {}
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/FloatingCombatText.lua"))("MSUF_Suite_QualityOfLife", P)
local M = assert(S.instances[id])
assert(frames == 0 and fontWrites == 0 and cvar == "1", "Inactive module performed work")
M.config = {}
for key, rule in pairs(spec.rules) do M.config[key] = rule.default end
M.context, M.active = S.NewContext(id), true
M:Enable()
local function CheckTextGeometry()
    for _, slot in ipairs(M.slots) do
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
    EmitOn(context.frame, event, ...)
    EmitOn(context.directFrame, event, ...)
end
local function CheckSpacing()
    for index, entry in ipairs(M.slots) do
        if entry.plate then
            local visible = 0
            for otherIndex, other in ipairs(M.slots) do
                if entry.plate == other.plate then
                    visible = visible + 1
                    if otherIndex > index then
                        local top = entry.frame.y + entry.frame.height + entry.move.offsetY
                        local otherTop = other.frame.y + other.frame.height + other.move.offsetY
                        assert(top < other.frame.y or otherTop < entry.frame.y,
                            "Damage numbers share overlapping animation paths")
                    end
                end
            end
            assert(visible <= 4, "Damage burst grew beyond four reserved lines")
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
assert(paints == 1 and M.slots[1].text == M.slots[1].critical
    and M.slots[1].text.fontSize == M.config.fontSize * M.config.critScale / 100)
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
for _ = 1, 96 do Hit("nameplate1") end
local positionWrites = anchors
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 96 do Hit("nameplate1") end
local allocated = collectgarbage("count") - before
collectgarbage("restart")
assert(paints == 194 and frames == created and fontWrites == styled and styleCalls == fontResolves)
assert(clockReads == reads and anchors == positionWrites, "Warm all-hits path repeated work")
assert(allocated < 0.25, "Warm all-hits path allocated Lua data")
Hit("target")
Hit("nameplate2")
Hit("nameplate3")
Hit("target", "ABSORB")
Hit(secret)
Hit("target", secret)
Emit("UNIT_COMBAT", "target", "HEAL", "", secret, 1)
Emit("UNIT_COMBAT", "target", secret, "", secret, 1)
assert(paints == 195, "Wrong target alias, ally, healing, mitigation or secret token was painted")
local slot = M.slots[M.cursor]
slot.animation.playing = false
slot.animation.scripts.OnFinished(slot.animation)
assert(not slot.frame.shown and not M.activePlates[second], "Finished animation leaked a plate")
Emit("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not M.activePlates[first])
for _, entry in ipairs(M.slots) do assert(not entry.frame.shown) end

-- Reserve complete animation paths, reuse the oldest burst entry and fill holes.
local function CheckOwners()
    for plate, head in pairs(M.firstSlots) do
        local mask, count, entry, previous = 0, 0, head, nil
        while entry do
            assert(entry.plate == plate and entry.older == previous, "Broken plate queue")
            mask, count = mask + entry.lineBit, count + 1
            assert(count <= 4, "Plate queue has a cycle or too many entries")
            previous, entry = entry, entry.newer
        end
        assert(mask == M.activePlates[plate] and previous == M.lastSlots[plate], "Stale plate ownership")
    end
    for plate in pairs(M.activePlates) do assert(M.firstSlots[plate] and M.lastSlots[plate]) end
    for _, entry in ipairs(M.slots) do
        if entry.plate then
            local linked = M.firstSlots[entry.plate]
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
local oldest = M.firstSlots[second]
local oldestLine = oldest.line
Hit("target")
assert(M.lastSlots[second] == oldest and oldest.line == oldestLine, "Full burst did not reuse its oldest line")
CheckOwners()
local middle = M.firstSlots[second].newer
local freeLine = middle.line
Finish(middle)
Hit("target", "CRITICAL")
assert(M.slots[M.cursor].line == freeLine, "A finished middle line was not reused")
CheckOwners()
-- More than six simultaneous enemies forces global pool recycling as well.
for index = 4, 11 do
    local unit = "nameplate" .. index
    plates[unit] = Plate(unit)
    Emit("NAME_PLATE_UNIT_ADDED", unit)
    for _ = 1, 5 do Hit(unit, "CRITICAL"); CheckOwners() end
end
for index = #M.slots, 1, -1 do
    local entry = M.slots[index]
    if entry.plate then Finish(entry) end
end
assert(not next(M.activePlates) and not next(M.firstSlots) and not next(M.lastSlots),
    "Animation completion retained a plate queue")
for _ = 1, 4 do Hit("target") end
Emit("NAME_PLATE_UNIT_REMOVED", "nameplate2")
CheckOwners()
assert(not next(M.activePlates) and not next(M.firstSlots) and not next(M.lastSlots),
    "Nameplate removal retained reserved lines")
Emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
Emit("PLAYER_TARGET_CHANGED")

font = "New MSUF profile.ttf"
M.config.hideBlizzard = false
M:Refresh()
assert(M.slots[1].normal.fontPath == font and cvar == "1")
M.config.font = "CombatTextFont"
M:Refresh()
assert(M.slots[1].normal.fontPath == OVERRIDE and M.slots[1].critical.fontPath == OVERRIDE)
font = "Changed global MSUF font.ttf"
M:Refresh()
assert(M.slots[1].normal.fontPath == OVERRIDE, "Global font overrode the module's choice")
M.config.font = ""
M:Refresh()
assert(M.slots[1].normal.fontPath == font and M.slots[1].critical.fontPath == font)
M.config.hideBlizzard = true
M:Refresh()
assert(cvar == "0")
for _, override in ipairs({ "", "CombatTextFont" }) do
    M.config.font, M.config.fontSize, M.config.critScale = override, 48, 200
    M:Refresh()
    for index = 1, 48 do
        local flag = index <= 24 and "CRITICAL" or ""
        Emit("UNIT_COMBAT", "target", "WOUND", flag, wideAmount, 1)
        local entry = M.slots[M.cursor]
        local expected = flag == "CRITICAL" and entry.critical or entry.normal
        assert(entry.text == expected and entry.text.shown ~= false)
        assert(entry.text.amount == wideAmount and entry.text.fontSize == (flag == "CRITICAL" and 96 or 48),
            "Pool reuse lost the full amount or critical size")
        CheckTextGeometry()
        CheckSpacing()
    end
end
M.active = false
M:Disable()
CheckOwners()
assert(not next(M.activePlates) and not next(M.firstSlots) and not next(M.lastSlots))
context:Release()
assert(cvar == "1" and not next(context.directFrame.events) and not next(context.frame.events))
print("Floating combat text lifecycle and render budget passed")
