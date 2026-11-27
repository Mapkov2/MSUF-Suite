-- Repeated Track of an already tracked scroll target (perf pass 2026-11-26:
-- MenuMotion re-tracked 15 targets per Communities reopen; ScrollMotion.Track
-- 53 calls, LegacyScrollMotion.Track 30). A target this owner already tracks
-- with the same scroll partner skips rebuilding its bindings. A new partner, a
-- binding that is still missing, a release and a new owner take the full path.
-- Reuses the native controller fixture of the scroll motion contract.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_scroll_motion_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find("local box, bar = Controller(nil)", 1, true))
local body = [======[
wipe = function(values) for key in pairs(values) do values[key] = nil end end
for _, frame in ipairs(frames) do
    function frame:UnregisterEvent(event) self.events[event] = nil end
end
local create = CreateFrame
CreateFrame = function()
    local frame = create()
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end
Load("Rendering/LegacyScrollMotion.lua")
local Legacy = NS.LegacyScrollMotion
local reads = 0
local spied = { "IsForbidden", "IsProtected", "GetName", "GetParent", "CanInterpolateScroll", "IsVisible",
    "GetThumb", "GetView", "GetScrollTarget", "GetVerticalScroll" }
local function Spy(frame)
    for _, name in ipairs(spied) do
        local native = frame[name]
        if native then frame[name] = function(...) reads = reads + 1 return native(...) end end
    end
    return frame
end
local function Retrack(track, target, owner, times)
    reads = 0
    for _ = 1, times or 15 do Check(track(target, owner) == true, "a repeated Track lost its tracked answer") end
    return reads
end

-- ScrollBox and ScrollBar pair (controller lease).
local box, bar = Controller(nil), Controller(false, true)
box.registeredScrollBar, bar.registeredScrollBox = bar, box
Spy(box) Spy(bar)
Check(Motion.Track(box, "menu"), "controller pair was not tracked")
local warm = Retrack(Motion.Track, box, "menu")
print(("15 repeated controller Tracks: %d native reads"):format(warm))
Check(warm <= 165, "a repeated Track of a settled controller lease redid its setup")
Check(box.canInterpolateScroll == true and bar.canInterpolateScroll == true, "re-tracking changed the native pair")
-- A new partner takes the full path and its controller joins the lease.
local replacement = Spy(Controller(false, true))
box.registeredScrollBar, replacement.registeredScrollBox = replacement, box
reads = 0
Check(Motion.Track(box, "menu") and reads > 0 and Motion.states[replacement]
    and Motion.states[replacement].leases[Motion.targets[box].menu], "a replaced scroll partner was not tracked")
Check(Retrack(Motion.Track, box, "menu") <= 165, "the new partner did not settle its lease")
-- Another owner and a released owner take the full path.
reads = 0
Check(Motion.Track(box, "other") and reads > 0, "a new owner reused another owner's lease")
Motion.ReleaseOwner("menu")
reads = 0
Check(Motion.Track(box, "menu") and reads > 0 and Motion.targets[box].menu, "a released owner was not tracked again")
Motion.ReleaseOwner("menu") Motion.ReleaseOwner("other")

-- A thumb that is not readable yet keeps the full path until it binds.
local late, lateBar = Controller(nil), Controller(false, true)
late.registeredScrollBar, lateBar.registeredScrollBox = lateBar, late
local thumb = lateBar.thumb
lateBar.thumb = nil
Check(Motion.Track(late, "menu") and not Motion.states[lateBar].thumb, "fixture bound a missing thumb")
lateBar.thumb = thumb
Check(Motion.Track(late, "menu") and Motion.states[lateBar].thumb == thumb, "a late thumb was never bound")
Spy(late) Spy(lateBar)
Check(Retrack(Motion.Track, late, "menu") <= 165, "a lease with its late thumb did not settle")
Motion.ReleaseOwner("menu")

-- Native list lease (Blizzard-owned controller fields).
local window = Spy(Frame())
function window:GetName() return "CommunitiesFrame" end
local list = Controller(nil)
function list:GetParent() return window end
function list:GetScrollTarget() return nil end
Spy(list)
Check(Motion.Track(list, "menu") and not Motion.states[list], "native Communities list left its native lease")
local nativeReads = Retrack(Motion.Track, list, "menu")
print(("15 repeated native list Tracks: %d native reads"):format(nativeReads))
Check(nativeReads <= 120, "a repeated Track of a native list lease redid its setup")
Motion.ReleaseOwner("menu")
reads = 0
Check(Motion.Track(list, "menu") and reads > 0, "a released native list lease was not tracked again")
Motion.ReleaseOwner("menu")

-- Parentage can change the route without giving the controller a new partner.
local parent = Frame()
local moved = Controller(false)
moved.parent = parent
function moved:GetParent() return self.parent end
function moved:GetScrollTarget() return nil end
Check(Motion.Track(moved, "reparent") and Motion.states[moved], "normal controller did not bind")
moved.parent = window
Check(Motion.Track(moved, "reparent") and next(moved.callbacks[ScrollBoxListMixin.Event.OnScroll] or {}),
    "a reparented Communities list lost its native render callback")
Motion.ReleaseOwner("reparent")
local movedOut = Controller(false)
movedOut.parent = window
function movedOut:GetParent() return self.parent end
function movedOut:GetScrollTarget() return nil end
Check(Motion.Track(movedOut, "reparent") and not Motion.states[movedOut], "native list took controller ownership")
movedOut.parent = parent
Check(Motion.Track(movedOut, "reparent") and Motion.states[movedOut], "a former native list did not bind as a controller")
Motion.ReleaseOwner("reparent")

-- Legacy ScrollFrame with a Slider bar.
local function Legacy_Frame(scrollBar)
    local scroll = Frame()
    function scroll:GetScrollChild() return nil end
    function scroll:GetVerticalScroll() return 0 end
    scroll.ScrollBar = scrollBar
    return Spy(scroll)
end
local slider = Spy(Frame())
local legacy = Legacy_Frame(slider)
Check(Legacy.Track(legacy, "menu") and Legacy.states[legacy].bar == slider, "legacy frame was not tracked")
local legacyReads = Retrack(Legacy.Track, legacy, "menu")
print(("15 repeated legacy Tracks: %d native reads"):format(legacyReads))
Check(legacyReads <= 30, "a repeated legacy Track exceeded its frame safety reads")
local newSlider = Spy(Frame())
legacy.ScrollBar = newSlider
reads = 0
Check(Legacy.Track(legacy, "menu") and reads > 0 and Legacy.states[legacy].bar == newSlider,
    "a replaced legacy bar was not tracked")
Check(Retrack(Legacy.Track, legacy, "menu") <= 30, "the replaced legacy bar did not settle")
Legacy.ReleaseOwner("menu")
reads = 0
Check(Legacy.Track(legacy, "menu") and reads > 0 and Legacy.states[legacy].owners.menu,
    "a released legacy frame was not tracked again")
Legacy.ReleaseOwner("menu")

-- Legacy ScrollFrame with a modern bar: ScrollMotion's lease answers for it.
local modern = Spy(Controller(false, true))
local delegating = Legacy_Frame(modern)
Check(Legacy.Track(delegating, "menu") and Motion.targets[modern].menu, "modern legacy bar was not delegated")
local delegatedReads = Retrack(Legacy.Track, delegating, "menu")
print(("15 repeated delegated legacy Tracks: %d native reads"):format(delegatedReads))
Check(delegatedReads <= 120, "a repeated delegated legacy Track redid its setup")
Motion.ReleaseOwner("menu")
reads = 0
Check(Legacy.Track(delegating, "menu") and reads > 0 and Motion.targets[modern].menu,
    "a released delegated bar was not tracked again")
Legacy.ReleaseOwner("menu")

-- A known legacy bar is not warm until its drag hooks can be bound.
local lateSlider = Frame()
lateSlider.forbidden = true
local lateLegacy = Legacy_Frame(lateSlider)
Check(Legacy.Track(lateLegacy, "menu") and Legacy.states[lateLegacy].bar == nil,
    "a forbidden legacy bar was bound")
lateSlider.forbidden = false
Check(Legacy.Track(lateLegacy, "menu") and Legacy.states[lateLegacy].bar == lateSlider
    and lateSlider.hooks.OnShow, "a newly safe legacy bar was never bound")
Legacy.ReleaseOwner("menu")

if NS.Client.isForever then
    QuestMapFrame = Frame()
    NS.AdapterKit = { IsDescendantOf = function(frame, ancestor) return frame:GetParent() == ancestor end }
    local reused = Legacy_Frame(slider)
    function reused:GetParent() return self.parent end
    Check(Legacy.Track(reused, "menu") and not Legacy.states[reused].snapToTop,
        "a generic legacy scroller used quest reset handling")
    reused.parent = QuestMapFrame
    Check(Legacy.Track(reused, "menu") and Legacy.states[reused].snapToTop,
        "a legacy scroller moved into the quest pane kept its generic policy")
    reused.parent = nil
    Check(Legacy.Track(reused, "menu") and not Legacy.states[reused].snapToTop,
        "a legacy scroller moved out of the quest pane kept quest reset handling")
    QuestMapFrame = nil
    Legacy.ReleaseOwner("menu")
end
print("Suite scroll re-track (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")
]======]
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    arg[2] = flavor
    assert(loadstring(source:sub(1, stop - 1) .. body, "@scroll_retrack_fixture"))()
end
