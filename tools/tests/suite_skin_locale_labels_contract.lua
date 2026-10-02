-- The skin's user-facing names reach the player through its locale tables:
-- every look and palette name and description, the font choices and the
-- Class Style label exist in the skin's English table and in the Suite's
-- German pack (the skin translates through the Suite), the options show them
-- localized (a German search for "Klassenstil" finds the style preset), and
-- no setter in the skin's code shows a hard-coded English literal.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function ReadFile(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local english = Support.SkinEnglish(root)
local German, _, germanPack = Support.SkinLocale(root, "deDE")
local function Translated(text, what)
    Check(english[text] ~= nil and (germanPack[text] ~= nil or Support.SKIN_SAME_IN_GERMAN[text]),
        what .. " is missing from the locale tables: " .. tostring(text))
end

-- Names and descriptions shown from the engine's catalogs.
local NS = { Client = { isForever = false, isMainline = true } }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
for name, look in pairs(NS.LookPresets) do
    Translated(look.label, "the name of look " .. name)
    Translated(look.description, "the description of look " .. name)
end
for key, label in pairs(NS.PaletteLabels) do Translated(label, "the name of palette " .. key) end
local faces = ReadFile("MSUF_Suite_Skin/Core/Typography.lua"):match("local faceLabels = (%b{})")
Check(faces ~= nil, "Typography.lua has no face label table")
for label in faces:gmatch('=%s*"([^"]+)"') do Translated(label, "the font choice") end
Translated("Class: %s", "the Class Style label")

-- Every language reads the skin through the Suite's localization: the
-- English text of a key (a key names it, like DOSSIER_LOADING, or is it)
-- goes through Suite.Text, and NS.SourceText gives that English text.
do
    local ns, shown = {}, { ["Loading item..."] = "Chargement de l'objet...", ["Rounded"] = "Arrondi" }
    local suite, locale = MSUFSuite, GetLocale
    MSUFSuite = { Text = function(text) return shown[text] or text end }
    GetLocale = function() return "frFR" end
    for _, file in ipairs({ "Localization.lua", "enUS.lua" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/Locales/" .. file))("MSUF_Suite_Skin", ns)
    end
    ns.InitializeLocalization()
    MSUFSuite, GetLocale = suite, locale
    Check(english.DOSSIER_LOADING == "Loading item..." and ns.L.DOSSIER_LOADING == shown["Loading item..."],
        "a skin key that names its text is not translated through the Suite")
    Check(ns.L.Rounded == "Arrondi" and ns.L["Not a skin string"] == "Not a skin string",
        "a skin key that is its text is not translated through the Suite")
    Check(ns.SourceText("DOSSIER_LOADING") == "Loading item..." and ns.SourceText("Rounded") == "Rounded",
        "NS.SourceText does not give the English text of a key")
    local French = Support.SkinLocale(root, "frFR")
    local translated = 0
    for key, text in pairs(english) do
        if French[key] ~= text then translated = translated + 1 end
    end
    Check(translated >= 30, "the French skin shows only " .. translated .. " translated strings")
end

-- The Class Style label and a German search.
UnitClass = function() return "Paladin", "PALADIN" end
C_ClassColor = { GetClassColor = function() return { r = 0.96, g = 0.55, b = 0.73, a = 1 } end }
RAID_CLASS_COLORS = {}
NS.L = German
NS.Registry = { QueueRefresh = function() end, NotifyListeners = function() end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Theme.lua"))("MSUF_Suite_Skin", NS)
Check(NS.Theme.GetClassLookLabel() == "Klasse: Paladin",
    "the Class Style label is not localized: " .. tostring(NS.Theme.GetClassLookLabel()))
local options = { GetPageDefinition = function() return nil end }
assert(loadfile(root .. "/MSUF_Suite_Skin_Options/Shell/Search.lua"))("MSUF_Suite_Skin_Options",
    { NS = NS, Options = options })
local found = false
for _, record in ipairs(options.SearchSettings("Klassenstil", 50)) do
    if record.page == "looks" then found = true end
end
Check(found, "a German search for Klassenstil found no style setting")
-- The class color palette, by the German name the packs give it (MSUF's
-- deDE wording for "Class Color" comes first).
found = false
local classColor = German["Class Color"]
Check(classColor ~= "Class Color", "the class color palette has no German name")
for _, record in ipairs(options.SearchSettings(classColor, 50)) do
    if record.page == "colors" then found = true end
end
Check(found, "a German search for " .. classColor .. " found no palette setting")

-- The pages show catalog names through the locale table.
for path, needle in pairs({
    ["MSUF_Suite_Skin_Options/Pages/Looks.lua"] = "L[look.label]",
    ["MSUF_Suite_Skin_Options/Pages/Colors.lua"] = "L[label]",
    ["MSUF_Suite_Skin_Options/Shell/Window.lua"] = "L[look.label]",
}) do
    Check(ReadFile(path):find(needle, 1, true) ~= nil, path .. " shows a catalog name without the locale table")
end
Check(ReadFile("MSUF_Suite_Skin_Options/Pages/Looks.lua"):find("L[selected.description", 1, true) ~= nil,
    "the look note shows its description without the locale table")

-- No hard-coded English in the skin's setters, tooltips, edit labels or
-- history labels. Catalog data (Defaults*.lua) is localized where it is
-- shown; upper-case constants name Blizzard globals, lower-case words ids.
local function Prose(literal)
    return literal:find("%a") ~= nil and not literal:match("^[%u%d_]+$") and not literal:match("^[%l%d_%-]+$")
end
local rules = {
    ":SetText%(%s*\"([^\"]*)\"", ":AddLine%(%s*\"([^\"]*)\"", "%f[%w]label%s*=%s*\"([^\"]*)\"",
    "%f[%w]group%s*=%s*\"([^\"]*)\"", "WithHistory%(%s*\"([^\"]*)\"",
}
-- Every code file the addon's TOC loads.
local function Lua(folder)
    local list = {}
    for line in ReadFile(folder .. "/" .. folder .. "_Mainline.toc"):gmatch("[^\n]+") do
        if line:match("%.lua$") then
            list[#list + 1] = root .. "/" .. folder .. "/" .. line:gsub("\\", "/")
        end
    end
    return list
end
local scanned, literals = 0, {}
for _, folder in ipairs({ "MSUF_Suite_Skin", "MSUF_Suite_Skin_Options" }) do
    for _, path in ipairs(Lua(folder)) do
        if not path:find("/Locales/", 1, true) and not path:find("/Libs/", 1, true)
            and not path:find("Core/Defaults", 1, true) then
            scanned = scanned + 1
            local file = assert(io.open(path, "rb"))
            local number = 0
            for line in file:read("*a"):gsub("\r\n", "\n"):gmatch("([^\n]*)\n?") do
                number = number + 1
                local code = line:gsub("%-%-.*$", "")
                for _, rule in ipairs(rules) do
                    for literal in code:gmatch(rule) do
                        if Prose(literal) then
                            literals[#literals + 1] = path:match("MSUF_Suite_Skin.*$") .. ":" .. number .. ": " .. literal
                        end
                    end
                end
            end
            file:close()
        end
    end
end
Check(scanned > 80, "the literal lint scanned only " .. scanned .. " files")
Check(#literals == 0, "hard-coded user-facing strings:\n  " .. table.concat(literals, "\n  "))

print("Suite skin locale labels: " .. checks .. " checks passed")
