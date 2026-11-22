local _, private = ...
local Suite = assert(_G.MSUFSuite, "MSUF_Suite is required")
private.NS, private.Suite = Suite, Suite.Suite

local appearance = Suite.AppearancePrimitives
private.Safety, private.Cosmetics, private.CombatGate = appearance.Safety, appearance.Cosmetics, appearance.CombatGate.Initialize()
private.IsCombatLocked, private.CopyValue = appearance.IsCombatLocked, Suite.CopyValue
private.SuiteCore = function() return Suite end
private.Defaults = { theme = Suite.TooltipAppearance.defaults }

local listeners = {}
local Registry = {}
private.Registry = Registry
function Registry.AddListener(owner, callback) listeners[owner] = callback end
function Registry.NotifyListeners(domain, field)
    if private.IsCombatLocked() then return false end
    if domain == "tooltipStyle" then private.MarkConfigured() end
    private.Surface.RefreshMedia()
    for owner, callback in pairs(listeners) do Suite.Dispatch(callback, owner, domain, field) end
    if private.Surface then private.Surface.RefreshAll() end
    if domain == "tooltipStyle" and (field == "borderMode" or field == "borderColor" or field == "preset") then
        Suite.Skin.TooltipAppearanceChanged()
    end
    return true
end
