-- Native WorldMap exterior artwork and per-slice shape identity.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    local map = Native("WorldMapFrame", 100, 100, 600, 400)
    local border = Native("ContourBorder", 100, 100, 600, 400)
    border.parent, border.strata = map, "HIGH"
    map.BorderFrame = border
    local info = Native("ContourInfo", 143, 455, 64, 64)
    info.parent, info.kind = border, "Button"
    border.Tutorial = info
    local function Art(parent, left, bottom, width, height, asset)
        local art = Native("ContourArt", left, bottom, width, height)
        art.parent, art.kind, art.asset = parent, "Texture", asset
        function art:GetTexture() return self.asset end
        function art:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
        return art
    end
    info.I = Art(info, 152, 464, 46, 46, "Interface\\common\\help-i")
    local portrait = Native("ContourPortrait", 100, 499, 1, 1)
    portrait.parent = border
    portrait.portrait = Art(portrait, 95, 445, 62, 62, "native-book")
    portrait.CircleMask = Art(portrait, 97, 449, 58, 58, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    border.PortraitContainer = portrait
    border.GetChildren = function() return info, portrait end
    map.GetChildren = function() return border end
    local shellGeometry = { fill = "suite-shell", margins = { 9.5, 9.5, 9.5, 9.5 }, slice = true }
    local shell = { visible = true, spec = { inset = 2, fillVisible = false }, geometry = shellGeometry }
    NS.Registry.GetSurface = function(frame) return frame == map and shell or nil end
    W.TrackFocus(map, "contour")
    local character = Native("CharacterFrame", 900, 100, 300, 400)
    W.TrackFocus(character, "contour")
    local state = F.records[map]
    local function Covered(x, y)
        for _, veil in ipairs(state.veils) do
            local rect = veil.rect
            if veil.dim and x >= rect.left and x < rect.left + rect.width
                and y >= rect.bottom and y < rect.bottom + rect.height then return true end
        end
        return false
    end
    Check(not Covered(144, 518), "transparent help-button margin receives a rectangular dim band")
    Check(Covered(175, 505), "visible exterior help artwork lost its dimming")
    Check(Covered(99, 478), "portrait artwork left of the native root remains undimmed")
    Check(state.rect.contour and state.rect.contour.geometry == shellGeometry and state.rect.contour.inset == 2,
        "edge-only shell lost its registered shape/inset")
    local portraitContour
    for index = 2, state.footprintCount do
        local shape = state.footprints[index].contour
        if shape and shape.art and shape.art.asset == "native-book" then portraitContour = shape end
    end
    Check(portraitContour and portraitContour.circle and portraitContour.circle.width == 58 / 62,
        "native portrait discovery lost its actual circular alpha mask")
    for index = 1, state.sliceCount do
        local slice = state.slices[index]
        Check(slice.source ~= nil, "rectangle subtraction discarded its original contour")
        if slice.bottom >= 500 then
            Check(slice.source.contour ~= nil, "exterior piece lost its alpha contour")
        end
    end
    -- Blizzard's X over the top edge (Forever's 28px close) is window chrome
    -- the inactive veil dims, until our caption cells stand for it: faded
    -- under them, it leaves no box in the veil.
    local close = Native("ContourClose", 676, 487, 28, 28)
    close.parent, close.kind = border, "Button"
    border.GetChildren = function() return info, portrait, close end
    map:Hide(); map:Show(); Tick(); Click(character)
    Check(Covered(690, 510), "an exterior native button lost its dimming")
    NS.WindowFocusChrome.SetHidden(function(frame) return frame == close end)
    map:Hide(); map:Show(); Tick(); Click(character)
    Check(not Covered(690, 510), "a faded native caption button still shapes the focus veil")
    NS.WindowFocusChrome.SetHidden(NS.WindowControlChrome.IsFaded)
    border.GetChildren = function() return info, portrait end
    map:Hide(); map:Show(); Tick(); Click(character)
    local foreignWrites = 0
    for _, frame in ipairs({ map, border, info, portrait, portrait.portrait, portrait.CircleMask }) do
        foreignWrites = foreignWrites + (frame.geometryWrites or 0)
    end
    Check(foreignWrites == 0, "contour discovery wrote native geometry")
    info.I.asset = { secret = true }
    map:Hide(); map:Show(); Tick(); Click(character)
    Check(not Covered(175, 505), "secret native art fell back to an unmasked click rectangle")
    info.I.asset = "Interface\\common\\help-i"
    map:Hide(); map:Show(); Tick(); Click(character)
    local reads = 0
    info.I.GetTexture = function() reads = reads + 1; return info.I.asset end
    map:Hide()
    for _ = 1, 100 do Tick() end
    Check(reads == 0, "closed-window contour discovery polled native artwork")

    character:Hide()
    local lower = Native("ProfessionsFrame", 103, 278, 18, 20)
    local top = Native("CharacterFrame", 50, 50, 400, 400)
    local hosted = Native("HostedSuiteCharacter", 80, 80, 160, 160)
    hosted:SetScale(1.25)
    NS.Registry.GetSurface = function(frame)
        if frame == hosted then
            return { visible = true, spec = { inset = 2 }, geometry = {
                fill = "suite-r24-fill", outside = "suite-r24-outside", margins = { 27.5, 27.5, 27.5, 27.5 },
                slice = true, shape = "round", radius = 24,
            } }
        end
    end
    NS.DB.geometry.roundWindows = true
    W.TrackFocus(lower, "contour")
    F.Present(top, hosted)
    W.TrackFocus(top, "contour")
    local hiddenUnderTop, clearTop = F.records[lower], F.records[top]
    Check(F.active == clearTop and #clearTop.veils == 0, "new clear presentation was previously dimmed")
    Check(not hiddenUnderTop.covered and hiddenUnderTop.sliceCount > 0,
        "rounded foreground incorrectly skipped a lower window fully inside its bounds")
    local cornerSlice
    for index = 1, hiddenUnderTop.sliceCount do
        local slice = hiddenUnderTop.slices[index]
        if slice.left <= 104 and slice.left + slice.width > 104 and slice.bottom <= 295 and slice.bottom + slice.height > 295 then
            cornerSlice = slice
            break
        end
    end
    Check(cornerSlice and not cornerSlice.cutoutMask, "mixed-scale cutout lost the dimmed band at the visible corner")
    local cut = clearTop.rect.roundedCut
    Check(cut and cut.geometry.outside == "suite-r24-outside" and cut.left == 102.5 and cut.bottom == 102.5
        and cut.width == 195 and cut.unitScale == 1.25, "cutout used native bounds, ignored the inset, or lost the overlay scale")
    Check(not NS.WindowFocusGeometry.Covers(clearTop.rect, lower, 0)
        and NS.WindowFocusGeometry.Covers(clearTop.rect, { left = 190, bottom = 190, width = 20, height = 20 }, 0),
        "coverage did not distinguish the transparent corner from the opaque interior")
    local carving = NS.WindowFocusGeometry
    local example = { rect = { left = 90, bottom = 270, width = 40, height = 40, unitScale = 1.25 } }
    Check(carving.Begin(example) and carving.SubtractWindow(example, clearTop), "same-scale corner could not be carved")
    local exact
    for index = 1, example.sliceCount do
        if example.slices[index].cutoutMask == cut then exact = true end
    end
    Check(exact, "same-scale opaque source missed the inverse mask")
    Check(carving.SubtractWindow(example, clearTop), "overlapping inverse masks could not be reduced to bands")
    for index = 1, example.sliceCount do
        local mask = example.slices[index].cutoutMask
        Check(not mask or mask == cut, "a corner slice retained competing inverse masks")
    end
    local subtract, rectangularRetry = carving.SubtractWindow, false
    carving.SubtractWindow = function(state, other, rectangular)
        if state == hiddenUnderTop then
            if not rectangular then
                state.roundedCuts = true
                return false
            end
            rectangularRetry = state.roundedCuts == nil and state.sliceCount == 1
        end
        return subtract(state, other, rectangular)
    end
    F.OwnedContourChanged(top)
    Tick()
    carving.SubtractWindow = subtract
    Check(rectangularRetry, "exhausted corner slices did not restart with rectangular subtraction")
    local reconcile
    NS.Registry.QueueJob = function(callback) reconcile = callback end
    NS.DB.geometry.roundWindows = false
    listeners[F](F, "theme", "look")
    Check(reconcile ~= nil, "changing rounding did not wait for the surface refresh")
    reconcile()
    Check(hiddenUnderTop.covered and not Dimmed(lower), "disabling rounding did not restore the rectangular cutout")

    local function Noop() end
    local binds, unbinds, typeReads, enumerations = 0, 0, 0, 0
    local function NewTexture()
        return { GetObjectType = function() typeReads = typeReads + 1; return "Texture" end,
            AddMaskTexture = function() binds = binds + 1 end, RemoveMaskTexture = function() unbinds = unbinds + 1 end }
    end
    local regions = {}
    for i = 1, 7 do regions[i] = NewTexture() end
    local canvas = {
        CreateMaskTexture = function()
            return { SetTexture = Noop, SetTexCoord = Noop, ClearAllPoints = Noop, SetPoint = Noop, SetSize = Noop, Show = Noop }
        end,
        GetNumRegions = function() return #regions end,
        GetRegions = function() enumerations = enumerations + 1; return unpack(regions) end,
    }
    local veil = { canvas = canvas }
    local box = { left = 0, bottom = 0, width = 100, height = 100, unitScale = 1 }
    local function ApplyMask() Check(NS.WindowFocusContour.Apply(veil, box, box), "valid contour paint failed") end
    for i = 1, 10 do ApplyMask() end
    print(("10 unmasked paints: %d region enumerations, %d type queries"):format(enumerations, typeReads))
    Check(enumerations == 0 and typeReads == 0, "unmasked paint scanned textures with no mask to apply or release")
    box.contour = { art = { asset = "sample", uv = { 0, 1, 0, 1 } } }
    for i = 1, 10 do ApplyMask() end
    Check(binds == 7 and typeReads == 7, "an unchanged mask binding repeated widget queries")
    local old = regions[7]
    regions[7] = NewTexture()
    ApplyMask()
    Check(binds == 8 and typeReads == 8, "same-size region replacement missed its first mask")
    box.contour = nil
    ApplyMask()
    Check(unbinds == 7, "returning to an unmasked shape left bound textures")
    regions[7] = old
    ApplyMask()
    Check(unbinds == 8, "a returning detached texture retained its old mask")
    local endScans = enumerations
    ApplyMask()
    Check(enumerations == endScans, "settled unmasked canvas kept scanning textures")
    local waiting, secret = NewTexture(), { secret = true }
    local publicType = waiting.GetObjectType
    waiting.GetObjectType = function() return secret end
    regions[8], regions[9] = secret, waiting
    box.contour = { art = { asset = "sample", uv = { 0, 1, 0, 1 } } }
    ApplyMask()
    Check(binds == 15, "restricted texture or object type participated in a new mask binding")
    waiting.GetObjectType = publicType
    ApplyMask()
    Check(binds == 16, "a previously unreadable object type was not retried")


end
]======]
assert(loadstring(source:sub(1, stop - 1) .. body .. '\nprint("suite_window_focus_contour_contract: " .. checks .. " checks passed")',
    "@window_focus_contour_contract"))()
