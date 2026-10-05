-- DataTexts popups (micro menu, travel, portals) stay on the screen, on
-- Retail and WoW Forever:
--   * on a bar docked to the top (the shipped "Top information bar" preset)
--     the popup opens below its place, not above the screen edge;
--   * a list taller than the room beside the place wraps into columns, no
--     more than the screen is wide;
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

    -- A list too long for the columns that fit beside a place in the middle
    -- of the screen takes the screen's height instead of running off its
    -- sides: the clamped popup stays whole on the screen, every row inside
    -- it. On a narrow screen the entries that fit no row scroll into the rows
    -- with the mouse wheel: every entry stays reachable.
    local function Whole(label)
        local count = 0
        for i = 1, #popup.rows do
            local row = popup.rows[i]
            if row.shown then
                count = count + 1
                local rowPoint = row.points[1]
                assert(rowPoint[4] >= 4 and rowPoint[4] + 232 <= popup.width - 4
                    and rowPoint[5] <= -4 and -rowPoint[5] + 24 <= popup.height - 4,
                    label .. ": travel row " .. i .. " sits outside its popup: " .. flavor)
            end
        end
        assert(popup.shown and popup:IsClampedToScreen() and popup.width <= W.UIParent:GetWidth()
            and popup.height <= W.UIParent:GetHeight(),
            label .. ": a " .. popup.width .. " x " .. popup.height .. " popup does not fit the screen: " .. flavor)
        return count
    end
    for i = OWNED + 1, 100 do ids[i] = tostring(1000 + i) end
    places = Apply("infoBottom")
    travel = assert(places.travel)
    travel.rect = { 400, SCREEN / 2 - 14, 100, 28 }
    W.Click(travel)
    popup = A.popup
    assert(Whole("centered place") == 100, "a centered travel popup dropped rows the screen has room for: " .. flavor)
    assert(not popup:IsMouseWheelEnabled(), "a travel popup that shows its whole list took the mouse wheel: " .. flavor)
    W.Click(popup.rows[1])
    W.UIParent.width = 700
    W.Click(travel)
    local slots = Whole("narrow screen")
    assert(slots > OWNED and slots < 100, "a narrow screen showed " .. slots .. " travel rows: " .. flavor)
    assert(popup:IsMouseWheelEnabled(), "a travel popup with more entries than rows ignores the mouse wheel: " .. flavor)
    -- The entry each row shows and uses, by its place in the list.
    local function Entry(row)
        local item = row:GetAttribute("item")
        local id = tonumber(item and item:match("^item:(%d+)$"))
        assert(id and row.label:GetText() == "Item " .. id, "a travel row shows another entry than it uses: " .. flavor)
        return id - 1000
    end
    local reached, first = {}, Entry(popup.rows[1])
    local function Look(label, offset)
        assert(Whole(label) == slots, label .. ": the travel popup changed its rows while scrolling: " .. flavor)
        for i = 1, slots do
            local entry = Entry(popup.rows[i])
            assert(entry == offset + i, label .. ": travel row " .. i .. " shows entry " .. entry .. ": " .. flavor)
            reached[entry] = true
        end
    end
    assert(first == 1, "a narrow screen's travel popup does not start at the first entry: " .. flavor)
    Look("narrow screen", 0)
    for offset = 1, 100 - slots do
        W.Fire(popup, "OnMouseWheel", -1)
        Look("scrolled " .. offset, offset)
    end
    W.Fire(popup, "OnMouseWheel", -1)
    Look("past the end", 100 - slots)
    for entry = 1, 100 do
        assert(reached[entry], "travel entry " .. entry .. " of 100 is unreachable on a narrow screen: " .. flavor)
    end
    -- The last entry performs its own action from its row.
    local last = popup.rows[slots]
    local actions = #W.secureActions
    W.Click(last)
    local record = W.secureActions[actions + 1]
    assert(record and record.frame == last and record.item == "item:1100" and not popup.shown,
        "the last travel entry of a scrolled popup does not use its Hearthstone: " .. flavor)
    -- A popup opened again starts at the top; the wheel back up gets there too.
    W.Click(travel)
    Look("opened again", 0)
    W.Fire(popup, "OnMouseWheel", -1)
    W.Fire(popup, "OnMouseWheel", -1)
    W.Fire(popup, "OnMouseWheel", 1)
    Look("wheel up", 1)
    W.Fire(popup, "OnMouseWheel", 1)
    W.Fire(popup, "OnMouseWheel", 1)
    Look("above the start", 0)
    -- In combat the popup is hidden and the wheel leaves its secure rows alone.
    W.Fire(popup, "OnMouseWheel", -1)
    W.SetCombat(true)
    assert(not popup:IsVisible(), "the travel popup stayed visible in combat: " .. flavor)
    W.Fire(popup, "OnMouseWheel", -1)
    W.SetCombat(false)
    assert(Entry(popup.rows[1]) == 2, "the wheel scrolled the secure travel rows in combat: " .. flavor)
    W.Click(travel)
    W.Click(popup.rows[1])
    W.UIParent.width = 1366
    for i = OWNED + 1, 100 do ids[i] = nil end
    places = Apply("infoBottom")
    travel = assert(places.travel)

    -- A place the client has not laid out yet keeps the old upward popup.
    travel.rect = nil
    W.Click(travel)
    point = popup.points[1]
    assert(popup.shown and point[1] == "BOTTOMLEFT" and point[2] == travel, "a place without edges lost its popup: " .. flavor)
    W.Click(popup.rows[1])
    print("Suite DataTexts popup placement passed: " .. flavor)
end
