-- The group finder dialog entry of the Blizzard window catalog waits for the
-- addon that defines its popups. On Retail that is Blizzard_GroupFinder
-- (upstream/live Blizzard_GroupFinder/Mainline/LFGFrame.xml). WoW Forever
-- never loads Blizzard_GroupFinder (upstream/forever Blizzard_GroupFinder.toc:
-- ExcludeLoadGameType camelot); there LFGInvitePopup comes from the always
-- loaded Blizzard_LFGUtil (Blizzard_LFGUtil.toc, Shared/LFGInvitePopup.xml),
-- and the entry waiting for Blizzard_GroupFinder never skinned it.
-- Usage: lua suite_lfg_invite_popup_owner_contract.lua <Suite root> [Catalog.lua]
local root = assert(arg[1], "Suite root required")
local catalogSource = arg[2] or root .. "/MSUF_Suite_Skin/Adapters/Catalog.lua"
local skin = root .. "/MSUF_Suite_Skin/"
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end
local function Noop() end

-- One client session: which Blizzard addons exist and are loaded, and the
-- frames they created.
local function Session(forever, groupFinderExists)
    GameEvent = forever and { RegisterCamelotEvents = Noop } or nil
    WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
    local loaded = { Blizzard_LFGUtil = true, Blizzard_GroupFinder = not forever }
    local exists = { Blizzard_LFGUtil = true, Blizzard_GroupFinder = groupFinderExists ~= false }
    C_AddOns = {
        DoesAddOnExist = function(name) return exists[name] == true end,
        -- loadedOrLoading, loaded
        IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    }
    local loadFrame = { SetScript = Noop, RegisterEvent = Noop, UnregisterEvent = Noop }
    CreateFrame = function() return loadFrame end
    local painted = {}
    local NS = {
        IsCombatLocked = function() return false end,
        DB = { enabled = true, skins = { blizzardWindows = true }, skinCategories = { group = true } },
        GenericWindows = {},
        AdapterKit = { Isolate = function(callback, ...) callback(...) return true end, CancelDeferred = Noop },
        -- GenericWindows.lua's private helpers; ApplyFrameNow paints one root.
        GenericWindowsShared = {
            DEFAULT_OWNER = "blizzardWindows",
            OwnerState = function() return { deferred = {} } end,
            OwnerKey = tostring,
            CatalogMode = function(mode) return mode end,
            ApplyFrameNow = function(frame)
                painted[#painted + 1] = frame
                return true, "applied", {}
            end,
            DeactivateOwner = Noop,
        },
    }
    assert(loadfile(skin .. "Core/Client.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(skin .. "Core/SuiteOwnership.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(catalogSource))("MSUF_Suite_Skin", NS)
    assert(loadfile(skin .. "Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(skin .. "Adapters/GenericWindowsCatalog.lua"))("MSUF_Suite_Skin", NS)
    Check(NS.Client.isForever == (forever == true), "the client was not detected")
    return NS, painted
end

-- The roots each client defines (mirror: upstream/live and upstream/forever).
local RETAIL_ROOTS = {
    "LFDRoleCheckPopup", "LFGDungeonReadyPopup", "LFGInvitePopup", "LFGListApplicationDialog",
    "LFGListInviteDialog", "LFGReadyCheckPopup", "PVPFramePopup", "PVPRoleCheckPopup",
    "PVPReadyDialog", "PVPReadyPopup", "PlunderstormFramePopup", "PlunderstormQueueTutorialFrame",
}
local function DefineRoots(names)
    for _, name in ipairs(RETAIL_ROOTS) do _G[name] = nil end
    for _, name in ipairs(names) do _G[name] = { name = name } end
end

-- Retail: unchanged, the entry belongs to Blizzard_GroupFinder and skins all
-- of its popups.
do
    DefineRoots(RETAIL_ROOTS)
    local NS, painted = Session(false)
    local entry = assert(NS.BlizzardCatalog.FindByFrame("LFGInvitePopup"), "LFGInvitePopup left the catalog")
    Check(entry.id == "group-finder-dialogs" and entry.addon == "Blizzard_GroupFinder",
        "the Retail owner of the group finder dialogs changed")
    Check(NS.BlizzardCatalog.IsEntryGlassReady(entry), "the group finder dialogs failed the Glass review")
    local ok, state = NS.GenericWindows.ApplyEntry(entry)
    Check(ok and state == "applied" and #painted == #RETAIL_ROOTS, "Retail did not skin every group finder popup")
end

-- Forever: only LFGInvitePopup exists, from Blizzard_LFGUtil. It is skinned
-- at once, whether or not the client lists the excluded Blizzard_GroupFinder,
-- and nothing waits for an addon that never loads.
for _, groupFinderExists in ipairs({ true, false }) do
    DefineRoots({ "LFGInvitePopup" })
    local NS, painted = Session(true, groupFinderExists)
    local label = " (Blizzard_GroupFinder listed: " .. tostring(groupFinderExists) .. ")"
    local entry = assert(NS.BlizzardCatalog.FindByFrame("LFGInvitePopup"), "LFGInvitePopup left the catalog")
    Check(NS.BlizzardCatalog.IsEntryGlassReady(entry), "the Forever group finder dialogs failed the Glass review")
    NS.GenericWindows.ScheduleLoadOnDemand()
    Check(NS.GenericWindows.GetStatus(entry.id) ~= "waiting",
        "Forever left the group finder dialogs waiting for Blizzard_GroupFinder" .. label)
    local ok, state = NS.GenericWindows.ApplyEntry(entry)
    Check(ok and state == "partial" and #painted == 1 and painted[1] == LFGInvitePopup,
        "Forever did not skin LFGInvitePopup" .. label)
end

print("Suite LFG invite popup owner: " .. checks .. " checks passed")
