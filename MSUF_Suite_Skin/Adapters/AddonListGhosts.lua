local _, NS = ...

-- Native tree rows are released immediately. These mouse-transparent copies
-- animate the last rendered pose without retaining native pool rows.
local Ghost = {}
NS.AddonListGhosts = Ghost
local Safety, Motion = NS.Safety, NS.Motion
local ConfigureDisclosure = NS.SuiteCore().ConfigureDisclosure
local fonts = { "Title", "Status", "Reload" }
local textures = { "GetNormalTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }
local ROOT_ROW_DEPTH = 1

local function Finished(group)
    group.ghost:Hide()
    local state, copy = group.state, group.copy
    if state.activeGhosts[copy.node] == copy then state.activeGhosts[copy.node] = nil end
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
    ConfigureDisclosure(move)
    ConfigureDisclosure(alpha)
    local copy = { frame = row, clip = clip, group = group, move = move, alpha = alpha, fonts = {}, textures = {} }
    if not state.generic then
        for index = 1, 4 do copy.fonts[index] = row:CreateFontString(nil, "OVERLAY") end
        for index = 1, 3 do copy.textures[index] = row:CreateTexture(nil, "ARTWORK") end
    end
    record.ghost, group.copy = copy, copy
    state.ghostRows[copy] = true
    return copy
end

function Ghost.Stop(state)
    if not state.ghostRows then return end
    for copy in pairs(state.ghostRows) do copy.group:Stop() copy.frame:Hide() copy.pendingNode = nil end
    state.ghostViewport:Hide()
    wipe(state.activeGhosts)
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
    state.ghostViewport, state.ghostClip, state.ghostRows, state.activeGhosts = viewport, clip, {}, {}
    viewport:Hide()
    if not state.collection then
        state.scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, Scrolled, state)
        state.ghostWatching = true
    end
end

local function HideRegion(target, saved)
    if saved and saved.shown == false then return end
    target:Hide()
    if saved then saved.shown = false end
end

local function Anchor(target, source, row, top, saved)
    local left, sourceTop = Safety.Read(source, "GetLeft"), Safety.Read(source, "GetTop")
    local rowLeft = saved and saved.rowLeft or Safety.Read(row, "GetLeft")
    local width, height = Safety.Read(source, "GetWidth"), Safety.Read(source, "GetHeight")
    if type(left) ~= "number" or type(sourceTop) ~= "number" or type(rowLeft) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number" then HideRegion(target, saved) return false end
    left, sourceTop = left - rowLeft, sourceTop - top
    if not saved or left ~= saved.left or sourceTop ~= saved.top then
        target:ClearAllPoints()
        target:SetPoint("TOPLEFT", target:GetParent(), "TOPLEFT", left, sourceTop)
        if saved then saved.left, saved.top = left, sourceTop end
    end
    if not saved or width ~= saved.width or height ~= saved.height then
        target:SetSize(width, height)
        if saved then saved.width, saved.height = width, height end
    end
    if not saved or not saved.shown then
        target:Show()
        if saved then saved.shown = true end
    end
    return true
end

local function WriteValue(target, saved, key, setter, value)
    if not saved or saved[key] ~= value then
        setter(target, value)
        if saved then saved[key] = value end
    end
end

local function WriteColor(target, saved, setter, r, g, b, a)
    if r and (not saved or r ~= saved.r or g ~= saved.g or b ~= saved.b or a ~= saved.a) then
        setter(target, r, g, b, a)
        if saved then saved.r, saved.g, saved.b, saved.a = r, g, b, a end
    end
end

local function CopyFont(target, source, row, top, saved)
    local text = Safety.Read(source, "GetText")
    if type(text) ~= "string" or Safety.Read(source, "IsShown") ~= true then return HideRegion(target, saved) end
    local path, size, flags = Safety.Call(source, "GetFont")
    if not Safety.Public(path) or not Safety.Public(size) or not Safety.Public(flags)
        or type(path) ~= "string" or type(size) ~= "number" then return HideRegion(target, saved) end
    if not Anchor(target, source, row, top, saved) then return end
    flags = flags or ""
    if not saved or path ~= saved.path or size ~= saved.fontSize or flags ~= saved.flags then
        target:SetFont(path, size, flags)
        if saved then saved.path, saved.fontSize, saved.flags = path, size, flags end
    end
    WriteValue(target, saved, "text", target.SetText, text)
    WriteValue(target, saved, "justifyH", target.SetJustifyH, Safety.Read(source, "GetJustifyH") or "LEFT")
    WriteValue(target, saved, "justifyV", target.SetJustifyV, Safety.Read(source, "GetJustifyV") or "MIDDLE")
    if not saved then target:SetAlpha(Safety.Read(source, "GetAlpha") or 1) end
    WriteColor(target, saved, target.SetTextColor, Safety.ReadColor(source, "GetTextColor"))
    return true
end

local function CopyTexture(target, source, row, top, shown, saved)
    if not shown or not source then return HideRegion(target, saved) end
    local atlas, texture = Safety.Read(source, "GetAtlas"), Safety.Read(source, "GetTexture")
    if not atlas and not texture then return HideRegion(target, saved) end
    if not Anchor(target, source, row, top, saved) then return end
    if not saved or atlas ~= saved.atlas or not atlas and texture ~= saved.texture then
        if atlas then target:SetAtlas(atlas) else target:SetTexture(texture) end
        if saved then saved.atlas, saved.texture, saved.coordA = atlas, texture, nil end
    end
    WriteColor(target, saved, target.SetVertexColor, Safety.ReadColor(source, "GetVertexColor"))
    if not saved then target:SetAlpha(Safety.Read(source, "GetAlpha") or 1) end
    WriteValue(target, saved, "desaturated", target.SetDesaturated, Safety.Read(source, "IsDesaturated") == true)
    return true
end

local function CopyCoordinates(target, source, saved)
    local a, b, c, d, e, f, g, h = Safety.Call(source, "GetTexCoord")
    if not Safety.Public(a) or not Safety.Public(b) or not Safety.Public(c) or not Safety.Public(d)
        or not Safety.Public(e) or not Safety.Public(f) or not Safety.Public(g) or not Safety.Public(h)
        or type(a) ~= "number" or type(h) ~= "number" then return end
    if saved and a == saved.coordA and b == saved.coordB and c == saved.coordC and d == saved.coordD
        and e == saved.coordE and f == saved.coordF and g == saved.coordG and h == saved.coordH then return end
    target:SetTexCoord(a, b, c, d, e, f, g, h)
    if saved then
        saved.coordA, saved.coordB, saved.coordC, saved.coordD = a, b, c, d
        saved.coordE, saved.coordF, saved.coordG, saved.coordH = e, f, g, h
    end
end

local function SavedRegion(copy, target)
    local regions = copy.questRegions
    if not regions then return end
    local saved = regions[target]
    if not saved then
        saved = {}
        regions[target] = saved
    end
    saved.rowLeft = copy.left
    return saved
end

local function CaptureRegion(state, record, copy, source)
    if Safety.Read(source, "IsVisible") ~= true then return end
    if state.model == "encounter" and source == Safety.Field(record.row, "description") then return end
    local kind = Safety.Read(source, "GetObjectType")
    local target, saved, visible
    if kind == "FontString" and copy.fontCount < 8 then
        copy.fontCount = copy.fontCount + 1
        target = copy.fonts[copy.fontCount] or copy.frame:CreateFontString(nil, "OVERLAY")
        copy.fonts[copy.fontCount] = target
        saved = SavedRegion(copy, target)
        visible = CopyFont(target, source, record.row, record.top, saved)
    elseif kind == "Texture" and copy.textureCount < 16 then
        copy.textureCount = copy.textureCount + 1
        target = copy.textures[copy.textureCount] or copy.frame:CreateTexture(nil, "ARTWORK")
        copy.textures[copy.textureCount] = target
        saved = SavedRegion(copy, target)
        visible = CopyTexture(target, source, record.row, record.top, true, saved)
        if not saved or visible then CopyCoordinates(target, source, saved) end
    end
    if not target or saved and not visible then return end
    local effective = Safety.Read(source, "GetEffectiveAlpha")
    local base = saved and copy.questBase or Safety.Read(state.scrollBox, "GetEffectiveAlpha")
    local rowAlpha = saved and copy.nativeAlpha or Safety.Read(record.row, "GetAlpha")
    if type(effective) == "number" and type(base) == "number" and type(rowAlpha) == "number" and base > 0 and rowAlpha > 0 then
        WriteValue(target, saved, "alpha", target.SetAlpha, effective / (base * rowAlpha))
    elseif saved then
        WriteValue(target, saved, "alpha", target.SetAlpha, Safety.Read(source, "GetAlpha") or 1)
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
    local regions = copy.questRegions
    for index = copy.fontCount + 1, #copy.fonts do
        local target = copy.fonts[index]
        HideRegion(target, regions and regions[target])
    end
    for index = copy.textureCount + 1, #copy.textures do
        local target = copy.textures[index]
        HideRegion(target, regions and regions[target])
    end
end

function Ghost.Capture(state, record)
    if state.generic then
        if record.parent == nil or state.model == "tree" and Safety.Read(record.parent, "GetDepth") == 0 then return end
    elseif Safety.Read(record.node, "GetDepth") == ROOT_ROW_DEPTH then
        -- Direct children of the invisible root cannot leave a closing branch.
        return
    end
    if not Safety.HasMethod(state.scrollBox, "GetLeft") then return end
    EnsureViewport(state)
    local copy = record.ghost or CreateCopy(state, record)
    -- Do not repaint a copy currently representing a released native row.
    if copy.group:IsPlaying() or copy.pendingNode then return end
    local row, top = record.row, record.top
    local cached = copy.node == record.node and copy.generation == state.ghostGeneration
        and copy.width == state.width and copy.scale == state.scale
        and (not state.generic or copy.provider == state.provider and not copy.dirty)
    copy.node, copy.top, copy.parent = record.node, top, record.parent
    copy.left = Safety.Read(row, "GetLeft")
    copy.viewportTop = Safety.Read(state.scrollBox, "GetTop")
    copy.viewportLeft = Safety.Read(state.scrollBox, "GetLeft")
    copy.nativeAlpha = Safety.Read(row, "GetAlpha")
    copy.displayTop, copy.displayAlpha = nil, nil
    if cached then return end
    copy.nativeHeight = Safety.Read(row, "GetHeight")
    copy.generation, copy.width, copy.scale = state.ghostGeneration, state.width, state.scale
    copy.provider, copy.dirty = state.provider, false
    if state.model == "quest" then
        copy.questRegions = copy.questRegions or {}
        copy.questBase = Safety.Read(state.scrollBox, "GetEffectiveAlpha")
    end
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
    if copy and (record.state.model ~= "quest" or copy.node == record.node) then
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
    local travel = math.max(16, boundary - top + 16)
    copy.targetTop, copy.offset, copy.startAlpha, copy.boundary = top + travel, -travel, alpha, boundary
    copy.frame:ClearAllPoints()
    copy.frame:SetPoint("TOPLEFT", clip, "TOPLEFT", copy.left - copy.viewportLeft, copy.targetTop - boundary)
    copy.frame:SetAlpha(1)
    copy.move:SetOffset(0, copy.offset)
    copy.alpha:SetFromAlpha(0)
    copy.alpha:SetToAlpha(alpha)
    state.ghostViewport:Show()
    copy.frame:Show()
    if not copy.group:IsPlaying() then state.ghostActive = (state.ghostActive or 0) + 1 end
    state.activeGhosts[copy.node] = copy
    copy.group:Stop()
    copy.group:Play(true)
end

-- A reopened native row takes over the visible pose of its closing copy.
function Ghost.Take(state, node, resume)
    local copy = state.activeGhosts[node]
    if not copy then return end
    local top, alpha
    if resume then
        local remaining = copy.move:GetSmoothProgress()
        top = copy.targetTop + copy.offset * remaining
        alpha = copy.startAlpha * remaining
        if top > copy.boundary then
            -- The native row has no header clip. Reveal from below the header
            -- and keep only the opacity of the still visible portion.
            local height = copy.nativeHeight
            local visible = type(height) == "number" and height > 0 and math.max(0, 1 - (top - copy.boundary) / height) or 0
            top, alpha = copy.boundary, alpha * visible
        end
    end
    copy.group:Stop()
    Finished(copy.group)
    return top, alpha
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

local function PlayQuestClosures(state)
    if not state.ghostRows or not state.ghostGeneration then return end
    local previous = state.ghostGeneration - 1
    for copy in pairs(state.ghostRows) do
        if copy.node and (copy.generation or 0) == previous and not state.seenKeys[copy.node] then
            local parent = copy.parent
            for _ = 1, 16 do
                if not parent then break end
                if state.changes[parent] == true then
                    local record = copy.group.record
                    if Safety.CanCreateRegions(record.row) and not Safety.GetProtection(record.row) then
                        PlayCopy(state, record, copy, parent)
                    end
                    break
                end
                parent = state.parents[parent]
            end
        end
    end
end

function Ghost.AfterLayout(state, changed)
    if state.model == "quest" then
        if changed then PlayQuestClosures(state) end
        for index = 1, state.count do Ghost.Capture(state, state.rows[index]) end
        return
    end
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
