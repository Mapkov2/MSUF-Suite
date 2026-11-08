local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local paints, watches, current = {}, {}, { shape = "RECTANGLE" }
    local W = H.New(root, flavor, { beforeModules = function(world)
        local bridge = world.Suite.HostBridge
        bridge.IconSkinLook = function(choice, shape)
            if choice == "CUSTOM" or choice == nil or current.shape ~= shape then return nil end
            return current
        end
        bridge.PaintIconSkin = function(owner, look, width, height, anchor)
            paints[#paints + 1] = { owner, look, width, height, anchor }
            return look ~= nil
        end
        bridge.IconSkinOutset = function() return 6, 8 end
        bridge.WatchIconSkins = function(id, on) watches[#watches + 1] = { id, on } end
    end })
    local rule = assert(W.Suite.SuiteCatalog.minimap.rules.iconSkin, "minimap icon skin setting missing")
    assert(rule.default == "CUSTOM" and rule.hidden, "old map profiles must preserve their own look")
    H.Enable(W, { captured = true, size = 240, borderSize = 2, outerBorderSize = 3, shadowSize = 6 })
    W.Step()
    local MM = W.MM
    assert(#paints == 0 and MM.style.iconSurface == nil, "off map skin allocated or painted")
    assert(watches[1][1] == "minimap" and not watches[1][2], "CUSTOM maps must not watch global skins")
    local nativeMask, nativeZoom = W.calls.mask, W.calls.zoom
    assert(W.S.Set("minimap", "iconSkin", "DEFAULT"))
    assert(watches[#watches][2], "DEFAULT maps must watch global skin edits")
    assert(W.calls.mask == nativeMask and W.calls.zoom == nativeZoom, "skin edit rebuilt native map scene")
    local last = assert(paints[#paints], "map skin was not painted")
    assert(last[1] ~= W.G.Minimap and last[5] == MM.host, "painter must own only Suite layers")
    assert(last[2] == current and last[3] == 240 and last[4] == 240, "square map skin mismatch")
    assert(not MM.edges[1]:IsShown() and not MM.outerEdges[1]:IsShown(), "double minimap border")
    for _, ring in ipairs(MM.shadows) do assert(not ring.edges[1]:IsShown(), "double minimap shadow") end
    local count = #paints
    W.M:Refresh(); W.M:Refresh()
    assert(#paints == count, "unchanged cold apply repainted map skin")
    assert(W.S.Set("minimap", "shape", 3))
    last = paints[#paints]
    assert(last[3] == 240 and last[4] == 160 and W.config.shape == 3, "wide map was forced square")
    assert(W.S.Set("minimap", "shape", 2))
    assert(paints[#paints][2] == nil and MM.disc:IsShown(), "incompatible circle skin must restore configured ring")
    current = { shape = "CIRCLE" }
    W.M:Refresh()
    assert(paints[#paints][2] == current and not MM.disc:IsShown(), "default change missed circle map")
    assert(W.S.Set("minimap", "iconSkin", "SHADOW1"))
    assert(watches[#watches][2], "fixed skins must follow global tint and gloss edits")
    W.SetCombat(true)
    count = #paints
    W.config.iconSkin = "CUSTOM"
    W.M:Refresh()
    assert(#paints == count, "combat refresh wrote skin layers")
    W.SetCombat(false); W.Step()
    assert(paints[#paints][2] == nil and MM.disc:IsShown(), "deferred reset missed configured ring")
    assert(not watches[#watches][2], "reset CUSTOM must stop watching global skins")
    assert(W.S.Set("minimap", "iconSkin", "DEFAULT"))
    assert(W.S.Set("minimap", "enabled", false))
    assert(paints[#paints][2] == nil and not MM.style.iconSurface:IsShown(), "disable retained map skin")
    assert(watches[#watches][1] == "minimap" and not watches[#watches][2], "disabled minimap watches skin")
end
-- Old hosts keep the configured map and never create a material surface.
do
    local W = H.New(root, "Mainline")
    H.Enable(W, { captured = true, iconSkin = "SHADOW1", borderSize = 2 })
    W.Step()
    assert(W.MM.style.iconSurface == nil and W.MM.edges[1]:IsShown(), "old host lost configured look")
end

local function CreatePreview(W)
    local frame = W.G.CreateFrame("Frame", nil, W.G.UIParent)
    local F = getmetatable(frame).__index
    local R = getmetatable(frame:CreateTexture()).__index
    F.CreateMaskTexture = F.CreateTexture
    function R:AddMaskTexture(mask) self.mask = mask end
    local P = { Suite = W.Suite, S = W.S, catalog = W.Suite.SuiteCatalog, RGB = W.S.RGB }
    local chunk = assert(loadfile(root .. "/MSUF_Suite_Options/Pages/MinimapPreviewArt.lua"))
    setfenv(chunk, W.G)("MSUF_Suite_Options", P)
    return P.CreateMinimapPreviewArt(frame)
end

-- Preview paints the exact shared renderer at its own scale, and hiding its
-- map/border layer hides the whole host material without showing old rings.
do
    local painted = {}
    local W = H.New(root, "Mainline", { beforeModules = function(world)
        local bridge = world.Suite.HostBridge
        local look = {}
        bridge.IconSkinLook = function() return look end
        bridge.PaintIconSkin = function(owner, skin, width, height, anchor)
            painted[#painted + 1] = { owner, skin, width, height, anchor }
            return skin ~= nil
        end
        bridge.IconSkinOutset = function() return 0, 0 end
    end })
    local art = CreatePreview(W)
    local hidden = {}
    local function Layer(key) return not hidden[key] end
    W.config.iconSkin, W.config.shape, W.config.size = "SHADOW1", 3, 240
    hidden.map = true
    art:Paint(W.config, .5, Layer)
    assert(art.style.iconSurface == nil and not art.edges[1]:IsShown(), "cold hidden preview drew old skin")
    hidden.map = false
    art:Paint(W.config, .5, Layer)
    local last = painted[#painted]
    assert(last[5] == art.map and last[3] == 120 and last[4] == 80, "preview dimensions diverge")
    assert(art.style.iconSurface:GetFrameLevel() > art.clip:GetFrameLevel(), "terrain covers preview material")
    assert(not art.edges[1]:IsShown(), "preview double border")
    hidden.border = true
    art:Paint(W.config, .5, Layer)
    assert(painted[#painted][2] == nil and not art.style.iconSurface:IsShown(), "preview border layer leaked material")
    hidden.border, hidden.map = false, true
    art:Paint(W.config, .5, Layer)
    assert(not art.style.iconSurface:IsShown(), "hidden preview map retained material")
end

-- Optional real MSUF 7.0 engine: runtime mask/scene/release and the shared
-- default notifications use the actual host Compile/Paint implementation.
if arg[2] then
    -- Harness options that load the real host; the world's MSUF default skin
    -- is `default`, and host.skins / host.shared are filled in at load.
    local function RealHost(default)
        local host = {}
        function host.beforeModules(world)
            local G = world.G
            local A3 = { _runtimeConfigGen = 1 }
            local shared = { iconSkinDefault = { styleSkin = default } }
            host.shared = shared
            function A3.EnsureDB() return {}, shared end
            local MSUF = { MSUF_Auras3 = A3, Util = { InCombat = function() return world.combat end } }
            local providers = { MSUF_PixelLayoutRegion = function(region) return region end,
                MSUF_EventBus_Register = function() end, MSUF_EventBus_Unregister = function() end }
            dofile(root .. "/tools/tests/suite_test_support.lua").HostMediaProviders(providers)
            function MSUF.Require(name) return assert(providers[name], name) end
            function MSUF.RunHostAPIStep(_, fn, ...) return true, fn(...) end
            function MSUF.ExportPublic(name, value) MSUF[name] = value end
            G.UnitAffectingCombat = function() return world.combat end
            local addon = arg[2] .. "/MidnightSimpleUnitFrames/"
            for _, file in ipairs({ "Runtime/MSUF_BorderStyles.lua", "Auras3/MSUF_Auras3_IconShape.lua",
                "Auras3/MSUF_Auras3_IconSkins.lua", "Auras3/MSUF_Auras3_IconSkins_Catalog.lua",
                "Auras3/MSUF_Auras3_IconSkins_Host.lua" }) do
                local chunk = assert(loadfile(addon .. file))
                setfenv(chunk, G)("MidnightSimpleUnitFrames", MSUF)
            end
            local skins = A3.IconSkins
            A3.MenuModel = {}
            MSUF.MSUF2 = {
                Widgets = {}, Theme = {}, AuraControls = { RequestAuraRuntime = function() end },
                ControlSchema = { UnitOptions = function() return {} end },
                RegisterPage = function() end, Format = string.format, Tr = function(text) return text end,
            }
            local menu = assert(loadfile(arg[2] .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_IconSkins.lua"))
            setfenv(menu, G)("MidnightSimpleUnitFrames_Options", MSUF)
            host.skins, host.page = skins, MSUF.MSUF2.IconSkinsPage
            G.MSUF_HostAPI = { version = 1, GetIconSkins = function() return skins.Host end }
            local sample = G.CreateFrame("Frame", nil, G.UIParent):CreateTexture()
            local R = getmetatable(sample).__index
            function R:SetSnapToPixelGrid(value) self.snap = value end
            function R:SetTexelSnappingBias(value) self.bias = value end
            function R:SetDesaturated(value) self.desaturated = value end
        end
        return host
    end
    for _, flavor in ipairs({ "Mainline", "Forever" }) do
        local host = RealHost("SHADOW1")
        local W = H.New(root, flavor, host)
        local skins, shared = host.skins, host.shared
        H.Enable(W, { captured = true, iconSkin = "DEFAULT", size = 240, borderSize = 2 })
        W.Step()
        local renderer = W.MM.style
        assert(renderer.iconPaintLook.skin.def.shape == "RECTANGLE", "real rectangular material missing")
        local before = renderer.iconPaintLook
        shared.iconSkinDefault.styleSkin = "DARK2"
        skins.NotifyChanged("profile")
        assert(renderer.iconPaintLook ~= before, "real profile notification missed map")
        assert(W.S.Set("minimap", "shape", 3) and renderer.iconHeight == 160, "real wide material missed geometry")
        shared.iconSkinDefault.styleSkin = "RING"
        assert(W.S.Set("minimap", "shape", 2))
        skins.NotifyChanged("profile")
        assert(renderer.iconPaintLook.skin.def.shape == "CIRCLE", "real circular material missing")
        local masks, zoom = W.calls.mask, W.calls.zoom
        local painted, surface, writes = renderer.iconPaintLook, renderer.iconSurface, 0
        local F = getmetatable(surface).__index
        local R = getmetatable(surface:CreateTexture()).__index
        -- Count actual native calls on the owned painter surface/regions.
        for _, prototype in ipairs({ F, R }) do
            for key, method in pairs(prototype) do
                if type(method) == "function" and (key:match("^Set") or key:match("^Create")
                    or key == "Hide" or key == "Show" or key == "ClearAllPoints") then
                    prototype[key] = function(self, ...)
                        if self == surface or self.parent == surface then writes = writes + 1 end
                        return method(self, ...)
                    end
                end
            end
        end
        renderer:PaintIconSkin(W.config, renderer.iconWidth, renderer.iconHeight, W.MM.host, true)
        renderer:PaintIconSkin(W.config, renderer.iconWidth, renderer.iconHeight, W.MM.host, true)
        W.M:Refresh(); W.M:Refresh()
        assert(writes == 0, "unchanged cold material wrote native regions")
        assert(renderer.iconPaintLook == painted and W.calls.mask == masks and W.calls.zoom == zoom,
            "unchanged material refreshed native minimap scene")
        assert(W.S.Set("minimap", "iconSkin", "CUSTOM") and not renderer.iconSurface:IsShown(), "real reset leaked skin")
        assert(W.MM.disc:IsShown(), "real reset failed to restore own circle")
        local refresh, refreshes = W.M.Refresh, 0
        W.M.Refresh = function(self) refreshes = refreshes + 1; return refresh(self) end
        shared.iconSkinDefault.styleSkin = "SHADOW1"
        skins.NotifyChanged("apply")
        assert(refreshes == 0, "actual global callback refreshed a CUSTOM map")
        assert(W.S.Set("minimap", "shape", 1) and W.S.Set("minimap", "iconSkin", "SHADOW1"))
        local prior, fixed = refreshes, renderer.iconPaintLook.signature
        shared.iconSkinDefault.styleSkinColorOverride = true
        shared.iconSkinDefault.styleSkinColor = { .4, .6, .8, 1 }
        shared.iconSkinDefault.styleSkinGlossColor = { .8, .7, .6, .5 }
        skins.NotifyChanged("apply")
        assert(refreshes == prior + 1 and renderer.iconPaintLook.signature ~= fixed,
            "actual fixed skin must still apply global frame/gloss colors")
        assert(W.S.Set("minimap", "iconSkin", "CUSTOM"))
        prior = refreshes
        shared.iconSkinDefault.styleSkinColor = { .5, .6, .8, 1 }
        skins.NotifyChanged("profile")
        assert(refreshes == prior, "actual reset CUSTOM map must stop following global edits")
        assert(W.S.Set("minimap", "enabled", false), "real release failed")
    end
    -- The same Shadow 3 assignment draws on square and round maps. Neither
    -- selecting it nor taking it off changes the minimap's native shape.
    for _, flavor in ipairs({ "Mainline", "Forever" }) do
        local host = RealHost("SHADOW3")
        local W = H.New(root, flavor, host)
        local page, area = host.page, "suite_minimap"
        page.RegisterArea({
            key = area, group = "Minimap", label = "Map", skinVariants = true,
            shape = function() return W.config.shape == 2 and "CIRCLE" or "RECTANGLE" end,
            read = function() return W.config.iconSkin end,
            write = function(choice) assert(W.S.Set("minimap", "iconSkin", choice)) end,
        })
        local ember = {}
        for key, value in pairs(W.Suite.MinimapStylePresets[4]) do ember[key] = value end
        ember.captured, ember.size, ember.iconSkin = true, 240, "DEFAULT"
        H.Enable(W, ember)
        W.Step()
        local MM, renderer = W.MM, W.MM.style
        local function CheckRoundLook(skinned)
            assert(W.config.shape == 2 and W.config.stylePreset == 4, flavor .. ": Ember lost its shape or preset")
            assert(W.G.Minimap.mask == MM.MASKS[2], flavor .. ": the map lost its circle mask")
            assert(renderer.glow:IsShown() and renderer.artOver:IsShown()
                and renderer.artOver:GetTexture() == W.Suite.MinimapStyle.paths[3], flavor .. ": Ember glow or ring missing")
            assert(MM.disc:IsShown() == not skinned and not MM.edges[1]:IsShown(), flavor .. ": own border state")
            local shadow = MM.shadows and MM.shadows[1]
            assert((shadow and shadow.disc:IsShown() or false) == not skinned, flavor .. ": own shadow state")
            assert(not shadow or not shadow.edges[1]:IsShown(), flavor .. ": square shadow on a round map")
            assert(renderer.iconSurface:IsShown() == skinned, flavor .. ": unexpected skin surface visibility")
            local shown = 0
            host.skins.EachLayer(renderer.iconSurface, function(texture)
                if not texture:IsShown() then return end
                shown = shown + 1
                assert(texture:GetTexture():match("msuf_skin_shadow3_circle%.tga$"), flavor .. ": wrong shadow art")
            end)
            assert(shown == (skinned and 1 or 0), flavor .. ": round map must paint one radial skin layer")
        end
        assert(renderer.iconPaintLook and renderer.iconPaintLook.skin.def.shape == "CIRCLE",
            flavor .. ": inherited Shadow 3 did not draw on Ember")
        CheckRoundLook(true)
        assert(page.SkinDraws(area), flavor .. ": menu incorrectly reports a shape mismatch")
        local found = {}
        for _, item in ipairs(page.ProductValues(area)) do found[item.value] = true end
        assert(found.SHADOW3 and found.RING and not found.DARK3, flavor .. ": round choices do not match renderer")
        local masks, zoom = W.calls.mask, W.calls.zoom
        page.SelectProduct(area, "SHADOW3")
        CheckRoundLook(true)
        local art = CreatePreview(W)
        local function ShowLayer() return true end
        art:Paint(W.config, .5, ShowLayer)
        assert(art.style.iconPaintLook == renderer.iconPaintLook and art.style.iconSurface:IsShown(),
            flavor .. ": preview did not paint the same radial skin")
        page.SelectProduct(area, "CUSTOM")
        CheckRoundLook(false)
        art:Paint(W.config, .5, ShowLayer)
        assert(not art.style.iconSurface:IsShown(), flavor .. ": preview retained the removed skin")
        assert(W.calls.mask == masks and W.calls.zoom == zoom, flavor .. ": skin switches rebuilt native map")
        assert(W.Suite.HostBridge.IconSkinLook("SHADOW3", "CIRCLE") == nil, "map variant leaked to other modules")
        page.SelectProduct(area, "DEFAULT")
        CheckRoundLook(true)
        host.shared.iconSkinDefault.styleSkin = "DARK3"
        host.skins.NotifyChanged("profile")
        CheckRoundLook(false)
        assert(not page.SkinDraws(area), flavor .. ": menu incorrectly reports a match")
        host.shared.iconSkinDefault.styleSkin = "SHADOW3"
        host.skins.NotifyChanged("profile")
        CheckRoundLook(true)
        assert(W.S.Set("minimap", "shape", 1) and W.S.Set("minimap", "iconSkin", "SHADOW3"))
        assert(W.G.Minimap.mask == MM.MASKS[1] and renderer.iconPaintLook.skin.def.id == "SHADOW3"
            and renderer.iconSurface:IsShown() and not MM.edges[1]:IsShown() and not MM.disc:IsShown(),
            flavor .. ": a square map must take Shadow 3 instead of its own border")
        assert(W.S.Set("minimap", "iconSkin", "CUSTOM") and not renderer.iconSurface:IsShown() and MM.edges[1]:IsShown(),
            flavor .. ": No skin must restore the square map's own border")
        assert(W.S.Set("minimap", "enabled", false))
    end
end
print("Minimap icon skin cold lifecycle, square/circle/wide shapes and combat deferral passed")
