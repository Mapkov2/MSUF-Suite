local root = assert(arg[1])
local driver, pending
local function Nop() end
local function Wipe(values) for key in pairs(values) do values[key] = nil end end
local slots, recs, active, names = {}, {}, {}, {}
local tracked, auraReads, unitChecks = {}, 0, 0
local secret = false
local function Public() return true end
local S = { Public = Public, PublicText = function(value) return value end,
    Text = function(value) return value end, Dispatch = function(callback, ...) callback(...) end,
    CreateFrame = function()
        driver = { RegisterEvent = Nop, UnregisterAllEvents = Nop,
            SetScript = function(self, _, callback) self.event = callback end }
        return driver
    end }
local C = { Const = { FAMILY = { AURA = 2, COOLDOWN = 1 }, KIND = { AURA_BAR = 3 } },
    AuraContainers = { live = { bar = { aura = slots } }, list = {}, where = {}, need = { timers = "" } },
    state = {}, EMPTY = {}, wipe = Wipe,
    Catalog = { SpellName = function(id) return tostring(id) end },
    Alerts = { AuraSensor = Nop }, AuraLooks = { Recipient = Nop }, AuraButtons = { Hush = Nop },
    NewWake = function(callback) return callback end,
    Wake = function(callback) assert(not pending); pending = callback end }
local P = { NS = { Client = { SupportsEvent = Public } }, Suite = S, CDM = C }
Enum = { SecrecyLevel = { NeverSecret = 0 } }
C_Secrets = { ShouldSpellAuraBeSecret = function() return secret end }
UnitExists = function(unit) unitChecks = unitChecks + 1; return true end
UnitName = function(unit) return names[unit] or unit end
C_UnitAuras = { GetAuraDataBySpellName = function(unit, name, filter)
    auraReads = auraReads + 1
    tracked[#tracked + 1] = unit
    assert(filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
    if active[unit] then return { spellId = tonumber(name) } end
end }
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/AuraRecipients.lua"))("CDM", P)
local entries = {}
for id = 1, 10 do
    entries[id] = { unit = "group", auraHelpful = true, src = "g", family = 2, key = id, name = "Aura", auraIDs = { [id] = true } }
end
local function Bind(_, _, unit, role, _, _, _, _, _, _, key)
    local rec = { unit = unit, role = role, shown = true, enabled = true, frame = {} }
    function rec.frame:SetUnit(nextUnit) assert(rec.unit == nextUnit) end
    slots[key], recs[#recs + 1] = rec, rec
    return rec
end
C.AuraRecipients.Sync("bar", "aura", {}, { hasRecipients = true, entries = entries, kind = 3 }, false, Bind, Nop)
assert(unitChecks == 470 and auraReads == 470)
local function Event(event, unit) driver.event(driver, event, unit) end
local function Flush() local callback = assert(pending); pending = nil; callback() end
auraReads, unitChecks, tracked = 0, 0, {}
Event("UNIT_AURA", "nameplate1")
assert(not pending, "untracked units armed work")
Event("UNIT_AURA", "raid40")
Event("UNIT_AURA", "party4")
Event("UNIT_AURA", "raid40")
Flush()
assert(unitChecks == 20 and auraReads == 20, "batch repeated native aura checks")
for i = 1, #tracked, 2 do assert(tracked[i] == "party4" and tracked[i + 1] == "raid40") end
local function Cost()
    local visits = 0
    local function Count()
        local frame = debug.getinfo(2, "nS")
        if frame.name == "Refresh" and frame.source:find("AuraRecipients.lua", 1, true) then visits = visits + 1 end
    end
    Event("UNIT_AURA", "raid40")
    debug.sethook(Count, "", 1)
    Flush()
    debug.sethook()
    return visits
end
local cost = Cost()
print(("CDM recipient work: %d Refresh instructions for ten rules and one dirty unit"):format(cost))
assert(cost < 1000, "one dirty token still looped over the whole roster: " .. cost)
active.raid40 = true
Event("UNIT_AURA", "raid40")
Flush()
assert(recs[1].unit == "raid40")
active.party4 = true
Event("UNIT_AURA", "party4")
Flush()
assert(recs[1].unit == "raid40", "active recipient must stay bound")
active.raid40 = false
Event("UNIT_AURA", "raid40")
Flush()
assert(recs[1].unit == "party4", "the next known match must win after aura loss")
active.party4, active.target = false, true
Event("GROUP_ROSTER_UPDATE")
Flush()
assert(recs[1].unit == "target" and recs[1].recipientText == "Aura on target")
names.target = "Another target"
Event("PLAYER_TARGET_CHANGED")
Flush()
assert(recs[1].unit == "target" and recs[1].recipientText == "Aura on Another target")
secret = true
Event("ADDON_RESTRICTION_STATE_CHANGED")
Flush()
assert(recs[1].unit == "player" and recs[1].recipientText == nil)
