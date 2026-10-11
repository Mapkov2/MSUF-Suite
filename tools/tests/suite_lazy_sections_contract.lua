-- Lazy accordion adoption (MSUF Menu2 b:LazyCollapsibleSection). A host
-- with the method builds a closed section's controls on first open; the
-- Suite keeps the header parts (actions, summary, label refreshers) in the
-- shell and its post-build work in onBuilt. Hosts without the method keep
-- the eager build in its original order. The fake host below follows the
-- Classic implementation (MSUF_Menu2_Widgets_PageBuilder.lua
-- InstallLazySection): shell through self:CollapsibleSection, an immediate
-- build for open sections unless deferWhileHidden finds the owning panel
-- hidden, otherwise entry._msuf2EnsureContent, which the combat lock refuses.
local root = assert(arg[1], "repository root required")
local function Check(condition, message)
    if not condition then error("suite_lazy_sections_contract: " .. message, 2) end
end

local Noop = function() end
local Methods, frameCalls = {}, 0
local function Frame(parent)
    frameCalls = frameCalls + 1
    local frame = { shown = true, parent = parent, height = 0 }
    return setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return Methods[key] or Noop end
    end })
end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetShown(shown) self.shown = shown and true or false end
function Methods:IsShown() return self.shown end
function Methods:SetHeight(height) self.height = height end
function Methods:GetHeight() return self.height end
function Methods:GetStringHeight() return 14 end
function Methods:GetParent() return self.parent end
CreateFrame = function(_, _, parent) return Frame(parent) end

local log, combat, combatLocked = {}, false, false
local function Log(text) log[#log + 1] = text end
local function Clear() for i = #log, 1, -1 do log[i] = nil end end
local function Count(text)
    local n = 0
    for _, item in ipairs(log) do if item == text then n = n + 1 end end
    return n
end

------------------------------------------------------------------ fake host
local lazyHost, rowAllocations = true, 0
local function Builder(ctx)
    local b = { ctx = ctx, width = 720, parent = ctx.wrapper or Frame(), collapsibles = {}, layoutEntries = {} }
    function b:Section(title, height)
        local section = Frame(self.parent)
        section.title, section._msuf2Width = Frame(section), self.width
        section:SetHeight(height)
        return section
    end
    function b:CollapsibleSection(id, title, _, defaultOpen)
        local saved = ctx.saved and ctx.saved[id]
        local body = Frame(self.parent)
        local entry = { open = (saved == nil) and defaultOpen == true or saved == true, builder = self, body = body,
            header = Frame(), label = Frame(), sectionId = id }
        body.sectionId, body.title, body._msuf2CollapsibleEntry = id, title, entry
        self.collapsibles[#self.collapsibles + 1] = entry
        Log("section " .. id)
        return body
    end
    function b:FinishSection(body) body.finished = (body.finished or 0) + 1 end
    if lazyHost then
        function b:LazyCollapsibleSection(id, title, height, defaultOpen, build, opts)
            opts = opts or {}
            Log("lazy " .. id)
            local body = self:CollapsibleSection(id, title, height, defaultOpen)
            local entry = body._msuf2CollapsibleEntry
            entry.lazyOpts = opts
            if opts.shell then opts.shell(body, entry) end
            local function Build()
                if entry.built then return true end
                if combatLocked then return false end
                entry.built = true
                build(body, entry)
                if opts.onBuilt then opts.onBuilt(body) end
                return true
            end
            local parent = entry.builder.parent
            local hidden = opts.deferWhileHidden and parent and not parent:IsShown()
            if opts.eager or (entry.open and not hidden) then Build() else entry._msuf2EnsureContent = Build end
            return body
        end
    end
    return b
end

------------------------------------------------------------------ namespace
-- Suite.HostBridge: an MSUF host without the interrupt-ready engine.
local P = { S = {}, Suite = { RGB = function() return 1, 1, 1 end, HostBridge = { KickReady = function() return nil end } },
    SearchPreparers = {}, ChoiceGates = {} }
P.Tr = function(text) return text end
P.M = {
    TrackRefresh = function(ctx, fn) ctx.refreshers[#ctx.refreshers + 1] = fn end,
    AddTooltip = Noop, RegisterControlMetadata = function() Log("metadata") end,
    BindTextInputAt = function() return Frame() end,
}
P.W = {
    PageBuilder = Builder,
    SettingsRows = function(_, parent, spec)
        Log("rows")
        rowAllocations = rowAllocations + #spec.rows
        local controls = {}
        for _, row in ipairs(spec.rows) do controls[row.id] = Frame(parent) end
        P.lastRows = spec.rows
        return { controls = controls, bottomY = spec.y - 40 * #spec.rows }
    end,
    SetControlDisabledReason = Noop, SetControlEnabled = Noop,
    SetCollapsibleSummary = function(body) body.summaries = (body.summaries or 0) + 1 end,
    AttachContextColorShortcut = function() Log("colors"); return {} end,
    EnsureSectionContent = function(section)
        Log("ensure")
        local entry = section._msuf2CollapsibleEntry or section
        if entry._msuf2EnsureContent then return entry._msuf2EnsureContent() end
        return true
    end,
    SegmentTabs = function(_, body, spec)
        Log("tabs")
        local function Choose(tab)
            Log("select " .. tab)
            spec.set(tab)
            spec.afterRefresh(tab)
        end
        return Frame(body), function() spec.afterRefresh(spec.get() or spec.defaultTab) end, nil, Choose
    end,
}
P.T = { Button = function(parent) return Frame(parent) end, colors = {} }
P.Combat = function() return combat end
P.Get = function() return 1 end
P.Set = Noop
P.RuleEnabled = function() return true end
P.Meta = function(pageKey, id, key, _, sectionId) return { controlId = pageKey .. "." .. id .. "." .. key, sectionId = sectionId } end
P.Description = function(parent) Log("description"); return Frame(parent) end
-- The "..." takes its header place from the summary already there
-- (SectionActions.lua SectionActionButton): record what it found.
P.AttachSectionReset = function(_, body, _, reset)
    Log("reset")
    body.resets, body.reset, body.summariesAtReset = (body.resets or 0) + 1, reset, body.summaries or 0
end
P.FinishBody = function(b, body, y)
    Log("finish")
    body._msuf2CursorY = y
    b:FinishSection(body)
end
P.SetButtonText, P.Help = Noop, function(summary, details) return { summary = summary, details = details } end
local RULES = {
    { key = "size", label = "Size", default = 1, min = 0, max = 2 },
    { key = "shown", label = "Shown", default = true },
    { key = "tint", label = "Tint", default = "ffffff", color = true },
}
P.catalog = { demo = { rules = {}, summary = "size shown" } }
for _, rule in ipairs(RULES) do P.catalog.demo.rules[rule.key] = rule end
-- An older Menu2 (no host API v2): the Suite's own field writes.
local bridge = { HostBridge = {} }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", bridge)
P.HM = bridge.HostBridge.Menu2(P.M)
-- Menu/Bridge.lua's helper over the adapter.
function P.HideControlTitle(widget)
    local title = P.HM.GetControlTitle(widget)
    if title then title:Hide() end
end
local function Load(file) assert(loadfile(root .. "/MSUF_Suite_Options/" .. file))("MSUF_Suite_Options", P) end
Load("Menu/Controls.lua")
Load("Menu/Colors.lua")
local function Ctx(saved)
    return { refreshers = {}, wrapper = Frame(), key = "suite_demo", saved = saved }
end
local function Section(ctx, b, sectionId, opts)
    local built
    opts.onBuilt = function(body, entries) Log("onBuilt"); built = { body = body, entries = entries } end
    local body, entries = P.RuleSection(ctx, b, opts.pageKey or "suite_demo", "demo", sectionId, sectionId, RULES, opts)
    return body, entries, function() return built end
end

------------------------------------------------------------------ old hosts
lazyHost = false
do
    local ctx = Ctx()
    Clear()
    local body, entries, built = Section(ctx, Builder(ctx), "old", { help = "Help", onEnsureVisible = Noop })
    Check(table.concat(log, ",") == "section old,description,rows,colors,reset,finish,onBuilt",
        "an old host lost the eager order: " .. table.concat(log, ","))
    Check(entries and #entries == 2 and built().entries == entries and body.summaries == 1,
        "an old host must return its entries, hand them to onBuilt and attach one summary")
    Check(body._msuf2CollapsibleEntry._msuf2EnsureVisible == Noop, "an old host lost onEnsureVisible")
end
Check(P.TabLazySection(Builder(Ctx()), function() return true end) == nil,
    "a facade must not advertise lazy sections its host does not have")

------------------------------------------------------------------ lazy host
lazyHost = true
do
    local ctx = Ctx()
    local b = Builder(ctx)
    Clear()
    local body, entries, built = Section(ctx, b, "closed", { help = "Help", onEnsureVisible = Noop })
    local entry = body._msuf2CollapsibleEntry
    Check(table.concat(log, ",") == "lazy closed,section closed,reset", "a closed section built more than its header: "
        .. table.concat(log, ","))
    Check(entries == nil and built() == nil and body.summaries == 1 and entry._msuf2EnsureVisible == Noop,
        "a closed section needs its summary and focus hook, but no controls or onBuilt yet")
    Check(body.summariesAtReset == 1, "a lazy shell attached \"...\" before its summary: the button moves left")
    local refreshers = #ctx.refreshers
    combat = true
    P.EnsureSectionContent(body)
    Check(Count("ensure") == 0 and not entry.built, "the Suite asked for a section build in combat")
    combat, combatLocked = false, true
    P.EnsureSectionContent(body)
    Check(not entry.built, "the host combat lock must keep the section armed")
    combatLocked = false
    Clear()
    P.EnsureSectionContent(body)
    Check(table.concat(log, ",") == "ensure,description,rows,colors,finish,onBuilt",
        "the deferred build lost its order: " .. table.concat(log, ","))
    Check(built() and #built().entries == 2 and body.summaries == 1 and #ctx.refreshers > refreshers,
        "the deferred build must hand over its entries without a second summary")
    Clear()
    P.EnsureSectionContent(body)
    Check(Count("rows") == 0, "a second ensure rebuilt the section")

    Clear()
    local openBody, openEntries, openBuilt = Section(ctx, b, "open", { open = true })
    Check(openEntries and #openEntries == 2 and openBuilt().entries == openEntries and Count("rows") == 1,
        "an open section must build at once and return its entries")
    Check(Count("lazy open") == 1 and openBody.summaries == 1, "an open section goes through the lazy host once")

    Clear()
    local colorsBody, colorsEntries = Section(ctx, b, "colors_demo", { pageKey = "colors" })
    Check(Count("lazy colors_demo") == 1 and colorsEntries == nil and Count("rows") == 0 and colorsBody.resets == 1,
        "closed Colors section allocated controls before opening")
    P.EnsureSectionContent(colorsBody)
    Check(Count("rows") == 1 and #P.lastRows == 3, "opening Colors lost its rows")
    P.EnsureSectionContent(colorsBody)
    Check(Count("rows") == 1, "reopening Colors allocated its rows again")
end

------------------------------------------------------------------ Colors cold/warm budgets
local function Instructions(callback)
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 100)
    callback()
    debug.sethook()
    return ticks * 100
end
do
    local oldCatalog, oldOrder, oldSkin, oldProvider = P.catalog, P.order, P.Suite.Skin, _G.MapkoSkin
    local loads = 0
    local function Catalog(count)
        local controls, rules = {}, {}
        for i = 1, count do
            local rule = { key = "color" .. i, label = "Color " .. i, default = "ffffff", color = true }
            controls[i], rules[rule.key] = rule, rule
        end
        return { title = "Palette", controls = controls, rules = rules }
    end
    P.catalog = { minimap = Catalog(2), actionbars = Catalog(96), damageMeter = Catalog(96) }
    P.order = { "minimap", "actionbars", "damageMeter" }
    P.ForgetAvailability = Noop
    _G.MapkoSkin = nil
    P.Suite.Skin = { EnsureEngine = function()
        loads = loads + 1
        local order = {}
        for i = 1, 64 do order[i] = { "tint" .. i, "Tint " .. i } end
        _G.MapkoSkin = { addonName = "MSUF_Suite_Skin", ColorOrder = order,
            SourceText = function(text) return text end,
            Theme = { GetColorTable = function() return { 0.1, 0.2, 0.3, 0.4 } end,
                SetColor = Noop, ResetColors = Noop } }
    end }
    local ctx, before = Ctx(), rowAllocations
    local b = Builder(ctx)
    local beforeFrames = frameCalls
    local coldInstructions = Instructions(function() P.BuildColorsCategory(ctx, b) end)
    local coldFrames = frameCalls - beforeFrames
    Check(rowAllocations - before == 2 and loads == 0,
        "cold Colors built closed palettes or loaded the skin engine")
    local sections = {}
    for _, entry in ipairs(b.collapsibles) do sections[entry.sectionId] = entry.body end
    for i = 1, 5 do for _, refresh in ipairs(ctx.refreshers) do refresh() end end
    Check(rowAllocations - before == 2 and loads == 0, "Colors refresh allocated closed palettes")
    P.EnsureSectionContent(sections.colors_suite_damageMeter)
    Check(rowAllocations - before == 98 and #P.lastRows == 96, "opening a palette lost its declared colors")
    P.EnsureSectionContent(sections.colors_suite_damageMeter)
    Check(rowAllocations - before == 98, "warm palette allocated rows again")
    combat = true
    P.EnsureSectionContent(sections.colors_suite_skin)
    Check(loads == 0, "Colors loaded skin in combat")
    combat = false
    P.EnsureSectionContent(sections.colors_suite_skin)
    Check(loads == 1 and rowAllocations - before == 162 and #P.lastRows == 64,
        "opening skin did not materialize its complete palette once")
    Check(select(4, P.lastRows[1].get()) == 0.4, "deferred skin color lost opacity")
    P.EnsureSectionContent(sections.colors_suite_skin)
    Check(loads == 1 and rowAllocations - before == 162, "warm skin rebuilt its palette")
    -- Legacy hosts still expose every color without the lazy API.
    lazyHost, _G.MapkoSkin = false, nil
    before = rowAllocations
    ctx = Ctx()
    beforeFrames = frameCalls
    local legacyInstructions = Instructions(function() P.BuildColorsCategory(ctx, Builder(ctx)) end)
    local legacyFrames = frameCalls - beforeFrames
    Check(coldInstructions < legacyInstructions and coldFrames < legacyFrames,
        "cold Colors did not reduce VM work and native frame requests")
    Check(rowAllocations - before == 258 and loads == 2, "legacy Colors lost palette coverage")
    lazyHost = true
    P.catalog, P.order, P.Suite.Skin, _G.MapkoSkin = oldCatalog, oldOrder, oldSkin, oldProvider
    print(("Colors budget fixture: cold 2/258 rows, %d/%d VM instructions, %d/%d frame requests; warm 0 new rows")
        :format(coldInstructions, legacyInstructions, coldFrames, legacyFrames))
end

------------------------------------------------------------------ module card
-- Switch, title suffix, summary and "..." in the shell; status line,
-- description, actions and rules on first open. Old hosts keep the eager
-- order. opts.eager (CDM builds into its card), opts.reset, colorSections.
local texts = {}
P.Text = function(parent)
    Log("text")
    texts[#texts + 1] = Frame(parent)
    return texts[#texts]
end
P.Button = function() Log("button"); return Frame() end
P.Available, P.StatusText = function() return true end, function() return "Active" end
P.SetTranslatedText = function(fontString, text) fontString.text = text end
P.W.SectionSwitch = function(body) Log("switch"); return Frame(body) end
P.M.BindBoolWidget = Noop
P.catalog.demo.description = "Demo"
local function Card(ctx, b, opts)
    opts.buildBody = function(_, y) Log("buildBody"); return y end
    return P.ModuleCard(ctx, b, "suite_demo", "demo", { { "Act", Noop, key = "act" } }, opts)
end
lazyHost = false
do
    local ctx = Ctx()
    Clear()
    Card(ctx, Builder(ctx), { open = false, colorSections = { { title = "Extra", rules = RULES } } })
    Check(table.concat(log, ",") == "section suite_demo_demo_module,switch,text,description,button,reset,buildBody,finish,colors",
        "an old host lost the module card's eager order: " .. table.concat(log, ","))
end
lazyHost = true
do
    local ctx = Ctx()
    local b = Builder(ctx)
    Clear()
    local custom = function() return true end
    local body = Card(ctx, b, { open = false, rules = RULES, reset = custom })
    local entry = body._msuf2CollapsibleEntry
    Check(table.concat(log, ",") == "lazy suite_demo_demo_module,section suite_demo_demo_module,switch,reset",
        "a closed module card built more than its header: " .. table.concat(log, ","))
    Check(body.summaries == 1 and body.summariesAtReset == 1 and body.reset == custom,
        "a closed module card needs its summary before \"...\" and the page's own reset")
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    Check(entry.label.text == "Basics", "a closed module card lost its title refresher")
    local summaries = body.summaries
    Clear()
    P.EnsureSectionContent(body)
    Check(table.concat(log, ",") == "ensure,text,description,button,rows,colors,buildBody,finish",
        "the module card's deferred build lost its order: " .. table.concat(log, ","))
    Check(texts[#texts].text == "Active" and body.summaries == summaries, "a module card built late must show its status at once, without a second summary")
    Clear()
    Card(ctx, b, { open = false, eager = true })
    Check(Count("lazy suite_demo_demo_module") == 0 and Count("button") == 1,
        "an eager module card (CDM builds into it) must build at once")
end

------------------------------------------------------------------ skin tabs
-- The Micro Bar tabs: the declared rows return at once (header summary and
-- reset); panels and tabs build on first open.
do
    local specs = {
        { id = "one", label = "One", title = "One", help = "First", rows = { { id = "a", label = "A" } } },
        { id = "two", label = "Two", title = "Two", help = "Second", rows = { { id = "b", label = "B" }, { id = "c", label = "C" } } },
    }
    local ctx = Ctx({ suite_skin_micro = false })
    Clear()
    local body, rows = P.SkinTabbedSection(ctx, Builder(ctx), "suite_skin_micro", "Micro Bar", specs, {})
    Check(rows and #rows == 3 and rows[3].id == "c" and Count("tabs") == 0 and Count("rows") == 0,
        "a closed skin tab section must return its rows and build no tabs")
    P.EnsureSectionContent(body)
    Check(Count("tabs") == 1 and Count("rows") == 2 and body.finished == 1, "the skin tabs did not build on demand")
    lazyHost = false
    ctx = Ctx({ suite_skin_micro = false })
    Clear()
    P.SkinTabbedSection(ctx, Builder(ctx), "suite_skin_micro", "Micro Bar", specs, {})
    Check(Count("tabs") == 1, "an old host builds the skin tabs at once")
    lazyHost = true
end

------------------------------------------------------------------ facades
-- HUD: every feature panel but the selected one is hidden.
Load("Pages/HUDWorkspace.lua")
do
    local ctx = Ctx()
    local facade = P.HUDMenu.Builder(ctx)
    Clear()
    local shown = Section(ctx, facade, "suite_hud_objectives_content", { open = true })
    local hidden, _, hiddenBuilt = Section(ctx, facade, "suite_hud_announcements_layout", { open = true })
    local shownEntry, hiddenEntry = shown._msuf2CollapsibleEntry, hidden._msuf2CollapsibleEntry
    Check(shownEntry.lazyOpts.deferWhileHidden and hiddenEntry.lazyOpts.deferWhileHidden
        and hiddenEntry.lazyOpts.shell, "the HUD facade must pass deferWhileHidden and keep the shell")
    Check(shownEntry.built and not hiddenEntry.built and hiddenBuilt() == nil and hidden.resets == 1,
        "an open HUD section on a hidden feature waits for its first show")
    Check(hiddenEntry.builder ~= shownEntry.builder and hidden._msufSuiteHUDReveal,
        "the lazy shell must still route through the facade to the feature builder")
    P.EnsureSectionContent(hidden)
    Check(hiddenEntry.built and hiddenBuilt(), "the hidden HUD section did not build on demand")
end
-- Action bars: grouped sections sit in tabs; others stay in the page.
Load("Pages/ActionBarsWorkspace.lua")
P.RegisterWorkspaceSearch = function() Log("workspace search") end
P.RegisterSummary("actionbars", "size shown")
do
    local ctx = Ctx()
    local facade = P.ActionBarMenu.Builder(ctx)
    Clear()
    local text = P.ActionBarMenu.Rules(ctx, facade, "suite_actionbars_bar_text", "Text", RULES, {})
    local look, lookEntries = P.ActionBarMenu.Rules(ctx, facade, "suite_actionbars_look", "Look", RULES, {})
    local free = P.ActionBarMenu.Rules(ctx, facade, "suite_actionbars_custom", "Custom", RULES, { open = true })
    local textEntry, lookEntry = text._msuf2CollapsibleEntry, look._msuf2CollapsibleEntry
    Check(textEntry.open and not textEntry.built and text.resets == 1 and text.summaries == 1
        and text._msufSuiteActionBarSectionId == "suite_actionbars_bar_text",
        "an open section on a hidden action bar tab needs its header only")
    Check(lookEntry.built and lookEntries and Count("workspace search") > 0,
        "the selected tab's first section must build at once with its search reveal")
    Check(free._msuf2CollapsibleEntry.lazyOpts.deferWhileHidden == false and free._msuf2CollapsibleEntry.built,
        "a section outside the tabs must not wait for a tab")
    Clear()
    P.EnsureSectionContent(text)
    Check(textEntry.built and Count("rows") == 1 and Count("workspace search") == 2,
        "the action bar section did not build on demand with its search reveal")
end

------------------------------------------------------------------ pages
-- Nameplates: the enemy section opens by default; saved closed it is lazy,
-- and preview handles build it before they select a tab.
local page
P.RegisterPage = function(spec) page = spec end
P.SectionRules = function(_, section)
    if section == "enemyColors" then return {} end
    return { { key = section .. "Size", label = "Size", sectionTitle = section, section = section, default = 1, min = 0, max = 2 } }
end
P.ModuleCard, P.BuildNameplatesPreview, P.BuildNameplatesAuraColors = Noop, Noop, Noop
P.catalog.nameplates = { rules = {} }
Load("Pages/Nameplates.lua")
do
    local ctx = Ctx({ suite_nameplates_enemy = false })
    Clear()
    page.build(ctx)
    Check(Count("tabs") == 0 and Count("lazy suite_nameplates_enemy") == 1, "a closed enemy section built its tabs")
    combat = true
    local body = P.SelectNameplatesEnemyTab("elements")
    Check(body and body.sectionId == "suite_nameplates_enemy" and Count("tabs") == 0,
        "the enemy tab selector must return the section and build nothing in combat")
    combat = false
    Check(P.SelectNameplatesEnemyTab("elements") == body and Count("tabs") == 1 and Count("select elements") == 1,
        "the enemy tab selector must build the section, then select the tab")
    lazyHost = false
    Clear()
    page.build(Ctx())
    Check(Count("tabs") == 1 and P.SelectNameplatesEnemyTab("appearance") and Count("select appearance") == 1,
        "an old host builds the enemy tabs at once")
end

print("Suite lazy sections: shell/content split, summary before \"...\", onBuilt, lazy Colors budgets, combat refusal, module cards, skin tabs, facades and page selectors passed")
