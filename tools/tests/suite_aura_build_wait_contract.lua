local root = assert(arg[1], "repository root required")
-- Native panel removal/reset wakes deferred aura builds on Forever.
-- SmartNavigation.lua from Forever 70938: ResetVars and RemovePanelInfo
-- own the active panel list. Waiting for changes costs no timer callbacks.

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

function hooksecurefunc(target, key, after)
    assert(key == "RemovePanelInfo" or key == "ResetVars", "unexpected hook")
    local original = target[key]
    target[key] = function(self, ...)
        local result = original(self, ...)
        after(self, ...)
        return result
    end
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
function SmartNavigation:ResetVars() self.activePanels = {} end
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
Advance(3600)
assert(ran == 0 and fired == 0 and Pending() == 0, "an open gamepad panel kept checking")
character:Hide()
assert(#SmartNavigation.activePanels == 0 and ran == 0, "the builds ran inside the panel's OnHide")
Advance(0)
assert(ran == 1, "a closed gamepad panel did not wake the waiting builds at once (one callback per owner)")
Advance(30)
assert(Pending() == 0, "aura build checks kept running after the last wait")

-- An old panel can remain listed under a hidden parent without more OnHide.
local party = Panel()
GroupTargeting:StartTargeting(party)
GroupTargeting:StopTargeting()
assert(#SmartNavigation.activePanels == 1, "fixture: Blizzard's stop order changed")
local waited = 0
Client.AfterAuraBuild("plates", function() waited = waited + 1 end)
local before = fired
Advance(3600)
assert(waited == 0 and Client.AuraBuildBlocked() and fired == before and Pending() == 0,
    "the stale panel caused polling or let builds run")
SmartNavigation:RemovePanelInfo(party)
assert(waited == 0 and Pending() == 1, "removal did not defer the wake by one frame")
Advance(0)
assert(waited == 1 and Pending() == 0, "native removal without OnHide did not wake the builds")

-- Only the last removal wakes the queue, even when combat defers the owner.
local spells, inventory = Panel(), Panel()
SmartNavigation:HandlePanelOpen(spells)
SmartNavigation:HandlePanelOpen(inventory)
combat = true
local processed = 0
Client.AfterAuraBuild("glows", function() processed = processed + 1 end)
Client.AfterAuraBuild("removed", function() error("a cancelled owner resumed") end)
Client.CancelAuraBuild("removed")
assert(#spells.hooks == 1 and #inventory.hooks == 1, "the addon hooked script on a Blizzard panel")
combat = false
spells:Hide()
assert(Pending() == 0 and processed == 0, "the first removal woke the builds")
SmartNavigation:ResetVars()
assert(Pending() == 1 and processed == 0, "native reset did not schedule the waiting work")
Advance(0)
assert(processed == 1 and Pending() == 0, "native reset failed to drain the last owner")

-- A second panel opened before the queued callback must block the waiting builds.
SmartNavigation:HandlePanelOpen(spells)
Client.AfterAuraBuild("plates", function() processed = processed + 1 end)
spells:Hide()
SmartNavigation:HandlePanelOpen(inventory)
Advance(0)
assert(processed == 1 and Pending() == 0, "the old wake crossed a newly opened panel")
inventory:Hide()
Advance(0)
assert(processed == 2 and Pending() == 0, "reopened panel stranded the owner")
print("suite_aura_build_wait_contract: native close/reset, cancellation and dormant waits passed")
