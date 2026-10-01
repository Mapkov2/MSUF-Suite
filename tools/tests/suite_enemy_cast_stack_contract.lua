local root = assert(arg[1], "repository root required")
-- Offline contract for the dungeon cast stack. Enemy cast details are secret
-- on the live client (SecretWhenUnitSpellCastRestricted): the sentinels below
-- raise on comparison, arithmetic, concatenation, indexing and tostring, so
-- the module may only hand them to native sinks.
local SecretMT = {}
local function Raise(what) return function() error("secret value used: " .. what, 2) end end
for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat",
    "__lt", "__le", "__eq", "__call", "__len" }) do SecretMT[key] = Raise(key) end
SecretMT.__index, SecretMT.__newindex, SecretMT.__tostring = Raise("index"), Raise("assignment"), Raise("tostring")
local function Secret() return setmetatable({}, SecretMT) end
local function IsSecret(value) return getmetatable(value) == SecretMT end
local Same = rawequal

local module, inside, instanceKind = nil, false, "party"
local casts, channels, targets = {}, {}, {}
local class, known, petKnown, cooldowns, gcds, reads = "MAGE", {}, {}, {}, {}, 0
local calls = {}
local function Count(name) calls[name] = (calls[name] or 0) + 1 end
local function Calls(name) return calls[name] or 0 end

local function Widget(kind)
    local w = { shown = true, kind = kind, scripts = {} }
    for _, key in ipairs({ "SetJustifyH", "SetWordWrap", "SetStatusBarTexture", "SetColorTexture", "SetAllPoints",
        "SetDrawSwipe", "SetDrawEdge", "SetDrawBling", "SetHideCountdownNumbers" }) do
        w[key] = function() end
    end
    function w:SetPoint(point) Count("SetPoint"); self.point = point end
    function w:ClearAllPoints() self.point = nil end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetWidth(value) self.width = value end
    function w:SetScale(value) self.scale = value end
    function w:SetAlpha(value) self.alpha, self.alphaBool = value, nil end
    function w:SetAlphaFromBoolean(value, yes, no)
        assert(IsSecret(value) or type(value) == "boolean", "SetAlphaFromBoolean needs a boolean")
        self.alphaBool, self.alphaYes, self.alphaNo = value, yes, no
        self.alpha = not IsSecret(value) and (value and yes or no) or nil
    end
    function w:SetMinMaxValues(a, b) self.minimum, self.maximum = a, b end
    function w:SetValue(value) self.value = value end
    function w:SetTexture(value) Count("SetTexture"); self.texture = value end
    function w:SetText(value) Count("SetText"); self.text = value end
    function w:SetShown(value) self.shown = value == true end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetStatusBarColor(...) Count("SetStatusBarColor"); self.color = { ... } end
    function w:SetTimerDuration(value, interpolation, direction)
        Count("SetTimerDuration")
        assert(interpolation ~= nil and direction ~= nil)
        self.duration, self.direction = value, direction
    end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:Clear() self.cooldown = nil end
    function w:SetSpriteSheetCell(cell, rows, columns)
        assert(rows == 4 and columns == 4, "raid markers use Blizzard's 4 x 4 sheet")
        self.cell = cell
    end
    function w:SetCooldownFromDurationObject(duration, clearIfZero)
        assert(clearIfZero == true); self.cooldown = duration
    end
    return w
end
UIParent = Widget("Frame")
TANK, HEALER, DAMAGER = "Panzer", "Heiler", "Schaden"
Enum = { StatusBarInterpolation = { Immediate = 0 }, StatusBarTimerDirection = { RemainingTime = 10, ElapsedTime = 11 },
    SecondsFormatterInterval = { Seconds = 0 }, SpellBookSpellBank = { Player = 0, Pet = 1 } }
C_DurationUtil = { CreateDurationTextBinding = function()
    return { SetFontString = function(self, v) self.text = v end,
        SetFormatter = function() end, SetUpdateInterval = function() end,
        SetDuration = function(self, v) self.duration = v end,
        SetEnabled = function(self, v) self.enabled = v end }
end }
C_StringUtil = { CreateSecondsFormatter = function()
    return { SetDesiredUnitCount = function() end, SetMinInterval = function() end }
end }
C_CurveUtil = { EvaluateColorValueFromBoolean = function(value, yes, no)
    Count("Evaluate")
    if IsSecret(value) then return Secret() end
    assert(type(value) == "boolean", "curve evaluation needs a boolean")
    return value and yes or no
end }
local LOCALIZED = { [116] = "Frostblitz", [15407] = "Gedankenschinden", [188196] = "Blitzschlag", [348] = "Feuerbrand" }
local cooldownDurations = {}
local ranges, rangeReads, markers, tickers = {}, 0, {}, {}
C_Timer = { NewTicker = function(interval, callback)
    local ticker = { interval = interval, callback = callback }
    function ticker:Cancel() self.cancelled = true end
    tickers[#tickers + 1] = ticker
    return ticker
end }
GetRaidTargetIndex = function(unit) Count("GetRaidTargetIndex"); return markers[unit] end
C_Spell = {
    IsSpellInRange = function(id, unit)
        assert(unit and unit:match("^nameplate%d+$"), "range checks name the cast's own nameplate")
        rangeReads = rangeReads + 1
        local value = ranges[unit]
        if type(value) == "table" and not IsSecret(value) then return value[id] end
        return value
    end,
    IsSpellImportant = function(id)
        assert(id ~= nil, "IsSpellImportant takes a spell")
        if IsSecret(id) then return Secret() end
        return id == 99
    end,
    GetSpellCooldown = function(id)
        reads = reads + 1
        local active = cooldowns[id]
        if active == nil then active = false end
        return { isActive = active, isOnGCD = gcds[id], startTime = Secret(), duration = Secret() }
    end,
    GetSpellCooldownDuration = function(id, ignoreGCD)
        assert(ignoreGCD == true, "the wake must ignore the global cooldown")
        cooldownDurations[id] = cooldownDurations[id] or { spell = id }
        return cooldownDurations[id]
    end,
    GetSpellInfo = function(id) return { name = LOCALIZED[id], iconID = id + 1000 } end,
}
C_SpellBook = { IsSpellKnown = function(id, bank) return (bank == 1 and petKnown or known)[id] == true end }
UnitClass = function() return "Class", class end
UnitName = function() return "Mapko" end
IsInInstance = function() return inside, inside and instanceKind or "none" end
UnitExists = function(unit) return casts[unit] ~= nil or channels[unit] ~= nil end
UnitCanAttack = function() return true end
UnitCastingDuration = function(unit) return casts[unit] and casts[unit].duration end
UnitChannelDuration = function(unit) return channels[unit] and channels[unit].duration end
UnitCastingInfo = function(unit)
    local c = casts[unit]
    if c then return c.name, c.name, c.icon, Secret(), Secret(), false, Secret(), c.locked, c.id, nil, 0 end
end
UnitChannelInfo = function(unit)
    local c = channels[unit]
    if c then return c.name, c.name, c.icon, Secret(), Secret(), false, c.locked, c.id, false, 0, nil end
end
UnitSpellTargetName = function(unit) Count("UnitSpellTargetName"); return targets[unit] end
local function SecretCast() return { name = Secret(), icon = Secret(), id = Secret(), locked = Secret(), duration = Secret() } end

local S = { Install = function(_, m) module = m end, Public = function(v) return not IsSecret(v) end,
    Finite = function(v) return type(v) == "number" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    CreateFrame = function(kind) Count("CreateFrame"); return Widget(kind) end,
    CreateTexture = function() return Widget("Texture") end,
    CreateFontString = function() return Widget("FontString") end,
    SetStyledFont = function() Count("SetStyledFont") end, GlobalFontPath = function() return "font" end,
    RegisterOwnedMover = function(_, element, spec) module.mover = { element = element, spec = spec } end,
    RGB = function(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255 end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/EnemyCastStack.lua"))("test", { NS = { Client = {} }, Suite = S })
module.active = true
module.config = { listSize = 2, castKinds = 1, fadeMinor = false, targetLine = true, readyStripe = false,
    interruptSpellID = 0, growth = 1, width = 280, rowHeight = 30, fontSize = 12, scale = 100, x = 350, y = 0,
    castColor = "b88a4a", priorityColor = "d65a5a", lockedColor = "7d8290", stripeColor = "63c88a" }
module.context = { events = {}, units = {},
    Event = function(self, event, fn, _, unit) self.events[event], self.units[event] = fn, unit end,
    RemoveEvent = function(self, event) self.events[event], self.units[event] = nil, nil end }
local function Fire(event, ...) assert(module.context.events[event], event)(module, event, ...) end
local function Live(unit) local entry = module.entries[unit]; return entry and entry.live end

------------------------------------------------------------------ gate and snapshot
module:Enable()
assert(module.mover.element == "casts" and module.mover.spec.sizeKeys[2] == "rowHeight", "mover lost its size keys")
assert(not module.listening and not module.host.shown and not module.context.events.NAME_PLATE_UNIT_ADDED,
    "the stack listened outside a dungeon")
casts.nameplate1 = SecretCast()
targets.nameplate1 = Secret()
channels.nameplate150 = SecretCast()
inside, instanceKind = true, "raid"; Fire("PLAYER_ENTERING_WORLD")
assert(not module.listening and not module.context.events.UNIT_SPELLCAST_START, "the stack listened in a raid")
instanceKind = "party"; Fire("PLAYER_ENTERING_WORLD")
assert(Live("nameplate1") and Live("nameplate150"), "the snapshot missed a nameplate token up to 150")
local first, second = module.ordered[1].row, module.ordered[2].row
assert(module.visible == 2 and first.slot == 1 and second.slot == 2 and module.host.shown)
-- Secret details reach their sinks untouched.
assert(Same(first.name.text, casts.nameplate1.name) and Same(first.icon.texture, casts.nameplate1.icon)
    and Same(first.target.text, targets.nameplate1) and Same(first.duration, casts.nameplate1.duration)
    and Same(first.binding.duration, casts.nameplate1.duration) and first.binding.enabled,
    "secret cast details did not reach the native sinks")
assert(IsSecret(first.color[1]) and IsSecret(first.color[3]), "secret importance or lock state was read in Lua")
assert(second.direction == Enum.StatusBarTimerDirection.RemainingTime
    and first.direction == Enum.StatusBarTimerDirection.ElapsedTime, "channels must count down, casts up")
assert(first.alpha == 1 and not first.stripe.shown, "plain rows faded or showed a ready mark")

------------------------------------------------------------------ warm hot path
local rowsBefore, styled = #module.rows, Calls("SetStyledFont")
local texts = Calls("SetText")
casts.nameplate7 = SecretCast()
Fire("UNIT_SPELLCAST_START", "nameplate7")
assert(Live("nameplate7") and not module.entries.nameplate7.row and #module.rows == rowsBefore
    and Calls("SetText") == texts, "a cast past the list size was painted")
local before = {}
for name, count in pairs(calls) do before[name] = count end
local function Unchanged(what)
    for name, count in pairs(calls) do
        assert(before[name] == count, what .. " (" .. name .. ")")
    end
end
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "NAME_PLATE_UNIT_REMOVED" }) do
    Fire(event, "nameplate9")
    Fire(event, "player")
end
Unchanged("an event of an unlisted unit touched the client")
-- A stop moves the next cast up: one re-anchor, one new paint, no restyle.
casts.nameplate1 = nil
local paints = Calls("SetTimerDuration")
Fire("UNIT_SPELLCAST_STOP", "nameplate1")
assert(not Live("nameplate1") and module.ordered[1].unit == "nameplate150" and module.ordered[1].row == second
    and second.slot == 1, "the remaining cast did not move up")
assert(module.ordered[2].unit == "nameplate7" and module.ordered[2].row == first and first.slot == 2
    and Same(first.name.text, casts.nameplate7.name), "the next cast did not take the freed row")
assert(Calls("SetTimerDuration") == paints + 1 and Calls("SetStyledFont") == styled and #module.rows == rowsBefore,
    "a stop restyled or repainted rows that only moved")
assert(module.entries.nameplate1.name == nil and module.entries.nameplate1.duration == nil,
    "a finished cast kept its secret details")
-- A failed attempt while the unit casts on keeps the running cast.
Fire("UNIT_SPELLCAST_FAILED", "nameplate7")
assert(Live("nameplate7") and module.ordered[2].unit == "nameplate7", "a failed stop removed a running cast")
-- Delays re-bind only the timer.
texts, paints = Calls("SetText"), Calls("SetTimerDuration")
casts.nameplate7.duration = Secret()
Fire("UNIT_SPELLCAST_DELAYED", "nameplate7")
assert(Calls("SetTimerDuration") == paints + 1 and Same(first.duration, casts.nameplate7.duration)
    and Same(first.binding.duration, casts.nameplate7.duration) and Calls("SetText") == texts,
    "a delay repainted more than the timer")
-- The interrupt events name the new state; only the color changes.
Fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "nameplate7")
local locked = { S.RGB("7d8290") }
assert(first.color[1] == locked[1] and first.color[3] == locked[3] and Calls("SetTimerDuration") == paints + 1,
    "a lock change did not recolor or re-bound the timer")
Fire("UNIT_SPELLCAST_INTERRUPTIBLE", "nameplate7")
assert(IsSecret(first.color[1]), "an interruptible cast did not return to its importance color")
assert(Calls("SetStyledFont") == styled, "a hot event restyled a row")

------------------------------------------------------------------ ready mark
module.config.readyStripe = true
known[2139] = true
module:Refresh()
assert(module.candidates[1] == 2139 and module.context.events.SPELL_UPDATE_COOLDOWN
    and module.context.units.UNIT_PET == "player", "the ready mark did not find the interrupt")
local rowA, rowB = module.ordered[1].row, module.ordered[2].row
assert(module.ready and rowA.stripe.shown and Same(rowA.stripe.alphaBool, module.ordered[1].locked)
    and rowA.stripe.alphaYes == 0 and rowA.stripe.alphaNo == 1, "the ready mark ignored the interrupt state")
local beforeReads = reads
Fire("SPELL_UPDATE_COOLDOWN", 133, nil)
assert(reads == beforeReads, "another spell's cooldown re-read the interrupt")
cooldowns[2139] = true
Fire("SPELL_UPDATE_COOLDOWN", 2139, nil)
assert(reads == beforeReads + 1 and not module.ready and not rowA.stripe.shown and not rowB.stripe.shown,
    "an interrupt on cooldown kept the ready mark")
local wake = module.wakes[1]
assert(wake and wake.cooldown == cooldownDurations[2139] and wake.alpha == 0, "no wake for the cooldown end")
gcds[2139] = true
Fire("SPELL_UPDATE_COOLDOWN", nil, nil)
assert(module.ready and rowA.stripe.shown and wake.cooldown == nil, "the global cooldown hid the ready mark")
gcds[2139], cooldowns[2139] = nil, true
Fire("SPELL_UPDATE_COOLDOWN", 9999, 2139)
assert(not module.ready, "an override spell of the interrupt was ignored")
-- The client sends no event when the cooldown ends; the wake repaints.
cooldowns[2139] = false
wake.scripts.OnCooldownDone()
assert(module.ready and rowA.stripe.shown and rowB.stripe.shown, "the cooldown end did not restore the mark")
class, known, petKnown = "WARLOCK", {}, { [19647] = true }
Fire("UNIT_PET", "player")
assert(module.candidates[1] == 19647 and #module.candidates == 1, "the active pet interrupt was not found")
petKnown = { [89766] = true }; Fire("PET_BAR_UPDATE")
assert(module.candidates[1] == 89766 and #module.candidates == 1, "a pet swap kept the old interrupt")
petKnown = {}; Fire("UNIT_PET", "player")
assert(#module.candidates == 0 and not module.context.events.SPELL_UPDATE_COOLDOWN and not module.ready,
    "no pet must mean no interrupt and no cooldown listener")
module.config.interruptSpellID = 123; module:Refresh()
assert(#module.candidates == 1 and module.candidates[1] == 123, "the interrupt spell ID was ignored")
module.config.interruptSpellID, module.config.readyStripe = 0, false
module:Refresh()
assert(not module.context.events.SPELL_UPDATE_COOLDOWN and not module.context.events.SPELLS_CHANGED
    and #module.candidates == 0, "a disabled ready mark kept its listeners")

------------------------------------------------------------------ fading, cast types, growth
module.config.fadeMinor = true; module:Refresh()
rowA = module.ordered[1].row
assert(Same(rowA.alphaBool, module.ordered[1].important) and rowA.alphaYes == 1 and rowA.alphaNo == .4,
    "fading must follow the game's importance flag, secret or not")
module.config.fadeMinor, module.config.castKinds = false, 2
module:Refresh()
assert(not Live("nameplate150") and module.ordered[1].unit == "nameplate7" and #module.ordered == 1,
    "a casts-only list kept a channel")
channels.nameplate150 = nil
Fire("UNIT_SPELLCAST_CHANNEL_START", "nameplate12")
assert(not module.entries.nameplate12 or not Live("nameplate12"), "a casts-only list added a channel")
module.config.castKinds, module.config.growth = 1, 2
module:Refresh()
assert(module.ordered[1].row.point == "BOTTOMLEFT", "new casts above the last must grow from the bottom")
module.config.growth = 1; module:Refresh()

------------------------------------------------------------------ Edit Mode samples
casts.nameplate3 = SecretCast()
Fire("UNIT_SPELLCAST_START", "nameplate3")
local liveRow = module.ordered[1].row
S.editMode = true
module.config.listSize, module.config.readyStripe, module.config.showMarkers = 4, true, true
module:Refresh()
assert(module.previews[1].marker.shown and module.previews[1].marker.cell == 3 and not module.previews[2].marker.shown,
    "samples did not show their raid markers")
module.config.showMarkers = nil
assert(module.host.shown and #module.previews == 4 and module.previews[1].shown and not liveRow.shown
    and not liveRow.binding.enabled and module.visible == 0, "Edit Mode did not swap live casts for samples")
assert(module.previews[1].name.text == "Frostblitz" and module.previews[2].name.text == "Gedankenschinden"
    and module.previews[1].target.text == "Mapko" and module.previews[2].target.text == "Panzer",
    "samples must use client names in the reader's language")
assert(module.previews[1].stripe.shown and not module.previews[3].stripe.shown and module.previews[1].duration == nil,
    "samples need a ready mark on interruptible casts and no timers")
casts.nameplate4 = SecretCast()
Fire("UNIT_SPELLCAST_START", "nameplate4")
assert(Live("nameplate4") and not module.entries.nameplate4.row, "Edit Mode painted a live cast")
module:HideEditPreview()
S.editMode = false
module.config.listSize = 2
module:Refresh()
assert(not module.previews[1].shown and module.ordered[1].row.shown and module.ordered[1].row.binding.enabled
    and module.visible == 2, "leaving Edit Mode did not restore live casts")

------------------------------------------------------------------ raid markers
module.config.readyStripe, module.config.showMarkers = false, true
local unitA, unitB = module.ordered[1].unit, module.ordered[2].unit
markers[unitA], markers[unitB] = Secret(), nil
module:Refresh()
local rowA, rowB = module.ordered[1].row, module.ordered[2].row
assert(module.context.events.RAID_TARGET_UPDATE and rowA.marker.shown and Same(rowA.marker.cell, markers[unitA])
    and not rowB.marker.shown, "a secret marker must reach the sprite sheet and no marker must hide the badge")
markers[unitB] = 6
Fire("RAID_TARGET_UPDATE")
assert(rowB.marker.shown and rowB.marker.cell == 6, "a new raid marker did not repaint the badge")
module.config.showMarkers = false; module:Refresh()
assert(not module.ordered[1].row.marker.shown and not module.context.events.RAID_TARGET_UPDATE,
    "switched-off markers kept the badge or the listener")

------------------------------------------------------------------ range dimming
class, known, petKnown = "MAGE", { [2139] = true }, {}
module.config.dimOutOfRange = true
ranges[unitA], ranges[unitB] = { [2139] = false }, { [2139] = true }
module:Refresh()
rowA, rowB = module.ordered[1].row, module.ordered[2].row
local ticker = tickers[#tickers]
assert(ticker and not ticker.cancelled and ticker.interval == .25 and module.rangeTicker == ticker,
    "dimming without a range ticker for the listed casts")
assert(rowA.alpha == .45 and rowB.alpha == 1, "an enemy beyond the interrupt was not dimmed")
assert(not module.context.events.SPELL_UPDATE_COOLDOWN, "dimming alone listened to cooldowns")
ranges[unitA] = { [2139] = true }
local writes = rangeReads
ticker.callback()
assert(rowA.alpha == 1 and rangeReads == writes + 2, "the tick did not sample each listed cast once")
ranges[unitB] = Secret()
ticker.callback()
assert(rowB.alpha == 1, "a secret range answer dimmed a cast")
ranges[unitB] = { [2139] = false }
ticker.callback()
assert(rowB.alpha == .45, "moving out of range did not dim")
-- Dimming scales the importance fade; hiding unmarked casts wins over fading.
module.config.fadeMinor = true; module:Refresh()
rowB = module.ordered[2].row
assert(Same(rowB.alphaBool, module.ordered[2].important) and rowB.alphaYes == .45 and math.abs(rowB.alphaNo - .18) < 1e-9,
    "the fade did not keep the range dim")
module.config.onlyImportant = true; module:Refresh()
rowA, rowB = module.ordered[1].row, module.ordered[2].row
assert(Same(rowA.alphaBool, module.ordered[1].important) and rowA.alphaYes == 1 and rowA.alphaNo == 0,
    "hiding unmarked casts must make them fully transparent")
module.config.fadeMinor, module.config.onlyImportant = false, false
module.config.dimOutOfRange = false; module:Refresh()
assert(ticker.cancelled and not module.rangeTicker and module.ordered[1].row.alpha == 1,
    "switching dimming off kept the ticker or the dim")

------------------------------------------------------------------ whole-bar ready mark
module.config.readyStripe, module.config.readyStyle = true, 2
cooldowns[2139], gcds[2139] = false, nil
module:Refresh()
rowA = module.ordered[1].row
local readyRGB = { S.RGB("63c88a") }
assert(not rowA.stripe.shown, "the whole-bar style still drew the stripe")
Fire("UNIT_SPELLCAST_INTERRUPTIBLE", unitA)
assert(rowA.color[1] == readyRGB[1] and rowA.color[3] == readyRGB[3], "an interruptible cast did not take the ready color")
Fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unitA)
local lockedRGB = { S.RGB("7d8290") }
assert(rowA.color[1] == lockedRGB[1], "an uninterruptible cast took the ready color")
Fire("UNIT_SPELLCAST_INTERRUPTIBLE", unitA)
cooldowns[2139] = true
Fire("SPELL_UPDATE_COOLDOWN", 2139, nil)
assert(rowA.color[1] ~= readyRGB[1], "an interrupt on cooldown kept the ready color")
module.config.readyStripe, module.config.readyStyle = false, 1
cooldowns[2139] = false
module:Refresh()

------------------------------------------------------------------ leaving and disabling
inside = false; Fire("ZONE_CHANGED_NEW_AREA")
assert(not module.host.shown and not module.context.events.UNIT_SPELLCAST_START and #module.ordered == 0
    and module.entries.nameplate7.name == nil, "leaving the dungeon kept casts or listeners")
for _, row in ipairs(module.rows) do assert(not row.shown and not row.binding.enabled, "a row kept its timer") end
inside = true; Fire("ZONE_CHANGED_NEW_AREA")
assert(module.visible == 2, "re-entering did not take a new snapshot")
-- With nothing listed, the player's cooldowns cost nothing.
class, known = "MAGE", { [2139] = true }
module.config.readyStripe = true; module:Refresh()
for unit in pairs(casts) do casts[unit] = nil; Fire("UNIT_SPELLCAST_STOP", unit) end
beforeReads = reads
Fire("SPELL_UPDATE_COOLDOWN", nil, nil)
Fire("SPELL_UPDATE_COOLDOWN", 2139, nil)
assert(module.visible == 0 and not module.host.shown and reads == beforeReads,
    "cooldown events were sampled with no cast listed")
casts.nameplate5 = SecretCast()
Fire("UNIT_SPELLCAST_START", "nameplate5")
assert(reads == beforeReads + 1 and module.ordered[1].row.stripe.shown, "the first listed cast skipped readiness")
module:Disable()
assert(module.visible == 0 and #module.ordered == 0 and not module.host.shown and not module.listening,
    "disable kept displayed casts")
for _, row in ipairs(module.rows) do
    assert(not row.binding.enabled and not row.shown, "disable kept an active cast binding")
end
print("Dungeon cast stack: gating, 150-plate snapshot, secret sinks, warm row paths, ready mark, samples and cleanup passed")
