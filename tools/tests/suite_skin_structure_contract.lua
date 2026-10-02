-- Structure of the Suite skin engine and its options: the files split in
-- quality pass 4 load in the order their consumers need, the shared helpers
-- replace the local copies, and no existence check remains for an API that
-- Retail and Forever always have or for one of the addon's own modules (the
-- tests stub those APIs and modules instead).
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"), "missing " .. relative)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local function TocFiles(addon)
    local files, index = {}, {}
    for line in Read(addon .. "/" .. addon .. "_Mainline.toc"):gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line:match("%.lua$") then
            files[#files + 1] = line:gsub("\\", "/")
            index[files[#files]] = #files
        end
    end
    return files, index
end

------------------------------------------------------------------ load order
-- Both skin TOCs keep one line-ending style, CRLF, throughout.
for _, addon in ipairs({ "MSUF_Suite_Skin", "MSUF_Suite_Skin_Options" }) do
    local file = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local raw = file:read("*a")
    file:close()
    local bare = raw:gsub("\r\n", "")
    Check(not bare:find("[\r\n]"), addon .. "_Mainline.toc mixes line endings (CRLF only)")
end

local skinFiles, skinAt = TocFiles("MSUF_Suite_Skin")
local function Before(first, second)
    Check(skinAt[first] and skinAt[second] and skinAt[first] < skinAt[second],
        first .. " must load before " .. second)
end
-- Each split file follows the file whose private table it reads.
Check(skinAt["Core/CheckmarksMenus.lua"] == skinAt["Core/Checkmarks.lua"] + 1,
    "CheckmarksMenus.lua must load right after Checkmarks.lua (NS.CheckmarksShared)")
Check(skinAt["Core/PublicAPIMethods.lua"] == skinAt["Core/PublicAPI.lua"] + 1,
    "PublicAPIMethods.lua must load right after PublicAPI.lua (NS.PublicAPIShared)")
Check(skinAt["Core/DefaultsLooks.lua"] == skinAt["Core/Defaults.lua"] + 1,
    "DefaultsLooks.lua must load right after Defaults.lua (NS.DefaultsShared)")
Before("Rendering/MicroMenuPerformance.lua", "Rendering/MicroMenuVisual.lua")
-- Load-time locals: NS.Clamp and NS.IsListed (Defaults), WatchSettings
-- (Registry), NS.MicroMenuPerformance.
for _, consumer in ipairs({ "Core/Database.lua", "Core/Theme.lua", "Rendering/WindowActionSettings.lua",
    "Rendering/MicroMenuVisual.lua", "Rendering/MicroMenuPerformance.lua" }) do
    Before("Core/Defaults.lua", consumer)
end
Before("Core/Registry.lua", "Rendering/IconSkin.lua")
Before("Core/Registry.lua", "Rendering/ScrollBarSkin.lua")
-- The rest of the engine is in place before the public API activates.
Before("Core/PublicAPIMethods.lua", "Core/Finalize.lua")

local optionFiles, optionAt = TocFiles("MSUF_Suite_Skin_Options")
local WIDGET_FILES = { "Shell/Widgets.lua", "Shell/WidgetsDropdown.lua", "Shell/WidgetsInput.lua",
    "Shell/WidgetsColor.lua" }
for index, file in ipairs(WIDGET_FILES) do
    Check(optionAt[file] == optionAt[WIDGET_FILES[1]] + index - 1,
        file .. " must follow Widgets.lua in this order (Private.Widgets, combat closers)")
end
Check(optionAt["Shell/Theme.lua"] < optionAt["Shell/Widgets.lua"]
    and optionAt["Shell/WidgetsColor.lua"] < optionAt["Shell/Window.lua"]
    and optionAt["Shell/WidgetsColor.lua"] < optionAt["Pages/Dashboard.lua"],
    "the widget files must load after the options theme and before the window and pages")

------------------------------------------------------------------ sources
-- Every Lua file this contract covers: the engine without the adapters and
-- libraries (Blizzard.lua included), and all option files.
local sources = {}
for _, file in ipairs(skinFiles) do
    if not file:match("^Libs/") and (not file:match("^Adapters/") or file == "Adapters/Blizzard.lua") then
        sources["MSUF_Suite_Skin/" .. file] = Read("MSUF_Suite_Skin/" .. file)
    end
end
for _, file in ipairs(optionFiles) do
    sources["MSUF_Suite_Skin_Options/" .. file] = Read("MSUF_Suite_Skin_Options/" .. file)
end

-- Existence checks for APIs Retail and Forever always have (verified in the
-- live and forever UI source). Client.lua's GameEvent check identifies
-- Forever and stays.
local GUARDS = {
    "type(InCombatLockdown)", "type(geterrorhandler)", "type(print)", "type(UnitClass)",
    "type(RAID_CLASS_COLORS)", "C_ClassColor and", "type(GetLocale)", "type(GetFonts)",
    "type(IsLoggedIn)", "type(CreateColor)", "type(hooksecurefunc)", "type(UpdateUIPanelPositions)",
    "type(ShowUIPanel)", "type(HideUIPanel)", "type(IsMouseButtonDown)", "if GameTooltip",
    "UIPanelWindows and", "not C_Timer", "if C_Timer", "C_EventUtils and", "DoesAddOnExist) ==",
    "not EventUtil", "PlaySound and", "IsControlKeyDown and", "IsShiftKeyDown and",
    "not ColorPickerFrame", "if UISpecialFrames", "ChatFontNormal or", "DropdownButtonMixin and",
    "ScrollBoxListMixin and", "ButtonGroupBaseMixin and", "Enum and Enum.", "LibStub and",
    "C_EncodingUtil and", "local function Codec", "_G.OpacityFrame then", "_G.AddonDialog then",
    "DEFAULT_CHAT_FRAME and", "type(NS) ~=", "GetFrameLevel and",
    ".SetWordWrap then", ".SetMaxLines then", ".SetTextInsets then", ".SetObeyStepOnDrag then",
    ".SetTextureSliceMargins then", ".SetClipsChildren then", ".SetGradient and",
    "type(texture.SetSnapToPixelGrid)", "type(line.SetColorTexture)",
}
-- Safety.Dispatch is securecallfunction itself, without a fallback for
-- harnesses that lack it (every contract stubs it).
local HARNESS_FALLBACKS = {}
Check(sources["MSUF_Suite_Skin/Core/Safety.lua"]:find("Safety%.Dispatch = securecallfunction[\r\n]")
    and not sources["MSUF_Suite_Skin/Core/Safety.lua"]:find("securecallfunction or", 1, true),
    "Safety.Dispatch keeps a fallback for harnesses without securecallfunction")
for path, text in pairs(sources) do
    for _, guard in ipairs(GUARDS) do
        Check(not text:find(guard, 1, true), path .. " still checks an API every client has: " .. guard)
    end
    local fallback = HARNESS_FALLBACKS[path]
    Check(fallback and text:find(fallback, 1, true)
        or not text:find("Offline test harness", 1, true) and not text:find("offline harness", 1, true),
        path .. " keeps a branch for offline test harnesses")
    Check(not text:find("%f[%w_]pcall%(") and not text:find("xpcall", 1, true)
        and not text:find("loadstring", 1, true), path .. " uses a protected or string call")
end

-- Own-module probes. At run time every file of an addon has loaded before
-- any of its functions runs, so a check whether one of the addon's own
-- modules (NS.X, set by one of its files) exists only served test harnesses
-- that load part of the addon; they stub or load the module instead. Real
-- state stays: the database before ADDON_LOADED (NS.DB, NS.RootDB), the
-- separate options addon (NS.Options, NS.OptionsReady) and the locale table.
local STATE = { DB = true, RootDB = true, Options = true, OptionsReady = true, ready = true,
    migrationOnly = true, L = true }
local allSources, modules = {}, {}
for _, file in ipairs(skinFiles) do
    if not file:match("^Libs/") then
        allSources["MSUF_Suite_Skin/" .. file] = Read("MSUF_Suite_Skin/" .. file)
    end
end
for _, file in ipairs(optionFiles) do
    allSources["MSUF_Suite_Skin_Options/" .. file] = Read("MSUF_Suite_Skin_Options/" .. file)
end
for _, text in pairs(allSources) do
    for line in text:gmatch("[^\n]+") do
        local name = line:match("^%s*NS%.([%a_][%w_]*)%s*=[^=]") or line:match("^function NS%.([%a_][%w_]*)%(")
        if name and not STATE[name] then modules[name] = true end
    end
end
Check(modules.Checkmarks and modules.WindowActionSkin and modules.BlizzardFontNames and modules.Client,
    "the own-module list is incomplete")

-- The private bridge tables of the split files (NS.*Shared and the catalog
-- data) are taken off NS by their last reader in TOC order, so nothing
-- internal stays reachable through _G.MapkoSkin. The absorption contract
-- checks the loaded namespace itself.
do
    local bridges = {}
    for _, text in pairs(allSources) do
        for name in text:gmatch("\nNS%.([%a_][%w_]*) = {") do
            if name:find("Shared$") or name == "BlizzardCatalogData" then bridges[name] = true end
        end
    end
    Check(bridges.CheckmarksShared and bridges.PublicAPIShared and bridges.DeepWindowsShared
        and bridges.GenericWindowsShared and bridges.MicroMenuShared and bridges.BlizzardCatalogData,
        "the bridge table list is incomplete")
    for name in pairs(bridges) do
        local lastReader, cleared
        for index, file in ipairs(skinFiles) do
            local text = allSources["MSUF_Suite_Skin/" .. file]
            if text and text:find("= NS." .. name .. "\n", 1, true) then lastReader = index end
            if text and text:find("\nNS." .. name .. " = nil\n", 1, true) then cleared = index end
        end
        Check(lastReader and cleared == lastReader,
            "NS." .. name .. " stays on _G.MapkoSkin after its last reader")
    end
end
-- Each pattern captures the module name of one probe form.
local MODULE_PROBES = {
    "%f[%w_]NS%.([%a_][%w_]*)%s+and%f[^%w_]",
    "%f[%w_]NS%.([%a_][%w_]*)%s+or%f[^%w_]",
    "%f[%w_]not%s+NS%.([%a_][%w_]*)%f[^%w_][^%.%[%(:%w_]",
    "%f[%w_]not%s+NS%.([%a_][%w_]*)$",
    "%f[%w_]NS%.([%a_][%w_]*)%s+then%f[^%w_]",
    "%f[%w_]NS%.([%a_][%w_]*)%s*[~=]=%s*nil%f[^%w_]",
    "type%(NS%.([%a_][%w_]*)[%.%)]",
    "%f[%w_]and%s+NS%.([%a_][%w_]*)%s*$",
    "%f[%w_]NS%.([%a_][%w_]*)%.([%a_][%w_]*)%s+and%s+NS%.%1%.%2[%s%(%.%[]",
    "%f[%w_]NS%.([%a_][%w_]*)[%w_%.]*%s+or%s+{%s*}",
}
local function ProbedModule(line)
    for _, pattern in ipairs(MODULE_PROBES) do
        for name in line:gmatch(pattern) do
            if modules[name] then return name end
        end
    end
    -- An option function probed before the call (Options addon).
    return line:match("%f[%w_]O%.([%a_][%w_]*)%s+and%s+O%.%1%s*%(")
end
for path, text in pairs(allSources) do
    local alias, aliasLine, number, trailing = nil, 0, 0, nil
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        number = number + 1
        if not line:match("^%s*%-%-") then
            local probed = ProbedModule(line)
            -- A module named last on the line before, tested on this one.
            if trailing and (line:match("^%s*and%f[^%w_]") or line:match("^%s*or%f[^%w_]")
                or line:match("^%s*then%f[^%w_]")) then
                probed = trailing
            end
            trailing = line:match("%f[%w_]NS%.([%a_][%w_]*)%s*$")
            if trailing and not modules[trailing] then trailing = nil end
            Check(not probed, ("%s:%d probes its own module %s: %s"):format(path, number,
                tostring(probed), line:match("^%s*(.-)%s*$")))
            -- A function-local alias of a module, checked right after.
            if alias and number - aliasLine <= 3 then
                Check(not line:find("%f[%w_]not%s+" .. alias .. "%f[^%w_]")
                    and not line:find("%f[%w_]" .. alias .. "%s*~=%s*nil")
                    and not line:find("%f[%w_]if%s+" .. alias .. "%s+then")
                    and not line:find("%f[%w_]" .. alias .. "%s+and%s+" .. alias .. "[%.:]"),
                    ("%s:%d probes its own module through %s"):format(path, number, alias))
            end
            local name, module = line:match("^%s+local%s+([%a_][%w_]*)%s*=%s*NS%.([%a_][%w_]*)%s*$")
            if name and modules[module] then alias, aliasLine = name, number end
        end
    end
end
-- Probe forms of single files: the window parts of Blizzard.lua, fallback
-- tables for catalogs Defaults.lua always defines, the public API version
-- from Bootstrap.lua, the enUS locale table, the options namespace and the
-- database readiness at activation (Finalize runs before ADDON_LOADED).
local SINGLE_PROBES = {
    ["MSUF_Suite_Skin/Adapters/Blizzard.lua"] = { "type(module) == \"table\"", "\"missing\" end",
        "reason ~= \"missing\"", "reason == \"missing\"" },
    ["MSUF_Suite_Skin/Core/PublicAPI.lua"] = { "publicAPIMajor or", "publicAPIMinor or" },
    ["MSUF_Suite_Skin/Core/PublicAPIMethods.lua"] = { "if NS.DB then PublicAPI.OnDatabaseReady() end" },
    ["MSUF_Suite_Skin/Locales/Localization.lua"] = { "localeTables.enUS or" },
    ["MSUF_Suite_Skin/Adapters/MicroMenuSettings.lua"] = { "(values or {})", "local function Clamp01(",
        "local function IsListed(" },
    ["MSUF_Suite_Skin/Adapters/OwnedMicroBarLayout.lua"] = { "function Layout.Clamp(",
        "NS.Client.isForever and 14 or 13" },
    ["MSUF_Suite_Skin/Adapters/OwnedMicroBar.lua"] = { "Layout.Clamp" },
    ["MSUF_Suite_Skin_Options/MSKIN_OptionsBootstrap.lua"] = { "NS.Options or {}", "O.widgetStates or",
        "O.textRoles or" },
    ["MSUF_Suite_Skin_Options/Shell/Search.lua"] = { "(order or {})" },
    ["MSUF_Suite_Skin_Options/Pages/Icons.lua"] = { "isForever and 14 or 13" },
}
for path, probes in pairs(SINGLE_PROBES) do
    local text = assert(allSources[path], path)
    for _, probe in ipairs(probes) do
        Check(not text:find(probe, 1, true), path .. " probes an own module again: " .. probe)
    end
end
Check(allSources["MSUF_Suite_Skin/Adapters/Blizzard.lua"]:find("return NS[moduleName][method](owner)", 1, true),
    "a Blizzard window part is looked up with a probe instead of called")
Check(allSources["MSUF_Suite_Skin/Adapters/MicroMenuSettings.lua"]:find("local Clamp = NS.Clamp", 1, true)
    and allSources["MSUF_Suite_Skin/Adapters/MicroMenuSettings.lua"]:find("local IsListed = NS.IsListed", 1, true)
    and allSources["MSUF_Suite_Skin/Adapters/OwnedMicroBarLayout.lua"]:find("local Clamp = NS.Clamp", 1, true)
    and allSources["MSUF_Suite_Skin/Adapters/OwnedMicroBar.lua"]:find("local Clamp = NS.Clamp", 1, true),
    "the Micro Bar keeps its own Clamp/IsListed instead of NS.Clamp/NS.IsListed")

-- One way to do each thing: the shared helpers, not local copies.
local function Source(path) return assert(sources[path], path) end
for _, path in ipairs({ "MSUF_Suite_Skin/Core/Database.lua", "MSUF_Suite_Skin/Core/Theme.lua",
    "MSUF_Suite_Skin/Rendering/WindowActionSettings.lua" }) do
    Check(not Source(path):find("local function IsListed(", 1, true)
        and Source(path):find("local IsListed = NS.IsListed", 1, true),
        path .. " keeps its own IsListed instead of NS.IsListed")
end
for _, path in ipairs({ "MSUF_Suite_Skin/Core/Database.lua", "MSUF_Suite_Skin/Core/Theme.lua",
    "MSUF_Suite_Skin/Rendering/MicroMenuVisual.lua", "MSUF_Suite_Skin/Rendering/MicroMenuPerformance.lua" }) do
    Check(not Source(path):find("local function Clamp(", 1, true)
        and Source(path):find("local Clamp = NS.Clamp", 1, true),
        path .. " keeps its own Clamp instead of NS.Clamp")
end
for _, path in ipairs({ "MSUF_Suite_Skin/Rendering/IconSkin.lua", "MSUF_Suite_Skin/Rendering/ScrollBarSkin.lua" }) do
    Check(not Source(path):find("local function EnsureListener(", 1, true)
        and Source(path):find("WatchSettings(RefreshAll,", 1, true),
        path .. " registers its own settings listener instead of Registry.WatchSettings")
end
Check(Source("MSUF_Suite_Skin/Core/Database.lua"):find("NS.Safety.SameColor(", 1, true)
    and not Source("MSUF_Suite_Skin/Core/Database.lua"):find("math.abs(color[1] - r)", 1, true),
    "Database compares migrated colors without Safety.SameColor")
Check(Source("MSUF_Suite_Skin_Options/Shell/WidgetsDropdown.lua"):find("CreateInputBox(frame, 9)", 1, true),
    "the dropdown search builds its own text field instead of the shared input box")

------------------------------------------------------------------ size
local DATA_FILES = {
    ["MSUF_Suite_Skin/Core/BlizzardFontCatalog.lua"] = true,
    ["MSUF_Suite_Skin/Locales/enUS.lua"] = true,
    ["MSUF_Suite_Skin/Locales/deDE.lua"] = true,
}
for path, text in pairs(sources) do
    local _, lines = text:gsub("\n", "\n")
    Check(DATA_FILES[path] or lines <= 900, path .. " has " .. lines .. " lines (at most 900)")
end
-- Function length and main-chunk locals from the compiler listing, when
-- luac sits next to the interpreter running this test.
local interpreter = arg[-1] or ""
local compiler = interpreter:gsub("lua%.exe$", "luac.exe"):gsub("lua$", "luac")
local probe = compiler ~= interpreter and io.open(compiler, "rb")
if probe then
    probe:close()
    for path in pairs(sources) do
        -- cmd.exe drops the outer quote pair of a quoted command line.
        local listing = assert(io.popen('""' .. compiler .. '" -l -p "' .. root .. "/" .. path .. '""'))
        local text = listing:read("*a")
        listing:close()
        Check(text:find("main <", 1, true), "luac listed nothing for " .. path)
        for kind, first, last, header in text:gmatch("\n?(%a+) <[^\n]-:(%d+),(%d+)> ([^\n]*\n[^\n]*)") do
            if kind == "main" then
                local count = tonumber(header:match("(%d+) locals"))
                Check(count and count <= 150, path .. " main chunk has " .. tostring(count) .. " locals")
            elseif kind == "function" then
                local length = tonumber(last) - tonumber(first) + 1
                Check(DATA_FILES[path] or length <= 80,
                    ("%s:%s function has %d lines (at most 80)"):format(path, first, length))
            end
        end
    end
end

------------------------------------------------------------------ behaviour
-- Registry.WatchSettings queues the job once per frame for the listed keys,
-- any theme write but the gradient switch and a profile switch; watching
-- the same job twice registers one listener.
do
    local queued = {}
    C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
    local NS = { IsCombatLocked = function() return false end }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Registry.lua"))("MSUF_Suite_Skin", NS)
    NS.Safety = { Dispatch = function(callback, ...) return callback(...) end }
    local runs = 0
    local function Job() runs = runs + 1 end
    local keys = { color = { accent = true } }
    NS.Registry.WatchSettings(Job, keys)
    NS.Registry.WatchSettings(Job, keys)
    local listeners = 0
    for _ in pairs(NS.Registry.listeners) do listeners = listeners + 1 end
    Check(listeners == 1, "watching one job twice registered " .. listeners .. " listeners")
    local function Flush()
        local index = 1
        while queued[index] do
            queued[index]()
            index = index + 1
        end
        queued = {}
    end
    for _, write in ipairs({ { "color", "text" }, { "appearance", "accent" }, { "theme", "gradient" },
        { "geometry", "radius" } }) do
        NS.Registry.NotifyListeners(write[1], write[2])
    end
    Flush()
    Check(runs == 0, "an unrelated setting ran the watched job")
    for _ = 1, 3 do NS.Registry.NotifyListeners("color", "accent") end
    NS.Registry.NotifyListeners("theme", "look")
    NS.Registry.NotifyListeners("profile", "activate")
    Flush()
    Check(runs == 1, "the watched writes of one frame ran the job " .. runs .. " times")
    -- Each rule on its own: a theme write and a profile switch queue the job
    -- without a listed key in the same frame.
    NS.Registry.NotifyListeners("theme", "look")
    Flush()
    Check(runs == 2, "a theme write alone did not run the watched job")
    NS.Registry.NotifyListeners("profile", "activate")
    Flush()
    Check(runs == 3, "a profile switch alone did not run the watched job")
    C_Timer = nil
end

-- The Checkmarks split (Checkmarks.lua, CheckmarksMenus.lua): the Settings
-- tab group's selection callback is registered and refreshes the skinned
-- tabs, and Restore releases every menu registration (ReleaseMenus).
do
    securecallfunction = function(callback, ...) return callback(...) end
    -- CallbackRegistry: one registration per event and owner.
    local function Registry()
        local registry = { callbacks = {} }
        function registry:RegisterCallback(event, callback, owner)
            self.callbacks[event] = self.callbacks[event] or {}
            self.callbacks[event][owner] = callback
        end
        function registry:UnregisterCallback(event, owner)
            if self.callbacks[event] then self.callbacks[event][owner] = nil end
        end
        function registry:Count()
            local count = 0
            for _, owners in pairs(self.callbacks) do
                for _ in pairs(owners) do count = count + 1 end
            end
            return count
        end
        return registry
    end
    EventRegistry = Registry()
    ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
    ButtonGroupBaseMixin = { Event = { Selected = "Selected" } }
    DropdownButtonMixin = { Event = { OnMenuOpen = "OnMenuOpen" } }
    local refreshedTabs, released, actionRestores = {}, {}, 0
    local function NoAction() return false end
    local NS = {
        DB = { enabled = true },
        IsCombatLocked = function() return false end,
        Registry = { AddListener = function() end },
        BlizzardYellow = { TrackDropdown = function() end },
        WindowActionSkin = {
            HasOwnedStates = NoAction,
            IsApplied = NoAction,
            Restore = function() actionRestores = actionRestores + 1 end,
        },
        ControlSkin = {
            IsApplied = function() return true end,
            Refresh = function(tab)
                refreshedTabs[tab] = (refreshedTabs[tab] or 0) + 1
                return true
            end,
        },
        GenericWindows = { Disable = function(owner) released[owner] = true end },
    }
    for _, file in ipairs({ "Core/Safety.lua", "Core/Checkmarks.lua", "Core/CheckmarksMenus.lua" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
    end
    local Checkmarks = NS.Checkmarks

    local categoryList = { ScrollBox = Registry() }
    function categoryList.ScrollBox:ForEachFrame() end
    local gameTab, tabs = {}, Registry()
    Check(Checkmarks.TrackSettingsCategories(categoryList, "settings", { GameTab = gameTab, tabsGroup = tabs }),
        "the Settings category list was not tracked")
    local selection = tabs.callbacks.Selected
    local tabOwner, onSelected = next(selection or {})
    Check(onSelected ~= nil, "the Settings tab group's selection callback was not registered")
    local before = refreshedTabs[gameTab] or 0
    if onSelected then onSelected(tabOwner) end
    Check(refreshedTabs[gameTab] == before + 1, "a selected Settings tab was not refreshed")

    local dropdown = Registry()
    dropdown.IsMenuOpen = NoAction
    function dropdown:GetMenuDescription() end
    Check(Checkmarks.TrackDropdown(dropdown, "dropdowns") and dropdown:Count() == 1,
        "a dropdown was not tracked")
    Checkmarks.RegisterLegacyDropdowns()
    Check(EventRegistry:Count() == 2 and categoryList.ScrollBox:Count() == 1,
        "the Settings and legacy dropdown callbacks were not registered")

    Check(Checkmarks.Restore() and actionRestores == 1, "Restore did not run")
    Check(dropdown:Count() == 0 and tabs:Count() == 0 and categoryList.ScrollBox:Count() == 0
        and EventRegistry:Count() == 0 and not Checkmarks.legacyRegistered
        and next(Checkmarks.dropdowns) == nil and next(Checkmarks.settingsCategoryLists) == nil
        and released["blizzard-dropdown-menus"] and released["legacy-dropdown-menu"],
        "Restore kept a menu registration (Checkmarks.ReleaseMenus)")
    securecallfunction, EventRegistry, ScrollBoxListMixin = nil, nil, nil
    ButtonGroupBaseMixin, DropdownButtonMixin = nil, nil
end

-- The shared value helpers keep the semantics of the copies they replace.
do
    local NS = { Client = { isForever = false },
        FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" } }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
    Check(NS.Clamp("x", 2, 5) == 2 and NS.Clamp(nil, 0, 1) == 0 and NS.Clamp(7, 2, 5) == 5
        and NS.Clamp(-1, 0, 1) == 0 and NS.Clamp("0.5", 0, 1) == 0.5, "NS.Clamp changed")
    Check(NS.IsListed({ "a", "b" }, "b") and not NS.IsListed({ "a" }, "c") and not NS.IsListed({}, nil),
        "NS.IsListed changed")

    -- The revision 47 Midnight Dark hover migration still matches the
    -- untouched factory color through Safety.SameColor and leaves an edited
    -- one alone.
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Database.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
    local function LegacyHover(r)
        local profile = NS.CopyValue(NS.Defaults)
        profile.revision = 47
        profile.theme.look, profile.theme.hoverStyle, profile.theme.hoverIntensity = "midnightDark", "softFill", 0.68
        profile.theme.colors.hover = { r, 71 / 255, 67 / 255, 0.5 }
        return NS.Database.Normalize(profile)
    end
    local factory = LegacyHover(66 / 255)
    local refreshed = NS.PresetOverrides.midnightDark.hover
    Check(factory.theme.hoverStyle == "outline" and factory.theme.colors.hover[1] == refreshed[1]
        and factory.theme.colors.hover[4] == 0.5,
        "the factory Midnight Dark hover did not move to the outline look")
    local edited = LegacyHover(70 / 255)
    Check(edited.theme.hoverStyle == "softFill" and edited.theme.colors.hover[1] == 70 / 255,
        "an edited Midnight Dark hover was migrated")
end

-- The option widgets: TrackAndRefresh paints once and registers the
-- refresher; the combat watcher closes the dropdown before the picker.
do
    local tracked = {}
    local O = {
        TrackRefresh = function(callback) tracked[#tracked + 1] = callback end,
    }
    local frames = {}
    CreateFrame = function()
        local frame = { scripts = {}, events = {} }
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        frames[#frames + 1] = frame
        return frame
    end
    local private = { NS = { L = {}, IsCombatLocked = function() return false end }, Options = O }
    assert(loadfile(root .. "/MSUF_Suite_Skin_Options/Shell/Widgets.lua"))("MSUF_Suite_Skin_Options", private)
    local paints = 0
    local function Paint() paints = paints + 1 end
    O.TrackAndRefresh(Paint)
    Check(paints == 1 and tracked[1] == Paint, "TrackAndRefresh did not paint once and register")
    local order = {}
    private.Widgets.CloseOnCombat(function() order[#order + 1] = "dropdown" end)
    private.Widgets.CloseOnCombat(function() order[#order + 1] = "picker" end)
    private.Widgets.popups.dropdown = true
    private.Widgets.WatchCombat()
    local watcher = frames[1]
    Check(watcher.events.PLAYER_REGEN_DISABLED, "an open popup does not watch for combat")
    private.Widgets.popups.dropdown = false
    watcher.scripts.OnEvent(watcher, "PLAYER_REGEN_DISABLED")
    Check(order[1] == "dropdown" and order[2] == "picker" and not watcher.events.PLAYER_REGEN_DISABLED,
        "combat did not close the popups in load order")
    CreateFrame = nil
end

print(("Suite skin structure: %d checks passed"):format(checks))
