-- Package 2: actual page builders, catalog/codec, list edits and Undo lifecycle.
-- Reuse the options fixture up to its first page build, with fresh state per case.
local root, selected = assert(arg[1]), arg[2]
local file = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_options_contract.lua", "rb"))
local source = file:read("*a"); file:close()
source = source:sub(1, assert(source:find("local ctx = { key = PAGE", 1, true)) - 1)
local boot = assert(loadstring(source .. [[
return { P = P, M = M, W = W, Page = Page, CDM = CDM, Config = Config, Fire = Fire, frames = frames,
    Tasks = function() return tasks end, Dropdown = function() return lastDropdown end,
    SetSpec = function(id) runtime.specID = id end,
    Build = function(width)
        local ctx = { key = PAGE, width = width, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
        current = ctx
        spec.build(ctx)
        ctx.fixedPreview.record.onActivate()
        M.RequestRefresh()
        return ctx, Page.ui
    end }
]], "@cdm-page-options-world"))
local function World(width)
    local world = boot()
    world.W.SetControlDisabledReason = function(widget, reason) widget.disabledReason = reason end
    world.ctx, world.ui = world.Build(width or 720)
    return world, world.P, world.Page, world.Config(), world.CDM
end
local function Control(world, key)
    for _, widget in ipairs(world.ctx.widgets) do
        if widget.row and widget.row.id == key then return widget end
    end
    error("missing control " .. key)
end
local function Sentence(world, text)
    for _, frame in ipairs(world.frames) do if frame.text == text then return frame end end
end
local function Case(id, check)
    if not selected or selected == id then check(); print("PKG2 PASS " .. id) end
end

Case("U01", function()
    local w, P, Page, config = World()
    config.specPositions = true
    assert(Page.SelectSpec(266))
    assert(w.ui.profileCaption.text:find("active specialization (Arcane)", 1, true),
        "U01: foreign selection must name the active layout owner")
    Control(w, "c1_x").set(77)
    assert(config.ess_x == 77 and Page.Spec() == 266 and Page.PlayerSpec() == 62,
        "U01: geometry and spell-list scopes must remain distinct")
    config.specPositions = false; P.Refresh()
    assert(w.ui.profileCaption.text:find("Layout and colors are shared", 1, true))
end)

Case("U02", function()
    local w, P, Page, config, CDM = World()
    config.c1_on, config.c1_shareContents = true, true
    config.listsData = assert(CDM.Codec.EncodeLists({ shared = { c1 = { "s133" } }, specs = { [63] = { c1 = { "s122" } } } }))
    Page.Select("c1")
    w.Fire(w.ui.spellButtons.clear, "OnEnter")
    assert(GameTooltip.line == "Empties this shared group for all specializations. You can undo it.",
        "U02: shared clear must explain its actual scope")
    w.Fire(w.ui.spellButtons.copy, "OnEnter")
    assert(GameTooltip.line == "This shared group's list already applies to all specializations.")
    assert(Sentence(w, "These spells apply to all specializations. Clearing the group empties it for all of them; turning sharing off brings back each spec's own list."),
        "U02: visible help still described a per-specialization list")
    assert(Page.ClearWithUndo("c1") and Page.note == "Removed every spell from Custom bar 1 for all specializations.")
    local data = CDM.Codec.DecodeLists(config.listsData)
    assert(not data.shared.c1 and data.specs[63].c1[1] == "s122")
    Page.RunUndo()
    assert(CDM.Codec.DecodeLists(config.listsData).shared.c1[1] == "s133")
    config.c1_shareContents = false; P.Refresh()
    w.Fire(w.ui.spellButtons.clear, "OnEnter")
    assert(GameTooltip.line == "Empties this bar for this specialization. You can undo it.")
    -- Modern hosts defer the detailed help until hover; its scope must stay live.
    local modern, details = boot()
    modern.W.DescriptionDetails = true
    modern.W.Description = function(body, text, x, y, width, _, help)
        if type(help) == "function" then details = help end
        return modern.P.Text(body, text, x, y, width)
    end
    modern.Build(720)
    modern.Config().c1_shareContents = true
    modern.Page.Select("c1")
    assert(details and details():find("apply to all specializations", 1, true))
    modern.Config().c1_shareContents = false
    assert(details():find("Lists are kept per specialization.", 1, true))
end)

Case("U03", function()
    local w, P, Page, config, CDM = World()
    local target = CDM.SLOT_INDEX.uti + CDM.OVERFLOW.OFF
    config.ess_overflow, config.ess_maxIcons, config.uti_on, config.uti_overflow = target, 3, false, 1
    local dropdown = Control(w, "c1_overflow")
    local function Reason(text)
        P.Refresh()
        local note = Sentence(w, text)
        assert(note and note.points[1][2] == dropdown and note.points[1][3] == "BOTTOMLEFT",
            "U03: missing reason below the overflow choice: " .. text)
        assert(config.ess_overflow == target, "U03: explaining an invalid choice must preserve it")
        assert(dropdown.row.values[target].tooltip(dropdown.row.values[target]) == text)
    end
    Reason("Overflow is inactive because the destination bar is off.")
    config.uti_on, config.uti_overflow = true, CDM.SLOT_INDEX.def + CDM.OVERFLOW.OFF
    Reason("Overflow is inactive because the destination also sends excess cooldowns. Turn off its overflow first.")
    config.ess_maxIcons = 0
    Reason("Overflow is inactive because Maximum icons is unlimited (0). Set a limit first.")
    config.ess_maxIcons, config.uti_overflow = 3, 1
    P.Refresh()
    assert(Page.OverflowReason("ess") == nil)
end)

Case("U05", function()
    local w, _, Page, config, CDM = World()
    local conversion = 0
    w.P.S.CooldownManagerConvertAnchor = function(slot, anchor)
        conversion = conversion + 1
        assert(slot == "uti" and anchor == CDM.ANCHOR.FREE + CDM.SLOT_INDEX.ess)
        return { uti_anchor = anchor, uti_x = 0, uti_y = 0 }
    end
    config.uti_x, config.uti_y, config.uti_gap, config.uti_side = 27, -19, 31, CDM.SIDE.ABOVE
    Page.OpenBarMenu(w.ui.previewUndo, "uti")
    local reset
    for _, item in ipairs(w.Dropdown().values) do if item.value == "reset" then reset = item end end
    assert(reset and reset.tooltip:find("Resets attachment, side, gap and growth.", 1, true)
        and reset.tooltip:find("Attached offsets become zero", 1, true), "U05: reset text promises to keep position")
    assert(Page.ResetBar("uti") and conversion == 1 and config.uti_x == 0 and config.uti_y == 0)
    assert(config.uti_side == CDM.SIDE.BELOW and config.uti_gap == 2)
    Page.RunUndo()
    assert(config.uti_x == 27 and config.uti_y == -19 and config.uti_gap == 31)
end)

Case("U06", function()
    local w, _, Page, config, CDM = World()
    local full = {}
    for i = 1, CDM.LIMITS.entries do full[i] = "s" .. (100000 + i) end
    config.c1_on = true
    config.listsData = assert(CDM.Codec.EncodeLists({ specs = {
        [62] = { c1 = { "s133" } }, [63] = { c1 = full, c2 = { "s133" } },
    } }))
    assert(Page.CopyListWithUndo("c1"))
    assert(Page.note == "Copied 1 entries to 1 other specializations. 1 destinations were full and could not accept every entry.",
        "U06: partial success hid the full destination")
    local data = CDM.Codec.DecodeLists(config.listsData)
    assert(data.specs[64].c1[1] == "s133" and #data.specs[63].c1 == CDM.LIMITS.entries
        and data.specs[63].c2[1] == "s133" and Page.undo)
    Page.RunUndo()
    data = CDM.Codec.DecodeLists(config.listsData)
    assert(not data.specs[64] and data.specs[63].c2[1] == "s133")
    -- A destination may accept one entry and refuse the next; both counts matter.
    table.remove(full)
    config.listsData = assert(CDM.Codec.EncodeLists({ specs = {
        [62] = { c1 = { "s133", "s122" } }, [63] = { c1 = full },
    } }))
    assert(Page.CopyListWithUndo("c1"))
    assert(Page.note == "Copied 3 entries to 2 other specializations. 1 destinations were full and could not accept every entry.")
end)

Case("U08", function()
    local w, _, _, _, CDM = World()
    for _, key in ipairs({ "specPositions", CDM.KEYS.c1.centerFirst }) do
        local widget = Control(w, key)
        w.Fire(widget, "OnEnter")
        assert(GameTooltip.shown and GameTooltip.owner == widget
            and GameTooltip.line == w.P.catalog.cooldownManager.rules[key].tooltip,
            "U08: catalog hover help did not reach " .. key)
    end
end)

Case("U09", function()
    local w, P, Page, config, CDM = World()
    config.c2_on, config.c2_kind = true, CDM.KIND.AURA_BAR
    config.c2_barStackEach, config.c2_barStackMarks = true, "2,4"
    Page.Select("c2")
    local marks
    for _, widget in ipairs(w.ctx.widgets) do
        if widget.label == "Stack markers (numbers separated by commas)" then marks = widget end
    end
    assert(marks and not marks.enabled and marks.disabledReason() == 'Turn off "Mark every stack" to change this.',
        "U09: overridden stack markers stayed editable without a reason")
    config.c2_barStackEach = false; P.Refresh()
    assert(marks.enabled and config.c2_barStackMarks == "2,4", "U09: stored custom markers were discarded")
    config.c2_kind, config.c2_align, config.c2_centerFirst = CDM.KIND.COOLDOWN, CDM.ALIGN.START, true
    P.Refresh()
    local centered = Control(w, "c1_centerFirst")
    assert(not centered.enabled and centered.disabledReason() == 'Choose Center for "Alignment".',
        "U09: centered-first needs a Center alignment explanation")
    config.c2_align = CDM.ALIGN.CENTER; P.Refresh()
    assert(centered.enabled and config.c2_centerFirst)
end)

Case("U12", function()
    for _, width in ipairs({ 420, 591, 592, 720 }) do
        local w = boot()
        local original, requested = w.W.SettingsRows, {}
        w.W.SettingsRows = function(ctx, body, spec)
            requested[#requested + 1] = spec
            return original(ctx, body, spec)
        end
        w.Build(width)
        assert(#requested > 0)
        for _, spec in ipairs(requested) do
            assert(spec.columns == (spec.width >= 560 and 2 or 1),
                "U12: CDM grid ignored the shared 560px breakpoint at page width " .. width)
        end
    end
end)

Case("U20", function()
    local w, _, Page = World()
    local undoButtons = { w.ui.previewUndo }
    for _, frame in ipairs(w.frames) do
        if frame.text == "Undo" and frame ~= w.ui.previewUndo then undoButtons[#undoButtons + 1] = frame end
    end
    assert(#undoButtons == 2, "U20 fixture needs both Undo controls")
    for _, button in ipairs(undoButtons) do
        Page.Note("Inspect the deletion.", function() end)
        assert(next(w.Tasks()))
        w.Fire(button, "OnEnter")
        assert(next(w.Tasks()) == nil, "U20: hovering Undo left the expiry running")
        -- Simulate 16 seconds by firing every scheduled timer twice.
        for _ = 1, 2 do for task in pairs(w.Tasks()) do task.fn() end end
        assert(Page.undo and Page.note == "Inspect the deletion.", "U20: Undo expired while hovered")
        w.Fire(button, "OnLeave")
        local task = assert(next(w.Tasks()), "U20: leaving Undo must restart expiry")
        task.fn()
        assert(Page.undo == nil)
        Page.Note("Inspect again.", function() end)
        w.Fire(button, "OnEnter"); w.Fire(button, "OnHide")
        assert(next(w.Tasks()), "U20: hiding hovered Undo left expiry paused")
        Page.ClearNote()
        assert(next(w.Tasks()) == nil)
    end
end)

Case("U21", function()
    local w = World()
    local widget = Control(w, "raidEssentials")
    w.Fire(widget, "OnEnter")
    assert(GameTooltip.owner == widget and GameTooltip.line ==
        "Uses MSUF's default spell lists for each specialization. Your own list changes are kept. This does not switch Suite profiles.",
        "U21: cooldown profiles still has no clear spell-list explanation")
end)

Case("F02", function()
    local w, _, Page, config, CDM = World()
    local initial = assert(CDM.Codec.EncodePositions({ spec = 62, specs = {
        [63] = { c1 = { x = 913, y = 117, size = 72 }, c2 = { x = 312 } },
        [64] = { c1 = { x = -700, y = 44 } },
    } }))
    config.positionsData, config.c1_on, config.c1_name = initial, true, "Old bar"
    config.listsData = assert(CDM.Codec.EncodeLists({ specs = { [63] = { c1 = { "s133" } } } }))
    local lists = config.listsData
    assert(Page.DeleteBar("c1"))
    local data = CDM.Codec.DecodePositions(config.positionsData)
    assert(not data.specs[63].c1 and data.specs[63].c2.x == 312 and not data.specs[64],
        "F02: deleting a slot retained another specialization's geometry")
    local deletionUndo = assert(Page.undo)
    assert(Page.AddBar(CDM.KIND.COOLDOWN) and Page.selected == "c1")
    -- A specialization without a saved slot inherits the current geometry.
    w.SetSpec(63)
    data = CDM.Codec.DecodePositions(config.positionsData)
    assert(not data.specs[63].c1 and config.c1_x ~= 913 and config.c1_size ~= 72,
        "F02: reused slot recovered the deleted layout")
    -- Restore the post-delete flat settings before exercising the guarded Undo.
    config.c1_on, config.c1_name = false, ""
    assert(deletionUndo())
    assert(config.positionsData == initial and config.listsData == lists and config.c1_name == "Old bar")
    -- A named disabled slot reused directly must clear and restore layouts too.
    config.c1_on = false
    for i = 2, 6 do config["c" .. i .. "_on"] = true end
    assert(Page.AddBar(CDM.KIND.COOLDOWN) and Page.undo)
    data = CDM.Codec.DecodePositions(config.positionsData)
    assert(not data.specs[63].c1 and data.specs[63].c2.x == 312)
    Page.RunUndo()
    assert(config.positionsData == initial and not config.c1_on and config.c1_name == "Old bar")
    -- An older build left layouts behind: the slot is off and unnamed, so it
    -- counts as fresh, yet adding a bar there must still drop them (with Undo).
    -- (The fixture's codec strings are handles into one world, so encode in it.)
    local _, _, lpage, lconfig, LCDM = World()
    local older = assert(LCDM.Codec.EncodePositions({ spec = 62, specs = {
        [63] = { c1 = { x = 913, y = 117, size = 72 }, c2 = { x = 312 } },
        [64] = { c1 = { x = -700, y = 44 } },
    } }))
    lconfig.positionsData = older
    assert(not lconfig.c1_on and lconfig.c1_name == "")
    assert(lpage.AddBar(LCDM.KIND.COOLDOWN) and lpage.selected == "c1")
    data = LCDM.Codec.DecodePositions(lconfig.positionsData)
    assert(not data.specs[63].c1 and data.specs[63].c2.x == 312 and not data.specs[64],
        "F02: a fresh slot kept the layouts an older build left behind")
    assert(lpage.undo, "F02: dropping legacy layouts needs an Undo")
    lpage.RunUndo()
    assert(lconfig.positionsData == older and not lconfig.c1_on and lconfig.c1_name == "")
    -- Nothing to drop: a plain new bar offers no Undo.
    local _, _, cpage, _, CCDM = World()
    assert(cpage.AddBar(CCDM.KIND.COOLDOWN) and cpage.undo == nil)
end)
