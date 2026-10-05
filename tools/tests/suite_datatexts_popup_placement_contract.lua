-- DataTexts popups (micro menu, travel, portals) stay on the screen, on
-- Retail and WoW Forever:
--   * on a bar docked to the top (the shipped "Top information bar" preset)
--     the popup opens below its place, not above the screen edge;
--   * a list taller than the room beside the place wraps into columns;
--   * the popup is clamped to the screen.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local SCREEN = 768
local OWNED = 45

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local W = H.New(root, flavor, { clientSecurity = true, beforeModules = function(world)
        local G = world.G
        G.GetMoney = function() return 120000 end
        G.C_Container = {
            GetContainerNumSlots = function() return 20 end,
            GetContainerNumFreeSlots = function() return 8, 0 end,
        }
        G.PlayerHasToy = function() return false end
        G.C_Item = {
            GetItemCount = function() return 1 end,
            GetItemInfo = function(id) return "Item " .. id, nil, nil, nil, nil, nil, nil, nil, nil, 123 end,
            GetItemCooldown = function() return 0, 0 end,
        }
        G.C_Spell = { GetSpellCooldownDuration = function() return nil end }
        -- The other places of the information presets.
        G.C_SpecializationInfo = {
            GetSpecialization = function() return 1 end,
            GetSpecializationInfo = function() return 62, "Arcane", "", 135932 end,
        }
        G.GetLootSpecialization = function() return 0 end
        G.GetMaxPlayerLevel, G.UnitLevel = function() return 80 end, function() return 80 end
        G.UnitXP, G.UnitXPMax = function() return 0 end, function() return 1 end
        G.C_Reputation = { GetWatchedFactionData = function() end }
        G.GetProfessions = function() end
        -- Micro buttons Blizzard put into its micro menu (layoutIndex).
        for index, name in ipairs({ "CharacterMicroButton", "QuestLogMicroButton", "MainMenuMicroButton" }) do
            world.New("Button", name, world.UIParent).layoutIndex = index
        end
        local methods = getmetatable(world.UIParent).__index
        methods.SetCooldown = function(self, start, duration) self.cooldownDuration = { start, duration } end
    end })
    local S, NS = W.S, W.Suite
    assert(W.UIParent:GetHeight() == SCREEN, "the harness screen changed")
    W.LoadAddon("MSUF_Suite_DataTexts")
    local M = assert(S.instances.dataTexts)
    local A = W.private.DataTextActions
    S.LearnedDungeonPortals = function() return {} end
    S.Start()
    local ids = {}
    for i = 1, OWNED do ids[i] = tostring(1000 + i) end

    local function Apply(preset)
        local values = NS.DataTextPresetValues(preset, 1, S.Config("dataTexts"))
        values.hearthItems = table.concat(ids, ",")
        assert(S.SetMany("dataTexts", values))
        local places = {}
        for _, place in ipairs(M.bars[1].slots) do
            if place.source then places[place.extra and place.extra.kind or place.source] = place end
        end
        return places
    end

    -- The shipped top bar: its places touch the top of the screen.
    local places = Apply("infoTop")
    for _, kind in ipairs({ "microMenu", "travel" }) do
        local place = assert(places[kind], "the top information bar lost its " .. kind .. " place")
        place.rect = { 0, SCREEN - 28, 100, 28 }
        W.Click(place)
        local popup = assert(A.popup, "the " .. kind .. " place opened no popup: " .. flavor)
        local point = popup.points[1]
        assert(popup.shown and #popup.points == 1 and point[1] == "TOPLEFT" and point[2] == place
            and point[3] == "BOTTOMLEFT" and point[5] < 0,
            "the " .. kind .. " popup of the top bar does not open below its place: " .. flavor)
        assert(popup:IsClampedToScreen(), "the DataTexts popup is not clamped to the screen")
        assert(popup.height + 3 <= SCREEN - 28, "the " .. kind .. " popup is taller than the room below the top bar: " .. flavor)
        W.Click(popup.rows[1])
    end

    -- The bottom bar opens upward as before; a long travel list wraps.
    places = Apply("infoBottom")
    local travel = assert(places.travel, "the bottom information bar lost its travel place")
    travel.rect = { 0, 0, 100, 28 }
    W.Click(travel)
    local popup = A.popup
    local point = popup.points[1]
    assert(popup.shown and point[1] == "BOTTOMLEFT" and point[2] == travel and point[3] == "TOPLEFT" and point[5] > 0,
        "the travel popup of the bottom bar does not open above its place: " .. flavor)
    assert(popup.height + 3 <= SCREEN - 28,
        "a travel popup with " .. OWNED .. " entries runs off the top of the screen: " .. flavor)
    local perColumn = math.floor((popup.height - 8) / 26)
    local columns = math.ceil(OWNED / perColumn)
    assert(columns > 1 and popup.width == 4 + columns * 236, "the long travel list did not wrap into columns: " .. flavor)
    for i = 1, OWNED do
        local row = popup.rows[i]
        local rowPoint = row.points[1]
        assert(row.shown and #row.points == 1 and rowPoint[2] == popup
            and rowPoint[4] == 4 + math.floor((i - 1) / perColumn) * 236 and rowPoint[5] == -4 - (i - 1) % perColumn * 26,
            "travel row " .. i .. " is not in its column: " .. flavor)
    end
    W.Click(popup.rows[1])

    -- A place the client has not laid out yet keeps the old upward popup.
    travel.rect = nil
    W.Click(travel)
    point = popup.points[1]
    assert(popup.shown and point[1] == "BOTTOMLEFT" and point[2] == travel, "a place without edges lost its popup: " .. flavor)
    W.Click(popup.rows[1])
    print("Suite DataTexts popup placement passed: " .. flavor)
end
