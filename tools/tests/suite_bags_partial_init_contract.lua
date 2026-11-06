local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
for _, wheel in ipairs({false,true}) do
    for _, failAt in ipairs({1,4,9,10,"mid"}) do
        local W = H.New(root, {client=arg[2] or "Mainline",config={windowPresentation=1}})
        W.sizes[0] = 4
        W.Put(0,1,101,1)
        W.OpenBags()
        W.CF:EnableMouseWheel(wheel)
        local original, create, count = W.P.BagAppearance.MakeButton, W.S.CreateTexture, 0
        W.P.BagAppearance.MakeButton = function(...)
            count = count + 1
            if count == failAt then error("injected controls constructor failure") end
            return original(...)
        end
        if failAt == "mid" then
            count = 0
            W.S.CreateTexture = function(parent, ...)
                if parent.kind == "Button" then
                    count = count + 1
                    if count == 2 then error("injected controls constructor failure") end
                end
                return create(parent, ...)
            end
        end
        local ok, message = pcall(W.Apply)
        assert(not ok and tostring(message):find("injected controls constructor failure",1,true), "partial constructor did not fail at requested stage")
        local V = W.P.InventoryView
        local partial = V.chrome
        W.M.active, W.S.states.bags.active = false, false
        local released, failure = pcall(W.M.Disable, W.M)
        assert(released, "partial-init release raised: "..tostring(failure))
        W.M.context:Release()
        assert(not partial:IsVisible() and not V.active, "partial UI remains interactive")
        assert(W.CF:IsMouseWheelEnabled()==wheel, "failed start changed native mouse wheel")
        for _, button in W.CF:EnumerateValidItems() do assert(button:IsShown(), "failed start hid native items") end
        W.P.BagAppearance.MakeButton, W.S.CreateTexture = original, create
        W.Apply()
        W.Settle()
        assert(V.active and V.events and V.equipped and V.clearRecent, "reenable reused incomplete UI")
        assert(not partial:IsVisible() and V.chrome~=partial, "failed chrome reused or left visible")
        assert(W.P.EquippedBags.frame:GetParent()==V.chrome, "equipped drawer belongs to failed UI")
        W.P.EquippedBags.Toggle()
        W.Settle()
        assert(W.P.EquippedBags.frame:IsVisible(), "equipped drawer lost after retry")
        W.S.Set("bags", "enabled", false)
        W.Settle()
        assert(W.CF:IsMouseWheelEnabled()==wheel, "successful retry lost original mouse wheel")
        assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0, "partial-init error/taint/lockdown writes")
    end
end
print("Partial controls constructor handback and retry passed: "..(arg[2] or "Mainline"))
