local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")

local function Specializations(W)
    local G = W.G
    W.spec, W.loot, W.reads = 1, 0, 0
    G.C_SpecializationInfo = {
        GetSpecialization = function() W.reads = W.reads + 1; return W.spec end,
        GetSpecializationInfo = function(index) return 70 + index, "Spec " .. index, nil, 100 + index end,
        SetSpecialization = function(index) W.spec = index end,
    }
    G.GetNumSpecializations = function() return 3 end
    G.GetLootSpecialization = function() return W.loot end
    G.SetLootSpecialization = function(id) W.loot = id end
    G.GetSpecializationInfoByID = function(id) return id, "Loot " .. id end
    local function Node()
        local node = { children = {} }
        function node:CreateTitle() end
        function node:SetEnabled(value) self.enabled = value end
        function node:CreateButton(name)
            local child = Node()
            child.name = name
            self.children[#self.children + 1] = child
            return child
        end
        function node:CreateRadio(name, selected, change, value)
            local child = self:CreateButton(name)
            child.selected, child.change, child.value = selected, change, value
            return child
        end
        return node
    end
    G.MenuUtil = { CreateContextMenu = function(_, builder)
        W.menu = Node()
        builder(nil, W.menu)
    end }
end

do
    local W = H.New(root, "Mainline")
    Specializations(W)
    W.editModeReady = true
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM = W.S, W.MM
    assert(not S.catalog.mapQuickSwitch and not S.instances.mapQuickSwitch,
        "specialization must no longer be an independent QoL module")
    assert(not MM.specialization.button and W.reads == 0, "disabled feature must stay dormant")
    assert(S.SetMany("minimap", { specButton = true, specSize = 30, specCorner = 1, specX = 9, specY = -7 }))
    local Q = MM.specialization
    assert(Q.button:IsVisible() and Q.button:GetParent() == MM.host and Q.icon.texture == 101,
        "specialization button must belong to the minimap host")
    local point, relative, anchor, x, y = Q.button:GetPoint(1)
    assert(point == "TOPLEFT" and relative == MM.host and anchor == "TOPRIGHT" and x == 13 and y == -7
        and Q.button.width == 30, "corner, size and preview offsets must reach the live button")
    W.Fire(Q.button, "OnClick")
    assert(#W.menu.children == 2 and #W.menu.children[1].children == 3 and #W.menu.children[2].children == 4)
    local spec = W.menu.children[1].children[2]
    local loot = W.menu.children[2].children[3]
    spec.change(spec.value)
    loot.change(loot.value)
    assert(W.spec == 2 and W.loot == 72, "menu must use native spec and loot setters")
    local reads = W.reads
    W.Event("PLAYER_SPECIALIZATION_CHANGED", "party1")
    assert(W.reads == reads, "other units must not refresh the player's icon")
    W.Event("PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(Q.icon.texture == 102, "spec event must refresh the icon")
    W.Fire(Q.button, "OnEnter")
    assert(W.G.GameTooltip:IsShown(), "tooltip should show current specialization")
    W.SetCombat(true)
    W.Fire(Q.button, "OnClick")
    assert(not W.menu.children[1].children[1].enabled and not W.menu.children[2].children[1].enabled)
    spec.change(3); loot.change(73)
    assert(W.spec == 2 and W.loot == 72, "callbacks created before combat must also be guarded")
    W.Event("PLAYER_SPECIALIZATION_CHANGED", "player") -- no protected layout writes
    W.SetCombat(false)
    assert(S.SetMany("minimap", { specShowSpec = false, specShowLoot = false }))
    assert(not Q.button:IsShown() and not W.G.GameTooltip:IsShown(), "empty button and its tooltip must hide")
    reads = W.reads
    W.Event("PLAYER_SPECIALIZATION_CHANGED", "player")
    W.Event("PLAYER_LOOT_SPEC_UPDATED")
    assert(W.reads == reads, "inactive specialization listeners must be released")
    assert(S.Set("minimap", "specShowLoot", true))
    W.Fire(Q.button, "OnClick")
    assert(#W.menu.children == 1 and #W.menu.children[1].children == 4, "loot-only menu must work")
    assert(S.Set("minimap", "visibility", 5))
    assert(not Q.button:IsVisible(), "button must follow minimap visibility")
    assert(S.Set("minimap", "visibility", 4))
    W.Fire(MM.catcher, "OnEnter"); W.Step()
    assert(Q.button:IsVisible(), "mouseover must reveal the integrated button")
    assert(S.Set("minimap", "enabled", false))
    assert(not Q.button:IsShown(), "disabling Minimap must release its specialization button")
    assert(S.Set("minimap", "enabled", true))
    assert(Q.button:IsShown(), "re-enabling Minimap must restore its configured button")
    reads = W.reads
    W.Advance(3)
    assert(W.reads == reads and not Q.button.scripts.OnUpdate,
        "specialization must not poll or add a per-frame callback")
    print("Minimap specialization: native menus, host visibility, events, combat and lifecycle passed")
end

do
    local W = H.New(root, "Forever")
    Specializations(W) -- APIs alone must not accidentally enable the Retail feature.
    H.Enable(W, { captured = true, specButton = true })
    assert(not W.MM.specialization.button and W.reads == 0,
        "Forever must keep the Retail specialization feature dormant")
    assert(W.S.catalog.minimap.rules.specButton.hidden, "Forever must hide specialization settings")
    print("Forever specialization exclusion passed")
end
