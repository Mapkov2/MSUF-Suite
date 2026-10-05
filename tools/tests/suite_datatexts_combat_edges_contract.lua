-- DataTexts events against the client's registration rules, on Retail and
-- WoW Forever:
--   * PLAYER_SPECIALIZATION_CHANGED carries a unit (UnitDocumentation.lua,
--     live and forever): a group member's spec swap never reformats the
--     player's Specialization places.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")

local function World(flavor, reads)
    local W = H.New(root, flavor, { clientSecurity = true, beforeModules = function(world)
        local G = world.G
        G.GetMoney = function() return 120000 end
        G.C_Container = {
            GetContainerNumSlots = function() return 20 end,
            GetContainerNumFreeSlots = function() return 8, 0 end,
        }
        G.PlayerHasToy = function() return false end
        G.C_Item = { GetItemCount = function() return 0 end, GetItemInfo = function() end }
        G.GetSpecialization, G.GetSpecializationInfo = nil, nil
        G.C_SpecializationInfo = {
            GetSpecialization = function() reads.spec = reads.spec + 1; return 1 end,
            GetSpecializationInfo = function() return 62, "Arcane", "", 135932 end,
        }
        G.GetLootSpecialization = function() return 0 end
        G.C_Spell = { GetSpellCooldownDuration = function() return nil end }
    end })
    -- Frame:RegisterUnitEvent: the client delivers the event only when its
    -- first payload is one of the registered units; RegisterEvent drops the filter.
    local F = getmetatable(W.UIParent)
    local RegisterEvent = F.RegisterEvent
    function F:RegisterUnitEvent(event, ...)
        self.events[event] = true
        self.unitFilters = self.unitFilters or {}
        local units = {}
        for i = 1, select("#", ...) do units[select(i, ...)] = true end
        self.unitFilters[event] = units
    end
    function F:RegisterEvent(event)
        RegisterEvent(self, event)
        if self.unitFilters then self.unitFilters[event] = nil end
    end
    return W
end

-- W.Event with the client's unit filters.
local function UnitEvent(W, event, unit)
    for _, frame in ipairs(W.frames) do
        local units = frame.unitFilters and frame.unitFilters[event]
        if frame.events[event] and (not units or units[unit]) then W.Fire(frame, "OnEvent", event, unit) end
    end
end

local function Choice(NS, key)
    for index, value in ipairs(NS.DataTextSourceKeys) do
        if value == key then return index end
    end
    error("unknown DataText source " .. key)
end

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local reads = { spec = 0 }
    local W = World(flavor, reads)
    local S, NS = W.S, W.Suite
    W.LoadAddon("MSUF_Suite_DataTexts")
    local M = assert(S.instances.dataTexts)
    S.Start()
    assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true,
        bar1Slot1 = Choice(NS, "specialization"), bar1Slot2 = Choice(NS, "specLoot"), bar1Slot3 = 1,
        bar1Slot4 = 1, bar1Slot5 = 1, bar1Slot6 = 1 }))
    local spec = M.bars[1].slots[1]
    assert(spec.text == "Specialization: Arcane", "the specialization place did not render: " .. flavor)

    -- A raid member swaps spec: the event carries their unit.
    reads.spec = 0
    for _, unit in ipairs({ "raid7", "party2", "target" }) do UnitEvent(W, "PLAYER_SPECIALIZATION_CHANGED", unit) end
    assert(reads.spec == 0, "a group member's spec swap reformatted the specialization places: " .. flavor)
    -- The player's own swap still updates them.
    UnitEvent(W, "PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(reads.spec > 0, "the player's spec swap did not update the specialization places: " .. flavor)
    print("Suite DataTexts combat edges and unit events passed: " .. flavor)
end
