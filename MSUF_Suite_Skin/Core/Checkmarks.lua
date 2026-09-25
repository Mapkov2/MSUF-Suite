local _, NS = ...

-- Recolor only verified Blizzard checkbox, menu-selection, dropdown-stepper
-- and close-button assets, and replace the exact Settings category highlight
-- with owned button states. Blizzard uses the same fields for unrelated
-- semantic art, so blanket texture passes remain unsafe. Ownership is
-- external, weak and reversible.
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
local HIGHLIGHT_GETTER_INDEX = 6
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

local function Close(left, right)
    return math.abs(left - right) <= 0.015
end

local function MatchesColor(color, r, g, b, a)
    return color ~= nil and Close(r, color[1]) and Close(g, color[2])
        and Close(b, color[3]) and Close(a, color[4])
end

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

local function AtlasKey(texture)
    local atlas = Safety.Read(texture, "GetAtlas")
    return type(atlas) == "string" and atlas:lower() or nil
end

local function AssetRole(texture)
    if not texture then return false end
    local atlas = AtlasKey(texture)
    if atlas and acceptedAtlases[atlas] then return acceptedAtlases[atlas] end
    for index = 1, #texturePathGetters do
        local path = Safety.Read(texture, texturePathGetters[index])
        if type(path) == "string" then
            path = path:gsub("/", "\\"):lower():gsub("%.blp$", ""):gsub("%.tga$", "")
            if acceptedPaths[path] then return acceptedPaths[path] end
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
    if state and not MatchesColor(state.applied, r, g, b, a)
        and not MatchesColor(state.original, r, g, b, a) then
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
    if r and MatchesColor(state.applied, r, g, b, a) then
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
    return ApplyTexture(texture, owner, colorRole)
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

function Checkmarks.DetectWindowAction(button)
    if not button then return nil end
    local normal = AtlasKey(Getter(button, "GetNormalTexture"))
    local definition = normal and windowActionPairs[normal] or nil
    if not definition
        or AtlasKey(Getter(button, "GetPushedTexture")) ~= definition.pushed then
        return nil
    end
    local disabled = Getter(button, "GetDisabledTexture")
    if disabled and AtlasKey(disabled) ~= definition.disabled then return nil end
    return definition.kind
end

function Checkmarks.GetWindowAction(button)
    local detected = Checkmarks.DetectWindowAction(button)
    if detected then return detected end
    if NS.WindowActionSkin and NS.WindowActionSkin.HasOwnedStates(button) then
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

function Checkmarks.IsCloseButton(button)
    return Checkmarks.GetWindowAction(button) == "close"
end

function Checkmarks.TrackButton(button, owner)
    if not NS.DB or not NS.DB.enabled or NS.IsCombatLocked() or not CanTrack(button) then
        return false
    end
    local changed = false
    local recognized = false
    local actionKind = Checkmarks.DetectWindowAction(button)
    if not actionKind and NS.WindowActionSkin
        and NS.WindowActionSkin.HasOwnedStates(button) then
        actionKind = NS.WindowActionSkin.GetKind(button)
    end
    local normalRole = AssetRole(Getter(button, "GetNormalTexture"))
    local highlightRole
    if normalRole == "blizzardExpand" then
        highlightRole = "blizzardExpandHover"
    elseif IsCloseRole(normalRole) then
        highlightRole = "blizzardCloseHover"
    end
    for index = 1, #buttonTextureGetters do
        local texture = Getter(button, buttonTextureGetters[index])
        local role = (index == HIGHLIGHT_GETTER_INDEX and highlightRole) or AssetRole(texture)
        if role then
            recognized = true
            changed = ApplyTexture(texture, owner, role) or changed
        end
    end
    for index = 1, #buttonTextureFields do
        local texture = Field(button, buttonTextureFields[index])
        local role = AssetRole(texture)
        if role then
            recognized = true
            changed = ApplyTexture(texture, owner, role) or changed
        end
    end
    if actionKind and NS.WindowActionSkin then
        local action = NS.WindowActionSkin.Track(button, owner, actionKind)
        recognized = action ~= nil or recognized
        changed = action ~= nil or changed
    elseif NS.WindowActionSkin and NS.WindowActionSkin.IsApplied(button)
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
    if NS.WindowActionSkin then NS.WindowActionSkin.Disable(button, owner) end
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

local function TrackSingleFrame(frame, owner)
    if not frame then return false end
    local changed = Checkmarks.TrackButton(frame, owner)
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

local function TrackChildButtons(owner, changed, ...)
    for index = 1, select("#", ...) do
        changed = Checkmarks.TrackButton(select(index, ...), owner) or changed
    end
    return changed
end

function Checkmarks.TrackFrame(frame, owner)
    local changed = TrackSingleFrame(frame, owner)
    if not HasReadableChildren(frame) then return changed end
    return TrackChildButtons(owner, changed, frame:GetChildren())
end

local function AppendChildren(queue, depths, visited, depth, maxNodes, ...)
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if child and not visited[child] and #queue < maxNodes then
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
local function WalkControlTree(root, owner, maxDepth, maxNodes, trackableOnly, visit)
    local queue, depths, visited = walkQueue, walkDepths, walkVisited
    local shared = not walkBusy
    if shared then
        walkBusy = true
    else
        queue, depths, visited = {}, {}, {}
    end
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
    if shared then
        ClearWalk(queue, depths, visited)
        walkBusy = false
    end
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

local function DropdownEvent()
    return DropdownButtonMixin and DropdownButtonMixin.Event
        and DropdownButtonMixin.Event.OnMenuOpen
end

local function LooksLikeDropdown(button)
    return button and type(button.RegisterCallback) == "function"
        and type(button.UnregisterCallback) == "function"
        and type(button.IsMenuOpen) == "function"
        and type(button.GetMenuDescription) == "function"
end

Checkmarks.IsDropdown = LooksLikeDropdown

-- Blizzard pools the same MenuTemplateBase frames across unrelated dropdowns.
-- A shared owner prevents disabling dropdown A from hiding a pooled popup
-- currently reused by dropdown B.
local DROPDOWN_MENU_OWNER = "blizzard-dropdown-menus"

local DROPDOWN_POPUP_SPEC = {
    role = "popup",
    radius = 6,
    inset = 0,
    maxDepth = 6,
    maxNodes = 320,
    menuPopup = true,
    registerDynamicRows = true,
    allowImplicitProtected = true,
}

-- DropdownButtonMixin passes the registration owner (the state) first.
local function OnMenuOpen(state, dropdown)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled then return end
    dropdown = dropdown or state.button
    if NS.BlizzardYellow then NS.BlizzardYellow.TrackDropdown(dropdown) end
    local menu = Field(dropdown, "menu")
    if not menu or not Safety.CanDecorate(menu, true) then return end
    -- Modern Blizzard_Menu proxies are compositor-managed: existing
    -- check/text regions remain safe to tint, but owned Surface creation is
    -- forbidden for their lifetime.
    if NS.GenericWindows and not Safety.IsCompositorManaged(menu) then
        NS.GenericWindows.ApplyFrame(menu, state.menuOwner, DROPDOWN_POPUP_SPEC)
    end
    Checkmarks.TrackFrame(menu, state.menuOwner)
end

function Checkmarks.UntrackDropdown(button)
    local state = Checkmarks.dropdowns[button]
    if not state then return false end
    if state.event and type(button.UnregisterCallback) == "function" then
        button:UnregisterCallback(state.event, state)
    end
    Checkmarks.dropdowns[button] = nil
    local ownerSet = Checkmarks.owners[state.owner]
    if ownerSet then ownerSet[button] = nil end
    if not next(Checkmarks.dropdowns) and NS.GenericWindows then
        NS.GenericWindows.Disable(DROPDOWN_MENU_OWNER)
    end
    return true
end

function Checkmarks.TrackDropdown(button, owner)
    local event = DropdownEvent()
    if NS.IsCombatLocked() or not event or not LooksLikeDropdown(button)
        or not CanTrack(button) then
        return false
    end
    if NS.BlizzardYellow then NS.BlizzardYellow.TrackDropdown(button) end
    local existing = Checkmarks.dropdowns[button]
    if existing and existing.owner == owner and existing.event == event then
        return true
    end
    if existing then Checkmarks.UntrackDropdown(button) end

    local state = { owner = owner, event = event, menuOwner = DROPDOWN_MENU_OWNER, button = button }
    button:RegisterCallback(event, OnMenuOpen, state)
    Checkmarks.dropdowns[button] = state
    local ownerSet = OwnerSet(owner)
    if ownerSet then ownerSet[button] = true end
    return true
end

local SETTINGS_CATEGORY_EVENT = "Settings.CategoryChanged"
local SETTINGS_TAB_KEYS = { "GameTab", "AddOnsTab" }

local SETTINGS_CATEGORY_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    useControlShape = true,
    pillHeight = 20,
    radius = 4,
    inset = 0,
    listItem = true,
    activeEdge = true,
    allowImplicitProtected = true,
}

local function SettingsCategoryScrollEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function SettingsTabSelectedEvent()
    return ButtonGroupBaseMixin and ButtonGroupBaseMixin.Event
        and ButtonGroupBaseMixin.Event.Selected
end

local function CategorySelected(row)
    local texture = Field(row, "Texture")
    if Safety.Read(texture, "GetAtlas") ~= "Options_List_Active" then return false end
    local shown = Safety.Read(texture, "IsShown")
    return shown == nil or shown == true
end

local function SkinSettingsCategoryRow(state, row)
    if not state.active or NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled
        or not row or not CanTrack(row) then
        return false
    end
    -- The Settings ScrollBox dispatches its header and spacer Frame templates
    -- through the same initializer callback as actual category Buttons. Only
    -- SettingsCategoryListButtonTemplate owns this selection texture.
    local texture = Field(row, "Texture")
    if not texture then return false end
    if NS.Cosmetics then NS.Cosmetics.Fade(texture, state.owner) end
    Checkmarks.TrackButton(Field(row, "Toggle"), state.owner)
    if not NS.ControlSkin then return false end
    local applied = NS.ControlSkin.ApplyButton(row, state.owner, SETTINGS_CATEGORY_SPEC)
    if applied and NS.Surface then NS.Surface.SetActive(row, CategorySelected(row)) end
    return applied ~= nil
end

local function TrackSettingsButton(button, owner)
    return Checkmarks.TrackButton(button, owner)
end

local function TrackSettingsControlTree(state, root)
    if not state or not state.active or NS.IsCombatLocked() or not root then return false end
    return (WalkControlTree(root, state.owner, 4, 96, false, TrackSettingsButton))
end

-- ScrollBox:ForEachFrame passes only the row; the walked state rides along
-- here instead of in a closure per walk.
local walkingState

local function SkinWalkedCategoryRow(row)
    SkinSettingsCategoryRow(walkingState, row)
end

local function TrackWalkedControlRow(row)
    TrackSettingsControlTree(walkingState, row)
end

local function ForEachStateRow(state, scrollBox, visit)
    local previous = walkingState
    walkingState = state
    scrollBox:ForEachFrame(visit)
    walkingState = previous
end

local function RefreshSettingsCategories(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local scrollBox = state.scrollBox
    if type(Field(scrollBox, "ForEachFrame")) ~= "function" then return false end
    ForEachStateRow(state, scrollBox, SkinWalkedCategoryRow)
    return true
end

local function RefreshSettingsControls(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local scrollBox = state.settingsScrollBox
    if type(Field(scrollBox, "ForEachFrame")) ~= "function" then return false end
    ForEachStateRow(state, scrollBox, TrackWalkedControlRow)
    return true
end

local function RefreshSettingsTabs(state)
    if not state or not state.active or NS.IsCombatLocked() or not NS.ControlSkin then
        return false
    end
    local panel = state.settingsPanel
    if not panel then return false end
    local changed = false
    for index = 1, #SETTINGS_TAB_KEYS do
        local tab = Field(panel, SETTINGS_TAB_KEYS[index])
        if tab and NS.ControlSkin.IsApplied(tab) then
            changed = NS.ControlSkin.Refresh(tab) == true or changed
        end
    end
    return changed
end

-- Callback registries pass the registration owner (the state) first.
local function OnCategoryChanged(state)
    RefreshSettingsCategories(state)
    -- Blizzard finishes DisplayCategory (including ScrollBox row
    -- initialization) before this event. Revisit the active rows so the
    -- very first Settings open receives the selected theme colors.
    RefreshSettingsControls(state)
    RefreshSettingsTabs(state)
end

local function OnTabSelected(state)
    RefreshSettingsTabs(state)
end

local function OnCategoryRowInitialized(state, row)
    SkinSettingsCategoryRow(state, row)
end

local function OnSettingsRowInitialized(state, row)
    TrackSettingsControlTree(state, row)
end

local function CanRegister(registry)
    return type(Field(registry, "RegisterCallback")) == "function"
end

local function CanUnregister(registry)
    return type(Field(registry, "UnregisterCallback")) == "function"
end

function Checkmarks.UntrackSettingsCategories(categoryList)
    local state = Checkmarks.settingsCategoryLists[categoryList]
    if not state then return false end
    state.active = false
    if state.settingsRegistered and CanUnregister(EventRegistry) then
        EventRegistry:UnregisterCallback(SETTINGS_CATEGORY_EVENT, state)
    end
    if state.scrollRegistered and state.scrollEvent and CanUnregister(state.scrollBox) then
        state.scrollBox:UnregisterCallback(state.scrollEvent, state)
    end
    if state.settingsScrollRegistered and state.scrollEvent
        and CanUnregister(state.settingsScrollBox) then
        state.settingsScrollBox:UnregisterCallback(state.scrollEvent, state)
    end
    if state.tabRegistered and state.tabEvent and CanUnregister(state.tabGroup) then
        state.tabGroup:UnregisterCallback(state.tabEvent, state)
    end
    Checkmarks.settingsCategoryLists[categoryList] = nil
    local ownerSet = Checkmarks.owners[state.owner]
    if ownerSet then ownerSet[categoryList] = nil end
    return true
end

local function ResolveSettingsList(settingsPanel)
    return Getter(settingsPanel, "GetSettingsList")
        or Field(Field(settingsPanel, "Container"), "SettingsList")
end

local function RegisterSettingsCallbacks(state)
    if CanRegister(EventRegistry) then
        EventRegistry:RegisterCallback(SETTINGS_CATEGORY_EVENT, OnCategoryChanged, state)
        state.settingsRegistered = true
    end
    if state.scrollEvent then
        state.scrollBox:RegisterCallback(state.scrollEvent, OnCategoryRowInitialized, state)
        state.scrollRegistered = true
        local settingsScrollBox = state.settingsScrollBox
        if CanRegister(settingsScrollBox)
            and type(Field(settingsScrollBox, "ForEachFrame")) == "function" then
            settingsScrollBox:RegisterCallback(state.scrollEvent, OnSettingsRowInitialized, state)
            state.settingsScrollRegistered = true
        end
    end
    if state.tabEvent and CanRegister(state.tabGroup) then
        state.tabGroup:RegisterCallback(state.tabEvent, OnTabSelected, state)
        state.tabRegistered = true
    end
end

function Checkmarks.TrackSettingsCategories(categoryList, owner, settingsPanel)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled or not categoryList
        or not CanTrack(categoryList) then
        return false
    end
    local scrollBox = Field(categoryList, "ScrollBox")
    if not CanRegister(scrollBox) or type(Field(scrollBox, "ForEachFrame")) ~= "function" then
        return false
    end
    local existing = Checkmarks.settingsCategoryLists[categoryList]
    if existing and existing.owner == owner then
        OnCategoryChanged(existing)
        return true
    elseif existing then
        Checkmarks.UntrackSettingsCategories(categoryList)
    end

    local state = {
        owner = owner,
        categoryList = categoryList,
        scrollBox = scrollBox,
        scrollEvent = SettingsCategoryScrollEvent(),
        settingsPanel = settingsPanel,
        active = true,
    }
    state.settingsScrollBox = Field(ResolveSettingsList(settingsPanel), "ScrollBox")
    state.tabGroup = Field(settingsPanel, "tabsGroup")
    state.tabEvent = SettingsTabSelectedEvent()
    RegisterSettingsCallbacks(state)
    if not state.settingsRegistered and not state.scrollRegistered then
        state.active = false
        return false
    end

    Checkmarks.settingsCategoryLists[categoryList] = state
    local ownerSet = OwnerSet(owner)
    if ownerSet then ownerSet[categoryList] = true end
    OnCategoryChanged(state)
    return true
end

function Checkmarks.UntrackOwner(owner)
    if NS.WindowActionSkin then NS.WindowActionSkin.DisableOwner(owner) end
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

local LEGACY_DROPDOWN_OWNER = "legacy-dropdown-menu"
local LEGACY_DROPDOWN_EVENT = "UIDropDownMenu.Show"

local LEGACY_DROPDOWN_SPEC = {
    role = "popup",
    radius = 6,
    inset = 0,
    maxDepth = 5,
    maxNodes = 260,
    menuPopup = true,
    legacyDropdown = true,
    registerDynamicRows = false,
    allowImplicitProtected = true,
}

function Checkmarks:OnLegacyDropdownShown(listFrame)
    if NS.IsCombatLocked() or not NS.DB or not NS.DB.enabled or not listFrame then return end
    if NS.GenericWindows then
        NS.GenericWindows.ApplyFrame(listFrame, LEGACY_DROPDOWN_OWNER, LEGACY_DROPDOWN_SPEC)
    end
    Checkmarks.TrackFrame(listFrame, LEGACY_DROPDOWN_OWNER)
end

function Checkmarks.RegisterLegacyDropdowns()
    if Checkmarks.legacyRegistered or not CanRegister(EventRegistry) then
        return Checkmarks.legacyRegistered
    end
    EventRegistry:RegisterCallback(LEGACY_DROPDOWN_EVENT, Checkmarks.OnLegacyDropdownShown, Checkmarks)
    Checkmarks.legacyRegistered = true
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
        ApplyTexture(texture, state.owner)
    end
    for button in pairs(Checkmarks.buttons) do
        Checkmarks.TrackButton(button, Checkmarks.buttonOwners[button])
    end
    local count = 0
    for _ in pairs(Checkmarks.states) do count = count + 1 end
    Checkmarks.count = count
    return true, count
end

local function Keys(set)
    local keys = {}
    for key in pairs(set) do keys[#keys + 1] = key end
    return keys
end

function Checkmarks.Restore()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("checkmarks:restore", Checkmarks.Restore)
        return false, "combat"
    end
    if NS.WindowActionSkin then NS.WindowActionSkin.Restore() end
    local dropdowns = Keys(Checkmarks.dropdowns)
    for index = 1, #dropdowns do Checkmarks.UntrackDropdown(dropdowns[index]) end
    local categoryLists = Keys(Checkmarks.settingsCategoryLists)
    for index = 1, #categoryLists do
        Checkmarks.UntrackSettingsCategories(categoryLists[index])
    end
    if Checkmarks.legacyRegistered and CanUnregister(EventRegistry) then
        EventRegistry:UnregisterCallback(LEGACY_DROPDOWN_EVENT, Checkmarks)
    end
    Checkmarks.legacyRegistered = false
    if NS.GenericWindows then NS.GenericWindows.Disable(LEGACY_DROPDOWN_OWNER) end
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

function Checkmarks:OnThemeChanged(domain, key)
    if domain == "color" and not ownedColorKeys[key] then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    Checkmarks.Apply()
end

function Checkmarks.GetStatus() return { applied = Checkmarks.count } end

NS.Registry.AddListener(Checkmarks, Checkmarks.OnThemeChanged)

return Checkmarks
