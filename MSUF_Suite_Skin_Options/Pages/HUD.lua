local _, Private = ...
local NS, O = Private.NS, Private.Options

local function SetHUD(key, value, adapter)
    if NS.IsCombatLocked() then return end
    NS.DB.hud[key] = value == true
    NS.Adapters.Refresh(adapter)
    NS.Registry.NotifyListeners("hud", key)
end

local function Toggle(parent, label, key, adapter, anchor, relative, width)
    local toggle = O.CreateToggle(parent, label, function()
        return NS.DB.hud[key]
    end, function(value)
        SetHUD(key, value, adapter)
    end, width or 370)
    if relative then
        toggle:SetPoint("TOPLEFT", relative, "BOTTOMLEFT", 0, -8)
    else
        toggle:SetPoint("TOPLEFT", anchor[1], anchor[2])
    end
    return toggle
end

O.RegisterPage("hud", NS.L.HUD, function(page)
    O.CreateSectionTitle(page, "Blizzard HUD", "Skin high-visibility HUD surfaces while Blizzard keeps positioning, data and actions.")

    local meter = O.CreatePanel(page, "card")
    meter:SetPoint("TOPLEFT", 4, -70)
    meter:SetPoint("TOPRIGHT", -4, -70)
    meter:SetHeight(274)
    local meterTitle = O.CreateText(meter, "BLIZZARD DAMAGE METER", 12, "accent")
    meterTitle:SetPoint("TOPLEFT", 14, -14)
    local meterText = O.CreateText(meter, "Class colors, values, icons and click actions stay native.", 11, "muted")
    meterText:SetPoint("TOPLEFT", meterTitle, "BOTTOMLEFT", 0, -7)
    meterText:SetPoint("RIGHT", -12, 0)

    local meterWindows = Toggle(meter, "Window and header surfaces", "damageMeterWindows", "damageMeter", { 10, -70 }, nil, 356)
    local meterRows = Toggle(meter, "Class-colored row plates", "damageMeterRows", "damageMeter", nil, meterWindows, 356)
    Toggle(meter, "Source detail window", "damageMeterDetails", "damageMeter", nil, meterRows, 356)

    local note = O.CreatePanel(page, "navigation")
    note:SetPoint("TOPLEFT", meter, "BOTTOMLEFT", 0, -12)
    note:SetPoint("BOTTOMRIGHT", -4, 4)
    local noteTitle = O.CreateText(note, "COMBAT-SAFE COVERAGE", 11, "success")
    noteTitle:SetPoint("TOPLEFT", 16, -16)
    local noteText = O.CreateText(note,
        "Static HUD surfaces are compiled out of combat. Dynamic meter rows never trigger skin mutations or queued work during combat. Newly opened secondary meter windows can be picked up safely with /mskin refresh outside combat.",
        12, "text")
    noteText:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -10)
    noteText:SetPoint("RIGHT", -16, 0)
    noteText:SetJustifyV("TOP")
end)
