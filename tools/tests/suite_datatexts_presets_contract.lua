-- Presets are isolated value maps; extended slots retain every field through
-- edits, imports and runtime refreshes without allocating extra default bars.
local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local W = H.New(root, flavor, { beforeModules = function(world)
        local G = world.G
        G.GetGameTime = function() return 12, 34 end
        G.GetFramerate = function() return 120 end
        G.GetNetStats = function() return 0, 0, 18, 24 end
        G.GetMoney = function() return 420000 end
        G.GetInventoryItemDurability = function() return 80, 100 end
        G.C_Container = {
            GetContainerNumSlots = function() return 20 end,
            GetContainerNumFreeSlots = function() return 8, 0 end,
        }
        G.GetProfessions = function() return 1, nil end
        G.GetProfessionInfo = function() return "Alchemy", 123, 50, 100 end
        G.UnitLevel = function() return 20 end
        G.UnitXP = function() return 50 end
        G.UnitXPMax = function() return 100 end
        G.GetMaxPlayerLevel = function() return 80 end
        G.C_SpecializationInfo = {
            GetSpecialization = function() return 1 end,
            GetSpecializationInfo = function() return 62, "Arcane", "", 123 end,
        }
        G.GetLootSpecialization = function() return 63 end
        G.GetSpecializationInfoByID = function() return 63, "Fire" end
        G.PlayerHasToy = function() return false end
        G.C_Item = { GetItemCount = function() return 0 end }
    end })
    local S, NS = W.S, W.Suite
    local c = S.Config("dataTexts")
    local rules = S.catalog.dataTexts.rules
    assert(NS.DataTextSlotLimit == 12, "the preset editor needs twelve bounded slots")
    assert(c.bar1Slot7 == nil and rawget(rules, "bar1Slot7") == nil,
        "unused extended slots must not seed physical rules or profile defaults")
    assert(rules.bar1Slot12 and rules.bar1Slot12Scale and not rules.bar1Slot13,
        "extended slot rules must be lazy and bounded")
    local selectedControls = NS.DataTextBarControls(c, 1)
    assert(#selectedControls > 100, "selected-bar editor did not receive its complete rule set")
    for _, rule in ipairs(selectedControls) do
        assert(rule.key:match("^bar(%d+)") == "1", "selected-bar controls include another bar")
    end
    local old = { false, "gold", "bags", "durability", "clock", "fps", "latency", "coordinates", "location", "xp",
        "sessionGold", "date", "fpsLatency", "broker", "currency", "crests", "itemLevel", "professions",
        "specialization", "audio", "hearth", "progress", "portals", "microMenu" }
    for index, source in ipairs(old) do assert(NS.DataTextSourceKeys[index] == source, "legacy source index changed") end
    W.LoadAddon("MSUF_Suite_DataTexts")
    S.Start()
    local M = S.instances.dataTexts
    assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true }))
    assert(#M.bars[1].slots == 6, "legacy bars must retain their six-place allocation")
    local count = flavor == "Forever" and 9 or 10
    local full = NS.DataTextPresetSources("infoTop")
    assert(#full == count and #NS.DataTextPresets == 6, "preset gallery lost a starting purpose")
    assert(NS.DataTextSourceAvailable("specLoot") == (flavor == "Mainline"))
    local beforeName, beforeSource = c.bar1Name, c.bar1Slot1
    local values = NS.DataTextPresetValues("infoTop", 1, c)
    assert(c.bar1Name == beforeName and c.bar1Slot1 == beforeSource, "previewing a preset changed saved configuration")
    assert(values.bar1Dock == NS.DataTextDock.TOP and values.bar1FullScreen,
        "top information preset must dock across the screen")
    assert(S.SetMany("dataTexts", values))
    local bar = M.bars[1]
    assert(#bar.slots == count, "extended runtime slots were not created on demand")
    for slot, key in ipairs(full) do
        local button = bar.slots[slot]
        assert(button.source and button.text, "preset source is missing from runtime: " .. key)
        assert(c["bar1Slot" .. slot] == NS.DataTextSourceIndex[key])
        if key == "clock" then
            assert(c["bar1Slot" .. slot .. "Placement"] == NS.DataTextPlacement.CENTER, "preset clock must be centered")
        elseif key == "specLoot" then
            assert(button.text:find("Arcane / Loot: Fire", 1, true), "combined specialization source lost loot specialization")
        end
    end
    assert(NS.DataTextPresetValues("infoBottom", 1, c).bar1Dock == NS.DataTextDock.BOTTOM)
    assert(S.SetMany("dataTexts", { bar1Slot12 = NS.DataTextSourceIndex.fps, bar1Slot12Scale = 125,
        bar1Slot12Broker = "Keep me", bar1Slot12Currency = 202, bar1Slot12MaxWidth = 410,
        bar1Slot12Placement = 3, bar1Slot12Padding = 9, bar1Slot12Background = "123456",
        bar1Slot12Alpha = 70, bar1Slot12IconColor = "abcdef" }))
    assert(#bar.slots == 12 and bar.slots[12].text, "twelfth slot must render")
    local moved = NS.DataTextMoveSlotValues(c, 1, 12, 1)
    for _, suffix in ipairs(NS.DataTextSlotSuffixes) do
        assert(moved["bar1Slot1" .. suffix] == c["bar1Slot12" .. suffix], "move lost slot field " .. suffix)
        assert(moved["bar1Slot2" .. suffix] == c["bar1Slot1" .. suffix], "move broke stable ordering " .. suffix)
    end
    assert(S.SetMany("dataTexts", moved))
    local removed = NS.DataTextRemoveSlotValues(c, 1, 1)
    for _, suffix in ipairs(NS.DataTextSlotSuffixes) do
        assert(removed["bar1Slot1" .. suffix] == c["bar1Slot2" .. suffix], "remove lost following slot field " .. suffix)
        assert(removed["bar1Slot12" .. suffix] == rules["bar1Slot12" .. suffix].default)
    end
    assert(not NS.DataTextMoveSlotValues(c, 1, 0, 4) and not NS.DataTextRemoveSlotValues(c, 1, 13))
    local newID = NS.DataTextNextBarID(c)
    local copy = NS.DataTextDuplicateBarValues(c, 1, newID)
    for _, suffix in ipairs(NS.DataTextSlotSuffixes) do
        assert(copy["bar" .. newID .. "Slot1" .. suffix] == c["bar1Slot1" .. suffix])
    end
    assert(copy["bar" .. newID .. "Name"] ~= c.bar1Name and not copy.bar1Name, "duplicate changed original bar")
    assert(S.SetMany("dataTexts", copy) and M.bars[newID], "duplicated extended bar did not activate")
    assert(S.Set("dataTexts", "bar1Name", string.rep("A", 64)))
    local namedID = NS.DataTextNextBarID(c)
    local longCopy = NS.DataTextDuplicateBarValues(c, 1, namedID)
    assert(#longCopy["bar" .. namedID .. "Name"] <= 64 and S.SetMany("dataTexts", longCopy),
        "maximum-length bar names must remain duplicable")
    local character = "\228\184\128"
    assert(S.Set("dataTexts", "bar1Name", string.rep(character, 21)))
    local unicodeCopy = NS.DataTextDuplicateBarValues(c, 1, NS.DataTextNextBarID(c))
    local copiedName = unicodeCopy["bar" .. NS.DataTextNextBarID(c) .. "Name"]
    assert(copiedName == "Copy of " .. string.rep(character, 18), "duplicate clipped inside a UTF-8 character")
    local empty = NS.DataTextPresetValues("empty", 1, c)
    for slot = 1, 12 do assert(empty["bar1Slot" .. slot] == 1, "empty preset inherited default content") end
    assert(empty.bar1Slot1Scale == 100 and empty.bar1Slot1Broker == "", "preset retained hidden slot customization")
    local creation = NS.DataTextBarCreationValues(c, NS.DataTextNextBarID(c), "minimap")
    assert(creation and not creation.bar1Slot1 and not creation.bar1X, "new preset changed an existing bar")
    assert(not NS.DataTextPresetValues("unknown", 1, c), "unknown preset must not mutate anything")
    local imported = { suite = { modules = { dataTexts = { bar1Slot12 = 6, bar1Slot12Scale = 999,
        bar1Slot12IconColor = "invalid" } } } }
    S.Normalize(imported)
    local importedData = imported.suite.modules.dataTexts
    assert(importedData.bar1Slot12 == 6 and importedData.bar1Slot12Scale <= 200
        and importedData.bar1Slot12IconColor ~= "invalid", "extended slot import bypassed validation")
    local fresh = { suite = { modules = { dataTexts = {} } } }
    S.Normalize(fresh)
    assert(fresh.suite.modules.dataTexts.bar1Slot7 == nil, "extended defaults leaked into a different profile")
    print("DataTexts preset and extended-slot contract: " .. flavor .. " PASS")
end
