local root = assert(arg[1], "repository root required")
-- The wait of aura container builds behind Forever's gamepad navigation
-- (MSUF_Suite/Core/Platform.lua AuraBuildBlocked/AfterAuraBuild), with the
-- real Platform.lua against a faithful subset of Blizzard's SmartNavigation
-- (forever 70291 Blizzard_GamepadSmartNavigation/SmartNavigation.lua:
-- GetPanelInfo :726-751, HandlePanelClose :778-780, RemovePanelInfo
-- :782-807) and GroupTargeting's stop order (Blizzard_GamepadTargeting/
-- GroupTargeting.lua:103-123). A closed panel wakes the builds at once; a
-- panel left listed for good (StopTargeting drops nil, :108 then :121, and a
-- host that parks the party frames under a hidden parent never hides them
-- again) costs a check every two seconds after the first five, not four a
-- second all session; the checks stop with the last wait.

MSUF_NS = { Client = { Flavor = "Mainline", IsForever = true } }
C_EventUtils = { IsEventValid = function() return true end }
securecallfunction = function(fn, ...) return fn(...) end
local now, combat, timers, tickers, fired = 0, false, {}, {}, 0
function GetTime() return now end
function InCombatLockdown() return combat end
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { due = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local ticker = { interval = interval, fn = fn, due = now + interval }
        function ticker:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}
-- Runs every timer and ticker due within the next `seconds`, in time order.
local function Advance(seconds)
    local stop = now + seconds
    while true do
        local best, due, ticker
        for i, t in ipairs(timers) do
            if t.due <= stop and (not due or t.due < due) then best, due, ticker = i, t.due, false end
        end
        for i, t in ipairs(tickers) do
            if not t.cancelled and t.due <= stop and (not due or t.due < due) then best, due, ticker = i, t.due, true end
        end
        if not best then break end
        now, fired = due, fired + 1
        if ticker then
            local t = tickers[best]
            t.due = t.due + t.interval
            t.fn(t)
        else
            table.remove(timers, best).fn()
        end
    end
    now = stop
end
local function Pending()
    local n = #timers
    for _, t in ipairs(tickers) do if not t.cancelled then n = n + 1 end end
    return n
end

local Suite = {}
assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", Suite)
local Client = Suite.Client
assert(Client.isForever, "the contract needs the Forever branch")

SmartNavigation = { activePanels = {}, hookedFrames = {} }
function SmartNavigation:GetPanelInfo(frame, dontCreate)
    for _, info in ipairs(self.activePanels) do if info.frame == frame then return info end end
    if dontCreate then return nil end
    local info = { frame = frame, buttonGroups = {} }
    if not self.hookedFrames[frame] then
        self.hookedFrames[frame] = true
        frame:HookScript("OnHide", function(hidden) self:HandlePanelClose(hidden) end)
    end
    table.insert(self.activePanels, info)
    return info
end
function SmartNavigation:RemovePanelInfo(frame)
    for i, info in ipairs(self.activePanels) do
        if info.frame == frame then
            table.remove(self.activePanels, i)
            return true
        end
    end
    return false
end
function SmartNavigation:HandlePanelClose(panel) self:RemovePanelInfo(panel) end
function SmartNavigation:HandlePanelOpen(panel) self:GetPanelInfo(panel) end
local GroupTargeting = {}
function GroupTargeting:StartTargeting(container)
    self.currentTargetingContainer = container
    SmartNavigation:HandlePanelOpen(container)
end
function GroupTargeting:StopTargeting()
    self.currentTargetingContainer = nil
    SmartNavigation:HandlePanelClose(self.currentTargetingContainer)
end

-- A panel frame: HookScript keeps the hooks in order, Hide runs them (the
-- OnHide script chain); nothing else of it is readable.
local function Panel()
    local frame = { hooks = {} }
    function frame:HookScript(script, fn)
        assert(script == "OnHide", "only the panel's OnHide is hooked")
        assert(not combat, "a gamepad panel was hooked in combat")
        self.hooks[#self.hooks + 1] = fn
    end
    function frame:Hide() for _, fn in ipairs(self.hooks) do fn(self) end end
    function frame:IsForbidden() return false end
    return setmetatable(frame, { __newindex = function(_, key) error("addon wrote field " .. key .. " on a panel") end })
end

-- Retail (no SmartNavigation) and Forever without an open panel never wait.
assert(not Client.AuraBuildBlocked(), "an empty panel list blocked aura builds")

-- A panel that closes wakes the waiting builds one frame later, before the
-- next check, and nothing keeps running afterwards.
local character, ran = Panel(), 0
SmartNavigation:HandlePanelOpen(character)
assert(Client.AuraBuildBlocked(), "an open gamepad panel did not block aura builds")
Client.AfterAuraBuild("bars", function(owner) assert(owner == "bars"); ran = ran + 1 end)
Client.AfterAuraBuild("bars", function(owner) assert(owner == "bars"); ran = ran + 1 end)
Advance(1)
assert(ran == 0, "builds ran under an open gamepad panel")
character:Hide()
assert(#SmartNavigation.activePanels == 0 and ran == 0, "the builds ran inside the panel's OnHide")
Advance(0)
assert(ran == 1, "a closed gamepad panel did not wake the waiting builds at once (one callback per owner)")
Advance(30)
assert(Pending() == 0, "aura build checks kept running after the last wait")

-- A panel GroupTargeting leaves listed under a hidden parent: one hour of
-- waiting costs the quarter-second checks of the first five seconds and one
-- check every two seconds after that.
local party = Panel()
GroupTargeting:StartTargeting(party)
GroupTargeting:StopTargeting()
assert(#SmartNavigation.activePanels == 1, "fixture: Blizzard's stop order no longer leaves the panel listed")
local waited = 0
Client.AfterAuraBuild("plates", function() waited = waited + 1 end)
local before = fired
Advance(3600)
local checks = fired - before
assert(waited == 0 and Client.AuraBuildBlocked(), "the stale panel let builds run")
assert(checks <= 20 + 1800 + 2, "a stale gamepad panel kept four aura build checks a second running: " .. checks)
assert(Pending() == 1, "the wait for a stale panel stopped checking")
-- The panel leaves the list without an OnHide (the host's group frames come
-- back and go): the next two-second check runs the builds and the chain ends.
SmartNavigation:RemovePanelInfo(party)
Advance(2)
assert(waited == 1, "the builds did not run within two seconds of the panel leaving")
Advance(30)
assert(Pending() == 0, "aura build checks kept running after the stale panel left")

-- In combat no panel is hooked (it may hold secure frames); the first check
-- out of combat hooks it.
local spells = Panel()
SmartNavigation:HandlePanelOpen(spells)
combat = true
Client.AfterAuraBuild("glows", function() end)
assert(#spells.hooks == 1, "a gamepad panel was hooked in combat")
combat = false
Advance(0.25)
assert(#spells.hooks == 2, "the gamepad panel was not watched once combat ended")
spells:Hide()
Advance(0)
assert(Pending() <= 1, "a closed panel left more than its last check behind")
Advance(30)
assert(Pending() == 0, "aura build checks kept running after the last wait")
print("suite_aura_build_wait_contract: panel wake, stale-panel back-off and self-stopping checks passed")
