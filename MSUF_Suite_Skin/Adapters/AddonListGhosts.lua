local _, NS = ...

-- Native tree rows are released immediately. These mouse-transparent copies
-- render their last appearance for 160ms without retaining native pool rows.
local Ghost = {}
NS.AddonListGhosts = Ghost
local Safety, Motion = NS.Safety, NS.Motion
local fonts = { "Title", "Status", "Reload" }
local textures = { "GetNormalTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }

local function Finished(group)
    group.ghost:Hide()
    local state = group.state
    state.ghostActive = math.max(0, (state.ghostActive or 0) - 1)
    if state.ghostActive == 0 then
        state.ghostViewport:Hide()
        state.ghostCategory = nil
    end
    local record = group.record
    if record.node and state.active and Motion.Enabled() and Safety.CanCreateRegions(record.row)
        and Safety.Read(record.row, "IsVisible") == true then Ghost.Capture(state, record) end
end

local function CreateCopy(state, record)
    local clip = state.ghostClip
    if state.generic then
        clip = Safety.CreateChildFrame("Frame", state.ghostViewport)
        clip:SetClipsChildren(true)
        clip:EnableMouse(false)
    end
    local row = Safety.CreateChildFrame("Frame", clip)
    row:EnableMouse(false)
    row:SetSize(state.width, 16)
    row:Hide()
    local group = row:CreateAnimationGroup()
    group.ghost, group.state, group.record = row, state, record
    group:SetScript("OnFinished", Finished)
    local move, alpha = group:CreateAnimation("Translation"), group:CreateAnimation("Alpha")
    move:SetDuration(0.16)
    alpha:SetDuration(0.16)
    move:SetSmoothing("IN_OUT")
    alpha:SetSmoothing("IN_OUT")
    local copy = { frame = row, clip = clip, group = group, move = move, alpha = alpha, fonts = {}, textures = {} }
    if not state.generic then
        for index = 1, 4 do copy.fonts[index] = row:CreateFontString(nil, "OVERLAY") end
        for index = 1, 3 do copy.textures[index] = row:CreateTexture(nil, "ARTWORK") end
    end
    record.ghost = copy
    state.ghostRows[copy] = true
    return copy
end

function Ghost.Stop(state)
    if not state.ghostRows then return end
    for copy in pairs(state.ghostRows) do copy.group:Stop() copy.frame:Hide() copy.pendingNode = nil end
    state.ghostViewport:Hide()
    state.ghostCategory, state.ghostPending, state.ghostActive = nil, nil, 0
    state.ghostPendingCopies = nil
end

local function Scrolled(state)
    if state.ghostCategory and not state.ghostPending then Ghost.Stop(state) end
end

local function EnsureViewport(state)
    if state.ghostViewport then
        if not state.collection and not state.ghostWatching then
            state.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, Scrolled, state)
            state.ghostWatching = true
        end
        return
    end
    local viewport = Safety.CreateChildFrame("Frame", state.scrollBox)
    viewport:SetAllPoints(state.scrollBox)
    viewport:SetClipsChildren(true)
    viewport:EnableMouse(false)
    viewport:SetFrameLevel((Safety.Read(state.scrollBox, "GetFrameLevel") or 0) + 10)
    local clip = Safety.CreateChildFrame("Frame", viewport)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    state.ghostViewport, state.ghostClip, state.ghostRows = viewport, clip, {}
    viewport:Hide()
    if not state.collection then
        state.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, Scrolled, state)
        state.ghostWatching = true
    end
end

local function Anchor(copy, source, row, top)
    local left, sourceTop = Safety.Read(source, "GetLeft"), Safety.Read(source, "GetTop")
    local rowLeft = Safety.Read(row, "GetLeft")
    local width, height = Safety.Read(source, "GetWidth"), Safety.Read(source, "GetHeight")
    if type(left) ~= "number" or type(sourceTop) ~= "number" or type(rowLeft) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number" then copy:Hide() return false end
    copy:ClearAllPoints()
    copy:SetPoint("TOPLEFT", copy:GetParent(), "TOPLEFT", left - rowLeft, sourceTop - top)
    copy:SetSize(width, height)
    copy:Show()
    return true
end

local function CopyFont(target, source, row, top)
    local text = Safety.Read(source, "GetText")
    if type(text) ~= "string" or Safety.Read(source, "IsShown") ~= true then target:Hide() return end
    local path, size, flags = Safety.Call(source, "GetFont")
    if not Safety.Public(path) or not Safety.Public(size) or not Safety.Public(flags)
        or type(path) ~= "string" or type(size) ~= "number" then target:Hide() return end
    if not Anchor(target, source, row, top) then return end
    target:SetFont(path, size, flags or "")
    target:SetText(text)
    target:SetJustifyH(Safety.Read(source, "GetJustifyH") or "LEFT")
    target:SetJustifyV(Safety.Read(source, "GetJustifyV") or "MIDDLE")
    target:SetAlpha(Safety.Read(source, "GetAlpha") or 1)
    local r, g, b, a = Safety.ReadColor(source, "GetTextColor")
    if r then target:SetTextColor(r, g, b, a) end
end

local function CopyTexture(target, source, row, top, shown)
    if not shown or not source then target:Hide() return end
    local atlas, texture = Safety.Read(source, "GetAtlas"), Safety.Read(source, "GetTexture")
    if not atlas and not texture then target:Hide() return end
    if not Anchor(target, source, row, top) then return end
    if atlas then target:SetAtlas(atlas) else target:SetTexture(texture) end
    local r, g, b, a = Safety.ReadColor(source, "GetVertexColor")
    if r then target:SetVertexColor(r, g, b, a) end
    target:SetAlpha(Safety.Read(source, "GetAlpha") or 1)
    target:SetDesaturated(Safety.Read(source, "IsDesaturated") == true)
end

local function CaptureRegion(state, record, copy, source)
    if Safety.Read(source, "IsVisible") ~= true then return end
    if state.model == "encounter" and source == Safety.Field(record.row, "description") then return end
    local kind = Safety.Read(source, "GetObjectType")
    local target
    if kind == "FontString" and copy.fontCount < 8 then
        copy.fontCount = copy.fontCount + 1
        target = copy.fonts[copy.fontCount] or copy.frame:CreateFontString(nil, "OVERLAY")
        copy.fonts[copy.fontCount] = target
        CopyFont(target, source, record.row, record.top)
    elseif kind == "Texture" and copy.textureCount < 16 then
        copy.textureCount = copy.textureCount + 1
        target = copy.textures[copy.textureCount] or copy.frame:CreateTexture(nil, "ARTWORK")
        copy.textures[copy.textureCount] = target
        CopyTexture(target, source, record.row, record.top, true)
        local a, b, c, d, e, f, g, h = Safety.Call(source, "GetTexCoord")
        if Safety.Public(a) and Safety.Public(b) and Safety.Public(c) and Safety.Public(d)
            and Safety.Public(e) and Safety.Public(f) and Safety.Public(g) and Safety.Public(h)
            and type(a) == "number" and type(h) == "number" then
            target:SetTexCoord(a, b, c, d, e, f, g, h)
        end
    end
    if target then
        local effective, base = Safety.Read(source, "GetEffectiveAlpha"), Safety.Read(state.scrollBox, "GetEffectiveAlpha")
        local rowAlpha = Safety.Read(record.row, "GetAlpha")
        if type(effective) == "number" and type(base) == "number" and type(rowAlpha) == "number" and base > 0 and rowAlpha > 0 then
            target:SetAlpha(effective / (base * rowAlpha))
        end
    end
end

local captureState, captureRecord, captureCopy
local CaptureChildren
local function CaptureRegions(...)
    for index = 1, select("#", ...) do CaptureRegion(captureState, captureRecord, captureCopy, select(index, ...)) end
end
local function CaptureFrames(depth, ...)
    for index = 1, select("#", ...) do CaptureChildren(select(index, ...), depth) end
end
CaptureChildren = function(frame, depth)
    if depth > 2 or captureCopy.budget <= 0 or not Safety.CanCreateRegions(frame)
        or Safety.Read(frame, "IsVisible") ~= true then return end
    captureCopy.budget = captureCopy.budget - 1
    CaptureRegions(Safety.Call(frame, "GetRegions"))
    CaptureFrames(depth + 1, Safety.Call(frame, "GetChildren"))
end

local function CaptureGeneric(state, record, copy)
    copy.fontCount, copy.textureCount, copy.budget = 0, 0, 24
    captureState, captureRecord, captureCopy = state, record, copy
    local kind = Safety.Read(record.row, "GetObjectType")
    if kind == "FontString" or kind == "Texture" then CaptureRegion(state, record, copy, record.row)
    else CaptureChildren(record.row, 0) end
    captureState, captureRecord, captureCopy = nil, nil, nil
    for index = copy.fontCount + 1, #copy.fonts do copy.fonts[index]:Hide() end
    for index = copy.textureCount + 1, #copy.textures do copy.textures[index]:Hide() end
end

function Ghost.Capture(state, record)
    if state.generic and (record.parent == nil or state.model == "tree" and Safety.Read(record.parent, "GetDepth") == 0) then return end
    if not Safety.HasMethod(state.scrollBox, "GetLeft") then return end
    EnsureViewport(state)
    local copy = record.ghost or CreateCopy(state, record)
    -- Do not repaint a copy currently representing a released native row.
    if copy.group:IsPlaying() or copy.pendingNode then return end
    local row, top = record.row, record.top
    local cached = copy.node == record.node and copy.generation == state.ghostGeneration
        and copy.width == state.width and copy.scale == state.scale
        and (not state.generic or copy.provider == state.provider and not copy.dirty)
    copy.node, copy.top = record.node, top
    copy.left = Safety.Read(row, "GetLeft")
    copy.viewportTop = Safety.Read(state.scrollBox, "GetTop")
    copy.viewportLeft = Safety.Read(state.scrollBox, "GetLeft")
    copy.nativeAlpha = Safety.Read(row, "GetAlpha")
    copy.displayTop, copy.displayAlpha = nil, nil
    if cached then return end
    copy.generation, copy.width, copy.scale = state.ghostGeneration, state.width, state.scale
    copy.provider, copy.dirty = state.provider, false
    if state.generic then CaptureGeneric(state, record, copy) return end
    for index = 1, 3 do CopyFont(copy.fonts[index], Safety.Field(row, fonts[index]), row, top) end
    local button = Safety.Field(row, "LoadAddonButton")
    local label = Safety.Read(button, "IsShown") and Safety.Read(button, "GetFontString")
    CopyFont(copy.fonts[4], label, row, top)
    local checkbox = Safety.Field(row, "Enabled")
    local checked, enabled = Safety.Read(checkbox, "GetChecked"), Safety.Read(checkbox, "IsEnabled")
    for index = 1, 3 do
        local shown = Safety.Read(checkbox, "IsShown") == true
            and (index == 1 or checked == true and (index == 2 and enabled ~= false or index == 3 and enabled == false))
        CopyTexture(copy.textures[index], Safety.Read(checkbox, textures[index]), row, top, shown)
    end
end

local function ClosingParent(state, node)
    for _ = 1, 16 do
        node = Safety.Read(node, "GetParent")
        if not node then return end
        if state.collapsed[node] == false and Safety.Read(node, "IsCollapsed") == true then return node end
    end
end

local function HeaderHeight(state, category)
    for index = 1, state.count do
        local record = state.rows[index]
        if record.node == category then return Safety.Read(record.row, "GetHeight") end
    end
end

local function Displayed(record, copy)
    local top, alpha = copy.top, copy.nativeAlpha
    if record.group and Safety.Read(record.group, "IsPlaying") then
        local progress = Safety.Read(record.translation, "GetSmoothProgress")
        local fade = Safety.Read(record.alpha, "GetSmoothProgress")
        if type(progress) == "number" then top = top + record.offset * progress end
        if type(fade) == "number" then alpha = record.alphaFrom + (record.alphaTo - record.alphaFrom) * fade end
    end
    local state = record.state
    local parent = state and state.model == "encounter" and state.records[Safety.Read(record.row, "GetParent")]
    if parent then
        if parent.group and Safety.Read(parent.group, "IsPlaying") then
            local progress = Safety.Read(parent.translation, "GetSmoothProgress")
            local fade = Safety.Read(parent.alpha, "GetSmoothProgress")
            local base = Safety.Read(parent.row, "GetAlpha")
            if type(progress) == "number" then top = top + parent.offset * progress end
            if type(fade) == "number" and type(base) == "number" and base > 0 and type(alpha) == "number" then
                alpha = alpha * (parent.alphaFrom + (parent.alphaTo - parent.alphaFrom) * fade) / base
            end
        elseif Safety.Read(parent.row, "IsVisible") ~= true then
            top = top + (parent.hiddenOffset or 0)
        end
    end
    return top, alpha
end

function Ghost.Initialized(state, row)
    local record = state.records[row]
    if record and record.ghost then record.ghost.dirty = true end
end

function Ghost.Hidden(record)
    local copy = record.ghost
    if copy then
        copy.displayTop, copy.displayAlpha = Displayed(record, copy)
        record.hiddenOffset = copy.displayTop - record.top
    end
end

local function PlayCopy(state, record, copy, category)
    local headerTop, height = state.previous[category], HeaderHeight(state, category)
    if state.generic and headerTop == nil then headerTop, height = copy.viewportTop, 0 end
    if type(headerTop) ~= "number" or type(height) ~= "number" or type(copy.left) ~= "number"
        or type(copy.viewportTop) ~= "number" or type(copy.viewportLeft) ~= "number" then return end
    if not state.generic and state.ghostCategory ~= category then Ghost.Stop(state) end
    state.ghostCategory, state.ghostPending = category, true
    local top, alpha = Displayed(record, copy)
    top, alpha = copy.displayTop or top, copy.displayAlpha or alpha
    if type(alpha) ~= "number" then return end
    local boundary, clip = headerTop - height, copy.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", state.ghostViewport, "TOPLEFT", 0, boundary - copy.viewportTop)
    clip:SetPoint("BOTTOMRIGHT", state.ghostViewport, "BOTTOMRIGHT", 0, 0)
    copy.frame:ClearAllPoints()
    copy.frame:SetPoint("TOPLEFT", clip, "TOPLEFT", copy.left - copy.viewportLeft, top - boundary)
    copy.frame:SetAlpha(1)
    copy.move:SetOffset(0, math.max(16, boundary - top + 16))
    copy.alpha:SetFromAlpha(alpha)
    copy.alpha:SetToAlpha(0)
    state.ghostViewport:Show()
    copy.frame:Show()
    if not copy.group:IsPlaying() then state.ghostActive = (state.ghostActive or 0) + 1 end
    copy.group:Stop()
    copy.group:Play()
end

function Ghost.Released(state, record, node)
    local copy = record.ghost
    if state.generic then node = record.node end
    if not copy or copy.node ~= node or not Motion.Enabled() or not state.active
        or not Safety.CanCreateRegions(record.row) or Safety.GetProtection(record.row)
        or not state.generic and type(Safety.Read(record.row, "GetTop")) ~= "number"
        or state.model == "tree" and Safety.Read(state.scrollBox, "GetDataProvider") ~= state.provider then return end
    if state.generic and state.model ~= "tree" then
        copy.pendingNode, copy.pendingParent, copy.pendingRecord = copy.node, record.parent, record
        state.ghostPendingCopies = true
        return
    end
    local category = ClosingParent(state, node)
    if category then PlayCopy(state, record, copy, category) end
end

function Ghost.AfterLayout(state)
    if not state.generic or state.model == "tree" or not state.ghostRows or not state.ghostPendingCopies then return end
    state.ghostPendingCopies = nil
    for copy in pairs(state.ghostRows) do
        if copy.pendingNode then
            local parent = copy.pendingParent
            for _ = 1, 16 do
                if not parent then break end
                if state.changes[parent] == true and not state.seenKeys[copy.pendingNode] then
                    PlayCopy(state, copy.pendingRecord, copy, parent)
                    break
                end
                parent = state.parents[parent]
            end
            local record = copy.pendingRecord
            copy.pendingNode, copy.pendingParent, copy.pendingRecord = nil, nil, nil
            if record.node and not copy.group:IsPlaying() then Ghost.Capture(state, record) end
        end
    end
end

function Ghost.Layout(state, provider, offset, width, height, scale)
    if state.generic and state.model ~= "tree" then
        if width ~= state.width or height ~= state.height or scale ~= state.scale
            or offset ~= state.offset and not state.ghostPendingCopies then Ghost.Stop(state) end
        return
    end
    if not state.ghostCategory then return end
    local stable = provider == state.provider and width == state.width and height == state.height and scale == state.scale
        and (state.ghostPending or offset == state.offset)
        and Safety.Read(state.ghostCategory, "IsCollapsed") == true
    local collapse = stable and state.ghostPending
    if not stable then Ghost.Stop(state) end
    state.ghostPending = nil
    return collapse
end
function Ghost.Release(state)
    Ghost.Stop(state)
    if state.ghostViewport and not state.collection then
        state.scrollBox:UnregisterCallback(ScrollBoxListMixin.Event.OnScroll, state)
        state.ghostWatching = false
    end
end
NS.AddonListMotion.SetGhostProvider(Ghost)
