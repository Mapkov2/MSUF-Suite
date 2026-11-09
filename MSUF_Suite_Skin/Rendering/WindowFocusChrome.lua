local _, NS = ...

-- Discover a bounded visible native tree after show/layout/input, then keep
-- relative chrome rectangles for drag updates. No closed-window polling.
local Chrome = {}
NS.WindowFocusChrome = Chrome
local Safety, Geometry = NS.Safety, NS.WindowFocusGeometry
local Contour = NS.WindowFocusContour
local observed = setmetatable({}, { __mode = "k" })
local MAX_NODES, MAX_DEPTH, MAX_EXTENTS = 384, 5, 16
local ranks = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local Changed

local function LayoutChanged(frame)
    local state = observed[frame]
    if state and state.focusVisible then
        state.chromeDirty = true
        Changed()
    end
end

local function Observe(frame, state)
    if observed[frame] == state then return end
    if not observed[frame] then
        frame:HookScript("OnShow", LayoutChanged)
        frame:HookScript("OnHide", LayoutChanged)
        frame:HookScript("OnSizeChanged", LayoutChanged)
        for _, method in ipairs({ "SetPoint", "SetFrameLevel", "SetFrameStrata", "SetScale" }) do
            if Safety.HasMethod(frame, method) then hooksecurefunc(frame, method, LayoutChanged) end
        end
    end
    observed[frame] = state
end

local function Enqueue(state, depth, ...)
    for index = 1, select("#", ...) do
        if state.queueCount >= MAX_NODES then return end
        local child = select(index, ...)
        if Safety.Public(child) and child and not Safety.IsForbidden(child) then
            state.queueCount = state.queueCount + 1
            state.queue[state.queueCount], state.depths[state.queueCount] = child, depth
        end
    end
end

local function Exterior(state, frame, depth)
    local art, circle, nativeArt = Contour.Artwork(state.frame, frame)
    local kind = Safety.Read(frame, "GetObjectType")
    local frameTab = kind == "Frame" and Safety.Read(frame, "GetScript", "OnMouseDown") ~= nil
    if depth > 2 or (kind ~= "Button" and kind ~= "CheckButton" and not frameTab and not nativeArt) then return false end
    local rect, root = state.chromeScratch, state.rect
    local slot = state.extentCount + 1
    local saved = state.extents[slot]
    if not saved then saved = {} state.extents[slot] = saved end
    if nativeArt then
        saved.contour = Contour.Native(art, circle, saved.contour, rect)
        if not saved.contour then return false end
    else
        if not Geometry.Read(frame, rect) then return false end
        saved.contour = Contour.Describe(frame, saved.contour)
    end
    if frameTab then
        local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
        if type(width) ~= "number" or type(height) ~= "number" or width > 80 or height > 80 then return false end
    end
    local right, top = rect.left + rect.width, rect.bottom + rect.height
    local rootRight, rootTop = root.left + root.width, root.bottom + root.height
    if rect.left >= root.left and right <= rootRight and rect.bottom >= root.bottom and top <= rootTop then return false end
    -- Native tabs and window controls stay beside their shell. Detached popup
    -- panels and scroll content are not part of this small chrome extension.
    local gutter = 64 * root.unitScale
    if rect.left < root.left - gutter or right > rootRight + gutter
        or rect.bottom < root.bottom - gutter or top > rootTop + gutter then return false end
    if state.extentCount == MAX_EXTENTS then return true end
    state.extentCount = state.extentCount + 1
    saved.left, saved.bottom = (rect.left - root.left) / root.width, (rect.bottom - root.bottom) / root.height
    saved.width, saved.height = rect.width / root.width, rect.height / root.height
    return true
end

local function Inspect(state, frame, depth)
    if Safety.Read(frame, "GetObjectType") == "GameTooltip" then return end
    if frame == state.presentation or NS.WindowFocus.records[frame] then return end
    local layer, level = Safety.Read(frame, "GetFrameStrata"), Safety.Read(frame, "GetFrameLevel")
    local rank = ranks[layer]
    local raised = rank and type(level) == "number" and (rank > state.rank or rank == state.rank and level >= state.level)
    local shown = Safety.Read(frame, "IsVisible") == true
    local exterior = shown and not state.presentation and Exterior(state, frame, depth)
    if depth <= 2 or raised or exterior then Observe(frame, state) end
    if shown and raised then
        if rank > state.chromeRank then state.chromeStrata, state.chromeRank, state.chromeLevel = layer, rank, level + 1
        elseif rank == state.chromeRank then state.chromeLevel = math.max(state.chromeLevel, level + 1) end
    end
    if shown and depth < MAX_DEPTH then Enqueue(state, depth + 1, Safety.Call(frame, "GetChildren")) end
end

local function Discover(state)
    state.chromeDirty = false
    state.queue, state.depths = state.queue or {}, state.depths or {}
    state.extents, state.chromeScratch = state.extents or {}, state.chromeScratch or {}
    state.extentCount, state.queueCount = 0, 0
    state.chromeStrata, state.chromeRank, state.chromeLevel = state.strata, state.rank, state.level
    Enqueue(state, 1, Safety.Call(state.frame, "GetChildren"))
    local index = 1
    while index <= state.queueCount do
        Inspect(state, state.queue[index], state.depths[index])
        state.queue[index], state.depths[index] = nil, nil
        index = index + 1
    end
end

function Chrome.Update(state)
    if state.chromeDirty or not state.extents then Discover(state) end
    if state.chromeRank > state.rank then state.strata, state.rank, state.level = state.chromeStrata, state.chromeRank, state.chromeLevel
    elseif state.chromeRank == state.rank then state.level = math.max(state.level, state.chromeLevel) end
    local root = state.rect
    root.contour = Contour.Describe(state.frame, root.contour)
    state.footprints, state.materialRect = state.footprints or {}, state.materialRect or {}
    state.footprints[1] = root
    local left, bottom, right, top = root.left, root.bottom, root.left + root.width, root.bottom + root.height
    for index = 1, state.extentCount do
        local saved, rect = state.extents[index], state.footprints[index + 1]
        if not rect then rect = {} state.footprints[index + 1] = rect end
        rect.left, rect.bottom = root.left + saved.left * root.width, root.bottom + saved.bottom * root.height
        rect.width, rect.height = saved.width * root.width, saved.height * root.height
        rect.unitScale, rect.contour = root.unitScale, saved.contour
        left, bottom = math.min(left, rect.left), math.min(bottom, rect.bottom)
        right, top = math.max(right, rect.left + rect.width), math.max(top, rect.bottom + rect.height)
    end
    state.footprintCount = state.extentCount + 1
    local material = state.materialRect
    material.left, material.bottom, material.width, material.height = left, bottom, right - left, top - bottom
end

function Chrome.Initialize(changed)
    Changed = changed
end
