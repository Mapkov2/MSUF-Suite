local _, P = ...
local Suite, S, M, W, T, Tr, HM = P.Suite, P.S, P.M, P.W, P.T, P.Tr, P.HM
local PAGE, ID = "suite_damageMeter", "damageMeter"

local HELP = {
    general = P.Help("Windows update from the client's own combat data: every event outside combat, and at the chosen interval during combat.",
        "Report in a window's Settings menu sends its ranking to chat once combat is over."),
    bars = "Bar colors follow the class unless you turn class colors off. The gradient can shade several edges at once; choose its color from the three dots and its strength below.",
    text = P.Help("Choose the values shown on each bar.", "Choose Custom layout to set the order of total, per-second and percent values, then pick spaces, brackets or a separator. The percent switch controls main rows; breakdown rows show available shares. Unavailable shares are omitted. Primary means per second for DPS/HPS and total for other meters. Text settings also apply to headers, details and the floating timer. Slug uses WoW's crisp font renderer with an outline and no shadow. Protected values show without a percentage until combat ends."),
    window = "The header shows the meter and fight. Its buttons change the meter and fight directly in the window.",
    details = "Click a bar to open the spell breakdown in the window; hover it for a short tooltip.",
    timer = "Turn off Show combat time to hide both the duration in every meter header and the separate floating timer. The two switches below let you show either one independently.",
    surfaces = "Textures use the window and header colors and opacity. Turn the texture switch off to return to a flat color.",
    borders = P.Help("Choose a style, then adjust its thickness in Bars or Window and header.",
        "Distance moves the border outward. Turn individual edges on or off."),
    iconBorder = "Enable Separate icon border in Bars. Independent settings override the row border. Material icon skins keep their own frame.",
    separators = "Static lines separate rows, icons and the header. Increase Bar spacing for more room between rows.",
    timerDock = P.Help("Free position uses the screen coordinates in Combat timer and Move on screen.",
        "Docked timers follow the selected window and hide with it. Positive horizontal offsets move right; positive vertical offsets move up."),
    namesFont = P.Help("Separate font settings override the shared font and text style. Turn the switch off to inherit them again.",
        "Text sizes stay in their usual sections and preview controls."),
    window_settings = "Each window keeps its own meter, fight, size and visibility rules. Drag the header or use MSUF Edit Mode to move it.",
}

-- The window settings that choose a fight: a threat window has none.
local FIGHT_KEYS = { Session = true, SyncSession = true }

-- The selected window is shared by the window controls below; their rules use
-- window 1's keys as templates and resolve to the selected window at runtime.
local selected = 1
-- Exact navigation follows the explicit picker, including retained windows
-- above windowCount. Their controls keep the existing disabled-state hint.
P.SearchPreparers[ID] = function() return selected end
local function WindowKey(key)
    local suffix = key:match("^w%d+(.+)$")
    return suffix and ("w" .. selected .. suffix) or key
end

local function IconSkinStatus(ctx, body, y, width)
    return y - Suite.HostBridge.IconSkinStatusRow(M, ctx, body, 16, y, width, P.IconSkinKey(ID))
end

local gradientKeys = { "gradientDirLeft", "gradientDirRight", "gradientDirUp", "gradientDirDown" }
local function BuildGradientPad(ctx, body, y, width)
    local sectionId = "suite_damageMeter_bars"
    P.Text(body, "Gradient direction", 16, y - 3, width)
    local pad = T.Panel(body, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y - 24)
    pad:SetSize(104, 78)
    local center = pad:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER", pad, "CENTER", 0, 0)
    center:SetSize(10, 10)
    local centerColor = T.colors.coreRim or { 0.043, 0.096, 0.150 }
    center:SetColorTexture(centerColor[1], centerColor[2], centerColor[3], 0.95)
    local directions = {
        { "^", gradientKeys[3], 41, -7 },
        { "<", gradientKeys[1], 18, -30 },
        { ">", gradientKeys[2], 64, -30 },
        { "v", gradientKeys[4], 41, -53 },
    }
    local buttons = {}
    for _, direction in ipairs(directions) do
        local text, key, x, buttonY = direction[1], direction[2], direction[3], direction[4]
        local button = T.Button(pad, text, 22, 18)
        button:SetPoint("TOPLEFT", pad, "TOPLEFT", x, buttonY)
        if T.CenterButtonLabel then T.CenterButtonLabel(button) end
        button:SetScript("OnClick", function()
            if not P.RuleEnabled(ID, P.catalog[ID].rules[key]) then return end
            local active = P.Get(ID, key) == true
            if active then
                local others = false
                for _, other in ipairs(gradientKeys) do
                    if other ~= key and P.Get(ID, other) then
                        others = true
                        break
                    end
                end
                if not others then return end
            end
            P.Set(ID, key, not active)
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, key, "setting", sectionId),
                P.catalog[ID].rules[key].label, "button")
        end
        buttons[key] = button
    end
    P.Text(body, "Select one or more edges. At least one direction stays active.", 136, y - 30, math.max(100, width - 120))
    M.TrackRefresh(ctx, function()
        local enabled = P.RuleEnabled(ID, P.catalog[ID].rules.gradientDirRight)
        pad:SetAlpha(enabled and 1 or 0.45)
        for _, key in ipairs(gradientKeys) do
            local button = buttons[key]
            button:SetActive(P.Get(ID, key) == true)
            W.SetControlEnabled(button, enabled)
        end
    end)
    return y - 114
end

-- The window picker, help and window-1 template rules resolved to the selected window.
local function WindowControls(ctx, b, body, templates, built)
    local width = math.max(240, (HM.GetSectionWidth(body) or b.width or 720) - 32)
    local help = P.Text(body, HELP.window_settings, 16, -18, width)
    local y = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    local picker = ctx.meterWindowPicker
    if not picker then
        local choices = {}
        for i = 1, Suite.DamageMeterMaxWindows do choices[i] = { value = i, text = Tr("Window %d"):format(i) } end
        picker = M.BindDropdownAt(ctx, body, Tr("Window"), 16, y, choices, math.floor(width / 2),
            function() return selected end, function(value) selected = tonumber(value) or 1
                P.Refresh() end,
            P.Meta(PAGE, ID, "window.selected", "ephemeral", "suite_damageMeter_windows"))
    end
    local note = P.Text(body, "", 28 + math.floor(width / 2), y - 24, math.floor(width / 2) - 12)
    y = y - 62
    local entries
    y, entries = P.RuleGrid(ctx, body, PAGE, ID, templates, y, width, WindowKey, "suite_damageMeter_windows", nil, built)
    P.MenuWorkspace.Prepare(body, entries)
    P.AttachRuleColors(body, "Window settings", ID, templates, WindowKey)
    return y, picker, note
end

-- Window settings: one pane whose controls follow the selected window. A
-- lazy host builds its controls when it first opens (P.LazySection).
local function BuildWindows(ctx, b)
    local templates = P.SectionRules(ID, "w1")
    local built = P.RuleRows(PAGE, ID, templates, WindowKey, "suite_damageMeter_windows")
    local picker, note
    P.LazySection(b, "suite_damageMeter_windows", Tr("Window settings"), true, {
        content = function(body)
            local y
            y, picker, note = WindowControls(ctx, b, body, templates, built)
            return y
        end,
        summary = function(body) P.AttachRowsSummary(ctx, body, built.rows) end,
        shell = function(body)
            P.AttachSectionReset(ctx, body, "Window settings", function()
                return P.ResetPrefix(ID, "w" .. selected)
            end)
        end,
        finish = function(body, y)
            local width = math.max(240, (HM.GetSectionWidth(body) or b.width or 720) - 32)
            P.Button(ctx, body, "Move this window", 16, y - 4, math.floor((width - 12) / 2),
                function() P.MoveOnScreen(ID, "window" .. selected) end,
                function() return P.Get(ID, "enabled") and selected <= P.Get(ID, "windowCount") end,
                P.Meta(PAGE, ID, "window.move", "action", "suite_damageMeter_windows"))
            M.TrackRefresh(ctx, function()
                local count = P.Get(ID, "windowCount")
                P.SetTranslatedText(note, selected > count
                    and string.format(Tr("Shown windows: %d. Raise the number of windows to show this one."), count) or "")
                if picker.SetValue then picker:SetValue(selected) end
            end)
            P.FinishBody(b, body, y - 40)
        end,
    })
end

local function Build(ctx)
    local b, ui = P.MenuWorkspace.Builder(ctx, { page = PAGE, module = ID, title = "Damage meter", height = 264,
        tabs = {
            { id = "shared", label = "General settings", sections = "damageMeter_module look general details" },
            { id = "appearance", label = "Appearance", sections = "bars window surfaces borders iconBorder separators" },
            { id = "text", label = "Text", sections = "text namesFont valuesFont headerFont detailsFont timerFont" },
            { id = "timer", label = "Combat timer", sections = "timer timerDock" },
            { id = "window", label = "Window settings", sections = "windows" },
        } })
    P.MenuSamples.Meter(ui, function() return selected end, function(value) selected = value
                P.Refresh() end)
    -- S.DamageMeterReset comes with the damage meter addon.
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Reset combat data", function() if S.DamageMeterReset then S.DamageMeterReset() end end,
          function() return S.DamageMeterReset ~= nil and P.Get(ID, "enabled") end, key = "reset_data" },
        { "Move on screen", function() P.MoveOnScreen(ID, "window1") end, nil, key = "move" },
    })
    P.MenuWorkspace.Rules(ctx, b, PAGE, ID, "suite_damageMeter_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = "Clean Modern uses matte panels with white accents. Midnight Blue keeps the original blue palette. Midnight Dark uses neutral charcoal glass; MSUF Forever retains its muted gold. Color changes become Custom.",
            extra = P.LookPresetButtons(ctx, PAGE, ID, "suite_damageMeter_look"),
        })
    for _, section in ipairs({ "general", "bars", "text", "window", "details", "timer", "surfaces", "borders", "iconBorder",
        "separators", "namesFont", "valuesFont", "headerFont", "detailsFont", "timerFont", "timerDock" }) do
        local rules = P.SectionRules(ID, section)
        if #rules > 0 then
            P.MenuWorkspace.Rules(ctx, b, PAGE, ID, "suite_damageMeter_" .. section, Tr(rules[1].sectionTitle), rules,
                { help = HELP[section] or section:find("Font", 1, true) and HELP.namesFont, open = section == "general",
                  extra = section == "bars" and function(body, y, width)
                      return IconSkinStatus(ctx, body, BuildGradientPad(ctx, body, y, width), width)
                  end or nil })
        end
    end
    BuildWindows(ctx, b)
    -- Windows above the configured count keep their settings but stay hidden.
    P.Gates[ID] = function(rule, key)
        if rule.key == "glossEnabled" or rule.key == "glossStrength" then
            return Suite.GlossMaterial.Available(), "This look requires MSUF 7.0."
        end
        if rule.key == "nameEllipsis" then return P.Get(ID, "nameMaxChars") > 0 end
        if rule.key == "shadowOpacity" or rule.key == "shadowDistance" then
            return P.Get(ID, "rendering") ~= P.Suite.FontRendering.SLUG
        end
        if key == "timerWindow" or key == "timerDockX" or key == "timerDockY" then
            return P.Get(ID, "timerAnchor") ~= 1
        end
        if key == "timerX" or key == "timerY" then return P.Get(ID, "timerAnchor") == 1 end
        if key:match("^iconBorder") and key ~= "iconBorder" then return P.Get(ID, "iconBorder") end
        local index = tonumber(key:match("^w(%d+)"))
        if not index then return true end
        if index > P.Get(ID, "windowCount") then return false end
        -- Only WoW Forever has a threat meter.
        local threat = Suite.DamageMeterThreatType
        if threat and FIGHT_KEYS[key:match("^w%d+(.+)$")] and P.Get(ID, "w" .. index .. "Type") == threat + 1 then
            return false, "Threat windows do not use fights."
        end
        return true
    end
    P.MenuWorkspace.Finish(ui)
end

P.RegisterPage({ key = PAGE, label = "Damage meter", title = "Damage meter", build = Build, icon = { 7, 0 },
    nav = "interface", navOrder = 3,
    aliases = { "damage_meter", "damagemeter", "meter", "dps", "details", "skada", "recount" } })
