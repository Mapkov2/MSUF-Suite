-- The Micro Bar frame switch (icons.microMenu.barFrame). Off takes the whole
-- frame around the bar away: the bar's background and border, the rules
-- beside the portrait and, on Forever, Blizzard's own art behind the menu, in
-- Blizzard's layout too. On brings back what the look draws. A look preset
-- keeps the switch as it is. Real OwnedMicroBar*, MicroMenuStates, MicroMenu
-- and MicroMenuSettings over the combat-end contract's menu fixture.
local root = assert(arg[1], "Suite root required")
local flavor = assert(arg[2], "flavor required")
local forever = flavor == "Forever"
local checks = 0
local function Check(value, message)
    assert(value, flavor .. ": " .. message)
    checks = checks + 1
end

local file = assert(io.open(root .. "/tools/tests/suite_skin_micro_bar_combat_end_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local flavorLine = 'local forever = os.getenv("SUITE_MICRO_FOREVER") == "1"'
Check(source:find(flavorLine, 1, true), "the fixture's flavor line moved")
source = source:gsub(flavorLine:gsub("%p", "%%%0"), "local forever = " .. tostring(forever), 1)
local stop = assert(source:find('Skin.Apply(menu, "combat-end-contract")', 1, true), "fixture end moved")
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, menu = menu, settings = settings, Load = Load, Owned = Owned, Skin = Skin }
]]

-- Textures each frame created, in order (the owned bar's portrait rules).
local textures = setmetatable({}, { __mode = "k" })
local H = assert(loadstring(fixture, "@micro_bar_frame_fixture"))()
local NS, menu, settings, Owned, Skin = H.NS, H.menu, H.settings, H.Owned, H.Skin
local createFrame = CreateFrame
CreateFrame = function(...)
    local frame = createFrame(...)
    local createTexture, list = frame.CreateTexture, {}
    textures[frame] = list
    function frame:CreateTexture(...)
        local texture = createTexture(self, ...)
        list[#list + 1] = texture
        return texture
    end
    return frame
end
-- Surfaces as the Registry sees them: the last spec and its visibility.
NS.Surface.Attach = function(target, spec)
    local state = { spec = spec, visible = true }
    NS.Registry.surfaces[target] = state
    return state
end
NS.Surface.SetVisible = function(target, visible)
    local state = NS.Registry.surfaces[target]
    if state then state.visible = visible end
    return true
end
-- A seeded button surface is reused; its late native text is tracked.
NS.BlizzardYellow = { TrackFrame = function() end }
NS.MicroMenuPresetValues = { framed = { barBackground = true, barBorder = 1, barMaterial = "modern" } }
NS.IsRetailPanelMicroBar = function() return false end
NS.AlignRetailPanelMicroBar = function() return false end
H.Load("Adapters/MicroMenuSettings.lua")

local function Surface(target)
    local state = NS.Registry.surfaces[target]
    return state and state.visible ~= false and state.spec or nil
end

-- A saved profile from before the switch has no barFrame: the frame shows.
settings.preset, settings.barBackground, settings.barBorder = "modern", true, 1
settings.barFrame = nil
Check(Skin.Apply(menu, "frame-contract"), "the Micro Bar did not apply")
local bar = Owned.GetFrames()
local made = textures[bar]
-- CreatePortrait's order: portrait, ring, top rule, bottom rule.
Check(made and made[1] == bar._msufForeverPortrait and made[2] == bar._msufForeverPortraitRing,
    "the owned bar no longer creates its portrait first")
local topRule, bottomRule = made[3], made[4]
local spec = Surface(bar)
Check(spec and spec.fillVisible == true and spec.border == 1, "the framed bar lost its background or border")
Check(topRule:IsShown() and bottomRule:IsShown(), "the framed bar lost its rules")
Check(menu.BorderArt:GetAlpha() == (forever and 0 or 1), "the owned bar changed the wrong client's native frame")

Check(NS.MicroMenuSkin.SetOption("barFrame", "off") == false, "the frame switch took a value that is not true or false")
Check(NS.MicroMenuSkin.SetOption("barFrame", false), "the frame switch was refused")
Check(settings.barFrame == false and settings.preset == "modern", "turning the frame off changed the look's preset")
Check(not Surface(bar), "the bar kept its background or border without its frame")
Check(not topRule:IsShown() and not bottomRule:IsShown(), "the bar kept its rules without its frame")
Check(bar._msufForeverPortrait:IsShown() and bar._msufForeverPortraitRing:IsShown(),
    "turning the frame off took the portrait away")
Check(menu.BorderArt:GetAlpha() == (forever and 0 or 1) and menu.BackgroundArt:GetAlpha() == (forever and 0 or 1),
    "the frameless owned bar changed the wrong client's native frame")

-- A look preset keeps the switch.
Check(NS.MicroMenuSkin.ApplyPreset("framed") and settings.barFrame == false and not Surface(bar),
    "a look preset brought the frame back")

-- Blizzard's layout with Blizzard's icons: the frameless bar takes Blizzard's
-- own art behind the menu away on Forever, and gives it back with the frame.
settings.layoutMode, settings.iconStyle, settings.barBackground, settings.barBorder = "blizzard", "blizzard", false, 0
Check(Skin.RefreshActive(), "Blizzard's layout did not apply")
Check(menu:GetParent() == MicroMenuContainer and not Owned.active, "Blizzard's layout kept the owned bar")
Check(not Surface(menu), "Blizzard's layout drew a frame the look has not")
Check(menu.BorderArt:GetAlpha() == (forever and 0 or 1) and menu.BackgroundArt:GetAlpha() == (forever and 0 or 1),
    "the frameless Blizzard layout kept Forever's frame art or faded Retail's")
Check(NS.MicroMenuSkin.SetOption("barFrame", true), "turning the frame on was refused")
Check(menu.BorderArt:GetAlpha() == 1 and menu.BackgroundArt:GetAlpha() == 1,
    "turning the frame on did not give Blizzard's frame art back")
Check(NS.MicroMenuSkin.SetOption("barFrame", false) and menu.BorderArt:GetAlpha() == (forever and 0 or 1),
    "turning the frame off again missed Forever's frame art")

-- The owned bar with its frame again: background, border and rules return.
settings.layoutMode, settings.iconStyle, settings.barBackground, settings.barBorder = "owned", "bold", true, 2
Check(NS.MicroMenuSkin.SetOption("barFrame", true), "turning the owned bar's frame on was refused")
spec = Surface(bar)
Check(menu:GetParent() == bar and spec and spec.fillVisible == true and spec.border == 2,
    "the owned bar's frame did not come back as the look draws it")
Check(topRule:IsShown() and bottomRule:IsShown(), "the owned bar's rules did not come back")
Check(menu.BorderArt:GetAlpha() == (forever and 0 or 1), "the framed owned bar changed the wrong client's frame art")

-- While Blizzard holds the menu elsewhere (a vehicle or pet battle bar), the
-- skin stands back: Blizzard's art shows there even without the frame.
Check(NS.MicroMenuSkin.SetOption("barFrame", false), "turning the owned bar's frame off again was refused")
local holder = CreateFrame("Frame", "OverrideActionBar", UIParent)
menu:OverrideMicroMenuPosition(holder)
Skin.RefreshActive()
Check(menu:GetParent() == holder and menu.BorderArt:GetAlpha() == 1 and menu.BackgroundArt:GetAlpha() == 1,
    "the frame switch faded Blizzard's art while Blizzard held the menu")
menu:ResetMicroMenuPosition()
Skin.RefreshActive()
Check(menu:GetParent() == bar and menu.BorderArt:GetAlpha() == (forever and 0 or 1),
    "the frameless owned bar did not take Forever's art away again after Blizzard's hold")

Skin.Disable()
Check(menu.BorderArt:GetAlpha() == 1 and menu.BackgroundArt:GetAlpha() == 1, "disabling the skin kept Blizzard's art faded")
print(("Suite Micro Bar frame (%s): %d checks passed"):format(flavor, checks))
