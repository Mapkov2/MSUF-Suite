local _, NS = ...

-- Discover a bounded visible native tree after show/layout/input, then keep
-- relative chrome rectangles for drag updates. No closed-window polling.
-- One walk of the root's children and grandchildren serves both roles: a
-- clear window's footprint and a dimmed window's material and layer, so a
-- focus change reuses it. Every walked node is observed: its own layout and
-- visibility changes invalidate the walk, added children fail the check.
local Chrome = {}
NS.WindowFocusChrome = Chrome
local Safety, Geometry = NS.Safety, NS.WindowFocusGeometry
local Contour = NS.WindowFocusContour
local observed = setmetatable({}, { __mode = "k" })
local locallyShown = setmetatable({}, { __mode = "k" })
-- Frames that already carry our layout hooks. Hooks cannot be removed, so a
-- released or re-observed frame never receives a second set.
local hooked = setmetatable({}, { __mode = "k" })
local MAX_NODES, MAX_DEPTH, MAX_EXTENTS, MAX_GUTTER = 384, 2, 16, 64
local ranks = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local Changed
local layoutScripts = { "OnShow", "OnHide", "OnSizeChanged" }
local layoutMethods = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetFrameLevel", "SetFrameStrata", "SetScale", "Raise" }
-- Blizzard caption buttons our caption faded (WindowControlChrome): no chrome.
local Hidden = function() return false end
function Chrome.SetHidden(predicate) Hidden = predicate end

local function LayoutChanged(frame)
    local state = observed[frame]
    if state and state.focusVisible and not state.chromeDirty and not state.static then
        state.chromeDirty = true
        Changed()
    end
end

-- Parent Show/Hide also delivers these scripts to locally shown children.
-- Only a change to the child's own visibility invalidates its geometry.
local function VisibilityChanged(frame)
    -- Released frames (a static window, see Chrome.Reset) keep inert hooks.
    if not observed[frame] then return end
    local shown = Safety.Read(frame, "IsShown")
    if type(shown) == "boolean" and locallyShown[frame] == shown then return end
    locallyShown[frame] = shown
    LayoutChanged(frame)
end

local function Observe(frame, state, visible)
    locallyShown[frame] = visible or Safety.Read(frame, "IsShown")
    if observed[frame] == state then return end
    if not hooked[frame] then
        hooked[frame] = true
        for index = 1, #layoutScripts do
            local script = layoutScripts[index]
            if Safety.Read(frame, "HasScript", script) == true then
                frame:HookScript(script, script == "OnSizeChanged" and LayoutChanged or VisibilityChanged)
            end
        end
        for _, method in ipairs(layoutMethods) do
            if Safety.HasMethod(frame, method) then hooksecurefunc(frame, method, LayoutChanged) end
        end
    end
    observed[frame] = state
end

-- Store the parents examined by discovery together with their public children.
-- Native child counts and parent identity can subsequently establish the same
-- membership without walking GetChildren or measuring any descendants.
local function Enqueue(state, parent, depth, ...)
    local topology, start = state.topology, state.topologyCount + 1
    local write = start + 1
    topology[start] = parent
    for index = 1, select("#", ...) do
        if state.queueCount >= MAX_NODES then state.partialTopology = true break end
        local child = select(index, ...)
        if Safety.Public(child) and child and not Safety.IsForbidden(child) then
            state.queueCount = state.queueCount + 1
            state.queue[state.queueCount], state.depths[state.queueCount] = child, depth
            write = write + 1
            topology[write] = child
        end
    end
    topology[start + 1], state.topologyCount = write - start - 1, write
end

local function SameChildOrder(graph, first, count, ...)
    if select("#", ...) ~= count then return false end
    for offset = 0, count - 1 do
        local child = select(offset + 1, ...)
        if not Safety.Public(child) or child ~= graph[first + offset] then return false end
    end
    return true
end

local function SameAnchors(state)
    local anchors, root = state.anchors, state.frame
    -- Most native panels have neither source of portrait/tutorial artwork.
    -- Both fields can be restricted, so resolve their identity only if public.
    local portrait, border = root.PortraitContainer, root.BorderFrame
    if Safety.Public(portrait) and Safety.Public(border) and portrait == nil and border == nil then
        return not (anchors.portrait or anchors.borderPortrait or anchors.tutorial)
    end
    state.probeAnchors = Contour.Anchors(root, state.probeAnchors or {})
    return anchors.portrait == state.probeAnchors.portrait and anchors.borderPortrait == state.probeAnchors.borderPortrait
        and anchors.tutorial == state.probeAnchors.tutorial
end

local function SameTopology(state, ordered)
    if not state.topologyCount or state.partialTopology or state.extentCount >= MAX_EXTENTS then return false end
    if state.layerAtDiscovery ~= state.rank or state.levelAtDiscovery ~= state.level then return false end
    for index = 1, state.tabScriptCount, 2 do
        local enabled = Safety.Read(state.tabScripts[index], "GetScript", "OnMouseDown") ~= nil
        if enabled ~= state.tabScripts[index + 1] then return false end
    end
    if state.topologyCount > 0 and not SameAnchors(state) then return false end
    local graph, index = state.topology, 1
    while index <= state.topologyCount do
        local parent, count = graph[index], graph[index + 1]
        index = index + 2
        if ordered and count > 0 then
            if not SameChildOrder(graph, index, count, Safety.Call(parent, "GetChildren")) then return false end
        else
            if Safety.Read(parent, "GetNumChildren") ~= count then return false end
            for slot = index, index + count - 1 do
                if Safety.Read(graph[slot], "GetParent") ~= parent then return false end
            end
        end
        index = index + count
    end
    return true
end

-- Reopen values come from getters discovery already consumed. No descendant
-- is queried by this cache between closing the root and its next visible use.
local function BeginReopenCache(state, uiScale)
    if not Safety.HasMethod(state.frame, "GetNumChildren") then return end
    local cache = state.reopenCache
    if not cache then
        cache = { shown = {}, layers = {}, rects = {}, rectIndex = {}, bounds = {} }
        state.reopenCache = cache
    else
        for key in pairs(cache.shown) do cache.shown[key] = nil end
        for key in pairs(cache.bounds) do cache.bounds[key] = nil end
        for i = 1, #cache.layers do cache.layers[i] = nil end
        for i = 1, #cache.rects, 7 do cache.rectIndex[cache.rects[i]] = nil end
        for i = 1, #cache.rects do cache.rects[i] = nil end
    end
    local rect = state.rect
    cache.left, cache.bottom, cache.width, cache.height = rect.left, rect.bottom, rect.width, rect.height
    cache.scale, cache.uiScale, cache.presentation = rect.unitScale, uiScale, state.presentation
    cache.hasArt = false
    cache.nativeRect = cache.nativeRect or {}
end

local function RememberRect(cache, frame, rect, nativeArt)
    if not cache then return end
    local data, index = cache.rects, #cache.rects
    cache.rectIndex[frame] = index + 1
    if nativeArt then cache.hasArt = true end
    data[index + 1], data[index + 2] = frame, nativeArt == true
    data[index + 3], data[index + 4] = rect and rect.left or false, rect and rect.bottom or false
    data[index + 5], data[index + 6] = rect and rect.width or false, rect and rect.height or false
    data[index + 7] = rect and rect.unitScale or false
end

-- Only the two shallowest levels can extend the shell: a deeper node is
-- rejected before any read, and its object type is the one Inspect read.
local function Exterior(state, frame, depth, kind, uiScale)
    if depth > 2 then return false end
    local art, circle, nativeArt = Contour.Artwork(state.anchors, frame)
    local frameTab = kind == "Frame" and Safety.Read(frame, "GetScript", "OnMouseDown") ~= nil
    if kind == "Frame" and not nativeArt then
        state.tabScripts = state.tabScripts or {}
        local last = state.tabScriptCount + 2
        state.tabScripts[last - 1], state.tabScripts[last], state.tabScriptCount = frame, frameTab, last
    end
    if kind ~= "Button" and kind ~= "CheckButton" and not frameTab and not nativeArt then return false end
    local rect, root = state.chromeScratch, state.rect
    local slot = state.extentCount + 1
    local saved = state.extents[slot]
    if not saved then saved = {} state.extents[slot] = saved end
    if nativeArt then
        saved.contour = Contour.Native(art, circle, saved.contour, rect, uiScale)
        if not saved.contour then RememberRect(state.reopenCache, frame, nil, true) return false end
    elseif not Geometry.Read(frame, rect, uiScale, nil, state.reopenCache and state.reopenCache.nativeRect) then
        RememberRect(state.reopenCache, frame, nil, false)
        return false
    end
    if state.reopenCache then RememberRect(state.reopenCache, frame, nativeArt and rect or state.reopenCache.nativeRect, nativeArt) end
    local right, top = rect.left + rect.width, rect.bottom + rect.height
    local rootRight, rootTop = root.left + root.width, root.bottom + root.height
    if rect.left >= root.left and right <= rootRight and rect.bottom >= root.bottom and top <= rootTop then return false end
    -- Native tabs and window controls stay beside their shell. Detached popup
    -- panels and scroll content are not part of this small chrome extension.
    local gutter = MAX_GUTTER * root.unitScale
    if rect.left < root.left - gutter or right > rootRight + gutter
        or rect.bottom < root.bottom - gutter or top > rootTop + gutter then return false end
    if frameTab then
        local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
        if type(width) ~= "number" or type(height) ~= "number" or width > 80 or height > 80 then return false end
    end
    if state.extentCount == MAX_EXTENTS then return true end
    if not nativeArt then saved.contour = Contour.Describe(frame, saved.contour) end
    state.extentCount = state.extentCount + 1
    saved.source = frame
    saved.left, saved.bottom = (rect.left - root.left) / root.width, (rect.bottom - root.bottom) / root.height
    saved.width, saved.height = rect.width / root.width, rect.height / root.height
    return true
end

local function Inside(cover, rect, gutter)
    return rect.left - gutter >= cover.left and rect.bottom - gutter >= cover.bottom
        and rect.left + rect.width + gutter <= cover.left + cover.width
        and rect.bottom + rect.height + gutter <= cover.bottom + cover.height
end

-- Blizzard computes the bounds of a frame with its descendants. If all of
-- them fit inside the bag, no slot can change its exterior cutout. Still
-- observe the exact current children for later movement and pooling.
local function EnqueueFootprint(state, parent, depth, uiScale, within, ...)
    local first = state.queueCount + 1
    Enqueue(state, parent, depth, ...)
    if not state.bagBounds or first > state.queueCount or not within and state.queueCount - first < 7 then return end
    if Safety.Read(parent, "IsIgnoringChildrenForBounds") ~= false then return end
    if not within then
        state.boundsScratch = state.boundsScratch or {}
        if not Geometry.Read(parent, state.boundsScratch, uiScale, "GetBoundsRect")
            or not Inside(state.rect, state.boundsScratch, 0) then return end
    end
    if state.reopenCache then state.reopenCache.bounds[parent] = within and "inherited" or "measured" end
    for index = first, state.queueCount do state.bagBounds[index] = true end
end

-- Children (depth 1) and grandchildren (depth 2) of the root. Their bounds
-- can extend the shell (tabs, portrait and tutorial art) and their layers can
-- rise above it. Each is observed, so its own layout change invalidates the
-- walk; deeper descendants stay inside the window and below the veil.
local function Inspect(state, frame, depth, uiScale, within)
    if frame == state.presentation or NS.WindowFocus.records[frame] or Hidden(frame) then return end
    local kind = Safety.Read(frame, "GetObjectType")
    if kind == "GameTooltip" then return end
    local shown = Safety.Read(frame, "IsVisible") == true
    if state.reopenCache then state.reopenCache.shown[frame] = shown end
    -- Even an ordinary hidden container can reveal a raised child or a tab.
    -- Its show hook requests a new pass before the veil is painted again.
    Observe(frame, state, shown)
    if not shown then return end
    local layer = Safety.Read(frame, "GetFrameStrata")
    local rank = ranks[layer]
    -- Frame level only orders widgets within a stratum.
    local level = rank and rank >= state.rank and Safety.Read(frame, "GetFrameLevel")
    if state.reopenCache then
        local layers = state.reopenCache.layers
        local index = #layers
        layers[index + 1], layers[index + 2], layers[index + 3] = frame, layer or false, level or false
    end
    local raised = type(level) == "number" and (rank > state.rank or level >= state.level)
    -- Bag slots inside the measured bag bounds cannot extend the shell.
    -- Native portrait and tutorial art always use their own bounds.
    local anchors = state.anchors
    local interior = within and frame ~= anchors.portrait and frame ~= anchors.borderPortrait
        and frame ~= anchors.tutorial
    if not interior and not state.presentation then Exterior(state, frame, depth, kind, uiScale) end
    if raised then
        if rank > state.chromeRank then state.chromeStrata, state.chromeRank, state.chromeLevel = layer, rank, level + 1
        elseif rank == state.chromeRank then state.chromeLevel = math.max(state.chromeLevel, level + 1) end
    end
    if depth >= MAX_DEPTH then return end
    if state.bagBounds then
        EnqueueFootprint(state, frame, depth + 1, uiScale, within, Safety.Call(frame, "GetChildren"))
    else
        Enqueue(state, frame, depth + 1, Safety.Call(frame, "GetChildren"))
    end
end

-- The flat membership pass already established that this node is readable.
-- Reuse that guard for its scalar bounds; none of these calls writes layout.
local function SameNodeRect(node, data, index)
    if type(node.GetRect) ~= "function" or type(node.GetEffectiveScale) ~= "function" then return false end
    local left, bottom, width, height = node:GetRect()
    local scale = node:GetEffectiveScale()
    if not (Safety.Public(left) and Safety.Public(bottom) and Safety.Public(width) and Safety.Public(height)
        and Safety.Public(scale)) then return false end
    if data[index + 2] == false then
        return type(left) ~= "number" or type(bottom) ~= "number" or type(width) ~= "number" or type(height) ~= "number"
            or type(scale) ~= "number" or width <= 0 or height <= 0
    end
    return left == data[index + 2] and bottom == data[index + 3] and width == data[index + 4]
        and height == data[index + 5] and scale == data[index + 6]
end

local function InteriorAtReopen(state, cache, uiScale)
    if state.extentCount ~= 0 or cache.hasArt or #cache.rects < 8 * 7
        or Safety.Read(state.frame, "IsIgnoringChildrenForBounds") ~= false then return false end
    local graph, cursor = state.topology, 1
    while cursor <= state.topologyCount do
        local parent, count = graph[cursor], graph[cursor + 1]
        if count > 0 and parent ~= state.frame and Safety.Read(parent, "IsIgnoringChildrenForBounds") ~= false then return false end
        cursor = cursor + count + 2
    end
    state.boundsScratch = state.boundsScratch or {}
    return Geometry.Read(state.frame, state.boundsScratch, uiScale, "GetBoundsRect") and Inside(state.rect, state.boundsScratch, 0)
end

local function SameReopenNodes(state, cache, uiScale)
    local interior = InteriorAtReopen(state, cache, uiScale)
    local graph, cursor = state.topology, 1
    while cursor <= state.topologyCount do
        local count = graph[cursor + 1]
        cursor = cursor + 2
        for index = cursor, cursor + count - 1 do
            local node = graph[index]
            local shown = cache.shown[node]
            if Safety.IsForbidden(node) then return false end
            if shown ~= "interior" then
                local excluded = node == state.presentation or NS.WindowFocus.records[node] or Hidden(node)
                if shown == nil then
                    if not excluded and Safety.Read(node, "GetObjectType") ~= "GameTooltip" then return false end
                elseif excluded or type(node.IsVisible) ~= "function" then return false
                else
                    local visible = node:IsVisible()
                    if not Safety.Public(visible) or shown ~= (visible == true) then return false end
                end
            end
            if observed[node] == state then locallyShown[node] = shown == true or Safety.Read(node, "IsShown") end
            local pos = cache.rectIndex[node]
            if not interior and pos and not cache.rects[pos + 1] and not SameNodeRect(node, cache.rects, pos) then return false end
        end
        cursor = cursor + count
    end
    return true
end

local function SameReopenArt(state, cache, uiScale)
    local data, rect = cache.rects, state.chromeScratch
    for index = 1, #data, 7 do
        if data[index + 1] then
            local frame = data[index]
            local art, mask = Contour.Artwork(state.anchors, frame)
            local saved
            for slot = 1, state.extentCount do
                if state.extents[slot].source == frame then saved = state.extents[slot] break end
            end
            cache.art = cache.art or {}
            local contour = Contour.Native(art, mask, saved and saved.contour or cache.art, rect, uiScale)
            if saved then saved.contour = contour end
            if (contour ~= nil) ~= (data[index + 2] ~= false) then return false end
            if contour and (rect.left ~= data[index + 2] or rect.bottom ~= data[index + 3]
                or rect.width ~= data[index + 4] or rect.height ~= data[index + 5] or rect.unitScale ~= data[index + 6]) then return false end
        end
    end
    return true
end

-- A clear window contributes only its silhouette. Its native layering matters
-- when it is first dimmed again, even if a different window took focus by Show.
local function SameReopenLayers(state, cache)
    for i = 1, #cache.layers, 3 do
        local layer = cache.layers[i + 1]
        if (Safety.Read(cache.layers[i], "GetFrameStrata") or false) ~= layer then return false end
        if layer and ranks[layer] and ranks[layer] >= state.rank
            and (Safety.Read(cache.layers[i], "GetFrameLevel") or false) ~= cache.layers[i + 2] then return false end
    end
    return true
end

local function SameReopen(state, footprintOnly, uiScale)
    local cache, root = state.reopenCache, state.rect
    if not cache or cache.presentation ~= state.presentation or cache.uiScale ~= uiScale or cache.scale ~= root.unitScale
        or cache.left ~= root.left or cache.bottom ~= root.bottom or cache.width ~= root.width or cache.height ~= root.height
        or not SameTopology(state, true) or not SameReopenNodes(state, cache, uiScale) then return false end
    for parent, mode in pairs(cache.bounds) do
        if Safety.Read(parent, "IsIgnoringChildrenForBounds") ~= false then return false end
        if mode == "measured" and (not Geometry.Read(parent, state.boundsScratch, uiScale, "GetBoundsRect")
            or not Inside(root, state.boundsScratch, 0)) then return false end
    end
    state.checkReopenLayers = footprintOnly and #cache.layers > 0
    if not footprintOnly and not SameReopenLayers(state, cache) then return false end
    if cache.hasArt and not SameReopenArt(state, cache, uiScale) then return false end
    for slot = 1, state.extentCount do
        local extent = state.extents[slot]
        local _, _, nativeArt = Contour.Artwork(state.anchors, extent.source)
        if not nativeArt then extent.contour = Contour.Describe(extent.source, extent.contour) end
    end
    return true
end

local function Discover(state, uiScale)
    BeginReopenCache(state, uiScale)
    state.checkReopenLayers = false
    state.chromeDirty, state.verifyTopology = false, false
    state.topology = state.topology or {}
    local previousCount = state.topologyCount or 0
    if state.tabScripts then
        for i = 1, state.tabScriptCount do state.tabScripts[i] = nil end
    end
    state.tabScriptCount = 0
    state.layerAtDiscovery, state.levelAtDiscovery = state.rank, state.level
    state.topologyCount, state.partialTopology = 0, false
    state.queue, state.depths = state.queue or {}, state.depths or {}
    state.extents, state.chromeScratch = state.extents or {}, state.chromeScratch or {}
    state.extentCount, state.queueCount = 0, 0
    state.anchors = Contour.Anchors(state.frame, state.anchors or {})
    state.chromeStrata, state.chromeRank, state.chromeLevel = state.strata, state.rank, state.level
    -- Bag slots are pooled children of the bag root. One bounds read can show
    -- that none of them reaches outside the shell.
    if state.frame == ContainerFrameCombinedBags or state.frame == ContainerFrame6 then
        state.bagBounds = state.bagBounds or {}
        EnqueueFootprint(state, state.frame, 1, uiScale, false, Safety.Call(state.frame, "GetChildren"))
    else
        state.bagBounds = nil
        Enqueue(state, state.frame, 1, Safety.Call(state.frame, "GetChildren"))
    end
    local index = 1
    while index <= state.queueCount do
        local within = state.bagBounds and state.bagBounds[index]
        if within then state.bagBounds[index] = nil end
        Inspect(state, state.queue[index], state.depths[index], uiScale, within)
        state.queue[index] = false
        index = index + 1
    end
    for i = state.topologyCount + 1, previousCount do state.topology[i] = nil end
end

-- A window that turned static (WindowFocus.Track) drops its walk. Its former
-- descendants keep inert hooks; a later walk reuses them (see Observe).
function Chrome.Reset(state)
    for frame, owner in pairs(observed) do
        if owner == state then observed[frame], locallyShown[frame] = nil, nil end
    end
    state.extents, state.reopenCache, state.topologyCount, state.extentCount = nil, nil, nil, 0
    state.checkAfterShow, state.verifyTopology, state.checkReopenLayers = false, false, false
    state.chromeDirty = true
end

local function PlainRoot(state)
    state.extentCount = 0
    state.chromeStrata, state.chromeRank, state.chromeLevel = state.strata, state.rank, state.level
end

-- footprintOnly: the window is clear and only cuts its footprint out of
-- other veils. One walk serves both roles, so a focus change reuses it.
function Chrome.Update(state, footprintOnly, uiScale)
    if state.static then
        -- Bags paints this shell (SuiteOwnership): its plain root rectangle is
        -- the whole window, so nothing below it is walked or observed.
        state.chromeDirty, state.verifyTopology = false, false
        state.checkAfterShow, state.checkReopenLayers = false, false
        PlainRoot(state)
    else
        if state.checkAfterShow then
            state.checkAfterShow, state.chromeDirty, state.verifyTopology = false, false, false
            if not SameReopen(state, footprintOnly, uiScale) then state.chromeDirty = true end
        end
        if state.checkReopenLayers and not footprintOnly then
            state.checkReopenLayers = false
            if not state.chromeDirty and not SameReopenLayers(state, state.reopenCache) then state.chromeDirty = true end
        end
        if state.verifyTopology and not state.chromeDirty then
            state.verifyTopology = false
            if not SameTopology(state) then state.chromeDirty = true end
        end
        if state.chromeDirty or not state.extents then Discover(state, uiScale) end
    end
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

-- A dimmed window's material bounds include every accepted native tab and
-- portrait. Only the band outside the clear root can require its child tree.
local function Cutout(state, windows, uiScale)
    local root = state.rect
    if not state.presentation then
        local left, bottom = root.left, root.bottom
        local right, top = left + root.width, bottom + root.height
        local gutter = MAX_GUTTER * root.unitScale
        for _, other in pairs(windows) do
            if other.readable and not other.keepClear and not other.covered then
                local rect = other.materialRect
                local otherRight, otherTop = rect.left + rect.width, rect.bottom + rect.height
                if otherRight > left - gutter and rect.left < right + gutter
                    and otherTop > bottom - gutter and rect.bottom < top + gutter
                    and (rect.left < left or otherRight > right or rect.bottom < bottom or otherTop > top) then
                    Chrome.Update(state, true, uiScale)
                    return
                end
            end
        end
    end
    state.footprints = state.footprints or {}
    state.footprints[1], state.footprintCount = root, 1
    -- Revalidate possible new or reparented children only when a cutout is needed.
    state.verifyTopology = true
end

local function UpdateDimmed(state, windows, uiScale)
    local cover
    local gutter = state.presentation and 0 or MAX_GUTTER * state.rect.unitScale
    for _, clear in pairs(windows) do
        if clear.keepClear and clear.readable and Inside(clear.rect, state.rect, 0) then
            if Inside(clear.rect, state.rect, gutter) then
                -- New children can appear while no veil is drawn here.
                state.covered, state.verifyTopology = true, true
                return
            end
            cover = clear.rect
        end
    end
    Chrome.Update(state, false, uiScale)
    state.covered = cover and Inside(cover, state.materialRect, 0)
    if not state.covered then NS.WindowFocusLayers.Prepare(state) end
end

function Chrome.UpdateWindows(windows, needsVeil, uiScale)
    for _, state in pairs(windows) do
        state.covered = nil
        if not needsVeil or not state.readable then
            state.verifyTopology = true
        elseif not state.keepClear then
            UpdateDimmed(state, windows, uiScale)
        end
    end
    if not needsVeil then return end
    for _, state in pairs(windows) do
        if state.keepClear then Cutout(state, windows, uiScale) end
    end
end

function Chrome.Initialize(changed)
    Changed = changed
end
