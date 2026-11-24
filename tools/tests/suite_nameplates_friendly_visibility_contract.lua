-- Friendly visibility is a Blizzard preference. Styling refreshes preserve
-- native Off; explicit Suite switches and the NPC binding change it once.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local live, writes, combat = {}, 0, false
local nativeEvent
local SECRET = {}
C_CVar = {
    GetCVar = function(key) return live[key] end,
    SetCVar = function(key, value)
        assert(not combat, "protected CVar write during combat")
        writes = writes + 1
        live[key] = tostring(value)
        if nativeEvent then nativeEvent(key) end
    end,
}
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
Enum = { GameRule = {} }
C_GameRules = { IsGameRuleActive = function() return false end }
local NS = { Client = { isForever = flavor == "Forever", isMainline = true } }
NS.Text = function(value) return value end
NS.Public = function(value) return value ~= SECRET end
NS.IsSecret = function(value) return value == SECRET end
NS.Finite = function(value) return type(value) == "number" and value == value end
NS.InCombat = function() return combat end
NS.IsCombatLocked = function() return combat end
NS.RGB = function() return 1, 1, 1 end
NS.Safety = { IsForbidden = function() return false end }
NS.Number, NS.PublicText, NS.ReadText = NS.Finite, tostring, tostring
NS.Dispatch = function(fn, ...) return fn(...) end
NS.Print, NS.CharacterData, NS.RootDB = function() end, {}, {}
NS.Skin = { Release = function() end }
NS.ActionBarTitles = {}
for bar = 1, 12 do NS.ActionBarTitles[bar] = "Action bar " .. bar end
local function Load(path, addon, namespace)
    assert(loadfile(path))(addon, namespace)
end
for _, file in ipairs({ "SuiteCatalog", "NameplateStyle", "NameplateExtensions", "NameplateAuraDisplay", "Catalog/Nameplates" }) do
    Load(root .. "/MSUF_Suite/Core/" .. file .. ".lua", "MSUF_Suite", NS)
end
local S = { catalog = NS.SuiteCatalog, instances = {} }
NS.Suite, MSUFSuite = S, NS
Load(arg[5] or root .. "/MSUF_Suite_Modules/Runtime.lua", "MSUF_Suite_Modules", {})
local private = { NS = NS, Suite = S }
Load(root .. "/MSUF_Suite_Nameplates/Modes.lua", "MSUF_Suite_Nameplates", private)
Load(arg[3] or root .. "/MSUF_Suite_Nameplates/CVars.lua", "MSUF_Suite_Nameplates", private)
Load(arg[4] or root .. "/MSUF_Suite/Core/Bindings.lua", "MSUF_Suite", NS)
local context, module = S.NewContext("nameplates"), {}
module.context, module.active = context, true
S.instances.nameplates = module
local rules = NS.SuiteCatalog.nameplates.rules
local function Config(values)
    local config = {}
    for key, rule in pairs(rules) do config[key] = rule.default end
    config.enabled = true
    for key, value in pairs(values or {}) do config[key] = value end
    return config
end
local function Apply()
    private.CVars.Apply(module)
end
S.Config = function(id) assert(id == "nameplates"); return module.config end
-- The controller (MSUF_Suite/Core/Suite.lua, SetMany) runs a confirmation
-- after the module applied the batch and restores the batch when it fails.
-- startFails models a module that does not start again.
local startFails = false
S.SetMany = function(id, values, confirm)
    assert(id == "nameplates")
    if combat then return false end
    local before = {}
    for key, value in pairs(module.config) do before[key] = value end
    for key, value in pairs(values) do module.config[key] = value end
    module.active = module.config.enabled and not startFails
    Apply()
    if not confirm then return true end
    local ok, reason = confirm()
    if ok then return true end
    for key in pairs(module.config) do module.config[key] = nil end
    for key, value in pairs(before) do module.config[key] = value end
    module.active = module.config.enabled and not startFails
    Apply()
    return false, reason
end
S.Status = function() return module.active and "Active" or "Stopped after an error" end
S.Set = function(id, key, value) return S.SetMany(id, { [key] = value }) end
nativeEvent = function(key) NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", key) end
local function Reset(values)
    for key in pairs(live) do live[key] = nil end
    for key in pairs(NS.RootDB) do NS.RootDB[key] = nil end
    live.nameplateShowFriendlyPlayers, live.nameplateShowFriendlyNpcs, live.UnitNameNPC = "0", "0", "0"
    module.config, module.cvarsPending, module.active = Config(values), nil, true
    module.friendlyVisibility, module.friendlyVisibilityPending, module.friendlyNpcNamesOnly = nil, nil, nil
    writes, combat = 0, false
end
local checks = 0
local function Check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
local function NativeOff(message)
    Check(live.nameplateShowFriendlyPlayers == "0" and live.nameplateShowFriendlyNpcs == "0", message)
end

Reset()
Apply()
NativeOff("startup forced native friendly Off to On")
Check(writes == 0, "default friendly styling wrote visibility")
Check(not NS.FriendlyNameplateShown("friendly") and not NS.FriendlyNameplateShown("friendlyNpc"),
    "Suite header ignored native Off")
Apply()
module.config = Config()
Apply()
NativeOff("refresh or profile reapply forced native Off to On")
Load(arg[3] or root .. "/MSUF_Suite_Nameplates/CVars.lua", "MSUF_Suite_Nameplates", private)
Apply()
NativeOff("reloaded CVar module forced native Off to On")

Check(NS.SetFriendlyNameplates("friendly", true), "Suite On failed with already enabled skin")
Check(live.nameplateShowFriendlyPlayers == "1" and NS.FriendlyNameplateShown("friendly"),
    "Suite On did not change native visibility")
Check(live.nameplateShowFriendlyNpcs == "0", "friendly player switch changed NPC visibility")
live.nameplateShowFriendlyPlayers = "0"
Apply()
Check(live.nameplateShowFriendlyPlayers == "0" and not NS.FriendlyNameplateShown("friendly"),
    "Blizzard Off was overwritten after a Suite On")
Check(NS.SetFriendlyNameplates("friendly", false) and not module.config.friendlySkinEnabled,
    "Suite Off did not save its setting")
Check(NS.SetFriendlyNameplates("friendly", true) and live.nameplateShowFriendlyPlayers == "1",
    "Suite Off to On required a second action")
Check(NS.SetFriendlyNameplates("friendly", false), "Suite Off failed")
Apply()
Check(live.nameplateShowFriendlyPlayers == "0", "refresh resurrected Suite-disabled plates")

-- A native On must work after a Suite Off as well. Native actions update
-- just the matching friendly switch and never overwrite the other scope.
Reset()
Apply()
Check(NS.SetFriendlyNameplates("friendly", false), "preparing native On failed")
live.nameplateShowFriendlyPlayers = "1"
NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", "nameplateShowFriendlyPlayers")
Check(module.config.friendlySkinEnabled and NS.FriendlyNameplateShown("friendly"),
    "Blizzard On did not re-enable the Suite friendly scope")
Apply()
Check(live.nameplateShowFriendlyPlayers == "1" and live.nameplateShowFriendlyNpcs == "0",
    "refresh reversed native On or affected friendly NPCs")
live.nameplateShowFriendlyPlayers = "0"
NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", "NAMEPLATESHOWFRIENDLYPLAYERS")
Check(module.config.friendlySkinEnabled == false and not NS.FriendlyNameplateShown("friendly"),
    "case-insensitive native Off did not update the Suite switch")
NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", SECRET)
Check(live.nameplateShowFriendlyPlayers == "0", "secret event argument changed friendly visibility")

-- Disabled/unsupported modules recover their old CVars before the optional
-- nameplate addon loads. Legacy forced-visibility records must be retired
-- there too, without relying on any CVars.Apply call to clear them first.
Reset()
module.active = false
NS.RootDB.suiteRecovery = { ["Realm/Tester"] = { nameplates = {
    nameplateShowFriendlyPlayers = { before = "1", applied = "0" },
    nameplateShowFriendlyNpcs = { before = "1", applied = "0" },
} } }
S.RestoreSaved("nameplates")
NativeOff("cold recovery resurrected native friendly nameplates before the module loaded")
Check(writes == 0 and next(NS.RootDB.suiteRecovery or {}) == nil,
    "cold recovery wrote or retained obsolete friendly visibility records")

Reset()
NS.RootDB.suiteRecovery = { ["Realm/Tester"] = { nameplates = {
    nameplateShowFriendlyPlayers = { before = "1", applied = "0" },
    nameplateShowFriendlyNpcs = { before = "1", applied = "0" },
} } }
Apply()
NativeOff("stale recovery restored a previous On over current Off")
context:Release()
NativeOff("module release restored abandoned friendly recovery")
Check(next(NS.RootDB.suiteRecovery or {}) == nil, "abandoned friendly recovery was retained")

Reset()
Check(NS.ToggleFriendlyNPCNameplates() and live.nameplateShowFriendlyNpcs == "1",
    "NPC binding required two presses after native Off")
Check(NS.ToggleFriendlyNPCNameplates() and live.nameplateShowFriendlyNpcs == "0",
    "NPC binding did not turn native plates Off")
Check(NS.SetFriendlyNameplates("friendlyNpc", true), "NPC health-bar On failed")
module.config.friendlyNPCs = 4
Apply()
Check(live.nameplateShowFriendlyNpcs == "0" and live.UnitNameNPC == "1"
    and NS.FriendlyNameplateShown("friendlyNpc"), "NPC names-only was treated as disabled")
Check(NS.ToggleFriendlyNPCNameplates() and not NS.FriendlyNameplateShown("friendlyNpc")
    and live.nameplateShowFriendlyNpcs == "0" and live.UnitNameNPC == "0", "NPC names-only Off retained world names")
Check(NS.ToggleFriendlyNPCNameplates() and NS.FriendlyNameplateShown("friendlyNpc")
    and live.nameplateShowFriendlyNpcs == "0" and live.UnitNameNPC == "1", "NPC names-only On lost its display choice")
Check(live.nameplateShowFriendlyPlayers == "0", "NPC actions changed friendly player plates")
live.nameplateShowFriendlyNpcs = "1"
NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", "nameplateShowFriendlyNpcs")
Check(module.config.friendlyNpcSkinEnabled and module.config.friendlyNPCs == 2
    and live.nameplateShowFriendlyNpcs == "1" and live.UnitNameNPC == "0",
    "native NPC On did not leave names-only mode for health bars")

-- Current names-only overrides remain temporary even though legacy forced
-- visibility recovery is obsolete. Disabling the module restores its real
-- native NPC bars and world-name baseline.
Reset({ friendlyNPCs = 4 })
live.nameplateShowFriendlyNpcs = "1"
Apply()
Check(live.nameplateShowFriendlyNpcs == "0" and live.UnitNameNPC == "1",
    "names-only did not establish its temporary native overrides")
module.active = false
context:Release()
Check(live.nameplateShowFriendlyNpcs == "1" and live.UnitNameNPC == "0",
    "current names-only recovery lost the previous native visibility")

-- Name only inside an instance: friendly plates there are forbidden to addons,
-- so friendly NPCs take world names until the player leaves (CVars.lua
-- NpcLock, Roles.RefreshContext). The switch, the binding, the Display choice
-- and the way out keep the player's choice; plates already off stay off.
do
    local X, roles = NS.NameplateExtensions, { inInstance = false }
    private.Roles = roles
    local function Zone(inside)
        roles.inInstance = inside
        private.CVars.InstanceChanged()
    end
    local function Shows(plates, names)
        return live.nameplateShowFriendlyNpcs == plates and live.UnitNameNPC == names
    end
    Reset()
    Apply()
    local quiet = writes
    Zone(true)
    Zone(false)
    Check(writes == quiet, "an instance change rewrote CVars without Name only")

    Reset({ friendlyNPCs = X.NPC_PLATE_NAME_ONLY })
    live.nameplateShowFriendlyNpcs = "1"
    Apply()
    Check(Shows("1", "0") and NS.FriendlyNameplateShown("friendlyNpc"), "Name only lost its plates outside instances")
    Zone(true)
    Check(Shows("0", "1") and NS.FriendlyNameplateShown("friendlyNpc"), "Name only kept forbidden plates in an instance")
    Check(module.config.friendlyNPCs == X.NPC_PLATE_NAME_ONLY and module.config.friendlyNpcSkinEnabled,
        "the instance fallback changed the saved display")
    Apply()
    Check(Shows("0", "1"), "a refresh in the instance lost the world names")
    Zone(false)
    Check(Shows("1", "0") and NS.FriendlyNameplateShown("friendlyNpc"), "leaving the instance kept world names")

    Zone(true)
    Check(NS.ToggleFriendlyNPCNameplates() and not NS.FriendlyNameplateShown("friendlyNpc") and Shows("0", "0"),
        "the binding left world names on in the instance")
    Check(NS.ToggleFriendlyNPCNameplates() and NS.FriendlyNameplateShown("friendlyNpc") and Shows("0", "1"),
        "the binding showed forbidden plates in the instance")
    Apply()
    Zone(false)
    Check(Shows("1", "0") and module.config.friendlyNPCs == X.NPC_PLATE_NAME_ONLY,
        "friendly NPCs turned on in the instance stayed off outside")

    -- Health bars show Blizzard's plates there; Name only takes world names back.
    Zone(true)
    Check(NS.SetFriendlyNameplates("friendlyNpc", NS.FriendlyNameplateShown("friendlyNpc"), { friendlyNPCs = 2 })
        and Shows("1", "0"), "Health bars stayed hidden in the instance")
    Check(NS.SetFriendlyNameplates("friendlyNpc", NS.FriendlyNameplateShown("friendlyNpc"),
        { friendlyNPCs = X.NPC_PLATE_NAME_ONLY }) and Shows("0", "1"), "Name only kept Blizzard's plates in the instance")
    live.nameplateShowFriendlyNpcs = "1"
    NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", "nameplateShowFriendlyNpcs")
    Check(module.config.friendlyNPCs == 2 and Shows("1", "0"), "Blizzard's NPC On in an instance did not ask for bars")
    Zone(false)

    -- A reload or crash inside: the next session finds the override either way.
    Reset({ friendlyNPCs = X.NPC_PLATE_NAME_ONLY })
    live.nameplateShowFriendlyNpcs = "1"
    Apply()
    Zone(true)
    module.friendlyNpcNamesOnly, module.npcLock = nil, nil
    Apply()
    Check(Shows("0", "1"), "a reload in the instance lost its world names")
    module.friendlyNpcNamesOnly, module.npcLock = nil, nil
    roles.inInstance = false
    Apply()
    Check(Shows("1", "0"), "a session after a crash in an instance kept the plates off")

    combat = true
    Zone(true)
    Check(module.cvarsPending and Shows("1", "0"), "an instance change wrote CVars in combat")
    combat = false
    Apply()
    Check(Shows("0", "1"), "the instance change held back for combat was lost")
    Zone(false)

    -- Natively hidden plates (a profile shared with another character).
    Reset({ friendlyNPCs = X.NPC_PLATE_NAME_ONLY })
    Apply()
    Zone(true)
    Check(Shows("0", "0") and not NS.FriendlyNameplateShown("friendlyNpc"),
        "an instance showed world names for friendly NPCs that were off")
    Zone(false)
    Check(Shows("0", "0"), "leaving an instance turned natively hidden plates on")
end

Reset()
local beforeWrites = writes
combat = true
Check(not NS.SetFriendlyNameplates("friendly", true) and not NS.ToggleFriendlyNPCNameplates(),
    "manual visibility edits were accepted during combat")
Check(writes == beforeWrites, "refused combat action wrote a CVar")
Apply()
Check(module.cvarsPending and writes == beforeWrites, "combat refresh wrote visibility")
combat = false
Apply()
NativeOff("deferred combat refresh forced native Off to On")

Reset()
Apply()
Check(NS.SetFriendlyNameplates("friendly", false), "preparing combat native On failed")
combat = true
live.nameplateShowFriendlyPlayers = "1"
local nativeOnWrites = writes
NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", "nameplateShowFriendlyPlayers")
Check(module.config.friendlySkinEnabled == false and writes == nativeOnWrites,
    "native combat event edited a profile or performed a protected write")
Apply()
combat = false
NS.SyncFriendlyNameplates(module, "PLAYER_REGEN_ENABLED")
Apply()
Check(module.config.friendlySkinEnabled and live.nameplateShowFriendlyPlayers == "1",
    "combat-end reconciliation lost the native On before deferred refresh")

-- The controller's queued refresh can precede Skin's combat-end listener.
-- That ordering must flush the native action before applying saved Off.
Reset()
Apply()
Check(NS.SetFriendlyNameplates("friendly", false), "preparing queued-refresh native On failed")
combat = true
live.nameplateShowFriendlyPlayers = "1"
NS.SyncFriendlyNameplates(module, "CVAR_UPDATE", "nameplateShowFriendlyPlayers")
Apply()
combat = false
Apply()
Check(module.config.friendlySkinEnabled and live.nameplateShowFriendlyPlayers == "1",
    "queued refresh ran before native reconciliation and reversed Blizzard On")

Reset({ enabled = false })
module.active = false
live.nameplateShowFriendlyPlayers = "1"
Check(not NS.FriendlyNameplateShown("friendly") and not NS.SetFriendlyNameplates("friendly", true),
    "disabled nameplate module accepted an implicit visibility change")
Check(NS.SetFriendlyNameplates("friendly", true, { enabled = true, friendlyNpcSkinEnabled = false,
    enemySkinEnabled = false, neutralSkinEnabled = false }) and module.config.enabled
    and module.config.friendlySkinEnabled and not module.config.friendlyNpcSkinEnabled,
    "enabling only the chosen scope from a disabled module failed")

Reset({ friendlySkinEnabled = false })
module.active, startFails = false, true
Check(not NS.SetFriendlyNameplates("friendly", true) and module.config.friendlySkinEnabled == false
    and writes == 0, "a stopped nameplate module saved a visibility switch it could not apply")
startFails = false
Check(NS.SetFriendlyNameplates("friendly", true) and module.active and live.nameplateShowFriendlyPlayers == "1",
    "the switch did not restart a nameplate module after a recoverable error")

Reset({ friendlySkinEnabled = false })
live.nameplateShowFriendlyPlayers = nil
Check(not NS.FriendlyNameplateShown("friendly") and not NS.SetFriendlyNameplates("friendly", true),
    "missing native CVar was treated as available")
Check(live.nameplateShowFriendlyPlayers == nil and writes == 0, "missing native CVar was created")
Check(module.config.friendlySkinEnabled == false, "missing CVar preflight changed the saved switch")
module.config.friendlySkinEnabled = true
live.nameplateShowFriendlyPlayers = SECRET
Check(not NS.FriendlyNameplateShown("friendly") and not NS.SetFriendlyNameplates("friendly", true),
    "secret native CVar was treated as available")
Check(live.nameplateShowFriendlyPlayers == SECRET and writes == 0, "secret native CVar was overwritten")
Check(not S.CommitCVar("nameplates", "unownedVisibility", "1"), "manual write bypassed declared CVar ownership")
Check(not NS.SetFriendlyNameplates("unknown", true), "unknown friendly scope was accepted")

-- An unavailable optional addon may leave its controller setter successful
-- without loading either the instance or shared CVar writer. Manual actions
-- must refuse that state rather than calling a missing runtime function.
Reset()
local savedInstance, savedCommit, savedSetMany = S.instances.nameplates, S.CommitCVar, S.SetMany
S.instances.nameplates, S.CommitCVar = nil, nil
S.SetMany = function(_, _, confirm) return confirm() end
Check(not NS.SetFriendlyNameplates("friendly", true) and not NS.ToggleFriendlyNPCNameplates(),
    "unavailable optional nameplate runtime accepted a native visibility action")
Check(writes == 0, "unavailable optional runtime changed native visibility")
S.instances.nameplates, S.CommitCVar, S.SetMany = savedInstance, savedCommit, savedSetMany

do
    Reset()
    live.nameplateShowFriendlyPlayerPets, live.UnitNameFriendlyPetName = "0", "1"
    live.nameplateShowEnemyPets, live.UnitNameEnemyPetName = "1", "0"
    live.UnitNameFriendlyGuardianName, live.UnitNameEnemyTotemName = "1", "1"
    local page = { Suite = NS, Tr = NS.Text, NameplatesStatus = { IsOffset = function() return false end } }
    function page.RuleRow(_, id, rule)
        return { kind = "dropdown", get = function() return S.Config(id)[rule.key] end,
            set = function(value) return S.Set(id, rule.key, value) end }
    end
    Load(root .. "/MSUF_Suite_Options/Pages/NameplatesDirectSettings.lua", "Options", page)
    local playerPets = page.RuleRow("suite_nameplates", "nameplates", rules.plateFriendlyPets)
    local enemyPets = page.RuleRow("suite_nameplates", "nameplates", rules.plateEnemyPets)
    Check(playerPets.kind == "dropdown" and enemyPets.kind == "dropdown"
        and playerPets.values()[3].text == "Names only (world names)", "pet rows did not offer a names-only choice")
    Check(playerPets.get() == 4 and enemyPets.get() == 2 and writes == 0,
        "the inherited controls did not distinguish world names from bars")
    Check(playerPets.set(3) and playerPets.get() == 3 and live.nameplateShowFriendlyPlayerPets == "0"
        and live.UnitNameFriendlyPetName == "0", "friendly Hide left the world-space pet name visible")
    Check(enemyPets.set(4) and enemyPets.get() == 4 and live.nameplateShowEnemyPets == "0"
        and live.UnitNameEnemyPetName == "1", "enemy Names only did not replace the plate with its world name")
    Check(playerPets.set(4) and live.UnitNameFriendlyPetName == "1" and live.nameplateShowFriendlyPlayerPets == "0",
        "friendly Names only did not restore the name after Hide")
    Check(live.UnitNameFriendlyGuardianName == "1" and live.UnitNameEnemyTotemName == "1",
        "changing pet display touched a different kind of minion")
    Check(playerPets.set(2) and live.nameplateShowFriendlyPlayerPets == "1" and live.UnitNameFriendlyPetName == "1",
        "Health bars failed to reveal the friendly pet plate")
    context:Release()
    Check(live.nameplateShowFriendlyPlayerPets == "0" and live.UnitNameFriendlyPetName == "1"
        and live.nameplateShowEnemyPets == "1" and live.UnitNameEnemyPetName == "0", "release lost the native pet defaults")
end

print("Suite friendly visibility " .. flavor .. ": " .. checks .. " causal checks passed")
