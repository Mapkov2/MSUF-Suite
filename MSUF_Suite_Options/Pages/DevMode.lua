local _, P = ...
local Dev, M, Tr = P.Suite.DevMode, P.M, P.Tr
local Animation = P.Suite.DevBarAnimation
local PAGE, TITLE = "suite_devMode", "Dev Mode"
local LOG_SECTION, FORCE_SECTION = PAGE .. "_logging", PAGE .. "_restrictions"
local TAINT = "taintLog"

local function Help(body, text, width)
    local description = P.Description(body, text, 16, -40, width)
    return -54 - math.ceil(description:GetStringHeight())
end

local function TaintLevel(ctx, body, width, y, current)
    local choices = {
        { value = "0", text = Tr("Off") },
        { value = "1", text = Tr("Basic") },
        { value = "2", text = Tr("Verbose") },
    }
    if current ~= "0" and current ~= "1" and current ~= "2" then
        choices[#choices + 1] = { value = current, text = current }
    end
    M.BindDropdownAt(ctx, body, Tr("Taint logging"), 16, y, choices, width,
        function() return Dev.Read(TAINT) end,
        function(value) Dev.Report(Dev.Set(TAINT, value)) end,
        P.Meta(PAGE, "devMode", TAINT, "ephemeral", LOG_SECTION))
    return y - 62
end

local function BuildLogging(ctx, builder)
    local body = builder:Section(Tr("Taint logging"), 120)
    local width = math.max(208, (P.HM.GetSectionWidth(body) or builder.width or 720) - 64)
    local y = Help(body,
        "Blizzard writes to Logs/taint.log in the current client folder. Reload the UI before reproducing an issue to capture its first taint entries.",
        width)
    local current = Dev.Read(TAINT)
    if current then
        y = TaintLevel(ctx, body, width, y, current)
    else
        local unavailable = P.Text(body, "Taint logging is unavailable on this client.", 16, y, width)
        y = y - 10 - math.ceil(unavailable:GetStringHeight())
    end
    local report = Dev.GetTaintReport()
    if report then
        local button = P.Button(ctx, body, "Taint Report", 16, y, width, report.Show, nil,
            P.Meta(PAGE, "devMode", "taintReport", "ephemeral", LOG_SECTION))
        y = y - button:GetHeight() - 12
    end
    P.FinishBody(builder, body, y)
end

local function RestrictionSwitch(ctx, body, entry, width, y)
    local key = entry.key
    M.BindSwitchAt(ctx, body, Tr(entry.label), 16, y, width,
        function() return Dev.Read(key) == "1" end,
        function(value) Dev.Report(Dev.Set(key, value and "1" or "0")) end,
        P.Meta(PAGE, "devMode", key, "ephemeral", FORCE_SECTION))
end

local function BuildRestrictions(ctx, builder)
    local body = builder:Section(Tr("Forced addon restrictions"), 120)
    local width = math.max(208, (P.HM.GetSectionWidth(body) or builder.width or 720) - 64)
    local y = Help(body,
        "Simulate Blizzard's restricted states for testing secret values. Simulated combat can close this menu. Use /msufdev off to stop all diagnostics.",
        width)
    local supported = false
    for _, entry in ipairs(Dev.restrictions) do
        if Dev.Read(entry.key) then
            supported = true
            RestrictionSwitch(ctx, body, entry, width, y)
            y = y - 36
        end
    end
    if supported then
        local force = P.Button(ctx, body, "Force all addon restrictions", 16, y, width,
            function() Dev.Report(Dev.SetAll(true)) end, nil,
            P.Meta(PAGE, "devMode", "force", "ephemeral", FORCE_SECTION), { wrap = true })
        y = y - force:GetHeight() - 12
    end
    local stop = P.Button(ctx, body, "Turn off all diagnostics", 16, y, width,
        function() Dev.Report(Dev.SetAll(false)) end, nil,
        P.Meta(PAGE, "devMode", "stop", "ephemeral", FORCE_SECTION), { wrap = true })
    P.FinishBody(builder, body, y - stop:GetHeight() - 12)
end

local barKind, oneAtATime = "all", false
local BAR_SECTION = PAGE .. "_bars"

local function StartBars()
    local ok, reason = Animation.Start(barKind, oneAtATime)
    if reason == "preview" then
        P.Suite.Print(Tr("Close Edit Mode before animating live bars."))
    else
        Dev.Report(ok, reason)
    end
end

local function BuildBarAnimation(ctx, builder)
    local body = builder:Section(Tr("Live bar animation"), 120)
    local width = math.max(208, (P.HM.GetSectionWidth(body) or builder.width or 720) - 64)
    local y = Help(body, "Animates visible MSUF bars outside combat. The test stops when combat starts.", width)
    local choices = {
        { value = "all", text = Tr("All bars") },
        { value = "health", text = Tr("Health bars") },
        { value = "power", text = Tr("Power Bars") },
        { value = "class", text = Tr("Class Resources") },
        { value = "cast", text = Tr("Castbars") },
    }
    if P.Suite.Client.isForever then
        choices[#choices + 1] = { value = "swing", text = Tr("Swing Timers") }
    end
    M.BindDropdownAt(ctx, body, Tr("Bars to animate"), 16, y, choices, width,
        function() return barKind end,
        function(value)
            barKind = value
            if Animation.IsRunning() then StartBars() end
        end,
        P.Meta(PAGE, "devMode", "barKind", "ephemeral", BAR_SECTION))
    y = y - 62
    M.BindSwitchAt(ctx, body, Tr("One bar at a time"), 16, y, width,
        function() return oneAtATime end,
        function(value)
            oneAtATime = value == true
            if Animation.IsRunning() then StartBars() end
        end,
        P.Meta(PAGE, "devMode", "barSequence", "ephemeral", BAR_SECTION))
    y = y - 36
    M.BindSwitchAt(ctx, body, Tr("Animate bar text"), 16, y, width,
        Animation.IsTextEnabled, Animation.SetTextEnabled,
        P.Meta(PAGE, "devMode", "barTextAnimation", "ephemeral", BAR_SECTION))
    y = y - 36
    M.BindSwitchAt(ctx, body, Tr("Animate live bars"), 16, y, width,
        Animation.IsRunning,
        function(value)
            if value then StartBars() else Animation.Stop() end
        end,
        P.Meta(PAGE, "devMode", "barAnimation", "ephemeral", BAR_SECTION))
    P.FinishBody(builder, body, y - 36)
end

local function Build(ctx)
    if ctx.searchRows then return end
    local builder = P.W.PageBuilder(ctx)
    BuildLogging(ctx, builder)
    BuildRestrictions(ctx, builder)
    BuildBarAnimation(ctx, builder)
end

P.RegisterPage({ key = PAGE, label = TITLE, title = TITLE, build = Build, reset = false,
    icon = { 4, 2 }, nav = "general", navOrder = 4,
    aliases = { "dev mode", "developer mode", "taint", "taintlog", "secret values", "entwicklermodus" } })
