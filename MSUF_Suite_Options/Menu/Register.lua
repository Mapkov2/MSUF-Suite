local _, P = ...
local Suite, M, S = P.Suite, P.M, P.S
-- Suite pages join MSUF's navigation groups by id, in this order. Each page
-- names its group and its place there (nav, navOrder of P.RegisterPage). A
-- host menu without a group (Retail MSUF still has Appearance and Features)
-- uses the fallback group, or gets the group title in front of its last group.
local NAV_GROUPS = {
    { id = "combat", title = "Combat" },
    { id = "interface", title = "Interface" },
    { id = "style", title = "Style", fallback = "appearance" },
    { id = "general", title = "General", fallback = "features", after = "gameplay" },
}
if type(M.RegisterHistoryProvider) == "function" then
    P.historyRegistered = M.RegisterHistoryProvider("MSUF_Suite", P.CaptureHistoryState, P.RestoreHistoryState) == true
end

-- The HD host atlas gives each Suite destination its own recognizable symbol.
-- Older hosts retain their existing atlas cells (HostBridgeMenu AddNavIcon).
local HD_NAV_ICONS = {
    suite_nameplates = { 0, 3 }, suite_cooldownManager = { 1, 3 },
    suite_buffReminders = { 2, 3 }, suite_hud = { 3, 3 },
    suite_actionbars = { 4, 3 }, suite_minimap = { 5, 3 },
    suite_damageMeter = { 6, 3 }, suite_bags = { 7, 3 },
    suite_chat = { 0, 4 }, suite_dataTexts = { 1, 4 },
    suite_skin = { 2, 4 }, suite_qualityOfLife = { 3, 4 },
}
local function AddIcons()
    for _, page in ipairs(P.pages) do
        P.HM.AddNavIcon(page.key, { icon = page.icon, hdIcon = HD_NAV_ICONS[page.key], accent = page.accent })
    end
end

-- Keep unavailable destinations visible and clickable so they can explain how
-- to turn the AddOn on. A saved module switch and Blizzard's AddOn switch are
-- separate: dormant load-on-demand modules still need their settings page.
local ADDON_NOTICE = "You need to turn on the module in Blizzard's AddOn list"
-- Every catalog module per page; the page reset and the AddOn checks use it.
local PAGE_MODULES = {}
for _, id in ipairs(Suite.SuiteOrder) do
    local key = P.catalog[id].page
    if key then
        local modules = PAGE_MODULES[key] or {}
        PAGE_MODULES[key] = modules
        modules[#modules + 1] = id
    end
end
local function PageAddOnEnabled(key)
    if key == "suite_skin" then return Suite.Client.AddOnEnabled("MSUF_Suite_Skin") end
    local modules = PAGE_MODULES[key]
    if not modules then return true end
    for _, id in ipairs(modules) do
        if Suite.Client.AddOnEnabled(P.catalog[id].addon) then return true end
    end
    return false
end
local function PageEnabled(key)
    if not PageAddOnEnabled(key) then return false, ADDON_NOTICE end
    if key == "suite_skin" then
        return P.SkinningEnabled() == true and Suite.Client.IsAddOnLoaded("MSUF_Suite_Skin"), "Off"
    end
    local modules = PAGE_MODULES[key]
    if not modules then return true end
    for _, id in ipairs(modules) do
        local addon = P.catalog[id].addon
        if S.Config(id).enabled == true and Suite.Client.AddOnEnabled(addon)
            and Suite.Client.IsAddOnLoaded(addon) then return true end
    end
    return false, "Off"
end
local function NavRow(page, group)
    return {
        key = page.key, label = page.label, group = group,
        availability = function() return PageEnabled(page.key) end,
    }
end

local function FindTitle(items, id)
    for i, item in ipairs(items) do
        if item.title and item.id == id then return i end
    end
end

-- Resolves the group a spec's pages join, creating its title when the host
-- has neither the group nor its fallback.
local function ResolveGroup(items, spec)
    if FindTitle(items, spec.id) then return spec.id end
    if spec.fallback and FindTitle(items, spec.fallback) then return spec.fallback end
    local at = #items + 1
    for i = #items, 1, -1 do
        if items[i].title then
            at = i
            break
        end
    end
    table.insert(items, at, { title = spec.title, id = spec.id })
    return spec.id
end

-- Row index a new page of `group` goes after: the `after` page when the group
-- holds it, else the group's last row (its title while it is empty).
local function InsertIndex(items, group, after)
    local last = FindTitle(items, group)
    for i = last + 1, #items do
        local item = items[i]
        if item.title or item.header then break end
        if item.group == group then
            last = i
            if after and item.key == after then break end
        end
    end
    return last
end

-- The page keys of one navigation group, in their declared order.
local function GroupPages(group)
    local pages = {}
    for _, page in ipairs(P.pages) do
        if page.nav == group then pages[#pages + 1] = page end
    end
    table.sort(pages, function(a, b) return a.navOrder < b.navOrder end)
    for i, page in ipairs(pages) do pages[i] = page.key end
    return pages
end

-- Navigation rows are inserted in place (other Menu2 files hold references
-- to these tables).
local function AddNavigation()
    local items = M.navItems
    if type(items) ~= "table" then return false end
    local pagesByKey = {}
    for _, page in ipairs(P.pages) do pagesByKey[page.key] = page end
    for _, item in ipairs(items) do
        if item.key and pagesByKey[item.key] then return true end
    end
    local placed = {}
    local function Place(spec, keys)
        local group = ResolveGroup(items, spec)
        local after = spec.after
        for _, key in ipairs(keys) do
            local page = pagesByKey[key]
            if page and not placed[key] then
                table.insert(items, InsertIndex(items, group, after) + 1, NavRow(page, group))
                placed[key], after = true, key
            end
        end
    end
    for _, spec in ipairs(NAV_GROUPS) do Place(spec, GroupPages(spec.id)) end
    -- A page without a known group still gets a row, at the end of Interface.
    for _, page in ipairs(P.pages) do
        if not placed[page.key] then Place(NAV_GROUPS[2], { page.key }) end
    end
    if type(M.navPrimaryForKey) == "table" then
        for _, page in ipairs(P.pages) do M.navPrimaryForKey[page.key] = page.key end
    end
    if type(M.ALIASES) == "table" then
        for _, page in ipairs(P.pages) do
            if M.ALIASES[page.key] == nil then M.ALIASES[page.key] = page.key end
            for _, alias in ipairs(page.aliases or {}) do
                if M.ALIASES[alias] == nil then M.ALIASES[alias] = page.key end
            end
        end
    end
    return true
end

-- Each refresh pass of a Suite page starts with fresh module availability
-- (Bridge.lua): the first refresher a page registers clears it.
local function PageBuilder(page)
    return function(ctx, ...)
        M.TrackRefresh(ctx, P.ForgetAvailability)
        if not PageAddOnEnabled(page.key) then
            local notice = P.Text(ctx.wrapper, ADDON_NOTICE, 16, -20, math.max(240, (ctx.width or 720) - 32))
            local height = notice:GetStringHeight() + 48
            -- A page may keep actions below it that need no module of its
            -- own (Skinning: Pages/Appearance.lua).
            if page.notice then height = 12 - page.notice(ctx, 20 - height) end
            ctx:SetContentHeight(height)
            return
        end
        return page.build(ctx, ...)
    end
end

local function RegisterPages()
    for _, page in ipairs(P.pages) do
        M.RegisterPage(page.key, { title = page.title, build = PageBuilder(page), version = 1 })
    end
end

-- Menu2 owns the toolbar and confirmation UI. Suite pages take part in its
-- page reset through the Suite's host bridge (MSUF_Suite/Core/HostBridge.lua):
-- a provider on Menu2 hosts with host API v1, the wrapped reset functions on
-- older hosts. These handlers are the Suite's half of either.
local function PageResetHandlers()
    local pages, specs = {}, {}
    for _, page in ipairs(P.pages) do
        pages[page.key], specs[page.key] = true, page
    end
    -- The page's title in the reader's language (its key when it has none).
    local function PageTitle(key)
        local page = specs[key]
        return page and P.Tr(page.title) or key
    end
    local handlers = { pages = pages, withHistory = P.WithHistory, confirm = P.Confirm, combat = P.Combat }
    function handlers.canReset(key)
        local page = specs[key]
        return page ~= nil and page.reset ~= false and PageAddOnEnabled(key)
    end
    function handlers.warning(key)
        return string.format(P.Tr("Reset %s to defaults?\n\nThis resets all settings on this Suite page for the active profile."),
            PageTitle(key))
    end
    function handlers.label(key)
        return string.format(P.Tr("Reset %s"), PageTitle(key))
    end
    function handlers.prepare(key)
        return key ~= "suite_skin" or Suite.Skin.EnsureEngine() == true
    end
    function handlers.run(key)
        if key == "suite_skin" then return P.ResetSkinPage() or false end
        -- The cooldown manager resets its settings, spell lists and spell
        -- options through its page, which offers an Undo line.
        local body = specs[key] and specs[key].resetPage
        if body then return body() == true end
        local modules = PAGE_MODULES[key]
        if not modules then return false end
        for _, id in ipairs(modules) do if not S.Reset(id) then return false end end
        return true
    end
    function handlers.finish()
        P.Refresh()
        if M.ShowStatusFeedback then M.ShowStatusFeedback(P.Tr("Page reset"), "ok", 1.5) end
    end
    return handlers
end

local function InstallPageResets()
    P.pageResetMode = Suite.HostBridge.RegisterPageResets(M, PageResetHandlers())
end

AddIcons()
RegisterPages()

Suite.HostBridge.WatchMenuContent(M, function(frame, token)
    local client = Suite.Skin.Acquire("menuContent")
    Suite.Skin.RegisterMenu(frame, "menuContent")
    if client and client.AnimateContent then client:AnimateContent(frame, token) end
end, function(frame)
    Suite.Skin.RegisterMenu(frame, "menuContent")
end)

-- Menu2 asks for rows only while its layer overview is open. Keep Suite
-- settings in the Suite profile and use its validated/history-aware setter.
local function SetSuiteLayer(edit, value)
    return P.Set(edit.module, edit.key, value)
end

local function RegisterSuiteLayers()
    if type(M.RegisterLayerOverviewProvider) ~= "function" then return end
    M.RegisterLayerOverviewProvider("suite-owned-surfaces", function(sink)
        local function Add(area, scope, label, module, key, enabled)
            local config = S.Config(module)
            local value = config and config[key]
            local automatic = type(value) ~= "number" or value < 0
            sink:Layer({
                id = "suite." .. module .. "." .. key,
                area = area, scope = scope, label = label,
                value = automatic and 0 or value, default = 0,
                automatic = automatic, enabled = enabled ~= false,
                settingKey = "suite." .. module .. "." .. key,
                edit = { kind = "external", set = SetSuiteLayer, module = module, key = key },
            })
        end

        local cooldown = S.Config("cooldownManager")
        for _, slot in ipairs(Suite.CDM.SLOTS) do
            local keys = Suite.CDM.KEYS[slot.key]
            Add("Suite Cooldown Manager", slot.title, "Whole bar", "cooldownManager", keys.layer,
                cooldown.enabled and cooldown[keys.on])
        end
        local data = S.Config("dataTexts")
        for _, id in ipairs(Suite.DataTextBarIDs(data)) do
            local prefix = "bar" .. id
            local name = data[prefix .. "Name"]
            if type(name) ~= "string" or name == "" then name = P.Tr("Bar %d"):format(id) end
            Add("Suite DataTexts", name, "Whole bar", "dataTexts", prefix .. "Layer",
                data.enabled and data[prefix .. "Enabled"])
        end
        local meter = S.Config("damageMeter")
        for i = 1, Suite.DamageMeterMaxWindows do
            Add("Suite Damage Meter", P.Tr("Window %d"):format(i), "Whole window", "damageMeter", "w" .. i .. "Layer",
                meter.enabled and i <= meter.windowCount)
        end
        local actions = S.Config("actionbars")
        for i = 1, Suite.ActionBarCount do
            Add("Suite Action Bars", Suite.ActionBarTitles[i], "Whole bar", "actionbars", "bar" .. i .. "Layer",
                actions.enabled and actions["bar" .. i .. "Visibility"] ~= Suite.ActionBarEnum.VISIBILITY.NEVER)
        end
        local xp = S.Config("xpBar")
        Add("Suite Quality of Life", "Experience", "Experience bar", "xpBar", "layer", xp.enabled)
    end)
end
-- MSUF's Icon Skins page (Style > Icon Skins) is the one place where skins
-- are chosen: "Where It Applies" gets a row per built-in cooldown manager bar,
-- one for the custom bars and one for all action bars, each the hidden
-- iconSkin rule of its bars written with history like every Suite setting.
-- The page reads the area's icon shape and sets it when a skin for another
-- shape is picked (the shape itself is chosen on the module page). A few rows
-- add a sample to the page's "Your Icons" strip. The module pages show the
-- area's skin through P.IconSkinKey and HostBridge.IconSkinStatusRow.
local SKIN_SAMPLES = { ess = "Interface\\Icons\\Spell_Nature_Lightning", buf = "Interface\\Icons\\Spell_Holy_WordFortitude" }
local CUSTOM_SLOT = {}
for _, slot in ipairs(Suite.CDM.SLOTS) do CUSTOM_SLOT[slot.key] = slot.custom == true end
function P.IconSkinKey(slot)
    if slot == "actionbars" then return "suite_actionbars" end
    return "suite_cdm_" .. (CUSTOM_SLOT[slot] and "custom" or slot)
end
local function IndexOf(list, value)
    for i = 1, #list do
        if list[i] == value then return i end
    end
end
-- The shape of an area's bars. Custom bars with different shapes answer
-- MIXED, which fits no skin: a skin picked for them sets every bar's shape.
local function SharedShape(id, keys, ids)
    local value = P.Get(id, keys[1])
    for i = 2, #keys do
        if P.Get(id, keys[i]) ~= value then return "MIXED" end
    end
    return ids[value] or "RECTANGLE"
end
-- Writes one value to every key in `keys` (custom bars share a row).
local function WriteAll(id, keys, value)
    if #keys == 1 then return P.Set(id, keys[1], value) end
    local values = {}
    for i = 1, #keys do values[keys[i]] = value end
    return P.SetMany(id, values)
end
-- A skin made for another shape is written with that shape in one step, as
-- the page's MatchShape would set it right after: the page then finds the
-- shape matching, and the module restyles once. No skin (also a Like default
-- whose default is none, as after the page's reset) leaves the shape alone.
local function WriteSkin(id, skinKeys, shapeKeys, ids, value)
    local wanted = Suite.HostBridge.IconSkinShape(value)
    local index = wanted and wanted ~= SharedShape(id, shapeKeys, ids) and IndexOf(ids, wanted)
    if not index then return WriteAll(id, skinKeys, value) end
    local values = {}
    for i = 1, #skinKeys do values[skinKeys[i]] = value end
    for i = 1, #shapeKeys do values[shapeKeys[i]] = index end
    return P.SetMany(id, values)
end
-- The page sets an area's shape when a new default skin wants another one
-- (Page.SelectDefault: after writing the default, before applying it).
-- Written then, the module would restyle with the new shape and the old
-- committed skin, so the area is only marked, and the mark is settled within
-- that page action: by MSUF's report of the committed default (this hook runs
-- before the modules refresh: one write per module, which that refresh then
-- skips, `refreshed`), or by the area's refresh right after the apply when no
-- report comes. Nothing outlives the page action, so an undo, a profile
-- switch or a look edit never moves a shape. The Suite refuses writes in
-- combat: a default picked in a fight leaves the shapes alone (no mark).
local marked, areaWrites, batches = {}, {}, {} -- area key -> true; area key -> its record
local function FlushShapes(refreshed)
    if not next(marked) then return end
    if not Suite.InCombat() then
        -- Each bar on its own (the custom bars share a row but can differ
        -- after a bar reset): only a bar that follows the default (DEFAULT,
        -- the catalog rules' default) takes its shape; a bar with its own
        -- skin keeps its shape.
        for key in pairs(marked) do
            local a = areaWrites[key]
            for i = 1, #a.shapeKeys do
                local skinKey, shapeKey = a.skinKeys[i] or a.skinKeys[1], a.shapeKeys[i]
                local wanted = P.Get(a.id, skinKey) == "DEFAULT" and Suite.HostBridge.IconSkinShape("DEFAULT")
                local index = wanted and IndexOf(a.ids, wanted)
                if index and index ~= P.Get(a.id, shapeKey) then
                    local values = batches[a.id] or {}
                    batches[a.id] = values
                    values[shapeKey] = index
                end
            end
        end
        for id, values in pairs(batches) do
            batches[id] = nil
            if P.SetMany(id, values) and refreshed then refreshed[id] = true end
        end
    end
    for key in pairs(marked) do marked[key] = nil end
end
Suite.HostBridge.OnIconSkinsChanged("MSUF_Suite_Options.shapes", FlushShapes)
local function SkinArea(key, group, label, order, id, skinKeys, shapeKeys, ids, icon)
    areaWrites[key] = { id = id, skinKeys = skinKeys, shapeKeys = shapeKeys, ids = ids }
    return {
        key = key, group = P.Tr(group), label = P.Tr(label), order = order, icon = icon, module = id,
        -- The custom bars' row reads Like default while any of them follows the
        -- default (a bar reset), so a new default reaches it: Page.SelectDefault
        -- matches only rows that read DEFAULT, and FlushShapes then moves only
        -- the bars that follow it.
        read = function()
            for i = 2, #skinKeys do
                if P.Get(id, skinKeys[i]) == "DEFAULT" then return "DEFAULT" end
            end
            return P.Get(id, skinKeys[1])
        end,
        write = function(value) return WriteSkin(id, skinKeys, shapeKeys, ids, value) end,
        shape = function() return SharedShape(id, shapeKeys, ids) end,
        setShape = function(shape)
            if not IndexOf(ids, shape) or Suite.InCombat() then return false end
            marked[key] = true
            return true
        end,
        refresh = function() FlushShapes() end,
    }
end
-- An area drawn square only (no shape setting): the page offers it only the
-- square skins.
local function SquareArea(key, group, label, order, id, skinKey, icon)
    return {
        key = key, group = P.Tr(group), label = P.Tr(label), order = order, icon = icon, module = id,
        read = function() return P.Get(id, skinKey) end,
        write = function(value) return P.Set(id, skinKey, value) end,
    }
end
-- Whether a row's icons are drawn now (Page.RegisterArea `available`): while
-- one of `ids` runs (the controller's state). Otherwise the page dims the row
-- and shows why: the module's own status when it is enabled but does not run
-- (its addon off in the AddOns list, failed, not on this client), else
-- `reason`, which names the module to turn on.
local function Running(ids, reason)
    return function()
        for i = 1, #ids do
            local state = S.states[ids[i]]
            if state and state.active and not state.error then return true end
        end
        if P.Get(ids[1], "enabled") == true then return false, P.StatusText(ids[1]) end
        return false, P.Tr(reason)
    end
end
local function RegisterIconSkinAreas()
    local CDM, specs, customSkins, customShapes = Suite.CDM, {}, {}, {}
    for i, slot in ipairs(CDM.SLOTS) do
        local keys = CDM.KEYS[slot.key]
        if slot.custom then
            customSkins[#customSkins + 1], customShapes[#customShapes + 1] = keys.iconSkin, keys.iconShape
        else
            specs[#specs + 1] = SkinArea(P.IconSkinKey(slot.key), "Cooldown manager", slot.title, i, "cooldownManager",
                { keys.iconSkin }, { keys.iconShape }, Suite.IconShapeIds, SKIN_SAMPLES[slot.key])
        end
    end
    specs[#specs + 1] = SkinArea(P.IconSkinKey("c1"), "Cooldown manager", "Custom bars", #CDM.SLOTS, "cooldownManager",
        customSkins, customShapes, Suite.IconShapeIds)
    specs[#specs + 1] = SkinArea(P.IconSkinKey("actionbars"), "Action bars", "All action bars", 1, "actionbars",
        { "iconSkin" }, { "buttonShape" }, Suite.ActionBarEnum.BUTTON_SHAPE_IDS, "Interface\\Icons\\Ability_Warrior_Charge")
    -- Blizzard's own player buffs and debuffs beside the minimap, as the
    -- Player aura layout module draws them.
    specs[#specs + 1] = SquareArea("suite_playerauras_buffs", "Player aura layout", "Buffs", 1, "playerAuras", "buffSkin")
    specs[#specs + 1] = SquareArea("suite_playerauras_debuffs", "Player aura layout", "Debuffs", 2, "playerAuras", "debuffSkin")
    local running = {
        cooldownManager = Running({ "cooldownManager" }, "Turn on the Cooldown manager to skin these icons."),
        actionbars = Running({ "actionbars" }, "Turn on Action bars to skin these buttons."),
        playerAuras = Running({ "playerAuraSkins", "playerAuras" },
            "Turn on Player aura skins (Quality of Life) to skin these icons."),
    }
    for _, spec in ipairs(specs) do spec.available = running[spec.module] end
    Suite.HostBridge.RegisterIconSkinAreas(M, specs)
end

RegisterSuiteLayers()
RegisterIconSkinAreas()
InstallPageResets()
local added = AddNavigation()
-- Menu2 builds its navigation once per session. If the window already exists
-- (options were opened before the suite attached), the rows appear after a reload.
if added and M.frame then
    Suite.Print(P.Tr("Reload the interface to show the Suite pages in the MSUF menu."))
end

Suite.Options = {
    RefreshAll = function() P.Refresh() end,
    BuildColorsCategory = function(ctx, builder) return P.BuildColorsCategory(ctx, builder) end,
    ApplyForeverStyle = function() return P.ApplyForeverStyle() end,
}
Suite.Menu.attached = true
-- Seed transition tracking after the initialized Suite has attached its menu.
P.Refresh()
