-- The real Platform provider and companion TOCs, independent of the host's client language.
local root = assert(arg[1])
local provider = arg[2] or root .. "/MSUF_Suite/Core/Platform.lua"
local locales = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local translated = {}
for i = 3, #locales do translated[locales[i]] = true end
local checks, values = 0, 0
local function Same(a, b)
    for key, value in pairs(a) do assert(rawget(b, key) == value, "lost or changed translation"); values = values + 1 end
    for key, value in pairs(b) do assert(rawget(a, key) == value, "unexpected translation") end
end
local function Dictionary()
    return setmetatable({ ["Reset %s"] = "HOST WINS", Font = "Font", ["Icon size"] = "" }, { __index = function(_, key) return key end })
end
local function Run(locale, forever, legacy, state, clientLocale)
    local L, expected = Dictionary(), Dictionary()
    local host = { LOCALE = locale, L = L }
    if not legacy then
        host.Client = { Flavor = "Mainline", IsForever = forever, SupportsEvent = function() return true end }
        host.RegisterLocale = function(wanted) assert(wanted == locale); return L end
    end
    local loads, messages, loaded, nested = {}, {}, {}, 0
    local env = setmetatable({ MSUF_NS = host, WOW_PROJECT_ID = 1, WOW_PROJECT_MAINLINE = 1,
        GetLocale = function() return clientLocale end, IsLoggedIn = function() return true end,
        InCombatLockdown = function() return state == "combat" end,
        GameEvent = forever and { RegisterCamelotEvents = function() end } or nil,
        CreateFrame = function() error("locale loading allocated a frame") end,
        DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end },
    }, { __index = _G })
    env._G = env
    env.C_AddOns = {
        IsAddOnLoaded = function(name)
            -- Finished is authoritative on Forever, even with a diagnostic first result.
            return not forever and loaded[name] == true, loaded[name] == true
        end,
        LoadAddOn = function(name)
            loads[#loads + 1] = name
            assert(name == "MSUF_Suite_Locale_" .. locale, "loaded an inactive language")
            if state == "missing" or state == "disabled" or state == "outdated" then return false, state:upper() end
            if not loaded[name] then
                assert(Support.LoadLocaleAddon(root, name, env))
                loaded[name] = true
                -- A nested ADDON_LOADED may arrive before the Suite is public.
                assert(rawget(env, "MSUFSuite") == nil)
                nested = nested + 1
            end
            if forever then return nil, "FOREVER_DIAGNOSTIC" end
            return true
        end,
    }
    if translated[locale] and state ~= "missing" and state ~= "disabled" and state ~= "outdated" then
        local expectedHost = { LOCALE = locale, L = expected,
            RegisterLocale = not legacy and function() return expected end or nil }
        local expectedEnv = setmetatable({ MSUF_NS = expectedHost }, { __index = _G })
        expectedEnv._G = expectedEnv
        setfenv(assert(loadfile(root .. "/MSUF_Suite/Locales/" .. locale .. ".lua")), expectedEnv)()
        if state == "preloaded" then
            assert(Support.LoadLocaleAddon(root, "MSUF_Suite_Locale_" .. locale, env))
            loaded["MSUF_Suite_Locale_" .. locale] = true
        end
    end
    local owner = {}
    setfenv(assert(loadfile(provider)), env)("MSUF_Suite", owner)
    Same(expected, L)
    assert(owner.L == L and host.LOCALE == locale and owner.startupError == nil)
    assert(owner.Text("Reset %s") == "HOST WINS" and owner.Text("Icon size") == "Icon size")
    assert(rawget(L, "Icon size") == "", "existing empty host value was overwritten")
    if translated[locale] then
        assert(#loads == 1, "selected translated language was not loaded exactly once")
        local failure = state == "missing" or state == "disabled" or state == "outdated"
        assert(#messages == (failure and 1 or 0), "locale failure was silent or successful load warned")
        assert(nested == ((failure or state == "preloaded") and 0 or 1))
    else
        assert(#loads == 0 and #messages == 0, "English/unknown locale loaded a companion")
    end
    checks = checks + 1
end
for _, locale in ipairs(locales) do
    for _, forever in ipairs({ false, true }) do
        for _, legacy in ipairs({ false, true }) do
            Run(locale, forever, legacy, "normal", locale)
            Run(locale, forever, legacy, "combat", locale == "enUS" and "deDE" or "enUS")
        end
    end
    if translated[locale] then
        for _, state in ipairs({ "preloaded", "missing", "disabled", "outdated" }) do
            Run(locale, false, false, state, "enUS")
            Run(locale, true, true, state, "frFR")
        end
    end
end
Run("xxXX", false, true, "normal", "deDE")
Run(nil, false, false, "normal", "enUS")
-- Boot the actual Core through installer/profile providers in every language on both clients.
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
for _, locale in ipairs(locales) do
    for _, forever in ipairs({ false, true }) do
        local L = Dictionary()
        local suite = H.Setup({ root = root, forever = forever, msuf = { LOCALE = locale, L = L } })
        assert(suite.L == L and suite.Database.GetActiveProfileName() == "Default")
        local title = suite.Text(suite.ActionBarTitles[9])
        assert(BINDING_HEADER_MSUFSUITE_BAR9 == title, "binding header captured before translation")
        assert(BINDING_NAME_MSUFSUITE_BAR9_BUTTON1 == suite.Text("%s button %d"):format(title, 1))
        assert(suite.Suite.catalog.cooldownManager)
        assert(#H.reported == 0 and #H.chat == 0, "translated core boot raised or warned")
        checks = checks + 1
    end
end
print(string.format("Suite locale loader: %d lifecycle/core cases, %d raw values; all12languages, both hosts/clients, errors/combat/preload passed", checks, values))
