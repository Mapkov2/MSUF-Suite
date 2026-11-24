-- The generic window catalog at the end of combat (raid trace 2026-11-23,
-- capture 15 frame 19846: a death popup shown in lockdown was painted, then
-- painted again in full by its combat gate job in the same frame). A combat
-- pass queues the full pass after combat only for work combat held back;
-- the end of combat, a steady re-show and a closed window repeat nothing.
-- Real Safety, CombatGate, AdapterKit and generic window passes; renderers
-- are the stubs of suite_skin_generic_windows_contract.lua.
local root = assert(arg[1], "Suite root required")
local skin = root .. "/MSUF_Suite_Skin/"
local checks, failures = 0, {}
local function Check(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end

-- Blizzard's callback isolation (securecallfunction): an error is reported to
-- the error handler and the caller goes on. Reports are counted, so a
-- boundary can be shown to report instead of swallowing.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

-- hooksecurefunc post-hooks: the original runs first, then the hook.
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then
        target, method, callback = _G, target, method
    end
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end

-- GenericWindows with the real Safety, AdapterKit and Catalog and stubbed renderers.
local locked = false
local listener
local listeners = {}
local counters = { attach = 0, yellow = 0, checkmarks = 0, unregister = 0 }
local yellowFrames
local registered = {}
local createdFrames = {}

local function NewFrame()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:HookScript(name, callback) self.scripts[name] = callback end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetParent() return self.parent end
    function frame:ClearAllPoints() end
    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetFrameLevel() end
    function frame:EnableMouse() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    createdFrames[#createdFrames + 1] = frame
    return frame
end
CreateFrame = function() return NewFrame() end
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
-- Global callbacks the window adapters register; none fires in this contract.
EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }

local NS
NS = {
    -- The skin's locale table (Locales/Localization.lua) is ready before
    -- any of this runs; here every key reads as itself.
    L = setmetatable({}, { __index = function(_, key) return key end }),
    IsCombatLocked = function() return locked end,
    -- The skin's handle on the Suite core (Core/Bootstrap.lua).
    SuiteCore = function() return MSUFSuite end,
    Client = {
        IsAddOnLoaded = function() return true end,
        HasAddOn = function() return true end,
    },
    CombatGate = {
        RunOrDefer = function(_, callback)
            if locked then return false, "combat" end
            callback()
            return true
        end,
        Cancel = function() end,
        -- This gate never keeps a job for later.
        IsPending = function() return false end,
    },
    Surface = {
        Attach = function(target, spec)
            counters.attach = counters.attach + 1
            target.surfaceSpec = spec
            return { spec = spec, edge = { SetDrawLayer = function() end } }
        end,
        -- The update-hook attach (Surface.Ensure) counts as an attach here.
        Ensure = function(target, spec) return NS.Surface.Attach(target, spec) end,
        SetVisible = function(target, visible) target.surfaceVisible = visible end,
        SetActive = function(target, active) target.surfaceActive = active end,
    },
    Cosmetics = {
        Fade = function() return true end,
        FadeNineSlice = function() end,
        FadeDialogHeader = function() end,
        Restore = function() end,
        RestoreOwner = function() end,
        SuppressVertexAlpha = function() end,
        GetOwner = function() return nil end,
    },
    ControlSkin = {
        DisableOwner = function() end,
        RefreshOwner = function() end,
        Refresh = function() return true end,
        IsApplied = function() return false end,
    },
    IconSkin = { DisableOwner = function() end, GetOwner = function() return nil end },
    ScrollBarSkin = { DisableOwner = function() end },
    Registry = {
        AddListener = function(owner, callback)
            listeners[owner] = callback
            if owner == NS.GenericWindows then listener = callback end
        end,
        RemoveListener = function(owner) listeners[owner] = nil end,
        GetSurface = function() return nil end,
        -- Coalesced repaints run at once here.
        QueueJob = function(job) job() end,
    },
    Theme = { GetColor = function() return 1, 1, 1, 1 end },
    BlizzardYellow = {
        TrackFrame = function(frame)
            counters.yellow = counters.yellow + 1
            if yellowFrames then yellowFrames[frame] = true end
        end,
        TrackFrames = function(frames, count)
            for index = 1, count do
                counters.yellow = counters.yellow + 1
                if yellowFrames then yellowFrames[frames[index]] = true end
            end
        end,
        TrackMenuSelection = function() end,
    },
    Checkmarks = {
        TrackFrame = function() counters.checkmarks = counters.checkmarks + 1 end,
        TrackDropdown = function() end,
        IsDropdown = function() return false end,
        GetWindowAction = function() return nil end,
        UntrackOwner = function() end,
        TrackTexture = function() return true end,
        UntrackTexture = function() end,
        TrackButton = function() return true end,
    },
    WindowActionSkin = {
        GetExplicitKind = function() return nil end,
        Apply = function() return nil end,
        SyncNativeVisual = function() return nil end,
        DisableOwner = function() end,
    },
    WindowControls = { TrackFocus = function() end, Attach = function() end, DisableOwner = function() end },
    -- Adapters that load after the generic windows; none owns a frame here.
    CharacterDetails = { IsHost = function() return false end },
    CharacterStats = { IsHost = function() return false end },
    EQoLCharacter = { IsHost = function() return false end },
    MacroWindow = { Apply = function() end, Disable = function() end },
    CatalogShopMotion = { Apply = function() end, Disable = function() end },
    QuestText = { Activate = function() end, Deactivate = function() end },
    Adapters = { Refresh = function() return true end },
}
-- The shared value helpers and the Retail Micro Bar line length of
-- Defaults.lua, which loads before every adapter.
do
    local defaults = { Client = NS.Client }
    assert(loadfile(skin .. "Core/Defaults.lua"))("MSUF_Suite_Skin", defaults)
    assert(loadfile(skin .. "Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", defaults)
    NS.Clamp, NS.IsListed = defaults.Clamp, defaults.IsListed
    NS.MicroMenuMaxButtonsPerLine = defaults.MicroMenuMaxButtonsPerLine
end
local function ColdSource(file)
    local baseline = os.getenv("SUITE_SKIN_COLD_BASELINE")
    local path = baseline and baseline .. "/MSUF_Suite_Skin/" .. file
    local found = path and io.open(path, "rb")
    if found then found:close(); return path end
    return skin .. file
end

dofile(root .. "/tools/tests/suite_test_support.lua").SecretValues()

-- The real combat gate: its event frame, scheduled resumes and budget clock.
NS.CombatGate = nil
local timers, clock = {}, 0
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
debugprofilestop = function() return clock end
InCombatLockdown = function() return locked end
local function RunTimers()
    local due = timers
    timers = {}
    for index = 1, #due do due[index]() end
end

for _, file in ipairs({ "../MSUF_Suite/Appearance/Safety.lua", "../MSUF_Suite/Appearance/CombatGate.lua",
    "Core/SuiteOwnership.lua", "Adapters/Catalog.lua", "Adapters/CatalogGlass.lua",
    "Adapters/AdapterKit.lua", "Adapters/SharedChrome.lua",
    "Adapters/GenericWindows.lua", "Adapters/GenericWindowsNodes.lua", "Adapters/GenericWindowsFrames.lua",
    "Adapters/FlightMapChrome.lua", "Adapters/GenericWindowsCatalog.lua" }) do
    assert(loadfile(ColdSource(file)))("MSUF_Suite_Skin", NS)
end
local GenericWindows, Gate, Safety = NS.GenericWindows, NS.CombatGate, NS.Safety
local gateFrame
for index = 1, #createdFrames do
    if createdFrames[index].scripts.OnEvent and createdFrames[index].events then gateFrame = gateFrame or createdFrames[index] end
end
assert(gateFrame, "combat gate frame missing")

-- Windows with native hook lists and the engine's protection rule: a frame
-- holding a protected descendant is implicitly protected itself.
local function Window(name, children)
    local w = { name = name, children = children or {}, shown = false, hooks = {}, reads = 0 }
    for _, child in ipairs(w.children) do child.parent = w end
    function w:GetObjectType() return "Frame" end
    function w:GetName() return self.name end
    function w:CreateTexture() return {} end
    function w:GetChildren() self.reads = self.reads + 1 return unpack(self.children) end
    function w:GetNumChildren() return #self.children end
    function w:GetParent() return self.parent end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:IsProtected()
        if self.explicit then return true, true end
        if self.protected then return true, false end
        for _, child in ipairs(self.children) do
            if child:IsProtected() then return true, false end
        end
        return false, false
    end
    function w:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function w:Show()
        self.shown = true
        for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
    end
    function w:Hide() self.shown = false end
    if name then _G[name] = w end
    return w
end

local function Reads(...)
    local total = 0
    for index = 1, select("#", ...) do total = total + select(index, ...).reads end
    return total
end

local function SetCombat(value, event)
    locked = value
    if event then gateFrame.scripts.OnEvent(gateFrame, event) end
end

local function Entry(id, frames, mode)
    return { id = id, category = "utility", frames = frames, mode = mode or "dialog" }
end

-- 1. The death popup of the raid trace: shown in lockdown (PLAYER_DEAD),
-- unprotected, no controls. The combat pass paints it at once and is
-- complete; the end of combat by itself scans and paints nothing.
do
    local body = Window(nil)
    local popup = Window("ContractDeathPopup", { body })
    GenericWindows.ApplyEntry(Entry("contract-death", { "ContractDeathPopup" }), "contract")
    Check(popup.reads == 0 and popup.surfaceSpec == nil, "a hidden window was scanned before its first show")
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    local attaches = counters.attach
    popup:Show()
    Check(popup.reads == 1 and body.reads == 1 and popup.surfaceSpec ~= nil,
        "the first combat show did not paint the window at once")
    local painted, reads = counters.attach - attaches, Reads(popup, body)
    Check(Gate.GetPendingCount() == 0,
        "a complete combat pass queued a full repass for the end of combat")
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    RunTimers()
    Check(Reads(popup, body) == reads and counters.attach - attaches == painted,
        "the end of combat scanned or painted a window the combat pass completed")
    -- Steady re-show, in and out of combat: no discovery, no scan, no paint.
    popup:Hide()
    popup:Show()
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    popup:Hide()
    popup:Show()
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    RunTimers()
    Check(Reads(popup, body) == reads and counters.attach - attaches == painted,
        "a steady re-show repeated the window's scan or paint")
    popup:Hide()
end

-- 2. Combat held a protected member back: the existing owner (the combat
-- gate job) runs the full pass after combat, which paints it. Two such
-- windows drain in request order; combat restarting mid-drain holds the rest.
local function Holder(name)
    local panel = Window(nil)
    panel.protected = true
    panel.Bg = {}
    local holder = Window(name, { Window(nil) })
    holder.Inset = panel -- a named member, not a descendant
    return holder, panel
end
do
    local first, firstPanel = Holder("ContractHolderA")
    local second, secondPanel = Holder("ContractHolderB")
    GenericWindows.ApplyEntry(Entry("contract-holder-b", { "ContractHolderB" }), "contract")
    GenericWindows.ApplyEntry(Entry("contract-holder-a", { "ContractHolderA" }), "contract")
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    local refusals = Safety.ImplicitRefusals()
    first:Show()
    second:Show()
    Check(first.surfaceSpec ~= nil and second.surfaceSpec ~= nil and firstPanel.surfaceSpec == nil
        and Safety.ImplicitRefusals() > refusals,
        "the combat pass did not paint the windows, painted a protected member or missed its refusal")
    Check(Gate.GetPendingCount() == 2, "combat-held work was not queued with its owner")
    local order = {}
    local attach = NS.Surface.Attach
    NS.Surface.Attach = function(target, spec)
        if target == first or target == second then
            order[#order + 1] = target
            clock = clock + 10
        end
        return attach(target, spec)
    end
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    Check(#order == 1 and order[1] == first and Gate.GetPendingCount() == 1,
        "the drain did not run the first job and keep the rest for the next frame")
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    RunTimers()
    Check(#order == 1 and Gate.GetPendingCount() == 1, "a job ran after combat restarted mid-drain")
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    RunTimers()
    NS.Surface.Attach = attach
    Check(#order == 2 and order[2] == second and Gate.GetPendingCount() == 0,
        "the remaining job was lost or reordered after the combat restart")
    Check(firstPanel.surfaceSpec ~= nil and secondPanel.surfaceSpec ~= nil,
        "the full pass after combat did not finish the protected members")
end

-- 3. A window closed before combat ends keeps its job's work for its next
-- show, exactly once.
do
    local late = Window(nil)
    late.protected = true
    late.Bg = {}
    local closing = Window("ContractClosing", { Window(nil) })
    closing.Inset = late
    GenericWindows.ApplyEntry(Entry("contract-closing", { "ContractClosing" }), "contract")
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    closing:Show()
    Check(Gate.GetPendingCount() == 1, "the held-back member was not queued")
    closing:Hide()
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    RunTimers()
    local reads = closing.reads
    Check(late.surfaceSpec == nil and reads == 1, "a closed window was painted at the end of combat")
    closing:Show()
    Check(late.surfaceSpec ~= nil and closing.reads == reads + 1, "the next show did not finish the held-back work")
    closing:Hide()
    closing:Show()
    Check(closing.reads == reads + 1, "the finished window repeated its pass on a steady re-show")
end

-- 4. Parts that wait for combat to end keep the full pass: window chrome,
-- window controls and a pass that failed.
do
    local chrome = Window("ContractChrome", { Window(nil) })
    GenericWindows.ApplyEntry(Entry("contract-chrome", { "ContractChrome" }, { role = "shell", windowChrome = "shell" }),
        "contract")
    local controlled = Window("ContractControlled", { Window(nil) })
    local attachControls = NS.WindowControls.Attach
    NS.WindowControls.Attach = function(frame) return frame == controlled end
    GenericWindows.ApplyEntry(Entry("contract-controls", { "ContractControlled" }), "contract")
    local failing = Window("ContractFailing", { Window(nil) })
    GenericWindows.ApplyEntry(Entry("contract-failing", { "ContractFailing" }), "contract")
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    chrome:Show()
    controlled:Show()
    local attach = NS.Surface.Attach
    NS.Surface.Attach = function(target, spec)
        if target == failing then return nil end
        return attach(target, spec)
    end
    failing:Show()
    NS.Surface.Attach = attach
    Check(Gate.GetPendingCount() == 3, "chrome, window controls or a failed pass lost its post-combat pass")
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    RunTimers()
    NS.WindowControls.Attach = attachControls
    Check(Gate.GetPendingCount() == 0 and chrome.reads == 2 and controlled.reads == 2 and failing.surfaceSpec ~= nil,
        "a queued full pass did not run after combat")
end

-- 5. A new revision (a settings refresh) while the window is open in combat
-- paints at once and leaves nothing for the end of combat.
do
    local open = Window("ContractOpen", { Window(nil) })
    open.shown = true
    SetCombat(true, "PLAYER_REGEN_DISABLED")
    GenericWindows.ApplyEntry(Entry("contract-open", { "ContractOpen" }), "contract")
    GenericWindows.ApplyEntry(Entry("contract-open", { "ContractOpen" }), "contract")
    Check(open.reads == 2 and Gate.GetPendingCount() == 0, "a combat refresh was not painted at once or queued a repass")
    SetCombat(false, "PLAYER_REGEN_ENABLED")
    RunTimers()
    Check(open.reads == 2, "the end of combat repeated a refreshed window")
end

-- 6. CanDecorate answers exactly as before; only implicit refusals count.
do
    local function Old(target, allow)
        if type(target) ~= "table" or Safety.IsForbidden(target) then return false end
        local protected, explicit = target:IsProtected()
        if issecretvalue(protected) or issecretvalue(explicit) then protected, explicit = true, true end
        if explicit == true then return false end
        if protected == true then return allow == true and not InCombatLockdown() end
        return true
    end
    local cases = {
        { IsProtected = function() return false, false end },
        { IsProtected = function() return true, false end },
        { IsProtected = function() return true, true end },
        { IsForbidden = function() return true end, IsProtected = function() return false, false end },
    }
    for _, combat in ipairs({ false, true }) do
        locked = combat
        for index, case in ipairs(cases) do
            for _, allow in ipairs({ false, true, nil }) do
                local before = Safety.ImplicitRefusals()
                local answer = Safety.CanDecorate(case, allow)
                Check(answer == Old(case, allow), "CanDecorate changed its answer for case " .. index)
                local counted = Safety.ImplicitRefusals() - before
                Check(counted == ((index == 2 and not answer) and 1 or 0), "an answer was miscounted for case " .. index)
            end
        end
    end
    locked = false
end

Check(#reported == 0, "a boundary reported: " .. table.concat(reported, "\n"))
assert(#failures == 0, table.concat(failures, "\n"))
print(("suite_skin_combat_repass_contract: %d checks"):format(checks))
