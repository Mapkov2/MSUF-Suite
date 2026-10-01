-- The skin's user-facing names reach the player through its locale tables:
-- every look and palette name and description, the font choices and the
-- Class Style label exist in English and German, the options show them
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

local tables = {}
for _, locale in ipairs({ "enUS", "deDE" }) do
    local captured
    assert(loadfile(root .. "/MSUF_Suite_Skin/Locales/" .. locale .. ".lua"))("MSUF_Suite_Skin",
        { RegisterLocale = function(_, values) captured = values end })
    tables[locale] = assert(captured, locale .. " did not register")
end
local function Resolver(locale)
    local active = tables[locale]
    return setmetatable({}, { __index = function(_, key)
        local value = active[key]
        if value == nil then value = tables.enUS[key] end
        return value == nil and key or value
    end })
end
local function Translated(text, what)
    Check(tables.enUS[text] ~= nil and tables.deDE[text] ~= nil,
        what .. " is missing from the locale tables: " .. tostring(text))
end

-- Names and descriptions shown from the engine's catalogs.
local NS = { Client = { isForever = false, isMainline = true } }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
for name, look in pairs(NS.LookPresets) do
    Translated(look.label, "the name of look " .. name)
    Translated(look.description, "the description of look " .. name)
end
for key, label in pairs(NS.PaletteLabels) do Translated(label, "the name of palette " .. key) end
local faces = ReadFile("MSUF_Suite_Skin/Core/Typography.lua"):match("local faceLabels = (%b{})")
Check(faces ~= nil, "Typography.lua has no face label table")
for label in faces:gmatch('=%s*"([^"]+)"') do Translated(label, "the font choice") end
Translated("Class: %s", "the Class Style label")

-- The Class Style label and a German search.
UnitClass = function() return "Paladin", "PALADIN" end
C_ClassColor = { GetClassColor = function() return { r = 0.96, g = 0.55, b = 0.73, a = 1 } end }
RAID_CLASS_COLORS = {}
NS.L = Resolver("deDE")
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
found = false
for _, record in ipairs(options.SearchSettings("Klassenfarbe", 50)) do
    if record.page == "colors" then found = true end
end
Check(found, "a German search for Klassenfarbe found no palette setting")

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
-- history labels. Catalog data (Defaults.lua) is localized where it is
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
            and not path:find("Core/Defaults.lua", 1, true) then
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
