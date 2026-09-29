local _, P = ...
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local PAGE = "suite_modules"
local SKIN_PAGE, SKIN_ADDON = "suite_skin", "MSUF_Suite_Skin"
local BUTTON_WIDTH = 140

-- One place to see and switch every Suite module. The sections follow the
-- sidebar groups (NAV_GROUPS in Menu/Register.lua). A row's switch writes
-- through the same setter as the module's own page, so MSUF's Undo covers
-- it, and its button opens that page.

local PRESET_LABEL = { core = "Turn on core modules", off = "Turn all off" }
local PRESET_TEXT = {
    core = "Turn on every core Suite module this client supports? Optional modules keep their current setting.",
    off = "Turn off every Suite module? Their settings stay saved. Skinning keeps its own switch.",
}

local function Always() return true end

local function OpenPage(key)
    if P.Combat() or not M.SelectPage then return end
    M.SelectPage(key)
end

-- A module stopped after an error stays off until one of its settings or the
-- profile changes: the controller clears state.error then (Core/Suite.lua).
-- Retry clears it without a change and applies the module again.
local function Retry(id)
    local state = S.states[id]
    if P.Combat() or not state.error then return end
    state.error, P.feedback[id] = nil, nil
    S.Apply(id)
end

-- A preset is one gesture: one MSUF history entry, undone in one step.
local function ApplyPreset(kind)
    if P.Combat() then return false end
    local ok = P.WithHistory(PRESET_LABEL[kind], "suite:modules.preset." .. kind, function()
        return S.Preset(kind)
    end)
    P.Refresh()
    return ok
end

local function ConfirmPreset(kind)
    if P.Combat() then return false end
    if not M.InstallStaticPopup then return ApplyPreset(kind) end
    M.InstallStaticPopup("MSUF_SUITE_MODULES_PRESET_CONFIRM", {
        text = "%s", button1 = YES, button2 = NO,
        OnAccept = function(_, data)
            if data and data.kind then ApplyPreset(data.kind) end
        end,
    })
    StaticPopup_Show("MSUF_SUITE_MODULES_PRESET_CONFIRM", Tr(PRESET_TEXT[kind]), nil, { kind = kind })
    return true
end

-- The installer opens in the middle of the screen; the menu steps aside.
local function RunSetup()
    if Suite.Installer.Open() and M.frame then M.frame:Hide() end
end

------------------------------------------------------------------ rows
-- A row reads its module through an entry: key, title, description, page,
-- installed, get/set of the switch, status() and, for catalog modules,
-- failed() and retry().
local function ModuleEntry(id)
    local spec = P.catalog[id]
    return {
        key = id, title = spec.title, description = spec.description, page = spec.page or ("suite_" .. id),
        installed = Suite.Client.HasAddOn(spec.addon),
        get = function() return P.Get(id, "enabled") == true end,
        set = function(value) P.Set(id, "enabled", value == true) end,
        status = function() return P.StatusText(id) end,
        failed = function() return S.states[id].error ~= nil end,
        retry = function() Retry(id) end,
    }
end

local function SkinStatus()
    local ok, why = Suite.Client.AddOnEnabled(SKIN_ADDON)
    if not ok then return Suite.StatusText(why, Tr) end
    return Tr(P.SkinningEnabled() and "Active" or "Off")
end

-- Skinning is no catalog module; its switch is the one on the Skinning page.
local function SkinEntry()
    return {
        key = "skin", title = "Skinning", page = SKIN_PAGE,
        description = "Styles Blizzard windows and Suite windows with the chosen Suite look.",
        installed = Suite.Client.HasAddOn(SKIN_ADDON),
        get = P.SkinningEnabled,
        set = function(value) P.SetSkinningEnabled(value == true) end,
        status = SkinStatus,
    }
end

-- The switch carries the module name; a module whose AddOn is not installed
-- shows its name, status and description only. The page and Retry buttons
-- sit on the right. Returns the next free y.
local function Row(ctx, body, sectionId, entry, y, width)
    local left = width - BUTTON_WIDTH - 12
    local top, toggle, retry = y, nil, nil
    if entry.installed then
        local row = P.Meta(PAGE, entry.key, "enabled", "setting", sectionId)
        row.id, row.kind, row.label, row.get, row.set = entry.key, "toggle", Tr(entry.title), entry.get, entry.set
        local grid = W.SettingsRows(ctx, body, { x = 16, y = y, width = left, columns = 1, rows = { row } })
        toggle, y = grid.controls[entry.key], grid.bottomY
    else
        P.Text(body, entry.title, 16, y - 6, left, T.colors.text)
        y = y - 28
    end
    local status = P.Text(body, "", 16, y, left, T.colors.text)
    local description = P.Text(body, entry.description or "", 16, y - 18, left, T.colors.dim or T.colors.muted)
    y = y - 18 - math.max(14, math.ceil(description:GetStringHeight() or 14))
    if entry.installed then
        P.Button(ctx, body, "Open page", 28 + left, top, BUTTON_WIDTH, function() OpenPage(entry.page) end,
            Always, P.Meta(PAGE, entry.key, "open", "navigation", sectionId))
        if entry.retry then
            retry = P.Button(ctx, body, "Retry", 28 + left, top - 32, BUTTON_WIDTH, entry.retry, entry.failed,
                P.Meta(PAGE, entry.key, "retry", "action", sectionId))
        end
        y = math.min(y, top - 62)
    end
    M.TrackRefresh(ctx, function()
        status:SetText(entry.status())
        if toggle then W.SetControlEnabled(toggle, not P.Combat()) end
        if retry then retry:SetShown(entry.failed()) end
    end)
    return y - 14
end

------------------------------------------------------------------ sections
-- { spec = NAV_GROUPS entry, entries = { catalog id or SKIN_PAGE } } per
-- sidebar group, modules in catalog order. A module whose page has no group
-- is listed under Interface, where the sidebar puts such a page.
local function Groups()
    local byPage, placed, groups, interface = {}, {}, {}, nil
    for _, id in ipairs(P.order) do
        local page = P.catalog[id].page or ("suite_" .. id)
        byPage[page] = byPage[page] or {}
        byPage[page][#byPage[page] + 1] = id
    end
    for _, spec in ipairs(P.navGroups) do
        local entries = {}
        for _, page in ipairs(spec.pages) do
            if page == SKIN_PAGE then entries[#entries + 1] = SKIN_PAGE end
            for _, id in ipairs(byPage[page] or {}) do
                entries[#entries + 1] = id
                placed[id] = true
            end
        end
        groups[#groups + 1] = { spec = spec, entries = entries }
        if spec.id == "interface" then interface = entries end
    end
    for _, id in ipairs(P.order) do
        if not placed[id] and interface then interface[#interface + 1] = id end
    end
    return groups
end

local function BuildGroup(ctx, b, group)
    local spec = group.spec
    local sectionId = PAGE .. "_" .. spec.id
    local body = b:CollapsibleSection(sectionId, Tr(P.navGroupTitles[spec.id] or spec.title), 120, true)
    local width = math.max(360, (body._msuf2Width or b.width or 720) - 32)
    local y = -18
    for _, key in ipairs(group.entries) do
        y = Row(ctx, body, sectionId, key == SKIN_PAGE and SkinEntry() or ModuleEntry(key), y, width)
    end
    P.FinishBody(b, body, y)
end

local function EnabledCount()
    local count = 0
    for _, id in ipairs(P.order) do
        if P.Get(id, "enabled") == true then count = count + 1 end
    end
    return count
end

-- Intro, how many modules are on and the actions for all modules at once.
local function BuildOverview(ctx, b)
    local sectionId = PAGE .. "_overview"
    local body = b:CollapsibleSection(sectionId, Tr("Overview"), 120, true)
    local width = math.max(360, (body._msuf2Width or b.width or 720) - 32)
    local intro = P.Text(body, "Switch Suite modules on or off, see what each one is doing and open its settings. A module you turn off keeps its settings.", 16, -18, width)
    local y = -18 - math.max(14, math.ceil(intro:GetStringHeight() or 14)) - 10
    local summary = P.Text(body, "", 16, y, width, T.colors.text)
    y = y - 28
    local actions = {
        { PRESET_LABEL.core, function() ConfirmPreset("core") end, "preset.core" },
        { PRESET_LABEL.off, function() ConfirmPreset("off") end, "preset.off" },
        { "Run setup again", RunSetup, "setup" },
    }
    local buttonWidth = math.floor((width - 2 * 12) / 3)
    for i, action in ipairs(actions) do
        P.Button(ctx, body, action[1], 16 + (i - 1) * (buttonWidth + 12), y, buttonWidth, action[2], Always,
            P.Meta(PAGE, "suite", action[3], "action", sectionId))
    end
    y = y - 38
    M.TrackRefresh(ctx, function()
        summary:SetText(string.format(Tr("%d of %d Suite modules are on"), EnabledCount(), #P.order))
    end)
    P.FinishBody(b, body, y)
end

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    BuildOverview(ctx, b)
    for _, group in ipairs(Groups()) do
        if #group.entries > 0 then BuildGroup(ctx, b, group) end
    end
end

-- reset = false: the page owns no settings, so the toolbar offers no Reset page.
P.RegisterPage({ key = PAGE, label = "Suite Modules", title = "Suite Modules", build = Build,
    icon = { 4, 2 }, accent = true, reset = false,
    aliases = { "modules", "suite", "suite modules", "module overview" } })
