-- The real Suite import entry points preserve unrelated legacy chat choices and
-- restore the real skin database when a replacement cannot be activated.
local root, scenario, overlay = assert(arg[1]), arg[2] or "all", arg[3]
local originalLoad = loadfile
if overlay then
    local suffix = scenario == "chat" and "/MSUF_Suite/Core/ProfileIO.lua" or "/MSUF_Suite/Core/ProfileImports.lua"
    loadfile = function(path)
        if path:gsub("\\", "/"):sub(-#suffix) == suffix then return originalLoad(overlay) end
        return originalLoad(path)
    end
end
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, encodings, reported = {}, {}, {}
local function Noop() end
securecallfunction = function(callback, ...)
    local result = { pcall(callback, ...) }
    if result[1] then return unpack(result, 2, table.maxn(result)) end
    reported[#reported + 1] = tostring(result[2])
end
MSUF_NS, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, SlashCmdList = {}, 1, 1, {}
InCombatLockdown = function() return false end
Minimap = { SetMaskTexture = Noop }
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
C_CVar = { GetCVar = function() return nil end }
Enum, C_EncodingUtil = { CompressionMethod = { Deflate = 1 } }, {}
for _, key in ipairs({ "SerializeCBOR", "DeserializeCBOR", "EncodeBase64", "DecodeBase64", "CompressString", "DecompressString" }) do
    C_EncodingUtil[key] = Noop
end
MSUF_EncodeCompactTable = function(value, prefix)
    assert(prefix == "MSUF3")
    encodings[#encodings + 1] = value
    return "MSUF3:" .. #encodings
end
MSUF_TryDecodeCompactString = function(text) return encodings[tonumber(text:match("^MSUF3:(%d+)$"))] end
MSUF_GlobalDB, MSUF_ActiveProfile = { profiles = { Default = {} } }, "Default"
MSUF_Profiles_ExportSelectionToString = function() return "MSUF3:frames" end
MSUF_Profiles_ImportIntoNewProfile = function(name)
    MSUF_GlobalDB.profiles[name], MSUF_ActiveProfile = {}, name
    return true
end
MSUF_SwitchProfile = function(name)
    if not MSUF_GlobalDB.profiles[name] then return false end
    MSUF_ActiveProfile = name
    return true
end
MSUF_DeleteProfile = function(name) MSUF_GlobalDB.profiles[name] = nil return true end
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileVariants.lua")
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local Profiles, IO = Suite.SuiteProfiles, Suite.ProfileIO

if scenario ~= "skin" then
    local revision = Support.MigrationStep(root, "Steps.ChatComfort") - 1
    local settings = { enabled = false, muteMusic = true, whisperWindows = 3 }
    local encoded = "MSUFM2:" .. MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 2,
        module = "dailyComfort", revision = revision, settings = settings }, "MSUF3")
    local id, _, _, chat = IO.PrepareModuleProfile(encoded, true)
    assert(id == "dailyComfort" and chat.whisperWindows == 3, "legacy chat preference missing")
    assert(chat.enabled == nil and chat.chatWheel == nil and chat.noChatFade == nil
        and chat.chatClassColors == nil, "legacy daily import replaced unspecified chat settings")
    assert(Suite.Suite.SetMany("chatComfort", { enabled = true, chatWheel = true,
        noChatFade = true, chatClassColors = true, whisperWindows = 1 }))
    assert(Profiles.ImportModule(encoded))
    chat = Suite.Suite.Config("chatComfort")
    assert(chat.enabled and chat.chatWheel and chat.noChatFade and chat.chatClassColors and chat.whisperWindows == 3,
        "live legacy daily import reset unrelated chat settings")
    local rule = Suite.SuiteCatalog.chatComfort.rules.chatWheel
    rule.personal, settings.chatWheel = true, false
    _, _, _, chat = IO.PrepareModuleProfile(encoded, true)
    rule.personal = nil
    assert(chat.chatWheel == nil, "legacy module imported a character-bound chat preference")
    assert(settings.whisperWindows == 3 and settings.enabled == false, "legacy preparation changed the source")
    print("legacy daily import: sparse chat merge and personal exclusion passed")
end

if scenario ~= "chat" then
    local skin = { addonName = "MSUF_Suite_Skin", Client = { isForever = false, isMainline = true },
        IsCombatLocked = function() return false end,
        FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
        Theme = { RefreshDynamicLook = Noop }, Typography = { Restore = Noop, ApplyConfigured = Noop },
        Adapters = { ApplyAll = Noop }, Registry = { RefreshAll = Noop, NotifyListeners = Noop, AddListener = Noop } }
    for _, file in ipairs({ "Defaults", "DefaultsLooks", "Database", "DatabaseProfiles", "Safety" }) do
        assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. file .. ".lua"))("MSUF_Suite_Skin", skin)
    end
    MSUFSuite = Suite
    local database = skin.Database
    MSUFSuiteSkinDB = nil
    database.Initialize()
    MapkoSkin = skin
    Suite.Client.AddOnEnabled = function() return true end
    local imported = skin.CopyValue(skin.DB)
    imported.theme.colors.accent[1] = 0.91
    skin.ProfileIO = { PrepareProfile = function() return skin.CopyValue(imported) end }
    local activate, replace = database.SetActiveProfile, database.SetProfile
    local function VerifyFailure(kind, target, existing)
        assert(activate("Default"))
        MSUF_ActiveProfile = target
        if existing then assert(replace(target, skin.CopyValue(skin.DB))) end
        local before = Suite.CopyValue(database.GetProfile(target))
        local previous = database.GetActiveProfileName()
        local failed = false
        database.SetActiveProfile = function(name)
            if name == target and not failed then
                failed = true
                if kind ~= "refuse" then assert(activate(name)) end
                if kind == "raise" then error("injected skin activation error") end
                return false, "injected skin activation refusal"
            end
            return activate(name)
        end
        local ok, reason = Profiles.ImportModule("MSKIN1:test")
        database.SetActiveProfile = activate
        assert(not ok and reason and failed, "skin import reported success after activation failed")
        assert(database.GetActiveProfileName() == previous, "skin import failed to restore the active profile")
        local after = database.GetProfile(target)
        if before then
            assert(after.theme.colors.accent[1] == before.theme.colors.accent[1], "failed skin import lost previous settings")
        else
            assert(after == nil, "failed skin import retained an unwanted new profile")
        end
    end
    VerifyFailure("refuse", "Default", true)
    VerifyFailure("partial", "Other", true)
    VerifyFailure("raise", "Other", true)
    VerifyFailure("partial", "New", false)
    VerifyFailure("raise", "Another New", false)
    MSUF_ActiveProfile = "Default"
    assert(Profiles.ImportModule("MSKIN1:test"))
    assert(skin.DB.theme.colors.accent[1] == 0.91, "successful skin import was reverted")
    print("skin module import: real database rollback for refusal, partial activation and raised errors passed")
end
loadfile = originalLoad
