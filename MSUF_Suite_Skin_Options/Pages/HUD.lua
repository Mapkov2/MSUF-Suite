local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local METER_TOGGLES = {
    { L["Window and header surfaces"], "damageMeterWindows" },
    { L["Class-colored row plates"], "damageMeterRows" },
    { L["Source detail window"], "damageMeterDetails" },
}

local function SetHUD(key, value, adapter)
    if NS.IsCombatLocked() then return end
    NS.DB.hud[key] = value == true
    NS.Adapters.Refresh(adapter)
    NS.Registry.NotifyListeners("hud", key)
end

local function BuildMeterCard(page)
    local meter = O.CreatePanel(page, "card")
    meter:SetPoint("TOPLEFT", 4, -70)
    meter:SetPoint("TOPRIGHT", -4, -70)
    meter:SetHeight(274)
    local meterTitle = O.CreateText(meter, L["BLIZZARD DAMAGE METER"], 12, "accent")
    meterTitle:SetPoint("TOPLEFT", 14, -14)
    local meterText = O.CreateText(meter, L["Class colors, values, icons and click actions stay native."], 11, "muted")
    meterText:SetPoint("TOPLEFT", meterTitle, "BOTTOMLEFT", 0, -7)
    meterText:SetPoint("RIGHT", -12, 0)

    local previous
    for index = 1, #METER_TOGGLES do
        local key = METER_TOGGLES[index][2]
        local toggle = O.CreateToggle(meter, METER_TOGGLES[index][1], function()
            return NS.DB.hud[key]
        end, function(value)
            SetHUD(key, value, "damageMeter")
        end, 356)
        if previous then
            toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        else
            toggle:SetPoint("TOPLEFT", 10, -70)
        end
        previous = toggle
    end
    return meter
end

local function BuildCombatNote(page, meter)
    local note = O.CreatePanel(page, "navigation")
    note:SetPoint("TOPLEFT", meter, "BOTTOMLEFT", 0, -12)
    note:SetPoint("BOTTOMRIGHT", -4, 4)
    local noteTitle = O.CreateText(note, L["COMBAT-SAFE COVERAGE"], 11, "success")
    noteTitle:SetPoint("TOPLEFT", 16, -16)
    local noteText = O.CreateText(note,
        L["Static HUD surfaces are compiled out of combat. Dynamic meter rows never trigger skin mutations or queued work during combat. Newly opened secondary meter windows can be picked up safely with /mskin refresh outside combat."],
        12, "text")
    noteText:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -10)
    noteText:SetPoint("RIGHT", -16, 0)
    noteText:SetJustifyV("TOP")
end

O.RegisterPage("hud", NS.L.HUD, function(page)
    O.CreateSectionTitle(page, L["Blizzard HUD"],
        L["Skin high-visibility HUD surfaces while Blizzard keeps positioning, data and actions."])
    BuildCombatNote(page, BuildMeterCard(page))
end)
