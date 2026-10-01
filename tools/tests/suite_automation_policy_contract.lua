-- Automation policy (MSUF_Suite/Core/SuiteCatalog.lua): every setting that
-- makes the Suite act on the player's behalf carries an automation flag in the
-- catalog. Shared imports switch all of them off (S.SanitizeImport) and the
-- profile-variant layer never holds them (Core/ProfileVariants.lua), so
-- neither a shared Suite string nor a shared MSUF variant patch can turn on
-- spending or automation. A source scan ties the flags to the runtime: a
-- module that calls an automation API must be flagged, unless the call only
-- follows an explicit click or confirmation listed below.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, provider, registered, overlay = {}, nil, {}, false
local frame = { general = {} }
local core = { UF = {}, ProfileRuntime = { Apply = function() end } }
MSUF_NS = core
MSUF_GlobalDB, MSUF_DB, MSUF_ActiveProfile = { profiles = { Default = frame } }, frame, "Default"
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
Minimap = { SetMaskTexture = function() end }
securecallfunction = function(fn, ...) return fn(...) end
core.ProfileFields = { RegisterExternal = function(name, value) assert(name == "suiteModules"); provider = value end }
core.ProfileVariants = {
    BaseSnapshot = function() return { suiteModules = provider.Snapshot(Suite.DB.suite.modules) } end,
    HasExternalOverlay = function() return overlay end,
    IsRecording = function() return false end,
    IsMaterialized = function() return overlay end,
    Restore = function() overlay = false end,
    ResolveCurrent = function() return true end,
}
core.ProfileSync = { RegisterModule = function(id) registered[id] = true end, RebaseExternal = function() end }
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileVariants.lua")
local catalog, order = Suite.SuiteCatalog, Suite.SuiteOrder

local function Check(condition, message)
    if not condition then error("suite_automation_policy_contract: " .. message, 2) end
    return condition
end

------------------------------------------------------------------ the policy
-- Kept here on purpose: dropping a flag from the catalog fails this list, and
-- an automation API call in an unflagged module fails the source scan.
local MODULES = { "qol", "quests", "combatLog", "lootContainers", "trustedPartyInvites", "delveSolePower",
    "professionAppearance", "collectionNewMarkers" }
local SWITCHES = { "qol.repair", "qol.autoJunk", "loot.quickLoot", "dailyComfort.autoSkipCinematic",
    "groupRaidShortcuts.autoMarkTank", "groupRaidShortcuts.autoMarkHealer", "groupFinderDoubleClick.quickApply",
    "mythicKeyShare.insertKey", "mythicResetReminder.announceReset", "tooltipDetails.inspectHovered" }
local expected = {}
for _, id in ipairs(MODULES) do
    Check(catalog[id] and catalog[id].automation == true, "automation module is not flagged: " .. id)
    expected[id .. ".enabled"] = true
end
for _, key in ipairs(SWITCHES) do expected[key] = true end
local flagged = 0
for _, id in ipairs(order) do
    for key, rule in pairs(catalog[id].rules) do
        if rule.automation then
            flagged = flagged + 1
            Check(expected[id .. "." .. key], "unexpected automation flag: " .. id .. "." .. key)
            Check(type(rule.default) == "boolean", "automation flag on a non-switch: " .. id .. "." .. key)
        end
    end
end
for key in pairs(expected) do
    local id, rule = key:match("^([^.]+)%.(.+)$")
    Check(catalog[id].rules[rule].automation == true, "automation switch is not flagged: " .. key)
end
Check(flagged == #MODULES + #SWITCHES, "automation flags drifted from the policy: " .. flagged)

------------------------------------------------------------------ shared imports
-- A profile with every switch of every module on, imported as shared data.
local profile = { suite = { schema = 1, revision = Suite.Suite.MigrationRevision, modules = {} } }
for _, id in ipairs(order) do
    local config = {}
    for key, rule in pairs(catalog[id].rules) do
        if type(rule.default) == "boolean" then config[key] = true end
    end
    profile.suite.modules[id] = config
end
local shared = Check(Suite.ProfileIO.PrepareTable(profile, true), "shared profile was rejected")
local trusted = Check(Suite.ProfileIO.PrepareTable(profile, false), "trusted profile was rejected")
for key in pairs(expected) do
    local id, rule = key:match("^([^.]+)%.(.+)$")
    Check(shared.suite.modules[id][rule] == false, "a shared profile kept automation on: " .. key)
    Check(trusted.suite.modules[id][rule] == true, "a trusted factory import lost an automation choice: " .. key)
end
for _, key in ipairs({ "actionbars.enabled", "minimap.enabled", "tooltipIDs.enabled", "lootVendorRules.enabled",
    "loot.manageHistory", "dailyComfort.enabled", "dailyComfort.hideTutorials", "groupRaidShortcuts.enabled",
    "mythicKeyShare.enabled", "groupFinderDoubleClick.enabled" }) do
    local id, rule = key:match("^([^.]+)%.(.+)$")
    Check(shared.suite.modules[id][rule] == true, "a shared import switched off an ordinary setting: " .. key)
end

------------------------------------------------------------------ profile variants
Check(Suite.Database.Initialize(nil), "Suite test profile did not initialize")
Suite.Suite.Normalize(Suite.DB)
Check(Suite.ProfileVariants.Register(), "the variant adapter did not register")
local modules = Suite.DB.suite.modules
for key in pairs(expected) do
    local id, rule = key:match("^([^.]+)%.(.+)$")
    modules[id][rule] = true
end
local snapshot = provider.Snapshot(modules)
for key in pairs(expected) do
    local id, rule = key:match("^([^.]+)%.(.+)$")
    local path = { "suiteModules", id, rule }
    Check(not provider.Allows(path), "a variant may hold automation: " .. key)
    local _, valid = provider.Check(path, true, false)
    Check(not valid, "a variant patch with automation passed validation: " .. key)
    _, valid = provider.Check(path, nil, true)
    Check(not valid, "a variant removal of automation passed validation: " .. key)
    Check(not (snapshot[id] and snapshot[id][rule] ~= nil), "the variant snapshot carried automation: " .. key)
end
for _, id in ipairs(MODULES) do
    Check(snapshot[id] == nil and not registered["suite:" .. id], "an automation module joined variants or sync: " .. id)
    Check(not provider.Allows({ "suiteModules", id, next(catalog[id].rules) }), "an automation module rule is variant-able: " .. id)
end
for _, key in ipairs({ "loot.manageHistory", "dailyComfort.hideTutorials", "groupRaidShortcuts.showPanel",
    "mythicKeyShare.fontSize", "tooltipIDs.enabled" }) do
    local id, rule = key:match("^([^.]+)%.(.+)$")
    Check(provider.Allows({ "suiteModules", id, rule }) and snapshot[id] and snapshot[id][rule] ~= nil
        and registered["suite:" .. id], "an ordinary setting left the variant layer: " .. key)
end
-- Restoring a variant base leaves the stored automation values alone.
snapshot.loot.manageHistory = false
modules.loot.quickLoot = true
Check(provider.Restore(modules, snapshot), "variant base did not restore")
Check(modules.loot.manageHistory == false and modules.loot.quickLoot == true,
    "a variant restore changed an automation setting or missed an ordinary one")
-- The base profile behind an overlay keeps the stored automation values.
overlay = true
local base = Check(Suite.ProfileVariants.BaseProfile("Default"), "base profile failed")
Check(base.suite.modules.loot.quickLoot == true and base.suite.modules.quests.enabled == true
    and base.suite.modules.mythicKeyShare.insertKey == true, "the base profile lost a stored automation setting")
overlay = false

------------------------------------------------------------------ runtime source scan
local function Strip(source)
    local out, i, n = {}, 1, #source
    while i <= n do
        local at = source:find("[%-\"'%[]", i)
        if not at then out[#out + 1] = source:sub(i); break end
        out[#out + 1] = source:sub(i, at - 1)
        local c = source:sub(at, at)
        local long = c == "[" and source:match("^%[(=*)%[", at)
        local comment = c == "-" and source:sub(at, at + 1) == "--"
        if comment then
            local level = source:match("^%[(=*)%[", at + 2)
            if level then
                local close = source:find("]" .. level .. "]", at + 4 + #level, true)
                i = close and close + #level + 2 or n + 1
            else
                i = source:find("\n", at, true) or n + 1
            end
        elseif long then
            local close = source:find("]" .. long .. "]", at + 2 + #long, true)
            out[#out + 1] = '""'
            i = close and close + #long + 2 or n + 1
        elseif c == '"' or c == "'" then
            local j = at + 1
            while j <= n do
                local d = source:sub(j, j)
                if d == "\\" then j = j + 2 elseif d == c or d == "\n" then break else j = j + 1 end
            end
            out[#out + 1] = '""'
            i = j + 1
        else
            out[#out + 1] = c
            i = at + 1
        end
    end
    return table.concat(out)
end

-- Game actions taken for the player. LoggingCombat counts only when it sets.
local APIS = {
    "RepairAllItems", "SellAllJunkItems", "UseContainerItem", "AcceptQuest", "CompleteQuest", "GetQuestReward",
    "SelectActiveQuest", "SelectAvailableQuest", "AcceptGroup", "LootSlot", "ConfirmLootSlot",
    "BuyTrainerService", "BuyMerchantItem", "ClearFanfare", "SetRaidTarget", "SendPlayerChoiceResponse",
    "CancelAuraByInstanceID", "CancelUnitBuff", "SendChatMessage", "SendAddonMessage", "NotifyInspect",
    "StopCinematic", "CinematicFrame_CancelCinematic", "CreateMacro", "SlotKeystone", "DoReadyCheck",
    "DoCountdown", "LFGListApplicationDialogSignUpButton_OnClick", "ApplyToGroup", "TaxiRequestEarlyLanding",
    "SetLootSpecialization",
}
-- Calls that run only after the player's own click or confirmation.
local CONFIRMED = {
    ["MSUF_Suite_QualityOfLife/TrainerLearnAll.lua BuyTrainerService"] = "learns after the cost confirmation",
    ["MSUF_Suite_QualityOfLife/LootVendorRules.lua UseContainerItem"] = "sells after the sale confirmation",
    ["MSUF_Suite_QualityOfLife/MacroBuilder.lua CreateMacro"] = "the explicit Create button",
    ["MSUF_Suite_QualityOfLife/FlightTimer.lua TaxiRequestEarlyLanding"] = "the explicit Land button",
    ["MSUF_Suite_Minimap/Specialization.lua SetLootSpecialization"] = "the explicit menu choice",
    ["MSUF_Suite_QualityOfLife/MerchantList.lua BuyMerchantItem"] =
        "the player's click on a Suite merchant row; currency, item and high-price purchases ask first, like Blizzard's rows",
    ["MSUF_Suite_Bags/BankActions.lua UseContainerItem"] = "the player's right click on a Suite bank slot withdraws it",
}
-- Addons whose files all belong to one catalog module.
local ADDON_MODULE = {
    MSUF_Suite_ActionBars = "actionbars", MSUF_Suite_Bags = "bags", MSUF_Suite_BuffReminders = "buffReminders",
    MSUF_Suite_Chat = "chat", MSUF_Suite_CooldownManager = "cooldownManager", MSUF_Suite_DamageMeter = "damageMeter",
    MSUF_Suite_DataTexts = "dataTexts", MSUF_Suite_Minimap = "minimap", MSUF_Suite_Nameplates = "nameplates",
}
-- Every Lua file the Suite addons load (their TOCs), vendored Libs/ excluded.
local function Files()
    local addons, seen, list = { "MSUF_Suite", "MSUF_Suite_Modules", "MSUF_Suite_Options",
        "MSUF_Suite_Skin", "MSUF_Suite_Skin_Options" }, {}, {}
    for _, id in ipairs(order) do addons[#addons + 1] = catalog[id].addon end
    for _, addon in ipairs(addons) do
        if not seen[addon] then
            seen[addon] = true
            for _, file in ipairs(Support.TocFiles(root, addon)) do
                if file:match("%.lua$") and not file:find("^Libs/") then list[#list + 1] = addon .. "/" .. file end
            end
        end
    end
    table.sort(list)
    return list
end
-- The catalog module a file belongs to, from its raw source.
local function Owner(rel, source)
    local addon = rel:match("^([^/]+)/")
    local id = source:match("S%.Install%(%s*\"(%w+)\"")
    if not id and source:find("S%.Install%(%s*ID%s*,") then
        id = source:match("local%s+ID%s*,?[%w_%s,]*=%s*\"(%w+)\"")
    end
    return id or ADDON_MODULE[addon]
end
local function Flagged(id)
    local spec = catalog[id]
    if not spec then return false end
    if spec.automation then return true end
    for _, rule in pairs(spec.rules) do if rule.automation then return true end end
    return false
end
local files, used, scanned = Files(), {}, 0
Check(#files > 100, "the source scan found too few Suite files: " .. #files)
for _, rel in ipairs(files) do
    local handle = assert(io.open(root .. "/" .. rel, "rb"))
    local source = handle:read("*a")
    handle:close()
    local code, owner = Strip(source), Owner(rel, source)
    scanned = scanned + 1
    for _, api in ipairs(APIS) do
        if code:find("%f[%w_]" .. api .. "%f[^%w_]") then
            local key = rel .. " " .. api
            if CONFIRMED[key] then
                used[key] = true
            else
                Check(owner and catalog[owner], "automation call outside a catalog module: " .. key)
                Check(Flagged(owner), "module calls " .. api .. " without an automation flag: " .. owner .. " (" .. rel .. ")")
            end
        end
    end
    if code:find("%f[%w_]LoggingCombat%s*%(%s*[^%s%)]") then
        Check(owner and Flagged(owner), "module sets the combat log without an automation flag: " .. rel)
    end
end
for key in pairs(CONFIRMED) do Check(used[key], "confirmed-call entry matches nothing; remove it: " .. key) end
print("suite_automation_policy_contract: ok (" .. flagged .. " automation settings, " .. scanned .. " files scanned)")
