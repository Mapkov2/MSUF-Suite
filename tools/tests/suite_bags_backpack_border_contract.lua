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
    assert(#W.errors == 0 and #W.taint == 0, "modeled error or taint")
end
print("Backpack border default, custom, reset and theme updates passed on both clients")
