local _, Suite = ...
-- The suite's pages live in the load-on-demand MSUF_Suite_Options addon. It is
-- loaded right after MSUF's own options addon (Main and Classic builds use the
-- same name and the same public Menu2 table), so no MSUF file carries suite code.
local Menu = {}
Suite.Menu = Menu
local HOST_OPTIONS = "MidnightSimpleUnitFrames_Options"
local SUITE_OPTIONS = "MSUF_Suite_Options"
local watcher

local function LoadAddOnByName(name)
    local loader = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if type(loader) ~= "function" then return false, "LoadAddOn unavailable" end
    local loaded, reason = loader(name)
    return Suite.Client.IsAddOnLoaded(name) or loaded == true, reason
end

-- Registers the suite pages once MSUF's Menu2 exists. Returns true when the
-- pages are (or already were) registered.
function Menu.Attach()
    if Menu.attached then return true end
    if not Suite.Client.IsAddOnLoaded(HOST_OPTIONS) then return false end
    if not Suite.Client.IsAddOnLoaded(SUITE_OPTIONS) then
        local ok, reason = LoadAddOnByName(SUITE_OPTIONS)
        if not ok then
            Menu.error = tostring(reason or "not loaded")
            Suite.Print("Enable MSUF Suite Options in the AddOns list (" .. Menu.error .. ").")
            return false
        end
    end
    -- MSUF_Suite_Options sets Menu.attached when its registration completed.
    return Menu.attached == true
end

local function OnEvent(frame, _, name)
    if name ~= HOST_OPTIONS then return end
    frame:UnregisterEvent("ADDON_LOADED")
    Menu.Attach()
end

-- Called from startup. Allocates the watcher only while MSUF's options are
-- still unloaded; it unregisters itself on the first matching ADDON_LOADED.
function Menu.Watch()
    if Menu.Attach() or watcher then return end
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", OnEvent)
    watcher:RegisterEvent("ADDON_LOADED")
end

-- Opens a suite page through MSUF's public menu entry point. MSUF's facade
-- loads its options addon on demand, which in turn attaches the suite pages.
function Menu.Open(page)
    if Suite.IsCombatLocked() then return false end
    local open = _G.MSUF2_Open
    if type(open) ~= "function" then return false end
    if Suite.Client.IsAddOnLoaded(HOST_OPTIONS) and not Menu.Attach() then return false end
    open(page or "suite_actionbars")
    return true
end
