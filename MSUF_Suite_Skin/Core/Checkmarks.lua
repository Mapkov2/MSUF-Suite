local _, NS = ...

-- Recolor only verified Blizzard checkbox, menu-selection, dropdown-stepper
-- and close-button assets, and replace the exact Settings category highlight
-- with owned button states. Blizzard uses the same fields for unrelated
-- semantic art, so blanket texture passes remain unsafe. Ownership is
-- external, weak and reversible. Dropdown popups, the Settings panel and
-- legacy dropdown lists are tracked in CheckmarksMenus.lua.
local Checkmarks = {
    states = setmetatable({}, { __mode = "k" }),
    buttons = setmetatable({}, { __mode = "k" }),
    buttonOwners = setmetatable({}, { __mode = "k" }),
    dropdowns = setmetatable({}, { __mode = "k" }),
    settingsCategoryLists = setmetatable({}, { __mode = "k" }),
    owners = {},
    count = 0,
    legacyRegistered = false,
}
NS.Checkmarks = Checkmarks

local Safety = NS.Safety

local acceptedAtlases = {
    ["checkmark-minimal"] = "checkmark",
    ["checkmark-minimal-disabled"] = "checkmark",
    ["common-dropdown-icon-checkmark-yellow"] = "checkmark",
    ["common-dropdown-icon-radialtick-yellow"] = "checkmark",
    ["common-dropdown-icon-back"] = "blizzardArrow",
    ["common-dropdown-icon-back-disabled"] = "blizzardArrow",
    ["common-dropdown-icon-next"] = "blizzardArrow",
    ["common-dropdown-icon-next-disabled"] = "blizzardArrow",
    ["common-button-dropdown-open"] = "blizzardExpand",
    ["common-button-dropdown-openpressed"] = "blizzardExpandPressed",
    ["common-button-dropdown-closed"] = "blizzardExpand",
    ["common-button-dropdown-closedpressed"] = "blizzardExpandPressed",
    ["redbutton-exit"] = "blizzardClose",
    ["redbutton-exit-pressed"] = "blizzardClosePressed",
    ["redbutton-exit-disabled"] = "blizzardCloseDisabled",
    ["redbutton-highlight"] = "blizzardCloseHover",
    ["redbutton-expand"] = "blizzardExpand",
    ["redbutton-expand-pressed"] = "blizzardExpandPressed",
    ["redbutton-expand-disabled"] = "disabled",
    ["redbutton-condense"] = "blizzardExpand",
    ["redbutton-condense-pressed"] = "blizzardExpandPressed",
    ["redbutton-condense-disabled"] = "disabled",
    ["redbutton-minicondense"] = "blizzardExpand",
    ["redbutton-minicondense-pressed"] = "blizzardExpandPressed",
    ["redbutton-minicondense-disabled"] = "disabled",
}

-- Exact UIButtonTemplate art kits present in upstream/live. These atlases
-- combine the glyph and native red button body, so preserving the original
-- texture as a desaturated alpha/luminance mask is the only lossless way to
-- remove the red while retaining Refresh/Delete/Cart/Visibility semantics.
local redButtonArtKits = {
    ["128-redbutton"] = true,
    ["128-redbutton-refresh"] = true,
    ["128-redbutton-exit"] = true,
    ["128-redbutton-arrowdown"] = true,
    ["128-redbutton-arrowupglow"] = true,
    ["128-redbutton-delete"] = true,
    ["128-redbutton-shoppingcart"] = true,
    ["128-redbutton-minus"] = true,
    ["128-redbutton-plus"] = true,
    ["128-redbutton-visibilityon"] = true,
    ["128-redbutton-visibilityoff"] = true,
    ["128-redbutton-cart-add"] = true,
    ["128-redbutton-cart-minus"] = true,
}

-- Expand the finite allowlist once. Always inspect the live atlas below:
-- pooled buttons can change art kits between two visits.
for kit in pairs(redButtonArtKits) do
    local close = kit == "128-redbutton-exit"
    acceptedAtlases[kit] = close and "blizzardClose" or "blizzardExpand"
    acceptedAtlases[kit .. "-pressed"] = close and "blizzardClosePressed" or "blizzardExpandPressed"
    acceptedAtlases[kit .. "-disabled"] = close and "blizzardCloseDisabled" or "disabled"
    acceptedAtlases[kit .. "-highlight"] = close and "blizzardCloseHover" or "blizzardExpandHover"
end

local texturePathGetters = { "GetTextureFilePath", "GetTexture" }
-- The sixth getter is the highlight: it takes the hover role of its button.
-- TrackButton reads the third, the normal texture, once before the loop.
local NORMAL_GETTER_INDEX, HIGHLIGHT_GETTER_INDEX = 3, 6
local buttonTextureGetters = {
    "GetCheckedTexture", "GetDisabledCheckedTexture", "GetNormalTexture",
    "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture",
}
local buttonTextureFields = { "CheckedTexture", "DisabledCheckedTexture", "leftTexture2", "Icon" }

local acceptedPaths = {
    ["interface\\buttons\\ui-checkbox-check"] = "checkmark",
    ["interface\\buttons\\ui-checkbox-check-disabled"] = "checkmark",
    ["interface\\common\\ui-dropdownradiochecks"] = "checkmark",
    ["interface\\buttons\\ui-plusbutton-up"] = "blizzardExpand",
    ["interface\\buttons\\ui-plusbutton-down"] = "blizzardExpandPressed",
    ["interface\\buttons\\ui-plusbutton-hilight"] = "blizzardExpandHover",
    ["interface\\buttons\\ui-minusbutton-up"] = "blizzardExpand",
    ["interface\\buttons\\ui-minusbutton-down"] = "blizzardExpandPressed",
    ["common-button-dropdown-open"] = "blizzardExpand",
    ["common-button-dropdown-openpressed"] = "blizzardExpandPressed",
    ["common-button-dropdown-closed"] = "blizzardExpand",
    ["common-button-dropdown-closedpressed"] = "blizzardExpandPressed",
}

-- A texture still shows our tint within COLOR_OWN; its native color is
-- classified within COLOR_NATIVE.
local ColorMatches = Safety.ColorMatches
local COLOR_OWN, COLOR_NATIVE = Safety.COLOR_OWN, Safety.COLOR_NATIVE

-- Vertex color as plain numbers; nil when missing or secret.
local function ReadVertex(texture)
    return Safety.ReadColor(texture, "GetVertexColor")
end

local function ReadDesaturated(texture)
    return Safety.Read(texture, "IsDesaturated") == true or nil
end

-- The first result of a getter, or nil.
local function Getter(object, name)
    return (Safety.Call(object, name))
end

-- Settings rows and pooled buttons show the same few atlases and files on
-- every visit. Each distinct name is lowered (and each path matched) once;
-- a cache is dropped when it reaches LOOKUP_CACHE_LIMIT names.
local LOOKUP_CACHE_LIMIT = 512
local lowerAtlases = { values = {}, count = 0 }
local pathRoles = { values = {}, count = 0 }

local function Remember(cache, key, value)
    if cache.count >= LOOKUP_CACHE_LIMIT then
        for oldKey in pairs(cache.values) do cache.values[oldKey] = nil end
        cache.count = 0
    end
    cache.values[key] = value
    cache.count = cache.count + 1
    return value
end

local function AtlasKey(texture)
    local atlas = Safety.Read(texture, "GetAtlas")
    if type(atlas) ~= "string" then return nil end
    return lowerAtlases.values[atlas] or Remember(lowerAtlases, atlas, atlas:lower())
end

-- The color role of a texture file path, or false.
local function PathRole(path)
    local role = pathRoles.values[path]
    if role == nil then
        local key = path:gsub("/", "\\"):lower():gsub("%.blp$", ""):gsub("%.tga$", "")
        role = Remember(pathRoles, path, acceptedPaths[key] or false)
    end
    return role
end

-- The first result of object:name() for an object already checked to be a
-- readable table (not forbidden): Safety.Call without its check per call.
-- TrackButton and AssetRole read several getters of one checked object.
local function CheckedCall(object, name)
    local method = object[name]
    if type(method) ~= "function" then return nil end
    return (method(object))
end

-- A string getter of a texture AssetRole has checked; nil when missing,
-- secret or not a string.
local function ReadString(texture, name)
    local value = CheckedCall(texture, name)
    if Safety.Public(value) and type(value) == "string" then return value end
    return nil
end

-- The texture is checked once, not once per getter as Safety.Read would.
local function AssetRole(texture)
    if not texture or type(texture) ~= "table" or Safety.IsForbidden(texture) then return false end
    local atlas = ReadString(texture, "GetAtlas")
    if atlas then
        atlas = lowerAtlases.values[atlas] or Remember(lowerAtlases, atlas, atlas:lower())
        if acceptedAtlases[atlas] then return acceptedAtlases[atlas] end
    end
    for index = 1, #texturePathGetters do
        local path = ReadString(texture, texturePathGetters[index])
        if path then
            local role = PathRole(path)
            if role then return role end
        end
    end
    return false
end

function Checkmarks.IsRedButtonArtKit(artKit)
    return type(artKit) == "string" and redButtonArtKits[artKit:lower()] == true
end

local function IsCloseRole(role)
    return role == "blizzardClose" or role == "blizzardClosePressed"
        or role == "blizzardCloseHover" or role == "blizzardCloseDisabled"
end

local function OwnerSet(owner)
    if owner == nil then return nil end
    local set = Checkmarks.owners[owner]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        Checkmarks.owners[owner] = set
    end
    return set
end

local function BindTexture(texture, state, owner)
    if state.owner ~= nil and state.owner ~= owner then
        local oldSet = Checkmarks.owners[state.owner]
        if oldSet then oldSet[texture] = nil end
    end
    state.owner = owner
    local set = OwnerSet(owner)
    if set then set[texture] = true end
end

local function ApplyTexture(texture, owner, forcedRole)
    if not texture then return false end
    local colorRole = forcedRole or AssetRole(texture)
    if not colorRole or type(texture.SetVertexColor) ~= "function" then return false end
    local r, g, b, a = ReadVertex(texture)
    if not r then return false end
    local state = Checkmarks.states[texture]
    if state and not ColorMatches(state.applied, r, g, b, a, COLOR_OWN)
        and not ColorMatches(state.original, r, g, b, a, COLOR_NATIVE) then
        return false
    end
    if not state then
        state = {
            original = { r, g, b, a },
            originalDesaturated = ReadDesaturated(texture),
            colorRole = colorRole,
        }
        Checkmarks.states[texture] = state
        Checkmarks.count = Checkmarks.count + 1
    end
    state.colorRole = colorRole
    BindTexture(texture, state, owner)

    -- Blizzard's selected atlases are yellow. Desaturating first turns their
    -- alpha/luminance into a neutral mask, allowing the full RGB token range.
    local desaturates = type(texture.SetDesaturated) == "function"
    if desaturates then texture:SetDesaturated(true) end
    local applied = state.applied or {}
    local tokenR, tokenG, tokenB, tokenA = NS.Theme.GetColor(state.colorRole)
    applied[1], applied[2], applied[3] = tokenR, tokenG, tokenB
    applied[4] = tokenA * (state.original[4] or 1)
    texture:SetVertexColor(applied[1], applied[2], applied[3], applied[4])
    state.applied = applied
    state.appliedDesaturated = desaturates or nil
    return true
end

local function RestoreTexture(texture, state)
    state = state or Checkmarks.states[texture]
    if not state then return false end
    local r, g, b, a = ReadVertex(texture)
    if r and ColorMatches(state.applied, r, g, b, a, COLOR_OWN) then
        if state.appliedDesaturated ~= nil and type(texture.SetDesaturated) == "function"
            and ReadDesaturated(texture) == state.appliedDesaturated then
            texture:SetDesaturated(state.originalDesaturated == true)
        end
        local original = state.original
        texture:SetVertexColor(original[1], original[2], original[3], original[4])
    end
    local set = state.owner ~= nil and Checkmarks.owners[state.owner] or nil
    if set then set[texture] = nil end
    Checkmarks.states[texture] = nil
    Checkmarks.count = math.max(0, Checkmarks.count - 1)
    return true
end

-- Dedicated adapters may bind an exact, source-verified Blizzard texture to a
-- theme role without adding that asset to the global atlas inventory. This is
-- intentionally texture-scoped: callers remain responsible for proving that
-- the region is decorative rather than semantic content.
function Checkmarks.TrackTexture(texture, owner, colorRole)
    if not NS.DB or not NS.DB.enabled or NS.IsCombatLocked()
        or type(colorRole) ~= "string" then
        return false
    end
    local applied = ApplyTexture(texture, owner, colorRole)
    -- The theme pass (Checkmarks.Apply) repaints it with this role: the
    -- allowlist does not know the asset.
    if applied then Checkmarks.states[texture].boundRole = colorRole end
    return applied
end

function Checkmarks.UntrackTexture(texture, owner)
    local state = texture and Checkmarks.states[texture]
    if not state or (owner ~= nil and state.owner ~= owner) then return false end
    return RestoreTexture(texture, state)
end

-- Window actions are deliberately stricter than the color allowlist. A lone
-- plus/minus texture or a suggestive field name is not enough: Blizzard uses
-- both for steppers, lists and semantic actions. Only complete known
-- Normal/Pushed atlas pairs receive an action meaning.
local windowActionPairs = {
    ["redbutton-exit"] = {
        pushed = "redbutton-exit-pressed", disabled = "redbutton-exit-disabled",
        kind = "close",
    },
    ["128-redbutton-exit"] = {
        pushed = "128-redbutton-exit-pressed", disabled = "128-redbutton-exit-disabled",
        kind = "close",
    },
    ["redbutton-expand"] = {
        pushed = "redbutton-expand-pressed", disabled = "redbutton-expand-disabled",
        kind = "maximize",
    },
    ["redbutton-condense"] = {
        pushed = "redbutton-condense-pressed", disabled = "redbutton-condense-disabled",
        kind = "minimize",
    },
    ["redbutton-minicondense"] = {
        pushed = "redbutton-minicondense-pressed", disabled = "redbutton-minicondense-disabled",
        kind = "minimize",
    },
    ["128-redbutton-plus"] = {
        pushed = "128-redbutton-plus-pressed", disabled = "128-redbutton-plus-disabled",
        kind = "add",
    },
    ["128-redbutton-minus"] = {
        pushed = "128-redbutton-minus-pressed", disabled = "128-redbutton-minus-disabled",
        kind = "remove",
    },
}

-- get reads the button's state textures (Getter, or ButtonGetter below).
-- normal: the button's normal texture, which the caller has already read.
local function DetectAction(button, get, normal)
    normal = AtlasKey(normal)
    local definition = normal and windowActionPairs[normal] or nil
    if not definition
        or AtlasKey(get(button, "GetPushedTexture")) ~= definition.pushed then
        return nil
    end
    local disabled = get(button, "GetDisabledTexture")
    if disabled and AtlasKey(disabled) ~= definition.disabled then return nil end
    return definition.kind
end

function Checkmarks.DetectWindowAction(button)
    if not button then return nil end
    return DetectAction(button, Getter, Getter(button, "GetNormalTexture"))
end

function Checkmarks.GetWindowAction(button)
    local detected = Checkmarks.DetectWindowAction(button)
    if detected then return detected end
    if NS.WindowActionSkin.HasOwnedStates(button) then
        return NS.WindowActionSkin.GetKind(button)
    end
    return nil
end

local function Field(object, name)
    return Safety.Field(object, name) or nil
end

local function CanTrack(button)
    return button and Safety.CanDecorate(button, true)
end

-- Getters of a button CanTrack accepted (a table that is not forbidden).
-- TrackButton reads its fields directly for the same reason.
local ButtonGetter = CheckedCall

function Checkmarks.TrackButton(button, owner)
    if not NS.DB or not NS.DB.enabled or NS.IsCombatLocked() or not CanTrack(button) then
        return false
    end
    local changed = false
    local recognized = false
    local normal = ButtonGetter(button, "GetNormalTexture")
    local actionKind = DetectAction(button, ButtonGetter, normal)
    if not actionKind and NS.WindowActionSkin.HasOwnedStates(button) then
        actionKind = NS.WindowActionSkin.GetKind(button)
    end
    local normalRole = AssetRole(normal)
    local highlightRole
    if normalRole == "blizzardExpand" then
        highlightRole = "blizzardExpandHover"
    elseif IsCloseRole(normalRole) then
        highlightRole = "blizzardCloseHover"
    end
    for index = 1, #buttonTextureGetters do
        local texture, role = normal, normalRole
        if index ~= NORMAL_GETTER_INDEX then
            texture = ButtonGetter(button, buttonTextureGetters[index])
            role = (index == HIGHLIGHT_GETTER_INDEX and highlightRole) or AssetRole(texture)
        end
        if role then
            recognized = true
            changed = ApplyTexture(texture, owner, role) or changed
        end
    end
    for index = 1, #buttonTextureFields do
        local texture = button[buttonTextureFields[index]]
        local role = AssetRole(texture)
        if role then
            recognized = true
            changed = ApplyTexture(texture, owner, role) or changed
        end
    end
    if actionKind then
        local action = NS.WindowActionSkin.Track(button, owner, actionKind)
        recognized = action ~= nil or recognized
        changed = action ~= nil or changed
    elseif NS.WindowActionSkin.IsApplied(button)
        and not NS.WindowActionSkin.HasOwnedStates(button) then
        -- A dynamic UIButton art kit changed to a non-action family. Keep the
        -- new semantic art and drop only our previous action layer.
        NS.WindowActionSkin.Disable(button, owner)
    end
    if recognized then
        Checkmarks.buttons[button] = true
        Checkmarks.buttonOwners[button] = owner
    end
    return changed
end

local function RestoreOwnedTexture(texture, owner)
    local state = texture and Checkmarks.states[texture]
    if state and (owner == nil or state.owner == owner) then
        return RestoreTexture(texture, state)
    end
    return false
end

function Checkmarks.UntrackButton(button, owner)
    if not button then return false end
    NS.WindowActionSkin.Disable(button, owner)
    -- RestoreTexture drops each state, so a texture reached through two
    -- getters is restored once.
    local restored = false
    for index = 1, #buttonTextureGetters do
        restored = RestoreOwnedTexture(Getter(button, buttonTextureGetters[index]), owner) or restored
    end
    for index = 1, #buttonTextureFields do
        restored = RestoreOwnedTexture(Field(button, buttonTextureFields[index]), owner) or restored
    end
    Checkmarks.buttons[button] = nil
    Checkmarks.buttonOwners[button] = nil
    return restored
end

local function TrackSingleFrame(frame, owner, buttonTracked)
    if not frame then return false end
    local changed = not buttonTracked and Checkmarks.TrackButton(frame, owner) or false
    changed = ApplyTexture(Field(frame, "Check"), owner) or changed
    local name = Safety.Read(frame, "GetName")
    if type(name) == "string" and name ~= "" then
        changed = ApplyTexture(_G[name .. "Check"], owner) or changed
    end
    return changed
end

local function HasReadableChildren(frame)
    return type(Safety.Field(frame, "GetChildren")) == "function" and not Safety.IsForbidden(frame)
end

-- A secret child (12.1 Hierarchy aspect) is skipped.
local function TrackChildButtons(owner, changed, ...)
    local Public = Safety.Public
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if Public(child) then
            changed = Checkmarks.TrackButton(child, owner) or changed
        end
    end
    return changed
end

-- buttonTracked: a frame walk already ran TrackButton on frame as a child of
-- its visited parent in this same pass (GenericWindows TraverseTree), so only
-- its Check textures and its own children remain.
function Checkmarks.TrackFrame(frame, owner, buttonTracked)
    local changed = TrackSingleFrame(frame, owner, buttonTracked)
    if not HasReadableChildren(frame) then return changed end
    return TrackChildButtons(owner, changed, frame:GetChildren())
end

-- 12.1 can return a secret child (Hierarchy aspect); a secret is never used
-- as a key or visited.
local function AppendChildren(queue, depths, visited, depth, maxNodes, ...)
    local Public = Safety.Public
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if Public(child) and child and not visited[child] and #queue < maxNodes then
            queue[#queue + 1] = child
            depths[#depths + 1] = depth
        end
    end
end

-- Walk scratch, reused because Settings rows are walked on every ScrollBox
-- initialization. A nested walk (none is expected) gets its own tables.
local walkQueue, walkDepths, walkVisited = {}, {}, {}
local walkBusy = false

local function ClearWalk(queue, depths, visited)
    for index = #queue, 1, -1 do
        queue[index] = nil
        depths[index] = nil
    end
    for node in pairs(visited) do visited[node] = nil end
end

-- Breadth-first walk over a bounded Blizzard frame tree. With trackableOnly,
-- a node that cannot be decorated is neither visited, counted nor expanded.
local function Walk(queue, depths, visited, root, owner, maxDepth, maxNodes, trackableOnly, visit)
    queue[1], depths[1] = root, 0
    local head, nodes, changed = 1, 0, false
    while head <= #queue and nodes < maxNodes do
        local current, depth = queue[head], depths[head]
        head = head + 1
        if current and not visited[current] then
            visited[current] = true
            if not trackableOnly or CanTrack(current) then
                nodes = nodes + 1
                changed = visit(current, owner) or changed
                if depth < maxDepth and HasReadableChildren(current) then
                    AppendChildren(queue, depths, visited, depth + 1, maxNodes, current:GetChildren())
                end
            end
        end
    end
    return changed, nodes
end

local function FinishWalk(...)
    return true, Walk(...)
end

-- One walk is one boundary: a visit that raises is reported, and the shared
-- scratch is cleared and released either way.
local function WalkControlTree(root, owner, maxDepth, maxNodes, trackableOnly, visit)
    if walkBusy then
        return Walk({}, {}, {}, root, owner, maxDepth, maxNodes, trackableOnly, visit)
    end
    walkBusy = true
    local finished, changed, nodes = Safety.Dispatch(FinishWalk, walkQueue, walkDepths, walkVisited,
        root, owner, maxDepth, maxNodes, trackableOnly, visit)
    ClearWalk(walkQueue, walkDepths, walkVisited)
    walkBusy = false
    if not finished then return false, 0 end
    return changed, nodes
end

-- Dedicated adapters intentionally do not run the generic window traversal.
-- Walk only their own bounded Blizzard root after a successful OOC apply so
-- pre-created close, paging, expand and condense buttons receive the same
-- verified native-asset recoloring as generic windows.  No regions are
-- created here and explicit protected subtrees are never entered.
function Checkmarks.TrackControlTree(root, owner, options)
    if not NS.DB or not NS.DB.enabled or NS.IsCombatLocked() or not root then
        return false, 0
    end
    options = type(options) == "table" and options or {}
    local maxDepth = math.max(0, math.min(12,
        math.floor(tonumber(options.maxDepth) or 8)))
    local maxNodes = math.max(1, math.min(1200,
        math.floor(tonumber(options.maxNodes) or 720)))
    return WalkControlTree(root, owner, maxDepth, maxNodes, true, TrackSingleFrame)
end

function Checkmarks.UntrackOwner(owner)
    NS.WindowActionSkin.DisableOwner(owner)
    local set = Checkmarks.owners[owner]
    local dropdowns, categoryLists, textures = {}, {}, {}
    if set then
        for object in pairs(set) do
            if Checkmarks.dropdowns[object] then
                dropdowns[#dropdowns + 1] = object
            elseif Checkmarks.settingsCategoryLists[object] then
                categoryLists[#categoryLists + 1] = object
            elseif Checkmarks.states[object] then
                textures[#textures + 1] = object
            end
        end
    end
    for index = 1, #dropdowns do Checkmarks.UntrackDropdown(dropdowns[index]) end
    for index = 1, #categoryLists do
        Checkmarks.UntrackSettingsCategories(categoryLists[index])
    end
    for index = 1, #textures do RestoreTexture(textures[index]) end
    for button, buttonOwner in pairs(Checkmarks.buttonOwners) do
        if buttonOwner == owner then
            Checkmarks.buttons[button] = nil
            Checkmarks.buttonOwners[button] = nil
        end
    end
    Checkmarks.owners[owner] = nil
    return true
end

function Checkmarks.Apply()
    if not NS.DB then return false, "uninitialized" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("checkmarks:apply", Checkmarks.Apply)
        return false, "combat"
    end
    if not NS.DB.enabled then return Checkmarks.Restore() end
    Checkmarks.RegisterLegacyDropdowns()
    for texture, state in pairs(Checkmarks.states) do
        ApplyTexture(texture, state.owner, state.boundRole)
    end
    for button in pairs(Checkmarks.buttons) do
        Checkmarks.TrackButton(button, Checkmarks.buttonOwners[button])
    end
    local count = 0
    for _ in pairs(Checkmarks.states) do count = count + 1 end
    Checkmarks.count = count
    return true, count
end

function Checkmarks.Restore()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("checkmarks:restore", Checkmarks.Restore)
        return false, "combat"
    end
    NS.WindowActionSkin.Restore()
    Checkmarks.ReleaseMenus()
    for texture, state in pairs(Checkmarks.states) do RestoreTexture(texture, state) end
    Checkmarks.count = 0
    return true
end

-- Color tokens this module paints.
local ownedColorKeys = {
    checkmark = true, blizzardYellow = true, blizzardArrow = true,
    blizzardExpand = true, blizzardExpandPressed = true, blizzardExpandHover = true,
    blizzardClose = true, blizzardClosePressed = true, blizzardCloseHover = true,
    blizzardCloseDisabled = true, disabled = true,
}

-- One full pass per frame of settings writes (Registry.QueueJob).
local function ApplyQueued() Checkmarks.Apply() end

function Checkmarks:OnThemeChanged(domain, key)
    if domain == "color" and not ownedColorKeys[key] then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    NS.Registry.QueueJob(ApplyQueued)
end

function Checkmarks.GetStatus() return { applied = Checkmarks.count } end

NS.Registry.AddListener(Checkmarks, Checkmarks.OnThemeChanged)

-- Private to CheckmarksMenus.lua, which loads next (TOC order) and takes it
-- off NS again.
NS.CheckmarksShared = {
    Field = Field,
    Getter = Getter,
    CanTrack = CanTrack,
    OwnerSet = OwnerSet,
    WalkControlTree = WalkControlTree,
}

return Checkmarks
