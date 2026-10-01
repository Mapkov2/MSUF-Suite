-- Item icon borders (Rendering/IconSkin.lua): an item update repaints only
-- what changed, a quality update in combat recolours the owned lines without
-- creating or anchoring anything, and decorative native art never stands in
-- for a quality colour. Real IconSkin, Safety and Registry.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

local calls = {}
local function Count(name) calls[name] = (calls[name] or 0) + 1 end
local function Reset() calls = {} end
local function Region()
    local region = { shown = true, color = { 1, 1, 1, 1 } }
    function region:IsForbidden() return false end
    function region:IsShown() return self.shown end
    function region:Show() Count("Show"); self.shown = true end
    function region:Hide() Count("Hide"); self.shown = false end
    function region:ClearAllPoints() Count("ClearAllPoints") end
    function region:SetPoint() Count("SetPoint") end
    function region:SetHeight() Count("SetSize") end
    function region:SetWidth() Count("SetSize") end
    function region:SetAlpha() end
    function region:GetAlpha() return 1 end
    function region:GetVertexColor() return unpack(self.color) end
    function region:SetColorTexture(r, g, b, a)
        Count("SetColorTexture")
        self.color = { r, g, b, a }
    end
    return region
end
local function Button(protected)
    local button = Region()
    button.Icon, button.IconBorder = Region(), Region()
    function button:IsProtected() return protected == true, false end
    function button:CreateTexture() return Region() end
    return button
end

local locked = false
local deferred = {}
local theme = { iconBorderStyle = "quality", iconBorderThickness = 1, iconBorderPadding = 0, iconBorderOpacity = 1 }
local NS = {
    IsCombatLocked = function() return locked end,
    DB = { theme = theme },
    Defaults = { theme = { iconBorderStyle = "quality" } },
    Theme = { GetColor = function() return 0.2, 0.3, 0.4, 1 end },
    Cosmetics = { Fade = function() return true end },
    CombatGate = { RunOrDefer = function(key, callback)
        if not locked then
            callback()
            return true
        end
        deferred[key] = callback
        return false, "combat"
    end },
}
InCombatLockdown = function() return locked end
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Rendering/IconSkin.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local IconSkin = NS.IconSkin
local function Lines(state) return state.lines end
local function ShowsColor(state, r, g, b)
    for _, line in ipairs(Lines(state)) do
        local color = line.color
        if math.abs(color[1] - r) > 1e-6 or math.abs(color[2] - g) > 1e-6 or math.abs(color[3] - b) > 1e-6 then
            return false
        end
    end
    return true
end

-- Every BAG_UPDATE repaints every bag button: an unchanged border costs no
-- anchor, colour or visibility call.
local button = Button()
button.IconBorder.color = { 0.64, 0.21, 0.93, 1 }
local state = assert(IconSkin.Apply(button, "bags", {}), "the item border was not skinned")
Check(ShowsColor(state, 0.64, 0.21, 0.93), "the border did not take the native quality colour")
Reset()
for _ = 1, 20 do
    IconSkin.Apply(button, "bags", {})
    IconSkin.Repaint(button)
end
Check((calls.ClearAllPoints or 0) == 0 and (calls.SetPoint or 0) == 0 and (calls.SetSize or 0) == 0,
    "an unchanged border was anchored again on an item update")
Check((calls.SetColorTexture or 0) == 0 and (calls.Show or 0) == 0 and (calls.Hide or 0) == 0,
    "an unchanged border was recoloured or shown again on an item update")
-- A new quality recolours the four lines once, without anchoring.
button.IconBorder.color = { 0.0, 0.44, 0.87, 1 }
Reset()
IconSkin.Repaint(button)
Check(calls.SetColorTexture == 4 and (calls.SetPoint or 0) == 0 and ShowsColor(state, 0, 0.44, 0.87),
    "a quality change did not recolour exactly the four lines")
-- A changed thickness anchors the lines once.
theme.iconBorderThickness = 2
Reset()
IconSkin.Repaint(button)
IconSkin.Repaint(button)
Check(calls.ClearAllPoints == 4 and calls.SetPoint == 8, "a thickness change did not anchor the lines once")
theme.iconBorderThickness = 1

-- Looting in combat: the owned lines take the new quality as paint only.
locked = true
button.IconBorder.color = { 1.0, 0.5, 0.0, 1 }
Reset()
Check(IconSkin.Repaint(button) == true, "a combat quality update was refused on an unprotected button")
Check(ShowsColor(state, 1, 0.5, 0) and (calls.SetPoint or 0) == 0 and (calls.ClearAllPoints or 0) == 0,
    "a combat quality update did not recolour the lines or anchored them")
button.Icon.shown = false
IconSkin.Repaint(button)
Check(not Lines(state)[1].shown, "an emptied slot kept its border in combat")
button.Icon.shown = true
IconSkin.Repaint(button)
Check(Lines(state)[1].shown, "a filled slot did not show its border in combat")
-- A protected button is left alone in combat and repainted right after it.
locked = false
local guarded = Button(true)
local guardedState = assert(IconSkin.Apply(guarded, "bags", { allowImplicitProtected = true }),
    "an implicitly protected item button was not skinned out of combat")
locked = true
guarded.IconBorder.color = { 0.1, 0.9, 0.1, 1 }
Reset()
Check(IconSkin.Repaint(guarded) == false and (calls.SetColorTexture or 0) == 0,
    "a protected item button was painted in combat")
Check(deferred["icon-skin:repaint"] ~= nil, "a protected border got no repaint after combat")
locked = false
deferred["icon-skin:repaint"]()
Check(ShowsColor(guardedState, 0.1, 0.9, 0.1), "the repaint after combat skipped the protected border")
locked = true
Check(IconSkin.Apply(Button(), "bags", {}) == nil, "a border was created in combat")
locked = false

-- Decorative native art (the white cooldown viewer overlay) is no quality
-- colour: the quality style draws the theme's icon border colour instead.
local viewerIcon = Button()
viewerIcon.IconBorder.color = { 1, 1, 1, 1 }
local viewerState = assert(IconSkin.Apply(viewerIcon, "hud", { nativeQuality = false }))
Check(ShowsColor(viewerState, 0.2, 0.3, 0.4), "decorative native art was read as a quality colour")
local itemIcon = Button()
itemIcon.IconBorder.color = { 1, 1, 1, 1 }
Check(ShowsColor(assert(IconSkin.Apply(itemIcon, "items", {})), 1, 1, 1),
    "an item border no longer reads its native quality colour")

-- Disable hides the lines; enabling again shows them.
IconSkin.DisableOwner("bags")
Check(not Lines(state)[1].shown, "disable left an item border shown")
IconSkin.Apply(button, "bags", {})
Check(Lines(state)[1].shown, "a re-enabled item border stayed hidden")

print("Suite skin icon borders: " .. checks .. " checks passed")
