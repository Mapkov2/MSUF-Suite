-- Profile strings through MSUF 7.0's real profile workbench (State/
-- MSUF_ProfileWorkbench.lua: review, "Keep positions", commit, history) with
-- the Suite's provider (Core/ProfileWorkbenchBridge.lua).
--
--   lua tools/tests/suite_profile_workbench_host_contract.lua <Suite root> <MSUF 7.0 root>
--
-- The workbench reviews every value of a provider snapshot as its own
-- change, and calls the provider's Restore with true as the second argument
-- (its history passes a reason text). An import's action bars are one
-- reviewed value, keep keys such as X and Y under "Keep positions", are
-- offered one frame after the commit and never by a history step; Retail
-- and WoW Forever keep their own cooldown manager and action bars
-- (Core/ProfileClients.lua).
local suiteRoot, root = assert(arg[1], "Suite root required"), assert(arg[2], "MSUF 7.0 root required")
-- An MSUF 7.0 checkout without its offline codec cannot run the real one.
local emulator = loadfile(root .. "/tools/tests/encoding_util_emulator.lua")
if not emulator then
    print("suite_profile_workbench_host_contract: SKIP (no tools/tests/encoding_util_emulator.lua in " .. root .. ")")
    return
end
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, "Mainline", { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end })
local env, core = mw.env, mw.core
-- MSUF's offline C_EncodingUtil: the real profile codec runs.
local Emulator = emulator()
env.C_EncodingUtil = Emulator.New()
env.Enum.CompressionMethod = Emulator.CompressionMethod
env.Enum.CompressionLevel = Emulator.CompressionLevel
env.C_AddOns = {
    GetAddOnMetadata = function() end,
    IsAddOnLoaded = function(name) return name == "MidnightSimpleUnitFrames", name == "MidnightSimpleUnitFrames" end,
    DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
env.UnitGUID = function(unit) return unit == "player" and "Player-1-00000001" or nil end
local Suite = {}
local Support = assert(loadfile(suiteRoot .. "/tools/tests/suite_test_support.lua"))()
for _, file in ipairs(Support.TocFiles(suiteRoot, "MSUF_Suite", "Mainline")) do
    if file:match("%.lua$") then
        local ok, why = mw.world:LoadFile(suiteRoot .. "/MSUF_Suite/" .. file, "MSUF_Suite", Suite)
        assert(ok, file .. ": " .. tostring(why))
    end
    if file == "Core/ProfileVariants.lua" then break end
end
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local W = core.ProfileWorkbench
local P, CDM = Suite.SuiteProfiles, "cooldownManager"
local encode, decode = Suite.ProfileIO.StorageCodec()
-- Next-frame callbacks wait here; NextFrame runs them.
local queue = {}
env.C_Timer = setmetatable({ After = function(_, callback) queue[#queue + 1] = callback end }, { __index = env.C_Timer })
local function NextFrame()
    local due = queue
    queue = {}
    for _, callback in ipairs(due) do callback() end
end
local asked = 0
local live = { keys = { X = "ACTIONBUTTON5", Y = "ACTIONBUTTON6", Q = "ACTIONBUTTON1" }, slots = { [1] = 133 },
    class = "MAGE", spec = 63, label = "Fire" }
Suite.ActionBarSnapshots = {
    ProfileSetup = function() return Suite.CopyValue(live) end,
    AskProfileSetup = function() asked = asked + 1 return true end,
}
local function Cooldowns() return Suite.DB.suite.modules[CDM] end
local function OfferRows(review)
    local rows = 0
    for _, change in ipairs(review.changes) do
        for _, key in ipairs(change.path) do
            if tostring(key):find("ctionBar") then rows = rows + 1 break end
        end
    end
    return rows
end

-- A Retail string: one reviewed value for its action bars; "Keep positions"
-- keeps the X and Y keys; the offer follows the commit a frame later.
Cooldowns().listsData = "R1-lists"
local retail = assert(P.Export())
Cooldowns().listsData = "R-local"
local review = assert(W.ReviewImport(retail))
assert(OfferRows(review) == 1, "the action bars are " .. OfferRows(review) .. " reviewed values, not one")
W.Preserve(review, "positions", true)
assert(W.CommitReview(review))
assert(asked == 0 and Suite.RootDB.actionBarOffer == nil, "the action bars were offered before the commit ended")
NextFrame()
local offer = Suite.RootDB.actionBarOffer
assert(asked == 1 and offer and offer.setup.keys.X == "ACTIONBUTTON5" and offer.setup.keys.Y == "ACTIONBUTTON6"
    and offer.setup.slots[1] == 133, "the committed import lost its action bars or the X and Y keys")
assert(Cooldowns().listsData == "R1-lists", "the review did not import the cooldown manager")
Suite.RootDB.actionBarOffer = nil

-- Unticked, the import offers nothing.
Cooldowns().listsData = "R-local"
review = assert(W.ReviewImport(retail))
for _, change in ipairs(review.changes) do
    for _, key in ipairs(change.path) do
        if key == "importedActionBars" then change.selected = false end
    end
end
assert(W.CommitReview(review))
NextFrame()
assert(asked == 1 and Suite.RootDB.actionBarOffer == nil and Cooldowns().listsData == "R1-lists",
    "an unticked offer was offered or the import failed")

-- A WoW Forever string on Retail: Retail's parked part comes back, WoW
-- Forever's cooldown manager and action bars are parked, and the exporter's
-- key bindings alone are offered (its spells are the other game's).
Suite.Client.isForever = true
Cooldowns().listsData = "F2-lists"
Cooldowns().clientParked = encode({ v = 1, client = "retail", revision = Suite.Suite.MigrationRevision,
    settings = { listsData = "R9-lists" } })
live = { keys = { E = "ACTIONBUTTON3" }, slots = { [2] = 5143 }, class = "MAGE", group = 1 }
local forever = assert(P.Export())
Suite.Client.isForever = false
Cooldowns().listsData, Cooldowns().clientParked = "R-local", ""
review = assert(W.ReviewImport(forever))
assert(OfferRows(review) == 1, "the other client's key bindings are not one reviewed value")
assert(W.CommitReview(review))
NextFrame()
local parked = decode(Cooldowns().clientParked)
assert(Cooldowns().listsData == "R9-lists", "Retail did not get its parked cooldown manager back")
assert(parked and parked.client == "forever" and parked.settings.listsData == "F2-lists",
    "Retail did not park WoW Forever's cooldown manager")
local bars = decode(Suite.DB.suite.modules.actionbars.parkedSetup)
assert(bars and bars.client == "forever" and bars.setup.slots[2] == 5143, "Retail did not park WoW Forever's action bars")
offer = Suite.RootDB.actionBarOffer
assert(asked == 2 and offer and offer.client == "retail" and offer.setup.keys.E == "ACTIONBUTTON3"
    and offer.setup.slots == nil and offer.setup.class == nil,
    "the WoW Forever exporter's key bindings were not offered alone on Retail")
Suite.RootDB.actionBarOffer = nil

-- A history step restores without offering. (The direct writes above
-- bypass the history: undo steps back to its own cursor.)
assert(core.History.Undo())
NextFrame()
assert(Cooldowns().listsData ~= "R9-lists" and asked == 2 and Suite.RootDB.actionBarOffer == nil,
    "undo did not step back or it offered action bars")
-- What an MSUF profile variant sets of the cooldown manager belongs to its
-- client: a WoW Forever bundle brings Retail's parked fields back into the
-- variant of the same name and parks its own, through MSUF's own variant
-- validation.
local Variants = core.ProfileVariants
local function SetDungeon(color)
    assert(Variants.Replace(env.MSUF_DB, { version = 1, entries = { { name = "Dungeon", conditions = { context = "party" },
        patch = { { path = { "suiteModules", CDM, "cdColor" }, value = color, remove = false },
            { path = { "general", "darkMode" }, value = true, remove = false } } } } }))
end
local function DungeonFields()
    local fields, others = {}, 0
    for _, entry in ipairs(env.MSUF_DB.profileVariants.entries) do
        for _, field in ipairs(entry.name == "Dungeon" and entry.patch or {}) do
            if field.path[1] == "suiteModules" and field.path[2] == CDM then fields[field.path[3]] = field.value
            else others = others + 1 end
        end
    end
    return fields, others
end
Suite.Client.isForever = true
SetDungeon("0000ff")
Cooldowns().clientParked = encode({ v = 1, client = "retail", revision = Suite.Suite.MigrationRevision,
    settings = { listsData = "R9-lists" }, variants = { Dungeon = { { key = "cdColor", value = "ff0000" } } } })
local foreverVariants = assert(P.Export())
Suite.Client.isForever = false
SetDungeon("123456")
review = assert(W.ReviewImport(foreverVariants))
assert(W.CommitReview(review))
NextFrame()
local dungeon, others = DungeonFields()
assert(dungeon.cdColor == "ff0000" and others == 1, "the variant did not get Retail's cooldown manager field back")
parked = decode(Cooldowns().clientParked)
assert(parked.client == "forever" and parked.variants and parked.variants.Dungeon[1].key == "cdColor"
    and parked.variants.Dungeon[1].value == "0000ff", "WoW Forever's variant field was not parked")
print("suite_profile_workbench_host_contract: review, keep positions, untick, cross-client import, undo and profile variants passed")
