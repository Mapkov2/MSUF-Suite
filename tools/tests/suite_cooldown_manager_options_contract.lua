local root = assert(arg[1], "repository root required")
-- Offline contract for the cooldown manager options page
-- (MSUF_Suite_Options/Pages/CooldownManager*.lua): registration, setting
-- coverage through custom bar 1's template rules, selected-bar key mapping,
-- attach targets (bars plus the player and target frames, no loops), Frame
-- Basics (module-wide rules, bar choice, name, type and bar actions), list
-- edits (codec + one history entry per gesture, Undo for anything that
-- drops data), the spell picker, the per-spell popover (text rows of the
-- shared text contract, row help), the preview as spell editor (pooled icon
-- buttons over the runtime canvas, marks), combat refusal and teardown when
-- the page hides. Budgets: a settings write that cannot change the spell
-- tiles makes no runtime call for them; a repaint of the same preview writes
-- no layout; navigation buttons take no history snapshot; the only
-- per-frame work is a drag, cleared on release, hide and combat.
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
function methods:GetScale() return self.scale end
function methods:GetCenter() return self.cx, self.cy end
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
-- Blizzard's Cooldown Manager sound list (Blizzard_CooldownViewer), read only:
-- any write from the page fails. Category 1 has a global string, 6 a plain
-- enum name, 9 neither; broken rows are skipped.
Enum.CooldownViewerSoundCategory = { Animals = 1, War2 = 6 }
COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_ANIMALS = "Animal sounds"
local function ReadOnly(tbl)
    return setmetatable(tbl, { __newindex = function() error("Blizzard's sound data was written", 2) end })
end
local blizzardSounds = {
    [1] = { { soundEnum = 1, soundKitID = 316401, text = "Cat" }, { soundEnum = 2, soundKitID = 316406, text = "Chicken" } },
    [6] = { { soundEnum = 3, soundKitID = 316731, text = "Abstract Whoosh" }, { soundEnum = 4, soundKitID = 0, text = "Broken" },
        "junk" },
    [9] = { { soundEnum = 5, soundKitID = 353392 } },
}
for _, rows in pairs(blizzardSounds) do
    for _, row in ipairs(rows) do if type(row) == "table" then ReadOnly(row) end end
    ReadOnly(rows)
end
CooldownViewerSoundData = ReadOnly(blizzardSounds)
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
W.AttachContextColorShortcut = function(section, opts)
    local shortcut = { options = opts }
    section.colorShortcut = shortcut
    return shortcut
end
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
    function b:CollapsibleSection(id, title, _, open)
        local body = Widget("Section")
        body.sectionId, body.title, body.defaultOpen = id, title, open == true
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
-- The shared text contract: per bar cdText, stackText ("Show charges and
-- stacks") and textTop ("Text on top": Stacks, Countdown) on every bar kind;
-- per spell timeText, stackText and textTop stored as 1..3.
for _, slot in ipairs(CDM.SLOTS) do
    local k = CDM.KEYS[slot.key]
    assert(k.cdText and k.stackText and k.textTop, "the text rules must reach every bar kind: " .. slot.key)
end
local textTopRule = Suite.SuiteCatalog.cooldownManager.rules[CDM.KEYS.c1.textTop]
assert(textTopRule.label == "Text on top" and textTopRule.default == 1 and textTopRule.choices[1] == "Stacks"
    and textTopRule.choices[2] == "Countdown", "Text on top rule")
for _, field in ipairs({ "timeText", "stackText", "textTop" }) do
    local valid = CDM.SPELL_FIELDS[field]
    assert(valid and not valid(0) and valid(1) and valid(3) and not valid(4), "spell text field " .. field)
end
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
-- units: what "Automatic" resolved an entry's buff to (optional runtime field).
local runtime = { played = {}, released = 0, specID = 62, units = {} }
local CATALOG_ORDER = { "b1", "b2", "b3", "b4", "b5", "b6", "b10", "b11", "b20", "b30", "b40" }
-- Rows carry their spell IDs where the runtime knows them (b1 has none, so
-- both shapes are covered).
-- hasAura: a cooldown that tracks a buff (its stacks show on the icon).
local CATALOG = {
    b1 = { name = "Fireball", texture = 101, family = 1, known = true, hasAura = true },
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
                known = not record or record.known, family = entryFamily, hidden = key == "b2",
                hiddenBy = key == "b2" and "ready" or nil, hasAura = record and record.hasAura, unit = runtime.units[key] }
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
    -- Like Preview.lua's canvas: per drawn item its region (icon, or row for
    -- buff bars), entry key (false for a sample) and dim flag, capped by
    -- the bar's icon limit; regions are pooled.
    S.CooldownManagerRenderPreview = function(parent, slot, w, h)
        runtime.rendered = { parent = parent, slot = slot, w = w, h = h }
        local frame = runtime.frame or Widget("Frame", parent)
        runtime.frame = frame
        frame.icons, frame.rows, frame.keys, frame.dim = frame.icons or {}, frame.rows or {}, frame.keys or {}, frame.dim or {}
        local info = CDM.SLOTS[CDM.SLOT_INDEX[slot]]
        local kind = info.custom and Config()[slot .. "_kind"] or info.kind
        local n = 0
        for i, entry in ipairs(Resolve()[slot]) do
            n = i
            frame.keys[i], frame.dim[i] = entry.key, entry.known == false
        end
        if n == 0 then
            for i = 1, 3 do frame.keys[i], frame.dim[i] = false, true end
            n = 3
        end
        for i = #frame.keys, n + 1, -1 do frame.keys[i], frame.dim[i] = nil, nil end
        local cap = Config()[slot .. "_maxIcons"]
        local count = type(cap) == "number" and cap > 0 and math.min(cap, n) or n
        frame.items = kind == 3 and frame.rows or frame.icons
        for i = 1, count do frame.items[i] = frame.items[i] or Widget(kind == 3 and "Row" or "Icon", frame) end
        frame.count, frame.kind = count, kind
        return frame
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
    S.CooldownManagerBlizzardSnapshot = function()
        return { ess={"b2","b1"},uti={"b4"},buf={"b10"},bar={},ext={"b30"} }
    end
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
for _, file in ipairs({ "Menu/Bridge.lua", "Menu/Controls.lua", "Pages/CooldownManagerData.lua",
    "Pages/CooldownManagerWidgets.lua", "Pages/CooldownManagerPopover.lua",
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
-- Navigation clicks never take Menu2's full settings snapshot. Frame Basics
-- is one block: the two module actions, the rules for every bar, then the
-- bar choice (selector, + Add bar, Bar actions, name and type) and the
-- selected bar's summary.
local cardButtons = 0
for _, child in ipairs(ctx.sections[1].children or {}) do
    if child.kind == "Button" then
        cardButtons = cardButtons + 1
        assert(child._msuf2SkipHistoryCheckpoint, "module card action takes a history snapshot: " .. tostring(child.text))
    end
end
assert(cardButtons == 4 and registered["menu2." .. PAGE .. ".cooldownManager.editor.add"].parent == ctx.sections[1]
    and registered["menu2." .. PAGE .. ".cooldownManager.editor.actions"].parent == ctx.sections[1],
    "Frame Basics must hold the two module actions, + Add bar and Bar actions")
assert(ctx.sections[1].title == "Frame Basics" and ctx.sections[1].defaultOpen, "Frame Basics comes first and open")
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

-- Sections and coverage through template keys; the bar's name and type sit
-- in Frame Basics.
local suffixes = {}
for _, suffix in ipairs(Page.CARD_SUFFIXES) do suffixes[suffix] = "card" end
for _, section in ipairs(Page.SECTIONS) do
    for _, suffix in ipairs(section.suffixes) do
        assert(not suffixes[suffix], "suffix listed twice: " .. suffix)
        suffixes[suffix] = section.id
    end
end
for suffix in pairs(CDM.KEYS.c1) do assert(suffixes[suffix], "no section for " .. suffix) end
assert(suffixes.stackText == "text" and suffixes.textTop == "text" and suffixes.cdText == "text",
    "the text switches and Text on top belong to Text")
-- Every rule has exactly one control on the page (Basics takes its rules
-- from the topic sections, it does not repeat them).
local covered = {}
for _, widget in ipairs(ctx.widgets) do
    assert(widget.rowKind ~= "color", "Cooldown Manager still renders an inline color box")
    local key = widget.meta and widget.meta.settingKey
    if key then
        assert(not covered[key], "setting shown twice on the page: " .. key)
        covered[key] = widget
        local prefix = key:match("^msufsuite%.cooldownManager%.(%w+)_")
        assert(not prefix or prefix == "c1", "control bound to a live per-bar key: " .. key)
    end
end
for _, section in ipairs(ctx.sections) do
    if type(section.colorShortcut) == "table" then
        local targets = section.colorShortcut.options.getTargets()
        assert(#targets <= section.colorShortcut.options.maxTargets,
            "Cooldown Manager color shortcut truncates its targets")
        for _, target in ipairs(targets) do
            local key = target.sourceSettingKey or target.settingKey
            assert(not covered[key], "color shown twice on the page: " .. key)
            covered[key] = target
        end
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
-- The former General section lives in Frame Basics, each rule once: the two
-- lists side by side, then the switches; the bar's name and type follow.
assert(not registered["menu2." .. PAGE .. ".section.suite_cooldownManager_general.expanded"], "General is no section any more")
for _, section in ipairs(ctx.sections) do
    assert(section.sectionId ~= "suite_cooldownManager_general", "General must live in Frame Basics")
end
local generalOrder = {}
for i, key in ipairs({ "blizzard", "soundChannel", "showGCD", "muteSounds", "readyGlowCombat" }) do
    local control = Control(key)
    assert(control.parent == ctx.sections[1] and control.meta.sectionId == PAGE .. "_cooldownManager_module",
        "Frame Basics lacks " .. key)
    for index, widget in ipairs(ctx.widgets) do if widget == control then generalOrder[i] = index end end
end
for i = 2, #generalOrder do assert(generalOrder[i] > generalOrder[i - 1], "Frame Basics rules out of order") end
for _, suffix in ipairs(Page.CARD_SUFFIXES) do
    assert(Control(suffix).parent == ctx.sections[1], "Frame Basics lacks the bar's " .. suffix)
end
local kindList = Control("kind").row.values
assert(kindList[1].text == "Cooldown bar" and kindList[2].text == "Buff icon bar" and kindList[3].text == "Timer bar",
    "one name per bar type")
-- Blizzard's choices explain themselves; the current one says what runs now.
local blizzardList = Control("blizzard").row.values
local offTip = blizzardList[1].tooltip(blizzardList[1])
assert(offTip:find("stops completely", 1, true) and offTip:find("Right now: Blizzard's bars are off.", 1, true)
    and not blizzardList[2].tooltip(blizzardList[2]):find("Right now", 1, true), "Blizzard's choices lack their reasons")
-- The sound channel means nothing while the module's sounds are muted.
M.RequestRefresh()
assert(Control("soundChannel").enabled, "the sound channel must be editable")
Config().muteSounds = true
M.RequestRefresh()
assert(not Control("soundChannel").enabled and Control("muteSounds").enabled, "muted sounds must grey the channel")
Config().muteSounds = false
M.RequestRefresh()

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
local order, openSections = {}, {}
for i, section in ipairs(ctx.sections) do
    order[i] = section.sectionId:gsub("^suite_cooldownManager_", "")
    if section.defaultOpen then openSections[#openSections + 1] = order[i] end
end
assert(table.concat(order, ",") == "cooldownManager_module,basics,spells,layout,look,text,effects,buffs,barstyle,visibility",
    "unexpected section order: " .. table.concat(order, ","))
assert(table.concat(openSections, ",") == "cooldownManager_module,basics", "only Frame Basics and Basics start open: "
    .. table.concat(openSections, ","))
assert(ctx.sections[3].title == "Spell list", "the tile section is the Spell list")
assert(ctx.sections[9].title == "Timer bar style", "the timer bar section says what it styles")
assert(ctx.sections[2]._msuf2CollapsibleEntry.label.text == "Basics: Utility cooldowns"
    and ctx.sections[4]._msuf2CollapsibleEntry.label.text:find("Utility cooldowns", 1, true),
    "section headers do not name the selected bar")
-- Basics holds the most used settings of the bar, the attachment complete.
for _, suffix in ipairs({ "on", "size", "perRow", "anchor", "side", "gap", "align", "alpha" }) do
    assert(Control(suffix).parent == ctx.sections[2], "Basics lacks " .. suffix)
end
assert(Control("grow").parent == ctx.sections[4] and Control("zoom").parent == ctx.sections[5],
    "Layout and Look keep the rest")
-- Opacity out of combat sits with the other visibility rules; the text
-- switches and Text on top in Text.
assert(Control("oocAlpha").parent == ctx.sections[10] and Control("vis").parent == ctx.sections[10],
    "Visibility holds the fade out of combat")
for _, suffix in ipairs({ "cdText", "stackText", "textTop", "stackPos" }) do
    assert(Control(suffix).parent == ctx.sections[6], "Text lacks " .. suffix)
end
local textTop = Control("textTop").row.values
assert(#textTop == 2 and textTop[1].text == "Stacks" and textTop[2].text == "Countdown", "Text on top choices")
picker.set("bar")
M.RequestRefresh()
assert(not size.enabled and Control("barWidth").enabled and not Control("desat").enabled and Control("pandemic").enabled,
    "controls must follow the bar type of the selected bar")
assert(Control("grow").enabled and not Control("spacing").enabled and not Control("zoom").enabled,
    "the built-in Buff bars row has fixed spacing and icon look")
assert(not Control("name").enabled and not Control("kind").enabled, "built-in bars cannot be renamed or retyped")
assert(not Control("glowStyle").enabled and not Control("glowTint").enabled,
    "the built-in Buff bars row has no bar-level glow look")
picker.set("c2")
M.RequestRefresh()
assert(Control("name").enabled and Control("kind").enabled and size.enabled and Control("desat").enabled
    and not Control("barWidth").enabled, "custom cooldown bar gates are wrong")
Config().c2_kind = 3
M.RequestRefresh()
assert(not size.enabled and Control("barWidth").enabled, "custom bar type change did not re-gate controls")
-- A custom Buff bar bar keeps what the runtime reads for it.
for suffix in pairs(Page.KIND3_EXTRA) do
    local control = Control(suffix)
    assert(control.sourceSettingKey and control.isEnabled() or control.enabled,
        "custom buff bars use " .. suffix)
end
assert(Control("grow").enabled and not Control("perRow").enabled and not Control("vertical").enabled
    and not Control("desat").enabled, "custom buff bar gates are wrong")
-- Custom buff bars of both types keep the glow look their aura glows use.
for _, kind in ipairs({ 3, 2 }) do
    Config().c2_kind = kind
    M.RequestRefresh()
    for suffix in pairs(Page.AURA_EXTRA) do
        assert(Page.Relevant("c2", suffix), "custom buff bars (type " .. kind .. ") use " .. suffix)
    end
    assert(Control("glowStyle").enabled and Control("glowTint").enabled and not Control("readyGlow").enabled,
        "custom buff bar glow look gates are wrong (type " .. kind .. ")")
end
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
assert(anchor.row.values[2].disabled and anchor.row.values[2].text == "Essential cooldowns"
    and anchor.row.values[2].tooltip(anchor.row.values[2]) == "A bar cannot attach to itself.", "a bar cannot attach to itself")
-- Utility follows Essential, Buffs follows Utility, Buff bars follows Buffs:
-- attaching Essential to any of them would close a loop (the runtime then
-- frees every bar of it). Defensives sit on the player frame.
for i, slot in ipairs({ "uti", "buf", "bar" }) do
    local item = anchor.row.values[CDM.SLOT_INDEX[slot] + 1]
    assert(item.disabled and item.loopOf == slot, "attach loop offered: " .. slot)
    local tip = item.tooltip(item)
    assert(tip:find(Page.BarName(slot), 1, true) and tip:find("loop", 1, true), "the loop entry must say why: " .. tip)
end
assert(not anchor.row.values[CDM.SLOT_INDEX.def + 1].disabled and not anchor.row.values[CDM.SLOT_INDEX.c1 + 1].disabled
    and anchor.row.values[CDM.SLOT_INDEX.def + 1].tooltip(anchor.row.values[CDM.SLOT_INDEX.def + 1]) == nil,
    "bars outside the chain stay selectable")
-- Old settings that already hold a loop say so in the summary.
Config().ess_anchor = CDM.SLOT_INDEX.uti + 1
assert(Page.InLoop("ess") and Page.InLoop("uti") and not Page.InLoop("buf")
    and Page.Summary("ess"):find("loop", 1, true), "a loop in saved settings is not reported: " .. Page.Summary("ess"))
Config().ess_anchor = 1
M.RequestRefresh()
assert(not Page.InLoop("ess") and not anchor.row.values[CDM.SLOT_INDEX.def + 1].disabled, "the loop check stuck")
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

-- Import copies one Blizzard spec's built-in order, keeps Suite custom bars
-- and every other spec, and its complete-list flags survive the codec.
do
    local before = Config().listsData
    Config().listsData = assert(CDM.Codec.EncodeLists({specs={
        [62]={c1={"b2"},ess={"i5512"}},[63]={ess={"b3"}}},
        hidden={[62]={b1=true,s9001=true}}}))
    local personal = Config().listsData
    assert(Page.ImportBlizzardWithUndo())
    local data = Lists()
    assert(table.concat(data.specs[62].ess,",")=="b1" and data.specs[62].c1[1]=="b2"
        and data.specs[63].ess[1]=="b3" and data.replace[62].ess and data.replace[62].bar
        and data.hidden[62].b1==nil and data.hidden[62].s9001==true,
        "Blizzard import must copy only the current spec's built-in bars")
    local profile = assert(Suite.ProfileIO.PrepareTable(Suite.DB,false))
    assert(profile.suite.modules.cooldownManager.listsData==Config().listsData
        and profile.suite.modules.cooldownManager.raidEssentials==true,
        "Suite profile export must carry the imported CDM layout and default choice")
    Page.RunUndo()
    assert(Config().listsData==personal,"Blizzard import Undo must restore the original list")
    Config().listsData=before
end

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

-- The Spell list's list-wide actions say what they drop, are one history
-- entry each and offer Undo (also one entry).
do
    local buttons = ui.spellButtons
    assert(Page.ClearLabel("uti") == "Restore spec defaults"
        and Page.ClearLabel("buf") == "Restore spec defaults"
        and Page.ClearLabel("bar") == "Restore spec defaults", "spec profile reset labels")
    Config().raidEssentials = false
    assert(Page.ClearLabel("uti") == "Reset to Blizzard's list", "native reset label")
    Config().raidEssentials = true
    M.RequestRefresh()
    assert(buttons.clear.text == "Restore raid essentials" and buttons.clear.enabled and buttons.copy.enabled
        and not buttons.restore.enabled, "Spell list actions on a built-in bar")
    Fire(buttons.clear, "OnEnter")
    assert(tooltip.text == "Restore raid essentials" and tooltip.line:find("other bars", 1, true), "the reset must say what it drops")
    Fire(buttons.clear, "OnLeave")
    local listsNow = Config().listsData
    local writes = historyWrites
    Click(buttons.clear, "LeftButton")
    assert(not (Lists().specs[62] and Lists().specs[62].ess) and historyWrites == writes + 1
        and Page.note == "Essential cooldowns is back to its raid essentials." and Page.undo, "restore raid essentials")
    Page.RunUndo()
    assert(Config().listsData == listsNow and Keys("ess") == "b1,b2,b3,b4,i5512" and historyWrites == writes + 2,
        "undo did not bring the bar's list back")
    -- Removed Blizzard entries come back as one gesture, with Undo.
    assert(Page.RemoveEntry("ess", "b2"))
    local hiddenNow = Config().listsData
    M.RequestRefresh()
    assert(buttons.restore.enabled and buttons.restore.text == "Show removed spells, all bars (1)", "restore count")
    Click(buttons.restore, "LeftButton")
    assert(not Lists().hidden[62] and Page.note == "Brought back the removed spells (1)." and Page.undo, "show removed spells")
    Page.RunUndo()
    assert(Config().listsData == hiddenNow, "undo did not hide the spells again")
    Config().listsData = listsNow
    -- The player's own entries go to the same bar in the other specializations.
    Fire(buttons.copy, "OnEnter")
    assert(tooltip.line:find("other specializations", 1, true), "the copy must say what it copies")
    Fire(buttons.copy, "OnLeave")
    writes = historyWrites
    Click(buttons.copy, "LeftButton")
    assert(Lists().specs[63].ess[1] == "i5512" and Lists().specs[64].ess[1] == "i5512" and #Lists().specs[63].ess == 1
        and historyWrites == writes + 1 and Page.note == "Copied 2 entries to 2 other specializations.", "copy the bar's list")
    Click(buttons.copy, "LeftButton")
    assert(historyWrites == writes + 1 and Page.note == "Your other specializations have them already." and not Page.undo,
        "a second copy must change nothing")
    Config().listsData = listsNow
    picker.set("uti")
    M.RequestRefresh()
    assert(not buttons.copy.enabled, "a bar without entries of your own has nothing to copy")
    picker.set("c3")
    M.RequestRefresh()
    assert(buttons.clear.text == "Remove all spells", "custom bars empty their list")
    picker.set("def")
    M.RequestRefresh()
    assert(buttons.clear.text == "Restore default spells", "Defensives go back to their preset")
    picker.set("ess")
    Page.ClearNote()
    M.RequestRefresh()
end

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
    -- A row may also hold a second field (the stack color beside its threshold).
    if field.color then
        assert(CDM.SPELL_FIELDS[field.color] and not fieldRows[field.color], "bad companion field " .. field.color)
        fieldRows[field.color] = true
    end
end
for field in pairs(CDM.SPELL_FIELDS) do assert(fieldRows[field], "no popover row for spell field " .. field) end
local tile = grid.tiles[1]
Click(tile, "LeftButton")
local pop = assert(Page.popover)
assert(pop.shown and pop.key == "b2" and pop.anchor == tile, "popover did not open on the tile")
assert(pop.rows.readyGlow.shown and not pop.rows.auraGlow and not pop.rows.lossSound, "popover rows must follow the entry family")
assert(not pop.hasAura and not pop.rows.stackGlow and not pop.rows.stackColorAt and not pop.rows.auraUnit,
    "a cooldown without a buff has no stack options and no Track on")
-- Controls end left of the per-row reset button (the row is 290 wide).
local resetLeft = pop.rows.readyGlow.reset.parent.width - pop.rows.readyGlow.reset.width
assert(Page.POP_X + pop.rows.glowStyle.choice.width <= resetLeft
    and Page.POP_X + pop.rows.sound.choice.width + 2 + pop.rows.sound.play.width <= resetLeft, "a control runs under the reset button")
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
assert(Page.SpellField("b2", "readyAlpha") == 99, "stepper must start from the bar value in single steps")
IsShiftKeyDown = function() return true end
Fire(pop.rows.readyAlpha.minus, "OnClick")
assert(Page.SpellField("b2", "readyAlpha") == 94, "Shift stepper must move by five")
IsShiftKeyDown = nil
IsControlKeyDown = function() return true end
Fire(pop.rows.readyAlpha.minus, "OnClick")
assert(Page.SpellField("b2", "readyAlpha") == 84, "Ctrl stepper must move by ten")
IsControlKeyDown = nil
Fire(pop.rows.glowColor.swatches[3], "OnClick")
assert(Page.SpellField("b2", "glowColor") == "ff4d4d", "color swatch failed")
Fire(pop.rows.icon.edit, "OnEnterPressed")
assert(Page.SpellField("b2", "icon") == nil, "empty icon field must not write")
pop.rows.icon.edit:SetText("12345")
Fire(pop.rows.icon.edit, "OnEnterPressed")
assert(Page.SpellField("b2", "icon") == 12345, "custom icon failed")
-- Sound picker: None, Blizzard's Cooldown Manager sounds by category, then
-- the LSM list; filter, play, pick.
local settingsToggles = toggledBlizzard
Fire(pop.rows.sound.choice, "OnClick")
local sounds = assert(Page.soundPicker)
-- Blizzard's list is read once per data table and kept.
local kits = assert(Page.BlizzardSounds(), "Blizzard's sound list missing")
local firstGroup = kits.groups[1]
assert(#kits.groups == 3 and Page.BlizzardSounds() == kits and kits.groups[1] == firstGroup,
    "Blizzard's sound list must be built once per data table")
assert(sounds.shown and pop.shown, "sound picker must open above the popover")
local function SoundRows()
    local out, texts = {}, {}
    for _, row in ipairs(sounds.rows) do
        if row.shown and row.item then out[#out + 1] = row; texts[#texts + 1] = row.text.text end
    end
    return out, table.concat(texts, "|")
end
local function FilterSounds(text)
    sounds.search:SetText(text)
    Fire(sounds.search, "OnTextChanged", true)
    return SoundRows()
end
local listed, listText = SoundRows()
assert(listText == "None|Blizzard Cooldown Manager|Animal sounds|Cat|Chicken|War 2|Abstract Whoosh|Category 9|"
    .. "Sound kit 353392|Shared media|Boom|Bell|Chime", "sound list order: " .. listText)
assert(listed[2].item.header == 1 and listed[3].item.header == 2 and not listed[2].play.shown and not listed[3].play.shown
    and listed[4].play.shown and not listed[1].play.shown, "headers and None have no Play button")
assert(listed[2].text.textColor[1] == 0.2 and listed[3].text.textColor[1] == 0.5, "section and category headers are styled")
assert(listed[4].item.value == "kit:316401" and listed[9].item.value == "kit:353392", "Blizzard sounds are kit values")
Fire(listed[3], "OnClick")
assert(sounds.shown and Page.SpellField("b2", "sound") == nil, "a header is not a sound")
Fire(listed[4].play, "OnClick")
assert(runtime.played[#runtime.played] == "kit:316401", "Blizzard sound preview must play the kit through the runtime")
local _, found = FilterSounds("animal")
assert(found == "Blizzard Cooldown Manager|Animal sounds|Cat|Chicken", "a category name must find its sounds: " .. found)
_, found = FilterSounds("whoosh")
assert(found == "Blizzard Cooldown Manager|War 2|Abstract Whoosh", "Blizzard sounds must be found by name: " .. found)
_, found = FilterSounds("zzz")
assert(found == "", "headers without a match must hide")
listed = FilterSounds("be")
local bell = listed[2]
assert(#listed == 2 and listed[1].item.header == 1 and bell.item.value == "lsm:Bell", "sound filter failed")
Fire(bell.play, "OnClick")
assert(runtime.played[#runtime.played] == "lsm:Bell", "sound preview failed")
Fire(bell, "OnClick")
assert(Page.SpellField("b2", "sound") == "lsm:Bell" and not sounds.shown, "sound pick failed")
Fire(pop.rows.sound.play, "OnClick")
assert(runtime.played[#runtime.played] == "lsm:Bell", "row play button failed")
-- A Blizzard sound shows its name; reopened, it is marked in its category
-- and not listed a second time. Reopening reuses the pooled rows and items.
local soundFrames, soundItems = #frames, sounds.items
Fire(pop.rows.sound.choice, "OnClick")
listed = FilterSounds("chick")
Fire(listed[3], "OnClick")
assert(Page.SpellField("b2", "sound") == "kit:316406" and pop.rows.sound.choice.text == "Chicken", "Blizzard sound pick failed")
Fire(pop.rows.sound.choice, "OnClick")
listed, listText = SoundRows()
assert(listText:find("^None|Blizzard Cooldown Manager|") and listed[5].item.value == "kit:316406"
    and listed[5].text.textColor[1] == 0.2 and listed[4].text.textColor[1] == 1, "the current Blizzard sound is not marked")
assert(#frames == soundFrames and sounds.items == soundItems and Page.BlizzardSounds() == kits,
    "reopening the sound picker must reuse its rows, items and Blizzard's list")
Fire(sounds.close, "OnClick")
-- Without Blizzard's list the section is hidden and a kit keeps a plain label.
CooldownViewerSoundData = nil
Fire(pop.rows.sound.choice, "OnClick")
_, listText = SoundRows()
assert(listText == "None|Sound kit 316406|Shared media|Boom|Bell|Chime", "sound list without Blizzard's data: " .. listText)
assert(#frames == soundFrames, "the sound picker without Blizzard's list must reuse its rows")
Fire(sounds.close, "OnClick")
CooldownViewerSoundData = blizzardSounds
M.RequestRefresh()
assert(pop.rows.sound.choice.text == "Chicken", "the sound label did not come back with Blizzard's list")
assert(toggledBlizzard == settingsToggles, "the sound picker must never drive Blizzard's settings panel")
writes = historyWrites
Fire(pop.reset, "OnClick")
assert(Page.SpellOverrides().e.b2 == nil and historyWrites == writes + 1, "reset spell failed")
-- The text rows of the shared contract: Countdown, Charges and Text on top,
-- each "Bar setting" by default and naming the bar's current choice; 2 and 3
-- are stored, "Bar setting" clears. One history entry per pick.
do
    local countdown, charges, top = pop.rows.timeText, pop.rows.stackText, pop.rows.textTop
    assert(countdown and countdown.shown and charges.shown and top.shown, "cooldowns offer the text rows")
    assert(countdown.label.text == "Countdown" and charges.label.text == "Charges" and top.label.text == "Text on top",
        "text row labels of a cooldown")
    assert(countdown.points[1][5] == pop.rows.swipe.points[1][5] - 26 and pop.rows.threshold.points[1][5] == top.points[1][5] - 26,
        "the text rows sit between Swipe and Warn below")
    assert(countdown.choice.text == "Bar: Show" and charges.choice.text == "Bar: Show" and top.choice.text == "Bar: Stacks"
        and not countdown.reset.shown, "text rows follow the bar and say how")
    for _, row in ipairs({ countdown, charges, top }) do
        assert(Page.POP_X + row.choice.width <= resetLeft, "a text choice runs under the reset button")
        local menu = {}
        for i, item in ipairs(row.field.menu) do menu[i] = item.value .. "=" .. item.text end
        assert(menu[1] == "0=Bar setting" and #menu == 3, "text rows start with Bar setting: " .. table.concat(menu, ","))
    end
    writes = historyWrites
    Fire(countdown.choice, "OnClick")
    assert(lastDropdown.owner == countdown.choice and lastDropdown.current == 0, "the Countdown list did not open on Bar setting")
    lastDropdown.onSelect(3)
    assert(Page.SpellField("b2", "timeText") == 3 and countdown.choice.text == "Hide" and countdown.reset.shown
        and countdown.label.textColor[1] == 0.2 and historyWrites == writes + 1, "Countdown: Hide failed")
    Fire(top.choice, "OnClick")
    lastDropdown.onSelect(3)
    assert(Page.SpellField("b2", "textTop") == 3 and top.choice.text == "Countdown", "Text on top: Countdown failed")
    Fire(charges.choice, "OnClick")
    lastDropdown.onSelect(2)
    assert(Page.SpellField("b2", "stackText") == 2 and charges.choice.text == "Show" and historyWrites == writes + 3,
        "Charges: Show failed")
    lastDropdown.onSelect(0)
    assert(Page.SpellField("b2", "stackText") == nil and charges.choice.text == "Bar: Show" and not charges.reset.shown,
        "Bar setting must clear the field")
    -- The bar's own choice shows through while the spell follows it.
    Config().ess_cdText, Config().ess_textTop = false, 2
    Fire(countdown.reset, "OnClick")
    assert(Page.SpellField("b2", "timeText") == nil and countdown.choice.text == "Bar: Hide", "the countdown hint must follow the bar")
    Fire(top.reset, "OnClick")
    assert(top.choice.text == "Bar: Countdown", "Text on top must name the bar's choice")
    Config().ess_cdText, Config().ess_textTop = true, 1
    M.RequestRefresh()
    assert(countdown.choice.text == "Bar: Show" and Page.SpellOverrides().e.b2 == nil, "text rows did not follow the bar back")
    -- Values outside the contract are refused.
    assert(not Page.SetSpellField("b2", "timeText", 0) and not Page.SetSpellField("b2", "textTop", 4)
        and not Page.SetSpellField("b2", "stackText", 1.5), "a text row stored an invalid value")
    -- Every label explains its row; the hint of rows without a bar setting is right.
    Fire(countdown.tip, "OnEnter")
    assert(tooltip.shown and tooltip.owner == countdown.tip and tooltip.text == "Countdown"
        and tooltip.line:find("countdown numbers", 1, true), "the Countdown label does not explain itself")
    Fire(countdown.tip, "OnLeave")
    assert(not tooltip.shown, "leaving the label must hide its tooltip")
    for _, field in ipairs(Page.FIELDS) do assert(type(field.help) == "string" and field.help ~= "", "no help for " .. field.key) end
    assert(pop.rows.threshold.hint.text == "All bars" and pop.rows.readyAlpha.hint.text == "Bar",
        "Warn below follows the module-wide setting, not the bar")
    -- Say the name: On, or nothing (there is no bar setting to follow).
    local tts = pop.rows.tts
    assert(tts.hint.text == "" and tts.off.active and not tts.on.active, "Say the name starts off, without a bar hint")
    Fire(tts.on, "OnClick")
    assert(Page.SpellField("b2", "tts") == true and tts.on.active and tts.reset.shown, "Say the name: On failed")
    Fire(tts.on, "OnClick")
    assert(Page.SpellField("b2", "tts") == true, "a second On keeps it on")
    Fire(tts.off, "OnClick")
    assert(Page.SpellField("b2", "tts") == nil and tts.off.active and not tts.reset.shown, "Off must clear, not store false")
    -- Header actions fit their captions and wrap; a Blizzard entry has three.
    assert(not pop.copy.shown and pop.remove.width == 90 and pop.move.points[1][4] == 106
        and pop.reset.points[1][5] == -54, "the header actions must sit on one line")
    assert(pop.scope.text:find("every bar and specialization", 1, true), "the popover must say where its choices apply")
end
-- Move to bar from the popover.
Fire(pop.move, "OnClick")
local names = {}
for _, item in ipairs(lastDropdown.values) do names[#names + 1] = item.value .. (item.disabled and "-" or "+") end
assert(table.concat(names, ",") == "uti+,def+,ext+,buf-,bar-", "move list must mark bars of the other family: " .. table.concat(names, ","))
lastDropdown.onSelect("ext")
assert(Keys("ext") == "b30,b2" and not pop.shown, "move to bar failed")
-- Stack options on a cooldown that shows its buff: steppers from Off, the
-- stack color beside its threshold, one history entry per gesture.
Click(grid.tiles[2], "LeftButton")
assert(pop.shown and pop.key == "b1" and pop.hasAura, "the popover did not open on the cooldown with a buff")
local stackGlow, stackColor = pop.rows.stackGlow, pop.rows.stackColorAt
assert(stackGlow and stackGlow.shown and stackColor.shown, "a cooldown that shows its buff offers the stack options")
assert(stackGlow.label.text == "Glow at stacks" and stackColor.label.text == "Color stacks from", "stack row labels")
assert(stackGlow.value.text == "Off" and stackColor.value.text == "Off" and not stackGlow.reset.shown
    and not stackColor.reset.shown and not stackGlow.hint and not stackColor.hint, "stack options start off, with no bar hint")
-- "Track on" (auraUnit): where the entry's buff is looked for. A stack row
-- right before "Glow at stacks"; Automatic (0) stores nothing, Me, Target
-- and Both store the runtime's 2, 3 and 4.
local trackOn = pop.rows.auraUnit
assert(trackOn and trackOn.shown and trackOn.label.text == "Track on" and trackOn.choice.text == "Automatic"
    and not trackOn.reset.shown and trackOn.label.textColor[1] ~= 0.2, "a cooldown that shows its buff offers Track on, Automatic")
assert(trackOn.points[1][5] == pop.rows.showAura.points[1][5] - 26 and stackGlow.points[1][5] == trackOn.points[1][5] - 26,
    "Track on sits under Show active buff duration, right before Glow at stacks")
assert(Page.POP_X + trackOn.choice.width <= resetLeft, "the Track on choice runs under the reset button")
do
    local field, index
    for i, candidate in ipairs(Page.FIELDS) do if candidate.key == "auraUnit" then field, index = candidate, i end end
    assert(field == trackOn.field and Page.FIELDS[index + 1].key == "stackGlow", "Track on must be the row before Glow at stacks")
    assert(field.kind == "choice" and field.stack and not field.cd and not field.aura and not field.auraLabel and not field.bar,
        "Track on is a stack row with one label and no bar value behind it")
    local choices = {}
    for i, item in ipairs(field.menu) do choices[i] = item.value .. "=" .. item.text end
    assert(table.concat(choices, ",") == "0=Automatic,2=Me,3=Target,4=Both", "Track on choices: " .. table.concat(choices, ","))
    local valid = CDM.SPELL_FIELDS.auraUnit
    assert(not valid(0) and valid(1) and valid(2) and valid(3) and valid(4) and not valid(5) and not valid(2.5),
        "the catalog stores 1 to 4; Automatic from the popover stores nothing")
    -- The stored values mean what the runtime makes of them (Resolve.lua).
    local file = assert(io.open(root .. "/MSUF_Suite_CooldownManager/Resolve.lua", "rb"))
    local literal = file:read("*a"):match("AURA_UNIT%s*=%s*(%b{})")
    file:close()
    local units = assert(literal and loadstring("return " .. literal), "the runtime's Track on map is missing")()
    assert(units[1] == nil and units[2] == "player" and units[3] == "target" and units[4] == "both",
        "Me, Target and Both must be the runtime's player, target and both")
    -- Stack-row gating: Blizzard's buffs and cooldowns that show their buff,
    -- never a plain cooldown or an item. Custom auras name their unit
    -- themselves (a: on you, d: on your target), so Track on would break them.
    local Applies = Page.FieldApplies
    assert(Applies(field, 2, "b", false) and not Applies(field, 2, "a", false) and not Applies(field, 2, "d", false)
        and Applies(field, 1, "b", true) and not Applies(field, 1, "b", false) and not Applies(field, 1, "s", false)
        and not Applies(field, 1, "s", true) and not Applies(field, 1, "i", false) and not Applies(field, 1, "e", false),
        "Track on must follow the stack rows of Blizzard's entries")
    local stackField = Page.FIELDS[index + 1]
    assert(Applies(stackField, 2, "a", false) and Applies(stackField, 2, "d", false), "custom auras keep their stack rows")
    -- Picks: one history entry each through the codec the runtime reads.
    local tileB1 = grid:Tile("b1")
    assert(tileB1 and not tileB1.mark.shown, "b1 starts without spell options")
    writes = historyWrites
    Fire(trackOn.choice, "OnClick")
    assert(lastDropdown.owner == trackOn.choice and lastDropdown.values == field.menu and lastDropdown.current == 0,
        "the Track on list did not open on Automatic")
    lastDropdown.onSelect(3)
    assert(Page.SpellField("b1", "auraUnit") == 3 and historyWrites == writes + 1 and trackOn.choice.text == "Target"
        and trackOn.reset.shown and trackOn.label.textColor[1] == 0.2 and tileB1.mark.shown, "Track on: Target failed")
    assert(CDM.Codec.DecodeSpells(Config().spellsData).e.b1.auraUnit == 3, "the choice must reach the stored spell options")
    Fire(trackOn.choice, "OnClick")
    assert(lastDropdown.current == 3, "the Track on list must mark the current choice")
    lastDropdown.onSelect(4)
    assert(Page.SpellField("b1", "auraUnit") == 4 and trackOn.choice.text == "Both", "Track on: Both failed")
    lastDropdown.onSelect(2)
    assert(Page.SpellField("b1", "auraUnit") == 2 and trackOn.choice.text == "Me" and historyWrites == writes + 3,
        "Track on: Me failed")
    -- Automatic clears the field: the spell is no longer customised.
    writes = historyWrites
    lastDropdown.onSelect(0)
    assert(Page.SpellField("b1", "auraUnit") == nil and Page.SpellOverrides().e.b1 == nil and historyWrites == writes + 1
        and trackOn.choice.text == "Automatic" and not trackOn.reset.shown and trackOn.label.textColor[1] ~= 0.2
        and not tileB1.mark.shown, "Automatic must clear the field, not store 0")
    lastDropdown.onSelect(0)
    assert(historyWrites == writes + 1, "Automatic on an automatic spell must not write")
    -- The row's reset clears it back to Automatic.
    lastDropdown.onSelect(3)
    writes = historyWrites
    Fire(trackOn.reset, "OnClick")
    assert(Page.SpellField("b1", "auraUnit") == nil and historyWrites == writes + 1 and trackOn.choice.text == "Automatic"
        and not trackOn.reset.shown, "the Track on reset must clear it back to Automatic")
    -- An explicit 1 (automatic, from an import) reads Automatic too.
    assert(Page.SetSpellField("b1", "auraUnit", 1) and trackOn.choice.text == "Automatic", "a stored 1 must read Automatic")
    lastDropdown.onSelect(0)
    assert(Page.SpellField("b1", "auraUnit") == nil, "Automatic must clear a stored 1")
    -- Values outside the catalog are refused, Automatic's 0 among them.
    writes = historyWrites
    assert(not Page.SetSpellField("b1", "auraUnit", 0) and not Page.SetSpellField("b1", "auraUnit", 5)
        and not Page.SetSpellField("b1", "auraUnit", 2.5) and not Page.SetSpellField("b1", "auraUnit", "3")
        and Page.SpellField("b1", "auraUnit") == nil and historyWrites == writes, "Track on stored an invalid value")
    -- Without Menu2's list, the choice steps through Me, Target, Both and
    -- back to Automatic.
    local openList = W.OpenDropdown
    W.OpenDropdown = nil
    local stepped = {}
    for i = 1, 4 do
        Fire(trackOn.choice, "OnClick")
        stepped[i] = tostring((Page.SpellField("b1", "auraUnit"))) .. "=" .. trackOn.choice.text
    end
    W.OpenDropdown = openList
    assert(table.concat(stepped, ",") == "2=Me,3=Target,4=Both,nil=Automatic",
        "Track on must step through its choices: " .. table.concat(stepped, ","))
    assert(Page.SpellOverrides().e.b1 == nil, "stepping back to Automatic must leave no spell options")
end
local stackReset = stackColor.reset.parent.width - stackColor.reset.width
assert(Page.POP_X + 22 + 2 + stackColor.value.width + 2 + 22 + 8 + stackColor.swatch.width <= stackReset,
    "the stack color swatch runs under the reset button")
local dr, dg, db = P.RGB("ff5a3c")
assert(stackColor.swatch.fill.color[1] == dr and stackColor.swatch.fill.color[2] == dg and stackColor.swatch.fill.color[3] == db
    and stackColor.swatch.alpha == 0.5, "the swatch shows the default stack color, dimmed while off")
writes = historyWrites
Fire(stackGlow.plus, "OnClick")
assert(Page.SpellField("b1", "stackGlow") == 1 and historyWrites == writes + 1 and stackGlow.value.text == "1"
    and stackGlow.reset.shown and stackGlow.label.textColor[1] == 0.2, "glow at stacks must step up from Off")
IsShiftKeyDown = function() return true end
Fire(stackGlow.plus, "OnClick")
IsShiftKeyDown = nil
assert(Page.SpellField("b1", "stackGlow") == 6, "Shift steps five stacks")
IsControlKeyDown = function() return true end
Fire(stackGlow.minus, "OnClick")
IsControlKeyDown = nil
assert(Page.SpellField("b1", "stackGlow") == nil and stackGlow.value.text == "Off" and not stackGlow.reset.shown,
    "stepping back to 0 must turn the stack glow off, not store 0")
assert(Page.SetSpellField("b1", "stackGlow", 99))
writes = historyWrites
Fire(stackGlow.plus, "OnClick")
assert(Page.SpellField("b1", "stackGlow") == 99 and historyWrites == writes, "glow at stacks stops at 99")
for _ = 1, 3 do Fire(stackColor.plus, "OnClick") end
assert(Page.SpellField("b1", "stackColorAt") == 3 and stackColor.value.text == "3" and stackColor.swatch.alpha == 1,
    "color stacks from failed")
Fire(stackColor.swatch, "OnEnter")
assert(tooltip.shown and tooltip.owner == stackColor.swatch and tooltip.text == "Stack color", "the swatch explains itself")
Fire(stackColor.swatch, "OnLeave")
Fire(stackColor.swatch, "OnClick")
assert(lastDropdown.owner == stackColor.swatch and lastDropdown.values == Page.COLOR_MENU and lastDropdown.current == "",
    "the stack color list did not open")
local defaultItem = lastDropdown.values[1]
assert(defaultItem.value == "" and defaultItem.swatchColor[1] == dr and defaultItem.swatchColor[4] == 1
    and #lastDropdown.values == 9, "the color list starts with the default color")
writes = historyWrites
lastDropdown.onSelect("4db8ff")
local br, bg, bb = P.RGB("4db8ff")
assert(Page.SpellField("b1", "stackColor") == "4db8ff" and historyWrites == writes + 1
    and stackColor.swatch.fill.color[1] == br and stackColor.swatch.fill.color[3] == bb
    and stackColor.swatch.edge.color[1] == 0.2, "stack color pick failed")
Fire(stackColor.swatch, "OnClick")
assert(lastDropdown.current == "4db8ff", "the color list must mark the current color")
lastDropdown.onSelect("")
assert(Page.SpellField("b1", "stackColor") == nil, "picking the default color must clear the field")
-- Without Menu2's list, the swatch steps through the colors.
local openDropdown = W.OpenDropdown
W.OpenDropdown = nil
Fire(stackColor.swatch, "OnClick")
W.OpenDropdown = openDropdown
assert(Page.SpellField("b1", "stackColor") == "ffd200", "the swatch did not step to the next color")
-- A color alone customises the row; its reset clears both fields as one step.
Fire(stackColor.minus, "OnClick"); Fire(stackColor.minus, "OnClick"); Fire(stackColor.minus, "OnClick")
assert(Page.SpellField("b1", "stackColorAt") == nil and stackColor.reset.shown and stackColor.label.textColor[1] == 0.2,
    "a stack color without a threshold is still a choice")
Fire(stackColor.plus, "OnClick")
writes = historyWrites
Fire(stackColor.reset, "OnClick")
assert(Page.SpellField("b1", "stackColorAt") == nil and Page.SpellField("b1", "stackColor") == nil
    and historyWrites == writes + 1 and not stackColor.reset.shown, "the stack row reset must clear both fields at once")
-- The buff and its stacks show only with "Show active buff duration":
-- otherwise the stack rows (Track on among them) stay editable but dimmed.
assert(stackGlow.alpha == 1 and stackColor.alpha == 1 and trackOn.alpha == 1, "stack rows dimmed while the buff shows")
Fire(pop.rows.showAura.off, "OnClick")
assert(stackGlow.alpha == 0.45 and stackColor.alpha == 0.45 and trackOn.alpha == 0.45 and pop.rows.glowStyle.alpha == 1,
    "stack rows must dim while the spell hides its buff")
Fire(stackGlow.tip, "OnEnter")
assert(tooltip.text == "Glow at stacks" and tooltip.line:find("Show active buff duration", 1, true),
    "a dimmed stack row must say why")
Fire(stackGlow.tip, "OnLeave")
Fire(trackOn.choice, "OnClick")
lastDropdown.onSelect(3)
assert(Page.SpellField("b1", "auraUnit") == 3 and trackOn.shown, "a dimmed Track on must stay editable")
Fire(pop.rows.showAura.reset, "OnClick")
assert(stackGlow.alpha == 1 and trackOn.alpha == 1, "stack rows must follow the spell's buff choice")
Config().ess_showAura = false
M.RequestRefresh()
assert(stackGlow.alpha == 0.45 and trackOn.alpha == 0.45, "stack rows must follow the bar's Show active buff duration")
Config().ess_showAura = true
M.RequestRefresh()
Fire(pop.reset, "OnClick")
assert(Page.SpellOverrides().e.b1 == nil and trackOn.choice.text == "Automatic" and not trackOn.reset.shown,
    "reset spell failed (Track on must go back to Automatic)")
Fire(pop.close, "OnClick")
-- Custom entries can be copied to the other specializations.
Click(grid.tiles[3], "LeftButton")
assert(pop.key == "i5512" and pop.copy.shown and not pop.rows.procGlow.shown and pop.rows.readyGlow.shown,
    "item entries show item options and the copy action")
-- Four header actions wrap onto a second line, and the rows move down.
assert(pop.copy.points[1][4] == 12 and pop.copy.points[1][5] == -80 and pop.scroll.points[1][5] == -(54 + 52 + 20),
    "the header actions must wrap")
assert(not pop.hasAura and not pop.rows.stackGlow.shown and not pop.rows.stackColorAt.shown and not pop.rows.auraUnit.shown,
    "items have no stack options and no Track on")
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
-- Glow style and color style buff glows too; stack options are always
-- live for buffs; a buff's own icon shows only while it is missing.
assert(pop.rows.glowStyle.shown and pop.rows.glowColor.shown, "buff entries must offer the glow style and color")
assert(pop.rows.stackGlow.shown and pop.rows.stackColorAt.shown and pop.rows.stackGlow.alpha == 1
    and pop.rows.stackColorAt.alpha == 1, "buff entries must offer the stack options at full strength")
local buffTrack = pop.rows.auraUnit
assert(buffTrack.shown and buffTrack.alpha == 1 and buffTrack.label.text == "Track on" and buffTrack.choice.text == "Automatic",
    "buff entries must offer Track on at full strength, under the same label")
assert(buffTrack.points[1][5] == pop.rows.showMissing.points[1][5] - 26
    and pop.rows.stackGlow.points[1][5] == buffTrack.points[1][5] - 26,
    "buff stack rows follow the missing row, Track on first")
Fire(buffTrack.choice, "OnClick")
lastDropdown.onSelect(4)
assert(Page.SpellField("b10", "auraUnit") == 4 and buffTrack.choice.text == "Both", "buff Track on failed")
Fire(pop.rows.glowStyle.choice, "OnClick")
lastDropdown.onSelect(3)
assert(Page.SpellField("b10", "glowStyle") == 3 and pop.rows.glowStyle.choice.text == "Pulse", "buff glow style failed")
Fire(pop.rows.stackGlow.plus, "OnClick")
Fire(pop.rows.stackColorAt.plus, "OnClick")
assert(Page.SpellField("b10", "stackGlow") == 1 and Page.SpellField("b10", "stackColorAt") == 1, "buff stack options failed")
Fire(pop.reset, "OnClick")
assert(Page.SpellOverrides().e.b10 == nil and buffTrack.choice.text == "Automatic", "reset buff options failed")
assert(pop.rows.icon.shown and pop.rows.icon.label.text == "Icon when missing (Enter)", "buff icon row must say when it applies")
-- Buffs name their text rows for what they show.
assert(pop.rows.timeText.shown and pop.rows.timeText.label.text == "Seconds" and pop.rows.stackText.label.text == "Stacks"
    and pop.rows.textTop.label.text == "Text on top" and pop.rows.timeText.choice.text == "Bar: Show",
    "buff text rows")
-- What Automatic picked, when the runtime says it.
runtime.units.b10 = "target"
Page.ui.grid.valid = false
M.RequestRefresh()
assert(pop.shown and buffTrack.choice.text == "Automatic: target", "Track on must say what Automatic picked")
runtime.units.b10 = nil
Page.ui.grid.valid = false
M.RequestRefresh()
assert(buffTrack.choice.text == "Automatic", "Track on without the runtime's answer")
picker.set("ess")
assert(not pop.shown, "changing the bar closes the popover")
M.RequestRefresh()

------------------------------------------------------------------ preview editor
-- The drawn icons are the spell editor: hover, click, middle-click, drag and
-- the + tile, on every bar type. The page lays pooled buttons over what the
-- runtime drew and never hooks the drawing itself.
do
    local DOT = " \194\183 "
    local HINT = "Click a spell for its settings" .. DOT .. "drag to reorder or onto a bar above" .. DOT
        .. "middle-click removes" .. DOT .. "+ adds"
    local TIP = "Click: settings" .. DOT .. "Drag: reorder" .. DOT .. "Middle-click: remove"
    local listsBefore = Config().listsData
    local hits, drag, canvas = ui.hits, ui.drag, runtime.frame
    local function Idle()
        if drag.host.scripts.OnUpdate then return false end
        for _, hit in ipairs(hits) do if hit.scripts.OnUpdate then return false end end
        return true
    end
    assert(Keys("ess") == "b3,b1,i5512", "unexpected start: " .. Keys("ess"))
    assert(ui.hitCount == 3 and hits[1].key == "b3" and hits[2].key == "b1" and hits[3].key == "i5512",
        "preview icons must carry the drawn entries")
    for i = 1, 3 do
        assert(hits[i].points[1][1] == "ALL" and hits[i].points[1][2] == canvas.icons[i], "preview button " .. i .. " is not on its icon")
    end
    assert(hits[1].dimmed and hits[1].dim.shown and not hits[2].dim.shown, "unlearned entries must be dimmed in the preview")
    assert(ui.plus.shown and ui.plus.points[1][2] == canvas and ui.plus.points[1][3] == "RIGHT",
        "the + tile must sit at the end of the drawing")
    -- The last note takes the hint's place until it clears itself.
    assert(Page.note and ui.previewLine.text == Page.note, "the preview line must show the last note")
    Page.ClearNote()
    assert(ui.previewLine.text == HINT and not ui.previewUndo.shown and ui.previewUndo._msuf2SkipHistoryCheckpoint
        and PendingTasks() == 0, "the hint line under the preview")
    for _, icon in ipairs(canvas.icons) do
        assert(next(icon.scripts) == nil and next(icon.hooks) == nil, "the page hooked the runtime's drawing")
    end
    -- At rest nothing runs per frame, and a repaint reuses every frame.
    assert(Idle(), "preview buttons run per frame at rest")
    local frameCount, hitPoints, plusPoints = #frames, hits[1].points, ui.plus.points
    M.RequestRefresh()
    M.RequestRefresh()
    assert(#frames == frameCount, "a preview repaint created frames")
    assert(hits[1].points == hitPoints and ui.plus.points == plusPoints, "a repaint of the same drawing re-anchored its buttons")
    -- Nor does it rescale the stage, resize the canvas or move the chips.
    local writesSeen = 0
    local function Count(self, value) writesSeen = writesSeen + 1; self.scale, self.height = value, value end
    ui.stage.SetScale, ui.canvas.SetHeight, ui.strip.SetHeight = Count, Count, Count
    local chipPoints = ui.chips.ess.points
    M.RequestRefresh()
    ui.stage.SetScale, ui.canvas.SetHeight, ui.strip.SetHeight = nil, nil, nil
    assert(writesSeen == 0 and ui.chips.ess.points == chipPoints, "a repaint of the same preview wrote layout")

    -- Hover: outline and a short tooltip, allocation-free.
    Fire(hits[2], "OnEnter")
    assert(hits[2].hover.shown and hits[2].lines[1].shown and tooltip.shown and tooltip.owner == hits[2]
        and tooltip.text == "Fireball" and tooltip.line == TIP, "hover must outline the icon and name the spell")
    Fire(hits[2], "OnLeave")
    assert(not hits[2].hover.shown and not hits[2].lines[1].shown and not tooltip.shown, "leaving must clear the hover")
    Fire(hits[1], "OnEnter")
    assert(tooltip.text == "Arcane Blast" and tooltip.line == "Not learned right now.", "unlearned entries say so")
    Fire(hits[1], "OnLeave")
    local function Hover()
        Fire(hits[2], "OnEnter"); Fire(hits[2], "OnLeave")
        Fire(ui.plus, "OnEnter"); Fire(ui.plus, "OnLeave")
    end
    collectgarbage("collect")
    collectgarbage("stop")
    -- One pass first: a collection shrinks the Lua stack and the next call
    -- grows it again, which is not the hover's allocation.
    Hover()
    local before = collectgarbage("count")
    for _ = 1, 50 do Hover() end
    local grew = collectgarbage("count") - before
    collectgarbage("restart")
    assert(grew == 0, "hovering the preview allocated " .. grew .. " KB")

    -- Left or right click: the tile's popover, under the icon; again closes.
    local writes = historyWrites
    Click(hits[2], "LeftButton")
    assert(pop.shown and pop.key == "b1" and pop.anchor == hits[2] and pop.points[1][2] == hits[2]
        and pop.points[1][3] == "BOTTOMLEFT", "a click must open the spell's popover under its icon")
    assert(pop.hasAura and pop.rows.stackGlow.shown and pop.rows.auraUnit.shown and pop.rows.readyGlow.shown,
        "the preview opens the tile's popover rows")
    assert(hits[2].lines[1].shown and historyWrites == writes, "the open icon is outlined; opening writes nothing")
    Click(hits[2], "LeftButton")
    assert(not pop.shown and not hits[2].lines[1].shown, "clicking the icon again must close the popover")
    Click(hits[2], "RightButton")
    assert(pop.shown and pop.anchor == hits[2], "a right click opens the popover too")
    Fire(pop.rows.readyGlow.on, "OnClick")
    assert(Page.SpellField("b1", "readyGlow") == true and historyWrites == writes + 1 and pop.shown and pop.anchor == hits[2],
        "a popover edit is one history entry and keeps the popover on its icon")
    assert(grid:Tile("b1").edge.color[1] == 0.12, "the spell list must not light a tile for the preview's popover")
    -- The drawn icon marks the spell's own options, as its tile does, and
    -- its tooltip names them.
    assert(hits[2].mark.shown and not hits[1].mark.shown and not hits[2].ruleMark.shown, "the preview must mark own options")
    Fire(hits[2], "OnEnter")
    assert(tooltip.line == "Own options: Glow when ready", "the tooltip must name the spell's own options: " .. tostring(tooltip.line))
    Fire(hits[2], "OnLeave")
    Fire(pop.reset, "OnClick")
    assert(not hits[2].mark.shown, "the mark must go with the options")
    Click(hits[1], "LeftButton")
    assert(pop.shown and pop.key == "b3" and pop.anchor == hits[1] and hits[1].lines[1].shown and not hits[2].lines[1].shown,
        "an unlearned entry opens its popover, and only its icon is outlined")
    Fire(pop.close, "OnClick")
    assert(not pop.shown and not hits[1].lines[1].shown, "closing the popover clears the outline")
    -- An open popover follows its spell when the drawing changes under it.
    Click(hits[2], "LeftButton")
    assert(Page.RemoveEntry("ess", "b3"))
    assert(pop.shown and pop.key == "b1" and pop.anchor == hits[1] and pop.points[1][2] == hits[1]
        and hits[1].lines[1].shown and not hits[2].lines[1].shown, "the popover must follow its spell to its new icon")
    Config().listsData = listsBefore
    M.RequestRefresh()
    assert(pop.shown and pop.anchor == hits[2] and Keys("ess") == "b3,b1,i5512", "the popover must follow its spell back")
    Fire(pop.close, "OnClick")

    -- Middle-click removes, with the Undo line under the preview.
    writes = historyWrites
    Click(hits[2], "MiddleButton")
    assert(Keys("ess") == "b3,i5512" and historyWrites == writes + 1, "middle-click must remove the spell in one step")
    assert(Page.note == "Removed Fireball." and ui.previewLine.text == "Removed Fireball." and ui.previewUndo.shown
        and PendingTasks() == 1, "the preview must show the removal with its Undo")
    assert(ui.hitCount == 2 and hits[2].key == "i5512" and not hits[3].shown, "the preview must follow the removal")
    Click(ui.previewUndo, "LeftButton")
    assert(Keys("ess") == "b3,b1,i5512" and historyWrites == writes + 2 and PendingTasks() == 0 and not ui.previewUndo.shown
        and ui.previewLine.text == HINT, "Undo under the preview must bring the spell back")

    -- Drag: 3 px, an insert marker, before or after the hovered icon.
    for i = 1, 3 do hits[i].cx, hits[i].cy = 60 + 40 * i, 50 end
    cursorX, cursorY = 100, 50
    Fire(hits[1], "OnMouseDown", "LeftButton")
    assert(drag.host.scripts.OnUpdate and not drag.active, "a press must arm the drag driver")
    cursorX = 101
    Fire(drag.host, "OnUpdate", 0.01)
    assert(not drag.active and not Page.ghost.shown, "the drag started below 3 px")
    cursorX = 185
    hits[3].mouseOver = true
    Fire(drag.host, "OnUpdate", 0.01)
    assert(drag.active and Page.ghost.shown and hits[1].dim.shown and drag.dropHit == hits[3] and drag.dropAfter
        and drag.marker.shown and drag.marker.points[1][2] == hits[3] and drag.marker.points[1][3] == "RIGHT",
        "the right half of an icon must mark the place after it")
    writes = historyWrites
    Fire(hits[1], "OnMouseUp", "LeftButton")
    Fire(hits[1], "OnClick", "LeftButton")
    hits[3].mouseOver = false
    assert(Keys("ess") == "b1,i5512,b3" and historyWrites == writes + 1, "preview reorder failed: " .. Keys("ess"))
    assert(Idle() and not Page.ghost.shown and not drag.marker.shown and not pop.shown,
        "the drop must end the drag without opening the popover")
    cursorX = 180
    Fire(hits[3], "OnMouseDown", "LeftButton")
    cursorX = 95
    hits[1].mouseOver = true
    Fire(drag.host, "OnUpdate", 0.01)
    assert(drag.dropHit == hits[1] and not drag.dropAfter and drag.marker.points[1][3] == "LEFT",
        "the left half must mark the place before")
    Fire(hits[3], "OnMouseUp", "LeftButton")
    hits[1].mouseOver = false
    assert(Keys("ess") == "b3,b1,i5512", "dropping before the first icon failed: " .. Keys("ess"))
    cursorX = 100
    Fire(hits[1], "OnMouseDown", "LeftButton")
    cursorX = 240
    ui.plus.mouseOver = true
    Fire(drag.host, "OnUpdate", 0.01)
    assert(drag.dropHit == ui.plus and drag.marker.points[1][2] == ui.plus and drag.marker.points[1][3] == "LEFT",
        "the + tile takes a drop at the end")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    ui.plus.mouseOver = false
    assert(Keys("ess") == "b1,i5512,b3", "dropping on + must move the spell to the end: " .. Keys("ess"))
    -- Onto a bar chip: moved there; a cooldown on a buff bar is refused.
    cursorX = 100
    Fire(hits[1], "OnMouseDown", "LeftButton")
    cursorX = 200
    ui.chips.uti.mouseOver = true
    Fire(drag.host, "OnUpdate", 0.01)
    assert(drag.dropSlot == "uti" and ui.chips.uti.drop.shown and not drag.marker.shown, "a bar chip must take the drop")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    ui.chips.uti.mouseOver = false
    assert(Keys("ess") == "i5512,b3" and Keys("uti"):find("b1", 1, true) and not ui.chips.uti.drop.shown
        and Page.note == "Moved Fireball to Utility cooldowns.", "dropping on a bar chip must move the spell there")
    cursorX = 100
    Fire(hits[1], "OnMouseDown", "LeftButton")
    cursorX = 200
    ui.chips.buf.mouseOver = true
    Fire(drag.host, "OnUpdate", 0.01)
    Fire(hits[1], "OnMouseUp", "LeftButton")
    ui.chips.buf.mouseOver = false
    assert(Page.noteError and Page.note == "That bar shows buffs." and ui.previewLine.textColor[1] == 1
        and Keys("ess") == "i5512,b3", "a cooldown dropped on a buff bar must be refused, in red")

    -- Combat: no hover, no click, no drag; combat mid-drag ends it.
    local keysNow = Keys("ess")
    tooltip.shown = false
    combat = true
    Fire(hits[1], "OnMouseDown", "LeftButton")
    assert(Idle(), "a preview drag armed in combat")
    Fire(hits[1], "OnEnter")
    assert(not hits[1].hover.shown and not tooltip.shown, "no hover in combat")
    Click(hits[1], "LeftButton")
    Click(hits[1], "MiddleButton")
    Click(ui.plus, "LeftButton")
    assert(not pop.shown and not Page.picker.shown and Keys("ess") == keysNow, "combat must refuse preview clicks")
    combat = false
    cursorX = 100
    Fire(hits[1], "OnMouseDown", "LeftButton")
    cursorX = 150
    Fire(drag.host, "OnUpdate", 0.01)
    assert(drag.active and Page.ghost.shown, "preview drag did not start")
    combat = true
    Fire(drag.host, "OnUpdate", 0.01)
    combat = false
    assert(Idle() and not drag.active and not Page.ghost.shown, "combat must end a preview drag")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    assert(Keys("ess") == keysNow, "a drag ended by combat must not write")
    -- Hiding the preview (or the menu) ends a drag too.
    Fire(hits[1], "OnMouseDown", "LeftButton")
    Fire(drag.host, "OnHide")
    assert(Idle(), "hiding the preview left the drag driver running")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    Fire(hits[1], "OnMouseDown", "LeftButton")
    cursorX = 190
    Fire(drag.host, "OnUpdate", 0.01)
    ui.previewBody:Hide()
    assert(Idle() and not drag.active and not Page.ghost.shown and runtime.previewOn == false,
        "closing the page must end a preview drag")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    assert(Keys("ess") == keysNow, "a drag ended by closing the page must not write")
    ui.previewBody:Show()
    ctx.fixedPreview.record.onActivate()
    assert(Page.ui == ui and runtime.previewOn, "the page did not come back")

    -- An empty bar: dimmed samples and the + tile open the picker.
    picker.set("c1")
    M.RequestRefresh()
    assert(ui.hitCount == 3 and hits[1].key == false and hits[1].dimmed and hits[3].dim.shown,
        "an empty bar must show dimmed sample icons")
    Fire(hits[1], "OnEnter")
    assert(tooltip.text == "Sample icon", "samples say what they are")
    Fire(hits[1], "OnLeave")
    Fire(hits[1], "OnMouseDown", "LeftButton")
    assert(Idle(), "samples do not drag")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    Fire(hits[1], "OnClick", "LeftButton")
    local pick = Page.picker
    assert(pick.shown and pick.anchor == hits[1] and pick.title.text == "Add to Custom bar 1", "a sample must open the picker")
    Click(hits[1], "LeftButton")
    assert(not pick.shown, "clicking the sample again closes the picker")
    Click(ui.plus, "LeftButton")
    assert(pick.shown and pick.anchor == ui.plus, "the + tile must open the picker")
    Click(ui.plus, "LeftButton")
    assert(not pick.shown, "the + tile closes the picker again")

    -- A spell a bar rule hides in play carries the amber strip, and its
    -- tooltip names the rule.
    picker.set("ext")
    M.RequestRefresh()
    assert(Keys("ext") == "b30,b2" and hits[2].key == "b2" and hits[2].ruleMark.shown and not hits[1].ruleMark.shown,
        "the preview must mark spells a bar rule hides")
    Fire(hits[2], "OnEnter")
    assert(tooltip.line == "Hidden while ready (Hide icons that are ready).", "the hidden reason: " .. tostring(tooltip.line))
    Fire(hits[2], "OnLeave")

    -- Buff bars (rows) and buff icons get the same buttons.
    picker.set("bar")
    M.RequestRefresh()
    assert(ui.kind == 3 and hits[1].key == "b20" and hits[1].points[1][2] == canvas.rows[1] and ui.hitCount == 1,
        "buff bar rows must get the same buttons")
    Click(hits[1], "LeftButton")
    assert(pop.shown and pop.key == "b20" and pop.anchor == hits[1] and pop.rows.auraGlow.shown,
        "a buff bar row opens its buff popover")
    Fire(pop.close, "OnClick")
    picker.set("buf")
    M.RequestRefresh()
    assert(ui.kind == 2 and hits[1].key == "b10" and hits[2].key == "b11" and hits[1].points[1][2] == canvas.icons[1],
        "buff icons must get the same buttons")
    -- Drawn downwards: the drag follows the drawing's own flow.
    hits[1].cx, hits[1].cy, hits[2].cx, hits[2].cy = 100, 60, 100, 30
    cursorX, cursorY = 100, 60
    Fire(hits[1], "OnMouseDown", "LeftButton")
    cursorY = 25
    hits[2].mouseOver = true
    Fire(drag.host, "OnUpdate", 0.01)
    assert(drag.axis == "y" and drag.sign == -1 and drag.dropAfter and drag.marker.points[1][3] == "BOTTOM",
        "a downward drawing must mark below the icon")
    Fire(hits[1], "OnMouseUp", "LeftButton")
    hits[2].mouseOver = false
    assert(Keys("buf") == "b11,b10", "buff reorder failed: " .. Keys("buf"))
    Click(hits[1], "MiddleButton")
    assert(Keys("buf") == "b10" and Page.note == "Removed Ice Barrier.", "middle-click must remove buffs too")

    Page.ClearNote()
    Config().listsData = listsBefore
    picker.set("ess")
    M.RequestRefresh()
    assert(Keys("ess") == "b3,b1,i5512" and Idle() and not ui.previewUndo.shown, "preview editor state not restored")
end

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
local listsBeforeReuse = Config().listsData
local reused = Lists()
reused.specs[62] = reused.specs[62] or {}
reused.specs[62].c2 = { "s133" }
Config().listsData = CDM.Codec.EncodeLists(reused)
local listsReused = Config().listsData
assert(Config().c1_x == 0 and Config().c1_y == 0, "c1 must sit at the screen center for this check")
-- The list says which bar a new one starts over.
Page.OpenAddBar(ui.addChip)
local replacing = lastDropdown.values[1]
assert(replacing.value == 1 and replacing.text == "Cooldown bar (replaces Old 2)" and replacing.translate == false
    and replacing.tooltip:find("Old 2", 1, true) and lastDropdown.values[3].text == "Timer bar (replaces Old 2)",
    "reusing a slot must say which bar it starts over")
writes = historyWrites
assert(Page.AddBar(1) and Page.selected == "c2" and historyWrites == writes + 1, "reusing a bar slot failed")
assert(Config().c2_on and Config().c2_kind == 1 and Config().c2_name == "Cooldowns 2" and Config().c2_size == 36,
    "a reused bar kept its old settings")
assert(not (Lists().specs[62] and Lists().specs[62].c2), "a reused bar kept its old spells")
assert(Config().c2_x == 0 and Config().c2_y == -48, "a new bar landed on another bar")
assert(focused == PAGE .. "_cooldownManager_module", "a new bar must bring its name input into view")
-- Undo brings the old bar back, settings, name and spells, in one entry.
assert(Page.note == "Old 2 was reset for the new bar." and Page.undo, "reusing a slot must offer Undo")
Page.RunUndo()
assert(not Config().c2_on and Config().c2_name == "Old 2" and Config().c2_kind == 3 and Config().c2_size == 60
    and Config().c2_y == 0 and Config().listsData == listsReused and historyWrites == writes + 2,
    "Undo did not bring the reused bar back")
Config().listsData = listsBeforeReuse
Config().c2_size, Config().c2_kind = 36, 1
Config().c2_on = false
for i = 2, 6 do Config()["c" .. i .. "_name"] = "" end
Config().c2_y = 0
Page.ClearNote()

-- Bar actions, from a chip's right click or Frame Basics: show or hide,
-- rename, move, reset, delete, and the settings of another bar.
M.RequestRefresh()
local function BarMenu(owner, button)
    lastDropdown = nil
    Fire(owner, "OnClick", button)
    return assert(lastDropdown and lastDropdown.owner == owner and lastDropdown, "bar actions did not open")
end
local menu = BarMenu(ui.chips.c1, "RightButton")
local menuValues = {}
for i, item in ipairs(menu.values) do menuValues[i] = tostring(item.value) end
assert(Page.selected == "c2" and table.concat(menuValues, ",")
    == "hide,rename,move,reset,delete,copy,copy:ess,copy:uti,copy:def,copy:ext,copy:buf,copy:bar,copy:c2"
    and menu.values[6].header and menu.values[7].translate == false and menu.values[7].text == "Essential cooldowns"
    and not menu.values[3].disabled and menu.values[5].tooltip:find("undo", 1, true),
    "bar actions of a custom bar: " .. table.concat(menuValues, ","))
-- Copy: the look and behavior of another bar, never its name, type or place.
Config().buf_zoom, Config().buf_border, Config().buf_size = 20, 3, 30
local c1Anchor, c1Name = Config().c1_anchor, Config().c1_name
writes = historyWrites
menu.onSelect("copy:buf")
assert(Config().c1_zoom == 20 and Config().c1_border == 3 and Config().c1_size == 30 and Config().c1_kind == 2
    and Config().c1_anchor == c1Anchor and Config().c1_name == c1Name and Config().c1_on and historyWrites == writes + 1,
    "copying bar settings failed")
assert(Page.note == "Buffs 1 now uses the settings of Buffs." and Page.undo, "the copy must offer Undo")
Page.RunUndo()
assert(Config().c1_zoom == 8 and Config().c1_border == 1 and Config().c1_size == 36 and historyWrites == writes + 2,
    "Undo did not take the copied settings back")
Config().buf_zoom, Config().buf_border = 8, 1
-- Reset, and an Undo refused once the bar changed since.
Config().c1_size = 50
BarMenu(ui.chips.c1, "RightButton").onSelect("reset")
assert(Config().c1_size == 36 and Config().c1_name == c1Name and Config().c1_on and Page.undo, "reset this bar failed")
Config().c1_size = 44
Page.RunUndo()
assert(Config().c1_size == 44 and Page.noteError and Page.note:find("changed since", 1, true), "a stale Undo must be refused")
Config().c1_size = 36
-- Hide and show: a built-in bar that is off stays in the strip, dimmed.
BarMenu(ui.chips.uti, "RightButton").onSelect("hide")
M.RequestRefresh()
assert(not Config().uti_on and ui.chips.uti.shown and ui.chips.uti.alpha == 0.5, "a hidden built-in bar left the strip")
local utiPoints = ui.chips.buf.points
M.RequestRefresh()
assert(ui.chips.buf.points == utiPoints, "a repaint of the same strip moved its chips")
menu = BarMenu(ui.chips.uti, "RightButton")
assert(menu.values[1].value == "show" and menu.values[2].value == "move" and menu.values[2].disabled
    and menu.values[2].tooltip == "Show this bar first." and menu.values[4].value == "copy",
    "a hidden bar offers Show and cannot move")
menu.onSelect("show")
assert(Config().uti_on, "showing a bar failed")
-- Rename selects the bar and brings its name input into view.
focused = nil
BarMenu(ui.chips.c1, "RightButton").onSelect("rename")
assert(Page.selected == "c1" and focused == PAGE .. "_cooldownManager_module", "rename did not open the bar's name")
-- Delete, from Frame Basics: the slot is free again, the page moves on, Undo.
local actionsButton = registered["menu2." .. PAGE .. ".cooldownManager.editor.actions"]
local reusedLists = Lists()
reusedLists.specs[62].c1 = { "s133" }
Config().listsData = CDM.Codec.EncodeLists(reusedLists)
local listsWithC1 = Config().listsData
writes = historyWrites
BarMenu(actionsButton).onSelect("delete")
assert(not Config().c1_on and Config().c1_name == "" and Config().c1_kind == 1 and not Lists().specs[62].c1
    and Page.selected == "ess" and historyWrites == writes + 1 and Page.note == "Deleted Buffs 1.", "deleting a bar failed")
M.RequestRefresh()
assert(not ui.chips.c1.shown and Page.FreeCustom() == "c1", "a deleted bar must free its slot")
Page.RunUndo()
M.RequestRefresh()
assert(Config().c1_on and Config().c1_name == "Buffs 1" and Config().c1_kind == 2 and Config().listsData == listsWithC1
    and ui.chips.c1.shown, "Undo did not bring the deleted bar back")
Config().listsData = listsBeforeReuse
Page.ClearNote()
-- Reset page: every cooldown-manager setting and spell list in one history entry.
local configBefore = {}
for key, value in pairs(Config()) do configBefore[key] = value end
Config().listsData = listsWithC1
configBefore.listsData = listsWithC1
writes = historyWrites
local beforePageReset = historyProvider.capture()
assert(M.ResetPageToDefaults(PAGE), "cooldown-manager Reset page was unavailable")
assert(Config().listsData == "" and not Config().c1_on and historyWrites == writes + 1,
    "Reset page did not restore settings and spell lists as one history entry")
assert(historyProvider.restore(beforePageReset), "Reset page history could not restore the Suite state")
for key, value in pairs(configBefore) do
    assert(Config()[key] == value, "Undo of the module reset lost " .. key)
end
assert(historyWrites == writes + 1, "Reset page must write one history entry")
Config().listsData = listsBeforeReuse
Page.ClearNote()
Page.selected = "c1"
M.RequestRefresh()

-- Greyed controls say why; sections a bar does not use drop the bar's name
-- from their header; colors follow their own switch.
do
    local function Note(section)
        for _, child in ipairs(section.children or {}) do
            if child.kind == "FontString" and type(child.text) == "string"
                and (child.text:find("Turn the cooldown manager on", 1, true) or child.text:find("Not used by", 1, true)
                    or child.text:find("Greyed", 1, true) or child.text:find("own options", 1, true)) then
                return child.text
            end
        end
        return ""
    end
    local effects, text = ctx.sections[7], ctx.sections[6]
    Page.Select("bar")
    M.RequestRefresh()
    assert(effects._msuf2CollapsibleEntry.label.text == "Cooldown effects"
        and Note(effects) == "Not used by the Timer bar type. Pick another bar to edit these.",
        "an unused section must keep its plain title: " .. effects._msuf2CollapsibleEntry.label.text)
    assert(text._msuf2CollapsibleEntry.label.text == "Text: Buff bars", "the text switches apply to timer bars too")
    Config().enabled = false
    M.RequestRefresh()
    assert(Note(ctx.sections[2]) == "Turn the cooldown manager on in Frame Basics to edit these.", "module off: " .. Note(ctx.sections[2]))
    Config().enabled = true
    Page.Select("ess")
    M.RequestRefresh()
    assert(Note(effects) == "" and effects._msuf2CollapsibleEntry.label.text == "Cooldown effects: Essential cooldowns",
        "a used section names its bar")
    local glow
    for _, target in ipairs(effects.colorShortcut.options.getTargets()) do
        if target.sourceSettingKey == "msufsuite.cooldownManager.c1_glowColor" then glow = target end
    end
    Config().ess_glowTint = false
    assert(glow and not glow.isEnabled(), "Glow color must follow Tint glows")
    Config().ess_glowTint = true
    assert(glow.isEnabled(), "Glow color with Tint glows on")
    Config().ess_glowTint = false
    -- Custom timer bars keep the countdown switch the runtime reads for them.
    Config().c3_kind = 3
    assert(Page.Relevant("c3", "cdText") and Page.Relevant("c3", "stackText") and Page.Relevant("c3", "textTop")
        and Page.Relevant("c3", "cdSize"), "custom timer bars use the text switches")
    Config().c3_kind = 1
    -- A named custom bar that is off stays in the strip; an unused slot does not.
    Config().c3_name = "Spare"
    M.RequestRefresh()
    assert(ui.chips.c3.shown and ui.chips.c3.alpha == 0.5 and not ui.chips.c4.shown, "set-up bars stay listed, dimmed")
    Config().c3_name = ""
    M.RequestRefresh()
end
Page.selected = "c1"
M.RequestRefresh()
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
assert(focused == PAGE .. "_basics", "clicking the preview did not open Basics")
assert(handle.scripts.OnUpdate == nil, "a click left the drag driver running")
Config().ess_anchor = 1
local x, y = Config().ess_x, Config().ess_y
cursorX, cursorY = 100, 100
Fire(handle, "OnMouseDown", "LeftButton")
assert(handle.scripts.OnUpdate, "the drawing must follow the cursor while the bar is dragged")
cursorX, cursorY = 130, 90
Fire(handle, "OnUpdate", 0.01)
local point = runtime.frame.points[1]
-- The drawing rests left of center by half the + tile beside it.
local baseX = handle.baseX
assert(type(baseX) == "number" and baseX < 0, "the drawing and its + tile are not centered together")
assert(point[1] == "CENTER" and point[4] == baseX + 30 and point[5] == -10, "the drawing did not follow the cursor")
Fire(handle, "OnMouseUp", "LeftButton")
assert(Config().ess_x == x + 30 and Config().ess_y == y - 10, "dragging the preview did not move the bar")
point = runtime.frame.points[1]
assert(handle.scripts.OnUpdate == nil and point[4] == baseX and point[5] == 0, "the drop left the drag running or the drawing off center")
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
assert(handle.dragging and runtime.frame.points[1][4] == handle.baseX + 50, "preview drag did not start")
combat = true
Fire(handle, "OnUpdate", 0.01)
assert(handle.scripts.OnUpdate == nil and not handle.dragging and runtime.frame.points[1][4] == handle.baseX,
    "combat must end a preview drag and center the drawing")
Fire(handle, "OnMouseDown", "LeftButton")
assert(handle.scripts.OnUpdate == nil, "preview drag armed in combat")
Fire(watcher, "OnEvent", "PLAYER_REGEN_DISABLED")
assert(not pop.shown and not watcher.events.PLAYER_REGEN_DISABLED, "combat did not close the popups")
assert(not Page.AddEntry("ess", "b5", 1) and not Page.RemoveEntry("ess", "b1") and not Page.MoveEntry("b1", "uti"),
    "list edits must be refused in combat")
assert(not Page.SetSpellField("b1", "readyGlow", true) and not Page.TogglePicker(grid.plus) and not Page.AddBar(1),
    "combat must refuse spell options, the picker and new bars")
assert(not Page.SetSpellField("b1", "stackGlow", 3) and not Page.ClearSpellFields("b1", { "stackColorAt", "stackColor" })
    and not Page.SetSpellField("b1", "auraUnit", 3)
    and not Page.OpenSoundPicker(handle, "", function() end) and not sounds.shown,
    "combat must refuse stack options and the sound picker")
Click(grid.tiles[1], "MiddleButton")
Fire(grid.tiles[1], "OnMouseDown", "LeftButton")
assert(host.scripts.OnUpdate == nil, "drag armed in combat")
lastDropdown = nil
Fire(ui.chips.ess, "OnClick", "RightButton")
assert(lastDropdown == nil and not Page.OpenBarMenu(ui.chips.ess, "ess") and not Page.OpenAddBar(ui.addChip)
    and not Page.CopyBarSettings("uti", "ess") and not Page.ResetBar("ess") and not Page.DeleteBar("c1")
    and not Page.ResetModule() and not Page.CopyListToSpecs("ess") and not Page.FocusName(),
    "combat must refuse bar actions, resets and copies")
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

------------------------------------------------------------------ runtime canvas
-- The real Preview.lua publishes what the page lays its buttons on: items
-- drawn (capped), their regions, entry keys and dim flags (unlearned or
-- sample), for icons and buff bar rows alike.
do
    local C = { EMPTY = {}, plans = {}, state = {}, entries = {}, spells = { e = {} }, views = {} }
    C.Catalog = { order = {}, records = {}, RecordTexture = function() end }
    local lists = { ess = { "s1", "s2", "s3" }, bar = { "a1" }, c1 = {} }
    C.Resolve = {
        Keys = function(slot, out)
            for i = #out, 1, -1 do out[i] = nil end
            for i, key in ipairs(lists[slot] or {}) do out[i] = key end
            return out
        end,
        Describe = function(key, d) d.texture, d.name, d.known = 500, key, key ~= "s2"; return d end,
    }
    C.Icons = {
        CreateStandalone = function(parent) return Widget("Icon", parent) end,
        StyleIcon = function(icon, view) icon.styleGen, icon.styleView = view.styleGen, view end,
        SetTexture = function(icon, texture) icon.texture = texture end,
    }
    C.Layout = {
        Offsets = function(view, n, out)
            local count = view.maxIcons and math.min(n, view.maxIcons) or n
            for i = 1, count do out[2 * i - 1], out[2 * i] = (i - 1) * 40, 0 end
            return count * 40, 36, count
        end,
        Metrics = function() return 200, 20 end,
    }
    C.views.ess = { kind = 1, styleGen = 1, maxIcons = 2 }
    C.views.bar = { kind = 3, styleGen = 1 }
    C.views.c1 = { kind = 1, styleGen = 1 }
    local suite = setmetatable({
        CreateFrame = function(kind, _, parent) return Widget(kind, parent) end,
        CreateTexture = function(parent) return Widget("Texture", parent) end,
        CreateFontString = function(parent) return Widget("FontString", parent) end,
    }, { __index = function() return Noop end })
    local chunk = assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Preview.lua"))
    chunk("MSUF_Suite_CooldownManager", { NS = { IsCombatLocked = function() return false end }, Suite = suite, CDM = C })
    local stage = Widget("Frame")
    local holder = assert(C.Preview.Render(stage, "ess", 400, 100), "canvas missing")
    assert(holder.count == 2 and holder.kind == 1 and holder.items == holder.icons and holder.items[2].shown
        and holder.keys[1] == "s1" and holder.keys[2] == "s2" and holder.keys[3] == "s3"
        and holder.dim[1] == false and holder.dim[2] == true, "the canvas must publish its items, keys and dim flags")
    assert(C.Preview.Render(stage, "bar", 400, 100) == holder and holder.kind == 3 and holder.items == holder.rows
        and holder.count == 1 and holder.keys[1] == "a1" and holder.keys[2] == nil and holder.dim[2] == nil,
        "buff bars publish their rows, and stale keys are cleared")
    C.Preview.Render(stage, "c1", 400, 100)
    assert(holder.count == 3 and holder.items == holder.icons and holder.keys[1] == false and holder.keys[3] == false
        and holder.dim[1] and holder.dim[3], "an empty bar publishes its sample icons as dimmed placeholders")
    C.Preview.Release(stage)
end
for key in pairs(_G) do
    if not globalsBefore[key] then error("options page created global " .. tostring(key)) end
end
-- Each page file keeps real headroom below Lua 5.1's 200 locals per chunk.
for _, file in ipairs({ "CooldownManagerData", "CooldownManagerWidgets", "CooldownManagerPopover",
    "CooldownManagerPreview", "CooldownManager" }) do
    local handle = assert(io.open(root .. "/MSUF_Suite_Options/Pages/" .. file .. ".lua", "rb"))
    local names = 0
    for line in handle:read("*a"):gmatch("[^\r\n]+") do
        local list = line:match("^local function ([%w_]+)") or line:match("^local ([%w_, ]+)=") or line:match("^local ([%w_]+)%s*$")
        if list then names = names + select(2, list:gsub("[%w_]+", "")) end
    end
    handle:close()
    assert(names <= 140, file .. ".lua declares " .. names .. " top-level locals")
end
print("Suite cooldown manager options: registration, template coverage, selected-bar keys, name commits, attach targets and loops, Frame Basics with the module rules and the bar choice, Basics, Text rules, exactly-once coverage, tile memo, list edits with Undo, picker, popover (text rows, row help, header actions), preview editor (hover, click, middle-click, drag, +, samples, buff bars, marks, write memo), stack options, Track on, buff glow styles, Blizzard sounds, bar reuse with Undo, bar actions (copy, reset, hide, rename, delete), page reset with history, greyed reasons, preview drag, simulation, layouts, combat refusal, teardown and the runtime canvas contract passed")
