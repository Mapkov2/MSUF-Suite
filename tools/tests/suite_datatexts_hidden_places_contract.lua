-- DataTexts places that are configured but not shown when the bars refresh
-- (a Mouseover bar not hovered yet, a bar a load condition hides) work once
-- they show, on Retail and WoW Forever:
--   * a Hearthstone place has its Hearthstone: the text names it and the
--     secure overlay uses it (hovering a Mouseover bar only rebinds);
--   * Retail: a Crests place observes the season's upgrade stages.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local MOUSEOVER = 4

local function Choice(NS, key)
    for index, value in ipairs(NS.DataTextSourceKeys) do
        if value == key then return index end
    end
    error("unknown DataText source " .. key)
end

local function World(flavor, extra)
    return H.New(root, flavor, { clientSecurity = true, beforeModules = function(world)
        local G = world.G
        G.GetMoney = function() return 120000 end
        G.C_Container = {
            GetContainerNumSlots = function() return 20 end,
            GetContainerNumFreeSlots = function() return 8, 0 end,
        }
        G.PlayerHasToy = function() return false end
        G.C_Item = {
            GetItemCount = function(id) return id == 6948 and 1 or 0 end,
            GetItemInfo = function(id)
                return id == 6948 and "Hearthstone" or nil, nil, nil, nil, nil, nil, nil, nil, nil, 134414
            end,
        }
        G.C_Spell = { GetSpellCooldownDuration = function() return nil end }
        if extra then extra(world) end
    end })
end

local function Hover(W, bar, place, hovered)
    bar.frame.mouseOver, place.mouseOver = hovered, hovered
    if hovered then
        W.Fire(bar.frame, "OnEnter")
        W.Fire(place, "OnEnter")
    else
        W.Fire(place, "OnLeave")
        W.Fire(bar.frame, "OnLeave")
    end
end

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local W = World(flavor)
    local G, S, NS = W.G, W.S, W.Suite
    function G.GameTooltip:SetItemByID(id) self.lines = { "item:" .. id } end
    W.LoadAddon("MSUF_Suite_DataTexts")
    local M = assert(S.instances.dataTexts)
    local A = W.private.DataTextActions
    S.Start()
    assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true, bar1Visibility = MOUSEOVER,
        bar1Slot1 = Choice(NS, "clock"), bar1Slot2 = Choice(NS, "hearth"), bar1Slot3 = 1, bar1Slot4 = 1,
        bar1Slot5 = 1, bar1Slot6 = 1 }))
    local bar = assert(M.bars[1])
    local hearth = bar.slots[2]
    assert(not (M.activeSources or {})[hearth.source], "a Mouseover bar that is not hovered counted as shown")
    -- The first hover after login: the place names its Hearthstone and the
    -- overlay uses it.
    Hover(W, bar, hearth, true)
    assert(hearth.extra.hearth and hearth.extra.hearth.id == 6948,
        "the Hearthstone place of a Mouseover bar has no Hearthstone: " .. flavor)
    assert(hearth.text == "Hearthstone: Hearthstone",
        "the Hearthstone place of a Mouseover bar shows " .. tostring(hearth.text) .. ": " .. flavor)
    local overlay = A.overlay
    assert(overlay and overlay.shown and overlay.owner == hearth and overlay:GetAttribute("item1") == "item:6948",
        "the Hearthstone place of a Mouseover bar has no secure overlay: " .. flavor)
    local before = #W.secureActions
    W.Click(overlay)
    local used = W.secureActions[#W.secureActions]
    assert(#W.secureActions == before + 1 and used.type == "item" and used.item == "item:6948",
        "clicking the Hearthstone place of a Mouseover bar used nothing: " .. flavor)
    Hover(W, bar, hearth, false)
    W.Fire(overlay, "OnLeave")
    G.C_Item.GetItemCount = function() return 0 end
    W.Event("BAG_UPDATE_DELAYED")
    assert(hearth.extra.hearth == nil, "hidden hearth place retained a lost item")
    Hover(W, bar, hearth, true)
    assert(not overlay.shown, "first show offered a stale secure hearth action")
    print("Suite DataTexts hidden places passed: " .. flavor)
end

-- Retail: a Crests place in the default "Observed upgrade stages" mode on a
-- Mouseover bar observes the season's stages while an item sits in
-- Blizzard's upgrade frame (ITEM_UPGRADE_MASTER_SET_ITEM;
-- C_ItemUpgrade.GetItemUpgradeItemInfo returns nothing once it closes), so
-- the place shows them when it is hovered later.
do
    local upgradeInfo
    local W = World("Mainline", function(world)
        local G = world.G
        G.C_Item = { GetItemCount = function() return 0 end, GetItemInfo = function() end }
        G.C_CurrencyInfo = { GetCurrencyInfo = function(id)
            if id == 3008 then return { name = "Valorstones", quantity = 1500, iconFileID = 1, discovered = true } end
            if id == 3107 then return { name = "Weathered Crest", quantity = 45, iconFileID = 2, discovered = true } end
        end }
        G.C_ItemUpgrade = { GetItemUpgradeItemInfo = function() return upgradeInfo end }
    end)
    local S, NS = W.S, W.Suite
    W.LoadAddon("MSUF_Suite_DataTexts")
    local M = assert(S.instances.dataTexts)
    local X = W.private.DataTextSources
    S.Start()
    assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true, bar1Visibility = MOUSEOVER,
        bar1Slot1 = Choice(NS, "clock"), bar1Slot2 = Choice(NS, "crests"), bar1Slot3 = 1, bar1Slot4 = 1,
        bar1Slot5 = 1, bar1Slot6 = 1 }))
    local bar = assert(M.bars[1])
    local crests = bar.slots[2]
    assert(S.Config("dataTexts").crestMode ~= NS.DataTextCrestMode.SELECTED, "the default crest mode is not Observed")
    upgradeInfo = { name = "Some Helm", upgradeCostTypesForSeason = {
        { orderIndex = 1, currencyID = 3008, sourceString = "a" },
        { orderIndex = 2, currencyID = 3107, sourceString = "b" } } }
    W.Event("ITEM_UPGRADE_MASTER_SET_ITEM")
    upgradeInfo = nil
    W.Step()
    assert(X.seasonCosts and #X.seasonCosts == 2,
        "a Crests place on a Mouseover bar did not observe the upgrade stages")
    Hover(W, bar, crests, true)
    assert(crests.text == "Crests: 1500 / 45", "the hovered Crests place shows " .. tostring(crests.text))
    print("Suite DataTexts hidden Crests place passed: Mainline")
end
