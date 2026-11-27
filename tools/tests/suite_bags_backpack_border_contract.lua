local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function CheckBorder(style, width, r, g, b, a)
    assert(style[6]:GetHeight() == width and style[7]:GetHeight() == width, "horizontal border width")
    assert(style[8]:GetWidth() == width and style[9]:GetWidth() == width, "vertical border width")
    for i = 6, 9 do
        local color = style[i].color
        assert(color[1] == r and color[2] == g and color[3] == b and color[4] == a, "border color or opacity")
    end
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    local W = H.New(root, { client = client })
    assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", W.NS)
    local api = { OnAppearanceChanged = function() end }
    local palette = { .05, .06, .07, .9 }
    local provider = {
        addonName = "MSUF_Suite_Skin", DB = { enabled = true },
        GetAPI = function() return api end,
        TooltipChrome = { GetBorder = function() return unpack(palette) end },
    }
    MapkoSkin = nil
    W.NS.Skin.enabled = true
    W.S.started = true
    W.S.Apply = function(id)
        assert(id == "bags")
        W.Apply()
    end
    W.Apply()
    W.OpenBags()
    W.Settle()
    local style = W.M.windows[W.CF]
    local reagent = W.M.windows[ContainerFrame6]
    local reagentColor = { unpack(reagent[6].color) }
    CheckBorder(style, 1, .063, .063, .063, 1)
    MapkoSkin = provider
    W.Apply()
    CheckBorder(style, 1, unpack(palette))

    W.S.SetMany("bags", {
        backpackBorderStyle = W.NS.BagsBorderStyle.CUSTOM,
        backpackBorderColor = "ff0000", backpackBorderWidth = 4, backpackBorderOpacity = 45,
    })
    CheckBorder(style, 4, 1, 0, 0, .45)
    local _, _, _, _, offset = style[8]:GetPoint(1)
    assert(offset == -4, "side edge overlaps translucent top edge")
    for i = 1, 4 do assert(reagent[6].color[i] == reagentColor[i], "custom border leaks into reagent window") end
    palette = { .1, .1, .1, .8 }
    api:OnAppearanceChanged("color", "border")
    CheckBorder(style, 4, 1, 0, 0, .45)
    W.S.Set("bags", "backpackBorderWidth", 0)
    CheckBorder(style, 0, 1, 0, 0, 0)

    W.S.Set("bags", "backpackBorderStyle", W.NS.BagsBorderStyle.DEFAULT)
    CheckBorder(style, 1, unpack(palette))
    palette = { .03, .04, .05, .7 }
    api:OnAppearanceChanged("color", "border")
    CheckBorder(style, 1, unpack(palette))
    W.config.backpackBorderStyle = nil
    palette = { .02, .03, .04, .8 }
    api:OnAppearanceChanged("appearance", "borderOpacity")
    CheckBorder(style, 1, unpack(palette))
    palette[4] = 0
    api:OnAppearanceChanged("geometry", "border")
    CheckBorder(style, 1, .063, .063, .063, 1)
    palette = { .02, .03, .04 }
    api:OnAppearanceChanged("color", "border")
    CheckBorder(style, 1, .063, .063, .063, 1)
    palette[4] = .8
    api:OnAppearanceChanged("color", "border")
    CheckBorder(style, 1, unpack(palette))
    provider.DB.enabled = false
    api:OnAppearanceChanged("adapter", "master")
    CheckBorder(style, 1, .063, .063, .063, 1)
    local widget = getmetatable(style.shell).__index
    function widget:CreateMaskTexture() return W.NewWidget("MaskTexture", nil, self) end
    function widget:ClearTextureSlice() self.slice = nil end
    function widget:SetTextureSliceMargins(...) self.slice = { ... } end
    function widget:SetTextureSliceMode(mode) self.sliceMode = mode end
    function widget:AddMaskTexture(mask)
        assert(not self.shellMask, "bag mask bound twice")
        self.shellMask = mask
    end
    function widget:RemoveMaskTexture(mask)
        assert(self.shellMask == mask, "releasing a mask outside its bag owner")
        self.shellMask = nil
    end
    function widget:SetVertexColor(...) self.vertex = { ... } end
    provider.Client = { isForever = client == "Forever" }
    provider.path, provider.GeometryBorders = "skin/", { 0, 1, 2 }
    provider.ShapeRadii = { 4, 6, 8, 12, 16, 20, 24 }
    provider.DB.enabled = true
    provider.DB.geometry = { family = "continuous", radius = 8, windowRadius = 24, roundWindows = false }
    provider.Safety = {
        CanCreateRegions = function() return true end,
        HasMethod = function(target, key) return type(target[key]) == "function" end,
        CreateChildFrame = function(kind, parent) return W.NewWidget(kind, nil, parent) end,
    }
    Enum.UITextureSliceMode = { Stretched = 1 }
    local skinPath = root .. "/MSUF_Suite_Skin/Rendering/"
    assert(loadfile(skinPath .. "Geometry.lua"))("MSUF_Suite_Skin", provider)
    assert(loadfile(skinPath .. "WindowFocusVisual.lua"))("MSUF_Suite_Skin", provider)
    W.S.SetMany("bags", { look = 3, windowPresentation = W.NS.BagsPresentation.PANEL,
        backpackBorderStyle = W.NS.BagsBorderStyle.CUSTOM, backpackBorderColor = "ff0000",
        backpackBorderWidth = 4, backpackBorderOpacity = 45 })
    provider.DB.geometry.roundWindows = true
    api:OnAppearanceChanged("geometry", "roundWindows")
    local mask = assert(style[2].shellMask, "enabling rounded windows did not repaint the custom-border backpack")
    assert(mask.parent == style.shell and mask.texture:match("continuous_r24_fill.png$") and mask.slice[1] == 27.5,
        "combined bags did not reuse the large shell contour")
    assert(style[3].shellMask == mask and style[5].shellMask == mask and style.closeFill.shellMask == mask
        and style[2].gradient and style[1].texture == mask.texture and #style[1].slice == 4,
        "rounded bags lost a body gradient or left square chrome or shadow visible")
    if style.feather then assert(style.feather.shellMask == mask, "panel feather leaked into the rounded corners") end
    assert(not style[6]:IsShown() and style.roundedBorder:GetParent() == style.shell
        and #style.roundedBorder.rings == 3 and style.roundedBorder.rings[1].vertex[4] == .45,
        "rounded border did not honor its width, opacity or shell motion")
    local contour, inset = W.NS.Skin.GetOwnedWindowContour(W.CF)
    assert(contour and contour.fill == mask.texture and inset == 1, "focus used the native rectangular bag bounds")
    local reagentContour, reagentInset = W.NS.Skin.GetOwnedWindowContour(ContainerFrame6)
    assert(reagentContour and reagentInset == 0, "focus missed the standalone bag contour")
    assert(reagent[6]:IsShown() and reagent[6].shellMask == reagent[2].shellMask,
        "rounded standalone bag lost or failed to clip the accent at the top edge")
    for i = 1, 4 do assert(reagent[6].color[i] == reagentColor[i], "rounding changed the standalone accent") end
    provider.DB.geometry.windowRadius = 16
    api:OnAppearanceChanged("geometry", "windowRadius")
    assert(style[2].shellMask == mask and mask.texture:match("continuous_r16_fill.png$"), "radius did not repaint the same mask")
    W.S.Set("bags", "backpackBorderWidth", 0)
    assert(not style.roundedBorder:IsShown(), "rounded border stayed visible at zero width")
    W.S.Set("bags", "backpackBorderWidth", 4)
    provider.DB.geometry.roundWindows = false
    api:OnAppearanceChanged("profile", "apply")
    assert(not style[2].shellMask and not mask:IsShown() and not style.roundedBorder:IsShown()
        and style[6]:IsShown() and not W.NS.Skin.GetOwnedWindowContour(W.CF),
        "switching to a square profile did not restore original bag chrome")
    CheckBorder(style, 4, 1, 0, 0, .45)
    assert(not style[1].slice and style[1].color[4] > 0, "square profile retained the sliced shadow")
    provider.Safety.CanCreateRegions = function(_, allowImplicitProtected) return allowImplicitProtected and not W.combat end
    provider.DB.geometry.roundWindows = true
    reagent.roundedMask = nil -- a cold native window with no allocated mask
    W.EnterCombat()
    W.Insecure(W.M.Refresh, W.M)
    assert(W.M.needsRoundedWindow and not reagent[2].shellMask, "bag mask refusal was not deferred during combat")
    W.LeaveCombat()
    W.Apply()
    assert(not W.M.needsRoundedWindow and reagent[2].shellMask and style[2].shellMask == mask
        and style[1].slice and style[1].texture == mask.texture,
        "combat replay did not restore the shape or reuse the backpack mask")
    assert(#W.errors == 0 and #W.taint == 0, "modeled error or taint")
end
print("Backpack border defaults, rounded chrome, profile changes and theme updates passed on both clients")
