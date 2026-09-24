local retail = assert(arg[1], "Retail MSUF root required")
local classic = assert(arg[2], "Classic MSUF root required")

local function Check(root)
    local eventFrame, registrations = nil, 0
    local client = { ReleaseAll = function() end }
    CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, script) self.script = script end
        eventFrame = frame
        return frame
    end
    hooksecurefunc = function() end
    InCombatLockdown = function() return false end
    MSUF_DB = { general = {} }
    local api = {
        RegisterAddon = function()
            registrations = registrations + 1
            return client
        end,
        IsEnabled = function() return true end,
        GetAppearanceSnapshot = function() return {} end,
        OnAppearanceChanged = function() end,
    }
    MapkoSkin = { migrationOnly = true, GetAPI = function() return api end }
    local host = { UI = { colors = {} } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua"))(
        "MidnightSimpleUnitFrames", host)
    assert(eventFrame and eventFrame.events.ADDON_LOADED and registrations == 0,
        "MSUF connected to the data-only legacy bridge")
    eventFrame.script(eventFrame, "ADDON_LOADED", "MapkoSkin")
    assert(registrations == 0 and eventFrame.events.ADDON_LOADED,
        "Legacy migration consumed MSUF's skin-provider watcher")
    MapkoSkin = { addonName = "MSUF_Suite_Skin", GetAPI = function() return api end }
    eventFrame.script(eventFrame, "ADDON_LOADED", "MSUF_Suite_Skin")
    assert(registrations == 1 and not eventFrame.events.ADDON_LOADED and host.MenuSkin.IsActive(),
        "MSUF did not connect to the Suite-owned skin engine")
end

Check(retail)
Check(classic)
print("MSUF Retail and Forever skin bridges: migration isolation and Suite provider handoff passed")
