local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, attempts, lookups, notices, reported = nil, {}, {}, {}, {}
local frames = Support.EventFrames()
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
    -- The client refuses a restricted action with ADDON_ACTION_BLOCKED while
    -- the call runs; no Lua error reaches the caller.
    CancelAuraByInstanceID = function(unit, instanceID)
        assert(unit == "player", "only the player's aura may be canceled")
        if blocked then
            frames.Fire("ADDON_ACTION_BLOCKED", "MSUF_Suite_QualityOfLife", "C_UnitAuras.CancelAuraByInstanceID()")
            return
        end
        attempts[#attempts + 1] = instanceID
    end,
}
local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Install = function(id, instance) assert(id == "professionAppearance"); module = instance end,
    CreateFrame = frames.Create,
    Dispatch = Support.Dispatcher(reported),
}
Support.QoLStyleFixture(root, S)
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
local before = #attempts
module:Enable()
assert(module.blocked and #notices == 1 and not context.events.UNIT_AURA and #attempts == before,
    "a blocked aura cancellation did not fail closed")
module:Disable()
blocked = false
-- A restricted aura lookup returns nothing (RequiresNonSecretAura).
C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
module:Enable()
assert(not module.blocked and #notices == 1 and #attempts == before and #reported == 0,
    "a restricted aura lookup canceled something or stopped the helper")
print("suite_profession_appearance_contract: ok")

-- Explicit cosmetic IDs use the same bounded delta/after-combat owner.
blocked, combat = false, false
C_UnitAuras.GetPlayerAuraBySpellID = function(id) return auras[id] end
module.config = { cosmeticSpellIDs = "12345, 12345, 394009" }
auras[12345] = Aura(12345, 765)
module.active = true; module:Refresh()
assert(module.extraSpells[12345] and not module.extraSpells[394009] and #module.scanIDs == 13)
assert(attempts[#attempts] == 765)
combat = true; auras[12345] = Aura(12345, 766)
context.events.UNIT_AURA(module, "UNIT_AURA", "player", { addedAuras = { auras[12345] } })
assert(attempts[#attempts] == 765)
combat = false; context.events.PLAYER_REGEN_ENABLED(module)
assert(attempts[#attempts] == 766)
module.config = { orbDeception = true, holidayCostumes = true, noggenfoggerSkeleton = true }
auras[16739], auras[16591], auras[24713] = Aura(16739, 801), Aura(16591, 802), Aura(24713, 803)
module:Refresh()
assert(module.extraSpells[16739] and module.extraSpells[16591] and module.extraSpells[24713])
local canceled = {}
for _, id in ipairs(attempts) do canceled[id] = true end
assert(canceled[801] and canceled[802] and canceled[803], "selected toy, holiday and consumable presets must cancel")
assert(not module.extraSpells[16593] and not module.extraSpells[16595], "other elixir effects must remain")
module.config = {}; module:Refresh()
assert(not next(module.extraSpells) and not context.events.UNIT_AURA, "presets must be explicitly selected")
