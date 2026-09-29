local root = assert(arg[1], "repository root required")
local module, attempts, lookups, notices = nil, {}, {}, {}
local combat, blocked = false, false
local auras = {}
local function Aura(spellID, instanceID)
    return { spellId = spellID, auraInstanceID = instanceID, isHelpful = true }
end

C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellID)
        lookups[#lookups + 1] = spellID
        return auras[spellID]
    end,
    CancelAuraByInstanceID = function(unit, instanceID)
        assert(unit == "player", "only the player's aura may be canceled")
        if blocked then error("client restriction") end
        attempts[#attempts + 1] = instanceID
    end,
}
local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Install = function(id, instance) assert(id == "professionAppearance"); module = instance end,
}
local NS = {
    IsCombatLocked = function() return combat end,
    Print = function(value) notices[#notices + 1] = value end,
}
local context = { events = {} }
function context:Event(name, callback, _, unit)
    self.events[name] = callback
    if name == "UNIT_AURA" then assert(unit == "player", "aura event was not unit filtered") end
end
function context:RemoveEvent(name) self.events[name] = nil end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ProfessionAppearance.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
module.config = { herbalism = true, mining = true, skinning = true,
    tailoring = true, leatherworking = true, alchemy = true,
    blacksmithing = true, cooking = true, enchanting = true,
    engineering = true, inscription = true, jewelcrafting = true }
auras[394005] = Aura(394005, 10)
auras[394009] = Aura(394009, 99) -- Fishing is deliberately excluded.
auras[394006] = "secret"
module:Enable()
assert(#lookups == 12 and #attempts == 1 and attempts[1] == 10,
    "initial scan did not target only the twelve known non-fishing appearances")
assert(context.events.UNIT_AURA and context.events.PLAYER_REGEN_ENABLED,
    "event-driven appearance handling was not installed")

local function Update(unit, info)
    context.events.UNIT_AURA(module, "UNIT_AURA", unit, info)
end
Update("target", { isFullUpdate = false, addedAuras = { Aura(394006, 11) } })
Update("secret", { isFullUpdate = false, addedAuras = { Aura(394006, 11) } })
Update("player", "secret")
Update("player", { isFullUpdate = false, addedAuras = "secret" })
Update("player", { isFullUpdate = false, addedAuras = { "secret", Aura(394009, 99) } })
assert(#attempts == 1, "secret, other-unit or fishing aura was canceled")

combat = true
Update("player", { isFullUpdate = false, addedAuras = { Aura(394006, 11) } })
assert(#attempts == 1, "aura was canceled during combat")
combat = false
Update("player", { isFullUpdate = false, addedAuras = { Aura(394006, 11) } })
Update("player", { isFullUpdate = false, addedAuras = { Aura(394006, 11) } })
assert(#attempts == 2 and attempts[2] == 11, "added aura did not cancel once")
Update("player", { isFullUpdate = false, removedAuraInstanceIDs = { 11 },
    addedAuras = { Aura(394006, 11) } })
assert(#attempts == 3, "removed aura instance was not released")

auras[394011] = Aura(394011, 12)
Update("player", { isFullUpdate = true })
assert(#attempts == 4 and attempts[4] == 12, "full update did not query known IDs")
auras[394006] = Aura(394006, 13)
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
local foundMining = false
for _, instanceID in ipairs(attempts) do
    if instanceID == 13 then foundMining = true end
end
assert(foundMining, "post-combat targeted rescan missed a profession aura")

module.config.mining = false
module:Refresh()
Update("player", { isFullUpdate = false, addedAuras = { Aura(394006, 14) } })
assert(attempts[#attempts] ~= 14, "disabled profession still canceled")
module:Disable()
module.active = false
assert(not context.events.UNIT_AURA and not context.events.PLAYER_REGEN_ENABLED,
    "disable left aura events active")

module.active = true
module.config = { herbalism = true }
auras[394005] = Aura(394005, 20)
blocked = true
module:Enable()
assert(module.blocked and #notices == 1 and not context.events.UNIT_AURA,
    "client API refusal did not fail closed")
module:Disable()
blocked = false
C_UnitAuras.GetPlayerAuraBySpellID = function() error("aura access restricted") end
module:Enable()
assert(module.blocked and #notices == 2 and not context.events.UNIT_AURA,
    "restricted targeted aura lookup did not fail closed")
print("suite_profession_appearance_contract: ok")
