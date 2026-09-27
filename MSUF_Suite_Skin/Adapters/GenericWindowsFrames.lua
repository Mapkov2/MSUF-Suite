local _, NS = ...

-- GenericWindows frame passes (see GenericWindows.lua): named controls that
-- are not descendants, the bounded child traversal, the per-frame state of
-- each pass and the pooled ScrollBox rows it registers.
local GenericWindows = NS.GenericWindows
local Shared = NS.GenericWindowsShared

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call
local Kit = NS.AdapterKit

local DEFAULT_OWNER = Shared.DEFAULT_OWNER
local frameStates = Shared.frameStates
local rowModes = Shared.rowModes
local childPanelSpecs = Shared.childPanelSpecs
local menuRowSpecs = Shared.menuRowSpecs
local OwnerState = Shared.OwnerState
local OwnerKey = Shared.OwnerKey
local CanSkin = Shared.CanSkin
local ObjectName = Shared.ObjectName
local Attach = Shared.Attach
local HasChrome = Shared.HasChrome
local FadeChrome = Shared.FadeChrome
local ChildPanelRole = Shared.ChildPanelRole
local AttachChildSurface = Shared.AttachChildSurface
local SkinButton = Shared.SkinButton
local SkinIconButtonBase = Shared.SkinIconButtonBase
local SkinInput = Shared.SkinInput
local SkinScrollBar = Shared.SkinScrollBar
local SkinNode = Shared.SkinNode
local EnsureThemeListener = Shared.EnsureThemeListener

local function ModeValue(mode, key, fallback)
    if type(mode) == "table" and mode[key] ~= nil then
        return mode[key]
    end
    return fallback
end

local function PublicNumber(target, method)
    local value = Safety.Read(target, method)
    return type(value) == "number" and value or nil
end

-- A full-screen UIParent child must never receive a generic opaque root
-- surface. Several Blizzard managers (notably MotionSicknessFrame) are
-- permanently shown and use setAllPoints even when their own artwork is
-- currently empty. Size detection is an additional runtime fail-safe on top
-- of catalog modes, so one bad source classification cannot black out WoW.
local function IsFullscreenRoot(frame)
    local uiParent = UIParent
    if frame == uiParent or not Kit.ParentIs(frame, uiParent) then
        return false
    end
    local width, height = PublicNumber(frame, "GetWidth"), PublicNumber(frame, "GetHeight")
    local uiWidth, uiHeight = PublicNumber(uiParent, "GetWidth"), PublicNumber(uiParent, "GetHeight")
    if not width or not height or not uiWidth or not uiHeight
        or uiWidth <= 0 or uiHeight <= 0 then
        return false
    end
    return width >= uiWidth * 0.9 and height >= uiHeight * 0.9
end

local function RootRole(mode)
    if type(mode) == "table" and type(mode.role) == "string" then
        return mode.role
    end
    if mode == "popup" or mode == "dialog" or mode == "tooltip" then
        return "popup"
    end
    if mode == "panel" then
        return "panel"
    end
    return "shell"
end

-- Catalog modes are static, so each converted mode is built once.
local catalogModes = Kit.WeakSet()
local NO_MODE = {}

local function CatalogMode(mode)
    local key = mode == nil and NO_MODE or mode
    local result = catalogModes[key]
    if result then return result end
    result = { allowImplicitProtected = true }
    if type(mode) == "table" then
        for modeKey, value in pairs(mode) do
            result[modeKey] = value
        end
    elseif type(mode) == "string" then
        result.role = RootRole(mode)
    end
    catalogModes[key] = result
    return result
end

-- Several Blizzard windows expose important controls as named regions or
-- mixin members which are not descendants (or whose internal child tree is
-- intentionally opaque). Probe only this fixed field vocabulary; this gives
-- Settings, AddOnList, ColorPicker and similar dialogs useful full coverage
-- without a global scan or semantic-art guessing.
local explicitButtonFields = {
    "OkayButton", "OKButton", "CancelButton", "ApplyButton", "CloseButton",
    "DoneButton", "AcceptButton", "DeclineButton", "ResetButton",
    "EnableAllButton", "DisableAllButton", "RefreshButton", "SearchButton",
    "BackButton", "NextButton", "PreviousButton",
    "MinimizeButton", "MaximizeButton", "CollapseButton", "ExpandButton",
    "PlusButton", "MinusButton",
}

local explicitTabFields = {
    "GameTab", "AddOnsTab", "GeneralTab", "AdvancedTab",
}

local explicitInputFields = {
    "SearchBox", "SearchEditBox", "FilterBox", "NameEditBox", "EditBox",
    "HexBox", "HexEditBox",
}

local explicitScrollFields = {
    "ScrollBar", "Scrollbar", "ScrollBoxScrollBar", "CategoryListScrollBar",
}

local explicitPanelFields = {
    "Inset", "Content", "Container", "Footer", "Header", "CategoryList",
    "SearchPreviewContainer", "LeftInset", "RightInset", "MainPanel",
    "GameTimeTutorial",
}

-- Named parentKey chains are not globals and are therefore invisible to the
-- catalog. Keep this list exact and source-reviewed instead of searching
-- arbitrary descendants for dialog-like names.
local explicitPanelPaths = {
    { "WoWTokenResults", "GameTimeTutorial" },
}

local LEGACY_DROPDOWN_BUTTON_LIMIT = 64

local function SkinExplicitPanel(panel, fieldName, owner, metrics)
    if not panel or not CanSkin(panel, metrics.allowImplicitProtected) or not HasChrome(panel) then
        return false
    end
    AttachChildSurface(owner, panel, childPanelSpecs[ChildPanelRole(fieldName)], metrics)
    FadeChrome(panel, owner)
    return true
end

-- Legacy Retail dropdown lists (currently retained by a small PvP path)
-- expose their native backdrops as Border/MenuBackdrop and their rows as
-- Button1..N rather than children of the opening dropdown control.
local function SkinLegacyDropdownList(frame, owner, metrics)
    local border = Field(frame, "Border")
    local backdrop = Field(frame, "MenuBackdrop")
    if border then FadeChrome(border, owner) end
    if backdrop then FadeChrome(backdrop, owner) end
    local count = math.max(tonumber((Field(frame, "numButtons"))) or 0, 1)
    count = math.min(count, LEGACY_DROPDOWN_BUTTON_LIMIT)
    local frameName = ObjectName(frame)
    for index = 1, count do
        local button = Field(frame, "Button" .. index)
            or (frameName ~= "" and _G[frameName .. "Button" .. index])
        if button and CanSkin(button, metrics.allowImplicitProtected) then
            NS.Checkmarks.TrackFrame(button, owner)
            Attach(owner, button, menuRowSpecs[metrics.allowImplicitProtected], metrics)
        end
    end
end

local function ExplicitControl(frame, key, allowImplicitProtected)
    local control = Field(frame, key)
    if control and CanSkin(control, allowImplicitProtected) then return control end
    return nil
end

local function SkinExplicitFields(frame, owner, metrics)
    local allowImplicitProtected = metrics.allowImplicitProtected
    if metrics.legacyDropdown then
        SkinLegacyDropdownList(frame, owner, metrics)
    end

    for index = 1, #explicitButtonFields do
        local control = ExplicitControl(frame, explicitButtonFields[index], allowImplicitProtected)
        if control and Kit.ObjectType(control) == "Button"
            and not SkinButton(control, owner, metrics) then
            SkinIconButtonBase(control, owner, metrics, explicitButtonFields[index])
        end
    end

    for index = 1, #explicitTabFields do
        local tab = ExplicitControl(frame, explicitTabFields[index], allowImplicitProtected)
        if tab and Kit.ObjectType(tab) == "Button" then
            SkinButton(tab, owner, metrics)
        end
    end

    for index = 1, #explicitInputFields do
        local input = ExplicitControl(frame, explicitInputFields[index], allowImplicitProtected)
        if input then SkinInput(input, owner, metrics) end
    end

    for index = 1, #explicitScrollFields do
        local scrollBar = ExplicitControl(frame, explicitScrollFields[index], allowImplicitProtected)
        if scrollBar then SkinScrollBar(scrollBar, owner, metrics) end
    end

    for index = 1, #explicitPanelFields do
        local fieldName = explicitPanelFields[index]
        SkinExplicitPanel(Field(frame, fieldName), fieldName, owner, metrics)
    end

    for index = 1, #explicitPanelPaths do
        local path = explicitPanelPaths[index]
        SkinExplicitPanel(Kit.PathOf(frame, path), path[#path], owner, metrics)
    end
end

-- Appends the given children for the next traversal depth. True when the
-- node limit cut the list short. A secret child is skipped: it is never
-- compared, used as a key or skinned.
local function AppendChildren(queue, depths, depth, limit, ...)
    for index = 1, select("#", ...) do
        if #queue >= limit then return true end
        local child = select(index, ...)
        if Safety.Public(child) and type(child) == "table" then
            queue[#queue + 1] = child
            depths[#depths + 1] = depth
        end
    end
    return false
end

local function IsOwnedEquipmentHost(frame)
    -- Owned equipment UI has its own styling and lifecycle. Do not rescan its
    -- subtree as if it were Blizzard-authored chrome.
    return NS.CharacterDetails.IsHost(frame) or NS.CharacterStats.IsHost(frame)
        or NS.EQoLCharacter.IsHost(frame)
end

-- rootIsNode: root is a descendant of an applied root (see ApplyDescendant)
-- and takes the node pass instead of the root's chrome pass.
local function TraverseTree(root, owner, metrics, maxDepth, maxNodes, rootIsNode)
    local queue, depths = { root }, { 0 }
    local head = 1
    while head <= #queue and metrics.nodes < maxNodes do
        local current, depth = queue[head], depths[head]
        head = head + 1
        if IsOwnedEquipmentHost(current) then
            -- Skipped deliberately; see IsOwnedEquipmentHost.
        elseif not CanSkin(current, metrics.allowImplicitProtected) then
            metrics.protected = metrics.protected + 1
        else
            metrics.nodes = metrics.nodes + 1
            SkinNode(current, owner, metrics, current == root and not rootIsNode)
            if depth < maxDepth then
                if AppendChildren(queue, depths, depth + 1, maxNodes, Call(current, "GetChildren")) then
                    metrics.truncated = true
                    metrics.nodeLimited = true
                end
            elseif (Safety.Read(current, "GetNumChildren") or 0) > 0 then
                metrics.truncated = true
            end
        end
    end
    if head <= #queue or #queue >= maxNodes then
        metrics.truncated = true
        metrics.nodeLimited = true
    end
end

local function TraversalLimits(mode)
    local maxDepth = tonumber(ModeValue(mode, "maxDepth", nil)) or GenericWindows.maxDepth
    local maxNodes = tonumber(ModeValue(mode, "maxNodes", nil)) or GenericWindows.maxNodes
    return math.max(0, math.min(12, math.floor(maxDepth))),
        math.max(1, math.min(1200, math.floor(maxNodes)))
end

local function NewMetrics(mode, allowImplicitProtected)
    return {
        nodes = 0,
        surfaces = 0,
        controls = 0,
        scrollBars = 0,
        protected = 0,
        errors = 0,
        -- truncated: the depth or node limit cut the tree short;
        -- nodeLimited: the node limit did, so nodes within depth were missed.
        truncated = false,
        nodeLimited = false,
        -- Working sets for this pass only; StoreFrameState removes them.
        surfaceTargets = {},
        controlTargets = {},
        scrollTargets = {},
        dynamicScrollBoxes = {},
        childSurfaceTargets = Kit.WeakSet(),
        rootChromeTargets = Kit.WeakSet(),
        allowImplicitProtected = allowImplicitProtected,
        menuPopup = ModeValue(mode, "menuPopup", false) == true,
        legacyDropdown = ModeValue(mode, "legacyDropdown", false) == true,
        preserveRootArt = ModeValue(mode, "preserveRootArt", false) == true,
        accentOnly = ModeValue(mode, "accentOnly", false) == true,
        childSurfaces = ModeValue(mode, "childSurfaces", true) ~= false,
    }
end

local metricWorkingSets = {
    "surfaceTargets", "childSurfaceTargets", "controlTargets", "scrollTargets",
    "dynamicScrollBoxes", "allowImplicitProtected", "menuPopup", "legacyDropdown",
    "preserveRootArt", "accentOnly", "childSurfaces", "rootChromeTargets",
}

local function StoreFrameState(frame, owner, mode, metrics, previousState, rootSurfaceAttached)
    local state = previousState or {}
    state.owner = owner
    state.mode = mode
    state.rootSurfaceAttached = rootSurfaceAttached
    state.childSurfaceTargets = metrics.childSurfaceTargets
    state.rootChromeTargets = metrics.rootChromeTargets
    state.active = true
    for index = 1, #metricWorkingSets do
        metrics[metricWorkingSets[index]] = nil
    end
    state.metrics = metrics
    frameStates[frame] = state
end

-- Fullscreen roots and preserveRootArt modes keep Blizzard's own backdrop,
-- including any art an earlier pass of this owner faded.
local function ResolveRootArt(frame, owner, metrics, wantsRootSurface, previous)
    metrics.fullscreenGuarded = wantsRootSurface and not metrics.accentOnly
        and IsFullscreenRoot(frame) or false
    if metrics.fullscreenGuarded then
        metrics.preserveRootArt = true
    end
    if metrics.preserveRootArt and previous and previous.rootChromeTargets then
        for region in pairs(previous.rootChromeTargets) do
            NS.Cosmetics.Restore(region, owner)
        end
    end
end

-- Modes are shared, unchanged tables or strings, so each root spec is built
-- once per mode and shared by every frame (and pooled row) using it.
local rootSpecs = Kit.WeakSet()

local function RootSpec(mode, allowImplicitProtected)
    local key = mode == nil and NO_MODE or mode
    local spec = rootSpecs[key]
    if not spec then
        spec = {
            role = RootRole(mode),
            radius = ModeValue(mode, "radius", 8),
            inset = ModeValue(mode, "inset", 0),
            border = ModeValue(mode, "border", nil),
            fillVisible = ModeValue(mode, "fillVisible", true) ~= false,
            listItem = ModeValue(mode, "listItem", false) == true,
            allowImplicitProtected = allowImplicitProtected,
        }
        rootSpecs[key] = spec
    end
    return spec
end

local RegisterDynamicScrollBox

-- While the Bags module paints the combined and reagent bag shell, the skin
-- keeps only the window's contents: no root surface and Blizzard's root art
-- left to the module. One derived mode per incoming mode.
local bagShellModes = Kit.WeakSet()

local function BagShellMode(mode)
    local key = mode == nil and NO_MODE or mode
    local result = bagShellModes[key]
    if result then return result end
    result = {}
    if type(mode) == "table" then
        for modeKey, value in pairs(mode) do result[modeKey] = value end
    elseif type(mode) == "string" then
        result.role = RootRole(mode)
    end
    result.rootSurface = false
    result.preserveRootArt = true
    bagShellModes[key] = result
    return result
end

local function OwnedMode(frame, mode)
    local ownership = NS.SuiteOwnership
    if ownership.IsBagShell(frame) and ownership.Owns("bagWindows") then
        return BagShellMode(mode)
    end
    return mode
end

local function ApplyFrameNow(frame, owner, mode)
    if not frame then return false, "invalid", nil end
    mode = OwnedMode(frame, mode)
    local allowImplicitProtected = ModeValue(mode, "allowImplicitProtected", false) == true
    if not CanSkin(frame, allowImplicitProtected) then
        return false, Safety.IsCompositorManaged(frame) and "compositor" or "protected", nil
    end
    if type((Field(frame, "CreateTexture"))) ~= "function" then return false, "invalid", nil end

    local previousState = frameStates[frame]
    local previous = previousState and previousState.owner == owner and previousState or nil
    local metrics = NewMetrics(mode, allowImplicitProtected)
    local wantsRootSurface = ModeValue(mode, "rootSurface", true) ~= false
    ResolveRootArt(frame, owner, metrics, wantsRootSurface, previous)

    local rootSurfaceAttached = false
    if wantsRootSurface and not metrics.fullscreenGuarded then
        if not Attach(owner, frame, RootSpec(mode, allowImplicitProtected), metrics) then
            return false, "surface", metrics
        end
        rootSurfaceAttached = true
    elseif previous and previous.rootSurfaceAttached == true then
        NS.Surface.SetVisible(frame, false)
    end

    if not metrics.accentOnly then
        SkinExplicitFields(frame, owner, metrics)
    end
    TraverseTree(frame, owner, metrics, TraversalLimits(mode))

    local ownerState = OwnerState(owner)
    ownerState.active = true
    if ModeValue(mode, "registerDynamicRows", true) ~= false then
        for scrollBox in pairs(metrics.dynamicScrollBoxes) do
            RegisterDynamicScrollBox(scrollBox, owner, allowImplicitProtected, metrics.menuPopup)
        end
    end
    if not metrics.childSurfaces and previous and previous.childSurfaceTargets then
        for target in pairs(previous.childSurfaceTargets) do
            NS.Surface.SetVisible(target, false)
        end
    end

    StoreFrameState(frame, owner, mode, metrics, previousState, rootSurfaceAttached)
    ownerState.frames[frame] = true
    NS.WindowControls.Attach(frame, owner)
    return true, "applied", metrics
end

-- Rows usually keep their text in child frames (a name or detail frame), so
-- the yellow refresh follows the row's own subtree within the depth and node
-- bounds of its first pass (the row mode). Varargs keep the walk
-- allocation-free; children the full pass skips are skipped here too.
local TrackRowChildren

local function TrackRowTree(yellow, frame, mode, depth, budget)
    yellow.TrackFrame(frame)
    if depth >= mode.maxDepth or budget <= 0 then return budget end
    return TrackRowChildren(yellow, mode, depth + 1, budget, Call(frame, "GetChildren"))
end

TrackRowChildren = function(yellow, mode, depth, budget, ...)
    for index = 1, select("#", ...) do
        if budget <= 0 then return 0 end
        local child = select(index, ...)
        if Safety.Public(child) and type(child) == "table" and not IsOwnedEquipmentHost(child)
            and CanSkin(child, mode.allowImplicitProtected) then
            budget = TrackRowTree(yellow, child, mode, depth, budget - 1)
        end
    end
    return budget
end

-- Blizzard initializes pooled ScrollBox rows on every scroll and data
-- refresh. A recycled row keeps every surface and faded region from its
-- first pass, so only element-dependent state is refreshed: Blizzard's
-- yellow text, the selected menu entry and the native check/expand glyphs.
local function RefreshTrackedRow(row, owner, mode)
    local yellow = NS.BlizzardYellow
    TrackRowTree(yellow, row, mode, 0, mode.maxNodes - 1)
    if mode.menuPopup then yellow.TrackMenuSelection(row) end
    NS.Checkmarks.TrackFrame(row, owner)
end

local function RefreshRecycledRow(row, registration)
    RefreshTrackedRow(row, registration.owner, registration.mode)
end

-- Registered once per ScrollBox as callback(registration, row).
local function OnRowInitialized(registration, row)
    local ownerState = registration.ownerState
    -- Optional pooled-row cosmetics never justify combat work or a
    -- post-combat backlog. A later OOC initialization handles the row.
    if not ownerState.active or not row or NS.IsCombatLocked() then return end
    if ownerState.skinnedRows[row] == ownerState.generation then
        RefreshRecycledRow(row, registration)
    elseif ApplyFrameNow(row, registration.owner, registration.mode) then
        ownerState.skinnedRows[row] = ownerState.generation
    end
end

RegisterDynamicScrollBox = function(scrollBox, owner, allowImplicitProtected, menuPopup)
    local ownerState = OwnerState(owner)
    if ownerState.scrollBoxes[scrollBox] then return false end
    local registration = {
        ownerState = ownerState,
        owner = owner,
        mode = rowModes[allowImplicitProtected == true][menuPopup == true],
    }
    registration.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, registration)
    if not registration.event then return false end
    ownerState.scrollBoxes[scrollBox] = registration
    EnsureThemeListener()
    Kit.ForEachRow(scrollBox, function(row)
        OnRowInitialized(registration, row)
    end)
    return true
end

-- A pooled frame that Blizzard acquires after a root's pass (from its own
-- pools, not a ScrollBox) takes the node pass that root's traversal gives
-- every descendant: no root surface, root chrome or frame state of its own.
-- mode is the root's mode with limits for the frame's own subtree. Out of
-- combat only; the caller decides which frames still need it.
function GenericWindows.ApplyDescendant(frame, owner, mode)
    owner = owner or DEFAULT_OWNER
    if not frame or NS.IsCombatLocked() then return false end
    local allowImplicitProtected = ModeValue(mode, "allowImplicitProtected", false) == true
    if not CanSkin(frame, allowImplicitProtected) then return false end
    local metrics = NewMetrics(mode, allowImplicitProtected)
    local maxDepth, maxNodes = TraversalLimits(mode)
    TraverseTree(frame, owner, metrics, maxDepth, maxNodes, true)
    OwnerState(owner).active = true
    if ModeValue(mode, "registerDynamicRows", true) ~= false then
        for scrollBox in pairs(metrics.dynamicScrollBoxes) do
            RegisterDynamicScrollBox(scrollBox, owner, allowImplicitProtected, metrics.menuPopup)
        end
    end
    return true
end

-- The same refresh for a pooled frame Blizzard filled again after its node
-- pass (ApplyDescendant): its surfaces and faded regions stay, while
-- Blizzard's gold text and native glyphs are tracked again. Allocation-free.
function GenericWindows.RefreshDescendant(frame, owner, mode)
    if not frame or NS.IsCombatLocked() then return false end
    RefreshTrackedRow(frame, owner or DEFAULT_OWNER, mode)
    return true
end

function GenericWindows.ApplyFrame(frame, owner, mode)
    owner = owner or DEFAULT_OWNER
    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-frame:" .. OwnerKey(owner) .. ":" .. tostring(frame)
        ownerState.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            ApplyFrameNow(frame, owner, mode)
        end)
        return false, "combat"
    end
    return ApplyFrameNow(frame, owner, mode)
end

Shared.CatalogMode = CatalogMode
Shared.ApplyFrameNow = ApplyFrameNow

return GenericWindows
