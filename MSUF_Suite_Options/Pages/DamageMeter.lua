local _, P = ...
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local PAGE, ID = "suite_damageMeter", "damageMeter"

local HELP = {
    general = "Windows update from the client's own combat data: every event outside combat, and at the chosen interval during combat.",
    bars = "Bar colors follow the class unless you turn class colors off. The gradient can shade several edges at once; choose its color from the three dots and its strength below.",
    text = "Choose Custom layout to set the order of total, per-second and percent values, then pick spaces, brackets or a separator. The percent switch controls main rows; breakdown rows show available shares. Unavailable shares are omitted. Primary means per second for DPS/HPS and total for other meters. Text settings also apply to headers, details and the floating timer. Slug uses WoW's crisp font renderer with an outline and no shadow. Protected values show without a percentage until combat ends.",
    window = "The header shows the meter and fight. Its buttons change the meter and fight directly in the window.",
    details = "Click a bar to open the spell breakdown in the window; hover it for a short tooltip.",
    timer = "Turn off Show combat time to hide both the duration in every meter header and the separate floating timer. The two switches below let you show either one independently.",
    window_settings = "Each window keeps its own meter, fight, size and visibility rules. Drag the header or use MSUF Edit Mode to move it.",
}

-- The selected window is shared by the window controls below; their rules use
-- window 1's keys as templates and resolve to the selected window at runtime.
local selected = 1
local function WindowKey(key)
    local suffix = key:match("^w%d+(.+)$")
    return suffix and ("w" .. selected .. suffix) or key
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
                    if other ~= key and P.Get(ID, other) then others = true; break end
                end
                if not others then return end
            end
            P.Set(ID, key, not active)
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, key, "setting", sectionId),
                Tr(P.catalog[ID].rules[key].label), "button")
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

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Reset combat data", function() if S.DamageMeterReset then S.DamageMeterReset() end end,
          function() return S.DamageMeterReset ~= nil and P.Get(ID, "enabled") end, key = "reset_data" },
        { "Move on screen", function() P.MoveOnScreen(ID, "window1") end, nil, key = "move" },
        { "Reset module", function()
            P.WithHistory("Reset damage meter", "suite:damageMeter.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    P.RuleSection(ctx, b, PAGE, ID, "suite_damageMeter_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = "Midnight Blue keeps the original blue palette. Midnight Dark uses neutral charcoal glass; MSUF Forever retains its muted gold. Color changes become Custom.",
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
                        M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "look." .. index, "action", "suite_damageMeter_look"),
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
    for _, section in ipairs({ "general", "bars", "text", "window", "details", "timer" }) do
        local rules = P.SectionRules(ID, section)
        if #rules > 0 then
            P.RuleSection(ctx, b, PAGE, ID, "suite_damageMeter_" .. section, Tr(rules[1].sectionTitle), rules,
                { help = HELP[section], open = section == "general",
                  extra = section == "bars" and function(body, y, width) return BuildGradientPad(ctx, body, y, width) end or nil })
        end
    end
    -- Window settings: one pane whose controls follow the selected window.
    local templates = P.SectionRules(ID, "w1")
    local body = b:CollapsibleSection("suite_damageMeter_windows", Tr("Window settings"), 120, true)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local help = P.Text(body, HELP.window_settings, 16, -18, width)
    local y = -18 - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    local choices = {}
    for i = 1, Suite.DamageMeterMaxWindows or 5 do choices[i] = { value = i, text = string.format(Tr("Window %d"), i) } end
    local picker = M.BindDropdownAt(ctx, body, Tr("Window"), 16, y, choices, math.floor(width / 2),
        function() return selected end,
        function(value) selected = tonumber(value) or 1; P.Refresh() end,
        P.Meta(PAGE, ID, "window.selected", "ephemeral", "suite_damageMeter_windows"))
    local note = P.Text(body, "", 28 + math.floor(width / 2), y - 24, math.floor(width / 2) - 12)
    y = y - 62
    y = P.RuleGrid(ctx, body, PAGE, ID, templates, y, width, WindowKey, "suite_damageMeter_windows")
    P.AttachRuleColors(body, "Window settings", ID, templates, WindowKey)
    P.Button(ctx, body, "Move this window", 16, y - 4, math.floor((width - 12) / 2),
        function() P.MoveOnScreen(ID, "window" .. selected) end,
        function() return P.Get(ID, "enabled") and selected <= P.Get(ID, "windowCount") end,
        P.Meta(PAGE, ID, "window.move", "action", "suite_damageMeter_windows"))
    y = y - 40
    -- Windows above the configured count keep their settings but stay hidden.
    P.Gates[ID] = function(rule, key)
        if rule.key == "nameEllipsis" then return P.Get(ID, "nameMaxChars") > 0 end
        if rule.key == "shadowOpacity" or rule.key == "shadowDistance" then
            return P.Get(ID, "rendering") ~= 3
        end
        local index = tonumber(key:match("^w(%d+)"))
        return not index or index <= P.Get(ID, "windowCount")
    end
    M.TrackRefresh(ctx, function()
        local count = P.Get(ID, "windowCount")
        note:SetText(selected > count and string.format(Tr("Shown windows: %d. Raise the number of windows to show this one."), count) or "")
        if picker.SetValue then picker:SetValue(selected) end
    end)
    P.FinishBody(b, body, y)
end

P.RegisterPage({ key = PAGE, label = "Damage meter", title = "Damage meter", build = Build, icon = { 7, 0 },
    aliases = { "damage_meter", "damagemeter", "meter", "dps" } })
