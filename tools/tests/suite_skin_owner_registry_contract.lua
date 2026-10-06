-- AdapterKit.NewOwners, the one owner registry of the skin adapters: the
-- per-owner state, its combat deferral and its release. A pass runs at once
-- out of combat; in combat each suffix keeps one job per state (built once,
-- no closure per request) that runs once at PLAYER_REGEN_ENABLED for the
-- owner's state then, only while it is active, with the latest argument.
-- A deferred disable runs only while the owner stays disabled. Release and
-- CancelDeferred cancel what is pending. Real Safety.lua, CombatGate.lua and
-- AdapterKit.lua.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

local locked = false
local frames = {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, script) self.script = script end
    frames[#frames + 1] = frame
    return frame
end
InCombatLockdown = function() return locked end

local hidden = {}
local NS = {
    IsCombatLocked = function() return locked end,
    Registry = { AddListener = function() end },
    Surface = { SetVisible = function(target, visible) hidden[target] = visible == false end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/CombatGate.lua", "Adapters/AdapterKit.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Kit, Gate, gateFrame = NS.AdapterKit, NS.CombatGate, frames[#frames]
local function EndCombat()
    locked = false
    gateFrame.script(gateFrame, "PLAYER_REGEN_ENABLED")
end

-- The registry is the only owner-state, deferral and Fade/Attach owner:
-- adapters keep no local copy and AdapterKit keeps no closure-per-call helper.
local function Source(path)
    local file = assert(io.open(root .. "/MSUF_Suite_Skin/" .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local kit = Source("Adapters/AdapterKit.lua")
Check(kit:find("function AdapterKit.NewOwners(config)", 1, true) and not kit:find("DeferForOwner", 1, true),
    "AdapterKit does not own the registry alone (DeferForOwner built a closure per request)")
local migrated = { "PaperDollChrome", "SemanticHUD", "SharedChrome", "DeepWindows", "CommonArt", "CommonMenus",
    "LegacyWindows", "SocialUI", "EditMode", "ChatFrames", "DamageMeter", "GenericWindows", "MajorWindows" }
for _, name in ipairs(migrated) do
    local source = Source("Adapters/" .. name .. ".lua")
    Check(source:find("Kit.NewOwners({", 1, true), name .. " does not use the owner registry")
    Check(not source:find("local function OwnerState", 1, true)
        and not source:find("local function RunOrDefer", 1, true)
        and not source:find("local function CancelDeferred", 1, true),
        name .. " keeps its own owner state or deferral copy")
end
-- PaperDollChrome is a thin wrapper: the kit's gated Fade/Attach/Ensure and its registry.
local chrome = Source("Adapters/PaperDollChrome.lua")
Check(chrome:find("Chrome.Fade = Kit.Fade", 1, true) and chrome:find("Chrome.Track = Kit.Track", 1, true)
    and chrome:find("return Kit.Ensure(state, target, spec)", 1, true)
    and chrome:find("return self.registry.RunOrDefer(state, suffix, callback)", 1, true)
    and not chrome:find("NS.Cosmetics.", 1, true) and not chrome:find("NS.CombatGate.", 1, true),
    "PaperDollChrome reimplements the kit's Fade, Attach or deferral")

-- Edit Mode fades through the kit's gate (combat, forbidden, CanDecorate).
local editMode = Source("Adapters/EditMode.lua")
Check(editMode:find("local Fade, FadeNineSlice = Kit.Fade, Kit.FadeNineSlice", 1, true)
    and not editMode:find("NS.Cosmetics.Fade", 1, true), "Edit Mode fades without the kit's gate")

------------------------------------------------------------------ owner state
local inits = 0
local Owners = Kit.NewOwners({
    prefix = "contract",
    default = "main",
    keyField = "parentOwner",
    surfaces = true,
    init = function(state, key)
        inits = inits + 1
        state.owner = key .. ":skin"
    end,
})
local state, key = Owners.State()
Check(key == "main" and state.parentOwner == "main" and state.owner == "main:skin"
    and state.active == false and type(state.deferred) == "table" and type(state.surfaces) == "table",
    "a new state lacks the configured key, flags or sets")
Check(Owners.State("main") == state and Owners.owners.main == state and inits == 1,
    "a second lookup made a new state or ran init again")
Check(getmetatable(state.surfaces) and getmetatable(state.surfaces).__mode == "k",
    "the surfaces set is not weak")
local plain = Kit.NewOwners({ prefix = "plain", active = true }).State("x")
Check(plain.owner == "x" and plain.active == true and plain.surfaces == nil,
    "the default key field, active flag or surface opt-in is wrong")

------------------------------------------------------------------ run now
local runs = {}
local function Pass(current, arg) runs[#runs + 1] = { state = current, arg = arg } end
Check(select(2, Owners.RunOrDefer(state, "pass", Pass)) == "disabled" and #runs == 0,
    "an inactive owner ran a pass")
Check(select(2, Owners.RunOrDefer(nil, "pass", Pass)) == "disabled", "a missing owner state raised or ran")
state.active = true
Check(Owners.RunOrDefer(state, "pass", Pass, "now") == true and #runs == 1 and runs[1].state == state
    and runs[1].arg == "now", "an out-of-combat pass did not run at once with its argument")
Check(state.jobs == nil and next(state.deferred) == nil, "an out-of-combat pass built a job or stayed marked")

local isolated = Kit.NewOwners({ prefix = "isolated", isolate = true })
local raising = isolated.State("x")
raising.active = true
Check(isolated.RunOrDefer(raising, "pass", function() error("contract: pass raised") end) == true
    and #reported == 1, "an isolated pass escaped or was not reported")
Check(not pcall(Owners.RunOrDefer, state, "pass", function() error("contract: plain pass raised") end),
    "a pass without isolate swallowed its error")

------------------------------------------------------------------ deferral
locked = true
local ran, reason = Owners.RunOrDefer(state, "pass", Pass, "first")
local job = state.jobs.pass
Check(ran == false and reason == "combat" and #runs == 1 and state.deferred[job.key] == true
    and job.key == "contract:main:pass", "a combat pass ran, was not marked or has the wrong key")
local run = Gate.pending[job.key]
Owners.RunOrDefer(state, "pass", Pass, "latest")
Check(state.jobs.pass == job and Gate.pending[job.key] == run and Gate.GetPendingCount() == 1,
    "a repeated request built a new job or closure")
Owners.RunOrDefer(state, "other", Pass, "other")
Check(state.jobs.other ~= job and Gate.GetPendingCount() == 2, "two suffixes share one job")
EndCombat()
Check(#runs == 3 and runs[2].arg == "latest" and runs[3].arg == "other" and next(state.deferred) == nil,
    "the deferred passes did not run once each with their latest argument")
EndCombat()
Check(#runs == 3, "a deferred pass ran twice")

-- For the owner's state then: a state applied again in between is the one passed.
locked = true
Owners.RunOrDefer(state, "pass", Pass, "replaced")
Owners.Forget(state)
local replaced = Owners.State("main")
replaced.active = true
EndCombat()
Check(#runs == 4 and runs[4].state == replaced and runs[4].arg == "replaced",
    "a deferred pass did not run for the owner's current state")

-- Not for an owner that went inactive or away.
locked = true
Owners.RunOrDefer(replaced, "pass", Pass)
replaced.active = false
EndCombat()
Check(#runs == 4 and next(replaced.deferred) == nil, "a deferred pass ran for an inactive owner")
locked = true
replaced.active = true
Owners.RunOrDefer(replaced, "pass", Pass)
Owners.Forget(replaced)
EndCombat()
Check(#runs == 4, "a deferred pass ran for a forgotten owner")

------------------------------------------------------------------ cancel and release
local current = Owners.State("main")
current.active = true
locked = true
Owners.RunOrDefer(current, "pass", Pass)
Kit.CancelDeferred(current)
Check(next(current.deferred) == nil and Gate.GetPendingCount() == 0, "CancelDeferred kept the pending pass")
local surface = {}
Kit.Track(current, surface)
Kit.Track(current, nil)
Owners.RunOrDefer(current, "pass", Pass)
Owners.Release(current)
Check(current.active == false and Gate.GetPendingCount() == 0 and hidden[surface] == true
    and Owners.owners.main == nil, "Release kept a pass, a surface or the owner")
EndCombat()
Check(#runs == 4, "a released owner's pass ran")

------------------------------------------------------------------ deferred disable
local disables = 0
local function Disable(disabled)
    disables = disables + 1
    Owners.Forget(disabled)
    return true
end
local owner = Owners.State("main")
owner.active = true
Check(Owners.DisableOrDefer(owner, Disable) == true and disables == 1 and owner.active == false,
    "an out-of-combat disable did not run at once")
owner = Owners.State("main")
owner.active = true
locked = true
Owners.RunOrDefer(owner, "pass", Pass)
ran, reason = Owners.DisableOrDefer(owner, Disable)
Check(ran == false and reason == "combat" and disables == 1 and Gate.GetPendingCount() == 1
    and owner.deferred["contract:main:disable"], "a combat disable ran, kept the pending pass or was not marked")
EndCombat()
Check(disables == 2 and #runs == 4 and Owners.owners.main == nil, "the deferred disable did not run once")
owner = Owners.State("main")
owner.active = true
locked = true
Owners.DisableOrDefer(owner, Disable)
Kit.CancelDeferred(owner)
owner.active = true
EndCombat()
Check(disables == 2 and Owners.owners.main == owner, "a disable cancelled by a later apply still ran")
locked = true
Owners.DisableOrDefer(owner, Disable)
owner.active = true
EndCombat()
Check(disables == 2, "a deferred disable ran for an owner that is active again")

------------------------------------------------------------------ adapters in combat
-- The adapters that defer apply and disable per owner, through the registry:
-- a combat apply queues, a combat disable replaces the queued passes and
-- runs once after combat, and an apply before then cancels it. Everything
-- outside the kit is a no-op here, so only the lifecycle is observed.
local function Noop() end
local noopModule = { __index = function() return Noop end }
setmetatable(NS, { __index = function(namespace, name)
    local module = setmetatable({}, noopModule)
    rawset(namespace, name, module)
    return module
end })
NS.Client = { IsAddOnLoaded = function() return true end }
NS.GenericWindows = { IsCategoryEnabled = function() return false end }
EventUtil = { ContinueOnAddOnLoaded = Noop }
hooksecurefunc = Noop
SocialUIFrame = {}
local adapters = {
    { file = "SemanticHUD", module = "SemanticHUD" },
    { file = "DeepWindows", module = "DeepWindows" },
    { file = "LegacyWindows", module = "LegacyWindows" },
    { file = "SocialUI", module = "SocialUISkin" },
}
for _, entry in ipairs(adapters) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/" .. entry.file .. ".lua"))("MSUF_Suite_Skin", NS)
    local adapter, name, before = NS[entry.module], entry.file, #reported
    locked = true
    adapter.Apply("combat")
    local applied = adapter.owners.combat
    Check(applied and applied.active and Gate.GetPendingCount() > 0, name .. " did not queue a combat apply")
    Check(select(2, adapter.Disable("combat")) == "combat" and Gate.GetPendingCount() == 1
        and applied.active == false, name .. " did not replace its queued passes with one deferred disable")
    adapter.Apply("combat")
    Check(adapter.owners.combat == applied and applied.active, name .. " lost its owner state on a combat apply")
    local disableKey
    for key in pairs(applied.deferred) do
        if key:find(":disable", 1, true) then disableKey = key end
    end
    Check(disableKey == nil and not Gate.pending[name .. ":combat:disable"],
        name .. " kept its deferred disable after a later apply")
    adapter.Disable("combat")
    EndCombat()
    Check(adapter.owners.combat == nil and Gate.GetPendingCount() == 0 and #reported == before,
        name .. " did not disable once after combat")
end

print("Suite skin owner registry: " .. checks .. " checks passed")
