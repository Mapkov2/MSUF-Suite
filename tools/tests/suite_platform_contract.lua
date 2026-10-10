local root = assert(arg[1], "repository root required")
-- The client's securecallfunction reports an error to the error handler and
-- returns nothing; this harness models exactly that.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
local Suite, reads, frames = {}, 0, 0
local denied = { "old_client_event" }
-- Classic MSUF (the multi-client build) hosts the Suite on WoW Forever.
MSUF_NS = { Client = {
    Family = "Mainline", Flavor = "Mainline", IsForever = true, IsRetail = true,
    SupportsEvent = function(event) return event ~= denied[1] end,
}, L = { ["Active"] = "Aktiv" } }
MapkoSkin = setmetatable({}, { __index = function() error("platform read the skin owner") end })
CreateFrame = function() frames = frames + 1;error("platform allocated a runtime frame") end
C_AddOns = {
    DoesAddOnExist = function(name) reads = reads + 1;return name == "Blizzard_CooldownViewer" end,
    IsAddOnLoaded = function(name) return true, name == "Loaded" end,
}
local SECRET = {}
issecretvalue = function(value) return value == SECRET end
assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", Suite)
do
    local rootFrame = { level = 17 }
    function rootFrame:GetFrameLevel() return self.level end
    function rootFrame:SetFrameLevel(level) self.level = level end
    local child = { level = 18, writes = 0 }
    function child:GetFrameLevel() return self.level end
    function child:SetFrameLevel(level) self.level = level; self.writes = self.writes + 1 end
    assert(Suite.ApplyOwnedLayer(rootFrame, -1) == false, "older MSUF must retain its frame level")
    assert(Suite.ApplyOwnedChildLayer(child, rootFrame, 5, 2, false) == false,
        "older MSUF must retain child levels")
    local routed
    MSUF_NS.UF = { Layers = {
        ApplyOwnedSurface = function(frame, layer, detail)
            routed = { frame, layer, detail }
            return true
        end,
        ElementLevel = function(layer, _, detail) return 100 + layer * 32 + detail end,
    } }
    assert(Suite.ApplyOwnedLayer(rootFrame, 5) == true and routed[1] == rootFrame and routed[2] == 5,
        "Suite did not delegate its root to the MSUF layer contract")
    assert(Suite.ApplyOwnedChildLayer(child, rootFrame, 5, 2, false) and child.level == 262,
        "Suite child did not stay inside its parent layer slot")
    assert(not Suite.ApplyOwnedChildLayer(child, rootFrame, -1, 2, false) and child.level == 262,
        "unchanged Auto should not write children")
    assert(Suite.ApplyOwnedChildLayer(child, rootFrame, -1, 2, true) and child.level == 19,
        "Auto did not restore the child's parent-relative level")
    MSUF_NS.UF = nil
end
-- The secret-safe readers and the translation lookup live in the always
-- loaded core, so the options pages have them without the module runtime.
assert(not Suite.Public(SECRET) and Suite.Public(1) and Suite.Number(1) and not Suite.Number(0 / 0)
    and not Suite.Number(SECRET) and Suite.Finite(2) and not Suite.Finite(math.huge)
    and Suite.PublicText("x") == "x" and Suite.PublicText("") == nil and Suite.PublicText(SECRET) == nil
    and Suite.ReadText(function() return SECRET end) == nil
    and Suite.ReadText(function(value) return value end, "Dornogal") == "Dornogal"
    and Suite.Text("Active") == "Aktiv" and Suite.Text("Off") == "Off",
    "the core lacks the shared secret-safe readers or the translation lookup")
-- Statuses stay English until shown; one that names an addon is translated
-- once, from its English format, and keeps the name.
Suite.L["Managed by %s"] = "Verwaltet von %s"
local managed = Suite.FormatStatus("Managed by %s", "ElvUI")
assert(managed == "Managed by ElvUI" and Suite.StatusText(managed) == "Verwaltet von ElvUI"
    and Suite.StatusText(managed, function(text) return "[" .. text .. "]" end) == "[Managed by ElvUI]"
    and Suite.StatusText("Active") == "Aktiv" and Suite.StatusText("Off") == "Off",
    "a status is not translated exactly once where it is shown")
Suite.L["Managed by %s"] = nil
assert(Suite.RGB("ff8000") == 1 and select(2, Suite.RGB("ff8000")) == 128 / 255 and Suite.RGB("bad") == 1,
    "the shared color reader is missing from the core")
assert(Suite.Client.flavor == "Forever" and Suite.Client.isMainline and not Suite.Client.modernEquipment)
assert(Suite.Client.SupportsEvent("UNIT_AURA") and not Suite.Client.SupportsEvent("old_client_event"))
assert(Suite.Client.HasAddOn("Blizzard_CooldownViewer") and not Suite.Client.HasAddOn("Missing"))
assert(Suite.Client.IsAddOnLoaded("Loaded") and not Suite.Client.IsAddOnLoaded("Incomplete"))
assert(Suite.L == MSUF_NS.L and frames == 0 and reads == 2)
assert(Suite.Client.isClassic == nil and Suite.Client.family == nil,
    "the Suite no longer models Classic clients")
-- Forever's Gamepad UI: Suite windows go through Classic MSUF's pad navigation.
-- Blizzard's frame controls manager is never called: registering an addon
-- window there taints the gamepad input state (blocked spellbook casts,
-- SetPreferredGamepadInteractTarget) and SmartNavigation rescans the window on
-- every CreateFrame below it. Pointer mode keeps the native cursor call.
do
    local style, cursor = true, 0
    local calls = {}
    local function Record(name) return function(frame) calls[#calls + 1] = name .. ":" .. frame.name end end
    InputUtil = { IsGamepadUIEnabled = function() return style end }
    GamepadMode = { FrameControlsManager = setmetatable({}, { __index = function(_, key)
        error("the Suite called Blizzard's frame controls manager: " .. tostring(key))
    end }) }
    MSUF_PadNavigation = { Attach = Record("attach"), Activate = Record("activate"), Release = Record("release") }
    CanAutoSetGamePadCursorControl = function(on) return on == true end
    SetGamePadCursorControl = function(on) assert(on == true); cursor = cursor + 1 end
    local window = { name = "SuiteWindow", shown = true }
    function window:IsShown() return self.shown end
    Suite.Client.AttachControllerWindow(window)
    Suite.Client.ResumeControllerWindow(window)
    Suite.Client.PauseControllerWindow(window)
    assert(table.concat(calls, ",") == "attach:SuiteWindow,activate:SuiteWindow,release:SuiteWindow",
        "Suite windows did not forward to MSUF's pad navigation: " .. table.concat(calls, ","))
    assert(Suite.Client.HasControllerNavigation() == true, "the host's pad navigation was not reported")
    -- A host without the navigation (Retail-only MSUF, an older Classic) is a no-op.
    MSUF_PadNavigation = nil
    assert(Suite.Client.HasControllerNavigation() == false, "a host without pad navigation reported one")
    Suite.Client.AttachControllerWindow(window)
    Suite.Client.ResumeControllerWindow(window)
    Suite.Client.PauseControllerWindow(window)
    assert(#calls == 3 and cursor == 0)
    style = false
    Suite.Client.RaiseControllerCursor()
    assert(cursor == 1)
    InputUtil, GamepadMode = nil, nil
    CanAutoSetGamePadCursorControl, SetGamePadCursorControl = nil, nil
end
local notifications, owner = 0, {}
Suite.Registry.AddListener(owner, function(who, domain, name)
    assert(who == owner and domain == "profile" and name == "Raid")
    notifications = notifications + 1
end)
Suite.OnProfileChanged("Raid")
assert(notifications == 1)
-- A listener that raises is reported; the other listeners still hear the change.
local failing = {}
Suite.Registry.AddListener(failing, function() error("listener failed") end)
Suite.OnProfileChanged("Raid")
assert(notifications == 2 and #reported == 1 and reported[1]:find("listener failed", 1, true),
    "one failing profile listener stopped the others")
Suite.Registry.RemoveListener(failing)
Suite.Registry.RemoveListener(owner)
Suite.OnProfileChanged("Raid")
assert(notifications == 2 and frames == 0 and #reported == 1)
assert(Suite.Host.build == "Classic")
local selectedFont = "Interface\\AddOns\\Test\\Selected.ttf"
MSUF_GetFontPath = function() return selectedFont end
assert(Suite.GlobalFontPath() == selectedFont, "Suite default did not follow MSUF's global font")
selectedFont = "Interface\\AddOns\\Test\\Changed.ttf"
assert(Suite.GlobalFontPath() == selectedFont, "Suite cached MSUF's global font")
selectedFont = SECRET
assert(Suite.GlobalFontPath() == Suite.MSUFMedia.font, "a secret font path escaped the fallback")
MSUF_GetFontPath = nil
assert(Suite.GlobalFontPath() == Suite.MSUFMedia.font, "the missing MSUF export lost the fallback")
-- Finish tells a completed call from one that raised.
local finished, a, b = Suite.Dispatch(Suite.Finish, function() return 1, 2 end)
assert(finished == true and a == 1 and b == 2)
assert(Suite.Dispatch(Suite.Finish, error, "raised") == nil and #reported == 2)

-- Main MSUF publishes no client model. The suite derives the same facts from
-- the project ID and Blizzard's Forever marker, and caches event validity.
local function Boot(project, forever)
    local suite, checks = {}, 0
    MSUF_NS = { L = {} }
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = project, 1
    GameEvent = forever and { RegisterCamelotEvents = function() end } or nil
    C_EventUtils = { IsEventValid = function(event) checks = checks + 1;return event ~= "MISSING_EVENT" end }
    assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", suite)
    return suite, function() return checks end
end
local main, checks = Boot(1, false)
assert(main.Host.build == "Main" and main.Client.flavor == "Mainline" and main.Client.isMainline)
assert(main.Client.modernEquipment and not main.Client.isForever)
assert(main.Client.SupportsEvent("UNIT_AURA") and not main.Client.SupportsEvent("MISSING_EVENT"))
assert(main.Client.SupportsEvent("UNIT_AURA") and checks() == 2, "event validity was not cached")
local forever = Boot(1, true)
assert(forever.Client.flavor == "Forever" and forever.Client.isMainline and not forever.Client.modernEquipment)
-- Only the Mainline TOC exists, so the marker places Forever whatever project
-- ID the client reports.
local foreverProject = Boot(2, true)
assert(foreverProject.Client.flavor == "Forever" and foreverProject.Client.isForever)
local unknown = Boot(2)
assert(unknown.Client.flavor == "Unknown" and not unknown.Client.isMainline and not unknown.Client.modernEquipment)
assert(Boot(99).Client.flavor == "Unknown" and frames == 0)

-- MSUF's font path lives only in NS.MSUFMedia, and every Suite file shares
-- the core's secret-safe readers instead of keeping its own copies.
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local READERS = { "function Text%(", "function PublicText%(", "function ReadText%(" }
local sources = {}
for _, addon in ipairs({ "MSUF_Suite", "MSUF_Suite_Modules", "MSUF_Suite_Options" }) do
    for _, file in ipairs(Support.TocFiles(root, addon)) do
        local source = assert(io.open(root .. "/" .. addon .. "/" .. file, "rb")):read("*a")
        sources[addon .. "/" .. file] = source
        if file ~= "Core/Platform.lua" then
            assert(not source:find("Expressway SemiBold.ttf", 1, true), addon .. "/" .. file .. " hard-codes MSUF's font")
            assert(not source:find("issecretvalue", 1, true) and not source:find("function Public%("),
                addon .. "/" .. file .. " keeps its own secret check")
        end
        if addon == "MSUF_Suite_Modules" then
            for _, reader in ipairs(READERS) do
                assert(not source:find(reader), addon .. "/" .. file .. " keeps its own text reader")
            end
        end
    end
end
-- Leftovers stay gone: the unused error reporter, the runtime's local event
-- router named like S.Dispatch, global CVar fallbacks (C_CVar exists on both
-- clients) and the Mainline name of the modern-equipment capability.
assert(not sources["MSUF_Suite/Core/Platform.lua"]:find("ReportError", 1, true), "Suite.ReportError is back")
local runtime = sources["MSUF_Suite_Modules/Runtime.lua"]
assert(not runtime:find("local function Dispatch(", 1, true), "the runtime's event router shadows S.Dispatch")
for _, file in ipairs({ "MSUF_Suite_Modules/Runtime.lua", "MSUF_Suite_Options/Pages/Chat.lua" }) do
    assert(not sources[file]:find("[^_%.]GetCVar") and not sources[file]:find("[^_%.]SetCVar")
        and not sources[file]:find("_G.GetCVar", 1, true), file .. " falls back to the global CVar functions")
end
for file, source in pairs(sources) do
    assert(not source:find("buffRemindersMainline", 1, true), file .. " names modern equipment Mainline")
end
-- APIs Blizzard's live and forever UI source both define or call are used
-- directly; test harnesses stub them instead of production code guarding them.
local ALWAYS = { "GetTime", "GetFramerate", "GetNetStats", "GetGameTime", "GetServerTime",
    "GetInventoryItemDurability", "GetMoney", "UnitLevel", "UnitXP", "UnitXPMax", "SetPortraitTexture",
    "GetInventoryItemTexture", "GetInventoryItemLink", "InCombatLockdown", "UnitIsAFK", "C_Timer.After",
    "GetCVar", "SetCVar" }
for _, file in ipairs({ "MSUF_Suite_Modules/DataSources.lua", "MSUF_Suite_Modules/AFKScreen.lua",
    "MSUF_Suite/Core/Catalog/Bags.lua" }) do
    for _, api in ipairs(ALWAYS) do
        assert(not sources[file]:find("type(" .. api .. ")", 1, true)
            and not sources[file]:find("type(_G." .. api .. ")", 1, true), file .. " guards " .. api)
    end
end
local bagsCatalog = sources["MSUF_Suite/Core/Catalog/Bags.lua"]
assert(bagsCatalog:find("C_CVar.GetCVar(", 1, true) and not bagsCatalog:find("[^_%.]GetCVar%("),
    "the Bags catalog reads the global GetCVar")
print("Standalone suite platform: Classic and Main hosts, Forever detection, optional-addon queries, locale, isolated profile listeners and Finish passed")
