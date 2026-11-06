local _, P = ...
local NS, S = P.NS, P.Suite
local Selection = { groups = setmetatable({}, { __mode = "k" }) }
P.BagTabSelection = Selection

local function Place(record, x, y)
    record.frame:ClearAllPoints()
    record.frame:SetPoint("TOPLEFT", record.view.chrome, "TOPLEFT", x, y)
    record.x, record.y = x, y
end

local function Snap(record)
    if record.group then record.group:Stop() end
    if NS.IsCombatLocked() and not P.BagLayout.Frame(record.frame) then
        record.needsSnap = true
        return
    end
    record.needsSnap = nil
    Place(record, record.toX, record.toY)
end

local function Finished(group) Snap(group.selection) end

local function New(view)
    local frame = P.ChildFrame("Frame", view.chrome)
    frame:EnableMouse(false)
    -- Tabs are child buttons one level higher: their text stays above the fill.
    frame:SetFrameLevel(view.chrome:GetFrameLevel())
    local fill = S.CreateTexture(frame, nil, "BACKGROUND")
    fill:SetAllPoints(frame)
    local edges = {}
    local corners = { {"TOPLEFT","TOPRIGHT"}, {"BOTTOMLEFT","BOTTOMRIGHT"},
        {"TOPLEFT","BOTTOMLEFT"}, {"TOPRIGHT","BOTTOMRIGHT"} }
    for i = 1, 4 do
        local edge = S.CreateTexture(frame, nil, "BORDER")
        edge:SetPoint(corners[i][1])
        edge:SetPoint(corners[i][2])
        if i < 3 then edge:SetHeight(1) else edge:SetWidth(1) end
        edges[i] = edge
    end
    local record = { frame = frame, fill = fill, edges = edges, view = view, chrome = view.chrome }
    view.tabSelection, Selection.groups[view] = record, record
    return record
end

local function Paint(record, config)
    if record.accent == config.accentColor then return end
    record.accent = config.accentColor
    local r, g, b = S.RGB(record.accent)
    record.fill:SetColorTexture(r, g, b, .154)
    for i = 1, 4 do record.edges[i]:SetColorTexture(r, g, b, .7) end
end

-- Top-relative units survive content-fit height changes between views.
local function Rect(view, button)
    local x, y, width, height = button:GetScaledRect()
    local left, bottom, _, chromeHeight = view.chrome:GetScaledRect()
    local scale = view.chrome:GetEffectiveScale()
    return (x - left) / scale, (y + height - bottom - chromeHeight) / scale, width / scale, height / scale
end

local function Current(record)
    if record.group and record.group:IsPlaying() then
        -- Sample before Stop: GetSmoothProgress already includes OUT easing.
        local progress = record.move:GetSmoothProgress()
        return record.fromX + record.moveX * progress, record.fromY + record.moveY * progress
    end
    return record.x, record.y
end

local function Move(record, button, config, animate)
    local x, y = Current(record)
    local targetX, targetY, width, height = Rect(record.view, button)
    if record.group then record.group:Stop() end
    record.selected, record.toX, record.toY = button, targetX, targetY
    record.frame:SetSize(width, height)
    if not animate or P.BagMotion.Mode(config) == NS.BagsAnimation.OFF or not x or x == targetX and y == targetY then
        Snap(record)
        return
    end
    if not record.group then
        record.group = record.frame:CreateAnimationGroup()
        record.move = record.group:CreateAnimation("Translation")
        record.group.selection = record
        record.group:SetScript("OnFinished", Finished)
        record.move:SetSmoothing("OUT")
    end
    record.fromX, record.fromY = x, y
    record.moveX, record.moveY = targetX - x, targetY - y
    Place(record, x, y)
    record.move:SetOffset(record.moveX, record.moveY)
    record.move:SetDuration(config.animationMode == NS.BagsAnimation.FULL and .16 or .12)
    record.group:Play()
end

function Selection.Refresh(view, config, geometryChanged)
    local record = view.tabSelection
    if not record or record.chrome ~= view.chrome then record = New(view) end
    Paint(record, config)
    local target = view.tabs[config.inventoryView]
    local reset = geometryChanged or record.needsSnap or record.mode ~= config.animationMode
    record.mode = config.animationMode
    if record.selected == target and not reset then return end
    if view.transitionPending and record.selected and not reset then return end
    Move(record, target, config, false)
end

function Selection.Switch(view, config)
    Selection.Refresh(view, config)
    Move(view.tabSelection, view.tabs[config.inventoryView], config, true)
end

local function Stop(record)
    if record.view.transitionPending and not NS.InCombat() then
        local x, y = Current(record)
        if record.group then record.group:Stop() end
        Place(record, x, y)
    else
        Snap(record)
    end
end

function Selection.StopAll()
    for _, record in pairs(Selection.groups) do Stop(record) end
end

-- Reuse the same motor for the clipped category rail and editor list.
function Selection.List(owner, parent, buttons, selected, config, animate, reset)
    local nav = owner.selectionView
    if not nav then nav = { look = {} } owner.selectionView = nav end
    nav.chrome, nav.tabs, nav.transitionPending = parent, buttons, animate
    nav.look.accentColor, nav.look.animationMode, nav.look.inventoryView = config.accentColor, config.animationMode, selected
    if not buttons[selected] then
        if nav.tabSelection then
            Stop(nav.tabSelection)
            nav.tabSelection.frame:Hide()
            nav.tabSelection.needsSnap = true
        end
        return
    end
    Selection.Refresh(nav, nav.look, reset)
    nav.tabSelection.frame:Show()
    if animate then Selection.Switch(nav, nav.look) end
    nav.transitionPending = false
end

function Selection.HideList(owner)
    local nav = owner.selectionView
    if not nav or not nav.tabSelection then return end
    local record = nav.tabSelection
    if record.group then record.group:Stop() end
    record.frame:Hide()
    record.needsSnap = true
end

P.BagMotion.SetSelectionStop(Selection.StopAll)
