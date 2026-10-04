local _, NS = ...

-- The Suite supports Retail and WoW Forever. Both load the Mainline TOC, so
-- C_AddOns and C_EventUtils always exist. Forever runs the Mainline engine
-- with a Camelot game layer; GameEvent.RegisterCamelotEvents identifies it
-- (Blizzard_Game/Camelot/EventRouting.lua in the forever branch).
local AddOns = C_AddOns
local forever = type(GameEvent) == "table" and type(GameEvent.RegisterCamelotEvents) == "function"
local mainline = forever or (WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

NS.Client = {
    flavor = forever and "Forever" or mainline and "Mainline" or "Unknown",
    isForever = forever,
    isMainline = mainline,
    -- Modern equipment annotations contain Retail-specific upgrade/rating
    -- contracts. Forever retains its native character layout and skin.
    modernEquipment = mainline and not forever,
}

-- C_AddOns.IsAddOnLoaded returns loadedOrLoading, loaded.
function NS.Client.IsAddOnLoaded(name)
    local _, loaded = AddOns.IsAddOnLoaded(name)
    return loaded == true
end

-- True when the addon is installed, loaded or not.
function NS.Client.HasAddOn(name)
    return AddOns.DoesAddOnExist(name) == true
end

function NS.Client.SupportsEvent(event)
    return C_EventUtils.IsEventValid(event) == true
end

-- WoW Forever's Gamepad UI. Its frame controls manager follows every panel the
-- panel manager shows or hides (UIParentPanelManager.ShowUIPanel/HideUIPanel
-- events in the forever branch), in the caller's context: driven from here,
-- its binding state stays tainted and SetPreferredGamepadInteractTarget is
-- blocked. The skin then leaves the panel manager to Blizzard.
-- Forever's Mainline InputUtil always defines IsGamepadUIEnabled.
function NS.Client.IsGamepadUI()
    return forever and InputUtil.IsGamepadUIEnabled() == true
end
