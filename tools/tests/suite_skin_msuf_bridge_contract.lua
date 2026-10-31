local retail = assert(arg[1], "Retail MSUF root required")
local classic = assert(arg[2], "Classic MSUF root required")

local function Check(root, motionPolicy)
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
    local appearance, stopped = {}, 0
    local api = {
        RegisterAddon = function()
            registrations = registrations + 1
            return client
        end,
        IsEnabled = function() return true end,
        GetAppearanceSnapshot = function() return appearance end,
        OnAppearanceChanged = function() end,
    }
    MapkoSkin = { migrationOnly = true, GetAPI = function() return api end }
    local host = { UI = { colors = {} } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua"))(
        "MidnightSimpleUnitFrames", host)
    if motionPolicy then eventFrame.script(eventFrame, "PLAYER_LOGIN") end
    assert(eventFrame and eventFrame.events.ADDON_LOADED and registrations == 0,
        "MSUF connected to the data-only legacy bridge")
    eventFrame.script(eventFrame, "ADDON_LOADED", "MapkoSkin")
    assert(registrations == 0 and eventFrame.events.ADDON_LOADED,
        "Legacy migration consumed MSUF's skin-provider watcher")
    MapkoSkin = { addonName = "MSUF_Suite_Skin", GetAPI = function() return api end }
    eventFrame.script(eventFrame, "ADDON_LOADED", "MSUF_Suite_Skin")
    assert(registrations == 1 and not eventFrame.events.ADDON_LOADED and host.MenuSkin.IsActive(),
        "MSUF did not connect to the Suite-owned skin engine")
    if motionPolicy then
        host.MSUF2 = { Theme = { StopAllMenuAnimations = function() stopped = stopped + 1 end } }
        assert(not host.MenuSkin.MotionReduced(), "unset suite flags disabled Core motion")
        appearance.menuAnimations = false
        assert(not host.MenuSkin.ScrollMotionReduced(), "decorative animation off disabled independent smooth scrolling")
        host.MenuSkin.Refresh(nil, "motion", "menuAnimations")
        assert(host.MenuSkin.MotionReduced() and stopped == 1, "Suite animation off did not stop Core menu groups")
        appearance.menuAnimations, appearance.reduceMotion = true, true
        host.MenuSkin.Refresh(nil, "motion", "reduceMotion")
        assert(host.MenuSkin.MotionReduced() and stopped == 2, "Suite reduced motion did not stop Core menu groups")
        appearance.reduceMotion = false
        host.MenuSkin.Refresh(nil, "motion", "reduceMotion")
        assert(not host.MenuSkin.MotionReduced(), "explicit false reduced-motion flag was lost")
        appearance.smoothScrolling = false
        host.MenuSkin.Refresh(nil, "motion", "smoothScrolling")
        assert(host.MenuSkin.ScrollMotionReduced() and not host.MenuSkin.MotionReduced(),
            "smooth scrolling off did not remain independent of decorative motion")
    end
end

Check(retail)
Check(classic)
Check(assert(arg[3], "MSUF 7.0 root required"), true)
-- Exercise both real dropdown scroll paths with the independent scroll policy.
do
    local root = assert(arg[3])
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Dropdowns.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local at = assert(source:find("\nIsDescendantOf = function", 1, true))
    local probe = [[
        dropdownFrame = { IsShown = function() return true end,
            _msuf2SmoothScrollDriver = { Hide = function() end, Show = function() end } }
        dropdownChild = { GetHeight = function() return 1000 end }
        dropdownScroll = { offset = 0, GetHeight = function() return 100 end,
            GetVerticalScroll = function(self) return self.offset end,
            SetVerticalScroll = function(self, value) self.offset = value end }
        SmoothDropdownScrollTo(100)
        assert(dropdownScroll.offset == 100, "Suite smoothing off left dropdown scroll active")
        dropdownScroll.offset, dropdownScroll._msuf2SmoothScrollTarget = 0, 100
        DropdownSmoothScrollOnUpdate(nil, 0.016)
        assert(dropdownScroll.offset == 100, "in-flight dropdown scroll ignored smoothing off")
    ]]
    local namespace = { Client = {}, MSUF2 = { Theme = {
        ReducedMotionEnabled = function(scrolling) return scrolling == true end } } }
    local providers = { MSUF_PixelLayoutRegion = function(region) return region end }
    local function Unused(name)
        return function() error("scroll probe unexpectedly called " .. name) end
    end
    for _, name in ipairs({ "MSUF_SetFontChecked", "MSUF_SetIconTexture", "MSUF_ResolveSafeFontPath", "MSUF_ResolveFontKeyPath" }) do
        providers[name] = Unused(name)
    end
    function namespace.Require(name) return assert(providers[name], name) end
    function namespace.Optional(name)
        assert(name == "MSUF_ResolveStatusbarTextureKey", name)
        return nil
    end
    assert(loadstring(source:sub(1, at - 1) .. "\n" .. probe))("MidnightSimpleUnitFrames", namespace)
end
print("MSUF skin bridges: migration/login, provider handoff and independent 7.0 motion/scroll policy passed")
