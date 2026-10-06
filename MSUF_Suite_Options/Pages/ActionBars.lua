local _, P = ...
local Suite, S, M, W, T, Tr, HM = P.Suite, P.S, P.M, P.W, P.T, P.Tr, P.HM
local PAGE, ID = "suite_actionbars", "actionbars"
local COUNT = Suite.ActionBarCount
local NEVER = Suite.ActionBarEnum.VISIBILITY.NEVER

-- Retail's rotation recommendation runs only while Blizzard's Assisted
-- Highlight option (the assistedCombatHighlight CVar) is on; Forever has no
-- assisted combat and hides those options.
local APPEARANCE = "Shared look of every suite action button. Blizzard's own highlight art is used when you pick Blizzard."
local HELP = {
    appearance = Suite.Client.isForever and APPEARANCE or P.Help(APPEARANCE,
        "Rotation recommendations appear while Blizzard's Assisted Highlight option is on. Blizzard's own recommendation highlight reaches only the bars that reuse Blizzard's buttons (2 to 8); Ring and Fill cover every bar."),
    cooldowns = "Cooldown numbers, swipes and state colors come from the client's action data; nothing is polled.",
    text = "Fonts, outlines, shadows and Smooth/Sharp/Slug rendering for keybinds, macro names, counts and cooldown numbers. Sizes are set per bar below. Slug has no shadow.",
    behavior = "Paging switches bar 1 between pages, like Blizzard's own main bar. Key bindings keep using Blizzard's commands.",
    editor = "Select a bar to adjust its layout and visibility.",
}
-- Per-bar settings grouped by topic; position (Point/X/Y) is never copied.
local GROUPS = {
    { id = "visibility", title = "When the selected bar appears", suffixes = { "Visibility", "HideGamepad", "Alpha", "FadeAlpha", "ClickThrough" } },
    { id = "layout", title = "Layout for the selected bar",
        suffixes = { "Buttons", "Rows", "Size", "Spacing", "Vertical", "Start", "ShowEmpty", "Layer", "Point", "X", "Y" } },
    { id = "text", title = "Text for the selected bar", suffixes = { "Keybind", "KeybindSize", "Macro", "MacroSize",
        "CountSize", "CooldownSize", "CooldownAutoSize", "KeybindPoint", "KeybindX", "KeybindY", "MacroPoint",
        "MacroX", "MacroY", "CountPoint", "CountX", "CountY", "CooldownPoint", "CooldownX", "CooldownY" } },
    { id = "ornaments", title = "Endcaps for the selected bar", suffixes = { "LeftEndcap", "LeftEndcapSize",
        "LeftEndcapX", "LeftEndcapY", "RightEndcap", "RightEndcapSize", "RightEndcapX", "RightEndcapY" } },
    { id = "background", title = "Background for the selected bar", suffixes = { "Background", "BackgroundColor",
        "BackgroundAlpha", "BackgroundPadding", "BackgroundPaddingX", "BackgroundPaddingY", "BackgroundX",
        "BackgroundY", "BackgroundBorder" } },
}
local POSITION = { Point = true, X = true, Y = true }
local ESSENTIAL = {
    layout = { Buttons = true, Rows = true, Size = true, Spacing = true, Vertical = true, ShowEmpty = true },
    text = { Keybind = true, KeybindSize = true, Macro = true, MacroSize = true,
        CountSize = true, CooldownSize = true, CooldownAutoSize = true },
    visibility = { Visibility = true, Alpha = true, FadeAlpha = true },
    ornaments = { LeftEndcap = true, LeftEndcapSize = true, RightEndcap = true, RightEndcapSize = true },
    background = { Background = true, BackgroundAlpha = true, BackgroundPadding = true, BackgroundBorder = true },
}
P.ActionBarSearchGroups = GROUPS
-- Copy To categories, one per section above, like the Unit and Group pages.
local COPY_CATEGORIES = {
    { key = "visibility", label = "Visibility", default = true,
      description = "Copies when the bar is shown, its opacity, fade and click-through." },
    { key = "layout", label = "Layout", default = true,
      description = "Copies buttons, rows, size, spacing, growth direction and empty slots. Position is never copied." },
    { key = "text", label = "Text", default = true,
      description = "Copies keybind and macro name visibility and every text size." },
    { key = "ornaments", label = "Endcaps", default = true, description = "Copies both endcaps, their sizes and offsets." },
    { key = "background", label = "Background", default = true,
      description = "Copies the bar background with its color, opacity and padding." },
}

-- The Copy To choices last for the session, like the Unit and Group pages.
local selected, copyDestinations = 1, nil
local copyScopes = {}
for _, category in ipairs(COPY_CATEGORIES) do copyScopes[category.key] = category.default end
local function BarKey(key)
    local suffix = key:match("^bar%d+(.+)$")
    return suffix and ("bar" .. selected .. suffix) or key
end
local function Rule(key) return P.catalog[ID].rules[key] end
-- S.ActionBarAvailable and S.OpenQuickKeybind come with the action bar addon.
local function Available(index)
    return not S.ActionBarAvailable or S.ActionBarAvailable(index) and true or false
end

-- Settings operations are plain catalog writes, so they also work while the
-- module is off or its runtime is not loaded yet.
local function GroupOf(suffix)
    for _, group in ipairs(GROUPS) do
        for _, candidate in ipairs(group.suffixes) do if candidate == suffix then return group.id end end
    end
end
local function BarTitle(index) return Tr(Suite.ActionBarTitles[index]) end
local function BarOff(index) return P.Get(ID, "bar" .. index .. "Visibility") == NEVER end

-- Blizzard_EditMode loads at startup on every supported client; the button
-- only reads whether Blizzard would enter its Edit Mode now.
local function CanMoveExtraAbility()
    return EditModeManagerFrame:CanEnterEditMode() == true
end

-- Adds what bar `to` needs to match bar `from` in the chosen groups. A
-- setting either bar does not have (hidden, such as macro names on the
-- Stance and Pet bars) is not copied.
local function CopyValues(values, from, to, groups)
    for _, group in ipairs(GROUPS) do
        if groups[group.id] then
            for _, suffix in ipairs(group.suffixes) do
                local rule, source = Rule("bar" .. to .. suffix), Rule("bar" .. from .. suffix)
                if not POSITION[suffix] and rule and not rule.hidden and source and not source.hidden then
                    values["bar" .. to .. suffix] = P.Get(ID, "bar" .. from .. suffix)
                end
            end
            if group.id == "visibility" then
                local mode = P.Get(ID, "bar" .. from .. "Visibility")
                values["bar" .. to .. "ResumeVisibility"] = mode == NEVER
                    and P.Get(ID, "bar" .. from .. "ResumeVisibility") or mode
            end
        end
    end
end
-- One undo step, named like the Unit and Group copies, for any number of bars.
local function CopyBars(label, from, targets, groups)
    if P.Combat() then return false end
    local values = {}
    for _, to in ipairs(targets) do
        if to ~= from then CopyValues(values, from, to, groups) end
    end
    if not next(values) then return false end
    return P.WithHistory(label, "suite:" .. ID .. ".copy", function()
        return P.SetMany(ID, values) == true
    end) == true
end

-- The section menu's "Copy section", like the Unit and Group sections: the
-- selected bar is the source, a bar that is switched off is listed but locked.
local function SectionCopy(group)
    return {
        label = "Copy to another bar",
        offLabel = "Bar disabled",
        source = function() return selected end,
        sourceLabel = BarTitle,
        targets = function(source)
            local items = {}
            for index = 1, COUNT do
                if index ~= source and Available(index) then items[#items + 1] = { value = index, text = BarTitle(index) } end
            end
            return items
        end,
        targetOff = BarOff,
        run = function(source, target) return CopyBars("Copy section", source, { target }, { [group] = true }) end,
    }
end
local function Preset(index, kind)
    local p = "bar" .. index
    local maxButtons = Rule(p .. "Buttons").max
    local rows = kind == "double" and 2 or kind == "grid" and 3 or kind == "column" and maxButtons or 1
    P.SetMany(ID, { [p .. "Buttons"] = maxButtons, [p .. "Rows"] = rows, [p .. "Vertical"] = kind == "column", [p .. "Start"] = 1 })
end

-- A quick switch hides a bar without discarding its combat or mouseover rule.
-- The resume mode is a hidden profile setting, so it survives reloads; the
-- toggle key bindings switch through the same rule (Core/Bindings.lua).
local function SetBarOn(index, on)
    local values = Suite.ActionBarSwitchValues(S.Config(ID), index, on)
    if values then P.SetMany(ID, values) end
end

local function BuildQuick(ctx, body, y, width)
    local section = "suite_actionbars_actionbars_module"
    local columns = width >= 560 and 2 or 1
    local cell = columns == 2 and math.floor((width - 12) / 2) or width
    local help = P.Text(body, "Switch each bar on or off here. Turning it back on restores its previous visibility mode. Select Layout to customize the bar selected above.", 16, y, width)
    local top = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 18
    for index = 1, COUNT do
        local bar = index
        local x = 16 + ((index - 1) % columns) * (cell + 12)
        local y = top - math.floor((index - 1) / columns) * 54
        local key = "bar" .. index .. "Visibility"
        -- These switches are actions on a fixed bar. The selected bar's
        -- mode dropdown keeps the sole template setting identity for search.
        local meta = P.Meta(PAGE, ID, "quick.bar" .. index, "action", section)
        local toggle = M.BindSwitchAt(ctx, body, Tr(Suite.ActionBarTitles[index]), x, y, cell - 52,
            function() return P.Get(ID, key) ~= NEVER end,
            function(value) SetBarOn(bar, value == true) end, meta)
        P.ActionBarMenu.Prepare(body, { { widget = toggle, rule = Rule(key), meta = meta, label = BarTitle(bar) } })
        local status = P.Text(body, "", x + 44, y - 26, cell - 44, T.colors.dim or T.colors.muted)
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(toggle, Available(bar) and not P.Combat())
            if not Available(bar) then
                P.SetTranslatedText(status, Tr("Not available on this client"))
                return
            end
            local mode = P.Get(ID, key)
            local label = Rule(key).choices[mode]
            if mode == NEVER then
                local previous = P.Get(ID, "bar" .. bar .. "ResumeVisibility")
                P.SetTranslatedText(status, string.format(Tr("Off - restores %s"), Tr(Rule(key).choices[previous])))
            else
                P.SetTranslatedText(status, Tr(label))
            end
        end)
    end
    return top - math.ceil(COUNT / columns) * 54 - 4
end

-- The "Enable action bars" card's reset: the switch and every quick switch.
local function ResetQuick()
    local keys = {}
    keys[#keys + 1] = "enabled"
    for index = 1, COUNT do
        keys[#keys + 1] = "bar" .. index .. "Visibility"
        keys[#keys + 1] = "bar" .. index .. "ResumeVisibility"
    end
    return P.ResetRules(ID, {}, nil, keys)
end

local function BuildPreview(ctx, parent, y, width, height)
    return P.ActionBarPreview.Build(ctx, parent, y, width, height, function() return selected end)
end

-- The selected bar stays above the scroller, so every topic keeps its scope.
local function BuildSelection(ctx, b, attachCopy)
    local body
    local narrow = (b.width or ctx.width or 720) - 32 < 560
    local height = narrow and 294 or 256
    if W.FixedPreviewSection then
        body = W.FixedPreviewSection(ctx, b, { title = Tr("Selected bar"), height = height })
        -- The host caps compact previews at 180px; this header also contains
        -- navigation and bar controls. Reserve its full height in the dock.
        HM.SetFixedPreviewHeight(body, height)
        body:SetHeight(height)
    else
        body = b:Section(Tr("Selected bar"), height)
    end
    ctx._msufSuiteActionBarHeader = body
    if body.title then body.title:Hide() end
    local width = (HM.GetSectionWidth(body) or b.width or 720) - 32
    local half, bars = math.floor((width - 12) / 2), {}
    for i = 1, COUNT do bars[i] = { value = i, text = BarTitle(i) } end
    local picker = M.BindDropdownAt(ctx, body, Tr("Selected bar"), 16, -54, bars, narrow and width - 100 or half,
        function() return selected end,
        function(value)
            selected = tonumber(value) or 1
            P.Refresh()
        end,
        P.Meta(PAGE, ID, "editor.selected", "ephemeral", "suite_actionbars_editor"))
    local meta = P.Meta(PAGE, ID, "selected.enabled", "action", "suite_actionbars_bar_visibility")
    local toggle = M.BindSwitchAt(ctx, body, Tr("Show this bar"), narrow and 16 or 28 + half,
        narrow and -112 or -68, narrow and width or width - half - 106,
        function() return not BarOff(selected) end,
        function(value)
            if P.Combat() then return end
            SetBarOn(selected, value == true)
        end, meta)
    M.TrackRefresh(ctx, function() W.SetControlEnabled(toggle, Available(selected) and not P.Combat()) end)
    local copyTo, copyButton = attachCopy(ctx, body, -44)
    if copyTo then M.TrackRefresh(ctx, function() copyTo.Refresh() end) end
    ctx._msufSuiteActionBarScopedControls = {
        suite_actionbars_bar_visibility = { widget = toggle, meta = meta,
            rule = { key = "selected.enabled", label = "Show this bar" } },
        suite_actionbars_editor = { widget = copyButton,
            meta = P.Meta(PAGE, ID, "editor.copyTo", "ephemeral", "suite_actionbars_editor"),
            rule = { key = "editor.copyTo", label = "Copy To" } },
    }
    BuildPreview(ctx, body, narrow and -148 or -110, width, 132)
    function ctx.RefreshActionBarScope()
        local shared = P.ActionBarMenu.IsShared(ctx)
        local title = HM.GetControlTitle(picker)
        if title then P.SetTranslatedText(title, Tr(shared and "Preview bar" or "Selected bar")) end
        W.SetControlShown(toggle, not shared)
        if copyButton then
            copyButton:SetShown(not shared)
            if shared then copyTo.Hide() end
        end
        P.ActionBarPreview.RefreshScope(ctx._msufSuiteActionBarPreview)
    end
    M.TrackRefresh(ctx, ctx.RefreshActionBarScope)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

-- Reuse the shared Copy To popup with independently selectable destinations.
-- The chosen groups still form one undo step across all destination bars.
local TARGET_WIDTHS = { [10] = 32, [11] = 56, [12] = 40, all = 38 }
local function ShortBarLabel(index)
    local title = Suite.ActionBarTitles[index]
    return title:match("^Action bar (%d+)$") or (title:gsub(" bar$", ""))
end
local function CopyTargets(source)
    local targets = {}
    for index = 1, COUNT do
        if index ~= source and Available(index) then targets[#targets + 1] = index end
    end
    return targets
end
local function CopyDestination(source)
    if not copyDestinations then
        copyDestinations = {}
        local first = CopyTargets(source)[1]
        if first then copyDestinations[first] = true end
    end
    local all, any = true, false
    for index = 1, COUNT do
        if index == source or not Available(index) then copyDestinations[index] = nil
        else
            any = true
            if not copyDestinations[index] then all = false end
        end
    end
    copyDestinations.all = any and all or false
    return copyDestinations
end
local function SelectCopyDestination(key)
    local targets = CopyDestination(selected)
    if key == "all" then
        local on = not targets.all
        for _, index in ipairs(CopyTargets(selected)) do targets[index] = on or nil end
    else
        targets[key] = not targets[key] or nil
    end
end
local function ConfirmCopyAll(run)
    P.Confirm("copy-bars",
        Tr("Copy these settings to ALL action bars?\n\nThis overwrites the chosen settings on every other bar. Positions stay as they are."),
        run)
end
local function RunCopyTo(popup)
    if P.Combat() then return false end
    local function Feedback(text, kind) if M.ShowStatusFeedback then M.ShowStatusFeedback(text, kind, 1.8) end end
    local groups, any = {}, false
    for key, on in pairs(copyScopes) do
        groups[key] = on == true
        any = any or on == true
    end
    if not any then return Feedback(Tr("No copy categories selected."), "warning") end
    local source, choices = selected, CopyDestination(selected)
    local targets, labels = {}, {}
    for _, index in ipairs(CopyTargets(source)) do
        if choices[index] then
            targets[#targets + 1], labels[#labels + 1] = index, BarTitle(index)
        end
    end
    if #targets == 0 then return Feedback(Tr("Select at least one destination bar."), "warning") end
    local all = choices.all
    local function Run()
        if CopyBars("Copy Bar Settings", source, targets, groups) then
            Feedback(string.format(Tr("Copied to %s"), all and Tr("All") or table.concat(labels, ", ")), "ok")
            popup:Hide()
            P.Refresh()
        else
            Feedback(Tr("Nothing was copied."), "warning")
        end
    end
    if all then return ConfirmCopyAll(Run) end
    return Run()
end
-- Uses MSUF's own Copy To popup, so the chrome is the same on every page.
local function AttachCopyTo(ctx, body, y)
    local Shared = M.UnitSectionsShared
    if not (Shared and Shared.MakeScopeCopyPopup) then return nil end
    local copy = (W.RoleButton and W.RoleButton(body, "Copy To", "success", 82, 24))
        or W.TopButton(body, "Copy To", 82, 24)
    copy:SetPoint("TOPRIGHT", body, "TOPRIGHT", -16, y - 24)
    HM.AllowCombatClick(copy)
    HM.SkipHistoryCheckpoint(copy)
    local targets = {}
    for index = 1, COUNT do targets[index] = { value = index, text = ShortBarLabel(index) } end
    targets[#targets + 1] = { value = "all", text = "All" }
    local api = Shared.MakeScopeCopyPopup(copy, {
        controlDomain = "suite", controlPageKey = PAGE, controlPath = "actionbars.copy",
        width = 480, height = 240, categoryRowsPerColumn = 3,
        categories = COPY_CATEGORIES, scopes = copyScopes,
        targets = targets, targetWidths = TARGET_WIDTHS, targetWidth = 26,
        sourceKey = function() return selected end,
        sourceLabel = BarTitle,
        selectedTarget = CopyDestination,
        isTargetVisible = function(key, source) return key == "all" or (key ~= source and Available(key)) end,
        onTargetClick = SelectCopyDestination,
        targetLabel = Tr("Destination bars (select one or more)"),
        runLabel = "Copy Selected", runWidth = 128,
        onRun = function(_, popup) return RunCopyTo(popup) end,
    })
    copy:SetScript("OnClick", function(self) api.Show(self) end)
    body:HookScript("OnHide", function() api.Hide() end)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(copy, P.Meta(PAGE, ID, "editor.copyTo", "ephemeral", "suite_actionbars_editor"), "Copy To", "button")
    end
    return api, copy
end

-- A lazy host builds the editor's buttons when it first opens (P.LazySection).
local function EditorContent(ctx, b, body)
    local width = math.max(260, (HM.GetSectionWidth(body) or b.width or 720) - 32)
    local half = math.floor((width - 12) / 2)
    local help = P.Description(body, HELP.editor, 16, -18, width)
    local y = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    local quarter = math.floor((width - 36) / 4)
    for i, preset in ipairs({ { "row", "One row" }, { "double", "Two rows" }, { "grid", "Three rows" }, { "column", "One column" } }) do
        P.Button(ctx, body, preset[2], 16 + (i - 1) * (quarter + 12), y, quarter, function() Preset(selected, preset[1]) end,
            function() return S.Availability(ID) and true or false end,
            P.Meta(PAGE, ID, "editor.preset." .. preset[1], "action", "suite_actionbars_editor"))
    end
    y = y - 40
    P.Button(ctx, body, "Move selected bar", 16, y, half, function() P.MoveOnScreen(ID, "bar" .. selected) end,
        function() return P.Get(ID, "enabled") and Available(selected) and P.Get(ID, "bar" .. selected .. "Visibility") ~= NEVER end,
        P.Meta(PAGE, ID, "editor.move", "action", "suite_actionbars_editor"))
    P.Button(ctx, body, "Key bindings", 28 + half, y, half, function() if S.OpenQuickKeybind then S.OpenQuickKeybind() end end,
        function() return S.OpenQuickKeybind ~= nil end,
        P.Meta(PAGE, ID, "editor.bindings", "action", "suite_actionbars_editor"))
    y = y - 40
    -- Blizzard owns the extra action and zone ability buttons and moves them
    -- in its Edit Mode only. Opened from this page's own code Edit Mode would
    -- run tainted, so the button runs Blizzard's /editmode command from a
    -- secure overlay (P.SecureMacroButton); the Suite never moves or
    -- reparents the protected buttons.
    P.SecureMacroButton(ctx, body, "Move extra action button", 16, y, width - 32, "/editmode",
        CanMoveExtraAbility, P.Meta(PAGE, ID, "editor.extraAbility", "action", "suite_actionbars_editor"))
    return y - 38
end

local function BuildEditor(ctx, b)
    P.LazySection(b, "suite_actionbars_editor", Tr("Customize a bar"), false, {
        content = function(body) return EditorContent(ctx, b, body) end,
        shell = function(body)
            P.AttachSectionReset(ctx, body, "Customize a bar", function()
                return P.ResetPrefix(ID, "bar" .. selected)
            end)
        end,
        finish = function(body, y) P.FinishBody(b, body, y) end,
    })
end

-- Per-bar controls follow the selected bar; bars missing on this client and
-- options that do not exist for a bar (macro names on stance/pet) are disabled.
P.Gates[ID] = function(rule, key)
    local index = tonumber(key:match("^bar(%d+)"))
    if not index then return true end
    local live = Rule(key)
    if not live or live.hidden then return false end
    return Available(index)
end

P.SearchPreparers[ID] = function(rule)
    if not rule.bar or P.Gates[ID](rule, BarKey(rule.key)) then return end
    local suffix = rule.key:match("^bar%d+(.+)$")
    for index = 1, COUNT do
        local candidate = Rule("bar" .. index .. suffix)
        if candidate and not candidate.hidden and Available(index) then
            selected = index
            P.Refresh()
            return
        end
    end
end

local function Build(ctx)
    local b = P.ActionBarMenu.Builder(ctx)
    BuildSelection(ctx, b, AttachCopyTo)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Key bindings", function() if S.OpenQuickKeybind then S.OpenQuickKeybind() end end,
          function() return S.OpenQuickKeybind ~= nil end, key = "bindings" },
        { "Move on screen", function() P.MoveOnScreen(ID, "bar1") end, nil, key = "move" },
        { "Reload UI", function() ReloadUI() end,
          function() return S.states[ID] and S.states[ID].reloadRequired ~= nil end, key = "reload" },
    }, { title = "Enable action bars", open = false, help = "Shared settings affect every action bar.", reset = ResetQuick,
        prepareControl = function(body, widget, key, kind, label)
            P.ActionBarMenu.Prepare(body, { { widget = widget, rule = { key = key, label = label },
                meta = P.Meta(PAGE, ID, key, kind, "suite_actionbars_actionbars_module") } })
        end,
        buildBody = function(body, y, width) return BuildQuick(ctx, body, y, width) end })
    P.ActionBarMenu.Rules(ctx, b, "suite_actionbars_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = "Choose the shared button colors and frame. Layout, bindings and visibility stay as set. Changing an individual color switches the label to Custom.",
            extra = P.LookPresetButtons(ctx, PAGE, ID, "suite_actionbars_look"),
        })
    local templates = P.SectionRules(ID, "bar1")
    for _, group in ipairs(GROUPS) do
        local rules = {}
        for _, rule in ipairs(templates) do
            if GroupOf(rule.key:sub(5)) == group.id then rules[#rules + 1] = rule end
        end
        P.ActionBarMenu.Rules(ctx, b, "suite_actionbars_bar_" .. group.id, Tr(group.title), rules,
            { keyFn = BarKey, open = false, copy = SectionCopy(group.id), essential = ESSENTIAL[group.id],
              help = group.id == "visibility" and "The quick switch above remembers this mode when you turn the bar off. Choose Never to keep it hidden." or nil })
    end
    BuildEditor(ctx, b)
    for _, section in ipairs({ "appearance", "cooldowns", "text", "behavior" }) do
        local rules = P.SectionRules(ID, section)
        P.ActionBarMenu.Rules(ctx, b, "suite_actionbars_" .. section, Tr(rules[1].sectionTitle), rules,
            { help = HELP[section], open = false })
    end
    P.ActionBarMenu.Finish(ctx)
end

P.RegisterPage({ key = PAGE, label = "Action bars", title = "Action bars", build = Build, icon = { 2, 2 },
    nav = "interface", navOrder = 1,
    aliases = { "actionbars", "action_bars", "bars_suite" } })
