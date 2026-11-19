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
        local values = { rgba = { r, g, b, a } }
        local region = NativeObject({
            GetVertexColor = function() return unpack(values.rgba) end,
            SetVertexColor = function(_, ...) NoNativeWrite(); values.rgba = { ... } end,
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
        local frame = NativeObject({
            NineSlice = NativeObject({ Center = center, TopEdge = border }),
            IsForbidden = function(self) return flags[self] == "forbidden" end,
            IsProtected = function(self) return flags[self] == "protected", flags[self] == "protected" end,
        })
        return frame, fill, edge
    end

    local tooltip, fill, edge = Tooltip()
    local embedded, embeddedFill = Tooltip()
    local itemReference = Tooltip()
    GameTooltip, EmbeddedItemTooltip, ItemRefTooltip = tooltip, embedded, itemReference
    GameNoHeaderTooltip, ShoppingTooltip1, ShoppingTooltip2 = nil, nil, nil
    GameSmallHeaderTooltip = Tooltip()
    flags[GameSmallHeaderTooltip] = "forbidden"

    nativeStyle = function(frame, values, red)
        building = true
        values.rgba = { red, 0.08, 0.09, 1 }
        if styleHook then styleHook(frame) end
        Check(values.rgba[1] == red, "post-hook painted before native widgets finished")
        building = false
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
    local ns = {
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
            ReuseColor = function(_, ...) return Color(...) end,
        },
        AdapterKit = {
            CancelDeferred = function() end,
            DeferHidden = function() return false end,
            Isolate = function(callback, ...) callback(...); return true end,
        },
        GenericWindows = {},
        GenericWindowsShared = {
            DEFAULT_OWNER = "generic",
            OwnerState = function(owner)
                states[owner] = states[owner] or {}
                return states[owner]
            end,
            OwnerKey = function(owner) return owner end,
            CanSkin = function() return true end,
            CatalogMode = function(mode) return mode end,
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
    }

    for _, path in ipairs({ "Core/Safety.lua", "Rendering/Geometry.lua", "Rendering/Surface.lua",
        "Adapters/Catalog.lua", "Adapters/CatalogGlass.lua", "Adapters/TooltipChrome.lua",
        "Adapters/GenericWindowsCatalog.lua" }) do
        Load(ns, path)
    end
    local generic = ns.GenericWindows
    local entries = {}
    for _, entry in ipairs(ns.BlizzardCatalog.entries) do entries[entry.id] = entry end
    local shared, itemRef = entries["core-tooltips"], entries["item-reference-tooltips"]
    Check(shared and itemRef, "native tooltip catalog roots disappeared")
    generic.ApplyEntry(shared, "test")
    Check(generic.GetStatus(shared.id) == "waiting" and styleHook == nil,
        "tooltip skin installed before the native addon loaded")
    addonLoaded = true
    frames[1].OnEvent(frames[1], "ADDON_LOADED", "Blizzard_GameTooltip")
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
    local originalEdge = tooltip.NineSlice.TopEdge
    local replacement, replacementColors = Texture(0.3, 0.4, 0.5, 0.6)
    tooltip.NineSlice.TopEdge = replacement
    nativeStyle(tooltip, fill, 0.2)
    NextFrame()
    Check(replacementColors.rgba[1] == 0.7, "a replacement native edge kept the old handle")
    tooltip.NineSlice.TopEdge = originalEdge
    Check(ns.Surface.TintEdge(tooltip, 0.26, 0.51, 0.92), "QoL border request no longer has a skin target")
    NextFrame()
    Check(edge.rgba[1] == 0.26 and edge.rgba[4] == 0.3, "quality/class color lost opacity")
    ns.Surface.TintEdge(tooltip)
    NextFrame()
    Check(edge.rgba[1] == 0.7, "cleared quality/class color did not return to theme")

    ns.DB.theme.gradient = true
    ns.DB.geometry.border = 0
    listeners[ns.TooltipChrome](nil, "geometry")
    NextFrame()
    Check(fill.gradient[1] == "HORIZONTAL" and fill.gradient[2].r == 0.12 and fill.gradient[3].r < 0.12
        and edge.rgba[4] == 0, "gradient or border-off option was lost")

    generic.ApplyEntry(itemRef, "test")
    Check(genericPaints == 1, "unrelated item-reference tooltip was redirected")
    nativeStyle(tooltip, fill, 0.22)
    generic.Disable("test")
    NextFrame()
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
