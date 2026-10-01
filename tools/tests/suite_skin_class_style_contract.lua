local root = assert(arg[1], "Suite root required")

local classes = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1.00, 0.96, 0.41 },
    PRIEST = { 1, 1, 1 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 },
    WARLOCK = { 0.53, 0.53, 0.93 }, MONK = { 0, 1, 0.60 },
    DRUID = { 1, 0.49, 0.04 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER = { 0.20, 0.58, 0.50 },
}
local function SameColor(actual, expected, message)
    assert(actual, message .. ": missing color")
    for channel = 1, 3 do
        assert(math.abs(actual[channel] - expected[channel]) < 0.000001, message)
    end
end
local function Noop() end
local function Load(name, ns)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. name .. ".lua"))("MSUF_Suite_Skin", ns)
end

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local token, classReads, colorReads = "ROGUE", 0, 0
    UnitClass = function(unit)
        assert(unit == "player", "Class Style queried another unit")
        classReads = classReads + 1
        return token, token
    end
    C_ClassColor = { GetClassColor = function(classToken)
        colorReads = colorReads + 1
        local color = classes[classToken]
        return color and { r = color[1], g = color[2], b = color[3], a = 1 }
    end }
    RAID_CLASS_COLORS = {}
    _G.MSUFSuite = nil
    -- The skin's profile names follow the Suite's rule (MSUF_Suite/Core/Database.lua).
    dofile(root .. "/tools/tests/suite_test_support.lua").SuiteProfileNames(root)
    local ns = {
        Client = { isMainline = true, isForever = flavor == "Forever" },
        IsCombatLocked = function() return false end,
        Registry = { QueueRefresh = Noop, NotifyListeners = Noop, RefreshAll = Noop },
        Safety = { Dispatch = function(callback, ...) return callback(...) end },
        Typography = { Restore = Noop, ApplyConfigured = Noop },
        Adapters = { ApplyAll = Noop },
    }
    Load("Defaults", ns)
    Load("Database", ns)
    Load("DatabaseProfiles", ns)
    Load("Theme", ns)
    ns.DB = ns.CopyValue(ns.Defaults)
    local theme = ns.Theme
    assert(ns.LookOrder[5] == "classColor" and ns.LookPresets.classColor.label == "Class Style",
        "Class Style is absent from the public catalog")
    for index, name in ipairs({ "cleanModern", "midnight", "foreverGlass", "midnightDark" }) do
        assert(ns.LookOrder[index] == name, "Class Style removed or renumbered an existing look")
    end
    assert(ns.PaletteOrder[4] == "classColor" and ns.PaletteLabels.classColor == "Class Color",
        "the existing Class Color palette was renamed or removed")

    -- The installer prepares a real class palette without modifying the
    -- currently active profile or its independently owned color tables.
    local originalColors = ns.DB.theme.colors
    local savedClass = ns.CopyValue(ns.Defaults)
    assert(theme.StyleProfile(savedClass, "classColor"), "installer rejected Class Style")
    SameColor(savedClass.theme.colors.accent, classes.ROGUE, "installer lost the class accent")
    SameColor(savedClass.theme.colors.microIconPressed, classes.ROGUE,
        "installer did not seed class-colored Micro Bar tokens")
    assert(ns.DB.theme.colors == originalColors and ns.DB.theme.look == "cleanModern",
        "styling an installer profile changed the active theme")

    -- A shared saved profile can still contain the last character's colors.
    -- Run the real login handler after changing the current character.
    ns.RootDB = { activeProfile = "Class", profiles = { Class = savedClass,
        Alt = ns.CopyValue(savedClass), Modern = ns.CopyValue(ns.Defaults) } }
    ns.DB = savedClass
    ns.Database.Initialize = function() return ns.DB end
    ns.InitializeLocalization = Noop
    ns.PublicAPI = { OnDatabaseReady = Noop, OnPlayerLogin = Noop }
    ns.BlizzardYellow, ns.Checkmarks = { Apply = Noop }, { Apply = Noop }
    ns.ChatFramesSkin = { RestoreBlizzardMessageColors = Noop }
    local lifecycle
    CreateFrame = function()
        lifecycle = { events = {} }
        function lifecycle:RegisterEvent(event) self.events[event] = true end
        function lifecycle:UnregisterEvent(event) self.events[event] = nil end
        function lifecycle:SetScript(script, callback)
            assert(script == "OnEvent", "Class Style introduced a frame polling script")
            self[script] = callback
        end
        return lifecycle
    end
    IsLoggedIn = function() return false end
    Load("Lifecycle", ns)
    lifecycle:OnEvent("ADDON_LOADED", "MSUF_Suite_Skin")
    token = "MAGE"
    lifecycle:OnEvent("PLAYER_LOGIN")
    SameColor(theme.GetColorTable("accent"), classes.MAGE,
        "login retained the previous character's class")
    SameColor(theme.GetColorTable("microIconPressed"), classes.MAGE,
        "Micro Bar remained on its named blue palette at login")
    assert(not lifecycle.events.PLAYER_LOGIN and not lifecycle.events.ADDON_LOADED,
        "Class Style kept one-shot startup events registered")

    -- Paint paths must return the installed tokens, not rebuild a palette or
    -- ask Blizzard for the player class on every texture or hover repaint.
    local readsBefore, colorsBefore = classReads, colorReads
    local accent, micro = theme.GetColorTable("accent"), theme.GetColorTable("microIconPressed")
    collectgarbage("collect")
    collectgarbage("stop")
    local memoryBefore = collectgarbage("count")
    for _ = 1, 10000 do
        assert(theme.GetColorTable("accent") == accent)
        assert(theme.GetColorTable("microIconPressed") == micro)
        theme.GetPlayerClassColor()
    end
    local growth = collectgarbage("count") - memoryBefore
    collectgarbage("restart")
    assert(classReads == readsBefore and colorReads == colorsBefore,
        "color reads repeatedly queried the player's class")
    assert(growth < 1, ("cached class color reads allocated %.2f KB"):format(growth))

    token = "PRIEST"
    assert(ns.Database.SetActiveProfile("Alt"), "class profile switch failed")
    SameColor(theme.GetColorTable("accent"), classes.PRIEST,
        "profile activation retained the previous character's colors")
    SameColor(theme.GetColorTable("microIconPressed"), classes.PRIEST,
        "profile activation left the Micro Bar with stale class colors")

    -- Every class keeps the broad surfaces dark, including a white Priest.
    -- Semantic warning/danger/success colors and item quality stay intact.
    for classToken, color in pairs(classes) do
        token = classToken
        assert(theme.ApplyLook("classColor"), "cannot apply " .. classToken .. " Class Style")
        SameColor(theme.GetColorTable("accent"), color, "wrong " .. classToken .. " accent")
        SameColor(theme.GetColorTable("checkmark"), color, "wrong " .. classToken .. " checkmark")
        for _, key in ipairs({ "background", "popup", "input", "surface", "buttonFill", "microBarFill" }) do
            local fill = theme.GetColorTable(key)
            assert(math.max(fill[1], fill[2], fill[3]) < 0.25,
                classToken .. " made a broad surface too bright: " .. key)
        end
        for _, key in ipairs({ "warning", "danger", "success" }) do
            SameColor(theme.GetColorTable(key), ns.BaseColors[key], "class look replaced semantic " .. key)
        end
        assert(ns.DB.theme.iconBorderStyle == "quality", "Class Style replaced item quality colors")
    end

    -- The installer and the look switch install a look through one routine:
    -- a styled installer profile matches the active profile after ApplyLook.
    for _, lookName in ipairs(ns.LookOrder) do
        token = "MAGE"
        local styled = ns.CopyValue(ns.DB)
        assert(theme.StyleProfile(styled, lookName) and theme.ApplyLook(lookName))
        for key, color in pairs(ns.DB.theme.colors) do
            SameColor(styled.theme.colors[key], color, lookName .. ": the installer and the look differ in " .. key)
        end
        assert(styled.theme.look == ns.DB.theme.look and styled.theme.preset == ns.DB.theme.preset
            and styled.icons.microMenu.preset == ns.DB.icons.microMenu.preset
            and styled.geometry.radius == ns.DB.geometry.radius
            and styled.theme.shellOpacity == ns.DB.theme.shellOpacity,
            lookName .. ": the installer and the look install different settings")
    end
    local themeFile = assert(io.open(root .. "/MSUF_Suite_Skin/Core/Theme.lua", "rb"))
    local _, seedings = themeFile:read("*a"):gsub("pairs%(NS%.MicroColorSources%)", "")
    themeFile:close()
    assert(seedings == 1, "Theme.lua installs a palette in " .. seedings .. " places")

    -- A hand edit turns the look custom. A modern Micro Bar that showed the
    -- look's own colours (Class Style, Clean Modern) keeps them instead of
    -- flipping to the named Midnight palette.
    for _, lookName in ipairs({ "classColor", "cleanModern" }) do
        token = "ROGUE"
        assert(theme.ApplyLook(lookName), "cannot apply " .. lookName)
        local pressed = ns.CopyValue(theme.GetColorTable("microIconPressed"))
        local fill = ns.CopyValue(theme.GetColorTable("microBarFill"))
        assert(theme.SetColor("text", 0.5, 0.5, 0.5, 1))
        SameColor(theme.GetColorTable("microIconPressed"), pressed,
            lookName .. ": an unrelated colour edit changed the Micro Bar")
        assert(theme.SetAppearance("shellOpacity", 0.8))
        SameColor(theme.GetColorTable("microBarFill"), fill,
            lookName .. ": an opacity change changed the Micro Bar")
        assert(ns.DB.theme.look == "custom", lookName .. ": a hand edit kept the named look")
    end
    assert(theme.ApplyLook("midnight"))
    local midnightPressed = ns.CopyValue(theme.GetColorTable("microIconPressed"))
    assert(theme.SetAppearance("panelOpacity", 0.9) and ns.DB.icons.microMenu.preset == "modern",
        "a hand edit under Midnight Blue changed the Micro Bar style")
    SameColor(theme.GetColorTable("microIconPressed"), midnightPressed,
        "a hand edit under Midnight Blue changed the Micro Bar colours")

    -- Explicit Micro Bar looks are independent. The Class Style default
    -- modern artwork is the one that follows the installed class palette.
    for _, entry in ipairs({ { "midnightDark", "midnightDark" }, { "forever", "foreverGlass" } }) do
        ns.DB.icons.microMenu.preset = entry[1]
        SameColor(theme.GetColorTable("microIconPressed"),
            ns.PresetOverrides[entry[2]].microIconPressed or ns.PresetOverrides[entry[2]].accent,
            "Class Style overrode the independent Micro Bar " .. entry[1] .. " palette")
    end
    assert(theme.ApplyLook("midnight"))
    SameColor(theme.GetColorTable("microIconPressed"), ns.BaseColors.accent,
        "switching back to Blue retained class Micro Bar colors")
    assert(theme.ApplyLook("cleanModern"))
    SameColor(theme.GetColorTable("microBarFill"), ns.PresetOverrides.cleanModern.microBarFill
        or ns.PresetOverrides.cleanModern.background,
        "switching back to Clean Modern retained class Micro Bar colors")
    assert(ns.Database.SetActiveProfile("Modern"))
    local modernColors = ns.DB.theme.colors
    token = "ROGUE"
    assert(not theme.RefreshDynamicLook() and ns.DB.theme.colors == modernColors,
        "a static look was replaced by the current class")
end

print("Class Style: login, profile/installer, 13 classes, Micro Bar switches and cached reads passed")
