local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local W = H.New(root, flavor)
    local extent
    local setExtent = W.MM.SetExtent
    W.MM.SetExtent = function(key, left, right, top, bottom)
        if key == "queue" then extent = { left, right, top, bottom } end
        setExtent(key, left, right, top, bottom)
    end
    local native = W.New("Frame", nil, W.G.UIParent)
    local eye = W.New("Button", "QueueStatusButton", native)
    eye:SetSize(45, 45)
    eye:SetScale(.8)
    eye:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", -45, 4)
    local click = function() end
    eye:SetScript("OnClick", click)
    eye:Hide()
    H.Enable(W, { captured = true, queueStatusEnabled = true, queueStatusSize = 32,
        queueStatusX = -2, queueStatusY = -52 })
    W.Step()
    assert(not eye:IsShown(), "layout force-showed the native queue eye")
    assert(eye:GetParent() == W.MM.host and math.abs(eye:GetScale() - 32 / 45) < .00001)
    local point, relative, relativePoint, x, y = eye:GetPoint()
    assert(point == "CENTER" and relative == W.MM.host and relativePoint == "TOPLEFT"
        and math.abs(x * eye:GetScale() + 2) < .00001 and math.abs(y * eye:GetScale() + 52) < .00001,
        tostring(point) .. "/" .. tostring(relativePoint) .. "/" .. tostring(x) .. "/" .. tostring(y))
    assert(eye:GetScript("OnClick") == click, "queue click behavior changed")
    eye:Show()
    W.Step()
    eye:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", -45, 4)
    W.Step()
    assert(select(2, eye:GetPoint()) == W.MM.host, "native reanchor escaped minimap placement")
    assert(W.S.SetMany("minimap", { queueStatusX = 260, queueStatusY = -260 }))
    W.Step()
    local width, height = W.MM.Dimensions()
    assert(extent[2] == 276 - width and extent[4] == 276 - height,
        "queue hover bounds omit right or bottom overflow")
    assert(W.S.Set("minimap", "queueStatusEnabled", false))
    assert(eye:GetParent() == native and eye:GetScale() == .8, "queue opt-out lost native geometry")
    assert(W.S.Set("minimap", "queueStatusEnabled", true))
    assert(eye:GetParent() == W.MM.host)
    -- One group finder: the group finder button holds the eye, which stands in
    -- for the button while Blizzard shows it (the player is queued).
    eye:Hide()
    -- A single pass places a new button before the eye that stands on it.
    W.config.dungeonWidth, W.config.dungeonHeight, W.config.dungeonButton = 52, 26, true
    W.MM.LayoutElements()
    local finder, holder = assert(W.MM.dungeonButton), assert(W.MM.dungeonEyeHolder)
    assert(select(2, eye:GetPoint()) == holder, "the eye was placed before its group finder button")
    W.Step()
    point, relative, relativePoint, x, y = eye:GetPoint()
    assert(eye:GetParent() == holder and point == "CENTER" and relative == holder and relativePoint == "CENTER"
        and x == 0 and y == 0 and math.abs(eye:GetScale() - 26 / 45) < .00001, "the eye did not stand on the group finder")
    point, relative, relativePoint = holder:GetPoint()
    assert(point == "CENTER" and relative == finder and relativePoint == "CENTER", "the eye's place left the button")
    -- A Suite glyph in its look's colour, without a box; only the square
    -- symbol takes clicks.
    local symbols, tints, icon = W.Suite.MinimapGroupFinderSymbol, W.Suite.MinimapGroupFinderTint, finder.dungeonIcon
    local function Tinted(hex)
        local r, g, b = W.S.RGB(hex)
        return math.abs(icon.vertex[1] - r) < 1e-6 and math.abs(icon.vertex[2] - g) < 1e-6
            and math.abs(icon.vertex[3] - b) < 1e-6
    end
    assert(W.S.Set("minimap", "stylePreset", 9))
    assert(icon.texture == "Interface\\AddOns\\MSUF_Suite\\Media\\GroupFinder\\Eye" and Tinted("b9ab86")
        and icon.desaturation == 0 and not rawget(finder, "dungeonRing"), "the eye glyph lost Midnight Dark or kept a box")
    local insets = finder.hitInsets
    assert(insets[1] == 13 and insets[2] == 13 and insets[3] == 0 and insets[4] == 0, "the empty sides take clicks")
    for preset, hex in pairs({ [8] = "57c7df", [7] = "d8b66a", [11] = "e6ecf2" }) do
        assert(W.S.Set("minimap", "stylePreset", preset))
        assert(Tinted(hex), "the glyph missed the colour of look " .. preset)
    end
    local r, g, b = W.S.ClassRGB("MAGE")
    assert(W.S.Set("minimap", "stylePreset", 12))
    assert(icon.vertex[1] == r and icon.vertex[2] == g and icon.vertex[3] == b, "Class Style did not class-colour the glyph")
    assert(W.S.SetMany("minimap", { stylePreset = 8, dungeonIconTint = tints.CLASS, dungeonStyle = 2 }))
    assert(icon.vertex[1] == r and icon.vertex[2] == g and icon.vertex[3] == b, "the class colour missed the glyph")
    assert(finder.dungeonRing:IsShown() and finder.dungeonDisc:IsShown() and finder.dungeonRing.width == 26
        and finder.dungeonRing.vertex[1] == r, "Modern Dark lost its round badge in the symbol's colour")
    assert(W.S.SetMany("minimap", { dungeonIconTint = tints.CUSTOM, dungeonIconColor = "336699" }))
    assert(Tinted("336699"), "the custom colour missed the glyph")
    -- Blizzard's eye: the first frame of its searching flipbook, in its own
    -- colours on Automatic and desaturated under a chosen colour.
    assert(W.S.Set("minimap", "dungeonIcon", symbols.BLIZZARD))
    local coords = icon.coords
    assert(icon.atlas == "groupfinder-eye-flipbook-searching" and coords[1] == 0 and math.abs(coords[2] - 1 / 11) < 1e-9
        and coords[3] == 0 and math.abs(coords[4] - 1 / 8) < 1e-9 and icon.desaturation == 1 and Tinted("336699"),
        "Blizzard's eye is not its flipbook's first frame in the chosen colour")
    assert(W.S.Set("minimap", "dungeonIconTint", tints.AUTO))
    assert(icon.desaturation == 0 and icon.vertex[1] == 1 and icon.vertex[2] == 1 and icon.vertex[3] == 1,
        "Automatic recoloured Blizzard's eye")
    -- With the atlas' file known, the frame is cut from that file in file coordinates.
    local atlasInfo = W.G.C_Texture.GetAtlasInfo
    W.G.C_Texture.GetAtlasInfo = function()
        return { file = 4321, leftTexCoord = .5, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = .5 }
    end
    assert(W.S.Set("minimap", "dungeonIconTint", tints.CLASS))
    coords = icon.coords
    assert(icon.texture == 4321 and coords[1] == .5 and math.abs(coords[2] - (.5 + .5 / 11)) < 1e-9 and coords[3] == 0
        and math.abs(coords[4] - .5 / 8) < 1e-9, "the eye's frame was not cut from the atlas file")
    W.G.C_Texture.GetAtlasInfo = atlasInfo
    assert(W.S.Set("minimap", "dungeonIconTint", tints.AUTO))
    -- A glyph the client has not loaded yet (no restart) falls back to Blizzard's eye.
    local setTexture = icon.SetTexture
    icon.SetTexture = function(self, value) self.texture = value return false end
    assert(W.S.Set("minimap", "dungeonIcon", symbols.GROUP))
    assert(icon.atlas == "groupfinder-eye-flipbook-searching" and icon.coords[2] < 1, "a missing glyph left a green square")
    icon.SetTexture = setTexture
    assert(W.S.SetMany("minimap", { dungeonIcon = symbols.EYE, dungeonStyle = 1 }))
    assert(not finder.dungeonRing:IsShown(), "the Default style kept the badge")
    assert(finder:IsVisible() and not eye:IsShown(), "an idle queue hid the group finder or showed the eye")
    assert(extent[1] == 0 and extent[2] == 0 and extent[3] == 0 and extent[4] == 0, "the standing eye kept its own bounds")
    eye:Show()
    W.Step()
    assert(eye:IsVisible() and not finder:IsShown(), "the queue showed two group finders")
    assert(eye:GetScript("OnClick") == click, "standing in changed the eye's click")
    eye:Hide()
    W.Step()
    assert(finder:IsVisible(), "the group finder stayed hidden after the queue")
    -- Hidden: Blizzard may show the eye, the player never sees it; the button stays.
    eye:Show()
    assert(W.S.Set("minimap", "queueStatusHidden", true))
    W.Step()
    assert(eye:IsShown() and not eye:IsVisible() and finder:IsVisible(), "the hidden eye showed or replaced the button")
    assert(W.S.Set("minimap", "dungeonButton", false))
    W.Step()
    assert(not eye:IsVisible() and not finder:IsShown(), "the hidden eye came back without the group finder")
    assert(W.S.Set("minimap", "queueStatusHidden", false))
    W.Step()
    point, relative, relativePoint = eye:GetPoint()
    assert(eye:IsVisible() and relative == W.MM.host and relativePoint == "TOPLEFT", "the eye lost its own offsets")
    assert(W.S.SetMany("minimap", { dungeonButton = true, queueStatusEnabled = false }))
    W.Step()
    assert(select(2, eye:GetPoint()) == holder and not finder:IsShown(), "the group finder needs the anchor setting")
    -- When to show: the button and the eye standing in for it follow one rule.
    local SHOW = W.Suite.MinimapGroupFinderShow
    eye:Hide()
    assert(W.S.Set("minimap", "dungeonShow", SHOW.MOUSEOVER))
    W.Step()
    assert(not finder:IsShown() and not holder:IsShown(), "a mouseover group finder showed without the pointer")
    W.Fire(W.MM.catcher, "OnEnter")
    W.Step()
    assert(finder:IsShown() and holder:IsShown(), "pointing at the map did not show the group finder")
    assert(finder.hookedScripts and finder.hookedScripts.OnEnter, "pointing at the button would close it")
    eye:Show()
    W.Step()
    assert(eye:IsVisible() and not finder:IsShown(), "the queue eye did not stand in on mouseover")
    W.Fire(W.MM.catcher, "OnLeave")
    W.Advance(0.2)
    assert(not W.MM.hovered and eye:IsShown() and not eye:IsVisible(), "the eye stayed after the pointer left")
    eye:Hide()
    assert(W.S.Set("minimap", "dungeonShow", SHOW.OUT_OF_COMBAT))
    W.Step()
    assert(finder:IsShown() and holder:IsShown(), "an out-of-combat group finder hid outside combat")
    W.SetCombat(true)
    W.Step()
    assert(not finder:IsShown() and not holder:IsShown(), "the group finder stayed in combat")
    W.SetCombat(false)
    W.Step()
    assert(finder:IsShown(), "the group finder did not return after combat")
    assert(W.S.Set("minimap", "dungeonShow", SHOW.QUEUED))
    W.Step()
    assert(not finder:IsShown() and holder:IsShown(), "only while queued showed the button")
    eye:Show()
    W.Step()
    assert(eye:IsVisible() and not finder:IsShown(), "only while queued hid the queue eye")
    W.SetCombat(true)
    W.Step()
    assert(eye:IsVisible(), "combat hid an eye whose rule ignores combat")
    W.SetCombat(false)
    assert(W.S.Set("minimap", "dungeonShow", SHOW.ALWAYS))
    W.Step()
    assert(W.S.Set("minimap", "enabled", false))
    assert(eye:GetParent() == native and eye:GetScale() == .8 and eye:GetScript("OnClick") == click)
end
print("Native queue eye: position, size, visibility, reanchor, group finder stand-in, show rules, hiding and restoration passed on both clients")
