local _, NS = ...

local OPTIONS_ADDON = "MSUF_Suite_Skin_Options"

function NS.EnsureOptionsLoaded()
    if NS.IsCombatLocked() then
        NS.Print(NS.L.OPEN_BLOCKED_COMBAT)
        return false
    end

    if not NS.Client.IsAddOnLoaded(OPTIONS_ADDON) then
        local loaded, reason = C_AddOns.LoadAddOn(OPTIONS_ADDON)
        if not loaded and not NS.OptionsReady and not NS.Client.IsAddOnLoaded(OPTIONS_ADDON) then
            NS.Print(NS.L.LOAD_OPTIONS_FAILED:format(tostring(reason or "unknown")))
            return false
        end
    end

    -- The options are a separate load-on-demand addon: disabled, failed to
    -- load or older, it may lack its namespace or entry points.
    if not NS.OptionsReady or not NS.Options or type(NS.Options.Open) ~= "function" then
        NS.Print(NS.L.OPTIONS_NOT_READY)
        return false
    end
    return true
end

-- The Suite menu owns the Skinning page; the standalone window is the
-- fallback when the MSUF menu cannot open it.
function NS.OpenOptions()
    local suite = _G.MSUFSuite
    if suite and suite.Menu and type(suite.Menu.Open) == "function"
        and suite.Menu.Open("suite_skin") then
        return true
    end
    if not NS.EnsureOptionsLoaded() then return false end
    return NS.Options.Open()
end

function NS.MountOptions(parent, width, height)
    if not NS.EnsureOptionsLoaded() or not NS.Options.Mount then return nil end
    return NS.Options.Mount(parent, width, height)
end
