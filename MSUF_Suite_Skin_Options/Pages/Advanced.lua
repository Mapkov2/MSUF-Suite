local _, Private = ...
local NS, O = Private.NS, Private.Options

O.RegisterPage("advanced", NS.L.ADVANCED, function(page)
    O.CreateSectionTitle(page, "Runtime contract", "The engine remains dormant until a lifecycle event or an explicit user action requires work.")

    local contract = O.CreatePanel(page, "card")
    contract:SetPoint("TOPLEFT", 4, -70)
    contract:SetPoint("TOPRIGHT", -4, -70)
    contract:SetHeight(254)

    local title = O.CreateText(contract, "COMBAT-QUIESCENT BY DESIGN", 12, "success")
    title:SetPoint("TOPLEFT", 16, -16)
    local body = O.CreateText(contract,
        "• No OnUpdate handlers\n• No tickers or timers\n• No global frame enumeration\n• No combat, unit, aura or nameplate listeners\n• One temporary PLAYER_REGEN_ENABLED listener only when a requested job must be deferred\n• One shared ADDON_LOADED dispatcher only while catalog targets are pending\n• External weak-key runtime state",
        13, "text")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    body:SetPoint("RIGHT", -18, 0)
    body:SetJustifyV("TOP")

    local api = O.CreatePanel(page, "navigation")
    api:SetPoint("TOPLEFT", contract, "BOTTOMLEFT", 0, -12)
    api:SetPoint("TOPRIGHT", contract, "BOTTOMRIGHT", 0, -12)
    api:SetHeight(146)
    local apiTitle = O.CreateText(api, "PUBLIC API", 11, "accent")
    apiTitle:SetPoint("TOPLEFT", 16, -16)
    local apiText = O.CreateText(api,
        "API version " .. tostring(NS.apiVersion) .. "\nSurface(frame, options)\nOwnedButton(button, options)\nGetColor(token) / GetLook()\nOnThemeChanged(owner, callback)",
        12, "muted")
    apiText:SetPoint("TOPLEFT", apiTitle, "BOTTOMLEFT", 0, -9)
    apiText:SetJustifyV("TOP")

    local resetArmed = false
    local reset
    reset = O.CreateButton(page, NS.L.RESET_ALL, 190, 28, function()
        if NS.IsCombatLocked() then return end
        if not resetArmed then
            resetArmed = true
            local state = O.widgetStates[reset]
            if state and state.label then state.label:SetText("Confirm factory reset") end
            return
        end
        local began = O.BeginUserChange(NS.L.RESET_ALL)
        NS.Database.ResetAll()
        NS.Typography.ApplyConfigured()
        NS.Adapters.ApplyAll()
        NS.Registry.RefreshAll()
        NS.Registry.NotifyListeners("theme", "reset")
        if began then O.CommitUserChange(NS.L.RESET_ALL) end
        resetArmed = false
        local state = O.widgetStates[reset]
        if state and state.label then state.label:SetText(NS.L.RESET_ALL) end
    end, "buttonPrimary")
    reset:SetPoint("BOTTOMRIGHT", -4, 4)

    local pending = O.CreateText(page, "", 11, "dim")
    pending:SetPoint("BOTTOMLEFT", 4, 12)
    O.TrackRefresh(function()
        pending:SetText("Deferred jobs: " .. tostring(NS.CombatGate.GetPendingCount()) .. "   |   Engine " .. NS.version)
    end)
end)
