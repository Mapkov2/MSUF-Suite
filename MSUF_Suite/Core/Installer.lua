local _, Suite = ...

local Installer = {}
Suite.Installer = Installer
local DB = Suite.Database
local selected = "suite"
local chosenLook
local keepFrames = true
local useRaidEssentials = true
local useScale = false
local scale = 1
local scalePreset = "custom"
local page = 1
local frame
local moduleOverrides = { suite = {}, classic = {}, forever = {} }
-- Above MSUF menu popups (DIALOG level 400); see CreateWindow.
local INSTALLER_FRAME_LEVEL = 500

function Installer.IsFirstRunPending()
    local installation = Suite.RootDB and Suite.RootDB.installation
    return type(installation) == "table" and installation.status == "pending"
        or (Suite.RootDB ~= nil or Suite.freshInstall) and not installation or false
end

function Installer.IsOpen()
    return frame ~= nil and frame:IsShown() or false
end

local function NotifyInstallerFinished()
    local registry = EventRegistry
    if registry then registry:TriggerEvent("MSUFSuite.Installer.Finished") end
end

-- Installer texts follow the Suite localization: English source strings
-- looked up in MSUF's locale table, which MSUF_Suite/Locales fills for
-- every supported language (MSUF's own wording wins where it has one).
local function Text(english)
    return Suite.Text(english)
end

-- Refusal reasons arrive as English text and are translated where shown.
local function ReasonText(reason)
    return Suite.StatusText(tostring(reason), Text)
end

local function RetailCooldowns()
    return not Suite.Client.isForever
end

local function PlayerCooldownAnchor()
    for index, unit in pairs(Suite.CDM.FRAME_ANCHORS) do
        if unit == "player" then return index end
    end
end

local function FrameProfileName()
    return type(_G.MSUF_ActiveProfile) == "string" and _G.MSUF_ActiveProfile ~= ""
        and _G.MSUF_ActiveProfile or DB.GetActiveProfileName()
end

local function DefaultLook()
    return selected == "forever" and "foreverGlass" or "cleanModern"
end

local function AppliedLook()
    if selected == "suite" then return chosenLook or "cleanModern" end
    return chosenLook
end

local function SkinPreset()
    if selected == "classic" then return Suite.RetailProfileSkinCompact end
    return (selected == "forever" or Suite.Client.isForever)
        and Suite.ForeverFactorySkinCompact or Suite.RetailFactorySkinCompact
end

-- Decoding a factory string is costly, so each one is decoded once. The
-- cached profile stays pristine: previews read it and installs copy it.
local decodedFactories = {}
local function FactoryProfile(layout, authored)
    layout = layout or selected
    local look = not authored and (layout == "suite" and (chosenLook or "cleanModern") or chosenLook) or nil
    local compact = layout == "classic" and Suite.RetailProfileModuleCompact
        or (Suite.Client.isForever or layout == "forever")
            and Suite.ForeverFactoryModuleCompact or Suite.RetailFactoryModuleCompact
    local cacheKey = layout .. (look or "authored") .. compact
    local profile = decodedFactories[cacheKey]
    if profile then return profile end
    local reason
    profile, reason = Suite.ProfileIO.PrepareProfile(compact, false)
    if not profile then return nil, reason end
    if look then Suite.Suite.StyleProfile(profile, look) end
    decodedFactories[cacheKey] = profile
    return profile
end

-- Whether a module starts enabled in the chosen profile: the choice made on
-- the modules page, else the factory value. nil for a module the factory
-- does not carry.
local function ModuleEnabled(profile, id)
    local config = profile.suite.modules[id]
    if not config then return nil end
    local override = moduleOverrides[selected][id]
    if override ~= nil then return override == true end
    return config.enabled == true
end

-- A reason the chosen factory profile cannot be installed on this client.
local function InstallBlocker(factory)
    if selected == "forever" and RetailCooldowns() and factory.suite.modules.cooldownManager
        and not PlayerCooldownAnchor() then
        return "CDM player-frame anchor unavailable"
    end
end

local function PreparedProfile()
    local factory, reason = FactoryProfile()
    if not factory then return false, reason end
    reason = InstallBlocker(factory)
    if reason then return false, reason end
    local profile = Suite.CopyValue(factory)
    local modules = profile.suite.modules
    local minimap = modules.minimap
    if selected == "suite" and minimap and minimap.stylePreset ~= 10 then
        minimap.point, minimap.x, minimap.y = 3, -20, -20
    end
    local xp = modules.xpBar
    if selected == "suite" and xp then xp.point, xp.x, xp.y = 2, 0, -24 end
    local bars = modules.actionbars
    if bars and selected == "suite" then
        bars.bar1Point, bars.bar1X, bars.bar1Y = 8, 0, 48
        bars.bar2Point, bars.bar2X, bars.bar2Y = 8, 0, 92
        bars.bar3Point, bars.bar3X, bars.bar3Y = 7, 24, 210
        bars.bar5Point, bars.bar5X, bars.bar5Y = 7, 72, 210
    end
    if selected == "suite" then
        -- The information strip belongs directly above the paired meters.
        -- Both groups follow the screen's right edge at every UI scale.
        local texts = modules.dataTexts
        if texts then texts.bar1Point, texts.bar1X, texts.bar1Y = 9, 0, 170 end
    end
    if selected == "classic" then Suite.InstallerLayout.Prepare(modules) end
    local cooldowns = modules.cooldownManager
    if cooldowns and RetailCooldowns() then
        cooldowns.raidEssentials = useRaidEssentials
        -- Keep personal icon lists and spell choices when changing between
        -- Modern and Retail Forever. Fresh installs use the supplied preset.
        local active = DB.GetProfile(DB.GetActiveProfileName())
        local old = active and active.suite and active.suite.modules
            and active.suite.modules.cooldownManager
        if (selected ~= "classic" or keepFrames) and old and type(old.listsData) == "string"
            and (selected ~= "forever" or old.listsData ~= "") then
            cooldowns.listsData = old.listsData
        end
        if (selected ~= "classic" or keepFrames) and old and type(old.spellsData) == "string"
            and (selected ~= "forever" or old.spellsData ~= "") then
            cooldowns.spellsData = old.spellsData
        end
        if selected == "forever" then
            local playerAnchor = PlayerCooldownAnchor()
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
    for id, enabled in pairs(moduleOverrides[selected]) do
        local config = modules[id]
        if config then config.enabled = enabled == true end
    end
    return profile
end

-- finish: the installer's last step inside the profile transaction (the UI
-- scale); its refusal rolls the install back.
local function ApplySuiteOnly(profile, finish)
    local name = FrameProfileName()
    if not DB.IsProfileName(name) then return false, "MSUF profile unavailable" end
    return Suite.SuiteProfiles.InstallSuiteFactory(name, profile,
        SkinPreset(), AppliedLook(), finish, selected ~= "suite" and { preserveSkinLayout = true } or nil)
end

local function NextFactoryName(base)
    local name = base
    local index = 2
    while DB.GetProfile(name) or (_G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles
        and _G.MSUF_GlobalDB.profiles[name]) or Suite.SuiteProfiles.SkinProfileExists(name) do
        name = base .. " " .. index
        index = index + 1
    end
    return name
end

local function ApplyClassic(profile, finish)
    local msuf = _G.MSUF_NS
    local frames = not Suite.Client.isForever and msuf
        and msuf.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
        or Suite.ClassicFactoryFramesCompact
    if type(frames) ~= "string" or type(profile) ~= "table" then
        return false, "Classic MSUF factory profile unavailable"
    end
    local skinEnabled = Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
    return Suite.SuiteProfiles.InstallFactory(NextFactoryName("Modern MSUF Suite"),
        frames, profile, skinEnabled and SkinPreset() or nil, AppliedLook(), finish,
        { screenHeight = false, preserveSkinLayout = true })
end

local function ApplyForever(profile, finish)
    local msuf = _G.MSUF_NS
    local frames = Suite.Client.isForever and msuf
        and msuf.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT
        or Suite.ForeverFactoryFramesCompact
    local skin = Suite.ForeverFactorySkinCompact
    if type(frames) ~= "string" or type(profile) ~= "table" then
        return false, "Forever factory profile unavailable"
    end
    local skinEnabled = Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
    -- Both Forever frame factories carry MSUF's own screen reference on every
    -- positioned frame, and MSUF adapts them from it. A second reference
    -- would scale positions MSUF has already adapted.
    return Suite.SuiteProfiles.InstallFactory(NextFactoryName("MSUF Suite Forever"), frames, profile,
        skinEnabled and skin or nil, AppliedLook(), finish,
        { screenHeight = false, preserveSkinLayout = true })
end

-- The scale the installer applies, decided once before anything commits:
-- MSUF's own frame scale back to 1 and, when chosen, the global UI scale
-- (the pixel preset takes the screen's current pixel-perfect scale).
local function ScaleSpec()
    if not useScale then return { msufScale = 1 } end
    if scalePreset == "pixel" and type(_G.MSUF_GetPixelPerfectScale) == "function" then
        scale = tonumber(_G.MSUF_GetPixelPerfectScale()) or scale
    end
    return { msufScale = 1, global = { preset = scalePreset, scale = scale } }
end

-- The profile install is the commit point. Every check that can refuse runs
-- before it (the scale through HostBridge.ScaleReady, the same answer on
-- both host paths, with MSUF's ranges). The scale goes to the installed
-- profile, so it is the transaction's last step (finish): should MSUF still
-- refuse it, the profile helpers roll the whole install back like any other
-- refusal. A failed attempt changes nothing, and a retry never installs a
-- second Forever profile.
function Installer.Apply()
    if Suite.InCombat() then return false, "Finish combat first." end
    if type(Suite.RootDB) ~= "table" then return false, "Suite database unavailable" end
    local spec = ScaleSpec()
    local ready, why = Suite.HostBridge.ScaleReady(spec)
    if not ready then return false, why end
    local profile, reason = PreparedProfile()
    if not profile then return false, reason end
    local function ApplyScale() return Suite.HostBridge.ApplyScale(spec) end
    local ok
    if keepFrames then
        ok, reason = ApplySuiteOnly(profile, ApplyScale)
    elseif selected == "forever" then
        ok, reason = ApplyForever(profile, ApplyScale)
    elseif selected == "classic" then
        ok, reason = ApplyClassic(profile, ApplyScale)
    else
        ok, reason = ApplySuiteOnly(profile, ApplyScale)
    end
    if not ok then return false, reason end
    local previous = Suite.RootDB.installation
    local getDefault = _G.MSUF_GetDefaultProfileForNewCharacters
    local carriedDefault = type(previous) == "table" and previous.newCharacterProfileOwned == true
        and type(getDefault) == "function" and getDefault() == previous.frameProfileName
    Suite.RootDB.installation = {
        revision = 4, status = "complete", profile = keepFrames and "suite" or selected,
        layout = selected == "forever" and "forever" or "retail",
        look = chosenLook or DefaultLook(), keepFrames = keepFrames,
        modernMeterMenuRevision = selected ~= "suite" and 2 or nil,
        modernPanelAnchorRevision = selected ~= "forever" and 1 or nil,
        resourceStackRevision = selected == "classic" and 1 or nil,
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
    Suite.SuiteProfiles.EnsureNewCharacterProfile()
    if selected ~= "classic" then Suite.SuiteProfiles.EnsureRetailResourceStack(true) end
    NotifyInstallerFinished()
    return true
end

local function Style(panel, selectedState, primary, accent)
    if accent then
        panel:SetBackdropColor(selectedState and 0.12 or 0.075,
            selectedState and 0.12 or 0.095, selectedState and 0.12 or 0.14, 1)
        panel:SetBackdropBorderColor(selectedState and accent[1] or 0.28,
            selectedState and accent[2] or 0.34, selectedState and accent[3] or 0.42, 1)
        return
    end
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

local function ProfileCard(parent, x, y, callback, colors)
    local card = Panel(parent, x, y, 508, 64, true)
    card.title = Label(card, "GameFontNormal", 16, -8, 370, 20)
    card.detail = Label(card, "GameFontHighlightSmall", 16, -29, 360, 29)
    card.mark = Label(card, "GameFontNormalSmall", 388, -8, 105, 20)
    card.mark:SetJustifyH("RIGHT")
    for index, hex in ipairs(colors or {}) do
        local swatch = card:CreateTexture(nil, "ARTWORK")
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetSize(16, 16)
        swatch:SetPoint("TOPLEFT", card, "TOPLEFT", 388 + (index - 1) * 25, -36)
        local r, g, b = Suite.RGB(hex)
        swatch:SetVertexColor(r, g, b, 1)
    end
    card:SetScript("OnClick", callback)
    return card
end

local function ToggleModule(id)
    local profile = FactoryProfile()
    local enabled = profile and ModuleEnabled(profile, id)
    if enabled == nil then return end
    moduleOverrides[selected][id] = not enabled
    Installer.Refresh()
end

------------------------------------------------------------------ window
-- The steps below create the window's regions in their original order, so
-- stacking and layout stay unchanged.
local function CreateWindow()
    local window = CreateFrame("Frame", "MSUFSuiteInstallFrame", _G.UIParent, "BackdropTemplate")
    window:SetSize(580, 470)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    -- MSUF's menu shares DIALOG strata (window level 10, its popups 400), and
    -- the host may open the installer while the menu is up. Set once, before
    -- the children exist: a fixed level never ratchets.
    window:SetFrameLevel(INSTALLER_FRAME_LEVEL)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    window:SetBackdropColor(0.035, 0.055, 0.085, 0.985)
    window:SetBackdropBorderColor(0.25, 0.43, 0.52, 1)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:Hide()
    window:SetScript("OnHide", function()
        if not Installer.IsFirstRunPending() then NotifyInstallerFinished() end
    end)
    Suite.Client.AttachControllerWindow(window)
    if Suite.Client.isForever then UISpecialFrames[#UISpecialFrames + 1] = "MSUFSuiteInstallFrame" end
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

-- Welcome cards and profile choice with the cooldown switch.
local function BuildProfileSteps(window)
    window.intro = {
        InfoCard(window, 36, 231, Text("1. Choose a Suite layout"),
            Text("Both Suite layouts work in Retail and Forever. Choose the layout first, then its colors.")),
        InfoCard(window, 36, 157, Text("2. Select modules"),
            Text("Keep the profile defaults or switch individual Suite modules on or off.")),
        InfoCard(window, 36, 83, Text("3. Set UI scale"),
            Text("Scaling starts off and changes only if you enable it.")),
    }
    Suite.InstallerProfiles.Build(window, Label, ProfileCard, NavButton, Style,
        function(layout)
            selected = layout
            Installer.Refresh()
        end,
        function(look)
            chosenLook = look
            Installer.Refresh()
        end, function(layout) return FactoryProfile(layout, true) end)
    local cooldowns = Panel(window, 36, 50, 508, 42, true)
    cooldowns.title = Label(cooldowns, "GameFontNormal", 14, -7, 360, 17)
    cooldowns.detail = Label(cooldowns, "GameFontHighlightSmall", 14, -24, 460, 15)
    cooldowns.mark = Label(cooldowns, "GameFontNormalSmall", 388, -7, 105, 18)
    cooldowns.mark:SetJustifyH("RIGHT")
    cooldowns:SetScript("OnClick", function()
        useRaidEssentials = not useRaidEssentials
        Installer.Refresh()
    end)
    window.cooldowns = cooldowns
    Suite.InstallerModules.Build(window, Panel, Label, NavButton, Style, ToggleModule)
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
    -- UISliderTemplateWithLabels (via OptionsSliderTemplate) on both clients.
    slider.Low:Hide()
    slider.High:Hide()
    slider.Text:Hide()
    slider:SetObeyStepOnDrag(true)
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
    window.keepFrames = NavButton(window, 36, 78, 508, "", function()
        keepFrames = not keepFrames
        Installer.Refresh()
    end)
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
            window.status:SetText("|cffff6666" .. (reason and ReasonText(reason) or Text("Installation failed")) .. "|r")
            return
        end
        page = 6
        Installer.Refresh()
    else
        ReloadUI()
    end
end

local function BuildNavigation(window)
    window.status = Label(window, "GameFontHighlightSmall", 36, -403, 508, 17)
    window.back = NavButton(window, 36, 15, 104, Text("Back"), function()
        page = math.max(1, page - 1)
        Installer.Refresh()
    end)
    window.close = NavButton(window, 150, 15, 104, Text("Not now"), function()
        -- Only a pending first run is skipped: setup reopened later through
        -- /msufsuite keeps its completed receipt.
        if Suite.RootDB and page ~= 6 and Installer.IsFirstRunPending() then
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
    Suite.InstallerProfiles.Show(f, page == 2, selected, chosenLook or "authored")
    f.cooldowns:SetShown(page == 2 and RetailCooldowns())
    Suite.InstallerModules.Show(f, page == 3)
    f.keepFrames:SetShown(scaling)
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
-- The chosen factory profile for the preview pages, read-only (never
-- copied). A reason the install would refuse is shown in the status line.
local function PreviewProfile(f)
    local profile, reason = FactoryProfile()
    if profile then reason = InstallBlocker(profile) end
    if reason then
        f.status:SetText("|cffff6666" .. ReasonText(reason) .. "|r")
        return nil
    end
    return profile
end

local function PaintWelcome(f)
    SetPageText(f, "Welcome to MSUF Suite",
        "Set up your interface in a few steps. Nothing changes until you click Install.")
end

local function PaintProfiles(f)
    SetPageText(f, "Choose a Suite layout", "Both Suite layouts work in Retail and Forever. Choose the layout first, then its colors.")
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
        local enabled = profile ~= nil and ModuleEnabled(profile, row.id) == true
        Style(row, enabled)
        row.state:SetText(enabled and Text("ON") or Text("OFF"))
    end
end

local function PaintScaling(f)
    f.keepFrames.caption:SetText(Text("Keep current MSUF frames: %s"):format(keepFrames and Text("ON") or Text("OFF")))
    Style(f.keepFrames, keepFrames)
    SetPageText(f, "Frames and UI scale",
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
    for _, id in ipairs(Suite.SuiteOrder) do
        total = total + 1
        if profile and ModuleEnabled(profile, id) then enabled = enabled + 1 end
    end
    local summary = Text("%d / %d enabled"):format(enabled, total)
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
    f.review[1].detail:SetText(Text("%s · Colors: %s · %s"):format(
        selected == "forever" and Text("MSUF Suite Forever") or Text("Modern MSUF Suite"),
        Suite.InstallerProfiles.LookLabel(chosenLook),
        keepFrames and Text("Current MSUF frames") or Text("Factory MSUF frames")))
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
    if Suite.InCombat() then return false, "combat" end
    selected = Suite.Client.isForever and "forever" or "classic"
    chosenLook, keepFrames = nil, false
    local active = DB.GetProfile(DB.GetActiveProfileName())
    local current = active and active.suite and active.suite.modules
        and active.suite.modules.cooldownManager
    useScale, scale, scalePreset, page = false, 1, "custom", 1
    useRaidEssentials = not (current and current.raidEssentials == false)
    moduleOverrides = { suite = {}, classic = {}, forever = {} }
    Build().moduleTab = "modules"
    -- A reopened window still shows the last session's slider position.
    frame.scaleSlider:SetValue(scale)
    Installer.Refresh()
    frame.moduleScroll:SetVerticalScroll(0)
    frame:Show()
    Suite.Client.ResumeControllerWindow(frame)
    Suite.Client.RaiseControllerCursor()
    return true
end
-- At login, wait for Classic MSUF's welcome/Quick Setup/import to resolve.
-- The host hands off with MaybeShow(); /msufsuite opens setup at any time.
local function HostFirstRunPending()
    if Suite.Host.build ~= "Classic" then return false end
    local firstLoad = _G.MSUF_NS.FirstLoad6
    return type(firstLoad) == "table" and type(firstLoad.IsFirstRunPending) == "function"
        and firstLoad:IsFirstRunPending() == true
end

function Installer.MaybeShow(reason)
    if not IsLoggedIn() then return false end
    if frame and frame:IsShown() then return false end
    if Installer.IsFirstRunPending() and not (reason == "login" and HostFirstRunPending()) then
        return Installer.Open()
    end
    return false
end

_G.SLASH_MSUFSUITEINSTALL1 = "/msufsuite"
_G.SlashCmdList.MSUFSUITEINSTALL = function(message)
    message = type(message) == "string" and message:match("^%s*(.-)%s*$"):lower() or ""
    if message == "" or message == "install" then
        local _, reason = Installer.Open()
        if reason == "combat" then Suite.Print(Text("Finish combat first.")) end
    else
        Suite.Print("/msufsuite install")
    end
end
