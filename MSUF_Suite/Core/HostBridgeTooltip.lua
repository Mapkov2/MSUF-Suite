local _, Suite = ...
local HostBridge = Suite.HostBridge

local pendingTooltipPanel, tooltipPositioner, legacyTooltipHook, tooltipObserver
local modifierDown = { ALT = IsAltKeyDown, SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown }

function HostBridge.OwnsUnitFrameTooltip(tooltip)
    local owner = rawget(tooltip, "_msufUnitTooltipOwner")
    return Suite.Public(owner) and owner ~= nil
end

local function ObserveShownUnit(panel, unit, opts)
    if not tooltipObserver or not Suite.PublicText(unit) or panel._msufEditPreviewActive == true then return end
    local shown = panel:IsShown()
    if not Suite.Public(shown) or shown ~= true then return end
    local api = HostBridge.UnitFrameTooltipAPI()
    if not api then return end
    opts = Suite.Public(opts) and type(opts) == "table" and canaccesstable(opts) and opts or nil
    local provider = opts and opts.provider
    if not Suite.Public(provider) then return end
    if provider ~= "MSUF" and api.GetUnitFrameTooltipSetting("unitTooltipProvider") ~= "MSUF" then return end
    local exists = UnitExists(unit)
    if Suite.Public(exists) and not exists then return end
    local ignoreMode = opts and opts.ignoreMode
    if not Suite.Public(ignoreMode) then return end
    if ignoreMode ~= true then
        local mode = api.GetUnitFrameTooltipSetting("unitTooltipMode")
        if mode == "NEVER" or mode == "OOC" and Suite.InCombat() then return end
        if mode == "MODIFIER" then
            local modifier = api.GetUnitFrameTooltipSetting("unitTooltipModifier")
            if not Suite.PublicText(modifier) then return end
            local down = modifierDown[modifier]
            if not down or not down() then return end
        end
    end
    Suite.Dispatch(tooltipObserver, panel, unit)
end

local function OfferTooltipPanel(_, unit, opts)
    if not pendingTooltipPanel and not tooltipPositioner and not tooltipObserver then return end
    local panel = _G.MSUF_PlayerInfoFrame
    if not panel then return end
    if pendingTooltipPanel then
        local receive = pendingTooltipPanel
        pendingTooltipPanel = nil
        Suite.Dispatch(receive, panel)
    end
    if tooltipPositioner and panel._msufEditPreviewActive ~= true then
        local shown = panel:IsShown()
        if Suite.Public(shown) and shown == true then Suite.Dispatch(tooltipPositioner, panel) end
    end
    ObserveShownUnit(panel, unit, opts)
end

local function ObserveUnitTooltip()
    if legacyTooltipHook then return true end
    local namespace = HostBridge.Namespace()
    local tooltips = namespace and namespace.Tooltips
    if not tooltips or type(tooltips.ShowUnit) ~= "function" then return false end
    hooksecurefunc(tooltips, "ShowUnit", OfferTooltipPanel)
    legacyTooltipHook = true
    return true
end

function HostBridge.SetUnitFrameTooltipPanelObserver(observer)
    if observer == tooltipObserver then return true end
    if observer and not ObserveUnitTooltip() then return false end
    tooltipObserver = observer
    return true
end

function HostBridge.SetUnitFrameTooltipPanelPositioner(positioner)
    if not positioner then tooltipPositioner = nil return true end
    if not ObserveUnitTooltip() then return false end
    tooltipPositioner = positioner
    OfferTooltipPanel()
    return true
end

function HostBridge.SetLegacyUnitFrameTooltipPanelStyler(styler)
    -- Released 7.0 hosts before the panel callback use the same addon-owned
    -- frame. The host's hover entry point discovers it once, after creation.
    pendingTooltipPanel = styler
    if not styler then return true end
    OfferTooltipPanel()
    if not pendingTooltipPanel or ObserveUnitTooltip() then return true end
    pendingTooltipPanel = nil
    return false
end
