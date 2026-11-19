local root = assert(arg[1])
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local MODES = { "class", "dark", "unified" }
local UNIT_COLOR, GROUP_COLOR = "336699", "cc3366"
local authored = { general = { barMode = "dark", darkBarGray = .2,
    unifiedBarR = .1, unifiedBarG = .6, unifiedBarB = .9, font = "Expressway" },
    player = { healthColorMode = "DARK", width = 310, offsetX = -320 },
    target = { healthColorMode = "CLASS", width = 280 }, arena3 = { healthColorMode = "GRADIENT" },
    targettarget = { healthColorMode = "CLASS", anchorToUnitframe = "target", width = 138, height = 16 },
    gf_party = { gfBarMode = "GLOBAL", width = 120 }, gf_raid = { gfBarMode = "CUSTOM", width = 80 },
    gf_mythicraid = { gfBarMode = "CLASS", gfUnifiedR = .8 }, bars = { classPowerWidth = 340 } }

local function Setup(forever)
    local Suite = H.Setup({ root = root, forever = forever })
    ColorPickerFrame = H.Widget("Frame")
    ColorPickerFrame:Hide()
    function ColorPickerFrame:SetupColorPickerAndShow(info)
        self.r, self.g, self.b = info.r, info.g, info.b
        self.swatchFunc, self.cancelFunc = info.swatchFunc, info.cancelFunc
        self:Show()
    end
    function ColorPickerFrame:GetColorRGB() return self.r, self.g, self.b end
    local encoded, serial = {}, 0
    local decode, encode = MSUF_TryDecodeCompactString, MSUF_EncodeCompactTable
    MSUF_TryDecodeCompactString = function(text)
        if encoded[text] then return Copy(encoded[text]) end
        if text == "MSUF3:frames" then
            return { addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = Copy(MSUF_DB) }
        end
        if text == Suite.ClassicFactoryFramesCompact or text == Suite.ForeverFactoryFramesCompact
            or text == Suite.ModernDarkFramesCompact then
            return { addon = "MSUF", fmt = 2, schema = 1, kind = "all", payload = { player = { width = 1 } },
                msuf6 = { schema = 600, kind = "all", payload = Copy(authored) } }
        end
        return decode(text)
    end
    MSUF_EncodeCompactTable = function(value, prefix)
        if not value.payload then return encode(value, prefix) end
        assert(prefix == "MSUF3", "frame color staging used the wrong export prefix")
        serial = serial + 1
        local key = "MSUF3:styled" .. serial
        encoded[key] = Copy(value)
        return key
    end
    MSUF_Profiles_ImportIntoNewProfile = function(name, compact)
        local envelope = assert(MSUF_TryDecodeCompactString(compact))
        -- Like the native importer, accept the canonical embedded snapshot.
        -- A bad codec fallback must reach our no-write assertion, rather than
        -- fail incidentally because the fixture rejects a valid Wago wrapper.
        envelope = MSUF_NS.ProfilePolicy and MSUF_NS.ProfilePolicy.SelectSupportedDecodedProfile(envelope)
            or envelope.msuf6 or envelope
        assert(envelope.kind == "all" and envelope.schema == 600, "color selection destroyed the import envelope")
        MSUF_GlobalDB.profiles[name] = Copy(envelope.payload)
        MSUF_ActiveProfile, MSUF_DB = name, MSUF_GlobalDB.profiles[name]
        return true
    end
    if forever then
        MSUF_NS.ProfilePolicy = { SelectSupportedDecodedProfile = function(envelope)
            if not envelope then return nil end
            local full = envelope.msuf6
            if not full then return envelope end
            return { addon = "MSUF", fmt = 2, schema = full.schema, kind = full.kind, payload = full.payload }
        end }
    end
    assert(Suite.Installer.Open())
    return Suite, assert(MSUFSuiteInstallFrame)
end

local function Choice(window, index, mode)
    for _, button in ipairs(window.layoutPreview.frameColors[index].buttons) do
        if button.mode == mode then return button end
    end
    error("missing color choice " .. mode)
end

local function Choose(Suite, window, index, mode, cancel)
    local button = Choice(window, index, mode)
    assert(button:IsShown(), "frame color control is hidden")
    button.scripts.OnClick()
    if mode ~= "unified" then return end
    local picker = ColorPickerFrame
    assert(picker:IsShown() and window:GetFrameStrata() == "HIGH", "Unified did not open the picker in front of setup")
    picker.r, picker.g, picker.b = Suite.RGB(index == 1 and UNIT_COLOR or GROUP_COLOR)
    picker.swatchFunc()
    if cancel then picker.cancelFunc() end
    picker:Hide()
    assert(window:GetFrameStrata() == "DIALOG", "closing the picker did not restore setup")
end

for _, forever in ipairs({ false, true }) do
    for _, layout in ipairs({ "classic", "forever", "modernDark" }) do
        for _, unit in ipairs(MODES) do
            for _, group in ipairs(MODES) do
                local Suite, window = Setup(forever)
                window.next.scripts.OnClick() -- layouts
                window[layout].scripts.OnClick()
                window.next.scripts.OnClick() -- modules
                window.next.scripts.OnClick() -- frame choices + scale
                local rows = assert(window.layoutPreview.frameColors, "setup has no independent frame color choices")
                assert(#rows == 2 and #rows[1].buttons == 4 and #rows[2].buttons == 4)
                local beforeFrames, beforeSuite = Copy(MSUF_DB), Copy(Suite.RootDB)
                local source = Suite.HostBridge.FactoryFramePreview(layout)
                local pristine = Copy(source)
                Choose(Suite, window, 1, unit)
                Choose(Suite, window, 2, group)
                assert(Equal(source, pristine) and Equal(MSUF_DB, beforeFrames)
                    and Equal(Suite.RootDB, beforeSuite), "staging changed the saved or cached profiles")
                local sample, tot
                for _, region in ipairs(window.layoutPreview.regions) do
                    if region.label == "Player" then sample = region end
                    if region.label == "Target of Target" then tot = region end
                end
                assert(sample, "player preview missing")
                local expected = unit == "class" and "c79c6e" or unit == "dark" and "333333" or UNIT_COLOR
                local r, g, b = Suite.RGB(expected)
                assert(math.abs(sample.fill.color[1] - r) < .00001
                    and math.abs(sample.fill.color[2] - g) < .00001
                    and math.abs(sample.fill.color[3] - b) < .00001, "unit preview ignores the staged frame color: " .. layout .. "/" .. unit .. "/" .. group .. " " .. table.concat(sample.fill.color, ","))
                assert(tot and math.abs(tot.fill.color[1] - r) < .00001
                    and math.abs(tot.fill.color[2] - g) < .00001 and math.abs(tot.fill.color[3] - b) < .00001,
                    "target-of-target preview ignores the staged frame color")
                window.back.scripts.OnClick()
                window.back.scripts.OnClick()
                window[layout == "classic" and "forever" or "classic"].scripts.OnClick()
                window[layout].scripts.OnClick()
                assert(Suite.InstallerFrameColors.Choices().unit == unit
                    and Suite.InstallerFrameColors.Choices().group == group, "layout switching lost explicit frame colors")
                assert(Suite.Installer.Apply())
                assert(MSUF_DB.general.barMode == unit and MSUF_DB.general.darkMode == (unit == "dark")
                    and MSUF_DB.general.useClassColors == (unit == "class"))
                for _, key in ipairs({ "player", "target", "targettarget", "arena3" }) do
                    assert(MSUF_DB[key].healthColorMode == unit:upper(), "unit override won over the install choice")
                end
                for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
                    assert(MSUF_DB[key].gfBarMode == (group == "class" and "CLASS" or group))
                end
                local comparable = Copy(MSUF_DB)
                comparable.general.barMode, comparable.general.darkMode, comparable.general.useClassColors =
                    authored.general.barMode, nil, nil
                for _, key in ipairs({ "player", "target", "targettarget", "arena3" }) do
                    comparable[key].healthColorMode = authored[key].healthColorMode
                end
                for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
                    comparable[key].gfBarMode = authored[key].gfBarMode
                    if group == "unified" then
                        local r, g, b = Suite.RGB(GROUP_COLOR)
                        assert(comparable[key].gfUnifiedR == r and comparable[key].gfUnifiedG == g and comparable[key].gfUnifiedB == b)
                        comparable[key].gfUnifiedR, comparable[key].gfUnifiedG, comparable[key].gfUnifiedB =
                            authored[key].gfUnifiedR, authored[key].gfUnifiedG, authored[key].gfUnifiedB
                    end
                end
                if unit == "unified" then
                    assert(Suite.InstallerFrameColors.HealthFill(MSUF_DB, "unit") == UNIT_COLOR)
                    comparable.general.unifiedBarR, comparable.general.unifiedBarG, comparable.general.unifiedBarB =
                        authored.general.unifiedBarR, authored.general.unifiedBarG, authored.general.unifiedBarB
                end
                assert(Equal(comparable, authored), "frame colors changed layout, fonts, power bars or custom palette values")
                assert(Suite.RootDB.installation.frameColors.unit == unit
                    and Suite.RootDB.installation.frameColors.group == group)
                assert(Suite.Installer.Open() and Suite.InstallerFrameColors.Choices() == nil,
                    "reopened setup inherited the last session's color overrides")
            end
        end
    end
    local Suite, window = Setup(forever)
    window.next.scripts.OnClick()
    window.next.scripts.OnClick()
    window.next.scripts.OnClick()
    MSUF_DB.player = { width = 310, offsetX = -320 }
    window.keepFrames.scripts.OnClick()
    local before = Copy(MSUF_DB)
    local old = MSUF_DB
    assert(window.layoutPreview.frameColorHint:IsShown())
    Choose(Suite, window, 1, "class")
    Choose(Suite, window, 1, "unified", true)
    assert(Suite.InstallerFrameColors.Choices().unit == "class", "Cancel lost the previous choice")
    Choose(Suite, window, 1, "unified")
    Choose(Suite, window, 2, "unified")
    Choose(Suite, window, 2, "profile")
    assert(Suite.InstallerFrameColors.Choices().group == nil, "Profile colors did not clear the override")
    H.combat = true
    assert(not Suite.Installer.Apply() and Equal(MSUF_DB, before), "combat install mutated frame settings")
    H.combat = false
    assert(Suite.Installer.Apply())
    assert(Equal(old, before) and MSUF_DB ~= old and Equal(MSUF_DB.player,
        { width = 310, offsetX = -320, healthColorMode = "UNIFIED" }), "keep frames did not preserve the layout in a separate profile")
    assert(Suite.RootDB.installation.frameColors.unitColor == UNIT_COLOR)
    assert(Suite.HostBridge.StyleFrameFactory("MSUF3:bad", { unit = "invalid" }) == nil)
    assert(Suite.HostBridge.StyleFrameFactory("MSUF3:frames", { unit = "unified", unitColor = "bad" }) == nil)
    assert(#H.reported == 0, "frame color setup raised errors")
    H.combat = false
    assert(Suite.Installer.Open())
    window.next.scripts.OnClick()
    window.next.scripts.OnClick()
    window.next.scripts.OnClick()
    Choose(Suite, window, 1, "dark")
    local saved = Copy(Suite.RootDB)
    local active = MSUF_ActiveProfile
    local encode = MSUF_EncodeCompactTable
    MSUF_EncodeCompactTable = nil
    assert(not Suite.Installer.Apply() and Equal(Suite.RootDB, saved) and MSUF_ActiveProfile == active,
        "missing encoder installed an unstyled factory or changed profiles")
    MSUF_EncodeCompactTable = function() return nil end
    assert(not Suite.Installer.Apply() and Equal(Suite.RootDB, saved) and MSUF_ActiveProfile == active,
        "refusing encoder installed an unstyled factory")
    MSUF_EncodeCompactTable = encode
    local policy = MSUF_NS.ProfilePolicy
    MSUF_NS.ProfilePolicy = { SelectSupportedDecodedProfile = function() return nil end }
    assert(not Suite.Installer.Apply() and Equal(Suite.RootDB, saved) and MSUF_ActiveProfile == active,
        "host profile policy refusal fell back to a legacy payload")
    MSUF_NS.ProfilePolicy = policy
    local scaleApply = Suite.HostBridge.ApplyScale
    Suite.HostBridge.ApplyScale = function() return false, "failed" end
    assert(not Suite.Installer.Apply() and Equal(Suite.RootDB, saved) and MSUF_ActiveProfile == active,
        "failed final scale step did not roll back frame colors and installed profiles")
    Suite.HostBridge.ApplyScale = scaleApply
    local inherited = { general = { barMode = "class" }, player = { healthColorMode = "DARK" }, target = {} }
    assert(Suite.InstallerFrameColors.HealthFill(inherited, "unit", inherited.target) == "c79c6e",
        "unoverridden target inherited the player's override instead of the global mode")
    for _, layout in ipairs({ "classic", "forever", "modernDark" }) do
        for scope = 1, 2 do
            for _, mode in ipairs(MODES) do
                local stagedSuite, stagedWindow = Setup(forever)
                stagedWindow.next.scripts.OnClick()
                stagedWindow[layout].scripts.OnClick()
                stagedWindow.next.scripts.OnClick()
                stagedWindow.next.scripts.OnClick()
                local source = stagedSuite.HostBridge.FactoryFramePreview(layout)
                local unchosen = scope == 1 and "group" or "unit"
                local beforeColor = stagedSuite.InstallerFrameColors.HealthFill(source, unchosen)
                Choose(stagedSuite, stagedWindow, scope, mode)
                local preview = stagedSuite.InstallerFrameColors.Preview(source)
                assert(stagedSuite.InstallerFrameColors.HealthFill(preview, unchosen) == beforeColor,
                    "single-scope choice changed the other frame preview")
                assert(stagedSuite.Installer.Apply())
                assert(stagedSuite.InstallerFrameColors.HealthFill(MSUF_DB, unchosen) == beforeColor,
                    "single-scope install changed the other frame coloring")
            end
        end
    end
end
print("installer frame colors: 54 paired + 36 single-scope client/layout/mode combinations, preview, retention and reopen passed")
