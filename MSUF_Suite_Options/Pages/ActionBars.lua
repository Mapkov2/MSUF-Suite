local _, P = ...
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local PAGE, ID = "suite_actionbars", "actionbars"
local COUNT = Suite.ActionBarCount or 12

local HELP = {
    appearance = "Shared look of every suite action button. Blizzard's own highlight art is used when you pick Blizzard.",
    cooldowns = "Cooldown numbers, swipes and state colors come from the client's action data; nothing is polled.",
    text = "Fonts, outlines, shadows and Smooth/Sharp/Slug rendering for keybinds, macro names, counts and cooldown numbers. Sizes are set per bar below. Slug has no shadow.",
    behavior = "Paging switches bar 1 between pages, like Blizzard's own main bar. Key bindings keep using Blizzard's commands.",
    editor = "Choose a bar to adjust its layout below. The preview uses sample buttons; empty slots and stances can differ in game.",
}
-- Per-bar settings grouped by topic; position (Point/X/Y) is never copied.
local GROUPS = {
    { id = "visibility", title = "When the selected bar appears", suffixes = { "Visibility", "Alpha", "FadeAlpha", "ClickThrough" } },
    { id = "layout", title = "Layout for the selected bar", suffixes = { "Buttons", "Rows", "Size", "Spacing", "Vertical", "Start", "ShowEmpty", "Point", "X", "Y" } },
    { id = "text", title = "Text for the selected bar", suffixes = { "Keybind", "KeybindSize", "Macro", "MacroSize", "CountSize", "CooldownSize" } },
    { id = "background", title = "Background for the selected bar", suffixes = { "Background", "BackgroundColor", "BackgroundAlpha", "BackgroundPadding" } },
}
local COPY_SCOPES = { layout = "layout", visibility = "visibility", appearance = { text = true, background = true } }

local selected, copyTarget, copyScope = 1, 2, "all"
local function BarKey(key)
    local suffix = key:match("^bar%d+(.+)$")
    return suffix and ("bar" .. selected .. suffix) or key
end
local function Rule(key) return P.catalog[ID].rules[key] end
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
local function CopyBar(from, to, scope)
    if from == to then return end
    local values = {}
    for _, group in ipairs(GROUPS) do
        local wanted = scope == "all" or COPY_SCOPES[scope] == group.id
            or type(COPY_SCOPES[scope]) == "table" and COPY_SCOPES[scope][group.id]
        if wanted then
            for _, suffix in ipairs(group.suffixes) do
                local rule = Rule("bar" .. to .. suffix)
                if suffix ~= "Point" and suffix ~= "X" and suffix ~= "Y" and rule and not rule.hidden then
                    values["bar" .. to .. suffix] = P.Get(ID, "bar" .. from .. suffix)
                end
            end
            if group.id == "visibility" then
                local mode = P.Get(ID, "bar" .. from .. "Visibility")
                values["bar" .. to .. "ResumeVisibility"] = mode == 6
                    and P.Get(ID, "bar" .. from .. "ResumeVisibility") or mode
            end
        end
    end
    P.SetMany(ID, values)
end
local function ResetBar(index)
    local values = {}
    for _, rule in ipairs(P.SectionRules(ID, "bar" .. index)) do values[rule.key] = rule.default end
    P.SetMany(ID, values)
end
local function Preset(index, kind)
    local p = "bar" .. index
    local maxButtons = Rule(p .. "Buttons").max
    local rows = kind == "double" and 2 or kind == "grid" and 3 or kind == "column" and maxButtons or 1
    P.SetMany(ID, { [p .. "Buttons"] = maxButtons, [p .. "Rows"] = rows, [p .. "Vertical"] = kind == "column", [p .. "Start"] = 1 })
end

-- A quick switch hides a bar without discarding its combat or mouseover rule.
-- The resume mode is a hidden profile setting, so it survives reloads.
local function SetBarOn(index, on)
    local key = "bar" .. index .. "Visibility"
    local resume = "bar" .. index .. "ResumeVisibility"
    local mode = P.Get(ID, key)
    if on then
        if mode == 6 then P.Set(ID, key, P.Get(ID, resume)) end
    elseif mode ~= 6 then
        P.SetMany(ID, { [key] = 6, [resume] = mode })
    end
end

local function BuildQuick(ctx, b)
    local section = "suite_actionbars_quick"
    local body = b:CollapsibleSection(section, Tr("Choose your bars"), 120, true)
    local width = math.max(260, (body._msuf2Width or b.width or 720) - 32)
    local columns = width >= 560 and 2 or 1
    local cell = columns == 2 and math.floor((width - 12) / 2) or width
    local help = P.Text(body, "Switch each bar on or off here. Turning it back on restores its previous visibility mode. Open Customize a bar below for layout and other options.", 16, -18, width)
    local top = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 18
    for index = 1, COUNT do
        local bar = index
        local x = 16 + ((index - 1) % columns) * (cell + 12)
        local y = top - math.floor((index - 1) / columns) * 54
        local key = "bar" .. index .. "Visibility"
        local meta = P.Meta(PAGE, ID, "quick.bar" .. index, "setting", section)
        meta.settingKey = "msufsuite.actionbars." .. key
        local toggle = M.BindSwitchAt(ctx, body, Tr(Suite.ActionBarTitles[index]), x, y, cell - 52,
            function() return P.Get(ID, key) ~= 6 end,
            function(value) SetBarOn(bar, value == true) end, meta)
        local status = P.Text(body, "", x + 44, y - 26, cell - 44, T.colors.dim or T.colors.muted)
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(toggle, Available(bar) and not P.Combat())
            if not Available(bar) then status:SetText(Tr("Not available on this client")); return end
            local mode = P.Get(ID, key)
            local label = Rule(key).choices[mode]
            if mode == 6 then
                local previous = P.Get(ID, "bar" .. bar .. "ResumeVisibility")
                status:SetText(Tr("Off") .. " - " .. Tr("restores") .. " " .. Tr(Rule(key).choices[previous]))
            else
                status:SetText(Tr(label))
            end
        end)
    end
    P.FinishBody(b, body, top - math.ceil(COUNT / columns) * 54 - 4)
end

-- Canonical grid math shared with the runtime: returns column, row of button i
-- (0-based) plus the grid size.
function P.ActionBarGrid(count, rows, vertical, start, i)
    rows = math.max(1, math.min(rows, count))
    local columns, lines, column, row
    if vertical then
        columns, lines = math.ceil(count / rows), rows
        row, column = i % rows, math.floor(i / rows)
    else
        columns = math.ceil(count / rows)
        lines = math.ceil(count / columns)
        column, row = i % columns, math.floor(i / columns)
    end
    if start == 2 or start == 4 then column = columns - 1 - column end
    if start == 3 or start == 4 then row = lines - 1 - row end
    return column, row, columns, lines
end

local function BuildPreview(ctx, parent, y, width)
    local height = 132
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", 16, y)
    host:SetSize(width, height)
    local back = host:CreateTexture(nil, "BACKGROUND")
    local tiles = {}
    for i = 1, 12 do
        local tile = CreateFrame("Frame", nil, host)
        tile.fill = tile:CreateTexture(nil, "ARTWORK")
        tile.fill:SetAllPoints()
        tile.fill:SetColorTexture(0.08, 0.20, 0.34, 1)
        tile.label = T.Font(tile, "GameFontHighlightSmall", tostring(i), T.colors.muted)
        tile.label:SetPoint("CENTER")
        tiles[i] = tile
    end
    local caption = P.Text(host, "", 0, -(height - 14), width)
    local function Paint()
        local p = "bar" .. selected
        local count = P.Get(ID, p .. "Buttons")
        local rows, vertical, start = P.Get(ID, p .. "Rows"), P.Get(ID, p .. "Vertical"), P.Get(ID, p .. "Start")
        local size, gap = P.Get(ID, p .. "Size"), P.Get(ID, p .. "Spacing")
        local _, _, columns, lines = P.ActionBarGrid(count, rows, vertical, start, 0)
        local realW = columns * size + (columns - 1) * gap
        local realH = lines * size + (lines - 1) * gap
        local fit = math.min(1, (width - 16) / math.max(1, realW), (height - 30) / math.max(1, realH))
        local left = (width - realW * fit) / 2
        local top = -((height - 22) - realH * fit) / 2
        for i, tile in ipairs(tiles) do
            tile:SetShown(i <= count)
            if i <= count then
                local column, row = P.ActionBarGrid(count, rows, vertical, start, i - 1)
                tile:ClearAllPoints()
                tile:SetSize(size * fit, size * fit)
                tile:SetPoint("TOPLEFT", host, "TOPLEFT", left + column * (size + gap) * fit, top - row * (size + gap) * fit)
            end
        end
        local showBack = P.Get(ID, p .. "Background")
        back:SetShown(showBack)
        if showBack then
            local pad = P.Get(ID, p .. "BackgroundPadding") * fit
            local r, g, b = P.RGB(P.Get(ID, p .. "BackgroundColor"))
            back:SetColorTexture(r, g, b, P.Get(ID, p .. "BackgroundAlpha") / 100)
            back:ClearAllPoints()
            back:SetPoint("TOPLEFT", host, "TOPLEFT", left - pad, top + pad)
            back:SetSize(realW * fit + pad * 2, realH * fit + pad * 2)
        end
        host:SetAlpha(math.max(0.25, P.Get(ID, p .. "Alpha") / 100))
        local text = Tr(Suite.ActionBarTitles[selected])
        if P.Get(ID, p .. "Visibility") == 6 then text = text .. "  (" .. Tr("hidden") .. ")" end
        if not Available(selected) then text = text .. "  (" .. Tr("not available on this client") .. ")" end
        caption:SetText(text)
    end
    M.TrackRefresh(ctx, Paint)
    return height
end

local function BuildEditor(ctx, b)
    local body = b:CollapsibleSection("suite_actionbars_editor", Tr("Customize a bar"), 120, false)
    local width = math.max(260, (body._msuf2Width or b.width or 720) - 32)
    local half = math.floor((width - 12) / 2)
    local help = P.Text(body, HELP.editor, 16, -18, width)
    local y = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    local bars = {}
    for i = 1, COUNT do bars[i] = { value = i, text = Tr(Suite.ActionBarTitles[i]) } end
    M.BindDropdownAt(ctx, body, Tr("Selected bar"), 16, y, bars, half,
        function() return selected end,
        function(value) selected = tonumber(value) or 1; if copyTarget == selected then copyTarget = selected == 1 and 2 or 1 end; P.Refresh() end,
        P.Meta(PAGE, ID, "editor.selected", "ephemeral", "suite_actionbars_editor"))
    y = y - 62
    y = y - BuildPreview(ctx, body, y, width) - 8
    local quarter = math.floor((width - 36) / 4)
    for i, preset in ipairs({ { "row", "One row" }, { "double", "Two rows" }, { "grid", "Three rows" }, { "column", "One column" } }) do
        P.Button(ctx, body, preset[2], 16 + (i - 1) * (quarter + 12), y, quarter, function() Preset(selected, preset[1]) end,
            function() return S.Availability(ID) and true or false end,
            P.Meta(PAGE, ID, "editor.preset." .. preset[1], "action", "suite_actionbars_editor"))
    end
    y = y - 40
    P.Button(ctx, body, "Move selected bar", 16, y, half, function() P.MoveOnScreen(ID, "bar" .. selected) end,
        function() return P.Get(ID, "enabled") and Available(selected) and P.Get(ID, "bar" .. selected .. "Visibility") ~= 6 end,
        P.Meta(PAGE, ID, "editor.move", "action", "suite_actionbars_editor"))
    P.Button(ctx, body, "Key bindings", 28 + half, y, half, function() if S.OpenQuickKeybind then S.OpenQuickKeybind() end end,
        function() return S.OpenQuickKeybind ~= nil end,
        P.Meta(PAGE, ID, "editor.bindings", "action", "suite_actionbars_editor"))
    P.FinishBody(b, body, y - 38)
end

local function BuildTools(ctx, b)
    local section = "suite_actionbars_tools"
    local body = b:CollapsibleSection(section, Tr("Advanced bar tools"), 120, false)
    local width = math.max(260, (body._msuf2Width or b.width or 720) - 32)
    local half = math.floor((width - 12) / 2)
    local help = P.Text(body, "Copy the selected bar to another bar or reset it. Position is never copied.", 16, -18, width)
    local y = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    local bars = {}
    for i = 1, COUNT do bars[i] = { value = i, text = Tr(Suite.ActionBarTitles[i]) } end
    M.BindDropdownAt(ctx, body, Tr("Copy to bar"), 16, y, bars, half,
        function() return copyTarget end, function(value) copyTarget = tonumber(value) or 1; P.Refresh() end,
        P.Meta(PAGE, ID, "editor.copyTarget", "ephemeral", section))
    local scopes = { { value = "all", text = Tr("Everything except position") }, { value = "layout", text = Tr("Layout") },
        { value = "visibility", text = Tr("Visibility") }, { value = "appearance", text = Tr("Text and background") } }
    M.BindDropdownAt(ctx, body, Tr("Settings to copy"), 28 + half, y, scopes, half,
        function() return copyScope end, function(value) copyScope = value or "all" end,
        P.Meta(PAGE, ID, "editor.copyScope", "ephemeral", section))
    y = y - 62
    P.Button(ctx, body, "Copy settings", 16, y, half, function() CopyBar(selected, copyTarget, copyScope) end,
        function() return copyTarget ~= selected and S.Availability(ID) and true or false end,
        P.Meta(PAGE, ID, "editor.copy", "action", section))
    P.Button(ctx, body, "Reset selected bar", 28 + half, y, half, function() ResetBar(selected) end,
        function() return S.Availability(ID) and true or false end,
        P.Meta(PAGE, ID, "editor.reset", "action", section))
    P.FinishBody(b, body, y - 38)
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

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Key bindings", function() if S.OpenQuickKeybind then S.OpenQuickKeybind() end end,
          function() return S.OpenQuickKeybind ~= nil end, key = "bindings" },
        { "Move on screen", function() P.MoveOnScreen(ID, "bar1") end, nil, key = "move" },
        { "Reload UI", function() if ReloadUI then ReloadUI() end end,
          function() return S.states[ID] and S.states[ID].reloadRequired ~= nil end, key = "reload" },
        { "Reset module", function()
            P.WithHistory("Reset action bars", "suite:actionbars.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    P.RuleSection(ctx, b, PAGE, ID, "suite_actionbars_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = "Choose the shared button colors and frame. Layout, bindings and visibility stay as set. Changing an individual color switches the label to Custom.",
            extra = function(body, y, width)
                local gap = 8
                local buttonWidth = math.floor((width - 2 * gap) / 3)
                for index, name in ipairs({ "Midnight Blue", "Midnight Dark", "MSUF Forever" }) do
                    local button = T.Button(body, Tr(name), buttonWidth, 26)
                    button:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + (index - 1) * (buttonWidth + gap), y)
                    button:SetScript("OnClick", function()
                        if not P.Combat() then P.Set(ID, "look", index) end
                    end)
                    if M.RegisterControlMetadata then
                        M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "look." .. index, "action", "suite_actionbars_look"),
                            Tr(name), "button")
                    end
                    M.TrackRefresh(ctx, function()
                        button:SetAlpha(P.Get(ID, "look") == index and 1 or 0.65)
                        button:SetEnabled(P.RuleEnabled(ID, P.catalog[ID].rules.look))
                    end)
                end
                return y - 38
            end,
        })
    BuildQuick(ctx, b)
    BuildEditor(ctx, b)
    local templates = P.SectionRules(ID, "bar1")
    for _, group in ipairs(GROUPS) do
        local rules = {}
        for _, rule in ipairs(templates) do
            if GroupOf(rule.key:sub(5)) == group.id then rules[#rules + 1] = rule end
        end
        P.RuleSection(ctx, b, PAGE, ID, "suite_actionbars_bar_" .. group.id, Tr(group.title), rules,
            { keyFn = BarKey, open = false,
              help = group.id == "visibility" and "The quick switch above remembers this mode when you turn the bar off. Choose Never to keep it hidden." or nil })
    end
    BuildTools(ctx, b)
    for _, section in ipairs({ "appearance", "cooldowns", "text", "behavior" }) do
        local rules = P.SectionRules(ID, section)
        P.RuleSection(ctx, b, PAGE, ID, "suite_actionbars_" .. section, Tr(rules[1].sectionTitle), rules,
            { help = HELP[section], open = false })
    end
end

P.RegisterPage({ key = PAGE, label = "Action bars", title = "Action bars", build = Build, icon = { 2, 2 },
    aliases = { "actionbars", "action_bars", "bars_suite" } })
