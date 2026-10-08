local _, Suite = ...

-- The Suite's half of Menu2's widget protocol: the per-widget fields MSUF's
-- menu reads and writes on its own controls, sections and navigation (undo
-- checkpoints, combat clicks, exact search preparation, section header
-- reserves, layout cursors, nav icons). This file is the only place in the
-- Suite that knows those field names. A Menu2 with host API v2
-- (M.HOST_API_VERSION >= 2, MSUF_Menu2_HostProtocol.lua) owns them behind its
-- own functions; an older Menu2 gets the Suite's previous field writes, kept
-- here unchanged. Both give the same fields, so a page behaves the same on
-- every host. The adapter is built once per Menu2 table (the options load
-- after MSUF's menu, Menu/Bridge.lua asks for it first) and the pages call
-- its functions: cold menu code, nothing allocated per call.
local HostBridge = Suite.HostBridge
Suite.HostBridge = HostBridge

local MENU_API_VERSION = 2
local pairs, rawget, tonumber, type = pairs, rawget, tonumber, type

-- Every v2 entry point the adapter binds; a host that lacks one gets the
-- legacy adapter as a whole.
local NAMES = {
    "SkipHistoryCheckpoint", "AllowCombatClick", "SetSearchTargetPrepare", "GetSearchTargetPrepare",
    "SetCommandAction", "GetControlTitle", "GetControlLabel", "GetControlSearchMeta", "GetRawSetText",
    "ReleaseColorShortcut",
    "GetSectionEntry", "SetSectionEntry", "GetSectionWidth", "SetSectionWidth", "GetSectionCursor",
    "SetSectionCursor", "MarkContextColorHost", "SetFixedPreviewHeight", "SetBuilderInsets",
    "SetSectionEnsureVisible", "GetSectionEnsureVisible", "SetSectionRefreshState", "GetSectionRefreshState",
    "SetMissingSectionResolver", "GetMissingSectionResolver", "ReserveSectionActions", "RefreshSectionLayout",
    "SetSectionPopupGetter", "AddNavIcon",
}
HostBridge.MENU_NAMES = NAMES

------------------------------------------------------------------ legacy
-- The previous field writes, one function per protocol step.
local L = {}
function L.SkipHistoryCheckpoint(widget)
    widget._msuf2SkipHistoryCheckpoint = true
    return widget
end
function L.AllowCombatClick(widget)
    widget._msuf2AllowCombatClick = true
    return widget
end
function L.SetSearchTargetPrepare(widget, prepare)
    widget._msuf2PrepareExactSearchTarget = prepare
    return widget
end
function L.GetSearchTargetPrepare(widget) return widget._msuf2PrepareExactSearchTarget end
function L.SetCommandAction(widget, action)
    widget._msuf2CommandAction = action
    return widget
end
function L.GetControlTitle(widget) return widget._msuf2Title end
function L.GetControlLabel(widget) return rawget(widget, "_msuf2Label") end
function L.GetControlSearchMeta(widget) return widget._msuf2SearchMeta end
function L.GetRawSetText(fontString) return fontString._msuf2RawSetText end
function L.ReleaseColorShortcut(shortcut) shortcut._msuf2BoundColorShortcut = nil end

function L.GetSectionEntry(frame) return frame._msuf2CollapsibleEntry end
function L.SetSectionEntry(frame, entry) frame._msuf2CollapsibleEntry = entry end
function L.GetSectionWidth(frame) return frame._msuf2Width end
function L.SetSectionWidth(frame, width) frame._msuf2Width = width end
function L.GetSectionCursor(frame) return frame._msuf2CursorY end
function L.SetSectionCursor(frame, y) frame._msuf2CursorY = y end
function L.MarkContextColorHost(frame) frame._msuf2ContextColorHost = true end
function L.SetFixedPreviewHeight(frame, height) frame._msuf2FixedPreviewActiveHeight = height end
function L.SetBuilderInsets(ctx, contentX, topInset)
    ctx._msuf2ContentX, ctx._msuf2TopInset = contentX, topInset
    return ctx
end

function L.SetSectionEnsureVisible(entry, ensure) entry._msuf2EnsureVisible = ensure end
function L.GetSectionEnsureVisible(entry) return entry._msuf2EnsureVisible end
function L.SetSectionRefreshState(entry, refresh) entry._msuf2RefreshState = refresh end
function L.GetSectionRefreshState(entry) return entry._msuf2RefreshState end
function L.SetMissingSectionResolver(entry, resolve) entry._msuf2ResolveMissingSection = resolve end
function L.GetMissingSectionResolver(entry) return entry._msuf2ResolveMissingSection end
-- MSUF's header layout keeps the reserve right of the feature switch; a
-- header without a summary row places it by the swatch reserve alone.
function L.ReserveSectionActions(entry, button, width)
    entry._msuf2SectionActions = button
    entry._msuf2ActionReserve = width
    if not entry._msuf2UXSummary then
        entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + width
    end
end
function L.RefreshSectionLayout(entry)
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
end
function L.SetSectionPopupGetter(button, getPopup) button._msuf2GetSectionPopup = getPopup end

-- The HD atlas (version 2) has a cell per Suite page; older atlases keep
-- the page's own cell. A key MSUF already styles keeps its icon and color.
local function LegacyNavIcon(T, pageKey, spec)
    local grid, colors = T.navIconGrid, T.navIconColors
    if type(grid) ~= "table" or type(colors) ~= "table" then return false end
    local neutral = colors.gameplay or colors.profiles
    local accent = colors.home or neutral
    local icon = (tonumber(T.navIconAtlasVersion) or 0) >= 2 and spec.hdIcon or spec.icon
    local added = false
    if icon and grid[pageKey] == nil then
        grid[pageKey] = icon
        added = true
    end
    if colors[pageKey] == nil then
        colors[pageKey] = spec.accent and accent or neutral
        added = true
    end
    return added
end

------------------------------------------------------------------ resolution
local function HasMenuAPI(M)
    if type(M.HOST_API_VERSION) ~= "number" or M.HOST_API_VERSION < MENU_API_VERSION then return false end
    for index = 1, #NAMES do
        if type(M[NAMES[index]]) ~= "function" then return false end
    end
    return true
end

local function Build(M)
    if not HasMenuAPI(M) then
        local adapter, T = { mode = "legacy" }, M.Theme
        for name, step in pairs(L) do adapter[name] = step end
        adapter.AddNavIcon = function(pageKey, spec) return LegacyNavIcon(T, pageKey, spec) end
        return adapter
    end
    local adapter = { mode = "host" }
    for index = 1, #NAMES do adapter[NAMES[index]] = M[NAMES[index]] end
    return adapter
end

local adapters = setmetatable({}, { __mode = "k" })

-- The adapter for one Menu2 table: its v2 functions, or the legacy writes.
-- adapter.mode is "host" or "legacy".
function HostBridge.Menu2(M)
    local adapter = adapters[M]
    if not adapter then
        adapter = Build(M)
        adapters[M] = adapter
    end
    return adapter
end

-- Installer chrome can open before the load-on-demand options. Resolve at
-- paint time: caching an absent Menu2 would miss the menu loaded later.
function HostBridge.MenuAppearance()
    local menu = _G.MSUF2
    if type(menu) == "table" and type(menu.Theme) == "table" then return menu.Theme end
    local ui = _G.MSUF_UI
    return type(ui) == "table" and ui or nil
end

-- Core shared UI and Menu2 have different public renderer sets; older
-- hosts may expose only colors. Keep those capabilities at this boundary,
-- resolving on each cold paint so a late Options load can provide them.
local function AppearanceAction(theme, name)
    local action = theme and theme[name]
    if type(action) == "function" then return action end
end

function HostBridge.MenuColor(token, alternate)
    local theme = HostBridge.MenuAppearance()
    local colors = theme and theme.colors
    local color = colors and (colors[token] or colors[alternate])
    local get = AppearanceAction(theme, "Color")
    return color or (get and get(token))
end

function HostBridge.MenuMaterial(frame, material)
    local apply = AppearanceAction(HostBridge.MenuAppearance(), "ApplyMaterial")
    if not apply then return false end
    apply(frame, material)
    return true
end

function HostBridge.MenuButton(parent, width, height)
    local create = AppearanceAction(HostBridge.MenuAppearance(), "Button")
    return create and create(parent, "", width, height) or nil
end

function HostBridge.MenuFont(label, color, role)
    local theme = HostBridge.MenuAppearance()
    local style = AppearanceAction(theme, "StyleFontString")
    if style then
        style(label, color, nil, role)
        return true
    end
    local apply = AppearanceAction(theme, "ApplyFontRole")
    if apply then apply(label, role, nil, "") end
    return false
end

-- Public UI buttons own their hover/selection painter and the skin's
-- corresponding control material. The label's legacy fields stay here.
function HostBridge.MenuButtonLabel(button)
    local menu = _G.MSUF2
    local get = type(menu) == "table" and menu.GetControlLabel
    return type(get) == "function" and get(button) or button._msuf2Label or button._label
end

local appearanceListeners = setmetatable({}, { __mode = "k" })
function HostBridge.WatchMenuAppearance(owner, callback)
    local watched = appearanceListeners[owner]
    if not watched then
        watched = {}
        appearanceListeners[owner] = watched
    end
    -- The already loaded skin's public listener signals look, palette and
    -- profile changes on both cold shared UI and the loaded Menu2.
    -- Querying its API neither loads the optional addon nor activates it.
    local skin = _G.MapkoSkin
    if type(skin) ~= "table" or type(skin.GetAPI) ~= "function" then return end
    local api = skin.GetAPI(2, 1)
    if type(api) == "table" and type(api.OnAppearanceChanged) == "function" then
        if not watched[api] then
            -- OnAppearanceChanged follows the skin's queued palette changes.
            -- The view coalesces repaint after core listeners finish too.
            hooksecurefunc(api, "OnAppearanceChanged", callback)
            watched[api] = true
        end
        return
    end
    api = skin.GetAPI(1, 0)
    if type(api) == "table" and type(api.OnThemeChanged) == "function" and not watched[api] then
        api.OnThemeChanged(owner, callback)
        watched[api] = true
    end
end

return HostBridge
