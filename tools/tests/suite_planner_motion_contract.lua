local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local args = arg
arg = { root, "--fixture", "-", flavor }
local E = assert(loadfile(root .. "/tools/tests/suite_planner_board_contract.lua"))()
arg = args
local st, NS, Plan, owner = E.st, E.NS, E.Plan, E.owner
local B, motions = Plan.Board, E.animations
local checks = 0
local function Check(value, message) assert(value, message) checks = checks + 1 end
local function Equal(actual, expected, message) Check(actual == expected, message .. ": " .. tostring(actual)) end
local function Finish(group)
    group.playing = nil
    if group.scripts.OnFinished then group.scripts.OnFinished(group) end
end
owner:Enable()
st.Flush()
Plan.Account().windowScale = .85
motions.hold = true
Plan.Window.Open("characters")
local window = B.window
Check(window.openMotion:IsPlaying(), "open must animate")
Finish(window.openMotion)
Equal(window:GetAlpha(), 1, "open completion restores base alpha")
local frames = #E.E.frames
local normal = window:GetScale()
window.maximize:Click()
Check(window.maximized and window.resizeMotion:IsPlaying(), "maximize must animate")
Check(window:GetScale() > normal and not window.scaleGrip:IsShown(), "maximize fits screen and suspends resize grip")
Check(window.resizeMotion.scale.fromX < 1 and window.resizeMotion.scale.toX == 1, "maximize animates from previous visual size")
Equal(Plan.Account().windowScale, .85, "maximize preserves normal user scale")
Finish(window.resizeMotion)
window.maximize:Click()
Equal(window:GetScale(), normal, "restore returns to normal size")
Check(not window.maximized and window.scaleGrip:IsShown(), "restore reactivates corner grip")
Finish(window.resizeMotion)
window.search:SetText("Alice")
local query, account = window.search:GetText(), Plan.Account()
window.minimize:Click()
Check(window:IsShown() and window.closeMotion:IsPlaying(), "minimize uses close motion before hiding")
Finish(window.closeMotion)
Check(not window:IsShown() and window.restoreBar:IsShown(), "minimize leaves a restore bar")
Check(window.owner == nil and window.matrix.model == nil, "minimize releases hidden view state")
window.restoreBar:Click()
Check(window:IsShown() and not window.restoreBar:IsShown(), "restore bar opens planner")
Equal(window.search:GetText(), query, "restore keeps search")
Equal(Plan.Account(), account, "window actions preserve account identity")
Finish(window.openMotion)
window.search:SetText("")
-- Both comparison sections and navigation sections use native scale/shift animations.
local view = window.matrix
local section
for _, band in ipairs(view.bands) do
    if band.activity and band.activity.kind == "section" and band.activity.key == "character" then section = band break end
end
Check(section ~= nil, "character accordion exists")
local rows = #view.rows
section.toggle:Click()
Check(window.foldActive and window.foldMotion:IsPlaying(), "close accordion starts bounded motion")
Equal(#view.rows, rows, "close retains old rows until motion completes")
local collapsedChild
for _, region in ipairs(window.foldRegions) do
    if region.foldChild then collapsedChild = region break end
end
Check(collapsedChild and collapsedChild.plannerFoldMotion.scale.toY == .001, "child content collapses vertically")
Finish(window.foldMotion)
Check(#view.rows < rows and not window.foldActive, "close completion commits folded layout")
section.toggle:Click()
Check(window.foldActive and #view.rows == rows, "open prepares final layout before entrance")
Finish(window.foldMotion)
Equal(#window.foldRegions, 0, "finished accordion releases transition references")
local caption = window.captions[1]
caption:Click()
Check(window.foldActive, "navigation collapse uses same motion")
Finish(window.foldMotion)
caption:Click()
Check(window.foldActive, "navigation expansion uses same motion")
Finish(window.foldMotion)
-- Rapid reversals, scrolling and reduced motion settle cleanly.
section.toggle:Click()
section.toggle:Click()
Check(window.foldActive, "rapid toggle reverses into an active entrance")
Finish(window.foldMotion)
Equal(Plan.Account().overviewFolded.character, nil, "rapid toggle keeps requested open state")
E.hostTheme.ReducedMotionEnabled = function() return true end
local plays = motions.playing
section.toggle:Click()
Check(not window.foldActive and #view.rows < rows, "reduced motion folds immediately")
window.maximize:Click()
Equal(motions.playing, plays, "reduced motion skips fold and maximize animations")
window.maximize:Click()
section.toggle:Click()
E.hostTheme.ReducedMotionEnabled = nil
window.minimize:Click()
window.close:Click()
Finish(window.closeMotion)
Check(not window.restoreBar:IsShown() and window.restoreBar.owner == nil,
    "latest close request must replace pending minimize")
Plan.Window.Open("characters")
Finish(window.openMotion)
window.close:Click()
window.minimize:Click()
Finish(window.closeMotion)
Check(window.restoreBar:IsShown(), "latest minimize request must replace pending close")
window.restoreBar:Click()
Finish(window.openMotion)
window.minimize:Click()
st.Event("PLAYER_REGEN_DISABLED")
Check(not window:IsShown() and not window.restoreBar:IsShown(), "combat clears both normal and minimized surfaces")
Finish(window.closeMotion)
Check(not window.restoreBar:IsShown(), "cancelled completion cannot resurrect restore bar")
st.Event("PLAYER_REGEN_ENABLED")
st.Flush()
Plan.Window.Open("characters")
Finish(window.openMotion)
window.minimize:Click()
Finish(window.closeMotion)
NS.DB = {}
window.restoreBar:Click()
Check(not window:IsShown() and not window.restoreBar:IsShown(), "stale profile restore is refused and cleared")
Equal(#E.E.frames, frames, "window controls reuse bounded frames")
print("Planner native motions: " .. checks .. " checks passed (" .. flavor .. ")")
