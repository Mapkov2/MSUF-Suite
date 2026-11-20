local root = arg[1] or "."
local SECRET = {}
local slots = { [4] = 8512, [2] = 8075 }
local buffs = { raid1 = 8515, raid3 = 8515 }
local visible = { raid1 = true, raid2 = true, raid3 = false }
local reads, used, notices, pending = 0, 0, 0, {}
local driver, blocked, chatLocked, combat, prepared, shown
AIR_TOTEM_SLOT, EARTH_TOTEM_SLOT = 4, 2
GameFontHighlightSmall = {}
function wipe(t) for k in pairs(t) do t[k] = nil end end
function UnitClass() return "Shaman", "SHAMAN" end
function IsInRaid() return true end
function GetNumGroupMembers() return 3 end
function GetNumSubgroupMembers() error("Use raid roster exactly once") end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost() return false end
function UnitIsVisible(unit) return visible[unit] end
function GetTime() return 10 end
function GetTotemInfo(slot)
    if slots[slot] == SECRET then return SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET end
    return slots[slot] ~= nil, nil, 8, 30, nil, nil, slots[slot]
end
C_Spell = { GetSpellName = function(id) return tostring(id) end }
C_Secrets = { ShouldSpellAuraBeSecret = function() return blocked == true end }
C_UnitAuras = {
    GetAuraDataBySpellName = function(unit, name, filter)
        assert(not blocked, "Do not query protected auras")
        assert(filter == "HELPFUL|PLAYER", "Filter out the other shaman")
        reads = reads + 1
        return name == "8515" and buffs[unit] and { spellId = buffs[unit] } or nil
    end,
}
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
C_ChatInfo = {
    SendChatMessage = function(text, channel)
        assert(not chatLocked and channel == "RAID")
        assert(text:find("1 with your buff, 1 without, 1 unknown.", 1, true))
        used = used + 1
    end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function() notices = notices + 1 end }

local function Public(v) return v ~= SECRET end
local function Nop() end
local S = {
    Public = Public,
    PublicText = function(v) return Public(v) and type(v) == "string" and v or nil end,
    Number = function(v) return Public(v) and type(v) == "number" end,
    Text = function(text) return text end,
    CreateFrame = function()
        assert(not driver, "Reuse the driver after disabling coverage")
        driver = { events = {} }
        function driver:SetScript(_, fn) self.fire = fn end
        function driver:RegisterEvent(event) self.events[event] = true end
        function driver:UnregisterEvent(event) self.events[event] = nil end
        function driver:UnregisterAllEvents() wipe(self.events) end
        return driver
    end,
    CreateFontString = function()
        return { SetFontObject = Nop, SetPoint = Nop, SetShadowOffset = Nop,
            SetText = function(self, text) self.text = text end }
    end,
}
local C = {
    Ranks = { Canon = function(id) return id == 10613 and 8512 or id end },
    state = {},
    bars = { cooldown = {} },
    TotemCoverageDisplay = {
        Prepare = function(_, _, ids, units)
            assert(#units == 3 and ids[8515])
            prepared = true
            return true
        end,
        Show = function(icon, label, _, _, have)
            assert(prepared and label == "8515")
            if combat then assert(have == SECRET, "The native panel must mirror hidden slot visibility") end
            shown = icon
            return true
        end,
        Hide = function() shown = nil end,
        Retire = function() shown = nil end,
    },
}
local NS = {
    Client = { isForever = true, AuraBuildBlocked = function() return false end },
    InCombat = function() return combat end,
    ChatLocked = function() return chatLocked end,
}
local P = { CDM = C, Suite = S, NS = NS }
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/TotemCoverage.lua"))("CDM", P)
local Coverage = C.TotemCoverage
local entry = { id = 4, slot = "cooldown", ov = {} }
local icon = { entry = entry }
local function Tick()
    local work = pending
    pending = {}
    for _, fn in ipairs(work) do fn() end
end
local function Fire(event, ...)
    assert(driver.events[event], "Driver is not listening for " .. event)
    driver:fire(event, ...)
end

Coverage.Sync(icon, entry)
assert(not driver, "Disabled by default, no UI or listeners")
entry.ov.totemCoverage = true
Coverage.Sync(icon, entry)
Tick()
assert(prepared and driver.events.UNIT_AURA)
assert(icon.totemCoverageValue == "1+" and reads == 2, "Unreadable must not become a definite no")
assert(Coverage.Hover(icon) and shown == icon)
Coverage.Leave(icon)

NS.ReportTotemCoverage(4)
assert(used == 1)
chatLocked = true
NS.ReportTotemCoverage(4)
assert(used == 1 and notices == 1)
chatLocked = false

local before = reads
visible.raid3 = true
Fire("UNIT_AURA", "raid3")
Fire("UNIT_AURA", "raid3")
Fire("UNIT_AURA", SECRET)
Fire("UNIT_AURA", "enemy")
assert(#pending == 1)
Tick()
assert(reads == before + 1 and icon.totemCoverageValue == "2/3", "Coalesce one lookup per changed unit")

blocked, combat, slots[4] = true, true, SECRET
Fire("ADDON_RESTRICTION_STATE_CHANGED")
assert(icon.totemCoverageValue == nil)
before = reads
Tick()
assert(reads == before and icon.totemCoverageValue == "?" and not driver.events.UNIT_AURA)
assert(not Coverage.Hover(icon) and shown == icon, "Native coverage stays available alongside the opaque slot tooltip")
NS.ReportTotemCoverage(4)
assert(used == 1 and notices == 2)

blocked, combat, slots[4] = false, false, 8835
Fire("PLAYER_REGEN_ENABLED")
Tick()
assert(icon.totemCoverageValue == nil and not shown, "Replacing totem with an unsupported one removes its coverage")

slots[4] = 10613
Coverage.Update(icon)
Tick()
assert(icon.totemCoverageValue == "2/3" and driver.events.UNIT_AURA)
C.bars.cooldown.hidden = true
Coverage.Update(icon)
Tick()
assert(not icon.totemCoverageValue and not driver.events.UNIT_AURA, "Hidden bars stop scanning")
C.bars.cooldown.hidden = false
Coverage.Update(icon)
Tick()
assert(icon.totemCoverageValue == "2/3")
Coverage.Retire(icon)
assert(not next(driver.events) and not icon.totemCoverageValue)
Coverage.Sync(icon, entry)
Tick()
assert(driver.events.UNIT_AURA)
print("suite_cdm_totem_coverage_contract: OK")
