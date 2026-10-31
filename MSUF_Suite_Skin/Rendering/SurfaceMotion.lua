local _, NS = ...

-- Foreign frames keep their scripts, geometry, focus and visibility. Only
-- Suite-owned fill/edge/hover textures move. MSUF's own animated controls opt
-- out through ownedArt; public clients can explicitly choose motion=true/false.
local SurfaceMotion = {}
NS.SurfaceMotion = SurfaceMotion
local Motion, Safety = NS.Motion, NS.Safety
local groups = setmetatable({}, { __mode = "k" })
local clamp = NS.Clamp
local opacityMaterial = { opacity = "control" }
-- Shared read-only rest pose. A surface owns writable channels only once its
-- first gesture starts; paints and hides before that need no spring object.
local idleChannels = {}
for index = 1, 7 do idleChannels[index] = { value = index == 7 and 1 or 0, target = 0, velocity = 0 } end

local function Safe(record)
    local state = record.state
    return state.visible ~= false and Safety.ReadUnprotected(state.target, "IsVisible") == true
        and not Safety.IsCompositorManaged(state.target)
end

local function Anchor(region, state, x, y, width, height, press)
    if not region then return end
    local inset = (tonumber(state.spec.inset) or 0) + press
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", state.target, "BOTTOMLEFT", inset + x, inset + y)
    region:SetPoint("TOPRIGHT", state.target, "TOPRIGHT", -inset + x + width, -inset + y + height)
end

local function Paint(record)
    local state, channels = record.state, record.channels or idleChannels
    local reveal, press = clamp(channels[7].value, 0, 1), channels[6].value
    local x, y = channels[1].value, channels[2].value
    local width, height = channels[3].value, channels[4].value
    if record.x ~= x or record.y ~= y or record.width ~= width or record.height ~= height
        or record.press ~= press or record.inset ~= state.spec.inset then
        Anchor(state.fill, state, x, y, width, height, press)
        Anchor(state.edge, state, x, y, width, height, press)
        record.x, record.y, record.width, record.height, record.press = x, y, width, height, press
        record.inset = state.spec.inset
    end
    local fillAlpha, edgeAlpha, depthAlpha = record.fillAlpha * reveal, record.edgeAlpha * reveal, record.depthAlpha * reveal
    if record.paintedFillAlpha ~= fillAlpha then state.fill:SetAlpha(fillAlpha) end
    if record.paintedEdgeAlpha ~= edgeAlpha then state.edge:SetAlpha(edgeAlpha) end
    if state.depth and record.paintedDepthAlpha ~= depthAlpha then state.depth:SetAlpha(depthAlpha) end
    record.paintedFillAlpha, record.paintedEdgeAlpha, record.paintedDepthAlpha = fillAlpha, edgeAlpha, depthAlpha
    if state.kind == "button" then
        local highlightAlpha = (channels[5].value > 0 or channels[5].target > 0) and 0 or record.nativeHighlightAlpha
        if record.paintedHighlightAlpha ~= highlightAlpha then state.highlight:SetAlpha(highlightAlpha) end
        record.paintedHighlightAlpha = highlightAlpha
    end
    local overlay = state.hoverOverlay
    if overlay and record.hoverAlpha then
        local alpha = record.hoverAlpha * clamp(channels[5].value, 0, 1)
        overlay:SetVertexColor(record.hoverR, record.hoverG, record.hoverB, alpha)
        if alpha > 0 and state.hoverEnabled then overlay:Show() else overlay:Hide() end
    end
end

local function Record(target)
    local state = NS.Registry.GetSurface(target)
    local record = state and state.motion
    if record and record.enabled and Motion.Enabled(state.spec)
        and (not Safety.HasMethod(target, "IsEnabled") or Safety.Read(target, "IsEnabled") == true) then
        if not record.channels then Motion.New(state, Paint, Safe, Motion.Restore, record) end
        return record
    end
end

local function Hover(target, entered)
    local record = Record(target)
    if not record then return end
    local state = record.state
    state.hovered = entered
    Motion.Set(record, 5, (entered or record.focused) and state.hoverEnabled and 1 or 0)
    Motion.Play(record, 0.12)
end
local function Enter(target) Hover(target, true) end
local function Leave(target) Hover(target, false) end
local function FocusIn(target)
    local record = Record(target)
    if record then
        record.focused = true
        Hover(target, record.state.hovered)
    end
end
local function FocusOut(target)
    local record = Record(target)
    if record then
        record.focused = false
        Hover(target, record.state.hovered)
    end
end
local function Press(target)
    local record = Record(target)
    if record and Safety.Read(target, "IsEnabled") ~= false then
        Motion.Set(record, 6, 1)
        Motion.Play(record, 0.14)
    end
end
local function Release(target)
    local record = Record(target)
    if record then
        Motion.Set(record, 6, 0)
        Motion.Play(record, 0.14)
    end
end
local function Click(target)
    local record = Record(target)
    if not record then return end
    local checked = Safety.Read(target, "GetChecked")
    if checked == nil then Motion.Set(record, 6, 0, 1)
    elseif checked == record.checked then return
    else
        record.checked = checked
        Motion.Set(record, 7, 1, 0.8)
    end
    Motion.Play(record, 0.14)
end
local function Hide(target)
    local state = NS.Registry.GetSurface(target)
    local record = state and state.motion
    if not record then return end
    record.focused, record.state.hovered = false, false
    if record.channels then Motion.Clear(record) else Motion.Restore(record) end
    record.lastActive = nil
    record.carryX, record.carryY, record.carryWidth, record.carryHeight = 0, 0, 0, 0
end

local function Show(target)
    local record = Record(target)
    if not record then return end
    record.checked = Safety.Read(target, "GetChecked")
    if not record.window then return end
    -- ContentMotion loads later; native OnShow runs after the complete load graph.
    -- Resolve here and use registration, independent of the OnShow hook order.
    local completeFade = NS.ContentMotion.HasOpeningFade(target)
    Motion.Set(record, 7, 1, completeFade and 1 or 0)
    Motion.Set(record, 2, 0, -3)
    Motion.Play(record, 0.16)
end

local hoverHooks = { OnEnter = Enter, OnLeave = Leave }
local hooks = {
    OnHide = Hide, OnDisable = Hide, OnShow = Show,
    OnEditFocusGained = FocusIn, OnEditFocusLost = FocusOut,
    OnClick = Click,
}
-- Controls only. Forever's SmartNavigation reads GetScript("OnMouseUp"/"OnMouseDown")
-- of every frame it scans that is not a Button or EditBox by type (Blizzard_Gamepad-
-- SmartNavigation/Utility.lua:196-206): a skin hook on a plain shell or popup Frame
-- (Game Menu, child panels) is a skin-tainted value in that secure scan.
local pressHooks = { OnMouseDown = Press, OnMouseUp = Release }

local function HookAll(target, list)
    for event, callback in pairs(list) do
        if target:HasScript(event) then target:HookScript(event, callback) end
    end
end

local function Bind(state)
    local target, spec = state.target, state.spec
    local kind = Safety.Read(target, "GetObjectType")
    local window = spec.role == "shell" or spec.role == "popup"
    local control = kind == "Button" or kind == "CheckButton" or kind == "EditBox"
    if spec.role == "status" or not (window or control)
        or not Safety.HasMethod(target, "HasScript") then return end
    local record = { state = state, paint = Paint, reset = Motion.Restore }
    record.window = window
    record.x, record.y, record.width, record.height, record.press = 0, 0, 0, 0, 0
    record.inset = state.spec.inset
    record.checked = Safety.Read(target, "GetChecked")
    state.motion = record
    if not window then
        state.hoverOverlay = state.hoverOverlay or target:CreateTexture(nil, "HIGHLIGHT", nil, 0)
        Anchor(state.hoverOverlay, state, 0, 0, 0, 0, 0)
    end
    HookAll(target, hooks)
    -- Mouse hooks can opt passive tooltips into hit testing. Preserve their
    -- native input policy while retaining the owned opening animation.
    if control or Safety.Read(target, "IsMouseMotionEnabled") == true then HookAll(target, hoverHooks) end
    if control then HookAll(target, pressHooks) end
    return record
end

-- Geometry is never used until every returned component is public. Coordinates
-- are compared only within one actual parent and converted through its scale.
local function Rect(target)
    if not Safety.HasMethod(target, "GetRect") then return end
    local x, y, width, height = target:GetRect()
    if not Safety.Public(x) or not Safety.Public(y) or not Safety.Public(width)
        or not Safety.Public(height) then return end
    local scale = Safety.Read(target, "GetEffectiveScale")
    if type(x) == "number" and type(y) == "number" and type(width) == "number"
        and type(height) == "number" and type(scale) == "number" and scale > 0 then
        return x * scale, y * scale, width * scale, height * scale, scale
    end
end

local function Travel(record, previous)
    if not previous or previous == record or previous.lastActive == nil or not Safe(previous) then return end
    if Safety.Read(record.state.target, "GetParent") ~= Safety.Read(previous.state.target, "GetParent") then return end
    local x, y, width, height, scale = Rect(record.state.target)
    local oldX, oldY, oldWidth, oldHeight, oldScale = Rect(previous.state.target)
    if not x or not oldX or width <= 0 or height <= 0 then return end
    Motion.New(record.state, Paint, Safe, Motion.Restore, record)
    local ratio = oldScale / scale
    Motion.Set(record, 1, 0, (oldX - x) / scale + (previous.carryX or 0) * ratio)
    Motion.Set(record, 2, 0, (oldY - y) / scale + (previous.carryY or 0) * ratio)
    Motion.Set(record, 3, 0, (oldWidth - width) / scale + (previous.carryWidth or 0) * ratio)
    Motion.Set(record, 4, 0, (oldHeight - height) / scale + (previous.carryHeight or 0) * ratio)
    record.channels[1].velocity, record.channels[2].velocity = (previous.carryVX or 0) * ratio, (previous.carryVY or 0) * ratio
    record.channels[3].velocity, record.channels[4].velocity = (previous.carryVW or 0) * ratio, (previous.carryVH or 0) * ratio
    Motion.Play(record, 0.16)
end

local function Carry(record)
    local c = record.channels or idleChannels
    record.carryX, record.carryY = c[1].value, c[2].value
    record.carryWidth, record.carryHeight = c[3].value, c[4].value
    record.carryVX, record.carryVY = c[1].velocity, c[2].velocity
    record.carryVW, record.carryVH = c[3].velocity, c[4].velocity
    if record.channels then
        for index = 1, 4 do Motion.Set(record, index, 0, 0) end
    end
end

local function Selection(record)
    local state, spec = record.state, record.state.spec
    local key = spec.motionGroup or (spec.role == "navigation" and "navigation")
    if not key or record.lastActive == (state.active == true) then return end
    local parent = Safety.Read(state.target, "GetParent")
    if not parent or parent == UIParent then return end
    local groupsForParent = groups[parent]
    if not groupsForParent then
        groupsForParent = {}
        groups[parent] = groupsForParent
    end
    local group = groupsForParent[key]
    if not group then
        group = {}
        groupsForParent[key] = group
    end
    if state.active then
        local previous = group.selected
        if previous and previous ~= record and previous.state.active then group.pending = record
        else
            group.selected = record
            Travel(record, previous)
        end
    elseif record.lastActive then
        Carry(record)
        if group.selected == record and group.pending and group.pending.state.active then
            group.selected = group.pending
            group.pending = nil
            Travel(group.selected, record)
        end
    end
end

local function HoverPaint(record)
    local state = record.state
    if not state.hoverOverlay then return end
    local asset, scale = NS.Surface.HoverStyle(state.geometry, NS.Theme.GetMaterialOpacity(opacityMaterial))
    NS.Geometry.ConfigureShape(state.hoverOverlay, asset, state.geometry)
    record.hoverR, record.hoverG, record.hoverB, record.hoverAlpha = NS.Theme.GetColor("hover")
    record.hoverAlpha = record.hoverAlpha * scale
    state.hoverEnabled = record.hoverAlpha > 0
    if state.kind == "button" then
        record.nativeHighlightAlpha = record.nativeHighlightAlpha or tonumber(Safety.Read(state.highlight, "GetAlpha")) or 1
        record.paintedHighlightAlpha = Safety.Read(state.highlight, "GetAlpha")
    end
end

function SurfaceMotion.Refresh(state)
    local record = state.motion
    if record then
        record.paintedFillAlpha = Safety.Read(state.fill, "GetAlpha")
        record.paintedEdgeAlpha = Safety.Read(state.edge, "GetAlpha")
        record.paintedDepthAlpha = Safety.Read(state.depth, "GetAlpha")
        if state.kind == "button" then record.paintedHighlightAlpha = Safety.Read(state.highlight, "GetAlpha") end
    end
    if not Motion.Enabled(state.spec) or not Safety.CanCreateRegions(state.target) then
        if record then
            Hide(state.target)
            record.enabled = state.visible ~= false
            if state.kind ~= "button" then NS.Surface.RefreshInteractiveHover(state, state.geometry) end
        end
        return
    end
    record = record or Bind(state)
    if not record then return end
    record.enabled = true
    -- Material opacity lives in vertex/gradient colors. Preserve the separate
    -- region-alpha bases rather than sampling our current reveal transform.
    record.fillAlpha = record.fillAlpha or tonumber(Safety.Read(state.fill, "GetAlpha")) or 1
    record.edgeAlpha = record.edgeAlpha or tonumber(Safety.Read(state.edge, "GetAlpha")) or 1
    record.depthAlpha = record.depthAlpha or tonumber(Safety.Read(state.depth, "GetAlpha")) or 1
    if state.visible == false then
        Hide(state.target)
        return
    end
    HoverPaint(record)
    Selection(record)
    record.lastActive = state.active == true
    Paint(record)
end
NS.Surface.SetMotionProvider(SurfaceMotion.Refresh)
