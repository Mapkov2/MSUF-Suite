-- Code that other addons register through the skin's public API runs through
-- Safety.Dispatch. The client's securecallfunction reports an error to the
-- error handler and returns nothing; this harness models exactly that. A
-- failing adapter or theme listener is reported and the others still run.
local root = assert(arg[1], "repository root required")

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
-- Retail and Forever always have C_Timer; this stand-in runs at once.
C_Timer = { After = function(_, callback) callback() end }

local function Frame()
    return {
        IsForbidden = function() return false end,
        IsProtected = function() return false, false end,
    }
end

local NS = {
    DB = { enabled = true, skins = {} },
    Client = { HasAddOn = function() return false end },
    IsCombatLocked = function() return false end,
    CombatGate = { RunOrDefer = function() error("no combat in this contract") end },
    WindowControls = { DisableOwner = function() end, Attach = function() end },
    Cosmetics = { RestoreOwner = function() end },
    Surface = { Attach = function(frame) return frame end, SetVisible = function() end },
    Checkmarks = { TrackControlTree = function() end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Core/SuiteOwnership.lua",
    "Adapters/Blizzard.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end

local Adapters = NS.Adapters
local applied = {}
local function Definition(id, apply, resolve)
    return {
        id = id,
        resolve = resolve or function() return Frame() end,
        apply = apply or function() applied[#applied + 1] = id; return true end,
    }
end
assert(Adapters.Register(Definition("before")))
assert(Adapters.Register(Definition("broken-apply", function() error("foreign apply failed") end)))
assert(Adapters.Register(Definition("broken-resolve", nil, function() error("foreign resolve failed") end)))
assert(Adapters.Register(Definition("after")))

assert(Adapters.ApplyAll() == true)
assert(#applied == 2 and applied[1] == "before" and applied[2] == "after",
    "a failing adapter stopped the adapters after it")
assert(#reported == 2 and reported[1]:find("foreign apply failed", 1, true)
    and reported[2]:find("foreign resolve failed", 1, true), "adapter errors were not reported")
assert(Adapters.status["broken-apply"].state == "error", "a failed apply was reported as applied")
assert(Adapters.status["broken-resolve"].state == "missing")
assert(Adapters.status.after.state == "applied")

local heard = {}
NS.Registry.AddListener({}, function() error("foreign listener failed") end)
NS.Registry.AddListener({}, function(_, domain, key) heard[#heard + 1] = domain .. ":" .. key end)
NS.Registry.AddListener({}, function(_, domain, key) heard[#heard + 1] = domain .. ":" .. key end)
assert(NS.Registry.NotifyListeners("theme", "look") == true)
assert(#heard == 2, "a failing theme listener stopped the others")
assert(#reported == 3 and reported[3]:find("foreign listener failed", 1, true))

local function Reported(text)
    for index = 1, #reported do
        if reported[index]:find(text, 1, true) then return true end
    end
    return false
end

-- The icon tree and window controls that follow an adapter's own callbacks
-- belong to the same boundary: ApplyAll reports them and goes on.
applied, reported = {}, {}
local tree = Definition("tree-fails")
tree.trackIconTree = true
assert(Adapters.Register(tree))
assert(Adapters.Register(Definition("after-tree")))
NS.Checkmarks.TrackControlTree = function(_, id)
    if id == "tree-fails" then error("icon tree failed") end
end
assert(Adapters.ApplyAll() == true)
assert(applied[#applied] == "after-tree" and Adapters.status["after-tree"].state == "applied",
    "an adapter whose icon tree raised stopped the adapters after it")
assert(Adapters.status["tree-fails"].state == "error" and Reported("icon tree failed"),
    "an icon tree error was not reported on its adapter")
NS.Checkmarks.TrackControlTree = function() end

-- Every sub-skin of the Blizzard window adapter is its own boundary, when it
-- applies and when it releases.
local PART_NAMES = { "DeepWindows", "SemanticHUD", "SharedChrome", "UIPanelButtons", "CommonMenus",
    "Commerce", "CharacterPanel", "InspectPanel", "SocialUISkin", "MajorWindows", "LegacyWindows",
    "CommonArt", "ForeverGroupFinder" }
local partCalls = {}
for _, name in ipairs(PART_NAMES) do
    NS[name] = {
        Apply = function()
            partCalls[name .. ":apply"] = true
            if name == "SharedChrome" then error("shared chrome apply failed") end
            return true
        end,
        Disable = function()
            partCalls[name .. ":disable"] = true
            if name == "SharedChrome" then error("shared chrome disable failed") end
            return true
        end,
    }
end
local genericReleased = false
NS.GenericWindows = {
    ApplyAll = function() return true, "applied" end,
    IsCategoryEnabled = function() return true end,
    Disable = function() genericReleased = true; return true end,
}
NS.MacroWindow = { Start = function() end }
NS.Client.isForever = false
NS.BlizzardCatalog = Frame()
reported = {}
assert(Adapters.Apply("blizzardWindows") == true,
    "a failing window part stopped the Blizzard window adapter")
for _, name in ipairs(PART_NAMES) do
    assert(partCalls[name .. ":apply"], "a failing window part stopped " .. name)
end
assert(Adapters.GetStatus("blizzardWindows") == "partial" and Reported("shared chrome apply failed"),
    "a failing window part was not reported as a partial apply")
NS.DB.skins.blizzardWindows = false
reported = {}
Adapters.Apply("blizzardWindows")
for _, name in ipairs(PART_NAMES) do
    assert(partCalls[name .. ":disable"], "a failing window part kept " .. name .. " skinned")
end
assert(genericReleased and Adapters.GetStatus("blizzardWindows") == "error"
    and Reported("shared chrome disable failed"),
    "a window part that failed to release was not reported")

-- Every part module loads before Blizzard.lua, so no part is probed for
-- being loaded: a part that raises before it starts (here its module table
-- is gone) is reported like any raising part, and the parts after it still
-- apply and release.
local commonMenus = NS.CommonMenus
NS.CommonMenus = nil
partCalls = {}
NS.DB.skins.blizzardWindows = true
reported = {}
Adapters.Apply("blizzardWindows")
for _, name in ipairs(PART_NAMES) do
    assert(name == "CommonMenus" or partCalls[name .. ":apply"],
        "a raising window part stopped " .. name)
end
assert(Adapters.GetStatus("blizzardWindows") == "partial" and Reported("a nil value"),
    "a window part without its module was not reported as a partial apply")
NS.DB.skins.blizzardWindows = false
reported = {}
Adapters.Apply("blizzardWindows")
for _, name in ipairs(PART_NAMES) do
    assert(name == "CommonMenus" or partCalls[name .. ":disable"],
        "a raising window part kept " .. name .. " skinned")
end
assert(Adapters.GetStatus("blizzardWindows") == "error" and Reported("a nil value"),
    "a window part without its module released as complete")
NS.CommonMenus = commonMenus

-- Login stages: each one is its own boundary, so the later stages and the
-- API clients still start.
local frames = {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, script) self.script = script end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    frames[#frames + 1] = frame
    return frame
end
local stages = {}
local function Stage(name)
    return function() stages[#stages + 1] = name end
end
local life = {
    Safety = NS.Safety,
    InitializeLocalization = function() end,
    Database = { Initialize = function() end },
    Theme = { RefreshDynamicLook = Stage("look") },
    BlizzardYellow = { Apply = function() error("gold text failed") end },
    Checkmarks = { Apply = Stage("checkmarks") },
    Typography = { ApplyConfigured = Stage("typography") },
    Adapters = { ApplyAll = Stage("adapters") },
    PublicAPI = { OnDatabaseReady = function() end, OnPlayerLogin = Stage("api") },
}
reported = {}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Lifecycle.lua"))("MSUF_Suite_Skin", life)
local lifecycle = frames[#frames]
lifecycle.script(lifecycle, "PLAYER_LOGIN")
assert(table.concat(stages, ",") == "look,checkmarks,typography,adapters,api"
    and Reported("gold text failed"), "a failing login stage stopped the stages after it")

-- Deferred combat jobs: each job is its own boundary within one drain.
local locked = false
local gate = { Safety = NS.Safety, IsCombatLocked = function() return locked end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/CombatGate.lua"))("MSUF_Suite_Skin", gate)
local gateFrame = frames[#frames]
local ran = {}
locked = true
for index = 1, 6 do
    gate.CombatGate.RunOrDefer("job" .. index, function()
        ran[#ran + 1] = index
        if index == 2 or index == 5 then error("deferred job " .. index .. " failed") end
    end)
end
assert(gateFrame.events.PLAYER_REGEN_ENABLED and gate.CombatGate.GetPendingCount() == 6)
locked = false
reported = {}
gateFrame.script(gateFrame, "PLAYER_REGEN_ENABLED")
assert(#ran == 6 and #reported == 2, "a failing deferred job stopped the drain")
assert(gate.CombatGate.GetPendingCount() == 0 and not gateFrame.events.PLAYER_REGEN_ENABLED,
    "the drain left jobs or its event behind")

-- Checkmark tree walks: a visit that raises is reported and releases the
-- shared walk state; the Settings row walk restores its state the same way.
local function NoAction() return false end
local marks = {
    Safety = NS.Safety,
    DB = { enabled = true },
    IsCombatLocked = function() return false end,
    Registry = { AddListener = function() end },
    Theme = { GetColor = function() return 1, 1, 1, 1 end },
    -- BlizzardYellow loads before, WindowActionSkin after these files; no
    -- button here is a window action.
    BlizzardYellow = { TrackDropdown = function() end },
    WindowActionSkin = { HasOwnedStates = NoAction, IsApplied = NoAction },
}
for _, file in ipairs({ "Core/Checkmarks.lua", "Core/CheckmarksMenus.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", marks)
end
local brokenRoot = Frame()
brokenRoot.GetNormalTexture = function() error("button texture failed") end
reported = {}
local changed, nodes = marks.Checkmarks.TrackControlTree(brokenRoot, "walk-contract")
assert(changed == false and nodes == 0 and Reported("button texture failed"),
    "a raising tree visit escaped the walk")
local healthy = Frame()
healthy.GetChildren = function() return Frame(), Frame() end
reported = {}
changed, nodes = marks.Checkmarks.TrackControlTree(healthy, "walk-contract")
assert(nodes == 3 and #reported == 0, "the walk after a failed one did not visit the whole tree")

EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
ButtonGroupBaseMixin = { Event = { Selected = "Selected" } }
local categories = Frame()
categories.ScrollBox = {
    RegisterCallback = function() end,
    UnregisterCallback = function() end,
    ForEachFrame = function() error("category rows failed") end,
}
reported = {}
assert(marks.Checkmarks.TrackSettingsCategories(categories, "settings-contract", {}) == true
    and Reported("category rows failed"), "a raising Settings row walk escaped")
EventRegistry, ScrollBoxListMixin, ButtonGroupBaseMixin = nil, nil, nil

-- The master switch: each stage is its own boundary, so a stage that raises
-- is reported and the later stages and the listeners still run.
local masterStages = {}
local function MasterStage(name)
    return function() masterStages[#masterStages + 1] = name end
end
NS.BlizzardYellow = { Apply = function() error("gold text stage failed") end }
NS.Checkmarks.Apply = MasterStage("checkmarks")
NS.Typography = { ApplyConfigured = MasterStage("typography") }
local masterOwner, masterHeard = {}, nil
NS.Registry.AddListener(masterOwner, function(_, domain, key)
    if domain == "adapter" then masterHeard = key end
end)
reported = {}
assert(Adapters.SetMasterEnabled(true) and table.concat(masterStages, ",") == "checkmarks,typography"
    and masterHeard == "master" and Reported("gold text stage failed"),
    "a failing master switch stage stopped the stages after it")

-- Profile activation and the look: each stage is its own boundary, and the
-- Suite's look callback is foreign code.
local engine = {
    Client = { isForever = false },
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    IsCombatLocked = function() return false end,
}
for _, file in ipairs({ "Core/Defaults.lua", "Core/Database.lua", "Core/DatabaseProfiles.lua", "Core/Safety.lua",
    "Core/Registry.lua", "Core/Theme.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", engine)
end
engine.RootDB = { activeProfile = "Default", profiles = {
    Default = engine.CopyValue(engine.Defaults), Raid = engine.CopyValue(engine.Defaults) } }
engine.DB = engine.RootDB.profiles.Default
local profileStages = {}
engine.Typography = {
    Restore = function() end,
    ApplyConfigured = function() error("typography stage failed") end,
}
engine.Adapters = { ApplyAll = function() profileStages[#profileStages + 1] = "adapters" end }
local engineOwner, engineHeard = {}, {}
engine.Registry.AddListener(engineOwner, function(_, domain, key)
    engineHeard[#engineHeard + 1] = domain .. ":" .. key
end)
reported = {}
assert(engine.Database.SetActiveProfile("Raid") and profileStages[1] == "adapters"
    and engineHeard[1] == "profile:activate" and Reported("typography stage failed"),
    "a failing profile stage stopped the stages after it")
-- The factory reset applies its profile through the same stages, announced
-- as a theme reset.
engineHeard, profileStages = {}, {}
engine.Database.ApplyActiveSettings("reset", "theme")
assert(profileStages[1] == "adapters" and engineHeard[1] == "theme:reset",
    "the shared profile apply did not run its stages or announce a theme reset")
_G.MSUFSuite = { Suite = { ApplyGlobalLook = function() error("suite look failed") end } }
reported, engineHeard = {}, {}
assert(engine.Theme.ApplyLook("midnight") and engine.DB.theme.look == "midnight"
    and engineHeard[1] == "theme:look" and Reported("suite look failed"),
    "a failing Suite look stopped the skin look")
_G.MSUFSuite = nil

print("Suite skin dispatch: failing foreign adapters and listeners are reported and isolated")
