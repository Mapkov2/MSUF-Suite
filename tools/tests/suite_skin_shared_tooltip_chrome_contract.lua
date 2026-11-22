local root = assert(arg[1], "Suite root required")
local skin = root .. "/MSUF_Suite_Skin/"
local checks = 0

local function Check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local function Load(ns, path)
    assert(loadfile(skin .. path))("MSUF_Suite_Skin", ns)
end

local function Color(r, g, b, a)
    return { r = r, g = g, b = b, a = a }
end
CreateColor = Color
Enum = { UITextureSliceMode = { Stretched = 0 } }
InCombatLockdown = function() return false end
securecallfunction = function(callback, ...) return callback(...) end

local function Test(forever)
    local addonLoaded = false
    local frames, timers, listeners = {}, {}, {}
    local flags = setmetatable({}, { __mode = "k" })
    local nativeStyle, styleHook, building
    local genericPaints, materialReads = 0, 0
    local function NoNativeWrite()
        assert(not building, "skin wrote during the native tooltip build")
    end

    function CreateFrame()
        local frame = {}
        function frame:SetScript(event, callback) self[event] = callback end
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        frames[#frames + 1] = frame
        return frame
    end

    C_Timer = { After = function(delay, callback)
        assert(delay == 0, "unexpected tooltip timer")
        timers[#timers + 1] = callback
    end }
    local function NextFrame()
        local queue = timers
        timers = {}
        for index = 1, #queue do queue[index]() end
    end

    local function NativeObject(members)
        return setmetatable(members, { __newindex = function(_, key)
            error("skin wrote a Blizzard member: " .. key)
        end })
    end

    local function Texture(r, g, b, a)
        local values = { rgba = { r, g, b, a }, alpha = 1, shown = true }
        local region = NativeObject({
            SetAllPoints = function(_, anchor) values.anchor = anchor end,
            ClearAllPoints = function() values.anchor = nil end,
            GetAlpha = function() return values.alpha end,
            IsShown = function() return values.shown end,
            Show = function() NoNativeWrite(); values.shown = true end,
            Hide = function() NoNativeWrite(); values.shown = false end,
            SetAlpha = function(_, alpha)
                NoNativeWrite()
                values.alpha = alpha
                if forever then values.rgba[4] = alpha end
            end,
            GetVertexColor = function() return unpack(values.rgba) end,
            SetVertexColor = function(_, ...)
                NoNativeWrite()
                values.rgba = { ... }
                if forever then values.alpha = values.rgba[4] end
            end,
            SetGradient = function(_, direction, from, to)
                NoNativeWrite()
                values.gradient = { direction, from, to }
            end,
            IsProtected = function(self) return flags[self] == "protected", flags[self] == "protected" end,
        })
        return region, values
    end

    local function Tooltip()
        local center, fill = Texture(0.15, 0.15, 0.15, 0.93)
        local border, edge = Texture(0.6, 0.6, 0.6, 0.8)
        local sliceAlpha, art = 1, {}
        local frame = NativeObject({
            NineSlice = NativeObject({
                Center = center, TopEdge = border,
                CreateTexture = function()
                    local region, data = Texture(1, 1, 1, 1)
                    art[region] = data
                    return region
                end,
                GetAlpha = function() return sliceAlpha end,
                SetAlpha = function(_, alpha) NoNativeWrite(); sliceAlpha = alpha end,
            }),
            IsForbidden = function(self) return flags[self] == "forbidden" end,
            IsProtected = function(self) return flags[self] == "protected", flags[self] == "protected" end,
        })
        return frame, fill, edge, art
    end

    local tooltip, fill, edge, owned = Tooltip()
    local embedded, embeddedFill = Tooltip()
    local itemReference = Tooltip()
    local mainCompare, mainCompareFill = Tooltip()
    local linkCompare, linkCompareFill = Tooltip()
    GameTooltip, EmbeddedItemTooltip, ItemRefTooltip = tooltip, embedded, itemReference
    GameNoHeaderTooltip, ShoppingTooltip1, ShoppingTooltip2 = nil, mainCompare, nil
    ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 = nil, linkCompare
    GameSmallHeaderTooltip = Tooltip()
    flags[GameSmallHeaderTooltip] = "forbidden"

    nativeStyle = function(frame, values, red)
        building = true
        values.rgba = { red, 0.08, 0.09, 1 }
        if forever then values.alpha = 1 end
        Check(values.rgba[1] == red, "post-hook painted before native widgets finished")
        building = false
        if styleHook then styleHook(frame) end
    end
    SharedTooltip_SetBackdropStyle = nativeStyle
    hooksecurefunc = function(target, callback)
        Check(target == "SharedTooltip_SetBackdropStyle" and not styleHook,
            "shared frame method or duplicate hook")
        styleHook = callback
    end

    local material = { from = "popup", to = "ink", border = "border" }
    local palette = { popup = { 0.12, 0.23, 0.34, 0.8 }, ink = { 0.09, 0.1, 0.12, 1 }, border = { 0.7, 0.8, 0.9, 0.5 } }
    local states = {}
    local ns
    ns = {
        path = "",
        GeometryBorders = { 0, 1, 2 },
        GeometryRadii = { 4, 8, 12 },
        DB = {
            theme = { gradient = false, gradientStrength = 0.5, gradientDirection = "HORIZONTAL" },
            geometry = { family = "round", radius = 8, border = 1 },
        },
        Client = { isForever = forever, HasAddOn = function() return true end,
            IsAddOnLoaded = function() return addonLoaded end },
        IsCombatLocked = function() return false end,
        Registry = {
            AddListener = function(owner, callback) listeners[owner] = callback end,
            GetSurface = function() end,
        },
        Theme = {
            GetMaterial = function(role)
                Check(role == "popup", "tooltip stopped using popup material")
                materialReads = materialReads + 1
                return material
            end,
            GetColorTable = function(role) return palette[role] end,
            GetColor = function(role) return unpack(palette[role]) end,
            GetMaterialOpacity = function() return 0.75 end,
            GetBorderOpacity = function() return 0.6 end,
            Border = function() return 0.7, 0.8, 0.9, ns.DB.geometry.border > 0 and 0.3 or 0 end,
            ReuseColor = function(_, ...) return Color(...) end,
        },
        AdapterKit = {
            CancelDeferred = function() end,
            DeferHidden = function() return false end,
            Isolate = function(callback, ...) callback(...); return true end,
        },
        GenericWindows = { PrepareWindowMotion = function() end },
        GenericWindowsShared = {
            DEFAULT_OWNER = "generic",
            OwnerState = function(owner)
                states[owner] = states[owner] or {}
                return states[owner]
            end,
            OwnerKey = function(owner) return owner end,
            CanSkin = function() return true end,
            CatalogMode = function(mode) return type(mode) == "table" and mode or {} end,
            ApplyFrameNow = function(frame)
                genericPaints = genericPaints + 1
                Check(frame == itemReference, "shared tooltip went through generic traversal")
                return true
            end,
            DeactivateOwner = function() end,
        },
        SuiteOwnership = { EntrySurface = function() end },
        WindowControls = { TrackFocus = function(frame)
            Check(frame == itemReference, "shared tooltip registered with the window controls")
        end, DisableOwner = function() end },
        MacroWindow = { Disable = function() end },
        CatalogShopMotion = { Disable = function() end },
    }

    local core = { DB = {}, QoLVisualStyles = { [4] = {} }, Skin = { TooltipTheme = function() return ns end } }
    local function PrepareCore() return core end
    ns.SuiteCore = PrepareCore
    for _, path in ipairs({ "../MSUF_Suite/Appearance/Safety.lua", "../MSUF_Suite/Appearance/Cosmetics.lua", "Rendering/Geometry.lua", "Rendering/Surface.lua",
        "Adapters/Catalog.lua", "Adapters/CatalogGlass.lua", "../MSUF_Suite_Tooltips/TooltipChrome.lua",
        "Adapters/GenericWindowsCatalog.lua" }) do
        Load(ns, path)
    end
    local texturePath
    ns.Surface.MediaPath = function(role) if role == "background" then return texturePath end end
    ns.Surface.SetMediaTexture = function(texture)
        if owned[texture] then owned[texture].path = texturePath end
    end
    local paintPlan = ns.Surface.PrepareFill
    ns.Surface.PrepareFill = function(_, spec) return paintPlan(ns.Theme.GetMaterial("popup"), spec) end
    local generic = ns.GenericWindows
    local entries = {}
    for _, entry in ipairs(ns.BlizzardCatalog.entries) do entries[entry.id] = entry end
    local itemRef = entries["item-reference-tooltips"]
    Check(not entries["core-tooltips"] and itemRef, "native tooltip chrome still belongs to Skinning")
    local chrome = ns.TooltipChrome
    for _, frame in ipairs({ tooltip, embedded, mainCompare, linkCompare }) do
        Check(chrome.Apply(frame, "test"), "standalone tooltip did not acquire its native slice")
    end
    Check(type(styleHook) == "function" and SharedTooltip_SetBackdropStyle == nativeStyle,
        "native style function replaced or hook missing")
    Check(fill.rgba[1] == 0.12 and math.abs(fill.rgba[4] - 0.60) < 0.0001
        and embeddedFill.rgba[1] == 0.12, "popup palette/opacity missing on main or embedded")
    Check(edge.rgba[1] == 0.7 and edge.rgba[4] == 0.3, "border theme/opacity missing")

    local reads = materialReads
    nativeStyle(tooltip, fill, 0.17)
    nativeStyle(tooltip, fill, 0.18)
    Check(#timers == 1, "reused tooltip queued duplicate settlements")
    NextFrame()
    Check(fill.rgba[1] == 0.12 and #timers == 0, "style reset left the tooltip native or kept polling")
    Check(materialReads == reads, "a native style reset resolved immutable popup materials")
    ns.ItemTooltipCard = { HasVisibleHeader = function() return true end }
    nativeStyle(tooltip, fill, 0.19)
    Check(fill.rgba[1] == 0.12 and #timers == 0, "a visible card flashed native chrome before the next frame")
    local slice = tooltip.NineSlice
    Check(chrome.SetCardBacking(tooltip, "all") and slice:GetAlpha() == 0,
        "unified card still composites the native slice under its background")
    nativeStyle(tooltip, fill, 0.24)
    Check(fill.rgba[4] == 1 and slice:GetAlpha() == 0 and #timers == 0, "native color reset revealed the slice")
    Check(chrome.SetCardBacking(tooltip, "fill") and slice:GetAlpha() == 1 and not slice.Center:IsShown()
        and edge.rgba[4] == 0.3, "native border could not stay visible while its fill was hidden")
    slice.Center:Show()
    nativeStyle(tooltip, fill, 0.25)
    Check(not slice.Center:IsShown(), "native style could reveal the fill in Keep mode")
    local restoredAlpha = forever and .6 or 1
    Check(chrome.SetCardBacking(tooltip, nil) and slice.Center:IsShown()
        and math.abs(slice.Center:GetAlpha() - restoredAlpha) < .0001 and math.abs(fill.rgba[4] - 0.60) < 0.0001,
        "minimal style did not regain its own fill")
    ns.ItemTooltipCard = nil
    texturePath = "Background fixture"
    listeners[ns.TooltipChrome](nil, "tooltipMedia")
    NextFrame()
    local overlay, overlayPaint = next(owned)
    Check(overlay and overlay:IsShown() and not slice.Center:IsShown()
        and overlayPaint.path == texturePath and overlayPaint.anchor == slice.Center
        and edge.rgba[1] == 0.7, "custom background replaced the atlas layout or tinted the border")
    texturePath = nil
    listeners[ns.TooltipChrome](nil, "tooltipMedia")
    NextFrame()
    Check(not overlay:IsShown() and slice.Center:IsShown(), "reset did not restore the native center")
    local originalEdge = tooltip.NineSlice.TopEdge
    local replacement, replacementColors = Texture(0.3, 0.4, 0.5, 0.6)
    tooltip.NineSlice.TopEdge = replacement
    nativeStyle(tooltip, fill, 0.2)
    NextFrame()
    Check(replacementColors.rgba[1] == 0.7, "a replacement native edge kept the old handle")
    tooltip.NineSlice.TopEdge = originalEdge
    Check(chrome.TintEdge(tooltip, 0.26, 0.51, 0.92), "QoL border request no longer has a skin target")
    NextFrame()
    Check(edge.rgba[1] == 0.26 and edge.rgba[4] == 0.3, "quality/class color lost opacity")
    chrome.TintEdge(tooltip)
    NextFrame()
    Check(edge.rgba[1] == 0.7, "cleared quality/class color did not return to theme")

    ns.DB.theme.gradient = true
    ns.DB.geometry.border = 0
    listeners[ns.TooltipChrome](nil, "geometry")
    NextFrame()
    Check(fill.gradient[1] == "HORIZONTAL" and fill.gradient[2].r == 0.12 and fill.gradient[3].r < 0.12
        and edge.rgba[4] == 0, "gradient or border-off option was lost")

    slice:SetAlpha(.85)
    Check(chrome.SetCardBacking(tooltip, "all") and slice:GetAlpha() == 0,
        "unified card failed to suppress the native gradient")
    addonLoaded = true
    generic.ApplyEntry(itemRef, "test")
    Check(genericPaints == 0, "Skinning repainted the pinned Tooltip module surface")
    Check(mainCompareFill.gradient[2].r == .12 and linkCompareFill.gradient[2].r == .12
        and chrome.IsActive(mainCompare) and chrome.IsActive(linkCompare), "a comparison retained different chrome")
    nativeStyle(tooltip, fill, 0.22)
    chrome.DisableOwner("test")
    generic.Disable("test")
    NextFrame()
    Check(slice:GetAlpha() == .85 and slice.Center:IsShown(), "disable lost the native slice visibility or opacity")
    Check(fill.rgba[1] == 0.22 and fill.gradient[2].r == 1 and embeddedFill.rgba[1] == 0.15,
        "disable overwrote the latest native style or left a gradient")
    Check(edge.rgba[1] == 0.6 and edge.rgba[4] == 0.8, "disable left the native border tinted")
    Check(replacementColors.rgba[1] == 0.3 and replacementColors.rgba[4] == 0.6,
        "replacement native edge lost its own baseline color")
    nativeStyle(tooltip, fill, 0.23)
    Check(#timers == 0, "disabled shared tooltip still schedules work")
end

Test(false)
Test(true)
print("suite shared tooltip chrome contract: " .. checks .. " checks passed")
