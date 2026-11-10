local root = assert(arg[1], "repository root required")
local Harness = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Check(client)
    local W = Harness.New(root, { client = client, config = {
        showRecent = false, showItemLevel = false, mergeStacks = true, inventoryView = 3,
        showPinned = false, hideEmptyCategories = false,
    } })
    local class = Enum.ItemClass
    GameTooltip.SetInventoryItem = function(self, unit, slot)
        assert(unit == "player" and type(slot) == "number")
        self:SetText("Bag")
        return true
    end
    W.sizes[0], W.sizes[1], W.sizes[2] = 3, 3, 2
    W.Define(101, { name = "Arrows", class = class.Projectile, equipLoc = "INVTYPE_AMMO", maxStack = 200 })
    W.Define(102, { name = "Bullets", class = class.Projectile, equipLoc = "INVTYPE_AMMO", maxStack = 200 })
    W.Define(103, { name = "Cloth", class = class.Tradegoods })
    W.Put(0, 1, 101, 4)
    W.Put(1, 1, 101, 6)
    W.Put(1, 2, 102, 10)
    W.Put(2, 1, 103, 1)
    W.Apply(); W.OpenBags(); W.Settle()
    local P, V = W.P, W.P.InventoryView
    local ammo = V.model.groupsByKey.ammo
    assert((ammo ~= nil) == (client == "Forever"), "ammunition category must be Forever-only")
    assert(W.NS.SuiteCatalog.bags.rules.category_ammo.hidden == (client ~= "Forever"))
    if ammo then
        assert(#ammo.rows == 2 and ammo.rows[1].count + ammo.rows[2].count == 20, "arrows and bullets must classify before equipment")
        W.S.Set("bags", "category_ammo", false); W.Settle()
        assert(not V.model.groupsByKey.ammo, "ammunition category could not be disabled")
        W.S.Set("bags", "category_ammo", true); W.Settle()
        P.InventoryControls.ToggleGroup("ammo"); W.Settle()
        assert(V.model.groupsByKey.ammo.collapsed, "ammunition section could not collapse")
        P.InventoryControls.ToggleGroup("ammo"); W.Settle()
    end

    local function Button(bag, slot)
        for _, item in ipairs(V.index.items) do
            if item.bag == bag and item.slot == slot then return item.button end
        end
        error("missing physical slot")
    end
    local function Mark(button, expected)
        local frame = assert(P.BagHover.frames[button], "visible slot has no hover decoration")
        assert(frame.fill:IsShown() and frame.match == expected, "wrong bag hover membership")
        assert(frame.fill.kind == "Texture", "bag hover must use non-interactive texture regions")
    end
    local function Cleared()
        for _, frame in pairs(P.BagHover.frames) do
            assert(not frame.fill:IsShown(), "hover decoration leaked")
            for _, edge in ipairs(frame.edges) do assert(not edge:IsShown(), "hover edge leaked") end
        end
    end
    local bag = P.EquippedBags.buttons[1]
    P.EquippedBags.Toggle(); W.Settle()
    local base = Button(0, 1)
    local click, drag = base:GetScript("OnClick"), base:GetScript("OnDragStart")
    local reads = W.calls.info
    local lines, addLine = {}, GameTooltip.AddLine
    GameTooltip.AddLine = function(self, text, ...) lines[#lines + 1] = text; return addLine(self, text, ...) end
    W.Hover(bag)
    assert(lines[#lines - 2] == "2 of 3 slots occupied; 1 free.", "bag tooltip did not show occupied/capacity/free")
    Mark(base, true) -- Representative is in backpack; another merged stack is in bag 1.
    Mark(Button(1, 3), true) -- Empty slot.
    Mark(Button(2, 1), false)
    assert(W.calls.info == reads, "hover reread the bag contents")
    assert(base:GetScript("OnClick") == click and base:GetScript("OnDragStart") == drag, "hover changed native item actions")
    W.Insecure(bag:GetScript("OnLeave"), bag)
    Cleared()
    W.BagChanged(1); W.Settle()
    assert(not GameTooltip:IsShown() and not P.BagHover.IsOwner(bag), "bag update resurrected an old tooltip")
    Cleared()
    GameTooltip.AddLine = addLine

    -- Reusing model rows after stacks move must not keep their old bag map.
    W.Put(1, 1, 103, 1); W.BagChanged(1); W.Settle()
    W.Hover(bag)
    Mark(base, false)
    for _, mode in ipairs({ 1, 2, 3 }) do
        W.S.Set("bags", "inventoryView", mode); W.Settle()
        W.Hover(bag)
        Mark(Button(1, 3), true)
        W.CloseBags(); Cleared()
        W.OpenBags(); W.Settle()
        P.EquippedBags.Toggle(); W.Settle()
    end
    W.Hover(bag); W.EnterCombat(); Cleared()
    P.BagHover.Clear(); Cleared() -- Repeated cleanup must also work inside lockdown.
    W.Hover(bag); Cleared()
    W.LeaveCombat(); W.Settle()
    P.EquippedBags.Toggle(); W.Settle(); W.Hover(bag)
    W.S.Set("bags", "inventoryView", 4); W.Settle(); Cleared()
    assert(#W.taint == 0, "bag hover tainted native item frames")
end

if arg[2] then Check(arg[2]) else Check("Mainline") Check("Forever") end
print("bag feedback: ammunition, merged membership, tooltip lifecycle and native actions passed on both clients")
