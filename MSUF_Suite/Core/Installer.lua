local _, Suite = ...

local Installer = {}
Suite.Installer = Installer
local DB = Suite.Database
local selected = "suite"
local useRaidEssentials = true
local useScale = false
local scale = 1
local scalePreset = "custom"
local page = 1
local frame
local moduleOverrides = { suite = {}, forever = {} }

-- Installer texts follow the Suite localization: English source strings
-- looked up in MSUF's locale table. That table has no installer strings yet,
-- so their reviewed German wording stays here and German clients keep it.
local GERMAN = {
    ["Finish combat first."] = "Bitte zuerst den Kampf beenden.",
    ["INSTALLATION"] = "INSTALLATION",
    ["1. Choose a profile"] = "1. Profil wählen",
    ["Modern keeps your MSUF frames. Forever installs the full factory profile."] = "Modern behält deine MSUF-Frames. Forever installiert das komplette Factory-Profil.",
    ["2. Select modules"] = "2. Module auswählen",
    ["Keep the profile defaults or switch individual Suite modules on or off."] = "Übernimm die Profilwerte oder schalte einzelne Suite-Module an oder aus.",
    ["3. Set UI scale"] = "3. UI-Skalierung wählen",
    ["Scaling starts off and changes only if you enable it."] = "Skalierung ist zunächst aus und ändert sich nur auf deinen Wunsch.",
    ["Pixel perfect"] = "Pixelgenau",
    ["Small"] = "Klein",
    ["Medium"] = "Mittel",
    ["Large"] = "Groß",
    ["Profile activated"] = "Profil aktiviert",
    ["Your selected settings have been saved."] = "Deine gewählten Einstellungen wurden gespeichert.",
    ["Reload the interface"] = "Oberfläche neu laden",
    ["This finishes loading the selected Suite modules."] = "Damit werden die gewählten Suite-Module vollständig geladen.",
    ["Back"] = "Zurück",
    ["Not now"] = "Später",
    ["Continue"] = "Weiter",
    ["DONE"] = "FERTIG",
    ["Reload UI"] = "UI neu laden",
    ["Install"] = "Installieren",
    ["Welcome to MSUF Suite"] = "Willkommen bei MSUF Suite",
    ["Set up your interface in a few steps. Nothing changes until you click Install."] = "Richte deine Oberfläche in wenigen Schritten ein. Erst „Installieren“ übernimmt die Auswahl.",
    ["Choose your profile"] = "Profil auswählen",
    ["Forever creates a complete profile. Modern keeps your MSUF frames and applies Suite and Skin settings."] = "Forever erstellt ein vollständiges Profil. Modern behält deine MSUF-Frames und übernimmt Suite- und Skin-Einstellungen.",
    ["Modern  ·  Suite only"] = "Modern  ·  nur Suite",
    ["Retail default. Applies the included Suite and optional Skin profile; keeps your MSUF frames."] = "Retail-Standard. Übernimmt Suite- und optionales Skin-Profil; behält deine MSUF-Frames.",
    ["Forever  ·  Complete profile"] = "Forever  ·  vollständiges Profil",
    ["Applies the current Forever factory to MSUF frames and Suite modules; Skin is included when enabled."] = "Übernimmt die aktuelle Forever-Factory für MSUF-Frames und Suite-Module; Skin bei aktiviertem Addon.",
    ["SELECTED"] = "GEWÄHLT",
    ["CHOOSE"] = "WÄHLEN",
    ["Forever creates a new profile. Existing profiles remain saved."] = "Forever erstellt ein neues Profil. Bestehende Profile bleiben gespeichert.",
    ["Modern replaces active Suite and optional Skin settings. MSUF frames stay unchanged."] = "Modern ersetzt aktive Suite- und optionale Skin-Einstellungen. MSUF-Frames bleiben unverändert.",
    ["MSUF spec cooldown profiles"] = "MSUF-Spec-Cooldown-Profile",
    ["Raid essentials, utility and buffs for your spec; turn off to follow Blizzard's CDM."] = "Raid-Essentials, Utility und Buffs für deinen Spec; aus folgt dem Blizzard-CDM.",
    ["ON"] = "AN",
    ["OFF"] = "AUS",
    ["Choose Suite modules"] = "Suite-Module auswählen",
    ["The chosen profile supplies all settings. Toggle which Suite modules are enabled in it."] = "Das gewählte Profil liefert alle Einstellungen. Wähle hier die aktivierten Suite-Module.",
    ["Set UI scale"] = "UI-Skalierung einstellen",
    ["Global UI scaling is off by default. Turn it on only if you want a different interface size."] = "Globale UI-Skalierung ist standardmäßig aus. Schalte sie nur für eine andere Oberflächengröße ein.",
    ["UI scaling is on"] = "UI-Skalierung ist an",
    ["UI scaling is off"] = "UI-Skalierung ist aus",
    ["Choose a preset below or fine-tune with the slider."] = "Wähle unten eine Stufe oder stelle den Regler frei ein.",
    ["MSUF restores your current Blizzard UI scale. Click here to enable optional scaling."] = "MSUF stellt deine aktuelle Blizzard-UI-Skalierung wieder her. Zum Aktivieren hier klicken.",
    ["Presets"] = "Skalierungsstufen",
    ["No Suite scaling will be applied."] = "Es wird keine Suite-Skalierung angewendet.",
    ["Review and install"] = "Prüfen und installieren",
    ["Check your choices. Install applies them together; you can return to any step first."] = "Prüfe deine Auswahl. „Installieren“ übernimmt sie gemeinsam; du kannst vorher zurückgehen.",
    ["Profile"] = "Profil",
    ["Forever · complete MSUF and Suite factory"] = "Forever · vollständige MSUF- und Suite-Factory",
    ["Modern · Suite profile, MSUF frames retained"] = "Modern · Suite-Profil, MSUF-Frames bleiben",
    ["Modules"] = "Module",
    ["enabled"] = "aktiv",
    ["MSUF spec cooldowns"] = "MSUF-Spec-Cooldowns",
    ["Blizzard cooldowns"] = "Blizzard-Cooldowns",
    ["UI scaling"] = "UI-Skalierung",
    ["Pixel perfect · adapts to resolution"] = "Pixelgenau · passt sich der Auflösung an",
    ["Off · Blizzard setting retained"] = "Aus · Blizzard-Einstellung bleibt",
    ["Installation complete"] = "Installation abgeschlossen",
    ["Your new setup is active. Reload the interface to finish loading all selected modules."] = "Deine neue Einrichtung ist aktiv. Lade die Oberfläche neu, damit alle gewählten Module geladen werden.",
}
local german = type(GetLocale) == "function" and GetLocale() == "deDE"
local function Text(english)
    local value = german and GERMAN[english] or Suite.L and Suite.L[english]
    return type(value) == "string" and value ~= "" and value or english
end

local function RetailCooldowns()
    return Suite.Client and Suite.Client.isMainline
        and (selected == "suite" or Suite.Client.isForever ~= true)
end

local function PlayerCooldownAnchor()
    local anchors = Suite.CDM and Suite.CDM.FRAME_ANCHORS
    for index, unit in pairs(anchors or {}) do
        if unit == "player" then return index end
    end
end

local function FrameProfileName()
    return type(_G.MSUF_ActiveProfile) == "string" and _G.MSUF_ActiveProfile ~= ""
        and _G.MSUF_ActiveProfile or DB.GetActiveProfileName()
end

local function PreparedProfile()
    local compact = selected == "forever" and Suite.ForeverFactoryModuleCompact
        or Suite.RetailFactoryModuleCompact
    local profile, reason = Suite.ProfileIO.PrepareProfile(compact, false)
    if not profile then return false, reason end
    local modules = profile.suite.modules
    local minimap = modules.minimap
    if minimap then minimap.point, minimap.x, minimap.y = 3, -20, -20 end
    local xp = modules.xpBar
    if xp then xp.point, xp.x, xp.y = 2, 0, -24 end
    local bars = modules.actionbars
    if bars and selected == "suite" then
        bars.bar1Point, bars.bar1X, bars.bar1Y = 8, 10, 48
        bars.bar2Point, bars.bar2X, bars.bar2Y = 8, 10, 92
        bars.bar3Point, bars.bar3X, bars.bar3Y = 7, 24, 210
        bars.bar5Point, bars.bar5X, bars.bar5Y = 7, 72, 210
    end
    if selected == "suite" then
        -- The supplied export was positioned around a 1440p screen centre.
        -- Keep its visual settings but anchor the visible groups to screen
        -- edges, so changing resolution or UI scale cannot push them away.
        local texts = modules.dataTexts
        if texts then texts.bar1Point, texts.bar1X, texts.bar1Y = 9, 0, 170 end
    end
    local cooldowns = modules.cooldownManager
    if cooldowns and RetailCooldowns() then
        cooldowns.raidEssentials = useRaidEssentials
        -- Keep personal icon lists and spell choices when changing between
        -- Modern and Retail Forever. Fresh installs use the supplied preset.
        local active = DB.GetProfile(DB.GetActiveProfileName())
        local old = active and active.suite and active.suite.modules
            and active.suite.modules.cooldownManager
        if old and type(old.listsData) == "string"
            and (selected == "suite" or old.listsData ~= "") then
            cooldowns.listsData = old.listsData
        end
        if old and type(old.spellsData) == "string"
            and (selected == "suite" or old.spellsData ~= "") then
            cooldowns.spellsData = old.spellsData
        end
        if selected == "forever" then
            local playerAnchor = PlayerCooldownAnchor()
            if not playerAnchor then return nil, "CDM player-frame anchor unavailable" end
            -- The authored Forever rows must survive the runtime's legacy
            -- defaults migration. Its old Potions row followed Utility far
            -- below the player; both side rows now follow the Player frame.
            cooldowns.captured = true
            cooldowns.defaultsVersion = Suite.CDM.DEFAULTS_VERSION
            cooldowns.def_anchor, cooldowns.def_side = playerAnchor, 2
            cooldowns.def_gap, cooldowns.def_align = 44, 3
            cooldowns.def_x, cooldowns.def_y = 0, 0
            cooldowns.ext_anchor, cooldowns.ext_side = playerAnchor, 1
            cooldowns.ext_gap, cooldowns.ext_align = 22, 2
            cooldowns.ext_x, cooldowns.ext_y = 0, 0
        end
    end
    local overrides = moduleOverrides[selected] or {}
    for id, enabled in pairs(overrides) do
        local module = profile.suite.modules[id]
        if module then module.enabled = enabled == true end
    end
    return profile
end

local function ApplySuiteOnly(profile)
    local name = FrameProfileName()
    if not DB.IsProfileName(name) then return false, "MSUF profile unavailable" end
    return Suite.SuiteProfiles.InstallSuiteFactory(name, profile,
        Suite.RetailFactorySkinCompact)
end

local function NextForeverName()
    local base = "MSUF Suite Forever"
    local name = base
    local index = 2
    while DB.GetProfile(name) or (_G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles
        and _G.MSUF_GlobalDB.profiles[name]) do
        name = base .. " " .. index
        index = index + 1
    end
    return name
end

local function ApplyForever(profile)
    local msuf = _G.MSUF_NS
    local frames = Suite.Client and Suite.Client.isForever and msuf
        and msuf.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT
        or Suite.ForeverFactoryFramesCompact
    local skin = Suite.ForeverFactorySkinCompact
    if type(frames) ~= "string" or type(profile) ~= "table" then
        return false, "Forever factory profile unavailable"
    end
    local skinEnabled = Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
    return Suite.SuiteProfiles.InstallFactory(NextForeverName(), frames, profile,
        skinEnabled and skin or nil)
end

local function ApplyScale()
    local general = type(_G.MSUF_DB) == "table" and _G.MSUF_DB.general
    if type(general) ~= "table" then return false, "MSUF scale settings unavailable" end
    if type(_G.MSUF_ResetGlobalUiScale) ~= "function"
        or type(_G.MSUF_ApplyMsufScale) ~= "function" then
        return false, "MSUF scale controls unavailable"
    end
    if useScale and type(_G.MSUF_SetGlobalUiScale) ~= "function" then
        return false, "MSUF UI scale control unavailable"
    end
    general.msufUiScale = 1
    general.uiScale = nil
    _G.MSUF_ApplyMsufScale(1)
    if _G.MSUF_ResetGlobalUiScale(true) == false then return false, "Cannot change scale in combat" end
    if useScale then
        if scalePreset == "pixel" and type(_G.MSUF_GetPixelPerfectScale) == "function" then
            scale = tonumber(_G.MSUF_GetPixelPerfectScale()) or scale
        end
        general.UIScale = type(general.UIScale) == "table" and general.UIScale or {}
        general.UIScale.Enabled = true
        general.UIScale.Scale = scale
        general.globalUiScalePreset = scalePreset
        general.globalUiScaleValue = scale
        _G.MSUF_SetGlobalUiScale(scale, true)
    end
    return true
end

local function ScaleControlsReady()
    if type(_G.MSUF_DB) ~= "table" or type(_G.MSUF_DB.general) ~= "table" then
        return false, "MSUF scale settings unavailable"
    end
    if type(_G.MSUF_ResetGlobalUiScale) ~= "function"
        or type(_G.MSUF_ApplyMsufScale) ~= "function" then
        return false, "MSUF scale controls unavailable"
    end
    if useScale and type(_G.MSUF_SetGlobalUiScale) ~= "function" then
        return false, "MSUF UI scale control unavailable"
    end
    return true
end

function Installer.Apply()
    if Suite.IsCombatLocked() then return false, Text("Finish combat first.") end
    if type(Suite.RootDB) ~= "table" then return false, "Suite database unavailable" end
    local ready, why = ScaleControlsReady()
    if not ready then return false, why end
    local profile, reason = PreparedProfile()
    if not profile then return false, reason end
    local ok, reason
    if selected == "forever" then ok, reason = ApplyForever(profile)
    else ok, reason = ApplySuiteOnly(profile) end
    if not ok then return false, reason end
    ok, reason = ApplyScale()
    if not ok then return false, reason end
    local previous = Suite.RootDB.installation
    local getDefault = _G.MSUF_GetDefaultProfileForNewCharacters
    local carriedDefault = type(previous) == "table" and previous.newCharacterProfileOwned == true
        and type(getDefault) == "function" and getDefault() == previous.frameProfileName
    Suite.RootDB.installation = {
        revision = 2, status = "complete", profile = selected,
        frameProfileName = FrameProfileName(),
        moduleOverrides = moduleOverrides[selected],
        raidEssentials = RetailCooldowns() and useRaidEssentials,
        uiScaleEnabled = useScale, uiScale = useScale and scale or nil,
        uiScalePreset = useScale and scalePreset or nil,
        foreverAnchorRevision = RetailCooldowns() and selected == "forever" and 1 or nil,
    }
    if carriedDefault and type(_G.MSUF_SetDefaultProfileForNewCharacters) == "function"
        and _G.MSUF_SetDefaultProfileForNewCharacters(FrameProfileName()) == true then
        Suite.RootDB.installation.newCharacterProfileRevision = 1
        Suite.RootDB.installation.newCharacterProfileOwned = true
    end
    if Suite.SuiteProfiles and Suite.SuiteProfiles.EnsureNewCharacterProfile then
        Suite.SuiteProfiles.EnsureNewCharacterProfile()
    end
    if Suite.SuiteProfiles and Suite.SuiteProfiles.EnsureRetailResourceStack then
        Suite.SuiteProfiles.EnsureRetailResourceStack(true)
    end
    return true
end

local function Style(panel, selectedState, primary)
    panel:SetBackdropColor(selectedState and 0.07 or 0.075,
        selectedState and 0.18 or 0.095, selectedState and 0.24 or 0.14, 1)
    if primary or selectedState then
        panel:SetBackdropBorderColor(0.19, 0.75, 0.86, 1)
    else
        panel:SetBackdropBorderColor(0.28, 0.34, 0.42, 1)
    end
end

local function Panel(parent, x, y, width, height, isButton)
    local panel = CreateFrame(isButton and "Button" or "Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    Style(panel, false)
    return panel
end

local function Label(parent, template, x, y, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY", template)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetSize(width, height)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function NavButton(parent, x, y, width, caption, callback, primary)
    local button = Panel(parent, x, y, width, 30, true)
    Style(button, false, primary)
    button.caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.caption:SetPoint("CENTER")
    button.caption:SetText(caption)
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.11, primary and 0.38 or 0.19, primary and 0.48 or 0.26, 1)
    end)
    button:SetScript("OnLeave", function(self) Style(self, false, primary) end)
    return button
end

local function InfoCard(parent, x, y, title, detail)
    local card = Panel(parent, x, y, 508, 56, false)
    card.title = Label(card, "GameFontNormal", 14, -10, 474, 18)
    card.title:SetText(title)
    card.detail = Label(card, "GameFontHighlightSmall", 14, -30, 474, 21)
    card.detail:SetText(detail)
    return card
end

local function ProfileCard(parent, x, y, callback)
    local card = Panel(parent, x, y, 508, 82, true)
    card.title = Label(card, "GameFontNormal", 16, -12, 370, 20)
    card.detail = Label(card, "GameFontHighlightSmall", 16, -36, 470, 38)
    card.mark = Label(card, "GameFontNormalSmall", 388, -13, 105, 20)
    card.mark:SetJustifyH("RIGHT")
    card:SetScript("OnClick", callback)
    return card
end

local function ModuleRow(parent, id, index, count)
    local perColumn = math.ceil(count / 2)
    local column = index > perColumn and 1 or 0
    local row = column == 0 and index - 1 or index - perColumn - 1
    local card = Panel(parent, 36 + column * 258, 272 - row * 25, 250, 22, true)
    card.id = id
    card.label = Label(card, "GameFontHighlightSmall", 10, -4, 188, 16)
    card.label:SetText((Suite.SuiteCatalog[id] and Suite.SuiteCatalog[id].title) or id)
    card.state = Label(card, "GameFontNormalSmall", 198, -4, 42, 16)
    card.state:SetJustifyH("RIGHT")
    card:SetScript("OnClick", function()
        local profile = PreparedProfile()
        local config = profile and profile.suite and profile.suite.modules[id]
        if not config then return end
        moduleOverrides[selected][id] = not config.enabled
        Installer.Refresh()
    end)
    card:SetScript("OnEnter", function(self)
        local spec = Suite.SuiteCatalog[id]
        local tooltip = _G.GameTooltip
        if not (spec and tooltip) then return end
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
        tooltip:SetText(spec.title or id)
        if type(spec.description) == "string" and spec.description ~= "" then
            tooltip:AddLine(spec.description, 0.78, 0.84, 0.89, true)
        end
        if Suite.Suite and type(Suite.Suite.Availability) == "function" then
            local available, reason = Suite.Suite.Availability(id)
            if not available and reason then tooltip:AddLine(reason, 1, 0.45, 0.4, true) end
        end
        tooltip:Show()
    end)
    card:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    return card
end

------------------------------------------------------------------ window
-- The steps below create the window's regions in their original order, so
-- stacking and layout stay unchanged.
local function CreateWindow()
    local window = CreateFrame("Frame", "MSUFSuiteInstallFrame", _G.UIParent, "BackdropTemplate")
    window:SetSize(580, 470)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    window:SetBackdropColor(0.035, 0.055, 0.085, 0.985)
    window:SetBackdropBorderColor(0.25, 0.43, 0.52, 1)
    window:EnableMouse(true)
    window:SetMovable(true)
    if window.SetClampedToScreen then window:SetClampedToScreen(true) end
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:Hide()
    return window
end

-- Brand, step counter, page title and body, and the five progress segments.
local function BuildHeader(window)
    window.brand = Label(window, "GameFontNormalSmall", 36, -19, 310, 17)
    window.brand:SetText("MSUF SUITE  /  " .. Text("INSTALLATION"))
    window.step = Label(window, "GameFontNormalSmall", 455, -19, 89, 17)
    window.step:SetJustifyH("RIGHT")
    window.title = Label(window, "GameFontNormalLarge", 36, -47, 508, 30)
    window.body = Label(window, "GameFontHighlight", 36, -108, 508, 57)
    window.progress = {}
    for i = 1, 5 do
        local segment = window:CreateTexture(nil, "ARTWORK")
        segment:SetTexture("Interface\\Buttons\\WHITE8X8")
        segment:SetSize(99, 3)
        segment:SetPoint("TOPLEFT", window, "TOPLEFT", 36 + (i - 1) * 106, -87)
        window.progress[i] = segment
    end
end

-- Pages 1 to 3: welcome cards, profile choice with the cooldown switch, and
-- one row per Suite module.
local function BuildProfileSteps(window)
    window.intro = {
        InfoCard(window, 36, 231, Text("1. Choose a profile"),
            Text("Modern keeps your MSUF frames. Forever installs the full factory profile.")),
        InfoCard(window, 36, 157, Text("2. Select modules"),
            Text("Keep the profile defaults or switch individual Suite modules on or off.")),
        InfoCard(window, 36, 83, Text("3. Set UI scale"),
            Text("Scaling starts off and changes only if you enable it.")),
    }
    window.suite = ProfileCard(window, 36, 210, function()
        selected = "suite"
        Installer.Refresh()
    end)
    window.forever = ProfileCard(window, 36, 112, function()
        selected = "forever"
        Installer.Refresh()
    end)
    window.profileNote = Label(window, "GameFontHighlightSmall", 38, -373, 504, 27)
    local cooldowns = Panel(window, 36, 63, 508, 42, true)
    cooldowns.title = Label(cooldowns, "GameFontNormal", 14, -7, 360, 17)
    cooldowns.detail = Label(cooldowns, "GameFontHighlightSmall", 14, -24, 460, 15)
    cooldowns.mark = Label(cooldowns, "GameFontNormalSmall", 388, -7, 105, 18)
    cooldowns.mark:SetJustifyH("RIGHT")
    cooldowns:SetScript("OnClick", function()
        useRaidEssentials = not useRaidEssentials
        Installer.Refresh()
    end)
    window.cooldowns = cooldowns
    window.moduleRows = {}
    for index, id in ipairs(Suite.SuiteOrder or {}) do
        window.moduleRows[index] = ModuleRow(window, id, index, #Suite.SuiteOrder)
    end
end

local SCALE_PRESETS = {
    { "Pixel perfect", function()
        local pixel = type(_G.MSUF_GetPixelPerfectScale) == "function"
            and _G.MSUF_GetPixelPerfectScale() or 1
        return tonumber(pixel) or 1
    end },
    { "Small", function() return 0.6 end },
    { "Medium", function() return 0.7 end },
    { "Large", function() return 0.8 end },
}

local function BuildScaleSlider(window)
    local slider = CreateFrame("Slider", "MSUFSuiteInstallScaleSlider", window, "OptionsSliderTemplate")
    slider:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 86, 110)
    slider:SetSize(346, 18)
    slider:SetMinMaxValues(0.3, 1.15)
    slider:SetValueStep(0.01)
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local label = _G["MSUFSuiteInstallScaleSlider" .. suffix]
        if label then label:Hide() end
    end
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    window.scaleSlider = slider
    slider:SetValue(scale)
    slider:SetScript("OnValueChanged", function(_, value)
        scale = math.floor(value * 100 + 0.5) / 100
        scalePreset = "custom"
        if window.scaleLabel then window.scaleLabel:SetText(("%d%%"):format(scale * 100 + 0.5)) end
    end)
end

-- Page 4: the scaling switch, preset buttons, slider and value label.
local function BuildScaleStep(window)
    window.scaleToggle = ProfileCard(window, 36, 216, function()
        useScale = not useScale
        Installer.Refresh()
    end)
    window.scaleHint = Label(window, "GameFontHighlightSmall", 38, -269, 500, 18)
    window.presets = {}
    for index, preset in ipairs(SCALE_PRESETS) do
        window.presets[index] = NavButton(window, 36 + (index - 1) * 135, 151, 103,
            Text(preset[1]), function()
                local wanted = math.max(0.3, math.min(1.15, preset[2]()))
                window.scaleSlider:SetValue(wanted)
                scale = wanted
                scalePreset = index == 1 and "pixel" or "custom"
                Installer.Refresh()
            end)
    end
    BuildScaleSlider(window)
    window.scaleLabel = Label(window, "GameFontNormal", 448, -338, 88, 24)
    window.scaleLabel:SetJustifyH("RIGHT")
end

-- Pages 5 and 6: the review summary and the completion cards.
local function BuildResultCards(window)
    window.review = {
        InfoCard(window, 36, 225, "", ""),
        InfoCard(window, 36, 152, "", ""),
        InfoCard(window, 36, 79, "", ""),
    }
    window.done = {
        InfoCard(window, 36, 176, Text("Profile activated"),
            Text("Your selected settings have been saved.")),
        InfoCard(window, 36, 103, Text("Reload the interface"),
            Text("This finishes loading the selected Suite modules.")),
    }
end

-- Continue walks the pages, installs on the review page and reloads at the end.
local function OnContinue(window)
    if page < 5 then
        page = page + 1
        Installer.Refresh()
    elseif page == 5 then
        local ok, reason = Installer.Apply()
        if not ok then
            window.status:SetText("|cffff6666" .. tostring(reason or "Installation failed") .. "|r")
            return
        end
        page = 6
        Installer.Refresh()
    elseif type(_G.ReloadUI) == "function" then
        _G.ReloadUI()
    else
        window:Hide()
    end
end

local function BuildNavigation(window)
    window.status = Label(window, "GameFontHighlightSmall", 36, -403, 508, 17)
    window.back = NavButton(window, 36, 15, 104, Text("Back"), function()
        page = math.max(1, page - 1)
        Installer.Refresh()
    end)
    window.close = NavButton(window, 150, 15, 104, Text("Not now"), function()
        if Suite.RootDB and page ~= 6 then
            Suite.RootDB.installation = { revision = 2, status = "skipped" }
        end
        window:Hide()
    end)
    window.next = NavButton(window, 414, 15, 130, Text("Continue"), function() OnContinue(window) end, true)
end

local function Build()
    if frame then return frame end
    frame = CreateWindow()
    BuildHeader(frame)
    BuildProfileSteps(frame)
    BuildScaleStep(frame)
    BuildResultCards(frame)
    BuildNavigation(frame)
    return frame
end

------------------------------------------------------------------ pages
local function SetShownAll(list, shown)
    for _, item in ipairs(list) do item:SetShown(shown) end
end

-- Shows the controls of the current page (1 welcome, 2 profile, 3 modules,
-- 4 scaling, 5 review, 6 done) and updates progress and navigation.
local function ShowPage(f)
    local complete, scaling = page == 6, page == 4
    f.step:SetText(complete and Text("DONE") or ("%d / 5"):format(page))
    for i, segment in ipairs(f.progress) do
        if i <= math.min(page, 5) then
            segment:SetColorTexture(0.16, 0.74, 0.84, 1)
        else
            segment:SetColorTexture(0.20, 0.25, 0.30, 1)
        end
    end
    SetShownAll(f.intro, page == 1)
    f.suite:SetShown(page == 2)
    f.forever:SetShown(page == 2)
    f.profileNote:SetShown(page == 2 and selected == "forever")
    f.cooldowns:SetShown(page == 2 and RetailCooldowns())
    SetShownAll(f.moduleRows, page == 3)
    f.scaleToggle:SetShown(scaling)
    f.scaleHint:SetShown(scaling)
    f.scaleSlider:SetShown(scaling and useScale)
    f.scaleLabel:SetShown(scaling and useScale)
    SetShownAll(f.presets, scaling and useScale)
    SetShownAll(f.review, page == 5)
    SetShownAll(f.done, complete)
    f.back:SetShown(page > 1 and not complete)
    f.close:SetShown(not complete)
    f.close:ClearAllPoints()
    f.close:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", page == 1 and 36 or 150, 15)
    f.next.caption:SetText(complete and Text("Reload UI") or page == 5 and Text("Install") or Text("Continue"))
    f.status:SetText("")
end

local function SetPageText(f, title, body)
    f.title:SetText(Text(title))
    f.body:SetText(Text(body))
end

-- The profile of the current choice; a failure is shown in the status line.
local function PreviewProfile(f)
    local profile, reason = PreparedProfile()
    if not profile then f.status:SetText("|cffff6666" .. tostring(reason) .. "|r") end
    return profile
end

local function PaintWelcome(f)
    SetPageText(f, "Welcome to MSUF Suite",
        "Set up your interface in a few steps. Nothing changes until you click Install.")
end

local function PaintProfiles(f)
    SetPageText(f, "Choose your profile",
        "Forever creates a complete profile. Modern keeps your MSUF frames and applies Suite and Skin settings.")
    f.suite.title:SetText(Text("Modern  ·  Suite only"))
    f.suite.detail:SetText(Text("Retail default. Applies the included Suite and optional Skin profile; keeps your MSUF frames."))
    f.forever.title:SetText(Text("Forever  ·  Complete profile"))
    f.forever.detail:SetText(Text("Applies the current Forever factory to MSUF frames and Suite modules; Skin is included when enabled."))
    Style(f.suite, selected == "suite")
    Style(f.forever, selected == "forever")
    f.suite.mark:SetText(selected == "suite" and Text("SELECTED") or Text("CHOOSE"))
    f.forever.mark:SetText(selected == "forever" and Text("SELECTED") or Text("CHOOSE"))
    f.profileNote:SetText(selected == "forever"
        and Text("Forever creates a new profile. Existing profiles remain saved.")
        or Text("Modern replaces active Suite and optional Skin settings. MSUF frames stay unchanged."))
    f.cooldowns.title:SetText(Text("MSUF spec cooldown profiles"))
    f.cooldowns.detail:SetText(Text("Raid essentials, utility and buffs for your spec; turn off to follow Blizzard's CDM."))
    f.cooldowns.mark:SetText(useRaidEssentials and Text("ON") or Text("OFF"))
    Style(f.cooldowns, useRaidEssentials)
end

local function PaintModules(f)
    SetPageText(f, "Choose Suite modules",
        "The chosen profile supplies all settings. Toggle which Suite modules are enabled in it.")
    local profile = PreviewProfile(f)
    for _, row in ipairs(f.moduleRows) do
        local config = profile and profile.suite.modules[row.id]
        local enabled = config and config.enabled == true
        Style(row, enabled)
        row.state:SetText(enabled and Text("ON") or Text("OFF"))
    end
end

local function PaintScaling(f)
    SetPageText(f, "Set UI scale",
        "Global UI scaling is off by default. Turn it on only if you want a different interface size.")
    f.scaleToggle.title:SetText(useScale and Text("UI scaling is on") or Text("UI scaling is off"))
    f.scaleToggle.detail:SetText(useScale and Text("Choose a preset below or fine-tune with the slider.")
        or Text("MSUF restores your current Blizzard UI scale. Click here to enable optional scaling."))
    f.scaleToggle.mark:SetText(useScale and Text("ON") or Text("OFF"))
    Style(f.scaleToggle, useScale)
    f.scaleHint:SetText(useScale and Text("Presets") or Text("No Suite scaling will be applied."))
    f.scaleLabel:SetText(scalePreset == "pixel" and ("%.2f%%"):format(scale * 100)
        or ("%d%%"):format(scale * 100 + 0.5))
end

local function ModuleSummary(profile)
    local enabled, total = 0, 0
    for _, id in ipairs(Suite.SuiteOrder or {}) do
        total = total + 1
        if profile and profile.suite.modules[id] and profile.suite.modules[id].enabled then
            enabled = enabled + 1
        end
    end
    local summary = ("%d / %d %s"):format(enabled, total, Text("enabled"))
    if RetailCooldowns() then
        summary = summary .. "  ·  "
            .. (useRaidEssentials and Text("MSUF spec cooldowns") or Text("Blizzard cooldowns"))
    end
    return summary
end

local function PaintReview(f)
    SetPageText(f, "Review and install",
        "Check your choices. Install applies them together; you can return to any step first.")
    local profile = PreviewProfile(f)
    f.review[1].title:SetText(Text("Profile"))
    f.review[1].detail:SetText(selected == "forever"
        and Text("Forever · complete MSUF and Suite factory")
        or Text("Modern · Suite profile, MSUF frames retained"))
    f.review[2].title:SetText(Text("Modules"))
    f.review[2].detail:SetText(ModuleSummary(profile))
    f.review[3].title:SetText(Text("UI scaling"))
    f.review[3].detail:SetText(useScale and (scalePreset == "pixel"
        and Text("Pixel perfect · adapts to resolution")
        or ("%d%%"):format(scale * 100 + 0.5))
        or Text("Off · Blizzard setting retained"))
end

local function PaintComplete(f)
    SetPageText(f, "Installation complete",
        "Your new setup is active. Reload the interface to finish loading all selected modules.")
end

local PAGE_PAINTERS = { PaintWelcome, PaintProfiles, PaintModules, PaintScaling, PaintReview, PaintComplete }

function Installer.Refresh()
    local f = Build()
    ShowPage(f)
    local paint = PAGE_PAINTERS[page] or PaintComplete
    paint(f)
end

function Installer.Open()
    if Suite.IsCombatLocked() then return false, "combat" end
    selected = Suite.Client and Suite.Client.isForever and "forever" or "suite"
    local active = DB.GetProfile(DB.GetActiveProfileName())
    local current = active and active.suite and active.suite.modules
        and active.suite.modules.cooldownManager
    useScale, scale, scalePreset, page = false, 1, "custom", 1
    useRaidEssentials = not (current and current.raidEssentials == false)
    moduleOverrides = { suite = {}, forever = {} }
    Installer.Refresh()
    frame:Show()
    return true
end
function Installer.MaybeShow()
    if type(_G.IsLoggedIn) == "function" and not _G.IsLoggedIn() then return false end
    if frame and frame.IsShown and frame:IsShown() then return false end
    if Suite.freshInstall and Suite.RootDB and not Suite.RootDB.installation then
        return Installer.Open()
    end
    return false
end

_G.SLASH_MSUFSUITEINSTALL1 = "/msufsuite"
_G.SlashCmdList.MSUFSUITEINSTALL = function(message)
    message = type(message) == "string" and message:match("^%s*(.-)%s*$"):lower() or ""
    if message == "" or message == "install" then
        Installer.Open()
    else
        Suite.Print("/msufsuite install")
    end
end
