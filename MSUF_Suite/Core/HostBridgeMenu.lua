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
-- A page with multiple editor selectors needs a larger compact reservation.
-- Keep the sticky host and its expander on the same size on old/v2 hosts.
function L.SetFixedPreviewCompactHeight(frame, height)
    frame._msuf2FixedPreviewActiveHeight = height
    frame._msuf2FixedPreviewHeight = height
    frame._msuf2FixedPreviewCompactHeight = height
    local record = frame._msuf2FixedPagePreviewRecord
    if record then
        record.fixedHeight = height
        -- Closing the expander clears ActiveHeight; the host's original
        -- resolver otherwise falls back to its smaller, clamped height.
        record.heightResolver = function() return tonumber(frame._msuf2FixedPreviewActiveHeight) or height end
    end
    frame:SetHeight(height)
end
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
    local adapter = { mode = "host", SetFixedPreviewCompactHeight = L.SetFixedPreviewCompactHeight }
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

-- MSUF's Icon Skins page (Style > Icon Skins, MSUF 7.0: M.IconSkinsPage)
-- lists the Suite's icon areas under "Where It Applies" (Page.RegisterArea;
-- spec fields in MSUF_Menu2_IconSkins.lua). Older hosts have no page, and a
-- host with the page but without the painter the Suite draws with
-- (HostBridge.IconSkins) gets no areas either: nothing there could show the
-- skin. Returns how many areas the page took.
function HostBridge.HasIconSkinAreas(M)
    local page = M and M.IconSkinsPage
    return not not (page and page.RegisterArea and HostBridge.IconSkins())
end
function HostBridge.RegisterIconSkinAreas(M, specs)
    if not HostBridge.HasIconSkinAreas(M) then return 0 end
    local register = M.IconSkinsPage.RegisterArea
    local added = 0
    for i = 1, #specs do
        if register(specs[i]) then added = added + 1 end
    end
    return added
end

-- The row MSUF's Icon Skins page offers module pages (Page.StatusRow): the
-- skin an area shows, a hint and the button to the page; skins are chosen
-- only there. `key` is an area key. Returns the row's height, or 0 where the
-- host offers none (also without the painter: the row would name a skin no
-- Suite icon shows).
function HostBridge.IconSkinStatusRow(M, ctx, parent, x, y, width, key)
    local page = M and M.IconSkinsPage
    local row = page and page.StatusRow
    if not row or not HostBridge.IconSkins() then return 0 end
    return row(ctx, parent, x, y, width, key) or 0
end

-- The same for a page with a bar selector: keyFn returns the selected bar's
-- area key; only hosts that mark Page.STATUS_ROW_KEY_FUNCTION take one.
function HostBridge.IconSkinStatusRowFor(M, ctx, parent, x, y, width, keyFn)
    local page = M and M.IconSkinsPage
    if not (page and page.STATUS_ROW_KEY_FUNCTION) then return 0 end
    return HostBridge.IconSkinStatusRow(M, ctx, parent, x, y, width, keyFn)
end

-- Only hosts offering the optional Aura appearance slot receive this menu.
-- A private reset key uses the host's validated provider protocol without
-- claiming any of its existing Buff/Debuff pages.
function HostBridge.HasPlayerAuraMenu(M)
    local page = M.AurasPage
    return not not (page and page.RegisterAppearanceType)
end
function HostBridge.RegisterPlayerAuraMenu(M, spec)
    local page = M.AurasPage
    if not (page and page.RegisterAppearanceType) then return false end
    M.RegisterPageResetProvider("MSUF_Suite.PlayerAuras", {
        pages = { suite_playerAuras = true }, canReset = spec.canReset,
        warning = spec.warning, historyLabel = spec.historyLabel, prepare = spec.prepare, finish = spec.finish,
        reset = function()
            if not M.ResetBlizzardAuraVisibility() then return false end
            return spec.reset()
        end,
    })
    return page.RegisterAppearanceType("blizzardPlayer", {
        text = spec.text, description = spec.description, build = spec.build,
        blizzardVisibility = true, resetProvider = M.PageResetProviders.suite_playerAuras,
    })
end
function HostBridge.SelectPlayerAuraMenu(M, visibilitySetting, legacyControl)
    local page = M.AurasPage
    if not (page and page.AppearanceType and page.AppearanceType("blizzardPlayer")) then return false end
    M.SetMenuStateValue("auraAppearanceContainer", "blizzardPlayer")
    if (not visibilitySetting or visibilitySetting == "") and legacyControl then
        if legacyControl:match("%.hide%-buffs$") then visibilitySetting = "auras3.shared.hideBlizzardBuffFrame"
        elseif legacyControl:match("%.hide%-debuffs$") then visibilitySetting = "auras3.shared.hideBlizzardDebuffFrame" end
    end
    return true, visibilitySetting and page.BlizzardVisibilityControlId(visibilitySetting)
end

-- Installer chrome can open before the load-on-demand options. Resolve at
-- paint time: caching an absent Menu2 would miss the menu loaded later.
local function LoadedMenu() return _G.MSUF2 end

-- A pending welcome lives in Options; until its menu opens it owns no screen.
function HostBridge.FirstRunVisible()
    local menu = LoadedMenu()
    return menu and menu.frame and menu.frame:IsShown() and HostBridge.FirstRunPending() or false
end

-- A cold skin action need not load Options. A later menu supplies history;
-- its result, including nil, is final and never runs the callback twice.
function HostBridge.WithMenuHistory(label, source, callback)
    local menu = LoadedMenu()
    if menu and type(menu.RunWithHistory) == "function" then
        return menu.RunWithHistory(label, source, callback)
    end
    return callback()
end

function HostBridge.MenuAppearance()
    local menu = LoadedMenu()
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

local FOCUS_TEXTURES = {
    "_msuf2FocusDim", "_msuf2FocusHaze", "_msuf2FocusSmearA",
    "_msuf2FocusSmearB", "_msuf2FocusWash", "_msuf2FocusGrain",
}

-- The translucent veil bypasses the material adapter, which paints panels.
-- A cold host never loads Options just to supply this optional painter.
function HostBridge.MenuFocusVeil(frame, variant)
    local apply = AppearanceAction(HostBridge.MenuAppearance(), "ApplyFocusVeil")
    if apply then apply(frame, variant or "dropdown") return true end
    for index = 1, #FOCUS_TEXTURES do
        local texture = frame[FOCUS_TEXTURES[index]]
        if texture then texture:Hide() end
    end
    return false
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
    local menu = LoadedMenu()
    local get = type(menu) == "table" and menu.GetControlLabel
    return type(get) == "function" and get(button) or button._msuf2Label or button._label
end

-- Both renderers build MSUF's window close button from the parent alone.
function HostBridge.MenuCloseButton(parent)
    local create = AppearanceAction(HostBridge.MenuAppearance(), "CloseButton")
    return create and create(parent) or nil
end

------------------------------------------------------------------ menu kit
-- Suite windows (the Adventure planner) wear Menu2's own chrome: its shell,
-- rail and host surfaces, navigation pills with atlas icons, collapse arrows
-- and search field. Menu2's theme ships in MSUF's load-on-demand options
-- addon; a window loads it on an explicit open only, never in combat.
local HOST_OPTIONS = "MidnightSimpleUnitFrames_Options"

local function MenuTheme()
    local menu = LoadedMenu()
    local theme = type(menu) == "table" and menu.Theme
    return type(theme) == "table" and theme or nil, menu
end

function HostBridge.EnsureMenuTheme()
    if MenuTheme() then return true end
    if InCombatLockdown() or Suite.Client.IsAddOnLoaded(HOST_OPTIONS) then return false end
    C_AddOns.LoadAddOn(HOST_OPTIONS)
    return MenuTheme() ~= nil
end

-- Menu2's backdrop textures and logo watermark across shell, host and rail.
function HostBridge.MenuAtmosphere(frame, host, rail)
    local apply = AppearanceAction(MenuTheme(), "ApplyMenuAtmosphere")
    if apply then apply(frame, host, rail) end
    return apply ~= nil
end

-- A rail pill as Menu2 builds its own: the nav-item painter (no fill at
-- rest, Menu2's hover and selected pill), with room for an atlas icon
-- (MenuNavIcon). List rows use it too.
function HostBridge.MenuNavButton(parent, width, height)
    local create = AppearanceAction(MenuTheme(), "Button")
    if not create then return nil end
    local button = create(parent, "", width, height)
    button._msuf2NavItem, button._msuf2SkipHistoryCheckpoint = true, true
    if button.RefreshVisual then button:RefreshVisual() end
    return button
end

-- Shows the icon of MSUF's HD atlas cell { column, row } on a rail pill,
-- registered under key like the Suite's own pages.
function HostBridge.MenuNavIcon(button, key, cell)
    local theme, menu = MenuTheme()
    local attach = AppearanceAction(theme, "AttachNavIcon")
    if not attach or not menu then return false end
    HostBridge.Menu2(menu).AddNavIcon(key, { hdIcon = cell })
    attach(button, key, false, true)
    return true
end

-- Menu2's caret texture; kind "nav" paints a rail group title, otherwise a
-- section header. Returns false when Menu2 is absent.
function HostBridge.MenuArrow(arrow, open, kind)
    local theme = MenuTheme()
    local media = theme and theme.media
    if not (media and media.collapseArrow and theme.colors) then return false end
    if arrow.plannerArrowTexture ~= theme.media.collapseArrow then
        arrow:SetTexture(theme.media.collapseArrow)
        arrow.plannerArrowTexture = theme.media.collapseArrow
    end
    if kind ~= "nav" then
        local apply = AppearanceAction(theme, "ApplyCollapseVisual")
        if apply then apply(arrow, nil, open) end
        return apply ~= nil
    end
    local c = open and theme.colors.navArrowOpen or theme.colors.navArrowClosed
    arrow:SetRotation(open and (math.pi * 0.5) or 0)
    if c then arrow:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return true
end

-- Menu2's rounded search input (the rail's own recipe).
function HostBridge.MenuEditBox(edit)
    local theme = MenuTheme()
    local skin, layers = AppearanceAction(theme, "SkinEditBox"), AppearanceAction(theme, "CreateSuperellipseLayers")
    if not skin then return false end
    skin(edit)
    if layers then
        local fill, edge = layers(edit, "_msuf2SearchEdit", 2, "BACKGROUND", "BORDER")
        edit._msuf2RoundedEditFill, edit._msuf2RoundedEditEdge = fill, edge
        if edit._msuf2PaintEditBox then edit._msuf2PaintEditBox(edit, false) end
    end
    return true
end

-- Sizes a public pill to its translated label within [minimum, maximum].
function HostBridge.MenuFitButton(button, minimum, maximum)
    local fit = AppearanceAction(MenuTheme(), "FitButtonWidth")
    if fit then fit(button, minimum, maximum) end
    return fit ~= nil
end

-- MSUF's reduced-motion preference: Menu2's reader once it is loaded, before
-- that the profile fields MSUF's core reads too.
function HostBridge.MenuReducedMotion()
    local reduced = AppearanceAction(HostBridge.MenuAppearance(), "ReducedMotionEnabled")
    if reduced then return reduced() == true end
    local db = HostBridge.CurrentFrameProfile()
    local general = type(db) == "table" and db.general
    return type(general) == "table" and (general.reduceMotion == true or general.reducedMotion == true)
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

-- Install once on the already loaded Menu2. Pending search skeletons never
-- fade; the completed renderer signal follows the final result paint.
local contentWatchers = setmetatable({}, { __mode = "k" })
function HostBridge.WatchMenuContent(menu, callback, register)
    if contentWatchers[menu] or not AppearanceAction(menu, "SelectPage") then return end
    local serial, lastPage, lastResults, lastTarget = 0
    local watched = setmetatable({}, { __mode = "k" })
    local function Shown(frame)
        local key = watched[frame]
        if key == "search" then
            if menu.searchResultsPending then callback(frame, false) return end
            lastResults = menu.searchResults
        end
        lastPage, lastTarget, serial = key, frame, serial + 1
        callback(frame, serial)
    end
    local function Watch(frame, key)
        if watched[frame] then return end
        watched[frame] = key
        frame:HookScript("OnShow", Shown)
    end
    local function Painted()
        local key = menu.activeKey
        local entry = menu.cache and menu.cache[key]
        if not entry then return end
        local target, token = entry.wrapper, entry
        if key == "search" then
            local view = entry._msuf2SearchView
            target, token = view and view.results, menu.searchResults
            if menu.searchResultsPending then
                if target then callback(target, false) end
                return
            end
            if token == lastResults and key == lastPage and target == lastTarget then return end
            lastResults = token
        elseif key == lastPage and target == lastTarget then return end
        if not target then return end
        Watch(target, key)
        lastPage, lastTarget, serial = key, target, serial + 1
        callback(target, serial)
    end
    hooksecurefunc(menu, "SelectPage", Painted)
    local widgets = menu.Widgets
    if register and AppearanceAction(widgets, "SegmentTabs") then
        hooksecurefunc(widgets, "SegmentTabs", function(_, _, options)
            for _, frame in pairs(options and options.frames or {}) do register(frame) end
        end)
    end
    local render = menu.Search and menu.Search._Render
    if AppearanceAction(render, "ShowSearchPage") then
        hooksecurefunc(render, "ShowSearchPage", Painted)
    end
    contentWatchers[menu] = true
end

-- Only the Options window refuses every combat open and hides at the combat
-- edge. Its hidden art can wait for OnShow; Edit Mode and other public skin
-- clients retain eager preparation, including controls first shown in combat.
function HostBridge.IsOptionsSurface(frame)
    local root = _G.MSUF2_Window
    if not root then return false end
    for _ = 1, 32 do
        if not Suite.Public(frame) or type(frame) ~= "table" then return false end
        if frame == root then return true end
        local isForbidden = AppearanceAction(frame, "IsForbidden")
        if isForbidden then
            local forbidden = isForbidden(frame)
            if not Suite.Public(forbidden) or forbidden then return false end
        end
        local getParent = AppearanceAction(frame, "GetParent")
        if not getParent then return false end
        frame = getParent(frame)
    end
    return false
end

-- Older hosts expose the same routing function through their search facade.
-- Keep the compatibility wrapper local to this adapter; no Blizzard table is touched.
local targetResolvers = {}
function HostBridge.RegisterSearchTargetResolver(menu, name, resolver)
    if menu.RegisterSearchTargetResolver then return menu.RegisterSearchTargetResolver(name, resolver) end
    local routing = menu.Search and menu.Search._RoutingAPI
    if not routing or not routing.OpenSearchTarget then return false end
    local handlers = targetResolvers[menu]
    if not handlers then
        handlers = {}
        targetResolvers[menu] = handlers
        local original = routing.OpenSearchTarget
        routing.OpenSearchTarget = function(page, query, fallback, anchor, route, target)
            if not (menu.frame and menu.frame.IsShown and menu.frame:IsShown()) then return false, false, false end
            for _, handler in pairs(handlers) do
                local nextPage, nextTarget, nextRoute = handler(page, target)
                if nextPage == false then return false, false, false end
                if nextPage then page, target, route, anchor = nextPage, nextTarget, nextRoute, nil end
            end
            return original(page, query, fallback, anchor, route, target)
        end
    end
    handlers[name] = resolver
    return true
end

-- Older supported menus already own Gameplay and its builder/history, but
-- predate page extensions. Adapt those public page callbacks only while Suite
-- is loaded; keep their settings, navigation identity and original build.
local legacyExtensions = setmetatable({}, { __mode = "k" })

local function ExtensionEnabled(record, key)
    local provider = record.provider
    return not provider.canReset or Suite.Dispatch(provider.canReset, key) == true
end

local function InstallExtensionResets(menu, records)
    local reset, warning = menu.ResetPageToDefaults, menu.BuildPageResetWarning
    menu.BuildPageResetWarning = function(key)
        local message = warning(key)
        local record = records[key]
        if record and ExtensionEnabled(record, key) and record.provider.warning then
            local extra = Suite.Dispatch(record.provider.warning, key)
            if extra then message = message and (message .. "\n\n" .. extra) or extra end
        end
        return message
    end
    menu.ResetPageToDefaults = function(key)
        local record = records[key]
        if not record or not ExtensionEnabled(record, key) then return reset(key) end
        local provider = record.provider
        if Suite.InCombat() then return false end
        if provider.prepare and Suite.Dispatch(provider.prepare, key) ~= true then return false end
        menu.SyncExternalHistoryState()
        local label = string.format(menu.Tr("Reset %s"), menu.Tr(menu.pages[key].title))
        local translated = AppearanceAction(menu, "TranslatedHistoryLabel")
        if translated then label = translated(label) end
        local success = false
        local committed = menu.RunWithHistory(label, "page:reset:" .. key, function()
            if reset(key) ~= true then return false end
            success = Suite.Dispatch(provider.reset, key) == true
            -- The host may already have changed; retain one undo entry even
            -- when the extension reports a partial failure.
            return true
        end)
        if committed and provider.finish then Suite.Dispatch(provider.finish, key) end
        return committed == true and success
    end
end

local function BuildLegacyExtension(menu, record, ctx)
    record.build(ctx)
    for _, builder in ipairs(ctx._msuf2PageBuilders or {}) do
        if builder.parent == ctx.wrapper then
            Suite.Dispatch(record.provider.build, ctx, builder)
            ctx:SetContentHeight(math.abs(builder.y) + 42)
            return
        end
    end
end

local function RegisterLegacyExtension(menu, page, name, provider)
    local spec = menu.pages and menu.pages[page]
    if not AppearanceAction(spec, "build") or not AppearanceAction(menu, "ResetPageToDefaults") then return false end
    local records = legacyExtensions[menu]
    if not records then
        records = {}
        legacyExtensions[menu] = records
        InstallExtensionResets(menu, records)
    end
    local record = records[page]
    if record then
        if record.name ~= name then return false end
        if record.provider == provider then return true end
        record.provider = provider
    else
        record = { name = name, provider = provider, build = spec.build }
        records[page] = record
        local extended = {}
        for key, value in pairs(spec) do extended[key] = value end
        extended.build = function(ctx) BuildLegacyExtension(menu, record, ctx) end
        menu.RegisterPage(page, extended)
        spec = extended
    end
    spec.version = (tonumber(spec.version) or 0) + 1
    if not Suite.InCombat() and menu.activeKey == page and menu.RebuildPageKeepingScroll then
        menu.RebuildPageKeepingScroll(page)
    end
    return true
end

-- Hosts that identify Suite controls by page name alone add raw module IDs
-- to every detail after it moves to Gameplay. Suite already supplies its own
-- feature aliases and detail terms; keep that ownership on embedded pages too.
local searchContexts = setmetatable({}, { __mode = "k" })
local function KeepSuiteSearchTerms(menu)
    local text = menu.Search and menu.Search.Text
    local context = AppearanceAction(text, "ControlContext")
    if not context or searchContexts[text] then return end
    searchContexts[text] = context
    text.ControlContext = function(value, ...)
        local key = tostring(value or "")
        if key:sub(1, 10) == "msufsuite." or key:sub(1, 20) == "suite_qualityOfLife_" then return "" end
        return context(value, ...)
    end
end

-- Additive host capabilities keep extension runtimes in their owning addon.
function HostBridge.RegisterPageExtension(menu, page, name, provider)
    KeepSuiteSearchTerms(menu)
    if not AppearanceAction(menu, "RegisterPageExtension") or not AppearanceAction(menu, "BuildPageExtensions") then
        return RegisterLegacyExtension(menu, page, name, provider)
    end
    return menu.RegisterPageExtension(page, name, provider) == true
end

-- Some host pages do not call BuildPageExtensions. Append through their
-- existing builder without requiring that opt-in, including on newer hosts.
function HostBridge.RegisterPageTail(menu, page, name, provider)
    KeepSuiteSearchTerms(menu)
    return RegisterLegacyExtension(menu, page, name, provider)
end

local menuStateFallbacks = setmetatable({}, { __mode = "k" })
function HostBridge.GetPersistentMenuState(menu, name)
    if AppearanceAction(menu, "GetPersistentMenuStateTable") then return menu.GetPersistentMenuStateTable(name) end
    local states = menuStateFallbacks[menu]
    if not states then states = {} menuStateFallbacks[menu] = states end
    if not states[name] then states[name] = {} end
    return states[name]
end

-- Unpainted layout blocks let embedded options use the host's own accordions.
-- They participate in the same flow as existing sections without a second card.
function HostBridge.MenuFlowSection(builder, height, gap)
    local frame = CreateFrame("Frame", nil, builder.parent)
    frame:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x or 0, builder.y)
    frame:SetSize(builder.width, height)
    frame._msuf2Width, frame._msuf2CursorY = builder.width, -height
    builder._collapsibleStartY = builder._collapsibleStartY or builder.y
    builder.layoutEntries[#builder.layoutEntries + 1] = { kind = "section", frame = frame, gap = gap or 8 }
    builder.y = builder.y - height - (gap or 8)
    return frame
end

-- Filter only the flow list, retaining each native accordion and its state.
function HostBridge.SetMenuFlowEntries(builder, entries)
    local layout = builder.layoutEntries
    local count = #entries
    -- Released hosts fall back to all collapsibles when the flow list is empty.
    -- Keep an invisible zero-height entry so an empty filter stays empty.
    if count == 0 and not builder._msufSuiteEmptyFlow then
        local frame = CreateFrame("Frame", nil, builder.parent)
        frame:SetSize(builder.width, 0)
        frame:Hide()
        builder._msufSuiteEmptyFlow = { kind = "section", frame = frame, gap = 0 }
    end
    count = math.max(1, count)
    local changed = #layout ~= count
    for index = 1, count do
        local entry = entries[index] or builder._msufSuiteEmptyFlow
        if layout[index] ~= entry then changed = true end
        layout[index] = entry
    end
    for index = #layout, count + 1, -1 do layout[index] = nil end
    if changed or builder._msuf2RelayoutPending then builder:RelayoutCollapsibles() end
end

return HostBridge
