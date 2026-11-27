-- Use the existing native widget model with the real Surface, ControlSkin,
-- UIPanelButtons post-hook and the actual Bags action-button constructor.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local fixture = file:read("*a")
file:close()
local finish = assert(fixture:find("local parent = Target(", 1, true))
local body = [=[
UIPanelButton_OnShow = function(button)
    if button:IsEnabled() then
        for _, key in ipairs({ "Left", "Middle", "Right" }) do button[key]:SetTexture("UI-Panel-Button-Up") end
    end
end
UIPanelCloseButton_SetBorderAtlas = Noop
hooksecurefunc = function(name, callback)
    local previous = assert(_G[name])
    _G[name] = function(...) previous(...); callback(...) end
end
local host, hostReads = {}, 0
NS.SuiteCore = function() hostReads = hostReads + 1; return host end
Load("Adapters/UIPanelButtons.lua")
assert(hostReads == 0, "the hidden or unloaded Bags owner was read at skin startup")
NS.UIPanelButtons.active = true
local bag = { BagsModule = { active = true, config = { accentColor = "ffffff" } } }
bag.Suite = {
    Text = function(value) return value end, RGB = function() return 1, 1, 1 end,
    CreateTexture = function(frame)
        local region = frame:CreateTexture()
        region.SetColorTexture, region.SetAllPoints, region.SetWidth, region.SetHeight = Noop, Noop, Noop, Noop
        return region
    end,
}
host.Suite = bag.Suite
function bag.ChildFrame(kind, parent, template)
    assert(template == "UIPanelButtonTemplate")
    local button = Target(kind, parent)
    button.SetSize, button.SetText = Noop, Noop
    button.SetNormalFontObject, button.SetHighlightFontObject, button.SetDisabledFontObject = Noop, Noop, Noop
    button.Left, button.Middle, button.Right = Texture(), Texture(), Texture()
    return button
end
assert(loadfile(root .. "/MSUF_Suite_Bags/Appearance.lua"))("Bags", bag)
assert(loadfile(root .. "/MSUF_Suite_Bags/GridView.lua"))("Bags", bag)
local click = function() end
NS.UIPanelButtons.active = false
UIPanelButton_OnShow(bag.ChildFrame("Button", UIParent, "UIPanelButtonTemplate"))
assert(hostReads == 0, "disabled button skins reached the Bags owner")
NS.UIPanelButtons.active = true
local button = bag.GridView.Button(UIParent, "Sort", 50, click)
local bagFill = button.surface
UIPanelButton_OnShow(button)
local surface = assert(NS.Registry.GetSurface(button))
assert(button:GetHighlightTexture() == surface.highlight and button:GetScript("OnClick") == click)
local refresh, paints = surface.refresh, 0
surface.refresh = function(...) paints = paints + 1; return refresh(...) end
button.Left = Texture()
button.Left:SetAlpha(.7)
local writes = 0
local native = button.Left.SetAlpha
function button.Left:SetAlpha(value) writes = writes + 1; native(self, value) end
local foreignHighlight = Texture()
button:SetHighlightTexture(foreignHighlight)
-- A skinned bag action is warm: each bag show cascades UIPanelButton_OnShow
-- to it, which needs no ControlSkin pass (UIPanelButtons WarmBagAction).
local apply, applies = NS.ControlSkin.ApplyUIPanelButton, 0
NS.ControlSkin.ApplyUIPanelButton = function(...) applies = applies + 1; return apply(...) end
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 10 do UIPanelButton_OnShow(button) end
debug.sethook()
print(("Ten shows: %d sampled Lua VM instructions, %d native slice writes, %d applies"):format(instructions, writes, applies))
print(("Ten shows: %d full surface paints"):format(paints))
assert(paints == 0, "tagged bag actions repainted unchanged materials on warm OnShow")
assert(applies == 0 and writes == 0, "a warm bag action ran ControlSkin again: " .. applies .. " applies, " .. writes .. " writes")
-- Measured 1,700 with the warm path; the reuse path took 10,000 or more.
assert(instructions < 2500, "warm bag action exceeded the combined ten-show VM budget")
NS.Registry.NotifyListeners("profile", "changed")
UIPanelButton_OnShow(button)
assert(paints == 1 and applies == 1, "a changed profile did not repaint the visible bag action")
assert(writes == 1, "the first show after a profile change did not fade the replaced slice once: " .. writes)
assert(NS.ControlSkin.states[button].fixedSpec, "warm actions copied immutable skin metadata")
assert(button.Left:GetAlpha() == 0 and button:GetHighlightTexture() == surface.highlight)
assert(button:GetPushedTexture() == surface.pushed and button:GetDisabledTexture() == surface.disabled and button.surface == bagFill)
button:Fire("OnEnter")
assert(bagFill:GetAlpha() == 1 and button:GetHighlightTexture() == surface.highlight)
button:Fire("OnLeave")
assert(bagFill:GetAlpha() == .7, "normal bag hover did not recover on leave")
button:SetEnabled(false)
UIPanelButton_OnShow(button)
assert(button:GetDisabledTexture() == surface.disabled and paints == 1, "disabled warm bag action lost its skin")
button:SetEnabled(true)
assert(NS.ControlSkin.Disable(button) and button.Left:GetAlpha() == .7, "release lost the replacement region's native alpha")
UIPanelButton_OnShow(button)
assert(NS.ControlSkin.GetOwner(button) == "uipanel-buttons" and button.Left:GetAlpha() == 0 and button.surface == bagFill)
-- Buttons which used the native template before either module loaded are
-- adopted on show. A fresh ordinary template keeps the full repair on reuse.
local other = bag.ChildFrame("Button", UIParent, "UIPanelButtonTemplate")
UIPanelButton_OnShow(other)
local otherSurface = NS.Registry.GetSurface(other)
local otherPaint, otherPaints = otherSurface.refresh, 0
otherSurface.refresh = function(...) otherPaints = otherPaints + 1; return otherPaint(...) end
UIPanelButton_OnShow(other)
UIPanelButton_OnShow(other)
assert(otherPaints == 2, "unmarked or pooled native buttons must retain full paints")
bag.BagAppearance.MakeButton(other)
UIPanelButton_OnShow(other)
assert(otherPaints == 3, "the first show after bag styling must repaint")
UIPanelButton_OnShow(other)
assert(otherPaints == 3, "the new bag action never entered its warm path")
bag.Suite.BagActionButtons = nil
UIPanelButton_OnShow(other)
assert(otherPaints == 4, "a missing bags owner must retain the normal native path")
bag.Suite.BagActionButtons = bag.BagAppearance.buttons
UIPanelButton_OnShow(other)
local warmApplies = applies
UIPanelButton_OnShow(other)
assert(applies == warmApplies, "a returned bags owner did not warm its action again")
-- Refresh re-skins every tracked button with the panel spec. No static
-- popup category is enabled in this fixture.
NS.GenericWindows = NS.GenericWindows or { IsCategoryEnabled = function() return false end }
NS.UIPanelButtons.Refresh()
local refreshed = applies
UIPanelButton_OnShow(other)
assert(applies == refreshed + 1, "the first show after a skin refresh skipped the bag action skin")
UIPanelButton_OnShow(other)
assert(applies == refreshed + 1, "the refreshed bag action did not become warm again")
print("Bags and Skin button lifecycle: warm paint budget, hover, profile, late adoption, native repair, disable/reopen passed")
]=]
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    arg[2] = flavor
    assert(loadstring(fixture:sub(1, finish - 1) .. body, "@bags_skin_button_fixture"))()
end
