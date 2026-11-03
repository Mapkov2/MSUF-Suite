-- Reproduce the live render-layer failure through the real focus controller.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_window_focus_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find('    local a = Native("CharacterFrame"', 1, true))
local body = [======[
    Load("Adapters/CatalogGlass.lua")
    UIPanelWindows.PVEFrame, UIPanelWindows.CommunitiesFrame = { area = "left" }, { area = "left" }
    local pve = Native("PVEFrame", 100, 100, 563, 428)
    local communities = Native("CommunitiesFrame", 400, 150, 810, 424)
    -- Native templates can own HIGH content below the bounded root sample.
    -- RaidFinder.NoRaidsCover and SharedXML.TemplatedList.ArtOverlay are HIGH.
    -- This opaque pixel models the live A/B: MEDIUM530 was behind content,
    -- changing only the owned veil to DIALOG made it visibly dim.
    local parent, content = pve
    for index = 1, 6 do
        local child = Native("NativeLayerNode" .. index, 100, 100, 563, 428)
        child.parent = parent
        parent.GetChildren = function() return child end
        parent, content = child, child
    end
    content.strata = "HIGH"
    local ranks = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
        FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    local function Brightness(x, y, nativeLayer, nativeLevel)
        local value = 1
        for _, veil in ipairs(veils) do
            local rect, overlay = veil.rect, veil.overlay
            local rank, layer = ranks[overlay:GetFrameStrata()], ranks[nativeLayer]
            local above = rank > layer or rank == layer and overlay:GetFrameLevel() > nativeLevel
            if veil.dim and above and x > rect.left and x < rect.left + rect.width
                and y > rect.bottom and y < rect.bottom + rect.height then value = value * 0.58 end
        end
        return value
    end
    pve.protected, pve.explicitProtected = true, true
    communities.protected, communities.explicitProtected = true, true
    _G.combat, _G.combatEdge = true, true
    W.TrackFocus(pve, "layers")
    W.TrackFocus(communities, "layers")
    Tick()
    Check(Brightness(200, 300, content:GetFrameStrata(), content:GetFrameLevel()) < 0.8,
        "visible full-alpha veil remained below an opaque native window layer")
    Check(Brightness(500, 300, communities:GetFrameStrata(), communities:GetFrameLevel()) == 1,
        "elevated inactive veil shaded the active window")
    Check(not pve.geometryWrites and not communities.geometryWrites and content.strata == "HIGH",
        "render-layer correction wrote protected native geometry or strata")
    Check(F.records[pve].rank == 3 and F.records[pve].strata == "MEDIUM",
        "paint elevation overwrote native ordering metadata")
    Click(pve); Tick()
    Check(Brightness(800, 300, "MEDIUM", 1) < 0.8 and Brightness(200, 300, "HIGH", 1) == 1,
        "elevated rendering lost focus reversal")
    local nativeHigh = Native("CharacterFrame", 200, 200, 400, 300)
    nativeHigh.strata = "HIGH"
    W.TrackFocus(nativeHigh, "layers")
    Click(communities); Tick()
    Check(NS.WindowFocusGeometry.Above(F.records[nativeHigh], F.records[pve]),
        "shared paint floor lost the native HIGH-over-MEDIUM order")
    for _, veil in ipairs(F.records[pve].veils) do
        Check(not veil.dim or not Intersects(veil.rect, F.records[nativeHigh].rect),
            "elevated lower window double-dimmed a higher inactive native window")
    end
    nativeHigh.strata = "FULLSCREEN_DIALOG"
    nativeHigh:Raise(); Tick()
    Check(Brightness(300, 300, "TOOLTIP", 1) == 1,
        "already high native window was needlessly elevated over a tooltip")
    local tooltip = Native("ScriptErrorsFrame", 1400, 100, 400, 300)
    tooltip.strata, tooltip.frameLevel = "TOOLTIP", 4000
    W.TrackFocus(tooltip, "layers")
    Click(communities); Tick()
    Check(Brightness(1500, 200, "TOOLTIP", 4000) < 0.8,
        "already higher native windows lost their effective render level")
    pve:Hide(); communities:Hide(); nativeHigh:Hide(); tooltip:Hide()
    Check(not driver.events.GLOBAL_MOUSE_DOWN and not driver.events.GLOBAL_MOUSE_UP and not driver.scripts.OnUpdate,
        "elevated render policy retained closed-window work")
end
print("suite_window_focus_layers_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@native_layer_focus_fixture"))()
