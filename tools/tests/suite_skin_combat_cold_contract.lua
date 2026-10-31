-- Real motion providers: hidden history must not enlarge combat work.
local root = assert(arg[1])
local prior = arg[3]
arg[3] = "coverage"
local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
arg[3] = prior
local NS, Frame = H.NS, H.Frame
local callbacks = {}
for _, frame in ipairs(H.frames) do
    if frame.events.PLAYER_REGEN_DISABLED then callbacks[#callbacks + 1] = frame end
end
local function Edge()
    for _, frame in ipairs(callbacks) do frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
end
local function LeaveCombat()
    for _, frame in ipairs(H.frames) do
        if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
    end
end
local function Steps(fn)
    local count = 0
    debug.sethook(function() count = count + 1 end, "", 1)
    fn()
    debug.sethook()
    return count
end
local function Result(owner, parent)
    local target = Frame(parent, true)
    target.provider = {}
    function target:GetDataProvider() return self.provider end
    NS.ResultMotion.Track(target, owner)
    target.provider = {}
    target:TriggerEvent("layout")
    return target, assert(NS.ContentMotion.records[target])
end
Edge()
local base = Steps(Edge)
LeaveCombat()
local hiddenStops = 0
local hidden = {}
for i = 1, 128 do
    local target, record = Result("hidden-results")
    local stop = record.group.Stop
    record.group.Stop = function(self) hiddenStops = hiddenStops + 1 stop(self) end
    target:Hide()
    hidden[i] = target
end
hiddenStops = 0
local populated = Steps(Edge)
assert(hiddenStops == 0, "combat stopped animations of already hidden windows again")
assert(populated <= base + 100, "hidden result history enlarged combat scans")
LeaveCombat()
local shown = hidden[1]
shown:Show()
shown:Fire("OnShow")
shown.provider = {}
shown:TriggerEvent("layout")
local record = NS.ContentMotion.records[shown]
assert(record.group:IsPlaying(), "reopened results failed to animate")
Edge()
assert(not record.group:IsPlaying() and record.owner == nil, "visible result motion did not release on combat")
shown:Hide()
NS.ResultMotion.ReleaseOwner("hidden-results")

LeaveCombat()
local parent = Frame(nil, true)
local child, childRecord = Result("parent-results", parent)
parent:Hide()
child:Fire("OnHide") -- Native OnHide also fires when an ancestor hides.
assert(child:IsShown() and not child:IsVisible() and not childRecord.group:IsPlaying())
Edge()
LeaveCombat()
parent:Show()
child:Fire("OnShow")
child.provider = {}
child:TriggerEvent("layout")
assert(childRecord.group:IsPlaying(), "parent reopen lost result motion")
Edge()
assert(not childRecord.group:IsPlaying() and childRecord.owner == nil,
    "parent reopen failed to rejoin combat cancellation")
NS.ResultMotion.ReleaseOwner("parent-results")
LeaveCombat()
local target, other = Frame(nil, true), Frame(nil, true)
local owner = {}
assert(NS.ContentMotion.Play(target, owner, 1))
assert(NS.ContentMotion.Play(other, owner, 1))
assert(not NS.ContentMotion.StopOwner(owner, false), "invalid target released unrelated content")
assert(NS.ContentMotion.StopOwner(owner, target), "targeted owner release missed its record")
assert(NS.ContentMotion.records[other].group:IsPlaying(), "targeted stop cancelled another target")
assert(not NS.ContentMotion.StopOwner({}, other), "foreign owner cancelled content")
assert(NS.ContentMotion.StopOwner(owner), "owner-wide cleanup lost remaining content")
assert(not NS.ContentMotion.records[other].group:IsPlaying())
local finished = Frame(nil, true)
assert(NS.ContentMotion.Play(finished, owner, 7))
local finishedRecord = NS.ContentMotion.records[finished]
finishedRecord.group:Finish()
assert(not finishedRecord.group:IsPlaying())
H.listeners[NS.ContentMotion]()
assert(NS.ContentMotion.Play(finished, owner, 7))
assert(finishedRecord.group:IsPlaying(), "settings change failed to invalidate completed content token")
print("Skin combat cold path: 128 hidden windows, 0 native stops; VM " .. base .. " -> " .. populated)
