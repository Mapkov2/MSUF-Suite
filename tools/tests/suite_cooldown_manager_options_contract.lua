local root = assert(arg[1], "repository root required")
-- Offline contract for the cooldown manager options page
-- (MSUF_Suite_Options/Pages/CooldownManager*.lua): registration, setting
-- coverage through custom bar 1's template rules, selected-bar key mapping,
-- attach targets (bars plus the player and target frames),
-- list edits (codec + one history entry per gesture), the spell picker, the
-- per-spell popover, combat refusal and teardown when the page hides.
-- Budgets: a settings write that cannot change the spell tiles makes no
-- runtime call for them; navigation buttons take no history snapshot; the
-- only per-frame work is a drag, cleared on release, hide and combat.
-- Menu2 is a stand-in modelled on suite_options_menu_contract.lua.

------------------------------------------------------------------ secrets
local SecretMT = {}
local function Raise(what) return function() error("secret value used: " .. what, 2) end end
for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__lt", "__le", "__eq", "__call", "__len" }) do
    SecretMT[key] = Raise(key)
end
SecretMT.__index = Raise("index"); SecretMT.__newindex = Raise("assignment"); SecretMT.__tostring = Raise("tostring")
local function Secret() return setmetatable({}, SecretMT) end
local function IsSecret(value) return getmetatable(value) == SecretMT end
issecretvalue = IsSecret

------------------------------------------------------------------ frames
local frames = {}
local methods = {}
local WidgetMT = {}
local function Noop() end
WidgetMT.__index = function(_, key)
    local method = methods[key]
    if method then return method end
    -- WoW methods are PascalCase; plain fields stay nil like on real frames.
    if type(key) == "string" and key:find("^%u") then return Noop end
    return nil
end
local function Widget(kind, parent)
    local w = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, hooks = {}, events = {},
        text = "", width = 100, height = 20, enabled = true, alpha = 1, points = {} }, WidgetMT)
    frames[#frames + 1] = w
    if parent then
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = w
    end
    return w
end
local function Run(frame, script)
    if frame.scripts[script] then frame.scripts[script](frame) end
    if frame.hooks[script] then frame.hooks[script](frame) end
end
function methods:Show() if not self.shown then self.shown = true; Run(self, "OnShow") end end
function methods:Hide() if self.shown then self.shown = false; Run(self, "OnHide") end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    local frame = self
    while frame do if not frame.shown then return false end; frame = frame.parent end
    return true
end
function methods:SetText(v) self.text = v end
function methods:GetText() return self.text end
function methods:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function methods:SetWidth(v) self.width = v end
function methods:GetWidth() return self.width end
function methods:SetHeight(v) self.height = v end
function methods:GetHeight() return self.height end
function methods:SetSize(a, b) self.width, self.height = a, b end
function methods:GetLeft() return self.left end
function methods:GetStringHeight() return 14 end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn) self.hooks[name] = fn end
function methods:SetEnabled(v) self.enabled = v and true or false end
function methods:IsEnabled() return self.enabled end
function methods:SetAlpha(v) self.alpha = v end
function methods:GetAlpha() return self.alpha end
function methods:SetActive(v) self.active = v and true or false end
function methods:SetTexture(v) self.texture = v end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function methods:SetDesaturated(v) self.desaturated = v and true or false end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetAllPoints(target) self.points = { { "ALL", target } } end
function methods:IsMouseOver() return self.mouseOver == true end
function methods:GetEffectiveScale() return 1 end
function methods:SetScale(v) self.scale = v end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(v) self.level = v end
function methods:GetParent() return self.parent end
function methods:GetChildren() return unpack(self.children or {}) end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:ClearFocus() self.focus = false end
function methods:HasFocus() return self.focus == true end
function methods:SetVerticalScroll(v) self.scroll = v end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetVerticalScrollRange() return 0 end
function methods:CreateTexture() return Widget("Texture", self) end
function methods:CreateFontString() return Widget("FontString", self) end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
local function Fire(frame, script, ...)
    local fn, hook = frame.scripts[script], frame.hooks[script]
    local result
    if fn then result = fn(frame, ...) end
    if hook then hook(frame, ...) end
    return result
end
-- A real click: press, release, then the click event.
local function Click(frame, button)
    Fire(frame, "OnMouseDown", button)
    Fire(frame, "OnMouseUp", button)
    return Fire(frame, "OnClick", button)
end
CreateFrame = function(kind, _, parent) return Widget(kind, parent) end
UIParent = Widget("Frame")

------------------------------------------------------------------ client stand-ins
local combat = false
InCombatLockdown = function() return combat end
SlashCmdList = {}
IsLoggedIn = function() return false end
LoggingCombat = function() return false end
GetInstanceInfo = function() return "outside", "none", 0 end
GetLocale = function() return "enUS" end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
GameFontHighlightSmall = {}
SecureHandlerSetFrameRef, RegisterStateDriver = function() end, function() end
C_DamageMeter = { GetCombatSessionFromType = function() end }
Enum = { DamageMeterType = { DamageDone = 0 } }
Minimap = { SetMaskTexture = function() end }
C_CooldownViewer = { GetCooldownViewerCategorySet = function() return {} end, GetCooldownViewerCooldownInfo = function() end }
local SPELLS = { [133] = { "Fireball", 1001 }, [1459] = { "Arcane Intellect", 1002 }, [122] = { "Frost Nova", 1004 },
    [382440] = { "Shifting Power", 1006 } }
C_Spell = {
    GetSpellCooldownDuration = function() end,
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] or nil end,
    GetSpellTexture = function(id) return SPELLS[id] and SPELLS[id][2] or nil end,
    GetSpellIDForSpellIdentifier = function(text) for id, spell in pairs(SPELLS) do if spell[1] == text then return id end end end,
}
C_Item = {
    GetItemNameByID = function(id) return id == 5512 and "Healthstone" or id == 9001 and "Trinket of Tests" or nil end,
    GetItemIconByID = function(id) return id == 5512 and 2001 or nil end,
    RequestLoadItemDataByID = function() end,
}
GetInventoryItemTexture = function(_, slot) return slot == 13 and 3001 or nil end
GetInventoryItemID = function(_, slot) return slot == 13 and 9001 or nil end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function(index) return ({ 62, 63, 64 })[index], ({ "Arcane", "Fire", "Frost" })[index] end,
}
GetNumSpecializations = function() return 3 end
local cursorX, cursorY = 100, 100
GetCursorPosition = function() return cursorX, cursorY end
local tooltip = { shown = false }
function tooltip:SetOwner(owner) self.owner = owner end
function tooltip:SetText(text) self.text = text end
function tooltip:AddLine(text) self.line = text end
function tooltip:Show() self.shown = true end
function tooltip:IsOwned(owner) return self.owner == owner end
function tooltip:Hide() self.shown = false end
GameTooltip = tooltip
local toggledBlizzard = 0
CooldownViewerSettings = { TogglePanel = function() toggledBlizzard = toggledBlizzard + 1 end }
local soundNames = { "Boom", "Bell", "Chime" }
LibStub = { GetLibrary = function(_, name)
    if name ~= "LibSharedMedia-3.0" then return nil end
    return { List = function() return soundNames end, Fetch = function(_, _, key) return "Sounds\\" .. key end }
end }
-- MSUF's compact codec, kept as an in-memory store.
local store = {}
MSUF_EncodeCompactTable = function(tbl, prefix) store[#store + 1] = tbl; return prefix .. ":" .. #store end
MSUF_TryDecodeCompactString = function(text) local n = tonumber(text:match("^MSUF3:(%d+)$")); return n and store[n] or nil end

local runtimeLoads = 0
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true, MSUF_Suite_Options = true }
local InstallRuntime
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name ~= "MapkoSkin" end,
    LoadAddOn = function(name)
        if name == "MSUF_Suite_CooldownManager" then
            runtimeLoads = runtimeLoads + 1
            loaded[name] = true
            InstallRuntime()
            return true
        end
        return false, "MISSING"
    end,
}
local L = setmetatable({}, { __index = function(_, k) return k end })
MSUF_NS = { L = L, GetEffectiveLocale = function() return "enUS" end }

------------------------------------------------------------------ Menu2 stand-in
local M, W, T = {}, {}, {}
MSUF2 = M
M.Widgets, M.Theme = W, T
M.frame = Widget("Frame")
local historyProvider, historyWrites, historyDepth = nil, 0, 0
M.RegisterHistoryProvider = function(_, capture, restore) historyProvider = { capture = capture, restore = restore }; return true end
-- Nested captures fold into the outer one, as Menu2's RunWithHistory does.
M.RunWithHistory = function(_, _, fn)
    if combat then return false end
    if historyDepth > 0 then return fn() end
    historyDepth = historyDepth + 1
    historyWrites = historyWrites + 1
    local result = fn()
    historyDepth = historyDepth - 1
    return result
end
local tasks = {}
local function PendingTasks() local n = 0; for _ in pairs(tasks) do n = n + 1 end; return n end
M.MenuTimer = { After = function(_, fn)
    if combat then return nil end
    local task = { fn = fn }
    function task:Cancel() tasks[self] = nil end
    tasks[task] = true
    return task
end }
M.PreviewSelectionBar = {
    Create = function(box, deps) box.selectionDeps = deps; local bar = Widget("SelectionBar", box); box.selectionBar = bar; return bar end,
    Refresh = function(box)
        local handle = box._selectedHandle
        if handle then box.selectionX, box.selectionY = box.selectionDeps.ReadOffsets(box, handle) else box.selectionX, box.selectionY = nil, nil end
    end,
    SetShown = function(box, shown) if box.selectionBar then box.selectionBar:SetShown(shown) end end,
}
M.ShouldExpandFixedPreview = function() return true end
M.pages = {}
M.Tr = function(text) return L[text] end
M.CreateMenuPopupPanel = function(parent) return Widget("Popup", parent) end
T.colors = { muted = { 0.5, 0.5, 0.5 }, text = { 1, 1, 1 }, dim = { 0.4, 0.4, 0.4 }, accent = { 0.2, 0.6, 1 } }
T.navIconGrid = { home = { 0, 0 }, gameplay = { 7, 1 } }
T.navIconColors = { home = { 1 }, gameplay = { 2 }, profiles = { 3 } }
T.Font = function(parent, _, text) local fs = Widget("FontString", parent); fs.text = text; return fs end
T.Button = function(parent, text, width, height) local b = Widget("Button", parent); b.text, b.width, b.height = text, width, height; return b end
T.Panel = function(parent) return Widget("Panel", parent) end
T.CenterButtonLabel = function() end
T.MeasureButtonWidth = function() return 90 end
M.navItems = {
    { key = "home", label = "Dashboard" },
    { title = "Features", id = "features" }, { key = "gameplay", label = "Gameplay", group = "features" },
    { key = "profiles", label = "Profiles", group = "features" },
}
M.navPrimaryForKey = { home = "home" }
M.ALIASES = {}
M.GlobalPage = { FontValues = function() return { { value = "Expressway", text = "Expressway" } } end }
M.StatusBarTextureItems = function(follow) return { { value = "", text = follow }, { value = "Flat", text = "Flat" } } end
M.RegisterPage = function(key, spec) M.pages[key] = spec end
M.ControlMeta = function(page, _, path, classification, exact)
    local meta = { controlId = "menu2." .. page .. "." .. path, classification = classification }
    for k, v in pairs(exact or {}) do meta[k] = v end
    return meta
end
local registered = {}
M.RegisterControlMetadata = function(widget, meta) if meta and meta.controlId then registered[meta.controlId] = widget end end
local current
M.TrackRefresh = function(ctx, fn) ctx.refreshers[#ctx.refreshers + 1] = fn end
M.RequestRefresh = function() if current then for _, fn in ipairs(current.refreshers) do fn() end end end
local function Bind(ctx, widget, get, set, meta, label)
    widget.get, widget.set, widget.meta, widget.label = get, set, meta, label
    ctx.widgets[#ctx.widgets + 1] = widget
    return widget
end
M.BindSwitchAt = function(ctx, parent, label, x, y, w, get, set, meta) return Bind(ctx, Widget("Switch", parent), get, set, meta, label) end
M.BindBoolWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
M.BindDropdownAt = function(ctx, parent, label, x, y, values, w, get, set, meta)
    local widget = Bind(ctx, Widget("Dropdown", parent), get, set, meta, label)
    widget.values = values
    return widget
end
M.BindTextInputAt = function(ctx, parent, label, x, y, w, get, set, blur, meta) return Bind(ctx, Widget("EditBox", parent), get, set, meta, label) end
M.BindDropdownWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
local lastDropdown, dropdownClosed = nil, 0
W.OpenDropdown = function(owner, values, currentValue, onSelect)
    lastDropdown = { owner = owner, values = values, current = currentValue, onSelect = onSelect }
    return true
end
W.CloseDropdown = function() dropdownClosed = dropdownClosed + 1 end
local focused
W.FocusCollapsibleSection = function(section) focused = section.sectionId; return true end
W.Dropdown = function(parent, label) local d = Widget("Dropdown", parent); d.label = label; return d end
W.MoveWidget = function() end
W.SectionSwitch = function(section, label) local w = Widget("Switch", section); w.label = label; section.headerSwitch = w; return w end
W.SetControlEnabled = function(widget, enabled) widget.enabled = enabled and true or false end
W.SettingsRows = function(ctx, parent, spec)
    local controls, y = {}, spec.y
    for _, row in ipairs(spec.rows) do
        local widget = Bind(ctx, Widget(row.kind, parent), row.get, row.set, row, row.label)
        widget.rowKind, widget.row = row.kind, row
        controls[row.id] = widget
        y = y - 40
    end
    return { controls = controls, bottomY = y }
end
W.PageBuilder = function(ctx)
    local b = { width = ctx.width, y = -12 }
    function b:Header() ctx.headers = (ctx.headers or 0) + 1 end
    function b:CollapsibleSection(id, title)
        local body = Widget("Section")
        body.sectionId, body.title = id, title
        body._msuf2Width = ctx.width
        body._msuf2CollapsibleEntry = { label = Widget("FontString", body) }
        ctx.sections[#ctx.sections + 1] = body
        ctx.pageItems[#ctx.pageItems + 1] = id
        return body
    end
    function b:FinishSection(body) body.finished = (body.finished or 0) + 1 end
    return b
end
W.FixedPreviewSection = function(ctx)
    local section, toolbar, record = Widget("FixedPreview", M.frame), Widget("Toolbar"), {}
    section._msuf2Width = ctx.width
    ctx.fixedPreview = { section = section, toolbar = toolbar, record = record }
    ctx.pageItems[#ctx.pageItems + 1] = "fixed-preview"
    return section, toolbar, record
end
W.AttachFixedPreviewExpander = function(section, toolbar, box, opts)
    local expander = { box = box, opts = opts }
    function expander:Open() self.expanded = true; box:ApplyCompactPreviewPresentation(false); return true end
    function expander:Close() self.expanded = false; box:ApplyCompactPreviewPresentation(true); return true end
    section.expander = expander
    return expander
end

------------------------------------------------------------------ suite core
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local NS = {}
local files = Support.TocFiles(root, "MSUF_Suite", "Mainline")
local listed = false
for _, file in ipairs(files) do if file == "Core/Catalog/CooldownManager.lua" then listed = true end end
local catalogFile = assert(io.open(root .. "/MSUF_Suite/Core/SuiteCatalog.lua", "rb"))
local integrated = catalogFile:read("*a"):find("cooldownManager%s*=") ~= nil
catalogFile:close()
for _, file in ipairs(files) do
    if file == "Core/Suite.lua" and not listed then
        -- Until the integrator lists the module, register it the way
        -- Build.Module does with its moduleAddons entry.
        local B = NS.CatalogBuild
        local original = B.Module
        if not integrated then
            B.Module = function(id, spec)
                if id ~= "cooldownManager" then return original(id, spec) end
                spec.id, spec.addon, spec.controls, spec.rules = id, "MSUF_Suite_CooldownManager", {}, {}
                spec.conflicts = spec.conflicts or {}
                NS.SuiteCatalog[id] = spec
                NS.SuiteOrder[#NS.SuiteOrder + 1] = id
                B.Add(id, B.Bool("enabled", "Enable module", true))
                return spec
            end
        end
        assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite", NS)
        B.Module = original
    end
    if file:match("%.lua$") then assert(loadfile(root .. "/MSUF_Suite/" .. file))("MSUF_Suite", NS) end
end
local Suite = assert(MSUFSuite)
local S = Suite.Suite
local CDM = assert(Suite.CDM, "cooldown manager catalog missing")
local ID = "cooldownManager"
Suite.Database.Initialize(nil)
S.Start()
local function Config() return S.Config(ID) end
assert(S.Availability(ID), "cooldown manager must be available in this harness")

-- Count list encodes to prove every gesture goes through the catalog codec.
local encodes = 0
local encodeLists = CDM.Codec.EncodeLists
CDM.Codec.EncodeLists = function(...) encodes = encodes + 1; return encodeLists(...) end

------------------------------------------------------------------ runtime stand-in
local runtime = { played = {}, released = 0, specID = 62 }
local CATALOG_ORDER = { "b1", "b2", "b3", "b4", "b5", "b6", "b10", "b11", "b20", "b30", "b40" }
-- Rows carry their spell IDs where the runtime knows them (b1 has none, so
-- both shapes are covered).
local CATALOG = {
    b1 = { name = "Fireball", texture = 101, family = 1, known = true },
    b2 = { name = "Frostbolt", texture = 102, family = 1, known = true },
    b3 = { name = "Arcane Blast", texture = 103, family = 1, known = false },
    b4 = { name = "Frost Nova", texture = 104, family = 1, known = true, spell = 122 },
    b5 = { name = "Blink", texture = Secret(), family = 1, known = true },
    b6 = { name = Secret(), texture = 106, family = 1, known = Secret() },
    b10 = { name = "Arcane Intellect", texture = 110, family = 2, known = true },
    b11 = { name = "Ice Barrier", texture = 111, family = 2, known = true },
    b20 = { name = "Clearcasting", texture = 120, family = 2, known = true },
    b30 = { name = "Berserking", texture = 130, family = 1, known = true },
    b40 = { name = "Shifting Power", texture = 140, family = 1, known = false, spell = 999, override = 382440,
        tooltip = 455110 },
}
local HOME = { ess = { "b1", "b2", "b3" }, uti = { "b4", "b5", "b6" }, buf = { "b10", "b11" }, bar = { "b20" }, ext = { "b30" } }
-- Resolution rules of BUILD_SPEC section 3 for specialization 62.
local function Resolve()
    local lists = CDM.Codec.DecodeLists(Config().listsData)
    local explicit, hidden = lists.specs[runtime.specID] or {}, lists.hidden[runtime.specID] or {}
    local claimed, plans = {}, {}
    for _, info in ipairs(CDM.SLOTS) do
        for _, key in ipairs(explicit[info.key] or {}) do if claimed[key] == nil then claimed[key] = info.key end end
    end
    for _, info in ipairs(CDM.SLOTS) do
        local slot, out, seen = info.key, {}, {}
        local kind = info.custom and Config()[slot .. "_kind"] or info.kind
        local family = kind == 1 and 1 or 2
        local function Add(key)
            local record = CATALOG[key]
            local entryFamily = record and record.family or (CDM.IsAuraKey(key) and 2 or 1)
            if seen[key] or entryFamily ~= family then return end
            seen[key] = true
            out[#out + 1] = { key = key, name = record and record.name or key, texture = record and record.texture,
                known = not record or record.known, family = entryFamily, hidden = key == "b2" }
        end
        for _, key in ipairs(explicit[slot] or {}) do if claimed[key] == slot then Add(key) end end
        if not info.custom then
            for _, key in ipairs(HOME[slot] or {}) do
                if not hidden[key] and (claimed[key] == nil or claimed[key] == slot) then Add(key) end
            end
        end
        plans[slot] = out
    end
    return plans
end
local function Keys(slot)
    local out = {}
    for _, entry in ipairs(Resolve()[slot]) do out[#out + 1] = entry.key end
    return table.concat(out, ",")
end
InstallRuntime = function()
    S.CooldownManagerBarEntries = function(slot) return Resolve()[slot] end
    S.CooldownManagerCatalogEntries = function(family)
        local where = {}
        for slot, list in pairs(Resolve()) do for _, entry in ipairs(list) do where[entry.key] = slot end end
        local out = {}
        for _, key in ipairs(CATALOG_ORDER) do
            local record = CATALOG[key]
            if record.family == family then
                out[#out + 1] = { key = key, name = record.name, texture = record.texture, known = record.known, category = 0,
                    slot = where[key], spell = record.spell, override = record.override, tooltip = record.tooltip }
            end
        end
        -- Like Catalog.List, cooldown rows end with the two trinket slots.
        if family == 1 then
            out[#out + 1] = { key = "e13", name = "Trinket of Tests", texture = 3001, known = true, slot = where.e13 }
            out[#out + 1] = { key = "e14", name = "Trinket 2", known = false, slot = where.e14 }
        end
        return out
    end
    S.CooldownManagerRenderPreview = function(parent, slot, w, h)
        runtime.rendered = { parent = parent, slot = slot, w = w, h = h }
        runtime.frame = runtime.frame or Widget("Frame", parent)
        return runtime.frame
    end
    S.CooldownManagerReleasePreview = function() runtime.released = runtime.released + 1 end
    -- Like the runtime: refused while the module is off or in combat; the
    -- answer is the state that now applies.
    S.CooldownManagerSimulate = function(on)
        runtime.simulate = on == true and not runtime.refuse and not combat
        return runtime.simulate
    end
    S.CooldownManagerSetPreview = function(on)
        if on and (runtime.inactive or combat) then return false end
        runtime.previewOn = on == true
        return true
    end
    S.CooldownManagerSpec = function() return runtime.specID, "Arcane", 135932 end
    S.CooldownManagerStatus = function() return "Blizzard's bars are off." end
    S.CooldownManagerPlaySound = function(value) runtime.played[#runtime.played + 1] = value end
    S.CooldownManagerConvertGrow = function(slot, grow) runtime.grow = slot; return { [slot .. "_grow"] = grow, [slot .. "_y"] = -123 } end
    S.CooldownManagerConvertVertical = function(slot, vertical) runtime.vertical = slot; return { [slot .. "_vertical"] = vertical, [slot .. "_x"] = 17 } end
end

------------------------------------------------------------------ options addon
-- Page files run in an environment that refuses global writes.
local globalsBefore = {}
for key in pairs(_G) do globalsBefore[key] = true end
local P = {}
local strict = setmetatable({}, { __index = _G, __newindex = function(_, key) error("options page wrote global " .. tostring(key), 2) end })
for _, file in ipairs({ "Menu/Bridge.lua", "Menu/Controls.lua", "Pages/CooldownManagerWidgets.lua",
    "Pages/CooldownManagerPreview.lua", "Pages/CooldownManager.lua", "Menu/Register.lua" }) do
    local chunk = assert(loadfile(root .. "/MSUF_Suite_Options/" .. file))
    if file:find("CooldownManager", 1, true) then setfenv(chunk, strict) end
    chunk("MSUF_Suite_Options", P)
end
local Page = assert(P.CDMPage, "page state missing")
local PAGE = "suite_cooldownManager"

-- Registration, navigation icon and aliases.
local spec = assert(M.pages[PAGE], "page not registered")
assert(spec.title == "Cooldown manager" and type(spec.build) == "function")
local icon = T.navIconGrid[PAGE]
assert(icon and icon[1] == 1 and icon[2] == 1, "navigation icon missing")
for _, page in ipairs(P.pages) do
    if page.key ~= PAGE and page.icon then
        assert(page.icon[1] ~= icon[1] or page.icon[2] ~= icon[2], "navigation icon shared with " .. page.key)
    end
end
for _, alias in ipairs({ "cdm", "cooldowns", "cooldown manager", "buff bars", "ccm" }) do
    assert(M.ALIASES[alias] == PAGE, "alias missing: " .. alias)
end
assert(historyProvider and P.historyRegistered, "suite history provider not registered")

------------------------------------------------------------------ build and activation
local ctx = { key = PAGE, width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = ctx
spec.build(ctx)
assert(ctx.pageItems[1] == "fixed-preview", "the docked preview must be the first page item")
assert(ctx.sections[1].sectionId == PAGE .. "_cooldownManager_module" and ctx.sections[1].headerSwitch, "module card must follow the preview")
-- Navigation clicks never take Menu2's full settings snapshot.
local cardButtons = 0
for _, child in ipairs(ctx.sections[1].children or {}) do
    if child.kind == "Button" then
        cardButtons = cardButtons + 1
        assert(child._msuf2SkipHistoryCheckpoint, "module card action takes a history snapshot: " .. tostring(child.text))
    end
end
assert(cardButtons == 3, "module card actions missing")
for _, section in ipairs(ctx.sections) do
    for _, child in ipairs(section.children or {}) do
        if child.kind == "Button" and section ~= ctx.sections[1] then
            assert(child._msuf2SkipHistoryCheckpoint, "page button takes a history snapshot: " .. tostring(child.text))
        end
    end
end
assert(not ctx.headers, "suite pages have no page header")
assert(runtimeLoads == 0 and not S.CooldownManagerBarEntries, "the runtime must load on activation, not while building")
for _, section in ipairs(ctx.sections) do assert(section.finished, "section not finished: " .. section.sectionId) end
ctx.fixedPreview.record.onActivate()
assert(runtimeLoads == 1 and runtime.previewOn == true, "activation did not load the runtime and start its preview mode")
assert(ctx.fixedPreview.section.expander.expanded, "preferred expanded preview did not open")
M.RequestRefresh()
assert(runtime.rendered and runtime.rendered.slot == "ess", "preview did not render the selected bar")
assert(runtime.frame.points[1][1] == "CENTER", "preview frame is not centered on the stage")
local ui = Page.ui
assert(ui.chips.ess.shown and ui.chips.ess.active and ui.chips.c1.shown == false and ui.addChip.shown,
    "bar chips must show enabled bars, the selection and + Add bar")
assert(registered["menu2." .. PAGE .. ".cooldownManager.preview.bar.ess"] == ui.chips.ess
    and registered["menu2." .. PAGE .. ".cooldownManager.preview.simulate"]
    and registered["menu2." .. PAGE .. ".cooldownManager.editor.add"], "preview and bar actions lack search metadata")

-- Sections and coverage through template keys.
local suffixes = {}
for _, section in ipairs(Page.SECTIONS) do
    for _, suffix in ipairs(section.suffixes) do
        assert(not suffixes[suffix], "suffix listed twice: " .. suffix)
        suffixes[suffix] = section.id
    end
end
for suffix in pairs(CDM.KEYS.c1) do assert(suffixes[suffix], "no section for " .. suffix) end
local covered = {}
for _, widget in ipairs(ctx.widgets) do
    local key = widget.meta and widget.meta.settingKey
    if key then
        covered[key] = widget
        local prefix = key:match("^msufsuite%.cooldownManager%.(%w+)_")
        assert(not prefix or prefix == "c1", "control bound to a live per-bar key: " .. key)
    end
end
local catalog = Suite.SuiteCatalog[ID]
local checked = 0
for key, rule in pairs(catalog.rules) do
    if not rule.hidden and not rule.previewOnly then
        local template = rule.suffix and CDM.KEYS.c1[rule.suffix] or key
        assert(covered["msufsuite.cooldownManager." .. template], "no menu control for " .. key)
        checked = checked + 1
    end
end
assert(checked > 500, "coverage check is vacuous")
local function Control(suffix) return assert(covered["msufsuite.cooldownManager." .. (CDM.KEYS.c1[suffix] or suffix)], suffix) end

------------------------------------------------------------------ selected bar mapping
local picker
for _, widget in ipairs(ctx.widgets) do
    if widget.meta and tostring(widget.meta.controlId):find("editor%.selected") then picker = widget end
end
assert(picker and picker.meta.historyMode == "none", "bar selector must be ephemeral")
-- Six built-in bars (Defensives and Potions and racials among them), then the
-- six custom bars: c1 is the seventh entry.
assert(#CDM.SLOTS == 12 and #picker.values() == #CDM.SLOTS, "bar selector lists every slot")
assert(picker.values()[3].value == "def" and picker.values()[4].value == "ext" and picker.values()[7].value == "c1"
    and picker.values()[7].text:find("(off)", 1, true) and not picker.values()[6].text:find("(off)", 1, true),
    "bar selector order: built-in bars first, custom bars after, off custom bars marked")
local size = Control("size")
local c1Size = Config().c1_size
picker.set("uti")
assert(Page.selected == "uti" and size.get() == Config().uti_size, "size control did not follow the selected bar")
size.set(50)
assert(Config().uti_size == 50 and Config().c1_size == c1Size and Config().ess_size ~= 50, "keyFn write hit the wrong bar")
local order = {}
for i, section in ipairs(ctx.sections) do order[i] = section.sectionId:gsub("^suite_cooldownManager_", "") end
assert(table.concat(order, ",") == "cooldownManager_module,bars,spells,layout,look,text,effects,buffs,barstyle,visibility,general",
    "unexpected section order: " .. table.concat(order, ","))
assert(ctx.sections[4]._msuf2CollapsibleEntry.label.text:find("Utility cooldowns", 1, true),
    "layout header does not name the selected bar")
picker.set("bar")
M.RequestRefresh()
assert(not size.enabled and Control("barWidth").enabled and not Control("desat").enabled and Control("pandemic").enabled,
    "controls must follow the bar type of the selected bar")
assert(Control("grow").enabled and not Control("spacing").enabled and not Control("zoom").enabled,
    "the built-in Buff bars row has fixed spacing and icon look")
assert(not Control("name").enabled and not Control("kind").enabled, "built-in bars cannot be renamed or retyped")
picker.set("c2")
M.RequestRefresh()
assert(Control("name").enabled and Control("kind").enabled and size.enabled and Control("desat").enabled
    and not Control("barWidth").enabled, "custom cooldown bar gates are wrong")
Config().c2_kind = 3
M.RequestRefresh()
assert(not size.enabled and Control("barWidth").enabled, "custom bar type change did not re-gate controls")
-- A custom Buff bar bar keeps what the runtime reads for it.
for suffix in pairs(Page.KIND3_EXTRA) do
    assert(Control(suffix).enabled, "custom buff bars use " .. suffix)
end
assert(Control("grow").enabled and not Control("perRow").enabled and not Control("vertical").enabled
    and not Control("desat").enabled, "custom buff bar gates are wrong")
Config().c2_kind = 1
-- The bar name commits to the bar it was typed for, even when the bar
-- changes before the input loses focus.
local nameInput = Control("name")
M.RequestRefresh()
Fire(nameInput, "OnEditFocusGained")
nameInput.focus = true
nameInput.scripts.OnEditFocusLost = function(self) self.set("Typed name") end
nameInput.ClearFocus = function(self) self.focus = false; Fire(self, "OnEditFocusLost") end
picker.set("c3")
assert(Config().c2_name == "Typed name" and Config().c3_name == "" and not nameInput.focus,
    "the pending name was not committed to its own bar before the switch")
assert(nameInput.get() == "" and nameInput._cdmSlot == nil, "the name input did not follow the new bar")
nameInput.scripts.OnEditFocusLost, nameInput.ClearFocus = nil, nil
Fire(nameInput, "OnEditFocusGained")
Page.selected = "c4"
nameInput.set("Late")
assert(Config().c3_name == "Late" and Config().c4_name == "", "a late commit wrote the name to another bar")
Fire(nameInput, "OnEditFocusLost")
nameInput.set("Now")
assert(Config().c4_name == "Now", "an unfocused write must follow the selected bar")
Config().c2_name, Config().c3_name, Config().c4_name = "", "", ""
picker.set("c2")
picker.set("ess")
M.RequestRefresh()
local anchor = Control("anchor")
assert(anchor.row.values[2].disabled and anchor.row.values[2].text == "Essential cooldowns" and not anchor.row.values[3].disabled,
    "a bar cannot attach to itself")
-- Attach targets: Free, the twelve bars, then MSUF's player and target frames.
local anchors = anchor.row.values
assert(#anchors == #CDM.SLOTS + 3 and #anchors == #CDM.ANCHOR_LABELS, "attach list must end with the two unit frames")
assert(CDM.FRAME_ANCHORS[14] == "player" and CDM.FRAME_ANCHORS[15] == "target" and not CDM.FRAME_ANCHORS[13],
    "frame targets must follow the last bar")
local function FrameTargetsIntact()
    for i, label in pairs({ [14] = "Player frame", [15] = "Target frame" }) do
        local item = anchors[i]
        if item.value ~= i or item.text ~= label or item.translate == false or item.disabled then return false end
    end
    return true
end
assert(FrameTargetsIntact(), "frame targets must keep their own translated labels and stay selectable")
-- Renaming a bar repaints only the bar entries.
Config().c6_name = "Cast bars"
picker.set("c6")
M.RequestRefresh()
assert(anchors[13].text == "Cast bars" and anchors[13].translate == false and anchors[13].disabled,
    "bar entries carry the bars' own names")
assert(FrameTargetsIntact() and not anchors[12].disabled, "repainting the bar entries renamed or disabled a frame target")
Config().c6_name = ""
picker.set("ess")
M.RequestRefresh()
assert(anchors[13].text == "Custom bar 6" and FrameTargetsIntact(), "frame targets drifted after the repaint")
-- A bar on a unit frame is attached, not placed freely.
assert(Config().def_anchor == 14 and Config().ext_anchor == 14, "Defensives and Potions and racials sit on the player frame")
local defSummary = Page.Summary("def")
assert(defSummary:find("Player frame", 1, true) and not defSummary:find("placed freely", 1, true),
    "bar summary must name the unit frame a bar is attached to: " .. defSummary)
assert(Page.Summary("uti"):find("Essential cooldowns", 1, true) and Page.Summary("ess"):find("placed freely", 1, true),
    "bar summary for bar attaches and free bars")
Control("grow").set(2)
assert(runtime.grow == "ess" and Config().ess_grow == 2 and Config().ess_y == -123, "grow change did not keep the bar in place")
Control("vertical").set(true)
M.RequestRefresh()
assert(runtime.vertical == "ess" and Config().ess_vertical and Config().ess_x == 17, "orientation change did not keep the bar in place")
assert(Control("grow").row.values[2].text == "Left", "vertical bars grow left or right")

------------------------------------------------------------------ list edits
local grid = ui.grid
assert(grid.count == 3 and Keys("ess") == "b1,b2,b3", "tile grid does not show the resolved bar")
-- A settings write that cannot change the tiles asks the runtime for nothing
-- (a slider drag repaints every tick); the tiles' inputs still do.
local entryCalls, barEntries = 0, S.CooldownManagerBarEntries
S.CooldownManagerBarEntries = function(slot) entryCalls = entryCalls + 1; return barEntries(slot) end
M.RequestRefresh()
local calls = entryCalls
assert(calls == 1, "the tile grid did not notice the runtime changed")
Control("zoom").set(12)
Control("swipeAlpha").set(40)
Control("size").set(41)
M.RequestRefresh()
assert(entryCalls == calls, "a look or layout slider tick rebuilt the spell tiles")
Control("maxIcons").set(2)
assert(entryCalls == calls + 1, "the icon cap changes which tiles are marked")
Control("maxIcons").set(0)
Config().c4_kind = 2
M.RequestRefresh()
assert(entryCalls == calls + 3, "a bar type change moves entries between bars")
Config().c4_kind = 1
M.RequestRefresh()
S.CooldownManagerBarEntries = barEntries
M.RequestRefresh()
assert(grid.count == 3, "tile grid lost its entries")
assert(grid.tiles[2].ruleMark.shown and not grid.tiles[1].ruleMark.shown, "hidden-by-rule entries are not marked")
assert(grid.tiles[3].icon.desaturated and grid.tiles[3].alpha == 0.55, "unlearned entries must be dimmed")
local function Lists() return CDM.Codec.DecodeLists(Config().listsData) end

-- Picker: filter, claim from another bar, keep open, custom IDs.
Fire(grid.plus, "OnClick", "LeftButton")
local pick = assert(Page.picker)
assert(pick.shown and pick.anchor == grid.plus, "picker did not open at the + tile")
local function VisibleRows()
    local out = {}
    for _, row in ipairs(pick.rows) do if row.shown and row.item then out[#out + 1] = row.item end end
    return out
end
local rows = VisibleRows()
assert(rows[1].kind == "header" and rows[2].key == "b40", "unassigned entries must come first")
local seenTrinket, trinketRows = false, 0
for _, item in ipairs(rows) do
    if item.key == "e13" then
        trinketRows = trinketRows + 1
        seenTrinket = item.text:find("Trinket of Tests", 1, true) ~= nil
    end
end
assert(seenTrinket and trinketRows == 1, "trinket slots must be listed once, under Trinkets and items")
pick.search:SetText("122")
Fire(pick.search, "OnTextChanged", true)
rows = VisibleRows()
assert(#rows == 2 and rows[2].key == "b4", "Blizzard entries must be found by their spell ID")
pick.search:SetText("382440")
Fire(pick.search, "OnTextChanged", true)
rows = VisibleRows()
assert(#rows == 2 and rows[2].key == "b40", "Blizzard entries must be found by their override spell ID")
pick.search:SetText("455110")
Fire(pick.search, "OnTextChanged", true)
rows = VisibleRows()
assert(#rows == 2 and rows[2].key == "b40", "Blizzard entries must be found by their tooltip spell ID")
pick.search:SetText("")
Fire(pick.search, "OnTextChanged", true)
pick.search:SetText("frost")
Fire(pick.search, "OnTextChanged", true)
rows = VisibleRows()
assert(#rows == 3 and rows[1].kind == "header" and rows[2].key == "b4" and rows[3].key == "b2", "search filter failed")
pick.search:SetText("zzz")
Fire(pick.search, "OnTextChanged", true)
assert(#VisibleRows() == 0 and pick.empty.shown, "empty search must say so")
pick.search:SetText("b6")
Fire(pick.search, "OnTextChanged", true)
assert(#VisibleRows() == 2, "entries with a protected name are still found by key")
pick.search:SetText("frost")
Fire(pick.search, "OnTextChanged", true)
local writes, encoded = historyWrites, encodes
local novaRow
for _, row in ipairs(pick.rows) do if row.shown and row.item and row.item.key == "b4" then novaRow = row end end
Fire(novaRow, "OnClick")
assert(historyWrites == writes + 1 and encodes == encoded + 1, "one pick must be one history entry through the codec")
assert(Keys("ess") == "b1,b2,b3,b4" and Keys("uti") == "b5,b6", "picking did not move the spell here")
assert(table.concat(Lists().specs[62].ess, ",") == "b1,b2,b3,b4", "explicit list must keep Blizzard's order first")
assert(pick.shown and pick.note.text == "Moved Frost Nova from Utility cooldowns." and Page.note == pick.note.text,
    "picker must stay open and name the old bar")
assert(novaRow.alpha == 0.45 and novaRow.status.text == "On this bar", "picked row did not grey in place")
Fire(novaRow, "OnClick")
assert(historyWrites == writes + 1, "picking an entry already on the bar must not write")
pick.idBox:SetText("5512")
Fire(pick.idBox, "OnTextChanged", true)
assert(pick.echo.text:find("Healthstone", 1, true) and pick.addB.enabled and not pick.addA.enabled, "item ID echo failed")
Fire(pick.addB, "OnClick")
assert(Keys("ess") == "b1,b2,b3,b4,i5512", "custom item was not added")
pick.idBox:SetText("Fireball")
Fire(pick.idBox, "OnTextChanged", true)
assert(pick.echo.text:find("Spell 133", 1, true) and pick.addA.enabled, "spell name lookup failed")
Fire(pick.addA, "OnClick")
assert(Keys("ess") == "b1,b2,b3,b4,i5512,s133", "custom spell was not added")
-- A spell Blizzard's Cooldown Manager tracks is added as that entry.
local listsBefore = Config().listsData
pick.idBox:SetText("382440")
Fire(pick.idBox, "OnTextChanged", true)
assert(pick.echo.text:find("Blizzard's entry", 1, true) and pick.addA.enabled, "the echo must name Blizzard's entry")
Fire(pick.addA, "OnClick")
assert(Keys("ess") == "b1,b2,b3,b4,i5512,s133,b40", "a tracked spell became a second, custom entry")
pick.idBox:SetText("122")
Fire(pick.idBox, "OnTextChanged", true)
writes = historyWrites
Fire(pick.addA, "OnClick")
assert(historyWrites == writes and pick.note.text:find("already on this bar", 1, true),
    "a tracked spell already on the bar must not be added again")
Config().listsData = listsBefore
pick.idBox:SetText("999999")
Fire(pick.idBox, "OnTextChanged", true)
assert(not pick.addA.enabled and not pick.addB.enabled and pick.echo.textColor[1] == 1, "unknown IDs must be refused")
local ok, reason = Page.AddEntry("ess", "a1459", 2)
assert(not ok and reason == "That bar shows cooldowns.", "wrong family must be refused")
Fire(pick.close, "OnClick")
assert(not pick.shown, "picker close failed")

-- Middle-click removes with an undo line that clears itself.
writes, encoded = historyWrites, encodes
Click(grid.tiles[1], "MiddleButton")
assert(historyWrites == writes + 1 and encodes == encoded + 1 and Keys("ess") == "b2,b3,b4,i5512,s133", "middle-click remove failed")
assert(Lists().hidden[62].b1, "removed Blizzard entries are hidden for the specialization")
assert(Page.undo and PendingTasks() == 1 and ui.PaintNote and Page.note == "Removed Fireball.", "undo line missing")
Click(grid.plus, "LeftButton")
local removedRow
for _, row in ipairs(pick.rows) do if row.shown and row.item and row.item.key == "b1" then removedRow = row end end
assert(removedRow and removedRow.status.text == "Removed" and VisibleRows()[2].key == "b1", "removed spells must be listed first and marked")
Fire(pick.close, "OnClick")
Page.RunUndo()
assert(Keys("ess") == "b1,b2,b3,b4,i5512,s133" and historyWrites == writes + 2 and PendingTasks() == 0, "undo failed")
Click(grid.tiles[6], "MiddleButton")
assert(Keys("ess") == "b1,b2,b3,b4,i5512", "custom entries leave the list")
assert(not (Lists().hidden[62] or {}).s133, "custom entries are never hidden")

-- Drag: insert after the hovered tile's right half.
local host = grid.host
cursorX, cursorY = 100, 100
Fire(grid.tiles[1], "OnMouseDown", "LeftButton")
assert(host.scripts.OnUpdate, "drag did not arm")
cursorX = 101
Fire(host, "OnUpdate", 0.01)
assert(not grid.dragTile, "drag started below the 3 px threshold")
cursorX = 140
grid.tiles[3].mouseOver, grid.tiles[3].left, grid.tiles[3].width = true, 120, 36
Fire(host, "OnUpdate", 0.01)
assert(grid.dragTile == grid.tiles[1] and grid.marker.shown and grid.dropAfter, "drag target not found")
writes = historyWrites
Fire(grid.tiles[1], "OnMouseUp", "LeftButton")
grid.tiles[3].mouseOver = false
assert(Keys("ess") == "b2,b3,b1,b4,i5512" and historyWrites == writes + 1, "reorder failed")
assert(host.scripts.OnUpdate == nil and not Page.ghost.shown and not grid.marker.shown, "drag left its OnUpdate running")
Fire(grid.tiles[1], "OnClick", "LeftButton")
assert(not (Page.popover and Page.popover.shown), "the click that ends a drag must not open the popover")
-- Drop onto a bar chip moves the entry; wrong families are refused.
Fire(grid.tiles[4], "OnMouseDown", "LeftButton")
cursorX = 200
ui.chips.uti.mouseOver = true
Fire(host, "OnUpdate", 0.01)
assert(grid.dropSlot == "uti" and ui.chips.uti.drop.shown, "chip drop target not highlighted")
Fire(grid.tiles[4], "OnMouseUp", "LeftButton")
ui.chips.uti.mouseOver = false
assert(Keys("uti") == "b5,b6,b4" and Keys("ess") == "b2,b3,b1,i5512", "drop on a bar chip did not move the spell")
assert(Page.note == "Moved Frost Nova to Utility cooldowns.", "move note missing")
cursorX = 100
Fire(grid.tiles[1], "OnMouseDown", "LeftButton")
cursorX = 200
ui.chips.buf.mouseOver = true
Fire(host, "OnUpdate", 0.01)
Fire(grid.tiles[1], "OnMouseUp", "LeftButton")
ui.chips.buf.mouseOver = false
assert(Page.noteError and Page.note == "That bar shows buffs." and Keys("buf") == "b10,b11", "cooldown dropped on a buff bar")

------------------------------------------------------------------ per-spell popover
local fieldRows = {}
for _, field in ipairs(Page.FIELDS) do
    assert(CDM.SPELL_FIELDS[field.key], "popover row for an unknown spell field: " .. field.key)
    fieldRows[field.key] = true
end
for field in pairs(CDM.SPELL_FIELDS) do assert(fieldRows[field], "no popover row for spell field " .. field) end
local tile = grid.tiles[1]
Click(tile, "LeftButton")
local pop = assert(Page.popover)
assert(pop.shown and pop.key == "b2" and pop.anchor == tile, "popover did not open on the tile")
assert(pop.rows.readyGlow.shown and not pop.rows.auraGlow and not pop.rows.lossSound, "popover rows must follow the entry family")
-- Controls end left of the per-row reset button (the row is 290 wide).
local resetLeft = pop.rows.readyGlow.reset.parent.width - pop.rows.readyGlow.reset.width
assert(130 + pop.rows.glowStyle.choice.width <= resetLeft
    and 130 + pop.rows.sound.choice.width + 2 + pop.rows.sound.play.width <= resetLeft, "a control runs under the reset button")
local lastSwatch = pop.rows.glowColor.swatches[#pop.rows.glowColor.swatches]
assert(lastSwatch.points[1][4] + lastSwatch.width <= resetLeft, "color swatches run under the reset button")
writes = historyWrites
Fire(pop.rows.readyGlow.on, "OnClick")
assert(Page.SpellField("b2", "readyGlow") == true and historyWrites == writes + 1, "per-spell toggle failed")
assert(pop.rows.readyGlow.reset.shown and pop.rows.readyGlow.label.textColor[1] == 0.2, "customised row has no accent and reset")
assert(tile.mark.shown, "tile does not mark per-spell options")
Fire(pop.rows.readyGlow.off, "OnClick")
assert(Page.SpellField("b2", "readyGlow") == false, "explicit off failed")
Fire(pop.rows.readyGlow.reset, "OnClick")
assert(Page.SpellField("b2", "readyGlow") == nil and not pop.rows.readyGlow.reset.shown, "row reset failed")
Fire(pop.rows.glowStyle.choice, "OnClick")
assert(lastDropdown and lastDropdown.owner == pop.rows.glowStyle.choice, "glow style list did not open")
lastDropdown.onSelect(2)
assert(Page.SpellField("b2", "glowStyle") == 2, "glow style failed")
Fire(pop.rows.readyAlpha.minus, "OnClick")
assert(Page.SpellField("b2", "readyAlpha") == 95, "stepper must start from the bar value")
Fire(pop.rows.glowColor.swatches[3], "OnClick")
assert(Page.SpellField("b2", "glowColor") == "ff4d4d", "color swatch failed")
Fire(pop.rows.icon.edit, "OnEnterPressed")
assert(Page.SpellField("b2", "icon") == nil, "empty icon field must not write")
pop.rows.icon.edit:SetText("12345")
Fire(pop.rows.icon.edit, "OnEnterPressed")
assert(Page.SpellField("b2", "icon") == 12345, "custom icon failed")
-- Sound picker: LSM list, filter, play, pick.
Fire(pop.rows.sound.choice, "OnClick")
local sounds = assert(Page.soundPicker)
assert(sounds.shown and pop.shown, "sound picker must open above the popover")
sounds.search:SetText("be")
Fire(sounds.search, "OnTextChanged", true)
local bell
for _, row in ipairs(sounds.rows) do if row.shown and row.item and row.item.value == "lsm:Bell" then bell = row end end
assert(bell and not sounds.rows[2].shown, "sound filter failed")
Fire(bell.play, "OnClick")
assert(runtime.played[#runtime.played] == "lsm:Bell", "sound preview failed")
Fire(bell, "OnClick")
assert(Page.SpellField("b2", "sound") == "lsm:Bell" and not sounds.shown, "sound pick failed")
Fire(pop.rows.sound.play, "OnClick")
assert(runtime.played[#runtime.played] == "lsm:Bell", "row play button failed")
writes = historyWrites
Fire(pop.reset, "OnClick")
assert(Page.SpellOverrides().e.b2 == nil and historyWrites == writes + 1, "reset spell failed")
-- Move to bar from the popover.
Fire(pop.move, "OnClick")
local names = {}
for _, item in ipairs(lastDropdown.values) do names[#names + 1] = item.value .. (item.disabled and "-" or "+") end
assert(table.concat(names, ",") == "uti+,def+,ext+,buf-,bar-", "move list must mark bars of the other family: " .. table.concat(names, ","))
lastDropdown.onSelect("ext")
assert(Keys("ext") == "b30,b2" and not pop.shown, "move to bar failed")
-- Custom entries can be copied to the other specializations.
Click(grid.tiles[3], "LeftButton")
assert(pop.key == "i5512" and pop.copy.shown and not pop.rows.procGlow.shown and pop.rows.readyGlow.shown,
    "item entries show item options and the copy action")
Fire(pop.copy, "OnClick")
assert(Lists().specs[63].ess[1] == "i5512" and Lists().specs[64].ess[1] == "i5512", "copy to specializations failed")
Fire(pop.close, "OnClick")
-- Aura entries get the buff options.
picker.set("buf")
M.RequestRefresh()
Click(grid.tiles[1], "RightButton")
assert(pop.shown and pop.key == "b10" and pop.rows.auraGlow.shown and pop.rows.lossSound.shown and not pop.rows.readyGlow.shown,
    "buff entries must show buff options")
assert(pop.rows.sound.label.text == "Sound when gained", "buff sound label")
-- Buff glows are a plain edge; a buff's own icon shows only while it is missing.
assert(not pop.rows.glowStyle.shown and pop.rows.glowColor.shown, "buff entries offer a glow style the runtime ignores")
assert(pop.rows.icon.shown and pop.rows.icon.label.text == "Icon when missing (Enter)", "buff icon row must say when it applies")
picker.set("ess")
assert(not pop.shown, "changing the bar closes the popover")
M.RequestRefresh()

------------------------------------------------------------------ bars
Page.OpenAddBar(ui.addChip)
assert(lastDropdown.owner == ui.addChip, "add bar menu did not open")
lastDropdown.onSelect(2)
M.RequestRefresh()
assert(Config().c1_on and Config().c1_kind == 2 and Config().c1_name == "Buffs 1" and Page.selected == "c1", "adding a bar failed")
assert(ui.chips.c1.shown and ui.chips.c1.active, "the new bar has no chip")
assert(#lastDropdown.values == 3, "only new bar types are offered while no named bar is off")
Control("on").set(false)
assert(not Config().c1_on and Page.FreeCustom() == "c2", "new bars must prefer an unused custom slot")
Page.OpenAddBar(ui.addChip)
local offered = lastDropdown.values
assert(#offered == 5 and offered[4].header and offered[5].value == "c1" and offered[5].text == "Buffs 1"
    and offered[5].translate == false, "named bars that are off must be offered again")
lastDropdown.onSelect("c1")
assert(Config().c1_on and Config().c1_kind == 2 and Page.selected == "c1", "turning a bar back on failed")
M.RequestRefresh()
-- Once every slot was named, a new bar reuses one that is off: it starts
-- over (settings, name and spells) and does not land on the bar at 0, 0.
for i = 2, 6 do Config()["c" .. i .. "_name"] = "Old " .. i end
Config().c2_size, Config().c2_kind = 60, 3
local reused = Lists()
reused.specs[62] = reused.specs[62] or {}
reused.specs[62].c2 = { "s133" }
Config().listsData = CDM.Codec.EncodeLists(reused)
assert(Config().c1_x == 0 and Config().c1_y == 0, "c1 must sit at the screen center for this check")
writes = historyWrites
assert(Page.AddBar(1) and Page.selected == "c2" and historyWrites == writes + 1, "reusing a bar slot failed")
assert(Config().c2_on and Config().c2_kind == 1 and Config().c2_name == "Cooldowns 2" and Config().c2_size == 36,
    "a reused bar kept its old settings")
assert(not (Lists().specs[62] and Lists().specs[62].c2), "a reused bar kept its old spells")
assert(Config().c2_x == 0 and Config().c2_y == -48, "a new bar landed on another bar")
Config().c2_on = false
for i = 2, 6 do Config()["c" .. i .. "_name"] = "" end
Config().c2_y = 0
-- Attached to a bar that is off: the summary and the drag refusal say so,
-- and Edit Mode opens on a bar it can move.
Config().ess_on = false
assert(Page.Summary("uti"):find("(off), takes the place of Essential cooldowns", 1, true),
    "summary hides that the parent bar is off: " .. Page.Summary("uti"))
assert(Page.AttachedText("uti"):find("Essential cooldowns", 1, true), "drag refusal must name the bar that is off")
assert(Page.Summary("buf"):find("Utility cooldowns", 1, true) and not Page.Summary("buf"):find("(off)", 1, true),
    "a bar on a shown parent is attached as usual")
local opened
S.OpenEditMode = function(_, element) opened = element; return false end
Page.selected = "ess"
M.RequestRefresh()
local move = registered["menu2." .. PAGE .. ".cooldownManager.action.move"]
assert(move and move.enabled, "Move bars on screen must stay available while another bar can move")
Fire(move, "OnClick")
assert(opened == "uti", "Edit Mode must open on a bar that is on and movable, not " .. tostring(opened))
Config().ess_on = true
S.OpenEditMode = nil
Page.selected = "c1"
M.RequestRefresh()
Fire(ui.chips.ess, "OnClick")
assert(Page.selected == "ess", "chip click did not select its bar")
M.RequestRefresh()
assert(Page.OpenBlizzardSettings() and toggledBlizzard == 1 and not M.frame.shown, "Blizzard's Cooldown Settings did not open")
M.frame:Show()
-- Preview handle: click focuses the layout, drag moves free bars.
local handle = ui.handle
assert(handle.shown, "preview handle missing")
Fire(handle, "OnMouseDown", "LeftButton")
Fire(handle, "OnMouseUp", "LeftButton")
assert(focused == PAGE .. "_layout", "clicking the preview did not open the layout")
assert(handle.scripts.OnUpdate == nil, "a click left the drag driver running")
Config().ess_anchor = 1
local x, y = Config().ess_x, Config().ess_y
cursorX, cursorY = 100, 100
Fire(handle, "OnMouseDown", "LeftButton")
assert(handle.scripts.OnUpdate, "the drawing must follow the cursor while the bar is dragged")
cursorX, cursorY = 130, 90
Fire(handle, "OnUpdate", 0.01)
local point = runtime.frame.points[1]
assert(point[1] == "CENTER" and point[4] == 30 and point[5] == -10, "the drawing did not follow the cursor")
Fire(handle, "OnMouseUp", "LeftButton")
assert(Config().ess_x == x + 30 and Config().ess_y == y - 10, "dragging the preview did not move the bar")
point = runtime.frame.points[1]
assert(handle.scripts.OnUpdate == nil and point[4] == 0 and point[5] == 0, "the drop left the drag running or the drawing off center")
M.RequestRefresh()
assert(ui.previewBody._selectedHandle == handle and ui.previewBody.selectionX == Config().ess_x, "selection bar lost the free bar")
Config().ess_anchor = 2
M.RequestRefresh()
assert(ui.previewBody._selectedHandle == handle, "attached bars nudge their offset from the anchor")
S.CooldownManagerMovable = function(slot) return slot ~= "ess" end
M.RequestRefresh()
assert(ui.previewBody._selectedHandle == nil, "the Essential bar riding Blizzard's bar offers no nudging")
x, y = Config().ess_x, Config().ess_y
cursorX, cursorY = 100, 100
Fire(handle, "OnMouseDown", "LeftButton")
assert(handle.scripts.OnUpdate == nil, "a bar that cannot move must not follow the cursor")
cursorX, cursorY = 140, 100
Fire(handle, "OnMouseUp", "LeftButton")
assert(Config().ess_x == x and Page.noteError and Page.note:find("Blizzard's Edit Mode", 1, true),
    "dragging a bar that cannot move must say why")
S.CooldownManagerMovable = nil
M.RequestRefresh()

------------------------------------------------------------------ simulation and preview mode
-- Simulate is offered only while the module runs; the toggle shows what the
-- runtime actually plays.
local simulate = registered["menu2." .. PAGE .. ".cooldownManager.preview.simulate"]
S.states[ID].active = false
M.RequestRefresh()
assert(not simulate.enabled, "Simulate must be off while the module does not run")
S.states[ID].active = true
M.RequestRefresh()
assert(simulate.enabled, "Simulate must be available while the module runs")
runtime.refuse = true
assert(not Page.SetSimulate(true) and not Page.simulating and not simulate.active, "a refused simulation shows as running")
runtime.refuse = nil
Fire(ctx.fixedPreview.toolbar, "OnShow")
assert(Page.SetSimulate(true) and runtime.simulate == true and simulate.active, "simulate did not start")
runtime.refuse = true
M.RequestRefresh()
assert(not Page.simulating and not simulate.active, "the toggle must follow a simulation the runtime ended")
runtime.refuse = nil
assert(Page.SetSimulate(true), "simulate did not restart")
-- The module switched on while the page is open gets the preview mode.
runtime.inactive = true
S.CooldownManagerSetPreview(false)
M.RequestRefresh()
assert(runtime.previewOn == false, "an inactive runtime refused the preview mode")
runtime.inactive = nil
M.RequestRefresh()
assert(runtime.previewOn == true, "the preview mode did not start when the module came on")

------------------------------------------------------------------ layouts
-- Menu2 builds one layout per window size and reuses them without a new
-- build. A layout built while another is shown does not take the page over;
-- the one being shown does, and a cached one hiding late stops nothing.
local ctx2 = { key = PAGE, width = 900, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
spec.build(ctx2)
assert(Page.ui == ui and ui.live, "a layout built in the background took the page over")
local released = runtime.released
ctx2.fixedPreview.record.onActivate()
local ui2 = Page.ui
assert(ui2 ~= ui and ui2.live and runtime.previewOn and runtime.simulate, "the shown layout did not take the page over")
ui.previewBody:Hide()
assert(runtime.previewOn == true and runtime.simulate == true and runtime.released == released + 1 and Page.ui == ui2,
    "a cached layout hiding late stopped the preview of the shown one")
ui2.chips.uti.mouseOver = true
assert(Page.ChipUnderCursor() == "uti", "drops must target the chips of the shown layout")
ui2.chips.uti.mouseOver = false
ui.previewBody:Show()
ctx.fixedPreview.record.onActivate()
ui2.previewBody:Hide()
assert(Page.ui == ui and ui.live and not ui2.live and runtime.previewOn == true, "switching back did not rebind the page")

------------------------------------------------------------------ combat refusal
local text = Config().listsData
writes = historyWrites
Click(grid.tiles[1], "LeftButton")
assert(pop.shown, "popover should be open before combat")
local watcher
for _, frame in ipairs(frames) do if frame.events.PLAYER_REGEN_DISABLED then watcher = frame end end
assert(watcher and watcher.events.GLOBAL_MOUSE_DOWN, "popups do not listen for combat and outside clicks")
cursorX, cursorY = 100, 100
Fire(handle, "OnMouseDown", "LeftButton")
cursorX, cursorY = 150, 100
Fire(handle, "OnUpdate", 0.01)
assert(handle.dragging and runtime.frame.points[1][4] == 50, "preview drag did not start")
combat = true
Fire(handle, "OnUpdate", 0.01)
assert(handle.scripts.OnUpdate == nil and not handle.dragging and runtime.frame.points[1][4] == 0,
    "combat must end a preview drag and center the drawing")
Fire(handle, "OnMouseDown", "LeftButton")
assert(handle.scripts.OnUpdate == nil, "preview drag armed in combat")
Fire(watcher, "OnEvent", "PLAYER_REGEN_DISABLED")
assert(not pop.shown and not watcher.events.PLAYER_REGEN_DISABLED, "combat did not close the popups")
assert(not Page.AddEntry("ess", "b5", 1) and not Page.RemoveEntry("ess", "b1") and not Page.MoveEntry("b1", "uti"),
    "list edits must be refused in combat")
assert(not Page.SetSpellField("b1", "readyGlow", true) and not Page.TogglePicker(grid.plus) and not Page.AddBar(1),
    "combat must refuse spell options, the picker and new bars")
Click(grid.tiles[1], "MiddleButton")
Fire(grid.tiles[1], "OnMouseDown", "LeftButton")
assert(host.scripts.OnUpdate == nil, "drag armed in combat")
size.set(30)
assert(Config().listsData == text and historyWrites == writes and Config().ess_size ~= 30, "combat wrote settings")
combat = false

------------------------------------------------------------------ teardown
Click(grid.tiles[1], "MiddleButton")
assert(PendingTasks() == 1, "undo line timer missing")
Click(grid.tiles[1], "LeftButton")
Fire(grid.tiles[1], "OnMouseDown", "LeftButton")
ui.previewBody:Hide()
host:Hide()
assert(PendingTasks() == 0 and host.scripts.OnUpdate == nil, "hiding the page left a timer or drag driver")
assert(not pop.shown and not watcher.events.PLAYER_REGEN_DISABLED and not watcher.events.GLOBAL_MOUSE_DOWN, "popups outlived the page")
assert(runtime.previewOn == false and runtime.simulate == false and runtime.released > 0, "preview mode outlived the page")
for key in pairs(_G) do
    if not globalsBefore[key] then error("options page created global " .. tostring(key)) end
end
print("Suite cooldown manager options: registration, template coverage, selected-bar keys, name commits, attach targets, tile memo, list edits, picker, popover, bar reuse, preview drag, simulation, layouts, combat refusal and teardown passed")
