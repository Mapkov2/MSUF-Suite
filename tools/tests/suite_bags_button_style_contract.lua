local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root, { config = { accentColor = "ff0000" } })
W.sizes[0] = 2
W.Apply()
W.OpenBags()
W.Settle()
local button = W.P.InventoryView.cleanup
for _, part in ipairs({ button.Left, button.Middle, button.Right }) do
    assert(part:GetAlpha() == 0, "native three-piece artwork must stay invisible")
    part:SetTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    assert(part:GetAlpha() == 0, "native button state changes cannot restore old artwork")
end
local surface = button.surface
assert(surface.color[1] == 1 and surface.color[3] == 0)
W.S.Set("bags", "accentColor", "0000ff")
assert(button.surface == surface and surface.color[1] == 0 and surface.color[3] == 1,
    "existing action buttons must follow a new look without allocation")
for _, getter in ipairs({"GetNormalTexture","GetPushedTexture","GetDisabledTexture","GetHighlightTexture"}) do
    local texture = button[getter](button)
    assert(not texture or texture:GetAlpha()==0, "stock state artwork survived flat button paint")
end
local all = W.P.ChildFrame("Button", W.P.InventoryView.chrome, "UIPanelButtonTemplate")
for _, state in ipairs({"Normal","Pushed","Disabled","Highlight"}) do all["Set"..state.."Texture"](all, "valid-asset") end
W.P.BagAppearance.MakeButton(all)
for _, state in ipairs({"Normal","Pushed","Disabled","Highlight"}) do
    assert(all["Get"..state.."Texture"](all):GetAlpha()==0, "one button state was not muted")
end
print("Bags native state assets, flat artwork and live palette contract passed")
