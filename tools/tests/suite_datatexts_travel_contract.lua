-- Travel reuses the native secure popup. Owned item/toy actions and learned
-- portals remain usable, while combat drops every protected dependency.
local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local secretCooldown, itemReads = false, 0
    local durationObject = {}
    local W = H.New(root, flavor, { clientSecurity = true, beforeModules = function(world)
        local G = world.G
        G.PlayerHasToy = function(id) return id == 42 end
        G.C_Item = {
            GetItemCount = function(id) itemReads = itemReads + 1; return id == 6948 and 1 or 0 end,
            GetItemInfo = function(id) return "Item " .. id, nil, nil, nil, nil, nil, nil, nil, nil, 123 end,
            GetItemCooldown = function()
                if secretCooldown then return world.secret, world.secret end
                return 10, 1800
            end,
        }
        G.C_Spell = { GetSpellCooldownDuration = function() return durationObject end }
        local frameMethods = getmetatable(world.UIParent).__index
        frameMethods.SetCooldown = function(self, start, duration) self.cooldownDuration = { start, duration } end
    end })
    local S, NS = W.S, W.Suite
    local c = S.Config("dataTexts")
    c.enabled, c.bar1Enabled = false, false
    W.LoadAddon("MSUF_Suite_DataTexts")
    local A, M = W.private.DataTextActions, S.instances.dataTexts
    S.LearnedDungeonPortals = function() return { { id = 900, name = "Portal", icon = 321 } } end
    S.Start()
    local values = NS.DataTextPresetValues("empty", 1, c)
    for index = 2, NS.DataTextBarLimit do values["bar" .. index .. "Enabled"] = false end
    values.bar1Slot1 = NS.DataTextSourceIndex.travel
    values.hearthItems = "6948,42,999"
    assert(S.SetMany("dataTexts", values))
    local button = M.bars[1].slots[1]
    local priorReads = itemReads
    W.Click(button)
    assert(itemReads > priorReads, "travel menu must refresh ownership when opened")
    local popup = assert(A.popup, "travel source did not create its secure popup")
    local count = flavor == "Forever" and 2 or 3
    assert(popup.shown and #popup.rows == count, "travel menu lost an owned item or included an unavailable portal")
    assert(popup.rows[1]:GetAttribute("type") == "item" and popup.rows[1]:GetAttribute("item") == "item:6948")
    assert(popup.rows[2]:GetAttribute("type") == "toy" and popup.rows[2]:GetAttribute("toy") == 42)
    assert(popup.rows[1].cooldown.cooldownDuration[2] == 1800, "item cooldown was not sent to its native widget")
    if flavor == "Mainline" then
        assert(popup.rows[3]:GetAttribute("spell") == 900
            and popup.rows[3].cooldown.cooldownDuration == durationObject, "portal must use its native duration object")
    end
    W.Click(popup.rows[1])
    local action = W.secureActions[#W.secureActions]
    assert(action.type == "item" and action.item == "item:6948" and not popup.shown, "travel item did not execute securely")
    W.Click(button)
    W.Click(popup.rows[2])
    action = W.secureActions[#W.secureActions]
    assert(action.type == "toy" and action.toy == 42, "travel toy did not execute securely")
    W.Click(button)
    local beforeCombatReads = itemReads
    W.SetCombat(true)
    assert(not popup.shown and #popup.points == 0 and not M.bars[1].frame:IsProtected(),
        "combat edge retained a protected dependency on a movable bar")
    W.Click(button)
    assert(not popup.shown and itemReads == beforeCombatReads, "combat click created or rebuilt a secure menu")
    W.SetCombat(false)
    secretCooldown = true
    W.Click(button)
    assert(popup.shown and not popup.rows[1].cooldown.cooldownDuration,
        "restricted item cooldown must not be inspected or retain an old swipe")
    local readsAtOpen = itemReads
    W.Advance(5)
    assert(itemReads == readsAtOpen, "travel source introduced polling")
    print("DataTexts native travel popup contract: " .. flavor .. " PASS")
end
