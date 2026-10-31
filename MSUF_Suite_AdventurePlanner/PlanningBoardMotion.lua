local _, P = ...
local NS, B = P.NS, P.PlanningTools.Board
local S, Plan = P.Suite, P.PlanningTools
local ToggleMaximize
local Bridge = NS.HostBridge
-- MSUF's popup motion: popupIn 0.105 s from scale 0.988, popupOut 0.085 s to
-- 0.994, and a short fade for a new page. MSUF's reduced motion skips them.
-- Animation groups run only while they play; the window stops every one of
-- them when it hides, so combat entry leaves nothing running.
local OPEN, CLOSE, PAGE = .105, .085, .14
local OPEN_SCALE, CLOSE_SCALE = .988, .994

function B.Reduced()
    return Bridge.MenuReducedMotion()
end

local function Group(region, scaled)
    local group = region:CreateAnimationGroup()
    group.fade = group:CreateAnimation("Alpha")
    if scaled then
        local scale = group:CreateAnimation("Scale")
        if scale.SetScaleFrom then group.scale = scale end
    end
    return group
end

local function Play(group, fromAlpha, toAlpha, duration, smoothing, fromScale, toScale)
    group:Stop()
    group.fade:SetFromAlpha(fromAlpha)
    group.fade:SetToAlpha(toAlpha)
    group.fade:SetDuration(duration)
    group.fade:SetSmoothing(smoothing)
    if group.scale then
        group.scale:SetScaleFrom(fromScale, fromScale)
        group.scale:SetScaleTo(toScale, toScale)
        group.scale:SetDuration(duration)
        group.scale:SetSmoothing(smoothing)
        group.scale:SetOrigin("CENTER", 0, 0)
    end
    group:Play()
end

local function Opened(group)
    group:GetParent():SetAlpha(1)
end

local function Closed(group)
    local window = group:GetParent()
    if window.plannerClosing then
        local after = window.plannerAfterClose
        window.plannerAfterClose = nil
        window.plannerClosing = nil
        if not after then B.ClearRestore(window) end
        window:Hide()
        if after then after(window) end
    end
end

function B.CreateMotion(window)
    window.openMotion = Group(window, true)
    window.openMotion:SetScript("OnFinished", Opened)
    window.closeMotion = Group(window, true)
    window.closeMotion:SetScript("OnFinished", Closed)
    window.pageMotion = Group(window.body, false)
    window.resizeMotion = Group(window, true)
    window.foldMotion, window.foldRegions = Group(window, false), {}
    window.foldMotion:SetScript("OnFinished", function() B.FinishAccordion(window, true) end)
end

function B.StopMotion(window)
    window.plannerClosing, window.plannerAfterClose = nil, nil
    B.FinishAccordion(window, false)
    window.resizeMotion:Stop()
    window.openMotion:Stop()
    window.closeMotion:Stop()
    window.pageMotion:Stop()
    window:SetAlpha(1)
    window.body:SetAlpha(1)
end

function B.PlayOpen(window)
    B.StopMotion(window)
    if B.Reduced() then return end
    window:SetAlpha(0)
    Play(window.openMotion, 0, 1, OPEN, "OUT", OPEN_SCALE, 1)
end

function B.PlayClose(window, after)
    if window.plannerClosing then window.plannerAfterClose = after return end
    B.StopMotion(window)
    if B.Reduced() then
        if not after then B.ClearRestore(window) end
        window:Hide()
        if after then after(window) end
        return
    end
    window.plannerAfterClose = after
    window.plannerClosing = true
    Play(window.closeMotion, 1, 0, CLOSE, "IN", 1, CLOSE_SCALE)
end

function B.PlayPage(window)
    if B.Reduced() or window.plannerClosing then return end
    Play(window.pageMotion, 0, 1, PAGE, "OUT", 1, 1)
end

function B.PlayResize(window, previous)
    if B.Reduced() then return end
    Play(window.resizeMotion, 1, 1, OPEN, "OUT", previous / window:GetScale(), 1)
end

function B.FinishAccordion(window, apply)
    if not window.foldActive then return end
    local commit = window.foldCommit
    window.foldActive, window.foldCommit = nil, nil
    window.foldMotion:Stop()
    for i = #window.foldRegions, 1, -1 do
        local region = window.foldRegions[i]
        region.plannerFoldMotion:Stop()
        region:ClearAllPoints()
        region:SetPoint(region.foldPoint, region.foldParent, region.foldRelative, region.foldX, region.foldY)
        window.foldRegions[i] = nil
    end
    if apply and commit and B.Valid(window) and window:IsShown() then commit(window) end
end

function B.AddFoldRegion(window, region, distance, child)
    local regions = window.foldRegions
    regions[#regions + 1] = region
    region.foldDistance, region.foldChild = distance, child
end

local function RegionFold(region, opening)
    local group = region.plannerFoldMotion
    if not group then
        group = Group(region, true)
        group.shift = group:CreateAnimation("Translation")
        region.plannerFoldMotion = group
    end
    region.foldPoint, region.foldParent, region.foldRelative, region.foldX, region.foldY = region:GetPoint(1)
    local distance = region.foldDistance
    if opening then
        region:ClearAllPoints()
        region:SetPoint(region.foldPoint, region.foldParent, region.foldRelative, region.foldX, region.foldY + distance)
    end
    group.fade:SetFromAlpha(opening and region.foldChild and 0 or 1)
    group.fade:SetToAlpha(not opening and region.foldChild and 0 or 1)
    group.fade:SetDuration(OPEN)
    group.fade:SetSmoothing("OUT")
    group.scale:SetScaleFrom(1, opening and region.foldChild and .001 or 1)
    group.scale:SetScaleTo(1, not opening and region.foldChild and .001 or 1)
    group.scale:SetDuration(OPEN)
    group.scale:SetSmoothing("OUT")
    group.scale:SetOrigin("TOPLEFT", 0, 0)
    group.shift:SetOffset(0, opening and -distance or distance)
    group.shift:SetDuration(OPEN)
    group.shift:SetSmoothing("OUT")
    group:Play()
end

function B.PlayAccordion(window, opening, commit, gather, key)
    B.FinishAccordion(window, true)
    if B.Reduced() then return commit(window) end
    if opening then commit(window) end
    gather(window, key)
    if #window.foldRegions == 0 then
        if not opening then commit(window) end
        return
    end
    window.foldActive, window.foldCommit = true, not opening and commit or nil
    for _, region in ipairs(window.foldRegions) do RegionFold(region, opening) end
    Play(window.foldMotion, 1, 1, OPEN, "OUT", 1, 1)
end

function B.ClearRestore(window)
    local bar = window.restoreBar
    if not bar then return end
    bar:Hide()
    bar.owner, bar.spec, bar.profile, bar.query, bar.selected = nil, nil, nil, nil, nil
    bar.column, bar.offset, bar.maximized = nil, nil, nil
end

local function RestorePlanner(bar)
    local owner, spec, profile = bar.owner, bar.spec, bar.profile
    if not owner or profile ~= NS.DB or not Plan.CanEdit() then return B.ClearRestore(B.window) end
    local query, selected, column, offset, maximized = bar.query, bar.selected, bar.column, bar.offset, bar.maximized
    local window = B.Open(owner, spec)
    if not window then return end
    window.search:SetText(query or "")
    window.matrix.characterOffset, window.selected = column or 0, selected
    window:Refresh()
    if spec.currentTab(owner) == "characters" then window.matrix.scroller:SetOffset(offset or 0)
    else window.listScroll:SetOffset(offset or 0) end
    if maximized then ToggleMaximize(window) end
end

local function ShowRestore(window)
    local bar = window.restoreBar
    if bar.owner and bar.profile == NS.DB and Plan.CanEdit() then bar:Show()
    else B.ClearRestore(window) end
end

local function Minimize(window)
    if not B.Valid(window) then return end
    B.FinishAccordion(window, true)
    local bar = window.restoreBar
    bar.owner, bar.spec, bar.profile = window.owner, window.spec, window.profile
    bar.query, bar.selected = window.search:GetText(), window.selected
    bar.column, bar.maximized = window.matrix.characterOffset, window.maximized
    bar.offset = window.spec.currentTab(window.owner) == "characters" and window.matrix.scroller.offset or window.listScroll.offset
    bar:SetScale(window:GetScale())
    B.PlayClose(window, ShowRestore)
end

ToggleMaximize = function(window)
    if not B.Valid(window) then return end
    B.FinishAccordion(window, true)
    B.StopMotion(window)
    local previous = window:GetScale()
    if window.maximized then
        window.maximized = nil
        window:SetScale(window.normalScale)
        window:ClearAllPoints()
        window:SetPoint(unpack(window.normalPoint))
    else
        window.normalScale, window.normalPoint = previous, { window:GetPoint(1) }
        window.maximized = true
        window:SetScale(math.min((UIParent:GetWidth() - 40) / B.WIDTH, (UIParent:GetHeight() - 40) / B.HEIGHT))
        window:ClearAllPoints()
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    window.scaleGrip:SetShown(not window.maximized)
    window.restoreGlyph:SetShown(window.maximized == true)
    B.PlayResize(window, previous)
end

function B.CreateWindowControls(window)
    local minimize = B.Button(window, "", 28, 22, function() Minimize(window) end)
    minimize:SetPoint("TOPRIGHT", -72, -8)
    local line = B.Texture(minimize, "OVERLAY", "text")
    line:SetSize(10, 1)
    line:SetPoint("CENTER")
    local maximize = B.Button(window, "", 28, 22, function() ToggleMaximize(window) end)
    maximize:SetPoint("TOPRIGHT", -42, -8)
    local square = S.CreateFrame("Frame", nil, maximize)
    square:SetSize(9, 8)
    square:SetPoint("CENTER")
    B.Edges(square, "text")
    local restore = S.CreateFrame("Frame", nil, maximize)
    restore:SetSize(9, 8)
    restore:SetPoint("CENTER", 2, 2)
    B.Edges(restore, "text")
    restore:Hide()
    window.minimize, window.maximize, window.restoreGlyph = minimize, maximize, restore
    local bar = B.Button(UIParent, "Adventure planner", 250, 28, RestorePlanner)
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 16)
    bar:SetFrameStrata("DIALOG")
    bar.text:ClearAllPoints()
    bar.text:SetPoint("LEFT", 12, 0)
    bar.text:SetPoint("RIGHT", -34, 0)
    local close = B.Button(bar, "X", 24, 22, function() B.ClearRestore(window) end)
    close:SetPoint("RIGHT", -3, 0)
    bar.close = close
    bar:Hide()
    window.restoreBar = bar
end

-- Escape closes an open text editor first, then the planner; every other key
-- reaches the game. The window is hidden in combat, so this never runs under
-- combat lockdown.
local function KeyDown(window, key)
    if InCombatLockdown() then return end
    local close = key == "ESCAPE"
    window:SetPropagateKeyboardInput(not close)
    if not close then return end
    local editor = P.Suite.ToolListWindow
    if editor.IsEditing(window.owner) then return editor.Close(window.owner) end
    B.Dismiss(window.owner)
end

function B.CreateKeyboard(window)
    window:EnableKeyboard(true)
    window:SetPropagateKeyboardInput(true)
    window:SetScript("OnKeyDown", KeyDown)
end
