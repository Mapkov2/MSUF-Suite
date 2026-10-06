-- Suite language packs (MSUF_Suite/Locales/<locale>.lua): every pack parses,
-- returns before any work for another locale, fills MSUF's table without
-- replacing MSUF's own wording, translates only current Suite strings with
-- the same format specifiers, color codes and a script that fits the
-- language, and covers the current extraction (tools/suite_locale_tool.py).
-- Usage: lua suite_locale_contract.lua <suite root> [python]
local root = assert(arg[1], "usage: suite_locale_contract.lua <suite root> [python]")
local python = arg[2] or os.getenv("MSUF_PYTHON") or "python"
local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local LATIN = { deDE = true, esES = true, esMX = true, frFR = true, itIT = true, ptBR = true }
local CHROME_MIN, HELP_MIN = 1.0, 1.0
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

------------------------------------------------------------------ extraction
-- The live English set, straight from the sources: a string added or renamed
-- since the packs were written shows up here at once.
local function Quote(text) return '"' .. text .. '"' end
local command = Quote(python) .. " " .. Quote(root .. "/tools/suite_locale_tool.py") .. " extract --tsv -"
if package.config:sub(1, 1) == "\\" then command = '"' .. command .. '"' end
local pipe = assert(io.popen(command, "r"))
local tsv = pipe:read("*a")
pipe:close()
local function Unescape(text)
    return (text:gsub("\\(.)", function(c)
        if c == "n" then return "\n" elseif c == "t" then return "\t" elseif c == "r" then return "\r" end
        return c
    end))
end
local strings, total = {}, 0
local header = true
for line in tsv:gmatch("[^\n]+") do
    if header then
        assert(line == "id\tclass\tenglish\tmsuf\tproper\tused", "unexpected extraction header: " .. line)
        header = false
    else
        local id, class, english, msuf, proper = line:match("^(%x+)\t([%w+]+)\t([^\t]*)\t([^\t]*)\t([01])\t")
        assert(id, "unreadable extraction line: " .. line)
        local covered = {}
        for locale in msuf:gmatch("[^,]+") do covered[locale] = true end
        strings[Unescape(english)] = { class = class:match("^%a+"), pending = class:find("pending", 1, true) ~= nil,
            msuf = covered, proper = proper == "1" }
        total = total + 1
    end
end
assert(total > 1000, "the extraction returned only " .. total .. " strings; is Python at " .. python .. "?")

------------------------------------------------------------------ text checks
local function Codepoints(text)
    local out, i = {}, 1
    while i <= #text do
        local c = text:byte(i)
        local size = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
        local code = size == 1 and c or c % (size == 2 and 0x20 or size == 3 and 0x10 or 0x08)
        for k = 1, size - 1 do code = code * 64 + (text:byte(i + k) or 0x80) % 64 end
        out[#out + 1] = code
        i = i + size
    end
    return out
end
local function Scripts(text)
    local found = {}
    for _, code in ipairs(Codepoints(text)) do
        if code >= 0x0400 and code <= 0x04FF then found.cyrillic = true end
        if (code >= 0xAC00 and code <= 0xD7AF) or (code >= 0x1100 and code <= 0x11FF)
            or (code >= 0x3130 and code <= 0x318F) then found.hangul = true end
        if (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0x3400 and code <= 0x4DBF)
            or (code >= 0xF900 and code <= 0xFAFF) then found.han = true end
    end
    return found
end
local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[-+ #0]*%d*%.?%d*[%a%%]") do list[#list + 1] = spec end
    return table.concat(list, " ")
end
local function Count(text, pattern)
    local n = 0
    for _ in text:gmatch(pattern) do n = n + 1 end
    return n
end
local function CheckEntry(locale, english, text)
    local where = locale .. " " .. string.format("%q", english):sub(1, 70)
    Check(text ~= "" and text:find("%S") ~= nil, where .. ": empty translation")
    Check(Specifiers(text) == Specifiers(english),
        where .. ": format specifiers " .. Specifiers(text) .. " differ from " .. Specifiers(english))
    Check(not text:find("%%%d+%$"), where .. ": positional specifiers do not exist in Lua 5.1")
    Check(Count(text, "|c%x%x%x%x%x%x%x%x") == Count(english, "|c%x%x%x%x%x%x%x%x")
        and Count(text, "|r") == Count(english, "|r"), where .. ": color codes differ")
    Check(Count(text, "|T") == Count(english, "|T"), where .. ": icon escapes differ")
    local scripts, info = Scripts(text), strings[english]
    if LATIN[locale] then
        Check(not (scripts.cyrillic or scripts.hangul or scripts.han), where .. ": CJK, Hangul or Cyrillic in a Latin locale")
    elseif locale == "ruRU" then
        Check(not (scripts.hangul or scripts.han), where .. ": CJK or Hangul in Russian")
        Check(scripts.cyrillic or info.proper, where .. ": no Cyrillic although the English is no proper name")
    elseif locale == "koKR" then
        Check(not scripts.cyrillic, where .. ": Cyrillic in Korean")
        Check(scripts.hangul or info.proper, where .. ": no Hangul although the English is no proper name")
    else
        Check(not (scripts.cyrillic or scripts.hangul), where .. ": Cyrillic or Hangul in Chinese")
        Check(scripts.han or info.proper, where .. ": no Chinese although the English is no proper name")
    end
end

------------------------------------------------------------------ loading a pack
-- MSUF's table: raw entries plus a key fallback, like Locales/MSUF_Localization.lua.
local function LocaleTable(preset)
    return setmetatable(preset or {}, { __index = function(_, key) return key end })
end
local function Run(locale, msuf)
    MSUF_NS, MSUF = msuf, nil
    local path = root .. "/MSUF_Suite/Locales/" .. locale .. ".lua"
    local chunk = assert(loadfile(path))
    local last = 0
    debug.sethook(function(_, line)
        if debug.getinfo(2, "S").source == "@" .. path and line > last then last = line end
    end, "l")
    chunk("MSUF_Suite", {})
    debug.sethook()
    MSUF_NS = nil
    return last
end
local function Refuse() error("the pack touched MSUF's locale table for another locale", 2) end
local function Sorted(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

for _, locale in ipairs(LOCALES) do
    local file = io.open(root .. "/MSUF_Suite/Locales/" .. locale .. ".lua", "rb")
    Check(file ~= nil, locale .. ": MSUF_Suite/Locales/" .. locale .. ".lua is missing")
    if file then
        local source = file:read("*a")
        file:close()
        Check(source:sub(1, 3) ~= "\239\187\191", locale .. ": the pack starts with a byte order mark")
        Check(source:find('if not MSUF or MSUF.LOCALE ~= "' .. locale .. '" then return end', 1, true) ~= nil,
            locale .. ": the pack lacks its locale guard")

        -- Another locale, or no MSUF: only the guard lines run, so no table
        -- or entry is built and MSUF's table is never touched.
        local sink = setmetatable({}, { __newindex = Refuse, __index = Refuse })
        for _, other in ipairs({ "enUS", locale == "deDE" and "frFR" or "deDE" }) do
            local last = Run(locale, { LOCALE = other, L = sink, RegisterLocale = Refuse })
            Check(last <= 5, locale .. " under " .. other .. " ran up to line " .. last .. " instead of returning at the guard")
        end
        Check(Run(locale, nil) <= 5, locale .. " without MSUF did not return at the guard")

        -- The matching locale: every entry lands in the table MSUF.RegisterLocale
        -- returns for this locale.
        local asked
        local entries = LocaleTable()
        Run(locale, { LOCALE = locale, L = sink,
            RegisterLocale = function(requested) asked = requested; return entries end })
        Check(asked == locale, locale .. ": the pack did not ask MSUF.RegisterLocale for its own locale")
        local keys = Sorted(entries)
        Check(#keys > 0, locale .. ": the pack wrote nothing for its own locale")
        -- The undo label of every Suite page reset (Menu/Register.lua): MSUF
        -- hosts before host API v1 have no translation of it, so the pack
        -- brings MSUF's own (copied from the Classic packs).
        Check(rawget(entries, "Reset %s") ~= nil and rawget(entries, "Reset %s") ~= "Reset %s",
            locale .. ": the pack lacks the page reset's undo label \"Reset %s\"")
        -- MSUF's own wording of a string always wins.
        if keys[1] then
            local owned = LocaleTable({ [keys[1]] = "MSUF WINS" })
            Run(locale, { LOCALE = locale, RegisterLocale = function() return owned end })
            Check(rawget(owned, keys[1]) == "MSUF WINS", locale .. ": the pack replaced a translation MSUF already has")
            Check(rawget(owned, keys[#keys]) == entries[keys[#keys]], locale .. ": entries after MSUF's own were lost")
        end
        local fallback = LocaleTable({ Font = "Font" })
        Run(locale, { LOCALE = locale, L = fallback })
        Check(rawget(fallback, "Font") == rawget(entries, "Font"),
            locale .. ": an English host fallback blocks the Suite translation")
        -- An MSUF build without RegisterLocale still gets the pack through MSUF.L.
        local plain = LocaleTable()
        Run(locale, { LOCALE = locale, L = plain })
        Check(#keys == 0 or rawget(plain, keys[1]) ~= nil, locale .. ": the pack ignored MSUF.L without RegisterLocale")

        for _, english in ipairs(keys) do
            if strings[english] then
                CheckEntry(locale, english, rawget(entries, english))
            else
                Check(false, locale .. ": " .. string.format("%q", english):sub(1, 70)
                    .. " is no current Suite string (removed or renamed? run tools/suite_locale_tool.py verify)")
            end
        end
        local counts = { chrome = { 0, 0 }, help = { 0, 0 } }
        for english, info in pairs(strings) do
            if not info.pending then
                local slot = counts[info.class]
                slot[2] = slot[2] + 1
                if info.msuf[locale] or rawget(entries, english) ~= nil then slot[1] = slot[1] + 1 end
            end
        end
        for class, minimum in pairs({ chrome = CHROME_MIN, help = HELP_MIN }) do
            local have, all = counts[class][1], counts[class][2]
            Check(all == 0 or have / all >= minimum, string.format(
                "%s: %s coverage %d/%d (%.1f%%) is below %d%%; run the delta pass: "
                .. "python tools/suite_locale_tool.py missing --locale %s --format json",
                locale, class, have, all, 100 * have / math.max(all, 1), minimum * 100, locale))
        end
    end
end

-- Collapsed summaries translate their UI label and their selected choice.
do
    local dictionary = { ["Icon size"] = "SYMBOLGROESSE", Top = "OBEN" }
    local refresh, summary
    local P = { S = {}, M = {}, W = {}, T = {}, Suite = {}, catalog = {} }
    local bridge = { HostBridge = {} }
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", bridge)
    P.HM = bridge.HostBridge.Menu2(P.M)
    P.Tr = function(key) return dictionary[key] or key end
    P.M.TrackRefresh = function(_, callback) refresh = callback end
    P.W.SetCollapsibleSummary = function(_, text) summary = text end
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Controls.lua"))("MSUF_Suite_Options", P)
    P.AttachRowsSummary({}, { _msuf2CollapsibleEntry = {} }, {
        { summary = 1, kind = "dropdown", label = "Icon size", get = function() return 1 end,
          values = { { value = 1, text = "Top" } } },
    })
    refresh()
    Check(summary == "SYMBOLGROESSE: OBEN", "collapsed summary left its label or choice English")
end

if #failures > 0 then
    table.sort(failures)
    for i = 1, math.min(#failures, 60) do print("FAIL " .. failures[i]) end
    error(#failures .. " locale problems", 0)
end
print("Suite locales: " .. total .. " strings; " .. #LOCALES
    .. " packs guard, fill MSUF's table without replacing it, match specifiers and scripts, and cover the extraction")
