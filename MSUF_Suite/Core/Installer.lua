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

local de = type(GetLocale) == "function" and GetLocale() == "deDE"
local function Tr(english, german) return de and german or english end
local function RetailCooldowns()
    return Suite.Client and Suite.Client.isMainline and selected == "suite"
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
        local cooldowns = modules.cooldownManager
        if cooldowns and RetailCooldowns() then
            cooldowns.raidEssentials = useRaidEssentials
            -- The Retail factory already includes the Subtlety Suite layout.
            -- Keep it on a fresh install; personal lists take precedence when
            -- a user reruns Modern. Other specs use the raid fallback.
            local active = DB.GetProfile(DB.GetActiveProfileName())
            local old = active and active.suite and active.suite.modules
                and active.suite.modules.cooldownManager
            if old and type(old.listsData) == "string" then
                cooldowns.listsData = old.listsData
            end
            if old and type(old.spellsData) == "string" then
                cooldowns.spellsData = old.spellsData
            end
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
    if Suite.IsCombatLocked() then return false, Tr("Finish combat first.", "Bitte zuerst den Kampf beenden.") end
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
    Suite.RootDB.installation = {
        revision = 2, status = "complete", profile = selected,
        frameProfileName = FrameProfileName(),
        moduleOverrides = moduleOverrides[selected],
        raidEssentials = RetailCooldowns() and useRaidEssentials,
        uiScaleEnabled = useScale, uiScale = useScale and scale or nil,
        uiScalePreset = useScale and scalePreset or nil,
    }
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

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "MSUFSuiteInstallFrame", _G.UIParent, "BackdropTemplate")
    frame:SetSize(580, 470)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0.035, 0.055, 0.085, 0.985)
    frame:SetBackdropBorderColor(0.25, 0.43, 0.52, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    frame.brand = Label(frame, "GameFontNormalSmall", 36, -19, 310, 17)
    frame.brand:SetText("MSUF SUITE  /  " .. Tr("INSTALLATION", "INSTALLATION"))
    frame.step = Label(frame, "GameFontNormalSmall", 455, -19, 89, 17)
    frame.step:SetJustifyH("RIGHT")
    frame.title = Label(frame, "GameFontNormalLarge", 36, -47, 508, 30)
    frame.body = Label(frame, "GameFontHighlight", 36, -108, 508, 57)
    frame.progress = {}
    for i = 1, 5 do
        local segment = frame:CreateTexture(nil, "ARTWORK")
        segment:SetTexture("Interface\\Buttons\\WHITE8X8")
        segment:SetSize(99, 3)
        segment:SetPoint("TOPLEFT", frame, "TOPLEFT", 36 + (i - 1) * 106, -87)
        frame.progress[i] = segment
    end

    frame.intro = {
        InfoCard(frame, 36, 231, Tr("1. Choose a profile", "1. Profil wählen"),
            Tr("Modern keeps your MSUF frames. Forever installs the full factory profile.",
                "Modern behält deine MSUF-Frames. Forever installiert das komplette Factory-Profil.")),
        InfoCard(frame, 36, 157, Tr("2. Select modules", "2. Module auswählen"),
            Tr("Keep the profile defaults or switch individual Suite modules on or off.",
                "Übernimm die Profilwerte oder schalte einzelne Suite-Module an oder aus.")),
        InfoCard(frame, 36, 83, Tr("3. Set UI scale", "3. UI-Skalierung wählen"),
            Tr("Scaling starts off and changes only if you enable it.",
                "Skalierung ist zunächst aus und ändert sich nur auf deinen Wunsch.")),
    }

    frame.suite = ProfileCard(frame, 36, 210, function()
        selected = "suite"
        Installer.Refresh()
    end)
    frame.forever = ProfileCard(frame, 36, 112, function()
        selected = "forever"
        Installer.Refresh()
    end)
    frame.profileNote = Label(frame, "GameFontHighlightSmall", 38, -373, 504, 27)
    frame.cooldowns = Panel(frame, 36, 63, 508, 42, true)
    frame.cooldowns.title = Label(frame.cooldowns, "GameFontNormal", 14, -7, 360, 17)
    frame.cooldowns.detail = Label(frame.cooldowns, "GameFontHighlightSmall", 14, -24, 460, 15)
    frame.cooldowns.mark = Label(frame.cooldowns, "GameFontNormalSmall", 388, -7, 105, 18)
    frame.cooldowns.mark:SetJustifyH("RIGHT")
    frame.cooldowns:SetScript("OnClick", function()
        useRaidEssentials = not useRaidEssentials
        Installer.Refresh()
    end)

    frame.moduleRows = {}
    for index, id in ipairs(Suite.SuiteOrder or {}) do
        frame.moduleRows[index] = ModuleRow(frame, id, index, #Suite.SuiteOrder)
    end

    frame.scaleToggle = ProfileCard(frame, 36, 216, function()
        useScale = not useScale
        Installer.Refresh()
    end)
    frame.scaleHint = Label(frame, "GameFontHighlightSmall", 38, -269, 500, 18)
    frame.presets = {}
    local presets = {
        { Tr("Pixel perfect", "Pixelgenau"), function()
            local pixel = type(_G.MSUF_GetPixelPerfectScale) == "function"
                and _G.MSUF_GetPixelPerfectScale() or 1
            return tonumber(pixel) or 1
        end },
        { Tr("Small", "Klein"), function() return 0.6 end },
        { Tr("Medium", "Mittel"), function() return 0.7 end },
        { Tr("Large", "Groß"), function() return 0.8 end },
    }
    for index, preset in ipairs(presets) do
        frame.presets[index] = NavButton(frame, 36 + (index - 1) * 135, 151, 103,
            preset[1], function()
                local wanted = math.max(0.3, math.min(1.15, preset[2]()))
                frame.scaleSlider:SetValue(wanted)
                scale = wanted
                scalePreset = index == 1 and "pixel" or "custom"
                Installer.Refresh()
            end)
    end
    frame.scaleSlider = CreateFrame("Slider", "MSUFSuiteInstallScaleSlider", frame, "OptionsSliderTemplate")
    frame.scaleSlider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 86, 110)
    frame.scaleSlider:SetSize(346, 18)
    frame.scaleSlider:SetMinMaxValues(0.3, 1.15)
    frame.scaleSlider:SetValueStep(0.01)
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local label = _G["MSUFSuiteInstallScaleSlider" .. suffix]
        if label then label:Hide() end
    end
    if frame.scaleSlider.SetObeyStepOnDrag then frame.scaleSlider:SetObeyStepOnDrag(true) end
    frame.scaleSlider:SetValue(scale)
    frame.scaleSlider:SetScript("OnValueChanged", function(_, value)
        scale = math.floor(value * 100 + 0.5) / 100
        scalePreset = "custom"
        if frame.scaleLabel then frame.scaleLabel:SetText(("%d%%"):format(scale * 100 + 0.5)) end
    end)
    frame.scaleLabel = Label(frame, "GameFontNormal", 448, -338, 88, 24)
    frame.scaleLabel:SetJustifyH("RIGHT")

    frame.review = {
        InfoCard(frame, 36, 225, "", ""),
        InfoCard(frame, 36, 152, "", ""),
        InfoCard(frame, 36, 79, "", ""),
    }
    frame.done = {
        InfoCard(frame, 36, 176, Tr("Profile activated", "Profil aktiviert"),
            Tr("Your selected settings have been saved.", "Deine gewählten Einstellungen wurden gespeichert.")),
        InfoCard(frame, 36, 103, Tr("Reload the interface", "Oberfläche neu laden"),
            Tr("This finishes loading the selected Suite modules.", "Damit werden die gewählten Suite-Module vollständig geladen.")),
    }

    frame.status = Label(frame, "GameFontHighlightSmall", 36, -403, 508, 17)
    frame.back = NavButton(frame, 36, 15, 104, Tr("Back", "Zurück"), function()
        page = math.max(1, page - 1)
        Installer.Refresh()
    end)
    frame.close = NavButton(frame, 150, 15, 104, Tr("Not now", "Später"), function()
        if Suite.RootDB and page ~= 6 then
            Suite.RootDB.installation = { revision = 2, status = "skipped" }
        end
        frame:Hide()
    end)
    frame.next = NavButton(frame, 414, 15, 130, Tr("Continue", "Weiter"), function()
        if page < 5 then
            page = page + 1
            Installer.Refresh()
        elseif page == 5 then
            local ok, reason = Installer.Apply()
            if not ok then
                frame.status:SetText("|cffff6666" .. tostring(reason or "Installation failed") .. "|r")
                return
            end
            page = 6
            Installer.Refresh()
        elseif type(_G.ReloadUI) == "function" then
            _G.ReloadUI()
        else
            frame:Hide()
        end
    end, true)
    return frame
end

function Installer.Refresh()
    local f = Build()
    local intro, profiles, modules, scaling, review, complete =
        page == 1, page == 2, page == 3, page == 4, page == 5, page == 6
    f.step:SetText(complete and Tr("DONE", "FERTIG") or
        ("%d / 5"):format(page))
    for i, segment in ipairs(f.progress) do
        if i <= math.min(page, 5) then segment:SetColorTexture(0.16, 0.74, 0.84, 1)
        else segment:SetColorTexture(0.20, 0.25, 0.30, 1) end
    end
    for _, card in ipairs(f.intro) do card:SetShown(intro) end
    f.suite:SetShown(profiles)
    f.forever:SetShown(profiles)
    f.profileNote:SetShown(profiles and selected == "forever")
    f.cooldowns:SetShown(profiles and RetailCooldowns())
    for _, row in ipairs(f.moduleRows) do row:SetShown(modules) end
    f.scaleToggle:SetShown(scaling)
    f.scaleHint:SetShown(scaling)
    f.scaleSlider:SetShown(scaling and useScale)
    f.scaleLabel:SetShown(scaling and useScale)
    for _, preset in ipairs(f.presets) do preset:SetShown(scaling and useScale) end
    for _, card in ipairs(f.review) do card:SetShown(review) end
    for _, card in ipairs(f.done) do card:SetShown(complete) end
    f.back:SetShown(page > 1 and not complete)
    f.close:SetShown(not complete)
    f.close:ClearAllPoints()
    f.close:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", page == 1 and 36 or 150, 15)
    f.next.caption:SetText(complete and Tr("Reload UI", "UI neu laden")
        or review and Tr("Install", "Installieren") or Tr("Continue", "Weiter"))
    f.status:SetText("")

    if intro then
        f.title:SetText(Tr("Welcome to MSUF Suite", "Willkommen bei MSUF Suite"))
        f.body:SetText(Tr("Set up your interface in a few steps. Nothing changes until you click Install.",
            "Richte deine Oberfläche in wenigen Schritten ein. Erst „Installieren“ übernimmt die Auswahl."))
    elseif profiles then
        f.title:SetText(Tr("Choose your profile", "Profil auswählen"))
        f.body:SetText(Tr("Forever creates a complete profile. Modern keeps your MSUF frames and applies Suite and Skin settings.",
            "Forever erstellt ein vollständiges Profil. Modern behält deine MSUF-Frames und übernimmt Suite- und Skin-Einstellungen."))
        f.suite.title:SetText(Tr("Modern  ·  Suite only", "Modern  ·  nur Suite"))
        f.suite.detail:SetText(Tr("Retail default. Applies the included Suite and optional Skin profile; keeps your MSUF frames.",
            "Retail-Standard. Übernimmt Suite- und optionales Skin-Profil; behält deine MSUF-Frames."))
        f.forever.title:SetText(Tr("Forever  ·  Complete profile", "Forever  ·  vollständiges Profil"))
        f.forever.detail:SetText(Tr("Applies the current Forever factory to MSUF frames and Suite modules; Skin is included when enabled.",
            "Übernimmt die aktuelle Forever-Factory für MSUF-Frames und Suite-Module; Skin bei aktiviertem Addon."))
        Style(f.suite, selected == "suite")
        Style(f.forever, selected == "forever")
        f.suite.mark:SetText(selected == "suite" and Tr("SELECTED", "GEWÄHLT") or Tr("CHOOSE", "WÄHLEN"))
        f.forever.mark:SetText(selected == "forever" and Tr("SELECTED", "GEWÄHLT") or Tr("CHOOSE", "WÄHLEN"))
        f.profileNote:SetText(selected == "forever"
            and Tr("Forever creates a new profile. Existing profiles remain saved.",
                "Forever erstellt ein neues Profil. Bestehende Profile bleiben gespeichert.")
            or Tr("Modern replaces active Suite and optional Skin settings. MSUF frames stay unchanged.",
                "Modern ersetzt aktive Suite- und optionale Skin-Einstellungen. MSUF-Frames bleiben unverändert."))
        f.cooldowns.title:SetText(Tr("MSUF spec cooldown profiles", "MSUF-Spec-Cooldown-Profile"))
        f.cooldowns.detail:SetText(Tr("Raid essentials, utility and buffs for your spec; turn off to follow Blizzard's CDM.",
            "Raid-Essentials, Utility und Buffs für deinen Spec; aus folgt dem Blizzard-CDM."))
        f.cooldowns.mark:SetText(useRaidEssentials and Tr("ON", "AN") or Tr("OFF", "AUS"))
        Style(f.cooldowns, useRaidEssentials)
    elseif modules then
        f.title:SetText(Tr("Choose Suite modules", "Suite-Module auswählen"))
        f.body:SetText(Tr("The chosen profile supplies all settings. Toggle which Suite modules are enabled in it.",
            "Das gewählte Profil liefert alle Einstellungen. Wähle hier die aktivierten Suite-Module."))
        local profile, reason = PreparedProfile()
        if not profile then f.status:SetText("|cffff6666" .. tostring(reason) .. "|r") end
        for _, row in ipairs(f.moduleRows) do
            local config = profile and profile.suite.modules[row.id]
            local enabled = config and config.enabled == true
            Style(row, enabled)
            row.state:SetText(enabled and Tr("ON", "AN") or Tr("OFF", "AUS"))
        end
    elseif scaling then
        f.title:SetText(Tr("Set UI scale", "UI-Skalierung einstellen"))
        f.body:SetText(Tr("Global UI scaling is off by default. Turn it on only if you want a different interface size.",
            "Globale UI-Skalierung ist standardmäßig aus. Schalte sie nur für eine andere Oberflächengröße ein."))
        f.scaleToggle.title:SetText(useScale and Tr("UI scaling is on", "UI-Skalierung ist an")
            or Tr("UI scaling is off", "UI-Skalierung ist aus"))
        f.scaleToggle.detail:SetText(useScale and Tr("Choose a preset below or fine-tune with the slider.",
            "Wähle unten eine Stufe oder stelle den Regler frei ein.")
            or Tr("MSUF restores your current Blizzard UI scale. Click here to enable optional scaling.",
                "MSUF stellt deine aktuelle Blizzard-UI-Skalierung wieder her. Zum Aktivieren hier klicken."))
        f.scaleToggle.mark:SetText(useScale and Tr("ON", "AN") or Tr("OFF", "AUS"))
        Style(f.scaleToggle, useScale)
        f.scaleHint:SetText(useScale and Tr("Presets", "Skalierungsstufen") or
            Tr("No Suite scaling will be applied.", "Es wird keine Suite-Skalierung angewendet."))
        f.scaleLabel:SetText(scalePreset == "pixel" and ("%.2f%%"):format(scale * 100)
            or ("%d%%"):format(scale * 100 + 0.5))
    elseif review then
        f.title:SetText(Tr("Review and install", "Prüfen und installieren"))
        f.body:SetText(Tr("Check your choices. Install applies them together; you can return to any step first.",
            "Prüfe deine Auswahl. „Installieren“ übernimmt sie gemeinsam; du kannst vorher zurückgehen."))
        local profile, reason = PreparedProfile()
        if not profile then f.status:SetText("|cffff6666" .. tostring(reason) .. "|r") end
        local enabled, total = 0, 0
        for _, id in ipairs(Suite.SuiteOrder or {}) do
            total = total + 1
            if profile and profile.suite.modules[id] and profile.suite.modules[id].enabled then
                enabled = enabled + 1
            end
        end
        f.review[1].title:SetText(Tr("Profile", "Profil"))
        f.review[1].detail:SetText(selected == "forever"
            and Tr("Forever · complete MSUF and Suite factory", "Forever · vollständige MSUF- und Suite-Factory")
            or Tr("Modern · Suite profile, MSUF frames retained", "Modern · Suite-Profil, MSUF-Frames bleiben"))
        f.review[2].title:SetText(Tr("Modules", "Module"))
        local moduleSummary = ("%d / %d %s"):format(enabled, total, Tr("enabled", "aktiv"))
        if RetailCooldowns() then
            moduleSummary = moduleSummary .. "  ·  "
                .. (useRaidEssentials and Tr("MSUF spec cooldowns", "MSUF-Spec-Cooldowns")
                    or Tr("Blizzard cooldowns", "Blizzard-Cooldowns"))
        end
        f.review[2].detail:SetText(moduleSummary)
        f.review[3].title:SetText(Tr("UI scaling", "UI-Skalierung"))
        f.review[3].detail:SetText(useScale and (scalePreset == "pixel"
            and Tr("Pixel perfect · adapts to resolution", "Pixelgenau · passt sich der Auflösung an")
            or ("%d%%"):format(scale * 100 + 0.5))
            or Tr("Off · Blizzard setting retained", "Aus · Blizzard-Einstellung bleibt"))
    else
        f.title:SetText(Tr("Installation complete", "Installation abgeschlossen"))
        f.body:SetText(Tr("Your new setup is active. Reload the interface to finish loading all selected modules.",
            "Deine neue Einrichtung ist aktiv. Lade die Oberfläche neu, damit alle gewählten Module geladen werden."))
    end
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
