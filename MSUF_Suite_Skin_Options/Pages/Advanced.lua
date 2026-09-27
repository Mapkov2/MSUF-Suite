local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local function BuildRuntimeContract(page)
    local contract = O.CreatePanel(page, "card")
    contract:SetPoint("TOPLEFT", 4, -70)
    contract:SetPoint("TOPRIGHT", -4, -70)
    contract:SetHeight(254)

    local title = O.CreateText(contract, L["COMBAT-QUIESCENT BY DESIGN"], 12, "success")
    title:SetPoint("TOPLEFT", 16, -16)
    -- The engine's actual runtime footprint: the window corner drag is its only
    -- OnUpdate (removed on release), timers are one-shot, and unit events
    -- serve only the Micro Bar portrait and open character panels.
    local body = O.CreateText(contract,
        L["• No idle OnUpdate; a window corner drag runs one only while the mouse button is held\n• No repeating tickers; short one-shot timers only batch layout and hover updates\n• No global frame enumeration\n• No aura or nameplate listeners; unit events only for the Micro Bar portrait and open character panels\n• Combat-state events only pause and resume deferred work and close open option popups\n• One shared ADDON_LOADED dispatcher only while catalog targets are pending\n• External weak-key runtime state"],
        13, "text")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    body:SetPoint("RIGHT", -18, 0)
    body:SetJustifyV("TOP")
    return contract
end

local function BuildPublicAPI(page, contract)
    local api = O.CreatePanel(page, "navigation")
    api:SetPoint("TOPLEFT", contract, "BOTTOMLEFT", 0, -12)
    api:SetPoint("TOPRIGHT", contract, "BOTTOMRIGHT", 0, -12)
    api:SetHeight(146)
    local apiTitle = O.CreateText(api, L["PUBLIC API"], 11, "accent")
    apiTitle:SetPoint("TOPLEFT", 16, -16)
    local apiText = O.CreateText(api,
        L["API version %s"]:format(tostring(NS.apiVersion))
            .. "\nSurface(frame, options)\nOwnedButton(button, options)\nGetColor(token) / GetLook()\nOnThemeChanged(owner, callback)",
        12, "muted")
    apiText:SetPoint("TOPLEFT", apiTitle, "BOTTOMLEFT", 0, -9)
    apiText:SetJustifyV("TOP")
end

-- The first click arms the reset and relabels the button; a second click
-- within ARM_SECONDS resets. An arm expires on its own, so a much later click
-- arms again instead of resetting the profile.
local ARM_SECONDS = 5

local function BuildFactoryReset(page)
    -- The number of the pending arm, nil when disarmed: a one-shot expiry
    -- timer ends only the arm it was started for.
    local armed
    local arms = 0
    local reset
    local function SetResetLabel(text)
        O.widgetStates[reset].label:SetText(text)
    end
    local function Disarm()
        armed = nil
        SetResetLabel(NS.L.RESET_ALL)
    end
    reset = O.CreateSettingButton(page, NS.L.RESET_ALL, 190, 28, function()
        if not armed then
            arms = arms + 1
            local arm = arms
            armed = arm
            SetResetLabel(L["Confirm factory reset"])
            C_Timer.After(ARM_SECONDS, function()
                if armed == arm then Disarm() end
            end)
            return
        end
        Disarm()
        local began = O.BeginUserChange(NS.L.RESET_ALL)
        -- The factory profile is applied like a profile switch, stage by stage
        -- (Database.ApplyActiveSettings). Every stage, the reset itself too, is
        -- its own boundary: one that raises is reported, and the later stages,
        -- the listeners and the history still finish.
        NS.Safety.Dispatch(NS.Database.ResetAll)
        NS.Database.ApplyActiveSettings("reset", "theme")
        if began then O.CommitUserChange(NS.L.RESET_ALL) end
    end, "buttonPrimary")
    reset:SetPoint("BOTTOMRIGHT", -4, 4)
end

O.RegisterPage("advanced", NS.L.ADVANCED, function(page)
    O.CreateSectionTitle(page, L["Runtime contract"],
        L["The engine remains dormant until a lifecycle event or an explicit user action requires work."])
    BuildPublicAPI(page, BuildRuntimeContract(page))
    BuildFactoryReset(page)

    local pending = O.CreateText(page, "", 11, "dim")
    pending:SetPoint("BOTTOMLEFT", 4, 12)
    O.TrackRefresh(function()
        pending:SetText(L["Deferred jobs: %s   |   Engine %s"]:format(
            tostring(NS.CombatGate.GetPendingCount()), NS.version))
    end)
end)
