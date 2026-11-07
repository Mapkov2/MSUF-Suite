-- Presets are isolated value maps; extended slots retain every field through
-- edits, imports and runtime refreshes without allocating extra default bars.
local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local xp, level, rested, fps, xpReads = 50, 20, 20, 120, 0
    local W = H.New(root, flavor, { clientCombatOrder = true, beforeModules = function(world)
        local G = world.G
        G.GetGameTime = function() return 12, 34 end
        G.GetFramerate = function() return fps end
        G.GetNetStats = function() return 0, 0, 18, 24 end
        G.GetMoney = function() return 420000 end
        G.GetInventoryItemDurability = function() return 80, 100 end
        G.C_Container = {
            GetContainerNumSlots = function() return 20 end,
            GetContainerNumFreeSlots = function() return 8, 0 end,
        }
        G.GetProfessions = function() return 1, nil end
        G.GetProfessionInfo = function() return "Alchemy", 123, 50, 100 end
        G.UnitLevel = function() return level end
        G.UnitXP = function()
            xpReads = xpReads + 1
            return xp
        end
        G.UnitXPMax = function() return 100 end
        G.GetMaxPlayerLevel = function() return 80 end
        G.GetXPExhaustion = function() return rested end
        G.HONOR_LEVEL_LABEL = "Honor Level %d"
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
    assert(#full == count and #NS.DataTextPresets == 7, "preset gallery lost a starting purpose")
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
    local menu = NS.DataTextPresetValues("microMenu", 1, c)
    assert(menu.bar1Width == 180 and menu.bar1Height == 26 and menu.bar1Look == 5 and not menu.bar1FullScreen)
    assert(menu.bar1Slot1 == NS.DataTextSourceIndex.microMenu and menu.bar1Slot2 == NS.DataTextSourceIndex.none)
    assert(S.SetMany("dataTexts", menu))
    assert(bar.slots[1].text == NS.Text("Menu") and not M.timer, "the menu-only preset did not render a static button")
    assert(S.SetMany("dataTexts", { bar1Slot1MenuLabel = "  Character | options  ", bar1ShowLabels = true }))
    assert(bar.slots[1].text == "Character || options", "the custom button label was prefixed or parsed as markup")
    assert(S.Set("dataTexts", "bar1Slot1MenuLabel", "   "))
    assert(bar.slots[1].text == NS.Text("Menu"), "an empty caption did not restore the default")
    local modern = NS.DataTextPresetValues("modern", 1, c)
    assert(modern.bar1Dock == NS.DataTextDock.TOP and modern.bar1FullScreen and modern.bar1Height == 26)
    assert(modern.bar1Slot2 == NS.DataTextSourceIndex.progressBar and modern.bar1Slot4Placement == NS.DataTextPlacement.CENTER)
    assert(modern.bar1Look == 5 and not modern.bar1AccentEnabled and not modern.bar1BorderEnabled)
    assert(S.SetMany("dataTexts", modern))
    local progress = bar.slots[2]
    local visual = assert(progress.dataProgress)
    assert(progress.text == "50% to level 21" and visual.track.shown, "Modern progress did not render")
    assert(visual.fill.width == visual.width * .5, "Modern XP fill is incorrect")
    assert(visual.bonus.width == visual.width * .7, "Modern rested XP fill is incorrect")
    assert(S.Set("dataTexts", "bar1Layout", NS.DataTextLayout.FIT))
    local sizes = W.calls["SetSize:Button"]
    xp, rested = 57, 0
    W.Event("PLAYER_XP_UPDATE", "player")
    assert(progress.text == "57% to level 21" and not visual.bonus.shown)
    assert(W.calls["SetSize:Button"] == sizes, "changing XP moved the slots of a Fit bar")
    rested = W.secret
    W.Event("UPDATE_EXHAUSTION")
    assert(progress.text == "57% to level 21" and not visual.bonus.shown, "secret rested XP altered the bar")
    xp, rested = W.secret, 0
    W.Event("PLAYER_XP_UPDATE", "player")
    assert(not visual.track.shown, "secret XP left a stale fill")
    xp = 57
    W.Event("PLAYER_XP_UPDATE", "player")

    assert(M.timer and M.context.callbacks.PLAYER_XP_UPDATE)
    W.SetCombat(true)
    assert(not M.timer and not next(M.events) and W.ContextPending(M.context) == 0,
        "a DataTexts timer or data event stayed armed in combat")
    for event in pairs(M.context.callbacks) do
        assert(event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED", event .. " stayed registered")
    end
    assert(not bar.frame.scripts.OnShow and not bar.frame.scripts.OnHide, "visibility still dispatches Lua in combat")
    local xpBefore = xpReads
    xp, fps = 80, 91
    W.Event("PLAYER_XP_UPDATE", "player")
    W.Event("PLAYER_MONEY")
    W.Event("UPDATE_FACTION")
    W.Advance(70)
    assert(xpReads == xpBefore and progress.text == "57% to level 21" and bar.slots[7].text == "120 fps",
        "DataTexts read or painted data in combat")
    W.SetCombat(false)
    assert(M.timer and M.context.callbacks.PLAYER_XP_UPDATE and bar.frame.scripts.OnShow,
        "combat exit did not restore sampling and visibility")
    assert(xpReads == xpBefore + 1 and progress.text == "80% to level 21" and bar.slots[7].text == "91 fps",
        "the post-combat refresh did not catch up in one pass")

    local rep = { name = "Test Faction", label = "Friendly", current = 25, maximum = 100 }
    S.ReputationProgress = function() return rep end
    level = 80
    W.Event("PLAYER_LEVEL_UP")
    assert(progress.text == "Test Faction · 25%" and visual.fill.width == visual.width * .25)
    rep = nil
    S.HonorProgress = function() return 60, 100, 7 end
    W.Event("UPDATE_FACTION")
    assert(progress.text == "Honor Level 7 · 60%" and visual.fill.width == visual.width * .6)
    S.HonorProgress = function() end
    W.Event("HONOR_XP_UPDATE")
    assert(not visual.track.shown, "no progress left a stale fill")
    level = 20
    assert(S.SetMany("dataTexts", values))
    assert(not visual.track.shown, "switching presets left a stale progress track")
    assert(S.SetMany("dataTexts", { bar1Slot12 = NS.DataTextSourceIndex.microMenu, bar1Slot12Scale = 125,
        bar1Slot12MenuLabel = "Character", bar1Slot12Broker = "Keep me", bar1Slot12Currency = 202, bar1Slot12MaxWidth = 410,
        bar1Slot12Placement = 3, bar1Slot12Padding = 9, bar1Slot12Background = "123456",
        bar1Slot12Alpha = 70, bar1Slot12IconColor = "abcdef" }))
    assert(#bar.slots == 12 and bar.slots[12].text == "Character", "the twelfth slot lost its caption")
    local moved = NS.DataTextMoveSlotValues(c, 1, 12, 1)
    for _, suffix in ipairs(NS.DataTextSlotSuffixes) do
        assert(moved["bar1Slot1" .. suffix] == c["bar1Slot12" .. suffix], "move lost slot field " .. suffix)
        assert(moved["bar1Slot2" .. suffix] == c["bar1Slot1" .. suffix], "move broke stable ordering " .. suffix)
    end
    assert(S.SetMany("dataTexts", moved))
    assert(bar.slots[1].text == "Character", "reordering lost the menu caption")
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
